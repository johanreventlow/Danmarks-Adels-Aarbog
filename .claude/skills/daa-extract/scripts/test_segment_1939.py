"""Tests for segment_1939.py — deterministisk narrative-segmentering (1939).

Alt testdata er SYNTETISK (opdigtede navne/datoer) — ingen PII.
"""

import segment_1939 as seg


# ---------------------------------------------------------------- helpers

def make_post(_id, window="window-01", gruppe=None, linje=None,
              foedsel=None, doed=None, begravelse=None, partnere=()):
    return {
        "_id": _id,
        "_window": window,
        "_ctx": {"linje": linje, "slaegtled": None, "gruppe": gruppe,
                 "foraeldre_note": None},
        "foedsel": {"date_raw": foedsel, "sted": None},
        "doed": {"date_raw": doed, "sted": None},
        "begravelse": {"date_raw": begravelse, "sted": None},
        "aegteskaber": [{"partner_navn": p} for p in partnere],
        "navn": f"Testperson {_id}",
    }


MINI_RAW = (
    "### PAGE 490 ###\n"
    "Aksel Aabing, f. 11. Jan. 1801 paa Testgaard,\n"
    "d. 2. Feb. 1860. Han var en flittig mand og\n"
    "byggede en vandmoelle.\n"
    "Berta Aabing, f. 12. Marts 1803, g. m.\n"
    "### PAGE 491 ###\n"
    "Carl Cediger, † 1877. Hun boede i Testkoebing\n"
    "til sin doed.\n"
    "Doris Aabing, om hvem intet vides.\n"
)

MINI_WINMAP = {"window-01": (490, 491)}


def run_mini(posts, raw=MINI_RAW, winmap=MINI_WINMAP):
    return seg.segment(posts, raw, winmap)


# ---------------------------------------------------------------- normalize

def test_normalize_removes_whitespace_and_lowercases():
    norm, idx = seg.normalize_with_map("Ab  C\nd")
    assert norm == "abcd"
    # index map points back to original positions
    assert [("Ab  C\nd")[i] for i in idx] == ["A", "b", "C", "d"]


def test_normalize_dagger_to_t():
    norm, _ = seg.normalize_with_map("† 1877")
    assert norm == "t1877"


def test_normalize_spaced_letters():
    # OCR-spatieret navn matcher kompakt form
    norm, _ = seg.normalize_with_map("T e s t n a v n")
    assert norm == "testnavn"


# ---------------------------------------------------------------- pages

def test_parse_pages_and_page_at():
    pages = seg.parse_pages(MINI_RAW)
    assert [p for _, p in pages] == [490, 491]
    lo, hi = seg.page_region(pages, len(MINI_RAW), 490, 490)
    assert MINI_RAW[lo:hi].startswith("### PAGE 490")
    assert "PAGE 491" not in MINI_RAW[lo + 1:hi]
    assert seg.page_at(pages, lo + 5) == 490
    assert seg.page_at(pages, len(MINI_RAW) - 1) == 491


# ---------------------------------------------------------------- anchor cut

def test_anchor_cut_between_two_posts():
    posts = [
        make_post(1, foedsel="11. Jan. 1801"),
        make_post(2, foedsel="12. Marts 1803"),
    ]
    out = run_mini(posts)
    assert out["1"]["metode"] == "anker"
    assert out["2"]["metode"] == "anker"
    # post 1 faar sin egen prosa, snit ved post 2's ankerlinje
    assert "11. Jan. 1801" in out["1"]["narrative"]
    assert "vandmoelle" in out["1"]["narrative"]
    assert "12. Marts 1803" not in out["1"]["narrative"]
    assert "12. Marts 1803" in out["2"]["narrative"]
    assert out["1"]["side"] == 490


def test_anchor_fallback_to_doed_and_partner():
    posts = [
        make_post(1, doed="2. Feb. 1860"),                # doed som anker
        make_post(2, partnere=("Carl Cediger",)),          # partner som anker
    ]
    out = run_mini(posts)
    assert out["1"]["metode"] == "anker"
    assert out["2"]["metode"] == "anker"
    assert "Carl Cediger" in out["2"]["narrative"]


def test_ambiguous_anchor_not_used():
    raw = (
        "### PAGE 490 ###\n"
        "Aksel Aabing, f. 1801.\n"
        "Berta Aabing, f. 1801.\n"
    )
    posts = [make_post(1, foedsel="1801", gruppe="g1")]
    out = seg.segment(posts, raw, {"window-01": (490, 490)})
    # "1801" findes to gange i vinduet -> ikke unikt -> fallback
    assert out["1"]["metode"] != "anker"
    assert out["1"]["narrative"]  # men aldrig tom


def test_dagger_anchor_matches_ocr_dagger():
    posts = [make_post(1, doed="† 1877")]
    out = run_mini(posts)
    assert out["1"]["metode"] == "anker"
    assert "1877" in out["1"]["narrative"]


# ---------------------------------------------------------------- fallbacks

def test_gruppe_fallback_for_anchorless_post():
    posts = [
        make_post(1, gruppe="g1", foedsel="11. Jan. 1801"),
        make_post(2, gruppe="g1", foedsel="12. Marts 1803"),
        make_post(3, gruppe="g1"),  # ingen ankre
    ]
    out = run_mini(posts)
    assert out["3"]["metode"] == "gruppe-fallback"
    # gruppens samlede blok: spaender over begge ankrede medlemmer
    assert "11. Jan. 1801" in out["3"]["narrative"]
    assert "12. Marts 1803" in out["3"]["narrative"]


def test_vindue_fallback_when_no_gruppe_anchor():
    posts = [make_post(1)]  # ingen ankre, ingen gruppe
    out = run_mini(posts)
    assert out["1"]["metode"] == "vindue-fallback"
    assert "Aksel Aabing" in out["1"]["narrative"]
    assert "Doris Aabing" in out["1"]["narrative"]


def test_every_post_gets_nonempty_narrative():
    posts = [
        make_post(1, gruppe="g1", foedsel="11. Jan. 1801"),
        make_post(2, gruppe="g1"),
        make_post(3),
        make_post(4, foedsel="99. Foo 9999"),  # anker findes ikke i raw
    ]
    out = run_mini(posts)
    assert set(out) == {"1", "2", "3", "4"}
    for v in out.values():
        assert v["narrative"].strip()
        assert isinstance(v["side"], int)
        assert v["metode"] in ("anker", "gruppe-fallback", "vindue-fallback")


def test_duplicate_anchor_position_second_becomes_fallback():
    posts = [
        make_post(1, foedsel="11. Jan. 1801"),
        make_post(2, foedsel="11. Jan. 1801"),  # samme anker -> kollision
    ]
    out = run_mini(posts)
    metoder = sorted(v["metode"] for v in out.values())
    assert metoder.count("anker") == 1


def test_suspiciously_short_anchor_slice_demoted_to_fallback():
    raw = (
        "### PAGE 490 ###\n"
        "Aa, f. 1.1.1801.\n"
        "Bb, f. 2.2.1802, som levede laenge og fik mange boern\n"
        "og en gaard og en moelle.\n"
    )
    posts = [
        make_post(1, foedsel="1.1.1801"),
        make_post(2, foedsel="2.2.1802"),
    ]
    out = seg.segment(posts, raw, {"window-01": (490, 490)})
    # post 1's anker-snit er < 20 tegn -> fail-safe: demoteres til fallback
    assert out["1"]["metode"] == "vindue-fallback"
    assert len(out["1"]["narrative"]) >= 20
    assert out["2"]["metode"] == "anker"


# ---------------------------------------------------------------- output

def test_page_markers_stripped_from_narrative():
    posts = [make_post(1, foedsel="12. Marts 1803")]
    out = run_mini(posts)
    # post 1's narrative krydser side-skiftet 490->491
    assert "### PAGE" not in out["1"]["narrative"]
    assert "Carl Cediger" in out["1"]["narrative"]


def test_side_is_page_of_narrative_start():
    posts = [
        make_post(1, foedsel="11. Jan. 1801"),
        make_post(2, doed="† 1877"),
    ]
    out = run_mini(posts)
    assert out["1"]["side"] == 490
    assert out["2"]["side"] == 491


def test_narrative_verbatim_no_paraphrase():
    posts = [make_post(1, foedsel="11. Jan. 1801"),
             make_post(2, foedsel="12. Marts 1803")]
    out = run_mini(posts)
    # ordret substring af raw (ingen omskrivning)
    assert out["1"]["narrative"] in MINI_RAW


def test_narrative_capped_at_window_region():
    raw = (
        "### PAGE 490 ###\n"
        "Aksel Aabing, f. 11. Jan. 1801.\n"
        "### PAGE 491 ###\n"
        "Andet stof uden ankre her.\n"
    )
    posts = [make_post(1, window="window-01", foedsel="11. Jan. 1801")]
    out = seg.segment(posts, raw, {"window-01": (490, 490)})
    # sidste ankrede post i sit vindue: cappes ved vinduets side-region
    assert "Andet stof" not in out["1"]["narrative"]
