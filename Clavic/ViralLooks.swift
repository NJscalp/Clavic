//
//  ViralLooks.swift
//  Clavic
//
//  Die 5 viralsten KI-Foto-Looks für Frauen, nachgebaut für die Templates.
//
//  Auswahl ist NICHT geraten: Glam AI (getglam) liefert über
//  /api/filters/all_items seinen kompletten Filter-Katalog samt echter
//  Nutzungszahlen. Recherchiert am 30.07.2026 — 480 Filter geladen, auf
//  `output_media_type == image` und den Tag "female" gefiltert, nach
//  `community_metrics.uses` sortiert. Das sind die Top 5 (Memes und
//  Utilities wie Upscale ausgenommen):
//
//    1. Photo Set / Triptych  17.5K   2. Vintage Beach  15.3K
//    3. Afterglow             11.6K   4. Photo Sunset   11.2K
//    5. Tropic Glow           11.1K   (Nachrücker: Retro Noir 10.6K)
//
//  Flibbo lieferte keine belastbaren Zahlen — deren Website ist eine
//  generische AI-Assistenten-Seite ohne Filter-Katalog.
//
//  Jeder Prompt folgt derselben DNA wie der Agent: Identity-Lock zuerst,
//  dann eine Pose, die zur NEUEN Szene passt (nicht die aus dem Quellfoto
//  übernommen), dann Licht/Grade als konkretes Rezept, dann der Realismus-
//  Schutz. Keine Marken und kein Text — unser Bildmodell verwürfelt beides.
//

import Foundation

enum ViralLooks {

    struct Look: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let hashtag: String
        let icon: String
        let asset: String
        let prompt: String
    }

    static let all: [Look] = [
        Look(
            id: "photo-set",
            title: "Photo Set",
            subtitle: "One selfie → a 3-shot golden-hour set",
            hashtag: "#PhotoSet",
            icon: "square.grid.3x1.below.line.grid.1x2",
            asset: "preview_look_photo_set",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth or redraw her. Build one vertical three-panel photo set: three separate photographs stacked one above the other with a thin clean white gap between them, all three showing the SAME woman in the SAME room and the SAME outfit, but caught in three different moments with three different crops. Top panel: a close crop of her face, looking straight down the lens. Middle panel: head tilted, gaze off to the side, one bare shoulder and her collarbone in frame. Bottom panel: framed further back, seated and leaning against the wall, chin lifted. She wears a plain fitted tan ribbed tank top and two layered thin gold chain necklaces. Late-afternoon sun through a window is the only light — low and hard, raking across her from one side, throwing crisp window-frame shadow bars onto the plain wall behind her, deep warm shadows, highlights just short of clipping on her cheekbone and shoulder. Warm amber-tan colour around 3600K, rich contrast, deep blacks. Real skin texture with visible pores and fine detail, naturally glossy lips, no beauty filter, no plastic smoothing. Each panel shot handheld at arm's length on a phone, framing slightly off-centre, mild sensor noise in the shadows. Photorealistic — it must read as three real photos taken within the same few minutes. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "vintage-beach",
            title: "Vintage Beach",
            subtitle: "Faded 35mm film on the sand",
            hashtag: "#VintageBeach",
            icon: "beach.umbrella.fill",
            asset: "preview_look_vintage_beach",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth or redraw her. Place her seated on wet-packed sand at the edge of the beach, knees drawn up in front of her, one forearm resting across her knees, barefoot, body angled slightly away from the lens while she looks straight into it — a relaxed unposed sitting position built for the sand, not carried over from the reference photo. Her long dark wavy hair is damp and salt-textured with a few strands stuck to her cheek. She wears a plain cream ribbed tank top and loose light-wash vintage blue jeans with the cuffs turned up. Bright overcast midday sea light, soft and even with no hard shadows, cool daylight around 6200K. Behind her: breaking white surf, a dark rocky headland far off to one side, damp sand and scattered footprints in the foreground. Faded 35mm film look — muted desaturated colour, lifted blacks, gentle halation on the bright surf, visible film grain, slightly soft corners. Real skin texture with pores and freckles, wind-flushed cheeks, no beauty filter. Shot handheld on a phone from a low crouch a couple of metres away, framing slightly off-centre, horizon not perfectly level. Photorealistic, looks like a real scanned film photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "afterglow",
            title: "Afterglow",
            subtitle: "Black & white window light",
            hashtag: "#Afterglow",
            icon: "circle.lefthalf.filled",
            asset: "preview_look_afterglow",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth or redraw her. Place her standing close to a tall black-framed window in a bare white room, body turned in profile to the lens, chin lifted toward the light, eyes closed, one hand loose at her side, weight settled on one hip — a calm standing position built for this room, not carried over from the reference photo. Her hair falls loose and wavy past her shoulders with a few strands lit bright at the edges. She wears an oversized crisp white cotton button-down shirt, cuffs unbuttoned, hem long. A single hard low sun through the window is the only light source: it throws a crisp grid of window-frame shadow bars across the white wall, across the floor and across her shirt, with a bright wedge of light falling on her face and throat. Converted to high-contrast black and white — clean bright highlights, deep true blacks, full tonal range through the mid greys, fine film grain. Real skin texture with visible pores, no beauty filter, no plastic smoothing. Shot handheld on a phone from a couple of metres away at chest height, framing slightly off-centre, part of the window clipped by the frame edge. Photorealistic, looks like a real photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "photo-sunset",
            title: "Photo Sunset",
            subtitle: "Cotton-candy sky, palms, candid",
            hashtag: "#PhotoSunset",
            icon: "sun.horizon.fill",
            asset: "preview_look_photo_sunset",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth or redraw her. Place her standing at the edge of a coastal road at dusk, turned away from the lens and looking back over one bare shoulder into the camera, weight on her back foot, mid-step — a natural turning-back position built for standing on a roadside, not carried over from the reference photo. Her dark hair is pulled up into a messy high ponytail with loose strands falling around her face and neck. She wears a plain black ribbed tank top. Behind her: towering pink and lilac cotton-candy sunset clouds filling the sky, tall palm trees in silhouette down the roadside, a thin strip of dark ocean on the horizon, a parked car thrown out of focus at the kerb. The last warm light of the day comes from behind her, wrapping a soft rim around her shoulder and the loose strands of hair, her face lit by the soft pink glow bouncing off the sky, around 4400K. Saturated pastel sky against warm skin, gentle contrast. Real skin texture with visible pores and a natural sheen, no beauty filter, no plastic smoothing. Shot handheld on a phone at chest height by someone standing a couple of metres away, framing slightly off-centre, horizon not perfectly level, mild sensor noise. Photorealistic, reads as a real candid phone photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "tropic-glow",
            title: "Tropic Glow",
            subtitle: "Wet-look glow in the jungle",
            hashtag: "#TropicGlow",
            icon: "leaf.fill",
            asset: "preview_look_tropic_glow",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth or redraw her. Build a tight close-up: her head and bare shoulders fill the frame, one hand raised to rest against her cheek and jaw, head turned slightly so she looks just past the lens — a close relaxed position built for this shot, not carried over from the reference photo. Her dark hair is wet and slicked back, still dripping at the ends, with a large pink hibiscus flower tucked behind one ear. Low in the frame her other hand holds a cut slice of pink dragon fruit. Behind her: dense sunlit tropical foliage, big glossy green leaves, hard dappled sun coming through them and throwing bright spots and deep shadow across the background. Her skin is dewy and wet with strong specular highlights sitting on her cheekbones, nose bridge, collarbones and shoulders — add shine and wetness, never remove skin surface. Naturally glossy lips. Saturated tropical colour, warm around 5200K, high micro-contrast, real skin texture with visible pores, no beauty filter, no plastic smoothing. Shot handheld on a phone close up, framing slightly off-centre with her shoulder clipped by the frame edge, shallow real lens falloff on the leaves behind. Photorealistic, looks like a real photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
    ]

    static func look(id: String) -> Look? { all.first { $0.id == id } }
    static func prompt(id: String) -> String { look(id: id)?.prompt ?? "" }
}
