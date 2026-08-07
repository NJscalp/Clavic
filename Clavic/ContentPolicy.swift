//
//  ContentPolicy.swift
//  Clavic
//
//  Client-side guardrails for user-entered prompts (App Store Guideline 1.1).
//  Blocks generation requests that describe intimate contact or sexual content.
//

import Foundation

enum ContentPolicy {
    /// Returns a user-facing error when the text must be rejected, otherwise nil.
    static func rejectionReason(for text: String) -> String? {
        let normalized = text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !normalized.isEmpty else { return nil }

        // Wortgrenzen-Match: verhindert Substring-Fehltreffer wie "hug" in
        // "huge" oder "sex" in "sussex". Nicht-alphanumerische Zeichen zählen
        // als Grenze; mehrwortige Phrasen werden als Ganzes gesucht.
        for phrase in blockedPhrases where containsWord(phrase, in: normalized) {
            return "This type of content isn't supported in Clavic. Please choose a different idea."
        }
        return nil
    }

    /// Sucht `phrase` als eigenständiges Wort/Wortfolge in `text` (Grenzen an
    /// Nicht-Buchstaben). `phrase` kann Leerzeichen enthalten (z. B. "make out").
    private static func containsWord(_ phrase: String, in text: String) -> Bool {
        let pattern = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}])"
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return text.contains(phrase)
        }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Whether a REMOTE template may appear in Discover. Stricter than the
    /// built-in filter: also rejects special modes remote templates must not
    /// claim (face-swap assets, candid/pinterest 2-photo modes).
    static func isAllowedTemplate(_ template: VideoTemplate) -> Bool {
        if template.faceTemplateAsset != nil { return false }
        if template.isCandidPOV { return false }
        if template.isPinterestSwap { return false }
        if template.requiredPhotoCount > 1 { return false }
        return !containsIntimateContent(template)
    }

    /// Pure intimate-/sexual-content check (App Store Guideline 1.1) for ANY
    /// template — used to filter built-in templates too, without removing
    /// legitimate multi-photo modes.
    static func containsIntimateContent(_ template: VideoTemplate) -> Bool {
        let combined = [
            template.title,
            template.subtitle,
            template.prompt,
            template.promptPhotoBackground ?? "",
            template.fixedEditPrompt ?? "",
            template.hashtag,
        ].joined(separator: " ")
        return rejectionReason(for: combined) != nil
    }

    /// Phrases we block. Scope is DELIBERATELY narrow: only explicit
    /// sexual/nudity content (App Store Guideline 1.1 — this is what got Clavic
    /// rejected before) plus kissing (the kiss-cam rejection). Everything that
    /// belongs to normal LARP/luxury/flex creation — people, groups, "romantic"
    /// golden-hour lighting, "sensual"/"seductive" glam wording, the Vegas
    /// "strip", embraces/hugs, adding a partner — is ALLOWED and no longer
    /// blocked, so legit flex edits (diamond chain, car flex, etc.) go through.
    private static let blockedPhrases: [String] = [
        // Kissing (prior App Store kiss-cam rejection).
        "kiss", "kissing", "make out", "making out", "makeout", "french kiss",
        "kiss cam", "kisscam", "kiss-cam",
        // Nudity.
        "nsfw", "nude", "naked", "nudity", "topless", "bottomless",
        // Explicit sexual content / acts.
        "sexual", "sex", "porn", "erotic",
        "make love", "making love", "lingerie", "undress", "stripper",
        "fondle", "grope", "on top of me", "in bed with",
    ]
}
