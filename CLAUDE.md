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
  sides_pipeline/         models.py · config.py · text.py · fetch.py · collect.py · group.py · stories.py · cost.py · schema.py · cli.py
  config/outlets.yaml     the outlet pool (see "How to add an outlet")
  config/pipeline.yaml    LLM model + per-stage effort/max_tokens/thresholds (the one place to downgrade the model)
  config/pricing.yaml     USD per MTok per model (cost.py refuses to price an unlisted model)
  config/prompts/*.md     prompt text, never inline in code (group.md so far)
  tests/                  pytest, fixtures/feeds/*.xml, fixtures/llm/*.json, conftest.py (FakeFetcher, article/outlet helpers)
  out/                    run artifacts (git-ignored): articles.json, stories.json, runs/<date>.json (cost report)
schema/digest.schema.json JSON contract between pipeline and app (pydantic models mirror it)
lib/, android/, ios/ …    Flutter app (phases 4–5; untouched by pipeline work)
```

## Commands

```
python3 -m venv pipeline/.venv && pipeline/.venv/bin/pip install -e "pipeline[dev]"
pipeline/.venv/bin/python -m pytest pipeline            # or: cd pipeline && pytest
pipeline/.venv/bin/python -m sides_pipeline.cli collect --out pipeline/out/articles.json [--outlets pipeline/config/outlets.yaml] [--window-hours 36] [--cap 40] [-v]
pipeline/.venv/bin/python -m sides_pipeline.cli group --in pipeline/out/articles.json --out pipeline/out/stories.json [--replay tests/fixtures/llm/x.json] [--raw-out f.json]
pipeline/.venv/bin/python -m sides_pipeline.cli run --through group        # collect → group into pipeline/out/
```

`group` and `run --through group` call the Claude API. Locally the key lives in the macOS Keychain and is read into
the environment for that shell only (never printed, never on disk, never committed):

```
export ANTHROPIC_API_KEY="$(security find-generic-password -s anthropic-api-key -a sides -w)"
```

In GitHub Actions the same variable comes from the repo secret `ANTHROPIC_API_KEY`. `--replay <fixture>` runs the
stage offline from a recorded response (no key needed).

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

### Grouping (phase 2)

- **One streamed Claude call per run** (`group.py: ClaudeGrouper`): `client.beta.messages.stream(...)` →
  `get_final_message()`, model from `pipeline.yaml` (`claude-opus-5-5`), `output_config.effort: medium`,
  structured output via `output_config.format` (JSON schema `stories[] {title, article_ids[]}`), server-side refusal
  fallback (`betas: [server-side-fallback-2026-07-01]`, `fallbacks: "default"`), `max_tokens` 64000. Thinking is always
  on for this model: never send `thinking`, `budget_tokens`, forced `tool_choice` or an assistant prefill (all 400).
  `stop_reason` `refusal` / `max_tokens` / anything but `end_turn` raises `GroupingError` and fails the run (exit 2) —
  a partial digest is never written. The SDK is read from the `claude-api` skill, not memory; re-check it before changing the call.
- **Clean prefix**: stable system prompt (`config/prompts/group.md`) first, the day's article lines last
  (`id | outlet_id | published_at | headline | snippet`, one line each, sorted by outlet then time).
- **The model only proposes groups.** `stories.py` enforces everything else, deterministically: drop unknown ids;
  an article in two stories stays where there are more distinct outlets (tie → first listed); a story needs
  ≥3 **distinct** outlets (several articles from one outlet count once but all stay in `articles[]`); rank by distinct
  outlets ↓, distinct leans covered ↓, blocs covered ↓, earliest `published_at` ↑; keep the top 10; fewer than 5 → the
  stories that qualify plus a `meta.warnings[]` entry. `coverage.lean/bloc` count distinct outlets per tag (lean=null
  outlets count in bloc only); `blindspot.lean/bloc` is the single tag covering the story when all others are 0.
  Story `id` = 12-hex sha1 of the sorted article ids. Titles are capped at 90 chars in code.
- **Cost accounting** (`cost.py`): every call's `usage` (input, output, cache read/write) × `config/pricing.yaml`
  → `RunCost`; written to `pipeline/out/runs/<date>.json`, copied into `meta.cost_usd`, printed as
  `grouping: N in / M out tokens → $x.xxxx`. A failed call is still recorded (it was billed).
- **First live run (14 Oct 2026)**: 723 articles → 65 raw stories → 10 kept (34 had <3 outlets, 21 beyond top 10);
  83,924 in / 9,557 out tokens, $0.53, 137 s.
- **stories.json is digest-shaped** (`schema_version, generated_at, date, meta, outlets, stories`) and validated against
  `schema/digest.schema.json` by the CLI and in tests; phase 3 adds the analysis fields to each story.

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
use) plus synthetic Atom/RSS/malformed/60-item feeds for edge cases.

The LLM is faked through the `Grouper` protocol: `ClaudeGrouper` (real SDK) and `FakeGrouper`, which replays
`tests/fixtures/llm/group_*.json` (`{model, stop_reason, usage, response: {stories[]}}`) and raises on a replayed
`refusal`/`max_tokens` exactly like the real one. To record a fixture: run the stage live with
`--raw-out <file>` (that is the fixture), then trim `articles.json` to the articles the response references
(`articles_live_<date>.json`); `tests/test_group_live_fixture.py` shows the pair in use. `ClaudeGrouper` itself is
tested with a stand-in client that records the request kwargs (model, effort, format, betas, fallbacks).

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
