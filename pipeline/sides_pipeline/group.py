"""Phase 2, LLM half: ask Claude to group the day's articles into stories.

The model only proposes ``stories[] { title, article_ids[] }``. Validation, the ≥3-distinct-outlet rule,
ranking and coverage statistics are all computed afterwards in :mod:`stories` (integrity rule 3).

The request is a clean prefix: the stable system prompt (config/prompts/group.md) comes first and the
day's article lines last, so prompt caching would work unchanged if the pipeline ever ran more than once a day.
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Protocol

import yaml
from pydantic import BaseModel, ConfigDict, Field

from .cost import RunCost, Usage
from .models import Article, CollectResult, Digest, DigestMeta, OutletPublic
from .stories import MIN_OUTLETS, MIN_STORIES, TOP_N, RawStory, ValidationReport, build_stories

log = logging.getLogger(__name__)

CONFIG_DIR = Path(__file__).resolve().parent.parent / "config"
DEFAULT_PIPELINE_CONFIG = CONFIG_DIR / "pipeline.yaml"
STAGE = "grouping"
FALLBACK_BETA = "server-side-fallback-2026-07-01"

# JSON schema sent as output_config.format. Kept minimal (structured outputs reject many keywords);
# title length and id validity are enforced in code afterwards.
GROUPING_OUTPUT_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "stories": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Neutral title, at most 90 characters, own wording"},
                    "article_ids": {"type": "array", "items": {"type": "string"}, "description": "ids copied exactly from the input"},
                },
                "required": ["title", "article_ids"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["stories"],
    "additionalProperties": False,
}


class GroupingError(RuntimeError):
    """The grouping call did not produce a usable response; the run must fail, never emit a partial digest."""


# ── config ────────────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class GroupingConfig:
    model: str
    effort: str
    max_tokens: int
    prompt_path: Path
    min_outlets: int = MIN_OUTLETS
    top_n: int = TOP_N
    min_stories: int = MIN_STORIES


def load_grouping_config(path: str | Path = DEFAULT_PIPELINE_CONFIG) -> GroupingConfig:
    path = Path(path)
    with open(path, "rb") as fh:
        data = yaml.safe_load(fh) or {}
    model = data.get("model")
    g = data.get("grouping") or {}
    if not model or "effort" not in g or "max_tokens" not in g or "prompt" not in g:
        raise ValueError(f"{path}: needs 'model' and grouping.effort/max_tokens/prompt")
    if g["effort"] not in ("low", "medium", "high", "xhigh", "max"):
        raise ValueError(f"{path}: grouping.effort must be low|medium|high|xhigh|max")
    return GroupingConfig(
        model=str(model),
        effort=str(g["effort"]),
        max_tokens=int(g["max_tokens"]),
        prompt_path=(path.parent / g["prompt"]).resolve(),
        min_outlets=int(g.get("min_outlets", MIN_OUTLETS)),
        top_n=int(g.get("top_n", TOP_N)),
        min_stories=int(g.get("min_stories", MIN_STORIES)),
    )


# ── prompt ────────────────────────────────────────────────────────────────────


def _cell(s: str) -> str:
    return " ".join(s.replace("|", "/").split())


def article_line(a: Article) -> str:
    ts = a.published_at.astimezone(UTC).strftime("%Y-%m-%dT%H:%MZ")
    return f"{a.id} | {a.outlet_id} | {ts} | {_cell(a.headline)} | {_cell(a.snippet)}"


def build_user_message(articles: list[Article], *, date: str) -> str:
    lines = [article_line(a) for a in sorted(articles, key=lambda a: (a.outlet_id, a.published_at, a.id))]
    return f"Articles collected for {date} ({len(lines)} items):\n\n" + "\n".join(lines)


def load_system_prompt(path: Path) -> str:
    text = path.read_text().strip()
    if not text:
        raise ValueError(f"{path}: empty prompt")
    return text


# ── grouper protocol + implementations ────────────────────────────────────────


class GroupingResponse(BaseModel):
    """The model's structured output, parsed and shape-checked."""

    model_config = ConfigDict(extra="forbid")

    class Item(BaseModel):
        model_config = ConfigDict(extra="forbid")
        title: str
        article_ids: list[str]

    stories: list[Item] = Field(default_factory=list)


@dataclass(frozen=True)
class GroupingResult:
    response: GroupingResponse
    usage: Usage
    model: str
    stop_reason: str
    seconds: float


class Grouper(Protocol):
    def group(self, system: str, user: str) -> GroupingResult: ...


class ClaudeGrouper:
    """Thin wrapper over the Anthropic SDK: one streamed, structured-output request per run."""

    def __init__(self, cfg: GroupingConfig, client=None):  # noqa: ANN001 - anthropic.Anthropic or a test double
        self.cfg = cfg
        if client is None:
            import anthropic  # imported lazily so tests never need the real client

            client = anthropic.Anthropic()  # key from ANTHROPIC_API_KEY (see README: Keychain recipe)
        self.client = client

    def request_kwargs(self, system: str, user: str) -> dict:
        return dict(
            model=self.cfg.model,
            max_tokens=self.cfg.max_tokens,
            system=system,
            messages=[{"role": "user", "content": user}],
            # Thinking is always on for this model; effort is the only depth control (no `thinking`, no budget).
            output_config={
                "effort": self.cfg.effort,
                "format": {"type": "json_schema", "schema": GROUPING_OUTPUT_SCHEMA},
            },
            # Server-side refusal fallback, routed by refusal category.
            betas=[FALLBACK_BETA],
            fallbacks="default",
        )

    def group(self, system: str, user: str) -> GroupingResult:
        started = time.monotonic()
        with self.client.beta.messages.stream(**self.request_kwargs(system, user)) as stream:
            message = stream.get_final_message()
        seconds = time.monotonic() - started

        usage = Usage.from_response_usage(message.usage)
        served_by = getattr(message, "model", self.cfg.model) or self.cfg.model
        if served_by != self.cfg.model:
            log.warning("grouping was served by fallback model %s (requested %s)", served_by, self.cfg.model)
        stop = message.stop_reason
        if stop == "refusal":
            details = getattr(message, "stop_details", None)
            cat = getattr(details, "category", None)
            expl = getattr(details, "explanation", None)
            raise GroupingError(f"model refused the grouping request (category={cat!r}): {expl or 'no explanation'}")
        if stop == "max_tokens":
            raise GroupingError(
                f"grouping response was truncated at max_tokens={self.cfg.max_tokens}; raise grouping.max_tokens"
            )
        if stop not in ("end_turn", "stop_sequence"):
            raise GroupingError(f"unexpected stop_reason {stop!r} from grouping call")

        text = next((b.text for b in message.content if getattr(b, "type", None) == "text"), None)
        if text is None:
            raise GroupingError("grouping response contained no text block")
        try:
            response = GroupingResponse.model_validate_json(text)
        except ValueError as exc:
            raise GroupingError(f"grouping response was not valid grouping JSON: {exc}") from exc
        return GroupingResult(response=response, usage=usage, model=served_by, stop_reason=stop, seconds=seconds)


class FakeGrouper:
    """Replays a recorded response from tests/fixtures/llm/group_*.json (no network).

    Fixture shape: ``{"model": str, "stop_reason": str, "usage": {input_tokens, output_tokens, …},
    "response": {"stories": [{"title", "article_ids"}]}}``. Raises like the real grouper on
    refusal / max_tokens so the CLI path is exercised identically.
    """

    def __init__(self, fixture: str | Path | dict):
        self.data = json.loads(Path(fixture).read_text()) if not isinstance(fixture, dict) else fixture
        self.calls: list[tuple[str, str]] = []

    def group(self, system: str, user: str) -> GroupingResult:
        self.calls.append((system, user))
        stop = self.data.get("stop_reason", "end_turn")
        if stop == "refusal":
            raise GroupingError("model refused the grouping request (replayed fixture)")
        if stop == "max_tokens":
            raise GroupingError("grouping response was truncated at max_tokens (replayed fixture)")
        u = self.data.get("usage", {})
        usage = Usage(
            input_tokens=int(u.get("input_tokens", 0)),
            output_tokens=int(u.get("output_tokens", 0)),
            cache_read_tokens=int(u.get("cache_read_input_tokens", 0)),
            cache_write_tokens=int(u.get("cache_creation_input_tokens", 0)),
        )
        return GroupingResult(
            response=GroupingResponse.model_validate(self.data["response"]),
            usage=usage,
            model=self.data.get("model", "fake"),
            stop_reason=stop,
            seconds=0.0,
        )


# ── orchestration ─────────────────────────────────────────────────────────────


@dataclass
class GroupOutcome:
    digest: Digest
    report: ValidationReport
    result: GroupingResult
    raw_response: dict


def group_articles(
    collected: CollectResult,
    grouper: Grouper,
    cfg: GroupingConfig,
    cost: RunCost,
    *,
    now: datetime | None = None,
    system_prompt: str | None = None,
) -> GroupOutcome:
    """articles.json → ranked stories digest (without analysis). Records the call in ``cost``."""
    now = now or datetime.now(tz=UTC)
    date = now.date().isoformat()
    system = system_prompt if system_prompt is not None else load_system_prompt(cfg.prompt_path)
    user = build_user_message(collected.articles, date=date)

    result = grouper.group(system, user)
    cost.record(STAGE, result.model, result.usage, seconds=result.seconds)
    log.info(
        "grouping: %d raw stories, %d in / %d out tokens, %.1fs",
        len(result.response.stories), result.usage.input_tokens, result.usage.output_tokens, result.seconds,
    )

    raw = [RawStory(title=s.title, article_ids=list(s.article_ids)) for s in result.response.stories]
    stories, report = build_stories(
        raw, collected.articles, collected.outlets,
        min_outlets=cfg.min_outlets, top_n=cfg.top_n, min_stories=cfg.min_stories,
    )
    warnings = list(report.warnings)
    if collected.feed_errors:
        warnings.append(f"{len(collected.feed_errors)} feed(s) failed during collect")

    digest = Digest(
        generated_at=now,
        date=date,
        meta=DigestMeta(
            model=result.model,
            cost_usd=cost.total_usd,
            outlets_polled=len(collected.outlets),
            articles_collected=len(collected.articles),
            warnings=warnings,
        ),
        outlets=list(collected.outlets),
        stories=stories,
    )
    return GroupOutcome(digest=digest, report=report, result=result, raw_response=result.response.model_dump())


def outlets_by_id(outlets: list[OutletPublic]) -> dict[str, OutletPublic]:
    return {o.id: o for o in outlets}
