# Was läuft wo

Stand 09.09.2026. Diese Datei ist die Antwort auf „wo läuft eigentlich was?".
Wenn etwas hier nicht mehr stimmt, gilt sie als falsch — nicht die Wirklichkeit.

## Die drei Teile

| Teil | Ordner | GitHub | Läuft auf |
|---|---|---|---|
| iOS-App | `~/Desktop/Clavic/Clavic` | `NJscalp/Clavic` (öffentlich) | App Store |
| KI-Backend | `~/Desktop/Day One/limitless-web` | `NJscalp/limitless-web` (öffentlich) | Railway |
| Website | `~/Desktop/clavic-web` | `NJscalp/clavic-web` (privat) | Railway |

Backend und Website bauen bei jedem Push auf `main` automatisch neu.

## Adressen

```
Backend    https://clavic-backend-production.up.railway.app
Website    https://www.clavic.cc          ← Railway, hier verlinken
           https://clavic.cc              ← noch Vercel, Kauf defekt
```

**Verlinke überall `www.clavic.cc`.** Auf `clavic.cc` liegt noch die
Vercel-Version mit einem inzwischen ungültigen Stripe-Schlüssel — der Checkout
schlägt dort fehl.

## Was noch offen ist

**1. App-Update einreichen.** `SeedanceAPI.swift` zeigt bereits auf Railway,
aber die Adresse ist fest einkompiliert. Erst ein neuer Build im App Store
bringt sie zu den Nutzern. Bis dahin sprechen alle installierten Apps mit
Vercel.

**2. `clavic.cc` umziehen.** Braucht Cloudflare als DNS-Anbieter; warum, steht
in `clavic-web/RAILWAY.md`. Domain bleibt bei Spaceship, nur die Nameserver
wechseln.

**3. Vercel abschalten — zuletzt.** Erst wenn 1 und 2 erledigt sind. Vorher
brechen alle Apps, deren Nutzer nicht aktualisiert haben.

## Was übersprungen wurde

**kie.ai** hat keinen gültigen Schlüssel mehr. Betroffen sind allein die
Vorlagen **Fruit Story** und **Brainrot** — sie sind die einzigen, die
`provider: "kie"` schicken. Sie sind in der App noch antippbar und liefern
einen Fehler. Alles andere läuft über WaveSpeed und ist nicht betroffen.

## Was du nicht noch einmal versuchen solltest

**Einen A-Eintrag für `clavic.cc` auf Railways IP.** Der Server antwortet,
aber Railway stellt kein Zertifikat aus, weil die Prüfung den CNAME sucht.
Ergebnis ist eine Sicherheitswarnung im Browser und eine unerreichbare Seite.
Am 09.09.2026 probiert, 20 Minuten Ausfall.

## Bekannte offene Punkte

**Das Backend hat keine Zugangssperre.** `APP_SHARED_SECRET` ist nicht gesetzt,
und ohne gesetztes Secret lässt `api/_shared/auth.mjs` jede Anfrage durch. Wer
die Adresse kennt, kann das Backend auf deine Rechnung benutzen. Einschalten
geht nur zusammen mit einem App-Update, weil die App das Secret mitschicken
muss (`SeedanceAPI.swift`, `sharedSecret`).

**Glow-up ist kaputt** — betrifft nicht Clavic, sondern die andere App, die
sich das Backend teilt. `claude-sonnet-4-20250514` steht als Vorgabe im Code
und gibt es nicht mehr; nach Umstellung auf ein aktuelles Modell kam als
nächster Fehler ein veraltetes `temperature`-Feld. War schon vor dem Umzug so.

**Drei Trend-Vorschauen ohne geklärte Bildrechte** — Red Sunset, Y2K Digicam,
Red Light. Siehe `docs/TIKTOK_TRENDS.md`, Abschnitt „Open item before release".
