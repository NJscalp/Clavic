//
//  AgentAnalyzingCard.swift
//  Clavic
//
//  Warte-Anzeige des Agenten, während er ein Foto LIEST.
//
//  Ersetzt die Pixel-Figur mit Lupe und den Geldregen-Larper. Grund: der Agent
//  analysiert hier ein konkretes Foto — eine Maskottchen-Figur daneben erzählt
//  davon nichts. Stattdessen läuft ein Scan-Streifen über GENAU das Foto, das
//  gerade gelesen wird. Das ist dieselbe Bildsprache wie im Chat-Tab, wo die
//  Ladeanzeige auch aus dem Bild selbst besteht (`BlurLoadingCard`).
//
//  Für reine Text-Antworten (kein Foto im Spiel) gibt es `AgentThinkingRow` —
//  eine schlanke Zeile mit wanderndem Schimmer statt einer Figur.
//

import SwiftUI

/// Foto-Analyse: das Bild klein, darüber ein weicher Scan-Streifen von oben nach
/// unten, plus Raster-Andeutung. Läuft in Schleife, bis die Antwort da ist.
struct AgentAnalyzingCard: View {
    let images: [UIImage]
    var note: String = "Reading your photo"

    init(images: [UIImage], note: String = "Reading your photo") {
        self.images = images
        self.note = note
    }

    init(image: UIImage, note: String = "Reading your photo") {
        self.images = [image]
        self.note = note
    }

    private let cardWidth: CGFloat = 188
    private let cardHeight: CGFloat = 224
    private let corner: CGFloat = 22

    private let stages = [
        ("Reading composition", "viewfinder"),
        ("Checking light & color", "sun.max.fill"),
        ("Protecting your identity", "faceid"),
        ("Building 3 directions", "square.stack.3d.up.fill")
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let beat = 1.65
            let step = Int(t / beat)
            let fraction = (t.truncatingRemainder(dividingBy: beat)) / beat
            // Hold long enough to read, then perform a clean 180° card flip.
            let flipProgress = max(0, min(1, (fraction - 0.70) / 0.30))
            let rawAngle = flipProgress * 180
            let showsNext = rawAngle >= 90
            let visibleStep = step + (showsNext ? 1 : 0)
            let visibleStage = visibleStep % stages.count
            let visibleImage = images.isEmpty ? nil : images[visibleStep % images.count]
            let readableAngle = showsNext ? rawAngle - 180 : rawAngle

            VStack(alignment: .leading, spacing: 8) {
                Text(note.uppercased())
                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)

                ZStack {
                    if let visibleImage {
                        Image(uiImage: visibleImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                            .blur(radius: 2.2)
                    } else {
                        Theme.surfaceHigh
                    }

                    LinearGradient(
                        colors: [.black.opacity(0.08), .black.opacity(0.16), .black.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(spacing: 9) {
                        Spacer()
                        Image(systemName: stages[visibleStage].1)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                        Text(stages[visibleStage].0)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        HStack(spacing: 5) {
                            ForEach(stages.indices, id: \.self) { index in
                                Capsule()
                                    .fill(index == visibleStage ? .white : .white.opacity(0.34))
                                    .frame(width: index == visibleStage ? 22 : 8, height: 4)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 16, y: 9)
                .rotation3DEffect(
                    .degrees(readableAngle),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )

                if images.count > 1 {
                    Text("Photo \((visibleStep % images.count) + 1) of \(images.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: cardWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Schlanke Denk-Zeile für Antworten OHNE Foto. Kein Maskottchen — nur ein
/// wandernder Schimmer, der zeigt, dass etwas entsteht.
struct AgentThinkingRow: View {
    var note: String = "Thinking"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TimelineView(.periodic(from: .now, by: 0.45)) { ctx in
                let n = Int(ctx.date.timeIntervalSinceReferenceDate / 0.45) % 3 + 1
                HStack(spacing: 3) {
                    Text(note)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(String(repeating: ".", count: n))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                .lineLimit(1)
            }
            ShimmerBar(width: 148)
            ShimmerBar(width: 104)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}

/// Platzhalter-Balken mit wanderndem Glanz.
struct ShimmerBar: View {
    var width: CGFloat
    var height: CGFloat = 8

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let p = (t.truncatingRemainder(dividingBy: 1.4)) / 1.4
            Capsule()
                .fill(Theme.surfaceHigh)
                .frame(width: width, height: height)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.9), .clear],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.45)
                        // von links außerhalb nach rechts außerhalb
                        .offset(x: width * CGFloat(p * 1.45) - width * 0.72)
                }
                .clipShape(Capsule())
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        if let ui = UIImage(named: "preview_ai_character") {
            AgentAnalyzingCard(image: ui)
        }
        AgentThinkingRow(note: "Cooking up the flex")
    }
    .padding()
    .background(Theme.background)
}
