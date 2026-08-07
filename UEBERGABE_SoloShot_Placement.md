# Übergabe — SoloShot-Platzierung & Discover-Umbau

Stand: 06.08.2026. Diese Datei ist die vollständige Arbeitsanweisung.
In einer neuen Sitzung genügt: **„Lies Clavic/UEBERGABE_SoloShot_Placement.md und
arbeite weiter."**

---

## Wo es steht

| Aufgabe | Stand |
|---|---|
| 1 — `PlacementSuggester.swift` | **Code fertig, Tests ROT** → hier weitermachen |
| 2 — `PlacementBoxOverlay.swift` | offen |
| 3 — SoloShotView verdrahten | offen |
| 4 — Weiterbearbeiten (Chat/Studio) | offen |
| 5 — Templates/Discover aufräumen | offen |
| 6 — `DirectorCameraView.swift` | offen, eigener Durchgang |

### Aufgabe 1 — was zu tun ist

`Clavic/PlacementSuggester.swift` ist vollständig nach Spezifikation gebaut und
die App **baut durch**. Aber alle vier Tests in
`ClavicTests/PlacementSuggesterTests.swift` schlagen fehl — **ohne** Assertion-
Meldung, auch ohne `XCTUnwrap`-Fehler. Das deutet auf einen Absturz in
`PlacementSuggester.analyse` hin, nicht auf ein falsches Ergebnis.

Hauptverdächtige, in dieser Reihenfolge:
1. `saliencyMatrix(_:)` — liest `VNSaliencyImageObservation.pixelBuffer` direkt
   über `assumingMemoryBound(to: Float.self)`. Format/Stride prüfen.
2. `columnLuminance(_:)` — `CIAreaAverage` mit `workingColorSpace: NSNull()`.
3. `horizonHeight(_:)` — `observation.transform` auf einem Punkt.

Vorgehen: die drei Hilfsfunktionen einzeln stubben und den Test erneut laufen
lassen, bis klar ist, welche abstürzt.

**Aufgabe 1 gilt erst als fertig, wenn die vier Tests grün sind.**

### Testlauf

Tests laufen NICHT gegen `generic/platform=iOS Simulator`, es braucht ein
konkretes Gerät:

```
xcodebuild test -project Clavic.xcodeproj -scheme Clavic \
  -destination 'id=B26AFEE4-163E-4417-8423-9DAE81DAC94C' \
  -only-testing:ClavicTests/PlacementSuggesterTests
```

### Wichtig vorab

Das Projekt ist **kein Git-Repository**. „Nach jeder Aufgabe committen" geht so
nicht. Als Erstes `git init` + ersten Commit anlegen — sonst gibt es bei einem
Fehlschlag keinen Weg zurück.

---

## Harte Regeln (gelten für alle Aufgaben)

- Vor jeder Änderung die betroffene Datei **ganz** lesen. Keine Typen erfinden,
  die es schon gibt.
- Keine neuen Third-Party-Abhängigkeiten. Nur Vision, CoreImage, AVFoundation,
  CoreGraphics, SwiftUI.
- Kein Hardcoding von Farben oder Abständen — immer `Theme.*`.
- Jede neue Datei bekommt einen deutschen Header-Kommentar im Stil der
  bestehenden Dateien: **warum** es die Datei gibt und welche Entscheidung
  dahintersteckt, nicht was der Code tut.
- Bestehende Wege nicht umgehen: Generierungen laufen weiter über den
  vorhandenen Chat-/Credits-Pfad. `ContentPolicy`, `SubjectDetector` und
  `EditPromptBooster` bleiben eingebunden.
- **Identitäts-Klausel bleibt in jedem Prompt**: „Keep the exact same person …
  Do NOT beautify, slim, smooth, retouch or redraw".
- Nichts blockiert den Main-Thread. Vision auf
  `DispatchQueue.global(qos: .userInitiated)` bzw. `Task.detached`.
- Bestehende Tests bleiben grün; für Neues kommen Tests dazu.

### Ausdrücklich nicht tun

- Keine `.fun`-Templates löschen, kein Asset entfernen
- Credits-Fluss, RevenueCatManager und Paywall nicht anfassen
- Kein ARKit — Vision reicht und läuft auf allen Geräten
- Die Box nie erzwingen: der Vorschlag darf die manuelle Position nie überschreiben
- Keine Beauty-, Slimming- oder Retusche-Voreinstellung neu einführen

---

## Aufgabe 2 — `PlacementBoxOverlay.swift`

Die Box muss auf dem Livebild ohne Erklärtext verständlich und anfassbar sein.

```swift
struct PlacementBoxOverlay: View {
    let suggestion: PlacementSuggestion?
    /// Vom Nutzer überschriebene Box. Ist sie gesetzt, gewinnt sie immer.
    @Binding var manualRect: CGRect?
    /// Bildgröße des angezeigten Kameraframes in Punkten.
    let frameSize: CGSize
}
```

Darstellung:
- Abgerundetes Rechteck, `cornerRadius: 22, style: .continuous`
- Rand 2 pt, `Theme.textPrimary.opacity(0.9)`, darunter 6 pt weicher Schatten
- Innenfläche `Theme.textPrimary.opacity(0.06)`
- Vier kurze Eckwinkel (je 18 pt) in Vollton
- Label mittig unter der Box, `.system(size: 11.5, weight: .semibold, design: .rounded)`:
  standing → „Hier stehst du" · seated → „Hier sitzt du" · leaning → „Hier lehnst du"
- Ein-/Ausblenden mit `.animation(.spring(response: 0.35, dampingFraction: 0.85))`
- Bei `confidence < 0.35` **und** `manualRect == nil`: gar nicht anzeigen

Interaktion:
- `DragGesture` verschiebt → setzt `manualRect`
- `MagnificationGesture` skaliert um den Mittelpunkt, Seitenverhältnis fest → setzt `manualRect`
- Box bleibt immer vollständig im Frame (klemmen)
- Sobald `manualRect != nil`: Chip „Auto" rechts oben; Tap setzt `manualRect = nil`

---

## Aufgabe 3 — `SoloShotView.swift` verdrahten

Neuer State:
```swift
@State private var placement: PlacementSuggestion?
@State private var manualPlacementRect: CGRect?
@State private var placementIsAnalyzing = false
@State private var capturedPlacement: PlacementSuggestion?   // beim Auslösen eingefroren
```

**Live-Analyse:** Frame-Callback dort anzapfen, wo der Preview-Layer gespeist
wird. Höchstens 8 Analysen/Sekunde, nie eine neue starten solange die vorige
läuft (`placementIsAnalyzing` als Gate). Ergebnis in `placement`,
`previousRect: placement?.rect` übergeben. **Nur in `Stage.scene` analysieren** —
in `.person` und `.review` stoppen (Akku).

**Overlay** in `cameraFrame(showGhost:)`, nur bei `stage == .scene`:
```swift
.overlay {
    if stage == .scene {
        PlacementBoxOverlay(
            suggestion: placement,
            manualRect: $manualPlacementRect,
            frameSize: frameSize
        )
    }
}
```

**Beim Auslösen** (`captureBackground()`): effektive Box
(`manualPlacementRect ?? placement?.rect`) samt Pose in `capturedPlacement`
einfrieren, **bevor** das Foto gespeichert wird. Danach Live-Analyse stoppen.

**Marker-Referenz** aus `capturedPlacement` bauen (ersetzt die bisherige
manuelle Markierung an genau der Stelle, wo sie heute erzeugt wird):
- Kopie des aufgenommenen Location-Fotos
- Darauf gefülltes, abgerundetes Rechteck an der Box-Position,
  `UIColor.systemPink.withAlphaComponent(0.45)`, cornerRadius = Box-Breite × 0.18
- JPEG, Qualität 0.9

**`SoloShotPrompt.build` erweitern:**
```swift
static func build(
    userText: String,
    sceneImage: Data? = nil,
    placement: PlacementSuggestion? = nil
) -> String
```
Ist `placement` gesetzt, diese zwei Sätze **nach der Identitäts-Klausel, vor der
Licht-/Realismus-Passage** einfügen:

> Place her exactly inside the pink marked region of the reference image: that
> rectangle is where her body belongs, her feet at its bottom edge, her head at
> its top edge. Remove the pink marker itself completely — it must not appear in
> the output. She is \<poseSentence\>, in a position built for this location and
> not carried over from the outfit reference. Match her lighting, shadow
> direction and colour temperature to the location photo, and ground her with a
> real contact shadow where she meets the floor.

`create()` übergibt `capturedPlacement`.

**Hinweistext in `sceneStage`** ersetzen durch:
„Wir zeigen dir, wo du am besten stehst. Box verschieben, wenn du woanders hin willst."

---

## Aufgabe 4 — Weiterbearbeiten nach der Generierung

Neue Datei `EditHandoff.swift`, im `ClavicApp`-Environment registriert:
```swift
@Observable final class EditHandoff {
    var pendingChatImage: Data?
    var pendingStudioImage: Data?
}
```

Im `reviewStage` bzw. am Ergebnis zwei Buttons:
- „Im Chat weiterbearbeiten" → `handoff.pendingChatImage = resultData`, Tab `.chatEdit`
- „Im Studio öffnen" → `handoff.pendingStudioImage = resultData`, Tab `.studio`

`ChatEditView` beobachtet `pendingChatImage`: lädt es als aktuelles Arbeitsbild,
schreibt eine Systemblase „Dein Bild ist geladen. Sag, was du ändern willst."
und setzt den Wert auf `nil`.

`StudioView` beobachtet `pendingStudioImage` analog und öffnet direkt den Reiter
mit den lokalen Reglern (kostenlos), nicht die Server-Werkzeuge.

In `ContentView` den Tab-Wechsel über `EditHandoff` ermöglichen, **ohne** den
bestehenden `createRequest`-Mechanismus zu verändern.

---

## Aufgabe 5 — `Templates.swift` und `DiscoverView.swift`

Discover zeigt heute 42 Templates, davon ~25 aus Meme-/Sport-/Brainrot-
Kategorien. Zielgruppe sind Frauen 18–35; die ersten 1,5 Sekunden entscheiden.

- `TemplateCategory` um `case fun` ergänzen
- Alle Templates aus `.worldcup`, `.fancam`, `.backrooms`, `.dance`, `.memes`
  auf `category: .fun` umhängen — **nicht löschen**
- Neues Feld `let isHiddenFromDiscover: Bool` (Default `false`) auf dem
  Template-Typ; alle `.fun`-Templates bekommen `true`
- `DiscoverView`: Chips in der Reihenfolge **Looks · Tools · Fun**, „Looks" ist
  vorausgewählt statt `.all`. Templates mit `isHiddenFromDiscover == true`
  erscheinen ausschließlich unter „Fun"
- `DiscoverView` bekommt oben einen **SoloShot-Hero** (halbe Bildschirmhöhe, ein
  laufendes Beispielvideo), darunter erst `clavicToolsSection`

**`ViralLooks.all` von 5 auf 12 erweitern.** Jeder neue Look folgt exakt der
bestehenden Prompt-DNA in dieser Reihenfolge:
Identitäts-Klausel → konkrete Pose für die neue Szene → Outfit → Lichtrezept mit
Kelvin-Angabe → Farbstimmung → echte Hauttextur → Aufnahmeart (Handy, leicht
außermittig) → „Photorealistic" → Format → „No text, no logos, no watermark".
Keine Marken, kein Text im Bild.

Themen der 7 neuen: Café-Fenster · Autositz bei Nacht · Spiegel-Selfie im Aufzug ·
Blumenmarkt · Rooftop bei Dämmerung · Bett am Morgen · Regen mit Straßenlicht.

---

## Aufgabe 6 (eigener Durchgang, erst nach 1–5) — `DirectorCameraView.swift`

Zwei verschiedene Situationen: „Ort" = niemand ist da, ich füge mich ein (das
ist SoloShot). **„Regie"** = jemand fotografiert mich, kann es aber nicht.
In diesem Modus wird **nichts generiert** — es entstehen echte Fotos.

- Rückkamera, die Nutzerin steht vor der Linse, eine andere Person hält das Telefon
- Live per `VNDetectHumanRectanglesRequest` + `VNDetectHumanBodyPoseRequest`:
  - Person zu klein → „Zwei Schritte näher"
  - Kamera zu hoch (Blickachse über Brusthöhe) → „Handy tiefer halten"
  - Füße angeschnitten → „Weiter runter"
  - Horizont schief > 4° (`VNDetectHorizonRequest`) → „Gerade halten"
- Nur **ein** Hinweis gleichzeitig, groß, mittig unten, Wechsel frühestens alle 1,2 s
- Stimmt alles 0,6 s durchgehend: automatisch Burst von 6 Aufnahmen über 1,5 s,
  ohne Tastendruck
- Danach Auswahlraster der 6 Bilder, Mehrfachauswahl, „Speichern" legt die
  gewählten in die Library
- Kein Credit-Verbrauch, keine Server-Runde

---

## Abnahmekriterien

- [ ] Die Location-Kamera zeigt eine ruhig stehende, abgerundete Box, die sich
      beim Schwenken flüssig mitbewegt und nicht zappelt
- [ ] Die Box weicht erkannten Personen sichtbar aus
- [ ] Die Box ist verschiebbar und skalierbar; der „Auto"-Chip stellt den
      Vorschlag wieder her
- [ ] Das erzeugte Bild platziert die Person innerhalb der markierten Region,
      und der rosa Marker ist im Ergebnis nicht mehr zu sehen
- [ ] Aus dem Ergebnis führen zwei Wege weiter: Chat und Studio, beide mit
      vorgeladenem Bild
- [ ] Discover öffnet auf „Looks"; kein Fan-Cam-, Backrooms- oder
      Tung-Tung-Template ist ohne den Fun-Chip erreichbar
- [ ] `ViralLooks.all.count == 12`, jeder Prompt enthält die Identitäts-Klausel
- [ ] `PlacementSuggesterTests` grün, bestehende Tests unverändert grün
- [ ] Instruments: Live-Analyse unter 15 % zusätzlicher CPU auf einem iPhone 13
