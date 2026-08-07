//
//  PixelLarper.swift
//  Clavic
//
//  2D-Pixel-Maskottchen für den Larp-Agent-Tab: ein schwarz gekleideter Typ mit
//  Sonnenbrille und funkelnder Diamant-Chain (LARP-Look). Komplett in SwiftUI
//  gezeichnet (Canvas) — keine Bild-Assets, scharf auf jeder Größe, animierbar.
//
//  Zwei Zustände:
//    • idle     – leichtes Atmen/Wippen + über die Chain wanderndes Funkeln
//    • thinking – wippt lebhafter, Kopf-Sway, Gedankenblase mit pulsierenden Punkten
//                 (ersetzt den hässlichen ProgressView beim Nachdenken)
//

import SwiftUI

struct PixelLarper: View {
    var thinking: Bool = false
    /// Lupen-Modus: die Figur hält eine Lupe vors Gesicht und scannt (für das
    /// gerade eingefügte Foto — „er schaut sich dein Bild an").
    var inspecting: Bool = false
    var size: CGFloat = 96

    // Pixel-Map: jede Zeile ein String, ein Zeichen = ein Pixel.
    //  .  transparent   H Kapuze/Hoodie (schwarz)   h Hoodie-Schatten
    //  F  Haut          f Haut-Schatten             G Sonnenbrille   L Brillen-Glanz
    //  W  Chain (Silber) D Diamant                  M Mund/Smirk
    private static let rows: [String] = [
        "....HHHHHHHH....",
        "...HHHHHHHHHH...",
        "..HHHHHHHHHHHH..",
        "..HHhFFFFFFhHH..",
        "..HHFFFFFFFFHH..",
        "..HHGGGGGGGGHH..",   // Sonnenbrille
        "..HHGLGGGGLGHH..",   // Brillen-Glanz
        "..HHFFFFFFFFHH..",
        "..HHFfFMMFfFHH..",   // Smirk
        "...HHFFFFFFHH...",
        "....HHHHHHHH....",   // Kiefer/Hals
        "...hHHHHHHHHh...",   // Schultern
        "..HHWHHHHHHWHH..",   // Chain-Enden am Hals
        "..HHHWHHHHWHHH..",   // Chain schwingt nach innen
        "..HHHHWDDWHHHH..",   // Chain-Boden mit Diamant-Anhänger
        "HHHHHHHHHHHHHHHH",   // Hoodie
        "HHHHHHHHHHHHHHHH",
        "HHHHhhHHHHhhHHHH",
    ]

    private static let palette: [Character: Color] = [
        "H": Color(red: 0.09, green: 0.09, blue: 0.11),   // schwarz
        "h": Color(red: 0.16, green: 0.16, blue: 0.19),   // Schatten
        "F": Color(red: 0.90, green: 0.72, blue: 0.56),   // Haut
        "f": Color(red: 0.78, green: 0.58, blue: 0.44),   // Haut-Schatten
        "G": Color(red: 0.05, green: 0.05, blue: 0.07),   // Brille
        "L": Color(red: 0.55, green: 0.75, blue: 1.0),    // Brillen-Glanz
        "M": Color(red: 0.45, green: 0.28, blue: 0.24),   // Mund
        "W": Color(red: 0.82, green: 0.86, blue: 0.92),   // Chain-Silber
        "D": Color(red: 0.75, green: 0.93, blue: 1.0),    // Diamant
    ]

    private var gridW: Int { Self.rows.map(\.count).max() ?? 16 }
    private var gridH: Int { Self.rows.count }

    // Positionen aller Diamant-Pixel (für das wandernde Funkeln).
    private static let diamondCells: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "D" || ch == "W" {
                out.append((x, y))
            }
        }
        return out
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvasSize in
                // Beim Nachdenken oben Platz für die Gedankenblase reservieren,
                // damit sie INNERHALB des Frames bleibt (kein Clipping).
                let headroom = thinking ? 5 : 0
                let effGridH = gridH + headroom
                let cell = min(canvasSize.width, canvasSize.height) / CGFloat(max(gridW, effGridH))
                let blockTop = (canvasSize.height - cell * CGFloat(effGridH)) / 2
                let originX = (canvasSize.width - cell * CGFloat(gridW)) / 2
                let originY = blockTop + cell * CGFloat(headroom)   // Figur sitzt unter dem Headroom

                // Wippen (Atmen); beim Nachdenken lebhafter + leichter Sway.
                let bobSpeed = thinking ? 3.4 : 1.8
                let bobAmp = thinking ? 0.5 : 0.3
                let yBob = CGFloat(sin(t * bobSpeed)) * cell * bobAmp
                let xSway = thinking ? CGFloat(sin(t * 2.1)) * cell * 0.3 : 0

                // Figur zeichnen.
                for (y, row) in Self.rows.enumerated() {
                    for (x, ch) in row.enumerated() where ch != "." {
                        guard let color = Self.palette[ch] else { continue }
                        let rect = CGRect(
                            x: originX + CGFloat(x) * cell + xSway,
                            y: originY + CGFloat(y) * cell + yBob,
                            width: cell + 0.6, height: cell + 0.6
                        )
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }

                // Wanderndes Funkeln über die Chain.
                if !Self.diamondCells.isEmpty {
                    let idx = Int(t * 4) % Self.diamondCells.count
                    let (sx, sy) = Self.diamondCells[idx]
                    let rect = CGRect(
                        x: originX + CGFloat(sx) * cell + xSway,
                        y: originY + CGFloat(sy) * cell + yBob,
                        width: cell + 0.6, height: cell + 0.6
                    )
                    ctx.fill(Path(rect), with: .color(.white))
                    let cx = rect.midX, cy = rect.midY
                    let glow = cell * 0.9
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: cx - glow, y: cy)); p.addLine(to: CGPoint(x: cx + glow, y: cy))
                        p.move(to: CGPoint(x: cx, y: cy - glow)); p.addLine(to: CGPoint(x: cx, y: cy + glow))
                    }, with: .color(.white.opacity(0.65)), lineWidth: max(1, cell * 0.18))
                }

                // Gedankenblase im reservierten Headroom (5 Zellen) ÜBER dem Kopf.
                // Absolut vom Frame-Oberrand verankert → bleibt immer im Bild.
                if thinking {
                    let bubbleColor = Color(red: 0.09, green: 0.09, blue: 0.11)
                    let dotCount = Int(t * 2.2) % 3 + 1
                    let headCenterX = originX + cell * CGFloat(gridW) / 2 + xSway * 0.5
                    let floatY = (CGFloat(sin(t * 2.6)) + 1) * cell * 0.18   // 0…0.36 Zellen, immer nach unten

                    // Hauptblase oben (bh 2.6 Zellen), Bläschen darunter Richtung Kopf.
                    let bw = cell * 6.4, bh = cell * 2.6
                    let bubbleRect = CGRect(x: headCenterX - bw / 2, y: blockTop + cell * 0.25 + floatY, width: bw, height: bh)
                    ctx.fill(Path(roundedRect: bubbleRect, cornerRadius: bh / 2), with: .color(bubbleColor))
                    for i in 0..<3 {
                        let on = i < dotCount
                        let dotRect = CGRect(
                            x: bubbleRect.minX + cell * (1.0 + CGFloat(i) * 1.55),
                            y: bubbleRect.midY - cell * 0.45,
                            width: cell * 0.9, height: cell * 0.9
                        )
                        ctx.fill(Path(ellipseIn: dotRect), with: .color(.white.opacity(on ? 0.95 : 0.28)))
                    }
                    // Zwei aufsteigende Bläschen zwischen Blase und Kopf.
                    ctx.fill(Path(ellipseIn: CGRect(x: headCenterX - cell * 0.2, y: bubbleRect.maxY + cell * 0.15 + floatY, width: cell * 1.1, height: cell * 1.1)), with: .color(bubbleColor.opacity(0.88)))
                    ctx.fill(Path(ellipseIn: CGRect(x: headCenterX - cell * 0.5, y: bubbleRect.maxY + cell * 1.15 + floatY, width: cell * 0.8, height: cell * 0.8)), with: .color(bubbleColor.opacity(0.72)))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 30) {
        PixelLarper(thinking: false, size: 120)
        PixelLarper(thinking: true, size: 120)
    }
    .padding()
    .background(Color(white: 0.95))
}
