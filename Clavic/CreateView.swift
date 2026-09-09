//
//  CreateView.swift
//  Clavic
//
//  Erstellen-Screen (modal): Video mit Seedance 2.0 aus Prompt +
//  Referenzbildern generieren. Optional mit Template vorbelegt.
//

import SwiftUI
import PhotosUI
import AVFoundation

struct CreateView: View {
    @Environment(GenerationManager.self) private var generationManager
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Optionales Template zur Vorbelegung
    let template: VideoTemplate?
    /// Wird nach erfolgreichem Start aufgerufen (z. B. Wechsel zur Bibliothek)
    var onSubmitted: (VideoProject) -> Void = { _ in }

    @State private var prompt = ""
    @State private var referenceImages: [Data] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var dualYouSelection: PhotosPickerItem?
    @State private var dualOpponentSelection: PhotosPickerItem?
    /// Motion Studio: vom Nutzer gewähltes Referenz-Video.
    @State private var motionVideoSelection: PhotosPickerItem?
    @State private var motionVideoData: Data?
    /// Motion-Templates: Länge „Auto" (= Länge des Eingangsvideos) vs. fester Wert.
    @State private var motionLengthAuto = true
    /// Gemessene Länge des gewählten Eingangsvideos (Sekunden), für „Auto".
    @State private var motionVideoDuration: Int?
    /// true, während das gewählte Video für den Upload aufbereitet (komprimiert/
    /// skaliert) wird → zeigt im UI „Preparing video…".
    @State private var motionVideoPreparing = false
    /// Motion: optionaler Vor-Edit fürs Foto (Nano Banana 2) — z. B. Hintergrund
    /// oder Person ändern, BEVOR Kling die Bewegung überträgt.
    @State private var motionEditPrompt = ""

    @State private var ratio: AspectRatio = .widescreen
    @State private var duration = 5
    @State private var generateAudio = true

    /// „Candid Späti": gewählte Szene + Vibe (Index in CandidPOV.scenes/.vibes).
    @State private var candidSceneIndex = 0
    @State private var candidVibeIndex = 0

    /// „Brainrot Character": gewählter Charakter + Text-/Background-Modus.
    @State private var brainrotCharId = Brainrot.chars.first?.id ?? ""
    @State private var brainrotUseCustomText = false
    @State private var brainrotText = ""
    @State private var brainrotBgMode: Brainrot.Background = .random
    @State private var brainrotBgSelection: PhotosPickerItem?
    @State private var brainrotBgData: Data?
    /// „Reden lassen": Charakter spricht den Text mit echter Stimme + Lip-Sync (Video).
    /// Standardmäßig AN – der Charakter SOLL reden (Aus = nur Standbild).
    @State private var brainrotTalk = true
    /// Optionaler Prompt, um am Bild/Charakter etwas zu ändern (z. B. „add sunglasses").
    @State private var brainrotImagePrompt = ""

    /// „AI Character": gewählte Attribute (Geschlecht/Haut/Augen/Haar) + optionaler
    /// Prompt. Kein Nutzerfoto – das Backend bekommt ein neutrales graues Seed-Bild.
    @State private var aiCharGender: AiCharacter.Gender = .woman
    @State private var luxuryCarBrand: LuxuryCar.Brand = .rollsRoyce
    @State private var aiCharSkin: AiCharacter.SkinTone = .fair
    @State private var aiCharEyes: AiCharacter.EyeColor = .blue
    @State private var aiCharHair: AiCharacter.HairColor = .brown
    @State private var aiCharExtra = ""
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
    /// Character-Insert: false = eigenen Hintergrund nutzen, true = KI erzeugt
    /// einen passenden dunklen, cinematischen Hintergrund.
    @State private var characterAddBackground = false

    /// Bild-Qualität (nur freier Bild-Editor): low=1K, medium=2K, high=4K.
    enum ImageQuality: String, CaseIterable, Identifiable {
        case low, medium, high
        var id: String { rawValue }
        var label: String {
            switch self { case .low: return "Standard"; case .medium: return "HD"; case .high: return "Ultra" }
        }
        // Nano Banana 2 (edit-fast) liefert mindestens 2K → low UND medium sind
        // real 2K; die UI zeigt daher nur noch Standard (2K) und Ultra (4K).
        var detail: String {
            switch self { case .low: return "2K"; case .medium: return "2K"; case .high: return "4K" }
        }
        /// In der Auswahl angezeigte Stufen (medium = identisch zu low → versteckt).
        static var selectable: [ImageQuality] { [.low, .high] }
    }
    @State private var imageQuality: ImageQuality = .low
    /// Alle Feineinstellungen liegen hinter einer Zeile. Vorbild: die
    /// „Advanced Settings"-Zeile, die AI-Bild-Apps durchgaengig nutzen —
    /// ein Screen zeigt Upload, Prompt, eine Zeile, einen Knopf. Nicht vier
    /// Abschnitte mit Chips.
    @State private var zeigeErweitert = false

    /// Vom Nutzer wählbare Auflösung für Seedance-2.0-Templates. Default 480p:
    /// 480p kostet halb so viele Credits wie 720p (resolutionFactor 1,0 vs 2,0)
    /// UND halb so viel API-Kosten. Da `upscaleVideoIfNeeded` 480p-Videos auf
    /// 1080p hochskaliert (auf dem Gerät, kostenlos), sieht 480p+Upscale sogar
    /// schärfer aus als raw 720p — Verbrauch und Nutzpreis halbieren sich, ohne
    /// spürbaren Qualitätsverlust. 720p bleibt teurer wählbar.
    @State private var resolution: Resolution = .p480

    @State private var showMissingKeyAlert = false
    // Synchroner Schutz gegen Mehrfach-Tap: verhindert, dass schnelle Taps
    // (auch während der Dismiss-Animation) MEHRERE Generierungen + Credit-Abzüge
    // auslösen. @State-Wert wird sofort geschrieben → Re-Entry wird sofort geblockt.
    @State private var isSubmitting = false
    @State private var showPaywall = false
    @State private var showSubscriptionGate = false
    @State private var showFileTooLargeAlert = false
    @State private var contentPolicyMessage: String?
    /// Einmaliges Einwilligungs-/Content-Policy-Gate vor dem ersten Foto-Upload.
    @AppStorage("acceptedContentPolicy") private var acceptedContentPolicy = false
    @State private var showConsent = false
    @State private var pendingPhotoItems: [PhotosPickerItem] = []
    /// Pinterest-Swap: zwei eigene Bilder (Inspo + Selfie) als feste Slots.
    @State private var pinInspoData: Data?
    @State private var pinSelfieData: Data?
    @State private var inspoSelection: PhotosPickerItem?
    @State private var selfieSelection: PhotosPickerItem?
    @State private var pendingPinItem: (item: PhotosPickerItem, isInspo: Bool)?
    /// Brainrot-Build: Charakter-Auswahl (Tung Tung / frucht-köpfig / eigene Figur).
    enum BuildCharacter: String, CaseIterable, Identifiable {
        case tung, fruit, custom
        var id: String { rawValue }
        var label: String {
            switch self { case .tung: return "Tung Tung"; case .fruit: return "Fruit figure"; case .custom: return "Your figure" }
        }
        var icon: String {
            switch self { case .tung: return "figure.stand"; case .fruit: return "leaf.fill"; case .custom: return "photo.badge.plus" }
        }
    }
    @State private var buildCharacter: BuildCharacter = .tung
    @State private var buildCustomSelection: PhotosPickerItem?
    @State private var buildCustomData: Data?
    /// AI Fruit Story: gewählte Charaktere (geordnet = Cast-Reihenfolge), Preset,
    /// Stil und – bei Custom – die eigene Story-Idee.
    @State private var fruitCharacterOrder: [String] = []
    @State private var fruitPresetId: String = FruitStoryCatalog.presets.first?.id ?? "cheating"
    @State private var fruitStyleId: String = FruitStoryCatalog.styles.first?.id ?? "cinematic"
    @State private var fruitCustomIdea: String = ""
    /// Maximale Anzahl Charaktere pro Story (Cast-Größe).
    private let maxFruitCharacters = 4
    private enum Field: Hashable { case prompt, target, outfit }
    @FocusState private var focusedField: Field?

    private let maxReferenceImages = 4
    /// Pinterest-Swap: Anzahl generierter Varianten (1 exakt + 3 andere Posen).
    private let pinterestVariantCount = 2

    /// Geführter „Fix"-Modus: kein Prompt, nur Foto + Hintergrund + Generieren.
    private var isFixed: Bool { template?.isFixed == true }
    /// Zwei-Personen-Video (z. B. Du + Gegner) – braucht genau 2 Fotos.
    private var isDualPersonVideo: Bool { (template?.requiredPhotoCount ?? 1) >= 2 }

    /// Bild-Trend (Nano Banana 2 Edit): Foto + kurzer Prompt → ein Bild.
    private var isImageEdit: Bool { template?.isImageEdit == true }

    /// Freier Bild-Editor: Foto + Anweisung (Outfit ändern / Person hinzufügen).
    private var isFreeformEdit: Bool { template?.isFreeformEdit == true }

    /// Character-Insert: fester Charakter (z. B. Pirat) wird ins Nutzerfoto
    /// eingefügt – nur Foto nötig, keine Texteingabe.
    private var isCharacterInsert: Bool { template?.characterRefAsset != nil }

    /// Pose-/Face-Template: festes Modell-Bild, das Gesicht der Nutzerin wird
    /// daraufgetauscht (Outfit/Pose bleiben) – nur Foto nötig, keine Texteingabe.
    private var isFaceTemplate: Bool { template?.faceTemplateAsset != nil }

    /// Fester-Prompt-Edit (z. B. Action Figure): Nutzerfoto + fester Prompt –
    /// nur Foto nötig, keine Texteingabe.
    private var isFixedEdit: Bool { template?.fixedEditPrompt != nil }

    /// Pinterest-Swap: zwei eigene Bilder (Inspo + Selfie), Gesicht wird getauscht.
    private var isPinterestSwap: Bool { template?.isPinterestSwap == true }

    /// Foto-Enhance / „8K Upscale": ein Foto → Nano Banana 2 baut es in max.
    /// Qualität (4K) fotoreal neu auf. Ein-Tap, immer Höchstqualität + Auto-Ratio.
    private var isPhotoEnhance: Bool { template?.isPhotoEnhance == true }

    /// „Still Life" / Backrooms-Memory: Foto → zufällig verzerrte Backrooms-
    /// Version (jedes Mal anders). Ein-Tap, kein Texteingabefeld.
    private var isStillLife: Bool { template?.isStillLife == true }

    /// „Candid Späti": fotoreal wirkender Schnappschuss. Prompt wird aus
    /// gewählter Szene + Vibe + 1–2 Fotos zusammengebaut (fester Realismus-Wrapper).
    private var isCandidPOV: Bool { template?.isCandidPOV == true }

    /// „Brainrot Character"-Generator (Charakter aus Asset, kein Nutzerfoto).
    private var isBrainrotCharacter: Bool { template?.isBrainrotCharacter == true }
    private var selectedBrainrotChar: BrainrotChar { Brainrot.char(brainrotCharId) ?? Brainrot.chars[0] }

    /// „AI Character"-Generator (einzigartige fotoreale Person, kein Nutzerfoto).
    private var isAiCharacter: Bool { template?.isAiCharacter == true }

    /// Luxury Car Selfie: Selfie + Automarke → Luxus-Interieur.
    private var isLuxuryCarSelfie: Bool { template?.isLuxuryCarSelfie == true }

    /// Brainrot-DIY-Build („Tung Tung baut ein Haus").
    private var isBrainrotBuild: Bool { template?.isBrainrotBuild == true }
    /// Generische Build-Variante (Riesen-Objekt, kein Foto nötig).
    private var isBrainrotBuildGeneric: Bool { isBrainrotBuild && template?.brainrotPersonalized != true }

    /// AI Fruit Story: Charakter-/Preset-/Stil-Auswahl, dann sprechendes
    /// Frucht-Drama (FruitStoryPipeline). Kein eigenes Foto nötig.
    private var isFruitStory: Bool { template?.isFruitStory == true }

    /// Upscale-Werkzeug: Datei hochladen → hochskalieren.
    private var upscaleKind: String? { template?.upscaleKind }
    private var isUpscale: Bool { template?.isUpscale == true }
    private var isVideoUpscale: Bool { upscaleKind == "video" }

    /// Motion Studio: eigenes Foto + eigenes Video + Prompt.
    private var isMotion: Bool { template?.isMotion == true }
    /// 720p fest — nur Motion Control (Reference-Video braucht Mindestqualität).
    private var locksResolution720: Bool { isMotion }

    /// Freie Video-Generierung mit Text-Prompt → Composer unten an der Tastatur.
    private var isPromptMode: Bool { !isUpscale && !isImageEdit && !isFixed && !isFruitStory && !isAiCharacter && !isMotion }

    /// Maximale Upload-Größe fürs Video-Upscale. Muss als Base64 (+33 %) plus
    /// JSON unter Vercels ~4,5 MB Request-Limit bleiben → 3,0 MB Binärdatei
    /// ≈ 4,0 MB Base64 (sonst HTTP 413 FUNCTION_PAYLOAD_TOO_LARGE).
    private let maxVideoUploadBytes = 3_000_000

    private var canGenerate: Bool {
        if isFruitStory {
            // Mindestens ein Charakter + (kein Custom ODER eine eigene Idee).
            guard !fruitCharacterOrder.isEmpty else { return false }
            if FruitStoryCatalog.preset(id: fruitPresetId)?.isCustom == true {
                return !fruitCustomIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
        if isBrainrotBuildGeneric {
            // Custom-Figur braucht einen Upload; Tung/Frucht sind gestellt.
            return buildCharacter != .custom || buildCustomData != nil
        }
        if isPinterestSwap {
            return pinInspoData != nil && pinSelfieData != nil
        }
        if isMotion {
            return !referenceImages.isEmpty && motionVideoData != nil
        }
        if isBrainrotCharacter {
            // Charakter kommt aus Asset → immer generierbar (eigenes Hintergrundbild optional).
            return brainrotBgMode != .own || brainrotBgData != nil
        }
        if isAiCharacter {
            // Braucht kein Nutzerfoto – immer generierbar.
            return true
        }
        if isUpscale || isImageEdit || isFixed {
            if isDualPersonVideo {
                return referenceImages.count >= 2
                    && referenceImages[0].isEmpty == false
                    && referenceImages[1].isEmpty == false
            }
            return !referenceImages.isEmpty
        }
        return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var creditCost: Int {
        // Brainrot „reden lassen": Video-Pipeline (Bild + Seedance + TTS + Lip-Sync).
        if isBrainrotCharacter && brainrotTalk {
            return CreditCosts.musicVideo(key: "brainrot_talk", resolution: .p720)
        }
        if template?.useMusicLipSync == true {
            return CreditCosts.musicVideo(key: template?.musicVideoKey ?? "", resolution: resolution)
        }
        if isImageEdit {
            if isPhotoEnhance { return CreditCosts.photoEnhance }
            // AI Character: Kosten nach gewählter Qualität (1K/2K/4K).
            if isAiCharacter { return CreditCosts.imageEditCredits(quality: imageQuality.rawValue) }
            // Pinterest-Swap erzeugt 4 Bilder (1 exakt + 3 Posen) → 4× Kosten.
            if isPinterestSwap { return CreditCosts.imageEditCredits(quality: imageQuality.rawValue) * pinterestVariantCount }
            return isFreeformEdit ? CreditCosts.imageEditCredits(quality: imageQuality.rawValue) : CreditCosts.imageEdit
        }
        if upscaleKind == "image" { return CreditCosts.imageUpscale }
        if upscaleKind == "video" { return CreditCosts.videoUpscale }
        if template?.useKlingMotion == true { return CreditCosts.klingMotionControl }
        // Video-Generierung: nach gewählter Länge, Auflösung + ob ein Referenz-Video genutzt wird.
        let hasReferenceVideo = !referenceVideoURLs.isEmpty || template?.referenceVideoURL != nil
        // Motion-Foto-Vor-Edit (Nano Banana 2) kostet 1 Bild-Credit extra.
        let preEdit = (isMotion && !motionEditPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? CreditCosts.imageEdit : 0
        return CreditCosts.video(seconds: duration, hasReferenceVideo: hasReferenceVideo, resolution: resolution) + preEdit
    }

    /// Zeigt dieses Template die Auflösungs-Auswahl? (Nur Seedance 2.0.)
    private var showsResolutionPicker: Bool { template?.usesSeedance == true }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if isUpscale {
                            upscaleUploadSection
                            generateButton
                        } else if isPinterestSwap {
                            // Beim Betreten stehen NUR die beiden Felder da.
                            // Groesse und Qualitaet erscheinen erst, wenn beide
                            // Fotos liegen — vorher ist die Wahl bedeutungslos
                            // und der Screen sieht aus wie ein Formular.
                            pinterestSwapSection
                            if pinInspoData != nil && pinSelfieData != nil {
                                erweiterteZeile {
                                    VStack(spacing: 20) {
                                        imageSizeSection
                                        imageQualitySection
                                    }
                                }
                            }
                            generateButton
                        } else if isPhotoEnhance {
                            // 8K Upscale: nur Foto + Generieren (immer max. Qualität,
                            // Original-Seitenverhältnis bleibt).
                            if referenceImages.isEmpty {
                                photoHintBanner
                            }
                            guidedPhotoSection
                            generateButton
                        } else if isBrainrotBuildGeneric {
                            // DIY-Build: Charakter wählen (Tung Tung / frucht-köpfig /
                            // eigene Figur hochladen), dann Auflösung + Generieren.
                            brainrotBuildInfo
                            buildCharacterSection
                            resolutionSection
                                .frame(maxWidth: .infinity, alignment: .leading)
                            generateButton
                        } else if isFruitStory {
                            // AI Fruit Story: Cast wählen, Story-Preset, Stil – der
                            // Backend-Planner schreibt daraus jedes Mal eine neue Story.
                            fruitStoryInfo
                            fruitCharacterSection
                            fruitPresetSection
                            if FruitStoryCatalog.preset(id: fruitPresetId)?.isCustom == true {
                                fruitCustomIdeaSection
                            }
                            fruitStyleSection
                            generateButton
                        } else if isBrainrotCharacter {
                            // Charakter-Generator: Grid + Text + Background (kein Nutzerfoto).
                            brainrotSection
                            generateButton
                        } else if isAiCharacter {
                            // AI Character: Attribut-Auswahl + optionaler Prompt (kein Nutzerfoto).
                            aiCharacterSection
                            imageSizeSection
                            imageQualitySection
                            generateButton
                        } else if isImageEdit {
                            if referenceImages.isEmpty {
                                photoHintBanner
                            }
                            guidedPhotoSection
                            attachedImagesRow
                            // Bildgröße/Format wählbar bei allen Bild-Edit-Templates,
                            // außer Candid (fest 9:16, damit es real wirkt).
                            if !isCandidPOV { imageSizeSection }
                            // Character-Insert braucht keine Texteingabe → fester
                            // Generieren-Button. Sonst schwebt der editComposer unten.
                            if isCharacterInsert {
                                characterBackgroundSection
                                generateButton
                            } else if isCandidPOV {
                                candidPOVSection
                                generateButton
                            } else if isLuxuryCarSelfie {
                                luxuryCarSection
                                generateButton
                            } else if isFaceTemplate || isFixedEdit || isStillLife {
                                generateButton
                            } else if isFreeformEdit {
                                editPresetsSection
                                imageQualitySection
                            }
                            // Text-Eingabe + Senden schweben unten über der
                            // Tastatur (siehe .safeAreaInset → editComposer).
                        } else if isFixed {
                            if isDualPersonVideo {
                                dualPersonPhotoSection
                            } else {
                                guidedPhotoSection
                            }
                            // Hintergrund-Auswahl nur, wenn das Template einen
                            // Foto-Hintergrund unterstützt. Sonst wird immer der
                            // Hintergrund/Look aus dem Video genommen.
                            if template?.promptPhotoBackground != nil {
                                backgroundChoiceSection
                            }
                            resolutionSection
                                .frame(maxWidth: .infinity, alignment: .leading)
                            generateButton
                        } else {
                            if let template, template.needsPhoto, referenceImages.isEmpty {
                                photoHintBanner
                            }
                            if isMotion {
                                // Geführter Flow: Foto + Video + Settings + Generieren.
                                // KEIN Prompt-Composer — der interne Motion-Prompt ist
                                // Technik und würde Nutzer nur verwirren.
                                guidedPhotoSection
                                motionVideoSection
                                motionSettingsSection
                                generateButton
                            } else {
                                settingsSection
                            }
                            attachedImagesRow
                            // promptComposer ist unten an der Tastatur gepinnt
                            // (siehe .safeAreaInset), damit man beim Tippen sieht
                            // was man schreibt – sauber über der Tastatur.
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
                // Schwebende Eingabe-Karte (wie Halo): liegt frei über dem Inhalt,
                // gleitet beim Antippen über die Tastatur hoch und beim Fertig
                // wieder zurück. Kein vollbreiter Hintergrund → wirkt nicht „fix".
                .safeAreaInset(edge: .bottom) {
                    if isPromptMode {
                        VStack(spacing: 8) {
                            if focusedField == .prompt { creditCostHint }
                            promptComposer
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.bottom, 8)
                        .animation(.easeOut(duration: 0.22), value: focusedField)
                    } else if isImageEdit && !isCharacterInsert && !isFaceTemplate && !isFixedEdit && !isPinterestSwap && !isStillLife && !isCandidPOV && !isBrainrotCharacter && !isAiCharacter && !isLuxuryCarSelfie {
                        VStack(spacing: 8) {
                            if focusedField == .target { creditCostHint }
                            editComposer
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.bottom, 8)
                        .animation(.easeOut(duration: 0.22), value: focusedField)
                    }
                }
                .onChange(of: photoSelection) { _, newItems in
                    handlePhotoSelection(newItems)
                }
                .onChange(of: dualYouSelection) { _, item in
                    handleDualPhotoSelection(item, slot: 0)
                }
                .onChange(of: dualOpponentSelection) { _, item in
                    handleDualPhotoSelection(item, slot: 1)
                }
                .onChange(of: inspoSelection) { _, item in
                    handlePinSelection(item, isInspo: true)
                }
                .onChange(of: selfieSelection) { _, item in
                    handlePinSelection(item, isInspo: false)
                }
                .onChange(of: buildCustomSelection) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let jpeg = image.resized(maxDimension: 1024).jpegData(compressionQuality: 0.9) {
                            withAnimation(.spring(duration: 0.3)) { buildCustomData = jpeg }
                        }
                    }
                }
                .onChange(of: motionVideoSelection) { _, item in
                    guard let item else { return }
                    Task {
                        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
                        motionVideoPreparing = true
                        // Beliebige Länge/Größe erlaubt: das Video wird für den Upload
                        // aufbereitet – zu kleine Clips werden hoch-, zu große runter-
                        // skaliert/komprimiert (Vercel-Body-Limit ~4,5 MB). KEIN hartes
                        // MB-Limit mehr beim Auswählen.
                        let prepared = await Self.preparedMotionVideo(raw)
                        let secs = await Self.videoDurationSeconds(prepared)
                        motionVideoPreparing = false
                        if prepared.count > maxVideoUploadBytes { showFileTooLargeAlert = true; return }
                        withAnimation(.spring(duration: 0.3)) {
                            motionVideoData = prepared
                            motionVideoDuration = secs
                        }
                    }
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
            }
            .alert("No connection", isPresented: $showMissingKeyAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The server is currently unreachable. Please try again in a moment.")
            }
            .alert("Video too large", isPresented: $showFileTooLargeAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This video is too large to upload. Please pick a shorter or lower-resolution clip.")
            }
            .alert("Before you upload", isPresented: $showConsent) {
                Button("I agree & continue") {
                    acceptedContentPolicy = true
                    let items = pendingPhotoItems
                    pendingPhotoItems = []
                    processPhotoSelection(items)
                    if let pin = pendingPinItem {
                        pendingPinItem = nil
                        loadPinPhoto(pin.item, isInspo: pin.isInspo)
                    }
                }
                Button("View policy") {
                    openURL(LegalLinks.terms)
                }
                Button("Cancel", role: .cancel) {
                    pendingPhotoItems = []
                    pendingPinItem = nil
                }
            } message: {
                Text("Only upload photos of yourself or people who have given you permission. Do not create sexual, romantic intimate-contact, hateful, deceptive or otherwise harmful content, or impersonate others. By continuing you confirm you have the rights to the photo and agree to our content policy.")
            }
            .alert("Content not supported", isPresented: Binding(
                get: { contentPolicyMessage != nil },
                set: { if !$0 { contentPolicyMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(contentPolicyMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showSubscriptionGate) {
            PaywallView()
        }
        .sheet(isPresented: $showPaywall) {
            CreditsView()
        }
        .onAppear(perform: applyTemplate)
    }

    private var navigationTitle: String {
        if isUpscale { return isVideoUpscale ? "Video Upscale" : "Image Upscale" }
        if isPhotoEnhance { return template?.title ?? "Enhance" }
        // Brainrot: „Make them talk" (Default an) erzeugt ein VIDEO.
        if isBrainrotCharacter { return brainrotTalk ? "Create Video" : "Create Image" }
        if isImageEdit { return "Create Image" }
        return "Create Video"
    }

    private func applyTemplate() {
        guard let template, prompt.isEmpty else { return }
        prompt = template.prompt
        ratio = template.ratio
        duration = template.duration
        // Seedance 2.0 / Kling Motion Control (reference-to-video) unterstützen
        // KEIN 480p → würde mit „video quality too low … 480p" abbrechen.
        // Daher für Motion immer 720p ausgeben.
        if template.isMotion { resolution = .p720 }
        // AI-Action-Templates + You're Next: 480p (günstigste API).
        if template.seedanceModel != nil { resolution = .p480 }
        if let videoURL = template.referenceVideoURL {
            referenceVideoURLs = [videoURL]
        }

        // QA/Test: Vorbelegung eines festen Referenzfotos als @Image1.
        // Das ist speziell für Motion/Music-LipSync-Templates gedacht,
        // damit du nur die Person-Quelle austauschst und prüfst, ob
        // das Video (Bewegung/Timing) gleich bleibt.
        if let assetName = template.presetPhotoAsset, referenceImages.isEmpty {
            if let img = UIImage(named: assetName),
               let jpeg = img.jpegForAPIUpload(maxDimension: 768, quality: 0.72) {
                let slots = max(1, template.requiredPhotoCount)
                referenceImages = Array(repeating: jpeg, count: slots)
            }
        }
    }

    // MARK: - Upscale-Upload

    private var upscaleUploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.10), Theme.accent.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14))
                    Image(systemName: isVideoUpscale ? "video.badge.plus" : "photo.badge.plus")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 74, height: 74)
                Text(isVideoUpscale ? "Add a video" : "Add a photo")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(isVideoUpscale ? "It gets upscaled to higher quality"
                                    : "It gets sharper and bigger")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Theme.accent.opacity(0.12), radius: 16, y: 8)
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
                Text("TREND")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
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

    /// Info-Banner für die generische Build-Variante (kein Foto nötig).
    private var brainrotBuildInfo: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Pick a builder, tap Generate – it builds a luxury home inside a random giant object. Every video is a new story.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
    }

    /// DIY-Build: Charakter-Auswahl + optionaler Upload einer eigenen Figur.
    private var buildCharacterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Builder", subtitle: "Who builds the house?")
            HStack(spacing: 8) {
                ForEach(BuildCharacter.allCases) { c in
                    SelectableChip(title: c.label, icon: c.icon, isSelected: buildCharacter == c) {
                        withAnimation(.spring(duration: 0.25)) { buildCharacter = c }
                    }
                }
                Spacer(minLength: 0)
            }
            if buildCharacter == .custom {
                PhotosPicker(selection: $buildCustomSelection, matching: .images) {
                    if let data = buildCustomData, let image = UIImage(data: data) {
                        ZStack(alignment: .bottomTrailing) {
                            Color.black.opacity(0.04)
                            Image(uiImage: image).resizable().scaledToFit()
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath"); Text("Change")
                            }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(.black.opacity(0.55), in: Capsule()).padding(10)
                        }
                        .frame(height: 240).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 30, weight: .medium)).foregroundStyle(Theme.accent)
                            Text("Add your figure").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                            Text("It gets restyled into a brainrot 3D character").font(.system(size: 11)).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).frame(height: 150)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - AI Fruit Story

    private var fruitStoryInfo: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Pick your fruit cast, choose a drama, tap Generate. The AI writes a brand-new talking-fruit story every time.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
    }

    /// Charakter-Auswahl (Mehrfachauswahl, Reihenfolge = Cast-Reihenfolge).
    private var fruitCharacterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cast", subtitle: "Pick up to \(maxFruitCharacters) characters – the order is the cast order.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 12) {
                ForEach(FruitStoryCatalog.characters) { c in
                    fruitCharacterTile(c)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fruitCharacterTile(_ c: FruitCharacter) -> some View {
        let index = fruitCharacterOrder.firstIndex(of: c.id)
        let isSelected = index != nil
        return Button {
            withAnimation(.spring(duration: 0.25)) { toggleFruitCharacter(c.id) }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let img = UIImage(named: c.asset) {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            ZStack {
                                LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.12)],
                                               startPoint: .top, endPoint: .bottom)
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 2.5 : 1)
                    )
                    if let index {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Theme.accent, in: Circle())
                            .padding(6)
                    }
                }
                Text(c.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Story-Preset (Cheating / Baby / … / Custom).
    private var fruitPresetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Story", subtitle: "Choose a drama – or write your own.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FruitStoryCatalog.presets) { p in
                        SelectableChip(title: p.label, icon: p.icon, isSelected: fruitPresetId == p.id) {
                            withAnimation(.spring(duration: 0.25)) { fruitPresetId = p.id }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Eigene Story-Idee (nur bei Preset „Custom").
    private var fruitCustomIdeaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your story", subtitle: "Describe the fruit drama you want.")
            TextField("e.g. Orange Mom finds Banana's secret phone messages…",
                      text: $fruitCustomIdea, axis: .vertical)
                    .submitLabel(.done)
                    .onSubmit { hideKeyboard() }
                .lineLimit(3...6)
                .focused($focusedField, equals: .prompt)
                .font(.system(size: 15))
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Visueller Stil (Cinematic / Cute / Drama Comedy / Dark Drama).
    private var fruitStyleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Style", subtitle: "The visual look of your story.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FruitStoryCatalog.styles) { s in
                        SelectableChip(title: s.label, icon: s.icon, isSelected: fruitStyleId == s.id) {
                            withAnimation(.spring(duration: 0.25)) { fruitStyleId = s.id }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleFruitCharacter(_ id: String) {
        if let idx = fruitCharacterOrder.firstIndex(of: id) {
            fruitCharacterOrder.remove(at: idx)
        } else if fruitCharacterOrder.count < maxFruitCharacters {
            fruitCharacterOrder.append(id)
        }
    }

    private func orderedSelectedCharacters() -> [FruitCharacter] {
        fruitCharacterOrder.compactMap { FruitStoryCatalog.character(id: $0) }
    }

    /// Baut die JSON-Konfiguration, die in `project.prompt` an die Pipeline geht.
    private func fruitConfigJSON() -> String {
        let chosen = orderedSelectedCharacters()
        let preset = FruitStoryCatalog.preset(id: fruitPresetId)
        let idea = (preset?.isCustom == true)
            ? fruitCustomIdea.trimmingCharacters(in: .whitespacesAndNewlines)
            : (preset?.storyIdea ?? "")
        let config: [String: Any] = [
            "presetId": fruitPresetId,
            "storyIdea": idea,
            "styleId": fruitStyleId,
            "sceneCount": FruitStoryCatalog.defaultSceneCount,
            "characters": chosen.map { $0.name },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: config),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
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

    /// Zwei-Personen-Trend: Du (Szene 1 + Vordergrund) + Gegner (Spotlight).
    private var dualPersonPhotoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Two photos",
                subtitle: "Left: you (full look for scene 1 + over-the-shoulder). Right: opponent — their real outfit is used, not face-swap."
            )
            HStack(spacing: 12) {
                dualPhotoSlot(
                    label: "You",
                    placeholder: "Your photo",
                    icon: "person.crop.square.badge.camera",
                    data: referenceImages.indices.contains(0) ? referenceImages[0] : nil,
                    selection: $dualYouSelection
                )
                dualPhotoSlot(
                    label: "Opponent",
                    placeholder: "Their photo",
                    icon: "person.fill.viewfinder",
                    data: referenceImages.indices.contains(1) ? referenceImages[1] : nil,
                    selection: $dualOpponentSelection
                )
            }
        }
    }

    private func dualPhotoSlot(
        label: String,
        placeholder: String,
        icon: String,
        data: Data?,
        selection: Binding<PhotosPickerItem?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            PhotosPicker(selection: selection, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    if let data, let image = UIImage(data: data) {
                        Color.black.opacity(0.04)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Change")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 9)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(8)
                    } else {
                        // Gestaltete Flaeche statt gestricheltem Kasten: weicher
                        // Verlauf, rundes Symbolabzeichen, kein Strichrahmen.
                        ZStack {
                            LinearGradient(colors: [Theme.accent.opacity(0.10),
                                                    Theme.accent.opacity(0.03)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(Theme.accent.opacity(0.14))
                                    Image(systemName: icon)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                                .frame(width: 56, height: 56)
                                Text(placeholder)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                        .strokeBorder(data == nil ? Theme.accent.opacity(0.22) : Theme.stroke,
                                      lineWidth: 1)
                )
                .shadow(color: Theme.accent.opacity(0.12), radius: 14, y: 6)
            }
        }
    }

    private func handleDualPhotoSelection(_ item: PhotosPickerItem?, slot: Int) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = image.jpegForAPIUpload(maxDimension: 768, quality: 0.72) {
                withAnimation(.spring(duration: 0.3)) {
                    if referenceImages.count <= slot {
                        referenceImages.append(contentsOf: Array(repeating: Data(), count: slot + 1 - referenceImages.count))
                    }
                    referenceImages[slot] = jpeg
                }
            }
        }
    }

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
            TextField("Describe your video …", text: $prompt, axis: .vertical)
                .focused($focusedField, equals: .prompt)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)

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

    /// Von Seedance 2.0 / Kling (r2v) unterstützte Ausgabelängen. Andere Werte
    /// (z. B. 8 s) werden vom Modell ignoriert → es liefert die Default-Länge (5 s).
    private let motionDurations = [5, 10]

    /// Rundet eine gemessene Länge auf die nächste UNTERSTÜTZTE Länge
    /// (8 s → 10 s), damit „Auto" nicht heimlich auf 5 s zurückfällt.
    private func snapMotionDuration(_ seconds: Int) -> Int {
        motionDurations.min(by: { abs($0 - seconds) < abs($1 - seconds) }) ?? 5
    }

    /// Tatsächliche „Auto"-Ausgabelänge (gemessen → gerundet auf unterstützte Länge).
    private var motionAutoDuration: Int? { motionVideoDuration.map(snapMotionDuration) }

    /// Motion-Templates: Länge (Auto = wie Eingangsvideo, oder fest) + Auflösung + Audio.
    private var motionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Optionaler Foto-Vor-Edit (Nano Banana 2): Hintergrund/Person ändern,
            // bevor die Bewegung übertragen wird — schnell im selben Template.
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "Edit your photo first (optional)",
                    subtitle: "Change the background or the person before the motion is applied."
                )
                TextField("e.g. change background to a beach, put me in a red dress…", text: $motionEditPrompt, axis: .vertical)
                    .submitLabel(.done)
                    .onSubmit { hideKeyboard() }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Length")
                HStack(spacing: 8) {
                    SelectableChip(
                        title: motionAutoDuration.map { "Auto · \($0)s" } ?? "Auto",
                        icon: "wand.and.stars",
                        isSelected: motionLengthAuto
                    ) { withAnimation(.spring(duration: 0.25)) { motionLengthAuto = true } }
                    ForEach(motionDurations, id: \.self) { sec in
                        SelectableChip(title: "\(sec)s", isSelected: !motionLengthAuto && duration == sec) {
                            withAnimation(.spring(duration: 0.25)) { motionLengthAuto = false; duration = sec }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            // 480p / 720p (Seedance 2.0 & Kling 3.0).
            resolutionSection

            // Audio an/aus (Dialog/SFX/Musik vom Modell, oder stummes Video).
            VStack(spacing: 0) {
                toggleRow(
                    icon: "speaker.wave.2.fill",
                    title: "Generate audio",
                    subtitle: "Add matching sound to the video, or keep it silent",
                    isOn: $generateAudio
                )
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Misst die Länge eines Videos (für „Auto"), begrenzt auf einen sinnvollen Bereich.
    nonisolated static func videoDurationSeconds(_ data: Data) async -> Int? {
        let url = URL.temporaryDirectory.appending(path: "motiondur-\(UUID().uuidString).mov")
        do {
            try data.write(to: url)
            let dur = try await AVURLAsset(url: url).load(.duration)
            try? FileManager.default.removeItem(at: url)
            let s = Int(dur.seconds.rounded())
            return s > 0 ? min(max(s, 3), 15) : nil
        } catch { return nil }
    }

    /// Bereitet ein gewähltes Motion-Referenzvideo für den Upload auf. Seedance/
    /// Kling (r2v) wollen ein **720p**-Referenzvideo (sonst „video quality too
    /// low"). Gleichzeitig muss es klein genug fürs Backend bleiben (Vercel-Body
    /// ~4,5 MB, Base64 + Foto → ~2,6 MB Video). Daher: auf **kurze Seite = 720**
    /// skalieren (klein → hoch, groß → runter) und per AVAssetWriter mit gezielter
    /// **Bitrate** neu kodieren, sodass die Datei ins Budget passt. Audio wird
    /// weggelassen (für Motion irrelevant → mehr Budget fürs Bild). So lassen sich
    /// auch 8–12 s-Clips in guter Qualität einfügen.
    nonisolated static func preparedMotionVideo(_ data: Data) async -> Data {
        let maxBytes = 2_600_000
        let targetShort: CGFloat = 720
        let srcURL = URL.temporaryDirectory.appending(path: "motionsrc-\(UUID().uuidString).mov")
        func rm(_ u: URL) { try? FileManager.default.removeItem(at: u) }
        do {
            try data.write(to: srcURL)
            let asset = AVURLAsset(url: srcURL)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { rm(srcURL); return data }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let oriented = natural.applying(transform)
            let w = abs(oriented.width), h = abs(oriented.height)
            guard w > 0, h > 0 else { rm(srcURL); return data }
            let duration = try await asset.load(.duration)
            let durSecs = max(duration.seconds, 0.5)
            var fps = (try? await track.load(.nominalFrameRate)) ?? 30
            if fps <= 0 || fps > 60 { fps = 30 }

            // Kurze Seite auf 720 bringen (hoch- oder runterskalieren), Seitenverhältnis halten.
            let shortSide = min(w, h)
            let scale = targetShort / shortSide
            func evenScaled(_ v: CGFloat) -> Int {
                var r = Int((v * scale).rounded())
                if r % 2 != 0 { r += 1 }
                return max(r, 2)
            }
            let target = CGSize(width: evenScaled(w), height: evenScaled(h))

            // Schon ~720p UND klein genug → unverändert lassen (kein Re-Encoding).
            if data.count <= maxBytes && shortSide >= 700 && shortSide <= 820 { rm(srcURL); return data }

            // Skalierung + Orientierung über eine Video-Composition (auf 720p bringen).
            let vcomp = AVMutableVideoComposition()
            vcomp.renderSize = target
            vcomp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(fps.rounded(), 1)))
            let instr = AVMutableVideoCompositionInstruction()
            instr.timeRange = CMTimeRange(start: .zero, duration: duration)
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            li.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
            instr.layerInstructions = [li]
            vcomp.instructions = [instr]

            // 1) Präziser AVAssetWriter-Transcode (Bitrate steuerbar, ohne Audio).
            let bitrate = max(1_000_000, min(6_000_000, Int(Double(maxBytes) * 8 / durSecs * 0.92)))
            if let out = await writerTranscode(asset: asset, track: track, comp: vcomp, target: target, bitrate: bitrate, fps: fps),
               out.count <= maxBytes + 300_000 {
                rm(srcURL); return out
            }

            // 2) Fallback: AVAssetExportSession skaliert ebenfalls auf 720p, ist aber
            //    deutlich kompatibler mit ungewöhnlichen Formaten/Codecs. Qualität
            //    absteigend, bis es ins Budget passt → so wird NIE das zu kleine
            //    Original gesendet, nur weil der erste Pfad scheiterte.
            for preset in [AVAssetExportPresetMediumQuality, AVAssetExportPresetLowQuality, AVAssetExportPresetHighestQuality] {
                if let out = await exportTranscode(asset: asset, comp: vcomp, preset: preset), out.count <= maxBytes {
                    rm(srcURL); return out
                }
            }
            rm(srcURL); return data
        } catch {
            rm(srcURL); return data
        }
    }

    /// Skaliert per AVAssetReader→AVAssetWriter auf `target` mit fester Bitrate (Video-only).
    private nonisolated static func writerTranscode(asset: AVURLAsset, track: AVAssetTrack, comp: AVMutableVideoComposition, target: CGSize, bitrate: Int, fps: Float) async -> Data? {
        let outURL = URL.temporaryDirectory.appending(path: "motionw-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)
        do {
            let reader = try AVAssetReader(asset: asset)
            let rOut = AVAssetReaderVideoCompositionOutput(
                videoTracks: [track],
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            )
            rOut.videoComposition = comp
            rOut.alwaysCopiesSampleData = false
            guard reader.canAdd(rOut) else { return nil }
            reader.add(rOut)
            let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
            let wIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(target.width),
                AVVideoHeightKey: Int(target.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: Int(max(fps.rounded(), 1)) * 2
                ]
            ])
            wIn.expectsMediaDataInRealTime = false
            guard writer.canAdd(wIn) else { return nil }
            writer.add(wIn)
            guard reader.startReading(), writer.startWriting() else { return nil }
            writer.startSession(atSourceTime: .zero)
            let queue = DispatchQueue(label: "clavic.motion.transcode")
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                wIn.requestMediaDataWhenReady(on: queue) {
                    while wIn.isReadyForMoreMediaData {
                        if reader.status == .reading, let sb = rOut.copyNextSampleBuffer() {
                            if !wIn.append(sb) {   // Append-Fehler → nicht endlos drehen.
                                reader.cancelReading()
                                wIn.markAsFinished()
                                writer.finishWriting { cont.resume() }
                                return
                            }
                        } else {
                            wIn.markAsFinished()
                            writer.finishWriting { cont.resume() }
                            break
                        }
                    }
                }
            }
            let result = (writer.status == .completed) ? (try? Data(contentsOf: outURL)) : nil
            try? FileManager.default.removeItem(at: outURL)
            return result
        } catch {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
    }

    /// Robuster Fallback-Transcode über AVAssetExportSession (skaliert via `comp`).
    private nonisolated static func exportTranscode(asset: AVURLAsset, comp: AVMutableVideoComposition, preset: String) async -> Data? {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        let outURL = URL.temporaryDirectory.appending(path: "motione-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)
        session.videoComposition = comp
        session.shouldOptimizeForNetworkUse = true
        do {
            try await session.export(to: outURL, as: .mp4)
            let d = try? Data(contentsOf: outURL)
            try? FileManager.default.removeItem(at: outURL)
            return d
        } catch {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
    }

    /// Motion Studio: Video-Auswahl (kurzer Clip, dessen Bewegung übernommen wird).
    private var motionVideoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Reference video",
                subtitle: "Pick any clip — its moves get copied onto your photo. Long or large videos are auto-optimized."
            )
            PhotosPicker(selection: $motionVideoSelection, matching: .videos) {
                HStack(spacing: 12) {
                    if motionVideoPreparing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing video…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Image(systemName: motionVideoData == nil ? "video.badge.plus" : "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(motionVideoData == nil ? Theme.accent : Theme.success)
                        Text(motionVideoData == nil ? "Add a video" : "Video added — tap to change")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Schwebender Composer für den freien Bild-Editor (Clavic Image Edit):
    /// Text + Bild-Hinzufügen (Inpaint) + Senden. Schwebt über der Tastatur.
    private var editComposer: some View {
        VStack(spacing: 0) {
            TextField("Edit anything in your image you want …", text: $editInstruction, axis: .vertical)
                .focused($focusedField, equals: .target)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)

            HStack(spacing: 10) {
                // Weitere Bilder anhängen (Inpaint / jemanden hinzufügen)
                PhotosPicker(
                    selection: $photoSelection,
                    maxSelectionCount: max(1, maxReferenceImages - referenceImages.count),
                    matching: .images
                ) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(referenceImages.count >= maxReferenceImages ? Theme.textTertiary : Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Theme.surfaceHigh, in: Circle())
                }
                .disabled(referenceImages.count >= maxReferenceImages)

                if referenceImages.count > 1 {
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
                .strokeBorder(focusedField == .target ? Theme.accent : Theme.stroke,
                              lineWidth: focusedField == .target ? 2 : 1)
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
        // Einmaliges Einwilligungs-/Richtlinien-Gate vor dem ersten Foto-Upload
        // (Apple-Anforderung für UGC-/Face-Apps: Rechte am Bild + kein Missbrauch).
        if !acceptedContentPolicy {
            pendingPhotoItems = newItems
            photoSelection = []
            showConsent = true
            return
        }
        processPhotoSelection(newItems)
    }

    private func processPhotoSelection(_ newItems: [PhotosPickerItem]) {
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
                              let jpeg = image.resized(maxDimension: 1600).jpegData(compressionQuality: 0.85) {
                        // 1600px/0.85 hält die Base64-Größe sicher unter Vercels
                        // ~4,5 MB Request-Limit (Topaz skaliert ohnehin wieder hoch).
                        withAnimation(.spring(duration: 0.3)) { referenceImages = [jpeg] }
                    }
                }
                photoSelection = []
                return
            }
            // Geführter Modus (Video-Trend): genau ein Foto (ersetzt das bestehende).
            if isFixed {
                if let item = newItems.first,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegForAPIUpload(maxDimension: 768, quality: 0.72) {
                    withAnimation(.spring(duration: 0.3)) {
                        referenceImages = [jpeg]
                    }
                }
            } else if isImageEdit {
                // Bild-Edit: Bilder ANHÄNGEN (Inpaint / jemanden hinzufügen), bis max.
                for item in newItems {
                    if referenceImages.count >= maxReferenceImages { break }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let jpeg = image.resized(maxDimension: 1280).jpegData(compressionQuality: 0.85) {
                        withAnimation(.spring(duration: 0.3)) {
                            referenceImages.append(jpeg)
                            // 8K Upscale: Original-Seitenverhältnis übernehmen, damit
                            // Nano Banana 2 die Komposition nicht verändert ("auto"
                            // würde sonst ein anderes Format wählen).
                            if isPhotoEnhance { ratio = closestAspectRatio(for: image.size) }
                        }
                    }
                }
            } else {
                for item in newItems {
                    if referenceImages.count >= maxReferenceImages { break }
                    // 1024px/0.80 pro Bild: auch bei 4 Referenzbildern bleibt der
                    // Request sicher unter Vercels ~4,5 MB Limit (verhindert 413).
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let jpeg = image.resized(maxDimension: 1024).jpegData(compressionQuality: 0.80) {
                        withAnimation(.spring(duration: 0.3)) {
                            referenceImages.append(jpeg)
                        }
                    }
                }
            }
            photoSelection = []
        }
    }

    /// Pinterest-Swap: ein Bild für einen festen Slot (Inspo/Selfie) wählen.
    /// Erstmaliger Upload geht durch das Einwilligungs-Gate.
    private func handlePinSelection(_ item: PhotosPickerItem?, isInspo: Bool) {
        guard let item else { return }
        if !acceptedContentPolicy {
            pendingPinItem = (item, isInspo)
            if isInspo { inspoSelection = nil } else { selfieSelection = nil }
            showConsent = true
            return
        }
        loadPinPhoto(item, isInspo: isInspo)
    }

    private func loadPinPhoto(_ item: PhotosPickerItem, isInspo: Bool) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = image.resized(maxDimension: 1280).jpegData(compressionQuality: 0.85) {
                withAnimation(.spring(duration: 0.3)) {
                    if isInspo { pinInspoData = jpeg } else { pinSelfieData = jpeg }
                }
            }
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

    /// Auflösungs-Auswahl (480p/720p) – nur für Seedance-2.0-Templates.
    /// 720p ist schärfer, kostet aber mehr Credits (siehe `creditCost`).
    @ViewBuilder private var resolutionSection: some View {
        if showsResolutionPicker {
            // Motion Control / You're Next Opponent: nur 720p.
            let options = locksResolution720 ? Resolution.allCases.filter { $0 == .p720 } : Resolution.allCases
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Resolution")
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        SelectableChip(
                            title: option.rawValue,
                            icon: option == .p720 ? "sparkles" : "rectangle.compress.vertical",
                            isSelected: resolution == option
                        ) {
                            withAnimation(.spring(duration: 0.25)) { resolution = option }
                        }
                    }
                }
                Text(locksResolution720
                     ? "Motion Control always renders in 720p for best results"
                     : (resolution == .p720
                        ? "Sharper, higher quality — costs more credits"
                        : "Faster and cheaper — lower quality"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

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

            resolutionSection

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

    /// Eine Zeile statt mehrerer Abschnitte. Zugeklappt sieht der Screen
    /// aufgeraeumt aus, aufgeklappt steht alles da.
    private func erweiterteZeile<Inhalt: View>(@ViewBuilder inhalt: () -> Inhalt) -> some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    zeigeErweitert.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Advanced settings")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(zeigeErweitert ? 90 : 0))
                }
                .padding(.horizontal, 18).padding(.vertical, 17)
                .background(Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if zeigeErweitert {
                inhalt()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

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
            // Farbiger Schein unter dem Knopf. Ohne ihn wirkt er wie ein
            // Formularelement, mit ihm wie die Aktion des Screens.
            .shadow(color: Theme.accent.opacity(canGenerate ? 0.38 : 0), radius: 18, y: 8)
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
        if isPhotoEnhance { return template?.title == "8K Upscale" ? "Upscale to 8K" : "Enhance Photo" }
        if isImageEdit { return "Generate Image" }
        return "Generate Video"
    }

    /// Wählt den passenden Prompt je nach Modus.
    private var finalPrompt: String {
        if isUpscale { return "" }
        if isFruitStory { return fruitConfigJSON() }
        if isStillLife { return makeStillLifePrompt() }
        if isCandidPOV { return makeCandidPrompt() }
        if isBrainrotCharacter {
            let base = Brainrot.buildPrompt(selectedBrainrotChar,
                                            text: brainrotUseCustomText ? brainrotText : "",
                                            background: brainrotBgMode)
            // Optionaler Bild-Änderungs-Prompt anhängen (Bild-Only-Modus).
            let extra = brainrotImagePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return extra.isEmpty ? base : base + ". " + extra
        }
        if isAiCharacter {
            return AiCharacter.buildPrompt(gender: aiCharGender,
                                           skin: aiCharSkin,
                                           eyes: aiCharEyes,
                                           hair: aiCharHair,
                                           extra: aiCharExtra)
        }
        if isLuxuryCarSelfie {
            return LuxuryCar.buildPrompt(brand: luxuryCarBrand)
        }
        if isPinterestSwap { return makePinterestSwapPrompt() }
        if isFixedEdit { return template?.fixedEditPrompt ?? "" }
        if isFaceTemplate { return makeFaceTemplatePrompt() }
        if isCharacterInsert { return makeCharacterInsertPrompt() }
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
        into the scene. If the instruction adds an object or element, render it at \
        correct, true-to-life real-world scale relative to its surroundings and \
        position and orient it the way it would naturally sit, stand or be parked \
        in reality, grounded with realistic contact shadows. \
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

    /// Auswahl für den Piraten-Insert: eigenes Foto vs. KI-Cinematic-Szene.
    private var characterBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                SelectableChip(title: "My photo", icon: "photo", isSelected: !characterAddBackground) {
                    withAnimation(.spring(duration: 0.25)) { characterAddBackground = false }
                }
                SelectableChip(title: "Cinematic scene", icon: "moon.stars.fill", isSelected: characterAddBackground) {
                    withAnimation(.spring(duration: 0.25)) { characterAddBackground = true }
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Schnellauswahl gängiger Edits für den freien Bild-Editor. Tippen füllt das
    /// Eingabefeld – der Nutzer kann danach noch frei anpassen.
    private let editPresets: [String] = [
        "Remove the background",
        "Put me on a clean white studio background",
        "Change my outfit to an elegant suit",
        "Old money aesthetic",
        "Add stylish sunglasses",
        "Black and white film look",
        "Make it look like a magazine cover",
    ]

    private var editPresetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick edits")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(editPresets, id: \.self) { preset in
                        SelectableChip(title: preset, isSelected: editInstruction == preset) {
                            withAnimation(.spring(duration: 0.25)) { editInstruction = preset }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imageQualitySectionTitle: String { "Quality · \(ImageEditAPI.displayName)" }

    private var imageQualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(imageQualitySectionTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(ImageQuality.selectable) { q in
                    SelectableChip(
                        title: "\(q.label) · \(q.detail) · \(CreditCosts.imageEditCredits(quality: q.rawValue))cr",
                        isSelected: imageQuality == q
                    ) {
                        withAnimation(.spring(duration: 0.25)) { imageQuality = q }
                    }
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bildgröße/Format für Bild-Edit-Templates (an kie Nano Banana 2 aspect_ratio).
    private var imageSizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image size")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AspectRatio.allCases) { option in
                        SelectableChip(
                            title: option.label,
                            icon: option.icon,
                            isSelected: ratio == option
                        ) {
                            withAnimation(.spring(duration: 0.25)) { ratio = option }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Wählt das zur Bildgröße passendste konkrete Seitenverhältnis (für das
    /// 8K-Upscale, damit die Komposition exakt erhalten bleibt).
    private func closestAspectRatio(for size: CGSize) -> AspectRatio {
        guard size.width > 0, size.height > 0 else { return .vertical }
        let r = size.width / size.height
        let options: [AspectRatio] = [.portrait, .vertical, .square, .classic, .widescreen, .cinema]
        let values: [AspectRatio: CGFloat] = [
            .portrait: 9.0/16.0, .vertical: 3.0/4.0, .square: 1.0,
            .classic: 4.0/3.0, .widescreen: 16.0/9.0, .cinema: 21.0/9.0,
        ]
        return options.min(by: { abs((values[$0] ?? 1) - r) < abs((values[$1] ?? 1) - r) }) ?? .vertical
    }

    /// Pinterest-Swap: zwei eigene Bilder nebeneinander (Inspo + Selfie).
    private var pinterestSwapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                pinPhotoSlot(
                    label: "Inspo look",
                    placeholder: "Pinterest photo",
                    icon: "rectangle.on.rectangle.angled",
                    data: pinInspoData,
                    selection: $inspoSelection
                )
                pinPhotoSlot(
                    label: "Your selfie",
                    placeholder: "Your photo",
                    icon: "person.crop.square.badge.camera",
                    data: pinSelfieData,
                    selection: $selfieSelection
                )
            }
        }
    }

    private func pinPhotoSlot(
        label: String,
        placeholder: String,
        icon: String,
        data: Data?,
        selection: Binding<PhotosPickerItem?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            PhotosPicker(selection: selection, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    if let data, let image = UIImage(data: data) {
                        Color.black.opacity(0.04)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Change")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 9)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(8)
                    } else {
                        // Gestaltete Flaeche statt gestricheltem Kasten: weicher
                        // Verlauf, rundes Symbolabzeichen, kein Strichrahmen.
                        ZStack {
                            LinearGradient(colors: [Theme.accent.opacity(0.10),
                                                    Theme.accent.opacity(0.03)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(Theme.accent.opacity(0.14))
                                    Image(systemName: icon)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                                .frame(width: 56, height: 56)
                                Text(placeholder)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                        .strokeBorder(data == nil ? Theme.accent.opacity(0.22) : Theme.stroke,
                                      lineWidth: 1)
                )
                .shadow(color: Theme.accent.opacity(0.12), radius: 14, y: 6)
            }
        }
    }

    /// „Still Life" / Backrooms-Memory: baut JEDES Mal eine andere Kombination
    /// aus Verzerrungen (Augen/Münder/Züge/Intensität) → jede Person sieht immer
    /// wieder anders „falsch nachgebaut" aus. Person bleibt erkennbar.
    private func makeStillLifePrompt() -> String {
        let eyes = [
            "a third eye on the forehead",
            "an extra pair of eyes just above the eyebrows",
            "four eyes arranged in two uneven rows",
            "six eyes scattered unevenly across the face",
            "two additional eyes on the cheeks",
            "one extra misaligned eye beside an existing eye",
            "a cluster of small extra eyes near the temple",
        ]
        let mouths = [
            "a second mouth just below the real one",
            "two overlapping mouths that don't line up",
            "a faint duplicated mouth on the chin",
            "a mouth stretched slightly too wide with a second row of lips",
            "a small extra mouth on one cheek",
            "a doubled mouth fused at the corner",
        ]
        let extras = [
            "a faintly duplicated nose",
            "stacked, slightly fused facial features",
            "an extra ear placed too high on the head",
            "subtly elongated neck and fingers",
            "one hand with a few too many fingers",
            "asymmetrical, slightly melted proportions",
            "a doubled jawline and smeared hairline",
            "skin that looks faintly rendered, like an unfinished 3D model",
        ]
        let intensity = [
            "The distortions are subtle and uncanny — easy to miss at first glance, then deeply wrong.",
            "The distortions are clearly visible and disturbing.",
            "The distortions are moderate — obviously wrong but still eerily human.",
        ]
        let e = eyes.randomElement() ?? eyes[0]
        let m = mouths.randomElement() ?? mouths[0]
        let x = extras.randomElement() ?? extras[0]
        let i = intensity.randomElement() ?? intensity[0]
        return """
        Transform the person in this photo into a "Still Life": the Backrooms' \
        flawed, imperfect MEMORY of this person — as if a generative AI tried to \
        recreate them from memory and got the details wrong. Keep them clearly \
        recognizable as the same person (same general face shape, hair, skin tone \
        and clothing), but rebuild them WRONG, with these specific anomalies: \
        \(e); \(m); and \(x). \(i) The wrongness must feel like AI image errors — \
        duplicated, misplaced, fused or stacked features — never a clean monster. \
        Place them standing in an empty 'backrooms' liminal space: endless damp \
        yellow wallpaper, worn beige carpet, a low ceiling of buzzing fluorescent \
        lights and slightly off perspective. Eerie, dread-filled atmosphere, dim \
        flat fluorescent lighting, faint handheld/VHS realism and grain. \
        Photorealistic and deeply uncanny — NOT a cartoon, NOT a clean 3D/CGI \
        render; it must look like a real, disturbing photograph of a malformed \
        humanoid. No text, no captions, no watermark.
        """
    }

    // MARK: - Candid Späti (fotorealistischer Schnappschuss)

    /// Fester Realismus-Wrapper + auswählbare Szenen/Vibes. Der Wrapper bleibt
    /// für den Nutzer unsichtbar; er wählt nur Szene + Vibe (+ optional 2. Foto).
    private enum CandidPOV {
        static let head = "Photorealistic iPhone POV photo, vertical 9:16, no filter, no HDR, natural raw quality with slight noise and lighting imperfections."
        static let tail = "Casual streetwear, candid, mid-conversation, NOT looking at the camera, no flash, slightly overexposed highlights, authentic unposed moment, shot like a friend snapped it. Keep each real person's EXACT face, hairstyle, skin tone and features — real human skin, NOT a 3D/CGI render, no waxy skin, no distortion, no extra limbs, no garbled text, no watermark."

        /// (Chip-Label, versteckter Szenen-Block)
        static let scenes: [(String, String)] = [
            ("7-Eleven Night", "Setting: night, sitting at a small metal table at the outdoor seating in front of a local convenience store; bright fluorescent overhead light, harsh uneven shadows, glass storefront with snack and drink shelves glowing behind, parked scooters and a dim street in the background."),
            ("Car at Night",  "Setting: inside a parked car at night, dashboard glow and passing streetlights through the windshield, slightly grainy low light, phone held from the driver seat."),
            ("Hotel Hallway", "Setting: a long brightly-lit hotel corridor at night, patterned carpet, evenly spaced doors, slightly green fluorescent tint, candid walk-and-talk."),
            ("Rooftop",       "Setting: a city rooftop at night, skyline and distant traffic lights softly out of focus behind, cool ambient light, hair moving slightly in the wind."),
            ("House Party",   "Setting: a crowded house party, warm dim lamps and string lights, slight motion blur, red-cup energy, candid in the middle of the room."),
            ("Backstage",     "Setting: a dim backstage area, gear cases and cables, a sliver of stage light spilling in, candid between sets.")
        ]
        /// (Chip-Label, Mimik/Pose)
        static let vibes: [(String, String)] = [
            ("Chill",       "Everyone relaxed and laid-back, easy expressions."),
            ("Deep Talk",   "Serious, focused expressions, engaged in conversation."),
            ("Cracking up", "Everyone mid-laugh, candid joy, one looking away laughing."),
            ("Dramatic",    "Cinematic tense mood, one looking down, charged silence.")
        ]

        static func build(scene: String, vibe: String, who: String) -> String {
            [head, scene, who, vibe, tail].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    /// „Candid Späti": Szene + Vibe wählen (nur eine Person pro Bild).
    private var candidPOVSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Scene")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(CandidPOV.scenes.enumerated()), id: \.offset) { idx, scene in
                            SelectableChip(title: scene.0, isSelected: candidSceneIndex == idx) {
                                withAnimation(.spring(duration: 0.25)) { candidSceneIndex = idx }
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Vibe")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(CandidPOV.vibes.enumerated()), id: \.offset) { idx, vibe in
                            SelectableChip(title: vibe.0, isSelected: candidVibeIndex == idx) {
                                withAnimation(.spring(duration: 0.25)) { candidVibeIndex = idx }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func makeCandidPrompt() -> String {
        let s = min(max(candidSceneIndex, 0), CandidPOV.scenes.count - 1)
        let v = min(max(candidVibeIndex, 0), CandidPOV.vibes.count - 1)
        let who = "The person from the uploaded photo is in the scene, casually hanging out."
        return CandidPOV.build(scene: CandidPOV.scenes[s].1, vibe: CandidPOV.vibes[v].1, who: who)
    }

    // MARK: - Brainrot Character

    /// Charakter-Grid + Text-Modus (Auto/Eigene Zeile) + Background (zufällig /
    /// eigenes Foto / keiner). Kein Nutzerfoto – der Charakter kommt aus dem Asset.
    private var brainrotSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Character")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(Brainrot.chars) { c in
                        Button {
                            withAnimation(.spring(duration: 0.25)) { brainrotCharId = c.id }
                        } label: {
                            VStack(spacing: 6) {
                                Image(c.assetName)
                                    .resizable().scaledToFill()
                                    .frame(height: 128)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(brainrotCharId == c.id ? Theme.accent : Theme.stroke,
                                                          lineWidth: brainrotCharId == c.id ? 3 : 1)
                                    )
                                Text(c.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "What they do / say")
                HStack(spacing: 8) {
                    SelectableChip(title: "Auto", isSelected: !brainrotUseCustomText) {
                        withAnimation(.spring(duration: 0.25)) { brainrotUseCustomText = false }
                    }
                    SelectableChip(title: "Your line", isSelected: brainrotUseCustomText) {
                        withAnimation(.spring(duration: 0.25)) { brainrotUseCustomText = true }
                    }
                    Spacer(minLength: 0)
                }
                if brainrotUseCustomText {
                    TextField("Drop a line or action…", text: $brainrotText, axis: .vertical)
                    .submitLabel(.done)
                    .onSubmit { hideKeyboard() }
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.accent)
                        .lineLimit(1...4)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Background")
                HStack(spacing: 8) {
                    SelectableChip(title: "Random", isSelected: brainrotBgMode == .random) {
                        withAnimation(.spring(duration: 0.25)) { brainrotBgMode = .random }
                    }
                    SelectableChip(title: "Your photo", isSelected: brainrotBgMode == .own) {
                        withAnimation(.spring(duration: 0.25)) { brainrotBgMode = .own }
                    }
                    SelectableChip(title: "None", isSelected: brainrotBgMode == .none) {
                        withAnimation(.spring(duration: 0.25)) { brainrotBgMode = .none }
                    }
                    Spacer(minLength: 0)
                }
                if brainrotBgMode == .own {
                    PhotosPicker(selection: $brainrotBgSelection, matching: .images) {
                        HStack(spacing: 12) {
                            Image(systemName: brainrotBgData == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(brainrotBgData == nil ? Theme.accent : Theme.success)
                            Text(brainrotBgData == nil ? "Choose a background photo" : "Background added — tap to change")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Optionaler Bild-Prompt: am Charakter/Bild etwas ändern.
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Change the look (optional)")
                TextField("e.g. add sunglasses, make it night, red hoodie…", text: $brainrotImagePrompt, axis: .vertical)
                    .submitLabel(.done)
                    .onSubmit { hideKeyboard() }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            }

            // „Reden lassen": Charakter spricht den Text mit ECHTER Stimme + Lip-Sync (Video).
            VStack(spacing: 0) {
                toggleRow(
                    icon: "waveform.circle.fill",
                    title: "Make them talk",
                    subtitle: "Real character voice + lip-sync to your line (video)",
                    isOn: $brainrotTalk
                )
            }
            .cardStyle()
        }
        .onChange(of: brainrotBgSelection) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let jpeg = UIImage(data: data)?.resized(maxDimension: 1280).jpegData(compressionQuality: 0.85) {
                    withAnimation(.spring(duration: 0.3)) {
                        brainrotBgData = jpeg
                        brainrotBgMode = .own
                    }
                }
            }
        }
    }

    // MARK: - AI Character

    private var aiCharacterSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                title: "Build a person",
                subtitle: "Every generation creates a different, ultra-realistic unique person. Pick the traits — hairstyle, age, expression, background and more are randomized for you."
            )

            attributeRow(title: "Gender", items: AiCharacter.Gender.allCases, selection: $aiCharGender) { $0.label }
            attributeRow(title: "Skin tone", items: AiCharacter.SkinTone.allCases, selection: $aiCharSkin) { $0.label }
            attributeRow(title: "Eye color", items: AiCharacter.EyeColor.allCases, selection: $aiCharEyes) { $0.label }
            attributeRow(title: "Hair color", items: AiCharacter.HairColor.allCases, selection: $aiCharHair) { $0.label }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Extra details (optional)")
                TextField("e.g. add glasses, beard, evening light, freckles…", text: $aiCharExtra, axis: .vertical)
                    .submitLabel(.done)
                    .onSubmit { hideKeyboard() }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
    }


    /// Luxury Car Selfie: Selfie hochladen + Automarke wählen.
    private var luxuryCarSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                title: "Pick your car",
                subtitle: "Choose the luxury brand — your selfie stays the same, only the interior changes."
            )
            attributeRow(title: "Car", items: LuxuryCar.Brand.allCases, selection: $luxuryCarBrand) { $0.label }
        }
    }

    /// Generische Attribut-Auswahlreihe (waagerecht scrollende Chips).
    private func attributeRow<T: Identifiable & Hashable>(
        title: String,
        items: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        SelectableChip(
                            title: label(item),
                            isSelected: selection.wrappedValue == item
                        ) {
                            withAnimation(.spring(duration: 0.25)) { selection.wrappedValue = item }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pinterest-Swap: tauscht das Gesicht aus dem Selfie (2. Bild) aufs Inspo-
    /// Bild (1. Bild) – Outfit, Pose, Szene bleiben identisch.
    private func makePinterestSwapPrompt() -> String {
        return """
        You are given two images. The FIRST image is an inspiration/fashion photo \
        (a Pinterest-style look). The SECOND image is a selfie of the user. \
        Replace ONLY the face and head likeness of the main person in the FIRST \
        image with the face and likeness of the person in the SECOND image, so it \
        clearly and convincingly looks like the user is the one wearing that look. \
        Keep the FIRST image's exact outfit, dress, body, pose, hands, hairstyle, \
        background, framing, camera angle and lighting completely UNCHANGED — \
        change only the face/identity. Blend the new face seamlessly: match the \
        head angle, skin tone, lighting direction and shadows of the FIRST image, \
        and adapt the visible neck/skin so it looks natural and consistent. \
        The result must look like a 100% REAL photograph of the user in that exact \
        look: natural detailed skin with pores and subtle imperfections, realistic \
        catchlights in the eyes, no plastic, waxy or airbrushed skin, no doll or \
        CGI look, no distortion or warping, no duplicated features. \
        No text and no watermark in the image.
        """
    }

    /// Pinterest-Swap: 4 Prompt-Varianten. #1 = exakt wie das Inspo-Bild (nur
    /// Gesicht getauscht). #2–4 = gleiche Location, Background, Outfit, Licht und
    /// Identität, aber eine ANDERE Körperpose (zufällig gewählt → jede Serie neu).
    private func makePinterestSwapVariants() -> [String] {
        let poses = [
            "standing confidently with one hand on the hip",
            "walking towards the camera in mid-step",
            "looking back over the shoulder",
            "leaning casually against a nearby surface or wall",
            "one hand gently touching the hair, relaxed stance",
            "sitting down in a relaxed, natural pose",
            "turned to a three-quarter side angle, hand in pocket",
            "arms crossed, casual confident stance",
        ]
        let chosen = Array(poses.shuffled().prefix(pinterestVariantCount - 1))
        var prompts = [makePinterestSwapPrompt()]
        for pose in chosen {
            prompts.append("""
            You are given two images. The FIRST image is an inspiration/fashion \
            photo. The SECOND image is a selfie of the user. Create a NEW photo of \
            the user wearing the EXACT same look as in the FIRST image: keep the \
            FIRST image's outfit, clothing, hairstyle, background, location, \
            setting, lighting, color grade and camera framing completely identical \
            — change ONLY the person's body pose to: \(pose). Replace the face and \
            likeness with the person from the SECOND image so it clearly looks like \
            the user. It must look like another shot from the SAME photoshoot in \
            the SAME place, just a different pose. \
            Photorealistic 100% real photograph: natural detailed skin with pores, \
            realistic catchlights, no plastic, waxy or airbrushed skin, no doll or \
            CGI look, no distortion or warping, no duplicated limbs. No text and no \
            watermark.
            """)
        }
        return prompts
    }

    /// Pose-/Face-Template: tauscht das Gesicht der Nutzerin (2. Bild) auf das
    /// feste Modell-Bild (1. Bild) – Outfit, Pose, Szene bleiben identisch.
    private func makeFaceTemplatePrompt() -> String {
        return """
        You are given two images. The FIRST image is a fashion photo of a woman \
        (the template). The SECOND image is a selfie of the user. Replace ONLY \
        the face of the woman in the FIRST image with the face and likeness of \
        the person in the SECOND image, so it clearly looks like the user is the \
        one in the photo. \
        Keep the FIRST image's exact outfit, dress, body, pose, hands, hair, \
        background, framing, camera angle and lighting completely UNCHANGED — \
        change only the face. Blend the new face seamlessly: match the head \
        angle, skin tone, lighting direction and shadows of the FIRST image, and \
        adapt the visible neck/skin tone to the new face so it looks natural. \
        The result must look like a 100% REAL photograph of the user in that \
        exact look: natural detailed skin with pores and subtle imperfections, \
        realistic catchlights in the eyes, no plastic, waxy or airbrushed skin, \
        no doll or CGI look, no distortion or warping, no duplicated features. \
        No text and no watermark in the image.
        """
    }

    /// Character-Insert: fügt den festen Charakter (2. Bild) realistisch ein,
    /// OHNE sein Aussehen zu verändern. Zwei Modi: eigenen Hintergrund behalten
    /// oder eine dunkle, cinematische Szene erzeugen.
    private func makeCharacterInsertPrompt() -> String {
        let pirate = "an eerie, uncanny pirate man with wide staring eyes, a weathered dark beard, a worn tricorn pirate hat and a yellow-and-teal ragged pirate costume with a wide sash belt and a wooden peg leg"
        let keepChar = "ABSOLUTELY DO NOT change the pirate's appearance: keep his exact face, the same wide eyes, beard, skin tone, hat, clothing, body and proportions identical to the reference image. Do not beautify, restyle, age or alter him — only relight, rescale and naturally pose him to fit the scene, with correct contact shadows."
        let realism = "The result must look like a genuine candid photograph, never AI-generated: natural detailed skin texture, no plastic, waxy or rubbery skin, no glow, halo or cut-out edges around the pirate, no duplicated limbs. No text and no watermark in the image."

        if characterAddBackground {
            return """
            You are given two images. The FIRST image is a real photo of a person \
            (the user). The SECOND image shows \(pirate). Build a NEW dark, \
            cinematic, eerie nighttime scene and place BOTH the person from the \
            FIRST image and the exact pirate from the SECOND image together in it, \
            standing close side by side as if photographed together at night. \
            Invent a realistic fitting backdrop in the style of an unsettling \
            late-night phone photo — for example a dim concrete tunnel, an empty \
            parking deck, a dark wooden boardwalk among trees, or a liminal \
            hallway — lit by a single harsh light source. Use strong moody \
            low-key lighting, deep shadows, a slightly desaturated cinematic \
            color grade and subtle film grain so it looks like a real night \
            snapshot. Keep the user's identity perfectly intact: the exact same \
            face, hair, skin tone and features from the FIRST image. \(keepChar) \
            Light both of them consistently with the new scene so they truly \
            belong in it. \(realism)
            """
        }
        return """
        You are given two images. The FIRST image is a real photo taken by the \
        user. The SECOND image shows \(pirate). Composite this exact pirate from \
        the SECOND image into the FIRST image so it looks like he was really \
        there, standing or lurking right next to or behind the main person. \
        \(keepChar) Match the FIRST photo perfectly: same lighting direction, \
        shadows, color grade, white balance, camera angle, lens perspective, \
        depth of field, sensor grain and resolution, so the pirate blends in as \
        a 100% real photograph. Keep the original person, their pose and the \
        entire background unchanged. \(realism)
        """
    }

    private func startGeneration() {
        focusedField = nil

        // Re-Entry-Schutz: läuft schon ein Submit (z. B. Doppel-/Dreifach-Tap
        // während die Ansicht sich schließt), sofort abbrechen.
        guard !isSubmitting else { return }

        guard KieSeedanceAPI.hasAPIKey else {
            showMissingKeyAlert = true
            return
        }

        // ALLE vom Nutzer editierbaren Freitext-Felder prüfen (App Store 1.1) —
        // jedes fließt in einen Prompt ein und muss intim-/sexuellen Inhalt sperren.
        let userTexts = [
            editInstruction, prompt, brainrotText, brainrotImagePrompt, aiCharExtra,
            motionEditPrompt, swapTarget, swapOutfit, fruitCustomIdea
        ]
        for text in userTexts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let reason = ContentPolicy.rejectionReason(for: trimmed) {
                contentPolicyMessage = reason
                return
            }
        }

        guard store.canCreate else {
            showSubscriptionGate = true
            return
        }

        // Genug Guthaben? Sonst Credits nachladen.
        guard store.canAfford(creditCost) else {
            showPaywall = true
            return
        }
        // Ab hier ist der Submit unumkehrbar → Re-Entry sperren (bis dismiss).
        isSubmitting = true
        store.consume(creditCost)

        // Pinterest-Swap: erzeugt 4 Bilder auf einmal – #1 exakt wie das Inspo-
        // Bild (nur Gesicht getauscht), #2–4 gleiche Location/Outfit, andere Pose.
        if isPinterestSwap, let inspo = pinInspoData, let selfie = pinSelfieData {
            let refs = [inspo, selfie]
            let perImage = CreditCosts.imageEditCredits(quality: imageQuality.rawValue)
            let variants = makePinterestSwapVariants()
            for (idx, variantPrompt) in variants.enumerated() {
                let proj = VideoProject(
                    prompt: variantPrompt,
                    templateTitle: template?.title ?? "",
                    ratio: ratio,
                    resolution: resolution,
                    duration: 0,
                    generateAudio: false,
                    useFastModel: true,
                    referenceImagesData: refs,
                    referenceVideoURLs: [],
                    referenceVideosData: [],
                    isImageOutput: true,
                    useKie: false,
                    useMusicLipSync: false,
                    musicVideoKey: "",
                    upscaleKind: nil,
                    creditCost: perImage,
                    imageQuality: imageQuality.rawValue
                )
                generationManager.submit(project: proj)
                // Nur das erste (exakte) Ergebnis ansteuern; die 3 Posen erscheinen
                // in der Library.
                if idx == 0 { onSubmitted(proj) }
            }
            dismiss()
            return
        }

        // Character-Insert: Nutzerfoto (1.) + festes Charakter-Bild (2.) senden,
        // damit der Charakter immer identisch eingefügt wird.
        var refImages = referenceImages
        var effectiveMusicKey = template?.musicVideoKey ?? ""
        // AI Fruit Story: gewählte Charaktere als Referenzbilder mitgeben – in
        // GENAU der Cast-Reihenfolge wie in der JSON-Config (`fruitConfigJSON`),
        // damit die Pipeline Name ↔ Bild korrekt zuordnet.
        if isFruitStory {
            refImages = orderedSelectedCharacters().compactMap {
                UIImage(named: $0.asset)?.resized(maxDimension: 1024).jpegData(compressionQuality: 0.9)
            }
            effectiveMusicKey = "fruit"
        }
        // Generische Build-Variante: gewählte Bau-Figur als Referenz mitgeben.
        // Tung Tung / frucht-köpfige Figur (gebündelt) oder eigene hochgeladene
        // Figur (wird in der Pipeline per Nano Banana 2 umgestylt → key "build_custom").
        if isBrainrotBuildGeneric {
            switch buildCharacter {
            case .tung:
                if let j = UIImage(named: "tung_character")?.resized(maxDimension: 1024).jpegData(compressionQuality: 0.9) { refImages = [j] }
                effectiveMusicKey = "build"
            case .fruit:
                if let j = UIImage(named: "fruit_character")?.resized(maxDimension: 1024).jpegData(compressionQuality: 0.9) {
                    refImages = [j]
                } else if let t = UIImage(named: "tung_character")?.resized(maxDimension: 1024).jpegData(compressionQuality: 0.9) {
                    refImages = [t]   // Fallback, falls Frucht-Asset noch nicht gebündelt
                }
                effectiveMusicKey = "build"
            case .custom:
                if let d = buildCustomData { refImages = [d] }
                effectiveMusicKey = "build_custom"
            }
        }
        // Pinterest-Swap: Inspo-Bild (1.) + Selfie (2.) – Nano Banana 2 tauscht das
        // Gesicht aufs Inspo-Bild.
        if isPinterestSwap, let inspo = pinInspoData, let selfie = pinSelfieData {
            refImages = [inspo, selfie]
        }
        if isCharacterInsert, let userPhoto = referenceImages.first,
           let asset = template?.characterRefAsset, let img = UIImage(named: asset),
           let charJPEG = img.resized(maxDimension: 1280).jpegData(compressionQuality: 0.9) {
            refImages = [userPhoto, charJPEG]
        }
        // Face-Template: festes Modell-Bild (1.) + Nutzerfoto (2.) – das Gesicht
        // der Nutzerin wird aufs Modell getauscht.
        if isFaceTemplate, let userPhoto = referenceImages.first,
           let asset = template?.faceTemplateAsset, let img = UIImage(named: asset),
           let modelJPEG = img.resized(maxDimension: 1280).jpegData(compressionQuality: 0.9) {
            refImages = [modelJPEG, userPhoto]
        }
        // Brainrot Character: festes Charakter-Referenzbild (1.) + optional eigenes
        // Hintergrundbild (2.). Nano Banana 2 setzt den Charakter in die Szene.
        if isBrainrotCharacter {
            var imgs: [Data] = []
            if let charImg = UIImage(named: selectedBrainrotChar.assetName)?
                .resized(maxDimension: 1024).jpegData(compressionQuality: 0.9) {
                imgs.append(charImg)
            }
            if brainrotBgMode == .own, let bg = brainrotBgData { imgs.append(bg) }
            if !imgs.isEmpty { refImages = imgs }
        }
        // AI Character: NEUTRALES graues Seed-Bild als einziges Referenzbild
        // (Backend braucht mind. 1 Bild; das Seed hat keine Identität → jede
        // Generierung eine andere Person). Prompt treibt die Erzeugung.
        if isAiCharacter {
            refImages = [AiCharacter.seedImageData()]
        }

        let project = VideoProject(
            prompt: finalPrompt,
            templateTitle: template?.title ?? "",
            ratio: ratio,
            resolution: resolution,
            duration: duration,
            generateAudio: generateAudio,
            useFastModel: true,
            referenceImagesData: refImages,
            referenceVideoURLs: referenceVideoURLs,
            referenceVideosData: motionVideoData.map { [$0] } ?? [],
            isImageOutput: isImageEdit || upscaleKind == "image",
            useKie: template?.useKie == true,
            useMusicLipSync: template?.useMusicLipSync == true,
            musicVideoKey: effectiveMusicKey,
            upscaleKind: upscaleKind,
            creditCost: creditCost,
            // 8K Upscale immer in max. Auflösung (4K) rendern.
            imageQuality: isPhotoEnhance ? "high" : imageQuality.rawValue
        )
        project.useKlingMotion = template?.useKlingMotion == true
        project.seedanceModel = template?.seedanceModel ?? ""
        // Motion: optionaler Nano-Banana-Vor-Edit fürs Foto (läuft in
        // GenerationManager VOR der Kling-Motion-Generierung).
        if isMotion {
            project.preEditPrompt = motionEditPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Motion-Templates: „Auto"-Länge = Länge des Eingangsvideos, gerundet auf
        // eine vom Modell unterstützte Länge (8 s → 10 s; sonst liefert Seedance
        // still die Default-Länge 5 s).
        if isMotion, motionLengthAuto, let v = motionVideoDuration {
            project.duration = snapMotionDuration(v)
        }
        // Brainrot „reden lassen": auf die Sprech-/Lip-Sync-Pipeline umrouten
        // (Bild → Seedance-Video → ElevenLabs-TTS in der Charakter-Stimme → fal
        // Lip-Sync). Ergebnis ist ein VIDEO; Seedance r2v braucht 720p.
        if isBrainrotCharacter && brainrotTalk {
            project.useMusicLipSync = true
            project.musicVideoKey = "brainrot_talk"
            project.isImageOutput = false
            project.resolutionRaw = Resolution.p720.rawValue
            project.talkVoice = selectedBrainrotChar.voice
            project.talkText = Brainrot.speechText(selectedBrainrotChar,
                                                   text: brainrotUseCustomText ? brainrotText : "")
            // prompt trägt den optionalen Bild-Änderungs-Prompt (leer = Charakter
            // unverändert; gefüllt = GPT-Image-2-Edit vor dem Talk-Video).
            project.prompt = brainrotImagePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        generationManager.submit(project: project)
        onSubmitted(project)
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
        // WICHTIG: Scale fest auf 1 — sonst rendert UIGraphicsImageRenderer mit
        // dem Geräte-Scale (2x/3x), d. h. „1024" würde real 2048/3072 Pixel
        // erzeugen → riesige Base64-Payload → HTTP 413 beim Upload.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// JPEG für API-Uploads — klein genug für Vercels ~4,5 MB Body-Limit.
    nonisolated func jpegForAPIUpload(maxDimension: CGFloat = 768, quality: CGFloat = 0.72) -> Data? {
        resized(maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }
}
