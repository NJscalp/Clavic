//
//  BeforeAfterSlider.swift
//  Clavic
//
//  Vorher/Nachher-Vorschau: zwei überlappende Bilder mit einer Trennlinie,
//  die automatisch hin und zurück wandert – ideal für Bild-Edit-Trends.
//
//  Die Richtung ist einstellbar. Auf den Kacheln läuft sie SENKRECHT, von oben
//  nach unten: die Kacheln sind hochkant, eine waagerechte Linie legt damit
//  immer das ganze Motiv frei statt nur eine schmale Spalte davon, und das
//  Raster wirkt ruhiger, weil alle Kacheln in dieselbe Richtung laufen.
//

import SwiftUI

struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage

    /// Dauer eines kompletten Durchlaufs.
    var sweepDuration: Double = 2.4
    /// Laufrichtung der Trennlinie. Senkrecht heißt: von oben nach unten.
    var axis: Axis = .horizontal
    var showLabels: Bool = true
    /// Steuert, ob der Slider animiert. Bei `false` steht er still (spart CPU,
    /// z. B. wenn die Kachel nicht sichtbar ist oder ein Sheet offen ist).
    var isAnimating: Bool = true
    /// Bei `true` kann der Nutzer die Trennlinie per Wisch steuern (Vollbild-Vergleich).
    var interactive: Bool = false
    /// true = Bild füllt (croppt); false = ganzes Bild sichtbar (Fit) mit weichem
    /// Blur-Hintergrund als Fade – so wird nichts abgeschnitten.
    var contentFill: Bool = true

    @State private var fraction: CGFloat = 0.18

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .leading) {
                // Fit-Modus: weicher Blur-Hintergrund füllt die Ränder (Fade).
                if !contentFill {
                    Image(uiImage: after)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                        .blur(radius: 22)
                        .opacity(0.5)
                }

                // Vorher (Hintergrund)
                Image(uiImage: before)
                    .resizable()
                    .aspectRatio(contentMode: contentFill ? .fill : .fit)
                    .frame(width: w, height: h)
                    .clipped()

                // Nachher (oben, durch die wandernde Maske freigelegt)
                Image(uiImage: after)
                    .resizable()
                    .aspectRatio(contentMode: contentFill ? .fill : .fit)
                    .frame(width: w, height: h)
                    .clipped()
                    .mask(alignment: axis == .horizontal ? .leading : .top) {
                        if axis == .horizontal {
                            Rectangle().frame(width: max(0, w * fraction))
                        } else {
                            Rectangle().frame(height: max(0, h * fraction))
                        }
                    }

                // Trennlinie + Griff
                ZStack {
                    Rectangle()
                        .fill(.white)
                        .frame(width: axis == .horizontal ? 2.5 : w,
                               height: axis == .horizontal ? h : 2.5)
                        .shadow(color: .black.opacity(0.35), radius: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                        .overlay(
                            Image(systemName: axis == .horizontal
                                  ? "arrow.left.and.right" : "arrow.up.and.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 0.36, green: 0.42, blue: 0.95))
                        )
                }
                .frame(width: axis == .horizontal ? 26 : w,
                       height: axis == .horizontal ? h : 26)
                .offset(x: axis == .horizontal ? w * fraction - 13 : 0,
                        y: axis == .horizontal ? 0 : h * fraction - 13)

                if showLabels {
                    labels(width: w, height: h)
                }
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(interactive ? dragGesture(width: w, height: h) : nil)
            .onAppear { updateAnimation() }
            .onChange(of: isAnimating) { _, _ in updateAnimation() }
            .onChange(of: interactive) { _, _ in updateAnimation() }
        }
    }

    private func dragGesture(width w: CGFloat, height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let raw = axis == .horizontal ? value.location.x / w : value.location.y / h
                fraction = min(0.98, max(0.02, raw))
            }
    }

    private func updateAnimation() {
        if interactive {
            fraction = 0.5
            return
        }
        if isAnimating {
            fraction = 0.18
            withAnimation(.easeInOut(duration: sweepDuration).repeatForever(autoreverses: true)) {
                fraction = 0.82
            }
        } else {
            // Animation stoppen und auf einen ruhigen Stand setzen.
            withAnimation(.easeInOut(duration: 0.2)) { fraction = 0.5 }
        }
    }

    @ViewBuilder
    private func labels(width: CGFloat, height: CGFloat) -> some View {
        if axis == .horizontal {
            VStack {
                Spacer()
                HStack {
                    badge("Before")
                    Spacer()
                    badge("After")
                }
                .padding(8)
            }
            .frame(width: width, height: height)
            .allowsHitTesting(false)
        } else {
            VStack {
                HStack { Spacer(); badge("After") }
                Spacer()
                HStack { Spacer(); badge("Before") }
            }
            .padding(8)
            .frame(width: width, height: height)
            .allowsHitTesting(false)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
    }
}
