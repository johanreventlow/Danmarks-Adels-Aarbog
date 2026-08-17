from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

import materialize_remaining_source_personas_1939_v50 as subject


EXPLICIT_USER_BASIS = (
    "explicit_user_instruction_prefer_later_full_person_over_summary_duplicate"
)
EXPECTED_COUNTS = {
    "same_existing_person": 1,
    "new_person_candidate": 1,
    "structural_or_summary": 1,
    "unresolved": 1,
}


def artifact_digest(value: object) -> str:
    payload = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def pending_row(key: str, start: int, text: str) -> dict[str, object]:
    return {
        "new_record_key": key,
        "pending_gates": ["source_persona", "identity", "interpretation_provenance"],
        "person_creation": "forbidden",
        "source_span": {"char_from": start, "char_to": start + len(text)},
        "verbatim_text": text,
    }


def old_persona(
    source_key: str,
    target_key: str,
    person_id: int,
    persona_id: str,
    start: int,
) -> dict[str, object]:
    text = f"Existing {source_key}"
    return {
        "source_persona_id": persona_id,
        "persona_key": f"1939:{source_key}",
        "source_id": 3,
        "source_record_key": source_key,
        "source_span": {"char_from": start, "char_to": start + len(text)},
        "verbatim_text": text,
        "target_record_key": target_key,
        "canonical_person_id": person_id,
        "identity_status": "accepted",
        "identity_decision": {
            "decision_batch": "fixture-batch",
            "decision_batch_sha256": "1" * 64,
            "candidate_evidence_sha256": "2" * 64,
            "confirmation": "explicit fixture confirmation",
            "reviewed_by": "fixture-reviewer",
        },
        "database_write_authorized": False,
    }


def database_preview() -> dict[str, object]:
    database_only = [{
        "record_key": "competing-target",
        "person_id": 104,
        "visning_navn": "Competing summary",
        "staged": False,
        "source_narrative_count": 1,
        "fact_count": 1,
        "family_member_count": 0,
    }]
    return {
        "schema_version": "1939-v50-database-preview-v1",
        "snapshot_at": "2026-08-17T00:00:00Z",
        "input_preview": {"schema_version": "1939-v50-import-preview-v1"},
        "database": {"transaction_read_only": "on"},
        "source": {"id": 3, "udgave": "DAA 1939", "import_key": "daa:1939"},
        "capabilities": {},
        "person_anchors": {
            "matched": [
                {"baseline_record_key": "old-target-a", "person_id": 101},
                {"baseline_record_key": "old-target-b", "person_id": 102},
                {"baseline_record_key": "selected-target", "person_id": 103},
            ],
            "matched_count": 3,
            "database_only": database_only,
            "database_only_record_keys": ["competing-target"],
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
        "expected_database_changes": {
            "canonical_person_creates": [],
            "canonical_person_updates": [],
            "canonical_person_deletes": [],
            "authorized": False,
        },
        "blockers": ["review_pending"],
        "canonical_mutations_authorized": False,
        "dry_run_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }


def fixture() -> dict[str, object]:
    database = database_preview()
    database_sha = artifact_digest(database)
    personas = [
        old_persona(
            "old-source-a", "old-target-a", 101,
            "49323d2a-9024-52fa-a405-60a90f840c5c", 1,
        ),
        old_persona(
            "old-source-b", "old-target-b", 102,
            "c5915c6d-6b36-5777-a3e4-c7bc9cc72f9c", 30,
        ),
    ]
    pending = [
        pending_row("new-a", 100, "Anna"),
        pending_row("new-b", 110, "Bent"),
        pending_row("new-c", 120, "Clara"),
        pending_row("new-d", 130, "Dorte"),
    ]
    source_persona_v1 = {
        "schema_version": "1939-v50-source-persona-materialization-v1",
        "generator_version": "materialize_source_personas_1939_v50.py:v1",
        "source": {
            "edition": "1939",
            "logical_source_id": "1939",
            "database_source_id": 3,
            "input_hashes": {
                "database_preview_sha256": database_sha,
                "identity_decision_sha256s": ["3" * 64],
                "import_preview_sha256": "4" * 64,
            },
        },
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {
            "approved_identity_decisions": 2,
            "source_personas": 2,
            "accepted_identities": 2,
            "remaining_genuinely_new_pending": 4,
        },
        "source_personas": personas,
        "remaining_genuinely_new_pending": pending,
        "expected_database_changes": {
            "source_persona_candidates": [row["source_persona_id"] for row in personas],
            "source_persona_identity_candidates": [row["source_persona_id"] for row in personas],
            "canonical_person_creates": [],
            "canonical_person_updates": [],
            "canonical_person_deletes": [],
            "authorized": False,
        },
        "source_persona_materialization_gate": "GO",
        "database_write_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }
    decisions = {
        "schema_version": "1939-v50-remaining-identity-decisions-v1",
        "generator_version": "materialize_remaining_identity_decisions_1939_v50.py:v1",
        "input_review_sha256": "5" * 64,
        "input_proposal_sha256": "6" * 64,
        "input_import_preview_sha256": "4" * 64,
        "input_database_preview_sha256": database_sha,
        "reviewed_by": "fixture-reviewer",
        "decision_basis": "complete_pdf_calamari_review",
        "review_only": True,
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {"decisions": 4, **EXPECTED_COUNTS},
        "decisions": [
            {
                "source_record_key": "new-a",
                "source_span": {"char_from": 100, "char_to": 104},
                "verbatim_sha256": hashlib.sha256(b"Anna").hexdigest(),
                "decision": "same_existing_person",
                "target_record_key": "selected-target",
                "canonical_person_id": 103,
                "competing_target_record_key": "competing-target",
                "competing_canonical_person_id": 104,
                "resolution_basis": EXPLICIT_USER_BASIS,
                "reason": "user_directed_prefer_later_full_person_over_summary_duplicate",
                "review_status": "codex_verified",
                "review_sha256": "5" * 64,
                "proposal_evidence_sha256": "7" * 64,
            },
            {
                "source_record_key": "new-b",
                "source_span": {"char_from": 110, "char_to": 114},
                "verbatim_sha256": hashlib.sha256(b"Bent").hexdigest(),
                "decision": "new_person_candidate",
                "reason": "distinct_person_without_anchor",
                "review_status": "codex_verified",
                "review_sha256": "5" * 64,
                "proposal_evidence_sha256": "8" * 64,
            },
            {
                "source_record_key": "new-c",
                "source_span": {"char_from": 120, "char_to": 125},
                "verbatim_sha256": hashlib.sha256(b"Clara").hexdigest(),
                "decision": "structural_or_summary",
                "context_owner_record_key": "old-source-a",
                "reason": "unambiguous_context_owner",
                "review_status": "codex_verified",
                "review_sha256": "5" * 64,
                "proposal_evidence_sha256": "9" * 64,
            },
            {
                "source_record_key": "new-d",
                "source_span": {"char_from": 130, "char_to": 135},
                "verbatim_sha256": hashlib.sha256(b"Dorte").hexdigest(),
                "decision": "unresolved",
                "reason": "insufficient_evidence",
                "review_status": "pending_user",
                "review_sha256": "5" * 64,
                "proposal_evidence_sha256": "a" * 64,
            },
        ],
        "decision_gate": "GO",
        "source_persona_materialization_gate": "NO-GO",
        "database_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }
    return {
        "source_persona_v1": source_persona_v1,
        "source_persona_v1_sha256": artifact_digest(source_persona_v1),
        "remaining_decisions": decisions,
        "remaining_decisions_sha256": artifact_digest(decisions),
        "database_preview": database,
        "database_preview_sha256": database_sha,
        "expected_v1_personas": 2,
        "expected_decisions": 4,
        "expected_disposition_counts": EXPECTED_COUNTS,
    }


def materialize(values: dict[str, object]) -> dict[str, object]:
    return subject._materialize_remaining_source_personas_for_contract(**values)


def test_public_materializer_rejects_weaker_count_contract():
    values = fixture()

    with pytest.raises(TypeError):
        subject.materialize_remaining_source_personas(**values)


def test_cli_does_not_expose_count_overrides():
    with pytest.raises(SystemExit) as raised:
        subject.main([
            "--source-personas-v1=missing-v1.json",
            "--remaining-decisions=missing-decisions.json",
            "--database-preview=missing-database.json",
            "--output=missing-output.json",
            "--report=missing-report.md",
            "--expected-v1-personas=23",
            "--expected-decisions=17",
        ])

    assert raised.value.code == 2


def test_deep_preserves_v1_and_appends_only_same_existing_person():
    values = fixture()
    original_personas = copy.deepcopy(values["source_persona_v1"]["source_personas"])

    result = materialize(values)

    assert result["schema_version"] == "1939-v50-source-persona-materialization-v2"
    assert result["source_personas"][:2] == original_personas
    assert values["source_persona_v1"]["source_personas"] == original_personas
    assert len(result["source_personas"]) == 3
    appended = result["source_personas"][2]
    assert appended["source_persona_id"] == "3aa4ed66-ac51-5775-a234-db6d4324250a"
    assert appended["source_record_key"] == "new-a"
    assert appended["target_record_key"] == "selected-target"
    assert appended["canonical_person_id"] == 103
    assert appended["identity_decision"]["competing_target_record_key"] == "competing-target"
    assert appended["identity_decision"]["competing_canonical_person_id"] == 104
    assert appended["identity_decision"]["resolution_basis"] == EXPLICIT_USER_BASIS
    assert [row["source_record_key"] for row in result["new_person_candidates"]] == ["new-b"]
    assert [row["source_record_key"] for row in result["structural_or_summary"]] == ["new-c"]
    assert [row["source_record_key"] for row in result["unresolved"]] == ["new-d"]
    for key in ("new_person_candidates", "structural_or_summary", "unresolved"):
        assert all("source_persona_id" not in row for row in result[key])
        assert all("canonical_mutations_authorized" not in row for row in result[key])
    assert result["counts"] == {
        "v1_source_personas": 2,
        "appended_source_personas": 1,
        "source_personas": 3,
        **EXPECTED_COUNTS,
    }
    assert result["canonical_mutations_authorized"] is False
    assert result["database_write_authorized"] is False
    assert result["expected_database_changes"]["canonical_person_creates"] == []
    assert result["expected_database_changes"]["canonical_person_updates"] == []
    assert result["expected_database_changes"]["canonical_person_deletes"] == []
    assert result["expected_database_changes"]["authorized"] is False
    assert result["database_gate"] == "NO-GO"
    assert result["reimport_gate"] == "NO-GO"


def test_accepts_selected_anchor_from_database_only():
    values = fixture()
    selected = values["remaining_decisions"]["decisions"][0]
    selected.update(target_record_key="competing-target", canonical_person_id=104)
    for key in (
        "competing_target_record_key", "competing_canonical_person_id", "resolution_basis",
    ):
        selected.pop(key)
    values["remaining_decisions_sha256"] = artifact_digest(values["remaining_decisions"])

    result = materialize(values)

    assert result["source_personas"][-1]["target_record_key"] == "competing-target"
    assert result["source_personas"][-1]["canonical_person_id"] == 104


@pytest.mark.parametrize(
    ("mutation", "refresh_hash", "code"),
    [
        (lambda v: v["source_persona_v1"]["source_personas"].reverse(), True,
         "REMAINING_SOURCE_PERSONA_V1_ORDER_INVALID"),
        (lambda v: v["source_persona_v1"]["source_personas"][0].update(
            source_persona_id="00000000-0000-5000-8000-000000000000"), True,
         "REMAINING_SOURCE_PERSONA_UUID_INVALID"),
        (lambda v: v["remaining_decisions"]["decisions"][0].update(
            source_record_key="old-source-a"), True,
         "REMAINING_SOURCE_PERSONA_COVERAGE_INVALID"),
        (lambda v: v["remaining_decisions"]["decisions"][0].update(
            target_record_key="old-target-a", canonical_person_id=101), True,
         "REMAINING_SOURCE_PERSONA_INJECTIVITY_INVALID"),
        (lambda v: v["remaining_decisions"]["decisions"][0].update(
            target_record_key="unknown-target", canonical_person_id=999), True,
         "REMAINING_SOURCE_PERSONA_TARGET_INVALID"),
        (lambda v: v["remaining_decisions"]["decisions"][0].update(
            source_span={"char_from": 100, "char_to": 105}), True,
         "REMAINING_SOURCE_PERSONA_SOURCE_DRIFT"),
        (lambda v: v["remaining_decisions"]["decisions"][1].update(
            decision="unresolved"), True,
         "REMAINING_SOURCE_PERSONA_COUNT_INVALID"),
        (lambda v: v["source_persona_v1"].update(unexpected=True), True,
         "REMAINING_SOURCE_PERSONA_V1_INVALID"),
        (lambda v: v["remaining_decisions"]["decisions"][0].update(unexpected=True), True,
         "REMAINING_SOURCE_PERSONA_DECISION_ROW_INVALID"),
        (lambda v: v["database_preview"].update(unexpected=True), True,
         "REMAINING_SOURCE_PERSONA_DATABASE_PREVIEW_INVALID"),
        (lambda v: v["remaining_decisions"].update(database_write_authorized=True), True,
         "REMAINING_SOURCE_PERSONA_DECISIONS_INVALID"),
        (lambda v: v["source_persona_v1"].update(canonical_mutations_authorized=True), True,
         "REMAINING_SOURCE_PERSONA_V1_INVALID"),
    ],
)
def test_rejects_lineage_injectivity_closed_schema_and_authority_drift(
    mutation, refresh_hash: bool, code: str,
):
    values = fixture()
    mutation(values)
    if refresh_hash:
        values["source_persona_v1_sha256"] = artifact_digest(values["source_persona_v1"])
        values["remaining_decisions_sha256"] = artifact_digest(values["remaining_decisions"])
        values["database_preview_sha256"] = artifact_digest(values["database_preview"])

    with pytest.raises(subject.RemainingSourcePersonaError, match=f"^{code}$"):
        materialize(values)


@pytest.mark.parametrize(
    ("artifact", "field", "code"),
    [
        ("source_persona_v1", "source_persona_v1_sha256", "REMAINING_SOURCE_PERSONA_V1_HASH_INVALID"),
        ("remaining_decisions", "remaining_decisions_sha256", "REMAINING_SOURCE_PERSONA_DECISIONS_HASH_INVALID"),
        ("database_preview", "database_preview_sha256", "REMAINING_SOURCE_PERSONA_DATABASE_HASH_INVALID"),
    ],
)
def test_recomputes_artifact_content_hashes(artifact: str, field: str, code: str):
    values = fixture()
    values[artifact]["generator_version" if artifact != "database_preview" else "snapshot_at"] = "drift"

    with pytest.raises(subject.RemainingSourcePersonaError, match=f"^{code}$"):
        materialize(values)


def test_rejects_duplicate_persona_id_and_source_in_v1_even_with_rehashed_artifact():
    values = fixture()
    duplicate = copy.deepcopy(values["source_persona_v1"]["source_personas"][0])
    duplicate["source_record_key"] = "old-source-c"
    duplicate["persona_key"] = "1939:old-source-c"
    duplicate["source_persona_id"] = "86af9b47-7b85-505e-b342-2ecd6c41ba84"
    values["source_persona_v1"]["source_personas"].append(duplicate)
    values["source_persona_v1"]["counts"].update(
        approved_identity_decisions=3, source_personas=3, accepted_identities=3,
    )
    values["source_persona_v1"]["expected_database_changes"]["source_persona_candidates"].append(
        duplicate["source_persona_id"]
    )
    values["source_persona_v1"]["expected_database_changes"][
        "source_persona_identity_candidates"
    ].append(duplicate["source_persona_id"])
    values["expected_v1_personas"] = 3
    values["source_persona_v1_sha256"] = artifact_digest(values["source_persona_v1"])

    with pytest.raises(
        subject.RemainingSourcePersonaError,
        match="^REMAINING_SOURCE_PERSONA_INJECTIVITY_INVALID$",
    ):
        materialize(values)


def test_write_outputs_is_exclusive_and_deterministic(tmp_path: Path):
    result = materialize(fixture())
    output = tmp_path / "source-personas.json"
    report = tmp_path / "source-personas.md"

    subject.write_outputs(result, output, report)
    json_bytes = output.read_bytes()
    report_bytes = report.read_bytes()
    with pytest.raises(FileExistsError):
        subject.write_outputs(result, output, report)
    subject.write_outputs(result, tmp_path / "other.json", tmp_path / "other.md")
    assert (tmp_path / "other.json").read_bytes() == json_bytes
    assert (tmp_path / "other.md").read_bytes() == report_bytes


def test_json_and_report_are_byte_identical_across_hash_seeds(tmp_path: Path):
    command = [
        sys.executable,
        "-B",
        "-c",
        (
            "from pathlib import Path; "
            "import test_materialize_remaining_source_personas_1939_v50 as t; "
            "import materialize_remaining_source_personas_1939_v50 as m; "
            "v=t.fixture(); r=m._materialize_remaining_source_personas_for_contract(**v); "
            "m.write_outputs(r, Path(__import__('sys').argv[1]), Path(__import__('sys').argv[2]))"
        ),
    ]
    outputs = []
    for seed in ("1", "987654"):
        output = tmp_path / f"{seed}.json"
        report = tmp_path / f"{seed}.md"
        environment = os.environ.copy()
        environment["PYTHONHASHSEED"] = seed
        subprocess.run(
            [*command, str(output), str(report)], check=True,
            cwd=Path(__file__).parent, env=environment,
        )
        outputs.append((output.read_bytes(), report.read_bytes()))

    assert outputs[0] == outputs[1]
