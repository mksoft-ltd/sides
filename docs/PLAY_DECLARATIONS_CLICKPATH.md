# Play Console declarations: click-path for Sides (run after the AAB is in internal testing)

Answers are in `android/fastlane/data_safety_answers.md` (section numbers below point there). This file only maps
them onto the console, in the order to do them. Prepared 15 Oct 2026 by store-publisher; not yet run.

Account: Chrome profile **froggyeye.ltd@gmail.com** (`/u/2/`), developer `7290847462815639528`, app
`4973894667859335790`. Start every section from the App content overview; deep links often bounce to Home
(house-facts §22):

    https://play.google.com/console/u/2/developers/7290847462815639528/app/4973894667859335790/app-content

Checkbox and radio state must be set with real clicks, not form_input (§22). Each section ends with **Save**; re-open
it once to confirm the answers stuck.

| # | Console page (App content → …) | What to enter | Answer source |
|---|---|---|---|
| 1 | Privacy policy | `https://mksoft-ltd.github.io/sides/privacy_policy.html` | §6 |
| 2 | App access | "All functionality is available without any access restrictions" | §3 |
| 3 | Ads | "Yes, my app contains ads" | §2 |
| 4 | Content rating → Start questionnaire | Email info@froggyeye.com; category "Reference, News, or Educational"; violence = text references only; sexual content No; language No; controlled substances = references only; gambling No; user interaction No; shares location No; digital purchases **Yes**; accept the computed rating (expected Teen / PEGI 12). Ticking the IARC terms is a legal acceptance: founder OK needed. | §7 |
| 5 | Target audience and content | Age groups 13–15, 16–17, 18+ (no under-13); "appeal to children" No | §4 |
| 6 | News apps | "Yes, my app is a news app"; publisher Froggy Eye Ltd; website `https://sides.froggyeye.com`; contact info@froggyeye.com. Check the site returns 200 just before. | §5 |
| 7 | Data safety | Overview: collects/shares Yes; encrypted in transit Yes; deletion request No; no accounts. Data types: Approximate location, App interactions, Crash logs, Diagnostics, Device or other IDs — each collected **and** shared, not ephemeral, required, purposes per §1 table. Everything else not collected. Preview → Save. (Alternative: Play's dataSafety API takes the CSV template, but has no GET to verify, so the console read is still needed.) | §1 |
| 8 | Government apps | No | §6 |
| 9 | Financial features | "My app doesn't provide any financial features" | §6 |
| 10 | Health | "My app does not have any health features" | §6 |
| 11 | Advertising ID | **Yes**; purposes Advertising or marketing, Analytics, Fraud prevention/security/compliance. This is the hidden "quick checks" blocker if skipped. | §6 |
| 12 | Store settings (Grow → Store presence → Store settings) | Category **News & Magazines**; tags News, Politics, World news (nearest offered); contact email/website already set by API (read back 15 Oct). | §8 |
| 13 | Countries / regions (Production → Countries/regions) | Only needed for the production release, not internal testing. Empty by default: add all, consider excluding mainland China to match Apple (not sold on Play there anyway). | checklist §4 |
| 14 | Publishing overview | Only after the founder confirms submission: "Send N changes for review". Then wait for "Your changes are now in review". | — |

Not filed (do not open): foreground service, full-screen intent, exact alarm, photo/video permissions (§6).
Already done by API: listing text, graphics, screenshots, contact details. The in-app product follows the AAB upload
(`scripts/publish/play_iap.rb`).
