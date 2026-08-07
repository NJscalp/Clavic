//
//  StudioView.swift
//  Clavic
//
//  Studio = BILD-EDITOR. Vorher standen hier nur Video-Modelle zur Auswahl;
//  Video ist in den Chat gewandert (Image/Video-Umschalter). Hier geht es
//  jetzt ausschließlich darum, ein vorhandenes Foto wirklich zu bearbeiten.
//
//  Zwei Ebenen, bewusst getrennt:
//
//  • LOKAL UND LIVE (gratis, sofort): Licht, Farbe, Filter, Hautton und die
//    Körper-Regler. Läuft über `PhotoEditEngine` auf dem Gerät — beim Ziehen
//    am Regler ist das Ergebnis sofort da. Ein Bildmodell auf dem Server
//    wäre pro Regler-Bewegung ein Aufruf von Sekunden und ein Credit.
//  • KI (kostet Credits, dauert Sekunden): nur das, was man nicht rechnen
//    kann — aus einer Grimasse ein natürliches Lächeln machen, ohne die
//    Person zu verändern.
//
//  HINTERGRUND-LOCK: die Körper-Regler sind radiusbegrenzte lokale
//  Verzerrungen (siehe `PhotoEditEngine.warp`). Außerhalb des Kreises bleibt
//  jedes Pixel unverändert — der Hintergrund KANN nicht verziehen. Der Kreis
//  ist sichtbar und verschiebbar, damit man genau sieht, was betroffen ist.
//

import SwiftUI
import PhotosUI
import Photos

struct StudioView: View {
    /// Bleibt für die Aufrufstelle in `ContentView` erhalten (Signatur ändert
    /// sich nicht), wird vom Editor aber nicht mehr benutzt.
    var onSubmitted: (VideoProject) -> Void = { _ in }

    @Environment(Store.self) private var store
    @Environment(EditHandoff.self) private var editHandoff

    // Quelle & Vorschau
    @State private var original: UIImage?          // volle Auflösung (fürs Sichern)
    @State private var previewSource: UIImage?     // verkleinert (fürs Rechnen)
    @State private var rendered: UIImage?          // Ergebnis der aktuellen Regler
    @State private var photoSelection: PhotosPickerItem?
    @AppStorage("acceptedContentPolicy") private var acceptedContentPolicy = false
    @State private var showConsent = false
    @State private var pendingAIPrompt: String?
    @State private var pendingAIExtraImages: [Data] = []
    @State private var pendingAIBaseImage: UIImage?
    @State private var pendingAIModel: String?
    @State private var pendingAIQuality: String?
    /// Remove muss durch Consent/Paywall/Netzwerkfehler denselben Bildstand
    /// behalten. Sonst zeigen Basisbild und gemalte Maske auf andere Pixel.
    @State private var pendingEraseContext: EraseRequestContext?
    @State private var showCamera = false
    @State private var openChatAfterNextAI = false

    // Bearbeitung
    @State private var edits = PhotoEdits()
    @State private var section: Section = .remove
    @State private var showPoseCamera = false
    @State private var analysis: BodyAnalysis = .fallback()
    @State private var analyzing = false
    @State private var bodyFocus: BodyPart = .waist
    @State private var showOriginal = false
    /// Wird gerade am Regler gezogen? Nur dann leuchtet die Wert-Blase.
    @State private var sliderTouched = false
    @State private var lightFocus = "exposure"
    @State private var retouchFocus = "smooth"
    @State private var faceAnalysis: FaceAnalysis = .fallback()
    @State private var faceFocus: FacePart = .jawline
    @State private var aiFocus = "fix"
    @State private var aiVariantID: String?
    @State private var aiInstruction = ""
    @State private var chatInstruction = ""
    @FocusState private var chatFocused: Bool

    /// Dieselbe nicht ueberschwingende Kurve wie im Chat-Tab. Ohne eine
    /// gemeinsame Kurve laufen Bild und Bedienleiste beim Aufgehen der Tastatur
    /// auf verschiedenen Federn gegeneinander.
    private static let composerMotion: Animation = .smooth(duration: 0.3)
    /// Ist gerade ein Werkzeug in Bearbeitung? Dann zeigt die untere Leiste
    /// ✕ · KATEGORIE · ✓ statt der Kategorie-Pillen (FaceLab-Modell).
    @State private var editingTool = false
    /// Stand vor dem Öffnen des Werkzeugs — ✕ stellt ihn wieder her.
    @State private var editsBeforeTool = PhotoEdits()
    @State private var snapshotBeforeTool: StudioSnapshot?
    @State private var history = StudioHistory(limit: 12)
    /// Gemalte Markierungen fürs Entfernen (relative Koordinaten).
    @State private var eraseStrokes: [EraseStroke] = []
    @State private var eraseBrush: Double = 0.06
    @State private var isDetectingEraseObject = false
    /// Verhindert, dass die langsamere Analyse eines alten Fotos ein danach
    /// geladenes Foto ueberschreibt.
    @State private var analysisRevision = 0

    @State private var isWorking = false
    @State private var toast: String?
    @State private var showSubscriptionGate = false

    private struct EraseRequestContext {
        let prepared: EraseMask.Prepared
    }

    /// Nur noch das, was das Studio wirklich gut kann: das Radier-Werkzeug und
    /// der Chat (mit Kamera). Die lokalen Regler fuer Gesicht, Koerper, Haut
    /// und Licht sind entfernt — sie versprachen mehr, als sie hielten.
    enum Section: String, CaseIterable, Identifiable {
        case remove, chat
        var id: String { rawValue }
        var label: String {
            switch self {
            case .remove: return "Remove"
            case .chat: return "Chat"
            }
        }
        var icon: String {
            switch self {
            case .remove: return "eraser"
            case .chat: return "message"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if previewSource == nil {
                emptyState
            } else {
                editorToolbar.disabled(isWorking)
                canvas
                    // Gleicher Seitenabstand wie beim Menü darunter, damit
                    // Bildkarte und Bedienleiste bündig übereinander stehen.
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 10)
                editorMenu
                    .disabled(analyzing || isWorking)
                    .allowsHitTesting(!analyzing && !isWorking)
                    .opacity(analyzing || isWorking ? 0.42 : 1)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .onChange(of: edits) { _, _ in rerender() }
        .onChange(of: editHandoff.pendingStudioImage) { _, _ in adoptHandoffImage() }
        .onAppear {
            adoptHandoffImage()
            #if DEBUG
            // Reproduzierbare Simulator-QA ohne Photo-Picker. Dieser Hook ist
            // nicht Teil des Release-Builds und nutzt nur ein bestehendes Asset.
            let environment = ProcessInfo.processInfo.environment
            if let requested = environment["UITEST_STUDIO_SECTION"],
               let target = Section(rawValue: requested) {
                section = target
            }
            if environment["UITEST_STUDIO_CAMERA"] != nil { showCamera = true }
            if environment["UITEST_STUDIO_SAMPLE"] != nil,
               previewSource == nil,
               let sample = UIImage(named: "face_model_1") {
                Task {
                    await load(sample)
                    if environment["UITEST_STUDIO_ERASE_STROKE"] != nil {
                        eraseStrokes = [EraseStroke(
                            points: [
                                CGPoint(x: 0.68, y: 0.43),
                                CGPoint(x: 0.72, y: 0.47),
                                CGPoint(x: 0.75, y: 0.52),
                            ],
                            width: 0.07
                        )]
                    }
                }
            }
            #endif
        }
        .alert("Before you use AI", isPresented: $showConsent) {
            Button("I agree & continue") {
                acceptedContentPolicy = true
                let prompt = pendingAIPrompt
                let extras = pendingAIExtraImages
                let eraseContext = pendingEraseContext
                let baseOverride = pendingAIBaseImage
                let modelOverride = pendingAIModel
                let qualityOverride = pendingAIQuality
                pendingAIPrompt = nil
                pendingAIExtraImages = []
                pendingEraseContext = nil
                pendingAIBaseImage = nil
                pendingAIModel = nil
                pendingAIQuality = nil
                if let prompt {
                    runAI(prompt, extraImages: extras, eraseContext: eraseContext,
                          baseImageOverride: baseOverride, modelOverride: modelOverride,
                          qualityOverride: qualityOverride)
                }
            }
            Button("View policy") { UIApplication.shared.open(LegalLinks.terms) }
            Button("Cancel", role: .cancel) {
                pendingAIPrompt = nil
                pendingAIExtraImages = []
                pendingEraseContext = nil
                pendingAIBaseImage = nil
                pendingAIModel = nil
                pendingAIQuality = nil
            }
        } message: {
            Text("AI tools upload the current photo for processing. Only continue with photos of yourself or people who have given permission.")
        }
        .overlay(alignment: .top) { if let toast { toastView(toast) } }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .sheet(isPresented: $showSubscriptionGate) { PaywallView() }
        .fullScreenCover(isPresented: $showCamera) {
            SoloShotView(
                // Der Solo Shot erzeugt das Bild inzwischen selbst und legt es
                // in der Bibliothek ab. Hier kommt nur noch das fertige Bild
                // an, damit man direkt weiterbearbeiten kann.
                onFinish: { image in
                    showCamera = false
                    Task { await load(image) }
                },
                onCancel: { showCamera = false }
            )
        }
        // Kamera aus dem Chat: liefert die eigene Aufnahme, die Vorlage und
        // einen fertig gebauten Prompt. Weil dabei immer die Haltung uebernommen
        // wird, laeuft der Auftrag ueber Nano Banana 2 (siehe ImageEditAPI).
        .fullScreenCover(isPresented: $showPoseCamera) {
            PoseCameraView(
                onSend: { result in
                    showPoseCamera = false
                    guard let shot = UIImage(data: result.shot) else { return }
                    runAI(result.prompt,
                          extraImages: [result.reference],
                          baseImageOverride: shot,
                          modelOverride: ImageEditAPI.poseModel)
                },
                onCancel: { showPoseCamera = false }
            )
        }
    }

    // MARK: - Leerer Zustand

    private var emptyState: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 5) {
                    Text("Studio")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your complete face, body and photo editor")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }

                if let before = UIImage(named: "preview_pro_glow_before"),
                   let after = UIImage(named: "preview_pro_glow_after") {
                    BeforeAfterSlider(before: before, after: after, sweepDuration: 3.0)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.white.opacity(0.65), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                }

                // Genau die drei Dinge, die das Studio wirklich kann — fest
                // nebeneinander statt scrollend. Vorher standen hier sechs
                // Versprechen, von denen vier gar nicht mehr existieren.
                HStack(spacing: 8) {
                    featureChip("Remove", "eraser")
                    featureChip("Chat edit", "message")
                    featureChip("Camera", "camera")
                }

                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label("Choose photo", systemImage: "photo.badge.plus")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassEffect(.regular.tint(Theme.accent).interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button { showCamera = true } label: {
                        Image(systemName: "person.crop.rectangle.badge.plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 52, height: 48)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create a solo shot")
                }

                Label("Local tools stay on this device · AI tools are clearly marked",
                      systemImage: "lock.shield")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private func featureChip(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
    }

    /// Eigenes, kompaktes Editor-Chrome innerhalb des bestehenden Studio-Tabs.
    /// Die globale Clavic-Tabbar bleibt dabei unangetastet.
    private var editorToolbar: some View {
        HStack(spacing: 6) {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change photo")

            Button { undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 32, height: 34)
            }
            .disabled(!history.canUndo || isWorking)
            .accessibilityLabel("Undo")

            Button { redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 32, height: 34)
            }
            .disabled(!history.canRedo || isWorking)
            .accessibilityLabel("Redo")

            Spacer(minLength: 4)

            VStack(spacing: 0) {
                Text("STUDIO")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .kerning(1.2)
                Text(section.label)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            compareButton

            Button { save() } label: {
                Text("Save")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }

    // MARK: - Leinwand

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                if let shown = showOriginal ? previewSource : (rendered ?? previewSource) {
                    // Bewusst OHNE Bezug auf `geo.size`: sobald die Tastatur
                    // aufgeht, aendert sich die Hoehe bei jedem einzelnen Frame.
                    // Vorher wurde daraufhin pro Frame die Zoom-Rechnung
                    // ausgefuehrt und das Bild neu skaliert — genau das hat
                    // beim Antippen der Chat-Zeile geruckelt. `scaledToFit`
                    // erledigt die Anpassung allein im Layout.
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surfaceHigh)
            // Weiche Ecken statt harter Kanten. Der Zuschnitt gilt bewusst nur
            // für das Bild: Statusanzeigen und Schalter liegen als Overlays
            // DARÜBER, sonst schneidet der Rahmen ihre Schatten ab.
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
            .overlay {
                // Malfläche nur im Erase-Reiter. `imageRect` ist der Bereich,
                // in dem das Bild wirklich liegt — bei Hochformat ist der
                // schmaler als der Rahmen, sonst säße die Markierung versetzt.
                if section == .remove, let shown = rendered ?? previewSource {
                    let imageRect = fittedRect(for: shown, in: geo.size)
                    ZStack {
                        // Sofortige lokale Vorschau unter dem Finger. Das ist
                        // bewusst keine vorgetäuschte fertige KI-Füllung: die
                        // markierte Fläche wird live weich ausgeblendet; nach
                        // „Remove" füllt die KI nur genau diese Maske.
                        if !eraseStrokes.isEmpty {
                            Image(uiImage: shown)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .blur(radius: 14)
                                .mask {
                                    EraseMaskPreview(
                                        strokes: eraseStrokes,
                                        imageRect: imageRect,
                                        tint: .white
                                    )
                                }
                                .allowsHitTesting(false)
                        }

                        EraseCanvas(strokes: $eraseStrokes, brush: eraseBrush,
                                    imageRect: imageRect)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            // EPIK legt den Hintergrund-Schalter AUF das Bild, nicht ins Menü —
            // dort, wo man die Wirkung sieht. Der Vergleichs-Knopf sitzt
            // daneben, ebenfalls auf dem Bild.

            .overlay { statusIndicator }
        }
    }

    /// „Scanne…" bzw. „Arbeite…" — liegt über dem Bildzuschnitt, damit der
    /// weiche Schatten der Anzeige nicht an der Bildkante abreißt.
    @ViewBuilder
    private var statusIndicator: some View {
        if analyzing {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Theme.accent)
                Text("Scanning person pixel by pixel…")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Mapping silhouette, pose and face landmarks")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else if isWorking {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .stroke(Theme.accent.opacity(0.16), lineWidth: 2)
                        .frame(width: 30, height: 30)
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(section == .remove ? "Removing selection" : "Creating your \(StudioAITools.all.first(where: { $0.id == aiFocus })?.label.lowercased() ?? "edit")")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(section == .remove ? "Keeping the rest of the photo untouched" : "Working on your photo")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Theme.stroke.opacity(0.75), lineWidth: 1)
            )
            .shadow(color: Theme.accent.opacity(0.10), radius: 14, y: 5)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    /// Wo liegt das Bild wirklich im Rahmen? `scaledToFit` lässt oben/unten
    /// bzw. links/rechts Luft, und genau dort darf nicht gemalt werden.
    private func fittedRect(for image: UIImage, in size: CGSize) -> CGRect {
        let ratio = image.size.width / max(image.size.height, 1)
        var w = size.width
        var h = w / ratio
        if h > size.height { h = size.height; w = h * ratio }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// Hintergrund-Lock als schwebende Pille auf dem Bild — Aufbau wie bei
    /// EPIK (Beschriftung links, Schalter rechts), nur in unserem hellen Glas
    /// statt auf Schwarz.
    private var backgroundLockPill: some View {
        HStack(spacing: 10) {
            Text("Background Lock")
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Toggle("", isOn: Binding(
                get: { edits.backgroundLock },
                set: { enabled in
                    guard enabled != edits.backgroundLock else { return }
                    if let snapshot = currentSnapshot() { history.remember(snapshot) }
                    edits.backgroundLock = enabled
                }
            ))
                .labelsHidden()
                .tint(Theme.accent)
                .scaleEffect(0.85)
                .frame(width: 46)
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    /// Gedrückt halten = Original zeigen.
    private var compareButton: some View {
        Image(systemName: showOriginal ? "eye.fill" : "arrow.left.arrow.right")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.accent)
            .frame(width: 34, height: 34)
            // Eine Glasschicht statt Glas ÜBER einer gefüllten Fläche — die
            // Doppelung hat einen harten Rand hinter dem Knopf erzeugt.
            .glassEffect(.regular.tint(Theme.accentSoft).interactive(), in: Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in showOriginal = true }
                    .onEnded { _ in showOriginal = false }
            )
            .accessibilityLabel("Hold to compare with the original")
    }

    // MARK: - Menü unten

    private var editorControlHeight: CGFloat { section == .chat ? 120 : 100 }

    private var editorMenu: some View {
        VStack(spacing: 6) {
            Group {
                switch section {
                case .remove: removeControls
                case .chat: chatControls
                }
            }
            // MINDESTHÖHE statt fester Höhe: Die gemeinsame Untergrenze hält
            // das Bild beim Reiterwechsel ruhig. Eine harte Obergrenze hat
            // dagegen die höheren Reiter (Regler + Werkzeugleiste, „Remove")
            // aus dem Rahmen laufen lassen — sie zeichneten dann über die
            // Kategorie-Pillen darunter.
            .frame(maxWidth: .infinity,
                   minHeight: editorControlHeight,
                   alignment: .top)
            .animation(Self.composerMotion, value: chatFocused)

            // FaceLab-Modell (aus `facelab.mp4` abgelesen): solange man nur
            // stöbert, stehen unten die KATEGORIE-PILLEN. Sobald ein Werkzeug
            // aktiv ist, werden sie durch die Modal-Leiste ✕ · NAME · ✓
            // ersetzt. Dadurch ist immer nur EINE Bedienebene sichtbar statt
            // drei gestapelter Reihen.
            if editingTool {
                HStack(spacing: 0) {
                    Button { cancelTool() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 30)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    // Großgeschrieben und mittig — genau wie bei FaceLab.
                    Text(section.label.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(Theme.textSecondary)

                    Spacer(minLength: 0)

                    Button { commitTool() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 30)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            } else {
                // Zwei feste Felder statt einer scrollenden Pillenleiste: bei
                // nur noch zwei Bereichen ist Scrollen sinnlos und man sieht
                // nicht auf einen Blick, was das Studio kann. Beide teilen sich
                // die Breite gleichmaessig, der Zuruecksetzen-Knopf sitzt fest
                // daneben.
                HStack(spacing: 8) {
                    ForEach(Section.allCases) { item in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { section = item }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(item.label)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(section == item ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .glassEffect(section == item
                                         ? .regular.tint(Theme.accent).interactive()
                                         : .regular.interactive(),
                                         in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Button { resetEdits() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(edits.isNeutral ? Theme.textTertiary : Theme.textPrimary)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(edits.isNeutral)
                }
                .padding(.horizontal, 2)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        // Der Schatten braucht unten Platz, sonst schneidet ihn die Kante der
        // Tab-Leiste ab und er wirkt wie ein grauer Balken.
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Regler je Sektion

    /// Gesicht — gleiche Bauform wie Körper: ein Regler, darunter die Leiste.
    @ViewBuilder
    private var removeControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "paintbrush.pointed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: $eraseBrush, in: 0.02...0.16)
                    .tint(Theme.accent)
                Text("Brush")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                selectForegroundObject()
            } label: {
                Label(isDetectingEraseObject ? "Finding object…" : "Auto-select object", systemImage: "viewfinder")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isWorking || isDetectingEraseObject)

            HStack(spacing: 6) {
                Button { if !eraseStrokes.isEmpty { eraseStrokes.removeLast() } } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(eraseStrokes.isEmpty)

                Button { eraseStrokes = [] } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(eraseStrokes.isEmpty)

                Button { runErase() } label: {
                    Label("Remove", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .glassEffect(eraseStrokes.isEmpty ? .regular : .regular.tint(Theme.accent).interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(eraseStrokes.isEmpty || isWorking)
            }

            Text(eraseStrokes.isEmpty
                 ? "Paint, or let Clavic select the main object."
                 : "Soft glow preview · refine it with the brush if needed.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Die Vision-Auswahl ist nur ein Vorschlag: Nutzer können sie anschließend
    /// mit dem Pinsel verfeinern oder komplett löschen. So wird nie heimlich
    /// etwas anderes als sichtbar ausgewählt entfernt.
    private func selectForegroundObject() {
        guard let image = currentFullSizeImage(), !isDetectingEraseObject else { return }
        isDetectingEraseObject = true
        DispatchQueue.global(qos: .userInitiated).async {
            let suggestion = EraseMask.largestForegroundObjectStrokes(in: image)
            DispatchQueue.main.async {
                isDetectingEraseObject = false
                guard !suggestion.isEmpty else {
                    flash("No clear foreground object found — paint over it instead.")
                    return
                }
                eraseStrokes = suggestion
                flash("Object selected — refine the glow if needed.")
            }
        }
    }

    /// Baut Basis, Markierung und finale Maske aus exakt demselben sichtbaren
    /// Fullsize-Stand. Die Striche bleiben bei Consent, Paywall, Offline oder
    /// einem Modellfehler erhalten und verschwinden erst nach einem Erfolg.
    private func runErase() {
        guard !eraseStrokes.isEmpty,
              let base = currentFullSizeImage(),
              let prepared = EraseMask.prepare(base: base, strokes: eraseStrokes),
              let markedData = prepared.marked.jpegData(compressionQuality: 0.82) else {
            flash("The Remove mask could not be prepared.")
            return
        }
        runAI(
            EraseMask.prompt,
            extraImages: [markedData],
            eraseContext: EraseRequestContext(prepared: prepared)
        )
    }

    /// Server-Werkzeuge — schlanker Katalog (siehe StudioAITools.swift).
    private var chatControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                // Kamera direkt im Chat: Vorlage waehlen, sich danach ausrichten,
                // Ergebnis laeuft durch denselben Weg wie ein getippter Auftrag.
                Button { showPoseCamera = true } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                TextField("Change outfit, light, a detail…", text: $chatInstruction, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    // Waechst mit — vorher waren nach zwei Zeilen Schluss.
                    .lineLimit(1...6)
                    .focused($chatFocused)
                    .animation(Self.composerMotion, value: chatInstruction)

                Button { runChatEdit() } label: {
                    Image(systemName: isWorking ? "hourglass" : "arrow.up")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking || chatInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))

            // Fest statt scrollend: vier Vorschlaege in zwei Zeilen, alle
            // sofort sichtbar.
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    chatSuggestion("Change my outfit")
                    chatSuggestion("Aesthetic pose")
                }
                HStack(spacing: 6) {
                    chatSuggestion("Warmer light")
                    chatSuggestion("Make it sharper")
                }
            }

            Text("Describe only what should change — everything else stays as photographed.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private func chatSuggestion(_ text: String) -> some View {
        Button { chatInstruction = text } label: {
            Text(text)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.surfaceHigh, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func runChatEdit() {
        let instruction = chatInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        // Pose-Aenderungen gehen an Nano Banana 2. GEMESSEN am selben Foto:
        // GPT Image 2 liess die Haltung unveraendert und setzte stattdessen
        // eine Sonnenbrille auf, Nano Banana 2 drehte Kopf, Arm und Standbein
        // und behielt Gesicht und Kleidung.
        let model = EditPromptBooster.wantsPoseChange(instruction)
            ? ImageEditAPI.poseModel
            : nil

        chatInstruction = ""

        // Erst nachsehen, OB ein Mensch im Bild ist. Ohne diese Pruefung hing
        // der Booster auch an einem Autofoto „same face and hairstyle" an — und
        // das Modell erfand dafuer eine Person.
        let base = currentFullSizeImage() ?? previewSource
        Task {
            let hasPerson = base == nil ? nil : await SubjectDetector.hasPerson(in: base!)
            await MainActor.run {
                runAI(EditPromptBooster.build(instruction, hasPerson: hasPerson),
                      modelOverride: model)
            }
        }
    }

    private func aiToolCell(_ tool: StudioAITool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: tool.icon)
                .font(.system(size: 17, weight: .medium))
                .frame(height: 18)
            Text(tool.label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(aiFocus == tool.id ? Theme.accent : Theme.textSecondary)
        .frame(width: 58, height: 36)
        .background(aiFocus == tool.id ? Theme.accent.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func selectAITool(_ tool: StudioAITool) {
        aiInstruction = ""
        aiVariantID = tool.variants.first?.id
        withAnimation(.easeOut(duration: 0.2)) { aiFocus = tool.id }
    }

    private func aiButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: range)
                .tint(Theme.accent)
        }
    }

    // MARK: - Ablauf

    private func currentSnapshot() -> StudioSnapshot? {
        guard let original, let previewSource else { return nil }
        return StudioSnapshot(
            original: original,
            preview: previewSource,
            edits: edits,
            bodyAnalysis: analysis,
            faceAnalysis: faceAnalysis
        )
    }

    private func restore(_ snapshot: StudioSnapshot) {
        analysisRevision &+= 1
        original = snapshot.original
        previewSource = snapshot.preview
        edits = snapshot.edits
        analysis = snapshot.bodyAnalysis
        faceAnalysis = snapshot.faceAnalysis
        rendered = nil
        analyzing = false
        editingTool = false
        snapshotBeforeTool = nil
        eraseStrokes = []
        rerender()
    }

    private func beginTool() {
        guard !editingTool else { return }
        editsBeforeTool = edits
        snapshotBeforeTool = currentSnapshot()
        withAnimation(.easeOut(duration: 0.2)) { editingTool = true }
    }

    private func cancelTool() {
        if let snapshotBeforeTool { restore(snapshotBeforeTool) }
        else { edits = editsBeforeTool }
        self.snapshotBeforeTool = nil
        withAnimation(.easeOut(duration: 0.2)) { editingTool = false }
    }

    private func commitTool() {
        if let before = snapshotBeforeTool, before.edits != edits {
            history.remember(before)
        }
        snapshotBeforeTool = nil
        withAnimation(.easeOut(duration: 0.2)) { editingTool = false }
    }

    private func resetEdits() {
        guard !edits.isNeutral else { return }
        if let snapshot = currentSnapshot() { history.remember(snapshot) }
        edits = PhotoEdits()
        editingTool = false
        snapshotBeforeTool = nil
    }

    private func undo() {
        guard let current = currentSnapshot(),
              let previous = history.undo(from: current) else { return }
        restore(previous)
    }

    private func redo() {
        guard let current = currentSnapshot(),
              let next = history.redo(from: current) else { return }
        restore(next)
    }

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else {
            await MainActor.run { flash("That photo could not be opened.") }
            return
        }
        await load(ui)
    }

    /// Nimmt ein aus einem anderen Tab übergebenes Bild an.
    ///
    /// Die Vorgabe war, dabei den Reiter mit den kostenlosen lokalen Reglern zu
    /// öffnen. Den gibt es hier nicht mehr: Licht, Farbe, Haut und Körper sind
    /// aus dem Studio geflogen, geblieben sind „Remove" und „Chat" (siehe
    /// `Section`). Deshalb bleibt es bei der voreingestellten Ansicht, statt
    /// eine Auswahl zu erzwingen, die niemandem etwas spart.
    private func adoptHandoffImage() {
        guard let data = editHandoff.pendingStudioImage,
              let image = UIImage(data: data) else { return }
        editHandoff.pendingStudioImage = nil
        Task { await load(image) }
    }

    private func load(_ ui: UIImage) async {
        let normalized = PhotoEditEngine.normalizedForEditing(ui)
        let preview = PhotoEditEngine.preview(from: normalized)
        let revision = await MainActor.run { () -> Int in
            analysisRevision &+= 1
            original = normalized
            previewSource = preview
            edits = PhotoEdits()
            rendered = nil
            photoSelection = nil
            analysis = .fallback()
            faceAnalysis = .fallback()
            analyzing = true
            editingTool = false
            snapshotBeforeTool = nil
            history.reset()
            eraseStrokes = []
            return analysisRevision
        }
        await analyzePhoto(preview, revision: revision)
    }

    /// Analyse MUSS fertig sein, bevor ein Regler Eingaben annimmt. Die UI wird
    /// solange sichtbar gesperrt; so kann kein früher Slider-Tap versehentlich
    /// mit den groben Fallback-Zonen rendern.
    private func analyzePhoto(_ preview: UIImage, revision: Int) async {
        // Analyse auf der Vorschau — die Zonen sind relativ, gelten also
        // genauso fürs Original.
        // Körper und Gesicht parallel — beides läuft auf dem Gerät und darf
        // sich nicht gegenseitig aufhalten.
        async let bodyFound = BodyAnalyzer.analyze(preview)
        async let faceFound = FaceAnalyzer.analyze(preview)
        let (b, f) = await (bodyFound, faceFound)
        await MainActor.run {
            guard revision == analysisRevision else { return }
            analysis = b
            faceAnalysis = f
            analyzing = false
        }
    }

    /// Neu rechnen — auf der verkleinerten Vorschau, deshalb schnell genug,
    /// um beim Ziehen mitzukommen.
    private func rerender() {
        guard let source = previewSource else { return }
        if edits.isNeutral { rendered = nil; return }
        rendered = PhotoEditEngine.render(edits, from: source, analysis: analysis, face: faceAnalysis)
    }

    private func runAI(
        _ prompt: String,
        extraImages: [Data] = [],
        eraseContext: EraseRequestContext? = nil,
        baseImageOverride: UIImage? = nil,
        modelOverride: String? = nil,
        qualityOverride: String? = nil
    ) {
        guard acceptedContentPolicy else {
            pendingAIPrompt = prompt
            pendingAIExtraImages = extraImages
            pendingEraseContext = eraseContext
            pendingAIBaseImage = baseImageOverride
            pendingAIModel = modelOverride
            pendingAIQuality = qualityOverride
            showConsent = true
            return
        }
        guard let baseImage = baseImageOverride ?? eraseContext?.prepared.base ?? currentFullSizeImage(),
              let base = baseImage.jpegData(compressionQuality: eraseContext == nil ? 0.95 : 0.82) else { return }
        guard store.canCreate else { showSubscriptionGate = true; return }
        // Remove braucht nur eine kleine, lokal zusammengesetzte Inpainting-
        // Fläche. 1K/Seedream reagiert deutlich schneller; außerhalb der Maske
        // bleibt ohnehin jedes Originalpixel erhalten.
        let requestQuality = qualityOverride ?? (eraseContext == nil ? "medium" : "low")
        let cost = CreditCosts.imageEditCredits(quality: requestQuality)
        guard store.canAfford(cost) else {
            flash("Not enough credits — top up to keep editing.")
            return
        }
        let snapshotBeforeAI = currentSnapshot()
        isWorking = true
        Task {
            do {
                let request = ImageEditRequest(
                    prompt: prompt,
                    referenceImages: [base] + extraImages,
                    quality: requestQuality,
                    aspectRatio: "auto",
                    model: modelOverride ?? (eraseContext == nil ? ImageEditAPI.chatModel : ImageEditAPI.defaultModel)
                )
                let taskID = try await ImageEditAPI.createTask(request)
                // 200 × 3 s = 10 Minuten. Vorher waren es 80 (= 4 Minuten) — GEMESSEN
                // braucht GPT Image 2 bei 4K/high rund 282 s, also MEHR als das alte
                // Limit. Die App gab auf, während WaveSpeed weiterrechnete: Bild fertig,
                // abgerechnet, aber nie angezeigt ("Timeout"-Fehler trotz Kosten).
                for attempt in 0..<200 {
                    // Beim kleinen Remove-Job nicht erst drei Sekunden blind
                    // warten. Danach reicht ein engerer Poll-Rhythmus, damit das
                    // Ergebnis sofort erscheint, sobald der Provider fertig ist.
                    if attempt > 0 {
                        try? await Task.sleep(nanoseconds: 1_250_000_000)
                    }
                    let state = try await ImageEditAPI.fetchTask(id: taskID)
                    if state.status == .succeeded, let urlString = state.imageURL,
                       let url = URL(string: urlString),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let ui = UIImage(data: data) {
                        let generated = PhotoEditEngine.normalizedForEditing(ui)
                        let committed: UIImage
                        if let eraseContext {
                            // Das Modell darf ausserhalb der gemalten Maske kein
                            // Pixel veraendern. So bleiben Gesicht, Crop, Farbe
                            // und alle bisherigen lokalen Edits garantiert stehen.
                            guard let masked = EraseMask.composite(
                                generated,
                                using: eraseContext.prepared
                            ) else {
                                throw URLError(.cannotDecodeContentData)
                            }
                            committed = masked
                        } else {
                            committed = generated
                        }
                        let preview = PhotoEditEngine.preview(from: committed)
                        let revision = await MainActor.run { () -> Int in
                            if let snapshotBeforeAI { history.remember(snapshotBeforeAI) }
                            store.consume(cost)
                            analysisRevision &+= 1
                            original = committed
                            previewSource = preview
                            edits = PhotoEdits()
                            rendered = nil
                            analysis = .fallback()
                            faceAnalysis = .fallback()
                            analyzing = true
                            editingTool = false
                            snapshotBeforeTool = nil
                            if eraseContext != nil { eraseStrokes = [] }
                            if openChatAfterNextAI {
                                section = .chat
                                openChatAfterNextAI = false
                            }
                            // Ergebnis sofort auf dem Canvas zeigen. Die erneute
                            // Scan-Analyse darf danach im hellen Overlay laufen.
                            isWorking = false
                            return analysisRevision
                        }
                        await analyzePhoto(preview, revision: revision)
                        await MainActor.run {
                            guard revision == analysisRevision else { return }
                            flash(eraseContext == nil
                                  ? "Done — keep going with the sliders."
                                  : "Removed — the photo is updated.")
                        }
                        return
                    }
                    if state.status == .failed { break }
                }
            } catch {
                // fällt unten in die Fehlermeldung
            }
            await MainActor.run {
                isWorking = false
                openChatAfterNextAI = false
                flash("That edit failed — try again.")
            }
        }
    }

    /// Aktueller Stand in voller Auflösung (Regler auf das Original angewandt),
    /// immer im kanonischen `.up`/Scale-1-Pixelraum.
    private func currentFullSizeImage() -> UIImage? {
        guard let original else { return nil }
        let image = edits.isNeutral ? original : (PhotoEditEngine.render(edits, from: original, analysis: analysis, face: faceAnalysis) ?? original)
        return PhotoEditEngine.normalizedForEditing(image)
    }

    private func save() {
        guard let image = currentFullSizeImage() else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in flash("Allow Photos access in Settings to save.") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                Task { @MainActor in flash(ok ? "Saved to Photos." : "Saving failed.") }
            }
        }
    }

    private func flash(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run { if toast == text { toast = nil } }
        }
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.8), in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
