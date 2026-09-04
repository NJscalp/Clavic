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
//    3. Der ganze Katalog. Eine Kachelwand hinter EINEM Knopf, der sagt, wie
//       viele Looks es sind. Nicht der Hauptweg, aber sichtbar vorhanden —
//       damit niemand denkt, das hier seien alle Möglichkeiten.
//
//    4. „I want to make my own thing." Ein eigener, breiter Knopf, nicht
//       mehr eine graue Fusszeile. Er ist die Antwort auf „und wenn ich
//       etwas ganz anderes will?" und muss deshalb genauso laut sein wie
//       die Vorschläge.
//
//  ES WIRD NICHTS GERENDERT, bevor hier etwas angetippt wurde. Jeder Tipp
//  kostet Credits, deshalb ist jeder Tipp eine bewusste Entscheidung.
//

import SwiftUI

struct DirectorPicks: View {
    let picks: [DirectorAPI.Option]
    let trends: [DirectorAPI.Option]
    /// false = der Wurf läuft noch.
    let landed: Bool
    let throwToken: Int
    /// Das Foto, über das gesprochen wird — liegt auf Karten, die es erhalten.
    let sourcePhoto: Data?
    var onPick: (DirectorAPI.Option) -> Void = { _ in }
    var onOwnIdea: () -> Void = {}

    @State private var katalogOffen = false

    /// Der Hauskatalog als antippbare Richtungen. Alles unter „Viral Looks",
    /// das ein Vorschaubild und ein Rezept hat.
    private static let katalog: [DirectorAPI.Option] = TemplateLibrary.all
        .filter { $0.category == .looks && !$0.prompt.isEmpty }
        .map {
            DirectorAPI.Option(
                id: $0.hashtag, label: $0.title, caption: $0.subtitle,
                mode: .grade, prompt: $0.prompt, preview: $0.preview
            )
        }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Der Kartenblock zeichnet über seine Layouthöhe hinaus nach oben
            // (der Nebelstreifen, aus dem sie kommen). Ohne Ausgleich schöben
            // sich die Karten über das, was darüber steht.
            vorschlaege

            if landed {
                if !trends.isEmpty { trendStreifen }
                katalogZeile
                eigeneIdee
            }
        }
        .animation(.easeOut(duration: 0.35), value: landed)
        .sheet(isPresented: $katalogOffen) {
            DirectorCatalogSheet(
                looks: Self.katalog,
                sourcePhoto: sourcePhoto,
                onPick: { option in
                    katalogOffen = false
                    onPick(option)
                }
            )
        }
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
            abschnitt("Trending on TikTok", zusatz: "sorted for your photo")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(trends.enumerated()), id: \.element.id) { rang, trend in
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
                if let name = trend.preview, UIImage(named: name) != nil {
                    Image(name).resizable().scaledToFill()
                } else if let data = sourcePhoto, trend.mode.keepsPhoto, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                }

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

    // MARK: - Der ganze Katalog

    /// Sagt die Zahl. „Browse all looks" allein waere ein Versprechen ohne
    /// Groesse — mit der Zahl weiss man vorher, was einen erwartet.
    private var katalogZeile: some View {
        Button { katalogOffen = true } label: {
            HStack(spacing: 11) {
                stapelVorschau
                VStack(alignment: .leading, spacing: 2) {
                    Text("Every look we have")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Self.katalog.count) to pick from")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
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

    /// Drei versetzte Vorschaubilder — man sieht, dass hinter dem Knopf
    /// Bilder liegen, nicht eine Liste.
    private var stapelVorschau: some View {
        ZStack {
            ForEach(Array(Self.katalog.prefix(3).enumerated()), id: \.offset) { index, look in
                Group {
                    if let name = look.preview, UIImage(named: name) != nil {
                        Image(name).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Theme.surfaceHigh)
                    }
                }
                .frame(width: 34, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.surface, lineWidth: 1.5)
                )
                .rotationEffect(.degrees(Double(index - 1) * 8))
                .offset(x: CGFloat(index - 1) * 11)
                .zIndex(Double(index))
            }
        }
        .frame(width: 60, height: 46)
    }

    // MARK: - Eigene Idee

    /// Kein grauer Fusszeilentext mehr. Wer etwas anderes will, soll das
    /// genauso laut angeboten bekommen wie die Vorschläge — sonst denkt er,
    /// die Vorschläge seien alles, was geht.
    private var eigeneIdee: some View {
        Button(action: onOwnIdea) {
            HStack(spacing: 11) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("I want to make my own thing")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Tell him in your words — he works from your photo")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.papier, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.30), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bausteine

    private func abschnitt(_ titel: String, zusatz: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(titel)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            if let zusatz {
                Text(zusatz)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Der ganze Katalog als Kachelwand

/// Alles, was das Haus kann, in einem Raster mit echten Vorschaubildern.
///
/// Bewusst KEINE Suchzeile und keine Filter: bei rund zwanzig Kacheln ist
/// Scrollen schneller als Tippen, und jedes Bedienelement mehr macht aus
/// einer Auswahl eine Verwaltung.
private struct DirectorCatalogSheet: View {
    let looks: [DirectorAPI.Option]
    let sourcePhoto: Data?
    let onPick: (DirectorAPI.Option) -> Void

    @Environment(\.dismiss) private var dismiss

    private let spalten = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: spalten, spacing: 14) {
                    ForEach(looks) { look in
                        Button { onPick(look) } label: { kachel(look) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Every look")
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
    }

    private func kachel(_ look: DirectorAPI.Option) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(Theme.surfaceHigh)
                if let name = look.preview, UIImage(named: name) != nil {
                    Image(name).resizable().scaledToFill()
                }
            }
            .frame(height: 178)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(look.label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(look.caption)
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
}
