//
//  UpscaleAPI.swift
//  Clavic
//
//  Image- & Video-Upscaling über das gemeinsame Vercel-Backend mit
//  kie.ai Topaz (KIE_API_KEY liegt server-seitig). Die App lädt die
//  Datei als Base64 hoch.
//
//  Ablauf:
//   1. POST /v1/upscale/submit  { type, image|video, factor, provider } → responseUrl (= kie taskId)
//   2. POST /v1/upscale/status  { type, responseUrl, provider }         → pollt
//

import Foundation

enum UpscaleAPI {
    static var hasAPIKey: Bool { BackendConfiguration.isConfigured }

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    private static var submitURL: URL { URL(string: base + "/v1/upscale/submit")! }
    private static var statusURL: URL { URL(string: base + "/v1/upscale/status")! }

    /// Reicht einen Upscale-Job ein und gibt die `responseUrl` (Poll-Handle) zurück.
    static func createTask(type: String, fileData: Data, factor: Int = 2) async throws -> String {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let isVideo = type == "video"
        var body: [String: Any] = [
            "type": isVideo ? "video" : "image",
            "factor": factor,
            "provider": "kie"
        ]
        body[isVideo ? "video" : "image"] = fileData.base64EncodedString()

        let json = try await post(submitURL, body: body, timeout: 120)
        guard let data = json["data"] as? [String: Any] else { throw SeedanceError.invalidResponse }
        if let responseURL = data["responseUrl"] as? String, !responseURL.isEmpty {
            return responseURL
        }
        if let statusURLString = data["statusUrl"] as? String, !statusURLString.isEmpty {
            return statusURLString
        }
        throw SeedanceError.invalidResponse
    }

    /// `id` ist die `responseUrl` des fal-Jobs. Liefert Status + Ergebnis-URL.
    static func fetchTask(id responseURL: String, type: String) async throws -> SeedanceTaskState {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let json = try await post(statusURL, body: ["type": type, "responseUrl": responseURL, "provider": "kie"], timeout: 30)
        guard let data = json["data"] as? [String: Any] else { throw SeedanceError.invalidResponse }

        let state = (data["state"] as? String ?? "").lowercased()
        switch state {
        case "queued":
            return SeedanceTaskState(status: .queued, videoURL: nil, failureReason: nil)
        case "running", "processing":
            return SeedanceTaskState(status: .running, videoURL: nil, failureReason: nil)
        case "succeeded":
            return SeedanceTaskState(status: .succeeded, videoURL: data["resultUrl"] as? String, failureReason: nil)
        default:
            return SeedanceTaskState(
                status: .failed,
                videoURL: nil,
                failureReason: data["failMsg"] as? String ?? "The upscale failed."
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
}
