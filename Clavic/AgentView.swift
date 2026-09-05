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
import QuartzCore
import SwiftData
import PhotosUI
import Photos

struct AgentView: View {
    /// Erst wenn das Start-Overlay weg ist, darf der Wurf laufen.
    var introFinished: Bool = true

    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [AgentMessage] = []
    @State private var input: String = ""
    @State private var attachments: [Data] = []          // Fotos für den nächsten Zug
    @State private var lastResult: Data?                 // letztes erzeugtes Bild → impliziter Input für Folge-Edits
    @State private var lastImages: [Data] = []           // zuletzt angehängte Original-Fotos → für Options/Folge-Edits
    @State private var isWorking = false
    /// Was auf dem Foto angestrichen wurde. Füttert die Schnellaufträge der
    /// Regie-Leiste — sie soll über DIESES Bild reden, nicht über Fotos.
    @State private var readMarks: [ReadMark] = []
    /// Die Bildlesung des aktuellen Fotos, aufgehoben aus dem letzten Zug.
    ///
    /// Sie kam schon immer mit der Antwort zurück und wurde weggeworfen. Wer
    /// sie behält, kann weitere Fragen zu DEMSELBEN Foto stellen, ohne es noch
    /// einmal analysieren zu lassen — die Trend-Auswahl tut genau das.
    @State private var photoReading: DirectorAPI.Reading?
    /// Was der Server gerade als Trend führt. Kommt aus `templates.json` und
    /// braucht kein App-Update: neuer Trend samt Bild hochgeladen, sofort im
    /// Streifen. Genau dafür wurde der eingebaute Katalog hier entfernt.
    /// OPTIONAL, nicht zwingend: `@Environment` mit einem nicht-optionalen
    /// `@Observable` stuerzt beim Zugriff ab, wenn niemand ihn eingehaengt
    /// hat — etwa in einer Vorschau oder einem Test. Der Streifen faellt dann
    /// auf die Vorschlaege des Directors zurueck, statt die App mitzureissen.
    @Environment(TemplateStore.self) private var templateStore: TemplateStore?
    @State private var photoSelections: [PhotosPickerItem] = []
    @AppStorage("acceptedContentPolicy") private var acceptedContentPolicy = false
    @State private var showConsent = false
    @State private var pendingItems: [PhotosPickerItem] = []
    @State private var previewItem: ChatImagePreviewItem?
    @State private var animatedUserMsgs: Set<UUID> = []   // Pop-in + Larper-Reaktion nur einmal je Bild-Nachricht
    @State private var showingOriginalResults: Set<UUID> = []
    @State private var toast: String?
    @State private var showSubscriptionGate = false
    @FocusState private var inputFocused: Bool
    /// Kamera-Modus („Recreate“), derselbe wie im Chat-Tab.
    @State private var showPoseCamera = false

    // MARK: - Maskottchen-Bühne
    /// Was die Figur oben gerade tut. Sie beginnt mit dem Standbild und wirft,
    /// sobald das Intro weg ist — wer die App öffnet, soll die Animation sehen.
    /// Danach fällt sie wieder auf `.idle`: das Standbild ist derselbe Frame,
    /// mit dem das Video endet, deshalb entsteht dabei kein sichtbarer Schnitt.
    @State private var mascotAct: MascotAct = .idle
    /// Der Begrüßungswurf läuft einmal pro Start, nicht bei jedem Tab-Wechsel.
    @State private var didPlayWelcomeThrow = false
    /// Zählt jeden angeforderten Wurf. Ein Zähler, kein Schalter: geworfen wird
    /// zur Begrüßung UND bei jedem neuen Vorschlagssatz.
    @State private var throwToken = 0
    /// false, solange die geworfenen Karten noch im Video unterwegs sind.
    /// Wird bei 2,95 s des Wurfs auf true gesetzt (siehe `MascotStage`).
    /// Startet auf false: unter der Figur soll erst NICHTS liegen, die Karten
    /// kommen im Moment des Wurfs herein.
    @State private var optionsRevealed = false
    /// Die Eingabezeile ist normalerweise NICHT da.
    ///
    /// Sie ist das Element, das eine Seite nach Chat aussehen lässt, und sie
    /// deckt die Auswahl zu. Sie erscheint nur, wenn jemand ausdrücklich etwas
    /// Eigenes sagen will — über „Something else? Just say it." — und
    /// verschwindet nach dem Absenden wieder.
    @State private var showComposer = false

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                // KEINE Eingabezeile im Auftakt. Vor der Analyse hat niemand
                // etwas zu tippen — der Director hat das Foto ja noch nicht
                // gesehen. Und die Eingabezeile ist genau das Element, das
                // eine Seite nach Chat aussehen lässt. Sie kommt mit der
                // ersten Antwort.
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            } else {
                conversation
            }
        }
        .background {
            // Die Werkstatt um die Figur herum. Vorher stand sie oben allein
            // und darunter lag der halbe Bildschirm leeres Cremeweiss — beim
            // Lesen wie nach dem Ergebnis. Die Requisiten liegen nur an den
            // Raendern und wachsen von aussen herein, damit nie etwas hinter
            // Foto oder Text liegt.
            ZStack {
                Theme.background
                // Im Auftakt zurueckhaltender: dort traegt schon das Blattwerk
                // der Figur, und `DirectorStart` fuellt die Mitte.
                DirectorScenery(busy: isWorking,
                                opacity: messages.isEmpty ? 0.7 : 1)
            }
            .ignoresSafeArea()
        }
        // Der Arbeitszustand spiegelt sich in der Bühne — aber nur, wenn nicht
        // gerade der Wurf läuft; der darf nicht unterbrochen werden.
        .task {
            // NICHT einfach in `onAppear` werfen. `onAppear` läuft, bevor der
            // erste Frame auf dem Schirm ist — beim Kaltstart liegt davor noch
            // der Startbildschirm, und der ganze Wurf lief unsichtbar dahinter
            // ab: sichtbar wurde die App erst, als die Karten längst lagen.
            //
            // Deshalb erst einen tatsächlich fertig gezeichneten Frame abwarten.
            // Der Abschlussblock einer CATransaction feuert genau dann.
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                CATransaction.begin()
                CATransaction.setCompletionBlock { c.resume() }
                CATransaction.commit()
            }
            startWelcomeThrowIfNeeded()
        }
        .onChange(of: introFinished) { _, done in
            guard done else { return }
            startWelcomeThrowIfNeeded()
        }
        // `initial: true` ist wichtig: ohne das wird der Zustand NUR bei einem
        // Wechsel gesetzt. Erscheint die Ansicht, waehrend schon gearbeitet
        // wird — wiederhergestellte Sitzung, Tab-Rueckkehr, UI-Review-Hook —
        // bleibt die Figur sonst im Leerlauf stehen, obwohl unten „Reading
        // your photo…" steht.
        .onChange(of: isWorking, initial: true) { _, working in
            guard mascotAct != .throwing else { return }
            mascotAct = working ? .working : .idle
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
        #if DEBUG
        .onAppear {
            let environment = ProcessInfo.processInfo.environment
            // Nur zum Prüfen der Karte im Simulator: legt ein Foto ein, ohne
            // dass jemand die Fotoauswahl bedienen muss.
            if let name = environment["UITEST_DIRECTOR_PHOTO"],
               messages.isEmpty, attachments.isEmpty,
               let ui = UIImage(named: name),
               let data = ui.jpegData(compressionQuality: 0.9) {
                attachments = [data]
            }

            if environment["UITEST_DIRECTOR_LOOKS"] != nil,
               messages.isEmpty,
               let source = UIImage(named: "preview_look_vintage_beach")?.jpegData(compressionQuality: 0.9) {
                lastImages = [source]
                var result = AgentMessage(
                    role: .assistant,
                    text: "Flat ceiling light and a cool cast — here's what I'd do."
                )
                func option(_ style: DigiCamStyles.Style, _ mode: DirectorAPI.Mode) -> DirectorAPI.Option {
                    DirectorAPI.Option(
                        id: style.id, label: style.title, caption: style.subtitle,
                        mode: mode, prompt: style.prompt, preview: style.previewAfter
                    )
                }
                // Zwei Picks, dazu ein paar Trends — wie im echten Zug.
                result.picks = Array(DigiCamStyles.all.prefix(2)).map { option($0, .grade) }
                result.trends = Array(DigiCamStyles.all.dropFirst(2).prefix(3)).map { option($0, .grade) }
                messages = [result]
                revealPicksAnyway()
            } else if environment["UITEST_DIRECTOR_RESULT"] != nil,
               messages.isEmpty,
               let vorher = UIImage(named: "director_real_party")?.jpegData(compressionQuality: 0.9),
               let nachher = UIImage(named: "preview_look_vintage_beach")?.jpegData(compressionQuality: 0.9) {
                // Der fertige Director's Cut, ohne einen Zug zu bezahlen.
                lastImages = [vorher]
                var result = AgentMessage(role: .assistant, text: "Here's what I'd do.")
                result.beforeImage = vorher
                result.resultImage = nachher
                messages = [result]
                revealPicksAnyway()
            } else if environment["UITEST_DIRECTOR_ONE"] != nil,
               messages.isEmpty,
               let source = UIImage(named: "preview_look_vintage_beach")?.jpegData(compressionQuality: 0.9) {
                // EIN Vorschlag: der Fall, in dem der Director sich festlegt.
                lastImages = [source]
                var result = AgentMessage(
                    role: .assistant,
                    text: "Flat ceiling light — this one needs flash."
                )
                let style = DigiCamStyles.all[5]
                result.picks = [DirectorAPI.Option(
                    id: style.id, label: style.title, caption: style.subtitle,
                    mode: .grade, prompt: style.prompt, preview: style.previewAfter
                )]
                result.lead = style.id
                messages = [result]
                revealPicksAnyway()
            } else if environment["UITEST_DIRECTOR_ANALYZING"] != nil,
               messages.isEmpty,
               let first = UIImage(named: "director_real_party")?.jpegData(compressionQuality: 0.9),
               let second = UIImage(named: "director_real_beach")?.jpegData(compressionQuality: 0.9) {
                lastImages = [first, second]
                messages = [AgentMessage(
                    role: .assistant,
                    text: "Reading your photo…",
                    isLoading: true,
                    isAnalyzing: true
                )]
                // `isWorking` ist ein EIGENER Zustand, nicht aus `messages`
                // abgeleitet. Ohne diese Zeile stellte der Hook das Lesen nur
                // halb her: die Karte lud, die Figur blieb im Leerlauf — und
                // der Pruef-Loop war im UI-Review nie zu sehen, obwohl er
                // richtig verdrahtet war.
                isWorking = true
            }
        }
        #endif
    }

    /// Die Figur ist ein Element im Fluss, keine feste Ebene — sie scrollt
    /// einfach weg. Im Leerzustand darf sie groß sein, im Verlauf reicht
    /// weniger, weil sie ohnehin nach dem ersten Wischen oben raus ist.
    /// 172 im Leerzustand: darunter müssen vier Polaroids samt Beschriftung
    /// Platz haben, ohne hinter der Eingabeleiste zu verschwinden.
    private var mascotHeight: CGFloat { messages.isEmpty ? 158 : 124 }

    /// Ein Aufruf für beide Scroll-Inhalte, damit sie nicht auseinanderlaufen.
    /// Einmal pro App-Start, und nur im Leerzustand — mitten in einem Verlauf
    /// wäre ein Begrüßungswurf sinnlos.
    private func startWelcomeThrowIfNeeded() {
        guard !didPlayWelcomeThrow, messages.isEmpty, !isWorking else { return }
        didPlayWelcomeThrow = true
        // Karten sicher verstecken, BEVOR geworfen wird — sonst liegen sie da,
        // während die Figur noch ausholt.
        optionsRevealed = false
        mascotAct = .throwing
        throwToken += 1
    }

    /// `height` nur setzen, wo die Figur NEBEN etwas steht — im Ergebnis
    /// steht sie klein rechts vom Foto statt breit darueber.
    private func mascotBlock(height: CGFloat? = nil,
                            idleLoopURL: URL? = nil) -> some View {
        MascotStage(
            act: mascotAct,
            throwToken: throwToken,
            expectsThrow: !didPlayWelcomeThrow && messages.isEmpty,
            height: height ?? mascotHeight,
            idleLoopURL: idleLoopURL,
            isActive: true,
            showsHabitat: messages.isEmpty,
            // In der Werkbank erzählt die Zeile darunter den Stand — die
            // Sprechblase wäre dieselbe Aussage ein zweites Mal.
            showsActivityPill: messages.isEmpty,
            onHandoff: {
                // Die Video-Karten sind an der Unterkante — jetzt kommen die
                // echten hinterher, damit kein toter Takt entsteht.
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    optionsRevealed = true
                }
            },
            onThrowFinished: { mascotAct = isWorking ? .working : .idle }
        )
    }

    /// Serververlagen als antippbare Richtungen.
    ///
    /// Nur Bild-Trends mit Vorschau und Rezept: ein Video-Trend gehört nicht
    /// in einen Streifen, der verspricht, DIESES Foto zu verändern, und eine
    /// Kachel ohne Bild kann man sich nicht vorstellen.
    private var serverTrends: [DirectorAPI.Option] {
        (templateStore?.templates ?? [])
            .filter { $0.isImageEdit && !$0.prompt.isEmpty && !$0.isHiddenFromDiscover }
            .compactMap { template in
                let vorschau = template.previewRemoteURL ?? template.preview
                guard !vorschau.isEmpty else { return nil }
                return DirectorAPI.Option(
                    id: template.hashtag.isEmpty ? template.title : template.hashtag,
                    label: template.title,
                    caption: template.subtitle,
                    mode: .grade,
                    prompt: template.fixedEditPrompt ?? template.prompt,
                    preview: vorschau
                )
            }
    }

    /// Der letzte Stand des Directors — das ist alles, was gezeigt wird.
    private var letzter: AgentMessage? {
        messages.last(where: { $0.role == .assistant })
    }

    /// KEIN Gesprächsverlauf mehr.
    ///
    /// Hier stand ein Chat: Nachrichtenblasen, „Thinking…", ein Scrollback aus
    /// vorherigen Zügen. Ein Creative Director schickt aber keine Nachrichten —
    /// er sieht sich das Bild an und legt etwas hin. Gezeigt wird deshalb immer
    /// nur der aktuelle Stand, in immer demselben Aufbau.
    ///
    /// Die Züge bleiben in `messages` erhalten; sie sind der Kontext für den
    /// Director. Nur DARGESTELLT wird der Verlauf nicht mehr.
    private var conversation: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                DirectorWorkspace(
                    mascot: { slot in
                        switch slot {
                        case .unterDerKarte:
                            mascotBlock().padding(.horizontal, -Theme.screenPadding)
                        case .nebenDemFoto:
                            // Klein und ohne den negativen Rand: hier steht sie
                            // IM Textspiegel neben dem Bild, nicht über die
                            // ganze Breite.
                            // Eigener Ruhe-Satz: hier zeigt, betrachtet und
                            // billigt sie den Abzug — statt dasselbe zu tun
                            // wie im Leerlauf auf dem Startbildschirm.
                            mascotBlock(height: 132, idleLoopURL: MascotStage.readLoopURL)
                                .frame(width: 132)
                        }
                    },
                    photo: letzter?.resultImage ?? lastImages.first,
                    before: letzter?.resultImage != nil ? lastImages.first : nil,
                    isWorking: letzter?.isLoading ?? false,
                    note: letzter?.loadingNote,
                    verdict: letzter?.text,
                    picks: letzter?.picks ?? [],
                    lead: letzter?.lead,
                    trends: letzter?.trends ?? [],
                    serverTrends: serverTrends,
                    composerOpen: showComposer,
                    reading: photoReading,
                    landed: optionsRevealed,
                    throwToken: throwToken,
                    onPick: { chooseOption($0) },
                    onOwnIdea: {
                        // Erst die Leiste einsetzen, DANN den Fokus. Beides im
                        // selben Zug laesst die Tastatur gegen die einlaufende
                        // Leiste anlaufen — sichtbar als Ruckler. Ein Zug der
                        // Laufschleife dazwischen reicht.
                        withAnimation(Self.composerMotion) { showComposer = true }
                        Task { @MainActor in inputFocused = true }
                    },
                    onCompare: {},
                    onKeep: {
                        if let daten = letzter?.resultImage { saveImage(daten) }
                    },
                    onTryAnother: {
                        // ZURUECK ZU DEN RICHTUNGEN, nicht zurueck auf null.
                        // Das Foto und die Lesung bleiben — nur das Ergebnis
                        // wird beiseitegelegt. Ein neuer Zug wuerde den Nutzer
                        // sein Bild noch einmal aussuchen lassen.
                        guard let letzter,
                              let index = messages.lastIndex(where: { $0.id == letzter.id })
                        else { return }
                        withAnimation(.smooth(duration: 0.3)) {
                            messages[index].resultImage = nil
                            messages[index].beforeImage = nil
                        }
                    },
                    onMarks: { readMarks = $0 }
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 6)
            // Ohne Eingabezeile braucht es nur Luft über der Tableiste.
            .padding(.bottom, showComposer ? 230 : 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded { if inputFocused { inputFocused = false } })
        .overlay(alignment: .bottom) {
            if showComposer { inputBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(Self.composerMotion, value: showComposer)
        .overlay(alignment: .topTrailing) {
            if !isWorking {
                Button { startNewChat() } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, Theme.screenPadding).padding(.top, 6)
            }
        }
    }

    // MARK: - Photo Director start

    // Offene Einstiege statt starrer Templates: jedes Beispiel kann verwendet,
    // gemischt oder komplett ignoriert werden. Die freie Eingabe bleibt direkt
    // darunter immer erreichbar.
    private static let suggestions = [
        "Keep everything — just make the light feel better",
        "Show me a few directions without changing who I am",
        "Give it a real G7X direct-flash look",
        "I have my own idea…",
    ]

    private var emptyState: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - (Theme.screenPadding * 2))

            ScrollView(showsIndicators: false) {
                // Mittig statt oben angeschlagen: mit drei flachen Karten
                // bliebe sonst unten eine große leere Fläche stehen.
                VStack(alignment: .leading, spacing: 16) {
                    Spacer(minLength: 0)
                // Erstes Element IM Scroll-Inhalt: beim Wischen geht die Figur
                // mit dem Hintergrund nach oben weg, der Rest rückt nach.
                // Über den Seitenrand hinaus, damit das Blattwerk vom
                // Bildrand hereinwächst und nicht im Textspiegel klebt.
                mascotBlock()
                    .padding(.horizontal, -Theme.screenPadding)

                // Kein Wurf mehr im Auftakt: geworfen wird, was ein Bild
                // trägt. Hier gibt es noch keins.
                DirectorStart(
                    photo: attachments.first,
                    photoSelections: $photoSelections,
                    onCamera: { showPoseCamera = true },
                    onSend: { Task { await send() } },
                    onClear: { attachments = [] }
                )

                    Spacer(minLength: 0)
                }
                .frame(width: contentWidth, alignment: .leading)
                .frame(minHeight: geometry.size.height - 200)
                .padding(.horizontal, Theme.screenPadding)
                // The floating composer overlays the scroll view; reserve enough
                // scrollable space so the final suggestion never hides beneath it.
                .padding(.bottom, 158)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(width: geometry.size.width)
            .clipped()
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

    private func directorReferenceTile(_ image: String, _ title: String, _ subtitle: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(image)
                .resizable()
                .scaledToFill()
                .frame(width: 150, height: 205)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(11)
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 28, height: 28)
                .background(.white, in: Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(9)
        }
        .frame(width: 150, height: 205)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                        } else if msg.isAnalyzing {
                            let analysisImages = lastImages.compactMap { UIImage(data: $0) }
                            if !analysisImages.isEmpty {
                                AgentAnalyzingCard(images: analysisImages, note: msg.loadingNote ?? "Reading your photo")
                            } else {
                                AgentThinkingRow(note: msg.loadingNote ?? "Reading your photo")
                            }
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
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFit()
                                    .opacity(showingOriginalResults.contains(msg.id) ? 0 : 1)

                                if let beforeData = msg.beforeImage,
                                   let before = UIImage(data: beforeData) {
                                    Image(uiImage: before)
                                        .resizable()
                                        .scaledToFit()
                                        .opacity(showingOriginalResults.contains(msg.id) ? 1 : 0)

                                    Text(showingOriginalResults.contains(msg.id) ? "ORIGINAL" : "RESULT")
                                        .font(.system(size: 10, weight: .black, design: .rounded))
                                        .tracking(0.6)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(.black.opacity(0.48), in: Capsule())
                                        .padding(12)
                                        .contentTransition(.opacity)
                                }
                            }
                            .frame(maxWidth: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard msg.beforeImage != nil else {
                                    previewItem = ChatImagePreviewItem(imageData: result, beforeData: nil, caption: nil)
                                    return
                                }
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    if showingOriginalResults.contains(msg.id) {
                                        showingOriginalResults.remove(msg.id)
                                    } else {
                                        showingOriginalResults.insert(msg.id)
                                    }
                                }
                            }

                            if msg.beforeImage != nil {
                                Label(
                                    showingOriginalResults.contains(msg.id) ? "Original · tap for result" : "Result · tap for original",
                                    systemImage: "hand.tap"
                                )
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                                .contentTransition(.opacity)
                            }
                            HStack(spacing: 10) {
                                agentActionButton(icon: "square.and.arrow.down", text: "Save") { saveImage(result) }
                                agentActionButton(icon: "arrow.uturn.up", text: "Edit again") { useAsInput(result) }
                            }
                        }
                        directionsBlock(msg)
                    }
                }
                Spacer(minLength: msg.picks.isEmpty ? 40 : 0)
            }
        }
    }

    /// On-brand Lade-Text: der generische „Thinking…"-Platzhalter wird ersetzt,
    /// echte Statustexte (z. B. „Creating your image…") bleiben stehen.
    private func loadingLabel(_ text: String?) -> String {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t != "Thinking…" else {
            return "Reading your photo…"
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

    /// Was der Director vorschlägt. Ausgelagert, weil der Swift-Typprüfer bei
    /// diesem Ausdruck im Nachrichtenkörper aufgab („unable to type-check this
    /// expression in reasonable time") — verschachtelte Views summieren sich.
    @ViewBuilder
    private func directionsBlock(_ msg: AgentMessage) -> some View {
        if !msg.picks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.accent)
                    Text("MY TWO BEST IDEAS")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text("Same face, always")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.surfaceHigh, in: Capsule())
                }

                DirectorPicks(
                    picks: msg.picks,
                    trends: msg.trends,
                    landed: optionsRevealed,
                    throwToken: throwToken,
                    sourcePhoto: lastImages.first,
                    onPick: { chooseOption($0) },
                    onOwnIdea: { input = ""; inputFocused = true }
                )
            }
            .padding(.top, 2)
        }
    }

    /// SICHERHEITSNETZ: zeigt die Vorschläge auch dann, wenn der Wurf sie
    /// nicht freigibt.
    ///
    /// Die Karten hängen an `optionsRevealed`, und das setzt normalerweise die
    /// Übergabe bei 2,95 s des Wurfvideos. Bleibt sie aus — fehlender Clip,
    /// abgebrochene Animation, ein Zustand den wir noch nicht kennen —, stünde
    /// die Überschrift „meine zwei besten Ideen" über einer leeren Fläche, und
    /// der Nutzer käme nicht weiter. Im Simulator genau so gesehen.
    ///
    /// Nach 4 Sekunden ist der Wurf in jedem Fall vorbei. Was dann noch
    /// verborgen ist, war es nicht mit Absicht.
    private func revealPicksAnyway() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                guard !optionsRevealed,
                      messages.contains(where: { !$0.picks.isEmpty })
                else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                    optionsRevealed = true
                }
            }
        }
    }

    // MARK: - Eingabeleiste

    /// Dieselbe Leiste wie im Chat-Tab — nur ohne das, was hier nichts zu
    /// suchen hat.
    ///
    /// Sie war vorher ein Eigenbau mit deckendem Tablett und einer Kopfzeile.
    /// Zwei Chats in derselben App sollen sich nicht unterschiedlich anfuehlen:
    /// gleiches Glas, gleiche Ecke (26), gleiche Kurve (`composerMotion`,
    /// `.smooth(0,3)`), gleiche Abstaende, Textfeld bis acht Zeilen.
    ///
    /// WAS FEHLT UND WARUM: kein Plus, keine Kamera, keine Bild/Video-Wahl.
    /// Der Director hat EIN Foto gelesen und angestrichen; alles hier gehoert
    /// zu diesem Foto. Ein Anhang-Knopf waere die Einladung, genau das zu
    /// verlassen — dann waere es wieder der Chat.
    ///
    /// Dafuer stehen ueber dem Feld die Anmerkungen vom Bild als fertige
    /// Auftraege — an derselben Stelle, an der im Chat die Einstellungs-Chips
    /// auftauchen, und nach derselben Regel: erst wenn getippt wird.
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if inputFocused && !schnellauftraege.isEmpty { schnellzeile }

            VStack(spacing: 10) {
                TextField("Tell him what to change…", text: $input, axis: .vertical)
                    .font(.system(size: 16.5, weight: .medium, design: .rounded))
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        inputFocused = false
                        if canSend { Task { await send() } }
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Ohne eigene Kurve springt die Leiste bei jedem Umbruch
                    // hart um. Ausloeser ist der Text, nicht der Fokus.
                    .animation(Self.composerMotion, value: input)

                HStack(spacing: 8) {
                    Button {
                        inputFocused = false
                        withAnimation(Self.composerMotion) { showComposer = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

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
                    .disabled(!canSend)
                    .animation(.spring(duration: 0.25), value: canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
            // Glas ist optisch geschlossen, hat aber durchsichtige Luecken —
            // ohne eigene Trefferflaeche faellt der Tipp durch auf eine Karte.
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, inputFocused ? 2 : 82)
        .animation(Self.composerMotion, value: inputFocused)
        .contentShape(Rectangle())
        .zIndex(100)
    }

    /// Genau die Kurve des Chat-Composers.
    private static let composerMotion: Animation = .smooth(duration: 0.3)

    /// Die Anmerkungen vom Foto als fertige Auftraege, dazu ein allgemeiner.
    ///
    /// Sie schreiben nur ins Feld, sie senden nicht. Jeder Zug kostet Credits —
    /// ein Tipp, der sofort rendert, waere eine Falle.
    private var schnellauftraege: [String] {
        var alle = readMarks.map(\.request)
        if alle.count < 3 { alle.append("Make it feel like a real camera shot") }
        return Array(alle.prefix(3))
    }

    private var schnellzeile: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(schnellauftraege, id: \.self) { auftrag in
                    Button {
                        input = auftrag
                    } label: {
                        Text(auftrag)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -Theme.screenPadding)
        .padding(.leading, Theme.screenPadding)
        .transition(.opacity.combined(with: .offset(y: 8)))
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
            // Ein neues Foto macht die alte Lesung ungueltig.
            if !loaded.isEmpty { photoReading = nil }
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
        // Ein Zug nur mit Foto heißt „schau dir das an“. Was daraus folgt,
        // entscheidet der Director — nicht die App.
        //
        // Hier stand früher ein erzwungener Prompt, der GENAU DREI Looks aus
        // einer festen Sieben-Namen-Liste verlangte und jede Retusche, jeden
        // Orts-, Posen- und Kleidungswechsel ausdrücklich verbot. Damit war
        // das Modell auf einen Bruchteil dessen festgenagelt, was es kann, und
        // sein Urteil wurde anschließend ohnehin überschrieben.
        let requestText = rawText
        // Kontext für Agent + Edit: neue Anhänge > letztes Ergebnis (Folge-Edit)
        // > zuletzt angehängte Originale (z. B. Options-Tap nach reiner Analyse).
        let contextImages: [Data]
        if !attached.isEmpty { contextImages = attached }
        else if let r = lastResult { contextImages = [r] }
        else { contextImages = lastImages }
        if !attached.isEmpty { lastImages = attached }
        // Verlauf: nur echte Text-Turns, Fehlermeldungen raus (verwässern sonst den Kontext).
        let history: [DirectorAPI.HistoryTurn] = messages.compactMap { m in
            guard let t = m.text, !t.isEmpty, !t.hasPrefix("Error:") else { return nil }
            return DirectorAPI.HistoryTurn(role: m.role == .user ? "user" : "assistant", text: t)
        }

        let hasImageContext = !contextImages.isEmpty
        await MainActor.run {
            messages.append(AgentMessage(role: .user, text: bubbleText, images: attached))
            var loadingMsg = AgentMessage(role: .assistant, text: "Thinking…", isLoading: true)
            loadingMsg.isAnalyzing = hasImageContext   // Foto vorhanden → Lupen-Analyse-Animation
            messages.append(loadingMsg)
            input = ""
            attachments = []
            showComposer = false
            isWorking = true
            inputFocused = false
        }

        do {
            let reply = try await DirectorAPI.chat(
                history: history,
                message: requestText,
                images: contextImages
                // Keine Lesung von hier: analysiert wird erst beim Absenden,
                // und zwar serverseitig in einem Zug. Wer ein Foto anhängt und
                // es wieder wegnimmt, zahlt nichts.
            )

            // Text-Antwort einsetzen (ersetzt den „Thinking…"-Platzhalter). Bei einem
            // Bild-Auftrag bleibt die Blase im Lade-Zustand, bis das Bild fertig ist.
            await MainActor.run {
                if let last = messages.indices.last {
                    var m = AgentMessage(
                        role: .assistant,
                        text: reply.message,
                        isLoading: reply.action != nil
                    )
                    // Was der Director vorschlägt, wird gezeigt — unverändert.
                    if reply.action == nil {
                        m.picks = reply.picks
                        m.lead = reply.lead
                        m.trends = reply.trends
                    }
                    // Bei einem Bild-Auftrag Lupen-Ansicht halten, bis das Rendern startet.
                    // Die Lesung aufheben, solange dasselbe Foto im Spiel ist.
                    if let gelesen = reply.reading { photoReading = gelesen }
                    m.isAnalyzing = (reply.action != nil) && hasImageContext
                    messages[last] = m

                    // Vorschläge sind da → das Chamäleon wirft sie herunter.
                    // Die Karten bleiben verborgen, bis der Wurf bei 3,50 s
                    // die Übergabe meldet.
                    if !m.picks.isEmpty {
                        revealPicksAnyway()
                        optionsRevealed = false
                        mascotAct = .throwing
                        throwToken += 1
                    }
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

    /// Default contract for Photo Director edits. Generative edit models tend to
    /// "improve" unrequested areas unless the invariants are repeated directly
    /// in the final render prompt. Explicit user changes still win; everything
    /// else is immutable.
    private func compositionLockedPrompt(_ requestedEdit: String) -> String {
        """
        EDIT CONTRACT — NON-NEGOTIABLE:
        Use the first reference as the exact base image. Preserve its exact canvas size, aspect ratio, crop, camera position, perspective and composition. Preserve every existing background pixel semantically: the same room/location, walls, furniture, objects, signs, reflections, sky, ground and empty spaces in the same positions. Do not add, remove, replace, move, redesign, clean up or hallucinate any object.

        Preserve the person exactly: same identity, face geometry, expression, gaze, head angle, hair shape and color, body proportions, pose, hand and finger positions, clothing, accessories and position in frame. Do not beautify, reshape, re-pose or restyle them.

        Only change an item above when the user's requested edit explicitly asks for that exact change. For a camera look, filter, lighting or color direction, change ONLY pixel-level color grading, exposure, contrast, white balance, saturation, highlight rolloff, shadows, noise and grain. A photographic filter is not permission to regenerate the scene.

        REQUESTED EDIT:
        \(requestedEdit)
        """
    }

    /// Each path promises a different amount of change. Applying the strict
    /// "same pixels" contract to all three made the creative path impossible.
    /// Haengt die leise Ebene an den Auftrag.
    ///
    /// Der Director hat beim Vorschlagen bereits entschieden, was diese
    /// Richtung technisch braucht — die Fackel weg, das Gesicht aus dem
    /// Gegenlicht holen, die Kleidung behalten. Ohne diese Zeilen geht das
    /// Wissen zwischen Vorschlag und Rendern verloren, und das Bildmodell
    /// muss es sich aus dem Fliesstext zusammenreimen.
    private func withSteps(_ prompt: String, _ option: DirectorAPI.Option) -> String {
        guard !option.internalSteps.isEmpty else { return prompt }
        return prompt + "\n\nALSO DO ALL OF THIS, it is part of the same job:\n"
            + option.internalSteps.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Welchen Vertrag ein Auftrag bekommt — entschieden am `mode`.
    ///
    /// HIER STAND EINE ALTLAST AUS DEM FRUEHEREN AGENTEN:
    ///
    ///     let isCreative = label.contains("new moment") || label.contains("reimagine")
    ///                      || (index == 2 && !label.contains("keep it real"))
    ///     let isSocial   = label.contains("post-ready") || (index == 1 && !isCreative)
    ///
    /// Die Bezeichnungen erfindet der Director heute frei — „post-ready" trifft
    /// praktisch nie. Damit entschied faktisch die POSITION IM ARRAY: Vorschlag
    /// 3 bekam den kreativen Vertrag, der ausdruecklich neue Pose, Ausschnitt
    /// und Umgebung erlaubt. Ein reines Farbgrading auf Platz 3 durfte also die
    /// Szene umbauen, nur weil es Platz 3 war.
    ///
    /// Der Director vergibt laengst genau die Angabe, die hier gebraucht wird.
    /// Sie wurde nur nie gelesen.
    private func renderContract(_ requested: String, mode: DirectorAPI.Mode) -> String {
        switch mode {
        case .grade:
            // Nur Licht und Farbe. Der strengste Vertrag, und der richtige:
            // ein Kamera-Look ist keine Erlaubnis, die Szene neu zu bauen.
            return compositionLockedPrompt(requested)

        case .retouch:
            // Gleiche Szene, gleicher Ausschnitt — aber etwas darf weg oder
            // repariert werden.
            return """
            SOCIAL EDIT CONTRACT:
            Keep the exact same person and identity: face geometry, skin tone, hair, body proportions, clothing and natural texture. Preserve the source photo as the base. You may improve light, color, detail, subject separation and perform only the crop or minor distraction cleanup explicitly required by the requested direction. Do not invent a new setting, pose, outfit or object. No beautification, body reshaping or plastic skin.

            REQUESTED DIRECTION:
            \(requested)
            """

        case .restage:
            // Ort, Kleidung, Pose duerfen sich aendern — die Identitaet nicht.
            return """
            CREATIVE PHOTO CONTRACT:
            Use the source person as the exact identity reference: preserve recognizable face geometry, skin tone, hair characteristics and body proportions. This direction intentionally permits a new natural pose, crop, lighting and environment. Rebuild all perspective, contact shadows, reflections, anatomy and camera grain coherently so it looks like one real photograph captured in that moment—not a pasted subject or a filter. Do not beautify or change the person's identity.

            REQUESTED DIRECTION:
            \(requested)
            """

        case .generate:
            // Etwas Neues. KEIN Personenvertrag: `generate` kommt nur auf
            // ausdrueckliche Bitte und oft ohne Person im Bild — eine Klausel
            // ueber „die Identitaet der Quellperson" waere dort schlicht falsch.
            return requested
        }
    }

    private func guidedDirectionPrompt(_ option: DirectorAPI.Option) -> String {
        withSteps(renderContract(option.prompt, mode: option.mode), option)
    }

    private func runEdit(action: DirectorAPI.Action, sourceImages: [Data]) async {
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

        let protectedAction = DirectorAPI.Action(
            prompt: compositionLockedPrompt(action.prompt),
            mode: action.mode,
            quality: action.quality
        )
        let request = ImageEditRequest(
            prompt: protectedAction.prompt,
            referenceImages: refs,
            quality: quality.apiValue,
            aspectRatio: "auto",
            model: ImageEditAPI.defaultModel
        )

        do {
            let taskID = try await ImageEditAPI.createTask(request)
            let result = try await pollTask(taskID)
            switch result {
            case .success(let imageData):
                // Realism-QA: Ergebnis prüfen und bei Bedarf EINMAL korrigiert neu
                // rendern (kostet den Nutzer keinen zweiten Credit).
                let finalData = await refineIfNeeded(imageData, action: protectedAction, refs: refs, sourceImages: sourceImages, quality: quality)
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
                    persistToLibrary(finalData, prompt: protectedAction.prompt, cost: cost, quality: quality.apiValue)
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
    /// Der Director prüft sein eigenes Ergebnis und bessert nach.
    ///
    /// DAS IST DER KERN DES PRODUKTS: nicht „mehr Funktionen", sondern weniger
    /// Arbeit zwischen dem Wunsch und einem guten Bild. Die Bearbeitung ist
    /// nicht fertig, wenn das Bild zurückkommt — sie ist fertig, wenn der
    /// Director es angesehen hat und dafür geradesteht.
    ///
    /// Zwei Anläufe, nicht einer. Der erste Versuch scheitert typischerweise
    /// an Identität oder daran, dass das Ergebnis wie ein NEUES Bild aussieht
    /// statt wie dasselbe Foto, anders belichtet — beides ist mit einem
    /// korrigierten Prompt oft im zweiten Anlauf behoben.
    ///
    /// Den Nutzer kostet das nichts: Credits werden erst beim Erfolg abgezogen,
    /// und zwar genau einmal. Die Nachbesserung geht auf uns.
    ///
    /// Blockiert nie: schlägt die Prüfung oder der zweite Anlauf fehl, bleibt
    /// das erste Ergebnis stehen.
    private func refineIfNeeded(_ first: Data, action: DirectorAPI.Action, refs: [Data], sourceImages: [Data], quality: ChatQuality) async -> Data {
        guard !sourceImages.isEmpty || action.mode == .generate else { return first }

        var best = first
        var prompt = action.prompt

        // Höchstens zwei Nachbesserungen — danach ist nicht der Prompt das
        // Problem, sondern der Auftrag, und weitere Anläufe kosten nur Zeit.
        //
        // EIN verfehlter LOOK bekommt davon nur den ersten. Er ist ein echter
        // Fehler — das Bild ist nicht die versprochene Aufnahme —, aber ein
        // milderer als eine verlorene Identität. Zweimal dafuer zu rendern
        // waere Geld fuer eine Geschmacksfrage.
        for attempt in 1...2 {
            await setLoadingNote(attempt == 1 ? "Checking the result…" : "Checking again…")

            let verdict = await DirectorAPI.review(
                originals: sourceImages, result: best, prompt: prompt, mode: action.mode
            )
            guard verdict.worthRetrying, let corrected = verdict.correctedPrompt else { return best }
            if verdict.isLookMiss && attempt > 1 { return best }

            // Sagt, WAS er nachbessert — der Nutzer soll sehen, dass hier
            // wirklich jemand hinschaut, statt einen Spinner zu zählen.
            await setLoadingNote(verdict.issues.first.map { "Fixing: \($0.lowercased())" } ?? "Improving the result…")

            // DERSELBE Vertrag wie beim ersten Versuch. Vorher stand hier
            // fest `compositionLockedPrompt` — bei einem `restage` haette der
            // zweite Anlauf also genau das verboten, was der Auftrag verlangt,
            // und die Nachbesserung haette gegen sich selbst gearbeitet.
            let req = ImageEditRequest(
                prompt: renderContract(corrected, mode: action.mode),
                referenceImages: refs,
                quality: quality.apiValue,
                aspectRatio: "auto",
                model: ImageEditAPI.defaultModel
            )
            guard let taskID = try? await ImageEditAPI.createTask(req),
                  case .success(let next) = ((try? await pollTask(taskID)) ?? .failure(""))
            else { return best }

            best = next
            prompt = corrected
        }
        return best
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

    /// Räumt offene Vorschläge weg, sobald einer gewählt wurde — sonst stehen
    /// zwei Runden Karten übereinander.
    private func clearOpenDirections() {
        for i in messages.indices where !messages[i].picks.isEmpty || !messages[i].trends.isEmpty {
            messages[i].picks = []
            messages[i].trends = []
        }
    }

    /// Eine zweite Runde. Was gut ist, entscheidet der Director — hier stand
    /// früher ein erzwungener Prompt, der ihm drei Farbgradings vorschrieb und
    /// jede Retusche verbot.
    private func moreIdeas() {
        guard !isWorking else { return }
        clearOpenDirections()
        Task {
            await send(
                override: "Two different ideas for the same photo, please — not variations of the ones you just gave me.",
                display: "Show me something else"
            )
        }
    }

    /// Options-Tap: vollen Prompt senden, in der Blase nur das Label zeigen.
    private func chooseOption(_ opt: DirectorAPI.Option) {
        guard !isWorking else { return }
        clearOpenDirections()
        // Every suggested direction is rendered by the image model. A preview
        // grade must never be presented or charged as an AI-created result.
        Task { await runDirectorSet([opt]) }
    }

    /// Creates every selected direction as an independent AI render. The
    /// options may describe more than a colour grade, so local Core Image
    /// filters are not a valid implementation of this action.
    private func createAllOptions(_ rawOptions: [DirectorAPI.Option]) {
        guard !isWorking else { return }
        let options = Array(rawOptions.prefix(3))
        guard !options.isEmpty else { return }
        Task { await runDirectorSet(options) }
    }

    private func runDirectorSet(_ options: [DirectorAPI.Option]) async {
        let quality = ChatQuality.medium
        let costPerImage = agentCredits(quality)
        let totalCost = options.count * costPerImage
        let sourceImages = !lastImages.isEmpty ? lastImages : (lastResult.map { [$0] } ?? [])

        guard !sourceImages.isEmpty else {
            flashToast("Add a photo first.")
            return
        }
        guard store.canCreate else {
            showSubscriptionGate = true
            return
        }
        guard store.canAfford(totalCost) else {
            flashToast("Not enough credits to create all \(options.count) versions.")
            return
        }

        clearOpenDirections()
        messages.append(AgentMessage(
            role: .user,
            text: options.count == 1 ? options[0].label : "Create all \(options.count) versions"
        ))
        var loading = AgentMessage(
            role: .assistant,
            text: options.count == 1 ? "Creating your image with AI…" : "Creating your first AI version…",
            isLoading: true
        )
        loading.isRendering = true
        loading.loadingNote = options.count == 1 ? "AI rendering" : "AI rendering 1 of \(options.count)"
        let loadingID = loading.id
        messages.append(loading)
        isWorking = true
        inputFocused = false

        var completed: [(option: DirectorAPI.Option, data: Data)] = []
        var failures = 0

        for (index, option) in options.enumerated() {
            if let messageIndex = messages.firstIndex(where: { $0.id == loadingID }) {
                messages[messageIndex].loadingNote = options.count == 1
                    ? "AI rendering"
                    : "AI rendering \(index + 1) of \(options.count)"
            }

            let request = ImageEditRequest(
                prompt: guidedDirectionPrompt(option),
                referenceImages: sourceImages,
                quality: quality.apiValue,
                aspectRatio: "auto",
                model: ImageEditAPI.defaultModel
            )
            do {
                let taskID = try await ImageEditAPI.createTask(request)
                switch try await pollTask(taskID) {
                case .success(let data):
                    // DERSELBE Pruefweg wie beim direkten Auftrag.
                    //
                    // Er fehlte hier — und das ist der Weg, den fast jeder
                    // Nutzer geht: Tippen auf eine Richtung. Identitaet,
                    // Haende, „sieht aus wie ein neues Bild" und der verfehlte
                    // Look wurden auf dem Hauptweg also nie geprueft, obwohl
                    // die ganze Logik dafuer bereitstand.
                    //
                    // Kostet den Nutzer nichts: `store.consume` laeuft weiter
                    // genau einmal je Bild, unten und erst bei Erfolg.
                    let geprueft = await refineIfNeeded(
                        data,
                        action: DirectorAPI.Action(
                            prompt: request.prompt, mode: option.mode, quality: quality.apiValue
                        ),
                        refs: sourceImages,
                        sourceImages: sourceImages,
                        quality: quality
                    )
                    completed.append((option, geprueft))
                case .failure:
                    failures += 1
                }
            } catch {
                failures += 1
            }
        }

        messages.removeAll { $0.id == loadingID }
        if completed.isEmpty {
            messages.append(AgentMessage(
                role: .assistant,
                text: "I couldn’t create the set. No credits were used — please try again."
            ))
            isWorking = false
            return
        }

        for (index, item) in completed.enumerated() {
            store.consume(costPerImage)
            persistToLibrary(item.data, prompt: item.option.prompt, cost: costPerImage, quality: quality.apiValue)
            var resultMessage = AgentMessage(
                role: .assistant,
                text: index == 0
                    ? (options.count == 1
                        ? "Your AI version is ready."
                        : "Your three AI versions are ready — choose what feels like you, save them, or edit any result again.")
                    : item.option.label
            )
            resultMessage.resultImage = item.data
            resultMessage.beforeImage = sourceImages.first
            withAnimation(.smooth(duration: 0.48)) {
                messages.append(resultMessage)
            }
            if index < completed.count - 1 {
                try? await Task.sleep(for: .milliseconds(320))
            }
        }
        if failures > 0 {
            messages.append(AgentMessage(
                role: .assistant,
                text: "\(failures) version couldn’t be completed, so no credits were used for it."
            ))
        }
        lastResult = completed.first?.data
        isWorking = false
    }

    private func startNewChat() {
        // Die Lesung gehoert zum FOTO, nicht zu den Vorschlaegen. Sie faellt
        // weg, wenn das Foto weg ist — nicht schon, wenn jemand eine Richtung
        // gewaehlt hat. Sonst waere sie beim Trend-Fenster nie mehr da.
        photoReading = nil
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
            templateTitle: "Photo Director",
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
    /// Ein, zwei oder drei Vorschläge — so viele, wie das Foto verdient.
    var picks: [DirectorAPI.Option] = []
    /// Der Vorschlag, den er selbst nehmen würde. Bei genau einem immer der.
    var lead: String? = nil
    /// Aktuelle Trends, nach Passung sortiert. Öffnet der Nutzer selbst.
    var trends: [DirectorAPI.Option] = []

    enum Role { case user, assistant }
}
