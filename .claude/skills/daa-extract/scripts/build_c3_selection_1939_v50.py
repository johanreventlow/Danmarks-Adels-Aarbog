#!/usr/bin/env python3
"""Derivér det låste C3-review-udsnit fra C0-kandidater og -beslutninger.

Skriptet er udelukkende en lokal, deterministisk afgrænsning af C3's
menneskelige review. Det tilgår aldrig databasen og skriver først output,
når begge C0-inputs og den fulde selektionskontrakt er valideret.
"""

import copy
import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional


C3_SCHEMA = "1939-v50-c3-selection-v1"
EXPECTED_C3_COUNT = 7
SPECIAL_RID = "R15"
COMPANION_RID = "R40"
SPECIAL_PERSON_IDS = (1017, 1021)
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _load_c0_decisions() -> Any:
    path = Path(__file__).with_name("convert_c0_linkage_decisions_1939_v50.py")
    spec = importlib.util.spec_from_file_location("c0_linkage_decisions_v50", path)
    if spec is None or spec.loader is None:
        raise ImportError("could not load C0 RID implementation")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


c0_decisions = _load_c0_decisions()


def fail(code: str) -> None:
    raise SystemExit(code)


def require_sha(value: str) -> None:
    if not isinstance(value, str) or _SHA256_RE.fullmatch(value) is None:
        fail("C3_SELECTION_HASH_INVALID")


def unique_by_key(rows: List[Dict[str, Any]], key_name: str) -> Dict[str, Dict[str, Any]]:
    result: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            fail("C3_SELECTION_KEY_DUPLICATE")
        key = row.get(key_name)
        if not isinstance(key, str) or key in result:
            fail("C3_SELECTION_KEY_DUPLICATE")
        result[key] = row
    return result


def candidate_ids(record: Dict[str, Any]) -> List[int]:
    candidates = record.get("candidates")
    if not isinstance(candidates, list):
        fail("C3_SELECTION_CANDIDATES_INVALID")
    ids: List[int] = []
    for candidate in candidates:
        if (not isinstance(candidate, dict)
                or not isinstance(candidate.get("person_id"), int)):
            fail("C3_SELECTION_CANDIDATES_INVALID")
        ids.append(candidate["person_id"])
    return ids


def make_case(record: Dict[str, Any], rid: str) -> Dict[str, Any]:
    selected_record = copy.deepcopy(record)
    selected_record["rid"] = rid
    return {"case_kind": "ordinary",
            "candidate_person_ids": sorted(candidate_ids(record)),
            "records": [selected_record]}


def make_special_case(r15: Dict[str, Any], r40: Dict[str, Any]) -> Dict[str, Any]:
    r15_record = copy.deepcopy(r15)
    r15_record["rid"] = SPECIAL_RID
    r40_record = copy.deepcopy(r40)
    r40_record["rid"] = COMPANION_RID
    return {"case_kind": "1017_1021",
            "candidate_person_ids": [1017, 1021],
            "records": [r15_record, r40_record]}


def build_selection(candidates_doc: Dict[str, Any], decisions_doc: Dict[str, Any],
                    candidates_sha256: str, decisions_sha256: str) -> Dict[str, Any]:
    require_sha(candidates_sha256)
    require_sha(decisions_sha256)
    if (not isinstance(candidates_doc, dict)
            or candidates_doc.get("schema_version") != "1.0"):
        fail("C3_SELECTION_CANDIDATES_INVALID")
    if (not isinstance(decisions_doc, dict)
            or decisions_doc.get("schema_version") != "1.0"):
        fail("C3_SELECTION_DECISIONS_INVALID")
    records = candidates_doc.get("records")
    decisions = decisions_doc.get("decisions")
    if not isinstance(records, list):
        fail("C3_SELECTION_CANDIDATES_INVALID")
    if not isinstance(decisions, list):
        fail("C3_SELECTION_DECISIONS_INVALID")
    records_by_key = unique_by_key(records, "new_record_key")
    decisions_by_key = unique_by_key(decisions, "new_record_key")
    if set(records_by_key) != set(decisions_by_key):
        fail("C3_SELECTION_KEY_MISMATCH")
    rid_by_key = c0_decisions.assign_rids(records)
    key_by_rid = {rid: key for key, rid in rid_by_key.items()}
    c3_keys = [key for key, row in decisions_by_key.items()
               if row.get("token") == "[C3]"]
    if len(c3_keys) != EXPECTED_C3_COUNT:
        fail("C3_SELECTION_COUNT_INVALID")
    for key in c3_keys:
        if records_by_key[key].get("classification") != "sammenlaegning":
            fail("C3_SELECTION_CLASS_INVALID:" + key)
    if SPECIAL_RID not in key_by_rid or key_by_rid[SPECIAL_RID] not in c3_keys:
        fail("C3_SELECTION_R15_INVALID")
    r15 = records_by_key[key_by_rid[SPECIAL_RID]]
    if sorted(candidate_ids(r15)) != list(SPECIAL_PERSON_IDS):
        fail("C3_SELECTION_R15_INVALID")
    if COMPANION_RID not in key_by_rid:
        fail("C3_SELECTION_R40_INVALID")
    r40_key = key_by_rid[COMPANION_RID]
    r40_decision = decisions_by_key[r40_key]
    if (r40_key in c3_keys or r40_decision.get("token") != "[KOBL]"
            or r40_decision.get("person_id") != 1017):
        fail("C3_SELECTION_R40_INVALID")
    ordinary = [make_case(records_by_key[key], rid_by_key[key])
                for key in sorted(c3_keys, key=lambda item: int(rid_by_key[item][1:]))
                if rid_by_key[key] != SPECIAL_RID]
    special = make_special_case(r15, records_by_key[r40_key])
    cases = ordinary + [special]
    person_ids = sorted({person_id for case in cases
                         for person_id in case["candidate_person_ids"]})
    return {"schema_version": C3_SCHEMA,
            "input_hashes": {"c0_candidates_sha256": candidates_sha256,
                             "c0_decisions_sha256": decisions_sha256},
            "case_count": 7, "record_count": 8,
            "decision_line_count": 15, "person_ids": person_ids,
            "cases": cases}


def _read_input(path: str, failure_code: str) -> Any:
    try:
        return Path(path).read_bytes()
    except OSError:
        fail(failure_code)


def _decode_document(raw: bytes, failure_code: str) -> Dict[str, Any]:
    try:
        document = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        fail(failure_code)
    if not isinstance(document, dict):
        fail(failure_code)
    return document


def _arguments(argv: List[str]) -> Dict[str, str]:
    allowed = {"--candidates", "--c0-decisions", "--output"}
    values: Dict[str, str] = {}
    position = 0
    while position < len(argv):
        option = argv[position]
        if (option not in allowed or option in values
                or position + 1 >= len(argv)
                or argv[position + 1].startswith("--")):
            fail("C3_SELECTION_ARGUMENTS_INVALID")
        values[option] = argv[position + 1]
        position += 2
    if set(values) != allowed:
        fail("C3_SELECTION_ARGUMENTS_INVALID")
    return values


def publish_output(output: Path, rendered: str) -> None:
    temp_path: Optional[Path] = None
    descriptor: Optional[int] = None
    try:
        if os.path.lexists(str(output)):
            fail("C3_SELECTION_OUTPUT_EXISTS")
        descriptor, temporary = tempfile.mkstemp(
            prefix="." + output.name + ".", suffix=".tmp", dir=str(output.parent))
        temp_path = Path(temporary)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = None
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(str(temp_path), str(output))
        except FileExistsError:
            fail("C3_SELECTION_OUTPUT_EXISTS")
        os.unlink(str(temp_path))
        temp_path = None
    except OSError:
        fail("C3_SELECTION_OUTPUT_WRITE_FAILED")
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temp_path is not None:
            try:
                os.unlink(str(temp_path))
            except OSError:
                pass


def main(argv: Optional[List[str]] = None) -> int:
    values = _arguments(list(sys.argv[1:] if argv is None else argv))
    output = Path(values["--output"])
    candidates_raw = _read_input(values["--candidates"], "C3_SELECTION_CANDIDATES_INVALID")
    decisions_raw = _read_input(values["--c0-decisions"], "C3_SELECTION_DECISIONS_INVALID")
    candidates_sha256 = hashlib.sha256(candidates_raw).hexdigest()
    decisions_sha256 = hashlib.sha256(decisions_raw).hexdigest()
    candidates_doc = _decode_document(candidates_raw, "C3_SELECTION_CANDIDATES_INVALID")
    decisions_doc = _decode_document(decisions_raw, "C3_SELECTION_DECISIONS_INVALID")
    result = build_selection(candidates_doc, decisions_doc,
                             candidates_sha256, decisions_sha256)
    rendered = json.dumps(result, ensure_ascii=False, sort_keys=True,
                          separators=(",", ":")) + "\n"
    publish_output(output, rendered)
    print("sager=7 records=8 beslutningslinjer=15")
    return 0


if __name__ == "__main__":
    sys.exit(main())
