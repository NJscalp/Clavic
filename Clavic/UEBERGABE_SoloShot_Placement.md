
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

## Nachtrag 04.09.2026 (10) — Warum der Director stehenblieb

**Die Ursache war Geld, nicht Code.** Jeder Zug endete mit 502, im Rumpf stand:
`"Your credit balance is too low to access the Anthropic API."` Der direkte
Anthropic-Zugang war leer. Der Testlauf aus Nachtrag (9) lief noch davor.

**Wie die zwei Modelle wirklich verdrahtet sind** (nachgesehen, nicht vermutet):

| Stufe | Modell | Weg | Schluessel |
|---|---|---|---|
| 1 — Foto lesen | google/gemini-3.5-flash | `fal.run/openrouter/router/vision` | `FAL_KEY` |
| 2 — entscheiden | claude-opus-5 | `api.anthropic.com` direkt | `ANTHROPIC_API_KEY` |

Also: **keine der beiden Stufen lief ueber WaveSpeed**, obwohl
`wavespeedConfigured: true` meldet und `director-wavespeed.mjs` existiert.
Stufe 1 war zu keiner Zeit kaputt — 26 Felder kamen sauber zurueck.

**WaveSpeed gemessen** (14 Laeufe, 7 Fotos, 2 Runden):
- Werkzeugaufruf geliefert: **14/14**. Die im Dateikopf befuerchtete Schwaeche
  (Opus schreibt den Aufruf als Text statt ihn zu taetigen) trat NICHT auf.
- Dauer 28–48 s gegenueber 12–15 s direkt.
- ABER: **13 von 14 Laeufen gaben genau 2 Picks**, einer gab 1. Direkt ueber
  Anthropic lag die Verteilung bei 1/2/2/3/1/3/2. Das ist der Preis von
  fehlendem `thinking: {type:"adaptive"}` und `output_config: {effort}` im
  OpenAI-Protokoll — und es kostet genau die Vielfalt aus Nachtrag (8).

**Gebaut: automatisches Ausweichen.** Faellt der direkte Weg aus (Guthaben,
Zeitlimit, nicht erreichbar), laeuft derselbe Opus 5 ueber WaveSpeed weiter,
statt dem Nutzer einen 502 zu zeigen. Der direkte Weg bleibt die Vorgabe.
Die Antwort meldet in `provider`, welcher Weg tatsaechlich geantwortet hat.
Geprueft nach dem Deploy: 4/4 HTTP 200, `provider: "wavespeed"`.

**Zu entscheiden:**
- Anthropic aufladen → die vielfaeltige Beurteilung kommt zurueck, Ausweichen
  bleibt als Netz.
- Oder `DIRECTOR_PROVIDER=wavespeed` dauerhaft → ein Schluessel, eine
  Abrechnung, aber fast immer zwei Vorschlaege.
- Stufe 1 laeuft weiter ueber fal. Sie auf WaveSpeed zu holen ist eigene
  Arbeit: `readPhoto` haengt fest am fal-Vision-Endpunkt.

## Nachtrag 04.09.2026 (11) — Alles über WaveSpeed

Auf Ansage: **kein fal, kein Anthropic direkt.** Beide Modelle, ein Schlüssel.

| Stufe | Modell | vorher | jetzt |
|---|---|---|---|
| 1 — Foto lesen | gemini-3.5-flash | `fal.run/openrouter/router/vision` | WaveSpeed |
| 2 — entscheiden | claude-opus-5 | `api.anthropic.com` | WaveSpeed |
| 3 — Ergebnis prüfen | claude-opus-5 | `api.anthropic.com` | WaveSpeed |

Stufe 3 war die stillste Falle: die Qualitätsprüfung hing an derselben
Anthropic-Rechnung, die leerlief. Sie schluckt Fehler absichtlich („eine
gescheiterte Prüfung darf ein gutes Bild nicht aufhalten") — sie wäre also
lautlos ausgefallen, ohne dass es jemand bemerkt hätte.

`callWaveSpeed` nimmt `tools` jetzt OPTIONAL. Lesung und Prüfung wollen reinen
JSON-Text; eine leere Werkzeugliste lehnen manche Modelle ab.

`DIRECTOR_PROVIDER` steht per Vorgabe auf `wavespeed`. Der Anthropic-Weg bleibt
im Code und ist über dieselbe Variable erreichbar — benutzt wird er nicht.

**Nach dem Deploy gemessen:**

| | Ergebnis | Dauer |
|---|---|---|
| Stufe 1, 3 Fotos | 3/3, je 26 Felder | 17–23 s |
| Stufe 2, 3 Fotos | 3/3, je 2 Picks | 36–45 s |
| Stufe 3, Gegenprobe | erkennt fremdes Bild: `major`, „Completely different person" | 9 s |
| Stufe 3, Nullprobe | erkennt „no perceptible change" | 9 s |

**Deshalb zwei Zeitlimits in `DirectorAPI.swift` angehoben:** Lesung 30 → 60 s
(gemessen bis 23 s), Zug 90 → 150 s (gemessen bis 45 s). Mit den alten Werten
wäre ein zäher Lauf kurz vor dem Ziel abgebrochen.

**Preis der Umstellung, gemessen:** ein Zug dauert jetzt rund 60 s statt 25,
und die Zahl der Vorschläge liegt fast immer bei 2 statt bei 1–3 — dem
OpenAI-Protokoll fehlen `thinking` und `effort`. Die Vielfalt aus Nachtrag (8)
ist damit teilweise wieder verloren; das ist der bewusst eingegangene Tausch
für einen Schlüssel und eine Abrechnung.

## Nachtrag 04.09.2026 (12) — Warum die Vorschläge ausblieben

Gemeldet: nach der Analyse nur noch Bild und Maskottchen, keine Vorschläge.

**Ursache gefunden und behoben: das Zeitlimit der Funktion.**
`api/gpt-image/[action].mjs` bedient ALLE DREI Director-Routen (chat, read,
review) und stand auf `maxDuration: 60`. Solange der Zug direkt über Anthropic
lief, brauchte er rund 13 s — reichlich Luft. Über WaveSpeed dauert derselbe
Zug 17–50 s, und wenn der Client keine Lesung mitschickt, laufen Lesung UND
Entscheidung in EINER Aufruf­instanz.

Reproduziert, dreimal, mit demselben Foto:

| Weg | HTTP | Dauer |
|---|---|---|
| read | 200 | 14–20 s |
| chat MIT Lesung | 200 | 17–43 s |
| chat OHNE Lesung | **504 FUNCTION_INVOCATION_TIMEOUT** | **60,3 s** |

Die App schickt genau dann keine Lesung mit, wenn die Lesung noch läuft oder in
ihr eigenes Zeitlimit gelaufen ist — auf dem alten Build 30 s, bei gemessenen
bis 24 s also knapp. Damit fällt sie in den Fall, der sicher scheitert.

`maxDuration` steht jetzt auf **300** (wie `kie/future-self`). Ein Lauf nach dem
Deploy: chat ohne Lesung, 47,5 s, HTTP 200, 2 Picks — die Grenze fällt weg.

**Danach neuer Anschlag: WaveSpeed-Guthaben leer.**
`director_http_403 · "group (…) balance not enough"`, reproduzierbar.
Stufe 1 (Gemini 3.5 Flash) läuft weiter — sie ist billig. Stufe 2 (Opus 5)
nicht: ~20k Token Systemprompt plus Bild, bei $5/$25 je Million.

Damit sind **beide** Konten leer: Anthropic seit heute Vormittag, WaveSpeed
seit den Messläufen. Ein erheblicher Teil davon geht auf die Messungen aus den
Nachträgen (9) bis (12) — rund 40 Opus-Aufrufe mit Bild an einem Tag.

**Zu tun, bevor weiter geprüft wird:** WaveSpeed aufladen. Ohne Guthaben ist
jede weitere Messung an Stufe 2 sinnlos.

## Nachtrag 04.09.2026 (13) — Der Director bildet eine Vision statt einen Befund

Umsetzung der Diagnose. Kein UI-Redesign, adaptive 1–3-Logik unangetastet.

**1. Repair-Pflichtregeln entfernt.** Alle drei Sätze aus der Diagnose sind raus:
„at least one of your directions should clear it", „one pick should deal with
them", „often the stronger pick". Ebenso „issues[0] gehört in deine eine Zeile".

**2. Zwei Ebenen im Schema.** `direction.internal_steps[]` (max 8, je ≤120
Zeichen) trägt die technische Arbeit. Der Prompt sagt ausdrücklich: eine
Störstelle ist fast nie eine Direction. Die App reicht die Schritte beim Rendern
als Checkliste an das Bildmodell weiter (`withSteps(_:_:)` in `AgentView`) —
sichtbar sind sie nirgends.

**3. Denkreihenfolge im Prompt** („HOW YOU THINK — IN THIS ORDER"): Moment
verstehen → Stärken sehen → Vision bilden → sichtbare Direction → *erst dann*
Schäden. Mit ausdrücklicher Nennung von `mood`, `location`, `time_of_day`,
`outfit` als Rohmaterial — die vier Felder, die vorher keine Regel hatten.

**4. Eigene Namen erlaubt.** Der Director darf Directions erfinden und mit
eigenem Slug versehen. Nichts hartcodiert.

**5. Lead-Frage neu:** „If I could show the user only ONE finished version of
this photo, which one would I choose?" Ein Cleanup darf Lead sein, wenn es
wirklich das Problem ist — ein kleiner Defekt nie.

**7. Eine Quelle für App und Director.** `loadTrends()` fällt jetzt auf
`/templates.json` derselben Auslieferung zurück — genau die Datei, aus der die
App ihre Kacheln lädt. `normalizeTrend` nimmt beide Formen an (gepflegte
Trendform und App-Vorlagenform); `subtitle` dient als `spot`, wenn keiner
gepflegt ist. Video-Vorlagen werden verworfen.

**8. Trend darf Pick und Lead sein** — im Prompt ausdrücklich erlaubt.
**Nachgewiesen:** bei `director_real_cafe` wurde „Pro-Look" aus `templates.json`
zum LEAD.

**9. Review kennt drei Fehlerarten:** `major` (Identität/Hände/neues Bild, bis
zu zwei Anläufe), **`look`** (technisch sauber, Richtung verfehlt — GENAU EIN
Anlauf), `minor` (kein Anlauf). iOS: `Review.Severity`, und
`refineIfNeeded` bricht bei `isLookMiss` nach dem ersten Versuch ab. Credits
weiterhin nur bei Erfolg.

**Zwei Fehler, die der Testlauf aufgedeckt hat:**
- `cleanOptions` verwarf Picks mit Prompt < 40 Zeichen. Seit es
  `internal_steps` gibt, legt das Modell die Substanz manchmal dorthin — ein
  Foto kam mit NULL Vorschlägen zurück. Jetzt werden Prompt und Schritte
  zusammengesetzt, statt die Richtung zu verlieren.
- Über das OpenAI-Protokoll lässt das Modell `picks` gelegentlich ganz weg
  (`required` wird dort nicht erzwungen). Das ergibt in der App einen toten
  Bildschirm. Jetzt GENAU EIN zweiter Anlauf, nur in diesem Fall.
- Neu: `debug: true` im Anfragerumpf liefert die rohe Werkzeugeingabe. Nur für
  die Fehlersuche, per Vorgabe aus.

### Testlauf, 12 Fotos

| lead-Modus | | Anzahl Picks | |
|---|---|---|---|
| retouch | 9 | 1 Pick | 1 |
| grade | 3 | 2 Picks | 11 |
| restage / generate | 0 | 3 Picks | 0 |

Leere Antworten: 0. Ø `internal_steps` je Pick: 5,6 (zwei Fotos: 0).

**Wichtig zur Deutung:** Der `retouch`-Anteil im MODUS ist geblieben — die
sichtbare Ebene hat sich aber umgedreht. Vorher hiessen die Leads „Clear the
flare", „Clean the neon mess", „Bring the skin back". Jetzt „Empty Alley Travel
Editorial", „Blue Hour Rooftop Editorial", „Late-Night Street Flash", „Just Her
And The Light". `mode` ist ein internes Etikett und steht auf keiner Karte.

## Nachtrag 04.09.2026 (14) — Form entscheiden, Formel verbieten

Drei gezielte Eingriffe, keine Architekturänderung.

**1. `decision_shape` wird VOR den Picks gesetzt.** Pflichtfeld im Werkzeug
(`single` | `alternatives` | `explore`). Im Prompt steht ausdrücklich: „Two is
not the safe middle" — wer aus Ausgewogenheit zu `alternatives` greift, hat
nicht entschieden, sondern voreingestellt.

Abgleich im Code, ohne Zusatzkosten und ohne Erfinden:
- **zu viele** Picks → auf die erklärte Zahl kürzen, den Lead zuerst; er darf
  nie der sein, der wegfällt
- **zu wenige** → nicht auffüllen (das wäre genau das Füllmaterial, das weg
  soll), stattdessen folgt die Form der Wirklichkeit
- Nach dem Kürzen wird der Lead neu bestimmt

GEMESSEN, 12 Fotos: **4× single / 8× alternatives / 0× explore** gegenüber
1× / 11× / 0× davor. Die Entscheidung bewegt sich also wirklich.

**2. Die Formel im Einzeiler.** Der erste Versuch („keine feste Konstruktion")
hat NICHTS bewirkt: 5 von 12 sagten weiter „is the whole photograph", 12 von 12
nutzten den Gedankenstrich-Pivot. Erst ein AUSDRÜCKLICHES VERBOT wirkte —
die Wendung namentlich verboten, den Pivot verboten, „gut, dann schlecht" als
Standardreihenfolge verboten, dazu Vorgaben zur Variation von Anfang und Länge.

| | „whole X" | Gedankenstrich | Wörter min/med/max |
|---|---|---|---|
| v2 (weiche Bitte) | 5/12 | 12/12 | 30/34/44 |
| v3 (Verbot) | 0/5 | 1/5 | 17/25/33 |

Lehre: Bei einem eingefahrenen Sprachmuster hilft „variiere" nicht. Nur die
Wendung beim Namen nennen und verbieten.

**3. Leere `internal_steps` ausdrücklich erlaubt** — in Schema und Prompt, mit
dem Prüfstein „würde das Weglassen diese Richtung sichtbar verschlechtern?".
NICHT NACHGEWIESEN: in beiden Läufen kam kein einziges leeres Array vor. Ob die
Regel greift, ist offen.

**4./5.** Lead-Logik unverändert. Zusätzlich gegen erzwungene Exotik: „An exotic
name on an ordinary decision is a costume."

### Abbruch des Testlaufs
Der dritte Durchlauf brach nach 5 von 12 Fotos ab — WaveSpeed-Guthaben leer
(`director_http_403 · balance not enough`). Die v3-Zahlen beruhen deshalb auf
5 Fotos, nicht auf 12. **Ursache waren meine eigenen Messläufe**: drei volle
12-Foto-Durchgänge sind 36 Opus-Aufrufe mit rund 20k Token Systemprompt, an
einem Tag, zusätzlich zu den Läufen aus Nachtrag (9)–(12).

## Nachtrag 04.09.2026 (15) — Anthropic direkt, und die Nachschlagetabelle raus

**Opus 5 läuft wieder direkt über Anthropic** (`DIRECTOR_PROVIDER` Vorgabe
`anthropic`). Grund ist der Cache, nicht der Preis — WaveSpeed berechnet
dieselben Tarife, kennt aber kein Prompt-Caching:

| | frisch je Zug | aus dem Cache | Kosten |
|---|---|---|---|
| direkt | 598 | 4.047 | **$0,029** |
| WaveSpeed | 8.985 | 0 | **$0,096** |

Neu **auch die Werkzeuge gecacht** (`cache_control` auf dem letzten Eintrag) —
rund 2.000 Token, die sonst jeden Zug voll kosteten.

Die **Ergebnisprüfung** läuft ebenfalls wieder direkt, mit Cache auf dem
Regelwerk und WaveSpeed als Netz. **Stufe 1 (Gemini) bleibt auf WaveSpeed:**
6,8 % der Kosten, 301 Token Prompt, jedes Bild ein anderes — nichts zu cachen.

Die Antwort meldet jetzt das Modell, das die API SELBST genannt hat
(`servedModel`), nicht unsere Konfiguration. Sonst liesse sich nie prüfen, ob
wirklich Opus 5 geantwortet hat.

### Die Nachschlagetabelle im Katalog

Gefunden bei der Prüfung auf Verallgemeinerbarkeit: `director-looks.mjs` hatte
je Look ein Feld `fits`, das als „Passt zu: …" in den Systemprompt ging —

```
nightflash   fits: 'Nachts draußen, Straße, Bar …'
sunsetbeach  fits: 'Außenaufnahmen, offener Himmel … später Nachmittag.'
cleangirl    fits: 'Porträts, Beauty …'
```

Das ist genau die Zuordnung Ort → Stil, die dafür sorgt, dass zwei völlig
verschiedene Nachtfotos dieselbe Antwort bekommen. **Feld umbenannt in
`condition` und inhaltlich umgeschrieben**: es steht jetzt, WORAN man im Bild
erkennt, dass ein Look tragen kann („Hinter dem Motiv sind punktförmige
Lichter, die zu Bokeh werden können, und die Umgebung ist dunkel genug für
Blitzabfall"). Bedingungen übertragen sich auf ungesehene Fotos, Kategorien
nicht. Dieselbe Umstellung bei den Trends.

Dazu zwei neue Prompt-Abschnitte:
- **„THE ONE MISTAKE THAT WOULD MAKE YOU USELESS"** — nie ein Attribut in einen
  Stil übersetzen; ein Ort ist kein Grund, eine Bedingung im Bild schon.
- **„HOW MUCH SHOULD CHANGE AT ALL"** — der Eingriffsumfang ist selbst Teil des
  Urteils, von „fast nichts" bis „Restaging". Das fehlte bisher ganz.

Ausserdem alle Beispiele entfernt, die aus dem 12-Foto-Testsatz stammten, plus
die Regel: Beispielformulierungen im Prompt zeigen eine FORM, nie Wörter zum
Übernehmen.

**NICHT GEPRÜFT.** Beide Konten sind leer (Anthropic *und* WaveSpeed), es liess
sich kein einziger Zug fahren. Syntax und Modulladen sind geprüft,
`looksForPrompt()` wurde ausgeführt. Das Verhalten ist offen.

## Nachtrag 05.09.2026 (16) — Der Katalog ist eine Ausführungs-, keine Entscheidungsbibliothek

Befund vorher: der Katalog **erzeugte** Ideen. Vier Ursachen, alle behoben.

**a) Position.** Die sieben Rezepte standen bei Zeichen ~3.400, die
Denkreihenfolge erst bei ~4.900 — das Modell las das Regal, bevor es erfuhr,
wie es denken soll. Jetzt: Denkreihenfolge @4.871, Bibliothek @13.093.

**b) Schritt 6** ergänzt: „Only after the photographic direction has been formed,
inspect the execution library … Never derive the vision from the existence of a
recipe."

**c) Frageichtung umgedreht.** `condition` → **`realizes`** (welche Vision das
Rezept bauen kann) plus **`requires`** (nachrangige technische Voraussetzung).
Im Prompt ausdrücklich: *„A satisfied Requires is never on its own a reason to
recommend a look."*

**d) Wissenshierarchie neu** — vorher „THE THREE THINGS YOU KNOW" mit Trends auf
Platz 1 und Katalog auf 2. Jetzt:
1. eigenes fotografisches Urteil über dieses Bild
2. allgemeines Foto-/Editing-Wissen
3. Hauskatalog als Ausführungsbibliothek
4. Trends als weitere verfügbare Ausführung

Dazu wörtlich: *„Neither 3 nor 4 is a starting point for an idea."* Und für die
Trend-Systemnachricht, die aus **Cache-Gründen** am Ende der Nachrichtenkette
steht: *„That is a technical detail of how they are delivered — it carries no
creative priority whatsoever."* Die technische Position bleibt unverändert.

**Ausnahme sauber getrennt:** fragt der Nutzer ausdrücklich nach einem Trend,
kippt die Rangfolge und die Aufgabe IST, den besten Trend für dieses Bild zu
finden — samt der Freiheit zu sagen, dass keiner passt.

Systemprompt jetzt 19.762 Zeichen ≈ 5.200 Token (vorher 4.675).
**Keine Modellaufrufe gemacht.** Verhalten weiterhin ungeprüft — beide Konten
sind leer.

## Nachtrag 05.09.2026 (17) — „Choose a trend" ist ein eigener Auftrag

Vorher rendete ein Tipp auf einen Trend direkt — der Director wurde nie gefragt.

**Zwei Aufgaben, zwei Prompts, bewusst getrennt.** Der normale Zug bildet erst
eine eigene Vision und prüft Trends danach als Ausführung. Die Trend-Auswahl
dreht das um, aber NUR weil der Nutzer ausdrücklich danach gefragt hat. Beides
in einen Prompt zu mischen hätte den normalen Director dazu gebracht, generell
Trends zu bevorzugen — deshalb `trendSelectionSystem()` mit eigenem, kurzem
Prompt (354 Token gegen 5.201 des grossen) und eigenem Werkzeug `rank_trends`.

**Die Bildlesung wurde bisher weggeworfen.** `DirectorAPI.read()` existiert,
wird aber nirgends aufgerufen; das Backend liefert `reading` in JEDER
Chat-Antwort mit, und die App hat sie ignoriert. Jetzt wird sie in
`AgentView.photoReading` behalten — gebunden ans FOTO, nicht an die Vorschläge:
sie fällt weg bei neuem Anhang und bei „Start over", nicht schon beim Wählen
einer Richtung. Damit kostet „nicht neu analysieren" nichts.

**Es geht kein Bild mit** und **es wird nichts gerendert.** Ohne vorhandene
Lesung wird gar nicht erst gefragt — dann bleibt es die Liste wie bisher.

**Der Director bewertet die Liste, die der NUTZER SIEHT.** Die App schickt ihre
`alleTrends` mit (id, label, caption); das Backend ergänzt Rezept und
Bedingung, wo eine id serverseitig bekannt ist. Sonst wäre „beste Passung"
wieder eine Behauptung über eine andere Liste.

UI im Sheet: `DIRECTOR'S TREND PICK` (grosse Vorschau + ein Satz warum) ·
`OTHER GOOD MATCHES` · `SEE ALL TRENDS`. Das alte Abzeichen auf der Kachel ist
entfallen. Sagt der Director, dass keiner passt, steht das als `MY HONEST
ANSWER` da. Der Nutzer kann weiterhin jeden Trend selbst wählen.

**Modellentscheidung steht aus** — läuft vorerst auf dem bestehenden Pfad
(Opus 5). Zahlen im Bericht an den Nutzer.

## Nachtrag 05.09.2026 (18) — Telemetrie für die Trend-Empfehlung

Modell bleibt `claude-opus-5`. Nichts umgestellt, nichts optimiert.

**Zwei Ereignisse, je eine strukturierte Zeile, KEIN zusätzlicher Modellaufruf.**

`phase: "ranked"` — beim Öffnen von „Choose a trend":
`id` · `verdict` (one_fits | none_fit | no_answer) · `bestId` · `alsoIds` ·
`why` (die Begründung des Directors) · `model` · `route` · `offered` (die
angebotenen ids) · `reading` (die vollständige Bildlesung).

`phase: "chosen"` — sobald der Nutzer im Fenster etwas wählt:
`id` · `chosenId` · `bestId` · **`followed`** · `hadRecommendation` · `source`.

`followed` ist die eine Zahl, an der sich die Qualität später ablesen lässt.
Gemeldet wird JEDE Wahl im Fenster — Empfehlung, Alternative oder etwas ganz
anderes aus der Liste; sonst liesse sich „übergangen" nicht von „nichts
gewählt" unterscheiden.

**Warum `console` und kein Speicher:** in dieser Auslieferung ist weder
`BLOB_READ_WRITE_TOKEN` noch Supabase gesetzt (geprüft). Eine Logzeile kostet
nichts und verzögert nichts. Nachteil: Vercel-Logs sind nur begrenzt haltbar.
Für den späteren Vergleich Opus/Haiku/Gemini reicht die Zeile inhaltlich — sie
enthält Lesung UND angebotene Liste, also denselben Fall — sie muss nur
rechtzeitig abgegriffen werden.

**Datenschutz:** die Bildlesung beschreibt einen Menschen (Kleidung, Ort,
Aussehen). `DIRECTOR_LOG_READING=off` lässt genau dieses Feld weg, alles andere
bleibt auswertbar.

Das Wahl-Ereignis läuft VOR der Bildlesung im Handler — es darf unter keinen
Umständen eine Analyse auslösen. Live geprüft: `{"ok":true}`, kein Modellaufruf.

## Nachtrag 05.09.2026 (19) — Zwei Bugs vor den echten Tests

**1. Die Qualitätsprüfung lief auf dem Hauptweg nicht.**
`refineIfNeeded` wurde nur aus `runEdit` gerufen — dem Weg, den der Director
selbst wählt und den der Prompt zur Ausnahme erklärt. Der Weg, den fast jeder
Nutzer geht (Tap auf eine Richtung → `runDirectorSet`), enthielt **null**
Vorkommen von `review` oder `refine`. Identität, Hände, „sieht aus wie ein neues
Bild" und der verfehlte Look wurden dort nie geprüft, obwohl die ganze Logik
bereitstand.

Jetzt ruft `runDirectorSet` denselben `refineIfNeeded` auf, mit einer aus dem
Pick gebauten `Action` (`prompt: request.prompt`, `mode: option.mode`).
Retry-Grenzen unverändert: `for attempt in 1...2`, `isLookMiss` bricht nach dem
ersten ab. `store.consume(costPerImage)` läuft weiter genau einmal je Bild,
danach und nur bei Erfolg — interne Anläufe kosten den Nutzer nichts.

**2. `option.mode` wurde beim Rendern weggeworfen.**
Entfernt:
```swift
let isCreative = label.contains("new moment") || label.contains("reimagine")
                 || (index == 2 && !label.contains("keep it real"))
let isSocial   = label.contains("post-ready") || (index == 1 && !isCreative)
```
Die Bezeichnungen erfindet der Director frei, also traf die Textsuche nie —
faktisch entschied die **Position im Array**. Vorschlag 3 bekam den kreativen
Vertrag, der neue Pose, Ausschnitt und Umgebung erlaubt.

Neu `renderContract(_:mode:)`:

| mode | Vertrag |
|---|---|
| `grade` | `compositionLockedPrompt` — nur Licht und Farbe |
| `retouch` | SOCIAL EDIT CONTRACT — gleiche Szene, Cleanup erlaubt |
| `restage` | CREATIVE PHOTO CONTRACT — Pose/Ort frei, Identität gesperrt |
| `generate` | kein Personenvertrag; der Auftrag steht allein |

Die Vertragstexte sind **wörtlich unverändert** übernommen, nur die Auswahl ist
neu. `withSteps(...)` umschliesst weiterhin alle vier Modi, `internal_steps`
fliessen also überall ein.

**Mitgezogen, weil sonst widersprüchlich:** die Nachbesserung in
`refineIfNeeded` nutzte fest `compositionLockedPrompt`. Bei einem `restage`
hätte der zweite Anlauf genau das verboten, was der Auftrag verlangt. Sie nutzt
jetzt `renderContract(corrected, mode: action.mode)`.

## Nachtrag 05.09.2026 (20) — Der Nutzer verstand nicht, was der Director tut

Gemeldet vom Erbauer selbst: „ich checke nicht, was er macht."

**Ursache: auf dem Schirm standen zwei Systeme nebeneinander, die nichts
miteinander zu tun hatten.**
- Der Zettel „WHAT I'D DO" kam aus `DirectorReadMarks` — einer lokalen
  Helligkeitsrechnung auf einem 48x48-Raster, aus sieben festen Textbausteinen.
  Nicht der Director. Und dieselbe Messung zeichnet schon die Kritzel auf dem
  Foto, es stand also zweimal dasselbe da.
- **Der eine Satz, den der Director wirklich sagt, wurde nirgends angezeigt.**
  `verdict: letzter?.text` wurde an die Werkbank uebergeben und dort genau
  einmal erwaehnt: in der Deklaration.

Behoben: der Zettel heisst `WHAT I SEE` und zeigt seinen Satz.

**Auswahl statt Sofortrendern.** Ein Tipp auf eine Karte WAEHLT sie jetzt
(Ring in Akzentfarbe) — er kostet keine Credits mehr. Darunter erscheinen:
- eine **Sprechblase mit dem Kopf der Figur**, die in einem Satz sagt, was das
  ist. Text aus vorhandenen Daten, KEIN zusaetzlicher Modellaufruf: die
  Beschreibung des Haus-Looks plus die Begruendung des Directors.
- ein einziger klarer Knopf **„Make it <Name>"**. Erst der rendert.

**Zwei Fehler dabei, im Simulator gesehen und behoben:**
1. Die Blase hing zuerst AN der Figur — und war damit unsichtbar: wer Karten
   aussucht, hat weit heruntergescrollt, die Figur steht dann ausserhalb des
   Bildes. Jetzt spricht sie von dort, wo der Nutzer hinsieht.
2. Der Satz stand doppelt, wenn die Begruendung des Directors woertlich die
   Beschreibung des Looks ist. Jetzt wird nur vorangestellt, was sich
   unterscheidet.

Dazu mehr Luft: Abstand zwischen den Bloecken von 18 auf 26.

**Kosten fuer den Nutzer sinken:** vorher konnte ein versehentlicher Tipp
sofort Credits ausgeben, ohne dass jemand wusste, was die Karte bedeutet.

## Nachtrag 05.09.2026 (21) — Ladeanzeige und nichts geht mehr verloren

**1. Die Anzeige erzählt jetzt, was passiert.** Waehrend des Erstellens stand
minutenlang „AI rendering" — und ein Bildschirm, der sich nicht bewegt, sieht
aus wie ein Absturz. Jetzt meldet `pollTask` ueber `onTick` die vergangenen
Sekunden, und `renderNote(seconds:)` macht daraus eine Zeile mit laufender Uhr:

```
Setting up your image            0:04
Painting the light and colour    0:18
Working on the detail            0:52
Almost there — this one's taking its time   1:40
```

Danach uebernehmen die vorhandenen Zeilen der Pruefung („Checking the result…",
„Fixing: …"). Erstellen und Pruefen sprechen damit dieselbe Sprache, und der
Nutzer sieht, WARUM es laenger dauert. Die Uhr ist kein Fortschritt — den gibt
der Dienst nicht her — sondern ein Lebenszeichen.

**2. Ein Auftrag geht nicht mehr verloren.**

Der Befund: `GenerationManager` kann das alles laengst — Bildaufgaben ueber
`ImageEditAPI`, Hintergrundzeit ueber `beginBackgroundTask`, Fortsetzen ueber
`resumePendingProjects()` beim Start, Bibliothek, Credit-Erstattung. **Der
Director benutzte ihn nur nicht:** er pollte in einer Ansicht-`Task` mit
lokaler Aufgaben-Nummer und legte den Bibliothekseintrag erst NACH dem Erfolg
an. Wer die App waehrend des Rechnens verliess, hatte danach nichts — obwohl
der Dienst weiterrechnete.

Jetzt:
- `startProject(...)` legt das Projekt an, BEVOR gerendert wird, mit Status
  `.running`; die Aufgaben-Nummer wird eingetragen, sobald sie da ist.
- `generationManager.claimExternal(id)` haelt die Hintergrundzeit offen —
  aber der Manager pollt NICHT mit. Zwei Schleifen auf derselben Aufgabe
  wuerden das Projekt doppelt abschliessen.
- Stirbt der Prozess, ist `externallyDriven` beim naechsten Start leer →
  `resumePendingProjects()` findet ein laufendes Bild mit Nummer und zieht es
  zu Ende. Genau dafuer ist es da.
- `finishProject` / `abortProject` tragen Ergebnis oder Fehler in DASSELBE
  Projekt ein. Der doppelte Bibliothekseintrag am Ende ist entfallen.

Credits weiterhin nur bei Erfolg und genau einmal.

## Nachtrag 05.09.2026 (22) — Die Trendkarte ist eine Zeile

Gemeldet: der Bereich unter der Analyse sei grafisch ueberfuellt. Gezaehlt
standen dort SIEBEN Bildsprachen uebereinander — Kritzel, Zettel, Polaroids,
Sprechblase, Vollknopf, dunkle Trendkarte, Glaskapsel.

Die Trendkarte war der groesste Posten: Ueberschrift mit Linie und Zaehler,
ein 168 pt hohes Bild mit Verlauf und zwei Overlay-Texten, vier Miniaturen,
eine Fusszeile mit Pfeil. Eine halbe Bildschirmseite fuer eine NEBENfunktion.

Jetzt eine Zeile: drei versetzte Miniaturen, „TIKTOK TRENDS", darunter
„Best match: <Name>" (oder die Anzahl, wenn der Director noch keine Passung
genannt hat), rechts ein Pfeil. Sie leistet dasselbe — es gibt Trends, so
viele, und der hier passt — und das grosse Bild steht im Pop-up, wo man es
ohnehin braucht.

`uebrigeTrends` wurde damit ueberfluessig und ist entfernt.

**Bewusst NICHT angefasst** (ausdruecklich so entschieden): die Kritzel auf
dem Foto bleiben, ebenso Zettel, Polaroids, Sprechblase und Knopf.

## Nachtrag 06.09.2026 (23) — Kein Zettel, keine Polaroids

Gemeldet: „WHAT I SEE passt nicht, da steht immer irgendetwas und hilft nichts —
man müsste direkt sehen, was kann ich machen." Und: die Polaroid-Karten nehmen
zu viel Platz und stören.

**Der Zettel ist weg.** `DirectorNote.swift` gelöscht, `verdict` aus
`DirectorWorkspace` und dem Aufruf in `AgentView` entfernt. Er trug seinen
einen Satz — aber die Frage des Nutzers ist nicht „was denkt er", sondern „was
kann ich machen". Diese Frage beantworten die Kacheln, und die Begründung
hängt an der Auswahl, wo sie gebraucht wird.
**Bewusst in Kauf genommen:** seine Einschätzung zum UMFANG („ich würde hier
kaum etwas anfassen") ist damit nicht mehr sichtbar.

**Die Polaroids sind weg.** `DirectorPolaroids.swift` gelöscht. Sie brachten
210 pt Foto, Rand, Schräglage, Schatten und beschrifteten Streifen für zwei
Wählbare — zusammen mit Kritzeln, Sprechblase und Trendkarte war der Schirm
voll, ohne mehr zu sagen.

Stattdessen `kachelKlein`: Bild und Name, sonst nichts. Höhe nach Anzahl —
168 pt bei einer Richtung, 148 bei zwei, 116 bei drei. Der `lead` trägt weiter
„MY PICK". Der Gruss während des Wurfs (`DirectorGreetingView`) bleibt und hält
dieselbe Höhe, sonst springt beim Landen die halbe Seite.

**Ergebnis: der ganze Ergebnis-Bildschirm passt jetzt ohne Scrollen** —
Foto mit Kritzeln + Figur · WHAT I'D MAKE + Kacheln · (gewählt) Sprechblase +
Knopf · Trendzeile · Glasleiste.

Beim Ersetzen sind mir Sprechblase und Knopf mit herausgerutscht; im Simulator
gesehen (Ring da, Blase und Knopf fehlten) und wieder eingesetzt.
