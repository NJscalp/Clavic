//
//  CreateView.swift
//  Clavic
//
//  Erstellen-Screen (modal): Video mit Seedance 2.0 aus Prompt +
//  Referenzbildern generieren. Optional mit Template vorbelegt.
//

import SwiftUI
import PhotosUI

struct CreateView: View {
    @Environment(GenerationManager.self) private var generationManager
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Optionales Template zur Vorbelegung
    let template: VideoTemplate?
    /// Wird nach erfolgreichem Start aufgerufen (z. B. Wechsel zur Bibliothek)
    var onSubmitted: () -> Void = {}

    @State private var prompt = ""
    @State private var referenceImages: [Data] = []
    @State private var photoSelection: [PhotosPickerItem] = []

    @State private var ratio: AspectRatio = .widescreen
    @State private var duration = 5
    @State private var generateAudio = true
    @State private var referenceVideoURLs: [String] = []

    /// Hintergrund-Quelle im geführten Modus.
    enum BackgroundMode { case trend, photo }
    @State private var backgroundMode: BackgroundMode = .trend

    /// Bild-Trend: Ziel-Look (Mann/Frau).
    enum SwapGender { case man, woman }
    @State private var swapTarget: String = ""
    @State private var swapOutfit: String = ""
    @State private var swapGender: SwapGender = .man
    /// Freier Bild-Editor: kurze Anweisung (Outfit ändern / jemanden hinzufügen).
    @State private var editInstruction: String = ""

    /// Seedance erzeugt immer in 480p.
    private let resolution: Resolution = .p480

    @State private var showMissingKeyAlert = false
    @State private var showPaywall = false
    @State private var showFileTooLargeAlert = false
    private enum Field: Hashable { case prompt, target, outfit }
    @FocusState private var focusedField: Field?

    private let maxReferenceImages = 4

    /// Geführter „Fix"-Modus: kein Prompt, nur Foto + Hintergrund + Generieren.
    private var isFixed: Bool { template?.isFixed == true }

    /// Bild-Trend (GPT Image 1 Edit): Foto + kurzer Prompt → ein Bild.
    private var isImageEdit: Bool { template?.isImageEdit == true }

    /// Freier Bild-Editor: Foto + Anweisung (Outfit ändern / Person hinzufügen).
    private var isFreeformEdit: Bool { template?.isFreeformEdit == true }

    /// Upscale-Werkzeug: Datei hochladen → hochskalieren.
    private var upscaleKind: String? { template?.upscaleKind }
    private var isUpscale: Bool { template?.isUpscale == true }
    private var isVideoUpscale: Bool { upscaleKind == "video" }

    /// Maximale Upload-Größe fürs Video-Upscale (Server-Body-Limit ~4,5 MB).
    private let maxVideoUploadBytes = 3_300_000

    private var canGenerate: Bool {
        if isUpscale || isImageEdit || isFixed {
            return !referenceImages.isEmpty
        }
        return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var creditCost: Int {
        if isImageEdit { return CreditCosts.imageEdit }
        if upscaleKind == "image" { return CreditCosts.imageUpscale }
        if upscaleKind == "video" { return CreditCosts.videoUpscale }
        // Video-Generierung: nach gewählter Länge + ob ein Referenz-Video genutzt wird.
        let hasReferenceVideo = !referenceVideoURLs.isEmpty || template?.referenceVideoURL != nil
        return CreditCosts.video(seconds: duration, hasReferenceVideo: hasReferenceVideo)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if isUpscale {
                            upscaleUploadSection
                            generateButton
                        } else if isImageEdit {
                            if referenceImages.isEmpty {
                                photoHintBanner
                            }
                            guidedPhotoSection
                            if isFreeformEdit {
                                editInstructionSection
                            } else {
                                swapTargetSection
                                swapGenderSection
                                swapOutfitSection
                            }
                            generateButton
                        } else if isFixed {
                            guidedPhotoSection
                            backgroundChoiceSection
                            generateButton
                        } else {
                            if let template, template.needsPhoto, referenceImages.isEmpty {
                                photoHintBanner
                            }
                            settingsSection
                            attachedImagesRow
                            promptComposer
                            creditCostHint
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: photoSelection) { _, newItems in
                    handlePhotoSelection(newItems)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .alert("No connection", isPresented: $showMissingKeyAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The server is currently unreachable. Please try again in a moment.")
            }
            .alert("Video too large", isPresented: $showFileTooLargeAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please pick a shorter clip (about 3 MB max) for upscaling.")
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showPaywall) {
            CreditsView()
        }
        .onAppear(perform: applyTemplate)
    }

    private var navigationTitle: String {
        if isUpscale { return isVideoUpscale ? "Video Upscale" : "Image Upscale" }
        if isImageEdit { return "Create Image" }
        return "Create Video"
    }

    private func applyTemplate() {
        guard let template, prompt.isEmpty else { return }
        prompt = template.prompt
        ratio = template.ratio
        duration = template.duration
        if let videoURL = template.referenceVideoURL {
            referenceVideoURLs = [videoURL]
        }
    }

    // MARK: - Upscale-Upload

    private var upscaleUploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: isVideoUpscale ? "Your video" : "Your photo",
                subtitle: isVideoUpscale
                    ? "Upload a short clip – it will be upscaled to higher quality."
                    : "Upload a photo – it will be sharpened and enlarged."
            )

            PhotosPicker(
                selection: $photoSelection,
                maxSelectionCount: 1,
                matching: isVideoUpscale ? .videos : .images
            ) {
                if let data = referenceImages.first {
                    upscaleSelectedPreview(data: data)
                } else {
                    upscaleEmptyState
                }
            }

            if isVideoUpscale {
                Text("Tip: short clips work best. Larger videos may be rejected.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func upscaleSelectedPreview(data: Data) -> some View {
        if !isVideoUpscale, let image = UIImage(data: data) {
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.04)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                changeBadge
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
        } else {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 10) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Text("Video selected")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(data.count / 1_000_000) MB")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                changeBadge
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
        }
    }

    private var changeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(isVideoUpscale ? "Change video" : "Change photo")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(12)
    }

    private var upscaleEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isVideoUpscale ? "video.badge.plus" : "photo.badge.plus")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(isVideoUpscale ? "Add video" : "Add photo")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(isVideoUpscale ? "Tap to choose a clip" : "Tap to choose a photo")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        )
    }

    // MARK: - Template-Banner

    private func templateBanner(_ template: VideoTemplate) -> some View {
        HStack(spacing: 14) {
            ZStack {
                template.gradient
                Image(systemName: template.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("TREND")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(template.hashtag)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(template.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(template.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .cardStyle()
    }

    private var photoHintBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("This trend needs your photo – add a reference image below.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
    }

    // MARK: - Geführter Modus

    private var guidedPhotoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Your photo",
                subtitle: "Add a photo of the person – it will be placed into the trend."
            )

            PhotosPicker(
                selection: $photoSelection,
                maxSelectionCount: 1,
                matching: .images
            ) {
                if let data = referenceImages.first, let image = UIImage(data: data) {
                    ZStack(alignment: .bottomTrailing) {
                        // Bild beliebiger Größe: voll sichtbar, immer innerhalb des Felds.
                        Color.black.opacity(0.04)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Change photo")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(12)
                    }
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.square.badge.camera")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(Theme.accent)
                        Text("Add photo")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Tap to choose a photo")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    )
                }
            }
        }
    }

    private var backgroundChoiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Background",
                subtitle: "Which background should appear in the video?"
            )
            HStack(spacing: 12) {
                backgroundOption(
                    mode: .trend,
                    icon: "sparkles.tv",
                    title: "Trend",
                    subtitle: "Original background"
                )
                backgroundOption(
                    mode: .photo,
                    icon: "photo",
                    title: "My photo",
                    subtitle: "Background from photo"
                )
            }
        }
    }

    // MARK: - Bild-Trend (welche Person + Ziel-Look)

    private var swapTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Who to change or add?",
                subtitle: "Describe which person to transform – or where to add a new person (optional)."
            )
            TextField(
                "e.g. the person on the left · or: add a person next to me",
                text: $swapTarget,
                axis: .vertical
            )
            .focused($focusedField, equals: .target)
            .lineLimit(1...4)
            .inputFieldStyle(focused: focusedField == .target)
        }
    }

    private var editInstructionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "What should change?",
                subtitle: "Change the outfit or add another person. Your face and identity stay the same."
            )
            TextField(
                "e.g. change my outfit to a black suit · or: add a friend next to me",
                text: $editInstruction,
                axis: .vertical
            )
            .focused($focusedField, equals: .target)
            .lineLimit(1...5)
            .inputFieldStyle(focused: focusedField == .target)

            HStack(spacing: 8) {
                editSuggestion("Elegant black suit")
                editSuggestion("Summer dress")
                editSuggestion("Add a friend")
            }
        }
    }

    private func editSuggestion(_ text: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { editInstruction = text }
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Theme.surfaceHigh, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var swapGenderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Edit into",
                subtitle: "Pick the new look for that person."
            )
            HStack(spacing: 12) {
                genderOption(
                    mode: .man,
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Beautiful Man",
                    subtitle: "Handsome guy"
                )
                genderOption(
                    mode: .woman,
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Beautiful Woman",
                    subtitle: "Gorgeous girl"
                )
            }
        }
    }

    private var swapOutfitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Outfit (optional)",
                subtitle: "Type the clothing the person should wear. Leave empty for an automatic stylish look."
            )
            TextField(
                "e.g. a black tailored suit · or: a red summer dress",
                text: $swapOutfit,
                axis: .vertical
            )
            .focused($focusedField, equals: .outfit)
            .lineLimit(1...4)
            .inputFieldStyle(focused: focusedField == .outfit)
        }
    }

    private func genderOption(mode: SwapGender, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = swapGender == mode
        return Button {
            withAnimation(.spring(duration: 0.25)) { swapGender = mode }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected ? AnyShapeStyle(Theme.accentSoft) : AnyShapeStyle(Theme.surface),
                in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func backgroundOption(mode: BackgroundMode, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = backgroundMode == mode
        return Button {
            withAnimation(.spring(duration: 0.25)) { backgroundMode = mode }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected ? AnyShapeStyle(Theme.accentSoft) : AnyShapeStyle(Theme.surface),
                in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prompt

    /// Eingabe im Composer-Stil: Textfeld oben, darunter eine Aktionsleiste
    /// mit Kamera (Referenzbild anhängen) links und Senden/Generieren rechts.
    private var promptComposer: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe your video …")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 14)
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $prompt)
                    .focused($focusedField, equals: .prompt)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .tint(Theme.accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .frame(minHeight: 92)
            }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $photoSelection,
                    maxSelectionCount: max(1, maxReferenceImages - referenceImages.count),
                    matching: .images
                ) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(referenceImages.count >= maxReferenceImages ? Theme.textTertiary : Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Theme.surfaceHigh, in: Circle())
                }
                .disabled(referenceImages.count >= maxReferenceImages)

                if !referenceImages.isEmpty {
                    Text("\(referenceImages.count)/\(maxReferenceImages)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                Button {
                    startGeneration()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            canGenerate ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.gray.opacity(0.3)),
                            in: Circle()
                        )
                }
                .disabled(!canGenerate)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .padding(.top, 2)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(focusedField == .prompt ? Theme.accent : Theme.stroke,
                              lineWidth: focusedField == .prompt ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.18), value: focusedField)
    }

    /// Horizontale Reihe der angehängten Referenzbilder (nur wenn vorhanden).
    @ViewBuilder
    private var attachedImagesRow: some View {
        if !referenceImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(referenceImages.enumerated()), id: \.offset) { index, data in
                        referenceThumbnail(data: data, index: index)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Referenzbilder

    private func handlePhotoSelection(_ newItems: [PhotosPickerItem]) {
        guard !newItems.isEmpty else { return }
        Task {
            // Upscale: genau eine Datei (Bild oder Video) hochladen.
            if isUpscale {
                if let item = newItems.first,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    if isVideoUpscale {
                        if data.count > maxVideoUploadBytes {
                            showFileTooLargeAlert = true
                        } else {
                            withAnimation(.spring(duration: 0.3)) { referenceImages = [data] }
                        }
                    } else if let image = UIImage(data: data),
                              let jpeg = image.resized(maxDimension: 2000).jpegData(compressionQuality: 0.9) {
                        withAnimation(.spring(duration: 0.3)) { referenceImages = [jpeg] }
                    }
                }
                photoSelection = []
                return
            }
            // Im geführten Modus / Bild-Trend genau ein Foto (ersetzt das bestehende).
            if isFixed || isImageEdit {
                if let item = newItems.first,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.resized(maxDimension: 1280).jpegData(compressionQuality: 0.85) {
                    withAnimation(.spring(duration: 0.3)) {
                        referenceImages = [jpeg]
                    }
                }
            } else {
                for item in newItems {
                    if referenceImages.count >= maxReferenceImages { break }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let jpeg = image.resized(maxDimension: 1280).jpegData(compressionQuality: 0.85) {
                        withAnimation(.spring(duration: 0.3)) {
                            referenceImages.append(jpeg)
                        }
                    }
                }
            }
            photoSelection = []
        }
    }

    private func referenceThumbnail(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            }
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    _ = referenceImages.remove(at: index)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.6), in: Circle())
            }
            .padding(5)
        }
    }

    // MARK: - Einstellungen

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Aspect ratio")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AspectRatio.allCases) { option in
                            SelectableChip(
                                title: option.label,
                                icon: option.icon,
                                isSelected: ratio == option
                            ) { ratio = option }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Length")
                    Spacer()
                    Text("\(duration) seconds")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                Slider(
                    value: Binding(
                        get: { Double(duration) },
                        set: { duration = Int($0.rounded()) }
                    ),
                    in: 4...15,
                    step: 1
                )
                .tint(Theme.accent)
            }

            VStack(spacing: 0) {
                toggleRow(
                    icon: "speaker.wave.2.fill",
                    title: "Generate audio",
                    subtitle: "Dialogue, sound effects and music to match the visuals",
                    isOn: $generateAudio
                )
            }
            .cardStyle()
        }
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(14)
    }

    // MARK: - Generieren

    private var generateButton: some View {
        VStack(spacing: 10) {
            Button {
                startGeneration()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isUpscale ? "arrow.up.left.and.arrow.down.right" : "wand.and.stars")
                    Text(generateButtonLabel)
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: canGenerate))
            .disabled(!canGenerate)

            creditCostHint
        }
    }

    private var creditCostHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "drop.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Costs \(creditCost) \(creditCost == 1 ? "Credit" : "Credits") · Balance: \(store.credits)")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(store.canAfford(creditCost) ? Theme.textSecondary : Theme.danger)
    }

    private var generateButtonLabel: String {
        if isUpscale { return "Upscale" }
        if isImageEdit { return "Generate Image" }
        return "Generate Video"
    }

    /// Wählt den passenden Prompt je nach Modus.
    private var finalPrompt: String {
        if isUpscale { return "" }
        if isFreeformEdit { return makeFreeformEditPrompt() }
        if isImageEdit { return makeGlowUpPrompt() }
        if isFixed, backgroundMode == .photo, let alt = template?.promptPhotoBackground {
            return alt
        }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Baut einen abwechslungsreichen Glow-Up-Prompt: das Ergebnis ist immer
    /// attraktiv und an das Bild angepasst, aber Aussehen und Outfit variieren
    /// bei jeder Generierung, damit nicht immer dieselbe Person erscheint.
    /// Fokus: maximal realistisch, perfekt eingepasste Beleuchtung.
    private func makeGlowUpPrompt() -> String {
        let manHair = [
            "a modern textured haircut", "a clean fade haircut",
            "stylish swept-back hair", "neatly groomed short hair",
            "a trendy crop hairstyle"
        ]
        let womanHair = [
            "long flowing hair", "an elegant styled updo",
            "trendy soft waves", "a sleek modern hairstyle",
            "natural voluminous glossy hair"
        ]
        let manOutfit = [
            "an elegant tailored suit with a modern slim cut",
            "a sharp designer blazer over a fitted modern shirt",
            "an elegant turtleneck with a stylish modern coat",
            "a refined modern outfit with a fitted dress shirt",
            "an elegant smart-casual look with a tailored jacket"
        ]
        let womanOutfit = [
            "an elegant figure-flattering dress",
            "a glamorous chic outfit",
            "a fashionable fitted dress that looks attractive and alluring",
            "a stylish crop top with a skirt",
            "a trendy flattering summer dress"
        ]

        let isMan = swapGender == .man
        let person = isMan ? "young man" : "young woman"
        let hair = (isMan ? manHair : womanHair).randomElement() ?? "stylish hair"
        let customOutfit = swapOutfit.trimmingCharacters(in: .whitespacesAndNewlines)
        let outfit = customOutfit.isEmpty
            ? (isMan ? manOutfit : womanOutfit).randomElement() ?? "a stylish outfit"
            : customOutfit
        let allure = isMan
            ? "Make him look handsome, elegant and attractive with a well-defined jawline, a fit physique and a confident, charismatic vibe — but attractive in a believable, human way, like a real good-looking person, not an exaggerated CGI model. Include subtle realistic facial-hair detail (light stubble or finely groomed beard) where it fits."
            : "Make her look beautiful, elegant and attractive in a tasteful way, with a believable, human beauty — like a real attractive person, not a flawless CGI doll."

        let target = swapTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject: String
        if target.isEmpty {
            subject = "Transform the main person in the photo into a genuinely attractive, good-looking \(person)."
        } else {
            subject = "In the photo, follow this instruction exactly: \(target). The resulting \(person) must look genuinely attractive and good-looking."
        }

        return """
        \(subject) Give them \(hair), wearing \(outfit). \(allure) \
        Adapt everything to this specific photo: match the exact lighting \
        direction, shadows, color grading, camera angle, lens perspective and \
        depth of field so the person blends in perfectly and looks like they \
        were really photographed in that scene with the same camera. \
        CRITICAL — the result must look like a 100% REAL photograph, never \
        AI-generated: render highly detailed, natural skin with visible pores, \
        fine skin texture and subtle, realistic imperfections (faint fine lines, \
        slight uneven skin tone, light freckles or minor blemishes), realistic \
        subsurface scattering and soft micro-shadows on the face. \
        Strictly AVOID any AI or 3D look: no plastic, waxy, glossy or rubbery \
        skin, no airbrushed or over-smoothed skin, no beauty-filter retouching, \
        no doll-like or CGI render, no perfect flawless symmetry, no overly \
        saturated colors, no glow, halo or outline artifacts. \
        Match real camera characteristics: natural sensor grain, true-to-life \
        skin tones and realistic dynamic range for the scene's lighting. \
        Keep lifelike eyes with natural catchlights and realistic individual \
        hair strands, and natural body proportions. Make the face look like a \
        unique, real human being. Keep the same pose, body position, framing \
        and background. Keep every other person in the photo unchanged. \
        No text or watermark in the image.
        """
    }

    /// Freier Bild-Editor: behält dieselbe Person bei, ändert nur, was die
    /// Anweisung verlangt (Outfit / zusätzliche Person), maximal fotorealistisch.
    private func makeFreeformEditPrompt() -> String {
        let instruction = editInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = instruction.isEmpty
            ? "Give the main person in the photo a stylish, well-fitting new outfit."
            : "Apply this edit to the photo exactly: \(instruction)."

        return """
        \(task) Keep the main person's identity perfectly intact: the exact same \
        face, facial features, hair, skin tone, body shape and proportions — only \
        change what the instruction asks for. If the instruction adds another \
        person, render that new person photorealistically and naturally integrated \
        into the scene. \
        Adapt everything to this specific photo: match the exact lighting \
        direction, shadows, color grading, camera angle, lens perspective and \
        depth of field so any change blends in perfectly. \
        CRITICAL — the result must look like a 100% REAL photograph, never \
        AI-generated: render highly detailed, natural skin with visible pores, \
        fine skin texture and subtle realistic imperfections, realistic \
        subsurface scattering and soft micro-shadows. \
        Strictly AVOID any AI or 3D look: no plastic, waxy or rubbery skin, no \
        airbrushed or over-smoothed skin, no beauty-filter retouching, no \
        doll-like or CGI render, no glow, halo or outline artifacts. \
        Keep lifelike eyes with natural catchlights and realistic individual hair \
        strands. Keep the same background, framing and composition unless the \
        instruction says otherwise. No text or watermark in the image.
        """
    }

    private func startGeneration() {
        focusedField = nil

        guard SeedanceAPI.hasAPIKey else {
            showMissingKeyAlert = true
            return
        }

        // Genug Guthaben? Sonst Paywall zeigen.
        guard store.canAfford(creditCost) else {
            showPaywall = true
            return
        }
        store.consume(creditCost)

        let project = VideoProject(
            prompt: finalPrompt,
            ratio: ratio,
            resolution: resolution,
            duration: duration,
            generateAudio: generateAudio,
            useFastModel: true,
            referenceImagesData: referenceImages,
            referenceVideoURLs: referenceVideoURLs,
            isImageOutput: isImageEdit || upscaleKind == "image",
            useKie: template?.useKie == true,
            upscaleKind: upscaleKind
        )
        generationManager.submit(project: project)
        onSubmitted()
        dismiss()
    }
}

// MARK: - Bild-Hilfen

extension UIImage {
    /// Verkleinert das Bild, damit Base64-Uploads klein bleiben.
    nonisolated func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
