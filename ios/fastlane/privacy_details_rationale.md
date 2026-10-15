# Apple App Privacy answers: why `privacy_details.json` says what it says

Sides 1.0.0, 15 Oct 2026. Source of truth: `docs/audits/security.md` ("PRIVACY POSTURE — what leaves the device"),
checked against the `PrivacyInfo.xcprivacy` files actually bundled in `ios/Pods` (GoogleMobileAds 13.3.0 and
UserMessagingPlatform). Format: fastlane `upload_app_privacy_details_to_app_store` (`json_path`). The upload stores
the answers but does not publish them: **App Privacy → Publish is a founder click in ASC** (house-facts §12).

## Not "Data Not Collected"

The AdMob SDK sends data to Google from the user's device, and Apple counts data collected by bundled third-party
SDKs as collected by the app. "Data Not Collected" would be false.

## Rows (one per data type; each is the union of what the two Google SDK manifests declare)

| Data type | Linked | Tracking | Purposes | Declared by |
|---|---|---|---|---|
| Device ID | Linked | **No** (see below) | Third-party advertising, Developer's advertising, Analytics | GoogleMobileAds |
| Coarse Location (IP-derived) | Linked | No | Third-party advertising, Developer's advertising, Analytics, App functionality | GoogleMobileAds (linked) + UMP (not linked, app functionality) |
| Advertising Data | Linked | No | Third-party advertising, Developer's advertising, Analytics | GoogleMobileAds |
| Product Interaction | Linked | No | Third-party advertising, Developer's advertising, Analytics, App functionality | GoogleMobileAds (linked) + UMP |
| Performance Data | Not linked | No | Third-party advertising, Developer's advertising, Analytics, App functionality | GoogleMobileAds + UMP |
| Other Diagnostic Data | Not linked | No | Third-party advertising, Developer's advertising, Analytics | GoogleMobileAds |
| Crash Data | Not linked | No | Analytics | GoogleMobileAds |

Where the two SDKs disagree on "linked" for the same type, the stricter answer (Linked) is used, because App Store
Connect takes one answer per data type.

## "Used to track you" = No, including Device ID

GoogleMobileAds' manifest flags Device ID as tracking. Sides answers **No**, and this is a deliberate compliance call,
not an omission:
- No App Tracking Transparency prompt and no `NSUserTrackingUsageDescription` (conductor decision, 15 Oct 2026,
  `docs/PRODUCT_SPEC.md`). Without ATT consent the IDFA reads as zeros, so the SDK cannot get it.
- Every ad request is `AdRequest(nonPersonalizedAds: true)` with no keywords, content URL or neighbouring URLs, so
  nothing about the user's reading is sent and no data is combined with other companies' data for targeted ads.
- The Device ID the SDK can read is the vendor-scoped IDFV, used for frequency capping and fraud prevention.
- Same house pattern as eight_ball_wisdom (live).

If ATT or personalised ads are ever added, Device ID (and any other type used for targeting) must flip to
`DATA_USED_TO_TRACK_YOU` and the ATT prompt becomes mandatory.

## Deliberately not declared

- **Purchase History.** The ad-free purchase runs through StoreKit. App code receives only the purchase state on the
  device and sends nothing anywhere: there is no receipt server or backend (security audit, IAP row). Data Apple
  processes for its own payment flow is not collected by the developer. Declaring it would be over-declaring, which is
  as inaccurate as omitting a real flow.
- **The digest download.** A plain GET to GitHub Pages with no identifiers, query parameters or cookies, and the
  developer has no access to Pages request logs. Nothing is collected.
- **Article link-outs.** User-initiated, opened in the system browser, outside the app.
- **Reading activity, settings, the cached digest, the ad-free flag.** Stored on the device only; never transmitted.

## Re-check before every release

Re-read `find ios/Pods -name PrivacyInfo.xcprivacy` after any `google_mobile_ads` upgrade. A new data type in
Google's manifest means a new row here.
