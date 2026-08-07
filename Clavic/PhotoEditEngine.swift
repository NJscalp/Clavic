//
//  PhotoEditEngine.swift
//  Clavic
//
//  Die Rechen-Schicht des Studio-Bildeditors. Bewusst KOMPLETT LOKAL über
//  Core Image — kein Server, keine Credits, kein Warten.
//
//  Warum lokal: der Nutzer soll beim Ziehen am Regler SOFORT sehen, wie sich
//  Taille, Brust, Bauch, Hautton oder Filter ändern. Mit einem Bildmodell auf
//  dem Server wäre jede Regler-Bewegung ein Netzwerk-Aufruf von mehreren
//  Sekunden und ein Credit — das wäre kein Live-Regler, sondern eine
//  Warteschlange. Formveränderungen und Farbe sind Geometrie bzw. Farbmathe,
//  beides kann das Gerät in Echtzeit.
//
//  HINTERGRUND-LOCK: die Körper-Regler sind radiusbegrenzte lokale
//  Verzerrungen (`CIBumpDistortion`). Alles außerhalb des Radius bleibt
//  Pixel für Pixel unverändert — der Hintergrund KANN also gar nicht
//  verziehen. Das ist keine Nachbearbeitung, sondern folgt aus der Bauweise.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Alle Regler eines Edits. Werte sind neutral bei 0 (bzw. 1 bei Skalen),
/// damit „nichts eingestellt" auch wirklich nichts verändert.
struct PhotoEdits: Equatable {
    // Licht & Farbe
    var exposure: Double = 0        // -1 … 1
    var highlights: Double = 0      // -1 … 1
    var shadows: Double = 0         // -1 … 1
    var contrast: Double = 0        // -1 … 1
    var saturation: Double = 0      // -1 … 1
    var warmth: Double = 0          // -1 … 1  (kalt … warm)
    var sharpen: Double = 0         //  0 … 1
    var vignette: Double = 0        //  0 … 1
    var fade: Double = 0            //  0 … 1
    var grain: Double = 0           //  0 … 1

    // Haut / Retusche. Alle Effekte bleiben in der erkannten Hautmaske.
    var skinTone: Double = 0        // -1 … 1  (heller … tiefer gebräunt)
    var smooth: Double = 0          //  0 … 1
    var evenSkin: Double = 0        //  0 … 1
    var redness: Double = 0         //  0 … 1
    var matte: Double = 0           //  0 … 1
    var glow: Double = 0            //  0 … 1

    // Make-up. Die Positionen stammen aus `FaceAnalysis`; ohne erkanntes
    // Gesicht bzw. Personen-/Hautmaske wird bewusst nichts angewendet.
    var foundation: Double = 0      //  0 … 1
    var blush: Double = 0           //  0 … 1
    var contour: Double = 0         //  0 … 1
    var lipColor: Double = 0        //  0 … 1
    var eyeBright: Double = 0       //  0 … 1
    var teethWhite: Double = 0      //  0 … 1

    // Haare: Preset und Deckkraft sind getrennt, damit ein gewähltes Preset
    // bei 0 weiterhin neutral ist.
    var hairTint: HairTintPreset = .none
    var hairTintIntensity: Double = 0 // 0 … 1

    // Körper: pro erkannter Zone eine Stärke, -1 (schmaler) … 1 (voller).
    // Die POSITION kommt aus der Bildanalyse (`BodyAnalysis`), nicht von Hand —
    // deshalb stehen hier nur noch die Werte, keine Mittelpunkte mehr.
    var body: [BodyPart: Double] = [:]
    /// Gesichts-Regler, analog zu `body`. Liegen lokal an, kosten nichts.
    var face: [FacePart: Double] = [:]
    /// „One-touch": EPIKs Ein-Knopf-Vorschlag. Legt auf alle Zonen eine dezente
    /// Standardkorrektur, die der Nutzer danach einzeln übersteuern kann.
    var oneTouch: Bool = false
    /// Hintergrund-Lock. Bei EPIK ein Schalter, der ÜBER dem Bild schwebt.
    /// An = nur die Person darf sich verformen (Personen-Maske), aus = die
    /// Verzerrung darf über die Silhouette hinauslaufen.
    var backgroundLock: Bool = true

    var filter: PhotoFilter = .none
    /// 1 bewahrt das bisherige Verhalten: ein gewählter Filter liegt zunächst
    /// mit voller Stärke an. 0 lässt ihn komplett ausfaden.
    var filterIntensity: Double = 1 // 0 … 1

    var isNeutral: Bool { self == PhotoEdits() }
    /// Wird eine Geometrie verändert? Nur dann lohnt die Masken-Mischung.
    var hasBodyChange: Bool {
        oneTouch
            || body.values.contains { Swift.abs($0) > 0.001 }
            || face.values.contains { Swift.abs($0) > 0.001 }
    }

    /// Effektiver Wert einer Zone: die dezente One-touch-Grundkorrektur, sofern
    /// der Nutzer diese Zone nicht selbst angefasst hat. Sobald er zieht,
    /// gewinnt sein Wert — der Schalter soll ein Vorschlag sein, keine Sperre.
    func value(for part: BodyPart) -> Double {
        if let manual = body[part], Swift.abs(manual) > 0.001 { return manual }
        return oneTouch ? part.oneTouchDefault : 0
    }
}

/// Farb-Presets. Rezepte bewusst an denselben Looks orientiert, die der
/// Agent kennt (G7X-Flash, Golden Hour, Film) — damit Studio und Agent
/// dieselbe Sprache sprechen.
enum PhotoFilter: String, CaseIterable, Identifiable {
    case none, g7x, golden, film, clean, moody, mono

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .g7x: return "G7X flash"
        case .golden: return "Golden"
        case .film: return "Film"
        case .clean: return "Clean"
        case .moody: return "Moody"
        case .mono: return "Mono"
        }
    }
}

/// Lokale Haarfarben. `color` ist absichtlich UIKit-Metadatum statt SwiftUI,
/// damit Modell und Render-Engine unabhängig von einer konkreten View bleiben.
enum HairTintPreset: String, CaseIterable, Identifiable {
    case none, blueBlack, espresso, chestnut, copper, auburn
    case honeyBlonde, platinum, ashBrown, burgundy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:        return "None"
        case .blueBlack:   return "Blue black"
        case .espresso:    return "Espresso"
        case .chestnut:    return "Chestnut"
        case .copper:      return "Copper"
        case .auburn:      return "Auburn"
        case .honeyBlonde: return "Honey blonde"
        case .platinum:    return "Platinum"
        case .ashBrown:    return "Ash brown"
        case .burgundy:    return "Burgundy"
        }
    }

    var color: UIColor {
        switch self {
        case .none:        return .clear
        case .blueBlack:   return UIColor(red: 0.035, green: 0.050, blue: 0.075, alpha: 1)
        case .espresso:    return UIColor(red: 0.120, green: 0.065, blue: 0.040, alpha: 1)
        case .chestnut:    return UIColor(red: 0.310, green: 0.135, blue: 0.070, alpha: 1)
        case .copper:      return UIColor(red: 0.690, green: 0.245, blue: 0.075, alpha: 1)
        case .auburn:      return UIColor(red: 0.430, green: 0.090, blue: 0.055, alpha: 1)
        case .honeyBlonde: return UIColor(red: 0.770, green: 0.565, blue: 0.265, alpha: 1)
        case .platinum:    return UIColor(red: 0.835, green: 0.810, blue: 0.700, alpha: 1)
        case .ashBrown:    return UIColor(red: 0.305, green: 0.270, blue: 0.235, alpha: 1)
        case .burgundy:    return UIColor(red: 0.300, green: 0.035, blue: 0.095, alpha: 1)
        }
    }

    fileprivate var ciColor: CIColor { CIColor(color: color) }
}

enum PhotoEditEngine {

    /// Ein einziger, geteilter Kontext. Ihn pro Frame neu zu bauen ist der
    /// klassische Grund, warum Core-Image-Regler ruckeln.
    private static let context: CIContext = {
        CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    }()

    /// Wendet alle Regler an. `image` sollte für die Live-Vorschau bereits
    /// verkleinert sein (siehe `preview(from:)`), fürs Sichern das Original.
    static func apply(_ edits: PhotoEdits, to image: CIImage,
                      analysis: BodyAnalysis? = nil,
                      face: FaceAnalysis? = nil) -> CIImage {
        var out = image
        let extent = image.extent

        // 1) Körper zuerst — Geometrie vor Farbe, sonst würden Farbsäume
        //    mitverzerrt. Die Zonen kommen aus der Bildanalyse.
        let a = analysis ?? .fallback()
        // Die Silhouette lebt im selben Pixelraum wie das Foto und muss jede
        // Geometrie mitmachen. Eine statische Ausgangsmaske schnitt verbreiterte
        // Schultern/Hueften sonst an der alten Kontur ab und liess Retusche nach
        // einer Verformung neben der Person liegen.
        var alignedPersonMask = a.mask?.resizedMask(to: extent)
        // Ohne erkannte Person duerfen globale Standardzonen niemals unbemerkt
        // einen beliebigen Bildbereich verformen. Farb-/Lichtwerkzeuge bleiben
        // verfuegbar; nur anatomische Koerper-Warps schliessen sicher.
        if a.hasPerson {
            for part in BodyPart.allCases {
                let amount = edits.value(for: part)
                guard abs(amount) > 0.001 else { continue }
                let zone = a.zone(part)
                out = warp(out, amount: amount, zone: zone, mode: part.mode, extent: extent)
                if let mask = alignedPersonMask {
                    alignedPersonMask = warp(mask, amount: amount, zone: zone,
                                             mode: part.mode, extent: extent)
                }
            }
        }
        // Gesicht danach: die Zonen sind kleiner und würden sonst von einer
        // groben Körperverformung mitgezogen.
        let f = face ?? .fallback()
        if f.hasFace {
            for part in FacePart.allCases {
                let amount = edits.face[part] ?? 0
                guard abs(amount) > 0.001 else { continue }
                out = warp(out, amount: amount, zone: f.zone(part), mode: part.mode, extent: extent)
                if let mask = alignedPersonMask {
                    alignedPersonMask = warp(mask, amount: amount, zone: f.zone(part),
                                             mode: part.mode, extent: extent)
                }
            }
        }
        // Personen-Maske: was außerhalb der Person liegt, kommt unverändert
        // aus dem Original zurück. Der Hintergrund ist damit auch dann sicher,
        // wenn eine Zone über ihn hinausragt.
        if let mask = alignedPersonMask, edits.hasBodyChange, edits.backgroundLock {
            let blend = CIFilter.blendWithMask()
            blend.inputImage = out
            blend.backgroundImage = image
            blend.maskImage = mask.resizedMask(to: extent)
            // Background Lock muss bei einem Filterfehler ebenfalls sicher
            // schließen: lieber keine Geometrie als ein verzogener Hintergrund.
            out = (blend.outputImage ?? image).cropped(to: extent)
        }

        // Masken werden einmal auf dem noch ungegradeten, aber bereits
        // geometrisch veränderten Bild ermittelt. So verändern starke Filter
        // nicht nachträglich, was als Haut erkannt wird.
        let localizedValues = [
            edits.skinTone, edits.smooth, edits.evenSkin, edits.redness,
            edits.matte, edits.glow, edits.foundation, edits.blush,
            edits.contour, edits.lipColor, edits.eyeBright, edits.teethWhite,
            edits.hairTintIntensity
        ]
        let needsSkinMask = localizedValues.contains { abs($0) > 0.001 }
        let skinMask = needsSkinMask
            ? SkinMask.mask(for: out, personMask: alignedPersonMask)
            : nil

        // 2) Filter-Preset als Basis-Grade. Die Intensität ist eine echte
        // Mischung mit dem ungefilterten Stand; 0 und 1 sind daher exakt.
        let filterAmount = clamp(edits.filterIntensity, 0...1)
        if edits.filter != .none, filterAmount > 0.001 {
            out = mix(grade(out, edits.filter), over: out,
                      amount: filterAmount, extent: extent)
        }

        // 3) Manuelle Licht-/Farbregler darüber.
        if abs(edits.exposure) > 0.001 {
            let adjust = CIFilter.exposureAdjust()
            adjust.inputImage = out
            adjust.ev = Float(clamp(edits.exposure, -1...1) * 1.4)
            out = adjust.outputImage ?? out
        }
        if abs(edits.highlights) > 0.001 || abs(edits.shadows) > 0.001 {
            // CIHighlightShadowAdjust kann Lichter nur zurückholen, nicht in
            // beide Richtungen bewegen. Eine monotone Tonkurve bildet dagegen
            // die bipolaren Studio-Regler symmetrisch und ohne Neutral-Falle ab.
            let tone = CIFilter.toneCurve()
            tone.inputImage = out
            tone.point0 = CGPoint(x: 0, y: 0)
            tone.point1 = CGPoint(x: 0.25,
                                  y: 0.25 + clamp(edits.shadows, -1...1) * 0.12)
            tone.point2 = CGPoint(x: 0.5, y: 0.5)
            tone.point3 = CGPoint(x: 0.75,
                                  y: 0.75 + clamp(edits.highlights, -1...1) * 0.12)
            tone.point4 = CGPoint(x: 1, y: 1)
            out = tone.outputImage ?? out
        }
        if abs(edits.contrast) > 0.001 || abs(edits.saturation) > 0.001 {
            let controls = CIFilter.colorControls()
            controls.inputImage = out
            controls.contrast = Float(1 + clamp(edits.contrast, -1...1) * 0.45)
            controls.saturation = Float(1 + clamp(edits.saturation, -1...1) * 0.6)
            controls.brightness = 0
            out = controls.outputImage ?? out
        }
        if abs(edits.warmth) > 0.001 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = out
            // Neutral ist 6500K; positiv = wärmer.
            temperature.neutral = CIVector(
                x: 6500 - clamp(edits.warmth, -1...1) * 1200,
                y: 0
            )
            temperature.targetNeutral = CIVector(x: 6500, y: 0)
            out = temperature.outputImage ?? out
        }
        if edits.fade > 0.001 {
            let amount = clamp(edits.fade, 0...1)
            let controls = CIFilter.colorControls()
            controls.inputImage = out
            controls.contrast = Float(1 - amount * 0.22)
            controls.saturation = Float(1 - amount * 0.08)
            controls.brightness = Float(amount * 0.02)
            out = controls.outputImage ?? out
        }

        // 4) Retusche, Haarfarbe und Make-up. Alle drei Pfade schließen bei
        // fehlender Analyse sicher: lieber kein Effekt als Farbe auf Wand,
        // Kleidung oder Augen.
        if let skinMask {
            out = applyRetouch(edits, to: out, skinMask: skinMask, extent: extent)
        }
        if let skinMask, let personMask = alignedPersonMask, f.hasFace {
            out = applyHairTint(edits, to: out, skinMask: skinMask,
                                personMask: personMask, face: f, extent: extent)
            out = applyMakeup(edits, to: out, skinMask: skinMask,
                              personMask: personMask, face: f, extent: extent)
        }

        if edits.sharpen > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = out
            sharpen.sharpness = Float(clamp(edits.sharpen, 0...1) * 0.9)
            out = sharpen.outputImage ?? out
        }
        if edits.grain > 0.001 {
            out = addGrain(to: out, amount: edits.grain, extent: extent)
        }
        if edits.vignette > 0.001 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = out
            vignette.intensity = Float(clamp(edits.vignette, 0...1) * 1.15)
            vignette.radius = 1.55
            out = vignette.outputImage ?? out
        }

        return out.cropped(to: extent)
    }

    // MARK: - Lokale Farb- und Beauty-Effekte

    private static func applyRetouch(_ edits: PhotoEdits, to image: CIImage,
                                     skinMask: CIImage, extent: CGRect) -> CIImage {
        var out = image

        // Bräune ist eine warme, leicht gesättigte Verschiebung in den
        // Mitteltönen. Die bewährte Kurve bleibt erhalten, wird jetzt aber mit
        // allen weiteren Retusche-Effekten über dieselbe Maske geführt.
        if abs(edits.skinTone) > 0.001 {
            let amount = clamp(edits.skinTone, -1...1)
            let tone = CIFilter.colorPolynomial()
            tone.inputImage = out
            tone.redCoefficients = CIVector(
                x: CGFloat(0.020 * amount),
                y: 1 + CGFloat(0.085 * amount), z: 0, w: 0
            )
            tone.greenCoefficients = CIVector(
                x: CGFloat(-0.008 * amount),
                y: 1 + CGFloat(0.020 * amount), z: 0, w: 0
            )
            tone.blueCoefficients = CIVector(
                x: CGFloat(-0.034 * amount),
                y: 1 - CGFloat(0.085 * amount), z: 0, w: 0
            )
            out = maskedMix(tone.outputImage ?? out, over: out,
                            mask: skinMask, amount: 1, extent: extent)
        }

        if edits.smooth > 0.001 {
            let amount = clamp(edits.smooth, 0...1)
            let blur = CIFilter.maskedVariableBlur()
            blur.inputImage = out.clampedToExtent()
            blur.mask = normalizedMask(skinMask, extent: extent)
            blur.radius = Float(max(extent.width, extent.height) * 0.009 * amount)
            let softened = (blur.outputImage ?? out).cropped(to: extent)
            // Selbst der maximale Stand lässt etwas Originaltextur stehen.
            out = maskedMix(softened, over: out, mask: skinMask,
                            amount: 0.72, extent: extent)
        }

        if edits.evenSkin > 0.001 {
            let amount = clamp(edits.evenSkin, 0...1)
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = out.clampedToExtent()
            blur.radius = Float(max(extent.width, extent.height) * 0.014)

            // Color blend übernimmt nur die großflächige Farbe des weicheren
            // Bilds; Poren-/Kantenluminanz kommt weiter aus dem Original.
            let color = CIFilter.colorBlendMode()
            color.inputImage = (blur.outputImage ?? out).cropped(to: extent)
            color.backgroundImage = out
            out = maskedMix(color.outputImage ?? out, over: out,
                            mask: skinMask, amount: amount * 0.62, extent: extent)
        }

        if edits.redness > 0.001 {
            let correction = CIFilter.colorMatrix()
            correction.inputImage = out
            correction.rVector = CIVector(x: 0.91, y: 0.045, z: 0.015, w: 0)
            correction.gVector = CIVector(x: 0.012, y: 1.005, z: 0, w: 0)
            correction.bVector = CIVector(x: 0, y: 0.012, z: 1.005, w: 0)
            correction.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            correction.biasVector = CIVector(x: 0, y: 0.004, z: 0.004, w: 0)
            out = maskedMix(correction.outputImage ?? out, over: out,
                            mask: skinMask,
                            amount: clamp(edits.redness, 0...1), extent: extent)
        }

        if edits.matte > 0.001 {
            let matte = CIFilter.highlightShadowAdjust()
            matte.inputImage = out
            matte.radius = Float(max(extent.width, extent.height) * 0.02)
            matte.shadowAmount = 0
            matte.highlightAmount = 0.42
            out = maskedMix(matte.outputImage ?? out, over: out,
                            mask: skinMask,
                            amount: clamp(edits.matte, 0...1) * 0.82,
                            extent: extent)
        }

        if edits.glow > 0.001 {
            let bloom = CIFilter.bloom()
            bloom.inputImage = out.clampedToExtent()
            bloom.radius = Float(max(3, max(extent.width, extent.height) * 0.012))
            bloom.intensity = 0.48
            out = maskedMix((bloom.outputImage ?? out).cropped(to: extent),
                            over: out, mask: skinMask,
                            amount: clamp(edits.glow, 0...1), extent: extent)
        }

        return out.cropped(to: extent)
    }

    private static func applyMakeup(_ edits: PhotoEdits, to image: CIImage,
                                    skinMask: CIImage, personMask: CIImage,
                                    face: FaceAnalysis, extent: CGRect) -> CIImage {
        let values = [edits.foundation, edits.blush, edits.contour,
                      edits.lipColor, edits.eyeBright, edits.teethWhite]
        guard face.hasFace, values.contains(where: { $0 > 0.001 }) else { return image }

        var out = image
        let person = normalizedMask(personMask.resizedMask(to: extent), extent: extent)
        let skin = normalizedMask(skinMask, extent: extent)
        let inverseSkin = invertedMask(skin, extent: extent)

        let eyeMask = pairedFeatureMask(face.zone(.eyes), extent: extent,
                                        offset: 0.52, radiusX: 0.36, radiusY: 0.72)
        let cheekMask = pairedFeatureMask(face.zone(.cheekbones), extent: extent,
                                          offset: 0.53, radiusX: 0.34, radiusY: 0.72)
        let lipMask = featureMask(face.zone(.lips), extent: extent,
                                  radiusX: 0.86, radiusY: 0.62)
        let mouthCore = featureMask(face.zone(.lips), extent: extent,
                                    radiusX: 0.68, radiusY: 0.44)
        let faceMask = featureMask(face.zone(.faceWidth), extent: extent,
                                   radiusX: 0.80, radiusY: 0.84, offsetY: 0.03)

        if edits.foundation > 0.001,
           let foundationBase = intersection([skin, person, faceMask], extent: extent) {
            let featureBlocker = union([eyeMask, lipMask], extent: extent)
            let foundationMask = featureBlocker.map {
                subtracting($0, from: foundationBase, extent: extent)
            } ?? foundationBase

            let foundation = CIFilter.colorMatrix()
            foundation.inputImage = out
            foundation.rVector = CIVector(x: 0.985, y: 0.008, z: 0, w: 0)
            foundation.gVector = CIVector(x: 0.004, y: 0.988, z: 0, w: 0)
            foundation.bVector = CIVector(x: 0, y: 0.006, z: 0.975, w: 0)
            foundation.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            foundation.biasVector = CIVector(x: 0.020, y: 0.012, z: 0.008, w: 0)
            out = maskedMix(foundation.outputImage ?? out, over: out,
                            mask: foundationMask,
                            amount: clamp(edits.foundation, 0...1) * 0.9,
                            extent: extent)
        }

        if edits.blush > 0.001,
           let blushMask = intersection([skin, person, cheekMask], extent: extent) {
            let blush = CIFilter.colorMatrix()
            blush.inputImage = out
            blush.rVector = CIVector(x: 1.025, y: 0.015, z: 0, w: 0)
            blush.gVector = CIVector(x: 0, y: 0.965, z: 0, w: 0)
            blush.bVector = CIVector(x: 0.018, y: 0, z: 0.985, w: 0)
            blush.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            blush.biasVector = CIVector(x: 0.045, y: -0.006, z: 0.010, w: 0)
            out = maskedMix(blush.outputImage ?? out, over: out,
                            mask: blushMask, amount: clamp(edits.blush, 0...1),
                            extent: extent)
        }

        if edits.contour > 0.001 {
            let cheek = face.zone(.cheekbones)
            let jaw = face.zone(.jawline)
            let cheekSides = pairedFeatureMask(cheek, extent: extent,
                                               offset: 0.73, radiusX: 0.23, radiusY: 0.92)
            let jawSides = pairedFeatureMask(jaw, extent: extent,
                                             offset: 0.70, radiusX: 0.24, radiusY: 0.88)
            if let contourZones = union([cheekSides, jawSides], extent: extent),
               let contourMask = intersection([skin, person, contourZones], extent: extent) {
                let contour = CIFilter.exposureAdjust()
                contour.inputImage = out
                contour.ev = -0.42
                out = maskedMix(contour.outputImage ?? out, over: out,
                                mask: contourMask,
                                amount: clamp(edits.contour, 0...1) * 0.82,
                                extent: extent)
            }
        }

        if edits.lipColor > 0.001,
           let safeLips = intersection([person, lipMask], extent: extent) {
            let lips = CIFilter.colorMonochrome()
            lips.inputImage = out
            lips.color = CIColor(red: 0.58, green: 0.075, blue: 0.16, alpha: 1)
            lips.intensity = 0.58
            out = maskedMix(lips.outputImage ?? out, over: out,
                            mask: safeLips,
                            amount: clamp(edits.lipColor, 0...1) * 0.9,
                            extent: extent)
        }

        // Die Helligkeitsmaske wird vor Augen-/Zahnkorrektur aus dem
        // ungeschminkten Stand gebildet. MinimumComponent selektiert nur Pixel,
        // deren drei Kanäle hell sind — Iris, dunkler Mund und bunte Pixel
        // werden dadurch nicht versehentlich weiß.
        let bright = brightNeutralMask(for: image, extent: extent)

        if edits.eyeBright > 0.001,
           let bright,
           let whites = intersection([person, eyeMask, inverseSkin, bright], extent: extent) {
            let eyes = CIFilter.colorControls()
            eyes.inputImage = out
            eyes.saturation = 0.28
            eyes.brightness = 0.10
            eyes.contrast = 1.02
            out = maskedMix(eyes.outputImage ?? out, over: out, mask: whites,
                            amount: clamp(edits.eyeBright, 0...1), extent: extent)
        }

        if edits.teethWhite > 0.001,
           let bright,
           let teeth = intersection([person, mouthCore, inverseSkin, bright], extent: extent) {
            let whitening = CIFilter.colorControls()
            whitening.inputImage = out
            whitening.saturation = 0.12
            whitening.brightness = 0.12
            whitening.contrast = 1.03
            out = maskedMix(whitening.outputImage ?? out, over: out, mask: teeth,
                            amount: clamp(edits.teethWhite, 0...1), extent: extent)
        }

        return out.cropped(to: extent)
    }

    private static func applyHairTint(_ edits: PhotoEdits, to image: CIImage,
                                      skinMask: CIImage, personMask: CIImage,
                                      face: FaceAnalysis, extent: CGRect) -> CIImage {
        let amount = clamp(edits.hairTintIntensity, 0...1)
        guard face.hasFace, edits.hairTint != .none, amount > 0.001 else { return image }

        let faceZone = face.zone(.faceWidth)
        let rx = faceZone.radiusX
        let ry = faceZone.radiusY
        let cap = BodyZone(
            center: CGPoint(x: faceZone.center.x,
                            y: faceZone.center.y - CGFloat(ry * 0.68)),
            radiusX: rx * 1.02,
            radiusY: ry * 0.70
        )
        let leftSide = BodyZone(
            center: CGPoint(x: faceZone.center.x - CGFloat(rx * 0.80),
                            y: faceZone.center.y - CGFloat(ry * 0.18)),
            radiusX: rx * 0.28,
            radiusY: ry * 0.58
        )
        let rightSide = BodyZone(
            center: CGPoint(x: faceZone.center.x + CGFloat(rx * 0.80),
                            y: faceZone.center.y - CGFloat(ry * 0.18)),
            radiusX: rx * 0.28,
            radiusY: ry * 0.58
        )

        let candidate = union([
            featureMask(cap, extent: extent),
            featureMask(leftSide, extent: extent),
            featureMask(rightSide, extent: extent)
        ], extent: extent)
        let person = normalizedMask(personMask.resizedMask(to: extent), extent: extent)
        let skin = normalizedMask(skinMask, extent: extent)

        // Haut leicht erweitern, bevor sie abgezogen wird. Der Sicherheitsrand
        // verhindert gefärbte Säume am Haaransatz und an den Ohren.
        let dilation = CIFilter.morphologyMaximum()
        dilation.inputImage = skin
        dilation.radius = Float(max(1, max(extent.width, extent.height) * 0.006))
        let dilatedSkin = normalizedMask(
            (dilation.outputImage ?? skin).cropped(to: extent), extent: extent
        )

        // Der untere, innere Gesichtsbereich wird zusätzlich ausgeschlossen.
        // Das schützt Augen und Mund, falls deren Farbe nicht als Haut erkannt
        // wird; Seitenhaar außerhalb dieses Kerns bleibt erreichbar.
        let innerFace = BodyZone(
            center: CGPoint(x: faceZone.center.x,
                            y: faceZone.center.y + CGFloat(ry * 0.20)),
            radiusX: rx * 0.72,
            radiusY: ry * 0.72
        )
        let featureBlocker = union([
            featureMask(innerFace, extent: extent),
            featureMask(face.zone(.eyes), extent: extent),
            featureMask(face.zone(.eyebrows), extent: extent)
        ], extent: extent)

        guard let candidate,
              var safeHair = intersection(
                [person, candidate, invertedMask(dilatedSkin, extent: extent)],
                extent: extent
              ) else { return image }
        if let featureBlocker {
            safeHair = subtracting(featureBlocker, from: safeHair, extent: extent)
        }

        // Nur die Maske federn, dann erneut mit den harten Sicherheitsgrenzen
        // schneiden. So entsteht kein Halo über Haut oder Hintergrund.
        let feather = CIFilter.gaussianBlur()
        feather.inputImage = safeHair.clampedToExtent()
        feather.radius = Float(max(0.75, max(extent.width, extent.height) * 0.0025))
        let feathered = normalizedMask(
            (feather.outputImage ?? safeHair).cropped(to: extent), extent: extent
        )
        guard let finalMask = intersection([
            feathered, person, invertedMask(dilatedSkin, extent: extent)
        ], extent: extent) else { return image }

        // ColorMonochrome erhält die Luminanz/Strähnenstruktur und ersetzt nur
        // einen Teil der Farbe — eine Tönung, keine flache Farbebene.
        let tint = CIFilter.colorMonochrome()
        tint.inputImage = image
        tint.color = edits.hairTint.ciColor
        tint.intensity = 0.72
        return maskedMix(tint.outputImage ?? image, over: image, mask: finalMask,
                         amount: amount * 0.88, extent: extent)
    }

    private static func addGrain(to image: CIImage, amount: Double,
                                 extent: CGRect) -> CIImage {
        let random = CIFilter.randomGenerator()
        guard let generated = random.outputImage else { return image }

        let grayscale = CIFilter.colorControls()
        grayscale.inputImage = generated.cropped(to: extent)
        grayscale.saturation = 0
        grayscale.contrast = 1.35
        grayscale.brightness = 0
        guard let noise = grayscale.outputImage else { return image }

        // Generator-Alpha ist ebenfalls zufällig. Für ein stabiles Blend muss
        // die Körnung vollständig deckend sein.
        let opaque = CIFilter.colorMatrix()
        opaque.inputImage = noise
        opaque.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        opaque.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        opaque.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        opaque.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        opaque.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = (opaque.outputImage ?? noise).cropped(to: extent)
        blend.backgroundImage = image
        return mix(blend.outputImage ?? image, over: image,
                   amount: clamp(amount, 0...1) * 0.24, extent: extent)
    }

    // MARK: - Masken-Algebra

    private static func featureMask(_ zone: BodyZone, extent: CGRect,
                                    radiusX: Double = 1, radiusY: Double = 1,
                                    offsetX: Double = 0, offsetY: Double = 0) -> CIImage {
        let adjusted = BodyZone(
            center: CGPoint(x: zone.center.x + CGFloat(zone.radiusX * offsetX),
                            y: zone.center.y + CGFloat(zone.radiusY * offsetY)),
            radiusX: max(zone.radiusX * radiusX, 0.001),
            radiusY: max(zone.radiusY * radiusY, 0.001)
        )
        let center = CGPoint(
            x: extent.minX + extent.width * adjusted.center.x,
            y: extent.minY + extent.height * (1 - adjusted.center.y)
        )
        let mask = softEllipseMask(
            extent: extent,
            center: center,
            radiusX: max(extent.width * adjusted.radiusX, 1),
            radiusY: max(extent.height * adjusted.radiusY, 1)
        ) ?? CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: extent)
        return normalizedMask(mask, extent: extent)
    }

    private static func pairedFeatureMask(_ zone: BodyZone, extent: CGRect,
                                          offset: Double, radiusX: Double,
                                          radiusY: Double) -> CIImage {
        let left = featureMask(zone, extent: extent, radiusX: radiusX,
                               radiusY: radiusY, offsetX: -offset)
        let right = featureMask(zone, extent: extent, radiusX: radiusX,
                                radiusY: radiusY, offsetX: offset)
        return union([left, right], extent: extent) ?? left
    }

    private static func brightNeutralMask(for image: CIImage,
                                          extent: CGRect) -> CIImage? {
        let minimum = CIFilter.minimumComponent()
        minimum.inputImage = image
        guard let grayscale = minimum.outputImage else { return nil }

        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = grayscale
        threshold.threshold = 0.42
        guard let binary = threshold.outputImage else { return nil }

        let feather = CIFilter.gaussianBlur()
        feather.inputImage = binary.clampedToExtent()
        feather.radius = Float(max(0.6, max(extent.width, extent.height) * 0.0015))
        return normalizedMask(
            (feather.outputImage ?? binary).cropped(to: extent), extent: extent
        )
    }

    /// Erzwingt eine opake Graustufenmaske. Das ist für Compositing wichtig:
    /// transparentes Schwarz würde beim Multiplizieren die jeweils andere
    /// Maske durchreichen, statt außerhalb zuverlässig null zu ergeben.
    private static func normalizedMask(_ image: CIImage, extent: CGRect) -> CIImage {
        let grayscale = CIFilter.minimumComponent()
        grayscale.inputImage = image.cropped(to: extent)
        let gray = grayscale.outputImage ?? image

        let alpha = CIFilter.colorMatrix()
        alpha.inputImage = gray
        alpha.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        alpha.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        alpha.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        alpha.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        alpha.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return (alpha.outputImage ?? gray).cropped(to: extent)
    }

    private static func intersection(_ masks: [CIImage],
                                     extent: CGRect) -> CIImage? {
        guard var result = masks.first.map({ normalizedMask($0, extent: extent) }) else {
            return nil
        }
        for mask in masks.dropFirst() {
            let multiply = CIFilter.multiplyCompositing()
            multiply.inputImage = result
            multiply.backgroundImage = normalizedMask(mask, extent: extent)
            guard let next = multiply.outputImage else { return nil }
            result = normalizedMask(next.cropped(to: extent), extent: extent)
        }
        return result.cropped(to: extent)
    }

    private static func union(_ masks: [CIImage], extent: CGRect) -> CIImage? {
        guard var result = masks.first.map({ normalizedMask($0, extent: extent) }) else {
            return nil
        }
        for mask in masks.dropFirst() {
            let maximum = CIFilter.maximumCompositing()
            maximum.inputImage = result
            maximum.backgroundImage = normalizedMask(mask, extent: extent)
            guard let next = maximum.outputImage else { return nil }
            result = normalizedMask(next.cropped(to: extent), extent: extent)
        }
        return result.cropped(to: extent)
    }

    private static func invertedMask(_ mask: CIImage, extent: CGRect) -> CIImage {
        let invert = CIFilter.colorInvert()
        invert.inputImage = normalizedMask(mask, extent: extent)
        return normalizedMask(invert.outputImage ?? mask, extent: extent)
    }

    private static func subtracting(_ mask: CIImage, from base: CIImage,
                                    extent: CGRect) -> CIImage {
        intersection([base, invertedMask(mask, extent: extent)], extent: extent)
            ?? normalizedMask(base, extent: extent)
    }

    private static func scaledMask(_ mask: CIImage, amount: Double,
                                   extent: CGRect) -> CIImage {
        let value = CGFloat(clamp(amount, 0...1))
        let scale = CIFilter.colorMatrix()
        scale.inputImage = normalizedMask(mask, extent: extent)
        scale.rVector = CIVector(x: value, y: 0, z: 0, w: 0)
        scale.gVector = CIVector(x: 0, y: value, z: 0, w: 0)
        scale.bVector = CIVector(x: 0, y: 0, z: value, w: 0)
        scale.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        scale.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return (scale.outputImage ?? mask).cropped(to: extent)
    }

    private static func maskedMix(_ effect: CIImage, over base: CIImage,
                                  mask: CIImage, amount: Double,
                                  extent: CGRect) -> CIImage {
        let value = clamp(amount, 0...1)
        guard value > 0.001 else { return base.cropped(to: extent) }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = effect.cropped(to: extent)
        blend.backgroundImage = base.cropped(to: extent)
        blend.maskImage = scaledMask(mask, amount: value, extent: extent)
        return (blend.outputImage ?? base).cropped(to: extent)
    }

    private static func mix(_ effect: CIImage, over base: CIImage,
                            amount: Double, extent: CGRect) -> CIImage {
        let value = clamp(amount, 0...1)
        guard value > 0.001 else { return base.cropped(to: extent) }
        guard value < 0.999 else { return effect.cropped(to: extent) }
        let mix = CIFilter.mix()
        mix.inputImage = effect.cropped(to: extent)
        mix.backgroundImage = base.cropped(to: extent)
        mix.amount = Float(value)
        return (mix.outputImage ?? base).cropped(to: extent)
    }

    private static func clamp(_ value: Double,
                              _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Lokale Verzerrung mit hartem Radius. `amount` < 0 zieht zusammen
    /// (schmaler), > 0 wölbt heraus (voller). Außerhalb des Radius passiert
    /// nichts — das ist der Hintergrund-Lock.
    private static func warp(_ image: CIImage, amount: Double, zone: BodyZone,
                             mode: WarpMode, extent: CGRect) -> CIImage {
        // Nicht jede Stelle wird breiter/schmaler gemacht. „Length" und „Torso"
        // STRECKEN, „Hip lift" SCHIEBT. Ohne diese Unterscheidung fühlen sich
        // alle sechzehn Regler identisch an — genau der Eindruck, den EPIK
        // nicht hat.
        switch mode {
        case .stretch:
            return verticalPush(image, amount: amount, zone: zone, extent: extent)
        case .lift:
            // Mittelpunkt bewusst am UNTEREN Rand der Zone: dadurch hebt sich
            // das Gewebe darueber, statt sich nur symmetrisch aufzublaehen -
            // das ist es, was "Hip lift" meint.
            return verticalPush(image, amount: amount, zone: zone, extent: extent,
                                centerBias: CGFloat(zone.radiusY) * 0.8)
        case .localStretch:
            return localVerticalStretch(image, amount: amount, zone: zone, extent: extent)
        case .widen:   break
        }
        // Core Image rechnet mit Ursprung unten links, die UI mit oben links.
        let cx = extent.origin.x + extent.width * zone.center.x
        let cy = extent.origin.y + extent.height * (1 - zone.center.y)
        let scale = 1.0
        // Eine Taille ist breiter als hoch — ein runder Wirkkreis zieht deshalb
        // auch Brust und Hüfte mit. Die Zone wird darum als Ellipse behandelt:
        // das Bild wird gestaucht, kreisrund verzerrt und zurückgestaucht.
        let rx = max(extent.width * CGFloat(zone.radiusX * scale), 1)
        let ry = max(extent.height * CGFloat(zone.radiusY * scale), 1)
        let k = rx / ry                       // >1 = breiter als hoch

        let toCircle = CGAffineTransform(translationX: 0, y: -cy)
            .concatenating(CGAffineTransform(scaleX: 1, y: k))
            .concatenating(CGAffineTransform(translationX: 0, y: cy * k))
        let squeezed = image.transformed(by: toCircle)

        let f = CIFilter.bumpDistortion()
        f.inputImage = squeezed
        f.center = CGPoint(x: cx, y: cy * k)
        f.radius = Float(rx)
        f.scale = Float(amount * 0.45)
        guard let bumped = f.outputImage else { return image }

        return bumped.transformed(by: toCircle.inverted()).cropped(to: extent)
    }

    /// STRECKEN (Forehead, Torso, Length) und SCHIEBEN (Hip lift).
    ///
    /// FRUEHER FALSCH, und zwar sichtbar: die alte Fassung hat ALLES unterhalb
    /// der Zone in der Hoehe skaliert und das Ergebnis ueber das Original
    /// gelegt. Zwei Fehler auf einmal - die ganze Person wanderte, und dort,
    /// wo die skalierte Kopie das Original nicht ueberdeckte, blieb dieses
    /// sichtbar: ein Doppelgaenger hinter der Person. Beim Stirn-Regler fiel
    /// das sofort auf, weil "unterhalb der Stirn" praktisch der ganze Mensch ist.
    ///
    /// Jetzt ueber CIBumpDistortionLinear: eine Verschiebung SENKRECHT zu einer
    /// waagerechten Linie, begrenzt durch einen Radius. Ausserhalb des Radius
    /// bleibt jedes Pixel unveraendert - kein Wandern, kein Doppelbild, kein
    /// Zusammensetzen zweier Ebenen.
    private static func verticalPush(_ image: CIImage, amount: Double, zone: BodyZone,
                                     extent: CGRect, centerBias: CGFloat = 0) -> CIImage {
        let cx = extent.origin.x + extent.width * zone.center.x
        // Core Image rechnet von unten links, die Zonen von oben links.
        let cy = extent.origin.y + extent.height * (1 - (CGFloat(zone.center.y) + centerBias))
        // Der Radius muss die Zone umfassen, sonst reisst die Verformung an der
        // Kante ab. Die groessere der beiden Halbachsen gibt ihn vor.
        let r = max(extent.width * CGFloat(zone.radiusX),
                    extent.height * CGFloat(zone.radiusY)) * 1.35

        let f = CIFilter.bumpDistortionLinear()
        f.inputImage = image
        f.center = CGPoint(x: cx, y: cy)
        f.radius = Float(max(r, 8))
        f.angle = 0                      // waagerechte Linie -> senkrechte Wirkung
        // GEMESSEN zu stark bei 0.35: die Stirn riss bei 37 % schon die
        // Haare hoch. Senkrechte Verschiebungen fallen viel stärker auf als
        // seitliche, deshalb deutlich zurückhaltender.
        f.scale = Float(amount * 0.05)
        return (f.outputImage ?? image).cropped(to: extent)
    }

    /// Vertikale Gesichtsverformung, die wirklich IN der analysierten Zone
    /// bleibt. `CIBumpDistortionLinear` ist hier ungeeignet: seine Linie läuft
    /// über die ganze Bildbreite und zog im Stirn-Test sichtbar die Haare mit.
    ///
    /// Stattdessen wird eine moderat vertikal skalierte Bildfassung nur durch
    /// eine weiche Ellipsenmaske eingeblendet. Am Maskenrand steht die Deckkraft
    /// bereits auf null, deshalb treffen dort exakt wieder die Originalpixel auf
    /// das Original — keine Naht, kein Doppelbild und keine wandernde Person.
    private static func localVerticalStretch(_ image: CIImage, amount: Double,
                                             zone: BodyZone, extent: CGRect) -> CIImage {
        let cx = extent.origin.x + extent.width * zone.center.x
        let cy = extent.origin.y + extent.height * (1 - zone.center.y)
        let rx = max(extent.width * CGFloat(zone.radiusX), 8)
        let ry = max(extent.height * CGFloat(zone.radiusY), 8)

        // Voll aufgedreht bleiben es bewusst nur ±14 %. Der Regler soll eine
        // glaubhafte Stirnkorrektur sein und keine Karikatur erzeugen.
        let scaleY = CGFloat(max(0.86, min(1.14, 1 + amount * 0.14)))
        let transform = CGAffineTransform(translationX: cx, y: cy)
            .scaledBy(x: 1, y: scaleY)
            .translatedBy(x: -cx, y: -cy)
        let stretched = image.transformed(by: transform).cropped(to: extent)

        guard let mask = softEllipseMask(extent: extent,
                                         center: CGPoint(x: cx, y: cy),
                                         radiusX: rx,
                                         radiusY: ry) else { return image }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = stretched
        blend.backgroundImage = image
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    /// Weiße Ellipse mit vollem Kern und weichem äußerem Drittel.
    private static func softEllipseMask(extent: CGRect, center: CGPoint,
                                        radiusX: CGFloat, radiusY: CGFloat) -> CIImage? {
        let gradient = CIFilter.radialGradient()
        gradient.center = center
        gradient.radius0 = Float(radiusX * 0.62)
        gradient.radius1 = Float(radiusX)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        // Opakes Schwarz ist auch außerhalb der Ellipse wirklich Maske=0.
        // Transparentes Schwarz würde bei späterer Masken-Algebra die andere
        // Ebene durchreichen und lokalisierte Farbe aus der Zone lecken lassen.
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let circle = gradient.outputImage else { return nil }

        let ellipse = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: 1, y: radiusY / radiusX)
            .translatedBy(x: -center.x, y: -center.y)
        return circle.transformed(by: ellipse).cropped(to: extent)
    }


    private static func grade(_ image: CIImage, _ filter: PhotoFilter) -> CIImage {
        switch filter {
        case .none:
            return image

        case .g7x:
            // Harter Direktblitz: angehobene Lichter, kühl-warmer Kontrast,
            // Ecken leicht abgedunkelt.
            let c = CIFilter.colorControls()
            c.inputImage = image
            c.contrast = 1.16
            c.saturation = 0.94
            c.brightness = 0.05
            let v = CIFilter.vignette()
            v.inputImage = c.outputImage
            v.intensity = 0.7
            v.radius = 1.6
            return v.outputImage ?? image

        case .golden:
            let t = CIFilter.temperatureAndTint()
            t.inputImage = image
            t.neutral = CIVector(x: 5200, y: 0)
            t.targetNeutral = CIVector(x: 6500, y: 0)
            let c = CIFilter.colorControls()
            c.inputImage = t.outputImage
            c.contrast = 1.04
            c.saturation = 1.12
            return c.outputImage ?? image

        case .film:
            let c = CIFilter.colorControls()
            c.inputImage = image
            c.contrast = 0.94
            c.saturation = 0.9
            let n = CIFilter.photoEffectFade()
            n.inputImage = c.outputImage
            return n.outputImage ?? image

        case .clean:
            let c = CIFilter.colorControls()
            c.inputImage = image
            c.contrast = 1.02
            c.saturation = 0.97
            c.brightness = 0.03
            return c.outputImage ?? image

        case .moody:
            let c = CIFilter.colorControls()
            c.inputImage = image
            c.contrast = 1.1
            c.saturation = 0.72
            let t = CIFilter.temperatureAndTint()
            t.inputImage = c.outputImage
            t.neutral = CIVector(x: 7200, y: 0)
            t.targetNeutral = CIVector(x: 6500, y: 0)
            return t.outputImage ?? image

        case .mono:
            let f = CIFilter.photoEffectMono()
            f.inputImage = image
            return f.outputImage ?? image
        }
    }

    // MARK: - Rendern

    /// Kanonischer Studio-Pixelraum: Orientierung `.up`, Scale 1 und echte
    /// Pixelmasse. Das ist absichtlich auch fuer Fullsize-Bilder zugaenglich,
    /// damit Import, Vision, Core Image, Remove-Maske und Export nie verschiedene
    /// EXIF-Achsen verwenden.
    nonisolated static func normalizedForEditing(
        _ image: UIImage,
        maxPixelDimension: CGFloat? = nil
    ) -> UIImage {
        let rawWidth: CGFloat
        let rawHeight: CGFloat
        if let cg = image.cgImage {
            rawWidth = CGFloat(cg.width)
            rawHeight = CGFloat(cg.height)
        } else {
            rawWidth = max(image.size.width * image.scale, 1)
            rawHeight = max(image.size.height * image.scale, 1)
        }

        let swapsAxes: Bool
        switch image.imageOrientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            swapsAxes = true
        default:
            swapsAxes = false
        }
        let orientedWidth = swapsAxes ? rawHeight : rawWidth
        let orientedHeight = swapsAxes ? rawWidth : rawHeight
        let longest = max(orientedWidth, orientedHeight, 1)
        let requested = maxPixelDimension.map { max($0, 1) } ?? longest
        let downscale = min(1, requested / longest)
        // Abrunden garantiert, dass auch durch Gleitkomma-Rundung keine Kante
        // einen Pixel ueber das vereinbarte Maximum hinausgeht.
        let targetWidth = max(1, floor(orientedWidth * downscale))
        let targetHeight = max(1, floor(orientedHeight * downscale))

        if image.imageOrientation == .up,
           image.scale == 1,
           rawWidth == targetWidth,
           rawHeight == targetHeight,
           image.cgImage != nil {
            return image
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let size = CGSize(width: targetWidth, height: targetHeight)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Verkleinerte, immer kanonisch ausgerichtete Fassung fuer die
    /// Live-Vorschau. Auf voller Aufloesung waere jede Regler-Bewegung traege.
    static func preview(from image: UIImage, maxDimension: CGFloat = 1100) -> UIImage {
        normalizedForEditing(image, maxPixelDimension: maxDimension)
    }

    static func render(_ edits: PhotoEdits, from source: UIImage,
                       analysis: BodyAnalysis? = nil,
                       face: FaceAnalysis? = nil) -> UIImage? {
        let canonical = normalizedForEditing(source)
        guard let cgSource = canonical.cgImage else { return nil }
        let ci = CIImage(cgImage: cgSource)
        let out = apply(edits, to: ci, analysis: analysis, face: face)
        guard let cg = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}
