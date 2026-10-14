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


def make_outlet(id: str = "guardian", **overrides) -> Outlet:
    base = dict(
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

    def __init__(self, mapping: dict[str, bytes | Exception]):
        self.mapping = mapping
        self.calls: list[str] = []

    def __call__(self, url: str) -> bytes:
        self.calls.append(url)
        result = self.mapping[url]
        if isinstance(result, Exception):
            raise result
        return result


@pytest.fixture
def now() -> datetime:
    return RECORDED_AT
