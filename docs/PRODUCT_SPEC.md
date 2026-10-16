# Sides: The News, Every Angle — Product spec

Publisher: Froggy Eye Ltd · Bundle/package `com.froggyeye.sides` · iOS + Android, phone and tablet (iPad: all four orientations, device family 1,2).
Approved plan: `~/.claude/plans/curried-herding-yao.md`. Data contract: `schema/digest.schema.json`.

## Summary

Once a day a central pipeline (`pipeline/`) collects headlines and ≤200-character feed summaries from ~29 English-language outlets tagged by political lean (left / centre / right), region and bloc (West / East), groups them into the day's top 5–10 stories (≥3 distinct outlets each), and analyses how each side frames each story. Every analytical point cites the articles it rests on. The app downloads that one public JSON file, caches it for offline reading, and links out to the original articles. It never shows article text beyond headline + snippet and never judges an outlet.

## Target users

- News readers who want to see how the same story is told across the political spectrum (UK/US).
- Readers interested in how Western and Eastern outlets differ on international stories.
- Students, teachers and journalists checking framing and sourcing quickly.

## Features

**MVP (phase 4, built)**
- **Search** (16 Oct 2026, build 9): a Search tab. Typing a topic searches today's digest and the last 14 days of the archive on the device (archive days are downloaded once and cached; offline, the cached days are searched) and lists the matching stories newest first with their date; a hit opens the full story page (archive stories keep their own previous / next). Under the results, "Compare today's coverage of this topic" asks the topic service for an on-demand comparison of today's headlines on those words: three or more outlets are needed, the first request takes up to a minute, the result is cached for 24 hours and shared with other readers, and the panel explains no_match, the daily budget being spent, and the hourly limit. The words typed are sent to the service (privacy policy).
- **Front page** (16 Oct 2026, build 8, `docs/screenshots/redesign/13–15`): the phone home is a news-app shell with bottom tabs Today · By side · Outlets. Today = the date and "Last updated" line, lens chips (All, Contested, Blindspots), the lead story on the dark brand plate (rank, "TOP STORY · N outlets", headline, the sourced summary, bars, outlet avatars, signal chips, "Compare coverage"), a horizontal "Top stories" strip of stories 2–4, then "More of today's stories" as rows (title, outlet count, signal chips, bars at the right). By side = "Today, side by side": one section per side present (Left-leaning, Centre, Right-leaning, Western, Eastern outlets) as a strip of cards showing each story's title, that side's lead headline quote and its outlet; a card opens the story on that axis. Outlets = the outlet list. No outlet logos, no third-party colours or type.
- Digest list (tablet master pane): date, intro line, then one card per story: rank, title, proportional coverage bars (Left/Centre/Right and West/East) with spoken labels, signal chips (blindspots "Only left-leaning outlets covered this" / "Only Western outlets covered this", "N contested claims", "N East–West contradictions", "Analysis unavailable"), outlet count and a "Compare coverage" cue; "Last updated" line, pull-to-refresh.
- **In brief** (16 Oct 2026): the first card on a story: "What happened" (the pipeline's sourced `summary`, two or three sentences), "Across the sides" (its sourced `conclusion`: what every side establishes, how the sides frame it differently, what stays contested; it states the disagreement and never resolves it) and "Where they disagree" (every contested claim and East–West contradiction as a row that jumps to its section, switching axis when needed; "No contested claims or East–West contradictions found in today's coverage." when there are none). Each paragraph carries source pills like any point. Hidden when the analysis is unavailable, and for a digest from before 16 Oct (no summary, no conclusion) with nothing contested.
- **Graphical layer** (16 Oct 2026): outlets appear as avatars (two or three initials on a circle in the outlet's lean colour, bloc colour for outlets off the lean scale; never a logo) on source pills, quote rows, the Sources list, a strip on each story card, and the story header's coverage spectrum: three zones Left · Centre · Right then West · East, each a colour rail with that side's avatars and its count; tapping a zone opens that side's articles. Section headings and jump chips carry icons; the In brief card opens with three stat tiles (agreed facts, contested claims, West–East contradictions); each contested claim shows a stated-versus-disputed bar.
- **Motion** (16 Oct 2026, `docs/screenshots/redesign/12_motion.gif`): a story's blocks fade and rise in a quick stagger; switching Political lean ↔ West / East slides the sections in from the side the axis sits on; the coverage spectrum's avatars pop in; the In brief tiles count up; a contested claim's stated-versus-disputed bar grows; a jump briefly tints the section it lands on. All of it is skipped when the device asks for reduced motion.
- Story detail (redesigned 16 Oct 2026, `docs/screenshots/redesign/`): compact header (title, outlet count, both coverage bars with inline legends, signal chips, unrated-outlet note), the axis switch "Political lean" | "West / East", then a horizontal **jump bar** ("On this page": Headlines · Emphasis · Agreed 10 · Left out 3 · Contested 1 · Opinion 1 · Sources 16, or Headlines · Emphasis · Contradictions 0 · Sources on the bloc axis) that scrolls to the section. The app bar shows "n of N" with previous / next story buttons (axis carried over; back still returns to the list).
  - **Compare by dimension, every side on the page at once** (no per-side tabs): "Headlines, side by side" and "What each side emphasises" each list every lean (or bloc) present as a block with a colour rail, the side's name and its outlet count. A headline quote is one row (quote, "Outlet · headline" or "Outlet · summary", open icon) that opens the article itself. An emphasis point is its text plus source pills.
  - Lean axis continues with "What all sources agree on"; "What each side leaves out" (one rail block per lean, "Not in left-leaning coverage"); "Contested claims" (card: claim, "Stated by" pills, "Disputed by" pills); "Opinion & analysis" in a separate tinted panel.
  - West / East axis continues with "East–West contradictions" (topic card with a West block and an East block), or "No contradictions found in today's coverage".
  - **Source pills**: one pill per outlet (up to three, then "+N more"), each with a dot in the outlet's lean colour (bloc colour for outlets off the lean scale) so the sides backing a point are visible at a glance. Tapping a pill opens the **sources sheet** ("Sources for this point", "N articles back this point"): every article with outlet, tags and headline, the tapped outlet first, each row opening the original in the external browser.
  - Sources: every article with outlet, lean/bloc/region tags, a visible "state media" tag for state-controlled outlets, headline and link.
  - "Report a problem with this story" at the end opens a mailto: to info@froggyeye.com with the subject "Sides story report" and the story title and digest date in the body (compliance m2).
- Offline: cached digest shown instantly; revalidated on launch/resume when the digest date is before today (UTC) or it was fetched more than 6 h ago; conditional GET with `If-None-Match`; offline-with-cache note; offline-without-cache empty state with Retry.
- Settings/About: theme (System/Light/Dark), text-size note (follows device up to 200%), ad-free purchase + restore, Google UMP "Ad privacy options" where required, how it works (says the comparison is generated automatically by an AI model from headlines and short summaries and not reviewed by a human editor), "Report a problem with a story" (mailto: info@froggyeye.com, subject "Sides story report"), outlets and rating basis, "Published by Froggy Eye Ltd", Contact (info@froggyeye.com, opens the mail app via mailto:), privacy policy, © 2026 Froggy Eye Ltd. The publisher and contact satisfy Play's News apps policy.
- Monetisation: AdMob banner at the bottom of the list and story screens (never inside sourced content, hidden until a digest loads), every request non-personalised with max ad content rating T and tagged not child-directed, with the under-age-of-consent tag left unset (compliance m3); a release build with Google's test units still in `AdConfig` never starts the ads SDK (compliance m4), one-time non-consumable `com.froggyeye.sides.adfree` removes ads instantly.

**Tablet (phase 5, built)**
- ≥ 744 dp window width (every iPad, both orientations): master-detail. Left pane = the digest list (360 dp; 320 dp below 900 dp so the detail pane keeps ≥ 380 dp, pull-to-refresh, selected story tinted, outlined and announced as selected); right pane = the selected story, story 1 by default; "No story selected" placeholder while there is no digest. Selecting a story swaps the pane in place and the URL reads `/story/:id` (axis carried over as `?axis=bloc`). The banner sits under the detail pane only.
- ≥ 1100 dp: perspectives side by side. In each comparison section ("Headlines, side by side", "What each side emphasises") the side blocks become one equal-width column per lean present (rail along the top), so a row compares across sides; shared sections (agreed, omissions, contested, opinion) are full-width below. West / East = two columns; each East–West contradiction is a full-width topic with the West and East statements aligned under their columns; "No contradictions found" spans both.
- Column guard: columns render only when every column gets ≥ 280 dp × text scale; otherwise the sides stay stacked (e.g. 3 leans on an 11" iPad landscape, or any columns at 200% text).
- Rotation/resizing keeps the selected story (route) and the axis (per-story provider).
- Below 744 dp the phone layout is unchanged. Large phones in landscape (≥ 744 dp wide) also get master-detail.

**Later**
- Phase 6: live digest URL via GitHub Actions + Pages.
- Archive of past days (`digest/index.json`), story search, share a story link.

## Screen map

```
/                      Home shell: tabs Today (front page) · By side · Outlets ──tap story──► /story/:id
                       (Story detail; ?axis=bloc opens West / East; By side opens on the side's axis)
  └─ settings icon ──► /settings ──► /settings/outlets  (Outlets and ratings)

Tablet (≥ 744 dp): / and /story/:id both render list + detail side by side; tapping a story is a
context.go to /story/:id that updates the same page (no push, no animation).
```

## Data model (app side, `lib/features/digest/domain/digest.dart`)

`Digest {schemaVersion, generatedAt, date, meta, outlets[], stories[]}` · `Outlet {id, name, lean?, region, bloc, ownership, country, homeUrl, ratingBasis}` · `Story {id, title, rank, outletCount, coverage, blindspot, articles[], agreedFacts[], framingByLean[], omissions[], contestedClaims[], opinion[], framingByBloc[], contradictions[], summary?, conclusion?}` · `Article {id, outletId, headline, snippet, url, publishedAt}` · `SourcedPoint {text, sources[]}` · `HeadlineQuote {articleId, quote, field: headline|snippet}` (field required, set by the pipeline validator) · `Contradiction {topic, west, east}`.
Integrity on read: unknown source ids are stripped and any point left without a source is dropped, so the UI cannot render an unsourced claim.

Local storage: `<documents>/digest/latest.json` + `latest.meta.json` (`fetched_at`, `etag`); SharedPreferences keys `theme_mode`, `ad_free_owned`. No accounts, no backend, no analytics or crash SDKs.

## Permissions

| Platform | Permission | Why |
|---|---|---|
| Android | `INTERNET` | Download the daily digest; load ads; billing. |
| Android | `com.google.android.gms.permission.AD_ID` | Required by Google Mobile Ads on Android 13+ (frequency capping, fraud prevention). Requests are non-personalised. |
| Android (merged from the Mobile Ads SDK) | `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE` | Added by `play-services-ads`; the app itself uses none directly. |
| Android (removed) | `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION`, `ACCESS_ADSERVICES_TOPICS` | Merged by `play-services-ads` for Privacy Sandbox targeting and measurement; stripped with `tools:node="remove"` because Sides requests non-personalised ads only (security audit SEC-6, 15 Oct 2026; verified absent from the built APK). |
| Android (merged from Billing) | `com.android.vending.BILLING` | Ad-free in-app purchase. |
| iOS | none requested at runtime | No ATT prompt and no `NSUserTrackingUsageDescription`: Sides does not track; all ad requests are non-personalised (house convention). `SKAdNetworkItems` (Google's list, 50 entries) and `GADApplicationIdentifier` are in Info.plist. `ITSAppUsesNonExemptEncryption = false`. |

**Decision (confirmed by the conductor, 15 Oct 2026): no App Tracking Transparency.** Sides follows the house pattern used in eight_ball_wisdom: no ATT prompt, no `NSUserTrackingUsageDescription`, non-personalised ad requests on both platforms, Google UMP consent where UK/EEA rules require it, and an "Ad privacy options" entry in Settings. Later privacy and compliance stages should not reopen this. If ATT is ever added, the App Privacy answers change to "used for tracking".

Privacy declarations must reflect AdMob (advertising data, device identifiers on Android, not used for tracking) rather than "No data collected".

## Release-stage to-dos owned elsewhere

- AdMob: create the app + banner units, then replace the test IDs in `lib/core/config/ad_config.dart`, `ios/Runner/Info.plist` (`GADApplicationIdentifier`) and `AndroidManifest.xml` (`APPLICATION_ID`) (`AdConfig.liveIdsConfigured` is derived from the unit IDs, so it turns true by itself; until then a release build ships without ads).
- Create `com.froggyeye.sides.adfree` in both consoles.
- Android release keystore (house-facts §7); app icon (design stage).

## Screenshot mode

`--dart-define=SCREENSHOT_MODE=true` loads the bundled sample digest (`assets/sample_digest.json`, the real 14 Oct 2026 run) with ads off; `--dart-define=SCREENSHOT_ROUTE=/story/<id>?axis=bloc` opens a route at launch; `--dart-define=SCREENSHOT_ORIENTATION=landscape|portrait` asks the system to rotate (iPadOS honours it only with `UIRequiresFullScreen`, which is added temporarily for captures and never committed). All are ignored in release builds. Tablet captures: `docs/screenshots/phase5/`.
