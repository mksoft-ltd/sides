"""Per-run cost accounting: every LLM call's token usage → USD via config/pricing.yaml."""

from __future__ import annotations

import json
import logging
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

import yaml

log = logging.getLogger(__name__)
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
    """No price row for the model (kept for callers that want to refuse; :meth:`RunCost.record` no longer raises)."""


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


@dataclass(frozen=True)
class Attempt:
    """One billed sampling attempt: the model that ran it and what it used.

    With the server-side refusal fallback one request can run several attempts (a declined one on the requested
    model, then the fallback model that served it). ``usage.iterations`` reports each; the top-level ``usage``
    covers only the attempt that produced the message, so cost is always summed over attempts."""

    model: str
    usage: Usage


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
    usd: float | None  # None = no price row for this model (recorded, never guessed; see RunCost.warnings)
    seconds: float | None = None


@dataclass
class RunCost:
    """Accumulates every paid call in a run. Written to out/runs/<date>.json and summarised on stdout."""

    pricing: dict[str, ModelPrice] = field(default_factory=load_pricing)
    started_at: datetime = field(default_factory=lambda: datetime.now(tz=UTC))
    calls: list[CallCost] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def record(self, stage: str, model: str, usage: Usage, *, seconds: float | None = None) -> CallCost:
        """Record one billed attempt. A model with no price row is recorded with ``usd=None`` and a warning —
        accounting must never throw away a paid result (a refusal fallback can be served by any model)."""
        price = self.pricing.get(model)
        if price is None:
            msg = (f"{stage}: no price for model {model!r} in pricing.yaml; "
                   f"{usage.input_tokens:,} in / {usage.output_tokens:,} out tokens recorded unpriced")
            log.warning(msg)
            if msg not in self.warnings:
                self.warnings.append(msg)
        call = CallCost(
            stage=stage,
            model=model,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cache_read_tokens=usage.cache_read_tokens,
            cache_write_tokens=usage.cache_write_tokens,
            usd=price_usage(usage, price) if price is not None else None,
            seconds=round(seconds, 1) if seconds is not None else None,
        )
        self.calls.append(call)
        return call

    def record_attempts(self, stage: str, attempts, *, seconds: float | None = None) -> list[CallCost]:  # noqa: ANN001
        """Record every attempt of one request (wall time goes on the last, the one that produced the message)."""
        attempts = list(attempts)
        return [
            self.record(stage, a.model, a.usage, seconds=seconds if i == len(attempts) - 1 else None)
            for i, a in enumerate(attempts)
        ]

    @property
    def total_usd(self) -> float:
        return round(sum(c.usd or 0.0 for c in self.calls), 6)

    @property
    def unpriced_calls(self) -> int:
        return sum(1 for c in self.calls if c.usd is None)

    def stage_total(self, stage: str) -> float:
        return round(sum(c.usd or 0.0 for c in self.calls if c.stage == stage), 6)

    def summary_lines(self) -> list[str]:
        """One line per stage, e.g. ``grouping: 55,112 in / 1,204 out tokens → $0.2445``."""
        lines = []
        for stage in dict.fromkeys(c.stage for c in self.calls):
            rows = [c for c in self.calls if c.stage == stage]
            inp = sum(c.input_tokens + c.cache_read_tokens + c.cache_write_tokens for c in rows)
            out = sum(c.output_tokens for c in rows)
            lines.append(f"{stage}: {inp:,} in / {out:,} out tokens → ${self.stage_total(stage):.4f}")
        tail = f" ({self.unpriced_calls} unpriced, see warnings)" if self.unpriced_calls else ""
        lines.append(f"total: ${self.total_usd:.4f} over {len(self.calls)} call(s){tail}")
        return lines

    def to_dict(self) -> dict:
        return {
            "started_at": self.started_at.isoformat().replace("+00:00", "Z"),
            "finished_at": datetime.now(tz=UTC).isoformat().replace("+00:00", "Z"),
            "total_usd": self.total_usd,
            "calls": [asdict(c) for c in self.calls],
            "warnings": list(self.warnings),
        }

    @classmethod
    def load(cls, path: str | Path, pricing: dict[str, ModelPrice] | None = None) -> "RunCost":
        """Continue an earlier stage's report (out/runs/<date>.json) so the day's total covers every stage."""
        data = json.loads(Path(path).read_text())
        rc = cls(pricing=pricing if pricing is not None else load_pricing())
        rc.started_at = datetime.fromisoformat(data["started_at"].replace("Z", "+00:00"))
        rc.calls = [CallCost(**c) for c in data.get("calls", [])]
        rc.warnings = list(data.get("warnings", []))
        return rc

    def write(self, path: str | Path) -> Path:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.to_dict(), indent=2) + "\n")
        return path
