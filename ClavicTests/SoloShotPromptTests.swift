import XCTest
import UIKit
import CoreImage
@testable import Clavic

final class SoloShotPromptTests: XCTestCase {
    func testOneShotUsesSeedreamV5ProEdit() {
        XCTAssertEqual(
            ImageEditAPI.soloShotModel,
            "bytedance/seedream-v5.0-pro/edit"
        )
        XCTAssertEqual(ImageEditAPI.soloShotModel, ImageEditAPI.defaultModel)
        XCTAssertEqual(ImageEditAPI.soloShotDisplayName, "Seedream 5.0 Pro")
    }

    func testPromptKeepsOriginalGuideAndPersonAsSeparateFigures() {
        let prompt = SoloShotPrompt.build(
            userText: "",
            placement: placement(),
            hasIdentityCloseup: true
        )

        XCTAssertLessThanOrEqual(prompt.count, SoloShotPrompt.maximumLength)
        XCTAssertTrue(prompt.contains("FIGURE 1 is the immutable original scene"))
        XCTAssertTrue(prompt.contains("FIGURE 2 is only a placement map"))
        XCTAssertTrue(prompt.contains("FIGURE 3 is the full identity and wardrobe reference"))
        XCTAssertTrue(prompt.contains("FIGURE 4 is a tight identity lock"))
        XCTAssertTrue(prompt.contains("exact hair base color, highlights and streak pattern"))
        XCTAssertTrue(prompt.contains("It is not a pose reference"))
        XCTAssertTrue(prompt.contains("x 20–50% and y 25–85%"))
        XCTAssertTrue(prompt.contains("maximum insertion zone, not a demand to show a full body"))
        XCTAssertTrue(prompt.contains("POSE OVERRIDE: FIGURE 3's pose is forbidden"))
        XCTAssertTrue(prompt.contains("head naturally upright"))
        XCTAssertTrue(prompt.contains("Apply FIGURE 1's actual light over the locked skin and hair colors"))
        XCTAssertTrue(prompt.contains("Existing foreground has absolute priority"))
        XCTAssertTrue(prompt.contains("Never remove an object or reveal invented legs or feet"))
        XCTAssertTrue(prompt.contains("Do not cut out, paste, overlay or preserve FIGURE 3 pixels"))
        XCTAssertTrue(prompt.contains("Local pixels may change where those effects touch the scene"))
        XCTAssertTrue(prompt.contains("Every FIGURE 1 pixel outside the visible inserted person"))
        XCTAssertTrue(prompt.contains("never a sticker or composite"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("qwen"))
    }

    func testLongDirectionCannotDisplaceRealismRules() {
        let prompt = SoloShotPrompt.build(
            userText: String(repeating: "natural editorial mood ", count: 300),
            placement: placement()
        )

        XCTAssertLessThanOrEqual(prompt.count, SoloShotPrompt.maximumLength)
        XCTAssertTrue(prompt.contains("The person must not be cleaner, brighter, sharper"))
        XCTAssertTrue(prompt.contains("contact shadow"))
        XCTAssertTrue(prompt.contains("never a sticker or composite"))
    }

    func testGenericInstructionIsRemoved() {
        XCTAssertEqual(
            SoloShotPrompt.sanitizeUserNote("Add me in the image."),
            ""
        )
    }

    func testSceneLockRestoresOriginalOutsidePersonMask() throws {
        let size = CGSize(width: 80, height: 100)
        let original = solidImage(.systemBlue, size: size)
        let generated = solidImage(.systemRed, size: size)
        let extent = CGRect(origin: .zero, size: size)
        let person = CGRect(x: 28, y: 25, width: 24, height: 55)
        let mask = CIImage(color: .white)
            .cropped(to: person)
            .composited(over: CIImage(color: .black).cropped(to: extent))

        let result = try XCTUnwrap(
            SoloShotSceneLock.composite(
                generated: generated,
                original: original,
                personMask: mask
            )
        )
        let corner = rgba(result, at: CGRect(x: 2, y: 2, width: 1, height: 1))
        let center = rgba(result, at: CGRect(x: 39, y: 49, width: 1, height: 1))

        XCTAssertLessThan(corner[0], 80)
        XCTAssertGreaterThan(corner[2], 140)
        XCTAssertGreaterThan(center[0], 140)
        XCTAssertLessThan(center[2], 100)
    }

    private func placement() -> PlacementSuggestion {
        PlacementSuggestion(
            rect: CGRect(x: 0.20, y: 0.25, width: 0.30, height: 0.60),
            pose: .standing,
            confidence: 1,
            poseSentence: "standing naturally with believable balance",
            tiltDegrees: nil
        )
    }

    private func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func rgba(_ image: UIImage, at bounds: CGRect) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        if let ci = CIImage(image: image) {
            CIContext().render(
                ci,
                toBitmap: &pixel,
                rowBytes: 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: space
            )
        }
        return pixel
    }
}
