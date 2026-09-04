//
//  DirectorReadMarks.swift
//  Clavic
//
//  WO der Director hinzeigt — und warum genau dort.
//
//  Auf das fertig gelesene Foto legen sich Anmerkungen wie auf einen Abzug,
//  den jemand mit dem Stift durchgegangen ist. Damit das nicht Dekoration ist,
//  DUERFEN DIE STELLEN NICHT ERFUNDEN SEIN: sie werden aus dem Bild selbst
//  gemessen.
//
//  GEMESSEN WIRD AUF EINEM 48x48-GRAUBILD.
//  Neun Felder, je Feld Mittelwert und Streuung der Helligkeit. Daraus:
//    • Motiv        = das Feld mit der groessten Streuung (dort ist Zeichnung),
//                     oder das Gesicht, falls Vision es findet.
//    • Tote Flaeche = das ruhigste Feld ausserhalb des Motivs.
//    • Rand         = die ruhigste der vier Randbahnen.
//  Der TEXT an der Stelle kommt aus der Helligkeit des Feldes: ausgefressen,
//  abgesoffen oder flach. Er behauptet nichts, was nicht gemessen wurde.
//
//  KEIN MODELL, KEINE ML-ANFRAGE fuer den Hauptweg — nur CoreGraphics.
//  Grund: im Simulator scheitern alle modellgestuetzten Vision-Anfragen mit
//  „Failed to create espresso context". Ein Aufbau, der nur auf Geraeten
//  funktioniert, ist im Entwurf nicht pruefbar. Die Gesichtserkennung laeuft
//  deshalb als EINZELNE, gekapselte Anfrage obendrauf: klappt sie, sitzt der
//  Kringel genauer; klappt sie nicht, sitzt er trotzdem richtig.
//
//  Der Graupuffer entsteht mit `data: nil` — CoreGraphics bestimmt die
//  Zeilenlaenge selbst. Zeichnet man stattdessen in ein Swift-Array, schreibt
//  eine aufgerundete Zeilenlaenge darueber hinaus; der Schaden faellt erst
//  spaeter beim Freigeben voellig unbeteiligten Speichers auf. Genau daran ist
//  im `PlacementSuggester` ein Testlauf mit `abrt` gestorben.
//

import UIKit
import Vision

/// Eine Anmerkung auf dem Abzug.
struct ReadMark: Identifiable, Equatable {
    enum Kind {
        /// Ein Kringel um das Motiv.
        case ring
        /// Eine Wellenlinie durch eine tote Flaeche.
        case wave
        /// Eine Ecke, die weg koennte.
        case bracket
    }

    let id: Int
    let kind: Kind
    /// Im Einheitsrechteck des Bildes, y von OBEN — wie SwiftUI zeichnet.
    let area: CGRect
    /// Zwei, drei Woerter in Kleinschreibung. Handschrift, kein Etikett.
    let label: String

    /// Ein Lob, kein Tadel.
    ///
    /// Ein roter Kringel mit „this is the shot" daneben ist ein Widerspruch:
    /// die Farbe sagt Fehler, der Text sagt Treffer. Deshalb weiss die Marke
    /// selbst, was sie ist, und die Tinte richtet sich danach.
    var isPraise: Bool { label == "this is the shot" }

    /// Was er daran machen wuerde — drei bis fuenf Woerter.
    ///
    /// Getrennt von `request`: dort steht ein Satz, den man ABSCHICKT, hier
    /// eine Zeile, die man LIEST. Wer eine Liste ueberfliegt, will keinen
    /// vollstaendigen Auftrag lesen, sondern wissen, was passiert.
    var change: String {
        switch label {
        case "light's blown out": return "Pull the light back"
        case "you're in the dark": return "Lift the shadows"
        case "light falls flat":   return "Give the light shape"
        case "this is the shot":   return "Keep your face as it is"
        case "dead space":         return "Fill the empty half"
        case "nothing here":       return "Fix the black corner"
        case "crop this off":      return "Crop the edge off"
        default:                   return label
        }
    }

    /// Was man dazu sagen wuerde, wenn man den Director bittet, es zu
    /// beheben. Steht hier und nicht in der Leiste unten, damit Anmerkung und
    /// Auftrag NIE auseinanderlaufen: es ist ein Wortschatz, nicht zwei.
    var request: String {
        switch label {
        case "light's blown out": return "Tame that blown-out light"
        case "you're in the dark": return "Lift the shadows on me"
        case "light falls flat":   return "Give the light some shape"
        case "this is the shot":   return "Push what already works here"
        case "dead space":         return "Do something with the empty half"
        case "nothing here":       return "Fill that black corner"
        case "crop this off":      return "Crop in tighter on me"
        default:                   return label
        }
    }
}

enum DirectorReadMarks {

    /// Kantenlaenge des Messbildes. 48 reicht: gesucht sind Flaechen, keine
    /// Details, und ein groesserer Puffer kostet nur Zeit.
    private static let grid = 48
    /// Felder je Achse.
    private static let cells = 3

    static func marks(for image: UIImage) async -> [ReadMark] {
        guard let gray = grayscale(image, side: grid) else { return [] }

        var stats: [(mean: Double, deviation: Double)] = []
        for row in 0..<cells {
            for column in 0..<cells {
                stats.append(cellStats(gray, row: row, column: column))
            }
        }
        guard stats.count == cells * cells else { return [] }

        // Motiv: wo am meisten Zeichnung ist. Das Gesicht sticht das aus,
        // wenn Vision es findet.
        let busiest = stats.enumerated().max(by: { $0.element.deviation < $1.element.deviation })?.offset ?? 4
        let face = await faceBox(in: image)
        let subject = face ?? cellRect(busiest)
        let subjectCell = face.map { cellIndex(containing: $0.center) } ?? busiest

        var result: [ReadMark] = []
        result.append(ReadMark(id: 0, kind: .ring,
                               area: subject.expanded(by: face == nil ? 0 : 0.16),
                               label: lightLabel(stats[subjectCell])))

        // Tote Flaeche: das ruhigste Feld, das nicht das Motiv ist. Nur wenn
        // es wirklich ruhig ist — sonst behauptet der Strich etwas Falsches.
        let calm = stats.enumerated()
            .filter { $0.offset != subjectCell }
            .min(by: { $0.element.deviation < $1.element.deviation })
        if let calm, calm.element.deviation < 0.11 {
            result.append(ReadMark(id: 1, kind: .wave,
                                   area: cellRect(calm.offset),
                                   label: calm.element.mean < 0.22 ? "nothing here" : "dead space"))
        }

        // Rand: die ruhigste der vier Bahnen, und nur wenn sie deutlich ruhiger
        // ist als das Bild insgesamt.
        let overall = stats.map(\.deviation).reduce(0, +) / Double(stats.count)
        if let edge = quietestEdge(gray), edge.deviation < overall * 0.7 {
            result.append(ReadMark(id: 2, kind: .bracket,
                                   area: edge.area, label: "crop this off"))
        }

        return result
    }

    // MARK: - Was die Helligkeit ueber das Licht sagt

    private static func lightLabel(_ stat: (mean: Double, deviation: Double)) -> String {
        if stat.mean > 0.78 { return "light's blown out" }
        if stat.mean < 0.24 { return "you're in the dark" }
        if stat.deviation < 0.10 { return "light falls flat" }
        return "this is the shot"
    }

    // MARK: - Felder

    private static func cellRect(_ index: Int) -> CGRect {
        let size = 1.0 / CGFloat(cells)
        return CGRect(x: CGFloat(index % cells) * size,
                      y: CGFloat(index / cells) * size,
                      width: size, height: size)
    }

    private static func cellIndex(containing point: CGPoint) -> Int {
        let column = min(cells - 1, max(0, Int(point.x * CGFloat(cells))))
        let row = min(cells - 1, max(0, Int(point.y * CGFloat(cells))))
        return row * cells + column
    }

    private static func cellStats(_ gray: GrayBuffer, row: Int, column: Int)
        -> (mean: Double, deviation: Double) {
        let step = gray.side / cells
        let x0 = column * step, y0 = row * step
        let x1 = column == cells - 1 ? gray.side : x0 + step
        let y1 = row == cells - 1 ? gray.side : y0 + step

        var sum = 0.0, sumSquares = 0.0, count = 0.0
        for y in y0..<y1 {
            let offset = y * gray.side
            for x in x0..<x1 {
                let value = Double(gray.pixels[offset + x]) / 255
                sum += value
                sumSquares += value * value
                count += 1
            }
        }
        guard count > 0 else { return (0, 0) }
        let mean = sum / count
        return (mean, max(0, sumSquares / count - mean * mean).squareRoot())
    }

    /// Die ruhigste der vier Randbahnen, jeweils ein Sechstel breit.
    private static func quietestEdge(_ gray: GrayBuffer)
        -> (area: CGRect, deviation: Double)? {
        let band = max(1, gray.side / 6)
        let candidates: [(CGRect, Range<Int>, Range<Int>)] = [
            (CGRect(x: 0, y: 0, width: 1, height: 1.0 / 6), 0..<gray.side, 0..<band),
            (CGRect(x: 0, y: 5.0 / 6, width: 1, height: 1.0 / 6), 0..<gray.side, (gray.side - band)..<gray.side),
            (CGRect(x: 0, y: 0, width: 1.0 / 6, height: 1), 0..<band, 0..<gray.side),
            (CGRect(x: 5.0 / 6, y: 0, width: 1.0 / 6, height: 1), (gray.side - band)..<gray.side, 0..<gray.side)
        ]

        var best: (CGRect, Double)?
        for (area, xs, ys) in candidates {
            var sum = 0.0, sumSquares = 0.0, count = 0.0
            for y in ys {
                let offset = y * gray.side
                for x in xs {
                    let value = Double(gray.pixels[offset + x]) / 255
                    sum += value
                    sumSquares += value * value
                    count += 1
                }
            }
            guard count > 0 else { continue }
            let mean = sum / count
            let deviation = max(0, sumSquares / count - mean * mean).squareRoot()
            if best == nil || deviation < best!.1 { best = (area, deviation) }
        }
        guard let best else { return nil }
        return (best.0, best.1)
    }

    // MARK: - Gesicht (Zugabe, kein Fundament)

    /// EINE Anfrage, gekapselt. Nie mit anderen gebuendelt: ein Fehlschlag in
    /// `perform([...])` reisst alle uebrigen mit, und im Simulator schlaegt
    /// jede modellgestuetzte Anfrage fehl.
    private static func faceBox(in image: UIImage) async -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectFaceRectanglesRequest()
                do {
                    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                // Das groesste Gesicht — bei mehreren geht es um das vorderste.
                guard let box = (request.results ?? [])
                    .map(\.boundingBox)
                    .max(by: { $0.width * $0.height < $1.width * $1.height }) else {
                    continuation.resume(returning: nil)
                    return
                }
                // Vision zaehlt y von unten, SwiftUI von oben.
                continuation.resume(returning: CGRect(
                    x: box.minX, y: 1 - box.maxY,
                    width: box.width, height: box.height
                ))
            }
        }
    }

    // MARK: - Graupuffer

    struct GrayBuffer {
        let pixels: [UInt8]
        let side: Int
    }

    private static func grayscale(_ image: UIImage, side: Int) -> GrayBuffer? {
        guard let cg = image.cgImage, side > 0 else { return nil }
        // `data: nil` — der Puffer gehoert CoreGraphics, siehe Kopf der Datei.
        guard let bitmap = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        bitmap.interpolationQuality = .medium
        bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let base = bitmap.data else { return nil }

        // Dicht zusammenkopieren, damit die Auswertung mit `side` rechnen darf
        // statt mit der Zeilenlaenge des Kontexts.
        let stride = bitmap.bytesPerRow
        let source = base.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBufferPointer { destination in
            for y in 0..<side {
                for x in 0..<side {
                    destination[y * side + x] = source[y * stride + x]
                }
            }
        }
        return GrayBuffer(pixels: pixels, side: side)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    /// Anteilig groesser, in beiden Richtungen, im Einheitsrechteck gehalten.
    func expanded(by fraction: CGFloat) -> CGRect {
        let dx = width * fraction, dy = height * fraction
        return insetBy(dx: -dx, dy: -dy)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
