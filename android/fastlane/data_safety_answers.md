# Google Play console answers: Sides 1.0.0 (com.froggyeye.sides, Play app 4973894667859335790)

Prepared 15 Oct 2026 for the publish stage. Source of truth for Data safety: `docs/audits/security.md`
("PRIVACY POSTURE — what leaves the device"). Every answer below is console-only (App content pages); `supply`
cannot upload any of it. Merged-manifest permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `com.google.android.gms.permission.AD_ID`,
`com.android.vending.BILLING`, WorkManager/receiver internals. `ACCESS_ADSERVICES_*` are stripped (SEC-6).

## 1. Data safety

### Overview questions

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (AdMob/UMP traffic is HTTPS; the digest GET is HTTPS) |
| Do you provide a way for users to request that their data is deleted? | **No.** Froggy Eye Ltd holds no user data: no accounts, no backend, no analytics. Ad data is held by Google under its own controls (see the privacy policy). |
| Account creation | **My app does not allow users to create an account** (so no deletion URL is required) |
| Independent security review | No |
| UPI / Families badges | Not applicable |

### Data types (all collected **and** shared, all by the Google Mobile Ads SDK and UMP)

| Category → type | Collected | Shared | Ephemeral | Required / optional | Purposes |
|---|---|---|---|---|---|
| Location → **Approximate location** (IP-derived) | Yes | Yes | No | Required | Advertising or marketing; Analytics; Fraud prevention, security and compliance |
| App activity → **App interactions** (ad views and taps, app launches) | Yes | Yes | No | Required | Advertising or marketing; Analytics; Fraud prevention, security and compliance |
| App info and performance → **Crash logs** | Yes | Yes | No | Required | Analytics; Fraud prevention, security and compliance |
| App info and performance → **Diagnostics** | Yes | Yes | No | Required | Advertising or marketing; Analytics; Fraud prevention, security and compliance |
| Device or other IDs → **Device or other IDs** (Advertising ID via `AD_ID`, app set ID) | Yes | Yes | No | Required | Advertising or marketing; Analytics; Fraud prevention, security and compliance |

"Required" because the SDK collects this whenever an ad is requested and there is no in-app switch that stops it
(the ad-free purchase stops ad requests, but it is a purchase, not a privacy control Play recognises as "optional").

### Every other data type: **Not collected**

Personal info, financial info (including **Purchase history**), health, messages, photos/videos, audio, files,
calendar, contacts, web browsing, precise location, app info "Other app performance data", installed apps, search
history: not collected.
- Purchases go through Google Play Billing. App code sends nothing about them anywhere (no receipt server). The
  in_app_purchase plugin does contact Play at every cold start (availability, localised price, a silent restore
  reconcile), but that is Google's own client, not data collected by the app.
- The digest download sends no identifiers (security audit). Reading activity, settings and the cached digest stay on
  the device. Article links open in the user's browser.

Not "No data collected": the ads SDK makes that answer false.

## 2. Ads declaration

**Does your app contain ads? Yes.** AdMob anchored adaptive banner at the bottom of the list and story screens.
The store listing then shows "Contains ads". Every request is non-personalised; UMP consent is shown where UK/EEA rules
require it. Do not answer No: the one-time purchase removes ads only for buyers.

## 3. App access

**All functionality is available without any access restrictions.** No login, no demo account, no region lock in the
app. (The ad-free purchase is a normal Play purchase, not gated content.)

## 4. Target audience and content

- **Target age groups: 13–15, 16–17, 18 and over.** Do not tick any under-13 group: that would put the app under the
  Families policy, which AdMob's standard banner and the news content do not fit. The audience is adult readers,
  students and teachers (Education secondary category on Apple).
- Could the store listing unintentionally appeal to children? **No.** No characters, no kid vocabulary, neutral news
  design (house-facts §31).
- Alternative if the founder prefers the narrowest scope: 18 and over only. Either is consistent with the IARC result.

## 5. News apps declaration

**Is your app a news app? Yes.** Sides publishes a daily digest of news headlines and analysis.

Requirements of Play's News policy, and where each is met:

| Requirement | Where satisfied | Status |
|---|---|---|
| Category News & Magazines | Store settings | Set at listing time |
| Publisher of the app identified | Listing: "Sides is published by Froggy Eye Ltd" in the full description; developer name Froggy Eye Ltd. In app: Settings › About shows "© 2026 Froggy Eye Ltd" | Done |
| Contact information for the publisher | Listing: info@froggyeye.com in the full description and the developer contact. In app: Settings › About shows a "Contact" tile reading info@froggyeye.com that opens the mail app (f049f70, 15 Oct 2026) | Done |
| Sources of content identified | Every point and quote names its outlet; Settings › Outlets and ratings lists all 29 outlets with lean, region, ownership and rating source; the description says so | Done |
| Content not primarily affiliate or ad-driven | Banner only, never inside content | Done |
| Website | https://sides.froggyeye.com (support/marketing URL) | **Must return 200 before submission** |

The declaration may ask for a news-publisher website and contact email: use `https://sides.froggyeye.com` and
`info@froggyeye.com` (verify the form's current fields before submission).

## 6. Other App content declarations

| Declaration | Answer |
|---|---|
| Government apps | **No** (not developed by or on behalf of a government) |
| Financial features | **My app doesn't provide any financial features** |
| Health apps | **My app does not have any health features** |
| COVID-19 contact tracing and status | No |
| Advertising ID | **Yes, uses Advertising ID.** Purpose: Advertising or marketing; Analytics; Fraud prevention, security and compliance. Matches `AD_ID` in the manifest. (Unlike house apps without ads, the answer here is Yes.) |
| Sign-in details | Not required (all functionality without login) |
| Photo and video permissions | Not applicable: no `READ_MEDIA_*` in the merged manifest |
| Foreground service / full-screen intent / exact alarm | Not applicable. The merged manifest has the base `FOREGROUND_SERVICE` permission (from WorkManager, merged via the ads SDK), but its service declares no `foregroundServiceType` and there is no typed `FOREGROUND_SERVICE_*` permission, so Play's foreground service declaration does not apply. No `USE_FULL_SCREEN_INTENT`, `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM`. **Do not file** any of these. |
| Privacy policy URL | `https://mksoft-ltd.github.io/sides/privacy_policy.html` |

## 7. Content rating (IARC questionnaire)

- Email: info@froggyeye.com. Category: **Reference, News, or Educational** (if the questionnaire shows the older
  wording, the nearest non-game choice; never "Game").
- Violence: the app shows text headlines and short summaries that report real-world violence (war, terrorism,
  crime). **No** images or video of violence. Answer the "news/reference content references violence" item **Yes,
  text references only**; graphic/realistic depictions **No**.
- Sexual content / nudity: **No** (headlines may mention misconduct cases as reporting; no depictions).
- Language: **No** crude language as a feature (outlet headlines are edited copy).
- Controlled substances: text references in news reporting only. Answer a "references" item **Yes** if offered; use, depiction or encouragement **No**.
- Gambling, simulated gambling, real-money: **No**.
- User interaction: users can interact or exchange content **No**; shares location **No**; unrestricted internet
  **No** (articles open in the external browser, user-initiated); digital purchases **Yes** (one-time in-app purchase).
- Expected result: **Teen / PEGI 12 / USK 12** (accept what IARC computes; do not dispute a lower rating).

## 8. Store settings

- App category: **News & Magazines**. Tags (up to 5): News, News aggregator, Politics, World news, Newspapers
  (nearest offered).
- Contact email: info@froggyeye.com. Website: https://sides.froggyeye.com. Phone: optional, leave blank.
- Listing locales: **en-GB (default) and en-US**. Release notes: `changelogs/1.txt` exists for exactly those two
  locales (house-facts §19).
