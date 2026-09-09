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

    /// Zählt jede Übergabe an den Chat hoch.
    ///
    /// WARUM EIN ZÄHLER UND NICHT DAS BILD SELBST: an `pendingChatImage`
    /// hängen ZWEI Beobachter. `ContentView` soll den Tab wechseln,
    /// `ChatEditView` soll das Bild übernehmen — und Letzteres setzt das Feld
    /// dabei sofort auf nil zurück. Der Chat-Tab liegt immer im Baum, auch
    /// wenn er nicht sichtbar ist; er war also schneller, und `ContentView`
    /// sah beim Nachsehen nur noch nil. Der Tab wechselte nie.
    ///
    /// Der Zähler wird von niemandem geleert. Er ist damit das verlässliche
    /// Signal „geh in den Chat", unabhängig davon, wer das Bild wann abholt.
    private(set) var chatToken = 0

    /// Der einzige Weg, ein Bild in den Chat zu geben.
    func sendToChat(_ data: Data) {
        pendingChatImage = data
        chatToken &+= 1
    }
}
