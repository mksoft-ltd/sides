# Sides: The News, Every Angle — ASO, pricing and growth

Stage 5a (growth-monetization), 15 Oct 2026. Consumed by release-manager (store text in `ios/fastlane/metadata/`,
`android/fastlane/metadata/android/`) and store-publisher (IAP price, categories).
Inputs: `docs/PRODUCT_SPEC.md`, `store_assets/BRAND.md`, `pipeline/config/outlets.yaml` (36 rows, 7 disabled = **29 live
outlets**), phase-4/5 screenshots, and live store data pulled 15 Oct 2026 (iTunes Search API GB + US, Google Play GB
search and listing pages). Ratings counts below are from those pulls.

Settled, not re-opened here: name, bundle/package `com.froggyeye.sides`, free with AdMob banners + non-consumable
`com.froggyeye.sides.adfree`, no accounts, no analytics, support/marketing URL `https://sides.froggyeye.com`, privacy URL
`https://mksoft-ltd.github.io/sides/privacy_policy.html`.

---

## 1. Store text (ready to use)

### App Store

| Field | Value | Length |
|---|---|---|
| Name | `Sides: The News, Every Angle` | 28 / 30 |
| Subtitle | `Compare left & right headlines` | 30 / 30 |
| Keywords | `bias,media,blindspot,balanced,perspectives,political,centre,center,world,daily,digest,coverage,press` | 100 / 100 |
| Primary category | News | |
| Secondary category | Education | |

Why this subtitle:
- It adds three indexed words the name lacks (`compare`, `left`/`right`, `headlines`) and says exactly what the screens show:
  real headline quotes grouped by lean.
- The `compare … headlines` shelves are empty on both storefronts. GB `compare left right headlines` returns general
  news apps (Opera News, The Times, Google News) with only NewsCord (23 ratings) on topic. US `compare left right` returns
  image-diff tools and a kids' left/right game. Per the empty-shelf rule, that is free ranking.
- §31 check: the iTunes Search API shows no other developer branded on this phrase. Nothing in it addresses children.
- Fallback if the founder wants West/East in the subtitle: `Left, right, West and East` (26). It reads well but loses
  `compare` and `headlines`, and the `west east news` shelf is an intent trap (see §2).

Keyword field rules followed:
- No word repeated from name or subtitle (Apple already combines across the three fields, so `news` + `bias` matches
  "news bias", `media` + `bias` matches "media bias", `daily` + `news` matches "daily news").
- No competitor names (Guideline 2.3.7). `ground`, `allsides`, `factual` are deliberately absent.
- `bias` and `balanced` appear **only** in the hidden keywords field. BRAND.md bans them from displayed copy, and the
  hidden field is not shown to anyone (same reasoning as house-facts §31). They are the words this audience actually
  types. If the founder wants the ban to cover the hidden field too, swap them for `spectrum,source` (still ≤100).
- `centre` and `center` both, because the US storefront is targeted and Apple does not fold spellings.

### Google Play

| Field | Value | Length |
|---|---|---|
| Title | `Sides: The News, Every Angle` | 28 / 30 |
| Short description | `See how left, right, West and East outlets cover the same stories, once a day` | 77 / 80 |
| Category | News & Magazines | |
| Tags (store settings, up to 5) | News, News aggregator, Politics, World news, Newspapers (pick the nearest offered) | |

Play has no keyword field: it indexes title, short description and long description. The long description therefore
has to carry the head terms in natural sentences. Release-manager should work these in, once each, never as a list:
"media-bias ratings" (the sanctioned use, naming AllSides / Ad Fontes as the rating sources), "compare headlines",
"political lean", "blindspot", "left, centre and right", "Western and Eastern outlets", "daily news digest",
"state media" (as the label, explaining CGTN etc. are shown and tagged, never endorsed).

### Description angles (release-manager writes the copy)

In this order, each true of the shipped product:
1. **Once a day, the top 5–10 stories, each covered by at least three outlets.** Generated centrally every morning; the
   app downloads one file and works offline afterwards.
2. **See how each side words it.** Real headline and snippet quotes from left, centre and right outlets, labelled by
   outlet. Coverage bars show who covered each story.
3. **Blindspots.** "Only left-leaning outlets covered this" / "Only Western outlets covered this".
4. **West and East.** About 29 English-language outlets, including Western, Middle Eastern, Indian, Chinese, Japanese
   and Korean outlets. State-controlled outlets carry a visible "state media" tag. East–West contradictions are listed
   when the day has them, and the app says "none found" when it does not. Say this in prose; no screenshot can show one
   honestly yet (BRAND.md).
5. **What all sources agree on, what each side leaves out, contested claims, opinion kept separate.**
6. **Every point links to its source.** Tap a chip to read the original on the outlet's own site. Sides shows headlines
   and short summaries only, never article text.
7. **Method and limits, stated plainly.** Lean ratings come from public media-bias rating services and are listed per
   outlet in the app. The analysis is generated automatically, and every point that cannot be traced to a headline or
   summary is dropped before publication. Sides does not rate accuracy or judge outlets.
8. **Business model.** Free with a small banner; one purchase removes ads for good. No account, no tracking, no
   subscription. Never write "no ads" for this app.

Required disclosure: the analysis is AI-generated. Say so in the description ("generated automatically by an AI model
from headlines and short summaries"). Hiding it is the single fastest way to lose this audience's trust, and both
stores are tightening on undisclosed AI content.

Banned in displayed copy (BRAND.md): bias/biased/unbiased, fake news, propaganda, spin, the truth, misinformation,
all/every outlet, #1, best, trusted, award. Also avoid "every side" and "every story" together: see §3.

---

## 2. Keyword research

Graded by page-one quality on the live stores (15 Oct 2026). "Ratings" = the incumbent's App Store rating count on that
storefront.

| Query | GB shelf | US shelf | Grade | Where it goes |
|---|---|---|---|---|
| media bias | Ad Fontes (3), NewsCord (23), AllSides (7), Ground News (3,284) | Ad Fontes (63), Ground News (48.5k), AllSides (300), Straight Arrow (9.8k) | **Target.** Thin in GB, only Ground News is strong | keywords `media`+`bias`; Play long desc "media-bias ratings" |
| news bias | AllSides, NewsCord, Ground News, then BBC/Sky | same set + MxM, Reuters | **Target** | name `news` + keyword `bias` |
| compare headlines / compare news | NewsCord only on topic, rest general news | general news, image-compare tools | **Target hard**: empty shelf | subtitle |
| blindspot news | Ground News, then Daily Mail/Times | US `blindspot` = a car-spotting game, a camera map, Ground News | **Target**: Ground News owns the term but nobody else does | keyword `blindspot`; desc |
| balanced news | AllSides (7), The Balanced News (0), Morning Coffee (4) | AllSides (300), several 0-rating apps | **Target**: every rival at near-zero ratings | keyword `balanced` |
| both sides news / news from all sides | AllSides, Straight Arrow, Drooid (6) | Drooid (58), Factlen (0), AllSides | **Target** via `sides` in name | name |
| news perspectives | general news only | general news only | **Target**: empty | keyword `perspectives` |
| daily news digest | SaySo (6), Rize (5), then general | similar | Medium: AI-digest crowd | keywords `daily`,`digest` |
| political lean | — | political sim games, Goods Unite Us | **Intent trap**: games | keep `political` only for "political news" |
| west east news | East Anglian, East Idaho, local TV | local US TV stations | **Intent trap**: regional news | not targeted; West/East lives in description and screenshots |
| sides | Side+ (Sidemen), Google Slides, games | similar | Brand term, no news app named Sides | name only |
| every angle | — | a 0-rating camera app "Every Angle", protractors | Irrelevant shelf | name only |

Takeaways:
- In the UK the whole niche is unclaimed: AllSides has 7 ratings, Ad Fontes 3, NewsCord 23. Ground News (3,284 GB /
  48.5k US) is the only established player. A well-reviewed UK-English app can reach page one for `media bias`,
  `balanced news` and `compare headlines` in GB within weeks.
- In the US, Ground News, Straight Arrow and AllSides hold the head terms. Aim at the long tail (`compare headlines`,
  `news perspectives`, `blindspot`) and the West/East angle nobody else offers.

---

## 3. Competitors and our honest position

| App | Stores (ratings) | Model | What it does | Our angle against it |
|---|---|---|---|---|
| **Ground News** (Snapwise) | iOS 48.5k US / 3.3k GB; Play 32.9k | Free tier + subscriptions: Pro ≈ $9.99/yr, Premium ≈ $29.99–39.99/yr, Vantage ≈ $99.99/yr | Aggregates thousands of sources, bias + factuality + ownership ratings per story, "Blindspot" feed | Ground News is broader and live. Sides is narrower and deeper: a fixed daily set of top stories, each broken into quoted wording per side, agreed facts, omissions and contested claims, all sourced. Sides adds a West/East axis with state-media labels. One small purchase instead of a subscription. |
| **AllSides** | iOS 300 US / 7 GB; Play 368, contains ads | Free with ads; web membership | Left/Centre/Right story trios, media-bias ratings | AllSides shows three articles side by side. Sides shows how the wording differs and what each side leaves out, plus West/East. AllSides is US-centric; Sides is UK + US + international. |
| **The Factual** (Yahoo) | No standalone app; ratings folded into Yahoo News since 2022 | — | Article credibility scores | Sides does not score credibility. Do not position on it. |
| **Improve the News** → now **Verity News** | iOS 59 US | Free | Multi-perspective summaries with sliders | Similar spirit, small install base. Sides wins on UK coverage and the West/East axis. |
| Others in the shelf | Straight Arrow (9.8k US, a news outlet), NewsCord (23/110), Drooid (58), Ad Fontes chart (63; Play category Education), The Bias "Wide-Angle News" (1), several 0-rating AI "balanced news" apps | | | Mostly AI-summary apps with no sources shown. "Every point links to its source" is the separator. |

Positioning line for all channels: **the same top stories, read side by side, with every point linked to the headline it
came from.** Never claim to be more accurate, fairer or more complete than any rival; this audience punishes that.

**Slogan proximity, action needed:** Ground News's Play short description is "See every side of every story". Our phone
screenshot 1 headline in BRAND.md is "Every story, every angle". That is close enough to read as an echo of a rival's
tagline, and it invites a "copycat" comment in exactly the communities we need. The name is fine, since "every angle"
is not their phrase. Recommend design swaps screenshot 1's headline to one of:
1. `Today's top stories, side by side` (preferred: matches the subline and the product)
2. `One story, told many ways`

This is a BRAND.md and `screenshots/specs.json` change owned by ui-designer; this stage did not edit either.

---

## 4. Categories

| Store | Primary | Secondary | Reasoning |
|---|---|---|---|
| App Store | **News** | **Education** | Every rival sits in News; that is where the searches happen. Magazines & Newspapers is for publications and readers of specific titles; Sides publishes no journalism of its own, so it would be misfiled there. Education fits the student, teacher and media-literacy use (spec target users) and is a far less crowded browse shelf. |
| Google Play | **News & Magazines** | (Play has one category) | The only sensible fit. Ad Fontes sits in Education on Play, but Sides is a daily reading app, not a reference chart. |

---

## 5. Age rating and content declarations (expectations)

- **Apple:** expect **13+** under the current questionnaire. Headlines routinely mention war, terrorism, crime and
  medical subjects. Answer "Infrequent/Mild" for realistic violence and mature/suggestive themes. Answer **No** to
  unrestricted web access: articles open in the external browser, not an in-app web view. No user-generated content,
  no chat, no gambling. Declare in-app purchases and advertising.
- **Google Play (IARC):** expect **Teen / PEGI 12** for the same reasons. Choose the reference/news-style app path
  where the questionnaire offers it; no UGC, no user interaction, no location sharing. Declare "Contains ads".
- **Play "News apps" declaration (App content):** answer **Yes**. Google's News policy then requires the app and
  listing to show who publishes it (Froggy Eye Ltd), a contact (info@froggyeye.com) and where the content comes from.
  The in-app "How it works" and "Outlets and ratings" pages cover sources; confirm the publisher line and contact are
  visible in Settings/About and on sides.froggyeye.com.
- **Apple availability:** exclude **mainland China**. News apps there need a government licence, and the content
  quotes Chinese state media critically alongside Western outlets. Every other storefront is fine, but the copy is UK + US
  English, so the effort goes there.
- Not for the Kids category; no kid vocabulary anywhere (house-facts §31). Nothing in this plan uses any.

---

## 6. Ad-free purchase price

**Decision: £2.99 / $2.99, one-time non-consumable `com.froggyeye.sides.adfree`.** Keep the in-app placeholder.

Reasoning:
- **What a buyer saves.** A daily reader sees roughly 3–6 banner impressions a day. Non-personalised UK/US banner eCPM
  is low, about $0.20–$0.80. That is about $0.30–$1.50 of ad revenue per daily reader per year. £2.99 nets about £2.12
  after UK VAT and the 15% small-business commission, which is roughly 2–5 years of that reader's banner revenue. The
  purchase is strictly better for the studio than the ads it removes.
- **Anchor.** The only paid rival with scale, Ground News, charges ≈ $9.99/yr at its lowest tier and recurring after
  that. £2.99 once is clearly cheaper than year one of a subscription, which is a message we can state without naming
  them: "one purchase, no subscription".
- **Impulse band.** £1.99–£2.99 is the no-deliberation band for removing a banner. £3.99–£4.99 starts reading as
  "premium features", and this purchase unlocks no features. A higher price would need a feature gate, which this plan
  does not recommend (see below).
- **Revision path.** Raising a non-consumable's price later is safe: no consent flow, existing owners keep it. Review at
  day 90. If ad-free conversion exceeds about 4% of monthly installs and refund requests are rare, move to £3.99 / $3.99.
- **Do not gate analysis behind payment.** The West/East axis, blindspots and sources are the reasons to install and to
  recommend the app. Gating them would cut word-of-mouth, the main growth channel for a no-UA studio.

Store mechanics:
- Apple: set the United Kingdom as the base storefront at £2.99 and set the United States explicitly to $2.99. Accept
  Apple's equalised prices elsewhere.
- Play: set GBP £2.99 and USD $2.99 explicitly. If using `convertRegionPrices`, feed tax-exclusive input: £2.49
  (house-facts §18).
- Apple review: the first non-consumable must ride the version's submission. Add it from the IAP's own page and verify
  **2 items** before submitting (house-facts §15).

Honest economics:
- The daily pipeline costs about $1.35/day, roughly £32/month (founder decision, 15 Oct 2026).
- Break-even needs about 15 ad-free sales a month at £2.99 net, before any banner revenue.
- At the portfolio's current organic run-rate, that needs roughly 400–500 installs a month at 3% conversion.
- Plan on running at a small loss for the first months. The levers, in order, are ASO, the community launch (§7), then
  a price review at day 90. The pipeline model downgrade was offered and declined; it stays the founder's call.

| Monthly installs | Ad-free buyers (3%) | IAP net | Banner revenue (≈30% become weekly readers) | Total vs £32 cost |
|---|---|---|---|---|
| 150 | 4–5 | ≈ £10 | ≈ £1–3 | −£19 |
| 500 | 15 | ≈ £32 | ≈ £4–10 | ≈ break-even |
| 1,500 | 45 | ≈ £95 | ≈ £12–30 | +£75–95 |

---

## 7. Launch and growth plan (one-person studio, no paid UA)

### Short term (0–6 months)

1. **ASO as above** on both stores, then use Play **store listing experiments** and Apple **Product Page Optimization**
   (both free) to test screenshot 1 and the short description. One test at a time, at least two weeks each.
2. **sides.froggyeye.com.** Make it more than a store link:
   - A plain "How Sides works" page: feeds only, ≤200-character summaries, the citation validator, lean ratings and
     their sources, the West/East axis and why state media is labelled rather than excluded.
   - The outlet list with each rating source.
   - "Today's digest" rendered from the public `digest/latest.json`, which gives the page fresh, indexable text every day.
   - Also host a copy of `app-ads.txt` at `https://sides.froggyeye.com/app-ads.txt`. AdMob checks the developer website
     listed on the store, and the listing will point at the subdomain. The studio file is verified on froggyeye.com,
     but confirm AdMob's app-ads.txt status reads "found" once the app is linked.
3. **Hacker News "Show HN".** The strongest single fit. Lead with the method: an LLM pipeline whose output is rejected
   unless every point quotes a headline verbatim, the cost per day, and the West/East axis. Post on a weekday morning US
   Eastern time, stay in the thread all day, and answer criticism of lean ratings plainly.
4. **Reddit, value-first and within each sub's rules.** Most news subs ban self-promotion, so read the rules first and
   never post the same text twice.
   - r/SideProject and r/IMadeThis: direct launch posts are allowed. r/AppHookup only if the ad-free purchase is ever
     made temporarily free, since that sub is for deals.
   - r/FlutterDev: a build write-up (master-detail tablet layout, offline-first digest cache), app link at the end.
   - r/MediaLiteracy, r/journalism: a "how outlets headlined X" comparison as content, not an ad.
   - Do **not** post in r/ukpolitics, r/politics, r/NeutralPolitics or r/neutralnews as promotion. They remove it and it
     brands the app partisan.
5. **Product Hunt** once there are about 20 ratings. Bluesky and Mastodon journalism and media-literacy circles: share
   one interesting day's comparison with a screenshot, no hard sell.
6. **Teachers.** Media literacy is on UK citizenship and English curricula. A one-page "using Sides in a lesson"
   PDF on the site, shared in teacher communities, fits the Education secondary category.

### Medium term (6–18 months)

- **Weekly "how the week was framed" post** on froggyeye.com, built from `digest/index.json`. Five topic examples:
  1. One story, five headlines: how left, centre and right outlets worded the same announcement.
  2. What the West covered that the East did not this week, and the reverse.
  3. Blindspots of the month: stories only one side covered.
  4. How state media framed a summit compared with public broadcasters.
  5. Words that differ: "migrants" vs "asylum seekers", "strike" vs "attack", counted across a month of headlines.
- **Share a story link** (already on the spec's "later" list). The single best product-led growth feature. Every shared
  link should land on a sides.froggyeye.com web view of that story with the store badges.
- **Archive of past days** (spec "later"), so the app is useful for revision, research and lessons.
- **Featuring.** Apple's News editorial favours apps with a clear civic purpose and good iPad layouts. Pitch through the
  App Store "Featuring nominations" in ASC with the iPad columns and the sourcing method. Elections and big summits are
  natural pitch windows.

### Long term (18+ months)

- More outlets and regions (Africa, Latin America in English), if the pipeline cost allows.
- An educational licence or classroom edition, only if teachers ask for it.
- Optional "Supporter" tip IAPs (consumable) as a way to fund the pipeline, never a feature gate.

---

## 8. Retention hooks

What the shipped product already has:
- **A daily reason to return.** A new digest lands every morning at 06:00 UTC, so the list changes each day and the
  app revalidates on launch and resume.
- **Blindspot chips.** Small, surprising findings that make people open a story.
- **West/East.** The one view no rival offers. It is what people will mention when they recommend the app.
- **Offline cache.** The app opens instantly with the last digest, which builds a commute habit.

Recommended next, in priority order:

| Feature | Complexity | Revenue impact | Priority |
|---|---|---|---|
| Opt-in daily local notification "Today's stories are ready" at a user-chosen time (flutter_local_notifications, no backend, off by default, asked after the 3rd day of use) | Low | Daily active users drive banner revenue and ad-free intent | HIGH revenue potential |
| Share a story link with a web landing page | Medium | Main organic acquisition loop | HIGH revenue potential |
| Archive of past days | Medium | Retention for students and researchers | MEDIUM opportunity |
| iOS widget showing today's top story and its coverage bar | Medium | Retention, featurability | EXPERIMENTAL |
| "Read all sides" counter: stories where you opened more than one side's tab, stored locally | Low | Gentle habit loop; no streak pressure | EXPERIMENTAL |

No streaks that punish missed days, no badges, no nagging. They fit neither this audience nor the brand.

---

## 9. Metrics to watch (no analytics SDK, consoles only)

| Metric | Where | Target / trigger |
|---|---|---|
| Product page conversion (impressions → installs) | ASC App Analytics, Play Console Store performance | Over 25% for search traffic; below 15% means the screenshots or subtitle fail |
| Search terms driving installs | Play Console "Search terms" (acquisition report) | Expect `media bias`, `balanced news` in GB; re-cut the keyword field at day 30 |
| Retention D1 / D7 / D28 | ASC (opted-in users), Play "Retained installers" | D7 above 20% for a daily app; below 10% means the digest is not earning a return |
| Ratings count and average | Both stores | Wait for 20+ ratings before Product Hunt. Watch for "biased" reviews and reply calmly with the method |
| Ad-free conversion | ASC Sales and Trends, Play Order management | 2–5% of monthly installs; above 4% triggers the £3.99 review |
| Banner fill, eCPM, match rate | AdMob | Fill under 80% means check SKAdNetwork and app-ads.txt (below) |
| Pipeline cost per day | Daily run summary / `runs/<date>.json` | About $1.35; compare with monthly revenue each month |
| Digest freshness | `digest/latest.json` date | Must be today; a stale digest kills retention fastest of all |

---

## 10. Experiments to run

1. Screenshot 1 headline A/B on Play: "Today's top stories, side by side" vs "One story, told many ways".
2. Short description: method-led ("…every point linked to its source") vs comparison-led (current) on Play.
3. Apple PPO: tablet-columns screenshot first vs phone digest first on iPad product page.
4. Price review at day 90: £2.99 vs £3.99, as a straight change, since neither store A/B tests IAP prices natively.

---

## 11. Risks to avoid

- **Any judgement word in displayed copy.** One "unbiased" in a description and the comment sections fill with
  "this is biased" replies. Describe the method; never grade outlets.
- **Echoing Ground News's tagline** (§3).
- **Overclaiming the AI.** Say it is generated automatically and every point is checked against a headline or summary.
  Never say "verified", "fact-checked" or "accurate".
- **Stale digest.** If the daily job stops (GitHub's 60-day schedule rule is mitigated in daily.yml), the app shows
  yesterday's news. That is the main churn risk.
- **State media.** Reviewers or users may ask why CGTN is included. The answer must be in the description and on the
  site: it is labelled "state media" and shown for comparison. RT, Sputnik and Press TV are excluded by design.
- **Ads drifting into content.** Banner stays in the bottom bar only, never interstitials. An interstitial between
  stories would break the reading tool positioning.

---

## 12. Notes for release-manager and store-publisher

- Name 28 chars, subtitle 30, keywords 100, Play short description 77: all within limits as written above.
- Copy is British English; the US listing can reuse it (only `centre`/`center` matters, and the keyword field covers both).
- "Contains ads" + "In-app purchases" on Play; ads and IAP declared on Apple. Privacy labels follow
  `docs/audits/security.md` (AdMob data, not used for tracking), not "No data collected".
- AdMob health checks for the publish stage:
  - Info.plist holds **50** SKAdNetwork IDs. Google's current list is longer. Refresh it from Google's quick-start page
    before release and keep any non-Google entries.
  - Replace the test `GADApplicationIdentifier`, Android `APPLICATION_ID` and unit IDs (spec release to-dos); check that
    iOS and Android unit IDs are not cross-wired.
  - app-ads.txt on sides.froggyeye.com (§7).
- Screenshot 1 headline change is recommended to design (§3); everything else in BRAND.md's headline tables is
  consistent with this plan.
