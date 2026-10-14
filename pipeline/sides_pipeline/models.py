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


class FeedError(BaseModel):
    model_config = ConfigDict(extra="forbid")

    outlet_id: str
    error: str


class CollectResult(BaseModel):
    """Contents of articles.json."""

    model_config = ConfigDict(extra="forbid")

    collected_at: datetime
    outlets: list[OutletPublic]
    articles: list[Article]
    feed_errors: list[FeedError]
    per_outlet_counts: dict[str, int]


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


class Story(BaseModel):
    """One of the day's top stories. Analysis fields (framing, contradictions, …) arrive in phase 3."""

    model_config = ConfigDict(extra="forbid")

    id: str = Field(pattern=r"^[0-9a-f]{12}$")
    title: str = Field(min_length=1, max_length=TITLE_MAX_CHARS)
    rank: int = Field(ge=1)
    outlet_count: int = Field(ge=1, description="distinct outlets")
    coverage: Coverage
    blindspot: Blindspot
    articles: list[Article] = Field(min_length=1)


class DigestMeta(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str
    cost_usd: float = Field(ge=0)
    outlets_polled: int = Field(ge=0)
    articles_collected: int = Field(ge=0)
    warnings: list[str] = Field(default_factory=list)


class Digest(BaseModel):
    """The published document. After phase 2 it carries stories without analysis (stories.json)."""

    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[1] = 1
    generated_at: datetime
    date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    meta: DigestMeta
    outlets: list[OutletPublic]
    stories: list[Story]
