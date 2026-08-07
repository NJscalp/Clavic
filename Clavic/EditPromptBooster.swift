//
//  EditPromptBooster.swift
//  Clavic
//
//  Gemeinsamer Realismus-Booster für freie Bild-Edit-Prompts (Nano Banana 2).
//  Wird vom Chat (ChatEditView) UND vom Studio (StudioView, Nano-Banana-Edit)
//  genutzt. NB2 folgt Einfüge-Anweisungen wörtlich, hat aber schwache
//  räumliche Prioren — ohne explizite Maßstab-/Perspektiv-/Schatten-Regeln
//  klebt es Objekte wie Sticker ein („park a Ferrari in the garage" →
//  zu klein, schwebend, quer). Spiegelbild: clavic-web/lib/edit-prompt.ts.
//

import Foundation

enum EditPromptBooster {

    /// Woerter, an denen ein Umbau der PERSON haengt (Pose, Haltung, Blick).
    private static let poseKeys = [
        "pose", "posing", "posiere", "haltung", "stance",
        "stand ", "standing", "sit ", "sitting", "lean", "lehn",
        "turn around", "dreh", "walk", "laufen", "gehen",
        "look away", "schau weg", "over the shoulder", "ueber die schulter",
        "candid", "natural pose", "andere pose", "neue pose"
    ]

    static func wantsPoseChange(_ text: String) -> Bool {
        let lower = text.lowercased()
        return poseKeys.contains { lower.contains($0) }
    }

    /// Woerter, an denen das EINSETZEN einer Person haengt.
    private static let personInsertKeys = [
        "add me", "put me", "place me", "insert me", "add myself", "me into",
        "me in the", "me in this", "add her", "add him", "add us", "put her",
        "put him", "put us", "add a person", "add someone", "insert a person",
        "fueg mich", "fuege mich", "setz mich", "setze mich", "stell mich",
        "stelle mich", "pack mich", "mich ins", "mich in das", "mich in dieses",
        "mich auf das", "mich hinzu"
    ]

    /// „Setz MICH in dieses Bild." — das ist kein Objekt-Einfuegen.
    ///
    /// GEMESSENER FEHLER: „add me in the image" traf nur das Schluesselwort
    /// `add ` und landete im Objekt-Zweig, der fuer „park a Ferrari in the
    /// garage" geschrieben wurde. Der befiehlt woertlich, die Beleuchtung
    /// unveraendert zu lassen, und sagt kein Wort zur Haltung. Heraus kam
    /// genau das: die Person als Aufkleber, Haltung 1:1 aus dem Referenzfoto,
    /// Licht der Szene ignoriert.
    static func wantsPersonInsert(_ text: String) -> Bool {
        let lower = text.lowercased()
        return personInsertKeys.contains { lower.contains($0) }
    }

    /// Welche Anfragen ueber Nano Banana 2 laufen muessen.
    ///
    /// Beides sind Umbauten AM KOERPER: eine neue Haltung, und das Einsetzen
    /// einer Person, die eine neue Haltung braucht. GPT Image 2 laesst die
    /// Haltung messbar unveraendert (siehe `ImageEditAPI.poseModel`) — und
    /// eine uebernommene Haltung IST der Aufkleber-Effekt.
    static func needsPoseModel(_ text: String) -> Bool {
        wantsPoseChange(text) || wantsPersonInsert(text)
    }

    /// Die Person darf beim Umposen NICHT neu erfunden werden.
    static let identityRule = """
    Keep the exact same person: same face and every feature of it, same hair, same skin tone and     real skin texture, same build and body proportions, same age, same outfit. Do NOT beautify,     slim, smooth or redraw them, and do not replace them with a look-alike.
    """

    /// Ohne diese Regel steht die Person schattenlos in der Szene. Der haeufigste
    /// Grund, warum ein sonst gutes Ergebnis sofort als Montage auffaellt.
    static let sceneLightRule = """
    LIGHT AND SHADOW MUST MATCH THE SCENE. Read where the light in this photograph comes from —     its direction, height, hardness and colour — and light the person with exactly that light.     If the scene is in hard sunlight, the person needs a bright lit side, a clearly darker shadow     side and crisp shadow edges; if it is overcast or shaded, soft and even. The person MUST cast     a shadow on the ground running in the same direction and with the same length and softness as     every other shadow already in the frame, plus contact shadow where feet meet the ground.     Match the scene's exposure, contrast and colour cast. A person without a shadow, or lit     differently from their surroundings, reads as pasted in and is a failed result.
    """

    /// Was im Bild erhalten bleiben muss — abhaengig davon, OB ein Mensch
    /// darauf ist. Vorher stand hier immer „same face and hairstyle"; bei einem
    /// Autofoto war das nur erfuellbar, indem das Modell eine Person erfand.
    private static func subjectRule(_ hasPerson: Bool?) -> String {
        switch hasPerson {
        case .some(true):  return "Keep the same subject — same face and hairstyle —"
        case .some(false): return "Keep the same subject and every object in it"
        case .none:        return "Keep the same subject exactly as it is"
        }
    }

    /// Steht NUR unter Bildern ohne Menschen. Ein Verbot allein reicht nicht:
    /// das Modell fuellt „leere" Szenen gern mit Menschen, wenn nichts dagegen
    /// spricht — also sagt es die Regel ausdruecklich.
    private static func noPeopleRule(_ hasPerson: Bool?) -> String {
        guard hasPerson == false else { return "" }
        return """


        THERE IS NO PERSON IN THIS PHOTOGRAPH AND THERE MUST BE NONE IN THE RESULT.         Do NOT add, invent or imply any person, face, human figure, hand, silhouette or         reflection of a person anywhere in the image. If the instruction mentions swapping         or replacing something, it refers to the object, never to a person.
        """
    }

    /// Baut einen image-to-image-Prompt, der je nach Nutzer-Absicht das
    /// Original-Foto maximal erhält. Nur für FREIE Nutzer-Prompts mit
    /// Referenzbild gedacht — kuratierte Template-Prompts nicht wrappen.
    ///
    /// `hasPerson` kommt aus `SubjectDetector` und entscheidet, ob die
    /// Personen-Regeln ueberhaupt gelten. `nil` = unbekannt → neutral.
    /// `referenceCount` ist die Zahl der mitgeschickten Bilder. Ab zwei muss
    /// der Prompt sagen, WELCHES was ist — ohne Nummerierung mischt das Modell
    /// bei zwei Referenzen Szene und Person (dieselbe Erfahrung wie in
    /// `PosePrompt.imageOrderNote`).
    static func build(_ user: String, hasPerson: Bool? = nil, referenceCount: Int = 1) -> String {
        let lower = user.lowercased()

        // Nur Hintergrund ändern → strengste Erhalt-Regel.
        let backgroundKeys = [
            "background", "backdrop", "hintergrund", "scenery", "landscape behind",
            "sky behind", "change the bg", "replace the bg", "new background",
            "hintergrund ändern", "hintergrund wechseln", "umgebung ändern",
            "behind me", "hinter mir", "scene behind"
        ]
        if backgroundKeys.contains(where: { lower.contains($0) }) {
            return """
            Image-to-image edit of the provided photo. Replace ONLY the background as described below. \
            Keep the foreground subject, pose, outfit, accessories, objects and lighting on the \
            subject exactly as in the original photo. Do NOT generate a new subject, new pose or new scene. \
            Only change the background: \(user)\(noPeopleRule(hasPerson))
            """
        }

        // PERSON EINSETZEN — noch vor der Pose. Wer „add me in the image"
        // schreibt, will beides: hineinkommen UND dabei natuerlich dastehen.
        if wantsPersonInsert(user) {
            let order = referenceCount >= 2
                ? """
                You are given exactly two reference images. IMAGE 1 is the SCENE — the photograph \
                the person has to end up in. IMAGE 2 is the PERSON — use it ONLY for identity: \
                face, hair, skin, build and outfit. Never copy IMAGE 2's background, lighting or \
                pose into the result.


                """
                : ""
            return """
            \(order)Image-to-image edit of the provided photo. Insert the person from the reference \
            photo INTO this scene, as if they had really been there when the photograph was taken. \
            The scene itself is sacred: location, background, camera angle, framing and everything \
            already in the frame stay exactly as they are.

            \(identityRule)

            BUILD A NEW POSE FOR THIS PLACE. Do NOT copy the pose, body angle, head tilt, gaze or \
            expression from the reference photo. A carried-over pose is the clearest sign of a \
            paste-in and counts as a failed result. Invent a natural, relaxed pose that belongs in \
            THIS location and makes sense with what is around them: real weight on the ground, \
            believable balance, one leg carrying more than the other, relaxed arms and hands, a \
            head angle and gaze that fit the scene. Re-render the whole body — head, neck, \
            shoulders, torso, arms, hands, legs and feet — as one continuous person in that new \
            pose, with real anatomy, correct foreshortening and clothing that falls the way fabric \
            would in that position. No seam at the neck or wrists.

            SCALE AND PERSPECTIVE. Size them against what is already in the frame — doors, chairs, \
            tables, cars, railings: a real adult is roughly door-handle to top-of-door tall. Match \
            the photograph's camera height, lens foreshortening and vanishing lines. Their feet \
            stand on the same ground plane as everything else: never floating, never sliding up a \
            wall, never a small distant cut-out.

            \(sceneLightRule)

            No halo, no hard cut-out edge, no sticker look, no plastic skin, no beauty filter. If \
            any edge of them still looks composited, redo the lighting until a stranger would \
            believe one camera took one photograph.

            Instruction: \(user)
            """
        }

        // POSE ZUERST PRUEFEN — vor dem Stil.
        //
        // GEMESSENER FEHLER (05.08.2026): der Nutzer schrieb „mach einen G7X
        // Filter darauf, mach eine aesthetic pose". Das traf die Stil-Liste
        // (g7x, filter — und ausgerechnet auch „aesthetic"), und der Stil-Zweig
        // schickt „Keep the exact same subject, POSE, composition ..." los. Die
        // App hat dem Modell also woertlich befohlen, die Pose NICHT zu
        // aendern, obwohl genau danach gefragt war. Ergebnis: Person 1:1
        // uebernommen, Pose unveraendert.
        //
        // Deshalb: Wer eine Pose will, bekommt den Pose-Zweig — und wenn
        // gleichzeitig ein Look gewuenscht ist, beides in EINEM Prompt.
        let wantsPose = wantsPoseChange(user)

        // Stil / Kamera / Look → Komposition + Motiv bleiben, nur Look ändert sich.
        let styleKeys = [
            "g7x", "camera", "flash", "lighting", "filter", "style", "look like",
            "cinematic", "vintage", "grain", "color grade", "lut", "aesthetic",
            "kamera", "blitz", "stil", "aussehen wie"
        ]
        let wantsStyle = styleKeys.contains { lower.contains($0) }

        if wantsPose {
            // Pose aendern heisst: Koerper NEU zeichnen, Person und Ort behalten.
            // Dazu zwingend die Lichtregel — ohne sie steht die Person ohne
            // Schatten in der Szene und wirkt eingeklebt (genau der Fehler im
            // Testbild vom 05.08.: harte Mittagssonne ringsum, Person flach
            // ausgeleuchtet, kein Schlagschatten).
            let styleNote = wantsStyle
                ? "\n\nApply the requested camera look / colour grade on top, as a grade over the whole photograph — it must affect the scene and the person equally."
                : ""
            return """
            Image-to-image edit of the provided photo. Change the person's POSE as described, and \
            re-render their body, limbs, hands and clothing correctly for that new pose with real \
            anatomy, real foreshortening and fabric that falls the way it would in that position.

            \(identityRule)

            \(sceneLightRule)\(styleNote)

            Requested change: \(user)
            """
        }

        if wantsStyle {
            return """
            Image-to-image edit of the provided photo. Keep the exact same subject, pose, composition, \
            framing and scene layout. Do NOT create a new subject or new scene. Apply only this visual \
            style or camera look to the existing photo: \(user)\(noPeopleRule(hasPerson))
            """
        }

        // Objekt/Element HINZUFÜGEN → strenge Maßstab-, Perspektiv- & Schatten-
        // Regeln. Die häufigste Realismus-Falle: „park a Ferrari in the garage".
        let addKeys = [
            "add ", "put ", "place ", "insert ", "spawn ", "give me ", "give it ",
            "füge", "stell", "setz", "pack", "leg", "tu ", "tue ", "mach ", "rein",
            "hinein", "dazu", "hinzu", "parke", "park "
        ]
        if addKeys.contains(where: { lower.contains($0) }) {
            return """
            Image-to-image edit of the provided photo. Add or insert the described element INTO the existing \
            photo — do not regenerate the scene. Keep the original scene, subject, people, background, \
            framing and lighting exactly as they are; only add or change what the instruction describes.
            CRITICAL realism & scale rules: render the new element at correct, true-to-life real-world scale \
            and proportions relative to its surroundings — sized naturally, NEITHER too small nor too large, \
            and NOT pasted in as a tiny distant cut-out. Position and orient it the way it would naturally \
            sit, stand or be parked in reality. If the element is a vehicle: it has just been driven in and \
            is parked in its final resting position — its body sits perfectly straight in the parking bay at \
            a yaw angle of exactly 0° to the room: the car's long axis runs exactly parallel to the side \
            walls with an EQUAL gap to the left and right wall, all four wheels straight, hood and roof \
            lines following the same vanishing point as the walls and floor lines, like a real parked car \
            rather than a showroom pose. If the instruction names a specific brand or model, reproduce that \
            EXACT real production car with its authentic body design, and render the manufacturer's genuine \
            emblem and badges accurately — correct shape, colours and placement, crisp and undistorted, \
            exactly as on the real car, never invented, warped or misspelled. Match the exact camera angle, perspective and \
            vanishing lines of the photo. Ground it firmly in the scene with realistic contact shadows where \
            it meets the floor or surface, and keep lighting direction, reflections, colour temperature and \
            depth of field consistent with the original. Photorealistic, indistinguishable from a real photograph.
            Instruction: \(user)\(noPeopleRule(hasPerson))
            """
        }

        // Sonstige kreative Änderungen — Motiv bleibt, plus allgemeine
        // Realismus-Klausel (Maßstab/Perspektive/Licht/Schatten).
        return """
        Image-to-image edit of the provided photo. \(subjectRule(hasPerson)) and the \
        existing scene; apply the instruction on the existing photo, do not generate an unrelated new image. \
        Keep real-world scale, correct perspective, consistent lighting, reflections and natural shadows so \
        the result stays photorealistic. User instruction: \(user)\(noPeopleRule(hasPerson))
        """
    }
}
