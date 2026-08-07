//
//  MusicVideoPipeline.swift
//  Clavic
//
//  Mehrstufige Pipeline für das Musikvideo-Template „Du bist gut Genug".
//  Seedance hat ein hartes 5-Sekunden-Limit bei reference-to-video, daher wird
//  die volle Performance aus mehreren Segmenten zusammengesetzt:
//
//   1. Für jeden Referenz-Chunk (a,b,c) ein Seedance-Segment generieren (kie.ai).
//      Seedance bildet die echte Sing-/Bewegungs-Performance des Original-Clips
//      nach – dadurch sieht der Mund natürlich/real aus (kein aufgesetztes
//      Lip-Sync).
//   2. Die Segmente lokal per AVFoundation aneinanderhängen (Segment c nur sein
//      Reststück) und den Original-Song als durchgehende Tonspur darüberlegen
//      → der Song wird „mitgesungen", es bleibt real.
//
//  Die Chunks + der Song liegen server-seitig fest (gleicher Song für alle
//  Nutzer); die Zeitfenster sind hier als Konstanten hinterlegt.
//

import Foundation
import AVFoundation
import UIKit

enum MusicVideoPipeline {

    // MARK: - Feste Konfiguration (an die gehosteten Referenz-Chunks gekoppelt)

    private struct Chunk {
        var refURL: String = ""       // gehosteter Referenz-Clip (@Video1) für dieses Segment
        var bundleName: String? = nil // ODER: gebündelter Clip (ohne .mp4) → als base64 gesendet
        let tailSeconds: Double?      // nur die letzten N s behalten (nil = ganzes Segment)
        /// Optionaler Prompt nur für dieses Segment (sonst der übergebene Standard-Prompt).
        var prompt: String? = nil
        /// Welche Nutzerfotos als @Image1/@Image2 an Seedance gehen (0-basiert).
        var imageIndices: [Int] = [0]
        /// Nur für Gemini-Omni-Chunks: Ziel-Ausgabedauer in Sekunden (3-8),
        /// passend zur Länge dieses Referenz-Clips.
        var omniDuration: Int = 8
    }

    /// Pro Template: die Referenz-Chunks, die Original-Tonspur und das
    /// Seitenverhältnis. Damit lässt sich dieselbe Pipeline für mehrere
    /// Templates nutzen, ohne sie zu kopieren.
    private struct Config {
        let chunks: [Chunk]
        let songURL: String
        let aspectRatio: String   // "16:9" (quer) oder "9:16" (hochkant)
        /// Gebündelte Tonspur (Dateiname ohne Endung) statt gehostetem Song.
        var songBundleName: String? = nil
        /// Loop-Plan für image-to-video-Templates: ein einziges generiertes
        /// Segment wird so oft wiederholt (mit diesen Tail-Längen) bis die
        /// Audiolänge gefüllt ist. nil = normale Chunk-Verkettung.
        var loopPlan: [Double?]? = nil
        /// false = Seedance 2.0 „normal" (bessere Qualität) statt fast.
        var fast: Bool = true
        /// Kling 3.0 Motion Control: gebündeltes Referenzvideo (Dateiname ohne
        /// .mp4). Wenn gesetzt, läuft EIN Kling-Call (Mensch-Bewegung → Motiv)
        /// statt der Seedance-Chunk-Pipeline; danach wird der Song darübergelegt.
        var klingRefBundle: String? = nil
        /// Alternativ: GEHOSTETES Kling-Referenzvideo (http-URL statt Bundle) —
        /// spart App-Größe und umgeht das ~4,5-MB-Body-Limit des Backends.
        var klingRefURL: String? = nil
        /// Compose-Schritt VOR Kling: gebündeltes Standbild der Video-Szene
        /// (Dateiname ohne .jpg). Die Person aus dem Nutzerfoto wird per
        /// Bild-Edit in dieses Standbild eingesetzt; Kling animiert dann das
        /// zusammengesetzte Bild mit der Bewegung aus dem Referenzvideo →
        /// Hintergrund/Szene sind 1:1 die aus dem Video (Kling nimmt die Szene
        /// sonst aus dem FOTO, nicht aus dem Video).
        var klingComposeFrameBundle: String? = nil
        /// Prompt für den Compose-Bild-Edit (erstes Bild = Szene, zweites = Person).
        var klingComposePrompt: String? = nil
        /// WaveSpeed-Kling-Modell (Default Kling O3/Omni 3 VIDEO-EDIT: tauscht
        /// nur die Person, Bewegung/Szene/Original-Ton bleiben; $0.126/s).
        var klingModel: String = "kwaivgi/kling-video-o3-std/video-edit"
        var klingMode: String = "720p"
        var klingOrientation: String = "video"        // "video" | "image"
        var klingBackground: String = "input_image"   // "input_image" | "input_video"
        /// Gemini Omni Video (kie `gemini-omni-video`) statt Seedance — immer @720p.
        var geminiOmni: Bool = false
        /// Erzwungene Render-Aufloesung (z. B. "720p" fuer Person-Swap-Qualitaet).
        var forceResolution: String? = nil
        /// Kie-Modell-Override (z. B. `bytedance/seedance-2-mini`).
        var seedanceModel: String? = nil
    }

    private static var base: String {
        var copy = BackendConfiguration.baseURL
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    /// Alle Pipeline-Templates, per Schlüssel ansprechbar (siehe
    /// `VideoTemplate.musicVideoKey`). Die Zeitfenster sind an die jeweils
    /// gehosteten Chunks gekoppelt.
    private static var configs: [String: Config] {
        [
            // „Du bist gut Genug" – 11,77 s Musikvideo, quer (16:9)
            "music": Config(
                chunks: [
                    Chunk(refURL: base + "/music-ref-a.mp4", tailSeconds: nil),
                    Chunk(refURL: base + "/music-ref-b.mp4", tailSeconds: nil),
                    // ref-c deckt 6,77–11,77 s ab; gebraucht wird nur 10,0–11,77 → letzte ~1,77 s
                    Chunk(refURL: base + "/music-ref-c.mp4", tailSeconds: 1.77),
                ],
                songURL: base + "/song-full.m4a",
                aspectRatio: "16:9"
            ),
            // „Nerv Backrooms" – 8,53 s Tanz, hochkant (9:16)
            "nerv": Config(
                chunks: [
                    Chunk(refURL: base + "/nerv-ref-a.mp4", tailSeconds: nil),
                    // ref-b deckt 3,53–8,53 s ab; gebraucht wird nur 5,0–8,53 → letzte ~3,53 s
                    Chunk(refURL: base + "/nerv-ref-b.mp4", tailSeconds: 3.53),
                ],
                songURL: base + "/nerv-song-full.m4a",
                aspectRatio: "9:16"
            ),
            // „Tung Tung Sahur Dance" – 14,1 s, hochkant (9:16). RECHTS tanzt der
            // Tung-Tung-Charakter (bleibt fix), LINKS wird der Nutzer eingesetzt und
            // macht denselben Tanz synchron. Ein einziger Seedance-video-edit über
            // die volle Länge; danach der Original-Song drüber.
            "tungdance": Config(
                chunks: [
                    Chunk(refURL: base + "/tung-ref-a.mp4", tailSeconds: nil,
                          prompt: tungDancePrompt, imageIndices: [0], omniDuration: 7),
                    Chunk(refURL: base + "/tung-ref-b.mp4", tailSeconds: nil,
                          prompt: tungDancePrompt, imageIndices: [0], omniDuration: 7),
                ],
                songURL: base + "/tung-song.m4a",
                aspectRatio: "9:16",
                geminiOmni: true
            ),
            // "On the Radar Rubberz" – 10,85 s OTR-Freestyle (Rubberz), hochkant
            // (9:16). EIN Kling-O3-video-edit über die volle Länge des
            // gehosteten Referenzclips: NUR die Person wird getauscht (Person aus
            // @Image1 ersetzt den Rapper), Bewegungen, Timing, grünes Neon-Studio
            // und Kamera bleiben identisch. Danach wird die ORIGINAL-Tonspur aus
            // rubberz.mp4 (rubberz-song.m4a) darübergelegt. (O3 rechnet max 10 s
            // ab — Clip ist 10,85 s, ggf. Output minimal kürzer als der Song.)
            // (Kling-Zwei-Schritt-Variante siehe rubberzComposePrompt — bei
            // Bedarf via klingRefURL/klingComposeFrameBundle reaktivierbar.)
            "rubberz": Config(
                chunks: [
                    Chunk(refURL: base + "/rubberz-ref.mp4", tailSeconds: nil, prompt: rubberzPrompt, imageIndices: [0]),
                ],
                songURL: base + "/rubberz-song.m4a",
                aspectRatio: "9:16",
                forceResolution: "720p"
            ),
            // "Baseball Fan Cam" - 10,05 s Broadcast-Cam, 4:3
            "baseball": Config(
                chunks: [
                    Chunk(refURL: base + "/baseball-ref-a.mp4", tailSeconds: nil),
                    Chunk(refURL: base + "/baseball-ref-b.mp4", tailSeconds: nil),
                ],
                songURL: base + "/baseball-song-full.m4a",
                aspectRatio: "4:3"
            ),
            // "Backrooms Dance" - 12,67 s Tanz, quadratisch (1:1)
            "pdance": Config(
                chunks: [
                    Chunk(refURL: base + "/pdance-ref-a.mp4", tailSeconds: nil),
                    Chunk(refURL: base + "/pdance-ref-b.mp4", tailSeconds: nil),
                    // ref-c deckt 7,67-12,67 s ab; gebraucht wird nur 10,0-12,67 -> letzte ~2,67 s
                    Chunk(refURL: base + "/pdance-ref-c.mp4", tailSeconds: 2.67),
                ],
                songURL: base + "/pdance-song-full.m4a",
                aspectRatio: "1:1"
            ),
            // "If you grab me imma bite you" – image-to-video (Seedance).
            // WICHTIG: KEINE echte-Person-Referenz (triggert kie-Moderation
            // "sensitive information") und KEIN Kling (lehnt Tiere ab). Reines
            // i2v: das Tier/Subjekt aus dem Foto wird animiert (eigener
            // Hintergrund bleibt), ein 5s-Segment wird aufs Original-Audio
            // (~12s) geloopt. Akzeptiert Tiere, kein Moderations-/Recognition-Fehler.
            // Kling 3.0 Motion Control (kie.ai): EIN Call – das gebündelte
            // Referenzvideo (person-ref) liefert die Bewegung, das Foto-Motiv
            // wird hineinanimiert, Hintergrund kommt aus dem Foto. Danach der
            // gebündelte Original-Song als Tonspur. ACHTUNG: Kling verlangt einen
            // menschlichen Oberkörper im Foto und lehnt reine Tierfotos ab.
            "dog": Config(
                chunks: [],
                songURL: "",
                aspectRatio: "9:16",
                songBundleName: "dog-song",
                klingRefBundle: "person-ref",
                klingMode: "720p",
                klingOrientation: "video",
                klingBackground: "input_image"
            ),
        ]
    }

    /// Fixiert die exakte Tung-Tung-Optik (sonst generiert Gemini Omni Flash
    /// beim Neu-Rendern der Szene einen generischen Holzroboter statt der
    /// erkennbaren Figur).
    private static var tungDancePrompt: String {
        """
        Reference video: a dancer on the LEFT and, on the RIGHT, the exact character 'Tung Tung Tung Sahur' — \
        a tall thin carved wooden log figure with a flat rectangular wood-grain face showing two small painted \
        dot eyes and a thin painted mouth, wearing a pink-and-white striped cloth headband tied around its \
        head, a gold tribal necklace with dangling charms across its chest, and a light wood-grain textured \
        cylindrical body with thin stick arms and legs. Keep this RIGHT character PIXEL-IDENTICAL to the \
        reference video in every frame — same carved wood texture, same painted face, same headband, same \
        gold necklace, same proportions, same dance moves and timing, do not simplify, stylize or redesign it. \
        Replace ONLY the LEFT dancer with the person from the reference image — their exact face, hair, skin \
        tone and gender, wearing casual streetwear — performing the exact same dance moves and timing as the \
        original left dancer, fully synchronized. Keep the driveway, houses, sky and camera framing exactly \
        the same. Photorealistic, sharp, no morphing, no watermark, no text. 9:16 vertical
        """
    }

    /// "On the Radar Rubberz" (video-edit): ersetzt den Rapper im grünen
    /// Neon-Studio durch das Nutzerfoto. NUR die Person wechselt — Bewegungen,
    /// Mundbewegungen, Timing, Set (grüne "ON THE RADAR"-Neonwand, Standmikro)
    /// und Kamera bleiben in jedem Frame identisch (Person-Swap, kein Style-Edit).
    private static var rubberzPrompt: String {
        """
        PERSON SWAP, not a style edit: the rapper performing into the standing microphone in @Video1 must be \
        COMPLETELY REPLACED by the person from @Image1 — their exact face, hair, skin tone and body, wearing \
        their own outfit from the photo. The original performer must NOT appear anywhere. The new person \
        performs the EXACT same freestyle rap: identical mouth movements and lip sync, head movements, hand \
        gestures, body language and precise timing as the original rapper. Keep EVERYTHING else completely \
        unchanged in every frame: the green neon "ON THE RADAR" letters on the back wall, the glowing green \
        studio lighting, the microphone and its stand in the exact same position, and the identical static \
        camera framing. Photorealistic, natural real footage look, sharp detail, no morphing, no distortion, \
        no added text, no watermark. 9:16 vertical
        """
    }

    /// Kling-Zwei-Schritt-Variante (aktuell inaktiv): Compose-Prompt, der die
    /// Person aus dem Nutzerfoto ins Studio-Standbild `rubberz-frame.jpg` setzt —
    /// Szene, Mikro, Framing und Licht bleiben pixelgenau erhalten. Das Ergebnis
    /// wäre das Start-Bild für Kling Motion Control.
    private static var rubberzComposePrompt: String {
        """
        PERSON SWAP in a still frame: replace the rapper standing at the microphone in the FIRST image with \
        the person from the SECOND image — their exact face, hair, skin tone and body, wearing their own \
        outfit from their photo. The original rapper must NOT appear. The new person stands in the exact \
        same position and pose at the standing microphone, at the same scale and distance from the camera. \
        Keep EVERYTHING else from the first image pixel-identical: the green neon "ON THE RADAR" letters on \
        the back wall, the glowing green studio lighting and color mood, the microphone and its stand, and \
        the exact camera framing. Photorealistic, natural real footage look, sharp detail, no morphing, no \
        added text, no watermark. 9:16 vertical
        """
    }

    private static func config(for key: String) -> Config {
        configs[key] ?? configs["music"]!
    }

    // MARK: - Öffentlicher Einstieg

    /// Führt die komplette Pipeline aus und liefert die lokale URL des fertigen
    /// Videos (volle Länge, mit Original-Song als Tonspur).
    static func run(
        key: String,
        prompt: String,
        photoJPEG: Data,
        extraPhotos: [Data] = [],
        resolution: String = "480p",
        onStage: @escaping (String) -> Void = { _ in }
    ) async throws -> URL {
        let allPhotos = compressPhotosForUpload([photoJPEG] + extraPhotos)
        let cfg = config(for: key)
        let renderResolution = cfg.forceResolution ?? (cfg.geminiOmni ? "720p" : resolution)

        // Kling O3 video-edit: ein einziger Call (Bewegung + Szene aus dem
        // Referenzvideo → Person aus dem Foto), danach Original-Song.
        if cfg.klingRefBundle != nil || cfg.klingRefURL != nil {
            // Optionaler Compose-Schritt: Person aus dem Nutzerfoto in das
            // Standbild der Video-Szene einsetzen (Bild-Edit), damit Kling
            // Szene UND Person aus dem zusammengesetzten Bild übernimmt.
            var klingPhoto = allPhotos[0]
            if let frameBundle = cfg.klingComposeFrameBundle {
                onStage("Placing you in the scene")
                klingPhoto = try await generateComposedFrame(
                    frameBundle: frameBundle,
                    personPhoto: allPhotos[0],
                    prompt: cfg.klingComposePrompt ?? "")
            }
            onStage("Generating performance")
            let resultURL = try await generateKlingSegment(
                prompt: prompt, photoB64: klingPhoto.base64EncodedString(),
                refBundle: cfg.klingRefBundle, refURL: cfg.klingRefURL,
                model: cfg.klingModel,
                mode: cfg.klingMode, orientation: cfg.klingOrientation, background: cfg.klingBackground)
            onStage("Finishing your video")
            let local = try await download(resultURL, ext: "mp4")
            let song: URL
            if let name = cfg.songBundleName, let url = Bundle.main.url(forResource: name, withExtension: "m4a") {
                song = url
            } else {
                song = try await download(cfg.songURL, ext: "m4a")
            }
            let merged = try await mergeSegments([local], songFile: song, tails: [nil])
            try? FileManager.default.removeItem(at: local)
            if cfg.songBundleName == nil { try? FileManager.default.removeItem(at: song) }
            return merged
        }

        let chunks = cfg.chunks

        // 1) Alle Segmente parallel generieren (Seedance oder Gemini Omni)
        onStage("Generating performance")
        let segmentURLs = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    let chunkPrompt = chunk.prompt ?? prompt
                    let images = chunk.imageIndices.compactMap { idx -> String? in
                        guard idx >= 0, idx < allPhotos.count else { return nil }
                        return allPhotos[idx].base64EncodedString()
                    }
                    guard !images.isEmpty else {
                        throw SeedanceError.taskFailed("Not enough reference photos for this template.")
                    }
                    let url: String
                    if cfg.geminiOmni {
                        url = try await generateOmniSegment(
                            prompt: chunkPrompt, imageB64s: images,
                            refURL: chunk.refURL, aspectRatio: cfg.aspectRatio,
                            duration: chunk.omniDuration)
                    } else {
                        url = try await generateSegment(
                            prompt: chunkPrompt, imageB64s: images,
                            refURL: chunk.refURL, bundleName: chunk.bundleName,
                            aspectRatio: cfg.aspectRatio,
                            resolution: renderResolution, fast: cfg.fast,
                            model: cfg.seedanceModel)
                    }
                    return (index, url)
                }
            }
            var results = Array<String?>(repeating: nil, count: chunks.count)
            for try await (index, url) in group { results[index] = url }
            return results.compactMap { $0 }
        }
        guard segmentURLs.count == chunks.count else {
            throw SeedanceError.taskFailed("A performance segment failed to generate.")
        }

        // 2) Segmente + Song herunterladen
        onStage("Finishing your video")
        var localSegments: [URL] = []
        for remote in segmentURLs {
            localSegments.append(try await download(remote, ext: "mp4"))
        }

        // image-to-video-Templates: ein Segment mehrfach loopen (Bild-Hintergrund
        // bleibt erhalten), damit die volle Original-Audiolänge gefüllt wird.
        var tails = chunks.map { $0.tailSeconds }
        if let plan = cfg.loopPlan, let first = localSegments.first {
            localSegments = plan.map { _ in first }
            tails = plan
        }

        let songFile: URL
        if let name = cfg.songBundleName, let url = Bundle.main.url(forResource: name, withExtension: "m4a") {
            songFile = url
        } else {
            songFile = try await download(cfg.songURL, ext: "m4a")
        }

        // 3) Zusammenfügen + Song als Tonspur
        let merged = try await mergeSegments(localSegments, songFile: songFile, tails: tails)

        // Aufräumen (gebündelte Audiodatei NICHT löschen).
        for f in Set(localSegments) { try? FileManager.default.removeItem(at: f) }
        if cfg.songBundleName == nil { try? FileManager.default.removeItem(at: songFile) }
        return merged
    }

    // MARK: - Schritt 1b: Gemini Omni Flash Reference-to-Video (WaveSpeed, @720p)

    private static func generateOmniSegment(prompt: String, imageB64s: [String],
                                           refURL: String, aspectRatio: String, duration: Int) async throws -> String {
        var body: [String: Any] = [
            "provider": "wavespeed",
            "model": "google/gemini-omni-flash/reference-to-video",
            "prompt": prompt,
            "imagesField": "images",
            "images": imageB64s,
            "aspectRatio": aspectRatio,
            "duration": min(8, max(3, duration)),
        ]
        if !refURL.isEmpty {
            body["videosField"] = "videos"
            body["videoUrls"] = [refURL]
        }
        let json = try await post(path: "/v1/seedance/reference-to-video", body: body, timeout: 180)
        guard let taskID = (json["data"] as? [String: Any])?["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return try await poll(timeoutSeconds: 900) {
            let json = try await post(path: "/v1/seedance/status",
                                      body: ["provider": "wavespeed", "taskId": taskID], timeout: 30)
            let data = json["data"] as? [String: Any] ?? [:]
            let state = (data["state"] as? String ?? "").lowercased()
            switch state {
            case "succeeded": return .done(data["videoUrl"] as? String)
            case "failed":    return .failed(data["failMsg"] as? String)
            default:          return .pending
            }
        }
    }

    // MARK: - Schritt 1c: Seedance-Segment

    private static func generateSegment(prompt: String, imageB64s: [String], refURL: String, bundleName: String?, aspectRatio: String, resolution: String, fast: Bool = true, model: String? = nil) async throws -> String {
        // Alles über WAVESPEED. Segmente mit Referenz-Clip laufen über
        // Kling O3 (Omni 3) VIDEO-EDIT — Person aus den Referenzbildern (Array,
        // auch MEHRERE wie bei "you") ersetzt die Person im Video, Bewegung,
        // Timing, Szene und Original-Ton bleiben erhalten. Kein resolution-Feld
        // (O3 kennt es nicht; Abrechnung 3–10 s à $0.126/s).
        var videoB64: String? = nil
        if let bundleName,
           let url = Bundle.main.url(forResource: bundleName, withExtension: "mp4"),
           let data = try? Data(contentsOf: url) {
            videoB64 = data.base64EncodedString()
        }
        let hasRef = videoB64 != nil || !refURL.isEmpty

        var body: [String: Any]
        if hasRef {
            body = [
                "provider": "wavespeed",
                "model": "kwaivgi/kling-video-o3-std/video-edit",
                "prompt": prompt,
                "imagesField": "images",
                "images": imageB64s,
            ]
            if let videoB64 { body["videos"] = [videoB64] } else { body["videoUrls"] = [refURL] }
        } else {
            // Reines Bild→Video: Seedance auf WaveSpeed (Fast/Standard).
            let m = fast ? "bytedance/seedance-2.0-fast/image-to-video"
                         : "bytedance/seedance-2.0/image-to-video"
            body = [
                "provider": "wavespeed",
                "model": m,
                "prompt": prompt,
                "images": imageB64s,
                "resolution": resolution,
                "duration": 5,
                "aspectRatio": aspectRatio,
                "generateAudio": false,
            ]
        }
        let json = try await post(path: "/v1/seedance/reference-to-video", body: body, timeout: 120)
        guard let taskID = (json["data"] as? [String: Any])?["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return try await poll(timeoutSeconds: 600) {
            let json = try await post(path: "/v1/seedance/status",
                                      body: ["provider": "wavespeed", "taskId": taskID], timeout: 30)
            let data = json["data"] as? [String: Any] ?? [:]
            let state = (data["state"] as? String ?? "").lowercased()
            switch state {
            case "succeeded": return .done(data["videoUrl"] as? String)
            case "failed":    return .failed(data["failMsg"] as? String)
            default:          return .pending
            }
        }
    }

    // MARK: - Schritt 1b: Kling 3.0 Motion-Control-Segment

    /// Setzt die Person aus dem Nutzerfoto per Bild-Edit (Seedream) in das
    /// gebündelte Standbild der Video-Szene ein. Liefert das zusammengesetzte
    /// Bild als JPEG-Daten (Start-Bild für Kling Motion Control).
    private static func generateComposedFrame(frameBundle: String, personPhoto: Data,
                                              prompt: String) async throws -> Data {
        guard let frameURL = Bundle.main.url(forResource: frameBundle, withExtension: "jpg"),
              let frameData = try? Data(contentsOf: frameURL) else {
            throw SeedanceError.invalidResponse
        }
        let request = ImageEditRequest(
            prompt: prompt,
            referenceImages: [frameData, personPhoto],   // 1 = Szene, 2 = Person
            quality: "medium",
            aspectRatio: "9:16"
        )
        let taskID = try await ImageEditAPI.createTask(request)
        let imageURL: String = try await poll(timeoutSeconds: 300) {
            let state = try await ImageEditAPI.fetchTask(id: taskID)
            switch state.status {
            case .succeeded: return .done(state.imageURL)
            case .failed:    return .failed(state.failureReason)
            default:         return .pending
            }
        }
        let local = try await download(imageURL, ext: "jpg")
        defer { try? FileManager.default.removeItem(at: local) }
        return try Data(contentsOf: local)
    }

    private static func generateKlingSegment(prompt: String, photoB64: String, refBundle: String?,
                                             refURL: String? = nil,
                                             model: String = "kwaivgi/kling-video-o3-std/video-edit",
                                             mode: String, orientation: String, background: String) async throws -> String {
        // Kling O3 (Omni 3) VIDEO-EDIT über WAVESPEED (Schema { prompt, video,
        // images }): Person aus dem Foto ersetzt die Person im Referenzvideo,
        // Bewegung/Szene/Original-Ton bleiben erhalten.
        // mode/orientation/background waren kie-spezifisch und entfallen.
        _ = (mode, orientation, background)
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var body: [String: Any] = [
            "provider": "wavespeed",
            "model": model,
            "prompt": trimmed.isEmpty
                ? "Replace the main person in the video with the person from the image. Keep exactly the same movements, timing, camera work, background and scene from the video. Preserve the exact identity, face and hair of the person from the image. Photorealistic, no morphing, no distortion. No text, no watermark."
                : trimmed,
            "imagesField": "images",
            "images": [photoB64],
        ]
        if let refURL, refURL.hasPrefix("http") {
            // Gehostetes Referenzvideo: URL wird vom Backend 1:1 durchgereicht.
            body["videoUrls"] = [refURL]
        } else if let refBundle,
                  let url = Bundle.main.url(forResource: refBundle, withExtension: "mp4"),
                  let data = try? Data(contentsOf: url) {
            body["videos"] = [data.base64EncodedString()]
        } else {
            throw SeedanceError.invalidResponse
        }

        let json = try await post(path: "/v1/seedance/reference-to-video", body: body, timeout: 180)
        guard let taskID = (json["data"] as? [String: Any])?["taskId"] as? String, !taskID.isEmpty else {
            throw SeedanceError.invalidResponse
        }
        return try await poll(timeoutSeconds: 900) {
            let json = try await post(path: "/v1/seedance/status",
                                      body: ["provider": "wavespeed", "taskId": taskID], timeout: 30)
            let data = json["data"] as? [String: Any] ?? [:]
            let state = (data["state"] as? String ?? "").lowercased()
            switch state {
            case "succeeded": return .done(data["videoUrl"] as? String)
            case "failed":    return .failed(data["failMsg"] as? String)
            default:          return .pending
            }
        }
    }

    // MARK: - Schritt 3: Segmente zusammenfügen + Song (AVFoundation)

    private static func mergeSegments(_ files: [URL], songFile: URL, tails: [Double?]) async throws -> URL {
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw SeedanceError.taskFailed("Could not build the video.")
        }

        // Videospuren der Segmente sequenziell einfügen.
        var cursor = CMTime.zero
        for (index, file) in files.enumerated() {
            let asset = AVURLAsset(url: file)
            let fullDuration = try await asset.load(.duration)

            var range = CMTimeRange(start: .zero, duration: fullDuration)
            if let tail = tails[index], tail > 0 {
                let tailTime = CMTime(seconds: tail, preferredTimescale: 600)
                if tailTime < fullDuration {
                    range = CMTimeRange(start: fullDuration - tailTime, duration: tailTime)
                }
            }
            if let v = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(range, of: v, at: cursor)
            }
            cursor = cursor + range.duration
        }

        // Original-Song als Tonspur (auf Videolänge begrenzt).
        let songAsset = AVURLAsset(url: songFile)
        let songDuration = try await songAsset.load(.duration)
        let audioDuration = min(cursor, songDuration)
        if audioDuration > .zero, let songTrack = try await songAsset.loadTracks(withMediaType: .audio).first {
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: songTrack, at: .zero)
        }

        // Export bevorzugt PASSTHROUGH: kopiert die Original-Videospuren der
        // Seedance-Segmente ohne erneute Kompression → keine Qualitätsverluste
        // (vorher wurde 480p ein zweites Mal komprimiert und sah schlechter aus
        // als die rohe kie.ai-Ausgabe). Fällt auf HighestQuality zurück, falls
        // die Segmente nicht passthrough-kompatibel sind.
        if let url = await export(composition, preset: AVAssetExportPresetPassthrough) {
            return url
        }
        if let url = await export(composition, preset: AVAssetExportPresetHighestQuality) {
            return url
        }
        throw SeedanceError.taskFailed("Could not export the video.")
    }

    /// Exportiert die Komposition mit dem angegebenen Preset. Gibt nil zurück,
    /// wenn das Preset nicht erstellt/genutzt werden kann (→ Fallback).
    private static func export(_ composition: AVMutableComposition, preset: String) async -> URL? {
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { return nil }
        let outURL = URL.temporaryDirectory.appending(path: "musicvideo-\(UUID().uuidString).mp4")
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

    /// Hält Base64-Uploads unter Vercels ~4,5 MB Request-Limit (verhindert HTTP 413).
    private static func compressPhotosForUpload(_ photos: [Data]) -> [Data] {
        photos.map { data in
            guard let image = UIImage(data: data),
                  let jpeg = image.jpegForAPIUpload(maxDimension: 768, quality: 0.72) else { return data }
            return jpeg
        }
    }

    private enum PollResult {
        case pending
        case done(String?)
        case failed(String?)
    }

    /// Pollt eine Closure alle 5 s, bis sie `done`/`failed` liefert.
    private static func poll(timeoutSeconds: Double, _ check: () async throws -> PollResult) async throws -> String {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        // Transiente Netzwerk-Fehler ("the network connection was lost", Timeout,
        // Funkloch) dürfen die Generierung NICHT abbrechen — der Task läuft
        // server-seitig weiter und wird voll berechnet. Erst nach ~2 min
        // durchgehend fehlgeschlagener Status-Checks wird wirklich aufgegeben.
        var consecutiveErrors = 0
        while Date() < deadline {
            try await Task.sleep(for: .seconds(5))
            let result: PollResult
            do {
                result = try await check()
                consecutiveErrors = 0
            } catch {
                consecutiveErrors += 1
                if consecutiveErrors >= 24 {
                    throw SeedanceError.taskFailed("Lost connection to the server. Please try again later.")
                }
                continue
            }
            switch result {
            case .pending: continue
            case .done(let url):
                guard let url, !url.isEmpty else { throw SeedanceError.invalidResponse }
                return url
            case .failed(let msg):
                throw SeedanceError.taskFailed(msg ?? "The generation failed.")
            }
        }
        throw SeedanceError.taskFailed("Timed out while creating your video.")
    }

    private static func download(_ remote: String, ext: String) async throws -> URL {
        guard let url = URL(string: remote) else { throw SeedanceError.invalidResponse }
        let (temp, _) = try await URLSession.shared.download(from: url)
        let dest = URL.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).\(ext)")
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
