"""Every outlet in config/outlets.yaml must be complete and self-consistent (no network)."""

from collections import Counter
from pathlib import Path
from typing import get_args

import pytest
import yaml
from pydantic import ValidationError

from sides_pipeline.config import DEFAULT_OUTLETS_PATH, load_outlets
from sides_pipeline.models import Bloc, Lean, Outlet, Ownership, Region

REQUIRED = {"id", "name", "feed_url", "home_url", "lean", "region", "bloc", "ownership", "country", "rating_basis"}
EXCLUDED_HOSTS = ("rt.com", "sputnik", "presstv")


@pytest.fixture(scope="module")
def raw_rows() -> list[dict]:
    with open(DEFAULT_OUTLETS_PATH, "rb") as fh:
        return yaml.safe_load(fh)["outlets"]


@pytest.fixture(scope="module")
def outlets() -> list[Outlet]:
    return load_outlets()


def test_config_file_lives_where_the_plan_says():
    assert DEFAULT_OUTLETS_PATH == Path(__file__).resolve().parent.parent / "config" / "outlets.yaml"
    assert DEFAULT_OUTLETS_PATH.exists()


def test_every_row_has_required_fields(raw_rows):
    for row in raw_rows:
        missing = REQUIRED - set(row)
        assert not missing, f"{row.get('id')}: missing {sorted(missing)}"


def test_ids_unique_and_enum_values_valid(outlets):
    ids = [o.id for o in outlets]
    dupes = [i for i, n in Counter(ids).items() if n > 1]
    assert not dupes
    assert len(outlets) >= 24
    for o in outlets:
        assert o.lean in (*get_args(Lean), None)
        assert o.region in get_args(Region)
        assert o.bloc in get_args(Bloc)
        assert o.ownership in get_args(Ownership)
        assert str(o.feed_url).startswith("http")
        assert str(o.home_url).startswith("https://")


def test_lean_null_iff_state_controlled_or_noted(outlets):
    for o in outlets:
        if o.ownership == "state-controlled":
            assert o.lean is None, o.id
        elif o.lean is None:
            assert o.lean_note, f"{o.id}: lean null without lean_note"
        else:
            assert o.lean_note is None or o.lean_note, o.id


def test_disabled_outlets_carry_a_note(outlets):
    for o in outlets:
        if not o.enabled:
            assert o.note and len(o.note) > 20, o.id


def test_sanctioned_outlets_are_excluded(outlets):
    for o in outlets:
        assert not any(h in str(o.feed_url).lower() or h in str(o.home_url).lower() for h in EXCLUDED_HOSTS), o.id


def test_both_blocs_and_all_three_leans_are_enabled(outlets):
    enabled = [o for o in outlets if o.enabled]
    assert {o.bloc for o in enabled} == {"west", "east"}
    assert {o.lean for o in enabled if o.lean} == {"left", "centre", "right"}
    assert sum(1 for o in enabled if o.bloc == "east") >= 5


def test_model_rejects_inconsistent_rows():
    base = dict(id="xx", name="X", feed_url="https://x.example/rss", home_url="https://x.example/", region="asia", bloc="east", country="China", rating_basis="r")
    with pytest.raises(ValidationError):
        Outlet(lean="left", ownership="state-controlled", **base)
    with pytest.raises(ValidationError):
        Outlet(lean=None, ownership="independent", **base)
    with pytest.raises(ValidationError):
        Outlet(lean="far-left", ownership="independent", **base)
    with pytest.raises(ValidationError):
        Outlet(lean="left", ownership="independent", unknown_field=1, **base)
    assert Outlet(lean=None, ownership="independent", lean_note="n/a", **base).lean is None


def test_duplicate_ids_rejected(tmp_path):
    rows = [dict(id="dup", name="A", feed_url="https://a.example/rss", home_url="https://a.example/", lean="left", region="uk", bloc="west", ownership="independent", country="UK", rating_basis="r")]
    p = tmp_path / "outlets.yaml"
    p.write_text(yaml.safe_dump({"outlets": rows * 2}))
    with pytest.raises(ValueError, match="duplicate outlet id"):
        load_outlets(p)
