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
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Build one vertical three-panel photo set: three separate photographs stacked one above the other with a thin clean white gap between them, all three showing the SAME woman in the SAME room and the SAME outfit, but caught in three different moments with three different crops. Top panel: a close crop of her face, looking straight down the lens. Middle panel: head tilted, gaze off to the side, one bare shoulder and her collarbone in frame. Bottom panel: framed further back, seated and leaning against the wall, chin lifted. She wears a plain fitted tan ribbed tank top and two layered thin gold chain necklaces. Late-afternoon sun through a window is the only light — low and hard, raking across her from one side, throwing crisp window-frame shadow bars onto the plain wall behind her, deep warm shadows, highlights just short of clipping on her cheekbone and shoulder. Warm amber-tan colour around 3600K, rich contrast, deep blacks. Real skin texture with visible pores and fine detail, naturally glossy lips, no beauty filter, no plastic smoothing. Each panel shot handheld at arm's length on a phone, framing slightly off-centre, mild sensor noise in the shadows. Photorealistic — it must read as three real photos taken within the same few minutes. Vertical 9:16. No text, no logos, no watermark.
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
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her seated on wet-packed sand at the edge of the beach, knees drawn up in front of her, one forearm resting across her knees, barefoot, body angled slightly away from the lens while she looks straight into it — a relaxed unposed sitting position built for the sand, not carried over from the reference photo. Her long dark wavy hair is damp and salt-textured with a few strands stuck to her cheek. She wears a plain cream ribbed tank top and loose light-wash vintage blue jeans with the cuffs turned up. Bright overcast midday sea light, soft and even with no hard shadows, cool daylight around 6200K. Behind her: breaking white surf, a dark rocky headland far off to one side, damp sand and scattered footprints in the foreground. Faded 35mm film look — muted desaturated colour, lifted blacks, gentle halation on the bright surf, visible film grain, slightly soft corners. Real skin texture with pores and freckles, wind-flushed cheeks, no beauty filter. Shot handheld on a phone from a low crouch a couple of metres away, framing slightly off-centre, horizon not perfectly level. Photorealistic, looks like a real scanned film photo. Vertical 9:16. No text, no logos, no watermark.
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
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her standing close to a tall black-framed window in a bare white room, body turned in profile to the lens, chin lifted toward the light, eyes closed, one hand loose at her side, weight settled on one hip — a calm standing position built for this room, not carried over from the reference photo. Her hair falls loose and wavy past her shoulders with a few strands lit bright at the edges. She wears an oversized crisp white cotton button-down shirt, cuffs unbuttoned, hem long. A single hard low sun through the window is the only light source: it throws a crisp grid of window-frame shadow bars across the white wall, across the floor and across her shirt, with a bright wedge of light falling on her face and throat. Converted to high-contrast black and white — clean bright highlights, deep true blacks, full tonal range through the mid greys, fine film grain. Real skin texture with visible pores, no beauty filter, no plastic smoothing. Shot handheld on a phone from a couple of metres away at chest height, framing slightly off-centre, part of the window clipped by the frame edge. Photorealistic, looks like a real photo. Vertical 9:16. No text, no logos, no watermark.
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
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her standing at the edge of a coastal road at dusk, turned away from the lens and looking back over one bare shoulder into the camera, weight on her back foot, mid-step — a natural turning-back position built for standing on a roadside, not carried over from the reference photo. Her dark hair is pulled up into a messy high ponytail with loose strands falling around her face and neck. She wears a plain black ribbed tank top. Behind her: towering pink and lilac cotton-candy sunset clouds filling the sky, tall palm trees in silhouette down the roadside, a thin strip of dark ocean on the horizon, a parked car thrown out of focus at the kerb. The last warm light of the day comes from behind her, wrapping a soft rim around her shoulder and the loose strands of hair, her face lit by the soft pink glow bouncing off the sky, around 4400K. Saturated pastel sky against warm skin, gentle contrast. Real skin texture with visible pores and a natural sheen, no beauty filter, no plastic smoothing. Shot handheld on a phone at chest height by someone standing a couple of metres away, framing slightly off-centre, horizon not perfectly level, mild sensor noise. Photorealistic, reads as a real candid phone photo. Vertical 9:16. No text, no logos, no watermark.
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
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Build a tight close-up: her head and bare shoulders fill the frame, one hand raised to rest against her cheek and jaw, head turned slightly so she looks just past the lens — a close relaxed position built for this shot, not carried over from the reference photo. Her dark hair is wet and slicked back, still dripping at the ends, with a large pink hibiscus flower tucked behind one ear. Low in the frame her other hand holds a cut slice of pink dragon fruit. Behind her: dense sunlit tropical foliage, big glossy green leaves, hard dappled sun coming through them and throwing bright spots and deep shadow across the background. Her skin is dewy and wet with strong specular highlights sitting on her cheekbones, nose bridge, collarbones and shoulders — add shine and wetness, never remove skin surface. Naturally glossy lips. Saturated tropical colour, warm around 5200K, high micro-contrast, real skin texture with visible pores, no beauty filter, no plastic smoothing. Shot handheld on a phone close up, framing slightly off-centre with her shoulder clipped by the frame edge, shallow real lens falloff on the leaves behind. Photorealistic, looks like a real photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "cafe-window",
            title: "Café Window",
            subtitle: "Morning light through the glass",
            hashtag: "#CafeWindow",
            icon: "cup.and.saucer.fill",
            asset: "preview_look_cafe_window",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her seated at a small marble table right against a tall café window, elbows on the table, both hands wrapped around a wide cappuccino cup held just below her chin, shoulders drawn in and head tilted a little toward the glass while she looks out of it — a settled, unposed sitting position built for this table, not carried over from the reference photo. Her hair is down with a loose middle part, a few strands falling in front of one shoulder. She wears a soft oatmeal knitted jumper with the sleeves pushed up. Morning sun comes through the window from her side, low and slightly hazy, lighting one half of her face brightly and leaving the other in soft warm shadow, with a bright bloom where the light hits the glass, around 4600K. Behind her: the blurred street outside, a fogged patch on the glass, a small vase on the table. Warm creamy colour grade, gentle contrast, soft lifted blacks. Real skin texture with visible pores and fine hairs catching the light, no beauty filter, no plastic smoothing. Shot handheld on a phone from across the table at eye height, framing slightly off-centre, the cup clipped by the frame edge, mild grain. Photorealistic, reads as a real candid phone photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "car-seat-night",
            title: "Car Seat at Night",
            subtitle: "Passenger seat, streetlights sliding past",
            hashtag: "#CarSeatNight",
            icon: "car.fill",
            asset: "preview_look_car_seat_night",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her sitting in the passenger seat of a parked car at night, seatbelt across her chest, head resting back against the headrest and turned toward the lens, one hand loose in her lap — a tired, relaxed sitting position built for this seat, not carried over from the reference photo. Her hair falls loose over the seatbelt strap. She wears a plain black long-sleeve top. The only light comes from outside: cool white streetlight through the side window raking across one cheek and her shoulder, plus a soft amber glow from a shop sign further off, and the faint green of the dashboard low on her chin. Deep dark interior, strong pools of light against near-black shadow, mixed colour temperature between 3000K amber and 6000K white. Behind her: the blurred night street through the window, out-of-focus headlights and sign lights. Moody low-key grade, rich blacks, visible high-ISO noise in the shadows. Real skin texture with visible pores, no beauty filter, no plastic smoothing. Shot handheld on a phone from the driver's seat, framing slightly off-centre, part of the seatbelt and door frame in shot. Photorealistic, reads as a real late-night phone photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "elevator-mirror",
            title: "Elevator Mirror",
            subtitle: "Mirror selfie in a lift",
            hashtag: "#ElevatorMirror",
            icon: "rectangle.portrait.on.rectangle.portrait",
            asset: "preview_look_elevator_mirror",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Build a mirror selfie taken inside a lift: she stands facing the mirrored back wall, weight on one hip, one arm raised holding the phone up near her shoulder with the phone visible in the reflection, the other hand hanging loose, chin slightly down and eyes on her own reflection — a standing mirror-selfie position built for this lift, not carried over from the reference photo. Her hair is down and slightly tousled. She wears a fitted black slip dress and simple silver hoop earrings. Overhead lift lighting only: a hard, slightly cool downlight around 5000K that puts small shadows under her brow and chin and throws a bright pool on the floor, with warm reflections off the brushed metal walls. Behind and around her: brushed steel panels, the lift button strip, the seam of the doors, everything lightly smudged and real. Slightly desaturated grade with a cool cast, moderate contrast, mild lens flare where the light hits the mirror. Real skin texture with visible pores, no beauty filter, no plastic smoothing. Framing slightly off-centre and tilted the way a real mirror selfie is, mild grain and a soft smudge on the mirror. Photorealistic, reads as a real phone mirror selfie. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "flower-market",
            title: "Flower Market",
            subtitle: "Buckets of blooms on a bright morning",
            hashtag: "#FlowerMarket",
            icon: "camera.macro",
            asset: "preview_look_flower_market",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her standing at a flower market stall, half turned away from the lens and looking back over her shoulder, one hand reaching into a bucket of blooms and one arm cradling a loose wrapped bunch of ranunculus and eucalyptus against her chest — a natural mid-browsing position built for this stall, not carried over from the reference photo. Her hair is tied back low with loose strands around her face. She wears a white cotton poplin blouse with the sleeves rolled and light blue jeans. Bright overcast morning light under the stall awning, soft and wrapping with no hard shadows, cool daylight around 6000K with a warm bounce off the market's wooden crates. Around her: zinc buckets packed with pink, cream and deep red flowers, green stems and paper wrapping, the blurred aisle of the market behind. Fresh saturated colour, clean whites, gentle contrast. Real skin texture with visible pores and a few freckles, no beauty filter, no plastic smoothing. Shot handheld on a phone from a couple of steps away at chest height, framing slightly off-centre with flowers clipped by the frame edge, mild grain. Photorealistic, reads as a real candid phone photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "rooftop-dusk",
            title: "Rooftop at Dusk",
            subtitle: "City skyline, last blue light",
            hashtag: "#RooftopDusk",
            icon: "building.2.fill",
            asset: "preview_look_rooftop_dusk",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her standing on a rooftop terrace with her back against the parapet wall, both forearms resting along the top of it behind her, one ankle crossed over the other, chin lifted and looking straight into the lens — a leaning standing position built for this parapet, not carried over from the reference photo. Her hair is loose and lifted slightly by the wind. She wears a cropped black knitted cardigan and wide grey tailored trousers. It is the blue hour just after sunset: a deep blue sky with a thin band of dying orange low on the horizon, the city skyline behind her lit window by window, warm points of light going out of focus. Her key light is a warm practical lamp on the terrace off to one side around 3200K, filled by the cool blue of the sky around 8000K, so one side of her face is warm and the other cool. Rich contrast between warm skin and cool sky, deep blacks, glowing highlights. Real skin texture with visible pores, no beauty filter, no plastic smoothing. Shot handheld on a phone from a few steps away at chest height, framing slightly off-centre, horizon not perfectly level, visible high-ISO grain. Photorealistic, reads as a real phone photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "morning-bed",
            title: "Morning in Bed",
            subtitle: "First light, rumpled sheets",
            hashtag: "#MorningInBed",
            icon: "bed.double.fill",
            asset: "preview_look_morning_bed",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her lying on her side across a rumpled bed, propped on one forearm with the duvet pulled loosely up under her arm, the other hand near her face, head tilted down into the pillow while she looks up into the lens — a soft just-woken position built for this bed, not carried over from the reference photo. Her hair is unbrushed and falls across the pillow and one cheek. She wears a plain white cotton camisole. Early morning sun comes through a gap in the curtains as a single soft shaft, falling across the sheets, her arm and one side of her face, leaving the rest of the room in gentle shadow, warm and low around 3400K with visible dust in the beam. Around her: creased white bedding, a dented pillow, a book face-down on the sheet. Warm soft grade, low contrast, lifted milky blacks, gentle bloom where the sun hits. Real skin texture with visible pores, pillow creases on her cheek, no beauty filter, no plastic smoothing. Shot handheld on a phone from just above her at close range, framing slightly off-centre with the duvet clipped by the frame edge, fine grain. Photorealistic, reads as a real morning phone photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
        Look(
            id: "rain-streetlight",
            title: "Rain & Streetlight",
            subtitle: "Wet pavement, amber glow",
            hashtag: "#RainStreetlight",
            icon: "cloud.rain.fill",
            asset: "preview_look_rain_streetlight",
            prompt: """
Keep the exact same woman from the reference photo — identical face, facial features, bone structure, skin tone, eye colour, hairline and natural expression. Do not beautify, slim, smooth, retouch or redraw her. Place her standing on a wet pavement at night under a streetlight, one hand holding a clear umbrella up and tilted back off her face, the other in her coat pocket, weight on one hip, head turned up and slightly toward the light — a standing position built for this pavement, not carried over from the reference photo. Her hair is damp at the ends with a few strands stuck to her temple. She wears a long dark trench coat over a plain top. The streetlight directly above and behind her is the key: a hard amber light around 2800K rimming her hair, her shoulders and the wet umbrella, with cool blue ambient from the night sky filling the shadows, and warm shop light reflecting up off the soaked pavement. Around her: falling rain caught as bright streaks in the beam, puddles mirroring the amber lamps, blurred traffic lights far down the street. High contrast, deep blacks, saturated amber against blue, strong specular highlights on every wet surface. Real skin texture with visible pores and real water droplets on her skin, no beauty filter, no plastic smoothing. Shot handheld on a phone from a couple of metres away at chest height, framing slightly off-centre, visible high-ISO grain and a little motion blur in the rain. Photorealistic, reads as a real night phone photo. Vertical 9:16. No text, no logos, no watermark.
"""
        ),
    ]

    static func look(id: String) -> Look? { all.first { $0.id == id } }
    static func prompt(id: String) -> String { look(id: id)?.prompt ?? "" }
}
