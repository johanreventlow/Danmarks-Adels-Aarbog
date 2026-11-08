"""Trin 6c-3: forælderarket — ét hash-bundet ark for `relation.parent`-fortolkninger.

Rækkefilen (relation_parent_rows.sql) rummer kun nøgler, versioner, persona-id'er og familie-kandidater — ingen
navne. Værktøjet printer kun antal og koder. B binder til den ENESTE familie-kandidat; ingen eller flere kandidater
giver ikke B (PARENT_FAMILY_NOT_UNIQUE). Serveren genberegner kandidaterne og afviser et forældet valg.
Hjælpere genbruges fra relation_child_sheet (ingen kopi).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal
from relation_child_sheet import Line, TOKENS, UUID, load_keys, select_rows, selected_rows_sha256
from spouse_exception_sheet import _write_private, check_private_path

CONTRACT = "relation-parent-sheet-input-v1"
P_RE = re.compile(rf"^P (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>\S+)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^P {UUID} ")
HASH_RE = re.compile(r"^# rows_sha256: ([0-9a-f]{64})$", re.M)

__all__ = ["render_sheet", "parse_sheet", "check_sheet", "sheet_rows", "decision_sql", "selected_rows_sha256", "main"]


def _rows(rows: dict) -> dict[str, dict]:
    if rows.get("contract") != CONTRACT:
        raise SheetError("ROWS_CONTRACT_INVALID")
    return {r["interpretation_key"]: r for r in rows["rows"]}


def _unique_family(r: dict) -> int | None:
    c = r["candidates"]
    return c[0]["family_id"] if len(c) == 1 else None


def render_sheet(rows: dict) -> str:
    by = _rows(rows)
    ordered = sorted(by.values(), key=lambda r: r["row_no"])
    out = ["# ======================== FORÆLDREARKET (6c-3) ========================",
           "# Kun linjerne, der starter med »P«, kan ændres — og kun bogstavet til sidst. Alt med »#« er information.",
           "#   B = bind til familien · R = afvis påstanden for altid · U = lad stå (kan tages op igen).",
           "#   B kræver præcis én familie-kandidat; ellers er linjen forudfyldt U.",
           f"# rows_sha256: {selected_rows_sha256(rows)}", "#"]
    for r in ordered:
        n = len(r["candidates"])
        fam = _unique_family(r)
        out.append(f"# [{r['row_no']}] persona {r['principal_persona_id']} · {n} familie-kandidat(er)"
                   + (f" · familie {fam}" if fam is not None else ""))
        out.append(f"P {r['interpretation_key']} {r['interpretation_version']} : {'B' if fam is not None else 'U'}")
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    lines = []
    for raw in text.splitlines():
        m = P_RE.match(raw)
        if m:
            lines.append(Line(m["key"], int(m["ver"]), m["tok"], m["note"]))
        elif LOOSE_RE.match(raw):
            raise SheetError("SHEET_LINE_INVALID")
    return lines


def check_sheet(lines: list[Line], rows: dict) -> list[tuple[Line, dict]]:
    by = _rows(rows)
    seen: set[str] = set()
    out = []
    for l in lines:
        if l.tok not in TOKENS:
            raise SheetError("SHEET_TOKEN_NOT_ALLOWED")
        r = by.get(l.key)
        if r is None or r["interpretation_version"] != l.version:
            raise SheetError("SHEET_LINE_UNKNOWN")
        if l.key in seen:
            raise SheetError("SHEET_LINE_DUPLICATE")
        seen.add(l.key)
        if l.tok == "B" and _unique_family(r) is None:
            raise SheetError("PARENT_FAMILY_NOT_UNIQUE")
        out.append((l, r))
    if seen != set(by):
        raise SheetError("SHEET_LINES_MISSING")
    return out


def sheet_rows(lines: list[Line], text: str, rows: dict) -> dict:
    """Rækkerne arket dækker; deres hash skal være den, arket blev bygget over."""
    by = _rows(rows)
    if any(l.key not in by for l in lines):
        raise SheetError("SHEET_LINE_UNKNOWN")
    m = HASH_RE.search(text)
    sub = select_rows(rows, [l.key for l in lines]) if lines else {**rows, "rows": []}
    if not m or m.group(1) != selected_rows_sha256(sub):
        raise SheetError("ROWS_HASH_MISMATCH")
    return sub


def decision_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    todo = [(l, r) for l, r in check_sheet(lines, rows) if l.tok in ("B", "R")]
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;", "SET LOCAL TimeZone='UTC';",
           "SET LOCAL search_path=pg_catalog,public,private;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
           "SET LOCAL ROLE authenticated;"]
    tag = sheet_sha256[:12]
    for l, r in todo:
        ctx = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": r["row_no"]}
        note = sql_literal(f"forælderark {tag} række {r['row_no']}" + (f" — {l.note}" if l.note else ""))
        action, fam = "rejected", "NULL"
        if l.tok == "B":
            f = _unique_family(r)
            if type(f) is not int:
                raise SheetError("PARENT_FAMILY_ID_INVALID")
            action, fam = "same", str(f)
        sql.append(f"SELECT red_afgoer_relation_interpretation('{l.key}'::uuid, {l.version}, '{action}', {fam}, {note}, "
                   f"{sql_literal(json.dumps(ctx, sort_keys=True))}::jsonb) \\g /dev/null")
    sql.append("COMMIT;")
    return "\n".join(sql) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    s = sub.add_parser("sql")
    for p in (r, s):
        p.add_argument("--rows", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    r.add_argument("--interpretation-keys", required=True)
    s.add_argument("--sheet", required=True)
    s.add_argument("--approved-sha256", required=True)
    args = ap.parse_args(argv)
    root = Path(args.private_root)
    try:
        rows = json.loads(check_private_path(Path(args.rows), root).read_bytes().decode("utf-8"))
        _rows(rows)
        out = check_private_path(Path(args.out), root)
        if args.cmd == "render":
            sel = select_rows(rows, load_keys(Path(args.interpretation_keys).read_text(encoding="utf-8")))
            _write_private(out, render_sheet(sel))
            ens = sum(1 for x in sel["rows"] if _unique_family(x) is not None)
            print(f"ARK_OK rows={len(sel['rows'])} entydig={ens} uden_entydig={len(sel['rows']) - ens}")
            return 0
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        sheet_sha = hashlib.sha256(sheet_bytes).hexdigest()
        if sheet_sha != args.approved_sha256:
            raise SheetError("SHEET_HASH_MISMATCH")
        text = sheet_bytes.decode("utf-8")
        lines = parse_sheet(text)
        sel = sheet_rows(lines, text, rows)
        sql = decision_sql(lines, sel, sheet_sha256=sheet_sha, rows_sha256=selected_rows_sha256(sel))
        _write_private(out, sql)
        toks = [l.tok for l in lines]
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK b={toks.count('B')} r={toks.count('R')} u={toks.count('U')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
