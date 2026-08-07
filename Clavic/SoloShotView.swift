//
//  SoloShotView.swift
//  Clavic
//
//  Ein geführter Kamera-Flow für Bilder, auf denen man selbst sein möchte,
//  ohne eine andere Person um ein Foto bitten zu müssen. Die Kamera nimmt den
//  echten Ort auf; die eigene Outfit-Referenz und eine sichtbare Platzierungs-
//  Markierung gehen danach als getrennte Referenzen an den Image-Edit-Flow.
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import CoreImage

private enum SoloShotFormat: String, CaseIterable, Identifiable {
    case square, portrait, story

    var id: String { rawValue }
    var label: String {
        switch self {
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .story: return "9:16"
        }
    }
    var aspect: CGFloat {
        switch self {
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .story: return 9.0 / 16.0
        }
    }
}

private enum SoloShotQuality: String, CaseIterable, Identifiable {
    case standard, high

    var id: String { rawValue }
    var label: String { self == .standard ? "Standard" : "High quality" }
    var apiQuality: String { self == .standard ? "medium" : "high" }
}

enum SoloShotPrompt {
    /// Zwei Bilder (bewusst nicht drei):
    ///   IMAGE 1 = Ort + blaue Platzierungs-Silhouette (WO / WIE GROSS)
    ///   IMAGE 2 = ich / Outfit / Identität
    ///
    /// Drei Fullsize-Referenzen + langer Prompt haben den Upload an die
    /// Gateway-Grenze gedrückt („That didn't work"). Die Guide-Datei enthält
    /// den Ort schon — ein separates Background-Bild ist überflüssig.
    static func build(
        userText: String,
        sceneImage: Data? = nil,
        placement: PlacementSuggestion? = nil
    ) -> String {
        let extra = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [core(placement: placement), identityRule]

        // Nach der Identitäts-Klausel, vor dem Licht: erst wer, dann wo, dann wie
        // beleuchtet. Das Modell gewichtet spätere Absätze stärker — die
        // Platzierung darf die Identität nicht verdrängen.
        if let placement {
            parts.append(placementRule(placement))
        }

        if let hint = sceneImage.flatMap({ SceneLightingHints.describe($0) }) {
            parts.append("""
            LIGHTING LOCK — match ME to the real location light in IMAGE 1, not to IMAGE 2.
            Measured look of the scene: \(hint)
            Relight every pixel of my skin, hair and clothes under that light. Discard \
            IMAGE 2's flash, ring light, flat indoor light and white balance completely. \
            Same key direction, colour temperature, exposure, grain and contact shadows \
            as IMAGE 1. If I still look pasted on, the lighting failed.
            """)
        } else {
            parts.append("""
            LIGHTING LOCK — match ME to the real location light in IMAGE 1, not to IMAGE 2.
            Relight every pixel of my skin, hair and clothes under IMAGE 1's light. \
            Discard IMAGE 2's flash, ring light and white balance. Same contact shadows \
            and grain as IMAGE 1. If I still look pasted on, the lighting failed.
            """)
        }

        if !extra.isEmpty {
            parts.append("""
            Extra direction from me (style and mood only — do not keep IMAGE 2's \
            lighting, do not keep my stiff selfie pose, do not change my identity, \
            do not alter IMAGE 1's background): \(extra)
            """)
        }
        return parts.joined(separator: "\n\n")
    }

    /// Die Klausel, die in JEDEM Bild-Prompt der App steht. Sie hat hier
    /// gefehlt — der Prompt umschrieb Identität zwar, benannte sie aber nie so
    /// hart, wie es der Rest der App tut.
    private static let identityRule = """
    Keep the exact same person: same face and every feature of it, same hair, same skin tone \
    and real skin texture, same build and body proportions, same age, same outfit. Do NOT \
    beautify, slim, smooth, retouch or redraw them, and do not replace them with a look-alike.
    """

    /// Die zwei Sätze zur markierten Region.
    ///
    /// Bewusst in der ICH-Form: der gesamte übrige Prompt spricht von „me".
    /// Ein Wechsel in die dritte Person mitten im Text ist der schnellste Weg
    /// zu zwei Personen im Ergebnis.
    private static func placementRule(_ placement: PlacementSuggestion) -> String {
        """
        Place me exactly inside the pink marked region of the reference image: that rectangle \
        is where my body belongs, my feet at its bottom edge, my head at its top edge. Remove \
        the pink marker itself completely — it must not appear in the output. I am \
        \(placement.poseSentence), in a position built for this location and not carried over \
        from the outfit reference. Match my lighting, shadow direction and colour temperature \
        to the location photo, and ground me with a real contact shadow where I meet the floor.
        """
    }

    /// Ohne Box bleibt es bei der von Hand ausgerichteten blauen Silhouette,
    /// mit Box ist die Markierung ein rosa Rechteck. Der Prompt muss dasselbe
    /// benennen, was wirklich im Bild liegt — sonst sucht das Modell eine
    /// Markierung, die es nicht gibt, und lässt die echte stehen.
    private static func core(placement: PlacementSuggestion?) -> String {
        let markerIntro = placement != nil
            ? "a pink semi-transparent rectangle marking WHERE I should stand and HOW LARGE I should be"
            : "a blue semi-transparent placement silhouette showing WHERE I should stand and HOW LARGE I should be"
        let marker = placement != nil ? "pink rectangle" : "blue silhouette"

        return """
    You are given exactly two reference images.
    IMAGE 1 = the real background location with \(markerIntro). The real \
    background is sacred: do not change, regenerate, crop or restyle it. Remove \
    the \(marker) completely from the result — it is only a placement guide, \
    not a pose guide and not part of the photo.
    IMAGE 2 = a photo of ME. Use it ONLY for identity and wardrobe: my exact face, \
    natural skin with every mole and freckle, body shape, hair, and the outfit \
    and shoes visible there. Someone who knows me must recognise me instantly. \
    Do NOT copy IMAGE 2's lighting onto the result.

    Create ONE photorealistic photograph: me, alone, naturally present in IMAGE 1's \
    location at the spot and size of the \(marker) — as if a real photographer \
    took this shot of me on location with the same camera. No other people.

    SCALE & PERSPECTIVE LOCK (critical — most failures happen here):
    - My height in the result MUST match the \(marker) height exactly. Do NOT \
    enlarge me to fill the frame.
    - Compare me to furniture and architecture in IMAGE 1 (doors, chairs, cabinets, \
    tables, windows). A real adult is roughly door-handle to top-of-door tall, never \
    as tall as a wardrobe or ceiling.
    - Match IMAGE 1's camera height, lens foreshortening and vanishing lines. If the \
    floor recedes, my feet sit on that same ground plane with correct perspective — \
    not floating, not sliding up walls.
    - If the \(marker) looks slightly large vs nearby objects, prefer the smaller, \
    physically believable size that still follows its position.

    GROUNDING & COMPOSITING:
    - Both feet (or seated contact) must touch a real surface in IMAGE 1 with soft \
    contact shadows and ambient occlusion under me.
    - Cast a subtle shadow consistent with IMAGE 1's light direction. Match depth of \
    field, noise/grain and colour of IMAGE 1 on my body.
    - I must look photographed in that room, not cut out and stuck on. No halo, no \
    hard cut-out edge, no plastic skin, no beauty filter.

    POSE: Do NOT copy the pose from IMAGE 2 or from the \(marker). Invent a new, \
    natural, aesthetic body pose that fits this exact location: correct weight on \
    the ground, believable balance, relaxed limbs, a head angle and gaze that belong \
    in the scene.

    Re-render my full body in that new pose as one continuous person — head, neck, \
    torso, arms, hands, legs and feet in my own build, with no seam at the neck or \
    wrists. Drape the outfit from IMAGE 2 naturally over that pose with real fabric \
    folds. No watermark, no leftover marker or outline.
    """
    }
}

struct SoloShotView: View {
    /// Das fertige Bild — der Nutzer kann es direkt im Studio weiterbearbeiten.
    let onFinish: (UIImage) -> Void
    let onCancel: () -> Void

    @Environment(Store.self) private var store
    @Environment(EditHandoff.self) private var editHandoff
    @Environment(\.modelContext) private var modelContext

    private enum Stage { case person, scene, review }
    /// Gallery/Selfie als eigene Card — nicht über die Kamera gelegt.
    private enum PersonCardPhase { case showcase, docked }

    @State private var stage: Stage = .person
    @State private var camera = PoseCameraModel()
    @State private var personSelection: PhotosPickerItem?
    @State private var backgroundSelection: PhotosPickerItem?
    @State private var personData: Data?
    @State private var personOverlay: UIImage?
    @State private var personCardPhase: PersonCardPhase = .showcase
    /// Rausziehen der Side-Card zum Ansehen — beim Loslassen zurück.
    @State private var personCardDrag: CGSize = .zero
    @State private var personCardDragging = false
    @State private var backgroundData: Data?
    /// Die Aufnahme, wie sie aus Kamera oder Mediathek kam — ohne Zuschnitt.
    /// Ohne sie ließe sich das Format im letzten Schritt nicht mehr ändern: der
    /// Zuschnitt wäre bereits eingebrannt.
    @State private var rawBackgroundData: Data?
    @State private var guideData: Data?
    /// Wie in der vorhandenen Pose-Kamera: Das gesamte Referenzbild liegt
    /// deckungsgleich und halbtransparent über dem Live-Bild.
    @State private var overlayOpacity: Double = 0.45
    /// Realistische Startgröße: bei 1 füllt die Figur den Rahmen (wirkt wie ein Schrank).
    @State private var overlayScale: CGFloat = 0.42
    @State private var liveScale: CGFloat = 1
    /// Normalisiert auf die Kamerabreite/-höhe, damit dieselbe Ausrichtung
    /// auch in der exportierten Placement-Referenz exakt erhalten bleibt.
    /// Leicht nach unten: Füße näher am Boden statt in der Bildmitte schweben.
    @State private var overlayOffset: CGSize = CGSize(width: 0, height: 0.12)
    @State private var liveOffset: CGSize = .zero
    /// Kein Knopf mehr: der Rahmen misst, wie viel Höhe ihm bleibt. Auf kurzen
    /// Geräten würde die volle Breite Auslöser, Regler und Hinweistext aus dem
    /// Bild drängen — dann schrumpft er von selbst.
    @State private var availableHeight: CGFloat = 0
    @State private var isCapturing = false
    @State private var countdown: Int?
    @State private var note = ""
    @State private var errorText: String?
    @State private var selectedFormat: SoloShotFormat = .portrait
    @State private var selectedQuality: SoloShotQuality = .standard
    @State private var keyboardVisible = false
    /// Das Erzeugen läuft jetzt HIER, nicht mehr erst nach dem Schließen im
    /// Studio: nur so kann der Wartezustand und danach das Ergebnis in dem
    /// Rahmen erscheinen, in dem man die Szene gerade ausgerichtet hat.
    @State private var isCreating = false
    @State private var workStartedAt: Date?
    @State private var resultImage: UIImage?
    /// Dieselben Bytes, die vom Server kamen — die Übergabe an Chat und Studio
    /// soll das Ergebnis nicht über ein erneutes Kodieren schicken.
    @State private var resultData: Data?
    @State private var showSubscriptionGate = false
    /// Vorschlag aus dem Livebild, verschobene Fassung der Nutzerin und die
    /// beim Auslösen eingefrorene Position. Der eingefrorene Stand ist der
    /// wichtige: nach dem Auslösen läuft keine Analyse mehr, die Marker-Referenz
    /// und der Prompt müssen sich aber noch auf genau diese Box beziehen.
    @State private var placement: PlacementSuggestion?
    @State private var manualPlacementRect: CGRect?
    @State private var placementIsAnalyzing = false
    @State private var capturedPlacement: PlacementSuggestion?
    /// Rahmenformat im Moment des Auslösens. Wird das Format im Review noch
    /// gewechselt, muss die Box mit umgerechnet werden — sie wurde gegen
    /// DIESES Verhältnis gemessen.
    @State private var capturedPlacementAspect: CGFloat = 1
    @FocusState private var noteFocused: Bool

    private var frameAspect: CGFloat { selectedFormat.aspect }

    /// Viewfinder-Radius: klein genug, dass oben/unten nicht wie ein Soft-Pill
    /// wirken, aber noch weich. Derselbe Wert für Kamera und Rückschau, damit
    /// die Kante beim Schrittwechsel nicht springt.
    private let cardCorner: CGFloat = 12

    /// Der Rahmen geht auf Kompaktgröße, wenn die Tastatur den Platz nimmt oder
    /// das Gerät schlicht zu kurz ist. `availableHeight == 0` heißt „noch nicht
    /// gemessen" — dann bleibt es bei der vollen Breite, damit beim ersten Bild
    /// nichts springt.
    private var cameraIsCompact: Bool {
        keyboardVisible || (availableHeight > 0 && availableHeight < 640)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // In allen drei Schritten dieselbe Kopfzeile: sie trägt das
                // Abbrechen-Kreuz und sagt, wo man gerade ist. Vorher gab es sie
                // nur im letzten Schritt — im Schritt „Ort" kam man deshalb gar
                // nicht mehr heraus, und der Aufbau sprang beim Wechsel.
                header
                switch stage {
                case .person: personStage
                case .scene: sceneStage
                case .review: reviewStage
                }
            }

            // Outfit-Card: erst normal (eigene Größe), dann nach links schweben.
            // Liegt bewusst NICHT als Overlay in der Kamera.
            if stage != .person, let personData, let image = UIImage(data: personData) {
                personFloatingCard(image)
                    .allowsHitTesting(personCardPhase == .docked)
                    .zIndex(40)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            availableHeight = height
        }
        .onAppear {
            Task { await camera.start() }
            #if DEBUG
            // Reproduzierbare Simulator-QA ohne Fotoauswahl: Referenz setzen und
            // direkt in den Ausricht-Schritt springen.
            let environment = ProcessInfo.processInfo.environment
            if environment["UITEST_SOLOSHOT_SAMPLE"] != nil,
               personData == nil,
               let sample = UIImage(named: "face_model_1"),
               let data = sample.jpegData(compressionQuality: 0.9) {
                personData = data
                preparePersonOverlay(from: data)
                personCardPhase = .docked
                stage = .scene

                if environment["UITEST_SOLOSHOT_REVIEW"] != nil,
                   let scene = UIImage(named: "sc_garage_after"),
                   let sceneData = scene.jpegData(compressionQuality: 0.9) {
                    finishBackground(sceneData)

                    if environment["UITEST_SOLOSHOT_LOADING"] != nil {
                        isCreating = true
                        workStartedAt = Date()
                    } else if environment["UITEST_SOLOSHOT_RESULT"] != nil {
                        resultImage = UIImage(named: "sc_garage_after")
                    }
                }
            }
            #endif
        }
        .onDisappear {
            camera.stopFrameStream()
            camera.stop()
        }
        .onChange(of: stage) { _, newStage in
            if newStage == .scene {
                startPlacementAnalysis()
            } else {
                camera.stopFrameStream()
            }
        }
        .onChange(of: personSelection) { _, item in
            guard let item else { return }
            Task { await loadPerson(from: item) }
        }
        .onChange(of: backgroundSelection) { _, item in
            guard let item else { return }
            Task { await loadBackground(from: item) }
        }
        .onChange(of: selectedFormat) { _, _ in
            guard stage == .review else { return }
            rebuildBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                keyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.90)) {
                keyboardVisible = false
            }
        }
        .overlay(alignment: .top) {
            if let errorText {
                Text(errorText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: errorText)
        .sheet(isPresented: $showSubscriptionGate) { PaywallView() }
    }

    private var header: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("SOLO SHOT")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .kerning(1.1)
                Text(headerSubtitle)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Color.clear.frame(width: 38, height: 38)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 10)
    }

    private var headerSubtitle: String {
        switch stage {
        case .person: return "1 · Your outfit"
        case .scene:
            return personCardPhase == .showcase ? "1 · Locked in" : "2 · Location"
        case .review: return "3 · Ready"
        }
    }

    // MARK: - Floating outfit card (nicht über der Kamera)

    /// Gallery/Selfie in natürlicher Größe mit runden Ecken → schwebt nach links
    /// schräg teilweise aus dem Bild. Rausziehen zum Ansehen, Loslassen = zurück.
    @ViewBuilder
    private func personFloatingCard(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let natural = image.size
            let aspect = natural.height > 0 ? natural.width / natural.height : 0.75
            let showcaseW = min(geo.size.width * 0.72, 320)
            let showcaseH = showcaseW / max(aspect, 0.45)
            let dockW: CGFloat = 88
            let dockH = dockW / max(aspect, 0.45)
            let isShowcase = personCardPhase == .showcase

            let cardW = isShowcase ? showcaseW : dockW
            let cardH = isShowcase ? min(showcaseH, geo.size.height * 0.58) : dockH
            // Links, schräg, teilweise außerhalb des Screens
            let dockX = dockW * 0.28
            let dockY = geo.size.height * 0.38
            let baseX = isShowcase ? geo.size.width * 0.5 : dockX
            let baseY = isShowcase ? geo.size.height * 0.42 : dockY
            let pull = hypot(max(0, personCardDrag.width), personCardDrag.height * 0.55)
            let peekScale: CGFloat = isShowcase ? 1 : (1 + min(pull / 140, 1) * 1.9)
            let peekRotation: Double = isShowcase ? 0 : (-8 + Double(personCardDrag.width / 36))

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cardW, height: cardH)
                .clipShape(RoundedRectangle(cornerRadius: isShowcase ? 18 : 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: isShowcase ? 18 : 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isShowcase ? 0.22 : 0.18), radius: isShowcase ? 22 : 14, y: 8)
                .scaleEffect(peekScale)
                .rotationEffect(.degrees(peekRotation))
                .position(
                    x: baseX + (isShowcase ? 0 : personCardDrag.width),
                    y: baseY + (isShowcase ? 0 : personCardDrag.height)
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard personCardPhase == .docked else { return }
                            personCardDragging = true
                            personCardDrag = CGSize(
                                width: min(max(value.translation.width, -36), 240),
                                height: min(max(value.translation.height, -180), 180)
                            )
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                personCardDrag = .zero
                                personCardDragging = false
                            }
                        }
                )
                .animation(
                    personCardDragging
                        ? nil
                        : .spring(response: 0.62, dampingFraction: 0.84),
                    value: personCardPhase
                )
        }
        .ignoresSafeArea()
    }

    /// Nach Selfie/Gallery: kurz normal zeigen, dann zur Side-Card animieren.
    private func presentPersonCard(with data: Data) async {
        personData = data
        preparePersonOverlay(from: data)
        personCardDrag = .zero
        personCardDragging = false
        personCardPhase = .showcase
        stage = .scene
        await switchToSceneCamera()

        try? await Task.sleep(nanoseconds: 520_000_000)
        withAnimation(.spring(response: 0.68, dampingFraction: 0.82)) {
            personCardPhase = .docked
        }
    }

    // MARK: - 1. Outfit reference

    /// NUR EIN dehnbarer `Spacer`, und der steht unten. Vorher rahmten zwei
    /// Spacer den Inhalt ein; SwiftUI teilt den Rest gleichmäßig auf beide auf,
    /// wodurch Kamera und Auslöser in die Bildschirmmitte rutschten statt oben
    /// zu stehen. Die zweite Knopfleiste unten ist ersatzlos weg — sie
    /// wiederholte Mediathek und Auslöser, die direkt unter der Kamera schon da
    /// sind, und das Abbrechen liegt jetzt in der Kopfzeile.
    private var personStage: some View {
        VStack(spacing: 12) {
            cameraFrame(showGhost: false)
                .padding(.horizontal, Theme.screenPadding)
                .frame(maxWidth: cameraIsCompact ? 245 : .infinity)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: cameraIsCompact)

            personShutterRow

            VStack(spacing: 4) {
                Text("REFERENCE PHOTO")
                    .font(.system(size: 11.5, weight: .black, design: .rounded))
                    .kerning(0.9)
                    .foregroundStyle(Theme.accent)

                Text("Take a full-body photo or choose one from your gallery.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 8)
        }
        .padding(.bottom, 12)
    }

    private var personShutterRow: some View {
        HStack(spacing: 0) {
            PhotosPicker(selection: $personSelection, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button { Task { await captureOutfitAfterCountdown() } } label: {
                ZStack {
                    Circle().fill(Theme.surface).frame(width: 66, height: 66)
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.20), lineWidth: 5)
                        .frame(width: 78, height: 78)
                    if isCapturing || countdown != nil {
                        ProgressView().tint(Theme.textPrimary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!camera.isAvailable || isCapturing || countdown != nil)
            .opacity(camera.isAvailable ? 1 : 0.35)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Take reference photo")

            Button { Task { await camera.flip() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!camera.isAvailable)
            .opacity(camera.isAvailable ? 1 : 0.35)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Switch front or back camera")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 2. Scene and placement

    private var sceneStage: some View {
        VStack(spacing: 12) {
            // Location-Kamera frei — Outfit sitzt als Card links, nicht darüber.
            cameraFrame(showGhost: false)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.leading, personCardPhase == .docked ? 36 : 0)
                .frame(maxWidth: cameraIsCompact ? 245 : .infinity)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: cameraIsCompact)
                .animation(.spring(response: 0.55, dampingFraction: 0.86), value: personCardPhase)

            if personCardPhase == .docked {
                sceneShutterRow

                captureSettings
                    .padding(.horizontal, 34)

                Text("Wir zeigen dir, wo du am besten stehst. Box verschieben, wenn du woanders hin willst.")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.opacity)
            }

            Spacer(minLength: 4)
        }
    }

    /// Halo-Aufbau unter der Kamera: Fotomediathek links, großer hohler
    /// Auslöser in der Mitte und Front-/Rückkamera rechts.
    private var sceneShutterRow: some View {
        HStack(spacing: 0) {
            PhotosPicker(selection: $backgroundSelection, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button { Task { await captureBackground() } } label: {
                ZStack {
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 66, height: 66)
                    Circle()
                        .strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 3)
                        .frame(width: 76, height: 76)
                    if isCapturing {
                        ProgressView().tint(Theme.textPrimary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!camera.isAvailable || isCapturing)
            .opacity(camera.isAvailable ? 1 : 0.35)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Take photo")

            Button { Task { await camera.flip() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!camera.isAvailable)
            .opacity(camera.isAvailable ? 1 : 0.35)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Switch front or back camera")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 3. Review

    private var reviewStage: some View {
        VStack(spacing: keyboardVisible ? 7 : 11) {
            if let backgroundData, let image = UIImage(data: backgroundData) {
                reviewPreview(image)
                    .frame(maxWidth: keyboardVisible ? 178 : .infinity)
                    .aspectRatio(previewAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: keyboardVisible ? 10 : cardCorner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: keyboardVisible ? 10 : cardCorner, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: keyboardVisible ? 8 : 16, y: 5)
                    .padding(.horizontal, keyboardVisible ? 0 : Theme.screenPadding)
                    .layoutPriority(1)
                    .animation(.spring(response: 0.36, dampingFraction: 0.88), value: keyboardVisible)
            }

            Spacer(minLength: keyboardVisible ? 0 : 6)

            if resultImage != nil {
                resultActions
                    .padding(.horizontal, Theme.screenPadding)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                if !isCreating {
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                        Slider(value: $overlayOpacity, in: 0.12...0.82)
                            .tint(Theme.accent)
                        Image(systemName: "photo.fill")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 28)

                    Text("Drag to place · pinch to size — then describe and create.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                soloShotComposer(createAction: create)
                    .padding(.horizontal, Theme.screenPadding)
                    .disabled(isCreating)
                    .opacity(isCreating ? 0.5 : 1)

                if !keyboardVisible && !isCreating {
                    Button {
                        stage = .scene
                        personCardPhase = .docked
                        Task { await switchToSceneCamera() }
                    } label: {
                        Text("Retake background")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, keyboardVisible ? 4 : 14)
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: keyboardVisible)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: resultImage != nil)
    }

    /// Nach dem Erzeugen: das Bild liegt bereits in der Bibliothek, von hier
    /// geht es entweder in den Editor oder in eine neue Aufnahme.
    private var resultActions: some View {
        VStack(spacing: 10) {
            Label("Saved to your library", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)

            // Zwei Wege aus dem Ergebnis heraus, beide mit dem Bild schon
            // geladen: reden (Chat) oder selbst Hand anlegen (Studio).
            HStack(spacing: 10) {
                Button {
                    editHandoff.pendingChatImage = resultData
                    onCancel()
                } label: {
                    Text("Im Chat weiterbearbeiten")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(resultData == nil)

                Button {
                    editHandoff.pendingStudioImage = resultData
                    onCancel()
                } label: {
                    Text("Im Studio öffnen")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassEffect(.regular.tint(Theme.accent).interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(resultData == nil)
            }

            Button {
                stage = .scene
                resultImage = nil
                resultData = nil
                Task { await switchToSceneCamera() }
            } label: {
                Text("New shot")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Format und Qualität im Ausricht-Schritt — dieselben Chips wie später in
    /// der Eingabeleiste, damit die Bedienung an beiden Stellen gleich aussieht.
    private var captureSettings: some View {
        HStack(spacing: 8) {
            formatChip
            qualityChip
        }
        .frame(maxWidth: .infinity)
    }

    private var formatChip: some View {
        Menu {
            Picker("", selection: $selectedFormat) {
                ForEach(SoloShotFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
        } label: {
            soloChip(icon: "aspectratio", text: selectedFormat.label)
        }
    }

    private var qualityChip: some View {
        Menu {
            Picker("", selection: $selectedQuality) {
                ForEach(SoloShotQuality.allCases) { quality in
                    Text(quality.label).tag(quality)
                }
            }
        } label: {
            soloChip(icon: "sparkles", text: selectedQuality == .standard ? "AUTO" : "HQ")
        }
    }

    private func soloChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 12.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    /// Gleiche Bauform wie die Eingabeleiste im Chat- und Agent-Tab: eine
    /// Liquid-Glass-Karte, Textfeld oben, darunter die Aktionszeile. Format und
    /// Qualität sitzen als Chips mit Auswahlmenü direkt darin, statt als eigene
    /// Reihe darüber zu schweben.
    private func soloShotComposer(createAction: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            TextField("Describe the pose, outfit or mood…", text: $note, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .font(.system(size: 16.5, weight: .medium, design: .rounded))
                .focused($noteFocused)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit {
                    noteFocused = false
                    hideKeyboard()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                PhotosPicker(selection: $backgroundSelection, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)

                formatChip
                qualityChip

                Spacer(minLength: 0)

                Button {
                    noteFocused = false
                    hideKeyboard()
                    createAction()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.tint(Theme.accent).interactive(), in: Circle())
                        .shadow(color: Theme.accent.opacity(0.28), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Liquid Glass (iOS 26) wie im Chat: die Leiste bricht das, was
        // darunter liegt, statt eine deckende Fläche zu sein.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }

    /// Solange nichts erzeugt wurde, gilt das gewählte Aufnahmeformat. Danach
    /// zählt das Seitenverhältnis des Ergebnisses, sonst würde die Karte das
    /// fertige Bild wieder beschneiden.
    private var previewAspect: CGFloat {
        if let resultImage, resultImage.size.height > 0 {
            return resultImage.size.width / resultImage.size.height
        }
        return frameAspect
    }

    private func reviewPreview(_ image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack {
                if let resultImage {
                    Image(uiImage: resultImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                        // Platzierung erst hier auf dem Location-Foto — nicht
                        // live über der Kamera mit dem Gallery-Bild.
                        alignedReferenceOverlay(in: geo.size, includeLiveTransform: true)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .allowsHitTesting(false)

                        if !isCreating {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    SimultaneousGesture(
                                        DragGesture()
                                            .onChanged { value in
                                                liveOffset = CGSize(
                                                    width: value.translation.width / max(geo.size.width, 1),
                                                    height: value.translation.height / max(geo.size.height, 1)
                                                )
                                            }
                                            .onEnded { _ in
                                                overlayOffset.width += liveOffset.width
                                                overlayOffset.height += liveOffset.height
                                                liveOffset = .zero
                                            },
                                        MagnifyGesture()
                                            .onChanged { liveScale = $0.magnification }
                                            .onEnded { _ in
                                                overlayScale = min(max(overlayScale * liveScale, 0.18), 2.5)
                                                liveScale = 1
                                            }
                                    )
                                )
                        }
                    }
                    .blur(radius: isCreating ? 30 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay { if isCreating { creatingOverlay } }
            .animation(.easeInOut(duration: 0.3), value: isCreating)
            .animation(.easeInOut(duration: 0.3), value: resultImage != nil)
        }
        .aspectRatio(previewAspect, contentMode: .fit)
    }

    /// Warte-Moment im Bildrahmen: Frost über der unscharfen Ausrichtung,
    /// darüber die Clavic-Animation. Aufbau wie `BlurLoadingCard` im Chat, aber
    /// bewusst ohne eigene Ecken — so gilt der runde Zuschnitt des
    /// Kamerarahmens und die Karte bleibt eine durchgehende Form.
    private var creatingOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)

            // Heller Video-Grund raus: multiply lässt ihn verschwinden, die
            // radiale Maske blendet die Ränder weich aus.
            IntroLoader()
                .frame(width: 150, height: 150)
                .mask(
                    RadialGradient(
                        gradient: Gradient(colors: [.black, .black, .clear]),
                        center: .center, startRadius: 24, endRadius: 78
                    )
                )
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
        .compositingGroup()
        // Fortschritt außerhalb der compositingGroup — sonst frisst das
        // multiply auch Balken und Schrift.
        .overlay(alignment: .bottom) {
            if let workStartedAt {
                GenerationProgress(startedAt: workStartedAt, estimate: 75)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.background.opacity(0.92),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(14)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Shared camera chrome

    @ViewBuilder
    private func cameraFrame(showGhost: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
        GeometryReader { geo in
            ZStack {
                // Volle Pixelgröße: ein `RoundedRectangle().fill` ohne Frame
                // nimmt sonst nur seine Idealgröße ein — dann bleiben oben und
                // unten graue „Kappen" sichtbar und die Ecken wirken falsch.
                Color.black
                    .frame(width: geo.size.width, height: geo.size.height)

                if camera.isAvailable {
                    // Die Ecken kommen von der UIView selbst: ein
                    // `AVCaptureVideoPreviewLayer` zeichnet sonst eckig über
                    // SwiftUI-`clipShape` hinaus — genau der Effekt, den man
                    // beim offenen Viewfinder als „nicht rund" sieht.
                    CameraPreviewLayer(camera: camera, cornerRadius: cardCorner)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Theme.surfaceHigh
                        .frame(width: geo.size.width, height: geo.size.height)
                    VStack(spacing: 8) {
                        Image(systemName: camera.permissionDenied ? "lock.fill" : "camera.fill")
                            .font(.system(size: 25, weight: .light))
                        Text(camera.permissionDenied ? "Camera access is off" : "No camera available")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.textSecondary)
                }

                if showGhost {
                    alignedReferenceOverlay(in: geo.size, includeLiveTransform: true)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(
                            SimultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        liveOffset = CGSize(
                                            width: value.translation.width / max(geo.size.width, 1),
                                            height: value.translation.height / max(geo.size.height, 1)
                                        )
                                    }
                                    .onEnded { _ in
                                        overlayOffset.width += liveOffset.width
                                        overlayOffset.height += liveOffset.height
                                        liveOffset = .zero
                                    },
                                MagnifyGesture()
                                    .onChanged { liveScale = $0.magnification }
                                    .onEnded { _ in
                                        overlayScale = min(max(overlayScale * liveScale, 0.18), 2.5)
                                        liveScale = 1
                                    }
                            )
                        )
                }

                // Kein Vergrößern-Knopf mehr: die Rahmengröße ergibt sich aus
                // dem verfügbaren Platz (siehe `cameraIsCompact`).
                if showGhost {
                    VStack {
                        HStack {
                            PhotosPicker(selection: $personSelection, matching: .images) {
                                Image(systemName: "photo.badge.arrow.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(.white.opacity(0.9), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Change overlay photo")

                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }

                // Die Box gehört zum Ausrichten des Ortes und nur dorthin.
                if stage == .scene {
                    PlacementBoxOverlay(
                        suggestion: placement,
                        manualRect: $manualPlacementRect,
                        frameSize: geo.size
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 76, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.32), radius: 12)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // compositingGroup zwingt auch den UIKit-Preview-Layer in denselben
            // Zuschnitt — ohne ihn bleiben die Kamerapixel an den Ecken eckig.
            .compositingGroup()
            .clipShape(shape)
        }
        .aspectRatio(frameAspect, contentMode: .fit)
        .frame(maxHeight: 500)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }

    @ViewBuilder
    private func alignedReferenceOverlay(in size: CGSize, includeLiveTransform: Bool) -> some View {
        // Cutout bevorzugen — klarere Größe als das volle Gallery-Rechteck.
        let image = personOverlay ?? personData.flatMap(UIImage.init(data:))
        if let image {
            let scale = overlayScale * (includeLiveTransform ? liveScale : 1)
            let offset = CGSize(
                width: (overlayOffset.width + (includeLiveTransform ? liveOffset.width : 0)) * size.width,
                height: (overlayOffset.height + (includeLiveTransform ? liveOffset.height : 0)) * size.height
            )
            let fitted = overlayFit(image.size, in: size)
            Image(uiImage: image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
                .scaleEffect(scale)
                .offset(offset)
                .opacity(overlayOpacity)
                .colorMultiply(Color(red: 0.55, green: 0.68, blue: 1.0))
        } else {
            Color.clear
        }
    }

    /// Größe, in der die Referenz vollständig in den Rahmen passt.
    private func overlayFit(_ image: CGSize, in frame: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return frame }
        let factor = min(frame.width / image.width, frame.height / image.height)
        return CGSize(width: image.width * factor, height: image.height * factor)
    }

    private func frameLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .black, design: .rounded))
            .kerning(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.accent.opacity(0.82), in: Capsule())
    }

    // MARK: - Live placement

    /// Höchstens acht Analysen je Sekunde, und nie zwei gleichzeitig. Die
    /// Kamera-Queue drosselt schon auf acht; das Gate hier fängt den Fall ab,
    /// dass eine Auswertung länger als 125 ms braucht — sonst stauen sich die
    /// Aufträge und die Box hinkt dem Bild sichtbar hinterher.
    private func startPlacementAnalysis() {
        camera.startFrameStream(minimumInterval: 0.125) { buffer, orientation in
            Task { @MainActor in
                analysePlacement(buffer, orientation: orientation)
            }
        }
    }

    private func analysePlacement(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        guard stage == .scene, !placementIsAnalyzing else { return }
        placementIsAnalyzing = true
        let previous = placement?.rect
        let aspect = frameAspect
        Task {
            let result = await PlacementSuggester.suggest(
                pixelBuffer: buffer,
                orientation: orientation,
                previousRect: previous,
                aspect: aspect
            )
            await MainActor.run {
                if stage == .scene { placement = result }
                placementIsAnalyzing = false
            }
        }
    }

    /// Die Box im Koordinatensystem des AKTUELLEN Zuschnitts. Solange das
    /// Format seit der Aufnahme gleich geblieben ist, ändert sich nichts.
    private func markerRect(_ rect: CGRect) -> CGRect {
        guard capturedPlacementAspect != frameAspect,
              let raw = rawBackgroundData,
              let image = UIImage(data: raw), image.size.height > 0 else { return rect }
        return ImageCrop.remap(
            rect,
            fromAspect: capturedPlacementAspect,
            toAspect: frameAspect,
            sourceAspect: image.size.width / image.size.height
        )
    }

    /// Beim Auslösen zählt, was in diesem Moment auf dem Bild lag — danach
    /// bewegt sich die Kamera weiter, der Vorschlag aber nicht mehr.
    private func freezePlacement() {
        if let rect = manualPlacementRect ?? placement?.rect {
            let pose = placement?.pose ?? .standing
            capturedPlacement = PlacementSuggestion(
                rect: rect,
                pose: pose,
                confidence: placement?.confidence ?? 1,
                poseSentence: PlacementSuggester.sentence(for: pose)
            )
            capturedPlacementAspect = frameAspect
        } else {
            capturedPlacement = nil
        }
        camera.stopFrameStream()
    }

    // MARK: - Capture and generation hand-off

    private func captureOutfitAfterCountdown() async {
        guard !isCapturing else { return }
        for value in stride(from: 3, through: 1, by: -1) {
            countdown = value
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        countdown = nil
        isCapturing = true
        defer { isCapturing = false }
        guard let data = await camera.capture(), UIImage(data: data) != nil else {
            flash("Couldn't capture your outfit. Try again.")
            return
        }
        // Selfie nicht in den Kamerarahmen zwingen — natürliche Größe der Card.
        await presentPersonCard(with: data)
    }

    private func captureBackground() async {
        noteFocused = false
        guard personCardPhase == .docked else { return }
        isCapturing = true
        defer { isCapturing = false }
        // Vor dem Foto einfrieren, nicht danach: zwischen Auslösen und
        // Speichern läuft die Analyse sonst noch einmal durch und die Box
        // wandert weg von dem, was die Nutzerin gesehen hat.
        freezePlacement()
        guard let data = await camera.capture() else {
            flash("Couldn't take that background shot.")
            return
        }
        finishBackground(data)
    }

    private func loadPerson(from item: PhotosPickerItem) async {
        defer { personSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
            flash("Couldn't read that outfit photo.")
            return
        }
        // Gallery-Bild so wie es ist (eigene Proportionen), nicht formatfüllend
        // über die Location-Kamera legen.
        await presentPersonCard(with: data)
    }

    private func loadBackground(from item: PhotosPickerItem) async {
        defer { backgroundSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            flash("Couldn't read that background photo.")
            return
        }
        // Ein Bild aus der Mediathek hat nie unter der Box gelegen — ein
        // stehengebliebener Vorschlag von vorhin würde hier ins Leere zeigen.
        capturedPlacement = nil
        finishBackground(data)
    }

    /// Der zweite Schritt zeigt den Ort, nicht das Gesicht — also auf die
    /// Rückkamera wechseln.
    ///
    /// Der `start()`-Aufruf davor ist der wichtigere Teil: `finishBackground`
    /// stoppt die Sitzung, bevor es zum Review geht. Wer dort „Retake
    /// background" tippt, landet wieder hier — und ohne Neustart zeigte der
    /// Rahmen nur noch Schwarz, weil die Vorschau an einer gestoppten Sitzung
    /// hängt. Der Wechsel allein half nicht: die Kamera steht dann längst
    /// hinten, `isFront` ist false, und der Zweig lief ins Leere.
    private func switchToSceneCamera() async {
        await camera.start()
        if camera.isFront { await camera.flip() }
    }

    private func finishBackground(_ raw: Data) {
        rawBackgroundData = raw
        guard rebuildBackground() else { return }
        camera.stop()
        stage = .review
    }

    /// Zuschnitt und Platzierungsvorlage aus der unveränderten Aufnahme neu
    /// aufbauen. Läuft auch, wenn im letzten Schritt das Format gewechselt
    /// wird — sonst zeigte die Vorschau zwar ein anderes Seitenverhältnis, aber
    /// weggeschickt wurde weiter die alt zugeschnittene Datei.
    @discardableResult
    private func rebuildBackground() -> Bool {
        guard let raw = rawBackgroundData else { return false }
        let cropped = ImageCrop.centerCrop(raw, toAspect: frameAspect) ?? raw
        guard let image = UIImage(data: cropped) else {
            flash("Couldn't prepare the placement guide.")
            return false
        }

        // Lag beim Auslösen eine Box auf dem Bild, ist sie die Markierung —
        // sie sagt Ort UND Größe, ohne die steife Selfie-Pose mitzuliefern.
        // Ohne Box bleibt es bei der von Hand ausgerichteten Silhouette.
        let guide: Data?
        if let capturedPlacement {
            guide = SoloShotGuide.renderMarker(on: image, rect: markerRect(capturedPlacement.rect))
        } else if let personOverlay {
            guide = SoloShotGuide.render(
                on: image,
                reference: personOverlay,
                scale: overlayScale,
                offset: overlayOffset
            )
        } else {
            guide = nil
        }

        guard let guide else {
            flash("Couldn't prepare the placement guide.")
            return false
        }
        backgroundData = cropped
        guideData = guide
        return true
    }

    private func create() {
        guard let personData, let backgroundData, let guideData, !isCreating else { return }
        guard store.canCreate else { showSubscriptionGate = true; return }
        let quality = selectedQuality.apiQuality
        let cost = CreditCosts.imageEditCredits(quality: quality)
        guard store.canAfford(cost) else {
            flash("Not enough credits — top up to keep creating.")
            return
        }

        let instruction = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // Licht-Hint aus dem unveränderten Ort; Upload = Guide (Ort+Silhouette) + ich.
        let prompt = SoloShotPrompt.build(
            userText: instruction,
            sceneImage: backgroundData,
            placement: capturedPlacement
        )
        isCreating = true
        workStartedAt = Date()

        Task {
            // Kompakter hochladen: drei Fullsize-Referenzen haben den Request
            // an die Gateway-Grenze gedrückt. Guide enthält den Ort bereits.
            let refs = [guideData, personData].compactMap {
                UIImage(data: $0)?.jpegForAPIUpload(maxDimension: 1024, quality: 0.72) ?? $0
            }
            guard refs.count == 2 else {
                await MainActor.run {
                    isCreating = false
                    flash("Couldn't prepare your photos — try again.")
                }
                return
            }

            do {
                let data = try await runSoloShotEdit(
                    prompt: prompt,
                    references: refs,
                    quality: quality,
                    model: ImageEditAPI.chatModel
                )
                await MainActor.run {
                    store.consume(cost)
                    persistToLibrary(
                        data,
                        prompt: instruction.isEmpty ? "Solo shot" : instruction,
                        cost: cost,
                        quality: quality
                    )
                    resultData = data
                    if let ui = UIImage(data: data) {
                        resultImage = PhotoEditEngine.normalizedForEditing(ui)
                    }
                    isCreating = false
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                await MainActor.run {
                    isCreating = false
                    flash(message.isEmpty ? "That didn't work — try again." : message)
                }
            }
        }
    }

    /// Erstellt den Edit und pollt bis Ergebnis oder Fehler. Bei GPT-Timeout/
    /// Gateway-Fehler einmal mit Seedream nachlegen — dasselbe Prompt-Paket,
    /// nur robusterer Upload-Pfad.
    private func runSoloShotEdit(
        prompt: String,
        references: [Data],
        quality: String,
        model: String
    ) async throws -> Data {
        func attempt(model: String) async throws -> Data {
            let request = ImageEditRequest(
                prompt: prompt,
                referenceImages: references,
                quality: quality,
                aspectRatio: "auto",
                model: model
            )
            let taskID = try await ImageEditAPI.createTask(request)
            var lastFailure: String?
            for attempt in 0..<200 {
                if attempt > 0 { try? await Task.sleep(nanoseconds: 1_250_000_000) }
                let state = try await ImageEditAPI.fetchTask(id: taskID)
                if state.status == .succeeded, let urlString = state.imageURL,
                   let url = URL(string: urlString) {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard UIImage(data: data) != nil else {
                        throw SeedanceError.invalidResponse
                    }
                    return data
                }
                if state.status == .failed {
                    lastFailure = state.failureReason
                    break
                }
            }
            throw SeedanceError.taskFailed(lastFailure ?? "Timed out — please try again.")
        }

        do {
            return try await attempt(model: model)
        } catch {
            // Nur soft failen, wenn GPT am Einreichen/Gateway scheitert — nicht
            // bei inhaltlichem Fail (dann würde Seedream oft dasselbe ablehnen).
            let text = (error as? LocalizedError)?.errorDescription?.lowercased() ?? ""
            let retryable = text.contains("unexpected response")
                || text.contains("unreachable")
                || text.contains("timed out")
                || text.contains("network")
                || text.contains("413")
                || text.contains("payload")
                || text.contains("too large")
                || text.contains("busy")
            guard model == ImageEditAPI.chatModel, retryable else { throw error }
            return try await attempt(model: ImageEditAPI.defaultModel)
        }
    }

    /// Gleiche Ablage wie im Chat und im Agent: Datei in Documents, Thumbnail
    /// fürs Raster, SwiftData-Eintrag. Damit taucht der Solo Shot in der
    /// Bibliothek auf, ohne dass man ihn extra sichern muss.
    private func persistToLibrary(_ data: Data, prompt: String, cost: Int, quality: String) {
        let ext = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
        let project = VideoProject(
            prompt: prompt,
            templateTitle: "Solo Shot",
            ratio: .portrait, resolution: .p720, duration: 0,
            generateAudio: false, useFastModel: true,
            referenceImagesData: [],
            isImageOutput: true, useKie: false,
            creditCost: cost, imageQuality: quality
        )
        let filename = "\(project.id.uuidString).\(ext)"
        let dest = URL.documentsDirectory.appending(path: filename)
        do { try data.write(to: dest) } catch { return }
        project.localVideoFilename = filename
        if let img = UIImage(data: data),
           let thumb = img.preparingThumbnail(of: CGSize(width: 600, height: 600 * img.size.height / max(img.size.width, 1))) {
            project.thumbnailData = thumb.jpegData(compressionQuality: 0.8)
        } else {
            project.thumbnailData = data
        }
        project.status = .succeeded
        modelContext.insert(project)
        try? modelContext.save()
    }

    private func preparePersonOverlay(from data: Data) {
        guard let image = UIImage(data: data) else { return }
        personOverlay = SoloShotPersonCutout.make(from: image) ?? image
    }

    private func flash(_ text: String) {
        withAnimation { errorText = text }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation { errorText = nil } }
        }
    }
}

/// Halbtransparente, absichtlich generische Figur. Sie ist eine Positionshilfe,
/// keine Vorschau des später erzeugten Körpers und wird nie exportiert.
private struct SoloShotGhost: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Capsule()
                    .fill(Theme.accent.opacity(0.22))
                    .frame(width: w * 0.68, height: h * 0.46)
                    .position(x: w * 0.5, y: h * 0.43)
                Circle()
                    .fill(Theme.accent.opacity(0.30))
                    .frame(width: w * 0.42, height: w * 0.42)
                    .position(x: w * 0.5, y: h * 0.14)
                HStack(spacing: w * 0.09) {
                    Capsule().fill(Theme.accent.opacity(0.24))
                    Capsule().fill(Theme.accent.opacity(0.24))
                }
                .frame(width: w * 0.54, height: h * 0.42)
                .position(x: w * 0.5, y: h * 0.78)
            }
            .overlay(
                RoundedRectangle(cornerRadius: w * 0.18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.92), lineWidth: 1.5)
            )
            .shadow(color: Theme.accent.opacity(0.85), radius: 10)
        }
        .accessibilityHidden(true)
    }
}

/// Die Referenz ist keine neue KI-Vorschau: Sie zeigt den wirklich gewählten
/// Galerie-Look als ausgeschnittene, bewegliche Stellvertreterin über dem
/// Live-Kamerabild. Damit sieht man vor dem Auslösen genau, wen Clavic später
/// in die Szene einsetzen soll.
private struct SoloShotReferenceOverlay: View {
    let image: UIImage

    var body: some View {
        ZStack {
            SoloShotGhost()
                .opacity(0.38)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.98), lineWidth: 1.5)
        )
        .shadow(color: Theme.accent.opacity(0.55), radius: 9)
        .accessibilityHidden(true)
    }
}

private enum SoloShotPersonCutout {
    private static let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
    ])

    static func make(from source: UIImage) -> UIImage? {
        let strokes = EraseMask.largestForegroundObjectStrokes(in: source)
        guard let prepared = EraseMask.prepare(base: source, strokes: strokes),
              let input = prepared.base.cgImage,
              let mask = prepared.mask.cgImage else { return nil }

        let extent = CGRect(x: 0, y: 0, width: input.width, height: input.height)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = CIImage(cgImage: input)
        blend.backgroundImage = CIImage(color: .clear).cropped(to: extent)
        blend.maskImage = CIImage(cgImage: mask)
        guard let output = blend.outputImage?.cropped(to: extent),
              let cutout = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: cutout, scale: 1, orientation: .up)
    }
}

private enum SoloShotGuide {

    /// Die Box als gefülltes Rechteck auf einer Kopie des Ortsfotos.
    ///
    /// Rosa, weil die Farbe in echten Innen- und Außenaufnahmen praktisch nie
    /// vorkommt: das Modell kann sie nicht mit etwas Vorhandenem verwechseln
    /// und entfernt sie deshalb zuverlässiger wieder.
    static func renderMarker(on source: UIImage, rect: CGRect) -> Data? {
        let normalized = PhotoEditEngine.normalizedForEditing(source)
        guard let cg = normalized.cgImage else { return nil }
        let size = CGSize(width: cg.width, height: cg.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: size))

            let marker = CGRect(
                x: rect.minX * size.width,
                y: rect.minY * size.height,
                width: rect.width * size.width,
                height: rect.height * size.height
            )
            guard marker.width > 0, marker.height > 0 else { return }
            UIColor.systemPink.withAlphaComponent(0.45).setFill()
            UIBezierPath(roundedRect: marker, cornerRadius: marker.width * 0.18).fill()
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    static func render(
        on source: UIImage,
        reference: UIImage,
        scale: CGFloat,
        offset: CGSize
    ) -> Data? {
        let normalized = PhotoEditEngine.normalizedForEditing(source)
        guard let cg = normalized.cgImage else { return nil }
        let size = CGSize(width: cg.width, height: cg.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            normalized.draw(in: CGRect(origin: .zero, size: size))

            let referenceSize = reference.size
            guard referenceSize.width > 0, referenceSize.height > 0 else { return }
            // `min`, nicht `max`: die Vorschau passt die Referenz vollständig in
            // den Rahmen ein. Mit formatfüllender Rechnung säße die Figur in der
            // exportierten Vorlage größer als dort, wo der Nutzer sie abgelegt
            // hat — und das Modell setzte sie entsprechend falsch ein.
            let fitScale = min(size.width / referenceSize.width,
                               size.height / referenceSize.height)
            let safeScale = min(max(scale, 0.18), 2.5)
            let drawSize = CGSize(
                width: referenceSize.width * fitScale * safeScale,
                height: referenceSize.height * fitScale * safeScale
            )
            let drawRect = CGRect(
                x: (size.width - drawSize.width) / 2 + offset.width * size.width,
                y: (size.height - drawSize.height) / 2 + offset.height * size.height,
                width: drawSize.width,
                height: drawSize.height
            )
            // Als getönte Silhouette zeichnen, nicht als klares Foto: sonst
            // liest das Modell die steife Selfie-Pose aus IMAGE 3 als Vorgabe.
            // Form + Größe bleiben; Gesicht/Outfit-Details werden absichtlich
            // unlesbar, damit nur die Platzierung zählt.
            let ghostFormat = UIGraphicsImageRendererFormat.default()
            ghostFormat.scale = 1
            ghostFormat.opaque = false
            let ghost = UIGraphicsImageRenderer(size: drawSize, format: ghostFormat).image { _ in
                let local = CGRect(origin: .zero, size: drawSize)
                reference.draw(in: local)
                UIColor(red: 0.18, green: 0.42, blue: 1.0, alpha: 1).setFill()
                UIRectFillUsingBlendMode(local, .sourceAtop)
            }
            ghost.draw(in: drawRect, blendMode: .normal, alpha: 0.48)
        }
        return image.jpegData(compressionQuality: 0.88)
    }
}
