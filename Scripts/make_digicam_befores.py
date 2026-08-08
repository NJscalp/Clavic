import json, time, urllib.request, sys
BASE="https://limitless-web-beryl.vercel.app"

# Das "Vorher" muss MITTELMAESSIG sein. Genau daran scheitern unsere bisherigen
# Kacheln: ein Studio-Katalogfoto ist schon perfekt, da kann kein Grading mehr
# etwas verbessern. WayShots Vorher-Bilder sind flaue Handyfotos.
FLAT = ("Shot on an ordinary phone camera with no editing at all: flat even exposure, dull washed "
"colours, low contrast, slightly greyish whites, mild digital noise, ordinary snapshot framing that "
"is a little off-centre and slightly crooked. It looks like an unedited photo straight from a "
"camera roll — not a professional or styled photograph. Real skin with visible pores, freckles and "
"texture, no makeup retouching, natural imperfect hair. Photorealistic. Vertical 9:16. "
"No text, no logos, no watermark.")

SCENES = {
 "digix": "A young woman in her twenties walking along a sunny old-town street at midday, white "
          "stone buildings behind her, she glances back over her shoulder at the camera, casual "
          "summer dress.",
 "digicam": "A young woman in her twenties sitting at a small table in a dimly lit restaurant at "
            "night, warm lamps and candles around her, she leans on one elbow looking at the camera.",
 "digis": "A young woman in her twenties standing on a beach just after sunset, dark blue sky, the "
          "sea behind her, she stands relaxed with one hand in her hair.",
 "digilite": "A young woman in her twenties standing near a big window inside a bright cafe on an "
             "overcast day, plants and pale walls around her, hands in her pockets.",
 "cleangirl": "A young woman in her twenties standing on a city pavement on an overcast day, beige "
              "coat, a plain building facade behind her, one hand holding her bag strap.",
 "bw": "Two young women in their twenties laughing together at an outdoor summer festival, a crowd "
       "blurred behind them, one has an arm around the other.",
}

def post(path, body, timeout=90):
    r=urllib.request.Request(BASE+path, data=json.dumps(body).encode(),
        headers={"Content-Type":"application/json"}, method="POST")
    with urllib.request.urlopen(r, timeout=timeout) as resp: return json.loads(resp.read())

for name in (sys.argv[1:] or SCENES):
    prompt = f"{SCENES[name]} {FLAT}"
    print(f"→ before_{name} … ", end="", flush=True)
    try:
        t=post("/v1/gpt-image/edit", {"prompt":prompt,"resolution":"1k","provider":"wavespeed",
            "model":"bytedance/seedream-v5.0-pro","aspectRatio":"9:16"})["data"]
        tid=t.get("taskId") or t.get("task_id")
        for _ in range(120):
            time.sleep(2)
            st=post("/v1/gpt-image/status", {"taskId":tid,"provider":"wavespeed"})["data"]
            s=(st.get("state") or "").lower()
            if s=="succeeded":
                urllib.request.urlretrieve(st["imageUrl"], f"before_{name}.jpg"); print("fertig"); break
            if s not in ("queued","running","processing"): print("FEHLER:", st.get("failMsg") or st); break
        else: print("Zeitueberschreitung")
    except Exception as e: print("FEHLER:", e)
