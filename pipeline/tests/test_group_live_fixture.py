"""Replays the real 14 Oct 2026 grouping response (recorded after the first live run) through the
validator and ranker. Exercises real headline data without any network."""

import json

from conftest import LLM_FIXTURES
from sides_pipeline.cost import RunCost
from sides_pipeline.group import FakeGrouper, GroupingConfig, group_articles
from sides_pipeline.models import CollectResult
from sides_pipeline.schema import validate_digest
from sides_pipeline.stories import story_id

CFG = GroupingConfig(model="claude-opus-5-5", effort="medium", max_tokens=64000, prompt_path=None)


def _run():
    collected = CollectResult.model_validate_json((LLM_FIXTURES / "articles_live_2026-10-14.json").read_text())
    grouper = FakeGrouper(LLM_FIXTURES / "group_live_2026-10-14.json")
    cost = RunCost()
    return group_articles(collected, grouper, CFG, cost, now=collected.collected_at, system_prompt="SYS"), cost


def test_live_fixture_reproduces_the_recorded_top_stories():
    outcome, cost = _run()
    d = outcome.digest
    validate_digest(d.model_dump(mode="json"))
    assert outcome.report.stories_in == 65
    assert outcome.report.unknown_ids_dropped == 0 and outcome.report.duplicate_memberships_resolved == 0
    assert outcome.report.below_min_outlets_dropped == 34 and outcome.report.beyond_top_n_dropped == 21
    assert len(d.stories) == 10 and d.meta.warnings == []
    assert [s.rank for s in d.stories] == list(range(1, 11))
    assert d.stories[0].title.startswith("Pope Leo diagnosed with lung cancer")
    assert d.stories[0].outlet_count == 12
    assert d.stories[0].coverage.lean.model_dump() == {"left": 6, "centre": 3, "right": 2}
    assert d.stories[0].coverage.bloc.model_dump() == {"west": 11, "east": 1}
    counts = [s.outlet_count for s in d.stories]
    assert counts == sorted(counts, reverse=True) and counts[-1] >= 3
    # Every story id is the hash of its own (sorted) article ids; no article is in two stories.
    seen = set()
    for s in d.stories:
        ids = [a.id for a in s.articles]
        assert s.id == story_id(ids)
        assert not (set(ids) & seen)
        seen.update(ids)


def test_live_fixture_has_a_lean_blindspot_and_mixed_bloc_coverage():
    outcome, _ = _run()
    flagged = [s for s in outcome.digest.stories if s.blindspot.lean]
    assert flagged and flagged[0].blindspot.lean == "left"
    assert flagged[0].coverage.lean.centre == 0 and flagged[0].coverage.lean.right == 0
    assert all(s.blindspot.bloc is None for s in outcome.digest.stories)  # every top story had West and East coverage


def test_live_fixture_cost_matches_recorded_usage():
    outcome, cost = _run()
    raw = json.loads((LLM_FIXTURES / "group_live_2026-10-14.json").read_text())
    u = raw["usage"]
    expected = u["input_tokens"] * 4.0 / 1e6 + u["output_tokens"] * 20.0 / 1e6
    assert abs(cost.total_usd - expected) < 1e-6
    assert outcome.digest.meta.cost_usd == cost.total_usd
    assert outcome.digest.meta.articles_collected == 257 and outcome.digest.meta.outlets_polled == 29
