# Sides: publish status

## Internal testing builds 4 to 10 (16 Oct 2026): UI redesign, In brief, graphical layer, motion, front page, search, readability

- **1.3.3 (versionCode 12)**: layered, automatic search (phone → archive online + shared cache → comparison only when
  today has nothing) with a step-by-step progress panel for slow searches. Privacy policy updated (17 Oct): the words
  are now sent automatically to check the shared cache. Replaces 11.
- **1.3.2 (versionCode 11)**: outlet thumbnails on quotes/sources/By side, per-side picture strip on the lead story and
  story header. Replaces 10.
- **1.3.1 (versionCode 10)**: readability pass (content first, sources behind one link per point, plain facts line,
  bigger reading text, clearer tap cues). Replaces 9 on the internal track.

- **1.3.0 (versionCode 9)**: Search tab (archive search on the device + on-demand topic comparison through the new
  Cloudflare worker `sides-topic`). Replaces 8 on the internal track. **Console to-do before any production release of
  1.3.0**: Play Data safety → add "App activity: other user-generated content / search queries" (collected, not shared,
  not linked to identity, optional, purpose app functionality); Apple App Privacy → "Search History" not linked, app
  functionality. The privacy policy already describes the service (effective 16 Oct 2026).

- **1.2.0 (versionCode 8)**: news-app front page (lead story on the plate, Top stories strip, rows, lens filters), By
  side tab, bottom tabs. Replaces 7 on the internal track.

- **1.1.0 (versionCode 7)**: motion on the story page (staggered reveal, axis-switch slide, avatar pop-in, stat
  count-up, stance-bar growth, jump highlight; all off under reduced motion). Replaces 6 on the internal track.

- **1.1.0 (versionCode 6)** (~07:50 UTC): outlet avatars, the header coverage spectrum (tappable zones), section icons,
  In brief stat tiles, stated-vs-disputed bars. Replaces 5 on the internal track.

- **Play internal track: 1.1.0 (versionCode 4)** uploaded `completed` with en-GB/en-US notes (commit 09a3894: the
  compare-by-dimension story page, source pills + sheet, jump bar, previous/next, signal chips). Replaced minutes later by
  **1.1.0 (versionCode 5)** (commit 669fefa: adds the In brief card — summary, conclusion across the sides, disagreements
  list). Testers on the internal opt-in link (above) get build 5. Production stays 1.0.0 (3) in review; nothing there
  was touched. Apple was not rebuilt (the redesign is not on TestFlight yet).
- **Pipeline**: the daily run was dispatched by hand at 00:31 UTC (run 38829982325) so `digest/latest.json` carries the
  new `summary` / `conclusion` fields for the In brief card; the 06:00 UTC schedule continues as before. The 1.0.0 app
  ignores the two new keys (its parser reads known keys only), so the live digest stays safe for the version in review.


## BOTH STORES SUBMITTED (15 Oct 2026, ~21:30 UTC)

- **Apple:** review submission `0affeefb…` WAITING_FOR_REVIEW since 20:49Z (version 1.0.0 build 3 + adfree IAP).
- **Play:** "Send changes for review" confirmed by the conductor ~21:30Z → Publishing overview shows **"Changes in
  review"** (12 changes: production 1.0.0 (3) full rollout, 177 countries + rest of world, en-GB/en-US listings,
  content rating, target audience, privacy policy, ads, data safety, health, news declaration, category).
- **Internal testing opt-in link (16 Oct 2026):** https://play.google.com/apps/internaltest/4700266578556660578 — tester
  lists attached: Family (kcyconsulting.ltd@gmail.com + 1), Founder testers, Froggy Eye internal testers. Build 1.0.0 (3).
- **AdMob:** both Sides apps added to the existing published EU (GDPR) message and the US state regulations message
  (each now 10 apps), privacy policy URL https://mksoft-ltd.github.io/sides/privacy_policy.html set per app. This
  clears the UMP "no form(s) configured" error. Home shows identity / payment address / payment method all verified
  (no payments banner). Still to do once listings are live: AdMob → Apps → each Sides app → App settings → link the
  store listing.

## 15 Oct 2026 evening: Apple SUBMITTED, Play draft production release staged (founder finishes 3 clicks)

- **Apple: submitted for review by the founder at 20:49 UTC.** Review submission `0affeefb…` state `WAITING_FOR_REVIEW`,
  submittedDate 2026-10-15T20:49:36Z, containing version 1.0.0 (appStoreState WAITING_FOR_REVIEW, build 1.0.0 (3)) and
  IAP `com.froggyeye.sides.adfree` (state WAITING_FOR_REVIEW). Nothing more to do on Apple until the review result.
- **Play: founder set Production countries/regions (177 + rest of world).** Conductor then staged the production
  release by API: track `production`, release `1.0.0 (3)`, versionCode 3, notes en-GB/en-US from `changelogs/3.txt`,
  **status `draft`** (validate: "Only releases with status draft may be created on draft app" — a never-published app
  cannot get a `completed` production release via the API), edit committed, read back = draft present. Dashboard shows
  "Create a new release" ticked. The Chrome auto-mode classifier denies "Preview and confirm the release" / "Send for
  review" ("Production Deploy"), so the founder clicks: Dashboard → "Preview and confirm the release" → Next → **Start
  rollout to Production** (or Save), then Publishing overview → **Send app for review**.
- **Later 15 Oct:** production release advanced to "Start full rollout" (Publishing overview lists 12 changes). Quick
  checks flagged one blocker, the **News and magazine apps declaration**, which the conductor completed (on behalf of
  Froggy Eye Ltd; contact URL https://sides.froggyeye.com; Commercial/Private; news aggregator Yes; no credentials
  required). "Submit 12 changes for review" is enabled; the final confirm button **"Send changes for review" is
  blocked by the Chrome classifier** → founder clicks it in the open dialog.
- `scripts/publish/play.rb` fix: a body-less POST (`:commit`) returned Google's HTML 404; it now sends an empty body with
  `Content-Length: 0`, which works (`:validate` never needed it).

## Play production draft via API: refused, nothing committed (15 Oct 2026)

Asked: stage a production `draft` release of versionCode 3 with all countries, committed with
`changesNotSentForReview=true` so nothing goes to review. Result, inside one edit:
- `countryTargeting` (explicit 174-region list + includeRestOfWorld, and includeRestOfWorld alone) → **400 "Country
  targeting is only supported for staged releases."** `countryAvailability/production` is read-only (GET 204, no
  countries set). So production countries/regions cannot be set through the API for a full release: console only.
- The draft release without targeting was accepted in the edit, but `:commit?changesNotSentForReview=true` → **400
  "Changes are sent for review automatically. The query parameter changesNotSentForReview must not be set."** A commit
  without the flag was not allowed by the conductor, so the edit was deleted. Read back: production track has **no
  release**; internal still `1.0.0 (3)` completed.
- Remaining on Play (console, founder): Production → Countries/regions (add all), create the production release from
  versionCode 3, Publishing overview → Send for review. Content rating is Completed (IARC done by the conductor). Apple
  privacy label is published; version 1.0.0 sits in draft submission 0affeefb; the IAP still needs the founder's
  "Add for Review" click.

## Build 3: new newspaper icon (15 Oct 2026, afternoon) — supersedes the build table below

| Store | Read back |
|---|---|
| Play internal | **1.0.0 (versionCode 3)**, `completed`, replaces 2 (notes en-GB + en-US). Signer = upload key EA:80:6D…B6:95. |
| Play listing images | en-GB and en-US: icon = 1, featureGraphic = 1, each **SHA-256 equal** to `store_assets/icon_512.png` / `feature_graphic.png` (the new newspaper art); 6 phone + 4 ten-inch screenshots unchanged. |
| ASC build | **1.0.0 (3)** `cd9e68c3-b182-448e-88d7-72e09b2ab9d1`, `VALID`, usesNonExemptEncryption false, **attached to version 1.0.0** (replaces build 1; read back on the version's build relationship). IPA: Apple Distribution 696939LPWV, live AdMob app ID, 0 sample IDs. |
| ASC review submission | Draft `0affeefb…` untouched: READY_FOR_REVIEW (draft), submittedDate null, 0 items; still the only submission on the app. |

Icon evidence (all in `docs/screenshots/publish/`): `build3_launcher_home.png` + `build3_launcher_icon_crop.png`
(release APK versionCode 3 on the `sides_capture` emulator: newspaper mark in the dock), `build3_app_running.png`
(release build 3 launched, live digest, no FATAL in logcat — the R8 lesson re-checked before upload),
`build3_ios_appicon.png` (AppIcon60x60@2x from the uploaded IPA). Store screenshots were not recaptured: they show
the in-app content, and the old app-bar mark is a 20 dp detail in the list shot only.


| Store | What is there (read back) |
|---|---|
| Play internal track | **1.0.0 (versionCode 2)**, status `completed`, notes en-GB + en-US. Signer = upload key EA:80:6D…B6:95. versionCode 1 (uploaded first) crashed at launch and was replaced; code 1 is burnt. |
| Play IAP | `com.froggyeye.sides.adfree`, option `adfree-buy`, **ACTIVE**, GB £2.99 (GBP 2.99), US $2.99, legacyCompatible, listings en-GB + en-US. |
| ASC build | **1.0.0 (1)**, `VALID`, minOs 15.0, usesNonExemptEncryption false, attached to version 1.0.0 (read back). Signed Apple Distribution 696939LPWV. |
| ASC IAP | `6822977312` **READY_TO_SUBMIT** (not yet in a submission: console step below). |
| ASC review submission | Draft `0affeefb-fdda-4bb3-a2e6-b9abfb22ff6a` (state READY_FOR_REVIEW = draft, 0 items, never submitted). Adding the version is refused only by `APP_DATA_USAGES_REQUIRED` (privacy label not published). |

**Live AdMob IDs** (commit 3aacab8): iOS app `~7295598634` / unit `/1517403205`; Android app `~9395893220` / unit
`/5017664516`, publisher `pub-6255057925578575`. Debug/profile builds keep Google's test units by design. Release
artifacts contain no sample ID: AAB `libapp.so` (all 3 ABIs) and the IPA's `App.framework` carry only live units;
IPA Info.plist and AAB manifest carry the live app IDs.

**Release smoke test (Android, emulator `sides_capture`, release APK of the shipped config):** launches, loads the live
15 Oct digest, banner fills. The SDK's own request log:
`AdRequestServiceImpl: Sending request: https://googleads.g.doubleclick.net/mads/gma?...client=ca-app-pub-6255057925578575...slotname=5017664516...`,
then `onSdkImpression`. The creative is labelled "Test Ad" because Google auto-flags emulators as test devices
("This request is sent from a test device"); the unit requested is the live one. **iOS**: no physical iPhone is
attached and Flutter release builds cannot run on a simulator, so iOS evidence is the binary (live IDs only, above).

**What tripped and how it was handled:**
- The first minified Android release (versionCode 1, already on internal) **crashed at launch**:
  `Unable to get provider androidx.startup.InitializationProvider … Failed to create an instance of
  androidx.work.impl.WorkDatabase` (R8 stripped WorkManager's Room DB constructor; WorkManager comes in with the ads
  SDK). Fixed with keep rules in `android/app/proguard-rules.pro` (374b22a), verified on the emulator, re-uploaded as
  versionCode 2. pubspec is now `1.0.0+2`; iOS is still build 1 (the fix is Android-only). Next build number must be
  ≥3 on both stores.
- The release-guard unit test pinned "no live IDs yet"; it now pins the live state and checks nothing is cross-wired.
- **UMP consent form not configured:** on launch UMP logs `Publisher misconfiguration: … no form(s) configured for
  the input app ID … ca-app-pub-6255057925578575~9395893220`. The app then still requests non-personalised ads, but
  UK/EEA users get no consent message. Founder: AdMob → Privacy & messaging → create and publish the GDPR (European
  regulations) message for both Sides apps.
- **AdMob apps are "not yet listed on a store" (Requires review).** Once each listing is live, link it in AdMob → App
  settings → App store details, then app-ads.txt verification runs.

## Play Console declarations (driven in the browser by the conductor, 15 Oct 2026; all read back "Actioned")

Privacy policy URL; Sign-in details (formerly App access) = no restricted parts; Ads = Yes; Target audience 13–15,
16–17, 18+; Data safety = collects and shares, encrypted in transit, no account creation, no deletion mechanism, 5 data
types (Approximate location, App interactions, Crash logs, Diagnostics, Device or other IDs), each collected and shared,
not ephemeral, required, purposes per `android/fastlane/data_safety_answers.md`; Government apps No; Financial features
none; Health none; Advertising ID Yes (Advertising/marketing, Analytics, Fraud prevention). Store settings: category
News & magazines, tags "News & magazines" + "News aggregator" (no Politics/World tag offered). Play no longer has a
separate "News apps" declaration (click-path row 6 obsolete). Still open on Play: Content rating (IARC terms need the
founder's OK), Countries/regions (production only), Send for review (founder). Console account index for
froggyeye.ltd@gmail.com in this Chrome profile is now `/u/0/`; deep links bounce to Home.

## Exact remaining clicks (nothing has been submitted)

1. **[F] ASC App Privacy:** enter the 7 data types from `ios/fastlane/privacy_details.json` → **Publish**.
2. **ASC IAP page** (In-App Purchases → "Remove ads" / com.froggyeye.sides.adfree) → **Add for Review** → choose the
   existing draft "Draft iOS Submission — Started by API user Q2GWD76GUV" (never "Create New Submission").
3. **ASC version 1.0.0 → Add for Review** into the SAME draft (or the publisher adds it by API once step 1 is done).
4. Read back: the draft must hold **2 items** (version + IAP).
5. **[F] Submit for review** (App Store) — founder-confirmed.
6. **[F] Play:** IARC content rating (accept terms), Countries/regions, create the production release from
   versionCode 2 (draft until first rollout) → Publishing overview → **Send changes for review**.
7. **[F] AdMob:** publish the UMP GDPR message for both apps; link store listings once live.

## Earlier stage-7 prep

Stage 7 (store-publisher), 15 Oct 2026. Every "done" line below was verified by an API read-back, not by a tool's
exit code. Records: ASC app `6822909350`, Play app `4973894667859335790`, bundle/package `com.froggyeye.sides`.

## Done

| Item | Evidence (read back) |
|---|---|
| Android upload keystore | `android/upload-keystore.jks`, alias `upload`. Release APK signer SHA-1 `EA:80:6D:C6:0D:14:F6:34:88:3C:00:01:8D:99:A0:D9:D4:EA:B6:95` = keystore. Password in `android/key.properties` (git-ignored) + Keychain service `sides-upload-keystore`. Release build: minify + shrink + proguard. |
| Version | Both stores had no build/artifact. pubspec `1.0.0+1`. ASC version string PATCHed `1.0` → `1.0.0` (read back `1.0.0`). |
| iOS signing prep | App Store profile "Sides App Store" (cert `48CDM5Z29C`, exp 11 Oct 2027) installed. `ios/ExportOptions.plist` pins cert SHA-1 `535BD1B4…2BA2C5` (the keychain holds two same-named distribution identities). |
| ASC text metadata | en-GB + en-US: name "Sides: The News, Every Angle" (28), subtitle (30), description (3043/3042), keywords (100), promo (161), support/marketing `https://sides.froggyeye.com`, privacy URL. All byte-equal to the local files. What's New is empty: Apple does not take release notes on a first version. Copyright `© 2026 Froggy Eye Ltd`. Categories NEWS / EDUCATION. |
| ASC review info | Kevin Lam, `+447415533188`, info@froggyeye.com, no demo account, notes 2955 chars (equal to file). |
| ASC age rating | `rating.json` applied: 26 attributes read back identical. API reports `appStoreAgeRating=TWELVE_PLUS` (Apple's enum for the 12+/13+ band). |
| ASC price + availability | Free (USA 0.0 base). 174 territories available, mainland China not; Hong Kong, Macau, Taiwan on; new territories on. |
| ASC screenshots | Per locale: 6 × 6.9" iPhone (1320×2868) + 4 × 13" iPad, all `COMPLETE`, order pinned. 6.5" rendered (`out/ios_65`) but not uploaded: deliver/ASC fold it into the same 6.7"/6.9" set. |
| ASC IAP | `com.froggyeye.sides.adfree` (id `6822977312`), Non-Consumable, reference "Ad-free", display "Remove ads", description 51 chars, en-GB + en-US. Price GBR £2.99 base, USA $2.99 manual. 174 territories (no CHN). Review screenshot = iOS Settings capture at £2.99 (`store_assets/screenshots/raw/iap_review_settings.png`), checksum match, `COMPLETE`. State `READY_TO_SUBMIT`. |
| Play listing | en-GB (default) + en-US: title (28), short (77), full (3043/3042), hi-res icon, feature graphic, 6 phone + 4 ten-inch screenshots each. Contact email info@froggyeye.com, website https://sides.froggyeye.com. |
| Screenshots (M3) | Harness names = `specs.json` raw names. iOS captured host-side (iPhone 17 Pro Max iOS 26.1; iPad Pro 12.9" iOS 17 landscape, because iPadOS 26 floats the app in a window). Android on the dedicated `sides_capture` AVD (1080×2400; 2560×1600 landscape). All 26 framed PNGs opened and checked; shot 1 reads "Today's top stories, side by side"; blindspot shots show story 7's chip. |
| SKAdNetwork | Info.plist's 50 `SKAdNetworkItems` equal Google's current list on the AdMob iOS quick-start page (fetched 15 Oct 2026, set difference empty both ways). No change needed. |
| fastlane | `ios/fastlane` lanes: validate, metadata, screenshots_upload, build_upload_testflight, privacy, precheck_live. `android/fastlane` lanes: validate, metadata, screenshots_upload, build_upload_play_internal. Binary lanes refuse Google's test AdMob app ID. Raw API scripts in `scripts/publish/`. |

## Refused / blocked (exact reasons)

- **Play IAP**: `oneTimeProducts:batchUpdate` → `400 Product "com.froggyeye.sides.adfree": Can't create product. To fix, request billing permission.` Play needs a BILLING-declaring AAB in a track first. `scripts/publish/play_iap.rb` is ready (convertRegionPrices fed £2.49 → GB £2.99 confirmed, US $2.99, regionsVersion 2026/01, legacyCompatible) — re-run it right after the first internal upload.
- **Apple privacy label upload**: `upload_app_privacy_details_to_app_store` has no API-key mode and there is no cached Apple ID session on this Mac (`~/.fastlane/spaceship` absent), so it cannot run unattended. Enter the 7 data types from `ios/fastlane/privacy_details.json` in the console (App Privacy), or run `FASTLANE_USER=<apple id> fastlane privacy` from `ios/` interactively, then click **Publish**.

## Remaining steps, in order

1. **Live AdMob IDs** (founder): swap the four values in `docs/RELEASE_CHECKLIST.md` §1, commit.
2. **Android binary**: `cd android && fastlane build_upload_play_internal` (internal track; checks the AAB signer). Then `scripts/publish/rb scripts/publish/play_iap.rb`.
3. **iOS binary**: set Runner Release signing to manual with profile "Sides App Store" if the archive refuses automatic signing, then `cd ios && fastlane build_upload_testflight`. Check the IPA's version/mtime; poll the build ≤20 min, then TestFlight → Build Uploads if it never appears.
4. **[F] Apple privacy label**: enter answers + **Publish** (above).
5. **Content rights**: done 15 Oct 2026 with conductor approval: `contentRightsDeclaration = USES_THIRD_PARTY_CONTENT` (read back on the full app GET; a `fields[apps]=` sparse read returns null for it).
6. **Play App content** (browser, click-path in `docs/PLAY_DECLARATIONS_CLICKPATH.md`, answers in `android/fastlane/data_safety_answers.md`): privacy policy, app access, ads = Yes, content rating (IARC), target audience 13+, News app = Yes, Data safety, Advertising ID = Yes, government/financial/health none, then countries/regions.
7. **Submission (founder-confirmed)**: attach build to version 1.0.0 → IAP page "Add for Review" into the version's draft submission → version "Add for Review" into the SAME draft → confirm **2 items** → submit. Play: promote/send for review from Publishing overview.

## Re-release one-liners

```
cd ios && fastlane metadata && fastlane screenshots_upload && fastlane build_upload_testflight
cd android && fastlane metadata && fastlane screenshots_upload && fastlane build_upload_play_internal
```
Screenshots: `scripts/publish/capture_ios.py <udid> store_assets/screenshots/raw 7|4`,
`scripts/publish/capture_android.sh phone|tablet <serial>`, then `store_assets/screenshots/render.sh`.
