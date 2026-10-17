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


def batch_params(kwargs: dict) -> dict:
    """A streamed request's kwargs as Message Batches ``params``: the Batches API rejects the server-side refusal
    fallback, so ``betas``/``fallbacks`` are dropped (a declined item is re-run synchronously, with the fallback)."""
    return {k: v for k, v in kwargs.items() if k not in ("betas", "fallbacks")}


def _result_from_message(message, requested: str, stage: str, seconds: float, *, batch: bool) -> StructuredResult:  # noqa: ANN001
    usage = Usage.from_response_usage(message.usage)
    served_by = getattr(message, "model", requested) or requested
    attempts = tuple(Attempt(a.model, a.usage, batch=batch) for a in attempts_from_message(message, requested))
    stop = message.stop_reason
    if stop == "refusal":
        raise LLMError("refusal", f"model refused the {stage} request", usage, served_by, attempts)
    if stop == "max_tokens":
        raise LLMError("max_tokens", f"{stage} response was truncated at max_tokens", usage, served_by, attempts)
    if stop not in ("end_turn", "stop_sequence"):
        raise LLMError("unexpected_stop", f"unexpected stop_reason {stop!r} from {stage} call", usage, served_by, attempts)
    text = next((b.text for b in message.content if getattr(b, "type", None) == "text"), None)
    if text is None:
        raise LLMError("no_text", f"{stage} response contained no text block", usage, served_by, attempts)
    return StructuredResult(text=text, usage=usage, model=served_by, stop_reason=stop, seconds=seconds, attempts=attempts)


def run_batch(client, requests: dict[str, dict], *, stage: str, deadline_s: float, poll_s: float,  # noqa: ANN001
              sleep=time.sleep, clock=time.monotonic) -> dict[str, StructuredResult | LLMError]:
    """Run ``{custom_id: request kwargs}`` through the Message Batches API at half price.

    Polls until the batch ends or ``deadline_s`` passes; past the deadline the batch is cancelled and whatever
    finished is kept. Every id maps to a StructuredResult or an LLMError: a billed failure (refusal, truncation)
    carries its batch-priced attempts; an item that errored, expired, was cancelled or never came back is an
    unbilled ``kind="batch_<type>"`` error. Callers re-run every error synchronously."""
    if not requests:
        return {}
    started = clock()
    batch = client.messages.batches.create(
        requests=[{"custom_id": cid, "params": batch_params(kw)} for cid, kw in requests.items()]
    )
    log.info("%s: batch %s submitted with %d request(s)", stage, batch.id, len(requests))
    cancelled = False
    while batch.processing_status != "ended":
        if not cancelled and clock() - started > deadline_s:
            log.warning("%s: batch %s not done after %.0f s; cancelling, finished items are kept", stage, batch.id, deadline_s)
            client.messages.batches.cancel(batch.id)
            cancelled = True
        elif cancelled and clock() - started > deadline_s + 120:
            log.warning("%s: batch %s still not ended after cancel; giving up on it", stage, batch.id)
            break
        sleep(poll_s)
        batch = client.messages.batches.retrieve(batch.id)
    seconds = clock() - started
    out: dict[str, StructuredResult | LLMError] = {}
    if batch.processing_status == "ended":
        for item in client.messages.batches.results(batch.id):
            kind = item.result.type
            if kind == "succeeded":
                requested = requests[item.custom_id]["model"]
                try:
                    out[item.custom_id] = _result_from_message(item.result.message, requested, stage, seconds, batch=True)
                except LLMError as exc:
                    out[item.custom_id] = exc
            else:
                out[item.custom_id] = LLMError(f"batch_{kind}", f"{stage}: batch item {kind}")
    for cid in requests:
        out.setdefault(cid, LLMError("batch_missing", f"{stage}: no batch result"))
    done = sum(1 for v in out.values() if isinstance(v, StructuredResult))
    log.info("%s: batch %s ended in %.0f s, %d/%d usable", stage, batch.id, seconds, done, len(requests))
    return out


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
