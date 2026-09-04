//
//  DirectorNote.swift
//  Clavic
//
//  Was er machen wuerde — als Blatt Papier, in drei Zeilen.
//
//  HIER STAND EIN ABSATZ. Der Director sagte einen ganzen Satz, gesetzt in
//  19 pt Serifen ueber zwei bis drei Zeilen. Schoen, aber man musste ihn LESEN,
//  um zu erfahren, was mit dem Foto passiert. Jetzt stehen dort drei bis vier
//  Woerter je Anmerkung, jede mit dem Punkt in der Farbe ihres Striches auf dem
//  Bild — rot fuer das, was stoert, gruen fuer das, was sitzt. Man sieht die
//  Markierung auf dem Foto und findet sie darunter wieder, ohne zu suchen.
//
//  Vorher stand hier eine Zeile mit einem blauen Balken davor. Inhaltlich
//  richtig, aber es sah aus wie eine Fehlermeldung. Der eine Satz, den der
//  Director sagt, ist das Herz des Bildschirms; er soll aussehen, als haette
//  ihn jemand aufgeschrieben.
//
//  WORAUS DER PAPIER-EINDRUCK ENTSTEHT — vier Dinge, jedes noetig:
//    • Serifen. Die ganze App ist rund und geometrisch; eine Serifenschrift
//      liest sich sofort als Dokument statt als Oberflaeche.
//    • Eine rote Randlinie links, wie im Schulheft. Sie ist der Grund, warum
//      man „Blatt" liest, bevor man ein Wort gelesen hat.
//    • Eine winzige Schraeglage und ein weicher Schatten: das Blatt LIEGT auf
//      dem Tisch, es ist nicht in die Seite einbetoniert.
//    • Eine Unterschrift. Ohne sie ist es Systemtext, mit ihr hat es einen
//      Absender.
//
//  Die Ecke oben rechts ist umgeknickt. Das kostet zwei Dreiecke und ist der
//  billigste Weg, aus einem Rechteck ein Stueck Papier zu machen.
//

import SwiftUI

struct DirectorNote: View {
    /// Die Anmerkungen vom Foto. Sie sind der Inhalt des Blattes.
    let marks: [ReadMark]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    /// Kantenlaenge des Eselsohrs.
    private static let dogEar: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            kopf
            VStack(alignment: .leading, spacing: 9) {
                ForEach(marks) { mark in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(mark.isPraise ? Theme.go : Theme.danger)
                            .frame(width: 7, height: 7)
                        Text(mark.change)
                            // Serifen halten das Blatt, aber kurz und gross
                            // genug, um es im Vorbeigehen zu lesen.
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            unterschrift
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .padding(.vertical, 16)
        .background(blatt)
        .rotationEffect(.degrees(-0.55))
        .shadow(color: Theme.textPrimary.opacity(0.10), radius: 12, x: 0, y: 6)
        .opacity(shown ? 1 : 0)
        // Es legt sich hin, statt zu erscheinen.
        .offset(y: shown ? 0 : 10)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1)) {
                shown = true
            }
        }
    }

    // MARK: - Kopfzeile

    private var kopf: some View {
        HStack(spacing: 8) {
            Text("WHAT I'D DO")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(Theme.danger.opacity(0.75))
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.10))
                .frame(height: 1)
            if !marks.isEmpty {
                Text("\(marks.count) note\(marks.count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        // Platz fuer das Eselsohr, sonst laeuft die Linie darunter durch.
        .padding(.trailing, Self.dogEar - 4)
    }

    private var unterschrift: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("— Clavic")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Theme.textSecondary)
                .rotationEffect(.degrees(-1.6))
        }
    }

    // MARK: - Das Blatt

    private var blatt: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.papier)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.07), lineWidth: 1)
                )
                // Die Randlinie des Schulhefts. Sie macht die Form.
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.danger.opacity(0.22))
                        .frame(width: 1)
                        .padding(.leading, 11)
                        .padding(.vertical, 5)
                }
            eselsohr
        }
    }

    /// Umgeknickte Ecke: ein Dreieck in Hintergrundfarbe schneidet die Ecke weg,
    /// ein zweites, dunkleres liegt als umgeschlagenes Blatt darunter.
    private var eselsohr: some View {
        ZStack(alignment: .topTrailing) {
            Triangle(corner: .topRight)
                .fill(Theme.background)
            Triangle(corner: .bottomLeft)
                .fill(Theme.textPrimary.opacity(0.09))
        }
        .frame(width: Self.dogEar, height: Self.dogEar)
        .padding(.trailing, 0.5)
        .padding(.top, 0.5)
    }
}

private struct Triangle: Shape {
    enum Corner { case topRight, bottomLeft }
    let corner: Corner

    func path(in r: CGRect) -> Path {
        var p = Path()
        switch corner {
        case .topRight:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        case .bottomLeft:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}
