import Foundation

/// Reviewed photo-look families. General templates must not become TikTok trends
/// merely because the server returned them. Evidence and photo credits: docs/TIKTOK_TRENDS.md.
enum TikTokTrends {
    struct Look: Identifiable {
        let id: String
        let title: String
        let caption: String
        let recipe: String
        var before: String { "trend_\(id)_before" }
        var after: String { "trend_\(id)_after" }

        var option: DirectorAPI.Option {
            DirectorAPI.Option(id: id, label: title, caption: caption, mode: .grade,
                prompt: """
                Keep the exact same person, face, skin tone, body, pose, clothing, objects,
                background and crop. Edit only photographic light and colour. Preserve real
                skin texture; no beauty smoothing or invented scenery. \(recipe)
                No text, no logos, no watermark.
                """, preview: after)
        }
    }

    static let all: [Look] = [
        Look(id: "g7xflash", title: "G7X Flash", caption: "Crisp flash · warm colour",
             recipe: "Crisp compact-camera flash finish, warm-neutral highlights, richer contrast and darker ambient tones. Keep highlights controlled."),
        Look(id: "goldenhour", title: "Golden Hour", caption: "Soft light · golden warmth",
             recipe: "Warm golden-hour colour, amber highlights and soft contrast. Respect existing light direction and preserve natural skin colour."),
        Look(id: "redsunset", title: "Red Sunset", caption: "Deep red sky · almost night",
             recipe: "Deep red-orange sunset colour: burnt-orange near the horizon falling to dark oxblood, dense blacks and a nearly-night ambience. No flash and no fill — light the subject only from the sky, warm on the side facing it and falling into shadow on the other. Keep coloured clothing recognisably its own colour under the red light. Keep the face readable and preserve its natural complexion."),
        Look(id: "y2kdigicam", title: "Y2K Digicam", caption: "Direct flash · CCD colour",
             recipe: "Early-2000s compact CCD camera rendering. Hard, frontal on-camera flash character: slightly blown highlights on the nearest skin with a fast falloff, so the surroundings drop away into dense shadow. Punchy, slightly off CCD colour — warm in the lights, cool blue-green in the shadows — contrast a step harder than a phone, and visible fine sensor noise in the dark areas. Flat and snapshot-like, not studio-lit."),
        Look(id: "redlight", title: "Red Light", caption: "One red source · hard shadow",
             recipe: "One small, hard, saturated red source close to the subject in an otherwise dark room. It throws a crisp-edged wedge of red across them and whatever is behind them; everything the beam misses falls off fast into dense, near-black shadow. Inside the beam the red is deep and pure, pushed towards orange where it is brightest on the skin, close to clipping. This is coloured LIGHT, not a red tint over the whole picture: anything the beam does not reach keeps its own colour — grey walls stay cold grey, black clothing stays black, and any surface lit by a screen or a second source stays neutral. That contrast between the red-lit and the neutral parts is the look. Dense blacks with no lift, no overall vignette, and honest high-ISO noise in the shadows."),
        Look(id: "bluehour", title: "Blue Hour", caption: "Cool blues · evening mood",
             recipe: "Blue twilight colour grade, cool blue shadows and gently darkened ambience. Keep the face readable and preserve its natural complexion.")
    ]

    static func look(id: String) -> Look? {
        let key = id.lowercased().filter { $0.isLetter || $0.isNumber }
        let canonical = key == "sunlitglow" ? "goldenhour" : key
        return all.first { $0.id == canonical }
    }

    /// Keep the Director's ordering and best-match signal for reviewed IDs only.
    /// Use our paired previews and matching recipes, never an unrelated remote image.
    static func options(ranked: [DirectorAPI.Option] = []) -> [DirectorAPI.Option] {
        var seen = Set<String>()
        var result: [DirectorAPI.Option] = []
        for incoming in ranked where incoming.mode == .grade {
            guard let look = look(id: incoming.id), seen.insert(look.id).inserted else { continue }
            var option = look.option
            option.isBestMatch = incoming.isBestMatch
            result.append(option)
        }
        result += all.filter { seen.insert($0.id).inserted }.map(\.option)
        return result
    }
}
