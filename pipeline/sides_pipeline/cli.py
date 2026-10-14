"""Command-line entry point: ``python -m sides_pipeline.cli collect --out pipeline/out/articles.json``."""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from .collect import PER_OUTLET_CAP, WINDOW_HOURS, collect
from .config import DEFAULT_OUTLETS_PATH, load_outlets
from .models import CollectResult, Outlet


def _table(outlets: list[Outlet], result: CollectResult) -> str:
    errors = {e.outlet_id: e.error for e in result.feed_errors}
    rows = []
    for o in outlets:
        if not o.enabled:
            rows.append((o.id, o.bloc, o.lean or "-", "off", o.note or "disabled"))
            continue
        rows.append((o.id, o.bloc, o.lean or "-", str(result.per_outlet_counts.get(o.id, 0)), errors.get(o.id, "")))
    head = ("outlet", "bloc", "lean", "kept", "error")
    widths = [max(len(r[i]) for r in rows + [head]) for i in range(4)]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths) + "  {}"
    lines = [fmt.format(*head), fmt.format(*["-" * w for w in widths], "-----")]
    lines += [fmt.format(*r) for r in rows]
    enabled = [o for o in outlets if o.enabled]
    lines.append("")
    lines.append(
        f"outlets: {len(enabled)} enabled / {len(outlets) - len(enabled)} disabled   "
        f"articles: {len(result.articles)}   feed errors: {len(result.feed_errors)}   "
        f"collected_at: {result.collected_at.isoformat()}"
    )
    return "\n".join(lines)


def cmd_collect(args: argparse.Namespace) -> int:
    outlets = load_outlets(args.outlets)
    result = collect(outlets, window_hours=args.window_hours, cap=args.cap)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result.model_dump(mode="json"), indent=2, ensure_ascii=False) + "\n")
    print(_table(outlets, result))
    print(f"wrote {out}")
    enabled = sum(1 for o in outlets if o.enabled)
    return 0 if result.articles and len(result.feed_errors) < enabled else 1


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="sides-pipeline", description="Sides daily news pipeline")
    p.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    sub = p.add_subparsers(dest="command", required=True)

    c = sub.add_parser("collect", help="fetch all outlet feeds and write articles.json")
    c.add_argument("--out", default="pipeline/out/articles.json", help="output path")
    c.add_argument("--outlets", default=str(DEFAULT_OUTLETS_PATH), help="outlets.yaml path")
    c.add_argument("--window-hours", type=int, default=WINDOW_HOURS, help="keep items newer than this")
    c.add_argument("--cap", type=int, default=PER_OUTLET_CAP, help="max items per outlet")
    c.set_defaults(func=cmd_collect)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    if not args.verbose:
        logging.getLogger("httpx").setLevel(logging.WARNING)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
