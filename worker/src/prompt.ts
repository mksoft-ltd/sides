// The user message, built exactly as pipeline/sides_pipeline/analyse.py builds it (build_story_message), so the
// prompt and the output schema stay the single source of truth shared with the daily run. The reader's query
// never appears here: the story title is a fixed neutral line and the articles were selected in code.

import type { Article, Outlet } from "./types.ts";

const TAG = /<\/?\s*articles\s*>/gi;

/** One column of an article line: no `|`, no line breaks, no `<articles>` tag (SEC-1). */
export function cell(s: string): string {
  return (s || "").replace(TAG, "[articles]").replace(/\|/g, "/").split(/\s+/).filter(Boolean).join(" ");
}

function ts(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "unknown";
  return d.toISOString().slice(0, 16) + "Z";
}

export function articleLine(a: Article, outlet: Outlet | undefined): string {
  const name = outlet?.name ?? a.outlet_id;
  const lean = outlet?.lean ?? "n/a";
  const bloc = outlet?.bloc ?? "?";
  const own = outlet?.ownership ?? "?";
  return `${a.id} | ${cell(name)} | ${lean} | ${bloc} | ${own} | ${ts(a.published_at)} | ${cell(a.headline)} | ${cell(a.snippet)}`;
}

export function sidesPresent(articles: Article[], outlets: Map<string, Outlet>) {
  const leans: Record<string, number> = {};
  const blocs: Record<string, number> = {};
  for (const a of articles) {
    const o = outlets.get(a.outlet_id);
    if (!o) continue;
    if (o.lean) leans[o.lean] = (leans[o.lean] ?? 0) + 1;
    blocs[o.bloc] = (blocs[o.bloc] ?? 0) + 1;
  }
  return { leans, blocs };
}

export const NEUTRAL_TITLE = "Articles a reader selected by keyword search";

export function buildStoryMessage(articles: Article[], outlets: Map<string, Outlet>): string {
  const { leans, blocs } = sidesPresent(articles, outlets);
  const orderL = ["left", "centre", "right"].filter((x) => x in leans);
  const orderB = ["west", "east"].filter((x) => x in blocs);
  const leanLine = orderL.map((x) => `${x} (${leans[x]})`).join(", ") || "none (no article is on the left/centre/right scale)";
  const blocLine = orderB.map((x) => `${x} (${blocs[x]})`).join(", ");
  const lines = articles.map((a) => articleLine(a, outlets.get(a.outlet_id)));
  return (
    `Story: ${NEUTRAL_TITLE}\n` +
    `Leans with articles: ${leanLine}\n` +
    `Blocs with articles: ${blocLine}\n` +
    `Articles (${lines.length}):\n\n` +
    "<articles>\n" +
    lines.join("\n") +
    "\n</articles>"
  );
}

// JSON schema sent as output_config.format: a copy of ANALYSIS_OUTPUT_SCHEMA in analyse.py (shared shapes under
// $defs so the compiled grammar stays small; see CLAUDE.md "Schema size").
const IDS = { $ref: "#/$defs/ids" };
const SOURCED = { $ref: "#/$defs/sourced" };
const QUOTE = { $ref: "#/$defs/quote" };
const SYNTHESIS = { $ref: "#/$defs/synthesis" };
const FRAMING_PROPS = {
  headline_quotes: { type: "array", items: QUOTE },
  emphasis: { type: "array", items: SOURCED },
};

export const ANALYSIS_OUTPUT_SCHEMA = {
  type: "object",
  $defs: {
    ids: { type: "array", items: { type: "string" }, description: "article ids from this story" },
    sourced: {
      type: "object",
      properties: { text: { type: "string" }, sources: IDS },
      required: ["text", "sources"],
      additionalProperties: false,
    },
    synthesis: {
      type: "object",
      properties: {
        text: { type: "string", description: "two or three plain sentences, at most 400 characters" },
        sources: { ...IDS, description: "article ids from this story that carry every statement in the text" },
      },
      required: ["text", "sources"],
      additionalProperties: false,
    },
    quote: {
      type: "object",
      properties: {
        article_id: { type: "string" },
        quote: { type: "string", description: "verbatim substring of that article's headline or snippet" },
      },
      required: ["article_id", "quote"],
      additionalProperties: false,
    },
  },
  properties: {
    summary: SYNTHESIS,
    agreed_facts: { type: "array", items: SOURCED },
    framing: {
      type: "array",
      items: {
        type: "object",
        properties: { lean: { type: "string", enum: ["left", "centre", "right"] }, ...FRAMING_PROPS },
        required: ["lean", "headline_quotes", "emphasis"],
        additionalProperties: false,
      },
    },
    omissions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          lean: { type: "string", enum: ["left", "centre", "right"], description: "the lean whose coverage lacks the point" },
          text: { type: "string" },
          sources: { ...IDS, description: "articles of OTHER leans that carry the point" },
        },
        required: ["lean", "text", "sources"],
        additionalProperties: false,
      },
    },
    contested_claims: {
      type: "array",
      items: {
        type: "object",
        properties: { claim: { type: "string" }, asserted_by: IDS, disputed_by: IDS },
        required: ["claim", "asserted_by", "disputed_by"],
        additionalProperties: false,
      },
    },
    opinion: { type: "array", items: SOURCED },
    framing_by_bloc: {
      type: "array",
      items: {
        type: "object",
        properties: { bloc: { type: "string", enum: ["west", "east"] }, ...FRAMING_PROPS },
        required: ["bloc", "headline_quotes", "emphasis"],
        additionalProperties: false,
      },
    },
    east_west_contradictions: {
      type: "array",
      items: {
        type: "object",
        properties: { topic: { type: "string" }, west: SOURCED, east: SOURCED },
        required: ["topic", "west", "east"],
        additionalProperties: false,
      },
    },
    conclusion: SYNTHESIS,
  },
  required: [
    "summary",
    "agreed_facts",
    "framing",
    "omissions",
    "contested_claims",
    "opinion",
    "framing_by_bloc",
    "east_west_contradictions",
    "conclusion",
  ],
  additionalProperties: false,
} as const;
