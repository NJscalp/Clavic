//
//  IntroView.swift
//  Clavic
//
//  App-Intro (Splash): spielt das „Clavic"-Logo-Video einmal ab und
//  blendet dann sanft zur App über. Der gleiche Clip wird über
//  `IntroLoader` als saubere Lade-Animation während der Generierung genutzt.
//

import SwiftUI
import AVFoundation

/// Vollbild-Intro, das `intro.mp4` einmal abspielt und danach `onFinished` ruft.
struct IntroView: View {
    var onFinished: () -> Void

    @State private var isFadingOut = false

    var body: some View {
        ZStack {
            // Gleicher Weißton wie das Video, damit der Übergang nahtlos ist.
            // NICHT `Theme.background`: das ist seit dem Maskottchen-Umbau ein
            // warmes Creme, das Intro-Video liegt aber auf #F1F1F3 — sonst
            // steht ein heller Kasten mitten auf der Fläche.
            Color(red: 0.945, green: 0.945, blue: 0.953).ignoresSafeArea()

            if let url = Bundle.main.url(forResource: "intro", withExtension: "mp4") {
                OncePlayerView(url: url) {
                    finish()
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 200, height: 200)
            } else {
                // Fallback, falls die Datei fehlt.
                Text("Clavic")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { finish() }
                    }
            }
        }
        .opacity(isFadingOut ? 0 : 1)
    }

    private func finish() {
        guard !isFadingOut else { return }
        withAnimation(.easeOut(duration: 0.45)) { isFadingOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onFinished() }
    }
}

/// Spielt ein Video genau einmal und meldet das Ende.
struct OncePlayerView: UIViewControllerRepresentable {
    let url: URL
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEnded: onEnded) }

    func makeUIViewController(context: Context) -> PlayerContainerController {
        let controller = PlayerContainerController()
        controller.configure(url: url, coordinator: context.coordinator)
        return controller
    }

    func updateUIViewController(_ uiViewController: PlayerContainerController, context: Context) {}

    final class Coordinator {
        let onEnded: () -> Void
        init(onEnded: @escaping () -> Void) { self.onEnded = onEnded }

        @objc func playerDidFinish() { onEnded() }
    }
}

final class PlayerContainerController: UIViewController {
    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()

    func configure(url: URL, coordinator: OncePlayerView.Coordinator) {
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        player.isMuted = true
        self.player = player

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        view.backgroundColor = .clear

        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(OncePlayerView.Coordinator.playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        player.play()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
    }
}

/// Loopende Lade-Animation (gleicher Intro-Clip) für die Generierung.
///
/// NAHTLOS, nicht über `LoopingVideoView`. Der lässt bei jeder Wiederholung ein
/// Bild aus — dieselbe Sache, die im Onboarding als Ruckler auffiel, gemessen
/// als Sprung von 49,5 von 255 statt 0,8. Auf einer Kachel im Raster fällt das
/// kaum auf; hier steht die Animation gross auf dem Bildschirm und läuft bei
/// JEDER Generierung eine halbe bis eine Minute lang. Alle vier Sekunden ein
/// Loch ist genau die Stelle, an der eine App billig wirkt.
///
/// Der Clip selbst trägt das: letztes zu erstem Bild springt um 2,08 von 255,
/// ein normaler Bildwechsel im Clip liegt bei 2,67. Die Naht ist unsichtbar,
/// sobald sie überhaupt gezeigt wird.
struct IntroLoader: View {
    var body: some View {
        Group {
            if Bundle.main.url(forResource: "intro", withExtension: "mp4") != nil {
                SchleifenVideo(name: "intro")
            } else {
                ProgressView().tint(Theme.accent)
            }
        }
    }
}
