//
//  LarpMoneyLoader.swift
//  Clavic
//
//  Lade-Anzeige, während der Agent ein Bild generiert.
//  BASIS = exakt die Clavic-Ladeanimation wie im Chat (IntroLoader + animierte
//  „…"-Caption). DARÜBER als eigene Agent-Animation: der 2D-Pixel-Larper (Ganz-
//  körper, mit Beinen) läuft von links herein, wirft 3× selbst Geld herunter und
//  geht dann wieder raus — danach lädt nur noch die Clavic-Animation weiter, bis
//  das Bild fertig ist. Alles in SwiftUI (Canvas).
//

import SwiftUI

struct LarpMoneyLoader: View {
    var note: String = "Making it rain"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.background)

                // DIE Clavic-Ladeanimation (identisch zum Chat).
                IntroLoader()
                    .frame(width: 58, height: 58)
                    .allowsHitTesting(false)

                // Einmaliger Larper-Auftritt: rein → 3× werfen → raus.
                LarperMoneyIntro()
                    .allowsHitTesting(false)
            }
            .frame(width: 218, height: 150)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // Caption mit animierten Punkten — wie die Clavic-Ladekarte.
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

/// Der Ganzkörper-Larper, der reinläuft, 3× Geld wirft und wieder rausgeht.
private struct LarperMoneyIntro: View {
    // Zeitplan (Sekunden ab Erscheinen)
    private let walkInEnd = 1.2
    private let throwDur = 0.9
    private let throwCount = 3
    private var throwStart: Double { walkInEnd }
    private var throwEnd: Double { walkInEnd + Double(throwCount) * throwDur }
    private var walkOutEnd: Double { throwEnd + 1.2 }

    @State private var start = Date()

    private static let pal: [Character: Color] = [
        "K": Color(red: 0.09, green: 0.09, blue: 0.11), "k": Color(red: 0.16, green: 0.16, blue: 0.19),
        "S": Color(red: 0.90, green: 0.72, blue: 0.56), "s": Color(red: 0.78, green: 0.58, blue: 0.44),
        "G": Color(red: 0.05, green: 0.05, blue: 0.07), "L": Color(red: 0.55, green: 0.75, blue: 1.0),
        "M": Color(red: 0.47, green: 0.27, blue: 0.24), "W": Color(red: 0.84, green: 0.87, blue: 0.92),
        "D": Color(red: 0.75, green: 0.93, blue: 1.0), "N": Color(red: 0.88, green: 0.89, blue: 0.92),
        "C": Color(red: 0.30, green: 0.66, blue: 0.42), "c": Color(red: 0.55, green: 0.83, blue: 0.62),
    ]
    private static let stand = ["....KKKKKK....","...KKKKKKKK...","...KKSSSSKK...","...KGGGGGGK...","...KGLGGLGK...","...KSSSSSSK...","...KSSMMSSK...","....SSSSSS....","...KKKKKKKK...","..KKKKKKKKKK..","..KKKKDDKKKK..","..SKKKKKKKKS..","..sKKKKKKKKs..","...KKKKKKKK...","...KKKKKKKK...","...KKK..KKK...","...KKK..KKK...","...KKK..KKK...","...KKK..KKK...","..NNNN..NNNN.."]
    private static let walkA = ["....KKKKKK....","...KKKKKKKK...","...KKSSSSKK...","...KGGGGGGK...","...KGLGGLGK...","...KSSSSSSK...","...KSSMMSSK...","....SSSSSS....","...KKKKKKKK...","..KKKKKKKKKK..","..KKKKDDKKKK..","..SKKKKKKKKS..","..sKKKKKKKKs..","...KKKKKKKK...","...KKKKKKKK...","...KKK..KKK...","..KKK....KKK..","..KKK....KKK..",".KKK......KKK.",".NNN......NNN."]
    private static let walkB = ["....KKKKKK....","...KKKKKKKK...","...KKSSSSKK...","...KGGGGGGK...","...KGLGGLGK...","...KSSSSSSK...","...KSSMMSSK...","....SSSSSS....","...KKKKKKKK...","..KKKKKKKKKK..","..KKKKDDKKKK..","..SKKKKKKKKS..","..sKKKKKKKKs..","...KKKKKKKK...","...KKKKKKKK...","...KKK..KKK...","...KKK..KKK...","....KKKKKK....","....KKKKKK....","....NNNN......"]
    private static let throwUp = ["....KKKKKK..C.","...KKKKKKKK.cC","...KKSSSSKKKC.","...KGGGGGGKK..","...KGLGGLGKK..","...KSSSSSSKK..","...KSSMMSSKK..","....SSSSSS....","...KKKKKKKK...","..KKKKKKKKKK..","..KKKKDDKKKK..","..SKKKKKKKK...","..sKKKKKKKK...","...KKKKKKKK...","...KKKKKKKK...","...KKK..KKK...","...KKK..KKK...","...KKK..KKK...","...KKK..KKK...","..NNNN..NNNN.."]
    private static let throwRel = ["....KKKKKK....","...KKKKKKKK...","...KKSSSSKK...","...KGGGGGGK...","...KGLGGLGK...","...KSSSSSSK...","...KSSMMSSK...","....SSSSSS....","...KKKKKKKK...","..KKKKKKKKKKK.","..KKKKDDKKKKKS","..SKKKKKKKK.Cc","..sKKKKKKKKs..","...KKKKKKKK...","...KKKKKKKK...","...KKK..KKK...","...KKK..KKK...","...KKK..KKK...","...KKK..KKK...","..NNNN..NNNN.."]

    private let gridW = 14, gridH = 20

    var body: some View {
        TimelineView(.animation) { tl in
            let e = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard e < walkOutEnd else { return }   // danach nur noch die Clavic-Animation

                let cell = size.height * 0.80 / CGFloat(gridH)
                let charW = CGFloat(gridW) * cell
                let topY = size.height - CGFloat(gridH) * cell - 3
                let standX = size.width * 0.30 - charW / 2

                // x-Position + aktueller Frame je Phase.
                let x: CGFloat
                let frame: [String]
                if e < walkInEnd {
                    let p = e / walkInEnd
                    x = -charW - 6 + (standX + charW + 6) * CGFloat(p)
                    frame = (Int(e / 0.16) % 2 == 0) ? Self.walkA : Self.walkB
                } else if e < throwEnd {
                    x = standX
                    let lt = (e - throwStart).truncatingRemainder(dividingBy: throwDur)
                    frame = lt < 0.40 ? Self.throwUp : (lt < 0.55 ? Self.throwRel : Self.stand)
                } else {
                    let p = (e - throwEnd) / 1.2
                    x = standX + (size.width + 12 - standX) * CGFloat(p)
                    frame = (Int(e / 0.16) % 2 == 0) ? Self.walkA : Self.walkB
                }

                // Jeder Wurf: erst fliegt ein BÜNDEL aus der Hand, dann platzt es
                // und fächert in viele einzelne Scheine auf, die herunterregnen.
                let gold = Color(red: 0.91, green: 0.77, blue: 0.33)
                let green = Self.pal["C"]!, greenLight = Self.pal["c"]!
                func drawBill(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ a: Double) {
                    let r = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
                    if r.minY > size.height || a <= 0 { return }
                    ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(green.opacity(a)))
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 1), with: .color(greenLight.opacity(a)), lineWidth: 1)
                    if w > cell * 1.1 {
                        let sr = h * 0.28
                        ctx.fill(Path(ellipseIn: CGRect(x: r.midX - sr, y: r.midY - sr, width: sr * 2, height: sr * 2)), with: .color(gold.opacity(a)))
                    }
                }
                for i in 0..<throwCount {
                    let release = throwStart + Double(i) * throwDur + 0.45
                    let age = e - release
                    if age < 0 || age > 2.0 { continue }
                    let handX = standX + 12 * cell
                    let handY = topY + 11 * cell
                    let burst = 0.16
                    if age < burst {
                        // Bündel (dicker Stapel) fliegt aus der Hand nach rechts-oben.
                        let p = CGFloat(age / burst)
                        let bx = handX + p * cell * 3.2
                        let by = handY - p * cell * 2.0
                        let w = cell * 2.6, h = cell * 1.8
                        let r = CGRect(x: bx - w / 2, y: by - h / 2, width: w, height: h)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(green))
                        ctx.stroke(Path(roundedRect: r.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 1.5), with: .color(greenLight), lineWidth: 1)
                        // gestapelte Kanten (mehrere Scheine)
                        for s in 1...2 {
                            let yy = r.minY + CGFloat(s) * h / 3
                            ctx.stroke(Path { p in p.move(to: CGPoint(x: r.minX + 2, y: yy)); p.addLine(to: CGPoint(x: r.maxX - 2, y: yy)) }, with: .color(green.opacity(0.7)), lineWidth: 1)
                        }
                        ctx.fill(Path(ellipseIn: CGRect(x: r.midX - h * 0.24, y: r.midY - h * 0.24, width: h * 0.48, height: h * 0.48)), with: .color(gold))
                    } else {
                        // Aufplatzen → viele Scheine fächern auf und fallen.
                        let bAge = age - burst
                        let bx0 = handX + cell * 3.2, by0 = handY - cell * 2.0
                        let n = 16
                        for j in 0..<n {
                            let seed = Double(i * 40 + j)
                            let dir = -1.7 + 2.3 * (Double(j) / Double(n - 1)) + 0.25 * sin(seed * 5) // Fächer nach oben-außen
                            let sp = cell * CGFloat(5.5 + 5.5 * frac(sin(seed) * 43.7))
                            let vx = CGFloat(cos(dir)) * sp
                            let vy = CGFloat(sin(dir)) * sp
                            let x = bx0 + CGFloat(bAge) * vx
                            let y = by0 + CGFloat(bAge) * vy + CGFloat(bAge * bAge) * cell * 13   // Gravitation
                            let flutter = abs(sin(e * 5 + seed * 1.9))
                            let w = cell * (0.55 + 1.25 * CGFloat(flutter))
                            let alpha = bAge < 1.2 ? 1.0 : max(0, 1 - (bAge - 1.2) / 0.6)
                            drawBill(x, y, w, cell * 1.05, alpha)
                        }
                    }
                }

                // Larper-Frame zeichnen.
                for (gy, row) in frame.enumerated() {
                    for (gx, ch) in row.enumerated() where ch != "." {
                        guard let color = Self.pal[ch] else { continue }
                        let rect = CGRect(x: x + CGFloat(gx) * cell, y: topY + CGFloat(gy) * cell, width: cell + 0.6, height: cell + 0.6)
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
    }

    private func frac(_ v: Double) -> Double { v - floor(v) }
}

#Preview {
    LarpMoneyLoader()
        .padding()
        .background(Color(white: 0.96))
}
