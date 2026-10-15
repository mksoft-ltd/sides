# store_assets/

Design sources for Sides. Everything regenerates from a script, with no hand-edited binaries.

| Path | What |
|---|---|
| `BRAND.md` | Palette, typography, icon rationale, tone, store-art rules, screenshot headlines, UI polish list |
| `screenshot_specs.md` | What to capture: route, state, theme per raw file |
| `icon/build_icon.py` | Pillow finisher: OpenArt mark (`icon/openart/r2_fanned.png`) → master, adaptive foreground, monochrome, `icon_mark.png`, `../icon_512.png`, proofs |
| `feature_graphic/render.sh` | headless Chrome → `../feature_graphic.png` + `proof_crop.png` |
| `screenshots/render.sh` | `specs.json` + `frame.html` + `raw*/` → `out/<target>/` |

## Regenerating the icon

```bash
python3 store_assets/icon/build_icon.py     # PNGs + proofs from the chosen OpenArt mark
dart run flutter_launcher_icons             # wires both platforms (config at the end of pubspec.yaml)
git checkout -- ios/Runner.xcodeproj/project.pbxproj
```

The mark is generated artwork: rerunning the script never spends credits. A new mark means a new OpenArt
pass (prompts and creation ids in BRAND.md, "Generated artwork") and a new `RAW` path in the script.
After the icon changes, rerun `feature_graphic/render.sh`, which embeds `icon/icon_mark.png`.

**Always revert the pbxproj afterwards.** `flutter_launcher_icons` 0.14.4 overwrites the project-level
`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES` with `= AppIcon` in both build
configurations. That is a package bug: the target already sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
The icon PNGs and `Contents.json` it writes are correct, so keep those.

The Android adaptive background is the solid colour `#15252C`. The package writes it to
`android/app/src/main/res/values/colors.xml` and owns that file, so put any hand-written colour in a separate
`values*/` file.

## Proofs worth looking at

- `icon/preview_48.png`: does the newspaper still read at launcher size?
- `icon/preview_adaptive.png`: the foreground at the 16% inset inside the round mask, with the 66 dp safe circle in red.
- `feature_graphic/proof_crop.png`: the outer 100 px shaded, because Play crops there on some surfaces.

Pillow is installed in the system `python3`. Chrome is used only for the HTML art.
