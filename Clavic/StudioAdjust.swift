//
//  StudioAdjust.swift
//  Clavic
//
//  Die Licht- und Haut-Regler als AUSWÄHLBARE Werkzeuge statt als Stapel.
//
//  Vorher standen im Studio fünf Schieberegler untereinander, und die Höhe des
//  Menüs änderte sich je nach Reiter — dadurch sprang das Bild bei jedem
//  Wechsel in eine andere Größe. Jetzt gilt überall dieselbe Bauform wie im
//  Body-Bereich: eine waagerecht scrollende Icon-Leiste, darüber EIN Regler
//  für das gerade gewählte Werkzeug. Das Menü hat damit eine feste Höhe, und
//  das Bild bleibt immer gleich groß.
//

import SwiftUI

/// Ein einzelner Regler. `keyPath` zeigt direkt in `PhotoEdits`, damit die
/// Leiste ohne Sonderfälle für jeden Wert funktioniert.
struct AdjustTool: Identifiable {
    let id: String
    let label: String
    let icon: String
    let keyPath: WritableKeyPath<PhotoEdits, Double>
    /// Bereich des Reglers. Werte mit natürlichem Nullpunkt gehen von −1 bis 1,
    /// reine Verstärker (Schärfe, Glow) von 0 bis 1.
    let range: ClosedRange<Double>

    var isBipolar: Bool { range.lowerBound < 0 }
}

enum StudioTools {
    /// Vollstaendiger Foto-Regler-Satz. Die Reihenfolge ist absichtlich von
    /// grossen Tonwerten zu Finish-Effekten aufgebaut.
    static let adjust: [AdjustTool] = [
        AdjustTool(id: "exposure",   label: "Exposure",   icon: "sun.max",            keyPath: \.exposure,   range: -1...1),
        AdjustTool(id: "highlights", label: "Highlights", icon: "sun.max.fill",       keyPath: \.highlights, range: -1...1),
        AdjustTool(id: "shadows",    label: "Shadows",    icon: "moon.fill",          keyPath: \.shadows,    range: -1...1),
        AdjustTool(id: "contrast",   label: "Contrast",   icon: "circle.lefthalf.filled", keyPath: \.contrast, range: -1...1),
        AdjustTool(id: "saturation", label: "Saturation", icon: "drop.halffull",      keyPath: \.saturation, range: -1...1),
        AdjustTool(id: "warmth",     label: "Warmth",     icon: "thermometer.medium", keyPath: \.warmth,     range: -1...1),
        AdjustTool(id: "sharpen",    label: "Sharpen",    icon: "triangle",           keyPath: \.sharpen,    range:  0...1),
        AdjustTool(id: "vignette",   label: "Vignette",   icon: "circle.dotted",      keyPath: \.vignette,   range:  0...1),
        AdjustTool(id: "fade",       label: "Fade",       icon: "cloud.fog",          keyPath: \.fade,       range:  0...1),
        AdjustTool(id: "grain",      label: "Grain",      icon: "circle.grid.cross",  keyPath: \.grain,      range:  0...1),
    ]

    /// Legacy-Name fuer bestehende Aufrufstellen waehrend der UI-Migration.
    static let light = adjust

    static let retouch: [AdjustTool] = [
        AdjustTool(id: "skinTone", label: "Tone",      icon: "person.fill",      keyPath: \.skinTone, range: -1...1),
        AdjustTool(id: "smooth",   label: "Smooth",    icon: "aqi.medium",       keyPath: \.smooth, range: 0...1),
        AdjustTool(id: "evenSkin", label: "Even",      icon: "circle.hexagongrid", keyPath: \.evenSkin, range: 0...1),
        AdjustTool(id: "redness",  label: "Redness",   icon: "cross.case",       keyPath: \.redness, range: 0...1),
        AdjustTool(id: "matte",    label: "Matte",     icon: "drop.degreesign",  keyPath: \.matte, range: 0...1),
    ]

    static let skin = retouch
}
