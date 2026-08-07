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

**Zwei Funde lagen daneben, beide teuer.**

*Erstens:* `columnLuminance` legte pro Bild einen
eigenen `CIContext` an, meine erste Fassung von `grayscale` einen zweiten. Bei
acht Analysen je Sekunde wären das sechzehn Metal-Kontexte pro Sekunde. Im
Testlauf hat das einen Test mit `signal abrt` abgeschossen und einen
unbeteiligten Erase-Test von 0,1 s auf **15 Minuten** gebremst. Jetzt gibt es
genau einen geteilten Kontext.

*Zweitens — und das war der teuerste:* der Testlauf stuerzte in etwa jedem
zweiten Durchgang mit `SIGABRT` ab, immer mit demselben Stack und immer einem
anderen Test zugeschrieben:

```
___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
swift_task_deinitOnExecutorImpl
TemplateStore.__deallocating_deinit
destroy for ContentView
```

Der Stack zeigte auf `ContentView` — die Ursache lag aber woanders. So wurde
sie eingekreist, jeweils drei bis vier Laeufe je Zeile:

| Was lief | Abstuerze |
|---|---|
| Ausgangsstand, 24 Tests | 0 von 4 |
| unser Stand, dieselben 24 Tests | 3 von 3 |
| unser Stand, dieselben Tests ohne `PlacementSuggesterTests` | 0 von 3 |

Damit war es eingegrenzt: nicht die Lauflaenge, nicht die App-Oberflaeche,
sondern `PlacementSuggester.suggest` selbst. Zwei Stellen dort schrieben ueber
rohe Zeiger in Swift-Arrays, und beide Male rundet das Framework die
Zeilenlaenge intern auf und schreibt hinter das Array:

- `grayscale`: `CGContext(data: &array, bytesPerRow: width)`
- `columnLuminance`: `CIAreaAverage` + `render(toBitmap:)` in vier Byte

Der Schaden faellt nie an der Stelle auf, sondern irgendwann spaeter beim
Freigeben von fremdem Speicher — daher der irrefuehrende Stack.

**Warum es auf dem Ausgangsstand nie auftrat:** dort warf der gebuendelte
Vision-Aufruf, `analyse` stieg mit `nil` aus, und beide Zeilen wurden nie
erreicht. Erst das tolerante Ausfuehren aus Aufgabe 1 hat sie erreichbar
gemacht.

Jetzt gibt es EINEN Graustufen-Durchgang, aus dem beide Messungen rechnen —
kein `CIAreaAverage`, kein `render(toBitmap:)`, kein roher Zeiger in ein
Swift-Array. Danach: **drei volle Laeufe, je 42 bestanden, kein Absturz.**

---

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

### Vorschau-Bilder der neuen Looks

Die sieben neuen Kacheln haben echte Beispielbilder. Sie sind **nicht**
danebengemalt, sondern über genau den Weg entstanden, den die Vorlage selbst
nimmt: Clavic-Backend → WaveSpeed → Seedream v5.0 Pro (edit), Referenz
`face_model_1`, Prompt wörtlich aus `ViralLooks.swift`, 9:16 bei 1k.
Die Nutzerin sieht damit auf der Kachel, was der Prompt dahinter wirklich
erzeugt.

Das Skript liegt im Projekt: `Scripts/make_look_previews.py`. Ein Look wird so
neu gebaut:

```
python3 Scripts/make_look_previews.py cafe-window
```

Kosten: rund 0,045 $ je Bild, also ~0,32 $ für alle sieben.

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

- [ ] **Auf echter Hardware prüfen.** Im Simulator gibt es keine Kamera: der
      Frame-Strom, die Box im Livebild, der Burst und die 15-%-CPU-Grenze aus
      den Abnahmekriterien sind **nicht** gemessen.
- [ ] Beispielvideo für den Solo-Shot-Hero. Aktuell steht dort das Standbild
      `preview_pro_glow_after` (eine Frau allein an einem Ort). Vorher lag hier
      ein Vorher/Nachher-Wischer über die Garagen-Aufnahme — der zeigte ein
      Auto und passte nicht zur Überschrift.
- [ ] Entscheiden, ob die kostenlosen Studio-Regler zurückkommen (siehe
      Aufgabe 4)
Die Oberfläche ist wieder **durchgehend Englisch**. Die deutschen Texte aus der
Vorgabe („Hier stehst du", „Regie", …) sind übersetzt; die Kommentare im Code
bleiben deutsch, so wie es die harten Regeln verlangen.

## Harte Regeln (galten und gelten weiter)

- Vor jeder Änderung die betroffene Datei ganz lesen
- Keine neuen Third-Party-Abhängigkeiten
- Kein Hardcoding von Farben/Abständen — immer `Theme.*`
- Deutscher Header-Kommentar in jeder neuen Datei: **warum**, nicht was
- Identitäts-Klausel in jedem Prompt
- Nichts blockiert den Main-Thread
- Kein ARKit; `.fun`-Templates und Assets bleiben; Credits, RevenueCat und
  Paywall bleiben unangetastet; die Box überschreibt nie die manuelle Position
