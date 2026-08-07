//
//  PaywallView.swift
//  Clavic
//
//  Abo-Paywall im Web-Design (clavic.cc) — dunkles Immersive-Layout,
//  StoreKit-Preise & Credit-Anzeige aus der App.
//

import SwiftUI
import StoreKit

// MARK: - Web-Paywall-Palette

private enum PW {
    static let bg = Color(red: 0.039, green: 0.039, blue: 0.071)       // #0a0a12
    static let card = Color(red: 0.078, green: 0.078, blue: 0.122)    // #14141f
    static let cardDark = Color(red: 0.059, green: 0.059, blue: 0.086) // #0f0f16
    static let cardActive = Color(red: 0.11, green: 0.15, blue: 0.25) // #1c2640
    static let cardCTATop = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let cardCTABottom = Color(red: 0.071, green: 0.071, blue: 0.11)
    static let tipBg = Color(red: 0.11, green: 0.11, blue: 0.16)
    static let text = Color.white
    static let textSec = Color.white.opacity(0.70)
    static let textTer = Color.white.opacity(0.45)
    static let textQuat = Color.white.opacity(0.35)
    static let stroke = Color.white.opacity(0.20)
    static let accent = Color(red: 0.16, green: 0.50, blue: 1.0)
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    @State private var selected: Product?
    @State private var isPurchasing = false
    @State private var infoMessage: String?
    @State private var appeared = false

    private let valueProps = [
        "One upload, endless AI looks",
        "Turn one selfie into hundreds of unique styles",
    ]

    private let showcase: [(label: String, asset: String)] = [
        ("Rolex", "sc_watch_after"),
        ("Lamborghini", "sc_garage_after"),
        ("Luxury Car", "preview_luxury_car_selfie"),
        ("Action Figure", "preview_action_figure"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                PW.bg.ignoresSafeArea()

                GeometryReader { geo in
                    let horizontalPadding: CGFloat = 16
                    let contentWidth = min(geo.size.width - horizontalPadding * 2, 448)
                    let marqueeCardW = min(88, contentWidth * 0.22)
                    let marqueeCardH = marqueeCardW * 1.4

                    ZStack {
                        paywallBackground(
                            width: geo.size.width,
                            cardWidth: marqueeCardW,
                            cardHeight: marqueeCardH
                        )

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                heroCard(contentWidth: contentWidth)
                                valuePropsBlock
                                templateShowcase
                                beforeAfterBlock(contentWidth: contentWidth)
                                socialProof
                                secondPlanBlock
                                creditPackBlock
                                legalCard
                                faqBlock
                                footerLinks
                            }
                            .frame(maxWidth: contentWidth)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, max(28, geo.safeAreaInsets.bottom + 12))
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PW.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PW.textSec)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        Task {
                            await store.restore()
                            infoMessage = store.isPro
                                ? "Your subscription has been restored."
                                : "No active purchases found."
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PW.textSec)
                }
            }
        }
        .background(PW.bg.ignoresSafeArea())
        .presentationBackground(PW.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            preselect()
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            AppsFlyerEventTracker.trackPaywallView()
        }
        .onChange(of: store.subscriptions.count) { _, _ in
            preselect()
        }
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

    // MARK: - Hintergrund

    private func paywallBackground(width: CGFloat, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 10) {
                MarqueeRow(examples: OnboardingExamples.rowA, cardWidth: cardWidth, cardHeight: cardHeight, speed: 22)
                MarqueeRow(examples: OnboardingExamples.rowB, cardWidth: cardWidth, cardHeight: cardHeight, speed: 28, reversed: true)
            }
            .frame(width: width)
            .padding(.top, 56)
            .mask(
                LinearGradient(
                    colors: [.black, .black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(0.75)

            LinearGradient(
                colors: [.clear, PW.bg.opacity(0.6), PW.bg],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )

            RadialGradient(
                colors: [PW.accent.opacity(0.14), .clear],
                center: .init(x: 0.0, y: 0.35),
                startRadius: 0,
                endRadius: min(320, width * 0.85)
            )
            RadialGradient(
                colors: [Color(red: 0.55, green: 0.38, blue: 1).opacity(0.10), .clear],
                center: .init(x: 1.0, y: 0.4),
                startRadius: 0,
                endRadius: min(300, width * 0.8)
            )
        }
        .frame(width: width)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Hero

    private func heroCard(contentWidth: CGFloat) -> some View {
        let titleSize = min(28, contentWidth * 0.072)
        return VStack(spacing: 0) {
            Text("Clavic Pro")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brandGradient)
                .padding(.bottom, 10)

            (Text("Your ").foregroundStyle(PW.text)
             + Text("AI studio").foregroundStyle(Theme.accent)
             + Text(" in your pocket").foregroundStyle(PW.text))
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            planPicker
                .padding(.top, 22)

            subscribeButton
                .padding(.top, 18)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [PW.cardCTATop, PW.cardCTABottom],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(PW.accent.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 20, y: 10)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private var valuePropsBlock: some View {
        VStack(spacing: 10) {
            Text("All your AI tools\nin one subscription")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(PW.text)
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            ForEach(valueProps, id: \.self) { line in
                Text(line)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PW.textSec)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var templateShowcase: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(showcase, id: \.asset) { item in
                VStack(spacing: 8) {
                    showcaseTile(asset: item.asset)
                    Text(item.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.top, 22)
    }

    private func showcaseTile(asset: String) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(PW.card)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let img = UIImage(named: asset) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(PW.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
    }

    private func beforeAfterBlock(contentWidth: CGFloat) -> some View {
        Group {
            if let b = UIImage(named: "sc_garage_before"), let a = UIImage(named: "sc_garage_after") {
                let height = min(300, contentWidth * 0.72)
                BeforeAfterSlider(before: b, after: a, showLabels: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(PW.stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                    .padding(.top, 22)
            }
        }
    }

    private var socialProof: some View {
        VStack(spacing: 8) {
            Text("🤩 50,000+")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(PW.text)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text("Users already created photos today")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PW.textTer)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    private var secondPlanBlock: some View {
        VStack(spacing: 12) {
            Text("Choose your plan")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(PW.text)
                .padding(.top, 16)

            HStack(alignment: .top, spacing: 10) {
                Text("💡")
                Text("People on the yearly plan save more and get the best results — fresh credits all year without thinking about it.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PW.tipBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(red: 1, green: 0.78, blue: 0.31).opacity(0.35), lineWidth: 1)
            )

            VStack(spacing: 0) {
                planPicker
                    .padding(16)
                subscribeButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [PW.cardCTATop, PW.cardCTABottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(PW.accent.opacity(0.35), lineWidth: 1)
            )
        }
    }

    // MARK: - Pläne (StoreKit)

    private var planPicker: some View {
        Group {
            if store.isLoadingProducts && store.subscriptions.isEmpty {
                ProgressView().tint(.white).padding(20)
            } else if store.subscriptions.isEmpty {
                VStack(spacing: 10) {
                    Text("Plans couldn't load.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PW.textSec)
                    Button("Try again") { Task { await store.reload(); preselect() } }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PW.accent)
                }
                .padding(16)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.subscriptions, id: \.id) { product in
                        PaywallPlanCard(
                            product: product,
                            weeklyProduct: store.products.first { $0.id == StoreIDs.weekly },
                            isSelected: selected?.id == product.id
                        ) {
                            withAnimation(.spring(duration: 0.25)) { selected = product }
                        }
                    }
                }
            }
        }
    }

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            Button {
                guard let product = selected else { return }
                Task { await buy(product) }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Subscribe & continue")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: PW.accent.opacity(0.45), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(selected == nil || isPurchasing)

            Text("Cancel anytime in App Store settings")
                .font(.system(size: 11))
                .foregroundStyle(PW.textTer)
        }
    }

    // MARK: - Credit-Packs

    private var creditPackBlock: some View {
        Group {
            if store.isPro, !store.creditPacks.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Need more credits?")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PW.text)
                        .padding(.top, 28)

                    HStack(spacing: 8) {
                        ForEach(store.creditPacks, id: \.id) { product in
                            Button { Task { await buy(product) } } label: {
                                PaywallCreditCard(product: product)
                            }
                            .buttonStyle(.plain)
                            .disabled(isPurchasing)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Text("Credits never expire. Top up anytime while your subscription is active.")
                        .font(.system(size: 11))
                        .foregroundStyle(PW.textQuat)
                }
            }
        }
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                Text("Selected plan: \(selected.displayPrice) billed every \(periodLabel(for: selected)).")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PW.textSec)
            }
            Text("Your subscription renews automatically. Cancel anytime in Settings → Apple ID → Subscriptions before your next billing date.")
                .font(.system(size: 11))
                .foregroundStyle(PW.textQuat)
            if let selected {
                Text("After your plan ends, Apple will charge \(selected.displayPrice) per \(periodLabel(for: selected)) until you cancel.")
                    .font(.system(size: 11))
                    .foregroundStyle(PW.textQuat)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PW.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(PW.stroke, lineWidth: 1)
        )
        .padding(.top, 22)
    }

    private var faqBlock: some View {
        VStack(spacing: 0) {
            Text("FAQ")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(PW.text)
                .padding(.top, 18)
            Text("Everything you need to know before subscribing")
                .font(.system(size: 12))
                .foregroundStyle(PW.textTer)
                .padding(.bottom, 8)

            PaywallFAQItem(
                question: "How do I activate my subscription?",
                answer: "After purchase, Sign in with Apple links your subscription automatically. Credits are added to your balance right away."
            )
            PaywallFAQItem(
                question: "How do I cancel?",
                answer: "Open iPhone Settings → your name → Subscriptions → Clavic → Cancel. You keep access until the end of your paid period."
            )
        }
        .padding(.horizontal, 4)
        .background(PW.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(PW.stroke, lineWidth: 1)
        )
        .padding(.top, 16)
    }

    private var footerLinks: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Link("Terms of Use", destination: LegalLinks.terms)
                Text("·").foregroundStyle(PW.textQuat)
                Link("Privacy Policy", destination: LegalLinks.privacy)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(PW.textTer)

            Text("Need help? Clavic.ai.app@gmail.com")
                .font(.system(size: 10.5))
                .foregroundStyle(PW.textQuat)

            Text("© 2026 Clavic")
                .font(.system(size: 10.5))
                .foregroundStyle(PW.textQuat)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Aktionen

    private func preselect() {
        #if DEBUG
        if let screenshotPlan = ProcessInfo.processInfo.environment["UITEST_PAYWALL_PLAN"] {
            let requestedID = screenshotPlan == "weekly" ? StoreIDs.weekly : StoreIDs.yearly
            if let requested = store.subscriptions.first(where: { $0.id == requestedID }) {
                selected = requested
                return
            }
        }
        #endif
        if selected == nil || !store.subscriptions.contains(where: { $0.id == selected?.id }) {
            selected = store.subscriptions.first(where: { $0.id == StoreIDs.yearly })
                ?? store.subscriptions.first
        }
    }

    private func periodLabel(for product: Product) -> String {
        switch product.id {
        case StoreIDs.weekly: return "week"
        case StoreIDs.yearly: return "year"
        default:
            guard let p = product.subscription?.subscriptionPeriod else { return "period" }
            switch p.unit {
            case .week: return "week"
            case .year: return "year"
            case .month: return "month"
            default: return "period"
            }
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
        } catch StoreError.subscriptionRequired {
            infoMessage = "Subscribe first to purchase credit packs."
        } catch {
            infoMessage = "Purchase failed. Please try again."
        }
    }
}

// MARK: - Plan-Karte (Web-Stil)

private struct PaywallPlanCard: View {
    let product: Product
    let weeklyProduct: Product?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(planTitle)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .textCase(.uppercase)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if let compare = compareAtPrice {
                            Text(compare)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PW.textTer)
                                .strikethrough()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        Text(product.displayPrice)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(PW.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("/\(pricePeriod)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PW.textSec)
                    }

                    if let creditsLine {
                        Text(creditsLine)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PW.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

                if product.id == StoreIDs.yearly {
                    Text("🔥 POPULAR")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(PW.accent, in: UnevenRoundedRectangle(
                            topLeadingRadius: 0, bottomLeadingRadius: 12,
                            bottomTrailingRadius: 0, topTrailingRadius: 16, style: .continuous
                        ))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? PW.cardActive : PW.cardDark,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? PW.accent.opacity(0.8) : PW.stroke,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? PW.accent.opacity(0.15) : .clear,
                radius: 12, y: 4
            )
        }
        .buttonStyle(.plain)
    }

    private var planTitle: String {
        product.id == StoreIDs.yearly ? "1-Year" : "1-Week"
    }

    private var pricePeriod: String {
        product.id == StoreIDs.yearly ? "year" : "week"
    }

    private var creditsLine: String? {
        guard let n = StoreIDs.subscriptionCredits[product.id] else { return nil }
        let per = product.id == StoreIDs.yearly ? "year" : "week"
        return "\(n) credits / \(per)"
    }

    private var compareAtPrice: String? {
        // Nur echter Jahres-Vergleich (52× Weekly) — kein fiktiver „50%-Rabatt“ beim Weekly-Plan.
        guard product.id == StoreIDs.yearly, let weekly = weeklyProduct else { return nil }
        let anchor = weekly.price * 52
        return anchor.formatted(product.priceFormatStyle)
    }
}

// MARK: - Credit-Karte

private struct PaywallCreditCard: View {
    let product: Product

    private var credits: Int { StoreIDs.creditPacks[product.id] ?? 0 }
    private var highlight: Bool { product.id == StoreIDs.credits75 }

    var body: some View {
        VStack(spacing: 4) {
            if let badge = packBadge {
                Text(badge)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(PW.accent, in: Capsule())
            } else {
                Color.clear.frame(height: 18)
            }

            Text("\(credits)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(highlight ? PW.accent : PW.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("credits")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PW.textTer)

            Text(product.displayPrice)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PW.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(highlight ? PW.cardActive : PW.cardDark, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(highlight ? PW.accent : PW.stroke, lineWidth: highlight ? 2 : 1)
        )
    }

    private var packBadge: String? {
        switch product.id {
        case StoreIDs.credits30: return "POPULAR"
        case StoreIDs.credits75: return "BEST VALUE"
        default: return nil
        }
    }
}

// MARK: - FAQ

private struct PaywallFAQItem: View {
    let question: String
    let answer: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack {
                    Text(question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Text(open ? "−" : "+")
                        .font(.system(size: 18))
                        .foregroundStyle(PW.textTer)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            if open {
                Text(answer)
                    .font(.system(size: 13))
                    .foregroundStyle(PW.textTer)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            Divider().background(Color.white.opacity(0.1))
        }
    }
}
