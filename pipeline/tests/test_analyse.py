"""Prompt building, the ClaudeAnalyser request shape (mocked client), FakeAnalyser replay, bounded concurrency
in story order, and the failed-call fallback. No network."""

import json
import threading
import time
from contextlib import contextmanager
from types import SimpleNamespace

import pytest

from conftest import aid, make_article, make_public
from sides_pipeline.analyse import (
    ANALYSIS_OUTPUT_SCHEMA,
    AnalysisConfig,
    AnalysisError,
    ClaudeAnalyser,
    FakeAnalyser,
    analyse_stories,
    build_story_message,
    load_analysis_config,
    sides_present,
)
from sides_pipeline.cost import ModelPrice, RunCost, Usage
from sides_pipeline.group import load_system_prompt
from sides_pipeline.llm import FALLBACK_BETA
from sides_pipeline.models import Story
from sides_pipeline.stories import RawStory, build_stories

CFG = AnalysisConfig(model="claude-opus-5-5", effort="high", max_tokens=32000, prompt_path=None, concurrency=4, retries=1)
PRICING = {"claude-opus-5-5": ModelPrice(4.0, 20.0, 0.2, 5.0)}

OUTLETS = [
    make_public("l1"), make_public("l2"),
    make_public("c1", lean="centre"),
    make_public("r1", lean="right"),
    make_public("e1", lean=None, bloc="east"),
]
OUTLET_MAP = {o.id: o for o in OUTLETS}


def make_story(*pairs, title="S0") -> Story:
    """pairs: (short_id, outlet_id). Builds a real Story through the phase-2 ranker."""
    arts = [make_article(p[0], p[1]) for p in pairs]
    stories, _ = build_stories([RawStory(title, [a.id for a in arts])], arts, OUTLETS)
    assert len(stories) == 1
    return stories[0]


def empty_response(**over):
    base = {k: [] for k in ("agreed_facts", "framing", "omissions", "contested_claims", "opinion", "framing_by_bloc", "east_west_contradictions")}
    base.update(over)
    return base


def fixture(response=None, *, stop="end_turn", inp=3000, out=800, model="claude-opus-5-5"):
    return {"model": model, "stop_reason": stop, "usage": {"input_tokens": inp, "output_tokens": out}, "response": response or empty_response()}


# ── config + prompt ───────────────────────────────────────────────────────────


def test_pipeline_yaml_has_analysis_section_with_high_effort_and_prompt():
    cfg = load_analysis_config()
    assert cfg.model == "claude-opus-5-5" and cfg.effort == "high"
    assert cfg.max_tokens >= 16000 and cfg.concurrency == 4 and cfg.retries == 1
    prompt = load_system_prompt(cfg.prompt_path)
    for phrase in ("ONLY headlines", "verbatim", "Never invent a side", "manufacture balance", "British English", "200 characters", "does not mention"):
        assert phrase in prompt, phrase


def test_story_message_lists_sides_present_and_one_line_per_article():
    story = make_story(("a", "l1"), ("b", "c1"), ("c", "e1"))
    msg = build_story_message(story, OUTLET_MAP)
    assert msg.startswith("Story: S0\n")
    assert "Leans with articles: left (1), centre (1)" in msg  # the lean=null East outlet is on no lean
    assert "Blocs with articles: west (2), east (1)" in msg
    block = msg.split("\n")[5:]
    assert block[0] == "<articles>" and block[-1] == "</articles>"  # SEC-1: feed text delimited as data
    lines = block[1:-1]
    assert len(lines) == 3
    parts = lines[0].split(" | ")
    assert len(parts) == 8 and parts[0] == story.articles[0].id
    assert any(" | n/a | east | " in ln for ln in lines)
    assert sides_present(story, OUTLET_MAP) == ({"left": 1, "centre": 1}, {"west": 2, "east": 1})


# ── ClaudeAnalyser with a mocked SDK client ───────────────────────────────────


class _FakeClient:
    def __init__(self, messages):
        self.messages = list(messages)
        self.kwargs = []
        self.beta = SimpleNamespace(messages=SimpleNamespace(stream=self._stream))

    @contextmanager
    def _stream(self, **kwargs):
        self.kwargs.append(kwargs)
        msg = self.messages.pop(0)
        yield SimpleNamespace(get_final_message=lambda: msg)


def _message(stop_reason="end_turn", text=None, model="claude-opus-5-5", stop_details=None):
    content = [SimpleNamespace(type="thinking", thinking="")]
    if text is not None:
        content.append(SimpleNamespace(type="text", text=text))
    return SimpleNamespace(
        stop_reason=stop_reason, stop_details=stop_details, content=content, model=model,
        usage=SimpleNamespace(input_tokens=2222, output_tokens=333, cache_read_input_tokens=0, cache_creation_input_tokens=0),
    )


def test_claude_analyser_sends_model_high_effort_structured_output_and_fallback():
    body = json.dumps(empty_response(agreed_facts=[{"text": "t", "sources": [aid("a")]}]))
    client = _FakeClient([_message(text=body)])
    result = ClaudeAnalyser(CFG, client=client).analyse("SYS", "USER", story_id="s1")

    kw = client.kwargs[0]
    assert kw["model"] == "claude-opus-5-5" and kw["max_tokens"] == 32000
    assert kw["system"] == "SYS" and kw["messages"] == [{"role": "user", "content": "USER"}]
    assert kw["output_config"]["effort"] == "high"
    assert kw["output_config"]["format"] == {"type": "json_schema", "schema": ANALYSIS_OUTPUT_SCHEMA}
    assert kw["betas"] == [FALLBACK_BETA] and kw["fallbacks"] == "default"
    assert "thinking" not in kw and "tool_choice" not in kw and "tools" not in kw
    assert result.response.agreed_facts[0].sources == [aid("a")]
    assert result.usage == Usage(2222, 333, 0, 0) and result.stop_reason == "end_turn"


def test_claude_analyser_raises_with_usage_on_refusal_and_max_tokens():
    details = SimpleNamespace(category="general_harms", explanation="no")
    with pytest.raises(AnalysisError, match="refused.*general_harms") as ei:
        ClaudeAnalyser(CFG, client=_FakeClient([_message(stop_reason="refusal", stop_details=details)])).analyse("S", "U", story_id="x")
    assert ei.value.kind == "refusal" and ei.value.usage == Usage(2222, 333, 0, 0)  # billed, so it is still costed
    with pytest.raises(AnalysisError, match="truncated") as ei:
        ClaudeAnalyser(CFG, client=_FakeClient([_message(stop_reason="max_tokens", text='{"agreed')])).analyse("S", "U", story_id="x")
    assert ei.value.kind == "max_tokens"
    with pytest.raises(AnalysisError, match="not valid analysis JSON") as ei:
        ClaudeAnalyser(CFG, client=_FakeClient([_message(text='{"agreed_facts": "x"}')])).analyse("S", "U", story_id="x")
    assert ei.value.kind == "bad_json"


def test_output_schema_is_structured_outputs_safe():
    """Structured outputs reject length/number keywords and need additionalProperties:false on every object."""
    def walk(node):
        if isinstance(node, dict):
            for bad in ("minLength", "maxLength", "minItems", "minimum", "maximum", "pattern"):
                assert bad not in node
            if node.get("type") == "object":
                assert node.get("additionalProperties") is False and set(node["required"]) == set(node["properties"])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(ANALYSIS_OUTPUT_SCHEMA)


# ── FakeAnalyser + orchestration ──────────────────────────────────────────────


def test_fake_analyser_replays_per_story_and_raises_on_refusal():
    fa = FakeAnalyser({"s1": fixture(), "s2": fixture(stop="refusal")})
    assert fa.analyse("S", "U", story_id="s1").usage == Usage(3000, 800, 0, 0)
    with pytest.raises(AnalysisError, match="refusal") as ei:
        fa.analyse("S", "U", story_id="s2")
    assert ei.value.usage == Usage(3000, 800, 0, 0)
    with pytest.raises(AnalysisError, match="no replay fixture"):
        fa.analyse("S", "U", story_id="s3")
    assert [c[0] for c in fa.calls] == ["s1", "s2", "s3"]


def test_fake_analyser_loads_a_directory_of_story_fixtures(tmp_path):
    (tmp_path / "abc.json").write_text(json.dumps(fixture()))
    fa = FakeAnalyser(tmp_path)
    assert fa.analyse("S", "U", story_id="abc").model == "claude-opus-5-5"


class _SlowAnalyser:
    """Finishes stories in reverse order and records how many run at once."""

    def __init__(self):
        self.in_flight = 0
        self.max_in_flight = 0
        self.lock = threading.Lock()

    def analyse(self, system, user, *, story_id):
        with self.lock:
            self.in_flight += 1
            self.max_in_flight = max(self.max_in_flight, self.in_flight)
        # later stories finish first
        rank = int(user.split("Story: S")[1].split("\n")[0])
        time.sleep(0.01 * (8 - rank))
        with self.lock:
            self.in_flight -= 1
        return FakeAnalyser({story_id: fixture(empty_response(agreed_facts=[{"text": f"from {rank}", "sources": []}]))}).analyse(system, user, story_id=story_id)


def test_analyse_stories_is_bounded_and_returns_results_in_story_order():
    stories = [make_story((f"a{i}", "l1"), (f"b{i}", "c1"), (f"c{i}", "r1"), title=f"S{i}") for i in range(1, 8)]
    slow = _SlowAnalyser()
    cfg = AnalysisConfig(model="claude-opus-5-5", effort="high", max_tokens=1, prompt_path=None, concurrency=3, retries=0)
    cost = RunCost(pricing=PRICING)
    results = analyse_stories(stories, OUTLETS, slow, cfg, cost, system_prompt="SYS")
    assert [r.story_id for r in results] == [s.id for s in stories]
    assert [r.response.agreed_facts[0].text for r in results] == [f"from {i}" for i in range(1, 8)]
    assert 1 < slow.max_in_flight <= 3
    assert len(cost.calls) == 7 and all(c.stage == "analysis" for c in cost.calls)


def test_failed_story_is_retried_once_then_reported_and_every_attempt_is_costed():
    s_ok, s_bad = make_story(("a", "l1"), ("b", "c1"), ("c", "r1"), title="ok"), make_story(("x", "l2"), ("y", "c1"), ("z", "e1"), title="bad")
    fa = FakeAnalyser({s_ok.id: fixture(), s_bad.id: fixture(stop="max_tokens", inp=1000, out=32000)})
    cost = RunCost(pricing=PRICING)
    results = analyse_stories([s_ok, s_bad], OUTLETS, fa, CFG, cost, system_prompt="SYS")
    assert results[0].ok and results[0].attempts == 1
    assert not results[1].ok and results[1].attempts == 2 and "max_tokens" in results[1].error
    assert sum(1 for c in fa.calls if c[0] == s_bad.id) == 2
    assert len(cost.calls) == 3  # 1 good + 2 failed attempts, all billed
    assert cost.total_usd == pytest.approx(3000 * 4e-6 + 800 * 20e-6 + 2 * (1000 * 4e-6 + 32000 * 20e-6))


def test_retry_succeeds_on_second_attempt():
    s = make_story(("a", "l1"), ("b", "c1"), ("c", "r1"))

    class Flaky:
        def __init__(self):
            self.n = 0

        def analyse(self, system, user, *, story_id):
            self.n += 1
            fx = fixture(stop="refusal") if self.n == 1 else fixture()
            return FakeAnalyser({story_id: fx}).analyse(system, user, story_id=story_id)

    results = analyse_stories([s], OUTLETS, Flaky(), CFG, RunCost(pricing=PRICING), system_prompt="SYS")
    assert results[0].ok and results[0].attempts == 2 and results[0].error is None
    assert results[0].raw_fixture["stop_reason"] == "end_turn"
