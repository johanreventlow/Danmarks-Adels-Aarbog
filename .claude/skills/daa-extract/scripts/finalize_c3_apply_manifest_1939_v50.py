#!/usr/bin/env python3
"""Finalize the exact, database-bound 1939 v50 C3 apply manifest.

Pure offline JSON-to-JSON transformation. Never opens a database
connection and never mutates production. Consumes the exact raw bytes of
Task 1's candidate manifest (``build_c3_apply_candidate_1939_v50.py``) and
Task 2's DB preview (``export_c3_apply_preview_1939_v50.R``), performs its
own independent one-to-one join and drift/binding-state validation of the
preview's ``before_state`` against the candidate, and — only if every case
and every record decision is exactly, unambiguously accounted for — emits
a single finalized manifest keyed by stable case/event element IDs. Task 4
(the human approval sheet) and Task 5/6 (the private apply tables and the
apply RPC) read this manifest, not the candidate or the preview directly.

Narrative prose (``normalized_text``) may travel into the finalized output
file (git-ignored, like Task 1's and Task 2's own outputs) but must never
reach stdout/stderr — only hashes and counts are printed there.
"""

import importlib.util
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


SCRIPT_DIR = Path(__file__).resolve().parent
CANDIDATE_BUILDER_PATH = SCRIPT_DIR / "build_c3_apply_candidate_1939_v50.py"
SCHEMA_VERSION = "1939-v50-c3-apply-manifest-v1"
CANDIDATE_SCHEMA_VERSION = "1939-v50-c3-apply-candidate-v1"
PREVIEW_SCHEMA_VERSION = "1939-v50-c3-apply-db-preview-v1"
CLI_ERROR_RE = re.compile(r"^C3_APPLY_MANIFEST_[A-Z0-9_]+$")


def _import(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("missing loader")
    spec.loader.exec_module(module)
    return module


# Reuse Task 1's canonicalization/hashing/IO primitives (same pattern Task 1
# itself uses to import convert_c3_decisions_1939_v50.py and
# build_c3_review_1939_v50.py) instead of duplicating them: `_canonical_bytes`
# / `_sha` define the one canonical-JSON-hash convention this whole C3 apply
# chain hash-binds against, `_decode_document` is the one strict-JSON /
# duplicate-key-rejecting reader, `_read_regular` is the one
# symlink/non-regular-file-refusing byte reader, and `publish_output` is the
# ~150-line durable atomic no-clobber writer (temp file + link + fsync +
# verified rollback). Re-implementing any of these here would be needless,
# fragile duplication of security-relevant code; only the CLI flag surface
# (`--candidate --preview --output`, distinct from Task 1's five flags) and
# this script's own C3_APPLY_MANIFEST_* error tokens are genuinely new.
candidate_builder = _import(
    "build_c3_apply_candidate_for_finalize", CANDIDATE_BUILDER_PATH)
_canonical_bytes = candidate_builder._canonical_bytes
_sha = candidate_builder._sha
_decode_document = candidate_builder._decode_document
_read_regular = candidate_builder._read_regular
_fail = candidate_builder.fail


# ---------------------------------------------------------------------------
# Structural key contracts (mirror the exact shapes Task 1 / Task 2 produce)
# ---------------------------------------------------------------------------

_CANDIDATE_KEYS = {
    "schema_version", "input_hashes", "counts", "cases",
    "canonical_content_sha256"}
_CANDIDATE_COUNTS = {
    "cases": 5, "identity_different": 5, "record_assign": 4,
    "record_no_publication": 2}
_CASE_KEYS = {"case_id", "identity", "record_decisions"}
_IDENTITY_KEYS = {"action", "person_ids"}
_ASSIGN_KEYS = {
    "action", "rid", "record_key", "target_person_id", "raw_sha256",
    "target_display_name", "source_text",
    "normalized_text", "normalized_sha256", "normalization_version",
    "normalization_flags", "expected_narrative"}
_NO_PUBLICATION_KEYS = {"action", "rid", "record_key"}
_EXPECTED_NARRATIVE_KEYS = {"privat", "side", "record_label", "citation_label"}

_PREVIEW_KEYS = {
    "schema_version", "candidate_file_sha256",
    "candidate_canonical_content_sha256", "database", "before_state",
    "before_state_canonical", "before_state_canonical_sha256", "candidate"}
_DATABASE_KEYS = {"database_name", "system_identifier"}
_BEFORE_STATE_KEYS = {
    "database_name", "system_identifier", "identity_pairs",
    "source_records", "target_narratives", "bindings", "source_anchors",
    "identity_components"}
_IDENTITY_PAIR_KEYS = {"case_id", "person_ids", "component_overlap",
                        "existing_rejection"}
_SOURCE_RECORD_KEYS = {"rid", "record_key", "match_count",
                        "verbatim_sha256", "side"}
_TARGET_NARRATIVE_KEYS = {"rid", "person_id", "narrative_id", "privat",
                           "old_text", "old_sha256"}
_BINDING_KEYS = {"record_key", "status", "binding_person_id"}
_BINDING_STATUSES = {
    "absent", "draft_same_record", "draft_other_record", "published",
    "withdrawn"}
_ASSIGN_ALLOWED_BINDING_STATUSES = {"absent", "draft_same_record"}

_HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
_DATABASE_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
_SYSTEM_IDENTIFIER_RE = re.compile(r"^[0-9]+$")


# ---------------------------------------------------------------------------
# Small type predicates
# ---------------------------------------------------------------------------

def _hex64(value: Any) -> bool:
    return isinstance(value, str) and _HEX64_RE.match(value) is not None


def _nonempty_str(value: Any) -> bool:
    return isinstance(value, str) and value != ""


def _bool(value: Any) -> bool:
    return type(value) is bool


def _positive_int(value: Any) -> bool:
    return type(value) is int and value > 0


def _optional_positive_int(value: Any) -> bool:
    return value is None or _positive_int(value)


def _optional_hex64(value: Any) -> bool:
    return value is None or _hex64(value)


def _exact_keys(value: Any, expected: set, code: str) -> None:
    if not isinstance(value, dict) or set(value.keys()) != expected:
        _fail(code)


# ---------------------------------------------------------------------------
# Candidate validation (Task 1's exact five-case, six-record output shape)
# ---------------------------------------------------------------------------

def _validate_candidate(doc: Dict[str, Any]) -> Dict[str, Any]:
    code = "C3_APPLY_MANIFEST_CANDIDATE_INVALID"
    _exact_keys(doc, _CANDIDATE_KEYS, code)
    if doc.get("schema_version") != CANDIDATE_SCHEMA_VERSION:
        _fail(code)
    if not isinstance(doc.get("input_hashes"), dict):
        _fail(code)
    if doc.get("counts") != _CANDIDATE_COUNTS:
        _fail(code)
    if not _hex64(doc.get("canonical_content_sha256")):
        _fail(code)
    cases = doc.get("cases")
    if not isinstance(cases, list) or len(cases) != 5:
        _fail(code)

    case_ids: List[str] = []
    rids: List[str] = []
    record_keys: List[str] = []
    assign_count = 0
    no_publication_count = 0
    for case in cases:
        _exact_keys(case, _CASE_KEYS, code)
        case_id = case.get("case_id")
        if not _nonempty_str(case_id):
            _fail(code)
        case_ids.append(case_id)

        identity = case.get("identity")
        _exact_keys(identity, _IDENTITY_KEYS, code)
        if identity.get("action") != "different":
            _fail(code)
        person_ids = identity.get("person_ids")
        if (not isinstance(person_ids, list) or len(person_ids) != 2
                or not all(_positive_int(pid) for pid in person_ids)
                or person_ids[0] >= person_ids[1]):
            _fail(code)

        record_decisions = case.get("record_decisions")
        if not isinstance(record_decisions, list) or not record_decisions:
            _fail(code)
        for decision in record_decisions:
            if not isinstance(decision, dict):
                _fail(code)
            rid = decision.get("rid")
            if not _nonempty_str(rid):
                _fail(code)
            action = decision.get("action")
            if action == "assign":
                _exact_keys(decision, _ASSIGN_KEYS, code)
                record_key = decision.get("record_key")
                if (not _nonempty_str(record_key)
                        or not _positive_int(decision.get("target_person_id"))
                        or not _nonempty_str(decision.get("target_display_name"))
                        or not _nonempty_str(decision.get("source_text"))
                        or not _hex64(decision.get("raw_sha256"))
                        or not _nonempty_str(decision.get("normalized_text"))
                        or not _hex64(decision.get("normalized_sha256"))
                        or not _nonempty_str(decision.get("normalization_version"))
                        or not isinstance(decision.get("normalization_flags"), list)):
                    _fail(code)
                if (_sha(decision["source_text"].encode("utf-8"))
                        != decision["raw_sha256"]):
                    _fail(code)
                expected_narrative = decision.get("expected_narrative")
                _exact_keys(expected_narrative, _EXPECTED_NARRATIVE_KEYS, code)
                if (expected_narrative.get("privat") is not False
                        or not _nonempty_str(expected_narrative.get("side"))
                        or expected_narrative.get("record_label") != record_key
                        or expected_narrative.get("citation_label")
                        != "DAA 1939 side " + expected_narrative.get("side")):
                    _fail(code)
                record_keys.append(record_key)
                assign_count += 1
            elif action == "no_publication":
                _exact_keys(decision, _NO_PUBLICATION_KEYS, code)
                record_key = decision.get("record_key")
                if not _nonempty_str(record_key):
                    _fail(code)
                record_keys.append(record_key)
                no_publication_count += 1
            else:
                _fail(code)
            rids.append(rid)

    if len(set(case_ids)) != 5 or len(set(rids)) != 6 or len(rids) != 6:
        _fail(code)
    if len(set(record_keys)) != 6 or len(record_keys) != 6:
        _fail(code)
    if assign_count != 4 or no_publication_count != 2:
        _fail(code)

    stated_hash = doc["canonical_content_sha256"]
    unhashed = {key: value for key, value in doc.items()
                if key != "canonical_content_sha256"}
    if _sha(_canonical_bytes(unhashed)) != stated_hash:
        _fail("C3_APPLY_MANIFEST_CANDIDATE_HASH_MISMATCH")

    return doc


def _candidate_index(candidate: Dict[str, Any]) -> Dict[str, Any]:
    case_ids: List[str] = []
    case_person_ids: Dict[str, List[int]] = {}
    by_rid: Dict[str, Dict[str, Any]] = {}
    by_record_key: Dict[str, str] = {}
    for case in candidate["cases"]:
        case_id = case["case_id"]
        case_ids.append(case_id)
        case_person_ids[case_id] = list(case["identity"]["person_ids"])
        for decision in case["record_decisions"]:
            by_rid[decision["rid"]] = {"case_id": case_id, "decision": decision}
            by_record_key[decision["record_key"]] = decision["rid"]
    return {
        "case_ids": case_ids,
        "case_person_ids": case_person_ids,
        "by_rid": by_rid,
        "by_record_key": by_record_key,
        "assign_rids": {rid for rid, entry in by_rid.items()
                        if entry["decision"]["action"] == "assign"},
    }


# ---------------------------------------------------------------------------
# Preview validation (Task 2's exact db-preview envelope, byte-bound)
# ---------------------------------------------------------------------------

def _validate_preview_shape(doc: Dict[str, Any]) -> Dict[str, Any]:
    code = "C3_APPLY_MANIFEST_PREVIEW_INVALID"
    _exact_keys(doc, _PREVIEW_KEYS, code)
    if doc.get("schema_version") != PREVIEW_SCHEMA_VERSION:
        _fail("C3_APPLY_MANIFEST_PREVIEW_SCHEMA_MISMATCH")
    if not _hex64(doc.get("candidate_file_sha256")):
        _fail(code)
    if not _hex64(doc.get("candidate_canonical_content_sha256")):
        _fail(code)
    database = doc.get("database")
    _exact_keys(database, _DATABASE_KEYS, code)
    if (not _DATABASE_NAME_RE.match(database.get("database_name") or "")
            or not _SYSTEM_IDENTIFIER_RE.match(
                database.get("system_identifier") or "")):
        _fail("C3_APPLY_MANIFEST_DATABASE_INVALID")
    if not _hex64(doc.get("before_state_canonical_sha256")):
        _fail(code)
    if not isinstance(doc.get("before_state_canonical"), str):
        _fail(code)
    before_state = doc.get("before_state")
    _exact_keys(before_state, _BEFORE_STATE_KEYS, code)
    if not isinstance(doc.get("candidate"), dict):
        _fail(code)
    return doc


def _cross_check_linkage(
        candidate: Dict[str, Any], preview: Dict[str, Any],
        candidate_raw: bytes) -> None:
    if preview["candidate_file_sha256"] != _sha(candidate_raw):
        _fail("C3_APPLY_MANIFEST_CANDIDATE_FILE_HASH_MISMATCH")
    if (preview["candidate_canonical_content_sha256"]
            != candidate["canonical_content_sha256"]):
        _fail("C3_APPLY_MANIFEST_CANDIDATE_CANONICAL_HASH_MISMATCH")
    if _canonical_bytes(preview["candidate"]) != _canonical_bytes(candidate):
        _fail("C3_APPLY_MANIFEST_CANDIDATE_EMBED_MISMATCH")

    before_state_canonical = preview["before_state_canonical"]
    if _sha(before_state_canonical.encode("utf-8")) != preview[
            "before_state_canonical_sha256"]:
        _fail("C3_APPLY_MANIFEST_BEFORE_STATE_HASH_MISMATCH")
    # before_state_canonical is a *string value* embedded inside the
    # already-strict-JSON-decoded preview document, so its own contents
    # never passed through _decode_document's guards (duplicate keys,
    # non-finite constants, invalid UTF-8). Route it through the same
    # reader used for every other document in this script, rather than a
    # bare json.loads, so a malformed embedded RPC answer fails closed with
    # an in-namespace C3_APPLY_MANIFEST_* token instead of a stray
    # non-finite-constant ValueError or a silently last-wins duplicate key.
    reparsed = _decode_document(
        before_state_canonical.encode("utf-8"), "C3_APPLY_MANIFEST_PREVIEW_INVALID")
    if _canonical_bytes(reparsed) != _canonical_bytes(preview["before_state"]):
        _fail("C3_APPLY_MANIFEST_BEFORE_STATE_CANONICAL_MISMATCH")

    database = preview["database"]
    before_state = preview["before_state"]
    if (before_state["database_name"] != database["database_name"]
            or before_state["system_identifier"]
            != database["system_identifier"]):
        _fail("C3_APPLY_MANIFEST_DATABASE_MISMATCH")


# ---------------------------------------------------------------------------
# One-to-one join + drift/binding-state validation of before_state
# ---------------------------------------------------------------------------

def _validate_identity_pairs(
        before_state: Dict[str, Any], index: Dict[str, Any]
        ) -> Dict[str, Dict[str, Any]]:
    identity_pairs = before_state["identity_pairs"]
    if not isinstance(identity_pairs, list) or len(identity_pairs) != 5:
        _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
    case_id_to_person_ids = index["case_person_ids"]
    seen: List[str] = []
    result: Dict[str, Dict[str, Any]] = {}
    for pair in identity_pairs:
        _exact_keys(pair, _IDENTITY_PAIR_KEYS, "C3_APPLY_MANIFEST_PREVIEW_INVALID")
        case_id = pair["case_id"]
        if (not _nonempty_str(case_id) or case_id not in index["case_ids"]
                or case_id in seen):
            _fail("C3_APPLY_MANIFEST_CASE_JOIN_MISMATCH")
        seen.append(case_id)
        person_ids = pair["person_ids"]
        if (not isinstance(person_ids, list) or len(person_ids) != 2
                or not all(type(pid) is int for pid in person_ids)):
            _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
        if person_ids != case_id_to_person_ids[case_id]:
            _fail("C3_APPLY_MANIFEST_IDENTITY_PAIR_MISMATCH")
        if not _bool(pair["component_overlap"]):
            _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
        if pair["component_overlap"] is not False:
            _fail("C3_APPLY_MANIFEST_COMPONENT_OVERLAP")
        if not _bool(pair["existing_rejection"]):
            _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
        if pair["existing_rejection"] is not False:
            _fail("C3_APPLY_MANIFEST_REJECTION_FINGERPRINT_MISMATCH")
        result[case_id] = pair
    if set(seen) != set(index["case_ids"]):
        _fail("C3_APPLY_MANIFEST_CASE_JOIN_MISMATCH")
    return result


def _validate_source_records(
        before_state: Dict[str, Any], index: Dict[str, Any]
        ) -> Dict[str, Dict[str, Any]]:
    source_records = before_state["source_records"]
    if not isinstance(source_records, list) or len(source_records) != 6:
        _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
    known_rids = set(index["by_rid"])
    seen: List[str] = []
    result: Dict[str, Dict[str, Any]] = {}
    for row in source_records:
        _exact_keys(row, _SOURCE_RECORD_KEYS, "C3_APPLY_MANIFEST_PREVIEW_INVALID")
        rid = row["rid"]
        if not _nonempty_str(rid) or rid not in known_rids or rid in seen:
            _fail("C3_APPLY_MANIFEST_RECORD_JOIN_MISMATCH")
        seen.append(rid)
        decision = index["by_rid"][rid]["decision"]
        if (not _nonempty_str(row["record_key"])
                or not (isinstance(row["match_count"], int)
                        and type(row["match_count"]) is not bool)
                or not _hex64(row["verbatim_sha256"])
                or not _nonempty_str(row["side"])):
            _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
        if row["record_key"] != decision["record_key"]:
            _fail("C3_APPLY_MANIFEST_SOURCE_ANCHOR_MISMATCH")
        if row["match_count"] != 1:
            _fail("C3_APPLY_MANIFEST_MATCH_COUNT_INVALID")
        if decision["action"] == "assign":
            if row["verbatim_sha256"] != decision["raw_sha256"]:
                _fail("C3_APPLY_MANIFEST_HASH_DRIFT")
            if row["side"] != decision["expected_narrative"]["side"]:
                _fail("C3_APPLY_MANIFEST_SIDE_DRIFT")
        result[rid] = row
    if set(seen) != known_rids:
        _fail("C3_APPLY_MANIFEST_RECORD_JOIN_MISMATCH")
    return result


def _validate_target_narratives(
        before_state: Dict[str, Any], index: Dict[str, Any]
        ) -> Dict[str, Dict[str, Any]]:
    target_narratives = before_state["target_narratives"]
    assign_rids = index["assign_rids"]
    if (not isinstance(target_narratives, list)
            or len(target_narratives) != len(assign_rids)):
        _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
    seen: List[str] = []
    result: Dict[str, Dict[str, Any]] = {}
    for row in target_narratives:
        _exact_keys(row, _TARGET_NARRATIVE_KEYS, "C3_APPLY_MANIFEST_PREVIEW_INVALID")
        rid = row["rid"]
        if not _nonempty_str(rid) or rid not in assign_rids or rid in seen:
            _fail("C3_APPLY_MANIFEST_TARGET_JOIN_MISMATCH")
        seen.append(rid)
        decision = index["by_rid"][rid]["decision"]
        if (not (isinstance(row["person_id"], int)
                 and type(row["person_id"]) is not bool)
                or not _bool(row["privat"])
                or not _optional_positive_int(row["narrative_id"])
                or not _optional_hex64(row["old_sha256"])):
            _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
        old_text = row["old_text"]
        if row["narrative_id"] is None:
            if old_text is not None or row["old_sha256"] is not None:
                _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
        elif (not _nonempty_str(old_text)
              or row["old_sha256"] is None
              or _sha(old_text.encode("utf-8")) != row["old_sha256"]):
            _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
        if row["person_id"] != decision["target_person_id"]:
            _fail("C3_APPLY_MANIFEST_TARGET_PERSON_MISMATCH")
        if row["privat"] is not False:
            _fail("C3_APPLY_MANIFEST_PRIVATE_DRIFT")
        result[rid] = row
    if set(seen) != assign_rids:
        _fail("C3_APPLY_MANIFEST_TARGET_JOIN_MISMATCH")
    return result


def _validate_bindings(
        before_state: Dict[str, Any], index: Dict[str, Any]
        ) -> Dict[str, Dict[str, Any]]:
    bindings = before_state["bindings"]
    known_record_keys = set(index["by_record_key"])
    if not isinstance(bindings, list) or len(bindings) != len(known_record_keys):
        _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
    seen: List[str] = []
    result: Dict[str, Dict[str, Any]] = {}
    for row in bindings:
        _exact_keys(row, _BINDING_KEYS, "C3_APPLY_MANIFEST_PREVIEW_INVALID")
        record_key = row["record_key"]
        if (not _nonempty_str(record_key)
                or record_key not in known_record_keys
                or record_key in seen):
            _fail("C3_APPLY_MANIFEST_BINDING_JOIN_MISMATCH")
        seen.append(record_key)
        if (not _nonempty_str(row["status"])
                or not _optional_positive_int(row["binding_person_id"])):
            _fail("C3_APPLY_MANIFEST_PREVIEW_INVALID")
        if row["status"] not in _BINDING_STATUSES:
            _fail("C3_APPLY_MANIFEST_NONCANONICAL_LABEL")
        if (row["status"] == "absent"
                and row["binding_person_id"] is not None):
            _fail("C3_APPLY_MANIFEST_BINDING_INVALID")
        rid = index["by_record_key"][record_key]
        decision = index["by_rid"][rid]["decision"]
        if decision["action"] == "assign":
            if row["status"] not in _ASSIGN_ALLOWED_BINDING_STATUSES:
                _fail("C3_APPLY_MANIFEST_BINDING_INVALID")
            if (row["status"] == "draft_same_record"
                    and row["binding_person_id"] != decision["target_person_id"]):
                _fail("C3_APPLY_MANIFEST_BINDING_INVALID")
        else:
            # Deliberately stricter than Task 2's own R validator (which
            # forbids only "published" for a no_publication record, letting
            # draft_same_record/draft_other_record/withdrawn pass through
            # to the preview surface as informational). This finalizer is
            # the last offline gate before a manifest is allowed to
            # authorize a real write (Task 5/6): any non-"absent" binding
            # means *something* already touched this record_key, and a
            # no_publication decision must apply to a record nobody has
            # touched at all.
            if row["status"] != "absent":
                _fail("C3_APPLY_MANIFEST_BINDING_ACTIVE_FOR_NO_PUBLICATION")
        result[record_key] = row
    if set(seen) != known_record_keys:
        _fail("C3_APPLY_MANIFEST_BINDING_JOIN_MISMATCH")
    return result


# ---------------------------------------------------------------------------
# Manifest assembly
# ---------------------------------------------------------------------------

def finalize_manifest(candidate_raw: bytes, preview_raw: bytes) -> Dict[str, Any]:
    """Join Task 1's candidate and Task 2's DB preview into one manifest.

    Raises SystemExit(<C3_APPLY_MANIFEST_* token>) on any structural
    mismatch, drift, or binding-state violation. Returns the finalized
    manifest dict on success.
    """
    candidate_doc = _validate_candidate(
        _decode_document(candidate_raw, "C3_APPLY_MANIFEST_CANDIDATE_INVALID"))
    preview_doc = _validate_preview_shape(
        _decode_document(preview_raw, "C3_APPLY_MANIFEST_PREVIEW_INVALID"))
    _cross_check_linkage(candidate_doc, preview_doc, candidate_raw)

    index = _candidate_index(candidate_doc)
    before_state = preview_doc["before_state"]
    identity_by_case = _validate_identity_pairs(before_state, index)
    source_by_rid = _validate_source_records(before_state, index)
    target_by_rid = _validate_target_narratives(before_state, index)
    binding_by_record_key = _validate_bindings(before_state, index)
    if not isinstance(before_state["source_anchors"], list):
        _fail("C3_APPLY_MANIFEST_SOURCE_ANCHORS_INVALID")
    if not isinstance(before_state["identity_components"], list):
        _fail("C3_APPLY_MANIFEST_IDENTITY_COMPONENTS_INVALID")

    cases_out: List[Dict[str, Any]] = []
    for case in candidate_doc["cases"]:
        case_id = case["case_id"]
        case_element_id = "case:" + case_id
        pair = identity_by_case[case_id]

        events_out: List[Dict[str, Any]] = []
        for decision in case["record_decisions"]:
            rid = decision["rid"]
            event_element_id = case_element_id + ":rid:" + rid
            source = source_by_rid[rid]
            binding = binding_by_record_key[decision["record_key"]]
            event_before_state: Dict[str, Any] = {
                "source_record": {
                    "match_count": source["match_count"],
                    "verbatim_sha256": source["verbatim_sha256"],
                    "side": source["side"],
                },
                "binding": {
                    "status": binding["status"],
                    "binding_person_id": binding["binding_person_id"],
                },
            }
            if decision["action"] == "assign":
                target = target_by_rid[rid]
                event_before_state["target_narrative"] = {
                    "person_id": target["person_id"],
                    "narrative_id": target["narrative_id"],
                    "privat": target["privat"],
                    "old_sha256": target["old_sha256"],
                }
                after_state = {
                    "target_person_id": decision["target_person_id"],
                    "target_display_name": decision["target_display_name"],
                    "source_text": decision["source_text"],
                    "raw_sha256": decision["raw_sha256"],
                    "normalized_text": decision["normalized_text"],
                    "normalized_sha256": decision["normalized_sha256"],
                    "normalization_version": decision["normalization_version"],
                    "normalization_flags": decision["normalization_flags"],
                    "expected_narrative": decision["expected_narrative"],
                }
            else:
                after_state = {}
            events_out.append({
                "element_id": event_element_id,
                "rid": rid,
                "record_key": decision["record_key"],
                "action": decision["action"],
                "after_state": after_state,
                "before_state": event_before_state,
            })

        cases_out.append({
            "element_id": case_element_id,
            "case_id": case_id,
            "after_state": {
                "action": "different",
                "person_ids": list(case["identity"]["person_ids"]),
            },
            "before_state": {
                "component_overlap": pair["component_overlap"],
                "existing_rejection": pair["existing_rejection"],
            },
            "events": events_out,
        })

    identity_events = len(cases_out)
    assign_events = sum(
        1 for case in cases_out for event in case["events"]
        if event["action"] == "assign")
    no_publication_events = sum(
        1 for case in cases_out for event in case["events"]
        if event["action"] == "no_publication")
    # "events" counts every logical decision this manifest carries: one
    # identity-different resolution per case, plus one record decision
    # (assign or no_publication) per record. 5 + 5 + 1 = 11, matching the
    # brief's exact assertion — NOT merely the record-level decision count
    # (6), which double-undercounts by omitting the identity layer.
    counts = {
        "cases": len(cases_out),
        "identity_events": identity_events,
        "assign_events": assign_events,
        "no_publication_events": no_publication_events,
        "events": identity_events + assign_events + no_publication_events,
    }
    if counts != {
            "cases": 5, "identity_events": 5, "assign_events": 4,
            "no_publication_events": 2, "events": 11}:
        _fail("C3_APPLY_MANIFEST_COUNTS_INVALID")

    result: Dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "input_hashes": {
            "candidate_raw_sha256": _sha(candidate_raw),
            "preview_raw_sha256": _sha(preview_raw),
            "candidate_canonical_content_sha256":
                candidate_doc["canonical_content_sha256"],
            "before_state_canonical_sha256":
                preview_doc["before_state_canonical_sha256"],
        },
        "database": dict(preview_doc["database"]),
        "counts": counts,
        "cases": cases_out,
    }
    result["canonical_content_sha256"] = _sha(_canonical_bytes(result))
    return result


# ---------------------------------------------------------------------------
# CLI: exact `--candidate --preview --output`, atomic no-clobber publish
# ---------------------------------------------------------------------------

def _arguments(argv: List[str]) -> Dict[str, str]:
    allowed = {"--candidate", "--preview", "--output"}
    values: Dict[str, str] = {}
    position = 0
    while position < len(argv):
        option = argv[position]
        if (option not in allowed or option in values
                or position + 1 >= len(argv)
                or argv[position + 1].startswith("--")):
            _fail("C3_APPLY_MANIFEST_ARGUMENTS_INVALID")
        values[option] = argv[position + 1]
        position += 2
    if set(values) != allowed:
        _fail("C3_APPLY_MANIFEST_ARGUMENTS_INVALID")
    return values


_PUBLISH_TOKEN_MAP = {
    "C3_APPLY_OUTPUT_EXISTS": "C3_APPLY_MANIFEST_OUTPUT_EXISTS",
    "C3_APPLY_OUTPUT_WRITE_FAILED": "C3_APPLY_MANIFEST_OUTPUT_WRITE_FAILED",
    "C3_APPLY_OUTPUT_RECOVERY_REQUIRED":
        "C3_APPLY_MANIFEST_OUTPUT_RECOVERY_REQUIRED",
}


def publish_output(output: Path, rendered: str) -> None:
    """Publish durably via Task 1's atomic writer, under this script's own
    C3_APPLY_MANIFEST_* token namespace (the underlying implementation
    raises its own C3_APPLY_OUTPUT_* tokens; those are remapped here so
    every token this CLI can ever emit matches CLI_ERROR_RE)."""
    try:
        candidate_builder.publish_output(output, rendered)
    except SystemExit as error:
        token = str(error)
        _fail(_PUBLISH_TOKEN_MAP.get(token, "C3_APPLY_MANIFEST_OUTPUT_WRITE_FAILED"))


def main(argv: Optional[List[str]] = None) -> int:
    values = _arguments(list(sys.argv[1:] if argv is None else argv))
    output = Path(values["--output"])
    candidate_raw = _read_regular(
        values["--candidate"], "C3_APPLY_MANIFEST_CANDIDATE_INVALID")
    preview_raw = _read_regular(
        values["--preview"], "C3_APPLY_MANIFEST_PREVIEW_INVALID")
    result = finalize_manifest(candidate_raw, preview_raw)
    rendered = _canonical_bytes(result).decode("utf-8")
    publish_output(output, rendered)
    output_sha = _sha(rendered.encode("utf-8"))
    counts = result["counts"]
    print(
        "schema={} cases={} identity_events={} assign_events={} "
        "no_publication_events={} events={} output={} sha256={}".format(
            result["schema_version"], counts["cases"],
            counts["identity_events"], counts["assign_events"],
            counts["no_publication_events"], counts["events"],
            output.name, output_sha))
    return 0


def _cli_status() -> int:
    try:
        return main()
    except SystemExit as error:
        token = str(error)
        if CLI_ERROR_RE.fullmatch(token) is None:
            token = "C3_APPLY_MANIFEST_INTERNAL_ERROR"
        print(token, file=sys.stderr)
        return 1
    except Exception:
        print("C3_APPLY_MANIFEST_INTERNAL_ERROR", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(_cli_status())
