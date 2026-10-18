"""Trin 5b 2b-ii (spec §5.3-5.4): ægteskabsarket for de ægteskaber, del 1 parkerede.

Arket og rækkefilen rummer navne og bogens tekst; værktøjet printer kun antal og koder.
`sql` laver to filer: et persona-manifest (relation_persona, profil v2) for S/D/N og et
psql-identitetsscript, der køres efter batchen.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from relation_persona_extract_v2 import PROFILE, RULE, propose
from spouse_exception_sheet import _write_private, check_private_path

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
M_RE = re.compile(rf"^M (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>[SDNIU])\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^M {UUID} ")
# Hvilke svar et forslag tillader (spec §5.3): D/S kun hvor udtrækket foreslog dem; N kræver et navn.
ALLOWED = {"S": {"S", "N", "I", "U"}, "D": {"D", "N", "I", "U"}, "N": {"N", "I", "U"}, "I": {"I", "U"}, "U": {"I", "U"}}


@dataclass(frozen=True)
class Line:
    key: str
    version: int
    tok: str
    note: str
    line: int


def _ws(s: str | None) -> str:
    return " ".join((s or "").split())


def _proposals(rows: dict) -> list[dict]:
    return [propose(r, int(rows["deceased_cutoff_year"])) for r in rows["rows"]]


def render_sheet(rows: dict) -> str:
    cutoff = int(rows["deceased_cutoff_year"])
    out = ["# ÆGTESKABSARK (trin 5b 2b-ii)",
           "# S = samme som forslagets partner · D = ny person, afdød efter bogen (alle årstal senest grænseåret;",
           "#   hvert årstal kan være et fødselsår — er du i tvivl, så svar N)",
           "# N = ny person, kan ikke erklæres afdød (oprettes ikke nu) · I = intet navn i bogen · U = uafklaret",
           "# Ret kun undtagelser. Er navnespændet forkert, er svaret U. En note må følge efter '#'.",
           "# Gem, og giv hashen i chatten.", ""]
    n = len(rows["rows"])
    for i, (r, p) in enumerate(zip(rows["rows"], _proposals(rows)), 1):
        text = r["clauses"][0]["verbatim_text"] if r["clauses"] else ""
        out += [f"## ÆGTESKAB {i}/{n} · post {r.get('record_key') or '?'}",
                f"#   Bogen: »{_ws(text)}«"]
        if "name_from" in p:
            out.append(f"#   Ægtefællens navn: »{_ws(text[p['name_from']:p['name_to']])}«")
        partners = "; ".join(f"{_ws(x.get('navn')) or '(intet navn)'} ({x.get('foedt') or '?'}–{x.get('doed') or '?'})"
                             f" · familie {x.get('family_id')} · nr. {x.get('ordinal') if x.get('ordinal') is not None else '?'}"
                             for x in r.get("principal_partners", []))
        out.append(f"#   Hovedpersonens partnere: {partners or '(ingen)'}")
        if "clause_years" in p:
            years = ", ".join(str(y) for y in p["clause_years"]) or "(ingen)"
            out.append(f"#   Årstal i klausulen: {years} · grænse {cutoff}")
        out += [f"#   Forslag: {p['tok']} ({p['reason']})",
                f"M {r['interpretation_key']} {r['interpretation_version']} : {p['tok']}", ""]
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    lines: list[Line] = []
    for raw in text.splitlines():
        if not raw.strip() or raw.startswith("#"):
            continue
        m = M_RE.match(raw)
        if not m:
            raise SheetError("SHEET_LINE_INVALID" if LOOSE_RE.match(raw) else "SHEET_LINE_UNKNOWN")
        lines.append(Line(m["key"], int(m["ver"]), m["tok"], (m["note"] or "").strip(), len(lines) + 1))
    return lines


def check_sheet(lines: list[Line], rows: dict) -> list[dict]:
    expected = [(r["interpretation_key"], int(r["interpretation_version"])) for r in rows["rows"]]
    if not lines or [(l.key, l.version) for l in lines] != expected:
        raise SheetError("SHEET_IDENTITY_MISMATCH")
    props = _proposals(rows)
    for l, p in zip(lines, props):
        if l.tok not in ALLOWED[p["tok"]]:
            raise SheetError(f"SHEET_TOKEN_NOT_ALLOWED line={l.line}")
    return props


def persona_manifest(lines: list[Line], rows: dict) -> dict:
    props = check_sheet(lines, rows)
    elements = {}
    for l, r, p in zip(lines, rows["rows"], props):
        if l.tok not in ("S", "D", "N"):
            continue
        c = r["clauses"][0]
        elements["relation-persona:" + r["interpretation_key"]] = {
            "birth_raw": None, "clause_observation_id": c["observation_id"], "clause_set_seq": c["clause_set_seq"],
            "clause_set_sha256": c["clause_set_sha256"], "death_raw": None,
            "interpretation_key": r["interpretation_key"], "interpretation_version": r["interpretation_version"],
            "marriage_ordinal": r["marriage_ordinal"], "name_from": p["name_from"], "name_to": p["name_to"],
            "post_offset": c["post_char_from"] + p["span_from"], "predicate": "relation.marriage", "profile": PROFILE,
            "span_from": p["span_from"], "span_to": p["span_to"]}
    return {"expected_counts": {"person_creates": 0, "source_evidence": 0, "relation_personas": len(elements)},
            "authorized_elements": dict(sorted(elements.items()))}


def identity_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    props = check_sheet(lines, rows)
    cutoff = int(rows["deceased_cutoff_year"])
    todo = [(l, p) for l, p in zip(lines, props) if l.tok in ("S", "D", "N")]
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;", "SET LOCAL TimeZone='UTC';",
           "SET LOCAL search_path=pg_catalog,public,private;"]
    # Ægtefælle-personaen, som persona-batchen skrev, findes som ejer før rolleskiftet.
    for l, _ in todo:
        sql.append(f"SELECT source_persona_id AS p{l.line} FROM private.interpretation_party_current "
                   f"WHERE interpretation_key='{l.key}' AND party_role='spouse' AND source_persona_id IS NOT NULL \\gset")
    sql += ["SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
            "SET LOCAL ROLE authenticated;"]
    tag = sheet_sha256[:12]
    for l, p in todo:
        note = sql_literal(f"ark 2b-ii {tag} linje {l.line}" + (f" — {l.note}" if l.note else ""))
        ctx = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": l.line}
        if l.tok == "S":
            action, person = "same", str(int(p["partner_person_id"]))
        else:
            action, person = "new_person_needed", "NULL"
            if l.tok == "D":
                ctx["deceased"] = {"rule": RULE, "cutoff_year": cutoff, "clause_years": p["clause_years"]}
        sql.append(f"SELECT red_afgoer_source_persona(:'p{l.line}'::uuid, 0, '{action}', {person}, {note}, "
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
    for a in ("--sheet", "--approved-sha256", "--expect-rows-sha256", "--manifest-out", "--identity-out"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        rows_path = check_private_path(Path(args.rows), root)
        rows_bytes = rows_path.read_bytes()
        rows = json.loads(rows_bytes.decode("utf-8"))
        if args.cmd == "render":
            out = check_private_path(Path(args.out), root)
            _write_private(out, render_sheet(rows))
            c = {t: 0 for t in "SDNIU"}
            for p in _proposals(rows):
                c[p["tok"]] += 1
            print(f"ARK_OK s={c['S']} d={c['D']} n={c['N']} i={c['I']} u={c['U']}")
            return 0
        mout = check_private_path(Path(args.manifest_out), root)
        iout = check_private_path(Path(args.identity_out), root)
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        lines = parse_sheet(sheet_bytes.decode("utf-8"))
        manifest = persona_manifest(lines, rows)
        ident = identity_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
        _write_private(mout, json.dumps(manifest, sort_keys=True, ensure_ascii=False) + "\n")
        _write_private(iout, ident)
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK manifest={len(manifest['authorized_elements'])} identitet={ident.count('red_afgoer_source_persona(')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
