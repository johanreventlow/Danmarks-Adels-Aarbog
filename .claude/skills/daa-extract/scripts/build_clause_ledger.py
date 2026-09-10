#!/usr/bin/env python3
"""Byg klausul-ledger for alle records i en privat teksteksport (#148, 4.1b).

Læser ingen database. Skriver kun til en 0700-mappe uden 'work'-komponent.
Ledger-filen bærer ingen tekst; teksterne ligger i en separat 0600-fil.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clause_segment  # noqa: E402
import evidence_extract  # noqa: E402


def _fail(code: str) -> None:
    print(code, file=sys.stderr)
    raise SystemExit(2)


def _validate_output_dir(path: str) -> Path:
    p = Path(path)
    if not p.is_absolute():
        _fail("OUTPUT_DIR_NOT_ABSOLUTE")
    if any(part == "work" or part.startswith("work_") for part in p.parts):
        _fail("OUTPUT_WORK_PATH")
    if not p.is_dir() or p.is_symlink():
        _fail("OUTPUT_DIR_INVALID")
    if (p.stat().st_mode & 0o777) != 0o700:
        _fail("OUTPUT_DIR_MODE_INVALID")
    return p


def _write_private(path: Path, payload) -> None:
    if path.exists():
        _fail("OUTPUT_EXISTS")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1, sort_keys=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--texts", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    out = _validate_output_dir(args.output_dir)
    profile = evidence_extract.load_profile(args.profile)
    rules = profile.get("clause_rules")
    if not rules:
        _fail("PROFILE_CLAUSE_RULES_MISSING")
    try:
        rows = json.loads(Path(args.texts).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        _fail("TEXTS_UNREADABLE")
    records, texts, flag_counter, unknown_tokens, gap_chars = [], {}, Counter(), Counter(), Counter()
    counts = []
    structural = 0
    for row in rows:
        text = row["verbatim_text"]
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != row["verbatim_sha256"]:
            _fail("TEXT_HASH_MISMATCH:" + row["record_key"])
        result = clause_segment.build_record_ledger(row["record_key"], row["occurrence_key"], text, rules)
        for ch in result["gap_violations"]:
            gap_chars["U+%04X" % ord(ch)] += 1
        clauses = []
        for clause in result["clauses"]:
            flag_counter.update(clause["flags"])
            if "unknown_abbreviation" in clause["flags"]:
                for token in clause["verbatim_text"].split():
                    if token.endswith(".") and len(token) <= 5 and token not in rules["non_terminal_abbreviations"]:
                        unknown_tokens[token] += 1
            if clause["classification"] == "structural_header":
                structural += 1
            texts[f"{row['record_key']}#{clause['ordinal']}"] = clause["verbatim_text"]
            clauses.append({k: clause[k] for k in ("ordinal", "char_from", "char_to", "classification", "flags", "verbatim_sha256")})
        counts.append(len(clauses))
        records.append({"record_key": row["record_key"], "occurrence_key": row["occurrence_key"],
                        "page_from": row["page_from"], "page_to": row["page_to"],
                        "parent_char_from": row["char_from"], "parent_char_to": row["char_to"],
                        "parent_verbatim_sha256": row["verbatim_sha256"],
                        "rendition_content_sha256": row["rendition_content_sha256"],
                        "rules_version": rules["version"], "ledger_sha256": result["ledger_sha256"], "clauses": clauses})
    ledger = {"schema_version": "clause-ledger-v1", "profile_id": args.profile, "profile_version": profile["version"],
              "rules_version": rules["version"], "segmenter_version": "clause_segment.py@v1",
              "gap_charset": list(rules["gap_charset"]),   # 4.1c's manifest hash-binder tegnsættet herfra
              "records": records}
    _write_private(out / "clause-ledger-v1.json", ledger)
    _write_private(out / "clause-ledger-texts-v1.json", texts)
    summary = {"records": len(records), "clauses": {"total": sum(counts), "min": min(counts) if counts else 0,
               "median": statistics.median(counts) if counts else 0, "max": max(counts) if counts else 0},
               "flags": dict(flag_counter), "structural_header": structural,
               "gap_violations": dict(gap_chars), "unknown_abbreviation_tokens": dict(unknown_tokens.most_common(50)),
               "ledger_file_sha256": hashlib.sha256((out / "clause-ledger-v1.json").read_bytes()).hexdigest()}
    _write_private(out / "clause-ledger-summary.json", summary)
    print(json.dumps({k: summary[k] for k in ("records", "clauses", "flags", "structural_header", "gap_violations", "ledger_file_sha256")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
