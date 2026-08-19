import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "convert_c0_linkage_decisions_1939_v50",
    Path(__file__).resolve().parent / "convert_c0_linkage_decisions_1939_v50.py")
c = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(c)


def _cand(person_id, navn, coverage=0.97, containment="record_in_person",
          name_signal=True, page_signal=True, staged=False, side="574-75"):
    return {"person_id": person_id, "visning_navn": navn, "staged": staged,
            "side": side, "ratio": 0.5, "coverage": coverage, "longest": 400,
            "containment": containment, "name_signal": name_signal,
            "page_signal": page_signal, "person_tekst": f"tekst om {navn}"}


DOC = {
    "schema_version": "1.0",
    "records": [
        {"new_record_key": "record-a", "classification": "kobling",
         "pages": {"page_from": 574, "page_to": 575}, "skeleton_len": 502,
         "verbatim_text": "Greve Ferdinand", "source_span": {"char_from": 1, "char_to": 9},
         "candidates": [_cand(1299, "Ferdinand Gottlieb")]},
        {"new_record_key": "record-b", "classification": "sammenlaegning",
         "pages": None, "skeleton_len": 300, "verbatim_text": "Anna og Christian",
         "source_span": {"char_from": 10, "char_to": 20},
         "candidates": [_cand(1296, "Anna", side=None, page_signal=None),
                        _cand(1297, "Christian", coverage=0.8, staged=True,
                              side=None, page_signal=None)]},
        {"new_record_key": "record-c", "classification": "aegte_ny",
         "pages": {"page_from": 504, "page_to": 504}, "skeleton_len": 137,
         "verbatim_text": "Fra ovennævnte Joachim nedstammer den yngre Linje",
         "source_span": {"char_from": 21, "char_to": 30}, "candidates": []},
        {"new_record_key": "record-d", "classification": "for_kort",
         "pages": {"page_from": 504, "page_to": 504}, "skeleton_len": 22,
         "verbatim_text": "I1. Hr. Iven til Rixdorf † 1569.",
         "source_span": {"char_from": 31, "char_to": 40},
         "candidates": [_cand(991, "Iven", coverage=1.0, side="504")]},
        {"new_record_key": "record-f", "classification": "allerede_materialiseret",
         "pages": {"page_from": 498, "page_to": 498}, "skeleton_len": 400,
         "verbatim_text": "Ditlev, nævnt 1254",
         "source_span": {"char_from": 51, "char_to": 60},
         "candidates": [_cand(1846, "Ditlev", coverage=1.0)]},
        {"new_record_key": "record-e", "classification": "gennemgang",
         "pages": {"page_from": 509, "page_to": 509}, "skeleton_len": 228,
         "verbatim_text": "D. Geheimekonferensraad Detlev",
         "source_span": {"char_from": 41, "char_to": 50},
         "candidates": [_cand(1159, "Detlev", name_signal=False, page_signal=None,
                              side=None)]},
    ],
}


# --------------------------------------------------------------------------
# generate
# --------------------------------------------------------------------------

def test_generate_udfylder_anbefaling_pr_klasse():
    text = c.generate_document(DOC)
    assert "[KOBL]" in text and "[C3]" in text and "[NY]" in text and "[SPØRG]" in text


def test_generate_saetter_mistaenkelige_oeverst():
    text = c.generate_document(DOC)
    assert text.index("KRÆVER STILLINGTAGEN") < text.index("FOR KORT")
    assert text.index("FOR KORT") < text.index("SAMMENLÆGNING")
    assert text.index("SAMMENLÆGNING") < text.index("FORESLÅET KOBLING")
    assert text.index("FORESLÅET KOBLING") < text.index("INGEN KANDIDAT")


def test_generate_er_deterministisk():
    assert c.generate_document(DOC) == c.generate_document(DOC)


def test_generate_har_en_linje_pr_record():
    text = c.generate_document(DOC)
    decision_lines = [l for l in text.split("\n") if c._parse_positional(l)]
    assert len(decision_lines) == len(DOC["records"])


def test_rid_foelger_sorteret_record_key_ikke_sektionsraekkefoelge():
    rids = c.assign_rids(DOC["records"])
    assert rids["record-a"] == "R01"
    assert rids["record-e"] == "R05"


# --------------------------------------------------------------------------
# convert — den glade vej
# --------------------------------------------------------------------------

def test_convert_uaendret_dokument_giver_anbefalingerne():
    result = c.convert_edited_document(c.generate_document(DOC), DOC)
    by_key = {d["new_record_key"]: d for d in result["decisions"]}
    assert by_key["record-a"]["token"] == "[KOBL]"
    assert by_key["record-a"]["person_id"] == 1299
    assert by_key["record-b"]["token"] == "[C3]"
    assert by_key["record-b"]["person_id"] is None
    assert by_key["record-c"]["token"] == "[NY]"
    assert by_key["record-d"]["token"] == "[SPØRG]"
    assert by_key["record-e"]["token"] == "[SPØRG]"


def _retok(text, record_key, new_token):
    """Skift token på ÉN beslutningslinje. Bruges frem for en rå
    streng-erstatning, fordi instruktionshovedet også nævner tokenerne --
    og hovedet er (med rette) byte-låst."""
    rid = c.assign_rids(DOC["records"])[record_key]
    lines = text.split("\n")
    for i, line in enumerate(lines):
        parsed = c._parse_positional(line)
        if parsed and parsed[1] == rid:
            lines[i] = new_token + line[len(parsed[0]):]
            return "\n".join(lines)
    raise AssertionError("linje for {} ikke fundet".format(record_key))


def test_convert_accepterer_menneskets_omvalg():
    text = _retok(c.generate_document(DOC), "record-a", "[SPØRG]")
    result = c.convert_edited_document(text, DOC)
    by_key = {d["new_record_key"]: d for d in result["decisions"]}
    assert by_key["record-a"]["token"] == "[SPØRG]"
    assert by_key["record-a"]["person_id"] is None


def test_convert_afviser_redigeret_instruktionshoved():
    # Hovedet forklarer hvad tokenerne betyder; ændres det, kan arkets
    # afgørelser ikke længere tolkes entydigt.
    text = c.generate_document(DOC).replace(
        "kobl recorden til den viste person", "kobl den til hvem som helst")
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_tillader_kobl_paa_for_kort_post():
    # Mennesket kan se hvad værktøjet ikke kan: 991 er en ægte kobling.
    text = _retok(c.generate_document(DOC), "record-d", "[KOBL]")
    result = c.convert_edited_document(text, DOC)
    by_key = {d["new_record_key"]: d for d in result["decisions"]}
    assert by_key["record-d"]["token"] == "[KOBL]"
    assert by_key["record-d"]["person_id"] == 991


def test_convert_taeller_beslutninger_pr_token():
    result = c.convert_edited_document(c.generate_document(DOC), DOC)
    assert result["counts"]["[KOBL]"] == 1
    assert result["counts"]["[SPØRG]"] == 2


# --------------------------------------------------------------------------
# convert — fail-closed
# --------------------------------------------------------------------------

def test_convert_afviser_kobl_paa_spaerret_post():
    text = c.generate_document(DOC).replace("[C3]", "[KOBL]", 1)
    with pytest.raises(SystemExit) as excinfo:
        c.convert_edited_document(text, DOC)
    assert excinfo.value.code == 2


def test_convert_udfylder_faerdig_paa_materialiseret():
    result = c.convert_edited_document(c.generate_document(DOC), DOC)
    by_key = {d["new_record_key"]: d for d in result["decisions"]}
    assert by_key["record-f"]["token"] == "[FÆRDIG]"
    assert by_key["record-f"]["person_id"] is None


def test_convert_afviser_kobl_paa_materialiseret_record():
    # Personen findes allerede, og dens narrativ har en UNIQUE binding:
    # en kobling ville kollidere frem for at tilføje noget.
    text = _retok(c.generate_document(DOC), "record-f", "[KOBL]")
    with pytest.raises(SystemExit) as excinfo:
        c.convert_edited_document(text, DOC)
    assert excinfo.value.code == 2


def test_convert_afviser_kobl_uden_kandidat():
    text = c.generate_document(DOC).replace("[NY]", "[KOBL]", 1)
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_redigeret_kontekst():
    text = c.generate_document(DOC).replace("Ferdinand Gottlieb", "Ferdinand Gottlie")
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_redigeret_person_id():
    text = c.generate_document(DOC).replace("1299", "1298")
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_ukendt_token():
    text = c.generate_document(DOC).replace("[NY]", "[MÅSKE]", 1)
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_slettet_linje():
    lines = c.generate_document(DOC).split("\n")
    kept = [line for line in lines if not line.startswith("[NY]")]
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(kept), DOC)


def test_convert_afviser_duplikeret_rid():
    lines = c.generate_document(DOC).split("\n")
    doubled = []
    for line in lines:
        doubled.append(line)
        if line.startswith("[NY]"):
            doubled.append(line)
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(doubled), DOC)


def test_convert_afviser_ombyttede_linjer():
    lines = c.generate_document(DOC).split("\n")
    positions = [i for i, l in enumerate(lines) if c._parse_positional(l)]
    a, bpos = positions[0], positions[-1]
    lines[a], lines[bpos] = lines[bpos], lines[a]
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(lines), DOC)


def test_convert_tillader_kolonneforskydning_ved_kortere_token():
    # Et menneske der erstatter [SPØRG] med det kortere [NY] flytter
    # kolonnen; det er den ENESTE tilladte afvigelse fra byte-identitet.
    text = _retok(c.generate_document(DOC), "record-e", "[NY]")
    assert "[NY] " in text  # kolonnen er nu forskudt ét tegn
    result = c.convert_edited_document(text, DOC)
    by_key = {d["new_record_key"]: d for d in result["decisions"]}
    assert by_key["record-e"]["token"] == "[NY]"
