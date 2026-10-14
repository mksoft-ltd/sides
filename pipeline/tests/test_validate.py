"""The citation validator: one test per rule. Each fixture introduces exactly one violation and asserts that it
is the only drop, counted under the right reason, and that everything else survives untouched."""

import pytest

from conftest import aid, make_article, make_public
from sides_pipeline.analyse import AnalysisResponse
from sides_pipeline.models import Story
from sides_pipeline.stories import RawStory, build_stories
from sides_pipeline.validate import empty_analysis, fold, validate_analysis

OUTLETS = [
    make_public("l1"), make_public("l2"),
    make_public("c1", lean="centre"),
    make_public("r1", lean="right"),
    make_public("e1", lean=None, bloc="east"), make_public("e2", lean=None, bloc="east"),
]
OUTLET_MAP = {o.id: o for o in OUTLETS}

# Story with articles: a (l1), b (l2), c (c1), r (r1), e (e1), f (e2); snippets are "Snippet for <id>".
HEADLINES = {
    "a": "Minister resigns after report finds ‘serious failings’",
    "b": "Report into the care scandal blames ministers",
    "c": "Minister quits as inquiry publishes findings",
    "r": "Minister steps down; opposition demands election",
    "e": "Western government loses minister over inquiry",
    "f": "Inquiry report published; minister leaves office",
}


def _story() -> Story:
    arts = [make_article(k, o, headline=HEADLINES[k]) for k, o in (("a", "l1"), ("b", "l2"), ("c", "c1"), ("r", "r1"), ("e", "e1"), ("f", "e2"))]
    stories, _ = build_stories([RawStory("Minister resigns", [x.id for x in arts])], arts, OUTLETS)
    return stories[0]


STORY = _story()
A, B, C, R, E, F = (aid(x) for x in "abcref")


def good_response() -> dict:
    """A fully valid response touching every section (every item survives the validator)."""
    return {
        "agreed_facts": [{"text": "The minister has resigned.", "sources": [A, C, R, F]}],
        "framing": [
            {"lean": "left", "headline_quotes": [{"article_id": A, "quote": "serious failings"}], "emphasis": [{"text": "Leads with the report's findings.", "sources": [A, B]}]},
            {"lean": "centre", "headline_quotes": [{"article_id": C, "quote": "Minister quits"}], "emphasis": []},
            {"lean": "right", "headline_quotes": [], "emphasis": [{"text": "Leads with the opposition's demand.", "sources": [R]}]},
        ],
        "omissions": [{"lean": "right", "text": "Right coverage does not mention the report's findings.", "sources": [A, B]}],
        "contested_claims": [{"claim": "Who the report blames.", "asserted_by": [B], "disputed_by": [C]}],
        "opinion": [{"text": "Snippet for a", "sources": [A]}],
        "framing_by_bloc": [
            {"bloc": "west", "headline_quotes": [{"article_id": R, "quote": "demands election"}], "emphasis": [{"text": "Domestic politics.", "sources": [R, C]}]},
            {"bloc": "east", "headline_quotes": [{"article_id": E, "quote": "Western government"}], "emphasis": [{"text": "Frames it as a Western government's loss.", "sources": [E]}]},
        ],
        "east_west_contradictions": [{"topic": "Why the minister left", "west": {"text": "Resigned.", "sources": [A]}, "east": {"text": "Left office.", "sources": [F]}}],
    }


GOOD_KEPT = 1 + (1 + 1) + 1 + 1 + 1 + 1 + 1 + (1 + 1) + (1 + 1) + 1  # = 14 leaf items


def run(resp: dict):
    analysed, counts = validate_analysis(AnalysisResponse.model_validate(resp), STORY, OUTLET_MAP)
    return analysed, counts


def test_fully_sourced_response_keeps_everything():
    analysed, counts = run(good_response())
    assert counts.kept == GOOD_KEPT and counts.dropped_by_reason == {} and counts.dropped == 0
    assert [f.lean for f in analysed.framing] == ["left", "centre", "right"]
    assert [f.bloc for f in analysed.framing_by_bloc] == ["west", "east"]
    assert analysed.validation == counts
    assert analysed.east_west_contradictions[0].west.sources == [A]


def test_unknown_id_is_dropped():
    resp = good_response()
    resp["agreed_facts"].append({"text": "Cites a foreign id.", "sources": [A, "ffffffffffff"]})
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {"unknown_id": 1} and counts.kept == GOOD_KEPT
    assert len(analysed.agreed_facts) == 1


def test_unknown_id_in_contested_or_quote_is_dropped_too():
    resp = good_response()
    resp["contested_claims"].append({"claim": "x", "asserted_by": [A], "disputed_by": ["000000000000"]})
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"unknown_id": 1}
    resp = good_response()
    resp["framing"][0]["headline_quotes"].append({"article_id": "000000000000", "quote": "serious failings"})
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"unknown_id": 1}


def test_empty_sources_is_dropped():
    resp = good_response()
    resp["opinion"].append({"text": "Nobody said this.", "sources": []})
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {"empty_sources": 1} and counts.kept == GOOD_KEPT
    assert len(analysed.opinion) == 1
    resp = good_response()
    resp["east_west_contradictions"].append({"topic": "t", "west": {"text": "w", "sources": []}, "east": {"text": "e", "sources": [E]}})
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"empty_sources": 1}


def test_quote_not_a_substring_of_headline_or_snippet_is_dropped():
    resp = good_response()
    resp["framing"][0]["headline_quotes"].append({"article_id": A, "quote": "serious failings by ministers"})  # paraphrase
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {"quote_not_found": 1} and counts.kept == GOOD_KEPT
    assert [q.quote for q in analysed.framing[0].headline_quotes] == ["serious failings"]


def test_quote_matching_is_case_and_whitespace_and_curly_quote_insensitive():
    resp = good_response()
    resp["framing"][0]["headline_quotes"].append({"article_id": A, "quote": "finds  'SERIOUS   failings'"})
    resp["opinion"] = [{"text": "snippet", "sources": [A]}]
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {}
    assert len(analysed.framing[0].headline_quotes) == 2
    assert fold("‘A’ – “B”") == "'a' - \"b\""


def test_quote_from_headline_gets_field_headline():
    analysed, counts = run(good_response())
    assert counts.dropped_by_reason == {}
    q = analysed.framing[0].headline_quotes[0]
    assert q.quote == "serious failings" and q.field == "headline"
    assert all(q.field == "headline" for f in analysed.framing + analysed.framing_by_bloc for q in f.headline_quotes)


def test_quote_from_snippet_is_accepted_with_field_snippet():
    resp = good_response()
    resp["framing"][1]["headline_quotes"].append({"article_id": C, "quote": "Snippet for c"})
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {} and counts.kept == GOOD_KEPT + 1
    assert analysed.framing[1].headline_quotes[1].field == "snippet"


def test_quote_present_in_both_headline_and_snippet_is_labelled_headline():
    resp = good_response()
    resp["framing"][1]["headline_quotes"].append({"article_id": C, "quote": "Minister"})  # "Minister quits…" / "Snippet for c" – headline only
    resp["framing"][0]["headline_quotes"].append({"article_id": A, "quote": "s"})  # single letter: in both headline and snippet
    analysed, _ = run(resp)
    assert analysed.framing[0].headline_quotes[1].field == "headline"


def test_framing_for_a_lean_with_no_articles_is_dropped():
    arts_story = STORY.model_copy(update={"articles": [a for a in STORY.articles if a.outlet_id != "r1"]})
    resp = good_response()
    # remove everything else that depends on the right-lean article so only the framing entry is at fault
    resp["agreed_facts"][0]["sources"] = [A, C, F]
    resp["omissions"] = []  # the only omission was about the right lean
    resp["framing_by_bloc"][0] = {"bloc": "west", "headline_quotes": [], "emphasis": [{"text": "Domestic politics.", "sources": [C]}]}
    analysed, counts = validate_analysis(AnalysisResponse.model_validate(resp), arts_story, OUTLET_MAP)
    assert counts.dropped_by_reason == {"side_without_articles": 1}
    assert [f.lean for f in analysed.framing] == ["left", "centre"]


def test_bloc_framing_for_a_bloc_with_no_articles_is_dropped():
    west_only = STORY.model_copy(update={"articles": [a for a in STORY.articles if a.outlet_id not in ("e1", "e2")]})
    resp = good_response()
    resp["agreed_facts"][0]["sources"] = [A, C, R]
    resp["east_west_contradictions"] = []
    analysed, counts = validate_analysis(AnalysisResponse.model_validate(resp), west_only, OUTLET_MAP)
    assert counts.dropped_by_reason == {"side_without_articles": 1}
    assert [f.bloc for f in analysed.framing_by_bloc] == ["west"]


def test_emphasis_sourced_outside_its_lean_is_dropped():
    resp = good_response()
    resp["framing"][0]["emphasis"].append({"text": "Cites a centre article under left.", "sources": [A, C]})
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {"source_outside_side": 1} and counts.kept == GOOD_KEPT
    assert len(analysed.framing[0].emphasis) == 1


def test_lean_null_article_cannot_source_a_lean_emphasis():
    resp = good_response()
    resp["framing"][0]["emphasis"].append({"text": "Eastern article under left.", "sources": [E]})
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"source_outside_side": 1}


def test_headline_quote_from_another_lean_is_dropped():
    resp = good_response()
    resp["framing"][2]["headline_quotes"].append({"article_id": A, "quote": "serious failings"})  # left article under right
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"source_outside_side": 1}


def test_bloc_emphasis_sourced_outside_its_bloc_is_dropped():
    resp = good_response()
    resp["framing_by_bloc"][1]["emphasis"].append({"text": "West article under east.", "sources": [E, A]})
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"source_outside_side": 1}


def test_omission_with_empty_sources_is_dropped():
    resp = good_response()
    resp["omissions"].append({"lean": "centre", "text": "Unsourced absence.", "sources": []})
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"empty_sources": 1}


def test_omission_citing_an_article_of_the_omitting_lean_is_dropped():
    resp = good_response()
    resp["omissions"].append({"lean": "left", "text": "Left does not mention X.", "sources": [B, C]})  # B is left
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {"omission_cites_omitter": 1} and counts.kept == GOOD_KEPT
    assert len(analysed.omissions) == 1


def test_omission_for_a_lean_with_no_articles_is_dropped():
    no_centre = STORY.model_copy(update={"articles": [a for a in STORY.articles if a.outlet_id != "c1"]})
    resp = good_response()
    resp["agreed_facts"][0]["sources"] = [A, R, F]
    resp["framing"] = [f for f in resp["framing"] if f["lean"] != "centre"]
    resp["contested_claims"] = []
    resp["framing_by_bloc"][0]["emphasis"][0]["sources"] = [R]
    resp["omissions"].append({"lean": "centre", "text": "Centre does not mention X.", "sources": [A]})
    _, counts = validate_analysis(AnalysisResponse.model_validate(resp), no_centre, OUTLET_MAP)
    assert counts.dropped_by_reason == {"side_without_articles": 1}


def test_contested_claim_with_one_empty_side_is_dropped():
    resp = good_response()
    resp["contested_claims"].append({"claim": "Nobody disputes this.", "asserted_by": [A], "disputed_by": []})
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"empty_sources": 1}


def test_contested_claim_whose_sides_share_an_outlet_is_dropped():
    resp = good_response()
    resp["contested_claims"].append({"claim": "Same outlet on both sides.", "asserted_by": [A], "disputed_by": [A, C]})
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {"contested_same_outlet": 1} and counts.kept == GOOD_KEPT
    assert len(analysed.contested_claims) == 1


def test_contradiction_with_west_side_citing_an_east_article_is_dropped():
    resp = good_response()
    resp["east_west_contradictions"].append({"topic": "Mixed", "west": {"text": "w", "sources": [A, E]}, "east": {"text": "e", "sources": [F]}})
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {"contradiction_wrong_bloc": 1} and counts.kept == GOOD_KEPT
    assert len(analysed.east_west_contradictions) == 1


def test_contradiction_with_east_side_citing_a_west_article_is_dropped():
    resp = good_response()
    resp["east_west_contradictions"].append({"topic": "Mixed", "west": {"text": "w", "sources": [A]}, "east": {"text": "e", "sources": [C]}})
    _, counts = run(resp)
    assert counts.dropped_by_reason == {"contradiction_wrong_bloc": 1}


def test_framing_entry_left_empty_after_checks_is_dropped():
    resp = good_response()
    resp["framing"][1] = {"lean": "centre", "headline_quotes": [{"article_id": C, "quote": "not in headline"}], "emphasis": []}
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {"quote_not_found": 1, "empty_framing": 1}
    assert [f.lean for f in analysed.framing] == ["left", "right"]


def test_duplicate_side_entries_merge_and_duplicate_ids_collapse():
    resp = good_response()
    resp["framing"].append({"lean": "left", "headline_quotes": [{"article_id": B, "quote": "care scandal"}], "emphasis": []})
    resp["agreed_facts"][0]["sources"] = [A, A, C]
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {} and counts.kept == GOOD_KEPT + 1
    assert [f.lean for f in analysed.framing] == ["left", "centre", "right"]
    assert len(analysed.framing[0].headline_quotes) == 2
    assert analysed.agreed_facts[0].sources == [A, C]


def test_long_text_is_cut_at_a_word_boundary_not_dropped():
    resp = good_response()
    resp["agreed_facts"][0]["text"] = "word " * 60
    analysed, counts = run(resp)
    assert counts.dropped_by_reason == {}
    assert len(analysed.agreed_facts[0].text) <= 200


def test_empty_analysis_clears_every_array():
    s = empty_analysis(run(good_response())[0])
    assert s.agreed_facts == [] and s.framing == [] and s.east_west_contradictions == [] and s.validation.kept == 0
    assert s.id == STORY.id and len(s.articles) == 6
