//
//  SubjectDetector.swift
//  Clavic
//
//  „Ist auf diesem Bild ueberhaupt ein Mensch?"
//
//  Der Grund fuer diese Datei ist ein gemessener Fehler (06.08.2026): Ein
//  Nutzer wollte im Studio ein AUTO gegen ein anderes Auto tauschen und schrieb
//  „swap the car to the car in the image". Der gemeinsame Prompt-Booster haengte
//  daran unbesehen „Keep the same subject — same face and hairstyle" — eine
//  Anweisung, die bei einem Autofoto nur erfuellbar ist, indem das Modell einen
//  Menschen ERFINDET. Genau das ist passiert.
//
//  Deshalb entscheidet ab jetzt das Bild, nicht der Text: ist niemand zu sehen,
//  faellt jede Personen-Klausel weg und wird durch ein ausdrueckliches Verbot
//  ersetzt, Personen hinzuzufuegen.
//

import UIKit
import Vision

enum SubjectDetector {

    /// `true` = mindestens ein Mensch erkennbar, `false` = keiner, `nil` = die
    /// Analyse war nicht moeglich (dann formuliert der Booster neutral, statt
    /// zu raten).
    static func hasPerson(in image: UIImage) async -> Bool? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                let faces = VNDetectFaceRectanglesRequest()
                let bodies = VNDetectHumanRectanglesRequest()
                do {
                    try handler.perform([faces, bodies])
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let hasFace = !(faces.results?.isEmpty ?? true)
                // Koerper ohne sichtbares Gesicht (von hinten, angeschnitten)
                // zaehlen mit — aber nur ab einer belastbaren Sicherheit, sonst
                // meldet Vision auch Schaufensterpuppen und Plakate.
                let hasBody = (bodies.results ?? []).contains { $0.confidence > 0.45 }
                continuation.resume(returning: hasFace || hasBody)
            }
        }
    }
}
