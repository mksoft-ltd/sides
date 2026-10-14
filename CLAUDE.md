# Sides: The News, Every Angle — project notes

Daily news digest: a Python pipeline collects headlines from ~25 outlets tagged by lean (left/centre/right),
region and bloc (West/East), groups them into the day's top stories, analyses how each side frames them with
every point traceable to a source article, and publishes JSON that the Flutter app reads.
Approved plan: `~/.claude/plans/curried-herding-yao.md`. Ship-app stage tracker: `PIPELINE.md`.
Publisher: Froggy Eye Ltd (house-facts §3). Bundle/package `com.froggyeye.sides`.

## Layout

```
pipeline/                 Python 3.12+ package (flat layout, no src/)
  pyproject.toml          deps, `pip install -e pipeline[dev]`, pytest config (socket guard)
  sides_pipeline/         models.py · config.py · text.py · fetch.py · collect.py · cli.py   (+ group/analyse/publish later)
  config/outlets.yaml     the outlet pool (see "How to add an outlet")
  tests/                  pytest, fixtures/feeds/*.xml, conftest.py (FakeFetcher)
  out/                    run artifacts (git-ignored): articles.json, later digest.json
schema/digest.schema.json JSON contract between pipeline and app (pydantic models mirror it)
lib/, android/, ios/ …    Flutter app (phases 4–5; untouched by pipeline work)
```

## Commands

```
python3 -m venv pipeline/.venv && pipeline/.venv/bin/pip install -e "pipeline[dev]"
pipeline/.venv/bin/python -m pytest pipeline            # or: cd pipeline && pytest
pipeline/.venv/bin/python -m sides_pipeline.cli collect --out pipeline/out/articles.json [--outlets pipeline/config/outlets.yaml] [--window-hours 36] [--cap 40] [-v]
```

## Architecture decisions so far

- **Feeds only, never article bodies.** RSS/Atom headline + feed summary; the summary is HTML-stripped and cut
  at a word boundary to ≤200 chars. This is the only ingestion that respects every outlet's terms.
- **Outlet tags live in config, not code.** `lean`, `region`, `bloc`, `ownership`, `rating_basis` per outlet.
  Lean ratings cite a public rating service (AllSides / Ad Fontes) with a check date. State-controlled outlets
  must have `lean: null`; non-Western outlets also get `lean: null` + `lean_note` because the UK/US
  left–right scale is not applied to them — they are analysed on the West/East axis instead.
- `ownership` has four values: `independent`, `public-service` (BBC, NPR, DW, France 24),
  `state-funded` (Al Jazeera: government-funded, editorially separate), `state-controlled` (CGTN, Global Times,
  Xinhua). `state-funded` was added in phase 1 so Al Jazeera is neither mislabelled "state-controlled" nor
  "public-service".
- **Collector contract** (`collect.py`): 36 h window, 40 most-recent items per outlet, dedupe by canonical URL
  (tracking params stripped) and by (outlet, normalised headline), missing dates fall back to fetch time with
  `published_at_estimated: true`, a failing feed goes to `feed_errors[]` and never aborts the run.
  `enabled: false` outlets are skipped but stay on record.
- **Network is isolated in `fetch.py`.** Everything else takes an injected `fetch(url) -> bytes`, so tests
  run entirely on fixtures.
- Python 3.14 is what the dev Mac has; the package declares `>=3.12` and uses nothing newer than 3.12.

## Integrity rules (from the spec — do not weaken)

1. Never store or publish article text beyond headline + ≤200-char snippet (`Article.snippet` max_length, schema `maxLength`).
2. Every analytical claim must cite article ids; unsourced ⇒ dropped (phase 3 validator).
3. Coverage/blindspot indicators are computed in code from outlet tags, never asked of the model.
4. No secrets in the repo or the app; the Anthropic key is a GitHub Actions secret only.
5. Tests never touch the network (see below).

## Test policy: no network in tests

`pipeline/pyproject.toml` runs pytest with `--disable-socket` (pytest-socket), so any socket call fails the
suite. `tests/test_no_network.py` asserts this directly. Feed fixtures live in `tests/fixtures/feeds/`:
four real feeds recorded once on 14 Oct 2026 (trimmed to 10 items; `conftest.RECORDED_AT` is the "now" tests
use) plus synthetic Atom/RSS/malformed/60-item feeds for edge cases. Later phases fake the LLM the same way
(`fixtures/llm/*.json`).

## How to add an outlet

1. Find the outlet's public RSS/Atom feed for top or world stories (English-language only). Check it live
   once (items, dates within the last day or two, no bot challenge).
2. Add a row to `pipeline/config/outlets.yaml` with every field (see the header comment). Choose `lean`
   from a public rating and name it in `rating_basis`; set `lean: null` + `lean_note` for non-Western
   outlets; `state-controlled` outlets must be `lean: null`.
3. `pytest` — `tests/test_outlets_config.py` checks required fields, unique ids, enum values and the lean rules.
4. Run `collect` once and confirm the outlet appears with a sensible count.
5. Never add RT, Sputnik or Press TV (UK-sanctioned; store takedown risk).
   If a feed dies, set `enabled: false` with a dated `note` rather than deleting the row (ids are stable).

## Conventions

- House style: British spelling in prose, `centre` not `center` in enums.
- JSON output uses ISO-8601 UTC with `Z`; ids are 12-hex sha1 prefixes of `outlet_id + "\n" + canonical url`.
- Commit trailer: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
