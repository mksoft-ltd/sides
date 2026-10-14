"""Per-run cost accounting: every LLM call's token usage → USD via config/pricing.yaml."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

import yaml

DEFAULT_PRICING_PATH = Path(__file__).resolve().parent.parent / "config" / "pricing.yaml"
_MTOK = 1_000_000


@dataclass(frozen=True)
class ModelPrice:
    """USD per million tokens."""

    input: float
    output: float
    cache_read: float
    cache_write: float


class PricingError(KeyError):
    """No price row for the model; refuse to guess."""


def load_pricing(path: str | Path = DEFAULT_PRICING_PATH) -> dict[str, ModelPrice]:
    with open(path, "rb") as fh:
        data = yaml.safe_load(fh)
    models = (data or {}).get("models")
    if not isinstance(models, dict) or not models:
        raise ValueError(f"{path}: expected a top-level 'models' mapping")
    return {name: ModelPrice(**{k: float(v) for k, v in row.items()}) for name, row in models.items()}


@dataclass(frozen=True)
class Usage:
    """Token counts from one response's ``usage`` (cache fields are 0 when the API omits them)."""

    input_tokens: int
    output_tokens: int
    cache_read_tokens: int = 0
    cache_write_tokens: int = 0

    @classmethod
    def from_response_usage(cls, usage) -> "Usage":  # noqa: ANN001 - SDK object or any duck
        return cls(
            input_tokens=int(getattr(usage, "input_tokens", 0) or 0),
            output_tokens=int(getattr(usage, "output_tokens", 0) or 0),
            cache_read_tokens=int(getattr(usage, "cache_read_input_tokens", 0) or 0),
            cache_write_tokens=int(getattr(usage, "cache_creation_input_tokens", 0) or 0),
        )


def price_usage(usage: Usage, price: ModelPrice) -> float:
    return round(
        usage.input_tokens * price.input / _MTOK
        + usage.output_tokens * price.output / _MTOK
        + usage.cache_read_tokens * price.cache_read / _MTOK
        + usage.cache_write_tokens * price.cache_write / _MTOK,
        6,
    )


@dataclass
class CallCost:
    stage: str
    model: str
    input_tokens: int
    output_tokens: int
    cache_read_tokens: int
    cache_write_tokens: int
    usd: float
    seconds: float | None = None


@dataclass
class RunCost:
    """Accumulates every paid call in a run. Written to out/runs/<date>.json and summarised on stdout."""

    pricing: dict[str, ModelPrice] = field(default_factory=load_pricing)
    started_at: datetime = field(default_factory=lambda: datetime.now(tz=UTC))
    calls: list[CallCost] = field(default_factory=list)

    def record(self, stage: str, model: str, usage: Usage, *, seconds: float | None = None) -> CallCost:
        try:
            price = self.pricing[model]
        except KeyError:
            raise PricingError(f"no price for model {model!r} in pricing.yaml") from None
        call = CallCost(
            stage=stage,
            model=model,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cache_read_tokens=usage.cache_read_tokens,
            cache_write_tokens=usage.cache_write_tokens,
            usd=price_usage(usage, price),
            seconds=round(seconds, 1) if seconds is not None else None,
        )
        self.calls.append(call)
        return call

    @property
    def total_usd(self) -> float:
        return round(sum(c.usd for c in self.calls), 6)

    def stage_total(self, stage: str) -> float:
        return round(sum(c.usd for c in self.calls if c.stage == stage), 6)

    def summary_lines(self) -> list[str]:
        """One line per stage, e.g. ``grouping: 55,112 in / 1,204 out tokens → $0.2445``."""
        lines = []
        for stage in dict.fromkeys(c.stage for c in self.calls):
            rows = [c for c in self.calls if c.stage == stage]
            inp = sum(c.input_tokens + c.cache_read_tokens + c.cache_write_tokens for c in rows)
            out = sum(c.output_tokens for c in rows)
            lines.append(f"{stage}: {inp:,} in / {out:,} out tokens → ${self.stage_total(stage):.4f}")
        lines.append(f"total: ${self.total_usd:.4f} over {len(self.calls)} call(s)")
        return lines

    def to_dict(self) -> dict:
        return {
            "started_at": self.started_at.isoformat().replace("+00:00", "Z"),
            "finished_at": datetime.now(tz=UTC).isoformat().replace("+00:00", "Z"),
            "total_usd": self.total_usd,
            "calls": [asdict(c) for c in self.calls],
        }

    @classmethod
    def load(cls, path: str | Path, pricing: dict[str, ModelPrice] | None = None) -> "RunCost":
        """Continue an earlier stage's report (out/runs/<date>.json) so the day's total covers every stage."""
        data = json.loads(Path(path).read_text())
        rc = cls(pricing=pricing if pricing is not None else load_pricing())
        rc.started_at = datetime.fromisoformat(data["started_at"].replace("Z", "+00:00"))
        rc.calls = [CallCost(**c) for c in data.get("calls", [])]
        return rc

    def write(self, path: str | Path) -> Path:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.to_dict(), indent=2) + "\n")
        return path
