//
//  MascotStage.swift
//  Clavic
//
//  Das Chamäleon oben im Director-Tab.
//
//  KEINE EIGENE EBENE: die Figur ist das erste Element IM Scroll-Inhalt, nicht
//  ein fester Streifen darüber. Wer scrollt, schiebt sie mit dem Hintergrund
//  nach oben weg und der Inhalt rückt nach. Sie fängt keine Berührungen ab
//  (`allowsHitTesting(false)`), sonst schluckt der AVPlayerLayer die Wischgeste.
//
//  ZWEI EBENEN, WEIL EIN SCHNITT SICHTBAR WÄRE
//  ------------------------------------------------------------------
//  Alle Clips sind mit WAN 3.0 Prime aus `LOOPstartend.png` erzeugt und enden
//  in derselben Pose. Trotzdem reicht hartes Umschalten NICHT, aus zwei
//  gemessenen Gründen:
//
//  1. Der Wurf endet unsauber. Die geworfenen Fotos berühren von 2,50 s bis
//     3,50 s die Unterkante des Bildes (y = 359 von 360) — ab 3,60 s springt
//     die unterste Bewegung auf y = 308 zurück: die Karten fliegen NICHT hinaus,
//     sie lösen sich rund 52 px über dem Rand in Luft auf. Daran sieht man
//     sofort, dass da ein Video läuft.
//  2. `replaceCurrentItem` zeigt beim Wechsel einen leeren Frame — daraus wird
//     ein sichtbarer Schnitt statt eines Loops.
//
//  Beides löst dieselbe Maßnahme: ZWEI `AVPlayerLayer` übereinander, zwischen
//  denen überblendet wird.
//
//  WANN geblendet wird, ist dabei das Entscheidende — und der erste Versuch bei
//  3,45 s war falsch. Dort steht die Figur mitten in der großen Armbewegung und
//  weicht noch um 32/255 von der Idle-Startpose ab; die Blende sah deshalb wie
//  ein Schnitt auf eine völlig andere Pose aus. GEMESSEN, Wurf gegen
//  Idle-Startpose:
//     3,47 s   31,6/255   ← hier wurde vorher geblendet
//     3,67 s   14,1/255
//     3,97 s    6,5/255
//     4,17 s    5,5/255   ← ab hier Rauschniveau, die Figur steht
//  Deshalb startet die Blende jetzt bei 4,20 s und dauert 0,50 s. Sie endet bei
//  4,70 s, also noch im Clip (5,00 s), und trifft eine Pose, die praktisch
//  identisch ist. Zwischen zwei Idle-Clips genügen 0,30 s.
//
//  ZEITEN DES WURFS (am Clip vermessen, 5,00 s / 150 Frames):
//     2,5–3,1 s  Karten fallen am stärksten
//     3,50 s     ← die echten Karten starten (`handoffTime`)
//     3,5–3,7 s  der letzte Kartensplitter verlässt den Rand
//     3,97 s     Figur hat ausgependelt
//     4,20 s     ← Kreuzblende beginnt (`fadeStart`), Pose sitzt
//

import AVFoundation
import SwiftUI

/// Was die Figur gerade tut.
enum MascotAct: Equatable {
    /// Idle-Loops.
    case idle
    /// Der Agent arbeitet — Idle plus Aktivitätspunkt.
    case working
    /// Einmaliger Wurf, danach zurück in die Idle-Loops.
    case throwing
}

struct MascotStage: View {
    var act: MascotAct = .idle
    /// Zählt hoch, wenn geworfen werden soll. Ein Zähler statt eines Schalters,
    /// weil der Wurf MEHRMALS läuft: einmal zur Begrüßung und danach jedes Mal,
    /// wenn der Agent neue Vorschläge liefert. Mit einer Einmal-Sperre blieben
    /// die Vorschläge ab dem zweiten Mal unsichtbar, weil die Übergabe fehlt.
    var throwToken: Int = 0
    /// true, solange der Begrüßungswurf noch aussteht.
    var expectsThrow: Bool = false
    /// Höhe des Blocks im Fluss.
    var height: CGFloat = 250
    /// Ist das gesetzt, laeuft NUR diese eine Datei in Endlosschleife, statt
    /// der Rotation aus mehreren Clips mit Ueberblendung dazwischen. Neben dem
    /// gelesenen Foto ist genau das noetig: die Ueberblendung ist der Grund,
    /// warum man dort einen Wechsel sah.
    var idleLoopURL: URL? = nil
    /// Nur der sichtbare Tab lässt die Videos laufen (Akku).
    var isActive: Bool = true
    /// true nur im leeren Auftakt: dann steht die Figur zwischen Blättern.
    /// Läuft schon ein Gespräch, soll der Kopf frei bleiben.
    var showsHabitat: Bool = true
    /// false, wenn die Umgebung den Arbeitsstand selbst erzählt. In der
    /// Werkbank steht darunter bereits „Checking what's in the way…" — die
    /// Sprechblase der Figur sagte daneben dasselbe noch einmal.
    var showsActivityPill: Bool = true
    /// Feuert bei 3,50 s des Wurfs — hier startet die native Karten-Animation.
    var onHandoff: () -> Void = {}
    /// Feuert, wenn der Wurf in die Idle-Loops übergeht.
    var onThrowFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ruhiges Atmen — nur im Standbild-Zweig ohne Videos.
    @State private var breathing = false
    /// false, solange der Videolayer noch nichts anzeigen kann.
    @State private var playerReady = false

    /// Sekunde, in der die echten Karten starten müssen.
    ///
    /// GEMESSEN im Clip (25 Bilder/s, Veränderung in der unteren Bildhälfte
    /// gegen das erste Bild): die geworfenen Karten sind ab 1,5 s im Bild, am
    /// stärksten bei 2,5 s, ab 3,9 s ganz weg. Bei 3,50 s waren sie schon zu
    /// rund 70 % verschwunden — deshalb entstand eine sichtbare Lücke zwischen
    /// Wurf und echten Karten. Bei 2,95 s greift die Übergabe, während die
    /// Karten im Video noch unterwegs sind; bis sie dort verschwinden, sind die
    /// echten unten angekommen.
    static let handoffTime: Double = 2.95
    /// Sekunde, in der die Kreuzblende in den Idle-Loop beginnt.
    static let fadeStart: Double = 4.20
    /// Dauer dieser Blende. Deckt das Verschwinden der Karten zu.
    static let throwFade: Double = 0.50
    /// Blende zwischen zwei Idle-Clips.
    static let idleFade: Double = 0.30
    /// Blende IN den Wurf hinein. Etwas kürzer, damit die Geste nicht träge wirkt.
    static let throwEnter: Double = 0.40

    /// Können die Clips überhaupt laufen? Eine Stelle, eine Antwort — vorher
    /// hing das Sicherheitsnetz IM Bild-Zweig und feuerte die Übergabe sofort
    /// mit, sobald der Zähler stieg. Dann lagen die Karten schon da, bevor der
    /// Wurf begonnen hatte.
    private var canPlayVideos: Bool {
        !reduceMotion && Self.throwURL != nil
            && (idleLoopURL != nil || !Self.idleURLs.isEmpty)
    }

    var body: some View {
        ZStack {
            if canPlayVideos, let throwURL = Self.throwURL {
                // UNTERLAGE. Der Videolayer erscheint schlagartig, sobald er
                // sein erstes Bild hat — beim Kaltstart 220 ms nach dem Rest
                // der Oberfläche, gemessen. Solange steht hier das Standbild,
                // und zwar dasselbe Bild in derselben Pose wie Bild 0 des
                // Wurfs (`LOOPstartend.png`). Der Wechsel ist deshalb nicht zu
                // sehen; ausgeblendet wird trotzdem weich.
                if !playerReady {
                    Image("clavic_mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(height: height * 0.991)
                        .frame(width: height, height: height)
                        .mask(Self.fogMask)
                        .transition(.opacity)
                }

                MascotPlayer(
                    throwURL: throwURL,
                    idleURLs: Self.idleURLs,
                    idleLoopURL: idleLoopURL,
                    scanURL: Self.scanURL,
                    // Waehrend er das Foto liest, haelt er die Lupe darueber —
                    // statt danebenzustehen, als ginge ihn das nichts an.
                    isScanning: act == .working,
                    throwToken: throwToken,
                    expectsThrow: expectsThrow,
                    isActive: isActive,
                    onHandoff: onHandoff,
                    onThrowFinished: onThrowFinished,
                    onReady: {
                        withAnimation(.easeOut(duration: 0.22)) { playerReady = true }
                    }
                )
                .frame(width: height, height: height)
                .mask(Self.fogMask)
            } else {
                Image("clavic_mascot")
                    .resizable()
                    .scaledToFit()
                    // GEMESSEN: die Figur füllt im Video 92,2 % der Framehöhe,
                    // im Standbild 93,1 % — ohne Ausgleich springt sie um 15 %.
                    .frame(height: height * 0.991)
                    // Ohne Videos wenigstens ruhiges Atmen, damit die Figur
                    // nicht wie ein aufgeklebter Sticker wirkt. Anker unten:
                    // die Füße bleiben stehen. Bei Reduce Motion steht sie still.
                    .scaleEffect(breathing ? 1.009 : 1.0, anchor: .bottom)
                    .animation(
                        reduceMotion ? nil
                        : .easeInOut(duration: 3.1).repeatForever(autoreverses: true),
                        value: breathing
                    )
                    .accessibilityLabel("Clavic")
                    .onAppear { breathing = true }
                    // SICHERHEITSNETZ: kann der Wurf nicht laufen (Reduce Motion,
                    // Clip fehlt), muss die Übergabe trotzdem feuern — sonst
                    // bleiben die geworfenen Karten für immer unsichtbar.
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // Ihre Umgebung. Sie liegt HINTER der Bühne. Frueher deckte der
        // Cremekasten des Videos die Mitte ab und das Blattwerk war nur links
        // und rechts zu sehen; seit die Clips ein echtes Alpha haben, wachsen
        // die Blaetter hinter der Figur durch.
        .background {
            if showsHabitat { MascotHabitat().allowsHitTesting(false) }
        }
        .clipped()
        .allowsHitTesting(false)
        .overlay(alignment: .bottom) {
            if act == .working && showsActivityPill { activityPill }
        }
        .animation(.easeInOut(duration: 0.25), value: act)
        // NUR wenn kein Video laufen kann, muss die Übergabe von Hand kommen —
        // sonst blieben die geworfenen Karten für immer unsichtbar.
        .onChange(of: throwToken) { _, token in
            guard !canPlayVideos, token > 0 else { return }
            onHandoff()
            onThrowFinished()
        }
    }

    private var activityPill: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.aiActive).frame(width: 7, height: 7)
            Text("Reading your photo…")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.opacity)
    }

    /// NEBEL AM RAND statt harter Kante.
    ///
    /// GEMESSEN am Clip (360×360): die Figur belegt x 17–83 %, die geworfenen
    /// Fotos fliegen bis x 0–99 % und bis an die Unterkante. Sie verlassen das
    /// Bild also genau dort, wo die Figur NICHT ist. Ohne Maske sieht man sie
    /// an der Videokante abrupt enden — man sieht, dass da ein Video aufhört.
    ///
    /// Die Maske blendet außen weich aus: seitlich über 12 %, unten nur über
    /// 5,5 %. Seitlich ist viel Luft (die Figur endet bei 17 % bzw. 83 %), unten
    /// dagegen stehen die Füße bei 95 % — eine tiefere Blende hätte sie
    /// angefressen, und abgeschnittene Füße lesen sich als Fehler, nicht als Nebel.
    /// Damit lösen sich die Fotos im Nebel auf, statt an einer Linie zu stoppen,
    /// und die Polaroids darunter kommen aus demselben Nebel wieder heraus.
    /// Oben wird nicht ausgeblendet — dort fliegt nichts hinaus.
    static var fogMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.88),
                .init(color: .clear, location: 1.00),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .mask(
            LinearGradient(
                stops: [
                    // Auch OBEN ausblenden. Vorher war die Oberkante des
                    // quadratischen Videokastens ein harter Schnitt — solange
                    // sein Creme exakt zur Seite passte, fiel das nicht auf,
                    // aber jede Abweichung wurde dort als Linie sichtbar.
                    // 3 % sind gut vier Punkte und liegen ueber dem Kopf: die
                    // Figur fuellt 92 % der Bildhoehe.
                    .init(color: .clear, location: 0.00),
                    .init(color: .black, location: 0.03),
                    .init(color: .black, location: 0.945),
                    .init(color: .clear, location: 1.00),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// ALLE CLIPS SIND HEVC MIT ALPHA (.mov), NICHT MEHR H.264 (.mp4).
    ///
    /// Vorher waren die Videos auf deckendes Creme aufgezogen. Solange die
    /// Oberflaeche dieselbe Creme war, fiel das nicht auf; sobald hinter der
    /// Figur Farbe liegt, stand ihr Videokasten als helles Rechteck im Bild.
    /// Dagegen half nur ein cremefarbenes Polster hinter ihr — ein Pflaster,
    /// kein Freisteller.
    ///
    /// Jetzt tragen die Clips einen echten Alphakanal. Der Schluessel war
    /// eindeutig, weil der Hintergrund in jedem Bild exakt (246,242,237) ist;
    /// die Arbeit steckte in zwei Stellen: der Bauch der Figur ist selbst
    /// cremefarben (deshalb zaehlt als Hintergrund nur, was vom BILDRAND aus
    /// erreichbar ist), und H.264 legt um jede Kante ein Ringing, das vor
    /// dunklem Grund sonst als heller Halo stehenbleibt.
    ///
    /// WICHTIG fuer die Wiedergabe: ein `AVPlayerLayer` zeigt das Alpha nur,
    /// wenn man ihn ausdruecklich auf 32BGRA stellt — siehe
    /// `pixelBufferAttributes` im Player. Ohne das laeuft der Film, aber
    /// deckend schwarz hinterlegt.
    private static let endung = "mov"

    static var throwURL: URL? {
        Bundle.main.url(forResource: "mascot_throw", withExtension: endung)
    }

    /// Die Idle-Loops. Alle starten und enden in der Pose von
    /// `LOOPstartend.png`, erzeugt mit WAN 3.0 Prime aus genau diesem Bild.
    ///
    /// `mascot_idle_tab` ist der neue, eigene Loop für den Director: die Augen
    /// führen — eins schwenkt links, das andere rechts, unabhängig, dann
    /// treffen sich beide beim Betrachter. Das ist die charakteristischste
    /// Eigenschaft eines Chamäleons und im Zuhause-Loop kommt sie nicht vor.
    static var idleURLs: [URL] {
        ["mascot_idle_tab", "mascot_idle1", "mascot_idle2", "mascot_idle3"].compactMap {
            Bundle.main.url(forResource: $0, withExtension: endung)
        }
    }

    /// DREI EIGENE POSEN neben dem gelesenen Foto — in EINER Datei.
    ///
    /// Warum eine Datei und nicht drei: die Idle-Rotation blendet 0,30 s VOR
    /// dem Ende des laufenden Clips auf den naechsten. Waehrend dieser Blende
    /// bewegt sich der alte Clip noch und der neue laeuft schon — man sieht
    /// zwei Figuren in verschiedenen Haltungen uebereinander. GENAU DAS war
    /// der sichtbare „Videowechsel". Eine Blende kann das nicht heilen; sie
    /// ist die Ursache.
    ///
    /// Deshalb: `mascot_read_loop.mp4` enthaelt alle drei Posen hintereinander
    /// und laeuft als EIN `AVPlayerLooper` — dieselbe Mechanik, die den
    /// Pruef-Loop schon lueckenlos haelt. Keine Blende, kein Wechsel, kein
    /// Neustart.
    ///
    /// Die Naehte sind VERSCHWEISST: jede Pose blendet ueber fuenf Bilder auf
    /// EIN gemeinsames Ankerbild und wieder heraus. Dadurch sind die Bilder an
    /// jedem Uebergang identisch. GEMESSEN, mittlere Abweichung von 255:
    /// Pose 1→2: 0,78 · Pose 2→3: 0,81 · Ende→Anfang: 0,64. Das ist der Rest
    /// der Videokompression, nicht mehr die Figur.
    static var readLoopURL: URL? {
        Bundle.main.url(forResource: "mascot_read_loop", withExtension: endung)
    }


    /// Der Prüf-Loop: er hält eine Lupe, ein Auge fixiert durch das Glas,
    /// das andere wandert weiter über die Karte. Läuft, solange er liest, und
    /// geht danach von selbst in die Ruhe zurück.
    ///
    /// GEMESSEN: Schnittsprung erstes zu letztem Bild 4,0 von 255 — praktisch
    /// unsichtbar. Der Idle-Loop kam roh auf 24,6 und musste auf sein
    /// sauberstes Teilstück beschnitten werden (11,8).
    static var scanURL: URL? {
        Bundle.main.url(forResource: "mascot_scan", withExtension: endung)
    }
}

// MARK: - Player

private struct MascotPlayer: UIViewRepresentable {
    let throwURL: URL
    let idleURLs: [URL]
    /// Eine einzige Datei in Endlosschleife statt der Rotation.
    let idleLoopURL: URL?
    /// Der Pruef-Loop. Optional: fehlt der Clip, bleibt es beim Leerlauf.
    let scanURL: URL?
    /// true, solange der Director das Foto liest.
    let isScanning: Bool
    let throwToken: Int
    /// true, solange ein Begrüßungswurf noch kommt. Dann läuft VORHER kein
    /// Idle-Loop, sondern es steht das erste Bild des Wurfs — dieselbe Pose wie
    /// `LOOPstartend.png`. Ohne das wirkt es, als sei die Animation noch gar
    /// nicht gestartet, während unten schon etwas passiert.
    let expectsThrow: Bool
    let isActive: Bool
    let onHandoff: () -> Void
    let onThrowFinished: () -> Void
    /// Feuert einmal, sobald wirklich ein Videobild auf dem Schirm sein kann.
    let onReady: () -> Void

    func makeUIView(context: Context) -> MascotPlayerUIView {
        let v = MascotPlayerUIView()
        v.configure(throwURL: throwURL, idleURLs: idleURLs,
                    idleLoopURL: idleLoopURL, scanURL: scanURL,
                    onHandoff: onHandoff, onThrowFinished: onThrowFinished,
                    onReady: onReady)
        // Reihenfolge: Pruefen ZUERST. `throwToken` ist nach dem
        // Begruessungswurf dauerhaft > 0, und eine frisch aufgebaute Ansicht
        // hat `lastThrowToken == 0` — der Wurf-Zweig hat den Pruef-Zweig
        // deshalb bei JEDEM Neuaufbau geschlagen. Er war toter Code.
        if isScanning {
            v.startScanning()
        } else if throwToken > 0 {
            v.startThrow(token: throwToken)
        } else if expectsThrow {
            v.holdFirstFrame()
        } else {
            v.startIdle()
        }
        return v
    }

    func updateUIView(_ uiView: MascotPlayerUIView, context: Context) {
        // Der Ruhe-Satz kann sich unter der laufenden Ansicht aendern: dieselbe
        // Buehne zeigt beim Lesen den einen und danach neben dem Foto den
        // anderen. `configure` laeuft nur beim Aufbau — ohne diese Zeile
        // spielte sie danach weiter die alten Clips.
        uiView.setIdleLoop(idleLoopURL)
        uiView.setActive(isActive)
        uiView.startThrow(token: throwToken)
        // Nach dem Wurf, sonst ueberschreibt der Wurf den Pruef-Loop sofort.
        uiView.setScanning(isScanning)
    }

    static func dismantleUIView(_ uiView: MascotPlayerUIView, coordinator: ()) {
        uiView.teardown()
    }
}

/// Zwei Ebenen, zwischen denen überblendet wird — siehe Dateikopf.
final class MascotPlayerUIView: UIView {

    private let layerA = AVPlayerLayer()
    private let layerB = AVPlayerLayer()
    // AVQueuePlayer statt AVPlayer: erbt davon, aendert am uebrigen Verhalten
    // nichts — aber nur an einen QueuePlayer laesst sich ein AVPlayerLooper
    // haengen, und der ist die einzige Art, einen Clip WIRKLICH lueckenlos zu
    // wiederholen.
    private let playerA = AVQueuePlayer()
    private let playerB = AVQueuePlayer()
    /// Beide Spieler duerfen NICHT auf Puffer warten.
    ///
    /// GEMESSEN in der Bildschirmaufnahme: beim Wiederholen des Loops fehlte
    /// die Figur ein bis zwei Bilder lang vollstaendig — der Sprung von Bild
    /// zu Bild sprang auf 49,5 von 255, waehrend er sonst bei 0,8 liegt. Das
    /// ist kein Posenfehler, sondern eine leere Ebene: der Spieler haelt beim
    /// Item-Wechsel an, um zu puffern, und die Ebene hat nichts zu zeigen.
    ///
    /// Die Clips liegen im Bundle und sind Sekunden lang; es gibt nichts zu
    /// puffern. Erster Versuch, bevor die Buehne umgebaut wird.
    private func nichtAufPufferWarten() {
        playerA.automaticallyWaitsToMinimizeStalling = false
        playerB.automaticallyWaitsToMinimizeStalling = false
    }
    /// Haelt den Pruef-Clip lueckenlos in der Schleife, solange gelesen wird.
    private var scanLooper: AVPlayerLooper?
    /// true = A ist sichtbar, B ist die Reserve.
    private var frontIsA = true

    private var throwURL: URL?
    private var idleURLs: [URL] = []
    private var idleLoopURL: URL?
    private var idleIndex = 0
    /// Der Pruef-Loop (Lupe). Laeuft, solange der Director das Foto liest.
    private var scanURL: URL?
    /// Verhindert, dass ein Zustandswechsel doppelt ueberblendet — SwiftUI
    /// ruft `updateUIView` bei jeder Neuzeichnung auf, nicht nur bei Aenderung.
    private var scanning = false
    private var onHandoff: (() -> Void)?
    private var onThrowFinished: (() -> Void)?

    private var observers: [(AVPlayer, Any)] = []
    /// Meldet EINMAL, sobald eine der Ebenen wirklich etwas anzeigen kann.
    private var readyObservers: [NSKeyValueObservation] = []
    private var onReady: (() -> Void)?
    private var reportedReady = false
    private var endObserver: NSObjectProtocol?
    /// Zuletzt ausgeführter Wurf. Ein neuer Zählerstand löst einen neuen aus,
    /// derselbe nicht — sonst startete `updateUIView` ihn dauernd neu.
    private var lastThrowToken = 0
    /// Nur für Tests: welcher Wurf zuletzt gestartet wurde.
    var lastThrowTokenForTesting: Int { lastThrowToken }
    private var paused = false
    /// true, solange nur das Standbild des Wurfs steht und noch nichts läuft.
    private var holding = false
    private var fading = false

    // MARK: Nie stehenbleiben

    /// Was gerade laufen SOLL. Ohne das kann nach einer Unterbrechung niemand
    /// entscheiden, was wieder anzuwerfen ist.
    private var currentSource: URL?
    /// true, wenn `currentSource` eine Endlosschleife ist (Looper statt Clip).
    private var currentIsLoop = false
    /// Anmeldungen beim App-Lebenszyklus. Muessen beim Abbau wieder weg.
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// Prueft alle zwei Sekunden, ob die Zeit noch laeuft.
    private var watchdog: Timer?
    private var lastSeenTime: Double = -1

    private var front: AVPlayer { frontIsA ? playerA : playerB }
    private var back: AVPlayer { frontIsA ? playerB : playerA }
    private var frontLayer: AVPlayerLayer { frontIsA ? layerA : layerB }
    private var backLayer: AVPlayerLayer { frontIsA ? layerB : layerA }

    // MARK: Aufbau

    /// Schaltet im Betrieb zwischen Rotation und Endlosschleife um.
    ///
    /// Dieselbe Buehne zeigt beim Lesen die Lupe und danach neben dem Foto den
    /// Ruhe-Loop. `configure` laeuft nur beim Aufbau — ohne diese Zeile bliebe
    /// sie danach in der Rotation vom Startbildschirm haengen.
    func setIdleLoop(_ url: URL?) {
        guard url != idleLoopURL else { return }
        let vorher = idleLoopURL
        idleLoopURL = url
        // Nicht waehrend des Wurfs oder des Lesens umschalten: die haben eine
        // eigene Erzaehlung, die nicht mittendrin abreissen darf.
        guard !scanning, !holding else { return }

        // EIN TAUSCH IM LAUFENDEN BETRIEB WIRD GEBLENDET, NICHT GESCHNITTEN.
        //
        // `startLoop` leert die Warteschlange und setzt sofort neu an. Solange
        // es nur EINE Schleife gab, war das richtig: der Wurf endet in der
        // Startpose und die Schleife beginnt in derselben.
        //
        // Seit der Director-Tab die Schleife nach Buehne wechselt, faellt der
        // Schnitt aber an einer BELIEBIGEN Stelle. GEMESSEN, mittlere
        // Abweichung von 255 zwischen einem Bild aus `mascot_read_loop` und
        // der Anfangspose von `mascot_scan`: kleinster Abstand 5,9, Mittel
        // 26,3, groesster 42,6. Eine saubere Naht liegt bei 0,8 bis 3,6 —
        // das war also bis zu zehnmal der Sprung, den man sonst als Fehler
        // sieht.
        //
        // Auf die naechste Ankerstelle zu warten hilft nicht: `read_loop`
        // durchlaeuft sie nur alle rund 6,3 Sekunden, so lange darf eine
        // Antwort auf einen Fingertipp nicht brauchen.
        if let url, vorher != nil, currentIsLoop, !fading {
            crossfadeToLoop(url, duration: 0.22)
            return
        }
        startIdle()
    }

    /// Dieselbe Blende wie zwischen den Idle-Clips, aber das Ziel ist eine
    /// Endlosschleife.
    ///
    /// `crossfade(to:)` kann das nicht: es spielt einmal ab. Und `startLoop`
    /// kann es nicht ohne Schnitt. Deshalb hier beides zusammen — Looper auf
    /// der Reserve-Ebene aufbauen, dann die alte darueber ausblenden.
    ///
    /// Der ALTE Clip laeuft waehrend der Blende weiter. Ihn vorher anzuhalten
    /// waere ein sichtbares Einfrieren; genau das steht schon im
    /// Abschlussblock von `crossfade(to:)`.
    private func crossfadeToLoop(_ url: URL, duration: Double) {
        guard let ziel = back as? AVQueuePlayer else { startLoop(url); return }
        fading = true
        let gehend = front
        let zielEbene = backLayer
        let gehendeEbene = frontLayer

        clearObservers()
        currentSource = url
        currentIsLoop = true

        ziel.removeAllItems()
        ziel.replaceCurrentItem(with: AVPlayerItem(url: url))
        ziel.seek(to: .zero)
        if !paused { ziel.play() }

        // NUR die obere Ebene ausblenden, die untere steht dabei schon voll da
        // — dieselbe Begruendung wie in `crossfade(to:)`.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zielEbene.opacity = 1
        zielEbene.zPosition = 0
        gehendeEbene.zPosition = 1
        CATransaction.commit()

        // Buchfuehrung sofort umlegen, nicht erst im Abschlussblock.
        frontIsA.toggle()

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            gehend.pause()
            (gehend as? AVQueuePlayer)?.removeAllItems()
            self.fading = false
        }
        gehendeEbene.opacity = 0
        CATransaction.commit()

        // Ohne das liefe der neue Clip GENAU EINMAL und bliebe stehen: die
        // Blende hat die Beobachter des alten Durchgangs geloescht.
        planeUebergabe(url, von: ziel)
    }

    func configure(throwURL: URL, idleURLs: [URL], idleLoopURL: URL? = nil,
                   scanURL: URL? = nil,
                   onHandoff: @escaping () -> Void, onThrowFinished: @escaping () -> Void,
                   onReady: @escaping () -> Void) {
        self.throwURL = throwURL
        self.idleURLs = idleURLs
        self.idleLoopURL = idleLoopURL
        self.scanURL = scanURL
        self.onHandoff = onHandoff
        self.onThrowFinished = onThrowFinished
        self.onReady = onReady
        self.idleIndex = idleURLs.indices.randomElement() ?? 0

        backgroundColor = .clear
        isUserInteractionEnabled = false
        nichtAufPufferWarten()
        beobachteLebenszyklus()
        starteWachhund()

        for (l, p) in [(layerA, playerA), (layerB, playerB)] {
            p.isMuted = true
            p.actionAtItemEnd = .pause
            l.player = p
            l.videoGravity = .resizeAspect
            l.isOpaque = false
            l.backgroundColor = UIColor.clear.cgColor
            // OHNE DIESE ZEILE IST DAS ALPHA WEG.
            // Ein `AVPlayerLayer` verlangt standardmaessig einen deckenden
            // Puffer und wirft den Alphakanal der HEVC-Datei fort — der Film
            // laeuft dann korrekt, aber auf Schwarz statt durchsichtig.
            l.pixelBufferAttributes = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            layer.addSublayer(l)
        }
        layerA.opacity = 1
        layerB.opacity = 0

        // Ein AVPlayerLayer zeigt nichts, bis er wirklich ein Bild hat, und er
        // blendet auch nicht ein — er ist schlagartig da. GEMESSEN beim
        // Kaltstart: die übrige Oberfläche stand ab 2,62 s, die Figur kam erst
        // bei 2,90 s. Diese 220 ms sind das Popping. Wer hier zuhört, kann
        // solange das Standbild stehen lassen.
        for l in [layerA, layerB] {
            readyObservers.append(
                l.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                    guard let self, !self.reportedReady, layer.isReadyForDisplay else { return }
                    self.reportedReady = true
                    DispatchQueue.main.async { self.onReady?() }
                }
            )
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let item = note.object as? AVPlayerItem,
                  item === self.front.currentItem else { return }
            // Beim Pruefen NICHT in den Leerlauf zurueckfallen, sondern den
            // Pruef-Clip neu ansetzen.
            //
            // Vorher stand hier nur ein `return`. Das hat den Leerlauf zwar
            // verhindert, aber auch das Sicherheitsnetz: wurde die geplante
            // Wiederholung verpasst, blieb das Video am letzten Bild stehen —
            // die Figur fror mitten im Lesen ein.
            // Beim Pruefen laeuft der AVPlayerLooper — er wiederholt selbst
            // und feuert dieses Ereignis gar nicht erst als Ende.
            if self.scanning { return }
            // Sicherheitsnetz: wurde die geplante Blende verpasst, trotzdem weiter.
            self.crossfadeToNextIdle(duration: MascotStage.idleFade)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layerA.frame = bounds; layerB.frame = bounds
        CATransaction.commit()
    }

    // MARK: Ablauf

    func startThrow(token: Int) {
        guard token > 0, token != lastThrowToken, let url = throwURL else { return }
        lastThrowToken = token
        clearObservers()

        // Stand vorher nur das erste Bild? Dann ist nichts zu blenden — der Clip
        // läuft einfach los. Nur aus einem LAUFENDEN Idle heraus wird geblendet,
        // weil der an beliebiger Stelle steht und der Wurf in der Startpose
        // beginnt; ohne Blende sähe man den Sprung auf eine andere Haltung.
        if holding {
            holding = false
            let p = front
            p.seek(to: .zero)
            p.play()
            addThrowBoundaries(on: p)
            return
        }
        crossfade(to: url, duration: MascotStage.throwEnter, onPlayer: { [weak self] p in
            self?.addThrowBoundaries(on: p)
        })
    }

    /// Zeigt das erste Bild des Wurfs und hält es an. Optisch identisch mit dem
    /// Standbild, aber schon der richtige Clip — der Start des Wurfs ist dadurch
    /// kein Wechsel, sondern nur ein Loslaufen.
    func holdFirstFrame() {
        guard let url = throwURL else { return }
        front.replaceCurrentItem(with: AVPlayerItem(url: url))
        front.seek(to: .zero)
        front.pause()
        holding = true
    }

    /// Die zwei Zeitpunkte im Wurf: Übergabe an die Karten, und der Ausstieg,
    /// sobald die Figur ausgependelt hat.
    private func addThrowBoundaries(on p: AVPlayer) {
        addBoundary(at: MascotStage.handoffTime, on: p) { [weak self] in
            self?.onHandoff?()
        }
        addBoundary(at: MascotStage.fadeStart, on: p) { [weak self] in
            guard let self else { return }
            self.crossfadeToNextIdle(duration: MascotStage.throwFade)
            self.onThrowFinished?()
        }
    }

    /// Startet DIREKT im Pruef-Loop, ohne Umweg ueber die Ruhe.
    ///
    /// GEMESSEN: SwiftUI baut diese Ansicht mehrfach neu auf, waehrend der
    /// Director liest. Jeder Neuaufbau lief `makeUIView` → `startIdle()` und
    /// erst danach `setScanning(true)` — der Uebergang zur Lupe brauchte aber
    /// eine Ueberblendung und wurde vom naechsten Neuaufbau abgeschnitten.
    /// Ergebnis: sichtbar war immer nur der frisch gestartete Leerlauf.
    func startScanning() {
        guard let scanURL else { startIdle(); return }
        scanning = true
        // Eine abgeschnittene Blende darf nicht dauerhaft sperren: `fading`
        // wird sonst nie zurueckgesetzt und blockiert jeden Idle-Wechsel.
        fading = false
        clearObservers()
        // Die eigene Ebene ausdruecklich nach vorn holen. Ohne das haengt es
        // davon ab, welche Blende zufaellig zuletzt lief.
        let visible = frontLayer, hidden = backLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        visible.opacity = 1
        visible.zPosition = 1
        hidden.opacity = 0
        hidden.zPosition = 0
        CATransaction.commit()
        // Lueckenlose Schleife statt Selbstueberblendung.
        //
        // Vorher wurde der Clip kurz vor seinem Ende auf SICH SELBST
        // ueberblendet. Waehrend dieser Blende liefen Anfang und Ende
        // gleichzeitig — sichtbar als Doppelbild und als Ruckler. Ein
        // AVPlayerLooper haengt das Item stattdessen nahtlos an sich selbst,
        // ohne Neustart und ohne Luecke.
        scanLooper = nil
        currentSource = scanURL
        // Derselbe Weg wie jede andere Schleife — siehe `startLoop`. Vorher
        // stand hier ein eigener `AVPlayerLooper` mit demselben Blinzeln.
        startLoop(scanURL)
    }

    func startIdle() {
        // Eine Datei, ein Looper, KEINE Blende — siehe `readLoopURL`.
        if let idleLoopURL {
            startLoop(idleLoopURL)
            return
        }
        guard !idleURLs.isEmpty else { return }
        play(idleURLs[idleIndex], on: front)
        scheduleIdleHandover(on: front)
    }

    /// Haengt eine Datei lueckenlos an sich selbst — UEBER BEIDE EBENEN.
    ///
    /// HIER STAND EIN `AVPlayerLooper`, UND DER HAT GEBLINZELT.
    ///
    /// Gemessen in der Bildschirmaufnahme, Ausschnitt um die Figur, 60 Bilder
    /// je Sekunde: bei JEDER Wiederholung fehlte die Figur ein bis zwei Bilder
    /// lang vollstaendig. Der Sprung von Bild zu Bild ging auf 49,5 von 255
    /// hoch, wo er sonst bei 0,8 liegt. Kein Posenfehler — eine leere Ebene.
    /// Der Looper tauscht das Item, und die `AVPlayerLayer` hat in diesem
    /// Moment nichts anzuzeigen.
    ///
    /// `automaticallyWaitsToMinimizeStalling = false` half nicht: nachgemessen
    /// blieben die Aussetzer bei 19,43 s, 29,45 s, 34,48 s — weiter im Takt
    /// der Cliplaenge. Es ist kein Pufferproblem, es ist der Item-Wechsel.
    ///
    /// Deshalb wiederholt sich der Clip jetzt ueber die ZWEITE Ebene: eine
    /// halbe Sekunde vor Schluss wird er dort neu aufgelegt und mit `preroll`
    /// bis zum ersten dekodierten Bild vorgespult. Am Ende des Durchgangs
    /// werden nur noch die Deckkraefte getauscht — ohne Animation, in einem
    /// Bild. Die Ebene, die sichtbar wird, HAT bereits ein Bild.
    ///
    /// Das geht nur, weil erstes und letztes Bild praktisch gleich sind.
    /// GEMESSEN nach dem Ping-Pong-Umbau: `mascot_idle_tab` 0,82 ·
    /// `mascot_idle3` 1,15 · `mascot_scan` 0,81 · `mascot_read_loop` 3,57.
    /// Eine Blende braucht es dafuer nicht — sie waere sogar schlechter,
    /// weil dann zwei Figuren uebereinanderlaegen.
    func startLoop(_ url: URL) {
        currentSource = url
        currentIsLoop = true
        fading = false
        clearObservers()
        scanLooper?.disableLooping()
        scanLooper = nil
        let sichtbar = frontLayer, versteckt = backLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sichtbar.opacity = 1; sichtbar.zPosition = 1
        versteckt.opacity = 0; versteckt.zPosition = 0
        CATransaction.commit()
        starteDurchgang(url, auf: front)
    }

    private func starteDurchgang(_ url: URL, auf spieler: AVPlayer) {
        (spieler as? AVQueuePlayer)?.removeAllItems()
        spieler.replaceCurrentItem(with: AVPlayerItem(url: url))
        spieler.seek(to: .zero)
        if !paused { spieler.play() }
        ruesteReserve(url)
        planeUebergabe(url, von: spieler)
    }

    /// Legt denselben Clip auf der Reserve-Ebene bereit und spult ihn bis zum
    /// ersten dekodierten Bild vor.
    ///
    /// SOFORT, nicht kurz vor Schluss. Der erste Anlauf ruestete die Reserve
    /// ueber einen zweiten Grenzzeit-Beobachter eine halbe Sekunde vor dem
    /// Ende — und der wurde manchmal verpasst. Dann lag beim Tausch noch der
    /// VORHERIGE Clip auf der Reserve, und die Figur sprang mitten im
    /// Trendmodus fuer fuenf Bilder in die Ruhehaltung, ohne Lupe. In der
    /// Aufnahme genau so gesehen: ein Sprung von 26,0 bei 13,78 s.
    ///
    /// Bereitgelegt wird jetzt am Anfang des Durchgangs. Die Reserve steht
    /// dann Sekunden lang fertig da, und der Tausch haengt an nichts mehr.
    private func ruesteReserve(_ url: URL) {
        let reserve = back
        (reserve as? AVQueuePlayer)?.removeAllItems()
        reserve.replaceCurrentItem(with: AVPlayerItem(url: url))
        reserve.pause()
        reserve.seek(to: .zero) { _ in Self.spuleVor(reserve, versuche: 3) }
    }

    /// `preroll` NUR bei fertigem Item.
    ///
    /// DAS HAT DIE APP ABSTUERZEN LASSEN. `AVPlayer.preroll(atRate:)` wirft
    /// eine Objective-C-Ausnahme, wenn der Spieler noch nicht `readyToPlay`
    /// ist — und seit die Reserve gleich zu Beginn des Durchgangs bestueckt
    /// wird, ist das Item beim Ende des `seek` regelmaessig noch nicht so weit.
    /// Im Absturzbericht: `EXC_CRASH SIGABRT`, `-[AVPlayer
    /// prerollAtRate:completionHandler:]` aus `ruesteReserve`. Eine
    /// ObjC-Ausnahme laesst sich aus Swift nicht fangen, also darf sie gar
    /// nicht erst entstehen.
    ///
    /// Ist noch nichts bereit, wird es spaeter erneut versucht. Klappt es gar
    /// nicht, faellt nur das Vorspulen aus — die Ebene hat dann bis zum
    /// Tausch trotzdem Sekunden Zeit, ihr erstes Bild zu dekodieren.
    private static func spuleVor(_ spieler: AVPlayer, versuche: Int) {
        guard versuche > 0 else { return }
        guard spieler.status == .readyToPlay,
              spieler.currentItem?.status == .readyToPlay else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                spuleVor(spieler, versuche: versuche - 1)
            }
            return
        }
        spieler.preroll(atRate: 1) { _ in }
    }

    private func planeUebergabe(_ url: URL, von spieler: AVPlayer) {
        guard let item = spieler.currentItem else { return }
        // Die Dauer des ASSETS, nicht des Items: die des Items ist direkt nach
        // dem Anlegen noch unbestimmt.
        let ende = CMTimeGetSeconds(item.asset.duration)
        guard ende.isFinite, ende > 0.2 else { return }

        // Zwei Hundertstel vor Schluss — ein Bild frueher ist unsichtbar, ein
        // Bild zu spaet zeigt das Standbild am Ende.
        addBoundary(at: ende - 0.02, on: spieler) { [weak self] in
            guard let self, self.currentIsLoop, self.currentSource == url else { return }
            self.uebergib(url, von: spieler)
        }
    }

    private func uebergib(_ url: URL, von alt: AVPlayer) {
        let neu = back

        // NIE auf eine Ebene tauschen, die etwas anderes zeigt. Genau daran
        // ist der erste Anlauf gescheitert; lieber ein harter Neustart
        // desselben Clips — dessen Naht ist gemessen unter 1,2.
        guard (neu.currentItem?.asset as? AVURLAsset)?.url == url else {
            alt.seek(to: .zero)
            if !paused { alt.play() }
            clearObservers()
            ruesteReserve(url)
            planeUebergabe(url, von: alt)
            return
        }

        let neueEbene = backLayer, alteEbene = frontLayer
        if !paused { neu.play() }

        // OHNE Animation. Erstes und letztes Bild sind gleich; eine Blende
        // waere hier nur ein weicher Doppelgaenger.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        neueEbene.opacity = 1; neueEbene.zPosition = 1
        alteEbene.opacity = 0; alteEbene.zPosition = 0
        CATransaction.commit()

        frontIsA.toggle()
        alt.pause()
        clearObservers()
        // Die eben frei gewordene Ebene wird die naechste Reserve.
        ruesteReserve(url)
        planeUebergabe(url, von: neu)
    }

    /// Schaltet zwischen Pruef-Loop und Ruhe um.
    ///
    /// Der Pruef-Clip laeuft als EINZELNER Loop weiter, nicht ueber die
    /// Idle-Rotation: er zeigt genau eine Handlung — die Lupe ueber der Karte —
    /// und ein Wechsel auf einen anderen Clip mittendrin waere ein Bruch in der
    /// Erzaehlung. GEMESSEN springt er beim Schnitt nur um 4,0 von 255, das
    /// haelt eine harte Wiederholung problemlos aus.
    func setScanning(_ on: Bool) {
        guard let scanURL, scanning != on else { return }
        scanning = on
        clearObservers()
        if on {
            // HARTER Schnitt statt Ueberblendung. GEMESSEN: mit `crossfade`
            // blieb `fading` auf true stehen und der Pruef-Clip wurde nie
            // sichtbar — die Ansicht wird waehrend des Lesens mehrfach neu
            // aufgebaut und schnitt die laufende Blende jedes Mal ab.
            // Beide Clips zeigen dieselbe Figur in fast derselben Haltung,
            // der Sprung faellt praktisch nicht auf.
            _ = scanURL
            startScanning()
        } else {
            // Looper zuerst loesen: er wuerde sonst weiter Items nachlegen und
            // gegen den Idle-Clip arbeiten.
            scanLooper?.disableLooping()
            scanLooper = nil
            // Zurueck in die Ruhe — ueber dieselbe Ueberblendung, damit die
            // Figur nicht hart von der Lupe in den Leerlauf springt.
            crossfadeToNextIdle(duration: MascotStage.idleFade)
        }
    }

    /// Haengt den Pruef-Clip kurz vor seinem Ende wieder an sich selbst.
    /// Blendet auf die Reserve-Ebene, auf der der nächste Idle-Clip startet.
    private func crossfadeToNextIdle(duration: Double) {
        // Laeuft hier eine Endlosschleife, gibt es nichts zu wechseln.
        if idleLoopURL != nil { startIdle(); return }
        guard !idleURLs.isEmpty, !fading else { return }
        if idleURLs.count > 1 {
            var next = idleIndex
            while next == idleIndex { next = Int.random(in: 0..<idleURLs.count) }
            idleIndex = next
        }
        crossfade(to: idleURLs[idleIndex], duration: duration) { [weak self] in
            guard let self else { return }
            self.scheduleIdleHandover(on: self.front)
        }
    }

    /// Die gemeinsame Mechanik: neuen Clip auf der Reserve-Ebene starten und
    /// die alte darüber ausblenden. Wird für BEIDE Richtungen gebraucht — in
    /// den Wurf hinein und aus ihm heraus. Fehlte die Hinrichtung, sprang die
    /// Figur beim Wurfbeginn hart von der Idle-Pose auf den Polaroid-Stapel.
    @discardableResult
    private func crossfade(to url: URL, duration: Double,
                           onPlayer: ((AVPlayer) -> Void)? = nil,
                           completion: (() -> Void)? = nil) -> AVPlayer {
        fading = true
        let leaving = front
        let target = back
        let targetLayer = backLayer
        let leavingLayer = frontLayer

        play(url, on: target)
        onPlayer?(target)

        // NUR die obere Ebene ausblenden, die untere steht dabei schon voll da.
        // Würde man beide gleichzeitig auf 0,5 fahren, summieren sie sich nicht
        // zu 1 — es entstünde ein sichtbar ausgeblichenes Zwischenbild.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        targetLayer.opacity = 1
        targetLayer.zPosition = 0
        leavingLayer.zPosition = 1
        CATransaction.commit()

        // Buchfuehrung SOFORT umlegen, nicht erst im Completion-Block.
        //
        // GEMESSEN: vorher kippte `frontIsA` erst am Ende der Blende. Waehrend
        // sie lief, zeigte `front` also auf die Ebene, die gerade WEGgeblendet
        // wird. Ein `play(on: front)` in diesem Fenster — genau das tat der
        // Pruef-Loop — landete auf einer Ebene mit Deckkraft 0. Der Clip lief,
        // war aber unsichtbar.
        frontIsA.toggle()

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            // Erst NACH der Blende anhalten, sonst friert das Bild sichtbar ein.
            leaving.pause()
            self.fading = false
            completion?()
        }
        leavingLayer.opacity = 0
        CATransaction.commit()
        return target
    }

    /// Plant die nächste Blende so, dass sie GENAU am Clip-Ende fertig ist.
    private func scheduleIdleHandover(on player: AVPlayer) {
        guard let item = player.currentItem else { return }
        let total = CMTimeGetSeconds(item.duration)
        guard total.isFinite, total > MascotStage.idleFade + 0.2 else { return }
        addBoundary(at: total - MascotStage.idleFade, on: player) { [weak self] in
            self?.crossfadeToNextIdle(duration: MascotStage.idleFade)
        }
    }

    private func play(_ url: URL, on player: AVPlayer) {
        // Ein aktiver Looper legt selbst Items nach — ohne ihn zu loesen,
        // waere das Ergebnis ein Wettlauf zwischen beiden.
        if scanLooper != nil {
            scanLooper?.disableLooping()
            scanLooper = nil
        }
        currentSource = url
        currentIsLoop = false
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: .zero)
        if !paused { player.play() }
    }

    /// Vor jedem neuen Wurf die alten Grenzzeit-Beobachter lösen — sonst
    /// feuern die des vorherigen Durchlaufs weiter mit.
    private func clearObservers() {
        for (p, o) in observers { p.removeTimeObserver(o) }
        observers.removeAll()
    }

    private func addBoundary(at seconds: Double, on player: AVPlayer, _ action: @escaping () -> Void) {
        let t = NSValue(time: CMTime(seconds: seconds, preferredTimescale: 600))
        let o = player.addBoundaryTimeObserver(forTimes: [t], queue: .main, using: action)
        observers.append((player, o))
    }

    // MARK: Nie stehenbleiben

    /// Zurueck aus dem Hintergrund — und zwar von selbst.
    ///
    /// DAS WAR EIN ECHTER FEHLER: `isActive` wurde vom Aufrufer fest auf
    /// `true` gesetzt, es gab also NIRGENDS eine Reaktion auf den
    /// App-Lebenszyklus. iOS haelt beim Wechsel in den Hintergrund jeden
    /// `AVPlayer` an; zurueck im Vordergrund hat ihn niemand wieder gestartet.
    /// Die Figur stand danach still, bis die Ansicht zufaellig neu aufgebaut
    /// wurde. Genau so ist es gemeldet worden.
    private func beobachteLebenszyklus() {
        let mitte = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification,
                     UIApplication.willEnterForegroundNotification] {
            lifecycleObservers.append(
                mitte.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.wiederAnwerfen()
                })
        }
        // Beim Verlassen ausdruecklich anhalten: sonst laeuft die Dekodierung
        // im Hintergrund noch kurz weiter und kostet Strom ohne Bild.
        lifecycleObservers.append(
            mitte.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                              object: nil, queue: .main) { [weak self] _ in
                self?.playerA.pause(); self?.playerB.pause()
            })
    }

    /// Alle zwei Sekunden nachsehen, ob die Zeit vorangeht.
    ///
    /// Ein `AVPlayerLooper` kann nach einer Unterbrechung mit leerer
    /// Warteschlange dastehen, ein Item kann fehlschlagen, und eine
    /// abgeschnittene Blende kann `fading` haengen lassen. In allen drei Faellen
    /// steht das Bild und NICHTS meldet sich. Zwei Sekunden Pruefintervall
    /// kosten nichts und sind die einzige Stelle, die aus jedem dieser
    /// Zustaende wieder herausfuehrt.
    private func starteWachhund() {
        watchdog?.invalidate()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pruefeLauf()
        }
        // `.common`, sonst steht der Wachhund genau dann still, wenn gescrollt
        // wird — also wenn ein Hänger am ehesten auffaellt.
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    private func pruefeLauf() {
        guard !paused, !holding, window != nil else { return }
        let jetzt = front.currentTime().seconds
        let laeuft = front.timeControlStatus == .playing
        let fehler = front.currentItem?.status == .failed || front.currentItem == nil

        if fehler {
            wiederAnwerfen()
        } else if !laeuft || (jetzt.isFinite && abs(jetzt - lastSeenTime) < 0.001) {
            // Steht, obwohl es laufen soll. Erst sanft anstossen; hilft das
            // beim naechsten Durchgang nicht, wird die Quelle neu gesetzt.
            if laeuft { wiederAnwerfen() } else { front.play() }
        }
        lastSeenTime = jetzt.isFinite ? jetzt : -1
    }

    /// Setzt das, was laufen soll, neu auf — egal aus welchem Zustand heraus.
    private func wiederAnwerfen() {
        guard !paused, !holding else { return }
        fading = false
        guard let quelle = currentSource else {
            if front.timeControlStatus != .playing { front.play() }
            return
        }
        if currentIsLoop {
            // Ein Looper mit leerer Warteschlange spielt nie wieder an. Neu
            // aufsetzen ist billiger als zu pruefen, warum er leer ist.
            startLoop(quelle)
        } else if front.currentItem == nil || front.currentItem?.status == .failed {
            play(quelle, on: front)
        } else if front.timeControlStatus != .playing {
            front.play()
        }
    }

    // MARK: Lebenszyklus

    func setActive(_ active: Bool) {
        paused = !active
        if active {
            if front.timeControlStatus != .playing { front.play() }
        } else {
            playerA.pause(); playerB.pause()
        }
    }

    func teardown() {
        watchdog?.invalidate()
        watchdog = nil
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
        clearObservers()
        readyObservers.forEach { $0.invalidate() }
        readyObservers.removeAll()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        playerA.pause(); playerB.pause()
        layerA.player = nil; layerB.player = nil
    }

    deinit { teardown() }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            MascotStage(act: .throwing, height: 250)
            ForEach(0..<6) { i in
                Text("Zeile \(i)").frame(maxWidth: .infinity, alignment: .leading).padding()
            }
        }
    }
    .background(Theme.background)
}

// MARK: - Warum hier KEIN Nebel mehr liegt

// Hier stand `MascotMist`: zwei Cremeschwaden, die 9,5 s hin und 9,5 s zurueck
// ueber die Figur zogen und dabei ihre Deckkraft zwischen 0,30 und 0,75
// aenderten. Gedacht war das als Atmen der Flaeche.
//
// Auf einer gleichmaessigen Cremeflaeche ist es aber genau das, was gemeldet
// wurde: der Hintergrund wird dunkler und wieder heller. Ein wandernder
// Schleier faellt immer auf; eine ruhige Blende sieht man nie. Das Einblenden
// der Kastenkanten uebernimmt deshalb allein `fogMask` — die laeuft jetzt an
// allen vier Seiten aus und bewegt sich nicht.

// MARK: - Ihre Umgebung

/// Blätter links und rechts, zwischen denen die Figur steht.
///
/// Sie soll nicht auf einer leeren Fläche stehen, sondern irgendwo sein. Ein
/// Chamäleon gehört ins Blattwerk, also wächst von beiden Rändern welches
/// herein — flach, mit derselben Navy-Kontur wie die Figur, in ihren eigenen
/// Farben: das Grün ihrer Augen und das Hellblau ihres Kamms. Keine neue
/// Farbe, keine Fotografie, nichts zum Anklicken.
///
/// Über den Zweigen geht Wind: meistens kaum spürbar, ab und zu eine kräftige
/// Bö, die die Blätter deutlich durchbiegt und wieder abflaut. Jedes Blatt hat
/// dabei seinen eigenen Takt, sodass sich nie zwei gleichzeitig bewegen.
///
/// Der Wind wird als Funktion der Uhrzeit gerechnet und über eine
/// `TimelineView` Bild für Bild ausgewertet — nicht als Animation zwischen
/// zwei Zuständen. Nur so lässt sich die Stärke fortlaufend ändern; eine
/// `repeatForever`-Animation hat eine feste Amplitude und kann nicht auffrischen.
///
/// WARUM NUR AN DEN RÄNDERN: die Clips der Figur sind auf deckendes Creme
/// aufgezogen. In der Mitte wäre alles dahinter verdeckt; ein Zweig, der
/// hinter ihr durchliefe, würde am Rand des Kastens abbrechen. Die Blätter
/// bleiben deshalb außerhalb.
private struct MascotHabitat: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ein Blatt.
    ///
    /// Alle Maße beziehen sich auf den freien SEITENSTREIFEN, nicht auf die
    /// ganze Bühne: der Clip der Figur ist quadratisch und sitzt in der Mitte,
    /// links und rechts bleibt je `(Breite − Höhe) / 2` übrig. Rechnet man mit
    /// der vollen Breite, landen die Blätter mitten im Bild und schweben dort
    /// wie abgerissene Striche — genau so sah der erste Versuch aus.
    private struct Sprig {
        /// Vielfaches der Streifenbreite.
        let length: CGFloat
        /// Anteil der Bühnenhöhe.
        let thickness: CGFloat
        /// Wie weit der Blattansatz VOR dem Bildrand liegt (Punkte). Negativ =
        /// außerhalb, damit das Blatt hereinwächst statt frei zu liegen.
        let base: CGFloat
        let angle: Double
        let color: Color
        /// Höhe der Blattmitte, Anteil der Bühnenhöhe.
        let y: CGFloat
        /// Dauer einer vollen Schwingung in Sekunden.
        let beat: Double
        let onLeft: Bool

        /// Kreisfrequenz aus der Taktdauer.
        var speed: Double { 2 * .pi / beat }
    }

    /// Ausschlag bei Windstille und zusätzlicher Ausschlag bei voller Bö.
    private static let calmSwing: Double = 1.6
    private static let gustSwing: Double = 7.5

    /// Windstärke zur Zeit `t`: 0 = fast still, 1 = kräftige Bö.
    ///
    /// Die Grundbrise schwankt langsam. Die Bö entsteht aus derselben
    /// Sinuswelle, nur hoch potenziert — dadurch wird aus der weichen Welle
    /// ein schmaler Impuls, der selten kommt und schnell wieder abfällt.
    private static func wind(at t: TimeInterval) -> Double {
        let breeze = 0.26 + 0.20 * sin(t * 0.13)
        let gust = pow(max(0, sin(t * 0.155 + 1.1)), 6) * 0.95
        return breeze + gust
    }

    /// Alle Blätter einer Seite teilen sich denselben Ansatzpunkt knapp
    /// außerhalb des Bildrands und fächern von dort auf. Mit verstreuten
    /// Ansätzen sah es aus wie hingeworfene Striche statt wie ein Zweig.
    private static let sprigs: [Sprig] = [
        Sprig(length: 1.15, thickness: 0.24, base: -20, angle: -44,
              color: Theme.aiActive, y: 0.72, beat: 4.6, onLeft: true),
        Sprig(length: 0.95, thickness: 0.20, base: -20, angle: -11,
              color: Theme.aiActive, y: 0.72, beat: 5.9, onLeft: true),
        Sprig(length: 0.72, thickness: 0.17, base: -20, angle: 21,
              color: Theme.accentLight, y: 0.72, beat: 5.2, onLeft: true),

        Sprig(length: 1.10, thickness: 0.23, base: -20, angle: 42,
              color: Theme.aiActive, y: 0.70, beat: 5.4, onLeft: false),
        Sprig(length: 0.90, thickness: 0.19, base: -20, angle: 9,
              color: Theme.aiActive, y: 0.70, beat: 6.4, onLeft: false),
        Sprig(length: 0.68, thickness: 0.16, base: -20, angle: -23,
              color: Theme.accentLight, y: 0.70, beat: 4.9, onLeft: false)
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Der freie Streifen neben dem quadratischen Clip.
            let side = max((w - h) / 2, 24)

            if reduceMotion {
                foliage(w: w, h: h, side: side, t: 0)
            } else {
                // 30 Bilder/s reichen für Blätter und sparen gegenüber der
                // vollen Bildrate der Anzeige.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    foliage(w: w, h: h, side: side,
                            t: tl.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    private func foliage(w: CGFloat, h: CGFloat, side: CGFloat, t: TimeInterval) -> some View {
        let strength = Self.wind(at: t)
        let amplitude = Self.calmSwing + Self.gustSwing * strength

        return ZStack {
            ForEach(Array(Self.sprigs.enumerated()), id: \.offset) { index, s in
                let len = side * s.length
                let phase = Double(index) * 0.9
                let swing = sin(t * s.speed + phase) * amplitude
                // Ein winziges Heben und Senken dazu — ein Blatt, das sich nur
                // dreht, wirkt wie an einer Achse festgeschraubt.
                let bob = sin(t * s.speed * 0.6 + phase) * 1.6 * strength

                leaf(s)
                    .frame(width: len, height: h * s.thickness)
                    // Anker am Blattansatz, nicht in der Mitte — sonst
                    // rudert das Blatt, statt sich zu wiegen.
                    .rotationEffect(.degrees(s.angle + swing),
                                    anchor: s.onLeft ? .leading : .trailing)
                    .position(x: s.onLeft ? s.base + len / 2 : w - s.base - len / 2,
                              y: h * s.y + bob)
            }
        }
        .frame(width: w, height: h)
    }

    private func leaf(_ s: Sprig) -> some View {
        ZStack {
            LeafShape().fill(s.color.opacity(0.92))
            LeafShape().stroke(Theme.textPrimary.opacity(0.75), lineWidth: 1.6)
            // Mittelrippe — ohne sie sieht das Blatt wie ein Bonbon aus.
            LeafRib().stroke(Theme.textPrimary.opacity(0.45), lineWidth: 1.2)
        }
    }
}

/// Spitz an beiden Enden — die einfachste Form, die man als Blatt liest.
private struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY),
                       control: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY),
                       control: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

private struct LeafRib: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.06, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.10, y: r.midY))
        return p
    }
}
