#!/usr/bin/env bash
# Publish pipeline/out/ onto the gh-pages branch (GitHub Pages site).
#
#   scripts/publish_site.sh [--no-push]
#
# 1. clones the gh-pages branch into $SITE_DIR (default .site/, git-ignored); creates it as an orphan if it does not exist
# 2. runs `python -m sides_pipeline.cli publish --site $SITE_DIR` (digest/<date>.json, latest.json, index.json,
#    runs/<date>.json, privacy_policy.html when present, .nojekyll, index.html)
# 3. commits "Digest <date>" and pushes (unless --no-push)
#
# Env: SITE_DIR, SITE_REMOTE_URL (default: origin of this repo; CI passes a token URL), PYTHON (default: python),
#      SUMMARY_OUT (optional path for the Markdown run summary — CI passes $GITHUB_STEP_SUMMARY),
#      GIT_AUTHOR_NAME/GIT_AUTHOR_EMAIL/GIT_COMMITTER_* (git's own variables; CI sets the Actions bot identity).
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SITE_DIR=${SITE_DIR:-$REPO_ROOT/.site}
SITE_REMOTE_URL=${SITE_REMOTE_URL:-$(git -C "$REPO_ROOT" remote get-url origin)}
PYTHON=${PYTHON:-python}
BRANCH=gh-pages
PUSH=1
[ "${1:-}" = "--no-push" ] && PUSH=0

DIGEST="$REPO_ROOT/pipeline/out/digest.json"
[ -f "$DIGEST" ] || { echo "no $DIGEST — run the pipeline first" >&2; exit 1; }
DATE=$("$PYTHON" -c "import json,sys; print(json.load(open(sys.argv[1]))['date'])" "$DIGEST")

rm -rf "$SITE_DIR"
if git clone --quiet --branch "$BRANCH" --single-branch --depth 1 "$SITE_REMOTE_URL" "$SITE_DIR" 2>/dev/null; then
  echo "checked out $BRANCH into $SITE_DIR"
else
  echo "no $BRANCH branch on the remote yet; creating it as an orphan"
  git init --quiet --initial-branch "$BRANCH" "$SITE_DIR"
  git -C "$SITE_DIR" remote add origin "$SITE_REMOTE_URL"
fi

ARGS=(publish --digest "$DIGEST" --runs-dir "$REPO_ROOT/pipeline/out/runs" --site "$SITE_DIR" --privacy-html "$REPO_ROOT/privacy_policy.html")
[ -n "${SUMMARY_OUT:-}" ] && ARGS+=(--summary-out "$SUMMARY_OUT")
(cd "$REPO_ROOT" && "$PYTHON" -m sides_pipeline.cli "${ARGS[@]}")

cd "$SITE_DIR"
git add -A
if git diff --cached --quiet; then
  echo "site unchanged; nothing to commit"
  exit 0
fi
git commit --quiet -m "Digest $DATE"
git --no-pager log -1 --stat --format='%h %s'
if [ "$PUSH" = 1 ]; then
  git push --quiet origin "HEAD:$BRANCH"
  echo "pushed $BRANCH"
else
  echo "--no-push: left the commit in $SITE_DIR"
fi
