"""Batch-first stages: half-price batch answers are used as-is; anything the batch cannot serve is re-run streamed
(with the refusal fallback); the cost report prices batch attempts at half. Fake Batches client, no network."""

import json
from contextlib import contextmanager
from types import SimpleNamespace

from conftest import make_article, make_public
from sides_pipeline.analyse import AnalysisConfig, analyse_stories
from sides_pipeline.batch import BatchConfig, BatchFirstAnalyser, BatchFirstGrouper
from sides_pipeline.cost import ModelPrice, RunCost
from sides_pipeline.group import GroupingConfig
from sides_pipeline.llm import run_batch
from sides_pipeline.stories import RawStory, build_stories

PRICE = {"claude-opus-5-5": ModelPrice(4.0, 20.0, 0.2, 5.0)}
OUTLETS = [make_public("l1"), make_public("c1", lean="centre"), make_public("r1", lean="right")]
GOOD = json.dumps({"summary": None, "agreed_facts": [], "framing": [], "omissions": [], "contested_claims": [],
                   "opinion": [], "framing_by_bloc": [], "east_west_contradictions": [], "conclusion": None})


def _msg(stop="end_turn", text=GOOD):
    content = [SimpleNamespace(type="text", text=text)] if text is not None else []
    return SimpleNamespace(stop_reason=stop, content=content, model="claude-opus-5-5",
                           usage=SimpleNamespace(input_tokens=1_000_000, output_tokens=100_000,
                                                 cache_read_input_tokens=0, cache_creation_input_tokens=0))


class FakeBatches:
    """messages.batches.{create, retrieve, cancel, results}; ``outcomes`` maps custom_id → message or a type."""

    def __init__(self, outcomes, polls_until_end=1):
        self.outcomes = outcomes
        self.polls_left = polls_until_end
        self.created = []
        self.cancelled = False

    def create(self, requests):
        self.created.append(requests)
        return SimpleNamespace(id="b1", processing_status="in_progress")

    def retrieve(self, _id):
        self.polls_left -= 1
        ended = self.polls_left <= 0 or self.cancelled
        return SimpleNamespace(id="b1", processing_status="ended" if ended else "in_progress")

    def cancel(self, _id):
        self.cancelled = True

    def results(self, _id):
        for cid, o in self.outcomes.items():
            if isinstance(o, str):
                yield SimpleNamespace(custom_id=cid, result=SimpleNamespace(type=o))
            else:
                yield SimpleNamespace(custom_id=cid, result=SimpleNamespace(type="succeeded", message=o))


class FakeClient:
    def __init__(self, batches, streamed=()):
        self.messages = SimpleNamespace(batches=batches)
        self.streamed = list(streamed)
        self.stream_kwargs = []
        self.beta = SimpleNamespace(messages=SimpleNamespace(stream=self._stream))

    @contextmanager
    def _stream(self, **kwargs):
        self.stream_kwargs.append(kwargs)
        msg = self.streamed.pop(0)
        yield SimpleNamespace(get_final_message=lambda: msg)


def _stories():
    arts = [make_article(x, o) for x, o in (("a", "l1"), ("b", "c1"), ("c", "r1"), ("d", "l1"), ("e", "c1"), ("f", "r1"))]
    stories, _ = build_stories([RawStory("One", [a.id for a in arts[:3]]), RawStory("Two", [a.id for a in arts[3:]])], arts, OUTLETS)
    return stories


ACFG = AnalysisConfig(model="claude-opus-5-5", effort="high", max_tokens=32000, prompt_path=None, concurrency=2, retries=1)
BCFG = BatchConfig(enabled=True, deadline_s=60, poll_s=1)


def _run(client):
    stories = _stories()
    an = BatchFirstAnalyser(ACFG, BCFG, client, sleep=lambda _s: None)
    an.prefetch(stories, OUTLETS, "SYSTEM")
    cost = RunCost(pricing=PRICE)
    results = analyse_stories(stories, OUTLETS, an, ACFG, cost, system_prompt="SYSTEM")
    return stories, results, cost


def test_batch_requests_drop_the_fallback_and_answers_cost_half():
    stories = _stories()
    batches = FakeBatches({s.id: _msg() for s in stories})
    client = FakeClient(batches)
    _, results, cost = _run(client)
    req = batches.created[0]
    assert {r["custom_id"] for r in req} == {s.id for s in stories}
    params = req[0]["params"]
    assert "betas" not in params and "fallbacks" not in params
    assert params["output_config"]["format"]["type"] == "json_schema" and params["model"] == "claude-opus-5-5"
    assert all(r.ok for r in results) and client.stream_kwargs == []
    # 1M in × $4 + 0.1M out × $20 = $6 a call at full price; batch halves it.
    assert all(c.batch for c in cost.calls) and all(c.usd == 3.0 for c in cost.calls)


def test_a_declined_item_is_billed_at_half_and_rerun_streamed_with_the_fallback():
    stories = _stories()
    batches = FakeBatches({stories[0].id: _msg(stop="refusal", text=None), stories[1].id: _msg()})
    client = FakeClient(batches, streamed=[_msg()])
    _, results, cost = _run(client)
    assert all(r.ok for r in results)
    assert len(client.stream_kwargs) == 1 and client.stream_kwargs[0]["fallbacks"] == "default"
    usds = sorted((c.batch, c.usd) for c in cost.calls)
    assert usds == [(False, 6.0), (True, 3.0), (True, 3.0)]


def test_errored_or_expired_items_are_rerun_streamed_without_using_the_retry():
    stories = _stories()
    batches = FakeBatches({stories[0].id: "errored", stories[1].id: "expired"})
    client = FakeClient(batches, streamed=[_msg(), _msg()])
    _, results, cost = _run(client)
    assert all(r.ok and r.attempts == 1 for r in results)
    assert len(cost.calls) == 2 and not any(c.batch for c in cost.calls)


def test_past_the_deadline_the_batch_is_cancelled_and_finished_items_are_kept():
    stories = _stories()
    batches = FakeBatches({stories[0].id: _msg()}, polls_until_end=10_000)
    client = FakeClient(batches)
    clock = iter(range(0, 10_000, 30))
    out = run_batch(client, {s.id: {"model": "claude-opus-5-5"} for s in stories}, stage="analysis",
                    deadline_s=60, poll_s=1, sleep=lambda _s: None, clock=lambda: next(clock))
    assert batches.cancelled
    assert out[stories[0].id].text == GOOD
    assert out[stories[1].id].kind == "batch_missing" and not out[stories[1].id].attempts


def test_grouping_uses_the_batch_and_falls_back_to_streamed():
    gcfg = GroupingConfig(model="claude-opus-5-5", effort="medium", max_tokens=64000, prompt_path=None)
    ok = json.dumps({"stories": [{"title": "T", "article_ids": ["a"]}]})
    client = FakeClient(FakeBatches({"grouping": _msg(text=ok)}))
    res = BatchFirstGrouper(gcfg, BCFG, client, sleep=lambda _s: None).group("S", "U")
    assert res.response.stories[0].title == "T" and all(a.batch for a in res.attempts)
    assert client.stream_kwargs == []

    client = FakeClient(FakeBatches({"grouping": "expired"}), streamed=[_msg(text=ok)])
    res = BatchFirstGrouper(gcfg, BCFG, client, sleep=lambda _s: None).group("S", "U")
    assert res.response.stories[0].title == "T" and len(client.stream_kwargs) == 1
    assert not any(a.batch for a in res.attempts)
