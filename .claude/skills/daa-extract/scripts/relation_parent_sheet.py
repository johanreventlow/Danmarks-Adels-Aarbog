"""Trin 6c-3: forælderarket — ét hash-bundet ark for `relation.parent`-fortolkninger.

Rækkefilen (relation_parent_rows.sql) findes i to kontrakter. v1: kun nøgler, versioner, persona-id'er og
familie-kandidater (ingen navne). v2 (6d-3): tilføjer kontekst — postens tekst, klausul/side, barnets og
kandidatfamiliernes forældre og børn med navne og datoer — og er derfor PII: den SKAL ligge under ~/.private. Begge
kontrakter accepteres; `render --html` viser konteksten (kun v2). Rækkefilens sha indgår uændret i arkets
hash-binding. Værktøjet printer kun antal og koder. B binder til den ENESTE familie-kandidat; ingen eller flere kandidater
giver ikke B (PARENT_FAMILY_NOT_UNIQUE). Serveren genberegner kandidaterne og afviser et forældet valg.
Hjælpere genbruges fra relation_child_sheet (ingen kopi).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import html as _html
import re
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal
from relation_child_sheet import Line, TOKENS, UUID, load_keys, select_rows, selected_rows_sha256
from private_io import check_private_path, write_private_new_many, write_private_replace

CONTRACT = "relation-parent-sheet-input-v1"
CONTRACT_V2 = "relation-parent-sheet-input-v2"
CONTRACTS = (CONTRACT, CONTRACT_V2)
P_RE = re.compile(rf"^P (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>\S+)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^P {UUID} ")
HASH_RE = re.compile(r"^# rows_sha256: ([0-9a-f]{64})$", re.M)

__all__ = ["render_html", "render_sheet", "parse_sheet", "check_sheet", "sheet_rows", "decision_sql", "selected_rows_sha256", "main"]


def _rows(rows: dict) -> dict[str, dict]:
    if rows.get("contract") not in CONTRACTS:
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
        if rows["contract"] == CONTRACT_V2:
            pr = r.get("principal") or {}
            out.append(f"#     barn: {_person_line(pr)} · post {r.get('record_key') or '?'}")
        out.append(f"P {r['interpretation_key']} {r['interpretation_version']} : {'B' if fam is not None else 'U'}")
    return "\n".join(out) + "\n"


def _person_line(p: dict) -> str:
    years = f" ({p.get('foedt') or '?'}–{p.get('doed') or ''})" if (p.get("foedt") or p.get("doed")) else ""
    return f"{p.get('navn') or '(uden navn)'}{years}"


def _locate(post: str, cl: dict) -> tuple[int, int] | None:
    """Klausulens plads i posten: offsets hvis de passer, ellers første forekomst; ellers ingen markering."""
    t = cl.get("text") or ""
    a, b = cl.get("post_char_from"), cl.get("post_char_to")
    if isinstance(a, int) and isinstance(b, int) and post[a:b] == t and t:
        return a, b
    i = post.find(t) if t else -1
    return (i, i + len(t)) if i >= 0 else None


HTML_CSS = """:root{--bg:#fbfaf7;--fg:#1d1b18;--mut:#6b665e;--card:#fff;--bd:#d8d3c8;--hl:#ffe58a;--ok:#1d6b3a;--warn:#9a5b00}
@media (prefers-color-scheme:dark){:root{--bg:#161513;--fg:#ece8df;--mut:#a39d91;--card:#201e1b;--bd:#3a3731;--hl:#6b5a14;--ok:#7bd096;--warn:#e0a84a}}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,sans-serif}
main{max-width:880px;margin:0 auto}h1{font-size:1.2rem}
.card{background:var(--card);border:1px solid var(--bd);border-radius:8px;padding:12px 16px;margin:16px 0}
.card h2{font-size:1rem;margin:0 0 4px}.mut{color:var(--mut);font-size:.9rem}
blockquote{margin:8px 0;padding:8px 12px;border-left:3px solid var(--bd);white-space:pre-wrap}
mark{background:var(--hl);color:inherit;padding:0 2px;border-radius:2px}
.fam{border-top:1px dashed var(--bd);margin-top:8px;padding-top:8px}.fam b{display:inline-block;min-width:5.5em}
ul{margin:2px 0 6px;padding-left:20px}.me{font-weight:600}.none{color:var(--warn)}code{font-size:.85rem}"""


def _p_li(p: dict, principal_id) -> str:
    me = ' class="me"' if p.get("person_id") == principal_id else ""
    liv = " · levende" if p.get("levende") else ""
    return f"<li{me}>{_html.escape(_person_line(p))}{liv}</li>"


def render_html(rows: dict) -> str:
    """Lokal, selvstændig kontekstside (ingen eksterne ressourcer; alt escapes). Kræver v2-rækkefilen."""
    if rows.get("contract") != CONTRACT_V2:
        raise SheetError("ROWS_CONTEXT_MISSING")
    e = _html.escape
    out = ["<!doctype html><html lang=\"da\"><head><meta charset=\"utf-8\">",
           "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
           "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'\">",
           f"<title>Forælderark</title><style>{HTML_CSS}</style></head><body><main>",
           f"<h1>Forælderark — kontekst</h1><p class=\"mut\">rows_sha256: {selected_rows_sha256(rows)}. "
           "Svar i token-arket (B / R / U); denne side er kun læsning. Indeholder navne og kildetekst — må ikke deles.</p>"]
    for r in sorted(rows["rows"], key=lambda r: r["row_no"]):
        pr = r.get("principal") or {}
        post = r.get("post_text") or ""
        out.append(f"<section class=\"card\"><h2>[{r['row_no']}] {e(_person_line(pr))} — post "
                   f"{e(str(r.get('record_key') or '?'))}</h2>")
        pages = sorted({(c.get("page_from"), c.get("page_to")) for c in r.get("clauses", [])},
                       key=lambda x: (x[0] is None, x[0] or 0, x[1] or 0))
        pg = ", ".join(str(a) if a == b else f"{a}–{b}" for a, b in pages)
        out.append(f"<div class=\"mut\">side {e(pg or '?')} · påstand <code>{e(r['interpretation_key'])}</code> "
                   f"v{r['interpretation_version']} · {len(r['candidates'])} familie-kandidat(er)</div>")
        spans = sorted(s for s in (_locate(post, c) for c in r.get("clauses", [])) if s)
        buf, pos = [], 0
        for a, b in spans:
            if a < pos:
                continue
            buf.append(e(post[pos:a])); buf.append(f"<mark>{e(post[a:b])}</mark>"); pos = b
        buf.append(e(post[pos:]))
        out.append(f"<blockquote>{''.join(buf) or '(ingen posttekst)'}</blockquote>")
        if not spans and r.get("clauses"):
            out.append("<div class=\"mut\">Klausul: " + " | ".join(e(c.get("text") or "") for c in r["clauses"]) + "</div>")
        if not r["candidates"]:
            out.append("<p class=\"none\">Ingen familie-kandidat — B er ikke muligt.</p>")
        for c in r["candidates"]:
            out.append(f"<div class=\"fam\"><b>Familie {e(str(c['family_id']))}</b>")
            out.append("<div class=\"mut\">Forældre</div><ul>"
                       + "".join(_p_li(p, None) for p in c.get("partners", [])) + "</ul>")
            out.append("<div class=\"mut\">Børn (barnet fra kortet er fremhævet)</div><ul>"
                       + "".join(_p_li(p, pr.get("person_id")) for p in c.get("children", [])) + "</ul></div>")
        out.append("</section>")
    out.append("</main></body></html>\n")
    return "\n".join(out)


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
    r.add_argument("--html", help="skriv også en lokal kontekstside (kræver rækkefil v2; samme valg af rækker)")
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
            html_out = check_private_path(Path(args.html), root) if args.html else None
            if html_out is not None:
                page = render_html(sel)
            # Ark (+ html) til udfyldning: nægtes, før noget skrives, hvis én af dem findes.
            write_private_new_many([(out, render_sheet(sel))]
                                   + ([(html_out, page)] if html_out is not None else []))
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
        write_private_replace(out, sql)
        toks = [l.tok for l in lines]
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK b={toks.count('B')} r={toks.count('R')} u={toks.count('U')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
