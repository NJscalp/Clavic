//
//  SettingsView.swift
//  Clavic
//
//  Einstellungen im gruppierten Light-Stil. Nur Inhalte, die wirklich
//  etwas tun: Backend-Status, Rechtstexte (in-App), Support, Bewerten,
//  Teilen.
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(Store.self) private var store

    @State private var legalDocument: LegalDocument?
    @State private var infoMessage: String?

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
        .sheet(item: $legalDocument) { doc in
            LegalTextView(document: doc)
        }
        .alert(infoMessage ?? "", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Gruppen

    private var backendGroup: some View {
        SettingsGroup(title: "Connection") {
            SettingsRow(
                label: "Status",
                value: SeedanceAPI.hasAPIKey ? "Connected" : "Not connected",
                valueColor: SeedanceAPI.hasAPIKey ? Theme.success : Theme.danger
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
            Button { legalDocument = .privacy } label: {
                SettingsRow(label: "Privacy Policy", showChevron: true)
            }
            .buttonStyle(.plain)
            divider
            Button { legalDocument = .terms } label: {
                SettingsRow(label: "Terms of Use", showChevron: true)
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
}

// MARK: - Rechtstexte

enum LegalDocument: Identifiable {
    case privacy
    case terms

    var id: String {
        switch self {
        case .privacy: return "privacy"
        case .terms: return "terms"
        }
    }

    var title: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .terms: return "Terms of Use"
        }
    }

    var body: String {
        switch self {
        case .privacy: return LegalContent.privacy
        case .terms: return LegalContent.terms
        }
    }
}

/// Zentrale Rechtstexte. Identisch zur veröffentlichten Web-Version
/// (docs/privacy.html, docs/terms.html) für den App-Store-Privacy-Link.
enum LegalContent {
    /// Kontaktadresse – auch im App Store Connect hinterlegen.
    static let contactEmail = "support@clavic.app"
    static let lastUpdated = "14 June 2026"

    static let privacy = """
    Privacy Policy
    Last updated: \(lastUpdated)

    Clavic ("Clavic", "we", "us") lets you create and edit videos and images
    from your own photos and text descriptions using artificial intelligence.
    We take your privacy seriously and only process the data needed to provide
    the app. This policy explains what we process, why, and your rights.

    1. Who is responsible
    The operator of the Clavic app is responsible for the processing described
    here. For any privacy request, contact us at \(contactEmail).

    2. What data we process
    • Content you provide: the photos and videos you upload and the text prompts
      you enter to generate or edit content.
    • Generated content: the videos and images the AI creates for you.
    • Purchase data: when you buy credits or a subscription, the purchase is
      handled by Apple. We receive confirmation of the purchase but never your
      payment-card details.
    • Sign in with Apple: if you sign in, we receive the identifier Apple
      provides. We do not request your name or email. You may use a private
      "Hide My Email" address.
    • Technical data: basic, non-identifying information needed to deliver
      requests reliably (e.g. error and connection status).

    We do NOT use advertising trackers, we do NOT collect your contacts or
    location, and we do NOT build advertising profiles about you.

    3. How and why we use your data
    We use the photos, videos and prompts you provide solely to perform the
    generation or edit you requested. To do this, your input is sent over an
    encrypted connection to our processing backend and from there to the AI
    providers that run the models. Purchase and account data are used to
    unlock and restore your credits and subscription.

    Legal bases (GDPR Art. 6(1)): performance of our contract with you (b) for
    providing the service and purchases, and our legitimate interest (f) in
    operating and securing the app.

    4. AI processing and providers (sub-processors)
    Your content is processed by the following providers acting on our behalf:
    • Apple – Sign in with Apple, in-app purchases, push delivery.
    • Vercel Inc. (USA) – hosting of our processing backend.
    • fal.ai and kie.ai – the AI models that generate or edit your content.
    These providers process your input only to return your result and are not
    permitted to use it to train their own models for their own purposes or for
    advertising. Processing may take place on servers in the United States.

    5. Storage and retention
    Your finished videos and images are stored locally on your device. Uploaded
    input and generated output are held by the providers only temporarily to
    complete the request and are deleted automatically a short time afterwards.
    Deleting a project in the app removes it from your device.

    6. Photo library access
    Clavic only requests "add" access to your photo library, and only when you
    choose to save a result. We never read or scan your existing photos. Photos
    you pick as input are selected by you through Apple's system picker.

    7. International transfers
    Because some providers are located in the United States, your data may be
    transferred there. Such transfers are based on appropriate safeguards
    (e.g. the EU Standard Contractual Clauses).

    8. Your rights
    Subject to applicable law (including the GDPR), you have the right to
    access, rectify, erase, restrict and port your data, and to object to
    processing. You can exercise these rights at any time by contacting
    \(contactEmail). You also have the right to lodge a complaint with your
    local data-protection authority.

    9. Children
    Clavic is not directed to children. You must be at least 17 years old, or
    the age of digital consent in your country, to use the app.

    10. Security
    We use encrypted connections (HTTPS/TLS) and limit access to data. No method
    of transmission is 100% secure, but we work to protect your information.

    11. Changes
    We may update this policy. The current version is always available in the
    app and on our website. Material changes will be highlighted in the app.

    12. Contact
    For any privacy question or request, email \(contactEmail).
    """

    static let terms = """
    Terms of Use
    Last updated: \(lastUpdated)

    By downloading or using Clavic you agree to these Terms of Use. If you do
    not agree, do not use the app.

    1. The service
    Clavic creates and edits videos and images from the photos and text
    descriptions you provide, using AI models operated by third-party providers.

    2. Eligibility
    You must be at least 17 years old, or the age of digital consent in your
    country, and able to enter a binding agreement.

    3. Your content and your responsibility
    You keep ownership of the photos and videos you upload. You confirm that you
    have all necessary rights to the content you upload and that your use does
    not infringe anyone's rights. You are solely responsible for the input you
    provide and the content you generate.

    4. Acceptable use
    You agree NOT to use Clavic to create or upload content that:
    • depicts a real, identifiable person without their consent (no deepfakes,
      no non-consensual likeness, no impersonation);
    • is sexual, nude or sexually suggestive, or that sexualises minors in any
      way;
    • is unlawful, hateful, harassing, violent, deceptive or that infringes
      intellectual-property, privacy or publicity rights.
    We may refuse, remove or block any request or content that violates these
    terms and may suspend access for misuse.

    5. AI output disclaimer
    AI-generated results can be inaccurate, unexpected or may not reflect real
    people or events. Results are provided "as is" without warranty of accuracy,
    quality or fitness for a particular purpose. Do not rely on outputs as fact.

    6. Ownership of results
    Subject to your compliance with these terms and the providers' rules, you may
    use the content you generate, including for personal and commercial purposes.
    You are responsible for how you use and publish it.

    7. Credits, subscriptions and payments
    Purchases of credits and subscriptions are processed by Apple through your
    App Store account. Subscriptions renew automatically until cancelled at least
    24 hours before the end of the current period. You can manage or cancel a
    subscription in your Apple ID settings. Credits are a one-time purchase and
    are consumed when you generate content. Except where required by law or by
    Apple's policies, payments are non-refundable.

    8. Apple standard EULA
    Unless you have a separate written agreement with us, your license to use the
    app is governed by Apple's standard Licensed Application End User License
    Agreement (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).
    Apple is not responsible for the app or its content.

    9. Termination
    We may suspend or end your access if you breach these terms. You may stop
    using the app at any time.

    10. Liability
    To the maximum extent permitted by law, Clavic is not liable for indirect or
    consequential damages arising from your use of the app or AI outputs. Nothing
    in these terms limits liability that cannot be limited by law.

    11. Changes and governing law
    We may update these terms; the current version applies. These terms are
    governed by the laws of the operator's place of business, without prejudice
    to mandatory consumer-protection rules in your country of residence.

    12. Contact
    Questions? Email us at \(contactEmail).
    """
}

struct LegalTextView: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    Text(document.body)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.screenPadding)
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.light)
    }
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
    var value: String? = nil
    var valueColor: Color = Theme.textSecondary
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
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
