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
        /// GENAU ZWEI — die persönlich stärksten Ideen des Directors für
        /// dieses Foto. Kein Menü, zwei Vorschläge.
        let picks: [Option]
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
        request.timeoutInterval = 30
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
        request.timeoutInterval = 90
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
                    preview: (o["preview"] as? String).flatMap { $0.isEmpty ? nil : $0 }
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
            picks: Array(options("picks").prefix(2)),
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
        let ok: Bool
        let issues: [String]
        let isMajor: Bool
        let correctedPrompt: String?

        /// Nichts zu beanstanden — oder nichts, was man beanstanden konnte.
        static let passed = Review(ok: true, issues: [], isMajor: false, correctedPrompt: nil)

        /// Lohnt ein weiterer Anlauf?
        var worthRetrying: Bool {
            !ok && isMajor && (correctedPrompt?.isEmpty == false)
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
            isMajor: (json["severity"] as? String) == "major",
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
