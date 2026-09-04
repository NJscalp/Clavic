//
//  Templates.swift
//  Clavic
//
//  Virale Video-Trends, eingeteilt in Nischen (Hooks, Dance, New),
//  die sich mit Seedance 2.0 (Foto + Prompt) umsetzen lassen.
//  Das Referenzfoto wird im Prompt über @Image1 angesprochen.
//
//  Vorschauen: Lege je Vorlage entweder ein Video oder ein Bild mit dem
//  Namen aus `preview` ab:
//   • Video:  <preview>.mp4  → als Datei in den Ordner "Clavic" ziehen
//             (wird automatisch ins Bundle übernommen). Spielt als Loop.
//   • Bild:   Asset namens <preview> in Assets.xcassets anlegen.
//  Reihenfolge: Video > Bild > Verlauf+Icon (Fallback).
//

import SwiftUI

enum TemplateCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case looks = "Viral Looks"
    case tools = "Clavic Tools"
    case trends = "Trends"
    case memes = "Memes"
    case dance = "Dances"
    case fancam = "Fan Cam"
    case worldcup = "World Cup"
    case backrooms = "Backrooms"
    /// Sammelbecken fuer alles Verspielte (Memes, Sport, Tanz, Backrooms).
    /// Diese Vorlagen bleiben vollstaendig erhalten, sie stehen nur nicht mehr
    /// im Weg: die Zielgruppe entscheidet in den ersten Sekunden, und dafuer
    /// zaehlen Looks und Werkzeuge, nicht Fan-Cams.
    case fun = "Fun"

    var id: String { rawValue }

    /// Symbol für das Nischen-Badge auf den Kacheln (nil = kein Badge)
    var badgeIcon: String? {
        switch self {
        case .all: return nil
        case .looks: return "sparkles"
        case .tools: return "wrench.and.screwdriver.fill"
        case .trends: return "flame.fill"
        case .memes: return "face.smiling.inverse"
        case .dance: return "figure.dance"
        case .fancam: return "sportscourt.fill"
        case .worldcup: return "soccerball"
        case .backrooms: return "door.left.hand.open"
        case .fun: return "gamecontroller.fill"
        }
    }
}

/// Eine Regel, zwei Aufrufer: die eingebauten Vorlagen und die vom Server.
/// Lagen die Bedingungen doppelt vor, wich das Verhalten frueher oder spaeter
/// auseinander — und ein ausgeblendetes Template taucht dann doch wieder auf.
enum TemplateFilter {
    static func apply(_ category: TemplateCategory, to templates: [VideoTemplate]) -> [VideoTemplate] {
        guard category != .fun else { return templates.filter(\.isHiddenFromDiscover) }
        return templates.filter { template in
            guard !template.isHiddenFromDiscover else { return false }
            guard category != .all else { return true }
            return template.category == category || template.extraCategories.contains(category)
        }
    }
}

struct VideoTemplate: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let category: TemplateCategory
    /// Erscheint ausschliesslich unter dem Fun-Chip, nirgends sonst.
    var isHiddenFromDiscover: Bool = false
    /// Zusätzliche Kategorien, in denen das Template ebenfalls erscheint
    /// (z. B. ein „New"-Template, das auch unter „Dance" auftauchen soll).
    var extraCategories: [TemplateCategory] = []
    let hashtag: String
    /// Basis-Name der Vorschau (Datei <preview>.mp4 im Bundle oder Asset <preview>)
    let preview: String
    let prompt: String
    let icon: String
    let colors: [Color]

    /// Empfohlene Voreinstellungen
    let ratio: AspectRatio
    let duration: Int
    /// Trend braucht ein eigenes Foto als Referenz
    let needsPhoto: Bool
    /// Optionales öffentliches Referenz-Video (wird als @Video1 genutzt,
    /// die Person aus dem Foto ersetzt die Person im Clip)
    var referenceVideoURL: String? = nil
    /// Geführter Modus: kein Prompt nötig, alles fix – nur Foto + Generieren.
    var isFixed: Bool = false
    /// Alternativer Prompt, wenn der Hintergrund aus dem Foto übernommen wird.
    /// Ist er nil, wird immer `prompt` (Trend-Hintergrund) genutzt.
    var promptPhotoBackground: String? = nil
    /// Bild-Trend: Ergebnis ist ein Bild (GPT Image 1 Edit) statt eines Videos.
    var isImageEdit: Bool = false
    /// Freier Bild-Editor: ein Foto + eine kurze Anweisung (Outfit ändern oder
    /// jemanden hinzufügen). Die Person bleibt dieselbe.
    var isFreeformEdit: Bool = false
    /// Character-Insert (Image-Edit): ein fester Charakter (Asset-Name) wird
    /// immer identisch ins Nutzerfoto eingefügt – keine Eingabe nötig, nur Foto.
    /// Wird zusammen mit `isImageEdit = true` verwendet.
    var characterRefAsset: String? = nil
    /// Pose-/Face-Template (Image-Edit): festes Modell-Bild (Asset-Name). Das
    /// Gesicht der Nutzerin wird auf das Modell getauscht – Outfit, Pose, Szene
    /// bleiben identisch. Nur Foto nötig. Mit `isImageEdit = true` verwenden.
    var faceTemplateAsset: String? = nil
    /// Fester-Prompt-Edit (Image-Edit): das Nutzerfoto wird mit einem festen
    /// Prompt transformiert (z. B. „Action Figure"). Keine Eingabe nötig, nur
    /// Foto + Generieren. Mit `isImageEdit = true` verwenden.
    var fixedEditPrompt: String? = nil
    /// Pinterest-Swap (Image-Edit): die Nutzerin lädt ZWEI eigene Bilder hoch –
    /// links ein Inspo-/Pinterest-Bild (z. B. Frau im schönen Dress), rechts ein
    /// Selfie. GPT Image 2 tauscht nur das Gesicht aufs Inspo-Bild (Outfit, Pose,
    /// Szene bleiben), sodass es real aussieht. Mit `isImageEdit = true`.
    var isPinterestSwap: Bool = false
    /// Foto-Enhance / „8K Upscale" (Image-Edit): nimmt ein Bild schlechter
    /// Qualität und baut es per GPT Image 2 in maximaler Auflösung (4K) fotoreal
    /// neu auf (Inhalt/Komposition bleiben). Ein-Tap: nur Foto + Generieren,
    /// keine Größen-/Qualitätswahl (immer max). Mit `isImageEdit = true` und
    /// `fixedEditPrompt` (Restore-Prompt). Ratio `.adaptive` → Original behalten.
    var isPhotoEnhance: Bool = false
    /// „Still Life" / Backrooms-Memory (Image-Edit): verwandelt das Nutzerfoto in
    /// die fehlerhaft nachgebildete Backrooms-Version (zusätzliche Augen, doppelte
    /// Münder, verschmolzene Züge, gelbe Backrooms-Szene). Der Prompt wird in
    /// CreateView ZUFÄLLIG zusammengebaut → jede Generierung sieht anders aus.
    /// Ein-Tap (nur Foto + Generieren). Mit `isImageEdit = true`.
    var isStillLife: Bool = false
    /// „Candid Späti" (Image-Edit): fotorealistischer, ungestellter Handy-Schnappschuss.
    /// Der Prompt wird in CreateView aus Szene + Vibe + (1 oder 2 Fotos) zusammengebaut –
    /// ein fester Realismus-Wrapper bleibt unsichtbar gleich. Mit `isImageEdit = true`.
    var isCandidPOV: Bool = false
    /// „Brainrot Character"-Generator: Charakter wählen + (Auto/Custom-Text) +
    /// Background-Modus → GPT-Image-2-Bild, optional sprechendes Lip-Sync-Video
    /// (Seedance + ElevenLabs-TTS + fal Lip-Sync). Mit `isImageEdit = true`.
    var isBrainrotCharacter: Bool = false
    /// „AI Character"-Generator: erzeugt bei jedem Generieren eine ANDERE,
    /// ultra-realistische, einzigartige Person (kein Nutzerfoto nötig). Nutzer
    /// wählt Geschlecht + Hautfarbe + Augenfarbe + Haarfarbe (+ optionaler
    /// Prompt); Rest wird zufällig aus Pools gezogen → 100.000+ Varianten.
    /// Läuft über GPT Image 2 (image-edit) mit neutralem grauen Seed-Bild.
    /// Mit `isImageEdit = true`.
    var isAiCharacter: Bool = false
    /// Luxury Car Selfie: Selfie + Automarke → Person im Luxus-Interieur.
    /// Mit `isImageEdit = true`.
    var isLuxuryCarSelfie: Bool = false
    /// Brainrot-DIY-Build („Tung Tung baut ein Haus"): mehrstufiges Bau-Video
    /// (BrainrotBuildPipeline). Läuft über die Music-Pipeline-Route
    /// (`useMusicLipSync = true`, `musicVideoKey = "build"` bzw. `"build_personal"`).
    /// `brainrotPersonalized = true` → Tung Tung baut im Kopf der Nutzerin (Foto
    /// nötig); false → Riesen-Objekt, kein Foto nötig (Charakter wird gestellt).
    var isBrainrotBuild: Bool = false
    var brainrotPersonalized: Bool = false
    /// AI Fruit Story: szenenweises Frucht-Drama (FruitStoryPipeline). Läuft
    /// über die Music-Pipeline-Route (`useMusicLipSync = true`,
    /// `musicVideoKey = "fruit"`). CreateView zeigt dann die Charakter-/Preset-/
    /// Stil-Auswahl; der Backend-Planner (Claude) schreibt jedes Mal eine neue
    /// Story, die mit GPT Image 2 + Veo 3.1 (sprechende Früchte) gerendert wird.
    var isFruitStory: Bool = false
    /// Diese Vorlage rendert über kie.ai (Seedance 2.0) statt fal.ai.
    var useKie: Bool = false
    /// Mehrstufiges Musikvideo/Tanz-Template: volle Länge aus Segmenten +
    /// Original-Sound (siehe `MusicVideoPipeline`). Nutzt feste, server-seitig
    /// gehostete Referenz-Chunks; `referenceVideoURL` wird dabei ignoriert.
    var useMusicLipSync: Bool = false
    /// Welches Pipeline-Template genutzt wird ("music", "nerv", …) – wählt die
    /// Chunks/Sound/Seitenverhältnis in `MusicVideoPipeline`.
    var musicVideoKey: String = ""
    /// Upscale-Werkzeug: Datei hochladen → hochskalieren ("image" oder "video").
    var upscaleKind: String? = nil
    var isUpscale: Bool { upscaleKind != nil }
    /// „Coming soon": Kachel ist sichtbar, lässt sich aber nicht öffnen.
    var comingSoon: Bool = false
    /// Archiviert: bleibt im Code (Pipelines/Flags), erscheint nicht in Discover.
    /// Zum Reaktivieren `isArchived` auf `false` setzen.
    var isArchived: Bool = false
    /// Asset-Namen für die automatische Vorher/Nachher-Vorschau (Slider).
    var previewBefore: String? = nil
    var previewAfter: String? = nil
    /// Motion Studio: Nutzer lädt eigenes Foto + eigenes Video + Prompt hoch.
    var isMotion: Bool = false
    /// true → Motion-Template geht über den Kling-Branch (Kling O3 video-edit).
    /// Seit dem O3-Umbau laufen ALLE Referenz-Video-Flows über dasselbe Modell.
    var useKlingMotion: Bool = false
    /// Optionaler Seedance-Modell-Override (z. B. "bytedance/seedance-2-mini" für
    /// günstige AI-Action-Templates). nil = Backend-Default (seedance-2-fast).
    var seedanceModel: String? = nil
    /// Server-Templates: gehostete Preview-Video-URL (statt Bundle-Datei).
    var previewRemoteURL: String? = nil
    /// Pflicht-Anzahl Nutzerfotos (1 = Standard; 2 = z. B. Du + Gegner).
    var requiredPhotoCount: Int = 1

    /// QA/Test: Ein festes Referenzfoto (Asset-Name) automatisch als @Image1
    /// vorbelegen. Dadurch kannst du Person-Wechsel testen, ohne jedes
    /// Mal manuell ein neues Foto auszuwählen.
    ///
    /// Erwartet ein Asset im Xcode-Katalog (Assets.xcassets), dessen Name
    /// exakt `presetPhotoAsset` entspricht (ohne Dateiendung).
    var presetPhotoAsset: String? = nil

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Credit-Kosten dieser Generierung. Bild-Operationen sind deutlich
    /// günstiger als Video, weil sie uns weniger kosten – so bleibt die Marge
    /// pro Credit positiv, egal ob der Nutzer Bilder oder Videos macht.
    /// Credit-Kosten in Abhängigkeit der gewählten Auflösung (480p/720p).
    /// Bild-/Upscale-Operationen sind auflösungs-unabhängig.
    func creditCost(resolution: Resolution) -> Int {
        if useMusicLipSync { return CreditCosts.musicVideo(key: musicVideoKey, resolution: resolution) }
        if isPhotoEnhance { return CreditCosts.photoEnhance }
        if useKlingMotion { return CreditCosts.klingMotionControl }
        if isImageEdit { return CreditCosts.imageEdit }
        switch upscaleKind {
        case "image": return CreditCosts.imageUpscale
        case "video": return CreditCosts.videoUpscale
        default:
            return CreditCosts.video(seconds: duration,
                                     hasReferenceVideo: referenceVideoURL != nil,
                                     resolution: resolution)
        }
    }

    /// Anzeigewert für Listen/Karten (günstigste Stufe 480p).
    var creditCost: Int { creditCost(resolution: .p480) }

    /// Nutzt dieses Template Seedance 2.0 (→ Auflösung wählbar)?
    var usesSeedance: Bool { useKie || useMusicLipSync }

    /// Bundle-URL einer Video-Vorschau, falls vorhanden.
    var previewVideoURL: URL? {
        if let previewRemoteURL, let url = URL(string: previewRemoteURL) { return url }
        return Bundle.main.url(forResource: preview, withExtension: "mp4")
    }

    /// Bild-Vorschau aus dem Asset-Katalog, falls vorhanden.
    var previewImage: UIImage? {
        UIImage(named: preview)
    }

    /// Vorher-Bild für den Vorher/Nachher-Slider, falls hinterlegt.
    var previewBeforeImage: UIImage? {
        guard let previewBefore else { return nil }
        return UIImage(named: previewBefore)
    }

    /// Nachher-Bild für den Vorher/Nachher-Slider, falls hinterlegt.
    var previewAfterImage: UIImage? {
        guard let previewAfter else { return nil }
        return UIImage(named: previewAfter)
    }
}

/// Zentrale Credit-Preise pro Modell/Aktion. An echte Provider-Kosten gekoppelt;
/// Marge siehe `CreditEconomics` (User-Preis, −30 % Apple, −API).
enum CreditCosts {
    /// Legacy-Budget für Formel-Fallbacks (nicht für Flat-Overrides).
    static let budgetPerCredit = 0.20

    static let imageEdit = 1     // Nano Banana 2 @1K (kie) – ~0,04 $
    static let imageUpscale = 1  // Topaz Image Upscale (~0,03 $)
    static let videoUpscale = 3  // Topaz Video Upscale (~0,30–0,50 $)
    /// 4K Foto-Enhance: ~0,12 $ API → 2 Cr ≈ 1,25 $ User, ~0,76 $ Profit.
    static let photoEnhance = 2
    /// Kling O3 video-edit (5 s): ~0,63 $ API → 5 Cr ≈ 3,13 $ User, satte Marge.
    static let klingMotionControl = 5

    /// Nano Banana 2 (kie): 1K / 2K / 4K — Kie-Preise ~0,04 / 0,06 / 0,09 $.
    static func imageEditCredits(quality: String) -> Int {
        switch quality.lowercased() {
        case "high": return 2    // 4K — ~0,09 $ API
        case "medium": return 1  // 2K — ~0,06 $ API
        default: return 1        // 1K — ~0,04 $ API
        }
    }

    /// Aufpreis-Faktor je Auflösung. Seedance 2.0 kostet bei 720p rund das
    /// Doppelte pro Sekunde wie bei 480p (≈2,25× mehr Pixel). Konservativ 2,0×,
    /// damit die Marge bei 720p sicher positiv bleibt.
    static func resolutionFactor(_ resolution: Resolution) -> Double {
        switch resolution {
        case .p480: return 1.0
        case .p720: return 2.0
        }
    }

    /// Anzahl Seedance-Segmente eines Pipeline-Templates (siehe
    /// `MusicVideoPipeline.configs` – hier gespiegelt für die Kostenrechnung).
    static func musicSegments(key: String) -> Int {
        switch key {
        case "music", "pdance": return 3
        case "dog": return 1       // ein Kling-Call, kein Seedance-Chunk
        case "rubberz": return 1   // ein video-edit über die volle Länge
        default: return 2          // nerv, baseball, …
        }
    }

    /// Credits @480p, verdoppelt bei 720p (`resolutionFactor`).
    private static func scaledMusicCredits(base480: Int, resolution: Resolution) -> Int {
        max(1, Int((Double(base480) * resolutionFactor(resolution)).rounded(.up)))
    }

    /// Musikvideo-/Tanz-Pipeline: Flat-Credits @480p (Sweet Spot), 720p ×2.
    static func musicVideo(key: String, resolution: Resolution) -> Int {
        // Tung-Dance: 2× Gemini Omni Flash reference-to-video @7 s ×
        // 0,16 $/s ≈ 2,24 $ echte Kosten.
        if key == "tungdance" { return 12 }
        // On the Radar Rubberz: 1× Kling O3 video-edit über die vollen ~10,9 s
        // (O3 rechnet max 10 s ab → ~1,26 $ echte Kosten; 12 Cr = fette Marge,
        // bewusst beibehalten).
        if key == "rubberz" { return 12 }
        // Brainrot-DIY-Build: ~45-s-Bausequenz aus 9 Seedance-2.0-Segmenten in
        // VOLLER Qualität (NICHT Fast → ~0,19 $/s @480p, ~2× Fast) + 9 GPT-Image-2-
        // Frames (1K). Premium-Trend-Video, entsprechend teuer.
        if key.hasPrefix("build") {
            let segments = 9.0
            let video = segments * 5.0 * 0.19 * resolutionFactor(resolution)
            let frames = segments * 0.04   // GPT Image 2 @1K pro Frame
            return max(40, Int(((video + frames) / budgetPerCredit).rounded(.up)))
        }
        // AI Fruit Story: 5 Szenen × ~8 s Veo 3.1 (sprechende Früchte, mit Ton)
        // + 5 GPT-Image-2-Keyframes (1K). Veo ist Premium → entsprechend teuer.
        // Auflösung ist hier immer 720p (Veo-Minimum), daher kein resolutionFactor.
        if key == "fruit" {
            let scenes = Double(FruitStoryCatalog.defaultSceneCount)   // 5
            let secs = Double(FruitStoryCatalog.sceneDuration)         // 8
            let video = scenes * secs * 0.08   // Veo 3.1 Fast @720p, Puffer ~0,08 $/s
            let frames = scenes * 0.012        // GPT Image 2 @1K pro Keyframe
            return max(45, Int(((video + frames) / budgetPerCredit).rounded(.up)))
        }
        // Brainrot-Charakter „reden lassen": Seedance 2.0 FAST (i2v) +
        // ElevenLabs-TTS + Lip-Sync. Kein Bild-Schritt mehr (Charakter kommt
        // aus dem Asset).
        if key == "brainrot_talk" {
            let video = 5.0 * 0.095 * resolutionFactor(resolution)   // Seedance 2.0 Fast i2v
            let extras = 0.03 + 0.12                                 // TTS + Lip-Sync
            return max(5, Int(((video + extras) / budgetPerCredit).rounded(.up)))
        }
        // Imma Bite You: 1× Kling O3 video-edit (kein Seedance-Chunk).
        if key == "dog" { return klingMotionControl }
        // You're Next Opponent: 2× Kling O3 video-edit ($0.126/s).
        if key == "you" {
            let raw = 2.0 * CreditEconomics.seedanceSegmentSeconds * 0.126
                * resolutionFactor(resolution) / budgetPerCredit
            return max(3, Int(raw.rounded(.up)))
        }

        // Flat-Overrides @480p (API ≈ Segmente × 5 s × 0,115 $/s).
        let flat480: Int? = switch key {
        case "music": 6       // 3 Segmente, ~1,73 $ API
        case "nerv", "baseball": 4   // 2 Segmente, ~1,15 $ API
        case "pdance": 6      // 3 Segmente, ~1,73 $ API
        default: nil
        }
        if let flat480 { return scaledMusicCredits(base480: flat480, resolution: resolution) }

        let perSegment = 5.0 * CreditEconomics.seedanceRefPerSecond
        let raw = Double(musicSegments(key: key)) * perSegment
            * resolutionFactor(resolution) / budgetPerCredit
        return max(3, Int(raw.rounded(.up)))
    }

    /// Video-Generierung. Kosten skalieren mit der Länge, der Auflösung und ob
    /// ein Referenz-Video genutzt wird (Referenz-Video → Kling O3 video-edit
    /// $0.126/s, ohne → Seedance 2.0 Fast i2v).
    static func video(seconds: Int, hasReferenceVideo: Bool, resolution: Resolution) -> Int {
        //   ohne Referenz (Bild→Video, Seedance 2.0 Fast): ~0,095 $/Output-Sekunde
        //   mit Referenz-Video (Kling O3 video-edit):       0,126 $/s (3–10 s)
        let perSecond = hasReferenceVideo ? 0.126 : 0.095
        let raw = Double(max(seconds, 1)) * perSecond
            * resolutionFactor(resolution) / budgetPerCredit
        return max(3, Int(raw.rounded(.up)))
    }

    /// Repräsentativer Wert fürs UI (entspricht einem typischen Trend-Video).
    static var representativeVideo: Int {
        video(seconds: 8, hasReferenceVideo: true, resolution: .p480)
    }
}

enum TemplateLibrary {
    static let all: [VideoTemplate] = [
        VideoTemplate(
            title: "Clavic Image Edit",
            subtitle: "Edit anything in your image",
            category: .tools,
            hashtag: "#ClavicEdit",
            preview: "preview_image_edit",
            prompt: "",
            icon: "photo.badge.plus.fill",
            colors: [Color(red: 0.20, green: 0.55, blue: 1.0), Color(red: 0.40, green: 0.28, blue: 0.92)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            isFreeformEdit: true,
            previewBefore: "preview_image_edit_before",
            previewAfter: "preview_image_edit_after"
        ),
        VideoTemplate(
            title: "Just the way we were wired",
            subtitle: "Drop the cursed pirate into your photo",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.backrooms],
            hashtag: "#JustTheWayWeWereWired",
            preview: "preview_captain_pirate",
            prompt: "",
            icon: "person.badge.plus",
            colors: [Color(red: 0.52, green: 0.50, blue: 0.18), Color(red: 0.12, green: 0.16, blue: 0.12)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            characterRefAsset: "pirate_captain_clark"
        ),
        VideoTemplate(
            title: "Action Figure",
            subtitle: "Turn yourself into a collectible toy",
            category: .trends,
            hashtag: "#ActionFigure",
            preview: "preview_action_figure",
            prompt: "",
            icon: "shippingbox.fill",
            colors: [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.55, green: 0.20, blue: 0.10)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: "Turn the person in this photo into a realistic collectible ACTION FIGURE displayed inside its blister-pack toy box. The figure is a faithful miniature of the person, keeping their EXACT face, hairstyle, skin tone and outfit. Add a few themed accessory items in the molded plastic tray beside the figure. The glossy cardboard header has a bold brand-style logo at the top and the person's first name in large letters, plus small 'COLLECTOR'S EDITION' text. Premium toy product photography, studio lighting, hyper-realistic plastic packaging with shine and reflections — it must look like a real photograph of a boxed collectible. The figure's face must look like a REAL person with natural skin and realistic features, NOT a cartoon, NOT a 3D/CGI render, no waxy or plastic skin on the face, no distortion, no extra limbs, no garbled text. No watermark."
        ),
        VideoTemplate(
            title: "Luxury Car Selfie",
            subtitle: "Your face, inside any hype car",
            category: .trends,
            hashtag: "#LuxuryCarSelfie",
            preview: "preview_luxury_car_selfie",
            prompt: "",
            icon: "car.fill",
            colors: [Color(red: 0.12, green: 0.12, blue: 0.16), Color(red: 0.82, green: 0.68, blue: 0.28)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            isLuxuryCarSelfie: true
        ),
        VideoTemplate(
            title: "G7X Flash",
            subtitle: "Crisp Xenon flash & warm skin",
            category: .looks,
            hashtag: "#G7XFlash",
            preview: "card_look_g7xflash",
            prompt: DigiCamStyles.prompt(id: "g7xflash"),
            icon: "bolt.circle.fill",
            colors: [Color(red: 0.92, green: 0.66, blue: 0.28), Color(red: 0.10, green: 0.07, blue: 0.06)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: DigiCamStyles.prompt(id: "g7xflash")
        ),
        VideoTemplate(
            title: "Sunset Beach",
            subtitle: "Pink dusk sky & golden rim glow",
            category: .looks,
            hashtag: "#SunsetBeach",
            preview: "card_look_sunsetbeach",
            prompt: DigiCamStyles.prompt(id: "sunsetbeach"),
            icon: "sun.max.fill",
            colors: [Color(red: 0.98, green: 0.74, blue: 0.36), Color(red: 0.10, green: 0.16, blue: 0.36)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: DigiCamStyles.prompt(id: "sunsetbeach")
        ),
        VideoTemplate(
            title: "Y2K Digicam",
            subtitle: "Cyber pop colors & CCD contrast",
            category: .looks,
            hashtag: "#Y2KDigicam",
            preview: "card_look_y2kdigicam",
            prompt: DigiCamStyles.prompt(id: "y2kdigicam"),
            icon: "camera.fill",
            colors: [Color(red: 0.86, green: 0.62, blue: 0.34), Color(red: 0.20, green: 0.14, blue: 0.10)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: DigiCamStyles.prompt(id: "y2kdigicam")
        ),
        VideoTemplate(
            title: "Sunlit Glow",
            subtitle: "Warm window rays & lush tones",
            category: .looks,
            hashtag: "#SunlitGlow",
            preview: "card_look_sunlitglow",
            prompt: DigiCamStyles.prompt(id: "sunlitglow"),
            icon: "sparkles",
            colors: [Color(red: 0.96, green: 0.94, blue: 0.88), Color(red: 0.62, green: 0.70, blue: 0.76)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: DigiCamStyles.prompt(id: "sunlitglow")
        ),
        VideoTemplate(
            title: "Clean Girl",
            subtitle: "Pure natural daylight & texture",
            category: .looks,
            hashtag: "#CleanGirl",
            preview: "card_look_cleangirl",
            prompt: DigiCamStyles.prompt(id: "cleangirl"),
            icon: "sun.haze.fill",
            colors: [Color(red: 0.94, green: 0.86, blue: 0.76), Color(red: 0.60, green: 0.50, blue: 0.42)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: DigiCamStyles.prompt(id: "cleangirl")
        ),
        VideoTemplate(
            title: "Night Flash",
            subtitle: "Late-night candid & city bokeh",
            category: .looks,
            hashtag: "#NightFlash",
            preview: "card_look_nightflash",
            prompt: DigiCamStyles.prompt(id: "nightflash"),
            icon: "car.fill",
            colors: [Color(red: 0.20, green: 0.15, blue: 0.30), Color(red: 0.05, green: 0.05, blue: 0.08)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: DigiCamStyles.prompt(id: "nightflash")
        ),
        VideoTemplate(
            title: "35mm Mono",
            subtitle: "High-contrast vintage B&W",
            category: .looks,
            hashtag: "#35mmMono",
            preview: "card_look_monomono",
            prompt: DigiCamStyles.prompt(id: "monomono"),
            icon: "circle.lefthalf.filled",
            colors: [Color(red: 0.72, green: 0.72, blue: 0.74), Color(red: 0.10, green: 0.10, blue: 0.11)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: DigiCamStyles.prompt(id: "monomono")
        ),
        VideoTemplate(
            title: "Photo Set",
            subtitle: "One selfie → a 3-shot golden-hour set",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#PhotoSet",
            preview: "preview_look_photo_set",
            prompt: ViralLooks.prompt(id: "photo-set"),
            icon: "square.grid.3x1.below.line.grid.1x2",
            colors: [Color(red: 0.62, green: 0.44, blue: 0.26), Color(red: 0.24, green: 0.16, blue: 0.12)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "photo-set")
        ),
        VideoTemplate(
            title: "Vintage Beach",
            subtitle: "Faded 35mm film on the sand",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#VintageBeach",
            preview: "preview_look_vintage_beach",
            prompt: ViralLooks.prompt(id: "vintage-beach"),
            icon: "beach.umbrella.fill",
            colors: [Color(red: 0.55, green: 0.66, blue: 0.70), Color(red: 0.86, green: 0.80, blue: 0.68)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "vintage-beach")
        ),
        VideoTemplate(
            title: "Afterglow",
            subtitle: "Black & white window light",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#Afterglow",
            preview: "preview_look_afterglow",
            prompt: ViralLooks.prompt(id: "afterglow"),
            icon: "circle.lefthalf.filled",
            colors: [Color(red: 0.30, green: 0.30, blue: 0.33), Color(red: 0.88, green: 0.88, blue: 0.90)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "afterglow")
        ),
        VideoTemplate(
            title: "Photo Sunset",
            subtitle: "Cotton-candy sky, palms, candid",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#PhotoSunset",
            preview: "preview_look_photo_sunset",
            prompt: ViralLooks.prompt(id: "photo-sunset"),
            icon: "sun.horizon.fill",
            colors: [Color(red: 0.93, green: 0.60, blue: 0.72), Color(red: 0.42, green: 0.34, blue: 0.62)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "photo-sunset")
        ),
        VideoTemplate(
            title: "Tropic Glow",
            subtitle: "Wet-look glow in the jungle",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#TropicGlow",
            preview: "preview_look_tropic_glow",
            prompt: ViralLooks.prompt(id: "tropic-glow"),
            icon: "leaf.fill",
            colors: [Color(red: 0.16, green: 0.52, blue: 0.32), Color(red: 0.94, green: 0.42, blue: 0.58)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "tropic-glow")
        ),
        VideoTemplate(
            title: "Café Window",
            subtitle: "Morning light through the glass",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#CafeWindow",
            preview: "preview_look_cafe_window",
            prompt: ViralLooks.prompt(id: "cafe-window"),
            icon: "cup.and.saucer.fill",
            colors: [Color(red: 0.78, green: 0.63, blue: 0.42), Color(red: 0.30, green: 0.21, blue: 0.14)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "cafe-window")
        ),
        VideoTemplate(
            title: "Car Seat at Night",
            subtitle: "Passenger seat, streetlights sliding past",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#CarSeatNight",
            preview: "preview_look_car_seat_night",
            prompt: ViralLooks.prompt(id: "car-seat-night"),
            icon: "car.fill",
            colors: [Color(red: 0.16, green: 0.20, blue: 0.34), Color(red: 0.05, green: 0.06, blue: 0.10)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "car-seat-night")
        ),
        VideoTemplate(
            title: "Elevator Mirror",
            subtitle: "Mirror selfie in a lift",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#ElevatorMirror",
            preview: "preview_look_elevator_mirror",
            prompt: ViralLooks.prompt(id: "elevator-mirror"),
            icon: "rectangle.portrait.on.rectangle.portrait",
            colors: [Color(red: 0.55, green: 0.57, blue: 0.62), Color(red: 0.20, green: 0.21, blue: 0.24)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "elevator-mirror")
        ),
        VideoTemplate(
            title: "Flower Market",
            subtitle: "Buckets of blooms on a bright morning",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#FlowerMarket",
            preview: "preview_look_flower_market",
            prompt: ViralLooks.prompt(id: "flower-market"),
            icon: "camera.macro",
            colors: [Color(red: 0.90, green: 0.52, blue: 0.60), Color(red: 0.34, green: 0.45, blue: 0.32)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "flower-market")
        ),
        VideoTemplate(
            title: "Rooftop at Dusk",
            subtitle: "City skyline, last blue light",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#RooftopDusk",
            preview: "preview_look_rooftop_dusk",
            prompt: ViralLooks.prompt(id: "rooftop-dusk"),
            icon: "building.2.fill",
            colors: [Color(red: 0.22, green: 0.30, blue: 0.60), Color(red: 0.86, green: 0.44, blue: 0.22)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "rooftop-dusk")
        ),
        VideoTemplate(
            title: "Morning in Bed",
            subtitle: "First light, rumpled sheets",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#MorningInBed",
            preview: "preview_look_morning_bed",
            prompt: ViralLooks.prompt(id: "morning-bed"),
            icon: "bed.double.fill",
            colors: [Color(red: 0.94, green: 0.84, blue: 0.72), Color(red: 0.52, green: 0.40, blue: 0.34)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "morning-bed")
        ),
        VideoTemplate(
            title: "Rain & Streetlight",
            subtitle: "Wet pavement, amber glow",
            category: .looks,
            extraCategories: [.trends],
            hashtag: "#RainStreetlight",
            preview: "preview_look_rain_streetlight",
            prompt: ViralLooks.prompt(id: "rain-streetlight"),
            icon: "cloud.rain.fill",
            colors: [Color(red: 0.92, green: 0.60, blue: 0.20), Color(red: 0.08, green: 0.12, blue: 0.24)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: ViralLooks.prompt(id: "rain-streetlight")
        ),
        VideoTemplate(
            title: "Brainrot Character",
            subtitle: "Pick a character, drop a line, go viral",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.trends],
            hashtag: "#brainrot",
            preview: "preview_brainrot_character",
            prompt: "",
            icon: "theatermasks.fill",
            colors: [Color(red: 0.55, green: 0.20, blue: 0.85), Color(red: 0.10, green: 0.10, blue: 0.20)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: false,
            isImageEdit: true,
            isBrainrotCharacter: true
        ),
        VideoTemplate(
            title: "AI Character",
            subtitle: "Generate a unique realistic person every time",
            category: .tools,
            extraCategories: [.trends],
            hashtag: "#AICharacter",
            preview: "preview_ai_character",
            prompt: "",
            icon: "person.crop.rectangle.stack.fill",
            colors: [Color(red: 0.30, green: 0.55, blue: 0.95), Color(red: 0.55, green: 0.25, blue: 0.85)],
            ratio: .square,
            duration: 0,
            needsPhoto: false,
            isImageEdit: true,
            isAiCharacter: true
        ),
        VideoTemplate(
            title: "If you grab me imma bite you",
            subtitle: "Make your photo do the viral dance",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.dance],
            hashtag: "#ImmaBiteYou",
            preview: "preview_dog",
            prompt: "Replace the main subject in the reference video with the subject from the photo. Keep the same body movements, head motion and timing from the reference video and keep the scene. Preserve the exact identity, fur/skin, colors, face and look of the subject from the photo so it clearly looks like them performing the motion. Family-friendly, wholesome, photorealistic, looks like a real phone video, natural smooth motion, no morphing, no distortion, no extra limbs, no text, no watermark.",
            icon: "pawprint.fill",
            colors: [Color(red: 0.42, green: 0.62, blue: 0.95), Color(red: 0.18, green: 0.30, blue: 0.55)],
            ratio: .portrait,
            duration: 12,
            needsPhoto: true,
            isFixed: true,
            useMusicLipSync: true,
            musicVideoKey: "dog"
        ),
        // Läuft unter der Haube über Kling O3 (Omni 3) video-edit auf WaveSpeed —
        // Person aus dem Foto ersetzt die Person im Video, Rest bleibt 1:1.
        VideoTemplate(
            title: "Kling Omni 3 Motion Control",
            subtitle: "Family-friendly dance or sports clips only",
            category: .tools,
            extraCategories: [.dance],
            hashtag: "#MotionControl",
            preview: "preview_motion",
            prompt: "Replace the main person in the reference video @Video1 with the person from @Image1. Keep exactly the same movements, dance, body language, motion and timing from @Video1, and keep the scene. Preserve the exact identity, face and hair of the person from @Image1. Photorealistic, natural skin, looks like real footage, no morphing, no distortion. No text, no watermark.",
            icon: "figure.run.circle.fill",
            colors: [Color(red: 0.20, green: 0.50, blue: 0.95), Color(red: 0.55, green: 0.25, blue: 0.90)],
            ratio: .portrait,
            duration: 5,
            needsPhoto: true,
            useKie: true,
            isMotion: true
        ),
        // Archiviert: war das separate "Kling 3.0 Motion Control"-Template —
        // seit dem Umbau auf Kling O3 video-edit identisch mit "Kling Omni 3
        // Motion Control" oben, daher ausgeblendet.
        VideoTemplate(
            title: "Kling 3.0 Motion Control",
            subtitle: "Your photo + a family-friendly dance video",
            category: .tools,
            extraCategories: [.dance],
            hashtag: "#MotionControl",
            preview: "preview_kling_motion",
            prompt: "Replace the person in the reference video with the person from the image. Keep exactly the same movements, body motion and timing, and keep the scene. Preserve the exact identity, face and hair of the person from the image. Photorealistic, natural, looks like real footage, no morphing, no distortion. No text, no watermark.",
            icon: "figure.dance.circle.fill",
            colors: [Color(red: 0.95, green: 0.30, blue: 0.55), Color(red: 0.45, green: 0.20, blue: 0.85)],
            ratio: .portrait,
            duration: 5,
            needsPhoto: true,
            useKie: true,
            isArchived: true,
            isMotion: true,
            useKlingMotion: true
        ),
        VideoTemplate(
            title: "Du bist gut Genug",
            subtitle: "Star in a cinematic music video",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.trends],
            hashtag: "#MusicVideo",
            preview: "preview_music_video",
            prompt: "Replace the person in the reference video @Video1 with the person from @Image1. Keep exactly the same movements, body language, head motion and the lip movements and mouth shapes and the precise timing from @Video1, and keep the entire scene: a cinematic high-contrast black-and-white music video, a single artist performing under a bright spotlight on a dark stage with silhouetted dancers and speaker stacks in the background. The artist wears a stylish black leather jacket. Keep the same camera work, dramatic spotlight lighting, film grain and black-and-white look. Preserve the exact identity, face, facial features and hair of the person from @Image1 so it clearly looks like that real person filmed live on stage. Photorealistic, natural skin texture and realistic detail, looks like real footage, not AI-generated, no morphing, no distortion. No text, no names, no captions, no watermark, no writing anywhere in the frame. 16:9 widescreen",
            icon: "music.mic",
            colors: [Color(red: 0.15, green: 0.15, blue: 0.18), Color(red: 0.55, green: 0.55, blue: 0.62)],
            ratio: .widescreen,
            duration: 10,
            needsPhoto: true,
            referenceVideoURL: "https://limitless-web-beryl.vercel.app/music-reference.mp4",
            isFixed: true,
            useKie: true,
            useMusicLipSync: true,
            musicVideoKey: "music"
        ),
        VideoTemplate(
            title: "Nervy Backrooms",
            subtitle: "Dance in the backrooms",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.dance],
            hashtag: "#NervyBackrooms",
            preview: "preview_nerv_backrooms",
            prompt: "Replace the person in the reference video @Video1 with the person from @Image1. Keep exactly the same dance, movements, body language, head motion and the precise timing from @Video1, keep the same pirate costume the dancer is wearing, and keep the entire scene: an empty yellow 'backrooms' liminal space with a low ceiling of fluorescent lights and bare carpet. Preserve the exact identity, face, facial features and hair of the person from @Image1 so it clearly looks like that real person dancing there. Photorealistic, natural skin texture and realistic detail, looks like real footage, not AI-generated, no morphing, no distortion. No text, no captions, no watermark anywhere in the frame. 9:16 vertical",
            icon: "figure.dance",
            colors: [Color(red: 0.85, green: 0.78, blue: 0.30), Color(red: 0.55, green: 0.50, blue: 0.15)],
            ratio: .portrait,
            duration: 8,
            needsPhoto: true,
            isFixed: true,
            useKie: true,
            useMusicLipSync: true,
            musicVideoKey: "nerv"
        ),
        VideoTemplate(
            title: "Backrooms Dance",
            subtitle: "Do the viral backrooms dance",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.backrooms],
            hashtag: "#BackroomsDance",
            preview: "preview_pdance",
            prompt: "Replace the dancing person in the reference video @Video1 with the person from @Image1. Keep exactly the same dance, movements, body language and precise timing, keep the same costume the dancer is wearing, and keep the entire scene: the empty yellow 'backrooms' liminal space with fluorescent ceiling lights. Preserve the exact identity, face, facial features and hair of the person from @Image1 so it clearly looks like that real person dancing. Photorealistic, natural skin texture, looks like real footage, not AI-generated, no morphing, no distortion. No text, no captions, no watermark. 1:1 square",
            icon: "figure.dance",
            colors: [Color(red: 0.90, green: 0.78, blue: 0.25), Color(red: 0.45, green: 0.40, blue: 0.12)],
            ratio: .square,
            duration: 12,
            needsPhoto: true,
            isFixed: true,
            promptPhotoBackground: "Keep exactly the same dance, movements and precise timing from the reference video @Video1, but use the person from @Image1 with their exact face and hair and place them dancing in their own real background and environment taken from @Image1 (not the backrooms). Photorealistic, natural skin texture, looks like real footage, not AI-generated, no morphing, no distortion. No text, no captions, no watermark. 1:1 square",
            useKie: true,
            useMusicLipSync: true,
            musicVideoKey: "pdance"
        ),
        VideoTemplate(
            title: "Tung Tung Sahur Dance",
            subtitle: "Dance in sync with Tung Tung Tung Sahur",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.trends, .memes],
            hashtag: "#TungTungTungSahur",
            preview: "preview_tung_dance",
            prompt: "Replace ONLY the human on the left of @Video1 with the person from @Image1 (same face, hair, outfit) doing the exact same synchronized dance and timing. Keep the wooden Tung Tung Tung Sahur character on the right completely unchanged, and keep the same driveway background. Photorealistic, real footage look, no morphing, no text, no watermark. 9:16 vertical",
            icon: "figure.dance",
            colors: [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.85, green: 0.28, blue: 0.45)],
            ratio: .portrait,
            duration: 14,
            needsPhoto: true,
            isFixed: true,
            useKie: true,
            useMusicLipSync: true,
            musicVideoKey: "tungdance"
        ),
        VideoTemplate(
            title: "On the Radar Rubberz",
            subtitle: "Rap the viral Rubberz freestyle — only you get swapped in",
            category: .trends,
            extraCategories: [.memes, .dance],
            hashtag: "#OnTheRadar",
            preview: "preview_rubberz",
            prompt: "Replace ONLY the rapper performing into the standing microphone in @Video1 with the person from @Image1 — their exact face, hair, skin tone and body, wearing their own outfit, performing the EXACT same freestyle rap, mouth movements, hand gestures, head motion and timing, fully lip-synced. Keep the green neon ON THE RADAR studio, microphone, lighting and camera framing COMPLETELY unchanged. Photorealistic, real footage look, sharp detail, no morphing, no watermark, no text. 9:16 vertical",
            icon: "music.mic",
            colors: [Color(red: 0.10, green: 0.85, blue: 0.35), Color(red: 0.02, green: 0.20, blue: 0.08)],
            ratio: .portrait,
            duration: 11,
            needsPhoto: true,
            isFixed: true,
            useKie: true,
            useMusicLipSync: true,
            musicVideoKey: "rubberz"
        ),
        // MARK: - Archiviert (nicht in Discover — Pipelines bleiben im Code)
        VideoTemplate(
            title: "Tung Tung Builds a House",
            subtitle: "Triple T builds inside a giant fruit",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.trends],
            hashtag: "#TungTungBuild",
            preview: "preview_tung_build",
            prompt: "",
            icon: "hammer.fill",
            colors: [Color(red: 0.95, green: 0.45, blue: 0.20), Color(red: 0.55, green: 0.25, blue: 0.10)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: false,
            isBrainrotBuild: true,
            brainrotPersonalized: false,
            useMusicLipSync: true,
            musicVideoKey: "build",
            isArchived: true
        ),
        VideoTemplate(
            title: "AI Fruit Story",
            subtitle: "Talking 3D fruit drama — a new story every time",
            category: .trends,
            extraCategories: [.memes],
            hashtag: "#AIFruitStory",
            preview: "preview_fruit_story",
            prompt: "",
            icon: "leaf.fill",
            colors: [Color(red: 0.98, green: 0.55, blue: 0.30), Color(red: 0.85, green: 0.20, blue: 0.35)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: false,
            isFruitStory: true,
            useMusicLipSync: true,
            musicVideoKey: "fruit",
            isArchived: true
        ),
        VideoTemplate(
            title: "Tung Tung Builds in Your Head",
            subtitle: "Triple T builds a house inside YOU",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.trends],
            hashtag: "#TungTungBuild",
            preview: "preview_tung_build_you",
            prompt: "",
            icon: "hammer.fill",
            colors: [Color(red: 0.95, green: 0.55, blue: 0.25), Color(red: 0.50, green: 0.22, blue: 0.30)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isFixed: true,
            isBrainrotBuild: true,
            brainrotPersonalized: true,
            useMusicLipSync: true,
            musicVideoKey: "build_personal",
            isArchived: true
        ),
        VideoTemplate(
            title: "Still Life",
            subtitle: "The backrooms' creepy memory of you",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.memes],
            hashtag: "#StillLife",
            preview: "preview_still_life",
            prompt: "",
            icon: "eye.trianglebadge.exclamationmark.fill",
            colors: [Color(red: 0.82, green: 0.74, blue: 0.20), Color(red: 0.35, green: 0.30, blue: 0.08)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            isStillLife: true
        ),

        // MARK: - Fan-Cam-Trend (Stadion-Broadcast „caught on camera")

        VideoTemplate(
            title: "Baseball Fan Cam",
            subtitle: "Caught on the stadium cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.trends],
            hashtag: "#FanCam",
            preview: "preview_baseball_fancam",
            prompt: "In the reference video @Video1, replace ONLY the person sitting in the stadium stands with the person from @Image1. Keep everything else exactly the same: the live baseball broadcast look, the stadium crowd behind, the scoreboard and TV graphics overlay, the camera framing and the exact same subtle motion and timing (glancing around, slightly self-aware as if just caught on the fan cam). Preserve the exact identity, face, facial features and hair of the person from @Image1. Photorealistic real broadcast footage, natural detailed skin, no plastic or AI look, no morphing, no distortion. No added text or watermark. 4:3",
            icon: "baseball.fill",
            colors: [Color(red: 0.12, green: 0.35, blue: 0.70), Color(red: 0.80, green: 0.20, blue: 0.25)],
            ratio: .classic,
            duration: 10,
            needsPhoto: true,
            isFixed: true,
            useKie: true,
            useMusicLipSync: true,
            musicVideoKey: "baseball"
        ),
        VideoTemplate(
            title: "Basketball Fan Cam",
            subtitle: "Caught on the arena cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.trends],
            hashtag: "#FanCam",
            preview: "preview_basketball_fancam",
            prompt: "Place the person from @Image1 sitting courtside in the stands at a packed basketball arena, shown live on the arena jumbotron / TV broadcast camera with a scoreboard and sports graphics overlay, glancing around and reacting slightly as if just caught on the fan cam. Preserve the exact identity, face, facial features and hair of the person from @Image1. Photorealistic real broadcast footage, natural detailed skin, no plastic or AI look, no morphing. No added text or watermark. 4:3",
            icon: "basketball.fill",
            colors: [Color(red: 0.85, green: 0.45, blue: 0.12), Color(red: 0.55, green: 0.20, blue: 0.10)],
            ratio: .classic,
            duration: 5,
            needsPhoto: true,
            isFixed: true,
            useKie: true
        ),
        VideoTemplate(
            title: "Football Fan Cam",
            subtitle: "Caught on the stadium cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.trends],
            hashtag: "#FanCam",
            preview: "preview_football_fancam",
            prompt: "Place the person from @Image1 sitting in the stands at a packed American football stadium, shown live on the stadium big screen / TV broadcast camera with a scoreboard and sports graphics overlay, glancing around and reacting slightly as if just caught on the fan cam. Preserve the exact identity, face, facial features and hair of the person from @Image1. Photorealistic real broadcast footage, natural detailed skin, no plastic or AI look, no morphing. No added text or watermark. 4:3",
            icon: "football.fill",
            colors: [Color(red: 0.18, green: 0.50, blue: 0.25), Color(red: 0.10, green: 0.25, blue: 0.15)],
            ratio: .classic,
            duration: 5,
            needsPhoto: true,
            isFixed: true,
            useKie: true
        ),

        // MARK: - World-Cup-Fan-Cam (je Land eine Frau im Nationaltrikot, nur Farben)

        VideoTemplate(
            title: "Brazil Fan Cam",
            subtitle: "World Cup fan cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.fancam],
            hashtag: "#WorldCup",
            preview: "preview_wc_brazil",
            prompt: "Place the person from @Image1 as a fan in the stands at a packed World Cup soccer stadium, wearing a bright yellow football jersey with green trim (Brazil national team colours) — team colours only, no logos, no text, no brand marks. Shown live on the stadium big screen / TV broadcast camera with a scoreboard and graphics overlay, cheering and reacting as if just caught on the fan cam. Preserve the exact identity, face and hair of the person from @Image1. Photorealistic real broadcast footage, natural skin, no plastic or AI look, no morphing. No added watermark. 4:3",
            icon: "soccerball",
            colors: [Color(red: 0.95, green: 0.80, blue: 0.10), Color(red: 0.10, green: 0.55, blue: 0.25)],
            ratio: .classic, duration: 5, needsPhoto: true, isFixed: true, useKie: true
        ),
        VideoTemplate(
            title: "Argentina Fan Cam",
            subtitle: "World Cup fan cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.fancam],
            hashtag: "#WorldCup",
            preview: "preview_wc_argentina",
            prompt: "Place the person from @Image1 as a fan in the stands at a packed World Cup soccer stadium, wearing a football jersey with light blue and white vertical stripes (Argentina national team colours) — team colours only, no logos, no text, no brand marks. Shown live on the stadium big screen / TV broadcast camera with a scoreboard and graphics overlay, cheering and reacting as if just caught on the fan cam. Preserve the exact identity, face and hair of the person from @Image1. Photorealistic real broadcast footage, natural skin, no plastic or AI look, no morphing. No added watermark. 4:3",
            icon: "soccerball",
            colors: [Color(red: 0.45, green: 0.70, blue: 0.92), Color(red: 0.92, green: 0.92, blue: 0.95)],
            ratio: .classic, duration: 5, needsPhoto: true, isFixed: true, useKie: true
        ),
        VideoTemplate(
            title: "France Fan Cam",
            subtitle: "World Cup fan cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.fancam],
            hashtag: "#WorldCup",
            preview: "preview_wc_france",
            prompt: "Place the person from @Image1 as a fan in the stands at a packed World Cup soccer stadium, wearing a deep blue football jersey with subtle red and white trim (France national team colours) — team colours only, no logos, no text, no brand marks. Shown live on the stadium big screen / TV broadcast camera with a scoreboard and graphics overlay, cheering and reacting as if just caught on the fan cam. Preserve the exact identity, face and hair of the person from @Image1. Photorealistic real broadcast footage, natural skin, no plastic or AI look, no morphing. No added watermark. 4:3",
            icon: "soccerball",
            colors: [Color(red: 0.12, green: 0.20, blue: 0.55), Color(red: 0.80, green: 0.15, blue: 0.20)],
            ratio: .classic, duration: 5, needsPhoto: true, isFixed: true, useKie: true
        ),
        VideoTemplate(
            title: "England Fan Cam",
            subtitle: "World Cup fan cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.fancam],
            hashtag: "#WorldCup",
            preview: "preview_wc_england",
            prompt: "Place the person from @Image1 as a fan in the stands at a packed World Cup soccer stadium, wearing a white football jersey with subtle navy trim (England national team colours) — team colours only, no logos, no text, no brand marks. Shown live on the stadium big screen / TV broadcast camera with a scoreboard and graphics overlay, cheering and reacting as if just caught on the fan cam. Preserve the exact identity, face and hair of the person from @Image1. Photorealistic real broadcast footage, natural skin, no plastic or AI look, no morphing. No added watermark. 4:3",
            icon: "soccerball",
            colors: [Color(red: 0.92, green: 0.92, blue: 0.95), Color(red: 0.70, green: 0.12, blue: 0.18)],
            ratio: .classic, duration: 5, needsPhoto: true, isFixed: true, useKie: true
        ),
        VideoTemplate(
            title: "Spain Fan Cam",
            subtitle: "World Cup fan cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.fancam],
            hashtag: "#WorldCup",
            preview: "preview_wc_spain",
            prompt: "Place the person from @Image1 as a fan in the stands at a packed World Cup soccer stadium, wearing a red football jersey with yellow and navy trim (Spain national team colours) — team colours only, no logos, no text, no brand marks. Shown live on the stadium big screen / TV broadcast camera with a scoreboard and graphics overlay, cheering and reacting as if just caught on the fan cam. Preserve the exact identity, face and hair of the person from @Image1. Photorealistic real broadcast footage, natural skin, no plastic or AI look, no morphing. No added watermark. 4:3",
            icon: "soccerball",
            colors: [Color(red: 0.80, green: 0.12, blue: 0.15), Color(red: 0.95, green: 0.78, blue: 0.10)],
            ratio: .classic, duration: 5, needsPhoto: true, isFixed: true, useKie: true
        ),
        VideoTemplate(
            title: "Germany Fan Cam",
            subtitle: "World Cup fan cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.fancam],
            hashtag: "#WorldCup",
            preview: "preview_wc_germany",
            prompt: "Place the person from @Image1 as a fan in the stands at a packed World Cup soccer stadium, wearing a white football jersey with black trim (Germany national team colours) — team colours only, no logos, no text, no brand marks. Shown live on the stadium big screen / TV broadcast camera with a scoreboard and graphics overlay, cheering and reacting as if just caught on the fan cam. Preserve the exact identity, face and hair of the person from @Image1. Photorealistic real broadcast footage, natural skin, no plastic or AI look, no morphing. No added watermark. 4:3",
            icon: "soccerball",
            colors: [Color(red: 0.20, green: 0.20, blue: 0.22), Color(red: 0.92, green: 0.92, blue: 0.95)],
            ratio: .classic, duration: 5, needsPhoto: true, isFixed: true, useKie: true
        ),
        VideoTemplate(
            title: "Portugal Fan Cam",
            subtitle: "World Cup fan cam",
            category: .fun,
            isHiddenFromDiscover: true,
            extraCategories: [.fancam],
            hashtag: "#WorldCup",
            preview: "preview_wc_portugal",
            prompt: "Place the person from @Image1 as a fan in the stands at a packed World Cup soccer stadium, wearing a dark red and maroon football jersey with green trim (Portugal national team colours) — team colours only, no logos, no text, no brand marks. Shown live on the stadium big screen / TV broadcast camera with a scoreboard and graphics overlay, cheering and reacting as if just caught on the fan cam. Preserve the exact identity, face and hair of the person from @Image1. Photorealistic real broadcast footage, natural skin, no plastic or AI look, no morphing. No added watermark. 4:3",
            icon: "soccerball",
            colors: [Color(red: 0.60, green: 0.10, blue: 0.15), Color(red: 0.10, green: 0.40, blue: 0.25)],
            ratio: .classic, duration: 5, needsPhoto: true, isFixed: true, useKie: true
        ),
        VideoTemplate(
            title: "Lego Trend",
            subtitle: "Put yourself in the Lego clip",
            category: .trends,
            hashtag: "#LegoTrend",
            preview: "preview_lego",
            prompt: "Replace the person in the reference video @Video1 with the person from @Image1, keep exactly the same movements, poses and the entire scene from @Video1: a bedroom with shelves full of built Lego sets, the person holds and balances various Lego models (Lego flower bouquet, Lego radio). Same camera work and lighting. Preserve the identity, face and hair of the person from @Image1. No text, no subtitles, no writing in the image, 9:16 vertical",
            icon: "cube.fill",
            colors: [Color(red: 0.98, green: 0.78, blue: 0.12), Color(red: 0.90, green: 0.20, blue: 0.18)],
            ratio: .portrait,
            duration: 8,
            needsPhoto: true,
            referenceVideoURL: "https://limitless-web-beryl.vercel.app/lego-reference.mp4",
            isFixed: true,
            promptPhotoBackground: "Keep exactly the movements, poses and timing from the reference video @Video1: the person holds and balances various Lego models (Lego flower bouquet, Lego radio). Use the person from @Image1 with their face and hair and place them into the environment and background from @Image1. Same camera work and lighting as in the video. No text, no subtitles, no writing in the image, 9:16 vertical",
            useKie: true
        ),
        // MARK: - AI Action POV (viral „impossible stunt"-Trend, Seedance 2.0 Fast)
        VideoTemplate(
            title: "Water Stunt POV",
            subtitle: "Run on water like a superhero",
            category: .trends,
            extraCategories: [.fancam],
            hashtag: "#AIStunt",
            preview: "preview_water_stunt",
            prompt: "Viral AI action sequence with seamless scene cuts. It STARTS with the person standing exactly as in @Image1, then they turn and run away from the camera into the next shot. They leap off a high ledge and perform acrobatic mid-air flips and somersaults, then land flat in a Superman flying pose landing ON TOP of the water surface — skimming on top of the water, NOT diving in and NOT splashing under it — and immediately sprint and glide super fast across the surface of the water into the distance, water spraying behind them. Dynamic action camera, bright sunny ocean, hyperreal, looks like a real viral AI clip. Keep the exact same face, hair, body and clothes of the person from @Image1. No text, no watermark. 9:16 vertical",
            icon: "figure.open.water.swim",
            colors: [Color(red: 0.10, green: 0.55, blue: 0.85), Color(red: 0.05, green: 0.22, blue: 0.50)],
            ratio: .portrait,
            duration: 10,
            needsPhoto: true,
            isFixed: true,
            useKie: true
        ),
        VideoTemplate(
            title: "Sunset Dunk POV",
            subtitle: "Throw down an impossible dunk",
            category: .trends,
            extraCategories: [.fancam],
            hashtag: "#AIDunk",
            preview: "preview_sunset_dunk",
            prompt: "Cinematic viral streetball POV. The exact same person from @Image1 dribbles a basketball and drives down an outdoor court at golden-hour sunset with a hyped crowd watching, then jumps impossibly high and slams a huge dunk on the hoop, dynamic action camera, energy and dust, the crowd reacting wildly, ending on a hero close-up. Hyperreal, looks like a real viral AI action clip. Keep the exact face, hair and identity of the person from @Image1. No text, no watermark. 9:16 vertical",
            icon: "basketball.fill",
            colors: [Color(red: 0.95, green: 0.45, blue: 0.15), Color(red: 0.45, green: 0.15, blue: 0.30)],
            ratio: .portrait,
            duration: 10,
            needsPhoto: true,
            isFixed: true,
            useKie: true
        ),
        // MARK: - Bull Charge (viraler „Stier rammt dich, du stehst auf und besiegst ihn"-Trend)
        VideoTemplate(
            title: "Bull Charge",
            subtitle: "A bull rams you — you get up and beat it",
            category: .trends,
            extraCategories: [.fancam],
            hashtag: "#BullCharge",
            preview: "preview_bull_charge",
            prompt: "The video STARTS (0–2s) with the person exactly as in @Image1, same pose, outfit, hair and scene. Then a realistic, natural bull with DARK eyes — NO glowing eyes, NO supernatural or magic elements — CHARGES IN from the left at full running speed and its HEAD AND HORNS MAKE HARD PHYSICAL CONTACT with the person's body, literally hitting and lifting them (2–4s). The real impact sends the person flying horizontally through the air and they SLAM BACK-FIRST into the wall behind them, cracking the wall and kicking up real dust and rubble (4–6s). The person drops to the ground, then determinedly pushes back to their feet into a fighting stance (6–7s). Then the person FIGHTS BACK: they grab the bull's horns or land a real punch and WRESTLE the bull DOWN to the ground, overpowering it, and stand victorious over the defeated bull as the dust settles (7–10s). CRITICAL: realistic physics with real weight and momentum — the bull must visibly MAKE CONTACT to throw the person, NO invisible force, NO magic flinging. Keep the EXACT face, identity, hair, body and outfit of the person from @Image1 throughout. Keep the same scene and background from @Image1. Photorealistic, cinematic action, dynamic camera, natural motion, looks like a real viral action-movie clip. No morphing, no distortion, no extra limbs, no glowing eyes, no body parts fusing together. No text, no watermark. 9:16 vertical",
            icon: "figure.martialarts",
            colors: [Color(red: 0.85, green: 0.18, blue: 0.18), Color(red: 0.20, green: 0.10, blue: 0.08)],
            ratio: .portrait,
            duration: 10,
            needsPhoto: true,
            isFixed: true,
            useKie: true
        ),
        VideoTemplate(
            title: "8K Upscale",
            subtitle: "Rebuild a blurry photo in crisp quality",
            category: .tools,
            hashtag: "#8KUpscale",
            preview: "preview_8k_after",
            prompt: "",
            icon: "wand.and.stars.inverse",
            colors: [Color(red: 0.10, green: 0.70, blue: 0.75), Color(red: 0.08, green: 0.35, blue: 0.55)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: "Restore and dramatically enhance this low-quality photo into a crisp, ultra-high-resolution, photorealistic image. Remove all blur, noise, pixelation, JPEG compression artifacts and graininess, and reconstruct fine realistic detail: sharp facial features, natural detailed skin with visible pores and texture, individual hair strands, fabric weave, crisp edges and accurate true-to-life lighting — as if it were re-shot with a professional high-end camera. CRITICAL: keep the EXACT same content, composition, framing, pose, identity, faces, expressions, colors and background — do NOT change, add, remove, restyle or beautify anything, only increase quality, sharpness and resolution. The result must look like a 100% real, natural photograph, never AI-generated: no plastic, waxy, airbrushed or over-smoothed skin, no painted, doll-like or CGI look, no distortion or warping, no invented details that were not in the original. No text, no watermark.",
            isPhotoEnhance: true,
            previewBefore: "preview_8k_before",
            previewAfter: "preview_8k_after"
        ),
        VideoTemplate(
            title: "Pro Glow",
            subtitle: "Better light, professional photo look",
            category: .tools,
            hashtag: "#ProGlow",
            preview: "preview_pro_glow_after",
            prompt: "",
            icon: "sun.max.fill",
            colors: [Color(red: 0.98, green: 0.78, blue: 0.42), Color(red: 0.85, green: 0.45, blue: 0.55)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            fixedEditPrompt: "Keep the person, their face, identity, pose, outfit, hair and the entire scene EXACTLY the same — do not change, add or remove anything. Only turn this into a polished, professional-looking photograph: enhance the lighting so it looks beautifully and professionally lit with soft flattering light and natural depth, improve the color grading, white balance, contrast and dynamic range, gently fix harsh shadows and any overexposure, and add subtle professional polish so it looks like it was shot by a professional photographer with a high-end camera. Keep it 100% photorealistic and natural: natural detailed skin, no plastic or waxy or over-smoothed skin, no beauty filter, no CGI look, no distortion, no changes to the subject's features or body. No text, no watermark.",
            isPhotoEnhance: true,
            previewBefore: "preview_pro_glow_before",
            previewAfter: "preview_pro_glow_after"
        ),
        VideoTemplate(
            title: "Image Upscale",
            subtitle: "Sharpen & enlarge a photo",
            category: .tools,
            hashtag: "#Upscale",
            preview: "preview_image_upscale",
            prompt: "",
            icon: "arrow.up.left.and.arrow.down.right.circle.fill",
            colors: [Color(red: 0.20, green: 0.60, blue: 0.95), Color(red: 0.15, green: 0.35, blue: 0.80)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: true,
            upscaleKind: "image",
            previewBefore: "preview_image_upscale_before",
            previewAfter: "preview_image_upscale_after"
        ),
        VideoTemplate(
            title: "Video Upscale",
            subtitle: "Boost your video quality",
            category: .tools,
            hashtag: "#Upscale",
            preview: "preview_video_upscale",
            prompt: "",
            icon: "arrow.up.forward.app.fill",
            colors: [Color(red: 0.45, green: 0.30, blue: 0.90), Color(red: 0.25, green: 0.18, blue: 0.65)],
            ratio: .adaptive,
            duration: 0,
            needsPhoto: false,
            upscaleKind: "video",
            previewBefore: "preview_video_upscale_before",
            previewAfter: "preview_video_upscale_after"
        )
    ]

    /// Nur Templates die in Discover/Listen erscheinen (ohne `isArchived` und ohne verbotene Inhalte).
    static var visible: [VideoTemplate] {
        all.filter { !$0.isArchived && ContentPolicy.isAllowedTemplate($0) }
    }

    static func filtered(by category: TemplateCategory) -> [VideoTemplate] {
        TemplateFilter.apply(category, to: visible)
    }

    static var trending: [VideoTemplate] {
        Array(visible.prefix(5))
    }

    static var featured: VideoTemplate { all[0] }
}

// MARK: - Server-gesteuerte Templates (Remote, ohne App-Update)

extension Color {
    /// Erzeugt eine Farbe aus einem Hex-String (z. B. "#1E8BFF" oder "1E8BFF").
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self = Color(red: Double((v >> 16) & 0xFF) / 255,
                         green: Double((v >> 8) & 0xFF) / 255,
                         blue: Double(v & 0xFF) / 255)
        } else {
            self = Color(red: 0.4, green: 0.3, blue: 0.9)
        }
    }
}

/// JSON-Schema für ein vom Server geladenes Template (templates.json).
struct RemoteTemplate: Codable {
    var title: String
    var subtitle: String = ""
    var category: String = "new"
    var extraCategories: [String] = []
    var hashtag: String = ""
    var previewURL: String? = nil
    var prompt: String = ""
    var promptPhotoBackground: String? = nil
    var icon: String = "sparkles"
    var colors: [String] = []
    var ratio: String = "9:16"
    var duration: Int = 5
    var needsPhoto: Bool = true
    var referenceVideoURL: String? = nil
    var isFixed: Bool = false
    var isImageEdit: Bool = false
    var isFreeformEdit: Bool = false
    var useKie: Bool = true
    var useMusicLipSync: Bool = false
    var musicVideoKey: String = ""
    var isMotion: Bool = false

    func toTemplate() -> VideoTemplate {
        // Server-Vorlagen aus den verspielten Nischen landen unter demselben
        // Fun-Chip wie die eingebauten. Ohne das haetten sie eine Kategorie,
        // fuer die es in Discover gar keinen Chip mehr gibt — sie waeren
        // ausgeliefert, aber unerreichbar.
        let raw = TemplateCategory(rawValue: category) ?? .trends
        let playful: Set<TemplateCategory> = [.memes, .dance, .fancam, .worldcup, .backrooms, .fun]
        let cat = playful.contains(raw) ? .fun : raw
        let extras = extraCategories.compactMap { TemplateCategory(rawValue: $0) }
        let cols = colors.isEmpty
            ? [Color(red: 0.40, green: 0.28, blue: 0.92), Color(red: 0.20, green: 0.55, blue: 1.0)]
            : colors.map { Color(hex: $0) }
        return VideoTemplate(
            title: title, subtitle: subtitle, category: cat,
            isHiddenFromDiscover: cat == .fun, extraCategories: extras,
            hashtag: hashtag, preview: "", prompt: prompt, icon: icon, colors: cols,
            ratio: AspectRatio(rawValue: ratio) ?? .portrait, duration: duration,
            needsPhoto: needsPhoto, referenceVideoURL: referenceVideoURL, isFixed: isFixed,
            promptPhotoBackground: promptPhotoBackground, isImageEdit: isImageEdit,
            isFreeformEdit: isFreeformEdit, useKie: useKie, useMusicLipSync: useMusicLipSync,
            musicVideoKey: musicVideoKey, isMotion: isMotion, previewRemoteURL: previewURL
        )
    }
}

/// Lädt Templates vom Server (neue Trends ohne App-Update) und hängt sie an die
/// eingebauten an. Fällt bei Fehler auf die eingebauten Templates zurück.
@MainActor
@Observable
final class TemplateStore {
    // Auch die EINGEBAUTEN Templates laufen durch den Intim-Contact-Filter
    // (App Store Guideline 1.1) — nicht nur die Remote-Templates. So kann
    // garantiert kein Template mit Kuss-/Umarmungs-/Intim-Bezug erscheinen.
    var templates: [VideoTemplate] = TemplateLibrary.visible.filter { !ContentPolicy.containsIntimateContent($0) }

    func filtered(by category: TemplateCategory) -> [VideoTemplate] {
        TemplateFilter.apply(category, to: templates)
    }

    var trending: [VideoTemplate] { Array(templates.prefix(5)) }

    func load() async {
        guard let url = URL(string: "https://limitless-web-beryl.vercel.app/templates.json") else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let remote = try JSONDecoder().decode([RemoteTemplate].self, from: data)
            let mapped = remote
                .map { $0.toTemplate() }
                .filter { ContentPolicy.isAllowedTemplate($0) }
            let base = TemplateLibrary.visible.filter { !ContentPolicy.containsIntimateContent($0) }
            if !mapped.isEmpty { templates = base + mapped }
        } catch {
            // Netzwerk/Decode-Fehler → eingebaute Templates bleiben.
        }
    }
}
