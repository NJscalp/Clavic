//
//  AgentView.swift
//  Clavic
//
//  Der In-App-Agent: ein Chat, dem man ein oder mehrere Fotos anhängt und in
//  natürlicher Sprache sagt, was man will — z. B. „analysier das erste Bild und
//  bau das Auto ins zweite ein". Der Agent (Claude, server-seitig) entscheidet:
//    • Text-Antwort  → Bild analysieren, Prompt schreiben, Ideen, Beratung
//    • Bild erzeugen → er schreibt einen fertigen GPT-Image-2-Prompt, und die
//      APP rendert das Bild über den bestehenden ImageEditAPI-Pfad (volle Bilder,
//      Credits werden erst bei Erfolg abgezogen).
//

import SwiftUI
import SwiftData
import PhotosUI
import Photos

struct AgentView: View {
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [AgentMessage] = []
    @State private var input: String = ""
    @State private var attachments: [Data] = []          // Fotos für den nächsten Zug
    @State private var lastResult: Data?                 // letztes erzeugtes Bild → impliziter Input für Folge-Edits
    @State private var lastImages: [Data] = []           // zuletzt angehängte Original-Fotos → für Options/Folge-Edits
    @State private var isWorking = false
    @State private var photoSelections: [PhotosPickerItem] = []
    @AppStorage("acceptedContentPolicy") private var acceptedContentPolicy = false
    @State private var showConsent = false
    @State private var pendingItems: [PhotosPickerItem] = []
    @State private var previewItem: ChatImagePreviewItem?
    @State private var animatedUserMsgs: Set<UUID> = []   // Pop-in + Larper-Reaktion nur einmal je Bild-Nachricht
    @State private var toast: String?
    @State private var showSubscriptionGate = false
    @FocusState private var inputFocused: Bool
    /// Kamera-Modus („Recreate“), derselbe wie im Chat-Tab.
    @State private var showPoseCamera = false

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { if inputFocused { inputFocused = false } })
                    .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Luftigere Züge (18 → 24), wie im Chat-Tab, und jeder Zug
                        // blendet weich ein statt hart zu erscheinen.
                        LazyVStack(spacing: 24) {
                            ForEach(messages) { msg in
                                messageRow(msg).id(msg.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 14)),
                                        removal: .opacity
                                    ))
                            }
                            Color.clear.frame(height: 6).id("bottom")
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        // Platz für den schwebenden „New chat"-Knopf oben rechts —
                        // sonst liegt er auf dem ersten, rechtsbündigen Foto.
                        .padding(.top, 46)
                        .padding(.bottom, 10)
                        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: messages.count)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .simultaneousGesture(TapGesture().onEnded { if inputFocused { inputFocused = false } })
                    .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
                    .overlay(alignment: .topTrailing) {
                        if !isWorking {
                            Button { startNewChat() } label: {
                                Label("New chat", systemImage: "square.and.pencil")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, Theme.screenPadding).padding(.top, 6)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
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
                pendingItems = items
                photoSelections = []
                showConsent = true
                return
            }
            Task { await loadAttachments(items) }
        }
        .alert("Before you upload", isPresented: $showConsent) {
            Button("I agree & continue") {
                acceptedContentPolicy = true
                let items = pendingItems
                pendingItems = []
                if !items.isEmpty { Task { await loadAttachments(items) } }
            }
            Button("View policy") {
                UIApplication.shared.open(LegalLinks.terms)
            }
            Button("Cancel", role: .cancel) { pendingItems = [] }
        } message: {
            Text("Only upload photos of yourself or people who have given you permission. Do not create sexual, hateful, deceptive or otherwise harmful content, or impersonate others. By continuing you confirm you have the rights to the photo and agree to our content policy.")
        }
        .overlay(alignment: .top) { if let toast { toastView(toast) } }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .fullScreenCover(item: $previewItem) { item in
            ChatImageFullscreenView(item: item) { data in saveImage(data) }
        }
        .sheet(isPresented: $showSubscriptionGate) { PaywallView() }
        .fullScreenCover(isPresented: $showPoseCamera) {
            PoseCameraView(
                onSend: { result in
                    showPoseCamera = false
                    // Beide Bilder als Anhang, der fertige Satz als Text — der
                    // Agent bekommt damit denselben Kontext wie der Chat.
                    // Reihenfolge WICHTIG: eigene Aufnahme zuerst, Vorlage
                    // danach (der Prompt spricht von IMAGE 1 / IMAGE 2).
                    attachments = [result.shot, result.reference]
                    input = result.instruction
                    Task { await send() }
                },
                onCancel: { showPoseCamera = false }
            )
        }
    }

    // MARK: - Leerer Zustand (animierte Pixel-Szene)

    // EIN Agent, der selbst entscheidet, was er aus dem Foto macht (LARP-Flex,
    // Fashion-Look oder Feed-Fix) — die Vorschläge decken bewusst alle drei
    // Richtungen ab, damit klar ist, wie breit er einsetzbar ist.
    private static let suggestions = [
        "Add a supercar to my garage — keep the garage & location the same",
        "Give me a look that actually fits this photo",
        "Make this insta-worthy — keep the same shot",
        "I have no idea — just tell me what to make of this",
    ]

    private var emptyState: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                WebsiteAgentScene(height: 270)
                    .padding(.top, 12)

                VStack(spacing: 5) {
                    Text("Trend Agent")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Drop a photo — I know what’s trending and I’ll build it with you in it.")
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    ForEach(Self.suggestions, id: \.self) { suggestionChip($0) }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 18)
        }
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            input = text
            inputFocused = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nachrichten

    @ViewBuilder
    private func messageRow(_ msg: AgentMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 8) {
                    if !msg.images.isEmpty {
                        SentImageBubble(
                            images: msg.images,
                            animate: !animatedUserMsgs.contains(msg.id),
                            onTap: { data in previewItem = ChatImagePreviewItem(imageData: data, beforeData: nil, caption: nil) },
                            onAnimated: { animatedUserMsgs.insert(msg.id) }
                        )
                    }
                    if let text = msg.text, !text.isEmpty {
                        // Wie im Chat-Tab: weiche graue Kapsel in Theme-Farben,
                        // nicht das gesättigte Blau.
                        Text(text)
                            .font(.system(size: 15.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        case .assistant:
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    if msg.isLoading {
                        if msg.isRendering {
                            // Bild wird gerendert → dieselbe Ladeanzeige wie im
                            // Chat-Tab: das Quellbild geblurred mit der Clavic-
                            // Animation darüber, sonst die Clavic-Ladekarte.
                            if let src = lastImages.first ?? lastResult,
                               let ui = UIImage(data: src) {
                                BlurLoadingCard(ui: ui)
                            } else {
                                ClavicLoadingCard(caption: msg.loadingNote ?? "Clavic is building your image")
                            }
                        } else if msg.isAnalyzing, let src = lastImages.first, let ui = UIImage(data: src) {
                            // Foto wird gelesen → Scan über genau dieses Foto.
                            AgentAnalyzingCard(image: ui, note: msg.loadingNote ?? "Reading your photo")
                        } else {
                            // Reine Text-Antwort → schlanke Denk-Zeile, keine Figur.
                            AgentThinkingRow(note: msg.loadingNote ?? loadingLabel(msg.text))
                        }
                    } else {
                        if let text = msg.text, !text.isEmpty {
                            Text(text)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                                .textSelection(.enabled)
                        }
                        if let result = msg.resultImage, let ui = UIImage(data: result) {
                            Button {
                                previewItem = ChatImagePreviewItem(imageData: result, beforeData: msg.beforeImage, caption: nil)
                            } label: {
                                Image(uiImage: ui).resizable().scaledToFit()
                                    .frame(maxWidth: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            HStack(spacing: 10) {
                                agentActionButton(icon: "square.and.arrow.down", text: "Save") { saveImage(result) }
                                agentActionButton(icon: "arrow.uturn.up", text: "Edit again") { useAsInput(result) }
                            }
                        }
                        if !msg.options.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(Array(msg.options.enumerated()), id: \.offset) { _, opt in
                                    PixelOptionButton(label: opt.label) { chooseOption(opt) }
                                }
                                // Schickt den Agenten zurück ans Foto: er liest es
                                // erneut und denkt sich KOMPLETT andere LARP-Wege aus
                                // (andere Autos, Uhren, Fits, Locations, Money-Props).
                                PixelOptionButton(label: "Analyze deeper — more ideas") { moreIdeas() }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                Spacer(minLength: 40)
            }
        }
    }

    /// On-brand Lade-Text: der generische „Thinking…"-Platzhalter wird ersetzt,
    /// echte Statustexte (z. B. „Creating your image…") bleiben stehen.
    private func loadingLabel(_ text: String?) -> String {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t != "Thinking…" else {
            return "Cooking up the flex…"
        }
        return t
    }

    private func agentActionButton(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(text).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.accent.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Eingabeleiste

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                // Angehängte Fotos GROSS über dem Textfeld — genau wie im
                // Chat-Tab: man sieht, woran man schreibt, bevor etwas im Chat
                // landet. Vorher waren es beschnittene 54-pt-Quadrate, in denen
                // ein Hochformat nicht zu erkennen war.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(attachments.enumerated()), id: \.offset) { idx, data in
                            if let ui = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    // Seitenverhältnis zuerst, dann NUR eine
                                    // Höhengrenze — sonst liegt der Rahmen nicht
                                    // am Bild an und es entstehen weiße Balken.
                                    Image(uiImage: ui)
                                        .resizable()
                                        .aspectRatio(ui.size.width / max(ui.size.height, 1), contentMode: .fit)
                                        .frame(maxHeight: 185)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(Theme.stroke, lineWidth: 1)
                                        )

                                    Button { attachments.remove(at: idx) } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 26, height: 26)
                                            .background(.black.opacity(0.55), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(7)
                                }
                            }
                        }
                    }
                }
            }

            // Gleiche Leiste wie im Chat-Tab: Textfeld oben, darunter die
            // Aktionszeile. Vorher stand hier eine eigene, einzeilige Variante
            // mit anderem Aussehen — zwei Chats in derselben App sollen sich
            // nicht unterschiedlich anfühlen.
            VStack(spacing: 10) {
                TextField("Tell me the flex…", text: $input, axis: .vertical)
                    .font(.system(size: 16.5, weight: .medium, design: .rounded))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    PhotosPicker(selection: $photoSelections, maxSelectionCount: 6, matching: .images) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    Button {
                        inputFocused = false
                        showPoseCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    Spacer(minLength: 0)

                    Button {
                        inputFocused = false
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .glassEffect(canSend ? .regular.tint(Theme.accent).interactive() : .regular, in: Circle())
                            .shadow(color: canSend ? Theme.accent.opacity(0.28) : .clear, radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .animation(.spring(duration: 0.25), value: canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var canSend: Bool {
        !isWorking && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    // MARK: - Foto laden

    private func loadAttachments(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Auf sinnvolle Kantenlänge bringen (spart Speicher; Rendern skaliert eh).
                if let ui = UIImage(data: data), let jpeg = ui.jpegForAPIUpload(maxDimension: 1280, quality: 0.85) {
                    loaded.append(jpeg)
                } else {
                    loaded.append(data)
                }
            }
        }
        await MainActor.run {
            attachments.append(contentsOf: loaded)
            if attachments.count > 6 { attachments = Array(attachments.suffix(6)) }
            photoSelections = []
        }
    }

    // MARK: - Senden

    /// `override`/`display`: für Options-Taps — voller Prompt geht an den Agent,
    /// aber in der Nutzer-Blase steht nur das kurze Label.
    private func send(override: String? = nil, display: String? = nil) async {
        let rawText = (override ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard override != nil ? !isWorking && !rawText.isEmpty : canSend else { return }

        if !rawText.isEmpty, let reason = ContentPolicy.rejectionReason(for: rawText) {
            flashToast(reason)
            return
        }

        // Options-Tap hängt keine neuen Fotos an (nutzt den bestehenden Kontext).
        let attached = override == nil ? attachments : []
        let bubbleText = display ?? (rawText.isEmpty ? nil : rawText)
        // Kontext für Agent + Edit: neue Anhänge > letztes Ergebnis (Folge-Edit)
        // > zuletzt angehängte Originale (z. B. Options-Tap nach reiner Analyse).
        let contextImages: [Data]
        if !attached.isEmpty { contextImages = attached }
        else if let r = lastResult { contextImages = [r] }
        else { contextImages = lastImages }
        if !attached.isEmpty { lastImages = attached }
        // Verlauf: nur echte Text-Turns, Fehlermeldungen raus (verwässern sonst den Kontext).
        let history: [AgentAPI.HistoryTurn] = messages.compactMap { m in
            guard let t = m.text, !t.isEmpty, !t.hasPrefix("Error:") else { return nil }
            return AgentAPI.HistoryTurn(role: m.role == .user ? "user" : "assistant", text: t)
        }

        let hasImageContext = !contextImages.isEmpty
        await MainActor.run {
            messages.append(AgentMessage(role: .user, text: bubbleText, images: attached))
            var loadingMsg = AgentMessage(role: .assistant, text: "Thinking…", isLoading: true)
            loadingMsg.isAnalyzing = hasImageContext   // Foto vorhanden → Lupen-Analyse-Animation
            messages.append(loadingMsg)
            input = ""
            attachments = []
            isWorking = true
            inputFocused = false
        }

        do {
            let reply = try await AgentAPI.chat(history: history, message: rawText, images: contextImages)

            // Text-Antwort einsetzen (ersetzt den „Thinking…"-Platzhalter). Bei einem
            // Bild-Auftrag bleibt die Blase im Lade-Zustand, bis das Bild fertig ist.
            await MainActor.run {
                if let last = messages.indices.last {
                    var m = AgentMessage(role: .assistant, text: reply.text, isLoading: reply.action != nil)
                    m.options = reply.action == nil ? reply.options : []
                    // Bei einem Bild-Auftrag Lupen-Ansicht halten, bis das Rendern startet.
                    m.isAnalyzing = (reply.action != nil) && hasImageContext
                    messages[last] = m
                }
            }

            if let action = reply.action {
                await runEdit(action: action, sourceImages: contextImages)
            } else {
                await MainActor.run { isWorking = false }
            }
        } catch {
            await MainActor.run {
                if let last = messages.indices.last {
                    messages[last] = AgentMessage(role: .assistant, text: "Error: \(error.localizedDescription)", isLoading: false)
                }
                isWorking = false
            }
        }
    }

    /// Führt den vom Agenten gewünschten Bild-Edit über GPT Image 2 aus.
    /// Agent-spezifische Credit-Kosten. Der Agent rendert über GPT Image 2 (teurer
    /// als Nano Banana im Chat) + Realism-QA + evtl. Re-Render — daher eigene
    /// Preise statt der geteilten `ChatQuality.credits`: low 1 · medium 2 · high 4.
    private func agentCredits(_ quality: ChatQuality) -> Int {
        switch quality {
        case .low: return 1
        case .medium: return 2
        case .high: return 4
        }
    }

    private func runEdit(action: AgentAPI.Action, sourceImages: [Data]) async {
        let quality = ChatQuality(rawValue: action.quality) ?? .medium
        let cost = agentCredits(quality)

        // Abo-/Credit-Gate wie im übrigen App-Fluss. Die (on-brand) Agent-Antwort
        // bleibt stehen — nur der Lade-Zustand endet und das passende Gate öffnet.
        guard store.canCreate else {
            await MainActor.run {
                if let last = messages.indices.last { messages[last].isLoading = false }
                isWorking = false
                showSubscriptionGate = true
            }
            return
        }
        guard store.canAfford(cost) else {
            await MainActor.run {
                if let last = messages.indices.last { messages[last].isLoading = false }
                isWorking = false
                flashToast("Not enough credits — top up to keep creating.")
            }
            return
        }

        // Ohne angehängtes Foto → neutrales Seed-Bild (Text-to-Image).
        let refs: [Data] = sourceImages.isEmpty ? [AiCharacter.seedImageData()] : sourceImages
        let beforeForCompare = sourceImages.first

        await MainActor.run {
            if let last = messages.indices.last {
                messages[last].isLoading = true
                messages[last].isRendering = true
                if (messages[last].text ?? "").isEmpty { messages[last].text = "Creating your image…" }
            }
        }

        let request = ImageEditRequest(
            prompt: action.prompt,
            referenceImages: refs,
            quality: quality.apiValue,
            aspectRatio: "auto",
            model: ImageEditAPI.chatModel
        )

        do {
            let taskID = try await ImageEditAPI.createTask(request)
            let result = try await pollTask(taskID)
            switch result {
            case .success(let imageData):
                // Realism-QA: Ergebnis prüfen und bei Bedarf EINMAL korrigiert neu
                // rendern (kostet den Nutzer keinen zweiten Credit).
                let finalData = await refineIfNeeded(imageData, action: action, refs: refs, sourceImages: sourceImages, quality: quality)
                await MainActor.run {
                    store.consume(cost)   // Credits ERST bei Erfolg — genau einmal.
                    if let last = messages.indices.last {
                        var m = messages[last]
                        m.isLoading = false
                        m.loadingNote = nil
                        m.resultImage = finalData
                        m.beforeImage = beforeForCompare
                        messages[last] = m
                    }
                    lastResult = finalData   // impliziter Input für den nächsten Folge-Edit
                    isWorking = false
                    persistToLibrary(finalData, prompt: action.prompt, cost: cost, quality: quality.apiValue)
                }
            case .failure(let reason):
                await MainActor.run {
                    if let last = messages.indices.last {
                        messages[last] = AgentMessage(role: .assistant, text: "Error: \(reason)", isLoading: false)
                    }
                    isWorking = false
                }
            }
        } catch {
            await MainActor.run {
                if let last = messages.indices.last {
                    messages[last] = AgentMessage(role: .assistant, text: "Error: \(error.localizedDescription)", isLoading: false)
                }
                isWorking = false
            }
        }
    }

    /// Realism-QA-Loop: benotet das Ergebnis; ist es nicht ok und liefert der
    /// QA-Agent einen Korrektur-Prompt, wird EINMAL neu gerendert. QA läuft nur
    /// bei echten Foto-Edits (Quellbilder vorhanden) und blockiert nie — bei
    /// Fehlern/OK bleibt das erste Ergebnis.
    private func refineIfNeeded(_ first: Data, action: AgentAPI.Action, refs: [Data], sourceImages: [Data], quality: ChatQuality) async -> Data {
        guard !sourceImages.isEmpty else { return first }

        await setLoadingNote("Checking realism…")
        guard let qa = try? await AgentAPI.qa(originals: sourceImages, result: first, prompt: action.prompt) else { return first }
        guard !qa.ok, let corrected = qa.correctedPrompt,
              !corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return first }

        await setLoadingNote("Making it more realistic…")
        let req = ImageEditRequest(
            prompt: corrected,
            referenceImages: refs,
            quality: quality.apiValue,
            aspectRatio: "auto",
            model: ImageEditAPI.chatModel
        )
        guard let taskID = try? await ImageEditAPI.createTask(req) else { return first }
        if case .success(let data2) = ((try? await pollTask(taskID)) ?? .failure("")) { return data2 }
        return first
    }

    private func setLoadingNote(_ note: String) async {
        await MainActor.run {
            if let last = messages.indices.last, messages[last].isLoading {
                messages[last].loadingNote = note
            }
        }
    }

    private enum PollResult { case success(Data); case failure(String) }

    private func pollTask(_ taskID: String) async throws -> PollResult {
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
                if consecutiveErrors >= 20 { return .failure("Lost connection — please check your internet and try again.") }
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

    // MARK: - Aktionen

    private func useAsInput(_ data: Data) {
        attachments = [data]
        inputFocused = true
        flashToast("Added as input for your next edit.")
    }

    /// „Analyze deeper": schickt den Agenten zurück ans Foto für eine ZWEITE,
    /// bewusst andere Ideen-Runde — statt Varianten derselben Richtung.
    private func moreIdeas() {
        guard !isWorking else { return }
        for i in messages.indices where !messages[i].options.isEmpty { messages[i].options = [] }
        Task {
            await send(
                override: "Analyze my photo again, deeper this time. Give me a completely different set of ideas than the ones you just offered, still grounded in what's actually in this photo — pull from other categories (other cars, watches, jewelry, outfits, locations, looks, grades, money props, or the lighting treatment) and use details in the photo you haven't used yet.",
                display: "Analyze deeper — more ideas"
            )
        }
    }

    /// Options-Tap: vollen Prompt senden, in der Blase nur das Label zeigen.
    private func chooseOption(_ opt: AgentAPI.Option) {
        guard !isWorking else { return }
        for i in messages.indices where !messages[i].options.isEmpty { messages[i].options = [] }
        Task { await send(override: opt.prompt, display: opt.label) }
    }

    private func startNewChat() {
        messages = []
        input = ""
        attachments = []
        lastResult = nil
        lastImages = []
    }

    private func persistToLibrary(_ data: Data, prompt: String, cost: Int, quality: String) {
        let ext = (data.starts(with: [0x89, 0x50, 0x4E, 0x47])) ? "png" : "jpg"
        let project = VideoProject(
            prompt: prompt,
            templateTitle: "Agent",
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

// MARK: - Gesendete Bilder (kompakt rechts, wie im Chat-Tab)

/// Zeigt die vom Nutzer angehängten Fotos als kleine Blase — gleiche Größe und
/// Rahmung wie im Chat-Tab (max. 190 pt hoch, Rahmen liegt am Bild an). Die
/// Lupen-Figur, die vorher über die Bildkante lugte, ist entfernt: die Analyse
/// wird jetzt von `AgentAnalyzingCard` erzählt, direkt am Foto.
private struct SentImageBubble: View {
    let images: [Data]
    var animate: Bool
    var onTap: (Data) -> Void
    var onAnimated: () -> Void

    @State private var appeared = false

    var body: some View {
        content
            .scaleEffect(appeared ? 1 : 0.9, anchor: .bottomTrailing)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                guard animate else { appeared = true; return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { appeared = true }
                onAnimated()
            }
    }

    @ViewBuilder private var content: some View {
        if images.count == 1, let ui = UIImage(data: images[0]) {
            Button { onTap(images[0]) } label: {
                Image(uiImage: ui).resizable().scaledToFit()
                    // Seitenverhältnis zuerst, dann nur eine Höhengrenze — sonst
                    // wird der Rahmen breiter als das Bild.
                    .aspectRatio(ui.size.width / max(ui.size.height, 1), contentMode: .fit)
                    .frame(maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 112), spacing: 8)], spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                    if let ui = UIImage(data: data) {
                        Button { onTap(data) } label: {
                            Image(uiImage: ui).resizable().scaledToFill()
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 236)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
    }
}

// MARK: - Options-Button (2D-Pixel-Stil)

/// Retro/Pixel-Button für die Edit-Richtungen nach der Analyse: dunkler Chip mit
/// hartem Pixel-Schatten, Gold-Rand, Mono-Font und einem Pixel-Diamant.
private struct PixelOptionButton: View {
    let label: String
    var action: () -> Void
    private let gold = Color(red: 0.91, green: 0.77, blue: 0.33)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PixelDiamondMini().frame(width: 15, height: 15)
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(gold)
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.9)).offset(x: 3, y: 3)   // harter Pixel-Schatten
                    RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.11, green: 0.11, blue: 0.14))
                    RoundedRectangle(cornerRadius: 8).strokeBorder(gold.opacity(0.7), lineWidth: 2)
                }
            )
            .padding(.trailing, 3).padding(.bottom, 3)   // Platz für den Schatten
        }
        .buttonStyle(.plain)
    }
}

/// Kleiner animationsfreier Pixel-Diamant (5×5) — passend zum LARP-Pixel-Stil.
private struct PixelDiamondMini: View {
    private let mask = ["..X..", ".XXX.", "XXXXX", ".XXX.", "..X.."]
    var body: some View {
        Canvas { ctx, size in
            let cell = size.width / 5
            let cyan = Color(red: 0.75, green: 0.93, blue: 1.0)
            for (y, row) in mask.enumerated() {
                for (x, ch) in row.enumerated() where ch == "X" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)),
                             with: .color((y == 2 || x == 2) ? .white : cyan))
                }
            }
        }
    }
}

// MARK: - Modell

struct AgentMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String?
    var images: [Data] = []        // vom Nutzer angehängte Fotos (bei .user)
    var isLoading: Bool = false
    var isAnalyzing: Bool = false  // Foto wird analysiert → Lupen-Loader
    var isRendering: Bool = false  // Bild wird generiert → Money-Rain-Loader statt Denk-Animation
    var loadingNote: String? = nil // Zwischenstatus beim Laden (z. B. „Checking realism…")
    var resultImage: Data? = nil   // vom Agenten erzeugtes Bild (bei .assistant)
    var beforeImage: Data? = nil   // Quellbild für Vorher/Nachher im Vollbild
    var options: [AgentAPI.Option] = []   // antippbare Edit-Richtungen nach der Analyse

    enum Role { case user, assistant }
}
