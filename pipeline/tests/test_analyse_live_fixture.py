"""Replays the real 14 Oct 2026 analysis responses (recorded after the first live run) over the phase-2 live
fixtures: grouping replay → stories → analysis replay → validator → digest. Real headline data, no network."""

import json

from conftest import LLM_FIXTURES
from sides_pipeline.analyse import AnalysisConfig, FakeAnalyser, analyse_stories
from sides_pipeline.cost import RunCost
from sides_pipeline.digest import assemble_digest
from sides_pipeline.group import FakeGrouper, GroupingConfig, group_articles
from sides_pipeline.models import CollectResult
from sides_pipeline.schema import validate_digest

ANALYSE_FIXTURES = LLM_FIXTURES / "analyse_live_2026-10-14"
GCFG = GroupingConfig(model="claude-opus-5-5", effort="medium", max_tokens=64000, prompt_path=None)
ACFG = AnalysisConfig(model="claude-opus-5-5", effort="high", max_tokens=32000, prompt_path=None, concurrency=4, retries=1)


def _run():
    collected = CollectResult.model_validate_json((LLM_FIXTURES / "articles_live_2026-10-14.json").read_text())
    cost = RunCost()
    grouped = group_articles(collected, FakeGrouper(LLM_FIXTURES / "group_live_2026-10-14.json"), GCFG, cost, now=collected.collected_at, system_prompt="SYS")
    analyser = FakeAnalyser(ANALYSE_FIXTURES)
    results = analyse_stories(grouped.digest.stories, grouped.digest.outlets, analyser, ACFG, cost, system_prompt="SYS")
    return assemble_digest(grouped.digest, results, cost, model="claude-opus-5-5", now=collected.collected_at), cost, analyser


def test_live_fixtures_cover_every_story_and_reproduce_the_digest():
    outcome, cost, analyser = _run()
    d = outcome.digest
    validate_digest(d.model_dump(mode="json"))
    assert len(d.stories) == 10 and outcome.failed == []
    assert sorted(p.stem for p in ANALYSE_FIXTURES.glob("*.json")) == sorted(s.id for s in d.stories)
    assert len(analyser.calls) == 10 and len(cost.calls) == 11  # 1 grouping + 10 analysis, no retries


def test_live_fixtures_have_no_unknown_id_drops_and_every_item_is_sourced():
    outcome, _, _ = _run()
    d = outcome.digest
    assert d.meta.validation.dropped_by_reason.get("unknown_id", 0) == 0
    assert d.meta.validation.kept > 0
    for s in d.stories:
        ids = {a.id for a in s.articles}
        for item in s.agreed_facts + s.opinion:
            assert item.sources and set(item.sources) <= ids
        for f in s.framing:
            assert all(q.article_id in ids for q in f.headline_quotes)
            assert all(e.sources and set(e.sources) <= ids for e in f.emphasis)
        for o in s.omissions:
            assert o.sources and set(o.sources) <= ids
        for c in s.contested_claims:
            assert c.asserted_by and c.disputed_by and set(c.asserted_by + c.disputed_by) <= ids
        for x in s.east_west_contradictions:
            assert x.west.sources and x.east.sources and set(x.west.sources + x.east.sources) <= ids


def test_live_fixture_top_story_has_lean_and_bloc_framing():
    outcome, _, _ = _run()
    top = outcome.digest.stories[0]
    assert top.title.startswith("Pope Leo diagnosed with lung cancer")
    assert {f.lean for f in top.framing} <= {"left", "centre", "right"} and len(top.framing) >= 2
    assert {f.bloc for f in top.framing_by_bloc} == {"west", "east"}
    assert top.agreed_facts


def test_live_fixture_quotes_carry_provenance_from_both_fields():
    outcome, _, _ = _run()
    fields = [q.field for s in outcome.digest.stories for f in s.framing + s.framing_by_bloc for q in f.headline_quotes]
    assert set(fields) == {"headline", "snippet"} and len(fields) == 125
    assert outcome.digest.meta.validation.dropped_by_reason == {}


def test_live_fixture_cost_is_the_sum_of_recorded_usage():
    outcome, cost, _ = _run()
    expected = 0.0
    for p in list(ANALYSE_FIXTURES.glob("*.json")) + [LLM_FIXTURES / "group_live_2026-10-14.json"]:
        u = json.loads(p.read_text())["usage"]
        expected += u["input_tokens"] * 4.0 / 1e6 + u["output_tokens"] * 20.0 / 1e6
    assert abs(cost.total_usd - expected) < 1e-5
    assert outcome.digest.meta.cost_usd == cost.total_usd
