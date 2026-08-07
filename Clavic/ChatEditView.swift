//
//  ChatEditView.swift
//  Clavic
//
//  Dritter Tab: konversationale Bild-Bearbeitung. User lädt ein Bild
//  (oder startet per Text-Prompt) und „chattet" das Bild Schritt für Schritt
//  weiter — jede Nachricht ist eine Bild-Edit-Anweisung, die Antwort ist das
//  neu generierte Bild. Nutzt GPT Image 2 (WaveSpeed) über ImageEditAPI.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import Photos
import Combine
import AVKit

struct ChatEditView: View {
    @Environment(Store.self) private var store
    @Environment(EditHandoff.self) private var editHandoff
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var currentImage: Data?        // jeweils letztes Ergebnis → Referenz für nächsten Edit
    /// Ergebnisse, deren Reveal-Wipe schon lief (jedes nur einmal animieren).
    @State private var revealedResults: Set<UUID> = []
    @State private var isWorking = false
    @State private var isLoadingPhoto = false
    @State private var quality: ChatQuality = .medium
    /// Vom Nutzer gewähltes Seitenverhältnis. „auto" → aus dem Input-Bild ableiten
    /// (bzw. 1:1 bei Text-to-Image) und Ergebnis auf Input-Größe skalieren.
    @State private var proportion: ChatProportion = .auto
    @State private var photoSelections: [PhotosPickerItem] = []
    @AppStorage("acceptedContentPolicy") private var acceptedContentPolicy = false
    @State private var showConsent = false
    @State private var pendingPhotoItems: [PhotosPickerItem] = []
    /// Ausgewählte, aber noch NICHT gesendete Fotos. Sie leben bis zum Absenden
    /// im Eingabefeld — erst beim Senden wandern sie in den Chat. Mehrzahl,
    /// damit man mehrere Vorlagen kombinieren kann (z. B. Person + Auto).
    @State private var pendingImages: [Data] = []
    /// Chat kann jetzt zweierlei erzeugen: ein Bild (Standard) oder ein Video
    /// aus dem aktuellen Bild (Kling O3). Der Umschalter sitzt im Composer.
    @State private var makesVideo = false
    @State private var videoDuration: ChatVideoAPI.Duration = .short
    @State private var saveToast: String?
    @State private var previewItem: ChatImagePreviewItem?
    @State private var showSubscriptionGate = false
    /// Start des laufenden Jobs — speist die Wartezeit-Anzeige im Ladeplatzhalter.
    @State private var workStartedAt: Date?
    /// Übliche Dauer des laufenden Jobs (Bild: je nach Qualität, Video: länger).
    @State private var workEstimate: TimeInterval = 60
    /// Kamera-Modus („Recreate"): Referenzbild halbtransparent über der Kamera.
    @State private var showPoseCamera = false
    /// Kamera wurde angetippt, es fehlt aber noch die Einwilligung.
    @State private var pendingPoseCamera = false
    /// Fertig gebauter Prompt aus dem Kamera-Modus. Ist er gesetzt, geht ER an
    /// das Modell statt des Booster-Ergebnisses — im Chat steht weiterhin der
    /// kurze Satz, den der Nutzer geschrieben hat.
    @State private var overridePrompt: String?
    /// Modell für den nächsten Zug, wenn es NICHT das Chat-Modell sein soll.
    ///
    /// Der Chat läuft auf GPT Image 2 (beste Text-/Logo-Treue). Für einen
    /// Personen-Swap ist das die falsche Wahl: GEMESSEN kam ein ÄHNLICH
    /// aussehender, aber anderer Mensch heraus — Muttermal und Augenbrauen-
    /// Narbe des Originals fehlten, Gesichtsform und Bart waren verändert.
    /// OpenAI-Modelle geben ein echtes Gesicht bewusst nicht originalgetreu
    /// wieder. Seedream v5 Pro hat diese Schranke nicht und trägt in dieser
    /// App ohnehin alle Vorlagen, die Menschen in Szenen setzen.
    @State private var overrideModel: String?
    @FocusState private var inputFocused: Bool

    /// Eine einzige Kurve fuer alles, was sich beim Auf- und Zuklappen der
    /// Eingabe bewegt. `.smooth` schwingt nicht ueber — mit einer federnden
    /// Kurve schoben sich Bild und Textfeld gegeneinander und es wirkte hakelig.
    private static let composerMotion: Animation = .smooth(duration: 0.3)

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                // Start-Zustand: alles auf EINEM Screen, ohne Scrollen — Foto-Karte,
                // beliebte Edits und das (unveränderte) Eingabefeld unten.
                VStack(spacing: 0) {
                    if isLoadingPhoto {
                        photoLoadingRow
                        Spacer(minLength: 0)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    if inputFocused { inputFocused = false }
                })
                .safeAreaInset(edge: .bottom, spacing: 0) { editToolbar }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Luftigere Abstände als vorher (20 → 26): Gemini lässt
                        // zwischen den Zügen deutlich mehr Raum, das trägt den
                        // ruhigen Eindruck mehr als jedes Farbdetail.
                        LazyVStack(spacing: 26) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                                messageRow(msg, index: index)
                                    .id(msg.id)
                                    // Jeder Zug blendet weich ein und steigt leicht
                                    // auf, statt hart zu erscheinen.
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 14)),
                                        removal: .opacity
                                    ))
                            }
                            Color.clear.frame(height: 6)
                            if isLoadingPhoto {
                                photoLoadingRow
                            }
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: messages.count)
                    }
                    // Runter-Wischen schließt die Tastatur sofort (kein „hängen").
                    .scrollDismissesKeyboard(.immediately)
                    // Tippen auf die Nachrichten-/Bildfläche schließt die Tastatur
                    // (liegt VOR dem safeAreaInset → das Eingabefeld selbst bleibt
                    // fokussierbar). simultan → Buttons/Slider funktionieren weiter.
                    .simultaneousGesture(TapGesture().onEnded {
                        if inputFocused { inputFocused = false }
                    })
                    .safeAreaInset(edge: .bottom, spacing: 0) { editToolbar }
                    // Neuen Chat starten (Verlauf + gespeicherte Session löschen).
                    .overlay(alignment: .topTrailing) {
                        if !isWorking {
                            Button {
                                startNewChat()
                            } label: {
                                Label("New chat", systemImage: "square.and.pencil")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, Theme.screenPadding)
                            .padding(.top, 6)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        // Nur der Chat: ruhiger App-Hintergrund, keine Raster/Blöcke mehr.
        .background(Theme.background.ignoresSafeArea())
        // „Done"-Tastaturleiste (ganz rechts) — NUR wenn das Chat-Feld fokussiert
        // ist, damit sie nicht doppelt mit Studio erscheint (beide Tabs im Baum).
        .toolbar {
            if inputFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .onChange(of: photoSelections) { _, items in
            guard !items.isEmpty else { return }
            if !acceptedContentPolicy {
                pendingPhotoItems = items
                photoSelections = []
                showConsent = true
                return
            }
            Task { await loadPickedImages(items) }
        }
        .alert("Before you upload", isPresented: $showConsent) {
            Button("I agree & continue") {
                acceptedContentPolicy = true
                let items = pendingPhotoItems
                pendingPhotoItems = []
                if !items.isEmpty { Task { await loadPickedImages(items) } }
                if pendingPoseCamera { pendingPoseCamera = false; showPoseCamera = true }
            }
            Button("View policy") {
                if let url = URL(string: LegalLinks.terms.absoluteString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPhotoItems = []
                pendingPoseCamera = false
            }
        } message: {
            Text("Only upload photos of yourself or people who have given you permission. Do not create sexual, hateful, deceptive or otherwise harmful content, or impersonate others. By continuing you confirm you have the rights to the photo and agree to our content policy.")
        }
        .overlay(alignment: .top) {
            if let saveToast { toastView(saveToast) }
        }
        .animation(.easeInOut(duration: 0.2), value: saveToast)
        .fullScreenCover(item: $previewItem) { item in
            ChatImageFullscreenView(item: item) { data in
                saveImage(data)
            }
        }
        .sheet(isPresented: $showSubscriptionGate) {
            PaywallView()
        }
        .fullScreenCover(isPresented: $showPoseCamera) {
            PoseCameraView(
                onSend: { result in
                    showPoseCamera = false
                    // Denselben Weg nehmen wie ein normaler Chat-Zug: beide
                    // Bilder ins Eingabefeld, Satz hinein, absenden. Dadurch
                    // gelten Credits, Fehlerbehandlung, Verlauf und Library
                    // hier exakt wie sonst auch.
                    startPoseEdit(result)
                },
                onCancel: { showPoseCamera = false }
            )
        }
        .onAppear {
            restoreSessionIfNeeded()
            adoptHandoffImage()
        }
        .onChange(of: editHandoff.pendingChatImage) { _, _ in adoptHandoffImage() }
        #if DEBUG
        .onAppear {
            // UI-Review: Ladezustand simulieren (Blur + Clavic-Anim) bzw. ein
            // fertiges Ergebnis, um Karte/Buttons zu prüfen.
            let env = ProcessInfo.processInfo.environment
            if env["UITEST_CHAT_LOADING"] != nil, messages.isEmpty,
               let img = UIImage(named: "sc_garage_after"), let d = img.jpegData(compressionQuality: 0.9) {
                currentImage = d
                messages = [
                    ChatMessage(role: .assistant, text: nil, image: nil, isLoading: true)
                ]
            }
            if env["UITEST_CHAT_DONE"] != nil, messages.isEmpty,
               let before = UIImage(named: "sc_garage_before")?.jpegData(compressionQuality: 0.9),
               let after = UIImage(named: "sc_garage_after")?.jpegData(compressionQuality: 0.9) {
                currentImage = after
                revealedResults.insert(UUID())   // Platzhalter
                let msg = ChatMessage(role: .assistant, text: "add a green Lamborghini", image: after, isLoading: false, beforeImage: before)
                revealedResults.insert(msg.id)    // Wipe überspringen fürs Standbild
                messages = [msg]
            }
        }
        #endif
    }

    // MARK: - Studio-Hintergrund

    private var studioBackground: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // Dezentes Canvas-Raster
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 28
                    var x: CGFloat = 0
                    while x <= geo.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= geo.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += step
                    }
                }
                .stroke(Theme.stroke.opacity(0.55), lineWidth: 0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            RadialGradient(
                colors: [Theme.accent.opacity(0.10), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            LinearGradient(
                colors: [Color.clear, Theme.accent.opacity(0.06)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Studio-Header

    private var studioHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 46, height: 46)
                    .shadow(color: Theme.accent.opacity(0.28), radius: 10, y: 5)
                Image(systemName: "photo.artframe")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Image Studio")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(!pendingImages.isEmpty
                     ? "Photo ready — describe your edit below"
                     : (currentImage == nil ? "Upload & transform your photos" : "Tap image to compare · refine with edits"))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if currentImage != nil {
                HStack(spacing: 5) {
                    Circle().fill(Theme.success).frame(width: 7, height: 7)
                    Text("\(resultCount) edit\(resultCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.background, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var resultCount: Int {
        messages.filter { $0.role == .assistant && $0.image != nil && !$0.isOriginal }.count
    }

    // MARK: - Leerer Canvas

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 2)

            VStack(spacing: 5) {
                Text("Your photo, your rules")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("New hair, couple pics, dream outfit — just tell it.")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            // Auto-animierte Before/After-Showcase (3 Styles) — zeigt sofort,
            // was die App kann, statt es zu beschreiben.
            ChatShowcaseCarousel(items: [
                .init(before: "preview_pro_glow_before", after: "preview_pro_glow_after", caption: "Natural glow-up",   icon: "sparkles"),
                .init(before: "sc_watch_before",  after: "sc_watch_after",  caption: "Add a Rolex",       icon: "applewatch"),
                .init(before: "preview_image_edit_before", after: "preview_image_edit_after", caption: "Dream outfit", icon: "tshirt"),
                .init(before: "sc_garage_before", after: "sc_garage_after", caption: "Park a supercar",   icon: "car.fill"),
                .init(before: "sc_pool_before",   after: "sc_pool_after",   caption: "Build a pool",       icon: "figure.pool.swim")
            ])
            .frame(maxHeight: .infinity)

            PhotosPicker(selection: $photoSelections, maxSelectionCount: 6, matching: .images) {
                HStack(spacing: 9) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text("Choose photo")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.3), radius: 14, y: 6)
            }
            .buttonStyle(.plain)

            // Quick-start prompts
            quickStartPrompts

            Spacer(minLength: 2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick-Start Prompts

    /// Chips unter dem Foto-Button: kurze Satzanfänge, die zeigen, was der Chat
    /// kann — speziell für Frauen 18-25 (Couple-Fotos, Beach Waves, Glow-up).
    private var quickStartPrompts: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                quickChip("💑 Couple photo", "Put me and my boyfriend on a beach at sunset")
                quickChip("🌊 Beach waves", "Give me beach waves and a linen dress")
            }
            HStack(spacing: 8) {
                quickChip("✨ Natural glow-up", "Make me look like me, just better lighting and skin")
                quickChip("👗 Dream outfit", "Dress me for a rooftop dinner in Paris")
            }
        }
    }

    private func quickChip(_ label: String, _ prompt: String) -> some View {
        Button {
            input = prompt
            inputFocused = true
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.surfaceHigh, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var photoLoadingRow: some View {
        HStack {
            ClavicLoadingCard(caption: "Loading your photo")
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: ChatMessage, index: Int) -> some View {
        if msg.role == .user {
            editInstructionCard(msg.text ?? "")
        } else {
            studioImageCard(msg, step: assistantImageIndex(upTo: index))
                // Eingefügtes Foto und der dazugehörige Text sind EIN Zug des
                // Nutzers, liegen im Modell aber als zwei Nachrichten vor. Der
                // gleichmäßige Stack-Abstand (26) trennt sie deshalb zu stark —
                // hier lokal zusammenziehen, damit sie als Paar lesen.
                .padding(.bottom, groupsWithNextMessage(at: index) ? -18 : 0)
        }
    }

    /// true, wenn an `index` das eingefügte Foto steht und direkt danach der
    /// Text des Nutzers folgt.
    private func groupsWithNextMessage(at index: Int) -> Bool {
        guard messages.indices.contains(index), messages[index].isOriginal else { return false }
        let next = index + 1
        guard messages.indices.contains(next) else { return false }
        return messages[next].role == .user
    }

    private func assistantImageIndex(upTo index: Int) -> Int {
        messages.prefix(index + 1).filter { $0.role == .assistant && $0.image != nil && !$0.isOriginal }.count
    }

    /// Nutzer-Anweisung als rechtsbündige Sprechblase — Gemini-Layout, aber in
    /// unseren Theme-Farben: weiche graue Kapsel statt gesättigtem Blau, kein
    /// Rahmen, kein Schatten. Die Blase wächst nur so breit wie der Text und
    /// hört bei ~78 % der Breite auf, damit die Seite luftig bleibt.
    private func editInstructionCard(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 44)
            Text(text)
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    /// Das vom Nutzer EINGEFÜGTE Foto — bewusst NICHT die große Ergebnis-Karte.
    /// Es gehört zum eigenen Zug, sitzt also rechts wie eine gesendete Nachricht
    /// und bleibt klein: es ist der Input, nicht das Ergebnis. Die breite Karte
    /// (bildschirmbreit, 470 pt hoch) hat hier vorher alles überdeckt.
    private func sentPhotoBubble(_ msg: ChatMessage, ui: UIImage) -> some View {
        HStack {
            Spacer(minLength: 60)
            Button { previewItem = ChatImagePreviewItem(imageData: msg.image ?? Data(), beforeData: nil, caption: nil) } label: {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    // Seitenverhältnis zuerst, dann NUR eine Höhengrenze — sonst
                    // ist der Rahmen breiter als das Bild und es entstehen
                    // weiße Balken neben einem Hochformat.
                    .aspectRatio(ui.size.width / max(ui.size.height, 1), contentMode: .fit)
                    .frame(maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func studioImageCard(_ msg: ChatMessage, step: Int) -> some View {
        if msg.isLoading {
            // Warte-Moment: das aktuelle Bild geblurred, darüber die Clavic-
            // Animation (heller Hintergrund per multiply entfernt) — clean und
            // gut in Screen-Recordings.
            if let cur = currentImage, let ui = ChatImageCache.image(for: cur) {
                BlurLoadingCard(ui: ui, startedAt: workStartedAt, estimate: workEstimate)
            } else {
                HStack {
                    ClavicLoadingCard(caption: "Clavic is applying your edit",
                                      startedAt: workStartedAt, estimate: workEstimate)
                    Spacer(minLength: 0)
                }
            }
        } else if msg.isOriginal, let imgData = msg.image, let ui = ChatImageCache.image(for: imgData) {
            // Eingefügtes Foto: kleine Blase rechts, kein Badge, keine Hinweise.
            sentPhotoBubble(msg, ui: ui)
        } else if let video = msg.videoURL, let url = URL(string: video) {
            // Fertiges Video: spielt direkt im Verlauf, mit Speichern-Aktion.
            VStack(alignment: .leading, spacing: 10) {
                ChatVideoPlayer(url: url)
                HStack(spacing: 8) {
                    actionButton(icon: "square.and.arrow.down", text: "Save") { saveVideo(url) }
                    Spacer(minLength: 0)
                }
            }
        } else if let imgData = msg.image, let ui = ChatImageCache.image(for: imgData) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    stageBadge(msg: msg, step: step)
                    Spacer()
                    if !msg.isOriginal, msg.beforeImage != nil {
                        Label("Swipe to compare", systemImage: "arrow.left.and.right")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                // Kompaktes Ergebnis: ganzes Bild sichtbar (Fit) mit weichem
                // Blur-Fade an den Rändern. Ist ein „Vorher" vorhanden, IST das
                // Bild ein Wisch-Slider (Before/After direkt im Chat, kein Vollbild).
                Group {
                    if !msg.isOriginal, let bData = msg.beforeImage, let bUI = ChatImageCache.image(for: bData) {
                        // Argumente bewusst getauscht: links = Original (Before),
                        // rechts = Ergebnis (After). contentFill → beide Bilder füllen
                        // EXAKT denselben Rahmen → deckungsgleich, sauberer Wisch.
                        BeforeAfterSlider(before: ui, after: bUI,
                                          showLabels: true, isAnimating: false,
                                          interactive: true, contentFill: true)
                    } else {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .modifier(RevealWipe(
                                ui: ui,
                                active: !msg.isOriginal && !revealedResults.contains(msg.id),
                                onStarted: { revealedResults.insert(msg.id) }
                            ))
                    }
                }
                // WICHTIG — Reihenfolge: erst das Seitenverhältnis, dann NUR eine
                // Höhen-Grenze. Kein `maxWidth: .infinity` vor dem Rahmen, sonst
                // ist der Rahmen immer bildschirmbreit und ein Hochformat sitzt
                // mit weißen Balken darin. So legt sich der Rahmen exakt ums Bild.
                .aspectRatio(ui.size.width / max(ui.size.height, 1), contentMode: .fit)
                .frame(maxHeight: 470)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
                // Zentrieren passiert erst NACH dem Rahmen — die Karte selbst
                // bleibt so breit wie das Bild.
                .frame(maxWidth: .infinity, alignment: .center)
                // Querformate dürfen bis dicht an den Bildschirmrand laufen.
                .padding(.horizontal, -(Theme.screenPadding - 6))

                // Nur Ergebnisse landen hier — das eingefügte Foto läuft über
                // `sentPhotoBubble`. Der Hinweis „Describe what you want
                // changed" steht deshalb im Platzhalter des Eingabefelds.
                HStack(spacing: 8) {
                    actionButton(icon: "arrow.triangle.2.circlepath", text: "Refine") {
                        input = "Keep this, but "
                        inputFocused = true
                    }
                    actionButton(icon: "square.and.arrow.down", text: "Save") { saveImage(imgData) }
                    Spacer(minLength: 0)
                }
            }
        } else if let err = msg.text, err.hasPrefix("Error") {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                Text(err.replacingOccurrences(of: "Error: ", with: ""))
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.danger)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func stageBadge(msg: ChatMessage, step: Int) -> some View {
        Group {
            if msg.isOriginal {
                Label("Original", systemImage: "photo")
            } else {
                Label("Edit \(max(step, 1))", systemImage: "sparkles")
            }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(msg.isOriginal ? Theme.textSecondary : Theme.accent)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            msg.isOriginal ? AnyShapeStyle(Theme.surfaceHigh) : AnyShapeStyle(Theme.accentSoft),
            in: Capsule()
        )
    }

    private func actionButton(icon: String, text: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                if let text { Text(text).font(.system(size: 13, weight: .semibold, design: .rounded)) }
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edit-Toolbar (schwebend über Tastatur / Tab-Bar)

    // Aufbau nach Halo AI (aus `halocamera.MP4`, 31.07.2026, Sek 21–31
    // Bild für Bild abgelesen): eingeklappt ist der Composer EINE ruhige
    // Zeile. Erst beim Antippen klappt er auf, das Vorschaubild schrumpft und
    // die Einstellungen erscheinen als kleine Chips darüber. Dadurch sieht der
    // Chat im Ruhezustand leer und clean aus, statt vier Reihen Bedienelemente
    // zu zeigen, die man meistens nicht braucht.
    private var editToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            attachedImages
            if inputFocused { settingsChips }
            composerCard
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(Self.composerMotion, value: inputFocused)
        .animation(Self.composerMotion, value: makesVideo)
        // Auch die Anhaenge-Leiste gehoert zu derselben Bewegung, sonst laeuft
        // die Bildhoehe der uebrigen Leiste hinterher.
        .animation(Self.composerMotion, value: pendingImages.count)
    }

    /// Angehängte Fotos. GROSS solange man nichts schreibt, KLEIN sobald die
    /// Tastatur offen ist — sonst schiebt das Bild den Composer aus dem Bild.
    @ViewBuilder private var attachedImages: some View {
        if !pendingImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, data in
                        if let ui = ChatImageCache.image(for: data) {
                            ZStack(alignment: .topTrailing) {
                                // Seitenverhältnis zuerst, dann NUR eine
                                // Höhengrenze — sonst liegt der Rahmen nicht am
                                // Bild an und es entstehen weiße Balken.
                                Image(uiImage: ui)
                                    .resizable()
                                    .aspectRatio(ui.size.width / max(ui.size.height, 1), contentMode: .fit)
                                    .frame(maxHeight: inputFocused ? 96 : 185)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Theme.stroke, lineWidth: 1)
                                    )

                                Button {
                                    pendingImages.remove(at: idx)
                                    if pendingImages.isEmpty { currentImage = nil }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(.black.opacity(0.55), in: Circle())
                                        // Skalieren statt Schrift- und Rahmenmass
                                        // umzuschalten: Schriftgroessen werden von
                                        // SwiftUI nicht interpoliert, der Knopf
                                        // sprang deshalb sichtbar um.
                                        .scaleEffect(inputFocused ? 0.77 : 1, anchor: .topTrailing)
                                }
                                .buttonStyle(.plain)
                                .padding(7)
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    /// Format und Länge als kleine Chips ÜBER dem Feld, jeweils mit Menü.
    private var settingsChips: some View {
        HStack(spacing: 7) {
            Menu {
                Picker("", selection: $proportion) {
                    ForEach(makesVideo ? ChatProportion.videoMenuOrder : ChatProportion.menuOrder) { p in
                        if let sub = p.subtitle {
                            Text("\(p.label)\n\(sub)").tag(p)
                        } else {
                            Text(p.label).tag(p)
                        }
                    }
                }
            } label: {
                chip(icon: "aspectratio", text: proportion.label)
            }
            .disabled(isWorking)

            if makesVideo {
                Menu {
                    Picker("", selection: $videoDuration) {
                        ForEach(ChatVideoAPI.Duration.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                } label: {
                    chip(icon: "clock", text: videoDuration.label)
                }
                .disabled(isWorking)
            } else {
                Menu {
                    Picker("", selection: $quality) {
                        ForEach(ChatQuality.allCases) { q in
                            Text("\(q.label) · \(q.credits) cr").tag(q)
                        }
                    }
                } label: {
                    chip(icon: "resize", text: quality.label)
                }
                .disabled(isWorking)
            }

            Spacer(minLength: 0)

            Text("\(makesVideo ? videoDuration.credits : quality.credits) cr")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 12.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    /// Die Karte: Textfeld oben, darunter IMMER die Aktionszeile.
    ///
    /// Vorher waren Kamera und der Bild/Video-Umschalter nur sichtbar, wenn das
    /// Textfeld den Fokus hatte — man musste also erst ins Feld tippen, um an
    /// die Kamera zu kommen. Von außen sah das aus, als gäbe es die Knöpfe
    /// nicht bzw. als wären sie tot. Sie stehen jetzt dauerhaft da; nur die
    /// Format-Chips klappen bei Fokus zusätzlich auf.
    private var composerCard: some View {
        VStack(spacing: 10) {
            TextField(placeholder, text: $input, axis: .vertical)
                .font(.system(size: 16.5, weight: .medium, design: .rounded))
                // Waechst mit dem Text mit — bis zu acht Zeilen statt fuenf.
                // Bei fuenf war schon Schluss, obwohl darueber genug Platz ist;
                // laengere Anweisungen liefen dann in ein winziges Scrollfeld.
                .lineLimit(1...8)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit {
                    inputFocused = false
                    if canSend && !isWorking { Task { await send() } }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Ohne eigene Kurve springt die Leiste bei jedem Zeilenumbruch
                // hart um. `input` ist der Ausloeser, nicht der Fokus.
                .animation(Self.composerMotion, value: input)

            HStack(spacing: 8) {
                plusButton
                cameraButton
                Spacer(minLength: 0)
                modeToggle
                applyButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Liquid Glass (iOS 26): die Leiste bricht und beugt das, was darunter
        // durchscrollt, statt eine deckende Fläche zu sein.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }

    private var placeholder: String {
        if makesVideo { return "Describe the motion…" }
        return currentImage == nil ? "Describe your image…" : "Describe your edit…"
    }

    private var plusButton: some View {
        PhotosPicker(selection: $photoSelections, maxSelectionCount: 6, matching: .images) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private var cameraButton: some View {
        Button {
            inputFocused = false
            // Auch hier landen fremde Gesichter in der Pipeline —
            // dieselbe Einwilligung wie beim Foto-Upload.
            if !acceptedContentPolicy {
                pendingPoseCamera = true
                showConsent = true
            } else {
                showPoseCamera = true
            }
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    /// Kleiner runder Sende-Button (spart Platz im Chat).
    private var applyButton: some View {
        Button {
            inputFocused = false
            Task { await send() }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(
                    canSend ? .regular.tint(Theme.accent).interactive() : .regular,
                    in: Circle()
                )
                .shadow(color: canSend ? Theme.accent.opacity(0.28) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!canSend || isWorking)
        .animation(.spring(duration: 0.25), value: canSend)
    }

    /// Proportion- (Seitenverhältnis) und Size- (Auflösung) Auswahl direkt über
    /// dem Text-Eingabefeld, jeweils als Chip mit Dropdown.
    /// Bild ⇄ Video. Video ist nur sinnvoll, wenn ein Bild da ist — sonst gäbe
    /// es nichts zu animieren, deshalb schaltet der Knopf dann nicht um.
    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeChip(title: "Image", icon: "photo", active: !makesVideo) { makesVideo = false }
            modeChip(title: "Video", icon: "film", active: makesVideo) {
                guard currentImage != nil || !pendingImages.isEmpty else {
                    flashToast("Add a photo first — video animates your image.")
                    return
                }
                makesVideo = true
            }
        }
        .padding(2)
        .glassEffect(.regular, in: Capsule())
    }

    private func modeChip(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? .white : Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(active ? .regular.tint(Theme.accent).interactive() : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    // MARK: - Toast

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.textPrimary.opacity(0.92), in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Aktionen

    private func loadPickedImages(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await MainActor.run { isLoadingPhoto = true }
        var loaded: [Data] = []
        for item in items.prefix(6) {
            if let data = try? await item.loadTransferable(type: Data.self),
               UIImage(data: data) != nil {
                loaded.append(data)
            }
        }
        guard !loaded.isEmpty else {
            await MainActor.run { isLoadingPhoto = false; photoSelections = [] }
            return
        }
        await MainActor.run {
            isLoadingPhoto = false
            // Das erste Foto ist das Arbeitsbild (Format, Folge-Edits), alle
            // zusammen gehen als Referenzen an das Modell.
            currentImage = loaded[0]
            photoSelections = []
            // Die Fotos landen BEWUSST noch nicht im Chat, sondern groß im
            // Eingabefeld — der Chat füllt sich erst beim Absenden.
            pendingImages = loaded
            messages = []
            input = ""
            inputFocused = true
            flashToast(loaded.count == 1
                       ? "Photo ready — describe your edit."
                       : "\(loaded.count) photos ready — describe your edit.")
            ChatSessionStore.save(messages: messages, currentImage: currentImage)
        }
    }

    /// Skaliert ein Bild auf exakt die gewünschten Pixelmaße (Quality-erhaltend
    /// als PNG). Dient dazu, dass das Edit-Ergebnis dieselbe Größe behält wie das
    /// Input-Bild.
    private static func resizedImage(_ data: Data, to size: CGSize) -> Data? {
        guard let img = UIImage(data: data), size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let new = renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        return new.pngData()
    }

    /// Leitet das zum Bild passende Seitenverhältnis aus den von kie unterstützten
    /// Werten ab, damit Nano Banana 2 das Format beim Editieren nicht umdreht.
    /// Ohne Bild (Text-to-Image) → „auto".
    private func aspectRatio(for imageData: Data?) -> String {
        guard let data = imageData, let img = UIImage(data: data),
              img.size.width > 0, img.size.height > 0 else {
            return "auto"
        }
        let ratio = Double(img.size.width / img.size.height)
        let allowed: [(String, Double)] = [
            ("1:1", 1.0), ("3:4", 3.0/4.0), ("4:3", 4.0/3.0),
            ("2:3", 2.0/3.0), ("3:2", 3.0/2.0), ("9:16", 9.0/16.0),
            ("16:9", 16.0/9.0), ("4:5", 4.0/5.0), ("5:4", 5.0/4.0),
            ("2:1", 2.0), ("1:2", 0.5), ("3:1", 3.0), ("1:3", 1.0/3.0),
            ("21:9", 21.0/9.0), ("9:21", 9.0/21.0),
        ]
        var best = "auto"; var bestDiff = Double.infinity
        for (name, r) in allowed {
            let diff = abs(ratio - r)
            if diff < bestDiff { bestDiff = diff; best = name }
        }
        return best
    }

    /// Freie Nutzer-Prompts laufen durch den gemeinsamen Realismus-Booster
    /// (gleiche Logik wie im Studio und auf der Website).
    private func buildEditPrompt(_ user: String) -> String {
        EditPromptBooster.build(user)
    }

    /// Stellt die letzte Chat-Session nach einem App-Neustart wieder her.
    /// Reveal-Animationen werden für wiederhergestellte Ergebnisse übersprungen.
    private func restoreSessionIfNeeded() {
        guard messages.isEmpty, !isWorking,
              let snapshot = ChatSessionStore.load(),
              !snapshot.messages.isEmpty else { return }
        messages = snapshot.messages
        currentImage = snapshot.currentImage
        for msg in snapshot.messages { revealedResults.insert(msg.id) }
    }

    /// Nimmt ein aus einem anderen Tab übergebenes Bild an.
    ///
    /// Es kommt als normales Arbeitsbild in den Verlauf — genau so, wie ein
    /// selbst hochgeladenes Foto. Damit gelten für den nächsten Zug Credits,
    /// Fehlerbehandlung und Library-Ablage unverändert.
    private func adoptHandoffImage() {
        guard let data = editHandoff.pendingChatImage else { return }
        editHandoff.pendingChatImage = nil
        currentImage = data
        messages.append(ChatMessage(role: .assistant, text: nil, image: data,
                                    isLoading: false, isOriginal: true))
        messages.append(ChatMessage(role: .assistant,
                                    text: "Your photo is loaded. Tell me what to change.",
                                    image: nil, isLoading: false))
        ChatSessionStore.save(messages: messages, currentImage: currentImage)
    }

    /// Leert den Verlauf und die gespeicherte Session (Ergebnisse bleiben
    /// natürlich in der Library erhalten).
    private func startNewChat() {
        messages = []
        currentImage = nil
        revealedResults = []
        input = ""
        ChatSessionStore.clear()
    }

    /// Übernimmt das Paket aus dem Kamera-Modus und schickt es als ganz
    /// normalen Chat-Zug los.
    ///
    /// REIHENFOLGE IST WICHTIG: eigene Aufnahme zuerst, Vorlage danach. Der
    /// Prompt spricht von „IMAGE 1 ist ich, IMAGE 2 ist die Vorlage" — dreht
    /// man die Liste um, tauscht das Modell die Gesichter.
    private func startPoseEdit(_ result: PoseCameraResult) {
        startNewChat()
        pendingImages = [result.shot, result.reference]
        currentImage = result.shot
        input = result.instruction
        overridePrompt = result.prompt
        // GPT Image 2: hält Identität und übernimmt die Pose der Vorlage
        // zuverlässiger als Seedream (das oft nur das Gesicht tauscht oder die
        // steife Selfie-Pose stehen lässt).
        overrideModel = ImageEditAPI.chatModel
        // Pose-Edits brauchen genug Auflösung, damit Haut unter dem Szenenlicht
        // neu gerendert wird — 1K lässt Selfie-Licht oft sichtbar stehen.
        if quality == .low { quality = .medium }
        Task { await send() }
    }

    /// Video-Zug: animiert das aktuelle Chat-Bild über Kling O3.
    /// Bewusst derselbe Ablauf wie beim Bild — Nutzer-Blase, Ladeplatzhalter,
    /// Credits erst bei Erfolg — damit sich im Chat nichts anders anfühlt.
    private func sendVideo(_ rawPrompt: String) async {
        guard let source = pendingImages.first ?? currentImage else {
            flashToast("Add a photo first — video animates your image.")
            return
        }
        let cost = videoDuration.credits
        guard store.canCreate else { showSubscriptionGate = true; return }
        guard store.canAfford(cost) else {
            flashToast("Not enough credits — top up to keep creating.")
            return
        }

        let seconds = videoDuration.rawValue
        let ratio = proportion.aspectValue(for: source)

        await MainActor.run {
            for pending in pendingImages {
                messages.append(ChatMessage(role: .assistant, text: nil, image: pending, isLoading: false, isOriginal: true))
            }
            if let first = pendingImages.first { currentImage = first }
            pendingImages = []
            messages.append(ChatMessage(role: .user, text: rawPrompt, image: nil, isLoading: false))
            messages.append(ChatMessage(role: .assistant, text: nil, image: nil, isLoading: true))
            input = ""
            isWorking = true
            inputFocused = false
            workStartedAt = Date()
            workEstimate = TimeInterval(seconds) * 20 + 40
        }

        do {
            let taskID = try await ChatVideoAPI.createTask(image: source, prompt: rawPrompt,
                                                          seconds: seconds, aspectRatio: ratio)
            var url: URL?
            for _ in 0..<150 {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                switch try await ChatVideoAPI.fetchTask(id: taskID) {
                case .succeeded(let u): url = u
                case .failed(let reason): throw SeedanceError.server(reason)
                case .running: continue
                }
                if url != nil { break }
            }
            guard let url else { throw SeedanceError.server("Timed out — please try again.") }

            await MainActor.run {
                store.consume(cost)   // Credits ERST bei Erfolg.
                if let last = messages.indices.last {
                    messages[last] = ChatMessage(role: .assistant, text: nil, image: nil,
                                                 isLoading: false, videoURL: url.absoluteString)
                }
                isWorking = false
            }
        } catch {
            await MainActor.run {
                if let last = messages.indices.last {
                    messages[last] = ChatMessage(role: .assistant, text: "Error: \(error.localizedDescription)",
                                                 image: nil, isLoading: false)
                }
                isWorking = false
            }
        }
    }

    private func send() async {
        let rawPrompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPrompt.isEmpty, !isWorking else { return }

        if let reason = ContentPolicy.rejectionReason(for: rawPrompt) {
            flashToast(reason)
            return
        }

        if makesVideo {
            await sendVideo(rawPrompt)
            return
        }

        // Nano Banana 2 (kie) bearbeitet das vorhandene Foto — kein Text-to-Image.
        // kein Text-to-Image. Der Prompt wird je nach Absicht angepasst
        // (Hintergrund-only vs. Stil vs. kreative Änderung). Ohne Bild →
        // reiner Nutzer-Prompt (graues Seed-Bild für Text-to-Image).
        // Der Kamera-Modus liefert einen fertig gebauten Prompt (Bild-Reihenfolge,
        // Identitäts- und Realismus-Regeln). Der würde durch den Booster nur
        // verwässert, deshalb hat er Vorrang.
        let prompt: String
        if let ready = overridePrompt {
            prompt = ready
        } else if let data = currentImage {
            // Gleiche Pruefung wie im Studio: ohne Mensch im Bild darf der
            // Booster keine Personen-Regeln anhaengen.
            let hasPerson: Bool? = await {
                guard let ui = UIImage(data: data) else { return nil }
                return await SubjectDetector.hasPerson(in: ui)
            }()
            prompt = EditPromptBooster.build(rawPrompt, hasPerson: hasPerson)
        } else {
            prompt = rawPrompt
        }

        let cost = quality.credits
        guard store.canCreate else {
            showSubscriptionGate = true
            return
        }
        guard store.canAfford(cost) else {
            flashToast("Not enough credits — top up to keep editing.")
            return
        }
        // Erst hier verbrauchen: scheitert es oben an Credits, bleiben der
        // gebaute Prompt und die Modellwahl für den nächsten Versuch erhalten.
        let modelForThisRun = overrideModel
        overridePrompt = nil
        overrideModel = nil

        // Ohne Bild ist es echtes Text→Bild: eigenes GPT-Image-2-Modell, KEIN
        // Referenzbild. Vorher lief das über ein graues Seed-Bild durchs
        // Edit-Modell — das Modell musste dann ein leeres Bild „bearbeiten",
        // was Motiv und Bildaufbau unnötig eingeschränkt hat.
        let isTextToImage = currentImage == nil && pendingImages.isEmpty
        // Alle neu angehängten Fotos gehen als Referenzen mit (z. B. Person +
        // Auto). Ohne neue Anhänge dient das laufende Ergebnis als Referenz,
        // damit Folge-Edits weiter auf dem letzten Bild aufbauen.
        let references: [Data] = pendingImages.isEmpty
            ? (currentImage.map { [$0] } ?? [])
            : pendingImages
        // Seitenverhältnis: Nutzerwahl (Proportion-Chip) hat Vorrang; bei „auto"
        // aus dem echten Referenzbild ableiten, damit das Format nicht umgedreht
        // wird. Ohne Bild (Text-to-Image) und „auto" → 1:1.
        let aspect: String
        if proportion != .auto {
            aspect = proportion.rawValue
        } else {
            aspect = aspectRatio(for: currentImage)
        }
        // Pixelmaße des Input-Bildes merken, damit das Ergebnis hinterher exakt
        // auf dieselbe Größe skaliert wird („Größe bleibt immer gleich wie Input",
        // z. B. beim G7X-Stil-Edit — nur der Stil ändert sich, nicht die Abmessung).
        // Nur bei Proportion „auto" (Format erhalten); bei gewählter Proportion
        // behält das Ergebnis sein neues Format.
        let inputPixels: CGSize? = currentImage.flatMap { data in
            UIImage(data: data)?.cgImage.map { CGSize(width: $0.width, height: $0.height) }
        }
        let beforeForThisEdit = currentImage

        await MainActor.run {
            // Jetzt erst wandert das im Eingabefeld gehaltene Foto in den Chat —
            // als Ausgangsbild, direkt über der Anweisung.
            for picked in pendingImages {
                messages.append(ChatMessage(role: .assistant, text: nil, image: picked, isLoading: false, isOriginal: true))
            }
            pendingImages = []
            messages.append(ChatMessage(role: .user, text: rawPrompt, image: nil, isLoading: false))
            messages.append(ChatMessage(role: .assistant, text: nil, image: nil, isLoading: true))
            input = ""
            isWorking = true
            workStartedAt = Date()
            workEstimate = quality.estimatedSeconds
        }

        let request = ImageEditRequest(
            prompt: prompt,
            referenceImages: references,
            quality: quality.apiValue,
            aspectRatio: aspect,
            // Pose-Aenderungen brauchen Nano Banana 2 (siehe ImageEditAPI.poseModel).
            model: modelForThisRun
                ?? (isTextToImage
                    ? ImageEditAPI.chatGenerateModel
                    : (EditPromptBooster.wantsPoseChange(rawPrompt) ? ImageEditAPI.poseModel : ImageEditAPI.chatModel))
        )

        do {
            let taskID = try await ImageEditAPI.createTask(request)
            let result = try await pollTask(taskID)
            switch result {
            case .success(let imageData):
                // Bei Proportion „auto" (Format erhalten): Ergebnis auf exakt die
                // Pixelmaße des Input-Bildes skalieren, damit die Größe gleich
                // bleibt. Bei gewählter Proportion behält das Ergebnis sein Format.
                let finalData: Data
                if proportion == .auto, let inSize = inputPixels {
                    finalData = Self.resizedImage(imageData, to: inSize) ?? imageData
                } else {
                    finalData = imageData
                }
                await MainActor.run {
                    store.consume(cost)
                    currentImage = finalData
                    if let lastIdx = messages.indices.last {
                        messages[lastIdx] = ChatMessage(
                            role: .assistant,
                            text: rawPrompt,
                            image: finalData,
                            isLoading: false,
                            beforeImage: beforeForThisEdit
                        )
                    }
                    isWorking = false
                    // Ergebnis in „My Creations" (Library) ablegen.
                    persistToLibrary(finalData, prompt: rawPrompt, cost: cost)
                    ChatSessionStore.save(messages: messages, currentImage: currentImage)
                }
            case .failure(let reason):
                await MainActor.run {
                    if let lastIdx = messages.indices.last {
                        messages[lastIdx] = ChatMessage(role: .assistant, text: "Error: \(reason)", image: nil, isLoading: false)
                    }
                    isWorking = false
                    ChatSessionStore.save(messages: messages, currentImage: currentImage)
                }
            }
        } catch {
            await MainActor.run {
                if let lastIdx = messages.indices.last {
                    messages[lastIdx] = ChatMessage(role: .assistant, text: "Error: \(error.localizedDescription)", image: nil, isLoading: false)
                }
                isWorking = false
                ChatSessionStore.save(messages: messages, currentImage: currentImage)
            }
        }
    }

    private enum PollResult {
        case success(Data)
        case failure(String)
    }

    private func pollTask(_ taskID: String) async throws -> PollResult {
        // Transiente Netzwerk-Fehler beim Status-Check überbrücken (der Edit
        // läuft server-seitig weiter) — erst nach ~1 min durchgehender Fehler
        // aufgeben statt beim ersten "network connection was lost".
        var consecutiveErrors = 0
        // 200 × 3 s = 10 Minuten. Vorher waren es 80 (= 4 Minuten) — GEMESSEN
        // braucht GPT Image 2 bei 4K/high rund 282 s, also MEHR als das alte
        // Limit. Die App gab auf, während WaveSpeed weiterrechnete: Bild fertig,
        // abgerechnet, aber nie angezeigt ("Timeout"-Fehler trotz Kosten).
        for _ in 0..<200 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return .failure("Cancelled.") }
            let state: ImageEditTaskState
            do {
                state = try await ImageEditAPI.fetchTask(id: taskID)
                consecutiveErrors = 0
            } catch {
                consecutiveErrors += 1
                if consecutiveErrors >= 20 {
                    return .failure("Lost connection — please check your internet and try again.")
                }
                continue
            }
            switch state.status {
            case .succeeded:
                guard let urlString = state.imageURL, let url = URL(string: urlString) else {
                    return .failure("No image returned.")
                }
                let (data, _) = try await URLSession.shared.data(from: url)
                return .success(data)
            case .failed:
                return .failure(state.failureReason ?? "The edit failed.")
            default:
                continue
            }
        }
        return .failure("Timed out — please try again.")
    }

    /// Legt ein Chat-Ergebnis als Bild-Projekt in „My Creations" (Library) ab —
    /// gleiche Persistenz wie Template-/Studio-Bilder (Datei in Documents +
    /// Thumbnail + SwiftData-Eintrag). Fehler werden still geschluckt (das
    /// Ergebnis bleibt im Chat sichtbar).
    private func persistToLibrary(_ data: Data, prompt: String, cost: Int) {
        // Bytes 1:1 in Documents schreiben (verlustfrei), Endung nach Signatur.
        let ext = (data.starts(with: [0x89, 0x50, 0x4E, 0x47])) ? "png" : "jpg"
        let project = VideoProject(
            prompt: prompt,
            templateTitle: "Image Edit",
            ratio: .portrait, resolution: .p720, duration: 0,
            generateAudio: false, useFastModel: true,
            referenceImagesData: [],
            isImageOutput: true, useKie: false,
            creditCost: cost, imageQuality: quality.apiValue
        )
        let filename = "\(project.id.uuidString).\(ext)"
        let dest = URL.documentsDirectory.appending(path: filename)
        do {
            try data.write(to: dest)
        } catch {
            return
        }
        project.localVideoFilename = filename
        // Thumbnail (verkleinert) fürs Library-Raster.
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

    /// Video in die Fotos-Mediathek sichern (lädt es vorher herunter).
    private func saveVideo(_ url: URL) {
        Task {
            do {
                let (tmp, _) = try await URLSession.shared.download(from: url)
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("clavic-\(UUID().uuidString).mp4")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else {
                        Task { @MainActor in flashToast("Allow Photos access in Settings to save.") }
                        return
                    }
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: dest)
                    } completionHandler: { ok, _ in
                        Task { @MainActor in flashToast(ok ? "Saved to Photos." : "Saving failed.") }
                    }
                }
            } catch {
                await MainActor.run { flashToast("Could not download the video.") }
            }
        }
    }

    private func saveImage(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in flashToast("Allow Photos access in Settings to save.") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                Task { @MainActor in flashToast(ok ? "Saved to Photos." : "Saving failed.") }
            }
        }
    }

    private func flashToast(_ text: String) {
        saveToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run { if saveToast == text { saveToast = nil } }
        }
    }
}

// MARK: - Modelle

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let role: Role
    var text: String?
    var image: Data?
    var isLoading: Bool
    var isOriginal: Bool = false   // hochgeladenes Originalfoto (ohne Aktions-Buttons)
    /// Fertiges Video (Kling O3) — Chat kann Bild ODER Video liefern.
    var videoURL: String? = nil
    /// Referenzbild direkt vor diesem Edit (für Vorher/Nachher im Vollbild).
    var beforeImage: Data? = nil

    enum Role: String, Codable { case user, assistant }
}

/// Persistiert den Chat-Verlauf (inkl. Bilder) über App-Starts — vorher war
/// die Konversation nach jedem Neustart weg, nur die Ergebnisse lagen in der
/// Library. Ein einzelnes JSON in Documents reicht für die eine Session.
enum ChatSessionStore {
    struct Snapshot: Codable {
        var messages: [ChatMessage]
        var currentImage: Data?
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat-session.json")
    }

    /// Speichert asynchron (Bilder machen das JSON ein paar MB groß —
    /// nie den Main-Thread blockieren). Lade-Platzhalter werden übersprungen.
    static func save(messages: [ChatMessage], currentImage: Data?) {
        let snapshot = Snapshot(messages: messages.filter { !$0.isLoading },
                                currentImage: currentImage)
        let url = fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Vollbild-Vorschau

struct ChatImagePreviewItem: Identifiable {
    let id = UUID()
    let imageData: Data
    let beforeData: Data?
    let caption: String?
}

/// Vollbild-Vorschau: heller Hintergrund im App-Look, und der Vergleich läuft
/// über EINEN Tap aufs Bild statt über einen Umschalter. Vorher und Nachher
/// liegen exakt deckungsgleich übereinander und werden nur überblendet — das
/// Bild springt also nie, es wechselt weich an derselben Stelle.
struct ChatImageFullscreenView: View {
    let item: ChatImagePreviewItem
    var onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    /// true = Original sichtbar. Nur relevant, wenn es ein Vorher-Bild gibt.
    @State private var showingBefore = false

    private var afterImage: UIImage? { UIImage(data: item.imageData) }
    private var beforeImage: UIImage? { item.beforeData.flatMap { UIImage(data: $0) } }
    private var hasCompare: Bool { beforeImage != nil && afterImage != nil }

    private let previewInset: CGFloat = 20
    private let previewCorner: CGFloat = 18

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                Group {
                    if let after = afterImage {
                        stackedPreview(after: after, before: beforeImage)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .onAppear { if !hasCompare { showingBefore = false } }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Theme.surfaceHigh, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onSave(showingBefore ? (item.beforeData ?? item.imageData) : item.imageData)
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.brandGradient, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Untere Zeile: Bildunterschrift bzw. der Hinweis, dass Tippen vergleicht.
    @ViewBuilder private var footer: some View {
        VStack(spacing: 6) {
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            if hasCompare {
                Text(showingBefore ? "Tap to see the result" : "Tap to see the original")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    /// Beide Bilder deckungsgleich gestapelt; getauscht wird nur die Deckkraft.
    /// Dadurch bleibt die Position exakt gleich und der Wechsel ist ein Fade.
    private func stackedPreview(after: UIImage, before: UIImage?) -> some View {
        GeometryReader { geo in
            let w = max(0, geo.size.width - previewInset * 2)
            let h = max(0, geo.size.height - previewInset * 2)

            ZStack {
                Image(uiImage: after)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
                    .opacity(showingBefore ? 0 : 1)

                if let before {
                    Image(uiImage: before)
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: h)
                        .opacity(showingBefore ? 1 : 0)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: previewCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: previewCorner, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if hasCompare {
                    Text(showingBefore ? "BEFORE" : "AFTER")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(12)
                        .contentTransition(.opacity)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            .frame(width: geo.size.width, height: geo.size.height)
            // Ganzes Bild ist die Schaltfläche — kein separater Umschalter.
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasCompare else { return }
                withAnimation(.easeInOut(duration: 0.32)) { showingBefore.toggle() }
            }
        }
        .padding(.horizontal, previewInset)
    }
}

enum ChatQuality: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: return "1K"
        case .medium: return "2K"
        case .high: return "4K"
        }
    }
    var apiValue: String { rawValue }
    var credits: Int { CreditCosts.imageEditCredits(quality: rawValue) }

    /// GEMESSEN gegen die echte Produktions-Route (GPT Image 2 / WaveSpeed),
    /// nicht geschätzt: 2K brauchte 59 s, 4K 282 s. 4K ist rund fünfmal so
    /// langsam wie 2K — nicht doppelt. Diese Werte speisen die Wartezeit-
    /// Anzeige; sie dürfen nur zusammen mit einer neuen Messung geändert werden.
    var estimatedSeconds: TimeInterval {
        switch self {
        case .low: return 35
        case .medium: return 60
        case .high: return 285
        }
    }
}

/// Wählbares Seitenverhältnis („p") im Chat-Input. „auto" übernimmt das
/// Input-Format und skaliert das Ergebnis auf die Input-Größe; die anderen
/// Werte werden 1:1 an kie geschickt.
enum ChatProportion: String, CaseIterable, Identifiable {
    case auto
    case r1x1 = "1:1"
    case r9x16 = "9:16"
    case r16x9 = "16:9"
    case r3x4 = "3:4"
    case r4x3 = "4:3"
    case r2x3 = "2:3"
    case r3x2 = "3:2"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto"
        default: return rawValue
        }
    }

    /// Klarname unter dem Verhältnis — „9:16" sagt niemandem etwas, „Story"
    /// schon. Übernommen aus Halo AIs Aspect-ratio-Menü.
    var subtitle: String? {
        switch self {
        case .auto:  return nil
        case .r1x1:  return "Square"
        case .r9x16: return "Story"
        case .r16x9: return "Widescreen"
        case .r3x4:  return "Portrait"
        case .r4x3:  return "Landscape"
        case .r2x3:  return "Tall portrait"
        case .r3x2:  return "Wide landscape"
        }
    }

    /// Reihenfolge im Menü — die gebräuchlichen zuerst, wie bei Halo.
    static let menuOrder: [ChatProportion] = [.auto, .r2x3, .r3x2, .r1x1, .r9x16, .r16x9, .r3x4, .r4x3]
    /// Für Video ergeben Hoch-/Querformate jenseits der drei üblichen keinen
    /// Sinn — Kling rechnet ohnehin auf diese Raster.
    static let videoMenuOrder: [ChatProportion] = [.auto, .r1x1, .r9x16, .r16x9]

    /// Seitenverhältnis für die Video-API. Bei „Auto" wird es aus dem
    /// Ausgangsbild abgeleitet, damit das Video nicht anders beschnitten ist
    /// als das Bild, das der Nutzer gerade vor sich sieht.
    func aspectValue(for image: Data) -> String {
        guard self == .auto else { return rawValue }
        guard let ui = UIImage(data: image), ui.size.height > 0 else { return "9:16" }
        let r = ui.size.width / ui.size.height
        if r > 1.55 { return "16:9" }
        if r > 1.2 { return "4:3" }
        if r > 0.85 { return "1:1" }
        if r > 0.7 { return "3:4" }
        return "9:16"
    }
}

/// Clavic-Ladekarte: gleicher Hintergrundton wie `intro.mp4` (`Theme.background`),
/// kompakt im Studio-Thread — kein greller Weiß-Kasten.
/// Auto-durchlaufende Before/After-Showcase für den leeren Chat: drei „Styles"
/// (Uhr, Auto, Pool), jede Karte wischt sauber vom Original zum Ergebnis. Wechselt
/// automatisch alle paar Sekunden und ist per Swipe steuerbar.
struct ChatShowcaseCarousel: View {
    struct Item: Identifiable {
        let id = UUID()
        let before: String
        let after: String
        let caption: String
        let icon: String
    }
    let items: [Item]
    @State private var page = 0
    private let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    ZStack(alignment: .bottomLeading) {
                        if let b = UIImage(named: item.before), let a = UIImage(named: item.after) {
                            BeforeAfterSlider(before: b, after: a,
                                              sweepDuration: 2.6, showLabels: false,
                                              isAnimating: page == idx)
                        } else {
                            Theme.surfaceHigh
                        }
                        // Caption-Chip unten links.
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .bold))
                            Text(item.caption)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 13)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                        .padding(14)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
                    .padding(.horizontal, 2)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .shadow(color: .black.opacity(0.10), radius: 18, y: 10)

            HStack(spacing: 7) {
                ForEach(items.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.accent : Theme.textTertiary.opacity(0.3))
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.spring(duration: 0.3), value: page)
                }
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                page = (page + 1) % max(items.count, 1)
            }
        }
    }
}

/// Dekodierte, fürs Display verkleinerte Chat-Bilder. Verhindert, dass bei jedem
/// Re-Render (z. B. pro Tastendruck) die vollen 2K-Ergebnisbilder neu dekodiert
/// werden — DAS war die Ruckel-Quelle beim Tippen/Scrollen im Chat.
enum ChatImageCache {
    private static let cache = NSCache<NSNumber, UIImage>()

    static func image(for data: Data) -> UIImage? {
        let key = NSNumber(value: data.hashValue ^ data.count)
        if let hit = cache.object(forKey: key) { return hit }
        guard let src = UIImage(data: data) else { return nil }
        let maxDim: CGFloat = 900
        let largest = max(src.size.width, src.size.height)
        let display: UIImage
        if largest > maxDim, let thumb = src.preparingThumbnail(of: CGSize(
            width: src.size.width * maxDim / largest,
            height: src.size.height * maxDim / largest)) {
            display = thumb
        } else {
            display = src.preparingForDisplay() ?? src
        }
        cache.setObject(display, forKey: key)
        return display
    }
}

/// Einmaliger Reveal-Wipe für neue Ergebnisse: das scharfe Bild wischt von links
/// nach rechts über eine weiche Blur-Version, mit leuchtender Kante.
struct RevealWipe: ViewModifier {
    let ui: UIImage
    let active: Bool
    var onStarted: () -> Void = {}
    @State private var p: CGFloat

    init(ui: UIImage, active: Bool, onStarted: @escaping () -> Void = {}) {
        self.ui = ui
        self.active = active
        self.onStarted = onStarted
        _p = State(initialValue: active ? 0.02 : 1)
    }

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: max(p, 0.001), y: 1, anchor: .leading)
            }
            .background {
                // Weiche Vorschau hinter dem Wipe (füllt die noch verdeckte Fläche).
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 16)
                    .opacity(0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .overlay {
                if p < 1 {
                    GeometryReader { geo in
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.9), .white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 26)
                            .blur(radius: 3)
                            .position(x: geo.size.width * p, y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard active, p < 1 else { return }
                onStarted()
                withAnimation(.easeInOut(duration: 0.9).delay(0.12)) { p = 1 }
            }
    }
}

/// „Clavic arbeitet": das aktuelle Bild geblurred, darüber die Clavic-Logo-
/// Animation. Der helle Video-Hintergrund wird per `.blendMode(.multiply)`
/// entfernt (dunkles Logo bleibt, heller Grund verschwindet in der Frost-Ebene)
/// → sauber ins geblurte Bild eingefügt, ganz ohne weißen Kasten.
struct BlurLoadingCard: View {
    let ui: UIImage
    /// Wann der Job losging + wie lange er üblicherweise dauert. Ohne Werte
    /// bleibt die Karte wie vorher (z. B. in Vorschauen).
    var startedAt: Date? = nil
    var estimate: TimeInterval = 60

    var body: some View {
        ZStack {
            // Geblurtes Ausgangsbild + Frost-Ebene (damit das dunkle Logo auf
            // JEDEM Bild sauber liest).
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 240, maxHeight: 340)
                .clipped()
                .blur(radius: 30)
                .overlay(.ultraThinMaterial)

            // Clavic-Animation — heller Hintergrund raus: (1) multiply lässt den
            // hellen Video-Grund verschwinden, (2) die radiale Maske blendet die
            // Ränder weich aus → nie ein harter heller Kasten, egal was multiply macht.
            IntroLoader()
                .frame(width: 160, height: 160)
                .mask(
                    RadialGradient(
                        gradient: Gradient(colors: [.black, .black, .clear]),
                        center: .center, startRadius: 26, endRadius: 84
                    )
                )
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
        .compositingGroup()   // multiply nur innerhalb der Karte anwenden
        .frame(minHeight: 240, maxHeight: 340)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Fortschritt AUSSERHALB der compositingGroup — sonst würde das
        // multiply oben auch den Balken und die Schrift auffressen.
        .overlay(alignment: .bottom) {
            if let startedAt {
                // Eigene Fläche darunter: der Untergrund ist ein beliebiges
                // Foto — ohne sie wäre der Text auf hellen Bildern unlesbar.
                GenerationProgress(startedAt: startedAt, estimate: estimate)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.background.opacity(0.92),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}

struct ClavicLoadingCard: View {
    var caption: String = "Clavic is working on your edit"
    var startedAt: Date? = nil
    var estimate: TimeInterval = 60

    private let cardWidth: CGFloat = 156
    private let cardHeight: CGFloat = 118
    private let loaderSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.background)

                IntroLoader()
                    .frame(width: loaderSize, height: loaderSize)
                    .allowsHitTesting(false)
            }
            .frame(width: cardWidth, height: cardHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )

            TimelineView(.periodic(from: .now, by: 0.45)) { context in
                let n = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 3 + 1
                HStack(spacing: 3) {
                    Text(caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(String(repeating: ".", count: n))
                        .foregroundStyle(Theme.accent)
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
            }

            if let startedAt {
                GenerationProgress(startedAt: startedAt, estimate: estimate)
                    .frame(width: cardWidth)
            }
        }
    }
}


/// Schlanker Player für Videos im Chat — Seitenverhältnis bleibt erhalten,
/// Rahmen liegt am Video an (gleiche Regel wie bei den Bildern).
private struct ChatVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .frame(maxHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .onAppear {
                let p = AVPlayer(url: url)
                p.isMuted = false
                player = p
                p.play()
            }
            .onDisappear { player?.pause() }
    }
}
