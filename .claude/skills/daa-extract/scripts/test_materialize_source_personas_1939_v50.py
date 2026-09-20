from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

import materialize_source_personas_1939_v50 as subject


def fixture_inputs() -> dict:
    source_a = {
        "new_record_key": "record-a",
        "source_span": {"char_from": 10, "char_to": 25},
        "verbatim_text": "Christian 1701",
        "person_creation": "forbidden",
        "pending_gates": ["source_persona", "identity", "interpretation_provenance"],
    }
    source_b = {
        "new_record_key": "record-b",
        "source_span": {"char_from": 30, "char_to": 42},
        "verbatim_text": "Otto ukendt",
        "person_creation": "forbidden",
        "pending_gates": ["source_persona", "identity", "interpretation_provenance"],
    }
    import_hashes = {
        "calamari_sha256": "1" * 64,
        "clean_sha256": "2" * 64,
        "ledger_sha256": "3" * 64,
        "materialization_sha256": "4" * 64,
        "reconciliation_report_sha256": "5" * 64,
        "reconciliation_sha256": "6" * 64,
    }
    import_preview = {
        "schema_version": "1939-v50-import-preview-v1",
        "generator_version": "prepare_reimport_1939_v50.py:v1",
        "source": {"edition": "1939", "source_id": "1939",
                   "rendition_id": "daa-1939-calamari-r6-clean",
                   "input_hashes": import_hashes},
        "canonical_mutations_authorized": False,
        "counts": {"genuinely_new_pending": 2, "source_records": 2},
        "source_records": [{
            "new_record_key": row["new_record_key"],
            "source_span": row["source_span"],
            "verbatim_text": row["verbatim_text"],
            "record_kind": "person",
            "disposition": "accepted_genuinely_new_source_record",
            "acceptance_id": f"accept-{index}",
            "baseline_record_keys": [],
            "person_creation": "forbidden",
        } for index, row in enumerate((source_a, source_b), 1)],
        "mapped_existing": [], "retired_legacy": [],
        "genuinely_new_pending": [source_a, source_b],
        "source_only_records": [],
        "expected_database_changes": {
            "source_record_candidates": ["record-a", "record-b"],
            "legacy_retirement_candidates": [],
            "canonical_person_creates": [], "canonical_person_updates": [],
            "canonical_person_deletes": [], "authorized": False,
        },
        "preview_gate": "GO", "reimport_gate": "NO-GO",
        "reimport_blockers": ["genuinely_new_identity_pending"],
    }
    database_preview = {
        "schema_version": "1939-v50-database-preview-v1",
        "input_preview": {"schema_version": "1939-v50-import-preview-v1",
                          "input_hashes": import_hashes},
        "source": {"id": 17, "udgave": "DAA 1939", "import_key": "daa:1939"},
        "canonical_mutations_authorized": False,
        "person_anchors": {
            "matched_count": 1, "missing_count": 0, "collision_count": 0,
            "retired_present_count": 0,
            "matched": [{"baseline_record_key": "baseline-a", "person_id": 1201}],
            "missing_record_keys": [], "collisions": [],
            "retired_present_record_keys": [], "retired_present": [],
            "database_only_record_keys": [], "database_only": [],
        },
        "expected_database_changes": {
            "canonical_person_creates": [], "canonical_person_updates": [],
            "canonical_person_deletes": [], "authorized": False,
        },
        "dry_run_gate": "NO-GO", "reimport_gate": "NO-GO",
    }
    decisions = [{
        "schema_version": "1939-v50-identity-decisions-v1",
        "generator_version": "materialize_identity_decisions_1939_v50.py:v1",
        "input_review_sha256": "7" * 64,
        "reviewed_by": "codex-assisted:johan-reventlow",
        "decision_batch": "batch-1", "confirmation": "ja",
        "decision_basis": "explicit_user_confirmation",
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {"decisions": 1, "same": 1},
        "decisions": [{
            "source_record_key": "record-a",
            "candidate_record_key": "baseline-a",
            "canonical_person_id": 1201,
            "action": "same",
            "record_provenance": {"record_key": "record-a",
                                  "external_person_number": None},
            "source_span": {"char_from": 10, "char_to": 25},
            "candidate_evidence_sha256": "8" * 64,
            "source_persona_status": "pending_materialization",
            "database_write_authorized": False,
        }],
        "decision_gate": "GO",
        "source_persona_materialization_gate": "NO-GO",
        "database_gate": "NO-GO", "reimport_gate": "NO-GO",
    }]
    return {
        "import_preview": import_preview,
        "database_preview": database_preview,
        "identity_decision_batches": decisions,
        "input_hashes": {
            "import_preview_sha256": "a" * 64,
            "database_preview_sha256": "b" * 64,
            "identity_decision_sha256s": ["c" * 64],
        },
    }


def test_materializes_approved_identity_and_leaves_other_source_pending():
    result = subject.build_source_persona_materialization(
        **fixture_inputs(), expected_decisions=1, expected_remaining_pending=1)

    assert result["counts"] == {
        "approved_identity_decisions": 1,
        "source_personas": 1,
        "accepted_identities": 1,
        "remaining_genuinely_new_pending": 1,
    }
    persona = result["source_personas"][0]
    assert persona["source_record_key"] == "record-a"
    assert persona["target_record_key"] == "baseline-a"
    assert persona["canonical_person_id"] == 1201
    assert persona["source_id"] == 17
    assert result["source"]["logical_source_id"] == "1939"
    assert persona["identity_status"] == "accepted"
    assert persona["source_span"] == {"char_from": 10, "char_to": 25}
    assert persona["verbatim_text"] == "Christian 1701"
    assert result["remaining_genuinely_new_pending"] == [fixture_inputs()[
        "import_preview"]["genuinely_new_pending"][1]]
    assert result["expected_database_changes"]["canonical_person_creates"] == []
    assert result["canonical_mutations_authorized"] is False
    assert result["database_write_authorized"] is False
    assert result["source_persona_materialization_gate"] == "GO"
    assert result["database_write_gate"] == "NO-GO"
    assert result["reimport_gate"] == "NO-GO"


def test_accepts_explicit_identity_to_existing_database_only_record():
    inputs = fixture_inputs()
    anchors = inputs["database_preview"]["person_anchors"]
    anchors["database_only_record_keys"] = ["db-only-a"]
    anchors["database_only"] = [{
        "record_key": "db-only-a", "person_id": 1300,
        "visning_navn": "Christian", "staged": False,
        "source_narrative_count": 1, "fact_count": 2,
        "family_member_count": 0,
    }]
    decision = inputs["identity_decision_batches"][0]["decisions"][0]
    decision["candidate_record_key"] = "db-only-a"
    decision["canonical_person_id"] = 1300

    result = subject.build_source_persona_materialization(
        **inputs, expected_decisions=1, expected_remaining_pending=1)

    assert result["source_personas"][0]["target_record_key"] == "db-only-a"
    assert result["source_personas"][0]["canonical_person_id"] == 1300


def test_source_persona_id_is_deterministic_and_source_scoped():
    inputs = fixture_inputs()
    first = subject.build_source_persona_materialization(
        **inputs, expected_decisions=1, expected_remaining_pending=1)
    second = subject.build_source_persona_materialization(
        **copy.deepcopy(inputs), expected_decisions=1, expected_remaining_pending=1)
    assert first == second
    assert first["source_personas"][0]["source_persona_id"] == (
        "f899b139-f2e4-5241-9c8d-9df3ea595edb")


@pytest.mark.parametrize("mutation", [
    "import_schema", "import_gate", "source_record_drift", "database_source",
    "database_target", "batch_schema", "batch_write_authority", "decision_action",
    "decision_span", "decision_source", "duplicate_source", "duplicate_candidate",
    "duplicate_person", "hash_count", "malformed_hash",
])
def test_rejects_input_drift_ambiguity_or_write_authority(mutation):
    inputs = copy.deepcopy(fixture_inputs())
    if mutation == "import_schema":
        inputs["import_preview"]["schema_version"] = "unknown"
    elif mutation == "import_gate":
        inputs["import_preview"]["preview_gate"] = "NO-GO"
    elif mutation == "source_record_drift":
        inputs["import_preview"]["source_records"][0]["verbatim_text"] = "drift"
    elif mutation == "database_source":
        inputs["database_preview"]["source"]["udgave"] = "DAA 1940"
    elif mutation == "database_target":
        inputs["database_preview"]["person_anchors"]["matched"][0]["person_id"] = 999
    elif mutation == "batch_schema":
        inputs["identity_decision_batches"][0]["schema_version"] = "unknown"
    elif mutation == "batch_write_authority":
        inputs["identity_decision_batches"][0]["database_write_authorized"] = True
    elif mutation == "decision_action":
        inputs["identity_decision_batches"][0]["decisions"][0]["action"] = "different"
    elif mutation == "decision_span":
        inputs["identity_decision_batches"][0]["decisions"][0]["source_span"]["char_to"] = 24
    elif mutation == "decision_source":
        inputs["identity_decision_batches"][0]["decisions"][0]["source_record_key"] = "record-z"
    elif mutation in {"duplicate_source", "duplicate_candidate", "duplicate_person"}:
        batch = inputs["identity_decision_batches"][0]
        second = copy.deepcopy(batch["decisions"][0])
        if mutation != "duplicate_source":
            second["source_record_key"] = "record-b"
            second["record_provenance"]["record_key"] = "record-b"
            second["source_span"] = {"char_from": 30, "char_to": 42}
        if mutation != "duplicate_candidate":
            second["candidate_record_key"] = "baseline-b"
            inputs["database_preview"]["person_anchors"]["matched"].append({
                "baseline_record_key": "baseline-b", "person_id": 1201})
            inputs["database_preview"]["person_anchors"]["matched_count"] = 2
        if mutation != "duplicate_person":
            second["canonical_person_id"] = 1202
            for row in inputs["database_preview"]["person_anchors"]["matched"]:
                if row["baseline_record_key"] == second["candidate_record_key"]:
                    row["person_id"] = 1202
        batch["decisions"].append(second)
        batch["counts"] = {"decisions": 2, "same": 2}
        inputs["input_hashes"]["identity_decision_sha256s"] = ["c" * 64]
    elif mutation == "hash_count":
        inputs["input_hashes"]["identity_decision_sha256s"] = []
    elif mutation == "malformed_hash":
        inputs["input_hashes"]["import_preview_sha256"] = "not-a-sha"
    expected_decisions = 2 if mutation.startswith("duplicate_") else 1
    expected_pending = 0 if expected_decisions == 2 else 1
    with pytest.raises(subject.SourcePersonaMaterializationError):
        subject.build_source_persona_materialization(
            **inputs, expected_decisions=expected_decisions,
            expected_remaining_pending=expected_pending)


def test_outputs_are_exclusive_and_byte_deterministic(tmp_path: Path):
    result = subject.build_source_persona_materialization(
        **fixture_inputs(), expected_decisions=1, expected_remaining_pending=1)
    output, report = tmp_path / "materialization.json", tmp_path / "report.md"
    subject.write_outputs(result, output, report)
    first = output.read_bytes(), report.read_bytes()
    with pytest.raises(FileExistsError):
        subject.write_outputs(result, output, report)
    output.unlink()
    report.unlink()
    subject.write_outputs(result, output, report)
    assert (output.read_bytes(), report.read_bytes()) == first
    assert json.loads(output.read_text(encoding="utf-8")) == result
