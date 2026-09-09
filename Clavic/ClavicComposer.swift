//
//  ClavicComposer.swift
//  Clavic
//
//  DIE EINE TEXTLEISTE DER APP.
//
//  Sie stand zweimal im Quelltext: einmal im Chat-Tab (`ChatEditView`), einmal
//  im Director (`AgentView`). Beide waren absichtlich gleich gebaut — gleiches
//  Glas, gleiche Ecke, gleiche Kurve — und genau das ist der Grund, warum sie
//  nicht zweimal existieren duerfen. Zwei Kopien einer bewusst identischen
//  Sache driften auseinander, sobald jemand nur eine von beiden anfasst.
//
//  Was hier drin liegt, ist die Leiste selbst: Feld, Glas, Rundung, Polster,
//  Wachstum bis acht Zeilen, Fokus und Absendetaste.
//
//  Was NICHT hier drin liegt, sind die Knoepfe daneben. Der Chat braucht Plus,
//  Kamera, Bild/Video-Schalter und „Apply"; der Director braucht Schliessen
//  und Senden. Die reicht der Aufrufer als `aktionen` herein — eine Leiste,
//  zwei Bestueckungen.
//
//  DIE KURVE GEHOERT DAZU. Ohne eigene Animation auf `text` springt die Leiste
//  bei jedem Zeilenumbruch hart um. Ausloeser ist der TEXT, nicht der Fokus —
//  das war in beiden Kopien schon so und wandert mit hierher.
//

import SwiftUI

struct ClavicComposer<Aktionen: View>: View {
    @Binding var text: String
    let placeholder: String
    /// Der Fokus liegt beim Aufrufer: er entscheidet, wann die Leiste das
    /// Wort bekommt, und die Tastatur haengt an seiner Ansicht.
    @FocusState.Binding var fokus: Bool
    /// Was die Absendetaste der Tastatur ausloest.
    var onSubmit: () -> Void = {}
    @ViewBuilder let aktionen: () -> Aktionen

    /// Dieselbe Kurve fuer alles, was sich an dieser Leiste bewegt.
    static var motion: Animation { .smooth(duration: 0.3) }

    var body: some View {
        VStack(spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.system(size: 16.5, weight: .medium, design: .rounded))
                // Waechst mit dem Text mit — bis zu acht Zeilen statt fuenf.
                // Bei fuenf war schon Schluss, obwohl darueber genug Platz ist;
                // laengere Anweisungen liefen dann in ein winziges Scrollfeld.
                .lineLimit(1...8)
                .focused($fokus)
                .submitLabel(.send)
                .onSubmit(onSubmit)
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Self.motion, value: text)

            HStack(spacing: 8) { aktionen() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Liquid Glass (iOS 26): die Leiste bricht und beugt das, was darunter
        // durchscrollt, statt eine deckende Flaeche zu sein.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        // Glas ist optisch geschlossen, hat aber durchsichtige Luecken — ohne
        // eigene Trefferflaeche faellt der Tipp durch auf das, was darunter
        // liegt.
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
