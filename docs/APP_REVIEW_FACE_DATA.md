# App Review — Face Data Responses (Guideline 2.1)

Paste these answers into **App Store Connect → App Review** when replying to the “Information Needed” message about face data.

Privacy Policy URL: **https://njscalp.github.io/Clavic/privacy.html**  
Face data section: **https://njscalp.github.io/Clavic/privacy.html#face-data**

---

## 1. What face data does the app collect?

Clavic does **not** collect face data in the background and does **not** create biometric identifiers (no faceprints, face templates, or face-recognition profiles).

The app only processes face data when the user **actively selects and uploads** a photo (via Apple’s photo picker) to generate or edit content — for example a selfie used in a fan-cam template, image edit, or similar feature. We do not scan the photo library, do not use the camera without user action, and do not perform identity verification.

---

## 2. Provide a complete and clear explanation of all planned uses of the collected face data.

Face data is used **solely** to fulfill the user’s explicit generation request — for example placing the user’s likeness into a chosen template or editing their photo as instructed. Uses include:

- Image-to-image edits (outfit, background, style, enhancement)
- Video generation where the user’s face/body from their photo is animated into a template scene (dance, fan cam, etc.)

We do **not** use face data for advertising, analytics, user identification, account verification, or training AI models.

---

## 3. Will the face data be shared with any third parties? Where will this information be stored?

**Sharing:** The user-selected photo is transmitted over HTTPS to our processing backend (hosted on **Vercel Inc., USA**) and then to our AI provider (**kie.ai**) **only** to produce the requested result. Face data is **not sold** and **not shared** with any other third party.

**Storage:**
- **On device:** Finished images/videos are stored locally on the user’s device until deleted in the app.
- **Our servers:** We do **not** retain a copy of uploaded face photos on our own servers.
- **Processors:** Uploaded input is held temporarily by Vercel/kie.ai only to complete the request and is deleted automatically shortly afterwards (within approximately 24 hours).

Sign in with Apple and in-app purchases are handled by **Apple**; we do not receive face data from Apple.

---

## 4. How long will face data be retained?

| Location | Retention |
|----------|-----------|
| User’s device (results) | Until the user deletes the project or uninstalls the app |
| Uploaded input (processors) | Temporary — deleted automatically after processing, typically within ~24 hours |
| Our own servers | Not retained |
| Biometric data / faceprints | Never created or stored |

---

## 5. Where in the privacy policy is face data explained? (specific sections)

| Topic | Policy section |
|-------|----------------|
| What data we process (overview) | **§2 What data we process** |
| Face data — collection, use, sharing, retention | **Face data** (subsection under §2, HTML id `face-data`) |
| AI processing providers | **§4 AI processing and providers** |
| General retention | **§5 Storage and retention** |
| Photo library access | **§6 Photo library access** |
| User rights (GDPR) | **§8 Your rights** |

---

## 6. Quote the specific text from the privacy policy concerning face data

> **Face data**
>
> Some photos you choose to upload may contain faces (for example a selfie you use for a face-swap, look or "Pinterest swap" template). We treat this as **face data** and handle it as follows:
>
> - **What we collect:** only the photos you yourself select and upload as input. We do **not** scan your photo library, we do **not** use the camera in the background, and we do **not** create faceprints, biometric identifiers, face templates or any face-recognition data.
>
> - **How we use it:** solely to generate the specific image or video you requested (for example placing your face into a chosen template). We never use face data to identify or verify you, for advertising, for analytics, or to train AI models.
>
> - **Sharing:** the photo is sent over an encrypted connection to our processing backend (Vercel Inc., USA) and to our AI provider (kie.ai) only to produce your result. Face data is **not** sold and **not** shared with any other third party.
>
> - **Storage & retention:** your finished results are stored locally on your device until you delete them. The uploaded photo is held by the processing providers only temporarily to complete the request and is deleted automatically shortly afterwards (within about 24 hours). We do **not** keep a copy of your face data on our own servers and we do **not** retain any biometric data.

(Source: https://njscalp.github.io/Clavic/privacy.html — section “Face data”)

---

## Additional note for reviewer

Clavic is rated 17+ and requires users to accept a content policy before uploading photos. Templates that could generate intimate contact between people have been removed from the app in this submission.
