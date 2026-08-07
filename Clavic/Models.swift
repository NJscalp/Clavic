//
//  Models.swift
//  Clavic
//
//  Datenmodelle für Seedance-2.0-Videogenerierungen.
//

import Foundation
import SwiftData

// MARK: - Generierungs-Parameter

enum AspectRatio: String, CaseIterable, Codable, Identifiable {
    case widescreen = "16:9"
    case portrait = "9:16"
    case square = "1:1"
    case classic = "4:3"
    case vertical = "3:4"
    case cinema = "21:9"
    case adaptive = "adaptive"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .adaptive: return "Auto"
        default: return rawValue
        }
    }

    var icon: String {
        switch self {
        case .widescreen: return "rectangle.ratio.16.to.9"
        case .portrait: return "rectangle.ratio.9.to.16"
        case .square: return "square"
        case .classic: return "rectangle.ratio.4.to.3"
        case .vertical: return "rectangle.ratio.3.to.4"
        case .cinema: return "pano"
        case .adaptive: return "wand.and.stars"
        }
    }
}

enum Resolution: String, CaseIterable, Codable, Identifiable {
    case p480 = "480p"
    case p720 = "720p"

    var id: String { rawValue }
}

enum GenerationStatus: String, Codable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled

    var label: String {
        switch self {
        case .queued: return "In queue"
        case .running: return "Generating"
        case .succeeded: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool { self == .queued || self == .running }
}

// MARK: - SwiftData-Modell

@Model
final class VideoProject {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var prompt: String = ""
    /// Titel des genutzten Templates (für die Anzeige in „My Creations").
    /// Leer = freie Generierung ohne Template.
    var templateTitle: String = ""
    var ratioRaw: String = AspectRatio.widescreen.rawValue
    var resolutionRaw: String = Resolution.p720.rawValue
    var duration: Int = 5
    var generateAudio: Bool = true
    var useFastModel: Bool = false

    /// Referenzbilder als JPEG-Daten (extern gespeichert)
    @Attribute(.externalStorage) var referenceImagesData: [Data] = []
    /// Öffentliche Referenz-Video-URLs (z. B. Trend-Clip als @Video1)
    var referenceVideoURLs: [String] = []
    /// Vom Nutzer hochgeladenes Referenz-Video (Motion Studio) als Daten.
    @Attribute(.externalStorage) var referenceVideosData: [Data] = []

    var statusRaw: String = GenerationStatus.queued.rawValue
    var taskID: String?
    var errorMessage: String?
    /// Live-Fortschrittstext (z. B. „Step 3/9 · Building the house"), wird während
    /// der Generierung laufend aktualisiert → echte Echtzeit-Anzeige im UI.
    var progressStage: String = ""
    /// true, sobald die abgebuchten Credits für dieses Projekt erstattet wurden –
    /// verhindert Doppel-Refund und garantiert, dass JEDER Fehlschlag erstattet wird.
    var refunded: Bool = false
    /// true = pausierte mehrstufige Generierung mit Checkpoint → kann über
    /// „Continue" ab der Abbruchstelle fortgesetzt werden (keine erneute Abbuchung).
    var resumable: Bool = false
    /// true = Video-Generierung über Kling 3.0 Motion Control (statt Seedance 2.0).
    var useKlingMotion: Bool = false

    /// Optionaler Seedance-Modell-Override (z. B. "bytedance/seedance-2-mini" für
    /// günstige Action-Templates). Leer = Backend-Default (seedance-2-fast).
    var seedanceModel: String = ""

    /// Optionaler Vor-Edit fürs Referenzfoto (Nano Banana 2): z. B. „change the
    /// background to a beach" oder „swap the person". Läuft VOR der Video-/
    /// Motion-Generierung — ersetzt die Steuer-Prompts, die Kling Motion Control
    /// (anders als Seedance r2v) nicht unterstützt. Leer = kein Vor-Edit.
    var preEditPrompt: String = ""

    /// „Brainrot Character – reden lassen": was der Charakter sagt (TTS-Text).
    var talkText: String = ""
    /// ElevenLabs-Voice-ID für das Sprechen (echte Stimme pro Charakter).
    var talkVoice: String = ""

    /// Temporäre Remote-URL der API (läuft nach 24 h ab)
    var remoteVideoURL: String?
    /// Dateiname des lokal gespeicherten Videos im Documents-Ordner
    var localVideoFilename: String?
    /// Vorschaubild des fertigen Videos
    @Attribute(.externalStorage) var thumbnailData: Data?

    /// true = Ergebnis ist ein Bild (GPT Image 1 Edit) statt eines Videos.
    var isImageOutput: Bool = false

    /// true = Generierung läuft über kie.ai (Seedance 2.0) statt fal.ai.
    var useKie: Bool = false

    /// true = mehrstufige Musikvideo-Pipeline (Segmente + Original-Sound, siehe
    /// `MusicVideoPipeline`). Ignoriert die normale Seedance/Upscale-Logik.
    var useMusicLipSync: Bool = false

    /// Welches Pipeline-Template (Chunks/Sound/Seitenverhältnis) genutzt wird,
    /// z. B. "music" oder "nerv" – siehe `MusicVideoPipeline.configs`.
    var musicVideoKey: String = ""

    /// Upscale-Job: "image" oder "video" (nil = normale Generierung).
    var upscaleKind: String? = nil

    /// Tatsächlich abgebuchte Credits für diese Generierung. Wird bei Fehlschlag
    /// 1:1 zurückerstattet, damit nie zu viel/zu wenig erstattet wird.
    var creditCost: Int = 0

    /// Bild-Qualität für Image-Edit: "low" (1K), "medium" (2K), "high" (4K).
    var imageQuality: String = "low"

    init(
        prompt: String,
        templateTitle: String = "",
        ratio: AspectRatio,
        resolution: Resolution,
        duration: Int,
        generateAudio: Bool,
        useFastModel: Bool,
        referenceImagesData: [Data],
        referenceVideoURLs: [String] = [],
        referenceVideosData: [Data] = [],
        isImageOutput: Bool = false,
        useKie: Bool = false,
        useMusicLipSync: Bool = false,
        musicVideoKey: String = "",
        upscaleKind: String? = nil,
        creditCost: Int = 0,
        imageQuality: String = "low"
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.prompt = prompt
        self.templateTitle = templateTitle
        self.ratioRaw = ratio.rawValue
        self.resolutionRaw = resolution.rawValue
        self.duration = duration
        self.generateAudio = generateAudio
        self.useFastModel = useFastModel
        self.referenceImagesData = referenceImagesData
        self.referenceVideoURLs = referenceVideoURLs
        self.referenceVideosData = referenceVideosData
        self.isImageOutput = isImageOutput
        self.useKie = useKie
        self.useMusicLipSync = useMusicLipSync
        self.musicVideoKey = musicVideoKey
        self.upscaleKind = upscaleKind
        self.creditCost = creditCost
        self.imageQuality = imageQuality
        self.statusRaw = GenerationStatus.queued.rawValue
    }

    var ratio: AspectRatio { AspectRatio(rawValue: ratioRaw) ?? .widescreen }
    var resolution: Resolution { Resolution(rawValue: resolutionRaw) ?? .p720 }

    var status: GenerationStatus {
        get { GenerationStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    /// Lokale URL des gespeicherten Videos, falls vorhanden
    var localVideoURL: URL? {
        guard let localVideoFilename else { return nil }
        let url = URL.documentsDirectory.appending(path: localVideoFilename)
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
    }

    /// Beste verfügbare Abspiel-URL (lokal bevorzugt)
    var playbackURL: URL? {
        if let local = localVideoURL { return local }
        if let remote = remoteVideoURL { return URL(string: remote) }
        return nil
    }
}
