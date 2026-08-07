//
//  HardPaywallView.swift
//  Clavic
//
//  Legacy full-screen subscription view. No longer used as a blocking gate —
//  see ContentView (dismissible PaywallView sheet). Kept for reference.
//

import SwiftUI
import StoreKit

/// Palette der dunklen, immersiven Paywall (hebt sie klar vom hellen App-UI ab,
/// damit sie nicht „wie ein Dokument" wirkt, sondern hochwertig/premium).
private enum PW {
    static let bgTop = Color(red: 0.11, green: 0.10, blue: 0.17)
    static let bgMid = Color(red: 0.07, green: 0.06, blue: 0.11)
    static let bgBottom = Color(red: 0.03, green: 0.03, blue: 0.06)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let text = Color.white
    static let textSec = Color.white.opacity(0.64)
    static let textTer = Color.white.opacity(0.40)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.30)
}

struct HardPaywallView: View {
    @Environment(Store.self) private var store

    @State private var selected: Product?
    @State private var isPurchasing = false
    @State private var infoMessage: String?
    /// Sanfte Einblend-Animation beim Erscheinen.
    @State private var appeared = false

    private let benefits: [(String, String)] = [
        ("sparkles", "Every trend, dance & fan cam"),
        ("infinity", "Credits topped up automatically"),
        ("wand.and.stars", "Realistic AI photos & glow-ups"),
        ("checkmark.seal.fill", "No watermark — post anywhere")
    ]

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let isSmall = h < 740
            let showVisual = !isSmall
            let gap: CGFloat = isSmall ? 10 : 16
            let titleSize: CGFloat = isSmall ? 23 : 28
            let visualH = min(h * 0.2, 172)
            // Inhaltsspalte auf dem iPad/Querformat begrenzen, damit nichts
            // über die volle Breite gestreckt wirkt; wird zentriert dargestellt.
            let contentW = min(geo.size.width - Theme.screenPadding * 2, 460)

            VStack(spacing: 0) {
                if showVisual {
                    visual(height: visualH, width: contentW)
                }

                Spacer(minLength: gap)
                titleBlock(titleSize: titleSize, isSmall: isSmall)

                Spacer(minLength: gap)
                benefitList(isSmall: isSmall)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

                Spacer(minLength: gap)
                planSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

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
        .background {
            ZStack {
                LinearGradient(colors: [PW.bgTop, PW.bgMid, PW.bgBottom],
                               startPoint: .top, endPoint: .bottom)
                // Weiche Brand-Glows oben für Tiefe.
                RadialGradient(colors: [Theme.accent.opacity(0.45), .clear],
                               center: .init(x: 0.18, y: 0.02), startRadius: 0, endRadius: 360)
                    .blendMode(.screen)
                RadialGradient(colors: [Color(red: 0.55, green: 0.38, blue: 1).opacity(0.40), .clear],
                               center: .init(x: 0.9, y: 0.12), startRadius: 0, endRadius: 320)
                    .blendMode(.screen)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            preselect()
            withAnimation(.spring(duration: 0.7).delay(0.1)) { appeared = true }
            AppsFlyerEventTracker.trackPaywallView()
            AdTracking.requestAuthorizationIfAppropriate()
        }
        .onChange(of: store.subscriptions.count) { _, _ in preselect() }
        .alert(infoMessage ?? "", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }


    // MARK: - Visual

    private func visual(height: CGFloat, width: CGFloat) -> some View {
        let rowH = (height - 8) / 2
        return VStack(spacing: 8) {
            MarqueeRow(examples: OnboardingExamples.rowA, cardWidth: rowH * 0.72, cardHeight: rowH, speed: 19)
            MarqueeRow(examples: OnboardingExamples.rowB, cardWidth: rowH * 0.72, cardHeight: rowH, speed: 25, reversed: true)
        }
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
        VStack(spacing: isSmall ? 6 : 9) {
            (Text("Unlock the ").foregroundStyle(PW.text)
             + Text("full studio").foregroundStyle(Theme.accent))
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text("Every trend, dance and realistic AI edit — credits refill automatically.")
                .font(.system(size: isSmall ? 13.5 : 15))
                .foregroundStyle(PW.textSec)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
        }
    }

    private func benefitList(isSmall: Bool) -> some View {
        let items = isSmall ? Array(benefits.prefix(3)) : benefits
        return VStack(spacing: isSmall ? 11 : 14) {
            ForEach(items, id: \.1) { icon, text in
                HStack(spacing: 13) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.18)).frame(width: 30, height: 30)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(text)
                        .font(.system(size: isSmall ? 14 : 15, weight: .medium))
                        .foregroundStyle(PW.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                }
            }
        }
        .padding(isSmall ? 15 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PW.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(PW.cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Pläne

    private var planSection: some View {
        Group {
            if !store.mainSubscriptions.isEmpty {
                VStack(spacing: 11) {
                    ForEach(store.mainSubscriptions, id: \.id) { product in
                        HardPlanCard(
                            product: product,
                            isSelected: selected?.id == product.id,
                            isBestValue: product.id == StoreIDs.yearly,
                            savingsPercent: savings(for: product)
                        ) { withAnimation(.spring(duration: 0.25)) { selected = product } }
                    }
                }
            } else if store.isLoadingProducts {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Loading plans …")
                        .font(.system(size: 13))
                        .foregroundStyle(PW.textTer)
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .background(PW.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Text("Plans couldn't load.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PW.textSec)
                    Button("Try again") {
                        Task { await store.reload(); preselect() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(PW.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
            }
        }
    }

    /// Ersparnis (%) vs. Wochen-Abo aufs Jahr gerechnet – nur fürs Jahres-Abo.
    private func savings(for product: Product) -> Int? {
        guard product.id == StoreIDs.yearly,
              let weekly = store.products.first(where: { $0.id == StoreIDs.weekly }) else { return nil }
        let yearAtWeekly = weekly.price * 52
        guard yearAtWeekly > 0 else { return nil }
        let fraction = (yearAtWeekly - product.price) / yearAtWeekly * 100
        // Über doubleValue runden: NSDecimalNumber.intValue liefert bei Decimals
        // mit sehr langer Nachkommastelle fälschlich 0.
        let pct = Int(NSDecimalNumber(decimal: fraction).doubleValue)
        return pct > 0 ? pct : nil
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
                .foregroundStyle(PW.textSec)
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
            .foregroundStyle(PW.textSec)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Auto-renews until cancelled. Manage anytime in your App Store settings.")
                .font(.system(size: 10.5))
                .foregroundStyle(PW.textTer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Link("Terms of Use", destination: LegalLinks.terms)
                Text("·").foregroundStyle(PW.textTer)
                Link("Privacy Policy", destination: LegalLinks.privacy)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(PW.textSec)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Texte

    private var ctaTitle: String {
        selected == nil ? "Choose a plan" : "Subscribe & continue"
    }

    private var ctaSubtitle: String {
        guard let selected else { return "Cancel anytime." }
        return "\(selected.displayPrice), renews automatically. Cancel anytime."
    }

    // MARK: - Aktionen

    private func preselect() {
        if selected == nil || !store.mainSubscriptions.contains(where: { $0.id == selected?.id }) {
            selected = store.mainSubscriptions.first(where: { $0.id == StoreIDs.yearly })
                ?? store.mainSubscriptions.first
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
    var savingsPercent: Int? = nil
    let action: () -> Void

    private var corner: CGFloat { 18 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                // Radio
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.25), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle().fill(Theme.brandGradient).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(planLabel)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(PW.text)
                    if let creditsText {
                        Text(creditsText)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(PW.text)
                    if let perWeek {
                        Text(perWeek)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PW.textTer)
                    }
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .background(
                isSelected ? AnyShapeStyle(Theme.accent.opacity(0.16)) : AnyShapeStyle(PW.card),
                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(PW.cardStroke),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? Theme.accent.opacity(0.35) : .clear, radius: 14, y: 6)
            .overlay(alignment: .topTrailing) {
                if isBestValue || savingsPercent != nil {
                    Text(savingsPercent.map { "\($0)% off vs weekly" } ?? "Best value")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 9)
                        .background(Theme.brandGradient, in: Capsule())
                        .offset(x: -10, y: -9)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 6, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Optionaler Pro-Woche-Preis (nur fürs Jahres-Abo, macht den Wert greifbar).
    private var perWeek: String? {
        guard product.id == StoreIDs.yearly else { return nil }
        let weekly = product.price / 52
        return weekly.formatted(product.priceFormatStyle) + " / week"
    }

    /// Wie viele Credits dieses Abo pro Zeitraum gutschreibt, z. B.
    /// „10 credits / week" bzw. „150 credits / year". Periode nach Produkt-ID,
    /// da StoreKit-Testing eine Woche teils als „7 Tage" meldet.
    private var creditsText: String? {
        guard let amount = StoreIDs.subscriptionCredits[product.id] else { return nil }
        let per: String
        switch product.id {
        case StoreIDs.weekly: per = "week"
        case StoreIDs.yearly: per = "year"
        default:
            switch product.subscription?.subscriptionPeriod.unit {
            case .some(.day): per = "day"
            case .some(.week): per = "week"
            case .some(.month): per = "month"
            case .some(.year): per = "year"
            default: per = "period"
            }
        }
        return "\(amount) credits / \(per)"
    }

    /// Plan-Name nach Produkt-ID (robust gegen StoreKit-Perioden-Eigenheiten).
    private var planLabel: String {
        switch product.id {
        case StoreIDs.weekly: return "Weekly"
        case StoreIDs.yearly: return "Yearly"
        default:
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
}
