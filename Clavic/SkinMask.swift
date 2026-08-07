//
//  SkinMask.swift
//  Clavic
//
//  Erkennt, WO im Bild Haut ist — damit der Hautton-Regler wirklich nur die
//  Haut bräunt und nicht das halbe Foto.
//
//  Vorher lief `skinTone` als Farbkurve über das GANZE Bild: mit der Haut
//  wurden Wand, Kleidung, Himmel und Haare mitgefärbt. Bei FaceLab ändert sich
//  sichtbar nur die Haut, sonst nichts — genau das ist der Unterschied.
//
//  Verfahren, bewusst ohne zusätzliches Modell:
//    1. Eine Farb-Nachschlagetabelle (`CIColorCube`) entscheidet pro Farbe, ob
//       sie hautartig ist. Das läuft auf der GPU und ist in Echtzeit möglich —
//       ein Test pro Pixel in Swift wäre bei jedem Reglerschritt zäh.
//    2. Das Ergebnis wird mit der PERSONEN-Maske aus Vision verrechnet. Ohne
//       diesen Schritt färbt man auch hautfarbene Wände, Holz und Sand mit.
//    3. Die Maske wird leicht weichgezeichnet, sonst entstehen harte Kanten
//       an den Rändern und das Ergebnis sieht ausgeschnitten aus.
//
//  Die Hautregel ist die klassische Kovac-Bedingung, ergänzt um eine
//  Chroma-Prüfung. Sie deckt helle bis sehr dunkle Hauttöne ab, weil sie nicht
//  auf Helligkeit prüft, sondern auf das VERHÄLTNIS der Kanäle.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

extension CIImage {
    /// Bringt eine bei der Vorschau-Analyse erzeugte Maske exakt auf die
    /// Render-Auflösung. `clampedToExtent()` wiederholt nur Randpixel und darf
    /// deshalb niemals als Größenanpassung benutzt werden.
    nonisolated func resizedMask(to target: CGRect) -> CIImage {
        guard extent.width > 0, extent.height > 0,
              target.width > 0, target.height > 0 else {
            return cropped(to: target)
        }
        var result = transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
        result = result.transformed(by: CGAffineTransform(
            scaleX: target.width / result.extent.width,
            y: target.height / result.extent.height
        ))
        result = result.transformed(by: CGAffineTransform(
            translationX: target.minX,
            y: target.minY
        ))
        return result.cropped(to: target)
    }
}

enum SkinMask {

    /// Kantenlänge der Nachschlagetabelle. 32 reicht: Hauttöne bilden im
    /// Farbraum einen breiten, zusammenhängenden Bereich, da braucht es keine
    /// feine Auflösung — und 64³ wäre achtmal so viel Speicher.
    private static let size = 32

    /// Wird einmal gebaut und behalten. Die Tabelle bei jedem Reglerschritt neu
    /// zu erzeugen war der Grund, warum solche Filter oft ruckeln.
    private static let cubeData: Data = {
        var data = [Float](repeating: 0, count: size * size * size * 4)
        var i = 0
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rf = Float(r) / Float(size - 1)
                    let gf = Float(g) / Float(size - 1)
                    let bf = Float(b) / Float(size - 1)
                    let v = skinLikelihood(rf, gf, bf)
                    data[i + 0] = v
                    data[i + 1] = v
                    data[i + 2] = v
                    data[i + 3] = 1
                    i += 4
                }
            }
        }
        return data.withUnsafeBufferPointer { Data(buffer: $0) }
    }()

    /// 0 = sicher keine Haut, 1 = sicher Haut. Bewusst mit weichem Übergang,
    /// damit die Maske keine harte Kante bekommt.
    private static func skinLikelihood(_ r: Float, _ g: Float, _ b: Float) -> Float {
        let mx = max(r, g, b), mn = min(r, g, b)

        // Rot muss führen und genügend relative Farbinformation vorhanden
        // sein. Relative statt absoluter Schwellen sind entscheidend: Eine
        // dunkle Hautstelle bei wenig Licht hat kleine Kanalwerte, aber nahezu
        // dieselben Verhältnisse wie dieselbe Haut im Hellen.
        let span = (mx - mn) / max(mx, 0.001)
        let redLead = (r - g) / max(r, 0.001)
        guard mx > 0.045,
              r > g * 1.02, r > b * 1.06,
              span > 0.08, redLead > 0.025 else { return 0 }

        // Chroma-Prüfung: Haut liegt in einem engen Bereich von Cb/Cr. Das
        // sortiert Orange-Rot (Backstein, Holz, Sonnenuntergang) aus, das die
        // Grundbedingungen sonst ebenfalls erfüllt.
        let y  =  0.299 * r + 0.587 * g + 0.114 * b
        let cb = (b - y) * 0.564 + 0.5
        let cr = (r - y) * 0.713 + 0.5
        guard cb > 0.30, cb < 0.50, cr > 0.52, cr < 0.68 else { return 0 }

        // Weicher Rand: je weiter von der Mitte des Hautbereichs, desto
        // schwächer — verhindert sichtbare Sprünge an Übergängen.
        let dCb = abs(cb - 0.40) / 0.10
        let dCr = abs(cr - 0.60) / 0.08
        let edge = max(dCb, dCr)
        let chroma = max(0, min(1, 1.4 - edge))
        // Fast schwarze Pixel (Haare/Schatten) nur weich einblenden. Anders
        // als die alte harte Rot-Schwelle bleibt Low-Light-Haut erreichbar.
        let visibility = max(0, min(1, (y - 0.035) / 0.08))
        return chroma * visibility
    }

    /// Liefert die Hautmaske (weiß = Haut) für das Bild.
    /// `personMask` kommt aus `BodyAnalysis` und begrenzt das Ergebnis auf die
    /// Person. Fehlt sie, liefern wir bewusst KEINE Maske: Eine bloße Farbsuche
    /// könnte sonst Holz, Sand oder eine hautfarbene Wand für Haut halten.
    static func mask(for image: CIImage, personMask: CIImage?) -> CIImage? {
        guard let personMask else { return nil }
        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = image
        cube.cubeDimension = Float(size)
        cube.cubeData = cubeData
        // Die LUT-Schwellen sind für gamma-kodiertes sRGB berechnet. Ohne
        // expliziten Farbraum würde Core Image sie im linearen Arbeitsraum
        // auswerten und besonders dunkle Haut fälschlich aussortieren.
        cube.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        guard var out = cube.outputImage else { return nil }

        let mult = CIFilter.multiplyCompositing()
        mult.inputImage = out
        mult.backgroundImage = personMask.resizedMask(to: image.extent)
        guard let personLimited = mult.outputImage else { return nil }
        out = personLimited

        // Weichzeichnen und wieder auf die Bildgröße beschneiden — `blur`
        // vergrößert sonst den Rahmen und die Maske passt nicht mehr.
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = out.clampedToExtent()
        blur.radius = Float(max(image.extent.width, image.extent.height) * 0.004)
        return (blur.outputImage ?? out).cropped(to: image.extent)
    }
}
