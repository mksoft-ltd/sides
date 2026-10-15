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

Icon faces: top `#C3CDD3`, left `#8F63D2`, right `#E8914A`, which are the lean colours tuned to sit on the dark plate.

## Typography

- **In app:** the platform system font (SF Pro on iOS, Roboto on Android) via Material 3's default
  text theme. No bundled fonts; Dynamic Type / font scale up to 200% is honoured.
- **Store art:** SF Pro Display (rendered from `-apple-system` in headless Chrome). Headline weight 700,
  tracking −2%; sublines 400 at ~0.78 opacity. Sentence case, no full stop on headlines.
- **Wordmark:** "Sides" in SF Pro Display Semibold, sentence case, no lockup tricks.

## Iconography and the app icon

The mark is **one cube seen from its corner, so three faces show at once**: the same object, three sides.
The faces are pulled slightly apart along their normals, leaving a Y-shaped seam so the three sides stay
distinct at 48 px. The colours echo the in-app lean palette: violet face on the left, orange face on the right,
lit slate face on top between them. All three faces have equal area, so no side is bigger than another.

- No outlet logos, flags, globes, newspaper mastheads or real-world brands.
- Generated from primitives by `icon/build_icon.py`; proofs at 180/120/48 px and inside the round
  launcher mask (`icon/preview_*.png`). The adaptive foreground keeps its farthest corner at 28.5 dp from
  the centre, inside the 33 dp safe circle. The themed (monochrome) icon separates the faces by opacity.
- In-app icons: Material Symbols outlined, default weight, so they match the M3 components already in use.

### Store-art rule (house-facts §29, Google Play Metadata policy)

**No tick, badge, seal, rosette, laurel, ribbon, medal or star in any store art**: app icon, adaptive
icon, Play hi-res icon, feature graphic, or screenshot framing. Play reads them as claims about awards,
ranking or endorsement and rejects the listing (Passport Photo Studio, 11 Aug 2026). Glyphs inside genuine
app UI captures are fine. Do not add a "verified" or "trusted" mark to the cube, ever.

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

Dark plate gradient. Left: the cube mark (120 px) beside the "Sides" wordmark (70 px Semibold) and the line
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
| 1 | Digest list, top of list | Every story, every angle | Today's top stories and who covered each one | light |
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

1. **Nested quote marks.** A quote that itself contains quotes renders as `“identified at a "very early stage.""`
   (Fox News, story 1, Right column). Fold inner straight double quotes to single curly quotes when wrapping.
2. **Detail app bar title "Story 1".** A rank is not a name. Consider "1 of 10" or an empty title, since the
   story headline sits directly below.
3. **Wordmark in the list app bar.** The list's app bar shows plain "Sides". A 20 dp cube mark before it,
   painted from the same geometry as `icon/build_icon.py`, would tie the app to its icon.
4. **Launch screens are white in dark mode.** Both platforms use the Flutter default launch background. Set the
   iOS LaunchScreen and Android `launch_background` (`values-night` too) to the theme surface, so dark-mode users
   do not get a white flash.
5. **Source chips truncate at 2 lines** ("…Doctors Say" lost on tablets). On widths ≥ 744 dp, 3 lines would show
   most full headlines without crowding.
6. **Rank badge tint.** The pale-blue `primaryContainer` circle is the only cool accent on the light list that is
   not a perspective colour. A neutral `surfaceContainerHighest` badge would keep the colour budget for the sides.
