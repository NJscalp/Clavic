//
//  StudioAITools.swift
//  Clavic
//
//  Die Server-Werkzeuge des Studios — nachgebaut nach FaceLab.
//
//  QUELLE, nicht geraten: FaceLabs Datenschutzerklärung
//  (irontech.mobi/facelab/ios/privacy, gelesen am 02.08.2026) nennt WÖRTLICH,
//  welche Funktionen ihre App auf den Server schickt:
//
//      „the Fix section, AI Beauty, Remover in the AI Remove section, Outfit in
//       the Clothes section, the Muscle section, the Hairstyle section, Auto in
//       the Adjust section, the Uncrop section, Generate in the Background
//       section"
//
//  Alles andere in ihrer App — Gesichtsform, Augen/Nase/Lippen, Körper, Haut,
//  Make-up, Filter — läuft LOKAL. Genau diese Trennung haben wir jetzt auch:
//  die Reiter Face/Body/Skin/Light/Filters rechnen auf dem Gerät und kosten
//  nichts, nur dieser Reiter kostet Credits.
//
//  Ihre Modelle laut derselben Quelle: Stable Diffusion (selbst betrieben),
//  Google Gemini 3 Pro Image und OpenAI. Wir fahren GPT Image 2 über
//  WaveSpeed — also dasselbe Haus wie ihr OpenAI-Weg.
//
//  Alle Prompts hier tragen denselben Identitäts-Schutz wie die des Agenten:
//  die Person darf NICHT neu gezeichnet oder „verschönert" werden. Genau daran
//  erkennt man sonst sofort, dass ein Bildmodell am Werk war.
//

import Foundation

struct StudioAIVariant: Identifiable {
    let id: String
    let label: String
    let promptSuffix: String
}

struct StudioAITool: Identifiable {
    let id: String
    let label: String
    let icon: String
    /// Kurzer Hinweis unter der Leiste, was passiert.
    let hint: String
    let prompt: String
    let variants: [StudioAIVariant]
    let customPlaceholder: String?

    init(id: String, label: String, icon: String, hint: String, prompt: String,
         variants: [StudioAIVariant] = [], customPlaceholder: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.hint = hint
        self.prompt = prompt
        self.variants = variants
        self.customPlaceholder = customPlaceholder
    }

    func resolvedPrompt(variantID: String?, customInstruction: String) -> String {
        var parts = [prompt]
        if let variantID,
           let variant = variants.first(where: { $0.id == variantID }) {
            parts.append(variant.promptSuffix)
        }
        let custom = customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { parts.append("User instruction: \(custom)") }
        return parts.joined(separator: "\n\n")
    }
}

enum StudioAITools {

    /// Gemeinsamer Vorspann. Steht vor JEDEM Werkzeug, weil das Modell sonst
    /// bei jeder Aufgabe dazu neigt, das Gesicht mit zu „verbessern".
    private static let keepIdentity = """
    Keep the exact same person: identical face, bone structure, jawline, eyes, nose, \
    mouth, skin tone and real skin texture with its pores and marks, same hair, same \
    apparent age, same body proportions. Do NOT beautify, slim, smooth, retouch or \
    redraw the person, and do not change their identity. Keep the same framing and crop. \
    Photorealistic, indistinguishable from an untouched photograph — no plastic skin, \
    no AI sheen.
    """

    /// Schlanker Katalog: große Änderungen per AI, Feinschliff lokal.
    static let all: [StudioAITool] = [
        StudioAITool(
            id: "fix", label: "Fix", icon: "wand.and.stars",
            hint: "Repairs a blurry or badly lit shot.",
            prompt: """
            \(keepIdentity)
            Repair the technical quality of this photograph only. Remove motion blur and \
            softness so the image is sharp and clean, recover detail lost to noise, fix the \
            white balance and exposure so the scene looks naturally lit, and lift crushed \
            shadows without flattening the contrast. Change nothing about the content: same \
            pose, same clothing, same background, same expression.
            """),

        StudioAITool(
            id: "beauty", label: "Beauty", icon: "sparkles",
            hint: "Gentle retouch that still looks like you.",
            prompt: """
            \(keepIdentity)
            Apply a restrained retouch as a real photographer would: even out blotchy skin \
            tone, calm redness, reduce shine on the forehead and nose, and soften — do not \
            erase — temporary blemishes. Keep pores, freckles, moles, scars, fine lines and \
            beard stubble exactly as they are; they are what makes it a real face. Do not \
            change face shape, do not enlarge eyes, do not slim the jaw, do not whiten teeth \
            beyond their natural colour.
            """),

        StudioAITool(
            id: "hair", label: "Hair", icon: "comb",
            hint: "New hairstyle, same face.",
            prompt: """
            \(keepIdentity)
            Change ONLY the hair. Give the person a well-cut, natural hairstyle that suits \
            their head shape and hairline, with realistic strand detail, believable volume \
            and a soft, natural edge against the background — no helmet-like outline. Keep \
            the natural hair colour unless it looks obviously dyed. The face, ears, forehead \
            and everything below the neck must stay pixel-identical.
            """,
            variants: [
                StudioAIVariant(id: "clean", label: "Clean", promptSuffix: "Use a clean, polished salon haircut with natural volume."),
                StudioAIVariant(id: "texture", label: "Texture", promptSuffix: "Use a modern textured haircut with realistic individual strands."),
                StudioAIVariant(id: "long", label: "Long", promptSuffix: "Create naturally long, healthy hair with believable weight and strand detail."),
                StudioAIVariant(id: "curls", label: "Curls", promptSuffix: "Create defined natural curls with realistic frizz and volume."),
            ],
            customPlaceholder: "Describe the hairstyle"),

        StudioAITool(
            id: "outfit", label: "Outfit", icon: "tshirt",
            hint: "Different clothes, same person and pose.",
            prompt: """
            \(keepIdentity)
            Change ONLY the clothing. Dress the person in a clean, well-fitting outfit that \
            suits the setting and the light in this photo. The fabric must follow the body \
            underneath with real folds, real seams and correct drape, and it must be lit by \
            the same light source as the rest of the scene, with matching shadows. Keep the \
            exact same pose, hands, hair, face and background.
            """,
            variants: [
                StudioAIVariant(id: "street", label: "Street", promptSuffix: "Use a premium modern streetwear outfit without visible logos."),
                StudioAIVariant(id: "tailored", label: "Tailored", promptSuffix: "Use an elegant, perfectly tailored quiet-luxury outfit."),
                StudioAIVariant(id: "evening", label: "Evening", promptSuffix: "Use a refined evening outfit appropriate for the setting."),
                StudioAIVariant(id: "sport", label: "Sport", promptSuffix: "Use a premium realistic athletic outfit without visible branding."),
            ],
            customPlaceholder: "Describe the outfit"),

        StudioAITool(
            id: "background", label: "Background", icon: "photo",
            hint: "New background, subject untouched.",
            prompt: """
            \(keepIdentity)
            Replace ONLY the background. Put the person into a clean, real-looking setting \
            that matches the direction, colour and hardness of the light already on them, so \
            nothing about them has to change. Keep every hair strand and edge of the person \
            intact — no cut-out halo, no glow outline. Add correct contact shadows where they \
            meet the ground. The person, their pose and their clothing stay exactly as they are.
            """,
            variants: [
                StudioAIVariant(id: "studio", label: "Studio", promptSuffix: "Use a premium neutral photo-studio background with soft falloff."),
                StudioAIVariant(id: "city", label: "City", promptSuffix: "Use a believable upscale city location matching the existing light."),
                StudioAIVariant(id: "sunset", label: "Sunset", promptSuffix: "Use a realistic golden-hour outdoor setting with matching light direction."),
                StudioAIVariant(id: "interior", label: "Interior", promptSuffix: "Use a high-end but natural interior matching the camera perspective."),
            ],
            customPlaceholder: "Describe the new background"),

        StudioAITool(
            id: "replace", label: "Replace", icon: "arrow.triangle.2.circlepath.camera",
            hint: "Replace one described detail, keep everything else.",
            prompt: """
            \(keepIdentity)
            Replace ONLY the object, garment detail or scene element described in the user \
            instruction. Match the original camera perspective, focus, grain, reflections, \
            shadows and light direction. Everything not explicitly named must remain \
            pixel-identical, especially every person and face. Do not add text or logos.
            """,
            customPlaceholder: "What should be replaced, and with what?"),
    ]
}
