import SwiftUI

/// Full original → wipe → full edit → wipe back. Both images share the same crop.
struct TrendPhotoPreview: View {
    let look: TikTokTrends.Look
    var isAnimating = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    private var running: Bool { visible && isAnimating && scenePhase == .active && !reduceMotion }

    /// An eight-second cycle includes a two-second hold at either end.
    static func progress(at time: TimeInterval) -> CGFloat {
        let phase = time.truncatingRemainder(dividingBy: 8)
        if phase < 2 { return 0 }
        if phase < 4 {
            let t = (phase - 2) / 2
            return CGFloat(t * t * (3 - 2 * t))
        }
        if phase < 6 { return 1 }
        let t = (phase - 6) / 2
        return CGFloat(1 - t * t * (3 - 2 * t))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
            let fraction: CGFloat = running ? Self.progress(at: timeline.date.timeIntervalSinceReferenceDate) : 0.5
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .leading) {
                    photo(look.before, size: size)
                    photo(look.after, size: size)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: size.width * fraction)
                        }
                    if fraction > 0.01 && fraction < 0.99 {
                        Rectangle().fill(.white.opacity(0.85))
                            .frame(width: 1.5)
                            .offset(x: size.width * (1 - fraction))
                    }
                    VStack {
                        Spacer()
                        HStack {
                            if fraction < 0.98 { badge("Before") }
                            Spacer(minLength: 0)
                            if fraction > 0.02 { badge("After") }
                        }
                    }
                    .padding(7)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(look.title), example photo before and after colour editing")
    }

    private func photo(_ name: String, size: CGSize) -> some View {
        Image(name).resizable().scaledToFill()
            .frame(width: size.width, height: size.height).clipped()
    }

    private func badge(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
    }
}
