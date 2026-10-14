"""Command-line entry point.

    python -m sides_pipeline.cli collect --out pipeline/out/articles.json
    python -m sides_pipeline.cli group --in pipeline/out/articles.json --out pipeline/out/stories.json
    python -m sides_pipeline.cli run --through group        # collect → group
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from datetime import UTC, datetime
from pathlib import Path

from .collect import PER_OUTLET_CAP, WINDOW_HOURS, collect
from .config import DEFAULT_OUTLETS_PATH, load_outlets
from .cost import RunCost
from .group import (
    DEFAULT_PIPELINE_CONFIG,
    ClaudeGrouper,
    FakeGrouper,
    GroupingError,
    GroupOutcome,
    load_grouping_config,
    group_articles,
)
from .models import CollectResult, Digest, Outlet
from .schema import validate_digest

log = logging.getLogger(__name__)

DEFAULT_OUT_DIR = Path("pipeline/out")


def _collect_table(outlets: list[Outlet], result: CollectResult) -> str:
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


def stories_table(digest: Digest) -> str:
    head = ("#", "title", "outlets", "L/C/R", "W/E", "blindspot")
    rows = []
    for s in digest.stories:
        cl, cb = s.coverage.lean, s.coverage.bloc
        flags = []
        if s.blindspot.lean:
            flags.append(f"lean={s.blindspot.lean}")
        if s.blindspot.bloc:
            flags.append(f"bloc={s.blindspot.bloc}")
        rows.append(
            (str(s.rank), s.title, str(s.outlet_count), f"{cl.left}/{cl.centre}/{cl.right}", f"{cb.west}/{cb.east}", ", ".join(flags) or "-")
        )
    widths = [max(len(r[i]) for r in rows + [head]) for i in range(len(head))]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths)
    lines = [fmt.format(*head), fmt.format(*["-" * w for w in widths])]
    lines += [fmt.format(*r) for r in rows]
    if not rows:
        lines.append("(no stories qualified)")
    return "\n".join(lines)


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def _do_collect(args: argparse.Namespace, out: Path) -> tuple[list[Outlet], CollectResult]:
    outlets = load_outlets(args.outlets)
    result = collect(outlets, window_hours=args.window_hours, cap=args.cap)
    _write_json(out, result.model_dump(mode="json"))
    print(_collect_table(outlets, result))
    print(f"wrote {out}")
    return outlets, result


def _do_group(collected: CollectResult, args: argparse.Namespace, out: Path, runs_dir: Path) -> GroupOutcome:
    cfg = load_grouping_config(args.config)
    cost = RunCost()
    grouper = FakeGrouper(args.replay) if getattr(args, "replay", None) else ClaudeGrouper(cfg)
    now = datetime.now(tz=UTC)
    try:
        outcome = group_articles(collected, grouper, cfg, cost, now=now)
    except GroupingError as exc:
        log.error("grouping failed: %s", exc)
        # Still account for the money spent (a refusal/truncation is a billed call).
        run_path = cost.write(runs_dir / f"{now.date().isoformat()}.json")
        print(f"grouping FAILED: {exc}\ncost report: {run_path}", file=sys.stderr)
        raise SystemExit(2) from exc

    payload = outcome.digest.model_dump(mode="json")
    validate_digest(payload)  # raises jsonschema.ValidationError on a contract break
    _write_json(out, payload)
    if args.raw_out:
        _write_json(Path(args.raw_out), {
            "model": outcome.result.model,
            "stop_reason": outcome.result.stop_reason,
            "usage": {"input_tokens": outcome.result.usage.input_tokens, "output_tokens": outcome.result.usage.output_tokens,
                      "cache_read_input_tokens": outcome.result.usage.cache_read_tokens,
                      "cache_creation_input_tokens": outcome.result.usage.cache_write_tokens},
            "response": outcome.raw_response,
        })
    run_path = cost.write(runs_dir / f"{outcome.digest.date}.json")

    print()
    print(stories_table(outcome.digest))
    print()
    print("validation: " + "; ".join(outcome.report.lines()))
    for w in outcome.digest.meta.warnings:
        print(f"WARNING: {w}")
    print()
    for line in cost.summary_lines():
        print(line)
    print(f"wall time: {outcome.result.seconds:.1f}s   model: {outcome.result.model}")
    print(f"wrote {out}")
    print(f"cost report: {run_path}")
    return outcome


def cmd_collect(args: argparse.Namespace) -> int:
    outlets, result = _do_collect(args, Path(args.out))
    enabled = sum(1 for o in outlets if o.enabled)
    return 0 if result.articles and len(result.feed_errors) < enabled else 1


def cmd_group(args: argparse.Namespace) -> int:
    collected = CollectResult.model_validate_json(Path(args.inp).read_text())
    out = Path(args.out)
    outcome = _do_group(collected, args, out, Path(args.runs_dir))
    return 0 if outcome.digest.stories else 1


def cmd_run(args: argparse.Namespace) -> int:
    out_dir = Path(args.out_dir)
    outlets, collected = _do_collect(args, out_dir / "articles.json")
    enabled = sum(1 for o in outlets if o.enabled)
    if not collected.articles or len(collected.feed_errors) >= enabled:
        print("collect produced no usable articles; stopping", file=sys.stderr)
        return 1
    if args.through == "collect":
        return 0
    args.runs_dir = str(out_dir / "runs")
    outcome = _do_group(collected, args, out_dir / "stories.json", out_dir / "runs")
    return 0 if outcome.digest.stories else 1


def _add_collect_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--outlets", default=str(DEFAULT_OUTLETS_PATH), help="outlets.yaml path")
    p.add_argument("--window-hours", type=int, default=WINDOW_HOURS, help="keep items newer than this")
    p.add_argument("--cap", type=int, default=PER_OUTLET_CAP, help="max items per outlet")


def _add_group_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--config", default=str(DEFAULT_PIPELINE_CONFIG), help="pipeline.yaml (model, effort, thresholds)")
    p.add_argument("--replay", default=None, help="replay a recorded LLM fixture instead of calling the API (no network)")
    p.add_argument("--raw-out", default=None, help="also save the model's raw grouping response here (for fixtures)")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="sides-pipeline", description="Sides daily news pipeline")
    p.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    sub = p.add_subparsers(dest="command", required=True)

    c = sub.add_parser("collect", help="fetch all outlet feeds and write articles.json")
    c.add_argument("--out", default=str(DEFAULT_OUT_DIR / "articles.json"), help="output path")
    _add_collect_args(c)
    c.set_defaults(func=cmd_collect)

    g = sub.add_parser("group", help="group articles.json into ranked stories (one Claude call)")
    g.add_argument("--in", dest="inp", default=str(DEFAULT_OUT_DIR / "articles.json"), help="articles.json path")
    g.add_argument("--out", default=str(DEFAULT_OUT_DIR / "stories.json"), help="output path")
    g.add_argument("--runs-dir", default=str(DEFAULT_OUT_DIR / "runs"), help="where <date>.json cost reports go")
    _add_group_args(g)
    g.set_defaults(func=cmd_group)

    r = sub.add_parser("run", help="run the stages in order: collect → group")
    r.add_argument("--through", choices=["collect", "group"], default="group", help="last stage to run")
    r.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="directory for articles.json, stories.json, runs/")
    _add_collect_args(r)
    _add_group_args(r)
    r.set_defaults(func=cmd_run)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    if not args.verbose:
        for noisy in ("httpx", "httpx2", "anthropic"):
            logging.getLogger(noisy).setLevel(logging.WARNING)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
