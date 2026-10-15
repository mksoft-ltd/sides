"""Phase 1: fetch every enabled outlet feed and turn it into Article records.

Integrity rules enforced here:
* headline + snippet (≤200 chars) only; article bodies are never fetched or stored;
* a failing feed is recorded in ``feed_errors`` and skipped, never aborts the run;
* items older than the window are dropped, each outlet capped at the N most recent;
* an item whose link is not on the outlet's own host (``home_url`` or ``link_hosts``) is dropped
  (``link_off_domain``, SEC-4) and an ``http://`` link is upgraded to ``https://``;
* an item whose headline or snippet reads like an instruction to a model is dropped before it can reach a prompt
  (``instruction_text``, SEC-1). Both are counted per outlet in ``item_drops``.
"""

from __future__ import annotations

import calendar
import hashlib
import logging
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from urllib.parse import urlsplit

import feedparser

from .fetch import Fetcher, http_fetch
from .guard import instruction_like
from .models import Article, CollectResult, FeedError, ItemDrop, Outlet
from .text import canonical_url, make_snippet, normalise_headline, normalise_ws

log = logging.getLogger(__name__)

WINDOW_HOURS = 36
PER_OUTLET_CAP = 40
MAX_WORKERS = 8
_MAX_ERROR_CHARS = 300


class FeedParseError(Exception):
    """The bytes we fetched were not a usable RSS/Atom feed."""


def article_id(outlet_id: str, url: str) -> str:
    return hashlib.sha1(f"{outlet_id}\n{url}".encode()).hexdigest()[:12]


def _entry_datetime(entry) -> datetime | None:  # noqa: ANN001
    for key in ("published_parsed", "updated_parsed", "created_parsed"):
        st = entry.get(key)
        if st:
            try:
                return datetime.fromtimestamp(calendar.timegm(st), tz=UTC)
            except (OverflowError, ValueError):
                continue
    return None


def _entry_summary(entry) -> str:  # noqa: ANN001
    if entry.get("summary"):
        return entry["summary"]
    for c in entry.get("content") or []:
        if c.get("value"):
            return c["value"]
    return ""


def link_on_outlet_host(outlet: Outlet, link: str) -> bool:
    host = (urlsplit(link).hostname or "").lower()
    return any(host == h or host.endswith("." + h) for h in outlet.allowed_link_hosts() if h)


def parse_feed(
    outlet: Outlet,
    raw: bytes,
    now: datetime,
    *,
    window_hours: int = WINDOW_HOURS,
    cap: int = PER_OUTLET_CAP,
    drops: Counter | None = None,
) -> list[Article]:
    """Parse one feed's bytes into deduplicated, windowed, capped Article records (newest first).
    Security drops are counted by reason into ``drops`` when given."""
    drops = drops if drops is not None else Counter()
    parsed = feedparser.parse(raw)
    if not parsed.entries:
        if parsed.bozo:
            raise FeedParseError(f"unparseable feed: {parsed.get('bozo_exception')}")
        raise FeedParseError("feed parsed but contains no items")

    cutoff = now - timedelta(hours=window_hours)
    seen_urls: set[str] = set()
    seen_heads: set[str] = set()
    articles: list[Article] = []

    for entry in parsed.entries:
        headline = normalise_ws(entry.get("title"))
        link = (entry.get("link") or "").strip()
        if not headline or not link.startswith(("http://", "https://")):
            continue
        if not link_on_outlet_host(outlet, link):
            drops["link_off_domain"] += 1
            log.warning("%s: dropped item linking off the outlet's host: %s", outlet.id, link[:120])
            continue
        snippet = make_snippet(_entry_summary(entry), headline)
        # Screen exactly what could reach a prompt: the headline and the stored snippet (not the full summary).
        if instruction_like(headline) or instruction_like(snippet):
            drops["instruction_text"] += 1
            log.warning("%s: dropped item with instruction-like text: %r", outlet.id, headline[:120])
            continue
        if link.startswith("http://"):
            link = "https://" + link[len("http://"):]
        url = canonical_url(link)
        head_key = normalise_headline(headline)
        if url in seen_urls or head_key in seen_heads:
            continue

        published = _entry_datetime(entry)
        estimated = published is None
        if published is None:
            published = now
        elif published < cutoff:
            continue

        seen_urls.add(url)
        seen_heads.add(head_key)
        articles.append(
            Article(
                id=article_id(outlet.id, url),
                outlet_id=outlet.id,
                headline=headline,
                snippet=snippet,
                url=url,
                published_at=published,
                published_at_estimated=estimated,
            )
        )

    articles.sort(key=lambda a: a.published_at, reverse=True)
    return articles[:cap]


def _describe(exc: BaseException) -> str:
    msg = f"{type(exc).__name__}: {exc}" if str(exc) else type(exc).__name__
    return normalise_ws(msg)[:_MAX_ERROR_CHARS]


def collect(
    outlets: list[Outlet],
    *,
    fetcher: Fetcher = http_fetch,
    now: datetime | None = None,
    window_hours: int = WINDOW_HOURS,
    cap: int = PER_OUTLET_CAP,
    max_workers: int = MAX_WORKERS,
) -> CollectResult:
    """Fetch all enabled outlets concurrently and assemble the articles.json payload."""
    now = now or datetime.now(tz=UTC)
    enabled = [o for o in outlets if o.enabled]
    skipped = [o.id for o in outlets if not o.enabled]
    if skipped:
        log.info("skipping disabled outlets: %s", ", ".join(skipped))

    def fetch_one(outlet: Outlet) -> tuple[Outlet, bytes | None, BaseException | None]:
        try:
            return outlet, fetcher(str(outlet.feed_url)), None
        except Exception as exc:  # noqa: BLE001 - any failure is a per-feed error, never fatal
            return outlet, None, exc

    with ThreadPoolExecutor(max_workers=max(1, min(max_workers, len(enabled) or 1))) as pool:
        fetched = list(pool.map(fetch_one, enabled))

    articles: list[Article] = []
    errors: list[FeedError] = []
    counts: dict[str, int] = {}
    item_drops: list[ItemDrop] = []
    seen_urls: set[str] = set()

    for outlet, raw, exc in fetched:
        if exc is not None:
            log.warning("%s: fetch failed: %s", outlet.id, _describe(exc))
            errors.append(FeedError(outlet_id=outlet.id, error=_describe(exc)))
            counts[outlet.id] = 0
            continue
        dropped: Counter = Counter()
        try:
            items = parse_feed(outlet, raw or b"", now, window_hours=window_hours, cap=cap, drops=dropped)
        except Exception as exc:  # noqa: BLE001
            log.warning("%s: parse failed: %s", outlet.id, _describe(exc))
            errors.append(FeedError(outlet_id=outlet.id, error=_describe(exc)))
            counts[outlet.id] = 0
            continue
        kept = []
        for a in items:
            key = str(a.url)
            if key in seen_urls:
                continue
            seen_urls.add(key)
            kept.append(a)
        counts[outlet.id] = len(kept)
        articles.extend(kept)
        item_drops += [ItemDrop(outlet_id=outlet.id, reason=r, count=n) for r, n in sorted(dropped.items())]

    return CollectResult(
        collected_at=now,
        outlets=[o.public() for o in enabled],
        articles=articles,
        feed_errors=errors,
        per_outlet_counts=counts,
        item_drops=item_drops,
    )
