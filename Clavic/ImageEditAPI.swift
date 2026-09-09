//
//  ImageEditAPI.swift
//  Clavic
//
//  Spricht das gemeinsame Vercel-Backend (limitless-web) für die
//  Bild-Bearbeitung (Bild → Bild) an, immer über provider "wavespeed".
//  Der WAVESPEED_API_KEY liegt server-seitig, die App braucht keinen
//  eigenen Schlüssel.
//
//  WELCHES Modell, entscheidet der Aufrufer über `ImageEditRequest.model`:
//    • defaultModel / soloShotModel → Seedream 5.0 Pro Edit (Standard)
//    • chatModel                    → GPT Image 2 (Chat, beste Texttreue)
//    • poseModel                    → Nano Banana 2 (Pose/Haltung)
//  Die Konstanten unten sind die eine Quelle der Wahrheit dafür.
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
    /// One Shot arbeitet mit sorgfaeltig getrennten Referenzen. Fuer
    /// Gesichts-, Stoff- und Raumdetails duerfen sie weniger stark verkleinert
    /// werden als normale Chat-Anhaenge; das harte Byte-Limit bleibt bestehen.
    var highFidelityReferences: Bool = false
}

struct ImageEditTaskState {
    var status: GenerationStatus
    var imageURL: String?
    var failureReason: String?
}

enum ImageEditAPI {
    /// EINHEITLICHES MODELL (Stand 09.09.2026): OpenAI GPT Image 2.5 Sunburst
    /// auf WaveSpeed — `openai/gpt-image-2.5-sunburst/edit`.
    /// Gleiche Request-Struktur wie GPT Image 2, laut WaveSpeed ist die
    /// Migration ein reiner Modell-ID-Tausch. Preis medium ~$0,024/1K, also
    /// unter der Haelfte der GPT-Image-2-Stufe. Sunburst ist die Variante fuer
    /// Edit-Praezision (die andere, Flare, ist auf Tempo ausgelegt).
    static let defaultModel = "openai/gpt-image-2.5-sunburst/edit"
    static let generateModel = "openai/gpt-image-2.5-sunburst/text-to-image"
    static let displayName = "GPT Image 2.5 Sunburst"

    static let chatModel = "openai/gpt-image-2.5-sunburst/edit"
    static let chatGenerateModel = "openai/gpt-image-2.5-sunburst/text-to-image"
    static let chatDisplayName = "GPT Image 2.5 Sunburst"

    static let soloShotModel = "openai/gpt-image-2.5-sunburst/edit"
    static let soloShotDisplayName = "GPT Image 2.5 Sunburst"

    /// ACHTUNG: hier lief bis 09.09.2026 bewusst Nano Banana 2. Messung vom
    /// 06.08.2026 (gleiches Foto, gleicher Prompt): GPT Image 2 liess die Pose
    /// unveraendert, setzte eine Sonnenbrille auf und VERAENDERTE DAS GESICHT;
    /// Nano Banana 2 drehte die Pose und hielt Gesicht und Kleid identisch.
    /// Sunburst ist ein anderes Modell mit besserer Edit-Kontrolle, aber fuer
    /// Pose-Prompts noch NICHT gegengeprueft. Vor Release testen.
    static let poseModel = "openai/gpt-image-2.5-sunburst/edit"
    static let poseDisplayName = "GPT Image 2.5 Sunburst"

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

        let model = request.model.isEmpty
            ? (request.referenceImages.isEmpty ? generateModel : defaultModel)
            : request.model

        // Immer neu komprimieren. Rohe Kamerabytes als Base64 sprengen sonst
        // leicht das ~4,5 MB Gateway-Limit — der Server antwortet dann mit 413
        // und die App zeigt nur „doesn't work".
        // Keep the complete JSON body below the gateway limit even when One
        // Shot adds a fourth, tight face/hair identity reference.
        let referenceByteBudget = min(
            850_000,
            max(450_000, 2_900_000 / max(request.referenceImages.count, 1))
        )
        let images = request.referenceImages.compactMap { data -> String? in
            let jpeg = encodedReferenceImage(
                data,
                highFidelity: request.highFidelityReferences,
                byteBudget: referenceByteBudget
            )
            guard let jpeg, !jpeg.isEmpty else { return nil }
            return jpeg.base64EncodedString()
        }
        if !request.referenceImages.isEmpty && images.isEmpty {
            throw SeedanceError.server("Couldn't prepare your photos for upload.")
        }
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

    /// Einmalige Upload-Kodierung. Im High-Fidelity-Pfad wird das gemeinsame
    /// Byte-Budget dynamisch auf alle One-Shot-Referenzen verteilt. So bleibt
    /// auch die zusaetzliche Gesicht-/Haar-Referenz nach Base64 unter dem
    /// Gateway-Limit, ohne Gesicht und Raum auf 1024 px zu zerdruecken.
    private static func encodedReferenceImage(
        _ data: Data,
        highFidelity: Bool,
        byteBudget: Int
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        guard highFidelity else {
            return image.jpegForAPIUpload(maxDimension: 1024, quality: 0.72)
                ?? image.jpegData(compressionQuality: 0.7)
        }

        let attempts: [(CGFloat, CGFloat)] = [
            (1600, 0.86), (1600, 0.78), (1440, 0.76),
            (1280, 0.72), (1120, 0.66), (960, 0.60),
        ]
        for (dimension, quality) in attempts {
            if let candidate = image.jpegForAPIUpload(
                maxDimension: dimension,
                quality: quality
            ),
               candidate.count <= byteBudget {
                return candidate
            }
        }
        return image.jpegForAPIUpload(maxDimension: 768, quality: 0.52)
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
