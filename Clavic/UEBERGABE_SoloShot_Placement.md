
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

## Nachtrag 04.09.2026 (5) — Der Kasten atmete: zwei Ursachen

Gemeldet: „man sieht den Background des Mascot im Video, er wird dunkler oder
heller, und man sieht Kanten."

**Ursache 1 — das Video selbst.** Das Videomodell laesst die Helligkeit des
ganzen Bildes wandern. GEMESSEN (Randbahn, Spanne ueber die Laufzeit, von 255):

| Clip | Spanne R/G/B |
|---|---|
| mascot_idle1 / idle_tab / scan | 1,0 – 2,1 (stabil) |
| **mascot_read_loop (vorher)** | **8,7 / 8,5 / 9,3** |
| mascot_throw | 13,0 / 12,6 / 10,9 (noch offen) |

`colorlevels` mit festem Weisspunkt kann das nicht beheben — es kennt EINEN
Wert, das Problem aendert sich ueber die Zeit. Deshalb `steady.py`: Bild fuer
Bild die 40-px-Randbahn messen und je Kanal multiplikativ auf den Zielwert
ziehen. Multiplikativ, weil die Drift eine Belichtung ist; dunkle Konturen
(Wert um 20) aendern sich dabei um unter 1. Nachher: Spanne 2,2 – 2,5, also im
Bereich der stabilen Altclips. Die verschweissten Naehte ueberleben das
(0,65 – 0,85), weil identische Bilder identische Verstaerkung bekommen.

ACHTUNG bei `steady.py`: Breite/Bildrate stehen im Skript. Ein Lauf mit den
falschen Werten (720/25 statt 960/24) zerlegt die Datei lautlos —
`mascot_throw` ist 720×720@30, nicht 960×960@24.

**Ursache 2 — unsere eigene Animation.** `MascotMist` schob zwei Cremeschwaden
9,5 s hin und 9,5 s zurueck ueber die Figur und aenderte dabei ihre Deckkraft
zwischen 0,30 und 0,75. Auf einer gleichmaessigen Cremeflaeche IST das „der
Hintergrund wird dunkler und heller". Ersatzlos entfernt.

**Die Kanten:** `fogMask` lief nur links, rechts und unten aus — die Oberkante
des quadratischen Videokastens war ein harter Schnitt. Jetzt laeuft sie an
allen vier Seiten aus (oben 3 %, das liegt ueber dem Kopf: die Figur fuellt
92 % der Bildhoehe). Am Bildschirm gemessen gibt es ueber die Kastenkante
keinen Sprung mehr: 246 → 250 → 246 ueber die ganze Breite.

Offen: `mascot_throw` driftet noch um 13. Er laeuft einmalig beim Start.

## Nachtrag 04.09.2026 (6) — Dieselbe Leiste, weniger Text, eine Trendkarte

**1. Die Regie-Leiste IST jetzt die Chat-Leiste.** Gleiches Glas, gleiche Ecke
(26), gleiche Kurve (`composerMotion` = `.smooth(0,3)`), gleiche Abstaende
(`inputFocused ? 2 : 82`), Textfeld bis acht Zeilen mit eigener Kurve auf
`input`. Das deckende Tablett und die Kopfzeile sind weg.
Weiterhin bewusst NICHT drin: Plus, Kamera, Bild/Video — der Director hat EIN
Foto gelesen, ein Anhang-Knopf waere die Einladung, das zu verlassen.
Die Schnellauftraege erscheinen wie die Einstellungs-Chips im Chat erst bei
Fokus.
Beim Oeffnen erst `showComposer`, dann im naechsten Zug der Laufschleife der
Fokus — zusammen laeuft die Tastatur gegen die einlaufende Leiste an.

**2. Das Blatt sagt jetzt, was ER MACHEN WUERDE.** Vorher stand dort ein ganzer
Satz in 19 pt Serifen ueber zwei bis drei Zeilen; man musste ihn lesen, um zu
wissen, was mit dem Foto passiert. Jetzt: „WHAT I'D DO" und je Anmerkung drei
bis fuenf Woerter (`ReadMark.change`), mit einem Punkt in der Farbe ihres
Striches auf dem Bild. Rot = stoert, gruen = sitzt. Markierung oben,
dieselbe Farbe unten — man findet sie ohne zu suchen.
**Bewusst entfernt:** der Satz aus `DirectorAPI.Reply.message` wird nicht mehr
angezeigt. Er steht weiter in `messages` und ist Kontext fuer den Director.

**3. Trends: eine Karte, ein Pop-up.** Der waagerechte Streifen nahm viel Hoehe
und zeigte nur drei auf einmal. Die Karte („OUR TIKTOK TRENDS", vier
Vorschaubilder, Zahl) oeffnet `DirectorTrendSheet` — ein Raster ohne Suche und
ohne Filter. Inhalt: Vorschlaege des Directors zuerst, dahinter der Server.
Neue Trends samt Bild und Name kommen ueber `templates.json`; `previewURL` wird
per `AsyncImage` geladen. Die eigentliche Pflegeoberflaeche dafuer steht noch
aus (Wunsch des Nutzers: erst wenn der Tab fertig entworfen ist).
