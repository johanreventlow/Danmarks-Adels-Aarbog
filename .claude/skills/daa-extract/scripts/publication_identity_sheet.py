"""Trin 6b, ceremoni C: kortark til den menneskelige identitetskontrol og manifest for publication_identity.

`render` bygger kort af red_publication_control (--control) og red_publication_control_details (--details): ét kort pr.
ikke-staged persona med udfald != enig og pr. stikprøvepersona. Stikprøvens kort blandes ind blandt de øvrige uden at vise
udfaldet (ingen kort viser udfaldet). Højst 30 kort pr. fil, højst 90 i alt.
`manifest` binder de udfyldte, godkendte ark til writer-payloads (private.write_publication_identity) og skriver et manifest
med samme form som publication_persona_manifest.sql: {"elements","expected_counts","dispositions"}.
Arkene og detaljerne rummer navne; filerne ligger kun under --private-root. Værktøjet printer kun antal og hashes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I tilføjer ikke scriptets mappe
from decision_sheet_core import SheetError, require_hex64  # noqa: E402
from identity_queue_sheet import _write_new, check_private_path  # noqa: E402

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
UUID_RE = re.compile(f"^{UUID}$")
P_RE = re.compile(rf"^P (?P<pid>{UUID}) (?P<ver>[0-9]+) : (?P<tok>S(?: (?P<hint>-?[0-9]{{1,18}}))?|F|U)\s*#.*$")
MAX_CARDS = 90
PER_FILE = 30
OUTCOMES = ("enig", "svag", "uenig", "navnefaelle", "ingen_kandidat")


def _ws(s) -> str:
    return " ".join(str(s or "").split())


def _years(born, died) -> str:
    return f"{born or '?'}–{died or '?'}"


def _sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def _is_new(c: dict) -> bool:
    return int(c.get("identity_version") or 0) == 0 and c.get("not_staged") is True


def _card_personas(control: dict) -> list[dict]:
    """Personas der får kort: ikke-staged med udfald != enig, samt stikprøven."""
    out = []
    for c in control["personas"]:
        if c.get("not_staged") is not True:
            continue
        if c.get("outcome") is None:
            raise SheetError("PUBLICATION_CONTROL_OUTCOME_MISSING")
        if c["outcome"] not in OUTCOMES:
            raise SheetError("PUBLICATION_CONTROL_OUTCOME_INVALID")
        if c["outcome"] != "enig" or c.get("in_sample"):
            out.append(c)
    return out


def _mix_key(pid: str) -> str:
    return hashlib.sha256(f"publication-sheet-v1:{pid}".encode()).hexdigest()


def _score(x) -> str:
    return "?" if x is None else str(x)


def _card(i: int, n: int, c: dict, d: dict) -> list[str]:
    persons = d.get("persons") or []
    prop = d.get("proposed") or {}
    lines = [f"## KORT {i}/{n} · bogens person: {_ws(prop.get('name'))} ({_years(prop.get('birth'), prop.get('death'))}) "
             f"· post {_ws(d.get('record_label'))}"]
    own = [p for p in persons if p.get("role") == "binding"]
    for p in own:
        lines.append(f"#   BINDING: {_ws(p.get('navn'))} ({_years(p.get('foedt'), p.get('doed'))}) · person {p.get('person_id')} · "
                     f"titel {_ws(', '.join(map(str, p.get('titel') or [])))} · post {_ws(', '.join(p.get('record_labels') or []))}")
        lines.append(f"#     bindingens egen score: {_score(p.get('score_raw'))} · signaler: {_ws(', '.join(map(str, p.get('signals') or [])))}")
    if not own:
        lines.append("#   BINDING: ikke blandt kandidaterne")
    comps = [p for p in persons if p.get("role") == "competitor"][:3]
    for k, p in enumerate(comps, 1):
        lines.append(f"#   Konkurrent {k}: {_ws(p.get('navn'))} ({_years(p.get('foedt'), p.get('doed'))}) · person {p.get('person_id')} · "
                     f"titel {_ws(', '.join(map(str, p.get('titel') or [])))} · post {_ws(', '.join(p.get('record_labels') or []))}")
        lines.append(f"#     klyngens score: {_score(p.get('cluster_score'))} · medlemmets egen score: {_score(p.get('score_raw'))}")
    if not comps:
        lines.append("#   Ingen konkurrerende klynger")
    lines.append(f"P {c['source_persona_id']} {int(c['identity_version'])} : _ # ")
    lines.append("")
    return lines


def render(control: dict, details: dict, base: str) -> list[tuple[str, str]]:
    cards = sorted(_card_personas(control), key=lambda c: _mix_key(c["source_persona_id"]))
    if len(cards) > MAX_CARDS:
        raise SheetError("PUBLICATION_SHEET_TOO_MANY_CARDS")
    dmap = {d["source_persona_id"]: d for d in details["personas"]}
    chunks = [cards[i:i + PER_FILE] for i in range(0, len(cards), PER_FILE)]
    files = []
    k = 0
    for f, chunk in enumerate(chunks, 1):
        out = [f"# IDENTITETSKONTROL (trin 6b C) — ark {f}/{len(chunks)}, {len(chunk)} kort. Gem filen og giv SHA-256.",
               "# Token efter ':': S (bindingen er rigtig) | S <person-id> (rigtig, og den person er samme som bindingen) | F (forkert) | U (ved ikke)",
               "# Ingen kort viser udfaldet. Alt efter '#' på P-linjen er en fri note.", ""]
        for c in chunk:
            k += 1
            d = dmap.get(c["source_persona_id"])
            if d is None:
                raise SheetError("PUBLICATION_CONTROL_DETAILS_MISSING")
            out += _card(k, len(cards), c, d)
        files.append((f"{base}-{f}.txt", "\n".join(out)))
    return files


def parse_sheet(text: str) -> list[tuple[int, dict]]:
    res = []
    for n, line in enumerate(text.splitlines(), 1):
        if not line.startswith("P "):
            continue
        m = P_RE.match(line)
        if not m:
            raise SheetError(f"PUBLICATION_SHEET_LINE_INVALID {n}")
        res.append((n, {"pid": m["pid"], "ver": int(m["ver"]), "tok": m["tok"][0],
                        "hint": int(m["hint"]) if m["hint"] else None}))
    return res


def build_manifest(control_bytes: bytes, sheets: list[tuple[str, bytes]], approved: list[str], persona_batch: str,
                   candidates_sha256: str) -> tuple[dict, dict]:
    control = json.loads(control_bytes.decode("utf-8"))
    require_hex64(candidates_sha256, *approved)
    if not UUID_RE.match(persona_batch):
        raise SheetError("PUBLICATION_MANIFEST_BATCH_INVALID")
    if len(approved) != len(sheets):
        raise SheetError("PUBLICATION_SHEET_HASH_MISMATCH")
    rows_sha = _sha(control_bytes)
    by_pid = {c["source_persona_id"]: c for c in control["personas"]}
    answers: dict[str, tuple[str, int, dict]] = {}
    for (name, b), ok in zip(sheets, approved):
        sha = _sha(b)
        if sha != ok:
            raise SheetError("PUBLICATION_SHEET_HASH_MISMATCH")
        for n, row in parse_sheet(b.decode("utf-8")):
            if row["pid"] in answers or row["pid"] not in by_pid:
                raise SheetError("PUBLICATION_SHEET_PERSONA_UNKNOWN")
            if row["ver"] != int(by_pid[row["pid"]]["identity_version"]):
                raise SheetError("PUBLICATION_SHEET_VERSION_MISMATCH")
            answers[row["pid"]] = (sha, n, row)
    expected = {c["source_persona_id"] for c in _card_personas(control)}
    if set(answers) != expected:
        raise SheetError("PUBLICATION_SHEET_CARDS_MISMATCH")
    for pid, (_, _, row) in answers.items():
        c = by_pid[pid]
        if c.get("in_sample") and row["tok"] in ("F", "U"):
            raise SheetError("PUBLICATION_SAMPLE_FAILED")
    elements: dict[str, dict] = {}
    dispositions = []
    for pid in sorted(by_pid):
        c = by_pid[pid]
        if c.get("not_staged") is not True:
            dispositions.append({"source_persona_id": pid, "label": "staged_ikke_offentlig"})
            continue
        if not _is_new(c):
            dispositions.append({"source_persona_id": pid, "label": "eksisterende_uaendret"})
            continue
        if c.get("binding_status") != "published" or c.get("person_id") is None:
            raise SheetError("PUBLICATION_CONTROL_BINDING_NOT_PUBLISHED")
        ans = answers.get(pid)
        payload = {
            "answer": ans[2]["tok"] if ans else None,
            "binding_id": c["binding_id"], "binding_status": c["binding_status"],
            "candidate_run_id": control["candidate_run_id"], "candidates_sha256": candidates_sha256,
            "expected_identity_version": 0, "outcome": c["outcome"], "person_id": c["person_id"],
            "persona_batch_id": persona_batch,
            "rows_sha256": rows_sha if ans else None,
            "same_as_hint_person_id": ans[2]["hint"] if ans else None,
            "sheet_line": ans[1] if ans else None,
            "sheet_sha256": ans[0] if ans else None,
            "source_persona_id": pid,
        }
        elements[f"publication-identity:{pid}"] = payload
    manifest = {"elements": dict(sorted(elements.items())),
                "expected_counts": {"person_creates": 0, "source_evidence": 0, "publication_identities": len(elements)},
                "dispositions": dispositions}
    return manifest, {"elements": len(elements), "dispositions": len(dispositions), "rows_sha256": rows_sha}


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    m = sub.add_parser("manifest")
    for p in (r, m):
        p.add_argument("--control", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    r.add_argument("--details", required=True)
    m.add_argument("--sheets", nargs="+", required=True)
    m.add_argument("--approved-sha256", required=True, help="kommasepareret, i samme rækkefølge som --sheets")
    m.add_argument("--persona-batch", required=True)
    m.add_argument("--candidates-sha256", required=True, help="candidates_sha256 for kandidatkørslen (står ikke i control-JSON)")
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        ctl_path = check_private_path(Path(args.control), root)
        ctl_bytes = ctl_path.read_bytes()
        if args.cmd == "render":
            det = json.loads(check_private_path(Path(args.details), root).read_bytes().decode("utf-8"))
            base = str(Path(args.out))
            outs = [check_private_path(Path(f"{base}-{i}.txt"), root) for i in (1, 2, 3)]
            files = render(json.loads(ctl_bytes.decode("utf-8")), det, base)
            for p in outs[:len(files)]:
                if p.exists():
                    raise SheetError("PUBLICATION_OUT_EXISTS")
            for (name, text) in files:
                _write_new(Path(name), text)
                print(f"PUBLICATION_SHEET_OK {Path(name).name} sha256={_sha(text.encode('utf-8'))}")
            print(f"PUBLICATION_RENDER_OK files={len(files)}")
            return 0
        out = check_private_path(Path(args.out), root)
        sheets = [(s, check_private_path(Path(s), root).read_bytes()) for s in args.sheets]
        manifest, info = build_manifest(ctl_bytes, sheets, args.approved_sha256.split(","), args.persona_batch,
                                        args.candidates_sha256)
        text = json.dumps(manifest, sort_keys=True, ensure_ascii=False)
        _write_new(out, text + "\n")
    except SheetError as exc:
        raise SystemExit(str(exc).split(" — ")[0])
    print(f"PUBLICATION_MANIFEST_OK elements={info['elements']} dispositions={info['dispositions']} "
          f"rows_sha256={info['rows_sha256']} manifest_sha256={_sha((text + chr(10)).encode('utf-8'))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
