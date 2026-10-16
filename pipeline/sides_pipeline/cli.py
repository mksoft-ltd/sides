"""Command-line entry point.

    python -m sides_pipeline.cli collect --out pipeline/out/articles.json
    python -m sides_pipeline.cli group --in pipeline/out/articles.json --out pipeline/out/stories.json
    python -m sides_pipeline.cli analyse --in pipeline/out/stories.json --out pipeline/out/digest.json
    python -m sides_pipeline.cli show --story 1 [--in pipeline/out/digest.json]
    python -m sides_pipeline.cli run --through analyse      # collect → group → analyse
    python -m sides_pipeline.cli publish --site site [--summary-out summary.md]   # out/ → gh-pages checkout
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from datetime import UTC, datetime
from pathlib import Path

from .analyse import ClaudeAnalyser, FakeAnalyser, StoryAnalysis, analyse_stories, load_analysis_config
from .collect import PER_OUTLET_CAP, WINDOW_HOURS, collect
from .config import DEFAULT_OUTLETS_PATH, load_outlets
from .cost import RunCost
from .digest import DigestOutcome, assemble_digest
from .group import (
    DEFAULT_PIPELINE_CONFIG,
    ClaudeGrouper,
    FakeGrouper,
    GroupingError,
    GroupOutcome,
    load_grouping_config,
    group_articles,
)
from .models import CollectResult, Digest, Outlet, Story
from .publish import publish, step_summary
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
        f"items dropped: {sum(d.count for d in result.item_drops)}   "
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


def _do_group(collected: CollectResult, args: argparse.Namespace, out: Path, runs_dir: Path) -> tuple[GroupOutcome, RunCost]:
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
    return outcome, cost


# ── analyse ───────────────────────────────────────────────────────────────────


def analysis_table(outcome: DigestOutcome) -> str:
    head = ("#", "title", "facts", "leans", "omiss", "contest", "opin", "blocs", "contra", "kept", "dropped")
    rows = []
    for s in outcome.digest.stories:
        if s.id in outcome.failed:
            rows.append((str(s.rank), s.title, "-", "-", "-", "-", "-", "-", "-", "-", "FAILED"))
            continue
        v = s.validation
        rows.append((
            str(s.rank), s.title, str(len(s.agreed_facts)), str(len(s.framing)), str(len(s.omissions)),
            str(len(s.contested_claims)), str(len(s.opinion)), str(len(s.framing_by_bloc)),
            str(len(s.east_west_contradictions)), str(v.kept), str(v.dropped),
        ))
    widths = [max(len(r[i]) for r in rows + [head]) for i in range(len(head))]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths)
    lines = [fmt.format(*head), fmt.format(*["-" * w for w in widths])]
    lines += [fmt.format(*r) for r in rows]
    return "\n".join(lines)


def _validation_line(outcome: DigestOutcome) -> str:
    v = outcome.digest.meta.validation
    by = ", ".join(f"{k}={n}" for k, n in sorted(v.dropped_by_reason.items())) or "none"
    return f"validator: kept {v.kept}, dropped {v.dropped} ({by})"


def _analysis_cost_line(cost: RunCost, results: list[StoryAnalysis]) -> str:
    rows = [c for c in cost.calls if c.stage == "analysis"]
    inp = sum(c.input_tokens + c.cache_read_tokens + c.cache_write_tokens for c in rows)
    out = sum(c.output_tokens for c in rows)
    wall = max((r.seconds for r in results), default=0.0)
    return f"analysis: {len(rows)} calls, {inp:,} in / {out:,} out → ${cost.stage_total('analysis'):.4f}   (longest call {wall:.1f}s)"


def _do_analyse(stories_digest: Digest, args: argparse.Namespace, out: Path, runs_dir: Path, cost: RunCost | None) -> tuple[DigestOutcome, RunCost]:
    cfg = load_analysis_config(args.config)
    run_path = runs_dir / f"{stories_digest.date}.json"
    if cost is None:
        if run_path.exists():
            cost = RunCost.load(run_path)
        else:
            cost = RunCost()
            print(f"WARNING: no cost report at {run_path}; the total below excludes earlier stages", file=sys.stderr)
    analyser = FakeAnalyser(args.replay_dir) if getattr(args, "replay_dir", None) else ClaudeAnalyser(cfg)
    now = datetime.now(tz=UTC)
    started = now
    results = analyse_stories(stories_digest.stories, stories_digest.outlets, analyser, cfg, cost)
    wall = (datetime.now(tz=UTC) - started).total_seconds()
    outcome = assemble_digest(stories_digest, results, cost, model=cfg.model, now=now)

    payload = outcome.digest.model_dump(mode="json")
    validate_digest(payload)  # raises jsonschema.ValidationError on a contract break
    _write_json(out, payload)
    if getattr(args, "raw_out_dir", None):
        for r in results:
            if r.raw_fixture is not None:
                _write_json(Path(args.raw_out_dir) / f"{r.story_id}.json", r.raw_fixture)
    cost.write(run_path)

    print()
    print(analysis_table(outcome))
    print()
    print(_validation_line(outcome))
    for w in outcome.digest.meta.warnings:
        print(f"WARNING: {w}")
    print()
    print(_analysis_cost_line(cost, results))
    for line in cost.summary_lines():
        print(line)
    print(f"wall time: {wall:.1f}s   model: {cfg.model}   effort: {cfg.effort}   concurrency: {cfg.concurrency}")
    print(f"wrote {out}")
    print(f"cost report: {run_path}")
    return outcome, cost


def _load_digest(path: Path) -> Digest:
    return Digest.model_validate_json(path.read_text())


# ── show ──────────────────────────────────────────────────────────────────────


def _wrap(text: str, indent: int, width: int = 100) -> str:
    import textwrap

    pad = " " * indent
    return textwrap.fill(text, width=width, initial_indent=pad, subsequent_indent=pad)


def show_story(digest: Digest, story: Story) -> str:
    """Pretty-print one story's full analysis with every source resolved to 'Outlet — headline'."""
    outlets = {o.id: o for o in digest.outlets}
    arts = {a.id: a for a in story.articles}

    def ref(aid: str) -> str:
        a = arts.get(aid)
        if a is None:
            return f"[{aid}: unknown]"
        o = outlets.get(a.outlet_id)
        name = o.name if o else a.outlet_id
        return f"{name} — {a.headline}"

    def refs(ids: list[str], indent: int = 6) -> list[str]:
        return [_wrap(f"↳ {ref(i)}", indent) for i in ids]

    def sourced_block(items, label: str) -> list[str]:  # noqa: ANN001
        lines = [f"{label} ({len(items)})"]
        if not items:
            lines.append("  none")
        for it in items:
            lines.append(_wrap(f"• {it.text}", 2))
            lines += refs(it.sources)
        return lines

    def framing_block(entries, key: str, label: str) -> list[str]:  # noqa: ANN001
        lines = [f"{label} ({len(entries)})"]
        if not entries:
            lines.append("  none")
        for e in entries:
            lines.append(f"  [{getattr(e, key).upper()}]")
            if e.headline_quotes:
                lines.append("    wording:")
                for q in e.headline_quotes:
                    a = arts.get(q.article_id)
                    name = outlets[a.outlet_id].name if a and a.outlet_id in outlets else q.article_id
                    lines.append(_wrap(f'{q.field}: "{q.quote}" — {name}', 6))
            if e.emphasis:
                lines.append("    emphasis:")
                for it in e.emphasis:
                    lines.append(_wrap(f"• {it.text}", 6))
                    lines += refs(it.sources, 8)
        return lines

    cl, cb = story.coverage.lean, story.coverage.bloc
    lines = [
        f"#{story.rank}  {story.title}",
        f"story {story.id}   outlets {story.outlet_count}   articles {len(story.articles)}   "
        f"L/C/R {cl.left}/{cl.centre}/{cl.right}   W/E {cb.west}/{cb.east}   "
        f"blindspot lean={story.blindspot.lean or '-'} bloc={story.blindspot.bloc or '-'}",
        "",
        "ARTICLES",
    ]
    for a in story.articles:
        o = outlets.get(a.outlet_id)
        tag = f"{o.lean or 'n/a'}/{o.bloc}" if o else "?"
        lines.append(_wrap(f"{a.id}  {o.name if o else a.outlet_id} ({tag}): {a.headline}", 2))
    lines.append("")
    for label, syn in (("SUMMARY", story.summary), ("CONCLUSION", story.conclusion)):
        lines.append(label)
        if syn is None:
            lines.append("  none")
        else:
            lines.append(_wrap(f"• {syn.text}", 2))
            lines += refs(syn.sources)
        lines.append("")
    lines += sourced_block(story.agreed_facts, "AGREED FACTS")
    lines.append("")
    lines += framing_block(story.framing, "lean", "FRAMING BY LEAN")
    lines.append("")
    lines.append(f"OMISSIONS ({len(story.omissions)})")
    if not story.omissions:
        lines.append("  none")
    for o in story.omissions:
        lines.append(_wrap(f"• {o.lean} coverage: {o.text}", 2))
        lines += refs(o.sources)
    lines.append("")
    lines.append(f"CONTESTED CLAIMS ({len(story.contested_claims)})")
    if not story.contested_claims:
        lines.append("  none")
    for c in story.contested_claims:
        lines.append(_wrap(f"• {c.claim}", 2))
        lines.append("      asserted by:")
        lines += refs(c.asserted_by, 8)
        lines.append("      disputed by:")
        lines += refs(c.disputed_by, 8)
    lines.append("")
    lines += sourced_block(story.opinion, "OPINION / ANALYSIS PIECES")
    lines.append("")
    lines += framing_block(story.framing_by_bloc, "bloc", "FRAMING BY BLOC (WEST / EAST)")
    lines.append("")
    lines.append(f"EAST–WEST CONTRADICTIONS ({len(story.east_west_contradictions)})")
    if not story.east_west_contradictions:
        lines.append("  none found")
    for x in story.east_west_contradictions:
        lines.append(_wrap(f"• {x.topic}", 2))
        lines.append(_wrap(f"WEST: {x.west.text}", 6))
        lines += refs(x.west.sources, 8)
        lines.append(_wrap(f"EAST: {x.east.text}", 6))
        lines += refs(x.east.sources, 8)
    lines.append("")
    v = story.validation
    by = ", ".join(f"{k}={n}" for k, n in sorted(v.dropped_by_reason.items())) or "none"
    lines.append(f"validator: kept {v.kept}, dropped {v.dropped} ({by})")
    return "\n".join(lines)


def cmd_collect(args: argparse.Namespace) -> int:
    outlets, result = _do_collect(args, Path(args.out))
    enabled = sum(1 for o in outlets if o.enabled)
    return 0 if result.articles and len(result.feed_errors) < enabled else 1


def cmd_group(args: argparse.Namespace) -> int:
    collected = CollectResult.model_validate_json(Path(args.inp).read_text())
    out = Path(args.out)
    outcome, _ = _do_group(collected, args, out, Path(args.runs_dir))
    return 0 if outcome.digest.stories else 1


def cmd_analyse(args: argparse.Namespace) -> int:
    stories_digest = _load_digest(Path(args.inp))
    outcome, _ = _do_analyse(stories_digest, args, Path(args.out), Path(args.runs_dir), None)
    return 0 if len(outcome.failed) < len(outcome.digest.stories) else 1


def cmd_show(args: argparse.Namespace) -> int:
    digest = _load_digest(Path(args.inp))
    story = next((s for s in digest.stories if s.rank == args.story), None)
    if story is None:
        print(f"no story with rank {args.story} in {args.inp} ({len(digest.stories)} stories)", file=sys.stderr)
        return 1
    print(show_story(digest, story))
    return 0


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
    outcome, cost = _do_group(collected, args, out_dir / "stories.json", out_dir / "runs")
    if not outcome.digest.stories:
        return 1
    if args.through == "group":
        return 0
    analysed, _ = _do_analyse(outcome.digest, args, out_dir / "digest.json", out_dir / "runs", cost)
    return 0 if len(analysed.failed) < len(analysed.digest.stories) else 1


def cmd_publish(args: argparse.Namespace) -> int:
    digest_path = Path(args.digest)
    runs_dir = Path(args.runs_dir)
    privacy = Path(args.privacy_html) if args.privacy_html else None
    result = publish(digest_path, runs_dir, Path(args.site), privacy_html=privacy)
    for w in result.written:
        print(f"wrote {w}")
    if not result.run_report_copied:
        print(f"WARNING: no cost report for {result.date} in {runs_dir}", file=sys.stderr)
    if privacy is not None and not result.privacy_copied:
        print(f"note: {privacy} does not exist yet; privacy_policy.html not published")
    print(f"index: {len(result.index)} digest(s), latest {result.index[0].date if result.index else '-'}")
    if args.summary_out:
        digest = _load_digest(digest_path)
        report = runs_dir / f"{digest.date}.json"
        Path(args.summary_out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.summary_out).write_text(step_summary(digest, report if report.exists() else None), encoding="utf-8")
        print(f"wrote {args.summary_out}")
    return 0


def _add_collect_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--outlets", default=str(DEFAULT_OUTLETS_PATH), help="outlets.yaml path")
    p.add_argument("--window-hours", type=int, default=WINDOW_HOURS, help="keep items newer than this")
    p.add_argument("--cap", type=int, default=PER_OUTLET_CAP, help="max items per outlet")


def _add_group_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--config", default=str(DEFAULT_PIPELINE_CONFIG), help="pipeline.yaml (model, effort, thresholds)")
    p.add_argument("--replay", default=None, help="replay a recorded LLM fixture instead of calling the API (no network)")
    p.add_argument("--raw-out", default=None, help="also save the model's raw grouping response here (for fixtures)")


def _add_analyse_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--replay-dir", default=None, help="replay recorded per-story fixtures (<story_id>.json) instead of calling the API")
    p.add_argument("--raw-out-dir", default=None, help="also save each story's raw analysis response here as <story_id>.json (for fixtures)")


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

    a = sub.add_parser("analyse", help="analyse each story's framing (one Claude call per story) and write digest.json")
    a.add_argument("--in", dest="inp", default=str(DEFAULT_OUT_DIR / "stories.json"), help="stories.json path")
    a.add_argument("--out", default=str(DEFAULT_OUT_DIR / "digest.json"), help="output path")
    a.add_argument("--runs-dir", default=str(DEFAULT_OUT_DIR / "runs"), help="where <date>.json cost reports go (continued from group)")
    a.add_argument("--config", default=str(DEFAULT_PIPELINE_CONFIG), help="pipeline.yaml (model, effort, concurrency)")
    _add_analyse_args(a)
    a.set_defaults(func=cmd_analyse)

    sh = sub.add_parser("show", help="pretty-print one story's full analysis with sources resolved")
    sh.add_argument("--in", dest="inp", default=str(DEFAULT_OUT_DIR / "digest.json"), help="digest.json path")
    sh.add_argument("--story", type=int, required=True, help="story rank (1 = top)")
    sh.set_defaults(func=cmd_show)

    r = sub.add_parser("run", help="run the stages in order: collect → group → analyse")
    r.add_argument("--through", choices=["collect", "group", "analyse"], default="analyse", help="last stage to run")
    r.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="directory for articles.json, stories.json, digest.json, runs/")
    _add_collect_args(r)
    _add_group_args(r)
    _add_analyse_args(r)
    r.set_defaults(func=cmd_run)

    pb = sub.add_parser("publish", help="copy digest.json + the day's cost report into a gh-pages site checkout")
    pb.add_argument("--digest", default=str(DEFAULT_OUT_DIR / "digest.json"), help="digest.json path")
    pb.add_argument("--runs-dir", default=str(DEFAULT_OUT_DIR / "runs"), help="where <date>.json cost reports are")
    pb.add_argument("--site", required=True, help="site directory (the gh-pages checkout); created if missing")
    pb.add_argument("--privacy-html", default="privacy_policy.html", help="copied to the site root when it exists (default: repo-root privacy_policy.html)")
    pb.add_argument("--summary-out", default=None, help="also write a Markdown run summary (cost + stories) here, e.g. $GITHUB_STEP_SUMMARY")
    pb.set_defaults(func=cmd_publish)
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
