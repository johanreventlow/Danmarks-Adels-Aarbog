#!/usr/bin/env python3
"""Manifest-bygger for C0's efterkørsel.

Beslutnings-anvendelsen er KOMPOSITION over ``normalize_narrative_v1``, aldrig
en anden kopi af dens regler: transformen er et strengt venstre-mod-højre-pas
uden lookahead ud over det flagede sted, så en afkortning af rå-teksten præcis
ved et flags ``char_offset`` og en genkørsel giver et EKSAKT præfiks af
standard-outputtet — og dermed splice-positionen via modulets eget API.
Mønsteret er verificeret mod alle 178 ægte flag i fase B.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib
import sys
from typing import Any, Dict, List, Tuple

_SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent

DEFAULT_ACTION = {"hyphen_unproven": "merge"}
VALID_ACTIONS = {"hyphen_unproven": {"merge", "keep"}}


def _fail(code: str) -> None:
    raise SystemExit(code)


def _import(name: str):
    spec = importlib.util.spec_from_file_location(name, _SCRIPTS_DIR / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


_flags_mod = _import("build_c0_followup_flags_1939_v50")
normalize_narrative_v1 = _flags_mod.normalize_narrative_v1


def _assert_invariants(text: str, context: str) -> None:
    if "### PAGE" in text:
        _fail("C0F_MANIFEST_INVARIANT_PAGE_MARKER:" + context)
    if _flags_mod._LONE_NEWLINE_RE.search(text):
        _fail("C0F_MANIFEST_INVARIANT_LONE_NEWLINE:" + context)
    if text != text.rstrip():
        _fail("C0F_MANIFEST_INVARIANT_TRAILING_WS:" + context)
    if not text.strip():
        _fail("C0F_MANIFEST_INVARIANT_EMPTY:" + context)


def _decided_text(raw: str, corpus: str, default_text: str,
                  op_flags: List[Dict[str, Any]], decisions: Dict[str, str]) -> str:
    edits: List[Tuple[int, int, str]] = []
    for flag in op_flags:
        kind = flag["kind"]
        flag_id = flag["flag_id"]
        if kind not in VALID_ACTIONS:
            _fail("C0F_MANIFEST_FLAG_KIND_UNKNOWN:" + flag_id)
        action = decisions.get(flag_id)
        if action is None:
            _fail("C0F_MANIFEST_DECISION_MISSING:" + flag_id)
        if action not in VALID_ACTIONS[kind]:
            _fail("C0F_MANIFEST_ACTION_INVALID:" + flag_id)
        if action == DEFAULT_ACTION[kind]:
            continue
        prefix_text = normalize_narrative_v1(raw[:flag["char_offset"]], corpus)["text"]
        prefix_len = len(prefix_text)
        # Ikke-tom kontrol selv naar default-spannet er 0 tegn: den bekraefter
        # at HELE praefikset flugter med standard-outputtet foer der splices,
        # saa en skredet prefix_len aldrig kan indsaette en "-" det forkerte sted.
        if default_text[:prefix_len] != prefix_text:
            _fail("C0F_MANIFEST_DECISION_PREFIX_MISMATCH:" + flag_id)
        # hyphen_unproven: standarden har allerede sammentrukket, 0 tegn beholdt.
        edits.append((prefix_len, prefix_len, "-"))
    edits.sort(key=lambda e: -e[0])
    text = default_text
    seen: List[Tuple[int, int]] = []
    for lo, hi, span in edits:
        if any(not (hi <= a or lo >= b) for a, b in seen):
            _fail("C0F_MANIFEST_DECISION_SPLICE_OVERLAP")
        seen.append((lo, hi))
        text = text[:lo] + span + text[hi:]
    return text


def build_manifest(flags_doc: Dict[str, Any], decisions_doc: Dict[str, Any],
                   candidates: Dict[str, Any]) -> Dict[str, Any]:
    accepted = set(int(p) for p in decisions_doc.get("accepted_person_ids", []))
    if not accepted:
        _fail("C0F_MANIFEST_EMPTY")
    decisions = decisions_doc.get("decisions") or {}
    recs = {r["new_record_key"]: r for r in candidates.get("records", [])}
    corpus = "\n".join(r["verbatim_text"] for r in candidates.get("records", []))

    operations = []
    for op in flags_doc["operations"]:
        pid = int(op["person_id"])
        if pid not in accepted:
            continue
        key = op["source_record_key"]
        if key not in recs:
            _fail("C0F_MANIFEST_RECORD_MISSING:%d" % pid)
        new_text = _decided_text(recs[key]["verbatim_text"], corpus,
                                 op["default_text"], op["flags"], decisions)
        # Invarianterne haevdes paa den FAERDIGE tekst: et splice kan i
        # princippet genindfoere et brud, som default_text ikke havde.
        _assert_invariants(new_text, "person=%d" % pid)
        operations.append({
            "person_id": pid,
            "narrative_id": int(op["narrative_id"]),
            "expected_old_narrative_sha256": op["old_sha256"],
            "source_record_key": key,
            "page_from": int(op["page_from"]),
            "new_text": new_text,
            "new_text_sha256": hashlib.sha256(new_text.encode("utf-8")).hexdigest(),
        })
    operations.sort(key=lambda o: o["person_id"])
    if not operations:
        _fail("C0F_MANIFEST_EMPTY")
    return {
        "schema_version": "1939-v50-c0-followup-manifest-v1",
        "generator": "build_c0_followup_manifest_1939_v50.py",
        # Baeres videre fra flag-dokumentet; apply sammenligner mod den LEVENDE
        # base, saa et manifest fra rehearsal ikke kan koeres mod prod.
        "database_name": flags_doc.get("database_name"),
        "database_identity": flags_doc.get("database_identity"),
        "source": {"edition": "1939", "database_source_id": 3},
        "counts": {"operations": len(operations), "bindings_create": len(operations)},
        "operations": operations,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flags", required=True)
    parser.add_argument("--decisions", required=True)
    parser.add_argument("--candidates", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    out = pathlib.Path(args.output)
    if out.exists():
        _fail("C0F_MANIFEST_OUTPUT_EXISTS")
    read = lambda p: json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
    man = build_manifest(read(args.flags), read(args.decisions), read(args.candidates))
    out.write_text(json.dumps(man, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    print("operationer=%d bindinger=%d" % (
        man["counts"]["operations"], man["counts"]["bindings_create"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
