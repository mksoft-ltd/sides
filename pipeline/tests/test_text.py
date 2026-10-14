import pytest

from sides_pipeline.text import (
    canonical_url,
    make_snippet,
    normalise_headline,
    normalise_ws,
    strip_html,
    truncate_words,
)


def test_normalise_ws():
    assert normalise_ws("  a \n\t b  ") == "a b"
    assert normalise_ws(None) == ""


def test_strip_html_tags_entities_and_double_encoding():
    assert strip_html("<p>Leaders met in <a href='x'>Geneva</a>.</p><p>Talks &amp; more</p>") == "Leaders met in Geneva. Talks & more"
    assert strip_html("&lt;p&gt;Twice &amp;amp; encoded&lt;/p&gt;") == "Twice & encoded"
    assert strip_html("Plain &ldquo;quoted&rdquo; &#8212; text") == "Plain “quoted” — text"
    assert strip_html("<script>alert(1)</script>Visible<style>p{}</style>") == "Visible"
    assert strip_html(None) == ""


@pytest.mark.parametrize("limit", [200, 50, 20])
def test_truncate_words_respects_limit_and_word_boundary(limit):
    text = "The quick brown fox jumps over the lazy dog " * 10
    out = truncate_words(text, limit)
    assert len(out) <= limit
    assert out.endswith("…")
    body = out[:-1]
    assert not body.endswith(" ")
    assert text.startswith(body)  # cut only at a word boundary, never mid-word
    assert body.split()[-1] in text.split()


def test_truncate_words_leaves_short_text_alone():
    assert truncate_words("Short.", 200) == "Short."
    assert truncate_words("x" * 200, 200) == "x" * 200


def test_make_snippet_drops_headline_echo():
    assert make_snippet("Same headline", "Same headline") == ""
    assert make_snippet("<b>Same headline</b>  ", "same HEADLINE") == ""
    assert make_snippet("<p>Different</p>", "Headline") == "Different"


@pytest.mark.parametrize(
    "raw, expected",
    [
        ("https://Example.com/a/b?utm_source=rss&utm_medium=feed#frag", "https://example.com/a/b"),
        ("https://example.com/a?id=42&fbclid=abc&utm_campaign=x", "https://example.com/a?id=42"),
        ("https://example.com/a?b=2&a=1", "https://example.com/a?b=2&a=1"),
        ("HTTP://EXAMPLE.com", "http://example.com/"),
        ("https://example.com/story?CMP=share_btn_url", "https://example.com/story"),
        ("  https://example.com/x?ref=rss&ns_mchannel=rss  ", "https://example.com/x"),
        ("https://www.aljazeera.com/sports/2026/10/14/story?traffic_source=rss", "https://www.aljazeera.com/sports/2026/10/14/story"),
    ],
)
def test_canonical_url(raw, expected):
    assert canonical_url(raw) == expected


def test_normalise_headline():
    assert normalise_headline("Fresh story & the HTML description!") == normalise_headline("fresh STORY  the html description")
