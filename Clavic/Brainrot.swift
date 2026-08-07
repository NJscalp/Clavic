//
//  Brainrot.swift
//  Clavic
//
//  Daten + Prompt-/Voice-Logik für den „Brainrot Character"-Generator.
//  15 Charaktere (3D-Brainrot-Meme-Look). Jeder hat:
//   • charPrompt  – feste Bildbeschreibung (Charakter-Konsistenz)
//   • autoAction  – Default-Aktion, wenn der Nutzer keinen eigenen Text eingibt
//   • voice       – ECHTE ElevenLabs-Stimme (Voice-ID) für das Sprechen (kein
//                   Roboter-TTS). Wird an die TTS-Route (kie/ElevenLabs) gegeben.
//   • Referenzbild-Asset = `id` (im Asset-Katalog), dient Konsistenz UND Kachel.
//
//  Der Prompt wird – wie bei StillLife/Candid – in CreateView aus Charakter +
//  (Auto/Custom-Text) + Background-Modus zusammengebaut.
//

import Foundation

struct BrainrotChar: Identifiable, Hashable {
    let id: String
    let name: String
    let charPrompt: String
    let autoAction: String
    /// ElevenLabs-Voice-ID (echte Stimme).
    let voice: String
    /// Gebündeltes Referenz-/Vorschaubild (Asset-Name == id).
    var assetName: String { id }
}

enum Brainrot {
    /// MiniMax Speech-2.6-HD Voice-IDs auf WaveSpeed (realistischste TTS dort —
    /// echte menschliche Stimmen, kein Roboter-Klang). JEDER Charakter bekommt
    /// eine EIGENE Stimme (15 distinkte Built-ins).
    /// (Konstantenname = Rolle, Wert = MiniMax voice_id.)
    enum Voice {
        static let clyde     = "Imposing_Manner"    // bedrohlich, wuchtig
        static let giovanni  = "Deep_Voice_Man"     // tiefer Erzähler (Brainrot-Klassiker)
        static let adam      = "Determined_Man"     // entschlossen, markig
        static let charlotte = "Calm_Woman"         // weiblich, elegant
        static let fin       = "Casual_Guy"         // locker, goofy
        static let daniel    = "Patient_Man"        // ruhig, bedächtig
        static let gigi      = "Lively_Girl"        // quirlig, kindlich
        static let callum    = "Young_Knight"       // heroisch (Ninja)
        static let patrick   = "Friendly_Person"    // laut-freundlich, energisch
        static let antoni    = "Decent_Boy"         // jung, locker
        static let sam       = "Elegant_Man"        // smooth, männlich
        static let rachel    = "Wise_Woman"         // weiblich, warm
        static let arnold    = "Exuberant_Girl"     // überdreht, energetisch
        static let josh      = "Inspirational_girl" // smug/überzeugt
        static let bill      = "Sweet_Girl_2"       // weich, ruhig
    }

    /// Fester Stil-Wrapper (3D-Brainrot-Look) – immer angehängt.
    static let styleTail = "3D Pixar-style glossy cartoon render, vibrant, vertical 9:16, internet brainrot meme aesthetic, cinematic lighting, no on-screen text, no watermark, no extra limbs, no distortion."

    static let randomBackgrounds = [
        "a neon-lit convenience store at night",
        "a sunny tropical beach",
        "a messy teenage bedroom",
        "a dim backrooms hallway with yellow wallpaper and buzzing lights",
        "a fancy candle-lit restaurant",
        "a rainy city street at night with neon signs",
        "a bright modern kitchen",
        "a packed soccer stadium at night",
        "deep outer space with stars and a planet",
        "a school classroom",
        "a sweaty gym with weights",
        "a generic fast-food restaurant interior",
    ]

    static let chars: [BrainrotChar] = [
        BrainrotChar(id: "tung_tung_sahur", name: "Tung Tung Tung Sahur",
            charPrompt: "Tung Tung Tung Sahur, a tall thin anthropomorphic wooden baseball-bat creature with stubby arms and legs, angry cartoon eyes, holding a small wooden bat",
            autoAction: "standing menacingly and lecturing the viewer", voice: Voice.clyde),
        BrainrotChar(id: "tralalero_tralala", name: "Tralalero Tralala",
            charPrompt: "Tralalero Tralala, a cartoon blue shark with three human legs wearing plain white sneakers, goofy grin",
            autoAction: "strutting confidently", voice: Voice.giovanni),
        BrainrotChar(id: "bombardiro_crocodilo", name: "Bombardiro Crocodilo",
            charPrompt: "Bombardiro Crocodilo, a hybrid of a grey military bomber plane and a crocodile, crocodile head on an airplane body with wings",
            autoAction: "flying over a city", voice: Voice.adam),
        BrainrotChar(id: "ballerina_cappuccina", name: "Ballerina Cappuccina",
            charPrompt: "Ballerina Cappuccina, an elegant ballerina whose head is a cappuccino coffee cup with foam, wearing a white tutu, graceful dancing pose",
            autoAction: "doing a delicate pirouette", voice: Voice.charlotte),
        BrainrotChar(id: "brr_brr_patapim", name: "Brr Brr Patapim",
            charPrompt: "Brr Brr Patapim, a creature that is a thick tree trunk body with long human legs, a big long nose, leafy green hair and googly eyes",
            autoAction: "stomping around goofily", voice: Voice.fin),
        BrainrotChar(id: "lirili_larila", name: "Lirili Larila",
            charPrompt: "Lirili Larila, a cactus-elephant hybrid wearing sandals, holding a pocket watch, surreal desert creature",
            autoAction: "walking slowly through a desert", voice: Voice.daniel),
        BrainrotChar(id: "chimpanzini_bananini", name: "Chimpanzini Bananini",
            charPrompt: "Chimpanzini Bananini, a small cheerful monkey whose body is a banana peel, big eyes",
            autoAction: "jumping around excitedly", voice: Voice.gigi),
        BrainrotChar(id: "cappuccino_assassino", name: "Cappuccino Assassino",
            charPrompt: "Cappuccino Assassino, a steaming coffee cup ninja assassin holding two katanas, dramatic stance",
            autoAction: "slicing the air with katanas", voice: Voice.callum),
        BrainrotChar(id: "bombombini_gusini", name: "Bombombini Gusini",
            charPrompt: "Bombombini Gusini, a goose fused with a fighter jet, feathered body with metal wings and jet engines",
            autoAction: "taking off at high speed", voice: Voice.patrick),
        BrainrotChar(id: "trippi_troppi", name: "Trippi Troppi",
            charPrompt: "Trippi Troppi, a surreal aquatic hybrid with a cat head on a shrimp body, underwater vibe",
            autoAction: "swimming in a chaotic loop", voice: Voice.antoni),
        BrainrotChar(id: "boneca_ambalabu", name: "Boneca Ambalabu",
            charPrompt: "Boneca Ambalabu, a creature with a green frog head, a black car tire as a torso, and thin human legs",
            autoAction: "bouncing on its tire body", voice: Voice.sam),
        BrainrotChar(id: "la_vacca_saturnita", name: "La Vacca Saturno Saturnita",
            charPrompt: "La Vacca Saturno Saturnita, a cow whose round body is the planet Saturn with glowing rings, cow head and four legs",
            autoAction: "floating and spinning slowly", voice: Voice.rachel),
        BrainrotChar(id: "glorbo_fruttodrillo", name: "Glorbo Fruttodrillo",
            charPrompt: "Glorbo Fruttodrillo, a crocodile-watermelon hybrid with green scaly skin showing watermelon patterns and red flesh",
            autoAction: "snapping its jaws playfully", voice: Voice.arnold),
        BrainrotChar(id: "peigengoo", name: "Peigengoo",
            charPrompt: "a realistic blue-grey city pigeon with exaggerated huge glossy human lips, photoreal, standing indoors looking at the camera",
            autoAction: "talking directly to the camera with a smug face", voice: Voice.josh),
        BrainrotChar(id: "burbaloni_luliloli", name: "Burbaloni Luliloli",
            charPrompt: "Burbaloni Luliloli, a cute round capybara whose body is fused inside a brown coconut shell, floating in calm water, big calm friendly eyes",
            autoAction: "floating calmly and bobbing in the water", voice: Voice.bill),
    ]

    static func char(_ id: String) -> BrainrotChar? { chars.first { $0.id == id } }

    /// Background-Modus für den Prompt-Aufbau.
    enum Background: String { case own, random, none }

    /// Baut den finalen Bild-Prompt. `text` leer → `autoAction` des Charakters.
    static func buildPrompt(_ c: BrainrotChar, text: String, background: Background) -> String {
        let action = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? c.autoAction
            : text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bg: String
        switch background {
        case .own:    bg = "Place the character naturally into the provided background photo, matching its lighting, shadows and perspective."
        case .random: bg = "Scene/background: " + (randomBackgrounds.randomElement() ?? "") + "."
        case .none:   bg = ""
        }
        return [c.charPrompt, action, bg, styleTail]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    /// Was der Charakter SAGT (für TTS), wenn der Nutzer Text eingibt; sonst ein
    /// kurzer generischer Brainrot-Satz aus der Aktion.
    static func speechText(_ c: BrainrotChar, text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "\(c.name)!" : t
    }
}
