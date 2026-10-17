"""Feed thumbnails: one https link per item, chosen from media:thumbnail / media:content / image enclosures;
nothing downloaded. Real recorded feeds plus synthetic edge cases. No network."""

import feedparser

from conftest import FakeFetcher, make_outlet, read_fixture
from sides_pipeline.collect import collect, entry_image


def _first_entry(name: str):
    return feedparser.parse(read_fixture(name)).entries[0]


def test_bbc_thumbnail_is_used():
    url = entry_image(_first_entry("real_bbc_world.xml"))
    assert url and url.startswith("https://ichef.bbci.co.uk/")


def test_guardian_picks_the_smallest_width_at_or_above_the_target():
    e = _first_entry("real_guardian_world.xml")
    widths = {c["url"]: int(c["width"]) for c in e.media_content if c.get("width")}
    url = entry_image(e)
    assert url in widths and widths[url] >= 460
    assert all(w < 460 or w >= widths[url] for w in widths.values())


def test_image_enclosure_is_used():
    url = entry_image(_first_entry("real_toi_world.xml"))
    assert url and url.startswith("https://static.toiimg.com/")


def test_feed_without_images_gives_none():
    assert entry_image(_first_entry("real_aljazeera_all.xml")) is None


def test_untrusted_links_are_refused_and_http_is_upgraded():
    assert entry_image({"media_thumbnail": [{"url": "javascript:alert(1)"}]}) is None
    assert entry_image({"media_thumbnail": [{"url": "https://user:pw@img.example/a.jpg"}]}) is None
    assert entry_image({"media_thumbnail": [{"url": "https://img.example/" + "a" * 2000}]}) is None
    assert entry_image({"media_thumbnail": [{"url": "http://img.example/a.jpg"}]}) == "https://img.example/a.jpg"
    assert entry_image({"enclosures": [{"href": "https://x.example/a.mp3", "type": "audio/mpeg"}]}) is None
    assert entry_image({"media_content": [{"url": "https://x.example/v.mp4", "medium": "video"}]}) is None


def test_largest_is_used_when_all_are_below_the_target():
    e = {"media_content": [{"url": "https://i.example/140.jpg", "width": "140"}, {"url": "https://i.example/300.jpg", "width": "300"}]}
    assert entry_image(e) == "https://i.example/300.jpg"


def test_collected_articles_carry_the_image_link(now):
    outlets = [make_outlet("bbc", feed_url="https://bbc.example/rss", home_url="https://www.bbc.co.uk/", link_hosts=["bbc.com", "bbc.co.uk"])]
    result = collect(outlets, fetcher=FakeFetcher({"https://bbc.example/rss": read_fixture("real_bbc_world.xml")}), now=now)
    assert result.articles and all(a.image_url and a.image_url.startswith("https://") for a in result.articles)
