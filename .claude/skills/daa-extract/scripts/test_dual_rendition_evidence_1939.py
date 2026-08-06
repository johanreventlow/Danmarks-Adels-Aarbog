import copy
import hashlib

import pytest

from dual_rendition_evidence_1939 import (
    align_renditions,
    derive_consensus,
    locate_baseline_anchors,
)


def occ(occurrence_id, order, marker, *, text="tekst", pages=(496,),
        post_class="nummereret", section=("I",), span=None):
    start, end = span if span is not None else (order * 10, order * 10 + 10)
    return {
        "occurrence_id": occurrence_id,
        "order": order,
        "span": {"char_from": start, "char_to": end},
        "pdf_pages": list(pages),
        "post_class": post_class,
        "printed_marker": marker,
        "section_signature": list(section),
        "text": text,
    }


def manifest(*occurrences, rendition="calamari"):
    return {
        "rendition": rendition,
        "source_length": max((item["span"]["char_to"] for item in occurrences), default=0),
        "occurrences": list(occurrences),
    }


def anchor(record_key, rendition, occurrence_id):
    return {
        "record_key": record_key,
        "rendition": rendition,
        "occurrence_id": occurrence_id,
        "status": "unique_exact_anchor",
    }


def alignment_for(*occurrence_ids):
    return {"pairs": [
        {"calamari_occurrence_id": occurrence_ids[index], "raw_occurrence_id": occurrence_ids[index + 1]}
        for index in range(0, len(occurrence_ids), 2)
    ]}


def anchors_with_nested_successor(volrad_key, emeke_key):
    return {
        volrad_key: anchor(volrad_key, "calamari", "c-volrad"),
        emeke_key: anchor(emeke_key, "calamari", "c-emeke"),
    }


def volrad_manifest(rendition, *, nested):
    prefix = "c" if rendition == "calamari" else "r"
    return manifest(
        occ("%s-volrad" % prefix, 0, "1", span=(0, 15 if nested else 10)),
        occ("%s-emeke" % prefix, 1, "2", span=(10, 20)),
        rendition=rendition,
    )


def consensus_for(anchors, alignment, calamari, raw):
    return derive_consensus(
        anchors, alignment, calamari_manifest=calamari, raw_manifest=raw,
    )


def test_unique_monotone_alignment_pairs_same_structural_sequence():
    cal = manifest(occ("c1", 0, "1"), occ("c2", 1, "2"))
    raw = manifest(occ("r1", 0, "1"), occ("r2", 1, "2"), rendition="raw_ocr")
    result = align_renditions(cal, raw)
    assert result["pairs"] == [
        {"calamari_occurrence_id": "c1", "raw_occurrence_id": "r1"},
        {"calamari_occurrence_id": "c2", "raw_occurrence_id": "r2"},
    ]


def test_equally_valid_repeated_marker_is_ambiguous_not_guessed():
    cal = manifest(occ("c1", 0, "1"))
    raw = manifest(occ("r1", 0, "1"), occ("r2", 1, "1"), rendition="raw_ocr")
    result = align_renditions(cal, raw)
    assert result["pairs"] == []
    assert result["ambiguous_occurrence_ids"] == ["c1", "r1", "r2"]


def test_different_ocr_wording_can_consensus_when_boundaries_match():
    alignment = align_renditions(
        manifest(occ("c1", 0, "1", text="Volrad")),
        manifest(occ("r1", 0, "1", text="V o 1 r a d"), rendition="raw_ocr"),
    )
    assert alignment["pairs"] == [{
        "calamari_occurrence_id": "c1", "raw_occurrence_id": "r1",
    }]


def test_volrad_span_containing_emeke_anchor_is_boundary_disagreement():
    result = consensus_for(
        anchors_with_nested_successor("rk-volrad", "rk-emeke"),
        alignment_for("c-volrad", "r-volrad", "c-emeke", "r-emeke"),
        volrad_manifest("calamari", nested=False),
        volrad_manifest("raw_ocr", nested=True),
    )
    assert result["rk-volrad"]["status"] == "unanchored"
    assert result["rk-volrad"]["reason"] == "boundary_disagreement"


def test_alignment_is_identical_after_deepcopy():
    cal = manifest(occ("c1", 0, "1"), occ("c2", 1, "2"))
    raw = manifest(occ("r1", 0, "1"), occ("r2", 1, "2"), rendition="raw_ocr")
    assert align_renditions(cal, raw) == align_renditions(copy.deepcopy(cal), copy.deepcopy(raw))


def test_reordered_predecessor_is_not_consensus():
    cal = manifest(occ("c1", 0, "1"), occ("c2", 1, "2"))
    raw = manifest(occ("r1", 0, "2"), occ("r2", 1, "1"), rendition="raw_ocr")
    result = consensus_for(
        {"rk": anchor("rk", "calamari", "c2")}, alignment_for("c1", "r2", "c2", "r1"), cal, raw,
    )
    assert result["rk"] == {"record_key": "rk", "status": "unanchored", "reason": "predecessor_disagreement"}


def test_missing_successor_is_not_consensus():
    cal = manifest(occ("c1", 0, "1"), occ("c2", 1, "2"))
    raw = manifest(occ("r1", 0, "1"), rendition="raw_ocr")
    result = consensus_for({"rk": anchor("rk", "calamari", "c1")}, alignment_for("c1", "r1"), cal, raw)
    assert result["rk"] == {"record_key": "rk", "status": "unanchored", "reason": "successor_disagreement"}


def test_page_disagreement_is_not_consensus():
    cal = manifest(occ("c1", 0, "1", pages=(496,)))
    raw = manifest(occ("r1", 0, "1", pages=(497,)), rendition="raw_ocr")
    result = consensus_for({"rk": anchor("rk", "calamari", "c1")}, alignment_for("c1", "r1"), cal, raw)
    assert result["rk"] == {"record_key": "rk", "status": "unanchored", "reason": "page_disagreement"}


def test_post_class_disagreement_creates_no_compatibility_edge_or_consensus():
    cal = manifest(occ("c1", 0, "1", post_class="nummereret"))
    raw = manifest(occ("r1", 0, "1", post_class="stamfader"), rendition="raw_ocr")
    alignment = align_renditions(cal, raw)
    assert alignment["calamari_unmatched"] == ["c1"]
    assert alignment["raw_unmatched"] == ["r1"]
    result = consensus_for({"rk": anchor("rk", "calamari", "c1")}, alignment_for("c1", "r1"), cal, raw)
    assert result["rk"] == {"record_key": "rk", "status": "unanchored", "reason": "post_class_disagreement"}


def test_two_record_keys_owning_one_occurrence_are_not_consensus():
    cal = manifest(occ("c1", 0, "1"))
    raw = manifest(occ("r1", 0, "1"), rendition="raw_ocr")
    result = consensus_for(
        {"rk-1": anchor("rk-1", "calamari", "c1"), "rk-2": anchor("rk-2", "calamari", "c1")},
        alignment_for("c1", "r1"), cal, raw,
    )
    assert result == {
        "rk-1": {"record_key": "rk-1", "status": "unanchored", "reason": "occurrence_collision"},
        "rk-2": {"record_key": "rk-2", "status": "unanchored", "reason": "occurrence_collision"},
    }


def test_overlapping_accepted_spans_are_not_consensus():
    cal = manifest(
        occ("c1", 0, "1", section=("I",), span=(0, 10)),
        occ("c2", 1, "2", section=("II",), span=(5, 15)),
    )
    raw = manifest(
        occ("r1", 0, "1", section=("I",), span=(0, 10)),
        occ("r2", 1, "2", section=("II",), span=(5, 15)), rendition="raw_ocr",
    )
    result = consensus_for(
        {"rk-1": anchor("rk-1", "calamari", "c1"), "rk-2": anchor("rk-2", "calamari", "c2")},
        alignment_for("c1", "r1", "c2", "r2"), cal, raw,
    )
    assert result == {
        "rk-1": {"record_key": "rk-1", "status": "unanchored", "reason": "span_overlap"},
        "rk-2": {"record_key": "rk-2", "status": "unanchored", "reason": "span_overlap"},
    }


def test_document_edge_sentinel_allows_consensus():
    cal = manifest(occ("c1", 0, "1"))
    raw = manifest(occ("r1", 0, "1"), rendition="raw_ocr")
    result = consensus_for({"rk": anchor("rk", "calamari", "c1")}, alignment_for("c1", "r1"), cal, raw)
    assert result["rk"]["status"] == "consensus"


def occurrence_manifest(rendition, text, spans=None):
    spans = ([(0, len(text))] if text else []) if spans is None else spans
    return {
        "schema_version": 1,
        "rendition": rendition,
        "source_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "source_length": len(text),
        "occurrences": [
            {
                "occurrence_id": "occ:%s:%d" % (rendition, order),
                "span": {"char_from": start, "char_to": end},
            }
            for order, (start, end) in enumerate(spans)
        ],
    }


def baseline_record(**overrides):
    record = {
        "record_key": "rk-1",
        "_v2_lokal_id": "I.1",
        "_narrativ_kilde": "calamari",
        "narrative": "Alfa prosa",
    }
    record.update(overrides)
    return record


def test_unique_exact_narrative_binds_record_key_to_one_occurrence():
    baseline = [baseline_record()]
    result = locate_baseline_anchors(
        baseline,
        calamari_text="1. Alfa prosa\n",
        raw_text="1. A1fa prosa\n",
        calamari_occurrences=occurrence_manifest("calamari", "1. Alfa prosa\n"),
        raw_occurrences=occurrence_manifest("raw_ocr", "1. A1fa prosa\n"),
    )
    assert result["rk-1"] == {
        "record_key": "rk-1",
        "_v2_lokal_id": "I.1",
        "rendition": "calamari",
        "occurrence_id": "occ:calamari:0",
        "span": {"char_from": 3, "char_to": 13},
        "status": "unique_exact_anchor",
    }


@pytest.mark.parametrize("text,reason", [
    ("ingen tekst", "missing_exact_baseline_narrative"),
    ("Alfa prosa / Alfa prosa", "repeated_exact_baseline_narrative"),
])
def test_missing_or_repeated_narrative_never_anchors(text, reason):
    baseline = [baseline_record()]
    result = locate_baseline_anchors(
        baseline,
        calamari_text=text,
        raw_text="1. A1fa prosa\n",
        calamari_occurrences=occurrence_manifest("calamari", text),
        raw_occurrences=occurrence_manifest("raw_ocr", "1. A1fa prosa\n"),
    )
    assert result["rk-1"] == {
        "record_key": "rk-1", "status": "unanchored", "reason": reason,
    }


@pytest.mark.parametrize("field,value", [
    ("record_key", 1),
    ("_v2_lokal_id", True),
    ("_narrativ_kilde", b"calamari"),
    ("narrative", None),
])
def test_baseline_identity_and_narrative_fields_require_exact_strings(field, value):
    record = baseline_record(**{field: value})
    with pytest.raises(ValueError, match=field):
        locate_baseline_anchors(
            [record], calamari_text="Alfa prosa", raw_text="",
            calamari_occurrences=occurrence_manifest("calamari", "Alfa prosa"),
            raw_occurrences=occurrence_manifest("raw_ocr", ""),
        )


@pytest.mark.parametrize("field,value", [
    ("record_key", ""),
    ("_v2_lokal_id", ""),
])
def test_baseline_identity_fields_must_not_be_empty(field, value):
    with pytest.raises(ValueError, match=field):
        locate_baseline_anchors(
            [baseline_record(**{field: value})], calamari_text="Alfa prosa", raw_text="",
            calamari_occurrences=occurrence_manifest("calamari", "Alfa prosa"),
            raw_occurrences=occurrence_manifest("raw_ocr", ""),
        )


@pytest.mark.parametrize("field", ["record_key", "_v2_lokal_id"])
def test_baseline_ids_are_globally_unique(field):
    second = baseline_record(record_key="rk-2", _v2_lokal_id="I.2")
    second[field] = baseline_record()[field]
    with pytest.raises(ValueError, match="duplicate %s" % field):
        locate_baseline_anchors(
            [baseline_record(), second], calamari_text="Alfa prosa", raw_text="",
            calamari_occurrences=occurrence_manifest("calamari", "Alfa prosa"),
            raw_occurrences=occurrence_manifest("raw_ocr", ""),
        )


def test_unknown_narrative_source_never_uses_another_rendition():
    result = locate_baseline_anchors(
        [baseline_record(_narrativ_kilde="invented")],
        calamari_text="Alfa prosa", raw_text="Alfa prosa",
        calamari_occurrences=occurrence_manifest("calamari", "Alfa prosa"),
        raw_occurrences=occurrence_manifest("raw_ocr", "Alfa prosa"),
    )
    assert result["rk-1"] == {
        "record_key": "rk-1", "status": "unanchored", "reason": "unknown_narrative_source",
    }


def test_empty_narrative_is_never_an_anchor():
    result = locate_baseline_anchors(
        [baseline_record(narrative="")], calamari_text="Alfa prosa", raw_text="",
        calamari_occurrences=occurrence_manifest("calamari", "Alfa prosa"),
        raw_occurrences=occurrence_manifest("raw_ocr", ""),
    )
    assert result["rk-1"] == {
        "record_key": "rk-1", "status": "unanchored", "reason": "missing_exact_baseline_narrative",
    }


def test_narrative_crossing_two_occurrences_is_not_anchored():
    text = "Alfa prosa"
    result = locate_baseline_anchors(
        [baseline_record()], calamari_text=text, raw_text="",
        calamari_occurrences=occurrence_manifest("calamari", text, [(0, 4), (4, len(text))]),
        raw_occurrences=occurrence_manifest("raw_ocr", ""),
    )
    assert result["rk-1"] == {
        "record_key": "rk-1", "status": "unanchored", "reason": "anchor_outside_occurrence",
    }


def test_two_records_claiming_one_occurrence_are_both_unanchored():
    records = [baseline_record(), baseline_record(record_key="rk-2", _v2_lokal_id="I.2")]
    result = locate_baseline_anchors(
        records, calamari_text="Alfa prosa", raw_text="",
        calamari_occurrences=occurrence_manifest("calamari", "Alfa prosa"),
        raw_occurrences=occurrence_manifest("raw_ocr", ""),
    )
    assert result == {
        "rk-1": {"record_key": "rk-1", "status": "unanchored", "reason": "anchor_occurrence_collision"},
        "rk-2": {"record_key": "rk-2", "status": "unanchored", "reason": "anchor_occurrence_collision"},
    }


@pytest.mark.parametrize("narrative", ["Alfa  prosa", "alfa prosa", "Alfa\u00ad prosa"])
def test_near_matches_only_differing_by_whitespace_case_or_soft_hyphen_never_anchor(narrative):
    result = locate_baseline_anchors(
        [baseline_record(narrative=narrative)], calamari_text="Alfa prosa", raw_text="",
        calamari_occurrences=occurrence_manifest("calamari", "Alfa prosa"),
        raw_occurrences=occurrence_manifest("raw_ocr", ""),
    )
    assert result["rk-1"] == {
        "record_key": "rk-1", "status": "unanchored", "reason": "missing_exact_baseline_narrative",
    }


def test_invalid_occurrence_manifest_builtin_types_are_rejected():
    manifest = occurrence_manifest("calamari", "Alfa prosa")
    manifest["occurrences"][0]["span"]["char_to"] = True
    with pytest.raises(ValueError, match="char_to"):
        locate_baseline_anchors(
            [baseline_record()], calamari_text="Alfa prosa", raw_text="",
            calamari_occurrences=manifest,
            raw_occurrences=occurrence_manifest("raw_ocr", ""),
        )


def test_manifest_source_length_requires_an_exact_builtin_integer():
    manifest = occurrence_manifest("calamari", "x")
    manifest["source_length"] = True
    with pytest.raises(ValueError, match="source_length"):
        locate_baseline_anchors(
            [baseline_record(narrative="x")], calamari_text="x", raw_text="",
            calamari_occurrences=manifest,
            raw_occurrences=occurrence_manifest("raw_ocr", ""),
        )


def test_inputs_are_not_mutated():
    records = [baseline_record()]
    calamari_manifest = occurrence_manifest("calamari", "Alfa prosa")
    raw_manifest = occurrence_manifest("raw_ocr", "")
    before = copy.deepcopy((records, calamari_manifest, raw_manifest))
    locate_baseline_anchors(
        records, calamari_text="Alfa prosa", raw_text="",
        calamari_occurrences=calamari_manifest, raw_occurrences=raw_manifest,
    )
    assert (records, calamari_manifest, raw_manifest) == before
