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
  sides_pipeline/         models.py · config.py · text.py · fetch.py · collect.py · llm.py · group.py · stories.py · analyse.py · validate.py · guard.py · digest.py · cost.py · schema.py · cli.py
  requirements.lock       hash-locked runtime deps for CI (requirements-dev.lock adds pytest); see "Deployment"
  config/outlets.yaml     the outlet pool (see "How to add an outlet")
  config/pipeline.yaml    LLM model + per-stage effort/max_tokens/thresholds (the one place to downgrade the model)
  config/pricing.yaml     USD per MTok per model, incl. the refusal-fallback models (an unlisted model is recorded unpriced + warned, never fatal)
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
- **Feed text is untrusted (security audit SEC-1/2/4, fix round 2).** Every `feed_url` must be https (the `Outlet`
  model refuses http). An item whose link is not on `home_url`'s host or a listed `link_hosts` host (subdomains
  included) is dropped (`link_off_domain`); `http://` links are upgraded. An item whose headline or snippet reads like
  an instruction to a model (`guard.instruction_like`: "ignore previous instructions", "system prompt", "as an AI model",
  "all outlets agree", role tags…) is dropped before any prompt (`instruction_text`). Only the headline and the stored
  ≤200-char snippet are screened, never the full summary, and patterns are phrase-level: the first live dry run dropped
  The National's property story on "New instructions in this market decreased…", so "new instructions", "developer
  mode", "jailbreak" and bare "as an assistant/AI" are deliberately not patterns (regression cases in
  `test_injection_guard.py`; 0 of 713 live articles trip the screen, 15 Oct 2026).
  Both are counted per outlet in `articles.json` `item_drops[]` and summarised in `meta.warnings`.
- **Network is isolated in `fetch.py`.** Everything else takes an injected `fetch(url) -> bytes`, so tests
  run entirely on fixtures.
- **Blocked/throttled feeds** (both full Actions runs of 14-15 Oct lost The Independent to 429 and Times of Israel to
  403 from GitHub's IP range; both fine from the Mac): `fetch.USER_AGENT` is browser-shaped with `SidesNewsBot/<v>` and
  our URL in its comment, `Accept: application/rss+xml, application/xml;q=0.9, */*;q=0.8`. `fetch_with_retry` retries
  403/429/5xx and transport errors 3 times (1 s·2^n + jitter, at least `Retry-After`, capped at 30 s); other errors
  fail at once. Then `collect` tries `feed_url_alternates[]` in order (https only); the first URL that fetches AND
  parses wins, and only when all fail does the outlet land in `feed_errors[]` (message lists every URL). Alternates:
  Independent `/rss`, `/news/world/europe/rss`; Times of Israel `/israel-and-the-region/feed/`, Feedburner copy (a
  different host). Whether GitHub's IPs get through is only visible in a scheduled run's collect table.
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
  (`id | outlet_id | published_at | headline | snippet`, one line each, sorted by outlet then time), wrapped in
  `<articles>…</articles>`. Both prompts state that headlines/snippets are untrusted data, never instructions. `_cell`
  strips `|` (column forgery), line breaks (row forgery) and any `<articles>` tag in feed text (delimiter forgery).
- **The model only proposes groups.** `stories.py` enforces everything else, deterministically: drop unknown ids;
  an article in two stories stays where there are more distinct outlets (tie → first listed); a story needs
  ≥3 **distinct** outlets (several articles from one outlet count once but all stay in `articles[]`); rank by distinct
  outlets ↓, distinct leans covered ↓, blocs covered ↓, earliest `published_at` ↑; keep the top 10; fewer than 5 → the
  stories that qualify plus a `meta.warnings[]` entry. `coverage.lean/bloc` count distinct outlets per tag (lean=null
  outlets count in bloc only); `blindspot.lean/bloc` is the single tag covering the story when all others are 0.
  Story `id` = 12-hex sha1 of the sorted article ids. Titles are capped at 90 chars in code.
- **Titles are grounded** (`guard.ground_title`, SEC-1): a model title stands only if one member headline shares ≥2
  content words with it and ≥2/3 of its content words appear in the story's headlines/snippets (all 37 live titles of
  14 Oct pass); a title with a URL/handle/instruction or failing that is replaced by the best-matching member headline
  and counted in `story.validation.dropped_by_reason` as `untrusted_text_title` / `title_ungrounded`.
- **Cost accounting** (`cost.py`): every billed *attempt* (input, output, cache read/write) × `config/pricing.yaml`
  → `RunCost`; written to `pipeline/out/runs/<date>.json`, copied into `meta.cost_usd`, printed as
  `grouping: N in / M out tokens → $x.xxxx`. A failed call is still recorded (it was billed), grouping included.
  With the refusal fallback, `message.model` is the model that served the call and top-level `usage` covers only that
  attempt; `llm.attempts_from_message` reads `usage.iterations` (a declined `message` entry on the requested model, then
  a `fallback_message` entry on the serving model) and each attempt is priced at its own model. `pricing.yaml` lists the
  fallback targets `claude-opus-5` and `claude-opus-4-8` ($5/$25, cache read $0.50, 5-min write $6.25). A model with no
  row is recorded with `usd: null`, a `RunCost.warnings` entry and a `meta.warnings` line: accounting never discards a
  paid run (code review M2).
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
- **Two sourced paragraphs across the story (16 Oct 2026)**: `summary` (what happened, ≤400 chars) and `conclusion`
  (what every side establishes, how the sides frame it differently, what stays contested; states the disagreement,
  never resolves it). Both are `Synthesis` (`models.py`: text ≤ `SYNTHESIS_TEXT_MAX_CHARS` 400 + sources), required in
  the output schema, validated by `validate._synthesis` under the same rules as a point (`unknown_id` / `empty_sources`
  / `untrusted_text`) and shipped as `null` when dropped or on a failed story. Schema: `$defs.synthesis`, story
  properties `summary` / `conclusion` (`anyOf` synthesis | null, not required: files before 16 Oct lack them; the app and
  `AnalysisResponse` default them to None, so the 14 Oct fixtures still replay). The app shows them in the "In brief"
  card at the top of a story (`in_brief_card.dart`: What happened · Across the sides · Where they disagree, the last
  listing contested claims and contradictions with rows that jump to their section, switching axis when needed).
  **Schema size**: structured outputs compile the schema to a grammar with an internal size limit; the inlined
  schema tipped over it ("The compiled grammar is too large", 400, run 38829982325) when the two paragraphs were
  added. `ANALYSIS_OUTPUT_SCHEMA` therefore defines the repeated shapes once under `$defs` (`ids`, `sourced`,
  `synthesis`, `quote`) and uses `$ref` (supported; descriptions do not count, duplicated structure does). An API 400
  is not a per-story failure: it aborts the run before anything is published (latest.json keeps the previous day),
  so any schema change gets one live `analyse` on a one-story stories.json (≈ $0.12) before it is pushed.
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
  | `untrusted_text` | a point text, claim, topic, contradiction side or kept quote carries a URL, an `@handle` or an instruction-shaped phrase (`guard.suspect_text`, SEC-1) |
  | `title_ungrounded` / `untrusted_text_title` | counted at grouping when the title was replaced (see Grouping); carried into the story's counts |

  A kept quote is stored as the outlet's exact text (the matched span of the headline/snippet, whitespace collapsed),
  never the model's copy, which could differ in case, quote style or dashes.
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
2. Add a row to `pipeline/config/outlets.yaml` with every field (see the header comment). The feed must be https. If
   its item links use a host other than `home_url`'s (e.g. dailymail.com for dailymail.co.uk), list it in `link_hosts`
   or those items are dropped as `link_off_domain`; never list a URL shortener. Choose `lean`
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
lib/features/story  StoryDetailView (body) + StoryDetailScreen (n of N, previous/next); widgets/ points (SideBlock, QuoteRow,
                    PointTile, ContestedClaimCard, ContradictionCard), source_pills (SourcePills, SourcesSheet), sources_list (SourceTile)
lib/features/{settings,purchases,ads}   theme mode, AdFreeController over StoreGateway, AdsService + AdBannerSlot
test/               fixtures (= assets/sample_digest.json), helpers/ (fakes, pumpSidesApp at 390×844), unit/, widget/
```

- **Seams, all overridden in `main()` and in tests**: `digestRepositoryProvider`, `settingsStoreProvider`,
  `storeGatewayProvider`, `adsServiceProvider` (default `DisabledAdsService`), `linkLauncherProvider`,
  `reconcileAtLaunchProvider`. Widget tests never touch a plugin; use `TestHarness`/`pumpSidesApp`.
- **Refresh policy**: cache first; revalidate on launch/resume when digest `date` < today (UTC) or fetched > 6 h
  ago; pull-to-refresh always fetches; conditional on ETag; a bad body never overwrites the cache; body decoded as UTF-8.
- **Integrity in the UI**: `Story.fromJson` strips unknown source ids and drops any point left unsourced; quotes need
  a resolvable article. `Story.validation` is parsed; `analysisUnavailable` (kept == 0 and every analysis list empty, i.e.
  the analysis failed or nothing survived) replaces the axis switch and every section with one "Analysis isn't
  available" notice: "None found" is only ever said about an analysis that ran (code review M3).
- **Digest parse off the UI isolate**: `parseDigest` is pure; `NetworkDigestRepository.defaultParser` is
  `parseDigestInBackground` (`compute`). Widget/controller tests pass `parse: parseDigestInline` because a real
  isolate's reply never arrives inside fake async. Any exception reading the cache is a miss (no endless spinner). Never render article text beyond headline + snippet; content copy lives in `Copy` and stays
  descriptive (never judges an outlet). Lean colours are violet/slate/orange, not red/blue (opposite meanings in UK/US).
  Story cards carry `StorySignals` chips (blindspots, "N contested claims", "N East–West contradictions", "Analysis
  unavailable"): counts of validated items, computed in the app, never a judgement.
- **Ads**: banner only in `bottomNavigationBar` of list/detail, hidden until a digest exists and the instant ad-free
  is owned. No ATT prompt: every request is `nonPersonalizedAds: true`, Google UMP gathers consent. Test IDs until
  publish (`AdConfig`, Info.plist `GADApplicationIdentifier`, manifest `APPLICATION_ID`). "Ad privacy options" in
  Settings waits for `AdsService.consentGathered` (UMP update succeeded) and only then asks whether it is required.
  The merged Privacy Sandbox permissions (`ACCESS_ADSERVICES_*`) are stripped in the manifest (SEC-6).
- **IAP**: outcomes only arrive on `purchaseStream`; Play reports a cancel/failed purchase with an EMPTY product id, which
  is routed to the purchase in flight (and ignored when none is); busy has a 75 s ceiling; entitlement persisted before
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
- **Story page = compare by dimension (UI redesign, 16 Oct 2026; screens in `docs/screenshots/redesign/`).** No
  per-side tabs: "Headlines, side by side" and "What each side emphasises" show every lean/bloc present at once, each
  as a `SideBlock` (colour rail + side name + outlet count); the shared sections follow (agreed, left out, contested,
  opinion / contradictions), then Sources. The body is one `SingleChildScrollView` column (not a lazy list) so the jump
  bar's `GlobalKey` anchors are always laid out and `Scrollable.ensureVisible` works; `find.text` therefore sees every
  section from the start in tests. A quote is a `QuoteRow` that opens its article; a point is `PointTile` = text +
  `SourcePills` (one pill per outlet, ≤3 then "+N more", lean-coloured dot) whose tap opens `SourcesSheet` (every
  article, tapped outlet first, rows open the browser). Jump chips are keyed `jump-<section>`; the bar scrolls
  horizontally, so tests `ensureVisible` a chip before tapping it.
- Axis per story lives in `storyViewProvider` (autoDispose family by story id; `axis == null` means "use the
  route's `?axis=`"), not widget state — a layout swap re-subscribes in the same frame so the reader's place survives.
- Columns: `StoryDetailView.columnsFit` — only at `LayoutSize.expanded` and only when every column gets ≥ 280 dp ×
  text scale; else the sides stay stacked. Each comparison section is its own `PerspectiveColumns` row (so
  `PerspectiveColumns.keyFor('left')` matches twice on a story with both sections). Contradiction rows
  (`ContradictionCard(sideBySide:)`) drop the card inset so they align with the bloc columns.
- Breakpoints: `LayoutSize.mediumMin` = 744 dp (iPad mini portrait, so every iPad is master-detail in both
  orientations; large phones in landscape too), `expandedMin` = 1100 dp. List pane 360 dp, 320 dp below 900 dp
  (`MasterDetailScreen.listPaneWidthFor`) so the detail pane stays ≥ 380 dp at 744.
- Tablet tests: `test/widget/tablet_layout_test.dart` (sizes in dp; pumpSidesApp renders at 3×).

## Deployment (phase 6)

- **Files**: `.github/workflows/daily.yml` (the daily job), `.github/workflows/ci.yml` (pytest + flutter on push/PR to
  main), `pipeline/sides_pipeline/publish.py` + `cli publish` (pure file copy, unit-tested in `tests/test_publish.py`),
  `scripts/publish_site.sh` (clone or orphan-create `gh-pages` → `publish` → commit `Digest <date>` → push; env
  `SITE_DIR`, `SITE_REMOTE_URL`, `PYTHON`, `SUMMARY_OUT`, git's `GIT_AUTHOR_*`/`GIT_COMMITTER_*`).
- **gh-pages layout** (branch `gh-pages`, served at `https://mksoft-ltd.github.io/sides/`, Pages source branch
  `gh-pages` path `/`, legacy build type, HTTPS enforced): `digest/latest.json` (byte-identical to the dated file),
  `digest/YYYY-MM-DD.json`, `digest/index.json` (plain JSON list, newest first, `{date, generated_at, stories, cost_usd}`;
  rebuilt from every dated file on the site and merged with the old index so a hand-pruned day keeps its row; a re-run of
  the same date replaces that day's file and row), `runs/YYYY-MM-DD.json` (cost report), `privacy_policy.html` (copied
  from the repo root when it exists — house-facts §5; the publish step logs and carries on when it does not),
  `.nojekyll`, `index.html`. The app's `AppConfig.digestUrl` points at `digest/latest.json`.
- **Per-run cost report (spec requirement)**: `publish --summary-out` renders `RunCost.summary_lines()` (the
  `grouping:` / `analysis:` / `total:` lines) and the top-stories table; the workflow writes it to
  `$GITHUB_STEP_SUMMARY`, so the cost is the first thing on each run's summary page. The same numbers are
  `runs/<date>.json` on the site and `pipeline/out/runs/<date>.json` inside the run's artifact (14-day retention).
- **daily.yml mechanics**: `schedule: "0 6 * * *"` + `workflow_dispatch` inputs `through` (collect | group | analyse,
  default analyse) and `dry_run` (true ⇒ collect only). The "Resolve stages" step turns those into one value;
  publishing runs only when it is `analyse` (group/collect runs leave the site untouched).
  **Two jobs (SEC-3, fix round 2)**: `build` holds `ANTHROPIC_API_KEY`, has `permissions: contents: read` and checks out
  with `persist-credentials: false`; it installs `pipeline/requirements.lock` with `pip --require-hashes --no-deps`
  (the package is not installed; `PYTHONPATH=pipeline`), runs the pipeline, stages the site read-only
  (`publish_site.sh --stage-only`, which also writes the step summary) and uploads it as artifact `site-<run_id>`
  (1 day, no hidden files) plus `pipeline-out-<run_id>` (14 days). `publish` (`needs: build`) has
  `contents: write` + `actions: write`, no secret and no Python deps: it downloads the site
  (`actions/download-artifact@v6`), runs `publish_site.sh --push-only DIR` (clone gh-pages, mirror DIR over it, commit,
  push) and the keepalive. The artifact is untrusted (SEC-9): `--push-only` accepts only `digest/*.json`,
  `runs/*.json`, `index.html`, `privacy_policy.html` (and ignores `.nojekyll`, which it writes itself); any `.git*`,
  symlink, nested dir or other file aborts before git runs. Every git call in the script and the keepalive runs with
  `-c core.hooksPath=/dev/null -c core.fsmonitor=false`; the publish checkout has `persist-credentials: false` and the
  token is given only to the pushes (`tests/test_publish_site_script.py` drives the real script against local repos). On a dry run or a run stopping before analyse, `publish` still runs green and writes
  "nothing to publish" to the summary. `tests/test_workflows.py` pins this shape. `concurrency: daily-digest`
  (no cancel), build `timeout-minutes: 30` (a full run is ~4 min). Actions pinned to majors: `actions/checkout@v5`,
  `actions/setup-python@v6`, `actions/upload-artifact@v6` / `download-artifact@v6` (Node 24),
  `subosito/flutter-action@v2` with `flutter-version: 3.44.4`.
- **Dependency locks**: regenerate both together after changing `pyproject.toml` (uv in any throwaway venv):
  `uv pip compile pipeline/pyproject.toml [--extra dev] --generate-hashes --python-version 3.12 --python-platform
  x86_64-unknown-linux-gnu --no-header -o pipeline/requirements[-dev].lock`. CI (`ci.yml`) installs
  `requirements-dev.lock` the same way. Locally `pip install -e "pipeline[dev]"` still works.
  Pushes made with `GITHUB_TOKEN` do not trigger other workflows, so the gh-pages commit and the keepalive commit never
  start CI. Pages was auto-enabled by GitHub the moment the `gh-pages` branch was pushed (the POST
  `/repos/mksoft-ltd/sides/pages` call returned 409 "already enabled"); `gh api repos/mksoft-ltd/sides/pages` shows the config.
- **Sleep guard**: GitHub's rule (docs, "Events that trigger workflows → schedule", checked 15 Oct 2026): "In a public
  repository, scheduled workflows are automatically disabled when no repository activity has occurred in 60 days."
  What counts as activity is not documented; the community keepalive actions found that merely toggling the workflow
  via the API did not reliably reset the deadline, and all converged on committing to the **default branch**. Our daily
  commit lands on `gh-pages`, not `main`, so it may not count. Mitigation, in the daily run's "Keep the schedule alive"
  step (scheduled runs only): (1) `gh api -X PUT .../actions/workflows/daily.yml/enable` (idempotent; also undoes a
  disable if one happened); (2) if the `main` HEAD commit is ≥ 45 days old, write today's date to `.github/keepalive`
  and push it to `main` as `github-actions[bot]`. Zero third-party actions, zero cost, at most one tiny commit every
  45 days. If the schedule ever does stop: `gh workflow enable daily.yml` and check the Actions tab banner.
- **When a run fails** (red run + GitHub's failure email): open the run → the failing step's log. `collect` exits 1
  only when no articles were collected at all (single feed failures are warnings; the run on 14 Oct saw Independent 429
  and Times of Israel 403 and carried on). `group` exits 2 on refusal/truncation — the cost report is still written and
  uploaded in the artifact, nothing is published, latest.json keeps the previous day. `analyse` exits 1 only when every
  story failed. A publish failure (push rejected) is a race with another run — the concurrency group should make that
  impossible; re-run the job. Re-running the same day is safe: the dated file and index row are replaced. To check the
  secret is still valid without paying for a full run: `gh workflow run daily.yml -f through=group`.
- **First workflow run (run 38655525802, 14 Oct 2026 23:40 UTC, 4 min 11 s, green)**: 2 feed errors, 52 raw stories →
  10 kept; grouping 77,968 in / 10,640 out → $0.5247; analysis 10 calls 50,795 in / 30,779 out → $0.8188; total
  $1.3434 over 11 calls. Because it ran before midnight UTC its date was 2026-10-14 and it replaced the digest of the
  same date published from the local run; the first index merge of two days happens with the 06:00 UTC run on 15 Oct.
