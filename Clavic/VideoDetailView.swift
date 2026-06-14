//
//  VideoDetailView.swift
//  Clavic
//
//  Detailansicht: Player, Projekt-Infos, Teilen, In Fotos sichern, Löschen.
//

import SwiftUI
import SwiftData
import AVKit
import Photos

struct VideoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: VideoProject

    @State private var player: AVPlayer?
    @State private var showDeleteConfirmation = false
    @State private var saveResultMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    playerSection
                    if project.status == .succeeded {
                        actionRow
                    }
                    if let error = project.errorMessage, project.status == .failed {
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
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.danger)
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
                        Text("This can take 1–2 minutes.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
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

    private var actionRow: some View {
        HStack(spacing: 12) {
            if let url = project.localVideoURL {
                ShareLink(item: url) {
                    actionLabel(icon: "square.and.arrow.up", text: "Share")
                }
                .buttonStyle(.plain)
            }
            Button {
                saveToPhotos()
            } label: {
                actionLabel(icon: "square.and.arrow.down", text: "Save to Photos")
            }
            .buttonStyle(.plain)
        }
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

    private func saveToPhotos() {
        guard let url = project.localVideoURL else {
            saveResultMessage = project.isImageOutput
                ? "The image isn't available locally yet."
                : "The video isn't available locally yet."
            return
        }
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

    private func deleteProject() {
        player?.pause()
        if let filename = project.localVideoFilename {
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: filename))
        }
        modelContext.delete(project)
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Info-Karten

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

    private var promptCard: some View {
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
