"""Tests for 1939-segmentering og deterministisk narrativbinding.

De små fixtures bruger korte typografiske OCR-ankre. To v2-integrationstests
kører mod repoets faktiske ``raw.txt``-fallback for regressionsbeviset.
"""

import segment_1939 as seg
import contextlib
import io
import os
import json
import subprocess
import sys
import tempfile

import segment as structural_segment


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


def run_structural(text, udgave):
    """Kør struktursegmenteringen på en kort OCR-fixture."""
    with tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8") as handle:
        handle.write(text)
        path = handle.name
    try:
        stderr = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            posts = structural_segment.main(path, udgave=udgave)
        return posts, stderr.getvalue()
    finally:
        os.unlink(path)


def run_structural_path(path, udgave):
    stderr = io.StringIO()
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
        posts = structural_segment.main(str(path), udgave=udgave)
    return posts, stderr.getvalue()


# ------------------------------------------------------ v2 unnumbered records

def test_v2_udskiller_stamfader_efter_centreret_slaegtledsanker():
    # Faktisk typografisk anker: "F ø rste S læ gtled ." efterfølges af en
    # udbredt personlinje uden trykt nummer; næste slægtled lukker posten.
    raw = "\n".join([
        "                    IL",
        "Linjen Gallentin.",
        "                  (S. 21).",
        "                     F ø rste S læ gtled .",
        "  T e s t A n e til Prøvested, nævnes 1393. — Søn:",
        "                     A ndet S læ gtled .",
        "1. T e s t B o er en nummereret post.",
    ])

    posts, _ = run_structural(raw, "1939-v2")
    unummererede = [post for post in posts if post.get("postklasse")]

    assert len(unummererede) == 1
    assert unummererede[0]["postklasse"] == "stamfader"
    assert unummererede[0]["lokal_id"] == "II.Første.U1"
    assert unummererede[0]["raw_text"] == (
        "T e s t A n e til Prøvested, nævnes 1393. — Søn:")
    assert unummererede[0]["dublet_af_stamtavle"] is False


def test_v2_udskiller_faellesstammens_sektionsstamfader():
    # Faktiske ankre før hovedlinjerne: "Den holstenske Linje." og et
    # centreret romertal bærer adressen; selve personen er unummereret.
    raw = "\n".join([
        "                                A.",
        "          Den holstenske Linje.",
        "                                    i.",
        "   T e s t A n e af Prøvested, nævnes 1223. — Sønner:",
        " 1. T e s t B o er nummereret.",
    ])

    posts, _ = run_structural(raw, "1939-v2")
    unummererede = [post for post in posts if post.get("postklasse")]

    assert len(unummererede) == 1
    assert unummererede[0]["lokal_id"] == "Stamme-holstenske.I.U1"


def test_v2_normaliserer_centreret_ocr_1_til_romertal_i_i_stammefasen():
    # Faktisk OCR-anker ved den ældre meklenborgske rod: centreret "1." er
    # bogens romertal I; reparationen gælder kun før hovedlinjerne.
    raw = "\n".join([
        "                                B.",
        "          Den ældre meklenborgske Linje.",
        "                                1.",
        "   T e s t A n e er den unummererede rod. — Sønner:",
        "                                II.",
        " 1. T e s t B o er nummereret.",
    ])

    posts, _ = run_structural(raw, "1939-v2")
    unummererede = [post for post in posts if post.get("postklasse")]

    assert [post["lokal_id"] for post in unummererede] == [
        "Stamme-ældre-meklenborgske.I.U1"]


def test_v2_bruger_faellesstammens_romertal_bogstav_som_adresse():
    # Faktisk typografisk anker: "VII C." efterfølges af én unummereret
    # enkeltbarnspost og bærer derfor et stabilt, trykt strukturslot.
    raw = "\n".join([
        "                                A.",
        "          Den holstenske Linje.",
        "                            VII B.",
        " 1. T e s t B o er en nummereret post.",
        "    fortsættelse med Efterslægt: Stamrække I.",
        "                            VII C.",
        "                  Lyder Reventlows Søn:",
        "   Dr. T e s t A n e er en unummereret enkeltbarnspost.",
    ])

    posts, _ = run_structural(raw, "1939-v2")
    unummererede = [post for post in posts if post.get("postklasse")]

    assert [post["lokal_id"] for post in unummererede] == [
        "Stamme-holstenske.VIIC.U1"]


def test_v2_markerer_indledningsoversigt_som_dubletklasse():
    # Faktisk typografisk anker: "Fra ovennævnte" indleder den kompakte,
    # hierarkiske oversigt, der tidligere gav Cay Friedrich-dubletten.
    raw = "\n".join([
        "    Fra ovennævnte J O A C H I M R E V E N T L O W nedstammer Linjen.",
        "    Joachim havde Sønnerne:",
        "   I. T e s t A n e til Prøvested.",
        " II. T e s t B o til Andetsted.",
        "                                B.",
        "          Den ældre meklenborgske Linje.",
        "  T e s t C a r l er sektionsprosa, ikke del af oversigten.",
        "                    I",
        "Den holstenske Linje.",
        "                  (S. 14).",
    ])

    posts, _ = run_structural(raw, "1939-v2")
    oversigt = [post for post in posts if post.get("postklasse") == "oversigtspost"]

    assert [post["lokal_id"] for post in oversigt] == [
        "Oversigt.Indledning.U1", "Oversigt.Indledning.U2"]
    assert all(post["dublet_af_stamtavle"] is True for post in oversigt)


def test_v2_udskiller_slutoversigt_uden_dubletgaet():
    # Faktisk typografisk anker: "Personer af Navnet Reventlow, der ikke kan
    # anvises Plads". Udbredte navnelinjer er poster indtil næste navnelinje.
    raw = "\n".join([
        "Personer af Navnet Reventlow, der ikke kan anvises Plads",
        "                  paa Slægtstavlerne:",
        "    T e s t A n e , nævnes 1350 som vidne.",
        "fortsat kort kildeprosa.",
        "    T e s t B o , nævnes 1366 som vidne.",
    ])

    posts, _ = run_structural(raw, "1939-v2")
    oversigt = [post for post in posts if post.get("postklasse") == "oversigtspost"]

    assert [post["lokal_id"] for post in oversigt] == [
        "Oversigt.Uplacerede.U1", "Oversigt.Uplacerede.U2"]
    assert "fortsat kort kildeprosa" in oversigt[0]["raw_text"]
    assert all(post["dublet_af_stamtavle"] is False for post in oversigt)


def test_v2_fail_closed_rapporterer_navnelignende_linje_uden_strukturanker():
    raw = "T v e t y d i g T e k s t kunne ligne en person, men mangler kontekst."

    posts, rapport = run_structural(raw, "1939-v2")

    assert posts == []
    assert "tvetydige unummererede kandidater: 1" in rapport
    assert "linje 1:" in rapport
    assert "T v e t y d i g" in rapport


def test_v2_bevarer_alle_v1_nummererede_poster_post_for_post():
    raw = "\n".join([
        "                    IV.",
        "Den danske grevelige Linje af 1673.",
        "                  (S. 43).",
        "                     F ø rste S læ gtled .",
        "  T e s t A n e er en unummereret stamfader.",
        "                     A ndet S læ gtled .",
        "1. T e s t B o har første nummererede narrativ.",
        "2. T e s t C a r l har andet nummererede narrativ.",
    ])

    v1, _ = run_structural(raw, "1939")
    v2, _ = run_structural(raw, "1939-v2")
    v2_nummererede = [post for post in v2 if not post.get("postklasse")]

    assert v2_nummererede == v1


def test_v2_lokal_ids_er_unikke_og_output_deterministisk():
    raw = "\n".join([
        "                    IL",
        "Linjen Gallentin.",
        "                     F ø rste S læ gtled .",
        "  T e s t A n e er stamfader.",
        "                     A ndet S læ gtled .",
        " T e s t B o er næste stamfader.",
        "                     T red je S læ gtled .",
        "1. T e s t C a r l er nummereret.",
    ])

    foerste, _ = run_structural(raw, "1939-v2")
    anden, _ = run_structural(raw, "1939-v2")

    assert foerste == anden
    assert len({post["lokal_id"] for post in foerste}) == len(foerste)


def test_v2_kan_vaelges_fra_kommandolinjen():
    raw = "\n".join([
        "                    I",
        "Den holstenske Linje.",
        "                     F ø rste S læ gtled .",
        "  T e s t A n e er stamfader.",
    ])
    with tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8") as handle:
        handle.write(raw)
        path = handle.name
    try:
        result = subprocess.run(
            [sys.executable, structural_segment.__file__, path,
             "--udgave", "1939-v2"],
            capture_output=True, text=True, check=False)
    finally:
        os.unlink(path)

    assert result.returncode == 0
    assert json.loads(result.stdout)[0]["lokal_id"] == "I.Første.U1"


def test_v2_faktisk_ocr_bevarer_v1_nummererede_byte_for_byte():
    # full_ocr_calamari_r6_clean.txt har ikke den centreringsinformation, som
    # den nuværende 1939-v1 er kalibreret imod; raw.txt er dens dokumenterede
    # fallback og det live regressionsgrundlag.
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../.."))
    ocr = os.path.join(repo, "work_1939_stamtavle", "raw.txt")

    v1, _ = run_structural_path(ocr, "1939")
    v2, _ = run_structural_path(ocr, "1939-v2")
    v2_nummererede = [post for post in v2 if not post.get("postklasse")]

    assert len(v1) == 505  # live parserfacit på denne branch
    assert v2_nummererede == v1
    assert (json.dumps(v2_nummererede, ensure_ascii=False, indent=2).encode("utf-8")
            == json.dumps(v1, ensure_ascii=False, indent=2).encode("utf-8"))


def test_v2_faktisk_ocr_taelling_unikhed_fail_closed_og_determinisme():
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../.."))
    ocr = os.path.join(repo, "work_1939_stamtavle", "raw.txt")

    foerste, rapport = run_structural_path(ocr, "1939-v2")
    anden, _ = run_structural_path(ocr, "1939-v2")
    nye = [post for post in foerste if post.get("postklasse")]
    stamfaedre = [post for post in nye if post["postklasse"] == "stamfader"]
    oversigter = [post for post in nye if post["postklasse"] == "oversigtspost"]

    assert len(nye) == 48
    assert len(stamfaedre) == 23
    assert len(oversigter) == 25
    assert sum(post["dublet_af_stamtavle"] for post in oversigter) == 7
    assert "tvetydige unummererede kandidater: 25" in rapport
    assert len({post["lokal_id"] for post in foerste}) == len(foerste)
    assert foerste == anden


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


def test_clean_1939_text_removes_header_and_despaces_long_runs():
    raw = "Ro-\n\n   Reventlow.\n\nstock og L o r e n z og A b e 1, men N. N. og f. 1901.\n"
    clean = seg.clean_1939_text(raw)
    assert "Reventlow." not in clean
    assert "Lorenz" in clean
    assert "Abel" in clean
    assert "N. N." in clean
    assert "f. 1901" in clean


def test_clean_1939_text_does_not_join_three_single_letters():
    assert seg.clean_1939_text("A B C") == "A B C"


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


def test_structural_boundary_caps_before_unanchored_next_post():
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801. Lang egen tekst her.\n"
        "2. Uankret Ulrik, om hvem intet andet vides.\n"
        "3. Berta Aabing, f. 12. Marts 1803. Lang egen tekst her.\n"
    )
    posts = [
        make_post(1, foedsel="11. Jan. 1801"),
        make_post(2),
        make_post(3, foedsel="12. Marts 1803"),
    ]
    out = seg.segment(posts, raw, {"window-01": (490, 490)})
    assert "Uankret Ulrik" not in out["1"]["narrative"]
    assert "12. Marts 1803" not in out["1"]["narrative"]


def test_unanchored_run_maps_one_to_one_to_exact_structural_gap():
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801. Lang egen tekst her.\n"
        "2. Uankret Ulrik, om hvem en lang opdigtet tekst er skrevet.\n"
        "3. Uankret Yrsa, om hvem en anden lang opdigtet tekst er skrevet.\n"
        "4. Berta Aabing, f. 12. Marts 1803. Lang egen tekst her.\n"
    )
    posts = [
        make_post(1, foedsel="11. Jan. 1801"),
        make_post(20),
        make_post(30),
        make_post(4, foedsel="12. Marts 1803"),
    ]
    out = seg.segment(posts, raw, {"window-01": (490, 490)})
    assert out["20"]["metode"] == "struktur-fallback"
    assert out["30"]["metode"] == "struktur-fallback"
    assert "Uankret Yrsa" not in out["20"]["narrative"]
    assert "Uankret Ulrik" not in out["30"]["narrative"]


def test_window_edge_uses_last_matching_book_number():
    raw = (
        "### PAGE 490 ###\n"
        "9. Aksel Aabing, f. 11. Jan. 1801. Sikker indledende ankerpost.\n"
        "1. Tidlig uvedkommende tekst, som er tilstraekkelig lang.\n"
        "2. Endnu en uvedkommende tekst, som er tilstraekkelig lang.\n"
        "1. Sen kantpost uden andre tekstankre, men med sikker bognummerering.\n"
    )
    post = make_post(99)
    post["nr"] = "1"
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"), post], raw,
        {"window-01": (490, 490)})
    assert out["99"]["metode"] == "struktur-fallback"
    assert "Sen kantpost" in out["99"]["narrative"]
    assert "Tidlig uvedkommende" not in out["99"]["narrative"]


def test_unique_name_can_anchor_post_without_dates():
    raw = (
        "### PAGE 490 ###\n"
        "1. Testperson 1, om hvem en lang opdigtet biografi er skrevet.\n"
        "2. Testperson 2, om hvem en anden lang biografi er skrevet.\n"
    )
    posts = [make_post(1), make_post(2)]
    out = seg.segment(posts, raw, {"window-01": (490, 490)})
    assert out["1"]["metode"] == "anker"
    assert out["2"]["metode"] == "anker"
    assert "Testperson 2" not in out["1"]["narrative"]


def test_unique_book_number_can_anchor_when_text_anchors_fail():
    raw = (
        "### PAGE 490 ###\n"
        "7. En helt anden opdigtet tekst uden matchende personfelt.\n"
    )
    post = make_post(1)
    post["nr"] = 7
    out = seg.segment([post], raw, {"window-01": (490, 490)})
    assert out["1"]["metode"] == "anker"
    assert out["1"]["narrative"].startswith("7.")


def test_book_number_is_scoped_by_roman_line():
    raw = (
        "### PAGE 490 ###\n"
        "II. En opdigtet linje\n"
        "3. Foerste tekst uden matchende personfelt, men tilstraekkelig lang.\n"
        "III. En anden opdigtet linje\n"
        "3. Anden tekst uden matchende personfelt, men tilstraekkelig lang.\n"
    )
    post = make_post(1, linje="III. En anden opdigtet linje")
    post["nr"] = "3"
    out = seg.segment([post], raw, {"window-01": (490, 490)})
    assert out["1"]["metode"] == "anker"
    assert "Anden tekst" in out["1"]["narrative"]
    assert "Foerste tekst" not in out["1"]["narrative"]


def test_book_number_is_scoped_by_named_letter_line():
    raw = (
        "### PAGE 490 ###\n"
        "B. Foerste opdigtede linje\n"
        "1. Foerste tekst uden matchende personfelt, men tilstraekkelig lang.\n"
        "B. Anden opdigtede linje\n"
        "1. Anden tekst uden matchende personfelt, men tilstraekkelig lang.\n"
    )
    post = make_post(1, linje="B. Anden opdigtede linje")
    post["nr"] = "1"
    out = seg.segment([post], raw, {"window-01": (490, 490)})
    assert out["1"]["metode"] == "anker"
    assert "Anden tekst" in out["1"]["narrative"]
    assert "Foerste tekst" not in out["1"]["narrative"]


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


def test_group_fallback_is_scoped_by_parent_note():
    posts = [
        make_post(1, gruppe="I", linje="L", foedsel="11. Jan. 1801"),
        make_post(2, gruppe="I", linje="L"),
        make_post(3, gruppe="I", linje="L", foedsel="12. Marts 1803"),
        make_post(4, gruppe="I", linje="L"),
    ]
    posts[0]["_ctx"]["foraeldre_note"] = "Forælder A"
    posts[1]["_ctx"]["foraeldre_note"] = "Forælder A"
    posts[2]["_ctx"]["foraeldre_note"] = "Forælder B"
    posts[3]["_ctx"]["foraeldre_note"] = "Forælder B"
    out = run_mini(posts)
    assert "12. Marts 1803" not in out["2"]["narrative"]
    assert "11. Jan. 1801" not in out["4"]["narrative"]


def test_vindue_fallback_when_no_gruppe_anchor():
    posts = [make_post(1)]  # ingen ankre, ingen gruppe
    out = run_mini(posts)
    assert out["1"]["metode"] == "nabo-fallback"
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
        assert v["metode"] in (
            "anker", "struktur-fallback", "gruppe-fallback", "nabo-fallback",
            "kollisions-fallback", "vindue-fallback")


def test_duplicate_anchor_position_second_becomes_fallback():
    posts = [
        make_post(1, foedsel="11. Jan. 1801"),
        make_post(2, foedsel="11. Jan. 1801"),  # samme anker -> kollision
    ]
    out = run_mini(posts)
    metoder = sorted(v["metode"] for v in out.values())
    assert metoder.count("anker") == 1
    assert metoder.count("kollisions-fallback") == 1


def test_short_but_structurally_bounded_anchor_slice_is_preserved():
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
    # Et entydigt anker med sikker graense er bedre end en enorm fallback,
    # selv naar kildens egen post er meget kort.
    assert out["1"]["metode"] == "anker"
    assert len(out["1"]["narrative"]) < 20
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


def test_compute_stats_exposes_duplication_and_noise_gates():
    posts = [make_post(1), make_post(2)]
    noisy = "1. L o r e n z\nReventlow.\n2. Anden opdigtet post med lang tekst."
    result = {
        "1": {"narrative": noisy, "side": 490, "metode": "gruppe-fallback"},
        "2": {"narrative": noisy, "side": 490, "metode": "gruppe-fallback"},
    }
    stats = seg.compute_stats(posts, result, MINI_WINMAP, MINI_RAW)
    assert stats["duplikerede_poster"] == 2
    assert stats["duplikat_klynger"] == 1
    assert stats["narrativer_med_flere_postmarkoerer"] == 2
    assert stats["narrativer_med_sidehoved"] == 2
    assert stats["narrativer_med_bogstavspredning"] == 2
    failures = seg.quality_gate_failures(stats)
    assert any("sidehoved_forekomster" in failure for failure in failures)
    assert any("bogstavspredning_forekomster" in failure for failure in failures)


# ------------------------------------------------- gruppeoverskrifter (bleed)

def test_group_header_terminates_previous_narrative():
    """Bogens kuld-overskrifter er ikke personposter og maa ikke haenge paa
    halen af den foregaaende post."""
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801. Egen tekst om hans virke.\n"
        "Sjette Slægtled.\n"
        "Aksel Aabings Børn m. Berta Bagger:\n"
        "1. Carla Aabing, f. 12. Marts 1830.\n"
    )
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"),
         make_post(2, foedsel="12. Marts 1830")],
        raw, {"window-01": (490, 490)})
    assert "Egen tekst om hans virke" in out["1"]["narrative"]
    assert "Slægtled" not in out["1"]["narrative"]
    assert "Aabings Børn" not in out["1"]["narrative"]


def test_multiline_group_header_is_cut_from_its_first_line():
    """Overskrifter over flere linjer snittes fra foerste linje, ikke fra den
    linje hvor 'Børn' tilfaeldigvis staar."""
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801. Egen tekst om hans virke.\n"
        "Kammerherre, Hofjægermester Aksel Bertram\n"
        "Christian Aabings Børn\n"
        "af første Ægteskab med Berta Bagger:\n"
        "1. Carla Aabing, f. 12. Marts 1830.\n"
    )
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"),
         make_post(2, foedsel="12. Marts 1830")],
        raw, {"window-01": (490, 490)})
    assert "Kammerherre" not in out["1"]["narrative"]
    assert "Ægteskab" not in out["1"]["narrative"]


def test_inline_boern_crossreference_does_not_cut_narrative():
    """'- Børn:' sidst i en post er bogens krydshenvisning, ikke en overskrift
    — snittet maa ikke vandre baglaens ind i prosaen."""
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801, en tekst der fortsaetter\n"
        "uden punktum ved linjeskift og slutter med en opremsning\n"
        "- Børn:\n"
        "2. Berta Aabing, f. 12. Marts 1803.\n"
    )
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"),
         make_post(2, foedsel="12. Marts 1803")],
        raw, {"window-01": (490, 490)})
    assert "fortsaetter" in out["1"]["narrative"]
    assert "uden punktum ved linjeskift" in out["1"]["narrative"]


def test_slaegtled_line_alone_terminates_narrative():
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801. Egen tekst om hans virke.\n"
        "Fjerde Slægtled.\n"
        "1. Carla Aabing, f. 12. Marts 1830.\n"
    )
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"),
         make_post(2, foedsel="12. Marts 1830")],
        raw, {"window-01": (490, 490)})
    assert "Slægtled" not in out["1"]["narrative"]


def test_prose_line_ending_in_colon_is_not_a_group_header():
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801, som skrev til sin ven\n"
        "og udtrykte det saaledes:\n"
        "»en meget lang og opdigtet sentens uden overskriftskarakter«.\n"
        "2. Berta Aabing, f. 12. Marts 1803.\n"
    )
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"),
         make_post(2, foedsel="12. Marts 1803")],
        raw, {"window-01": (490, 490)})
    assert "sentens uden overskriftskarakter" in out["1"]["narrative"]


# ----------------------------------------------- orddelt navn ved linjeskift

def test_hyphenated_name_across_linebreak_still_anchors_head():
    """OCR deler navne ved linjeskift ('Ana-\\nstasia'); ankeret skal stadig
    finde navnet, saa postens hoved ikke gaar tabt."""
    raw = (
        "### PAGE 490 ###\n"
        "3. Comtesse Karoline Ana-\n"
        "stasia, f. 11. Jan. 1801 paa Testgaard, en laengere tekst.\n"
        "4. Berta Aabing, f. 12. Marts 1803.\n"
    )
    post = make_post(1, foedsel="11. Jan. 1801")
    post["navn"] = "Karoline Anastasia"
    out = seg.segment(
        [post, make_post(2, foedsel="12. Marts 1803")],
        raw, {"window-01": (490, 490)})
    assert out["1"]["narrative"].startswith("3.")
    assert "Ana-" in out["1"]["narrative"]


def test_normalize_drops_hyphens_symmetrically():
    norm, _ = seg.normalize_with_map("Ana-\nstasia")
    assert norm == "anastasia"
    norm2, _ = seg.normalize_with_map("Anastasia")
    assert norm == norm2


# ------------------------------------------------ bar romertalslinje + snap

def test_bare_roman_line_terminates_narrative():
    """Romertalslinjer uden efterfoelgende tekst ('III.' alene paa linjen)
    er ogsaa sektionsgraenser."""
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801. Egen tekst om hans virke.\n"
        "III.\n"
        "Aksel Aabings Børn m. Berta Bagger:\n"
        "1. Carla Aabing, f. 12. Marts 1830.\n"
    )
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"),
         make_post(2, foedsel="12. Marts 1830")],
        raw, {"window-01": (490, 490)})
    assert "III." not in out["1"]["narrative"]


def test_anchor_snaps_back_to_own_record_start():
    """Naar ankeret er et faktum inde i posten, flyttes starten tilbage til
    postens egen nummerlinje, saa hovedet ikke gaar tabt."""
    raw = (
        "### PAGE 490 ###\n"
        "2. Aksel Aabing, som var en meget omtalt mand i sin samtid,\n"
        "f. 11. Jan. 1801 paa Testgaard, og som drev vandmoellen.\n"
        "3. Berta Aabing, f. 12. Marts 1803.\n"
    )
    post = make_post(1, foedsel="11. Jan. 1801")
    post["navn"] = "Ukendt Navn Der Ikke Findes"
    post["_orig_nr"] = 2
    out = seg.segment(
        [post, make_post(2, foedsel="12. Marts 1803")],
        raw, {"window-01": (490, 490)})
    assert out["1"]["narrative"].startswith("2. Aksel Aabing")
    assert "omtalt mand" in out["1"]["narrative"]


def test_snap_back_stops_at_foreign_record_start():
    """Ligger der en anden posts nummerlinje mellem ankeret og postens egen
    nummerlinje, snappes der ikke — saa naboens tekst aldrig opsluges."""
    raw = (
        "### PAGE 490 ###\n"
        "2. Aksel Aabing, en kort indledning uden ankerord i teksten.\n"
        "3. Berta Bagger, om hvem der staar en anden lang tekst her.\n"
        "en fortsaettelse med f. 11. Jan. 1801 midt i naboens afsnit.\n"
    )
    post = make_post(1, foedsel="11. Jan. 1801")
    post["navn"] = "Ukendt Navn Der Ikke Findes"
    post["_orig_nr"] = 2
    out = seg.segment([post], raw, {"window-01": (490, 490)})
    assert "Aksel Aabing" not in out["1"]["narrative"]


def test_group_header_without_colon_terminates_narrative():
    """Nogle kuld-overskrifter ender paa punktum, ikke kolon
    ('Johan Reventlows Døtre m. Birgitte Hansdatter (Lindenov).')."""
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801. Egen tekst om hans virke.\n"
        "Johan Aabings Døtre m. Berta Bagger\n"
        "(Lindenov).\n"
        "1. Carla Aabing, f. 12. Marts 1830.\n"
    )
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"),
         make_post(2, foedsel="12. Marts 1830")],
        raw, {"window-01": (490, 490)})
    assert "Aabings Døtre" not in out["1"]["narrative"]
    assert "Egen tekst om hans virke" in out["1"]["narrative"]


def test_prose_mentioning_children_is_not_a_group_header():
    """En prosalinje der naevner '<Navn>s Børn' midt i en saetning maa ikke
    snitte posten over."""
    raw = (
        "### PAGE 490 ###\n"
        "1. Aksel Aabing, f. 11. Jan. 1801, som var Fader til\n"
        "Bertram Aabings Børn og som drev vandmoellen til sin doed.\n"
        "2. Berta Aabing, f. 12. Marts 1803.\n"
    )
    out = seg.segment(
        [make_post(1, foedsel="11. Jan. 1801"),
         make_post(2, foedsel="12. Marts 1803")],
        raw, {"window-01": (490, 490)})
    assert "vandmoellen til sin doed" in out["1"]["narrative"]
