//
//  DirectorTrendRow.swift
//  Clavic
//
//  Die Trends als schlichte Wischreihe.
//
//  HIER LAG EIN KRANZ. Die Karten sassen auf einem gedachten Rad, kippten mit,
//  verloren Farbe und tauchten zu den Raendern hin weg. Das sah gut aus und
//  war die falsche Form: ein Kranz ist eine Buehne, und Trends sind der DRITTE
//  Weg dieses Bildschirms. Er hat mehr Aufmerksamkeit eingefordert, als ihm
//  zusteht — und er brauchte Sonderregeln fuer alles: eine Maske gegen den
//  abgeschnittenen Rand, ein Fenster gegen das Ruckeln, eine Pruefung gegen
//  das Mitdrehen beim senkrechten Scrollen.
//
//  Eine waagerechte Reihe kann das alles von Haus aus. Sie rastet ein, sie
//  scrollt nicht mit, wenn man die Seite bewegt, und sie sagt ohne Kunstgriff:
//  hier liegen mehrere, wisch weiter.
//
//  DIE KARTE IST DIE AUS DER LIBRARY: Bild im Hochformat, Ecke 16, Name
//  darunter. Wer dort seine Bilder ansieht, erkennt hier sofort, dass das
//  etwas zum Auswaehlen ist.
//
//  ES WIRD NICHTS GERENDERT, wenn man wischt. Wischen zeigt nur; bezahlt wird
//  der Knopf darunter.
//

import SwiftUI

struct DirectorTrendRow: View {
    let trends: [DirectorAPI.Option]
    /// Der Trend, den der Director fuer DIESES Foto vorn sieht.
    var besterID: String? = nil
    let sourcePhoto: Data?
    /// Aus, solange das Pop-up offen ist — dann sieht sie ohnehin niemand.
    var isAnimating: Bool = true
    @Binding var gewaehlt: DirectorAPI.Option?
    /// Meldet die erste echte Benutzung — Wischen oder Antippen.
    var onBeruehrt: () -> Void = {}

    private static var kartenBreite: CGFloat { 152 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(trends) { trend in
                    Button { waehle(trend) } label: { karte(trend) }
                        .buttonStyle(.plain)
                        .scrollTransition(.interactive, axis: .horizontal) { inhalt, phase in
                            // Nur angedeutet: die Karten am Rand treten leicht
                            // zurueck. Kein Kippen, kein Verblassen — das war
                            // der Kranz.
                            inhalt.opacity(1 - abs(phase.value) * 0.25)
                        }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.screenPadding)
        }
        .scrollTargetBehavior(.viewAligned)
        // Der Inhalt endet buendig mit dem Textspiegel, laeuft beim Wischen
        // aber ueber die volle Breite.
        .scrollClipDisabled()
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onChanged { wert in
                let dx = abs(wert.translation.width), dy = abs(wert.translation.height)
                guard dx > 24, dx > dy * 1.6 else { return }
                onBeruehrt()
            }
        )
    }

    private func karte(_ trend: DirectorAPI.Option) -> some View {
        let aktiv = trend.id == gewaehlt?.id
        return VStack(alignment: .leading, spacing: 7) {
            Color.clear
                .aspectRatio(0.78, contentMode: .fit)
                .frame(width: Self.kartenBreite)
                .background(Theme.surfaceHigh)
                .overlay { bild(trend) }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(aktiv ? Theme.accent : Theme.textPrimary.opacity(0.08),
                                      lineWidth: aktiv ? 2.5 : 1)
                )
                .overlay(alignment: .topLeading) {
                    if trend.id == besterID {
                        Text("BEST FOR THIS PHOTO")
                            .font(.system(size: 7.5, weight: .black, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.accent, in: Capsule())
                            .padding(6)
                    }
                }

            Text(trend.label)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(aktiv ? Theme.accent : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.kartenBreite, alignment: .leading)
        }
    }

    /// Ein geprüfter Trend zeigt sein Vorher/Nachher-Paar. Alles andere faellt
    /// auf ein Einzelbild zurueck.
    @ViewBuilder
    private func bild(_ trend: DirectorAPI.Option) -> some View {
        if let look = TikTokTrends.look(id: trend.id) {
            TrendPhotoPreview(look: look, isAnimating: isAnimating)
        } else if let name = trend.preview, name.hasPrefix("http"), let url = URL(string: name) {
            AsyncImage(url: url) { phase in
                if let bild = phase.image { bild.resizable().scaledToFill() }
                else { Rectangle().fill(Theme.surfaceHigh) }
            }
        } else if let name = trend.preview, UIImage(named: name) != nil {
            Image(name).resizable().scaledToFill()
        } else if let data = sourcePhoto, trend.mode.keepsPhoto, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        }
    }

    private func waehle(_ trend: DirectorAPI.Option) {
        onBeruehrt()
        withAnimation(.smooth(duration: 0.22)) {
            gewaehlt = trend.id == gewaehlt?.id ? nil : trend
        }
    }
}
