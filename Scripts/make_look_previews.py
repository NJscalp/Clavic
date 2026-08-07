#!/usr/bin/env python3
"""Erzeugt die Vorschau-Bilder der ViralLooks-Kacheln.

Aus dem Projektstammverzeichnis aufrufen:  python3 Scripts/make_look_previews.py [look-id ...]

Nimmt genau den Weg, den die App auch nimmt: das Clavic-Backend auf Vercel,
Seedream v5.0 Pro (edit) ueber WaveSpeed. Der Prompt kommt woertlich aus
ViralLooks.swift — die Kachel soll zeigen, was die Vorlage wirklich erzeugt,
nicht ein daneben gemaltes Stimmungsbild.
"""

import base64
import json
import re
import sys
import time
import urllib.request

BASE = "https://limitless-web-beryl.vercel.app"
SWIFT = "/Users/normannjungbauer/Desktop/Clavic/Clavic/Clavic/ViralLooks.swift"
REF = "Clavic/Assets.xcassets/face_model_1.imageset/face_model_1.jpg"

NEW_LOOKS = [
    "cafe-window", "car-seat-night", "elevator-mirror", "flower-market",
    "rooftop-dusk", "morning-bed", "rain-streetlight",
]


def looks():
    """id -> (asset, prompt) aus dem Swift-Quelltext."""
    text = open(SWIFT).read()
    found = {}
    for block in text.split("Look(")[1:]:
        ident = re.search(r'id:\s*"([^"]+)"', block)
        asset = re.search(r'asset:\s*"([^"]+)"', block)
        prompt = re.search(r'prompt:\s*"""\n(.*?)\n"""', block, re.S)
        if ident and asset and prompt:
            found[ident.group(1)] = (asset.group(1), prompt.group(1).strip())
    return found


def post(path, body, timeout=90):
    request = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read())


def generate(prompt, reference_b64):
    body = {
        "prompt": prompt,
        "resolution": "1k",
        "provider": "wavespeed",
        "model": "bytedance/seedream-v5.0-pro/edit",
        "images": [reference_b64],
        "imagesField": "images",
        "aspectRatio": "9:16",
    }
    task = post("/v1/gpt-image/edit", body)["data"]
    task_id = task.get("taskId") or task.get("task_id")
    if not task_id:
        raise RuntimeError(f"keine taskId: {task}")

    for _ in range(120):
        time.sleep(2)
        state = post("/v1/gpt-image/status", {"taskId": task_id, "provider": "wavespeed"})["data"]
        status = (state.get("state") or "").lower()
        if status == "succeeded":
            return state["imageUrl"]
        if status not in ("queued", "running", "processing"):
            raise RuntimeError(f"fehlgeschlagen: {state.get('failMsg') or state}")
    raise RuntimeError("Zeitueberschreitung")


def main():
    wanted = sys.argv[1:] or NEW_LOOKS
    catalog = looks()
    reference = base64.b64encode(open(REF, "rb").read()).decode()

    for ident in wanted:
        asset, prompt = catalog[ident]
        print(f"→ {ident} … ", end="", flush=True)
        try:
            url = generate(prompt, reference)
            with urllib.request.urlopen(url, timeout=120) as response:
                target = f"Clavic/Assets.xcassets/{asset}.imageset/{asset}.jpg"
            open(target, "wb").write(response.read())
            print(f"fertig ({target})")
        except Exception as error:                      # noqa: BLE001
            print(f"FEHLER: {error}")


if __name__ == "__main__":
    main()
