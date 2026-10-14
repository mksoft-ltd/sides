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

Later phases (analysis, publishing, the GitHub Actions schedule) are documented here as they land.

## App

Flutter app (iOS + Android, phone + tablet). Setup and run instructions follow once the app phase starts.

---

© 2026 Froggy Eye Ltd
