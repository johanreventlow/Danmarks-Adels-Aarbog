import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest
from identity_decision_sheet import (IdDecision, SheetError, check_identity, check_render, decision_sql,
                                     parse_sheet, render_sheet, sheet_order)

P1 = "11111111-1111-4111-8111-111111111111"
P2 = "22222222-2222-4222-8222-222222222222"
C1 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
RUN = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
H = "ab" * 32
SCRIPT = str(Path(__file__).resolve().parent / "identity_decision_sheet.py")


def row(pid, cands=True, tier="auto", score=0.93):
    return {"source_persona_id": pid, "version": 0, "source_id": 1, "persona_key": "k", "record_key": "I-1",
            "mention_role": "principal", "name": "Anna Test", "name_origin": "accepted_interpretation",
            "interpretations": [{"predicate": "person.birth", "status": "proposed", "value_text": "1801"}],
            "run_id": RUN if cands else None,
            "candidates": [{"candidate_id": C1, "rank": 1, "person_id": 42, "person_name": "Anna Kanon",
                            "born": "1801", "died": "1860", "score": score, "tier": tier,
                            "signals": ["name", "birth"]}] if cands else []}


def test_render_sorterer_sikreste_først_og_forudfylder_intet():
    ark = render_sheet([row(P2, tier="review", score=0.75), row(P1)])
    assert ark.index(P1) < ark.index(P2)
    assert f"D {P1} 0 : _" in ark and f"D {P2} 0 : _" in ark
    assert "1: person 42" in ark


def test_render_viser_ingen_kandidat():
    assert "ingen kandidat" in render_sheet([row(P1, cands=False)])


def test_parse_alle_tokens():
    ark = (f"D {P1} 0 : 1 # fulgt\nD {P2} 3 : P 4711\n"
           f"D 33333333-3333-4333-8333-333333333333 0 : X\n"
           f"D 44444444-4444-4444-8444-444444444444 0 : N # findes ikke\n"
           f"D 55555555-5555-4555-8555-555555555555 1 : U\n")
    d = parse_sheet(ark)
    assert d[0] == IdDecision(P1, 0, "same", None, 1, "fulgt", 1)
    assert d[1] == IdDecision(P2, 3, "same", 4711, None, "", 2)
    assert [x.action for x in d[2:]] == ["different", "new_person_needed", "unresolved"]


def test_uafgjort_og_ukendt_token_stopper():
    with pytest.raises(SheetError, match="SHEET_UNDECIDED lines=1"):
        parse_sheet(f"D {P1} 0 : _\n")
    with pytest.raises(SheetError, match="SHEET_TOKEN_INVALID"):
        parse_sheet(f"D {P1} 0 : A\n")


def test_ombyttet_og_slettet_linje_fanges():
    rows = [row(P1), row(P2, tier="review", score=0.75)]
    with pytest.raises(SheetError, match="SHEET_ORDER_MISMATCH"):
        check_identity(parse_sheet(f"D {P2} 0 : X\nD {P1} 0 : X\n"), rows)
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        check_identity(parse_sheet(f"D {P1} 0 : X\n"), rows)


def test_kandidat_token_uden_kandidat_stopper():
    rows = [row(P1, cands=False)]
    with pytest.raises(SheetError, match="SHEET_CANDIDATE_MISSING line=1"):
        decision_sql(parse_sheet(f"D {P1} 0 : 1\n"), rows, sheet_sha256=H, rows_sha256=H)


def test_sql_binder_kandidat_ark_og_kørsel():
    rows = [row(P1)]
    sql = decision_sql(parse_sheet(f"D {P1} 0 : 1 # o'hara\n"), rows, sheet_sha256=H, rows_sha256=H)
    assert sql.startswith("\\set ON_ERROR_STOP on\nBEGIN;")
    # aktualiteten afgøres atomisk af RPC'en (Task 3); arket sender kørslen med kandidaten
    assert '"run_id": "' + RUN + '"' in sql and "SHEET_CANDIDATE_RUN_STALE" not in sql
    assert f"red_afgoer_source_persona('{P1}'::uuid, 0, 'same', 42," in sql
    assert '"candidate_id": "' + C1 + '"' in sql and '"basis": "human_sheet"' in sql
    assert "o''hara" in sql and "DECISION_COUNT_MISMATCH" in sql and sql.rstrip().endswith("COMMIT;")


def _ark(rows, tok="1"):
    return render_sheet(rows).replace(" : _", f" : {tok}")


def test_rettet_kandidatlinje_stopper():
    rows = [row(P1)]
    with pytest.raises(SheetError, match="SHEET_RENDER_MISMATCH line="):
        check_render(_ark(rows).replace("1: person 42", "1: person 99"), rows)
    for gammel, ny in [("Anna Kanon", "Anna Anden"), ("score 0.93", "score 0.99"), ("  auto  ", "  review  ")]:
        with pytest.raises(SheetError, match="SHEET_RENDER_MISMATCH"):
            check_render(_ark(rows).replace(gammel, ny), rows)
    with pytest.raises(SheetError, match="SHEET_RENDER_MISMATCH"):   # slettet/flyttet kommentarlinje
        check_render("".join(l for l in _ark(rows).splitlines(keepends=True) if "1: person" not in l), rows)
    check_render(_ark(rows).replace(" : 1", " : 1 # note"), rows)   # token og note må ændres


def test_cli_rettet_kandidatlinje_stopper(tmp_path):
    p, out = _cli(tmp_path, _ark([row(P1)]).replace("person 42", "person 99"))
    assert p.returncode == 1 and "SHEET_RENDER_MISMATCH" in p.stdout and not out.exists()


def _cli(tmp_path, ark, godkend=None, rows=None):
    rf = tmp_path / "rows.json"; rf.write_text(json.dumps(rows or [row(P1)]), encoding="utf-8")
    af = tmp_path / "ark.txt"; af.write_text(godkend or ark, encoding="utf-8")
    sha = hashlib.sha256(af.read_bytes()).hexdigest(); af.write_text(ark, encoding="utf-8")
    p = subprocess.run([sys.executable, SCRIPT, "sql", "--sheet", str(af), "--approved-sha256", sha,
                        "--rows", str(rf), "--expect-rows-sha256", hashlib.sha256(rf.read_bytes()).hexdigest(),
                        "--out", str(tmp_path / "d.sql")], capture_output=True, text=True)
    return p, tmp_path / "d.sql"


def test_cli_ændret_ark_stopper(tmp_path):
    p, out = _cli(tmp_path, _ark([row(P1)], "X"), godkend=_ark([row(P1)], "1"))
    assert p.returncode == 1 and "SHEET_HASH_MISMATCH" in p.stdout and not out.exists()


def test_cli_komplet_ark(tmp_path):
    p, out = _cli(tmp_path, _ark([row(P1)]))
    assert p.returncode == 0 and "SQL_OK afgørelser=1" in p.stdout and out.exists()
