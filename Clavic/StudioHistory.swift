//
//  StudioHistory.swift
//  Clavic
//
//  Nicht-destruktiver Verlauf fuer den Studio-Tab. Ein Snapshot enthaelt auch
//  das aktuelle Basisbild: dadurch lassen sich nicht nur lokale Regler,
//  sondern auch fertige AI-Schritte wieder rueckgaengig machen.
//

import UIKit

struct StudioSnapshot {
    let original: UIImage
    let preview: UIImage
    let edits: PhotoEdits
    let bodyAnalysis: BodyAnalysis
    let faceAnalysis: FaceAnalysis
}

struct StudioHistory {
    private(set) var undoStack: [StudioSnapshot] = []
    private(set) var redoStack: [StudioSnapshot] = []
    let limit: Int

    init(limit: Int = 12) {
        self.limit = max(1, limit)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func remember(_ snapshot: StudioSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll(keepingCapacity: true)
    }

    mutating func undo(from current: StudioSnapshot) -> StudioSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        if redoStack.count > limit {
            redoStack.removeFirst(redoStack.count - limit)
        }
        return previous
    }

    mutating func redo(from current: StudioSnapshot) -> StudioSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        return next
    }

    mutating func reset() {
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
    }
}
