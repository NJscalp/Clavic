//
//  DirectorAmbience.swift
//  Clavic
//
//  Der ruhige Farbschimmer unter der Figur.
//
//  Drei weiche Flächen in ihren eigenen Farben — Körperblau, Kamm-Hellblau und
//  der Grünton der Augen —, sehr blass und stark weichgezeichnet. Sie atmen
//  langsam und driften, jede in eigenem Takt, damit nie ein sichtbarer
//  Rhythmus entsteht. Kein Muster, keine Kanten, nichts zum Ansehen: es soll
//  auffallen, wenn es FEHLT, nicht wenn es da ist.
//
//  EINSCHRÄNKUNG, bewusst so: die Wurf- und Ruhevideos der Figur sind auf
//  deckendes Creme aufgezogen (Alpha im Player sah ausgewaschen aus). Liegt
//  eine Farbfläche hinter der Figur, wird genau dieser Cremekasten als weißes
//  Rechteck sichtbar — im Simulator geprüft. Deshalb liegt der Schimmer NUR
//  unter ihr, im Bereich des Grußes und der Karten, und läuft oben und unten
//  weich aus.
//

import SwiftUI

struct DirectorAmbience: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = max(geo.size.height, 1)
            ZStack {
                blob(Theme.accentLight, size: w * 0.90, opacity: 0.21)
                    .position(x: w * 0.20, y: h * 0.40)
                    .scaleEffect(breathe ? 1.08 : 0.94)

                blob(Theme.accent, size: w * 0.62, opacity: 0.11)
                    .position(x: w * 0.88, y: h * 0.56)
                    .scaleEffect(breathe ? 0.92 : 1.08)

                blob(Theme.aiActive, size: w * 0.44, opacity: 0.16)
                    .position(x: w * 0.46, y: h * 0.92)
                    .scaleEffect(breathe ? 1.10 : 0.96)
            }
            .frame(width: w, height: h)
            .blur(radius: 44)
            // Oben und unten auslaufen lassen: eine harte Kante gegen das
            // Video der Figur oder gegen die Eingabezeile würde sofort
            // auffallen.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.16),
                        .init(color: .black, location: 0.84),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
    }
}

#Preview {
    DirectorAmbience()
        .frame(height: 420)
        .background(Theme.background)
}
