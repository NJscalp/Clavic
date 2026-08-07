//
//  PlacementSuggesterTests.swift
//  ClavicTests
//
//  Der Platzierungs-Vorschlag ist die eine Stelle im Ablauf, an der die App
//  eine Entscheidung FÜR die Nutzerin trifft. Sitzt die Box falsch, steht die
//  Person am Ende im Gebüsch oder auf einer anderen Person — und das faellt
//  erst am fertigen, bezahlten Bild auf.
//
//  Deshalb pruefen diese Tests nicht die Rechnung, sondern die vier
//  Zusicherungen, auf die sich die Oberflaeche verlaesst: es kommt ueberhaupt
//  ein Vorschlag, er weicht in die leere Bildhaelfte aus, er legt sich nie auf
//  einen erkannten Menschen, und er zappelt zwischen zwei Frames nicht.
//
//  Die Bilder werden synthetisch erzeugt, damit die Tests ohne Kamera,
//  Netzwerk und Testdaten-Dateien laufen.
//

import CoreGraphics
import CoreVideo
import XCTest
@testable import Clavic

final class PlacementSuggesterTests: XCTestCase {

    // MARK: - Hilfen

    /// Erzeugt einen BGRA-Puffer und laesst den Aufrufer hineinzeichnen.
    private func makeBuffer(
        width: Int = 480,
        height: Int = 640,
        draw: (CGContext) -> Void
    ) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard let pixelBuffer = buffer else {
            fatalError("Konnte keinen Testpuffer anlegen")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )!

        // Grundton hell — sonst sieht Vision ueberall „nichts".
        context.setFillColor(CGColor(red: 0.86, green: 0.86, blue: 0.84, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return pixelBuffer
    }

    /// Zeichnet unruhige Struktur — das zieht die Saliency an.
    private func fillWithClutter(_ context: CGContext, in rect: CGRect) {
        var toggle = false
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                toggle.toggle()
                context.setFillColor(toggle
                    ? CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
                    : CGColor(red: 0.95, green: 0.3, blue: 0.1, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 14, height: 14))
                x += 14
            }
            y += 14
        }
    }

    // MARK: - Tests

    func testEmptyBrightSceneReturnsStandingBox() async throws {
        let buffer = makeBuffer { _ in }   // nur der helle Grundton

        let suggestion = await PlacementSuggester.suggest(
            pixelBuffer: buffer, orientation: .up, previousRect: nil
        )

        let result = try XCTUnwrap(suggestion, "Ein leeres, helles Bild muss eine Box liefern")
        XCTAssertEqual(result.pose, .standing)
        XCTAssertFalse(result.poseSentence.isEmpty)
        // Vollstaendig im Bild.
        XCTAssertGreaterThanOrEqual(result.rect.minX, 0)
        XCTAssertLessThanOrEqual(result.rect.maxX, 1)
        XCTAssertLessThanOrEqual(result.rect.maxY, 1)
    }

    func testBoxAvoidsClutteredHalf() async throws {
        // Rechte Haelfte voller Struktur, linke leer.
        let buffer = makeBuffer { context in
            self.fillWithClutter(context, in: CGRect(x: 240, y: 0, width: 240, height: 640))
        }

        let suggestion = await PlacementSuggester.suggest(
            pixelBuffer: buffer, orientation: .up, previousRect: nil
        )

        let result = try XCTUnwrap(suggestion)
        XCTAssertLessThan(result.rect.midX, 0.5,
                          "Die Box gehoert in die leere Bildhaelfte, nicht in die volle")
    }

    func testBoxDoesNotOverlapDetectedPerson() async throws {
        // Grosse menschenaehnliche Silhouette mittig. Erkennt Vision sie nicht,
        // greift ersatzweise die Leere-Regel — beides ist ein gueltiges
        // Ergebnis, ueberlappen darf die Box aber nie.
        let buffer = makeBuffer { context in
            context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 200, y: 380, width: 90, height: 110))   // Kopf
            context.fill(CGRect(x: 175, y: 120, width: 140, height: 270))             // Rumpf
        }

        let suggestion = await PlacementSuggester.suggest(
            pixelBuffer: buffer, orientation: .up, previousRect: nil
        )

        let result = try XCTUnwrap(suggestion)
        // Silhouette in normalisierten Koordinaten, Ursprung oben links.
        let person = CGRect(x: 175.0 / 480, y: 1 - 490.0 / 640,
                            width: 140.0 / 480, height: 370.0 / 640)
        XCTAssertLessThan(PlacementSuggester.iou(person, result.rect), 0.15,
                          "Die Box darf sich nicht auf eine erkannte Person legen")
    }

    func testSmoothingKeepsBoxCalmBetweenFrames() async throws {
        let first = makeBuffer { context in
            self.fillWithClutter(context, in: CGRect(x: 300, y: 0, width: 180, height: 640))
        }
        // Leicht verschobenes Motiv — wie ein minimaler Schwenk.
        let second = makeBuffer { context in
            self.fillWithClutter(context, in: CGRect(x: 288, y: 0, width: 180, height: 640))
        }

        // `await` direkt in XCTUnwrap geht nicht (Autoclosure ohne Concurrency),
        // deshalb erst auswerten, dann auspacken.
        let firstResult = await PlacementSuggester.suggest(
            pixelBuffer: first, orientation: .up, previousRect: nil
        )
        let a = try XCTUnwrap(firstResult)
        let secondResult = await PlacementSuggester.suggest(
            pixelBuffer: second, orientation: .up, previousRect: a.rect
        )
        let b = try XCTUnwrap(secondResult)

        XCTAssertLessThan(abs(a.rect.origin.x - b.rect.origin.x), 0.08,
                          "Die Box darf zwischen zwei aehnlichen Frames nicht springen")
    }
}
