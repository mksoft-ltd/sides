# Code review — Sides: The News, Every Angle

Stage 4a (code-review gate) · 2026-10-15 · reviewer: mobile-code-reviewer · reviewed at `51860ab` (main)

Scope: the Flutter app (`lib/`, `test/`, `integration_test/`, Android/iOS native config) and the Python pipeline
(`pipeline/sides_pipeline/`, `.github/workflows/`, `scripts/`). Gates re-run by the reviewer at `51860ab`:
`flutter analyze` clean · `flutter test` 214 passed · `pytest` 138 passed.

## CODE QUALITY SCORE

**8 / 10.** The code is clean and well layered, and its comments explain why. Every plugin sits behind a seam
(repository, cache, remote, store gateway, ads service, launcher, settings store). Integrity is enforced twice,
in the pipeline validator and on read. The three Major findings are in edge paths the tests do not model:
how the Android billing plugin reports a cancel, a refusal fallback served by another model, and a story whose
analysis failed.

## PERFORMANCE RISK LEVEL

**Low.** The list is a builder, rebuilds are narrowed with `select`, and the detail page is one short `ListView`.
The digest is cached and revalidated with ETags. The only hot spot is a synchronous `jsonDecode` of the digest
on the UI isolate (Minor m5).

## What is done well

- **Cache and refresh policy.** The policy is pure and unit-tested. Writes go through a temp file and a rename. A bad
  body never overwrites a good cache. A 304 with no cached copy is treated as a failure. The body is decoded as UTF-8
  whatever charset Pages sends. Concurrent refreshes share one request, and a thrown error still clears `refreshing`
  (F1 fix verified).
- **On-read integrity in `Story.fromJson`.** Unknown ids are stripped, unsourced points are dropped, quotes need a
  resolvable article, and contested claims and contradictions need both sides sourced. The widgets check again.
- **Pipeline validator.** The validator applies its rules in a fixed order and records why each item was dropped.
  The model never sets the quote `field`. Coverage and blindspot are computed in code.
- **Money path.** The purchase listener starts at launch. The entitlement is persisted before `completePurchase`.
  A pending Play purchase is not granted. A silent restore runs on Play at launch and resume. Busy state has a ceiling,
  and notices carry a serial number.
- **Ads.** Banners appear only in `bottomNavigationBar` or under the detail pane, never inside sourced content. They
  are hidden until a digest exists and disappear when ad-free is owned. Debug builds always request test units.
- **Adaptive layout.** Layout follows the route. Axis and tab live in an autoDispose family keyed by story id, so the
  reader's place survives rotation. Columns fall back to tabs when the text scale needs the width.

## CODE QUALITY ISSUES

### M1 — Android: a cancelled or failed purchase is ignored, so the button spins for 75 s with no notice
- **Location:** `lib/features/purchases/presentation/ad_free_controller.dart:213-216`. The same filter makes the
  `itemAlreadyOwned` branch at `:247-251` unreachable on Android.
- **Severity:** Major
- **Failure scenario:** On Android the user taps "Remove ads", then backs out of the Play sheet. `in_app_purchase_android`
  0.5.4 has no purchase to attach to that result, so it emits a `PurchaseDetails` with `productID: ''` and
  `status: canceled` (`in_app_purchase_android_platform.dart:298-313`, read in the pub cache). Every non-OK billing
  result does the same with `status: error`. The controller sees a product id that is not the ad-free id, skips the
  event and `continue`s. `busy` stays true, so the button reads "Working…" with Buy and Restore disabled until the
  75 s ceiling fires. No "cancelled" or "failed" notice is ever shown. The `itemAlreadyOwned` recovery can never run
  on Android for the same reason. The unit test passes only because it emits the cancel with the real product id
  (`test/unit/ad_free_controller_test.dart:34`, `:112`), which is iOS behaviour, not Play behaviour.
- **Why it matters:** This is the most common purchase outcome on the platform that has never had an order. It is
  the "permanently spinning button" the code's own comment warns reads as a broken app in review.
- **Fix:** Treat an event whose `productID` is empty as belonging to the purchase in flight. Route it through the
  `canceled`/`error` handling, including the `itemAlreadyOwned` check, instead of `continue`. Keep the
  complete-and-skip path only for events with a non-empty foreign product id. Add tests that emit
  `PurchaseDetails(productID: '', status: canceled)` and `(productID: '', status: error, error: IAPError(message: 'BillingResponse.itemAlreadyOwned'))`
  after `buy()`. Assert that `busy` is false and the notice is set well before `busyCeiling`, and that a restore was
  requested in the second case. Both tests fail against the current code.

### M2 — A refusal fallback crashes the paid run: the fallback model is not in `pricing.yaml`
- **Location:** `pipeline/sides_pipeline/cost.py:89-92` (raises `PricingError`). Callers: `group.py:229` and
  `analyse.py:404-406`. Uncaught at `cli.py:107-114`, which catches only `GroupingError`, and at `cli.py:194-205`.
  The model name comes from `llm.py:77`.
- **Severity:** Major
- **Failure scenario:** Both calls opt into `fallbacks: "default"`. When a safety classifier declines an Opus 5.5
  request, the API re-runs it server-side on Claude Opus 5 or Claude Opus 4.8, and `message.model` names the model that
  answered (claude-api skill, refusal section). `run_structured` returns that name and `cost.record(stage, result.model, …)`
  looks it up. `pricing.yaml` lists only `claude-opus-5-5`, `claude-sonnet-5-5` and `claude-haiku-5-5`, so a
  `PricingError` is raised (reproduced below). That error is a `KeyError`, which nothing catches:
  - **Grouping:** the run dies after the call was paid for, with a traceback. No `stories.json` and no cost report are
    written.
  - **Analysis:** costs are recorded only after every story has finished, so one fallback on one story throws away all
    10 paid analyses. `digest.json` and `runs/<date>.json` are never written and nothing is published.

  A daily news digest about wars, attacks and outbreaks is exactly the content that trips classifiers, and the same
  running story can trip them several days in a row. The fallback, which exists to recover these requests, turns a
  recoverable event into a lost and unaccounted day.

  Reproduction:
  ```
  RunCost().record('analysis', 'claude-opus-5', Usage(1000, 500))
  -> PricingError "no price for model 'claude-opus-5' in pricing.yaml"   (same for claude-opus-4-8)
  ```
- **Second defect, same path:** `Usage.from_response_usage(message.usage)` reads only the top-level `usage`. With
  fallbacks, that covers only the attempt that produced the message. Per-attempt billing is in `usage.iterations`, so a
  declined attempt billed before the fallback is missing from `cost_usd`. Separately, `analyse_one` keeps one `model`
  per story, so every attempt is priced at the last attempt's model.
- **Fix:**
  1. Add `claude-opus-5` and `claude-opus-4-8` rows to `pricing.yaml`, taking the rates from the pricing page. The skill
     table lists $5 / $25 per MTok for input and output; the cache rates need checking.
  2. Make a missing price non-fatal. Record the call priced at the requested model, mark it `unpriced`, and log a
     warning. Accounting must never discard a paid result.
  3. Price each entry of `usage.iterations` at its own model when the field is present.
  4. Add a test where the stand-in client returns `model="claude-opus-5"` from a grouping call and from one analysis
     call. Assert that the run completes, the digest is written, and the cost report holds every call.

### M3 — A story whose analysis failed is shown as "None found" and "No contradictions found"
- **Location:** `pipeline/sides_pipeline/digest.py:46-54` ships the story with empty arrays and records the failure
  only in `meta.warnings`. `lib/features/digest/domain/digest.dart` parses neither `meta.warnings` nor
  `story.validation`. `lib/features/story/presentation/widgets/story_detail_view.dart:186, 201, 209, 227, 237, 294,
  304-308` then render `Copy.noneFound` and `Copy.noContradictions`.
- **Severity:** Major (product integrity)
- **Failure scenario:** One story's analysis call is refused or truncated twice. This is the designed per-story
  failure path, and it becomes the normal outcome for a refused story once M2 is fixed. The digest still publishes
  because exit 1 needs every story to fail. In the app every section of that story reads "None found in today's
  coverage." The West / East view states "No contradictions found in today's coverage". Both are factual claims about an
  analysis that never ran. The spec allows "none found" only when the analysis ran and found nothing.
- **Fix:** App-side, with no schema change: parse the story's `validation` object, which the schema already requires.
  When `kept == 0` and every analysis array is empty, replace the perspective and analysis sections with one notice:
  "Analysis isn't available for this story today. Its sources are listed below." Keep coverage, blindspot and
  sources. The same notice also covers the case where the validator dropped everything. Add a widget test with a fixture
  story whose arrays are empty and `validation: {kept: 0, dropped_by_reason: {}}`. Assert that neither
  `Copy.noneFound` nor `Copy.noContradictions` appears on either axis.

### Minor

| # | Finding | Location | Fix |
|---|---|---|---|
| m1 | The on-read check does not re-verify side membership: a framing quote's article in that lean or bloc, contradiction sides in the right bloc, an omission not citing the omitter. It also does not re-check that a quote is a substring of the headline or snippet. The class comment says the UI "can never render an unsourced claim even if a bad file slipped past" the validator, which is stronger than the code. The pipeline enforces all of this, so this is defence in depth only. | `lib/features/digest/domain/digest.dart:5-10`, `388-394`, `448-454` | Add the cheap membership and substring checks on read, or narrow the comment. |
| m2 | A kept quote stores the model's text (`normalise_ws(q.quote)`), not the source span. The match ignores case, quote style and dashes, so the displayed "verbatim" quote can differ from the outlet's headline, for example "PM Slams" against "PM slams". | `pipeline/sides_pipeline/validate.py:150` | Store the matched slice of the original headline or snippet. |
| m3 | An analysis item whose text is blank after whitespace normalisation is kept and shown as "…". The response models have no `min_length`. | `validate.py:87-92`, `analyse.py:200-210` | Drop it under a new `empty_text` reason. |
| m4 | If `loadCached()` throws anything other than the exceptions the parser catches, for example an asset failure in the bundled repository, `initialising` stays true and the screen shows an endless spinner with no Retry. | `lib/features/digest/presentation/providers/digest_controller.dart:68-76` | Wrap the call in try/finally and set `initialising: false` on every path, as `_refresh` already does. |
| m5 | A digest of about 150 KB is decoded with `jsonDecode` and parsed into models on the UI isolate at launch and on every 200 response. The cache read also uses `existsSync`. Expect a jank frame of roughly 10 ms on low-end Android. | `lib/features/digest/data/digest_repository.dart:187-203`, `digest_cache.dart:81` | Run `_tryParse` with `Isolate.run`; the models are plain immutable data. |
| m6 | The "Ad privacy options" tile asks UMP for its status before consent has been gathered. Consent is gathered only when the first banner loads, which is after a digest exists. A first-launch EEA user who opens Settings early never sees the tile in that session. | `settings_screen.dart:197-199`, `ads_service.dart:48-60` | Call `initialize()` once at launch after the first frame, and await it before reading the status. |
| m7 | After `onAdFailedToLoad` a banner never retries until the width changes, so one no-fill costs the rest of the session on that screen. | `ads_service.dart:156-160` | Retry with backoff, for example 30 s, then 60 s, capped. |
| m8 | The pipeline's dependencies are lower-bound only (`anthropic>=1.14` and others) and there is no lockfile. The paid daily job uses beta parameters, so an SDK major release can break it overnight. | `pipeline/pyproject.toml:10-17`, `daily.yml` "Install pipeline" | Pin upper bounds, or install from a hashed requirements lock in `daily.yml`. |
| m9 | Undated feed items are stamped with the fetch time, which bypasses the 36 h window. A feed that carries old undated items feeds them into today's grouping. | `pipeline/sides_pipeline/collect.py:89-94` | Cap undated items per outlet, or drop them when the feed has dated items. |
| m10 | `canonical_url` strips `source`, `src`, `ref`, `partner`, `sh` and `ito`. On some sites these change the page, and the canonical URL is the published link. | `pipeline/sides_pipeline/text.py:16-24` | Strip only known tracking parameters (`utm_*`, `fbclid` and similar), or keep the original link for `url` and use the canonical form only as the dedupe key. |
| m11 | Lean columns need about 1265 dp of window: 3 × 280 + 2 × 16 + 32 padding + a 361 dp list pane. An 11-inch iPad Pro in landscape at 1194 dp stays on tabs, while the plan says columns from 1100 dp. Bloc columns do appear from 1100 dp. The check is deliberate and tested. | `story_detail_view.dart:38-50` | Founder or design call. Either accept it and note it in `PRODUCT_SPEC.md`, or narrow the list pane at the expanded size. |

### Nit
- `_onPurchases` is an `async` stream callback, so two batches can interleave across `await setBool`. This is benign
  today because the operations are idempotent. `ad_free_controller.dart:211`.
- A framing entry left empty by on-read stripping renders a panel with two "None found" lines. Filter it out in
  `Story.fromJson`.
- Duplicate-membership strength in `stories.py:148-160` is computed on the pre-resolution id sets, so the result
  depends on order. It is deterministic, but the docstring implies otherwise.
- `publish_site.sh:29-35`: any failed clone, including network or auth failures, falls through to "creating it as an
  orphan". The non-force push is then rejected, so no data is lost, but the log points at the wrong cause.
- `pricing.yaml` does not model Haiku 5.5's higher rate for prompts above 100K tokens. The grouping prompt is about
  80K tokens, so a later downgrade could be under-reported.
- A phone reader on a story page sees "Story not available" once a resume refresh brings a new day's digest, because
  story ids change. The behaviour is acceptable. A "Back to today's stories" action would help.

## PERFORMANCE ISSUES

- The main-isolate JSON parse is the only measurable cost (m5).
- `DigestListView` watches the whole `DigestState`, so a refresh rebuilds the header and the visible cards. The list
  is at most about 11 rows, so the cost is negligible.
- `StoryDetailView` builds every section eagerly in a `ListView(children:)`. A story has a few dozen widgets, so this
  is fine. Move to slivers only if stories grow past about 50 sources.
- The ads SDK starts lazily on the first banner, so launch is not blocked. That is good, but it is also the cause of m6.

## RECOMMENDED IMPROVEMENTS (priority order)

1. **M2.** Price the fallback models, make a missing price non-fatal, and sum `usage.iterations`. This protects every
   paid run.
2. **M1.** Route empty-`productID` events to the purchase in flight, with tests that use the real Play shape.
3. **M3.** Show "Analysis unavailable" for a story with no analysis, never "None found".
4. m4 and m5, which are small and contained.
5. m6, m7 and m8, then the rest as time allows.

Before and after for M1:
```dart
// before
if (p.productID != AppConfig.adFreeProductId) {
  if (p.pendingCompletePurchase) await _complete(p);
  continue;
}
// after: Play reports cancel/error with no purchase attached, i.e. productID ''
final bool ours = p.productID == AppConfig.adFreeProductId || p.productID.isEmpty;
if (!ours) {
  if (p.pendingCompletePurchase) await _complete(p);
  continue;
}
```

## ARCHITECTURE IMPROVEMENTS

No structural change is needed. The feature-first layout, the injected seams and the pure policy objects suit this
size of app. One contract gap is worth closing: the app cannot tell "the analysis found nothing" from "the analysis did
not run". M3 can be fixed app-side from `validation`. An explicit optional per-story `analysis_status` in
`schema/digest.schema.json` would make the contract self-describing. Add it as an optional field so schema version 1
readers keep working.

## Re-review notes for the fix round

- Each Major fix must be re-verified against the real plugin or API shapes, not against the fixer's fakes. For M1,
  that means a fake that emits `productID: ''`. For M2, a stand-in response whose `model` differs from the requested
  model and that carries `usage.iterations`.
- The M3 widget test must assert that `Copy.noneFound` and `Copy.noContradictions` are absent. Asserting only that the
  new notice is present would not catch a regression.

## Re-verification — 2026-10-15 (fix round 2: 99fec96, 2caff21, 136d51d)

The original reviewer re-verified at `44bda98`, not from the fixer's notes. Gates re-run: `flutter analyze` clean ·
`flutter test` 227 passed · `pytest` 179 passed · CI on main green. Each Major fix was reverted in a scratch worktree
to confirm its new tests fail against the original defect.

| Finding | Status | Evidence |
|---|---|---|
| **M1** Android id-less cancel/error | **Resolved** | `_isOurs` binds an event with an empty product id and status `canceled`/`error` to a purchase in flight (`_purchasing`, cleared by `_finish` and by the busy ceiling). A stray id-less event with no purchase in flight is ignored. The new tests build the exact 0.5.4 shape (`productID: ''`, `IAPError.message` = response code). Restoring the old product-id filter fails 3 tests: cancel, error and itemAlreadyOwned. |
| **M2** Fallback model unpriced, run lost | **Resolved** | `claude-opus-5` and `claude-opus-4-8` are priced at $5 / $25 input/output, matching the claude-api skill table. `RunCost.record` no longer raises: an unpriced model is recorded with `usd: null` and the warning reaches `meta.warnings`. `attempts_from_message` costs every `usage.iterations` entry. Declined attempts are `message` entries on the requested model and the serving attempt is `fallback_message`, which matches the skill's refusal-fallback section. A refused grouping call is still costed before re-raising. The total for a grouping fallback was checked by hand at $0.0285 and matched. Reverting to a raising recorder fails the unpriced-model test. Reverting to top-level-only usage fails 3 tests. |
| **M3** Failed analysis shown as "None found" | **Resolved** | `Story.analysisUnavailable` is true when `validation.kept == 0` and every analysis list is empty. The story page then replaces the axis switch and all sections with "Analysis isn't available for this story today. Its sources are listed below." On both axes the test asserts that `Copy.noneFound`, `Copy.noContradictions` and the no-contradictions key are absent. A control test keeps "None found" for an analysed story. Forcing the getter to `false` fails the tests. |
| m2 exact quote span | Resolved | `source_span` maps the folded match back to the original text. Checked independently: a quote matched case-insensitively against `PM Slams “plan” — again` is stored with the outlet's own casing, curly quotes and dash. |
| m4 cache-read exception | Resolved | `_start` treats any exception from `loadCached` as a cache miss, so the first screen can no longer spin forever. |
| m5 off-thread parse | Resolved | `NetworkDigestRepository` parses through `compute(parseDigest, …)` by default, and widget tests inject the inline parser. The cache existence check is now async. |
| m6 ad-privacy tile before consent | Resolved | The tile awaits `consentGathered`, which completes from the UMP callbacks, before asking for the requirement status. Settings tests cover before and after consent. |
| m8 unpinned pipeline dependencies | Resolved | `daily.yml` and `ci.yml` install from hashed lockfiles with `--require-hashes`. |
| m1, m3, m7, m9–m11, Nits | Open, non-blocking | Not taken in this round. |

**Residual observations (Minor, non-blocking):**
- **R1.** The itemAlreadyOwned path is reachable when Play reports the result on the purchase stream. If
  `launchBillingFlow` instead returns non-OK synchronously, `buy()` shows "failed" and clears `_purchasing` first, so a
  later id-less event is ignored. Restore still works, and the launch reconcile normally grants an owner before Buy is
  shown. Not verified on a device.
- **R2.** Per-iteration token fields are read with the same names as top-level `usage`. A missing field would cost
  that attempt $0 rather than crash. An attempt declined before any output may not be billed, so counting it can
  over-report slightly. That is the conservative direction.
- **R3.** `analysisUnavailable` keys on `kept == 0`. A story whose kept items were all stripped on read would still say
  "None found". The pipeline's validator makes that unreachable today.
- **R4.** The new `untrusted_text` rule (SEC-1) drops model-written text with domain-like tokens, such as a quote
  containing "X.com", or with phrases like "all outlets agree". This costs content, never sourcing. It is owned by
  the security audit.
- **R5.** An ungrounded or suspect story title is replaced by one member outlet's headline, shown as the story title
  without attribution. The live calibration says this is rare (37 of 37 titles passed). Preferring a centre or
  public-service outlet's headline would keep it neutral.

No new Critical or Major issue was introduced by the fix round.

Verdict: PASS
