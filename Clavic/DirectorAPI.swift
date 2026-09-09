//
//  DirectorAPI.swift
//  Clavic
//
//  Der Client zum Photo Director. Löst `AgentAPI` ab.
//
//  ZWEI AUFRUFE, UND DAS IST ABSICHT:
//
//  `read(image:)` schickt EIN Foto und bekommt die Bildlesung zurück — was
//  drauf ist, woher das Licht kommt, wie hart, welcher Ausschnitt, was dem
//  Bild schadet. Das dauert rund zehn Sekunden, weshalb die App ihn startet,
//  sobald ein Foto angehängt wird, und nicht erst beim Senden. Bis der Nutzer
//  seinen Satz getippt hat, liegt die Lesung da.
//
//  `chat(...)` ist der eigentliche Zug. Liegt eine Lesung vor, geht sie als
//  Text mit und das Foto bleibt zu Hause — billiger und über mehrere Züge
//  wiederverwendbar. Liegt keine vor, gehen die Fotos mit und der Director
//  sieht selbst. NIE wird auf die Lesung gewartet.
//
//  Was gegenüber dem alten `AgentAPI` neu ist:
//   • `id` statt Label-Vergleich. Vorher hat die App Optionen über ihren
//     ANZEIGETEXT wiedererkannt — daran ist jede Umbenennung zerbrochen.
//   • `mode` sagt, was mit dem Foto passiert: grade · retouch · restage ·
//     generate. Vorher musste die App das raten.
//   • `preview` nennt das Vorschau-Asset, wenn es ein Look aus dem Katalog ist.
//

import UIKit

enum DirectorAPI {

    /// Was mit dem Foto geschieht.
    enum Mode: String {
        /// Nur Licht und Farbe. Motiv, Pose, Ausschnitt bleiben.
        case grade
        /// Gleiche Szene, aber etwas wird entfernt, gesäubert oder repariert.
        case retouch
        /// Ort, Kleidung oder Requisiten ändern sich. Identität bleibt gesperrt.
        case restage
        /// Etwas Neues entsteht.
        case generate

        /// true, wenn das Originalfoto erhalten bleibt.
        var keepsPhoto: Bool { self == .grade || self == .retouch }
    }

    /// Eine antippbare Richtung.
    struct Option: Identifiable, Hashable {
        let id: String
        let label: String
        let caption: String
        let mode: Mode
        let prompt: String
        /// Asset-Name, wenn es ein Look aus dem Hauskatalog ist.
        let preview: String?
        /// DIE LEISE EBENE: die technische Arbeit, die diese Richtung braucht.
        ///
        /// Steht bewusst NICHT auf der Karte. Der Nutzer waehlt ein Ergebnis
        /// („Natural Mountain Editorial"), nicht eine Liste von Handgriffen.
        /// Beim Rendern gehen die Schritte als Checkliste an das Bildmodell —
        /// dort entscheiden sie, ob aus der Vision ein gutes Bild wird.
        var internalSteps: [String] = []
        /// Nur bei Trends: der eine, der zu DIESEM Foto herausragt. Der
        /// Director hat die Bildlesung — er kann das beurteilen, und genau
        /// dafuer ist er da. Der Nutzer soll keine Galerie durchsuchen.
        var isBestMatch: Bool = false
    }

    /// Der Director will direkt rendern.
    struct Action {
        let prompt: String
        let mode: Mode
        let quality: String
    }

    struct Reply {
        /// Eine Zeile, die den stärksten Befund aus dem Foto benennt.
        let message: String
        /// EINE, ZWEI ODER DREI — so viele, wie dieses Foto verdient.
        ///
        /// Vorher stand hier „genau zwei". Zwei Antworten auf jedes Foto ist
        /// aber keine Meinung, sondern ein Layout: man sieht sofort, dass das
        /// System immer dasselbe tut. Wie viele es sind, ist selbst Teil des
        /// Urteils — ein sicherer Einzelvorschlag ist stärker als zwei, von
        /// denen einer nur die Zeile füllt.
        let picks: [Option]
        /// Der Vorschlag, den er selbst nehmen würde, wenn einer klar vorn
        /// liegt. Bei genau einem Vorschlag immer gesetzt.
        let lead: String?
        /// DIE BILDLESUNG AUS STUFE 1.
        ///
        /// Das Backend hat sie schon immer mitgeliefert und die App hat sie
        /// weggeworfen. Wer sie behält, kann später weitere Fragen zu
        /// demselben Foto stellen, ohne es noch einmal analysieren zu lassen —
        /// die Trend-Auswahl tut genau das.
        let reading: Reading?
        /// Aktuelle Trends, nach Passung zu DIESEM Foto sortiert, bester
        /// zuerst. Darf leer sein — dann trägt das Foto gerade keinen.
        let trends: [Option]
        let action: Action?
    }

    struct HistoryTurn {
        let role: String   // "user" | "assistant"
        let text: String
    }

    /// Die Bildlesung. Die App reicht sie nur durch — sie muss den Inhalt
    /// nicht kennen, nur weitergeben.
    typealias Reading = [String: Any]

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    private static var chatURL: URL { URL(string: base + "/v1/director/chat")! }
    private static var readURL: URL { URL(string: base + "/v1/director/read")! }

    /// 1024 px reichen für Licht, Ausschnitt und Hintergrund. Kleiner hat in
    /// früheren Messungen Szenendetails zerstört, größer bringt nichts mehr.
    private static func encode(_ data: Data) -> String? {
        UIImage(data: data)?.jpegForAPIUpload(maxDimension: 1024, quality: 0.72)?.base64EncodedString()
    }

    // MARK: - Stufe 1

    /// Liest ein Foto. Wirft nicht — ohne Lesung läuft der Zug trotzdem.
    static func read(image: Data) async -> Reading? {
        guard BackendConfiguration.isConfigured, let b64 = encode(image) else { return nil }

        var request = URLRequest(url: readURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 60 s, nicht 30. Seit die Lesung ueber WaveSpeed laeuft statt ueber
        // fal, dauert sie GEMESSEN 17 bis 23 Sekunden — bei 30 waere jeder
        // langsamere Lauf abgebrochen und der Nutzer haette ohne Lesung
        // weitergemacht, also teurer und schlechter.
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["images": [b64]])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return json["reading"] as? Reading
    }

    // MARK: - Stufe 2

    static func chat(history: [HistoryTurn],
                     message: String,
                     images: [Data],
                     reading: Reading? = nil) async throws -> Reply {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        // Fotos NUR mitschicken, wenn keine Lesung vorliegt.
        let imageB64: [String] = reading == nil ? images.prefix(4).compactMap(encode) : []

        var body: [String: Any] = [
            "message": message,
            "history": history.suffix(10).map { ["role": $0.role, "text": $0.text] },
            "images": imageB64,
        ]
        if let reading { body["reading"] = reading }

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 150 s. Der Entscheider braucht ueber WaveSpeed gemessen 36 bis 45 s,
        // gegenueber 12 bis 15 direkt — das OpenAI-Protokoll ist langsamer.
        // Reserve fuer einen zaehen Lauf, sonst bricht der Zug kurz vor dem
        // Ziel ab und der Nutzer sieht nur einen Fehler.
        request.timeoutInterval = 150
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SeedanceError.invalidResponse }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SeedanceError.server("Director \(http.statusCode)") }

        func options(_ key: String) -> [Option] {
            (json[key] as? [[String: Any]] ?? []).compactMap { o in
                guard let id = o["id"] as? String, !id.isEmpty,
                      let prompt = o["prompt"] as? String, !prompt.isEmpty else { return nil }
                return Option(
                    id: id,
                    label: (o["label"] as? String) ?? id,
                    caption: (o["caption"] as? String) ?? "",
                    mode: Mode(rawValue: (o["mode"] as? String) ?? "") ?? .grade,
                    prompt: prompt,
                    preview: (o["preview"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    internalSteps: (o["internal_steps"] as? [String])?
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty } ?? [],
                    isBestMatch: (o["fit"] as? String) == "best"
                )
            }
        }

        var action: Action?
        if let a = json["action"] as? [String: Any],
           let prompt = a["prompt"] as? String, !prompt.isEmpty {
            action = Action(
                prompt: prompt,
                mode: Mode(rawValue: (a["mode"] as? String) ?? "") ?? .grade,
                quality: (a["quality"] as? String) ?? "medium"
            )
        }

        return Reply(
            message: ((json["message"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            picks: Array(options("picks").prefix(3)),
            lead: (json["lead"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            reading: json["reading"] as? Reading,
            trends: options("trends"),
            action: action
        )
    }

    // MARK: - Der Director prüft sein eigenes Ergebnis

    /// Urteil über ein gerendertes Bild.
    ///
    /// `severity` entscheidet, ob ein zweiter Versuch sich lohnt: `major`
    /// heißt, Identität, Hände oder der „sieht aus wie ein neues Bild"-Test
    /// sind durchgefallen. Das sind die Fehler, die ein Mensch sofort sieht.
    struct Review {
        /// Wie schwer der Fehler wiegt — und danach, wie oft nachgebessert wird.
        enum Severity: String {
            /// Kleinigkeiten, die niemand bemerkt. Kein zweiter Anlauf.
            case minor
            /// Technisch sauber und trotzdem falsch: die gewaehlte Richtung ist
            /// nicht angekommen. GENAU EIN weiterer Anlauf — es ist ein echter
            /// Fehler, aber keiner, fuer den man beliebig oft rendern darf.
            case look
            /// Identitaet, Haende oder „sieht aus wie ein neues Bild". Der
            /// bestehende Weg mit bis zu zwei Anlaeufen.
            case major
        }

        let ok: Bool
        let issues: [String]
        let severity: Severity
        let correctedPrompt: String?

        /// Nichts zu beanstanden — oder nichts, was man beanstanden konnte.
        static let passed = Review(ok: true, issues: [], severity: .minor, correctedPrompt: nil)

        /// Lohnt ein weiterer Anlauf?
        var worthRetrying: Bool {
            !ok && severity != .minor && (correctedPrompt?.isEmpty == false)
        }

        /// Ein verfehlter Look bekommt nur EINEN Versuch, kein zweites Rendern.
        var isLookMiss: Bool { severity == .look }

        /// Die Beanstandung, die von einem echten Identitaetsverlust spricht.
        ///
        /// Der Server stuft solche Faelle bereits im Code auf `major` hoch;
        /// hier wird nur herausgelesen, WELCHE Beanstandung es war, damit die
        /// App sie dem Nutzer nennen kann statt „Fehler" zu sagen.
        ///
        /// DIE WORTLISTE WAR ZU BREIT UND HAT EIN GUTES BILD GEKOSTET. Sie
        /// enthielt `face`, `eyes`, `skin tone`, `complexion`, `age` — genau
        /// die Woerter, mit denen ein Pruefer auch eine gelungene
        /// FARBKORREKTUR beschreibt („skin tone is warmer"). Ein G7X-Grade ist
        /// daran als Identitaetsverlust gescheitert und wurde verworfen.
        ///
        /// Sie ist absichtlich dieselbe wie auf dem Server. Wer eine der
        /// beiden aendert, muss die andere mitaendern — sonst wirft die App
        /// weg, was der Server durchgewunken hat, oder umgekehrt.
        var identityIssue: String? {
            guard !ok, severity == .major else { return nil }
            let woerter = [
                "identity", "different person", "another person", "not the same person",
                "looks like someone else", "different woman", "different man", "new person",
                "lookalike", "look-alike",
                "face shape", "facial structure", "facial geometry", "bone structure",
                "jawline", "jaw shape", "nose shape", "different nose", "reshaped",
                "eye colour", "eye color",
                "hair", "hairstyle", "hairline", "bangs", "fringe", "ponytail", "braid", "wig",
            ]
            return issues.first { issue in
                let t = issue.lowercased()
                return woerter.contains { t.contains($0) }
            }
        }
    }

    private static var reviewURL: URL { URL(string: base + "/v1/director/review")! }

    /// Prüft ein Ergebnis gegen die Originale — nach den Regeln des Modus.
    ///
    /// Wirft nie: eine gescheiterte Prüfung darf ein gutes Bild nicht
    /// aufhalten. Im Zweifel gilt das Bild als bestanden.
    static func review(originals: [Data], result: Data, prompt: String, mode: Mode) async -> Review {
        guard BackendConfiguration.isConfigured else { return .passed }

        let origB64 = originals.prefix(3).compactMap {
            UIImage(data: $0)?.jpegForAPIUpload(maxDimension: 768, quality: 0.6)?.base64EncodedString()
        }
        guard let resB64 = UIImage(data: result)?
                .jpegForAPIUpload(maxDimension: 768, quality: 0.6)?.base64EncodedString(),
              !origB64.isEmpty || mode == .generate
        else { return .passed }

        var request = URLRequest(url: reviewURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !BackendConfiguration.sharedSecret.isEmpty {
            request.setValue("Bearer \(BackendConfiguration.sharedSecret)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 70
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "prompt": prompt, "images": origB64, "result": resB64, "mode": mode.rawValue,
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .passed }

        let corrected = (json["correctedPrompt"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Review(
            ok: (json["ok"] as? Bool) ?? true,
            issues: (json["issues"] as? [String]) ?? [],
            severity: Review.Severity(rawValue: (json["severity"] as? String) ?? "") ?? .minor,
            correctedPrompt: (corrected?.isEmpty == false) ? corrected : nil
        )
    }

    // MARK: - Die Karten beim Start

    /// Eine Karte, die das Chamäleon beim Öffnen wirft.
    ///
    /// Sie trägt KEINEN Bild-Prompt, sondern nur `ask` — eine Absicht in
    /// normaler Sprache. Ohne Foto gibt es nichts zu bearbeiten; wer antippt,
    /// sagt dem Director bloß, worauf er hinauswill.
    struct ShowcaseCard: Identifiable, Hashable {
        let id: String
        let label: String
        let caption: String
        /// "trend" = was gerade läuft · "skill" = was der Director kann.
        let kind: String
        let preview: String?
        /// Zeichen für Karten ohne Vorschaufoto — sonst steht dort eine leere
        /// graue Fläche.
        let icon: String
        let ask: String

        var isTrend: Bool { kind == "trend" }
    }

    private static var showcaseURL: URL { URL(string: base + "/v1/director/showcase")! }

    /// Holt die Startkarten. Wirft nie — die App hat einen eigenen Vorrat.
    ///
    /// Reine Leseoperation ohne Modell, kostet also nichts. Deshalb darf sie
    /// beim Öffnen laufen.
    static func showcase() async -> [ShowcaseCard] {
        guard BackendConfiguration.isConfigured else { return [] }
        var request = URLRequest(url: showcaseURL)
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["cards"] as? [[String: Any]]
        else { return [] }

        return list.compactMap { c in
            guard let id = c["id"] as? String, !id.isEmpty,
                  let label = c["label"] as? String, !label.isEmpty else { return nil }
            return ShowcaseCard(
                id: id,
                label: label,
                caption: (c["caption"] as? String) ?? "",
                kind: (c["kind"] as? String) ?? "skill",
                preview: (c["preview"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                icon: (c["icon"] as? String) ?? "sparkles",
                ask: (c["ask"] as? String) ?? "I want the \(label) look on my photo."
            )
        }
    }
}


// MARK: - Trend-Auswahl

extension DirectorAPI {

    /// Was der Director über die angebotenen Trends sagt.
    struct TrendVerdict {
        /// Die id des Trends, den er nehmen würde. `nil` heißt: keiner passt.
        let bestID: String?
        /// Ein Satz. Bei `bestID == nil` steht hier, warum keiner passt.
        let why: String
        /// Bis zu zwei weitere, die auch gehen.
        let alsoIDs: [String]
        /// Bindet die spätere Wahl des Nutzers an GENAU diese Empfehlung.
        /// Ohne sie liesse sich nie sagen, ob jemand dem Director gefolgt ist.
        let selectionID: String?

        static let none = TrendVerdict(bestID: nil, why: "", alsoIDs: [], selectionID: nil)
    }

    /// „Welcher dieser Trends passt zu DIESEM Foto?"
    ///
    /// EIN EIGENER AUFTRAG, nicht der normale Zug. Der normale Director bildet
    /// erst eine eigene Vision und prüft Trends danach als Ausführung; hier hat
    /// der Nutzer ausdrücklich nach Trends gefragt, also ist das die Aufgabe.
    ///
    /// ES GEHT KEIN BILD MIT. Die Lesung liegt aus dem letzten Zug vor und
    /// beantwortet die Frage vollständig — ein zweites Mal sehen kostet Geld
    /// und bringt nichts. Ohne Lesung wird gar nicht erst gefragt.
    ///
    /// ES WIRD NICHTS GERENDERT. Der Nutzer bekommt eine Empfehlung und
    /// entscheidet selbst; Credits fließen erst, wenn er einen Trend bestätigt.
    ///
    /// Wirft nie: ohne Urteil zeigt die Liste sich wie bisher.
    static func rankTrends(reading: Reading, offered: [Option]) async -> TrendVerdict {
        guard BackendConfiguration.isConfigured, !offered.isEmpty else { return .none }

        let body: [String: Any] = [
            "intent": "trend_selection",
            "reading": reading,
            "trends": offered.prefix(24).map {
                ["id": $0.id, "label": $0.label, "caption": $0.caption]
            },
        ]
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .none }

        let best = (json["bestId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return TrendVerdict(
            bestID: (json["verdict"] as? String) == "one_fits" ? best : nil,
            why: ((json["why"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            alsoIDs: (json["alsoIds"] as? [String]) ?? [],
            selectionID: (json["selectionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// Meldet, welchen Trend der Nutzer wirklich genommen hat.
    ///
    /// Das zweite Ereignis zur Empfehlung — erst mit ihm laesst sich sagen, ob
    /// jemand dem Director gefolgt ist oder ihn uebergangen hat. Ohne das
    /// waeren alle Empfehlungen unbewertbar.
    ///
    /// KEIN Modellaufruf, keine Wartezeit: abgeschickt und vergessen. Ein
    /// Fehlschlag darf den Nutzer nicht aufhalten — dann fehlt eine Logzeile,
    /// mehr nicht.
    static func reportTrendChoice(selectionID: String?, chosenID: String, bestID: String?) {
        guard BackendConfiguration.isConfigured else { return }
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "intent": "trend_choice",
            "selectionId": selectionID as Any,
            "chosenId": chosenID,
            "bestId": bestID as Any,
            "source": "trend_sheet",
        ])
        URLSession.shared.dataTask(with: request).resume()
    }
}
