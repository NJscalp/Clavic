//
//  ChatVideoAPI.swift
//  Clavic
//
//  Video-Erzeugung direkt aus dem Chat: aktuelles Chat-Bild + Prompt + Dauer
//  → Kling O3 (Omni 3) image-to-video.
//
//  Bewusst ein EIGENER, schlanker Client statt einer weiteren Verzweigung in
//  `KieSeedanceAPI.createTask`: dort hängen Templates, Studio und die Musik-
//  Pipeline dran, und dieser Pfad braucht nichts davon — nur ein Bild, einen
//  Prompt und eine Dauer.
//
//  Wichtiges Detail, live gegen WaveSpeed verifiziert: dieses Modell erwartet
//  `image` als EINZELNEN String, nicht als Array. Deshalb wird `imagesField`
//  NICHT mitgeschickt — der Backend-Wrapper setzt dann von sich aus
//  `payload.image = <url>`. Mit `imagesField: "images"` antwortet die API
//  „field image is required", mit einem Array „must be a string".
//

import Foundation

enum ChatVideoAPI {

    /// Kling O3 (Omni 3) Bild→Video. Anzeigename in der App: „Kling Omni 3".
    static let model = "kwaivgi/kling-video-o3-std/image-to-video"

    /// Wählbare Längen im Chat. Kling O3 rechnet nach Sekunden ab, deshalb
    /// bleibt die Auswahl bewusst klein und die Kosten vorhersehbar.
    enum Duration: Int, CaseIterable, Identifiable {
        case short = 5
        case long = 10
        var id: Int { rawValue }
        var label: String { "\(rawValue)s" }
        /// Kling O3 kostet ~0,126 $/s — dieselbe Formel wie bei Referenz-Videos.
        var credits: Int {
            CreditCosts.video(seconds: rawValue, hasReferenceVideo: true, resolution: .p480)
        }
    }

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    private static var submitURL: URL { URL(string: base + "/v1/seedance/reference-to-video")! }
    private static var statusURL: URL { URL(string: base + "/v1/seedance/status")! }

    /// Startet den Job und liefert die Task-ID.
    static func createTask(image: Data, prompt: String, seconds: Int, aspectRatio: String) async throws -> String {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let body: [String: Any] = [
            "provider": "wavespeed",
            "model": model,
            "prompt": prompt,
            // KEIN imagesField — siehe Kopfkommentar.
            "images": [image.base64EncodedString()],
            "duration": seconds,
            "aspectRatio": aspectRatio,
        ]

        let json = try await post(submitURL, body: body, timeout: 150)
        guard let data = json["data"] as? [String: Any],
              let taskID = data["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return taskID
    }

    enum State {
        case running
        case succeeded(URL)
        case failed(String)
    }

    static func fetchTask(id: String) async throws -> State {
        let json = try await post(statusURL, body: ["taskId": id, "provider": "wavespeed"], timeout: 40)
        let data = (json["data"] as? [String: Any]) ?? [:]
        let state = String(describing: data["state"] ?? "").lowercased()
        switch state {
        case "succeeded", "success", "completed":
            let raw = (data["videoUrl"] as? String) ?? (data["video_url"] as? String) ?? ""
            guard let url = URL(string: raw) else { return .failed("No video returned.") }
            return .succeeded(url)
        case "failed", "error":
            return .failed((data["failMsg"] as? String) ?? "The video failed.")
        default:
            return .running
        }
    }

    private static func post(_ url: URL, body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !BackendConfiguration.sharedSecret.isEmpty {
            request.setValue("Bearer \(BackendConfiguration.sharedSecret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SeedanceError.invalidResponse
        }
        return json
    }
}
