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

/// Schaltet die laufenden Kachel-Vorschauen (Slider-Animation, Video-Loops)
/// global ab, wenn sie nicht sichtbar sind (anderer Tab, offenes Sheet,
/// App im Hintergrund). Das hält Tab-Wechsel und Tastatur flüssig.
private struct PreviewsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var previewsActive: Bool {
        get { self[PreviewsActiveKey.self] }
        set { self[PreviewsActiveKey.self] = newValue }
    }
}

/// Overlay, das die Kachelfläche mit einer Vorschau füllt (oder leer bleibt).
struct TemplatePreviewOverlay: View {
    let template: VideoTemplate
    @Environment(\.previewsActive) private var previewsActive

    var body: some View {
        if let before = template.previewBeforeImage,
           let after = template.previewAfterImage {
            // Senkrecht: die Kacheln sind hochkant, eine waagerechte Trennlinie
            // legt damit immer das ganze Motiv frei statt einer schmalen Spalte.
            BeforeAfterSlider(before: before, after: after, axis: .vertical,
                              showLabels: false, showDivider: false,
                              isAnimating: previewsActive)
                .allowsHitTesting(false)
        } else if let url = template.previewVideoURL {
            LoopingVideoView(url: url, isActive: previewsActive)
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
    var isActive: Bool = true

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.update(url: url)
        uiView.setActive(isActive)
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
    /// Vom View gewünschter Zustand (sichtbar/aktiv). Window-Zustand hat Vorrang.
    private var wantsActive = true

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

    /// Pausiert/spielt den vorhandenen Player ohne teure Neuerstellung.
    func setActive(_ active: Bool) {
        guard wantsActive != active else { return }
        wantsActive = active
        applyPlaybackState()
    }

    private func applyPlaybackState() {
        let shouldPlay = wantsActive && window != nil
        if shouldPlay { queuePlayer?.play() } else { queuePlayer?.pause() }
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
        applyPlaybackState()
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
        let shouldPlay = wantsActive && newWindow != nil
        if shouldPlay { queuePlayer?.play() } else { queuePlayer?.pause() }
    }
}
