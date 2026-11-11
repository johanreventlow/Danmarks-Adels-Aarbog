"""Trin 5b 2b-ii runde 2 (spec §17.6): ark v3. Kun opdigtede navne."""
import json

import pytest

import relation_marriage_sheet_v3 as sh
from decision_sheet_core import SheetError

K1, K2 = "11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"
SP = "33333333-3333-3333-3333-333333333333"


def mrow(key, text, raw, partners=(), ordinal=1):
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": "relation.marriage", "raw": raw,
            "record_key": "II-1", "marriage_ordinal": ordinal, "supporting_count": 1, "principal_ok": True,
            "principal_person_id": 5, "principal_partners": list(partners), "post_text": "Anna A. " + text,
            "clauses": [{"observation_id": "44444444-4444-4444-4444-444444444444", "clause_set_seq": 1,
                         "clause_set_sha256": "a" * 64, "verbatim_text": text, "post_char_from": 8, "post_char_to": 8 + len(text)}]}


def rows():
    return {"contract": "relation-persona-v3-input", "source_id": 1, "deceased_cutoff_year": 1906,
            "rows": [mrow(K1, "Gift 1890 med Ida komtesse Dal til Ørum.", "Gift med Ida komtesse Dal til Ørum",
                          [{"person_id": 7, "family_id": 3, "ordinal": 2, "navn": "Ida Dal"}]),
                     mrow(K2, "Gift 1890 med Ole Dal, datter af Ole Dal.", "Gift med Ole Dal, datter af Ole Dal")],
            "redecide_rows": [{"source_persona_id": SP, "identity_version": 1,
                               "previous": {"basis": "web_detail", "note": "kø"},
                               "name_text": "Gro von Hak", "clause_text": "Gift 1314 med Gro von Hak.",
                               "clause_is_current": True, "post_text": "Carl C. Gift 1314 med Gro von Hak.",
                               "record_key": "II-9", "page_from": 9, "marriage_ordinal": 1, "principal_person_id": 6,
                               "principal_partners": []}]}


def sheet(m1="S", m2="D", p="D", extra1=""):
    return (f"# ark\nM {K1} 1 : {m1}{extra1}\nM {K2} 1 : {m2}\nP {SP} 1 : {p}\n")


def test_render_viser_skaevt_nummer_hele_posten_og_P():
    out = sh.render_sheet(rows())
    assert "nr. i bogen 1 ≠ nr. i familien 2" in out
    assert "Hele posten:" in out and "Tidligere afgørelse: web_detail · note: »kø«" in out
    assert f"P {SP} 1 : D" in out


def test_P_kort_uden_dato():
    # Indholds-id (#151, spec §4 pkt. 3): arkets hash indgår i alle v3-payloads; en dato for den tidligere
    # afgørelse ville gøre arket afhængigt af kørselsdagen.
    import re
    out = sh.render_sheet(rows())
    p_card = out[out.index("Tidligere afgørelse"):].splitlines()[0]
    assert not re.search(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", p_card) and "None" not in p_card


def test_navnerettelse_giver_sheet_basis_og_hash_i_manifest():
    lines = sh.parse_sheet(sheet(extra1=" navn: »Ida komtesse Dal«"))
    m = sh.persona_manifest(lines, rows(), sheet_sha256="c" * 64)
    e = m["authorized_elements"]["relation-persona:" + K1]
    assert e["profile"] == "relation-persona-2018-20-v3" and e["name_basis"] == "sheet"
    assert e["sheet_sha256"] == "c" * 64 and e["sheet_line"] == 1
    assert m["authorized_elements"]["relation-persona:" + K2]["name_basis"] == "rule"


def test_navn_to_gange_afvises():
    # K2's klausul rummer »Ole Dal« to gange (rækken er uændret, så vinduet findes og navnestarten nås)
    r = rows()
    assert sh.propose(r["rows"][1], 1906)["tok"] == "D"
    with pytest.raises(SheetError, match="SHEET_NAME_INVALID"):
        sh.check_sheet(sh.parse_sheet(sheet(m2="D").replace(f"M {K2} 1 : D", f"M {K2} 1 : D navn: »Ole Dal«")), r)


def test_navn_ved_I_eller_U_afvises():
    with pytest.raises(SheetError, match="SHEET_NAME_INVALID"):
        sh.check_sheet(sh.parse_sheet(sheet(m1="U", extra1=" navn: »Ida Dal«")), rows())


def test_U_til_S_kun_naar_reglen_bekraefter():
    # K2 har ingen partner ⇒ S er ikke tilladt, heller ikke med rettet navn
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        sh.check_sheet(sh.parse_sheet(sheet(m2="S")), rows())


def test_S_til_N_er_ikke_tilladt():
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        sh.check_sheet(sh.parse_sheet(sheet(m1="N")), rows())


def test_P_D_kun_naar_reglen_siger_D():
    r = rows()
    r["redecide_rows"][0]["clause_text"] = "Gift 1950 med Gro von Hak."
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        sh.check_sheet(sh.parse_sheet(sheet()), r)


def test_P_version_skal_passe():
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        sh.check_sheet(sh.parse_sheet(sheet().replace(f"P {SP} 1", f"P {SP} 2")), rows())


def test_identitetsscript_P_bruger_raekkefilens_version_og_deceased():
    lines = sh.parse_sheet(sheet())
    sql = sh.identity_sql(lines, rows(), sheet_sha256="c" * 64, rows_sha256="d" * 64)
    assert f"red_afgoer_source_persona('{SP}'::uuid, 1, 'new_person_needed', NULL," in sql
    assert '"clause_years": [1314]' in sql and '"rule": "aarstal-120-v1"' in sql and "erstatter version 1" in sql
    assert sql.count("red_afgoer_source_persona(") == 3


def test_P_N_skriver_intet():
    sql = sh.identity_sql(sh.parse_sheet(sheet(p="N")), rows(), sheet_sha256="c" * 64, rows_sha256="d" * 64)
    assert SP not in sql


# --- Trin 6d-3: arket læser profilen ----------------------------------------------------------------------------------
from pathlib import Path

HERE = Path(__file__).resolve().parent
P_1939 = HERE.parent / "profiles" / "relation-persona-1939.json"
GOLDEN = HERE / "fixtures" / "relation-sheet-v3-default-golden.json"


def test_default_profile_unchanged():
    # Facit = HEAD-kodens (før 6d-3) output for denne fixture, fanget én gang og gemt; ikke en ny kørsel af koden.
    gold = json.loads(GOLDEN.read_text(encoding="utf-8"))
    lines = sh.parse_sheet(sheet(extra1=" navn: »Ida komtesse Dal«"))
    assert sh.render_sheet(rows()) == gold["render"]
    assert sh.persona_manifest(lines, rows(), sheet_sha256="c" * 64) == gold["manifest"]
    assert sh.identity_sql(lines, rows(), sheet_sha256="c" * 64, rows_sha256="d" * 64) == gold["identity_sql"]
    # og med 2018-20-profilfilen eksplicit
    from relation_persona_extract_v3 import load_profile
    p = load_profile(HERE.parent / "profiles" / "relation-persona-2018-20.json")
    assert sh.render_sheet(rows(), p) == gold["render"]
    assert sh.persona_manifest(lines, rows(), sheet_sha256="c" * 64, profile=p) == gold["manifest"]


def raw_rows():
    t = "Gift 1890 med Ida Bran-\ndenburg, f. 1801."
    return {"contract": "relation-persona-v3-input", "source_id": 3, "deceased_cutoff_year": 1906,
            "rows": [mrow(K1, t, "Gift med Ida Brandenburg")], "redecide_rows": []}


def test_profile_1939_manifest():
    from relation_persona_extract_v3 import load_profile
    p = load_profile(P_1939)
    r = raw_rows()
    # standardprofilen (folded): orddelingen giver intet vindue; 1939-profilen (raw): D-forslag
    assert sh.propose(r["rows"][0], 1906)["reason"] == "intet_vindue"
    assert "(intet_vindue)" in sh.render_sheet(r)
    out = sh.render_sheet(r, p)
    assert "Forslag: D (aldersregel)" in out
    lines = sh.parse_sheet(f"M {K1} 1 : D\n")
    m = sh.persona_manifest(lines, r, sheet_sha256="c" * 64, profile=p)
    e = m["authorized_elements"]["relation-persona:" + K1]
    assert e["profile"] == "relation-persona-1939-v1" and e["name_basis"] == "rule"
    t = r["rows"][0]["clauses"][0]["verbatim_text"]
    assert t[e["name_from"]:e["name_to"]] == "Ida Bran-\ndenburg"
    # uden profil afvises D (reglen finder intet vindue)
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        sh.persona_manifest(lines, r, sheet_sha256="c" * 64)


def test_profile_uden_v3_aegteskabsform_afvises():
    with pytest.raises(SheetError, match="PROFILE_MARRIAGE_FORM_INVALID"):
        sh.render_sheet(rows(), {"relation_profile": "x", "predicate_forms": {"relation.marriage": "v1"}, "text_form": "folded"})
