//
//  OnboardingView.swift
//  Clavic
//
//  Willkommens-Flow beim ersten Start:
//   • Hero-Screen mit automatisch laufender Beispiel-Galerie (Before/After
//     + Trend-Videos) und einem Text passend zur App.
//   • Anschließend ein kurzes, generisches Tutorial in 3 Schritten, das zu
//     jedem aktuellen und künftigen Werkzeug passt.
//

import SwiftUI

// MARK: - Beispiel-Galerie

/// Eine animierte Vorschau für die Galerie: entweder ein Before/After-Slider
/// oder ein loopendes Trend-Video.
enum OnboardingExample: Identifiable, Hashable {
    case slider(before: String, after: String)
    case video(String)

    var id: String {
        switch self {
        case let .slider(before, after): return "s-\(before)-\(after)"
        case let .video(name): return "v-\(name)"
        }
    }
}

enum OnboardingExamples {
    /// Reihenfolge so gewählt, dass die Galerie abwechslungsreich wirkt.
    static let all: [OnboardingExample] = [
        .slider(before: "preview_glowup_swap_before", after: "preview_glowup_swap_after"),
        .video("preview_lego"),
        .slider(before: "preview_image_upscale_before", after: "preview_image_upscale_after"),
        .slider(before: "preview_video_upscale_before", after: "preview_video_upscale_after")
    ]

    static let rowA: [OnboardingExample] = all
    static let rowB: [OnboardingExample] = Array(all.reversed())
}

/// Rendert eine einzelne animierte Beispiel-Karte.
struct ExampleCardView: View {
    let example: OnboardingExample
    var corner: CGFloat = 20

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
    }

    @ViewBuilder
    private var content: some View {
        switch example {
        case let .slider(before, after):
            if let b = UIImage(named: before), let a = UIImage(named: after) {
                BeforeAfterSlider(before: b, after: a, showLabels: false)
            } else {
                Theme.surfaceHigh
            }
        case let .video(name):
            if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                LoopingVideoView(url: url)
            } else {
                Theme.surfaceHigh
            }
        }
    }
}

/// Endlos laufende, nicht interaktive Reihe von Beispiel-Karten (Marquee).
struct MarqueeRow: View {
    let examples: [OnboardingExample]
    var cardWidth: CGFloat = 132
    var cardHeight: CGFloat = 188
    var spacing: CGFloat = 14
    var speed: CGFloat = 24
    var reversed: Bool = false

    var body: some View {
        let unit = cardWidth + spacing
        let setWidth = unit * CGFloat(max(examples.count, 1))
        // Dauer für genau einen kompletten Durchlauf. Die Phase wird aus
        // (t mod period) berechnet – dadurch bleiben die Zahlen klein und der
        // Umbruch ist exakt periodisch (kein Ruckeln durch Float-Ungenauigkeit).
        let period = Double(setWidth) / Double(max(speed, 1))

        GeometryReader { geo in
            // Genug Wiederholungen, damit der sichtbare Bereich auch direkt am
            // Loop-Übergang immer lückenlos gefüllt ist (nichts „buggt weg").
            let copies = max(2, Int((geo.size.width / setWidth).rounded(.up)) + 2)

            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(t.truncatingRemainder(dividingBy: period) / period) * setWidth
                let offsetX = reversed ? phase - setWidth : -phase

                HStack(spacing: spacing) {
                    ForEach(0..<copies, id: \.self) { rep in
                        ForEach(Array(examples.enumerated()), id: \.offset) { idx, example in
                            ExampleCardView(example: example)
                                .frame(width: cardWidth, height: cardHeight)
                                .id("\(rep)-\(idx)")
                        }
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .offset(x: offsetX)
            }
        }
        .frame(height: cardHeight)
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Binding var isPresented: Bool

    /// 0 = Hero, 1...n = Tutorial-Schritte
    @State private var page = 0

    private struct Step {
        let caption: String
        let title: String
        let subtitle: String
        let example: OnboardingExample
    }

    private let steps: [Step] = [
        Step(
            caption: "Pick a tool",
            title: "Jump into a viral trend",
            subtitle: "Choose a trend, a glow-up edit or an upscaler. New tools drop all the time – there's always something fresh to try.",
            example: .video("preview_lego")
        ),
        Step(
            caption: "Add your media",
            title: "Drop in your photo or clip",
            subtitle: "Upload a photo or video and pick your look. No prompt skills needed – just tap and go.",
            example: .slider(before: "preview_glowup_swap_before", after: "preview_glowup_swap_after")
        ),
        Step(
            caption: "Tap generate",
            title: "Watch it transform",
            subtitle: "Our AI does the work and drops a share-ready result straight into your Library.",
            example: .slider(before: "preview_image_upscale_before", after: "preview_image_upscale_after")
        )
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if page == 0 {
                hero
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                tutorial
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Hero

    private var hero: some View {
        GeometryReader { geo in
            let cardH = min(180, geo.size.height * 0.21)
            let cardW = cardH * 0.72
            let titleSize = min(34, geo.size.width * 0.085)

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                VStack(spacing: 12) {
                    MarqueeRow(examples: OnboardingExamples.rowA, cardWidth: cardW, cardHeight: cardH, speed: 22)
                    MarqueeRow(examples: OnboardingExamples.rowB, cardWidth: cardW, cardHeight: cardH, speed: 28, reversed: true)
                }
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                Spacer(minLength: 16)

                VStack(spacing: 12) {
                    Text("Create viral AI\nvideos & photo edits")
                        .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .minimumScaleFactor(0.7)

                    Text("Swap your look, jump into trends and upscale your media – all from a single photo.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 28)
                }
                .padding(.horizontal, 8)

                Spacer(minLength: 16)

                Button {
                    withAnimation(.spring(duration: 0.4)) { page = 1 }
                } label: {
                    Text("Get started")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.screenPadding)

                Text("By continuing, you accept our Terms of Service and Privacy Policy.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Tutorial

    private var tutorial: some View {
        let step = steps[min(page - 1, steps.count - 1)]
        return GeometryReader { geo in
            let cardH = min(380, geo.size.height * 0.44)

            VStack(spacing: 0) {
                topNav
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 6)

                Spacer(minLength: 8)

                ZStack(alignment: .bottom) {
                    ExampleCardView(example: step.example, corner: 26)
                        .frame(maxWidth: .infinity)
                        .frame(height: cardH)
                        .padding(.horizontal, 36)

                    Text(step.caption)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 22)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .offset(y: 18)
                }

                Spacer(minLength: 16)

                VStack(spacing: 10) {
                    Text(step.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    Text(step.subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: 14)

                pageDots
                    .padding(.bottom, 14)

                Button {
                    advance()
                } label: {
                    Text(page >= steps.count ? "Continue" : "Next")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 20)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var topNav: some View {
        HStack {
            navArrow(system: "chevron.left") {
                withAnimation(.spring(duration: 0.35)) { page -= 1 }
            }
            Spacer()
            if page < steps.count {
                navArrow(system: "chevron.right") {
                    withAnimation(.spring(duration: 0.35)) { page += 1 }
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }

    private func navArrow(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(1...steps.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.accent : Theme.surfaceHigh)
                    .frame(width: index == page ? 24 : 8, height: 8)
                    .animation(.spring(duration: 0.3), value: page)
            }
        }
    }

    private func advance() {
        if page >= steps.count {
            withAnimation { isPresented = false }
        } else {
            withAnimation(.spring(duration: 0.4)) { page += 1 }
        }
    }
}
