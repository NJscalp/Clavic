# TikTok photo-look previews

Updated 2026-09-06. User requested real outdoor photographs of women only, same-photo before/after pairs, automatic transitions, and removal of unsubstantiated trends.

## Included looks

This is a reviewed selection, not a live global ranking. Golden Hour and Blue Hour are historical TikTok classics; G7X and Digicam are supported by 2026 coverage. No fake view counts or “viral today” badges.

| ID | Evidence |
| --- | --- |
| g7xflash | [Tom’s Guide, 2026-02-23](https://www.tomsguide.com/cameras-photography/canon-powershot-g7-x-mark-iii-still-worth-it-in-2026): continuing TikTok popularity of the G7X camera/look family, not a measurement of this specific preset. |
| goldenhour | [Creative Bloq, updated 2022-09-08](https://www.creativebloq.com/news/viral-tiktok-photo-editing-hack): historical viral iPhone colour-edit tutorial by anaugazz. |
| redsunset | Requested by the app owner on 2026-09-07 from a reference they supplied (`images.jpg`). No published reach evidence collected for this one — it is an owner-selected look, not a measured trend. |
| y2kdigicam | [Digital Camera World, 2026-07-14](https://www.digitalcameraworld.com/cameras/compact-cameras/i-wrote-off-the-digicam-as-a-temporary-trend-but-three-years-later-crappy-cameras-have-only-become-more-popular): continuing retro compact-camera trend. Preview pair and recipe narrowed on 2026-09-07 to the night direct-flash variant the owner supplied. |
| redlight | Owner-selected, added 2026-09-07. The technique is documented rather than measured: TikTok's own [red LED light](https://www.tiktok.com/discover/red-led-light-trend) and [red light filter](https://www.tiktok.com/discover/red-light-filter-effect-tiktok) discovery pages collect the trend, [Snapchat ships a Red Light lens](https://www.snapchat.com/lens/3c3c24c0361e4a2eaa5b74d2a9860ec4), and clip-on [red flashlight filters for phones](https://www.amazon.com/Spotlight-Smartphones-Astronomy-Batteries-Charging/dp/B0D32KL894) are sold for it. No reach figures collected. |
| bluehour | [Know Your Meme, 2022-11-11](https://knowyourmeme.com/memes/blue-hour): historical TikTok Photoshop tutorial; original video linked in the research catalog. |

Two "before" frames deliberately break the plain-daylight rule the other looks follow: `y2kdigicam` and `redlight` are indoor/night scenes, so their before is the same moment without the flash respectively without the red source, not a daytime version. Turning either into daylight would be a scene rewrite, and the card would then promise a change of time of day that the grade recipe cannot make.

Night Flash (Instagram evidence), Cinematic (tutorial evidence without strong reach evidence), generic Sunset, Clean Girl and 35mm Mono are excluded from this TikTok selection. General Library/Studio tools are unaffected. Only reviewed IDs are accepted from Director recommendations. Unknown server templates cannot reappear in the ring or sheet. Existing `sunlitglow` IDs map to Golden Hour.

## Real photographs and licenses

| Preview | Photographer / original | Local source |
| --- | --- | --- |
| G7X Flash | [Patrick Porto / Pexels 4116647](https://www.pexels.com/photo/photo-of-woman-wearing-sunglasses-4116647/) | Existing `director_real_car` asset; real nighttime street flash photo. |
| Golden Hour and Blue Hour | [Jack Dong / Unsplash CNepV4eLfGY](https://unsplash.com/photos/a-woman-standing-on-a-beach-next-to-the-ocean-CNepV4eLfGY) | `docs/trend-photo-sources/jack-dong-beach.jpg`; published 2023-08-08, Sony ILCE-7M4 listed by source. |
| Red Light | **Provenance not established.** Supplied by the app owner as `~/Desktop/red.jpeg`, 736 × 920, no photographer, platform or licence known. | Owner-supplied file. |
| Y2K Digicam | **Replaced 2026-09-07. Provenance not established.** Supplied by the app owner as `~/Desktop/1234.jpeg`, 736 × 1059, no photographer, platform or licence known. The former Pexels source (rasul lotfi / [Pexels 14411942](https://www.pexels.com/photo/woman-portrait-at-sunset-14411942/), `docs/trend-photo-sources/sunset-woman.jpg`) is no longer used by this look. | Owner-supplied file. |

| Red Sunset | **Provenance not established.** Supplied by the app owner as `~/Desktop/images.jpg`, a 407 × 491 screenshot with a black frame — no photographer, platform or licence known. | `docs/trend-photo-sources/` entry still missing. |

**Open item before release:** the Red Sunset, Y2K Digicam and Red Light pairs each show a real, identifiable woman from a source whose photographer and licence are unknown. Three of six trend cards are affected. Confirm the rights, or replace the pairs with licensed photographs, before these looks ship.

Licenses checked: [Pexels](https://www.pexels.com/license/) and [Unsplash](https://unsplash.com/license). Photos are illustrative examples, not testimonials or endorsements. No TikTok creator photos were copied from social posts. Five pairs are exceptions to this and were **generatively edited** (Seedream v5.0 Pro, 2K, via the app's own backend): `g7xflash`, `goldenhour`, `redsunset`, `y2kdigicam` and `redlight`. In each the app owner supplied the "after" and asked for a matching "before"; the before was rendered from the after under the app's own identity lock and grade contract, so the person, pose, clothing and framing are the same in both frames and only light and colour differ. `redsunset`, `y2kdigicam` and `redlight` had their after additionally re-rendered from the low-resolution source to fix image quality; both were sent with `aspectRatio: "3:4"` and an explicit framing lock, because without it the model re-cropped and returned 2:3. The people in them are the people in the source photographs, not invented.

## Reproducible edits

Run `swift scripts/render_trend_previews.swift` from the repository root. It saves JPEG assets, each 768 × 1024, into `Clavic/Assets.xcassets/trend_*`. It no longer covers `g7xflash`, `goldenhour`, `redsunset`, `y2kdigicam` and `redlight` — those pairs are generative and are not reproduced by this script; re-running it would overwrite them with the old Core Image versions.

For the one pair the script still owns (`bluehour`): each pair uses the same crop and the same source photograph. Before is the downloaded source with only matched crop/resize; it is not artificially degraded. After uses Core Image colour matrices, exposure, contrast, saturation and highlight control. Faces, bodies, poses, background objects and geometry are not generated, warped or retouched.

For the five generative pairs the same rule holds by contract rather than by construction: the render ran under the app's identity lock plus its `grade` contract, which forbids changing composition, background, pose, clothing or the person. Both frames of each pair descend from one image, so they align exactly.

The images illustrate the colour direction. They are not claimed to be paid production AI-render outputs or exact replicas of a third-party TikTok filter. Selecting a trend still follows the existing Director render flow; its reviewed prompt preserves the subject and scene. The app itself remains an AI photo editor.

`TrendPhotoPreview` uses a synchronized eight-second loop: two seconds original, two seconds wipe, two seconds edit, two seconds wipe back. Before is always left, After right. Paused/offscreen/background/reduced-motion previews show a static split. Opening the trend sheet pauses the underlying ring.

## Validation

`TikTokTrendsTests` checks filtering of unreviewed entries, legacy ID mapping, safe recipe/preview replacement, exclusion of restaging recommendations, distinct equal-sized assets, and complete-photo hold/transition states. Simulator screenshots and recording are saved under `output/tiktok-real-photo-previews` in the workspace parent.
