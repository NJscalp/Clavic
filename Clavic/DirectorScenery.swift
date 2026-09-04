//
//  DirectorScenery.swift
//  Clavic
//
//  Die Werkbank hat jetzt einen Raum drumherum.
//
//  WARUM ES DAS GIBT.
//  Im Director-Tab stand die Figur oben allein, und darunter war der halbe
//  Bildschirm leeres Cremeweiss — beim Lesen wie nach dem Ergebnis. Das liest
//  sich nicht wie eine Werkstatt, sondern wie eine Seite, die nicht fertig
//  geladen hat.
//
//  WAS ES IST.
//  Sieben Requisiten im Stil des Maskottchens — Sofortbilder, Filmdose,
//  Softbox, Farbfaecher, Gluehbirne, Kamera, Kaffeebecher — erzeugt mit
//  unserem eigenen Bildgenerator (Nano Banana 2), auf dieselbe Palette
//  festgelegt wie das Thema: Navy, Blau, Hellblau, Creme, Limette.
//
//  ZWEI REGELN, DIE ALLES ANDERE BESTIMMEN.
//  1. Sie liegen NUR an den Raendern und wachsen von aussen herein, teils
//     angeschnitten. Nichts liegt je hinter Text oder Foto. Deshalb ist die
//     Position nicht frei, sondern an eine Kante gebunden (`edge`).
//  2. Sie bewegen sich nach DERSELBEN Windformel wie das Blattwerk der Figur
//     (`MascotHabitat`). Eine Bewegungssprache, nicht zwei — sonst zappeln auf
//     einem Bildschirm zwei verschiedene Uhren.
//
//  Solange gelesen wird, atmet die Kulisse etwas kraeftiger; danach beruhigt
//  sie sich, ohne zu verschwinden. Bei „Bewegung reduzieren" steht sie still —
//  sichtbar bleibt sie trotzdem, denn ihre Aufgabe ist die Flaeche, nicht die
//  Animation.
//

import SwiftUI

struct DirectorScenery: View {
    /// Lauter und weiter, solange der Director liest.
    var busy: Bool = false
    /// Grunddeckkraft. Die Requisiten sind Kulisse, kein Inhalt — sie duerfen
    /// nie mit dem Foto oder den Vorschlaegen um Aufmerksamkeit ringen.
    var opacity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Edge { case left, right }

    private struct Prop {
        let asset: String
        let edge: Edge
        /// Wie weit das Stueck ueber den Bildrand hinausragt, Anteil seiner
        /// Breite. 0,3 heisst: knapp ein Drittel liegt draussen.
        let bleed: CGFloat
        /// Hoehe der Mitte, Anteil der Flaechenhoehe.
        let y: CGFloat
        /// Breite, Anteil der Flaechenbreite.
        let width: CGFloat
        let angle: Double
        /// Dauer einer vollen Schwingung in Sekunden.
        let beat: Double
        let alpha: Double

        var speed: Double { 2 * .pi / beat }
    }

    /// Verteilt ueber die ganze Hoehe, links und rechts abwechselnd, mit
    /// unterschiedlichen Takten — gleiche Takte lassen alles im Gleichschritt
    /// wippen, und das sieht sofort nach Maschine aus.
    private static let props: [Prop] = [
        Prop(asset: "prop_polaroid", edge: .left,  bleed: 0.34, y: 0.10,
             width: 0.30, angle: -13, beat: 6.2, alpha: 0.16),
        Prop(asset: "prop_lamp",     edge: .right, bleed: 0.30, y: 0.18,
             width: 0.24, angle: 9,   beat: 7.4, alpha: 0.14),
        Prop(asset: "prop_film",     edge: .right, bleed: 0.36, y: 0.46,
             width: 0.26, angle: -8,  beat: 5.6, alpha: 0.15),
        Prop(asset: "prop_swatch",   edge: .left,  bleed: 0.32, y: 0.55,
             width: 0.30, angle: 15,  beat: 6.8, alpha: 0.15),
        Prop(asset: "prop_camera",   edge: .left,  bleed: 0.30, y: 0.80,
             width: 0.24, angle: -6,  beat: 5.9, alpha: 0.14),
        Prop(asset: "prop_cup",      edge: .right, bleed: 0.33, y: 0.74,
             width: 0.20, angle: 11,  beat: 6.6, alpha: 0.14),
        // Nicht tiefer: unter 0,9 verschwindet ein Stueck hinter der
        // schwebenden Tableiste und ist umsonst geladen.
        Prop(asset: "prop_bulb",     edge: .left,  bleed: 0.36, y: 0.33,
             width: 0.19, angle: -14, beat: 7.1, alpha: 0.13)
    ]

    /// Windstaerke wie im Blattwerk: eine langsame Grundbrise, dazu eine
    /// hochpotenzierte Sinuswelle, die daraus einen seltenen, schmalen Stoss
    /// macht. Identisch zu `MascotHabitat.wind` — dieselbe Luft im Raum.
    private static func wind(at t: TimeInterval) -> Double {
        let breeze = 0.26 + 0.20 * sin(t * 0.13)
        let gust = pow(max(0, sin(t * 0.155 + 1.1)), 6) * 0.95
        return breeze + gust
    }

    var body: some View {
        GeometryReader { geo in
            if reduceMotion {
                stage(in: geo.size, t: 0)
            } else {
                // 15 Bilder/s statt der 30 des Blattwerks: ein Takt dauert
                // hier 5 bis 7 Sekunden, der Weg pro Bild ist also winzig.
                // Die Kulisse liegt hinter dem GANZEN Bildschirm — sie jede
                // zweite Anzeigezeile neu zu zeichnen waere reine Heizleistung.
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { tl in
                    stage(in: geo.size,
                          t: tl.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .allowsHitTesting(false)
        // Der Bildschirm scrollt; ohne Beschnitt haengen die Requisiten sonst
        // ueber die Tableiste hinaus.
        .clipped()
    }

    private func stage(in size: CGSize, t: TimeInterval) -> some View {
        let strength = Self.wind(at: t)
        // Beim Lesen deutlich mehr Ausschlag: die Werkstatt ist in Betrieb.
        let swingScale: Double = busy ? 3.4 : 1.5
        let bobScale: CGFloat = busy ? 7 : 3

        return ZStack {
            ForEach(Array(Self.props.enumerated()), id: \.offset) { index, p in
                let w = size.width * p.width
                let phase = Double(index) * 0.8
                let swing = sin(t * p.speed + phase) * swingScale * strength
                let bob = CGFloat(sin(t * p.speed * 0.55 + phase))
                    * bobScale * CGFloat(strength)

                Image(p.asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w)
                    .rotationEffect(.degrees(p.angle + swing))
                    .opacity(p.alpha * opacity)
                    .position(x: p.edge == .left ? w * (0.5 - p.bleed)
                                                 : size.width - w * (0.5 - p.bleed),
                              y: size.height * p.y + bob)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
