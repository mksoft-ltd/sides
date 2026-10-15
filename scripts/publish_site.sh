#!/usr/bin/env bash
# Publish pipeline/out/ onto the gh-pages branch (GitHub Pages site).
#
#   scripts/publish_site.sh [--no-push]          local: build the site, commit, push (or leave the commit)
#   scripts/publish_site.sh --stage-only         CI build job: build the site into $SITE_DIR, no git writes;
#                                                the clone's .git is removed so $SITE_DIR is plain files
#   scripts/publish_site.sh --push-only DIR      CI publish job: put the site files from DIR (an artifact) on
#                                                gh-pages, commit and push. Runs no pipeline code at all.
#
# Build (all modes but --push-only):
# 1. clones the gh-pages branch into $SITE_DIR (default .site/, git-ignored); creates it as an orphan if it does not exist
# 2. runs `python -m sides_pipeline.cli publish --site $SITE_DIR` (digest/<date>.json, latest.json, index.json,
#    runs/<date>.json, privacy_policy.html when present, .nojekyll, index.html)
# 3. commits "Digest <date>" and pushes (unless --no-push / --stage-only)
#
# The split exists for security audit SEC-3: in CI the job that holds ANTHROPIC_API_KEY and runs the pipeline's
# third-party Python code has a read-only token, and the job with the write token runs only git.
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
MODE=full
FROM_DIR=
case "${1:-}" in
  --no-push) PUSH=0 ;;
  --stage-only) MODE=stage ;;
  --push-only) MODE=push; FROM_DIR=${2:?--push-only needs the directory holding the built site} ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

clone_site() {
  rm -rf "$SITE_DIR"
  if git clone --quiet --branch "$BRANCH" --single-branch --depth 1 "$SITE_REMOTE_URL" "$SITE_DIR" 2>/dev/null; then
    echo "checked out $BRANCH into $SITE_DIR"
  else
    echo "no $BRANCH branch on the remote yet; creating it as an orphan"
    git init --quiet --initial-branch "$BRANCH" "$SITE_DIR"
    git -C "$SITE_DIR" remote add origin "$SITE_REMOTE_URL"
  fi
}

if [ "$MODE" = push ]; then
  # Publish job: plain files in, no pipeline code. The date comes from the built site itself.
  [ -f "$FROM_DIR/digest/latest.json" ] || { echo "no $FROM_DIR/digest/latest.json — nothing to publish" >&2; exit 1; }
  FROM_DIR=$(cd "$FROM_DIR" && pwd)
  DATE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['date'])" "$FROM_DIR/digest/latest.json")
  clone_site
  # Mirror the built site over the clone; .git stays. The build job started from this same branch, so files it
  # did not touch (older dated digests, a hand-pruned day) are already in FROM_DIR.
  find "$SITE_DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  cp -R "$FROM_DIR"/. "$SITE_DIR"/
else
  DIGEST="$REPO_ROOT/pipeline/out/digest.json"
  [ -f "$DIGEST" ] || { echo "no $DIGEST — run the pipeline first" >&2; exit 1; }
  DATE=$("$PYTHON" -c "import json,sys; print(json.load(open(sys.argv[1]))['date'])" "$DIGEST")
  clone_site

  ARGS=(publish --digest "$DIGEST" --runs-dir "$REPO_ROOT/pipeline/out/runs" --site "$SITE_DIR" --privacy-html "$REPO_ROOT/privacy_policy.html")
  [ -n "${SUMMARY_OUT:-}" ] && ARGS+=(--summary-out "$SUMMARY_OUT")
  (cd "$REPO_ROOT" && "$PYTHON" -m sides_pipeline.cli "${ARGS[@]}")

  if [ "$MODE" = stage ]; then
    rm -rf "$SITE_DIR/.git"
    echo "staged the site for $DATE in $SITE_DIR (no commit, no push)"
    exit 0
  fi
fi

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
