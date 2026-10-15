from datetime import UTC, datetime, timedelta

import pytest

from conftest import FakeFetcher, make_outlet, read_fixture
from sides_pipeline.collect import FeedParseError, article_id, collect, parse_feed
from sides_pipeline.models import SNIPPET_MAX_CHARS, CollectResult


def test_parse_real_rss_guardian(now):
    o = make_outlet("guardian")
    arts = parse_feed(o, read_fixture("real_guardian_world.xml"), now)
    assert 1 <= len(arts) <= 10
    for a in arts:
        assert a.outlet_id == "guardian"
        assert "<" not in a.snippet and "&amp;" not in a.snippet
        assert len(a.snippet) <= SNIPPET_MAX_CHARS
        assert str(a.url).startswith("https://www.theguardian.com/")
        assert a.published_at.tzinfo is not None
        assert not a.published_at_estimated
    assert arts == sorted(arts, key=lambda a: a.published_at, reverse=True)


@pytest.mark.parametrize("name", ["real_bbc_world.xml", "real_aljazeera_all.xml", "real_toi_world.xml"])
def test_parse_other_real_feeds(name, now):
    arts = parse_feed(make_outlet("xx"), read_fixture(name), now)
    assert len(arts) >= 1
    assert all(len(a.snippet) <= SNIPPET_MAX_CHARS for a in arts)
    assert all(a.id == article_id("xx", str(a.url)) for a in arts)


def test_toi_offsets_are_converted_to_utc(now):
    arts = parse_feed(make_outlet("toi"), read_fixture("real_toi_world.xml"), now)
    # Feed uses +05:30 offsets; every parsed time must be UTC-aware and not in the future.
    assert all(a.published_at.utcoffset() == timedelta(0) for a in arts)
    assert all(a.published_at <= now + timedelta(hours=1) for a in arts)


def test_parse_atom_feed(now):
    arts = parse_feed(make_outlet("atom"), read_fixture("synthetic_atom.xml"), now)
    by_head = {a.headline: a for a in arts}
    assert "Atom entry one" in by_head  # whitespace normalised
    one = by_head["Atom entry one"]
    assert str(one.url) == "https://atom.example.com/stories/one"  # utm + fragment stripped
    assert one.snippet == "First Atom story & summary."
    assert one.published_at == datetime(2026, 10, 14, 19, 30, tzinfo=UTC)
    two = by_head["Atom entry two with content only"]
    assert two.snippet == "Content block used when no summary exists."
    assert two.published_at == datetime(2026, 10, 14, 8, 0, tzinfo=UTC)  # +02:00 → UTC
    three = by_head["Atom entry with no date at all"]
    assert three.published_at == now and three.published_at_estimated is True


def test_rss_edge_cases(now):
    arts = parse_feed(make_outlet("rss"), read_fixture("synthetic_rss_edge_cases.xml"), now)
    heads = [a.headline for a in arts]
    assert heads.count("Fresh story & the HTML description") == 1  # (outlet, headline) dedupe
    assert "Exact duplicate URL item" not in heads  # url dedupe after canonicalisation
    assert "Stale item from two days ago" not in heads  # 36h window
    assert "Item on the window edge (35h old)" in heads
    assert "No link item" not in heads
    assert all(h for h in heads)  # empty titles skipped
    by_head = {a.headline: a for a in arts}
    fresh = by_head["Fresh story & the HTML description"]
    assert str(fresh.url) == "https://rss.example.com/news/fresh?id=42"
    assert fresh.snippet == "Leaders met in Geneva on Tuesday. Talks continue “tomorrow” — officials said."
    long = by_head["Very long description that must be truncated at a word boundary"]
    assert len(long.snippet) <= SNIPPET_MAX_CHARS and long.snippet.endswith("…")
    assert long.snippet.startswith("The quick brown fox")
    undated = by_head["Undated item falls back to fetch time"]
    assert undated.published_at_estimated and undated.published_at == now
    assert by_head["Item whose description equals its headline"].snippet == ""


def test_window_is_configurable(now):
    raw = read_fixture("synthetic_rss_edge_cases.xml")
    assert "Item on the window edge (35h old)" in [a.headline for a in parse_feed(make_outlet("rr"), raw, now, window_hours=36)]
    assert "Item on the window edge (35h old)" not in [a.headline for a in parse_feed(make_outlet("rr"), raw, now, window_hours=24)]


def test_per_outlet_cap_keeps_most_recent(now):
    arts = parse_feed(make_outlet("cap"), read_fixture("synthetic_many_items.xml"), now)
    assert len(arts) == 40
    assert arts[0].headline == "Capped story number 00"
    assert arts[-1].headline == "Capped story number 39"
    assert len(parse_feed(make_outlet("cap"), read_fixture("synthetic_many_items.xml"), now, cap=5)) == 5


def test_malformed_feed_raises(now):
    with pytest.raises(FeedParseError):
        parse_feed(make_outlet("bad"), read_fixture("synthetic_malformed.xml"), now)
    with pytest.raises(FeedParseError):
        parse_feed(make_outlet("empty"), b"", now)


def test_article_id_is_short_stable_hash():
    a = article_id("guardian", "https://www.theguardian.com/x")
    assert a == article_id("guardian", "https://www.theguardian.com/x")
    assert a != article_id("bbc", "https://www.theguardian.com/x")
    assert len(a) == 12 and int(a, 16) >= 0


def test_collect_records_errors_without_aborting(now):
    outlets = [
        make_outlet("guardian", feed_url="https://g.example/rss"),
        make_outlet("timeout", feed_url="https://t.example/rss", lean="centre"),
        make_outlet("http500", feed_url="https://h.example/rss", lean="right"),
        make_outlet("garbage", feed_url="https://x.example/rss", lean="right"),
        make_outlet("disabled", feed_url="https://d.example/rss", lean="right", enabled=False, note="off"),
        make_outlet("cgtn", feed_url="https://c.example/rss", lean=None, ownership="state-controlled", bloc="east", region="asia", country="China"),
    ]
    fetcher = FakeFetcher(
        {
            "https://g.example/rss": read_fixture("real_guardian_world.xml"),
            "https://t.example/rss": TimeoutError("timed out after 10s"),
            "https://h.example/rss": RuntimeError("HTTP 500"),
            "https://x.example/rss": read_fixture("synthetic_malformed.xml"),
            "https://c.example/rss": read_fixture("real_aljazeera_all.xml"),
        }
    )
    result = collect(outlets, fetcher=fetcher, now=now)
    assert isinstance(result, CollectResult)
    assert result.collected_at == now
    assert "https://d.example/rss" not in fetcher.calls  # enabled: false honoured
    assert sorted(fetcher.calls) == sorted(["https://g.example/rss", "https://t.example/rss", "https://h.example/rss", "https://x.example/rss", "https://c.example/rss"])
    errs = {e.outlet_id: e.error for e in result.feed_errors}
    assert set(errs) == {"timeout", "http500", "garbage"}
    assert errs["timeout"].startswith("TimeoutError: timed out")
    assert errs["http500"] == "RuntimeError: HTTP 500"
    assert errs["garbage"].startswith("FeedParseError")
    assert result.per_outlet_counts["guardian"] > 0 and result.per_outlet_counts["cgtn"] > 0
    assert result.per_outlet_counts["timeout"] == 0 and result.per_outlet_counts["http500"] == 0
    assert "disabled" not in result.per_outlet_counts
    assert [o.id for o in result.outlets] == ["guardian", "timeout", "http500", "garbage", "cgtn"]
    assert len(result.articles) == sum(result.per_outlet_counts.values())
    assert len({str(a.url) for a in result.articles}) == len(result.articles)


def test_collect_dedupes_same_url_across_outlets(now):
    raw = read_fixture("synthetic_atom.xml")
    outlets = [make_outlet("aa", feed_url="https://a.example/rss"), make_outlet("bb", feed_url="https://b.example/rss")]
    result = collect(outlets, fetcher=FakeFetcher({"https://a.example/rss": raw, "https://b.example/rss": raw}), now=now)
    assert result.per_outlet_counts == {"aa": 3, "bb": 0}
    assert not result.feed_errors


def test_collect_output_round_trips_through_json(now):
    outlets = [make_outlet("guardian", feed_url="https://g.example/rss")]
    result = collect(outlets, fetcher=FakeFetcher({"https://g.example/rss": read_fixture("real_guardian_world.xml")}), now=now)
    dumped = result.model_dump(mode="json")
    assert dumped["collected_at"] == "2026-10-14T22:00:00Z"
    assert set(dumped) == {"collected_at", "outlets", "articles", "feed_errors", "per_outlet_counts", "item_drops"}
    assert CollectResult.model_validate(dumped) == result
    assert set(dumped["outlets"][0]) == {"id", "name", "lean", "region", "bloc", "ownership", "country", "home_url", "rating_basis"}
