//
//  BodyAnalyzer.swift
//  Clavic
//
//  Analysiert ein eingefügtes Foto, BEVOR bearbeitet wird — so wie EPIK es
//  macht: die App weiß hinterher, wo der Körper ist, und die Regler treffen
//  dadurch die richtige Zone, statt dass der Nutzer einen Kreis suchen muss.
//
//  Mehrstufige Vision-Analyse, komplett auf dem Gerät und ohne Upload:
//
//  1. `VNDetectHumanBodyPoseRequest` liefert 15 Gelenke (Schultern, Ellbogen,
//     Handgelenke, Hüften, Knie, Knöchel, Hals, Nase). Daraus werden die
//     anatomischen Zonen abgeleitet — die Taille liegt z. B. nicht an einer
//     festen Bildposition, sondern zwischen Schulter- und Hüftlinie.
//  2. `VNGeneratePersonInstanceMaskRequest` trennt einzelne Menschen und liefert
//     fuer die ausgewaehlte Hauptperson eine Maske in Bildaufloesung.
//  3. Falls das Instanzmodell nicht verfuegbar ist, liefert
//     `VNGeneratePersonSegmentationRequest` mit `.accurate` die lokale
//     Portrait-Matting-Maske. Deren Bounding Box ersetzt globale Schaetzzonen.
//
//  Gibt es keine erkennbare Person, werden Koerper-Warps in der Render-Engine
//  nicht angewendet. So kann eine Standardzone nie unbemerkt die Wand treffen.
//

import CoreImage
import UIKit
import Vision

/// Eine anatomische Zone in relativen Bildkoordinaten (0…1, Ursprung oben links).
nonisolated struct BodyZone: Equatable {
    var center: CGPoint
    /// Halbe Breite bzw. Höhe der Wirkfläche, ebenfalls relativ.
    var radiusX: Double
    var radiusY: Double
}

/// Ergebnis der Analyse eines Fotos.
nonisolated struct BodyAnalysis: Equatable {
    var hasPerson: Bool
    var zones: [BodyPart: BodyZone]
    /// Personen-Maske als CIImage (weiß = Person). Nil, wenn nicht ermittelbar.
    var mask: CIImage?

    static func fallback() -> BodyAnalysis {
        BodyAnalysis(hasPerson: false, zones: BodyPart.defaultZones, mask: nil)
    }

    func zone(_ part: BodyPart) -> BodyZone {
        zones[part] ?? BodyPart.defaultZones[part]!
    }

    static func == (a: BodyAnalysis, b: BodyAnalysis) -> Bool {
        a.hasPerson == b.hasPerson && a.zones == b.zones
    }
}

/// Was ein Regler mit seiner Zone macht. Nicht jede Körperstelle wird gleich
/// verändert: die Taille wird schmaler, das Bein LÄNGER, die Hüfte wandert
/// nach OBEN. Ohne diese Unterscheidung fühlen sich alle Regler gleich an.
nonisolated enum WarpMode {
    case widen      // breiter / schmaler (Standard)
    case stretch    // in der Höhe strecken / stauchen
    case lift       // nach oben / unten schieben
    case localStretch // nur innerhalb einer weichen Ellipse vertikal skalieren
}

/// Die Körperstellen. Satz und Reihenfolge sind aus EPIKs Body-Werkzeug
/// übernommen — abgelesen aus dem Bildschirmvideo `epik.MP4` (31.07.2026,
/// 103 s), Werkzeugleiste bei Sekunde 33–101 in Originalauflösung.
/// Reihenfolge dort: One-touch │ Head, All body, Length, Legs, Hips, Hip lift,
/// Waist, Belly, Back, Thickness, Length, Neck, Arms, Chest, 90 degrees,
/// Shoulders.
///
/// EINE ABWEICHUNG: EPIK hat ZWEI Einträge, die beide „Length" heißen — der
/// vierte meint die Beine, der zwölfte den Rumpf (im Video nur am Icon
/// unterscheidbar: gleiches Rumpf-Symbol, einmal mit waagerechtem Pfeil für
/// „Thickness", einmal mit senkrechtem). In einer Leiste, die man seitlich
/// scrollt, sind zwei gleich benannte Knöpfe eine Falle. Der zweite heißt
/// hier deshalb „Torso".
nonisolated enum BodyPart: String, CaseIterable, Identifiable {
    case head, allBody, length, legs, hips, hipLift, waist, belly
    case back, thickness, torso, neck, arms, chest, tilt, shoulders

    var id: String { rawValue }

    /// Schlankes Studio-Menü — One-touch nutzt weiter die Defaults darunter.
    static let studioParts: [BodyPart] = [
        .waist, .belly, .hips, .legs, .shoulders,
    ]

    var label: String {
        switch self {
        case .head: return "Head"
        case .allBody: return "All body"
        case .length: return "Length"
        case .legs: return "Legs"
        case .hips: return "Hips"
        case .hipLift: return "Hip lift"
        case .waist: return "Waist"
        case .belly: return "Belly"
        case .back: return "Back"
        case .thickness: return "Thickness"
        case .torso: return "Torso"
        case .neck: return "Neck"
        case .arms: return "Arms"
        case .chest: return "Chest"
        case .tilt: return "90 degrees"
        case .shoulders: return "Shoulders"
        }
    }

    var icon: String {
        switch self {
        case .head: return "circle.dashed"
        case .allBody: return "figure.stand"
        case .length: return "arrow.up.and.down"
        case .legs: return "figure.walk"
        case .hips: return "oval.portrait"
        case .hipLift: return "arrow.up.to.line"
        case .waist: return "figure.core.training"
        case .belly: return "circle.lefthalf.filled"
        case .back: return "figure.stand.line.dotted.figure.stand"
        case .thickness: return "arrow.left.and.right"
        case .torso: return "rectangle.portrait.arrowtriangle.2.outward"
        case .neck: return "person.bust"
        case .arms: return "figure.arms.open"
        case .chest: return "heart"
        case .tilt: return "rotate.3d"
        case .shoulders: return "figure.american.football"
        }
    }

    /// Was „One-touch" auf diese Zone legt. BEWUSST KLEIN (max. 0,18): der
    /// Ein-Knopf-Vorschlag soll wie ein guter Schnappschuss aussehen, nicht wie
    /// eine Karikatur. Kopf, Hals und „90 degrees" bleiben unangetastet —
    /// dort fällt jede automatische Änderung sofort als Bearbeitung auf.
    var oneTouchDefault: Double {
        switch self {
        case .waist:  return -0.18
        case .belly:  return -0.14
        case .length: return  0.10
        case .legs:   return  0.08
        case .hips:   return  0.06
        default:      return  0
        }
    }

    /// Wie der Regler wirkt. Siehe `WarpMode`.
    var mode: WarpMode {
        switch self {
        case .length, .torso: return .stretch
        case .hipLift: return .lift
        default: return .widen
        }
    }

    /// Fallback, wenn keine Person erkannt wurde — grobe Faustwerte für eine
    /// stehende Person im Hochformat.
    static let defaultZones: [BodyPart: BodyZone] = [
        .head:      BodyZone(center: CGPoint(x: 0.50, y: 0.16), radiusX: 0.13, radiusY: 0.09),
        .neck:      BodyZone(center: CGPoint(x: 0.50, y: 0.25), radiusX: 0.09, radiusY: 0.05),
        .shoulders: BodyZone(center: CGPoint(x: 0.50, y: 0.30), radiusX: 0.24, radiusY: 0.07),
        .arms:      BodyZone(center: CGPoint(x: 0.50, y: 0.42), radiusX: 0.30, radiusY: 0.14),
        .chest:     BodyZone(center: CGPoint(x: 0.50, y: 0.38), radiusX: 0.20, radiusY: 0.09),
        .back:      BodyZone(center: CGPoint(x: 0.50, y: 0.42), radiusX: 0.21, radiusY: 0.12),
        .waist:     BodyZone(center: CGPoint(x: 0.50, y: 0.50), radiusX: 0.19, radiusY: 0.10),
        .belly:     BodyZone(center: CGPoint(x: 0.50, y: 0.55), radiusX: 0.16, radiusY: 0.08),
        .hips:      BodyZone(center: CGPoint(x: 0.50, y: 0.60), radiusX: 0.22, radiusY: 0.10),
        .hipLift:   BodyZone(center: CGPoint(x: 0.50, y: 0.60), radiusX: 0.22, radiusY: 0.12),
        .legs:      BodyZone(center: CGPoint(x: 0.50, y: 0.80), radiusX: 0.20, radiusY: 0.18),
        .thickness: BodyZone(center: CGPoint(x: 0.50, y: 0.45), radiusX: 0.24, radiusY: 0.20),
        .torso:     BodyZone(center: CGPoint(x: 0.50, y: 0.45), radiusX: 0.24, radiusY: 0.20),
        .allBody:   BodyZone(center: CGPoint(x: 0.50, y: 0.50), radiusX: 0.40, radiusY: 0.45),
        .length:    BodyZone(center: CGPoint(x: 0.50, y: 0.70), radiusX: 0.30, radiusY: 0.30),
        .tilt:      BodyZone(center: CGPoint(x: 0.50, y: 0.45), radiusX: 0.30, radiusY: 0.30),
    ]
}

/// Vision ist CPU/Neural-Engine-Arbeit und darf trotz der projektweiten
/// MainActor-Standardisolation niemals den UI-Executor belegen. Ein
/// `nonisolated` async-Aufruf laeuft gemaess Swift-Concurrency auf dem
/// generischen Executor; die bestehende Aufrufsignatur bleibt unveraendert.
nonisolated enum BodyAnalyzer {

    private struct MaskMetrics {
        let foregroundPixels: Int
        /// Normalisierte Bildkoordinaten mit Ursprung oben links.
        let boundingBox: CGRect
    }

    private struct InstanceSelection {
        let instances: IndexSet
        let lowResolutionMask: CVPixelBuffer
        let metrics: MaskMetrics
    }

    /// Ein Kontext nur fuer das Auslesen der kleinen Vision-Masken. Die
    /// eigentliche hochaufgeloeste Maske bleibt als CIImage auf GPU-Seite.
    private static let maskContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])

    /// Analysiert das Foto. Läuft im Hintergrund; das Ergebnis wird nur einmal
    /// pro eingefügtem Bild gebraucht.
    static func analyze(_ image: UIImage) async -> BodyAnalysis {
        // Ein einziger kanonischer Pixelraum beseitigt die sonst unvermeidbare
        // Mischung aus EXIF-Orientierung, UIImage-Punkten und CGImage-Pixeln.
        // Alle Vision-Anfragen laufen danach mit `.up`; ihre Masken passen ohne
        // Rotationsheuristik auf Vorschau und Render-Engine.
        let canonical = PhotoEditEngine.normalizedForEditing(image)
        guard let cg = canonical.cgImage else { return .fallback() }
        let targetExtent = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)

        var personMask: CIImage?
        var personBox: CGRect?

        // Stufe 1: einzelne Menschen statt einer gemeinsamen Silhouette. Das
        // verhindert, dass das Gesicht von Person A mit dem Koerper von Person B
        // kombiniert wird. `generateScaledMaskForImage` liefert die Maske bereits
        // in der Aufloesung des kanonischen Eingabebilds.
        let instanceHandler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        let instanceRequest = VNGeneratePersonInstanceMaskRequest()
        if (try? instanceHandler.perform([instanceRequest])) != nil,
           let observation = instanceRequest.results?.first,
           let selection = primaryInstance(in: observation) {
            let highResolution = try? observation.generateScaledMaskForImage(
                forInstances: selection.instances,
                from: instanceHandler
            )
            let chosenBuffer = highResolution ?? selection.lowResolutionMask
            personMask = maskImage(from: chosenBuffer, fittedTo: targetExtent)
            personBox = selection.metrics.boundingBox
        }

        // Stufe 2: auf Geraeten/Simulatoren ohne Instanzmodell bleibt Apples
        // genaueste Portrait-Matting-Stufe erhalten. Float statt 8 Bit bewahrt
        // weiche Haar- und Kleidungsraender. Eine leere Maske gilt nicht als
        // erkannte Person.
        if personMask == nil {
            let segmentationHandler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            let segmentation = VNGeneratePersonSegmentationRequest()
            segmentation.qualityLevel = .accurate
            segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent32Float
            if (try? segmentationHandler.perform([segmentation])) != nil,
               let buffer = segmentation.results?.first?.pixelBuffer,
               let metrics = maskMetrics(in: buffer),
               metrics.foregroundPixels > 0 {
                personMask = maskImage(from: buffer, fittedTo: targetExtent)
                personBox = metrics.boundingBox
            }
        }

        // Pose separat ausfuehren: ein nicht verfuegbares Pose-Modell darf die
        // bereits erfolgreiche Segmentierung nicht entwerten. Bei mehreren
        // Posen gewinnt die mit der groessten Ueberlappung zur ausgewaehlten
        // Personeninstanz.
        let poseHandler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        let poseRequest = VNDetectHumanBodyPoseRequest()
        try? poseHandler.perform([poseRequest])
        let observation = selectPose(from: poseRequest.results ?? [], matching: personBox)

        var zones = personBox.map(zones(fromPersonBoundingBox:)) ?? [:]
        if let observation {
            let aspect = CGFloat(cg.width) / CGFloat(max(cg.height, 1))
            // Gelenke sind fuer Taille, Schultern und Hueften genauer; die
            // maskenbezogenen Zonen bleiben als sichere Ergaenzung fuer
            // angeschnittene oder sitzende Personen bestehen.
            zones.merge(deriveZones(from: observation, aspect: aspect)) { _, poseZone in poseZone }
        }

        let hasPerson = personMask != nil || observation != nil
        guard hasPerson else { return .fallback() }
        return BodyAnalysis(
            hasPerson: true,
            zones: zones.isEmpty ? BodyPart.defaultZones : zones,
            mask: personMask
        )
    }

    /// Bildbezogene zweite Stufe, wenn Gelenke fehlen. Im Unterschied zu den
    /// globalen Default-Zonen bleiben alle Mittelpunkte und Radien innerhalb der
    /// tatsaechlich segmentierten Person.
    static func zones(fromPersonBoundingBox input: CGRect) -> [BodyPart: BodyZone] {
        let minX = max(0, min(1, input.minX))
        let minY = max(0, min(1, input.minY))
        let maxX = max(minX, min(1, input.maxX))
        let maxY = max(minY, min(1, input.maxY))
        let box = CGRect(x: minX, y: minY,
                         width: max(maxX - minX, 0.01),
                         height: max(maxY - minY, 0.01))

        func zone(_ x: CGFloat, _ y: CGFloat,
                  _ radiusX: CGFloat, _ radiusY: CGFloat) -> BodyZone {
            BodyZone(
                center: CGPoint(x: box.minX + box.width * x,
                                y: box.minY + box.height * y),
                radiusX: Double(max(box.width * radiusX, 0.01)),
                radiusY: Double(max(box.height * radiusY, 0.01))
            )
        }

        return [
            .head:      zone(0.50, 0.10, 0.22, 0.10),
            .neck:      zone(0.50, 0.20, 0.15, 0.055),
            .shoulders: zone(0.50, 0.27, 0.43, 0.075),
            .arms:      zone(0.50, 0.40, 0.49, 0.18),
            .chest:     zone(0.50, 0.34, 0.34, 0.105),
            .back:      zone(0.50, 0.40, 0.36, 0.15),
            .waist:     zone(0.50, 0.50, 0.30, 0.095),
            .belly:     zone(0.50, 0.55, 0.29, 0.085),
            .hips:      zone(0.50, 0.61, 0.36, 0.105),
            .hipLift:   zone(0.50, 0.61, 0.38, 0.12),
            .legs:      zone(0.50, 0.80, 0.34, 0.20),
            .thickness: zone(0.50, 0.43, 0.40, 0.22),
            .torso:     zone(0.50, 0.43, 0.40, 0.22),
            .allBody:   zone(0.50, 0.50, 0.50, 0.50),
            .length:    zone(0.50, 0.76, 0.40, 0.24),
            .tilt:      zone(0.50, 0.43, 0.44, 0.27),
        ]
    }

    private static func primaryInstance(
        in observation: VNInstanceMaskObservation
    ) -> InstanceSelection? {
        var best: InstanceSelection?
        for index in observation.allInstances {
            let instances = IndexSet(integer: index)
            guard let buffer = try? observation.generateMask(forInstances: instances),
                  let metrics = maskMetrics(in: buffer),
                  metrics.foregroundPixels > 0 else { continue }
            let candidate = InstanceSelection(
                instances: instances,
                lowResolutionMask: buffer,
                metrics: metrics
            )
            if best == nil || metrics.foregroundPixels > best!.metrics.foregroundPixels {
                best = candidate
            }
        }
        return best
    }

    /// Liest eine kleine binaere Vision-Maske in CI-Koordinaten aus. CI schreibt
    /// die erste Bitmap-Zeile am unteren Bildrand; fuer BodyZone wird die y-Achse
    /// deshalb explizit in den oben-links-Pixelraum gedreht.
    private static func maskMetrics(in buffer: CVPixelBuffer) -> MaskMetrics? {
        let image = CIImage(cvPixelBuffer: buffer)
        let width = max(Int(image.extent.width.rounded()), 1)
        let height = max(Int(image.extent.height.rounded()), 1)
        var pixels = [UInt8](repeating: 0, count: width * height)
        maskContext.render(
            image,
            toBitmap: &pixels,
            rowBytes: width,
            bounds: CGRect(x: image.extent.minX, y: image.extent.minY,
                           width: CGFloat(width), height: CGFloat(height)),
            format: .L8,
            colorSpace: nil
        )

        var count = 0
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[row + x] >= 32 {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        // Einzelne Modellpixel sind kein belastbarer Mensch.
        guard count >= max(8, width * height / 2000), maxX >= minX, maxY >= minY else {
            return nil
        }
        let x = CGFloat(minX) / CGFloat(width)
        let top = 1 - CGFloat(maxY + 1) / CGFloat(height)
        let boxWidth = CGFloat(maxX - minX + 1) / CGFloat(width)
        let boxHeight = CGFloat(maxY - minY + 1) / CGFloat(height)
        return MaskMetrics(
            foregroundPixels: count,
            boundingBox: CGRect(x: x, y: top, width: boxWidth, height: boxHeight)
        )
    }

    private static func maskImage(from buffer: CVPixelBuffer,
                                  fittedTo extent: CGRect) -> CIImage {
        CIImage(cvPixelBuffer: buffer).resizedMask(to: extent)
    }

    private static func selectPose(
        from observations: [VNHumanBodyPoseObservation],
        matching personBox: CGRect?
    ) -> VNHumanBodyPoseObservation? {
        observations.max { lhs, rhs in
            poseScore(lhs, matching: personBox) < poseScore(rhs, matching: personBox)
        }
    }

    private static func poseScore(_ observation: VNHumanBodyPoseObservation,
                                  matching personBox: CGRect?) -> CGFloat {
        guard let recognized = try? observation.recognizedPoints(.all) else { return 0 }
        let points = recognized.values.filter { $0.confidence > 0.10 }
        guard !points.isEmpty else { return 0 }
        let confidence = points.reduce(CGFloat.zero) { $0 + CGFloat($1.confidence) }
            / CGFloat(points.count)
        guard let personBox else { return confidence }
        let inside = points.reduce(0) { partial, point in
            let p = CGPoint(x: point.location.x, y: 1 - point.location.y)
            return partial + (personBox.insetBy(dx: -0.03, dy: -0.03).contains(p) ? 1 : 0)
        }
        return CGFloat(inside) / CGFloat(points.count) * 4 + confidence
    }

    /// Leitet die Zonen aus den Gelenken ab. Vision rechnet mit Ursprung UNTEN
    /// links und normierten Koordinaten; die UI arbeitet oben links, deshalb
    /// wird y gespiegelt.
    private static func deriveZones(from o: VNHumanBodyPoseObservation, aspect: CGFloat) -> [BodyPart: BodyZone] {
        // Schwelle bewusst niedrig: bei einem gemessenen Testfoto lagen die
        // Hüftgelenke bei 0.14/0.13 — mit der naheliegenden 0.15 fiel die
        // ganze Erkennung auf Standardwerte zurück, obwohl die Person klar
        // erkannt war.
        func point(_ name: VNHumanBodyPoseObservation.JointName, _ minConfidence: Float = 0.10) -> CGPoint? {
            guard let p = try? o.recognizedPoint(name), p.confidence > minConfidence else { return nil }
            return CGPoint(x: p.location.x, y: 1 - p.location.y)   // → oben links
        }

        // NUR die Schultern sind Pflicht — sie werden am zuverlässigsten
        // erkannt. Fehlt die Hüfte (sitzende Person, angeschnittenes Bild),
        // wird sie aus der Körperproportion geschätzt, statt aufzugeben.
        guard let ls = point(.leftShoulder), let rs = point(.rightShoulder) else { return [:] }

        let shoulderMid = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let shoulderWidth = max(abs(ls.x - rs.x), 0.08)

        let hipMid: CGPoint
        let hipWidth: CGFloat
        if let lh = point(.leftHip), let rh = point(.rightHip) {
            hipMid = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
            hipWidth = max(abs(lh.x - rh.x), 0.07)
        } else {
            // Rumpfhöhe ≈ 1,5 × Schulterbreite. x und y sind unterschiedlich
            // skaliert (Bild ist nicht quadratisch), deshalb über das
            // Seitenverhältnis umrechnen.
            let torsoInY = shoulderWidth * 1.5 * aspect
            hipMid = CGPoint(x: shoulderMid.x, y: min(shoulderMid.y + torsoInY, 0.97))
            hipWidth = shoulderWidth * 0.92
        }
        let torsoHeight = max(abs(hipMid.y - shoulderMid.y), 0.10)

        var zones: [BodyPart: BodyZone] = [:]
        func z(_ part: BodyPart, _ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
            zones[part] = BodyZone(center: CGPoint(x: x, y: y),
                                   radiusX: Double(max(rx, 0.02)),
                                   radiusY: Double(max(ry, 0.02)))
        }

        // --- Kopf & Hals -----------------------------------------------------
        // Die Nase ist der zuverlässigste Kopfpunkt; fehlt sie (Rückenansicht),
        // wird der Kopf aus der Rumpfhöhe geschätzt statt aufzugeben.
        let headY = point(.nose)?.y ?? (shoulderMid.y - torsoHeight * 0.45)
        z(.head, shoulderMid.x, headY, shoulderWidth * 0.62, torsoHeight * 0.30)
        z(.neck, shoulderMid.x, (headY + shoulderMid.y) / 2,
          shoulderWidth * 0.30, abs(shoulderMid.y - headY) * 0.32)

        // --- Oberkörper ------------------------------------------------------
        z(.shoulders, shoulderMid.x, shoulderMid.y, shoulderWidth * 0.85, torsoHeight * 0.30)
        z(.chest, shoulderMid.x, shoulderMid.y + torsoHeight * 0.28,
          shoulderWidth * 0.70, torsoHeight * 0.28)
        // Arme liegen AUSSERHALB der Schulterbreite — deshalb ein deutlich
        // größerer x-Radius als bei den Schultern selbst.
        z(.arms, shoulderMid.x, shoulderMid.y + torsoHeight * 0.35,
          shoulderWidth * 1.35, torsoHeight * 0.50)
        // „Back" wirkt auf denselben Rumpf, aber tiefer und flacher — bei EPIK
        // ist es die Haltung, nicht die Breite.
        z(.back, shoulderMid.x, shoulderMid.y + torsoHeight * 0.40,
          max(shoulderWidth, hipWidth) * 0.78, torsoHeight * 0.42)

        // Taille: die schmalste Stelle liegt bei rund 60 % zwischen Schulter
        // und Hüfte — nicht mittig, das ist der häufigste Fehler.
        z(.waist, (shoulderMid.x + hipMid.x) / 2, shoulderMid.y + torsoHeight * 0.62,
          max(shoulderWidth, hipWidth) * 0.62, torsoHeight * 0.30)
        z(.belly, (shoulderMid.x + hipMid.x) / 2, shoulderMid.y + torsoHeight * 0.78,
          max(shoulderWidth, hipWidth) * 0.52, torsoHeight * 0.24)

        z(.hips, hipMid.x, hipMid.y, hipWidth * 0.95, torsoHeight * 0.30)
        z(.hipLift, hipMid.x, hipMid.y, hipWidth * 1.05, torsoHeight * 0.36)

        // Rumpf als Ganzes — „Thickness" (Breite) und „Torso" (Höhe) teilen
        // sich dieselbe Fläche, nur der Wirkmodus unterscheidet sie.
        let torsoMid = CGPoint(x: (shoulderMid.x + hipMid.x) / 2,
                               y: (shoulderMid.y + hipMid.y) / 2)
        z(.thickness, torsoMid.x, torsoMid.y, max(shoulderWidth, hipWidth) * 0.95, torsoHeight * 0.62)
        z(.torso, torsoMid.x, torsoMid.y, max(shoulderWidth, hipWidth) * 0.95, torsoHeight * 0.62)
        z(.tilt, torsoMid.x, torsoMid.y, max(shoulderWidth, hipWidth) * 1.2, torsoHeight * 0.9)

        // --- Beine -----------------------------------------------------------
        // Nur rechnen, wenn Knie bzw. Knöchel wirklich im Bild sind — sonst
        // würde bei einem Halbkörperfoto ins Leere gerechnet.
        let knee = midpoint(point(.leftKnee), point(.rightKnee))
        let ankle = midpoint(point(.leftAnkle), point(.rightAnkle))
        let legBottom = ankle?.y ?? knee.map { $0.y + torsoHeight * 0.8 } ?? min(hipMid.y + torsoHeight * 1.4, 0.99)
        z(.legs, hipMid.x, (hipMid.y + legBottom) / 2,
          hipWidth * 0.85, abs(legBottom - hipMid.y) * 0.55)
        // „Length" streckt ab der Hüfte abwärts — die Zone beginnt dort und
        // reicht bis zum Bildrand, damit die Füße mitgehen.
        z(.length, hipMid.x, (hipMid.y + 1.0) / 2, hipWidth * 1.3, abs(1.0 - hipMid.y) / 2)
        // „All body" umfasst alles vom Kopf bis zum tiefsten erkannten Punkt.
        z(.allBody, shoulderMid.x, (headY + legBottom) / 2,
          max(shoulderWidth, hipWidth) * 1.4, abs(legBottom - headY) * 0.55)

        return zones
    }

    private static func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
        switch (a, b) {
        case let (x?, y?): return CGPoint(x: (x.x + y.x) / 2, y: (x.y + y.y) / 2)
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return nil
        }
    }
}
