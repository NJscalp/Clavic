//
//  AiCharacter.swift
//  Clavic
//
//  „AI Character"-Generator: erzeugt bei jedem Generieren eine ANDERE,
//  ultra-realistische, einzigartige Person (wie ein echtes Foto) – ohne dass
//  der Nutzer ein Foto hochlädt. Der Nutzer wählt nur Geschlecht, Hautfarbe,
//  Augenfarbe, Haarfarbe (+ optionaler Prompt); alles andere (Frisur, Alter,
//  Ethnie-Hinweis, Ausdruck, Details, Hintergrund, Outfit, Beleuchtung) wird
//  ZUFÄLLIG aus Pools zusammengewürfelt → 100.000+ verschiedene Menschen.
//
//  Technik: Das Backend braucht mind. 1 Bild (`/v1/gpt-image/edit` lehnt leere
//  `images` mit `missing_image` ab). Wir senden ein neutrales GRAUES Seed-Bild
//  (keine Identität) + den gebauten Prompt. GPT Image 2 erzeugt daraus eine
//  neue, einzigartige Person mit den gewählten Attributen. Da das Seed keine
//  Identität hat, ist jede Generierung eine andere Person.
//

import Foundation
import UIKit

enum AiCharacter {

    // MARK: - Nutzer wählbare Attribute

    enum Gender: String, CaseIterable, Identifiable {
        case woman, man
        var id: String { rawValue }
        var label: String { self == .woman ? "Woman" : "Man" }
        /// Subjekt-Phrase für den Prompt.
        var noun: String { self == .woman ? "young woman" : "young man" }
    }

    enum SkinTone: String, CaseIterable, Identifiable {
        case light, fair, medium, olive, tan, brown, deep
        var id: String { rawValue }
        var label: String {
            switch self {
            case .light: return "Light"
            case .fair: return "Fair"
            case .medium: return "Medium"
            case .olive: return "Olive"
            case .tan: return "Tan"
            case .brown: return "Brown"
            case .deep: return "Deep"
            }
        }
        var phrase: String {
            switch self {
            case .light: return "very light fair skin"
            case .fair: return "fair skin with a natural complexion"
            case .medium: return "medium skin tone"
            case .olive: return "warm olive skin"
            case .tan: return "tan sun-kissed skin"
            case .brown: return "rich brown skin"
            case .deep: return "deep dark skin"
            }
        }
    }

    enum EyeColor: String, CaseIterable, Identifiable {
        case blue, green, hazel, brown, darkBrown, amber, gray, violet
        var id: String { rawValue }
        var label: String {
            switch self {
            case .blue: return "Blue"
            case .green: return "Green"
            case .hazel: return "Hazel"
            case .brown: return "Brown"
            case .darkBrown: return "Dark Brown"
            case .amber: return "Amber"
            case .gray: return "Gray"
            case .violet: return "Violet"
            }
        }
        var phrase: String {
            switch self {
            case .blue: return "bright blue eyes"
            case .green: return "green eyes"
            case .hazel: return "hazel eyes"
            case .brown: return "warm brown eyes"
            case .darkBrown: return "deep dark brown eyes"
            case .amber: return "amber eyes"
            case .gray: return "steely gray eyes"
            case .violet: return "rare violet eyes"
            }
        }
    }

    enum HairColor: String, CaseIterable, Identifiable {
        case black, brown, auburn, red, blonde, platinum, dirtyBlonde, chestnut, gray, white
        var id: String { rawValue }
        var label: String {
            switch self {
            case .black: return "Black"
            case .brown: return "Brown"
            case .auburn: return "Auburn"
            case .red: return "Red"
            case .blonde: return "Blonde"
            case .platinum: return "Platinum"
            case .dirtyBlonde: return "Dirty Blonde"
            case .chestnut: return "Chestnut"
            case .gray: return "Gray"
            case .white: return "White"
            }
        }
        var phrase: String {
            switch self {
            case .black: return "black"
            case .brown: return "brown"
            case .auburn: return "auburn"
            case .red: return "red"
            case .blonde: return "blonde"
            case .platinum: return "platinum blonde"
            case .dirtyBlonde: return "dirty blonde"
            case .chestnut: return "chestnut"
            case .gray: return "silver gray"
            case .white: return "white"
            }
        }
    }

    // MARK: - Zufalls-Pools (nicht nutzerwählbar → für Einzigartigkeit)

    static let hairstylesWoman = [
        "long straight hair", "long wavy hair", "long curly hair",
        "a sleek high ponytail", "a messy bun", "shoulder-length bob",
        "pixie cut", "braided hair", "a low chignon", "voluminous curls",
        "side-swept waves", "dreadlocks"
    ]
    static let hairstylesMan = [
        "short textured hair", "a clean fade haircut", "a messy quiff",
        "buzz cut", "curly short hair", "swept-back hair",
        "an undercut", "shoulder-length hair", "cornrows",
        "a slick back", "a modern crop", "dreadlocks"
    ]

    static let ageRanges = [
        "early 20s", "mid 20s", "late 20s", "early 30s",
        "mid 30s", "early 40s"
    ]

    /// Neutraler regionaler Hinweis für vielfältige Gesichtsstrukturen
    /// (Diversität, keine Stereotypen).
    static let ethnicities = [
        "Scandinavian", "Mediterranean", "Eastern European", "East Asian",
        "South Asian", "Southeast Asian", "Middle Eastern", "West African",
        "East African", "Latina", "Indigenous Andean", "mixed European"
    ]

    static let expressions = [
        "a calm neutral expression looking straight at the camera",
        "a soft natural smile",
        "a confident subtle smile",
        "a thoughtful relaxed expression",
        "a friendly warm expression",
        "a serious editorial expression"
    ]

    static let features = [
        "light freckles across the nose and cheeks",
        "a small beauty mark near the lip",
        "subtle dimples",
        "natural visible skin pores and fine texture",
        "a faint scar through the eyebrow",
        "no makeup, bare natural skin"
    ]

    static let backgrounds = [
        "a neutral gray studio background",
        "a soft blurred white backdrop",
        "a warm beige studio backdrop",
        "a dark charcoal background",
        "a softly lit plain wall",
        "an out-of-focus urban street",
        "an out-of-focus park in soft daylight",
        "a softly blurred café interior",
        "golden-hour outdoor light",
        "a minimalist concrete wall"
    ]

    static let outfits = [
        "a simple plain t-shirt",
        "a casual hoodie",
        "a plain white tank top",
        "a knit sweater",
        "a plain black turtleneck",
        "a denim jacket",
        "a casual button-up shirt",
        "a plain long-sleeve tee"
    ]

    static let lighting = [
        "soft diffused studio lighting",
        "natural window light",
        "soft beauty lighting",
        "gentle directional light",
        "even flat studio lighting"
    ]

    // MARK: - Stil-Wrapper (immer angehängt → garantiert fotoreal)

    static let styleTail = """
    The result MUST look like a 100% real photograph of a real unique person, \
    never AI-generated: highly detailed natural skin with visible pores and fine \
    texture, realistic eyes with natural iris detail and catchlights, individual \
    hair strands, natural lip and skin color, accurate facial proportions and \
    subtle asymmetry that real faces have. No plastic, waxy, airbrushed or \
    over-smoothed skin, no doll-like or CGI look, no beauty filter, no distortion, \
    no extra limbs or fingers, no symmetric cloning. Each generation must be a \
    DIFFERENT unique person — do not reproduce a generic or repeated face. \
    Photorealistic, shot on a 50mm lens, shallow depth of field. No text, \
    no watermark, no logo.
    """

    // MARK: - Prompt-Aufbau

    /// Baut den finalen Bild-Prompt aus den gewählten Attributen + Zufalls-Pools.
    /// `extra` = optionaler Nutzer-Prompt (z. B. „add glasses, evening light").
    static func buildPrompt(gender: Gender,
                            skin: SkinTone,
                            eyes: EyeColor,
                            hair: HairColor,
                            extra: String) -> String {
        let hairstyle = (gender == .woman ? hairstylesWoman : hairstylesMan).randomElement() ?? "stylish hair"
        let age = ageRanges.randomElement() ?? "in their 20s"
        let ethnicity = ethnicities.randomElement() ?? ""
        let expression = expressions.randomElement() ?? "a neutral expression"
        let feature = features.randomElement() ?? ""
        let background = backgrounds.randomElement() ?? "a neutral studio background"
        let outfit = outfits.randomElement() ?? "a plain t-shirt"
        let light = lighting.randomElement() ?? "soft studio lighting"

        var parts: [String] = []
        parts.append("Ultra realistic portrait photograph of a unique \(age) \(ethnicity.lowercased()) \(gender.noun)")
        parts.append("with \(skin.phrase), \(eyes.phrase), \(hairstyle) in \(hair.phrase) color")
        parts.append(feature)
        parts.append(expression)
        parts.append("wearing \(outfit)")
        parts.append("against \(background)")
        parts.append("with \(light)")
        parts.append(styleTail)

        let trimmedExtra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExtra.isEmpty {
            parts.append("Additional instruction: \(trimmedExtra)")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ". ") + "."
    }

    // MARK: - Seed-Bild

    /// Neutrales graues 512×512-Bild als „Input" für den Backend-Edit-Endpunkt
    /// (der keine leeren `images` akzeptiert). Da es keine Identität enthält,
    /// erzeugt das Modell daraus eine neue, einzigartige Person.
    static func seedImageData() -> Data {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }
}
