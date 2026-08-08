import pytest

from boundary_signals_1939 import SignalError, classify_gap, may_bulk_confirm


def clause(char_from, char_to, classification):
    return {"char_from": char_from, "char_to": char_to,
            "classification": classification}


CLAUSES = [
    clause(0, 20, "record_text"),
    clause(20, 40, "structural_header"),
    clause(40, 45, "layout"),
    clause(45, 70, "record_text"),
]


def test_a_gap_of_only_heading_and_layout_has_no_prose():
    summary = classify_gap(CLAUSES, {"char_from": 20, "char_to": 45})

    assert summary["har_broedtekst"] is False
    assert summary["klasser"]["structural_header"] == 1
    assert summary["klasser"]["layout"] == 1
    assert summary["tegn"] == 25


def test_a_gap_touching_prose_reports_it():
    summary = classify_gap(CLAUSES, {"char_from": 30, "char_to": 50})

    assert summary["har_broedtekst"] is True
    assert summary["klasser"]["record_text"] == 1


def test_an_empty_gap_has_no_clauses_and_no_prose():
    summary = classify_gap(CLAUSES, {"char_from": 40, "char_to": 40})

    assert summary["tegn"] == 0
    assert summary["har_broedtekst"] is False
    assert summary["klasser"] == {"record_text": 0, "structural_header": 0,
                                  "layout": 0, "noise": 0}


def test_an_unknown_classification_fails_closed():
    with pytest.raises(SignalError, match="klassifikation"):
        classify_gap([clause(0, 10, "opfundet")], {"char_from": 0, "char_to": 10})


def test_a_reversed_gap_fails_closed():
    with pytest.raises(SignalError, match="hul"):
        classify_gap(CLAUSES, {"char_from": 40, "char_to": 20})


CLEAN_SUMMARY = {"tegn": 30, "klasser": {"record_text": 0, "structural_header": 1,
                                         "layout": 1, "noise": 0},
                 "har_broedtekst": False}


def test_a_heading_only_gap_may_be_bulk_confirmed():
    assert may_bulk_confirm("Sjette Slægtled\n", "Sjette Slægtled\n", CLEAN_SUMMARY) is True


def test_prose_in_the_gap_blocks_bulk_confirmation():
    summary = {**CLEAN_SUMMARY, "har_broedtekst": True}

    assert may_bulk_confirm("noget prosa\n", "noget prosa\n", summary) is False


def test_a_printed_head_in_calamari_blocks_bulk_confirmation():
    assert may_bulk_confirm("7. Heinrich til Gottesgabe\n", "", CLEAN_SUMMARY) is False


def test_a_printed_head_only_in_raw_ocr_still_blocks_bulk_confirmation():
    """Netop den fejl der skabte problemet: Calamari tabte hovedet, rå OCR har det."""
    assert may_bulk_confirm(
        "7 Heinrich til Gottesgabe\n", "7. H e i n r i c h til Gottesgabe\n", CLEAN_SUMMARY,
    ) is False


def test_an_empty_gap_may_be_bulk_confirmed():
    empty = {"tegn": 0, "klasser": dict.fromkeys(
        ("record_text", "structural_header", "layout", "noise"), 0),
        "har_broedtekst": False}

    assert may_bulk_confirm("", "", empty) is True
