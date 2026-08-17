from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

import materialize_remaining_identity_decisions_1939_v50 as subject


EXPLICIT_USER_BASIS = (
    "explicit_user_instruction_prefer_later_full_person_over_summary_duplicate"
)


def digest(value: object) -> str:
    payload = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def evidence_digest(review_sha256: str, row: dict[str, object]) -> str:
    payload = {"review_sha256": review_sha256, **row}
    return digest(payload)


def source_row(key: str, start: int, text: str) -> dict[str, object]:
    return {
        "acceptance_id": f"accept-{key}",
        "baseline_record_keys": [],
        "disposition": "genuinely_new_pending",
        "new_record_key": key,
        "person_creation": "forbidden",
        "record_kind": "person",
        "source_span": {"char_from": start, "char_to": start + len(text)},
        "verbatim_text": text,
    }


def fixture() -> dict[str, object]:
    import_preview = {
        "schema_version": "1939-v50-import-preview-v1",
        "generator_version": "fixture:v1",
        "source": {"edition": "1939", "input_hashes": {}},
        "counts": {"source_records": 5},
        "source_records": [
            source_row("new-a", 10, "Anna"),
            source_row("new-b", 20, "Bent"),
            source_row("new-c", 30, "Clara"),
            source_row("owner-c", 40, "Owner Clara"),
            source_row("new-d", 60, "Dorte"),
        ],
        "genuinely_new_pending": [],
        "mapped_existing": [],
        "retired_legacy": [],
        "source_only_records": [],
        "expected_database_changes": {},
        "reimport_blockers": ["review_pending"],
        "canonical_mutations_authorized": False,
        "preview_gate": "GO",
        "reimport_gate": "NO-GO",
    }
    database_preview = {
        "schema_version": "1939-v50-database-preview-v1",
        "source": {},
        "snapshot_at": "2026-08-17T00:00:00Z",
        "input_preview": {"schema_version": "1939-v50-import-preview-v1"},
        "database": {"transaction_read_only": "on"},
        "capabilities": {},
        "person_anchors": {
            "matched": [{"baseline_record_key": "old-a", "person_id": 101}],
            "matched_count": 1,
            "database_only": [{
                "record_key": "old-other",
                "person_id": 102,
                "visning_navn": "Anna other",
                "staged": False,
                "source_narrative_count": 1,
                "fact_count": 1,
                "family_member_count": 0,
            }],
            "database_only_record_keys": ["old-other"],
            "missing_count": 0,
            "missing_record_keys": [],
            "collision_count": 0,
            "collisions": [],
            "retired_present": [],
            "retired_present_count": 0,
            "retired_present_record_keys": [],
        },
        "source_records": {},
        "narratives": {},
        "facts": {},
        "relations": {},
        "expected_database_changes": {},
        "blockers": ["review_pending"],
        "canonical_mutations_authorized": False,
        "dry_run_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }
    import_sha = digest(import_preview)
    database_sha = digest(database_preview)
    input_hashes = {
        "boundary_materialization_sha256": "1" * 64,
        "calamari_sha256": "2" * 64,
        "clean_sha256": "3" * 64,
        "database_only_profiles_sha256": "4" * 64,
        "database_preview_sha256": database_sha,
        "import_preview_sha256": import_sha,
        "source_persona_sha256": "5" * 64,
    }
    subjects = []
    for key, start, text in (
        ("new-a", 10, "Anna"),
        ("new-b", 20, "Bent"),
        ("new-c", 30, "Clara"),
        ("new-d", 60, "Dorte"),
    ):
        subjects.append({
            "new_record_key": key,
            "source_span": {"char_from": start, "char_to": start + len(text)},
            "verbatim_text": text,
            "previous_record": None,
            "next_record": None,
            "page_evidence": {"page_from": 503, "page_to": 503},
            "later_occurrences": [],
            "candidates": [],
            "presentation_candidates": [],
            "review_state": "pending",
        })
    subjects[2]["later_occurrences"] = [{
        "record_key": "owner-c",
        "source_span": {"char_from": 40, "char_to": 51},
        "signal": {"kind": "literal_name", "text": "Clara", "authoritative": True},
    }]
    review = {
        "schema_version": "1939-v50-remaining-identity-review-v1",
        "generator_version": "fixture:v1",
        "input_hashes": input_hashes,
        "review_only": True,
        "review_state": "pending",
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {
            "subjects": 4,
            "mapped_profiles": 1,
            "database_only_profiles": 1,
            "profiles": 2,
            "candidate_links": 0,
            "presentation_only": 0,
        },
        "subjects": subjects,
        "review_gate": "GO",
        "identity_decision_gate": "NO-GO",
        "database_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }
    review_sha = digest(review)
    rows = [
        {
            "source_record_key": "new-a",
            "source_span": {"char_from": 10, "char_to": 14},
            "verbatim_sha256": hashlib.sha256(b"Anna").hexdigest(),
            "decision": "same_existing_person",
            "target_record_key": "old-a",
            "canonical_person_id": 101,
            "competing_target_record_key": "old-other",
            "competing_canonical_person_id": 102,
            "resolution_basis": EXPLICIT_USER_BASIS,
            "reason": "user_directed_prefer_later_full_person_over_summary_duplicate",
            "review_status": "codex_verified",
        },
        {
            "source_record_key": "new-b",
            "source_span": {"char_from": 20, "char_to": 24},
            "verbatim_sha256": hashlib.sha256(b"Bent").hexdigest(),
            "decision": "new_person_candidate",
            "reason": "pdf_calamari_hierarchy_supports_distinct_person_without_existing_anchor",
            "review_status": "codex_verified",
        },
        {
            "source_record_key": "new-c",
            "source_span": {"char_from": 30, "char_to": 35},
            "verbatim_sha256": hashlib.sha256(b"Clara").hexdigest(),
            "decision": "structural_or_summary",
            "context_owner_record_key": "owner-c",
            "reason": "pdf_calamari_lineage_summary_has_unambiguous_context_owner",
            "review_status": "codex_verified",
        },
        {
            "source_record_key": "new-d",
            "source_span": {"char_from": 60, "char_to": 65},
            "verbatim_sha256": hashlib.sha256(b"Dorte").hexdigest(),
            "decision": "unresolved",
            "reason": "insufficient_identity_evidence",
            "review_status": "pending_user",
        },
    ]
    for row in rows:
        row["evidence_sha256"] = evidence_digest(review_sha, row)
    proposal = {
        "schema_version": "1939-v50-remaining-identity-proposals-v1",
        "review_sha256": review_sha,
        "reviewed_by": "codex_verified",
        "decision_basis": "complete_review",
        "review_only": True,
        "review_state": "complete",
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {
            "decisions": 4,
            "same_existing_person": 1,
            "new_person_candidate": 1,
            "structural_or_summary": 1,
            "unresolved": 1,
        },
        "proposals": rows,
        "proposal_gate": "GO",
        "identity_decision_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }
    return {
        "review": review,
        "proposal": proposal,
        "review_sha256": review_sha,
        "import_preview": import_preview,
        "import_preview_sha256": import_sha,
        "database_preview": database_preview,
        "database_preview_sha256": database_sha,
        "expected_decisions": 4,
    }


def materialize(values: dict[str, object]) -> dict[str, object]:
    return subject.materialize_remaining_decisions(**values)


def refresh_evidence(values: dict[str, object], index: int) -> None:
    row = values["proposal"]["proposals"][index]
    without_hash = {key: value for key, value in row.items() if key != "evidence_sha256"}
    row["evidence_sha256"] = evidence_digest(values["review_sha256"], without_hash)


def test_materializes_all_four_dispositions_in_review_source_order():
    result = materialize(fixture())

    assert result["schema_version"] == "1939-v50-remaining-identity-decisions-v1"
    assert result["counts"] == {
        "decisions": 4,
        "same_existing_person": 1,
        "new_person_candidate": 1,
        "structural_or_summary": 1,
        "unresolved": 1,
    }
    assert [row["source_record_key"] for row in result["decisions"]] == [
        "new-a", "new-b", "new-c", "new-d"
    ]
    assert result["decisions"][0]["target_record_key"] == "old-a"
    assert result["decisions"][0]["competing_target_record_key"] == "old-other"
    assert result["decisions"][2]["context_owner_record_key"] == "owner-c"
    assert result["canonical_mutations_authorized"] is False
    assert result["database_write_authorized"] is False
    assert result["database_gate"] == "NO-GO"
    assert result["reimport_gate"] == "NO-GO"


@pytest.mark.parametrize(
    ("mutation", "code"),
    [
        (lambda v: v["proposal"]["proposals"].append(copy.deepcopy(v["proposal"]["proposals"][0])),
         "REMAINING_DECISION_COVERAGE_INVALID"),
        (lambda v: v["proposal"]["proposals"].pop(), "REMAINING_DECISION_COVERAGE_INVALID"),
        (lambda v: v["proposal"]["proposals"][1].update(source_record_key="new-a"),
         "REMAINING_DECISION_COVERAGE_INVALID"),
        (lambda v: v["proposal"]["proposals"][1].update(decision="maybe"),
         "REMAINING_DECISION_ACTION_INVALID"),
        (lambda v: v["proposal"]["proposals"][1].update(target_record_key="hidden"),
         "REMAINING_DECISION_ROW_INVALID"),
        (lambda v: v["proposal"]["proposals"][0].update(canonical_person_id=999),
         "REMAINING_DECISION_TARGET_INVALID"),
        (lambda v: v["database_preview"]["person_anchors"].update(matched_count=2),
         "REMAINING_DECISION_DATABASE_PREVIEW_INVALID"),
        (lambda v: v["import_preview"]["source_records"][3].update(verbatim_text="drift"),
         "REMAINING_DECISION_IMPORT_PREVIEW_INVALID"),
        (lambda v: v["proposal"].update(database_write_authorized=True),
         "REMAINING_DECISION_PROPOSAL_INVALID"),
        (lambda v: v["proposal"].update(hidden_authority=True),
         "REMAINING_DECISION_PROPOSAL_INVALID"),
    ],
)
def test_rejects_closed_schema_coverage_target_preview_and_authority_drift(mutation, code):
    values = fixture()
    mutation(values)
    with pytest.raises(subject.RemainingIdentityDecisionError, match=f"^{code}$"):
        materialize(values)


def test_rejects_duplicate_selected_target_and_person():
    values = fixture()
    second = values["proposal"]["proposals"][1]
    second.update({
        "decision": "same_existing_person",
        "target_record_key": "old-a",
        "canonical_person_id": 101,
        "reason": "same_anchor",
    })
    refresh_evidence(values, 1)

    with pytest.raises(
        subject.RemainingIdentityDecisionError,
        match="^REMAINING_DECISION_INJECTIVITY_INVALID$",
    ):
        materialize(values)


def test_rejects_competing_target_without_explicit_user_basis():
    values = fixture()
    values["proposal"]["proposals"][0]["resolution_basis"] = "codex_inference"
    refresh_evidence(values, 0)

    with pytest.raises(
        subject.RemainingIdentityDecisionError,
        match="^REMAINING_DECISION_COMPETITION_INVALID$",
    ):
        materialize(values)


def test_rejects_silently_removed_competition_from_user_directed_choice():
    values = fixture()
    row = values["proposal"]["proposals"][0]
    del row["competing_target_record_key"]
    del row["competing_canonical_person_id"]
    del row["resolution_basis"]
    refresh_evidence(values, 0)

    with pytest.raises(
        subject.RemainingIdentityDecisionError,
        match="^REMAINING_DECISION_COMPETITION_INVALID$",
    ):
        materialize(values)


def test_rejects_boolean_proposal_count_that_compares_equal_to_integer():
    values = fixture()
    values["proposal"]["counts"]["unresolved"] = True

    with pytest.raises(
        subject.RemainingIdentityDecisionError,
        match="^REMAINING_DECISION_COUNT_INVALID$",
    ):
        materialize(values)


def test_rejects_false_context_owner_even_when_evidence_hash_is_recomputed():
    values = fixture()
    values["proposal"]["proposals"][2]["context_owner_record_key"] = "missing-owner"
    refresh_evidence(values, 2)

    with pytest.raises(
        subject.RemainingIdentityDecisionError,
        match="^REMAINING_DECISION_OWNER_INVALID$",
    ):
        materialize(values)


@pytest.mark.parametrize(
    ("field", "code"),
    [
        ("review_sha256", "REMAINING_DECISION_REVIEW_HASH_INVALID"),
        ("import_preview_sha256", "REMAINING_DECISION_PREVIEW_HASH_INVALID"),
        ("database_preview_sha256", "REMAINING_DECISION_PREVIEW_HASH_INVALID"),
    ],
)
def test_rejects_input_hash_drift(field, code):
    values = fixture()
    values[field] = "f" * 64

    with pytest.raises(subject.RemainingIdentityDecisionError, match=f"^{code}$"):
        materialize(values)


def test_rejects_source_span_and_verbatim_hash_drift():
    for field, value in (
        ("source_span", {"char_from": 20, "char_to": 25}),
        ("verbatim_sha256", "e" * 64),
    ):
        values = fixture()
        values["proposal"]["proposals"][1][field] = value
        refresh_evidence(values, 1)
        with pytest.raises(
            subject.RemainingIdentityDecisionError,
            match="^REMAINING_DECISION_SOURCE_DRIFT$",
        ):
            materialize(values)


def test_rejects_altered_evidence_hash():
    values = fixture()
    values["proposal"]["proposals"][0]["evidence_sha256"] = "a" * 64

    with pytest.raises(
        subject.RemainingIdentityDecisionError,
        match="^REMAINING_DECISION_EVIDENCE_INVALID$",
    ):
        materialize(values)


def test_write_outputs_is_exclusive_and_deterministic(tmp_path: Path):
    result = materialize(fixture())
    output = tmp_path / "decisions.json"
    report = tmp_path / "decisions.md"

    subject.write_outputs(result, output, report)
    first_json = output.read_bytes()
    first_report = report.read_bytes()
    with pytest.raises(FileExistsError):
        subject.write_outputs(result, output, report)

    other_output = tmp_path / "other.json"
    other_report = tmp_path / "other.md"
    subject.write_outputs(result, other_output, other_report)
    assert other_output.read_bytes() == first_json
    assert other_report.read_bytes() == first_report


def test_count_field_order_is_deterministic_across_python_hash_seeds():
    command = [
        sys.executable,
        "-B",
        "-c",
        (
            "import json; "
            "import test_materialize_remaining_identity_decisions_1939_v50 as t; "
            "import materialize_remaining_identity_decisions_1939_v50 as m; "
            "print(json.dumps(m.materialize_remaining_decisions(**t.fixture())['counts']))"
        ),
    ]
    outputs = []
    for seed in ("1", "2"):
        environment = os.environ.copy()
        environment["PYTHONHASHSEED"] = seed
        outputs.append(subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            cwd=Path(__file__).parent,
            env=environment,
        ).stdout)

    assert outputs[0] == outputs[1]
