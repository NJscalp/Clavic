//
//  EraseCanvas.swift
//  Clavic
//
//  Remove has two deliberately separate stages:
//
//  1. A live, local stroke mask. It follows the finger without waiting for an
//     AI request and remains the source of truth for the selected pixels.
//  2. A generated result. It is composited back only through that mask, so an
//     image model cannot silently redraw the rest of the photograph.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import Vision

/// A painted line in relative image coordinates (0...1). Keeping both the
/// points and width relative makes one stroke line up with preview and export.
struct EraseStroke: Equatable {
    var points: [CGPoint] = []
    /// Brush width relative to the image width.
    var width: Double
}

/// Reusable, non-interactive live visualization of a Remove mask.
///
/// `EraseCanvas` uses this view while drawing, but it can also be placed over a
/// progress preview after submission. It intentionally never intercepts input.
struct EraseMaskPreview: View {
    let strokes: [EraseStroke]
    let imageRect: CGRect
    var tint = Color(red: 0.35, green: 0.78, blue: 1.0)

    var body: some View {
        Canvas { context, _ in
            guard imageRect.width > 0, imageRect.height > 0 else { return }
            context.clip(to: Path(imageRect))
            for stroke in strokes {
                EraseStrokeDrawing.draw(
                    stroke,
                    imageRect: imageRect,
                    tint: tint,
                    context: &context
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Interactive painting surface. The active stroke is inserted into the
/// binding immediately and updated on every drag event. This is important:
/// parent views and progress overlays always see the exact mask under the
/// finger instead of receiving it only after the gesture ends.
struct EraseCanvas: View {
    @Binding var strokes: [EraseStroke]
    var brush: Double
    /// Area occupied by the aspect-fitted image inside the canvas.
    let imageRect: CGRect

    @State private var activeStrokeIndex: Int?

    var body: some View {
        EraseMaskPreview(strokes: strokes, imageRect: imageRect)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateStroke(at: value.location, mayBegin: true)
                    }
                    .onEnded { value in
                        // DragGesture can deliver a final position that was not
                        // part of the last onChanged callback. Preserve it so a
                        // quick flick never leaves the line visually hanging.
                        updateStroke(at: value.location, mayBegin: false)
                        activeStrokeIndex = nil
                    }
            )
            .onDisappear { activeStrokeIndex = nil }
    }

    private func updateStroke(at location: CGPoint, mayBegin: Bool) {
        guard imageRect.width > 0, imageRect.height > 0 else { return }

        if let index = activeStrokeIndex, strokes.indices.contains(index) {
            var stroke = strokes[index]
            appendInterpolatedPoint(relative(location), to: &stroke)
            strokes[index] = stroke
            return
        }

        // A stroke must start on the photograph. Once it has started, its
        // coordinates are clamped at the edge while the finger is outside.
        guard mayBegin, imageRect.contains(location) else {
            activeStrokeIndex = nil
            return
        }

        strokes.append(
            EraseStroke(
                points: [relative(location)],
                width: min(max(brush, 0.001), 1)
            )
        )
        activeStrokeIndex = strokes.index(before: strokes.endIndex)
    }

    private func appendInterpolatedPoint(_ point: CGPoint, to stroke: inout EraseStroke) {
        guard let last = stroke.points.last else {
            stroke.points = [point]
            return
        }

        let lastAbsolute = absolute(last)
        let nextAbsolute = absolute(point)
        let distance = hypot(nextAbsolute.x - lastAbsolute.x,
                             nextAbsolute.y - lastAbsolute.y)
        guard distance >= 0.35 else { return }

        // More points than the gesture system supplies make tight curves and
        // fast flicks continuous. The cap prevents a single event after an app
        // hitch from allocating an unbounded number of points.
        let maximumStep = max(1.5, CGFloat(stroke.width) * imageRect.width * 0.24)
        let steps = min(max(Int(ceil(distance / maximumStep)), 1), 64)
        for step in 1...steps {
            let amount = CGFloat(step) / CGFloat(steps)
            stroke.points.append(
                CGPoint(
                    x: last.x + (point.x - last.x) * amount,
                    y: last.y + (point.y - last.y) * amount
                )
            )
        }
    }

    private func relative(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: clamp((point.x - imageRect.minX) / max(imageRect.width, 1)),
            y: clamp((point.y - imageRect.minY) / max(imageRect.height, 1))
        )
    }

    private func absolute(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + point.y * imageRect.height
        )
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private enum EraseStrokeDrawing {
    static func draw(_ stroke: EraseStroke, imageRect: CGRect, tint: Color,
                     context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }
        let width = max(CGFloat(stroke.width) * imageRect.width, 1)

        func absolute(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: imageRect.minX + point.x * imageRect.width,
                y: imageRect.minY + point.y * imageRect.height
            )
        }

        if stroke.points.count == 1 {
            let center = absolute(first)
            // Mehr Licht als Farbe: Die Auswahl soll wie ein leichter Neon-Glow
            // wirken und niemals das eigentliche Foto verdecken.
            drawDot(center: center, width: width * 2.65,
                    color: tint.opacity(0.035), context: &context)
            drawDot(center: center, width: width * 1.85,
                    color: tint.opacity(0.075), context: &context)
            drawDot(center: center, width: width * 1.28,
                    color: tint.opacity(0.16), context: &context)
            drawDot(center: center, width: width,
                    color: tint.opacity(0.28), context: &context)
            return
        }

        var path = Path()
        path.move(to: absolute(first))
        for point in stroke.points.dropFirst() {
            path.addLine(to: absolute(point))
        }
        context.stroke(
            path,
            with: .color(tint.opacity(0.035)),
            style: StrokeStyle(lineWidth: width * 2.65,
                               lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(tint.opacity(0.075)),
            style: StrokeStyle(lineWidth: width * 1.85,
                               lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(tint.opacity(0.16)),
            style: StrokeStyle(lineWidth: width * 1.28,
                               lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(tint.opacity(0.28)),
            style: StrokeStyle(lineWidth: width,
                               lineCap: .round, lineJoin: .round)
        )
    }

    private static func drawDot(center: CGPoint, width: CGFloat, color: Color,
                                context: inout GraphicsContext) {
        let rect = CGRect(x: center.x - width / 2, y: center.y - width / 2,
                          width: width, height: width)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

enum EraseMask {
    /// Canonical inputs for one Remove operation. `base`, `marked`, and `mask`
    /// are upright, scale-1 images with exactly the same pixel dimensions.
    /// Keeping them together prevents the two-reference mismatch that occurs
    /// when one image is made before local edits and one after them.
    struct Prepared {
        let base: UIImage
        let marked: UIImage
        let mask: UIImage
        let strokes: [EraseStroke]
    }

    private static let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
    ])

    /// Normalizes EXIF orientation and UIKit scale into an upright, scale-1
    /// image whose point dimensions equal its physical pixel dimensions.
    static func canonicalBase(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let oriented = source.oriented(forExifOrientation: image.exifOrientation)
        let integralExtent = oriented.extent.integral
        guard integralExtent.width > 0, integralExtent.height > 0 else { return nil }

        let translated = oriented.transformed(by: CGAffineTransform(
            translationX: -integralExtent.minX,
            y: -integralExtent.minY
        ))
        let outputExtent = CGRect(origin: .zero, size: integralExtent.size)
        let colorSpace = rgbColorSpace(for: cgImage)
        guard let output = context.createCGImage(
            translated,
            from: outputExtent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else { return nil }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }

    /// Creates every input from one canonical base. Callers should retain this
    /// value until the request succeeds, rather than rebuilding one reference
    /// from a newer or older editor state.
    static func prepare(base image: UIImage, strokes: [EraseStroke]) -> Prepared? {
        let safeStrokes = sanitized(strokes)
        guard !safeStrokes.isEmpty,
              let base = canonicalBase(image),
              let mask = strokeMask(for: base, strokes: safeStrokes),
              let marked = markedCanonical(base, strokes: safeStrokes) else {
            return nil
        }
        return Prepared(base: base, marked: marked, mask: mask,
                        strokes: safeStrokes)
    }

    /// Erkennt den größten klar vom Hintergrund getrennten Gegenstand direkt
    /// auf dem Gerät. Das Ergebnis wird in dieselben Pinselzüge übersetzt wie
    /// eine manuelle Auswahl, damit Vorschau, Prompt und finale Komposition
    /// weiterhin exakt denselben Auswahlraum verwenden.
    static func largestForegroundObjectStrokes(in image: UIImage) -> [EraseStroke] {
        guard let base = canonicalBase(image), let cg = base.cgImage else { return [] }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first else { return [] }

        var best: (pixelCount: Int, strokes: [EraseStroke])?
        for index in observation.allInstances {
            let selection = IndexSet(integer: index)
            guard let buffer = try? observation.generateMask(forInstances: selection),
                  let candidate = strokes(forForegroundMask: buffer),
                  !candidate.strokes.isEmpty else { continue }
            if best == nil || candidate.pixelCount > best!.pixelCount {
                best = candidate
            }
        }
        return best?.strokes ?? []
    }

    /// Verdichtet die Vision-Maske in horizontale, leicht überlappende Züge.
    /// 40–55 Züge sind wesentlich leichter zu zeichnen als tausende Punkte,
    /// decken den Gegenstand aber dicht genug für das Inpainting ab.
    private static func strokes(forForegroundMask buffer: CVPixelBuffer)
        -> (pixelCount: Int, strokes: [EraseStroke])? {
        let image = CIImage(cvPixelBuffer: buffer)
        let width = max(Int(image.extent.width.rounded()), 1)
        let height = max(Int(image.extent.height.rounded()), 1)
        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width,
            bounds: CGRect(x: image.extent.minX, y: image.extent.minY,
                           width: CGFloat(width), height: CGFloat(height)),
            format: .L8,
            colorSpace: nil
        )

        let threshold: UInt8 = 32
        let count = pixels.reduce(into: 0) { total, value in
            if value >= threshold { total += 1 }
        }
        guard count >= max(10, width * height / 2_000) else { return nil }

        let rowStep = max(2, height / 48)
        let brushWidth = min(0.13, max(0.018,
            Double(rowStep) * 1.75 / Double(max(width, 1))))
        var result: [EraseStroke] = []

        for y in stride(from: 0, to: height, by: rowStep) {
            let row = y * width
            var x = 0
            while x < width {
                while x < width && pixels[row + x] < threshold { x += 1 }
                let start = x
                while x < width && pixels[row + x] >= threshold { x += 1 }
                let end = x - 1
                // Kein eigener Strich für einzelne, unsichere Maskenpixel.
                guard end >= start, end - start >= max(1, width / 160) else { continue }
                let relativeY = 1 - (CGFloat(y) + CGFloat(rowStep) * 0.5) / CGFloat(height)
                result.append(EraseStroke(
                    points: [
                        CGPoint(x: CGFloat(start) / CGFloat(width), y: relativeY),
                        CGPoint(x: CGFloat(end) / CGFloat(width), y: relativeY)
                    ],
                    width: brushWidth
                ))
            }
        }
        return (count, result)
    }

    /// Compatibility helper for existing call sites. New Remove flows should
    /// retain `prepare(base:strokes:)`, then pass the same Prepared value to
    /// `composite(_:using:)` when the AI result arrives.
    static func marked(_ image: UIImage, strokes: [EraseStroke]) -> UIImage? {
        prepare(base: image, strokes: strokes)?.marked
    }

    /// Restricts a generated image to the selected region. The result is first
    /// normalized and mapped to the base pixel grid. The stroke mask is then
    /// expanded to cover object edges and softly feathered; mathematically, all
    /// pixels where the mask is black come directly from `prepared.base`.
    ///
    /// Expansion and feather are relative to base width, matching brush width.
    static func composite(
        _ generatedImage: UIImage,
        using prepared: Prepared,
        expansion: Double = 0.012,
        feather: Double = 0.006
    ) -> UIImage? {
        guard let baseCG = prepared.base.cgImage,
              let generated = canonicalBase(generatedImage),
              let generatedCG = generated.cgImage,
              let maskCG = prepared.mask.cgImage else { return nil }

        let extent = CGRect(x: 0, y: 0,
                            width: baseCG.width, height: baseCG.height)
        guard extent.width > 0, extent.height > 0 else { return nil }

        let baseCI = CIImage(cgImage: baseCG)
        let generatedCI = CIImage(cgImage: generatedCG)
        let scaledGenerated = generatedCI
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / generatedCI.extent.width,
                y: extent.height / generatedCI.extent.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: -generatedCI.extent.minX,
                y: -generatedCI.extent.minY
            ))
            .cropped(to: extent)

        var maskCI = CIImage(cgImage: maskCG).cropped(to: extent)
        let expansionPixels = max(0, min(expansion, 0.25)) * extent.width
        if expansionPixels > 0.5 {
            let dilate = CIFilter.morphologyMaximum()
            dilate.inputImage = maskCI
            dilate.radius = Float(expansionPixels)
            maskCI = (dilate.outputImage ?? maskCI).cropped(to: extent)
        }

        let featherPixels = max(0, min(feather, 0.10)) * extent.width
        if featherPixels > 0.25 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = maskCI.clampedToExtent()
            blur.radius = Float(featherPixels)
            maskCI = (blur.outputImage ?? maskCI).cropped(to: extent)
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = scaledGenerated
        blend.backgroundImage = baseCI
        blend.maskImage = maskCI
        guard let composited = blend.outputImage?.cropped(to: extent) else {
            return nil
        }

        let colorSpace = rgbColorSpace(for: baseCG)
        guard let output = context.createCGImage(
            composited,
            from: extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else { return nil }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }

    /// Convenience overload when a caller does not need to retain Prepared.
    static func composite(
        _ generatedImage: UIImage,
        over baseImage: UIImage,
        strokes: [EraseStroke],
        expansion: Double = 0.012,
        feather: Double = 0.006
    ) -> UIImage? {
        guard let prepared = prepare(base: baseImage, strokes: strokes) else {
            return nil
        }
        return composite(generatedImage, using: prepared,
                         expansion: expansion, feather: feather)
    }

    private static func markedCanonical(_ base: UIImage,
                                        strokes: [EraseStroke]) -> UIImage? {
        guard let cgImage = base.cgImage else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            base.draw(in: CGRect(origin: .zero, size: size))
            draw(strokes, in: renderer.cgContext, size: size,
                 color: UIColor.magenta.cgColor)
        }
    }

    private static func strokeMask(for base: UIImage,
                                   strokes: [EraseStroke]) -> UIImage? {
        guard let cgImage = base.cgImage else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.black.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            draw(strokes, in: renderer.cgContext, size: size,
                 color: UIColor.white.cgColor)
        }
    }

    private static func draw(_ strokes: [EraseStroke], in context: CGContext,
                             size: CGSize, color: CGColor) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            let width = max(CGFloat(stroke.width) * size.width, 1)
            context.setLineWidth(width)
            if stroke.points.count == 1 {
                context.fillEllipse(in: CGRect(
                    x: first.x * size.width - width / 2,
                    y: first.y * size.height - width / 2,
                    width: width,
                    height: width
                ))
                continue
            }

            context.beginPath()
            context.move(to: CGPoint(x: first.x * size.width,
                                     y: first.y * size.height))
            for point in stroke.points.dropFirst() {
                context.addLine(to: CGPoint(x: point.x * size.width,
                                            y: point.y * size.height))
            }
            context.strokePath()
        }
    }

    private static func sanitized(_ strokes: [EraseStroke]) -> [EraseStroke] {
        strokes.compactMap { stroke in
            let points = stroke.points.compactMap { point -> CGPoint? in
                guard point.x.isFinite, point.y.isFinite else { return nil }
                return CGPoint(x: min(max(point.x, 0), 1),
                               y: min(max(point.y, 0), 1))
            }
            guard !points.isEmpty, stroke.width.isFinite else { return nil }
            return EraseStroke(points: points,
                               width: min(max(stroke.width, 0.001), 1))
        }
    }

    /// RGBA output requires an RGB colour space. Camera images normally carry
    /// sRGB or Display-P3, but screenshots and generated masks can be grayscale.
    private static func rgbColorSpace(for image: CGImage) -> CGColorSpace {
        if let colorSpace = image.colorSpace, colorSpace.model == .rgb {
            return colorSpace
        }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// Prompt for the current two-reference fallback route. A true mask-aware
    /// backend can use `Prepared.mask` directly and omit the marked reference.
    static let prompt = """
    You are given two images of the same photo. IMAGE 1 is the original. IMAGE 2 is \
    the same photo with a bright magenta marking painted on top of it.

    Return IMAGE 1 with everything that lies under the magenta marking REMOVED, and \
    the space it occupied filled in so that it looks like the object was never there. \
    Continue the surrounding background across the gap — the same wall, floor, sky, \
    fabric, skin or surface that borders the area, with matching texture, grain, \
    perspective, colour and lighting. If the removed thing cast a shadow or a \
    reflection, remove that too.

    Do NOT paint anything new into the gap, do NOT invent objects, people or text to \
    fill it, and do NOT show any magenta in the result. Everything OUTSIDE the marked \
    area must stay pixel-identical to IMAGE 1 — same framing, same crop, same colours, \
    same people, same faces. Photorealistic, indistinguishable from the untouched photo.
    """
}

private extension UIImage {
    var exifOrientation: Int32 {
        switch imageOrientation {
        case .up: return 1
        case .upMirrored: return 2
        case .down: return 3
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .right: return 6
        case .rightMirrored: return 7
        case .left: return 8
        @unknown default: return 1
        }
    }
}
