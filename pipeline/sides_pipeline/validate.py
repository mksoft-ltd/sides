"""Phase 3, deterministic half: the citation validator. Nothing unsourced survives (integrity rule 2).

Every item the model proposed is checked against the story's own articles and outlet tags. An item is
dropped under the FIRST failing reason below and counted in ``ValidationCounts.dropped_by_reason``:

  unknown_id                 a cited id (sources / asserted_by / disputed_by / article_id) is not in this story
  empty_sources              sources (or asserted_by / disputed_by / a contradiction side) is empty
  quote_not_found            a headline quote is not a literal substring of the cited article's headline or snippet
                             (case-insensitive, whitespace-normalised, straight/curly quotes and dashes folded);
                             a kept quote gets ``field`` = "headline" or "snippet" (headline wins when both match)
  side_without_articles      a framing entry / omission names a lean or bloc that has no article in this story
  source_outside_side        a framing quote or emphasis item cites an article not of that lean / bloc
  omission_cites_omitter     an omission is sourced to an article of the very lean said to omit the point
  contested_same_outlet      asserted_by and disputed_by share an outlet (the two sides must be disjoint outlet sets)
  contradiction_wrong_bloc   west.sources are not all West-bloc articles, or east.sources not all East-bloc
  empty_framing              a framing entry has nothing left after its quotes and emphasis were checked

Texts longer than 200 characters are cut at a word boundary (logged, not a drop).
"""

from __future__ import annotations

import logging
import re

from .analyse import AnalysisResponse, sides_present
from .models import (
    ANALYSIS_TEXT_MAX_CHARS,
    BlocFraming,
    ContestedClaim,
    Contradiction,
    HeadlineQuote,
    LeanFraming,
    Omission,
    OutletPublic,
    Sourced,
    Story,
    ValidationCounts,
)
from .text import normalise_ws, truncate_words

log = logging.getLogger(__name__)

LEANS = ("left", "centre", "right")
BLOCS = ("west", "east")

_FOLD = str.maketrans({"‘": "'", "’": "'", "‚": "'", "“": '"', "”": '"', "„": '"', "–": "-", "—": "-", "‑": "-", " ": " "})
_WS = re.compile(r"\s+")


def fold(s: str) -> str:
    """Comparison form for the quote check: lower-case, typographic quotes/dashes folded, whitespace collapsed."""
    return _WS.sub(" ", (s or "").translate(_FOLD)).strip().lower()


class _Ctx:
    """Everything about one story the rules need, computed once."""

    def __init__(self, story: Story, outlets: dict[str, OutletPublic]):
        self.ids = {a.id for a in story.articles}
        self.outlet_of = {a.id: a.outlet_id for a in story.articles}
        self.lean_of = {a.id: (outlets[a.outlet_id].lean if a.outlet_id in outlets else None) for a in story.articles}
        self.bloc_of = {a.id: (outlets[a.outlet_id].bloc if a.outlet_id in outlets else None) for a in story.articles}
        self.haystack = {a.id: (fold(a.headline), fold(a.snippet)) for a in story.articles}
        leans, blocs = sides_present(story, outlets)
        self.leans_present = set(leans)
        self.blocs_present = set(blocs)
        self.counts = ValidationCounts()
        self.truncated = 0

    # ── bookkeeping ──
    def keep(self) -> None:
        self.counts.kept += 1

    def drop(self, reason: str, what: str) -> None:
        self.counts.dropped_by_reason[reason] = self.counts.dropped_by_reason.get(reason, 0) + 1
        log.debug("validator dropped (%s): %s", reason, what)

    # ── primitive checks (return a reason or None) ──
    def check_ids(self, ids: list[str]) -> str | None:
        if any(i not in self.ids for i in ids):
            return "unknown_id"
        if not ids:
            return "empty_sources"
        return None

    def text(self, s: str) -> str:
        s = normalise_ws(s)
        if len(s) > ANALYSIS_TEXT_MAX_CHARS:
            self.truncated += 1
            s = truncate_words(s, ANALYSIS_TEXT_MAX_CHARS)
        return s or "…"

    def quote_field(self, q: AnalysisResponse.Quote) -> str | None:
        """'headline' / 'snippet' naming where the quote appears verbatim (headline wins), or None when nowhere."""
        head, snip = self.haystack[q.article_id]
        needle = fold(q.quote)
        if not needle:
            return None
        if needle in head:
            return "headline"
        if needle in snip:
            return "snippet"
        return None


def _dedupe(ids: list[str]) -> list[str]:
    return list(dict.fromkeys(ids))


def _sourced(ctx: _Ctx, item: AnalysisResponse.Sourced, *, side_of=None, side=None, label="item") -> Sourced | None:  # noqa: ANN001
    ids = _dedupe(item.sources)
    reason = ctx.check_ids(ids)
    if reason is None and side is not None and any(side_of[i] != side for i in ids):
        reason = "source_outside_side"
    if reason:
        ctx.drop(reason, f"{label} {item.text[:60]!r} {ids}")
        return None
    ctx.keep()
    return Sourced(text=ctx.text(item.text), sources=ids)


def _framing(ctx: _Ctx, entries, *, kind: str) -> list:  # noqa: ANN001
    """Validate framing entries for leans (kind="lean") or blocs (kind="bloc"); merges duplicate sides."""
    present = ctx.leans_present if kind == "lean" else ctx.blocs_present
    side_of = ctx.lean_of if kind == "lean" else ctx.bloc_of
    valid_sides = LEANS if kind == "lean" else BLOCS
    merged: dict[str, tuple[list[HeadlineQuote], list[Sourced]]] = {}
    for e in entries:
        side = getattr(e, kind)
        if side not in valid_sides or side not in present:
            ctx.drop("side_without_articles", f"framing[{kind}={side}]")
            continue
        quotes, emph = merged.setdefault(side, ([], []))
        seen = {(q.article_id, q.quote) for q in quotes}
        for q in e.headline_quotes:
            if (q.article_id, q.quote) in seen:
                continue
            reason = ctx.check_ids([q.article_id])
            if reason is None and side_of[q.article_id] != side:
                reason = "source_outside_side"
            field = ctx.quote_field(q) if reason is None else None
            if reason is None and field is None:
                reason = "quote_not_found"
            if reason:
                ctx.drop(reason, f"quote {q.quote[:60]!r} ({q.article_id})")
                continue
            seen.add((q.article_id, q.quote))
            ctx.keep()
            quotes.append(HeadlineQuote(article_id=q.article_id, quote=normalise_ws(q.quote), field=field))
        for item in e.emphasis:
            s = _sourced(ctx, item, side_of=side_of, side=side, label=f"emphasis[{side}]")
            if s is not None:
                emph.append(s)
    out = []
    for side in valid_sides:
        if side not in merged:
            continue
        quotes, emph = merged[side]
        if not quotes and not emph:
            ctx.drop("empty_framing", f"framing[{kind}={side}]")
            continue
        cls = LeanFraming if kind == "lean" else BlocFraming
        out.append(cls(**{kind: side}, headline_quotes=quotes, emphasis=emph))
    return out


def validate_analysis(response: AnalysisResponse, story: Story, outlets: dict[str, OutletPublic]) -> tuple[Story, ValidationCounts]:
    """Return a copy of ``story`` with the validated analysis attached, plus what was kept/dropped."""
    ctx = _Ctx(story, outlets)

    agreed = [s for s in (_sourced(ctx, i, label="agreed_fact") for i in response.agreed_facts) if s]
    opinion = [s for s in (_sourced(ctx, i, label="opinion") for i in response.opinion) if s]
    framing = _framing(ctx, response.framing, kind="lean")
    framing_by_bloc = _framing(ctx, response.framing_by_bloc, kind="bloc")

    omissions: list[Omission] = []
    for o in response.omissions:
        ids = _dedupe(o.sources)
        reason = ctx.check_ids(ids)
        if reason is None and (o.lean not in LEANS or o.lean not in ctx.leans_present):
            reason = "side_without_articles"
        if reason is None and any(ctx.lean_of[i] == o.lean for i in ids):
            reason = "omission_cites_omitter"
        if reason:
            ctx.drop(reason, f"omission[{o.lean}] {o.text[:60]!r}")
            continue
        ctx.keep()
        omissions.append(Omission(lean=o.lean, text=ctx.text(o.text), sources=ids))

    contested: list[ContestedClaim] = []
    for c in response.contested_claims:
        a_ids, d_ids = _dedupe(c.asserted_by), _dedupe(c.disputed_by)
        reason = ctx.check_ids(a_ids) or ctx.check_ids(d_ids)
        if reason is None:
            a_out = {ctx.outlet_of[i] for i in a_ids}
            d_out = {ctx.outlet_of[i] for i in d_ids}
            if a_out & d_out:
                reason = "contested_same_outlet"
        if reason:
            ctx.drop(reason, f"contested {c.claim[:60]!r}")
            continue
        ctx.keep()
        contested.append(ContestedClaim(claim=ctx.text(c.claim), asserted_by=a_ids, disputed_by=d_ids))

    contradictions: list[Contradiction] = []
    for x in response.east_west_contradictions:
        w_ids, e_ids = _dedupe(x.west.sources), _dedupe(x.east.sources)
        reason = ctx.check_ids(w_ids) or ctx.check_ids(e_ids)
        if reason is None and (any(ctx.bloc_of[i] != "west" for i in w_ids) or any(ctx.bloc_of[i] != "east" for i in e_ids)):
            reason = "contradiction_wrong_bloc"
        if reason:
            ctx.drop(reason, f"contradiction {x.topic[:60]!r}")
            continue
        ctx.keep()
        contradictions.append(Contradiction(
            topic=ctx.text(x.topic),
            west=Sourced(text=ctx.text(x.west.text), sources=w_ids),
            east=Sourced(text=ctx.text(x.east.text), sources=e_ids),
        ))

    counts = ctx.counts
    if ctx.truncated:
        log.warning("story %s: %d analysis text(s) cut to %d chars", story.id, ctx.truncated, ANALYSIS_TEXT_MAX_CHARS)
    analysed = story.model_copy(update=dict(
        agreed_facts=agreed, framing=framing, omissions=omissions, contested_claims=contested, opinion=opinion,
        framing_by_bloc=framing_by_bloc, east_west_contradictions=contradictions, validation=counts,
    ))
    return analysed, counts


def empty_analysis(story: Story) -> Story:
    """The story with every analysis array empty (used when its analysis call failed)."""
    return story.model_copy(update=dict(
        agreed_facts=[], framing=[], omissions=[], contested_claims=[], opinion=[],
        framing_by_bloc=[], east_west_contradictions=[], validation=ValidationCounts(),
    ))
