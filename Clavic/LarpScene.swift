//
//  LarpScene.swift
//  Clavic
//
//  Animierte 2D-Pixel-Szene als Design-Herzstück des Larp-Agent-Tabs:
//  dunkle „Bühne" mit einer Pixel-Night-City-Skyline (funkelnde Gold-Fenster),
//  dem Larper davor mit Gold-Glow, und aufsteigenden, glitzernden Pixel-Diamanten.
//  Alles in SwiftUI (Canvas) — keine Assets, läuft flüssig, skaliert scharf.
//

import SwiftUI

struct LarpScene: View {
    var height: CGFloat = 246

    private let gold = Color(red: 0.91, green: 0.77, blue: 0.33)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.17), Color(red: 0.04, green: 0.04, blue: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
            LarpSceneBackdrop()
            PixelLarper(thinking: false, size: height * 0.62)
                .offset(y: -height * 0.04)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(gold.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}

/// Animierter Pixel-Hintergrund: Gold-Glow, Skyline mit funkelnden Fenstern,
/// aufsteigende Diamanten.
private struct LarpSceneBackdrop: View {
    private let gold = Color(red: 0.93, green: 0.79, blue: 0.36)
    private let diamond = Color(red: 0.75, green: 0.93, blue: 1.0)
    private let diamondMask = ["..X..", ".XXX.", "XXXXX", ".XXX.", "..X.."]

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                // --- Gold-Glow hinter dem Larper (Mitte) ---
                let gr = size.width * 0.34
                let center = CGPoint(x: size.width / 2, y: size.height * 0.40)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - gr, y: center.y - gr, width: gr * 2, height: gr * 2)),
                    with: .radialGradient(Gradient(colors: [gold.opacity(0.22), .clear]),
                                          center: center, startRadius: 2, endRadius: gr)
                )

                // --- Skyline mit funkelnden Fenstern ---
                let u = max(3, floor(size.width / 58))     // Pixel-/Fenster-Einheit
                let cols = Int(size.width / u) + 2
                var bx = 0, bi = 0
                while bx < cols {
                    let bwUnits = 5 + (bi % 3)              // Gebäudebreite 5–7
                    let hUnits = 5 + Int(5 * abs(sin(Double(bi) * 1.27)))
                    let bxpx = CGFloat(bx) * u
                    let topY = size.height - CGFloat(hUnits) * u
                    ctx.fill(
                        Path(CGRect(x: bxpx, y: topY, width: CGFloat(bwUnits) * u, height: CGFloat(hUnits) * u + u)),
                        with: .color(Color(red: 0.07, green: 0.08, blue: 0.13))
                    )
                    // Fenster
                    for wy in 1..<max(2, hUnits) {
                        for wx in 1..<bwUnits {
                            if (wx + wy) % 2 == 0 { continue }
                            let seed = bi * 31 + wx * 7 + wy * 13
                            if seed % 5 == 0 { continue }
                            let tw = sin(t * 1.6 + Double(seed)) > 0.35 ? 1.0 : 0.55
                            ctx.fill(
                                Path(CGRect(x: bxpx + CGFloat(wx) * u, y: topY + CGFloat(wy) * u, width: u * 0.6, height: u * 0.6)),
                                with: .color(gold.opacity(0.55 * tw))
                            )
                        }
                    }
                    bx += bwUnits + 1
                    bi += 1
                }

                // --- Aufsteigende, glitzernde Pixel-Diamanten ---
                let count = 7
                let cycle = Double(size.height) + 60
                for k in 0..<count {
                    let fx = frac(sin(Double(k) * 91.7) * 43.1)
                    let x = size.width * (0.08 + 0.84 * fx)
                    let speed = 13.0 + Double(k % 3) * 6
                    let up = (t * speed + Double(k) / Double(count) * cycle).truncatingRemainder(dividingBy: cycle)
                    let y = size.height - CGFloat(up)
                    let bright = sin(t * 3 + Double(k) * 1.3) > 0.2
                    let cell = u * 0.34
                    for (ry, row) in diamondMask.enumerated() {
                        for (rx, ch) in row.enumerated() where ch == "X" {
                            let isCenter = (ry == 2 || rx == 2)
                            let col = bright ? (isCenter ? Color.white : diamond) : diamond.opacity(0.5)
                            ctx.fill(
                                Path(CGRect(x: x + CGFloat(rx - 2) * cell, y: y + CGFloat(ry - 2) * cell, width: cell + 0.5, height: cell + 0.5)),
                                with: .color(col)
                            )
                        }
                    }
                }
            }
        }
    }

    private func frac(_ x: Double) -> Double { let f = x - floor(x); return f }
}

#Preview {
    LarpScene()
        .padding()
        .background(Color(white: 0.96))
}
