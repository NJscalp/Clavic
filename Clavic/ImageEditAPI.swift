//
//  ImageEditAPI.swift
//  Clavic
//
//  Spricht das gemeinsame Vercel-Backend (limitless-web) für die
//  Bild-Bearbeitung (Bild → Bild) an. Läuft über WaveSpeed AI
//  (Nano Banana 2, provider "wavespeed"). Der WAVESPEED_API_KEY liegt
//  server-seitig, die App braucht keinen eigenen Schlüssel.
//
//  Ablauf:
//   1. POST /v1/gpt-image/edit   → liefert taskId
//   2. POST /v1/gpt-image/status → pollt (provider wavespeed, taskId) bis succeeded/failed
//

import Foundation
import UIKit

struct ImageEditRequest {
    var prompt: String
    var referenceImages: [Data]
    /// "low" (1K), "medium" (2K), "high" (4K)
    var quality: String = "low"
    /// Gewünschtes Seitenverhältnis/Bildgröße (z. B. "1:1", "9:16", "auto").
    var aspectRatio: String = "auto"
    /// WaveSpeed-Modell-Slug — Standard überall: Nano Banana 2 (edit).
    var model: String = ImageEditAPI.defaultModel
}

struct ImageEditTaskState {
    var status: GenerationStatus
    var imageURL: String?
    var failureReason: String?
}

enum ImageEditAPI {
    /// ByteDance Seedream v5.0 Pro EDIT auf WaveSpeed AI — bis zu 10
    /// Referenzbilder, $0,045 @1k / $0,09 @2k.
    static let defaultModel = "bytedance/seedream-v5.0-pro/edit"
    /// Text→Bild (ohne Referenzfoto): Seedream v5.0 Pro.
    static let generateModel = "bytedance/seedream-v5.0-pro"
    static let displayName = "Seedream 5.0 Pro"

    /// NUR für den Chat (Clavic Image Edit): OpenAI GPT Image 2 auf WaveSpeed —
    /// beste Text-/Logo-Treue (~99 %). Preis hängt an `quality`, nicht an der
    /// Auflösung: low 0,02–0,04 $, medium 0,07–0,19 $, high 0,23–0,73 $.
    static let chatModel = "openai/gpt-image-2/edit"
    /// Text→Bild OHNE Referenzfoto, ebenfalls GPT Image 2. Live gegen
    /// WaveSpeed geprüft: `openai/gpt-image-2` und `…/generate` gibt es NICHT,
    /// der gültige Slug ist `…/text-to-image`.
    static let chatGenerateModel = "openai/gpt-image-2/text-to-image"
    static let chatDisplayName = "GPT Image 2"

    /// Google Nano Banana 2 (Gemini 3 Pro Image) auf WaveSpeed — fuer alles,
    /// wo die Person selbst UMGEBAUT wird: Pose, Haltung, Blickrichtung,
    /// Koerperdrehung.
    ///
    /// GEMESSEN am 06.08.2026, gleiches Foto, gleicher Prompt („change ONLY her
    /// body pose to a relaxed aesthetic editorial pose"):
    ///  - GPT Image 2  → Pose praktisch unveraendert, dafuer setzte es eine
    ///    Sonnenbrille auf und veraenderte das Gesicht.
    ///  - Nano Banana 2 → Kopf gedreht, Hand im Haar, anderes Standbein,
    ///    Gesicht und Kleid identisch.
    /// Darum laufen Pose-Anweisungen ueber dieses Modell.
    static let poseModel = "google/nano-banana-2/edit"
    static let poseDisplayName = "Nano Banana 2"

    static var hasAPIKey: Bool { BackendConfiguration.isConfigured }

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    private static var submitURL: URL { URL(string: base + "/v1/gpt-image/edit")! }
    private static var statusURL: URL { URL(string: base + "/v1/gpt-image/status")! }

    // MARK: - Request einreichen

    /// Reicht den Edit-Job über das Backend (WaveSpeed Nano Banana 2) ein und
    /// gibt die WaveSpeed-`taskId` zurück.
    static func createTask(_ request: ImageEditRequest) async throws -> String {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        // Immer neu komprimieren. Rohe Kamerabytes als Base64 sprengen sonst
        // leicht das ~4,5 MB Gateway-Limit — der Server antwortet dann mit 413
        // und die App zeigt nur „doesn't work".
        let images = request.referenceImages.compactMap { data -> String? in
            let jpeg = UIImage(data: data)?.jpegForAPIUpload(maxDimension: 1024, quality: 0.72)
                ?? UIImage(data: data)?.jpegData(compressionQuality: 0.7)
            guard let jpeg, !jpeg.isEmpty else { return nil }
            return jpeg.base64EncodedString()
        }
        if !request.referenceImages.isEmpty && images.isEmpty {
            throw SeedanceError.server("Couldn't prepare your photos for upload.")
        }
        // Ohne Referenzfoto → Text→Bild (Seedream v5.0 Pro); mit Foto → Edit.
        let model = request.model.isEmpty
            ? (images.isEmpty ? generateModel : defaultModel)
            : request.model
        // Qualität → Auflösung, modellabhängig:
        //  - Seedream v5 kennt NUR 1k/2k → low/medium = 1k, high = 2k
        //    ("4k" würde die API ablehnen).
        //  - GPT Image 2 kennt 1k/2k/4k UND ein eigenes `quality`-Feld
        //    (bestimmt den Preis) → low→1k, medium→2k, high→4k + quality.
        let isGPTImage = model.contains("gpt-image")
        let resolution: String
        switch request.quality.lowercased() {
        case "high": resolution = isGPTImage ? "4k" : "2k"
        case "medium": resolution = isGPTImage ? "2k" : "1k"
        default: resolution = "1k"
        }
        var body: [String: Any] = [
            "prompt": request.prompt,
            "resolution": resolution,
            "provider": "wavespeed",
            "model": model,
        ]
        if isGPTImage {
            body["quality"] = request.quality.lowercased()
        }
        if !images.isEmpty {
            body["images"] = images
            // nano-banana-2/edit erwartet die Referenzen als ARRAY-Feld `images`.
            body["imagesField"] = "images"
        }
        // "auto" = Modell entscheidet → Feld weglassen.
        if request.aspectRatio.lowercased() != "auto" && request.aspectRatio.lowercased() != "adaptive" {
            body["aspectRatio"] = request.aspectRatio
        }

        let json = try await post(submitURL, body: body, timeout: 60)
        guard let data = json["data"] as? [String: Any] else {
            throw SeedanceError.invalidResponse
        }
        if let taskID = (data["taskId"] as? String ?? data["task_id"] as? String), !taskID.isEmpty {
            return taskID
        }
        throw SeedanceError.invalidResponse
    }

    // MARK: - Status abfragen

    /// `id` ist die WaveSpeed-`taskId`.
    static func fetchTask(id taskID: String) async throws -> ImageEditTaskState {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }

        let json = try await post(statusURL, body: ["taskId": taskID, "provider": "wavespeed"], timeout: 30)
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
            let rawMsg = data["failMsg"] as? String ?? ""
            let friendly = rawMsg.isEmpty
                ? "Couldn't create this image. Your credits were refunded — please try again."
                : friendlyBackendError(json: ["error": rawMsg], statusCode: 200)
            return ImageEditTaskState(status: .failed, imageURL: nil, failureReason: friendly)
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
}
