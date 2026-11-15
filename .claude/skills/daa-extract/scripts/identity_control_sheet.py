#!/usr/bin/env python3
"""Kontrolark (trin 5b del 1, spec §23): blinde ægtefællekort + forældrekort i ét hash-bundet ark.

Hvert kort viser hovedpersonen, bogens ordrette klausul og kandidaternes egne data, så det kan afgøres
med bogen ved hånden. SQL'en har to transaktioner: (1) forsegling, ægtefællernes afgørelser og
evaluering, (2) forældrekortene — en forældrelinje kan aldrig rulle identitetsdelen tilbage (§23.4).
Ægtefællelinjer sendes som visningsplads, forældrelinjer uden familie-id; serveren opløser målet."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from private_io import write_private_new, write_private_replace

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
D_RE = re.compile(rf"^D (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|[123](?:=[123]){{0,2}}|X|N|U)\s*(?:#\s*(?P<note>.*))?$")
R_RE = re.compile(rf"^R (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|A|R|F|U)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^[DR] {UUID} [0-9]+ : ")


@dataclass(frozen=True)
class Line:
    kind: str          # 'D' eller 'R'
    item_id: str
    version: int
    tok: str
    note: str
    line: int


def _positions(tok: str) -> list[int] | None:
    """`2` → [2]; `2=1` → [1, 2] (dublet: samme individ på flere pladser). None ved gentaget plads."""
    ps = [int(x) for x in tok.split("=")]
    return sorted(ps) if len(set(ps)) == len(ps) else None


def _id(it: dict) -> str:
    return it.get("source_persona_id") or it["interpretation_key"]


def _key(it: dict) -> tuple:
    return (0 if it["kind"] == "identity" else 1, it["record_key"], _id(it))


def ordered(rows: dict) -> list[dict]:
    return sorted(rows["items"], key=_key)


def _ws(s: str | None) -> str:
    """Én linje: OCR-tekst kan rumme linjeskift, som ellers ville bryde arkets linjeformat."""
    return " ".join((s or "").split())


def _years(p: dict) -> str:
    return f"{p.get('born') or '?'}–{p.get('died') or '?'}"


def _who(p: dict) -> str:
    return f"{_ws(p.get('name')) or '(intet navn)'} ({_years(p)})"


def _clause(it: dict) -> str:
    t = it["text"]
    if it.get("span"):
        a, b = it["span"]
        t = t[:a] + "[[" + t[a:b] + "]]" + t[b:]
    return f"#   Bogen: »{_ws(t)}«"


def render_sheet(rows: dict) -> str:
    out = ["# KONTROLARK (trin 5b del 1)",
           "# Ægtefællekort (D): 1/2/3 = samme person som kandidat nr., X = ingen af dem, N = ny person nødvendig, U = kan ikke afgøres.",
           "#   1=2 = kandidat 1 og 2 er samme individ (dublet i basen), og ægtefællen er ham/hende (også 1=3, 2=3, 1=2=3).",
           "# Forældrekort (R): A = sandt, R = bogen siger ikke dette, F = bogen siger det, men familien i basen passer ikke, U = kan ikke afgøres.",
           "# Afgør ud fra bogen. En note må følge efter '#'. Ret intet andet. Gem, og giv hashen i chatten.", ""]
    items = ordered(rows)
    n_d = sum(1 for it in items if it["kind"] == "identity")
    n_r = len(items) - n_d
    d = r = 0
    for it in items:
        if it["kind"] == "identity":
            d += 1
            out.append(f"## ÆGTEFÆLLEKORT {d}/{n_d} · post {it['record_key']} · PDF-side {it['pages']} · ægteskab nr. {it['marriage_ordinal']}")
            out.append(f"#   Hovedperson: {_who(it['principal'])}")
            out.append(_clause(it))
            for c in sorted(it["display"], key=lambda c: c["position"]):
                t = f"  · {', '.join(_ws(x) for x in c['titles'])}" if c["titles"] else ""
                post = f"  · egen post {c['own_post_key']}" if c["own_post_key"] else ""
                out.append(f"#   {c['position']}: {_who(c)}{t}{post}")
                if c["parents"]:
                    out.append("#        forældre: " + ", ".join(_who(x) for x in c["parents"]))
            out.append(f"D {it['source_persona_id']} {it['version']} : _")
        else:
            r += 1
            out.append(f"## FORÆLDREKORT {r}/{n_r} · post {it['record_key']} · PDF-side {it['pages']}")
            out.append(f"#   Hovedperson: {_who(it['principal'])}")
            out.append(_clause(it))
            fam = "; ".join(_who(x) + (f" · egen post {x['own_post_key']}" if x["own_post_key"] else "")
                            + (" ← modpart" if x["counterpart"] else "") for x in it["partners"])
            out.append(f"#   Familie: {fam}")
            hvor = "i [[…]]" if it.get("span") else "i sætningen"
            out.append(f"#   Spørgsmål: Er den markerede (←) den forælder, bogen nævner {hvor}?")
            out.append(f"R {it['interpretation_key']} {it['version']} : _")
        out.append("")
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    res, undecided, seen = [], [], set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not (line.startswith("D ") or line.startswith("R ")):
            if line.lstrip().startswith(("D ", "R ")):
                raise SheetError(f"SHEET_LINE_INVALID line={n}")
            continue
        m = (D_RE if line.startswith("D ") else R_RE).match(line)
        if not m:
            raise SheetError(f"SHEET_TOKEN_INVALID line={n}" if LOOSE_RE.match(line) else f"SHEET_LINE_INVALID line={n}")
        if line[0] == "D" and m["tok"][0] in "123" and _positions(m["tok"]) is None:
            raise SheetError(f"SHEET_TOKEN_INVALID line={n}")
        if m["id"] in seen:
            raise SheetError(f"SHEET_DUPLICATE line={n}")
        seen.add(m["id"])
        if m["tok"] == "_":
            undecided.append(n); continue
        res.append(Line(line[0], m["id"], int(m["ver"]), m["tok"], (m["note"] or "").strip(), n))
    if undecided:
        raise SheetError("SHEET_UNDECIDED lines=" + ",".join(map(str, undecided)))
    return res


def check_render(text: str, rows: dict) -> None:
    forventet, faktisk = render_sheet(rows).splitlines(), text.splitlines()
    if len(faktisk) != len(forventet):
        raise SheetError(f"SHEET_RENDER_MISMATCH lines={len(faktisk)} forventet={len(forventet)}")
    for n, (f, a) in enumerate(zip(forventet, faktisk), 1):
        if f.startswith(("D ", "R ")):
            if not a.startswith(f[:f.rindex(" : ") + 3]):
                raise SheetError(f"SHEET_RENDER_MISMATCH line={n}")
        elif a != f:
            raise SheetError(f"SHEET_RENDER_MISMATCH line={n}")


def check_identity(lines: list[Line], rows: dict) -> None:
    forventet = [(_id(it), it["version"]) for it in ordered(rows)]
    if [(l.item_id, l.version) for l in lines] != forventet:
        raise SheetError("SHEET_IDENTITY_MISMATCH")


def _ctx(ctx: dict) -> str:
    return f"{sql_literal(json.dumps(ctx, ensure_ascii=False, sort_keys=True))}::jsonb"


def _call(fn: str, args: str, ctx: dict) -> str:
    return f"INSERT INTO decided SELECT {fn}({args}, {_ctx(ctx)});"


def decision_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    ctl = rows["control_run_id"]
    # sql_literal fordobler kun '; backslash i en note skal være bogstavelig i sessionen
    head = ["BEGIN;", "SET LOCAL standard_conforming_strings=on;", "SET LOCAL ROLE authenticated;",
            "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
            "CREATE TEMP TABLE decided(v integer) ON COMMIT DROP;"]
    t1 = ["\\set ON_ERROR_STOP on", *head,
          f"SELECT red_seal_identity_control_run('{ctl}'::uuid, '{sheet_sha256}', '{rows_sha256}');"]
    t2 = list(head)
    n1 = n2 = 0
    shown = {it["source_persona_id"]: {c["position"] for c in it["display"]} for it in rows["items"] if it["kind"] == "identity"}
    for l in lines:
        base = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": l.line,
                "control_run_id": ctl}
        note = sql_literal(f"ark {sheet_sha256[:12]} linje {l.line}" + (f" — {l.note}" if l.note else ""))
        if l.kind == "D":
            pid = f"'{l.item_id}'::uuid, {l.version}"
            if l.tok[0] in "123":
                ps = _positions(l.tok)
                if not set(ps) <= shown[l.item_id]:
                    raise SheetError(f"SHEET_POSITION_INVALID line={l.line}")
                ctx = {**base, "display_position": ps[0]}
                if len(ps) > 1:
                    ctx["display_positions"] = ps          # §23.4 errata: dublet; serveren binder efter dubletreglen (familiens post)
                t1.append(_call("red_afgoer_source_persona", f"{pid}, 'same', NULL, {note}", ctx))
            else:
                act = {"X": "different", "N": "new_person_needed", "U": "unresolved"}[l.tok]
                t1.append(_call("red_afgoer_source_persona", f"{pid}, '{act}', NULL, {note}", base))
            n1 += 1
        elif l.tok == "U":
            continue                                   # §23.4: U skriver intet; påstanden forbliver proposed
        else:
            key = f"'{l.item_id}'::uuid, {l.version}"
            if l.tok == "F":
                t2.append(f"INSERT INTO decided SELECT red_classify_parent_card('{ctl}'::uuid, {key}, 'F', {note}, {_ctx(base)});")
            else:
                act = {"A": "same", "R": "rejected"}[l.tok]
                t2.append(_call("red_afgoer_relation_interpretation", f"{key}, '{act}', NULL, {note}", base))
            n2 += 1
    t1 += [f"DO $$ BEGIN IF (SELECT count(*) FROM decided) <> {n1} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;",
           f"SELECT red_evaluate_identity_control_run('{ctl}'::uuid) AS kontrolstatus;", "COMMIT;"]
    t2 += [f"DO $$ BEGIN IF (SELECT count(*) FROM decided) <> {n2} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;",
           "SELECT 'familie_aendret=' || count(*) FROM decided WHERE v = 0;", "COMMIT;"]
    return "\n".join(t1 + t2) + "\n"


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
        # Udfyldbart menneskeark: et eksisterende (måske udfyldt) ark overskrives aldrig.
        write_private_new(Path(args.out), render_sheet(rows))
        n_d = sum(1 for it in rows["items"] if it["kind"] == "identity")
        n_h = sum(1 for it in rows["items"] if it["kind"] == "identity" and it.get("stratum") == "navnefaelle")
        print(f"ARK_OK aegtefaellekort={n_d} foraeldrekort={len(rows['items']) - n_d} navnefaeller={n_h}")
        print(f"  rows_sha256 {hashlib.sha256(rows_bytes).hexdigest()}")
        return 0
    sheet_bytes = Path(args.sheet).read_bytes()          # læses præcis én gang
    try:
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        tekst = sheet_bytes.decode("utf-8")
        check_render(tekst, rows)
        lines = parse_sheet(tekst)
        check_identity(lines, rows)
        sql = decision_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
    except SheetError as exc:
        print(str(exc)); return 1
    write_private_replace(Path(args.out), sql)
    print(f"SQL_OK linjer={len(lines)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
