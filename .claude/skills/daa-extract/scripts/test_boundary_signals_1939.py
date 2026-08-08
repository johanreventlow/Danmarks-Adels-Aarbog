import pytest

from boundary_signals_1939 import SignalError, classify_gap, may_bulk_confirm, span_signals


def record(navn, orig_nr, gruppe=1, char_from=None):
    entry = {"navn": navn, "_orig_nr": orig_nr, "_gruppe_nr": gruppe,
             "_v2_lokal_id": f"III.Sjette.III.{orig_nr}"}
    if char_from is not None:
        entry["char_from"] = char_from
    return entry


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


def test_an_uncovered_character_in_a_nonempty_gap_fails_closed():
    with pytest.raises(SignalError, match="dækker ikke hele hullet"):
        classify_gap(
            [clause(20, 30, "structural_header"), clause(31, 45, "layout")],
            {"char_from": 20, "char_to": 45},
        )


def test_a_reversed_clause_fails_closed():
    with pytest.raises(SignalError, match="ugyldige positioner"):
        classify_gap([clause(45, 20, "layout")], {"char_from": 20, "char_to": 45})


def test_a_clause_without_coordinates_fails_closed():
    with pytest.raises(SignalError, match="ugyldige positioner"):
        classify_gap([{"classification": "layout"}], {"char_from": 20, "char_to": 45})


def test_missing_clauses_fail_closed():
    with pytest.raises(SignalError, match="klausuler"):
        classify_gap(None, {"char_from": 20, "char_to": 45})


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


def test_integer_prose_signal_is_rejected():
    with pytest.raises(SignalError, match="har_broedtekst"):
        may_bulk_confirm("", "", {**CLEAN_SUMMARY, "har_broedtekst": 0})


def test_summary_without_classes_is_rejected():
    with pytest.raises(SignalError, match="klasser"):
        may_bulk_confirm("", "", {"tegn": 0, "har_broedtekst": False})


def test_summary_with_wrong_class_keys_is_rejected():
    with pytest.raises(SignalError, match="klasser"):
        may_bulk_confirm(
            "", "", {"tegn": 0, "klasser": {"layout": 0}, "har_broedtekst": False},
        )


def test_a_span_opening_with_its_own_printed_head_has_no_signal():
    own = record("Christine Augusta", 6, char_from=0)

    signals = span_signals({"char_from": 0, "char_to": 400}, own,
                           "6. Christine Augusta; g. 1708 i Königsberg.", [own])

    assert signals == []


def test_a_headless_span_is_flagged():
    own = record("Heinrich", 7, char_from=0)

    signals = span_signals({"char_from": 0, "char_to": 200}, own,
                           "Prins Georgs Reg., 1703 Sek.major.", [own])

    assert "mangler_eget_hoved" in signals


def test_a_span_carrying_a_later_siblings_head_is_flagged():
    own = record("Christine Augusta", 6, char_from=0)
    later = record("Heinrich", 7, char_from=400)

    signals = span_signals(
        {"char_from": 0, "char_to": 400}, own,
        "6. Christine Augusta; g. 1708.\n7 Heinrich til Gottesgabe", [own, later],
    )

    assert "slugt_hoved" in signals


def test_a_date_continuation_is_not_a_swallowed_head():
    own = record("Ditlev Christian Ernst", 24, char_from=0)
    sibling = record("Margrethe", 23, char_from=400)

    signals = span_signals(
        {"char_from": 0, "char_to": 400}, own,
        "24. Ditlev Christian Ernst, f. 12 Juni 1712, bgr.\n23 s. M. i Kiel.",
        [own, sibling],
    )

    assert "slugt_hoved" not in signals


def test_siblings_out_of_printed_order_give_a_number_skip():
    own = record("Heino", 5, char_from=900)
    earlier = record("David", 6, char_from=100)

    signals = span_signals({"char_from": 900, "char_to": 1000}, own,
                           "5. Heino til Lelkendorf.", [own, earlier])

    assert "nummerspring" in signals


def test_a_span_far_shorter_than_its_siblings_is_flagged_for_sorting_only():
    own = record("Kort", 3, char_from=0)
    siblings = [own, record("Lang", 4, char_from=100), record("Lang", 5, char_from=900)]

    signals = span_signals({"char_from": 0, "char_to": 20}, own, "3. Kort.", siblings,
                           sibling_lengths=[800, 820])

    assert signals == ["laengdeafvigelse"]
