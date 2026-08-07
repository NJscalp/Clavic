//
//  LarpAnalyzeLoader.swift
//  Clavic
//
//  Lade-Anzeige, WÄHREND der Agent ein angehängtes Foto analysiert (bevor er mit
//  Optionen oder einem Edit antwortet). Im Stil der Clavic-Ladekarte (IntroLoader
//  + „…"-Caption), darüber die eigene Agent-Animation: der Ganzkörper-Pixel-Larper
//  läuft von links herein, hält eine Lupe hoch und scannt das Bild kurz, dann geht
//  er wieder raus. Läuft in Schleife, bis die Analyse fertig ist. Alles in SwiftUI.
//

import SwiftUI

struct LarpAnalyzeLoader: View {
    var note: String = "Analyzing your photo"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.background)
                IntroLoader()
                    .frame(width: 58, height: 58)
                    .allowsHitTesting(false)
                LarperAnalyzeIntro()
                    .allowsHitTesting(false)
            }
            .frame(width: 218, height: 150)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            TimelineView(.periodic(from: .now, by: 0.45)) { ctx in
                let n = Int(ctx.date.timeIntervalSinceReferenceDate / 0.45) % 3 + 1
                HStack(spacing: 3) {
                    Text(note).foregroundStyle(Theme.textSecondary)
                    Text(String(repeating: ".", count: n)).foregroundStyle(Theme.accent)
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
            }
        }
    }
}

/// Larper läuft rein → hält die Lupe hoch & scannt → läuft wieder raus (Schleife).
private struct LarperAnalyzeIntro: View {
    private let walkInEnd = 1.1
    private let inspectEnd = 3.4
    private let cycle = 4.6   // danach von vorne

    @State private var start = Date()

    private static let pal: [Character: Color] = [
        "K": Color(red: 0.09, green: 0.09, blue: 0.11), "k": Color(red: 0.16, green: 0.16, blue: 0.19),
        "S": Color(red: 0.90, green: 0.72, blue: 0.56), "s": Color(red: 0.78, green: 0.58, blue: 0.44),
        "G": Color(red: 0.05, green: 0.05, blue: 0.07), "L": Color(red: 0.55, green: 0.75, blue: 1.0),
        "M": Color(red: 0.47, green: 0.27, blue: 0.24), "W": Color(red: 0.84, green: 0.87, blue: 0.92),
        "D": Color(red: 0.75, green: 0.93, blue: 1.0), "N": Color(red: 0.88, green: 0.89, blue: 0.92),
    ]
    private static let stand = ["....KKKKKK....","...KKKKKKKK...","...KKSSSSKK...","...KGGGGGGK...","...KGLGGLGK...","...KSSSSSSK...","...KSSMMSSK...","....SSSSSS....","...KKKKKKKK...","..KKKKKKKKKK..","..KKKKDDKKKK..","..SKKKKKKKKS..","..sKKKKKKKKs..","...KKKKKKKK...","...KKKKKKKK...","...KKK..KKK...","...KKK..KKK...","...KKK..KKK...","...KKK..KKK...","..NNNN..NNNN.."]
    private static let walkA = ["....KKKKKK....","...KKKKKKKK...","...KKSSSSKK...","...KGGGGGGK...","...KGLGGLGK...","...KSSSSSSK...","...KSSMMSSK...","....SSSSSS....","...KKKKKKKK...","..KKKKKKKKKK..","..KKKKDDKKKK..","..SKKKKKKKKS..","..sKKKKKKKKs..","...KKKKKKKK...","...KKKKKKKK...","...KKK..KKK...","..KKK....KKK..","..KKK....KKK..",".KKK......KKK.",".NNN......NNN."]
    private static let walkB = ["....KKKKKK....","...KKKKKKKK...","...KKSSSSKK...","...KGGGGGGK...","...KGLGGLGK...","...KSSSSSSK...","...KSSMMSSK...","....SSSSSS....","...KKKKKKKK...","..KKKKKKKKKK..","..KKKKDDKKKK..","..SKKKKKKKKS..","..sKKKKKKKKs..","...KKKKKKKK...","...KKKKKKKK...","...KKK..KKK...","...KKK..KKK...","....KKKKKK....","....KKKKKK....","....NNNN......"]

    private let gridW = 14, gridH = 20

    var body: some View {
        TimelineView(.animation) { tl in
            let e = tl.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
            Canvas { ctx, size in
                let cell = size.height * 0.80 / CGFloat(gridH)
                let charW = CGFloat(gridW) * cell
                let topY = size.height - CGFloat(gridH) * cell - 3
                let standX = size.width * 0.30 - charW / 2

                let x: CGFloat
                let frame: [String]
                var inspecting = false
                if e < walkInEnd {
                    let p = e / walkInEnd
                    x = -charW - 6 + (standX + charW + 6) * CGFloat(p)
                    frame = (Int(e / 0.16) % 2 == 0) ? Self.walkA : Self.walkB
                } else if e < inspectEnd {
                    x = standX
                    frame = Self.stand
                    inspecting = true
                } else {
                    let p = (e - inspectEnd) / (cycle - inspectEnd)
                    x = standX + (size.width + 12 - standX) * CGFloat(p)
                    frame = (Int(e / 0.16) % 2 == 0) ? Self.walkA : Self.walkB
                }

                // Figur zeichnen.
                for (gy, row) in frame.enumerated() {
                    for (gx, ch) in row.enumerated() where ch != "." {
                        guard let color = Self.pal[ch] else { continue }
                        let rect = CGRect(x: x + CGFloat(gx) * cell, y: topY + CGFloat(gy) * cell, width: cell + 0.6, height: cell + 0.6)
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }

                // Lupe: beim Inspizieren vor dem Gesicht, scannt in kleiner Bahn + Glint.
                if inspecting {
                    let scanT = e - walkInEnd
                    let baseX = x + cell * 11.5
                    let baseY = topY + cell * 4.5
                    let lensX = baseX + CGFloat(sin(scanT * 3.0)) * cell * 1.4
                    let lensY = baseY + CGFloat(sin(scanT * 1.7)) * cell * 1.1
                    let r = cell * 1.9

                    // Haltende Hand am Griff-Ansatz (unten-rechts der Linse).
                    let handX = lensX + r * 0.9, handY = lensY + r * 0.9
                    ctx.fill(Path(ellipseIn: CGRect(x: handX - cell * 0.6, y: handY - cell * 0.6, width: cell * 1.2, height: cell * 1.2)), with: .color(Self.pal["S"]!))
                    // Griff
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: lensX + r * 0.55, y: lensY + r * 0.55)); p.addLine(to: CGPoint(x: handX + cell, y: handY + cell)) },
                               with: .color(Self.pal["k"]!), lineWidth: max(2, cell * 0.5))
                    // Glas (leicht bläulich, halbtransparent)
                    ctx.fill(Path(ellipseIn: CGRect(x: lensX - r, y: lensY - r, width: r * 2, height: r * 2)), with: .color(Self.pal["D"]!.opacity(0.45)))
                    // Rahmen
                    ctx.stroke(Path(ellipseIn: CGRect(x: lensX - r, y: lensY - r, width: r * 2, height: r * 2)),
                               with: .color(Color(red: 0.91, green: 0.77, blue: 0.33)), lineWidth: max(2, cell * 0.5))
                    // Glint (weißer Strich, wandert)
                    let g = CGFloat(0.5 + 0.4 * sin(scanT * 4))
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: lensX - r * 0.5, y: lensY - r * 0.5 + r * g * 0.4))
                        p.addLine(to: CGPoint(x: lensX + r * 0.1, y: lensY - r * 0.7 + r * g * 0.4))
                    }, with: .color(.white.opacity(0.85)), lineWidth: max(1.5, cell * 0.32))
                    // kleiner Scan-Funke im Zentrum, pulsiert
                    if sin(scanT * 6) > 0.3 {
                        ctx.fill(Path(ellipseIn: CGRect(x: lensX - cell * 0.28, y: lensY - cell * 0.28, width: cell * 0.56, height: cell * 0.56)), with: .color(.white.opacity(0.9)))
                    }
                }
            }
        }
    }
}

#Preview {
    LarpAnalyzeLoader()
        .padding()
        .background(Color(white: 0.96))
}
