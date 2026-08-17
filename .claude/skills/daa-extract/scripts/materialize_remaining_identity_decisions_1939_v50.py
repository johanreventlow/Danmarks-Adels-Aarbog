#!/usr/bin/env python3
"""Materialize closed, review-only decisions for remaining DAA 1939 identities."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1939-v50-remaining-identity-decisions-v1"
EXPLICIT_USER_BASIS = (
    "explicit_user_instruction_prefer_later_full_person_over_summary_duplicate"
)
EXPLICIT_USER_REASON = "user_directed_prefer_later_full_person_over_summary_duplicate"
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
DECISION_ORDER = (
    "same_existing_person",
    "new_person_candidate",
    "structural_or_summary",
    "unresolved",
)
DECISIONS = frozenset(DECISION_ORDER)


class RemainingIdentityDecisionError(ValueError):
    pass


def _fail(code: str) -> None:
    raise RemainingIdentityDecisionError(code)


def _text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value:
        _fail(code)
    return value


def _sha(value: Any, code: str) -> str:
    value = _text(value, code)
    if not HASH_RE.fullmatch(value):
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


def _canonical_digest(value: Any) -> str:
    payload = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _span(value: Any, code: str) -> dict[str, int]:
    if not isinstance(value, dict) or set(value) != {"char_from", "char_to"}:
        _fail(code)
    start = _nonnegative_int(value.get("char_from"), code)
    end = _nonnegative_int(value.get("char_to"), code)
    if end <= start:
        _fail(code)
    return {"char_from": start, "char_to": end}


def _validate_review(review: Any, expected_decisions: int) -> tuple[
        list[dict[str, Any]], dict[str, str]]:
    expected_keys = {
        "schema_version", "generator_version", "input_hashes", "review_only",
        "review_state", "canonical_mutations_authorized", "database_write_authorized",
        "counts", "subjects", "review_gate", "identity_decision_gate",
        "database_gate", "reimport_gate",
    }
    if (not isinstance(review, dict) or set(review) != expected_keys or
            review.get("schema_version") != "1939-v50-remaining-identity-review-v1" or
            review.get("review_only") is not True or review.get("review_state") != "pending" or
            review.get("canonical_mutations_authorized") is not False or
            review.get("database_write_authorized") is not False or
            review.get("review_gate") != "GO" or
            review.get("identity_decision_gate") != "NO-GO" or
            review.get("database_gate") != "NO-GO" or
            review.get("reimport_gate") != "NO-GO"):
        _fail("REMAINING_DECISION_REVIEW_INVALID")
    _text(review.get("generator_version"), "REMAINING_DECISION_REVIEW_INVALID")
    input_hashes = review.get("input_hashes")
    expected_hashes = {
        "boundary_materialization_sha256", "calamari_sha256", "clean_sha256",
        "database_only_profiles_sha256", "database_preview_sha256",
        "import_preview_sha256", "source_persona_sha256",
    }
    if not isinstance(input_hashes, dict) or set(input_hashes) != expected_hashes:
        _fail("REMAINING_DECISION_REVIEW_INVALID")
    hashes = {
        key: _sha(input_hashes[key], "REMAINING_DECISION_REVIEW_INVALID")
        for key in sorted(expected_hashes)
    }
    counts = review.get("counts")
    count_keys = {
        "subjects", "mapped_profiles", "database_only_profiles", "profiles",
        "candidate_links", "presentation_only",
    }
    subjects = review.get("subjects")
    if (not isinstance(counts, dict) or set(counts) != count_keys or
            not all(isinstance(counts[key], int) and not isinstance(counts[key], bool) and
                    counts[key] >= 0 for key in count_keys) or
            counts["subjects"] != expected_decisions or
            counts["profiles"] != counts["mapped_profiles"] + counts["database_only_profiles"] or
            not isinstance(subjects, list) or len(subjects) != expected_decisions):
        _fail("REMAINING_DECISION_REVIEW_INVALID")

    subject_keys = {
        "new_record_key", "source_span", "verbatim_text", "previous_record",
        "next_record", "page_evidence", "later_occurrences", "candidates",
        "presentation_candidates", "review_state",
    }
    profile_keys = {
        "candidate_record_key", "candidate_person_id", "candidate_display_name",
        "classification", "proposed_action", "signals",
    }
    signal_keys = {"kind", "text", "authoritative", "source_start", "source_end"}
    rows: list[dict[str, Any]] = []
    seen_keys: set[str] = set()
    seen_spans: set[tuple[int, int]] = set()
    candidate_links = 0
    presentation_links = 0
    previous_start = -1
    for raw in subjects:
        if not isinstance(raw, dict) or set(raw) != subject_keys or raw.get("review_state") != "pending":
            _fail("REMAINING_DECISION_REVIEW_INVALID")
        key = _text(raw.get("new_record_key"), "REMAINING_DECISION_REVIEW_INVALID")
        source = _text(raw.get("verbatim_text"), "REMAINING_DECISION_REVIEW_INVALID")
        source_span = _span(raw.get("source_span"), "REMAINING_DECISION_REVIEW_INVALID")
        span_pair = (source_span["char_from"], source_span["char_to"])
        if (span_pair[1] - span_pair[0] != len(source) or key in seen_keys or
                span_pair in seen_spans or span_pair[0] <= previous_start):
            _fail("REMAINING_DECISION_REVIEW_INVALID")
        previous_start = span_pair[0]
        seen_keys.add(key)
        seen_spans.add(span_pair)
        page = raw.get("page_evidence")
        if (not isinstance(page, dict) or set(page) != {"page_from", "page_to"} or
                _positive_int(page.get("page_from"), "REMAINING_DECISION_REVIEW_INVALID") >
                _positive_int(page.get("page_to"), "REMAINING_DECISION_REVIEW_INVALID")):
            _fail("REMAINING_DECISION_REVIEW_INVALID")
        for neighbor in (raw.get("previous_record"), raw.get("next_record")):
            if neighbor is not None:
                if not isinstance(neighbor, dict) or set(neighbor) != {"new_record_key", "source_span"}:
                    _fail("REMAINING_DECISION_REVIEW_INVALID")
                _text(neighbor.get("new_record_key"), "REMAINING_DECISION_REVIEW_INVALID")
                _span(neighbor.get("source_span"), "REMAINING_DECISION_REVIEW_INVALID")
        for field, classification in (
                ("candidates", "review_candidate"),
                ("presentation_candidates", "presentation_only")):
            profiles = raw.get(field)
            if not isinstance(profiles, list):
                _fail("REMAINING_DECISION_REVIEW_INVALID")
            for profile in profiles:
                if not isinstance(profile, dict) or set(profile) != profile_keys:
                    _fail("REMAINING_DECISION_REVIEW_INVALID")
                _text(profile.get("candidate_record_key"), "REMAINING_DECISION_REVIEW_INVALID")
                _positive_int(profile.get("candidate_person_id"), "REMAINING_DECISION_REVIEW_INVALID")
                _text(profile.get("candidate_display_name"), "REMAINING_DECISION_REVIEW_INVALID")
                if (profile.get("classification") != classification or
                        profile.get("proposed_action") != "unresolved" or
                        not isinstance(profile.get("signals"), list) or not profile["signals"]):
                    _fail("REMAINING_DECISION_REVIEW_INVALID")
                for signal in profile["signals"]:
                    if not isinstance(signal, dict) or set(signal) != signal_keys:
                        _fail("REMAINING_DECISION_REVIEW_INVALID")
                    start = _nonnegative_int(signal.get("source_start"), "REMAINING_DECISION_REVIEW_INVALID")
                    end = _nonnegative_int(signal.get("source_end"), "REMAINING_DECISION_REVIEW_INVALID")
                    text = _text(signal.get("text"), "REMAINING_DECISION_REVIEW_INVALID")
                    if (signal.get("kind") not in {"literal_name", "literal_fact_value", "normalized_name"} or
                            not isinstance(signal.get("authoritative"), bool) or end <= start or
                            end > len(source) or source[start:end] != text):
                        _fail("REMAINING_DECISION_REVIEW_INVALID")
            if field == "candidates":
                candidate_links += len(profiles)
            else:
                presentation_links += len(profiles)
        occurrences = raw.get("later_occurrences")
        if not isinstance(occurrences, list):
            _fail("REMAINING_DECISION_REVIEW_INVALID")
        for occurrence in occurrences:
            if not isinstance(occurrence, dict) or set(occurrence) != {"record_key", "source_span", "signal"}:
                _fail("REMAINING_DECISION_REVIEW_INVALID")
            _text(occurrence.get("record_key"), "REMAINING_DECISION_REVIEW_INVALID")
            _span(occurrence.get("source_span"), "REMAINING_DECISION_REVIEW_INVALID")
            signal = occurrence.get("signal")
            if (not isinstance(signal, dict) or set(signal) != {"kind", "text", "authoritative"} or
                    not isinstance(signal.get("authoritative"), bool)):
                _fail("REMAINING_DECISION_REVIEW_INVALID")
            _text(signal.get("kind"), "REMAINING_DECISION_REVIEW_INVALID")
            _text(signal.get("text"), "REMAINING_DECISION_REVIEW_INVALID")
        rows.append({"new_record_key": key, "source_span": source_span,
                     "verbatim_text": source})
    if counts["candidate_links"] != candidate_links or counts["presentation_only"] != presentation_links:
        _fail("REMAINING_DECISION_REVIEW_INVALID")
    return rows, hashes


def _validate_import_preview(value: Any) -> dict[str, dict[str, Any]]:
    expected_keys = {
        "schema_version", "generator_version", "source", "counts", "source_records",
        "genuinely_new_pending", "mapped_existing", "retired_legacy", "source_only_records",
        "expected_database_changes", "reimport_blockers", "canonical_mutations_authorized",
        "preview_gate", "reimport_gate",
    }
    if (not isinstance(value, dict) or set(value) != expected_keys or
            value.get("schema_version") != "1939-v50-import-preview-v1" or
            value.get("canonical_mutations_authorized") is not False or
            value.get("preview_gate") != "GO" or value.get("reimport_gate") != "NO-GO"):
        _fail("REMAINING_DECISION_IMPORT_PREVIEW_INVALID")
    records = value.get("source_records")
    counts = value.get("counts")
    if (not isinstance(records, list) or not isinstance(counts, dict) or
            counts.get("source_records") != len(records)):
        _fail("REMAINING_DECISION_IMPORT_PREVIEW_INVALID")
    expected_row_keys = {
        "acceptance_id", "baseline_record_keys", "disposition", "new_record_key",
        "person_creation", "record_kind", "source_span", "verbatim_text",
    }
    by_key: dict[str, dict[str, Any]] = {}
    for raw in records:
        if not isinstance(raw, dict) or set(raw) != expected_row_keys:
            _fail("REMAINING_DECISION_IMPORT_PREVIEW_INVALID")
        key = _text(raw.get("new_record_key"), "REMAINING_DECISION_IMPORT_PREVIEW_INVALID")
        source = _text(raw.get("verbatim_text"), "REMAINING_DECISION_IMPORT_PREVIEW_INVALID")
        source_span = _span(raw.get("source_span"), "REMAINING_DECISION_IMPORT_PREVIEW_INVALID")
        if key in by_key or source_span["char_to"] - source_span["char_from"] != len(source):
            _fail("REMAINING_DECISION_IMPORT_PREVIEW_INVALID")
        by_key[key] = raw
    return by_key


def _validate_database_preview(value: Any) -> tuple[set[tuple[str, int]], set[tuple[str, int]]]:
    expected_keys = {
        "schema_version", "source", "snapshot_at", "input_preview", "database",
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
        _fail("REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
    anchors = value.get("person_anchors")
    anchor_keys = {
        "matched", "matched_count", "database_only", "database_only_record_keys",
        "missing_count", "missing_record_keys", "collision_count", "collisions",
        "retired_present", "retired_present_count", "retired_present_record_keys",
    }
    if not isinstance(anchors, dict) or set(anchors) != anchor_keys:
        _fail("REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
    matched = anchors.get("matched")
    database_only = anchors.get("database_only")
    if (not isinstance(matched, list) or not isinstance(database_only, list) or
            anchors.get("matched_count") != len(matched) or
            anchors.get("missing_count") != 0 or anchors.get("missing_record_keys") != [] or
            anchors.get("collision_count") != 0 or anchors.get("collisions") != [] or
            not isinstance(anchors.get("retired_present"), list) or
            anchors.get("retired_present_count") != len(anchors["retired_present"]) or
            not isinstance(anchors.get("retired_present_record_keys"), list)):
        _fail("REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
    matched_pairs: set[tuple[str, int]] = set()
    for row in matched:
        if not isinstance(row, dict) or set(row) != {"baseline_record_key", "person_id"}:
            _fail("REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
        pair = (_text(row.get("baseline_record_key"), "REMAINING_DECISION_DATABASE_PREVIEW_INVALID"),
                _positive_int(row.get("person_id"), "REMAINING_DECISION_DATABASE_PREVIEW_INVALID"))
        if pair in matched_pairs:
            _fail("REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
        matched_pairs.add(pair)
    database_pairs: set[tuple[str, int]] = set()
    database_keys = []
    db_row_keys = {
        "record_key", "person_id", "visning_navn", "staged", "source_narrative_count",
        "fact_count", "family_member_count",
    }
    for row in database_only:
        if not isinstance(row, dict) or set(row) != db_row_keys:
            _fail("REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
        key = _text(row.get("record_key"), "REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
        pair = (key, _positive_int(row.get("person_id"), "REMAINING_DECISION_DATABASE_PREVIEW_INVALID"))
        if pair in database_pairs:
            _fail("REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
        database_pairs.add(pair)
        database_keys.append(key)
    all_pairs = matched_pairs | database_pairs
    if (len(all_pairs) != len(matched_pairs) + len(database_pairs) or
            len({key for key, _ in all_pairs}) != len(all_pairs) or
            len({person_id for _, person_id in all_pairs}) != len(all_pairs) or
            anchors.get("database_only_record_keys") != database_keys):
        _fail("REMAINING_DECISION_DATABASE_PREVIEW_INVALID")
    return matched_pairs, database_pairs


def materialize_remaining_decisions(
    *, review: dict[str, Any], proposal: dict[str, Any], review_sha256: str,
    import_preview: dict[str, Any], import_preview_sha256: str,
    database_preview: dict[str, Any], database_preview_sha256: str,
    expected_decisions: int = 17, proposal_sha256: str | None = None,
) -> dict[str, Any]:
    expected_decisions = _positive_int(expected_decisions, "REMAINING_DECISION_COUNT_INVALID")
    review_sha256 = _sha(review_sha256, "REMAINING_DECISION_REVIEW_HASH_INVALID")
    import_preview_sha256 = _sha(import_preview_sha256, "REMAINING_DECISION_PREVIEW_HASH_INVALID")
    database_preview_sha256 = _sha(database_preview_sha256, "REMAINING_DECISION_PREVIEW_HASH_INVALID")
    subjects, input_hashes = _validate_review(review, expected_decisions)
    if (input_hashes["import_preview_sha256"] != import_preview_sha256 or
            input_hashes["database_preview_sha256"] != database_preview_sha256):
        _fail("REMAINING_DECISION_PREVIEW_HASH_INVALID")
    import_records = _validate_import_preview(import_preview)
    matched_pairs, database_pairs = _validate_database_preview(database_preview)
    anchor_pairs = matched_pairs | database_pairs

    proposal_keys = {
        "schema_version", "review_sha256", "reviewed_by", "decision_basis",
        "review_only", "review_state", "canonical_mutations_authorized",
        "database_write_authorized", "counts", "proposals", "proposal_gate",
        "identity_decision_gate", "reimport_gate",
    }
    if (not isinstance(proposal, dict) or set(proposal) != proposal_keys or
            proposal.get("schema_version") != "1939-v50-remaining-identity-proposals-v1" or
            proposal.get("review_only") is not True or proposal.get("review_state") != "complete" or
            proposal.get("canonical_mutations_authorized") is not False or
            proposal.get("database_write_authorized") is not False or
            proposal.get("proposal_gate") != "GO" or
            proposal.get("identity_decision_gate") != "NO-GO" or
            proposal.get("reimport_gate") != "NO-GO"):
        _fail("REMAINING_DECISION_PROPOSAL_INVALID")
    if _sha(proposal.get("review_sha256"), "REMAINING_DECISION_REVIEW_HASH_INVALID") != review_sha256:
        _fail("REMAINING_DECISION_REVIEW_HASH_INVALID")
    reviewed_by = _text(proposal.get("reviewed_by"), "REMAINING_DECISION_PROPOSAL_INVALID")
    decision_basis = _text(proposal.get("decision_basis"), "REMAINING_DECISION_PROPOSAL_INVALID")
    proposal_rows = proposal.get("proposals")
    if not isinstance(proposal_rows, list) or len(proposal_rows) != expected_decisions:
        _fail("REMAINING_DECISION_COVERAGE_INVALID")
    if [row.get("source_record_key") if isinstance(row, dict) else None for row in proposal_rows] != [
            row["new_record_key"] for row in subjects]:
        _fail("REMAINING_DECISION_COVERAGE_INVALID")

    base_keys = {
        "source_record_key", "source_span", "verbatim_sha256", "decision", "reason",
        "review_status", "evidence_sha256",
    }
    selected_keys: set[str] = set()
    selected_people: set[int] = set()
    decisions: list[dict[str, Any]] = []
    derived_counts = {decision: 0 for decision in DECISION_ORDER}
    for raw, review_subject in zip(proposal_rows, subjects):
        if not isinstance(raw, dict):
            _fail("REMAINING_DECISION_ROW_INVALID")
        decision = raw.get("decision")
        if decision not in DECISIONS:
            _fail("REMAINING_DECISION_ACTION_INVALID")
        expected_row_keys = set(base_keys)
        has_competition = False
        if decision == "same_existing_person":
            expected_row_keys |= {"target_record_key", "canonical_person_id"}
            competition_keys = {
                "competing_target_record_key", "competing_canonical_person_id",
                "resolution_basis",
            }
            present_competition = set(raw) & competition_keys
            if present_competition:
                if present_competition != competition_keys:
                    _fail("REMAINING_DECISION_COMPETITION_INVALID")
                expected_row_keys |= competition_keys
                has_competition = True
        elif decision == "structural_or_summary":
            expected_row_keys.add("context_owner_record_key")
        if set(raw) != expected_row_keys:
            _fail("REMAINING_DECISION_ROW_INVALID")
        if (decision == "same_existing_person" and
                (raw.get("reason") == EXPLICIT_USER_REASON) != has_competition):
            _fail("REMAINING_DECISION_COMPETITION_INVALID")
        _text(raw.get("reason"), "REMAINING_DECISION_ROW_INVALID")
        _text(raw.get("review_status"), "REMAINING_DECISION_ROW_INVALID")
        if raw.get("source_record_key") != review_subject["new_record_key"]:
            _fail("REMAINING_DECISION_COVERAGE_INVALID")
        if (_span(raw.get("source_span"), "REMAINING_DECISION_SOURCE_DRIFT") !=
                review_subject["source_span"] or
                _sha(raw.get("verbatim_sha256"), "REMAINING_DECISION_SOURCE_DRIFT") !=
                hashlib.sha256(review_subject["verbatim_text"].encode("utf-8")).hexdigest()):
            _fail("REMAINING_DECISION_SOURCE_DRIFT")
        if decision == "same_existing_person":
            target = _text(raw.get("target_record_key"), "REMAINING_DECISION_TARGET_INVALID")
            person_id = _positive_int(raw.get("canonical_person_id"), "REMAINING_DECISION_TARGET_INVALID")
            if (target, person_id) not in anchor_pairs:
                _fail("REMAINING_DECISION_TARGET_INVALID")
            if target in selected_keys or person_id in selected_people:
                _fail("REMAINING_DECISION_INJECTIVITY_INVALID")
            selected_keys.add(target)
            selected_people.add(person_id)
            if has_competition:
                competing = _text(raw.get("competing_target_record_key"), "REMAINING_DECISION_COMPETITION_INVALID")
                competing_person = _positive_int(
                    raw.get("competing_canonical_person_id"), "REMAINING_DECISION_COMPETITION_INVALID")
                if ((competing, competing_person) not in database_pairs or
                        competing == target or competing_person == person_id or
                        raw.get("resolution_basis") != EXPLICIT_USER_BASIS or
                        raw.get("reason") != EXPLICIT_USER_REASON):
                    _fail("REMAINING_DECISION_COMPETITION_INVALID")
        elif decision == "structural_or_summary":
            owner = _text(raw.get("context_owner_record_key"), "REMAINING_DECISION_OWNER_INVALID")
            if owner not in import_records or owner == review_subject["new_record_key"]:
                _fail("REMAINING_DECISION_OWNER_INVALID")
        evidence = _sha(raw.get("evidence_sha256"), "REMAINING_DECISION_EVIDENCE_INVALID")
        unsigned = {key: value for key, value in raw.items() if key != "evidence_sha256"}
        if evidence != _canonical_digest({"review_sha256": review_sha256, **unsigned}):
            _fail("REMAINING_DECISION_EVIDENCE_INVALID")
        output_row = {key: value for key, value in raw.items() if key != "evidence_sha256"}
        output_row["review_sha256"] = review_sha256
        output_row["proposal_evidence_sha256"] = evidence
        decisions.append(output_row)
        derived_counts[decision] += 1

    counts = proposal.get("counts")
    expected_count_keys = {"decisions", *DECISIONS}
    final_counts = {"decisions": len(decisions), **derived_counts}
    if (not isinstance(counts, dict) or set(counts) != expected_count_keys or
            not all(isinstance(counts[key], int) and not isinstance(counts[key], bool) and
                    counts[key] >= 0 for key in expected_count_keys) or
            counts != final_counts):
        _fail("REMAINING_DECISION_COUNT_INVALID")
    if proposal_sha256 is None:
        proposal_sha256 = _canonical_digest(proposal)
    else:
        proposal_sha256 = _sha(proposal_sha256, "REMAINING_DECISION_PROPOSAL_HASH_INVALID")
    return {
        "schema_version": SCHEMA_VERSION,
        "generator_version": "materialize_remaining_identity_decisions_1939_v50.py:v1",
        "input_review_sha256": review_sha256,
        "input_proposal_sha256": proposal_sha256,
        "input_import_preview_sha256": import_preview_sha256,
        "input_database_preview_sha256": database_preview_sha256,
        "reviewed_by": reviewed_by,
        "decision_basis": decision_basis,
        "review_only": True,
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": final_counts,
        "decisions": decisions,
        "decision_gate": "GO",
        "source_persona_materialization_gate": "NO-GO",
        "database_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }


def render_markdown(result: dict[str, Any]) -> str:
    counts = result["counts"]
    lines = [
        "# DAA 1939 v50 remaining identity decisions",
        "",
        "Lukket, hashbundet beslutningsmaterialisering. Ingen database- eller canonical writes er autoriseret.",
        "",
        f"- review SHA-256: `{result['input_review_sha256']}`",
        f"- proposal SHA-256: `{result['input_proposal_sha256']}`",
        f"- import-preview SHA-256: `{result['input_import_preview_sha256']}`",
        f"- database-preview SHA-256: `{result['input_database_preview_sha256']}`",
        f"- decisions: {counts['decisions']}",
        f"- same_existing_person: {counts['same_existing_person']}",
        f"- new_person_candidate: {counts['new_person_candidate']}",
        f"- structural_or_summary: {counts['structural_or_summary']}",
        f"- unresolved: {counts['unresolved']}",
        f"- database gate: **{result['database_gate']}**",
        f"- reimport gate: **{result['reimport_gate']}**",
        "",
        "## Decisions",
        "",
    ]
    for index, row in enumerate(result["decisions"], 1):
        suffix = ""
        if row["decision"] == "same_existing_person":
            suffix = f" -> `{row['target_record_key']}` / person `{row['canonical_person_id']}`"
        elif row["decision"] == "structural_or_summary":
            suffix = f" -> owner `{row['context_owner_record_key']}`"
        lines.append(f"{index}. `{row['source_record_key']}`: `{row['decision']}`{suffix}")
    lines.append("")
    return "\n".join(lines)


def write_outputs(result: dict[str, Any], output_path: Path | str,
                  report_path: Path | str) -> None:
    output = Path(output_path)
    report = Path(report_path)
    if output.resolve() == report.resolve():
        _fail("REMAINING_DECISION_OUTPUT_INVALID")
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


def _load_bytes(path: Path) -> tuple[bytes, Any]:
    payload = path.read_bytes()
    return payload, json.loads(payload)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--proposal", required=True, type=Path)
    parser.add_argument("--import-preview", required=True, type=Path)
    parser.add_argument("--database-preview", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-decisions", type=int, default=17)
    args = parser.parse_args(argv)
    review_bytes, review = _load_bytes(args.review)
    proposal_bytes, proposal = _load_bytes(args.proposal)
    import_bytes, import_preview = _load_bytes(args.import_preview)
    database_bytes, database_preview = _load_bytes(args.database_preview)
    result = materialize_remaining_decisions(
        review=review,
        proposal=proposal,
        review_sha256=hashlib.sha256(review_bytes).hexdigest(),
        proposal_sha256=hashlib.sha256(proposal_bytes).hexdigest(),
        import_preview=import_preview,
        import_preview_sha256=hashlib.sha256(import_bytes).hexdigest(),
        database_preview=database_preview,
        database_preview_sha256=hashlib.sha256(database_bytes).hexdigest(),
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
