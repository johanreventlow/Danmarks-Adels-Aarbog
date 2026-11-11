"""Trin 5b 2b-ii runde 2 (spec §17.6): ægteskabsark v3 — M-linjer med navnerettelse, P-linjer til genafgørelse.

Arket og rækkefilen rummer navne og bogens tekst; værktøjet printer kun antal og koder. `sql` laver et
persona-manifest (profil v3, med arkets hash og linje) og ét identitetsscript (M og P i samme transaktion).
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from relation_marriage_sheet import _ws
from relation_persona_extract_v3 import RULE, NameOverrideError, load_profile, propose, propose_redecide
from spouse_exception_sheet import _write_private, check_private_path

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
M_RE = re.compile(rf"^M (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>[SDNIU])"
                  rf"(?:\s+navn:\s*»(?P<navn>[^»«]+)«)?\s*(?:#\s*(?P<note>.*))?$")
P_RE = re.compile(rf"^P (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>[DNU])\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^[MP] {UUID} ")
# S kan ikke blive N (D/N kræver nul partnertræf, spec §17.4); U løftes kun via genberegning på rettet navn.
ALLOWED = {"S": {"S", "I", "U"}, "D": {"D", "N", "I", "U"}, "N": {"N", "I", "U"}, "I": {"I", "U"}, "U": {"I", "U"}}
ALLOWED_P = {"D": {"D", "N", "U"}, "N": {"N", "U"}, "U": {"N", "U"}}


@dataclass(frozen=True)
class Line:
    kind: str
    key: str
    version: int
    tok: str
    navn: str | None
    note: str
    line: int


def _profile(profile: dict | None) -> dict:
    """Profilen (6d-3): relation_profile, predicate_forms og text_form læses fra profilfilen (load_profile); uden
    profil gælder standardprofilen (2018-20-v3), så arket opfører sig som hidtil. Arket kender kun ægteskaber (v3)."""
    p = profile if profile is not None else load_profile(None)
    if p["predicate_forms"].get("relation.marriage") != "v3":
        raise SheetError("PROFILE_MARRIAGE_FORM_INVALID")
    return p


def _cutoff(rows: dict) -> int:
    return int(rows["deceased_cutoff_year"])


def render_sheet(rows: dict, profile: dict | None = None) -> str:
    tf = _profile(profile)["text_form"]
    cutoff = _cutoff(rows)
    out = ["# ÆGTESKABSARK v3 (trin 5b 2b-ii runde 2)",
           "# S = samme som forslagets partner · D = ny person, afdød efter bogen (alle årstal senest grænseåret)",
           "# N = ny person, kan ikke erklæres afdød (oprettes ikke nu) · I = intet navn i bogen · U = uafklaret",
           "# Er navnet forkert afsluttet, så skriv efter svaret:  navn: »navnet præcis som i bogen«",
           "#   (det skal begynde, hvor forslaget begynder). D/N kræver et navn uden titel.",
           "# P-linjer: D = opret den afdøde ægtefælle (ny afgørelse med dødsoplysning) · N/U = lad stå.",
           "# Ret kun undtagelser. En note må følge efter '#'. Gem, og giv hashen i chatten.", ""]
    n = len(rows["rows"])
    for i, r in enumerate(rows["rows"], 1):
        p = propose(r, cutoff, text_form=tf)
        text = r["clauses"][0]["verbatim_text"] if r["clauses"] else ""
        out += [f"## ÆGTESKAB {i}/{n} · post {r.get('record_key') or '?'}", f"#   Bogen: »{_ws(text)}«"]
        if "name_from" in p:
            out.append(f"#   Ægtefællens navn: »{_ws(text[p['name_from']:p['name_to']])}«")
        partners = "; ".join(f"{_ws(x.get('navn')) or '(intet navn)'} ({x.get('foedt') or '?'}–{x.get('doed') or '?'})"
                             f" · familie {x.get('family_id')} · nr. {x.get('ordinal') if x.get('ordinal') is not None else '?'}"
                             for x in r.get("principal_partners", []))
        out.append(f"#   Hovedpersonens partnere: {partners or '(ingen)'}")
        if p["tok"] == "S" and p.get("partner_ordinal") is not None and p["partner_ordinal"] != r["marriage_ordinal"]:
            out.append(f"#   OBS: nr. i bogen {r['marriage_ordinal']} ≠ nr. i familien {p['partner_ordinal']} — bekræft bevidst")
        if "clause_years" in p:
            out.append(f"#   Årstal i klausulen: {', '.join(map(str, p['clause_years'])) or '(ingen)'} · grænse {cutoff}")
        if p["tok"] == "D":
            out += [f"#   Hele posten: »{_ws(r.get('post_text'))}«",
                    "#   Gælder et senere årstal i posten ægtefællen? Så svar N."]
        out += [f"#   Forslag: {p['tok']} ({p['reason']})",
                f"M {r['interpretation_key']} {r['interpretation_version']} : {p['tok']}", ""]
    for j, q in enumerate(rows.get("redecide_rows", []), 1):
        p = propose_redecide(q, cutoff)
        prev = q.get("previous") or {}
        out += [f"## GENAFGØRELSE {j} · post {q.get('record_key') or '?'}, s. {q.get('page_from') or '?'}",
                f"#   Tidligere afgørelse: {prev.get('basis')} · note: »{_ws(prev.get('note'))}«",
                f"#   Ægtefællens navn: »{_ws(q.get('name_text'))}«",
                f"#   Klausulen: »{_ws(q.get('clause_text'))}«",
                f"#   Hele posten: »{_ws(q.get('post_text'))}«",
                f"#   Årstal i klausulen: {', '.join(map(str, p.get('clause_years', []))) or '(ingen)'} · grænse {cutoff}",
                "#   Gælder et senere årstal i posten ægtefællen? Så svar N.",
                f"#   Forslag: {p['tok']} ({p['reason']})",
                f"P {q['source_persona_id']} {q['identity_version']} : {p['tok']}", ""]
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    lines: list[Line] = []
    for raw in text.splitlines():
        if not raw.strip() or raw.startswith("#"):
            continue
        m = M_RE.match(raw) or P_RE.match(raw)
        if not m:
            raise SheetError("SHEET_LINE_INVALID" if LOOSE_RE.match(raw) else "SHEET_LINE_UNKNOWN")
        navn = m.groupdict().get("navn")
        lines.append(Line(raw[0], m["key"], int(m["ver"]), m["tok"], navn, (m["note"] or "").strip(), len(lines) + 1))
    return lines


def check_sheet(lines: list[Line], rows: dict, profile: dict | None = None) -> tuple[list[dict], list[dict]]:
    tf = _profile(profile)["text_form"]
    cutoff = _cutoff(rows)
    m_lines = [l for l in lines if l.kind == "M"]
    p_lines = [l for l in lines if l.kind == "P"]
    exp_m = [(r["interpretation_key"], int(r["interpretation_version"])) for r in rows["rows"]]
    exp_p = [(q["source_persona_id"], int(q["identity_version"])) for q in rows.get("redecide_rows", [])]
    if (not lines or [l.kind for l in lines] != ["M"] * len(m_lines) + ["P"] * len(p_lines)
            or [(l.key, l.version) for l in m_lines] != exp_m or [(l.key, l.version) for l in p_lines] != exp_p):
        raise SheetError("SHEET_IDENTITY_MISMATCH")
    m_props = []
    for l, r in zip(m_lines, rows["rows"]):
        if l.navn is not None and l.tok not in ("S", "D", "N"):
            raise SheetError(f"SHEET_NAME_INVALID line={l.line}")
        try:
            p = propose(r, cutoff, name_override=l.navn, text_form=tf)
        except NameOverrideError:
            raise SheetError(f"SHEET_NAME_INVALID line={l.line}") from None
        if l.tok not in ALLOWED[p["tok"]]:
            raise SheetError(f"SHEET_TOKEN_NOT_ALLOWED line={l.line}")
        m_props.append(p)
    p_props = []
    for l, q in zip(p_lines, rows.get("redecide_rows", [])):
        p = propose_redecide(q, cutoff)
        if l.tok not in ALLOWED_P[p["tok"]]:
            raise SheetError(f"SHEET_TOKEN_NOT_ALLOWED line={l.line}")
        p_props.append(p)
    return m_props, p_props


def persona_manifest(lines: list[Line], rows: dict, *, sheet_sha256: str, profile: dict | None = None) -> dict:
    require_hex64(sheet_sha256)
    prof = _profile(profile)
    m_props, _ = check_sheet(lines, rows, prof)
    elements = {}
    for l, r, p in zip([l for l in lines if l.kind == "M"], rows["rows"], m_props):
        if l.tok not in ("S", "D", "N"):
            continue
        c = r["clauses"][0]
        elements["relation-persona:" + r["interpretation_key"]] = {
            "birth_raw": None, "clause_observation_id": c["observation_id"], "clause_set_seq": c["clause_set_seq"],
            "clause_set_sha256": c["clause_set_sha256"], "death_raw": None,
            "interpretation_key": r["interpretation_key"], "interpretation_version": r["interpretation_version"],
            "marriage_ordinal": r["marriage_ordinal"], "name_basis": p["name_basis"], "name_from": p["name_from"],
            "name_to": p["name_to"], "post_offset": c["post_char_from"] + p["span_from"], "predicate": "relation.marriage",
            "profile": prof["relation_profile"], "sheet_line": l.line, "sheet_sha256": sheet_sha256,
            "span_from": p["span_from"], "span_to": p["span_to"]}
    return {"expected_counts": {"person_creates": 0, "source_evidence": 0, "relation_personas": len(elements)},
            "authorized_elements": dict(sorted(elements.items()))}


def identity_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str, profile: dict | None = None) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    m_props, p_props = check_sheet(lines, rows, _profile(profile))
    cutoff = _cutoff(rows)
    m_todo = [(l, p) for l, p in zip([l for l in lines if l.kind == "M"], m_props) if l.tok in ("S", "D", "N")]
    p_todo = [(l, p) for l, p in zip([l for l in lines if l.kind == "P"], p_props) if l.tok == "D"]
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;", "SET LOCAL TimeZone='UTC';",
           "SET LOCAL search_path=pg_catalog,public,private;"]
    for l, _ in m_todo:
        sql.append(f"SELECT source_persona_id AS p{l.line} FROM private.interpretation_party_current "
                   f"WHERE interpretation_key='{l.key}' AND party_role='spouse' AND source_persona_id IS NOT NULL \\gset")
    sql += ["SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
            "SET LOCAL ROLE authenticated;"]
    tag = sheet_sha256[:12]
    base = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256}
    for l, p in m_todo:
        note = sql_literal(f"ark v3 {tag} linje {l.line}" + (f" — {l.note}" if l.note else ""))
        ctx = {**base, "line": l.line}
        if l.tok == "S":
            action, person = "same", str(int(p["partner_person_id"]))
        else:
            action, person = "new_person_needed", "NULL"
            if l.tok == "D":
                ctx["deceased"] = {"rule": RULE, "cutoff_year": cutoff, "clause_years": p["clause_years"]}
        sql.append(f"SELECT red_afgoer_source_persona(:'p{l.line}'::uuid, 0, '{action}', {person}, {note}, "
                   f"{sql_literal(json.dumps(ctx, sort_keys=True))}::jsonb) \\g /dev/null")
    for l, p in p_todo:
        note = sql_literal(f"ark v3 {tag} linje {l.line} — erstatter version {l.version}" + (f" — {l.note}" if l.note else ""))
        ctx = {**base, "line": l.line, "deceased": {"rule": RULE, "cutoff_year": cutoff, "clause_years": p["clause_years"]}}
        sql.append(f"SELECT red_afgoer_source_persona('{l.key}'::uuid, {l.version}, 'new_person_needed', NULL, {note}, "
                   f"{sql_literal(json.dumps(ctx, sort_keys=True))}::jsonb) \\g /dev/null")
    sql.append("COMMIT;")
    return "\n".join(sql) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    s = sub.add_parser("sql")
    for p in (r, s):
        p.add_argument("--profile", help="profilfil (profiles/relation-persona-*.json); uden: standardprofilen")
        p.add_argument("--rows", required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    r.add_argument("--out", required=True)
    for a in ("--sheet", "--approved-sha256", "--expect-rows-sha256", "--manifest-out", "--identity-out"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        try:
            profile = _profile(load_profile(args.profile))
        except (ValueError, KeyError, OSError):
            raise SheetError("PROFILE_FILE_INVALID") from None
        rows_path = check_private_path(Path(args.rows), root)
        rows_bytes = rows_path.read_bytes()
        rows = json.loads(rows_bytes.decode("utf-8"))
        if rows.get("contract") != "relation-persona-v3-input":
            raise SheetError("ROWS_CONTRACT_INVALID")
        if args.cmd == "render":
            out = check_private_path(Path(args.out), root)
            _write_private(out, render_sheet(rows, profile))
            c = {t: 0 for t in "SDNIU"}
            cp = {t: 0 for t in "DNU"}
            for row in rows["rows"]:
                c[propose(row, _cutoff(rows), text_form=profile["text_form"])["tok"]] += 1
            for q in rows.get("redecide_rows", []):
                cp[propose_redecide(q, _cutoff(rows))["tok"]] += 1
            print(f"ARK_OK s={c['S']} d={c['D']} n={c['N']} i={c['I']} u={c['U']} p_d={cp['D']} p_n={cp['N']} p_u={cp['U']}")
            return 0
        mout = check_private_path(Path(args.manifest_out), root)
        iout = check_private_path(Path(args.identity_out), root)
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        lines = parse_sheet(sheet_bytes.decode("utf-8"))
        manifest = persona_manifest(lines, rows, sheet_sha256=sheet_sha, profile=profile)
        ident = identity_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha, profile=profile)
        _write_private(mout, json.dumps(manifest, sort_keys=True, ensure_ascii=False) + "\n")
        _write_private(iout, ident)
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK manifest={len(manifest['authorized_elements'])} identitet={ident.count('red_afgoer_source_persona(')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
