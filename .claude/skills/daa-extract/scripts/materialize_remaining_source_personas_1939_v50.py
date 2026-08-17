#!/usr/bin/env python3
"""Append reviewed remaining identities to the DAA 1939 source-persona bundle."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
from typing import Any
import uuid


SCHEMA_VERSION = "1939-v50-source-persona-materialization-v2"
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
DECISION_ORDER = (
    "same_existing_person",
    "new_person_candidate",
    "structural_or_summary",
    "unresolved",
)
DECISIONS = frozenset(DECISION_ORDER)
PRODUCTION_V1_SHA256 = "07756ef4faf17561cf84095c5abe47919064d72ceecd3e1d9f725281ab0b172d"
PRODUCTION_DECISIONS_SHA256 = "a86b508205ca413f1c7f4af2f747b320f9f77bde7fb686dc10cf343b16565ebe"
PRODUCTION_COUNTS = {
    "same_existing_person": 8,
    "new_person_candidate": 8,
    "structural_or_summary": 1,
    "unresolved": 0,
}
EXPLICIT_USER_BASIS = (
    "explicit_user_instruction_prefer_later_full_person_over_summary_duplicate"
)


class RemainingSourcePersonaError(ValueError):
    pass


def _fail(code: str) -> None:
    raise RemainingSourcePersonaError(code)


def _text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value:
        _fail(code)
    return value


def _positive_int(value: Any, code: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        _fail(code)
    return value


def _nonnegative_int(value: Any, code: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        _fail(code)
    return value


def _sha(value: Any, code: str) -> str:
    value = _text(value, code)
    if not HASH_RE.fullmatch(value):
        _fail(code)
    return value


def _span(value: Any, code: str) -> dict[str, int]:
    if not isinstance(value, dict) or set(value) != {"char_from", "char_to"}:
        _fail(code)
    start = _nonnegative_int(value.get("char_from"), code)
    end = _nonnegative_int(value.get("char_to"), code)
    if end <= start:
        _fail(code)
    return {"char_from": start, "char_to": end}


def _artifact_digest(value: Any) -> str:
    payload = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _persona_id(logical_source_id: str, record_key: str) -> str:
    return str(uuid.uuid5(
        uuid.NAMESPACE_URL,
        f"daa:source-persona:{logical_source_id}:{record_key}",
    ))


def _validate_v1(
    value: Any,
    supplied_sha256: Any,
    expected_v1_personas: int,
    expected_decisions: int,
) -> tuple[
    str, int, list[dict[str, Any]], dict[str, dict[str, Any]], dict[str, str],
]:
    supplied_sha256 = _sha(supplied_sha256, "REMAINING_SOURCE_PERSONA_V1_HASH_INVALID")
    if _artifact_digest(value) != supplied_sha256:
        _fail("REMAINING_SOURCE_PERSONA_V1_HASH_INVALID")
    if expected_v1_personas == 24 and expected_decisions == 17:
        if supplied_sha256 != PRODUCTION_V1_SHA256:
            _fail("REMAINING_SOURCE_PERSONA_V1_HASH_INVALID")
    expected_keys = {
        "schema_version", "generator_version", "source",
        "canonical_mutations_authorized", "database_write_authorized", "counts",
        "source_personas", "remaining_genuinely_new_pending",
        "expected_database_changes", "source_persona_materialization_gate",
        "database_write_gate", "reimport_gate",
    }
    if (not isinstance(value, dict) or set(value) != expected_keys or
            value.get("schema_version") != "1939-v50-source-persona-materialization-v1" or
            value.get("generator_version") != "materialize_source_personas_1939_v50.py:v1" or
            value.get("canonical_mutations_authorized") is not False or
            value.get("database_write_authorized") is not False or
            value.get("source_persona_materialization_gate") != "GO" or
            value.get("database_write_gate") != "NO-GO" or
            value.get("reimport_gate") != "NO-GO"):
        _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
    source = value.get("source")
    if not isinstance(source, dict) or set(source) != {
        "edition", "logical_source_id", "database_source_id", "input_hashes",
    } or source.get("edition") != "1939":
        _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
    logical_source_id = _text(
        source.get("logical_source_id"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
    database_source_id = _positive_int(
        source.get("database_source_id"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
    hashes = source.get("input_hashes")
    if not isinstance(hashes, dict) or set(hashes) != {
        "database_preview_sha256", "identity_decision_sha256s", "import_preview_sha256",
    }:
        _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
    input_hashes = {
        "database_preview_sha256": _sha(
            hashes.get("database_preview_sha256"), "REMAINING_SOURCE_PERSONA_V1_INVALID"),
        "import_preview_sha256": _sha(
            hashes.get("import_preview_sha256"), "REMAINING_SOURCE_PERSONA_V1_INVALID"),
    }
    old_decision_hashes = hashes.get("identity_decision_sha256s")
    if not isinstance(old_decision_hashes, list) or not old_decision_hashes:
        _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
    for digest in old_decision_hashes:
        _sha(digest, "REMAINING_SOURCE_PERSONA_V1_INVALID")

    counts = value.get("counts")
    personas = value.get("source_personas")
    pending = value.get("remaining_genuinely_new_pending")
    if (not isinstance(counts, dict) or set(counts) != {
            "approved_identity_decisions", "source_personas", "accepted_identities",
            "remaining_genuinely_new_pending",
        } or not isinstance(personas, list) or not isinstance(pending, list) or
            len(personas) != expected_v1_personas or len(pending) != expected_decisions or
            counts != {
                "approved_identity_decisions": len(personas),
                "source_personas": len(personas),
                "accepted_identities": len(personas),
                "remaining_genuinely_new_pending": len(pending),
            }):
        _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")

    persona_keys: set[str] = set()
    persona_ids: set[str] = set()
    source_keys: set[str] = set()
    target_keys: set[str] = set()
    person_ids: set[int] = set()
    previous_source_key: str | None = None
    persona_row_keys = {
        "source_persona_id", "persona_key", "source_id", "source_record_key",
        "source_span", "verbatim_text", "target_record_key", "canonical_person_id",
        "identity_status", "identity_decision", "database_write_authorized",
    }
    identity_keys = {
        "decision_batch", "decision_batch_sha256", "candidate_evidence_sha256",
        "confirmation", "reviewed_by",
    }
    for row in personas:
        if not isinstance(row, dict) or set(row) != persona_row_keys:
            _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
        source_key = _text(
            row.get("source_record_key"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        if previous_source_key is not None and source_key <= previous_source_key:
            _fail("REMAINING_SOURCE_PERSONA_V1_ORDER_INVALID")
        previous_source_key = source_key
        persona_id = _text(
            row.get("source_persona_id"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        persona_key = _text(row.get("persona_key"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        target_key = _text(
            row.get("target_record_key"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        person_id = _positive_int(
            row.get("canonical_person_id"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        source_span = _span(row.get("source_span"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        verbatim = _text(row.get("verbatim_text"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        identity = row.get("identity_decision")
        if (persona_id != _persona_id(logical_source_id, source_key)):
            _fail("REMAINING_SOURCE_PERSONA_UUID_INVALID")
        if (persona_key != f"{logical_source_id}:{source_key}" or
                row.get("source_id") != database_source_id or
                source_span["char_to"] - source_span["char_from"] != len(verbatim) or
                row.get("identity_status") != "accepted" or
                row.get("database_write_authorized") is not False or
                not isinstance(identity, dict) or set(identity) != identity_keys):
            _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
        for field in ("decision_batch", "confirmation", "reviewed_by"):
            _text(identity.get(field), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        for field in ("decision_batch_sha256", "candidate_evidence_sha256"):
            _sha(identity.get(field), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        if (persona_id in persona_ids or persona_key in persona_keys or
                source_key in source_keys or target_key in target_keys or person_id in person_ids):
            _fail("REMAINING_SOURCE_PERSONA_INJECTIVITY_INVALID")
        persona_ids.add(persona_id)
        persona_keys.add(persona_key)
        source_keys.add(source_key)
        target_keys.add(target_key)
        person_ids.add(person_id)

    pending_by_key: dict[str, dict[str, Any]] = {}
    previous_pending_key: str | None = None
    pending_keys = {
        "new_record_key", "pending_gates", "person_creation", "source_span", "verbatim_text",
    }
    for row in pending:
        if not isinstance(row, dict) or set(row) != pending_keys:
            _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
        key = _text(row.get("new_record_key"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        span = _span(row.get("source_span"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        text = _text(row.get("verbatim_text"), "REMAINING_SOURCE_PERSONA_V1_INVALID")
        if previous_pending_key is not None and key <= previous_pending_key:
            _fail("REMAINING_SOURCE_PERSONA_V1_ORDER_INVALID")
        previous_pending_key = key
        if (key in source_keys or key in pending_by_key or
                row.get("pending_gates") != [
                    "source_persona", "identity", "interpretation_provenance"] or
                row.get("person_creation") != "forbidden" or
                span["char_to"] - span["char_from"] != len(text)):
            _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
        pending_by_key[key] = copy.deepcopy(row)

    changes = value.get("expected_database_changes")
    expected_change_keys = {
        "source_persona_candidates", "source_persona_identity_candidates",
        "canonical_person_creates", "canonical_person_updates",
        "canonical_person_deletes", "authorized",
    }
    ordered_persona_ids = [row["source_persona_id"] for row in personas]
    if (not isinstance(changes, dict) or set(changes) != expected_change_keys or
            changes.get("source_persona_candidates") != ordered_persona_ids or
            changes.get("source_persona_identity_candidates") != ordered_persona_ids or
            changes.get("canonical_person_creates") != [] or
            changes.get("canonical_person_updates") != [] or
            changes.get("canonical_person_deletes") != [] or
            changes.get("authorized") is not False):
        _fail("REMAINING_SOURCE_PERSONA_V1_INVALID")
    return (
        logical_source_id,
        database_source_id,
        copy.deepcopy(personas),
        pending_by_key,
        input_hashes,
    )


def _validate_database_preview(
    value: Any,
    supplied_sha256: Any,
    database_source_id: int,
) -> tuple[set[tuple[str, int]], set[tuple[str, int]]]:
    supplied_sha256 = _sha(
        supplied_sha256, "REMAINING_SOURCE_PERSONA_DATABASE_HASH_INVALID")
    if _artifact_digest(value) != supplied_sha256:
        _fail("REMAINING_SOURCE_PERSONA_DATABASE_HASH_INVALID")
    expected_keys = {
        "schema_version", "snapshot_at", "input_preview", "database", "source",
        "capabilities", "person_anchors", "source_records", "narratives", "facts",
        "relations", "expected_database_changes", "blockers",
        "canonical_mutations_authorized", "dry_run_gate", "reimport_gate",
    }
    if (not isinstance(value, dict) or set(value) != expected_keys or
            value.get("schema_version") != "1939-v50-database-preview-v1" or
            value.get("canonical_mutations_authorized") is not False or
            value.get("dry_run_gate") != "NO-GO" or value.get("reimport_gate") != "NO-GO" or
            not isinstance(value.get("database"), dict) or
            value["database"].get("transaction_read_only") != "on" or
            not isinstance(value.get("input_preview"), dict) or
            value["input_preview"].get("schema_version") != "1939-v50-import-preview-v1"):
        _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    source = value.get("source")
    if (not isinstance(source, dict) or source.get("id") != database_source_id or
            source.get("udgave") != "DAA 1939" or source.get("import_key") != "daa:1939"):
        _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    anchors = value.get("person_anchors")
    anchor_keys = {
        "matched", "matched_count", "database_only", "database_only_record_keys",
        "missing_count", "missing_record_keys", "collision_count", "collisions",
        "retired_present", "retired_present_count", "retired_present_record_keys",
    }
    if not isinstance(anchors, dict) or set(anchors) != anchor_keys:
        _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    matched = anchors.get("matched")
    database_only = anchors.get("database_only")
    if (not isinstance(matched, list) or not isinstance(database_only, list) or
            anchors.get("matched_count") != len(matched) or
            anchors.get("missing_count") != 0 or anchors.get("missing_record_keys") != [] or
            anchors.get("collision_count") != 0 or anchors.get("collisions") != [] or
            not isinstance(anchors.get("retired_present"), list) or
            anchors.get("retired_present_count") != len(anchors["retired_present"]) or
            not isinstance(anchors.get("retired_present_record_keys"), list)):
        _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    matched_pairs: set[tuple[str, int]] = set()
    for row in matched:
        if not isinstance(row, dict) or set(row) != {"baseline_record_key", "person_id"}:
            _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
        pair = (
            _text(row.get("baseline_record_key"), "REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID"),
            _positive_int(row.get("person_id"), "REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID"),
        )
        if pair in matched_pairs:
            _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
        matched_pairs.add(pair)
    database_pairs: set[tuple[str, int]] = set()
    observed_database_keys: list[str] = []
    database_row_keys = {
        "record_key", "person_id", "visning_navn", "staged", "source_narrative_count",
        "fact_count", "family_member_count",
    }
    for row in database_only:
        if not isinstance(row, dict) or set(row) != database_row_keys:
            _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
        key = _text(row.get("record_key"), "REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
        pair = (
            key,
            _positive_int(row.get("person_id"), "REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID"),
        )
        if pair in database_pairs:
            _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
        database_pairs.add(pair)
        observed_database_keys.append(key)
    all_pairs = matched_pairs | database_pairs
    if (anchors.get("database_only_record_keys") != observed_database_keys or
            len(all_pairs) != len(matched_pairs) + len(database_pairs) or
            len({key for key, _ in all_pairs}) != len(all_pairs) or
            len({person_id for _, person_id in all_pairs}) != len(all_pairs)):
        _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    changes = value.get("expected_database_changes")
    if (not isinstance(changes, dict) or changes.get("canonical_person_creates") != [] or
            changes.get("canonical_person_updates") != [] or
            changes.get("canonical_person_deletes") != [] or
            changes.get("authorized") is not False):
        _fail("REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    return matched_pairs, database_pairs


def _expected_counts(
    expected_decisions: int,
    supplied: Any,
) -> dict[str, int]:
    if expected_decisions == 17:
        if supplied is not None:
            _fail("REMAINING_SOURCE_PERSONA_COUNT_INVALID")
        return dict(PRODUCTION_COUNTS)
    if not isinstance(supplied, dict) or set(supplied) != DECISIONS:
        _fail("REMAINING_SOURCE_PERSONA_COUNT_INVALID")
    result: dict[str, int] = {}
    for decision in DECISION_ORDER:
        value = supplied.get(decision)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            _fail("REMAINING_SOURCE_PERSONA_COUNT_INVALID")
        result[decision] = value
    if sum(result.values()) != expected_decisions:
        _fail("REMAINING_SOURCE_PERSONA_COUNT_INVALID")
    return result


def _validate_decisions(
    value: Any,
    supplied_sha256: Any,
    pending_by_key: dict[str, dict[str, Any]],
    anchor_pairs: set[tuple[str, int]],
    database_only_pairs: set[tuple[str, int]],
    v1_input_hashes: dict[str, str],
    expected_decisions: int,
    expected_counts: dict[str, int],
) -> tuple[list[dict[str, Any]], str, str]:
    supplied_sha256 = _sha(
        supplied_sha256, "REMAINING_SOURCE_PERSONA_DECISIONS_HASH_INVALID")
    if _artifact_digest(value) != supplied_sha256:
        _fail("REMAINING_SOURCE_PERSONA_DECISIONS_HASH_INVALID")
    if expected_decisions == 17 and supplied_sha256 != PRODUCTION_DECISIONS_SHA256:
        _fail("REMAINING_SOURCE_PERSONA_DECISIONS_HASH_INVALID")
    expected_keys = {
        "schema_version", "generator_version", "input_review_sha256",
        "input_proposal_sha256", "input_import_preview_sha256",
        "input_database_preview_sha256", "reviewed_by", "decision_basis", "review_only",
        "canonical_mutations_authorized", "database_write_authorized", "counts",
        "decisions", "decision_gate", "source_persona_materialization_gate",
        "database_gate", "reimport_gate",
    }
    if (not isinstance(value, dict) or set(value) != expected_keys or
            value.get("schema_version") != "1939-v50-remaining-identity-decisions-v1" or
            value.get("generator_version") !=
            "materialize_remaining_identity_decisions_1939_v50.py:v1" or
            value.get("review_only") is not True or
            value.get("canonical_mutations_authorized") is not False or
            value.get("database_write_authorized") is not False or
            value.get("decision_gate") != "GO" or
            value.get("source_persona_materialization_gate") != "NO-GO" or
            value.get("database_gate") != "NO-GO" or value.get("reimport_gate") != "NO-GO"):
        _fail("REMAINING_SOURCE_PERSONA_DECISIONS_INVALID")
    reviewed_by = _text(
        value.get("reviewed_by"), "REMAINING_SOURCE_PERSONA_DECISIONS_INVALID")
    decision_basis = _text(
        value.get("decision_basis"), "REMAINING_SOURCE_PERSONA_DECISIONS_INVALID")
    review_sha = _sha(
        value.get("input_review_sha256"), "REMAINING_SOURCE_PERSONA_DECISIONS_INVALID")
    _sha(value.get("input_proposal_sha256"), "REMAINING_SOURCE_PERSONA_DECISIONS_INVALID")
    if (value.get("input_import_preview_sha256") != v1_input_hashes["import_preview_sha256"] or
            value.get("input_database_preview_sha256") !=
            v1_input_hashes["database_preview_sha256"]):
        _fail("REMAINING_SOURCE_PERSONA_LINEAGE_INVALID")
    rows = value.get("decisions")
    counts = value.get("counts")
    final_counts = {"decisions": expected_decisions, **expected_counts}
    if (not isinstance(rows, list) or len(rows) != expected_decisions or
            not isinstance(counts, dict) or set(counts) != {"decisions", *DECISIONS} or
            counts != final_counts or
            not all(isinstance(counts[key], int) and not isinstance(counts[key], bool)
                    for key in counts)):
        _fail("REMAINING_SOURCE_PERSONA_COUNT_INVALID")

    common_keys = {
        "source_record_key", "source_span", "verbatim_sha256", "decision", "reason",
        "review_status", "review_sha256", "proposal_evidence_sha256",
    }
    derived_counts = {decision: 0 for decision in DECISION_ORDER}
    seen_sources: set[str] = set()
    selected_targets: set[str] = set()
    selected_people: set[int] = set()
    validated: list[dict[str, Any]] = []
    for raw in rows:
        if not isinstance(raw, dict):
            _fail("REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
        decision = raw.get("decision")
        if decision not in DECISIONS:
            _fail("REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
        row_keys = set(common_keys)
        competition_keys = {
            "competing_target_record_key", "competing_canonical_person_id", "resolution_basis",
        }
        present_competition = set(raw) & competition_keys
        if decision == "same_existing_person":
            row_keys |= {"target_record_key", "canonical_person_id"}
            if present_competition:
                if present_competition != competition_keys:
                    _fail("REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
                row_keys |= competition_keys
        elif decision == "structural_or_summary":
            row_keys.add("context_owner_record_key")
        if set(raw) != row_keys:
            _fail("REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
        source_key = _text(
            raw.get("source_record_key"), "REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
        pending = pending_by_key.get(source_key)
        if pending is None or source_key in seen_sources:
            _fail("REMAINING_SOURCE_PERSONA_COVERAGE_INVALID")
        seen_sources.add(source_key)
        if (_span(raw.get("source_span"), "REMAINING_SOURCE_PERSONA_SOURCE_DRIFT") !=
                pending["source_span"] or
                _sha(raw.get("verbatim_sha256"), "REMAINING_SOURCE_PERSONA_SOURCE_DRIFT") !=
                hashlib.sha256(pending["verbatim_text"].encode("utf-8")).hexdigest() or
                _sha(raw.get("review_sha256"), "REMAINING_SOURCE_PERSONA_SOURCE_DRIFT") !=
                review_sha):
            _fail("REMAINING_SOURCE_PERSONA_SOURCE_DRIFT")
        _sha(raw.get("proposal_evidence_sha256"), "REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
        _text(raw.get("reason"), "REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
        _text(raw.get("review_status"), "REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
        if decision == "same_existing_person":
            target = _text(
                raw.get("target_record_key"), "REMAINING_SOURCE_PERSONA_TARGET_INVALID")
            person_id = _positive_int(
                raw.get("canonical_person_id"), "REMAINING_SOURCE_PERSONA_TARGET_INVALID")
            if (target, person_id) not in anchor_pairs:
                _fail("REMAINING_SOURCE_PERSONA_TARGET_INVALID")
            if target in selected_targets or person_id in selected_people:
                _fail("REMAINING_SOURCE_PERSONA_INJECTIVITY_INVALID")
            selected_targets.add(target)
            selected_people.add(person_id)
            if present_competition:
                competing = _text(
                    raw.get("competing_target_record_key"),
                    "REMAINING_SOURCE_PERSONA_COMPETITION_INVALID")
                competing_person = _positive_int(
                    raw.get("competing_canonical_person_id"),
                    "REMAINING_SOURCE_PERSONA_COMPETITION_INVALID")
                if ((competing, competing_person) not in database_only_pairs or
                        competing == target or competing_person == person_id or
                        raw.get("resolution_basis") != EXPLICIT_USER_BASIS):
                    _fail("REMAINING_SOURCE_PERSONA_COMPETITION_INVALID")
        elif decision == "structural_or_summary":
            _text(raw.get("context_owner_record_key"),
                  "REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID")
        derived_counts[decision] += 1
        validated.append(copy.deepcopy(raw))
    if set(pending_by_key) != seen_sources:
        _fail("REMAINING_SOURCE_PERSONA_COVERAGE_INVALID")
    if derived_counts != expected_counts:
        _fail("REMAINING_SOURCE_PERSONA_COUNT_INVALID")
    return validated, reviewed_by, decision_basis


def materialize_remaining_source_personas(
    *,
    source_persona_v1: dict[str, Any],
    source_persona_v1_sha256: str,
    remaining_decisions: dict[str, Any],
    remaining_decisions_sha256: str,
    database_preview: dict[str, Any],
    database_preview_sha256: str,
    expected_v1_personas: int = 24,
    expected_decisions: int = 17,
    expected_disposition_counts: dict[str, int] | None = None,
) -> dict[str, Any]:
    """Build an append-only v2 bundle without granting database authority."""
    expected_v1_personas = _positive_int(
        expected_v1_personas, "REMAINING_SOURCE_PERSONA_COUNT_INVALID")
    expected_decisions = _positive_int(
        expected_decisions, "REMAINING_SOURCE_PERSONA_COUNT_INVALID")
    disposition_counts = _expected_counts(expected_decisions, expected_disposition_counts)
    (
        logical_source_id,
        database_source_id,
        old_personas,
        pending_by_key,
        v1_input_hashes,
    ) = _validate_v1(
        source_persona_v1,
        source_persona_v1_sha256,
        expected_v1_personas,
        expected_decisions,
    )
    matched_pairs, database_only_pairs = _validate_database_preview(
        database_preview,
        database_preview_sha256,
        database_source_id,
    )
    if database_preview_sha256 != v1_input_hashes["database_preview_sha256"]:
        _fail("REMAINING_SOURCE_PERSONA_LINEAGE_INVALID")
    decision_rows, reviewed_by, decision_basis = _validate_decisions(
        remaining_decisions,
        remaining_decisions_sha256,
        pending_by_key,
        matched_pairs | database_only_pairs,
        database_only_pairs,
        v1_input_hashes,
        expected_decisions,
        disposition_counts,
    )

    persona_ids = {row["source_persona_id"] for row in old_personas}
    persona_keys = {row["persona_key"] for row in old_personas}
    source_keys = {row["source_record_key"] for row in old_personas}
    target_keys = {row["target_record_key"] for row in old_personas}
    person_ids = {row["canonical_person_id"] for row in old_personas}
    appended: list[dict[str, Any]] = []
    non_persona: dict[str, list[dict[str, Any]]] = {
        "new_person_candidate": [],
        "structural_or_summary": [],
        "unresolved": [],
    }
    for decision in decision_rows:
        source_key = decision["source_record_key"]
        pending = pending_by_key[source_key]
        if decision["decision"] != "same_existing_person":
            non_persona[decision["decision"]].append(copy.deepcopy(decision))
            continue
        target = decision["target_record_key"]
        person_id = decision["canonical_person_id"]
        persona_id = _persona_id(logical_source_id, source_key)
        persona_key = f"{logical_source_id}:{source_key}"
        if (persona_id in persona_ids or persona_key in persona_keys or
                source_key in source_keys or target in target_keys or person_id in person_ids):
            _fail("REMAINING_SOURCE_PERSONA_INJECTIVITY_INVALID")
        persona_ids.add(persona_id)
        persona_keys.add(persona_key)
        source_keys.add(source_key)
        target_keys.add(target)
        person_ids.add(person_id)
        provenance = {
            "decision": "same_existing_person",
            "decision_artifact_sha256": remaining_decisions_sha256,
            "review_sha256": decision["review_sha256"],
            "proposal_evidence_sha256": decision["proposal_evidence_sha256"],
            "reviewed_by": reviewed_by,
            "decision_basis": decision_basis,
            "reason": decision["reason"],
            "review_status": decision["review_status"],
        }
        for field in (
            "competing_target_record_key", "competing_canonical_person_id", "resolution_basis",
        ):
            if field in decision:
                provenance[field] = decision[field]
        appended.append({
            "source_persona_id": persona_id,
            "persona_key": persona_key,
            "source_id": database_source_id,
            "source_record_key": source_key,
            "source_span": copy.deepcopy(pending["source_span"]),
            "verbatim_text": pending["verbatim_text"],
            "target_record_key": target,
            "canonical_person_id": person_id,
            "identity_status": "accepted",
            "identity_decision": provenance,
            "database_write_authorized": False,
        })

    personas = [*old_personas, *appended]
    ordered_persona_ids = [row["source_persona_id"] for row in personas]
    counts = {
        "v1_source_personas": len(old_personas),
        "appended_source_personas": len(appended),
        "source_personas": len(personas),
        **disposition_counts,
    }
    return {
        "schema_version": SCHEMA_VERSION,
        "generator_version": "materialize_remaining_source_personas_1939_v50.py:v1",
        "source": {
            "edition": "1939",
            "logical_source_id": logical_source_id,
            "database_source_id": database_source_id,
            "input_hashes": {
                "source_persona_v1_sha256": source_persona_v1_sha256,
                "remaining_identity_decisions_sha256": remaining_decisions_sha256,
                "database_preview_sha256": database_preview_sha256,
            },
        },
        "review_only": True,
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": counts,
        "source_personas": personas,
        "new_person_candidates": non_persona["new_person_candidate"],
        "structural_or_summary": non_persona["structural_or_summary"],
        "unresolved": non_persona["unresolved"],
        "expected_database_changes": {
            "source_persona_candidates": ordered_persona_ids,
            "source_persona_identity_candidates": ordered_persona_ids,
            "canonical_person_creates": [],
            "canonical_person_updates": [],
            "canonical_person_deletes": [],
            "authorized": False,
        },
        "source_persona_materialization_gate": "GO",
        "database_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }


def render_markdown(result: dict[str, Any]) -> str:
    counts = result["counts"]
    hashes = result["source"]["input_hashes"]
    lines = [
        "# DAA 1939 v50 source-persona materialization v2",
        "",
        "Append-only, hashbundet og DB-fri materialisering. Ingen canonical writes er autoriseret.",
        "",
        f"- source-persona v1 SHA-256: `{hashes['source_persona_v1_sha256']}`",
        f"- remaining decisions SHA-256: `{hashes['remaining_identity_decisions_sha256']}`",
        f"- database-preview SHA-256: `{hashes['database_preview_sha256']}`",
        f"- bevarede v1-personaer: {counts['v1_source_personas']}",
        f"- tilføjede personaer: {counts['appended_source_personas']}",
        f"- source-personaer i alt: {counts['source_personas']}",
        f"- new_person_candidate: {counts['new_person_candidate']}",
        f"- structural_or_summary: {counts['structural_or_summary']}",
        f"- unresolved: {counts['unresolved']}",
        f"- database gate: **{result['database_gate']}**",
        f"- reimport gate: **{result['reimport_gate']}**",
        "",
        "## Tilføjede source-personaer",
        "",
    ]
    start = counts["v1_source_personas"]
    for index, row in enumerate(result["source_personas"][start:], 1):
        lines.append(
            f"{index}. `{row['source_record_key']}` -> `{row['target_record_key']}` "
            f"(person `{row['canonical_person_id']}`)"
        )
    lines.extend(["", "## Ikke-persona-dispositioner", ""])
    for key in ("new_person_candidates", "structural_or_summary", "unresolved"):
        for row in result[key]:
            lines.append(f"- `{row['source_record_key']}`: `{row['decision']}`")
    lines.append("")
    return "\n".join(lines)


def write_outputs(
    result: dict[str, Any], output_path: Path | str, report_path: Path | str,
) -> None:
    output = Path(output_path)
    report = Path(report_path)
    if output.resolve() == report.resolve():
        _fail("REMAINING_SOURCE_PERSONA_OUTPUT_INVALID")
    output.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    created: list[Path] = []
    try:
        with output.open("x", encoding="utf-8", newline="\n") as handle:
            created.append(output)
            json.dump(result, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        with report.open("x", encoding="utf-8", newline="\n") as handle:
            created.append(report)
            handle.write(render_markdown(result))
    except Exception:
        for path in created:
            path.unlink(missing_ok=True)
        raise


def _load(path: Path) -> tuple[bytes, Any]:
    payload = path.read_bytes()
    return payload, json.loads(payload)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-personas-v1", required=True, type=Path)
    parser.add_argument("--remaining-decisions", required=True, type=Path)
    parser.add_argument("--database-preview", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-v1-personas", type=int, default=24)
    parser.add_argument("--expected-decisions", type=int, default=17)
    args = parser.parse_args(argv)
    v1_bytes, v1 = _load(args.source_personas_v1)
    decision_bytes, decisions = _load(args.remaining_decisions)
    database_bytes, database = _load(args.database_preview)
    result = materialize_remaining_source_personas(
        source_persona_v1=v1,
        source_persona_v1_sha256=hashlib.sha256(v1_bytes).hexdigest(),
        remaining_decisions=decisions,
        remaining_decisions_sha256=hashlib.sha256(decision_bytes).hexdigest(),
        database_preview=database,
        database_preview_sha256=hashlib.sha256(database_bytes).hexdigest(),
        expected_v1_personas=args.expected_v1_personas,
        expected_decisions=args.expected_decisions,
    )
    write_outputs(result, args.output, args.report)
    print(json.dumps({
        "output": str(args.output),
        "report": str(args.report),
        "counts": result["counts"],
        "database_write_authorized": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
