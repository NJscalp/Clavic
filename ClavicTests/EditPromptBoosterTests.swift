//
//  EditPromptBoosterTests.swift
//  ClavicTests
//
//  „add me in the image" landete monatelang im Objekt-Zweig, der fuer
//  „park a Ferrari in the garage" geschrieben wurde. Der befiehlt woertlich,
//  die Beleuchtung unveraendert zu lassen, und sagt kein Wort zur Haltung —
//  heraus kam die Person als Aufkleber, Haltung 1:1 aus dem Referenzfoto,
//  Licht der Szene ignoriert.
//
//  Der Fehler war von aussen nicht zu sehen: der Prompt sah plausibel aus,
//  nur eben der falsche. Deshalb halten diese Tests fest, WELCHER Zweig einen
//  Satz faengt — und dass der Personen-Zweig die drei Dinge enthaelt, an denen
//  Einfuegen scheitert: Identitaet, neue Haltung, Licht der Szene.
//

import UIKit
import XCTest
@testable import Clavic

final class EditPromptBoosterTests: XCTestCase {

    private let insertRequests = [
        "add me in the image",
        "Add me to this photo",
        "put me in the picture",
        "füge mich ins bild ein",
        "setz mich in dieses foto",
        "add her to the scene",
    ]

    func testInsertingAPersonIsNotTreatedAsAnObject() {
        for request in insertRequests {
            XCTAssertTrue(EditPromptBooster.wantsPersonInsert(request),
                          "Nicht als Personen-Einfuegen erkannt: \(request)")

            let prompt = EditPromptBooster.build(request, hasPerson: true)
            XCTAssertFalse(prompt.contains("parking bay"),
                           "\(request) landet im Auto-Zweig")
            XCTAssertFalse(prompt.contains("lighting exactly as they are"),
                           "\(request) friert das Licht ein")
        }
    }

    /// Die drei Zusicherungen, an denen ein Einfuegen steht und faellt.
    func testInsertPromptCarriesIdentityPoseAndLight() {
        let prompt = EditPromptBooster.build("add me in the image", hasPerson: true)

        XCTAssertTrue(prompt.contains("Keep the exact same person"),
                      "Identitaets-Klausel fehlt — es kaeme ein fremder Mensch heraus")
        XCTAssertTrue(prompt.contains("Do NOT copy the pose"),
                      "Ohne dieses Verbot wird die Haltung aus dem Referenzfoto uebernommen")
        XCTAssertTrue(prompt.contains("BUILD A NEW POSE FOR THIS PLACE"))
        XCTAssertTrue(prompt.contains("RELIGHT THEM COMPLETELY"),
                      "Ohne Umbeleuchtung klebt das Licht des Referenzfotos auf der Person")
        XCTAssertTrue(prompt.contains("ATMOSPHERE"),
                      "Stimmung, Korn und Schaerfe muessen zur Szene passen, nicht nur der Schatten")
        XCTAssertTrue(prompt.contains("Discard the light they came with"))
        XCTAssertTrue(prompt.contains("no sticker look"))
        XCTAssertTrue(prompt.contains("add me in the image"),
                      "Der Wunsch der Nutzerin muss im Prompt stehen bleiben")
    }

    /// Aus dem Szenenbild wird das Licht GEMESSEN und als konkrete Vorgabe in
    /// den Prompt geschrieben. Ohne diese Zeile stand dort nur „match the
    /// lighting" — und genau daran ist es gescheitert.
    func testMeasuredSceneLightGoesIntoThePrompt() throws {
        let scene = try XCTUnwrap(UIImage(named: "sc_garage_after", in: .main, with: nil)
            ?? UIImage(named: "sc_garage_after"))
        let data = try XCTUnwrap(scene.jpegData(compressionQuality: 0.9))

        let withScene = EditPromptBooster.build("add me in the image", hasPerson: true,
                                                referenceCount: 2, sceneImage: data)
        XCTAssertTrue(withScene.contains("Measured look of THIS scene"))

        let withoutScene = EditPromptBooster.build("add me in the image", hasPerson: true,
                                                   referenceCount: 2)
        XCTAssertFalse(withoutScene.contains("Measured look of THIS scene"),
                       "Ohne Szenenbild darf nichts erfunden werden")
    }

    /// Bei zwei Bildern muss der Prompt sagen, welches die Szene ist.
    func testTwoReferencesAreNumbered() {
        let two = EditPromptBooster.build("add me in the image", hasPerson: true, referenceCount: 2)
        XCTAssertTrue(two.contains("IMAGE 1 is the SCENE"))
        XCTAssertTrue(two.contains("IMAGE 2 is the PERSON"))

        let one = EditPromptBooster.build("add me in the image", hasPerson: true, referenceCount: 1)
        XCTAssertFalse(one.contains("IMAGE 1 is the SCENE"))
    }

    /// Haltung umbauen kann GPT Image 2 messbar nicht — beide Faelle muessen
    /// deshalb auf Nano Banana 2 laufen.
    func testBodyChangesRouteToThePoseModel() {
        XCTAssertTrue(EditPromptBooster.needsPoseModel("add me in the image"))
        XCTAssertTrue(EditPromptBooster.needsPoseModel("give me a natural pose"))
        XCTAssertFalse(EditPromptBooster.needsPoseModel("make it black and white"))
    }

    /// Das Einfuegen eines GEGENSTANDS bleibt im Objekt-Zweig — dort stehen
    /// die Massstab- und Perspektiv-Regeln, die ein Auto braucht.
    func testInsertingAnObjectStillUsesTheObjectBranch() {
        let prompt = EditPromptBooster.build("park a Ferrari in the garage", hasPerson: false)
        XCTAssertTrue(prompt.contains("parking bay"))
        XCTAssertFalse(EditPromptBooster.wantsPersonInsert("park a Ferrari in the garage"))
    }

    /// Ein reiner Look-Wunsch darf die Haltung weiter einfrieren.
    func testStyleOnlyRequestKeepsThePose() {
        let prompt = EditPromptBooster.build("make it look like a g7x photo")
        XCTAssertTrue(prompt.contains("Keep the exact same subject, pose"))
    }
}
