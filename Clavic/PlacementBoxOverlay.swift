//
//  PlacementBoxOverlay.swift
//  Clavic
//
//  Der Vorschlag aus dem PlacementSuggester ist nur dann etwas wert, wenn er
//  ohne ein Wort Erklärung verstanden wird. Deshalb keine Beschriftung, die
//  erklärt, was passiert — sondern eine Form, die jeder schon kennt: ein
//  Rahmen mit Eckwinkeln, so wie ihn jede Kamera für „hier" benutzt.
//
//  Und deshalb auch KEIN Text wie „Hier stehst du". Wer das Telefon hochhält
//  und sich dreht, liest nicht. Stattdessen sagt die Farbe alles: der Rahmen
//  und der Standpunkt darin sind weiß, solange die Kamera noch sucht, und
//  springen auf Gelb, sobald der Winkel stimmt. Man dreht, bis es gelb wird,
//  und drückt ab.
//
//  Die Box gehört der Nutzerin, nicht dem Algorithmus. Sobald sie sie
//  anfasst, gewinnt ihre Position — und zwar dauerhaft, bis sie über den
//  „Auto"-Chip ausdrücklich zurückgibt. Ein Vorschlag, der die eigene
//  Entscheidung eine Sekunde später wieder überschreibt, wäre schlimmer als
//  gar kein Vorschlag.
//
//  Der „Auto"-Chip sitzt in der oberen rechten Ecke des BILDES, nicht der Box:
//  die Box steht oft schon am oberen Rand, dort wäre kein Platz für ihn — und
//  ein Bedienelement, das mit der Box wandert, ist schwerer wiederzufinden.
//

import SwiftUI

struct PlacementBoxOverlay: View {

    let suggestion: PlacementSuggestion?
    /// Vom Nutzer überschriebene Box. Ist sie gesetzt, gewinnt sie immer.
    @Binding var manualRect: CGRect?
    /// Bildgröße des angezeigten Kameraframes in Punkten.
    let frameSize: CGSize

    /// Ausgangslage der laufenden Geste. Ohne sie würde jede Änderung auf dem
    /// schon verschobenen Stand aufsetzen und die Box davonlaufen.
    @State private var gestureStart: CGRect?
    @State private var isInteracting = false

    // MARK: - Ableitungen

    private var effectiveRect: CGRect? {
        manualRect ?? suggestion?.rect
    }

    /// Unter 0.35 Confidence ist der Vorschlag geraten — dann lieber nichts
    /// zeigen als in die falsche Ecke zeigen. Eine gesetzte Handposition
    /// bleibt davon unberührt.
    private var isVisible: Bool {
        guard effectiveRect != nil else { return false }
        if manualRect != nil { return true }
        return (suggestion?.confidence ?? 0) >= 0.35
    }

    /// Sobald die Nutzerin die Box selbst gesetzt hat, gilt ihre Entscheidung
    /// als die richtige — dann leuchtet es gelb, ohne dass ein Algorithmus
    /// darüber abstimmt.
    private var isReady: Bool {
        if manualRect != nil { return true }
        return suggestion?.isReadyForTheShot ?? false
    }

    private var guideColor: Color {
        isReady ? Theme.cameraGuideReady : Theme.cameraGuide
    }

    private var boxInPoints: CGRect? {
        guard let effectiveRect, frameSize.width > 0, frameSize.height > 0 else { return nil }
        return CGRect(
            x: effectiveRect.minX * frameSize.width,
            y: effectiveRect.minY * frameSize.height,
            width: effectiveRect.width * frameSize.width,
            height: effectiveRect.height * frameSize.height
        )
    }

    // MARK: - Aufbau

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let boxInPoints, isVisible {
                box(in: boxInPoints)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }

            if manualRect != nil {
                autoChip
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(Theme.screenPadding)
                    .transition(.opacity)
            }
        }
        .frame(width: frameSize.width, height: frameSize.height, alignment: .topLeading)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: manualRect != nil)
        // Während einer Geste darf nichts nachfedern, sonst klebt die Box
        // spürbar hinter dem Finger.
        .animation(isInteracting ? nil : .spring(response: 0.35, dampingFraction: 0.85),
                   value: effectiveRect)
        .animation(.easeInOut(duration: 0.22), value: isReady)
    }

    private func box(in rect: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .fill(guideColor.opacity(isReady ? 0.12 : 0.06))

            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(guideColor.opacity(0.9), lineWidth: 2)
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 0)

            CornerTicks(cornerRadius: Theme.cornerLarge, length: 18)
                .stroke(guideColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Der Standpunkt: unten mittig, dort wo die Füße hinkommen. Er ist
            // der Punkt, den man auf die Stelle im Raum legt.
            standingPoint
                .offset(y: rect.height / 2)
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .gesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        // `position` statt `offset`: `offset` verschiebt nur das Gezeichnete,
        // die Box lag fuer die Beruehrung weiterhin in der Ecke — sie war
        // sichtbar, aber nicht zu fassen. `position` setzt die Lage selbst.
        .position(x: rect.midX, y: rect.midY)
    }

    /// Ring mit Kern, gut sichtbar auf hellem wie dunklem Grund. Wenn der
    /// Winkel stimmt, wächst er kurz auf — die Bewegung sieht man aus dem
    /// Augenwinkel, die Farbe allein nicht.
    private var standingPoint: some View {
        ZStack {
            Circle()
                .strokeBorder(guideColor, lineWidth: 2)
                .frame(width: 22, height: 22)
            Circle()
                .fill(guideColor)
                .frame(width: 7, height: 7)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 4)
        .scaleEffect(isReady ? 1.18 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isReady)
    }

    private var autoChip: some View {
        Button {
            manualRect = nil
        } label: {
            Label("Auto", systemImage: "wand.and.stars")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.surface.opacity(0.9)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Restore the suggested spot")
    }

    // MARK: - Gesten

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard frameSize.width > 0, frameSize.height > 0 else { return }
                let base = beginGesture()
                isInteracting = true
                manualRect = clamped(
                    CGRect(
                        x: base.minX + value.translation.width / frameSize.width,
                        y: base.minY + value.translation.height / frameSize.height,
                        width: base.width,
                        height: base.height
                    )
                )
            }
            .onEnded { _ in
                gestureStart = nil
                isInteracting = false
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = beginGesture()
                isInteracting = true
                // Seitenverhältnis bleibt fest: die Box beschreibt einen
                // Menschen, kein beliebiges Rechteck.
                let ratio = base.height > 0 ? base.width / base.height : 0.38
                let width = min(max(base.width * value.magnification, 0.06), 0.9)
                let height = min(max(ratio > 0 ? width / ratio : base.height, 0.08), 0.98)
                manualRect = clamped(
                    CGRect(
                        x: base.midX - width / 2,
                        y: base.midY - height / 2,
                        width: width,
                        height: height
                    )
                )
            }
            .onEnded { _ in
                gestureStart = nil
                isInteracting = false
            }
    }

    /// Beide Gesten laufen gegen denselben Ausgangsstand — sonst würde
    /// gleichzeitiges Ziehen und Skalieren einander aufschaukeln.
    private func beginGesture() -> CGRect {
        if let gestureStart { return gestureStart }
        let base = effectiveRect ?? CGRect(x: 0.33, y: 0.30, width: 0.16, height: 0.42)
        gestureStart = base
        return base
    }

    /// Die Box bleibt immer vollständig im Bild.
    private func clamped(_ rect: CGRect) -> CGRect {
        let width = min(rect.width, 1)
        let height = min(rect.height, 1)
        return CGRect(
            x: min(max(rect.minX, 0), 1 - width),
            y: min(max(rect.minY, 0), 1 - height),
            width: width,
            height: height
        )
    }
}

/// Vier kurze Eckwinkel — der Teil, der die Form als „Kamera-Rahmen" lesbar
/// macht. Sie setzen erst hinter der Rundung an, damit sie auf der Kante
/// liegen und nicht in sie hineinlaufen.
private struct CornerTicks: Shape {
    let cornerRadius: CGFloat
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let horizontal = min(length, max(0, rect.width / 2 - radius))
        let vertical = min(length, max(0, rect.height / 2 - radius))

        // oben links
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius + horizontal, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius + vertical))

        // oben rechts
        path.move(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius - horizontal, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius + vertical))

        // unten links
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius + horizontal, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius - vertical))

        // unten rechts
        path.move(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius - horizontal, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - vertical))

        return path
    }
}
