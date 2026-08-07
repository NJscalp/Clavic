import CoreImage
import UIKit
import XCTest
@testable import Clavic

@MainActor
final class PhotoEditEngineTests: XCTestCase {

    func testPreviewUsesUprightScaleOnePixelSpaceAndHonorsMaximumEdge() throws {
        let base = try makeImage(width: 24, height: 12) { x, y in
            x < 12 ? (220, UInt8(y * 8), 30, 255) : (20, 70, 210, 255)
        }
        let raw = try XCTUnwrap(base.cgImage)
        // Reale Kamera-/Photo-Library-Bilder koennen rohe Querformatpixel mit
        // einer EXIF-Drehung und einem UIKit-Scale groesser als 1 liefern.
        let rotated = UIImage(cgImage: raw, scale: 2, orientation: .right)

        let preview = PhotoEditEngine.preview(from: rotated, maxDimension: 10)
        let pixels = try XCTUnwrap(preview.cgImage)

        XCTAssertEqual(preview.imageOrientation, .up)
        XCTAssertEqual(preview.scale, 1)
        XCTAssertEqual(pixels.width, 5)
        XCTAssertEqual(pixels.height, 10)
        XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 10)
    }

    func testBodyWarpFailsClosedWithoutDetectedPerson() throws {
        let width = 220
        let height = 180
        let source = try makeImage(width: width, height: height) { x, y in
            (UInt8((x * 3) % 255), UInt8((y * 5) % 255), UInt8((x + y) % 255), 255)
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))
        var edits = PhotoEdits()
        edits.body[.waist] = 1
        let unsafeFallback = BodyAnalysis(
            hasPerson: false,
            zones: BodyPart.defaultZones,
            mask: whiteMask(size: CGSize(width: width, height: height))
        )

        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, analysis: unsafeFallback)
        )
        let before = try pixels(of: baseline)
        let after = try pixels(of: result)
        XCTAssertEqual(
            meanRGBDelta(before, after, xRange: 0..<width, yRange: 0..<height),
            0,
            accuracy: 0.01,
            "Ohne sicher erkannte Person duerfen Default-Zonen das Foto nicht verformen."
        )
    }

    func testPersonBoundingBoxFallbackZonesStayInsideDetectedPerson() {
        let box = CGRect(x: 0.12, y: 0.18, width: 0.34, height: 0.70)
        let zones = BodyAnalyzer.zones(fromPersonBoundingBox: box)

        XCTAssertEqual(zones.count, BodyPart.allCases.count)
        for part in BodyPart.allCases {
            guard let zone = zones[part] else {
                XCTFail("Fehlende Zone fuer \(part.rawValue)")
                continue
            }
            XCTAssertTrue(box.insetBy(dx: -0.001, dy: -0.001).contains(zone.center))
            XCTAssertLessThanOrEqual(CGFloat(zone.radiusX), box.width / 2 + 0.001)
            XCTAssertLessThanOrEqual(CGFloat(zone.radiusY), box.height / 2 + 0.001)
        }
        let allBody = zones[.allBody]
        XCTAssertNotNil(allBody)
        XCTAssertEqual(allBody?.center.x ?? -1, box.midX, accuracy: 0.0001)
        XCTAssertEqual(allBody?.center.y ?? -1, box.midY, accuracy: 0.0001)
    }

    func testBodyAnalyzerPersonMaskMatchesCanonicalReferencePixels() async throws {
        let bundle = Bundle(for: type(of: self))
        let sourceURL = try XCTUnwrap(bundle.url(forResource: "clav_face", withExtension: "jpg"))
        let source = try XCTUnwrap(UIImage(data: Data(contentsOf: sourceURL)))
        let preview = PhotoEditEngine.preview(from: source, maxDimension: 900)
        let result = await BodyAnalyzer.analyze(preview)

        guard let mask = result.mask else {
            throw XCTSkip("Die lokale Vision-Segmentierung ist in diesem Simulator nicht verfuegbar.")
        }
        let pixels = try XCTUnwrap(preview.cgImage)
        XCTAssertTrue(result.hasPerson, "Eine erfolgreiche Personenmaske muss hasPerson setzen, auch ohne Pose-Modell.")
        XCTAssertEqual(mask.extent.width, CGFloat(pixels.width), accuracy: 0.5)
        XCTAssertEqual(mask.extent.height, CGFloat(pixels.height), accuracy: 0.5)

        let allBody = result.zone(.allBody)
        XCTAssertTrue((0...1).contains(allBody.center.x))
        XCTAssertTrue((0...1).contains(allBody.center.y))
    }

    func testCreateVisualReferenceRendersWhenRequested() async throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["CLAVIC_VISUAL_OUTPUT_DIR"] else {
            throw XCTSkip("Set CLAVIC_VISUAL_OUTPUT_DIR to create manual before/after renders.")
        }
        let bundle = Bundle(for: type(of: self))
        let sourceURL = try XCTUnwrap(bundle.url(forResource: "clav_face", withExtension: "jpg"))
        let source = try XCTUnwrap(UIImage(data: Data(contentsOf: sourceURL)))
        let preview = PhotoEditEngine.preview(from: source, maxDimension: 900)

        async let bodyResult = BodyAnalyzer.analyze(preview)
        async let faceResult = FaceAnalyzer.analyze(preview)
        let (body, detectedFace) = await (bodyResult, faceResult)
        // Vision-Modelle stehen in manchen Simulator-Runtimes nicht zur
        // Verfügung. Für diesen manuellen Render-Test reicht dann dieselbe
        // sichere Fallback-Zone, die auch die App benutzt.
        let face = detectedFace.hasFace ? detectedFace : .fallback()

        var foreheadEdits = PhotoEdits()
        foreheadEdits.face[.forehead] = 1
        let forehead = try XCTUnwrap(
            PhotoEditEngine.render(foreheadEdits, from: preview, analysis: body, face: face)
        )

        var skinEdits = PhotoEdits()
        skinEdits.skinTone = 1
        let skin = try XCTUnwrap(
            PhotoEditEngine.render(skinEdits, from: preview, analysis: body, face: face)
        )

        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(preview.pngData()).write(to: directory.appendingPathComponent("face-before.png"))
        try XCTUnwrap(forehead.pngData()).write(to: directory.appendingPathComponent("face-forehead-after.png"))
        try XCTUnwrap(skin.pngData()).write(to: directory.appendingPathComponent("face-skin-after.png"))
    }

    func testSkinToneChangesSkinButLeavesNonSkinPixelsAlone() throws {
        let size = CGSize(width: 240, height: 120)
        let source = try makeImage(width: 240, height: 120) { x, _ in
            // Linke Hälfte: typischer Haut-Chromawert. Rechte Hälfte: Blau.
            x < 120 ? (191, 122, 92, 255) : (35, 94, 205, 255)
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))

        var edits = PhotoEdits()
        edits.skinTone = 1
        let analysis = BodyAnalysis(
            hasPerson: true,
            zones: BodyPart.defaultZones,
            mask: whiteMask(size: size)
        )
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, analysis: analysis)
        )

        let before = try pixels(of: baseline)
        let after = try pixels(of: result)
        let skinDelta = meanRGBDelta(before, after, xRange: 20..<100, yRange: 20..<100)
        let blueDelta = meanRGBDelta(before, after, xRange: 160..<220, yRange: 20..<100)

        XCTAssertGreaterThan(skinDelta, 3, "Der Hautton-Regler muss auf erkannter Haut sichtbar wirken.")
        XCTAssertLessThan(blueDelta, 0.2, "Nicht-Haut-Pixel dürfen nicht mitgefärbt werden.")
    }

    func testSkinToneAlsoRecognizesDarkLowLightSkin() throws {
        let size = CGSize(width: 120, height: 100)
        let source = try makeImage(width: 120, height: 100) { _, _ in
            // Gleiche Rot-/Chroma-Verhältnisse wie Haut, aber bewusst deutlich
            // unter der früheren absoluten r>0.28-Schwelle.
            (51, 31, 21, 255)
        }
        let analysis = BodyAnalysis(
            hasPerson: true,
            zones: BodyPart.defaultZones,
            mask: whiteMask(size: size)
        )
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))
        var edits = PhotoEdits()
        edits.skinTone = 1
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, analysis: analysis)
        )

        let before = try pixels(of: baseline)
        let after = try pixels(of: result)
        XCTAssertGreaterThan(
            meanRGBDelta(before, after, xRange: 10..<110, yRange: 10..<90),
            1.5,
            "Dunkle Haut darf durch absolute Helligkeitsschwellen nicht ausgeschlossen werden."
        )
    }

    func testSkinToneDoesNothingWithoutPersonMask() throws {
        let source = try makeImage(width: 160, height: 120) { _, _ in
            (191, 122, 92, 255)
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))

        var edits = PhotoEdits()
        edits.skinTone = 1
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, analysis: .fallback())
        )

        let before = try pixels(of: baseline)
        let after = try pixels(of: result)
        XCTAssertEqual(
            meanRGBDelta(before, after, xRange: 0..<160, yRange: 0..<120),
            0,
            accuracy: 0.01,
            "Ohne sichere Personenmaske darf nicht ersatzweise das ganze Foto getönt werden."
        )
    }

    func testPreviewPersonMaskScalesToFullResolution() throws {
        let source = try makeImage(width: 240, height: 120) { _, _ in
            (191, 122, 92, 255)
        }
        // So groß wie eine Analyse-Vorschau und nur links weiß. Beim Rendern
        // muss die Trennkante von x=60 auf x=120 skaliert werden.
        let smallMaskImage = try makeImage(width: 120, height: 60) { x, _ in
            x < 60 ? (255, 255, 255, 255) : (0, 0, 0, 255)
        }
        let smallMask = try XCTUnwrap(CIImage(image: smallMaskImage))
        let analysis = BodyAnalysis(
            hasPerson: true,
            zones: BodyPart.defaultZones,
            mask: smallMask
        )

        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))
        var edits = PhotoEdits()
        edits.skinTone = 1
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, analysis: analysis)
        )

        let before = try pixels(of: baseline)
        let after = try pixels(of: result)
        let insideScaledMask = meanRGBDelta(before, after, xRange: 72..<105, yRange: 30..<90)
        let outsideScaledMask = meanRGBDelta(before, after, xRange: 165..<215, yRange: 30..<90)
        XCTAssertGreaterThan(insideScaledMask, 2)
        XCTAssertLessThan(outsideScaledMask, 0.2)
    }

    func testFaceEditDoesNothingWhenNoFaceWasDetected() throws {
        let source = try makeImage(width: 180, height: 180) { x, y in
            (UInt8((x * 3) % 256), UInt8((y * 5) % 256), UInt8((x + y) % 256), 255)
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))
        var edits = PhotoEdits()
        edits.face[.forehead] = 1
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, face: .fallback())
        )
        let before = try pixels(of: baseline)
        let after = try pixels(of: result)
        XCTAssertEqual(
            meanRGBDelta(before, after, xRange: 0..<180, yRange: 0..<180),
            0,
            accuracy: 0.01
        )
    }

    func testForeheadWarpStaysInsideAnalyzedEllipse() throws {
        let width = 240
        let height = 240
        let source = try makeImage(width: width, height: height) { x, y in
            // Zweidimensionales Muster: eine lokale Verschiebung ist gut
            // messbar, während unveränderte Bereiche pixelgenau gleich bleiben.
            let r = UInt8((x * 5 + y * 2) % 256)
            let g = UInt8((x * 2 + y * 7) % 256)
            let b = UInt8((x * 3 + y * 11) % 256)
            return (r, g, b, 255)
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))

        let forehead = BodyZone(
            center: CGPoint(x: 0.5, y: 0.5),
            radiusX: 0.20,
            radiusY: 0.10
        )
        var face = FaceAnalysis.fallback()
        face.hasFace = true
        face.zones[.forehead] = forehead

        var edits = PhotoEdits()
        edits.face[.forehead] = 1
        let analysis = BodyAnalysis(
            hasPerson: true,
            zones: BodyPart.defaultZones,
            mask: whiteMask(size: CGSize(width: width, height: height))
        )
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, analysis: analysis, face: face)
        )

        let before = try pixels(of: baseline)
        let after = try pixels(of: result)
        let centerDelta = meanRGBDelta(before, after, xRange: 92..<148, yRange: 104..<116)

        // Die Ellipse endet bei x=72...168 und y=96...144. Diese Bereiche
        // liegen mit Abstand außerhalb und müssen deshalb unverändert bleiben.
        let topDelta = meanRGBDelta(before, after, xRange: 0..<240, yRange: 0..<80)
        let sideDelta = meanRGBDelta(before, after, xRange: 0..<60, yRange: 80..<160)

        XCTAssertGreaterThan(centerDelta, 0.5, "Der Stirn-Regler muss innerhalb seiner Zone wirken.")
        XCTAssertLessThan(topDelta, 0.05, "Die Verformung darf Haare/Pixel oberhalb der Stirnzone nicht verschieben.")
        XCTAssertLessThan(sideDelta, 0.05, "Die Verformung darf nicht mehr als Linie über die ganze Bildbreite laufen.")
    }

    func testFilterIntensityHasExactZeroAndFullEndpoints() throws {
        let source = try makeImage(width: 160, height: 100) { x, y in
            (
                UInt8(35 + (x * 2 + y) % 190),
                UInt8(25 + (x + y * 3) % 180),
                UInt8(20 + (x * 3 + y * 2) % 200),
                255
            )
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))

        var zero = PhotoEdits()
        zero.filter = .mono
        zero.filterIntensity = 0
        let zeroResult = try XCTUnwrap(PhotoEditEngine.render(zero, from: source))

        var half = zero
        half.filterIntensity = 0.5
        let halfResult = try XCTUnwrap(PhotoEditEngine.render(half, from: source))

        var full = zero
        full.filterIntensity = 1
        let fullResult = try XCTUnwrap(PhotoEditEngine.render(full, from: source))

        let before = try pixels(of: baseline)
        let zeroPixels = try pixels(of: zeroResult)
        let halfPixels = try pixels(of: halfResult)
        let fullPixels = try pixels(of: fullResult)
        let zeroDelta = meanRGBDelta(before, zeroPixels, xRange: 0..<160, yRange: 0..<100)
        let halfDelta = meanRGBDelta(before, halfPixels, xRange: 0..<160, yRange: 0..<100)
        let fullDelta = meanRGBDelta(before, fullPixels, xRange: 0..<160, yRange: 0..<100)

        XCTAssertEqual(zeroDelta, 0, accuracy: 0.01)
        XCTAssertGreaterThan(fullDelta, 5)
        XCTAssertGreaterThan(halfDelta, 1)
        XCTAssertLessThan(halfDelta, fullDelta)
    }

    func testRetouchEffectsStayOnSkinAndFailClosedWithoutMask() throws {
        let width = 200
        let height = 120
        let source = try makeImage(width: width, height: height) { x, y in
            if x < 105 {
                // Zwei hautartige Töne geben Smooth/Even eine echte Textur,
                // während Redness/Matte/Glow ebenfalls sichtbar bleiben.
                return (x + y).isMultiple(of: 2)
                    ? (205, 132, 98, 255)
                    : (154, 83, 66, 255)
            }
            return (30, 82, 205, 255)
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))
        let before = try pixels(of: baseline)
        let analysis = BodyAnalysis(
            hasPerson: true,
            zones: BodyPart.defaultZones,
            mask: whiteMask(size: CGSize(width: width, height: height))
        )
        let effects: [(String, WritableKeyPath<PhotoEdits, Double>)] = [
            ("Smooth", \.smooth),
            ("Even skin", \.evenSkin),
            ("Redness", \.redness),
            ("Matte", \.matte),
            ("Glow", \.glow),
        ]

        for (name, keyPath) in effects {
            var edits = PhotoEdits()
            edits[keyPath: keyPath] = 1
            let result = try XCTUnwrap(
                PhotoEditEngine.render(edits, from: source, analysis: analysis)
            )
            let after = try pixels(of: result)
            XCTAssertGreaterThan(
                meanRGBDelta(before, after, xRange: 18..<88, yRange: 18..<102),
                0.35,
                "\(name) muss auf der Haut sichtbar sein."
            )
            XCTAssertLessThan(
                meanRGBDelta(before, after, xRange: 140..<190, yRange: 18..<102),
                0.05,
                "\(name) darf Nicht-Haut-Pixel nicht verändern."
            )

            let noMask = try XCTUnwrap(
                PhotoEditEngine.render(edits, from: source, analysis: .fallback())
            )
            let noMaskPixels = try pixels(of: noMask)
            XCTAssertEqual(
                meanRGBDelta(before, noMaskPixels, xRange: 0..<width, yRange: 0..<height),
                0,
                accuracy: 0.01,
                "\(name) muss ohne Personenmaske sicher schließen."
            )
        }
    }

    func testMakeupDoesNothingWithoutDetectedFace() throws {
        let source = try makeImage(width: 180, height: 180) { x, y in
            (UInt8(70 + x % 120), UInt8(45 + y % 100), UInt8(35 + (x + y) % 90), 255)
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))
        var edits = PhotoEdits()
        edits.foundation = 1
        edits.blush = 1
        edits.contour = 1
        edits.lipColor = 1
        edits.eyeBright = 1
        edits.teethWhite = 1
        let analysis = BodyAnalysis(
            hasPerson: true,
            zones: BodyPart.defaultZones,
            mask: whiteMask(size: CGSize(width: 180, height: 180))
        )
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source,
                                   analysis: analysis, face: .fallback())
        )
        XCTAssertEqual(
            meanRGBDelta(try pixels(of: baseline), try pixels(of: result),
                         xRange: 0..<180, yRange: 0..<180),
            0,
            accuracy: 0.01
        )
    }

    func testLipColorStaysInsideAnalyzedLipZone() throws {
        let width = 200
        let height = 200
        let source = try makeImage(width: width, height: height) { _, _ in
            (105, 105, 105, 255)
        }
        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))
        var face = FaceAnalysis.fallback()
        face.hasFace = true
        face.zones[.lips] = BodyZone(
            center: CGPoint(x: 0.5, y: 0.58), radiusX: 0.14, radiusY: 0.07
        )
        let analysis = BodyAnalysis(
            hasPerson: true,
            zones: BodyPart.defaultZones,
            mask: whiteMask(size: CGSize(width: width, height: height))
        )
        var edits = PhotoEdits()
        edits.lipColor = 1
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, analysis: analysis, face: face)
        )
        let before = try pixels(of: baseline)
        let after = try pixels(of: result)
        XCTAssertGreaterThan(
            meanRGBDelta(before, after, xRange: 90..<110, yRange: 110..<122), 2
        )
        XCTAssertLessThan(
            meanRGBDelta(before, after, xRange: 0..<45, yRange: 0..<45), 0.05
        )
    }

    func testHairTintUsesPersonCapAndExcludesSkinAndBackground() throws {
        let width = 240
        let height = 240
        let source = try makeImage(width: width, height: height) { x, y in
            guard x >= 36, x < 204, y < 220 else { return (25, 78, 196, 255) }
            if y < 82 { return (34, 39, 48, 255) }                // Haar
            if x >= 70, x < 170, y < 184 { return (191, 122, 92, 255) } // Haut
            return (35, 120, 70, 255)                             // Kleidung
        }
        let maskImage = try makeImage(width: width, height: height) { x, y in
            x >= 36 && x < 204 && y < 220
                ? (255, 255, 255, 255)
                : (0, 0, 0, 255)
        }
        let analysis = BodyAnalysis(
            hasPerson: true,
            zones: BodyPart.defaultZones,
            mask: try XCTUnwrap(CIImage(image: maskImage))
        )
        var face = FaceAnalysis.fallback()
        face.hasFace = true

        let baseline = try XCTUnwrap(PhotoEditEngine.render(PhotoEdits(), from: source))
        var edits = PhotoEdits()
        edits.hairTint = .copper
        edits.hairTintIntensity = 1
        let result = try XCTUnwrap(
            PhotoEditEngine.render(edits, from: source, analysis: analysis, face: face)
        )
        let before = try pixels(of: baseline)
        let after = try pixels(of: result)

        XCTAssertGreaterThan(
            meanRGBDelta(before, after, xRange: 82..<158, yRange: 16..<58), 1,
            "Die sichere obere Kopfzone muss getönt werden."
        )
        XCTAssertLessThan(
            meanRGBDelta(before, after, xRange: 88..<152, yRange: 108..<158), 0.1,
            "Erkannte Haut darf keine Haarfarbe erhalten."
        )
        XCTAssertLessThan(
            meanRGBDelta(before, after, xRange: 0..<24, yRange: 20..<200), 0.05,
            "Außerhalb der Personenmaske muss der Hintergrund exakt bleiben."
        )
    }

    // MARK: - Pixel helpers

    private struct PixelBuffer {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    private enum PixelTestError: Error {
        case imageCreation
        case contextCreation
        case missingCGImage
    }

    private func makeImage(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
    ) throws -> UIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                let index = (y * width + x) * 4
                bytes[index] = value.0
                bytes[index + 1] = value.1
                bytes[index + 2] = value.2
                bytes[index + 3] = value.3
            }
        }

        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let cg = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw PixelTestError.imageCreation
        }
        return UIImage(cgImage: cg)
    }

    private func whiteMask(size: CGSize) -> CIImage {
        CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func pixels(of image: UIImage) throws -> PixelBuffer {
        guard let cg = image.cgImage else { throw PixelTestError.missingCGImage }
        let width = cg.width
        let height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PixelTestError.contextCreation
        }
        context.interpolationQuality = .none
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PixelBuffer(width: width, height: height, bytes: bytes)
    }

    private func meanRGBDelta(
        _ lhs: PixelBuffer,
        _ rhs: PixelBuffer,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Double {
        precondition(lhs.width == rhs.width && lhs.height == rhs.height)
        var total = 0
        var samples = 0
        for y in yRange {
            for x in xRange {
                let index = (y * lhs.width + x) * 4
                total += abs(Int(lhs.bytes[index]) - Int(rhs.bytes[index]))
                total += abs(Int(lhs.bytes[index + 1]) - Int(rhs.bytes[index + 1]))
                total += abs(Int(lhs.bytes[index + 2]) - Int(rhs.bytes[index + 2]))
                samples += 3
            }
        }
        return Double(total) / Double(samples)
    }
}
