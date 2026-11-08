"""Trin 6c-3: forælderarket. Kun syntetiske id'er; ingen navne findes i rækkefilen."""
import hashlib
import json

import pytest

import relation_child_sheet as cs
import relation_parent_sheet as ps
from decision_sheet_core import SheetError

K1, K2, K3 = ("00000000-0000-0000-0000-00000000000" + c for c in "123")
P1 = "11111111-1111-1111-1111-111111111111"


def cand(fam):
    return {"family_id": fam, "counterpart_persona_id": P1, "counterpart_person_id": 40 + fam}


def row(no, key, cands):
    return {"row_no": no, "interpretation_key": key, "interpretation_version": 1,
            "principal_persona_id": P1, "candidates": cands}


ROWS = {"contract": "relation-parent-sheet-input-v1", "source_id": 1,
        "rows": [row(1, K1, [cand(7)]), row(2, K2, []), row(3, K3, [cand(7), cand(8)])]}
SHA = {"s": "a" * 64}


def test_render_forudfylder_b_kun_ved_entydig_familie():
    t = ps.render_sheet(ROWS)
    assert f"P {K1} 1 : B" in t and f"P {K2} 1 : U" in t and f"P {K3} 1 : U" in t
    assert "rows_sha256: " + ps.selected_rows_sha256(ROWS) in t


# Hardkodet: ændres arkformatet eller den kanoniske JSON, skal tallene ændres bevidst.
SHEET_SHA = "1e4b49eab9871bf4f048f370dc60f252a3218dc745560363b9bb14e63dd3ef76"
ROWS_SHA = "4880e24e76c30d6b421ea762eccdbbfad1522b6b5a5c8bc160513f4657eb3991"


def test_hardkodede_hashes():
    assert hashlib.sha256(ps.render_sheet(ROWS).encode()).hexdigest() == SHEET_SHA
    assert ps.selected_rows_sha256(ROWS) == ROWS_SHA


def test_family_id_skal_vaere_int():
    for bad in ("7; DROP", True, 7.0):
        rows = {**ROWS, "rows": [row(1, K1, [{**cand(7), "family_id": bad}])]}
        t = ps.render_sheet(rows)
        with pytest.raises(SheetError, match="PARENT_FAMILY_ID_INVALID"):
            ps.decision_sql(ps.parse_sheet(t), rows, sheet_sha256="a" * 64, rows_sha256="b" * 64)


def test_sql_round_trip_hardkodet_sha():
    t = ps.render_sheet(ROWS).replace(f"P {K2} 1 : U", f"P {K2} 1 : R")
    sql = ps.decision_sql(ps.parse_sheet(t), ROWS, sheet_sha256=SHEET_SHA, rows_sha256=ROWS_SHA)
    assert f'"rows_sha256": "{ROWS_SHA}"' in sql and f"forælderark {SHEET_SHA[:12]}" in sql
    assert sql.count("red_afgoer_relation_interpretation(") == 2
    assert f"'{K1}'::uuid, 1, 'same', 7," in sql and f"'{K2}'::uuid, 1, 'rejected', NULL," in sql
    assert '"basis": "human_sheet"' in sql and '"line": 1' in sql and '"rows_sha256": "' in sql


@pytest.mark.parametrize("key", [K2, K3])
def test_b_uden_entydig_familie_afvist(key):
    t = ps.render_sheet(ROWS).replace(f"P {key} 1 : U", f"P {key} 1 : B")
    with pytest.raises(SheetError, match="PARENT_FAMILY_NOT_UNIQUE"):
        ps.decision_sql(ps.parse_sheet(t), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)


def test_u_giver_intet_kald_og_r_paa_tvetydig_er_ok():
    t = ps.render_sheet(ROWS).replace(f"P {K3} 1 : U", f"P {K3} 1 : R")
    sql = ps.decision_sql(ps.parse_sheet(t), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)
    assert f"'{K3}'::uuid, 1, 'rejected', NULL" in sql and f"'{K2}'" not in sql


@pytest.mark.parametrize("edit,code", [
    (lambda t: t.replace(f"P {K1} 1 : B", f"P {K1} 1 : S"), "SHEET_TOKEN_NOT_ALLOWED"),
    (lambda t: t + f"P {K1} 1 : B\n", "SHEET_LINE_DUPLICATE"),
    (lambda t: t.replace(f"P {K1} 1 : B", f"P {K1} 2 : B"), "SHEET_LINE_UNKNOWN"),
    (lambda t: t.replace(f"P {K1} 1 : B\n", ""), "SHEET_LINES_MISSING"),
])
def test_ark_fejl(edit, code):
    with pytest.raises(SheetError, match=code):
        ps.decision_sql(ps.parse_sheet(edit(ps.render_sheet(ROWS))), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)


def test_cli_round_trip_og_afgraensning(tmp_path, capsys):
    root = tmp_path / ".private"
    root.mkdir()
    rows_f, keys_f = root / "rows.json", tmp_path / "keys.txt"
    rows_f.write_text(json.dumps(ROWS), encoding="utf-8")
    keys_f.write_text(f"{K1}\n# kommentar\n{K2}\n", encoding="utf-8")
    sheet = root / "sheet.txt"
    base = ["--rows", str(rows_f), "--private-root", str(root)]
    assert ps.main(["render", *base, "--interpretation-keys", str(keys_f), "--out", str(sheet)]) == 0
    text = sheet.read_text(encoding="utf-8")
    assert K1 in text and K2 in text and K3 not in text
    out = root / "d.sql"
    sha = hashlib.sha256(sheet.read_bytes()).hexdigest()
    assert ps.main(["sql", *base, "--sheet", str(sheet), "--approved-sha256", sha, "--out", str(out)]) == 0
    printed = capsys.readouterr().out
    assert "SQL_OK b=1 r=0 u=1" in printed and K1 not in printed
    sub = {**ROWS, "rows": ROWS["rows"][:2]}
    assert ps.selected_rows_sha256(sub) in out.read_text(encoding="utf-8")
    # ændret ark ≠ godkendt hash
    sheet.write_text(text.replace(f"P {K1} 1 : B", f"P {K1} 1 : R"), encoding="utf-8")
    assert ps.main(["sql", *base, "--sheet", str(sheet), "--approved-sha256", sha, "--out", str(out)]) == 1


def test_ark_med_rows_hash_der_ikke_matcher_afvises():
    t = ps.render_sheet(ROWS).replace(ps.selected_rows_sha256(ROWS), "c" * 64)
    with pytest.raises(SheetError, match="ROWS_HASH_MISMATCH"):
        ps.sheet_rows(ps.parse_sheet(t), t, ROWS)


def test_ukendt_nogle_i_noglefil_afvises(tmp_path):
    with pytest.raises(SheetError, match="CHILD_KEY_UNKNOWN"):
        cs.select_rows(ROWS, [K1, "00000000-0000-0000-0000-0000000000ff"])
