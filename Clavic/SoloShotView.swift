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
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI
import UIKit
import Vision

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
    // Seedream accepts the complete instruction set; keeping this above the
    // immutable-scene rules prevents safety constraints from being truncated.
    static let maximumLength = 4_000

    /// Seedream bekommt getrennte Quellen mit genau einer Verantwortung:
    /// FIGURE 1 = finales Originalfoto, FIGURE 2 = reine Positionskarte,
    /// FIGURE 3 = Koerper und Kleidung, optional FIGURE 4 = enger Identitaets-
    /// und Haar-Crop. Diese Trennung verhindert, dass das Modell die rosa Karte
    /// als eigentliches Basisbild neu zeichnet oder das Gesicht erraten muss.
    static func build(
        userText: String,
        sceneImage _: Data? = nil,
        placement: PlacementSuggestion? = nil,
        hasIdentityCloseup: Bool = false
    ) -> String {
        let fallback = CGRect(x: 0.42, y: 0.34, width: 0.16, height: 0.42)
        let rect = placement?.rect ?? fallback
        let percent: (CGFloat) -> Int = { Int(($0 * 100).rounded()) }
        let pose = placement?.poseSentence ?? "standing naturally with believable balance"

        let identityCloseup = hasIdentityCloseup
            ? "FIGURE 4 is a tight identity lock for the same person's face and hair. Preserve its exact facial geometry, eye shape and color, nose, lips, jaw, hairline, parting, natural skin tone and marks, and exact hair base color, highlights and streak pattern. It is not a pose reference."
            : ""
        let required = """
        Create exactly one cohesive photorealistic camera photograph.

        FIGURE 1 is the immutable original scene and the final base image. Keep its exact crop, camera, lens, geometry, walls, floor, ceiling, furniture, bedding, screens, cables, objects, people, reflections, colors and exposure. Never remove, move, resize, clean, replace or redesign anything already visible.

        FIGURE 2 is only a placement map of FIGURE 1. Its pink rectangle spans x \(percent(rect.minX))–\(percent(rect.maxX))% and y \(percent(rect.minY))–\(percent(rect.maxY))% from the top-left. It is the maximum insertion zone, not a demand to show a full body or feet. Never render its rectangle, tint or guide marks.

        FIGURE 3 is the full identity and wardrobe reference. Insert exactly that person once: same facial structure and features, eye color, hairline, hair color and highlights, age, skin tone and marks, natural skin texture, body build and proportions, and the same visible outfit. Do not beautify, slim, smooth, recolor, change the face, add accessories or substitute a look-alike.

        \(identityCloseup)

        POSE OVERRIDE: FIGURE 3's pose is forbidden. Do not copy its head tilt, neck bend, shoulder angle, arm positions, seated posture or weight distribution. Build one continuous, anatomically correct person \(pose). Unless the user explicitly asks otherwise, keep the head naturally upright, neck unbent, shoulders relaxed and close to level, and use a calm gaze fitting FIGURE 1. Do not cut out, paste, overlay or preserve FIGURE 3 pixels. Discard all of FIGURE 3's lighting, white balance, sharpness and background.

        Photograph the person through FIGURE 1's camera: match its vanishing lines, camera height, focal length and depth. Use the pink zone for position and maximum scale, then verify scale against doors and furniture. Existing foreground has absolute priority: if a bed, blanket, table, person, plant or other object crosses the zone, leave it exactly where it is and place it naturally in front of the inserted person. Hide or crop unseen body parts behind that foreground or the frame edge. Never remove an object or reveal invented legs or feet just to show a full body.

        Reconstruct the same identity in the new scene-fitting pose; do not redesign it. Apply FIGURE 1's actual light over the locked skin and hair colors without changing their underlying color or identity. Match light direction, softness, exposure, color cast, contrast, depth of field, sensor grain, compression and edge softness. The person must not be cleaner, brighter, sharper or more saturated than the surrounding room. Add physically correct contact shadow, ambient occlusion, cast shadow, color spill and any required reflection. Local pixels may change where those effects touch the scene; everything else follows FIGURE 1.

        Every FIGURE 1 pixel outside the visible inserted person and a narrow natural contact-shadow edge is immutable. The result must look like one untouched real phone photo, never a sticker or composite. No halo, plastic skin, mannequin body, extra limbs, duplicate person, text, watermark or guide marks.
        """
        let compact = required
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = sanitizeUserNote(userText)
        guard !extra.isEmpty else { return String(compact.prefix(maximumLength)) }

        let suffix = "\n\nOptional direction applies only to the inserted person's pose or expression, never to FIGURE 1: "
        let available = maximumLength - compact.count - suffix.count
        guard available > 0 else { return String(compact.prefix(maximumLength)) }
        return compact + suffix + String(extra.prefix(available))
    }

    static func sanitizeUserNote(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let generic = text
            .lowercased()
            .replacingOccurrences(of: "[^a-zäöüß ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let ignored = [
            "add me", "add me in the image", "put me in the image",
            "insert me", "place me", "füge mich ein", "setz mich ins bild",
        ]
        return ignored.contains(generic) ? "" : text
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
    /// Kein Knopf mehr: der Rahmen misst, wie viel Höhe ihm bleibt. Auf kurzen
    /// Geräten würde die volle Breite Auslöser, Regler und Hinweistext aus dem
    /// Bild drängen — dann schrumpft er von selbst.
    @State private var availableHeight: CGFloat = 0
    @State private var isCapturing = false
    @State private var countdown: Int?
    @State private var note = ""
    @State private var errorText: String?
    @State private var selectedFormat: SoloShotFormat = .portrait
    /// One Shot soll standardmaessig das finale 2K-Foto liefern. 1K bleibt als
    /// guenstigere Wahl erhalten, wird aber nicht mehr still bevorzugt.
    @State private var selectedQuality: SoloShotQuality = .high
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
            //
            // Nur im Ausricht-Schritt. Im Review ist das Outfit laengst
            // festgelegt — dort waere es nur noch ein zweites Bild, das ueber
            // dem Ortsfoto liegt und die Sicht auf die Platzierung nimmt.
            if stage == .scene, let personData, let image = UIImage(data: personData) {
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
        .fullScreenCover(isPresented: $showSubscriptionGate) { PaywallView() }
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
            cameraFrame()
                .padding(.horizontal, Theme.screenPadding)
                .frame(maxWidth: cameraIsCompact ? 245 : .infinity)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: cameraIsCompact)

            personShutterRow

            VStack(spacing: 4) {
                Text("REFERENCE PHOTO")
                    .font(.system(size: 11.5, weight: .black, design: .rounded))
                    .kerning(0.9)
                    .foregroundStyle(Theme.accent)

                Text("Use a clear photo of your face and outfit. A cropped reference stays cropped or naturally hidden — One Shot will never remove scene objects just to expose a full body.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
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
            cameraFrame()
                .padding(.horizontal, Theme.screenPadding)
                .padding(.leading, personCardPhase == .docked ? 36 : 0)
                .frame(maxWidth: cameraIsCompact ? 245 : .infinity)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: cameraIsCompact)
                .animation(.spring(response: 0.55, dampingFraction: 0.86), value: personCardPhase)

            if personCardPhase == .docked {
                sceneShutterRow

                captureSettings
                    .padding(.horizontal, 34)

                Text("We show you where to stand. Drag the box if you want to be somewhere else.")
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
                    Text("The box is the maximum area for you. Existing beds, furniture and foreground always stay in place and may naturally cover part of the body.")
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
                    if let resultData { editHandoff.sendToChat(resultData) }
                    onCancel()
                } label: {
                    Text("Keep editing in Chat")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(resultData == nil)

                Button {
                    // Ging frueher ins Studio. Das gibt es nicht mehr — und
                    // der Chat kann alles, was man hier anschliessend will.
                    if let resultData { editHandoff.sendToChat(resultData) }
                    onCancel()
                } label: {
                    Text("Open in Chat")
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
            TextField("Optional pose or expression…", text: $note, axis: .vertical)
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

                        // Hier lag frueher die Outfit-Referenz als halb
                        // durchsichtige Silhouette ueber dem Ortsfoto. Zwei
                        // Bilder uebereinander sind aber genau das, was man
                        // nicht sehen will — und die Box sagt dasselbe, ohne
                        // das Foto zuzudecken.
                        if !isCreating {
                            PlacementBoxOverlay(
                                suggestion: effectivePlacement,
                                manualRect: $manualPlacementRect,
                                frameSize: geo.size
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
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
    private func cameraFrame() -> some View {
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

    /// Die Box, die wirklich gilt: die Hand der Nutzerin schlaegt den
    /// eingefrorenen Vorschlag, und wenn es beides nicht gibt (Bild aus der
    /// Mediathek), steht sie mittig auf dem Boden. Eine Markierung muss es
    /// immer geben — ohne sie weiss das Modell nicht, wie gross die Person
    /// sein soll, und macht sie so hoch wie einen Schrank.
    private var effectivePlacement: PlacementSuggestion {
        let rect = manualPlacementRect ?? capturedPlacement?.rect ?? Self.defaultBox
        let pose = capturedPlacement?.pose ?? .standing
        return PlacementSuggestion(
            rect: rect,
            pose: pose,
            confidence: capturedPlacement?.confidence ?? 1,
            poseSentence: PlacementSuggester.sentence(for: pose),
            tiltDegrees: capturedPlacement?.tiltDegrees
        )
    }

    /// Mittig, Fuesse im unteren Viertel — dieselben Proportionen, die der
    /// Suggester auch vorschlaegt (Verhaeltnis rund 1 : 2,6).
    private static let defaultBox = CGRect(x: 0.42, y: 0.34, width: 0.16, height: 0.42)

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
        // stehengebliebener Vorschlag von vorhin wuerde hier ins Leere zeigen.
        // Stattdessen die Standardbox, die sich im Review verschieben laesst.
        capturedPlacement = nil
        manualPlacementRect = nil
        capturedPlacementAspect = frameAspect
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

        // Immer der rosa Marker. Frueher lag hier wahlweise die getoente
        // Outfit-Silhouette — die deckte das Ortsfoto zu und lieferte dem
        // Modell nebenbei die steife Selfie-Haltung als Vorlage mit.
        let guide = SoloShotGuide.renderMarker(on: image, rect: markerRect(effectivePlacement.rect))

        guard let guide else {
            flash("Couldn't prepare the placement guide.")
            return false
        }
        backgroundData = cropped
        guideData = guide
        return true
    }

    private func create() {
        guard !isCreating else { return }
        // Die Box laesst sich im Review noch verschieben — also die Markierung
        // unmittelbar vor dem Absenden neu zeichnen, nicht die von vorhin.
        guard rebuildBackground() else { return }
        guard let personData, let backgroundData, let guideData else { return }
        guard store.canCreate else { showSubscriptionGate = true; return }
        let quality = selectedQuality.apiQuality
        let cost = CreditCosts.imageEditCredits(quality: quality)
        guard store.canAfford(cost) else {
            flash("Not enough credits — top up to keep creating.")
            return
        }

        let instruction = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let aspectRatio = selectedFormat.label
        let lockedPlacement = effectivePlacement
        let lockedPlacementRect = markerRect(lockedPlacement.rect)
        isCreating = true
        workStartedAt = Date()

        Task {
            // FIGURE 1 muss das unmarkierte Original sein. Die rosa Karte ist
            // nur FIGURE 2; FIGURE 3 liefert Koerper und Kleidung. Ein enger
            // Gesichts-/Haar-Crop wird, wenn Vision ein Gesicht erkennt, als
            // FIGURE 4 zur Identitaetssperre angehaengt.
            let identityCloseup = await SoloShotIdentityReference.make(from: personData)
            let refs = [backgroundData, guideData, personData]
                + (identityCloseup.map { [$0] } ?? [])
            let prompt = SoloShotPrompt.build(
                userText: instruction,
                sceneImage: backgroundData,
                placement: lockedPlacement,
                hasIdentityCloseup: identityCloseup != nil
            )

            do {
                let generated = try await runSoloShotEdit(
                    prompt: prompt,
                    references: refs,
                    quality: quality,
                    aspectRatio: aspectRatio
                )
                guard let data = await SoloShotSceneLock.merge(
                    generatedData: generated,
                    originalData: backgroundData,
                    placementRect: lockedPlacementRect
                ) else {
                    throw SeedanceError.server(
                        "Couldn't isolate the inserted person without changing your scene. Please try another placement."
                    )
                }
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

    /// Ein einziger reproduzierbarer Modellpfad. Ein stiller Wechsel zu einem
    /// zweiten Modell wuerde Prompt und Referenzbedeutung wieder auseinander
    /// bringen und bei identischen Eingaben verschiedene Resultate erzeugen.
    private func runSoloShotEdit(
        prompt: String,
        references: [Data],
        quality: String,
        aspectRatio: String
    ) async throws -> Data {
        let request = ImageEditRequest(
            prompt: prompt,
            referenceImages: references,
            quality: quality,
            aspectRatio: aspectRatio,
            model: ImageEditAPI.soloShotModel,
            highFidelityReferences: true
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

    private func flash(_ text: String) {
        withAnimation { errorText = text }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation { errorText = nil } }
        }
    }
}

/// Liefert Seedream neben der Ganzkoerperreferenz einen hochaufgeloesten,
/// engen Kopf-Crop. So muss das Modell Gesichtszuege und Haarfarbe nicht aus
/// wenigen Pixeln der Ganzkoerperaufnahme erraten. Der Crop ist ausdruecklich
/// nur Identitaets-, niemals Posevorlage.
nonisolated enum SoloShotIdentityReference {
    static func make(from data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            crop(from: data)
        }.value
    }

    static func crop(from data: Data) -> Data? {
        guard let raw = UIImage(data: data) else { return nil }
        let image = PhotoEditEngine.normalizedForEditing(raw)
        guard let cg = image.cgImage else { return nil }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let face = request.results?.max(by: {
                  $0.boundingBox.width * $0.boundingBox.height
                      < $1.boundingBox.width * $1.boundingBox.height
              }) else { return nil }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let box = face.boundingBox
        let faceRect = CGRect(
            x: box.minX * width,
            y: (1 - box.maxY) * height,
            width: box.width * width,
            height: box.height * height
        )

        // Vision schliesst Haare groesstenteils aus dem Gesichtsrechteck aus.
        // Grosszuegig nach oben und seitlich erweitern, damit Haaransatz,
        // Scheitel, Grundfarbe und Highlights wirklich in FIGURE 4 liegen.
        let expanded = CGRect(
            x: faceRect.minX - faceRect.width * 0.75,
            y: faceRect.minY - faceRect.height * 1.05,
            width: faceRect.width * 2.5,
            height: faceRect.height * 2.65
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral

        guard expanded.width >= 80, expanded.height >= 80,
              let cropped = cg.cropping(to: expanded) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
            .jpegData(compressionQuality: 0.96)
    }
}

/// Seedream darf die Person realistisch neu beleuchten, aber es darf nicht das
/// Ortsfoto neu erfinden. Darum wird aus dem Ergebnis nur die eingefuegte
/// Personeninstanz (plus wenige weiche Randpixel fuer Haar/Kontaktschatten)
/// ueber das lokale Original gelegt. Der Rest stammt wieder aus FIGURE 1.
nonisolated enum SoloShotSceneLock {
    private static let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
    ])

    static func merge(
        generatedData: Data,
        originalData: Data,
        placementRect: CGRect
    ) async -> Data? {
        guard let generated = UIImage(data: generatedData),
              let original = UIImage(data: originalData) else { return nil }
        let analysis = await BodyAnalyzer.analyze(generated)
        guard analysis.hasPerson, let personMask = analysis.mask,
              let result = composite(
                generated: generated,
                original: original,
                personMask: personMask,
                placementRect: placementRect
              ) else { return nil }
        return result.jpegData(compressionQuality: 0.96)
    }

    /// Separat testbar: nur weisse Maskenpixel duerfen vom generierten Bild
    /// kommen. Die Placement-Zone verhindert, dass eine bereits im Original
    /// vorhandene Person an einer anderen Stelle versehentlich mitkopiert wird.
    static func composite(
        generated: UIImage,
        original: UIImage,
        personMask: CIImage,
        placementRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> UIImage? {
        let foreground = PhotoEditEngine.normalizedForEditing(generated)
        let background = PhotoEditEngine.normalizedForEditing(original)
        guard foreground.cgImage != nil,
              let backgroundCG = background.cgImage else { return nil }

        // Das lokale Ortsfoto bestimmt Aufloesung und Pixelraum. Seedreams
        // Person wird in diesen Raum skaliert; nicht umgekehrt.
        let size = CGSize(width: backgroundCG.width, height: backgroundCG.height)
        let extent = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let fittedForeground = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            foreground.draw(in: extent)
        }
        guard let fittedForegroundCG = fittedForeground.cgImage else { return nil }

        let foregroundCI = CIImage(cgImage: fittedForegroundCG)
        let backgroundCI = CIImage(cgImage: backgroundCG)
        let edgeRadius = max(3, min(size.width, size.height) * 0.003)

        let morphology = CIFilter.morphologyMaximum()
        morphology.inputImage = personMask.resizedMask(to: extent)
        morphology.radius = Float(edgeRadius)
        guard let expanded = morphology.outputImage else { return nil }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = expanded
        blur.radius = Float(max(1.5, edgeRadius * 0.45))
        guard let softened = blur.outputImage?.cropped(to: extent) else { return nil }

        let padX = max(0.055, placementRect.width * 0.22)
        let padY = max(0.055, placementRect.height * 0.14)
        let zone = CGRect(
            x: max(0, placementRect.minX - padX),
            y: max(0, placementRect.minY - padY),
            width: min(1, placementRect.maxX + padX) - max(0, placementRect.minX - padX),
            height: min(1, placementRect.maxY + padY) - max(0, placementRect.minY - padY)
        )
        let zonePixels = CGRect(
            x: zone.minX * size.width,
            y: (1 - zone.maxY) * size.height,
            width: zone.width * size.width,
            height: zone.height * size.height
        ).intersection(extent)
        let black = CIImage(color: .black).cropped(to: extent)
        let whiteZone = CIImage(color: .white)
            .cropped(to: zonePixels)
            .composited(over: black)
        let restrictToZone = CIFilter.multiplyCompositing()
        restrictToZone.inputImage = softened
        restrictToZone.backgroundImage = whiteZone
        guard let lockedMask = restrictToZone.outputImage?.cropped(to: extent) else { return nil }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = foregroundCI
        blend.backgroundImage = backgroundCI
        blend.maskImage = lockedMask
        guard let output = blend.outputImage?.cropped(to: extent),
              let cg = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}

private enum SoloShotGuide {
    /// FIGURE 2 ist keine zweite Basisaufnahme, sondern nur eine gut lesbare
    /// Positionskarte. Die Kontur ist eine MAXIMALE Einfuegezone, keine
    /// Ganzkoerper- oder Fussvorgabe. Vordergrund innerhalb der Zone bleibt.
    static func renderMarker(on source: UIImage, rect: CGRect) -> Data? {
        let normalized = PhotoEditEngine.normalizedForEditing(source)
        guard let cg = normalized.cgImage else { return nil }
        let size = CGSize(width: cg.width, height: cg.height)
        let canvas = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            normalized.draw(in: canvas)

            let proposed = CGRect(
                x: rect.minX * size.width,
                y: rect.minY * size.height,
                width: rect.width * size.width,
                height: rect.height * size.height
            )
            let marker = proposed.intersection(canvas.insetBy(dx: 2, dy: 2))
            guard marker.width > 8, marker.height > 8 else { return }

            let stroke = max(5, min(size.width, size.height) * 0.006)
            let radius = min(marker.width * 0.14, 30)
            let path = UIBezierPath(roundedRect: marker, cornerRadius: radius)
            UIColor.systemPink.withAlphaComponent(0.06).setFill()
            path.fill()
            UIColor.systemPink.withAlphaComponent(0.98).setStroke()
            path.lineWidth = stroke
            path.stroke()
        }
        return image.jpegData(compressionQuality: 0.90)
    }
}
