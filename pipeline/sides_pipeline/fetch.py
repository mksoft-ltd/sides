"""The one place the pipeline touches the network. Tests inject a fake fetcher instead.

Some outlets throttle or block cloud IP ranges (GitHub Actions saw The Independent answer 429 and Times of
Israel 403 on both full runs of 14-15 Oct 2026, while both worked from a residential IP). So:

* the User-Agent is browser-shaped but still names us in its comment, and ``Accept`` asks for feeds;
* :func:`fetch_with_retry` retries 403/429/5xx and transport errors up to ``RETRIES`` times with exponential
  backoff plus jitter, honouring ``Retry-After`` (seconds or an HTTP date, capped at ``MAX_DELAY_S``);
* the collector then tries an outlet's ``feed_url_alternates`` in order (see collect.py).
"""

from __future__ import annotations

import random
import time
from collections.abc import Callable
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime

import httpx

from . import __version__

Fetcher = Callable[[str], bytes]

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/141.0.0.0 Safari/537.36 "
    f"(compatible; SidesNewsBot/{__version__}; +https://froggyeye.com/sides; "
    "headline-and-summary aggregator; contact info@froggyeye.com)"
)
ACCEPT = "application/rss+xml, application/xml;q=0.9, */*;q=0.8"
DEFAULT_TIMEOUT_S = 10.0

RETRIES = 3  # after the first attempt, so at most 4 requests per URL
BACKOFF_BASE_S = 1.0
MAX_DELAY_S = 30.0
RETRY_STATUSES = frozenset({403, 429})  # plus every 5xx


class FetchHTTPError(Exception):
    """A non-2xx answer. ``retry_after`` is the parsed ``Retry-After`` delay in seconds, when the server sent one."""

    def __init__(self, url: str, status: int, retry_after: float | None = None):
        super().__init__(f"HTTP {status} for {url}")
        self.url = url
        self.status = status
        self.retry_after = retry_after


def parse_retry_after(value: str | None, *, now: datetime | None = None) -> float | None:
    """``Retry-After`` as seconds: an integer, or an HTTP date relative to ``now``. None when absent/unparsable."""
    if not value:
        return None
    value = value.strip()
    if value.isdigit():
        return float(value)
    try:
        when = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=UTC)
    return max(0.0, (when - (now or datetime.now(tz=UTC))).total_seconds())


def http_fetch(url: str, timeout: float = DEFAULT_TIMEOUT_S) -> bytes:
    """One GET of a feed; a non-2xx answer raises FetchHTTPError carrying any Retry-After."""
    headers = {"User-Agent": USER_AGENT, "Accept": ACCEPT}
    with httpx.Client(timeout=timeout, follow_redirects=True, headers=headers) as client:
        resp = client.get(url)
        if resp.status_code >= 400:
            raise FetchHTTPError(url, resp.status_code, parse_retry_after(resp.headers.get("retry-after")))
        return resp.content


def is_retryable(exc: BaseException) -> bool:
    if isinstance(exc, FetchHTTPError):
        return exc.status in RETRY_STATUSES or exc.status >= 500
    return isinstance(exc, httpx.TransportError)


def backoff_delay(attempt: int, retry_after: float | None, *, rand: Callable[[], float] = random.random) -> float:
    """Delay before retry number ``attempt`` (0-based): base·2^attempt plus up to one base of jitter, never less
    than the server's Retry-After, never more than MAX_DELAY_S."""
    delay = BACKOFF_BASE_S * (2**attempt) + BACKOFF_BASE_S * rand()
    if retry_after is not None:
        delay = max(delay, retry_after)
    return min(delay, MAX_DELAY_S)


def fetch_with_retry(
    fetcher: Fetcher,
    url: str,
    *,
    retries: int = RETRIES,
    sleep: Callable[[float], None] = time.sleep,
    rand: Callable[[], float] = random.random,
) -> bytes:
    """``fetcher(url)``, retried on 403/429/5xx/transport errors; the last error is re-raised."""
    for attempt in range(retries + 1):
        try:
            return fetcher(url)
        except Exception as exc:  # noqa: BLE001 - classified below; anything else propagates unchanged
            if attempt >= retries or not is_retryable(exc):
                raise
            sleep(backoff_delay(attempt, getattr(exc, "retry_after", None), rand=rand))
    raise AssertionError("unreachable")  # pragma: no cover
