import pytest

from boundary_spans_1939 import (
    BoundaryError, boundary_id_for, build_boundaries, collect_accepted_spans,
)


def anchored(key, cid, char_from, char_to):
    return {cid: {"baseline_record_key": key, "candidate": {
        "candidate_id": cid, "postklasse": "nummereret",
        "calamari_span": {"char_from": char_from, "char_to": char_to},
        "pdf_pages": [500], "approval": {"kind": "human_approved_span_v1",
                                         "calamari_excerpt_sha256": "a" * 64}}}}


def automatic(key, cid, char_from, char_to):
    return {key: {"baseline_record_key": key, "queue_class": "auto_resolved",
                  "candidate": {"candidate_id": cid, "postklasse": "nummereret",
                                "calamari_span": {"char_from": char_from, "char_to": char_to},
                                "pdf_pages": [500]}}}


def test_spans_are_sorted_by_position_and_carry_their_origin():
    spans = collect_accepted_spans(
        {**anchored("rk-b", "human:b", 200, 300)},
        {**automatic("rk-a", "1939:a", 0, 100)},
    )

    assert [span["baseline_record_key"] for span in spans] == ["rk-a", "rk-b"]
    assert [span["origin"] for span in spans] == ["automatisk", "menneske"]
    assert spans[0]["char_from"] == 0 and spans[0]["char_to"] == 100


def test_overlapping_spans_fail_closed():
    with pytest.raises(BoundaryError, match="overlapper"):
        collect_accepted_spans(
            {**anchored("rk-a", "human:a", 0, 150)},
            {**automatic("rk-b", "1939:b", 100, 200)},
        )


def test_the_same_record_cannot_own_two_spans():
    with pytest.raises(BoundaryError, match="to gange"):
        collect_accepted_spans(
            {**anchored("rk-a", "human:a", 0, 100),
             **anchored("rk-a", "human:a2", 200, 300)},
            {},
        )


def test_boundaries_include_the_edges_of_the_source():
    spans = collect_accepted_spans({**anchored("rk-a", "human:a", 50, 100)}, {})

    boundaries = build_boundaries(spans, source_length=200)

    assert len(boundaries) == 2
    assert boundaries[0]["before"] is None
    assert boundaries[0]["gap"] == {"char_from": 0, "char_to": 50}
    assert boundaries[1]["after"] is None
    assert boundaries[1]["gap"] == {"char_from": 100, "char_to": 200}


def test_no_accepted_span_gives_one_boundary_covering_everything():
    boundaries = build_boundaries([], source_length=200)

    assert len(boundaries) == 1
    assert boundaries[0]["before"] is None and boundaries[0]["after"] is None
    assert boundaries[0]["gap"] == {"char_from": 0, "char_to": 200}


def test_adjacent_spans_give_an_empty_gap():
    spans = collect_accepted_spans(
        {**anchored("rk-a", "human:a", 0, 100), **anchored("rk-b", "human:b", 100, 200)},
        {},
    )

    middle = build_boundaries(spans, source_length=200)[1]

    assert middle["before"]["baseline_record_key"] == "rk-a"
    assert middle["after"]["baseline_record_key"] == "rk-b"
    assert middle["gap"] == {"char_from": 100, "char_to": 100}


def test_boundary_id_is_stable_and_revision_bearing():
    before = {"candidate_id": "human:a", "char_from": 0, "char_to": 100}
    after = {"candidate_id": "human:b", "char_from": 100, "char_to": 200}

    first = boundary_id_for(before, after, 0)

    assert first == boundary_id_for(before, after, 0)
    assert first != boundary_id_for(before, after, 1)
    assert first != boundary_id_for(after, before, 0)


def test_boundary_id_survives_a_cycle_only_through_its_revision():
    """A -> B -> A giver samme spænd igen; kun revisionen skiller dommene."""
    before = {"candidate_id": "human:a", "char_from": 0, "char_to": 100}
    after = {"candidate_id": "human:b", "char_from": 100, "char_to": 200}

    assert boundary_id_for(before, after, 0) != boundary_id_for(before, after, 2)
