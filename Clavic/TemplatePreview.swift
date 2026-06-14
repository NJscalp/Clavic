//
//  TemplatePreview.swift
//  Clavic
//
//  Legt über den Verlauf+Icon einer Kachel automatisch eine echte
//  Vorschau, falls vorhanden:
//   1. Video  <preview>.mp4 (im App-Bundle) → stummer Loop
//   2. Bild   Asset <preview>               → füllend
//   3. sonst nichts → die Kachel zeigt ihren Verlauf + Icon (Fallback)
//

import SwiftUI
import AVFoundation

/// Overlay, das die Kachelfläche mit einer Vorschau füllt (oder leer bleibt).
struct TemplatePreviewOverlay: View {
    let template: VideoTemplate

    var body: some View {
        if let before = template.previewBeforeImage,
           let after = template.previewAfterImage {
            BeforeAfterSlider(before: before, after: after, showLabels: false)
                .allowsHitTesting(false)
        } else if let url = template.previewVideoURL {
            LoopingVideoView(url: url)
                .allowsHitTesting(false)
        } else if let image = template.previewImage {
            Color.clear.overlay(
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            )
            .clipped()
            .allowsHitTesting(false)
        }
        // sonst: kein Overlay → Verlauf + Icon der Kachel bleiben sichtbar
    }
}

/// Stummer, endlos loopender Video-Player ohne Steuerelemente (für Kacheln).
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.update(url: url)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.teardown()
    }
}

final class LoopingPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        setup(url: url)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func update(url: URL) {
        guard url != currentURL else { return }
        setup(url: url)
    }

    private func setup(url: URL) {
        teardown()
        currentURL = url

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        queuePlayer = player
        player.play()
    }

    func teardown() {
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
        queuePlayer = nil
        currentURL = nil
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // Pausiert, sobald die Kachel aus der Ansicht scrollt; spielt wieder beim Erscheinen.
        if newWindow == nil {
            queuePlayer?.pause()
        } else {
            queuePlayer?.play()
        }
    }
}
