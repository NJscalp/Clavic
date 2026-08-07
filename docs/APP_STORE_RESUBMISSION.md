# App Store Resubmission Checklist (Clavic)

Use this checklist before resubmitting build **6780159019** after the June 2026 rejection.

---

## 1. Guideline 1.1 — Objectionable Content (code changes ✅)

**What Apple flagged:** Templates that could generate intimate contact (hugging, kissing).

**Fixed in this build:**
- Removed/archived face-swap fashion templates (Red Dress Night, City Streetstyle, Summer Stroll, Studio Chic, Sunset Boho)
- Archived 7-Eleven Night (two-person candid POV), Pinterest Swap, You're Next Opponent
- Removed captain-kiss music-video pipeline code
- Removed “add a second person” quick-edit preset
- Added client-side `ContentPolicy` filter for user prompts (kiss/hug/intimate/sexual terms)
- Strengthened upload consent copy

**App Review note (paste into App Store Connect → App Review Information → Notes):**

> We removed all templates that could be used to generate intimate contact between people. Archived templates are no longer visible in Discover. User-entered prompts that describe kissing, hugging or sexual content are blocked client-side. Users must agree to our content policy before uploading photos.

---

## 2. Guideline 2.3.3 — Screenshots (App Store Connect — you must do this)

Apple rejected marketing screenshots that do not show the real in-app UI.

**Do this in App Store Connect → your app → Previews and Screenshots:**

1. Open **View All Sizes in Media Manager** (required for some sizes).
2. Replace screenshots with **real captures from the current build** on device or Simulator:
   - **Screenshot 1:** Discover tab with template grid
   - **Screenshot 2:** Create flow (template selected, photo picker)
   - **Screenshot 3:** Chat Edit / image editing
   - **Screenshot 4:** Library with finished creation
   - **Screenshot 5 (optional):** Credits / subscription sheet (dismissible)
3. **Do not use:** pure marketing graphics, fake UI mockups, splash/login-only screens as majority.
4. Use the same light theme the app ships with.

Tip: `Cmd+S` in Simulator, or iPhone screenshots after installing the TestFlight/production build.

---

## 3. Guideline 2.1 — Face Data (App Review reply)

Copy the answers from **`APP_REVIEW_FACE_DATA.md`** into App Store Connect → App Review → reply to the “Information Needed” message.

Ensure Privacy Policy URL is: **https://njscalp.github.io/Clavic/privacy.html** (section **Face data**, anchor `#face-data`).

---

## 4. Guideline 2.1(b) — In-App Purchases not submitted

Apple cannot finish review until **all IAP products referenced in the app** are submitted with metadata.

**Products in app (`StoreIDs`):**

| Product ID   | Type        | Name in UI   |
|-------------|-------------|--------------|
| `Clavic.W`  | Auto-renewable subscription | Weekly |
| `Clavic.Y`  | Auto-renewable subscription | Yearly |
| `Clavic.2M` | Auto-renewable subscription | 2 Months (win-back; optional) |
| `Clavic.10` | Consumable  | Credit pack |
| `Clavic.30` | Consumable  | Credit pack |
| `Clavic.75` | Consumable  | Credit pack |

**Steps in App Store Connect:**

1. **My Apps → Clavic → Monetization → In-App Purchases**
2. For **each** product above:
   - Status must be **Ready to Submit** (not Missing Metadata)
   - Add **Display Name**, **Description**, **Price**
   - Upload **Review Screenshot** showing the paywall/credits screen where the product appears (required!)
3. **Subscriptions:** create/verify subscription group, add localization
4. Submit IAPs for review **together with** the new app binary
5. Upload new build → select the submitted IAPs on the version page → Submit for Review

---

## 5. Guideline 5.6 — Manipulative IAP (code changes ✅)

**What Apple flagged:** Forcing purchases (hard paywall, dark patterns).

**Fixed in this build:**
- Removed blocking hard paywall after sign-in — app is usable without subscribing
- New users receive **3 welcome credits** once after sign-in
- Subscription offer is a **dismissible sheet** (`PaywallView` with close button), shown only once
- Credits/subscription upsell when user runs out of credits (standard pattern)
- Removed pulsing CTA manipulation from onboarding gate

**App Review note:**

> Users can explore the full app after Sign in with Apple without purchasing. They receive 3 welcome credits to try generation. The subscription screen can be dismissed with the X button and is shown only once. Purchases are optional; credits can also be bought as consumable packs.

---

## Build & submit order

1. Bump build number in Xcode
2. Archive → Upload to App Store Connect
3. Fix screenshots (section 2)
4. Submit all IAPs with review screenshots (section 4)
5. Reply to Face Data questions (section 3 + `APP_REVIEW_FACE_DATA.md`)
6. Paste App Review notes (sections 1 + 5)
7. Submit version for review

---

## Privacy policy deploy

If you changed `Clavic/docs/privacy.html`, push to GitHub Pages so the live URL matches:

```bash
cd Clavic/docs
git add privacy.html
git commit -m "Update privacy policy face data section"
git push
```

Verify: https://njscalp.github.io/Clavic/privacy.html#face-data
