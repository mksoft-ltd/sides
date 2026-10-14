# Sides: The News, Every Angle — Product spec

Publisher: Froggy Eye Ltd · Bundle/package `com.froggyeye.sides` · iOS + Android, phone (tablet layout: phase 5).
Approved plan: `~/.claude/plans/curried-herding-yao.md`. Data contract: `schema/digest.schema.json`.

## Summary

Once a day a central pipeline (`pipeline/`) collects headlines and ≤200-character feed summaries from ~29 English-language outlets tagged by political lean (left / centre / right), region and bloc (West / East), groups them into the day's top 5–10 stories (≥3 distinct outlets each), and analyses how each side frames each story. Every analytical point cites the articles it rests on. The app downloads that one public JSON file, caches it for offline reading, and links out to the original articles. It never shows article text beyond headline + snippet and never judges an outlet.

## Target users

- News readers who want to see how the same story is told across the political spectrum (UK/US).
- Readers interested in how Western and Eastern outlets differ on international stories.
- Students, teachers and journalists checking framing and sourcing quickly.

## Features

**MVP (phase 4, built)**
- Digest list: rank, title, outlet count, proportional coverage bars (Left/Centre/Right and West/East) with spoken labels, blindspot chips ("Only left-leaning outlets covered this", "Only Western outlets covered this"), generated date and "Last updated" line, pull-to-refresh.
- Story detail: coverage expanded (with a note when unrated outlets count only on the West/East axis), axis switch "Political lean" | "West / East".
  - Lean: tabs only for leans present; headline-wording quotes labelled `headline` / `snippet` with the outlet; emphasis points; "What all sources agree on"; "What each side leaves out"; "Contested claims"; "Opinion & analysis" in a separate tinted panel.
  - West / East: West and East tabs (blocs present); "East–West contradictions" as West/East pairs, or "No contradictions found in today's coverage".
  - Sources: every article with outlet, lean/bloc/region tags, a visible "state media" tag for state-controlled outlets, headline and link.
  - Every point shows its sources as chips "Outlet — headline" that open the original article in the external browser.
- Offline: cached digest shown instantly; revalidated on launch/resume when the digest date is before today (UTC) or it was fetched more than 6 h ago; conditional GET with `If-None-Match`; offline-with-cache note; offline-without-cache empty state with Retry.
- Settings/About: theme (System/Light/Dark), text-size note (follows device up to 200%), ad-free purchase + restore, Google UMP "Ad privacy options" where required, how it works, outlets and rating basis, privacy policy, © 2026 Froggy Eye Ltd.
- Monetisation: AdMob banner at the bottom of the list and story screens (never inside sourced content, hidden until a digest loads), one-time non-consumable `com.froggyeye.sides.adfree` removes ads instantly.

**Later**
- Phase 5: tablet master-detail (≥840 dp) and side-by-side perspective columns (≥1100 dp). Extension points: `LayoutSize`, `DigestListView`, `StoryDetailView`, `/story/:id?axis=bloc`.
- Phase 6: live digest URL via GitHub Actions + Pages.
- Archive of past days (`digest/index.json`), story search, share a story link.

## Screen map

```
/                      Digest list ──tap story──► /story/:id   (Story detail; ?axis=bloc opens West / East)
  └─ settings icon ──► /settings ──► /settings/outlets  (Outlets and ratings)
```

## Data model (app side, `lib/features/digest/domain/digest.dart`)

`Digest {schemaVersion, generatedAt, date, meta, outlets[], stories[]}` · `Outlet {id, name, lean?, region, bloc, ownership, country, homeUrl, ratingBasis}` · `Story {id, title, rank, outletCount, coverage, blindspot, articles[], agreedFacts[], framingByLean[], omissions[], contestedClaims[], opinion[], framingByBloc[], contradictions[]}` · `Article {id, outletId, headline, snippet, url, publishedAt}` · `SourcedPoint {text, sources[]}` · `HeadlineQuote {articleId, quote, field: headline|snippet}` · `Contradiction {topic, west, east}`.
Integrity on read: unknown source ids are stripped and any point left without a source is dropped, so the UI cannot render an unsourced claim.

Local storage: `<documents>/digest/latest.json` + `latest.meta.json` (`fetched_at`, `etag`); SharedPreferences keys `theme_mode`, `ad_free_owned`. No accounts, no backend, no analytics or crash SDKs.

## Permissions

| Platform | Permission | Why |
|---|---|---|
| Android | `INTERNET` | Download the daily digest; load ads; billing. |
| Android | `com.google.android.gms.permission.AD_ID` | Required by Google Mobile Ads on Android 13+ (frequency capping, fraud prevention). Requests are non-personalised. |
| Android (merged from the Mobile Ads SDK) | `ACCESS_NETWORK_STATE`, `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION`, `ACCESS_ADSERVICES_TOPICS`, `WAKE_LOCK`, `FOREGROUND_SERVICE` | Added by `play-services-ads`; the app itself uses none directly. Security/compliance stages may decide to strip the Privacy Sandbox ones with `tools:node="remove"`. |
| Android (merged from Billing) | `com.android.vending.BILLING` | Ad-free in-app purchase. |
| iOS | none requested at runtime | No ATT prompt and no `NSUserTrackingUsageDescription`: Sides does not track; all ad requests are non-personalised (house convention). `SKAdNetworkItems` (Google's list, 50 entries) and `GADApplicationIdentifier` are in Info.plist. `ITSAppUsesNonExemptEncryption = false`. |

Privacy declarations must reflect AdMob (advertising data, device identifiers on Android, not used for tracking) rather than "No data collected".

## Release-stage to-dos owned elsewhere

- AdMob: create the app + banner units, then replace the test IDs in `lib/core/config/ad_config.dart`, `ios/Runner/Info.plist` (`GADApplicationIdentifier`) and `AndroidManifest.xml` (`APPLICATION_ID`) and set `AdConfig.liveIdsConfigured = true`.
- Create `com.froggyeye.sides.adfree` in both consoles.
- Android release keystore (house-facts §7); app icon (design stage).

## Screenshot mode

`--dart-define=SCREENSHOT_MODE=true` loads the bundled sample digest (`assets/sample_digest.json`, the real 14 Oct 2026 run) with ads off; `--dart-define=SCREENSHOT_ROUTE=/story/<id>?axis=bloc` opens a route at launch. Both are ignored in release builds.
