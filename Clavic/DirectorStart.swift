//
//  DirectorStart.swift
//  Clavic
//
//  Der Auftakt: was da steht, bevor und während ein Foto ankommt.
//
//  DAS LEERE SOFORTBILD IST DER KNOPF.
//  Hier stand vorher ein großer blauer Knopf mit Listenzeilen darunter —
//  sauber, funktionierend und austauschbar. Clavic hat drei Dinge, die sonst
//  niemand hat: das Chamäleon, das Polaroid-Motiv und Liquid Glass. Der
//  Auftakt benutzt jetzt alle drei.
//
//  UND DAS FOTO GEHT IN DIESE KARTE.
//  Nicht als Anhang über einer Textzeile — das ließe es wie einen Chat
//  aussehen. Die Karte WAR die Aufforderung; sobald ein Foto da ist, ist sie
//  die Antwort darauf. Ein Zustand, zwei Füllungen.
//
//  EINE EIGENE IDEE DARF AUCH VORHER KOMMEN — ABER LEISE.
//  Lange stand hier gar keine Eingabe: eine Textzeile über der Karte hätte die
//  Seite nach Chat aussehen lassen, und vor der Analyse hat der Director das
//  Foto ja noch nicht gesehen. Das galt aber nur für eine gleichrangige Zeile.
//  Wer schon weiß, was er will, soll nicht erst eine Analyse abwarten müssen,
//  die er gar nicht braucht.
//
//  Deshalb: „See what he'd do" bleibt der eine große Knopf, und darunter steht
//  EINE Zeile in Nebentext — kein Feld, kein Rahmen, kein Sende-Pfeil. Sie
//  erscheint erst mit dem Foto, weil es vorher nichts gibt, worauf sich eine
//  Idee beziehen könnte.
//
//  DIE KARTE NIMMT DIE FORM DES FOTOS AN.
//  Das Fach hatte eine feste Höhe. Ein Hochformat wurde darin beschnitten —
//  Köpfe abgeschnitten, das Motiv aus der Mitte gerückt. Jetzt wird das
//  Seitenverhältnis des Bildes gemessen und das Fach danach gesetzt: nichts
//  wird beschnitten, und das Sofortbild wächst oder schrumpft mit, wie ein
//  echter Abzug in seinem Format.
//
//  EIN WEG IN DIE ANALYSE, DREI WERKZEUGE DANEBEN.
//  Die Karte führt in die Analyse: Foto rein, der Director sieht es an.
//  Darunter liegen drei Dinge, die kein Urteil brauchen, weil sie genau eine
//  Sache tun — sich in ein fremdes Foto setzen, etwas wegnehmen, größer
//  machen. Alle drei sehen gleich aus (`DirectorToolCards`).
//
//  KEINE BALKEN MEHR. „Put yourself in any photo" stand hier als schmale
//  Zeile über zwei Bildkarten — also genau das, was an „Take one now" schon
//  falsch war: Text, wo die Nachbarn zeigen, worum es geht.
//
//  KEINE VORSCHLÄGE VOR DER ANALYSE.
//  Unter der Karte standen einmal drei Laschen — „Clean it up", „Rescue the
//  light". Sie fragten nach einer Richtung, bevor der Director das Foto
//  überhaupt gesehen hatte. Falsche Reihenfolge: erst das Bild, dann sein
//  Befund, dann die Wahl. Vorher gibt es nichts sinnvoll zu wählen.
//
//  DER HINTERGRUND IST NICHT LEER.
//  Dahinter liegen vier Sofortbilder, eigens für die App gezeichnet (Nano
//  Banana 2 Pro, das Maskottchen als Stilreferenz): dieselbe Navy-Kontur,
//  dieselbe Palette. Sie zeigen ohne ein Wort, worum es geht — harter Blitz,
//  Gegenlicht am Wasser, Nachtstraße, ruhiges Tageslicht. Angeschnitten und
//  schief wie Abzüge auf einem Tisch, gedämpft, damit sie die Karte nie
//  überstimmen.
//

import SwiftUI
import PhotosUI

struct DirectorStart: View {
    /// Das angehängte Foto. Füllt die Karte, sobald es da ist.
    let photo: Data?
    @Binding var photoSelections: [PhotosPickerItem]
    var onCamera: () -> Void = {}
    var onRemoveObjects: () -> Void = {}
    var onUpscale: () -> Void = {}
    var onSend: () -> Void = {}
    var onClear: () -> Void = {}
    /// Der zweite Weg: nicht fragen, sondern selbst ansagen.
    var onOwnIdea: () -> Void = {}
    /// Der dritte Weg: einen Look direkt waehlen. Der Director liest das Foto
    /// trotzdem — die Lesung fliesst dann in genau diesen Look.
    var onPickTrend: (TikTokTrends.Look) -> Void = { _ in }

    @State private var appeared = false
    @State private var shimmer = false
    /// Seitenverhältnis des eingelegten Fotos (Breite ÷ Höhe).
    ///
    /// Begrenzt, damit ein extremes Panorama oder ein sehr schmales Hochformat
    /// die Karte nicht zerreißt — dann wird eben doch beschnitten, aber nur in
    /// den Fällen, in denen jede andere Lösung schlimmer aussähe.
    @State private var fotoSeiten: CGFloat = Self.leerSeiten
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Größtes Innenmaß des Fachs. Breite und Höhe werden aus dem
    /// Seitenverhältnis des Fotos gerechnet, beide gedeckelt.
    private static let fachMaxBreite: CGFloat = 214
    private static let fachMaxHoehe: CGFloat = 230
    private static let randSeitlich: CGFloat = 9
    /// Form des leeren Fachs — leicht liegend, wie ein Sofortbild.
    private static let leerSeiten: CGFloat = 214 / 176
    private static let seitenMin: CGFloat = 0.60   // hochkant
    private static let seitenMax: CGFloat = 1.60   // liegend

    /// Das Fach nimmt die Form des Fotos an — aber die HÖHE ist gedeckelt,
    /// nicht das Seitenverhältnis. Bei einem Hochformat wird die Karte also
    /// schmaler statt höher. Andersherum wuchs sie über die Bühne hinaus und
    /// der Knopf darunter lag auf ihr; im Simulator genau so gesehen.
    private var fachHoehe: CGFloat { min(Self.fachMaxHoehe, Self.fachMaxBreite / fotoSeiten) }
    private var fachBreite: CGFloat { min(Self.fachMaxBreite, fachHoehe * fotoSeiten) }
    private var kartenBreite: CGFloat { fachBreite + Self.randSeitlich * 2 }

    /// Die vier Motive. Winkel und Versatz sind fest — zufällige würden bei
    /// jedem Neuzeichnen springen.
    private static let streu: [(asset: String, x: CGFloat, y: CGFloat, dreh: Double, breite: CGFloat)] = [
        ("pola_flash",  -0.45, -0.30, -14, 112),
        ("pola_sunset",  0.41, -0.26,  11, 104),
        ("pola_night",  -0.44,  0.30,   8, 106),
        ("pola_clean",   0.42,  0.24,  -9,  98),
    ]

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                streuung
                karteMitRahmen
                    .scaleEffect(appeared ? 1 : 0.94)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.78), value: appeared)
            }
            .frame(height: 318)

            if photo == nil {
                // Drei Werkzeuge, die kein Urteil des Directors brauchen: jedes
                // tut genau eine Sache. Deshalb stehen sie hier und nicht in
                // seinen Vorschlaegen — und alle drei sehen gleich aus, damit
                // keines wie ein Hinweistext wirkt.
                VStack(spacing: 14) {
                    // Die Looks stehen auch OHNE Foto schon da — und ZUERST.
                    //
                    // Vorher sah man auf dem leeren Startbildschirm nur ein
                    // Ablagefach und drei Werkzeuge — dass die App ueberhaupt
                    // Trend-Looks kann, erfuhr man erst nach dem Hochladen und
                    // einer Bildlesung. Sie standen dann zwar hier, aber UNTER
                    // den Werkzeugen: auf dem Geraet lagen sie damit unterhalb
                    // des Bildrands, und wer nicht weiterschob, sah sie nie.
                    //
                    // Jetzt kommen sie direkt nach dem Ablagefach. Wer sie
                    // sieht, weiss sofort, wofuer er sein Foto hergibt. Ein
                    // Tipp fuehrt dann in die Mediathek und merkt sich den Look.
                    // Die Werkzeuge ruecken darunter — sie brauchen keinen
                    // Anreiz, man sucht sie gezielt.
                    DirectorTrendCards(onPick: onPickTrend,
                                       photoMissing: true,
                                       photoSelections: $photoSelections)

                    DirectorToolCards(onSwap: onCamera,
                                      onRemove: onRemoveObjects,
                                      onUpscale: onUpscale)
                        .padding(.horizontal, Theme.screenPadding)
                }
                .padding(.top, 2)
            } else {
                VStack(spacing: 12) {
                    losKnopf
                    eigeneIdeeZeile
                    // Mit Foto stehen die Trends UNTER den beiden Wegen, nicht
                    // darueber. Der Director bleibt das Angebot des Hauses; wer
                    // schon weiss, was er will, findet den kurzen Weg trotzdem.
                    DirectorTrendCards(onPick: onPickTrend,
                                       photoSelections: $photoSelections)
                        .padding(.top, 2)
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: photo != nil)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fotoSeiten)
        .onChange(of: photo, initial: true) { _, neu in
            guard let daten = neu, let ui = UIImage(data: daten), ui.size.height > 0 else {
                fotoSeiten = Self.leerSeiten
                return
            }
            fotoSeiten = min(max(ui.size.width / ui.size.height, Self.seitenMin), Self.seitenMax)
        }
        .onAppear {
            appeared = true
            guard !reduceMotion else { return }
            // Langer Weg, langsam: der Rücksprung der Schleife passiert weit
            // außerhalb der Karte. Mit kurzem Weg endete der Streifen sichtbar
            // am Rand und sprang zurück — das las sich als Fehler.
            withAnimation(.linear(duration: 7.5).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
    }

    // MARK: - Die Karte

    @ViewBuilder
    private var karteMitRahmen: some View {
        if photo == nil {
            PhotosPicker(selection: $photoSelections, maxSelectionCount: 6, matching: .images) { karte }
                .buttonStyle(.plain)
        } else {
            karte.overlay(alignment: .topTrailing) { verwerfen }
        }
    }

    /// Klein und leise. Die große Glaskugel an dieser Ecke saß nie richtig —
    /// sie war ein zweites Material auf einer Karte, die schon aus Glas ist.
    private var verwerfen: some View {
        Button(action: onClear) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.textPrimary.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(14)
    }

    private var karte: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                // Nur angedeutet, nicht deckend — eine volle Fläche hier hätte
                // alles blockiert, was der Glasrahmen durchlässt.
                Rectangle().fill(Theme.surfaceHigh.opacity(photo == nil ? 0.32 : 1))

                if let data = photo, let ui = UIImage(data: data) {
                    // Das Fach hat jetzt die Form des Bildes — also passt es
                    // vollständig hinein und muss nicht beschnitten werden.
                    Image(uiImage: ui).resizable().scaledToFit()
                } else {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.40),
                            .init(color: Color.white.opacity(0.45), location: 0.50),
                            .init(color: .clear, location: 0.60),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(16))
                    .scaleEffect(2.2)
                    .offset(x: shimmer ? 900 : -900)
                    .blendMode(.plusLighter)

                    VStack(spacing: 9) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Theme.accent.opacity(0.85))
                        Text("Drop your photo here")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary.opacity(0.62))
                    }
                }
            }
            .frame(width: fachBreite, height: fachHoehe)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            // Kein Innenstrich mehr. Auf dem leeren Fach war er eine graue
            // Linie ohne Aufgabe, und auf einem Foto zerschneidet er dessen
            // eigene Kante. Das Bild bringt seinen Rand selbst mit.
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(photo == nil ? 0 : 0.08), lineWidth: 1)
            )

            // Der beschriftete Streifen sagt, woran man ist.
            VStack(alignment: .leading, spacing: 2) {
                Text(photo == nil ? "Your photo" : "Got it")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(photo == nil ? "I'll find the best direction for it" : "Let me have a look at this")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            // EXPLIZITE Breite, nicht `maxWidth: .infinity`. Mit unendlich
            // durfte die Beschriftung über das Fach hinauswachsen und zog die
            // ganze Karte mit: gemessen 220 pt breit statt 171, und das Foto
            // saß dann links im Kasten — 20 pt Rand links, 48 rechts.
            .frame(width: fachBreite, alignment: .leading)
            .padding(.top, 9)
            .padding(.bottom, 3)
        }
        .padding(.horizontal, 9)
        .padding(.top, 9)
        .padding(.bottom, 15)
        .frame(width: kartenBreite)
        // Das Glas liegt als HINTERGRUND, nicht als Effekt auf der Karte.
        //
        // Direkt angewandt hat es sich nicht an die Breite gehalten: gemessen
        // 218 pt statt der gesetzten 171, und nach rechts versetzt — daher der
        // ungleiche Rand (21 pt links, 44 rechts). Die dünne Umrandung saß
        // dabei korrekt, das Glas nicht. Als `.background` nimmt es exakt die
        // Größe des Inhalts.
        //
        // `.clear` statt `.regular`: die Karte liegt auf den farbigen Abzügen,
        // und das dichtere Glas hat davon nichts durchgelassen — es sah aus
        // wie Milchglas.
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Theme.textPrimary.opacity(0.16), radius: 16, x: 0, y: 9)
        .rotationEffect(.degrees(-2.2))
    }

    /// Kein Sende-Pfeil in einer Textzeile — der ließe es wie einen Chat
    /// aussehen. Ein Satz in seiner Stimme, der sagt, was als Nächstes kommt.
    private var losKnopf: some View {
        Button(action: onSend) {
            HStack(spacing: 8) {
                Text("See what he'd do")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Theme.accent, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.32), radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
    }

    /// Der zweite Weg, absichtlich schwächer.
    ///
    /// Keine Kapsel, keine Fläche, kein Pfeil — nur eine Zeile in Nebentext mit
    /// dem angetippten Wort in Akzentfarbe. Sie steht unter dem großen Knopf
    /// und sieht auch so aus: ein Angebot für die, die schon wissen, was sie
    /// wollen, und kein zweiter Aufruf neben dem ersten.
    private var eigeneIdeeZeile: some View {
        Button(action: onOwnIdea) {
            (Text("Already have an idea? ")
                .foregroundStyle(Theme.textTertiary)
             + Text("Tell Clavic…")
                .foregroundStyle(Theme.accent))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Die verstreuten Abzüge

    /// Liegen HINTER der Karte. Gedämpft, leicht unscharf, angeschnitten — sie
    /// füllen die Fläche, ohne um Aufmerksamkeit zu bitten. Sobald ein Foto
    /// liegt, treten sie weiter zurück: dann zählt nur noch das echte Bild.
    private var streuung: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                ForEach(Array(Self.streu.enumerated()), id: \.offset) { index, s in
                    Image(s.asset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: s.breite, height: s.breite)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .padding(6)
                        .padding(.bottom, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .shadow(color: Theme.textPrimary.opacity(0.13), radius: 9, x: 0, y: 5)
                        .rotationEffect(.degrees(s.dreh))
                        .offset(x: w * s.x, y: geo.size.height * s.y)
                        .opacity(appeared ? (photo == nil ? 0.62 : 0.26) : 0)
                        .scaleEffect(appeared ? 1 : 0.9)
                        .animation(
                            .spring(response: 0.7, dampingFraction: 0.82).delay(Double(index) * 0.06),
                            value: appeared
                        )
                        .animation(.easeOut(duration: 0.45), value: photo == nil)
                }
            }
            .frame(width: w, height: geo.size.height)
            .blur(radius: 0.4)
            .allowsHitTesting(false)
        }
    }
}
