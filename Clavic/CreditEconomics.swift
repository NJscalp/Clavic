//
//  CreditEconomics.swift
//  Clavic
//
//  Zentrale Kalkulation: User-Preis → −30 % Apple → −API = Profit.
//  IAP-Preise aus Products.storekit; API-Schätzungen aus kie.ai-Rechnungen.
//

import Foundation

enum CreditEconomics {

    /// Apple App Store Provision (Standard 30 %).
    static let appleCommission = 0.30

    /// Credit-Packs (USD, Credits) — Clavic.10 / .30 / .75.
    static let creditPacks: [(priceUSD: Double, credits: Int)] = [
        (24.99, 40),
        (69.99, 110),
        (135.99, 220),
    ]

    /// Ø User-Preis pro Credit über alle Packs (gleich gewichtet).
    static var averageRevenuePerCreditUSD: Double {
        let perCredit = creditPacks.map { $0.priceUSD / Double($0.credits) }
        return perCredit.reduce(0, +) / Double(perCredit.count)
    }

    /// Netto nach Apple-Abzug pro Credit.
    static var netRevenuePerCreditUSD: Double {
        averageRevenuePerCreditUSD * (1 - appleCommission)
    }

    // MARK: - API-Kosten (USD, konservativ)

    static let nanoBanana1K = 0.04
    static let nanoBanana2K = 0.06
    static let nanoBanana4K = 0.09
    static let seedanceRefPerSecond = 0.126   // Kling O3 video-edit $/s (Ref-Video-Segmente)
    static let seedanceSegmentSeconds = 5.0
    static let klingMotionControlUSD = 0.63   // Kling O3 video-edit ~5 s ($0.126/s)

    static func seedancePipelineUSD(segments: Int, resolution: Resolution) -> Double {
        let factor: Double = resolution == .p720 ? 2.0 : 1.0
        return Double(segments) * seedanceSegmentSeconds * seedanceRefPerSecond * factor
    }

    static func nanoBananaUSD(quality: String) -> Double {
        switch quality.lowercased() {
        case "high": return nanoBanana4K
        case "medium": return nanoBanana2K
        default: return nanoBanana1K
        }
    }

    // MARK: - Zeile für eine Generierung

    struct LineItem: Identifiable {
        let id = UUID()
        let name: String
        let credits: Int
        let apiCostUSD: Double

        var userPaysUSD: Double { Double(credits) * averageRevenuePerCreditUSD }
        var netAfterAppleUSD: Double { userPaysUSD * (1 - appleCommission) }
        var profitUSD: Double { netAfterAppleUSD - apiCostUSD }
        var marginPercent: Double {
            guard netAfterAppleUSD > 0 else { return 0 }
            return (profitUSD / netAfterAppleUSD) * 100
        }
    }

    /// Alle angepassten Templates @480p (Default in der App).
    static var adjustedTemplates480p: [LineItem] {
        [
            LineItem(
                name: "If you grab me imma bite you",
                credits: CreditCosts.klingMotionControl,
                apiCostUSD: klingMotionControlUSD
            ),
            LineItem(
                name: "Du bist gut Genug",
                credits: CreditCosts.musicVideo(key: "music", resolution: .p480),
                apiCostUSD: seedancePipelineUSD(segments: 3, resolution: .p480)
            ),
            LineItem(
                name: "Nervy Backrooms",
                credits: CreditCosts.musicVideo(key: "nerv", resolution: .p480),
                apiCostUSD: seedancePipelineUSD(segments: 2, resolution: .p480)
            ),
            LineItem(
                name: "Backrooms Dance",
                credits: CreditCosts.musicVideo(key: "pdance", resolution: .p480),
                apiCostUSD: seedancePipelineUSD(segments: 3, resolution: .p480)
            ),
            LineItem(
                name: "Baseball Fan Cam",
                credits: CreditCosts.musicVideo(key: "baseball", resolution: .p480),
                apiCostUSD: seedancePipelineUSD(segments: 2, resolution: .p480)
            ),
            LineItem(
                name: "Chat · Nano Banana 2 @4K",
                credits: CreditCosts.imageEditCredits(quality: "high"),
                apiCostUSD: nanoBanana4K
            ),
            LineItem(
                name: "8K Upscale / Pro Glow",
                credits: CreditCosts.photoEnhance,
                apiCostUSD: nanoBanana4K
            ),
            LineItem(
                name: "Kling Motion Control",
                credits: CreditCosts.klingMotionControl,
                apiCostUSD: klingMotionControlUSD
            ),
        ]
    }
}
