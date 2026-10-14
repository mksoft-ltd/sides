"""Loading and validating config/outlets.yaml."""

from __future__ import annotations

from pathlib import Path

import yaml
from pydantic import TypeAdapter

from .models import Outlet

DEFAULT_OUTLETS_PATH = Path(__file__).resolve().parent.parent / "config" / "outlets.yaml"

_OUTLETS = TypeAdapter(list[Outlet])


def load_outlets(path: str | Path = DEFAULT_OUTLETS_PATH) -> list[Outlet]:
    """Parse outlets.yaml, validate every row, and reject duplicate ids."""
    with open(path, "rb") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict) or "outlets" not in data:
        raise ValueError(f"{path}: expected a top-level 'outlets' list")
    outlets = _OUTLETS.validate_python(data["outlets"])
    seen: set[str] = set()
    for o in outlets:
        if o.id in seen:
            raise ValueError(f"{path}: duplicate outlet id {o.id!r}")
        seen.add(o.id)
    return outlets
