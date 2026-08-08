import json

import pytest

from detect_boundary_defects_1939 import (
    BoundaryDefectError,
    find_boundary_defects,
    fold_ocr,
    suggested_reason,
    write_report,
)


def record(*, key, navn, orig_nr, narrative, gruppe=1, sider="535", lokal_id=None):
    return {
        "record_key": key,
        "navn": navn,
        "narrative": narrative,
        "_orig_nr": orig_nr,
        "_gruppe_nr": gruppe,
        "sider": sider,
        "_v2_lokal_id": lokal_id or f"III.Sjette.III.{orig_nr}",
    }


def test_fold_ocr_normalises_letterspacing_and_confusable_glyphs():
    assert fold_ocr("H e n r i c h") == "henrich"
    assert fold_ocr("E 1 s e b e") == "elsebe"
    assert fold_ocr("S i g î r e d") == "sigfred"
    assert fold_ocr("Q o t s k a l k") == "gotskalk"


def test_finds_the_boundary_pair_when_a_head_is_swallowed_by_its_predecessor():
    swallower = record(
        key="rk-6", navn="Christine Augusta", orig_nr=6,
        narrative="6. Christine Augusta; g. 1708 i Königsberg.\n"
                  "7 Heinrich til Gottesgabe, 1697 Fændrik ved Livgarden",
    )
    orphan = record(
        key="rk-7", navn="Heinrich", orig_nr=7,
        narrative="Prins Georgs Reg., 1703 Sek.major, 1705 afsk.",
    )

    report = find_boundary_defects([swallower, orphan])

    assert report["summary"] == {
        "poster": 2, "graensefejl_par": 1, "slugt_hoved": 0, "mangler_eget_hoved": 0,
    }
    pair = report["graensefejl_par"][0]
    assert pair["swallower"]["record_key"] == "rk-6"
    assert pair["orphan"]["record_key"] == "rk-7"
    assert pair["orphan"]["_orig_nr"] == 7
    assert pair["swallowed_head"].startswith("7 Heinrich")
    assert pair["gruppe_nr"] == 1


def test_letterspaced_own_head_is_not_reported_as_missing():
    clean = record(
        key="rk-2", navn="Henrich", orig_nr=2, narrative="H e n r i c h + ung.",
    )
    ocr_mangled = record(
        key="rk-3", navn="Elsebe", orig_nr=3,
        narrative="E 1 s e b e, g. m. Henning Brockdorff.",
    )

    report = find_boundary_defects([clean, ocr_mangled])

    assert report["summary"]["mangler_eget_hoved"] == 0
    assert report["mangler_eget_hoved"] == []


def test_printed_rank_before_the_name_is_not_a_missing_head():
    titled = record(key="rk-6", navn="Wilhelmine Juliane", orig_nr=6,
                    narrative="6. Comtesse Wilhelmine Juliane, f. 30 Juni 1762.")
    doubled = record(key="rk-4", navn="Christian Detlev Ludvig", orig_nr=4,
                     narrative="4. Greve Christian Detlev Ludvig Sophus, f. 1848.")

    report = find_boundary_defects([titled, doubled])

    assert report["mangler_eget_hoved"] == []


@pytest.mark.parametrize("navn,orig_nr,narrative", [
    ("Wilhelmine Juliane", 6, "6. Comtesse ilhelmine Juliane, f. 30 Juni 1762."),
    ("Nancy Ida", 1, "1. Comtesse MWancy Ida, f. 20 Febr. 1901."),
    ("Theodor Carl Ludwig Detlev", 2, "2. Greve Teodor Carl Ludwg Detlev, f. 1868."),
    ("Ditlev Christian", 1, "Ditlev Christian, f. o. 1720; imm. 1739."),
])
def test_garbled_initials_in_the_printed_head_are_not_missing_heads(navn, orig_nr, narrative):
    report = find_boundary_defects([record(key="rk-1", navn=navn, orig_nr=orig_nr,
                                          narrative=narrative)])

    assert report["mangler_eget_hoved"] == []


def test_a_foreign_printed_head_at_the_opening_is_still_flagged():
    """A record opening with another sibling's number is a real defect."""
    intruded = record(key="rk-2", navn="Christian Albrecht", orig_nr=2,
                      narrative="1. Magdalene Sophie, f. 1745 i Randers.")

    report = find_boundary_defects([intruded])

    assert [entry["record_key"] for entry in report["mangler_eget_hoved"]] == ["rk-2"]


def test_mid_sentence_opening_is_still_flagged_after_rank_stripping():
    orphan = record(key="rk-5", navn="Otto", orig_nr=5,
                    narrative="med Svaghed † 27 Marts 1618. Gift 1581 m. Anna.")

    report = find_boundary_defects([orphan])

    assert [entry["record_key"] for entry in report["mangler_eget_hoved"]] == ["rk-5"]


def test_date_continuation_is_not_mistaken_for_a_swallowed_head():
    sibling = record(key="rk-23", navn="Margrethe", orig_nr=23,
                     narrative="23. Margrethe, f. 1700.")
    dated = record(
        key="rk-24", navn="Ditlev Christian Ernst", orig_nr=24,
        narrative="24. Ditlev Christian Ernst, f. 12 Juni 1712, bgr.\n"
                  "23 s. M. i Kiel, 1740 Kammerherre.",
    )

    report = find_boundary_defects([sibling, dated])

    assert report["summary"]["slugt_hoved"] == 0
    assert report["summary"]["graensefejl_par"] == 0


def test_number_from_another_sibling_group_is_ignored():
    outside = record(key="rk-a", navn="Heinrich", orig_nr=7, gruppe=99,
                     narrative="Prins Georgs Reg., 1703 Sek.major.")
    inside = record(
        key="rk-b", navn="Christine Augusta", orig_nr=6, gruppe=1,
        narrative="6. Christine Augusta; g. 1708.\n7 Heinrich til Gottesgabe",
    )

    report = find_boundary_defects([outside, inside])

    assert report["summary"]["graensefejl_par"] == 0
    assert report["summary"]["slugt_hoved"] == 0


def test_orphan_without_a_swallowing_predecessor_is_reported_alone():
    orphan = record(key="rk-9", navn="Bertram", orig_nr=9,
                    narrative="var 1681 Testamentsvidne paa Lindved.")

    report = find_boundary_defects([orphan])

    assert report["summary"]["mangler_eget_hoved"] == 1
    assert report["mangler_eget_hoved"][0]["record_key"] == "rk-9"
    assert report["graensefejl_par"] == []


def test_unnumbered_record_is_counted_but_never_flagged_on_numbering():
    unnumbered = record(key="rk-u", navn="Gotskalk af Reventlow", orig_nr=None,
                        narrative="nævnes 1223 som Vidne.", lokal_id="Stamme.I.U1")

    report = find_boundary_defects([unnumbered])

    assert report["summary"] == {
        "poster": 1, "graensefejl_par": 0, "slugt_hoved": 0, "mangler_eget_hoved": 0,
    }


def test_suggested_reason_carries_the_greppable_prefix_and_both_numbers():
    swallower = record(
        key="rk-6", navn="Christine Augusta", orig_nr=6,
        narrative="6. Christine Augusta; g. 1708.\n7 Heinrich til Gottesgabe",
    )
    orphan = record(key="rk-7", navn="Heinrich", orig_nr=7,
                    narrative="Prins Georgs Reg., 1703 Sek.major.")
    pair = find_boundary_defects([swallower, orphan])["graensefejl_par"][0]

    reason = suggested_reason(pair)

    assert reason.startswith("GRÆNSEFEJL: ")
    assert "nr. 6" in reason and "nr. 7" in reason
    assert "Christine Augusta" in reason and "Heinrich" in reason


def test_report_is_written_without_overwriting_an_existing_file(tmp_path):
    out = tmp_path / "rapport.json"
    report = find_boundary_defects([record(key="rk-1", navn="Ditlev", orig_nr=1,
                                          narrative="1. Ditlev til Holtenklinken.")])

    write_report(report, out)

    assert json.loads(out.read_text(encoding="utf-8"))["summary"]["poster"] == 1
    with pytest.raises(FileExistsError):
        write_report(report, out)


@pytest.mark.parametrize("baseline", ["ikke en liste", [None], [{"navn": "uden nøgle"}]])
def test_malformed_baseline_fails_closed(baseline):
    with pytest.raises(BoundaryDefectError):
        find_boundary_defects(baseline)
