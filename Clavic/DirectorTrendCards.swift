//
//  DirectorTrendCards.swift
//  Clavic
//
//  Die Trend-Looks am Start — als Liste, nicht als Karussell.
//
//  WARUM SIE HIERHER GEHOEREN. Bisher kamen die Trends erst NACH der Bildlesung
//  des Directors — man musste erst „See what he'd do" druecken und abwarten, um
//  ueberhaupt zu sehen, dass es sie gibt. Wer wusste, dass er Golden Hour will,
//  musste trotzdem durch die Beratung.
//
//  WARUM UNTEREINANDER STATT NEBENEINANDER. Erst standen sie in einer
//  waagerechten Reihe. Auf dem Geraet waren davon zweieinhalb Karten zu sehen,
//  die dritte lief am rechten Rand ins Nichts — von sechs Looks kannte man drei
//  und ahnte nichts von den anderen. Eine waagerechte Reihe versteckt, was sie
//  zeigen soll. Untereinander steht jeder Look mit Namen und Zeile da, und die
//  Liste hat keinen Rand, hinter dem noch etwas liegen koennte.
//
//  UND DER SCHATTEN WURDE ABGESCHNITTEN. Die Reihe lag in einer eigenen
//  `ScrollView`; die schneidet an ihren Kanten, und zwar mitten durch den
//  Schatten der ersten und letzten Karte. Man sah eine harte senkrechte Naht
//  neben den Karten. Ein `padding` half nur gegen die obere und untere Kante,
//  nicht gegen die seitlichen. Ohne eigene ScrollView gibt es nichts mehr, das
//  schneiden koennte.
//

import PhotosUI
import SwiftUI

struct DirectorTrendCards: View {
    /// Wird mit dem gewaehlten Look aufgerufen.
    var onPick: (TikTokTrends.Look) -> Void = { _ in }

    /// Liegt noch kein Foto? Dann fuehrt eine Zeile zuerst in die Mediathek.
    ///
    /// Die Looks stehen auch ohne Foto da, damit man SIEHT, was die App kann,
    /// bevor man etwas hergibt. Ein Tipp darf dann aber nicht ins Leere laufen:
    /// er merkt sich den Look und fragt nach dem Bild. Ein deaktivierter oder
    /// stummer Knopf waere die schlechtere Antwort — er zeigt etwas Schoenes und
    /// weigert sich dann, ohne zu sagen warum.
    var photoMissing: Bool = false
    @Binding var photoSelections: [PhotosPickerItem]

    private static let bildBreite: CGFloat = 58
    private static let bildHoehe: CGFloat = 74

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(photoMissing ? "Looks you can pick" : "Or pick a look")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 9) {
                ForEach(TikTokTrends.all) { look in
                    if photoMissing {
                        PhotosPicker(selection: $photoSelections,
                                     maxSelectionCount: 1,
                                     matching: .images) {
                            zeile(look)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { onPick(look) })
                    } else {
                        Button { onPick(look) } label: { zeile(look) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    /// Eine Zeile: Vorschau links, Name und Beschreibung rechts.
    ///
    /// Das „after"-Asset zeigt, was der Look tut. Faellt es aus, bleibt die
    /// Flaeche ruhig statt ein Fragezeichen zu zeigen — eine fehlende Vorschau
    /// ist kein Grund, die Zeile zu verlieren.
    private func zeile(_ look: TikTokTrends.Look) -> some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: Self.bildBreite, height: Self.bildHoehe)
                .background(Theme.surfaceHigh)
                .overlay {
                    Image(look.after)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(look.title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(look.caption)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 1)
        )
        // Weich und tief statt hart und nah: ein enger, dunkler Schatten zeichnet
        // eine sichtbare Kante um die Karte, ein weiter heller laesst sie
        // schweben. Gemessen am Rest der Ansicht — die Werkzeugkarten liegen
        // auf denselben Werten.
        .shadow(color: Theme.textPrimary.opacity(0.07), radius: 12, x: 0, y: 5)
    }
}
