//
//  DigiCamStylesTests.swift
//  ClavicTests
//
//  Die Digicam-Stile sind der eine Teil des Katalogs, bei dem sich die POSE
//  ausdruecklich NICHT aendern darf — sie sind ein Grading auf dem eigenen
//  Foto, keine neue Szene. Faellt dieser Satz aus dem Prompt, stellt das
//  Modell die Person um und die Nutzerin bekommt ein anderes Bild zurueck als
//  das, das sie aufgenommen hat.
//
//  Ebenso wichtig: „Grade, nicht Retusche". Ohne diesen Satz glaettet das
//  Modell die Haut, und dann ist es ein Beauty-Filter — genau das, was die
//  App nirgends tut.
//

import XCTest
@testable import Clavic

final class DigiCamStylesTests: XCTestCase {

    func testEveryStyleKeepsPersonAndPose() {
        XCTAssertEqual(DigiCamStyles.all.count, 7)

        for style in DigiCamStyles.all {
            let prompt = style.prompt
            XCTAssertTrue(prompt.contains("Keep the exact same person"),
                          "\(style.title): Identitaets-Klausel fehlt")
            XCTAssertTrue(prompt.contains("Keep the exact same pose"),
                          "\(style.title): die Pose darf sich hier nicht aendern")
            XCTAssertTrue(prompt.contains("this is a colour grade, not a retouch"),
                          "\(style.title): ohne diesen Satz wird es ein Beauty-Filter")
            XCTAssertTrue(prompt.contains("No text, no logos, no watermark"),
                          "\(style.title): Marken-/Text-Sperre fehlt")
            XCTAssertFalse(prompt.isEmpty)
        }

        XCTAssertEqual(Set(DigiCamStyles.all.map(\.id)).count, 7, "Doppelte Stil-ID")
    }

    /// Die Vorher/Nachher-Kachel ist das Versprechen. Fehlt eine der beiden
    /// Seiten, zeigt die Kachel nur einen Verlauf.
    func testEveryStyleHasABeforeAndAnAfterImage() {
        for style in DigiCamStyles.all {
            XCTAssertNotNil(UIImage(named: style.previewBefore),
                            "\(style.title): Vorher-Bild \(style.previewBefore) fehlt")
            XCTAssertNotNil(UIImage(named: style.previewAfter),
                            "\(style.title): Nachher-Bild \(style.previewAfter) fehlt")
        }
    }

    /// Ein Grading ist kein Szenen-Generator. Waeren die Stile bei den
    /// ViralLooks gelandet, stuende in einer Liste einmal „erfinde eine Szene"
    /// und einmal „fass die Szene nicht an".
    func testStylesAreNotMixedIntoViralLooks() {
        let lookIDs = Set(ViralLooks.all.map(\.id))
        for style in DigiCamStyles.all {
            XCTAssertFalse(lookIDs.contains(style.id))
        }
    }
}
