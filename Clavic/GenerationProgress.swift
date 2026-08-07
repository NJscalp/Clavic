//
//  GenerationProgress.swift
//  Clavic
//
//  Ehrliche Wartezeit-Anzeige unter jedem Ladeplatzhalter.
//
//  Hintergrund: die Poll-Schleifen warten jetzt bis zu 10 Minuten, weil ein
//  4K-Bild bei GPT Image 2 GEMESSEN rund 282 Sekunden braucht. Ein stiller
//  Spinner fühlt sich in dieser Zeit wie ein Absturz an — der Nutzer bricht ab
//  (und zahlt trotzdem, weil WaveSpeed weiterrechnet). Deshalb steht hier
//  sichtbar, wie lange es schon läuft und wie lange es üblicherweise dauert.
//
//  Die Schätzwerte sind gemessen, nicht geraten (siehe [[clavic-poll-timeout]]):
//  1K ≈ 35 s, 2K ≈ 60 s, 4K ≈ 285 s.
//

import SwiftUI

struct GenerationProgress: View {
    let startedAt: Date
    /// Übliche Dauer in Sekunden für die gewählte Qualität.
    let estimate: TimeInterval
    /// Auf dunklem Untergrund (Blur-Karte) wird heller gezeichnet.
    var onDark: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            // Nie ganz voll: solange nichts zurückkam, ist es nicht fertig.
            // Ein Balken, der auf 100 % steht und weiterläuft, ist eine Lüge.
            let fraction = min(elapsed / max(estimate, 1), 0.97)
            let overdue = elapsed > estimate

            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(trackColor)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(6, geo.size.width * fraction))
                            .animation(.linear(duration: 1), value: fraction)
                    }
                }
                .frame(height: 3)

                Text(caption(elapsed: elapsed, overdue: overdue))
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var trackColor: Color {
        onDark ? .white.opacity(0.25) : .black.opacity(0.10)
    }

    private var textColor: Color {
        onDark ? .white.opacity(0.85) : Theme.textSecondary
    }

    private func caption(elapsed: TimeInterval, overdue: Bool) -> String {
        let running = Self.clock(elapsed)
        if overdue {
            // Über der Schätzung NICHT auf Fehler umschalten — bei 4K ist das
            // normal. Nur sagen, dass weiter gearbeitet wird.
            return "\(running) · taking a bit longer — still working"
        }
        let left = Self.rough(estimate - elapsed)
        return "\(running) · about \(left) left"
    }

    /// mm:ss — die vergangene Zeit ist eine Tatsache und wird exakt gezeigt.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Die Restzeit ist eine Schätzung und wird bewusst grob gerundet —
    /// eine sekundengenaue Restanzeige, die springt, wirkt kaputt.
    static func rough(_ seconds: TimeInterval) -> String {
        let s = max(seconds, 0)
        if s < 20 { return "10 sec" }
        if s < 60 { return "\(Int((s / 15).rounded()) * 15) sec" }
        let minutes = Int((s / 60).rounded(.up))
        return minutes == 1 ? "1 min" : "\(minutes) min"
    }
}
