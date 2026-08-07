//
//  ImageCropRemapTests.swift
//  ClavicTests
//
//  Die Platzierungs-Box wird gegen das Rahmenformat gemessen, das beim
//  Ausloesen eingestellt war. Wechselt die Nutzerin das Format danach noch im
//  letzten Schritt, wird das Ortsfoto neu zugeschnitten — und die rosa
//  Markierung saesse ohne Umrechnung an einer anderen Stelle als die, auf die
//  sie die Box gezogen hat. Auffallen wuerde das erst am fertigen, bezahlten
//  Bild.
//
//  Deshalb pruefen diese Tests die reine Geometrie, ohne Kamera und ohne Bild.
//

import CoreGraphics
import XCTest
@testable import Clavic

final class ImageCropRemapTests: XCTestCase {

    /// Sensorbild 4:3 — so kommt es aus der Kamera.
    private let raw: CGFloat = 4.0 / 3.0
    private let portrait: CGFloat = 4.0 / 5.0
    private let story: CGFloat = 9.0 / 16.0

    func testSameFormatChangesNothing() {
        let rect = CGRect(x: 0.31, y: 0.22, width: 0.18, height: 0.47)
        XCTAssertEqual(
            ImageCrop.remap(rect, fromAspect: portrait, toAspect: portrait, sourceAspect: raw),
            rect
        )
    }

    func testCentredBoxStaysCentredWhenTheFormatNarrows() {
        let rect = CGRect(x: 0.40, y: 0.20, width: 0.20, height: 0.50)
        let mapped = ImageCrop.remap(rect, fromAspect: portrait, toAspect: story, sourceAspect: raw)
        XCTAssertEqual(mapped.midX, 0.5, accuracy: 0.0001, "Die Mitte bleibt die Mitte")
        // Der neue Ausschnitt ist schmaler, dieselbe Stelle wird also breiter.
        XCTAssertGreaterThan(mapped.width, rect.width)
        // Beide Zuschnitte sind gleich hoch, senkrecht darf sich nichts ändern.
        XCTAssertEqual(mapped.minY, rect.minY, accuracy: 0.0001)
        XCTAssertEqual(mapped.height, rect.height, accuracy: 0.0001)
    }

    func testOffCentreBoxLandsOnTheSamePlaceInTheScene() {
        let rect = CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.40)
        let mapped = ImageCrop.remap(rect, fromAspect: portrait, toAspect: story, sourceAspect: raw)

        // Von Hand nachgerechnet: 4:3-Aufnahme, Ausschnitt 4:5 beginnt bei
        // 0.2667, Ausschnitt 9:16 bei 0.3854 (Bildbreite 4/3, Höhe 1).
        XCTAssertEqual(mapped.minX, (0.26667 + 0.40 * 0.8 - 0.38542) / 0.5625, accuracy: 0.001)
        XCTAssertEqual(mapped.width, 0.20 * 0.8 / 0.5625, accuracy: 0.001)
    }

    func testTheRoundTripComesBack() {
        let rect = CGRect(x: 0.34, y: 0.26, width: 0.16, height: 0.44)
        let narrowed = ImageCrop.remap(rect, fromAspect: portrait, toAspect: story, sourceAspect: raw)
        let back = ImageCrop.remap(narrowed, fromAspect: story, toAspect: portrait, sourceAspect: raw)
        XCTAssertEqual(back.minX, rect.minX, accuracy: 0.001)
        XCTAssertEqual(back.width, rect.width, accuracy: 0.001)
    }

    /// Eine Box am Rand des breiten Formats liegt im schmalen gar nicht mehr
    /// im Bild. Sie wird gestutzt, nicht aus dem Bild geschoben.
    func testABoxOutsideTheNarrowerCropIsClampedIntoTheFrame() {
        let rect = CGRect(x: 0.02, y: 0.30, width: 0.14, height: 0.40)
        let mapped = ImageCrop.remap(rect, fromAspect: portrait, toAspect: story, sourceAspect: raw)
        XCTAssertGreaterThanOrEqual(mapped.minX, 0)
        XCTAssertLessThanOrEqual(mapped.maxX, 1.0001)
    }

    func testNonsenseInputIsHandedBackUnchanged() {
        let rect = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.4)
        XCTAssertEqual(ImageCrop.remap(rect, fromAspect: 0, toAspect: story, sourceAspect: raw), rect)
        XCTAssertEqual(ImageCrop.remap(rect, fromAspect: portrait, toAspect: 0, sourceAspect: raw), rect)
        XCTAssertEqual(ImageCrop.remap(rect, fromAspect: portrait, toAspect: story, sourceAspect: 0), rect)
    }
}
