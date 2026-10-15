# Store compliance audit — Sides: The News, Every Angle

Stage 6 (app-store-review-auditor), 15 Oct 2026, `main` at 8f85b48. Scope: the Flutter app and native configs, both
fastlane metadata trees, the console answer sheets, the privacy policy (repo and live), store art and the rendered
screenshots. Built and inspected: a fresh release APK (`flutter build apk --release`) and the iOS simulator
`Runner.app` (README xcodebuild recipe). Live state was read from both stores' APIs.

## APP REVIEW RESULT

**Approval probability:** High once the publish-stage gates below are closed.
**Platforms analysed:** Apple App Store and Google Play.

No Critical findings. The code and store text are compliant. The two open Major items are submission gates that
stage 7 closes. Neither needs a change to `lib/` or the metadata text. M1 closed during this audit.

## Verified clean (evidence)

| Area | Evidence |
|---|---|
| Store records (§20) | ASC 6822909350: bundle `com.froggyeye.sides`, SKU `sides`, primary locale en-GB, one version `1.0` PREPARE_FOR_SUBMISSION, 0 builds. Play 4973894667859335790: en-GB listing only, all four tracks empty. pubspec `1.0.0+1`, `applicationId`/`PRODUCT_BUNDLE_IDENTIFIER` match, team `696939LPWV`. |
| Character limits | Apple: name 28/30, subtitle 30/30, keywords 100/100, promo 161/170, description 3043/4000, release notes 154. Play: title 28/30, short 77/80, full 3043/4000. Both locales on both stores. |
| 2.3.1 / 2.3.8 accuracy | "29 English-language outlets" = 29 `enabled` rows in `outlets.yaml` and 29 outlets in the live digest. "Middle East, India, China, Japan and South Korea, plus The Moscow Times" matches the East bloc. CGTN is `state-controlled` and shows a "state media" tag. Max snippet in the live digest is 199 characters. "At least three different outlets", "5 to 10 stories", "text size up to 200%" and "Restore purchases is in Settings" all match the code. No kid vocabulary anywhere (§31). |
| Leaked chat / notes (§24) | Both descriptions, promo, release notes and review notes read end to end as a customer would. No conversational lines, markdown or notes-to-self. |
| Judgement words | `lib/core/constants/copy.dart` and the settings strings contain no "verified", "fact-checked", "accurate", "unbiased" or "truth". "Bias" appears only in the hidden keywords and as "media-bias ratings", which names the rating source. |
| 3.1.1 IAP | Non-consumable `com.froggyeye.sides.adfree` through the native `in_app_purchase` plugin. Settings shows "Remove ads — <store price>" and an always-present "Restore purchases" button (`settings_screen.dart:197`). Busy/cancel/pending/store-unavailable states all have copy. |
| 3.1.2(c) | Not applicable. The only product is a non-consumable, not an auto-renewable subscription, so no Terms of Use link is required in the description or app. Apple's standard EULA applies by default. |
| IAP review screenshot | `integration_test/screenshots_test.dart` shot `05_settings` renders the un-owned tile with a price via a fake store, so the ASC IAP capture can be produced on an iOS simulator. |
| 5.1.1(v) / 4.2 | No accounts or sign-in. The app downloads and caches a daily digest and adds coverage bars, blindspots, per-lean wording, omissions, contested claims and a West/East axis, so it is more than a link list or website wrapper. |
| Link-outs | `ExternalBrowserLauncher` opens only http/https with `LaunchMode.externalApplication`, and mailto only through `compose`. No in-app web view in `lib/` (the WKWebView framework comes from the ads SDK). |
| Play News policy | Settings › About shows "Published by Froggy Eye Ltd", a Contact tile reading `info@froggyeye.com` (mailto, with a fallback snackbar naming the address), the privacy policy and © 2026 Froggy Eye Ltd. Settings › Outlets and ratings lists every outlet with country, lean, bloc, ownership and rating source. Article chips name the outlet. |
| Ads placement | The banner sits only in `bottomNavigationBar` of the list, story and master-detail screens. It is never inside sourced content, is hidden until a digest exists, and disappears when ad-free is owned. Every request is `nonPersonalizedAds: true`. The SDK starts only after UMP `canRequestAds()`. "Ad privacy options" shows where UMP requires it. |
| iOS binary (§17) | `nm -u` on `Runner.debug.dylib` (GMA statically linked): no `CLLocationManager`, `AVCaptureDevice`, `PHPhotoLibrary`, `CNContactStore`, `AVAudioRecorder`, `EKEventStore`, `CMMotionActivityManager`, `CBCentralManager` or `ATTrackingManager`. `ASIdentifierManager` (AdSupport, weak), `AVAudioSession` playback and `CMMotionManager` are linked, and none of them needs a purpose string. AppTrackingTransparency is not linked, so `NSUserTrackingUsageDescription` is not needed. `libswiftCoreLocation` is weak-linked with no location-manager symbol. No purpose strings are required, and none are declared. |
| iOS config | `MinimumOSVersion` 15.0 in the built app (§23). `ITSAppUsesNonExemptEncryption` false. ATS default (no exceptions). Device family 1,2, all four iPad orientations, no `UIRequiresFullScreen`, launch storyboard present, UIScene adopted. Privacy manifests are bundled for GoogleMobileAds, UMP, Flutter, shared_preferences, url_launcher, in_app_purchase and webview. |
| Android artifact | Release APK: targetSdk 36, permissions `INTERNET`, `AD_ID`, `ACCESS_NETWORK_STATE`, `BILLING`, `WAKE_LOCK`, `FOREGROUND_SERVICE` and the app's own receiver permission. `ACCESS_ADSERVICES_*` are absent (SEC-6). WorkManager's foreground service has no type, and there is no typed `FOREGROUND_SERVICE_*` permission, so no Play FGS declaration is needed. `libflutter.so`/`libapp.so` have 64 KB alignment and the other `.so` files 16 KB. |
| Privacy policy (§5) | `AppConfig.privacyPolicyUrl` (extracted from `libapp.so`) returns 200 `text/html; charset=utf-8`. The live body is byte-identical to the repo's `privacy_policy.html`, which `scripts/build_privacy_html.py` regenerates unchanged. Content names Froggy Eye Ltd as controller, AdMob/UMP data (device IDs, IP-derived location, interactions, diagnostics), non-personalised ads, no ATT, GitHub Pages IP exposure, purchases, UK GDPR basis and rights, under-13s and contact. |
| Labels vs SDKs | Apple `privacy_details.json` has 7 rows, the union of the bundled GMA 13.3.0 and UMP `PrivacyInfo.xcprivacy`. Play Data safety has 5 types, collected and shared, and matches Google's AdMob disclosure guidance and the `AD_ID` permission. Advertising ID = Yes. Purchase history is correctly not declared because no receipt server exists. "Not used for tracking" is the documented no-ATT house decision with non-personalised requests. It is consistent across the label, the policy and the review notes. |
| Age rating | Apple `rating.json` gives an expected 13+ with Advertising = Yes and no UGC or unrestricted web. Play target audience is 13+ bands only, so the app stays out of Families. IARC is expected to give Teen / PEGI 12. |
| Store art (§29) | `icon_512.png` is a three-face cube and `feature_graphic.png` has wordmark + tagline + bars. Both were opened as images. No tick, badge, seal, rosette, star or award mark. |
| Availability | ASC plan excludes mainland China (news licensing). HK/Macau/Taiwan stay on. |

## REJECTION RISKS

| # | Risk | Platform | Policy | Severity |
|---|---|---|---|---|
| M1 | **Resolved during this audit.** At first check `https://sides.froggyeye.com` did not resolve. Stage 8 landed (ecc3e5b), and the re-check returned 200 `text/html`. The body is the real Sides page, not a parking page. `/app-ads.txt` returns 200 `text/plain` with the studio line. | Both | Apple 1.5, Play News policy | Major, closed |
| M2 | Publish-stage swaps not done yet: Google **test** AdMob IDs in `ios/Runner/Info.plist:28`, `AndroidManifest.xml:48` and `ad_config.dart:21-22`; the release APK is debug-signed (`CN=Android Debug`, SEC-5); the IAP product does not exist in either console; the ASC version string is `1.0` while the build will be `1.0.0`. | Both | Apple 2.1/2.3 (test ads in review), Play signing, §15 | Major (known stage-7 items, not code defects) |
| M3 | The rendered store screenshots are stale and incomplete. `store_assets/screenshots/out/ios_69/01_digest.png` still carries the condemned headline "Every story, every angle". `specs.json` was already changed to "Today's top stories, side by side". Only 2 of 6 phone and 2 of 4 tablet shots are rendered. `raw_android/` does not exist, and the harness shot names (`01_list`, `02_story_lean`…) differ from the `raw` names `specs.json` expects (`phone_01_digest.png`…). | Both | Apple 2.3.3/2.3.7, ASO §3 | Major (stage-7 capture gate) |
| m1 | The name suffix "Every Angle" is shared with two live news apps on the same concept: "Prism News: See Every Angle." (Dec 2025) and "Clarrus: News From Every Angle" (Sep 2026). Clarrus' description ("what to emphasise, what to leave out, and how to frame it") is close to Sides' own sections. `docs/ASO.md:109` calls the shelf irrelevant, which is wrong. "Sides" is distinctive and "every angle" is generic English, so the risk is low. A 4.3(a) review costs a full cycle (§31). | Apple | 4.3(a), §31 | Minor (founder call) |
| m2 | In-app copy never says the analysis is AI-generated. `Copy.howItWorks` says only "generated once a day". The store descriptions and review notes disclose it, and there is no in-app way to report a wrong or offensive story summary. | Both | Play AI-Generated Content policy (scope for developer-generated summaries is unclear), Apple 2.3.1 | Minor (recommended before submission) |
| m3 | No maximum ad content rating is set. A 13+/Teen app with 13–15 in its Play target audience can receive MA-rated banners. | Both | Play Ads policy (ads consistent with the content rating), AdMob | Minor |
| m4 | Nothing stops a release build shipping test ad units. `AdConfig.liveIdsConfigured` is read by nothing (`grep` finds no consumer). | Both | Apple 2.1, AdMob | Minor |
| m5 | Headlines and snippets from 29 outlets are displayed in a monetised app. This follows the safest aggregator pattern: headline, a snippet of 200 characters or fewer, attribution and a link-out. Apple may still ask for permission evidence. | Apple | 5.2.1 / 5.2.2 | Minor (advisory) |
| m6 | `android/fastlane/data_safety_answers.md` §5 still says the in-app contact is "not shown yet — Open: app change". §6 says "none in the merged manifest" for foreground service, but base `FOREGROUND_SERVICE` is present. The conclusion (do not file) is still right. | Google | doc drift | Minor |

## REQUIRED FIXES (before submission; owners named)

1. **M1: closed.** `sides.froggyeye.com` serves the app page and `app-ads.txt` (verified by reading the body).
   Re-read it once just before submission.
2. **M2: publish-stage swaps (stage 7), in this order.**
   - Create the AdMob apps and units. Replace the five IDs listed in `docs/RELEASE_CHECKLIST.md` §1 and check iOS and Android are not cross-wired.
   - Refresh `SKAdNetworkItems`.
   - *Keystore: superseded 15 Oct 2026, generated and verified (SHA-1 EA:80:6D…B6:95). Never regenerate.* Re-check that no keystore exists (confirmed again today: no `key.properties`, no `*.jks`, Play tracks empty), generate it, and wire it per §7/§30. Verify the AAB signer SHA-1.
   - PATCH the ASC version string to `1.0.0` so the build attaches. *Done 15 Oct 2026.*
   - Create the IAP in both consoles, add the IAP to the submission from its own page, and confirm **2 items** (§15).
   - Build the release from the commit with live IDs and smoke-test the banner and the purchase sheet on a device.
3. **M3: re-capture and re-render the screenshots (stage 7).** *Superseded 15 Oct 2026 (store-publisher): done and uploaded, see docs/PUBLISH_STATUS.md. Do not act on this item.*
   - Align the harness output names with `specs.json` `raw` names, or the reverse.
   - Capture iOS (iPhone 6.9"/6.5", iPad 13") and Android phone/tablet separately, so no iPhone status bar lands on Play.
   - Re-render every target and open each PNG.
   - Confirm shot 1 reads "Today's top stories, side by side" and that the blindspot shot shows story 7's chip.
   - Capture the IAP review screenshot (`05_settings`) on iOS, un-owned, with the real £2.99 tier.

## RECOMMENDED IMPROVEMENTS

1. (m1) Founder decision before stage 7: keep the name, or move the suffix to Sides' own vocabulary, e.g. "Sides:
   Left, Right, West & East" or "Sides: Compare News Coverage". Check other developers' names with the iTunes Search
   API first. If it changes, update both stores' names (ASC `appInfoLocalizations`, Play title), the feature graphic
   tagline and `docs/ASO.md`. If kept, note the reply text for a 4.3(a) dispute: original code, its own pipeline, and
   the West/East axis that no rival has.
2. (m2) Add one sentence to `Copy.howItWorks`: "The comparison is written automatically by an AI model and is not
   reviewed by a human editor." Add a "Report a problem with this story" tile on the story screen that opens mailto
   with the story id and date. Both are cheap and cover Play's AI-content reporting expectation if it applies.
3. (m3) Set `MobileAds.instance.updateRequestConfiguration(RequestConfiguration(maxAdContentRating:
   MaxAdContentRating.t))` before the first load, or set the AdMob console's max ad content rating to T for both apps.
4. (m4) Make the release guard real. Add a `test/unit/release_guards_test.dart` case, or a check in the publish
   script, that fails when a release is built while `_releaseBanner*` equals a `testBanner*` constant or
   `liveIdsConfigured` is false.
5. (m5) If Apple asks under 5.2.2, reply as follows. Sides reads only public RSS feeds that outlets publish for
   syndication, and displays headlines and feed summaries of 200 characters or fewer with attribution. Every item
   links to the publisher's own site in the system browser, and ads never sit inside the content.
6. (m6) Update `data_safety_answers.md` §5 (contact is now in-app, f049f70) and §6 (FGS base permission present,
   untyped, no declaration).
7. Settings › Outlets and ratings reads the outlet list from the digest. On a first launch with no network it is
   empty, while the store copy promises the list. This is acceptable because the app itself is unusable offline on
   first launch and says so, but a bundled outlet list would make the screen always work.

## FINAL SUBMISSION CHECKLIST

- [x] `sides.froggyeye.com` serves the real app page (body read) and `/app-ads.txt` (15 Oct 2026, after ecc3e5b)
- [ ] Live AdMob app + banner IDs in all five places; SKAdNetwork list refreshed; release smoke-tested on device
- [ ] Upload keystore generated after re-checking none exists; AAB signer SHA-1 matches; Play App Signing enrolled
- [ ] ASC version string `1.0.0`; build number above both stores' max
- [ ] IAP `com.froggyeye.sides.adfree` created on both stores at £2.99/$2.99; iOS IAP review screenshot attached
- [ ] Screenshots re-captured per platform, re-rendered from current `specs.json`, every PNG opened
- [ ] Apple privacy label uploaded and **Published** (founder click); Play Data safety, Ads = Yes, Advertising ID = Yes, News app = Yes, target audience 13+ only
- [ ] Age rating applied from `rating.json`; IARC questionnaire as in `data_safety_answers.md` §7
- [ ] Availability excludes mainland China
- [ ] ASC submission shows **2 items** (version + IAP) before Submit
- [ ] Founder: name decision (m1) made before metadata upload

## Re-verification — minors fix round (15 Oct 2026, `main` at c7aed64; fix 5883f8b)

Checked by the original auditor. `flutter analyze` is clean and `flutter test` passes 247. Each fix was reverted in
the working tree and its test failed, then the change was restored (tree clean afterwards).

| Finding | Status | Evidence |
|---|---|---|
| m1 name suffix "Every Angle" | **Open: founder call** | Not yet answered. Decide before the stage-7 metadata upload. |
| m2 AI disclosure + reporting | **Fixed** | `Copy.howItWorks` now says the comparison "is generated automatically by an AI model … and is not reviewed by a human editor". `ReportStoryTile` appears in Settings › How it works and at the foot of every story, including tablet. It sends through `LinkLauncher.compose` (mailto only). The subject is "Sides story report", and from a story the body carries the title and digest date, percent-encoded with no `+`. A failed launch shows the address. Mutation (AI sentence removed) failed `story_report_test`. |
| m3 max ad content rating | **Fixed** | `AdConfig.requestConfiguration` sets `MaxAdContentRating.t`, not child-directed. `updateRequestConfiguration` runs after UMP consent and before `MobileAds.initialize()`. Mutation (call removed) failed `ad_config_test`. |
| m4 release guard | **Fixed** | `liveIdsConfigured` is now derived from the unit IDs. `main` installs `AdMobAdsService` only when `AdConfig.mayStartAds(releaseMode: kReleaseMode)` is true, so a release build still on test units never starts the SDK. Mutation (guard forced true) failed `ad_config_test`. |
| m6 doc drift | **Fixed** | `data_safety_answers.md` §5 shows the in-app contact as done. §6 explains that base `FOREGROUND_SERVICE` is present but untyped, so there is no declaration. |

Residuals (Minor, no regression):
- **The guard fails closed into a different mismatch.** A release that misses the ID swap ships with no banner. The
  listing says the app shows one, and Settings still sells "Remove ads". That is far better than test ads, but stage 7
  must confirm a live banner on the release smoke test (already in M2) before submitting.
- **`tagForUnderAgeOfConsent: no` is an assertion, not a default.** Play's target audience includes 13–15. In
  EEA countries whose digital age of consent is 16, that statement is not true of every user. Requests are already
  non-personalised, so the practical effect is small. Leaving TFUA unspecified would avoid asserting it. Optional.

Verdict: PASS
