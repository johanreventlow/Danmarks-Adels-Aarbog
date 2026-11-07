"""Trin 5b 2b-iii (spec §6): børnearket. Kun opdigtede navne."""
import pytest

import relation_child_sheet as cs
from decision_sheet_core import SheetError

K1, K2, K3 = ("00000000-0000-0000-0000-00000000000" + c for c in "123")


def row(no, key, ok=True, afv=(), brud=()):
    return {"row_no": no, "interpretation_key": key, "interpretation_version": 1, "raw": "3 sønner: Andet slægtled, V, nr. 2-4",
            "rule": {"ok": ok, "brud": list(brud), "afvigelser": list(afv), "family_id": 7,
                     "ref": {"count": 3, "nr_from": 2, "nr_to": 4}},
            "principal_named": {"navn": "Ole Alfa", "foedt": "1770", "post": "V-1"},
            "children_named": [{"person_id": 1, "navn": "Ib Alfa", "foedt": "1801", "linje": "V", "nr": 2, "kuld": "V", "gen_local": 2}]}


ROWS = {"contract": "relation-child-sheet-input-v1", "source_id": 1,
        "rows": [row(1, K1), row(2, K2, afv=["A3_usikker"]), row(3, K3, ok=False, brud=["H3_familie"])]}


def test_render_blokke_og_forudfyldning():
    t = cs.render_sheet(ROWS)
    assert f"C {K1} 1 : B" in t and f"C {K2} 1 : B" in t and K3 not in t
    assert t.index(K1) < t.index("# DEL 2 —") < t.index(K2)
    assert "Ikke på arket: 1" in t


def test_render_er_til_at_navigere():
    # projektejeren 2026-10-20: nummererede linjer med forælderen, afvigelser i almindelige ord, vejledning øverst
    t = cs.render_sheet(ROWS)
    assert "Sådan" in t.split("DEL 1")[0]
    assert "[1] Forælder: Ole Alfa (f. 1770), post V-1" in t and "[2] Forælder: Ole Alfa" in t
    assert "databasen: 1 barn" in t                          # ental, ikke »1 børn«
    assert "bogen er selv usikker" in t and "A3_usikker" not in t
    assert "forælderen har børn i flere ægteskaber" in t and "H3_familie" not in t


def test_beslutnings_sql_b_r_u():
    t = cs.render_sheet(ROWS).replace(f"C {K2} 1 : B", f"C {K2} 1 : R")
    sql = cs.decision_sql(cs.parse_sheet(t), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)
    assert sql.count("red_afgoer_relation_interpretation(") == 2
    assert f"'{K1}'::uuid, 1, 'same', NULL" in sql and f"'{K2}'::uuid, 1, 'rejected', NULL" in sql
    assert '"line": 1' in sql and '"basis": "human_sheet"' in sql
    t_u = t.replace(f"C {K1} 1 : B", f"C {K1} 1 : U")
    assert cs.decision_sql(cs.parse_sheet(t_u), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64).count("red_afgoer_relation_interpretation(") == 1


@pytest.mark.parametrize("edit,code", [
    (lambda t: t.replace(f"C {K1} 1 : B", f"C {K1} 1 : S"), "SHEET_TOKEN_NOT_ALLOWED"),
    (lambda t: t + f"C {K3} 1 : B\n", "SHEET_LINE_UNKNOWN"),                 # Review Focus 4: H-brud på arket
    (lambda t: t.replace(f"C {K1} 1 : B\n", ""), "SHEET_LINES_MISSING"),
    (lambda t: t + f"C {K1} 1 : B\n", "SHEET_LINE_DUPLICATE"),
    (lambda t: t.replace(f"C {K1} 1 : B", f"C {K1} 2 : B"), "SHEET_LINE_UNKNOWN"),
])
def test_ark_fejl(edit, code):
    with pytest.raises(SheetError, match=code):
        cs.decision_sql(cs.parse_sheet(edit(cs.render_sheet(ROWS))), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)


def test_nogleafgraensning_udelader_raekker_uden_for_listen():
    sub = cs.select_rows(ROWS, [K1, K3])
    assert [r["interpretation_key"] for r in sub["rows"]] == [K1, K3]
    t = cs.render_sheet(sub)
    assert K1 in t and K2 not in t and "Ikke på arket: 1" in t
    sql = cs.decision_sql(cs.parse_sheet(t), sub, sheet_sha256="a" * 64, rows_sha256=cs.selected_rows_sha256(sub))
    assert sql.count("red_afgoer_relation_interpretation(") == 1 and K2 not in sql
    assert cs.selected_rows_sha256(sub) != cs.selected_rows_sha256(ROWS)
    assert "NULL" in sql                                   # børn kaldes med p_family_id NULL


def test_nogleafgraensning_ukendt_nogle_og_fil():
    with pytest.raises(SheetError, match="CHILD_KEY_UNKNOWN"):
        cs.select_rows(ROWS, ["00000000-0000-0000-0000-0000000000ff"])
    assert cs.load_keys(f"{K1}\n\n# x\n{K2} # y\n") == [K1, K2]
    for bad in ("", "x\n", f"{K1}\n{K1}\n"):
        with pytest.raises(SheetError, match="KEYS_FILE_INVALID"):
            cs.load_keys(bad)
