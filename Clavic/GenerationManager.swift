//
//  GenerationManager.swift
//  Clavic
//
//  Steuert den Lebenszyklus einer Generierung: Task einreichen,
//  Status pollen, fertiges Video herunterladen und Thumbnail erzeugen.
//

import Foundation
import SwiftData
import AVFoundation
import UIKit

@Observable
@MainActor
final class GenerationManager {
    /// IDs der Projekte, die gerade aktiv überwacht werden
    private(set) var activeProjectIDs: Set<UUID> = []
    /// Projekte mit einer aktuell laufenden Polling-Schleife (verhindert Doppel-Polling)
    private var liveMonitors: Set<UUID> = []
    /// Projekte, deren initialer Einreich-Aufruf gerade läuft (noch keine Task-ID)
    private var submitting: Set<UUID> = []

    private var modelContext: ModelContext?
    /// Für Credit-Rückerstattung bei Fehlern
    var store: Store?

    /// Hält die App nach dem Wechsel in den Hintergrund kurz am Leben,
    /// damit fast fertige Generierungen noch abgeschlossen werden können.
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func configure(context: ModelContext) {
        self.modelContext = context
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
            if project.taskID != nil {
                monitor(project: project)
            } else {
                // Nur als unterbrochen markieren, wenn auch keine Überwachung
                // bzw. kein Einreich-Aufruf mehr aktiv ist.
                if !liveMonitors.contains(project.id) && !submitting.contains(project.id) {
                    project.status = .failed
                    project.errorMessage = "The generation was interrupted."
                    activeProjectIDs.remove(project.id)
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Generierung starten

    func submit(project: VideoProject) {
        guard let modelContext else { return }
        modelContext.insert(project)
        try? modelContext.save()

        activeProjectIDs.insert(project.id)
        // Markiert das Projekt als "wird eingereicht", damit ein zwischenzeitlicher
        // Rückkehr-Trigger es nicht fälschlich als unterbrochen markiert.
        submitting.insert(project.id)

        Task {
            defer { submitting.remove(project.id) }
            do {
                let taskID: String
                if let kind = project.upscaleKind {
                    guard let fileData = project.referenceImagesData.first else {
                        throw SeedanceError.invalidResponse
                    }
                    taskID = try await UpscaleAPI.createTask(type: kind, fileData: fileData)
                } else if project.isImageOutput {
                    let request = ImageEditRequest(
                        prompt: project.prompt,
                        referenceImages: project.referenceImagesData
                    )
                    taskID = try await ImageEditAPI.createTask(request)
                } else {
                    let request = SeedanceRequest(
                        prompt: project.prompt,
                        referenceImages: project.referenceImagesData,
                        ratio: project.ratio,
                        resolution: project.resolution,
                        duration: project.duration,
                        generateAudio: project.generateAudio,
                        useFastModel: project.useFastModel,
                        referenceVideoURLs: project.referenceVideoURLs
                    )
                    taskID = project.useKie
                        ? try await KieSeedanceAPI.createTask(request)
                        : try await SeedanceAPI.createTask(request)
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

    // MARK: - Polling

    private func monitor(project: VideoProject) {
        // Verhindert eine zweite Polling-Schleife für dasselbe Projekt.
        guard !liveMonitors.contains(project.id) else { return }
        liveMonitors.insert(project.id)
        activeProjectIDs.insert(project.id)

        Task {
            defer { liveMonitors.remove(project.id) }

            guard let taskID = project.taskID else {
                fail(project: project, message: "No task ID available.")
                return
            }

            var consecutiveErrors = 0

            while true {
                try? await Task.sleep(for: .seconds(5))

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
                    } else if project.useKie {
                        let state = try await KieSeedanceAPI.fetchTask(id: taskID)
                        status = state.status
                        resultURL = state.videoURL
                        failureReason = state.failureReason
                    } else {
                        let state = try await SeedanceAPI.fetchTask(id: taskID)
                        status = state.status
                        resultURL = state.videoURL
                        failureReason = state.failureReason
                    }
                    consecutiveErrors = 0

                    switch status {
                    case .queued, .running:
                        if project.status != status {
                            project.status = status
                            try? modelContext?.save()
                        }
                    case .succeeded:
                        project.remoteVideoURL = resultURL
                        await finalize(project: project)
                        return
                    case .failed, .cancelled:
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
    private func finalize(project: VideoProject) async {
        defer {
            activeProjectIDs.remove(project.id)
            endBackgroundTaskIfIdle()
            try? modelContext?.save()
        }

        guard let remote = project.remoteVideoURL, let url = URL(string: remote) else {
            project.status = .succeeded
            return
        }

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            let ext = project.isImageOutput ? "jpg" : "mp4"
            let filename = "\(project.id.uuidString).\(ext)"
            let destination = URL.documentsDirectory.appending(path: filename)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            project.localVideoFilename = filename
            if project.isImageOutput {
                project.thumbnailData = await Self.generateImageThumbnail(for: destination)
            } else {
                project.thumbnailData = await Self.generateThumbnail(for: destination)
            }
        } catch {
            // Ergebnis bleibt über die Remote-URL erreichbar, solange sie gültig ist.
        }

        project.status = .succeeded
    }

    private func fail(project: VideoProject, message: String) {
        project.status = .failed
        project.errorMessage = message
        activeProjectIDs.remove(project.id)
        endBackgroundTaskIfIdle()
        // Bei Fehlschlag die abgezogenen Credits zurückerstatten.
        store?.refund(store?.cost(forDuration: project.duration) ?? 0)
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
}
