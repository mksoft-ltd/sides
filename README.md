# Sides: The News, Every Angle

A daily news digest that shows how outlets across the political spectrum, and across the West/East divide,
frame the same story — every point traceable to a source headline. Two parts live in this repo:

- `pipeline/` — Python pipeline that collects headlines once a day, groups them into stories, analyses the
  framing and publishes a JSON digest (runs on GitHub Actions, publishes to GitHub Pages).
- the Flutter app (`lib/`, `android/`, `ios/`) that reads the digest.

Project notes, decisions and conventions are in `CLAUDE.md`; the JSON contract is `schema/digest.schema.json`.

## Pipeline setup

Requires Python 3.12 or newer.

```bash
python3 -m venv pipeline/.venv
source pipeline/.venv/bin/activate
pip install -e "pipeline[dev]"
```

Collect today's headlines (needs the network; writes `pipeline/out/articles.json` and prints a per-outlet table):

```bash
python -m sides_pipeline.cli collect --out pipeline/out/articles.json
```

Options: `--outlets <yaml>` (default `pipeline/config/outlets.yaml`), `--window-hours 36`, `--cap 40`, `-v`.

Group today's articles into the top stories (one Claude call; writes `pipeline/out/stories.json` and
`pipeline/out/runs/<date>.json` with the run's cost, prints the ranked table and the cost line):

```bash
export ANTHROPIC_API_KEY="$(security find-generic-password -s anthropic-api-key -a sides -w)"   # macOS Keychain, local runs
python -m sides_pipeline.cli group --in pipeline/out/articles.json --out pipeline/out/stories.json
python -m sides_pipeline.cli run --through group          # collect → group in one go
```

The key is never written to disk; in GitHub Actions it comes from the repo secret `ANTHROPIC_API_KEY`. Model,
effort and thresholds live in `pipeline/config/pipeline.yaml`; prices in `pipeline/config/pricing.yaml`; the
grouping prompt in `pipeline/config/prompts/group.md`. Add `--replay pipeline/tests/fixtures/llm/group_live_2026-10-14.json`
to run the stage offline from a recorded response.

Run the tests (no network is ever used; any socket call fails the suite):

```bash
pytest pipeline
```

Outlets are configured in `pipeline/config/outlets.yaml`. Each has a lean (left/centre/right or null),
region, bloc (west/east), ownership and the public rating the lean comes from. Only headlines and
summaries of at most 200 characters are ever stored; article bodies are never fetched.

Analyse the stories (one Claude call per story, four in flight; writes `pipeline/out/digest.json`, the finished
digest, and extends the day's cost report; prints a per-story table of counts, the validator totals and the cost):

```bash
python -m sides_pipeline.cli analyse --in pipeline/out/stories.json --out pipeline/out/digest.json
python -m sides_pipeline.cli show --story 1                # one story's full analysis with every source resolved
python -m sides_pipeline.cli run --through analyse        # collect → group → analyse in one go
```

Every point in the digest cites article ids from its own story; the citation validator drops anything that does not
(the drop counts are in `meta.validation`). A story whose analysis call fails ships with empty analysis and a warning.
Add `--replay-dir pipeline/tests/fixtures/llm/analyse_live_2026-10-14` to run the stage offline; `--raw-out-dir DIR`
records a new set of fixtures. The analysis prompt is `pipeline/config/prompts/analyse.md`.

Publish a finished run onto the GitHub Pages site (see Deployment):

```bash
python -m sides_pipeline.cli publish --site .site      # writes digest/, runs/, index.html into a site directory
scripts/publish_site.sh [--no-push]                     # clone gh-pages → publish → commit "Digest <date>" → push
```

## Deployment

The digest is produced once a day by GitHub Actions and served from GitHub Pages; nothing else is hosted.

- **Daily run**: `.github/workflows/daily.yml` runs at 06:00 UTC (`cron "0 6 * * *"`) on `ubuntu-latest` with
  Python 3.12: `pip install -e pipeline`, then `python -m sides_pipeline.cli run --through analyse` with the key from the
  repo secret `ANTHROPIC_API_KEY`. It then checks out the `gh-pages` branch, runs `publish`, commits `Digest YYYY-MM-DD`
  as `github-actions[bot]` and pushes; Pages goes live a minute or so later. A non-zero exit from any stage fails
  the run (red) and GitHub emails the repo owner. One run costs about $1.35 (Claude Opus 5.5; ~£32/month).
- **Site** (`https://mksoft-ltd.github.io/sides/`): `digest/latest.json` (what the app reads), `digest/YYYY-MM-DD.json`
  (one per day, kept), `digest/index.json` (newest-first `{date, generated_at, stories, cost_usd}` for every day),
  `runs/YYYY-MM-DD.json` (the day's cost report), `privacy_policy.html` (once the file exists at the repo root),
  `index.html`. Published by `pipeline/sides_pipeline/publish.py` via `scripts/publish_site.sh`.
- **Per-run cost report**: three places, every run — the workflow's job summary (Actions → the run → Summary: the
  `grouping` / `analysis` / `total` lines and the top-stories table), `runs/<date>.json` on the site
  (`https://mksoft-ltd.github.io/sides/runs/<date>.json`, every call with token counts and USD), and `meta.cost_usd` in
  the digest itself. The run's whole `pipeline/out/` is also attached to the run as an artifact for 14 days.
- **Run it by hand**: Actions → "Daily digest" → Run workflow, or from a terminal:

  ```bash
  gh workflow run daily.yml                      # full run and publish (paid, ~$1.35)
  gh workflow run daily.yml -f through=group     # stop after grouping (one paid call), no publish
  gh workflow run daily.yml -f dry_run=true      # collect only: free, no publish, checks the feeds
  gh run watch                                   # follow it
  ```

  Locally the same thing is `python -m sides_pipeline.cli run --through analyse && scripts/publish_site.sh`
  (your git credentials push `gh-pages`).
- **Rotate the key**: create a new key in the Anthropic console, then `gh secret set ANTHROPIC_API_KEY` (paste when
  prompted; never put it on the command line or in a file), run `gh workflow run daily.yml -f through=group` to prove it
  works, then revoke the old key. Locally: `security add-generic-password -U -s anthropic-api-key -a sides -w`.
- **CI**: `.github/workflows/ci.yml` runs `pytest` (network blocked) and `flutter analyze` + `flutter test`
  (Flutter 3.44.4) on every push and pull request to `main`.
- **Sleep guard**: GitHub switches off scheduled workflows in a public repo after 60 days without repository
  activity. The daily run re-enables itself through the API and, when `main` has been quiet for 45 days, pushes a dated
  `.github/keepalive` marker to `main` (details in `CLAUDE.md`).

## App

Flutter app (iOS + Android; phone layout done, tablet layout is phase 5). Requires Flutter 3.44+, Xcode with
CocoaPods, and the Android SDK. No keys or secrets are needed: the app reads the public digest at
`https://mksoft-ltd.github.io/sides/digest/latest.json` (live from phase 6).

```bash
flutter pub get
flutter analyze
flutter test                                    # unit + widget tests, no network, no ads/IAP plugins
flutter run                                     # live digest (404 until phase 6 publishes it)
flutter run --dart-define=SCREENSHOT_MODE=true  # bundled sample digest, no ads (debug/profile only)
flutter build apk --debug
```

iOS simulator builds: on Xcode 27, `flutter build ios --simulator` fails in Flutter's own packaging step
(`lipo -verify_arch` takes one arch). Build with xcodebuild instead:

```bash
flutter build ios --simulator --debug   # writes Generated.xcconfig, then fails at debug_unpack_ios (toolchain bug)
cd ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination "generic/platform=iOS Simulator" BUILD_DIR=$PWD/../build/ios \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted ../build/ios/Debug-iphonesimulator/Runner.app && xcrun simctl launch booted com.froggyeye.sides
```

Ads use Google's test IDs until the publish stage (see `lib/core/config/ad_config.dart`). The ad-free product
`com.froggyeye.sides.adfree` must exist in App Store Connect and Play Console before the purchase button enables.
Product spec: `docs/PRODUCT_SPEC.md`. Phase 4 screenshots: `docs/screenshots/phase4/`; tablet (iPad Pro 12.9") screenshots: `docs/screenshots/phase5/`.
Xcode 27 here has no Simulator.app, so iPad landscape captures use `--dart-define=SCREENSHOT_ORIENTATION=landscape`
with `UIRequiresFullScreen` temporarily added to Info.plist (iPadOS ignores orientation requests from multitasking apps);
revert it before committing.

---

© 2026 Froggy Eye Ltd
