//
//  PoseCamera.swift
//  Clavic
//
//  „Recreate": ein Referenzbild (z. B. von Pinterest) liegt halbtransparent
//  ÜBER dem Live-Kamerabild. Man sieht sich selbst und die Vorlage gleichzeitig
//  und kann die Pose nachstellen, bevor ausgelöst wird. Danach fragt die App im
//  Chat, was daraus werden soll — z. B. „swap me with the person sitting on the
//  Lamborghini".
//
//  Ablauf:
//    1. Referenz wählen (Fotomediathek ODER Link, auch eine Pinterest-Pin-URL)
//    2. Aufnehmen — Vorlage liegt durchsichtig über der Kamera, verschiebbar,
//       skalierbar, Deckkraft regelbar
//    3. Sagen, was passieren soll → beide Bilder gehen als Referenzen an
//       GPT Image 2, der Prompt wird aus der Absicht gebaut (PoseIntent)
//
//  Diese Datei enthält nur Kamera + Auswahl + Prompt-Bau. Gesendet wird über
//  den normalen Chat-Weg (ChatEditView.send), damit Credits, Fehlerbehandlung,
//  Library-Ablage und Verlauf sich exakt gleich verhalten.
//

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Ergebnis

/// Was der Kamera-Modus an den Chat zurückgibt.
struct PoseCameraResult {
    /// Die eigene Aufnahme (oder ein aus der Mediathek gewähltes Selfie).
    var shot: Data
    /// Die Vorlage, die über der Kamera lag.
    var reference: Data
    /// Kurzer Satz für die Chat-Blase — das, was der Nutzer wollte.
    var instruction: String
    /// Fertiger, ausformulierter Prompt für das Modell.
    var prompt: String
}

// MARK: - Absichten

/// Was mit Vorlage + eigener Aufnahme geschehen soll. Jede Absicht hat einen
/// eigenen Prompt, weil die Fälle sich grundlegend unterscheiden: einmal
/// gewinnt die Vorlage (Szene bleibt, Person wird getauscht), einmal gewinnt
/// das eigene Foto (Person bleibt, nur der Look wandert herüber).
enum PoseIntent: String, CaseIterable, Identifiable {
    case swap        // Szene der Vorlage, aber ich bin die Person darin
    case pose        // meine Aufnahme, Pose sauber wie in der Vorlage
    case place       // ich am Ort/Hintergrund der Vorlage
    case look        // Outfit, Licht und Farbgebung der Vorlage auf mein Foto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swap:  return "Swap me in"
        case .pose:  return "Same pose"
        case .place: return "Same place"
        case .look:  return "Same look"
        }
    }

    var subtitle: String {
        switch self {
        case .swap:  return "I replace the person in the reference"
        case .pose:  return "My photo, posed exactly like the reference"
        case .place: return "Me, in the reference's location"
        case .look:  return "Outfit, lighting and colours from the reference"
        }
    }

    var icon: String {
        switch self {
        case .swap:  return "person.crop.rectangle.badge.plus"
        case .pose:  return "figure.stand"
        case .place: return "mappin.and.ellipse"
        case .look:  return "paintpalette"
        }
    }

    /// Kurzer Satz, der in der Chat-Blase erscheint.
    var chatLine: String {
        switch self {
        case .swap:  return "Swap me with the person in the reference"
        case .pose:  return "Put me in the exact pose from the reference"
        case .place: return "Put me in the location from the reference"
        case .look:  return "Give me the outfit and look from the reference"
        }
    }
}

// MARK: - Prompt

enum PosePrompt {

    /// Beide Bilder gehen in FESTER Reihenfolge an das Modell:
    ///   IMAGE 1 = die eigene Aufnahme (die Person, die erhalten bleiben muss)
    ///   IMAGE 2 = die Vorlage (Szene, Pose, Look)
    /// Der Prompt benennt sie genau so. Ohne diese Nummerierung mischt GPT
    /// Image 2 bei zwei Referenzen die Gesichter — es weiß sonst nicht, wer
    /// von beiden „ich" ist.
    static func imageOrderNote(hasPerson: Bool) -> String {
        let first = hasPerson
            ? "IMAGE 1 is a photo of ME — my face, my body, my identity."
            : "IMAGE 1 shows the OBJECT that must end up in the result — no person is involved."
        return """
    You are given exactly two reference images. \(first) \
    IMAGE 2 is the reference I want to recreate.

    The two images are INSTRUCTIONS, never layers. Produce ONE single, opaque, \
    fully rendered photograph. Do NOT overlay, blend, cross-fade, double-expose or \
    ghost the two images onto each other. Nothing from IMAGE 2 may appear as a \
    translucent outline, a faint silhouette or a see-through copy anywhere in the \
    result, and no part of IMAGE 1 may show through anything. Every pixel of the \
    output must be a solid, believable part of one real scene.
    """
    }

    /// Identitäts-Regel: das Gesicht darf NIE „schöner" gemacht werden. Genau
    /// daran erkennt man KI-Bilder — ein glattgezogenes Fremdgesicht auf einem
    /// echten Körper.
    ///
    /// Wichtig: „same skin tone" meint Melanin/Unterton der Person — NICHT den
    /// Weißabgleich oder die Belichtung von IMAGE 1. Sonst klebt das Selfie-Licht
    /// auf der Person und sie wirkt falsch in der Szene.
    static let identityRule = """
    Copy my face from IMAGE 1 exactly, feature by feature, as if it were cloned: the same \
    face shape and width, the same jawline and chin, the same eye shape, spacing and colour, \
    the same eyebrows including their exact thickness and any gap or scar in them, the same \
    nose, the same lips, the same ears, the same hairline and hair texture, the same beard or \
    stubble at the same density, and my natural melanin / undertone. Reproduce every individual \
    mark my face carries — every mole, freckle, birthmark, scar, blemish and line — in the same \
    place, at the same size. Do NOT beautify, slim, smooth, retouch, age, de-age or idealise me. \
    Do NOT produce a person who merely resembles me: a look-alike is a failure. Do NOT blend my \
    face with the face of the person in IMAGE 2 in any amount. Someone who knows me must \
    recognise me instantly, and must be unable to point to a single feature that changed.

    IDENTITY IS SHAPE AND FEATURES ONLY. Do NOT copy the lighting, white balance, flash look, \
    exposure or colour grade of IMAGE 1 onto me in the result.
    """

    /// Licht-Regel: steht bewusst am Ende des Prompts (vor optionalem Extra),
    /// weil Modelle den Schluss am stärksten gewichten — und genau hier ist der
    /// häufigste Fake-Look: Pose stimmt, Person wirkt aber belichtet wie das Selfie.
    static func lightingLock(sceneHint: String?, hasPerson: Bool = true) -> String {
        let measured: String
        if let sceneHint, !sceneHint.isEmpty {
            measured = """

            Measured look of the TARGET scene (IMAGE 2) — match me to this, not to IMAGE 1: \
            \(sceneHint)
            """
        } else {
            measured = ""
        }

        // Ohne Person geht es um dasselbe Problem — nur heisst der Gegenstand
        // nicht „ich". Der Personen-Text wuerde hier sonst wieder einen Menschen
        // einfordern, gegen das Verbot weiter oben.
        guard hasPerson else {
            return """
            LIGHTING LOCK — THIS IS WHAT MAKES THE RESULT REAL OR FAKE.
            The object can be placed perfectly and still look fake if it keeps IMAGE 1's light. \
            Relight the object completely as if it had physically been there when IMAGE 2 was taken.\
            \(measured)

            EVERY SURFACE of the object must be re-rendered under IMAGE 2's light: discard IMAGE 1's \
            light, white balance and contrast entirely. Key light from the same side, same height and \
            same hardness as everything already in IMAGE 2. Reflections on paint, chrome, glass and \
            metal must mirror IMAGE 2's actual surroundings — its sky, walls and ground — never \
            IMAGE 1's. The object MUST cast a shadow running in the same direction, with the same \
            length and softness, as every other shadow in the frame, plus firm contact shadow where \
            it meets the ground. An object without a shadow, or lit differently from its \
            surroundings, reads as pasted in and is a failed result.
            """
        }

        return """
        LIGHTING LOCK — THIS IS WHAT MAKES THE RESULT REAL OR FAKE.
        The pose can be perfect and still look wrong if I am lit like IMAGE 1. Relight me \
        completely as if I was physically standing in IMAGE 2 when that photo was taken.\
        \(measured)

        EVERY PIXEL OF MY SKIN, HAIR AND CLOTHES must be re-rendered under IMAGE 2's light:
        - Discard IMAGE 1's light entirely: phone flash, ring light, flat indoor ceiling, \
          window selfie light, its white balance, its contrast — none of it may remain.
        - Key light direction: same side, same height, same hardness/softness as on people \
          and objects already in IMAGE 2. Specular highlights on nose, forehead, cheeks, \
          lips, hair and fabric must come from that same direction.
        - Colour temperature: if IMAGE 2 is warm/golden, cool/blue, neon or mixed, my skin \
          and outfit must pick up that exact cast and any coloured bounce from nearby surfaces \
          (wall, car paint, sky, ground). No neutral phone-selfie skin in a warm scene.
        - Exposure match: same brightness, contrast, highlight roll-off and black level as \
          IMAGE 2. I must not look brighter, cleaner or sharper than the scene around me.
        - Shadows: my body casts contact shadows and ambient occlusion where I touch ground, \
          seats or props — same length, angle, softness and colour as shadows already visible \
          in IMAGE 2. No floating cut-out, no glowing halo, no dark pasted silhouette.
        - Integration: same grain/noise, same slight blur/depth of field falloff, same lens \
          character as IMAGE 2. If any edge of me still looks composited, redo the lighting \
          until a stranger would believe one camera took one photo.

        Photorealistic result only. No plastic skin, no beauty filter, no sticker look.
        """
    }

    /// `sceneImage`: die Zielszene (IMAGE 2) — daraus lesen wir Weißabgleich und
    /// Helligkeit und schreiben sie als konkrete Vorgabe in den Licht-Block.
    /// Fuer Bilder OHNE Menschen. Der gesamte Prompt oben ist auf „ich" und
    /// „mein Gesicht" gebaut — GEMESSEN am 06.08.2026 fuehrte das dazu, dass
    /// beim Tausch zweier AUTOS eine Person ins Bild erfunden wurde, weil der
    /// Prompt eine verlangte. Diese Fassung spricht ausschliesslich vom Objekt.
    static let objectIdentityRule = """
    Keep the object from IMAGE 1 EXACTLY as it is: same model and body shape, same colour and \
    finish, same wheels, same trim, badges, lettering and every visible detail. Do NOT swap it \
    for a similar-looking one, do not restyle it, do not change its year, class or proportions. \
    Someone who owns this exact object must recognise it immediately.

    THERE IS NO PERSON IN EITHER IMAGE AND THERE MUST BE NONE IN THE RESULT. Do NOT add, invent \
    or imply any person, face, driver, passenger, hand, silhouette or reflection of a person \
    anywhere in the image. Empty seats stay empty.
    """

    private static func objectCore(intent: PoseIntent) -> String {
        switch intent {
        case .swap:
            return """
            Take the object from IMAGE 1 and put it into the photograph from IMAGE 2, in place of \
            the corresponding object there. Everything else in IMAGE 2 stays exactly as it is: the \
            same location, camera angle, framing, time of day and every other object in the frame.
            """
        case .pose:
            return """
            Show the object from IMAGE 1 in the same position, angle and orientation as the \
            corresponding object in IMAGE 2, keeping IMAGE 2's location and camera perspective.
            """
        case .place:
            return """
            Place the object from IMAGE 1 into the location shown in IMAGE 2, standing or parked \
            the way it naturally would, with correct scale and perspective for that place.
            """
        case .look:
            return """
            Keep the object from IMAGE 1 and apply the colour treatment, lighting mood and overall \
            look of IMAGE 2 to the whole photograph.
            """
        }
    }

    /// `hasPerson: false` schaltet auf die Objekt-Fassung um.
    static func build(intent: PoseIntent, userText: String, sceneImage: Data? = nil,
                      hasPerson: Bool = true) -> String {
        let extra = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let core: String

        switch intent {
        case .swap:
            // GEMESSEN an einem echten Durchlauf (Selfie eines Mannes + Vorlage
            // „Frau im Kleid auf einem Lamborghini"): ohne die folgende, sehr
            // explizite Trennung setzt das Modell zwar mein GESICHT ein, behält
            // aber Kleid, Damenschuhe und die fremde Körperform bei. Ergebnis:
            // mein Kopf auf einem fremden Körper — genau der „Fake"-Look, den es
            // zu vermeiden gilt. Deshalb steht hier ausdrücklich, was aus WELCHEM
            // Bild kommt, und zwar getrennt nach Person und Umgebung.
            core = """
            Recreate the photograph in IMAGE 2, but the person in it is ME from IMAGE 1.

            THIS IS A FULL PERSON REPLACEMENT, NOT A FACE SWAP. Do not cut out my head and \
            paste it onto the other person's body — that always looks fake. The entire human \
            being in the result is me: my head AND my neck, shoulders, torso, arms, hands, \
            legs and skin, all in one piece, all with my own build, with no seam or tone \
            break at the neck or wrists.

            Take from IMAGE 2: the surroundings, framing, camera, BODY POSE (limb positions, \
            head angle, gaze) — and the SCENE LIGHTING that must light me.
            Take from IMAGE 1: my identity, hair, build, gender presentation, clothes and shoes \
            only — never IMAGE 1's lighting.
            The original person in IMAGE 2 is gone completely — none of their face, body, \
            skin, hands, clothing, shoes, jewellery or hair may survive anywhere in the \
            result. Never put me into their garments. If my outfit from IMAGE 1 is only \
            partly visible, continue it plausibly in the same style and fabric.

            I occupy their position with correct contact, correct weight and my own real \
            body proportions at a believable scale.

            POSE LOCK: limb positions, torso angle, head tilt, hands and gaze match IMAGE 2, \
            not IMAGE 1. Keeping my selfie pose inside IMAGE 2's scene is a failure.
            """
        case .pose:
            core = """
            Keep MY photo from IMAGE 1 — same person, same outfit, same location and same \
            background. Change only my body pose so that it matches the pose in IMAGE 2 \
            exactly: same limb positions, same body angle, same head tilt, same hands, \
            same weight distribution. Re-render my body and clothing naturally for that \
            new pose, with correct anatomy, correct foreshortening and fabric that falls \
            the way it would in that position. Keep IMAGE 1's scene lighting consistent \
            across my newly posed body — no mismatched lit limbs.
            """
        case .place:
            // Früher blieb die Selfie-Pose stehen — eingefügt wirkte man wie ein
            // Aufkleber. Pose muss neu zur Szene entstehen; Identität und Outfit
            // kommen aus IMAGE 1, Ort aus IMAGE 2.
            core = """
            Place ME from IMAGE 1 into the location and environment of IMAGE 2: \
            same background, same setting, same time of day, same atmosphere. Do NOT \
            copy the person from IMAGE 2 into the result — only their surroundings.

            Keep my exact identity, face, body shape, hair and the outfit from IMAGE 1. \
            Do NOT keep my original pose from IMAGE 1 if that pose is a stiff selfie, \
            mirror shot or phone-facing stance — invent a natural, aesthetic pose that \
            belongs in this location: real weight on the ground, believable balance, \
            relaxed limbs, correct contact with floor or props, camera height and \
            perspective matching IMAGE 2. Re-render my full body in that pose as one \
            continuous person with natural fabric drape. Never floating, never cut-out.
            """
        case .look:
            core = """
            Keep MY photo from IMAGE 1 — same person, same pose, same framing, same \
            location. Transfer only the styling from IMAGE 2 onto me: the outfit and its \
            fabrics, the accessories, the hair styling, the make-up, plus the lighting \
            setup and the colour grade of that photo. Fit the clothing to my actual body \
            with real folds, real seams and correct drape, as if I were genuinely wearing it.
            """
        }

        // Licht zuletzt: Pose kann stimmen und trotzdem fake wirken, wenn das
        // Selfie-Licht auf der Person kleben bleibt. Der gemessene Szenen-Hint
        // gibt dem Modell konkrete Temperatur/Helligkeit statt nur „match light".
        let sceneHint = sceneImage.flatMap { SceneLightingHints.describe($0) }
        var parts = hasPerson
            ? [imageOrderNote(hasPerson: true), core, identityRule,
               lightingLock(sceneHint: sceneHint, hasPerson: true)]
            : [imageOrderNote(hasPerson: false), objectCore(intent: intent), objectIdentityRule,
               lightingLock(sceneHint: sceneHint, hasPerson: false)]
        if !extra.isEmpty {
            // Extra darf Stil ergänzen, aber nicht Selfie-Licht oder Pose retten.
            parts.append("""
            Extra direction from me (style and mood only — do not keep IMAGE 1's \
            lighting, do not keep a stiff selfie pose, do not change my identity, \
            do not ignore the lighting lock above): \(extra)
            """)
        }
        return parts.joined(separator: "\n\n")
    }
}

/// Liest aus der Zielszene grob Helligkeit und Wärmeton — als konkrete Vorgabe
/// im Prompt, nicht als Bildbearbeitung. Modelle folgen „warm golden, dim side
/// light" zuverlässiger als einem generischen „match the lighting".
enum SceneLightingHints {
    static func describe(_ data: Data) -> String? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        return describe(image)
    }

    static func describe(_ cgImage: CGImage) -> String? {
        let sampleSide = 48
        guard let context = CGContext(
            data: nil,
            width: sampleSide,
            height: sampleSide,
            bitsPerComponent: 8,
            bytesPerRow: sampleSide * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
        guard let bytes = context.data else { return nil }

        let buffer = bytes.bindMemory(to: UInt8.self, capacity: sampleSide * sampleSide * 4)
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var sumLuma = 0.0
        let count = Double(sampleSide * sampleSide)
        for i in 0..<(sampleSide * sampleSide) {
            let o = i * 4
            let r = Double(buffer[o])
            let g = Double(buffer[o + 1])
            let b = Double(buffer[o + 2])
            sumR += r; sumG += g; sumB += b
            sumLuma += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let r = sumR / count, g = sumG / count, b = sumB / count
        let luma = sumLuma / count / 255.0
        let warmth = (r - b) / 255.0

        let brightness: String
        switch luma {
        case ..<0.22: brightness = "dim / low-key"
        case ..<0.40: brightness = "softly lit"
        case ..<0.62: brightness = "moderately bright"
        default: brightness = "bright / high-key"
        }

        let temperature: String
        switch warmth {
        case ..<(-0.08): temperature = "cool / blue-cyan cast"
        case ..<(-0.03): temperature = "slightly cool"
        case ..<0.03: temperature = "neutral white balance"
        case ..<0.10: temperature = "warm / golden cast"
        default: temperature = "strongly warm / amber-orange cast"
        }

        // Grobe Seiten-Asymmetrie: linke vs. rechte Bildhälfte — Hint auf
        // seitliches Schlüssellicht, wenn eine Seite klar heller ist.
        var leftLuma = 0.0, rightLuma = 0.0
        let half = sampleSide / 2
        for y in 0..<sampleSide {
            for x in 0..<sampleSide {
                let o = (y * sampleSide + x) * 4
                let lum = 0.2126 * Double(buffer[o]) + 0.7152 * Double(buffer[o + 1]) + 0.0722 * Double(buffer[o + 2])
                if x < half { leftLuma += lum } else { rightLuma += lum }
            }
        }
        let cells = Double(sampleSide * half)
        leftLuma /= cells; rightLuma /= cells
        let sideBias = (rightLuma - leftLuma) / 255.0
        let direction: String
        switch sideBias {
        case 0.06...: direction = "stronger light from the right side of the frame"
        case ...(-0.06): direction = "stronger light from the left side of the frame"
        default: direction = "fairly even left/right illumination (front or overhead key more likely)"
        }

        return "\(brightness); \(temperature); \(direction)"
    }
}

// MARK: - Referenz aus dem Netz

enum ReferenceLoader {

    enum LoadError: LocalizedError {
        case badURL, noImageFound, notAnImage

        var errorDescription: String? {
            switch self {
            case .badURL: return "That doesn't look like a link."
            case .noImageFound: return "Couldn't find an image on that page — open the pin, tap Share → Copy link, or save the picture to your photos."
            case .notAnImage: return "That link didn't return a picture."
            }
        }
    }

    /// Holt ein Bild aus einem Link. Zwei Fälle:
    ///  - direkter Bild-Link (i.pinimg.com/…jpg) → direkt laden
    ///  - Seiten-Link (pinterest.com/pin/…) → HTML holen und Bild heraussuchen
    ///
    /// Der Browser-User-Agent ist Pflicht: ohne ihn liefert Pinterest eine
    /// leere App-Shell ohne Meta-Tags.
    static func load(from raw: String) async throws -> Data {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text), url.host != nil else { throw LoadError.badURL }

        let (data, response) = try await fetch(url)
        let mime = (response as? HTTPURLResponse)?.mimeType ?? ""

        if mime.hasPrefix("image/") || UIImage(data: data) != nil {
            guard UIImage(data: data) != nil else { throw LoadError.notAnImage }
            return data
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let imageURL = extractImageURL(from: html) else {
            throw LoadError.noImageFound
        }
        // GEMESSEN: Pinterests og:image zeigt auf die 736px-Variante (736×1308),
        // dieselbe Datei liegt unter /originals/ in 1200×2133. Als Vorlage für
        // einen Swap ist das ein spürbarer Unterschied, also zuerst die große
        // Fassung versuchen und nur bei Fehlschlag auf die kleine zurückfallen.
        if let big = upgradedToOriginal(imageURL),
           let (bigData, _) = try? await fetch(big),
           UIImage(imgData: bigData) != nil {
            return bigData
        }
        let (imgData, _) = try await fetch(imageURL)
        guard UIImage(imgData: imgData) != nil else { throw LoadError.notAnImage }
        return imgData
    }

    /// `…/736x/ab/cd/ef/hash.jpg` → `…/originals/ab/cd/ef/hash.jpg`.
    /// Nur für i.pinimg.com; andere Hosts bleiben unangetastet.
    static func upgradedToOriginal(_ url: URL) -> URL? {
        guard url.host?.hasSuffix("pinimg.com") == true else { return nil }
        var parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 5 else { return nil }
        guard parts[0] != "originals" else { return nil }
        parts[0] = "originals"
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.path = "/" + parts.joined(separator: "/")
        return comps?.url
    }

    private static func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    /// Sucht die beste Bild-URL im HTML. `og:image` ist das vom Betreiber selbst
    /// benannte Hauptbild — alles andere ist Raten.
    ///
    /// Pinterest schreibt das Tag als
    /// `<meta content="…" data-app="true" name="og:image" property="og:image"/>` —
    /// `content` steht VOR `property`. Deshalb sind beide Reihenfolgen abgedeckt;
    /// mit nur der üblichen (property zuerst) findet man auf Pinterest nichts.
    static func extractImageURL(from html: String) -> URL? {
        let patterns = [
            #"<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']"#,
            #"<meta[^>]*name=["']twitter:image["'][^>]*content=["']([^"']+)["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html) else { continue }
            if let url = normalizedURL(String(html[r])) { return url }
        }
        return mostReferencedPinImage(in: html)
    }

    /// Notfall, wenn kein Meta-Tag da ist: die HÄUFIGSTE Bilddatei nehmen.
    ///
    /// Naheliegend wäre, einfach die erste `…/originals/…`-URL zu greifen —
    /// GEMESSEN ist das aber falsch: die erste steht in Pinterests eigenem CSS
    /// und ist auf jeder Pin-Seite dieselbe Grafik. Das Pin-Bild dagegen kommt
    /// in vielen Größen vor (60x60, 236x, 474x, 736x, originals …) und ist damit
    /// die einzige Datei, die sich häuft — ein Zähler trifft sie zuverlässig,
    /// ein Positionsvergleich nicht.
    private static func mostReferencedPinImage(in html: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: #"https://i\.pinimg\.com/[^"'\\\s)]+"#) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        var counts: [String: Int] = [:]     // "ab/cd/ef/hash.jpg" → Anzahl
        var example: [String: String] = [:] // dieselbe Datei → eine echte URL
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: html) else { return }
            let raw = String(html[r])
            let parts = raw.replacingOccurrences(of: "https://i.pinimg.com/", with: "")
                .split(separator: "/").map(String.init)
            // Nach dem Größen-Segment stehen immer drei Hash-Ordner + Datei.
            guard parts.count >= 4 else { return }
            let key = parts.suffix(4).joined(separator: "/")
            counts[key, default: 0] += 1
            if example[key] == nil { example[key] = raw }
        }
        // Mindestens ZWEI Vorkommen verlangen. GEMESSEN an einem Pin, den
        // Pinterest nur als leere Hülle ausliefert: dort steht genau eine
        // einzige Bild-URL im HTML — Pinterests eigene Oberflächen-Grafik.
        // Ohne diese Schranke bekäme der Nutzer die als „seine Vorlage"
        // untergeschoben. Lieber nichts finden und das sauber sagen.
        guard let best = counts.max(by: { $0.value < $1.value }), best.value >= 2,
              let raw = example[best.key] else { return nil }
        return normalizedURL(raw)
    }

    /// HTML-/JSON-Maskierungen zurückdrehen, die in eingebetteten Skripten stehen.
    private static func normalizedURL(_ raw: String) -> URL? {
        let cleaned = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u002f", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
        guard let url = URL(string: cleaned), url.host != nil else { return nil }
        return url
    }
}

private extension UIImage {
    /// Kurzform, damit oben `UIImage(imgData:)` lesbar bleibt.
    convenience init?(imgData: Data) { self.init(data: imgData) }
}

// MARK: - Kamera

/// Dünne Hülle um AVCaptureSession: Vorschau, Front/Back-Wechsel, Auslösen.
@MainActor
@Observable
final class PoseCameraModel: NSObject {
    let session = AVCaptureSession()

    /// EINE Vorschau-Ebene für die gesamte Lebensdauer der Kamera.
    ///
    /// SwiftUI verwirft beim Schrittwechsel (Outfit → Ort) den ganzen Teilbaum
    /// und baut ihn neu auf. Entstünde dabei jedes Mal eine neue
    /// `AVCaptureVideoPreviewLayer`, hinge die neue Ebene an einer Sitzung,
    /// deren Vorschau-Verbindung noch die alte, gerade erst abgeräumte Ebene
    /// hält — die neue bekommt dann kein Bild und der Rahmen bleibt schwarz,
    /// obwohl die Sitzung läuft. Mit einer einzigen, dauerhaften Ansicht kann
    /// das nicht passieren: sie wird nur umgehängt, nie neu erzeugt.
    let previewView = CameraPreviewView()

    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var captureContinuation: CheckedContinuation<Data?, Never>?

    var isFront = true
    var isAvailable = false
    var permissionDenied = false
    /// Auf dem Simulator gibt es keine Kamera — dann führt die Ansicht direkt
    /// zur Mediathek, statt ein schwarzes Rechteck zu zeigen.
    var setupFinished = false

    /// Ob die Kamera laufen SOLL. `session.isRunning` allein taugt nicht als
    /// Grundlage: Start und Stopp laufen auf einem Hintergrund-Thread, direkt
    /// nach `stop()` meldet die Sitzung noch „läuft". Ein `start()` in diesem
    /// Moment würde verworfen, der Stopp danach greift trotzdem — und die
    /// Vorschau bliebe schwarz, obwohl `isAvailable` weiter true sagt.
    private var wantsRunning = false

    /// Mehrfach aufrufbar: läuft die Kamera schon und ist gewollt, passiert
    /// nichts. War sie gestoppt, wird sie neu aufgebaut und gestartet.
    func start() async {
        let wasWanted = wantsRunning
        wantsRunning = true
        if wasWanted, session.isRunning, input != nil { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { permissionDenied = true; setupFinished = true; return }
        default:
            permissionDenied = true; setupFinished = true; return
        }
        await configureAndRun()
    }

    func stop() {
        wantsRunning = false
        let s = session
        Task.detached { if s.isRunning { s.stopRunning() } }
    }

    /// Wechselt zwischen Front- und Rückkamera. Bewusst `async`: der Aufrufer
    /// muss warten können, bis das neue Eingabegerät wirklich hängt — sonst
    /// löst der nächste Schritt auf einer halb umgebauten Sitzung aus.
    func flip() async {
        isFront.toggle()
        await configureAndRun()
    }

    private func configureAndRun() async {
        let position: AVCaptureDevice.Position = isFront ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video) else {
            isAvailable = false; setupFinished = true; return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        // Die Referenz MUSS mit entfernt werden. Bleibt sie stehen und das neue
        // Eingabegerät lässt sich nicht anhängen, meldet `isAvailable` weiter
        // true — die Ansicht zeigt dann eine Vorschau ohne Eingang, also
        // Schwarz, und der Auslöser bleibt fälschlich bedienbar.
        let previous = input
        if let previous {
            session.removeInput(previous)
            self.input = nil
        }
        if let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
        } else if let previous, session.canAddInput(previous) {
            // Lieber bei der bisherigen Kamera bleiben als ganz ohne Bild
            // dastehen: schlägt der Wechsel fehl, hing die Sitzung sonst ohne
            // Eingang da und der Rahmen blieb leer, bis man neu einsteigt.
            session.addInput(previous)
            input = previous
            isFront = previous.device.position == .front
        }
        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        isAvailable = input != nil
        setupFinished = true
        guard isAvailable, wantsRunning else { return }

        let s = session
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task.detached {
                if !s.isRunning { s.startRunning() }
                cont.resume()
            }
        }
    }

    /// Löst aus und liefert JPEG-Daten. Bei der Frontkamera wird gespiegelt,
    /// damit das Ergebnis dem entspricht, was auf dem Bildschirm zu sehen war —
    /// sonst steht die mühsam nachgestellte Pose hinterher seitenverkehrt zur
    /// Vorlage.
    func capture() async -> Data? {
        guard isAvailable else { return nil }
        let settings = AVCapturePhotoSettings()
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isFront
        }
        return await withCheckedContinuation { cont in
            captureContinuation = cont
            output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension PoseCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            captureContinuation?.resume(returning: error == nil ? data : nil)
            captureContinuation = nil
        }
    }
}

/// Die dauerhafte Ansicht, die das Live-Bild trägt. Sie gehört dem Kameramodell
/// (`PoseCameraModel.previewView`) und überlebt jeden SwiftUI-Neuaufbau.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyCornerRadius(_ radius: CGFloat) {
        // Ohne masksToBounds zeichnet der Preview-Layer eckig über den
        // SwiftUI-Rahmen hinaus — die Ecken sehen dann „nicht rund" aus.
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        layer.masksToBounds = true
    }
}

/// Live-Vorschau der Kamera. Reicht nur die bestehende Ansicht des Modells
/// durch, statt eine eigene zu erzeugen.
struct CameraPreviewLayer: UIViewRepresentable {
    let camera: PoseCameraModel
    var cornerRadius: CGFloat = 0

    func makeUIView(context: Context) -> CameraPreviewView {
        attach(camera.previewView)
        return camera.previewView
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        attach(uiView)
    }

    private func attach(_ view: CameraPreviewView) {
        if view.videoPreviewLayer.session !== camera.session {
            view.videoPreviewLayer.session = camera.session
        }
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.applyCornerRadius(cornerRadius)
    }
}
