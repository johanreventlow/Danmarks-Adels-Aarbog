"""#244 (spec §6): ark til rettelse af skævt gemte ægteskabsnumre. Kun opdigtede navne."""
import pytest

import relation_ordinal_sheet as osh
from decision_sheet_core import SheetError

K1, K2, K3 = ("00000000-0000-0000-0000-00000000000" + c for c in "123")


def row(no, key, stored=2, new=1, book=1, fam=1):
    return {"row_no": no, "interpretation_key": key, "interpretation_version": 2, "spouse_party_version": 1,
            "stored_ordinal": stored, "new_ordinal": new, "book_ordinal": book, "family_id": 7, "family_ordinal": fam,
            "principal_named": {"navn": "Anna Alfa", "foedt": "1770", "post": "V-1"},
            "spouse_named": {"navn": "Bo Beta", "foedt": "1768"}}


ROWS = {"contract": "relation-ordinal-sheet-input-v1", "source_id": 1,
        "rows": [row(1, K1), row(2, K2, stored=1, new=2, book=2, fam=2), row(3, K3, new=None, book=None)]}


def test_render():
    t = osh.render_sheet(ROWS)
    assert f"C {K1} 1 : B" in t and f"C {K2} 1 : B" in t and K3 not in t
    assert "# [1] Forælder: Anna Alfa (f. 1770), post V-1 · Ægtefælle: Bo Beta (f. 1768)" in t
    assert "bogens N°: 1 · gemt → nyt: 2 → 1 · familiens nr.: 1" in t
    assert "Ikke på arket: 1" in t


def test_sql_og_tokens():
    lines = osh.parse_sheet(osh.render_sheet(ROWS).replace(f"C {K2} 1 : B", f"C {K2} 1 : U"))
    sql = osh.decision_sql(lines, ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)
    assert sql.count("red_ret_aegteskabsnummer(") == 1 and f"'{K1}'::uuid, 1," in sql
    assert '"line": 1' in sql and '"basis": "human_sheet"' in sql


@pytest.mark.parametrize("tok", ["R", "S", "b"])
def test_token_afvist(tok):
    lines = osh.parse_sheet(osh.render_sheet(ROWS).replace(f"C {K1} 1 : B", f"C {K1} 1 : {tok}"))
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        osh.check_sheet(lines, ROWS)


def test_linjefejl():
    t = osh.render_sheet(ROWS)
    with pytest.raises(SheetError, match="SHEET_LINES_MISSING"):
        osh.check_sheet(osh.parse_sheet(t.replace(f"C {K2} 1 : B\n", "")), ROWS)
    with pytest.raises(SheetError, match="SHEET_LINE_DUPLICATE"):
        osh.check_sheet(osh.parse_sheet(t + f"C {K1} 1 : B\n"), ROWS)
    with pytest.raises(SheetError, match="SHEET_LINE_UNKNOWN"):
        osh.check_sheet(osh.parse_sheet(t.replace(f"C {K1} 1 : B", f"C {K1} 9 : B")), ROWS)


def test_kontrakt():
    with pytest.raises(SheetError, match="ROWS_CONTRACT_INVALID"):
        osh.render_sheet({**ROWS, "contract": "x"})
