//
//  DirectorGreeting.swift
//  Clavic
//
//  Der Gruß, der beim Öffnen steht, solange der Wurf läuft.
//
//  Eine Zeile, fett, groß — sonst nichts. Keine zweite Zeile mit Erklärung:
//  die war beim letzten Anlauf zu klein zum Lesen und hat den Auftakt
//  zugestellt. Was hier steht, ist eine Ansage, kein Hinweistext.
//
//  Zwanzig Sprüche, bei jedem Start ein anderer. Sie klingen alle nach der
//  Figur: knapp, direkt, mit einem Augenzwinkern Richtung Chamäleon (Farbe
//  wechseln, sich anpassen, die Haut tauschen).
//
//  Die Animation dauert knapp eine Sekunde: die Zeile schiebt sich von unten
//  herein, während eine weiche Kante von links nach rechts über sie wischt und
//  sie freigibt. Ein Wischer statt eines Einblendens, weil er die Zeile LIEST,
//  wie man sie liest.
//
//  WICHTIG: die Animation hängt an `trigger`, NICHT an `onAppear`, UND sie
//  startet mit einer halben Sekunde Vorlauf.
//
//  Beides ist teuer gelernt. `onAppear` feuert, lange bevor etwas zu sehen
//  ist. `trigger` ist der Zähler, der auch den Wurf auslöst — er wird erst
//  hochgezählt, wenn ein Bild wirklich gezeichnet wurde. Das reichte aber
//  immer noch nicht: der Startbildschirm blendet danach noch über, und in der
//  Bildschirmaufnahme sprang die Zeile in EINEM Einzelbild von unsichtbar auf
//  fertig — der ganze Wischer lag hinter der Überblendung.
//
//  Gemessen liegen zwischen dem gezeichneten Bild und dem, was man sieht, gut
//  eine halbe Sekunde. Genau so lange wartet die Animation. Für den Wurf
//  spielt derselbe Versatz keine Rolle, der läuft 3,5 Sekunden.
//
//  Nachgemessen in der Bildschirmaufnahme (30 Bilder/s): der Wurf startet bei
//  2,2 s, der Wischer läuft von 2,65 s bis 3,6 s, die Karten landen bei 5,7 s.
//  Die Zeile steht also rund zwei Sekunden ruhig da, bevor sie abgelöst wird.
//
//  Ein Wort je Spruch steht in Akzentblau — markiert im Text mit *Sternchen*.
//  Das ist die einzige Farbe außer der Kontur, und sie hält die Zeile mit dem
//  Maskottchen zusammen.
//

import SwiftUI

enum DirectorGreetings {
    /// Der Teil zwischen zwei `*` wird in Akzentfarbe gesetzt.
    static let all: [String] = [
        "What are we *shooting*?",
        "Let's change the *light*.",
        "Name a *look*.",
        "I'll *blend in*.",
        "Ready when *you* are.",
        "Show me something *good*.",
        "Any *mood* you want.",
        "Time to *reshoot*.",
        "Let's get *cinematic*.",
        "Pick a *color*.",
        "New day, new *look*.",
        "What's the *vibe*?",
        "Let's try something *odd*.",
        "Your camera, my *eye*.",
        "One photo, many *skins*.",
        "Let's *repaint* it.",
        "Bring me a *photo*.",
        "Make it *unmistakable*.",
        "Let's *not be subtle*.",
        "Choose your *weather*."
    ]

    static func random() -> String { all.randomElement() ?? all[0] }
}

struct DirectorGreetingView: View {
    /// Zählt bei jedem Wurf hoch. Jede Änderung sucht einen neuen Spruch aus
    /// und lässt ihn hereinwischen.
    let trigger: Int

    @State private var markup = DirectorGreetings.random()
    /// 0 = noch verdeckt, 1 = ganz freigegeben.
    @State private var reveal: CGFloat = 0
    @State private var lift: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vorlauf, bis die Überblendung des Startbildschirms durch ist. Im
    /// Simulator gemessen, nicht geschätzt.
    private static let leadIn: Double = 0.45

    var body: some View {
        styled
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: lift)
            .mask(wipe)
            .onChange(of: trigger) { _, _ in
                markup = DirectorGreetings.random()
                run()
            }
            .onAppear {
                // Nur der Nachzügler-Fall: der Bereich wird neu aufgebaut,
                // während der Zähler schon steht (etwa nach einem Tabwechsel).
                if trigger > 0 { run() }
            }
    }

    /// Baut die Zeile aus den Abschnitten zwischen den Sternchen. Ungerade
    /// Abschnitte sind die betonten.
    private var styled: Text {
        markup.components(separatedBy: "*").enumerated().reduce(Text("")) { line, part in
            line + Text(part.1).foregroundStyle(part.0 % 2 == 1 ? Theme.accent : Theme.textPrimary)
        }
    }

    /// Die weiche Kante, die über die Zeile wandert.
    ///
    /// ACHTUNG: hier wird ein FESTER Verlauf verschoben, nicht ein Verlauf mit
    /// wandernden Stützstellen. SwiftUI interpoliert die `location`-Werte eines
    /// `LinearGradient` nicht — die Maske ist damit gesprungen statt gewischt,
    /// in der Bildschirmaufnahme nachgemessen. Ein `offset` dagegen wird
    /// animiert.
    private var wipe: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Der Verlauf ist breiter als die Zeile: der weiche Teil hängt
            // rechts über, damit die Buchstaben auftauchen statt zu erscheinen.
            let soft = max(w * 0.30, 1)
            let total = w + soft
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: w / total),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: total, height: geo.size.height)
            // reveal 0 → ganz links außerhalb, nichts frei.
            // reveal 1 → deckt die Zeile vollständig.
            .offset(x: (reveal - 1) * total)
        }
    }

    private func run() {
        guard !reduceMotion else { reveal = 1; lift = 0; return }
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) { reveal = 0; lift = 22 }
        // easeInOut, nicht easeOut: easeOut legt 80 % der Strecke im ersten
        // Drittel zurück — nachgemessen war der Wischer dann nach einer halben
        // Sekunde durch, obwohl er eine ganze dauern sollte.
        withAnimation(.easeInOut(duration: 1.0).delay(Self.leadIn)) { reveal = 1 }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(Self.leadIn)) { lift = 0 }
    }
}

#Preview {
    DirectorGreetingView(trigger: 1)
    .padding(Theme.screenPadding)
    .background(Theme.background)
}
