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
    let image: UIImage
    var note: String = "Reading your photo"

    private let side: CGFloat = 132
    private let corner: CGFloat = 16

    var body: some View {
        HStack(spacing: 12) {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // 2,2 s pro Durchlauf, danach kurze Pause → kein Dauer-Zappeln.
                let cycle = 2.2
                let p = (t.truncatingRemainder(dividingBy: cycle)) / cycle

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
                    .overlay(scanOverlay(progress: p))
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
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
                // Zwei Platzhalter-Zeilen, die schimmern: signalisiert „hier
                // entsteht gleich Text", ohne schon etwas zu behaupten.
                ShimmerBar(width: 116)
                ShimmerBar(width: 78)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    /// Der Scan: eine weiche Lichtkante, die nach unten wandert, darüber ein
    /// feines Raster — liest sich als „wird ausgemessen", nicht als Deko.
    private func scanOverlay(progress: Double) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let y = h * CGFloat(progress)
            ZStack(alignment: .topLeading) {
                // Bereich oberhalb der Kante leicht abdunkeln = „schon gelesen".
                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .frame(height: max(0, y))

                LinearGradient(
                    colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.85), Theme.accent.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 26)
                .offset(y: y - 13)
                .blendMode(.plusLighter)

                gridLines(size: geo.size)
            }
        }
    }

    private func gridLines(size: CGSize) -> some View {
        Canvas { ctx, s in
            var path = Path()
            let step = s.width / 4
            var x = step
            while x < s.width { path.addRect(CGRect(x: x, y: 0, width: 0.5, height: s.height)); x += step }
            var y = step
            while y < s.height { path.addRect(CGRect(x: 0, y: y, width: s.width, height: 0.5)); y += step }
            ctx.fill(path, with: .color(.white.opacity(0.22)))
        }
        .frame(width: size.width, height: size.height)
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
