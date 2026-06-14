//
//  KieSeedanceAPI.swift
//  Clavic
//
//  Spricht denselben Vercel-Backend-Endpoint wie SeedanceAPI an, aber über
//  den Provider "kie" (kie.ai Jobs-API). Der KIE_API_KEY liegt server-seitig.
//  Wird aktuell für den Lego-Trend genutzt.
//
//  Ablauf:
//   1. POST /v1/seedance/reference-to-video { provider: "kie", … } → taskId
//   2. POST /v1/seedance/status            { provider: "kie", taskId } → pollt
//

import Foundation

enum KieSeedanceAPI {
    static var hasAPIKey: Bool { BackendConfiguration.isConfigured }

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    private static var submitURL: URL { URL(string: base + "/v1/seedance/reference-to-video")! }
    private static var statusURL: URL { URL(string: base + "/v1/seedance/status")! }

    // MARK: - Request einreichen

    /// Reicht den Job über das Backend (Provider kie) ein und gibt die kie-`taskId` zurück.
    static func createTask(_ request: SeedanceRequest) async throws -> String {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let images = request.referenceImages.map { $0.base64EncodedString() }
        var body: [String: Any] = [
            "provider": "kie",
            "prompt": request.prompt,
            "images": images,
            "resolution": request.resolution.rawValue,
            "duration": request.duration,
            "aspectRatio": kieAspectRatio(request.ratio),
            "generateAudio": request.generateAudio,
            "fast": request.useFastModel
        ]
        if !request.referenceVideoURLs.isEmpty {
            body["videoUrls"] = request.referenceVideoURLs
        }

        // Upload + Job-Erstellung können bei kie etwas dauern.
        let json = try await post(submitURL, body: body, timeout: 120)
        guard let data = json["data"] as? [String: Any] else {
            throw SeedanceError.invalidResponse
        }
        if let taskID = data["taskId"] as? String, !taskID.isEmpty {
            return taskID
        }
        throw SeedanceError.invalidResponse
    }

    // MARK: - Status abfragen

    /// `id` ist die kie-`taskId`.
    static func fetchTask(id taskID: String) async throws -> SeedanceTaskState {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let json = try await post(statusURL, body: ["provider": "kie", "taskId": taskID], timeout: 30)
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

    private static func kieAspectRatio(_ ratio: AspectRatio) -> String {
        ratio == .adaptive ? "9:16" : ratio.rawValue
    }
}
