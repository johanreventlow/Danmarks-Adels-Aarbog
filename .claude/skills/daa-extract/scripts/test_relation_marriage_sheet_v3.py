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
                               "previous": {"basis": "web_detail", "note": "kø", "decided_at": "2026-10-13"},
                               "name_text": "Gro von Hak", "clause_text": "Gift 1314 med Gro von Hak.",
                               "clause_is_current": True, "post_text": "Carl C. Gift 1314 med Gro von Hak.",
                               "record_key": "II-9", "page_from": 9, "marriage_ordinal": 1, "principal_person_id": 6,
                               "principal_partners": []}]}


def sheet(m1="S", m2="D", p="D", extra1=""):
    return (f"# ark\nM {K1} 1 : {m1}{extra1}\nM {K2} 1 : {m2}\nP {SP} 1 : {p}\n")


def test_render_viser_skaevt_nummer_hele_posten_og_P():
    out = sh.render_sheet(rows())
    assert "nr. i bogen 1 ≠ nr. i familien 2" in out
    assert "Hele posten:" in out and "Tidligere afgørelse: web_detail, 2026-10-13" in out
    assert f"P {SP} 1 : D" in out


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
