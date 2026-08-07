//
//  LuxuryCar.swift
//  Clavic
//
//  „Luxury Car Selfie": Nutzer-Selfie + Automarke → GPT Image 2 setzt die Person
//  ins passende Luxus-Interieur (gleiche Logik wie clavic-web `carselfie`-Flow).
//

import Foundation

enum LuxuryCar {

    enum Brand: String, CaseIterable, Identifiable {
        case rollsRoyce = "Rolls-Royce"
        case ferrari = "Ferrari"
        case lamborghini = "Lamborghini"
        case porsche = "Porsche"
        case bentley = "Bentley"
        case mercedesMaybach = "Mercedes-Maybach"

        var id: String { rawValue }
        var label: String { rawValue }

        var interiorDescription: String {
            switch self {
            case .rollsRoyce:
                return "the tan leather interior of a Rolls-Royce, with the double-R 'RR' emblem embossed on the headrest, a starlight headliner with tiny lights on the ceiling"
            case .ferrari:
                return "the red and black leather interior of a Ferrari, with the yellow prancing-horse Ferrari shield emblem visible on the headrest or steering wheel, carbon fiber trim"
            case .lamborghini:
                return "the black and yellow alcantara interior of a Lamborghini, with the gold Lamborghini bull shield emblem visible on the seat or steering wheel, angular carbon fiber trim"
            case .porsche:
                return "the black leather interior of a Porsche, with the Porsche crest emblem visible on the headrest, clean minimal cabin design"
            case .bentley:
                return "the quilted diamond-stitched leather interior of a Bentley, with the winged Bentley emblem embossed on the headrest, polished wood veneer trim"
            case .mercedesMaybach:
                return "the two-tone quilted leather interior of a Mercedes-Maybach, with the three-pointed star Mercedes emblem visible on the headrest, ambient interior lighting"
            }
        }
    }

    static func buildPrompt(brand: Brand) -> String {
        """
        Keep the exact same person, face, identity, hairstyle and outfit from the photo. \
        Replace the background and setting so the person is taking a selfie sitting inside \(brand.interiorDescription). \
        Match the selfie framing, angle and close-up look of the original photo, with realistic interior lighting and reflections on the leather. \
        Photorealistic, no text, no watermark.
        """
    }
}
