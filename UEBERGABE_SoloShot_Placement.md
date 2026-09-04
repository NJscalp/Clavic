# Übergabe — SoloShot-Platzierung & Discover-Umbau

> **HISTORISCH — Stand 07.08.2026. Zwei Aussagen darin gelten nicht mehr:**
>
> 1. Weiter unten steht „Der Absturz ist damit seltener, aber **NICHT weg**."
>    Er ist inzwischen weg — behoben in `56a52b8` (grayscale schrieb über ein
>    Swift-Array hinaus) und `66241df` (keine rohen Zeiger mehr in Swift-Arrays).
> 2. „Aufgabe 6 — Regie" beschreibt `DirectorCameraView`. Diese Ansicht ist
>    fertig, aber **nirgends in der App eingebunden** — sie lebt nur noch über
>    `DirectorCoachTests`.
>
> Alles andere ist als Protokoll weiterhin gültig.

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
Swift-Array.

**Der Absturz ist damit seltener, aber NICHT weg.** Nach dem Umbau liefen vier
Durchgaenge sauber, der fuenfte stuerzte wieder ab. Und diesmal mit einer
anderen Klasse im Stack:

```
___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
swift_task_deinitOnExecutorImpl
OncePlayerView.Coordinator.__deallocating_deinit   ← vorher: TemplateStore
```

Dass zwei voellig verschiedene Klassen denselben Weg nehmen, verschiebt den
Verdacht: es geht nicht um `TemplateStore` und nicht um eine einzelne Zeile,
sondern um `swift_task_deinitOnExecutorImpl` — das Projekt uebersetzt mit
`-default-isolation=MainActor`, also ist fast jede Klasse `@MainActor`, und
ihr `deinit` springt auf den Main-Executor, sobald die letzte Referenz auf
einem Hintergrund-Thread faellt.

**Naechster Schritt, und diesmal mit dem richtigen Werkzeug:** Address
Sanitizer im Test-Schema einschalten. Der schlaegt an der Stelle an, an der
ueber den Speicher hinausgeschrieben wird — nicht erst beim spaeteren
Freigeben. Alles bisherige war Raten anhand eines Stacks, der auf den
Tatort NICHT zeigt.

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

### Nachtrag: Sucher statt Beschriftung, ein Bild statt zwei

Zwei Rueckmeldungen aus dem Betrieb:

**Im Review lagen zwei Bilder uebereinander.** Auf dem Ortsfoto lag die
Outfit-Referenz als getoente Silhouette, dazu die Outfit-Karte am linken Rand.
Beides ist weg: die Box zeigt die Platzierung, ohne das Foto zuzudecken, und
die Outfit-Karte erscheint nur noch im Ausricht-Schritt, wo sie hingehoert.
Damit ist auch die alte Silhouetten-Maschinerie raus (`alignedReferenceOverlay`,
`overlayScale`/`overlayOffset`/`overlayOpacity`, der blaue Guide-Pfad) — die
Markierung ist jetzt immer das rosa Rechteck, auch bei einem Bild aus der
Mediathek.

**Kein „Hier stehst du" mehr, sondern ein Sucher.** Wer das Telefon hochhaelt
und sich dreht, liest nicht. Rahmen und Standpunkt sind **weiss**, solange die
Kamera sucht, und springen auf **gelb**, sobald der Winkel stimmt
(`PlacementSuggestion.isReadyForTheShot`: Confidence >= 0.5 und Horizont
hoechstens 4 Grad schief; ohne erkennbaren Horizont zaehlt nur die Confidence,
sonst gaebe es drinnen nie gruenes Licht). Man dreht, bis es gelb wird.

**Dabei gefunden:** die Box liess sich gar nicht anfassen. Sie lag per
`offset` an ihrer Stelle — das verschiebt nur das Gezeichnete, fuer die
Beruehrung blieb sie in der Ecke. Jetzt `position`. Aufgefallen ist das erst
beim Ziehen im Simulator, nicht beim Lesen des Codes.

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

---

## Nachtrag 03.09.2026 — Prüf-Loop des Maskottchens eingehängt

Die vorherige Sitzung brach am Sitzungslimit ab, kurz nachdem die beiden neuen
Clips erzeugt, auf `Theme.background` gemattet und in `MascotStage` verdrahtet
waren. Build und Tests waren grün, **aber `scanURL` wurde nirgends benutzt** —
der Prüf-Loop lag fertig im Bundle und lief nie.

Das ist jetzt eingehängt:

- `MascotPlayerUIView.setScanning(_:)` blendet zwischen Prüf-Loop und Ruhe um,
  über dieselbe Überblendung wie der Idle-Wechsel. Ohne sie spränge die Figur
  hart von der Lupe in den Leerlauf.
- `scheduleScanRepeat` hängt den Clip kurz vor seinem Ende wieder an sich
  selbst. Bewusst **ein einzelner Loop**, nicht die Idle-Rotation: er zeigt
  genau eine Handlung, und ein Wechsel mittendrin wäre ein Bruch. Der gemessene
  Schnittsprung von 4,0 von 255 hält die Wiederholung unsichtbar.
- `MascotStage` reicht `isScanning: act == .working` durch. `mascotAct` steht
  über `onChange(of: isWorking)` bereits auf `.working`, sobald der Director
  liest — es war nur nichts daran angeschlossen.
- `setScanning` läuft in `updateUIView` **nach** `startThrow`, sonst
  überschriebe ein laufender Wurf den Prüf-Loop sofort.

Ein `scanning`-Flag verhindert doppeltes Überblenden: SwiftUI ruft
`updateUIView` bei jeder Neuzeichnung auf, nicht nur bei einer Änderung.

**Was nicht geprüft ist:** wie es aussieht. Der Simulator hat keine Kamera, und
der Director-Ablauf hängt hinter der Anmeldung. Build und Testlauf sind grün,
die Bewegung selbst hat niemand gesehen.

### Zur Entwarnung, falls die Frage wieder aufkommt

Die Clips stehen **nicht** in `project.pbxproj` — das ist korrekt so. Das
Projekt nutzt Dateisystem-Synchronisation (`PBXFileSystemSynchronizedRootGroup`,
5 Vorkommen); Dateien im Ordner landen automatisch im Bundle. Nachgeprüft:
`mascot_scan.mp4` liegt in beiden gebauten `Clavic.app` (Gerät und Simulator).

## Nachtrag 04.09.2026 — Die Werkstatt um die Figur

Im Director-Tab stand das Maskottchen oben allein, darunter lag der halbe
Bildschirm leeres Cremeweiss — beim Lesen wie nach dem Ergebnis.

Neu: `DirectorScenery.swift`. Sieben Requisiten im Stil des Maskottchens
(Sofortbilder, Filmdose, Softbox, Farbfaecher, Gluehbirne, Kamera, Becher),
erzeugt mit **Nano Banana 2 ueber fal** und auf die Theme-Palette festgelegt.
Die Rohbilder entstanden auf magentafarbenem Grund und wurden lokal
freigestellt — Magenta kommt in der Palette nicht vor, deshalb liess es sich
sauber wegschneiden, ohne die cremefarbenen Flaechen zu treffen.

Zwei Regeln, die den Aufbau bestimmen:
1. Requisiten liegen **nur an den Raendern** und wachsen von aussen herein.
   Nie etwas hinter Text oder Foto — deshalb ist die Position an eine Kante
   gebunden (`edge` + `bleed`), nicht frei.
2. Sie bewegen sich nach **derselben Windformel** wie das Blattwerk
   (`MascotHabitat.wind`). Eine Bewegungssprache, nicht zwei.

Beim Lesen atmet die Kulisse kraeftiger (`busy`), danach beruhigt sie sich.
Sie laeuft mit 15 Bildern/s statt 30: ein Takt dauert 5-7 s, und sie liegt
hinter dem ganzen Bildschirm.

Eingehaengt in `AgentView.body` als Hintergrund — deckt Auftakt, Lesen und
Ergebnis in einem Zug ab.

Assets: `prop_polaroid`, `prop_bulb`, `prop_film`, `prop_swatch`, `prop_lamp`,
`prop_cup`, `prop_camera` (zusammen 1,4 MB).

## Nachtrag 04.09.2026 (2) — Der Abzug wird angestrichen

Fuenf Aenderungen am Ergebnis-Bildschirm des Director-Tabs:

1. **`DirectorReadMarks.swift`** misst das Foto (48x48-Graubild, neun Felder,
   Mittelwert und Streuung) und liefert zwei bis drei Anmerkungen mit Stelle
   und Text. Die Gesichtserkennung laeuft als EINZELNE, gekapselte
   Vision-Anfrage obendrauf — nie gebuendelt, weil im Simulator jede
   modellgestuetzte Anfrage scheitert und ein Fehlschlag die uebrigen
   mitreisst. Der Graupuffer entsteht mit `data: nil` (siehe die
   `abrt`-Geschichte im `PlacementSuggester`).

2. **`DirectorInkNotes.swift`** zieht die Striche ueber `trim(to:)`, nicht als
   Einblendung. `trim` gibt es nur auf `Shape` — ein `@ViewBuilder`, der je
   nach Fall eine andere Form liefert, ist schon `some View` und laesst sich
   nicht mehr ziehen. Deshalb EIN `InkStroke` mit drei Formen darin.
   Rot fuer das, was stoert, gruen fuer das, was sitzt.

3. **`DirectorNote.swift`** — das Urteil als Blatt: Serifen, rote Randlinie,
   Eselsohr, Unterschrift, leichte Schraeglage.

4. **`DirectorPicks.swift`** neu: Trends als sichtbarer Streifen statt hinter
   einer zugeklappten Zeile, der ganze Katalog (19 Looks) hinter einem Knopf,
   der seine Groesse nennt, und „I want to make my own thing" als eigener
   breiter Knopf.

5. **Die Leiste unten ist die Regie-Leiste**, nicht die Chat-Leiste: kein
   Anhang, keine Kamera, dafuer die Anmerkungen vom Foto als Schnellauftraege.
   Sie traegt einen DECKENDEN Untergrund — der erste Entwurf hatte nur Glas um
   das Textfeld, und ueber den Trendkacheln war nichts davon lesbar.

Ausserdem: **`mascot_idle_present.mp4`** — neue Ruhepose, die Figur hebt den
Abzug und zeigt ihn her. Erzeugt aus dem ERSTEN BILD von `mascot_idle1`
(Seedance i2v ueber fal), Cremeton per `colorlevels` auf den Ton der
vorhandenen Clips gehoben (die Rohdatei war (237,233,230) statt (246,242,237)),
dann hin und zurueck geschnitten: der Clip endet auf seinem Anfangsbild,
mittlere Abweichung an der Naht 0,9 von 255.
