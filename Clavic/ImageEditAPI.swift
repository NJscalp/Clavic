//
//  ImageEditAPI.swift
//  Clavic
//
//  Spricht das gemeinsame Vercel-Backend (limitless-web) für die
//  Bild-Bearbeitung (Bild → Bild) an. Es wird kie.ai "Nano Banana 2"
//  genutzt (provider "kie"); der KIE_API_KEY liegt server-seitig, die App
//  braucht keinen eigenen Schlüssel. Günstigste Stufe (1K, jpg).
//
//  Ablauf (analog zu Seedance):
//   1. POST /v1/gpt-image/edit   → liefert responseUrl (= kie taskId)
//   2. POST /v1/gpt-image/status → pollt bis succeeded/failed
//

import Foundation

struct ImageEditRequest {
    var prompt: String
    var referenceImages: [Data]
    /// "low" (günstigste), "medium", "high"
    var quality: String = "low"
}

struct ImageEditTaskState {
    var status: GenerationStatus
    var imageURL: String?
    var failureReason: String?
}

enum ImageEditAPI {
    static var hasAPIKey: Bool { BackendConfiguration.isConfigured }

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    private static var submitURL: URL { URL(string: base + "/v1/gpt-image/edit")! }
    private static var statusURL: URL { URL(string: base + "/v1/gpt-image/status")! }

    // MARK: - Request einreichen

    /// Reicht den Edit-Job über das Backend ein und gibt die `responseUrl` zurück.
    static func createTask(_ request: ImageEditRequest) async throws -> String {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let images = request.referenceImages.map { $0.base64EncodedString() }
        let body: [String: Any] = [
            "prompt": request.prompt,
            "images": images,
            "provider": "kie"
        ]

        let json = try await post(submitURL, body: body, timeout: 60)
        guard let data = json["data"] as? [String: Any] else {
            throw SeedanceError.invalidResponse
        }
        if let responseURL = data["responseUrl"] as? String, !responseURL.isEmpty {
            return responseURL
        }
        if let statusURLString = data["statusUrl"] as? String, !statusURLString.isEmpty {
            return statusURLString
        }
        throw SeedanceError.invalidResponse
    }

    // MARK: - Status abfragen

    /// `id` ist die `responseUrl` des fal-Jobs.
    static func fetchTask(id responseURL: String) async throws -> ImageEditTaskState {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let json = try await post(statusURL, body: ["responseUrl": responseURL, "provider": "kie"], timeout: 30)
        guard let data = json["data"] as? [String: Any] else {
            throw SeedanceError.invalidResponse
        }

        let state = (data["state"] as? String ?? "").lowercased()
        switch state {
        case "queued":
            return ImageEditTaskState(status: .queued, imageURL: nil, failureReason: nil)
        case "running", "processing":
            return ImageEditTaskState(status: .running, imageURL: nil, failureReason: nil)
        case "succeeded":
            return ImageEditTaskState(status: .succeeded, imageURL: data["imageUrl"] as? String, failureReason: nil)
        default:
            return ImageEditTaskState(
                status: .failed,
                imageURL: nil,
                failureReason: data["failMsg"] as? String ?? "The image edit failed."
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
