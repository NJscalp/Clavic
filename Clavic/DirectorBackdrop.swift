//
//  DirectorBackdrop.swift
//  Clavic
//
//  Der Hintergrund des Director-Tabs.
//
//  WAS VORHER DA WAR.
//  `DirectorScenery`: sieben gezeichnete Requisiten an den Raendern, leicht
//  schwingend. Gemeint als Werkstatt, gelesen als Stoerung — hinter der
//  Trend-Zeile standen erkennbare Umrisse, und alles, was man als GEGENSTAND
//  erkennt, zieht Blick von der Karte ab, die man antippen soll.
//
//  WAS ES JETZT IST.
//  Vier sehr weiche Farbfelder in der Themenpalette, gross, randlos, langsam
//  driftend. Nichts davon hat eine Form, die man benennen kann. Der Blick
//  bleibt an den Karten haengen; der Hintergrund traegt nur die Flaeche.
//
//  KEIN `.blur()`.
//  Ein Weichzeichner ueber den ganzen Bildschirm kostet jeden Frame Fuellrate
//  und schneidet ausserdem an seinen eigenen Grenzen ab — genau der Fehler,
//  der beim Trend-Kranz oben und unten die Kante sichtbar gemacht hat. Ein
//  `RadialGradient` mit gestaffelten Stopps IST bereits weich, kostet nichts
//  und hat keine Grenze, an der er abschneiden koennte.
//
//  WARUM ES OBEN SCHWACH IST.
//  Die Videos der Figur haben kein Alpha; sie sind auf Creme gebacken
//  (#F7F3ED, praktisch `Theme.background`). Liegt ein kraeftiger Verlauf
//  dahinter, steht der Videokasten als helles Rechteck im Bild. Die Figur
//  sitzt in beiden Zustaenden in der oberen Haelfte, deshalb blendet die
//  Maske das Leuchten von oben herein statt es dort voll stehen zu lassen.
//

import SwiftUI

struct DirectorBackdrop: View {
    /// Waehrend der Director liest, atmet es etwas weiter — dieselbe Regel wie
    /// ueberall sonst: der Arbeitszustand ist am Bildschirm ablesbar.
    var busy: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    private struct Wolke {
        /// Mitte, Anteil der Flaeche. Werte ausserhalb 0…1 sind Absicht: die
        /// Quelle liegt vor dem Bildrand, sichtbar ist nur ihr Auslauf.
        let x: CGFloat
        let y: CGFloat
        /// Radius, Anteil der BREITE — auch in der Hoehe, sonst wird das Feld
        /// auf einem langen Bildschirm zur Ellipse und bekommt eine Richtung.
        let radius: CGFloat
        let farbe: Color
        let deckkraft: Double
        /// Weg von Ruhe- zu Endlage in Punkten. GEMESSEN, nicht geschaetzt:
        /// mit zweistelligen Wegen ueber 20 s aendert sich ueber 6 s kein
        /// einziger Pixelwert — der Verlauf ist so flach, dass die Bewegung
        /// unter der Farbquantisierung verschwindet. Das war Rechenzeit ohne
        /// Wirkung. Bei rund 50 pt bewegt sich das Feld ueber eine Minute
        /// sichtbar, pro Sekunde aber immer noch unter zwei Punkten — als
        /// Bewegung erkennt man das nicht.
        let weg: CGSize
        let atem: CGFloat
        /// Sekunden fuer einen Weg. Bewusst teilerfremd zueinander, sonst
        /// treffen sich zwei Felder regelmaessig in derselben Lage und der
        /// Bildschirm bekommt einen Puls.
        let takt: Double
    }

    private static let wolken: [Wolke] = [
        // Gross und links draussen: traegt die Flaeche, ohne je eine Kante zu
        // zeigen.
        Wolke(x: -0.12, y: 0.26, radius: 1.00,
              farbe: Theme.accentLight, deckkraft: 0.26,
              weg: CGSize(width: 58, height: -42), atem: 1.10, takt: 23),
        // Rechts unten, das kraeftigere Blau — es zieht den Blick nach unten,
        // wo die Trend-Zeile und die Eingabe liegen.
        Wolke(x: 1.02, y: 0.56, radius: 0.94,
              farbe: Theme.accent, deckkraft: 0.17,
              weg: CGSize(width: -46, height: 52), atem: 0.90, takt: 29),
        // Der Limeton der Augen, unter der linken unteren Ecke. Mittig und
        // breiter gestellt lag er als durchgehendes Band an der Unterkante —
        // das liest sich als Farbstich, nicht als Licht. In der Ecke ist es
        // ein Schein, und die Diagonale kuehl-oben/warm-unten bleibt.
        Wolke(x: 0.26, y: 1.02, radius: 0.80,
              farbe: Theme.aiActive, deckkraft: 0.19,
              weg: CGSize(width: 40, height: -31), atem: 1.13, takt: 19),
        // Kleiner Aufheller oben rechts, damit die Kopfzeile nicht in einer
        // toten Ecke steht.
        Wolke(x: 0.98, y: 0.02, radius: 0.64,
              farbe: Theme.accentLight, deckkraft: 0.18,
              weg: CGSize(width: -34, height: 40), atem: 1.09, takt: 26)
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Theme.background
                ForEach(Array(Self.wolken.enumerated()), id: \.offset) { _, w in
                    feld(w, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
            // OBEN BEI NULL ANFANGEN, nicht bei 0,46.
            //
            // Ueber dem Bildschirm liegt die Kopfzeile aus `ContentView` —
            // eine deckende Flaeche in `Theme.background`. Begann das
            // Farbleuchten schon dort, stand unter der Leiste eine harte
            // waagerechte Kante: Creme oben, getoent unten. Genau die Stelle,
            // an der auch die Karten beim Scrollen durchlaufen; das las sich
            // als Fehler im Hintergrund.
            //
            // Deshalb ist die Maske auf Hoehe der Leiste (rund 15 % der
            // Bildschirmhoehe) exakt null. Dort IST der Hintergrund
            // `Theme.background` — dieselbe Farbe wie die Leiste, keine Kante
            // moeglich. Erst darunter blendet die Farbe ein, langsam, mit
            // wachsender Steigung.
            //
            // Verloren geht dabei nichts: die oberen 16 % sind Statusleiste
            // und Kopfzeile. Gefaerbt wird, wo gearbeitet wird.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.16),
                        .init(color: .black.opacity(0.30), location: 0.34),
                        .init(color: .black.opacity(0.72), location: 0.50),
                        .init(color: .black, location: 0.66),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // Die Maske frisst auch das Creme darunter. Es muss deshalb ein
            // zweites Mal darunter liegen, ungemaskt — sonst scheint durch den
            // oberen Rand die Systemfarbe.
            .background(Theme.background)
        }
        .allowsHitTesting(false)
        .onAppear { phase = true }
    }

    private func feld(_ w: Wolke, in size: CGSize) -> some View {
        let r = size.width * w.radius
        let staerke = busy ? 1.18 : 1.0
        let laeuft = !reduceMotion && phase

        return Circle()
            .fill(
                RadialGradient(
                    // Fuenf Stopps statt zweier: ein linearer Auslauf auf
                    // `.clear` zeichnet einen sichtbaren Ring an der Grenze.
                    // Diese Staffelung ahmt einen weichen Abfall nach.
                    gradient: Gradient(stops: [
                        .init(color: w.farbe.opacity(w.deckkraft * staerke), location: 0),
                        .init(color: w.farbe.opacity(w.deckkraft * staerke * 0.72), location: 0.30),
                        .init(color: w.farbe.opacity(w.deckkraft * staerke * 0.34), location: 0.56),
                        .init(color: w.farbe.opacity(w.deckkraft * staerke * 0.10), location: 0.79),
                        .init(color: w.farbe.opacity(0), location: 1)
                    ]),
                    center: .center, startRadius: 0, endRadius: r
                )
            )
            .frame(width: r * 2, height: r * 2)
            .scaleEffect(laeuft ? w.atem : 1)
            .offset(x: laeuft ? w.weg.width : 0,
                    y: laeuft ? w.weg.height : 0)
            .position(x: size.width * w.x, y: size.height * w.y)
            // Jede Wolke bekommt ihre EIGENE Animation. Ein gemeinsames
            // `withAnimation` gaebe allen denselben Takt, und vier Felder im
            // Gleichschritt liest man sofort als Maschine.
            .animation(
                reduceMotion ? nil
                             : .easeInOut(duration: w.takt).repeatForever(autoreverses: true),
                value: phase
            )
            .animation(.easeInOut(duration: 0.9), value: busy)
    }
}

#Preview {
    ZStack {
        DirectorBackdrop()
        VStack(spacing: 12) {
            Text("Clavic").font(.title2.bold())
            RoundedRectangle(cornerRadius: 20).fill(Theme.surface).frame(height: 150)
            Spacer()
        }
        .padding()
    }
    .ignoresSafeArea()
}
