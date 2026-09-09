//
//  DirectorToolCards.swift
//  Clavic
//
//  Die beiden Werkzeuge am Start: etwas wegnehmen, oder groesser machen.
//
//  SIE ZEIGEN, WAS SIE TUN. Ein schmaler Balken mit „Remove objects" verlangt,
//  dass man es sich vorstellt. Diese Karten zeigen es:
//
//    • „Remove objects" traegt ein echtes Foto mit dem magentafarbenen Strich
//      darauf — genau so sieht das Werkzeug im Gebrauch aus. Wer die Karte
//      sieht, hat die Bedienung schon verstanden.
//    • „4K Upscale" zeigt Vorher und Nachher als wandernde Trennlinie
//      (`BeforeAfterSlider`), dieselbe Darstellung wie auf den Vorlagenkacheln.
//
//  Der Strich ist NICHT gemalt, sondern gezeichnet: eine `Path`-Kurve in
//  derselben Magenta wie die echte Maske. Ein eigenes Asset dafuer waere ein
//  Bild, das jemand pflegen muss; die Kurve ist immer aktuell.
//

import SwiftUI

struct DirectorToolCards: View {
    var onSwap: () -> Void = {}
    var onRemove: () -> Void = {}
    var onUpscale: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            // DER SWAP IST AUCH EINE KARTE, und die breiteste.
            //
            // Er stand hier als schmale Zeile ueber den beiden anderen — also
            // genau das, was an den alten Knoepfen falsch war: ein Balken mit
            // Text, waehrend daneben Bilder zeigen, worum es geht. Jetzt sind
            // alle drei Werkzeuge gleich auswaehlbar, und das auffaelligste
            // bekommt die volle Breite.
            karte(titel: "Put yourself in any photo",
                  hinweis: "Pinterest link or a photo you like",
                  seiten: 1.5,
                  tap: onSwap) { swapBild }

            HStack(spacing: 12) {
                karte(titel: "Remove objects",
                      hinweis: "Paint over it — it's gone",
                      tap: onRemove) { entfernenBild }

                karte(titel: "4K Upscale",
                      hinweis: "Sharper, bigger, cleaner",
                      tap: onUpscale) { upscaleBild }
            }
        }
    }

    private func karte<Inhalt: View>(titel: String, hinweis: String,
                                     seiten: CGFloat = 1.15,
                                     tap: @escaping () -> Void,
                                     @ViewBuilder bild: () -> Inhalt) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .aspectRatio(seiten, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surfaceHigh)
                    .overlay { bild() }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(titel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(hinweis)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Theme.textPrimary.opacity(0.07), radius: 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Die drei Bilder

    /// VORHER UND NACHHER NEBENEINANDER, beschriftet.
    ///
    /// Ein einzelnes Bild kann diesen Weg nicht erklaeren: man sieht eine
    /// Person in einer Szene und weiss nicht, ob das die Vorlage ist oder das
    /// Ergebnis. Erst das Paar zeigt die Sache — dieselbe Szene, dieselbe
    /// Pose, dasselbe Kleid, andere Person.
    ///
    /// NEBENEINANDER STATT SCHIEBEREGLER. Die beiden Aufnahmen sind Hochformat;
    /// ein waagerechter Regler auf einer breiten Karte haette von beiden nur
    /// ein Band aus der Mitte gezeigt und die Gesichter abgeschnitten — und
    /// genau die Gesichter sind hier der Punkt. Das Paar ist deshalb als EIN
    /// Bild gesetzt (`preview_swap_pair`), jede Haelfte vollstaendig.
    private var swapBild: some View {
        ZStack {
            if let ui = UIImage(named: "preview_swap_pair") {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if let ui = UIImage(named: "preview_pinterest_swap") {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.surfaceHigh)
            }

            // Die Beschriftung sitzt auf den Haelften, nicht im Bild: so bleibt
            // sie in unserer Schrift und laesst sich aendern, ohne das Asset
            // neu zu bauen.
            HStack(spacing: 0) {
                marke("BEFORE")
                marke("AFTER")
            }
        }
    }

    private func marke(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .black, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.42), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(8)
    }

    @ViewBuilder
    private var entfernenBild: some View {
        ZStack {
            if let ui = UIImage(named: "preview_image_edit_before") {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.surfaceHigh)
            }
            // Derselbe Magenta wie die echte Maske (`EraseMask`), damit die
            // Karte und das Werkzeug dieselbe Sprache sprechen.
            PinselStrich()
                .stroke(Color(red: 1, green: 0.16, blue: 0.78).opacity(0.78),
                        style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))
                .blur(radius: 0.4)
        }
    }

    @ViewBuilder
    private var upscaleBild: some View {
        if let vorher = UIImage(named: "preview_image_upscale_before"),
           let nachher = UIImage(named: "preview_image_upscale_after") {
            BeforeAfterSlider(before: vorher, after: nachher, axis: .vertical,
                              showLabels: false, showDivider: false, isAnimating: true)
                .allowsHitTesting(false)
        } else {
            Rectangle().fill(Theme.surfaceHigh)
        }
    }
}

/// Ein kurzer, leicht krummer Strich — so, wie ein Daumen ueber ein Objekt
/// wischt. Bewusst nicht gerade: eine Gerade sieht nach Balken aus, nicht nach
/// Hand.
private struct PinselStrich: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.24, y: r.minY + r.height * 0.62))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.72, y: r.minY + r.height * 0.48),
                   control1: CGPoint(x: r.minX + r.width * 0.38, y: r.minY + r.height * 0.74),
                   control2: CGPoint(x: r.minX + r.width * 0.60, y: r.minY + r.height * 0.62))
        return p
    }
}
