//
//  DirectorTrendCards.swift
//  Clavic
//
//  Die Trend-Looks direkt am Start waehlbar, sobald ein Foto liegt.
//
//  WARUM SIE HIERHER GEHOEREN. Bisher kamen die Trends erst NACH der Bildlesung
//  des Directors — man musste erst „See what he'd do" druecken und abwarten, um
//  ueberhaupt zu sehen, dass es sie gibt. Wer wusste, dass er Golden Hour will,
//  musste trotzdem durch die Beratung.
//
//  Jetzt stehen sie mit Namen und Vorschau da. Der Director wird dadurch nicht
//  uebergangen: Wer eine Karte antippt, bekommt trotzdem seine Lesung des Fotos
//  — sie fliesst nur in DIESEN einen Look, statt eine Auswahl vorzuschlagen.
//  Vorher: „Was soll ich machen?" Jetzt zusaetzlich: „Mach mir das hier, aber
//  richtig fuer dieses Bild."
//
//  Gleiche Bauweise wie `DirectorToolCards` — Bild oben, Titel und Zeile
//  darunter, dieselbe Ecke, derselbe Rand. Zwei verschiedene Kartenstile auf
//  einem Bildschirm haetten so ausgesehen, als kaemen sie aus zwei Apps.
//

import SwiftUI

struct DirectorTrendCards: View {
    /// Wird mit dem gewaehlten Look aufgerufen.
    var onPick: (TikTokTrends.Look) -> Void = { _ in }

    private static let kartenBreite: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or pick a look")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TikTokTrends.all) { look in
                        karte(look)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                // Ohne das schneidet der Schatten der ersten und letzten Karte
                // an der Scroll-Kante ab.
                .padding(.vertical, 4)
            }
        }
    }

    private func karte(_ look: TikTokTrends.Look) -> some View {
        Button { onPick(look) } label: {
            VStack(alignment: .leading, spacing: 7) {
                // Das „after"-Asset zeigt, was der Look tut. Faellt es aus,
                // bleibt die Flaeche ruhig statt ein Fragezeichen zu zeigen —
                // eine fehlende Vorschau ist kein Grund, die Karte zu verlieren.
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(width: Self.kartenBreite)
                    .background(Theme.surfaceHigh)
                    .overlay {
                        Image(look.after)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(look.title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(look.caption)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .frame(width: Self.kartenBreite, alignment: .leading)
            }
            .padding(7)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Theme.textPrimary.opacity(0.10), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}
