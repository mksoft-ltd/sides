"""Phase 6, publish: copy a finished run into the GitHub Pages site directory (the ``gh-pages`` checkout).

Site layout (served at https://mksoft-ltd.github.io/sides/):

    digest/latest.json        byte-identical copy of digest/<date>.json for the newest date
    digest/<date>.json        one file per day, never rewritten by a later day
    digest/index.json         newest-first list of {date, generated_at, stories, cost_usd} for every digest on the site
    runs/<date>.json          the day's cost report (every paid call, token counts, USD)
    privacy_policy.html       copied from the repo root when it exists (house-facts §5); absent otherwise
    index.html, .nojekyll     a one-paragraph landing page; .nojekyll stops Pages running Jekyll over the JSON

Nothing here touches the network. ``publish()`` is a pure file operation so the tests run on tmp dirs.
"""

from __future__ import annotations

import json
import logging
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path

from .cost import RunCost
from .models import Digest

log = logging.getLogger(__name__)

SITE_URL = "https://mksoft-ltd.github.io/sides/"
_DATE_FILE = re.compile(r"^(\d{4}-\d{2}-\d{2})\.json$")

INDEX_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sides digest feed</title>
<style>body{font-family:system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1rem;line-height:1.5;color:#222}code{background:#f3f3f3;padding:.1rem .3rem;border-radius:3px}</style>
</head>
<body>
<h1>Sides: The News, Every Angle</h1>
<p>This site hosts the daily news digest read by the Sides app: how outlets across the political spectrum and the
West/East divide frame the same stories, every point traced to a source headline. Only headlines and short feed
summaries are ever stored.</p>
<ul>
<li><a href="digest/latest.json">digest/latest.json</a> — today's digest</li>
<li><a href="digest/index.json">digest/index.json</a> — every available date with story count and run cost</li>
<li><code>digest/YYYY-MM-DD.json</code> and <code>runs/YYYY-MM-DD.json</code> — one digest and one cost report per day</li>
</ul>
<p>Published by Froggy Eye Ltd. Source: <a href="https://github.com/mksoft-ltd/sides">github.com/mksoft-ltd/sides</a>.</p>
</body>
</html>
"""


@dataclass
class IndexEntry:
    date: str
    generated_at: str
    stories: int
    cost_usd: float

    @classmethod
    def from_digest_bytes(cls, raw: bytes) -> "IndexEntry":
        d = json.loads(raw)
        return cls(date=d["date"], generated_at=d["generated_at"], stories=len(d.get("stories", [])), cost_usd=float(d["meta"]["cost_usd"]))

    def to_dict(self) -> dict:
        return {"date": self.date, "generated_at": self.generated_at, "stories": self.stories, "cost_usd": self.cost_usd}


@dataclass
class PublishResult:
    date: str
    site_dir: Path
    written: list[Path] = field(default_factory=list)
    index: list[IndexEntry] = field(default_factory=list)
    privacy_copied: bool = False
    run_report_copied: bool = False


def load_index(path: Path) -> dict[str, IndexEntry]:
    """Existing digest/index.json → {date: entry}; a missing or unreadable file is an empty index."""
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text())
        return {e["date"]: IndexEntry(e["date"], e["generated_at"], int(e["stories"]), float(e["cost_usd"])) for e in data}
    except (ValueError, KeyError, TypeError) as exc:
        log.warning("ignoring unreadable %s: %s", path, exc)
        return {}


def build_index(digest_dir: Path, existing: dict[str, IndexEntry]) -> list[IndexEntry]:
    """Every dated digest file on the site wins over the old index entry for its date; newest first."""
    merged = dict(existing)
    for f in digest_dir.glob("*.json"):
        m = _DATE_FILE.match(f.name)
        if not m:
            continue
        try:
            merged[m.group(1)] = IndexEntry.from_digest_bytes(f.read_bytes())
        except (ValueError, KeyError, TypeError) as exc:
            log.warning("skipping %s in index: %s", f, exc)
    return [merged[d] for d in sorted(merged, reverse=True)]


def publish(
    digest_path: Path,
    runs_dir: Path,
    site_dir: Path,
    *,
    privacy_html: Path | None = None,
) -> PublishResult:
    """Write ``digest_path`` and its cost report into ``site_dir`` and refresh the index and landing page."""
    raw = Path(digest_path).read_bytes()
    digest = Digest.model_validate_json(raw)  # fail loudly on a broken digest before anything is written
    date = digest.date
    site_dir = Path(site_dir)
    digest_dir = site_dir / "digest"
    runs_out = site_dir / "runs"
    digest_dir.mkdir(parents=True, exist_ok=True)
    runs_out.mkdir(parents=True, exist_ok=True)
    result = PublishResult(date=date, site_dir=site_dir)

    def put(path: Path, data: bytes | str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(data, str):
            path.write_text(data, encoding="utf-8")
        else:
            path.write_bytes(data)
        result.written.append(path)

    put(digest_dir / f"{date}.json", raw)
    put(digest_dir / "latest.json", raw)

    run_report = Path(runs_dir) / f"{date}.json"
    if run_report.exists():
        put(runs_out / f"{date}.json", run_report.read_bytes())
        result.run_report_copied = True
    else:
        log.warning("no cost report at %s; runs/%s.json not published", run_report, date)

    result.index = build_index(digest_dir, load_index(digest_dir / "index.json"))
    put(digest_dir / "index.json", json.dumps([e.to_dict() for e in result.index], indent=2) + "\n")

    if privacy_html is not None and Path(privacy_html).exists():
        shutil.copyfile(privacy_html, site_dir / "privacy_policy.html")
        result.written.append(site_dir / "privacy_policy.html")
        result.privacy_copied = True
    elif privacy_html is not None:
        log.info("no %s yet; privacy_policy.html not published", privacy_html)

    put(site_dir / ".nojekyll", "")
    put(site_dir / "index.html", INDEX_HTML)
    return result


# ── Actions step summary ──────────────────────────────────────────────────────


def step_summary(digest: Digest, run_report: Path | None) -> str:
    """Markdown for $GITHUB_STEP_SUMMARY: the cost lines first (spec: report each run's cost), then the stories."""
    lines = [f"## Sides digest {digest.date}", ""]
    if run_report is not None and run_report.exists():
        cost = RunCost.load(run_report)
        lines.append("**Cost**")
        lines.append("")
        lines += [f"- {line}" for line in cost.summary_lines()]
        lines.append(f"- cost report: `runs/{digest.date}.json` on the site, `pipeline/out/runs/{digest.date}.json` in the artifact")
    else:
        lines.append(f"**Cost**: ${digest.meta.cost_usd:.4f} (meta.cost_usd; no per-call report found)")
    lines.append("")
    lines.append(
        f"**Run**: {len(digest.stories)} stories from {digest.meta.articles_collected} articles across "
        f"{digest.meta.outlets_polled} outlets · model {digest.meta.model} · validator kept {digest.meta.validation.kept}, "
        f"dropped {digest.meta.validation.dropped}"
    )
    lines.append("")
    lines.append("| # | Story | Outlets | L/C/R | W/E | Blindspot |")
    lines.append("|---|---|---|---|---|---|")
    for s in digest.stories:
        cl, cb = s.coverage.lean, s.coverage.bloc
        flags = [f"lean={s.blindspot.lean}"] if s.blindspot.lean else []
        if s.blindspot.bloc:
            flags.append(f"bloc={s.blindspot.bloc}")
        title = s.title.replace("|", "\\|")
        lines.append(f"| {s.rank} | {title} | {s.outlet_count} | {cl.left}/{cl.centre}/{cl.right} | {cb.west}/{cb.east} | {', '.join(flags) or '-'} |")
    if digest.meta.warnings:
        lines.append("")
        lines.append("**Warnings**")
        lines.append("")
        lines += [f"- {w}" for w in digest.meta.warnings]
    lines.append("")
    lines.append(f"Live: {SITE_URL}digest/latest.json")
    return "\n".join(lines) + "\n"
