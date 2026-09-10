//
//  PersonalPreviews.swift
//  Clavic
//
//  Waehrend der Director nachdenkt, entstehen die Vorschauen schon — an DEINEM
//  Foto, nicht an dem einer Fremden.
//
//  DAS PROBLEM, DAS DAS LOEST. Jede App dieser Art zeigt ihre Looks am Foto
//  eines Models. Man waehlt also blind: „Golden Hour" sieht auf dem
//  Werbebild toll aus und auf dem eigenen Kuechenfoto nach gar nichts. Erst
//  nach dem Bezahlen sieht man, was der Look mit dem eigenen Bild macht.
//
//  DIE ZEIT IST OHNEHIN DA. Die Bildlesung des Directors dauert GEMESSEN 17
//  bis 23 Sekunden (siehe `DirectorAPI.read`), in denen der Nutzer eine
//  Ladeanimation ansieht. In dieses Fenster passen die Vorschauen: MiniMax H3
//  braucht gemessen 12 bis 20 Sekunden pro Bild und laeuft parallel.
//
//  WARUM MINIMAX UND NICHT DAS GUTE MODELL. Nicht wegen der Qualitaet — wegen
//  der Zeit. GPT Image 2.5 braucht fuer dasselbe 31 bis 44 Sekunden; drei
//  davon parallel waeren teurer als die Generierung, fuer die der Nutzer
//  bezahlt. MiniMax kostet $0,03 je Bild und ist rechtzeitig fertig. Das
//  ENDGUELTIGE Bild rendert weiterhin das gute Modell — die Vorschau ist eine
//  Vorschau.
//
//  DER PROMPT MUSS `<Picture 1>` SAGEN. Das ist keine Stilfrage, sondern die
//  Bedienungsanleitung des Modells: es erwartet seine Eingaben als
//  `<Picture 1>` … `<Picture N>` im Text. GEMESSEN ohne diese Anrede: das
//  Modell behandelt das Foto als lose Inspiration und LOESCHT DIE PERSON —
//  zurueck kam die Szene ohne den Menschen darin. Mit der Anrede steht sie da.
//
//  WAS ES NICHT KANN, und das gehoert dazu: MiniMax setzt den Ausschnitt neu.
//  Die Person bleibt, rueckt aber im Bild. Fuer eine Vorschau in Daumennagel-
//  Groesse ist das in Ordnung; als Endergebnis waere es falsch, und deshalb
//  ist es keins.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class PersonalPreviews {

    /// Look-ID → fertige Vorschau am eigenen Foto.
    private(set) var bilder: [String: Data] = [:]
    /// Welche gerade rechnen — fuer den Platzhalter auf der Karte.
    private(set) var laufen: Set<String> = []

    /// Hoechstens drei.
    ///
    /// Jede Vorschau kostet $0,03, und zwar BEVOR der Nutzer irgendetwas
    /// bezahlt hat. Bei drei sind das $0,09 je gelesenem Foto — vertretbar,
    /// weil die Lesung selbst schon eine Absicht ist. Bei sechs waere es fast
    /// ein Drittel der Marge einer Generierung, fuer Bilder, die niemand
    /// angefordert hat.
    static let maxAnzahl = 3

    /// Vorschau-Modell. Bewusst NICHT `ImageEditAPI.defaultModel`.
    static let modell = "wavespeed-ai/minimax-h3/image-edit"

    private var aufgabe: Task<Void, Never>?
    /// Fuer welches Foto die aktuellen Vorschauen gelten. Ein zweiter Aufruf
    /// mit demselben Foto zahlt nicht noch einmal.
    private var quelle: Data?

    // MARK: Steuerung

    /// Startet die Vorschauen fuer ein Foto. Mehrfachaufrufe fuer dasselbe
    /// Foto sind ein no-op.
    /// AUS. Nicht auskommentiert, sondern ein Schalter — der Rest der Maschine
    /// ist in Ordnung und wartet auf ein brauchbares Modell.
    ///
    /// WARUM ABGESCHALTET. Die Pruefung unten fragt, ob auf der Vorschau EIN
    /// Gesicht ist — nicht, ob es DAS DES NUTZERS ist. MiniMax komponiert die
    /// Szene neu und setzt dabei auch fremde Menschen ein; so eine Vorschau
    /// kommt durch die Pruefung und zeigt dem Nutzer sein Foto mit einer
    /// anderen Person darin. Genau das wurde gemeldet.
    ///
    /// Ein Gesichtsvergleich statt einer Gesichtszaehlung waere die Loesung,
    /// aber solange das Vorschaumodell in zwei von drei Faellen ohnehin
    /// unbrauchbar liefert, ist es das nicht wert. Erst ein Modell, das den
    /// Ausschnitt haelt — dann diese Zeile weg.
    static let eingeschaltet = false

    func starte(fuer foto: Data) {
        guard Self.eingeschaltet else { return }
        guard quelle != foto else { return }
        stoppe()
        quelle = foto
        guard BackendConfiguration.isConfigured, let ui = UIImage(data: foto) else { return }

        aufgabe = Task { [weak self] in
            // Die Auswahl kommt aus der EIGENEN Messung, nicht vom Server:
            // `DirectorReadMarks` rechnet lokal in CoreGraphics und ist sofort
            // fertig. Auf die Antwort des Directors zu warten hiesse, die
            // Zeit zu verlieren, die wir gerade nutzen wollen.
            let marken = await DirectorReadMarks.marks(for: ui)
            guard !Task.isCancelled else { return }
            let looks = Self.auswahl(marken)
            await self?.rendere(looks, foto: foto)
        }
    }

    func stoppe() {
        aufgabe?.cancel()
        aufgabe = nil
        laufen.removeAll()
    }

    /// Neues Foto, neue Vorschauen.
    func leere() {
        stoppe()
        bilder.removeAll()
        quelle = nil
    }

    func bild(_ lookID: String) -> Data? { bilder[lookID] }
    func laeuft(_ lookID: String) -> Bool { laufen.contains(lookID) }

    // MARK: Auswahl

    /// WELCHE Looks vorgerechnet werden — entschieden am gemessenen Licht.
    ///
    /// `DirectorReadMarks` sagt, was mit dem Foto los ist: ausgefressen,
    /// abgesoffen oder flach. Daraus folgt, welcher Look ueberhaupt eine
    /// Verbesserung waere. Ein Blitz-bei-Nacht auf einem schon ueberstrahlten
    /// Foto ist keine Hilfe, sondern eine zweite Baustelle.
    ///
    /// Die Reihenfolge ist die Rangfolge: was zur Messung passt, kommt zuerst.
    /// Danach fuellen die drei verlaesslichsten Looks auf, damit auch bei einem
    /// technisch einwandfreien Foto etwas zu sehen ist.
    static func auswahl(_ marken: [ReadMark]) -> [TikTokTrends.Look] {
        let etiketten = Set(marken.map(\.label))
        var ids: [String] = []

        if etiketten.contains("you're in the dark") { ids += ["g7xflash", "redlight"] }
        if etiketten.contains("light's blown out")  { ids += ["redsunset", "bluehour"] }
        if etiketten.contains("light falls flat")   { ids += ["goldenhour", "bluehour"] }

        ids += ["goldenhour", "g7xflash", "y2kdigicam"]

        var gesehen = Set<String>()
        return ids
            .filter { gesehen.insert($0).inserted }
            .compactMap { TikTokTrends.look(id: $0) }
            .prefix(maxAnzahl)
            .map { $0 }
    }

    // MARK: Rendern

    private func rendere(_ looks: [TikTokTrends.Look], foto: Data) async {
        laufen = Set(looks.map(\.id))

        // Parallel, nicht nacheinander: drei mal 15 Sekunden hintereinander
        // waeren 45 und damit weit hinter der Lesung.
        await withTaskGroup(of: (String, Data?).self) { gruppe in
            for look in looks {
                gruppe.addTask {
                    (look.id, await Self.eineVorschau(look, foto: foto))
                }
            }
            for await (id, daten) in gruppe {
                guard !Task.isCancelled else { return }
                laufen.remove(id)
                if let daten { bilder[id] = daten }
            }
        }
        laufen.removeAll()
    }

    /// Ist die Person auf der Vorschau noch da?
    ///
    /// DIE WICHTIGSTE PRUEFUNG DIESER DATEI. GEMESSEN an sechs Laeufen gegen
    /// die echte Route: MiniMax setzt den Ausschnitt neu, und dabei faellt die
    /// Person mal heraus — bei „golden hour" stand nur noch ein Schuh am
    /// linken Rand, bei „y2k digicam" war sie ganz weg, die Szene blieb.
    ///
    /// Eine Vorschau, die dem Nutzer sein Foto OHNE ihn zeigt, ist schlimmer
    /// als das Beispielbild aus dem Katalog. Also: war auf dem Original ein
    /// Gesicht und ist auf der Vorschau keins, wird sie verworfen und die
    /// Karte bleibt beim Beispiel. Lieber keine eigene Vorschau als eine, in
    /// der man geloescht wurde.
    private static func personNochDa(original: UIImage, vorschau: Data) async -> Bool {
        guard let neu = UIImage(data: vorschau) else { return false }
        let vorher = await FaceAnalyzer.analyze(original)
        guard vorher.hasFace else { return true }   // ohne Gesicht nichts zu verlieren
        return await FaceAnalyzer.analyze(neu).hasFace
    }

    private static func eineVorschau(_ look: TikTokTrends.Look, foto: Data) async -> Data? {
        let anfrage = ImageEditRequest(
            prompt: prompt(fuer: look),
            referenceImages: [foto],
            quality: "low",              // 1K reicht fuer eine Kachel
            aspectRatio: "auto",
            model: modell
        )
        guard let id = try? await ImageEditAPI.createTask(anfrage) else { return nil }
        // Kein Fortschritt nach aussen: eine Vorschau, die nicht kommt, ist
        // kein Fehler, den der Nutzer sehen muss — dann steht dort eben das
        // Haus-Beispiel.
        guard case .success(let bild) = await warte(auf: id) else { return nil }
        guard let original = UIImage(data: foto),
              await personNochDa(original: original, vorschau: bild) else { return nil }
        return bild
    }

    private enum Ausgang { case success(Data), failure }

    private static func warte(auf taskID: String, maxSekunden: Int = 60) async -> Ausgang {
        for _ in 0..<(maxSekunden / 2) {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return .failure }
            guard let stand = try? await ImageEditAPI.fetchTask(id: taskID) else { continue }
            switch stand.status {
            case .succeeded:
                guard let adresse = stand.imageURL, let url = URL(string: adresse),
                      let (daten, _) = try? await URLSession.shared.data(from: url)
                else { return .failure }
                return .success(daten)
            case .failed, .cancelled:
                return .failure
            default:
                continue
            }
        }
        return .failure
    }

    /// Der Prompt fuer die Vorschau.
    ///
    /// Kurz, und mit `<Picture 1>` — siehe Kopf dieser Datei. Der Kern des
    /// Looks kommt aus dem Rezept selbst, damit die Vorschau dieselbe Sache
    /// zeigt, die das gute Modell danach in gross rendert.
    private static func prompt(fuer look: TikTokTrends.Look) -> String {
        let kern = VersionChain.kurzerTitel(look.option.prompt, maximal: 220)
        return """
        Edit <Picture 1>. \(kern)
        Keep the same person with the same face, the same pose, the same clothing \
        and the same framing as in <Picture 1>. Change only light, colour and grain.
        """
    }
}
