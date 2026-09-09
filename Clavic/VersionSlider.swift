//
//  VersionSlider.swift
//  Clavic
//
//  Vorher/Nachher als GRIFF, den man zieht — und bei mehreren Bearbeitungen
//  zusaetzlich als Weg durch jeden einzelnen Zwischenstand.
//
//  WAS VORHER FALSCH WAR. Der Vergleich lief ueber EINEN Tipp aufs Bild: einmal
//  tippen zeigt das Original, nochmal tippen das Ergebnis. Das ist ein Schnitt.
//  Man sieht zwei Zustaende, aber nie den Uebergang — und genau der ist das,
//  was der Filter gemacht hat. Wer drei Mal nachbearbeitet hat, sah davon
//  ohnehin nur den ersten und den letzten Stand; alles dazwischen war weg.
//
//  ZWEI BEDIENUNGEN, WEIL ES ZWEI FRAGEN SIND:
//
//  1. „Was hat sich veraendert?" — der Griff im Bild. Links vom Griff das
//     Original, rechts der gewaehlte Stand, deckungsgleich uebereinander. Der
//     Griff folgt dem Finger genau. Beide Bilder sind gleichzeitig zu sehen,
//     an derselben Stelle, und das Auge vergleicht selbst.
//
//  2. „Wie ist es dahin gekommen?" — die Schrittleiste darunter. Sie erscheint
//     nur, wenn es mehr als einen Bearbeitungsschritt gab. Beim Ziehen wird
//     zwischen benachbarten Staenden UEBERBLENDET, nicht umgeschaltet: das Bild
//     wandert weich von Fassung zu Fassung, statt zu springen.
//
//  Warum nicht beides in einer Geste? Weil ein Wischbalken die Breite EINMAL
//  aufteilt. Er kann entweder „Original gegen Endstand" zeigen oder „Schritt 2
//  gegen Schritt 3" — nicht beides an derselben Fingerposition. Der Versuch,
//  die Kette auf die Balkenposition zu legen, hat genau eine Folge: bei drei
//  oder mehr Staenden zeigt die Ausgangsansicht nicht mehr das Ergebnis,
//  sondern irgendeinen Zwischenstand. Also lieber zwei ehrliche Regler als
//  einer, der beides halb kann.
//
//  Bei nur zwei Staenden — also im Normalfall „Foto rein, Bild raus" — faellt
//  die Leiste ganz weg und es bleibt ein reiner Vorher/Nachher-Schieber.
//

import SwiftUI

struct VersionSlider: View {
    /// Alle Staende in Reihenfolge: `[0]` ist das Original, der letzte das
    /// Ergebnis. Mit weniger als zwei Eintraegen gibt es nichts zu vergleichen,
    /// dann zeigt die Ansicht einfach das Bild.
    let versions: [UIImage]

    /// Beschreibt den Schritt von `versions[k]` zu `versions[k+1]`. Darf leer
    /// oder kuerzer sein — fehlt ein Text, steht dort „Step k".
    var titles: [String] = []

    var cornerRadius: CGFloat = 20
    /// Aus, wo kein Platz ist (kleine Blase im Chat). Bei zwei Staenden hat sie
    /// ohnehin nichts zu tun und erscheint nie.
    var showsRail: Bool = true
    /// Einmaliger Wisch beim Erscheinen. Ohne ihn steht der Griff am Rand und
    /// niemand weiss, dass man ziehen kann.
    var showsHint: Bool = true

    /// Tippen (statt Ziehen) auf das Bild. Ohne das waere in der Chat-Blase der
    /// Weg ins Vollbild weg — die Ziehgeste schluckt sonst jeden Tipp.
    var onTap: (() -> Void)? = nil

    /// Anteil des Bildes, der links vom Griff das ORIGINAL zeigt.
    ///
    /// Startwert 0,12: das Ergebnis bleibt die Hauptsache — man hat es gerade
    /// erstellt und will es sehen — aber die Naht steht sichtbar im Bild, statt
    /// sich am Rand zu verstecken.
    @State private var teiler: CGFloat = 0.12
    /// Position in der Kette, 0 … versions.count-1. Gebrochene Werte blenden
    /// zwischen zwei Staenden ueber.
    @State private var stand: CGFloat = 0
    @State private var zieht = false
    @State private var leisteZieht = false
    @State private var hinweisGelaufen = false
    @State private var letzteRasterung = -1
    @State private var teilerVorZug: CGFloat = 0.12

    private var anzahl: Int { versions.count }
    private var hatVergleich: Bool { anzahl >= 2 }
    /// Die Leiste lohnt erst ab drei Staenden — bei zweien waere sie ein Regler
    /// mit genau einer Stellung.
    private var zeigtLeiste: Bool { showsRail && anzahl >= 3 }

    private var seitenverhaeltnis: CGFloat {
        guard let letzte = versions.last, letzte.size.height > 0 else { return 1 }
        return letzte.size.width / letzte.size.height
    }

    var body: some View {
        bildFlaeche
            .onAppear {
                stand = CGFloat(max(anzahl - 1, 0))
                spielHinweis()
            }
    }

    // MARK: Bild

    private var bildFlaeche: some View {
        Color.clear
            .aspectRatio(seitenverhaeltnis, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack(alignment: .topLeading) {
                        // Rechts: der gewaehlte Stand. Zwei Nachbarn
                        // uebereinander, die Deckkraft macht den Uebergang.
                        gewaehlterStand(w: w, h: h)

                        // Links: das Original, bis zum Griff freigelegt.
                        if hatVergleich {
                            bild(versions[0], w: w, h: h)
                                .mask(alignment: .leading) {
                                    Rectangle().frame(width: max(0, w * teiler))
                                }
                        }

                        if hatVergleich {
                            marken(w: w)
                            griff(w: w, h: h)
                        }
                        if zeigtLeiste {
                            // IM Bild, nicht darunter.
                            //
                            // Darunter hätte sie eine eigene Breite gebraucht:
                            // das Bild sitzt „fit" in seinem Platz und ist
                            // meist schmaler als die Spalte, die Leiste lief
                            // also über beide Bildkanten hinaus. Im Bild ist
                            // die Breite von selbst richtig — und die Leiste
                            // liegt da, wo man beim Vergleichen ohnehin
                            // hinsieht.
                            leiste
                                .frame(width: w, height: h, alignment: .bottom)
                        }
                    }
                    .frame(width: w, height: h)
                    .contentShape(Rectangle())
                    .gesture(hatVergleich ? zieherGeste(w: w) : nil)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }

    /// Der Stand rechts vom Griff — zwischen zwei Nachbarn ueberblendet.
    private func gewaehlterStand(w: CGFloat, h: CGFloat) -> some View {
        let unten = min(Int(stand), max(anzahl - 1, 0))
        let oben = min(unten + 1, max(anzahl - 1, 0))
        let anteil = stand - CGFloat(unten)
        return ZStack {
            if versions.indices.contains(unten) { bild(versions[unten], w: w, h: h) }
            if oben != unten, versions.indices.contains(oben) {
                bild(versions[oben], w: w, h: h).opacity(Double(anteil))
            }
        }
    }

    private func bild(_ img: UIImage, w: CGFloat, h: CGFloat) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: w, height: h)
            .clipped()
    }

    // MARK: Der Griff
    //
    // Bewusst NICHT die uebliche weisse Linie mit dem weissen Kreis darauf. Die
    // liegt auf hellen Bildern flach auf und verschwindet. Hier: ein Verlauf im
    // Balken, damit er als Glas und nicht als Farbe liest, ein weicher Schein
    // dahinter, der ihn auf jedem Untergrund abhebt, und ein Griff aus
    // Milchglas mit zwei Pfeilen — dieselbe Sprache wie der Rest der App.

    private func griff(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // Schein hinter der Naht. Ohne ihn verschwindet eine weisse Linie
            // auf einem hellen Bild und saeuft auf einem dunklen ab — im
            // Simulator beides gesehen.
            Rectangle()
                .fill(Color.white.opacity(0.30))
                .frame(width: 14)
                .blur(radius: 7)

            // Zwei Linien statt einer: die dunkle darunter gibt der weissen
            // eine Kante, sonst liegt sie flach auf dem Bild auf.
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .frame(width: 4)
                .blur(radius: 1.5)

            Rectangle()
                .fill(LinearGradient(colors: [.white, .white.opacity(0.78), .white],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 2)

            knopf
        }
        .frame(height: h)
        .position(x: max(0, min(w, w * teiler)), y: h / 2)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.9), value: zieht)
    }

    /// Hochkant, weiss, mit blauen Pfeilen.
    ///
    /// Der erste Anlauf war ein Quadrat aus `.ultraThinMaterial` — ueber einem
    /// Foto wurde daraus ein grauer Klecks, der wie ein Platzhalter aussah.
    /// Deckendes Weiss traegt die Markenfarbe und liest auf jedem Untergrund.
    /// Die Hochkantform nimmt ausserdem die Richtung der Naht auf, statt sie
    /// mit einem Kreis zu unterbrechen.
    private var knopf: some View {
        HStack(spacing: 1) {
            Image(systemName: "chevron.compact.left")
            Image(systemName: "chevron.compact.right")
        }
        .font(.system(size: 15, weight: .black))
        .foregroundStyle(Theme.accent)
        .frame(width: 30, height: 46)
        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .scaleEffect(zieht ? 1.1 : 1)
    }

    /// „Before" und „After" liegen ueber dem Bild, je auf ihrer Seite.
    ///
    /// Sie blenden aus, sobald ihre Seite zu schmal wird. Ein Schild, das ueber
    /// dem falschen Bild klebt, ist schlimmer als keins.
    private func marken(w: CGFloat) -> some View {
        HStack {
            marke("BEFORE").opacity(teiler > 0.16 ? 1 : 0)
            Spacer(minLength: 0)
            marke("AFTER").opacity(teiler < 0.84 ? 1 : 0)
        }
        .padding(11)
        .frame(width: w, alignment: .top)
        .animation(.easeOut(duration: 0.18), value: teiler > 0.16)
        .animation(.easeOut(duration: 0.18), value: teiler < 0.84)
        .allowsHitTesting(false)
    }

    private func marke(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .black, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(.black.opacity(0.38), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.5))
    }

    private func zieherGeste(w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { wert in
                if !zieht { zieht = true; teilerVorZug = teiler }
                hinweisGelaufen = true          // Hinweis abbrechen, der Nutzer ist schneller
                teiler = min(1, max(0, wert.location.x / max(w, 1)))
            }
            .onEnded { wert in
                zieht = false
                // Fast keine Bewegung heisst: das war ein Tipp, kein Ziehen.
                // `minimumDistance: 0` faengt beides ab, also muss hier
                // unterschieden werden — sonst kaeme man aus der Chat-Blase
                // nie mehr ins Vollbild. Der Griff springt dann auch nicht
                // unter den Finger, sondern bleibt, wo er stand.
                let weg = hypot(wert.translation.width, wert.translation.height)
                if weg < 6, let onTap {
                    teiler = teilerVorZug
                    onTap()
                }
            }
    }

    // MARK: Schrittleiste

    private var leiste: some View {
        VStack(spacing: 7) {
            // Der Name des Standes steht ÜBER der Leiste, nicht im Griff.
            //
            // Im Griff sah er zuerst besser aus — bis „Cleaner background" am
            // rechten Ende über die Leiste hinausragte. Ein Griff muss so breit
            // bleiben wie er ist, egal wie der Schritt heißt.
            Text(standName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(.black.opacity(0.42), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                .animation(.easeInOut(duration: 0.18), value: standName)

            GeometryReader { geo in
                let w = geo.size.width
                let rand: CGFloat = 17                 // halbe Griffbreite plus Luft
                let bahn = max(w - rand * 2, 1)        // Weg der Griffmitte
                let anteil = (stand - 1) / CGFloat(max(anzahl - 2, 1))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.black.opacity(0.34))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))

                    // Ein Punkt je BEARBEITUNG — das Original ist keine Stellung.
                    //
                    // Es stand zuerst mit auf der Leiste, ganz links. Diese
                    // Stellung zeigte dann links das Original und rechts auch
                    // das Original: eine Stufe, bei der nichts passiert. Der
                    // Ausgangszustand liegt ohnehin immer auf der linken Seite
                    // des Griffs.
                    //
                    // Die Punkte sitzen GENAU auf der Bahn der Griffmitte;
                    // vorher waren sie über einen `HStack` verteilt und trafen
                    // den Griff nie — die Leiste sah dadurch schief aus.
                    ForEach(1..<anzahl, id: \.self) { i in
                        let x = rand + bahn * (CGFloat(i - 1) / CGFloat(max(anzahl - 2, 1)))
                        let erreicht = stand >= CGFloat(i) - 0.02
                        Circle()
                            .fill(erreicht ? Color.white : Color.white.opacity(0.45))
                            .frame(width: 5, height: 5)
                            .position(x: x, y: 15)
                    }

                    Capsule()
                        .fill(Theme.brandGradient)
                        .frame(width: 30, height: 24)
                        .overlay(
                            Text("\(min(Int(stand.rounded()), anzahl - 1))")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .scaleEffect(leisteZieht ? 1.12 : 1)
                        .position(x: rand + bahn * anteil, y: 15)
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(leistenGeste(rand: rand, bahn: bahn))
                .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.9), value: leisteZieht)
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }

    private var standName: String {
        let i = Int(stand.rounded())
        if i <= 0 { return String(localized: "Original") }
        let k = i - 1
        if titles.indices.contains(k), !titles[k].isEmpty { return titles[k] }
        return i == anzahl - 1 ? String(localized: "Result") : String(localized: "Step \(i)")
    }

    private func leistenGeste(rand: CGFloat, bahn: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { wert in
                if !leisteZieht { leisteZieht = true }
                let roh = (wert.location.x - rand) / max(bahn, 1)
                stand = min(CGFloat(anzahl - 1),
                            max(1, 1 + roh * CGFloat(max(anzahl - 2, 1))))
                // Ein leises Tacken an jeder Fassung — sonst fuehlt sich das
                // Ziehen an, als haette es keine Stationen.
                let naechste = Int(stand.rounded())
                if naechste != letzteRasterung, abs(stand - CGFloat(naechste)) < 0.08 {
                    letzteRasterung = naechste
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                leisteZieht = false
                // Auf die naechste Fassung einrasten: ein Stand zu 60 % ist
                // kein Ergebnis, das jemand speichern oder ansehen will.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    stand = CGFloat(Int(stand.rounded()))
                }
            }
    }

    // MARK: Hinweis

    /// Einmal kurz aufziehen und zurueck.
    ///
    /// Kein Dauerlauf: die alte Vorschau lief endlos hin und her, was auf einem
    /// Ergebnisbild unruhig ist. Ein einziger Zug genuegt, um zu zeigen, dass
    /// da etwas zu ziehen ist.
    private func spielHinweis() {
        guard showsHint, hatVergleich, !hinweisGelaufen else { return }
        hinweisGelaufen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard !zieht else { return }
            withAnimation(.easeInOut(duration: 0.75)) { teiler = 0.62 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                guard !zieht else { return }
                withAnimation(.easeInOut(duration: 0.65)) { teiler = 0.12 }
            }
        }
    }
}

// MARK: - Kette speichern und wieder auslesen

/// Packt und liest die Zwischenstände eines Bildes.
///
/// Eine eigene Stelle dafür, weil die Kette an FÜNF Orten entsteht (Director,
/// Chat, Solo Shot, Kamera, Templates) und überall gleich aussehen muss.
enum VersionChain {
    /// Lange Kante, auf die jeder gespeicherte Stand verkleinert wird.
    static let maxKante: CGFloat = 1200

    /// Kurzer Name für einen Schritt auf der Leiste.
    ///
    /// Der Prompt ist oft ein ganzer Satz. Auf der Leiste ist Platz für ein
    /// paar Wörter, also erster Satz, hart gekappt — lieber abgeschnitten als
    /// dreizeilig umbrochen.
    static func kurzerTitel(_ prompt: String, maximal: Int = 34) -> String {
        let erster = prompt.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? prompt
        let sauber = erster.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sauber.count > maximal else { return sauber }
        return String(sauber.prefix(maximal - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Ist das ein Platzhalter statt eines echten Ausgangsfotos?
    ///
    /// GEFUNDEN BEIM PRÜFEN DER LETZTEN ABLAGESTELLEN: `AiCharacter.seedImageData()`
    /// ist ein einfarbig graues Quadrat, 512 × 512. Es steht als Referenzbild in
    /// jedem AI-Charakter-Projekt, weil das Backend mindestens ein Bild braucht.
    /// Der Rückfall auf ein einzelnes Referenzbild hätte daraus ein „Before"
    /// gemacht — die Bibliothek hätte eine graue Fläche gegen das Ergebnis
    /// geschoben und wie kaputt ausgesehen.
    ///
    /// Geprüft wird nicht auf genau dieses Bild, sondern auf die Eigenschaft:
    /// eine Fläche ohne jeden Kontrast ist nie ein Foto. Damit fällt auch jeder
    /// künftige Platzhalter durch, ohne dass jemand daran denken muss.
    nonisolated static func istPlatzhalter(_ img: UIImage) -> Bool {
        let kante = 8
        var puffer = [UInt8](repeating: 0, count: kante * kante * 4)
        guard let raum = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &puffer, width: kante, height: kante,
                                  bitsPerComponent: 8, bytesPerRow: kante * 4,
                                  space: raum,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = img.cgImage else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: kante, height: kante))
        var min: UInt8 = 255, max: UInt8 = 0
        for i in stride(from: 0, to: puffer.count, by: 4) {
            for k in 0..<3 {
                let wert = puffer[i + k]
                if wert < min { min = wert }
                if wert > max { max = wert }
            }
        }
        // Vier Stufen von 255 Spielraum: JPEG-Rauschen auf einer echten Fläche
        // bleibt darunter, jedes Foto liegt weit darüber.
        return max - min <= 4
    }

    /// Verkleinert und komprimiert eine Kette fürs Ablegen im Projekt.
    ///
    /// Nicht auf dem Hauptthread aufrufen, wenn die Kette lang ist —
    /// `resized` rendert jedes Bild neu.
    nonisolated static func pack(_ staende: [Data]) -> [Data] {
        staende.compactMap { roh in
            guard let img = UIImage(data: roh) else { return nil }
            return img.resized(maxDimension: maxKante).jpegData(compressionQuality: 0.8)
        }
    }
}

extension VideoProject {
    /// Alle Stände inklusive Ergebnis, in der Reihenfolge, in der sie
    /// entstanden sind. Leer oder einelementig heißt: nichts zu vergleichen.
    var versionImages: [UIImage] {
        // Rückfall für Einträge ohne eigene Kette: ein EINZELNES Referenzbild
        // ist das Ausgangsfoto (Template-Generierungen legen es dort ab). Bei
        // zweien — Pinterest-Swap: Inspo plus Selfie — ist keins „das Vorher",
        // dann bleibt der Vergleich aus.
        let rueckfall = stepImagesData.isEmpty && referenceImagesData.count == 1
            ? referenceImagesData
            : []
        var bilder = (stepImagesData + rueckfall).compactMap { UIImage(data: $0) }
        // Ein Platzhalter ist kein Vorher — siehe `VersionChain.istPlatzhalter`.
        bilder.removeAll { VersionChain.istPlatzhalter($0) }
        if let url = localVideoURL,
           let daten = try? Data(contentsOf: url),
           let ergebnis = UIImage(data: daten) {
            bilder.append(ergebnis)
        } else if let daten = thumbnailData, let ergebnis = UIImage(data: daten) {
            bilder.append(ergebnis)
        }
        return bilder
    }

    /// Legt die Vorgeschichte ab. `staende` ist alles VOR dem Ergebnis.
    func setzeKette(_ staende: [Data], titel: [String] = []) {
        stepImagesData = VersionChain.pack(staende)
        stepTitles = titel
    }
}
