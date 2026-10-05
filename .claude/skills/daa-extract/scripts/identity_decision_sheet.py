#!/usr/bin/env python3
"""Identitetsark (trin 5a): token-fil → red_afgoer_source_persona med basis human_sheet.

Rækkefilen (0600, uden for repoet) binder personas, versioner og kandidatkørslen. Et
kandidat-token (1/2/3) betyder altid den kandidat, redaktøren så: SQL'en stopper, hvis
kørslen ikke længere er den seneste for kilden."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
LINE_RE = re.compile(rf"^D (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|[123]|P [1-9][0-9]*|X|N|U)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^D {UUID} [0-9]+ : ")
TIER_ORDER = {"auto": 0, "review": 1, "none": 2}


@dataclass(frozen=True)
class IdDecision:
    persona_id: str
    version: int
    action: str
    person_id: int | None
    candidate_rank: int | None
    note: str
    line: int


def _best(r: dict) -> tuple:
    c = r["candidates"][0] if r["candidates"] else None
    return (TIER_ORDER[c["tier"]] if c else 3, -(c["score"] if c else 0), r["source_persona_id"])


def sheet_order(rows: list[dict]) -> list[dict]:
    return sorted(rows, key=_best)


def render_sheet(rows: list[dict]) -> str:
    out = ["# IDENTITETSAFGØRELSER (trin 5a)",
           "# Efter kolonet: 1/2/3 = samme som kandidat nr., 'P <id>' = samme som anden person,",
           "# X = en anden person (ikke i basen), N = ny person nødvendig, U = uafklaret.",
           "# En note må følge efter '#'. Ret intet andet. Gem, og giv hashen i chatten.", ""]
    for r in sheet_order(rows):
        out.append(f"# POST {r['record_key']} · persona: {r['name'] or '(intet navn)'} · nævnt som: {r['mention_role']}")
        fort = " · ".join(f"{i['predicate']} {i['value_text']} ({i['status']})" for i in r["interpretations"])
        out.append(f"#   fortolkninger: {fort or 'ingen'}")
        if not r["candidates"]:
            out.append("#   ingen kandidat")
        for c in r["candidates"]:
            out.append(f"#   {c['rank']}: person {c['person_id']}  {c['person_name']}  {c['born'] or '?'}–{c['died'] or '?'}"
                       f"  score {c['score']}  {c['tier']}  [{', '.join(c['signals'])}]")
        out.append("#   ingen anbefaling udfyldt — vælg selv")
        out.append(f"D {r['source_persona_id']} {r['version']} : _")
        out.append("")
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[IdDecision]:
    decisions, undecided, seen = [], [], set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line.startswith("D "):
            if line.lstrip().startswith("D "):
                raise SheetError(f"SHEET_LINE_INVALID line={n}")
            continue
        m = LINE_RE.match(line)
        if not m:
            raise SheetError(f"SHEET_TOKEN_INVALID line={n}" if LOOSE_RE.match(line) else f"SHEET_LINE_INVALID line={n}")
        if m["id"] in seen:
            raise SheetError(f"SHEET_DUPLICATE line={n}")
        seen.add(m["id"])
        tok, note = m["tok"], (m["note"] or "").strip()
        if tok == "_":
            undecided.append(n)
            continue
        if tok in "123":
            d = IdDecision(m["id"], int(m["ver"]), "same", None, int(tok), note, n)
        elif tok.startswith("P "):
            d = IdDecision(m["id"], int(m["ver"]), "same", int(tok[2:]), None, note, n)
        else:
            d = IdDecision(m["id"], int(m["ver"]), {"X": "different", "N": "new_person_needed", "U": "unresolved"}[tok],
                           None, None, note, n)
        decisions.append(d)
    if undecided:
        raise SheetError("SHEET_UNDECIDED lines=" + ",".join(map(str, undecided)))
    return decisions


def check_identity(decisions: list[IdDecision], rows: list[dict]) -> None:
    forventet = {(r["source_persona_id"], r["version"]) for r in rows}
    faktisk = {(d.persona_id, d.version) for d in decisions}
    if faktisk != forventet:
        raise SheetError(f"SHEET_IDENTITY_MISMATCH mangler={len(forventet - faktisk)} ekstra={len(faktisk - forventet)}")
    for d, r in zip(decisions, sheet_order(rows)):
        if (d.persona_id, d.version) != (r["source_persona_id"], r["version"]):
            raise SheetError(f"SHEET_ORDER_MISMATCH line={d.line}")


def check_render(text: str, rows: list[dict]) -> None:
    """Arket skal være præcis det, render_sheet byggede af rækkefilen — kun token og note på D-linjerne
    må være ændret. Ellers kan en rettet kandidatlinje vise én person, mens tokenet binder en anden."""
    forventet, faktisk = render_sheet(rows).splitlines(), text.splitlines()
    if len(faktisk) != len(forventet):
        raise SheetError(f"SHEET_RENDER_MISMATCH lines={len(faktisk)} forventet={len(forventet)}")
    for n, (f, a) in enumerate(zip(forventet, faktisk), 1):
        if f.startswith("D "):
            if not a.startswith(f[:f.rindex(" : ") + 3]):
                raise SheetError(f"SHEET_RENDER_MISMATCH line={n}")
        elif a != f:
            raise SheetError(f"SHEET_RENDER_MISMATCH line={n}")


def decision_sql(decisions: list[IdDecision], rows: list[dict], *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    by_id = {r["source_persona_id"]: r for r in rows}
    # Kandidatens kørsel sendes med; RPC'en afviser en forældet kørsel under kildelåsen (Task 3).
    out = ["\\set ON_ERROR_STOP on", "BEGIN;"]
    out += ["SET LOCAL ROLE authenticated;", "SELECT set_config('request.jwt.claim.sub', :'actor', true);",
            "CREATE TEMP TABLE decided(v integer) ON COMMIT DROP;"]
    for d in decisions:
        r = by_id[d.persona_id]
        ctx = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": d.line}
        person = d.person_id
        if d.candidate_rank is not None:
            cand = next((c for c in r["candidates"] if c["rank"] == d.candidate_rank), None)
            if cand is None:
                raise SheetError(f"SHEET_CANDIDATE_MISSING line={d.line}")
            person, ctx["candidate_id"], ctx["run_id"] = cand["person_id"], cand["candidate_id"], r["run_id"]
        note = f"ark {sheet_sha256[:12]} linje {d.line}" + (f" — {d.note}" if d.note else "")
        person_sql = str(int(person)) if person is not None else "NULL"
        out.append(f"INSERT INTO decided SELECT red_afgoer_source_persona('{d.persona_id}'::uuid, {d.version}, "
                   f"'{d.action}', {person_sql}, {sql_literal(note)}, "
                   f"{sql_literal(json.dumps(ctx, ensure_ascii=False, sort_keys=True))}::jsonb);")
    out.append("DO $$ BEGIN IF (SELECT count(*) FROM decided) <> "
               f"{len(decisions)} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;")
    out.append("COMMIT;")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render"); r.add_argument("--rows", required=True); r.add_argument("--out", required=True)
    s = sub.add_parser("sql")
    for a in ("--sheet", "--approved-sha256", "--rows", "--expect-rows-sha256", "--out"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    rows_bytes = Path(args.rows).read_bytes()
    rows = json.loads(rows_bytes.decode("utf-8"))
    if args.cmd == "render":
        out = Path(args.out); out.write_text(render_sheet(rows), encoding="utf-8"); out.chmod(0o600)
        print(f"ARK_OK linjer={len(rows)} uden_kandidat={sum(1 for x in rows if not x['candidates'])}")
        print(f"  rows_sha256 {hashlib.sha256(rows_bytes).hexdigest()}")
        return 0
    try:
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256,
                                           Path(args.sheet).read_bytes(), args.approved_sha256)
        check_render(Path(args.sheet).read_text(encoding="utf-8"), rows)
        decisions = parse_sheet(Path(args.sheet).read_text(encoding="utf-8"))
        check_identity(decisions, rows)
        sql = decision_sql(decisions, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
    except SheetError as exc:
        print(str(exc))
        return 1
    out = Path(args.out); out.write_text(sql, encoding="utf-8"); out.chmod(0o600)
    tal = {a: sum(1 for d in decisions if d.action == a) for a in ("same", "different", "new_person_needed", "unresolved")}
    print(f"SQL_OK afgørelser={len(decisions)} {tal}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
