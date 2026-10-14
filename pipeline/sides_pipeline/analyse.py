"""Phase 3, LLM half: one structured-output call per story asking how each lean and each bloc frames it.

The model only proposes items. :mod:`validate` then drops, deterministically, every item that is not fully
sourced to this story's articles (integrity rule 2), and :mod:`digest` assembles the published document.

Concurrency: the stories are analysed on a bounded thread pool (``analysis.concurrency`` in pipeline.yaml,
default 4) and results come back in story order. A story whose call fails after ``analysis.retries`` extra
attempts is reported as failed; the digest keeps it with empty analysis arrays and a ``meta.warnings`` entry.
"""

from __future__ import annotations

import json
import logging
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import UTC
from pathlib import Path
from typing import Protocol

import yaml
from pydantic import BaseModel, ConfigDict, Field

from .cost import RunCost, Usage
from .group import CONFIG_DIR, DEFAULT_PIPELINE_CONFIG, _cell, load_system_prompt
from .llm import EFFORT_LEVELS, LLMError, make_client, run_structured, structured_request_kwargs, usage_from_fixture
from .models import Article, OutletPublic, Story

log = logging.getLogger(__name__)

STAGE = "analysis"
DEFAULT_CONCURRENCY = 4
DEFAULT_RETRIES = 1

# JSON schema sent as output_config.format. Structured outputs reject length/number constraints, so text
# length, id validity and side/bloc consistency are enforced afterwards in validate.py.
_IDS = {"type": "array", "items": {"type": "string"}}
_SOURCED = {
    "type": "object",
    "properties": {"text": {"type": "string"}, "sources": {**_IDS, "description": "article ids from this story"}},
    "required": ["text", "sources"],
    "additionalProperties": False,
}
_QUOTE = {
    "type": "object",
    "properties": {
        "article_id": {"type": "string"},
        "quote": {"type": "string", "description": "verbatim substring of that article's headline or snippet"},
    },
    "required": ["article_id", "quote"],
    "additionalProperties": False,
}
_FRAMING_PROPS = {"headline_quotes": {"type": "array", "items": _QUOTE}, "emphasis": {"type": "array", "items": _SOURCED}}
ANALYSIS_OUTPUT_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "agreed_facts": {"type": "array", "items": _SOURCED},
        "framing": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"lean": {"type": "string", "enum": ["left", "centre", "right"]}, **_FRAMING_PROPS},
                "required": ["lean", "headline_quotes", "emphasis"],
                "additionalProperties": False,
            },
        },
        "omissions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "lean": {"type": "string", "enum": ["left", "centre", "right"], "description": "the lean whose coverage lacks the point"},
                    "text": {"type": "string"},
                    "sources": {**_IDS, "description": "articles of OTHER leans that carry the point"},
                },
                "required": ["lean", "text", "sources"],
                "additionalProperties": False,
            },
        },
        "contested_claims": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"claim": {"type": "string"}, "asserted_by": _IDS, "disputed_by": _IDS},
                "required": ["claim", "asserted_by", "disputed_by"],
                "additionalProperties": False,
            },
        },
        "opinion": {"type": "array", "items": _SOURCED},
        "framing_by_bloc": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"bloc": {"type": "string", "enum": ["west", "east"]}, **_FRAMING_PROPS},
                "required": ["bloc", "headline_quotes", "emphasis"],
                "additionalProperties": False,
            },
        },
        "east_west_contradictions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"topic": {"type": "string"}, "west": _SOURCED, "east": _SOURCED},
                "required": ["topic", "west", "east"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["agreed_facts", "framing", "omissions", "contested_claims", "opinion", "framing_by_bloc", "east_west_contradictions"],
    "additionalProperties": False,
}


class AnalysisError(RuntimeError):
    """One story's analysis call produced nothing usable (refusal, truncation, bad JSON). Per story, not fatal."""


# ── config ────────────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class AnalysisConfig:
    model: str
    effort: str
    max_tokens: int
    prompt_path: Path | None
    concurrency: int = DEFAULT_CONCURRENCY
    retries: int = DEFAULT_RETRIES


def load_analysis_config(path: str | Path = DEFAULT_PIPELINE_CONFIG) -> AnalysisConfig:
    path = Path(path)
    with open(path, "rb") as fh:
        data = yaml.safe_load(fh) or {}
    model = data.get("model")
    a = data.get("analysis") or {}
    if not model or "effort" not in a or "max_tokens" not in a or "prompt" not in a:
        raise ValueError(f"{path}: needs 'model' and analysis.effort/max_tokens/prompt")
    if a["effort"] not in EFFORT_LEVELS:
        raise ValueError(f"{path}: analysis.effort must be one of {'|'.join(EFFORT_LEVELS)}")
    return AnalysisConfig(
        model=str(model),
        effort=str(a["effort"]),
        max_tokens=int(a["max_tokens"]),
        prompt_path=(path.parent / a["prompt"]).resolve(),
        concurrency=max(1, int(a.get("concurrency", DEFAULT_CONCURRENCY))),
        retries=max(0, int(a.get("retries", DEFAULT_RETRIES))),
    )


# ── prompt ────────────────────────────────────────────────────────────────────


def story_article_line(a: Article, outlet: OutletPublic | None) -> str:
    ts = a.published_at.astimezone(UTC).strftime("%Y-%m-%dT%H:%MZ")
    name = outlet.name if outlet else a.outlet_id
    lean = (outlet.lean if outlet and outlet.lean else "n/a")
    bloc = outlet.bloc if outlet else "?"
    own = outlet.ownership if outlet else "?"
    return f"{a.id} | {_cell(name)} | {lean} | {bloc} | {own} | {ts} | {_cell(a.headline)} | {_cell(a.snippet)}"


def sides_present(story: Story, outlets: dict[str, OutletPublic]) -> tuple[dict[str, int], dict[str, int]]:
    """Articles (not outlets) per lean and per bloc, for the prompt header and the validator."""
    leans: dict[str, int] = {}
    blocs: dict[str, int] = {}
    for a in story.articles:
        o = outlets.get(a.outlet_id)
        if o is None:
            continue
        if o.lean:
            leans[o.lean] = leans.get(o.lean, 0) + 1
        blocs[o.bloc] = blocs.get(o.bloc, 0) + 1
    return leans, blocs


def build_story_message(story: Story, outlets: dict[str, OutletPublic]) -> str:
    leans, blocs = sides_present(story, outlets)
    order_l = [x for x in ("left", "centre", "right") if x in leans]
    order_b = [x for x in ("west", "east") if x in blocs]
    lean_line = ", ".join(f"{x} ({leans[x]})" for x in order_l) or "none (no article is on the left/centre/right scale)"
    bloc_line = ", ".join(f"{x} ({blocs[x]})" for x in order_b)
    lines = [story_article_line(a, outlets.get(a.outlet_id)) for a in story.articles]
    return (
        f"Story: {story.title}\n"
        f"Leans with articles: {lean_line}\n"
        f"Blocs with articles: {bloc_line}\n"
        f"Articles ({len(lines)}):\n\n" + "\n".join(lines)
    )


# ── analyser protocol + implementations ───────────────────────────────────────


class AnalysisResponse(BaseModel):
    """The model's structured output for one story, parsed and shape-checked (not yet validated)."""

    model_config = ConfigDict(extra="forbid")

    class Sourced(BaseModel):
        model_config = ConfigDict(extra="forbid")
        text: str
        sources: list[str]

    class Quote(BaseModel):
        model_config = ConfigDict(extra="forbid")
        article_id: str
        quote: str

    class LeanFraming(BaseModel):
        model_config = ConfigDict(extra="forbid")
        lean: str
        headline_quotes: list["AnalysisResponse.Quote"]
        emphasis: list["AnalysisResponse.Sourced"]

    class BlocFraming(BaseModel):
        model_config = ConfigDict(extra="forbid")
        bloc: str
        headline_quotes: list["AnalysisResponse.Quote"]
        emphasis: list["AnalysisResponse.Sourced"]

    class Omission(BaseModel):
        model_config = ConfigDict(extra="forbid")
        lean: str
        text: str
        sources: list[str]

    class Contested(BaseModel):
        model_config = ConfigDict(extra="forbid")
        claim: str
        asserted_by: list[str]
        disputed_by: list[str]

    class Contradiction(BaseModel):
        model_config = ConfigDict(extra="forbid")
        topic: str
        west: "AnalysisResponse.Sourced"
        east: "AnalysisResponse.Sourced"

    agreed_facts: list[Sourced] = Field(default_factory=list)
    framing: list[LeanFraming] = Field(default_factory=list)
    omissions: list[Omission] = Field(default_factory=list)
    contested_claims: list[Contested] = Field(default_factory=list)
    opinion: list[Sourced] = Field(default_factory=list)
    framing_by_bloc: list[BlocFraming] = Field(default_factory=list)
    east_west_contradictions: list[Contradiction] = Field(default_factory=list)


@dataclass(frozen=True)
class AnalysisResult:
    response: AnalysisResponse
    usage: Usage
    model: str
    stop_reason: str
    seconds: float


class Analyser(Protocol):
    def analyse(self, system: str, user: str, *, story_id: str) -> AnalysisResult: ...


class ClaudeAnalyser:
    """One streamed, structured-output request per story through the shared wrapper in :mod:`llm`.

    On an unusable response (refusal / max_tokens / no text / bad JSON) raises AnalysisError carrying the
    billed usage, so the orchestrator can account for it and decide whether to retry.
    """

    def __init__(self, cfg: AnalysisConfig, client=None):  # noqa: ANN001 - anthropic.Anthropic or a test double
        self.cfg = cfg
        self.client = client if client is not None else make_client()

    def request_kwargs(self, system: str, user: str) -> dict:
        return structured_request_kwargs(
            model=self.cfg.model, max_tokens=self.cfg.max_tokens, effort=self.cfg.effort,
            system=system, user=user, schema=ANALYSIS_OUTPUT_SCHEMA,
        )

    def analyse(self, system: str, user: str, *, story_id: str) -> AnalysisResult:
        try:
            res = run_structured(self.client, self.request_kwargs(system, user), stage=STAGE)
        except LLMError as exc:
            err = AnalysisError(f"story {story_id}: {exc}")
            err.usage, err.model, err.kind = exc.usage, exc.model, exc.kind  # type: ignore[attr-defined]
            raise err from exc
        try:
            response = AnalysisResponse.model_validate_json(res.text)
        except ValueError as exc:
            err = AnalysisError(f"story {story_id}: analysis response was not valid analysis JSON: {exc}")
            err.usage, err.model, err.kind = res.usage, res.model, "bad_json"  # type: ignore[attr-defined]
            raise err from exc
        return AnalysisResult(response=response, usage=res.usage, model=res.model, stop_reason=res.stop_reason, seconds=res.seconds)


class FakeAnalyser:
    """Replays recorded responses, one fixture per story id (no network).

    ``fixtures`` is a directory of ``<story_id>.json`` files or a ``{story_id: fixture}`` dict. Each fixture has
    the same shape as the grouping ones: ``{"model", "stop_reason", "usage", "response": {...analysis...}}``.
    A replayed ``refusal`` / ``max_tokens`` raises AnalysisError exactly like the real analyser. A story with no
    fixture uses ``default`` when given, else raises AnalysisError (the orchestrator then marks it failed).
    """

    def __init__(self, fixtures: str | Path | dict[str, dict], *, default: dict | None = None):
        if isinstance(fixtures, dict):
            self.data = dict(fixtures)
        else:
            self.data = {p.stem: json.loads(p.read_text()) for p in sorted(Path(fixtures).glob("*.json"))}
        self.default = default
        self.calls: list[tuple[str, str, str]] = []

    def analyse(self, system: str, user: str, *, story_id: str) -> AnalysisResult:
        self.calls.append((story_id, system, user))
        fx = self.data.get(story_id, self.default)
        if fx is None:
            raise AnalysisError(f"story {story_id}: no replay fixture")
        stop = fx.get("stop_reason", "end_turn")
        usage = usage_from_fixture(fx.get("usage", {}))
        if stop in ("refusal", "max_tokens"):
            err = AnalysisError(f"story {story_id}: replayed fixture stop_reason={stop}")
            err.usage, err.model, err.kind = usage, fx.get("model", "fake"), stop  # type: ignore[attr-defined]
            raise err
        return AnalysisResult(
            response=AnalysisResponse.model_validate(fx["response"]),
            usage=usage,
            model=fx.get("model", "fake"),
            stop_reason=stop,
            seconds=0.0,
        )


# ── orchestration ─────────────────────────────────────────────────────────────


@dataclass
class StoryAnalysis:
    """What one story's analysis call(s) produced: the raw response (None when every attempt failed)."""

    story_id: str
    response: AnalysisResponse | None
    attempts: int
    error: str | None = None
    usage: list[Usage] = field(default_factory=list)
    model: str | None = None
    seconds: float = 0.0
    raw_fixture: dict | None = None  # the last successful response in fixture shape (for --raw-out-dir)

    @property
    def ok(self) -> bool:
        return self.response is not None


def analyse_one(story: Story, analyser: Analyser, cfg: AnalysisConfig, system: str, outlets: dict[str, OutletPublic]) -> StoryAnalysis:
    user = build_story_message(story, outlets)
    out = StoryAnalysis(story_id=story.id, response=None, attempts=0)
    for attempt in range(1 + cfg.retries):
        out.attempts = attempt + 1
        try:
            res = analyser.analyse(system, user, story_id=story.id)
        except AnalysisError as exc:
            u = getattr(exc, "usage", None)
            if u is not None:
                out.usage.append(u)
                out.model = getattr(exc, "model", None) or out.model
            out.error = str(exc)
            log.warning("analysis attempt %d/%d failed for story %s (%s): %s", attempt + 1, 1 + cfg.retries, story.id, getattr(exc, "kind", "?"), exc)
            continue
        out.usage.append(res.usage)
        out.model = res.model
        out.seconds = res.seconds
        out.response = res.response
        out.error = None
        out.raw_fixture = {
            "model": res.model,
            "stop_reason": res.stop_reason,
            "usage": {
                "input_tokens": res.usage.input_tokens,
                "output_tokens": res.usage.output_tokens,
                "cache_read_input_tokens": res.usage.cache_read_tokens,
                "cache_creation_input_tokens": res.usage.cache_write_tokens,
            },
            "response": res.response.model_dump(),
        }
        break
    return out


def analyse_stories(
    stories: list[Story],
    outlets: list[OutletPublic],
    analyser: Analyser,
    cfg: AnalysisConfig,
    cost: RunCost,
    *,
    system_prompt: str | None = None,
) -> list[StoryAnalysis]:
    """Analyse every story (bounded concurrency), return results in story order, record every billed call."""
    system = system_prompt if system_prompt is not None else load_system_prompt(cfg.prompt_path)
    outlet_map = {o.id: o for o in outlets}
    if not stories:
        return []
    with ThreadPoolExecutor(max_workers=min(cfg.concurrency, len(stories))) as pool:
        results = list(pool.map(lambda s: analyse_one(s, analyser, cfg, system, outlet_map), stories))
    for r in results:
        for u in r.usage:
            cost.record(STAGE, r.model or cfg.model, u, seconds=r.seconds if r.ok else None)
    ok = sum(1 for r in results if r.ok)
    log.info("analysis: %d/%d stories analysed, %d calls", ok, len(results), sum(len(r.usage) for r in results))
    return results


__all__ = [
    "ANALYSIS_OUTPUT_SCHEMA", "AnalysisConfig", "AnalysisError", "AnalysisResponse", "AnalysisResult", "Analyser",
    "ClaudeAnalyser", "FakeAnalyser", "StoryAnalysis", "analyse_one", "analyse_stories", "build_story_message",
    "load_analysis_config", "sides_present", "story_article_line", "CONFIG_DIR",
]
