#!/usr/bin/env python3
"""Konvertér et byte-låst C3-reviewark til tekstfri beslutnings-JSON."""

import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"
SCHEMA_VERSION = "1939-v50-c3-decisions-v1"
IDENTITY_SIMPLE = {"FORSKELLIGE", "UAFKLARET"}
RECORD_SIMPLE = {"INGEN_PUBLIKATION", "UAFKLARET"}
REVISION_KINDS = {"split_into", "merged_from", "replaced_by"}
SAMME_RE = re.compile(r"^SAMME ([0-9]+) ([0-9]+)$")
TIL_RE = re.compile(r"^TIL ([0-9]+)$")
REVISION_RE = re.compile(r"^REVISION (split_into|merged_from|replaced_by)$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CLI_ERROR_RE = re.compile(r"^C3_[A-Z0-9_]+$")
HASH_KEYS = {
    "c0_candidates_sha256", "c0_decisions_sha256", "selection_sha256",
    "state_sha256", "review_sha256",
}


def _import_build():
    spec = importlib.util.spec_from_file_location(
        "build_c3_review_1939_v50_for_converter", BUILD_PATH)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("missing loader")
    spec.loader.exec_module(module)
    return module


build = _import_build()


def fail(code: str) -> None:
    raise SystemExit(code)


def _valid_hashes(input_hashes: Any) -> bool:
    return (isinstance(input_hashes, dict)
            and set(input_hashes) == HASH_KEYS
            and all(isinstance(value, str)
                    and SHA256_RE.fullmatch(value) is not None
                    for value in input_hashes.values()))


def _normalize_build_error(error: SystemExit) -> None:
    token = str(error)
    if token == "C3_REVIEW_SELECTION_HASH_MISMATCH":
        fail("C3_REVIEW_HASH_MISMATCH")
    stable_code = token.split(":", 1)[0]
    if CLI_ERROR_RE.fullmatch(stable_code) is not None:
        fail(stable_code)
    fail("C3_REVIEW_INPUT_INVALID")


def _identity(token: str, allowed_person_ids: List[int]) -> Dict[str, Any]:
    if token == "FORSKELLIGE":
        return {"action": "different"}
    if token == "UAFKLARET":
        return {"action": "unresolved"}
    match = SAMME_RE.fullmatch(token)
    if match is None:
        fail("C3_REVIEW_TOKEN_INVALID")
    alias_id, canonical_id = (int(match.group(1)), int(match.group(2)))
    if alias_id not in allowed_person_ids or canonical_id not in allowed_person_ids:
        fail("C3_REVIEW_TOKEN_INVALID")
    return {
        "action": "same",
        "alias_person_id": alias_id,
        "canonical_person_id": canonical_id,
    }


def _record(token: str, allowed_person_ids: List[int]) -> Dict[str, Any]:
    if token == "INGEN_PUBLIKATION":
        return {"action": "no_publication"}
    if token == "UAFKLARET":
        return {"action": "unresolved"}
    assign_match = TIL_RE.fullmatch(token)
    if assign_match is not None:
        person_id = int(assign_match.group(1))
        if person_id not in allowed_person_ids:
            fail("C3_REVIEW_TOKEN_INVALID")
        return {"action": "assign", "person_id": person_id}
    revision_match = REVISION_RE.fullmatch(token)
    if revision_match is not None:
        return {"action": "revision",
                "relation_kind": revision_match.group(1)}
    fail("C3_REVIEW_TOKEN_INVALID")
    raise AssertionError("unreachable")


def _parse_decision_line(line: str, expected_line: str,
                         item: Dict[str, Any]) -> Dict[str, Any]:
    tail = item["tail"]
    suffix = "] " + tail + "\n"
    if not line.startswith("["):
        fail("C3_REVIEW_TOKEN_INVALID")
    if not line.endswith(suffix):
        fail("C3_REVIEW_LINE_TAMPERED")
    token = line[1:-len(suffix)]
    if not token:
        fail("C3_REVIEW_TOKEN_INVALID")
    if item["type"] == "identity":
        decision = _identity(token, item["allowed_person_ids"])
    else:
        decision = _record(token, item["allowed_person_ids"])
    expected_prefix = "[{}]".format(item["default_token"])
    if not expected_line.startswith(expected_prefix):
        fail("C3_REVIEW_INTERNAL_ERROR")
    decision["_token"] = token
    return decision


def _structured_cases(selection_doc: Dict[str, Any],
                      decisions: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
    cases: List[Dict[str, Any]] = []
    for case in selection_doc["cases"][:-1]:
        rid = case["records"][0]["rid"]
        record_decision = dict(decisions["record:" + rid])
        record_decision["rid"] = rid
        cases.append({
            "case_kind": "ordinary",
            "rid": rid,
            "identity": dict(decisions["identity:" + rid]),
            "record_decisions": [record_decision],
        })
    special_records = []
    for rid in ("R40", "R15"):
        record_decision = dict(decisions["record:" + rid])
        record_decision["rid"] = rid
        special_records.append(record_decision)
    cases.append({
        "case_kind": "1017_1021",
        "identity": dict(decisions["identity:1017:1021"]),
        "record_decisions": special_records,
    })
    return cases


def _same_component(seed: int,
                    same_edges: List[Dict[str, Any]]) -> set:
    component = {seed}
    changed = True
    while changed:
        changed = False
        for edge in same_edges:
            subject_id = edge["subject_id"]
            object_id = edge["object_id"]
            if subject_id in component or object_id in component:
                old_size = len(component)
                component.update({subject_id, object_id})
                changed = changed or len(component) != old_size
    return component


def _validate_same_decision(decision: Dict[str, Any],
                            state_doc: Dict[str, Any]) -> None:
    if decision["action"] != "same":
        return
    alias_id = decision["alias_person_id"]
    canonical_id = decision["canonical_person_id"]
    if alias_id == canonical_id:
        fail("C3_DECISION_SELF_LINK")
    same_edges = [edge for edge in state_doc["identity_edges"]
                  if edge["role"] == "samme_som"]
    if any(edge["subject_id"] == alias_id
           and edge["object_id"] == canonical_id for edge in same_edges):
        return
    if any(edge["subject_id"] == alias_id
           and edge["object_id"] != canonical_id for edge in same_edges):
        fail("C3_DECISION_G3_CONFLICT")
    if any(edge["object_id"] == alias_id for edge in same_edges):
        fail("C3_DECISION_G4_CONFLICT")
    normalized = (min(alias_id, canonical_id), max(alias_id, canonical_id))
    if any(edge["role"] == "ikke_samme_som"
           and (edge["subject_id"], edge["object_id"]) == normalized
           for edge in state_doc["identity_edges"]):
        fail("C3_DECISION_NOT_SAME_CONFLICT")
    alias_component = _same_component(alias_id, same_edges)
    canonical_component = _same_component(canonical_id, same_edges)
    if any(
            (conflict["left_person_id"] in alias_component
             and conflict["right_person_id"] in canonical_component)
            or (conflict["right_person_id"] in alias_component
                and conflict["left_person_id"] in canonical_component)
            for conflict in state_doc["partner_conflicts"]):
        fail("C3_DECISION_PARTNER_CONFLICT")


def _validate_graph_decisions(decisions: Dict[str, Dict[str, Any]],
                              state_doc: Dict[str, Any]) -> None:
    for decision_id, decision in decisions.items():
        if decision_id.startswith("identity:"):
            _validate_same_decision(decision, state_doc)


def parse_review(text: str, selection_doc: Dict[str, Any],
                 state_doc: Dict[str, Any],
                 input_hashes: Dict[str, str]) -> Dict[str, Any]:
    if not isinstance(text, str) or not _valid_hashes(input_hashes):
        fail("C3_REVIEW_HASH_MISMATCH")
    if (selection_doc.get("input_hashes") if isinstance(selection_doc, dict)
            else None) != {
                "c0_candidates_sha256": input_hashes["c0_candidates_sha256"],
                "c0_decisions_sha256": input_hashes["c0_decisions_sha256"],
            }:
        fail("C3_REVIEW_HASH_MISMATCH")
    if hashlib.sha256(text.encode("utf-8")).hexdigest() != input_hashes[
            "review_sha256"]:
        fail("C3_REVIEW_HASH_MISMATCH")

    if (isinstance(state_doc, dict)
            and isinstance(state_doc.get("selection_sha256"), str)
            and SHA256_RE.fullmatch(state_doc["selection_sha256"]) is not None
            and state_doc["selection_sha256"]
            != input_hashes["selection_sha256"]):
        fail("C3_REVIEW_HASH_MISMATCH")

    try:
        baseline = build.render_review(
            selection_doc, state_doc, input_hashes["selection_sha256"],
            input_hashes["state_sha256"])
        sequence = build.review_sequence(selection_doc, state_doc)
    except SystemExit as error:
        _normalize_build_error(error)
        raise AssertionError("unreachable")
    header = build.HEADER.format(
        selection_sha256=input_hashes["selection_sha256"],
        state_sha256=input_hashes["state_sha256"]) + "\n"
    header_lines = header.splitlines(keepends=True)
    actual_lines = text.splitlines(keepends=True)
    baseline_lines = baseline.splitlines(keepends=True)
    for item in sequence:
        if item["type"] != "heading":
            suffix = "] " + item["tail"] + "\n"
            occurrences = sum(
                1 for line in actual_lines
                if line.startswith("[") and line.endswith(suffix))
            if occurrences > 1:
                fail("C3_REVIEW_DECISION_DUPLICATE")
    if len(actual_lines) < len(baseline_lines):
        fail("C3_REVIEW_LINE_MISSING")
    if len(actual_lines) > len(baseline_lines):
        fail("C3_REVIEW_LINE_UNEXPECTED")
    for actual, expected in zip(actual_lines[:len(header_lines)], header_lines):
        if actual != expected:
            if (expected.startswith("# selection_sha256=")
                    or expected.startswith("# state_sha256=")):
                fail("C3_REVIEW_HASH_MISMATCH")
            fail("C3_REVIEW_LINE_TAMPERED")

    decisions: Dict[str, Dict[str, Any]] = {}
    reconstructed = list(header_lines)
    body_offset = len(header_lines)
    for position, item in enumerate(sequence):
        actual = actual_lines[body_offset + position]
        expected = baseline_lines[body_offset + position]
        if item["type"] == "heading":
            if actual != expected:
                fail("C3_REVIEW_LINE_TAMPERED")
            reconstructed.append(expected)
            continue
        if item["decision_id"] in decisions:
            fail("C3_REVIEW_DECISION_DUPLICATE")
        decision = _parse_decision_line(actual, expected, item)
        token = decision.pop("_token")
        decisions[item["decision_id"]] = decision
        reconstructed.append("[{}] {}\n".format(token, item["tail"]))
    if "".join(reconstructed) != text:
        fail("C3_REVIEW_LINE_TAMPERED")

    _validate_graph_decisions(decisions, state_doc)
    cases = _structured_cases(selection_doc, decisions)
    unresolved = sum(
        1 for case in cases
        for decision in [case["identity"]] + case["record_decisions"]
        if decision["action"] == "unresolved")
    return {
        "schema_version": SCHEMA_VERSION,
        "input_hashes": dict(input_hashes),
        "counts": {
            "cases": 7,
            "records": 8,
            "decision_lines": 15,
            "unresolved": unresolved,
        },
        "cases": cases,
        "database_identity": {
            "database_name": state_doc["database_name"],
            "database_identity": state_doc["database_identity"],
        },
    }


def _arguments(argv: List[str]) -> Dict[str, str]:
    allowed = {"--review", "--selection", "--state", "--output"}
    values: Dict[str, str] = {}
    position = 0
    while position < len(argv):
        option = argv[position]
        if (option not in allowed or option in values
                or position + 1 >= len(argv)
                or argv[position + 1].startswith("--")):
            fail("C3_DECISIONS_ARGUMENTS_INVALID")
        values[option] = argv[position + 1]
        position += 2
    if set(values) != allowed:
        fail("C3_DECISIONS_ARGUMENTS_INVALID")
    return values


def _read_input(path: str, failure_code: str) -> bytes:
    try:
        return Path(path).read_bytes()
    except OSError:
        fail(failure_code)
    raise AssertionError("unreachable")


def _decode_text(raw: bytes) -> str:
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        fail("C3_DECISIONS_REVIEW_INVALID")
    raise AssertionError("unreachable")


def _decode_document(raw: bytes, failure_code: str) -> Dict[str, Any]:
    try:
        document = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        fail(failure_code)
    if not isinstance(document, dict):
        fail(failure_code)
    return document


def publish_output(output: Path, rendered: str) -> None:
    """Publisér med hard-link; destinationen kan aldrig overskrives."""
    temp_path: Optional[Path] = None
    descriptor: Optional[int] = None
    try:
        if os.path.lexists(str(output)):
            fail("C3_DECISIONS_OUTPUT_EXISTS")
        descriptor, temporary = tempfile.mkstemp(
            prefix="." + output.name + ".", suffix=".tmp",
            dir=str(output.parent))
        temp_path = Path(temporary)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = None
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(str(temp_path), str(output))
        except FileExistsError:
            fail("C3_DECISIONS_OUTPUT_EXISTS")
        os.unlink(str(temp_path))
        temp_path = None
    except OSError:
        fail("C3_DECISIONS_OUTPUT_WRITE_FAILED")
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
    if os.path.lexists(str(output)):
        fail("C3_DECISIONS_OUTPUT_EXISTS")
    review_raw = _read_input(values["--review"],
                             "C3_DECISIONS_REVIEW_INVALID")
    selection_raw = _read_input(values["--selection"],
                                "C3_DECISIONS_SELECTION_INVALID")
    state_raw = _read_input(values["--state"],
                            "C3_DECISIONS_STATE_INVALID")
    review_text = _decode_text(review_raw)
    selection_doc = _decode_document(
        selection_raw, "C3_DECISIONS_SELECTION_INVALID")
    state_doc = _decode_document(state_raw, "C3_DECISIONS_STATE_INVALID")
    c0_hashes = selection_doc.get("input_hashes")
    if not isinstance(c0_hashes, dict):
        fail("C3_DECISIONS_SELECTION_INVALID")
    input_hashes = {
        "c0_candidates_sha256": c0_hashes.get("c0_candidates_sha256"),
        "c0_decisions_sha256": c0_hashes.get("c0_decisions_sha256"),
        "selection_sha256": hashlib.sha256(selection_raw).hexdigest(),
        "state_sha256": hashlib.sha256(state_raw).hexdigest(),
        "review_sha256": hashlib.sha256(review_raw).hexdigest(),
    }
    result = parse_review(
        review_text, selection_doc, state_doc, input_hashes)
    rendered = json.dumps(
        result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    publish_output(output, rendered)
    counts = result["counts"]
    print("sager={} records={} beslutningslinjer={} uafklarede={}".format(
        counts["cases"], counts["records"], counts["decision_lines"],
        counts["unresolved"]))
    return 0


def _cli_status() -> int:
    try:
        return main()
    except SystemExit as error:
        token = str(error)
        if CLI_ERROR_RE.fullmatch(token) is None:
            token = "C3_DECISIONS_INTERNAL_ERROR"
        print(token, file=sys.stderr)
        return 1
    except Exception:
        print("C3_DECISIONS_INTERNAL_ERROR", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(_cli_status())
