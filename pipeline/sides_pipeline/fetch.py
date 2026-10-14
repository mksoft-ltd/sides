"""The one place the pipeline touches the network. Tests inject a fake fetcher instead."""

from __future__ import annotations

from typing import Callable

import httpx

from . import __version__

Fetcher = Callable[[str], bytes]

USER_AGENT = (
    f"SidesNewsBot/{__version__} (+https://froggyeye.com/sides; "
    "headline-and-summary aggregator; contact info@froggyeye.com)"
)
DEFAULT_TIMEOUT_S = 10.0


def http_fetch(url: str, timeout: float = DEFAULT_TIMEOUT_S) -> bytes:
    """GET a feed with a descriptive User-Agent and a hard per-request timeout."""
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5",
    }
    with httpx.Client(timeout=timeout, follow_redirects=True, headers=headers) as client:
        resp = client.get(url)
        resp.raise_for_status()
        return resp.content
