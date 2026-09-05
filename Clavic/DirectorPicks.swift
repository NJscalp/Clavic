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
//    2. Was gerade auf TikTok läuft — EINE Karte, die sich zu einer ruhigen
//       Übersicht öffnet.
//
//       Vorher lag hier ein waagerechter Streifen. Der zeigte zwar Bilder,
//       nahm aber viel Höhe und konnte immer nur drei auf einmal zeigen —
//       bei zwanzig Trends wischt niemand bis zum Ende. Die Karte zeigt vier
//       Vorschaubilder und die Zahl; alles Weitere liegt eine Berührung
//       entfernt in einem Raster, das man in einem Blick überfliegt.
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
    /// Die Richtung, die der Director selbst nehmen wuerde.
    var lead: String? = nil
    let trends: [DirectorAPI.Option]
    /// Was der Server gerade als Trend fuehrt. Kommt aus `templates.json` und
    /// braucht kein App-Update — genau dafuer ist der Streifen da.
    var serverTrends: [DirectorAPI.Option] = []
    /// true, solange die grosse Leiste unten steht. Dann ist die kleine hier
    /// weg: sie ist ja nach unten gewandert.
    var composerOpen: Bool = false
    /// Die Bildlesung. Liegt sie vor, kann der Director die angebotenen Trends
    /// gegen DIESES Foto beurteilen, ohne es noch einmal zu analysieren.
    var reading: DirectorAPI.Reading? = nil

    @State private var trendsOffen = false
    /// false = der Wurf läuft noch.
    let landed: Bool
    let throwToken: Int
    /// Das Foto, über das gesprochen wird — liegt auf Karten, die es erhalten.
    let sourcePhoto: Data?
    var onPick: (DirectorAPI.Option) -> Void = { _ in }
    var onOwnIdea: () -> Void = {}
    /// Was gerade angesehen wird — der Aufrufer haelt es, weil die Figur oben
    /// darueber spricht und die steht nicht hier drin.
    var selected: DirectorAPI.Option? = nil
    var onSelect: (DirectorAPI.Option?) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            // Der Kartenblock zeichnet über seine Layouthöhe hinaus nach oben
            // (der Nebelstreifen, aus dem sie kommen). Ohne Ausgleich schöben
            // sich die Karten über das, was darüber steht.
            vorschlaege

            if landed {
                if !alleTrends.isEmpty { trendKarte }
                if !composerOpen { eigeneIdee }
            }
        }
        .animation(.easeOut(duration: 0.35), value: landed)
        .animation(.smooth(duration: 0.28), value: selected?.id)
        .animation(.smooth(duration: 0.3), value: composerOpen)
        .sheet(isPresented: $trendsOffen) {
            DirectorTrendSheet(
                trends: alleTrends,
                reading: reading,
                sourcePhoto: sourcePhoto,
                onPick: { option in
                    trendsOffen = false
                    onPick(option)
                }
            )
        }
    }

    /// Vorschlaege des Directors zuerst — sie sind auf DIESES Foto sortiert —,
    /// dahinter, was der Server gerade fuehrt. Doppelte fliegen raus.
    private var alleTrends: [DirectorAPI.Option] {
        var gesehen = Set(trends.map(\.id))
        return trends + serverTrends.filter { gesehen.insert($0.id).inserted }
    }

    // MARK: - Was man machen kann

    /// KACHELN STATT SOFORTBILDER.
    ///
    /// Hier lagen geworfene Polaroids: 210 Punkt hohes Foto, Rand, Schraeglage,
    /// Schatten, beschrifteter Streifen. Schoen — aber sie nahmen den halben
    /// Bildschirm fuer zwei Waehlbare, und neben Kritzeln, Zettel, Sprechblase
    /// und Trendkarte war das Bild optisch voll, ohne mehr zu sagen.
    ///
    /// Was hier gebraucht wird, ist eine Antwort auf „was kann ich machen":
    /// ein Bild, damit man es sich vorstellen kann, und ein Name. Mehr nicht.
    /// Die Erklaerung haengt an der Auswahl — in der Sprechblase der Figur,
    /// dort wo sie gebraucht wird, und nicht vorsorglich an jeder Kachel.
    private var vorschlaege: some View {
        VStack(alignment: .leading, spacing: 10) {
            if landed {
                abschnitt("WHAT I'D MAKE")
                HStack(spacing: 10) {
                    ForEach(picks) { pick in
                        Button { onSelect(pick.id == selected?.id ? nil : pick) } label: {
                            kachelKlein(pick)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selected, picks.contains(where: { $0.id == selected.id }) {
                    sprechblase(selected)
                    machDas(selected)
                }
            } else {
                // Waehrend des Wurfs steht hier sein Gruss — sonst springt die
                // halbe Seite, wenn die Kacheln landen.
                DirectorGreetingView(trigger: throwToken)
                    .frame(height: bildHoehe + 26)
            }
        }
    }

    /// Was die Figur zur gewaehlten Kachel sagt.
    ///
    /// KEIN zusaetzlicher Modellaufruf. Der Text steht schon in der Antwort:
    /// `caption` ist die Zeile, mit der der Director diese Richtung begruendet
    /// hat. Bei einem Haus-Look kommt dessen Beschreibung davor — „Crisp Xenon
    /// flash & warm skin" sagt in vier Woertern, WAS es ist.
    ///
    /// Sie haengt an der AUSWAHL, nicht an jeder Kachel: eine Erklaerung, wenn
    /// sie gebraucht wird, statt drei vorsorglich nebeneinander.
    private func sprechblase(_ option: DirectorAPI.Option) -> some View {
        let hausLook = option.preview.flatMap { name -> DigiCamStyles.Style? in
            guard name.hasPrefix("card_look_") else { return nil }
            return DigiCamStyles.style(id: String(name.dropFirst("card_look_".count)))
        }
        // Nur voranstellen, wenn es NICHT dasselbe ist — sonst stand der Satz
        // zweimal da.
        let beschreibung = hausLook?.subtitle
        let satz = (beschreibung.map { $0.caseInsensitiveCompare(option.caption) == .orderedSame } ?? true)
            ? option.caption
            : [beschreibung, option.caption].compactMap { $0 }.joined(separator: ". ")

        return HStack(alignment: .top, spacing: 10) {
            // Nur der KOPF. Das Bild zeigt die ganze Figur; rund ausgeschnitten
            // saehe man sonst den Bauch.
            Image("clavic_mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .offset(y: 20)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .background(Theme.papier, in: Circle())

            Text(satz.isEmpty ? option.caption : satz)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1))
                .shadow(color: Theme.textPrimary.opacity(0.08), radius: 10, y: 4)
        }
        .transition(.opacity.combined(with: .offset(y: -6)))
    }

    /// Der eine klare Knopf. Erst HIER kostet es Credits — vorher hat die Figur
    /// gesagt, was es ist.
    private func machDas(_ option: DirectorAPI.Option) -> some View {
        Button { onPick(option) } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 15, weight: .bold))
                Text("Make it \(option.label)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.accent, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.30), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    /// Winzige, weit gesperrte Versalien mit einer Linie — dieselbe Zeile wie
    /// ueber der Trendzeile, damit der Bildschirm eine Handschrift hat.
    private func abschnitt(_ titel: String) -> some View {
        HStack(spacing: 8) {
            Text(titel)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1).fixedSize()
            Rectangle().fill(Theme.textPrimary.opacity(0.10)).frame(height: 1)
        }
    }

    /// Bildhoehe nach Anzahl: eine Richtung darf gross sein, drei muessen
    /// nebeneinander passen.
    private var bildHoehe: CGFloat {
        switch picks.count {
        case 1:  return 168
        case 2:  return 148
        default: return 116
        }
    }

    private func kachelKlein(_ option: DirectorAPI.Option) -> some View {
        let gewaehlt = option.id == selected?.id
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.surfaceHigh)
                vorschau(option)
                if option.id == lead && picks.count > 1 {
                    Text("MY PICK")
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.accent, in: Capsule())
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: bildHoehe)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(gewaehlt ? Theme.accent : Theme.textPrimary.opacity(0.08),
                                  lineWidth: gewaehlt ? 3 : 1)
            )

            Text(option.label)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Trends

    /// Die beste Passung — falls der Director eine benennen konnte.
    ///
    /// NUR aus SEINEN Trends. Die Server-Trends hat er nie gesehen; sie eine
    /// „beste Passung" zu nennen waere eine Behauptung ohne Grundlage.
    private var besteWahl: DirectorAPI.Option? {
        trends.first(where: { $0.isBestMatch }) ?? trends.first
    }


    /// EINE ZEILE. Der Trendbereich ist eine TUER, keine Auslage.
    ///
    /// Hier stand eine halbe Bildschirmseite: Ueberschrift mit Linie und
    /// Zaehler, ein 168 Punkt hohes Bild mit Verlauf und zwei Overlay-Texten,
    /// darunter vier Miniaturen, darunter eine Fusszeile mit Pfeil. Sieben
    /// Elemente fuer eine Nebenfunktion — und zusammen mit Kritzeln, Zettel,
    /// Polaroids, Sprechblase und Glasleiste war der Bildschirm optisch voll,
    /// ohne dadurch mehr zu sagen.
    ///
    /// Was die Zeile leistet, ist dasselbe: sie zeigt, dass es Trends gibt,
    /// wie viele, und welchen der Director fuer dieses Foto vorn sieht. Das
    /// grosse Bild dazu steht im Pop-up, wo man es auch braucht.
    private var trendKarte: some View {
        Button { trendsOffen = true } label: {
            HStack(spacing: 12) {
                stapel

                VStack(alignment: .leading, spacing: 2) {
                    Text("TIKTOK TRENDS")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    Text(besteWahl.map { "Best match: \($0.label)" }
                         ?? "\(alleTrends.count) to look through")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Drei versetzte Vorschauen — man sieht, dass dahinter Bilder liegen,
    /// ohne dass sie den Platz einer eigenen Karte brauchen.
    private var stapel: some View {
        ZStack {
            ForEach(Array(alleTrends.prefix(3).enumerated()), id: \.element.id) { index, trend in
                vorschau(trend)
                    .frame(width: 32, height: 42)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.surface, lineWidth: 1.5)
                    )
                    .rotationEffect(.degrees(Double(index - 1) * 7))
                    .offset(x: CGFloat(index - 1) * 10)
                    .zIndex(Double(index))
            }
        }
        .frame(width: 56, height: 44)
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

// MARK: - Alle Trends in einem Blick

/// Das Pop-up hinter der Trend-Karte.
///
/// BEWUSST OHNE Suchzeile, Filter oder Kategorien. Bei zwanzig Kacheln ist
/// Ueberfliegen schneller als Tippen, und jedes Bedienelement mehr macht aus
/// einer Auswahl eine Verwaltung.
///
/// Der Inhalt kommt aus zwei Quellen und sieht gleich aus: die Vorschlaege des
/// Directors fuer DIESES Foto zuerst, dahinter, was der Server gerade fuehrt
/// (`templates.json`). Neuer Trend, Bild und Name hochgeladen — er steht hier,
/// ohne App-Update. Genau dafuer laedt `vorschau(_:)` eine Adresse statt eines
/// Asset-Namens.
private struct DirectorTrendSheet: View {

    let trends: [DirectorAPI.Option]
    /// Die Bildlesung. Ohne sie wird nicht gefragt — dann bleibt es die Liste.
    let reading: DirectorAPI.Reading?
    let sourcePhoto: Data?
    let onPick: (DirectorAPI.Option) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Das Urteil des Directors ueber GENAU DIESE Liste.
    @State private var urteil: DirectorAPI.TrendVerdict?
    @State private var laeuft = false

    private var bestMatch: DirectorAPI.Option? {
        guard let id = urteil?.bestID else { return nil }
        return trends.first { $0.id == id }
    }
    private var weitere: [DirectorAPI.Option] {
        let ids = urteil?.alsoIDs ?? []
        return ids.compactMap { id in trends.first { $0.id == id } }
    }
    /// Alles, was nicht schon oben steht.
    private var rest: [DirectorAPI.Option] {
        let oben = Set([bestMatch?.id].compactMap { $0} + weitere.map(\.id))
        return trends.filter { !oben.contains($0.id) }
    }

    /// Jede Wahl im Fenster laeuft hier durch — die Empfehlung, eine
    /// Alternative oder etwas ganz anderes aus der Liste. Nur so laesst sich
    /// spaeter unterscheiden, ob jemand dem Director gefolgt ist oder ihn
    /// uebergangen hat. Meldet und faehrt sofort fort.
    private func waehle(_ trend: DirectorAPI.Option) {
        DirectorAPI.reportTrendChoice(
            selectionID: urteil?.selectionID,
            chosenID: trend.id,
            bestID: urteil?.bestID
        )
        onPick(trend)
    }

    private let spalten = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if laeuft { sucht }
                    if let bestMatch { empfehlung(bestMatch) }
                    if let urteil, urteil.bestID == nil, !urteil.why.isEmpty { keinerPasst(urteil.why) }
                    if !weitere.isEmpty {
                        abschnitt("OTHER GOOD MATCHES")
                        LazyVGrid(columns: spalten, spacing: 14) {
                            ForEach(weitere) { t in
                                Button { waehle(t) } label: { kachel(t) }.buttonStyle(.plain)
                            }
                        }
                    }
                    if !rest.isEmpty {
                        abschnitt(bestMatch == nil ? "ALL TRENDS" : "SEE ALL TRENDS")
                        LazyVGrid(columns: spalten, spacing: 14) {
                            ForEach(rest) { t in
                                Button { waehle(t) } label: { kachel(t) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .task {
                // NUR mit vorhandener Lesung. Ohne sie muesste das Foto neu
                // analysiert werden — dafuer ist eine Trendliste kein Grund.
                guard urteil == nil, let reading, !trends.isEmpty else { return }
                laeuft = true
                let ergebnis = await DirectorAPI.rankTrends(reading: reading, offered: trends)
                laeuft = false
                withAnimation(.smooth(duration: 0.3)) { urteil = ergebnis }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Our TikTok trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
        // Ruhig hereinkommen und sich zur Haelfte oeffnen lassen: das Foto
        // darunter bleibt sichtbar, waehrend man waehlt.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func kachel(_ trend: DirectorAPI.Option) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(Theme.surfaceHigh)
                bild(trend)
            }
            .frame(height: 186)
            .clipped()


            VStack(alignment: .leading, spacing: 2) {
                Text(trend.label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(trend.caption)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Theme.textPrimary.opacity(0.06), radius: 8, y: 4)
    }

    private func abschnitt(_ titel: String) -> some View {
        HStack(spacing: 8) {
            Text(titel)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1).fixedSize()
            Rectangle().fill(Theme.textPrimary.opacity(0.10)).frame(height: 1)
        }
    }

    /// Waehrend er urteilt. Kein Kreisel: dieselbe Sprache wie beim Lesen.
    private var sucht: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Checking which of these suits your photo…")
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// DIRECTOR'S TREND PICK — gross, mit einem Satz warum.
    private func empfehlung(_ trend: DirectorAPI.Option) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            abschnitt("DIRECTOR'S TREND PICK")
            Button { waehle(trend) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack { Rectangle().fill(Theme.surfaceHigh); bild(trend) }
                        .frame(height: 300)
                        .clipped()
                    VStack(alignment: .leading, spacing: 5) {
                        Text(trend.label)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        if let why = urteil?.why, !why.isEmpty {
                            Text(why)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1))
                .shadow(color: Theme.textPrimary.opacity(0.10), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
        }
    }

    /// „Keiner passt" ist eine echte Antwort und wird auch so gezeigt.
    private func keinerPasst(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            abschnitt("MY HONEST ANSWER")
            Text(why)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.papier, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// Aus dem Bundle ODER vom Server — siehe Kopf.
    @ViewBuilder
    private func bild(_ trend: DirectorAPI.Option) -> some View {
        if let name = trend.preview, name.hasPrefix("http"), let url = URL(string: name) {
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
}
