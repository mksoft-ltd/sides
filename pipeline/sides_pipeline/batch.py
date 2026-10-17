"""Batch-first LLM stages: the daily run's calls go through the Message Batches API at half price.

Nothing about a stage's output changes. Each wrapper asks the batch first and hands back its answer; any request
the batch could not serve (declined, truncated, errored, expired, unfinished at the deadline) is re-run through the
normal streamed path, which keeps the server-side refusal fallback and the usual retry. Billed batch attempts are
recorded with ``batch=True`` (priced at half in cost.py), so the cost report stays exact.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from pathlib import Path

import yaml

from .analyse import (
    ANALYSIS_OUTPUT_SCHEMA,
    AnalysisConfig,
    AnalysisError,
    AnalysisResponse,
    AnalysisResult,
    ClaudeAnalyser,
    build_story_message,
)
from .group import ClaudeGrouper, GroupingConfig, GroupingError, GroupingResponse, GroupingResult
from .llm import LLMError, StructuredResult, run_batch, structured_request_kwargs
from .models import OutletPublic, Story

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class BatchConfig:
    enabled: bool = False
    deadline_s: float = 900.0
    poll_s: float = 20.0


def load_batch_config(path: str | Path) -> BatchConfig:
    data = yaml.safe_load(Path(path).read_text()) or {}
    b = data.get("batch") or {}
    return BatchConfig(
        enabled=bool(b.get("enabled", False)),
        deadline_s=float(b.get("deadline_minutes", 15)) * 60,
        poll_s=float(b.get("poll_seconds", 20)),
    )


class BatchFirstGrouper:
    """The one grouping request through the batch; the streamed grouper when the batch cannot serve it."""

    def __init__(self, cfg: GroupingConfig, batch: BatchConfig, client=None, *, sleep=time.sleep):  # noqa: ANN001
        self.sync = ClaudeGrouper(cfg, client)
        self.batch = batch
        self.sleep = sleep
        self.batch_attempts: tuple = ()  # billed batch attempts that did not produce the result (declined etc.)

    def group(self, system: str, user: str) -> GroupingResult:
        kwargs = self.sync.request_kwargs(system, user)
        got = run_batch(self.sync.client, {"grouping": kwargs}, stage="grouping",
                        deadline_s=self.batch.deadline_s, poll_s=self.batch.poll_s, sleep=self.sleep)["grouping"]
        if isinstance(got, StructuredResult):
            try:
                response = GroupingResponse.model_validate_json(got.text)
                return GroupingResult(response=response, usage=got.usage, model=got.model,
                                      stop_reason=got.stop_reason, seconds=got.seconds, attempts=got.attempts)
            except ValueError as exc:
                log.warning("grouping: batch answer was not valid JSON (%s); running it again streamed", exc)
                self.batch_attempts = got.attempts
        else:
            log.warning("grouping: batch could not serve it (%s); running it streamed", got.kind)
            self.batch_attempts = got.attempts
        try:
            res = self.sync.group(system, user)
        except GroupingError as exc:
            raise GroupingError(str(exc), tuple(self.batch_attempts) + tuple(exc.attempts)) from exc
        return GroupingResult(response=res.response, usage=res.usage, model=res.model, stop_reason=res.stop_reason,
                              seconds=res.seconds, attempts=tuple(self.batch_attempts) + tuple(res.billed))


class BatchFirstAnalyser:
    """Every story's first attempt comes from one batch submitted up front; retries and anything the batch could
    not serve go to the streamed analyser. Implements the same ``analyse`` protocol as ClaudeAnalyser."""

    def __init__(self, cfg: AnalysisConfig, batch: BatchConfig, client=None, *, sleep=time.sleep):  # noqa: ANN001
        self.sync = ClaudeAnalyser(cfg, client)
        self.batch = batch
        self.sleep = sleep
        self.results: dict[str, StructuredResult | LLMError] = {}

    def prefetch(self, stories: list[Story], outlets: list[OutletPublic], system: str) -> None:
        outlet_map = {o.id: o for o in outlets}
        requests = {
            s.id: structured_request_kwargs(
                model=self.sync.cfg.model, max_tokens=self.sync.cfg.max_tokens, effort=self.sync.cfg.effort,
                system=system, user=build_story_message(s, outlet_map), schema=ANALYSIS_OUTPUT_SCHEMA,
            )
            for s in stories
        }
        self.results = run_batch(self.sync.client, requests, stage="analysis",
                                 deadline_s=self.batch.deadline_s, poll_s=self.batch.poll_s, sleep=self.sleep)

    def analyse(self, system: str, user: str, *, story_id: str) -> AnalysisResult:
        got = self.results.pop(story_id, None)
        if isinstance(got, StructuredResult):
            try:
                response = AnalysisResponse.model_validate_json(got.text)
                return AnalysisResult(response=response, usage=got.usage, model=got.model,
                                      stop_reason=got.stop_reason, seconds=got.seconds, attempts=got.attempts)
            except ValueError as exc:
                err = AnalysisError(f"story {story_id}: batch analysis was not valid analysis JSON: {exc}")
                err.usage, err.model, err.kind = got.usage, got.model, "bad_json"  # type: ignore[attr-defined]
                err.attempts = got.attempts  # type: ignore[attr-defined]
                raise err from exc
        if isinstance(got, LLMError) and got.attempts:
            # Billed (declined / truncated in the batch): count it as this attempt; the retry runs streamed.
            err = AnalysisError(f"story {story_id}: {got}")
            err.usage, err.model, err.kind = got.usage, got.model, got.kind  # type: ignore[attr-defined]
            err.attempts = got.attempts  # type: ignore[attr-defined]
            raise err
        # Not served and not billed (errored / expired / cancelled / missing), or a retry: streamed now.
        return self.sync.analyse(system, user, story_id=story_id)
