//
//  DirectorPicks.swift
//  Clavic
//
//  Was der Director nach dem Blick aufs Foto anbietet.
//
//  VIER WEGE, VON ENG NACH WEIT — und jeder ist SICHTBAR.
//
//    1. Seine zwei Vorschläge. Groß, offen, ohne Aufklappen. Zwei und nicht
//       vier: ein Creative Director sagt „das sind meine zwei besten Ideen",
//       er legt keinen Katalog hin.
//
//    2. Was gerade auf TikTok läuft — als Streifen, den man sieht, nicht als
//       Zeile, die man erst antippen muss.
//
//       DAS WAR DER FEHLER DER VORVERSION: die Trends lagen hinter einer
//       zugeklappten Zeile mit einem Pfeil. Wer nicht weiss, was dahinter
//       liegt, klappt nicht auf — man kann sich nichts vorstellen, was man
//       nicht sieht. Jetzt liegen die Vorschaubilder offen da.
//
//    3. „…or tell me your own idea" — eine kleine Glasleiste, die nach
//       unten wandert.
//
//       Sie liegt zuerst klein im Fluss, dort wo man sie braucht. Beim
//       Antippen verschwindet sie hier und die grosse Regie-Leiste steht
//       unten am Bildschirmrand — dieselbe Bewegung, die man aus dem
//       Chat-Tab kennt. Kein zweiter Ort zum Suchen.
//
//  KEIN KATALOG-KNOPF MEHR. Hier stand „Every look we have" mit allem, was
//  im Bundle liegt. Das war eine Liste, die nur ein App-Update aendern kann —
//  und Trends kommen nicht im Rhythmus von App-Updates. Was der Streifen
//  zeigt, kommt deshalb VOM SERVER (`TemplateStore`, `templates.json`):
//  neuer Trend, Bild dazu, hochgeladen, sofort drin.
//
//  ES WIRD NICHTS GERENDERT, bevor hier etwas angetippt wurde. Jeder Tipp
//  kostet Credits, deshalb ist jeder Tipp eine bewusste Entscheidung.
//

import SwiftUI

struct DirectorPicks: View {
    let picks: [DirectorAPI.Option]
    let trends: [DirectorAPI.Option]
    /// Was der Server gerade als Trend fuehrt. Kommt aus `templates.json` und
    /// braucht kein App-Update — genau dafuer ist der Streifen da.
    var serverTrends: [DirectorAPI.Option] = []
    /// true, solange die grosse Leiste unten steht. Dann ist die kleine hier
    /// weg: sie ist ja nach unten gewandert.
    var composerOpen: Bool = false
    /// false = der Wurf läuft noch.
    let landed: Bool
    let throwToken: Int
    /// Das Foto, über das gesprochen wird — liegt auf Karten, die es erhalten.
    let sourcePhoto: Data?
    var onPick: (DirectorAPI.Option) -> Void = { _ in }
    var onOwnIdea: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Der Kartenblock zeichnet über seine Layouthöhe hinaus nach oben
            // (der Nebelstreifen, aus dem sie kommen). Ohne Ausgleich schöben
            // sich die Karten über das, was darüber steht.
            vorschlaege

            if landed {
                if !alleTrends.isEmpty { trendStreifen }
                if !composerOpen { eigeneIdee }
            }
        }
        .animation(.easeOut(duration: 0.35), value: landed)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: composerOpen)
    }

    /// Vorschlaege des Directors zuerst — sie sind auf DIESES Foto sortiert —,
    /// dahinter, was der Server gerade fuehrt. Doppelte fliegen raus.
    private var alleTrends: [DirectorAPI.Option] {
        var gesehen = Set(trends.map(\.id))
        return trends + serverTrends.filter { gesehen.insert($0.id).inserted }
    }

    // MARK: - Seine zwei

    private var vorschlaege: some View {
        VStack(alignment: .leading, spacing: 8) {
            DirectorPolaroids(
                items: picks.map { PolaroidItem($0, sourcePhoto: sourcePhoto) },
                landed: landed,
                throwToken: throwToken,
                onPick: { item in
                    guard let option = picks.first(where: { $0.id == item.id }) else { return }
                    onPick(option)
                }
            )
            .padding(.top, DirectorPolaroids.topOverhang)
        }
    }

    // MARK: - Trends

    private var trendStreifen: some View {
        VStack(alignment: .leading, spacing: 9) {
            abschnitt("TRENDING ON TIKTOK", zusatz: "FOR YOU")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(alleTrends.enumerated()), id: \.element.id) { rang, trend in
                        Button { onPick(trend) } label: { trendKachel(trend, rang: rang) }
                            .buttonStyle(.plain)
                    }
                }
                // Der Streifen laeuft bis an den Bildrand und wieder heraus —
                // die angeschnittene Kachel rechts sagt, dass es weitergeht.
                .padding(.horizontal, Theme.screenPadding)
            }
            .padding(.horizontal, -Theme.screenPadding)
        }
    }

    private func trendKachel(_ trend: DirectorAPI.Option, rang: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.surfaceHigh)
                vorschau(trend)

                // Der Rang ist nicht Zierrat: die Reihenfolge ist bereits nach
                // Passung zu DIESEM Foto sortiert, und die Zahl sagt das.
                Text("#\(rang + 1)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(7)
            }
            .frame(width: 128, height: 160)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(trend.label)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(trend.caption)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(width: 128, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Theme.textPrimary.opacity(0.07), radius: 8, y: 4)
    }

    /// Das Vorschaubild einer Kachel — aus dem Bundle ODER vom Server.
    ///
    /// Ein Trend, der erst gestern hochgeladen wurde, hat kein Asset im
    /// Bundle. Sieht `preview` wie eine Adresse aus, wird es geladen; sonst
    /// bleibt es der alte Weg ueber den Asset-Katalog.
    @ViewBuilder
    private func vorschau(_ trend: DirectorAPI.Option) -> some View {
        if let name = trend.preview, name.hasPrefix("http"), let url = URL(string: name) {
            AsyncImage(url: url) { phase in
                if let bild = phase.image {
                    bild.resizable().scaledToFill()
                } else {
                    // Kein Kreisel: eine ruhige Flaeche stoert weniger als ein
                    // Dutzend drehende Raedchen in einem Streifen.
                    Rectangle().fill(Theme.surfaceHigh)
                }
            }
        } else if let name = trend.preview, UIImage(named: name) != nil {
            Image(name).resizable().scaledToFill()
        } else if let data = sourcePhoto, trend.mode.keepsPhoto, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        }
    }

    // MARK: - Eigene Idee

    /// Eine kleine Glasleiste, die beim Antippen nach unten wandert.
    ///
    /// Sie sieht aus wie die grosse Regie-Leiste, nur klein und an der Stelle,
    /// an der man auf den Gedanken kommt. Beim Antippen verschwindet sie hier
    /// und dieselbe Leiste steht unten am Bildschirmrand — sie ist nicht
    /// zweimal da, sie ist umgezogen. Deshalb steuert `composerOpen` von
    /// aussen, ob sie ueberhaupt gezeigt wird.
    ///
    /// Das Glas ist dasselbe Material wie im Chat-Tab. Wer dort getippt hat,
    /// erkennt hier sofort, was das ist.
    private var eigeneIdee: some View {
        Button(action: onOwnIdea) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("…or tell me your own idea")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Theme.surfaceHigh, in: Circle())
            }
            .padding(.leading, 15)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: Capsule())
            .shadow(color: Theme.textPrimary.opacity(0.08), radius: 10, y: 4)
            // Glas ist optisch geschlossen, hat aber durchsichtige Luecken —
            // ohne eigene Trefferflaeche geht der Tipp daran vorbei.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .offset(y: 12)))
    }

    // MARK: - Bausteine

    /// Dieselbe Typografie wie die Kopfzeile auf dem Blatt: winzige, weit
    /// gesperrte Versalien und eine Linie, die den Rest der Breite nimmt.
    /// Ein Bildschirm, eine Handschrift — sonst zerfaellt er in Bausteine aus
    /// verschiedenen Apps.
    private func abschnitt(_ titel: String, zusatz: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(titel)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(Theme.textTertiary)
                // Eine Ueberschrift, die umbricht, reisst die Linie daneben
                // mit — im Simulator sah das aus wie ein Satzfehler.
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.10))
                .frame(height: 1)
            if let zusatz {
                Text(zusatz)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Eine Linie, die nichts darstellt — der Platzhalter fuer eine Idee, die
/// noch niemand aufgeschrieben hat. Zwei ungleiche Wellen uebereinander, damit
/// sie nicht wie eine Sinuskurve aussieht.
private struct KritzelLinie: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let steps = 60
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let y = r.midY + sin(t * 2.4 * 2 * .pi) * r.height * 0.30
                           + sin(t * 5.1 * 2 * .pi + 1.3) * r.height * 0.10
            let point = CGPoint(x: r.minX + r.width * t, y: y)
            if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
}
