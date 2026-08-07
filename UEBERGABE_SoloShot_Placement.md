# Übergabe — SoloShot-Platzierung & Discover-Umbau

Stand: 07.08.2026. Alle sechs Aufgaben sind gebaut, die App baut durch und
**alle 36 Tests sind grün** (vorher 24, davon 4 rot).

Das Projekt ist jetzt ein Git-Repository. Vier Commits, je einer pro Abschnitt:

```
3bc7b8e Aufgaben 5+6: Discover auf die Zielgruppe, Regie-Modus
79b3ff8 Aufgaben 2-4: Platzierungs-Box, Verdrahtung, Uebergabe an Chat/Studio
3257c7f Aufgabe 1: Platzierungs-Vorschlag ueberlebt fehlende Vision-Modelle
894f9b7 Ausgangsstand vor SoloShot-Platzierung
```

### Testlauf

```
xcodebuild test -project Clavic.xcodeproj -scheme Clavic \
  -destination 'id=B26AFEE4-163E-4417-8423-9DAE81DAC94C' \
  -only-testing:ClavicTests
```

---

## Was aus jeder Aufgabe wurde

| Aufgabe | Stand |
|---|---|
| 1 — `PlacementSuggester.swift` | fertig, vier Tests grün |
| 2 — `PlacementBoxOverlay.swift` | fertig |
| 3 — SoloShotView verdrahtet | fertig |
| 4 — Weiterbearbeiten (Chat/Studio) | fertig, mit einer Einschränkung |
| 5 — Templates/Discover | fertig, mit zwei Abweichungen |
| 6 — `DirectorCameraView.swift` | fertig, acht Tests grün |

### Aufgabe 1 — warum die Tests rot waren

Es war **kein Absturz**. Alle fünf Vision-Requests liefen in *einem*
`handler.perform([...])`. Im Simulator scheitern die drei modellgestützten
(Saliency, Personen, Gesichter) mit `Failed to create espresso context` — und
ein einziger Fehlschlag riss die ganze Gruppe mit, `analyse` gab `nil` zurück.

Zwei Änderungen, beide auch auf echten Geräten relevant:

- Jeder Request läuft einzeln. Ein fehlendes Modell kostet nur seine eigene
  Messung, nicht den ganzen Vorschlag.
- Fällt die Saliency aus, misst `structureMatrix` die Unruhe des Bildes selbst
  (Textur je Zelle plus Abweichung vom Median-Ton). Ohne ML, deshalb sinkt die
  Confidence um 15 %.

**Der teuerste Fund lag daneben:** `columnLuminance` legte pro Bild einen
eigenen `CIContext` an, meine erste Fassung von `grayscale` einen zweiten. Bei
acht Analysen je Sekunde wären das sechzehn Metal-Kontexte pro Sekunde. Im
Testlauf hat das einen Test mit `signal abrt` abgeschossen und einen
unbeteiligten Erase-Test von 0,1 s auf **15 Minuten** gebremst. Jetzt gibt es
genau einen geteilten Kontext.

### Aufgabe 3 — drei Stellen, an denen die Vorgabe nicht aufging

1. **Zuschnitt.** Der Sensor liefert 4:3, die Vorschau zeigt 4:5. Ohne
   denselben mittigen Zuschnitt läge die Box im Livebild woanders als im
   gespeicherten Foto. `PlacementSuggester.suggest` hat dafür einen optionalen
   `aspect`-Parameter bekommen.
2. **Kein Frame-Callback vorhanden.** `PoseCameraModel` hatte nur einen
   Photo-Output. Es gibt jetzt einen `AVCaptureVideoDataOutput`, der nur
   angehängt wird, solange jemand zuhört, und schon auf der Kamera-Queue auf
   8/s drosselt.
3. **Der Prompt widersprach dem Bild.** Der bestehende Prompt beschreibt eine
   *blaue Silhouette*. Mit Box liegt aber ein *rosa Rechteck* im Bild. Die
   Markierung wird jetzt an einer Stelle benannt und überall eingesetzt —
   sonst sucht das Modell eine Markierung, die es nicht gibt, und lässt die
   echte stehen.

Zwei bewusste Abweichungen vom Wortlaut:

- Die zwei vorgegebenen Sätze stehen in der **Ich-Form** („Place me…"), nicht
  in der dritten Person. Der gesamte übrige Prompt spricht von „me"; ein
  Wechsel mitten im Text ist der schnellste Weg zu zwei Personen im Ergebnis.
- Die **Identitäts-Klausel fehlte in diesem Prompt komplett**. Sie ist ergänzt
  (Wortlaut aus `EditPromptBooster`), die Platzierungs-Sätze stehen direkt
  dahinter.

### Aufgabe 4 — eine Vorgabe ließ sich nicht erfüllen

`EditHandoff` steht, ist im `ClavicApp`-Environment registriert, und beide
Wege aus dem Ergebnis funktionieren.

**Aber:** „Studio öffnet den Reiter mit den lokalen Reglern (kostenlos)" geht
nicht — diesen Reiter gibt es nicht mehr. `StudioView.Section` kennt nur noch
`.remove` und `.chat`; Licht, Farbe, Haut und Körper sind laut Kommentar im
Kopf der Datei ausgebaut worden („sie versprachen mehr, als sie hielten").
Das Bild wird geladen, die Ansicht bleibt auf der Voreinstellung. Wenn die
kostenlosen Regler zurückkommen sollen, ist das eine eigene Aufgabe.

### Aufgabe 5 — zwei Abweichungen

- **Der Trends-Chip ist geblieben**, die Reihenfolge ist Looks · Tools ·
  Trends · Fun. Nach dem Umhängen liegen acht Vorlagen in `.trends`; mit nur
  drei Chips wäre keine einzige davon noch erreichbar gewesen.
- **Der Hero zeigt kein Video, sondern den Vorher/Nachher-Wischer** über
  `sc_garage_before`/`sc_garage_after`. Ein Solo-Shot-Beispielvideo liegt nicht
  im Bundle. Sobald es eines gibt, gehört an diese Stelle ein
  `LoopingVideoView` — die Stelle ist im Code markiert.

Zusätzlich: die 7 neuen Looks haben **eigene Kacheln** bekommen. Ohne sie wäre
`ViralLooks.all.count == 12` erfüllt, aber sieben Prompts unerreichbar. Die
Vorschau-Assets (`preview_look_cafe_window` usw.) fehlen noch — die Kacheln
fallen sauber auf Verlauf + Symbol zurück, sehen aber leer aus.
**Das ist der nächste sinnvolle Schritt.**

### Aufgabe 6 — Regie

`DirectorCameraView.swift`. Die Vorgabe nannte keinen Einstieg; er sitzt jetzt
als „Regie"-Pille unten rechts im Solo-Shot-Hero in Discover.

Die Geometrie-Regeln liegen getrennt in `DirectorCoach` (`DirectorFrame` rein,
höchstens ein `DirectorHint` raus) — nur so lassen sich die Schwellen prüfen,
ohne mit dem Telefon in der Hand vor der Kamera zu stehen. Acht Tests halten
Rangfolge und Schwellen fest.

---

## Was noch offen ist

- [ ] **Der Testlauf stürzt sporadisch ab — nicht im neuen Code.** In 2 von 6
      Läufen bricht der Host-Prozess mit `SIGABRT` ab, XCTest schreibt es dem
      Test zu, der gerade läuft (einmal `testBoxDoesNotOverlapDetectedPerson`,
      einmal `testBoxAvoidsClutteredHalf`, beide mit Dauer 0,000 s). Der Stack
      ist beide Male identisch und enthält **keinen** Frame aus dem
      Platzierungs-Code:

      ```
      ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
      swift_task_deinitOnExecutorImpl
      TemplateStore.__deallocating_deinit
      destroy for ContentView
      ```

      Reports: `~/Library/Logs/DiagnosticReports/Clavic-2026-08-07-1624*.ips`
      und `-1935*.ips`. Der erste stammt aus einer Zeit, in der `ContentView`
      noch unverändert war — das spricht für einen Altbestand: ein
      `@MainActor`-`TemplateStore`, der über den Concurrency-Executor
      abgeräumt wird, während `load()` noch läuft. **Eigene Aufgabe.**

- [ ] **Auf echter Hardware prüfen.** Im Simulator gibt es keine Kamera: der
      Frame-Strom, die Box im Livebild, der Burst und die 15-%-CPU-Grenze aus
      den Abnahmekriterien sind **nicht** gemessen.
- [ ] Vorschau-Assets für die 7 neuen Looks
- [ ] Beispielvideo für den Solo-Shot-Hero
- [ ] Entscheiden, ob die kostenlosen Studio-Regler zurückkommen (siehe
      Aufgabe 4)
- [ ] Die deutschen Texte („Hier stehst du", „Auto", „Wir zeigen dir, wo du am
      besten stehst", die Regie-Texte) stehen laut Vorgabe auf Deutsch, der
      Rest der Oberfläche ist Englisch. Das ist so gebaut, aber es fällt auf.

## Harte Regeln (galten und gelten weiter)

- Vor jeder Änderung die betroffene Datei ganz lesen
- Keine neuen Third-Party-Abhängigkeiten
- Kein Hardcoding von Farben/Abständen — immer `Theme.*`
- Deutscher Header-Kommentar in jeder neuen Datei: **warum**, nicht was
- Identitäts-Klausel in jedem Prompt
- Nichts blockiert den Main-Thread
- Kein ARKit; `.fun`-Templates und Assets bleiben; Credits, RevenueCat und
  Paywall bleiben unangetastet; die Box überschreibt nie die manuelle Position
