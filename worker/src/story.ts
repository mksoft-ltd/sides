// Port of the deterministic story rules in pipeline/sides_pipeline/stories.py: coverage and blindspot from
// outlet tags (integrity rule 3), the story id from the sorted article ids.

import type { Article, Bloc, Lean, Outlet } from "./types.ts";

export async function storyId(articleIds: string[]): Promise<string> {
  const data = new TextEncoder().encode([...articleIds].sort().join("\n"));
  const hash = await crypto.subtle.digest("SHA-1", data);
  return [...new Uint8Array(hash)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 12);
}

export function computeCoverage(articles: Article[], outlets: Map<string, Outlet>) {
  const lean: Record<Lean, number> = { left: 0, centre: 0, right: 0 };
  const bloc: Record<Bloc, number> = { west: 0, east: 0 };
  for (const oid of new Set(articles.map((a) => a.outlet_id))) {
    const o = outlets.get(oid);
    if (!o) continue;
    if (o.lean) lean[o.lean] += 1;
    bloc[o.bloc] += 1;
  }
  return { lean, bloc };
}

function soleNonzero<K extends string>(counts: Record<K, number>): K | null {
  const covered = (Object.keys(counts) as K[]).filter((k) => counts[k] > 0);
  return covered.length === 1 ? covered[0] : null;
}

export function computeBlindspot(coverage: { lean: Record<Lean, number>; bloc: Record<Bloc, number> }) {
  return { lean: soleNonzero(coverage.lean), bloc: soleNonzero(coverage.bloc) };
}
