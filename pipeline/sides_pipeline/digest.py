"""Phase 3, assembly: stories.json + validated per-story analysis → the published digest.json.

A story whose analysis failed is kept with empty analysis arrays and a ``meta.warnings`` entry, so the digest
still ships. ``meta.cost_usd`` is the whole run (grouping + analysis) and ``meta.validation`` totals the
citation validator over every story.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime

from .analyse import StoryAnalysis
from .cost import RunCost
from .models import Digest, Story, ValidationCounts
from .validate import empty_analysis, validate_analysis

log = logging.getLogger(__name__)


@dataclass
class DigestOutcome:
    digest: Digest
    per_story: dict[str, ValidationCounts] = field(default_factory=dict)
    failed: list[str] = field(default_factory=list)  # story ids whose analysis failed


def assemble_digest(
    stories_digest: Digest,
    analyses: list[StoryAnalysis],
    cost: RunCost,
    *,
    model: str,
    now: datetime | None = None,
) -> DigestOutcome:
    """Attach validated analysis to every story of ``stories_digest`` and refresh ``meta``."""
    now = now or datetime.now(tz=UTC)
    outlets = {o.id: o for o in stories_digest.outlets}
    by_id = {a.story_id: a for a in analyses}
    totals = ValidationCounts()
    out = DigestOutcome(digest=stories_digest)  # replaced below
    warnings = list(stories_digest.meta.warnings)
    stories: list[Story] = []
    for story in stories_digest.stories:
        a = by_id.get(story.id)
        if a is None or not a.ok:
            reason = a.error if a is not None else "no analysis result"
            stories.append(empty_analysis(story))
            out.failed.append(story.id)
            msg = f"story {story.rank} ({story.id}) has no analysis: {reason}"
            warnings.append(msg)
            log.warning(msg)
            continue
        analysed, counts = validate_analysis(a.response, story, outlets)
        stories.append(analysed)
        out.per_story[story.id] = counts
        totals.add(counts)

    for w in cost.warnings:  # e.g. a fallback model with no price row (recorded unpriced, never fatal)
        if w not in warnings:
            warnings.append(w)
    meta = stories_digest.meta.model_copy(update=dict(
        model=model,
        cost_usd=cost.total_usd,
        warnings=warnings,
        validation=totals,
    ))
    out.digest = stories_digest.model_copy(update=dict(generated_at=now, meta=meta, stories=stories))
    return out
