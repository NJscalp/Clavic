//
//  SeedanceAPI.swift
//  Clavic
//
//  Spricht das gemeinsame Vercel-Backend (limitless-web) an, in dem der
//  FAL_KEY bereits server-seitig hinterlegt ist. Die App braucht daher
//  KEINEN eigenen API-Schlüssel.
//
//  Ablauf:
//   1. POST /v1/seedance/reference-to-video  → liefert response_url (Job)
//   2. POST /v1/seedance/status { responseUrl } → pollt bis succeeded/failed
//

import Foundation

/// Zentrale Backend-Konfiguration (gleiches Backend wie die Day-One-App).
enum BackendConfiguration {
    /// Railway-Deploy mit verbundenen APIs (Schlüssel liegen server-seitig).
    ///
    /// ACHTUNG beim Ändern: Diese Adresse ist fest einkompiliert. Jede bereits
    /// installierte App-Version spricht weiter mit der Adresse, mit der sie
    /// gebaut wurde — ein Serverwechsel erreicht diese Nutzer erst, wenn sie
    /// aus dem App Store aktualisiert haben.
    static let baseURL = "https://clavic-backend-production.up.railway.app"
    /// Optionales Shared Secret (nur falls APP_SHARED_SECRET im Backend gesetzt ist).
    static let sharedSecret = ""

    static var isConfigured: Bool { !baseURL.isEmpty }
}

enum SeedanceError: LocalizedError {
    case missingBackend
    case invalidResponse
    case server(String)
    case taskFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBackend:
            return "Backend is not configured."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .server(let message):
            return message
        case .taskFailed(let message):
            return message
        }
    }
}

/// Wandelt eine Backend-Fehlerantwort in eine nutzerfreundliche Meldung um.
/// Wichtig: Provider-/Kontostandsfehler unseres KI-Dienstes (z. B. kie.ai ohne
/// Guthaben → Antwort `kie_missing_task_id` / „Credits insufficient") dürfen NICHT
/// roh angezeigt werden – das wirkt wie ein Bug bzw. suggeriert fälschlich, der
/// Nutzer sei schuld. Stattdessen ein generischer „später erneut versuchen"-Hinweis.
func friendlyBackendError(json: [String: Any]?, statusCode: Int) -> String {
    let code = (json?["error"] as? String ?? json?["message"] as? String ?? "").lowercased()
    let detailMsg = ((json?["detail"] as? [String: Any])?["msg"] as? String ?? "").lowercased()
    let combined = code + " " + detailMsg
    if combined.contains("credit") || combined.contains("insufficient")
        || combined.contains("balance") || combined.contains("missing_task_id")
        || combined.contains("quota") || combined.contains("rate limit")
        || statusCode == 429 || statusCode >= 500 {
        return "The AI service is busy right now. Your credits were refunded — please try again in a few minutes."
    }
    if combined.contains("recognition") {
        return "This photo couldn't be processed. Please try a clear photo of a person."
    }
    if combined.contains("sensitive") || combined.contains("moderat")
        || combined.contains("policy") || combined.contains("nsfw") {
        return "This couldn't be created — it was flagged by the content filter. Try a different character, wording or photo."
    }
    if combined.contains("pixel count") || combined.contains("409600")
        || combined.contains("greater than or equal")
        || combined.contains("higher quality")
        || (combined.contains("quality") && combined.contains("low"))
        || (combined.contains("resolution") && combined.contains("video")) {
        return "Couldn't render this clip. Tip: Motion Control works best at 720p — set Resolution to 720p and try again."
    }
    if statusCode == 413 || combined.contains("too_large") || combined.contains("payload") {
        return "Photos are too large to upload. Try a closer crop or a smaller image, then try again."
    }
    if !code.isEmpty { return "Couldn't create your video right now. Please try again." }
    return "Server error (\(statusCode)). Please try again."
}

struct SeedanceRequest {
    var prompt: String
    var referenceImages: [Data]
    var ratio: AspectRatio
    var resolution: Resolution
    var duration: Int
    var generateAudio: Bool
    var useFastModel: Bool
    var referenceVideoURLs: [String] = []
    /// Vom Nutzer hochgeladenes Referenz-Video (Motion Studio), als Daten.
    var referenceVideosData: [Data] = []
    /// true → Kling 3.0 Motion Control statt Seedance reference-to-video
    /// (Charakter aus dem Bild, Bewegung + Szene aus dem Video).
    var kling: Bool = false
    /// Optionaler Modell-Override (z. B. "bytedance/seedance-2-mini" für günstige
    /// Action-Templates). Leer/nil = Backend-Default (seedance-2-fast).
    var model: String? = nil
}

struct SeedanceTaskState {
    var status: GenerationStatus
    var videoURL: String?
    var failureReason: String?
}

struct SeedanceAPI {
    /// Backend hält den Schlüssel – die App ist startklar, sobald das Backend konfiguriert ist.
    static var hasAPIKey: Bool { BackendConfiguration.isConfigured }

    private static var submitURL: URL {
        URL(string: BackendConfiguration.baseURL.trimmingTrailingSlashes() + "/v1/seedance/reference-to-video")!
    }

    private static var statusURL: URL {
        URL(string: BackendConfiguration.baseURL.trimmingTrailingSlashes() + "/v1/seedance/status")!
    }

    // MARK: - Request einreichen

    /// Reicht den Job über das Backend ein und gibt die `response_url` des fal-Jobs zurück
    /// (wird zum Pollen verwendet).
    static func createTask(_ request: SeedanceRequest) async throws -> String {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let images = request.referenceImages.map { $0.base64EncodedString() }
        var body: [String: Any] = [
            "prompt": request.prompt,
            "images": images,
            "resolution": request.resolution.rawValue,
            "duration": request.duration,
            "aspectRatio": falAspectRatio(request.ratio),
            "generateAudio": request.generateAudio
        ]
        if !request.referenceVideoURLs.isEmpty {
            body["videoUrls"] = request.referenceVideoURLs
        }

        let json = try await post(submitURL, body: body, timeout: 60)

        guard let data = json["data"] as? [String: Any] else {
            throw SeedanceError.invalidResponse
        }
        if let responseURL = data["responseUrl"] as? String, !responseURL.isEmpty {
            return responseURL
        }
        // Fallback: statusUrl ohne "/status" als Basis verwenden
        if let statusURLString = data["statusUrl"] as? String, !statusURLString.isEmpty {
            return statusURLString
        }
        throw SeedanceError.invalidResponse
    }

    // MARK: - Status abfragen

    /// `id` ist die `response_url` des fal-Jobs.
    static func fetchTask(id responseURL: String) async throws -> SeedanceTaskState {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let json = try await post(statusURL, body: ["responseUrl": responseURL], timeout: 30)
        guard let data = json["data"] as? [String: Any] else {
            throw SeedanceError.invalidResponse
        }

        let state = (data["state"] as? String ?? "").lowercased()
        switch state {
        case "queued":
            return SeedanceTaskState(status: .queued, videoURL: nil, failureReason: nil)
        case "running", "processing":
            return SeedanceTaskState(status: .running, videoURL: nil, failureReason: nil)
        case "succeeded":
            return SeedanceTaskState(status: .succeeded, videoURL: data["videoUrl"] as? String, failureReason: nil)
        default:
            let rawMsg = data["failMsg"] as? String ?? ""
            let friendly = rawMsg.isEmpty
                ? "The generation failed. Your credits were refunded — please try again."
                : friendlyBackendError(json: ["error": rawMsg], statusCode: 200)
            return SeedanceTaskState(status: .failed, videoURL: nil, failureReason: friendly)
        }
    }

    // MARK: - HTTP

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
        guard let http = response as? HTTPURLResponse else { throw SeedanceError.invalidResponse }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(http.statusCode) else {
            let message = json?["error"] as? String
                ?? json?["message"] as? String
                ?? "Server error (\(http.statusCode))."
            throw SeedanceError.server(message)
        }
        guard let json else { throw SeedanceError.invalidResponse }
        return json
    }

    private static func falAspectRatio(_ ratio: AspectRatio) -> String {
        ratio == .adaptive ? "auto" : ratio.rawValue
    }
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var copy = self
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }
}
