import copy
import hashlib

import pytest

from dual_rendition_evidence_1939 import locate_baseline_anchors


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
