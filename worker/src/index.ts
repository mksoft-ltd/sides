// Sides topic worker.
//
//   GET /v1/topic?q=<words>[&date=YYYY-MM-DD]
//
// Response (JSON, always 200 unless the request itself is malformed):
//   {status: "ready", cached: bool, digest: {...}}      a digest-shaped document with one story (the app's parser
//                                                        and story page take it as is)
//   {status: "pending", retry_after: 5}                  another request is analysing the same topic right now
//   {status: "no_match", matched_outlets: n}             fewer than MIN_OUTLETS distinct outlets match the words
//   {status: "capped"}                                   today's analysis budget is spent (cached topics still serve)
//   {status: "rate_limited", retry_after: 3600}          this network address asked for too many new topics
//   {status: "error", message}                           the analysis call failed; try later
//
// The reader's words are only ever a keyword filter over the day's published article pool; they never reach the
// model. Results are cached in KV for 24 hours keyed by the normalised words and the date, so a topic is paid for
// once a day however many readers ask for it.

import Anthropic from "@anthropic-ai/sdk";
import PROMPT from "./analyse.md";
import { displayTitle, normalisedQuery, selectArticles } from "./match.ts";
import { ANALYSIS_OUTPUT_SCHEMA, buildStoryMessage } from "./prompt.ts";
import { computeBlindspot, computeCoverage, storyId } from "./story.ts";
import type { AnalysisResponse, ArticlePool, Digest, Outlet, Story } from "./types.ts";
import { emptyAnalysis, validateAnalysis } from "./validate.ts";

export interface Env {
  TOPICS: KVNamespace;
  ANTHROPIC_API_KEY: string;
  SITE_BASE: string;
  MODEL: string;
  EFFORT: string;
  MAX_TOKENS: string;
  DAILY_CAP: string;
  HOURLY_PER_IP: string;
  MIN_OUTLETS: string;
  MAX_ARTICLES: string;
}

const READY_TTL = 24 * 3600;
const NO_MATCH_TTL = 3600;
const PENDING_TTL = 120;
const POOL_TTL = 600;

// USD per million tokens, matching pipeline/config/pricing.yaml for the default model.
const PRICE: Record<string, { in: number; out: number; cacheRead: number; cacheWrite: number }> = {
  "claude-opus-5-5": { in: 4, out: 20, cacheRead: 0.2, cacheWrite: 5 },
  "claude-opus-5": { in: 5, out: 25, cacheRead: 0.5, cacheWrite: 6.25 },
  "claude-opus-4-8": { in: 5, out: 25, cacheRead: 0.5, cacheWrite: 6.25 },
};

const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra },
  });

const today = () => new Date().toISOString().slice(0, 10);

async function sha1(s: string): Promise<string> {
  const h = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(s));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function loadPool(env: Env, date: string): Promise<ArticlePool | null> {
  const url = `${env.SITE_BASE}/articles/${date}.json`;
  const cache = caches.default;
  const req = new Request(url, { cf: { cacheTtl: POOL_TTL } });
  let res = await cache.match(req);
  if (!res) {
    res = await fetch(req);
    if (!res.ok) return null;
    const copy = new Response(res.body, res);
    copy.headers.set("cache-control", `public, max-age=${POOL_TTL}`);
    await cache.put(req, copy.clone());
    res = copy;
  }
  return (await res.json()) as ArticlePool;
}

/** Approximate counters in KV (not atomic; a small overrun is acceptable for a spend cap). */
async function bump(env: Env, key: string, ttl: number): Promise<number> {
  const n = Number((await env.TOPICS.get(key)) ?? "0") + 1;
  await env.TOPICS.put(key, String(n), { expirationTtl: ttl });
  return n;
}

async function analyse(env: Env, pool: ArticlePool, articles: ArticlePool["articles"], outlets: Map<string, Outlet>) {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 1, timeout: 170_000 });
  const message = (await client.beta.messages.create({
    model: env.MODEL,
    max_tokens: Number(env.MAX_TOKENS),
    system: PROMPT,
    messages: [{ role: "user", content: buildStoryMessage(articles, outlets) }],
    output_config: { effort: env.EFFORT as "high", format: { type: "json_schema", schema: ANALYSIS_OUTPUT_SCHEMA } },
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    stream: false,
  } as Parameters<typeof client.beta.messages.create>[0])) as Anthropic.Beta.BetaMessage;
  const stop = (message as { stop_reason?: string }).stop_reason;
  if (stop !== "end_turn" && stop !== "stop_sequence") {
    throw new Error(`analysis stopped with ${stop}`);
  }
  const text = (message.content as Array<{ type: string; text?: string }>).find((b) => b.type === "text")?.text;
  if (!text) throw new Error("analysis response had no text block");
  const response = JSON.parse(text) as AnalysisResponse;
  const usage = message.usage as {
    input_tokens: number;
    output_tokens: number;
    cache_read_input_tokens?: number | null;
    cache_creation_input_tokens?: number | null;
  };
  const served = (message as { model?: string }).model ?? env.MODEL;
  const price = PRICE[served] ?? PRICE[env.MODEL];
  const cost =
    (usage.input_tokens * price.in +
      usage.output_tokens * price.out +
      (usage.cache_read_input_tokens ?? 0) * price.cacheRead +
      (usage.cache_creation_input_tokens ?? 0) * price.cacheWrite) /
    1_000_000;
  return { response, model: served, cost };
}

async function buildDigest(
  env: Env,
  pool: ArticlePool,
  query: string,
  date: string,
): Promise<{ digest: Digest; cost: number } | { noMatch: number }> {
  const minOutlets = Number(env.MIN_OUTLETS);
  const match = selectArticles(query, pool, { minOutlets, maxArticles: Number(env.MAX_ARTICLES) });
  if (!match) return { noMatch: 0 };
  const outlets = new Map(match.outlets.map((o) => [o.id, o]));
  const coverage = computeCoverage(match.articles, outlets);
  const id = await storyId(match.articles.map((a) => a.id));
  let analysis = emptyAnalysis();
  let model = env.MODEL;
  let cost = 0;
  const warnings: string[] = [];
  try {
    const r = await analyse(env, pool, match.articles, outlets);
    analysis = validateAnalysis(r.response, match.articles, outlets);
    model = r.model;
    cost = r.cost;
  } catch (e) {
    warnings.push(`story 1 (${id}) has no analysis: ${(e as Error).message}`);
  }
  const story: Story = {
    id,
    title: displayTitle(query),
    rank: 1,
    outlet_count: match.outlets.length,
    coverage,
    blindspot: computeBlindspot(coverage),
    articles: match.articles,
    ...analysis,
  };
  const digest: Digest = {
    schema_version: 1,
    generated_at: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    date,
    meta: {
      model,
      cost_usd: Number(cost.toFixed(6)),
      outlets_polled: pool.outlets.length,
      articles_collected: pool.articles.length,
      warnings,
      validation: analysis.validation,
    },
    outlets: match.outlets,
    stories: [story],
  };
  return { digest, cost };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "GET" || url.pathname !== "/v1/topic") {
      return json({ status: "error", message: "GET /v1/topic?q=words[&date=YYYY-MM-DD]" }, 404);
    }
    const q = (url.searchParams.get("q") ?? "").slice(0, 120);
    const norm = normalisedQuery(q);
    if (!norm) return json({ status: "no_match", matched_outlets: 0 });
    const dateParam = url.searchParams.get("date");
    const date = dateParam && /^\d{4}-\d{2}-\d{2}$/.test(dateParam) ? dateParam : today();
    const key = `topic:v1:${date}:${await sha1(norm)}`;

    const cached = await env.TOPICS.get(key, "json") as { status: string; digest?: Digest; matched_outlets?: number } | null;
    if (cached?.status === "ready") return json({ status: "ready", cached: true, digest: cached.digest });
    if (cached?.status === "no_match") return json({ status: "no_match", matched_outlets: cached.matched_outlets ?? 0 });
    if (cached?.status === "pending") return json({ status: "pending", retry_after: 5 });

    const pool = await loadPool(env, date);
    if (!pool) return json({ status: "error", message: `no article pool for ${date}` });

    // Cheap pre-check before any budget is spent: enough outlets at all?
    const probe = selectArticles(q, pool, { minOutlets: Number(env.MIN_OUTLETS), maxArticles: Number(env.MAX_ARTICLES) });
    if (!probe) {
      await env.TOPICS.put(key, JSON.stringify({ status: "no_match", matched_outlets: 0 }), { expirationTtl: NO_MATCH_TTL });
      return json({ status: "no_match", matched_outlets: 0 });
    }

    const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
    const hour = Math.floor(Date.now() / 3_600_000);
    if ((await bump(env, `rl:${await sha1(ip)}:${hour}`, 3600)) > Number(env.HOURLY_PER_IP)) {
      return json({ status: "rate_limited", retry_after: 3600 }, 200, { "retry-after": "3600" });
    }
    if ((await bump(env, `cap:${date}`, 2 * 24 * 3600)) > Number(env.DAILY_CAP)) {
      return json({ status: "capped" });
    }

    await env.TOPICS.put(key, JSON.stringify({ status: "pending" }), { expirationTtl: PENDING_TTL });
    try {
      const built = await buildDigest(env, pool, q, date);
      if ("noMatch" in built) {
        await env.TOPICS.put(key, JSON.stringify({ status: "no_match", matched_outlets: built.noMatch }), { expirationTtl: NO_MATCH_TTL });
        return json({ status: "no_match", matched_outlets: built.noMatch });
      }
      const failed = built.digest.meta.warnings.length > 0;
      await env.TOPICS.put(key, JSON.stringify({ status: "ready", digest: built.digest }), {
        expirationTtl: failed ? 300 : READY_TTL,
      });
      return json({ status: "ready", cached: false, digest: built.digest });
    } catch (e) {
      await env.TOPICS.delete(key);
      return json({ status: "error", message: (e as Error).message });
    }
  },
};
