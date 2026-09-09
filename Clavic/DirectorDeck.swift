//
//  DirectorDeck.swift
//  Clavic
//
//  Der Kartenstapel, auf dem der Director seine Ideen ablegt.
//
//  EINE IDEE LIEGT VORN, DIE ANDEREN LIEGEN SICHTBAR DARUNTER.
//
//  DER STAPEL IST DER WAEHLER. Es gibt keinen zweiten Ort zum Umschalten:
//  wischen oder eine Karte darunter antippen, mehr nicht.
//
//  ER KENNT WEDER PICKS NOCH TRENDS. Er bekommt eine Liste und einen Baustein
//  fuer die Karte — deshalb kann die Trendansicht dieselbe Buehne benutzen,
//  statt eine zweite zu sein.
//
//  ── WARUM DIE REIHENFOLGE HIER DRIN LIEGT ────────────────────────────────
//
//  Der erste Anlauf hat die Reihenfolge aus `aktivID` GERECHNET: aktive Karte
//  vorn, der Rest rotiert dahinter. Beim Wischen sah das falsch aus, und zwar
//  aus einem Grund, den keine Feder heilt.
//
//  Sobald der Wisch die aktive Karte umsetzte, rechnete sich die Reihenfolge
//  neu — und damit sprang im SELBEN Bild auch `zIndex` um. Die Karte, die
//  gerade losfliegt, lag schlagartig hinter dem Stapel und schob sich sichtbar
//  RUECKWAERTS durch die anderen hindurch. Kein Wackeln: eine Karte, die nach
//  hinten teleportiert, waehrend sie noch zur Seite laeuft.
//
//  Deshalb haelt der Stapel seine Reihenfolge SELBST, und waehrend einer
//  Bewegung wird sie nicht angefasst. Erst wenn die Bewegung durch ist, wird
//  die abgelegte Karte hinten eingereiht — ohne Animation, weil sie an dieser
//  Stelle ohnehin unsichtbar ist.
//
//  Zwei Bewegungen, eine Sprache:
//
//    WISCHEN — die vordere Karte laeuft zur Seite und liegt dabei die ganze
//    Zeit OBEN. Die anderen ruecken um einen Rang auf. Erst ganz zum Schluss
//    dreht sich die Reihenfolge.
//
//    TIPPEN auf eine hintere Karte — sie wird nach oben gezogen und ist
//    waehrend der ganzen Bewegung die oberste. Das ist auch physikalisch
//    richtig: man zieht eine Karte heraus und legt sie obenauf. Hier darf die
//    Reihenfolge sofort stehen, weil die Karte, die nach hinten geht, unter
//    der neuen verschwindet.
//

import SwiftUI

struct DirectorDeck<Karte: View>: View {
    let optionen: [DirectorAPI.Option]
    /// Welche vorn liegen soll. Wird beim Aufbau und bei Aenderungen von
    /// aussen uebernommen — waehrend einer Bewegung nie.
    let aktivID: String?
    /// Hoehe EINER Karte. Der Stapel braucht darueber hinaus Platz fuer die
    /// Kanten der Karten dahinter.
    let hoehe: CGFloat
    var onAktiv: (DirectorAPI.Option) -> Void = { _ in }
    @ViewBuilder let karte: (DirectorAPI.Option) -> Karte

    /// Die Wahrheit ueber die Lage — vorderste zuerst. Nur Kennungen, damit
    /// eine neue Antwort den Stapel nicht durcheinanderbringt.
    @State private var reihenfolge: [String] = []
    /// Was gerade in Bewegung ist. Solange das steht, bleibt `reihenfolge`
    /// beim Wischen unangetastet.
    @State private var flug: Flug?
    /// Wie weit die vordere Karte gerade mitgezogen wird.
    @GestureState private var zug: CGFloat = 0

    private struct Flug: Equatable {
        let id: String
        /// −1 oder +1: die Karte fliegt zur Seite (Wisch).
        /// 0: die Karte wird nach vorn gezogen (Tipp auf eine hintere).
        let richtung: CGFloat
        var istWisch: Bool { richtung != 0 }
    }

    /// Hoechstens zwei Kanten sind zu sehen. Ein tieferer Stapel bringt keine
    /// Information mehr, nur Unruhe — und mehr als drei Richtungen gibt es
    /// ohnehin nie.
    private static var sichtbar: Int { 3 }
    private static var versatzX: CGFloat { 21 }
    private static var versatzY: CGFloat { 15 }
    /// Eine Feder, kein Ease: der Stapel soll sich anfassen lassen.
    private static var feder: Animation { .spring(response: 0.44, dampingFraction: 0.82) }

    private var geordnet: [DirectorAPI.Option] {
        let nach = Dictionary(uniqueKeysWithValues: optionen.map { ($0.id, $0) })
        return reihenfolge.compactMap { nach[$0] }
    }

    private var kanten: CGFloat {
        CGFloat(min(max(optionen.count - 1, 0), Self.sichtbar - 1)) * Self.versatzY
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(geordnet) { option in
                let platz = platzierung(option)
                karte(option)
                    .frame(height: hoehe)
                    .scaleEffect(platz.groesse, anchor: .top)
                    .offset(x: platz.x, y: platz.y)
                    // Nur angedeutet. Ein staerkerer Winkel liesse den Stapel
                    // wie ein Karussell aussehen statt wie Papier.
                    .rotationEffect(.degrees(platz.drehung), anchor: .bottom)
                    // Die hinteren treten auch farblich zurueck. Weisse Karten
                    // auf cremefarbenem Grund waren sonst nur als Schattenkante
                    // zu ahnen — im Simulator so gesehen.
                    .opacity(platz.deckkraft)
                    .zIndex(platz.z)
                    .allowsHitTesting(platz.rang < Self.sichtbar && flug == nil)
                    // NUR auf den hinteren Karten. Auf der vorderen wuerde sie
                    // mit dem Knopf darauf um denselben Tipp streiten.
                    .onTapGesture { if platz.rang > 0 { zieheVor(option) } }
                    .gesture(ziehen,
                             including: platz.rang == 0 && optionen.count > 1 && flug == nil
                                 ? .all : .subviews)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: hoehe + kanten)
        .onAppear { ordneNeu() }
        .onChange(of: optionen.map(\.id)) { _, _ in ordneNeu() }
        .onChange(of: aktivID) { _, neu in
            // Von aussen gesetzt — etwa wenn das Trendurteil den Besten nach
            // vorn holt. Waehrend einer Bewegung nicht dazwischenfunken.
            guard flug == nil, let neu, reihenfolge.first != neu,
                  reihenfolge.contains(neu) else { return }
            withAnimation(Self.feder) { reihenfolge = rotiert(auf: neu) }
        }
    }

    // MARK: - Wo eine Karte liegt

    private struct Platz {
        let rang: Int
        let x: CGFloat
        let y: CGFloat
        let groesse: CGFloat
        let drehung: Double
        let deckkraft: Double
        let z: Double
    }

    private func ruhe(_ rang: Int, zug: CGFloat = 0) -> Platz {
        Platz(rang: rang,
              x: CGFloat(rang) * Self.versatzX + zug,
              y: CGFloat(rang) * Self.versatzY,
              groesse: 1 - CGFloat(rang) * 0.05,
              drehung: rang == 0 ? Double(zug) / 34 : Double(rang) * 1.5,
              deckkraft: tiefe(rang),
              z: Double(Self.sichtbar - rang))
    }

    private func platzierung(_ option: DirectorAPI.Option) -> Platz {
        let index = reihenfolge.firstIndex(of: option.id) ?? 0
        let fliegt = flug?.id == option.id

        // WISCH: die abfliegende Karte behaelt Rang 0 und liegt OBEN, alle
        // anderen ruecken schon einen Rang auf. Die Reihenfolge selbst bleibt
        // unangetastet — genau daran ist der erste Anlauf gescheitert.
        if let flug, flug.istWisch {
            if fliegt {
                return Platz(rang: 0,
                             x: flug.richtung * 520,
                             y: 0,
                             groesse: 0.97,
                             drehung: Double(flug.richtung) * 9,
                             // Weich weg, nicht schlagartig: sie wird gleich
                             // hinten wieder eingereiht.
                             deckkraft: 0,
                             z: 1000)
            }
            return ruhe(max(index - 1, 0))
        }

        // TIPP: die Reihenfolge steht schon richtig, die geholte Karte liegt
        // aber waehrend der ganzen Bewegung obenauf — sie wird ja aus dem
        // Stapel herausgezogen.
        var platz = ruhe(index, zug: index == 0 ? zug : 0)
        if fliegt {
            platz = Platz(rang: platz.rang, x: platz.x, y: platz.y,
                          groesse: platz.groesse, drehung: platz.drehung,
                          deckkraft: platz.deckkraft, z: 1000)
        }
        return platz
    }

    private func tiefe(_ rang: Int) -> Double {
        switch rang {
        case 0:  return 1
        case 1:  return 0.80
        case 2:  return 0.58
        default: return 0
        }
    }

    // MARK: - Bewegungen

    private var ziehen: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($zug) { wert, stand, _ in stand = wert.translation.width }
            .onEnded { wert in wischWeg(wert.translation.width) }
    }

    /// Ein Wisch legt die vordere Karte ab und holt die naechste vor.
    ///
    /// Unter der Schwelle passiert nichts: die Karte federt zurueck, weil
    /// `zug` beim Loslassen von selbst auf null geht. Das ist die Rueckmeldung
    /// „ich habe dich gehoert, aber du warst nicht entschlossen".
    private func wischWeg(_ dx: CGFloat) {
        guard flug == nil, reihenfolge.count > 1, abs(dx) > 56,
              let gehend = reihenfolge.first else { return }

        // AN DER ANIMATION, NICHT AN EINER ZAHL.
        //
        // Hier stand ein `Task.sleep` von 0,42 Sekunden — geraten passend zur
        // Feder. Solange es lief, war der Stapel gesperrt und jeder weitere
        // Wisch fiel ins Leere; wer zweimal schnell wischte, kam einmal weiter.
        // `completionCriteria` sagt genau dann Bescheid, wenn die Bewegung
        // wirklich durch ist.
        withAnimation(Self.feder, completionCriteria: .logicallyComplete) {
            flug = Flug(id: gehend, richtung: dx > 0 ? 1 : -1)
        } completion: {
            guard flug?.id == gehend else { return }
            var neu = reihenfolge
            neu.removeFirst()
            neu.append(gehend)
            // Ohne Animation: die Karte liegt in diesem Moment unsichtbar am
            // Rand, ihren Weg nach hinten muss niemand sehen.
            var ohne = Transaction(); ohne.disablesAnimations = true
            withTransaction(ohne) {
                reihenfolge = neu
                flug = nil
            }
            meldeVorne()
        }
    }

    /// Eine hintere Karte wird nach vorn geholt — dieselbe Feder, aber sie
    /// kommt UEBER den Stapel statt zur Seite.
    private func zieheVor(_ option: DirectorAPI.Option) {
        guard flug == nil, reihenfolge.first != option.id else { return }
        withAnimation(Self.feder, completionCriteria: .logicallyComplete) {
            flug = Flug(id: option.id, richtung: 0)
            reihenfolge = rotiert(auf: option.id)
        } completion: {
            guard flug?.id == option.id else { return }
            var ohne = Transaction(); ohne.disablesAnimations = true
            withTransaction(ohne) { flug = nil }
            meldeVorne()
        }
    }

    // MARK: - Reihenfolge fuehren

    private func ordneNeu() {
        let ids = optionen.map(\.id)
        guard Set(reihenfolge) != Set(ids) || reihenfolge.isEmpty else { return }
        // Eine neue Antwort setzt den Stapel zurueck: aktive Karte nach vorn.
        let start = aktivID.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        if let start, let i = ids.firstIndex(of: start) {
            reihenfolge = Array(ids[i...]) + Array(ids[..<i])
        } else {
            reihenfolge = ids
        }
        flug = nil
    }

    private func rotiert(auf id: String) -> [String] {
        guard let i = reihenfolge.firstIndex(of: id) else { return reihenfolge }
        return Array(reihenfolge[i...]) + Array(reihenfolge[..<i])
    }

    private func meldeVorne() {
        guard let vorn = reihenfolge.first,
              let option = optionen.first(where: { $0.id == vorn }) else { return }
        onAktiv(option)
    }
}
