import Foundation

/// Reviewed photo-look families. General templates must not become TikTok trends
/// merely because the server returned them. Evidence and photo credits: docs/TIKTOK_TRENDS.md.
enum TikTokTrends {
    struct Look: Identifiable {
        let id: String
        let title: String
        let caption: String
        let recipe: String

        /// Wie weit dieser Look eingreifen darf.
        ///
        /// `.grade` heisst: nur Licht und Farbe. Das reicht fuer Golden Hour und
        /// Blue Hour — dort aendert sich wirklich nur die Farbe.
        ///
        /// Vier Looks brauchen mehr, und zwar nicht aus Bequemlichkeit: G7X
        /// Flash, Y2K Digicam, Red Sunset und Red Light sind BELEUCHTUNGEN, keine
        /// Farbkorrekturen. Aus Tageslicht Nacht mit Blitz zu machen ist als
        /// Farbkorrektur nicht moeglich — am 09.09.2026 gegen die viralen
        /// Vorlagen geprueft: Mit `.grade` lieferte `g7xflash` ein huebsches
        /// Golden-Hour-Bild ganz ohne Blitz. `.retouch` behaelt das Quellfoto als
        /// Basis und sperrt Identitaet, Pose und Umgebung weiterhin, erlaubt aber
        /// die Neubelichtung.
        var mode: DirectorAPI.Mode = .grade

        /// Wenn gesetzt, wird dieser Text UNVERAENDERT als Prompt benutzt.
        ///
        /// Die Kurzform aus `recipe` plus Rahmensatz reicht fuer einfache
        /// Farbgrades. Eine Beleuchtung braucht dagegen genaue Angaben zu
        /// Richtung, Haerte, Abfall und Kante — und `y2kdigicam` braucht sogar
        /// eine AUSNAHME vom Rahmensatz, weil der Datumsstempel Text ist und der
        /// Rahmensatz jeden Text verbietet. Genau dieser Widerspruch hat das
        /// erkennbarste Merkmal des Looks jahrelang unmoeglich gemacht.
        var fullPrompt: String? = nil

        var before: String { "trend_\(id)_before" }
        var after: String { "trend_\(id)_after" }

        var option: DirectorAPI.Option {
            let text = fullPrompt ?? """
                Keep the exact same person, face, skin tone, body, pose, clothing, objects,
                background and crop. Edit only photographic light and colour. Preserve real
                skin texture; no beauty smoothing or invented scenery. \(recipe)
                No text, no logos, no watermark.
                """
            return DirectorAPI.Option(id: id, label: title, caption: caption, mode: mode,
                                      prompt: text, preview: after)
        }
    }

    static let all: [Look] = [
        Look(id: "g7xflash", title: "G7X Flash", caption: "Night · direct flash",
             recipe: "", mode: .retouch, fullPrompt: """
             Make this photo look like it was taken at night on a Canon G7X Mark III with the
             built-in flash fired straight at the subject. The whole scene is night — sky, water,
             ground and buildings all dark. The flash lights the person from the camera: bright,
             flat, falling off fast into blackness behind them. Visible sensor noise in the dark
             areas. Keep the face, body, pose and clothing exactly as they are.
             """),
        Look(id: "y2kdigicam", title: "Y2K Digicam", caption: "Daylight flash · CCD",
             recipe: "", mode: .retouch, fullPrompt: """
             Make this photo look like a 2004 snapshot from a cheap 3-megapixel digital camera
             with the flash forced on in daylight. Oversaturated blues and greens, hard direct
             flash on the subject, visible grain, slightly soft, mild vignette. Burn a small
             orange date stamp "2004 08 14" into the lower right corner. Keep the face, body,
             pose and clothing exactly as they are.
             """),
        Look(id: "redsunset", title: "Red Sunset", caption: "Flash · burning sky",
             recipe: "", mode: .retouch, fullPrompt: """
             Make this photo look like a real photograph taken with a camera flash in front of a
             sunset. This must look like an actual sunset someone photographed, not a red filter
             laid over the sky.

             The sky has a real gradient: warm and bright low near the horizon where the sun just
             went down, deepening to darker red and dusky purple higher up. Keep the existing
             clouds where they are and light them from below, warm on their undersides. The rest
             of the scene — water, ground, buildings — falls dark and takes a warm cast from the
             sky, with the horizon still the brightest part of the frame.

             The flash lights the person from the camera: bright and flat, so they stand out
             against the dark sky.

             The flash changes only how bright she is, never who she is or how she is standing.
             Her head stays at exactly the same angle, her eyes stay exactly as they are — if
             they are closed or lowered in the original they stay closed or lowered — and her
             expression, pose, hands and clothing do not move. Keep her real skin texture; the
             flash must not smooth or beautify her.
             """),
        Look(id: "redlight", title: "Red Light", caption: "Hard red · half in dark",
             recipe: "", mode: .retouch, fullPrompt: """
             Re-light this photo with a hard red light hitting the person from low and in front,
             like a red traffic light at night. Their face and body glow deep red where the light
             lands, with a visible edge where it stops — above it stays dark. Everything else in
             the frame falls to near-black. Keep the face, body, pose and clothing exactly as
             they are.
             """),
        Look(id: "goldenhour", title: "Golden Hour", caption: "Strong golden wash",
             recipe: "", fullPrompt: """
             Apply a strong golden hour grade to this photo. Warm everything hard toward gold and
             amber, lift the light, deepen and warm the shadows, add a soft warm haze. Keep the
             existing clouds where they are — recolour them, do not replace them. Keep the face,
             body, pose and clothing exactly as they are.
             """),
        Look(id: "bluehour", title: "Blue Hour", caption: "Cool blues · evening",
             recipe: "", fullPrompt: """
             Apply a blue hour grade to this photo. Cool blue twilight tones, gently darkened,
             moody and cinematic. Keep the existing clouds where they are — recolour them, do not
             replace them. Keep the face, body, pose and clothing exactly as they are.
             """),
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
