//
//  BeforeAfterSlider.swift
//  Clavic
//
//  Vorher/Nachher-Vorschau: zwei überlappende Bilder mit einer
//  Trennlinie, die automatisch sauber von links nach rechts und
//  zurück wandert – ideal für Bild-Edit-Trends.
//

import SwiftUI

struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage

    /// Dauer eines kompletten Durchlaufs (links → rechts).
    var sweepDuration: Double = 2.4
    var showLabels: Bool = true

    @State private var fraction: CGFloat = 0.18

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .leading) {
                // Vorher (Hintergrund)
                Image(uiImage: before)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                // Nachher (oben, durch die wandernde Maske freigelegt)
                Image(uiImage: after)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, w * fraction))
                    }

                // Trennlinie + Griff
                ZStack {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2.5)
                        .shadow(color: .black.opacity(0.35), radius: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                        .overlay(
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 0.36, green: 0.42, blue: 0.95))
                        )
                }
                .frame(width: 26, height: h)
                .offset(x: w * fraction - 13)

                if showLabels {
                    labels(width: w, height: h)
                }
            }
            .frame(width: w, height: h)
            .onAppear {
                fraction = 0.18
                withAnimation(.easeInOut(duration: sweepDuration).repeatForever(autoreverses: true)) {
                    fraction = 0.82
                }
            }
        }
    }

    private func labels(width: CGFloat, height: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack {
                badge("Vorher")
                Spacer()
                badge("Nachher")
            }
            .padding(8)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
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
