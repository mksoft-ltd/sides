// A reader's search → the articles it selects. The query is untrusted text: it is only ever used as a
// keyword filter in this file and never reaches the model (prompt.ts passes a fixed, neutral title).

import type { Article, Outlet } from "./types.ts";

const STOP = new Set(
  "the a an and or of to in on for at by with from as is are was were be been its it this that after over amid into new says say said than more about up out off will can how why what who when where his her their has have had not but news".split(
    " ",
  ),
);
const FOLD: Record<string, string> = { "‘": "'", "’": "'", "“": '"', "”": '"', "–": "-", "—": "-" };

export function fold(s: string): string {
  return (s || "").replace(/[‘’“”–—]/g, (c) => FOLD[c] ?? c).toLowerCase();
}

/** Lower-cased content words of the query, ≥2 chars, stop words removed, de-duplicated, in order. */
export function queryTerms(query: string): string[] {
  const words = fold(query).match(/[a-z0-9]+/g) ?? [];
  const out: string[] = [];
  for (const w of words) {
    if (w.length < 2 || STOP.has(w) || out.includes(w)) continue;
    out.push(w);
    if (out.length >= 8) break;
  }
  return out;
}

/** Stable cache key material: the sorted terms. Two phrasings of one topic share a key. */
export function normalisedQuery(query: string): string {
  return [...queryTerms(query)].sort().join(" ");
}

/** A short, plain display title for the result: the reader's words, capitalised, ≤ 90 chars. */
export function displayTitle(query: string): string {
  const words = (query.match(/[\p{L}\p{N}'’-]+/gu) ?? []).slice(0, 12);
  const t = words.join(" ").slice(0, 90).trim();
  return t ? t[0].toUpperCase() + t.slice(1) : "Search";
}

/** Whole-word, stem-tolerant match: "strike" matches "strikes", "striking" matches "strike"? No: prefix of ≥4. */
function termMatches(term: string, haystack: string): boolean {
  if (term.length >= 4) {
    // Prefix match on word starts: "refiner" ~ "refineries", "strike" ~ "strikes".
    const re = new RegExp(`\\b${term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`, "i");
    return re.test(haystack);
  }
  const re = new RegExp(`\\b${term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i");
  return re.test(haystack);
}

export interface Match {
  articles: Article[];
  outlets: Outlet[];
  /** "all" when every term matched each article, "any" when the looser pass was needed. */
  mode: "all" | "any";
}

/**
 * The articles for a query. First pass: every term must appear in the headline or snippet. If fewer than
 * [minOutlets] distinct outlets match, second pass: any term. Articles are capped at [maxArticles], keeping
 * at most two per outlet so a prolific feed cannot crowd the others out, newest first.
 */
export function selectArticles(
  query: string,
  pool: { articles: Article[]; outlets: Outlet[] },
  { minOutlets, maxArticles }: { minOutlets: number; maxArticles: number },
): Match | null {
  const terms = queryTerms(query);
  if (terms.length === 0) return null;
  const byId = new Map(pool.outlets.map((o) => [o.id, o]));
  const text = (a: Article) => fold(`${a.headline} ${a.snippet}`);

  const pass = (mode: "all" | "any"): Article[] =>
    pool.articles.filter((a) => {
      const hay = text(a);
      const hits = terms.filter((t) => termMatches(t, hay)).length;
      // Looser pass: one term is enough for a one- or two-word search, two for longer ones.
      return mode === "all" ? hits === terms.length : hits >= (terms.length <= 2 ? 1 : 2);
    });

  let mode: "all" | "any" = "all";
  let hits = pass("all");
  if (new Set(hits.map((a) => a.outlet_id)).size < minOutlets) {
    mode = "any";
    hits = pass("any");
  }
  if (new Set(hits.map((a) => a.outlet_id)).size < minOutlets) return null;

  hits.sort((a, b) => (a.published_at < b.published_at ? 1 : a.published_at > b.published_at ? -1 : 0));
  const perOutlet = new Map<string, number>();
  const chosen: Article[] = [];
  for (const a of hits) {
    const n = perOutlet.get(a.outlet_id) ?? 0;
    if (n >= 2) continue;
    perOutlet.set(a.outlet_id, n + 1);
    chosen.push(a);
    if (chosen.length >= maxArticles) break;
  }
  chosen.sort((a, b) => (a.outlet_id < b.outlet_id ? -1 : a.outlet_id > b.outlet_id ? 1 : a.published_at < b.published_at ? -1 : 1));
  const outlets = [...new Set(chosen.map((a) => a.outlet_id))]
    .map((id) => byId.get(id))
    .filter((o): o is Outlet => o !== undefined);
  return { articles: chosen, outlets, mode };
}
