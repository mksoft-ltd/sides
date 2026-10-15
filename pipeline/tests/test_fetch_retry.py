"""Feeds that throttle or block cloud IPs (The Independent 429, Times of Israel 403 on GitHub Actions, Oct 2026):
retries with backoff + jitter honouring Retry-After, then per-outlet alternates in order. No network."""

from datetime import UTC, datetime

import httpx
import pytest

from conftest import FakeFetcher, make_outlet, read_fixture
from sides_pipeline.collect import collect
from sides_pipeline.config import load_outlets
from sides_pipeline.fetch import (
    ACCEPT,
    MAX_DELAY_S,
    RETRIES,
    USER_AGENT,
    FetchHTTPError,
    backoff_delay,
    fetch_with_retry,
    parse_retry_after,
)

URL = "https://feed.example/rss"
GOOD = read_fixture("real_guardian_world.xml")


class Sleeps(list):
    def __call__(self, s: float) -> None:
        self.append(s)


def test_429_429_200_succeeds_on_the_third_attempt_with_growing_backoff():
    f = FakeFetcher({URL: [FetchHTTPError(URL, 429), FetchHTTPError(URL, 429), GOOD]})
    sleeps = Sleeps()
    assert fetch_with_retry(f, URL, sleep=sleeps, rand=lambda: 0.5) == GOOD
    assert f.calls == [URL] * 3
    assert sleeps == [1.5, 2.5]  # base·2^n + jitter(0.5·base)


def test_retry_after_is_honoured_and_capped():
    f = FakeFetcher({URL: [FetchHTTPError(URL, 429, retry_after=7.0), FetchHTTPError(URL, 503, retry_after=999), GOOD]})
    sleeps = Sleeps()
    fetch_with_retry(f, URL, sleep=sleeps, rand=lambda: 0.0)
    assert sleeps == [7.0, MAX_DELAY_S]


def test_parse_retry_after_seconds_and_http_date():
    now = datetime(2026, 10, 15, 6, 0, tzinfo=UTC)
    assert parse_retry_after("12") == 12.0
    assert parse_retry_after("Thu, 15 Oct 2026 06:00:20 GMT", now=now) == 20.0
    assert parse_retry_after("soon") is None and parse_retry_after(None) is None


@pytest.mark.parametrize("exc", [FetchHTTPError(URL, 403), FetchHTTPError(URL, 500), httpx.ConnectError("reset")])
def test_retryable_errors_retry_then_reraise_after_the_last_attempt(exc):
    f = FakeFetcher({URL: exc})
    sleeps = Sleeps()
    with pytest.raises(type(exc)):
        fetch_with_retry(f, URL, sleep=sleeps, rand=lambda: 0.0)
    assert len(f.calls) == RETRIES + 1 and len(sleeps) == RETRIES


@pytest.mark.parametrize("exc", [FetchHTTPError(URL, 404), FetchHTTPError(URL, 410), ValueError("bad")])
def test_non_retryable_errors_fail_at_once(exc):
    f = FakeFetcher({URL: exc})
    sleeps = Sleeps()
    with pytest.raises(type(exc)):
        fetch_with_retry(f, URL, sleep=sleeps)
    assert f.calls == [URL] and sleeps == []


def test_backoff_never_exceeds_the_cap():
    assert backoff_delay(10, None, rand=lambda: 1.0) == MAX_DELAY_S


def test_user_agent_is_browser_shaped_but_names_us_and_accept_asks_for_feeds():
    assert USER_AGENT.startswith("Mozilla/5.0 ") and "SidesNewsBot/" in USER_AGENT and "+https://froggyeye.com/sides" in USER_AGENT
    assert ACCEPT == "application/rss+xml, application/xml;q=0.9, */*;q=0.8"


def _outlet(**kw):
    return make_outlet("indy", feed_url="https://indy.example/world/rss", **kw)


def test_alternates_are_tried_in_order_and_the_first_success_wins(now):
    o = _outlet(feed_url_alternates=["https://indy.example/rss", "https://indy.example/uk/rss"])
    f = FakeFetcher({
        "https://indy.example/world/rss": FetchHTTPError("w", 429),
        "https://indy.example/rss": GOOD,
        "https://indy.example/uk/rss": GOOD,
    })
    res = collect([o], fetcher=f, now=now, sleep=Sleeps())
    assert res.feed_errors == [] and res.per_outlet_counts["indy"] > 0
    assert f.calls == ["https://indy.example/world/rss"] * (RETRIES + 1) + ["https://indy.example/rss"]


def test_an_unparsable_primary_also_falls_through_to_the_alternate(now):
    o = _outlet(feed_url_alternates=["https://indy.example/rss"])
    f = FakeFetcher({"https://indy.example/world/rss": read_fixture("synthetic_malformed.xml"), "https://indy.example/rss": GOOD})
    res = collect([o], fetcher=f, now=now, sleep=Sleeps())
    assert res.feed_errors == [] and res.per_outlet_counts["indy"] > 0


def test_when_every_url_fails_the_outlet_lands_in_feed_errors_and_the_run_continues(now):
    o = _outlet(feed_url_alternates=["https://indy.example/rss"])
    ok = make_outlet("guardian", feed_url="https://g.example/rss")
    f = FakeFetcher({
        "https://indy.example/world/rss": FetchHTTPError("https://indy.example/world/rss", 429),
        "https://indy.example/rss": FetchHTTPError("https://indy.example/rss", 403),
        "https://g.example/rss": GOOD,
    })
    res = collect([o, ok], fetcher=f, now=now, sleep=Sleeps())
    err = {e.outlet_id: e.error for e in res.feed_errors}
    assert set(err) == {"indy"}
    assert "https://indy.example/world/rss: FetchHTTPError: HTTP 429" in err["indy"]
    assert "https://indy.example/rss: FetchHTTPError: HTTP 403" in err["indy"]
    assert res.per_outlet_counts["indy"] == 0 and res.per_outlet_counts["guardian"] > 0


def test_configured_alternates_exist_for_the_two_blocked_outlets_and_are_https():
    by_id = {o.id: o for o in load_outlets()}
    assert [str(u) for u in by_id["independent"].feed_url_alternates][:1] == ["https://www.independent.co.uk/rss"]
    assert "https://feeds.feedburner.com/TheTimesOfIsrael" in [str(u) for u in by_id["timesofisrael"].feed_url_alternates]
    with pytest.raises(ValueError, match="must be https"):
        make_outlet("xx", feed_url_alternates=["http://x.example/rss"])
