"""Trin 5b 2b-ii (spec §5.3-5.4): ægteskabsarket for de parkerede ægteskaber."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

import relation_marriage_sheet as rms
from decision_sheet_core import SheetError

K1 = "11111111-1111-4111-8111-111111111111"   # D
K2 = "22222222-2222-4222-8222-222222222222"   # S
K3 = "33333333-3333-4333-8333-333333333333"   # I
K4 = "44444444-4444-4444-8444-444444444444"   # N


def row(key, text, raw, partners=(), ordinal=1):
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": "relation.marriage", "raw": raw,
            "record_key": "II-1", "marriage_ordinal": ordinal, "supporting_count": 1, "principal_ok": True,
            "principal_person_id": 9, "principal_partners": list(partners),
            "clauses": [{"observation_id": "o-" + key[:4], "clause_set_seq": 1, "clause_set_sha256": "c" * 64,
                         "verbatim_text": text, "post_char_from": 100, "post_char_to": 100 + len(text)}]}


def rows():
    return {"contract": "relation-persona-v2-input", "source_id": 1, "deceased_cutoff_year": 1906, "rows": [
        row(K1, "Gift 1. gang 1890 med Bo Beta, f. 1801.", "Gift med Bo Beta"),
        row(K2, "Gift 1890 med Cia Ceta.", "Gift med Cia Ceta",
            partners=[{"person_id": 7, "family_id": 3, "ordinal": 1, "navn": "Cia Carla Ceta", "foedt": "1870", "doed": "1940"}]),
        row(K3, "Gift 1975.", "Gift 1975."),
        row(K4, "Gift 1950 med O'Dea Di.", "Gift med O'Dea Di")]}


def test_render_forudfylder_og_viser_grundlag():
    ark = rms.render_sheet(rows())
    assert f"M {K1} 1 : D" in ark and f"M {K2} 1 : S" in ark and f"M {K3} 1 : I" in ark and f"M {K4} 1 : N" in ark
    assert "#   Ægtefællens navn: »Bo Beta«" in ark
    assert "#   Årstal i klausulen: 1801, 1890 · grænse 1906" in ark
    assert "Cia Carla Ceta (1870–1940) · familie 3 · nr. 1" in ark
    assert all(len(l) and "\n" not in l for l in ark.splitlines() if l.startswith("M "))


def test_parse_rundtur_og_tokens():
    lines = rms.parse_sheet(rms.render_sheet(rows()))
    assert [(l.key, l.tok, l.line) for l in lines] == [(K1, "D", 1), (K2, "S", 2), (K3, "I", 3), (K4, "N", 4)]
    with pytest.raises(SheetError, match="SHEET_LINE_INVALID"):
        rms.parse_sheet(f"M {K1} 1 : X\n")
    with pytest.raises(SheetError, match="SHEET_LINE_UNKNOWN"):
        rms.parse_sheet("noget andet\n")


def test_identitet_og_rækkefølge():
    lines = rms.parse_sheet(rms.render_sheet(rows()))
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        rms.check_sheet(lines[1:], rows())
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        rms.check_sheet([lines[1], lines[0], *lines[2:]], rows())


def test_D_og_S_kun_hvor_forslaget_tillader_det():
    ark = rms.render_sheet(rows())
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED line=4"):
        rms.check_sheet(rms.parse_sheet(ark.replace(f"M {K4} 1 : N", f"M {K4} 1 : D")), rows())
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED line=1"):
        rms.check_sheet(rms.parse_sheet(ark.replace(f"M {K1} 1 : D", f"M {K1} 1 : S")), rows())
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED line=3"):
        rms.check_sheet(rms.parse_sheet(ark.replace(f"M {K3} 1 : I", f"M {K3} 1 : N")), rows())
    # D → N og alt → U/I er altid tilladt
    ok = ark.replace(f"M {K1} 1 : D", f"M {K1} 1 : N").replace(f"M {K2} 1 : S", f"M {K2} 1 : U")
    rms.check_sheet(rms.parse_sheet(ok), rows())


def test_manifest_kun_S_D_N_og_profil_v2():
    lines = rms.parse_sheet(rms.render_sheet(rows()))
    m = rms.persona_manifest(lines, rows())
    assert m["expected_counts"] == {"person_creates": 0, "source_evidence": 0, "relation_personas": 3}
    assert sorted(m["authorized_elements"]) == sorted("relation-persona:" + k for k in (K1, K2, K4))
    e = m["authorized_elements"]["relation-persona:" + K1]
    assert sorted(e) == ["birth_raw", "clause_observation_id", "clause_set_seq", "clause_set_sha256", "death_raw",
                         "interpretation_key", "interpretation_version", "marriage_ordinal", "name_from", "name_to",
                         "post_offset", "predicate", "profile", "span_from", "span_to"]
    assert e["profile"] == "relation-persona-2018-20-v2" and (e["span_from"], e["span_to"]) == (0, 29)
    assert (e["name_from"], e["name_to"]) == (22, 29) and e["post_offset"] == 100 and e["birth_raw"] is None


def test_identitetsscript_laaser_og_citerer():
    ark = rms.render_sheet(rows()).replace(f"M {K4} 1 : N", f"M {K4} 1 : N  # O'Brien \\ x")
    lines = rms.parse_sheet(ark)
    sql = rms.identity_sql(lines, rows(), sheet_sha256="b" * 64, rows_sha256="a" * 64)
    assert sql.index("BEGIN;\nSET LOCAL standard_conforming_strings=on;") < sql.index("red_afgoer_source_persona")
    assert "'same', 7," in sql and sql.count("'new_person_needed', NULL,") == 2
    assert '"deceased": {"clause_years": [1801, 1890], "cutoff_year": 1906, "rule": "aarstal-120-v1"}' in sql
    assert "O''Brien \\ x" in sql and sql.rstrip().endswith("COMMIT;")
    assert sql.index("interpretation_party_current") < sql.index("SET LOCAL ROLE authenticated")


def _git_root_free(tmp_path):
    root = tmp_path / "priv"
    root.mkdir()
    return root


def test_cli_hashbinding_og_sti(tmp_path):
    root = _git_root_free(tmp_path)
    rows_p = root / "rows.json"
    rows_p.write_text(json.dumps(rows()) + "\n", encoding="utf-8")
    ark = root / "ark.txt"
    tool = str(Path(__file__).with_name("relation_marriage_sheet.py"))
    r = subprocess.run([sys.executable, tool, "render", "--rows", str(rows_p), "--out", str(ark), "--private-root", str(root)],
                       capture_output=True, text=True)
    assert r.stdout.strip() == "ARK_OK s=1 d=1 n=1 i=1 u=0"
    rsha = hashlib.sha256(rows_p.read_bytes()).hexdigest()
    asha = hashlib.sha256(ark.read_bytes()).hexdigest()
    base = [sys.executable, tool, "sql", "--rows", str(rows_p), "--sheet", str(ark), "--expect-rows-sha256", rsha,
            "--manifest-out", str(root / "m.json"), "--identity-out", str(root / "i.sql"), "--private-root", str(root)]
    assert subprocess.run(base + ["--approved-sha256", "0" * 64], capture_output=True, text=True).stdout.strip() == "SHEET_HASH_MISMATCH"
    r = subprocess.run(base + ["--approved-sha256", asha], capture_output=True, text=True)
    assert r.stdout.strip() == "SQL_OK manifest=3 identitet=3"
    assert (root / "m.json").stat().st_mode & 0o777 == 0o600
    outside = tmp_path / "ude.txt"
    r = subprocess.run([sys.executable, tool, "render", "--rows", str(rows_p), "--out", str(outside), "--private-root", str(root)],
                       capture_output=True, text=True)
    assert r.stdout.strip() == "SHEET_PATH_NOT_PRIVATE"
