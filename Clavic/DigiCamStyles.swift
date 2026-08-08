//
//  DigiCamStyles.swift
//  Clavic
//
//  Der Digicam-Look — der Grund, warum Leute seit Monaten nach einer Canon
//  G7X suchen, die es nirgends zu kaufen gibt.
//
//  Diese Stile sind bewusst KEINE ViralLooks. Ein ViralLook baut eine neue
//  Szene um die Person herum. Hier passiert das Gegenteil: Motiv, Pose,
//  Bildaufbau und Ort bleiben unangetastet, es ändert sich nur, wie das Foto
//  aussieht. Deshalb ein eigener Typ und eine eigene Datei — würde man beides
//  vermischen, stünde in einer Liste einmal „erfinde eine Szene" und einmal
//  „fass die Szene nicht an".
//
//  Die sechs Rezepte sind aus dem WayShot-Teardown abgeleitet (Desktop/Claud/
//  wayshot-teardown.md). Deren Vorschaubilder haben wir NICHT übernommen: das
//  sind fremde Fotos echter Menschen. Unsere Kacheln zeigen stattdessen einen
//  echten Durchlauf durch genau diesen Prompt — was die Nutzerin auf der
//  Kachel sieht, ist das, was sie bekommt.
//

import Foundation

enum DigiCamStyles {

    struct Style: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let hashtag: String
        let icon: String
        /// Das unveränderte Ausgangsfoto der Kachel — bewusst ein flaues,
        /// mittelmäßiges Handyfoto. Ein Studio-Katalogbild taugt hier nicht:
        /// es ist schon perfekt, also kann das Grading nichts mehr sichtbar
        /// verbessern, und die Kachel verspricht nichts.
        let previewBefore: String
        /// Derselbe Durchlauf, den `prompt` erzeugt.
        let previewAfter: String
        /// Das Rezept — ohne die gemeinsamen Klammern oben und unten.
        let recipe: String

        var prompt: String { "\(DigiCamStyles.keepRule)\n\n\(recipe)\n\n\(DigiCamStyles.gradeRule)" }
    }

    /// Steht über jedem Rezept. Der Unterschied zu allem anderen im Katalog:
    /// hier darf sich die POSE ausdrücklich NICHT ändern.
    static let keepRule = """
    Keep the exact same person: same face and every feature of it, same hair, same skin tone and \
    real skin texture, same build and body proportions, same age, same outfit. Do NOT beautify, \
    slim, smooth, retouch or redraw them. Keep the exact same pose, framing, composition and scene \
    - change ONLY the look of the photograph.
    """

    /// Steht unter jedem Rezept. „Grade, nicht Retusche" ist der Satz, der den
    /// Look von einem Beauty-Filter trennt: die Haut behält ihre Poren.
    static let gradeRule = """
    Skin keeps visible pores and real texture - this is a colour grade, not a retouch. The grade \
    covers the whole frame, person and background equally. Photorealistic, looks like a real photo \
    straight out of the camera. No text, no logos, no watermark.
    """

    static let all: [Style] = [
        Style(
            id: "digix",
            title: "DigiX",
            subtitle: "The punchy 2000s digicam look",
            hashtag: "#DigiX",
            icon: "camera.fill",
            previewBefore: "preview_digicam_digix_before",
            previewAfter: "preview_digicam_digix_after",
            recipe: """
            Grade it like a 2000s compact digital camera on a bright day: high contrast, deep \
            crushed blacks, warm glowing highlights around hair and edges around 3800K, punchy \
            saturated colour, a gentle vignette darkening the corners, fine sensor noise in the \
            shadows.
            """
        ),
        Style(
            id: "digicam",
            title: "DigiCam",
            subtitle: "Warm night light, deep blacks",
            hashtag: "#DigiCam",
            icon: "flashlight.on.fill",
            previewBefore: "preview_digicam_digicam_before",
            previewAfter: "preview_digicam_digicam_after",
            recipe: """
            Grade it like a 2000s compact digital camera at night indoors: warm tungsten and \
            candlelight around 2900K pushed up, glossy specular highlights on the skin, saturated \
            warm midtones, the background falling away into deep black, visible high-ISO noise.
            """
        ),
        Style(
            id: "digis",
            title: "DigiS",
            subtitle: "Direct flash after sunset",
            hashtag: "#DigiS",
            icon: "bolt.fill",
            previewBefore: "preview_digicam_digis_before",
            previewAfter: "preview_digicam_digis_after",
            recipe: """
            Grade it like a 2000s compact camera with direct on-camera flash after sunset: deep \
            blue sky, hot warm flash highlights on the skin and the nearest surfaces, high \
            micro-contrast, crisp point lights in the distance, slight falloff into darkness at \
            the frame edges.
            """
        ),
        Style(
            id: "digilite",
            title: "DigiLite",
            subtitle: "Bright, airy, barely there",
            hashtag: "#DigiLite",
            icon: "sun.max.fill",
            previewBefore: "preview_digicam_digilite_before",
            previewAfter: "preview_digicam_digilite_after",
            recipe: """
            Grade it like a bright airy daylight compact camera photo around 5600K: low contrast, \
            lifted milky blacks, soft pastel colour, clean bright whites, very fine grain, nothing \
            crushed.
            """
        ),
        Style(
            id: "cleangirl",
            title: "Clean Girl",
            subtitle: "Warm skin, clean whites, quiet glow",
            hashtag: "#CleanGirl",
            icon: "sparkles",
            previewBefore: "preview_digicam_cleangirl_before",
            previewAfter: "preview_digicam_cleangirl_after",
            recipe: """
            Grade it in the clean-girl look: warm bright skin with a subtle natural glow, clean \
            neutral whites, soft gentle contrast, muted beige and cream tones, barely any grade on \
            the background.
            """
        ),
        Style(
            id: "bw",
            title: "Mono",
            subtitle: "High-contrast black and white",
            hashtag: "#Mono",
            icon: "circle.lefthalf.filled",
            previewBefore: "preview_digicam_bw_before",
            previewAfter: "preview_digicam_bw_after",
            recipe: """
            Convert it to high-contrast black and white: deep true blacks, bright clean highlights, \
            the full range of mid greys in between, visible film grain, no colour anywhere.
            """
        ),
    ]

    static func style(id: String) -> Style? { all.first { $0.id == id } }
    static func prompt(id: String) -> String { style(id: id)?.prompt ?? "" }
}
