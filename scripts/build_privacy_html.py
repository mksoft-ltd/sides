#!/usr/bin/env python3
"""Render PRIVACY_POLICY.md (repo root) to privacy_policy.html (repo root).

The store privacy-policy URL is https://mksoft-ltd.github.io/sides/privacy_policy.html
(AppConfig.privacyPolicyUrl). The daily workflow's build job copies privacy_policy.html
from the repo root onto GitHub Pages, so this file goes live on the next daily run.
Raw Markdown is served as text/plain, which Apple 5.1.1(i) review has treated as not
being a privacy policy page (house-facts §5). The Markdown stays the source of truth;
this script is the only thing that writes the HTML, so the two cannot drift.

Run from anywhere:  python3 scripts/build_privacy_html.py
Check mode (CI):    python3 scripts/build_privacy_html.py --check   (exit 1 if stale)

Dependency-free. It handles exactly the Markdown the policy uses: h1/h2, paragraphs,
unordered lists (a block may start with a paragraph and continue as a list), and inline
bold/italic/code/links/bare URLs. Hard-wrapped lines inside a paragraph or bullet are
joined, never turned into separate <p> elements.
"""

from __future__ import annotations

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PRIVACY_POLICY.md"
TARGET = ROOT / "privacy_policy.html"

HEAD = """<!DOCTYPE html>
<html lang="en-GB"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
:root{{color-scheme:light dark;--fg:#1d2128;--bg:#fbfaf7;--muted:#5a6270;--link:#3d4f9f;--code:#eceae4}}
@media (prefers-color-scheme:dark){{:root{{--fg:#e6e6e3;--bg:#16181c;--muted:#a3a9b3;--link:#9fb0f5;--code:#2a2d33}}}}
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;max-width:720px;margin:2rem auto;
padding:0 16px;line-height:1.6;color:var(--fg);background:var(--bg)}}
h1{{font-size:1.6rem;line-height:1.3}}h2{{font-size:1.2rem;margin-top:2rem}}a{{color:var(--link);overflow-wrap:anywhere}}
code{{background:var(--code);padding:.1em .3em;border-radius:3px;font-size:.92em}}
ul{{padding-left:1.2rem}}li{{margin:.35rem 0}}
</style>
</head><body>
"""

FOOT = "</body></html>\n"


def _link(m: re.Match[str]) -> str:
    url = m.group(1)
    trail = ""
    while url and url[-1] in ".,;:":
        trail = url[-1] + trail
        url = url[:-1]
    return f'<a href="{url}">{url}</a>{trail}'


def inline(text: str) -> str:
    """Escape first, then apply inline Markdown, so source text can never inject HTML."""
    out = html.escape(text, quote=False)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r'(?<!href=")(?<!">)(https?://[^\s<)]+)', _link, out)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<!\*)\*([^*\n]+?)\*(?!\*)", r"<em>\1</em>", out)
    out = re.sub(r"`([^`\n]+?)`", r"<code>\1</code>", out)
    return out


def render_block(lines: list[str]) -> list[str]:
    parts: list[str] = []
    para: list[str] = []
    items: list[str] = []
    for line in lines:
        if line.startswith("- "):
            items.append(line[2:].strip())
        elif items:
            items[-1] += " " + line.strip()  # hard-wrapped continuation of a bullet
        else:
            para.append(line.strip())  # hard-wrapped continuation of a paragraph
    if para:
        parts.append(f"<p>{inline(' '.join(para))}</p>")
    if items:
        parts.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
    return parts


def render(markdown: str) -> str:
    parts: list[str] = []
    title = "Privacy Policy"
    for block in re.split(r"\n\s*\n", markdown.strip()):
        lines = [ln.rstrip() for ln in block.split("\n") if ln.strip()]
        if not lines:
            continue
        first = lines[0]
        if first.startswith("## "):
            parts.append(f"<h2>{inline(first[3:].strip())}</h2>")
            lines = lines[1:]
        elif first.startswith("# "):
            title = first[2:].strip()
            parts.append(f"<h1>{inline(title)}</h1>")
            lines = lines[1:]
        if lines:
            parts.extend(render_block(lines))
    return HEAD.format(title=html.escape(title)) + "\n".join(parts) + "\n" + FOOT


def main(argv: list[str]) -> int:
    if not SOURCE.exists():
        print(f"missing {SOURCE}", file=sys.stderr)
        return 1
    out = render(SOURCE.read_text(encoding="utf-8"))
    if "--check" in argv:
        current = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
        if current != out:
            print(f"{TARGET.name} is stale: run scripts/build_privacy_html.py", file=sys.stderr)
            return 1
        print(f"{TARGET.name} is up to date")
        return 0
    TARGET.write_text(out, encoding="utf-8")
    print(f"wrote {TARGET.relative_to(ROOT)} from {SOURCE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
