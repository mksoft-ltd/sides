// Wire shapes shared with the pipeline (schema/digest.schema.json) and the app's parser.

export type Lean = "left" | "centre" | "right";
export type Bloc = "west" | "east";

export interface Outlet {
  id: string;
  name: string;
  lean: Lean | null;
  region: string;
  bloc: Bloc;
  ownership: string;
  country: string;
  home_url: string;
  rating_basis: string;
}

export interface Article {
  id: string;
  outlet_id: string;
  headline: string;
  snippet: string;
  url: string;
  published_at: string;
}

/** articles/<date>.json as the pipeline publishes it. */
export interface ArticlePool {
  date: string;
  collected_at: string;
  outlets: Outlet[];
  articles: Article[];
}

export interface Sourced {
  text: string;
  sources: string[];
}

export interface HeadlineQuote {
  article_id: string;
  quote: string;
  field: "headline" | "snippet";
}

export interface LeanFraming {
  lean: Lean;
  headline_quotes: HeadlineQuote[];
  emphasis: Sourced[];
}

export interface BlocFraming {
  bloc: Bloc;
  headline_quotes: HeadlineQuote[];
  emphasis: Sourced[];
}

export interface Omission {
  lean: Lean;
  text: string;
  sources: string[];
}

export interface ContestedClaim {
  claim: string;
  asserted_by: string[];
  disputed_by: string[];
}

export interface Contradiction {
  topic: string;
  west: Sourced;
  east: Sourced;
}

export interface ValidationCounts {
  kept: number;
  dropped_by_reason: Record<string, number>;
}

export interface Story {
  id: string;
  title: string;
  rank: number;
  outlet_count: number;
  coverage: { lean: Record<Lean, number>; bloc: Record<Bloc, number> };
  blindspot: { lean: Lean | null; bloc: Bloc | null };
  articles: Article[];
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

export interface Digest {
  schema_version: 1;
  generated_at: string;
  date: string;
  meta: {
    model: string;
    cost_usd: number;
    outlets_polled: number;
    articles_collected: number;
    warnings: string[];
    validation: ValidationCounts;
  };
  outlets: Outlet[];
  stories: Story[];
}

/** The model's raw structured output (shape-checked by the API, validated by validate.ts). */
export interface RawQuote {
  article_id: string;
  quote: string;
}
export interface RawFramingLean {
  lean: string;
  headline_quotes: RawQuote[];
  emphasis: Sourced[];
}
export interface RawFramingBloc {
  bloc: string;
  headline_quotes: RawQuote[];
  emphasis: Sourced[];
}
export interface AnalysisResponse {
  summary: Sourced | null;
  agreed_facts: Sourced[];
  framing: RawFramingLean[];
  omissions: { lean: string; text: string; sources: string[] }[];
  contested_claims: ContestedClaim[];
  opinion: Sourced[];
  framing_by_bloc: RawFramingBloc[];
  east_west_contradictions: { topic: string; west: Sourced; east: Sourced }[];
  conclusion: Sourced | null;
}
