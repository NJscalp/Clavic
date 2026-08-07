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
    @State private var showIntro = true

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
            ZStack {
                ContentView()
                    .environment(generationManager)
                    .environment(store)

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
}
