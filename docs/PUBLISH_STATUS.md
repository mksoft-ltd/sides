# Sides 1.0.0: publish status

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
5. **Content rights** (ASC, API-settable): the app shows third-party headlines and feed summaries. Recommended answer: uses third-party content, has the rights (public syndication feeds, attribution, links out; compliance m5). Needs a founder/conductor OK before PATCHing `contentRightsDeclaration`.
6. **Play App content** (browser, answers in `android/fastlane/data_safety_answers.md`): privacy policy, app access, ads = Yes, content rating (IARC), target audience 13+, News app = Yes, Data safety, Advertising ID = Yes, government/financial/health none, then countries/regions.
7. **Submission (founder-confirmed)**: attach build to version 1.0.0 → IAP page "Add for Review" into the version's draft submission → version "Add for Review" into the SAME draft → confirm **2 items** → submit. Play: promote/send for review from Publishing overview.

## Re-release one-liners

```
cd ios && fastlane metadata && fastlane screenshots_upload && fastlane build_upload_testflight
cd android && fastlane metadata && fastlane screenshots_upload && fastlane build_upload_play_internal
```
Screenshots: `scripts/publish/capture_ios.py <udid> store_assets/screenshots/raw 7|4`,
`scripts/publish/capture_android.sh phone|tablet <serial>`, then `store_assets/screenshots/render.sh`.
