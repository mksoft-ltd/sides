"""Deterministic validation, ranking, coverage and blindspot rules (code, never the model)."""

from conftest import aid, make_article, make_public
from sides_pipeline.stories import (
    RawStory,
    build_stories,
    clean_title,
    compute_blindspot,
    compute_coverage,
    story_id,
)

# A pool: 4 left, 2 centre, 3 right (west), 3 lean=null east outlets.
OUTLETS = [
    make_public("l1"), make_public("l2"), make_public("l3"), make_public("l4"),
    make_public("c1", lean="centre"), make_public("c2", lean="centre"),
    make_public("r1", lean="right"), make_public("r2", lean="right"), make_public("r3", lean="right"),
    make_public("e1", lean=None, bloc="east"), make_public("e2", lean=None, bloc="east"), make_public("e3", lean=None, bloc="east"),
]


def arts(*pairs):
    """pairs: (short_id, outlet_id[, minutes])"""
    return [make_article(p[0], p[1], minutes=p[2] if len(p) > 2 else 0) for p in pairs]


def test_unknown_ids_are_dropped_and_counted():
    articles = arts(("a", "l1"), ("b", "c1"), ("c", "r1"))
    raw = [RawStory("S", [aid("a"), "ffffffffffff", aid("b"), aid("c"), "nope"])]
    stories, rep = build_stories(raw, articles, OUTLETS)
    assert rep.unknown_ids_dropped == 2
    assert len(stories) == 1 and {a.id for a in stories[0].articles} == {aid("a"), aid("b"), aid("c")}


def test_article_in_two_stories_goes_to_story_with_more_distinct_outlets():
    articles = arts(("a", "l1"), ("b", "c1"), ("c", "r1"), ("d", "e1"), ("x", "l2"), ("y", "l3"), ("z", "c2"))
    big = RawStory("big", [aid("a"), aid("b"), aid("c"), aid("d"), aid("x")])  # 5 outlets
    small = RawStory("small", [aid("x"), aid("y"), aid("z")])  # 3 outlets, shares x
    stories, rep = build_stories([small, big], articles, OUTLETS)
    assert rep.duplicate_memberships_resolved == 1
    by_title = {s.title: s for s in stories}
    assert aid("x") in {a.id for a in by_title["big"].articles}
    # "small" lost x, leaving 2 distinct outlets → dropped by the threshold
    assert "small" not in by_title and rep.below_min_outlets_dropped == 1


def test_duplicate_membership_tie_goes_to_first_story():
    articles = arts(("a", "l1"), ("b", "c1"), ("c", "r1"), ("p", "l2"), ("q", "c2"))
    first = RawStory("first", [aid("a"), aid("b"), aid("c")])
    second = RawStory("second", [aid("c"), aid("p"), aid("q")])  # also 3 outlets, shares c
    stories, _ = build_stories([first, second], articles, OUTLETS)
    titles = {s.title: s for s in stories}
    assert aid("c") in {a.id for a in titles["first"].articles}
    assert "second" not in titles  # down to 2 outlets


def test_fewer_than_three_distinct_outlets_dropped_and_same_outlet_counts_once():
    articles = arts(("a", "l1"), ("b", "l1"), ("c", "l1"), ("d", "c1"), ("e", "l1"), ("f", "c1"), ("g", "r1"))
    one_outlet_many_articles = RawStory("solo", [aid("a"), aid("b"), aid("c")])  # 3 articles, 1 outlet
    two_outlets = RawStory("duo", [aid("a"), aid("d")])
    ok = RawStory("ok", [aid("e"), aid("f"), aid("g"), aid("b")])  # l1 twice → 3 distinct outlets
    stories, rep = build_stories([one_outlet_many_articles, two_outlets, ok], articles, OUTLETS)
    assert rep.below_min_outlets_dropped == 2
    assert [s.title for s in stories] == ["ok"]
    s = stories[0]
    assert s.outlet_count == 3
    assert len(s.articles) == 4  # both l1 articles kept in articles[]
    assert s.coverage.lean.left == 1  # l1 counted once


def test_ranking_order_with_all_tie_breaks():
    articles = arts(
        # A: 4 outlets, 2 leans, 1 bloc
        ("a1", "l1"), ("a2", "l2"), ("a3", "c1"), ("a4", "l3"),
        # B: 3 outlets, 3 leans, 1 bloc
        ("b1", "l1"), ("b2", "c1"), ("b3", "r1"),
        # C: 3 outlets, 2 leans, 2 blocs, earliest at minute 30
        ("c1", "l1", 30), ("c2", "r1", 40), ("c3", "e1", 50),
        # D: 3 outlets, 2 leans, 2 blocs, earliest at minute 10 → beats C
        ("d1", "l1", 10), ("d2", "r1", 60), ("d3", "e1", 70),
        # E: 3 outlets, 2 leans, 1 bloc
        ("e1", "l1"), ("e2", "l2"), ("e3", "c1"),
    )
    raw = [
        RawStory("E", [aid("e1"), aid("e2"), aid("e3")]),
        RawStory("C", [aid("c1"), aid("c2"), aid("c3")]),
        RawStory("A", [aid("a1"), aid("a2"), aid("a3"), aid("a4")]),
        RawStory("D", [aid("d1"), aid("d2"), aid("d3")]),
        RawStory("B", [aid("b1"), aid("b2"), aid("b3")]),
    ]
    stories, _ = build_stories(raw, articles, OUTLETS, min_stories=1)
    assert [s.title for s in stories] == ["A", "B", "D", "C", "E"]
    assert [s.rank for s in stories] == [1, 2, 3, 4, 5]


def test_coverage_counts_distinct_outlets_and_excludes_null_lean_from_lean():
    articles = arts(("a", "l1"), ("b", "l1"), ("c", "c1"), ("d", "e1"), ("e", "e2"))
    cov = compute_coverage(articles, {o.id: o for o in OUTLETS})
    assert cov.lean.model_dump() == {"left": 1, "centre": 1, "right": 0}
    assert cov.bloc.model_dump() == {"west": 2, "east": 2}
    assert compute_blindspot(cov).model_dump() == {"lean": None, "bloc": None}


def test_blindspot_right_only():
    cov = compute_coverage(arts(("a", "r1"), ("b", "r2"), ("c", "r3")), {o.id: o for o in OUTLETS})
    bs = compute_blindspot(cov)
    assert bs.lean == "right" and bs.bloc == "west"


def test_blindspot_east_only_has_no_lean_blindspot():
    cov = compute_coverage(arts(("a", "e1"), ("b", "e2"), ("c", "e3")), {o.id: o for o in OUTLETS})
    assert cov.lean.model_dump() == {"left": 0, "centre": 0, "right": 0}
    bs = compute_blindspot(cov)
    assert bs.bloc == "east" and bs.lean is None


def test_blindspot_with_one_null_lean_outlet_still_flags_lean():
    # left + left + east(null lean): lean blindspot = left, bloc blindspot = None (both blocs present)
    cov = compute_coverage(arts(("a", "l1"), ("b", "l2"), ("c", "e1")), {o.id: o for o in OUTLETS})
    bs = compute_blindspot(cov)
    assert bs.lean == "left" and bs.bloc is None


def test_top_10_cap_and_fewer_than_5_warning():
    articles = []
    raw = []
    for i in range(12):
        ids = [f"{i}a", f"{i}b", f"{i}c"]
        articles += arts((ids[0], "l1", i), (ids[1], "c1", i), (ids[2], "r1", i))
        raw.append(RawStory(f"S{i}", [aid(x) for x in ids]))
    stories, rep = build_stories(raw, articles, OUTLETS)
    assert len(stories) == 10 and rep.beyond_top_n_dropped == 2 and rep.warnings == []
    assert [s.title for s in stories] == [f"S{i}" for i in range(10)]  # identical except earliest published_at

    few, rep2 = build_stories(raw[:3], articles, OUTLETS)
    assert len(few) == 3
    assert len(rep2.warnings) == 1 and "only 3 stories" in rep2.warnings[0]


def test_story_id_is_stable_and_order_independent():
    assert story_id(["b", "a", "c"]) == story_id(["a", "b", "c"])
    assert story_id(["a", "b"]) != story_id(["a", "b", "c"])
    assert len(story_id(["a"])) == 12


def test_clean_title_caps_at_90_chars():
    long = "word " * 40
    t = clean_title(long)
    assert len(t) <= 90 and t.endswith("…")
    assert clean_title("  Neat   title ") == "Neat title"
    assert clean_title("") == "Untitled story"
