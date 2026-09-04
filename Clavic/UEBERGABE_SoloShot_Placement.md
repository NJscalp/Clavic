
## Nachtrag 04.09.2026 (3) — Eigene Posen, Filmstreifen, leerer Abzug

**Drei eigene Ruheposen neben dem gelesenen Foto** (`MascotStage.readIdleURLs`):
`mascot_read_point`, `_study`, `_approve` — zeigen, betrachten, gutheissen.
Der Platz spielte vorher denselben Satz wie der Startbildschirm, und der
Wechsel zwischen den alten Clips war als Schnitt zu sehen, weil sie in
voellig verschiedenen Posen enden.

Warum diese drei ineinander laufen:
- Alle drei entstanden aus DEMSELBEN Bild (erstes Bild von `mascot_idle1`).
- Jeder Clip laeuft hin und zurueck, endet also auf seinem Anfangsbild.
  Eigene Naht: 0,9-1,1 von 255.
- Ende und Anfang ZWEIER VERSCHIEDENER Clips: 2,3-2,5 von 255 im Mittel.
  Das verdeckt die vorhandene kurze Blende vollstaendig — es brauchte keinen
  neuen Player.

**Cremeton: zweimal korrigiert.** Erst auf den Dateiwert der vorhandenen Clips
(`colorlevels` rimax/gimax/bimax). Danach war der Kasten AUF DEM SCHIRM
trotzdem heller: gerendert 251,247,242 gegen 247,243,237 der alten Clips, bei
praktisch gleichem Dateiwert. Also ein zweites Mal, diesmal am GEMESSENEN
Bildschirmwert (romax/gomax/bomax). Lehre: bei diesen Clips nicht den
Dateiwert vergleichen, sondern einen Screenshot.

`MascotStage` hat dafuer `idleSet`, `MascotPlayerUIView` ein `setIdleSet(_:)` —
der laufende Clip wird dabei NICHT abgeschnitten, erst der naechste kommt aus
dem neuen Satz.

**Auswahl neu:** der Katalog ist ein Filmstreifen mit Perforation statt einer
weissen Zeile mit Pfeil; die eigene Idee ein leerer Abzug mit Bleistiftlinie
statt eines gestrichelten Kastens. Abschnittsueberschriften tragen dieselbe
Typografie wie die Kopfzeile auf dem Blatt.

## Nachtrag 04.09.2026 (4) — Eine Datei, ein Looper; Katalog raus, Server rein

**Der sichtbare „Videowechsel" hatte eine Ursache im Code, nicht im Material:**
`scheduleIdleHandover` startet die Ueberblendung **0,30 s VOR dem Ende** des
laufenden Clips. Waehrend dieser Blende bewegt sich der alte Clip noch und der
neue laeuft schon — zwei Figuren in verschiedenen Haltungen uebereinander. Eine
Blende kann das nicht heilen, sie IST das Problem.

Loesung: `mascot_read_loop.mp4` — alle drei Posen in EINER Datei, gehalten von
EINEM `AVPlayerLooper` (dieselbe Mechanik wie der Pruef-Loop). Keine Blende,
kein Wechsel, kein Neustart.

Die Naehte sind **verschweisst**: jede Pose blendet ueber 5 Bilder auf EIN
gemeinsames Ankerbild und wieder heraus, deshalb sind die Bilder an jedem
Uebergang identisch. Mittlere Abweichung von 255: 2,5 → **0,7**.
(Skripte: `weld.py`, `joins.py` im Scratchpad-Verlauf; Ankerbild ist Bild 0 der
ersten Pose.)

Code: `MascotStage.idleLoopURL` / `MascotPlayerUIView.startLoop(_:)` /
`setIdleLoop(_:)`. Ist `idleLoopURL` gesetzt, wird die Rotation komplett
umgangen — auch `crossfadeToNextIdle` faellt darauf zurueck.

**„Every look we have" ist raus.** Es war eine Liste aus dem Bundle, die nur
ein App-Update aendern kann — und Trends kommen nicht im Rhythmus von
App-Updates. Der Trendstreifen zieht jetzt zusaetzlich aus `TemplateStore`
(`templates.json`): Bild-Trends mit `previewURL` erscheinen sofort, ohne
Update. `DirectorPicks.vorschau(_:)` laedt eine Vorschau per `AsyncImage`,
wenn `preview` mit `http` beginnt, sonst wie bisher aus dem Asset-Katalog.

Der `TemplateStore` haengt in `AgentView` **optional** im Environment: ein
nicht-optionales `@Environment` mit `@Observable` stuerzt beim Zugriff ab, wenn
niemand ihn eingehaengt hat.

**„…or tell me your own idea"** ist eine kleine Liquid-Glass-Leiste im Fluss.
Beim Antippen verschwindet sie (`composerOpen`) und dieselbe Leiste steht unten
am Rand — sie ist nicht zweimal da, sie ist umgezogen.
