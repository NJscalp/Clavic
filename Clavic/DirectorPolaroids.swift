//
//  DirectorPolaroids.swift
//  Clavic
//
//  Was das Chamäleon herunterwirft.
//
//  Solange der Wurf läuft, steht hier der Gruß (`DirectorGreetingView`): eine
//  fette Zeile, die in knapp einer Sekunde hereinwischt. Bei der Übergabe
//  (3,50 s des Wurfs, siehe `MascotStage`) blendet sie weg und die vier Karten
//  kommen nacheinander von oben herein — je 0,10 s versetzt.
//
//  Sie POPPEN dabei nicht herein, sie kommen AUS DEM NEBEL. Über den Karten
//  liegt ein Streifen, in dem alles nach oben hin ausläuft — genau wie der
//  untere Rand des Videos. Eine Karte, die noch oben steht, ist darin nicht
//  zu sehen; beim Herunterfahren wird sie sichtbar. Die Feder ist bewusst
//  überschwingfrei (Dämpfung 0,95): ein Nachfedern sah aus wie ein Aufploppen.
//
//  Die Höhe des Bereichs ist immer dieselbe, ob Gruß oder Karten. Sonst
//  springt beim Landen die halbe Seite.
//
//  Polaroid statt Kachel, weil die Geste das verlangt: geworfene Bilder landen
//  schief, mit Rand und einem beschrifteten Streifen unten. Eine randlose
//  Vollbild-Kachel würde nicht aussehen, als hätte sie jemand geworfen.
//
//  Der Rahmen ist Liquid Glass (`glassEffect(.regular.interactive())`), das
//  Foto darin bleibt deckend. Dadurch federt die Karte beim Antippen nach,
//  ohne dass das Bild mitwabert — und der Rand nimmt die Farbe der Seite auf.
//
//  ZWEI ACHTUNGEN bei Glas, beide teuer bezahlt:
//
//  1. Die Fläche wird nicht von der Karte gezeichnet, sondern vom Glas-System.
//     `.opacity(0)` versteckt den Inhalt, das Glas aber nicht — die Rahmen
//     stünden von Anfang an da. Deshalb wird über die ANZAHL gezeichneter
//     Karten animiert, und die Einblendung enthält bewusst KEIN `.opacity`,
//     sondern nur Versatz und Skalierung.
//  2. Überlappen sich zwei Glasflächen, wird das Foto darunter milchig. Jeder
//     gefächerte Stapel sieht deshalb verwaschen aus — Karten dürfen sich nie
//     überlagern.
//
//  Inhalt sind die Digicam-Stile — sie haben bereits Vorschaufoto, Namen und
//  einen Einzeiler. Später können hier ebenso Agent-Richtungen liegen; die
//  Karte selbst weiß nicht, woher ihr Inhalt kommt.
//

import SwiftUI

/// Ein Eintrag auf einer geworfenen Karte.
struct PolaroidItem: Identifiable {
    let id: String
    let title: String
    let caption: String
    /// Name eines Assets. Fehlt es, zeigt die Karte eine ruhige Fläche.
    let asset: String
    /// Was beim Antippen an den Agenten geht.
    let prompt: String
    /// Der Vorschlag, den der Director selbst nehmen wuerde. Wird nur
    /// ausgewiesen, wenn es MEHRERE gibt — bei einem einzigen ist es ohnehin
    /// seine Wahl, und ein Abzeichen daran waere Rauschen.
    var isLead: Bool = false
    /// Zeichen, wenn es weder Asset noch Bild gibt. Eine leere graue Fläche
    /// auf einer Karte sagt dem Nutzer nichts.
    var icon: String? = nil
    /// Ein konkretes Bild statt eines Assets.
    ///
    /// Bei den Modi `grade` und `retouch` bleibt das Foto des Nutzers ja
    /// erhalten — dann gehört genau dieses Foto auf die Karte und nicht ein
    /// fremdes Beispielbild. Für frei erfundene Richtungen ohne Vorschau ist
    /// es die einzige Möglichkeit, überhaupt etwas zu zeigen.
    var image: Data? = nil
}

extension PolaroidItem {
    /// Baut eine Karte aus dem, was der Director geliefert hat.
    ///
    /// `sourcePhoto` ist das Foto, über das gesprochen wird. Es wird nur
    /// eingesetzt, wenn der Modus es erhält — bei `restage` und `generate`
    /// entstünde sonst der falsche Eindruck, das Ergebnis sähe so aus.
    init(_ option: DirectorAPI.Option, sourcePhoto: Data? = nil) {
        self.init(
            id: option.id,
            title: option.label,
            caption: option.caption,
            asset: option.preview ?? "",
            prompt: option.prompt,
            image: option.preview == nil && option.mode.keepsPhoto ? sourcePhoto : nil
        )
    }
}

extension PolaroidItem {
    /// Eine Startkarte vom Server.
    ///
    /// Hier stand früher `directionsFromStyles` — die sieben Digicam-Filter,
    /// fest im Binary. Sie waren nur mit einem App-Update änderbar und das
    /// Langweiligste, was der Director kann. Jetzt kommen die Karten von
    /// `/v1/director/showcase`: aktuelle Trends plus das, was er kann und was
    /// niemand erwartet.
    init(_ card: DirectorAPI.ShowcaseCard) {
        self.init(
            id: card.id,
            title: card.label,
            caption: card.caption,
            asset: card.preview ?? "",
            prompt: card.ask,
            icon: card.preview == nil ? card.icon : nil
        )
    }

    /// Der Vorrat für den Fall, dass der Server nicht antwortet.
    ///
    /// Bewusst KEINE Filter, sondern dasselbe, was der Server zeigen würde —
    /// sonst sähe die App offline nach etwas völlig anderem aus.
    static let fallbackShowcase: [PolaroidItem] = [
        PolaroidItem(id: "skill_declutter", title: "Clean it up",
                     caption: "Remove what ruins the shot", asset: "",
                     prompt: "Look at my photo and remove whatever is ruining it.", icon: "wand.and.sparkles"),
        PolaroidItem(id: "skill_reallight", title: "Rescue the light",
                     caption: "Faces out of shadow", asset: "",
                     prompt: "The light in my photo is bad. Fix it without making it look edited.", icon: "sun.max"),
        PolaroidItem(id: "skill_postable", title: "Make it postable",
                     caption: "One clear subject", asset: "",
                     prompt: "Make my photo postable.", icon: "square.and.arrow.up"),
    ]
}

// MARK: - Eine Karte

struct PolaroidCard: View {
    let item: PolaroidItem
    /// Leichte Schräglage — geworfene Bilder landen nicht im Raster.
    let tilt: Double
    /// Schmaler und flacher — für drei Karten nebeneinander.
    var compact: Bool = false
    /// EIN Vorschlag, ueber die ganze Breite.
    ///
    /// Wenn der Director nur eine Richtung sieht, ist das seine Aussage — und
    /// eine Aussage in einer 88 Punkt hohen Briefmarke liest sich wie ein
    /// Restposten. Dann bekommt das Foto die Flaeche, die ihm zusteht.
    var hero: Bool = false
    var onTap: () -> Void = {}

    /// Rahmenbreite des Polaroids. Unten breiter — das ist die Proportion, an
    /// der man ein Sofortbild überhaupt erkennt.
    private var border: CGFloat { compact ? 6 : 8 }

    /// Höhe des Fotos.
    static let photoHeight: CGFloat = 88
    static let compactPhotoHeight: CGFloat = 64
    static let heroPhotoHeight: CGFloat = 210
    /// Gesamthöhe einer Karte: Rand 8 + Foto + Streifen 50 + Rand 14.
    ///
    /// Die Zahl steht hier und NUR hier. Aus ihr rechnet `DirectorPolaroids`
    /// die Höhe des ganzen Bereichs; laufen die beiden auseinander, sitzt der
    /// Gruß an einer anderen Stelle als die Karten.
    static var totalHeight: CGFloat { 8 + photoHeight + 50 + 14 }
    static var compactTotalHeight: CGFloat { 6 + compactPhotoHeight + 36 + 10 }
    static var heroTotalHeight: CGFloat { 10 + heroPhotoHeight + 58 + 16 }
    static func totalHeight(compact: Bool) -> CGFloat { compact ? compactTotalHeight : totalHeight }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(Theme.surfaceHigh)

                    if let data = item.image, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else if UIImage(named: item.asset) != nil {
                        Image(item.asset)
                            .resizable()
                            .scaledToFill()
                    } else if let icon = item.icon {
                        Image(systemName: icon)
                            .font(.system(size: compact ? 24 : 30, weight: .regular))
                            .foregroundStyle(Theme.accent.opacity(0.85))
                    }
                }
                .frame(height: hero ? Self.heroPhotoHeight
                                    : (compact ? Self.compactPhotoHeight : Self.photoHeight))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                // „Das ist meiner." Nur wenn es mehrere gibt — sonst sagt es
                // nichts, was die Karte nicht schon durch ihr Alleinsein sagt.
                .overlay(alignment: .topLeading) {
                    if item.isLead && !hero {
                        Text("MY PICK")
                            .font(.system(size: 8.5, weight: .black, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.accent, in: Capsule())
                            .padding(6)
                    }
                }
                // Feine Navy-Kante am Bild selbst — dieselbe Kontur wie am
                // Maskottchen, damit Rahmen und Figur zur selben Zeichnung gehören.
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.14), lineWidth: 1)
                )

                // Der beschriftete Streifen — das, was ein Polaroid ausmacht.
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: hero ? 19 : (compact ? 11.5 : 14),
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(item.caption)
                        .font(.system(size: hero ? 13.5 : (compact ? 9.5 : 11.5),
                                      weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 28 : 38, alignment: .leading)
                .padding(.top, compact ? 6 : 8)
                .padding(.bottom, compact ? 3 : 4)
            }
            .padding(.horizontal, border)
            .padding(.top, border)
            .padding(.bottom, border + 6)
            // LIQUID GLASS als Rahmen: das Foto bleibt deckend, nur die
            // Umrahmung ist Glas. `interactive()` gibt ihr das Nachfedern beim
            // Antippen — deshalb sitzt der Effekt auf der Karte und nicht auf
            // dem Bild, sonst würde das Foto mitwabern.
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Theme.textPrimary.opacity(0.13), radius: 10, x: 0, y: 5)
            .rotationEffect(.degrees(tilt))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Der Bereich unter der Figur

struct DirectorPolaroids: View {
    let items: [PolaroidItem]
    /// false = der Wurf läuft noch. Wird an der Übergabe auf true gesetzt.
    let landed: Bool
    /// Zählt bei jedem Wurf hoch — erst dann läuft die Gruß-Animation. Siehe
    /// die Warnung in `DirectorGreeting.swift`.
    let throwToken: Int
    var onPick: (PolaroidItem) -> Void = { _ in }

    /// Drei Karten stehen nebeneinander und werden dafür kleiner, zwei bleiben
    /// groß. Mehr als drei gibt es nicht mehr — der Director nennt zwei Ideen,
    /// der Auftakt wirft drei.
    private var isCompact: Bool { items.count >= 3 }
    /// Genau eine Richtung → sie bekommt die ganze Flaeche.
    private var isHero: Bool { items.count == 1 }
    private var columnCount: Int { min(max(items.count, 1), 3) }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: isCompact ? 10 : 14), count: columnCount)
    }
    private var rowCount: Int { Int(ceil(Double(items.count) / Double(columnCount))) }

    /// Feste, aber unregelmäßige Winkel — zufällige würden bei jedem Neuzeichnen
    /// springen, und ein gleichmäßiges Muster sähe wieder nach Raster aus.
    private static let tilts: [Double] = [-2.4, 1.8, 1.2, -1.6, -0.9, 2.1]

    /// Wie viele Karten schon gelandet SIND. Nicht `opacity` — siehe die
    /// Glas-Warnung oben.
    @State private var shown = 0

    /// Zwei Kartenreihen plus Abstand — die Höhe, die der Bereich immer hat.
    ///
    /// GEMESSEN, warum die Karten kleiner sind als vorher: mit 170 pt hoher
    /// Karte endete die untere Reihe bei 667 pt und die Glasleiste der Eingabe
    /// begann bei 669 pt. Die Karte war vollständig da, stieß aber ohne jeden
    /// Abstand an die Leiste — und las sich dadurch als abgeschnitten. Mit dem
    /// kleineren Foto bleiben rund 35 pt Luft.
    static var blockHeight: CGFloat { PolaroidCard.totalHeight * 2 + 16 }
    /// Tatsächliche Höhe für die aktuelle Bestückung.
    private var currentBlockHeight: CGFloat {
        (isHero ? PolaroidCard.heroTotalHeight
                : PolaroidCard.totalHeight(compact: isCompact)) * CGFloat(rowCount)
            + (rowCount > 1 ? 16 : 0)
    }
    /// Siehe `fogDepth`: so viel zeichnet der Block über sich hinaus.
    static var topOverhang: CGFloat { fogDepth }

    /// Wie hoch der Nebelstreifen über den Karten ist. Darin fahren sie
    /// herunter, ohne dass man sie schon sieht.
    private static let fogDepth: CGFloat = 58
    /// Wie weit der Block über seine Layouthöhe hinaus nach OBEN zeichnet.
    ///
    /// Im Auftakt ist das gewollt — die Karten kommen aus dem Nebel unter der
    /// Figur. Steht über dem Block aber etwas anderes (im Gespräch die
    /// Überschrift), schiebt sich der Überstand darüber. Wer den Block dort
    /// einsetzt, muss diesen Wert als oberen Abstand ausgleichen.

    var body: some View {
        ZStack(alignment: .top) {
            if !landed {
                DirectorGreetingView(trigger: throwToken)
                    .padding(.top, 6)
                    .transition(.opacity)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index < shown {
                        PolaroidCard(
                            item: item,
                            tilt: Self.tilts[index % Self.tilts.count],
                            compact: isCompact,
                            hero: isHero,
                            onTap: { onPick(item) }
                        )
                        // Nur Versatz, keine Skalierung und kein `.opacity`:
                        // Skalierung sieht aus wie Aufploppen, und Deckkraft
                        // ignoriert das Glas ohnehin.
                        // Kurzer Weg. Mit 110 Punkten kam die Karte sichtbar
                        // von weit oben angeflogen; der untere Teil war dabei
                        // die ganze Zeit zu sehen, weil der Nebel nur oben
                        // liegt. 68 Punkte lesen sich als Absetzen.
                        .transition(.offset(y: -(Self.fogDepth + 10)))
                    }
                }
            }
            // Der Nebelstreifen. Er liegt ÜBER den Karten und läuft nach oben
            // aus; die zusätzliche Höhe wird danach wieder aus dem Layout
            // herausgerechnet, damit unten nichts verrutscht.
            .modifier(FadeInAtTop(depth: Self.fogDepth, contentHeight: currentBlockHeight))
        }
        .frame(height: currentBlockHeight, alignment: .top)
        // Weiche Farbflächen in den Farben der Figur — sie geben dem Bereich
        // Leben, ohne dass dort etwas zu lesen wäre. Über die Seitenränder
        // hinaus, damit sie nicht in einem Kasten sitzen.
        .background(
            DirectorAmbience()
                .padding(.horizontal, -Theme.screenPadding)
                .padding(.top, -30)
                // Nach unten weit über die Karten hinaus: so endet auch das
                // Auslaufen des Schimmers erst hinter der Eingabeleiste und
                // nicht auf sichtbarem Grund.
                .padding(.bottom, -Self.hiddenBelow)
        )
        .animation(.easeOut(duration: 0.35), value: landed)
        .onChange(of: landed, initial: true) { _, isLanded in
            guard isLanded else { shown = 0; return }
            guard shown < items.count else { return }
            // Nacheinander, nicht als Block — jede Karte landet einzeln.
            for i in items.indices {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.10) {
                    // Dämpfung 1,0 = gar kein Überschwingen. Alles darunter
                    // liest sich als Ploppen.
                    withAnimation(.spring(response: 0.72, dampingFraction: 1.0)) {
                        shown = max(shown, i + 1)
                    }
                }
            }
        }
    }
}

/// Wie weit unterhalb der Karten noch nichts zu sehen sein darf.
///
/// Die Eingabeleiste beginnt rund 35 pt unter der letzten Kartenreihe. Alles,
/// was weiter unten endet, liegt hinter ihrem Glas und ist damit unsichtbar —
/// dort dürfen Kanten liegen, auf dem freien Seitengrund nicht.
private let hiddenBelowCards: CGFloat = 80

extension DirectorPolaroids {
    fileprivate static var hiddenBelow: CGFloat { hiddenBelowCards }
}

/// Lässt Inhalt nach OBEN hin auslaufen, ohne ihn irgendwo zu beschneiden.
///
/// WARUM ES DAS GIBT: eine Maske beschneidet immer auf ihre eigene Fläche.
/// Inhalt, der darüber hinausragt — schräge Karten, ihre Rundungen, ihre
/// Schatten —, verschwindet dabei ersatzlos, und zwar mit einer schnurgeraden
/// Kante quer durchs Bild. Genau daran ist hier nacheinander alles
/// hängengeblieben: erst die Seiten, dann die unteren Ecken, dann die
/// Schatten. Jedes Mal wurde eine einzelne Zahl nachgebessert, und beim
/// nächsten Mal fehlte die nächste.
///
/// Deshalb steht die Luft jetzt an EINER Stelle und gilt für alle drei Seiten,
/// die nicht auslaufen sollen. Sie ist absichtlich großzügig: die Kante der
/// Maske liegt damit weiter unten als die Eingabeleiste beginnt, also hinter
/// deren Glas, und seitlich außerhalb des Bildschirms. Selbst wenn ein
/// Schatten größer wird, kann sie nicht mehr sichtbar werden.
struct FadeInAtTop: ViewModifier {
    /// Höhe des Auslaufens am oberen Rand.
    let depth: CGFloat
    /// Höhe des Inhalts — nur, um die Stützstelle des Verlaufs zu rechnen.
    let contentHeight: CGFloat

    private var bleed: CGFloat { hiddenBelowCards }

    func body(content: Content) -> some View {
        let total = contentHeight + depth + bleed
        return content
            .padding(.top, depth)
            .padding(.bottom, bleed)
            .padding(.horizontal, bleed)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: depth / max(total, 1))
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // Dieselbe Luft wieder aus dem Layout rechnen — sonst verschiebt
            // sich alles darunter.
            .padding(.top, -depth)
            .padding(.bottom, -bleed)
            .padding(.horizontal, -bleed)
    }
}

#Preview {
    ScrollView {
        DirectorPolaroids(items: PolaroidItem.fallbackShowcase, landed: true, throwToken: 1)
            .padding(18)
    }
    .background(Theme.background)
}
