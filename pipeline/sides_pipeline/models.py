"""Pydantic models shared by every pipeline phase and mirrored in schema/digest.schema.json."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, model_validator

Lean = Literal["left", "centre", "right"]
Bloc = Literal["west", "east"]
Region = Literal["uk", "us", "europe", "middle_east", "asia", "africa", "oceania", "americas"]
Ownership = Literal["independent", "public-service", "state-funded", "state-controlled"]

SNIPPET_MAX_CHARS = 200


class Outlet(BaseModel):
    """One row of config/outlets.yaml."""

    model_config = ConfigDict(extra="forbid")

    id: str = Field(pattern=r"^[a-z][a-z0-9_]{1,31}$")
    name: str = Field(min_length=1)
    feed_url: HttpUrl
    # Tried in order when the primary feed cannot be fetched or parsed (e.g. a 429/403 from cloud IP ranges).
    feed_url_alternates: list[HttpUrl] = Field(default_factory=list)
    home_url: HttpUrl
    lean: Lean | None
    lean_note: str | None = None
    region: Region
    bloc: Bloc
    ownership: Ownership
    country: str = Field(min_length=2)
    rating_basis: str = Field(min_length=1)
    enabled: bool = True
    note: str | None = None
    # Hosts (besides home_url's) that this outlet's article links may point at; subdomains included (SEC-4).
    link_hosts: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def _https_feed(self) -> "Outlet":
        # SEC-2: a plain-HTTP feed lets anyone on the path rewrite headlines and links.
        for u in (self.feed_url, *self.feed_url_alternates):
            if u.scheme != "https":
                raise ValueError(f"{self.id}: feed_url must be https (got {u})")
        return self

    def allowed_link_hosts(self) -> tuple[str, ...]:
        home = (self.home_url.host or "").lower().removeprefix("www.")
        return tuple(dict.fromkeys([home, *(h.lower().removeprefix("www.") for h in self.link_hosts)]))

    @model_validator(mode="after")
    def _lean_rules(self) -> "Outlet":
        if self.ownership == "state-controlled":
            if self.lean is not None:
                raise ValueError(f"{self.id}: state-controlled outlets must have lean: null")
        elif self.lean is None and not self.lean_note:
            raise ValueError(f"{self.id}: lean is null but no lean_note explains why")
        return self

    def public(self) -> "OutletPublic":
        return OutletPublic(
            id=self.id,
            name=self.name,
            lean=self.lean,
            region=self.region,
            bloc=self.bloc,
            ownership=self.ownership,
            country=self.country,
            home_url=self.home_url,
            rating_basis=self.rating_basis,
        )


class OutletPublic(BaseModel):
    """The outlet record that ships in the digest (no feed URL, no operational fields)."""

    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    lean: Lean | None
    region: Region
    bloc: Bloc
    ownership: Ownership
    country: str
    home_url: HttpUrl
    rating_basis: str


IMAGE_URL_MAX_CHARS = 1000


class Article(BaseModel):
    """Headline + short snippet only. Full article text is never stored (integrity rule)."""

    model_config = ConfigDict(extra="forbid")

    id: str = Field(pattern=r"^[0-9a-f]{12}$")
    outlet_id: str
    headline: str = Field(min_length=1)
    snippet: str = Field(max_length=SNIPPET_MAX_CHARS)
    url: HttpUrl
    published_at: datetime
    published_at_estimated: bool = False
    # The feed's own thumbnail for the item, as a link to the outlet's image server: never downloaded, stored or
    # re-hosted. https only; the app shows it credited to the outlet and falls back to the outlet's initials.
    image_url: str | None = Field(default=None, max_length=IMAGE_URL_MAX_CHARS, pattern=r"^https://")


class FeedError(BaseModel):
    model_config = ConfigDict(extra="forbid")

    outlet_id: str
    error: str


class ItemDrop(BaseModel):
    """Feed items one outlet lost at collect for a security reason (``link_off_domain`` / ``instruction_text``)."""

    model_config = ConfigDict(extra="forbid")

    outlet_id: str
    reason: str
    count: int = Field(ge=1)


class CollectResult(BaseModel):
    """Contents of articles.json."""

    model_config = ConfigDict(extra="forbid")

    collected_at: datetime
    outlets: list[OutletPublic]
    articles: list[Article]
    feed_errors: list[FeedError]
    per_outlet_counts: dict[str, int]
    item_drops: list[ItemDrop] = Field(default_factory=list)


# ── Phase 2: stories ───────────────────────────────────────────────────────────

TITLE_MAX_CHARS = 90


class LeanCoverage(BaseModel):
    """Distinct outlets per lean covering a story. Outlets with lean=null are not counted anywhere."""

    model_config = ConfigDict(extra="forbid")

    left: int = Field(ge=0)
    centre: int = Field(ge=0)
    right: int = Field(ge=0)


class BlocCoverage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    west: int = Field(ge=0)
    east: int = Field(ge=0)


class Coverage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lean: LeanCoverage
    bloc: BlocCoverage


class Blindspot(BaseModel):
    """The single lean / bloc that covers a story when every other one has zero outlets, else null."""

    model_config = ConfigDict(extra="forbid")

    lean: Lean | None
    bloc: Bloc | None


# ── Phase 3: per-story analysis (every item cites article ids; validate.py drops anything unsourced) ──

ANALYSIS_TEXT_MAX_CHARS = 200
SYNTHESIS_TEXT_MAX_CHARS = 400


class Sourced(BaseModel):
    """A single analytical point and the article ids it rests on."""

    model_config = ConfigDict(extra="forbid")

    text: str = Field(min_length=1, max_length=ANALYSIS_TEXT_MAX_CHARS)
    sources: list[str] = Field(min_length=1)


class Synthesis(BaseModel):
    """A sourced paragraph that reads across the whole story: the ``summary`` (what happened, from the headlines
    and snippets) and the ``conclusion`` (where the coverage agrees, differs and stays contested). Longer than a
    point, still nothing but cited material; the validator drops it like any other item when it is not."""

    model_config = ConfigDict(extra="forbid")

    text: str = Field(min_length=1, max_length=SYNTHESIS_TEXT_MAX_CHARS)
    sources: list[str] = Field(min_length=1)


QuoteField = Literal["headline", "snippet"]


class HeadlineQuote(BaseModel):
    """Verbatim wording lifted from one article; ``field`` says whether it came from the headline or the snippet.
    The validator sets ``field`` deterministically (headline wins when the quote appears in both); the model never does."""

    model_config = ConfigDict(extra="forbid")

    article_id: str
    quote: str = Field(min_length=1)
    field: QuoteField


class LeanFraming(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lean: Lean
    headline_quotes: list[HeadlineQuote]
    emphasis: list[Sourced]


class BlocFraming(BaseModel):
    model_config = ConfigDict(extra="forbid")

    bloc: Bloc
    headline_quotes: list[HeadlineQuote]
    emphasis: list[Sourced]


class Omission(BaseModel):
    """A point lean X's coverage does not mention, sourced to the articles that DO carry it."""

    model_config = ConfigDict(extra="forbid")

    lean: Lean
    text: str = Field(min_length=1, max_length=ANALYSIS_TEXT_MAX_CHARS)
    sources: list[str] = Field(min_length=1)


class ContestedClaim(BaseModel):
    model_config = ConfigDict(extra="forbid")

    claim: str = Field(min_length=1, max_length=ANALYSIS_TEXT_MAX_CHARS)
    asserted_by: list[str] = Field(min_length=1)
    disputed_by: list[str] = Field(min_length=1)


class Contradiction(BaseModel):
    """West and East coverage stating incompatible things about one topic."""

    model_config = ConfigDict(extra="forbid")

    topic: str = Field(min_length=1, max_length=ANALYSIS_TEXT_MAX_CHARS)
    west: Sourced
    east: Sourced


class ValidationCounts(BaseModel):
    """What the citation validator kept and dropped (per story, and totalled in meta)."""

    model_config = ConfigDict(extra="forbid")

    kept: int = Field(ge=0, default=0)
    dropped_by_reason: dict[str, int] = Field(default_factory=dict)

    def add(self, other: "ValidationCounts") -> None:
        self.kept += other.kept
        for k, v in other.dropped_by_reason.items():
            self.dropped_by_reason[k] = self.dropped_by_reason.get(k, 0) + v

    @property
    def dropped(self) -> int:
        return sum(self.dropped_by_reason.values())


class Story(BaseModel):
    """One of the day's top stories. The analysis arrays are empty until phase 3 fills them (or when the
    story's analysis call failed; see meta.warnings)."""

    model_config = ConfigDict(extra="forbid")

    id: str = Field(pattern=r"^[0-9a-f]{12}$")
    title: str = Field(min_length=1, max_length=TITLE_MAX_CHARS)
    rank: int = Field(ge=1)
    outlet_count: int = Field(ge=1, description="distinct outlets")
    coverage: Coverage
    blindspot: Blindspot
    articles: list[Article] = Field(min_length=1)
    agreed_facts: list[Sourced] = Field(default_factory=list)
    framing: list[LeanFraming] = Field(default_factory=list)
    omissions: list[Omission] = Field(default_factory=list)
    contested_claims: list[ContestedClaim] = Field(default_factory=list)
    opinion: list[Sourced] = Field(default_factory=list)
    framing_by_bloc: list[BlocFraming] = Field(default_factory=list)
    east_west_contradictions: list[Contradiction] = Field(default_factory=list)
    summary: Synthesis | None = Field(default=None, description="what happened, sourced; None until analysed or when dropped")
    conclusion: Synthesis | None = Field(default=None, description="where the coverage agrees, differs and stays contested")
    validation: ValidationCounts = Field(default_factory=ValidationCounts)


class DigestMeta(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str
    cost_usd: float = Field(ge=0)
    outlets_polled: int = Field(ge=0)
    articles_collected: int = Field(ge=0)
    warnings: list[str] = Field(default_factory=list)
    validation: ValidationCounts = Field(default_factory=ValidationCounts, description="citation-validator totals")


class Digest(BaseModel):
    """The published document. After phase 2 it carries stories without analysis (stories.json)."""

    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[1] = 1
    generated_at: datetime
    date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    meta: DigestMeta
    outlets: list[OutletPublic]
    stories: list[Story]
