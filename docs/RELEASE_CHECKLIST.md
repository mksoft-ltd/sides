# Sides 1.0.0: release checklist (console-only work for the publish stage)

Written 15 Oct 2026 by release-manager (stage 5b). Store text is in `ios/fastlane/metadata/` and
`android/fastlane/metadata/android/` (en-GB + en-US on both stores) and uploads verbatim. Console answers are in
`android/fastlane/data_safety_answers.md` (Play) and `ios/fastlane/privacy_details.json` + `privacy_details_rationale.md`
+ `rating.json` (Apple). Records: ASC app 6822909350, Play app 4973894667859335790, bundle/package `com.froggyeye.sides`,
version 1.0.0, build/version code 1 (re-derive from both stores' live state before upload, house-facts §20).

Owner key: **[F]** founder-only click, **[A]** app change (a fix agent; release-manager does not edit `lib/`),
**[P]** publish stage (automatable).

## 1. App changes needed before the release build

- [x] **[A] Contact email visible in the app (Play News policy).** Done 15 Oct 2026. Settings › About now shows
  "Published by Froggy Eye Ltd", a "Contact" tile reading `info@froggyeye.com` that opens `mailto:` through
  `LinkLauncher.compose` (mailto only; the article path `open` stays http/https only), the existing "Privacy policy"
  tile, and "© 2026 Froggy Eye Ltd". Address in `AppConfig.contactEmail`, labels in `Copy`. Pinned by
  `test/widget/settings_test.dart` (About group) and `test/unit/link_launcher_scheme_test.dart`.
- [ ] **[A]/[P] Live AdMob IDs** (create in AdMob first, see §2). Replace exactly these four test values
  (`AdConfig.liveIdsConfigured` is derived from the two unit IDs and needs no edit; until both differ from the test units a
  release build does not start the ads SDK at all, so a missed swap ships without ads rather than with test ads):
  - `lib/core/config/ad_config.dart` line 22 `_releaseBannerAndroid` (now `testBannerAndroid`) → live Android banner unit
  - `lib/core/config/ad_config.dart` line 23 `_releaseBannerIos` (now `testBannerIos`) → live iOS banner unit
  - `ios/Runner/Info.plist` line 28 `GADApplicationIdentifier` (`ca-app-pub-3940256099942544~1458002511`) → live iOS app ID
  - `android/app/src/main/AndroidManifest.xml` line 48 `com.google.android.gms.ads.APPLICATION_ID`
    (`ca-app-pub-3940256099942544~3347511713`) → live Android app ID
  Check the iOS and Android IDs are not cross-wired (an iOS unit in the Android build serves nothing). Keep the
  `testBanner*` constants: debug and profile builds must keep using them.
- [ ] **[A] Refresh SKAdNetwork IDs.** `ios/Runner/Info.plist` holds 50 `SKAdNetworkItems`. Replace the list with
  Google's current one from the Google Mobile Ads iOS quick-start page and keep any non-Google entries.
- [ ] **[P] Upload keystore (house-facts §7, §26, §30).** Checked 15 Oct 2026: no `android/key.properties`, no
  `*.jks` anywhere in the repo (`android/` and `android/app/` both checked), `android/app/build.gradle.kts` release
  `signingConfig` is still `debug` (security audit SEC-5), and nothing has been uploaded to Play for this app, so
  generating a key now cannot orphan an uploaded artifact. Re-run those three checks immediately before generating
  (another agent may have done it). Then: `keytool -genkeypair` → `android/upload-keystore.jks`, alias `upload`;
  `android/key.properties` with `storeFile=../upload-keystore.jks` (Gradle resolves it against `android/app/`, §30) or
  keep the keystore in `android/app/`; wire `signingConfigs.release` per `wheel_of_choices/android/app/build.gradle.kts`;
  back the keystore and passwords up where the founder keeps the others. Verify the AAB's signing SHA-1 matches the
  keystore. Both files are already git-ignored.

## 2. AdMob console [P]

- [ ] Create two AdMob apps under the Froggy Eye publisher (`pub-6255057925578575`): Sides iOS and Sides Android.
  Link each to its store listing once live (AdMob needs the store link to verify app-ads.txt).
- [ ] One **Banner** unit per app (anchored adaptive banner in code). Name: `sides-ios-banner`, `sides-android-banner`.
- [ ] Privacy & messaging: confirm the GDPR consent message (UMP) is published for both apps; the app relies on it in
  the UK/EEA.
- [ ] Copy the IDs into the places in §1.

## 3. Website and URLs [P]

- [ ] **sides.froggyeye.com does not resolve yet** (DNS returned nothing, curl 000, 15 Oct 2026). It is the support
  and marketing URL on both stores and the Play News declaration website. Create the subdomain and app page through the
  froggyeye.com site tooling (house-facts §25), then confirm HTTP 200. Fallback if it cannot be live before
  submission: switch `support_url.txt` / `marketing_url.txt` (both locales) to `https://froggyeye.com`.
- [ ] **app-ads.txt on sides.froggyeye.com**: serve `https://sides.froggyeye.com/app-ads.txt` with the studio line
  `google.com, pub-6255057925578575, DIRECT, f08c47fec0942fa0` (same as `froggyeye.com/app-ads.txt`). Once linked,
  AdMob's app-ads.txt status must read "found".
- [ ] **Privacy policy URL**: `https://mksoft-ltd.github.io/sides/privacy_policy.html` returned **404** on 15 Oct
  2026 because the file had not been committed. It is now committed at the repo root; the daily workflow's build job
  copies it onto gh-pages, so it goes live on the next daily run (06:00 UTC) or a manual
  `gh workflow run daily.yml`. Verify `200` + `content-type: text/html` using the URL extracted from
  `AppConfig.privacyPolicyUrl`, not one typed by hand.

## 4. App Store Connect

- [ ] [P] Upload metadata (`deliver`, en-GB primary + en-US), categories News / Education, copyright, review
  information (phone `+447415533188`, no demo account).
- [ ] [P] Age rating: apply `ios/fastlane/rating.json` (PATCH `ageRatingDeclarations`). Expected **13+**. Advertising =
  Yes, UGC / chat / unrestricted web = No.
- [ ] [P] **IAP** `com.froggyeye.sides.adfree`, Non-Consumable. Reference name "Ad-free". Display name "Remove ads".
  Description (≤55): `Removes the banner ads for good. One-time purchase.` (51). Price: base storefront United Kingdom
  **£2.99**, United States set explicitly to **$2.99**, others Apple-equalised. Review screenshot: the Settings
  "Remove ads" tile. Review note: "Removes the AdMob banner. No content is gated."
- [ ] [P] **Availability: all storefronts except mainland China** (news-app licensing; the content quotes Chinese state
  media alongside other outlets). Hong Kong, Macau and Taiwan stay on.
- [ ] [P] App privacy: upload `ios/fastlane/privacy_details.json` (7 data types, none used for tracking).
- [ ] **[F] App Privacy → Publish** (the API cannot publish it; house-facts §12).
- [ ] [P] Order (house-facts §15): IAP → privacy label published → version → build attached → from the **IAP's own
  page** "Add for Review" into the version's draft submission → confirm **2 items** → submit.

## 5. Google Play Console

- [ ] [P] Listing: `supply` metadata for en-GB (default) and en-US only, title / short / full description,
  `changelogs/1.txt`. Category News & Magazines; contact info@froggyeye.com; website sides.froggyeye.com.
- [ ] [P] **IAP** `com.froggyeye.sides.adfree` (one-time product). Name "Remove ads", description
  "Removes the banner ads for good. One-time purchase, no subscription." GBP **£2.99** and USD **$2.99** set
  explicitly; if using `convertRegionPrices`, feed the tax-exclusive **£2.49** (house-facts §18). Product creation needs
  a billing-enabled build ACTIVE in some track (internal testing is enough).
- [ ] [P] App content, using the answers in `android/fastlane/data_safety_answers.md`:
  - Data safety (collected and shared: approximate location, app interactions, crash logs, diagnostics, device or
    other IDs; not "No data collected").
  - **News apps declaration: Yes** (needs the in-app contact from §1 and a live website from §3).
  - Ads: **Yes, contains ads**. Advertising ID: **Yes**.
  - Content rating (IARC): category Reference, News, or Educational. Expected Teen / PEGI 12.
  - Target audience: 13–15, 16–17, 18+ (no under-13 group).
  - App access: all functionality available without restrictions.
  - Government, Financial features, Health: none.
- [ ] [P] Upload the AAB with the raw androidpublisher call, not `supply` (house-facts §28).

## 6. Founder items

- [ ] [F] Publish the Apple privacy label (above).
- [ ] [F] ASC 2FA login, only if no App Store Connect browser session is alive when the publish stage runs.
- [ ] [F] Keep a backup of the new upload keystore and its passwords (§1).
- Optional decisions, defaults already applied: Play target audience 13+ bands (alternative: 18+ only); the hidden
  Apple keywords keep `bias` and `balanced` (ASO §1; swap for `spectrum,source` if the brand ban should cover the
  hidden field too).
