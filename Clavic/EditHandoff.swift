//
//  EditHandoff.swift
//  Clavic
//
//  Ein fertiges Bild ist selten fertig. Bisher endete der Solo Shot in einer
//  Sackgasse: das Ergebnis lag in der Bibliothek, und wer noch etwas ändern
//  wollte, musste es dort suchen und von Hand wieder öffnen.
//
//  Diese Ablage ist die Übergabe zwischen zwei Tabs. Sie hält absichtlich nur
//  die Bilddaten und nichts weiter — wer das Bild annimmt, entscheidet selbst,
//  was er damit anfängt, und setzt den Wert danach auf `nil` zurück. Ein Bild,
//  das liegen bleibt, würde beim nächsten Tab-Wechsel erneut auftauchen.
//

import Foundation
import Observation

@Observable
final class EditHandoff {
    /// Wartet darauf, im Chat als Arbeitsbild geladen zu werden.
    var pendingChatImage: Data?
    /// Wartet darauf, im Studio geöffnet zu werden.
    var pendingStudioImage: Data?
}
