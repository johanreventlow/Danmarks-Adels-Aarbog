from __future__ import annotations

import copy
from pathlib import Path

import build_death_year_identity_review_1939_v50 as subject
import pytest


def profile_row(record_key: str, person_id: int, name: str,
                death_value: str) -> dict:
    return {
        "record_key": record_key,
        "person_id": person_id,
        "display_name": name,
        "facts": [{
            "fact_id": f"{record_key}:fact:0",
            "fact_type": "død",
            "raw_value": death_value,
        }],
    }


def fixture_inputs() -> dict:
    mapped_review = {
        "schema_version": "1939-v50-mapped-identity-review-v1",
        "review_only": True,
        "review_state": "pending",
        "canonical_mutations_authorized": False,
        "counts": {
            "subjects": 3, "profiles": 3, "searchable_profiles": 3,
            "unsearchable_profiles": 0, "candidate_links": 0,
            "linked_subjects": 0, "unlinked_subjects": 3,
            "ambiguous_subjects": 0,
        },
        "unsearchable_profile_keys": [],
        "subjects": [
            {"new_record_key": "new-already", "source_span": {
                "char_from": 0, "char_to": 8}, "verbatim_text": "Benedicte",
             "review_state": "pending", "person_creation": "forbidden",
             "candidates": []},
            {"new_record_key": "new-detlev", "source_span": {
                "char_from": 9, "char_to": 54},
             "verbatim_text": "Detlev til Hemmelmark † 1701, havde Sønnerne ...",
             "review_state": "pending", "person_creation": "forbidden",
             "candidates": []},
            {"new_record_key": "new-unknown", "source_span": {
                "char_from": 55, "char_to": 68}, "verbatim_text": "Ukendt person",
             "review_state": "pending", "person_creation": "forbidden",
             "candidates": []},
        ],
        "review_gate": "GO", "identity_decision_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }
    database_preview = {
        "schema_version": "1939-v50-database-preview-v1",
        "canonical_mutations_authorized": False,
        "dry_run_gate": "NO-GO", "reimport_gate": "NO-GO",
        "person_anchors": {
            "matched_count": 3, "missing_count": 0, "collision_count": 0,
            "matched": [
                {"baseline_record_key": "old-already", "person_id": 901},
                {"baseline_record_key": "old-detlev", "person_id": 1137},
                {"baseline_record_key": "old-other", "person_id": 902},
            ],
            "missing_record_keys": [], "collisions": [],
        },
    }
    clean_records = [
        {"record_key": "old-already", "navn": "Benedicte", "facts": []},
        {"record_key": "old-detlev", "navn": "Detlev", "facts": [{
            "faktatype": "død", "date_raw": "4 Nov. 1701"}]},
        {"record_key": "old-other", "navn": "Otto", "facts": [{
            "faktatype": "død", "date_raw": "1618"}]},
    ]
    decisions = [{
        "schema_version": "1939-v50-identity-decisions-v1",
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {"decisions": 1, "same": 1},
        "decisions": [{
            "source_record_key": "new-already",
            "candidate_record_key": "old-already",
            "canonical_person_id": 901,
            "action": "same",
            "database_write_authorized": False,
        }],
        "decision_gate": "GO", "source_persona_materialization_gate": "NO-GO",
        "database_gate": "NO-GO", "reimport_gate": "NO-GO",
    }]
    return {
        "mapped_review": mapped_review,
        "database_preview": database_preview,
        "clean_records": clean_records,
        "identity_decision_batches": decisions,
        "input_hashes": {
            "mapped_review_sha256": "a" * 64,
            "database_preview_sha256": "b" * 64,
            "clean_sha256": "c" * 64,
            "identity_decision_sha256s": ["d" * 64],
        },
    }


def test_qualifies_literal_principal_name_and_death_year():
    profile = profile_row("old-detlev", 1137, "Detlev", "4 Nov. 1701")
    candidate = subject.qualifying_candidate(
        "Detlev til Hemmelmark († 1701), der havde Sønnerne Heinrich ...",
        profile,
    )
    assert candidate["candidate_record_key"] == "old-detlev"
    assert [(row["kind"], row["text"]) for row in candidate["signals"]] == [
        ("literal_name", "Detlev"),
        ("literal_death_year", "1701"),
    ]


@pytest.mark.parametrize("source_text", [
    "Detlev til Hemmelmark, der havde Sønnen Heinrich † 1701.",
    "Detlev til Hemmelmark uden dødsår.",
])
def test_rejects_year_after_transition_or_missing_year(source_text):
    profile = profile_row("old-detlev", 1137, "Detlev", "4 Nov. 1701")
    assert subject.qualifying_candidate(source_text, profile) is None


def test_rejects_name_introduced_after_parent_transition():
    profile = profile_row(
        "old-christian", 1201, "Christian Ditlev", "1 Okt. 1738")
    source_text = (
        "Storkansler Conrad Reventlow havde Sønnen: "
        "Christian Ditlev † 1738.")
    assert subject.qualifying_candidate(source_text, profile) is None


def test_rejects_partial_first_name_when_full_profile_name_differs():
    profile = profile_row(
        "old-christian", 1220, "Christian Detlev", "10 Dec. 1775")
    assert subject.qualifying_candidate(
        "Christian Ditlev til Christianssæde († 1775).", profile) is None


def test_builds_closed_review_with_exact_coverage_and_no_authority():
    result = subject.build_death_year_review(
        **fixture_inputs(), expected_subjects=2, expected_links=1,
        expected_profiles=3)
    assert result["schema_version"] == "1939-v50-death-year-identity-review-v1"
    assert result["counts"] == {
        "subjects": 2, "profiles": 3, "searchable_profiles": 3,
        "unsearchable_profiles": 0, "candidate_links": 1,
        "linked_subjects": 1, "unlinked_subjects": 1,
    }
    assert result["review_only"] is True
    assert result["canonical_mutations_authorized"] is False
    assert result["database_write_authorized"] is False
    assert result["identity_decision_gate"] == "NO-GO"
    assert result["database_gate"] == "NO-GO"
    assert result["reimport_gate"] == "NO-GO"


@pytest.mark.parametrize("mutation", [
    "mapped_schema", "mapped_gate", "decision_write_authority",
    "duplicate_decision_source", "profile_count", "duplicate_person_id",
    "missing_clean_profile", "subject_count", "link_count",
    "ambiguous_candidate", "mapped_profile_count",
])
def test_fails_closed_on_input_drift_or_ambiguity(mutation):
    inputs = copy.deepcopy(fixture_inputs())
    expected_links = 1
    if mutation == "mapped_schema":
        inputs["mapped_review"]["schema_version"] = "unknown"
    elif mutation == "mapped_gate":
        inputs["mapped_review"]["review_gate"] = "NO-GO"
    elif mutation == "decision_write_authority":
        inputs["identity_decision_batches"][0]["database_write_authorized"] = True
    elif mutation == "duplicate_decision_source":
        batch = inputs["identity_decision_batches"][0]
        batch["decisions"].append(copy.deepcopy(batch["decisions"][0]))
        batch["counts"] = {"decisions": 2, "same": 2}
    elif mutation == "profile_count":
        inputs["database_preview"]["person_anchors"]["matched_count"] = 2
    elif mutation == "mapped_profile_count":
        inputs["mapped_review"]["counts"].update({
            "profiles": 4, "searchable_profiles": 4})
    elif mutation == "duplicate_person_id":
        inputs["database_preview"]["person_anchors"]["matched"][2]["person_id"] = 1137
    elif mutation == "missing_clean_profile":
        inputs["clean_records"].pop()
    elif mutation == "subject_count":
        review = inputs["mapped_review"]
        review["subjects"].pop()
        review["counts"].update({"subjects": 2, "unlinked_subjects": 2})
    elif mutation == "link_count":
        expected_links = 2
    elif mutation == "ambiguous_candidate":
        inputs["clean_records"][2].update({
            "navn": "Detlev",
            "facts": [{"faktatype": "død", "date_raw": "1701"}],
        })
    with pytest.raises(subject.DeathYearIdentityReviewError):
        subject.build_death_year_review(
            **inputs, expected_subjects=2, expected_links=expected_links,
            expected_profiles=3)


def test_outputs_are_exclusive_and_byte_deterministic(tmp_path: Path):
    result = subject.build_death_year_review(
        **fixture_inputs(), expected_subjects=2, expected_links=1,
        expected_profiles=3)
    output, report = tmp_path / "review.json", tmp_path / "review.md"
    subject.write_outputs(result, output, report)
    first = output.read_bytes(), report.read_bytes()
    with pytest.raises(FileExistsError):
        subject.write_outputs(result, output, report)
    output.unlink()
    report.unlink()
    subject.write_outputs(result, output, report)
    assert (output.read_bytes(), report.read_bytes()) == first


def test_preserves_declared_nameless_profile_in_coverage_but_not_search():
    inputs = copy.deepcopy(fixture_inputs())
    review = inputs["mapped_review"]
    review["counts"].update({
        "searchable_profiles": 2,
        "unsearchable_profiles": 1,
    })
    review["unsearchable_profile_keys"] = ["old-other"]
    inputs["clean_records"][2]["navn"] = None
    result = subject.build_death_year_review(
        **inputs, expected_subjects=2, expected_links=1,
        expected_profiles=3)
    assert result["counts"]["profiles"] == 3
    assert result["counts"]["searchable_profiles"] == 2
    assert result["counts"]["unsearchable_profiles"] == 1
