import importlib.util
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "match_c0_records_1939_v50",
    Path(__file__).resolve().parent / "match_c0_records_1939_v50.py")
m = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(m)

LANG = 400  # skeletlængde komfortabelt over MIN_SKELETON_CHARS


# --------------------------------------------------------------------------
# skelet
# --------------------------------------------------------------------------

def test_skeleton_fjerner_ombrydning_og_ocr_mellemrum():
    a = m.text_skeleton("5. Greve Ferdinand Einar Julius Gottlie b til\nVindeholme")
    b = m.text_skeleton("Greve Ferdinand Einar Julius Gottlieb til Vindeholme")
    assert a.endswith("gottliebtilvindeholme")
    assert b in a


def test_skeleton_er_idempotent():
    once = m.text_skeleton("A-\nbe  c.")
    assert m.text_skeleton(once) == once


# --------------------------------------------------------------------------
# lighed
# --------------------------------------------------------------------------

def test_similarity_exact():
    s = m.similarity("abc", "abc")
    assert s["containment"] == "exact"
    assert s["ratio"] == 1.0
    assert s["coverage"] == 1.0


def test_kort_record_i_lang_narrativ_er_kandidat():
    # Den fælde ratio() ville falde i: perfekt delstreng, stor længdeforskel.
    record = m.text_skeleton("Greve Ferdinand Einar Julius Gottlie b til Vindeholme")
    person = m.text_skeleton(
        "x" * 3000 + "Greve Ferdinand Einar Julius Gottlieb til Vindeholme" + "y" * 3000)
    s = m.similarity(record, person)
    assert s["coverage"] >= 0.9
    assert s["ratio"] < 0.3  # dokumenterer hvorfor ratio ikke må styre


def test_similarity_containment_begge_veje():
    assert m.similarity("abc", "xxabcxx")["containment"] == "record_in_person"
    assert m.similarity("xxabcxx", "abc")["containment"] == "person_in_record"
    assert m.similarity("abc", "def")["containment"] == "none"


def test_similarity_taaler_tomme_strenge():
    s = m.similarity("", "")
    assert s["coverage"] == 0.0
    assert s["longest"] == 0
    assert s["containment"] == "none"


# --------------------------------------------------------------------------
# sammenhængende anker — spejlvendingen af ratio-fælden
# --------------------------------------------------------------------------

def test_kort_modpart_med_spredte_bogstaver_er_ikke_anker():
    # Person 1149 hedder "Henrich" (10 skelettegn). Bogstaverne findes spredt
    # i enhver lang record -> coverage 1.0 uden nogen identitet på spil.
    # Uden ankerkravet blev kalibreringsrecorden derfor sammenlaegning.
    kort = m.text_skeleton("Henrich")
    lang = m.text_skeleton(
        "Greve Ferdinand Einar Julius Gottlieb til Vindeholme, 1874 Student fra "
        "Roskilde Katedralskole, 1879 cand. polit., Volontør i Udenrigsministeriet")
    s = m.similarity(lang, kort)
    assert s["coverage"] > 0.5          # den gamle regel ville sige kandidat
    assert not m.has_anchor(s, len(lang), len(kort))


def test_langt_sammenhaengende_match_er_anker():
    person = m.text_skeleton("Greve Ferdinand Einar Julius Gottlieb til Vindeholme")
    record = m.text_skeleton(
        "5. Greve Ferdinand Einar Julius Gottlieb til Vindeholme (udskilt 1909)")
    s = m.similarity(record, person)
    assert m.has_anchor(s, len(record), len(person))


def test_ankerkrav_skalerer_for_korte_modparter():
    # 80 % af den korteste, dog højst MIN_ANCHOR_RUN.
    assert m.anchor_required(500, 20) == 16
    assert m.anchor_required(500, 500) == m.MIN_ANCHOR_RUN
    assert m.anchor_required(0, 500) == 0


# --------------------------------------------------------------------------
# forfilter
# --------------------------------------------------------------------------

def test_forfilter_slipper_korte_skeletter_igennem():
    assert m.shares_ngram("kort", "noget helt andet og laengere tekst her")


def test_forfilter_afviser_uden_faelles_ngram():
    a = "a" * 100
    b = "b" * 100
    assert not m.shares_ngram(a, b)


def test_forfilter_accepterer_faelles_ngram():
    faelles = "ferdinandeinarjulius"  # 20 tegn
    assert m.shares_ngram("x" * 50 + faelles, "y" * 50 + faelles)


# --------------------------------------------------------------------------
# navne- og sidesignal
# --------------------------------------------------------------------------

def test_name_signal_taaler_ocr_mellemrum_og_klammer():
    assert m.name_signal("Greve Ferdinand Einar Julius Gottlie b til",
                         "Ferdinand Einar Julius Gottlieb")
    assert m.name_signal("Henrik Reventlow, f. 1600", "Henrik [Reventlow]")
    assert not m.name_signal("Christian Ditlev", "Anna Sophie")


def test_name_signal_er_falsk_ved_meget_kort_navn():
    # For korte navne matcher tilfældigt; de må ikke bekræfte noget.
    assert not m.name_signal("Marie og Ida", "Ida")


def test_name_signal_taaler_manglende_navn():
    assert not m.name_signal("noget tekst", None)


def test_page_signal_er_none_naar_side_mangler():
    assert m.page_signal({"page_from": 574, "page_to": 575}, None) is None
    assert m.page_signal(None, "574-75") is None


def test_page_signal_matcher_overlap():
    assert m.page_signal({"page_from": 574, "page_to": 575}, "574-75") is True
    assert m.page_signal({"page_from": 574, "page_to": 575}, "575") is True
    assert m.page_signal({"page_from": 574, "page_to": 575}, "601") is False


# --------------------------------------------------------------------------
# klassificering
# --------------------------------------------------------------------------

def test_classify_kobling_kraever_bekraeftende_signal():
    cand = [{"person_id": 1299, "coverage": 0.97, "containment": "record_in_person",
             "name_signal": True, "page_signal": True}]
    assert m.classify(cand, LANG) == "kobling"


def test_classify_gennemgang_naar_kun_tekst_taler():
    cand = [{"person_id": 1299, "coverage": 0.97, "containment": "record_in_person",
             "name_signal": False, "page_signal": None}]
    assert m.classify(cand, LANG) == "gennemgang"


def test_classify_sammenlaegning_ved_flere_kandidater():
    cand = [{"person_id": 1296, "coverage": 0.95, "containment": "person_in_record",
             "name_signal": True, "page_signal": True},
            {"person_id": 1297, "coverage": 0.93, "containment": "person_in_record",
             "name_signal": True, "page_signal": True}]
    assert m.classify(cand, LANG) == "sammenlaegning"


def test_classify_aegte_ny_uden_kandidater():
    assert m.classify([], LANG) == "aegte_ny"


def test_classify_er_fail_closed_ved_svag_daekning():
    cand = [{"person_id": 5, "coverage": 0.56, "containment": "none",
             "name_signal": True, "page_signal": True}]
    assert m.classify(cand, LANG) == "gennemgang"


def test_kort_record_bliver_for_kort_ikke_sammenlaegning():
    # "4. Margrethe." -> "4margrethe" (10 tegn) matcher promiskuøst.
    # Den må ALDRIG rutes til C3 som fragment.
    cand = [{"person_id": i, "coverage": 1.0, "containment": "record_in_person",
             "name_signal": True, "page_signal": None} for i in (10, 11, 12)]
    assert m.classify(cand, len(m.text_skeleton("4. Margrethe."))) == "for_kort"


def test_kort_record_uden_kandidater_er_ogsaa_for_kort():
    assert m.classify([], 10) == "for_kort"


def test_for_kort_gaelder_ogsaa_lige_under_graensen():
    assert m.classify([], m.MIN_SKELETON_CHARS - 1) == "for_kort"
    assert m.classify([], m.MIN_SKELETON_CHARS) == "aegte_ny"
