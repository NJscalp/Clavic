//
//  BrainrotBuildPipeline.swift
//  Clavic
//
//  "Tung Tung Tung Sahur baut ein Haus" – Brainrot-DIY-Build-Template.
//  Bildet den echten viralen Trend (@brainrot.diy, ~60 s) nach: EINE
//  durchgehende, sich Schritt für Schritt entwickelnde Bau-Sequenz mit vielen
//  granularen Schritten (anzeichnen → aufschneiden → Tür → Dampfsperre →
//  Bodenrost → Wand-Lattengerüst → rosa Dämmung → Trockenbau → möbliertes
//  Finale), NICHT drei große Sprünge.
//
//  Pro Schritt:
//   1. GPT Image 2 erzeugt das nächste Frame – verkettet aus dem vorigen Frame
//      (gleicher Ort, gleicher Charakter, sichtbarer Baufortschritt).
//   2. Seedance 2.0 animiert das Frame als ~5-s-Clip (image-to-video) mit
//      eigenem ASMR-Bau-Sound (generateAudio).
//  Alle Clips werden lokal (mit ihrem eigenen Ton) in Reihenfolge zusammengefügt
//  → ~45–50 s, wie die echten Videos.
//
//  Das Riesen-Objekt wird bei jeder Generierung ZUFÄLLIG gewählt → jede Story
//  sieht anders aus. Personalisiert: Tung Tung baut im Kopf der Nutzerin.
//
//  Alles über kie.ai (GPT Image 2 + Seedance 2.0) – kein fal.
//

import Foundation
import AVFoundation
import UIKit

enum BrainrotBuildPipeline {

    /// Gebündeltes Charakter-Referenzbild (echter Tung Tung Tung Sahur).
    private static let characterAsset = "tung_character"

    /// Mögliche Riesen-Objekte (Anzeigename + Innen-Material) für die generische
    /// Variante. Jede Generierung würfelt ein anderes → immer neue Story.
    private static let objects: [(name: String, inside: String)] = [
        ("a giant watermelon", "juicy red-and-green watermelon flesh"),
        ("a giant banana", "pale yellow banana flesh"),
        ("a giant orange", "juicy orange segment flesh"),
        ("a giant walnut", "ridged brown walnut shell"),
        ("a giant peanut", "tan peanut shell"),
        ("a giant cucumber", "watery green cucumber flesh"),
        ("a giant coconut", "white coconut flesh"),
        ("a giant pineapple", "yellow fibrous pineapple flesh"),
        ("a giant strawberry", "red seedy strawberry flesh"),
        ("a giant avocado", "smooth green avocado flesh"),
        ("a giant apple", "crisp white apple flesh"),
        ("a giant pumpkin", "orange stringy pumpkin flesh"),
    ]

    // Charakter-unabhängig: die Beschreibung verweist auf das Referenzbild, damit
    // JEDE Figur funktioniert (Tung Tung, frucht-köpfige Figur ODER eine eigene
    // hochgeladene/umgestylte Figur). Das Referenzbild ankert den Look.
    private static let char = "the same builder character, keeping its exact identity, colors, shape and look from the reference image"

    /// Restyle-Prompt: wandelt eine hochgeladene beliebige Figur in den glossy
    /// Brainrot-3D-Charakter-Stil um (als Referenz für den Bau).
    private static let restylePrompt = "Turn the figure in this image into a glossy, hyper-realistic 3D cartoon 'brainrot' meme character: a full-body stylized creature with big expressive eyes and smooth Pixar-like CGI rendering, standing upright facing forward, holding a small tool, on a clean plain light-gray studio background. Keep its recognizable identity, colors and key features. Photorealistic 3D render, no text, no watermark."
    private static let realism = "Hyper-realistic glossy 3D render like a high-end CGI film, cinematic natural lighting, vertical 9:16. No text, no watermark."
    /// Bewegungs-/Stil-Vorgabe für die Seedance-Clips: Time-Lapse-Speed (schnell,
    /// wie die echten Videos), zusätzlich wird im Schnitt nochmal beschleunigt.
    private static let asmr = "FAST TIME-LAPSE, sped-up construction motion, hands and tools moving quickly, satisfying speed-build montage, smooth cinematic camera, photorealistic, no text, no watermark."

    /// Beschleunigungsfaktor beim Zusammenschneiden → echter Time-Lapse-Look.
    private static let speedUp = 2.0

    /// Zufalls-Varianten, damit JEDE Generierung ein einzigartiges Video wird
    /// (zusätzlich zum zufälligen Objekt).
    private static let settings = [
        "a sunny grassy backyard", "a green park at golden hour",
        "a backyard garden at midday", "a lawn on a bright sunny day",
        "a grassy field with trees behind",
    ]
    // Luxus-Modern-Home-Stile (wie die viralen @mr.zoox-Reveals): das Finale ist
    // immer eine beeindruckende, hochwertige Innenausstattung – KEINE Hütte.
    private static let finishes = [
        "a luxury modern marble interior with recessed cove lighting",
        "a sleek glass-walled modern villa interior",
        "a high-end penthouse interior with floor-to-ceiling windows",
        "an elegant warm-wood-and-marble designer interior",
        "a bright minimalist luxury apartment interior",
    ]

    // MARK: - Einstieg

    /// Erzeugt das fertige Bau-Video und liefert die lokale Datei-URL zurück.
    /// - characterImage: die Bau-Figur (Tung Tung, frucht-köpfig ODER eigene).
    /// - userPhoto: nur bei `personalized` (Bau im Kopf der Person).
    /// - restyleCharacter: true → `characterImage` ist eine hochgeladene Figur und
    ///   wird zuerst per GPT Image 2 in den Brainrot-3D-Stil umgewandelt.
    /// Aufgelöster Plan – im Checkpoint gesichert, damit ein Resume DIESELBE
    /// Story (Objekt/Setting/Finish) weiterführt statt neu zu würfeln.
    private struct BuildPlan: Codable { var name: String; var inside: String; var setting: String; var finish: String }

    static func run(personalized: Bool,
                    characterImage: Data,
                    userPhoto: Data? = nil,
                    restyleCharacter: Bool = false,
                    resolution: String,
                    projectID: UUID,
                    onStage: @escaping (String) -> Void = { _ in }) async throws -> URL {

        // Charakter vorbereiten (eigene Figur ggf. in den Stil umwandeln) – das
        // Ergebnis wird gecacht, damit Resume denselben Charakter nutzt.
        var charJPEG = characterImage
        if restyleCharacter {
            if let cached = Checkpoint.load(projectID, "char.jpg") {
                charJPEG = cached
            } else {
                onStage("Styling your character")
                let styledURL = try await makeFrame(prompt: restylePrompt, images: [characterImage])
                charJPEG = try await downloadData(styledURL)
                Checkpoint.save(projectID, "char.jpg", charJPEG)
            }
        }

        // Plan: aus dem Checkpoint laden (Resume) oder neu würfeln + sichern.
        let plan: BuildPlan
        if let saved = Checkpoint.loadPlan(projectID),
           let p = try? JSONDecoder().decode(BuildPlan.self, from: Data(saved.utf8)) {
            plan = p
        } else {
            let o = objects.randomElement() ?? objects[0]
            plan = BuildPlan(name: o.name, inside: o.inside,
                             setting: settings.randomElement() ?? settings[0],
                             finish: finishes.randomElement() ?? finishes[0])
            if let d = try? JSONEncoder().encode(plan) {
                Checkpoint.savePlan(projectID, String(decoding: d, as: UTF8.self))
            }
        }
        let stages = personalized
            ? personalStages(finish: plan.finish)
            : genericStages(object: (name: plan.name, inside: plan.inside), setting: plan.setting, finish: plan.finish)
        let count = stages.count
        let baseInputs: [Data] = personalized ? [userPhoto ?? charJPEG, charJPEG] : [charJPEG]

        // 1) Keyframes – nur fehlende erzeugen (fertige aus dem Checkpoint).
        let kfDone = (0..<count).filter { Checkpoint.exists(projectID, "kf_\($0).jpg") }.count
        onStage("Designing scenes \(kfDone)/\(count)")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<count where !Checkpoint.exists(projectID, "kf_\(i).jpg") {
                let prompt = stages[i].frame
                group.addTask {
                    let url = try await makeFrame(prompt: prompt, images: baseInputs)
                    Checkpoint.save(projectID, "kf_\(i).jpg", try await downloadData(url))
                }
            }
            var done = kfDone
            for try await _ in group { done += 1; onStage("Designing scenes \(done)/\(count)") }
        }

        // 2) Clips animieren – nur fehlende (fertige Clips bleiben im Checkpoint,
        //    werden also nie doppelt erzeugt/bezahlt). Jeder fertige Clip wird
        //    sofort gesichert.
        let segDone = (0..<count).filter { Checkpoint.exists(projectID, "seg_\($0).mp4") }.count
        onStage("Building the house \(segDone)/\(count)")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<count where !Checkpoint.exists(projectID, "seg_\(i).mp4") {
                guard let frame = Checkpoint.load(projectID, "kf_\(i).jpg") else { continue }
                let prompt = stages[i].anim
                let res = resolution
                group.addTask {
                    let url = try await animate(imageData: frame, prompt: prompt, resolution: res)
                    let local = try await downloadToFile(url, ext: "mp4")
                    Checkpoint.adopt(projectID, "seg_\(i).mp4", from: local)
                    try? FileManager.default.removeItem(at: local)
                }
            }
            var done = segDone
            for try await _ in group { done += 1; onStage("Building the house \(done)/\(count)") }
        }
        let segURLs = (0..<count).map { Checkpoint.url(projectID, "seg_\($0).mp4") }
        guard segURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw SeedanceError.taskFailed("A build segment failed to generate.")
        }

        // 3) Clips in Reihenfolge mit eigenem Ton zusammenfügen.
        onStage("Finishing your video")
        let merged = try await concatKeepingAudio(segURLs)
        return merged
    }

    // MARK: - Bau-Schritte (frame = GPT-Image-2-Prompt, anim = Seedance-Prompt)

    /// Generische Variante: Tung Tung baut Schritt für Schritt in einem
    /// Riesen-Objekt – eine durchgehende Szene mit fortschreitendem Bau.
    private static func genericStages(object: (name: String, inside: String),
                                      setting: String, finish: String) -> [(frame: String, anim: String)] {
        let n = object.name
        let inside = object.inside
        // Echter @mr.zoox-Bogen: kurzer Bau → großer LUXUS-REVEAL (Walkthrough
        // mehrerer Räume) → Lifestyle-Outro. Jeder Schritt anderer Kamerawinkel.
        return [
            ("WIDE ESTABLISHING SHOT from far away: the ENTIRE \(n) lies huge in \(setting), much bigger than \(char) who stands beside it with a measuring tape, chalk-drawing a white doorway outline on the \(n). Bright, glossy, hyper-realistic. \(realism)",
             "Time-lapse: the wooden character quickly chalks a doorway outline on the giant \(n). \(asmr)"),

            ("MEDIUM SIDE-ANGLE SHOT of the same giant \(n) in \(setting): \(char) saws the doorway open, chunks of \(inside) tumbling onto the grass, a wheelbarrow piled with wood planks beside him. \(realism)",
             "Time-lapse: the character saws the doorway open, chunks of \(inside) drop out fast. \(asmr)"),

            ("POV WIDE INTERIOR SHOT looking down the hollow \(n): a long smooth polished \(inside) tunnel-room, \(char) rushing in carrying stacks of wood planks (motion blur, fast). \(realism)",
             "Fast time-lapse: the character hauls wood planks into the smooth hollow \(n). \(asmr)"),

            ("LOW-ANGLE INTERIOR SHOT inside the \(n): wooden floor framing and wall studs going up fast, \(char) hammering the structure together, sawdust flying. \(realism)",
             "Fast time-lapse: floor and wall framing go up around the character. \(asmr)"),

            ("WIDE INTERIOR SHOT inside the \(n): drywall, flooring and big window openings being installed over the framing, the raw room turning into real rooms, \(char) finishing the walls. \(realism)",
             "Fast time-lapse: walls, floors and windows are installed, raw rooms taking shape. \(asmr)"),

            ("STUNNING WIDE REVEAL SHOT — the FINISHED luxury entrance hall inside the \(n), built as \(finish): a long polished marble floor, marble feature wall, glowing recessed cove ceiling lights, \(char) walking in proudly. Looks like a high-end real-estate tour. \(realism)",
             "Smooth cinematic camera glides through the finished luxury marble entrance hall, the character walking proudly. \(asmr)"),

            ("WIDE REVEAL SHOT of the modern luxury LIVING ROOM & KITCHEN inside the \(n) (\(finish)): designer sofas, an island kitchen, warm lighting and FLOOR-TO-CEILING GLASS WINDOWS showing the green field outside, \(char) relaxing on the sofa. \(realism)",
             "Cinematic camera pans across the luxury living room and kitchen with huge glass windows, the character relaxing. \(asmr)"),

            ("WIDE REVEAL SHOT of the elegant luxury BEDROOM inside the \(n) (\(finish)): a plush modern bed, soft warm lighting, a big window, tasteful decor, \(char) admiring the room. \(realism)",
             "Cinematic camera reveals the cozy luxury bedroom, the character admiring it. \(asmr)"),

            ("LIFESTYLE OUTRO SHOT: \(char) relaxing happily, enjoying the finished giant-\(n) luxury home — lounging by the big window with the field view (or stepping outside proudly in front of the \(n)). Warm golden light, satisfying ending. \(realism)",
             "Final lifestyle shot: the character relaxes and enjoys his finished luxury home inside the \(n). \(asmr)"),
        ]
    }

    /// Personalisierte Variante: Tung Tung baut Schritt für Schritt im Kopf der
    /// Person (Querschnitt), das echte Gesicht bleibt außen erhalten.
    private static func personalStages(finish: String) -> [(frame: String, anim: String)] {
        let head = "the person's head"
        // Jedes Frame nutzt [Foto, Charakter] als Referenz (Gesicht bleibt
        // erhalten); jeder Schritt mit eigenem Kamerawinkel, KEIN Chaining.
        let keep = "The FIRST image is a real person, the SECOND is the wooden character. Keep the person's real face, hair and identity intact on the outside, photorealistic."
        return [
            ("\(keep) Funny surreal brainrot meme — WIDE SHOT: a clean cut-away cross-section of the top of \(head) reveals \(char) inside with a measuring tape, chalking out a room. \(realism)",
             "Time-lapse: inside the head the wooden character chalks out a room. \(asmr)"),

            ("\(keep) MEDIUM SHOT into the cut-away \(head): \(char) hauls in wood planks and rapidly hammers up floor and wall framing, sawdust flying. \(realism)",
             "Fast time-lapse: the character frames floors and walls inside the head. \(asmr)"),

            ("\(keep) WIDE INTERIOR SHOT inside \(head): drywall, flooring and a window opening being installed over the framing, the raw space turning into real rooms, \(char) finishing the walls. \(realism)",
             "Fast time-lapse: walls, floor and a window are installed inside the head. \(asmr)"),

            ("\(keep) STUNNING WIDE REVEAL inside \(head): a FINISHED luxury entrance hall built as \(finish) — polished marble floor, marble feature wall, glowing recessed cove lighting, \(char) walking in proudly. \(realism)",
             "Smooth cinematic camera glides through the finished luxury marble hall inside the head. \(asmr)"),

            ("\(keep) WIDE REVEAL of the modern luxury LIVING ROOM inside \(head) (\(finish)): designer sofas, warm lighting and a big glass window, \(char) relaxing on the sofa. \(realism)",
             "Cinematic camera pans across the luxury living room inside the head, the character relaxing. \(asmr)"),

            ("\(keep) WIDE REVEAL of the elegant luxury BEDROOM inside \(head) (\(finish)): a plush modern bed, soft warm lighting, tasteful decor, \(char) admiring the room. \(realism)",
             "Cinematic camera reveals the cozy luxury bedroom inside the head. \(asmr)"),

            ("\(keep) LIFESTYLE OUTRO: the camera pulls back to show the person's normal head from outside again (face intact), then \(char) peeks out happily from the finished luxury home inside. Warm golden light, satisfying ending. \(realism)",
             "Final lifestyle shot: the character peeks out happily from the finished luxury home inside the head. \(asmr)"),
        ]
    }

    // MARK: - Schritt 1: Frame (GPT Image 2)

    private static func makeFrame(prompt: String, images: [Data]) async throws -> String {
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

    // MARK: - Schritt 2: Segment animieren (Seedance image-to-video + SFX)

    private static func animate(imageData: Data, prompt: String, resolution: String) async throws -> String {
        let body: [String: Any] = [
            "provider": "kie",
            "prompt": prompt,
            "images": [imageData.base64EncodedString()],
            "resolution": resolution,
            "duration": 5,
            "aspectRatio": "9:16",
            "generateAudio": true,   // ASMR-Bau-Sound von Seedance
            "fast": false,           // Seedance 2.0 (volle Qualität, nicht Fast)
        ]
        let json = try await post(path: "/v1/seedance/reference-to-video", body: body, timeout: 120)
        guard let taskID = (json["data"] as? [String: Any])?["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return try await poll(timeoutSeconds: 900) {
            let json = try await post(path: "/v1/seedance/status",
                                      body: ["provider": "kie", "taskId": taskID], timeout: 30)
            let data = json["data"] as? [String: Any] ?? [:]
            switch (data["state"] as? String ?? "").lowercased() {
            case "succeeded": return .done(data["videoUrl"] as? String)
            case "failed":    return .failed(data["failMsg"] as? String)
            default:          return .pending
            }
        }
    }

    // MARK: - Schritt 3: Clips zusammenfügen (Ton der Segmente behalten)

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

        // Time-Lapse: das ganze zusammengesetzte Video (Bild + Ton) gleichmäßig
        // beschleunigen → schneller Speed-Build-Look wie in den viralen Clips.
        if speedUp > 1.0, cursor > .zero {
            let full = CMTimeRange(start: .zero, duration: cursor)
            let target = CMTime(seconds: cursor.seconds / speedUp, preferredTimescale: 600)
            videoTrack.scaleTimeRange(full, toDuration: target)
            audioTrack.scaleTimeRange(full, toDuration: target)
        }

        // Beschleunigte Zeitbereiche erfordern eine Neukodierung (kein Passthrough).
        if let url = await export(composition, preset: AVAssetExportPresetHighestQuality) { return url }
        throw SeedanceError.taskFailed("Could not export the video.")
    }

    private static func export(_ composition: AVMutableComposition, preset: String) async -> URL? {
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { return nil }
        let outURL = URL.temporaryDirectory.appending(path: "build-\(UUID().uuidString).mp4")
        session.shouldOptimizeForNetworkUse = true
        do {
            try await session.export(to: outURL, as: .mp4)
            return outURL
        } catch {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
    }

    // MARK: - Hilfen

    private enum PollResult {
        case pending
        case done(String?)
        case failed(String?)
    }

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
        let url = URL.temporaryDirectory.appending(path: "buildseg-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }
}
