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

    /// Reicht den Job über das Backend ein (Provider WAVESPEED — alle Modelle
    /// laufen über WaveSpeed) und gibt die `taskId` zurück.
    /// • Bild→Video: Seedance 2.0 Fast (WaveSpeed)
    /// • Referenz-Video / Motion Control: Kling Omni 3 (O3) VIDEO-EDIT —
    ///   Person aus dem Bild ersetzt die Person im Video, Bewegung, Timing,
    ///   Szene und Original-Ton bleiben erhalten (keep_original_sound = default).
    static func createTask(_ request: SeedanceRequest) async throws -> String {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let images = request.referenceImages.map { $0.base64EncodedString() }
        let hasRefVideo = !request.referenceVideoURLs.isEmpty || !request.referenceVideosData.isEmpty

        var body: [String: Any] = ["provider": "wavespeed", "images": images]

        if request.model?.contains("gemini-omni-flash") == true {
            // Google Gemini Omni Flash (reference-to-video): Bilder (Pflicht) +
            // optionales Referenz-Video + Prompt, Dauer 1-8 s.
            body["model"] = "google/gemini-omni-flash/reference-to-video"
            body["prompt"] = request.prompt
            body["imagesField"] = "images"
            body["aspectRatio"] = "9:16"
            body["duration"] = min(8, max(3, request.duration))
            if !request.referenceVideosData.isEmpty {
                body["videosField"] = "videos"
                body["videos"] = request.referenceVideosData.map { $0.base64EncodedString() }
            } else if !request.referenceVideoURLs.isEmpty {
                body["videosField"] = "videos"
                body["videoUrls"] = request.referenceVideoURLs
            }
        } else if request.kling || hasRefVideo {
            // Referenz-Video / Motion Control: Kling O3 (Omni 3) VIDEO-EDIT.
            // Schema: prompt (Pflicht) + video (Pflicht) + images (max 4).
            // Nur die Person wird getauscht; Bewegung, Kamera, Szene und der
            // Original-Ton des Referenzvideos bleiben erhalten. Kein
            // resolution-Feld — O3 kennt es nicht.
            body["model"] = "kwaivgi/kling-video-o3-std/video-edit"
            let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            body["prompt"] = prompt.isEmpty ? Self.defaultSwapPrompt : prompt
            body["imagesField"] = "images"
            if !request.referenceVideoURLs.isEmpty {
                body["videoUrls"] = request.referenceVideoURLs
            }
            if !request.referenceVideosData.isEmpty {
                body["videos"] = request.referenceVideosData.map { $0.base64EncodedString() }
            }
        } else {
            // Bild→Video: Seedance 2.0 Fast auf WaveSpeed.
            body["model"] = "bytedance/seedance-2.0-fast/image-to-video"
            body["prompt"] = request.prompt
            body["resolution"] = request.resolution.rawValue
            body["duration"] = max(request.duration, 4)   // WaveSpeed-Minimum 4 s
            body["aspectRatio"] = kieAspectRatio(request.ratio)
            body["generateAudio"] = request.generateAudio
        }

        // Upload + Job-Erstellung können etwas dauern.
        let json = try await post(submitURL, body: body, timeout: 120)
        guard let data = json["data"] as? [String: Any] else {
            throw SeedanceError.invalidResponse
        }
        if let taskID = data["taskId"] as? String, !taskID.isEmpty {
            return taskID
        }
        throw SeedanceError.invalidResponse
    }

    /// Standard-Prompt für Kling O3 video-edit, wenn das Template/Studio keinen
    /// eigenen Prompt mitgibt (z. B. der Kling-Motion-Flow: nur Foto + Video).
    private static let defaultSwapPrompt = "Replace the main person in the video with the person from the image. Keep exactly the same movements, body motion, timing, camera work, background and scene from the video. Preserve the exact identity, face and hair of the person from the image. Photorealistic, natural, looks like real footage, no morphing, no distortion. No text, no watermark."

    // MARK: - Status abfragen

    /// `id` ist die WaveSpeed-`taskId` (Alt-Tasks mit "ws:"-Präfix werden toleriert).
    static func fetchTask(id taskID: String) async throws -> SeedanceTaskState {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let cleanID = taskID.hasPrefix("ws:") ? String(taskID.dropFirst(3)) : taskID
        let json = try await post(statusURL,
                                  body: ["provider": "wavespeed", "taskId": cleanID],
                                  timeout: 30)
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
            // Rohen Provider-Fehler (z. B. „video pixel count … >= 409600")
            // nie ungefiltert zeigen → in eine verständliche Meldung übersetzen.
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
            throw SeedanceError.server(friendlyBackendError(json: json, statusCode: http.statusCode))
        }
        guard let json else { throw SeedanceError.invalidResponse }
        return json
    }

    private static func kieAspectRatio(_ ratio: AspectRatio) -> String {
        ratio == .adaptive ? "9:16" : ratio.rawValue
    }
}
