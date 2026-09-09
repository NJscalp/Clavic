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
import AVFoundation

// MARK: - Beispiel-Galerie

/// Eine animierte Vorschau für die Galerie: entweder ein Before/After-Slider
/// oder ein loopendes Trend-Video.
enum OnboardingExample: Identifiable, Hashable {
    case slider(before: String, after: String)
    case video(String)
    /// Einzelnes Ergebnisbild. Gebraucht fuer die Beauty-/Look-Vorschauen —
    /// die liegen als fertige Ergebnisse vor, nicht als Vorher/Nachher-Paar.
    case image(String)

    var id: String {
        switch self {
        case let .slider(before, after): return "s-\(before)-\(after)"
        case let .video(name): return "v-\(name)"
        case let .image(name): return "i-\(name)"
        }
    }
}

enum OnboardingExamples {
    /// Drei Reihen mit jeweils unterschiedlichem Inhalt – so wirkt die Galerie
    /// abwechslungsreich (Trend-Videos + Before/After-Slider gemischt).
    // Jede Reihe zur HAELFTE Beauty/Transformation. Vorher war die Galerie
    // fast reiner Sport, Fancam und Luxus — maennlich besetzt, obwohl der
    // groesste Teil der zahlenden Nutzerinnen schlicht das eigene Foto
    // verbessern will. Wer hier nur Fussball und Garagen sieht, haelt Clavic
    // fuer eine Meme-App und ist weg, bevor die Paywall kommt.
    static let rowA: [OnboardingExample] = [
        .slider(before: "preview_pro_glow_before", after: "preview_pro_glow_after"),
        .image("preview_look_afterglow"),
        .slider(before: "preview_glowup_swap_before", after: "preview_glowup_swap_after"),
        .video("preview_music_video"),
        .slider(before: "sc_garage_before", after: "sc_garage_after"),
        .video("preview_nerv_backrooms")
    ]
    static let rowB: [OnboardingExample] = [
        .image("preview_look_photo_sunset"),
        .slider(before: "preview_8k_before", after: "preview_8k_after"),
        .image("preview_look_tropic_glow"),
        .slider(before: "sc_watch_before", after: "sc_watch_after"),
        .video("preview_football_fancam"),
        .slider(before: "preview_image_edit_before", after: "preview_image_edit_after")
    ]
    static let rowC: [OnboardingExample] = [
        .image("preview_look_vintage_beach"),
        .slider(before: "preview_image_upscale_before", after: "preview_image_upscale_after"),
        .image("preview_look_photo_set"),
        .image("preview_pinterest_swap"),
        .slider(before: "sc_pool_before", after: "sc_pool_after"),
        .video("preview_wc_argentina")
    ]
    /// Gesamter Pool (für Tutorial-Schritte), abwechslungsreich sortiert.
    static let all: [OnboardingExample] = rowA + rowB + rowC
}

/// Rendert eine einzelne animierte Beispiel-Karte.
struct ExampleCardView: View {
    let example: OnboardingExample
    var corner: CGFloat = 20
    /// true = große Einzel-Karte (Tutorial/Sign-in) → Video spielt LIVE.
    /// false = Marquee mit vielen Karten → Standbild (sonst Dutzende Player → Ruckeln).
    var animated: Bool = false

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
        case let .image(name):
            if let ui = UIImage(named: name) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Theme.surfaceHigh
            }
        case let .video(name):
            if animated, let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                // Große Einzel-Karte (Tutorial/Sign-in): Video läuft LIVE.
                LoopingVideoView(url: url)
            } else if Bundle.main.url(forResource: name, withExtension: "mp4") != nil {
                // Marquee: LIVE-Video über GETEILTEM Player – ein Decoder pro
                // Datei, egal wie viele Karten-Kopien (sonst Dutzende Player →
                // Freeze). Das Poster liegt als Sofort-/Fallback-Hintergrund
                // darunter und bestimmt die Größe (Color-Container → Portrait-
                // Kartengröße, kein 16:9-Ausreißen).
                Theme.surfaceHigh
                    .overlay {
                        if let poster = UIImage(named: "\(name)_poster") {
                            Image(uiImage: poster).resizable().scaledToFill()
                        }
                    }
                    .overlay { SharedMarqueeVideoView(name: name) }
            } else {
                Theme.surfaceHigh
            }
        }
    }
}

/// Geteilte Loop-Player für die Marquee. Pro Videodatei wird EIN AVQueuePlayer
/// erzeugt und in ALLEN Karten-Kopien gleichzeitig angezeigt (ein AVPlayer darf
/// in mehreren AVPlayerLayern laufen). Dadurch laufen nur so viele Decoder wie
/// es UNIQUE Videos gibt (~13) statt pro Karte/Kopie (~39) → die Karten spielen
/// LIVE, ohne dass die UI einfriert.
@MainActor
enum MarqueePlayerPool {
    private static var players: [String: AVQueuePlayer] = [:]
    private static var loopers: [String: AVPlayerLooper] = [:]

    static func player(for name: String) -> AVQueuePlayer? {
        if let p = players[name] { return p }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return nil }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        loopers[name] = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        players[name] = player
        player.play()
        return player
    }
}

/// Zeigt einen geteilten Loop-Player (siehe `MarqueePlayerPool`) in einer
/// Marquee-Karte. resizeAspectFill → 16:9-Video wird in Portrait gecroppt.
struct SharedMarqueeVideoView: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> SharedPlayerUIView { SharedPlayerUIView(name: name) }
    func updateUIView(_ uiView: SharedPlayerUIView, context: Context) {}
}

final class SharedPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(name: String) {
        super.init(frame: .zero)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = MarqueePlayerPool.player(for: name)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // Beim Erscheinen sicherstellen, dass der geteilte Player läuft.
        if newWindow != nil { (playerLayer.player as? AVQueuePlayer)?.play() }
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

    /// Steuert die laufende Drift. false→true wird EINMAL per repeatForever
    /// animiert; SwiftUI interpoliert nur den Offset auf dem Render-Server –
    /// die Karten selbst werden NICHT pro Frame neu gebaut (kein Ruckeln/„stuck").
    @State private var rolling = false

    var body: some View {
        let unit = cardWidth + spacing
        let setWidth = unit * CGFloat(max(examples.count, 1))
        let period = Double(setWidth) / Double(max(speed, 1))
        // Start- und Zielposition für eine Richtung. Da sich der Inhalt alle
        // `setWidth` exakt wiederholt, ist der Rücksprung am Periodenende
        // unsichtbar → nahtlose Endlosschleife.
        let base: CGFloat = reversed ? -setWidth : 0
        let target: CGFloat = reversed ? setWidth : -setWidth

        // Overlay + Clip: `fixedSize` darf den Parent nicht über die Bildschirmbreite
        // hinaus aufweiten (sonst horizontaler Overflow in Paywall/Onboarding).
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .overlay(alignment: .leading) {
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { rep in
                        ForEach(Array(examples.enumerated()), id: \.offset) { idx, example in
                            ExampleCardView(example: example)
                                .frame(width: cardWidth, height: cardHeight)
                                .id("\(rep)-\(idx)")
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: base + (rolling ? target : 0))
            }
            .clipped()
            .allowsHitTesting(false)
        .onAppear {
            rolling = false
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                rolling = true
            }
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Binding var isPresented: Bool

    /// 0 = Hero, 1...n = Tutorial-Schritte
    @State private var page = 0
    /// Einblend-Animation des Hero-Texts beim ersten Erscheinen.
    @State private var heroIn = false
    /// Sanftes Pulsieren des Glühens hinter dem Haupt-Button.
    @State private var ctaPulse = false

    private struct Step {
        let caption: String
        let title: String
        let subtitle: String
        let example: OnboardingExample
    }

    private let steps: [Step] = [
        Step(
            caption: "Say what you want",
            title: "Talk to your photo",
            subtitle: "No templates. No filters. Just tell Clavic what you want — new hair, couple pics, dream outfit. Your photo, your rules.",
            example: .slider(before: "preview_pro_glow_before", after: "preview_pro_glow_after")
        ),
        Step(
            caption: "Step by step",
            title: "Hair first, then outfit, then scene",
            subtitle: "Change one thing at a time. Beach waves. Then the dress. Then put yourself on a real beach. You decide every step.",
            example: .slider(before: "preview_image_edit_before", after: "preview_image_edit_after")
        ),
        Step(
            caption: "Look like you",
            title: "Better, but still YOU",
            subtitle: "Clavic never changes your face or body unless you ask. No plastic skin. No auto-slim. Just you — looking your best.",
            example: .slider(before: "sc_watch_before", after: "sc_watch_after")
        )
    ]

    @State private var zeigeZiele = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if page == 0 {
                hero
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else if zeigeZiele {
                // Letzter Schritt vor der App: die eine Frage. Siehe
                // `OnboardingGoals.swift` fuer Herkunft und Begruendung.
                OnboardingZieleView(
                    schritt: steps.count + 1,
                    vonSchritten: steps.count + 1,
                    onZurueck: {
                        withAnimation(.spring(duration: 0.35)) { zeigeZiele = false }
                    },
                    onWeiter: { ziele in
                        UserDefaults.standard.set(
                            ziele.map(\.rawValue).joined(separator: ","),
                            forKey: OnboardingZiel.speicherSchluessel
                        )
                        schliessen()
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
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
            let cardH = min(150, geo.size.height * 0.168)
            let cardW = cardH * 0.72
            let titleSize = min(35, geo.size.width * 0.09)

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                // Drei versetzte Galerie-Reihen für maximale Abwechslung.
                VStack(spacing: 9) {
                    MarqueeRow(examples: OnboardingExamples.rowA, cardWidth: cardW, cardHeight: cardH, speed: 20)
                    MarqueeRow(examples: OnboardingExamples.rowB, cardWidth: cardW, cardHeight: cardH, speed: 27, reversed: true)
                    MarqueeRow(examples: OnboardingExamples.rowC, cardWidth: cardW, cardHeight: cardH, speed: 23)
                }
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                Spacer(minLength: 14)

                VStack(spacing: 13) {
                    ratingPill
                        .opacity(heroIn ? 1 : 0)
                        .offset(y: heroIn ? 0 : 10)

                    Text("Your photo, your rules.\nJust tell it what you want.")
                        .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.brandGradient)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .minimumScaleFactor(0.7)

                    Text("New hair, couple pics, dream outfit — tell Clavic what you want and watch it happen. Step by step, your way. No templates, no filters.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 28)
                }
                .padding(.horizontal, 8)
                .opacity(heroIn ? 1 : 0)
                .offset(y: heroIn ? 0 : 16)

                Spacer(minLength: 16)

                glowingPrimaryButton(title: "Get started") {
                    withAnimation(.spring(duration: 0.4)) { page = 1 }
                }
                .padding(.horizontal, Theme.screenPadding)
                .opacity(heroIn ? 1 : 0)
                .offset(y: heroIn ? 0 : 16)

                // Markdown-Links öffnen die externen GitHub-Pages-Seiten
                // (gleiche URLs wie LegalLinks). Interpolation würde Markdown
                // deaktivieren, daher hier als String-Literal.
                Text("By continuing, you accept our [Terms of Use](https://njscalp.github.io/Clavic/terms.html) and [Privacy Policy](https://njscalp.github.io/Clavic/privacy.html).")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .tint(Theme.accent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                withAnimation(.spring(duration: 0.7).delay(0.15)) { heroIn = true }
            }
        }
    }

    /// Dezente Social-Proof-Pill mit Sternen (ohne erfundene Zahlen).
    private var ratingPill: some View {
        HStack(spacing: 7) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 1.0, green: 0.75, blue: 0.2))
                }
            }
            Text("Loved by creators")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 13)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }

    /// Primär-Button mit weichem, pulsierendem Verlaufs-Glühen dahinter.
    private func glowingPrimaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(PrimaryButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(Theme.brandGradient)
                .blur(radius: 20)
                .opacity(ctaPulse ? 0.55 : 0.28)
                .scaleEffect(x: ctaPulse ? 1.02 : 0.97, y: ctaPulse ? 1.12 : 0.9)
                .padding(.horizontal, 8)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                ctaPulse = true
            }
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
                    // Weiches Verlaufs-Glühen hinter der Vorschau.
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Theme.brandGradient)
                        .blur(radius: 38)
                        .opacity(0.22)
                        .padding(.horizontal, 48)
                        .frame(height: cardH)

                    ExampleCardView(example: step.example, corner: 26, animated: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: cardH)
                        .padding(.horizontal, 36)
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .opacity
                        ))

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
                .id("text-\(page)")
                .transition(.opacity.combined(with: .offset(y: 12)))

                Spacer(minLength: 14)

                pageDots
                    .padding(.bottom, 14)

                glowingPrimaryButton(title: page >= steps.count ? "Continue" : "Next") {
                    advance()
                }
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
            // Nach dem Tutorial kommt nicht mehr direkt die App, sondern die
            // Zielfrage. Ohne sie startet der Director bei jedem ersten Foto
            // ohne jede Vorinformation.
            withAnimation(.spring(duration: 0.4)) { zeigeZiele = true }
        } else {
            withAnimation(.spring(duration: 0.4)) { page += 1 }
        }
    }

    private func schliessen() {
        withAnimation { isPresented = false }
        // AppsFlyer-Funnel + ATT-Abfrage (in-context, nach Onboarding).
        AppsFlyerEventTracker.trackOnboardingComplete()
        AdTracking.requestAuthorizationIfAppropriate()
    }
}
