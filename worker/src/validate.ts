// Port of pipeline/sides_pipeline/validate.py: nothing unsourced survives (integrity rule 2). Every item the
// model proposed is checked against the story's own articles and outlet tags; an item is dropped under the
// first failing reason and counted. Keep the rules in step with validate.py (its docstring lists them).

import { suspectText } from "./guard.ts";
import type {
  AnalysisResponse,
  Article,
  Bloc,
  BlocFraming,
  ContestedClaim,
  Contradiction,
  HeadlineQuote,
  Lean,
  LeanFraming,
  Omission,
  Outlet,
  Sourced,
  Story,
  ValidationCounts,
} from "./types.ts";

export const ANALYSIS_TEXT_MAX_CHARS = 200;
export const SYNTHESIS_TEXT_MAX_CHARS = 400;
const LEANS: Lean[] = ["left", "centre", "right"];
const BLOCS: Bloc[] = ["west", "east"];

const FOLD: Record<string, string> = {
  "‘": "'", "’": "'", "‚": "'", "“": '"', "”": '"', "„": '"', "–": "-", "—": "-", "‑": "-", " ": " ",
};

export function normaliseWs(s: string): string {
  return (s || "").split(/\s+/).filter(Boolean).join(" ");
}

export function truncateWords(s: string, limit: number): string {
  if (s.length <= limit) return s;
  const cut = s.slice(0, limit - 1);
  const at = cut.lastIndexOf(" ");
  return (at > limit / 2 ? cut.slice(0, at) : cut).trimEnd() + "…";
}

/** fold(s) plus, for every folded character, the index of the original character it came from. */
export function foldWithMap(s: string): { folded: string; idx: number[] } {
  const out: string[] = [];
  const idx: number[] = [];
  const chars = [...(s || "")];
  for (let i = 0; i < chars.length; i++) {
    const ch = FOLD[chars[i]] ?? chars[i];
    if (/\s/.test(ch)) {
      if (out.length && out[out.length - 1] !== " ") {
        out.push(" ");
        idx.push(i);
      }
      continue;
    }
    for (const c of ch.toLowerCase()) {
      out.push(c);
      idx.push(i);
    }
  }
  if (out.length && out[out.length - 1] === " ") {
    out.pop();
    idx.pop();
  }
  return { folded: out.join(""), idx };
}

export function fold(s: string): string {
  return foldWithMap(s).folded;
}

/** The exact substring of `original` whose folded form is `needle` (whitespace collapsed), or null. */
export function sourceSpan(original: string, needle: string): string | null {
  if (!needle) return null;
  const { folded, idx } = foldWithMap(original);
  const pos = folded.indexOf(needle);
  if (pos < 0) return null;
  const chars = [...original];
  const start = idx[pos];
  const end = idx[pos + needle.length - 1] + 1;
  return normaliseWs(chars.slice(start, end).join(""));
}

class Ctx {
  ids: Set<string>;
  outletOf = new Map<string, string>();
  leanOf = new Map<string, Lean | null>();
  blocOf = new Map<string, Bloc | null>();
  haystack = new Map<string, [string, string]>();
  source = new Map<string, [string, string]>();
  leansPresent = new Set<Lean>();
  blocsPresent = new Set<Bloc>();
  counts: ValidationCounts = { kept: 0, dropped_by_reason: {} };
  truncated = 0;

  constructor(articles: Article[], outlets: Map<string, Outlet>) {
    this.ids = new Set(articles.map((a) => a.id));
    for (const a of articles) {
      const o = outlets.get(a.outlet_id);
      this.outletOf.set(a.id, a.outlet_id);
      this.leanOf.set(a.id, o?.lean ?? null);
      this.blocOf.set(a.id, o?.bloc ?? null);
      this.haystack.set(a.id, [fold(a.headline), fold(a.snippet)]);
      this.source.set(a.id, [a.headline, a.snippet]);
      if (o?.lean) this.leansPresent.add(o.lean);
      if (o) this.blocsPresent.add(o.bloc);
    }
  }

  keep() {
    this.counts.kept += 1;
  }
  drop(reason: string) {
    this.counts.dropped_by_reason[reason] = (this.counts.dropped_by_reason[reason] ?? 0) + 1;
  }
  checkIds(ids: string[]): string | null {
    if (ids.some((i) => !this.ids.has(i))) return "unknown_id";
    if (ids.length === 0) return "empty_sources";
    return null;
  }
  text(s: string, limit = ANALYSIS_TEXT_MAX_CHARS): string {
    let t = normaliseWs(s);
    if (t.length > limit) {
      this.truncated += 1;
      t = truncateWords(t, limit);
    }
    return t || "…";
  }
  quoteSource(articleId: string, quote: string): [HeadlineQuote["field"], string] | null {
    const hay = this.haystack.get(articleId);
    const src = this.source.get(articleId);
    if (!hay || !src) return null;
    const needle = fold(quote);
    if (!needle) return null;
    const fields: [HeadlineQuote["field"], string, string][] = [
      ["headline", hay[0], src[0]],
      ["snippet", hay[1], src[1]],
    ];
    for (const [name, h, original] of fields) {
      if (h.includes(needle)) {
        const span = sourceSpan(original, needle);
        if (span) return [name, span];
      }
    }
    return null;
  }
}

const dedupe = (ids: string[]) => [...new Set(ids)];

function sourced(ctx: Ctx, item: Sourced, side?: { of: Map<string, string | null>; value: string }): Sourced | null {
  const ids = dedupe(item.sources ?? []);
  let reason = ctx.checkIds(ids);
  if (!reason && side && ids.some((i) => side.of.get(i) !== side.value)) reason = "source_outside_side";
  if (!reason && suspectText(item.text)) reason = "untrusted_text";
  if (reason) {
    ctx.drop(reason);
    return null;
  }
  ctx.keep();
  return { text: ctx.text(item.text), sources: ids };
}

function synthesis(ctx: Ctx, item: Sourced | null | undefined): Sourced | null {
  if (!item) return null;
  const ids = dedupe(item.sources ?? []);
  let reason = ctx.checkIds(ids);
  if (!reason && suspectText(item.text)) reason = "untrusted_text";
  if (reason) {
    ctx.drop(reason);
    return null;
  }
  ctx.keep();
  return { text: ctx.text(item.text, SYNTHESIS_TEXT_MAX_CHARS), sources: ids };
}

function framing<K extends "lean" | "bloc">(
  ctx: Ctx,
  entries: Array<{ headline_quotes: { article_id: string; quote: string }[]; emphasis: Sourced[] } & Record<K, string>>,
  kind: K,
): Array<K extends "lean" ? LeanFraming : BlocFraming> {
  const present: Set<string> = kind === "lean" ? ctx.leansPresent : ctx.blocsPresent;
  const sideOf = kind === "lean" ? ctx.leanOf : ctx.blocOf;
  const validSides: string[] = kind === "lean" ? LEANS : BLOCS;
  const merged = new Map<string, { quotes: HeadlineQuote[]; emph: Sourced[] }>();
  for (const e of entries) {
    const side = e[kind];
    if (!validSides.includes(side) || !present.has(side)) {
      ctx.drop("side_without_articles");
      continue;
    }
    if (!merged.has(side)) merged.set(side, { quotes: [], emph: [] });
    const m = merged.get(side)!;
    const seen = new Set(m.quotes.map((q) => `${q.article_id}\n${q.quote}`));
    for (const q of e.headline_quotes ?? []) {
      if (seen.has(`${q.article_id}\n${q.quote}`)) continue;
      let reason = ctx.checkIds([q.article_id]);
      if (!reason && sideOf.get(q.article_id) !== side) reason = "source_outside_side";
      const found = reason ? null : ctx.quoteSource(q.article_id, q.quote);
      if (!reason && !found) reason = "quote_not_found";
      if (!reason && found && suspectText(found[1])) reason = "untrusted_text";
      if (reason) {
        ctx.drop(reason);
        continue;
      }
      seen.add(`${q.article_id}\n${q.quote}`);
      ctx.keep();
      m.quotes.push({ article_id: q.article_id, quote: found![1], field: found![0] });
    }
    for (const item of e.emphasis ?? []) {
      const s = sourced(ctx, item, { of: sideOf, value: side });
      if (s) m.emph.push(s);
    }
  }
  const out: Array<Record<string, unknown>> = [];
  for (const side of validSides) {
    const m = merged.get(side);
    if (!m) continue;
    if (m.quotes.length === 0 && m.emph.length === 0) {
      ctx.drop("empty_framing");
      continue;
    }
    out.push({ [kind]: side, headline_quotes: m.quotes, emphasis: m.emph });
  }
  return out as unknown as Array<K extends "lean" ? LeanFraming : BlocFraming>;
}

export interface ValidatedAnalysis {
  summary: Sourced | null;
  agreed_facts: Sourced[];
  framing: LeanFraming[];
  omissions: Omission[];
  contested_claims: ContestedClaim[];
  opinion: Sourced[];
  framing_by_bloc: BlocFraming[];
  east_west_contradictions: Contradiction[];
  conclusion: Sourced | null;
  validation: ValidationCounts;
}

export function validateAnalysis(
  response: AnalysisResponse,
  articles: Article[],
  outlets: Map<string, Outlet>,
): ValidatedAnalysis {
  const ctx = new Ctx(articles, outlets);
  const summary = synthesis(ctx, response.summary);
  const conclusion = synthesis(ctx, response.conclusion);
  const agreed = (response.agreed_facts ?? []).map((i) => sourced(ctx, i)).filter((s): s is Sourced => s !== null);
  const opinion = (response.opinion ?? []).map((i) => sourced(ctx, i)).filter((s): s is Sourced => s !== null);
  const fr = framing(ctx, response.framing ?? [], "lean");
  const frb = framing(ctx, response.framing_by_bloc ?? [], "bloc");

  const omissions: Omission[] = [];
  for (const o of response.omissions ?? []) {
    const ids = dedupe(o.sources ?? []);
    let reason = ctx.checkIds(ids);
    if (!reason && (!LEANS.includes(o.lean as Lean) || !ctx.leansPresent.has(o.lean as Lean))) reason = "side_without_articles";
    if (!reason && ids.some((i) => ctx.leanOf.get(i) === o.lean)) reason = "omission_cites_omitter";
    if (!reason && suspectText(o.text)) reason = "untrusted_text";
    if (reason) {
      ctx.drop(reason);
      continue;
    }
    ctx.keep();
    omissions.push({ lean: o.lean as Lean, text: ctx.text(o.text), sources: ids });
  }

  const contested: ContestedClaim[] = [];
  for (const c of response.contested_claims ?? []) {
    const a = dedupe(c.asserted_by ?? []);
    const d = dedupe(c.disputed_by ?? []);
    let reason = ctx.checkIds(a) ?? ctx.checkIds(d);
    if (!reason) {
      const aOut = new Set(a.map((i) => ctx.outletOf.get(i)));
      if (d.some((i) => aOut.has(ctx.outletOf.get(i)))) reason = "contested_same_outlet";
    }
    if (!reason && suspectText(c.claim)) reason = "untrusted_text";
    if (reason) {
      ctx.drop(reason);
      continue;
    }
    ctx.keep();
    contested.push({ claim: ctx.text(c.claim), asserted_by: a, disputed_by: d });
  }

  const contradictions: Contradiction[] = [];
  for (const x of response.east_west_contradictions ?? []) {
    const w = dedupe(x.west?.sources ?? []);
    const e = dedupe(x.east?.sources ?? []);
    let reason = ctx.checkIds(w) ?? ctx.checkIds(e);
    if (!reason && (w.some((i) => ctx.blocOf.get(i) !== "west") || e.some((i) => ctx.blocOf.get(i) !== "east"))) {
      reason = "contradiction_wrong_bloc";
    }
    if (!reason && [x.topic, x.west.text, x.east.text].some((t) => suspectText(t))) reason = "untrusted_text";
    if (reason) {
      ctx.drop(reason);
      continue;
    }
    ctx.keep();
    contradictions.push({
      topic: ctx.text(x.topic),
      west: { text: ctx.text(x.west.text), sources: w },
      east: { text: ctx.text(x.east.text), sources: e },
    });
  }

  return {
    summary,
    conclusion,
    agreed_facts: agreed,
    framing: fr,
    omissions,
    contested_claims: contested,
    opinion,
    framing_by_bloc: frb,
    east_west_contradictions: contradictions,
    validation: ctx.counts,
  };
}

/** The story with every analysis array empty (used when the analysis call failed). */
export function emptyAnalysis(): ValidatedAnalysis {
  return {
    summary: null,
    conclusion: null,
    agreed_facts: [],
    framing: [],
    omissions: [],
    contested_claims: [],
    opinion: [],
    framing_by_bloc: [],
    east_west_contradictions: [],
    validation: { kept: 0, dropped_by_reason: {} },
  };
}

export type { Story };
