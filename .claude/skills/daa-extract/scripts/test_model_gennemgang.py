"""Tests til trin 6m del 1: læse-kun eksport og model_gennemgang.py. Kun syntetiske fixtures, ingen rigtige navne."""
from __future__ import annotations

import re
from pathlib import Path

HERE = Path(__file__).parent
EKSPORT_SQL = HERE / "model_gennemgang_eksport.sql"


def _kode(sql: str) -> str:
    return "\n".join(l for l in sql.splitlines() if not l.lstrip().startswith("--"))


# --- Task 2: læse-kun eksport ---------------------------------------------------------------------------------

def test_eksport_sql_er_laese_kun():
    sql = EKSPORT_SQL.read_text(encoding="utf-8")
    kode = [l for l in _kode(sql).splitlines() if l.strip()]
    assert kode[0].strip() == "BEGIN;" and kode[1].strip() == "SET TRANSACTION READ ONLY;"
    assert kode[-1].strip() == "ROLLBACK;"
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT)\b", "\n".join(kode), re.I)
    assert ":'src'" in sql or ":src" in sql
    # narrative_record_state med true låser (FOR UPDATE + LOCK TABLE) og fejler i READ ONLY (Codex #1).
    kald = re.findall(r"narrative_record_state\s*\(([^;]*?)\)", "\n".join(kode), re.S)
    assert kald, "eksporten skal hente state_sha256 fra narrative_record_state"
    for argumenter in kald:
        assert argumenter.split(",")[-1].strip().lower() == "false"
