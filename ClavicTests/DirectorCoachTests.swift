//
//  DirectorCoachTests.swift
//  ClavicTests
//
//  Im Regie-Modus loest die App von selbst aus. Das ist nur dann eine gute
//  Idee, wenn die Bedingung dafuer stimmt: sagt der Coach faelschlich „passt",
//  entsteht ein Burst von sechs unbrauchbaren Bildern, und sagt er nie „passt",
//  passiert ueberhaupt nichts und niemand weiss, warum.
//
//  Ausserdem darf immer nur EIN Hinweis kommen. Diese Tests halten die
//  Rangfolge fest, damit sie nicht beim naechsten Umbau kippt.
//

import CoreGraphics
import XCTest
@testable import Clavic

final class DirectorCoachTests: XCTestCase {

    /// Eine Einstellung, an der nichts auszusetzen ist.
    private var good: DirectorFrame {
        DirectorFrame(
            person: CGRect(x: 0.30, y: 0.10, width: 0.34, height: 0.80),
            chestY: 0.42,
            horizonDegrees: 1.0
        )
    }

    func testGoodFrameProducesNoHint() {
        XCTAssertNil(DirectorCoach.hint(for: good))
    }

    func testNobodyInFrameAsksToComeCloser() {
        XCTAssertEqual(DirectorCoach.hint(for: DirectorFrame()), .comeCloser)
    }

    func testSmallPersonAsksToComeCloser() {
        var frame = good
        frame.person = CGRect(x: 0.42, y: 0.40, width: 0.14, height: 0.32)
        XCTAssertEqual(DirectorCoach.hint(for: frame), .comeCloser)
    }

    func testChestBelowCentreMeansPhoneIsTooHigh() {
        var frame = good
        frame.chestY = 0.72
        XCTAssertEqual(DirectorCoach.hint(for: frame), .phoneLower)
    }

    func testFeetTouchingTheBottomEdgeAsksToTiltDown() {
        var frame = good
        frame.person = CGRect(x: 0.30, y: 0.18, width: 0.34, height: 0.82)
        XCTAssertEqual(DirectorCoach.hint(for: frame), .tiltDown)
    }

    func testTiltedHorizonAsksToHoldStraight() {
        var frame = good
        frame.horizonDegrees = -6.5
        XCTAssertEqual(DirectorCoach.hint(for: frame), .holdStraight)
        // Knapp unter der Schwelle darf es nicht meckern — sonst steht der
        // Hinweis dauerhaft im Bild und der Burst faellt nie.
        frame.horizonDegrees = 3.9
        XCTAssertNil(DirectorCoach.hint(for: frame))
    }

    /// Alles gleichzeitig falsch: es kommt trotzdem genau ein Hinweis, und
    /// zwar der, den man zuerst beheben wuerde.
    func testOnlyTheMostImportantHintSurvives() {
        let frame = DirectorFrame(
            person: CGRect(x: 0.42, y: 0.62, width: 0.14, height: 0.38),
            chestY: 0.88,
            horizonDegrees: 12
        )
        XCTAssertEqual(DirectorCoach.hint(for: frame), .comeCloser)
    }

    func testMissingPoseDoesNotInventAHeightComplaint() {
        var frame = good
        frame.chestY = nil
        XCTAssertNil(DirectorCoach.hint(for: frame))
    }
}
