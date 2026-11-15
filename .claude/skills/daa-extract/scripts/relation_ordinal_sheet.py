"""#244 (spec §6): ark til rettelse af skævt gemte ægteskabsnumre — ét hash-bundet ark, B = ret, U = lad stå.

Rækkefil og ark rummer navne; værktøjet printer kun antal og koder. `sql` laver ét afgørelsesscript
(red_ret_aegteskabsnummer med human_sheet-kontekst). Serveren genberegner nummeret og afviser alt andet.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from private_io import check_private_path, write_private_new, write_private_replace

CONTRACT = "relation-ordinal-sheet-input-v1"
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
C_RE = re.compile(rf"^C (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>\S+)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^C {UUID} ")
TOKENS = {"B", "U"}


@dataclass
class Line:
    key: str
    version: int
    tok: str
    note: str | None


def _rettes(r: dict) -> bool:
    n = r.get("new_ordinal")
    return (n is not None and n != r.get("stored_ordinal") and r.get("family_ordinal") == n
            and r.get("book_ordinal") in (None, n))


def _ok_rows(rows: dict) -> dict[str, dict]:
    if rows.get("contract") != CONTRACT:
        raise SheetError("ROWS_CONTRACT_INVALID")
    return {r["interpretation_key"]: r for r in rows["rows"] if _rettes(r)}


def _linje(no: int, r: dict) -> str:
    p, s = r.get("principal_named") or {}, r.get("spouse_named") or {}
    return (f"# [{no}] Forælder: {p.get('navn') or '?'} (f. {p.get('foedt') or '?'}), post {p.get('post') or '?'}"
            f" · Ægtefælle: {s.get('navn') or '?'} (f. {s.get('foedt') or '?'})")


def render_sheet(rows: dict) -> str:
    ok = sorted(_ok_rows(rows).values(), key=lambda r: r["row_no"])
    uden = len(rows["rows"]) - len(ok)
    out = ["# ================= ÆGTESKABSNUMRE (#244) =================",
           "# Sådan læses arket:",
           "#   - Kun linjerne, der starter med »C«, kan ændres — og kun bogstavet til sidst. Alt med »#« er information.",
           "#   - B = ret det gemte nummer til bogens og familiens · U = lad stå (skriver intet).",
           "#   - Familien og ægtefællen er rigtige; kun nummeret i kilden rettes. Bagefter genbindes i samme familie.",
           "#",
           f"# {len(ok)} linjer (forudfyldt B)"]
    for no, r in enumerate(ok, start=1):
        out.append(_linje(no, r))
        out.append(f"#     bogens N°: {r.get('book_ordinal') or '-'} · gemt → nyt: {r['stored_ordinal']} → {r['new_ordinal']}"
                   f" · familiens nr.: {r['family_ordinal']}")
        out.append(f"C {r['interpretation_key']} {r['spouse_party_version']} : B")
    out += ["#", f"# Ikke på arket: {uden} (nummeret kan ikke rettes entydigt). De står uændret."]
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
        if r is None or r["spouse_party_version"] != l.version:
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
    todo = [(l, r) for l, r in check_sheet(lines, rows) if l.tok == "B"]
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;", "SET LOCAL TimeZone='UTC';",
           "SET LOCAL search_path=pg_catalog,public,private;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
           "SET LOCAL ROLE authenticated;"]
    tag = sheet_sha256[:12]
    for l, r in todo:
        ctx = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": r["row_no"]}
        note = sql_literal(f"nummerark {tag} række {r['row_no']}" + (f" — {l.note}" if l.note else ""))
        sql.append(f"SELECT red_ret_aegteskabsnummer('{l.key}'::uuid, {l.version}, {note}, "
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
            write_private_new(check_private_path(Path(args.out), root), text)  # udfyldbart ark
            ok = _ok_rows(rows)
            print(f"ARK_OK linjer={len(ok)} uden={len(rows['rows']) - len(ok)}")
            return 0
        dout = check_private_path(Path(args.decision_out), root)
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        lines = parse_sheet(sheet_bytes.decode("utf-8"))
        sql = decision_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
        write_private_replace(dout, sql)
        toks = [l.tok for l in lines]
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK b={toks.count('B')} u={toks.count('U')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
