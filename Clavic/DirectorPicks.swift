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
//    3. Der ganze Katalog — als FILMSTREIFEN, nicht als Listenzeile.
//
//       Eine weisse Zeile mit einem Pfeil rechts ist das Bauteil, das in
//       jeder App steht. Sie sagt nichts darüber, wo man ist. Der Streifen
//       mit Perforation gehört dagegen auf denselben Tisch wie die Filmdose
//       in der Kulisse und die Sofortbilder darüber — und man sieht sofort
//       Bilder statt eines Versprechens.
//
//    4. „…or tell me your own idea" — als LEERER ABZUG.
//
//       Vorher war das ein Kasten mit gestrichelter Umrandung. Der liest sich
//       als Ablagefeld für Dateien, und gestrichelte Kästen stehen in jeder
//       zweiten App. Ein leerer Abzug mit einer Bleistiftlinie darauf sagt
//       dasselbe in der Sprache dieses Bildschirms: der Director hat zwei
//       Bilder hingelegt, und eins ist noch frei.
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
                katalogStreifen
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
            abschnitt("TRENDING ON TIKTOK", zusatz: "FOR YOU")

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

    /// Ein Filmstreifen statt einer Listenzeile.
    ///
    /// Die Perforation oben und unten ist der ganze Trick: sie macht aus einer
    /// Reihe Bildchen ein Objekt, das auf diesem Tisch liegen kann. Sie ist
    /// nicht gezeichnet, sondern eine Reihe kleiner Rechtecke im gleichen
    /// Abstand — deshalb passt sie sich jeder Breite an.
    private var katalogStreifen: some View {
        Button { katalogOffen = true } label: {
            VStack(alignment: .leading, spacing: 7) {
                abschnitt("EVERY LOOK WE HAVE", zusatz: "\(Self.katalog.count)")

                ZStack {
                    Theme.textPrimary
                    VStack(spacing: 0) {
                        perforation
                        HStack(spacing: 3) {
                            ForEach(Array(Self.katalog.prefix(6).enumerated()), id: \.offset) { _, look in
                                Group {
                                    if let name = look.preview, UIImage(named: name) != nil {
                                        Image(name).resizable().scaledToFill()
                                    } else {
                                        Rectangle().fill(Theme.surfaceHigh)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 62)
                                .clipped()
                            }
                        }
                        .padding(.horizontal, 3)
                        perforation
                    }
                    .padding(.vertical, 5)
                }
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                // Er liegt leicht schief auf dem Tisch, wie alles hier.
                .rotationEffect(.degrees(-0.6))
                .shadow(color: Theme.textPrimary.opacity(0.16), radius: 10, y: 5)
            }
        }
        .buttonStyle(.plain)
    }

    /// Eine Reihe Perforationslöcher.
    private var perforation: some View {
        HStack(spacing: 0) {
            ForEach(0..<14, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.background)
                    .frame(width: 7, height: 5)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    // MARK: - Eigene Idee

    /// Ein leerer Abzug. Kein gestrichelter Kasten.
    ///
    /// Er hat genau die Form der geworfenen Karten darüber — Bildfeld oben,
    /// beschrifteter Streifen unten, leicht schief. Dadurch steht die eigene
    /// Idee sichtbar AUF DERSELBEN STUFE wie die beiden Vorschläge, statt als
    /// Notausgang darunter.
    ///
    /// Im Bildfeld liegt eine Bleistiftlinie, die nichts darstellt: sie sagt
    /// „hier ist noch nichts", ohne ein Symbol zu bemühen.
    private var eigeneIdee: some View {
        Button(action: onOwnIdea) {
            VStack(spacing: 0) {
                ZStack {
                    Theme.background
                    KritzelLinie()
                        .stroke(Theme.textTertiary.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .padding(.horizontal, 34)
                        .padding(.vertical, 22)
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34)
                        .background(Theme.surface, in: Circle())
                        .shadow(color: Theme.textPrimary.opacity(0.10), radius: 5, y: 2)
                }
                .frame(height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(9)
                .padding(.bottom, 0)

                HStack(spacing: 0) {
                    Text("…or tell me your own idea")
                        .font(.system(size: 14.5, weight: .semibold, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .rotationEffect(.degrees(1.1))
            .shadow(color: Theme.textPrimary.opacity(0.13), radius: 11, y: 6)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
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
