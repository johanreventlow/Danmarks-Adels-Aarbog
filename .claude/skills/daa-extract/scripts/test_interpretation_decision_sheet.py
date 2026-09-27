import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest
from interpretation_decision_sheet import (Decision, SheetError, check_identity, decision_sql,
                                           parse_sheet, render_sheet)

U1 = "11111111-1111-4111-8111-111111111111"
U2 = "22222222-2222-4222-8222-222222222222"
U3 = "33333333-3333-4333-8333-333333333333"
H = "ab" * 32
SCRIPT = str(Path(__file__).resolve().parent / "interpretation_decision_sheet.py")


def row(uid, pred="person.death", value="1850"):
    return {"interpretation_id": uid, "version": 1, "record_key": "I-1", "predicate": pred,
            "value_text": value, "confidence": 0.9, "persona_role": "principal",
            "cited": [{"ordinal": 1, "text": "† 1850", "flags": []}]}


def test_render_forudfylder_kun_fra_tidligere_dom():
    ark = render_sheet([row(U1), row(U2, value="1851")], {("I-1", "person.death", "1850"): "J"})
    assert f"D {U1} 1 : A" in ark
    assert f"D {U2} 1 : _" in ark


def test_render_viser_reviewsignal_fra_forespoergbare_felter():
    r = row(U1)
    r["confidence"] = 0.5
    r["cited"][0]["flags"] = ["unknown_abbreviation"]
    ark = render_sheet([r, row(U2, value="1851")], {})
    assert "se nærmere: lav confidence, klausulflag" in ark
    assert "se nærmere: nej" in ark


def test_parse_laeser_beslutninger_og_noter():
    ark = f"# kommentar\nD {U1} 1 : A\nD {U2} 1 : R # forkert år\n"
    assert parse_sheet(ark) == [Decision(U1, 1, "accepted", "", 2),
                                Decision(U2, 1, "rejected", "forkert år", 3)]


def test_uafgjort_stopper_med_linjenumre():
    with pytest.raises(SheetError, match="SHEET_UNDECIDED lines=2"):
        parse_sheet(f"# x\nD {U1} 1 : _\n")


def test_ukendt_token_og_dublet_stopper():
    with pytest.raises(SheetError, match="SHEET_TOKEN_INVALID"):
        parse_sheet(f"D {U1} 1 : X\n")
    with pytest.raises(SheetError, match="SHEET_DUPLICATE"):
        parse_sheet(f"D {U1} 1 : A\nD {U1} 1 : R\n")


def test_ugyldig_og_indrykket_linje_stopper():
    with pytest.raises(SheetError, match="SHEET_LINE_INVALID"):
        parse_sheet("D ikke-en-uuid 1 : A\n")
    with pytest.raises(SheetError, match="SHEET_LINE_INVALID line=2"):
        parse_sheet(f"D {U1} 1 : A\n  D {U2} 1 : R\n")


def test_slettet_linje_fanges_af_identitetstjekket():
    with pytest.raises(SheetError, match="mangler=1 ekstra=0"):
        check_identity(parse_sheet(f"D {U1} 1 : A\n"), [row(U1), row(U2)])


def test_ombyttet_uuid_fanges_af_identitetstjekket():
    with pytest.raises(SheetError, match="mangler=1 ekstra=1"):
        check_identity(parse_sheet(f"D {U1} 1 : A\nD {U3} 1 : R\n"), [row(U1), row(U2)])


def test_aendret_version_fanges_af_identitetstjekket():
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        check_identity(parse_sheet(f"D {U1} 2 : A\n"), [row(U1)])


def test_sql_er_en_transaktion_med_taelling_og_citering():
    sql = decision_sql([Decision(U1, 1, "accepted", "o'hara", 2)], sheet_sha256=H, rows_sha256=H)
    assert sql.startswith("\\set ON_ERROR_STOP on\nBEGIN;")
    assert "SET LOCAL ROLE authenticated;" in sql
    assert "set_config('request.jwt.claim.sub', :'actor', true)" in sql
    assert f"red_decide_interpretation('{U1}'::uuid, 1, 'accepted'," in sql
    assert "o''hara" in sql and '"rows_sha256"' in sql
    assert "DECISION_COUNT_MISMATCH" in sql
    assert sql.rstrip().endswith("COMMIT;")


def test_sql_kraever_begge_hashes():
    with pytest.raises(SheetError, match="SHEET_HASH_REQUIRED"):
        decision_sql([Decision(U1, 1, "accepted", "", 1)], sheet_sha256="", rows_sha256=H)
    with pytest.raises(SheetError, match="SHEET_HASH_REQUIRED"):
        decision_sql([Decision(U1, 1, "accepted", "", 1)], sheet_sha256=H, rows_sha256="")


def _cli(tmp_path, ark_tekst, godkend_foer=None, rows=None, rows_hash=None):
    rows_fil = tmp_path / "rows.json"
    rows_fil.write_text(json.dumps(rows or [row(U1)]), encoding="utf-8")
    ark = tmp_path / "ark.txt"
    ark.write_text(godkend_foer or ark_tekst, encoding="utf-8")
    godkendt = hashlib.sha256(ark.read_bytes()).hexdigest()
    ark.write_text(ark_tekst, encoding="utf-8")
    p = subprocess.run([sys.executable, SCRIPT, "sql", "--sheet", str(ark),
                        "--approved-sha256", godkendt, "--rows", str(rows_fil),
                        "--expect-rows-sha256",
                        rows_hash or hashlib.sha256(rows_fil.read_bytes()).hexdigest(),
                        "--out", str(tmp_path / "d.sql")], capture_output=True, text=True)
    return p, tmp_path / "d.sql"


def test_cli_afviser_aendret_ark(tmp_path):
    p, sql = _cli(tmp_path, f"D {U1} 1 : R\n", godkend_foer=f"D {U1} 1 : A\n")
    assert p.returncode == 1 and "SHEET_HASH_MISMATCH" in p.stdout and not sql.exists()


def test_cli_afviser_aendret_raekkefil(tmp_path):
    p, sql = _cli(tmp_path, f"D {U1} 1 : A\n", rows_hash="0" * 64)
    assert p.returncode == 1 and "ROWS_HASH_MISMATCH" in p.stdout and not sql.exists()


def test_cli_skriver_sql_for_komplet_ark(tmp_path):
    p, sql = _cli(tmp_path, f"D {U1} 1 : A\n")
    assert p.returncode == 0 and "SQL_OK afgørelser=1" in p.stdout and sql.exists()


def test_ombyttede_beslutningslinjer_fanges():
    """4.5-kodereview, fund 3: to gyldige D-linjer, der bytter plads, bytter også
    hvilken kommentarblok mennesket afgjorde ud fra."""
    rows = [row(U1), row(U2, value="1851")]
    with pytest.raises(SheetError, match="SHEET_ORDER_MISMATCH line=1"):
        check_identity(parse_sheet(f"D {U2} 1 : A\nD {U1} 1 : R\n"), rows)


def test_renderet_ark_i_egen_orden_godkendes():
    rows = [row(U2, value="1851"), row(U1)]
    prior = {("I-1", "person.death", "1850"): "J", ("I-1", "person.death", "1851"): "N"}
    check_identity(parse_sheet(render_sheet(rows, prior)), rows)
