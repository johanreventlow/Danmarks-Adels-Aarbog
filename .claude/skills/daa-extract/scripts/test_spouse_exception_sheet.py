import hashlib
import json
import os
import subprocess
from pathlib import Path

import pytest

import spouse_exception_sheet as ses
from decision_sheet_core import SheetError

P1 = "11111111-1111-4111-8111-111111111111"
P2 = "22222222-2222-4222-8222-222222222222"
C1 = "33333333-3333-4333-8333-333333333333"
RUN = "44444444-4444-4444-8444-444444444444"
I1 = "55555555-5555-4555-8555-555555555555"


def rows():
    return {"contract": "spouse-exception-rows-v1", "source_id": 1,
            "s_rows": [{"source_persona_id": P1, "identity_version": 0, "candidate_id": C1, "run_id": RUN,
                        "candidate_rank": 1, "candidate_tier": "review", "candidate_score": 0.8, "candidate_count": 2,
                        "candidate_person_id": 10, "principal_person_id": 9, "family_id": 7, "family_ordinal": 1,
                        "candidate_display": {"visning_navn": "Bo Beta", "visning_fuldt_navn": None,
                                              "visning_foedt": "1801", "visning_doed": None},
                        "mentions": [{"mention_role": "spouse", "verbatim_text": "Bo\nBeta"}]}],
            "o_rows": [{"interpretation_id": I1, "family_id": 8, "principal_person_id": 11, "spouse_person_id": 12,
                        "book_ordinal": 2, "family_ordinal": 1, "state_sha256": "a" * 64}]}


def test_render_forudfylder_og_holder_linjer_paa_en_linje():
    ark = ses.render_sheet(rows())
    assert f"S {P1} 0 : S" in ark
    assert f"O {I1} 2/1 : F" in ark          # forslag uden forslagsfil: behold familiens
    assert "Bo Beta" in ark and "Bo\nBeta" not in ark


def test_parse_rundtur():
    lines = ses.parse_sheet(ses.render_sheet(rows()))
    assert [(l.kind, l.item_id, l.tok) for l in lines] == [("S", P1, "S"), ("O", I1, "F")]


@pytest.mark.parametrize("bad", ["S {p} 0 : X", "S {p} 0 : S\nS {p} 0 : S", "", "O {i} 2/1 : S"])
def test_afviser_ugyldige_linjer(bad):
    tekst = bad.format(p=P1, i=I1)
    with pytest.raises(SheetError):
        ses.check_identity(ses.parse_sheet(tekst), rows())


def test_afviser_omordning():
    ark = ses.render_sheet(rows())
    s_line = next(l for l in ark.splitlines() if l.startswith("S "))
    o_line = next(l for l in ark.splitlines() if l.startswith("O "))
    byttet = ark.replace(s_line, "@@").replace(o_line, s_line).replace("@@", o_line)
    with pytest.raises(SheetError):
        ses.check_identity(ses.parse_sheet(byttet), rows())


def test_note_citering():
    ark = ses.render_sheet(rows()).replace(f"S {P1} 0 : S", f"S {P1} 0 : S  # O'Brien \\ test")
    sql = ses.sheet_sql(ses.parse_sheet(ark), rows(), sheet_sha256="b" * 64, rows_sha256="c" * 64, source_id=1)
    assert "O''Brien \\ test" in sql


def test_sql_raekkefoelge_og_taelling():
    ark = ses.render_sheet(rows()).replace(f"O {I1} 2/1 : F", f"O {I1} 2/1 : B")
    sql = ses.sheet_sql(ses.parse_sheet(ark), rows(), sheet_sha256="b" * 64, rows_sha256="c" * 64, source_id=1)
    order = [sql.index(x) for x in ("pg_advisory_xact_lock", "private.lock_family_rows", "SPOUSE_SHEET_ROWS_STALE",
                                    "SPOUSE_SHEET_ORDINAL_DRIFT", "SET LOCAL ROLE authenticated",
                                    "red_afgoer_source_persona", "red_set_familie_ordinal", "SHEET_COUNT_MISMATCH", "\nCOMMIT;")]
    assert order == sorted(order)
    assert "ordinal_beholdt" not in sql


def test_sql_A_og_U_skriver_intet():
    ark = ses.render_sheet(rows()).replace(f"S {P1} 0 : S", f"S {P1} 0 : A")
    sql = ses.sheet_sql(ses.parse_sheet(ark), rows(), sheet_sha256="b" * 64, rows_sha256="c" * 64, source_id=1)
    assert "red_afgoer_source_persona" not in sql and "ordinal_beholdt" in sql


def test_sti_uden_for_private_root_afvises(tmp_path):
    root = tmp_path / "priv"; root.mkdir(mode=0o700)
    with pytest.raises(SheetError):
        ses.check_private_path(tmp_path / "andet" / "ark.txt", root)


def test_sti_i_git_arbejdstrae_afvises(tmp_path):
    root = tmp_path / "priv"; root.mkdir(mode=0o700)
    subprocess.run(["git", "init", "-q", str(root / "repo")], check=True)
    with pytest.raises(SheetError):
        ses.check_private_path(root / "repo" / "ark.txt", root)


def test_cli_hashbinding(tmp_path):
    root = tmp_path / "priv"; root.mkdir(mode=0o700)
    rows_path = root / "rows.json"
    rows_path.write_text(json.dumps(rows()) + "\n", encoding="utf-8")
    ark = root / "ark.txt"
    script = Path(ses.__file__)
    run = lambda *a: subprocess.run(["python3", str(script), *a, "--private-root", str(root)], capture_output=True, text=True)
    assert run("render", "--rows", str(rows_path), "--out", str(ark)).returncode == 0
    assert oct(ark.stat().st_mode & 0o777) == "0o600"
    rows_sha = hashlib.sha256(rows_path.read_bytes()).hexdigest()
    forkert = run("sql", "--sheet", str(ark), "--approved-sha256", "0" * 64, "--rows", str(rows_path),
                  "--expect-rows-sha256", rows_sha, "--source", "1", "--out", str(root / "a.sql"))
    assert forkert.returncode == 1 and not (root / "a.sql").exists()
    ok = run("sql", "--sheet", str(ark), "--approved-sha256", hashlib.sha256(ark.read_bytes()).hexdigest(),
             "--rows", str(rows_path), "--expect-rows-sha256", rows_sha, "--source", "1", "--out", str(root / "a.sql"))
    assert ok.returncode == 0 and "Bo Beta" not in ok.stdout + ok.stderr
