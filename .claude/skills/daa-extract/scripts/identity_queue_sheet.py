"""Trin 5a+5b-overførslen (plan B1 Task 4): køens ark fra trin 5b 2b-i i repoet (port af den private koe-apply.py).

Køen er kildens ægtefællepersonas uden afgørelse (proposed eller ingen identitet). `render` skriver én Q-linje pr. persona i
detaljedumpet (red_source_persona_detail pr. persona) sorteret efter persona-id, med bogens tekst, hovedpersonens partnere og
kandidaterne som kommentarlinjer. `sql` oversætter det godkendte ark til red_afgoer_source_persona-kald i én transaktion med
kildelås, mængdevagt (KOE_ROWS_STALE over persona-id'erne) og tællevagt (KOE_COUNT_MISMATCH). Noten har samme format som i
beviskæden (`kø 2b-i <sh[:12]> sag <n> — <grund>`), så en ny arkhash giver ny note og dermed nyt v3-ark (forventet kaskade).
Arket og detaljerne rummer navne og kildetekst; værktøjet printer kun antal og hashes."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I tilføjer ikke scriptets mappe
from decision_sheet_core import SheetError, require_hex64, sql_literal  # noqa: E402

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
Q_RE = re.compile(rf"^Q (?P<pid>{UUID}) (?P<ver>[0-9]+) : (?P<tok>same (?P<person>-?[0-9]+)|N|X|U)\s*#\s*(?P<why>\S.*)$")
ACT = {"same": "same", "N": "new_person_needed", "X": "different", "U": "unresolved"}


def _ws(s) -> str:
    return " ".join(str(s or "").split())


def _years(born, died) -> str:
    return f"{born or '?'}–{died or '?'}"


def _sorted(details: list[dict]) -> list[dict]:
    return sorted(details, key=lambda x: x["persona"]["source_persona_id"])


def render_sheet(details: list[dict]) -> str:
    dets = _sorted(details)
    n = len(dets)
    out = [f"# KØEN (trin 5b 2b-i) — {n} ægtefællesager. Gem filen og giv SHA-256.",
           "# Token efter ':': same <person-id> (samme som den person) | N (ny person) | X (forkert udtræk) | U (uafklaret)",
           "# Alt efter '#' på Q-linjen er begrundelsen og gemmes i noten.", ""]
    for i, x in enumerate(dets, 1):
        p = x["persona"]; fc = x.get("family_context") or {}
        book = " / ".join(_ws(m.get("verbatim_text")) for m in x.get("mentions") or [] if m.get("mention_role") == "spouse")
        out.append(f"## SAG {i}/{n} · grund: {x.get('review_reason') or '?'} · bogens ægteskab nr. {fc.get('marriage_ordinal', '?')}")
        out.append(f"#   Bogen: »{book}«")
        for pp in x.get("principal_partners") or []:
            out.append(f"#   Hovedpersonens partner: {_ws(pp.get('name'))} ({_years(pp.get('born'), pp.get('died'))}) · person "
                       f"{pp.get('person_id')} · familie {pp.get('family_id')} nr. {pp.get('ordinal')}")
        if not x.get("principal_partners"):
            out.append("#   Hovedpersonen har ingen partner i databasen")
        for c in (x.get("candidates") or [])[:3]:
            out.append(f"#   Kandidat {c.get('rank')}: {_ws(c.get('person_name'))} ({_years(c.get('born'), c.get('died'))}) · person "
                       f"{c.get('person_id')} · {c.get('tier')} {c.get('score')}")
        out.append(f"Q {p['source_persona_id']} {int(p['version'])} : _ # ")
        out.append("")
    return "\n".join(out)


def sheet_sql(sheet_text: str, details: list[dict], *, sheet_sha256: str, approved_sha256: str, rows_sha256: str,
              source_id: int) -> tuple[str, dict[str, int]]:
    require_hex64(sheet_sha256, approved_sha256, rows_sha256)
    if sheet_sha256 != approved_sha256:
        raise SheetError("KOE_SHEET_HASH_MISMATCH")
    ids = sorted(x["persona"]["source_persona_id"] for x in details)
    lines = [l for l in sheet_text.splitlines() if l.startswith("Q ")]
    if len(lines) != len(ids):
        raise SheetError("KOE_LINE_COUNT")
    src = int(source_id)
    # Mængdevagten sammenligner som Python sorterer (bytevis): COLLATE "C" (beviskædens version sorterede efter basens collation).
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL TimeZone='UTC';", "SET LOCAL search_path=pg_catalog,public,private;",
           "SET LOCAL standard_conforming_strings=on;",
           f"SELECT pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:{src}',0)) \\g /dev/null",
           "DO $chk$ BEGIN IF (SELECT array_agg(sp.id::text ORDER BY sp.id::text COLLATE \"C\") FROM private.source_persona sp "
           f"LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id WHERE sp.source_id={src} "
           "AND coalesce(i.decision_status,'proposed')='proposed' AND EXISTS (SELECT 1 FROM private.source_persona_mention m "
           "WHERE m.persona_id=sp.id AND m.mention_role='spouse')) IS DISTINCT FROM "
           f"ARRAY[{','.join(sql_literal(i) for i in ids)}]::text[] THEN RAISE EXCEPTION 'KOE_ROWS_STALE'; END IF; END $chk$;",
           # Temp-tabellen oprettes efter rolleskiftet, så authenticated kan skrive i den.
           "SET LOCAL ROLE authenticated;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
           "CREATE TEMP TABLE applied(kind text) ON COMMIT DROP;"]
    counts = {k: 0 for k in ACT}
    seen: set[str] = set()
    for n, line in enumerate(lines, 1):
        m = Q_RE.match(line)
        if not m:
            raise SheetError(f"KOE_LINE_INVALID {n}")
        pid = m["pid"]
        if pid not in ids or pid in seen:
            raise SheetError(f"KOE_PERSONA_UNKNOWN {n}")
        seen.add(pid)
        kind = m["tok"].split()[0]
        counts[kind] += 1
        ctx = json.dumps({"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": n},
                         sort_keys=True)
        note = sql_literal(f"kø 2b-i {sheet_sha256[:12]} sag {n} — {m['why'].strip()}")
        person = str(int(m["person"])) if m["person"] else "NULL"
        sql.append(f"INSERT INTO applied SELECT {sql_literal(kind)} FROM (SELECT red_afgoer_source_persona({sql_literal(pid)}::uuid, "
                   f"{int(m['ver'])}, {sql_literal(ACT[kind])}, {person}, {note}, {sql_literal(ctx)}::jsonb)) x;")
    sql.append("RESET ROLE;")
    cond = " OR ".join(f"(SELECT count(*) FROM applied WHERE kind={sql_literal(k)})<>{v}" for k, v in counts.items())
    sql.append(f"DO $cnt$ BEGIN IF {cond} THEN RAISE EXCEPTION 'KOE_COUNT_MISMATCH'; END IF; END $cnt$;")
    sql.append("COMMIT;")
    return "\n".join(sql) + "\n", counts


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


def _write_new(path: Path, text: str) -> None:
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise SheetError("KOE_OUT_EXISTS") from None
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    s = sub.add_parser("sql")
    for p in (r, s):
        p.add_argument("--details", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    for a in ("--sheet", "--approved-sha256", "--source"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        det_path = check_private_path(Path(args.details), root)
        out = check_private_path(Path(args.out), root)
        det_bytes = det_path.read_bytes()
        details = json.loads(det_bytes.decode("utf-8"))
        if args.cmd == "render":
            text = render_sheet(details)
            _write_new(out, text)
            print(f"KOE_RENDER_OK n={len(details)} sheet_sha256={hashlib.sha256(text.encode('utf-8')).hexdigest()}")
            return 0
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha = hashlib.sha256(det_bytes).hexdigest()
        sql, counts = sheet_sql(sheet_bytes.decode("utf-8"), details, sheet_sha256=hashlib.sha256(sheet_bytes).hexdigest(),
                                approved_sha256=args.approved_sha256, rows_sha256=rows_sha, source_id=int(args.source))
        _write_new(out, sql)
    except SheetError as exc:
        raise SystemExit(str(exc).split(" — ")[0])
    print(f"KOE_SQL_OK n={sum(counts.values())} " + " ".join(f"{k}={v}" for k, v in counts.items()) + f" rows_sha256={rows_sha}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
