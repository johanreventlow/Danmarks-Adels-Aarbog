import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

import identity_queue_sheet as iqs
from decision_sheet_core import SheetError

P1 = "11111111-1111-4111-8111-111111111111"
P2 = "22222222-2222-4222-8222-222222222222"
P3 = "33333333-3333-4333-8333-333333333333"
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def detail(pid, ver=1, name="Bo Beta"):
    return {"persona": {"source_persona_id": pid, "version": ver, "source_id": 1, "persona_key": "a-1#rel", "decision_status": "proposed",
                        "canonical_person_id": None},
            "review_reason": "no_candidate", "family_context": {"marriage_ordinal": 1},
            "mentions": [{"mention_role": "spouse", "verbatim_text": name}],
            "principal_partners": [{"name": "Partner Navn", "born": 1800, "died": None, "person_id": 9, "family_id": 7, "ordinal": 1}],
            "candidates": [{"rank": 1, "person_name": "Kandidat Navn", "born": None, "died": 1860, "person_id": 10,
                            "tier": "none", "score": 0.4}]}


def details():
    # Bevidst usorteret: arket sorterer efter persona-id.
    return [detail(P3, 2), detail(P1, 0), detail(P2, 1)]


def answered(text: str, answers: dict[str, str]) -> str:
    out = []
    for line in text.splitlines():
        m = re.match(rf"^Q ({UUID.pattern}) ([0-9]+) : _ # $", line)
        out.append(f"Q {m.group(1)} {m.group(2)} : {answers[m.group(1)]}" if m else line)
    return "\n".join(out) + "\n"


def sheet_and_sql(answers, dets=None):
    dets = details() if dets is None else dets
    text = answered(iqs.render_sheet(dets), answers)
    sh = hashlib.sha256(text.encode()).hexdigest()
    return text, sh, iqs.sheet_sql(text, dets, sheet_sha256=sh, approved_sha256=sh, rows_sha256="e" * 64, source_id=1)


GOOD = {P1: "same 9 # partner er hovedpersonens", P2: "N # ny person", P3: "U # uklart"}


def test_render_one_line_per_persona_sorted():
    qs = [l for l in iqs.render_sheet(details()).splitlines() if l.startswith("Q ")]
    assert qs == [f"Q {P1} 0 : _ # ", f"Q {P2} 1 : _ # ", f"Q {P3} 2 : _ # "]


def test_valid_sheet_calls_and_note_format():
    _, sh, (sql, counts) = sheet_and_sql(GOOD)
    calls = [l for l in sql.splitlines() if "red_afgoer_source_persona(" in l]
    assert len(calls) == 3 and counts == {"same": 1, "N": 1, "X": 0, "U": 1}
    assert f"'kø 2b-i {sh[:12]} sag 3 — uklart'" in calls[2]
    assert f"'{P1}'::uuid, 0, 'same', 9," in calls[0] and f"'{P2}'::uuid, 1, 'new_person_needed', NULL," in calls[1]
    ctx = json.loads(re.search(r"'(\{.*\})'::jsonb", calls[0]).group(1))
    assert ctx == {"basis": "human_sheet", "sheet_sha256": sh, "rows_sha256": "e" * 64, "line": 1}


def test_rows_stale_guard_over_sorted_persona_ids():
    _, _, (sql, _) = sheet_and_sql(GOOD)
    assert "KOE_ROWS_STALE" in sql and f"ARRAY['{P1}','{P2}','{P3}']::text[]" in sql
    assert "ORDER BY sp.id::text COLLATE \"C\"" in sql and "sp.source_id=1 " in sql
    assert "KOE_COUNT_MISMATCH" in sql


def test_wrong_hash_stops():
    text = answered(iqs.render_sheet(details()), GOOD)
    with pytest.raises(SheetError, match="^KOE_SHEET_HASH_MISMATCH"):
        iqs.sheet_sql(text, details(), sheet_sha256=hashlib.sha256(text.encode()).hexdigest(),
                      approved_sha256="0" * 64, rows_sha256="e" * 64, source_id=1)


def test_wrong_line_count_stops():
    # Arket har 3 Q-linjer, detaljedumpet 4 personas.
    text = answered(iqs.render_sheet(details()), GOOD)
    sh = hashlib.sha256(text.encode()).hexdigest()
    with pytest.raises(SheetError, match="^KOE_LINE_COUNT"):
        iqs.sheet_sql(text, details() + [detail("44444444-4444-4444-8444-444444444444")], sheet_sha256=sh,
                      approved_sha256=sh, rows_sha256="e" * 64, source_id=1)


def test_unknown_persona_stops():
    text = answered(iqs.render_sheet(details()), GOOD).replace(P2, "55555555-5555-4555-8555-555555555555")
    sh = hashlib.sha256(text.encode()).hexdigest()
    with pytest.raises(SheetError, match="^KOE_PERSONA_UNKNOWN 2$"):
        iqs.sheet_sql(text, details(), sheet_sha256=sh, approved_sha256=sh, rows_sha256="e" * 64, source_id=1)


def test_duplicate_persona_stops():
    text = answered(iqs.render_sheet(details()), GOOD).replace(P2, P1)
    sh = hashlib.sha256(text.encode()).hexdigest()
    with pytest.raises(SheetError, match="^KOE_PERSONA_UNKNOWN 2$"):
        iqs.sheet_sql(text, details(), sheet_sha256=sh, approved_sha256=sh, rows_sha256="e" * 64, source_id=1)


@pytest.mark.parametrize("bad", ["same # uden person", "_ # ", "N", "Y # ukendt token"])
def test_invalid_line_stops(bad):
    with pytest.raises(SheetError, match="^KOE_LINE_INVALID 1$"):
        sheet_and_sql({**GOOD, P1: bad})


def test_note_with_quote_is_escaped():
    _, _, (sql, _) = sheet_and_sql({**GOOD, P3: "U # O'Hara?"})
    assert "sag 3 — O''Hara?'" in sql


def _cli(*args, cwd):
    return subprocess.run([sys.executable, "-I", str(Path(iqs.__file__)), *args], capture_output=True, text=True, cwd=cwd)


def test_cli_render_sql_prints_no_uuid_or_name_and_refuses_existing(tmp_path):
    root = tmp_path / "priv"; root.mkdir()
    det = root / "koe-detaljer.json"; det.write_text(json.dumps(details()), encoding="utf-8")
    ark = root / "koe.txt"
    r = _cli("render", "--details", str(det), "--out", str(ark), "--private-root", str(root), cwd=tmp_path)
    assert r.returncode == 0 and r.stdout.startswith("KOE_RENDER_OK n=3 ")
    assert oct(ark.stat().st_mode & 0o777) == "0o600"
    ark.write_text(answered(ark.read_text(encoding="utf-8"), GOOD), encoding="utf-8")
    sh = hashlib.sha256(ark.read_bytes()).hexdigest()
    out = root / "koe-apply.sql"
    r = _cli("sql", "--sheet", str(ark), "--approved-sha256", sh, "--details", str(det), "--source", "1", "--out", str(out),
             "--private-root", str(root), cwd=tmp_path)
    assert r.returncode == 0, r.stderr
    assert r.stdout.startswith("KOE_SQL_OK n=3 same=1 N=1 X=0 U=1 rows_sha256=")
    for s in (r.stdout, r.stderr):
        assert not UUID.search(s) and "Bo Beta" not in s and "Kandidat" not in s
    r = _cli("sql", "--sheet", str(ark), "--approved-sha256", sh, "--details", str(det), "--source", "1", "--out", str(out),
             "--private-root", str(root), cwd=tmp_path)
    assert r.returncode == 1 and "KOE_OUT_EXISTS" in r.stderr


def test_cli_refuses_path_outside_private_root(tmp_path):
    root = tmp_path / "priv"; root.mkdir()
    det = tmp_path / "koe-detaljer.json"; det.write_text(json.dumps(details()), encoding="utf-8")
    r = _cli("render", "--details", str(det), "--out", str(root / "koe.txt"), "--private-root", str(root), cwd=tmp_path)
    assert r.returncode == 1 and "SHEET_PATH_NOT_PRIVATE" in r.stderr
