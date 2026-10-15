"""Shared fixtures. Network is blocked for the whole suite via pyproject addopts (--disable-socket)."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from sides_pipeline.models import Outlet

FIXTURES = Path(__file__).parent / "fixtures" / "feeds"

# The real feeds in fixtures/ were recorded at this instant; tests use it as "now".
RECORDED_AT = datetime(2026, 10, 14, 22, 0, tzinfo=UTC)


def read_fixture(name: str) -> bytes:
    return (FIXTURES / name).read_bytes()


# Synthetic feeds link to *.example.com; the four recorded real feeds link to their outlets' own hosts. The
# collector drops items linking anywhere else (SEC-4), so test outlets allow both unless a test overrides it.
TEST_LINK_HOSTS = ["example.com", "theguardian.com", "bbc.co.uk", "bbc.com", "aljazeera.com", "indiatimes.com"]


def make_outlet(id: str = "guardian", **overrides) -> Outlet:
    base = dict(
        link_hosts=list(TEST_LINK_HOSTS),
        id=id,
        name=id.title(),
        feed_url=f"https://{id}.example.com/rss",
        home_url=f"https://{id}.example.com/",
        lean="left",
        region="uk",
        bloc="west",
        ownership="independent",
        country="United Kingdom",
        rating_basis="test",
    )
    base.update(overrides)
    return Outlet(**base)


class FakeFetcher:
    """Dependency-injected replacement for http_fetch: url → fixture bytes or raised exception."""

    def __init__(self, mapping: dict[str, bytes | Exception | list]):
        """A list value is a sequence of answers for successive calls (the last one repeats)."""
        self.mapping = {k: (list(v) if isinstance(v, list) else v) for k, v in mapping.items()}
        self.calls: list[str] = []

    def __call__(self, url: str) -> bytes:
        self.calls.append(url)
        result = self.mapping[url]
        if isinstance(result, list):
            result = result.pop(0) if len(result) > 1 else result[0]
        if isinstance(result, Exception):
            raise result
        return result


@pytest.fixture
def now() -> datetime:
    return RECORDED_AT


# ── Phase 2 helpers ───────────────────────────────────────────────────────────

from datetime import timedelta  # noqa: E402

from sides_pipeline.models import Article, OutletPublic  # noqa: E402

LLM_FIXTURES = Path(__file__).parent / "fixtures" / "llm"


def make_public(id: str, lean: str | None = "left", bloc: str = "west", **overrides) -> OutletPublic:
    base = dict(
        id=id,
        name=id.title(),
        lean=lean,
        region="uk" if bloc == "west" else "asia",
        bloc=bloc,
        ownership="independent",
        country="Testland",
        home_url=f"https://{id}.example.com/",
        rating_basis="test",
    )
    base.update(overrides)
    return OutletPublic(**base)


def make_article(aid: str, outlet_id: str, *, minutes: int = 0, headline: str | None = None) -> Article:
    """aid is any short string; it is padded to the 12-hex id format."""
    hexid = aid.encode().hex().ljust(12, "0")[:12]
    return Article(
        id=hexid,
        outlet_id=outlet_id,
        headline=headline or f"Headline {aid} from {outlet_id}",
        snippet=f"Snippet for {aid}",
        url=f"https://{outlet_id}.example.com/{aid}",
        published_at=RECORDED_AT - timedelta(hours=6) + timedelta(minutes=minutes),
    )


def aid(short: str) -> str:
    """The 12-hex id make_article() gives a short id."""
    return short.encode().hex().ljust(12, "0")[:12]
