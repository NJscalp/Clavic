//
//  FruitStoryCatalog.swift
//  Clavic
//
//  "AI Fruit Story" – Daten + Prompt-Bausteine (nachgebaut nach Zyvos
//  gleichnamigem Template, eigene Formulierung).
//
//  Aufbau wie bei Zyvo:
//   • Charakter-Auswahl  (feste 3D-Frucht-Figuren als Referenzbilder)
//   • Story-Preset       (Dramen-Vorlage mit „storyIdea"-Seed)
//   • Visueller Stil     (Cinematic / Cute / Drama-Comedy / Dark Drama)
//  Daraus schreibt ein LLM (Backend-Planner) jedes Mal ein NEUES Drehbuch,
//  das die FruitStoryPipeline mit GPT Image 2 (Keyframes) + Veo 3.1
//  (sprechende Clips) rendert.
//

import SwiftUI

// MARK: - Charaktere

struct FruitCharacter: Identifiable, Hashable {
    let id: String          // stabiler Schlüssel, z. B. "orangemom"
    let name: String        // Anzeige-/Drehbuch-Name, z. B. "Orange Mom"
    let role: String        // Rolle für den Planner
    let asset: String       // gebündeltes Referenzbild im Asset-Katalog
}

// MARK: - Story-Presets

struct FruitPreset: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String      // kurze UI-Beschreibung
    let storyIdea: String   // ausführlicher Seed für den Planner ("" = Custom)
    let conflict: String
    let icon: String
    var isCustom: Bool { id == "custom" }
}

// MARK: - Stile

struct FruitStyle: Identifiable, Hashable {
    let id: String
    let label: String
    let prompt: String      // Stil-Vorspann für die Keyframe-Prompts
    let icon: String
}

enum FruitStoryCatalog {

    /// Wie viele Szenen eine Story standardmäßig hat (wie Zyvos Default).
    static let defaultSceneCount = 5
    /// Veo-Cliplänge pro Szene (Sekunden).
    static let sceneDuration = 8

    // 10 feste Frucht-Charaktere (wie Zyvos Roster).
    static let characters: [FruitCharacter] = [
        .init(id: "orangemom",     name: "Orange Mom",     role: "emotional main character", asset: "fruit_char_orangemom"),
        .init(id: "banana",        name: "Banana",         role: "villain / rival character", asset: "fruit_char_banana"),
        .init(id: "strawberrymom", name: "Strawberry Mom", role: "drama / relationship character", asset: "fruit_char_strawberrymom"),
        .init(id: "hotpeach",      name: "Hot Peach",      role: "popular twist character", asset: "fruit_char_hotpeach"),
        .init(id: "bossmango",     name: "Boss Mango",     role: "authority / boss character", asset: "fruit_char_bossmango"),
        .init(id: "ananasgirl",    name: "Ananas Girl",    role: "stylish supporting character", asset: "fruit_char_ananasgirl"),
        .init(id: "appleson",      name: "Apple Son",      role: "young supporting character", asset: "fruit_char_appleson"),
        .init(id: "lemonkid",      name: "Lemon Kid",      role: "cute side character", asset: "fruit_char_lemonkid"),
        .init(id: "orangekid",     name: "Orange Kid",     role: "innocent child character", asset: "fruit_char_orangekid"),
        .init(id: "brokkoliboss",  name: "Brokkoli Boss",  role: "funny strict boss character", asset: "fruit_char_brokkoliboss"),
    ]

    static func character(id: String) -> FruitCharacter? { characters.first { $0.id == id } }

    // 5 Drama-Presets + Custom (eigene Seeds, gleiche 5-Akt-Dramaturgie wie Zyvo).
    static let presets: [FruitPreset] = [
        .init(id: "cheating", label: "Cheating",
              detail: "A fruit catches their partner cheating.",
              storyIdea: "A fruit suspects their partner is hiding something. Across the scenes: a suspicious clue surfaces, a tense confrontation, the truth bursting out in a heated argument, an emotional breakdown, and a final shocking twist that flips everything.",
              conflict: "Secret discovered — dramatic confrontation and emotional breakdown",
              icon: "heart.slash.fill"),
        .init(id: "baby", label: "Getting a baby",
              detail: "A fruit reveals life-changing news.",
              storyIdea: "A fruit is nervously hiding life-changing news from their partner. Build from a tense hint that something is different, to the big emotional reveal, an overwhelmed and shocked reaction, a vulnerable moment, and a warm, heartfelt ending where everything changes.",
              conflict: "Life-changing revelation — shock turning into joy",
              icon: "figure.2.and.child.holdinghands"),
        .init(id: "cheats-back", label: "Cheats back",
              detail: "A betrayed fruit plans revenge.",
              storyIdea: "A betrayed fruit quietly plans their payback. From the heartbreak of finding out, to hiding the pain while scheming, to a stunning transformation, to a jaw-dropping reveal at the worst possible moment for the other, ending with the tables completely turned.",
              conflict: "Betrayal discovered — secret revenge planned and executed",
              icon: "flame.fill"),
        .init(id: "secret-twin", label: "Secret twin",
              detail: "A hidden twin changes everything.",
              storyIdea: "A fruit notices their partner behaving like two completely different people — remembering things wrong, showing up in two places. Confusion turns into suspicion, then a scene that makes no sense, then the shocking secret-twin reveal that explains every mystery, ending with both twins face to face.",
              conflict: "Identity mystery — twin reveal that explains everything",
              icon: "person.2.fill"),
        .init(id: "kicked-out", label: "Kicked out",
              detail: "A fruit gets kicked out, then returns.",
              storyIdea: "After an explosive argument, a fruit is thrown out of the house. Left outside with their bags in shock, they disappear and rebuild themselves in secret, then return completely transformed and powerful, revealing a secret they discovered while they were gone that changes everything.",
              conflict: "Explosive split — shocking transformed return with the truth",
              icon: "door.left.hand.open"),
        .init(id: "custom", label: "Custom",
              detail: "Write your own fruit story.",
              storyIdea: "",
              conflict: "",
              icon: "square.and.pencil"),
    ]

    static func preset(id: String) -> FruitPreset? { presets.first { $0.id == id } }

    // 4 Stile (wie Zyvo: Cinematic 3D / Cute 3D / Drama Comedy / Dark Drama).
    static let styles: [FruitStyle] = [
        .init(id: "cinematic", label: "Cinematic 3D",
              prompt: "Polished viral-ready 3D render with premium short-form drama lighting, cinematic contrast and a clean strong focal point.",
              icon: "film.fill"),
        .init(id: "cute", label: "Cute 3D",
              prompt: "Cute glossy 3D render with charming characters, big expressive faces and colorful, warm cinematic lighting.",
              icon: "sparkles"),
        .init(id: "drama-comedy", label: "Drama Comedy",
              prompt: "Lively 3D render with exaggerated but readable comedic reactions, polished characters and bright cinematic lighting.",
              icon: "theatermasks.fill"),
        .init(id: "dark-drama", label: "Dark Drama",
              prompt: "Moody cinematic 3D render with intense dramatic lighting, suspenseful shadows and strong emotion.",
              icon: "moon.stars.fill"),
    ]

    static func style(id: String) -> FruitStyle? { styles.first { $0.id == id } }

    // MARK: - Render-Regeln (sinngemäß wie Zyvos Regelblöcke)

    static let characterConsistencyRules = "Render every listed character as a TALL, FULL-ADULT anthropomorphic fruit-human with adult proportions and a mature face — never a baby, toddler or shrunken child. Preserve each character's exact identity from its reference image: fruit type, face, body shape, outfit, accessories and color palette. This identity is LOCKED for the whole story — never merge or swap one character into another. Only include the characters listed for this scene; do not invent extra foreground characters."

    static let sceneRules = "One cinematic moment only — no split panels or collages. Keep the environment simple enough that the emotion reads immediately. Use a dramatic camera angle, lighting and staging so the story beat is instantly obvious."

    static let visualRules = "Cinematic lighting tuned for premium short-form drama. Clean, readable foreground action with one strong focal point. Vertical 9:16 framing that reads instantly without captions. The image must clearly communicate this scene's purpose."

    static let negativeRules = "No text, captions, subtitles, speech bubbles, title cards, logos, UI overlays or watermarks. No random background crowd, identity swaps, extra limbs, melted features or realism drift."

    static let continuityRule = "A continuity reference image of the previous scene is included. Use it ONLY for environment, set layout, lighting and camera continuity — do NOT copy any character from it that is not in this scene's cast. If this scene is a new location, build the new environment fresh."

    // MARK: - Prompt-Zusammenbau

    /// Baut den GPT-Image-2-Prompt für den Keyframe einer Szene zusammen
    /// (Stil + Szenenbeschreibung + Charakter-/Szenen-/Negativ-Regeln).
    static func keyframePrompt(sceneImage: String,
                               characterNames: [String],
                               style: FruitStyle,
                               hasContinuityReference: Bool) -> String {
        var parts: [String] = []
        parts.append(style.prompt)
        parts.append("SCENE: \(sceneImage)")
        if !characterNames.isEmpty {
            parts.append("Characters in this scene: \(characterNames.joined(separator: ", ")).")
        }
        parts.append(characterConsistencyRules)
        if hasContinuityReference { parts.append(continuityRule) }
        parts.append(sceneRules)
        parts.append(visualRules)
        parts.append(negativeRules)
        return parts.joined(separator: "\n")
    }

    /// Baut den Veo-3.1-Animations-Prompt (mit gesprochenem Dialog) für eine Szene.
    static func animationPrompt(action: String, dialogue: String, style: FruitStyle) -> String {
        var parts: [String] = []
        let act = action.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append("Animate this as one cinematic vertical 9:16 scene of polished 3D anthropomorphic fruit characters. \(act)")
        let line = dialogue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty {
            parts.append("The fruit characters SPEAK their lines out loud with matching lip-sync, real voices and emotion: \(line)")
        }
        parts.append("\(style.prompt) Smooth cinematic camera, expressive acting, natural ambient sound. No on-screen text, captions, subtitles or watermarks.")
        return parts.joined(separator: " ")
    }
}
