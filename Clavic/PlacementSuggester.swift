//
//  PlacementSuggester.swift
//  Clavic
//
//  Wer allein unterwegs ist und sich in einen Ort einfügen will, muss heute
//  selbst raten, wo im Bild sie später stehen soll. Das ist die schwerste
//  Entscheidung im ganzen Ablauf — und ausgerechnet die, für die man am
//  wenigsten Anhaltspunkte hat, während man das Telefon hochhält.
//
//  Die Kamera weiß es besser: sie sieht, wo das Bild leer ist, wo der Boden
//  verläuft und aus welcher Richtung das Licht kommt. Genau diese drei
//  Beobachtungen entscheiden hier, wo die Box liegt.
//
//  Bewusst ein VORSCHLAG, nie ein Zwang. Die Nutzerin kann die Box jederzeit
//  verschieben, und ihre Position gewinnt dann immer — deshalb gibt diese
//  Datei nur Daten zurück und fasst keine UI an.
//
//  Kein ARKit: das läuft nicht auf allen Geräten und braucht Bewegung, bevor
//  es etwas weiß. Vision liefert alles Nötige aus einem einzigen Standbild.
//

import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Eine vorgeschlagene Stelle im Livebild, an der die Person später stehen soll.
struct PlacementSuggestion: Equatable {
    enum Pose: String, Equatable {
        case standing      // freier Raum, Füße am Boden
        case seated        // erkannte horizontale Kante auf Sitzhöhe
        case leaning       // große ruhige vertikale Fläche daneben (Wand)
    }

    /// Normalisiert (0…1), Ursprung OBEN LINKS, im Koordinatensystem des
    /// angezeigten Kamerabilds — nicht im Vision-System.
    var rect: CGRect
    var pose: Pose
    /// 0…1. Unter 0.35 zeigt die UI die Box nicht an.
    var confidence: Double
    /// Fertiger Teilsatz für den Bild-Prompt.
    var poseSentence: String
}

enum PlacementSuggester {

    /// EIN Kontext für alle Messungen, nicht einer je Bild.
    ///
    /// Ein `CIContext` hält Metal-Ressourcen. Bei acht Analysen je Sekunde
    /// entstünden sonst sechzehn davon pro Sekunde — das kostet Speicher und
    /// Akku, und unter Last bricht der Prozess irgendwann ab.
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    // MARK: - Öffentliche API

    /// Analysiert genau einen Kameraframe. Gibt `nil` zurück, wenn keine
    /// brauchbare Stelle gefunden wurde.
    ///
    /// `aspect` ist das Seitenverhältnis des angezeigten Rahmens. Der Sensor
    /// liefert 4:3, die Vorschau zeigt aber z. B. 4:5 — ohne denselben Zuschnitt
    /// läge die Box im Livebild woanders als später im gespeicherten Foto.
    static func suggest(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        previousRect: CGRect?,
        aspect: CGFloat? = nil
    ) async -> PlacementSuggestion? {
        await withCheckedContinuation { continuation in
            // Vision und die Luminanz-Messung sind rechenintensiv genug, um
            // eine Kamera-Vorschau sichtbar stocken zu lassen.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: analyse(
                        pixelBuffer: pixelBuffer,
                        orientation: orientation,
                        previousRect: previousRect,
                        aspect: aspect
                    )
                )
            }
        }
    }

    // MARK: - Analyse

    private static func analyse(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        previousRect: CGRect?,
        aspect: CGFloat?
    ) -> PlacementSuggestion? {
        // --- Schritt 1: zuschneiden und verkleinern. Alles Weitere rechnet auf
        // dieser Fassung.
        guard let small = downscaled(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            aspect: aspect
        ) else {
            return nil
        }

        // --- Schritt 2: alle Requests in EINEM Handler.
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let horizon = VNDetectHorizonRequest()
        let humans = VNDetectHumanRectanglesRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = 0.2
        rectangles.maximumObservations = 8

        // Jeder Request einzeln: die drei modellgestützten (Saliency, Personen,
        // Gesichter) können auf einem Gerät fehlschlagen, auf dem die anderen
        // laufen. Liefen alle in einem Aufruf, würde ein einziger Fehlschlag
        // den gesamten Vorschlag kosten — und die Nutzerin sähe gar keine Box.
        let handler = VNImageRequestHandler(ciImage: small, options: [:])
        for request in [saliency, horizon, humans, faces, rectangles] as [VNRequest] {
            try? handler.perform([request])
        }

        // --- Schritt 3: Saliency-Matrix.
        // Fällt Vision aus, messen wir die Unruhe des Bildes selbst. Das ist
        // gröber, aber es hält den Vorschlag am Leben statt ihn zu streichen.
        // EIN Graustufen-Durchgang für beide Messungen unten.
        let gray = grayscale(small)

        var map = saliencyMatrix(saliency.results?.first as? VNSaliencyImageObservation)
        let usedFallbackMap = map.isEmpty
        if usedFallbackMap, let gray {
            map = structureMatrix(gray)
        }

        // Horizont: Vision liefert eine Transformation, aus der sich die Höhe
        // der Linie in der Bildmitte ableiten lässt.
        let horizonY = horizonHeight(horizon.results?.first as? VNHorizonObservation)

        // Personen und Gesichter, umgerechnet auf „Ursprung oben links".
        let blockers = (humans.results ?? []).map { flip($0.boundingBox) }
            + (faces.results ?? []).map { flip($0.boundingBox) }

        let columnLuma = gray.map(columnLuminance) ?? []

        // --- Schritt 4 + 5: Kandidaten bilden und bewerten.
        let centers: [CGFloat] = [0.25, 0.33, 0.50, 0.67, 0.75]
        let footYs: [CGFloat] = [0.72, 0.80, 0.88, 0.96]

        var best: (rect: CGRect, score: Double)?

        for cx in centers {
            for footY in footYs {
                let height = min(max(0.42 + (footY - 0.72) * 1.1, 0.42), 0.86)
                let width = height * 0.38
                let rect = CGRect(
                    x: cx - width / 2,
                    y: footY - height,
                    width: width,
                    height: height
                )

                // Muss mit Rand vollständig im Bild liegen.
                let margin: CGFloat = 0.03
                guard rect.minX >= margin, rect.maxX <= 1 - margin,
                      rect.minY >= margin, rect.maxY <= 1 - margin else { continue }

                // Harte Ablehnung: Überschneidung mit Person oder Gesicht.
                if blockers.contains(where: { iou($0, rect) > 0.15 }) { continue }

                let emptiness = 1 - meanSaliency(map, in: rect)
                let thirds = min(max(1 - min(abs(cx - 1.0 / 3), abs(cx - 2.0 / 3)) / 0.17, 0), 1)
                let ground: Double
                if let horizonY {
                    ground = rect.maxY > horizonY ? 1.0 : 0.0
                } else {
                    ground = 0.5
                }
                let light = facesTheLight(cx: cx, columns: columnLuma) ? 1.0 : 0.3
                let centerBias = 1 - Double(abs(cx - 0.5)) * 2

                let score = emptiness * 0.40
                    + Double(thirds) * 0.20
                    + ground * 0.20
                    + light * 0.10
                    + centerBias * 0.10

                if best == nil || score > best!.score {
                    best = (rect, score)
                }
            }
        }

        guard var winner = best else { return nil }

        // --- Schritt 6: Pose bestimmen.
        var pose = PlacementSuggestion.Pose.standing
        if let seatTop = seatEdgeTop(
            rectangles.results ?? [],
            in: winner.rect
        ) {
            pose = .seated
            // Unterkante beibehalten, Höhe reduzieren — sitzend ist kürzer.
            let newHeight = winner.rect.height * 0.62
            winner.rect = CGRect(
                x: winner.rect.minX,
                y: winner.rect.maxY - newHeight,
                width: winner.rect.width,
                height: newHeight
            )
            _ = seatTop
        } else if isLeaningSurface(map, beside: winner.rect, horizonY: horizonY) {
            pose = .leaning
        }

        // --- Schritt 7: glätten.
        var rect = winner.rect
        if let previousRect {
            let jumped = abs(previousRect.midX - rect.midX) > 0.25
                || abs(previousRect.midY - rect.midY) > 0.25
            if !jumped {
                rect = CGRect(
                    x: previousRect.origin.x * 0.75 + rect.origin.x * 0.25,
                    y: previousRect.origin.y * 0.75 + rect.origin.y * 0.25,
                    width: previousRect.size.width * 0.75 + rect.size.width * 0.25,
                    height: previousRect.size.height * 0.75 + rect.size.height * 0.25
                )
            }
        }

        // --- Schritt 8: Confidence.
        var confidence = min(max(winner.score, 0), 1)
        if horizonY == nil { confidence *= 0.6 }
        if usedFallbackMap { confidence *= 0.85 }

        return PlacementSuggestion(
            rect: rect,
            pose: pose,
            confidence: confidence,
            poseSentence: sentence(for: pose)
        )
    }

    // MARK: - Prompt-Bausteine

    static func sentence(for pose: PlacementSuggestion.Pose) -> String {
        switch pose {
        case .standing:
            return "standing upright at ease, weight settled on one hip, both feet flat on the ground, shoulders relaxed"
        case .seated:
            return "seated naturally on the surface behind her, knees together and angled slightly away from the lens, back straight"
        case .leaning:
            return "leaning one shoulder lightly against the flat surface beside her, one knee bent, arms relaxed"
        }
    }

    // MARK: - Bildaufbereitung

    private static func downscaled(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        aspect: CGFloat?
    ) -> CIImage? {
        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        if let aspect, aspect > 0 {
            image = centerCropped(image, toAspect: aspect)
        }
        let longEdge = max(image.extent.width, image.extent.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1, 256 / longEdge)
        guard scale < 1 else { return image }

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        return filter.outputImage ?? image
    }

    /// Derselbe mittige Zuschnitt, den die Vorschau und der spätere Export
    /// benutzen. Der Ursprung wird auf (0,0) zurückgeschoben, damit alle
    /// folgenden Schritte wieder von einem Bild ab null ausgehen.
    private static func centerCropped(_ image: CIImage, toAspect aspect: CGFloat) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let current = extent.width / extent.height
        var crop = extent
        if current > aspect {
            let width = extent.height * aspect
            crop = CGRect(x: extent.midX - width / 2, y: extent.minY,
                          width: width, height: extent.height)
        } else if current < aspect {
            let height = extent.width / aspect
            crop = CGRect(x: extent.minX, y: extent.midY - height / 2,
                          width: extent.width, height: height)
        }
        return image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }

    // MARK: - Saliency

    /// Zeilen von OBEN nach unten, damit die Matrix dasselbe Koordinatensystem
    /// benutzt wie die zurückgegebene Box.
    private static func saliencyMatrix(_ observation: VNSaliencyImageObservation?) -> [[Float]] {
        guard let buffer = observation?.pixelBuffer else { return [] }
        // Wir lesen die Karte als rohe Floats. Liefert Vision je ein anderes
        // Format, wäre das eine Fehlinterpretation fremden Speichers.
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float else {
            return []
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let stride = CVPixelBufferGetBytesPerRow(buffer)

        var rows = [[Float]](repeating: [Float](repeating: 0, count: width), count: height)
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude

        for y in 0..<height {
            let line = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                let value = line[x]
                rows[y][x] = value
                minimum = Swift.min(minimum, value)
                maximum = Swift.max(maximum, value)
            }
        }

        // Auf 0…1 normalisieren. Bei flacher Karte alles auf 0.
        let span = maximum - minimum
        guard span > 0.0001 else {
            return [[Float]](repeating: [Float](repeating: 0, count: width), count: height)
        }
        for y in 0..<height {
            for x in 0..<width {
                rows[y][x] = (rows[y][x] - minimum) / span
            }
        }
        return rows
    }

    /// Ersatz für die Saliency, wenn Vision keine liefert.
    ///
    /// Zwei Beobachtungen reichen, um „hier ist schon etwas" von „hier ist
    /// Platz" zu trennen: eine Fläche ist belegt, wenn sie unruhig ist
    /// (Struktur, Muster, Kanten) oder wenn ihr Ton deutlich vom vorherrschenden
    /// Ton der Szene abweicht (eine dunkle Gestalt vor heller Wand). Der Median
    /// steht für den vorherrschenden Ton, weil ein Mittelwert schon von einer
    /// halb vollen Bildhälfte verzogen wird.
    private static func structureMatrix(_ gray: GrayImage) -> [[Float]] {
        let cell = 4
        let columns = gray.width / cell
        let rows = gray.height / cell
        guard columns > 0, rows > 0 else { return [] }

        var means = [[Float]](repeating: [Float](repeating: 0, count: columns), count: rows)
        var spreads = means

        for row in 0..<rows {
            for column in 0..<columns {
                var sum: Float = 0
                var sumOfSquares: Float = 0
                for y in (row * cell)..<((row + 1) * cell) {
                    for x in (column * cell)..<((column + 1) * cell) {
                        let value = Float(gray.pixels[y * gray.width + x]) / 255
                        sum += value
                        sumOfSquares += value * value
                    }
                }
                let count = Float(cell * cell)
                let mean = sum / count
                means[row][column] = mean
                spreads[row][column] = Swift.max(0, sumOfSquares / count - mean * mean).squareRoot()
            }
        }

        let median = means.flatMap { $0 }.sorted()[rows * columns / 2]

        var result = means
        for row in 0..<rows {
            for column in 0..<columns {
                let tone = Swift.min(1, abs(means[row][column] - median) * 3)
                let texture = Swift.min(1, spreads[row][column] * 4)
                result[row][column] = Swift.max(tone, texture)
            }
        }
        return result
    }

    /// Dicht gepackte Graustufen, Zeile 0 ist die OBERSTE Bildzeile.
    struct GrayImage {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    private static func grayscale(_ image: CIImage) -> GrayImage? {
        let extent = image.extent
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        guard width > 0, height > 0, !extent.isInfinite else { return nil }

        guard let cgImage = context.createCGImage(image, from: extent) else { return nil }

        // CoreGraphics bekommt seinen EIGENEN Puffer (`data: nil`) und bestimmt
        // die Zeilenlänge selbst.
        //
        // Vorher lag hier ein Swift-Array, in das der Kontext über einen rohen
        // Zeiger hineinzeichnete. Genau bei dieser Konstruktion schreibt eine
        // von CoreGraphics aufgerundete Zeilenlänge über das Array-Ende hinaus —
        // und der Schaden fällt nicht hier auf, sondern irgendwann später beim
        // Freigeben von völlig unbeteiligtem Speicher. So ist der Testlauf
        // abgestürzt: mit `abrt` im Abbau von `ContentView`.
        guard let bitmap = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let base = bitmap.data else { return nil }

        // Dicht zusammenkopieren, damit die Auswertung mit `width` rechnen kann
        // statt mit der Zeilenlänge des Kontexts.
        let stride = bitmap.bytesPerRow
        let source = base.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBufferPointer { destination in
            guard let target = destination.baseAddress else { return }
            for row in 0..<height {
                target.advanced(by: row * width)
                    .update(from: source.advanced(by: row * stride), count: width)
            }
        }
        return GrayImage(pixels: pixels, width: width, height: height)
    }

    /// Mittlere Auffälligkeit innerhalb einer normalisierten Box (Ursprung oben links).
    static func meanSaliency(_ map: [[Float]], in normalizedRect: CGRect) -> Double {
        guard !map.isEmpty, !map[0].isEmpty else { return 0.5 }
        let height = map.count
        let width = map[0].count

        let x0 = Swift.max(0, Int((normalizedRect.minX * CGFloat(width)).rounded(.down)))
        let x1 = Swift.min(width - 1, Int((normalizedRect.maxX * CGFloat(width)).rounded(.up)))
        let y0 = Swift.max(0, Int((normalizedRect.minY * CGFloat(height)).rounded(.down)))
        let y1 = Swift.min(height - 1, Int((normalizedRect.maxY * CGFloat(height)).rounded(.up)))
        guard x1 >= x0, y1 >= y0 else { return 0.5 }

        var total: Double = 0
        var count = 0
        for y in y0...y1 {
            for x in x0...x1 {
                total += Double(map[y][x])
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0.5
    }

    // MARK: - Horizont, Licht, Sitzkanten

    /// Höhe der Horizontlinie in der Bildmitte, Ursprung oben links.
    private static func horizonHeight(_ observation: VNHorizonObservation?) -> CGFloat? {
        guard let observation else { return nil }
        // Vision beschreibt den Horizont als Transformation. Die Mitte der
        // unteren Bildkante durch sie hindurch ergibt die Linienhöhe.
        let point = CGPoint(x: 0.5, y: 0.5).applying(observation.transform)
        let flipped = 1 - point.y            // Vision zaehlt von unten
        guard flipped.isFinite, flipped > 0, flipped < 1 else { return nil }
        return flipped
    }

    /// Mittlere Luminanz je Drittel-Spalte, links nach rechts.
    ///
    /// Gerechnet auf demselben Graustufen-Puffer wie die Ersatzkarte. Vorher
    /// lief das über `CIAreaAverage` und `render(toBitmap:)` in ein vier Byte
    /// grosses Swift-Array — CoreImage schreibt dabei eine ganze, aufgerundete
    /// Zeile und damit über das Array hinaus. Der Prozess stirbt daran nicht
    /// sofort, sondern irgendwann später beim Freigeben von fremdem Speicher.
    ///
    /// Auf dem Ausgangsstand fiel das nie auf, weil `analyse` vorher ausstieg:
    /// der gebündelte Vision-Aufruf warf, und diese Zeile wurde nie erreicht.
    private static func columnLuminance(_ gray: GrayImage) -> [Double] {
        guard gray.width >= 3, gray.height >= 1 else { return [] }

        let columnWidth = gray.width / 3
        guard columnWidth > 0 else { return [] }

        var result: [Double] = []
        for index in 0..<3 {
            let start = index * columnWidth
            let end = index == 2 ? gray.width : start + columnWidth
            var total = 0.0
            var count = 0
            for y in 0..<gray.height {
                let row = y * gray.width
                for x in start..<end {
                    total += Double(gray.pixels[row + x])
                    count += 1
                }
            }
            result.append(count > 0 ? total / Double(count) / 255 : 0)
        }
        return result
    }

    /// Schaut die Person ins Licht? Wahr, wenn eine Nachbarspalte heller ist
    /// als die eigene.
    private static func facesTheLight(cx: CGFloat, columns: [Double]) -> Bool {
        guard columns.count == 3 else { return false }
        let own = Swift.min(2, Swift.max(0, Int(cx * 3)))
        let left = own > 0 ? columns[own - 1] : -1
        let right = own < 2 ? columns[own + 1] : -1
        return Swift.max(left, right) > columns[own]
    }

    /// Oberkante einer waagerechten Fläche im unteren Drittel des Kandidaten,
    /// die mindestens 60 % seiner Breite überdeckt.
    private static func seatEdgeTop(
        _ observations: [VNRectangleObservation],
        in candidate: CGRect
    ) -> CGFloat? {
        let lowerThird = CGRect(
            x: candidate.minX,
            y: candidate.maxY - candidate.height / 3,
            width: candidate.width,
            height: candidate.height / 3
        )

        for observation in observations {
            let box = flip(observation.boundingBox)
            // „Annähernd waagerecht": Ober- und Unterkante gleich hoch.
            let topLeft = flipPoint(observation.topLeft)
            let topRight = flipPoint(observation.topRight)
            guard abs(topLeft.y - topRight.y) < 0.03 else { continue }

            let top = Swift.min(topLeft.y, topRight.y)
            guard top >= lowerThird.minY, top <= lowerThird.maxY else { continue }

            let overlap = Swift.min(box.maxX, candidate.maxX) - Swift.max(box.minX, candidate.minX)
            guard overlap >= candidate.width * 0.6 else { continue }
            return top
        }
        return nil
    }

    /// Ruhige, glatte Fläche direkt neben dem Kandidaten = Wand zum Anlehnen.
    private static func isLeaningSurface(
        _ map: [[Float]],
        beside candidate: CGRect,
        horizonY: CGFloat?
    ) -> Bool {
        // Kein Anlehnen, wenn der Horizont mitten durch die Box laeuft — dann
        // steht die Person im Freien, nicht an einer Wand.
        if let horizonY, horizonY > candidate.minY, horizonY < candidate.maxY { return false }

        // Eine ruhige Flaeche ist nur dann eine Wand, wenn ueberhaupt etwas im
        // Bild ist, wovon sie sich abhebt. In einer voellig leeren Szene waere
        // jede Stelle „ruhig" — dort steht die Person frei.
        guard meanSaliency(map, in: CGRect(x: 0, y: 0, width: 1, height: 1)) > 0.2 else { return false }

        let stripWidth: CGFloat = 0.12
        let left = CGRect(x: candidate.minX - stripWidth, y: candidate.minY,
                          width: stripWidth, height: candidate.height)
        let right = CGRect(x: candidate.maxX, y: candidate.minY,
                           width: stripWidth, height: candidate.height)

        for strip in [left, right] where strip.minX >= 0 && strip.maxX <= 1 {
            if meanSaliency(map, in: strip) < 0.15 { return true }
        }
        return false
    }

    // MARK: - Geometrie

    /// Vision rechnet von UNTEN links, die App von OBEN links.
    private static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func flipPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: 1 - point.y)
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let overlap = Double(intersection.width * intersection.height)
        let union = Double(a.width * a.height + b.width * b.height) - overlap
        return union > 0 ? overlap / union : 0
    }
}
