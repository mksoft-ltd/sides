"""Validate pipeline output against schema/digest.schema.json (the contract shared with the app)."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

import jsonschema

SCHEMA_PATH = Path(__file__).resolve().parents[2] / "schema" / "digest.schema.json"


@lru_cache(maxsize=1)
def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text())


def _validator(ref: str | None = None) -> jsonschema.Draft202012Validator:
    schema = load_schema()
    if ref:
        schema = {"$ref": ref, "$defs": schema["$defs"]}
    return jsonschema.Draft202012Validator(schema, format_checker=jsonschema.Draft202012Validator.FORMAT_CHECKER)


def validate_digest(payload: dict) -> None:
    """Raise jsonschema.ValidationError if the digest/stories.json document breaks the contract."""
    _validator().validate(payload)


def validate_ref(ref: str, payload: dict) -> None:
    _validator(ref).validate(payload)
