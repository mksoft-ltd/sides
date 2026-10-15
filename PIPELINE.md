# PIPELINE.md — Sides: The News, Every Angle

Store records (14 Oct 2026): ASC app 6822909350 · Play app 4973894667859335790 · bundle/package `com.froggyeye.sides` · website slug `sides`.
Approved architecture plan: `~/.claude/plans/curried-herding-yao.md` (copied into `docs/PRODUCT_SPEC.md` at stage 1).
Founder decisions 14–15 Oct 2026: Claude Opus 5.5 for the daily pipeline at full settings — cost lever declined 15 Oct, keep ~$1.35/day (~£32/mo); free app with AdMob banners + ad-free IAP `com.froggyeye.sides.adfree`; West/East axis with East–West contradictions; iPad/tablet supported.

| # | Stage | Status | Date | Notes |
|---|-------|--------|------|-------|
| 1a | build: pipeline phase 1 (collect) | done | 2026-10-14 | 45 tests, socket guard; 29 live outlets (7 dead feeds kept disabled with notes), 726 articles in sample; commits 909bbd0, 0f04255 |
| 1b | build: pipeline phase 2 (group) | done | 2026-10-14 | 75 tests; live run 10 stories from 723 articles, grouping $0.53 (84k in/9.6k out); commit f37d659 |
| 1c | build: pipeline phase 3 (analyse) | done | 2026-10-14 | 117 tests; 10 stories analysed, 318 items kept / 0 dropped, analysis $0.83 → day total $1.35; commits 198c5a0, 7495b09 (quote `field` = headline/snippet: 87/38 today); 120 tests |
| 1d | build: phone app (phase 4) | done | 2026-10-15 | analyze clean, 65 tests, apk + xcodebuild sim builds OK (note: `flutter build ios --simulator` lipo step fails on Xcode 27 — use archive/xcodebuild); screenshots docs/screenshots/phase4; commits 89e0e07 cd2c90f 2c11f72 |
| 1e | build: tablet layout (phase 5) | done | 2026-10-15 | 85 tests; master-detail ≥744dp (all iPads, both orientations); 90 tests; commit 71a95fc; columns ≥1100dp; iPad screenshots docs/screenshots/phase5; commits f82ec19 157b14b 959978b |
| 1f | build: deployment (phase 6) | done | 2026-10-15 | daily.yml 06:00 UTC + ci.yml; gh-pages live at https://mksoft-ltd.github.io/sides/digest/latest.json; first run $1.34; 128 pipeline tests; commits 74c2e5f ddfaa79 |
| 2 | design | done | 2026-10-15 | BRAND.md, cube icon wired both platforms (apk + Runner.app verified), icon_512, feature graphic, screenshot specs + headlines; 6 polish items listed in BRAND.md for the fix round; commit 6469a3f |
| 3 | test | in-progress | 2026-10-15 | mobile-qa-architect |
| 4a | code-review | pending | | mobile-code-reviewer |
| 4b | security | pending | | mobile-security-auditor |
| 5 | metadata | pending | | growth-monetization → release-manager |
| 6 | compliance | pending | | app-store-review-auditor |
| 7 | publish | pending | | store-publisher; AdMob IDs + IAP product are console items |
| 8 | website | pending | | froggyeye.com `sides` subdomain |
