import pytest

from boundary_signals_1939 import SignalError, classify_gap


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
