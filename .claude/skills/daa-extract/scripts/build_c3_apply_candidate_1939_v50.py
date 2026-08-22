#!/usr/bin/env python3
"""Build the database-independent, hash-bound 1939 v50 C3 candidate."""

import hashlib
import importlib.util
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional


SCRIPT_DIR = Path(__file__).resolve().parent
CONVERT_PATH = SCRIPT_DIR / "convert_c3_decisions_1939_v50.py"
BUILD_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"
NORMALIZE_PATH = SCRIPT_DIR / "normalize_narrative_1939_v50.py"
SCHEMA_VERSION = "1939-v50-c3-apply-candidate-v1"
CLI_ERROR_RE = re.compile(r"^C3_APPLY_[A-Z0-9_]+$")


def _import(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("missing loader")
    spec.loader.exec_module(module)
    return module


convert = _import("convert_c3_decisions_for_apply_candidate", CONVERT_PATH)
build = _import("build_c3_review_for_apply_candidate", BUILD_PATH)
normalize = _import("normalize_narrative_for_apply_candidate", NORMALIZE_PATH)
normalize_narrative_v1 = normalize.normalize_narrative_v1


def fail(code: str) -> None:
    raise SystemExit(code)


def _reject_constant(_token: str) -> None:
    raise ValueError("non-finite JSON constant")


def _decode_document(raw: bytes, code: str) -> Dict[str, Any]:
    if not isinstance(raw, bytes):
        fail(code)
    try:
        value = json.loads(raw.decode("utf-8"), parse_constant=_reject_constant)
    except (UnicodeDecodeError, ValueError):
        fail(code)
    if not isinstance(value, dict):
        fail(code)
    return value


def _decode_review(raw: bytes) -> str:
    if not isinstance(raw, bytes):
        fail("C3_APPLY_REVIEW_INVALID")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        fail("C3_APPLY_REVIEW_INVALID")
    raise AssertionError("unreachable")


def _canonical_bytes(value: Any) -> bytes:
    try:
        rendered = json.dumps(
            value, ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), allow_nan=False) + "\n"
    except (TypeError, ValueError):
        fail("C3_APPLY_INTERNAL_VALUE_INVALID")
    return rendered.encode("utf-8")


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _case_id(selection_case: Dict[str, Any]) -> str:
    if selection_case.get("case_kind") == "ordinary":
        records = selection_case.get("records")
        if not isinstance(records, list) or len(records) != 1:
            fail("C3_APPLY_SELECTION_INVALID")
        rid = records[0].get("rid") if isinstance(records[0], dict) else None
        if not isinstance(rid, str):
            fail("C3_APPLY_SELECTION_INVALID")
        return rid
    if selection_case.get("case_kind") == "1017_1021":
        return "1017/1021"
    fail("C3_APPLY_SELECTION_INVALID")
    raise AssertionError("unreachable")


def _validate_upstream(
        decisions: Dict[str, Any], selection: Dict[str, Any],
        decisions_raw: bytes, selection_raw: bytes, state_raw: bytes,
        review_raw: bytes) -> Dict[str, str]:
    selection_hashes = selection.get("input_hashes")
    decision_hashes = decisions.get("input_hashes")
    if (not isinstance(selection_hashes, dict)
            or set(selection_hashes) != {
                "c0_candidates_sha256", "c0_decisions_sha256"}
            or not isinstance(decision_hashes, dict)
            or set(decision_hashes) != {
                "c0_candidates_sha256", "c0_decisions_sha256",
                "selection_sha256", "state_sha256", "review_sha256"}):
        fail("C3_APPLY_UPSTREAM_HASH_MISMATCH")
    expected = {
        "c0_candidates_sha256": selection_hashes["c0_candidates_sha256"],
        "c0_decisions_sha256": selection_hashes["c0_decisions_sha256"],
        "selection_sha256": _sha(selection_raw),
        "state_sha256": _sha(state_raw),
        "review_sha256": _sha(review_raw),
    }
    if decision_hashes != expected:
        fail("C3_APPLY_UPSTREAM_HASH_MISMATCH")
    return {
        "decisions_sha256": _sha(decisions_raw),
        "selection_sha256": expected["selection_sha256"],
        "state_sha256": expected["state_sha256"],
        "review_sha256": expected["review_sha256"],
        "c0_candidates_sha256": expected["c0_candidates_sha256"],
        "c0_decisions_sha256": expected["c0_decisions_sha256"],
    }


def _selection_records(selection: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    records: Dict[str, Dict[str, Any]] = {}
    record_keys = set()
    for case in selection["cases"]:
        for record in case["records"]:
            rid = record["rid"]
            key = record["new_record_key"]
            if rid in records or key in record_keys:
                fail("C3_APPLY_SELECTION_INVALID")
            records[rid] = record
            record_keys.add(key)
    return records


def _ordered_unique_flags(value: Any) -> List[Dict[str, Any]]:
    if not isinstance(value, list):
        fail("C3_APPLY_NORMALIZATION_FLAGS_INVALID")
    flags: List[Dict[str, Any]] = []
    seen = set()
    for flag in value:
        if (not isinstance(flag, dict)
                or set(flag) != {"kind", "context", "char_offset"}
                or not isinstance(flag["kind"], str) or not flag["kind"]
                or not isinstance(flag["context"], str)
                or type(flag["char_offset"]) is not int
                or flag["char_offset"] < 0):
            fail("C3_APPLY_NORMALIZATION_FLAGS_INVALID")
        key = _canonical_bytes(flag)
        if key in seen:
            fail("C3_APPLY_NORMALIZATION_FLAGS_INVALID")
        seen.add(key)
        flags.append(dict(flag))
    return flags


def _assign_payload(decision: Dict[str, Any], record: Dict[str, Any],
                    corpus: str) -> Dict[str, Any]:
    target = decision.get("person_id")
    matches = [candidate for candidate in record.get("candidates", [])
               if isinstance(candidate, dict)
               and candidate.get("person_id") == target]
    if len(matches) != 1:
        fail("C3_APPLY_ASSIGN_TARGET_INVALID")
    selected = matches[0]
    raw = record.get("verbatim_text")
    record_key = record.get("new_record_key")
    side = selected.get("side")
    if (not isinstance(raw, str) or not raw
            or not isinstance(record_key, str) or not record_key
            or type(target) is not int or target <= 0
            or not isinstance(side, str) or not side
            or selected.get("staged") is not False):
        fail("C3_APPLY_ASSIGN_TARGET_INVALID")
    first = normalize_narrative_v1(raw, corpus)
    second = normalize_narrative_v1(raw, corpus)
    if _canonical_bytes(first) != _canonical_bytes(second):
        fail("C3_APPLY_NORMALIZATION_NONDETERMINISTIC")
    if (not isinstance(first, dict) or set(first) != {"text", "flags", "applied"}
            or not isinstance(first.get("text"), str) or not first["text"]):
        fail("C3_APPLY_NORMALIZATION_INVALID")
    flags = _ordered_unique_flags(first["flags"])
    normalized_raw = first["text"].encode("utf-8")
    return {
        "action": "assign",
        "rid": decision["rid"],
        "record_key": record_key,
        "target_person_id": target,
        "raw_sha256": _sha(raw.encode("utf-8")),
        "normalized_text": first["text"],
        "normalized_sha256": _sha(normalized_raw),
        "normalization_version": normalize.VERSION,
        "normalization_flags": flags,
        "expected_narrative": {
            "privat": False,
            "side": side,
            "record_label": record_key,
            "citation_label": "DAA 1939 side " + side,
        },
    }


def build_candidate_manifest(
        decisions_raw: bytes, selection_raw: bytes, state_raw: bytes,
        review_raw: bytes) -> Dict[str, Any]:
    """Validate the complete raw C3 chain and return five whole cases."""
    decisions = _decode_document(decisions_raw, "C3_APPLY_DECISIONS_INVALID")
    selection = _decode_document(selection_raw, "C3_APPLY_SELECTION_INVALID")
    state = _decode_document(state_raw, "C3_APPLY_STATE_INVALID")
    review = _decode_review(review_raw)

    try:
        build._validate_documents(selection, state)
    except SystemExit:
        fail("C3_APPLY_SELECTION_INVALID")
    input_hashes = _validate_upstream(
        decisions, selection, decisions_raw, selection_raw, state_raw,
        review_raw)
    converter_hashes = {
        key: decisions["input_hashes"][key]
        for key in ("c0_candidates_sha256", "c0_decisions_sha256",
                    "selection_sha256", "state_sha256", "review_sha256")
    }
    try:
        reproduced = convert.parse_review(
            review, selection, state, converter_hashes)
    except SystemExit:
        fail("C3_APPLY_REVIEW_INVALID")
    if _canonical_bytes(reproduced) != _canonical_bytes(decisions):
        fail("C3_APPLY_DECISIONS_MISMATCH")

    selection_cases = selection.get("cases")
    decision_cases = decisions.get("cases")
    if (not isinstance(selection_cases, list) or len(selection_cases) != 7
            or not isinstance(decision_cases, list)
            or len(decision_cases) != 7):
        fail("C3_APPLY_DECISION_SET_INVALID")
    case_ids = [_case_id(case) for case in selection_cases]
    if len(set(case_ids)) != 7:
        fail("C3_APPLY_SELECTION_INVALID")
    records = _selection_records(selection)
    corpus = "\n".join(
        record["verbatim_text"] for case in selection_cases
        for record in case["records"])

    resolved_indexes = []
    for index, case in enumerate(decision_cases):
        identity = case.get("identity") if isinstance(case, dict) else None
        record_decisions = case.get("record_decisions") if isinstance(case, dict) else None
        if (not isinstance(identity, dict)
                or not isinstance(record_decisions, list)
                or not record_decisions):
            fail("C3_APPLY_DECISION_SET_INVALID")
        actions = [identity.get("action")] + [
            row.get("action") if isinstance(row, dict) else None
            for row in record_decisions]
        if all(action != "unresolved" for action in actions):
            resolved_indexes.append(index)
        elif any(action != "unresolved" for action in actions):
            fail("C3_APPLY_DECISION_SET_INVALID")

    cases: List[Dict[str, Any]] = []
    identity_count = assign_count = no_publication_count = 0
    used_rids = set()
    for index in resolved_indexes:
        decision_case = decision_cases[index]
        selection_case = selection_cases[index]
        identity = decision_case["identity"]
        person_ids = selection_case["candidate_person_ids"]
        if (identity != {"action": "different"}
                or not isinstance(person_ids, list) or len(person_ids) != 2
                or any(type(person_id) is not int or person_id <= 0
                       for person_id in person_ids)
                or person_ids != sorted(set(person_ids))):
            fail("C3_APPLY_DECISION_SET_INVALID")
        identity_count += 1
        output_records = []
        for decision in decision_case["record_decisions"]:
            if not isinstance(decision, dict):
                fail("C3_APPLY_DECISION_SET_INVALID")
            rid = decision.get("rid")
            if not isinstance(rid, str) or rid in used_rids or rid not in records:
                fail("C3_APPLY_DECISION_SET_INVALID")
            used_rids.add(rid)
            action = decision.get("action")
            if action == "assign":
                output_records.append(_assign_payload(decision, records[rid], corpus))
                assign_count += 1
            elif action == "no_publication" and set(decision) == {"action", "rid"}:
                output_records.append({
                    "action": "no_publication", "rid": rid,
                    "record_key": records[rid]["new_record_key"],
                })
                no_publication_count += 1
            else:
                fail("C3_APPLY_DECISION_SET_INVALID")
        cases.append({
            "case_id": case_ids[index],
            "identity": {"action": "different", "person_ids": list(person_ids)},
            "record_decisions": output_records,
        })

    counts = {
        "cases": len(cases),
        "identity_different": identity_count,
        "record_assign": assign_count,
        "record_no_publication": no_publication_count,
    }
    if counts != {
            "cases": 5, "identity_different": 5,
            "record_assign": 5, "record_no_publication": 1}:
        fail("C3_APPLY_DECISION_SET_INVALID")
    result: Dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "input_hashes": input_hashes,
        "counts": counts,
        "cases": cases,
    }
    result["canonical_content_sha256"] = _sha(_canonical_bytes(result))
    return result


def _arguments(argv: List[str]) -> Dict[str, str]:
    allowed = {"--decisions", "--selection", "--state", "--review", "--output"}
    values: Dict[str, str] = {}
    position = 0
    while position < len(argv):
        option = argv[position]
        if (option not in allowed or option in values
                or position + 1 >= len(argv)
                or argv[position + 1].startswith("--")):
            fail("C3_APPLY_ARGUMENTS_INVALID")
        values[option] = argv[position + 1]
        position += 2
    if set(values) != allowed:
        fail("C3_APPLY_ARGUMENTS_INVALID")
    return values


def _read_regular(path_text: str, code: str) -> bytes:
    path = Path(path_text)
    try:
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            fail(code)
        return path.read_bytes()
    except OSError:
        fail(code)
    raise AssertionError("unreachable")


def publish_output(output: Path, rendered: str) -> None:
    """Publish through a sibling hard link without overwriting any path."""
    temporary_path: Optional[Path] = None
    descriptor: Optional[int] = None
    try:
        if os.path.lexists(str(output)):
            fail("C3_APPLY_OUTPUT_EXISTS")
        parent_info = output.parent.lstat()
        if stat.S_ISLNK(parent_info.st_mode) or not stat.S_ISDIR(parent_info.st_mode):
            fail("C3_APPLY_OUTPUT_WRITE_FAILED")
        descriptor, temporary = tempfile.mkstemp(
            prefix="." + output.name + ".", suffix=".tmp",
            dir=str(output.parent))
        temporary_path = Path(temporary)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = None
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(str(temporary_path), str(output))
        except FileExistsError:
            fail("C3_APPLY_OUTPUT_EXISTS")
        os.unlink(str(temporary_path))
        temporary_path = None
    except OSError:
        fail("C3_APPLY_OUTPUT_WRITE_FAILED")
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temporary_path is not None:
            try:
                os.unlink(str(temporary_path))
            except OSError:
                pass


def main(argv: Optional[List[str]] = None) -> int:
    values = _arguments(list(sys.argv[1:] if argv is None else argv))
    output = Path(values["--output"])
    if os.path.lexists(str(output)):
        fail("C3_APPLY_OUTPUT_EXISTS")
    decisions_raw = _read_regular(values["--decisions"], "C3_APPLY_DECISIONS_INVALID")
    selection_raw = _read_regular(values["--selection"], "C3_APPLY_SELECTION_INVALID")
    state_raw = _read_regular(values["--state"], "C3_APPLY_STATE_INVALID")
    review_raw = _read_regular(values["--review"], "C3_APPLY_REVIEW_INVALID")
    result = build_candidate_manifest(
        decisions_raw, selection_raw, state_raw, review_raw)
    rendered = _canonical_bytes(result).decode("utf-8")
    publish_output(output, rendered)
    output_sha = _sha(rendered.encode("utf-8"))
    counts = result["counts"]
    print(
        "schema={} cases={} identity_different={} record_assign={} "
        "record_no_publication={} output={} sha256={}".format(
            result["schema_version"], counts["cases"],
            counts["identity_different"], counts["record_assign"],
            counts["record_no_publication"], output.name, output_sha))
    return 0


def _cli_status() -> int:
    try:
        return main()
    except SystemExit as error:
        token = str(error)
        if CLI_ERROR_RE.fullmatch(token) is None:
            token = "C3_APPLY_INTERNAL_ERROR"
        print(token, file=sys.stderr)
        return 1
    except Exception:
        print("C3_APPLY_INTERNAL_ERROR", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(_cli_status())
