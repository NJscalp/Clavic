//
//  GenerationManager.swift
//  Clavic
//
//  Steuert den Lebenszyklus einer Generierung: Task einreichen,
//  Status pollen, fertiges Video herunterladen und Thumbnail erzeugen.
//

import Foundation
import SwiftData
import UIKit
import AVFoundation

@Observable
@MainActor
final class GenerationManager {
    /// IDs der Projekte, die gerade aktiv überwacht werden
    private(set) var activeProjectIDs: Set<UUID> = []
    /// Projekte mit einer aktuell laufenden Polling-Schleife (verhindert Doppel-Polling)
    private var liveMonitors: Set<UUID> = []
    /// Projekte, deren initialer Einreich-Aufruf gerade läuft (noch keine Task-ID)
    private var submitting: Set<UUID> = []
    /// Projekte, die eine ANSICHT gerade selbst faehrt.
    ///
    /// Der Director pollt seinen Render in der Ansicht, weil er danach noch
    /// die Qualitaetspruefung fahren und das Ergebnis im Gespraech zeigen
    /// muss. Sein Projekt liegt trotzdem ab der ersten Sekunde in der
    /// Datenbank — sonst waere es weg, wenn die App stirbt.
    ///
    /// Solange dieser Prozess lebt, darf der Manager nicht MIT pollen: zwei
    /// Schleifen auf derselben Aufgabe wuerden das Projekt doppelt abschliessen.
    /// Nach einem Neustart ist die Menge leer — dann uebernimmt er, und genau
    /// dafuer ist das Ganze da.
    private var externallyDriven: Set<UUID> = []

    private var modelContext: ModelContext?
    /// Für Credit-Rückerstattung bei Fehlern
    var store: Store?

    /// Hält die App nach dem Wechsel in den Hintergrund kurz am Leben,
    /// damit fast fertige Generierungen noch abgeschlossen werden können.
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func configure(context: ModelContext) {
        self.modelContext = context
    }

    /// Eine Ansicht uebernimmt das Pollen selbst — der Manager haelt nur die
    /// Hintergrundzeit offen und laesst die Finger vom Status.
    func claimExternal(_ id: UUID) {
        externallyDriven.insert(id)
        activeProjectIDs.insert(id)
    }

    /// Die Ansicht ist fertig (oder gescheitert).
    func releaseExternal(_ id: UUID) {
        externallyDriven.remove(id)
        activeProjectIDs.remove(id)
        endBackgroundTaskIfIdle()
    }

    // MARK: - App-Lebenszyklus

    /// Beim Wechsel in den Hintergrund: Extra-Laufzeit von iOS anfordern,
    /// solange noch Generierungen laufen. Die eigentliche Generierung läuft
    /// serverseitig weiter – so kann die App ein kurz danach fertiges Video
    /// noch herunterladen, statt das Polling sofort einzufrieren.
    func handleEnteredBackground() {
        guard !activeProjectIDs.isEmpty else { return }
        beginBackgroundTask()
    }

    /// Beim Zurückkehren in den Vordergrund: Hintergrund-Task beenden und
    /// alle noch laufenden Generierungen weiter überwachen.
    func handleBecameActive() {
        endBackgroundTask()
        resumePendingProjects()
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "VideoGeneration") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Beendet die Hintergrund-Laufzeit, sobald keine Generierung mehr läuft.
    private func endBackgroundTaskIfIdle() {
        if activeProjectIDs.isEmpty { endBackgroundTask() }
    }

    /// Setzt nach einem App-Neustart oder bei Rückkehr in den Vordergrund die
    /// Überwachung laufender Tasks fort. Mehrfaches Aufrufen ist sicher –
    /// `monitor` verhindert doppelte Polling-Schleifen.
    func resumePendingProjects() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<VideoProject>()
        guard let projects = try? modelContext.fetch(descriptor) else { return }

        for project in projects where project.status.isActive {
            // Faehrt eine Ansicht das Projekt in DIESEM Prozess selbst, nicht
            // dazwischenfunken. Nach einem Neustart ist die Menge leer.
            if externallyDriven.contains(project.id) { continue }
            if project.taskID != nil {
                monitor(project: project)
            } else {
                // Unterbrochene Generierung (z. B. lange Pipeline + App-Kill, kein
                // taskID): wenn schon Szenen im Checkpoint liegen → wiederaufnehmbar
                // (Credits bleiben, Continue setzt fort); sonst Refund über fail().
                if !liveMonitors.contains(project.id) && !submitting.contains(project.id) {
                    failOrResumable(project: project, message: "The generation was interrupted.")
                }
            }
        }
    }

    // MARK: - Generierung starten

    func submit(project: VideoProject) {
        guard let modelContext else { return }
        project.progressStage = "Starting…"
        modelContext.insert(project)
        try? modelContext.save()

        // Bester Moment für die Notification-Erlaubnis: der Nutzer wartet
        // gerade auf genau das Ergebnis, das wir ihm später melden wollen.
        Notifier.requestAuthorizationIfNeeded()

        activeProjectIDs.insert(project.id)
        // Markiert das Projekt als "wird eingereicht", damit ein zwischenzeitlicher
        // Rückkehr-Trigger es nicht fälschlich als unterbrochen markiert.
        submitting.insert(project.id)

        Task {
            defer { submitting.remove(project.id) }
            do {
                // Fotos vor jedem API-Call verkleinern (Vercel-Limit ~4,5 MB → 413).
                let uploadImages = Self.compressForUpload(project.referenceImagesData, video: !project.isImageOutput)

                // Musikvideo-Template: eigene mehrstufige Pipeline (Segmente +
                // Lip-Sync + lokales Zusammenfügen), kein Task-ID-Polling.
                if project.useMusicLipSync {
                    try await runMusicLipSync(project: project, uploadImages: uploadImages)
                    return
                }

                var taskID: String
                if let kind = project.upscaleKind {
                    guard let fileData = uploadImages.first else {
                        throw SeedanceError.invalidResponse
                    }
                    taskID = try await UpscaleAPI.createTask(type: kind, fileData: fileData)
                } else if project.isImageOutput {
                    let request = ImageEditRequest(
                        prompt: project.prompt,
                        referenceImages: uploadImages,
                        quality: project.imageQuality,
                        aspectRatio: project.ratio.rawValue,
                        model: ImageEditAPI.defaultModel
                    )
                    taskID = try await ImageEditAPI.createTask(request)
                } else {
                    // Optionaler Vor-Edit (Nano Banana 2): Hintergrund/Person im
                    // Foto ändern, BEVOR das Video-/Motion-Modell läuft. Ersetzt
                    // die Steuer-Prompts, die Kling Motion Control nicht kennt.
                    var videoImages = uploadImages
                    if !project.preEditPrompt.isEmpty, let photo = videoImages.first {
                        project.progressStage = "Updating your photo…"
                        try? modelContext.save()
                        if let edited = try? await Self.preEditPhoto(photo, instruction: project.preEditPrompt) {
                            videoImages[0] = edited
                        }
                    }
                    let request = SeedanceRequest(
                        prompt: project.prompt,
                        referenceImages: videoImages,
                        ratio: project.ratio,
                        resolution: project.resolution,
                        duration: project.duration,
                        generateAudio: project.generateAudio,
                        useFastModel: project.useFastModel,
                        referenceVideoURLs: project.referenceVideoURLs,
                        referenceVideosData: project.referenceVideosData,
                        kling: project.useKlingMotion,
                        model: project.seedanceModel.isEmpty ? nil : project.seedanceModel
                    )
                    // Alle Video-Modelle laufen über WaveSpeed (Seedance i2v bzw.
                    // Kling Motion Control bei Referenz-Video).
                    taskID = try await KieSeedanceAPI.createTask(request)
                }
                project.taskID = taskID
                project.status = .running
                try? modelContext.save()
                monitor(project: project)
            } catch {
                fail(project: project, message: error.localizedDescription)
            }
        }
    }

    // MARK: - Musikvideo-Pipeline

    /// Führt die mehrstufige Musikvideo-Pipeline aus und speichert das fertige
    /// Video lokal. Fehler werden wie bei normalen Generierungen behandelt.
    private func runMusicLipSync(project: VideoProject, uploadImages: [Data]) async throws {
        project.status = .running
        try? modelContext?.save()

        guard let photo = uploadImages.first else {
            fail(project: project, message: "No photo provided.")
            return
        }

        // Live-Fortschritt: Pipeline-Stufen direkt ins Projekt schreiben (Main).
        let onStage: (String) -> Void = { [weak project] s in
            Task { @MainActor in project?.progressStage = s }
        }

        do {
            let localURL: URL
            // AI Fruit Story: eigene Pipeline (Claude-Planner → Nano Banana 2
            // Keyframes → Veo 3.1 sprechende Clips → Merge). Die Konfiguration
            // (Preset, Cast, Stil, Szenenzahl) liegt als JSON in `prompt`, die
            // Charakter-Referenzbilder in `referenceImagesData`.
            if project.musicVideoKey == "fruit" {
                let config = try JSONDecoder().decode(
                    FruitStoryPipeline.Config.self, from: Data(project.prompt.utf8))
                localURL = try await FruitStoryPipeline.run(
                    config: config,
                    characterImages: uploadImages,
                    resolution: project.resolution.rawValue,
                    projectID: project.id,
                    onStage: onStage)
            } else if project.musicVideoKey.hasPrefix("build") {
                let imgs = uploadImages
                let personalized = project.musicVideoKey == "build_personal"
                let restyle = project.musicVideoKey == "build_custom"
                // Fallback-Charakter (Tung Tung), falls keiner mitgegeben wurde.
                let tung = UIImage(named: "tung_character")?.jpegData(compressionQuality: 0.9)
                let characterImage: Data
                let userPhoto: Data?
                if personalized {
                    userPhoto = imgs.first
                    characterImage = (imgs.count > 1 ? imgs[1] : tung) ?? photo
                } else {
                    userPhoto = nil
                    characterImage = imgs.first ?? tung ?? photo
                }
                localURL = try await BrainrotBuildPipeline.run(
                    personalized: personalized,
                    characterImage: characterImage,
                    userPhoto: userPhoto,
                    restyleCharacter: restyle,
                    resolution: project.resolution.rawValue,
                    projectID: project.id,
                    onStage: onStage)
            } else if project.musicVideoKey == "brainrot_talk" {
                // Brainrot-Charakter reden lassen: (optionaler Bild-Edit →) Seedance-
                // Talk-Video → ElevenLabs-TTS → kie Lip-Sync (Fallback: Audio-Merge).
                // Charakter-Bild liegt in referenceImagesData[0], Text/Voice in
                // talkText/talkVoice, optionaler Bild-Änderungs-Prompt in prompt.
                let charImg = uploadImages.first ?? photo
                localURL = try await TalkingPipeline.run(
                    imageEdit: project.prompt,
                    charImageJPEG: charImg,
                    speech: project.talkText,
                    voice: project.talkVoice,
                    resolution: project.resolution.rawValue,
                    onStage: onStage)
            } else {
                let extras = Array(uploadImages.dropFirst())
                localURL = try await MusicVideoPipeline.run(
                    key: project.musicVideoKey,
                    prompt: project.prompt,
                    photoJPEG: photo,
                    extraPhotos: extras,
                    resolution: project.resolution.rawValue,
                    onStage: onStage)
            }
            Checkpoint.clear(project.id)   // Erfolg → Zwischenstände aufräumen
            await finalizeLocal(project: project, localURL: localURL)
        } catch {
            failOrResumable(project: project, message: error.localizedDescription)
        }
    }

    /// Fehlschlag bei einer mehrstufigen Pipeline: gibt es schon fertige Szenen
    /// im Checkpoint, wird das Projekt als WIEDERAUFNEHMBAR markiert (Credits
    /// bleiben, kein Doppelt-Erzeugen beim „Continue"). Sonst normaler Refund.
    private func failOrResumable(project: VideoProject, message: String) {
        let pipeline = project.musicVideoKey == "fruit" || project.musicVideoKey.hasPrefix("build")
        if pipeline && Checkpoint.hasAnySegment(project.id) {
            project.status = .failed
            project.errorMessage = "Paused — tap Continue to finish from where it stopped."
            project.resumable = true
            project.progressStage = ""
            activeProjectIDs.remove(project.id)
            endBackgroundTaskIfIdle()
            try? modelContext?.save()
        } else {
            fail(project: project, message: message)
        }
    }

    /// Nimmt eine pausierte Pipeline-Generierung wieder auf – nutzt die bereits
    /// erzeugten Szenen aus dem Checkpoint, erzeugt nur die fehlenden weiter.
    /// KEINE erneute Credit-Abbuchung (wurde beim ersten Start bezahlt).
    func resume(project: VideoProject) {
        guard project.resumable else { return }
        project.resumable = false
        project.errorMessage = nil
        project.status = .queued
        project.progressStage = "Resuming…"
        activeProjectIDs.insert(project.id)
        submitting.insert(project.id)
        try? modelContext?.save()
        Task {
            defer { submitting.remove(project.id) }
            let uploadImages = Self.compressForUpload(project.referenceImagesData, video: true)
            try? await runMusicLipSync(project: project, uploadImages: uploadImages)
        }
    }

    /// Übernimmt eine bereits lokal erzeugte Videodatei in den Documents-Ordner
    /// und erstellt ein Thumbnail (Pendant zu `finalize` für Remote-URLs).
    private func finalizeLocal(project: VideoProject, localURL: URL) async {
        defer {
            activeProjectIDs.remove(project.id)
            endBackgroundTaskIfIdle()
            try? modelContext?.save()
        }
        let filename = "\(project.id.uuidString).mp4"
        let destination = URL.documentsDirectory.appending(path: filename)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: localURL, to: destination)
            project.localVideoFilename = filename
            project.thumbnailData = await Self.generateThumbnail(for: destination)
        } catch {
            // Datei bleibt ggf. im temporären Ordner; Status trotzdem auf erfolgreich,
            // falls die Datei lesbar ist – sonst als Fehler markieren.
            project.status = .failed
            project.errorMessage = "Could not save the finished video."
            return
        }
        project.status = .succeeded
        notifyFinished(project, success: true)
    }

    // MARK: - Polling

    private func monitor(project: VideoProject) {
        // Verhindert eine zweite Polling-Schleife für dasselbe Projekt.
        guard !liveMonitors.contains(project.id) else { return }
        liveMonitors.insert(project.id)
        activeProjectIDs.insert(project.id)

        Task {
            defer { liveMonitors.remove(project.id) }

            guard var taskID = project.taskID else {
                fail(project: project, message: "No task ID available.")
                return
            }

            var consecutiveErrors = 0
            var upscaleRetries = 0
            let startTime = Date()
            // Harter Gesamt-Timeout: hängt der Backend-Task endlos in „running"
            // (kein failed/succeeded), bricht die Schleife sonst NIE ab und die
            // Credits würden nie erstattet. Nach dem Limit → fail() (= Refund).
            let maxSeconds: TimeInterval = project.upscaleKind != nil ? 1500 : 900

            while true {
                try? await Task.sleep(for: .seconds(5))

                if Date().timeIntervalSince(startTime) > maxSeconds {
                    fail(project: project,
                         message: "The generation timed out. Your credits were refunded — please try again.")
                    return
                }

                do {
                    let status: GenerationStatus
                    let resultURL: String?
                    let failureReason: String?
                    if let kind = project.upscaleKind {
                        let state = try await UpscaleAPI.fetchTask(id: taskID, type: kind)
                        status = state.status
                        resultURL = state.videoURL
                        failureReason = state.failureReason
                    } else if project.isImageOutput {
                        let state = try await ImageEditAPI.fetchTask(id: taskID)
                        status = state.status
                        resultURL = state.imageURL
                        failureReason = state.failureReason
                    } else {
                        // Video-Status immer über kie (Seedance 2.0), kein fal.
                        let state = try await KieSeedanceAPI.fetchTask(id: taskID)
                        status = state.status
                        resultURL = state.videoURL
                        failureReason = state.failureReason
                    }
                    consecutiveErrors = 0

                    switch status {
                    case .queued, .running:
                        // Live-Status mit laufendem mm:ss-Zähler → der Nutzer sieht,
                        // dass etwas passiert (statt statischem „1–2 min").
                        let e = Int(Date().timeIntervalSince(startTime))
                        let clock = String(format: "%d:%02d", e / 60, e % 60)
                        let base = status == .queued
                            ? "Waiting in line…"
                            : (project.isImageOutput ? "Creating your image…" : "Generating your video…")
                        project.progressStage = "\(base)  \(clock)"
                        if project.status != status {
                            project.status = status
                            try? modelContext?.save()
                        }
                    case .succeeded:
                        project.remoteVideoURL = resultURL
                        await finalize(project: project)
                        return
                    case .failed, .cancelled:
                        // Transient kie-Fehler („internal error, please try again
                        // later") beim Upscaler: bis zu 3× neu einreichen und
                        // weiterpollen — kie's Topaz ist oft nur kurz glitchy.
                        if project.upscaleKind != nil, status == .failed,
                           let msg = failureReason,
                           msg.localizedCaseInsensitiveContains("internal error")
                            || msg.localizedCaseInsensitiveContains("try again later"),
                           upscaleRetries < 3,
                           let kind = project.upscaleKind,
                           let fileData = project.referenceImagesData.first {
                            upscaleRetries += 1
                            project.progressStage = "Retrying… (\(upscaleRetries)/3)"
                            try? await Task.sleep(for: .seconds(2))
                            if let newID = try? await UpscaleAPI.createTask(type: kind, fileData: fileData) {
                                taskID = newID
                                project.taskID = newID
                                consecutiveErrors = 0
                                continue
                            }
                        }
                        fail(project: project, message: failureReason ?? "The generation failed.")
                        return
                    }
                } catch {
                    // Bei fehlender Backend-Konfiguration sofort abbrechen.
                    if error is SeedanceError, case SeedanceError.missingBackend = error {
                        fail(project: project, message: error.localizedDescription)
                        return
                    }
                    // Bei vorübergehenden Netzwerkfehlern weiter pollen –
                    // erst nach längerer Dauerstörung (~5 min) aufgeben.
                    consecutiveErrors += 1
                    if consecutiveErrors >= 60 {
                        fail(project: project, message: "Lost connection to the server. Please try again later.")
                        return
                    }
                }
            }
        }
    }

    // MARK: - Abschluss

    /// Lädt das Video lokal herunter (Remote-URL läuft nach 24 h ab) und erzeugt ein Thumbnail.
    /// Öffentlicher Einstieg für „Download erneut versuchen": führt `finalize`
    /// für ein bereits succeeded-Projekt erneut aus (mit dem robusten Browser-UA-
    /// Download). Nutzung z. B. für alte Kling-3.0-Projekte, deren Download damals
    /// still scheiterte (status=succeeded, aber keine lokale Datei). Bei Erfolg
    /// steht die Datei lokal zum Speichern/Teilen bereit; bei Misserfolg wird das
    /// Projekt sauber als fehlgeschlossen markiert (+ idempotente Erstattung).
    func redownloadResult(project: VideoProject) async {
        await finalize(project: project)
    }

    private func finalize(project: VideoProject) async {
        defer {
            activeProjectIDs.remove(project.id)
            endBackgroundTaskIfIdle()
            try? modelContext?.save()
        }

        guard let remote = project.remoteVideoURL, let url = URL(string: remote) else {
            project.status = .succeeded
            notifyFinished(project, success: true)
            return
        }

        // Robuster Download: manche kie/Kling-CDNs lehnen das iOS-Default-User-
        // Agent ab (HTTP 403) → der vorherige `URLSession.shared.download`
        // schlug bei Kling 3.0 still fehl, das Projekt wurde dennoch als
        // „succeeded" ohne lokale Datei markiert → „video not available for
        // download". Erst versuchen wir den Standard-Download, bei Fehler/403
        // folgt ein Download mit Browser-User-Agent. Erst wenn beides scheitert,
        // wird das Projekt sauber als fehlgeschlossen markiert (+ Erstattung).
        guard let tempURL = await Self.downloadRemoteMedia(at: url) else {
            fail(project: project,
                 message: "Couldn't download the result. Please try again — your credits were refunded.")
            return
        }

        // WICHTIG: echtes Bildformat erkennen und korrekte Endung wählen.
        // Das Backend (Nano Banana 2) liefert PNG; früher wurde die Datei pauschal
        // als .jpg abgelegt → Photos transcodierte PNG→JPEG (verlustbehaftet),
        // wodurch gespeicherte Bilder „automatisch schlechter"/verpixelt wirkten.
        // Mit der richtigen Endung (png/jpg) übernimmt Photos die Original-Bytes
        // verlustfrei.
        let ext: String
        var sourceURL = tempURL
        if project.isImageOutput {
            ext = Self.detectImageExtension(at: tempURL)
        } else {
            ext = "mp4"
            // Videos: Seedance (vertikal) liefert oft nur ~496×864 (~480p), auch
            // wenn 720p angefordert wird. Auf dem Handy full-screen wird das stark
            // hochskaliert → wirkt verpixelt/weich. Liegt die Kurzseite unter 720p,
            // hier auf 1080p (Seitenverhältnis erhalten) bei hoher Bitrate neu
            // rendern → sichtbar schärfer, ohne echte Details zu erfinden. Dateien
            // ≥720p bleiben unverändert (verlustfrei).
            if let upscaled = await Self.upscaleVideoIfNeeded(at: tempURL) {
                sourceURL = upscaled
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        let filename = "\(project.id.uuidString).\(ext)"
        let destination = URL.documentsDirectory.appending(path: filename)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destination)
        } catch {
            fail(project: project,
                 message: "Couldn't save the result. Please try again — your credits were refunded.")
            return
        }
        project.localVideoFilename = filename
        if project.isImageOutput {
            project.thumbnailData = await Self.generateImageThumbnail(for: destination)
        } else {
            project.thumbnailData = await Self.generateThumbnail(for: destination)
        }
        project.status = .succeeded
        notifyFinished(project, success: true)
    }

    /// „Dein Video ist fertig"-Mitteilung (nur wenn die App im Hintergrund ist).
    private func notifyFinished(_ project: VideoProject, success: Bool) {
        Notifier.generationFinished(templateTitle: project.templateTitle,
                                    success: success,
                                    isImage: project.isImageOutput)
    }

    private func fail(project: VideoProject, message: String) {
        project.status = .failed
        project.errorMessage = message
        notifyFinished(project, success: false)
        activeProjectIDs.remove(project.id)
        endBackgroundTaskIfIdle()
        // Bei JEDEM Fehlschlag (Fehler, Abbruch, App-Kill) genau die abgebuchten
        // Credits zurückerstatten – aber nur EINMAL (Idempotenz über `refunded`),
        // damit es weder doppelt erstattet noch (wie bei Fruit Story) vergessen wird.
        if !project.refunded {
            let refundAmount: Int
            if project.creditCost > 0 {
                refundAmount = project.creditCost
            } else if project.useMusicLipSync {
                refundAmount = CreditCosts.musicVideo(key: project.musicVideoKey, resolution: project.resolution)
            } else {
                refundAmount = CreditCosts.video(seconds: project.duration,
                                                 hasReferenceVideo: !project.referenceVideoURLs.isEmpty,
                                                 resolution: project.resolution)
            }
            store?.refund(refundAmount)
            project.refunded = true
        }
        try? modelContext?.save()
    }

    // MARK: - Thumbnail

    nonisolated private static func generateThumbnail(for url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)

        guard let cgImage = try? await generator.image(at: .init(seconds: 0.1, preferredTimescale: 600)).image else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }

    /// Erzeugt aus einer lokalen Bilddatei ein verkleinertes Thumbnail.
    nonisolated private static func generateImageThumbnail(for url: URL) async -> Data? {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return image.resized(maxDimension: 1000).jpegData(compressionQuality: 0.85)
    }

    /// Erkennt das echte Bildformat aus den Datei-Header-Bytes → richtige Endung,
    /// damit Photos das Original verlustfrei übernimmt (kein PNG→JPEG-Re-Encode).
    nonisolated private static func detectImageExtension(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 8) else { return "png" }
        try? handle.close()
        let b = [UInt8](head)
        if b.count >= 4, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 {
            return "png"   // PNG-Signatur
        }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF {
            return "jpg"   // JPEG-SOIMarker
        }
        if b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
           b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 {
            return "webp"  // RIFF...WEBP
        }
        return "png"   // Nano Banana 2 Default ist PNG
    }

    /// Lädt ein generiertes Ergebnis (Video oder Bild) robust herunter:
    /// 1) Standard-`URLSession`-Download (klappt für die meisten kie/Seedance-Hosts).
    /// 2) Fallback mit Browser-User-Agent — manche kie/Kling-CDNs lehnen das
    ///    iOS-Default-UA ab (HTTP 403), sodass Kling-3.0-Videos scheinbar fertig,
    ///    aber nicht herunterladbar waren. Mit Browser-UA klappt's.
    /// Leere/fehlerhafte Downloads (<10 KB) werden verworfen. Liefert eine
    /// temporäre Datei-URL oder nil.
    nonisolated private static func downloadRemoteMedia(at url: URL) async -> URL? {
        // 1) Standard-Download.
        if let (tempURL, _) = try? await URLSession.shared.download(from: url),
           Self.isUsableMedia(at: tempURL) {
            return tempURL
        }
        // 2) Fallback mit Browser-User-Agent.
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                     + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                     + "Version/17.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 120
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        cfg.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, _) = try await session.data(for: req)
            guard data.count > 10_000 else { return nil }
            let out = URL.temporaryDirectory.appending(path: "clavic-dl-\(UUID().uuidString)")
            try data.write(to: out)
            return out
        } catch {
            return nil
        }
    }

    /// Mindestgrößen-Check: leere/fehlerhafte Downloads verwerfen.
    nonisolated private static func isUsableMedia(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size > 10_000
    }

    /// Liegt das generierte Video unter 720p (Seedance vertikal oft ~496×864),
    /// wird es hier auf 1080p hochskaliert (Seitenverhältnis erhalten, hohe Bitrate,
    /// AVAssetExportSession HighestQuality). Das nimmt dem Handy-Player die grobe
    /// Full-Screen-Hochskalierung ab → gespeicherte/ geteilte Videos wirken deutlich
    /// schärfer, nicht mehr verpixelt. Audio bleibt erhalten. Dateien ≥720p werden
    /// unverändert durchgereicht (nil → kein Re-Encode).
    nonisolated private static func upscaleVideoIfNeeded(at url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let natSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration) else { return nil }

        let oriented = natSize.applying(transform)
        let w = abs(oriented.width), h = abs(oriented.height)
        guard w > 1, h > 1 else { return nil }
        let shortSide = min(w, h)
        guard shortSide < 720 else { return nil }  // schon ≥720p → nichts tun

        func evenScaled(_ dim: CGFloat) -> Int {
            let v = Int((dim * (1080.0 / shortSide)).rounded())
            return v % 2 == 0 ? max(v, 2) : max(v + 1, 2)
        }
        let target = CGSize(width: evenScaled(w), height: evenScaled(h))

        let comp = AVMutableVideoComposition()
        comp.renderSize = target
        comp.frameDuration = CMTime(value: 1, timescale: 30)
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: duration)
        let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let sx = CGFloat(target.width) / w
        let sy = CGFloat(target.height) / h
        li.setTransform(transform.concatenating(CGAffineTransform(scaleX: sx, y: sy)), at: .zero)
        instr.layerInstructions = [li]
        comp.instructions = [instr]

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        export.videoComposition = comp
        export.shouldOptimizeForNetworkUse = false  // keine Bitrate-Drosselung
        let out = URL.temporaryDirectory.appending(path: "clavic-up-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)
        do {
            try await export.export(to: out, as: .mp4)
            if export.status == .completed { return out }
            try? FileManager.default.removeItem(at: out)
            return nil
        } catch {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
    }

    /// Nano-Banana-2-Vor-Edit: wendet die Anweisung (z. B. „change the background
    /// to a beach") aufs Foto an und liefert das bearbeitete Bild zurück.
    /// Wirft bei Fehler/Timeout — der Aufrufer nutzt dann das Original weiter.
    private static func preEditPhoto(_ photo: Data, instruction: String) async throws -> Data {
        let request = ImageEditRequest(
            prompt: "Edit this photo: \(instruction). Keep it photorealistic and natural; keep everything not mentioned unchanged. No text, no watermark.",
            referenceImages: [photo],
            quality: "low",
            aspectRatio: "auto"
        )
        let taskID = try await ImageEditAPI.createTask(request)
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(4))
            let state = try await ImageEditAPI.fetchTask(id: taskID)
            switch state.status {
            case .succeeded:
                guard let s = state.imageURL, let url = URL(string: s) else {
                    throw SeedanceError.invalidResponse
                }
                let (data, _) = try await URLSession.shared.data(from: url)
                return data
            case .failed, .cancelled:
                throw SeedanceError.taskFailed(state.failureReason ?? "Photo edit failed.")
            default:
                continue
            }
        }
        throw SeedanceError.taskFailed("Photo edit timed out.")
    }

    /// Verkleinert Referenzfotos vor dem Upload (Vercel Body-Limit ~4,5 MB).
    private static func compressForUpload(_ images: [Data], video: Bool) -> [Data] {
        let maxDim: CGFloat = video ? 768 : 1024
        let quality: CGFloat = video ? 0.72 : 0.78
        return images.map { data in
            guard let image = UIImage(data: data),
                  let jpeg = image.jpegForAPIUpload(maxDimension: maxDim, quality: quality) else { return data }
            return jpeg
        }
    }
}
