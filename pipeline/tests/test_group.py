"""Prompt building, the ClaudeGrouper request shape (mocked client) and FakeGrouper replay. No network."""

import json
from contextlib import contextmanager
from types import SimpleNamespace

import pytest

from conftest import RECORDED_AT, aid, make_article, make_public
from sides_pipeline.cost import ModelPrice, RunCost, Usage
from sides_pipeline.group import (
    FALLBACK_BETA,
    GROUPING_OUTPUT_SCHEMA,
    ClaudeGrouper,
    FakeGrouper,
    GroupingConfig,
    GroupingError,
    article_line,
    build_user_message,
    group_articles,
    load_grouping_config,
    load_system_prompt,
)
from sides_pipeline.models import CollectResult
from sides_pipeline.schema import validate_digest

CFG = GroupingConfig(model="claude-opus-5-5", effort="medium", max_tokens=64000, prompt_path=None)


def test_pipeline_yaml_loads_with_approved_model_and_prompt():
    cfg = load_grouping_config()
    assert cfg.model == "claude-opus-5-5" and cfg.effort == "medium"
    assert cfg.max_tokens >= 16000
    prompt = load_system_prompt(cfg.prompt_path)
    assert "same event" in prompt and "90 characters" in prompt and "sport" in prompt.lower()


def test_article_line_is_compact_and_pipe_safe():
    a = make_article("x", "bbc", headline="Head | line  with   spaces")
    line = article_line(a)
    parts = line.split(" | ")
    assert len(parts) == 5 and parts[0] == a.id and parts[1] == "bbc"
    assert parts[3] == "Head / line with spaces"
    assert parts[2].endswith("Z")


def test_user_message_has_articles_last_and_stable_order():
    arts = [make_article("b", "sky"), make_article("a", "bbc")]
    msg = build_user_message(arts, date="2026-10-14")
    assert msg.startswith("Articles collected for 2026-10-14 (2 items)")
    lines = msg.strip().split("\n")[-2:]
    assert lines[0].split(" | ")[1] == "bbc" and lines[1].split(" | ")[1] == "sky"


# ── ClaudeGrouper with a mocked SDK client ────────────────────────────────────


class _FakeClient:
    """Stands in for anthropic.Anthropic: records the kwargs and returns a canned final message."""

    def __init__(self, message):
        self.message = message
        self.kwargs = None
        self.beta = SimpleNamespace(messages=SimpleNamespace(stream=self._stream))

    @contextmanager
    def _stream(self, **kwargs):
        self.kwargs = kwargs
        yield SimpleNamespace(get_final_message=lambda: self.message)


def _message(stop_reason="end_turn", text=None, model="claude-opus-5-5", stop_details=None):
    content = [SimpleNamespace(type="thinking", thinking="")]
    if text is not None:
        content.append(SimpleNamespace(type="text", text=text))
    return SimpleNamespace(
        stop_reason=stop_reason,
        stop_details=stop_details,
        content=content,
        model=model,
        usage=SimpleNamespace(input_tokens=1234, output_tokens=56, cache_read_input_tokens=0, cache_creation_input_tokens=0),
    )


def test_claude_grouper_sends_model_effort_structured_output_and_fallback():
    body = json.dumps({"stories": [{"title": "T", "article_ids": ["aaaaaaaaaaaa"]}]})
    client = _FakeClient(_message(text=body))
    result = ClaudeGrouper(CFG, client=client).group("SYS", "USER")

    kw = client.kwargs
    assert kw["model"] == "claude-opus-5-5"
    assert kw["max_tokens"] == 64000
    assert kw["system"] == "SYS" and kw["messages"] == [{"role": "user", "content": "USER"}]
    assert kw["output_config"]["effort"] == "medium"
    assert kw["output_config"]["format"] == {"type": "json_schema", "schema": GROUPING_OUTPUT_SCHEMA}
    assert kw["betas"] == [FALLBACK_BETA] and kw["fallbacks"] == "default"
    # Things that 400 on this model must not be sent.
    assert "thinking" not in kw and "tool_choice" not in kw and "tools" not in kw
    assert kw["messages"][-1]["role"] == "user"  # no assistant prefill

    assert result.response.stories[0].article_ids == ["aaaaaaaaaaaa"]
    assert result.usage == Usage(1234, 56, 0, 0)
    assert result.model == "claude-opus-5-5" and result.stop_reason == "end_turn"


def test_claude_grouper_raises_on_refusal():
    details = SimpleNamespace(category="general_harms", explanation="nope")
    client = _FakeClient(_message(stop_reason="refusal", stop_details=details))
    with pytest.raises(GroupingError, match="refused.*general_harms"):
        ClaudeGrouper(CFG, client=client).group("S", "U")


def test_claude_grouper_raises_on_max_tokens():
    client = _FakeClient(_message(stop_reason="max_tokens", text='{"stories": ['))
    with pytest.raises(GroupingError, match="truncated"):
        ClaudeGrouper(CFG, client=client).group("S", "U")


def test_claude_grouper_raises_on_bad_json_or_missing_text():
    with pytest.raises(GroupingError, match="not valid grouping JSON"):
        ClaudeGrouper(CFG, client=_FakeClient(_message(text='{"stories": "x"}'))).group("S", "U")
    with pytest.raises(GroupingError, match="no text block"):
        ClaudeGrouper(CFG, client=_FakeClient(_message(text=None))).group("S", "U")


# ── end-to-end with FakeGrouper (synthetic) ───────────────────────────────────


def _collected(articles, outlets):
    return CollectResult(collected_at=RECORDED_AT, outlets=outlets, articles=articles, feed_errors=[], per_outlet_counts={})


def test_group_articles_end_to_end_with_fake_grouper_produces_schema_valid_digest(tmp_path):
    outlets = [make_public("l1"), make_public("c1", lean="centre"), make_public("r1", lean="right"), make_public("e1", lean=None, bloc="east")]
    articles = [make_article("a", "l1"), make_article("b", "c1"), make_article("c", "r1"), make_article("d", "e1"), make_article("z", "l1")]
    fixture = {
        "model": "claude-opus-5-5",
        "stop_reason": "end_turn",
        "usage": {"input_tokens": 10_000, "output_tokens": 500},
        "response": {"stories": [
            {"title": "A real story", "article_ids": [aid("a"), aid("b"), aid("c"), aid("d"), "ffffffffffff"]},
            {"title": "Too thin", "article_ids": [aid("z")]},
        ]},
    }
    grouper = FakeGrouper(fixture)
    cost = RunCost(pricing={"claude-opus-5-5": ModelPrice(4.0, 20.0, 0.2, 5.0)})
    outcome = group_articles(_collected(articles, outlets), grouper, CFG, cost, now=RECORDED_AT, system_prompt="SYS")

    assert grouper.calls[0][0] == "SYS" and aid("a") in grouper.calls[0][1]
    d = outcome.digest
    assert d.date == "2026-10-14" and d.meta.model == "claude-opus-5-5"
    assert d.meta.cost_usd == pytest.approx(0.04 + 0.01)
    assert d.meta.outlets_polled == 4 and d.meta.articles_collected == 5
    assert len(d.stories) == 1 and d.stories[0].outlet_count == 4
    assert d.stories[0].blindspot.model_dump() == {"lean": None, "bloc": None}
    assert outcome.report.unknown_ids_dropped == 1 and outcome.report.below_min_outlets_dropped == 1
    assert any("only 1 stories" in w for w in d.meta.warnings)
    payload = d.model_dump(mode="json")
    validate_digest(payload)
    (tmp_path / "stories.json").write_text(json.dumps(payload))
    validate_digest(json.loads((tmp_path / "stories.json").read_text()))


def test_fake_grouper_replays_refusal_as_error():
    with pytest.raises(GroupingError):
        FakeGrouper({"stop_reason": "refusal", "response": {"stories": []}}).group("S", "U")
