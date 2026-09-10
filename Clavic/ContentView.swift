//
//  ContentView.swift
//  Clavic
//
//  Root-View: geteilte Top-Bar, Inhalt (Entdecken / Bibliothek) und
//  schwebende Bottom-Bar zum Erstellen.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    /// true, sobald das Start-Overlay weg ist. Erst dann darf die Maskottchen-
    /// Animation loslaufen — sonst spielt sie unsichtbar hinter dem Intro ab.
    var introFinished: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(GenerationManager.self) private var generationManager
    @Environment(Store.self) private var store
    @Environment(EditHandoff.self) private var editHandoff
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasSeenSubscriptionOffer") private var hasSeenSubscriptionOffer = false

    @State private var tab: MainTab = .agent
    @State private var showSettings = false
    @State private var createRequest: CreateRequest?
    @State private var showPaywall = false
    @State private var showSubscriptionOffer = false
    /// Abo-Gate beim Template-Tipp (schließbares Sheet, kein App-Block).
    @State private var showSubscriptionGate = false
    @State private var pendingCreateTemplate: VideoTemplate?
    @State private var keyboardVisible = false
    /// Navigations-Pfad: nach „Generate" direkt ins Detail/Generierung pushen.
    @State private var navPath: [VideoProject] = []
    /// Server-gesteuerte Templates (neue Trends ohne App-Update).
    @State private var templateStore = TemplateStore()

    /// Der Studio-Tab ist entfallen. Was man dort wirklich brauchte —
    /// Objekte entfernen — steht jetzt als eigenes Werkzeug am Start des
    /// Directors; alles Weitere war eine zweite Umsetzung dessen, was der
    /// Chat-Tab ohnehin kann.
    enum MainTab { case chatEdit, agent, library }

    /// Tastatur-/Preview-Last: nur der sichtbare Tab hält Live-State aktiv.
    private var chatEditActive: Bool {
        let inMainApp = hasSeenOnboarding
        return inMainApp && tab == .chatEdit && createRequest == nil && !showSettings && !showPaywall && !showSubscriptionOffer && !showSubscriptionGate
    }

    /// Hülle für die Erstellen-Präsentation. Über `item` statt `isPresented`
    /// wird garantiert immer das korrekte Template (oder keins) übergeben.
    struct CreateRequest: Identifiable {
        let id = UUID()
        let template: VideoTemplate?
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $navPath) {
                ZStack(alignment: .bottom) {
                    Theme.background.ignoresSafeArea()

                    ZStack {
                        ChatEditView()
                            .opacity(tab == .chatEdit ? 1 : 0)
                            .allowsHitTesting(tab == .chatEdit)

                        AgentView(introFinished: introFinished)
                            .opacity(tab == .agent ? 1 : 0)
                            .allowsHitTesting(tab == .agent)

                        LibraryView()
                            .opacity(tab == .library ? 1 : 0)
                            .allowsHitTesting(tab == .library)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) { topBar }
                    // Content tabs keep the old reserved area. Chat + Director
                    // deliberately draw behind the glass bar so there is no large
                    // opaque strip between their floating composer and navigation.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !keyboardVisible && tab != .chatEdit && tab != .agent {
                            floatingBar
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !keyboardVisible && (tab == .chatEdit || tab == .agent) {
                            floatingBar
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: keyboardVisible)
                }
                .navigationDestination(for: VideoProject.self) { project in
                    VideoDetailView(project: project)
                }
            }
            .tint(Theme.accent)

            // Erststart-Flow: Onboarding → App.
            // Der Larp-Funnel und der Sign-in-mit-Apple-Screen sind am
            // 09.09.2026 entfallen. Das Abo-Angebot laeuft jetzt direkt nach
            // dem Onboarding ueber completeOnboardingFlow().
            if !hasSeenOnboarding {
                OnboardingFlowView(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { hasSeenOnboarding = !$0 }
                ))
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showPaywall) {
            CreditsView()
        }
        // Vollbild statt Sheet: als Karte mit grauem Streifen darueber wirkte
        // die Paywall wie ein Hinweisfenster, nicht wie ein eigener Screen.
        .fullScreenCover(isPresented: $showSubscriptionOffer, onDismiss: {
            hasSeenSubscriptionOffer = true
        }) {
            PaywallView()
        }
        .fullScreenCover(isPresented: $showSubscriptionGate, onDismiss: {
            if !store.isPro { pendingCreateTemplate = nil }
        }) {
            PaywallView()
        }
        // Ein übergebenes Bild bringt den Tab mit, in dem es gebraucht wird.
        // Der Erstellen-Weg über `createRequest` bleibt davon unberührt.
        // Am ZÄHLER, nicht am Bild — siehe `EditHandoff.chatToken`.
        .onChange(of: editHandoff.chatToken) { _, _ in
            withAnimation(.spring(duration: 0.3)) { tab = .chatEdit }
        }
        .onChange(of: hasSeenOnboarding) { _, done in
            if done { completeOnboardingFlow() }
        }
        .onChange(of: store.isPro) { _, isPro in
            guard isPro, let template = pendingCreateTemplate else { return }
            pendingCreateTemplate = nil
            showSubscriptionGate = false
            createRequest = CreateRequest(template: template)
        }
        .fullScreenCover(item: $createRequest) { request in
            CreateView(template: request.template) { project in
                // Nach „Generate" direkt in die Generierungs-/Detail-Ansicht des
                // neuen Projekts (statt in die My-Creations-Liste). Library liegt
                // darunter, damit „Zurück" sauber dorthin führt.
                tab = .library
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    navPath = [project]
                }
            }
        }
        .environment(templateStore)
        .onAppear {
            generationManager.configure(context: modelContext)
            generationManager.store = store
            generationManager.resumePendingProjects()
            if hasSeenOnboarding { completeOnboardingFlow() }
            #if DEBUG
            // UI-Review-Hook (nur Debug/Simulator): Tab oder Template per
            // Launch-Env öffnen, z. B. SIMCTL_CHILD_UITEST_TEMPLATE="Pinterest Swap".
            let env = ProcessInfo.processInfo.environment
            if let t = env["UITEST_TAB"] {
                if t == "chat" { tab = .chatEdit }
                else if t == "agent" { tab = .agent }
                else if t == "library" { tab = .library }
            }
            if let title = env["UITEST_TEMPLATE"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if let tpl = templateStore.templates.first(where: { $0.title == title }) {
                        openCreate(with: tpl)
                    }
                }
            }
            #endif
        }
        .task {
            await templateStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    private func openCreate(with template: VideoTemplate?) {
        guard store.canCreate else {
            pendingCreateTemplate = template
            showSubscriptionGate = true
            return
        }
        createRequest = CreateRequest(template: template)
    }

    /// Nach dem Onboarding: einmaliges, schließbares Abo-Angebot.
    private func completeOnboardingFlow() {
        guard !hasSeenSubscriptionOffer, !store.isPro else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showSubscriptionOffer = true
        }
    }

    // MARK: - Top-Bar

    private var topBar: some View {
        HStack {
            Button {
                if store.isPro {
                    showPaywall = true
                } else {
                    showSubscriptionGate = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image("credit_coin")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("\(store.credits)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(store.isPro ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.accent), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Clavic")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 10)
        // WARUM DIE LEISTE UNTEN AUSLAEUFT.
        //
        // Zwei Fassungen davor, beide falsch:
        //
        // 1. `Theme.background.opacity(0.95)` — die fehlenden 5 % waren als
        //    Andeutung von Tiefe gedacht und lasen sich als Zeichenfehler:
        //    gescrollte Karten schimmerten als Geistertext DURCH die Leiste,
        //    auch hinter dem Titel.
        //
        // 2. Voll deckendes `Theme.background` — kein Geistertext mehr, dafuer
        //    schnitt die Leiste den Inhalt an ihrer Unterkante knochenhart ab.
        //    Weil sie dieselbe Farbe hat wie der Hintergrund, sieht man dort
        //    keine Kopfzeile, sondern einen Balken, der Karten zerschneidet.
        //    Im Simulator reproduziert: Startbildschirm hochgescrollt, harte
        //    Linie bei 122 pt quer durch die Fotokarten.
        //
        // Jetzt: deckend ueber die volle Hoehe der Leiste — hinter dem Titel
        // ist NIE etwas zu ahnen — und darunter ein 26 pt langer Auslauf, in
        // dem der Inhalt weich verschwindet. Keine Kante, kein Geistertext.
        // Das negative untere `padding` laesst den Verlauf ueber die Leiste
        // hinausragen; ein `.background` wird nicht beschnitten.
        //
        // Der Auslauf endet auf `Theme.background.opacity(0)`, NICHT auf
        // `.clear`: `.clear` ist schwarz mit Alpha 0, und dagegen zu
        // interpolieren graut die Mitte des Verlaufs an.
        .background {
            VStack(spacing: 0) {
                // Deckend ueber Statusleiste UND Leiste. Ohne
                // `ignoresSafeArea` endet diese Flaeche an der Unterkante der
                // Statusleiste — und weil ein `ScrollView` bis dorthin
                // zeichnet, stand gescrollter Inhalt DARUEBER: Foto und Figur
                // oben, Karten unten, dazwischen ein cremefarbener Streifen.
                // Das ist der Balken, den man sieht. Im Simulator so
                // reproduziert, Picks-Ansicht weit hochgescrollt.
                Theme.background
                // Der Auslauf: feste 26 pt, nicht ein Anteil der Hoehe. Der
                // obere Sicherheitsbereich ist je nach Geraet 20 bis 62 pt
                // gross; ein Prozentwert waere auf jedem Modell woanders.
                LinearGradient(
                    stops: [
                        .init(color: Theme.background, location: 0),
                        .init(color: Theme.background.opacity(0.72), location: 0.5),
                        .init(color: Theme.background.opacity(0), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 26)
            }
            // Das negative untere `padding` schiebt genau diese 26 pt unter
            // die Leiste hinaus. Deckend bleibt damit exakt die Leiste selbst.
            .padding(.bottom, -26)
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Schwebende Bottom-Bar

    // Vier klare Ziele: Director ist der zentrale Einstieg, daneben freie
    // Bearbeitung, Studio und Bibliothek. Discover ist bewusst entfernt.
    private var floatingBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 2) {
                    barButton(icon: "sparkles.rectangle.stack.fill", label: "Director", isActive: tab == .agent) {
                        withAnimation(.spring(duration: 0.3)) { tab = .agent }
                    }
                    barButton(icon: "wand.and.stars", label: "Chat", isActive: tab == .chatEdit) {
                        withAnimation(.spring(duration: 0.3)) { tab = .chatEdit }
                    }
                    barButton(icon: "photo.on.rectangle", label: "Library", isActive: tab == .library) {
                        withAnimation(.spring(duration: 0.3)) { tab = .library }
                    }
                }
                .padding(5)
                .glassEffect(.regular, in: Capsule())
                // DIE LEISTE MUSS TIPPS SCHLUCKEN, AUCH NEBEN DEN KNOEPFEN.
                //
                // Gemeldet: „ich druecke drauf und dahinter wird was
                // ausgewaehlt". Genau so war es. Sichtbar ist eine Kapsel,
                // hittestbar waren nur die drei Knopfflaechen — das 5-Punkt-
                // Polster ringsum und die 2 Punkt zwischen den Knoepfen
                // gehoerten zu nichts. Ein Tipp dorthin fiel durch das Glas auf
                // den Inhalt darunter; im Director liegt dort die Look-Liste,
                // also wurde ein Look gewaehlt.
                //
                // `contentShape` macht die ganze Kapsel hittestbar, der leere
                // Tipp verbraucht ihn. Die Knoepfe liegen weiter innen und
                // gewinnen fuer sich selbst — nur die Luecken landen hier.
                .contentShape(Capsule())
                .onTapGesture { }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 6)
    }

    private func barButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? .white : Theme.textSecondary)
            .frame(width: 70, height: 50)
            .background {
                if isActive {
                    Capsule().fill(Theme.accent)
                        .glassEffect(.regular.tint(Theme.accent).interactive(), in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VideoProject.self, inMemory: true)
        .environment(GenerationManager())
        .environment(Store())
        .environment(EditHandoff())
}
