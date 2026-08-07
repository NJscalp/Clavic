//
//  WebsiteAgentScene.swift
//  Clavic
//
//  Hero-Karte des Larp-Agent-Tabs, übernommen von der Website
//  (components/WebsiteLarpAgent.tsx): dunkle Terminal-Karte mit Gold-Rand,
//  Raster, Status-Zeile, Claim, Funken, Pixel-Figur und Footer-Leiste.
//
//  WICHTIG: Nur der Agent-Tab benutzt diese Szene. Der Onboarding-Funnel
//  (LarpFunnelView) behält bewusst LarpScene.
//

import ImageIO
import SwiftUI

struct WebsiteAgentScene: View {
    var height: CGFloat = 270

    // Farben 1:1 aus globals.css der Website.
    private let goldStroke = Color(red: 0.839, green: 0.725, blue: 0.294)   // #d6b94b
    private let goldLabel = Color(red: 0.851, green: 0.733, blue: 0.333)    // #d9bb55
    private let lime = Color(red: 0.796, green: 1.0, blue: 0.404)           // #cbff67

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                background(size: geo.size)
                grid
                sparks(width: width)
                copyBlock(width: width)
                footer
                character(width: width)
                header
            }
            .frame(width: width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(goldStroke.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.09, green: 0.133, blue: 0.094).opacity(0.18), radius: 22, y: 20)
    }

    // MARK: - Hintergrund

    private func background(size: CGSize) -> some View {
        // radial(70% 42%, grün) + radial(22% 80%, gold) über linear(145deg).
        let reach = max(size.width, size.height)
        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.067, green: 0.094, blue: 0.067), location: 0),      // #111811
                    .init(color: Color(red: 0.031, green: 0.043, blue: 0.035), location: 0.68),   // #080b09
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.263, green: 0.459, blue: 0.306).opacity(0.42), .clear],
                center: UnitPoint(x: 0.70, y: 0.42), startRadius: 0, endRadius: reach * 0.31
            )
            RadialGradient(
                colors: [Color(red: 0.820, green: 0.698, blue: 0.275).opacity(0.12), .clear],
                center: UnitPoint(x: 0.22, y: 0.80), startRadius: 0, endRadius: reach * 0.30
            )
        }
    }

    /// Feines 22-pt-Raster, das nach rechts ausblendet (::before auf der Website).
    private var grid: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
                x += 22
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 22
            }
            ctx.fill(path, with: .color(.white.opacity(0.08)))
        }
        .opacity(0.16)
        .mask(
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.74)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .allowsHitTesting(false)
    }

    // MARK: - Textblöcke

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Rectangle()
                    .fill(lime)
                    .frame(width: 6, height: 6)
                    .shadow(color: lime, radius: 4)
                Text("CLAVIC TREND AGENT")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.88)
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Text("ONLINE · PRIVATE")
                .font(.system(size: 6, weight: .black, design: .monospaced))
                .tracking(0.66)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
    }

    private func copyBlock(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR PERSONAL AI CREATIVE")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(0.91)
                .foregroundStyle(goldLabel)
                .padding(.bottom, 9)
            // line-height .98 → die beiden Zeilen sitzen enger als normal.
            VStack(alignment: .leading, spacing: -2) {
                Text("Drop the photo.")
                Text("Name the flex.")
            }
            .font(.system(size: 22, weight: .bold))
            .tracking(-0.99)
            .foregroundStyle(.white)
        }
        .frame(width: width * 0.44, alignment: .leading)
        .padding(.leading, 18)
        .padding(.top, 66)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("PHOTO → DIRECTION → RESULT")
                .foregroundStyle(.white.opacity(0.39))
            Spacer(minLength: 6)
            Text("READY TO CREATE ↗")
                .foregroundStyle(lime)
        }
        .font(.system(size: 6, weight: .black, design: .monospaced))
        .tracking(0.48)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Color(red: 0.020, green: 0.031, blue: 0.024).opacity(0.72))
        .overlay(Rectangle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 15)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Funken und Figur

    private func sparks(width: CGFloat) -> some View {
        // websiteAgentSpark 2.8s steps(3, end): drei diskrete Zustände.
        TimelineView(.periodic(from: .now, by: 2.8 / 3)) { timeline in
            let step = Int((timeline.date.timeIntervalSinceReferenceDate / (2.8 / 3)).rounded(.down))
            ZStack(alignment: .topTrailing) {
                spark("◆", color: goldStroke.opacity(0.62), step: step)
                    .offset(x: -width * 0.43, y: 91)
                spark("✦", color: lime.opacity(0.6), step: step + 1)
                    .offset(x: -width * 0.09, y: 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .allowsHitTesting(false)
    }

    private func spark(_ glyph: String, color: Color, step: Int) -> some View {
        let states: [(opacity: Double, lift: CGFloat)] = [(0.35, 0), (0.78, -2.7), (0.78, -2.7)]
        let state = states[((step % states.count) + states.count) % states.count]
        return Text(glyph)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .opacity(state.opacity)
            .offset(y: state.lift)
    }

    private func character(width: CGFloat) -> some View {
        WebsiteAgentCharacter()
            .frame(width: width * 0.54, height: 264)
            .padding(.trailing, width * 0.04)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .shadow(color: .black.opacity(0.45), radius: 6, y: 15)
            .allowsHitTesting(false)
    }
}

// MARK: - Animierte Pixel-Figur

/// Spielt das animierte WebP der Website ab. Die Sequenz läuft mit rund 3 fps
/// (77 Frames auf 23 s), deshalb wird Frame für Frame dekodiert statt alles im
/// Speicher zu halten. Bis der erste Frame da ist — und falls das Dekodieren
/// fehlschlägt — steht das Poster, die Karte ist also nie leer.
private struct WebsiteAgentCharacter: View {
    @State private var frame: CGImage?

    var body: some View {
        Group {
            if let frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image("website_agent_poster")
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task { await play() }
    }

    private func play() async {
        guard let sequence = WebsiteAgentSequence() else { return }
        var index = 0
        while !Task.isCancelled {
            if let image = sequence.image(at: index) { frame = image }
            try? await Task.sleep(nanoseconds: UInt64(sequence.delay(at: index) * 1_000_000_000))
            index = (index + 1) % sequence.count
        }
    }
}

/// Dünner Wrapper um die WebP-Sequenz aus dem Asset-Katalog.
private final class WebsiteAgentSequence {
    private let source: CGImageSource
    let count: Int
    private let delays: [Double]

    init?() {
        guard let asset = NSDataAsset(name: "website_agent_actions"),
              let source = CGImageSourceCreateWithData(asset.data as CFData, nil)
        else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        self.source = source
        self.count = count
        self.delays = (0..<count).map { Self.delay(source: source, index: $0) }
    }

    func image(at index: Int) -> CGImage? {
        CGImageSourceCreateImageAtIndex(source, index, nil)
    }

    func delay(at index: Int) -> Double {
        delays.indices.contains(index) ? delays[index] : 0.3
    }

    /// Frame-Dauer aus den WebP-Properties; 0.3 s als Rückfall (Mittel der Datei).
    private static func delay(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any]
        else { return 0.3 }
        let unclamped = webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double
        let clamped = webp[kCGImagePropertyWebPDelayTime] as? Double
        let value = unclamped ?? clamped ?? 0.3
        return value > 0.01 ? value : 0.3
    }
}

#Preview {
    WebsiteAgentScene()
        .padding()
        .background(Color(white: 0.95))
}
