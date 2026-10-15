# Sides — screenshot capture specs

Headline copy, framing rules and order: `BRAND.md` → "Screenshot headlines" and "Screenshot framing".
Renderer: `screenshots/render.sh [target …]` reads `screenshots/specs.json` and frames
`<raw_dir>/<raw>` into `screenshots/out/<target>/<id>.png`. Missing captures are skipped and listed.

Every capture: `--dart-define=SCREENSHOT_MODE=true`, which loads the bundled 14 Oct 2026 digest with ads off.
Status bar overridden to 9:41 with full bars and battery. Story ids below are from that digest.

| raw file | Device | Route / dart-defines | State to reach before capture | Theme |
|---|---|---|---|---|
| `phone_01_digest.png` | iPhone 6.9" | `SCREENSHOT_ROUTE=/` | none, top of list | light |
| `phone_02_wording.png` | iPhone 6.9" | `/story/c8bbc1a001c2` | none, Lean axis, Left tab | light |
| `phone_03_west_east.png` | iPhone 6.9" | `/story/8c5fe1c3c5b6?axis=bloc` | none, West tab | dark |
| `phone_04_blindspot.png` | iPhone 6.9" | `/story/b4b715a72e0d` | none, the "Only left-leaning outlets covered this" chip must be on screen | light |
| `phone_05_agreed.png` | iPhone 6.9" | `/story/aa7201957adf` | scroll until the heading "What all sources agree on" is ~120 dp below the app bar | light |
| `phone_06_sources.png` | iPhone 6.9" | `/story/728984a49b5c` | scroll until the heading "Sources" is ~120 dp below the app bar | dark |
| `ipad_01_lean_columns.png` | iPad 13" landscape | `/story/c8bbc1a001c2`, `SCREENSHOT_ORIENTATION=landscape` | none | light |
| `ipad_02_bloc_dark.png` | iPad 13" landscape | `/story/8c5fe1c3c5b6?axis=bloc`, landscape | none | dark |
| `ipad_03_blindspot.png` | iPad 13" landscape | `/story/b4b715a72e0d`, landscape | none, the chip shows at the top of the detail pane | light |
| `ipad_04_sources.png` | iPad 13" landscape | `/story/728984a49b5c`, landscape | scroll the detail pane to "Sources" | light |

Android: capture the same phone list on a Pixel-class emulator (1080 × 2400) into `screenshots/raw_android/`, and
the tablet list on a 10" landscape tablet emulator (2560 × 1600), with the same file names.

Rules carried from earlier ship runs:
- Each scrolled shot names **one** anchor heading. Do not require two elements on one frame.
- Scroll anchors are found by their text (`Copy.agreed`, `Copy.sources` in `lib/core/constants/copy.dart`);
  if the copy changes, change this file.
- `docs/screenshots/phase4/01`, `02` and `phase5/01`, `04` were copied into `raw/` as framing proofs only.
  They are 6.3" captures, and the iPad ones show a live clock. Replace them with real captures before upload.
