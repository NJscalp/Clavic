//
//  SchleifenVideo.swift
//  Clavic
//
//  Ein kurzer Clip, endlos, ohne sichtbare Naht.
//
//  WARUM DAS NICHT `AVPlayerLooper` MACHT. Genau der stand vorher hier — und
//  genau der ist im Maskottchen der Buehne schon einmal durchgefallen. Die
//  Messung steht in `MascotStage.swift` und gilt hier unveraendert: bei JEDER
//  Wiederholung fehlte die Figur ein bis zwei Bilder lang vollstaendig, der
//  Sprung von Bild zu Bild ging dabei auf 49,5 von 255 hoch, waehrend er sonst
//  bei 0,8 liegt. Der Looper tauscht das Item, und die `AVPlayerLayer` hat in
//  diesem Moment nichts anzuzeigen. Alle vier Sekunden ein Aussetzer — genau
//  das, was im Onboarding als „ruckelt, man sieht den Schnitt" ankam.
//
//  `automaticallyWaitsToMinimizeStalling = false` half nicht; es ist kein
//  Pufferproblem, sondern der Item-Wechsel. Die Clips selbst sind in Ordnung:
//  gemessen springt das letzte Bild zum ersten nur um 0,84 bis 0,88 von 255,
//  waehrend ein normaler Bildwechsel im Clip schon bei 1,1 bis 1,9 liegt. Die
//  Naht ist also unsichtbar — sie wurde nur nie gezeigt.
//
//  DIE LOESUNG, uebernommen aus `MascotStage`: zwei Ebenen im Wechsel. Der
//  Clip liegt gleich zu Beginn eines Durchgangs auch auf der versteckten Ebene
//  bereit und wird dort mit `preroll` bis zum ersten dekodierten Bild
//  vorgespult. Zwei Hundertstel vor Schluss werden nur noch die Deckkraefte
//  getauscht — ohne Animation, in einem Bild. Es gibt keinen Item-Wechsel und
//  damit auch keine leere Ebene.
//
//  Bewusst kein eigener Nachbau, sondern dieselbe Mechanik wie in
//  `MascotStage`: zwei Schleifen-Implementierungen nebeneinander waren der
//  Grund, dass der Fehler an einer Stelle behoben war und an der anderen nicht.
//

import AVFoundation
import SwiftUI
import UIKit

/// Spielt einen Clip stumm in Endlosschleife.
struct SchleifenVideo: UIViewRepresentable {
    /// Der Clip. Fehlt er, bleibt die Flaeche leer statt abzustuerzen.
    let quelle: URL?
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// Aus, solange die Ansicht nicht sichtbar sein soll (anderer Tab, Sheet
    /// darueber). Spart Dekodierung, ohne den Aufbau wegzuwerfen.
    var isActive: Bool = true

    /// Aus dem Bundle, ueber den Dateinamen ohne Endung.
    init(name: String, gravity: AVLayerVideoGravity = .resizeAspect, isActive: Bool = true) {
        // `.mov` als zweiter Versuch: die Maskottchen-Clips der Buehne liegen
        // in dem Format vor, und ein Aufrufer soll den Unterschied nicht
        // kennen muessen.
        self.quelle = Bundle.main.url(forResource: name, withExtension: "mp4")
            ?? Bundle.main.url(forResource: name, withExtension: "mov")
        self.gravity = gravity
        self.isActive = isActive
    }

    init(url: URL, gravity: AVLayerVideoGravity = .resizeAspect, isActive: Bool = true) {
        self.quelle = url
        self.gravity = gravity
        self.isActive = isActive
    }

    func makeUIView(context: Context) -> SchleifenView {
        let v = SchleifenView()
        v.backgroundColor = .clear
        if let quelle { v.starte(url: quelle, gravity: gravity) }
        v.setzeAktiv(isActive)
        return v
    }

    func updateUIView(_ uiView: SchleifenView, context: Context) {
        if let quelle { uiView.starte(url: quelle, gravity: gravity) }  // no-op bei gleichem Clip
        uiView.setzeAktiv(isActive)
    }

    static func dismantleUIView(_ uiView: SchleifenView, coordinator: ()) {
        uiView.stoppe()
    }
}

final class SchleifenView: UIView {

    // Zwei Ebenen, zwei Spieler. Immer eine sichtbar, die andere haelt den
    // naechsten Durchgang startbereit.
    private let ebeneA = AVPlayerLayer()
    private let ebeneB = AVPlayerLayer()
    private let spielerA = AVPlayer()
    private let spielerB = AVPlayer()

    private var vorneIstA = true
    private var vorne: AVPlayer { vorneIstA ? spielerA : spielerB }
    private var hinten: AVPlayer { vorneIstA ? spielerB : spielerA }
    private var vordereEbene: AVPlayerLayer { vorneIstA ? ebeneA : ebeneB }
    private var hintereEbene: AVPlayerLayer { vorneIstA ? ebeneB : ebeneA }

    private var quelle: URL?
    private var aktuell: URL?
    private var grenzen: [(AVPlayer, Any)] = []
    private var lebenszyklus: [NSObjectProtocol] = []
    private var wachhund: Timer?
    private var zuletztGesehen: Double = -1
    private var pausiert = false
    /// Was der Aufrufer will — getrennt davon, ob die Ansicht gerade im
    /// Fenster haengt. Beides muss stimmen, damit gespielt wird.
    private var willLaufen = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        for (ebene, spieler) in [(ebeneA, spielerA), (ebeneB, spielerB)] {
            spieler.isMuted = true
            // Lokale Datei, ein paar Sekunden lang — es gibt nichts zu puffern.
            spieler.automaticallyWaitsToMinimizeStalling = false
            ebene.player = spieler
            ebene.videoGravity = .resizeAspect
            ebene.opacity = 0
            layer.addSublayer(ebene)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nur programmatisch") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ebeneA.frame = bounds; ebeneB.frame = bounds
        CATransaction.commit()
    }

    // MARK: Start und Stopp

    func starte(url: URL, gravity: AVLayerVideoGravity = .resizeAspect) {
        guard aktuell != url else { return }           // schuetzt vor Doppelstart
        stoppe()
        ebeneA.videoGravity = gravity
        ebeneB.videoGravity = gravity
        aktuell = url
        quelle = url
        pausiert = false

        CATransaction.begin(); CATransaction.setDisableActions(true)
        vordereEbene.opacity = 1; vordereEbene.zPosition = 1
        hintereEbene.opacity = 0; hintereEbene.zPosition = 0
        CATransaction.commit()

        starteDurchgang(url, auf: vorne)
        beobachteLebenszyklus()
        starteWachhund()
    }

    /// An oder aus, ohne den Aufbau wegzuwerfen.
    ///
    /// Gebraucht von den Vorschauen: eine Kachel in einem anderen Tab soll
    /// nicht dekodieren, aber beim Zurueckkommen sofort wieder laufen.
    func setzeAktiv(_ aktiv: Bool) {
        guard willLaufen != aktiv else { return }
        willLaufen = aktiv
        wendeLaufAn()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // Aus der Ansicht gescrollt heisst: nicht dekodieren.
        wendeLaufAn(fenster: newWindow != nil)
    }

    private func wendeLaufAn(fenster: Bool? = nil) {
        let sichtbar = fenster ?? (window != nil)
        pausiert = !(willLaufen && sichtbar)
        if pausiert {
            spielerA.pause(); spielerB.pause()
        } else if vorne.timeControlStatus != .playing {
            vorne.play()
        }
    }

    func stoppe() {
        wachhund?.invalidate(); wachhund = nil
        loeseGrenzen()
        lebenszyklus.forEach { NotificationCenter.default.removeObserver($0) }
        lebenszyklus.removeAll()
        spielerA.pause(); spielerB.pause()
        spielerA.replaceCurrentItem(with: nil)
        spielerB.replaceCurrentItem(with: nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ebeneA.opacity = 0; ebeneB.opacity = 0
        CATransaction.commit()
        aktuell = nil
        quelle = nil
        zuletztGesehen = -1
    }

    deinit { stoppe() }

    // MARK: Der Durchgang

    private func starteDurchgang(_ url: URL, auf spieler: AVPlayer) {
        spieler.replaceCurrentItem(with: element(url))
        spieler.seek(to: .zero)
        if !pausiert { spieler.play() }
        ruesteReserve(url)
        planeUebergabe(url, von: spieler)
    }

    private func element(_ url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1
        return item
    }

    /// Legt denselben Clip auf der versteckten Ebene bereit und spult ihn bis
    /// zum ersten dekodierten Bild vor — SOFORT, nicht kurz vor Schluss.
    ///
    /// In `MascotStage` wurde die Reserve erst eine halbe Sekunde vor dem Ende
    /// bestueckt; dieser zweite Grenzzeit-Beobachter wurde manchmal verpasst,
    /// und dann lag beim Tausch noch der falsche Clip bereit. Jetzt steht die
    /// Reserve Sekunden lang fertig da und der Tausch haengt an nichts mehr.
    private func ruesteReserve(_ url: URL) {
        let reserve = hinten
        reserve.replaceCurrentItem(with: element(url))
        reserve.pause()
        reserve.seek(to: .zero) { _ in Self.spuleVor(reserve, versuche: 3) }
    }

    /// `preroll` NUR bei fertigem Item.
    ///
    /// `AVPlayer.preroll(atRate:)` wirft eine Objective-C-Ausnahme, wenn der
    /// Spieler noch nicht `readyToPlay` ist — in `MascotStage` hat genau das
    /// die App abstuerzen lassen (`EXC_CRASH SIGABRT`). Aus Swift laesst sich
    /// so eine Ausnahme nicht fangen, sie darf also gar nicht erst entstehen.
    /// Ist noch nichts bereit, wird es spaeter erneut versucht; klappt es gar
    /// nicht, faellt nur das Vorspulen aus — die Ebene hat bis zum Tausch
    /// trotzdem Sekunden Zeit, ihr erstes Bild zu dekodieren.
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
        addGrenze(bei: ende - 0.02, auf: spieler) { [weak self] in
            guard let self, self.quelle == url else { return }
            self.uebergib(url, von: spieler)
        }
    }

    private func uebergib(_ url: URL, von alt: AVPlayer) {
        let neu = hinten

        // NIE auf eine Ebene tauschen, die etwas anderes zeigt. Lieber ein
        // harter Neustart desselben Clips — dessen Naht ist gemessen unter 1,2
        // von 255 und damit unsichtbar.
        guard (neu.currentItem?.asset as? AVURLAsset)?.url == url else {
            alt.seek(to: .zero)
            if !pausiert { alt.play() }
            loeseGrenzen()
            ruesteReserve(url)
            planeUebergabe(url, von: alt)
            return
        }

        let neueEbene = hintereEbene, alteEbene = vordereEbene
        if !pausiert { neu.play() }

        // OHNE Animation. Erstes und letztes Bild sind gleich; eine Blende
        // waere hier nur ein weicher Doppelgaenger.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        neueEbene.opacity = 1; neueEbene.zPosition = 1
        alteEbene.opacity = 0; alteEbene.zPosition = 0
        CATransaction.commit()

        vorneIstA.toggle()
        alt.pause()
        loeseGrenzen()
        // Die eben frei gewordene Ebene wird die naechste Reserve.
        ruesteReserve(url)
        planeUebergabe(url, von: neu)
    }

    // MARK: Grenzzeiten

    private func loeseGrenzen() {
        for (p, o) in grenzen { p.removeTimeObserver(o) }
        grenzen.removeAll()
    }

    private func addGrenze(bei sekunden: Double, auf spieler: AVPlayer,
                           _ aktion: @escaping () -> Void) {
        let t = NSValue(time: CMTime(seconds: sekunden, preferredTimescale: 600))
        let o = spieler.addBoundaryTimeObserver(forTimes: [t], queue: .main, using: aktion)
        grenzen.append((spieler, o))
    }

    // MARK: Nie stehenbleiben

    /// iOS haelt beim Wechsel in den Hintergrund jeden `AVPlayer` an; zurueck
    /// im Vordergrund startet ihn niemand von selbst wieder.
    private func beobachteLebenszyklus() {
        let mitte = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification,
                     UIApplication.willEnterForegroundNotification] {
            lebenszyklus.append(mitte.addObserver(forName: name, object: nil,
                                                  queue: .main) { [weak self] _ in
                self?.pausiert = false
                self?.wiederAnwerfen()
            })
        }
        // Beim Verlassen ausdruecklich anhalten: sonst laeuft die Dekodierung
        // im Hintergrund noch kurz weiter und kostet Strom ohne Bild.
        lebenszyklus.append(mitte.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            self?.pausiert = true
            self?.spielerA.pause(); self?.spielerB.pause()
        })
    }

    /// Alle zwei Sekunden nachsehen, ob die Zeit vorangeht.
    ///
    /// Ein verpasster Grenzzeit-Beobachter oder ein fehlgeschlagenes Item
    /// laesst das Bild stehen, ohne dass sich irgendetwas meldet. Das hier ist
    /// die einzige Stelle, die aus so einem Zustand wieder herausfuehrt.
    private func starteWachhund() {
        wachhund?.invalidate()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pruefeLauf()
        }
        // `.common`, sonst steht der Wachhund genau dann still, wenn gescrollt
        // oder geblaettert wird — also wenn ein Haenger am ehesten auffaellt.
        RunLoop.main.add(t, forMode: .common)
        wachhund = t
    }

    private func pruefeLauf() {
        guard !pausiert, window != nil, quelle != nil else { return }
        let jetzt = vorne.currentTime().seconds
        let laeuft = vorne.timeControlStatus == .playing
        let fehler = vorne.currentItem == nil || vorne.currentItem?.status == .failed

        if fehler {
            wiederAnwerfen()
        } else if !laeuft {
            vorne.play()
        } else if jetzt.isFinite, abs(jetzt - zuletztGesehen) < 0.001 {
            // Laeuft angeblich, die Zeit steht trotzdem.
            wiederAnwerfen()
        }
        zuletztGesehen = jetzt.isFinite ? jetzt : -1
    }

    private func wiederAnwerfen() {
        guard !pausiert, let url = quelle else { return }
        loeseGrenzen()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        vordereEbene.opacity = 1; vordereEbene.zPosition = 1
        hintereEbene.opacity = 0; hintereEbene.zPosition = 0
        CATransaction.commit()
        starteDurchgang(url, auf: vorne)
    }
}
