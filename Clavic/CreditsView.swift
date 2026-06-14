//
//  CreditsView.swift
//  Clavic
//
//  Reiner Credit-Kauf (keine Abos / Abo-Texte). Wird geöffnet, wenn der
//  Nutzer Guthaben aufladen will. Oben ein visueller Hero-Banner mit dem
//  aktuellen Guthaben, darunter die Credit-Packs zur Auswahl.
//

import SwiftUI
import StoreKit

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    @State private var isPurchasing = false
    @State private var selectedID: String?
    @State private var infoMessage: String?

    private var selectedProduct: Product? {
        store.creditPacks.first { $0.id == selectedID } ?? store.creditPacks.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        hero
                        packs
                        buyButton
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
                            infoMessage = store.isPro
                                ? "Your subscription has been restored."
                                : "Nothing to restore. Credit packs are one-time purchases."
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: preselect)
        .onChange(of: store.creditPacks.count) { _, _ in preselect() }
        .alert(infoMessage ?? "", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.brandGradient)

                // dezente dekorative Kreise
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 150, height: 150)
                    .offset(x: 120, y: -54)
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 90, height: 90)
                    .offset(x: -130, y: 56)

                VStack(spacing: 6) {
                    Image("credit_coin")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 66, height: 66)
                    Text("\(store.credits)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(store.credits == 1 ? "credit available" : "credits available")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.vertical, 28)
            }
            .frame(maxWidth: .infinity)
            .shadow(color: Theme.accent.opacity(0.3), radius: 16, y: 8)

            VStack(spacing: 5) {
                Text("Top up your credits")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Spend credits on any tool. Images cost less than videos. Added instantly, never expire.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            costLegend
        }
    }

    private var costLegend: some View {
        HStack(spacing: 0) {
            legendItem(icon: "play.rectangle.fill", title: "Video", detail: "from \(CreditCosts.video(seconds: 3, hasReferenceVideo: false))")
            legendDivider
            legendItem(icon: "arrow.up.forward.app.fill", title: "Upscale", detail: "\(CreditCosts.imageUpscale)–\(CreditCosts.videoUpscale)")
            legendDivider
            legendItem(icon: "wand.and.stars", title: "Image", detail: "\(CreditCosts.imageEdit)")
        }
        .padding(.vertical, 12)
        .cardStyle()
    }

    private func legendItem(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("\(detail) cr")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private var legendDivider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1, height: 34)
    }

    // MARK: - Packs

    private var packs: some View {
        Group {
            if !store.creditPacks.isEmpty {
                VStack(spacing: 12) {
                    ForEach(store.creditPacks, id: \.id) { product in
                        packRow(product)
                    }
                }
            } else if store.isLoadingProducts {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading packs …")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .cardStyle()
            } else {
                VStack(spacing: 10) {
                    Text("Packs couldn't load.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Try again") { Task { await store.reload() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .cardStyle()
            }
        }
    }

    private func packRow(_ product: Product) -> some View {
        let credits = StoreIDs.creditPacks[product.id] ?? 0
        let selected = selectedProduct?.id == product.id
        let badge = packBadge(for: product.id)
        let videos = credits / CreditCosts.representativeVideo
        let images = credits / CreditCosts.imageEdit

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedID = product.id
            }
        } label: {
            HStack(spacing: 14) {
                Image("credit_coin")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("\(credits) credits")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 7)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    Text("up to \(videos) videos or \(images) image edits")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 8)

                Text(product.displayPrice)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(16)
            .background(
                selected ? AnyShapeStyle(Theme.accentSoft) : AnyShapeStyle(Theme.surface),
                in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    private var buyButton: some View {
        Group {
            if let product = selectedProduct {
                let credits = StoreIDs.creditPacks[product.id] ?? 0
                Button {
                    Task { await buy(product) }
                } label: {
                    HStack(spacing: 8) {
                        if isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Get \(credits) credits · \(product.displayPrice)")
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !isPurchasing))
                .disabled(isPurchasing)
            }
        }
    }

    private func packBadge(for id: String) -> String? {
        switch id {
        case StoreIDs.credits30: return "POPULAR"
        case StoreIDs.credits75: return "BEST VALUE"
        default: return nil
        }
    }

    private var footer: some View {
        Text("One-time purchase charged to your App Store account. Credits never expire.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }

    // MARK: - Kauf

    private func preselect() {
        if selectedID == nil || !store.creditPacks.contains(where: { $0.id == selectedID }) {
            selectedID = store.creditPacks.first(where: { $0.id == StoreIDs.credits75 })?.id
                ?? store.creditPacks.first?.id
        }
    }

    private func buy(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let success = try await store.purchase(product)
            if success {
                let amount = StoreIDs.creditPacks[product.id] ?? 0
                infoMessage = "\(amount) credits have been added."
            }
        } catch {
            infoMessage = "Purchase failed. Please try again."
        }
    }
}
