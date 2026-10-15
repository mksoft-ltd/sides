"""M2 (fix round 2): a call served by the server-side refusal fallback must never lose the paid run.

The stand-in responses use the API's real shape (claude-api skill, refusal-fallback section; SDK 1.14
``BetaMessageIterationUsage`` / ``BetaFallbackMessageIterationUsage``): ``message.model`` names the model that
served the call, top-level ``usage`` covers only that attempt, and ``usage.iterations`` lists every attempt —
the declined one on the requested model first, then a ``fallback_message`` entry for the serving model."""

import json
from contextlib import contextmanager
from types import SimpleNamespace

import pytest

from conftest import RECORDED_AT, aid, make_article, make_public
from sides_pipeline.analyse import AnalysisConfig, ClaudeAnalyser, analyse_stories
from sides_pipeline.cost import RunCost, load_pricing
from sides_pipeline.digest import assemble_digest
from sides_pipeline.group import ClaudeGrouper, GroupingConfig, GroupingError, group_articles
from sides_pipeline.models import CollectResult
from sides_pipeline.schema import validate_digest

REQUESTED = "claude-opus-5-5"
GCFG = GroupingConfig(model=REQUESTED, effort="medium", max_tokens=64000, prompt_path=None)
ACFG = AnalysisConfig(model=REQUESTED, effort="high", max_tokens=32000, prompt_path=None, concurrency=2, retries=1)
OUTLETS = [make_public("l1"), make_public("c1", lean="centre"), make_public("r1", lean="right"), make_public("e1", lean=None, bloc="east")]
ARTICLES = [make_article("a", "l1"), make_article("b", "c1"), make_article("c", "r1"), make_article("d", "e1")]


def _it(type_, model, inp, out):
    return SimpleNamespace(type=type_, model=model, input_tokens=inp, output_tokens=out,
                           cache_read_input_tokens=0, cache_creation_input_tokens=0)


def _fallback_message(text, served_by, *, declined=(2000, 0), served=(2100, 400), stop="end_turn"):
    """A response served by ``served_by`` after ``REQUESTED`` declined."""
    iterations = [_it("message", REQUESTED, *declined), _it("fallback_message", served_by, *served)]
    content = [SimpleNamespace(type="fallback", **{"from": SimpleNamespace(model=REQUESTED)}, to=SimpleNamespace(model=served_by))]
    if text is not None:
        content.append(SimpleNamespace(type="text", text=text))
    return SimpleNamespace(
        stop_reason=stop, stop_details=None, content=content, model=served_by,
        usage=SimpleNamespace(input_tokens=served[0], output_tokens=served[1], cache_read_input_tokens=0,
                              cache_creation_input_tokens=0, iterations=iterations),
    )


def _plain_message(text):
    return SimpleNamespace(stop_reason="end_turn", stop_details=None, content=[SimpleNamespace(type="text", text=text)],
                           model=REQUESTED, usage=SimpleNamespace(input_tokens=1000, output_tokens=100,
                                                                  cache_read_input_tokens=0, cache_creation_input_tokens=0))


class _Client:
    def __init__(self, messages):
        self.messages = list(messages)
        self.beta = SimpleNamespace(messages=SimpleNamespace(stream=self._stream))

    @contextmanager
    def _stream(self, **kwargs):
        msg = self.messages.pop(0)
        yield SimpleNamespace(get_final_message=lambda: msg)


def _collected():
    return CollectResult(collected_at=RECORDED_AT, outlets=OUTLETS, articles=ARTICLES, feed_errors=[], per_outlet_counts={})


GROUP_BODY = json.dumps({"stories": [{"title": "A story", "article_ids": [aid("a"), aid("b"), aid("c"), aid("d")]}]})


@pytest.mark.parametrize("served_by", ["claude-opus-5", "claude-opus-4-8"])
def test_grouping_served_by_fallback_completes_and_costs_every_attempt(served_by):
    cost = RunCost()  # the real pricing.yaml
    grouper = ClaudeGrouper(GCFG, client=_Client([_fallback_message(GROUP_BODY, served_by)]))
    outcome = group_articles(_collected(), grouper, GCFG, cost, now=RECORDED_AT, system_prompt="SYS")

    validate_digest(outcome.digest.model_dump(mode="json"))
    assert [(c.model, c.input_tokens, c.output_tokens) for c in cost.calls] == [(REQUESTED, 2000, 0), (served_by, 2100, 400)]
    p = load_pricing()
    expected = 2000 * p[REQUESTED].input / 1e6 + 2100 * p[served_by].input / 1e6 + 400 * p[served_by].output / 1e6
    assert cost.total_usd == pytest.approx(expected) and outcome.digest.meta.cost_usd == pytest.approx(expected)
    assert cost.warnings == [] and all(c.usd is not None for c in cost.calls)


def test_fallback_model_with_no_price_row_is_recorded_unpriced_and_the_run_still_completes():
    cost = RunCost()
    grouper = ClaudeGrouper(GCFG, client=_Client([_fallback_message(GROUP_BODY, "claude-opus-9-9")]))
    outcome = group_articles(_collected(), grouper, GCFG, cost, now=RECORDED_AT, system_prompt="SYS")
    validate_digest(outcome.digest.model_dump(mode="json"))
    assert [c.usd is None for c in cost.calls] == [False, True]
    assert any("claude-opus-9-9" in w for w in outcome.digest.meta.warnings)


def test_refused_grouping_call_is_still_costed_per_attempt():
    cost = RunCost()
    whole_chain_refused = _fallback_message(None, "claude-opus-5", stop="refusal")
    with pytest.raises(GroupingError):
        group_articles(_collected(), ClaudeGrouper(GCFG, client=_Client([whole_chain_refused])), GCFG, cost,
                       now=RECORDED_AT, system_prompt="SYS")
    assert [c.model for c in cost.calls] == [REQUESTED, "claude-opus-5"]


def test_one_analysis_served_by_fallback_keeps_every_paid_story_and_writes_the_digest(tmp_path):
    cost = RunCost()
    grouped = group_articles(_collected(), ClaudeGrouper(GCFG, client=_Client([_plain_message(GROUP_BODY)])), GCFG, cost,
                             now=RECORDED_AT, system_prompt="SYS").digest
    body = json.dumps({"agreed_facts": [{"text": "Something happened", "sources": [aid("a"), aid("b")]}], "framing": [],
                       "omissions": [], "contested_claims": [], "opinion": [], "framing_by_bloc": [], "east_west_contradictions": []})
    client = _Client([_fallback_message(body, "claude-opus-5")])
    results = analyse_stories(grouped.stories, grouped.outlets, ClaudeAnalyser(ACFG, client=client), ACFG, cost, system_prompt="SYS")
    assert results[0].ok
    outcome = assemble_digest(grouped, results, cost, model=REQUESTED, now=RECORDED_AT)
    payload = outcome.digest.model_dump(mode="json")
    validate_digest(payload)
    (tmp_path / "digest.json").write_text(json.dumps(payload))
    assert outcome.digest.stories[0].agreed_facts[0].text == "Something happened"
    assert [(c.stage, c.model) for c in cost.calls] == [("grouping", REQUESTED), ("analysis", REQUESTED), ("analysis", "claude-opus-5")]
    assert outcome.digest.meta.cost_usd == pytest.approx(cost.total_usd) and cost.unpriced_calls == 0
