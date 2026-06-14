//
//  PaywallView.swift
//  Clavic
//
//  Abo-Paywall (Clavic Pro) + optionale Credit-Packs.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    @State private var selected: Product?
    @State private var isPurchasing = false
    @State private var infoMessage: String?

    private let features: [(String, String)] = [
        ("drop.fill", "Credits included – topped up automatically"),
        ("sparkles", "All viral trend templates"),
        ("bolt.fill", "Faster queue"),
        ("wand.and.stars", "No watermark")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 26) {
                        header
                        featureList
                        planSection
                        purchaseButton
                        creditPackSection
                        footer
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        Task {
                            await store.restore()
                            if store.isPro {
                                infoMessage = "Your subscription has been restored."
                            } else {
                                infoMessage = "No active purchases found."
                            }
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear { preselect() }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
        .alert(infoMessage ?? "", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 6)

            Text("Create without limits")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Unlock every tool, keep your credits topped up and export without a watermark.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: 14) {
            ForEach(features, id: \.1) { icon, text in
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 26)
                    Text(text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.success)
                }
            }
        }
        .padding(18)
        .cardStyle()
    }

    // MARK: - Pläne

    private var planSection: some View {
        Group {
            if store.subscriptions.isEmpty {
                if store.isLoadingProducts {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading prices …")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .cardStyle()
                } else {
                    VStack(spacing: 10) {
                        Text("Plans couldn't load.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Button("Try again") {
                            Task { await store.reload() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .cardStyle()
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(store.subscriptions, id: \.id) { product in
                        PlanCard(
                            product: product,
                            isSelected: selected?.id == product.id,
                            isBestValue: product.id == StoreIDs.yearly
                        ) { selected = product }
                    }
                }
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            guard let product = selected else { return }
            Task { await buy(product) }
        } label: {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(purchaseTitle)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: selected != nil && !isPurchasing))
        .disabled(selected == nil || isPurchasing)
    }

    private var purchaseTitle: String {
        guard let selected else { return "Choose a plan" }
        if let offer = selected.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return "Try free, then \(selected.displayPrice)"
        }
        return "Start now – \(selected.displayPrice)"
    }

    // MARK: - Credit-Packs

    private var creditPackSection: some View {
        Group {
            if !store.creditPacks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Prefer a one-time top-up? Add credits")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 12) {
                        ForEach(store.creditPacks, id: \.id) { product in
                            Button {
                                Task { await buy(product) }
                            } label: {
                                creditPackCard(product)
                            }
                            .buttonStyle(.plain)
                            .disabled(isPurchasing)
                        }
                    }
                    Text("1 Credit = 1 video. Credits never expire.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func creditPackCard(_ product: Product) -> some View {
        let credits = StoreIDs.creditPacks[product.id] ?? 0
        let badge = packBadge(for: product.id)
        let highlight = product.id == StoreIDs.credits75
        let perVideo = credits > 0
            ? (product.price / Decimal(credits)).formatted(product.priceFormatStyle)
            : ""
        return VStack(spacing: 5) {
            ZStack {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .background(Theme.accent, in: Capsule())
                }
            }
            .frame(height: 18)

            Text("\(credits)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? Theme.accent : Theme.textPrimary)
            Text(credits == 1 ? "credit" : "credits")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Text(product.displayPrice)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 4)
            if !perVideo.isEmpty {
                Text("\(perVideo) / video")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            highlight ? AnyShapeStyle(Theme.accentSoft) : AnyShapeStyle(Theme.surface),
            in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .strokeBorder(highlight ? Theme.accent : Theme.stroke, lineWidth: highlight ? 2 : 1)
        )
    }

    private func packBadge(for id: String) -> String? {
        switch id {
        case StoreIDs.credits30: return "POPULAR"
        case StoreIDs.credits75: return "BEST VALUE"
        default: return nil
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Payment is charged to your App Store account. The subscription renews automatically unless cancelled at least 24 h before the end of the period. Cancel anytime in your App Store settings.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    // MARK: - Aktionen

    private func preselect() {
        if selected == nil {
            selected = store.subscriptions.first(where: { $0.id == StoreIDs.yearly })
                ?? store.subscriptions.first
        }
    }

    private func buy(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let success = try await store.purchase(product)
            if success {
                if store.isPro {
                    dismiss()
                } else {
                    infoMessage = "Credits have been added."
                }
            }
        } catch {
            infoMessage = "Purchase failed. Please try again."
        }
    }
}

// MARK: - Plan-Karte

private struct PlanCard: View {
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
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Theme.accent).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        if isBestValue {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 7)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    if let desc = creditText {
                        Text(desc)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(16)
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

    /// e.g. "10 Credits per week"
    private var creditText: String? {
        guard let credits = StoreIDs.subscriptionCredits[product.id] else { return nil }
        let period = product.subscription.map { periodText($0.subscriptionPeriod) } ?? ""
        return "\(credits) Credits \(period)"
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        let n = period.value
        switch period.unit {
        case .day: return n == 1 ? "per day" : "every \(n) days"
        case .week: return n == 1 ? "per week" : "every \(n) weeks"
        case .month: return n == 1 ? "per month" : "every \(n) months"
        case .year: return n == 1 ? "per year" : "every \(n) years"
        @unknown default: return ""
        }
    }
}
