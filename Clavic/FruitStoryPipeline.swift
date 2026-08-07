//
//  FruitStoryPipeline.swift
//  Clavic
//
//  "AI Fruit Story" – mehrstufige Pipeline, nachgebaut nach Zyvos Template:
//
//   1. PLAN     – Backend-Planner (Claude) schreibt aus Preset + Cast + Stil
//                 jedes Mal ein NEUES szenenweises Drehbuch (Titel, Bild-Prompt,
//                 Dialog, Action je Szene). → immer eine neue Story.
//   2. KEYFRAME – GPT Image 2 erzeugt pro Szene das Standbild. Die gewählten
//                 Frucht-Charaktere kommen als Referenzbilder mit (Identität
//                 bleibt gleich); ab Szene 2 zusätzlich der vorige Frame als
//                 Kontinuitäts-Referenz (gleiche Welt/Lichtstimmung).
//   3. ANIMATE  – Veo 3.1 animiert jeden Keyframe zu einem ~8-s-Clip, in dem
//                 die Früchte ihren Dialog WIRKLICH sprechen (Lippensync + Ton).
//   4. MERGE    – alle Clips werden lokal mit ihrem Ton aneinandergehängt.
//
//  Bild über kie.ai (GPT Image 2), Video über kie.ai (Veo 3.1) – kein fal.
//

import Foundation
import AVFoundation
import UIKit

enum FruitStoryPipeline {

    // MARK: - Eingabe

    /// Konfiguration, die CreateView als JSON in `project.prompt` ablegt.
    struct Config: Decodable {
        var presetId: String
        var storyIdea: String       // bei Custom die Nutzereingabe, sonst Preset-Seed
        var styleId: String
        var sceneCount: Int
        var characters: [String]    // Cast-Namen, parallel zu den Referenzbildern
    }

    /// Eine vom Planner gelieferte Szene. (Codable → im Checkpoint speicherbar,
    /// damit ein Resume DIESELBE Story weiterführt.)
    private struct PlannedScene: Codable {
        var title: String
        var characters: [String]
        var image: String
        var dialogue: String
        var action: String
    }

    // MARK: - Einstieg

    /// Erzeugt das fertige Fruit-Story-Video und liefert die lokale Datei-URL.
    /// - characterImages: Referenzbilder der gewählten Charaktere, in derselben
    ///   Reihenfolge wie `config.characters`.
    static func run(config: Config,
                    characterImages: [Data],
                    resolution: String,
                    projectID: UUID,
                    onStage: @escaping (String) -> Void = { _ in }) async throws -> URL {

        let style = FruitStoryCatalog.style(id: config.styleId) ?? FruitStoryCatalog.styles[0]

        // Name → Referenzbild (für die szenenweise Charakterauswahl).
        var imageForName: [String: Data] = [:]
        for (i, name) in config.characters.enumerated() where i < characterImages.count {
            imageForName[name.lowercased()] = characterImages[i]
        }

        // 1) Drehbuch: aus dem Checkpoint laden (Resume = DIESELBE Story) oder neu
        //    planen (Claude) und im Checkpoint sichern.
        onStage("Writing your story")
        let scenes: [PlannedScene]
        if let saved = Checkpoint.loadPlan(projectID),
           let decoded = try? JSONDecoder().decode([PlannedScene].self, from: Data(saved.utf8)),
           !decoded.isEmpty {
            scenes = decoded
        } else {
            scenes = try await planScenes(config: config)
            guard !scenes.isEmpty else { throw SeedanceError.taskFailed("The story planner returned no scenes.") }
            if let data = try? JSONEncoder().encode(scenes) {
                Checkpoint.savePlan(projectID, String(decoding: data, as: UTF8.self))
            }
        }
        let count = scenes.count

        // 2) Keyframes SEQUENZIELL (Welt-/Lichtkontinuität). Fertige werden im
        //    Checkpoint gehalten → beim Resume nur fehlende neu erzeugen.
        onStage("Designing the scenes")
        var keyframes: [Data] = []
        var previousFrame: Data? = nil
        for (i, scene) in scenes.enumerated() {
            let kfName = "kf_\(i).jpg"
            if let cached = Checkpoint.load(projectID, kfName) {
                keyframes.append(cached); previousFrame = cached; continue
            }
            var refs: [Data] = []
            for n in scene.characters {
                if let img = imageForName[n.lowercased()] { refs.append(img) }
            }
            if refs.isEmpty { refs = characterImages }
            if let prev = previousFrame { refs.append(prev) }

            let prompt = FruitStoryCatalog.keyframePrompt(
                sceneImage: scene.image,
                characterNames: scene.characters,
                style: style,
                hasContinuityReference: previousFrame != nil)

            let url = try await makeKeyframe(prompt: prompt, images: refs)
            let data = try await downloadData(url)
            Checkpoint.save(projectID, kfName, data)
            keyframes.append(data)
            previousFrame = data
        }

        // 3) Animieren (Veo 3.1, sprechende Früchte), parallel – aber NUR Szenen,
        //    deren Clip noch nicht im Checkpoint liegt. Jeder fertige Clip wird
        //    sofort gespeichert → bei Abbruch geht nichts Bezahltes verloren.
        let doneBefore = (0..<count).filter { Checkpoint.exists(projectID, "seg_\($0).mp4") }.count
        onStage("Bringing it to life \(doneBefore)/\(count)")
        try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 0..<count where !Checkpoint.exists(projectID, "seg_\(i).mp4") {
                let frame = keyframes[i]
                let animPrompt = FruitStoryCatalog.animationPrompt(
                    action: scenes[i].action, dialogue: scenes[i].dialogue, style: style)
                let res = resolution
                group.addTask {
                    let url = try await animate(imageData: frame, prompt: animPrompt, resolution: res)
                    let local = try await downloadToFile(url, ext: "mp4")
                    Checkpoint.adopt(projectID, "seg_\(i).mp4", from: local)
                    try? FileManager.default.removeItem(at: local)
                    return i
                }
            }
            var done = doneBefore
            for try await _ in group { done += 1; onStage("Bringing it to life \(done)/\(count)") }
        }
        // Alle Clips müssen jetzt vorhanden sein.
        let segURLs = (0..<count).map { Checkpoint.url(projectID, "seg_\($0).mp4") }
        guard segURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw SeedanceError.taskFailed("A scene failed to animate.")
        }

        // 4) Clips in Reihenfolge mit eigenem Ton zusammenfügen.
        onStage("Finishing your video")
        let merged = try await concatKeepingAudio(segURLs)
        return merged
    }

    // MARK: - Schritt 1: Planner (Claude über Backend)

    private static func planScenes(config: Config) async throws -> [PlannedScene] {
        // Cast mit Rollen für den Planner aufbereiten.
        let cast: [[String: String]] = config.characters.map { name in
            let role = FruitStoryCatalog.characters.first { $0.name == name }?.role ?? "supporting character"
            return ["name": name, "role": role]
        }
        let body: [String: Any] = [
            "presetId": config.presetId,
            "storyIdea": config.storyIdea,
            "style": FruitStoryCatalog.style(id: config.styleId)?.label ?? "Cinematic 3D",
            "sceneCount": config.sceneCount,
            "characters": cast,
        ]
        let json = try await post(path: "/v1/fruit-story/plan", body: body, timeout: 120)
        guard let data = json["data"] as? [String: Any],
              let rawScenes = data["scenes"] as? [[String: Any]] else {
            throw SeedanceError.invalidResponse
        }
        return rawScenes.map { s in
            PlannedScene(
                title: s["title"] as? String ?? "",
                characters: (s["characters"] as? [String]) ?? [],
                image: s["image"] as? String ?? "",
                dialogue: s["dialogue"] as? String ?? "",
                action: s["action"] as? String ?? "")
        }.filter { !$0.image.isEmpty }
    }

    // MARK: - Schritt 2: Keyframe (GPT Image 2 über kie)

    private static func makeKeyframe(prompt: String, images: [Data]) async throws -> String {
        let req = ImageEditRequest(prompt: prompt, referenceImages: images,
                                   quality: "low", aspectRatio: "9:16",
                                   model: ImageEditAPI.defaultModel)
        let taskID = try await ImageEditAPI.createTask(req)
        return try await poll(timeoutSeconds: 600) {
            let state = try await ImageEditAPI.fetchTask(id: taskID)
            switch state.status {
            case .succeeded: return .done(state.imageURL)
            case .failed:    return .failed(state.failureReason)
            default:         return .pending
            }
        }
    }

    // MARK: - Schritt 3: Szene animieren (Veo 3.1 image-to-video + Dialog-Ton)

    private static func animate(imageData: Data, prompt: String, resolution: String) async throws -> String {
        // Veo unterstützt 720p/1080p – 480p auf 720p anheben.
        let veoRes = resolution.lowercased() == "1080p" ? "1080p" : "720p"
        let body: [String: Any] = [
            "provider": "kie",   // läuft über die seedance-Route (kie-Block)
            "veo": true,         // → Veo-3.1-Zweig (sprechende Früchte)
            "prompt": prompt,
            "images": [imageData.base64EncodedString()],
            "aspectRatio": "9:16",
            "resolution": veoRes,
            "duration": FruitStoryCatalog.sceneDuration,
        ]
        let json = try await post(path: "/v1/fruit-story/animate", body: body, timeout: 120)
        guard let taskID = (json["data"] as? [String: Any])?["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return try await poll(timeoutSeconds: 900) {
            let json = try await post(path: "/v1/fruit-story/status",
                                      body: ["taskId": taskID, "provider": "kie", "veo": true], timeout: 30)
            let data = json["data"] as? [String: Any] ?? [:]
            switch (data["state"] as? String ?? "").lowercased() {
            case "succeeded": return .done(data["videoUrl"] as? String)
            case "failed":    return .failed(data["failMsg"] as? String)
            default:          return .pending
            }
        }
    }

    // MARK: - Schritt 4: Clips zusammenfügen (Ton der Segmente behalten)

    private static func concatKeepingAudio(_ files: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw SeedanceError.taskFailed("Could not build the video.") }

        var cursor = CMTime.zero
        for file in files {
            let asset = AVURLAsset(url: file)
            let dur = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: dur)
            if let v = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(range, of: v, at: cursor)
            }
            if let a = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: a, at: cursor)
            }
            cursor = cursor + dur
        }

        if let url = await export(composition, preset: AVAssetExportPresetHighestQuality) { return url }
        throw SeedanceError.taskFailed("Could not export the video.")
    }

    private static func export(_ composition: AVMutableComposition, preset: String) async -> URL? {
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { return nil }
        let outURL = URL.temporaryDirectory.appending(path: "fruitstory-\(UUID().uuidString).mp4")
        session.shouldOptimizeForNetworkUse = true
        do {
            try await session.export(to: outURL, as: .mp4)
            return outURL
        } catch {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
    }

    // MARK: - Hilfen (analog BrainrotBuildPipeline)

    private enum PollResult { case pending, done(String?), failed(String?) }

    private static func poll(timeoutSeconds: Int,
                             _ check: () async throws -> PollResult) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            switch try await check() {
            case .done(let url):
                guard let url, !url.isEmpty else { throw SeedanceError.invalidResponse }
                return url
            case .failed(let msg):
                throw SeedanceError.taskFailed(msg ?? "The generation failed.")
            case .pending:
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        throw SeedanceError.taskFailed("Timed out while creating your video.")
    }

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
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

    private static func downloadData(_ remote: String) async throws -> Data {
        guard let url = URL(string: remote) else { throw SeedanceError.invalidResponse }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private static func downloadToFile(_ remote: String, ext: String) async throws -> URL {
        let data = try await downloadData(remote)
        let url = URL.temporaryDirectory.appending(path: "fruitseg-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }
}
