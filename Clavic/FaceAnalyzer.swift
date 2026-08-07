//
//  FaceAnalyzer.swift
//  Clavic
//
//  Gesichts-Werkzeuge — das, was Clavic bisher komplett fehlte.
//
//  Gegenstück zu `BodyAnalyzer`, nur mit `VNDetectFaceLandmarksRequest` statt
//  der Körperhaltung. Vision liefert dabei 76 Punkte, aufgeteilt in genau die
//  Regionen, aus denen Editoren wie FaceLab ihre Regler bauen:
//
//      faceContour · leftEye · rightEye · leftEyebrow · rightEyebrow
//      nose · noseCrest · medianLine · outerLips · innerLips
//      leftPupil · rightPupil
//
//  WICHTIG fürs Verständnis der Kosten: das läuft komplett auf dem Gerät, in
//  Echtzeit, ohne Server und ohne Credits. Es wird nichts neu generiert, das
//  echte Foto wird nur verformt — deshalb bleibt die Person erkennbar, statt
//  wie bei einem Bildmodell durch eine Neuzeichnung ersetzt zu werden.
//

import CoreImage
import UIKit
import Vision

/// Die Gesichtsstellen. Reihenfolge wie in den gängigen Editoren: erst die
/// Form des Gesichts, dann die einzelnen Züge.
nonisolated enum FacePart: String, CaseIterable, Identifiable {
    case faceWidth, jawline, cheekbones, forehead, chin
    case eyes, eyebrows, nose, lips, smile

    var id: String { rawValue }

    /// Was im Studio-Menü sichtbar ist — der Rest bleibt im Engine für Alt-Edits.
    static let studioParts: [FacePart] = [
        .faceWidth, .jawline, .eyes, .nose, .lips,
    ]

    var label: String {
        switch self {
        case .faceWidth:  return "Face"
        case .jawline:    return "Jawline"
        case .cheekbones: return "Cheeks"
        case .forehead:   return "Forehead"
        case .chin:       return "Chin"
        case .eyes:       return "Eyes"
        case .eyebrows:   return "Brows"
        case .nose:       return "Nose"
        case .lips:       return "Lips"
        case .smile:      return "Smile"
        }
    }

    var icon: String {
        switch self {
        case .faceWidth:  return "face.smiling"
        case .jawline:    return "triangle"
        case .cheekbones: return "circle.hexagonpath"
        case .forehead:   return "rectangle.portrait.topthird.inset.filled"
        case .chin:       return "arrowtriangle.down"
        case .eyes:       return "eye"
        case .eyebrows:   return "eyebrow"
        case .nose:       return "nose"
        case .lips:       return "mouth"
        case .smile:      return "face.smiling.inverse"
        }
    }

    /// Fast alles ist ein Breiter/Schmaler; nur die Stirn wird gestreckt.
    var mode: WarpMode {
        switch self {
        // Die Stirn darf NICHT den linearen Ganzkörper-Filter benutzen: dessen
        // Wirkung läuft entlang einer kompletten waagerechten Linie und zieht
        // dadurch Haare, Ohren und Kleidung mit. Die lokale Variante bleibt in
        // der analysierten Stirnellipse und blendet an deren Rand weich aus.
        case .forehead: return .localStretch
        default:        return .widen
        }
    }

    /// Faustwerte für ein frontales Porträt, falls kein Gesicht erkannt wird.
    static let defaultZones: [FacePart: BodyZone] = [
        .faceWidth:  BodyZone(center: CGPoint(x: 0.50, y: 0.45), radiusX: 0.26, radiusY: 0.30),
        .jawline:    BodyZone(center: CGPoint(x: 0.50, y: 0.62), radiusX: 0.22, radiusY: 0.12),
        .cheekbones: BodyZone(center: CGPoint(x: 0.50, y: 0.45), radiusX: 0.24, radiusY: 0.10),
        .forehead:   BodyZone(center: CGPoint(x: 0.50, y: 0.26), radiusX: 0.20, radiusY: 0.09),
        .chin:       BodyZone(center: CGPoint(x: 0.50, y: 0.70), radiusX: 0.10, radiusY: 0.07),
        .eyes:       BodyZone(center: CGPoint(x: 0.50, y: 0.40), radiusX: 0.20, radiusY: 0.05),
        .eyebrows:   BodyZone(center: CGPoint(x: 0.50, y: 0.35), radiusX: 0.20, radiusY: 0.04),
        .nose:       BodyZone(center: CGPoint(x: 0.50, y: 0.50), radiusX: 0.08, radiusY: 0.07),
        .lips:       BodyZone(center: CGPoint(x: 0.50, y: 0.61), radiusX: 0.10, radiusY: 0.05),
        .smile:      BodyZone(center: CGPoint(x: 0.50, y: 0.61), radiusX: 0.13, radiusY: 0.05),
    ]
}

nonisolated struct FaceAnalysis: Equatable {
    var hasFace: Bool
    var zones: [FacePart: BodyZone]

    static func fallback() -> FaceAnalysis {
        FaceAnalysis(hasFace: false, zones: FacePart.defaultZones)
    }

    func zone(_ part: FacePart) -> BodyZone {
        zones[part] ?? FacePart.defaultZones[part]!
    }
}

/// Opt-out aus der projektweiten MainActor-Standardisolation: Vision fuehrt die
/// Landmark-Anfragen synchron aus, deshalb muss der umgebende async-Worker auf
/// dem generischen Executor laufen statt die SwiftUI-Interaktion zu blockieren.
nonisolated enum FaceAnalyzer {

    static func analyze(_ image: UIImage) async -> FaceAnalysis {
        // Dieselbe kanonische `.up`-Pixelflaeche wie BodyAnalyzer und die
        // Render-Engine. Dadurch braucht der Hintergrund-Worker weder eine
        // MainActor-isolierte UIImage-Extension noch EXIF-Sonderfaelle.
        let canonical = PhotoEditEngine.normalizedForEditing(image)
        guard let cg = canonical.cgImage else { return .fallback() }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        let request = VNDetectFaceLandmarksRequest()
        // 76 Punkte statt der voreingestellten 65: nur damit sind die
        // Augenbrauen und die Lippenkontur fein genug für eigene Regler.
        request.constellation = .constellation76Points

        let landmarkSucceeded = (try? handler.perform([request])) != nil
        let landmarkFace = request.results?.max {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        }

        // Manche Simulatoren und ältere Geräte können das Landmark-Modell
        // nicht laden, obwohl der deutlich leichtere Gesichtsdetektor klappt.
        // Dann NICHT auf feste Bildkoordinaten zurückfallen: Das erkannte
        // Gesichtsrechteck reicht für echte, fotobezogene Zonen und einen
        // korrekten Auto-Zoom. Auf unterstützten Geräten bleiben die feineren
        // 76 Landmarken der bevorzugte Weg.
        guard landmarkSucceeded, let face = landmarkFace else {
            let rectangleHandler = VNImageRequestHandler(
                cgImage: cg,
                orientation: .up,
                options: [:]
            )
            let rectangles = VNDetectFaceRectanglesRequest()
            guard (try? rectangleHandler.perform([rectangles])) != nil,
                  let box = rectangles.results?.max(by: {
                    $0.boundingBox.width * $0.boundingBox.height
                        < $1.boundingBox.width * $1.boundingBox.height
                  })?.boundingBox else {
                return .fallback()
            }
            return analysis(fromFaceBox: box)
        }
        guard let marks = face.landmarks else {
            return analysis(fromFaceBox: face.boundingBox)
        }

        // Vision liefert Landmarken RELATIV ZUM GESICHTSRECHTECK (0…1 darin),
        // nicht zum Bild. Ohne diese Umrechnung säße jede Zone falsch — der
        // häufigste Fehler bei Gesichts-Werkzeugen.
        let box = face.boundingBox   // Ursprung unten links, normiert aufs Bild
        func toImage(_ p: CGPoint) -> CGPoint {
            CGPoint(x: box.origin.x + p.x * box.width,
                    y: 1 - (box.origin.y + p.y * box.height))   // y auf oben-links drehen
        }
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            (region?.normalizedPoints ?? []).map(toImage)
        }
        func bounds(_ pts: [CGPoint]) -> (center: CGPoint, rx: CGFloat, ry: CGFloat)? {
            guard !pts.isEmpty else { return nil }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            return (CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
                    max((maxX - minX) / 2, 0.01),
                    max((maxY - minY) / 2, 0.01))
        }

        let contour = points(marks.faceContour)
        let leftEye = points(marks.leftEye), rightEye = points(marks.rightEye)
        let leftBrow = points(marks.leftEyebrow), rightBrow = points(marks.rightEyebrow)
        let nose = points(marks.nose)
        let outer = points(marks.outerLips)

        // Immer mit Zonen relativ zum tatsächlich gefundenen Gesicht starten.
        // Fehlt z. B. wegen Haaren eine Augenbraue, darf die Stirn nicht auf
        // eine feste globale Bildposition springen. Verfügbare Landmarken
        // überschreiben diese zweite, gröbere Erkennungsstufe anschließend.
        var zones = analysis(fromFaceBox: box).zones
        func put(_ part: FacePart, _ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) {
            zones[part] = BodyZone(center: c, radiusX: Double(max(rx, 0.01)), radiusY: Double(max(ry, 0.01)))
        }

        // Gesicht als Ganzes: das Rechteck von Vision, leicht großzügiger.
        let faceCenter = CGPoint(x: box.midX, y: 1 - box.midY)
        put(.faceWidth, faceCenter, box.width * 0.60, box.height * 0.58)

        if let c = bounds(contour) {
            // Die Kontur läuft von Ohr zu Ohr über das Kinn. Die Kieferlinie ist
            // deren untere Hälfte, die Wangenknochen die obere.
            let lower = contour.filter { $0.y > c.center.y }
            let upper = contour.filter { $0.y <= c.center.y }
            if let l = bounds(lower) { put(.jawline, l.center, l.rx * 0.95, l.ry * 0.9) }
            if let u = bounds(upper) { put(.cheekbones, u.center, u.rx * 0.95, u.ry * 0.8) }
            if let chinPt = contour.max(by: { $0.y < $1.y }) {
                put(.chin, chinPt, c.rx * 0.34, c.ry * 0.22)
            }
        }

        // Stirn: zwischen Augenbrauen und Oberkante des Gesichtsrechtecks.
        if let brows = bounds(leftBrow + rightBrow) {
            let top = 1 - box.maxY
            let span = abs(brows.center.y - top)
            // Die Stirn liegt im UNTEREN Teil zwischen Augenbrauen und
            // Oberkante des Gesichtsrechtecks. Nimmt man die Mitte, greift der
            // Regler in den Haaransatz — gemessen an einem Testfoto zog er die
            // Frisur nach oben statt die Stirn zu ändern. 35 % statt 50 %, und
            // ein knapperer Radius halten ihn auf der Haut.
            put(.forehead, CGPoint(x: faceCenter.x, y: brows.center.y - span * 0.35),
                box.width * 0.34, max(span * 0.26, 0.015))
            put(.eyebrows, brows.center, brows.rx * 1.05, brows.ry * 1.6)
        }

        if let eyes = bounds(leftEye + rightEye) {
            put(.eyes, eyes.center, eyes.rx * 1.05, eyes.ry * 2.0)
        }
        if let n = bounds(nose) {
            put(.nose, n.center, n.rx * 1.1, n.ry * 1.0)
        }
        if let lips = bounds(outer) {
            put(.lips, lips.center, lips.rx * 1.05, lips.ry * 1.5)
            // „Smile" wirkt breiter als die Lippen selbst — die Mundwinkel
            // sollen mitgehen, sonst sieht es aufgesetzt aus.
            put(.smile, lips.center, lips.rx * 1.5, lips.ry * 1.2)
        }

        return FaceAnalysis(hasFace: !zones.isEmpty,
                            zones: zones.isEmpty ? FacePart.defaultZones : zones)
    }

    /// Grobe, aber weiterhin bildbezogene Zonen aus dem Gesichtsrechteck.
    /// Das ist die belastbare zweite Stufe, wenn einzelne Landmarken auf dem
    /// Gerät nicht verfügbar sind. Alle Koordinaten sind Proportionen des von
    /// Vision gefundenen Gesichts, nicht pauschale Positionen im ganzen Foto.
    private static func analysis(fromFaceBox box: CGRect) -> FaceAnalysis {
        let top = 1 - box.maxY
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: box.minX + box.width * x,
                    y: top + box.height * y)
        }
        func zone(_ x: CGFloat, _ y: CGFloat,
                  _ radiusX: CGFloat, _ radiusY: CGFloat) -> BodyZone {
            BodyZone(center: point(x, y),
                     radiusX: Double(max(box.width * radiusX, 0.01)),
                     radiusY: Double(max(box.height * radiusY, 0.01)))
        }

        return FaceAnalysis(hasFace: true, zones: [
            .faceWidth:  zone(0.50, 0.50, 0.60, 0.58),
            .jawline:    zone(0.50, 0.72, 0.45, 0.16),
            .cheekbones: zone(0.50, 0.48, 0.46, 0.13),
            .forehead:   zone(0.50, 0.23, 0.34, 0.10),
            .chin:       zone(0.50, 0.86, 0.20, 0.10),
            .eyes:       zone(0.50, 0.38, 0.38, 0.08),
            .eyebrows:   zone(0.50, 0.29, 0.38, 0.07),
            .nose:       zone(0.50, 0.53, 0.16, 0.14),
            .lips:       zone(0.50, 0.70, 0.22, 0.10),
            .smile:      zone(0.50, 0.70, 0.28, 0.10),
        ])
    }
}
