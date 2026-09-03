#!/usr/bin/env python3
"""Build the database-independent, hash-bound 1939 v50 C3 candidate."""

import hashlib
import importlib.util
import json
import os
import re
import secrets
import stat
import sys
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

    def reject_duplicate_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                fail(code)
            result[key] = value
        return result

    try:
        value = json.loads(
            raw.decode("utf-8"), parse_constant=_reject_constant,
            object_pairs_hook=reject_duplicate_keys)
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
    display_name = selected.get("visning_navn")
    if (not isinstance(raw, str) or not raw
            or not isinstance(record_key, str) or not record_key
            or type(target) is not int or target <= 0
            or not isinstance(side, str) or not side
            or not isinstance(display_name, str) or not display_name
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
        "target_display_name": display_name,
        "source_text": raw,
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
    # Fastlåst facitliste for fasen. Revideret 2026-08-23: R28's record-
    # beslutning blev flippet fra assign til no_publication, da personens
    # (1220, samme_som 510) rigtige narrativ allerede er publiceret fra
    # "8."-posten på side 545 (record-2c93dd69...), og R28's record er
    # oversigtsposten på side 509, som ikke skal være nogens biografi.
    if counts != {
            "cases": 5, "identity_different": 5,
            "record_assign": 4, "record_no_publication": 2}:
        fail("C3_APPLY_DECISION_SET_INVALID")
    result: Dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "input_hashes": input_hashes,
        "counts": counts,
        "cases": cases,
    }
    # Definition: SHA-256 of the canonical JSON bytes (including trailing LF)
    # before this field is inserted. The exact candidate-file SHA cannot be
    # embedded without self-reference; the CLI prints it and every downstream
    # consumer computes it from the exact raw candidate bytes.
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
    """Publish durably through one verified parent-directory descriptor."""
    temporary_name: Optional[str] = None
    ownership_descriptor: Optional[int] = None
    write_descriptor: Optional[int] = None
    parent_descriptor: Optional[int] = None
    temp_created = False
    linked = False
    temp_removed = False
    directory_synced = False
    primary_code = "C3_APPLY_OUTPUT_WRITE_FAILED"
    recovery_required = False

    def entry_info(name: str):
        try:
            return os.stat(
                name, dir_fd=parent_descriptor, follow_symlinks=False)
        except FileNotFoundError:
            return None

    def inode(info):
        return None if info is None else (info.st_dev, info.st_ino)

    def ownership_inode():
        if ownership_descriptor is None:
            raise OSError("ownership descriptor missing")
        info = os.fstat(ownership_descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise OSError("ownership inode is not regular")
        return (info.st_dev, info.st_ino)

    def recover() -> bool:
        """Return true only for a verified, durably clean rollback."""
        nonlocal write_descriptor
        clean = True
        if write_descriptor is not None:
            try:
                os.close(write_descriptor)
            except OSError:
                clean = False
            write_descriptor = None

        if linked:
            try:
                target_inode = inode(entry_info(output.name))
                if target_inode == ownership_inode():
                    os.unlink(output.name, dir_fd=parent_descriptor)
                elif target_inode is not None:
                    clean = False
            except OSError:
                clean = False

        if temp_created and temporary_name is not None and not temp_removed:
            try:
                temp_inode = inode(entry_info(temporary_name))
                if temp_inode == ownership_inode():
                    os.unlink(temporary_name, dir_fd=parent_descriptor)
                elif temp_inode is not None:
                    clean = False
            except OSError:
                clean = False

        # Every directory mutation made by this invocation, including a
        # rollback, must become durable before a clean failure can be claimed.
        if temp_created:
            try:
                os.fsync(parent_descriptor)
            except OSError:
                clean = False

        try:
            if linked and entry_info(output.name) is not None:
                clean = False
            if (temporary_name is not None
                    and entry_info(temporary_name) is not None):
                clean = False
        except OSError:
            clean = False
        return clean

    try:
        open_flags = (os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
                      | getattr(os, "O_NOFOLLOW", 0))
        parent_descriptor = os.open(str(output.parent), open_flags)
        if not stat.S_ISDIR(os.fstat(parent_descriptor).st_mode):
            fail("C3_APPLY_OUTPUT_WRITE_FAILED")

        temp_flags = (os.O_WRONLY | os.O_CREAT | os.O_EXCL
                      | getattr(os, "O_NOFOLLOW", 0))
        for _attempt in range(128):
            token = secrets.token_hex(16)
            if re.fullmatch(r"[0-9a-f]{32}", token) is None:
                continue
            candidate_name = ".c3-apply-{}.tmp".format(token)
            try:
                ownership_descriptor = os.open(
                    candidate_name, temp_flags, 0o600,
                    dir_fd=parent_descriptor)
            except FileExistsError:
                continue
            temporary_name = candidate_name
            temp_created = True
            break
        if ownership_descriptor is None or temporary_name is None:
            raise OSError("temporary name allocation exhausted")
        ownership_inode()
        os.fchmod(ownership_descriptor, 0o600)

        write_descriptor = os.dup(ownership_descriptor)
        handle = os.fdopen(write_descriptor, "w", encoding="utf-8")
        write_descriptor = None
        with handle:
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(
                temporary_name, output.name,
                src_dir_fd=parent_descriptor,
                dst_dir_fd=parent_descriptor,
                follow_symlinks=False)
        except FileExistsError:
            primary_code = "C3_APPLY_OUTPUT_EXISTS"
            raise OSError("destination exists")
        linked = True
        if inode(entry_info(output.name)) != ownership_inode():
            raise OSError("published inode mismatch")
        os.unlink(temporary_name, dir_fd=parent_descriptor)
        temp_removed = True
        os.fsync(parent_descriptor)
        directory_synced = True
        # Success is exact at this final same-dirfd inventory. An unrelated
        # actor may still mutate directory names after the check; preventing
        # arbitrary future deletion is outside a filesystem publication API.
        target_info = entry_info(output.name)
        if (target_info is None or not stat.S_ISREG(target_info.st_mode)
                or inode(target_info) != ownership_inode()
                or entry_info(temporary_name) is not None):
            recovery_required = True
            raise OSError("final publication inventory mismatch")
        if not (temp_created and linked and temp_removed and directory_synced):
            raise OSError("publication state incomplete")
    except OSError:
        if parent_descriptor is None:
            fail(primary_code)
        if not recover() or recovery_required:
            fail("C3_APPLY_OUTPUT_RECOVERY_REQUIRED")
        fail(primary_code)
    finally:
        if write_descriptor is not None:
            try:
                os.close(write_descriptor)
            except OSError:
                pass
        if ownership_descriptor is not None:
            try:
                os.close(ownership_descriptor)
            except OSError:
                pass
        if parent_descriptor is not None:
            try:
                os.close(parent_descriptor)
            except OSError:
                pass


def main(argv: Optional[List[str]] = None) -> int:
    values = _arguments(list(sys.argv[1:] if argv is None else argv))
    output = Path(values["--output"])
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
