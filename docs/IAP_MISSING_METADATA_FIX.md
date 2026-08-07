# App Store Connect: „Fehlende Metadaten“ bei IAPs beheben

**Wichtig:** Du musst die Produkte **nicht neu anlegen**, wenn die IDs schon existieren (`Clavic.W`, `Clavic.Y`, …). Gelöschte Product IDs kann Apple **nie wieder verwenden** — dann müsstest du auch den App-Code ändern.

In 90 % der Fälle bleibt der Status „Missing Metadata“, obwohl alles „ausgefüllt“ wirkt, weil **ein verstecktes Pflichtfeld** fehlt — nicht weil die Produkte kaputt sind.

---

## Schnell-Check (5 Minuten)

Geh der Reihe nach durch. Hake ab, was schon erledigt ist:

### A) Verträge & Banking (blockiert ALLES)

**App Store Connect → Business (Geschäftliches) → Agreements**

| Punkt | Status muss sein |
|-------|------------------|
| **Paid Applications** (Kostenpflichtige Apps) | **Active / Aktiv** |
| Bankkonto | Hinterlegt |
| Steuerformulare (W-8BEN / EU) | Ausgefüllt |

Ohne aktives Paid-Applications-Agreement zeigen IAPs oft dauerhaft „Fehlende Metadaten“.

---

### B) Abo-**Gruppe** lokalisieren (häufigster Fehler!)

**Monetization → Subscriptions → Klick auf die Gruppe** (z. B. „Clavic Membership“)  
**Nicht** auf ein einzelnes Abo klicken.

1. Scrolle zu **App Store Localization** (oder „Lokalisierungen“)
2. Klicke **+** (Plus)
3. Sprache: **English (U.S.)** (oder German — mindestens eine!)
4. **Subscription Group Display Name:** `Clavic Pro`
5. Optional **App Name:** `Clavic` (falls abgefragt)
6. **Save / Sicher**

→ Seite neu laden. Danach sollten die Abos in der Gruppe oft von „Missing Metadata“ auf **Ready to Submit** springen.

---

### C) Jedes Abo einzeln (3 Stück)

**Monetization → Subscriptions → [Gruppe] → [Produkt]**

Für **Clavic.W**, **Clavic.Y**, **Clavic.2M** jeweils:

| Feld | Pflicht | Wert |
|------|---------|------|
| Reference Name | ✅ | siehe unten |
| Duration | ✅ | 1 Week / 1 Year / 2 Months |
| Price | ✅ | Preisstufe wählen (z. B. $9.99 / $149.99 / $29.99) |
| **Cleared for Sale** | ✅ | **Ein** |
| Localization (mind. 1 Sprache) | ✅ | Display Name + **Description** (Description darf nicht leer sein!) |
| **Review → Screenshot** | ✅ | Paywall-Screenshot (siehe unten) |

#### Texte zum Kopieren (English U.S.)

**Clavic.W — Weekly**
- Display Name: `Weekly`
- Description: `10 credits every week, access to all templates, no watermark. Renews automatically until cancelled.`

**Clavic.Y — Yearly**
- Display Name: `Yearly`
- Description: `150 credits per year, access to all templates, no watermark. Best value. Renews automatically until cancelled.`

**Clavic.2M — 2 Months**
- Display Name: `2 Months`
- Description: `45 credits over 2 months, access to all templates, no watermark. Renews automatically until cancelled.`

---

### D) Jedes Consumable einzeln (3 Stück)

**Monetization → In-App Purchases → [Produkt]**

Für **Clavic.10**, **Clavic.30**, **Clavic.75**:

| Feld | Pflicht |
|------|---------|
| Type | **Consumable** |
| Reference Name | ✅ |
| Price | ✅ |
| **Cleared for Sale** | ✅ **Ein** |
| Localization (Display Name + Description) | ✅ |
| **Review → Screenshot** | ✅ |

#### Texte zum Kopieren

**Clavic.10**
- Reference Name: `40 Credits Pack`
- Display Name: `40 Credits`
- Description: `One-time purchase of 40 credits for AI image and video generation. Credits do not expire.`

**Clavic.30**
- Reference Name: `110 Credits Pack`
- Display Name: `110 Credits`
- Description: `One-time purchase of 110 credits for AI image and video generation. Credits do not expire.`

**Clavic.75**
- Reference Name: `220 Credits Pack`
- Display Name: `220 Credits`
- Description: `One-time purchase of 220 credits for AI image and video generation. Credits do not expire.`

---

### E) Review-Screenshot (sehr oft vergessen!)

Für **jedes** der 6 Produkte (3 Abos + 3 Consumables):

1. Produkt öffnen → **App Review Information** / **Review Information**
2. **Screenshot** hochladen (nur für Review, nicht im Store sichtbar)
3. Mindestgröße: z. B. **640 × 920** px oder iPhone-Screenshot-Format

**Was zeigen:** Die Paywall in der App, auf der das Produkt sichtbar ist:
- Abos: Sheet mit Weekly / Yearly (Screenshot von `PaywallView`)
- Credits: `CreditsView` mit den drei Credit-Packs

Tipp: Simulator → Paywall öffnen → `Cmd + S` → hochladen. **Derselbe Screenshot** kann für alle 6 Produkte verwendet werden, wenn alle auf dem Bild erkennbar sind — oder je Produkt ein zugeschnittenes Bild.

---

### F) IAPs an die App-Version hängen

**My Apps → Clavic → [deine Version, z. B. 1.0] → unten**

Sektion **In-App Purchases and Subscriptions** (oder „In-App-Käufe“):

1. **+** klicken
2. Alle 6 Produkte auswählen, die **Ready to Submit** sind
3. Speichern

Ohne diesen Schritt kann Review die Käufe nicht prüfen (Ablehnung 2.1b).

---

### G) Zusammen mit Binary einreichen

1. Neues Build hochladen (Build-Nummer erhöhen)
2. Build der Version zuweisen
3. IAPs an Version gehängt (Schritt F)
4. **Submit for Review**

IAPs werden **mit** der App-Version reviewt, nicht isoliert (außer du nutzt explizit „Submit for Review“ pro IAP nach erstem Binary).

---

## Status-Bedeutung

| Status | Bedeutung |
|--------|-----------|
| **Missing Metadata** | Mindestens ein Pflichtfeld fehlt (oft Gruppen-Lokalisierung oder Screenshot) |
| **Ready to Submit** | Metadaten vollständig — kann an Version gehängt werden |
| **Waiting for Review** | Eingereicht |
| **Approved** | Freigegeben |

---

## Wann wirklich NEU anlegen?

Nur wenn:
- Produkt-ID **nie** in diesem App-Account angelegt wurde, **oder**
- Apple Support bestätigt, dass die ID dauerhaft defekt ist

**Neue IDs** (Beispiel, nur wenn nötig):
```
clavic.sub.weekly
clavic.sub.yearly
clavic.sub.twomonth
clavic.credits.40
clavic.credits.110
clavic.credits.220
```

Dann müssten `Store.swift`, `Products.storekit` und **RevenueCat** angepasst werden.

**Empfehlung:** Erst Schritte A–F — in den meisten Fällen reicht das.

---

## RevenueCat (falls aktiv)

Nach Änderungen in App Store Connect:

**RevenueCat Dashboard → Clavic → Products**

- Dieselben Product IDs wie in der App
- Entitlements / Offerings verknüpft
- App Store Shared Secret in RevenueCat hinterlegt

---

## Checkliste zum Abhaken

```
[ ] Paid Applications Agreement = Active
[ ] Bank + Steuer = vollständig
[ ] Subscription GROUP Localization (Display Name) gesetzt
[ ] Clavic.W — Preis, Lokalisierung, Screenshot, Cleared for Sale
[ ] Clavic.Y — Preis, Lokalisierung, Screenshot, Cleared for Sale
[ ] Clavic.2M — Preis, Lokalisierung, Screenshot, Cleared for Sale
[ ] Clavic.10 — Preis, Lokalisierung, Screenshot, Cleared for Sale
[ ] Clavic.30 — Preis, Lokalisierung, Screenshot, Cleared for Sale
[ ] Clavic.75 — Preis, Lokalisierung, Screenshot, Cleared for Sale
[ ] Alle 6 Produkte an App-Version gehängt
[ ] Neues Binary hochgeladen + Submit for Review
```
