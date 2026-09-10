//
//  DirectorPicks.swift
//  Clavic
//
//  Die Buehne, auf der der Director seine Ideen ablegt.
//
//  DREI WEGE, VON OBEN NACH UNTEN NACH WICHTIGKEIT:
//
//    1. SEINE IDEEN — ein Kartenstapel (`DirectorDeck`). Eine liegt vorn, die
//       anderen sichtbar darunter. Wischen oder eine hintere Karte antippen
//       tauscht sie; der Stapel ist der Waehler.
//    2. DIE EIGENE IDEE — ein Knopf, der die Buehne raeumt und die Textleiste
//       aus dem Chat-Tab hereinholt (`ClavicComposer`). Kein Verlauf, keine
//       Blasen: der Text geht in denselben Zug wie ein Vorschlags-Chip.
//    3. DIE TRENDS — ein drehbarer Kartenkranz (`DirectorTrendRing`), ganz
//       unten und offen sichtbar.
//
//  DIE TRENDS WAREN EIN KNOPF. „Find a TikTok trend ›", dahinter ein zweiter
//  Zustand mit eigenem Stapel. Das war ehrlich sekundaer, zeigte aber nichts:
//  Trends SIND Bilder, und ein Wort darueber macht niemanden neugierig. Der
//  Zustand ist ersatzlos weg, die Karten liegen jetzt offen da.
//
//  Sekundaer bleiben sie trotzdem, und zwar an drei Stellen: sie stehen ganz
//  unten, ihre Karten sind klein, und einen blauen Knopf bekommt der Kranz
//  erst, wenn ihn jemand angefasst hat. Bis dahin ist „Make it" auf der
//  Director-Karte der einzige blaue Knopf des Bildschirms.
//
//  DAS TRENDURTEIL HAENGT AN DIESER BERUEHRUNG. Frueher lief es beim Betreten
//  des Trendmodus. Ohne Modus braucht es ein anderes Signal, und Anfassen ist
//  genau eines — sonst liefe bei jeder Analyse ein Modellaufruf mit, den
//  niemand bestellt hat.
//
//  ES WIRD NICHTS GERENDERT, bevor „Make it" angetippt wurde. Jeder Tipp
//  kostet Credits, deshalb ist jeder Tipp eine bewusste Entscheidung.
//

import SwiftUI

/// Was gerade auf der Buehne liegt. Reicht bis zu `AgentView` hoch, weil die
/// Figur daneben ihren Ruhe-Loop danach waehlt — sie soll zeigen, wovon
/// gerade die Rede ist.
enum DirectorBuehne: Equatable {
    case picks
    case trends
    case eigeneIdee
}

struct DirectorPicks: View {
    /// Vorschauen am eigenen Foto, Look-ID → Bild.
    ///
    /// WARUM DAS DIE KARTE VERAENDERT. Bisher stand auf jeder Karte das
    /// Beispielbild aus dem Hauskatalog — eine fremde Person in diesem Look.
    /// Man waehlte damit blind: „Golden Hour" sieht am Werbefoto immer gut
    /// aus, am eigenen Kuechenbild oft nach nichts. Liegt eine eigene
    /// Vorschau vor, steht sie hier; sonst wie bisher das Beispiel.
    var eigeneVorschauen: [String: Data] = [:]

    let picks: [DirectorAPI.Option]
    /// Die Richtung, die der Director selbst nehmen wuerde.
    var lead: String? = nil
    let trends: [DirectorAPI.Option]
    /// Additional candidates, filtered against the reviewed TikTok catalog.
    var serverTrends: [DirectorAPI.Option] = []
    /// Die Bildlesung. Liegt sie vor, kann der Director die angebotenen Trends
    /// gegen DIESES Foto beurteilen, ohne es noch einmal zu analysieren.
    var reading: DirectorAPI.Reading? = nil

    @State private var trendsOffen = false
    @State private var buehne: DirectorBuehne = .picks
    /// Das Urteil ueber DIESE Trendliste. Genau einmal geholt.
    @State private var trendUrteil: DirectorAPI.TrendVerdict?
    @State private var urteilLaeuft = false
    @State private var eigeneZeile = ""
    /// Welcher Trend gerade in der Mitte des Kranzes steht.
    @State private var trendGewaehlt: DirectorAPI.Option?
    /// Erst wenn jemand den Kranz angefasst hat, gibt es dort einen Knopf —
    /// und erst dann lohnt sich die Frage an den Director, welcher passt.
    @State private var kranzBeruehrt = false
    @FocusState private var zeileAktiv: Bool
    /// false = der Wurf läuft noch.
    let landed: Bool
    let throwToken: Int
    /// Das Foto, über das gesprochen wird — liegt auf Karten, die es erhalten.
    let sourcePhoto: Data?
    var onPick: (DirectorAPI.Option) -> Void = { _ in }
    /// Die eigene Ansage. Geht direkt in einen Zug — dafuer gibt es
    /// `send(override:)` schon, es braucht keinen neuen Weg.
    var onDirect: (String) -> Void = { _ in }
    /// Meldet den Zustand nach oben, damit die Figur darauf reagieren kann.
    var onBuehne: (DirectorBuehne) -> Void = { _ in }
    /// Was gerade angesehen wird — der Aufrufer haelt es, weil die Figur oben
    /// darueber spricht und die steht nicht hier drin.
    var selected: DirectorAPI.Option? = nil
    var onSelect: (DirectorAPI.Option?) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if landed {
                ueberschrift
                inhalt
                // DIE LEISTE STEHT IMMER HIER, in beiden Zustaenden.
                //
                // Sie in den Moduswechsel zu haengen waere naheliegend und
                // falsch: SwiftUI baut sie dann beim Wechsel neu auf, der
                // Fokus geht verloren und die Tastatur klappt sofort wieder
                // zu. Genau in dem Moment, in dem der Nutzer tippen will.
                //
                // Sie bleibt deshalb dieselbe Ansicht; der Modus entscheidet
                // nur, was DARUEBER und DARUNTER liegt.
                ideenLeiste
                trendKranz
            } else {
                DirectorGreetingView(trigger: throwToken)
                    .frame(height: 230)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.35), value: landed)
        .animation(.smooth(duration: 0.34), value: buehne)
        .onChange(of: buehne, initial: true) { _, neu in onBuehne(neu) }
        // Das Urteil holt sich der Trendmodus selbst — einmal, und nur wenn
        // eine Bildlesung vorliegt. Ohne sie muesste das Foto neu analysiert
        // werden; dafuer ist eine Trendliste kein Grund.
        .task(id: kranzBeruehrt) {
            guard kranzBeruehrt, trendUrteil == nil, !urteilLaeuft,
                  let reading, !alleTrends.isEmpty else { return }
            urteilLaeuft = true
            let ergebnis = await DirectorAPI.rankTrends(reading: reading, offered: alleTrends)
            urteilLaeuft = false
            // Der Kranz holt den Besten selbst in die Mitte, sobald
            // `besterID` steht — siehe `DirectorTrendRing.setzeStart`.
            withAnimation(.smooth(duration: 0.4)) { trendUrteil = ergebnis }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["UITEST_DIRECTOR_TRENDS"] == "1" {
                trendsOffen = true
            }
        }
        #endif
        .sheet(isPresented: $trendsOffen) {
            DirectorTrendSheet(
                trends: sortierteTrends,
                reading: reading,
                // GEREICHT, nicht neu geholt: derselbe Aufruf zweimal waere
                // derselbe Preis zweimal.
                vorabUrteil: trendUrteil,
                sourcePhoto: sourcePhoto,
                onPick: { option in
                    trendsOffen = false
                    onPick(option)
                }
            )
        }
    }

    // MARK: - Kopf und Inhalt

    private var ueberschrift: some View {
        HStack(spacing: 8) {
            Text(titel)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(buehne == .picks ? Theme.textTertiary : Theme.accent)
                .lineLimit(1).fixedSize()
                .contentTransition(.opacity)

            Rectangle().fill(Theme.textPrimary.opacity(0.09)).frame(height: 1)

            if buehne != .picks { zurueck }
        }
    }

    private var titel: String {
        switch buehne {
        case .eigeneIdee: return "YOUR IDEA"
        default:          return "CLAVIC'S PICKS"
        }
    }

    private var zurueck: some View {
        Button {
            zeileAktiv = false
            wechsle(zu: .picks)
        } label: {
            Text("Back to Clavic's picks")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var inhalt: some View {
        switch buehne {
        case .eigeneIdee:
            Text("What do you have in mind?")
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .transition(.opacity.combined(with: .offset(y: -10)))
        default:
            stapel(picks)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    /// Derselbe Stapel fuer beide Listen. Das IST die Anforderung: der
    /// Trendmodus ist kein anderer Bildschirm, sondern andere Karten.
    private func stapel(_ liste: [DirectorAPI.Option]) -> some View {
        DirectorDeck(
            optionen: liste,
            aktivID: aktive(aus: liste)?.id,
            // GEMESSEN, nicht geschaetzt: 15 Punkt Rand oben und unten, die
            // hoechste Spalte der Kopfzeile (Name zweizeilig plus zweizeilige
            // Beschreibung, rund 110), 10 Punkt Abstand und der 50 Punkt hohe
            // Knopf. Mit 168 quoll die Karte ueber ihren Rahmen und legte sich
            // im Simulator auf die Zeilen darunter.
            hoehe: 200,
            onAktiv: { onSelect($0) },
            karte: { richtungsKarte($0) }
        )
    }

    // MARK: - Die Nebenwege

    /// DIE EIGENE IDEE IST DIE LEISTE SELBST, kein Knopf davor.
    ///
    /// Hier stand „Tell Clavic your idea" als Pille. Ein Knopf, der eine
    /// Eingabe verspricht, ist aber ein Umweg: man tippt, ein Bildschirm
    /// wechselt, DANN darf man schreiben. Die Leiste kann das Versprechen
    /// selbst sein — sie sieht aus wie eine Eingabe, weil sie eine ist.
    ///
    /// Beim Antippen raeumt der Bildschirm auf: der Stapel und die Trends
    /// gehen weg, es bleibt die Frage und die Zeile. Ausgeloest wird das vom
    /// FOKUS, nicht von einem Tipp-Handler — so gilt es auch, wenn die
    /// Tastatur auf einem anderen Weg hochkommt.
    @ViewBuilder
    private var ideenLeiste: some View {
        ClavicComposer(
            text: $eigeneZeile,
            placeholder: buehne == .eigeneIdee
                ? "Make it look like a film still…"
                : "Tell Clavic your idea…",
            fokus: $zeileAktiv,
            onSubmit: anweisen
        ) {
            if buehne == .eigeneIdee {
                Button {
                    zeileAktiv = false
                    zurueckZuPicks()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Button(action: anweisen) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(
                        kannAnweisen ? .regular.tint(Theme.accent).interactive() : .regular,
                        in: Circle()
                    )
                    .shadow(color: kannAnweisen ? Theme.accent.opacity(0.28) : .clear,
                            radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(!kannAnweisen)
            .animation(.spring(duration: 0.25), value: kannAnweisen)
        }
        // Der Fokus IST der Moduswechsel.
        .onChange(of: zeileAktiv) { _, aktiv in
            guard aktiv, buehne != .eigeneIdee else { return }
            withAnimation(.smooth(duration: 0.34)) { buehne = .eigeneIdee }
            onBuehne(.eigeneIdee)
        }
    }

    private func zurueckZuPicks() {
        withAnimation(.smooth(duration: 0.34)) { buehne = .picks }
        onBuehne(.picks)
        onSelect(nil)
    }

    // MARK: - Die Trends

    /// DIE TRENDS LIEGEN OFFEN DA, statt hinter einem Knopf.
    ///
    /// Hier stand „Find a TikTok trend ›" — ehrlich sekundaer, aber es zeigte
    /// nichts. Trends SIND Bilder; ein Wort darueber macht niemanden
    /// neugierig, und wer nicht tippt, erfaehrt nie, was es gibt.
    ///
    /// Der Kranz bleibt trotzdem der dritte Weg: er steht ganz unten, seine
    /// Karten sind klein, und einen blauen Knopf bekommt er erst, wenn jemand
    /// ihn angefasst hat. Vorher ist „Make it" auf der Director-Karte der
    /// einzige blaue Knopf des Bildschirms.
    @ViewBuilder
    private var trendKranz: some View {
        if buehne == .picks, !alleTrends.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("TIKTOK TRENDS")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).fixedSize()
                    Rectangle().fill(Theme.textPrimary.opacity(0.09)).frame(height: 1)
                    Button { trendsOffen = true } label: {
                        Text("See all")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).fixedSize()
                    }
                    .buttonStyle(.plain)
                }

                DirectorTrendRow(
                    trends: sortierteTrends,
                    besterID: bestandenerTrend,
                    sourcePhoto: sourcePhoto,
                    isAnimating: !trendsOffen,
                    gewaehlt: $trendGewaehlt,
                    // Anfassen ist die Absichtserklaerung: erst danach fragt
                    // die App den Director, welcher Trend zu DIESEM Foto
                    // passt, und erst danach steht dort ein Knopf. Ohne diese
                    // Schwelle liefe bei jeder Analyse ein Modellaufruf mit,
                    // den niemand bestellt hat.
                    onBeruehrt: beruehrt
                )

                if kranzBeruehrt, let trend = trendGewaehlt {
                    machDas(trend)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .transition(.opacity)
        }
    }

    private func beruehrt() {
        guard !kranzBeruehrt else { return }
        withAnimation(.smooth(duration: 0.3)) { kranzBeruehrt = true }
        onBuehne(.trends)
    }

    /// EIN KNOPF, DER AUCH WIE EINER AUSSIEHT.
    ///
    /// Hier standen zwei Textzeilen mit einem kleinen Pfeil. Sie waren
    /// zurueckhaltend — und damit zu zurueckhaltend: sie sahen aus wie
    /// Beschriftung, nicht wie etwas, das man antippt. Wer nicht ausprobiert,
    /// hat den zweiten und dritten Weg der App nie gefunden.
    ///
    /// Jetzt: 54 Punkt hoch, Flaeche, Rand, Symbol, Winkel rechts. Aber in
    /// Grauwerten, nicht in Akzentblau — der eine blaue Knopf auf diesem
    /// Bildschirm bleibt „Make it".
    private func nebenweg(_ text: String, symbol: String,
                          _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.10), in: Circle())

                Text(text)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.09), lineWidth: 1)
            )
            // Die Flaeche ist gefuellt, der Rand aber rund — ohne eigene
            // Trefferflaeche geht ein Tipp in den Ecken daneben.
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func wechsle(zu neu: DirectorBuehne) {
        withAnimation(.smooth(duration: 0.34)) { buehne = neu }
        // Die Auswahl gehoert zur Liste, die gerade liegt. Ohne das Loesen
        // zeigte der Trendstapel weiter auf eine Richtung, die er nicht hat.
        onSelect(nil)
        if neu == .eigeneIdee {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                zeileAktiv = true
            }
        }
    }

    // MARK: - Trends sortieren

    /// Der Beste zuerst, dann die anderen guten, dann der Rest.
    ///
    /// Ohne Urteil greift, was der Director in seiner Antwort schon markiert
    /// hat (`isBestMatch`) — dafuer braucht es keinen zweiten Aufruf.
    private var sortierteTrends: [DirectorAPI.Option] {
        guard let urteil = trendUrteil else {
            let beste = alleTrends.filter(\.isBestMatch)
            return beste + alleTrends.filter { !$0.isBestMatch }
        }
        var rang: [String: Int] = [:]
        if let best = urteil.bestID { rang[best] = 0 }
        for (i, id) in urteil.alsoIDs.enumerated() where rang[id] == nil { rang[id] = i + 1 }
        return alleTrends.enumerated().sorted { a, b in
            let ra = rang[a.element.id] ?? (1000 + a.offset)
            let rb = rang[b.element.id] ?? (1000 + b.offset)
            return ra < rb
        }.map(\.element)
    }

    /// Welcher Trend fuer DIESES Foto vorn liegt — aus dem Urteil, sonst aus
    /// der Markierung, die der Director schon in seiner Antwort gesetzt hat.
    private var bestandenerTrend: String? {
        trendUrteil?.bestID ?? alleTrends.first(where: \.isBestMatch)?.id
    }

    /// Vorschlaege des Directors zuerst — sie sind auf DIESES Foto sortiert —,
    /// dahinter, was der Server gerade fuehrt. Doppelte fliegen raus.
    private var alleTrends: [DirectorAPI.Option] {
        TikTokTrends.options(ranked: trends + serverTrends)
    }

    // MARK: - Die Karte

    /// Welche Karte in DIESER Liste vorn liegt.
    ///
    /// `selected` liegt im Aufrufer und ueberlebt einen Listenwechsel — ohne
    /// den Abgleich zeigte der Trendstapel auf eine Richtung, die er nicht
    /// hat. Faellt nichts zusammen, gilt der Lead, sonst die erste.
    private func aktive(aus liste: [DirectorAPI.Option]) -> DirectorAPI.Option? {
        liste.first { $0.id == selected?.id }
            ?? liste.first { $0.id == lead }
            ?? liste.first
    }

    /// EINE RICHTUNG ALS KARTE. Text traegt die Aussage, das Bild ist Beiwerk.
    ///
    /// Hier lag einmal ein 252 Punkt hohes Referenzbild. Das war groesser als
    /// das Foto des Nutzers weiter oben, und damit stand der Satz auf dem
    /// Kopf: zu sehen war eine fremde Frau in einem fertigen Look, nicht eine
    /// Entscheidung ueber DIESES Bild.
    ///
    /// Die Karte hat eine FESTE Hoehe. Nur so liegen die Kanten der Karten
    /// dahinter parallel — ungleich hohe Karten sehen nicht nach Stapel aus,
    /// sondern nach Fehler.
    private func richtungsKarte(_ option: DirectorAPI.Option) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    if let marke = abzeichen(option) {
                        Text(marke)
                            .font(.system(size: 9.5, weight: .black, design: .rounded))
                            .tracking(1.3)
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    }

                    Text(option.label)
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    let text = beschreibung(option)
                    if !text.isEmpty {
                        Text(text)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if hatVorschau(option) { referenz(option) }
            }

            Spacer(minLength: 0)

            machDas(option)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: Theme.textPrimary.opacity(0.10), radius: 12, y: 6)
    }

    /// Wessen Wahl das ist — oder, im Trendmodus, wofuer sie gut ist.
    ///
    /// Nur auf der Karte, die es wirklich betrifft. Traegt jede Karte ein
    /// Abzeichen, sagt es nichts mehr.
    private func abzeichen(_ option: DirectorAPI.Option) -> String? {
        picks.count > 1 && option.id == lead ? "CLAVIC'S PICK" : nil
    }

    /// Der Daumennagel. Klein, hochkant, mit einer Zeile darunter, die sagt,
    /// was er IST.
    ///
    /// Die Zeile ist der Punkt: ohne sie sieht man eine fremde Person und
    /// haelt sie fuer das Ergebnis. Mit ihr ist es eine Musterkarte.
    private func referenz(_ option: DirectorAPI.Option) -> some View {
        VStack(spacing: 4) {
            Color.clear
                .frame(width: 72, height: 92)
                .background(Theme.surfaceHigh)
                .overlay { vorschau(option).id(option.id) }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
                )

            Text("THE LOOK")
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// Ob ueberhaupt etwas zu zeigen ist.
    ///
    /// `vorschau(_:)` faellt still auf nichts zurueck, wenn weder Adresse noch
    /// Asset noch das eigene Foto passen. Ohne diese Pruefung stuende dort ein
    /// leeres graues Rechteck mit „THE LOOK" darunter.
    private func hatVorschau(_ option: DirectorAPI.Option) -> Bool {
        if eigeneVorschauen[option.id] != nil { return true }
        if let name = option.preview, !name.isEmpty {
            if name.hasPrefix("http") { return true }
            if UIImage(named: name) != nil { return true }
        }
        return sourcePhoto != nil && option.mode.keepsPhoto
    }

    /// Was diese Richtung IST, in einer Zeile.
    ///
    /// KEIN zusaetzlicher Modellaufruf. `caption` ist die Zeile, mit der der
    /// Director sie begruendet hat; bei einem Haus-Look kommt dessen
    /// Beschreibung davor — „Crisp Xenon flash" sagt in drei Woertern, was es
    /// technisch ist. Sind beide gleich, steht sie nur einmal da.
    private func beschreibung(_ option: DirectorAPI.Option) -> String {
        let hausLook = option.preview.flatMap { name -> DigiCamStyles.Style? in
            guard name.hasPrefix("card_look_") else { return nil }
            return DigiCamStyles.style(id: String(name.dropFirst("card_look_".count)))
        }
        let teile = [hausLook?.subtitle, option.caption]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        // Gleiches nicht zweimal: in den Testdaten ist die Look-Beschreibung
        // oft woertlich die Begruendung des Directors.
        if teile.count == 2, teile[0].caseInsensitiveCompare(teile[1]) == .orderedSame {
            return teile[0]
        }
        return teile.joined(separator: " · ")
    }

    /// Der eine klare Knopf. Erst HIER kostet es Credits — vorher hat die
    /// Karte nur gesagt, was es waere.
    private func machDas(_ option: DirectorAPI.Option) -> some View {
        Button { waehleAus(option) } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 15, weight: .bold))
                // NUR „Make it". Der Name steht zwei Zeilen darueber; ihn
                // hier zu wiederholen war die dritte Nennung derselben Sache
                // auf einem Bildschirm.
                Text("Make it")
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.accent, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.30), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    /// Jede Wahl laeuft hier durch.
    ///
    /// Im Trendmodus wird sie gemeldet — nur so laesst sich spaeter
    /// unterscheiden, ob jemand dem Director gefolgt ist oder ihn uebergangen
    /// hat. Dieselbe Meldung schickt auch das Pop-up; sie darf beim Umbau der
    /// Ansicht nicht verloren gehen.
    private func waehleAus(_ option: DirectorAPI.Option) {
        // Ob es ein Trend war, steht jetzt an der Option selbst — es gibt
        // keinen Trendmodus mehr, in dem man das ablesen koennte.
        if !picks.contains(where: { $0.id == option.id }),
           alleTrends.contains(where: { $0.id == option.id }) {
            DirectorAPI.reportTrendChoice(
                selectionID: trendUrteil?.selectionID,
                chosenID: option.id,
                bestID: trendUrteil?.bestID
            )
        }
        onPick(option)
    }

    // MARK: - Trends

    /// EINE TEXTZEILE. Der Trendbereich ist eine TUER, keine Auslage.
    ///
    /// Hier stand zuletzt „best match: Y2K Digicam" beziehungsweise „19 to
    /// look through". Beides war falsch gewichtet: ein zweiter Name neben
    /// CLAVIC'S PICK ist eine zweite Empfehlung, und eine Zahl wirbt mit
    /// Menge, wo es um eine Entscheidung geht. Die Zeile sagt jetzt nur, dass
    /// es diese Tuer gibt und was dahinter passiert — die Beurteilung fuer
    /// DIESES Foto laeuft ohnehin erst im Pop-up.
    private var trendZeile: some View {
        Button { trendsOffen = true } label: {
            HStack(spacing: 7) {
                Text("TikTok trends")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text("· Find one for this photo")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
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
        if let eigenes = eigeneVorschauen[trend.id], let ui = UIImage(data: eigenes) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else if let name = trend.preview, name.hasPrefix("http"), let url = URL(string: name) {
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

    private var kannAnweisen: Bool {
        !eigeneZeile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func anweisen() {
        let text = eigeneZeile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        zeileAktiv = false
        eigeneZeile = ""
        zurueckZuPicks()
        onDirect(text)
    }

    // MARK: - Bausteine

}

// MARK: - Alle Trends in einem Blick

/// Das Pop-up hinter der Trend-Karte.
///
/// BEWUSST OHNE Suchzeile, Filter oder Kategorien. Bei zwanzig Kacheln ist
/// Ueberfliegen schneller als Tippen, und jedes Bedienelement mehr macht aus
/// einer Auswahl eine Verwaltung.
///
/// Reviewed photo looks, ordered by the Director when a photo reading exists.
private struct DirectorTrendSheet: View {

    let trends: [DirectorAPI.Option]
    /// Die Bildlesung. Ohne sie wird nicht gefragt — dann bleibt es die Liste.
    let reading: DirectorAPI.Reading?
    /// Das Urteil, das die Buehne schon geholt hat. Liegt es vor, wird NICHT
    /// noch einmal gefragt — derselbe Aufruf zweimal waere derselbe Preis
    /// zweimal.
    var vorabUrteil: DirectorAPI.TrendVerdict? = nil
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
                    Text("Real photos. Same shot, different look.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
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
                if let vorabUrteil { urteil = vorabUrteil; return }
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
        if let look = TikTokTrends.look(id: trend.id) {
            TrendPhotoPreview(look: look)
        } else if let name = trend.preview, name.hasPrefix("http"), let url = URL(string: name) {
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
