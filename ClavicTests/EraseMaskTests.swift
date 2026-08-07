import UIKit
import XCTest
@testable import Clavic

@MainActor
final class EraseMaskTests: XCTestCase {

    func testPrepareCreatesOneCanonicalPixelGridAndSanitizesStrokes() throws {
        let cgImage = try solidCGImage(width: 80, height: 48,
                                       rgba: (28, 56, 92, 255))
        // A scale other than one must not leak into coordinates sent to the AI.
        let source = UIImage(cgImage: cgImage, scale: 2, orientation: .up)
        let stroke = EraseStroke(
            points: [CGPoint(x: -0.4, y: 1.3), CGPoint(x: 0.5, y: 0.5)],
            width: 1.4
        )

        let prepared = try XCTUnwrap(
            EraseMask.prepare(base: source, strokes: [stroke])
        )

        XCTAssertEqual(prepared.base.imageOrientation, .up)
        XCTAssertEqual(prepared.base.scale, 1)
        XCTAssertEqual(prepared.base.cgImage?.width, 80)
        XCTAssertEqual(prepared.base.cgImage?.height, 48)
        XCTAssertEqual(prepared.marked.cgImage?.width, 80)
        XCTAssertEqual(prepared.marked.cgImage?.height, 48)
        XCTAssertEqual(prepared.mask.cgImage?.width, 80)
        XCTAssertEqual(prepared.mask.cgImage?.height, 48)
        XCTAssertEqual(prepared.strokes[0].points[0], CGPoint(x: 0, y: 1))
        XCTAssertEqual(prepared.strokes[0].width, 1)
    }

    func testCanonicalBaseAppliesRightOrientationAndSwapsPixelDimensions() throws {
        let cgImage = try solidCGImage(width: 30, height: 18,
                                       rgba: (40, 80, 120, 255))
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        let canonical = try XCTUnwrap(EraseMask.canonicalBase(rotated))

        XCTAssertEqual(canonical.imageOrientation, .up)
        XCTAssertEqual(canonical.scale, 1)
        XCTAssertEqual(canonical.cgImage?.width, 18)
        XCTAssertEqual(canonical.cgImage?.height, 30)
    }

    func testCompositeChangesOnlyStrokeMaskAndScalesGeneratedImageToBase() throws {
        let base = UIImage(cgImage: try solidCGImage(
            width: 160, height: 100, rgba: (24, 52, 88, 255)
        ))
        // Deliberately half resolution: compositing must map it to the base grid.
        let generated = UIImage(cgImage: try solidCGImage(
            width: 80, height: 50, rgba: (218, 126, 18, 255)
        ))
        let stroke = EraseStroke(points: [CGPoint(x: 0.5, y: 0.5)],
                                 width: 0.12)
        let prepared = try XCTUnwrap(
            EraseMask.prepare(base: base, strokes: [stroke])
        )

        let output = try XCTUnwrap(
            EraseMask.composite(generated, using: prepared,
                                expansion: 0, feather: 0)
        )

        XCTAssertEqual(output.cgImage?.width, 160)
        XCTAssertEqual(output.cgImage?.height, 100)
        XCTAssertEqual(try pixel(output, x: 4, y: 4),
                       try pixel(prepared.base, x: 4, y: 4),
                       "Pixels outside the stroke must come from the canonical base.")
        XCTAssertEqual(try pixel(output, x: 155, y: 95),
                       try pixel(prepared.base, x: 155, y: 95))
        XCTAssertEqual(try pixel(output, x: 80, y: 50),
                       try pixel(generated, x: 40, y: 25),
                       "The center of a hard mask must come from the generated result.")
    }

    func testDefaultExpansionStillLeavesFarPixelsExactlyUnchanged() throws {
        let base = UIImage(cgImage: try solidCGImage(
            width: 240, height: 180, rgba: (18, 42, 76, 255)
        ))
        let generated = UIImage(cgImage: try solidCGImage(
            width: 240, height: 180, rgba: (204, 112, 30, 255)
        ))
        let stroke = EraseStroke(
            points: [CGPoint(x: 0.45, y: 0.5), CGPoint(x: 0.55, y: 0.5)],
            width: 0.06
        )
        let prepared = try XCTUnwrap(
            EraseMask.prepare(base: base, strokes: [stroke])
        )

        let output = try XCTUnwrap(
            EraseMask.composite(generated, using: prepared)
        )

        XCTAssertEqual(try pixel(output, x: 2, y: 2),
                       try pixel(prepared.base, x: 2, y: 2))
        XCTAssertEqual(try pixel(output, x: 237, y: 177),
                       try pixel(prepared.base, x: 237, y: 177))
        XCTAssertNotEqual(try pixel(output, x: 120, y: 90),
                          try pixel(prepared.base, x: 120, y: 90))
    }

    // MARK: - Pixel helpers

    private enum TestError: Error {
        case imageCreation
        case contextCreation
    }

    private func solidCGImage(
        width: Int,
        height: Int,
        rgba: (UInt8, UInt8, UInt8, UInt8)
    ) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = rgba.0
            bytes[index + 1] = rgba.1
            bytes[index + 2] = rgba.2
            bytes[index + 3] = rgba.3
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw TestError.imageCreation
        }
        return image
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> [UInt8] {
        guard let cgImage = image.cgImage else { throw TestError.imageCreation }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw TestError.contextCreation
        }
        context.interpolationQuality = .none
        context.translateBy(x: CGFloat(-x), y: CGFloat(y - cgImage.height + 1))
        context.draw(cgImage, in: CGRect(x: 0, y: 0,
                                        width: cgImage.width,
                                        height: cgImage.height))
        return bytes
    }
}
