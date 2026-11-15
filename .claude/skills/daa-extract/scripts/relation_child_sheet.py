"""Trin 5b 2b-iii (spec §6): børnearket — ét hash-bundet ark for alle børnehenvisninger, der opfylder H.

Rækkefil og ark rummer navne og bogens tekst; værktøjet printer kun antal og koder. `sql` laver ét afgørelsesscript
(red_afgoer_relation_interpretation med human_sheet-kontekst). Serveren genberegner reglen og afviser H-brud.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from private_io import check_private_path, write_private_new, write_private_replace

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


def load_keys(text: str) -> list[str]:
    """Nøglefil: én interpretation_key pr. linje; tomme linjer og #-kommentarer springes over."""
    keys = []
    for raw in text.splitlines():
        t = raw.split("#", 1)[0].strip()
        if not t:
            continue
        if not re.fullmatch(UUID, t):
            raise SheetError("KEYS_FILE_INVALID")
        keys.append(t)
    if not keys or len(set(keys)) != len(keys):
        raise SheetError("KEYS_FILE_INVALID")
    return keys


def select_rows(rows: dict, keys: list[str]) -> dict:
    """Afgræns rækkefilen til de valgte nøgler (rækkefølge som i filen). Ukendt nøgle → CHILD_KEY_UNKNOWN."""
    by = {r["interpretation_key"] for r in rows["rows"]}
    if any(k not in by for k in keys):
        raise SheetError("CHILD_KEY_UNKNOWN")
    wanted = set(keys)
    return {**rows, "rows": [r for r in rows["rows"] if r["interpretation_key"] in wanted]}


def selected_rows_sha256(rows: dict) -> str:
    """Hash over de valgte rækker (kanonisk JSON, sorteret på nøgle)."""
    rs = sorted(rows["rows"], key=lambda r: r["interpretation_key"])
    return hashlib.sha256(json.dumps(rs, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest()


def _ok_rows(rows: dict) -> dict[str, dict]:
    if rows.get("contract") != CONTRACT:
        raise SheetError("ROWS_CONTRACT_INVALID")
    return {r["interpretation_key"]: r for r in rows["rows"] if r["rule"].get("ok")}


# Afvigelser og brud i almindelige ord (projektejeren 2026-10-20: arket skal kunne læses uden koder).
BRUD_TEKST = {"H1_klausul": "påstanden citerer ikke præcis én klausul", "H1_hovedperson": "ingen entydig hovedperson",
              "H1_postnoegle": "hovedpersonen har ingen entydig post", "H2": "bogens tekst kan ikke læses som henvisning",
              "H3_familie": "forælderen har børn i flere ægteskaber (eller ingen)",
              "H3_raekker": "familien har en omstridt eller ikke-biologisk barnerække", "H4": "kønnet passer ikke",
              "H5_nr": "postnumrene passer ikke", "H5_linje": "et barn står i en anden linje",
              "H5_romertal": "romertallet passer ikke", "H5_slaegtled": "slægtleddet passer ikke",
              "H5_slaegtled_gennem": "det gennemgående slægtled passer ikke",
              "H6": "intet barn har egen post"}


def _antal(n: int) -> str:
    return f"{n} barn" if n == 1 else f"{n} børn"


def _afvigelse(code: str, r: dict) -> str:
    ref, n = r["rule"].get("ref") or {}, len(r["children_named"])
    if code == "A1_antal_familie":
        return f"bogen siger {_antal(ref.get('count', 0))}, familien har {_antal(n)}"
    if code == "A2_antal_interval":
        k = (ref.get("nr_to") or 0) - (ref.get("nr_from") or 0) + 1
        return f"bogen siger {_antal(ref.get('count', 0))}, men henviser til {k} poster"
    if code == "A3_usikker":
        return "bogen er selv usikker (»(?)«)"
    if code == "A4_uden_henvisning":
        return "bogen henviser ikke til poster"
    return code


def _forælder(no: int, r: dict) -> str:
    p = r.get("principal_named") or {}
    return f"# [{no}] Forælder: {p.get('navn') or '?'} (f. {p.get('foedt') or '?'}), post {p.get('post') or '?'}"


def _child(c: dict) -> str:
    return (f"#        - {c['navn']} (f. {c.get('foedt') or '?'}), post {c.get('linje') or '-'}-{c.get('nr') or '-'}, "
            f"kuld {c.get('kuld') or '-'}, slægtled {c.get('gen_local') or '-'}")


def _poster(r: dict) -> str:
    nrs = sorted((c["linje"], c["nr"]) for c in r["children_named"] if c.get("linje") and c.get("nr") is not None)
    if not nrs:
        return "ingen med egen post"
    return f"poster {nrs[0][0]}-{nrs[0][1]} … {nrs[-1][0]}-{nrs[-1][1]}" if len(nrs) > 1 else f"post {nrs[0][0]}-{nrs[0][1]}"


def render_sheet(rows: dict) -> str:
    ok = _ok_rows(rows)
    passer = sorted((r for r in ok.values() if not r["rule"]["afvigelser"]), key=lambda r: r["row_no"])
    kort = sorted((r for r in ok.values() if r["rule"]["afvigelser"]), key=lambda r: r["row_no"])
    uden = [r for r in rows["rows"] if not r["rule"].get("ok")]
    out = ["# ======================== BØRNEARKET (2b-iii) ========================",
           "# Sådan læses arket:",
           "#   - Kun linjerne, der starter med »C«, kan ændres — og kun bogstavet til sidst. Alt med »#« er information.",
           "#   - B = bind (kilden vises for læseren) · R = afvis påstanden for altid · U = lad stå (kan tages op igen).",
           "#   - DEL 1 passer helt mellem bog og database (antal, numre, slægtled, afdeling, køn); normalt skal intet rettes.",
           "#   - DEL 2 er kort, hvor bog og database afviger; læs dem og vælg.",
           "#",
           f"# DEL 1 — {len(passer)} flokke, der passer helt (forudfyldt B)"]
    no = 0
    for r in passer:
        no += 1
        out.append(_forælder(no, r))
        out.append(f"#     bogen: »{r['raw']}«  ·  databasen: {_antal(len(r['children_named']))}, {_poster(r)}")
        out.append(f"C {r['interpretation_key']} {r['interpretation_version']} : B")
    out += ["#", f"# DEL 2 — {len(kort)} kort, hvor bog og database afviger (forudfyldt B)"]
    for r in kort:
        no += 1
        out.append(_forælder(no, r))
        out.append(f"#     bogen: »{r['raw']}«")
        out.append("#     afviger: " + "; ".join(_afvigelse(c, r) for c in r["rule"]["afvigelser"]))
        out.append(f"#     databasens {_antal(len(r['children_named']))}:")
        out.extend(_child(c) for c in r["children_named"])
        out.append(f"C {r['interpretation_key']} {r['interpretation_version']} : B")
    grunde = sorted({BRUD_TEKST.get(b, b) for r in uden for b in r["rule"].get("brud", [])})
    out += ["#", f"# Ikke på arket: {len(uden)} (grunde: {'; '.join(grunde) or '-'}). De står uændret som forslag."]
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
        p.add_argument("--interpretation-keys", default=None)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    r.add_argument("--out", required=True)
    for a in ("--sheet", "--approved-sha256", "--expect-rows-sha256", "--decision-out"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        rows_bytes = check_private_path(Path(args.rows), root).read_bytes()
        rows = json.loads(rows_bytes.decode("utf-8"))
        subset = args.interpretation_keys is not None
        if subset:
            rows = select_rows(rows, load_keys(Path(args.interpretation_keys).read_text(encoding="utf-8")))
        if args.cmd == "render":
            text = render_sheet(rows)
            write_private_new(check_private_path(Path(args.out), root), text)  # udfyldbart ark
            ok = _ok_rows(rows)
            kort = sum(1 for x in ok.values() if x["rule"]["afvigelser"])
            print(f"ARK_OK passer={len(ok) - kort} kort={kort} uden={len(rows['rows']) - len(ok)}")
            return 0
        dout = check_private_path(Path(args.decision_out), root)
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        if subset:
            rows_sha = selected_rows_sha256(rows)
        lines = parse_sheet(sheet_bytes.decode("utf-8"))
        sql = decision_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
        write_private_replace(dout, sql)
        toks = [l.tok for l in lines]
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK b={toks.count('B')} r={toks.count('R')} u={toks.count('U')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
