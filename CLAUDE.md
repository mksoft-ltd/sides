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
  sides_pipeline/         models.py · config.py · text.py · fetch.py · collect.py · llm.py · group.py · stories.py · analyse.py · validate.py · digest.py · cost.py · schema.py · cli.py
  config/outlets.yaml     the outlet pool (see "How to add an outlet")
  config/pipeline.yaml    LLM model + per-stage effort/max_tokens/thresholds (the one place to downgrade the model)
  config/pricing.yaml     USD per MTok per model (cost.py refuses to price an unlisted model)
  config/prompts/*.md     prompt text, never inline in code (group.md, analyse.md)
  tests/                  pytest, fixtures/feeds/*.xml, fixtures/llm/*.json + analyse_live_<date>/<story_id>.json, conftest.py
  out/                    run artifacts (git-ignored): articles.json, stories.json, digest.json, runs/<date>.json (cost report)
schema/digest.schema.json JSON contract between pipeline and app (pydantic models mirror it)
lib/, android/, ios/ …    Flutter app (phases 4–5; untouched by pipeline work)
```

## Commands

```
python3 -m venv pipeline/.venv && pipeline/.venv/bin/pip install -e "pipeline[dev]"
pipeline/.venv/bin/python -m pytest pipeline            # or: cd pipeline && pytest
pipeline/.venv/bin/python -m sides_pipeline.cli collect --out pipeline/out/articles.json [--outlets pipeline/config/outlets.yaml] [--window-hours 36] [--cap 40] [-v]
pipeline/.venv/bin/python -m sides_pipeline.cli group --in pipeline/out/articles.json --out pipeline/out/stories.json [--replay tests/fixtures/llm/x.json] [--raw-out f.json]
pipeline/.venv/bin/python -m sides_pipeline.cli analyse --in pipeline/out/stories.json --out pipeline/out/digest.json [--replay-dir DIR] [--raw-out-dir DIR]
pipeline/.venv/bin/python -m sides_pipeline.cli show --story 1 [--in pipeline/out/digest.json]   # one story's full analysis, sources resolved
pipeline/.venv/bin/python -m sides_pipeline.cli run --through analyse      # collect → group → analyse into pipeline/out/
```

`group`, `analyse` and `run` call the Claude API. Locally the key lives in the macOS Keychain and is read into
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
  `schema/digest.schema.json` by the CLI and in tests; the analysis arrays are present but empty until `analyse` runs.

### Analysis (phase 3)

- **One call per story** (`analyse.py: ClaudeAnalyser`) through the same wrapper as grouping (`llm.py`:
  stream → `get_final_message`, `output_config.effort: high`, structured output `ANALYSIS_OUTPUT_SCHEMA`, refusal
  fallback, usage captured). Stories run on a thread pool bounded to `analysis.concurrency` (4); results come back
  in story order. System prompt `config/prompts/analyse.md`; user message = title, a header naming the leans and
  blocs that actually have articles, then `id | outlet | lean | bloc | ownership | published_at | headline | snippet`
  per article (`lean: n/a` for outlets off the UK/US scale, which belong to the bloc axis only).
- **Two axes in one response**: lean (`agreed_facts`, `framing[]` per lean, `omissions[]`, `contested_claims[]`,
  `opinion[]`) and West/East (`framing_by_bloc[]`, `east_west_contradictions[]` = one topic with a `west` and an
  `east` side that state incompatible things; empty when they do not, shown as "none found", never padded).
- **Failure is per story, not per run**: refusal / `max_tokens` / unparsable JSON → one retry (`analysis.retries`),
  then the story ships with empty analysis arrays and a `meta.warnings[]` entry. Every attempt is billed and costed.
  The command exits 1 only when every story failed.
- **Citation validator** (`validate.py`, deterministic, runs after every response; integrity rule 2). An item is
  dropped under the first failing rule and counted in `story.validation` and `meta.validation`
  (`{kept, dropped_by_reason{reason: n}}`):

  | reason | rule |
  |---|---|
  | `unknown_id` | any cited id (`sources`, `asserted_by`, `disputed_by`, `article_id`) is not an article of this story |
  | `empty_sources` | `sources` / either side of a contested claim or contradiction is empty |
  | `quote_not_found` | a headline quote is not a literal substring of the cited article's headline or snippet (case-insensitive, whitespace-collapsed, curly quotes/dashes folded to ASCII); a kept quote gets `field: "headline"` or `"snippet"` from the validator (headline wins when both match), never from the model |
  | `side_without_articles` | a framing entry or omission names a lean/bloc with no article in this story |
  | `source_outside_side` | a framing quote or emphasis item cites an article not of that lean/bloc (lean=null articles belong to no lean) |
  | `omission_cites_omitter` | an omission is sourced to an article of the lean said to omit the point |
  | `contested_same_outlet` | `asserted_by` and `disputed_by` share an outlet (the two sides must be disjoint outlet sets) |
  | `contradiction_wrong_bloc` | `west.sources` not all West-bloc articles, or `east.sources` not all East-bloc |
  | `empty_framing` | a framing entry has nothing left once its quotes and emphasis were checked |

  Duplicate ids inside one item collapse; two entries for the same lean/bloc merge; texts over 200 chars are cut at a
  word boundary (logged, not dropped). Nothing the validator did not pass reaches `digest.json`.
- **Digest assembly** (`digest.py`): stories.json + validated analysis → `out/digest.json`, `meta.cost_usd` = grouping
  + analysis (the standalone `analyse` command continues `out/runs/<date>.json` via `RunCost.load`), `meta.validation`
  = totals, `generated_at` refreshed; validated against the schema before writing (all analysis arrays are required,
  possibly empty).
- **Replay recipe**: `analyse --raw-out-dir DIR` saves each story's raw response as `DIR/<story_id>.json` (fixture
  shape `{model, stop_reason, usage, response}`); `analyse --replay-dir DIR` replays them with no key and no network.
  `tests/fixtures/llm/analyse_live_2026-10-14/` holds the first live run; `tests/test_analyse_live_fixture.py`
  rebuilds the digest from the phase-2 live fixtures + these and asserts 0 `unknown_id` drops.
- **First live run (14 Oct 2026)**: 10 stories, 10 calls (no retries), 4 in flight; 51,052 in / 31,189 out tokens,
  $0.83, 84 s wall (longest call 42.5 s). Validator: 318 items kept, 0 dropped; 0 East–West contradictions found
  (the day's stories were not contested between blocs). Day total with grouping: $1.35 (≈ £32/month at one run a
  day, above the plan's ~$0.75 estimate because `high` effort spends ~3k reasoning+output tokens per story).

## Integrity rules (from the spec — do not weaken)

1. Never store or publish article text beyond headline + ≤200-char snippet (`Article.snippet` max_length, schema `maxLength`).
2. Every analytical claim must cite article ids; unsourced ⇒ dropped (`validate.py`, rules table above).
3. Coverage/blindspot indicators are computed in code from outlet tags, never asked of the model.
4. No secrets in the repo or the app; the Anthropic key is a GitHub Actions secret only.
5. Tests never touch the network (see below).

## Test policy: no network in tests

`pipeline/pyproject.toml` runs pytest with `--disable-socket` (pytest-socket), so any socket call fails the
suite. `tests/test_no_network.py` asserts this directly. Feed fixtures live in `tests/fixtures/feeds/`:
four real feeds recorded once on 14 Oct 2026 (trimmed to 10 items; `conftest.RECORDED_AT` is the "now" tests
use) plus synthetic Atom/RSS/malformed/60-item feeds for edge cases.

The LLM is faked through the `Grouper` / `Analyser` protocols: `ClaudeGrouper` / `ClaudeAnalyser` (real SDK via
`llm.py`) and `FakeGrouper` / `FakeAnalyser` (per-story `<story_id>.json` fixtures). `FakeGrouper` replays
`tests/fixtures/llm/group_*.json` (`{model, stop_reason, usage, response: {stories[]}}`) and raises on a replayed
`refusal`/`max_tokens` exactly like the real one. To record a fixture: run the stage live with
`--raw-out <file>` (that is the fixture), then trim `articles.json` to the articles the response references
(`articles_live_<date>.json`); `tests/test_group_live_fixture.py` shows the pair in use. `ClaudeGrouper` itself is
tested with a stand-in client that records the request kwargs (model, effort, format, betas, fallbacks); so is
`ClaudeAnalyser` (`tests/test_analyse.py`). `tests/test_validate.py` has one test per validator rule, each introducing
exactly one violation into an otherwise fully valid response.

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

## App (Flutter)

Spec: `docs/PRODUCT_SPEC.md`. Stack: flutter_riverpod 3 (Notifier, no codegen), go_router, http, path_provider,
shared_preferences, url_launcher, intl, google_mobile_ads **pinned 9.0.0**, in_app_purchase (+ in_app_purchase_android
for a type guard). No analytics, crash reporting or accounts.

```
lib/app/            app.dart (MaterialApp.router, theme, text scale clamp 2.0, lifecycle → resume hooks), router.dart (Routes)
lib/core/           config/ (AppConfig URLs + product id + SCREENSHOT_* defines; AdConfig = every AdMob id), constants/copy.dart
                    (all content-facing UI strings), theme/ (PerspectiveColors), layout/breakpoints.dart, launcher/, storage/, time/
lib/features/digest domain/digest.dart (models + on-read integrity), domain/refresh_policy.dart, data/ (cache, remote, repository),
                    presentation/ (DigestController, DigestListView body + DigestListScreen scaffold, StoryCard)
lib/features/story  StoryDetailView (body) + StoryDetailScreen; widgets/ points, source chips, sources list
lib/features/{settings,purchases,ads}   theme mode, AdFreeController over StoreGateway, AdsService + AdBannerSlot
test/               fixtures (= assets/sample_digest.json), helpers/ (fakes, pumpSidesApp at 390×844), unit/, widget/
```

- **Seams, all overridden in `main()` and in tests**: `digestRepositoryProvider`, `settingsStoreProvider`,
  `storeGatewayProvider`, `adsServiceProvider` (default `DisabledAdsService`), `linkLauncherProvider`,
  `reconcileAtLaunchProvider`. Widget tests never touch a plugin; use `TestHarness`/`pumpSidesApp`.
- **Refresh policy**: cache first; revalidate on launch/resume when digest `date` < today (UTC) or fetched > 6 h
  ago; pull-to-refresh always fetches; conditional on ETag; a bad body never overwrites the cache; body decoded as UTF-8.
- **Integrity in the UI**: `Story.fromJson` strips unknown source ids and drops any point left unsourced; quotes need
  a resolvable article. Never render article text beyond headline + snippet; content copy lives in `Copy` and stays
  descriptive (never judges an outlet). Lean colours are violet/slate/orange, not red/blue (opposite meanings in UK/US).
- **Ads**: banner only in `bottomNavigationBar` of list/detail, hidden until a digest exists and the instant ad-free
  is owned. No ATT prompt: every request is `nonPersonalizedAds: true`, Google UMP gathers consent. Test IDs until
  publish (`AdConfig`, Info.plist `GADApplicationIdentifier`, manifest `APPLICATION_ID`).
- **IAP**: outcomes only arrive on `purchaseStream`; busy has a 75 s ceiling; entitlement persisted before
  `completePurchase`; Play-only silent restore at launch/resume; Play pending purchases are not granted.
- **Native**: SPM disabled in pubspec (ads pod is CocoaPods-only); iOS min 15.0 (pbxproj + Podfile post_install);
  UIScene adopted (FlutterSceneDelegate + FlutterImplicitEngineDelegate, iOS 27 safe). google_mobile_ads 9.1.0
  breaks the iOS module import (non-modular private header); re-test before unpinning.
- **Deep link**: `/story/:id?axis=bloc` opens West / East. Screenshot harness: `SCREENSHOT_MODE=true` +
  `SCREENSHOT_ROUTE=<route>` (ignored in release).
- **Tablet layout (phase 5)**: `lib/app/adaptive_pages.dart` — `HomePage` (`/`) and `StoryPage` (`/story/:id`) pick
  the phone screen or `MasterDetailScreen` from `LayoutSize` on every build, so rotation switches live. Single adaptive
  route, no ShellRoute: at tablet widths a selection is `context.go(Routes.story(id, axis:))`; go_router keys a
  declarative match by its route pattern, so story → story updates the same `NoTransitionPage` in place. The first
  selection from `/` adds that page over `/` (system back returns to story 1). Phones keep `MaterialPage` + push.
  The list scroll offset survives that first hop via `masterListScrollProvider`.
- Axis + tab per story live in `storyViewProvider` (autoDispose family by story id; `axis == null` means "use the
  route's `?axis=`"), not widget state — a layout swap re-subscribes in the same frame so the reader's place survives.
- Columns: `StoryDetailView.columnsFit` — only at `LayoutSize.expanded` and only when every column gets ≥ 280 dp ×
  text scale; else tabs. Contradiction rows (`ContradictionCard(sideBySide:)`) drop the card inset so they align
  with the bloc columns. iPad portrait < 840 dp (all but 12.9"/13") gets the phone layout by design of the breakpoint.
- Tablet tests: `test/widget/tablet_layout_test.dart` (sizes in dp; pumpSidesApp renders at 3×).
