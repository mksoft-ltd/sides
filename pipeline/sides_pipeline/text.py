"""Pure text helpers: whitespace, HTML stripping, snippet truncation, URL canonicalisation."""

from __future__ import annotations

import html
import re
from html.parser import HTMLParser
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from .models import SNIPPET_MAX_CHARS

_WS = re.compile(r"\s+")
_ELLIPSIS = "…"

# Query parameters that only track the reader; removed when canonicalising URLs.
_TRACKING_PARAMS = {
    "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid",
    "ref", "ref_src", "ref_url", "source", "src", "cmpid", "cmp", "ocid", "ns_mchannel",
    "ns_source", "ns_campaign", "ns_linkname", "ns_fee", "at_medium", "at_campaign",
    "at_custom1", "at_custom2", "at_custom3", "at_custom4", "ito", "ICID", "icid",
    "CMP", "guccounter", "guce_referrer", "guce_referrer_sig", "__twitter_impression",
    "sh", "smid", "smtyp", "partner", "ftag", "intcmp", "xtor", "traffic_source", "taid",
}
_TRACKING_PREFIXES = ("utm_", "pk_", "piwik_", "mtm_", "hsa_", "vero_", "_hs", "oly_")


def normalise_ws(s: str | None) -> str:
    """Collapse all runs of whitespace to one space and trim."""
    if not s:
        return ""
    return _WS.sub(" ", s).strip()


class _TextExtractor(HTMLParser):
    _BLOCK_TAGS = {"p", "br", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "blockquote"}
    _SKIP_TAGS = {"script", "style"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag: str, attrs) -> None:  # noqa: ANN001
        if tag in self._SKIP_TAGS:
            self._skip += 1
        elif tag in self._BLOCK_TAGS:
            self.parts.append(" ")

    def handle_endtag(self, tag: str) -> None:
        if tag in self._SKIP_TAGS and self._skip:
            self._skip -= 1
        elif tag in self._BLOCK_TAGS:
            self.parts.append(" ")

    def handle_data(self, data: str) -> None:
        if not self._skip:
            self.parts.append(data)


def strip_html(s: str | None) -> str:
    """Remove tags, decode entities (twice-encoded feeds included), normalise whitespace."""
    if not s:
        return ""
    text = html.unescape(s) if "<" not in s else s
    parser = _TextExtractor()
    try:
        parser.feed(text)
        parser.close()
    except Exception:  # pragma: no cover - HTMLParser is lenient; belt and braces
        text = re.sub(r"<[^>]+>", " ", text)
        return normalise_ws(html.unescape(text))
    return normalise_ws(html.unescape("".join(parser.parts)))


def truncate_words(s: str, limit: int = SNIPPET_MAX_CHARS) -> str:
    """Cut at a word boundary so that len(result) <= limit, appending an ellipsis when cut."""
    s = normalise_ws(s)
    if len(s) <= limit:
        return s
    budget = limit - len(_ELLIPSIS)
    cut = s[:budget]
    # Back off to the last whole word, unless that would leave nothing.
    space = cut.rfind(" ")
    if space > 0:
        cut = cut[:space]
    return cut.rstrip(" ,;:.-—–") + _ELLIPSIS


def make_snippet(raw_html: str | None, headline: str = "", limit: int = SNIPPET_MAX_CHARS) -> str:
    """Feed summary → plain-text snippet (≤ limit chars). Drops a snippet that merely repeats the headline."""
    text = strip_html(raw_html)
    if headline and normalise_ws(text).casefold() == normalise_ws(headline).casefold():
        return ""
    return truncate_words(text, limit)


def _is_tracking(key: str) -> bool:
    return key in _TRACKING_PARAMS or key.lower().startswith(_TRACKING_PREFIXES)


def canonical_url(url: str) -> str:
    """Lower-case scheme/host, drop fragment and tracking params, strip empty query."""
    url = url.strip()
    parts = urlsplit(url)
    scheme = (parts.scheme or "https").lower()
    netloc = parts.netloc.lower()
    if not netloc:
        return url
    kept = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True) if not _is_tracking(k)]
    query = urlencode(kept, doseq=True)
    path = parts.path or "/"
    return urlunsplit((scheme, netloc, path, query, ""))


_PUNCT = re.compile(r"[^\w\s]", re.UNICODE)


def normalise_headline(s: str) -> str:
    """Key used to spot the same headline twice within one outlet."""
    return normalise_ws(_PUNCT.sub("", s.casefold()))
