"""`cli run` exit codes are the publish gate: daily.yml publishes only when `run` exits 0, so a day that collected
nothing, grouped nothing, or analysed nothing must exit non-zero and must stop before the later (paid) stages.
Stages are replaced with stand-ins at the cli seam (`_do_collect` / `_do_group` / `_do_analyse`); no network, no LLM.
Also: `publish` refuses a broken digest before touching the site."""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from pydantic import ValidationError

from sides_pipeline import cli
from sides_pipeline.cli import main
from sides_pipeline.publish import publish


class Stages:
    """Records which stages ran; each returns what the test configured."""

    def __init__(self, *, articles=1, feed_errors=0, enabled=3, stories=2, failed=0, group_exit=None):
        self.calls: list[str] = []
        self.articles, self.feed_errors, self.enabled = articles, feed_errors, enabled
        self.stories, self.failed, self.group_exit = stories, failed, group_exit

    def collect(self, args, out):
        self.calls.append("collect")
        outlets = [SimpleNamespace(enabled=True) for _ in range(self.enabled)] + [SimpleNamespace(enabled=False)]
        return outlets, SimpleNamespace(articles=[object()] * self.articles, feed_errors=[object()] * self.feed_errors)

    def group(self, collected, args, out, runs_dir):
        self.calls.append("group")
        if self.group_exit is not None:
            raise SystemExit(self.group_exit)
        digest = SimpleNamespace(stories=[object()] * self.stories)
        return SimpleNamespace(digest=digest), object()

    def analyse(self, stories_digest, args, out, runs_dir, cost):
        self.calls.append("analyse")
        n = len(stories_digest.stories)
        return SimpleNamespace(digest=stories_digest, failed=[object()] * min(self.failed, n)), cost


@pytest.fixture
def stages(monkeypatch):
    def install(**kw) -> Stages:
        s = Stages(**kw)
        monkeypatch.setattr(cli, "_do_collect", s.collect)
        monkeypatch.setattr(cli, "_do_group", s.group)
        monkeypatch.setattr(cli, "_do_analyse", s.analyse)
        return s
    return install


def run(tmp_path, *extra: str) -> int:
    return main(["run", "--out-dir", str(tmp_path), *extra])


def test_healthy_day_exits_0_and_runs_every_stage(tmp_path, stages):
    s = stages()
    assert run(tmp_path) == 0
    assert s.calls == ["collect", "group", "analyse"]


def test_no_articles_exits_1_before_any_paid_call(tmp_path, stages):
    s = stages(articles=0)
    assert run(tmp_path) == 1
    assert s.calls == ["collect"]


def test_every_enabled_feed_failing_exits_1_even_with_stray_articles(tmp_path, stages):
    s = stages(articles=5, feed_errors=3, enabled=3)
    assert run(tmp_path) == 1
    assert s.calls == ["collect"]


def test_most_feeds_failing_but_one_working_carries_on(tmp_path, stages):
    s = stages(articles=5, feed_errors=2, enabled=3)
    assert run(tmp_path) == 0
    assert s.calls == ["collect", "group", "analyse"]


def test_zero_qualifying_stories_exits_1_and_skips_analysis(tmp_path, stages):
    # Without this a schema-valid digest with no stories would replace latest.json for every reader.
    s = stages(stories=0)
    assert run(tmp_path) == 1
    assert s.calls == ["collect", "group"]


def test_every_story_failing_analysis_exits_1(tmp_path, stages):
    stages(stories=3, failed=3)
    assert run(tmp_path) == 1


def test_some_stories_failing_analysis_still_publishes(tmp_path, stages):
    stages(stories=3, failed=2)
    assert run(tmp_path) == 0


def test_grouping_refusal_propagates_exit_2(tmp_path, stages):
    s = stages(group_exit=2)
    with pytest.raises(SystemExit) as exc:
        run(tmp_path)
    assert exc.value.code == 2
    assert "analyse" not in s.calls


def test_through_collect_and_through_group_stop_early_with_0(tmp_path, stages):
    s = stages()
    assert run(tmp_path, "--through", "collect") == 0
    assert s.calls == ["collect"]
    s = stages()
    assert run(tmp_path, "--through", "group") == 0
    assert s.calls == ["collect", "group"]


def test_publish_refuses_a_broken_digest_and_leaves_the_site_untouched(tmp_path):
    site = tmp_path / "site"
    (site / "digest").mkdir(parents=True)
    latest = site / "digest" / "latest.json"
    latest.write_text('{"yesterday": true}\n')
    before = latest.read_bytes()

    broken = tmp_path / "digest.json"
    broken.write_text(json.dumps({"schema_version": 1, "date": "2026-10-15", "stories": "none"}))
    with pytest.raises(ValidationError):
        publish(broken, tmp_path / "runs", site)

    assert latest.read_bytes() == before
    assert sorted(p.name for p in (site / "digest").iterdir()) == ["latest.json"]
