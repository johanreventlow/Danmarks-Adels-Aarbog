#!/usr/bin/env python3
"""Fail-closed konverter: menneskeark -> beslutnings-JSON.

Alt andet end tokenet er byte-låst. En redigeret kontekst er terminal, ikke
noget der forsøges tolket: ellers kunne en utilsigtet ændring flytte et valg
til et andet sted i teksten uden at nogen opdagede det.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any, Dict

ACTION_BY_TOKEN = {"[MERGE]": "merge", "[KEEP]": "keep"}
PERSON_TOKENS = {"[ACCEPT]": True, "[AFVIS]": False}


def _fail(code: str) -> None:
    raise SystemExit(code)


def parse_review(text: str, flags_doc: Dict[str, Any]) -> Dict[str, Any]:
    forventet_flag = {}
    forventet_person = {}
    for op in flags_doc["operations"]:
        forventet_person[op["person_id"]] = "%d  %s" % (
            op["person_id"], op["source_record_key"])
        for flag in op["flags"]:
            forventet_flag[flag["flag_id"]] = "%s  |  %s" % (
                flag["flag_id"], flag["context"].replace("\n", "\\n"))

    decisions: Dict[str, str] = {}
    accepted = []
    set_person = set()
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#") or line.startswith("=="):
            continue
        token, _, hale = line.partition(" ")
        hale = hale.strip()
        if token in PERSON_TOKENS:
            pid = int(hale.split()[0])
            if pid not in forventet_person:
                _fail("C0F_REVIEW_PERSON_UNKNOWN:line=%d" % number)
            if hale != forventet_person[pid]:
                _fail("C0F_REVIEW_LINE_TAMPERED:line=%d" % number)
            if pid in set_person:
                _fail("C0F_REVIEW_PERSON_DUPLICATE:line=%d" % number)
            set_person.add(pid)
            if PERSON_TOKENS[token]:
                accepted.append(pid)
        elif token in ACTION_BY_TOKEN:
            flag_id = hale.split("  |  ")[0]
            if flag_id not in forventet_flag:
                _fail("C0F_REVIEW_FLAG_UNKNOWN:line=%d" % number)
            if hale != forventet_flag[flag_id]:
                _fail("C0F_REVIEW_LINE_TAMPERED:line=%d" % number)
            if flag_id in decisions:
                _fail("C0F_REVIEW_FLAG_DUPLICATE:line=%d" % number)
            decisions[flag_id] = ACTION_BY_TOKEN[token]
        else:
            _fail("C0F_REVIEW_TOKEN_INVALID:line=%d:token=%s" % (number, token))

    if set(forventet_person) - set_person:
        _fail("C0F_REVIEW_PERSON_MISSING:" + ",".join(
            str(p) for p in sorted(set(forventet_person) - set_person)))
    if set(forventet_flag) - set(decisions):
        _fail("C0F_REVIEW_FLAG_MISSING:" + ",".join(
            sorted(set(forventet_flag) - set(decisions))))
    if not accepted:
        _fail("C0F_REVIEW_EMPTY")
    return {"decisions": decisions, "accepted_person_ids": sorted(accepted)}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", required=True)
    parser.add_argument("--flags", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    out = pathlib.Path(args.output)
    if out.exists():
        _fail("C0F_DECISIONS_OUTPUT_EXISTS")
    flags_doc = json.loads(pathlib.Path(args.flags).read_text(encoding="utf-8"))
    result = parse_review(
        pathlib.Path(args.review).read_text(encoding="utf-8"), flags_doc)
    result["schema_version"] = "1939-v50-c0-followup-decisions-v1"
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    print("accepteret=%d afgjorte_orddelinger=%d" % (
        len(result["accepted_person_ids"]), len(result["decisions"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
