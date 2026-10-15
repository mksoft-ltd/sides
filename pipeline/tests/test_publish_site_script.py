"""SEC-9 (security re-verification): `publish_site.sh --push-only` treats the staged site as untrusted.

The staged site is an artifact from the build job, which runs third-party code. The publish job holds the
write token, so nothing in that artifact may make git execute code: a planted .git/hooks/pre-commit, a stray
dotfile or anything off the allow-list aborts the run before git is touched, and every git call runs with
core.hooksPath=/dev/null. These tests drive the real script against local repos only (no network)."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "publish_site.sh"
IDENT = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}

pytestmark = pytest.mark.skipif(shutil.which("git") is None or shutil.which("bash") is None, reason="needs git + bash")


def _git(*args, cwd=None):
    return subprocess.run(["git", "-c", "core.hooksPath=/dev/null", *args], cwd=cwd, check=True,
                          capture_output=True, text=True, env={**os.environ, **IDENT}).stdout.strip()


@pytest.fixture
def remote(tmp_path):
    """A bare repo with a gh-pages branch holding yesterday's site."""
    work = tmp_path / "seed"
    work.mkdir()
    _git("init", "-q", "--initial-branch", "gh-pages", cwd=work)
    (work / "digest").mkdir()
    (work / "digest" / "2026-10-14.json").write_text('{"date": "2026-10-14"}')
    _git("add", "-A", cwd=work)
    _git("commit", "-q", "-m", "seed", cwd=work)
    bare = tmp_path / "remote.git"
    _git("clone", "-q", "--bare", str(work), str(bare))
    return bare


def _staged(tmp_path) -> Path:
    d = tmp_path / "staged"
    (d / "digest").mkdir(parents=True)
    (d / "runs").mkdir()
    for name in ("2026-10-14.json", "2026-10-15.json"):
        (d / "digest" / name).write_text('{"date": "%s"}' % name[:10])
    (d / "digest" / "latest.json").write_text('{"date": "2026-10-15"}')
    (d / "digest" / "index.json").write_text("[]")
    (d / "runs" / "2026-10-15.json").write_text("{}")
    (d / "index.html").write_text("<html></html>")
    return d


def _push_only(tmp_path, remote, staged, extra_env=None):
    env = {**os.environ, **IDENT, "SITE_DIR": str(tmp_path / "site"), "SITE_REMOTE_URL": str(remote), **(extra_env or {})}
    return subprocess.run(["bash", str(SCRIPT), "--push-only", str(staged)], env=env, capture_output=True, text=True)


def _head(remote):
    return _git("--git-dir", str(remote), "rev-parse", "gh-pages")


def test_a_clean_staged_site_is_published_with_nojekyll(tmp_path, remote):
    before = _head(remote)
    r = _push_only(tmp_path, remote, _staged(tmp_path))
    assert r.returncode == 0, r.stderr
    assert _head(remote) != before
    files = set(_git("--git-dir", str(remote), "ls-tree", "-r", "--name-only", "gh-pages").splitlines())
    assert {"digest/2026-10-15.json", "digest/latest.json", "runs/2026-10-15.json", "index.html", ".nojekyll"} <= files


def test_a_planted_pre_commit_hook_is_refused_and_never_runs(tmp_path, remote):
    staged = _staged(tmp_path)
    marker = tmp_path / "HOOK-RAN-WITH-WRITE-TOKEN"
    hooks = staged / ".git" / "hooks"
    hooks.mkdir(parents=True)
    (hooks / "pre-commit").write_text(f"#!/bin/sh\ntouch {marker}\n")
    (hooks / "pre-commit").chmod(0o755)
    before = _head(remote)
    r = _push_only(tmp_path, remote, staged)
    assert r.returncode != 0 and "refusing" in r.stderr
    assert not marker.exists()
    assert _head(remote) == before


@pytest.mark.parametrize("stray", [".env", ".gitattributes", "digest/.gitmodules", "notes.txt", "digest/x/deep.json"])
def test_a_stray_or_off_list_file_is_refused(tmp_path, remote, stray):
    staged = _staged(tmp_path)
    (staged / stray).parent.mkdir(parents=True, exist_ok=True)
    (staged / stray).write_text("x")
    before = _head(remote)
    r = _push_only(tmp_path, remote, staged)
    assert r.returncode != 0 and "refusing" in r.stderr, (stray, r.stdout, r.stderr)
    assert _head(remote) == before


def test_a_symlink_in_the_staged_site_is_refused(tmp_path, remote):
    staged = _staged(tmp_path)
    (staged / "digest" / "evil.json").symlink_to("/etc/passwd")
    r = _push_only(tmp_path, remote, staged)
    assert r.returncode != 0 and "refusing" in r.stderr


def test_hooks_never_run_even_if_a_hooks_path_reaches_git(tmp_path, remote):
    """Defence in depth: every git call passes -c core.hooksPath=/dev/null, which outranks any injected config."""
    marker = tmp_path / "HOOK-RAN"
    hookdir = tmp_path / "evil-hooks"
    hookdir.mkdir()
    for h in ("pre-commit", "post-commit", "pre-push", "post-checkout"):
        (hookdir / h).write_text(f"#!/bin/sh\ntouch {marker}\n")
        (hookdir / h).chmod(0o755)
    injected = {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.hooksPath", "GIT_CONFIG_VALUE_0": str(hookdir)}
    r = _push_only(tmp_path, remote, _staged(tmp_path), extra_env=injected)
    assert r.returncode == 0, r.stderr
    assert not marker.exists()
