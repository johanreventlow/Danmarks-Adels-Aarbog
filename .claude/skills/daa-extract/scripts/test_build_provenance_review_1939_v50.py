from __future__ import annotations

import copy
import hashlib
import json

import pytest

import build_provenance_review_1939_v50 as subject


def _hashes() -> dict[str, str]:
    return {
        "boundary_materialization_sha256": "a" * 64,
        "calamari_sha256": "b" * 64,
        "database_preview_sha256": "c" * 64,
        "database_profiles_sha256": "d" * 64,
        "import_preview_sha256": "e" * 64,
        "reconciliation_sha256": "f" * 64,
        "remaining_decisions_sha256": "1" * 64,
        "source_persona_v2_sha256": "2" * 64,
    }


def fixture_inputs() -> dict:
    source_text = "Anna, f. 1800, g. 1820; 2 børn: næste slægtled nr. 3-4.\n"
    source_span = {"char_from": 10, "char_to": 10 + len(source_text)}
    mapped = {
        "baseline_record_key": "old-a",
        "new_record_key": "record-a",
        "legacy_name": "Anna",
        "narrative_change": {"authorized": False, "changed": True,
                             "legacy_sha256": "3" * 64, "source_sha256": "4" * 64},
        "fact_candidates": [
            {"authorized": False, "provenance_status": "missing_provenance",
             "legacy_payload": {"faktatype": "begravelse", "kilde_span": None,
                                "sted": "Kirken"}},
            {"authorized": False, "provenance_status": "nonliteral_provenance",
             "legacy_payload": {"faktatype": "fødsel", "date_raw": "1800",
                                "kilde_span": "født 1800"}},
        ],
        "marriage_candidates": [
            {"authorized": False, "provenance_status": "nonliteral_provenance",
             "legacy_payload": {"ordinal": 1, "partner_navn": "Bent",
                                "dato_raw": "1820", "kilde_span": "gift 1820"}},
        ],
        "relationship_candidates": [
            {"authorized": False,
             "provenance_status": "legacy_structure_pending_revalidation",
             "kind": "children_reference", "legacy_payload": {"nr_range": [3, 4]}},
        ],
    }
    import_preview = {
        "schema_version": "1939-v50-import-preview-v1",
        "preview_gate": "GO", "reimport_gate": "NO-GO",
        "canonical_mutations_authorized": False,
        "source": {"edition": "1939", "source_id": "1939",
                   "rendition_id": "daa-1939-calamari-r6-clean",
                   "input_hashes": {"calamari_sha256": "b" * 64,
                                    "reconciliation_sha256": "f" * 64,
                                    "materialization_sha256": "a" * 64}},
        "counts": {"mapped_existing": 1,
                   "facts": {"missing_provenance": 1, "nonliteral_provenance": 1},
                   "marriages": {"missing_provenance": 0, "nonliteral_provenance": 1},
                   "relationships": {"legacy_structure_pending_revalidation": 1}},
        "mapped_existing": [mapped],
        "source_records": [{"new_record_key": "record-a", "source_span": source_span,
                            "verbatim_text": source_text}],
    }
    source_persona_v2 = {
        "schema_version": "1939-v50-source-persona-materialization-v2",
        "counts": {"source_personas": 0, "new_person_candidate": 1,
                   "structural_or_summary": 0, "unresolved": 0},
        "source": {"edition": "1939", "logical_source_id": "1939",
                   "database_source_id": 3, "input_hashes": {}},
        "source_personas": [], "new_person_candidates": [{"source_record_key": "record-new"}],
        "structural_or_summary": [], "unresolved": [],
        "canonical_mutations_authorized": False,
        "database_write_authorized": False, "reimport_gate": "NO-GO",
    }
    remaining_decisions = {
        "schema_version": "1939-v50-remaining-identity-decisions-v1",
        "decision_gate": "GO", "database_write_authorized": False,
        "canonical_mutations_authorized": False, "reimport_gate": "NO-GO",
        "counts": {"decisions": 1, "same_existing_person": 0,
                   "new_person_candidate": 1, "structural_or_summary": 0,
                   "unresolved": 0},
        "decisions": [{"source_record_key": "record-new",
                       "decision": "new_person_candidate"}],
    }
    database_preview = {
        "schema_version": "1939-v50-database-preview-v3",
        "database": {"database_name": "postgres", "transaction_read_only": "on"},
        "source": {"id": 3, "udgave": "DAA 1939", "import_key": "daa:1939"},
        "input_preview": {"schema_version": "1939-v50-import-preview-v1",
                          "sha256": "e" * 64, "input_hashes": {}},
        "person_anchors": {"matched_count": 1, "missing_count": 0,
                           "collision_count": 0,
                           "matched": [{"baseline_record_key": "old-a", "person_id": 101}]},
        "source_personas": {"new_person_candidate_count": 1,
                            "unresolved_count": 0, "target_mismatch_count": 0},
        "canonical_mutations_authorized": False, "reimport_gate": "NO-GO",
    }
    database_profiles = {
        "schema_version": "1939-v50-provenance-db-profiles-v1",
        "input": {"database_preview_sha256": "c" * 64,
                  "import_preview_sha256": "e" * 64,
                  "declared_record_keys": ["old-a"]},
        "database": {"database_name": "postgres", "transaction_read_only": "on",
                     "source_id": 3},
        "counts": {"profiles": 1},
        "profiles": [{
            "record_key": "old-a", "person_id": 101, "display_name": "Anna",
            "staged": False, "narratives": [],
            "facts": [{"fact_id": 301, "fact_type": "fødsel", "assertion_id": 401,
                       "raw_value": "1800", "citation": {"citation_id": 501,
                       "text": "f. 1800", "page": "10"}, "editorial_events": 0}],
            "relations": [{"relation_id": 601, "role": "ejer",
                           "subject_person_id": 101, "subject_display_name": "Anna",
                           "object_person_id": 901, "object_display_name": None,
                           "assertion_id": 701, "raw_value": None,
                           "citation": {"citation_id": 801, "text": "til Gaarden",
                                        "page": "10"}, "editorial_events": 0}],
            "families": [{"family_id": 1001, "members": [
                {"person_id": 101, "role": "partner", "display_name": "Anna",
                 "editorial_events": 0},
                {"person_id": 102, "role": "partner", "display_name": "Bent",
                 "editorial_events": 0}],
                "facts": [{"fact_id": 1101, "fact_type": "vielse",
                           "assertion_id": 1201, "raw_value": "1820",
                           "citation": {"citation_id": 1301, "text": "g. 1820",
                                        "page": "10"}, "editorial_events": 0}]}],
        }],
        "review_only": True, "database_write_authorized": False,
        "canonical_mutations_authorized": False,
    }
    reconciliation = {
        "schema_version": "1.0", "source": {"edition": "1939",
        "calamari_sha256": "b" * 64},
        "report": {"baseline_total": 1, "new_total": 1,
                   "remaining_baseline_review": 0, "remaining_new_review": 0,
                   "reconciliation_gate": "GO"},
        "baseline_entries": [{}], "new_entries": [{}], "decision_source": {},
    }
    boundary_materialization = {
        "schema_version": "1.0", "source_record_review": {
            "schema_version": "1.0", "source_id": "1939",
            "rendition_id": "daa-1939-calamari-r6-clean", "rendition_sha256": "b" * 64,
            "records": [{"acceptance_id": "accept-a", "record_kind": "unclassified",
                         "decision_status": "accepted", "reviewed_by": "tester",
                         "decision_version": 1, "verbatim_text": source_text,
                         "span": {"page_from": 503, "page_to": 503,
                                  "char_from": 0, "char_to": len(source_text), "bbox": None},
                         "source_anchor": source_span}],
        }}
    calamari_text = " " * 10 + source_text
    return {
        "import_preview": import_preview, "source_persona_v2": source_persona_v2,
        "remaining_decisions": remaining_decisions,
        "database_preview": database_preview, "database_profiles": database_profiles,
        "reconciliation": reconciliation,
        "boundary_materialization": boundary_materialization,
        "calamari_text": calamari_text, "input_hashes": _hashes(),
        "expected_facts": 2, "expected_marriages": 1,
        "expected_relationships": 1, "expected_profiles": 1,
        "expected_new_persons": 1,
    }


def test_builds_exact_coverage_source_order_and_review_context():
    result = subject._build_provenance_review(**fixture_inputs())
    assert result["counts"] == {
        "facts": 2, "marriages": 1, "relationships": 1, "subjects": 4,
        "mapped_profiles": 1, "new_person_candidates": 1,
    }
    assert [row["category"] for row in result["subjects"]] == [
        "fact", "fact", "marriage", "relationship"]
    assert len({row["review_subject_id"] for row in result["subjects"]}) == 4
    fact = result["subjects"][1]
    assert fact["source_record_key"] == "record-a"
    assert fact["page_evidence"] == {"page_from": 503, "page_to": 503}
    assert fact["canonical_target"] == {
        "baseline_record_key": "old-a", "canonical_person_id": 101,
        "display_name": "Anna", "staged": False,
    }
    assert fact["database_context"] == fixture_inputs()["database_profiles"]["profiles"][0]["facts"]
    assert fact["evidence_signals"] == [{
        "kind": "literal_raw_value", "text": "1800", "source_start": 9,
        "source_end": 13, "authoritative": False,
    }]
    assert all(row["proposed_disposition"] == "unresolved" for row in result["subjects"])
    assert result["review_gate"] == "GO"
    assert result["decision_gate"] == "NO-GO"
    assert result["database_write_authorized"] is False
    assert result["canonical_mutations_authorized"] is False


@pytest.mark.parametrize("mutation", [
    "fact_count", "marriage_count", "relationship_count", "profile_count",
    "duplicate_profile", "calamari_drift", "boundary_drift", "target_drift",
    "database_profile_hash", "new_person_count", "write_authority",
    "candidate_extra_field",
])
def test_fails_closed_on_coverage_lineage_target_or_authority_drift(mutation):
    values = fixture_inputs()
    if mutation == "fact_count":
        values["expected_facts"] = 3
    elif mutation == "marriage_count":
        values["expected_marriages"] = 2
    elif mutation == "relationship_count":
        values["expected_relationships"] = 2
    elif mutation == "profile_count":
        values["expected_profiles"] = 2
    elif mutation == "duplicate_profile":
        values["database_profiles"]["profiles"].append(
            copy.deepcopy(values["database_profiles"]["profiles"][0]))
        values["database_profiles"]["counts"]["profiles"] = 2
    elif mutation == "calamari_drift":
        values["calamari_text"] = values["calamari_text"].replace("Anna", "Anne")
    elif mutation == "boundary_drift":
        values["boundary_materialization"]["source_record_review"]["records"][0][
            "verbatim_text"] = "drift"
    elif mutation == "target_drift":
        values["database_preview"]["person_anchors"]["matched"][0]["person_id"] = 999
    elif mutation == "database_profile_hash":
        values["database_profiles"]["input"]["database_preview_sha256"] = "9" * 64
    elif mutation == "new_person_count":
        values["expected_new_persons"] = 2
    elif mutation == "write_authority":
        values["source_persona_v2"]["database_write_authorized"] = True
    elif mutation == "candidate_extra_field":
        values["import_preview"]["mapped_existing"][0]["fact_candidates"][0]["extra"] = True
    with pytest.raises(subject.ProvenanceReviewError):
        subject._build_provenance_review(**values)


def test_public_builder_locks_production_universe():
    assert "expected_facts" not in subject.build_provenance_review.__annotations__
    assert subject.PRODUCTION_COUNTS == (130, 94, 81, 543, 8)


def test_retired_source_candidates_are_not_provenance_review_subjects():
    values = fixture_inputs()
    values["import_preview"]["mapped_existing"][0]["fact_candidates"].append({
        "authorized": False, "provenance_status": "retired_source_record",
        "legacy_payload": {"faktatype": "navn", "kilde_span": "Anna"},
    })
    result = subject._build_provenance_review(**values)
    assert result["counts"]["subjects"] == 4


def test_already_literal_candidates_are_not_parked_review_subjects():
    values = fixture_inputs()
    values["import_preview"]["mapped_existing"][0]["fact_candidates"].append({
        "authorized": False, "provenance_status": "source_bound_literal",
        "legacy_payload": {"faktatype": "navn", "kilde_span": "Anna"},
    })
    result = subject._build_provenance_review(**values)
    assert result["counts"]["subjects"] == 4


def test_output_is_exclusive_and_hash_bound(tmp_path):
    result = subject._build_provenance_review(**fixture_inputs())
    output = tmp_path / "review.json"
    report = tmp_path / "review.md"
    subject.write_outputs(result, output, report)
    parsed = json.loads(output.read_text())
    assert parsed["input_hashes"] == dict(sorted(_hashes().items()))
    assert hashlib.sha256(output.read_bytes()).hexdigest()
    with pytest.raises(FileExistsError):
        subject.write_outputs(result, output, tmp_path / "other.md")
