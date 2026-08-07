//
//  TalkingPipeline.swift
//  Clavic
//
//  „Brainrot Character – reden lassen": erzeugt aus einem Charakter ein
//  sprechendes, lippensynchrones Video mit ECHTER Stimme (ElevenLabs).
//
//  Stufen (alles über das Clavic-Backend / kie + fal):
//    1. GPT Image 2  – Charakter in Szene (Bild)
//    2. Seedance r2v – Bild → kurzes Video (Charakter spricht in die Kamera)
//    3. ElevenLabs TTS (kie) – Text → Audio in der Charakter-Stimme
//    4. fal Lip-Sync – Mundbewegung des Videos passend zur Audiospur
//  → fertiges Video lokal gespeichert.
//
//  Schritt 2 + 3 laufen parallel (unabhängig), Schritt 4 kombiniert sie.
//

import Foundation
import AVFoundation

enum TalkingPipeline {
    private static var base: String {
        var s = BackendConfiguration.baseURL
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Seedance 2.0 Fast auf WAVESPEED für das Basis-Video (i2v) — Mini wurde
    /// aus allen Workflows entfernt.
    private static let seedanceModel = "bytedance/seedance-2.0-fast/image-to-video"
    /// MiniMax Speech-2.6-HD (WaveSpeed) — realistischste TTS dort.
    private static let ttsModel = "minimax/speech-2.6-hd"
    /// ByteDance LatentSync (WaveSpeed) — Video+Audio → lippensynchrones Video.
    private static let lipsyncModel = "bytedance/latentsync"

    /// Basis-Video-Prompt: Charakter spricht front-facing in die Kamera (Mund
    /// sichtbar → Lip-Sync greift sauber). Charakter-Konsistenz aus dem Bild.
    /// Nahaufnahme, frontal, Gesicht füllt das Bild, MUND deutlich & wiederholt
    /// auf/zu – so findet der Lip-Sync bei JEDEM Charakter einen klaren Mund.
    private static let talkVideoPrompt =
        "The exact same character from the image, its head and upper body large and centered in the frame, face clearly visible, looking straight into the camera and TALKING — the mouth clearly and repeatedly opening and closing as if speaking, lips/jaw visibly moving. Keep the character identical and consistent (same colors, design, face). Front-facing, smooth cartoon animation, no text, no watermark."

    static func run(imageEdit: String,
                    charImageJPEG: Data,
                    speech: String,
                    voice: String,
                    resolution: String,
                    onStage: @escaping (String) -> Void) async throws -> URL {

        // Charakterbild als Seedance-Input. Standard: gebündeltes (freigegebenes)
        // Asset DIREKT → keine OpenAI-Moderation, günstiger. NUR wenn der Nutzer
        // einen Änderungs-Prompt eingibt, läuft ein Nano-Banana-2-Edit (WaveSpeed).
        var charB64 = charImageJPEG.base64EncodedString()
        let edit = imageEdit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !edit.isEmpty {
            onStage("Updating the look…")
            let editedURL = try await submitKiePoll(
                submitPath: "/v1/gpt-image/edit",
                body: ["provider": "wavespeed",
                       "model": ImageEditAPI.defaultModel,
                       "imagesField": "images",
                       "prompt": "Keep the same character and its identity. \(edit). Same 3D glossy brainrot cartoon style, vertical 9:16, no text, no watermark.",
                       "images": [charB64], "resolution": "1k", "aspectRatio": "9:16"],
                statusPath: "/v1/gpt-image/status", statusBody: ["provider": "wavespeed"],
                resultKey: "imageUrl", timeout: 300)
            let editedImage = try await download(editedURL, ext: "jpg")
            charB64 = try Data(contentsOf: editedImage).base64EncodedString()
        }

        // Basis-Video (Seedance Mini via WaveSpeed) + Stimme (TTS) – parallel.
        onStage("Bringing them to life…")
        async let baseVideoURL = submitKiePoll(
            submitPath: "/v1/seedance/reference-to-video",
            body: ["provider": "wavespeed", "model": seedanceModel,
                   "prompt": talkVideoPrompt, "images": [charB64],
                   "resolution": "720p", "duration": 5, "aspectRatio": "9:16",
                   "generateAudio": false],
            statusPath: "/v1/seedance/status",
            statusBody: ["provider": "wavespeed"],
            resultKey: "videoUrl", timeout: 600)

        async let speechAudioURL = submitTTSPoll(text: speech, voice: voice)

        let (videoURL, audioURL) = try await (baseVideoURL, speechAudioURL)

        // Lip-Sync (kie/volcengine): Mund auf die Stimme synchronisieren. Klappt es
        // bei einem Charakter NICHT (kein klar erkennbarer Mund), Fallback: die
        // Stimme aufs Seedance-Talk-Video legen → der Mund bewegt sich generisch,
        // die echte Stimme spielt. So kommt für JEDEN Charakter ein vertontes,
        // redendes Video raus (statt Fehlschlag/„keine Stimme").
        onStage("Syncing the voice…")
        if let synced = try? await submitLipsyncPoll(videoUrl: videoURL, audioUrl: audioURL) {
            onStage("Finishing up…")
            return try await download(synced, ext: "mp4")
        }
        onStage("Finishing up…")
        let videoFile = try await download(videoURL, ext: "mp4")
        let audioFile = try await download(audioURL, ext: "mp3")
        return try await mergeAudio(video: videoFile, audio: audioFile)
    }

    /// Fallback: legt die Stimme (Audio) auf das Talk-Video (AVFoundation).
    private static func mergeAudio(video: URL, audio: URL) async throws -> URL {
        let comp = AVMutableComposition()
        let vAsset = AVURLAsset(url: video)
        let aAsset = AVURLAsset(url: audio)
        let vDur = try await vAsset.load(.duration)
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let srcV = try await vAsset.loadTracks(withMediaType: .video).first else {
            return video   // im Zweifel das stumme Video zurückgeben
        }
        try vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: srcV, at: .zero)
        if let aDur = try? await aAsset.load(.duration),
           let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
           let srcA = try? await aAsset.loadTracks(withMediaType: .audio).first {
            try? aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: min(aDur, vDur)), of: srcA, at: .zero)
        }
        let out = URL.temporaryDirectory.appending(path: "talkmerge-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            return video
        }
        try await export.export(to: out, as: .mp4)
        return out
    }

    // MARK: - Schritt-Helfer

    /// kie-Jobs (Bild / Seedance-Video): submit → data.taskId, status mit taskId.
    private static func submitKiePoll(submitPath: String, body: [String: Any],
                                      statusPath: String, statusBody: [String: Any],
                                      resultKey: String, timeout: Double) async throws -> String {
        let json = try await post(path: submitPath, body: body, timeout: 120)
        guard let taskID = (json["data"] as? [String: Any])?["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return try await poll(timeoutSeconds: timeout) {
            var sb = statusBody; sb["taskId"] = taskID
            let j = try await post(path: statusPath, body: sb, timeout: 30)
            return pollResult(j, resultKey: resultKey)
        }
    }

    /// MiniMax-TTS (WaveSpeed): submit { provider:wavespeed, model, input:{text, voice_id} }
    /// → data.taskId; status → audioUrl.
    private static func submitTTSPoll(text: String, voice: String) async throws -> String {
        let json = try await post(path: "/v1/gpt-image/edit",
                                  body: ["provider": "wavespeed", "model": ttsModel,
                                         "input": ["text": text, "voice_id": voice]], timeout: 60)
        guard let taskID = (json["data"] as? [String: Any])?["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return try await poll(timeoutSeconds: 300) {
            let j = try await post(path: "/v1/gpt-image/status",
                                   body: ["provider": "wavespeed", "taskId": taskID], timeout: 30)
            return pollResult(j, resultKey: "audioUrl")
        }
    }

    /// LatentSync (WaveSpeed): submit { provider:wavespeed, model, input:{video, audio} }
    /// → data.taskId; status → videoUrl.
    private static func submitLipsyncPoll(videoUrl: String, audioUrl: String) async throws -> String {
        let json = try await post(path: "/v1/seedance/reference-to-video",
                                  body: ["provider": "wavespeed", "model": lipsyncModel,
                                         "input": ["video": videoUrl, "audio": audioUrl]],
                                  timeout: 120)
        guard let taskID = (json["data"] as? [String: Any])?["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return try await poll(timeoutSeconds: 600) {
            let j = try await post(path: "/v1/seedance/status",
                                   body: ["provider": "wavespeed", "taskId": taskID], timeout: 30)
            return pollResult(j, resultKey: "videoUrl")
        }
    }

    // MARK: - Generische Helfer (Muster aus MusicVideoPipeline)

    private enum PollResult { case pending, done(String?), failed(String?) }

    private static func pollResult(_ json: [String: Any], resultKey: String) -> PollResult {
        let data = json["data"] as? [String: Any] ?? [:]
        let state = (data["state"] as? String ?? "").lowercased()
        switch state {
        case "succeeded", "success": return .done(data[resultKey] as? String)
        case "failed", "fail":       return .failed(data["failMsg"] as? String)
        default:                     return .pending
        }
    }

    private static func poll(timeoutSeconds: Double, _ check: () async throws -> PollResult) async throws -> String {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(5))
            switch try await check() {
            case .pending: continue
            case .done(let url):
                guard let url, !url.isEmpty else { throw SeedanceError.invalidResponse }
                return url
            case .failed(let msg):
                // Rohen Provider-Fehler (z. B. OpenAI-Moderation) nie ungefiltert
                // zeigen → freundlich übersetzen.
                let friendly = (msg?.isEmpty == false)
                    ? friendlyBackendError(json: ["error": msg!], statusCode: 200)
                    : "The generation failed. Your credits were refunded — please try again."
                throw SeedanceError.taskFailed(friendly)
            }
        }
        throw SeedanceError.taskFailed("Timed out while creating your video.")
    }

    private static func download(_ remote: String, ext: String) async throws -> URL {
        guard let url = URL(string: remote) else { throw SeedanceError.invalidResponse }
        let (temp, _) = try await URLSession.shared.download(from: url)
        let dest = URL.temporaryDirectory.appending(path: "talk-\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }

    private static func post(path: String, body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard BackendConfiguration.isConfigured else { throw SeedanceError.missingBackend }
        var request = URLRequest(url: URL(string: base + path)!)
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
