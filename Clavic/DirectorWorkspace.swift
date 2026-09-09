//
//  DirectorWorkspace.swift
//  Clavic
//
//  Was nach dem Absenden zu sehen ist — und was ausdrücklich NICHT zu sehen ist.
//
//  KEIN VERLAUF, KEINE BLASEN.
//  Hier stand ein Chat: Nachrichtenblasen, „Thinking…", ein Scrollback aus
//  vorherigen Zügen. Das ist das Gegenteil dessen, was der Director sein soll.
//  Ein Creative Director schickt dir keine Nachrichten — er sieht sich dein
//  Bild an und legt dir etwas hin.
//
//  Deshalb ist das hier eine WERKBANK, kein Gespräch: EIN Bild, EIN Befund,
//  die Auswahl darunter. Immer derselbe Aufbau, egal in welchem Zug. Nichts
//  scrollt weg, nichts staut sich an.
//
//  BEIM LESEN: DAS FOTO SELBST IST DIE LADEANZEIGE.
//  `BlurLoadingCard` — geblurtes Ausgangsbild, darüber die Clavic-Animation,
//  dieselbe wie im Chat-Tab seit jeher. Kein scharfes Bild mit einem Schleier
//  darüber: es ist gerade nicht deins, es ist bei ihm. Und die Figur steht
//  DARUNTER und schaut es sich an, statt oben unbeteiligt herumzustehen.
//
//  DIE WARTEZEIT ERZÄHLT.
//  Statt eines Kreisels und des Wortes „Thinking…" nennt er der Reihe nach,
//  was er gerade tut — Licht, Aufbau, Störstellen. Diese Stufen sind nicht
//  erfunden: es sind genau die Felder, die Stufe 1 tatsächlich ausliest.
//  Gemessen dauert eine Bildlesung rund 15 Sekunden; Ladebildschirme in
//  erfolgreichen Apps halten Leute fast neun, wenn sie erzählen, was passiert.
//

import SwiftUI

/// Was er der Reihe nach tut. Entspricht den Feldern der Bildlesung.
///
/// Steht ausserhalb der Struktur: `DirectorWorkspace` ist generisch (es nimmt
/// die Maskottchen-Ansicht entgegen), und generische Typen dürfen in Swift
/// keine statischen gespeicherten Eigenschaften haben.
private let arbeitsStufen = [
    "Where the light falls…",
    "What the frame cuts…",
    "What doesn't belong…",
    "Ideas coming together…",
]

/// Wo die Figur gerade steht. Sie braucht an beiden Stellen eine andere
/// Groesse und einen anderen Rand, deshalb entscheidet der Aufrufer — die
/// Werkbank sagt nur, WELCHER Platz gemeint ist.
enum MascotSlot {
    /// Beim Lesen: breit unter der Ladekarte, sie schaut sie an.
    case unterDerKarte
    /// Beim Ergebnis: klein rechts NEBEN dem Foto. Vorher stand sie oben
    /// allein ueber dem Bild und hatte sichtbar nichts damit zu tun.
    case nebenDemFoto
}

struct DirectorWorkspace<Mascot: View>: View {
    /// Die Figur, an dem Platz, den die Werkbank gerade braucht.
    @ViewBuilder let mascot: (MascotSlot) -> Mascot
    /// Das Bild, um das es geht — Ergebnis, sonst das Original.
    let photo: Data?
    /// Ein zweites Bild zum Vergleichen (Vorher), falls es ein Ergebnis gibt.
    let before: Data?
    let isWorking: Bool
    /// Zwischenstand aus dem Renderpfad, etwa „Fixing: plastic skin".
    let note: String?
    let picks: [DirectorAPI.Option]
    /// Die Richtung, die der Director selbst nehmen wuerde.
    var lead: String? = nil
    let trends: [DirectorAPI.Option]
    /// Trends vom Server — kein App-Update noetig.
    var serverTrends: [DirectorAPI.Option] = []
    /// true, solange die Regie-Leiste unten steht.
    var composerOpen: Bool = false
    /// Seine kurze Einschaetzung. EINE ZEILE, kein Zettel.
    ///
    /// Sie stand zwischendurch auf einem Blatt Papier mit Eselsohr, roter
    /// Randlinie und Unterschrift — ein Dokument fuer einen Satz. Das war das
    /// Problem, nicht der Satz: er ist das Einzige, was zeigt, dass hier
    /// jemand DIESES Foto angesehen hat, und der einzige Ort, an dem
    /// „ich wuerde hier kaum etwas anfassen" ueberhaupt stehen kann.
    var verdict: String? = nil
    /// Die Bildlesung, damit die Trend-Auswahl das Foto nicht neu analysiert.
    var reading: DirectorAPI.Reading? = nil

    /// Was der Nutzer gerade ansieht. Ein Tipp auf eine Karte WAEHLT sie —
    /// die Figur erklaert sie dann, und erst der Knopf darunter rendert.
    @State private var gewaehlt: DirectorAPI.Option?
    let landed: Bool
    let throwToken: Int
    var onPick: (DirectorAPI.Option) -> Void = { _ in }
    /// Die eigene Ansage aus der Buehne — geht unveraendert in einen Zug.
    var onDirect: (String) -> Void = { _ in }
    /// Welcher Zustand gerade auf der Buehne liegt. Der Aufrufer waehlt danach
    /// den Ruhe-Loop der Figur.
    var onBuehne: (DirectorBuehne) -> Void = { _ in }
    var onCompare: () -> Void = {}
    /// „Behalt ich" — sichert das Ergebnis.
    var onKeep: () -> Void = {}
    /// „Nochmal anders" — zurueck zu den Richtungen, ohne neues Foto.
    /// Mit dem fertigen Bild in den Chat wechseln und dort weiterarbeiten.
    var onKeepEditing: () -> Void = {}
    var onTryAnother: () -> Void = {}
    /// Reicht die gemessenen Anmerkungen nach oben. Die Leiste unten baut ihre
    /// Schnellauftraege daraus — so redet sie ueber DIESES Foto und nicht
    /// ueber Fotos im Allgemeinen.
    var onMarks: ([ReadMark]) -> Void = { _ in }

    @State private var stufe = 0
    /// Laeuft, solange gelesen wird — treibt den Schimmer in der Zeile.
    @State private var schimmer = false
    @State private var zeigeVorher = false
    /// Die gemessenen Anmerkungen auf dem Foto. Leer, solange gelesen wird.
    @State private var marks: [ReadMark] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        VStack(spacing: 14) {
            if isWorking {
                ladeKarte
                mascot(.unterDerKarte)
                arbeitsZeile
                // Darunter blieb der halbe Bildschirm leer. Zwei Platzhalter in
                // GENAU der Form der spaeteren Vorschlaege sagen ohne ein Wort,
                // was gleich passiert — und der Sprung vom Lesen zum Ergebnis
                // ist kleiner, weil die Form schon dasteht.
                platzhalterVorschlaege
            } else if let before, let photo {
                // DAS ERGEBNIS IST DER MOMENT. Es bekommt die Flaeche, und
                // darunter stehen zwei Entscheidungen — nicht zwoelf Werkzeuge.
                directorsCut(vorher: before, nachher: photo)
            } else {
                ergebnisBuehne
                if let verdict, !verdict.isEmpty { einschaetzung(verdict) }
            }

            if !picks.isEmpty {
                DirectorPicks(
                    picks: picks, lead: lead, trends: trends,
                    serverTrends: serverTrends,
                    reading: reading,
                    landed: landed, throwToken: throwToken,
                    sourcePhoto: before ?? photo,
                    onPick: onPick,
                    onDirect: onDirect,
                    onBuehne: onBuehne,
                    selected: gewaehlt,
                    onSelect: { neu in
                        withAnimation(.smooth(duration: 0.28)) { gewaehlt = neu }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                schimmer = true
            }
        }
        // Die Anmerkungen werden am Bild GEMESSEN, nicht erfunden — deshalb
        // laufen sie hier und nicht im Aufrufer: sie gehoeren zu dem Foto, das
        // gerade auf der Buehne liegt, und zu keinem anderen.
        .task(id: markKey) {
            guard !isWorking, before == nil,
                  let daten = photo, let ui = UIImage(data: daten) else {
                marks = []
                onMarks([])
                return
            }
            let gemessen = await DirectorReadMarks.marks(for: ui)
            guard !Task.isCancelled else { return }
            marks = gemessen
            onMarks(gemessen)
        }
        .task(id: isWorking) {
            guard isWorking, !reduceMotion else { return }
            stufe = 0
            // Vier Stufen à 4 s decken die gemessenen ~15 s ab. Läuft es
            // länger, bleibt die letzte stehen — sie verspricht nichts, was
            // sie nicht halten kann.
            while !Task.isCancelled && stufe < arbeitsStufen.count - 1 {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.4)) { stufe += 1 }
            }
        }
    }

    // MARK: - Beim Lesen

    /// Die Clavic-Ladeanimation im geblurten Foto — dieselbe Karte wie im
    /// Chat-Tab. Sie sagt ohne Worte: das Bild ist gerade in Arbeit.
    @ViewBuilder
    private var ladeKarte: some View {
        if let daten = photo, let ui = UIImage(data: daten) {
            BlurLoadingCard(ui: ui, leicht: true)
                .frame(maxHeight: 250)
        }
    }

    // MARK: - Was gleich kommt

    /// DIE LEERE BUEHNE, in genau der Form der spaeteren echten.
    ///
    /// Vorher endete der Bildschirm nach der Textzeile und darunter lag die
    /// halbe Hoehe leer — das liest sich wie ein Fehler, nicht wie Arbeit.
    /// Der Platzhalter fuellt die Flaeche, sagt ohne ein Wort was folgt, und
    /// der Wechsel zum Ergebnis wird kleiner, weil die Form schon steht.
    ///
    /// Hier standen zwei liegende Zeilen — die Form der alten Doppelkarte.
    /// Seit es EINE Buehne mit Schaltleiste gibt, versprach das die falsche
    /// Seite: der Nutzer sah zwei Vorschlaege kommen und bekam einen.
    private var platzhalterVorschlaege: some View {
        VStack(alignment: .leading, spacing: 12) {
            schimmerFlaeche(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(height: 252)

            HStack(spacing: 10) {
                schimmerFlaeche(Circle()).frame(width: 44, height: 44)
                schimmerFlaeche(Capsule()).frame(height: 40)
            }

            schimmerFlaeche(Capsule()).frame(height: 50)

            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { i in
                    schimmerFlaeche(Capsule())
                        .frame(width: i == 0 ? 132 : 108, height: 46)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 2)
        .transition(.opacity)
    }

    /// Eine leere Flaeche mit dem wandernden Licht aus der Textzeile — ein
    /// Motiv fuer alles, was gerade laedt, statt drei verschiedene Anzeigen.
    private func schimmerFlaeche(_ form: some Shape) -> some View {
        form
            .fill(Theme.surface.opacity(0.5))
            .overlay {
                if !reduceMotion {
                    LinearGradient(colors: [.clear, Theme.textPrimary.opacity(0.06), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 140)
                        .offset(x: schimmer ? 260 : -220)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(form)
    }

    // MARK: - Das Bild

    private var bildKarte: some View {
        // Mittig. Ohne das saß die Karte am linken Rand, weil ein `scaledToFit`
        // im ZStack nur so breit wird wie es muss.
        ZStack(alignment: .center) {
            if let daten = anzuzeigen, let ui = UIImage(data: daten) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 186)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.09), lineWidth: 1)
                    )
                    .padding(9)
                    .padding(.bottom, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.clear)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .shadow(color: Theme.textPrimary.opacity(0.14), radius: 14, x: 0, y: 8)
                    // Während er arbeitet, liegt das Bild ruhig unter einem
                    // Schleier — es ist gerade nicht deins, es ist bei ihm.
                    .overlay {
                        if isWorking {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.background.opacity(0.32))
                                .padding(9)
                                .padding(.bottom, 6)
                        }
                    }
                    // Der Stift geht ueber den Abzug. Nur ueber dem ORIGINAL:
                    // beim Vorher/Nachher-Vergleich waeren die Anmerkungen auf
                    // dem fertigen Bild eine Kritik an der eigenen Arbeit.
                    .overlay {
                        if !isWorking, !zeigeVorher, before == nil {
                            DirectorInkNotes(marks: marks, active: true)
                                .padding(9)
                                .padding(.bottom, 6)
                        }
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if before != nil && !isWorking {
                vergleichKnopf
            }
        }
    }

    // MARK: - Der Director's Cut

    /// Sagt, WO man ist und WAS ein Tipp tut.
    ///
    /// Vorher stand hier nur „AFTER" mit einem Finger-Symbol. Das benennt den
    /// Zustand, aber nicht das Paar — wer nicht tippt, erfaehrt nie, dass es
    /// ueberhaupt ein Vorher gibt. Und ein Symbol allein liest niemand als
    /// „hier kann man umschalten".
    ///
    /// Jetzt steht beides da: der aktuelle Zustand fett, dahinter in
    /// Grauweiss, was der Tipp bringt. Damit ist der Vergleich schon aus dem
    /// Stand zu verstehen, ohne ihn ausprobiert zu haben.
    private var standMarke: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 9.5, weight: .bold))
            Text(zeigeVorher ? "BEFORE" : "AFTER")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.1)
                .contentTransition(.opacity)
            Text(zeigeVorher ? "TAP FOR AFTER" : "TAP FOR BEFORE")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.66))
                .contentTransition(.opacity)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.46), in: Capsule())
        .padding(10)
    }

    private func seitenVerhaeltnis(_ bild: UIImage) -> CGFloat {
        guard bild.size.height > 0 else { return 1 }
        // Gedeckelt, damit ein extremes Panorama oder ein sehr schmales
        // Hochformat den Bildschirm nicht sprengt.
        return min(max(bild.size.width / bild.size.height, 0.55), 1.8)
    }

    /// Original und Ergebnis im selben Rahmen, umgeschaltet per Tipp.
    ///
    /// Hier lag ein Schieber mit Trennlinie. Der zeigt beide Zustaende
    /// gleichzeitig, aber er verlangt auch, dass man ihn greift und haelt —
    /// und die Linie liegt die ganze Zeit quer durchs Gesicht. Beim ERGEBNIS
    /// will man nicht vergleichen, sondern sehen, was herausgekommen ist.
    ///
    /// Die Hoehe kommt aus dem Bildschirm, nicht aus einer festen Zahl: bei
    /// 186 Punkten wie frueher war das Ergebnis eine Briefmarke unter einer
    /// Liste. Es ist das Einzige, worauf es hier ankommt.
    @ViewBuilder
    private func directorsCut(vorher: Data, nachher: Data) -> some View {
        if let vorherBild = UIImage(data: vorher), let nachherBild = UIImage(data: nachher) {
            VStack(spacing: 14) {
                // Platz fuer „Start over" oben rechts. Ohne den liegt der
                // Knopf auf dem Bild — im Simulator genau so gesehen.
                Color.clear.frame(height: 26)
                // EIN TIPP TAUSCHT, KEIN REGLER.
                //
                // Hier lag ein `BeforeAfterSlider` mit weisser Trennlinie und
                // Griff. Der kann mehr — man zieht die Kante beliebig weit —,
                // aber er verlangt auch mehr: man muss ihn greifen und halten,
                // und die Linie liegt die ganze Zeit quer durchs Gesicht.
                //
                // Beim ERGEBNIS will man nicht vergleichen, sondern sehen, was
                // herausgekommen ist. Ein Tipp, ein weicher Wechsel, fertig.
                //
                // UND DER RAHMEN LIEGT AM FOTO, nicht an einer festen Hoehe.
                // Vorher stand hier `frame(height:)` — bei einem Hochformat
                // blieben links und rechts leere Balken stehen. Jetzt gibt das
                // Seitenverhaeltnis des Bildes die Form vor und die Hoehe ist
                // nur noch gedeckelt.
                Color.clear
                    .aspectRatio(seitenVerhaeltnis(nachherBild), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.46)
                    .overlay {
                        ZStack {
                            Image(uiImage: nachherBild).resizable().scaledToFill()
                                .opacity(zeigeVorher ? 0 : 1)
                            Image(uiImage: vorherBild).resizable().scaledToFill()
                                .opacity(zeigeVorher ? 1 : 0)
                        }
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomLeading) { standMarke }
                    // Der Rahmen der Library: 9 Punkt Polster, Glas, Ecke 23.
                    // Wer dort seine Bilder ansieht, erkennt hier dieselbe Form.
                    .padding(9)
                    .glassEffect(.regular.interactive(),
                                 in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .onTapGesture {
                        withAnimation(.smooth(duration: 0.28)) { zeigeVorher.toggle() }
                    }
                    .shadow(color: Theme.textPrimary.opacity(0.12), radius: 14, y: 7)

                HStack(spacing: 8) {
                    Text("THE DIRECTOR'S CUT")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).fixedSize()
                    Rectangle().fill(Theme.textPrimary.opacity(0.10)).frame(height: 1)
                }

                // DREI WEGE, NACH WICHTIGKEIT.
                //
                // Behalten ist der Normalfall und bekommt die volle Breite.
                // Darunter die beiden Fortsetzungen: dasselbe Bild weiter
                // bearbeiten, oder eine andere Richtung derselben Vorlage.
                Button(action: onKeep) {
                    Label("Keep it", systemImage: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.accent, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.28), radius: 10, y: 4)
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button(action: onKeepEditing) {
                        Label("Keep editing", systemImage: "wand.and.stars")
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.textPrimary.opacity(0.10), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: onTryAnother) {
                        Text("Try another")
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.textPrimary.opacity(0.10), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Seine Zeile. Kein Rahmen, kein Hintergrund, keine Ueberschrift.
    private func einschaetzung(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15.5, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    // MARK: - Die Ergebnis-Buehne

    /// Foto und Figur NEBENEINANDER.
    ///
    /// Vorher stand die Figur breit ueber dem Bild und das Bild darunter
    /// mittig — zwei Dinge untereinander, die nichts miteinander zu tun
    /// hatten. Jetzt steht sie rechts daneben, unten buendig, und schaut auf
    /// den Abzug, den sie gerade angestrichen hat.
    ///
    /// `.bottom` als Ausrichtung ist nicht Geschmack: die Fuesse der Figur
    /// sollen auf derselben Linie stehen wie die Unterkante des Bildes,
    /// sonst schwebt sie daneben.
    private var ergebnisBuehne: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bildKarte
                .frame(maxWidth: .infinity)
            mascot(.nebenDemFoto)
        }
    }


    /// Was die Figur zur gerade gewaehlten Karte sagt.
    ///
    /// KEIN zusaetzlicher Modellaufruf. Der Text steht bereits in der Antwort:
    /// `caption` ist die eine Zeile, mit der der Director diese Richtung
    /// begruendet hat. Fuer Katalog-Looks kommt die Beschreibung des Looks
    /// dazu — „Crisp Xenon flash & warm skin" sagt in vier Woertern, WAS es
    /// technisch ist, und genau das fehlte dem Nutzer.
    private func sprechblase(fuer option: DirectorAPI.Option) -> some View {
        let hausLook = option.preview.flatMap { name -> DigiCamStyles.Style? in
            guard name.hasPrefix("card_look_") else { return nil }
            return DigiCamStyles.style(id: String(name.dropFirst("card_look_".count)))
        }
        let satz = [hausLook?.subtitle, option.caption]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 3) {
            Text(option.label)
                .font(.system(size: 12.5, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(satz.isEmpty ? option.caption : satz)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 190, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.textPrimary.opacity(0.09), lineWidth: 1))
        .shadow(color: Theme.textPrimary.opacity(0.14), radius: 12, y: 5)
        // Nach links aus der Figur heraus, damit sie am Bildrand nicht
        // abgeschnitten wird.
        .offset(x: -118, y: -6)
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomTrailing)))
    }

    /// Nur neu messen, wenn sich wirklich das Foto oder der Zustand aendert.
    /// Ohne eigenen Schluessel liefe die Messung bei jedem Neuzeichnen erneut.
    private var markKey: String {
        "\(isWorking)-\(before != nil)-\(photo?.count ?? 0)"
    }

    private var anzuzeigen: Data? {
        if let before, zeigeVorher { return before }
        return photo
    }

    /// Vorher/Nachher am Bild selbst, kein eigener Reiter.
    private var vergleichKnopf: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { zeigeVorher.toggle() }
            onCompare()
        } label: {
            Text(zeigeVorher ? "Before" : "After")
                .font(.system(size: 11.5, weight: .black, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Theme.textPrimary.opacity(0.62), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(18)
    }

    // MARK: - Arbeit und Befund

    private var arbeitsZeile: some View {
        HStack(spacing: 9) {
            // Kein Kreisel mehr. Ein Kreisel sagt „das System arbeitet"; hier
            // soll aber jemand mitdenken. Stattdessen wandert ein Licht durch
            // die Zeile selbst — dieselbe Bildsprache wie die Lupe darueber,
            // und es nimmt keinen eigenen Platz weg.
            let zeile = note ?? arbeitsStufen[min(stufe, arbeitsStufen.count - 1)]
            Text(zeile)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .overlay {
                    if !reduceMotion {
                        LinearGradient(
                            colors: [.clear, Theme.textPrimary.opacity(0.7), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 80)
                        .offset(x: schimmer ? 210 : -150)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .mask { Text(zeile).font(.system(size: 17, weight: .semibold, design: .rounded)) }
                    }
                }
                .contentTransition(.opacity)
                .id(zeile)
                .transition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

}
