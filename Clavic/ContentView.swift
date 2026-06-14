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
    @AppStorage("hasSignedIn") private var hasSignedIn = false
    @AppStorage("hasSeenWelcomeOffer") private var hasSeenWelcomeOffer = false

    @State private var tab: MainTab = .discover
    @State private var showSettings = false
    @State private var createRequest: CreateRequest?
    @State private var showPaywall = false

    enum MainTab { case discover, library }

    /// Hülle für die Erstellen-Präsentation. Über `item` statt `isPresented`
    /// wird garantiert immer das korrekte Template (oder keins) übergeben.
    struct CreateRequest: Identifiable {
        let id = UUID()
        let template: VideoTemplate?
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    Theme.background.ignoresSafeArea()

                    Group {
                        switch tab {
                        case .discover:
                            DiscoverView { template in
                                openCreate(with: template)
                            }
                        case .library:
                            LibraryView()
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) { topBar }

                    floatingBar
                }
                .navigationDestination(for: VideoProject.self) { project in
                    VideoDetailView(project: project)
                }
            }
            .tint(Theme.accent)

            // Erststart-Flow: Onboarding → iCloud-Anmeldung → Welcome-Paywall
            if !hasSeenOnboarding {
                OnboardingView(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { hasSeenOnboarding = !$0 }
                ))
                .transition(.opacity)
                .zIndex(3)
            } else if !hasSignedIn {
                SignInView(isSignedIn: $hasSignedIn)
                    .transition(.opacity)
                    .zIndex(2)
            } else if !store.isPro && !hasSeenWelcomeOffer {
                HardPaywallView { withAnimation { hasSeenWelcomeOffer = true } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showPaywall) {
            CreditsView()
        }
        .fullScreenCover(item: $createRequest) { request in
            CreateView(template: request.template) {
                tab = .library
            }
        }
        .onAppear {
            generationManager.configure(context: modelContext)
            generationManager.store = store
            generationManager.resumePendingProjects()
        }
    }

    private func openCreate(with template: VideoTemplate?) {
        createRequest = CreateRequest(template: template)
    }

    // MARK: - Top-Bar

    private var topBar: some View {
        HStack {
            Button {
                showPaywall = true
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

    private var floatingBar: some View {
        HStack {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    barButton(icon: "globe", isActive: tab == .discover) {
                        withAnimation(.spring(duration: 0.3)) { tab = .discover }
                    }
                    barButton(icon: "photo.on.rectangle", isActive: tab == .library) {
                        withAnimation(.spring(duration: 0.3)) { tab = .library }
                    }
                }
                .padding(7)
                .glassEffect(.regular, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 6)
    }

    private func barButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isActive ? .white : Theme.textSecondary)
                .frame(width: 60, height: 60)
                .background {
                    if isActive {
                        Circle().fill(Theme.accent)
                            .glassEffect(.regular.tint(Theme.accent).interactive(), in: Circle())
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
