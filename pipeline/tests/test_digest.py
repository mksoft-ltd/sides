"""Digest assembly: validated analysis attached per story, failed stories kept with empty arrays + a warning,
meta totals (cost across stages, validation), schema validation, and the CLI tables/show output."""

import json

import pytest

from conftest import RECORDED_AT, aid, make_article, make_public
from sides_pipeline.analyse import AnalysisConfig, FakeAnalyser, analyse_stories
from sides_pipeline.cli import analysis_table, main, show_story
from sides_pipeline.cost import ModelPrice, RunCost, Usage
from sides_pipeline.digest import assemble_digest
from sides_pipeline.models import Digest, DigestMeta
from sides_pipeline.schema import validate_digest
from sides_pipeline.stories import RawStory, build_stories

PRICING = {"claude-opus-5-5": ModelPrice(4.0, 20.0, 0.2, 5.0)}
CFG = AnalysisConfig(model="claude-opus-5-5", effort="high", max_tokens=32000, prompt_path=None, concurrency=2, retries=1)
OUTLETS = [make_public("l1"), make_public("c1", lean="centre"), make_public("r1", lean="right"), make_public("e1", lean=None, bloc="east")]


def _stories_digest() -> Digest:
    arts = [make_article(x, o, headline=f"Headline {x}") for x, o in (("a", "l1"), ("b", "c1"), ("c", "r1"), ("d", "e1"), ("x", "l1"), ("y", "c1"), ("z", "r1"))]
    raw = [RawStory("First story", [aid("a"), aid("b"), aid("c"), aid("d")]), RawStory("Second story", [aid("x"), aid("y"), aid("z")])]
    stories, _ = build_stories(raw, arts, OUTLETS)
    return Digest(
        generated_at=RECORDED_AT, date="2026-10-14",
        meta=DigestMeta(model="claude-opus-5-5", cost_usd=0.5, outlets_polled=4, articles_collected=7, warnings=["1 feed(s) failed during collect"]),
        outlets=OUTLETS, stories=stories,
    )


def _response_for(story):
    ids = [a.id for a in story.articles]
    left = next(a.id for a in story.articles if a.outlet_id == "l1")
    centre = next(a.id for a in story.articles if a.outlet_id == "c1")
    return {
        "agreed_facts": [{"text": "Everyone reports it.", "sources": ids[:3]}, {"text": "Bad id.", "sources": ["ffffffffffff"]}],
        "framing": [{"lean": "left", "headline_quotes": [{"article_id": left, "quote": "Headline"}], "emphasis": []}],
        "omissions": [], "contested_claims": [], "opinion": [],
        "framing_by_bloc": [{"bloc": "west", "headline_quotes": [], "emphasis": [{"text": "West.", "sources": [centre]}]}],
        "east_west_contradictions": [],
    }


def _grouping_cost() -> RunCost:
    cost = RunCost(pricing=PRICING)
    cost.record("grouping", "claude-opus-5-5", Usage(100_000, 10_000), seconds=100.0)  # $0.4 + $0.2
    return cost


def test_assembly_attaches_validated_analysis_keeps_failed_story_and_totals_cost(tmp_path):
    d = _stories_digest()
    s1, s2 = d.stories
    fa = FakeAnalyser({
        s1.id: {"model": "claude-opus-5-5", "stop_reason": "end_turn", "usage": {"input_tokens": 5000, "output_tokens": 1000}, "response": _response_for(s1)},
        s2.id: {"model": "claude-opus-5-5", "stop_reason": "refusal", "usage": {"input_tokens": 4000, "output_tokens": 0}},
    })
    cost = _grouping_cost()
    results = analyse_stories(d.stories, d.outlets, fa, CFG, cost, system_prompt="SYS")
    out = assemble_digest(d, results, cost, model="claude-opus-5-5", now=RECORDED_AT)
    dg = out.digest

    # story 1: validated analysis attached, bad-id fact dropped
    a1 = dg.stories[0]
    assert len(a1.agreed_facts) == 1 and a1.framing[0].lean == "left" and a1.framing_by_bloc[0].bloc == "west"
    assert a1.validation.kept == 3 and a1.validation.dropped_by_reason == {"unknown_id": 1}
    # story 2: failed after retry → empty arrays + warning, still in the digest
    a2 = dg.stories[1]
    assert out.failed == [s2.id]
    assert a2.agreed_facts == [] and a2.framing == [] and a2.validation.kept == 0
    assert dg.meta.warnings[0] == "1 feed(s) failed during collect"
    assert any(w.startswith(f"story 2 ({s2.id}) has no analysis") and "refusal" in w for w in dg.meta.warnings)
    # meta totals
    assert dg.meta.validation.kept == 3 and dg.meta.validation.dropped_by_reason == {"unknown_id": 1}
    grouping, analysis = 0.6, (5000 * 4e-6 + 1000 * 20e-6) + 2 * 4000 * 4e-6
    assert cost.stage_total("grouping") == pytest.approx(grouping) and cost.stage_total("analysis") == pytest.approx(analysis)
    assert dg.meta.cost_usd == pytest.approx(grouping + analysis)
    assert dg.meta.model == "claude-opus-5-5" and dg.generated_at == RECORDED_AT and dg.date == "2026-10-14"
    assert dg.meta.outlets_polled == 4 and dg.meta.articles_collected == 7
    # the untouched phase-2 fields survive
    assert dg.stories[0].rank == 1 and dg.stories[0].coverage == s1.coverage and dg.outlets == d.outlets

    payload = dg.model_dump(mode="json")
    validate_digest(payload)
    p = tmp_path / "digest.json"
    p.write_text(json.dumps(payload))
    validate_digest(json.loads(p.read_text()))
    assert Digest.model_validate_json(p.read_text()) == dg

    table = analysis_table(out)
    assert "FAILED" in table.splitlines()[-1] and "First story" in table
    shown = show_story(dg, dg.stories[0])
    assert "AGREED FACTS (1)" in shown and "↳ L1 — Headline a" in shown and 'headline: "Headline" — L1' in shown
    assert "validator: kept 3, dropped 1 (unknown_id=1)" in shown


def test_run_cost_load_continues_an_earlier_stage_report(tmp_path):
    cost = _grouping_cost()
    path = cost.write(tmp_path / "runs" / "2026-10-14.json")
    again = RunCost.load(path, pricing=PRICING)
    assert again.total_usd == pytest.approx(0.6) and again.calls[0].stage == "grouping" and again.started_at == cost.started_at
    again.record("analysis", "claude-opus-5-5", Usage(1000, 100))
    assert again.total_usd == pytest.approx(0.6 + 0.004 + 0.002)
    assert [c.stage for c in again.calls] == ["grouping", "analysis"]


def test_stories_json_from_phase_2_still_validates_with_default_empty_analysis():
    """A phase-2 stories.json without analysis keys loads with empty arrays and passes the extended schema."""
    d = _stories_digest()
    payload = d.model_dump(mode="json")
    for s in payload["stories"]:
        for k in ("agreed_facts", "framing", "omissions", "contested_claims", "opinion", "framing_by_bloc", "east_west_contradictions", "validation"):
            s.pop(k)
    payload["meta"].pop("validation")
    reloaded = Digest.model_validate(payload)
    assert reloaded.stories[0].agreed_facts == [] and reloaded.meta.validation.kept == 0
    validate_digest(reloaded.model_dump(mode="json"))


def test_cli_analyse_replay_and_show(tmp_path, capsys):
    d = _stories_digest()
    s1, s2 = d.stories
    stories_path = tmp_path / "stories.json"
    stories_path.write_text(json.dumps(d.model_dump(mode="json")))
    fixtures = tmp_path / "fx"
    fixtures.mkdir()
    (fixtures / f"{s1.id}.json").write_text(json.dumps({"model": "claude-opus-5-5", "stop_reason": "end_turn", "usage": {"input_tokens": 10, "output_tokens": 5}, "response": _response_for(s1)}))
    (fixtures / f"{s2.id}.json").write_text(json.dumps({"model": "claude-opus-5-5", "stop_reason": "end_turn", "usage": {"input_tokens": 10, "output_tokens": 5}, "response": _response_for(s2)}))
    runs = tmp_path / "runs"
    _grouping_cost().write(runs / "2026-10-14.json")
    out = tmp_path / "digest.json"
    raw = tmp_path / "raw"

    rc = main(["analyse", "--in", str(stories_path), "--out", str(out), "--runs-dir", str(runs), "--replay-dir", str(fixtures), "--raw-out-dir", str(raw)])
    assert rc == 0
    printed = capsys.readouterr().out
    assert "analysis: 2 calls, 20 in / 10 out → $0.0003" in printed
    assert "validator: kept 6, dropped 2 (unknown_id=2)" in printed
    assert "total: $0.6003 over 3 call(s)" in printed
    digest = json.loads(out.read_text())
    validate_digest(digest)
    assert digest["meta"]["cost_usd"] == pytest.approx(0.60028)
    assert sorted(p.stem for p in raw.glob("*.json")) == sorted([s1.id, s2.id])
    assert json.loads((runs / "2026-10-14.json").read_text())["calls"][-1]["stage"] == "analysis"

    assert main(["show", "--in", str(out), "--story", "2"]) == 0
    shown = capsys.readouterr().out
    assert shown.startswith("#2  Second story") and "EAST–WEST CONTRADICTIONS (0)" in shown and "none found" in shown
    assert main(["show", "--in", str(out), "--story", "9"]) == 1
