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
    case hooks = "Hooks"
    case dance = "Dance"
    case new = "New"

    var id: String { rawValue }

    /// Symbol für das Nischen-Badge auf den Kacheln (nil = kein Badge)
    var badgeIcon: String? {
        switch self {
        case .all: return nil
        case .hooks: return "flame.fill"
        case .dance: return "figure.dance"
        case .new: return "sparkles"
        }
    }
}

struct VideoTemplate: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let category: TemplateCategory
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
    /// Diese Vorlage rendert über kie.ai (Seedance 2.0) statt fal.ai.
    var useKie: Bool = false
    /// Upscale-Werkzeug: Datei hochladen → hochskalieren ("image" oder "video").
    var upscaleKind: String? = nil
    var isUpscale: Bool { upscaleKind != nil }
    /// „Coming soon": Kachel ist sichtbar, lässt sich aber nicht öffnen.
    var comingSoon: Bool = false
    /// Asset-Namen für die automatische Vorher/Nachher-Vorschau (Slider).
    var previewBefore: String? = nil
    var previewAfter: String? = nil

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Credit-Kosten dieser Generierung. Bild-Operationen sind deutlich
    /// günstiger als Video, weil sie uns weniger kosten – so bleibt die Marge
    /// pro Credit positiv, egal ob der Nutzer Bilder oder Videos macht.
    var creditCost: Int {
        if isImageEdit { return CreditCosts.imageEdit }
        switch upscaleKind {
        case "image": return CreditCosts.imageUpscale
        case "video": return CreditCosts.videoUpscale
        default:
            return CreditCosts.video(seconds: duration, hasReferenceVideo: referenceVideoURL != nil)
        }
    }

    /// Bundle-URL einer Video-Vorschau, falls vorhanden.
    var previewVideoURL: URL? {
        Bundle.main.url(forResource: preview, withExtension: "mp4")
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

/// Zentrale Credit-Preise pro Modell/Aktion. Direkt an die echten
/// Provider-Kosten (kie.ai, 480p) gekoppelt, damit wir bei jedem Modell im
/// Plus bleiben – egal ob Bild oder (kurzes/langes) Video.
///
/// Kalkulation: Wir verkaufen Credits im günstigsten Fall (Abo) für ~0,70 €
/// netto pro Credit. Mit einem internen Kostenbudget von ~0,20 € pro Credit
/// bleibt immer eine klare Marge.
enum CreditCosts {
    /// Internes Kostenbudget pro Credit (in $/€, grob gleichgesetzt).
    static let budgetPerCredit = 0.20

    static let imageEdit = 1     // Nano Banana 2 Image Edit (~0,03 $)
    static let imageUpscale = 1  // Topaz Image Upscale (~0,03 $)
    static let videoUpscale = 3  // Topaz Video Upscale (~0,30–0,50 $)

    /// Video-Generierung (Seedance 2.0 Fast @480p). Kosten skalieren mit der
    /// Länge; mit Referenz-Video wird teurer abgerechnet (Input + Output).
    static func video(seconds: Int, hasReferenceVideo: Bool) -> Int {
        // kie.ai Seedance 2.0 Fast @480p:
        //   ohne Referenz (Bild→Video): ~0,095 $/Output-Sekunde
        //   mit Referenz-Video:        ~0,0575 $/s × (Input+Output) ≈ 0,115 $/s
        let perSecond = hasReferenceVideo ? 0.115 : 0.095
        let raw = Double(max(seconds, 1)) * perSecond / budgetPerCredit
        return max(3, Int(raw.rounded(.up)))
    }

    /// Repräsentativer Wert fürs UI (entspricht einem typischen Trend-Video).
    static var representativeVideo: Int { video(seconds: 8, hasReferenceVideo: true) }
}

enum TemplateLibrary {
    static let all: [VideoTemplate] = [
        VideoTemplate(
            title: "Clavic Image Edit",
            subtitle: "Change outfits or add someone",
            category: .new,
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
            title: "Love and Affection Trend",
            subtitle: "Restyle a person in your photo",
            category: .new,
            hashtag: "#LoveAndAffection",
            preview: "preview_glowup_swap",
            prompt: "In @Image1, replace the chosen person with an attractive, well-groomed young man with a similar pose, clothing and gaze. Keep the other person, the background, the lighting and the image quality exactly the same. Photorealistic, natural skin tones, no text in the image.",
            icon: "wand.and.stars.inverse",
            colors: [Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.62, green: 0.30, blue: 0.85)],
            ratio: .portrait,
            duration: 0,
            needsPhoto: true,
            isImageEdit: true,
            previewBefore: "preview_glowup_swap_before",
            previewAfter: "preview_glowup_swap_after"
        ),
        VideoTemplate(
            title: "OMG Hook",
            subtitle: "Scroll-stopping opener",
            category: .hooks,
            hashtag: "#OMGHook",
            preview: "preview_omg_hook",
            prompt: "The person in @Image1 looks surprised straight into the camera, then something unexpected and spectacular happens right behind them, fast dramatic zoom, shocked expression, cinematic lighting, maximum tension in the first seconds as a perfect scroll-stopper, 9:16 vertical",
            icon: "exclamationmark.bubble.fill",
            colors: [Color(red: 1.0, green: 0.42, blue: 0.30), Color(red: 0.80, green: 0.10, blue: 0.45)],
            ratio: .portrait,
            duration: 5,
            needsPhoto: true,
            comingSoon: true
        ),
        VideoTemplate(
            title: "Dance Reference",
            subtitle: "Viral dance move",
            category: .dance,
            hashtag: "#DanceTrend",
            preview: "preview_dance",
            prompt: "The person in @Image1 performs an energetic viral dance, fluid rhythmic full-body movements, hip sway and clean arm choreography on beat, confident expression, modern club lighting, dynamic but stable camera, loop-friendly, 9:16 vertical",
            icon: "figure.dance",
            colors: [Color(red: 0.55, green: 0.35, blue: 0.95), Color(red: 0.95, green: 0.30, blue: 0.65)],
            ratio: .portrait,
            duration: 6,
            needsPhoto: true,
            comingSoon: true
        ),
        VideoTemplate(
            title: "Lego Trend",
            subtitle: "Put yourself in the Lego clip",
            category: .new,
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
        VideoTemplate(
            title: "Image Upscale",
            subtitle: "Sharpen & enlarge a photo",
            category: .new,
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
            category: .new,
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

    static func filtered(by category: TemplateCategory) -> [VideoTemplate] {
        category == .all ? all : all.filter { $0.category == category }
    }

    static var trending: [VideoTemplate] {
        Array(all.prefix(5))
    }

    static var featured: VideoTemplate { all[0] }
}
