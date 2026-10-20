"""Trin 5b 2b-iii (spec §6): børnearket — ét hash-bundet ark for alle børnehenvisninger, der opfylder H.

Rækkefil og ark rummer navne og bogens tekst; værktøjet printer kun antal og koder. `sql` laver ét afgørelsesscript
(red_afgoer_relation_interpretation med human_sheet-kontekst). Serveren genberegner reglen og afviser H-brud.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from spouse_exception_sheet import _write_private, check_private_path

CONTRACT = "relation-child-sheet-input-v1"
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
C_RE = re.compile(rf"^C (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>\S+)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^C {UUID} ")
TOKENS = {"B", "R", "U"}


@dataclass
class Line:
    key: str
    version: int
    tok: str
    note: str | None


def _ok_rows(rows: dict) -> dict[str, dict]:
    if rows.get("contract") != CONTRACT:
        raise SheetError("ROWS_CONTRACT_INVALID")
    return {r["interpretation_key"]: r for r in rows["rows"] if r["rule"].get("ok")}


def _child(c: dict) -> str:
    return f"#     {c['navn']} (f. {c.get('foedt') or '?'}) [{c.get('linje') or '-'}-{c.get('nr') or '-'}, kuld {c.get('kuld') or '-'}, slægtled {c.get('gen_local') or '-'}]"


def render_sheet(rows: dict) -> str:
    ok = _ok_rows(rows)
    passer = [r for r in ok.values() if not r["rule"]["afvigelser"]]
    kort = [r for r in ok.values() if r["rule"]["afvigelser"]]
    uden = [r for r in rows["rows"] if not r["rule"].get("ok")]
    out = ["# Børnearket (2b-iii). Tokens: B = bind, R = afvis påstanden, U = lad stå (intet skrives).",
           "# Passer helt (alle krav og ingen afvigelser) — forudfyldt B:"]
    for r in sorted(passer, key=lambda r: r["row_no"]):
        out.append(f"#   »{r['raw']}« — {len(r['children_named'])} børn")
        out.append(f"C {r['interpretation_key']} {r['interpretation_version']} : B")
    out.append("# Kort (afvigelser, som du kan tilsidesætte) — forudfyldt B:")
    for r in sorted(kort, key=lambda r: r["row_no"]):
        out.append(f"#   »{r['raw']}« — afvigelser: {', '.join(r['rule']['afvigelser'])}")
        out.extend(_child(c) for c in r["children_named"])
        out.append(f"C {r['interpretation_key']} {r['interpretation_version']} : B")
    brud = sorted({b for r in uden for b in r["rule"].get("brud", [])})
    out.append(f"# Ikke på arket: {len(uden)} (brud: {', '.join(brud) or '-'})")
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    lines = []
    for raw in text.splitlines():
        m = C_RE.match(raw)
        if m:
            lines.append(Line(m["key"], int(m["ver"]), m["tok"], m["note"]))
        elif LOOSE_RE.match(raw):
            raise SheetError("SHEET_LINE_INVALID")
    return lines


def check_sheet(lines: list[Line], rows: dict) -> list[tuple[Line, dict]]:
    ok = _ok_rows(rows)
    seen: set[str] = set()
    out = []
    for l in lines:
        if l.tok not in TOKENS:
            raise SheetError("SHEET_TOKEN_NOT_ALLOWED")
        r = ok.get(l.key)
        if r is None or r["interpretation_version"] != l.version:
            raise SheetError("SHEET_LINE_UNKNOWN")
        if l.key in seen:
            raise SheetError("SHEET_LINE_DUPLICATE")
        seen.add(l.key)
        out.append((l, r))
    if seen != set(ok):
        raise SheetError("SHEET_LINES_MISSING")
    return out


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
        note = sql_literal(f"børneark {tag} række {r['row_no']}" + (f" — {l.note}" if l.note else ""))
        action = "same" if l.tok == "B" else "rejected"
        sql.append(f"SELECT red_afgoer_relation_interpretation('{l.key}'::uuid, {l.version}, '{action}', NULL, {note}, "
                   f"{sql_literal(json.dumps(ctx, sort_keys=True))}::jsonb) \\g /dev/null")
    sql.append("COMMIT;")
    return "\n".join(sql) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    s = sub.add_parser("sql")
    for p in (r, s):
        p.add_argument("--rows", required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    r.add_argument("--out", required=True)
    for a in ("--sheet", "--approved-sha256", "--expect-rows-sha256", "--decision-out"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        rows_bytes = check_private_path(Path(args.rows), root).read_bytes()
        rows = json.loads(rows_bytes.decode("utf-8"))
        if args.cmd == "render":
            text = render_sheet(rows)
            _write_private(check_private_path(Path(args.out), root), text)
            ok = _ok_rows(rows)
            kort = sum(1 for x in ok.values() if x["rule"]["afvigelser"])
            print(f"ARK_OK passer={len(ok) - kort} kort={kort} uden={len(rows['rows']) - len(ok)}")
            return 0
        dout = check_private_path(Path(args.decision_out), root)
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        lines = parse_sheet(sheet_bytes.decode("utf-8"))
        sql = decision_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
        _write_private(dout, sql)
        toks = [l.tok for l in lines]
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK b={toks.count('B')} r={toks.count('R')} u={toks.count('U')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
