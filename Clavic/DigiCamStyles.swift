//
//  DigiCamStyles.swift
//  Clavic
//
//  100% universelle Foto- & Kamera-Looks:
//  G7X Flash, Sunset Beach, Y2K Digicam, Sunlit Glow, Clean Girl, Night Flash, 35mm Mono.
//
//  Diese Stile verändern Motiv, Pose, Bildaufbau, Identität, Kleidung und Ort NICHT,
//  sondern wenden ein authentisches, fotorealistisches Color- & Blitz-Grading an.
//

import Foundation

enum DigiCamStyles {

    struct Style: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let hashtag: String
        let tag: String
        let category: String
        let icon: String
        let previewBefore: String
        let previewAfter: String
        let recipe: String

        var prompt: String { "\(DigiCamStyles.keepRule)\n\n\(recipe)\n\n\(DigiCamStyles.gradeRule)" }
    }

    /// Steht über jedem Rezept. Motiv & Identität bleiben 100% geschützt.
    static let keepRule = """
    Keep the exact same person: same face and every feature of it, same hair, same skin tone and \
    real skin texture, same build and body proportions, same age, same outfit. Do NOT beautify, \
    slim, smooth, retouch or redraw them. Keep the exact same pose, framing, composition and scene \
    - change ONLY the photographic look and lighting grade.
    """

    /// Steht unter jedem Rezept. Echter Kamera-Look mit Poren, kein Plastik-Filter.
    static let gradeRule = """
    Skin keeps visible pores, natural highlights and real texture - this is a colour grade, not a retouch. \
    The grade covers the whole frame, person and background equally. \
    Photorealistic, looks like a real photograph straight out of a camera. No text, no logos, no watermark.
    """

    static let all: [Style] = [
        Style(
            id: "g7xflash",
            title: "G7X Flash",
            subtitle: "Crisp Xenon flash & warm skin",
            hashtag: "#G7XFlash",
            tag: "🔥 VIRAL",
            category: "Flash",
            icon: "bolt.circle.fill",
            previewBefore: "card_look_g7xflash",
            previewAfter: "card_look_g7xflash",
            recipe: """
            Recreate an authentic Canon G7X direct on-camera flash response: crisp natural skin, \
            bright but controlled flash highlights on the face and outfit, a softly darker room \
            ambience in the background, flattering warm-neutral skin tones around 5200K, realistic \
            compact-camera sharpness and fine sensor texture.
            """
        ),
        Style(
            id: "sunsetbeach",
            title: "Sunset Beach",
            subtitle: "Pink dusk sky & golden rim glow",
            hashtag: "#SunsetBeach",
            tag: "🌅 SUNSET",
            category: "Glow",
            icon: "sun.max.fill",
            previewBefore: "card_look_sunsetbeach",
            previewAfter: "card_look_sunsetbeach",
            recipe: """
            Infuse the photo with a vibrant beach sunset look: soft pastel pink and orange \
            dusk sky gradients, glowing golden rim light outlining hair and shoulders, warm sunlit \
            skin tones, and creamy gentle ocean twilight contrast.
            """
        ),
        Style(
            id: "y2kdigicam",
            title: "Y2K Digicam",
            subtitle: "Cyber pop colors & CCD contrast",
            hashtag: "#Y2KDigicam",
            tag: "📼 Y2K",
            category: "Vintage",
            icon: "camera.fill",
            previewBefore: "card_look_y2kdigicam",
            previewAfter: "card_look_y2kdigicam",
            recipe: """
            Grade it like a 2000s cyber compact digital camera: punchy contrast, deep crushed blacks, \
            vibrant saturated pop colors, warm glowing highlights around hair and edges around 3800K, \
            and subtle digital CCD sensor grain.
            """
        ),
        Style(
            id: "sunlitglow",
            title: "Sunlit Glow",
            subtitle: "Warm window rays & lush tones",
            hashtag: "#SunlitGlow",
            tag: "☀️ GLOW",
            category: "Glow",
            icon: "sparkles",
            previewBefore: "card_look_sunlitglow",
            previewAfter: "card_look_sunlitglow",
            recipe: """
            Apply a warm sunlit morning window grade: soft golden light streaming from the side, \
            delicate luminous skin highlights, lush fresh natural tones, airy bright shadows, and \
            gentle warm daylight diffusion.
            """
        ),
        Style(
            id: "cleangirl",
            title: "Clean Girl",
            subtitle: "Pure natural daylight & texture",
            hashtag: "#CleanGirl",
            tag: "☁️ CLEAN",
            category: "Daylight",
            icon: "sun.haze.fill",
            previewBefore: "card_look_cleangirl",
            previewAfter: "card_look_cleangirl",
            recipe: """
            Grade with the viral Clean Girl daylight aesthetic: ultra-natural soft daylight, \
            perfectly balanced neutral-warm tones, sharp natural skin texture with visible pores \
            and zero artificial smoothing, minimalist clean contrast and effortless clarity.
            """
        ),
        Style(
            id: "nightflash",
            title: "Night Flash",
            subtitle: "Late-night candid & city bokeh",
            hashtag: "#NightFlash",
            tag: "🚗 FLASH",
            category: "Flash",
            icon: "car.fill",
            previewBefore: "card_look_nightflash",
            previewAfter: "card_look_nightflash",
            recipe: """
            Recreate a late-night on-camera flash look: crisp direct flash highlighting the subject \
            sharply, moody dark ambient background falloff, warm vibrant skin tones, and subtle \
            blurred night street lights in the background.
            """
        ),
        Style(
            id: "monomono",
            title: "35mm Mono",
            subtitle: "High-contrast vintage B&W",
            hashtag: "#35mmMono",
            tag: "🖤 EDITORIAL",
            category: "B&W",
            icon: "circle.lefthalf.filled",
            previewBefore: "card_look_monomono",
            previewAfter: "card_look_monomono",
            recipe: """
            Convert to timeless high-contrast 35mm black and white film: rich velvety blacks, \
            bright luminous highlights, wide dynamic tonal range, and authentic fine monochrome \
            grain like Kodak Tri-X 400.
            """
        ),
    ]

    static func style(id: String) -> Style? {
        if let match = all.first(where: { $0.id == id }) { return match }
        let lower = id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = all.first(where: {
            $0.id.lowercased() == lower
                || $0.title.lowercased() == lower
                || $0.hashtag.lowercased() == lower
                || lower.contains($0.title.lowercased())
                || $0.title.lowercased().contains(lower)
        }) {
            return match
        }

        // Semantic keyword & legacy mapping
        if lower.contains("sunset") || lower.contains("beach") {
            return all.first(where: { $0.id == "sunsetbeach" })
        } else if lower.contains("y2k") || lower.contains("2000") || lower.contains("digi") {
            return all.first(where: { $0.id == "y2kdigicam" })
        } else if lower.contains("sunlit") || lower.contains("glow") || lower.contains("tropic") {
            return all.first(where: { $0.id == "sunlitglow" })
        } else if lower.contains("clean") || lower.contains("daylight") {
            return all.first(where: { $0.id == "cleangirl" })
        } else if lower.contains("night") || lower.contains("car") || lower.contains("club") {
            return all.first(where: { $0.id == "nightflash" })
        } else if lower.contains("mono") || lower.contains("b&w") || lower.contains("bw") || lower.contains("black") {
            return all.first(where: { $0.id == "monomono" })
        } else {
            return all.first(where: { $0.id == "g7xflash" })
        }
    }

    static func prompt(id: String) -> String { style(id: id)?.prompt ?? "" }
}
