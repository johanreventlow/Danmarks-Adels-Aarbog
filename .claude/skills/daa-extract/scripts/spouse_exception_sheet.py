"""Trin 5b 2b-i (spec §5): undtagelsesark for ægtefæller, hvis partner er kandidat nr. 1, og gældende
ordinal-afvigelser. Arket rummer navne og bogens tekst; værktøjet printer kun antal og hashes."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
# `?` (#248): en linje, hvis kandidat nr. 1 deles med en anden ægtefælle i posten, står ubesvaret.
S_RE = re.compile(rf"^S (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>[SAU?])\s*(?:#\s*(?P<note>.*))?$")
# Indholds-id (#151, spec §4 pkt. 1): O-linjen nøgles på fortolkningsnøglen og afgørelsesversionen, ikke på et
# tilfældigt afgørelsesversions-id; et v1-ark (`O <id> b/f`) matcher ikke og afvises.
O_RE = re.compile(rf"^O (?P<id>{UUID}) (?P<ver>[0-9]+) (?P<bog>[0-9]+|\?)/(?P<fam>[0-9]+|\?) : (?P<tok>[BF])\s*(?:#\s*(?P<note>.*))?$")
CONTRACT = "spouse-exception-rows-v2"
LOOSE_RE = re.compile(rf"^[SO] {UUID} ")


@dataclass(frozen=True)
class Line:
    kind: str
    item_id: str
    version: int | None
    tok: str
    note: str
    line: int          # 1-baseret ordinal blandt svarlinjerne


def _ws(s: str | None) -> str:
    return " ".join((s or "").split())


def _years(born, died) -> str:
    return f"{born or '?'}–{died or '?'}"


def _nr(n) -> str:
    # family_member.ordinal (og bogens nummer) kan være NULL; arket viser '?' (Opus kode-review I2)
    return "?" if n is None else str(n)


def _require_v2(rows: dict) -> None:
    if rows.get("contract") != CONTRACT:
        raise SheetError("SHEET_CONTRACT_UNSUPPORTED")


def render_sheet(rows: dict, forslag: dict[str, str] | None = None) -> str:
    _require_v2(rows)
    forslag = forslag or {}
    out = ["# UNDTAGELSESARK (trin 5b 2b-i)",
           "# S-linjer: S = samme person som kandidat nr. 1 (forudfyldt), A = en anden person, U = kan ikke afgøres.",
           "#   A og U skriver intet; sagen afgøres bagefter i webkøen.",
           "# O-linjer: B = ret familiens ægteskabsnummer til bogens, F = behold familiens.",
           "# Ret kun undtagelser. En note må følge efter '#'. Gem, og giv hashen i chatten.", ""]
    for i, r in enumerate(rows["s_rows"], 1):
        d = r["candidate_display"]
        navn = _ws(d.get("visning_fuldt_navn") or d.get("visning_navn")) or "(intet navn)"
        kilde = " / ".join(_ws(m["verbatim_text"]) for m in r["mentions"])
        out += [f"## ÆGTEFÆLLE {i}/{len(rows['s_rows'])}",
                f"#   Bogen: »{kilde}«",
                f"#   Kandidat 1: {navn} ({_years(d.get('visning_foedt'), d.get('visning_doed'))}) · {r['candidate_tier']} · "
                f"score {r['candidate_score']} · {r['candidate_count']} kandidater",
                f"#   Partner i familie {r['family_id']} (ægteskab nr. {_nr(r['family_ordinal'])})"]
        # #248 rute A (spec §3.3): et forudfyldt S skjulte, at kandidat nr. 1 var hovedpersonens anden ægtefælle.
        rivals = int(r.get("post_rivals", 0))
        if rivals:
            out.append(f"#   ADVARSEL: kandidat 1 er også kandidat for {rivals} anden ægtefælle i posten — navnefælle? Svar S, A eller U.")
        out += [f"S {r['source_persona_id']} {r['identity_version']} : {'?' if rivals else 'S'}", ""]
    for i, r in enumerate(rows["o_rows"], 1):
        tok = forslag.get(r["interpretation_key"], "F")
        out += [f"## ORDINAL {i}/{len(rows['o_rows'])} · familie {r['family_id']} · bogen nr. {_nr(r['book_ordinal'])}, familien nr. {_nr(r['family_ordinal'])}",
                f"O {r['interpretation_key']} {int(r['interpretation_version'])} {_nr(r['book_ordinal'])}/{_nr(r['family_ordinal'])} : {tok}", ""]
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    lines: list[Line] = []
    for raw in text.splitlines():
        if not raw.strip() or raw.startswith("#"):
            continue
        m = S_RE.match(raw) or O_RE.match(raw)
        if not m:
            raise SheetError("SHEET_LINE_INVALID" if LOOSE_RE.match(raw) else "SHEET_LINE_UNKNOWN")
        kind = raw[0]
        lines.append(Line(kind, m["id"], int(m["ver"]), m["tok"], (m["note"] or "").strip(),
                          len(lines) + 1))
    return lines


def _expected(rows: dict) -> list[tuple]:
    return ([("S", r["source_persona_id"], r["identity_version"]) for r in rows["s_rows"]]
            + [("O", r["interpretation_key"], r["interpretation_version"]) for r in rows["o_rows"]])


def _require_answered(lines: list[Line]) -> None:
    if any(l.tok == "?" for l in lines):
        raise SheetError("SHEET_UNANSWERED")


def check_identity(lines: list[Line], rows: dict) -> None:
    _require_v2(rows)
    if [(l.kind, l.item_id, l.version) for l in lines] != _expected(rows) or not lines:
        raise SheetError("SHEET_IDENTITY_MISMATCH")
    _require_answered(lines)


def check_private_path(path: Path, root: Path) -> Path:
    root_r = root.resolve()
    if path.is_symlink():
        raise SheetError("SHEET_PATH_SYMLINK")
    p = path.resolve()
    if root_r not in p.parents:
        raise SheetError("SHEET_PATH_NOT_PRIVATE")
    for parent in [p.parent, *p.parent.parents]:
        if (parent / ".git").exists():
            raise SheetError("SHEET_PATH_IN_GIT")
    return p


def _write_private(path: Path, text: str) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    path.chmod(0o600)


def sheet_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str, source_id: int) -> str:
    _require_v2(rows)
    _require_answered(lines)
    require_hex64(sheet_sha256, rows_sha256)
    s_by = {r["source_persona_id"]: r for r in rows["s_rows"]}
    o_by = {r["interpretation_key"]: r for r in rows["o_rows"]}
    persons = sorted({r["principal_person_id"] for r in rows["s_rows"]} | {r["candidate_person_id"] for r in rows["s_rows"]}
                     | {r["principal_person_id"] for r in rows["o_rows"]} | {r["spouse_person_id"] for r in rows["o_rows"]})
    if any(l.kind == "O" and l.tok == "B" and o_by[l.item_id]["book_ordinal"] is None for l in lines):
        raise SheetError("SHEET_ORDINAL_B_UDEN_BOGTAL")
    tag = sheet_sha256[:12]
    # sql_literal fordobler kun '; backslash i en note skal derfor være bogstavelig i sessionen (Opus kode-review I1)
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL TimeZone='UTC';", "SET LOCAL search_path=pg_catalog,public,private;",
           "SET LOCAL standard_conforming_strings=on;",
           f"SELECT pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:{int(source_id)}',0)) \\g /dev/null",
           f"SELECT private.lock_family_rows(ARRAY[{','.join(str(int(p)) for p in persons)}]::bigint[]) \\g /dev/null",
           "DO $chk$ BEGIN",
           f"  IF encode(sha256(convert_to(private.spouse_exception_projection({int(source_id)})::text||E'\\n','UTF8')),'hex')<>'{rows_sha256}' THEN",
           "    RAISE EXCEPTION 'SPOUSE_SHEET_ROWS_STALE'; END IF; END $chk$;"]
    for l in lines:
        if l.kind == "O" and l.tok == "B":
            r = o_by[l.item_id]
            sql.append(f"DO $o{l.line}$ BEGIN IF (SELECT ordinal FROM family_member WHERE family_id={int(r['family_id'])} "
                       f"AND person_id={int(r['principal_person_id'])} AND rolle='partner') IS DISTINCT FROM {'NULL' if r['family_ordinal'] is None else int(r['family_ordinal'])} "
                       f"THEN RAISE EXCEPTION 'SPOUSE_SHEET_ORDINAL_DRIFT'; END IF; END $o{l.line}$;")
    # Temp-tabellen oprettes EFTER rolleskiftet (som del 1): ellers ejes den af operatøren, og authenticated
    # kan ikke skrive i den.
    sql += ["SET LOCAL ROLE authenticated;",
            "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
            "CREATE TEMP TABLE applied(kind text) ON COMMIT DROP;"]
    n = {"S": 0, "B": 0, "F": 0}
    for l in lines:
        note = sql_literal(f"ark 2b-i {tag} linje {l.line}" + (f" — {l.note}" if l.note else " — partner er kandidat nr. 1"))
        base = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": l.line}
        if l.kind == "S" and l.tok == "S":
            r = s_by[l.item_id]
            ctx = {**base, "candidate_id": r["candidate_id"], "run_id": r["run_id"]}
            sql.append(f"INSERT INTO applied SELECT 'S' FROM (SELECT red_afgoer_source_persona('{l.item_id}'::uuid, {int(l.version)}, "
                       f"'same', {int(r['candidate_person_id'])}, {note}, "
                       f"{sql_literal(json.dumps(ctx, sort_keys=True))}::jsonb)) x;")
            n["S"] += 1
        elif l.kind == "O" and l.tok == "B":
            r = o_by[l.item_id]
            sql.append(f"SELECT red_set_familie_ordinal({int(r['family_id'])}, {int(r['principal_person_id'])}, 'partner', "
                       f"{int(r['book_ordinal'])}) \\g /dev/null")
            sql.append("INSERT INTO applied VALUES ('B');")
            n["B"] += 1
    sql.append("RESET ROLE;")
    for l in lines:
        if l.kind == "O" and l.tok == "F":
            r = o_by[l.item_id]
            ev = {"sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": l.line,
                  "book_ordinal": r["book_ordinal"], "family_ordinal": r["family_ordinal"], "note": l.note}
            # Den gældende afgørelsesversion slås op ved kørsel (ingen række ⇒ SHEET_COUNT_MISMATCH); rækkefil-vagten
            # ($chk$) under kildelåsen sikrer, at tilstanden er den godkendte.
            sql.append(f"INSERT INTO applied SELECT 'F' FROM (SELECT private.append_relation_classification(ic.id, 'ordinal_beholdt', "
                       f"{sql_literal(json.dumps(ev, sort_keys=True))}::jsonb) FROM private.interpretation_current ic "
                       f"WHERE ic.interpretation_key='{l.item_id}'::uuid AND ic.version={int(l.version)}) x;")
            n["F"] += 1
    sql.append("DO $cnt$ BEGIN IF " + " OR ".join(
        f"(SELECT count(*) FROM applied WHERE kind='{k}')<>{v}" for k, v in sorted(n.items()))
        + " THEN RAISE EXCEPTION 'SHEET_COUNT_MISMATCH'; END IF; END $cnt$;")
    sql.append("COMMIT;")
    return "\n".join(sql) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    s = sub.add_parser("sql")
    for p in (r, s):
        p.add_argument("--rows", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    r.add_argument("--forslag")
    for a in ("--sheet", "--approved-sha256", "--expect-rows-sha256", "--source"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        rows_path = check_private_path(Path(args.rows), root)
        out = check_private_path(Path(args.out), root)
        rows_bytes = rows_path.read_bytes()
        rows = json.loads(rows_bytes.decode("utf-8"))
        if args.cmd == "render":
            forslag = {}
            if args.forslag:
                forslag = json.loads(check_private_path(Path(args.forslag), root).read_text(encoding="utf-8"))
            _write_private(out, render_sheet(rows, forslag))
            print(f"ARK_OK s={len(rows['s_rows'])} o={len(rows['o_rows'])}")
            return 0
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        lines = parse_sheet(sheet_bytes.decode("utf-8"))
        check_identity(lines, rows)
        _write_private(out, sheet_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha, source_id=int(args.source)))
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK linjer={len(lines)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
