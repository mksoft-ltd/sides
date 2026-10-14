# PIPELINE.md — Sides: The News, Every Angle

Store records (14 Oct 2026): ASC app 6822909350 · Play app 4973894667859335790 · bundle/package `com.froggyeye.sides` · website slug `sides`.
Approved architecture plan: `~/.claude/plans/curried-herding-yao.md` (copied into `docs/PRODUCT_SPEC.md` at stage 1).
Founder decisions 14 Oct 2026: Claude Opus 5.5 for the daily pipeline (paid, ~£18/mo); free app with AdMob banners + ad-free IAP `com.froggyeye.sides.adfree`; West/East axis with East–West contradictions; iPad/tablet supported.

| # | Stage | Status | Date | Notes |
|---|-------|--------|------|-------|
| 1a | build: pipeline phase 1 (collect) | done | 2026-10-14 | 45 tests, socket guard; 29 live outlets (7 dead feeds kept disabled with notes), 726 articles in sample; commits 909bbd0, 0f04255 |
| 1b | build: pipeline phase 2 (group) | in-progress | 2026-10-14 | general-purpose agent; key in Keychain (anthropic-api-key/sides) + GH secret |
| 1c | build: pipeline phase 3 (analyse) | pending | | |
| 1d | build: phone app (phase 4) | pending | | flutter-architect |
| 1e | build: tablet layout (phase 5) | pending | | flutter-architect |
| 1f | build: deployment (phase 6) | pending | | GitHub Actions cron + Pages, secret via `gh secret set` |
| 2 | design | pending | | ui-designer |
| 3 | test | pending | | mobile-qa-architect |
| 4a | code-review | pending | | mobile-code-reviewer |
| 4b | security | pending | | mobile-security-auditor |
| 5 | metadata | pending | | growth-monetization → release-manager |
| 6 | compliance | pending | | app-store-review-auditor |
| 7 | publish | pending | | store-publisher; AdMob IDs + IAP product are console items |
| 8 | website | pending | | froggyeye.com `sides` subdomain |
