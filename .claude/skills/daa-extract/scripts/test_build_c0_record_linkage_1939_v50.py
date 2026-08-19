import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "build_c0_record_linkage_1939_v50",
    Path(__file__).resolve().parent / "build_c0_record_linkage_1939_v50.py")
b = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(b)


def _person(person_id, navn, tekst, side=None, staged=False, binding=False):
    return {"person_id": person_id, "visning_navn": navn, "staged": staged,
            "side": side, "privat": False, "tekst": tekst,
            "tekst_sha256": "0" * 64, "har_record_binding": binding,
            "binding_status": None}


def _record(key, tekst, char_from=1, char_to=9):
    return {"new_record_key": key,
            "source_span": {"char_from": char_from, "char_to": char_to},
            "verbatim_text": tekst}


LANG_HALE = (" Han var 1874 Student fra Roskilde Katedralskole, 1879 cand. polit., "
             "Volontør i Udenrigsministeriet, 1882-85 Attache ved Legationen i Paris.")


# --------------------------------------------------------------------------
# klassificering af ægte-agtige records
# --------------------------------------------------------------------------

def test_record_med_eksakt_tekst_bliver_kobling():
    records = [_record("record-a", "Greve Ferdinand Gottlie b til Vindeholme" + LANG_HALE)]
    persons = [_person(1299, "Ferdinand Gottlieb",
                       "Greve Ferdinand Gottlieb til Vindeholme" + LANG_HALE, side="574-75")]
    pages = {"record-a": {"page_from": 574, "page_to": 575}}
    result = b.build_records(records, persons, pages)
    assert result[0]["classification"] == "kobling"
    assert result[0]["candidates"][0]["person_id"] == 1299


def test_record_der_matcher_to_personer_spaerres():
    faelles = ("Anna Sophie f. 1693 paa Reventlow og Christian Ditlev f. 1710 "
               "sammesteds, begge omtalt i samme afsnit af stamtavlen.")
    records = [_record("record-b", faelles)]
    persons = [_person(1296, "Anna Sophie", "Anna Sophie f. 1693 paa Reventlow"),
               _person(1297, "Christian Ditlev", "Christian Ditlev f. 1710 sammesteds")]
    result = b.build_records(records, persons, {})
    assert result[0]["classification"] == "sammenlaegning"
    assert len(result[0]["candidates"]) == 2


def test_record_uden_lighed_bliver_aegte_ny():
    records = [_record("record-c",
                       "Ifølge velvillig Meddelelse fra Fru Hildegard von Marchtaler, "
                       "Hamborg, blev i Altona 4 Juli 1695 døbt Carl von Carlstein.")]
    persons = [_person(1, "Otto", "Otto til Søbo, var 1260 Ridder og deltog i toget mod "
                                  "Rügen sammen med sin broder Iven af samme slægt.")]
    result = b.build_records(records, persons, {})
    assert result[0]["classification"] == "aegte_ny"
    assert result[0]["candidates"] == []


def test_kort_record_bliver_for_kort_med_trunkeret_kandidatliste():
    records = [_record("record-d", "4. Margrethe.")]
    persons = [_person(i, f"Margrethe {i}", f"Margrethe {i} var gift og døde ung.")
               for i in range(10, 20)]
    result = b.build_records(records, persons, {})
    assert result[0]["classification"] == "for_kort"
    assert len(result[0]["candidates"]) <= 5
    assert result[0]["skeleton_len"] < 60


# --------------------------------------------------------------------------
# lukning begge veje
# --------------------------------------------------------------------------

def test_lukning_markerer_uforklaret_gammel_tekst():
    closure = b.build_closure(
        records=[{"new_record_key": "record-a", "classification": "kobling",
                  "candidates": [{"person_id": 1299}]}],
        old_text_persons=[1299, 1802], database_only_persons=[1299, 991])
    assert closure["old_text_explained"] == [1299]
    assert closure["old_text_unexplained"] == [1802]
    assert closure["database_only_unexplained"] == [991]


def test_spaerret_record_forklarer_men_loeser_ikke():
    # En sammenlægningspost FORKLARER hvorfor personerne har gammel tekst
    # (en record peger på dem), men LØSER dem ikke i C0 -- de er udskudt til
    # C3. De to spørgsmål holdes adskilt, så fragmentpersonerne hverken
    # forsvinder i "forklaret" eller forurener det ægte fund "uforklaret".
    closure = b.build_closure(
        records=[{"new_record_key": "record-b", "classification": "sammenlaegning",
                  "candidates": [{"person_id": 1296}, {"person_id": 1297}]}],
        old_text_persons=[1296, 1297], database_only_persons=[])
    assert sorted(closure["old_text_explained"]) == [1296, 1297]
    assert closure["old_text_unexplained"] == []
    assert sorted(closure["old_text_deferred_c3"]) == [1296, 1297]
    assert closure["old_text_resolved_in_c0"] == []


def test_for_kort_bidrager_hverken_til_forklaret_eller_loest():
    closure = b.build_closure(
        records=[{"new_record_key": "record-d", "classification": "for_kort",
                  "candidates": [{"person_id": 991}]}],
        old_text_persons=[991], database_only_persons=[991])
    assert closure["old_text_explained"] == []
    assert closure["old_text_unexplained"] == [991]
    assert closure["database_only_unexplained"] == [991]
    # ... men noteres særskilt, så 'uforklaret' ikke overdriver.
    assert closure["old_text_only_short_record_hint"] == [991]


def test_uforklaret_uden_noget_spor_giver_intet_hint():
    closure = b.build_closure(
        records=[{"new_record_key": "record-e", "classification": "aegte_ny",
                  "candidates": []}],
        old_text_persons=[1802], database_only_persons=[])
    assert closure["old_text_unexplained"] == [1802]
    assert closure["old_text_only_short_record_hint"] == []


# --------------------------------------------------------------------------
# gates
# --------------------------------------------------------------------------

def test_hash_gate_afviser_forkert_input(tmp_path):
    wrong = tmp_path / "wrong.json"
    wrong.write_text("{}", encoding="utf-8")
    with pytest.raises(SystemExit) as excinfo:
        b.load_locked(wrong, "0" * 64, "C0_LINKAGE_IMPORT_PREVIEW_HASH_MISMATCH")
    assert excinfo.value.code == 2


def test_kalibreringsanker_er_haardkodet():
    assert b.CALIBRATION_RECORD_KEY == "record-82f49e95-e5ce-4e08-9840-d0e334b4ba50"
    assert b.CALIBRATION_PERSON_ID == 1299


def test_gate_afviser_person_haevdet_to_gange():
    built = [{"new_record_key": "record-a", "classification": "kobling",
              "candidates": [{"person_id": 1299}]},
             {"new_record_key": "record-b", "classification": "kobling",
              "candidates": [{"person_id": 1299}]}]
    with pytest.raises(SystemExit) as excinfo:
        b.assert_no_person_claimed_twice(built)
    assert excinfo.value.code == 2


def test_gate_tillader_forskellige_personer():
    built = [{"new_record_key": "record-a", "classification": "kobling",
              "candidates": [{"person_id": 1299}]},
             {"new_record_key": "record-b", "classification": "gennemgang",
              "candidates": [{"person_id": 1298}]}]
    b.assert_no_person_claimed_twice(built)  # må ikke rejse


def test_gate_afviser_usandsynlig_fordeling():
    built = [{"new_record_key": f"record-{i}", "classification": "kobling",
              "candidates": [{"person_id": i}]} for i in range(30)]
    with pytest.raises(SystemExit) as excinfo:
        b.assert_kobling_distribution_plausible(built)
    assert excinfo.value.code == 2


def test_gate_tillader_rimelig_fordeling():
    built = [{"new_record_key": f"record-{i}", "classification": "kobling",
              "candidates": [{"person_id": i}]} for i in range(12)]
    b.assert_kobling_distribution_plausible(built)  # må ikke rejse


# --------------------------------------------------------------------------
# sidekort
# --------------------------------------------------------------------------

def test_sidekort_kraever_byte_eksakt_verbatim():
    boundary = {"schema_version": "1.0", "source_record_review": {
        "schema_version": "1.0", "source_id": b.CALAMARI_SOURCE_ID,
        "rendition_id": b.CALAMARI_RENDITION_ID, "rendition_sha256": "f" * 64,
        "records": [{"source_anchor": {"char_from": 1, "char_to": 9},
                     "span": {"page_from": 574, "page_to": 575},
                     "verbatim_text": "en anden tekst"}]}}
    records = {"record-a": _record("record-a", "min tekst")}
    with pytest.raises(SystemExit) as excinfo:
        b.boundary_pages(boundary, records, "f" * 64)
    assert excinfo.value.code == 2


def test_sidekort_slaar_op_paa_anker():
    boundary = {"schema_version": "1.0", "source_record_review": {
        "schema_version": "1.0", "source_id": b.CALAMARI_SOURCE_ID,
        "rendition_id": b.CALAMARI_RENDITION_ID, "rendition_sha256": "f" * 64,
        "records": [{"source_anchor": {"char_from": 1, "char_to": 9},
                     "span": {"page_from": 574, "page_to": 575},
                     "verbatim_text": "min tekst"}]}}
    records = {"record-a": _record("record-a", "min tekst")}
    pages = b.boundary_pages(boundary, records, "f" * 64)
    assert pages["record-a"] == {"page_from": 574, "page_to": 575}
