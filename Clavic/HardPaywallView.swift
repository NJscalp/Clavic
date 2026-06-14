//
//  HardPaywallView.swift
//  Clavic
//
//  Welcome-Paywall direkt nach der Anmeldung. Ruhiges, hochwertiges Design,
//  passend zur App (kein „Sale"-Ton). Passt komplett auf den Bildschirm und
//  scrollt nur auf sehr kleinen Geräten.
//

import SwiftUI
import StoreKit

struct HardPaywallView: View {
    /// Wird aufgerufen, wenn der Nutzer ohne Kauf fortfährt.
    var onClose: () -> Void

    @Environment(Store.self) private var store

    @State private var selected: Product?
    @State private var isPurchasing = false
    @State private var infoMessage: String?
    @State private var legalDocument: LegalDocument?

    private let benefits: [(String, String)] = [
        ("infinity", "Credits refilled every period"),
        ("sparkles", "Every trend, edit & upscaler"),
        ("bolt.fill", "Priority processing"),
        ("checkmark.seal.fill", "No watermark on your exports")
    ]

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let isSmall = h < 740
            let showVisual = !isSmall
            let gap: CGFloat = isSmall ? 10 : 16
            let titleSize: CGFloat = isSmall ? 23 : 28
            let visualH = min(h * 0.15, 132)
            let contentW = geo.size.width - Theme.screenPadding * 2

            VStack(spacing: 0) {
                if showVisual {
                    visual(height: visualH, width: contentW)
                }

                Spacer(minLength: gap)
                titleBlock(titleSize: titleSize, isSmall: isSmall)

                Spacer(minLength: gap)
                benefitList(isSmall: isSmall)

                Spacer(minLength: gap)
                planSection

                Spacer(minLength: gap)
                ctaBlock(isSmall: isSmall)

                Spacer(minLength: 6)
                footer
            }
            .frame(width: contentW, alignment: .center)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { preselect() }
        .onChange(of: store.subscriptions.count) { _, _ in preselect() }
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

    // MARK: - Visual

    private func visual(height: CGFloat, width: CGFloat) -> some View {
        MarqueeRow(
            examples: OnboardingExamples.rowA,
            cardWidth: height * 0.72,
            cardHeight: height,
            speed: 20
        )
        .frame(width: width, height: height)
        .clipped()
        .mask(
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func titleBlock(titleSize: CGFloat, isSmall: Bool) -> some View {
        VStack(spacing: isSmall ? 5 : 8) {
            Text("Create without limits")
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text("Unlock every tool and keep your credits topped up – make as much as you want.")
                .font(.system(size: isSmall ? 13.5 : 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
        }
    }

    private func benefitList(isSmall: Bool) -> some View {
        let items = isSmall ? Array(benefits.prefix(3)) : benefits
        return VStack(spacing: isSmall ? 9 : 12) {
            ForEach(items, id: \.1) { icon, text in
                HStack(spacing: 13) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    Text(text)
                        .font(.system(size: isSmall ? 14 : 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.success)
                }
            }
        }
        .padding(isSmall ? 13 : 16)
        .cardStyle()
    }

    // MARK: - Pläne

    private var planSection: some View {
        Group {
            if !store.subscriptions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(store.subscriptions, id: \.id) { product in
                        HardPlanCard(
                            product: product,
                            isSelected: selected?.id == product.id,
                            isBestValue: product.id == StoreIDs.yearly
                        ) { selected = product }
                    }
                }
            } else if store.isLoadingProducts {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading plans …")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .cardStyle()
            } else {
                VStack(spacing: 10) {
                    Text("Plans couldn't load.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Try again") {
                        Task { await store.reload(); preselect() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .cardStyle()
            }
        }
    }

    private func ctaBlock(isSmall: Bool) -> some View {
        VStack(spacing: isSmall ? 7 : 10) {
            Button {
                guard let product = selected else { return }
                Task { await buy(product) }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaTitle)
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: selected != nil && !isPurchasing))
            .disabled(selected == nil || isPurchasing)

            Text(ctaSubtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)

            Button("Restore purchases") {
                Task {
                    await store.restore()
                    infoMessage = store.isPro
                        ? "Your subscription has been restored."
                        : "No active purchases found."
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Auto-renews until cancelled. Manage anytime in your App Store settings.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Button("Terms of Use") { legalDocument = .terms }
                Text("·").foregroundStyle(Theme.textTertiary)
                Button("Privacy Policy") { legalDocument = .privacy }
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Texte

    private var ctaTitle: String {
        guard let selected else { return "Choose a plan" }
        if let offer = selected.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return "Start free trial"
        }
        return "Continue"
    }

    private var ctaSubtitle: String {
        guard let selected else { return "Cancel anytime." }
        if let offer = selected.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return "\(trialDays(offer)) days free, then \(selected.displayPrice). Cancel anytime."
        }
        return "\(selected.displayPrice), renews automatically. Cancel anytime."
    }

    private func trialDays(_ offer: Product.SubscriptionOffer) -> Int {
        let p = offer.period
        switch p.unit {
        case .day: return p.value
        case .week: return p.value * 7
        case .month: return p.value * 30
        case .year: return p.value * 365
        @unknown default: return p.value
        }
    }

    // MARK: - Aktionen

    private func preselect() {
        if selected == nil || !store.subscriptions.contains(where: { $0.id == selected?.id }) {
            selected = store.subscriptions.first(where: { $0.id == StoreIDs.yearly })
                ?? store.subscriptions.first
        }
    }

    private func buy(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let success = try await store.purchase(product)
            if success && !store.isPro {
                infoMessage = "Purchase complete."
            }
        } catch {
            infoMessage = "Purchase failed. Please try again."
        }
    }
}

// MARK: - Plan-Karte

private struct HardPlanCard: View {
    let product: Product
    let isSelected: Bool
    let isBestValue: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle().fill(Theme.accent).frame(width: 13, height: 13)
                    }
                }

                HStack(spacing: 8) {
                    Text(planLabel)
                        .font(.system(size: 16.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    if isBestValue {
                        Text("Best value")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(15)
            .background(
                isSelected ? AnyShapeStyle(Theme.accentSoft) : AnyShapeStyle(Theme.surface),
                in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Zeigt nur „Weekly" bzw. „Yearly" – abgeleitet aus der Abo-Laufzeit.
    private var planLabel: String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayName }
        switch period.unit {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Yearly"
        @unknown default: return product.displayName
        }
    }
}
