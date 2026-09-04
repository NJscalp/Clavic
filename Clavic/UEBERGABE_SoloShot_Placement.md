
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
