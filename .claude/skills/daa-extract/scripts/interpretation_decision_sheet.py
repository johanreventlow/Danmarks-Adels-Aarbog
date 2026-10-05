#!/usr/bin/env python3
"""Afgørelsesark for fortolkninger (spec §8.2): token-fil → red_decide_interpretation.

To hashes binder afgørelsen: arkets (det mennesket godkendte) og rækkefilens (det
eksakte sæt `(interpretation_id, version)`, arket blev bygget af). Oversættelsen
kræver, at arkets beslutninger dækker præcis det sæt — en slettet, indrykket eller
ombyttet linje stopper (4.5-review, fund 1).

Arket indeholder kildetekst og skrives 0600 uden for repoet. SQL'en bærer kun id'er,
status, de to hashes og menneskets noter.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal as _lit, verify_bound

TOKENS = {"A": "accepted", "R": "rejected", "U": "unresolved"}
LINE_RE = re.compile(
    r"^D (?P<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) "
    r"(?P<ver>[1-9][0-9]*) : (?P<tok>\S+)\s*(?:#\s*(?P<note>.*))?$")


@dataclass(frozen=True)
class Decision:
    interpretation_id: str
    version: int
    status: str
    note: str
    line: int


def reviewsignal(r: dict) -> list[str]:
    """ERRATA 8.2: signalet udledes af forespørgbare felter og persisteres ikke."""
    s = []
    if r["confidence"] < 0.8:
        s.append("lav confidence")
    if r["persona_role"] != "principal":
        s.append("anden person")
    if any(c["flags"] for c in r["cited"]):
        s.append("klausulflag")
    if len(r["cited"]) > 1:
        s.append("flere klausuler")
    return s


def sheet_order(rows: list[dict]) -> list[dict]:
    """Arkets faste orden — den samme ved render og ved identitetstjekket."""
    return sorted(rows, key=lambda r: (r["record_key"], r["predicate"], r["interpretation_id"]))


def render_sheet(rows: list[dict], prior: dict, *, title: str = "4.5",
                 prior_label: str = "4.3b") -> str:
    """`prior_label` siger, hvis dom forudfyldningen kommer fra — kontrolmodellen (decisions
    2026-09-27) forudfylder med projektejerens 4.5-afgørelser, ikke 4.3b's."""
    out = [f"# AFGØRELSE AF FORTOLKNINGSFORSLAG ({title})",
           "# Skriv A (accepter), R (afvis) eller U (uafklaret) efter kolonet.",
           "# En note må følge efter '#'. Ret intet andet. Gem, og giv hashen i chatten.",
           ""]
    for r in sheet_order(rows):
        dom = prior.get((r["record_key"], r["predicate"], r["value_text"]))
        anbefaling = {"J": f"A ({prior_label}: sand)", "N": f"R ({prior_label}: usand)"}.get(dom, "ingen")
        out.append(f"# POST {r['record_key']} · {r['predicate']} · confidence "
                   f"{r['confidence']} · {r['persona_role']}")
        for c in r["cited"]:
            flag = f"  flag: {','.join(c['flags'])}" if c["flags"] else ""
            out.append(f"#   [{c['ordinal']}] {c['text']}{flag}")
        out.append(f"#   værdi: {r['value_text']}        anbefaling: {anbefaling}")
        out.append(f"#   se nærmere: {', '.join(reviewsignal(r)) or 'nej'}")
        tok = {"J": "A", "N": "R"}.get(dom, "_")
        out.append(f"D {r['interpretation_id']} {r['version']} : {tok}")
        out.append("")
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Decision]:
    decisions, undecided, seen = [], [], set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line.startswith("D "):
            if line.lstrip().startswith("D "):
                raise SheetError(f"SHEET_LINE_INVALID line={n}")   # indrykket beslutning
            continue
        m = LINE_RE.match(line)
        if not m:
            raise SheetError(f"SHEET_LINE_INVALID line={n}")
        if m["id"] in seen:
            raise SheetError(f"SHEET_DUPLICATE line={n}")
        seen.add(m["id"])
        if m["tok"] == "_":
            undecided.append(n)
            continue
        if m["tok"] not in TOKENS:
            raise SheetError(f"SHEET_TOKEN_INVALID line={n}")
        decisions.append(Decision(m["id"], int(m["ver"]), TOKENS[m["tok"]],
                                  (m["note"] or "").strip(), n))
    if undecided:
        raise SheetError("SHEET_UNDECIDED lines=" + ",".join(map(str, undecided)))
    return decisions


def check_identity(decisions: list[Decision], rows: list[dict]) -> None:
    forventet = {(r["interpretation_id"], r["version"]) for r in rows}
    faktisk = {(d.interpretation_id, d.version) for d in decisions}
    if faktisk != forventet:
        raise SheetError(f"SHEET_IDENTITY_MISMATCH mangler={len(forventet - faktisk)} "
                         f"ekstra={len(faktisk - forventet)}")
    # Samme mængde er ikke nok: to D-linjer, der bytter plads, bytter også den
    # kommentarblok, mennesket afgjorde ud fra (4.5-kodereview, fund 3).
    for d, r in zip(decisions, sheet_order(rows)):
        if (d.interpretation_id, d.version) != (r["interpretation_id"], r["version"]):
            raise SheetError(f"SHEET_ORDER_MISMATCH line={d.line}")


#: Menneskelige afgørelsesmetoder. Kontrolmodellen (decisions 2026-09-27) tæller maskinelle og
#: menneskelige afgørelser på dette felt, så det er et lukket sæt.
SHEET_METHODS = ("human-sheet-4.5", "human-sheet-kontrol-v1")


def decision_sql(decisions: list[Decision], *, sheet_sha256: str, rows_sha256: str,
                 method: str = "human-sheet-4.5") -> str:
    if method not in SHEET_METHODS:
        raise SheetError("SHEET_METHOD_INVALID")
    require_hex64(sheet_sha256, rows_sha256)
    out = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL ROLE authenticated;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true);",
           "CREATE TEMP TABLE decided(id uuid) ON COMMIT DROP;"]
    for d in decisions:
        evidence = json.dumps({"method": method, "sheet_sha256": sheet_sha256,
                               "rows_sha256": rows_sha256, "line": d.line, "note": d.note},
                              ensure_ascii=False, sort_keys=True)
        out.append(f"INSERT INTO decided SELECT red_decide_interpretation("
                   f"'{d.interpretation_id}'::uuid, {d.version}, '{d.status}', "
                   f"{_lit(evidence)}::jsonb);")
    out.append("DO $$ BEGIN IF (SELECT count(*) FROM decided) <> "
               f"{len(decisions)} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;")
    out.append("COMMIT;")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("--rows", required=True)
    r.add_argument("--prior")
    r.add_argument("--out", required=True)
    r.add_argument("--title", default="4.5")
    r.add_argument("--prior-label", default="4.3b")
    h = sub.add_parser("html")
    h.add_argument("--rows", required=True)
    h.add_argument("--prior")
    h.add_argument("--sheet", help="påbegyndt ark; afgjorte linjer indlæses")
    h.add_argument("--mangler", help="påbegyndt MANGLER.txt")
    h.add_argument("--out", required=True)
    h.add_argument("--title", default="4.5")
    h.add_argument("--prior-label", default="4.3b")
    s = sub.add_parser("sql")
    s.add_argument("--sheet", required=True)
    s.add_argument("--approved-sha256", required=True)
    s.add_argument("--rows", required=True)
    s.add_argument("--expect-rows-sha256", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--method", default="human-sheet-4.5", choices=SHEET_METHODS)
    args = ap.parse_args()

    rows_bytes = Path(args.rows).read_bytes()
    rows_sha = hashlib.sha256(rows_bytes).hexdigest()
    rows = json.loads(rows_bytes.decode("utf-8"))

    prior = {}
    if args.cmd in ("render", "html") and args.prior:
        prior = {tuple(k.split("\x1f")): v for k, v in
                 json.loads(Path(args.prior).read_text(encoding="utf-8")).items()}

    if args.cmd == "html":
        from decision_sheet_html import build_payload, render_html
        try:
            payload = build_payload(
                rows, prior, rows_sha256=rows_sha,
                sheet_text=Path(args.sheet).read_text(encoding="utf-8") if args.sheet else None,
                mangler_text=Path(args.mangler).read_text(encoding="utf-8") if args.mangler else None,
                title=args.title, prior_label=args.prior_label)
        except SheetError as exc:
            print(str(exc))
            return 1
        out = Path(args.out)
        out.write_text(render_html(payload), encoding="utf-8")
        out.chmod(0o600)
        afgjort = sum(1 for it in payload["items"] if it["initial_tok"] != "_")
        mangler = sum(len(v.splitlines()) for v in payload["mangler"].values())
        print(f"HTML_OK forslag={len(payload['items'])} poster={len(payload['posts'])} "
              f"afgjort={afgjort} mangler_linjer={mangler} "
              f"uplacerede={len(payload['unplaced'].splitlines())}")
        print(f"  rows_sha256 {rows_sha}")
        return 0

    if args.cmd == "render":
        out = Path(args.out)
        out.write_text(render_sheet(rows, prior, title=args.title, prior_label=args.prior_label),
                       encoding="utf-8")
        out.chmod(0o600)
        forudfyldt = sum(1 for r in rows if (r["record_key"], r["predicate"], r["value_text"]) in prior)
        print(f"ARK_OK linjer={len(rows)} forudfyldt={forudfyldt}")
        print(f"  rows_sha256 {rows_sha}")
        return 0

    # Arket læses præcis én gang: hash og parsing bruger samme bytes (ingen TOCTOU).
    data = Path(args.sheet).read_bytes()
    try:
        rows_sha, faktisk = verify_bound(rows_bytes, args.expect_rows_sha256, data, args.approved_sha256)
    except SheetError as exc:
        print(str(exc))
        return 1
    try:
        decisions = parse_sheet(data.decode("utf-8"))
        check_identity(decisions, rows)
        sql = decision_sql(decisions, sheet_sha256=faktisk, rows_sha256=rows_sha,
                           method=args.method)
    except SheetError as exc:
        print(str(exc))
        return 1
    out = Path(args.out)
    out.write_text(sql, encoding="utf-8")
    out.chmod(0o600)
    tal = {st: sum(1 for d in decisions if d.status == st) for st in TOKENS.values()}
    print(f"SQL_OK afgørelser={len(decisions)} {tal}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
