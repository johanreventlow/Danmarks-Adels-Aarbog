#!/usr/bin/env python3
"""Kontrolark (trin 5b): blind stikprøve + uoverensstemmelser + relationslinjer i ét hash-bundet ark.

SQL'en forsegler kontrolkørslen med arkets og rækkefilens hash, afgør hver linje og evaluerer —
alt i én transaktion (spec §7.1). Stikprøvelinjer sendes som visningsplads; serveren opløser målet."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
D_RE = re.compile(rf"^D (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|[123]|P [1-9][0-9]*|X|N|U)\s*(?:#\s*(?P<note>.*))?$")
R_RE = re.compile(rf"^R (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|[123]|U)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^[DR] {UUID} [0-9]+ : ")


@dataclass(frozen=True)
class Line:
    kind: str          # 'D' eller 'R'
    item_id: str
    version: int
    tok: str
    note: str
    line: int


def _key(it: dict) -> tuple:
    return (it["record_key"], it["kind"], it.get("source_persona_id") or it.get("interpretation_key"))


def ordered(rows: dict) -> list[dict]:
    return sorted(rows["items"], key=_key)


MAX_LINES = 80


def split_rows(rows: dict, max_lines: int = MAX_LINES) -> list[dict]:
    """Del rækkefilen i ark (spec §7.3, errata §22). Hele stikprøven står i ark 1 — det eneste ark,
    der forsegler og evaluerer; ark 2.. bærer kun ikke-stikprøvelinjer."""
    items = ordered(rows)
    samples = [it for it in items if it["sample"]]
    rest = [it for it in items if not it["sample"]]
    if len(samples) > max_lines:
        raise SheetError(f"SHEET_SAMPLE_TOO_LARGE stikproeve={len(samples)} max={max_lines}")
    plads = max_lines - len(samples)
    parts = [samples + rest[:plads]] + [rest[i:i + max_lines] for i in range(plads, len(rest), max_lines)]
    return [{**rows, "items": sorted(p, key=_key), "part": n, "parts": len(parts), "seal": n == 1}
            for n, p in enumerate(parts, 1)]


def _cand_blind(d: dict) -> str:
    t = f"  · {', '.join(d['titles'])}" if d["titles"] else ""
    post = f"  · egen post {d['own_post_key']}" if d["own_post_key"] else ""
    return f"#   {d['position']}: {d['person_name'] or '(intet navn)'}  {d['born'] or '?'}–{d['died'] or '?'}{t}{post}"


def _cand_full(c: dict) -> str:
    t = f"  · {', '.join(c['titles'])}" if c["titles"] else ""
    fam = f"  familie {c['family_id']} nr {c['ordinal']}" if c.get("family_id") is not None else ""
    return (f"#   {c['rank']}: person {c['person_id']}  {c['person_name'] or '(intet navn)'}  {c['born'] or '?'}–{c['died'] or '?'}{t}"
            f"  score {c['score']}  {c['tier']}  [{', '.join(c['signals'])}]{fam}")


def render_sheet(rows: dict) -> str:
    out = ["# KONTROLARK (trin 5b) — ægtefæller og børn/forældre",
           "# D-linjer: 1/2/3 = samme som kandidat nr., 'P <id>' = anden person, X = ikke i basen,",
           "#           N = ny person nødvendig, U = uafklaret. R-linjer: 1/2/3 = familie nr., U = uafklaret.",
           "# En note må følge efter '#'. Ret intet andet. Gem, og giv hashen i chatten.", ""]
    if rows.get("parts", 1) > 1:   # et enkelt ark renderes uændret
        out.insert(1, f"# Ark {rows['part']} af {rows['parts']} — " + (
            "hele stikprøven; forsegler kontrolkørslen" if rows["seal"] else "kun uoverensstemmelser; anvendes efter ark 1"))
    for it in ordered(rows):
        if it["kind"] == "identity":
            out.append(f"# POST {it['record_key']} · ægtefælle nr. {it['marriage_ordinal']}: {it['name'] or '(intet navn)'}")
            if it["sample"]:
                out += [_cand_blind(d) for d in sorted(it["display"], key=lambda d: d["position"])]
            else:
                out.append(f"#   grund: {it['reason']}")
                out += [_cand_full(c) for c in it["candidates"]] or ["#   ingen kandidat"]
            out.append(f"D {it['source_persona_id']} {it['version']} : _")
        else:
            out.append(f"# POST {it['record_key']} · {it['predicate']}")
            out += [f"#   {f['position']}: familie med {f['counterpart_name']} (post {f['counterpart_post_key']})"
                    for f in it["families"]] or ["#   ingen familie"]
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
    forventet = [((it.get("source_persona_id") or it["interpretation_key"]), it["version"]) for it in ordered(rows)]
    if [(l.item_id, l.version) for l in lines] != forventet:
        raise SheetError("SHEET_IDENTITY_MISMATCH")


def _call(fn: str, args: str, ctx: dict) -> str:
    return (f"INSERT INTO decided SELECT {fn}({args}, "
            f"{sql_literal(json.dumps(ctx, ensure_ascii=False, sort_keys=True))}::jsonb);")


def decision_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    ctl = rows["control_run_id"]
    seal = rows.get("seal", True)
    if not seal and any(it["sample"] for it in rows["items"]):
        raise SheetError("SHEET_PART_INVALID stikprøvelinje uden for ark 1")
    by_id = {(it.get("source_persona_id") or it["interpretation_key"]): it for it in rows["items"]}
    out = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL ROLE authenticated;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
           "CREATE TEMP TABLE decided(v integer) ON COMMIT DROP;"]
    if seal:
        out.append(f"SELECT red_seal_identity_control_run('{ctl}'::uuid, '{sheet_sha256}', '{rows_sha256}');")
    for l in lines:
        it = by_id[l.item_id]
        base = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": l.line}
        note = sql_literal(f"ark {sheet_sha256[:12]} linje {l.line}" + (f" — {l.note}" if l.note else ""))
        if it["sample"]:
            base["control_run_id"] = ctl
        if l.kind == "D":
            pid = f"'{l.item_id}'::uuid, {l.version}"
            if l.tok in "123" and it["sample"]:
                out.append(_call("red_afgoer_source_persona", f"{pid}, 'same', NULL, {note}", {**base, "display_position": int(l.tok)}))
            elif l.tok in "123":
                c = next((c for c in it["candidates"] if c["rank"] == int(l.tok)), None)
                if c is None:
                    raise SheetError(f"SHEET_CANDIDATE_MISSING line={l.line}")
                out.append(_call("red_afgoer_source_persona", f"{pid}, 'same', {int(c['person_id'])}, {note}",
                                 {**base, "candidate_id": c["candidate_id"], "run_id": it["run_id"]}))
            elif l.tok.startswith("P "):
                out.append(_call("red_afgoer_source_persona", f"{pid}, 'same', {int(l.tok[2:])}, {note}", base))
            else:
                act = {"X": "different", "N": "new_person_needed", "U": "unresolved"}[l.tok]
                out.append(_call("red_afgoer_source_persona", f"{pid}, '{act}', NULL, {note}", base))
        else:
            key = f"'{l.item_id}'::uuid, {l.version}"
            if l.tok == "U":
                out.append(_call("red_afgoer_relation_interpretation", f"{key}, 'unresolved', NULL, {note}", base))
            elif it["sample"]:
                out.append(_call("red_afgoer_relation_interpretation", f"{key}, 'same', NULL, {note}",
                                 {**base, "display_position": int(l.tok)}))
            else:
                f = next((f for f in it["families"] if f["position"] == int(l.tok)), None)
                if f is None:
                    raise SheetError(f"SHEET_CANDIDATE_MISSING line={l.line}")
                out.append(_call("red_afgoer_relation_interpretation", f"{key}, 'same', {int(f['family_id'])}, {note}", base))
    out.append(f"DO $$ BEGIN IF (SELECT count(*) FROM decided) <> {len(lines)} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;")
    if seal:
        out.append(f"SELECT red_evaluate_identity_control_run('{ctl}'::uuid) AS kontrolstatus;")
    out.append("COMMIT;")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render"); r.add_argument("--rows", required=True); r.add_argument("--out", required=True)
    s = sub.add_parser("sql")
    for a in ("--sheet", "--approved-sha256", "--rows", "--expect-rows-sha256", "--out"):
        s.add_argument(a, required=True)
    s.add_argument("--part", type=int, default=1)
    args = ap.parse_args()
    rows_bytes = Path(args.rows).read_bytes()
    alle = json.loads(rows_bytes.decode("utf-8"))
    if args.cmd == "render":
        try:
            parts = split_rows(alle)
        except SheetError as exc:
            print(str(exc)); return 1
        out = Path(args.out)
        for part in parts:
            f = out if part["part"] == 1 else out.with_name(f"{out.stem}-{part['part']}{out.suffix}")
            f.write_text(render_sheet(part), encoding="utf-8"); f.chmod(0o600)
        n_s = sum(1 for it in alle["items"] if it["sample"])
        print(f"ARK_OK ark={len(parts)} linjer={len(alle['items'])} stikproeve={n_s} uoverensstemmelser={len(alle['items']) - n_s}")
        print(f"  rows_sha256 {hashlib.sha256(rows_bytes).hexdigest()}")
        return 0
    sheet_bytes = Path(args.sheet).read_bytes()          # læses præcis én gang
    try:
        parts = split_rows(alle)
        if not 1 <= args.part <= len(parts):
            raise SheetError(f"SHEET_PART_INVALID part={args.part} af {len(parts)}")
        rows = parts[args.part - 1]
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        tekst = sheet_bytes.decode("utf-8")
        check_render(tekst, rows)
        lines = parse_sheet(tekst)
        check_identity(lines, rows)
        sql = decision_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
    except SheetError as exc:
        print(str(exc)); return 1
    out = Path(args.out); out.write_text(sql, encoding="utf-8"); out.chmod(0o600)
    print(f"SQL_OK linjer={len(lines)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
