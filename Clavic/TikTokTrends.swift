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
             Re-expose this photograph as if it had been shot at NIGHT on a Canon G7X compact
             camera with the built-in flash fired. This is a re-lighting of the SAME photo —
             do not repaint, redraw, reconstruct or re-pose the person or the scene.

             The light:
             - Pull the ambient scene down about three stops into night. Sky goes deep and dark.
             - Add ONE hard, direct, on-camera flash from the camera position. No diffusion,
               no softbox, no bounce — a small built-in flash firing straight down the lens axis.
             - The flash falls off fast: what is close is bright and slightly hot, what is a few
               metres back sinks toward black. Nothing in the far distance is lit.
             - Because the light sits on the lens axis, the modelling on the face is FLAT and
               almost shadowless, and the shadow the person casts falls directly behind them.
             - A few small specular highlights where the flash hits skin directly, one or two
               of them just clipping to white.
             - White balance warm-neutral, the way a G7X renders flash. Deep focus throughout,
               small-sensor look. Mild vignette. Visible sensor noise in the dark areas.

             Preserve exactly, untouched:
             - The face, all facial features, the expression, the pose, the hands, the body
               shape, the hair, the clothing, the framing and the crop.
             - Real skin texture — pores, uneven tone, small marks, stray hairs. NO skin
               smoothing, NO beautifying, NO retouching, NO slimming, NO reshaping.
             - No fake background blur. A compact camera at f/2.8 does not produce creamy bokeh.

             The result must look like a real amateur snapshot taken at night with a
             point-and-shoot: harsh, flat-lit, imperfect, a bit noisy. It must NOT look like a
             studio portrait, a beauty filter, a golden-hour photo or an AI render.
             """),
        Look(id: "y2kdigicam", title: "Y2K Digicam", caption: "Daylight flash · CCD",
             recipe: "", mode: .retouch, fullPrompt: """
             Make this photograph look like it was taken in about 2004 on a cheap 3-megapixel
             compact digital camera with the flash forced on. This is a re-processing of the
             SAME photo — do not repaint, redraw, reconstruct or re-pose the person or the scene.

             The camera:
             - Flash fires even though there is daylight. Direct, on-axis, undiffused: the
               subject is lit flat and slightly too bright, the background sits a stop or two
               darker than the subject.
             - Push saturation aggressively the way early camera processors did: blues go very
               blue, greens go vivid, and skin takes on a faintly orange-pink cast.
             - Raise contrast. Clip a few highlights on skin and on the brightest surfaces.
             - Add visible luminance noise, strongest in the shadows and in flat areas of sky.
             - Soften detail everywhere very slightly — this sensor never resolved fine texture.
               A touch of purple-green fringing along hard bright edges.
             - Slight barrel distortion and a mild vignette from a cheap zoom lens.

             Date stamp — REQUIRED, this is the single most recognisable element of the look:
             - Burn a small date stamp into the LOWER RIGHT corner, in the orange-yellow
               seven-segment style those cameras used, slightly soft and slightly
               semi-transparent, as if exposed into the frame rather than drawn on top.
             - Format it exactly as: 2004 08 14
             - Nothing else. No other text, no logo, no watermark, no border, no frame.

             Preserve exactly, untouched:
             - The face, all facial features, the expression, the pose, the hands, the body
               shape, the hair, the clothing, the framing and the crop.
             - Real skin texture. NO skin smoothing, NO beautifying, NO retouching, NO
               slimming, NO reshaping. The flash should make skin look MORE real, not less.

             The result must look like a found photo from a 2004 holiday folder: bright, flat,
             grainy, over-saturated, imperfect. It must NOT look modern, clean, cinematic or
             AI-generated.
             """),
        Look(id: "redsunset", title: "Red Sunset", caption: "Flash · burning sky",
             recipe: "", mode: .retouch, fullPrompt: """
             Re-light this photograph as a FLASH-AT-SUNSET shot: the sky burns deep red-orange
             behind the person, and the person herself is lit by the camera's flash. This is a
             re-lighting of the SAME photo — do not repaint, redraw, reconstruct or re-pose the
             person or the scene.

             The sky and the ambient:
             - Push the existing sky to a deep sunset: burnt orange near the horizon falling to
               dark oxblood higher up. Dense blacks in the land and the shadows.
             - Keep the sky's existing cloud SHAPES exactly as they are — same clouds, same
               places, same outlines. Only their colour and brightness change. Do not add
               clouds, do not remove clouds, do not add a sun disc that is not already there.
             - Everything not reached by the flash sits near-night: the far beach, the water,
               the distant background all fall dark.

             The flash — this is what makes the shot:
             - ONE hard, direct, on-camera flash fires from the camera position onto the person.
               She is properly exposed and clearly brighter than everything around her.
             - She must NOT be a silhouette. Her face, skin and clothing read clearly and keep
               their own colour: white clothing stays white, skin keeps its natural complexion.
             - The flash is on the lens axis, so the modelling on her face is flat and almost
               shadowless, with a few small specular highlights on the skin, one or two just
               clipping.
             - The flash falls off fast. Whatever is a few metres behind her gets nothing.
             - The contrast between the flash-lit person and the dark burning sky IS the look.

             Preserve exactly, untouched:
             - The face, all facial features, the expression, the pose, the hands, the body
               shape, the hair, the clothing, the framing and the crop.
             - Real skin texture — pores, uneven tone, small marks. NO skin smoothing, NO
               beautifying, NO retouching, NO slimming, NO reshaping.

             The result must look like a real phone-or-compact snapshot taken with flash in
             front of a sunset: harsh light on her, dramatic dark sky behind. It must NOT look
             like a silhouette, a studio portrait or an AI render. No text, no logos, no watermark.
             """),
        Look(id: "redlight", title: "Red Light", caption: "Hard red · half in dark",
             recipe: "", mode: .retouch, fullPrompt: """
             Re-light this photograph with a hard, raking RED light that cuts across the person
             — the look of sitting in a car at night with a red light falling in through the
             window. This is a re-lighting of the SAME photo — do not repaint, redraw,
             reconstruct or re-pose the person or the scene.

             The light has a hard EDGE, and that edge is the whole look:
             - One small, hard, saturated red source sits LOW and in FRONT of her, on the
               camera's side, roughly at chest-to-chin height. It rakes upward and across her.
             - The beam is NARROW and it is aimed at HER. It is partly blocked at its upper
               edge, so what reaches her is a bounded shaft, not an open floodlight.
             - Nothing else in the picture is in the beam. Foreground objects beside her — a
               tree trunk, a wall, a post — stay DARK. They are not the subject and must not
               become the brightest thing in the frame. Only a faint spill may touch them.
             - Because the source is low and hard, the light lands as a clearly bounded BAND,
               not an even wash. There is a visible boundary on her face where the red stops.
             - Above that boundary — the upper face, the forehead, the hairline, the top of the
               head — stays DARK, barely lit, falling toward black.
             - Below and along it — the cheek, the bridge and tip of the nose, the lips, the
               jaw, the chin, the neck, the collarbone, the top of the shoulder and the arm —
               burn hot saturated red, pushed toward orange at the brightest points and coming
               close to clipping.
             - ON THE LIT SIDE THE RED WINS. The source is so saturated that it swallows local
               colour: skin does not read as tanned skin with a warm glow, it reads as RED-ORANGE.
               White fabric lit by this source is RED, not white. There is almost no green or
               blue left in the lit pixels — the lit areas sit hard in the red-orange channel.
               Do not protect natural complexion here and do not keep clothing its own colour:
               under a light this saturated, nothing keeps its own colour.
             - What stays untouched on the lit side is TEXTURE and SHAPE — pores, fabric weave,
               strands of hair, the geometry of the face — not colour.
             - The boundary itself is crisp, not a soft gradient. It runs at an angle across the
               face, the way a shaft of light through a window does.

             Everything else:
             - The surroundings fall off fast into dense, near-black darkness. Only a small
               amount of red spill lands on what is immediately beside her.
             - The background is not red — it is simply dark. Dense blacks with no lift, honest
               high-ISO noise in the shadows.
             - She is by a clear margin the brightest thing in the frame, and the lit half of
               her is by a clear margin the brightest part of her.

             This is coloured LIGHT with a hard edge, not a red filter over the picture and not
             an even red glow on the whole person. Half of her is on fire, half of her is gone.

             Preserve exactly, untouched:
             - The face, all facial features, the expression, the pose, the hands, the body
               shape, the hair, the clothing, the framing and the crop.
             - Real skin texture — pores, uneven tone, small marks, stray hairs. NO skin
               smoothing, NO beautifying, NO retouching, NO slimming, NO reshaping. The hard
               light should make skin look MORE real, not less.

             The result must look like a real night snapshot lit by one hard red source:
             high-contrast, cinematic, half in darkness. It must NOT look like an even red
             glow, a red colour wash, or an AI render. No text, no logos, no watermark.
             """),
        Look(id: "goldenhour", title: "Golden Hour", caption: "Strong golden wash",
             recipe: "", fullPrompt: """
             Apply a strong GOLDEN HOUR colour grade to this photograph, the way a heavy
             Lightroom preset would. This is a grade, NOT a re-render: do not repaint, redraw,
             relight from a new direction or reconstruct anything in the frame.

             Grade — this must be clearly visible, not subtle:
             - Warm the whole image hard toward gold and amber. Push the highlights to a rich
               honey tone; let the warmth carry into the midtones too.
             - Lift the exposure of everything the low sun would reach, and let the brightest
               areas bloom slightly, as if flaring into the lens.
             - Deepen the shadows and warm them toward brown-orange rather than blue.
             - Raise saturation on oranges, yellows and reds. Pull greens down and warm them so
               foliage reads golden rather than fresh.
             - Add a soft warm haze across the frame that is strongest toward the brightest side
               of the picture, thinning out toward the darker side.
             - Give hair and the edges of the body a warm golden rim where they already catch
               light. Do not invent a new light source and do not move the existing one.

             Do not invent scenery:
             - Keep the sky's existing cloud SHAPES exactly as they are. Only their colour and
               brightness may change. Do not add clouds, do not remove clouds, do not add a sun
               disc that is not already visible in the frame.

             Preserve exactly, untouched:
             - The face, all facial features, the expression, the pose, the hands, the body
               shape, the hair, the clothing, the framing and the crop.
             - Real skin texture including pores, marks and uneven tone. NO skin smoothing, NO
               beautifying, NO retouching, NO slimming, NO reshaping.
             - The original grain and noise. Do not clean, denoise or sharpen.

             The result must look like the SAME phone photo with a strong warm preset on it —
             still slightly imperfect and real. It must NOT look HDR, glossy, airbrushed or
             AI-generated. No text, no logos, no watermark.
             """),
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
