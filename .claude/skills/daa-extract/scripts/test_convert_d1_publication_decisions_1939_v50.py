import importlib.util
import json
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "convert_d1_publication_decisions_1939_v50",
    Path(__file__).resolve().parent / "convert_d1_publication_decisions_1939_v50.py")
c = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(c)

DOC = {
    "schema_version": "1.0",
    "counts": {"staged_total": 96, "selected": 3, "predicted_partners": 2,
               "blocked_no_binding": 7, "spouses_visible_partner": 21,
               "expected_unstaged_total": 5},
    "selected": [
        {"person_id": 927, "visning_navn": "Henrik", "side": "507", "fakta": 1,
         "samme_som_2020": False, "partner_ids": []},
        {"person_id": 937, "visning_navn": "Gotskalk [Reventlow]", "side": "500",
         "fakta": 2, "samme_som_2020": True, "partner_ids": [1467]},
        {"person_id": 947, "visning_navn": "Hedevig Maria", "side": "598", "fakta": 3,
         "samme_som_2020": False, "partner_ids": [1467, 1468]},
    ],
    "predicted_partners": [
        {"person_id": 1467, "visning_navn": "Anna Margarethe von der Lieth",
         "via_person_ids": [937, 947]},
        {"person_id": 1468, "visning_navn": "Jørgen Nielsen Pougdal",
         "via_person_ids": [947]},
    ],
}

# To valgte der deler familie -- 26 af de 44 ser sådan ud i prod.
DOC_KOBLET = {
    "schema_version": "1.0",
    "counts": {"staged_total": 96, "selected": 2, "predicted_partners": 0,
               "blocked_no_binding": 7, "spouses_visible_partner": 21,
               "expected_unstaged_total": 2},
    "selected": [
        {"person_id": 950, "visning_navn": "Anna Sophie", "side": "598", "fakta": 2,
         "samme_som_2020": False, "partner_ids": [951]},
        {"person_id": 951, "visning_navn": "Engelke Reventlow", "side": "598",
         "fakta": 2, "samme_som_2020": False, "partner_ids": [950]},
    ],
    "predicted_partners": [],
}


def _retok(doc, text, person_id, new_token):
    pid = c.assign_pids(doc["selected"])[person_id]
    lines = text.split("\n")
    for i, line in enumerate(lines):
        parsed = c._parse_positional(line)
        if parsed and parsed[1] == pid:
            lines[i] = new_token + line[len(parsed[0]):]
            return "\n".join(lines)
    raise AssertionError("linje for {} ikke fundet".format(person_id))


# --------------------------------------------------------------------------
# generate
# --------------------------------------------------------------------------

def test_generate_udfylder_publicer_paa_alle():
    text = c.generate_document(DOC)
    assert text.count("[PUBLICÉR]") >= 3


def test_generate_er_deterministisk():
    assert c.generate_document(DOC) == c.generate_document(DOC)


def test_pid_foelger_stigende_person_id():
    pids = c.assign_pids(DOC["selected"])
    assert pids[927] == "P01" and pids[947] == "P03"


def test_linjen_viser_stubs_der_foelger_med():
    text = c.generate_document(DOC)
    assert "1467" in text and "1468" in text
    assert "stub følger med" in text


def test_linjen_markerer_tvaerudgave_samme_som():
    assert "samme_som 2020" in c.generate_document(DOC)


def test_linjen_advarer_om_koblede_valgte():
    # Brugeren skal kunne SE koblingen, før hen prøver at holde én tilbage.
    text = c.generate_document(DOC_KOBLET)
    assert "KOBLET til valgt" in text
    assert "951" in text and "950" in text


def test_generate_har_en_linje_pr_person():
    text = c.generate_document(DOC)
    linjer = [l for l in text.split("\n") if c._parse_positional(l)]
    assert len(linjer) == 3


# --------------------------------------------------------------------------
# convert — den glade vej
# --------------------------------------------------------------------------

def test_convert_uaendret_giver_alle_valgte():
    result = c.convert_edited_document(c.generate_document(DOC), DOC)
    assert result["person_ids"] == [927, 937, 947]
    assert result["held_back"] == []
    assert result["predicted_partners"] == [1467, 1468]
    assert result["expected_unstaged_total"] == 5


def test_vent_fjerner_personen_og_dens_enepartner():
    # 947 er eneste vej til 1468; holdes 947 tilbage, skal 1468 også ud.
    text = _retok(DOC, c.generate_document(DOC), 947, "[VENT]")
    result = c.convert_edited_document(text, DOC)
    assert result["person_ids"] == [927, 937]
    assert result["held_back"] == [947]
    assert result["predicted_partners"] == [1467]  # 937 er stadig en vej
    assert result["expected_unstaged_total"] == 3


def test_vent_beholder_partner_der_naas_via_en_anden_valgt():
    text = _retok(DOC, c.generate_document(DOC), 937, "[VENT]")
    result = c.convert_edited_document(text, DOC)
    assert 1467 in result["predicted_partners"]


def test_alle_vent_giver_tom_publicering():
    text = c.generate_document(DOC)
    for pid in (927, 937, 947):
        text = _retok(DOC, text, pid, "[VENT]")
    result = c.convert_edited_document(text, DOC)
    assert result["person_ids"] == []
    assert result["predicted_partners"] == []
    assert result["expected_unstaged_total"] == 0


# --------------------------------------------------------------------------
# [VENT] der ikke kan honoreres
# --------------------------------------------------------------------------

def test_vent_afvises_naar_den_alligevel_ville_blive_publiceret():
    # RPC'en afstager enhver staged person med familie-kant til id-listen.
    # At acceptere [VENT] her ville lyve om resultatet.
    text = _retok(DOC_KOBLET, c.generate_document(DOC_KOBLET), 950, "[VENT]")
    with pytest.raises(SystemExit) as excinfo:
        c.convert_edited_document(text, DOC_KOBLET)
    assert excinfo.value.code == 2


def test_vent_paa_begge_koblede_accepteres():
    text = c.generate_document(DOC_KOBLET)
    for pid in (950, 951):
        text = _retok(DOC_KOBLET, text, pid, "[VENT]")
    result = c.convert_edited_document(text, DOC_KOBLET)
    assert result["person_ids"] == []
    assert sorted(result["held_back"]) == [950, 951]


# --------------------------------------------------------------------------
# fail-closed
# --------------------------------------------------------------------------

def test_convert_afviser_ukendt_token():
    text = _retok(DOC, c.generate_document(DOC), 927, "[MÅSKE]")
    with pytest.raises(SystemExit) as excinfo:
        c.convert_edited_document(text, DOC)
    assert excinfo.value.code == 2


def test_convert_afviser_redigeret_kontekst():
    text = c.generate_document(DOC).replace("Hedevig Maria", "Hedevig Marie")
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_redigeret_instruktionshoved():
    text = c.generate_document(DOC).replace(
        "Ret KUN tokenet", "Ret hvad du vil i")
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_slettet_linje():
    lines = [l for l in c.generate_document(DOC).split("\n")
             if not l.startswith("[PUBLICÉR]")]
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(lines), DOC)


def test_convert_afviser_duplikeret_pid():
    lines = c.generate_document(DOC).split("\n")
    index = next(i for i, l in enumerate(lines) if c._parse_positional(l))
    duplikeret = lines[:index + 1] + [lines[index]] + lines[index + 1:]
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(duplikeret), DOC)


def test_convert_afviser_tom_selection():
    with pytest.raises(SystemExit):
        c.convert_edited_document("uanset hvad", {"schema_version": "1.0",
                                                  "selected": [],
                                                  "predicted_partners": []})


def test_convert_tillader_kolonneforskydning_ved_kortere_token():
    # [VENT] er kortere end [PUBLICÉR]; kolonnen flytter sig, og det er den
    # ENESTE tilladte afvigelse fra byte-identitet.
    text = _retok(DOC, c.generate_document(DOC), 947, "[VENT]")
    result = c.convert_edited_document(text, DOC)
    assert result["held_back"] == [947]
