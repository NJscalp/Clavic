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
    /// Vercel-Deploy mit verbundenen APIs (FAL_KEY server-seitig).
    static let baseURL = "https://limitless-web-beryl.vercel.app"
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

struct SeedanceRequest {
    var prompt: String
    var referenceImages: [Data]
    var ratio: AspectRatio
    var resolution: Resolution
    var duration: Int
    var generateAudio: Bool
    var useFastModel: Bool
    var referenceVideoURLs: [String] = []
}

struct SeedanceTaskState {
    var status: GenerationStatus
    var videoURL: String?
    var failureReason: String?
}

struct SeedanceAPI {
    /// Aus Kompatibilität beibehalten (frühere fal-Key-Speicherung).
    static let apiKeyDefaultsKey = "fal.apiKey"

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
            return SeedanceTaskState(
                status: .failed,
                videoURL: nil,
                failureReason: data["failMsg"] as? String ?? "The generation failed."
            )
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
