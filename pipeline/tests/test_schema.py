"""articles.json records must validate against the shared JSON schema (schema/digest.schema.json)."""

import json
from pathlib import Path

import jsonschema

from conftest import FakeFetcher, make_outlet, read_fixture
from sides_pipeline.collect import collect

SCHEMA_PATH = Path(__file__).resolve().parents[2] / "schema" / "digest.schema.json"


def _schema():
    return json.loads(SCHEMA_PATH.read_text())


def test_schema_is_valid_draft_2020_12():
    jsonschema.Draft202012Validator.check_schema(_schema())


def test_collect_output_matches_schema_defs(now):
    outlets = [make_outlet("guardian", feed_url="https://g.example/rss"), make_outlet("cgtn", feed_url="https://c.example/rss", lean=None, ownership="state-controlled", bloc="east", region="asia", country="China")]
    result = collect(outlets, fetcher=FakeFetcher({"https://g.example/rss": read_fixture("real_guardian_world.xml"), "https://c.example/rss": read_fixture("real_aljazeera_all.xml")}), now=now)
    schema = _schema()
    validator = jsonschema.Draft202012Validator({"$ref": "#/$defs/collect_output", "$defs": schema["$defs"]})
    validator.validate(result.model_dump(mode="json"))


def test_schema_rejects_long_snippets_and_bad_leans():
    schema = _schema()
    article = jsonschema.Draft202012Validator({"$ref": "#/$defs/article", "$defs": schema["$defs"]})
    good = {"id": "0123456789ab", "outlet_id": "bbc", "headline": "H", "snippet": "s", "url": "https://x.example/a", "published_at": "2026-10-14T22:00:00Z", "published_at_estimated": False}
    article.validate(good)
    assert not article.is_valid({**good, "snippet": "x" * 201})
    assert not article.is_valid({**good, "body": "full text must never appear"})
    outlet = jsonschema.Draft202012Validator({"$ref": "#/$defs/outlet", "$defs": schema["$defs"]})
    assert not outlet.is_valid({"id": "x", "name": "X", "lean": "far-left", "region": "uk", "bloc": "west", "ownership": "independent", "country": "UK", "home_url": "https://x.example/", "rating_basis": "r"})
