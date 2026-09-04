//
//  ClavicApp.swift
//  Clavic
//

import SwiftUI
import SwiftData

@main
struct ClavicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var generationManager = GenerationManager()
    @State private var store = Store()
    /// Übergabe eines fertigen Bildes zwischen den Tabs (Solo Shot → Chat/Studio).
    @State private var editHandoff = EditHandoff()
    /// Das alte Logo-Intro (`intro.mp4`, 4,0 s) ist AUS.
    ///
    /// Grund, gemessen: das Video lief 4 Sekunden über der App, und der
    /// Begrüßungswurf des Chamäleons startete in dem Moment, in dem das Intro
    /// endete — beides zusammen bedeutete, dass der Wurf komplett hinter dem
    /// Intro und dem Startbildschirm ablief. Sichtbar wurde die App erst, als
    /// die Karten längst gelandet waren.
    ///
    /// Der Wurf IST jetzt der Auftakt. Das Logo braucht es davor nicht mehr:
    /// „Clavic" steht in der Top-Bar, und die Figur ist die Marke.
    /// Zum Zurückholen genügt `= true`.
    @State private var showIntro = false

    init() {
        // RevenueCat einmalig beim Start konfigurieren (Observer-Mode).
        // Trackt Downloads/Nutzer; Käufe werden aus Store.swift gemeldet.
        RevenueCatManager.configure()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VideoProject.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            launchRoot
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                generationManager.handleEnteredBackground()
            case .active:
                generationManager.handleBecameActive()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var launchRoot: some View {
#if DEBUG
        if ProcessInfo.processInfo.environment["PHOTO_DIRECTOR_PREVIEW"] == "1" {
            PhotoDirectorPreviewRoot()
        } else {
            mainAppRoot
        }
#else
        mainAppRoot
#endif
    }

    private var mainAppRoot: some View {
        ZStack {
            ContentView(introFinished: !showIntro)
                .environment(generationManager)
                .environment(store)
                .environment(editHandoff)

            if showIntro {
                IntroView { showIntro = false }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .onOpenURL { url in
            AppsFlyerEventTracker.handleOpenURL(url, options: [:])
        }
    }
}
