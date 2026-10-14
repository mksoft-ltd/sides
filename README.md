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

Run the tests (no network is ever used; any socket call fails the suite):

```bash
pytest pipeline
```

Outlets are configured in `pipeline/config/outlets.yaml`. Each has a lean (left/centre/right or null),
region, bloc (west/east), ownership and the public rating the lean comes from. Only headlines and
summaries of at most 200 characters are ever stored; article bodies are never fetched.

Later phases (grouping, analysis, publishing, the GitHub Actions schedule and the `ANTHROPIC_API_KEY`
secret) are documented here as they land.

## App

Flutter app (iOS + Android, phone + tablet). Setup and run instructions follow once the app phase starts.

---

© 2026 Froggy Eye Ltd
