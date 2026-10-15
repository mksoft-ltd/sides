from types import SimpleNamespace

import pytest

from sides_pipeline.cost import Attempt, ModelPrice, RunCost, Usage, load_pricing, price_usage


def test_pricing_table_has_opus_55():
    p = load_pricing()
    assert p["claude-opus-5-5"] == ModelPrice(input=4.0, output=20.0, cache_read=0.20, cache_write=5.0)


def test_usage_from_sdk_like_object_and_pricing_maths():
    u = Usage.from_response_usage(SimpleNamespace(input_tokens=50_000, output_tokens=2_000, cache_read_input_tokens=10_000, cache_creation_input_tokens=1_000))
    assert u == Usage(50_000, 2_000, 10_000, 1_000)
    price = ModelPrice(input=4.0, output=20.0, cache_read=0.20, cache_write=5.0)
    # 50k*4 + 2k*20 + 10k*0.2 + 1k*5 = 0.20 + 0.04 + 0.002 + 0.005
    assert price_usage(u, price) == pytest.approx(0.247)


def test_usage_tolerates_missing_cache_fields():
    u = Usage.from_response_usage(SimpleNamespace(input_tokens=10, output_tokens=5, cache_read_input_tokens=None))
    assert u.cache_read_tokens == 0 and u.cache_write_tokens == 0


def test_run_cost_accumulates_and_summarises(tmp_path):
    rc = RunCost(pricing={"m": ModelPrice(1.0, 10.0, 0.1, 1.25)})
    rc.record("grouping", "m", Usage(1_000_000, 100_000), seconds=12.3)
    rc.record("analysis", "m", Usage(500_000, 0))
    assert rc.total_usd == pytest.approx(2.5)
    assert rc.stage_total("grouping") == pytest.approx(2.0)
    lines = rc.summary_lines()
    assert lines[0] == "grouping: 1,000,000 in / 100,000 out tokens → $2.0000"
    assert lines[-1].startswith("total: $2.5000 over 2 call(s)")
    out = rc.write(tmp_path / "runs" / "2026-10-14.json")
    data = __import__("json").loads(out.read_text())
    assert data["total_usd"] == pytest.approx(2.5) and len(data["calls"]) == 2 and data["calls"][0]["seconds"] == 12.3


def test_unknown_model_is_recorded_unpriced_with_a_warning_never_raises(tmp_path):
    """M2 (fix round 2): accounting must never throw away a paid result."""
    rc = RunCost(pricing={"m": ModelPrice(1, 1, 1, 1)})
    rc.record("grouping", "m", Usage(1_000_000, 0))
    call = rc.record("grouping", "unpriced-model", Usage(10, 5))
    assert call.usd is None and call.input_tokens == 10 and call.output_tokens == 5
    assert rc.total_usd == pytest.approx(1.0) and rc.unpriced_calls == 1
    assert len(rc.warnings) == 1 and "unpriced-model" in rc.warnings[0]
    assert rc.summary_lines()[-1] == "total: $1.0000 over 2 call(s) (1 unpriced, see warnings)"
    path = rc.write(tmp_path / "r.json")
    data = __import__("json").loads(path.read_text())
    assert data["calls"][1]["usd"] is None and data["warnings"] == rc.warnings
    again = RunCost.load(path, pricing=rc.pricing)
    assert again.warnings == rc.warnings and again.total_usd == pytest.approx(1.0)


def test_pricing_table_prices_the_refusal_fallback_models():
    p = load_pricing()
    for m in ("claude-opus-5", "claude-opus-4-8"):
        assert p[m] == ModelPrice(input=5.0, output=25.0, cache_read=0.50, cache_write=6.25)


def test_record_attempts_prices_each_attempt_at_its_own_model():
    rc = RunCost(pricing={"a": ModelPrice(1, 0, 0, 0), "b": ModelPrice(2, 0, 0, 0)})
    calls = rc.record_attempts("analysis", [Attempt("a", Usage(1_000_000, 0)), Attempt("b", Usage(1_000_000, 0))], seconds=3.0)
    assert [c.usd for c in calls] == [1.0, 2.0] and [c.seconds for c in calls] == [None, 3.0]
