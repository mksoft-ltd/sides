# Sides: The News, Every Angle — Brand

Source of truth for every visual and written asset of Sides (store art, icon, website page).
The in-app palette lives in `lib/core/theme/app_theme.dart`; this file must stay consistent with it.
Publisher: Froggy Eye Ltd. Copyright line: `© 2026 Froggy Eye Ltd`.

## Positioning

A once-a-day digest that shows how outlets across the political spectrum, and from Western and Eastern
countries, cover the same top stories. Every analytical point cites the headline or snippet it rests on.
Calm, factual, a reading tool rather than a feed. Studio line: *Useful apps. No dark patterns.*
(Sides carries a banner ad with a one-time ad-free purchase, so never write "no ads" for this app.)

## Palette

Two families. The **perspective colours** are content: they always mean the same side and always
appear with a text label. The **plate colours** are the brand surface for store art and the icon.

### Perspective colours (from `PerspectiveColors`)

| Meaning | Light theme | Dark theme | Note |
|---|---|---|---|
| Left-leaning | `#7B4FB8` violet | `#B79CEB` | |
| Centre | `#5F6B73` slate | `#A7B3BB` | |
| Right-leaning | `#B0601A` orange | `#F0A35E` | |
| West | `#2E7D7A` teal | `#6CC5C0` | |
| East | `#8E6C00` gold | `#E0BE55` | |
| Empty track | `#D5D9DC` | `#3A3F44` | |

Never red or blue for a side: the UK and US use them with opposite meanings, so either mapping reads as
partisan to half the audience. Never use a perspective colour decoratively, e.g. for a button or headline.

### Brand surface (store art, icon)

| Token | Hex | Use |
|---|---|---|
| Plate top | `#1D313A` | gradient start (icon, feature graphic, dark screenshot plate) |
| Plate bottom | `#0F1C22` | gradient end |
| Plate flat | `#15252C` | Android adaptive-icon background |
| Ink on plate | `#EEF2F4` | headlines on the dark plate |
| Muted on plate | `#A7B3BB` | sublines on the dark plate |
| Paper top / bottom | `#F4F8FA` / `#DCE6EA` | light plate behind dark-theme captures |
| Ink on paper | `#13232A` | headlines on the light plate |
| App seed | `#34505C` | Material 3 seed for both in-app themes (deep slate-teal) |

Icon sheets: front page `#C3CDD3`, left sheet `#8F63D2`, right sheet `#E8914A`, which are the lean colours tuned to sit on the dark plate.

## Typography

- **In app:** the platform system font (SF Pro on iOS, Roboto on Android) via Material 3's default
  text theme. No bundled fonts; Dynamic Type / font scale up to 200% is honoured.
- **Store art:** SF Pro Display (rendered from `-apple-system` in headless Chrome). Headline weight 700,
  tracking −2%; sublines 400 at ~0.78 opacity. Sentence case, no full stop on headlines.
- **Wordmark:** "Sides" in SF Pro Display Semibold, sentence case, no lockup tricks.

## Iconography and the app icon

The mark is **a newspaper front page with two more sheets fanned out behind it**. The front page is pale slate,
with a thick headline bar, a photo block and three columns of text bars, so a stranger sees "newspaper" and
knows it is a news app even at 48 px. Behind it, a violet sheet fans out to the left and an orange sheet to
the right. These are the lean colours in their in-app positions, so the icon says "the same news, from several
sides". The text bars are abstract: no letters, no masthead lettering, no headline anyone could read.

- No outlet logos, flags, globes, real mastheads or real-world brands.
- Generated with OpenArt (record below), then finished in code by `icon/build_icon.py`. The script keys the
  mark off the model's background, snaps every pixel to the exact brand hex, clips the corner fragments the
  model left above and below the front page, and places the mark at 78% of the master's width on the plate
  gradient. The dark text bars are holes in the page, so the plate shows through as the ink.
- Proofs at 180/120/48 px and inside the round launcher mask (`icon/preview_*.png`). The adaptive foreground
  keeps its farthest corner at 30 dp from the centre, inside the 33 dp safe circle. The themed (monochrome)
  icon shows the front page solid and the two back sheets at 62% opacity.
- `icon/icon_mark.png` is the tight transparent mark used by the feature graphic.
- In-app icons: Material Symbols outlined, default weight, so they match the M3 components already in use.
- The in-app app-bar mark (`SidesMark`) paints this newspaper mark (front page between the violet and orange
  sheets), repainted in b23cc74; it no longer draws the earlier cube.

### Generated artwork

Credits are OpenArt credits. The balance was 22,880 before this pass and 22,680 after, so the pass used 200.
Raw outputs and prompt files are in `icon/openart/`.

| Asset | Model | Prompt | Creation id | Date | Credits | File | Verdict |
|---|---|---|---|---|---|---|---|
| Icon, fanned pages | nano-banana-pro, text-to-image, 1:1 | prompt V1 | `SmPCb1HxhulYDGRW1dHo` | 2026-10-15 | 40 | `openart/v1_fanned.png` | Best news read; side pages messy outlines. Refined. |
| Icon, split page | nano-banana-pro, text-to-image, 1:1 | prompt V2 | `y4fHnCAGLyQ3uT3ac6FA` | 2026-10-15 | 40 | `openart/v2_split.png` | Rejected: reads as a barcode or radiator, not a newspaper. |
| Icon, folded paper | nano-banana-pro, text-to-image, 1:1 | prompt V3 | `UGPqDkVlh6q7QqNc610u` | 2026-10-15 | 40 | `openart/v3_folded.png` | Rejected: fold reads as a folder tab; the sides idea is weak. |
| Icon, refinement 1 | nano-banana-pro, image-to-image from V1 | prompt R1 | `emkR0nfdiKbVKa2NrGkW` | 2026-10-15 | 40 | `openart/r1_fanned.png` | Front page clean; back sheets still outlines. |
| **Icon, chosen** | nano-banana-pro, image-to-image from R1 | prompt R2 | `ZLzSgWDROF32MFaeIUlm` | 2026-10-15 | 40 | `openart/r2_fanned.png` | **Chosen.** Corner fragments clipped in code. |
| Feature graphic | none | n/a | n/a | 2026-10-15 | 0 | `feature_graphic.png` | Re-rendered in code with `icon/icon_mark.png`. |

Full prompts:

- **V1:** A newspaper front page icon: three newspaper front pages fanned out like a hand of cards from a shared bottom pivot, each page tilted at a different angle. The left page is violet #8F63D2, the middle page is pale slate #C3CDD3 and sits in front, the right page is orange #E8914A. Each page clearly reads as a newspaper front page: a thick headline bar across the top, a rectangular photo block, and several columns of short horizontal text-line bars, all drawn as solid shapes in dark slate #15252C. Flat vector app icon artwork, single centred mark with generous empty margins (mark fills about 60 percent of the frame), on a perfectly flat solid background of exact colour #15252C (dark slate), no gradient, no texture, no vignette. Abstract blank text bars only, no readable letters, no text, no words, no numbers, no masthead lettering. No badges, ticks, check marks, seals, stars, ribbons, laurels, logos or trademarks. No device, no hands, no shadows, no photo-realism, no glossy 3D, no bevels. Crisp geometric shapes, minimal, premium, readable at 48 pixels.
- **V2:** A newspaper front page icon: a single upright newspaper front page, cut vertically into three equal strips that are pulled slightly apart by thin even gaps, so it reads as one page seen from three sides. Left strip violet #8F63D2, middle strip pale slate #C3CDD3, right strip orange #E8914A. The page clearly reads as a newspaper: a thick headline bar spanning the top, a rectangular photo block, and columns of short horizontal text-line bars, all drawn as solid shapes in dark slate #15252C, continuing across the three strips. Slightly rounded outer corners. Flat vector app icon artwork, single centred mark with generous empty margins (mark fills about 60 percent of the frame), on a perfectly flat solid background of exact colour #15252C (dark slate), no gradient, no texture, no vignette. Abstract blank text bars only, no readable letters, no text, no words, no numbers, no masthead lettering. No badges, ticks, check marks, seals, stars, ribbons, laurels, logos or trademarks. No device, no hands, no shadows, no photo-realism, no glossy 3D, no bevels. Crisp geometric shapes, minimal, premium, readable at 48 pixels.
- **V3:** A newspaper icon: a folded broadsheet newspaper seen from the front, slightly angled, with a visible fold at the top edge giving it a recognisable newspaper silhouette. The page is pale slate #C3CDD3 with a thick dark headline bar across the top, and below it three text columns; the left column block is tinted violet #8F63D2, the middle column stays pale slate, the right column block is tinted orange #E8914A, each column filled with short horizontal text-line bars in dark slate #15252C. Flat vector app icon artwork, single centred mark with generous empty margins (mark fills about 60 percent of the frame), on a perfectly flat solid background of exact colour #15252C (dark slate), no gradient, no texture, no vignette. Abstract blank text bars only, no readable letters, no text, no words, no numbers, no masthead lettering. No badges, ticks, check marks, seals, stars, ribbons, laurels, logos or trademarks. No device, no hands, no shadows, no photo-realism, no glossy 3D, no bevels. Crisp geometric shapes, minimal, premium, readable at 48 pixels.
- **R1:** Redraw this icon more cleanly and boldly. Keep the same idea: three newspaper front pages fanned out from a shared bottom pivot, the pale slate #C3CDD3 page in front in the middle, a violet #8F63D2 page tilted behind to the left, an orange #E8914A page tilted behind to the right. Make the two back pages SOLID filled pages exactly like the front page (not outlines), each showing only its top-left headline bar and a few text-line bars in dark slate #15252C where it peeks out. Fan them less widely (about 15 degrees each side) so the whole mark is compact and roughly square, and make the mark larger, filling about 70 percent of the frame, centred, with even margins. Front page: one thick headline bar across the top, a rectangular photo block at top left with a few short text lines beside it, and three columns of short text-line bars below, all solid dark slate #15252C. Perfectly flat solid background exact colour #15252C, no gradient, no texture. Flat vector, crisp geometric shapes, symmetric, no shadows, no glossy 3D. Abstract blank text bars only, no readable letters, no text, no numbers. No badges, ticks, seals, stars, ribbons, logos.
- **R2:** Clean up this icon. Keep the front pale slate #C3CDD3 newspaper page exactly as it is (headline bar, photo block, text lines, three columns, all dark slate #15252C). Fix the two pages behind it: each must be ONE plain, completely solid filled rotated rectangle the same size as the front page, with NO inner detail, NO outlines, NO dark interior and NO text bars. The violet #8F63D2 sheet is rotated about 12 degrees counter-clockwise and peeks out evenly on the left side; the orange #E8914A sheet is rotated about 12 degrees clockwise and peeks out evenly on the right side; both rotate around the same point at the bottom centre of the front page, mirror-symmetric. Remove all stray triangles and fragments; nothing peeks out above or below except the clean corners of the two sheets. Thin even gap of background colour #15252C around the front page so the three sheets stay distinct. Centred, mark fills about 70 percent of the frame. Perfectly flat solid background exact colour #15252C. Flat vector, crisp, no shadows, no gradients, no 3D. No readable letters, no text, no numbers, no badges, ticks, seals, stars, ribbons, logos.

### Store-art rule (house-facts §29, Google Play Metadata policy)

**No tick, badge, seal, rosette, laurel, ribbon, medal or star in any store art**: app icon, adaptive
icon, Play hi-res icon, feature graphic, or screenshot framing. Play reads them as claims about awards,
ranking or endorsement and rejects the listing (Passport Photo Studio, 11 Aug 2026). Glyphs inside genuine
app UI captures are fine. Do not add a "verified" or "trusted" mark to the icon, ever.

## Tone of voice

- **Neutral and descriptive.** Say what coverage contains: "Only left-leaning outlets covered this",
  "What each side leaves out". Never judge an outlet, its accuracy or its motives.
- Never write "fake news", "bias", "biased", "unbiased", "propaganda", "spin", "the truth" or "misinformation"
  in store copy or UI. "Political lean" and "media-bias ratings" (as the name of the external rating source) are
  the only sanctioned uses of the topic.
- Never claim completeness, ranking or authority: no "all the news", "every outlet", "#1", "best",
  "most trusted", "award-winning", "editor's choice".
- Adult, plain British English (`centre`, `emphasise`). No kid vocabulary, no exclamation marks, no emoji.
- Describe the method honestly: headlines and short summaries, once a day, every point linked to its source.
- No currency figures and no country-specific legal claims in store art.

## Store assets

| Asset | Platform | Size | File | Source |
|---|---|---|---|---|
| App icon master | both | 1024 × 1024, opaque RGB | `icon/icon_master.png` | `icon/build_icon.py` |
| Play hi-res icon | Google Play | 512 × 512, opaque RGB | `icon_512.png` | `icon/build_icon.py` |
| Feature graphic | Google Play | 1024 × 500, opaque RGB | `feature_graphic.png` | `feature_graphic/feature_graphic.html` + `render.sh` |
| iPhone screenshots | App Store | 1320 × 2868 (6.9") and 1284 × 2778 (6.5") | `screenshots/out/ios_69/`, `ios_65/` | `screenshots/render.sh` |
| iPad screenshots | App Store | 2752 × 2064 landscape (13") | `screenshots/out/ipad_13/` | same |
| Phone screenshots | Google Play | 1080 × 1920 | `screenshots/out/play_phone/` | same, Android captures |
| 10" tablet screenshots | Google Play | 2560 × 1600 | `screenshots/out/play_tablet/` | same, Android captures |

### Feature graphic

Dark plate gradient. Left: the newspaper mark (`icon/icon_mark.png`, 96 px tall) beside the "Sides" wordmark (70 px Semibold) and the line
"The news, every angle." (25 px, muted). Right: an abstract coverage card in the app's own visual language,
with a Political lean bar (Left / Centre / Right) and a West / East bar. It shows no counts and no headline,
because store art never shows invented news data. Everything sits inside the central 824 × 300 px, since Play
crops the edges on some surfaces (see `feature_graphic/proof_crop.png`).

### Screenshot framing

- No device frame. The raw capture sits centred with rounded corners (8.5% of its width on phones,
  2.2% on tablets) and a soft shadow, and bleeds off the bottom edge.
- Plate contrasts with the capture: light-theme captures sit on the **dark plate**, dark-theme captures sit
  on the **light paper plate**. This alternation gives the gallery rhythm.
- Copy block at the top, centred: headline 104 px and subline 50 px on the 1320-wide canvas, scaled
  proportionally on others. The capture starts a fixed gap below the measured copy block.
- Apple sets use iOS captures. Play sets use **Android** captures, so an iPhone status bar never appears on a
  Play listing. Status bar: 9:41, full signal, full battery (`xcrun simctl status_bar … override`;
  Android demo mode). The phase-5 iPad captures still show the real clock, so recapture them.
- Captures always come from `--dart-define=SCREENSHOT_MODE=true`, which loads the bundled real digest of 14 Oct
  2026 with ads off. No ad banners in store art.

## Screenshot headlines

Order is marketing priority: the first two carry the hooks. Headlines run under 6 words and name the outcome.
Sublines say what the screen shows. Each line is true of the shot it sits on. `screenshots/specs.json` holds
the same strings for the renderer, so change both together.

### Phone (iPhone 6.9" / 6.5", Play phone)

| # | Screen and state | Headline | Subline | Capture theme |
|---|---|---|---|---|
| 1 | Digest list, top of list | Today's top stories, side by side | Today's top stories and who covered each one | light |
| 2 | Story 1, Political lean, Left tab, top | Compare how each side words it | Real headline quotes from left, centre and right | light |
| 3 | Story 5, West / East, West tab, top | See how West and East differ | Western and Eastern outlets on the same story | dark |
| 4 | Story 7 (left-only blindspot chip), top | See what only one side covered | Blindspot labels flag one-sided coverage | light |
| 5 | Story 3, scrolled to "What all sources agree on" | Shared facts and contested claims | Plus what each side leaves out | light |
| 6 | Story 2, scrolled to "Sources" | Every point links to its source | Read the original on the outlet's own site | dark |

### Tablet (iPad 13" landscape, Play 10" tablet landscape)

| # | Screen and state | Headline | Subline | Capture theme |
|---|---|---|---|---|
| 1 | Master-detail, story 1, lean columns | Every side, side by side | Left, centre and right in columns on tablets | light |
| 2 | Master-detail, story 5, West / East columns | West and East, column by column | How Western and Eastern outlets frame the story | dark |
| 3 | Master-detail, story 7 selected (blindspot chip) | See what only one side covered | Blindspot labels flag one-sided coverage | light |
| 4 | Master-detail, story 2 scrolled to "Sources" | Every point links to its source | Read the original on the outlet's own site | light |

Words deliberately avoided: "unbiased", "bias", "truth", "fake", "all outlets", "every outlet", "trusted",
"#1", "award". East–West contradictions are named in the store description, not in a headline, because the
bundled sample day found none, so no screenshot can show one honestly.

## Recommended UI polish

Observed on the phase-4/5 captures. These are suggestions only: design did not change any screen.

1. [x] (done in 3f24d7d) **Nested quote marks.** A quote that itself contains quotes renders as `“identified at a "very early stage.""`
   (Fox News, story 1, Right column). Fold inner straight double quotes to single curly quotes when wrapping.
2. [x] (done in 3f24d7d) **Detail app bar title "Story 1".** A rank is not a name. Consider "1 of 10" or an empty title, since the
   story headline sits directly below.
3. [x] (done in 3f24d7d) **Wordmark in the list app bar.** The list's app bar shows plain "Sides". A 20 dp cube mark before it,
   painted from the same geometry as `icon/build_icon.py`, would tie the app to its icon.
4. [x] (done in 3f24d7d) **Launch screens are white in dark mode.** Both platforms use the Flutter default launch background. Set the
   iOS LaunchScreen and Android `launch_background` (`values-night` too) to the theme surface, so dark-mode users
   do not get a white flash.
5. [x] (done in 3f24d7d) **Source chips truncate at 2 lines** ("…Doctors Say" lost on tablets). On widths ≥ 744 dp, 3 lines would show
   most full headlines without crowding.
6. [x] (done in 3f24d7d) **Rank badge tint.** The pale-blue `primaryContainer` circle is the only cool accent on the light list that is
   not a perspective colour. A neutral `surfaceContainerHighest` badge would keep the colour budget for the sides.
