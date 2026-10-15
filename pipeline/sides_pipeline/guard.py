"""Prompt-injection guards (security audit SEC-1). Feed text is untrusted data written by third parties.

Three deterministic layers, all pure functions:

1. :func:`suspect_text` flags text that carries a URL, an ``@handle`` or an instruction-shaped phrase
   ("ignore previous instructions", "system prompt", "as an AI", …). The collector drops feed items whose
   headline or snippet is suspect, so they never reach a prompt; the validator drops any model-written point,
   claim, topic or quote that is suspect (reason ``untrusted_text``).
2. :func:`title_grounded` checks a model-written story title against the story's own articles: one cited
   headline must share at least ``MIN_SHARED_WITH_ONE_HEADLINE`` content words with it, and at least
   ``MIN_GROUNDED_SHARE`` of its content words must appear in the story's headlines/snippets. Calibrated on the
   first live run (14 Oct 2026): all 37 model titles pass; the weakest shared 2 words with one headline and
   6 of 8 words with the story.
3. :func:`ground_title` replaces an ungrounded or suspect title with the best-matching member headline.

The patterns are deliberately phrase-level: single words such as "ignore" occur in ordinary news headlines, and so
do "new instructions" (estate agents), "developer mode" and "jailbreak" (tech news) and "as an assistant" (sport), which
is why none of those is a pattern. The collector screens only the text that would reach a prompt (the headline and the
≤200-char snippet), never the feed's full summary. Calibrated against every enabled live feed on 15 Oct 2026.
"""

from __future__ import annotations

import re

from .models import Article

MIN_SHARED_WITH_ONE_HEADLINE = 2
MIN_GROUNDED_SHARE = 2 / 3

_URL = re.compile(
    r"(?:\bhttps?://|\bwww\.|\b[a-z0-9-]{2,}\.(?:com|org|net|io|ai|co|uk|ru|cn|info|xyz|ly|me|tv|news|gov)(?:/|\b))",
    re.IGNORECASE,
)
_HANDLE = re.compile(r"(?<![\w.])@[A-Za-z0-9_]{2,}")
_INSTRUCTION = re.compile(
    r"|".join([
        # "ignore previous instructions", "disregard all prior rules", "forget the above prompt"
        r"\b(?:ignore|disregard|forget|override)\W+(?:(?:all|any|the|your|of|these)\W+){0,3}"
        r"(?:previous|prior|above|earlier|preceding|system)\W+(?:\w+\W+){0,2}?"
        r"(?:instructions?|prompts?|rules|directions|messages|context)\b",
        r"\bsystem\s+prompt\b",
        r"\bdeveloper\s+message\b",
        r"\bas\s+an?\s+(?:ai\s+(?:language\s+)?model|large\s+language\s+model|language\s+model|llm)\b",
        r"\byou\s+are\s+now\s+(?:an?|the|my)\s+\w+",
        r"\byou\s+are\s+(?:an?\s+)?(?:ai\s+model|chatgpt|claude|gpt|llm|language\s+model)\b",
        r"\bsummari[sz]e\s+this\s+(?:as|story\s+as)\b",
        r"\b(?:all|every)\s+(?:outlets|sources)\s+(?:agree|confirm)\b",
        r"</?\s*(?:system|instructions?|articles?|assistant|user)\s*>",
        r"^\s*(?:assistant|system|user)\s*:",
    ]),
    re.IGNORECASE | re.MULTILINE,
)

_STOP = frozenset(
    "the a an and or of to in on for at by with from as is are was were be been its it this that after over amid "
    "into new says say said than more about up out off will can how why what who when where his her their has have "
    "had not but".split()
)
_WORD = re.compile(r"[a-z0-9]+")
_FOLD = str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"', "–": "-", "—": "-"})


def instruction_like(text: str) -> bool:
    """Instruction-shaped phrasing only (the collector's screen: a URL or handle in a headline is ordinary news)."""
    return bool(text) and _INSTRUCTION.search(text) is not None


def suspect_text(text: str) -> str | None:
    """``"url"`` / ``"handle"`` / ``"instruction"`` when model-written ``text`` carries a link or an instruction."""
    if not text:
        return None
    if _URL.search(text):
        return "url"
    if _HANDLE.search(text):
        return "handle"
    if _INSTRUCTION.search(text):
        return "instruction"
    return None


def content_stems(text: str) -> set[str]:
    """Lower-cased content words (≥3 chars, stop words removed), stemmed to their first five letters."""
    words = _WORD.findall((text or "").translate(_FOLD).lower())
    return {w[:5] for w in words if len(w) >= 3 and w not in _STOP}


def title_grounded(title: str, articles: list[Article]) -> bool:
    words = content_stems(title)
    if not words:
        return True  # nothing that could carry a claim (e.g. "S1"); a URL/instruction is caught by suspect_text
    if not articles:
        return False
    best = max(len(words & content_stems(a.headline)) for a in articles)
    if best < min(MIN_SHARED_WITH_ONE_HEADLINE, len(words)):
        return False
    story = set().union(*(content_stems(a.headline) | content_stems(a.snippet) for a in articles))
    return len(words & story) / len(words) >= MIN_GROUNDED_SHARE


def ground_title(title: str, articles: list[Article]) -> tuple[str, str | None]:
    """``(title, None)`` when the title may stand; otherwise ``(member headline, reason)`` where reason is
    ``untrusted_text_title`` (suspect) or ``title_ungrounded``. The replacement is the member headline sharing the most
    content words with the proposed title (ties → earliest listed), skipping suspect headlines."""
    reason = "untrusted_text_title" if suspect_text(title) else (None if title_grounded(title, articles) else "title_ungrounded")
    if reason is None:
        return title, None
    words = content_stems(title)
    clean = [a for a in articles if not suspect_text(a.headline)] or list(articles)
    best = max(clean, key=lambda a: (len(words & content_stems(a.headline)), -clean.index(a)))
    return best.headline, reason
