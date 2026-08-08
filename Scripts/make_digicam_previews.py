import base64, json, time, urllib.request, sys, subprocess, os
BASE="https://limitless-web-beryl.vercel.app"
CAT="/Users/normannjungbauer/Desktop/Clavic/Clavic/Clavic/Assets.xcassets"

KEEP = ("Keep the exact same person: same face and every feature of it, same hair, same skin tone "
"and real skin texture, same build and body proportions, same age, same outfit. Do NOT beautify, "
"slim, smooth, retouch or redraw them. Keep the exact same pose, framing, composition and scene - "
"change ONLY the look of the photograph.")
TAIL = ("Skin keeps visible pores and real texture - this is a colour grade, not a retouch. The grade "
"covers the whole frame, person and background equally. Photorealistic, looks like a real photo "
"straight out of the camera. No text, no logos, no watermark.")

STYLES = {
 "digix": ("face_model_3",
   "Grade it like a 2000s compact digital camera on a bright day: high contrast, deep crushed "
   "blacks, warm glowing highlights around hair and edges around 3800K, punchy saturated colour, "
   "a gentle vignette darkening the corners, fine sensor noise in the shadows."),
 "digicam": ("face_model_1",
   "Grade it like a 2000s compact digital camera at night indoors: warm tungsten and candlelight "
   "around 2900K pushed up, glossy specular highlights on the skin, saturated warm midtones, the "
   "background falling away into deep black, visible high-ISO noise."),
 "digis": ("face_model_5",
   "Grade it like a 2000s compact camera with direct on-camera flash after sunset: deep blue sky, "
   "hot warm flash highlights on the skin and the nearest surfaces, high micro-contrast, crisp "
   "point lights in the distance, slight falloff into darkness at the frame edges."),
 "digilite": ("face_model_4",
   "Grade it like a bright airy daylight compact camera photo around 5600K: low contrast, lifted "
   "milky blacks, soft pastel colour, clean bright whites, very fine grain, nothing crushed."),
 "cleangirl": ("face_model_2",
   "Grade it in the clean-girl look: warm bright skin with a subtle natural glow, clean neutral "
   "whites, soft gentle contrast, muted beige and cream tones, barely any grade on the background."),
 "bw": ("face_model_1",
   "Convert it to high-contrast black and white: deep true blacks, bright clean highlights, the "
   "full range of mid greys in between, visible film grain, no colour anywhere."),
}

def post(path, body, timeout=90):
    r=urllib.request.Request(BASE+path, data=json.dumps(body).encode(),
        headers={"Content-Type":"application/json"}, method="POST")
    with urllib.request.urlopen(r, timeout=timeout) as resp: return json.loads(resp.read())

def source(name):
    src=f"before_{name}.jpg"
    out=f"src_before_{name}.jpg"
    subprocess.run(["sips","-Z","1024","-s","format","jpeg",src,"--out",out],
                   capture_output=True)
    return out

for name in (sys.argv[1:] or STYLES):
    asset, recipe = STYLES[name]
    prompt = f"{KEEP}\n\n{recipe}\n\n{TAIL}"
    b64 = base64.b64encode(open(source(name),"rb").read()).decode()
    print(f"→ {name} … ", end="", flush=True)
    try:
        t=post("/v1/gpt-image/edit", {"prompt":prompt,"resolution":"1k","provider":"wavespeed",
            "model":"google/nano-banana-2/edit","images":[b64],"imagesField":"images"})["data"]
        tid=t.get("taskId") or t.get("task_id")
        for _ in range(120):
            time.sleep(2)
            st=post("/v1/gpt-image/status", {"taskId":tid,"provider":"wavespeed"})["data"]
            s=(st.get("state") or "").lower()
            if s=="succeeded":
                urllib.request.urlretrieve(st["imageUrl"], f"style_{name}.jpg"); print("fertig"); break
            if s not in ("queued","running","processing"):
                print("FEHLER:", st.get("failMsg") or st); break
        else: print("Zeitueberschreitung")
    except Exception as e:
        print("FEHLER:", e)
