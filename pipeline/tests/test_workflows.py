"""SEC-3 (fix round 2): the daily job's security shape, pinned.

The job that holds ANTHROPIC_API_KEY and runs third-party PyPI code must have a read-only token and no persisted
credentials; the job with the write token must hold no API key and run no pipeline code; every pip install must
come from a hashed lock."""

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
DAILY = yaml.safe_load((ROOT / ".github/workflows/daily.yml").read_text())
CI = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())


def _steps(job):
    return job.get("steps", [])


def _text(obj) -> str:
    return yaml.safe_dump(obj)


def test_build_job_holds_the_secret_with_a_read_only_token_and_no_persisted_credentials():
    build = DAILY["jobs"]["build"]
    assert build["permissions"] == {"contents": "read"}
    checkout = next(s for s in _steps(build) if str(s.get("uses", "")).startswith("actions/checkout@"))
    assert checkout.get("with", {}).get("persist-credentials") is False
    assert "secrets.ANTHROPIC_API_KEY" in _text(build)
    assert "x-access-token" not in _text(build) and "github.token" not in _text(build)


def test_publish_job_has_the_write_token_but_no_secret_and_runs_no_pipeline_code():
    publish = DAILY["jobs"]["publish"]
    assert publish["needs"] == "build"
    assert publish["permissions"] == {"contents": "write", "actions": "write"}
    text = _text(publish)
    assert "ANTHROPIC_API_KEY" not in text and "secrets." not in text
    assert "sides_pipeline" not in text and "pip install" not in text and "setup-python" not in text
    assert "--push-only" in text


def test_workflow_default_token_is_read_only():
    assert DAILY["permissions"] == {"contents": "read"}
    assert CI["permissions"] == {"contents": "read"}


def test_every_pip_install_is_hash_locked():
    runs = [s["run"] for wf in (DAILY, CI) for job in wf["jobs"].values() for s in _steps(job) if "run" in s]
    installs = [r for r in runs if "pip install" in r]
    assert installs, "expected the workflows to install the pipeline dependencies"
    for r in installs:
        assert "--require-hashes" in r and re.search(r"-r pipeline/requirements(-dev)?\.lock", r), r
        assert " -e " not in r


def test_lock_files_pin_every_package_with_hashes_and_cover_pyproject():
    for name in ("requirements.lock", "requirements-dev.lock"):
        text = (ROOT / "pipeline" / name).read_text()
        pins = re.findall(r"^([a-z0-9][a-z0-9._-]*)==([^\s\\]+)", text, re.MULTILINE)
        assert pins, name
        blocks = re.split(r"^(?=[a-z0-9])", text, flags=re.MULTILINE)
        for b in blocks:
            if re.match(r"[a-z0-9]", b):
                assert "--hash=sha256:" in b, f"{name}: no hash for {b.splitlines()[0]}"
        names = {p[0] for p in pins}
        for direct in ("anthropic", "feedparser", "httpx", "jsonschema", "pydantic", "pyyaml"):
            assert direct in names, f"{name} misses {direct}"
    assert "pytest-socket" in (ROOT / "pipeline" / "requirements-dev.lock").read_text()
