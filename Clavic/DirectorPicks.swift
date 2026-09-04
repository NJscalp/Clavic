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

    @State private var trendsOffen = false
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
                if !alleTrends.isEmpty { trendKarte }
                if !composerOpen { eigeneIdee }
            }
        }
        .animation(.easeOut(duration: 0.35), value: landed)
        .animation(.smooth(duration: 0.3), value: composerOpen)
        .sheet(isPresented: $trendsOffen) {
            DirectorTrendSheet(
                trends: besteWahl.map { b in [b] + alleTrends.filter { $0.id != b.id } } ?? alleTrends,
                bestMatchID: besteWahl?.id,
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

    // MARK: - Seine zwei

    private var vorschlaege: some View {
        VStack(alignment: .leading, spacing: 8) {
            DirectorPolaroids(
                items: picks.map {
                    var item = PolaroidItem($0, sourcePhoto: sourcePhoto)
                    item.isLead = ($0.id == lead)
                    return item
                },
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

    /// Die beste Passung — falls der Director eine benennen konnte.
    ///
    /// NUR aus SEINEN Trends. Die Server-Trends hat er nie gesehen; sie eine
    /// „beste Passung" zu nennen waere eine Behauptung ohne Grundlage.
    private var besteWahl: DirectorAPI.Option? {
        trends.first(where: { $0.isBestMatch }) ?? trends.first
    }

    private var uebrigeTrends: [DirectorAPI.Option] {
        guard let besteWahl else { return alleTrends }
        return alleTrends.filter { $0.id != besteWahl.id }
    }

    /// EINE Karte statt eines Streifens — mit der besten Passung obenauf.
    ///
    /// Der eigentliche Nutzen des Directors ist hier nicht die Galerie,
    /// sondern dass er die Bildlesung kennt: Er kann sagen, WELCHER Trend zu
    /// genau diesem Foto passt. Deshalb steht einer gross oben und der Rest
    /// klein darunter — statt zwanzig gleichberechtigter Kacheln, die der
    /// Nutzer selbst durchsehen muesste.
    private var trendKarte: some View {
        Button { trendsOffen = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("TIKTOK TRENDS")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).fixedSize()
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.10))
                        .frame(height: 1)
                    Text("\(alleTrends.count)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                }

                if let besteWahl {
                    ZStack(alignment: .bottomLeading) {
                        vorschau(besteWahl)
                            .frame(maxWidth: .infinity)
                            .frame(height: 168)
                            .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                       startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("BEST MATCH FOR YOUR PHOTO")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(Theme.aiActive)
                            Text(besteWahl.label)
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !uebrigeTrends.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(uebrigeTrends.prefix(4).enumerated()), id: \.element.id) { _, trend in
                            vorschau(trend)
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                HStack(spacing: 6) {
                    Text(uebrigeTrends.isEmpty ? "See the trend" : "See them all")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Theme.textPrimary.opacity(0.08), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
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
    /// Der eine, den der Director fuer dieses Foto vorn sieht.
    let bestMatchID: String?
    let sourcePhoto: Data?
    let onPick: (DirectorAPI.Option) -> Void

    @Environment(\.dismiss) private var dismiss

    private let spalten = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: spalten, spacing: 14) {
                    ForEach(trends) { trend in
                        Button { onPick(trend) } label: { kachel(trend) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(Theme.screenPadding)
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
            .overlay(alignment: .topLeading) {
                if trend.id == bestMatchID {
                    Text("BEST MATCH")
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.aiActive, in: Capsule())
                        .padding(7)
                }
            }

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
