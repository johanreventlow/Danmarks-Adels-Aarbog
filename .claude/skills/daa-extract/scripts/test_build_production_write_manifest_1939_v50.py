from __future__ import annotations

import hashlib
import json
import uuid

import pytest

from build_production_write_manifest_1939_v50 import ManifestError, _build_manifest


def sha(value):
    return hashlib.sha256((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()).hexdigest()


def fixture():
    key = "record-3766faae-ae21-412a-8cfb-745a19ac77f0"
    source_personas = {
        "schema_version": "1939-v50-source-persona-materialization-v2",
        "new_person_candidates": [{"source_record_key": key, "source_span": {"char_from": 0, "char_to": 9}, "verbatim_sha256": hashlib.sha256(b"1. Ditlev").hexdigest(), "decision": "new_person_candidate", "reason": "verified", "review_status": "codex_verified", "review_sha256": "a"*64, "proposal_evidence_sha256": "b"*64}],
        "counts": {"new_person_candidate": 1}, "database_write_authorized": False,
    }
    identity_review = {"schema_version": "1939-v50-remaining-identity-review-v1", "subjects": [{"new_record_key": key, "source_span": {"char_from": 0, "char_to": 9}, "verbatim_text": "1. Ditlev", "page_evidence": {"page_from": 1, "page_to": 1}}], "database_write_authorized": False}
    identity_decisions = {"schema_version": "1939-v50-remaining-identity-decisions-v1", "counts": {"new_person_candidate": 1, "unresolved": 0}, "decisions": [{"source_record_key": key, "source_span": {"char_from": 0, "char_to": 9}, "verbatim_sha256": hashlib.sha256(b"1. Ditlev").hexdigest(), "decision": "new_person_candidate", "reason": "verified", "review_status": "codex_verified", "review_sha256": "a"*64}], "database_write_authorized": False}
    provenance = {"schema_version": "1939-v50-provenance-decisions-v1", "counts": {"subjects": 1, "unresolved": 0}, "decisions": [{"review_subject_id": "p1", "category": "fact", "source_record_key": "record-x", "canonical_target": {"canonical_person_id": 1}, "disposition": "retain_source_only", "resolution_basis": "safe", "canonical_operations": [], "evidence_sha256": "c"*64}], "production_authorized": False, "database_write_authorized": False}
    preview = {"schema_version": "1939-v50-database-preview-v3", "person_anchors": {"matched_count": 1, "missing_count": 0, "collision_count": 0, "matched": [{"baseline_record_key": "baseline-1", "person_id": 1}]}, "canonical_mutations_authorized": False, "expected_database_changes": {"authorized": False}, "source": {"database_source_id": 3}}
    return source_personas, identity_review, identity_decisions, provenance, preview


def build():
    values = fixture()
    return _build_manifest(*values, input_hashes=[sha(v) for v in values], expected_existing=1, expected_new=1, expected_provenance=1, allowed_new_keys={values[0]["new_person_candidates"][0]["source_record_key"]})


def test_manifest_has_stable_person_create_without_numeric_id():
    out = build()
    create = out["person_creates"][0]
    assert create["source_record_key"].startswith("record-")
    assert "person_id" not in create
    assert create["staged"] is True
    assert create["name"] == "Ditlev"
    assert create["sex"] is None
    assert create["source_persona_id"] == str(uuid.uuid5(uuid.NAMESPACE_URL, f"daa:source-persona:1939:{create['source_record_key']}"))
    assert out["counts"]["existing_anchors"] == 1
    assert out["production_authorized"] is False


def test_source_only_decision_only_emits_private_evidence():
    out = build()
    assert [x["dependency_class"] for x in out["operations"]] == ["source_evidence", "person_create"]
    assert out["canonical_delta"] == []


@pytest.mark.parametrize("index,mutate", [
    (0, lambda x: x.update(database_write_authorized=True)),
    (1, lambda x: x["subjects"][0].update(verbatim_text="drift")),
    (2, lambda x: x["counts"].update(unresolved=1)),
    (3, lambda x: x["decisions"][0].update(disposition="unresolved")),
    (4, lambda x: x["person_anchors"]["matched"].append({"baseline_record_key": "b2", "person_id": 2})),
])
def test_drift_fails_closed(index, mutate):
    values = list(fixture())
    hashes = [sha(v) for v in values]
    mutate(values[index])
    with pytest.raises(ManifestError):
        _build_manifest(*values, input_hashes=hashes, expected_existing=1, expected_new=1, expected_provenance=1, allowed_new_keys={"record-3766faae-ae21-412a-8cfb-745a19ac77f0"})
