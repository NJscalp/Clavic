//
//  SettingsView.swift
//  Clavic
//
//  Einstellungen im gruppierten Light-Stil. Nur Inhalte, die wirklich
//  etwas tun: Backend-Status, Rechtstexte (extern verlinkt), Support, Bewerten,
//  Teilen.
//

import SwiftUI
import SwiftData
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(Store.self) private var store

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasSeenWelcomeOffer") private var hasSeenWelcomeOffer = false
    @AppStorage("acceptedContentPolicy") private var acceptedContentPolicy = false

    @State private var infoMessage: String?
    @State private var showDeleteAccount = false

    private let shareMessage = "Clavic – turn your photos into viral videos with AI."

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        backendGroup
                        legalGroup
                        supportGroup
                        accountGroup
                        versionLabel
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .alert(infoMessage ?? "", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("Delete account?", isPresented: $showDeleteAccount, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account and all your creations and data from this device. Remaining credits are not refundable. This cannot be undone.")
        }
    }

    // MARK: - Gruppen

    private var backendGroup: some View {
        SettingsGroup(title: "Connection") {
            SettingsRow(
                label: "Status",
                value: KieSeedanceAPI.hasAPIKey ? "Connected" : "Not connected",
                valueColor: KieSeedanceAPI.hasAPIKey ? Theme.success : Theme.danger
            )
            divider
            SettingsRow(
                label: "Balance",
                value: "\(store.credits) Credits"
            )
        }
    }

    private var legalGroup: some View {
        SettingsGroup(title: "Legal") {
            Link(destination: LegalLinks.privacy) {
                SettingsRow(label: "Privacy Policy", showChevron: true)
            }
            .buttonStyle(.plain)
            divider
            Link(destination: LegalLinks.terms) {
                SettingsRow(label: "Terms of Use", showChevron: true)
            }
            .buttonStyle(.plain)
            divider
            Button {
                acceptedContentPolicy = false
                infoMessage = "The upload consent will appear again the next time you add a photo in Create or Chat."
            } label: {
                SettingsRow(label: "Revisit consent", showChevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var supportGroup: some View {
        SettingsGroup(title: "Support") {
            Button { requestReview() } label: {
                SettingsRow(label: "Rate the app", showChevron: true)
            }
            .buttonStyle(.plain)
            divider
            ShareLink(item: shareMessage) {
                SettingsRow(label: "Share app", showChevron: true)
            }
            .buttonStyle(.plain)
            divider
            Button {
                Task {
                    await store.restore()
                    infoMessage = store.isPro
                        ? "Your subscription has been restored."
                        : "No active purchases found."
                }
            } label: {
                SettingsRow(label: "Restore purchases", showChevron: true)
            }
            .buttonStyle(.plain)
            divider
            Button { contactSupport(subject: "Clavic – Support") } label: {
                SettingsRow(label: "Contact / Report a problem", showChevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var accountGroup: some View {
        SettingsGroup(title: "Account") {
            Button(role: .destructive) {
                showDeleteAccount = true
            } label: {
                SettingsRow(label: "Delete account", labelColor: Theme.danger, showChevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var versionLabel: some View {
        Text("Version \(appVersion) (\(appBuild))")
            .font(.system(size: 13))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var divider: some View {
        Divider().overlay(Theme.stroke).padding(.leading, 16)
    }

    // MARK: - Aktionen

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Löscht das Konto und alle lokalen Nutzerdaten (Apple-Pflicht 5.1.1(v)).
    /// Es gibt keinen eigenen Server-Account – der Sign-in ist nur ein lokaler
    /// Status; daher werden alle lokalen Daten entfernt und die App auf den
    /// Anmelde-Zustand zurückgesetzt.
    private func deleteAccount() {
        // 1) Alle Creations (SwiftData) löschen.
        try? modelContext.delete(model: VideoProject.self)
        try? modelContext.save()
        // 2) Erzeugte Mediendateien im Dokumente-Ordner entfernen.
        if let docs = try? FileManager.default.contentsOfDirectory(
            at: URL.documentsDirectory, includingPropertiesForKeys: nil) {
            for url in docs where ["mp4", "mov", "jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // 3) Guthaben + Kauf-Gutschriften zurücksetzen.
        store.credits = 0
        UserDefaults.standard.removeObject(forKey: Store.grantedTxKey)
        // 4) Onboarding-Status zurücksetzen → zurück zum Onboarding.
        //    (Frueher fuehrte der Reset zum Sign-in-Screen; den gibt es nicht mehr.)
        acceptedContentPolicy = false
        hasSeenWelcomeOffer = false
        hasSeenOnboarding = false
        dismiss()
    }

    /// Öffnet eine vorbereitete Support-/Report-Mail.
    private func contactSupport(subject: String) {
        let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let body = "App version: \(appVersion) (\(appBuild))\n\nDescribe your issue or report below:\n"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(LegalLinks.supportEmail)?subject=\(s)&body=\(body)") {
            openURL(url)
        }
    }
}

// MARK: - Rechtstexte (extern)

/// Die Rechtstexte liegen NICHT in der App, sondern auf einer öffentlichen
/// GitHub-Pages-Website (Quelle: docs/ im Clavic-Repo). Alle Links in der App
/// öffnen diese Seiten im Browser. So bleibt nur eine Quelle der Wahrheit, und
/// es entspricht Apples Anforderung an erreichbare Privacy-/Terms-Links.
enum LegalLinks {
    static let privacy = URL(string: "https://njscalp.github.io/Clavic/privacy.html")!
    static let terms = URL(string: "https://njscalp.github.io/Clavic/terms.html")!
    /// Support-/Report-Kontakt (für Apple-Pflicht-Reporting änderbar).
    static let supportEmail = "Clavic.ai.app@gmail.com"
}


// MARK: - Bausteine

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .cardStyle()
        }
    }
}

struct SettingsRow: View {
    let label: String
    var labelColor: Color = Theme.textPrimary
    var value: String? = nil
    var valueColor: Color = Theme.textSecondary
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(labelColor)
            Spacer(minLength: 12)
            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}
