//
//  UpscaleAPI.swift
//  Clavic
//
//  Image- & Video-Upscaling über das gemeinsame Vercel-Backend mit
//  WaveSpeed (WAVESPEED_API_KEY liegt server-seitig). Die App lädt die
//  Datei als Base64 hoch; das Backend lädt sie zu WaveSpeed und mappt sie
//  auf das `image`/`video`-Feld der Upscaler-Modelle.
//
//  Ablauf:
//   1. POST /v1/gpt-image/edit bzw. /v1/seedance/reference-to-video
//      { provider:"wavespeed", model, images|videos } → taskId
//   2. …/status { provider:"wavespeed", taskId } → pollt
//

import Foundation

enum UpscaleAPI {
    static var hasAPIKey: Bool { BackendConfiguration.isConfigured }

    /// WaveSpeed-Upscaler-Modelle.
    private static let imageModel = "wavespeed-ai/image-upscaler"
    private static let videoModel = "wavespeed-ai/video-upscaler"

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    /// Reicht einen Upscale-Job ein und gibt die `taskId` (Poll-Handle) zurück.
    static func createTask(type: String, fileData: Data, factor: Int = 2) async throws -> String {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let isVideo = type == "video"
        var body: [String: Any] = [
            "provider": "wavespeed",
            "model": isVideo ? videoModel : imageModel,
        ]
        if isVideo {
            body["videos"] = [fileData.base64EncodedString()]
        } else {
            body["images"] = [fileData.base64EncodedString()]
        }
        let path = isVideo ? "/v1/seedance/reference-to-video" : "/v1/gpt-image/edit"
        let json = try await post(URL(string: base + path)!, body: body, timeout: 120)
        guard let data = json["data"] as? [String: Any] else { throw SeedanceError.invalidResponse }
        if let taskID = (data["taskId"] as? String ?? data["responseUrl"] as? String), !taskID.isEmpty {
            return taskID
        }
        throw SeedanceError.invalidResponse
    }

    /// `id` ist die WaveSpeed-`taskId`. Liefert Status + Ergebnis-URL.
    static func fetchTask(id responseURL: String, type: String) async throws -> SeedanceTaskState {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let isVideo = type == "video"
        let path = isVideo ? "/v1/seedance/status" : "/v1/gpt-image/status"
        let json = try await post(URL(string: base + path)!,
                                  body: ["provider": "wavespeed", "taskId": responseURL], timeout: 30)
        guard let data = json["data"] as? [String: Any] else { throw SeedanceError.invalidResponse }

        let state = (data["state"] as? String ?? "").lowercased()
        switch state {
        case "queued":
            return SeedanceTaskState(status: .queued, videoURL: nil, failureReason: nil)
        case "running", "processing":
            return SeedanceTaskState(status: .running, videoURL: nil, failureReason: nil)
        case "succeeded":
            let url = (data["videoUrl"] as? String) ?? (data["imageUrl"] as? String) ?? (data["outputUrl"] as? String)
            return SeedanceTaskState(status: .succeeded, videoURL: url, failureReason: nil)
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
