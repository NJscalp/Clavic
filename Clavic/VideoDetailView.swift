//
//  VideoDetailView.swift
//  Clavic
//
//  Detailansicht: Player, Projekt-Infos, Teilen, In Fotos sichern, Löschen.
//

import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import Photos
import UIKit

struct VideoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(Store.self) private var store
    @Environment(GenerationManager.self) private var generationManager

    let project: VideoProject

    @State private var player: AVPlayer?
    @State private var showDeleteConfirmation = false
    @State private var saveResultMessage: String?
    /// Bereitet einen (für Free-Nutzer mit Wasserzeichen versehenen) Export vor.
    @State private var isPreparingExport = false
    @State private var shareItem: ShareItem?
    @State private var isRedownloading = false

    /// Alte Projekte, deren Download damals still scheiterte (status=succeeded,
    /// aber keine lokale Datei, nur Remote-URL). Für sie wird beim Öffnen ein
    /// Retry-Download angeboten bzw. automatisch angestoßen.
    private var needsRedownload: Bool {
        project.status == .succeeded
            && project.localVideoURL == nil
            && project.remoteVideoURL != nil
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    playerSection
                    if needsRedownload {
                        redownloadCard
                    } else if project.status == .succeeded {
                        actionRow
                    }
                    if project.status == .failed, project.resumable {
                        resumeCard
                    } else if let error = project.errorMessage, project.status == .failed {
                        errorCard(error)
                    }
                    if !project.isImageOutput {
                        promptCard
                    }
                    detailsCard
                    if !project.referenceImagesData.isEmpty {
                        referencesCard
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(project.isImageOutput ? "Image" : "Video")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        reportContent()
                    } label: {
                        Label("Report a problem", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(project.isImageOutput ? "Delete image" : "Delete video", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .confirmationDialog(project.isImageOutput ? "Delete image?" : "Delete video?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This and all related data will be permanently removed.")
        }
        .alert(
            saveResultMessage ?? "",
            isPresented: Binding(
                get: { saveResultMessage != nil },
                set: { if !$0 { saveResultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
        .onAppear {
            if !project.isImageOutput, let url = project.playbackURL, project.status == .succeeded {
                player = AVPlayer(url: url)
            }
            if needsRedownload && !isRedownloading {
                Task { await redownload() }
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

    // MARK: - Player

    private var resultImage: UIImage? {
        if let url = project.localVideoURL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }
        if let data = project.thumbnailData, let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    private var playerSection: some View {
        Group {
            if project.isImageOutput, project.status == .succeeded, let image = resultImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            } else if let player {
                VideoPlayer(player: player)
                    .aspectRatio(aspectRatioValue, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            } else if project.status.isActive {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                        .fill(Theme.background)
                        .aspectRatio(16/9, contentMode: .fit)
                    VStack(spacing: 8) {
                        IntroLoader()
                            .frame(width: 120, height: 120)
                            .allowsHitTesting(false)
                        Text(project.progressStage.isEmpty ? "Starting…" : project.progressStage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.25), value: project.progressStage)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                        .fill(Theme.surface)
                        .aspectRatio(16/9, contentMode: .fit)
                    VStack(spacing: 12) {
                        Image(systemName: project.status == .failed ? "exclamationmark.triangle" : "film")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.textTertiary)
                        Text(project.status.label)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var aspectRatioValue: CGFloat {
        switch project.ratio {
        case .widescreen: return 16/9
        case .portrait: return 9/16
        case .square: return 1
        case .classic: return 4/3
        case .vertical: return 3/4
        case .cinema: return 21/9
        case .adaptive: return 16/9
        }
    }

    // MARK: - Aktionen

    /// Karte für alte Projekte ohne lokale Datei: bietet „Retry download" an und
    /// zeigt den Status des erneuten Downloads (robuster Browser-UA-Pfad).
    private var redownloadCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: isRedownloading ? "arrow.down.circle" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .rotationEffect(.degrees(isRedownloading ? 360 : 0))
                    .animation(isRedownloading
                               ? .linear(duration: 1).repeatForever(autoreverses: false)
                               : .default,
                               value: isRedownloading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isRedownloading ? "Downloading your video…" : "Video not saved yet")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(isRedownloading
                         ? "Fetching it from the server — this only takes a moment."
                         : "Tap below to fetch it from the server, then save or share it.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if !isRedownloading {
                Button {
                    Task { await redownload() }
                } label: {
                    actionLabel(icon: "arrow.triangle.2.circlepath", text: "Retry download")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    /// Löst den erneuten Download über den robusten Browser-UA-Pfad aus.
    private func redownload() async {
        await MainActor.run { isRedownloading = true }
        await generationManager.redownloadResult(project: project)
        await MainActor.run {
            isRedownloading = false
            if project.localVideoURL != nil {
                saveResultMessage = "Download ready — you can save or share now."
                if !project.isImageOutput, let url = project.playbackURL {
                    player = AVPlayer(url: url)
                }
            } else {
                saveResultMessage = "Download still failed — your credits were refunded."
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await shareToTikTok() }
            } label: {
                actionLabel(icon: "music.note", text: "TikTok")
            }
            .buttonStyle(.plain)
            .disabled(isPreparingExport)

            Button {
                Task { await exportAndShare() }
            } label: {
                actionLabel(icon: "square.and.arrow.up",
                            text: isPreparingExport ? "Preparing…" : "Share")
            }
            .buttonStyle(.plain)
            .disabled(isPreparingExport)

            Button {
                Task { await saveToPhotos() }
            } label: {
                actionLabel(icon: "square.and.arrow.down", text: "Save")
            }
            .buttonStyle(.plain)
            .disabled(isPreparingExport)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
    }

    /// Viral-Loop: Ergebnis in die Fotos sichern, Template-Hashtag in die
    /// Zwischenablage kopieren und TikTok öffnen — dort wählt der Nutzer das
    /// Video aus der Galerie und fügt die Caption ein. (Ohne TikTok-SDK; ist
    /// TikTok nicht installiert, öffnet sich das normale Share-Sheet.)
    private func shareToTikTok() async {
        guard let raw = project.localVideoURL else {
            saveResultMessage = project.isImageOutput
                ? "The image isn't available locally yet."
                : "The video isn't available locally yet."
            return
        }
        isPreparingExport = true
        let url = await exportForSharing(raw)
        isPreparingExport = false
        let isImage = project.isImageOutput

        // 1) In die Fotos sichern (TikTok zieht Uploads aus der Galerie).
        let granted = await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                cont.resume(returning: status == .authorized || status == .limited)
            }
        }
        guard granted else {
            saveResultMessage = "No access to the photo library. Please allow it in iOS Settings."
            return
        }
        let saved = await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges {
                if isImage {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
            } completionHandler: { success, _ in
                cont.resume(returning: success)
            }
        }
        guard saved else {
            saveResultMessage = "Saving failed."
            return
        }

        // 2) Caption (Template-Hashtag) in die Zwischenablage.
        let hashtag = TemplateLibrary.all
            .first(where: { $0.title == project.templateTitle })?
            .hashtag ?? ""
        UIPasteboard.general.string = hashtag.isEmpty ? "#clavic" : "\(hashtag) #clavic"

        // 3) TikTok öffnen (zwei bekannte URL-Schemes), sonst Share-Sheet.
        let schemes = ["tiktok://", "snssdk1233://"]
        for scheme in schemes {
            if let appURL = URL(string: scheme), UIApplication.shared.canOpenURL(appURL) {
                saveResultMessage = "Saved to Photos ✓ Caption copied — pick the \(isImage ? "photo" : "video") from your gallery in TikTok and paste the caption."
                await UIApplication.shared.open(appURL)
                return
            }
        }
        await exportAndShare()
    }

    /// Liefert die zu teilende/sichernde Datei. Free-Nutzer bekommen ein
    /// „Made with Clavic"-Wasserzeichen (Viral-Loop + Upgrade-Anreiz); Pro-Nutzer
    /// exportieren sauber. Bei einem Fehler wird die Originaldatei genutzt.
    private func exportForSharing(_ raw: URL) async -> URL {
        // IMMER die Original-Datei speichern/teilen – kein Re-Encode, keine
        // Skalierung → Download in EXAKT der erzeugten Qualität (nicht verpixelt).
        // (Hard Paywall: alle Nutzer sind Pro; kein Wasserzeichen-Re-Encode mehr.)
        return raw
    }

    private func exportAndShare() async {
        guard let raw = project.localVideoURL else {
            saveResultMessage = project.isImageOutput
                ? "The image isn't available locally yet."
                : "The video isn't available locally yet."
            return
        }
        isPreparingExport = true
        let url = await exportForSharing(raw)
        isPreparingExport = false
        shareItem = ShareItem(url: url)
    }

    private func actionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func saveToPhotos() async {
        guard let raw = project.localVideoURL else {
            saveResultMessage = project.isImageOutput
                ? "The image isn't available locally yet."
                : "The video isn't available locally yet."
            return
        }
        isPreparingExport = true
        let url = await exportForSharing(raw)
        isPreparingExport = false
        let isImage = project.isImageOutput
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    saveResultMessage = "No access to the photo library. Please allow it in iOS Settings."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                if isImage {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
            } completionHandler: { success, _ in
                Task { @MainActor in
                    let noun = isImage ? "Image" : "Video"
                    saveResultMessage = success ? "\(noun) saved to Photos." : "Saving failed."
                }
            }
        }
    }

    /// Meldet das Ergebnis an den Support (Apple-Anforderung: Report-Mechanismus
    /// für anstößige/problematische Inhalte).
    private func reportContent() {
        let subject = "Report content – Clavic"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Report"
        let body = "Reported item: \(project.id)\nTemplate: \(project.templateTitle)\nCreated: \(project.createdAt)\n\nPlease describe the problem:\n"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(LegalLinks.supportEmail)?subject=\(subject)&body=\(body)") {
            openURL(url)
        }
    }

    private func deleteProject() {
        player?.pause()
        player = nil
        // Erst die Ansicht schließen, DANN löschen. Sonst würde SwiftUI die
        // Detailansicht kurz mit dem bereits gelöschten Objekt neu rendern
        // (navigationDestination-Wert wird ungültig) → Crash / „passiert nichts".
        let filename = project.localVideoFilename
        let context = modelContext
        let target = project
        // Fair: ein nicht fertiges, noch nicht erstattetes Projekt (z. B. pausiert/
        // fehlgeschlagen) wird beim Löschen erstattet, damit keine Credits verloren gehen.
        if target.status != .succeeded, !target.refunded, target.creditCost > 0 {
            store.refund(target.creditCost)
            target.refunded = true
        }
        Checkpoint.clear(target.id)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if let filename {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: filename))
            }
            context.delete(target)
            try? context.save()
        }
    }

    // MARK: - Info-Karten

    /// Pausierte mehrstufige Generierung: fortsetzen ab der Abbruchstelle
    /// (bereits erzeugte Szenen bleiben erhalten, keine erneute Abbuchung).
    private var resumeCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paused")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Some scenes are already done. Continue to finish from where it stopped — no extra credits, nothing is re-created.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Button {
                generationManager.resume(project: project)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Continue")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
            }
        }
        .padding(14)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text("Generation failed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.3), lineWidth: 1)
        )
    }

    // Bei Template-Videos zeigen wir NICHT den internen Prompt, sondern nur den
    // Template-Namen. Nur bei freien Generierungen (kein Template) wird der
    // selbst eingegebene Prompt angezeigt.
    @ViewBuilder
    private var promptCard: some View {
        if !project.templateTitle.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Template")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                Text(project.templateTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .cardStyle()
        } else if !project.prompt.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                Text(project.prompt)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .cardStyle()
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            if project.isImageOutput {
                detailRow(label: "Model", value: "Clavic Image 1 (Edit)")
                divider
                detailRow(label: "Type", value: "Image")
                divider
                detailRow(label: "Created", value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
            } else {
                detailRow(label: "Model", value: "Clavic Video Reference")
                divider
                detailRow(label: "Aspect ratio", value: project.ratio.label)
                divider
                detailRow(label: "Resolution", value: project.resolution.rawValue)
                divider
                detailRow(label: "Length", value: "\(project.duration) seconds")
                divider
                detailRow(label: "Audio", value: project.generateAudio ? "Yes" : "No")
                divider
                detailRow(label: "Created", value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .cardStyle()
    }

    private var divider: some View {
        Divider().overlay(Theme.stroke).padding(.leading, 16)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var referencesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reference images")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(project.referenceImagesData.enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }
}

// MARK: - Share-Sheet

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Natives iOS-Teilen-Menü (TikTok, Instagram, Reels, Nachrichten …).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Wasserzeichen ("Made with Clavic")

enum WatermarkError: Error { case noVideoTrack, exportFailed }

/// Brennt ein dezentes „Made with Clavic"-Branding in Exporte (Free-Tier).
/// Sorgt für kostenlose Reichweite beim Teilen + Upgrade-Anreiz (Pro = ohne).
enum Watermark {

    static let text = "Made with Clavic"

    // MARK: Video

    static func video(at sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw WatermarkError.noVideoTrack
        }
        let duration = try await asset.load(.duration)
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WatermarkError.exportFailed
        }
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        if let audio = try await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audio, at: .zero)
        }

        // Auf die korrekte (gedrehte) Ausgabegröße rendern.
        let oriented = naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(makeWatermarkLayer(canvas: renderSize))
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outURL = URL.temporaryDirectory.appending(path: "clavic-share-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw WatermarkError.exportFailed
        }
        export.videoComposition = videoComposition
        export.shouldOptimizeForNetworkUse = true
        try await export.export(to: outURL, as: .mp4)
        return outURL
    }

    // MARK: Bild

    static func image(at sourceURL: URL) throws -> URL {
        guard let data = try? Data(contentsOf: sourceURL), let image = UIImage(data: data) else {
            throw WatermarkError.exportFailed
        }
        let size = image.size
        // In NATIVER Auflösung rendern: sonst nimmt UIGraphicsImageRenderer die
        // Bildschirm-Scale (2x/3x) und skaliert das Bild hoch → unscharf/„verpixelt".
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        let result = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            drawWatermark(canvas: size)
        }
        guard let jpeg = result.jpegData(compressionQuality: 0.97) else { throw WatermarkError.exportFailed }
        let outURL = URL.temporaryDirectory.appending(path: "clavic-share-\(UUID().uuidString).jpg")
        try? FileManager.default.removeItem(at: outURL)
        try jpeg.write(to: outURL)
        return outURL
    }

    // MARK: Zeichnen

    private static func metrics(_ size: CGSize) -> (font: UIFont, textSize: CGSize, pill: CGSize, padH: CGFloat) {
        let fontSize = max(16, min(size.width, size.height) * 0.045)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let padH = fontSize * 0.75
        let padV = fontSize * 0.5
        return (font, textSize, CGSize(width: textSize.width + padH * 2, height: textSize.height + padV * 2), padH)
    }

    /// CALayer-Overlay fürs Video (Core-Animation-Geometrie: Ursprung unten links).
    private static func makeWatermarkLayer(canvas size: CGSize) -> CALayer {
        let m = metrics(size)
        let bottomMargin = size.height * 0.05
        let pill = CALayer()
        pill.frame = CGRect(x: (size.width - m.pill.width) / 2, y: bottomMargin,
                            width: m.pill.width, height: m.pill.height)
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.38).cgColor
        pill.cornerRadius = m.pill.height / 2
        pill.masksToBounds = true

        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = CTFontCreateWithName(m.font.fontName as CFString, m.font.pointSize, nil)
        textLayer.fontSize = m.font.pointSize
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.frame = CGRect(x: 0, y: (m.pill.height - m.textSize.height) / 2,
                                 width: m.pill.width, height: m.textSize.height)
        pill.addSublayer(textLayer)
        return pill
    }

    /// Direktes Zeichnen fürs Bild (UIKit-Geometrie: Ursprung oben links).
    private static func drawWatermark(canvas size: CGSize) {
        let m = metrics(size)
        let x = (size.width - m.pill.width) / 2
        let y = size.height - m.pill.height - size.height * 0.05
        let pillRect = CGRect(x: x, y: y, width: m.pill.width, height: m.pill.height)
        UIColor.black.withAlphaComponent(0.38).setFill()
        UIBezierPath(roundedRect: pillRect, cornerRadius: m.pill.height / 2).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: m.font, .foregroundColor: UIColor.white]
        let textOrigin = CGPoint(x: x + m.padH, y: y + (m.pill.height - m.textSize.height) / 2)
        (text as NSString).draw(at: textOrigin, withAttributes: attrs)
    }
}
