"""Trin 5a+5b-overførslen (plan B2 Task 2, spec §6.3): sammenlign arbejdskørslens indhold med beviskædens.

Indgangene er to udskrifter af `transfer_5ab_content.sql` (linjer `<lag>|<nøgle>|<værdi-json>`) og listen over forventede
forskelle (`5ab-expected-v1`). En forskel pr. (lag, nøgle) er tilladt, når en post dækker den:
  absent_new  nøglen findes i den gamle, ikke i den nye;
  absent_old  nøglen findes i den nye, ikke i den gamle;
  may_differ  nøglen findes i begge, og værdierne er ens, når postens felter fjernes.
Lag af formen `sheet:<kind>` hører til svaroverførslen og ignoreres her. En nøgle kan forekomme flere gange (kildevisningen);
værdierne sammenlignes da som en mængde med gentagelser. Rapporten (0600) bærer nøgler og værdier; stdout kun antal og en hash.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I tilføjer ikke scriptets mappe
from decision_sheet_core import SheetError  # noqa: E402

VERSION = "5ab-expected-v1"
KINDS = ("absent_new", "absent_old", "may_differ")
Rows = dict[tuple[str, str], list[str]]


def parse_lines(text: str) -> Rows:
    out: dict[tuple[str, str], list[str]] = defaultdict(list)
    for n, line in enumerate((x for x in text.splitlines() if x.strip()), 1):
        parts = line.split("|", 2)
        if len(parts) != 3 or not parts[0] or not parts[1]:
            raise SheetError(f"CONTENT_LINE_INVALID {n}")
        try:
            v = json.loads(parts[2])
        except json.JSONDecodeError:
            raise SheetError(f"CONTENT_LINE_INVALID {n}") from None
        out[(parts[0], parts[1])].append(json.dumps(v, sort_keys=True, ensure_ascii=False))
    return {k: sorted(v) for k, v in out.items()}


@dataclass(frozen=True)
class Entry:
    layer: str
    key: str
    kind: str
    fields: tuple[str, ...]


def load_expected(doc) -> dict[tuple[str, str], Entry]:
    if not isinstance(doc, dict) or doc.get("version") != VERSION or not isinstance(doc.get("entries"), list):
        raise SheetError("EXPECTED_INVALID version")
    out: dict[tuple[str, str], Entry] = {}
    for n, e in enumerate(doc["entries"], 1):
        ok = isinstance(e, dict) and isinstance(e.get("layer"), str) and isinstance(e.get("key"), str) \
            and e.get("kind") in KINDS and isinstance(e.get("reason"), str) and e["reason"].strip()
        flds = e.get("fields", []) if isinstance(e, dict) else None
        ok = ok and isinstance(flds, list) and all(isinstance(f, str) for f in flds) and (e["kind"] != "may_differ" or flds)
        if not ok or (e["layer"], e["key"]) in out:
            raise SheetError(f"EXPECTED_INVALID {n}")
        if e["layer"].startswith("sheet:"):
            continue
        out[(e["layer"], e["key"])] = Entry(e["layer"], e["key"], e["kind"], tuple(flds))
    return out


def _without(values: list[str], fields: tuple[str, ...]) -> list[str]:
    out = []
    for v in values:
        d = json.loads(v)
        out.append(json.dumps({k: x for k, x in d.items() if k not in fields} if isinstance(d, dict) else d, sort_keys=True))
    return sorted(out)


@dataclass
class Result:
    same: int = 0
    allowed: int = 0
    unexpected: list[tuple[str, str, list[str], list[str]]] = field(default_factory=list)
    unused: int = 0


def compare(old: Rows, new: Rows, expected: dict[tuple[str, str], Entry]) -> Result:
    r = Result(); used: set[tuple[str, str]] = set()
    for k in sorted(set(old) | set(new)):
        o, n = old.get(k, []), new.get(k, [])
        if o == n:
            r.same += 1
            continue
        e = expected.get(k)
        ok = e is not None and (
            (e.kind == "absent_new" and o and not n) or (e.kind == "absent_old" and n and not o)
            or (e.kind == "may_differ" and o and n and _without(o, e.fields) == _without(n, e.fields)))
        if ok:
            r.allowed += 1; used.add(k)
        else:
            r.unexpected.append((k[0], k[1], o, n))
    r.unused = len(set(expected) - used)
    return r


def report_text(r: Result) -> str:
    out = [f"same={r.same} allowed={r.allowed} unexpected={len(r.unexpected)} unused_expected={r.unused}"]
    for lag, key, o, n in r.unexpected:
        out += ["", f"## {lag} {key}"] + [f"- {x}" for x in o] + [f"+ {x}" for x in n]
    return "\n".join(out) + "\n"


def _write_new(path: Path, text: str) -> None:
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise SheetError("CONTENT_REPORT_EXISTS") from None
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def main() -> int:
    ap = argparse.ArgumentParser()
    for a in ("--old", "--new", "--expected", "--report"):
        ap.add_argument(a, required=True)
    ap.add_argument("--require-layers", default="", help="kommasepareret; runneren giver alle projektionens lag")
    args = ap.parse_args()
    try:
        old, new = parse_lines(Path(args.old).read_text(encoding="utf-8")), parse_lines(Path(args.new).read_text(encoding="utf-8"))
        # Tomme eller lagløse udskrifter (forkert kilde, fejlet omdirigering) må aldrig give CONTENT_OK.
        for name, rows in (("old", old), ("new", new)):
            if not rows:
                raise SheetError(f"CONTENT_EMPTY {name}")
            missing = [l for l in args.require_layers.split(",") if l and l not in {k[0] for k in rows}]
            if missing:
                raise SheetError(f"CONTENT_LAYER_MISSING {name} {','.join(missing)}")
        r = compare(old, new, load_expected(json.loads(Path(args.expected).read_text(encoding="utf-8"))))
        text = report_text(r)
        _write_new(Path(args.report), text)
    except SheetError as exc:
        raise SystemExit(str(exc).split(" — ")[0])
    if r.unexpected:
        print(f"CONTENT_UNEXPECTED n={len(r.unexpected)} report_sha256={hashlib.sha256(text.encode('utf-8')).hexdigest()}")
        return 3
    print(f"CONTENT_OK same={r.same} allowed={r.allowed} unused_expected={r.unused}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
