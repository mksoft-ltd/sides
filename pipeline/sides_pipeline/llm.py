"""The one Claude client wrapper shared by every LLM stage (grouping, analysis).

One streamed, structured-output request: ``client.beta.messages.stream(**kwargs)`` → ``get_final_message()``.
Request shape (checked against the claude-api skill, 14 Oct 2026, SDK 1.14):
* ``model`` from pipeline.yaml (claude-opus-5-5); thinking is always on for this model, so never send
  ``thinking``/``budget_tokens``, forced ``tool_choice`` or an assistant prefill (all 400);
* ``output_config.effort`` is the only depth control; ``output_config.format`` carries the JSON schema;
* server-side refusal fallback: ``betas=[server-side-fallback-2026-07-01]`` + ``fallbacks="default"``;
* ``usage`` is captured for the cost report even when the call is unusable (it was billed).
* With fallbacks, ``message.model`` names the model that actually served the call, and the top-level ``usage``
  covers only that attempt. ``usage.iterations`` is the per-attempt source of truth (a declined attempt on the
  requested model is reported there with its own ``model``); :func:`attempts_from_message` turns it into
  ``Attempt``s and every one is costed (re-checked against the skill's refusal-fallback section, 15 Oct 2026).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

from .cost import Attempt, Usage

log = logging.getLogger(__name__)

FALLBACK_BETA = "server-side-fallback-2026-07-01"
EFFORT_LEVELS = ("low", "medium", "high", "xhigh", "max")


class LLMError(RuntimeError):
    """The call did not produce usable structured text. ``kind`` is one of refusal / max_tokens /
    unexpected_stop / no_text; ``usage`` is what the failed call cost (None when the request itself failed)."""

    def __init__(self, kind: str, message: str, usage: Usage | None = None, model: str | None = None,
                 attempts: tuple[Attempt, ...] = ()):
        super().__init__(message)
        self.kind = kind
        self.usage = usage
        self.model = model
        self.attempts = attempts or ((Attempt(model, usage),) if usage is not None and model else ())


@dataclass(frozen=True)
class StructuredResult:
    """The raw text of a successful structured-output call plus its accounting fields."""

    text: str
    usage: Usage
    model: str
    stop_reason: str
    seconds: float
    attempts: tuple[Attempt, ...] = ()


def make_client():  # noqa: ANN201 - anthropic.Anthropic; imported lazily so tests never need the real SDK client
    import anthropic

    return anthropic.Anthropic()  # key from ANTHROPIC_API_KEY (README: Keychain recipe); SDK retries 429/5xx


def structured_request_kwargs(*, model: str, max_tokens: int, effort: str, system: str, user: str, schema: dict) -> dict:
    if effort not in EFFORT_LEVELS:
        raise ValueError(f"effort must be one of {EFFORT_LEVELS}, got {effort!r}")
    return dict(
        model=model,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": user}],
        output_config={"effort": effort, "format": {"type": "json_schema", "schema": schema}},
        betas=[FALLBACK_BETA],
        fallbacks="default",
    )


def attempts_from_message(message, requested: str) -> tuple[Attempt, ...]:  # noqa: ANN001 - SDK BetaMessage or a duck
    """Every billed attempt of one response. Falls back to the top-level ``usage`` when ``iterations`` is absent
    (no fallback ran, or an SDK/API that does not report it)."""
    served_by = getattr(message, "model", None) or requested
    usage = getattr(message, "usage", None)
    iterations = getattr(usage, "iterations", None) or []
    out: list[Attempt] = []
    for it in iterations:
        model = getattr(it, "model", None) or (served_by if getattr(it, "type", None) == "fallback_message" else requested)
        out.append(Attempt(str(model), Usage.from_response_usage(it)))
    if not out:
        out.append(Attempt(served_by, Usage.from_response_usage(usage)))
    return tuple(out)


def run_structured(client, kwargs: dict, *, stage: str) -> StructuredResult:  # noqa: ANN001
    """Stream one request and return the text block, or raise LLMError describing why it is unusable."""
    requested = kwargs["model"]
    started = time.monotonic()
    with client.beta.messages.stream(**kwargs) as stream:
        message = stream.get_final_message()
    seconds = time.monotonic() - started

    usage = Usage.from_response_usage(message.usage)
    served_by = getattr(message, "model", requested) or requested
    attempts = attempts_from_message(message, requested)
    if served_by != requested:
        log.warning("%s was served by fallback model %s (requested %s), %d billed attempt(s)", stage, served_by, requested, len(attempts))
    stop = message.stop_reason
    if stop == "refusal":
        details = getattr(message, "stop_details", None)
        cat = getattr(details, "category", None)
        expl = getattr(details, "explanation", None)
        raise LLMError("refusal", f"model refused the {stage} request (category={cat!r}): {expl or 'no explanation'}", usage, served_by, attempts)
    if stop == "max_tokens":
        raise LLMError("max_tokens", f"{stage} response was truncated at max_tokens={kwargs['max_tokens']}; raise {stage}.max_tokens", usage, served_by, attempts)
    if stop not in ("end_turn", "stop_sequence"):
        raise LLMError("unexpected_stop", f"unexpected stop_reason {stop!r} from {stage} call", usage, served_by, attempts)
    text = next((b.text for b in message.content if getattr(b, "type", None) == "text"), None)
    if text is None:
        raise LLMError("no_text", f"{stage} response contained no text block", usage, served_by, attempts)
    return StructuredResult(text=text, usage=usage, model=served_by, stop_reason=stop, seconds=seconds, attempts=attempts)


def usage_from_fixture(u: dict) -> Usage:
    """``usage`` as recorded in a tests/fixtures/llm/*.json file (API field names)."""
    return Usage(
        input_tokens=int(u.get("input_tokens", 0)),
        output_tokens=int(u.get("output_tokens", 0)),
        cache_read_tokens=int(u.get("cache_read_input_tokens", 0)),
        cache_write_tokens=int(u.get("cache_creation_input_tokens", 0)),
    )


def usage_to_fixture(u: Usage) -> dict:
    return {
        "input_tokens": u.input_tokens,
        "output_tokens": u.output_tokens,
        "cache_read_input_tokens": u.cache_read_tokens,
        "cache_creation_input_tokens": u.cache_write_tokens,
    }
