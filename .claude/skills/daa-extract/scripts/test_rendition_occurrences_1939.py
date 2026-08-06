import copy
import hashlib

import pytest
import segment

from rendition_occurrences_1939 import (
    CALAMARI_R6_TO_PDF_V1,
    _canonical_occurrence_signature,
    extract_rendition_occurrences,
)


def test_extracts_exact_source_only_occurrences():
    text = "### PAGE 1 ###\nI. Første Slægtled\n1. Alfa\nfortsat\n2. Beta\n"
    result = extract_rendition_occurrences(
        text, rendition="calamari", page_map=CALAMARI_R6_TO_PDF_V1
    )
    assert result["source_sha256"] == hashlib.sha256(text.encode()).hexdigest()
    assert [o["printed_marker"] for o in result["occurrences"]] == ["1", "2"]
    assert all("record_key" not in o for o in result["occurrences"])
    for occurrence in result["occurrences"]:
        span = occurrence["span"]
        exact = text[span["char_from"]:span["char_to"]]
        assert hashlib.sha256(exact.encode()).hexdigest() == occurrence["verbatim_sha256"]


def test_occurrence_ends_before_next_record_marker():
    text = "### PAGE 1 ###\n1. Volrad\nprosa\n2. Emeke\n"
    result = extract_rendition_occurrences(
        text, rendition="raw_ocr", page_map=None
    )
    first, second = result["occurrences"]
    assert first["span"]["char_to"] <= second["span"]["char_from"]
    assert "Emeke" not in text[first["span"]["char_from"]:first["span"]["char_to"]]


@pytest.mark.parametrize("rendition", ["calamari", "raw_ocr"])
def test_output_is_deterministic_and_input_is_not_mutated(rendition):
    text = "### PAGE 1 ###\n1. Alfa\n2. Beta\n"
    before = text
    first = extract_rendition_occurrences(
        text, rendition=rendition,
        page_map=CALAMARI_R6_TO_PDF_V1 if rendition == "calamari" else None,
    )
    second = extract_rendition_occurrences(
        text, rendition=rendition,
        page_map=CALAMARI_R6_TO_PDF_V1 if rendition == "calamari" else None,
    )
    assert first == second
    assert text == before


@pytest.mark.parametrize("bad_map", [True, [(1, 496)], ((5, 500), (1, 496))])
def test_calamari_page_map_requires_exact_ordered_tuple(bad_map):
    with pytest.raises(ValueError, match="page_map"):
        extract_rendition_occurrences(
            "1. Alfa\n", rendition="calamari", page_map=bad_map
        )


def test_repeated_printed_numbers_remain_distinct_occurrences():
    result = extract_rendition_occurrences(
        "1. Alfa\nI.\n1. Beta\n", rendition="raw_ocr", page_map=None
    )
    ones = [o for o in result["occurrences"] if o["printed_marker"] == "1"]
    assert len(ones) == 2
    assert len({o["occurrence_id"] for o in ones}) == 2


def test_pinned_calamari_map_uses_the_nonlinear_page_points():
    result = extract_rendition_occurrences(
        "### PAGE 58 ###\n1. Alfa\n### PAGE 63 ###\nfortsat\n",
        rendition="calamari",
        page_map=CALAMARI_R6_TO_PDF_V1,
    )
    assert result["page_mapping_id"] == "calamari-r6-to-pdf-v1"
    assert result["occurrences"][0]["pdf_pages"] == [555, 575]


def test_pinned_calamari_map_rounds_half_pages_up_deterministically():
    result = extract_rendition_occurrences(
        "### PAGE 84 ###\n1. Alfa\n",
        rendition="calamari",
        page_map=CALAMARI_R6_TO_PDF_V1,
    )
    assert result["occurrences"][0]["pdf_pages"] == [597]


def test_calamari_rejects_changed_but_ordered_pinned_map():
    with pytest.raises(ValueError, match="page_map"):
        extract_rendition_occurrences(
            "1. Alfa\n",
            rendition="calamari",
            page_map=((1, 496), (5, 501)),
        )


@pytest.mark.parametrize("corruption", ["gap", "overlap", "verbatim"])
def test_rejects_corrupted_ledger_clauses(monkeypatch, corruption):
    text = "1. Alfa\n2. Beta\n"
    ledger = copy.deepcopy(segment._evidence_ledger(text))
    if corruption == "gap":
        ledger["clauses"][1]["span"]["char_from"] += 1
    elif corruption == "overlap":
        ledger["clauses"][1]["span"]["char_from"] -= 1
    else:
        ledger["clauses"][0]["verbatim_text"] = "forfalsket\n"
    monkeypatch.setattr(segment, "_evidence_ledger", lambda _source: ledger)
    with pytest.raises(ValueError):
        extract_rendition_occurrences(text, rendition="raw_ocr", page_map=None)


def test_layout_page_marker_inside_occurrence_is_exact_and_reports_both_pages():
    text = "### PAGE 1 ###\n1. Alfa\n### PAGE 2 ###\nfortsat\n"
    result = extract_rendition_occurrences(
        text, rendition="calamari", page_map=CALAMARI_R6_TO_PDF_V1
    )
    occurrence = result["occurrences"][0]
    exact = text[occurrence["span"]["char_from"]:occurrence["span"]["char_to"]]
    assert "### PAGE 2 ###" in exact
    assert occurrence["pdf_pages"] == [496, 497]


def test_occurrence_inherits_preceding_calamari_page_marker():
    result = extract_rendition_occurrences(
        "### PAGE 1 ###\n1. Alfa\n2. Beta\n",
        rendition="calamari", page_map=CALAMARI_R6_TO_PDF_V1,
    )
    assert [occurrence["pdf_pages"] for occurrence in result["occurrences"]] == [[496], [496]]


def test_occurrence_inherits_only_nearest_preceding_calamari_page_marker():
    result = extract_rendition_occurrences(
        "### PAGE 1 ###\n1. Alfa\n### PAGE 2 ###\n2. Beta\n3. Gamma\n",
        rendition="calamari", page_map=CALAMARI_R6_TO_PDF_V1,
    )
    assert result["occurrences"][2]["pdf_pages"] == [497]


def test_leading_unclassified_prose_remains_an_unmarked_occurrence():
    result = extract_rendition_occurrences(
        "Indledende prosa uden trykt post.\n1. Alfa\n",
        rendition="raw_ocr", page_map=None,
    )
    assert [o["printed_marker"] for o in result["occurrences"]] == [None, "1"]


def test_structural_only_source_remains_an_unmarked_exact_occurrence():
    text = "I.\n"
    result = extract_rendition_occurrences(text, rendition="raw_ocr", page_map=None)
    occurrence = result["occurrences"][0]
    assert occurrence["printed_marker"] is None
    assert occurrence["span"] == {"char_from": 0, "char_to": len(text)}


def test_neighbor_signatures_are_the_canonical_digest_of_actual_neighbors():
    result = extract_rendition_occurrences(
        "1. Alfa\n2. Beta\n3. Gamma\n", rendition="raw_ocr", page_map=None
    )
    first, second, third = result["occurrences"]
    assert first["predecessor_signature"] is None
    assert first["successor_signature"] == _canonical_occurrence_signature(second)
    assert second["predecessor_signature"] == _canonical_occurrence_signature(first)
    assert second["successor_signature"] == _canonical_occurrence_signature(third)
    assert third["predecessor_signature"] == _canonical_occurrence_signature(second)
    assert third["successor_signature"] is None
