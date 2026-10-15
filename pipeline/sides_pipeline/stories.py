"""Phase 2, deterministic half: validate the model's grouping and rank the day's stories.

Everything the spec says *code* must enforce lives here, never in the prompt:
* unknown article ids are dropped;
* an article in two stories stays in the one with more distinct outlets (tie → first listed);
* a story needs ≥ ``min_outlets`` **distinct** outlets (several articles from one outlet count once);
* ranking: distinct outlets ↓, distinct leans covered ↓, blocs covered ↓, earliest ``published_at`` ↑;
* coverage and blindspot indicators are computed from outlet tags (integrity rule 3).
"""

from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass, field

from .models import (
    TITLE_MAX_CHARS,
    Article,
    Blindspot,
    BlocCoverage,
    Coverage,
    LeanCoverage,
    OutletPublic,
    Story,
    ValidationCounts,
)
from .guard import ground_title
from .text import normalise_ws, truncate_words

log = logging.getLogger(__name__)

MIN_OUTLETS = 3
TOP_N = 10
MIN_STORIES = 5


@dataclass
class RawStory:
    """What the model returned for one story, before validation."""

    title: str
    article_ids: list[str]


@dataclass
class ValidationReport:
    """Counts the CLI prints so a human can see what the validator threw away and why."""

    stories_in: int = 0
    unknown_ids_dropped: int = 0
    duplicate_memberships_resolved: int = 0
    empty_stories_dropped: int = 0
    below_min_outlets_dropped: int = 0
    beyond_top_n_dropped: int = 0
    titles_replaced: int = 0
    stories_out: int = 0
    warnings: list[str] = field(default_factory=list)

    def lines(self) -> list[str]:
        return [
            f"stories from model: {self.stories_in}",
            f"unknown article ids dropped: {self.unknown_ids_dropped}",
            f"duplicate memberships resolved: {self.duplicate_memberships_resolved}",
            f"stories with no valid articles dropped: {self.empty_stories_dropped}",
            f"stories with < {MIN_OUTLETS} distinct outlets dropped: {self.below_min_outlets_dropped}",
            f"stories beyond top {TOP_N} dropped: {self.beyond_top_n_dropped}",
            f"titles replaced by a member headline (ungrounded or suspect): {self.titles_replaced}",
            f"stories kept: {self.stories_out}",
        ]


def story_id(article_ids: list[str]) -> str:
    """Short stable hash of the sorted article ids: the same set of articles always gets the same id."""
    return hashlib.sha1("\n".join(sorted(article_ids)).encode()).hexdigest()[:12]


def clean_title(title: str, limit: int = TITLE_MAX_CHARS) -> str:
    return truncate_words(normalise_ws(title), limit) or "Untitled story"


def distinct_outlets(articles: list[Article]) -> set[str]:
    return {a.outlet_id for a in articles}


def compute_coverage(articles: list[Article], outlets: dict[str, OutletPublic]) -> Coverage:
    """Distinct outlets per lean and per bloc. lean=null outlets count for bloc but for no lean."""
    lean = {"left": 0, "centre": 0, "right": 0}
    bloc = {"west": 0, "east": 0}
    for oid in distinct_outlets(articles):
        o = outlets.get(oid)
        if o is None:
            continue
        if o.lean is not None:
            lean[o.lean] += 1
        bloc[o.bloc] += 1
    return Coverage(lean=LeanCoverage(**lean), bloc=BlocCoverage(**bloc))


def _sole_nonzero(counts: dict[str, int]) -> str | None:
    covered = [k for k, v in counts.items() if v > 0]
    return covered[0] if len(covered) == 1 else None


def compute_blindspot(coverage: Coverage) -> Blindspot:
    """A blindspot is when exactly one lean (or bloc) carries the story and every other has 0 outlets."""
    return Blindspot(
        lean=_sole_nonzero(coverage.lean.model_dump()),
        bloc=_sole_nonzero(coverage.bloc.model_dump()),
    )


def _rank_key(articles: list[Article], coverage: Coverage):
    leans_covered = sum(1 for v in coverage.lean.model_dump().values() if v > 0)
    blocs_covered = sum(1 for v in coverage.bloc.model_dump().values() if v > 0)
    earliest = min(a.published_at for a in articles)
    # sort() is ascending, so negate the "bigger is better" terms.
    return (-len(distinct_outlets(articles)), -leans_covered, -blocs_covered, earliest)


def build_stories(
    raw: list[RawStory],
    articles: list[Article],
    outlets: list[OutletPublic],
    *,
    min_outlets: int = MIN_OUTLETS,
    top_n: int = TOP_N,
    min_stories: int = MIN_STORIES,
) -> tuple[list[Story], ValidationReport]:
    """Turn the model's raw grouping into ranked, validated Story records plus a report of what was dropped."""
    report = ValidationReport(stories_in=len(raw))
    by_id = {a.id: a for a in articles}
    outlet_map = {o.id: o for o in outlets}

    # 1. Resolve ids; drop unknown ones.
    resolved: list[tuple[str, list[str]]] = []
    for rs in raw:
        ids: list[str] = []
        seen: set[str] = set()
        for aid in rs.article_ids:
            if aid in seen:
                continue  # same id twice inside one story is harmless; keep once
            seen.add(aid)
            if aid in by_id:
                ids.append(aid)
            else:
                report.unknown_ids_dropped += 1
                log.warning("dropping unknown article id %r from story %r", aid, rs.title)
        resolved.append((rs.title, ids))

    # 2. Each article in at most one story: keep it where there are the most distinct outlets (tie → first).
    owner: dict[str, int] = {}
    for idx, (_, ids) in enumerate(resolved):
        strength = len({by_id[a].outlet_id for a in ids})
        for aid in ids:
            if aid not in owner:
                owner[aid] = idx
                continue
            cur = owner[aid]
            cur_strength = len({by_id[a].outlet_id for a in resolved[cur][1]})
            report.duplicate_memberships_resolved += 1
            if strength > cur_strength:
                owner[aid] = idx
    membership: list[list[str]] = [[] for _ in resolved]
    for idx, (_, ids) in enumerate(resolved):
        membership[idx] = [aid for aid in ids if owner[aid] == idx]

    # 3. Distinct-outlet threshold.
    candidates: list[tuple[str, list[Article]]] = []
    for (title, _), ids in zip(resolved, membership, strict=True):
        arts = [by_id[a] for a in ids]
        if not arts:
            report.empty_stories_dropped += 1
            continue
        if len(distinct_outlets(arts)) < min_outlets:
            report.below_min_outlets_dropped += 1
            continue
        candidates.append((title, arts))

    # 4. Rank and cap.
    scored = []
    for title, arts in candidates:
        arts = sorted(arts, key=lambda a: (a.published_at, a.outlet_id, a.id))
        cov = compute_coverage(arts, outlet_map)
        scored.append((_rank_key(arts, cov), title, arts, cov))
    scored.sort(key=lambda t: t[0])
    report.beyond_top_n_dropped = max(0, len(scored) - top_n)
    scored = scored[:top_n]

    stories = []
    for i, (_, title, arts, cov) in enumerate(scored, start=1):
        # SEC-1: the title is model-written free text with no citation; ground it in the story's own headlines.
        title, replaced = ground_title(normalise_ws(title), arts)
        counts = ValidationCounts()
        if replaced:
            report.titles_replaced += 1
            counts.dropped_by_reason[replaced] = 1
            log.warning("story %d title replaced by a member headline (%s)", i, replaced)
        stories.append(Story(
            id=story_id([a.id for a in arts]),
            title=clean_title(title),
            rank=i,
            outlet_count=len(distinct_outlets(arts)),
            coverage=cov,
            blindspot=compute_blindspot(cov),
            articles=arts,
            validation=counts,
        ))
    report.stories_out = len(stories)
    if len(stories) < min_stories:
        msg = f"only {len(stories)} stories qualified (target {min_stories}, need ≥{min_outlets} distinct outlets each)"
        report.warnings.append(msg)
        log.warning(msg)
    return stories, report
