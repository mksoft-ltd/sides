"""Publishing a run into the gh-pages site directory: fresh site, merge onto an existing site, index order and
dedupe, latest.json identity, missing privacy html tolerated, CLI + step summary. No network."""

import json
from pathlib import Path

from conftest import RECORDED_AT, aid, make_article, make_public
from sides_pipeline.cli import main
from sides_pipeline.cost import ModelPrice, RunCost, Usage
from sides_pipeline.models import Digest, DigestMeta
from sides_pipeline.publish import IndexEntry, build_index, publish, step_summary
from sides_pipeline.stories import RawStory, build_stories

OUTLETS = [make_public("l1"), make_public("c1", lean="centre"), make_public("r1", lean="right"), make_public("e1", lean=None, bloc="east")]


def _digest(date: str, cost_usd: float = 1.25, n_stories: int = 2) -> Digest:
    arts = [make_article(x, o, headline=f"Headline {x}") for x, o in (("a", "l1"), ("b", "c1"), ("c", "r1"), ("d", "e1"), ("x", "l1"), ("y", "c1"), ("z", "r1"))]
    raw = [RawStory("First | story", [aid("a"), aid("b"), aid("c"), aid("d")]), RawStory("Second story", [aid("x"), aid("y"), aid("z")])][:n_stories]
    stories, _ = build_stories(raw, arts, OUTLETS)
    return Digest(
        generated_at=RECORDED_AT, date=date,
        meta=DigestMeta(model="claude-opus-5-5", cost_usd=cost_usd, outlets_polled=4, articles_collected=7, warnings=[]),
        outlets=OUTLETS, stories=stories,
    )


def _write_run(out: Path, date: str, cost_usd: float = 1.25, n_stories: int = 2) -> tuple[Path, Path]:
    """pipeline/out shape: digest.json + runs/<date>.json."""
    out.mkdir(parents=True, exist_ok=True)
    digest_path = out / "digest.json"
    digest_path.write_text(json.dumps(_digest(date, cost_usd, n_stories).model_dump(mode="json"), indent=2, ensure_ascii=False) + "\n")
    rc = RunCost(pricing={"claude-opus-5-5": ModelPrice(4.0, 20.0, 0.2, 5.0)})
    rc.record("grouping", "claude-opus-5-5", Usage(100_000, 10_000), seconds=90.0)
    rc.record("analysis", "claude-opus-5-5", Usage(50_000, 20_000), seconds=40.0)
    run_path = rc.write(out / "runs" / f"{date}.json")
    return digest_path, run_path


def test_fresh_site_has_every_file(tmp_path):
    digest_path, run_path = _write_run(tmp_path / "out", "2026-10-15")
    site = tmp_path / "site"
    res = publish(digest_path, tmp_path / "out" / "runs", site, privacy_html=tmp_path / "privacy_policy.html")

    assert res.date == "2026-10-15"
    assert (site / "digest" / "latest.json").read_bytes() == (site / "digest" / "2026-10-15.json").read_bytes() == digest_path.read_bytes()
    assert (site / "runs" / "2026-10-15.json").read_bytes() == run_path.read_bytes() and res.run_report_copied
    assert (site / ".nojekyll").exists() and (site / ".nojekyll").read_text() == ""
    html = (site / "index.html").read_text()
    assert "digest/latest.json" in html and "digest/index.json" in html and "<!doctype html>" in html
    index = json.loads((site / "digest" / "index.json").read_text())
    assert index == [{"date": "2026-10-15", "generated_at": "2026-10-14T22:00:00Z", "stories": 2, "cost_usd": 1.25}]


def test_missing_privacy_html_is_tolerated_and_present_one_is_copied(tmp_path):
    digest_path, _ = _write_run(tmp_path / "out", "2026-10-15")
    site = tmp_path / "site"
    res = publish(digest_path, tmp_path / "out" / "runs", site, privacy_html=tmp_path / "privacy_policy.html")
    assert not res.privacy_copied and not (site / "privacy_policy.html").exists()

    (tmp_path / "privacy_policy.html").write_text("<html>policy</html>")
    res = publish(digest_path, tmp_path / "out" / "runs", site, privacy_html=tmp_path / "privacy_policy.html")
    assert res.privacy_copied and (site / "privacy_policy.html").read_text() == "<html>policy</html>"

    # privacy_html=None: nothing is looked for
    res = publish(digest_path, tmp_path / "out" / "runs", tmp_path / "site2")
    assert not res.privacy_copied


def test_publishing_onto_existing_site_keeps_older_days_and_merges_index(tmp_path):
    site = tmp_path / "site"
    for i, date in enumerate(("2026-10-13", "2026-10-14")):
        dp, _ = _write_run(tmp_path / f"out{i}", date, cost_usd=1.0 + i)
        publish(dp, tmp_path / f"out{i}" / "runs", site)
    old_13 = (site / "digest" / "2026-10-13.json").read_bytes()
    # an index entry whose digest file is gone (hand-pruned) survives the merge
    idx_path = site / "digest" / "index.json"
    entries = json.loads(idx_path.read_text())
    entries.append({"date": "2026-10-01", "generated_at": "2026-10-01T06:10:00Z", "stories": 9, "cost_usd": 0.9})
    idx_path.write_text(json.dumps(entries))

    dp, _ = _write_run(tmp_path / "out2", "2026-10-15", cost_usd=3.0)
    res = publish(dp, tmp_path / "out2" / "runs", site)

    assert (site / "digest" / "2026-10-13.json").read_bytes() == old_13          # older days untouched
    assert (site / "digest" / "latest.json").read_bytes() == dp.read_bytes()    # latest moved on
    assert {p.name for p in (site / "runs").iterdir()} == {"2026-10-13.json", "2026-10-14.json", "2026-10-15.json"}
    dates = [e["date"] for e in json.loads(idx_path.read_text())]
    assert dates == ["2026-10-15", "2026-10-14", "2026-10-13", "2026-10-01"]     # newest first, old entry kept
    assert [e.cost_usd for e in res.index] == [3.0, 2.0, 1.0, 0.9]


def test_index_dedupes_by_date_and_republishing_a_day_replaces_its_entry(tmp_path):
    site = tmp_path / "site"
    dp, _ = _write_run(tmp_path / "out", "2026-10-15", cost_usd=1.0, n_stories=1)
    publish(dp, tmp_path / "out" / "runs", site)
    # a corrupt duplicate row in the index is collapsed, and a re-run of the same day wins
    idx_path = site / "digest" / "index.json"
    rows = json.loads(idx_path.read_text())
    idx_path.write_text(json.dumps(rows + rows))
    dp2, _ = _write_run(tmp_path / "out2", "2026-10-15", cost_usd=2.0, n_stories=2)
    res = publish(dp2, tmp_path / "out2" / "runs", site)
    assert [(e.date, e.stories, e.cost_usd) for e in res.index] == [("2026-10-15", 2, 2.0)]
    assert len(list((site / "digest").glob("2026-*.json"))) == 1


def test_build_index_ignores_non_dated_and_unreadable_files(tmp_path):
    d = tmp_path / "digest"
    d.mkdir()
    (d / "latest.json").write_text("{}")
    (d / "index.json").write_text("[]")
    (d / "2026-10-14.json").write_text("not json")
    dp, _ = _write_run(tmp_path / "out", "2026-10-15")
    (d / "2026-10-15.json").write_bytes(dp.read_bytes())
    idx = build_index(d, {"2026-10-14": IndexEntry("2026-10-14", "2026-10-14T06:00:00Z", 10, 1.3)})
    assert [(e.date, e.stories) for e in idx] == [("2026-10-15", 2), ("2026-10-14", 10)]


def test_missing_cost_report_still_publishes_digest(tmp_path):
    dp, run_path = _write_run(tmp_path / "out", "2026-10-15")
    run_path.unlink()
    res = publish(dp, tmp_path / "out" / "runs", tmp_path / "site")
    assert not res.run_report_copied and not (tmp_path / "site" / "runs" / "2026-10-15.json").exists()
    assert (tmp_path / "site" / "digest" / "latest.json").exists()


def test_step_summary_leads_with_cost_and_lists_stories(tmp_path):
    dp, run_path = _write_run(tmp_path / "out", "2026-10-15")
    md = step_summary(Digest.model_validate_json(dp.read_text()), run_path)
    lines = md.splitlines()
    assert lines[0] == "## Sides digest 2026-10-15"
    assert "- grouping: 100,000 in / 10,000 out tokens → $0.6000" in lines
    assert "- analysis: 50,000 in / 20,000 out tokens → $0.6000" in lines
    assert "- total: $1.2000 over 2 call(s)" in lines
    assert "| 1 | First \\| story | 4 | 1/1/1 | 3/1 | - |" in lines
    assert "| 2 | Second story | 3 | 1/1/1 | 3/0 | bloc=west |" in lines
    assert lines.index("**Cost**") < lines.index("| # | Story | Outlets | L/C/R | W/E | Blindspot |")
    # no per-call report → falls back to meta.cost_usd
    assert "**Cost**: $1.2500" in step_summary(Digest.model_validate_json(dp.read_text()), None)


def test_cli_publish_writes_site_and_summary(tmp_path, capsys):
    dp, _ = _write_run(tmp_path / "out", "2026-10-15")
    site = tmp_path / "site"
    summary = tmp_path / "summary.md"
    rc = main([
        "publish", "--digest", str(dp), "--runs-dir", str(tmp_path / "out" / "runs"), "--site", str(site),
        "--privacy-html", str(tmp_path / "privacy_policy.html"), "--summary-out", str(summary),
    ])
    out = capsys.readouterr().out
    assert rc == 0
    assert (site / "digest" / "latest.json").exists() and (site / "runs" / "2026-10-15.json").exists()
    assert "privacy_policy.html not published" in out and "index: 1 digest(s), latest 2026-10-15" in out
    assert summary.read_text().startswith("## Sides digest 2026-10-15")
