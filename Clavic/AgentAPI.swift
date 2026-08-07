//
//  AgentAPI.swift
//  Clavic
//
//  Netzwerk-Client für den In-App-Agenten. Schickt den Chatverlauf (Text) plus
//  die aktuell angehängten Fotos (verkleinert, nur zur Analyse) an das Backend
//  (/v1/agent/chat → Claude Tool-Use) und bekommt zurück:
//    • reply  – Text-Antwort für den Chat
//    • action – optional: der Agent will ein Bild erzeugen/bearbeiten. Dann
//               rendert die APP das Bild anschließend selbst über GPT Image 2
//               (mit den Fotos in voller Qualität) – gleicher Pfad wie der
//               bestehende Image-Edit-Chat.
//

import UIKit

enum AgentAPI {

    /// Der Agent möchte ein Bild erzeugen/bearbeiten.
    struct Action {
        let prompt: String
        /// "low" | "medium" | "high"
        let quality: String
    }

    /// Eine antippbare Edit-Richtung nach der Foto-Analyse.
    struct Option {
        let label: String
        let prompt: String
    }

    struct Reply {
        let text: String
        let action: Action?
        let options: [Option]
    }

    struct HistoryTurn {
        let role: String   // "user" | "assistant"
        let text: String
    }

    /// Urteil des Realism-QA-Agenten über ein gerendertes Ergebnis.
    struct QAResult {
        let ok: Bool
        let issues: [String]
        let correctedPrompt: String?
    }

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    private static var chatURL: URL { URL(string: base + "/v1/agent/chat")! }
    private static var qaURL: URL { URL(string: base + "/v1/agent/qa")! }

    /// Fragt den Agenten. `images` = die zu DIESEM Zug angehängten Fotos (Original-
    /// bytes); sie werden hier klein gerechnet, damit der Request-Body klein bleibt.
    /// `persona`: "larp" | "feed" | "fashion".
    /// Alle teilen sich Endpunkt und Mechanik, haben aber eigene Wissensbasen.
    static func chat(history: [HistoryTurn], message: String, images: [Data], persona: String = "larp") async throws -> Reply {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        // Fotos nur zur ANALYSE → groß genug für Kleidung, Licht, Hintergrund und
        // Perspektive, aber weiterhin deutlich kleiner als das Render-Original.
        // 640 px / JPEG 0.5 hat wichtige Szenendetails für den Agenten zerstört.
        let imageB64: [String] = images.prefix(6).compactMap { data in
            if let small = UIImage(data: data)?.jpegForAPIUpload(maxDimension: 1024, quality: 0.72) {
                return small.base64EncodedString()
            }
            return data.isEmpty ? nil : data.base64EncodedString()
        }

        let historyJSON = history.suffix(12).map { ["role": $0.role, "text": $0.text] }

        let body: [String: Any] = [
            "message": message,
            "history": historyJSON,
            "images": imageB64,
            "persona": persona,
        ]

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !BackendConfiguration.sharedSecret.isEmpty {
            request.setValue("Bearer \(BackendConfiguration.sharedSecret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 70

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Der Agent ist nur die Planungs-Schicht. Ein Netzwerk-/Provider-
            // Problem darf die eigentliche Bild-Engine nicht blockieren.
            return fallbackReply(message: message, hasImages: !images.isEmpty)
        }
        guard let http = response as? HTTPURLResponse else {
            return fallbackReply(message: message, hasImages: !images.isEmpty)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            return fallbackReply(message: message, hasImages: !images.isEmpty)
        }
        guard let json else { return fallbackReply(message: message, hasImages: !images.isEmpty) }

        let reply = (json["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var action: Action? = nil
        if let a = json["action"] as? [String: Any],
           (a["type"] as? String) == "edit_image",
           let prompt = a["prompt"] as? String, !prompt.isEmpty {
            let quality = (a["quality"] as? String) ?? "medium"
            action = Action(prompt: prompt, quality: quality)
        }

        var options: [Option] = []
        if let list = json["options"] as? [[String: Any]] {
            options = list.compactMap { o in
                guard let label = o["label"] as? String, !label.isEmpty,
                      let prompt = o["prompt"] as? String, !prompt.isEmpty else { return nil }
                return Option(label: label, prompt: prompt)
            }
        }

        return Reply(text: reply.isEmpty ? "…" : reply, action: action, options: options)
    }

    /// Deterministischer Notfall-Agent: hält den Larp-Flow funktionsfähig, wenn
    /// Claude/Anthropic kein Guthaben hat, rate-limited ist oder nicht antwortet.
    /// Der teure Render läuft danach unverändert über ImageEditAPI.
    private static func fallbackReply(message: String, hasImages: Bool) -> Reply {
        let raw = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.lowercased()
        let vaguePhrases: Set<String> = [
            "hi", "hey", "hello", "yo", "make it cool", "make this cool",
            "flex this", "what can you do", "surprise me", "ideas",
            "analyse this", "analyze this"
        ]
        let asksForIdeas = normalized.range(
            of: #"\b(analy[sz]e|ideas?|options?|ways?|suggest|recommend|what can|what would|flex this)\b"#,
            options: .regularExpression
        ) != nil
        let isVague = raw.isEmpty || raw.count < 10 || asksForIdeas || vaguePhrases.contains(normalized)
        let identityLock = hasImages
            ? "Keep the exact same person from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, redraw or alter their identity. "
            : ""
        let realism = " Match the source perspective, light direction, colour temperature, reflections, shadows and phone-camera grain. Make it genuinely photorealistic with natural skin texture, correct hands and crisp details."

        if hasImages && isVague {
            let options = [
                Option(
                    label: "Diamond chain",
                    prompt: identityLock + "Add one premium iced-out diamond Cuban-link chain while keeping the pose, clothes, face and original location unchanged." + realism
                ),
                Option(
                    label: "Supercar arrival",
                    prompt: identityLock + "Place the person naturally beside a real black Lamborghini at an upscale night arrival with believable direct-flash lighting." + realism
                ),
                Option(
                    label: "Private jet",
                    prompt: identityLock + "Move the scene to a private-jet runway at golden hour with understated luxury clothes and one clear hero flex." + realism
                )
            ]
            return Reply(text: "I’ve got the photo — pick the flex and I’ll build it.", action: nil, options: options)
        }

        let request = raw.isEmpty ? "Create a believable luxury lifestyle portrait with one strong hero flex" : raw
        let prompt = identityLock
            + request
            + ". Keep everything the user did not ask to change consistent with the source."
            + realism
        return Reply(
            text: "Say less — I’m building that now.",
            action: Action(prompt: prompt, quality: "medium"),
            options: []
        )
    }

    /// Realism-QA: lässt den zweiten Agenten Original(e) vs. Ergebnis benoten.
    /// Bei Netz-/Parse-Fehlern gibt der Server `ok:true` zurück → QA blockiert den
    /// Flow nie. `originals` = die Quell-Fotos, `result` = das gerenderte Bild.
    static func qa(originals: [Data], result: Data, prompt: String) async throws -> QAResult {
        guard BackendConfiguration.isConfigured else { return QAResult(ok: true, issues: [], correctedPrompt: nil) }

        let origB64: [String] = originals.prefix(3).compactMap { data in
            if let small = UIImage(data: data)?.jpegForAPIUpload(maxDimension: 640, quality: 0.5) {
                return small.base64EncodedString()
            }
            return data.isEmpty ? nil : data.base64EncodedString()
        }
        guard let resB64 = UIImage(data: result)?.jpegForAPIUpload(maxDimension: 640, quality: 0.5)?.base64EncodedString(),
              !origB64.isEmpty else {
            return QAResult(ok: true, issues: [], correctedPrompt: nil)
        }

        let body: [String: Any] = ["prompt": prompt, "images": origB64, "result": resB64]

        var request = URLRequest(url: qaURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !BackendConfiguration.sharedSecret.isEmpty {
            request.setValue("Bearer \(BackendConfiguration.sharedSecret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 70

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return QAResult(ok: true, issues: [], correctedPrompt: nil)   // im Zweifel durchwinken
        }

        let ok = (json["ok"] as? Bool) ?? true
        let issues = (json["issues"] as? [String]) ?? []
        let corrected = json["correctedPrompt"] as? String
        return QAResult(ok: ok, issues: issues, correctedPrompt: (corrected?.isEmpty == false) ? corrected : nil)
    }
}
