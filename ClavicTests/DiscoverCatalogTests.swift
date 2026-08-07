//
//  DiscoverCatalogTests.swift
//  ClavicTests
//
//  Discover ist die erste Fläche, die eine neue Nutzerin sieht. Zwei Dinge
//  dürfen dort nie kaputtgehen, und beide fallen von Hand kaum auf:
//
//  Erstens muss die verspielte Hälfte des Katalogs hinter dem Fun-Chip
//  bleiben. Rutscht ein Fan-Cam-Template zurück in die Startansicht, merkt
//  man das erst an der Abbruchquote.
//
//  Zweitens trägt jeder Look-Prompt die Identitäts-Klausel. Fehlt sie in
//  einem einzigen, kommt aus genau dieser Vorlage ein fremder, geglätteter
//  Mensch heraus — und das ist der Fehler, der die App als KI entlarvt.
//

import XCTest
@testable import Clavic

final class DiscoverCatalogTests: XCTestCase {

    func testPlayfulTemplatesAreOnlyReachableUnderFun() {
        let hidden = TemplateLibrary.visible.filter(\.isHiddenFromDiscover)
        XCTAssertFalse(hidden.isEmpty, "Ohne ausgeblendete Vorlagen prüft dieser Test nichts")

        for category in TemplateCategory.allCases where category != .fun {
            let shown = TemplateLibrary.filtered(by: category)
            XCTAssertTrue(
                shown.allSatisfy { !$0.isHiddenFromDiscover },
                "Unter \(category.rawValue) darf keine ausgeblendete Vorlage stehen"
            )
        }

        let fun = TemplateLibrary.filtered(by: .fun)
        XCTAssertEqual(Set(fun.map(\.title)), Set(hidden.map(\.title)),
                       "Der Fun-Chip zeigt genau die ausgeblendeten Vorlagen")
    }

    func testNoPlayfulCategoryTemplateSurvivedTheMove() {
        let playful: Set<TemplateCategory> = [.memes, .dance, .fancam, .worldcup, .backrooms]
        let stragglers = TemplateLibrary.all.filter { playful.contains($0.category) }
        XCTAssertTrue(stragglers.isEmpty,
                      "Noch nicht umgehängt: \(stragglers.map(\.title))")
    }

    func testEveryViralLookCarriesTheIdentityClause() {
        XCTAssertEqual(ViralLooks.all.count, 12)
        for look in ViralLooks.all {
            XCTAssertTrue(look.prompt.contains("Keep the exact same woman"),
                          "\(look.title) hat keine Identitäts-Klausel")
            XCTAssertTrue(look.prompt.contains("No text, no logos, no watermark"),
                          "\(look.title) endet nicht mit der Marken-/Text-Sperre")
        }
        XCTAssertEqual(Set(ViralLooks.all.map(\.id)).count, 12, "Doppelte Look-ID")
    }

    func testEveryViralLookHasATemplate() {
        let prompts = Set(TemplateLibrary.all.compactMap(\.fixedEditPrompt))
        for look in ViralLooks.all {
            XCTAssertTrue(prompts.contains(look.prompt),
                          "\(look.title) ist über keine Kachel erreichbar")
        }
    }
}
