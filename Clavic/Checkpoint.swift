//
//  Checkpoint.swift
//  Clavic
//
//  Persistenter Zwischenspeicher für mehrstufige Pipelines (Fruit Story, Build).
//  Bricht eine lange Generierung mittendrin ab (Fehler/App-Kill), bleiben die
//  bereits FERTIGEN Szenen-Clips + der aufgelöste Plan (gleiche Story) auf der
//  Platte erhalten. Beim „Continue" werden diese wiederverwendet und NUR die
//  fehlenden Szenen neu erzeugt → kein Doppelt-/Überlappen, keine erneuten kie-
//  Kosten für schon Erstelltes.
//
//  Ablage: Documents/checkpoints/<projectID>/
//    plan.json          – aufgelöster Plan (Szenen / Objekt+Setting+Finish)
//    kf_<i>.jpg         – fertiger Keyframe der Szene i
//    seg_<i>.mp4        – fertiger animierter Clip der Szene i
//

import Foundation

enum Checkpoint {

    private static func dir(_ id: UUID) -> URL {
        let d = URL.documentsDirectory.appending(path: "checkpoints/\(id.uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Plan (gleiche Story beim Resume)

    static func savePlan(_ id: UUID, _ json: String) {
        try? Data(json.utf8).write(to: dir(id).appending(path: "plan.json"))
    }
    static func loadPlan(_ id: UUID) -> String? {
        try? String(contentsOf: dir(id).appending(path: "plan.json"), encoding: .utf8)
    }

    // MARK: Datei-Bausteine (Keyframes/Clips)

    static func url(_ id: UUID, _ name: String) -> URL { dir(id).appending(path: name) }
    static func exists(_ id: UUID, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(id, name).path)
    }
    static func save(_ id: UUID, _ name: String, _ data: Data) {
        try? data.write(to: url(id, name))
    }
    static func load(_ id: UUID, _ name: String) -> Data? {
        try? Data(contentsOf: url(id, name))
    }
    /// Kopiert eine lokale Datei in den Checkpoint (für fertige Clips).
    static func adopt(_ id: UUID, _ name: String, from src: URL) {
        let dst = url(id, name)
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: src, to: dst)
    }

    /// Gibt es überhaupt schon einen fertigen Clip? (entscheidet „resumable").
    static func hasAnySegment(_ id: UUID) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir(id).path) else { return false }
        return files.contains { $0.hasPrefix("seg_") && $0.hasSuffix(".mp4") }
    }

    static func clear(_ id: UUID) {
        try? FileManager.default.removeItem(at: dir(id))
    }
}
