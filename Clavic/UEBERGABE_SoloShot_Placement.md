
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

## Nachtrag 04.09.2026 (7) — 60 fps, kein Standbild, kein Hänger

**Der „Cut am Schluss" war ein STANDBILD, und zwar meins.** Gemessen an der
Bewegung je Bild: am Umlauf des Lese-Loops standen **24 Bilder lang exakt 0**,
also 0,4 Sekunden Stillstand, dann lief es von vorn. Ursache war der
Schweisspunkt aus Nachtrag (4): ich hatte die ersten und letzten fuenf Bilder
jeder Pose auf ein gemeinsames Ankerbild geblendet. Die Naht war danach messbar
perfekt (0,85 statt 2,5 von 255) — und die Figur stand.

Der Fehler war die Zielgroesse: 2,5 von 255 ist weniger als bei `mascot_idle1`
(2,2) und `mascot_scan` (2,3), die seit jeher laufen. Ich habe etwas
Unsichtbares repariert und dabei etwas Sichtbares eingebaut.

Neu gebaut ohne Schweisspunkt (`rebuild_loop.py`):
`fw` = Bild 0…N-1, `rv` = rueckwaerts OHNE erstes und letztes Bild. Ein
Abschnitt endet auf Bild 1, der naechste beginnt auf Bild 0 — keine Dopplung.
Laengster Stillstand jetzt 15 Bilder bei 60 fps (0,25 s) und das mitten in
einer Geste, nicht am Umlauf.

**Die richtige Kennzahl fuer einen Ping-Pong-Loop ist NICHT „erstes gegen
letztes Bild".** Bei sauberem Ping-Pong unterscheiden die sich um genau einen
Bewegungsschritt. Verglichen wird der Umlaufschritt mit den Nachbarschritten:

| Clip | Umlaufschritt | Median aller Schritte |
|---|---|---|
| read_loop neu | 2,76 | 0,76 |
| mascot_idle1 (im Bestand) | 1,47 | 0,31 |

**Alle sieben Clips laufen jetzt mit 60 fps**, mit echten Zwischenbildern
(`minterpolate`, bidirektional, aobmc+vsbmc). Nicht doppelte Bilder — die
machen die Datei groesser, ohne dass die Bewegung feiner wird. 7,1 → 8,5 MB.

FUER SCHLEIFENDE CLIPS gilt `loop60.py` statt der einfachen Umrechnung: dem
letzten Bild fehlt der rechte Nachbar, dort raet `minterpolate` und die Naht
bricht (`mascot_scan`: 2,29 → 3,7). Der Clip wird deshalb ZWEIMAL hintereinander
interpoliert und die mittlere Periode herausgeschnitten — jedes Bild hatte dann
echte Nachbarn auf beiden Seiten. Ergebnis fuer `mascot_scan`: 2,29 → **0,88**.
Die Periode dabei ZAEHLEN, nicht ausrechnen: `minterpolate` liefert nicht exakt
fps×Dauer Bilder, und ein um zwei Bilder verschobener Schnitt zerstoert genau
die Naht, die er retten soll.

**Der App-Wechsel war ein echter Fehler.** `isActive` stand fest auf `true`, es
gab NIRGENDS eine Reaktion auf den Lebenszyklus. iOS haelt beim Wechsel in den
Hintergrund jeden `AVPlayer` an — zurueck im Vordergrund hat ihn niemand wieder
gestartet. Jetzt horcht `MascotPlayerUIView` auf `didBecomeActive` /
`willEnterForeground` und wirft wieder an; beim Verlassen haelt es ausdruecklich
an. Im Simulator geprueft: HOME, vier Sekunden warten, zurueck — Bewegung ueber
sechs Sekunden 19,1 / 19,7 / 14,4 / 4,2.

**Wachhund:** alle zwei Sekunden wird geprueft, ob die Zeit vorangeht. Ein
`AVPlayerLooper` kann mit leerer Warteschlange dastehen, ein Item fehlschlagen,
eine abgeschnittene Blende `fading` haengen lassen — in allen drei Faellen steht
das Bild und nichts meldet sich. Der Timer laeuft in `.common`, sonst stuende er
genau beim Scrollen still. Dafuer merkt sich der Player in `currentSource` /
`currentIsLoop`, was laufen SOLL.

## Nachtrag 04.09.2026 (8) — Der Director bekommt ein Urteil statt eines Layouts

Umsetzung der Produktlogik. Was GEBAUT ist:

**§2 Kein starrer Flow.** Die harte Regel „EXACTLY TWO" ist raus — an drei
Stellen: im Systemprompt, im Werkzeug-Schema (`minItems 1, maxItems 3`) und in
`cleanOptions(...).slice(0, 3)`. Dazu ein neues Feld **`lead`**: die id des
Vorschlags, den der Director selbst nehmen wuerde. Bei genau einem Vorschlag
immer gesetzt. Der Prompt sagt jetzt ausdruecklich, WANN eins, zwei oder drei
richtig sind — und dass eine feste Zahl keine Meinung ist, sondern ein Layout.

**§3 Breitere Lesung.** Vier Felder ergaenzt, die vorher fehlten und ohne die
zwei verschiedene Fotos zwangslaeufig aehnlich beantwortet wurden:
`outfit`, `location`, `time_of_day`, `mood`. Dazu im Prompt eine ausdrueckliche
Liste des Repertoires (Flash, editorial, cinematic, night, film stock, soft
daylight, dramatic, paparazzi, disposable, dreamy, luxury, holiday …) und die
Regel: zwei verschiedene Fotos duerfen nicht dieselbe Antwort bekommen.

**§4 Director's Ideas.** `PolaroidCard` hat eine **Hero-Variante**: bei genau
EINEM Vorschlag waechst das Foto von 88 auf 210 Punkte. Bei mehreren traegt der
`lead` ein kleines **MY PICK**. Der Grid konnte 1–3 schon vorher.

**§5 Choose a TikTok Trend.** Die beste Passung steht jetzt GROSS oben auf der
Karte („BEST MATCH FOR YOUR PHOTO"), der Rest klein darunter; im Pop-up steht
sie vorn und traegt ein Abzeichen. Die Bewertung kommt vom Director (`fit`),
weil nur er die Bildlesung hat — **Server-Trends bekommen sie NICHT**, sie eine
beste Passung zu nennen waere eine Behauptung ohne Grundlage.

**§12 Result Screen.** `directorsCut(vorher:nachher:)` — der vorhandene
`BeforeAfterSlider` interaktiv, ueber rund 46 % der Bildschirmhoehe, darunter
„THE DIRECTOR'S CUT" und genau zwei Entscheidungen: **Keep it** (sichert in
Fotos) und **Try another direction** (legt nur das Ergebnis beiseite, Foto und
Lesung bleiben — ein neuer Zug wuerde den Nutzer sein Bild noch einmal
aussuchen lassen). Der Schieber steht still, bis jemand zieht.

Neue Debug-Haken: `UITEST_DIRECTOR_RESULT`, `UITEST_DIRECTOR_ONE`.

**§8/§9 waren bereits gebaut** und bleiben unveraendert: `DirectorAPI.review`
gegen `/v1/director/review`, `refineIfNeeded` mit hoechstens zwei
Nachbesserungen, Credits nur bei Erfolg, blockiert nie.

### Was NOCH NICHT gebaut ist
- **§10 Maskottchen-Zustaende**: es haelt beim Lesen UND beim Pruefen dieselbe
  Lupe. Eigene Regungen fuer „Idee gefunden", „praesentiert", „fertig" fehlen —
  dafuer braucht es neue Clips.
- **§6** funktioniert (freie Eingabe geht an den Director, der den technischen
  Prompt baut), ist aber nicht gegen Beispielsaetze geprueft worden.
- Das Backend ist **nicht deployt** — die Prompt-Aenderungen wirken erst danach.

## Nachtrag 04.09.2026 (9) — Deployt und mit sieben Fotos geprüft

**Regel korrigiert (auf Zuruf).** „Zwei verschiedene Fotos duerfen nicht
dieselbe Antwort bekommen" war eine harte Vielfalts-Vorgabe und damit falsch:
sie haette den Director zwingen koennen, die richtige Antwort zurueckzuhalten,
um abwechslungsreich auszusehen. Neu formuliert als **„Judge this photo on its
own"** — Wiederholung ist ausdruecklich erlaubt, wenn sie stimmt; verboten ist
die faule Variante. Der Pruefstein ist nicht „habe ich das schon gesagt",
sondern „kann ich zeigen, was in DIESEM Bild mich dazu gebracht hat".
Ebenfalls entfernt: „never make every pick a catalogue look" — mit nur EINEM
Pick war das ein Widerspruch.

**Deployt** auf `limitless-web` (production), Health gruen,
`directorBrain: claude-opus-5`.

**Testlauf, sieben verschiedene Fotos** (`probe.py`, Ergebnis in `probe.json`):

| Foto | Picks | lead | Modus des lead |
|---|---|---|---|
| clubflash | 3 | Bring the skin back | retouch |
| monowindow | 2 | Clear the crowd behind | retouch |
| beach | 2 | Clear the stray light | retouch |
| cafe | 3 | Clean the neon mess | retouch |
| car | 1 | Clean the scan | retouch |
| mirror | 3 | Clear the flare | retouch |
| party | 2 | Clear the frame | retouch |

Die Anzahl schwankt tatsaechlich (1 bis 3). Jede Zeile benennt etwas, das nur
in DIESEM Bild steht. Sechs von sieben Leads sind ein `retouch` einer konkret
benannten Stoerstelle — nicht ein Katalog-Look. Katalog-Looks tauchen nur als
Zweit- und Drittvorschlag auf.

**Nicht deterministisch:** derselbe Wagen-Clip lieferte in zwei Laeufen einmal
1 und einmal 2 Picks. Das ist erwuenscht (ein Urteil, keine Tabelle), aber es
heisst: ein einzelner Testlauf beweist nichts.

**Gefunden und behoben:** Bildunterschriften wurden hart bei 90 Zeichen
abgeschnitten, mitten im Wort („…their skin textu"). Jetzt `cut()` auf
Wortgrenze mit Auslassungspunkt.

**OFFEN — Trends sind leer.** `trendsSource: "none"`: weder `TRENDS_URL` noch
`DIRECTOR_TRENDS` sind gesetzt. In allen sieben Laeufen kam
`trends: []` zurueck. Die „BEST MATCH"-Auszeichnung hat damit nichts zu
bewerten. Das ist eine Konfigurationsluecke, keine Codeluecke — die Mechanik
steht (`director-trends.mjs`).

**Warnung beim Deploy:** Node 20.x ist veraltet, Deployments ab 01.10.2026
schlagen fehl. Fix waere `"engines": { "node": "24.x" }` in der `package.json`
des Backends.
