#!/usr/bin/env python3
"""Validér C3-reviewbytes og find de 15 redigerbare tokenintervaller."""

import hashlib
import importlib.util
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Tuple


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"
CONVERTER_PATH = SCRIPT_DIR / "convert_c3_decisions_1939_v50.py"
HASH_KEYS = {
    "c0_candidates_sha256",
    "c0_decisions_sha256",
    "selection_sha256",
    "state_sha256",
    "review_sha256",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("missing loader")
    spec.loader.exec_module(module)
    return module


build = _load_module("build_c3_review_1939_v50_for_html", BUILD_PATH)
converter = _load_module(
    "convert_c3_decisions_1939_v50_for_html", CONVERTER_PATH)


@dataclass(frozen=True)
class DecisionSlot:
    decision_id: str
    case_id: str
    decision_type: str
    start: int
    end: int
    default_token: str
    allowed_person_ids: Tuple[int, ...]


def fail(code: str) -> None:
    raise SystemExit(code)


def _valid_hashes(input_hashes: Any) -> bool:
    return (
        isinstance(input_hashes, Mapping)
        and set(input_hashes) == HASH_KEYS
        and all(isinstance(value, str)
                and SHA256_RE.fullmatch(value) is not None
                for value in input_hashes.values())
    )


def _decode_document(raw: bytes) -> Dict[str, Any]:
    try:
        document = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        fail("C3_HTML_REVIEW_INVALID")
    if not isinstance(document, dict):
        fail("C3_HTML_REVIEW_INVALID")
    return document


def _map_review_error(error: SystemExit) -> None:
    token = str(error).split(":", 1)[0]
    if token in {
            "C3_REVIEW_HASH_INVALID",
            "C3_REVIEW_HASH_MISMATCH",
            "C3_REVIEW_SELECTION_HASH_INVALID",
            "C3_REVIEW_SELECTION_HASH_MISMATCH"}:
        fail("C3_HTML_HASH_MISMATCH")
    if token == "C3_REVIEW_COUNT_INVALID":
        fail("C3_HTML_COUNT_INVALID")
    if token in {
            "C3_REVIEW_SPECIAL_INVALID",
            "C3_REVIEW_R15_INVALID",
            "C3_REVIEW_R40_INVALID"}:
        fail("C3_HTML_SPECIAL_INVALID")
    fail("C3_HTML_REVIEW_INVALID")


def _validated_sequence(selection_doc: Mapping[str, Any],
                        state_doc: Mapping[str, Any]
                        ) -> List[Dict[str, Any]]:
    try:
        sequence = build.review_sequence(selection_doc, state_doc)
    except SystemExit as error:
        _map_review_error(error)
        raise AssertionError("unreachable")
    if not isinstance(sequence, list):
        fail("C3_HTML_REVIEW_INVALID")
    return sequence


def _validate_locked_counts(selection_doc: Mapping[str, Any]) -> None:
    expected = {
        "case_count": 7,
        "record_count": 8,
        "decision_line_count": 15,
    }
    if any(type(selection_doc.get(field)) is not int
           or selection_doc.get(field) != value
           for field, value in expected.items()):
        fail("C3_HTML_COUNT_INVALID")
    cases = selection_doc.get("cases")
    if not isinstance(cases, list):
        fail("C3_HTML_REVIEW_INVALID")
    if len(cases) != 7:
        fail("C3_HTML_COUNT_INVALID")
    record_count = 0
    for case in cases:
        if not isinstance(case, Mapping) or not isinstance(
                case.get("records"), list):
            fail("C3_HTML_REVIEW_INVALID")
        record_count += len(case["records"])
    if record_count != 8:
        fail("C3_HTML_COUNT_INVALID")


def _case_id(decision_id: str) -> str:
    if decision_id == "identity:1017:1021" or decision_id in {
            "record:R40", "record:R15"}:
        return "1017/1021"
    parts = decision_id.split(":")
    if len(parts) != 2 or not parts[1]:
        fail("C3_HTML_REVIEW_INVALID")
    return parts[1]


def _validate_slot_contract(review_bytes: bytes,
                            slots: Sequence[DecisionSlot]) -> None:
    decision_ids = [slot.decision_id for slot in slots]
    if len(set(decision_ids)) != len(decision_ids):
        fail("C3_HTML_DECISION_DUPLICATE")
    previous_end = 0
    for slot in slots:
        if (
                not isinstance(slot.decision_id, str)
                or not slot.decision_id
                or not isinstance(slot.case_id, str)
                or not slot.case_id
                or slot.decision_type not in {"identity", "record"}
                or type(slot.start) is not int
                or type(slot.end) is not int
                or slot.start < previous_end
                or slot.start < 0
                or slot.end <= slot.start
                or slot.end > len(review_bytes)
                or not isinstance(slot.default_token, str)
                or not slot.default_token
                or not isinstance(slot.allowed_person_ids, tuple)
                or not slot.allowed_person_ids
                or tuple(sorted(set(slot.allowed_person_ids)))
                != slot.allowed_person_ids
                or any(type(person_id) is not int or person_id <= 0
                       for person_id in slot.allowed_person_ids)):
            fail("C3_HTML_SLOT_INVALID")
        expected = slot.default_token.encode("utf-8")
        if review_bytes[slot.start:slot.end] != expected:
            fail("C3_HTML_SLOT_INVALID")
        try:
            review_bytes[:slot.start].decode("utf-8")
            review_bytes[:slot.end].decode("utf-8")
        except UnicodeDecodeError:
            fail("C3_HTML_SLOT_INVALID")
        previous_end = slot.end


def _discover_slots(review_bytes: bytes,
                    selection_bytes: bytes,
                    state_bytes: bytes,
                    input_hashes: Mapping[str, str]) -> List[DecisionSlot]:
    if not _valid_hashes(input_hashes):
        fail("C3_HTML_HASH_MISMATCH")
    if (not isinstance(review_bytes, bytes)
            or not isinstance(selection_bytes, bytes)
            or not isinstance(state_bytes, bytes)):
        fail("C3_HTML_REVIEW_INVALID")
    exact_inputs = (
        (review_bytes, "review_sha256"),
        (selection_bytes, "selection_sha256"),
        (state_bytes, "state_sha256"),
    )
    if any(hashlib.sha256(raw).hexdigest() != input_hashes[hash_name]
           for raw, hash_name in exact_inputs):
        fail("C3_HTML_HASH_MISMATCH")
    selection_doc = _decode_document(selection_bytes)
    state_doc = _decode_document(state_bytes)
    selection_hashes = selection_doc.get("input_hashes")
    if selection_hashes != {
            "c0_candidates_sha256": input_hashes["c0_candidates_sha256"],
            "c0_decisions_sha256": input_hashes["c0_decisions_sha256"]}:
        fail("C3_HTML_HASH_MISMATCH")
    if state_doc.get("selection_sha256") != input_hashes[
            "selection_sha256"]:
        fail("C3_HTML_HASH_MISMATCH")
    _validate_locked_counts(selection_doc)
    try:
        review_text = review_bytes.decode("utf-8")
    except UnicodeDecodeError:
        fail("C3_HTML_REVIEW_INVALID")

    sequence = _validated_sequence(selection_doc, state_doc)
    try:
        parsed = converter.parse_review(
            review_text, selection_doc, state_doc, dict(input_hashes))
    except SystemExit as error:
        _map_review_error(error)
        raise AssertionError("unreachable")
    if parsed.get("counts") != {
            "cases": 7,
            "records": 8,
            "decision_lines": 15,
            "unresolved": 12}:
        fail("C3_HTML_COUNT_INVALID")

    header = build.HEADER.format(
        selection_sha256=input_hashes["selection_sha256"],
        state_sha256=input_hashes["state_sha256"]) + "\n"
    lines = review_text.splitlines(keepends=True)
    header_line_count = len(header.splitlines(keepends=True))
    line_offsets: List[int] = []
    byte_offset = 0
    for line in lines:
        line_offsets.append(byte_offset)
        byte_offset += len(line.encode("utf-8"))

    slots: List[DecisionSlot] = []
    for position, item in enumerate(sequence):
        if item.get("type") == "heading":
            continue
        line_index = header_line_count + position
        if line_index >= len(lines):
            fail("C3_HTML_REVIEW_INVALID")
        default_token = item.get("default_token")
        tail = item.get("tail")
        decision_id = item.get("decision_id")
        allowed_ids = item.get("allowed_person_ids")
        if (
                item.get("type") not in {"identity", "record"}
                or not isinstance(default_token, str)
                or not isinstance(tail, str)
                or not isinstance(decision_id, str)
                or not isinstance(allowed_ids, list)):
            fail("C3_HTML_REVIEW_INVALID")
        expected_line = "[{}] {}\n".format(default_token, tail)
        if lines[line_index] != expected_line:
            fail("C3_HTML_SLOT_INVALID")
        start = line_offsets[line_index] + len("[".encode("utf-8"))
        end = start + len(default_token.encode("utf-8"))
        slots.append(DecisionSlot(
            decision_id=decision_id,
            case_id=_case_id(decision_id),
            decision_type=item["type"],
            start=start,
            end=end,
            default_token=default_token,
            allowed_person_ids=tuple(allowed_ids),
        ))
    if len(slots) != 15:
        fail("C3_HTML_COUNT_INVALID")
    _validate_slot_contract(review_bytes, slots)
    return slots


def decision_slots(review_bytes: bytes,
                   selection_bytes: bytes,
                   state_bytes: bytes,
                   input_hashes: Mapping[str, str]) -> List[Dict[str, Any]]:
    """Validér rå inputbytes og returnér JSON-sikre tokenintervaller."""
    slots = _discover_slots(
        review_bytes, selection_bytes, state_bytes, input_hashes)
    return [
        {
            "decision_id": slot.decision_id,
            "case_id": slot.case_id,
            "decision_type": slot.decision_type,
            "start": slot.start,
            "end": slot.end,
            "default_token": slot.default_token,
            "allowed_person_ids": list(slot.allowed_person_ids),
        }
        for slot in slots
    ]
