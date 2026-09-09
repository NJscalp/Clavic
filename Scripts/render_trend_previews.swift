// Run from the repository root: swift scripts/render_trend_previews.swift
// Classical Core Image colour editing only. No generative model, warping or retouching.
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Clavic/Assets.xcassets")
let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let extent = CGRect(x: 0, y: 0, width: 768, height: 1024)

func source(_ path: String) -> CIImage {
    let raw = CIImage(contentsOf: root.appendingPathComponent(path), options: [.applyOrientationProperty: true])!
    let r = raw.extent
    let width = min(r.width, r.height * 0.75)
    let height = width / 0.75
    let crop = CGRect(x: r.midX - width / 2, y: r.midY - height / 2, width: width, height: height)
    return raw.cropped(to: crop)
        .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        .transformed(by: CGAffineTransform(scaleX: 768 / width, y: 1024 / height))
        .cropped(to: extent)
}

func matrix(_ image: CIImage, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
            bias: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)) -> CIImage {
    image.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
        "inputBiasVector": CIVector(x: bias.0, y: bias.1, z: bias.2, w: 0)
    ])
}

func save(_ image: CIImage, name: String) throws {
    let folder = assets.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("\(name).jpg")
    try context.writeJPEGRepresentation(of: image.cropped(to: extent), to: file,
        colorSpace: space, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92])
    let contents: [String: Any] = ["images": [["filename": "\(name).jpg", "idiom": "universal"]],
                                   "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: folder.appendingPathComponent("Contents.json"))
}

let beach = source("docs/trend-photo-sources/jack-dong-beach.jpg")
let street = source("Clavic/Assets.xcassets/director_real_car.imageset/director_real_car.jpg")
let portrait = source("docs/trend-photo-sources/sunset-woman.jpg")

// Preserve the real flash already present in the photograph; clarify its colour response.
let flash = matrix(street, 1.015, 1.015, 1.04)
    .applyingFilter("CIColorControls", parameters: ["inputContrast": 1.09, "inputSaturation": 1.04])
    .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 0.6, "inputShadowAmount": 0.05])
let golden = matrix(beach, 1.12, 0.985, 0.925, bias: (0.012, 0, 0.004))
    .applyingFilter("CIColorControls", parameters: ["inputContrast": 1.07, "inputSaturation": 1.13])
    .applyingFilter("CIExposureAdjust", parameters: ["inputEV": 0.16])
let digicam = matrix(portrait, 0.91, 1.025, 1.14)
    .applyingFilter("CIColorControls", parameters: ["inputContrast": 1.20, "inputSaturation": 1.12])
    .applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.35])
let blue = matrix(beach, 0.76, 0.94, 1.23, bias: (0, 0, 0.025))
    .applyingFilter("CIExposureAdjust", parameters: ["inputEV": -0.55])
    .applyingFilter("CIColorControls", parameters: ["inputContrast": 1.08, "inputSaturation": 0.97])

for (id, original, edited) in [("g7xflash", street, flash), ("goldenhour", beach, golden),
                                ("y2kdigicam", portrait, digicam), ("bluehour", beach, blue)] {
    try save(original, name: "trend_\(id)_before")
    try save(edited, name: "trend_\(id)_after")
    print("Saved \(id): original and colour edit, 768 × 1024")
}
