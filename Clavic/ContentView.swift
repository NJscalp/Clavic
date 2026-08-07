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
    @Environment(\.modelContext) private var modelContext
    @Environment(GenerationManager.self) private var generationManager
    @Environment(Store.self) private var store
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasSeenLarpFunnel") private var hasSeenLarpFunnel = false
    @AppStorage("hasSignedIn") private var hasSignedIn = false
    @AppStorage("hasSeenSubscriptionOffer") private var hasSeenSubscriptionOffer = false

    @State private var tab: MainTab = .discover
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

    enum MainTab { case discover, chatEdit, agent, studio, library }

    /// Laufende Kachel-Vorschauen nur, wenn Discover vorne sichtbar ist
    /// (kein offenes Sheet/Cover) – hält Tab-Wechsel und Tastatur flüssig.
    private var previewsActive: Bool {
        let inMainApp = hasSeenOnboarding && hasSignedIn
        return inMainApp && tab == .discover && createRequest == nil && !showSettings && !showPaywall && !showSubscriptionOffer && !showSubscriptionGate
    }

    /// Tastatur-/Preview-Last: nur der sichtbare Tab hält Live-State aktiv.
    private var chatEditActive: Bool {
        let inMainApp = hasSeenOnboarding && hasSignedIn
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
                        DiscoverView { template in
                            openCreate(with: template)
                        }
                        .opacity(tab == .discover ? 1 : 0)
                        .allowsHitTesting(tab == .discover)
                        .environment(\.previewsActive, previewsActive)

                        ChatEditView()
                            .opacity(tab == .chatEdit ? 1 : 0)
                            .allowsHitTesting(tab == .chatEdit)

                        AgentView()
                            .opacity(tab == .agent ? 1 : 0)
                            .allowsHitTesting(tab == .agent)

                        StudioView { project in
                            tab = .library
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                navPath = [project]
                            }
                        }
                        .opacity(tab == .studio ? 1 : 0)
                        .allowsHitTesting(tab == .studio)

                        LibraryView()
                            .opacity(tab == .library ? 1 : 0)
                            .allowsHitTesting(tab == .library)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) { topBar }
                    // Tab-Bar als Bottom-SafeAreaInset: der Inhalt jeder Tab liegt
                    // automatisch SAUBER über der Bar (kein manuelles Bottom-Padding
                    // mehr, keine Überlappung). Bei Tastatur wird die Bar ausgeblendet
                    // (Inset-Höhe 0), sodass der Chat-Input Platz hat.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !keyboardVisible {
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

            // Erststart-Flow: Onboarding → Larp-Funnel (Conversion) → Anmeldung → App
            if !hasSeenOnboarding {
                OnboardingView(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { hasSeenOnboarding = !$0 }
                ))
                .transition(.opacity)
                .zIndex(3)
            } else if !hasSeenLarpFunnel {
                // Interaktiver Teaser VOR der Paywall: Foto → Analyse → Ideen →
                // „Continue to see your result" → Paywall. Der Funnel IST das
                // Abo-Angebot → danach kein zweites Paywall-Sheet mehr zeigen.
                LarpFunnelView {
                    hasSeenLarpFunnel = true
                    hasSeenSubscriptionOffer = true
                }
                .transition(.opacity)
                .zIndex(3)
            } else if !hasSignedIn {
                SignInView(isSignedIn: $hasSignedIn)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showPaywall) {
            CreditsView()
        }
        .sheet(isPresented: $showSubscriptionOffer, onDismiss: {
            hasSeenSubscriptionOffer = true
        }) {
            PaywallView()
        }
        .sheet(isPresented: $showSubscriptionGate, onDismiss: {
            if !store.isPro { pendingCreateTemplate = nil }
        }) {
            PaywallView()
        }
        .onChange(of: hasSignedIn) { _, signedIn in
            if signedIn { completeSignInFlow() }
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
            if hasSignedIn { completeSignInFlow() }
            #if DEBUG
            // UI-Review-Hook (nur Debug/Simulator): Tab oder Template per
            // Launch-Env öffnen, z. B. SIMCTL_CHILD_UITEST_TEMPLATE="Pinterest Swap".
            let env = ProcessInfo.processInfo.environment
            if let t = env["UITEST_TAB"] {
                if t == "chat" { tab = .chatEdit }
                else if t == "agent" { tab = .agent }
                else if t == "library" { tab = .library }
                else if t == "studio" { tab = .studio }
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

    /// Nach Anmeldung: einmaliges, schließbares Abo-Angebot.
    private func completeSignInFlow() {
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
        .background(Theme.background.opacity(0.95))
    }

    // MARK: - Schwebende Bottom-Bar

    // Beschriftete Bottom-Bar: jedes Tab zeigt Icon + Titel, damit man sofort
    // findet, was was ist. Reihenfolge gruppiert bewusst: Entdecken (browse) →
    // die drei Erstellen-Tools (Chat · Agent · Studio) → Bibliothek.
    private var floatingBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 2) {
                    barButton(icon: "square.grid.2x2.fill", label: "Discover", isActive: tab == .discover) {
                        withAnimation(.spring(duration: 0.3)) { tab = .discover }
                    }
                    barButton(icon: "wand.and.stars", label: "Chat", isActive: tab == .chatEdit) {
                        withAnimation(.spring(duration: 0.3)) { tab = .chatEdit }
                    }
                    barButton(icon: "diamond.fill", label: "Agent", isActive: tab == .agent) {
                        withAnimation(.spring(duration: 0.3)) { tab = .agent }
                    }
                    barButton(icon: "slider.horizontal.3", label: "Studio", isActive: tab == .studio) {
                        withAnimation(.spring(duration: 0.3)) { tab = .studio }
                    }
                    barButton(icon: "photo.on.rectangle", label: "Library", isActive: tab == .library) {
                        withAnimation(.spring(duration: 0.3)) { tab = .library }
                    }
                }
                .padding(5)
                .glassEffect(.regular, in: Capsule())
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
            .frame(width: 60, height: 50)
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
}
