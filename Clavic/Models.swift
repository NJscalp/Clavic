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
    var ratioRaw: String = AspectRatio.widescreen.rawValue
    var resolutionRaw: String = Resolution.p720.rawValue
    var duration: Int = 5
    var generateAudio: Bool = true
    var useFastModel: Bool = false

    /// Referenzbilder als JPEG-Daten (extern gespeichert)
    @Attribute(.externalStorage) var referenceImagesData: [Data] = []
    /// Öffentliche Referenz-Video-URLs (z. B. Trend-Clip als @Video1)
    var referenceVideoURLs: [String] = []

    var statusRaw: String = GenerationStatus.queued.rawValue
    var taskID: String?
    var errorMessage: String?

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

    /// Upscale-Job: "image" oder "video" (nil = normale Generierung).
    var upscaleKind: String? = nil

    init(
        prompt: String,
        ratio: AspectRatio,
        resolution: Resolution,
        duration: Int,
        generateAudio: Bool,
        useFastModel: Bool,
        referenceImagesData: [Data],
        referenceVideoURLs: [String] = [],
        isImageOutput: Bool = false,
        useKie: Bool = false,
        upscaleKind: String? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.prompt = prompt
        self.ratioRaw = ratio.rawValue
        self.resolutionRaw = resolution.rawValue
        self.duration = duration
        self.generateAudio = generateAudio
        self.useFastModel = useFastModel
        self.referenceImagesData = referenceImagesData
        self.referenceVideoURLs = referenceVideoURLs
        self.isImageOutput = isImageOutput
        self.useKie = useKie
        self.upscaleKind = upscaleKind
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
