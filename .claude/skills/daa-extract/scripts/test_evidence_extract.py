from dataclasses import replace

import pytest

import evidence_extract
from evidence_extract import ExtractionError, complete_batch, load_profile, prepare_batch, reusable


RECORDS = [{"record_key": "record-a", "raw": "Født 1801."}, {"record_key": "record-b", "raw": "Gift 1820."}]


def validate_output(*args, **kwargs):
    implementation = getattr(evidence_extract, "validate_output", None)
    if implementation is None:
        pytest.fail("validate_output mangler")
    return implementation(*args, **kwargs)


def test_profiles_pin_terra_and_sol_without_ambient_settings(monkeypatch):
    monkeypatch.setenv("MODEL", "anything-else")
    batch = prepare_batch("daa-1939-v1", RECORDS, extraction_version="extractor-1")
    assert batch.effective_model_id == "gpt-5.6-terra"
    assert batch.prompt_version == load_profile("daa-1939-v1")["prompt_version"]


def test_sol_requires_explicit_escalation_gate():
    with pytest.raises(ExtractionError, match="ESCALATION"):
        prepare_batch("daa-1939-v1", RECORDS, extraction_version="extractor-1", escalate=True)
    assert prepare_batch("daa-1939-v1", RECORDS, extraction_version="extractor-1", escalate=True,
                         escalation_reason="unreadable structural header").effective_model_id == "gpt-5.6-sol"


def test_batch_rejects_missing_or_duplicate_record_key():
    with pytest.raises(ExtractionError, match="RECORD_KEYS"):
        prepare_batch("daa-1939-v1", [{"record_key": ""}], extraction_version="extractor-1")
    with pytest.raises(ExtractionError, match="RECORD_KEYS"):
        prepare_batch("daa-1939-v1", [RECORDS[0], RECORDS[0]], extraction_version="extractor-1")


def test_partial_output_never_becomes_green_or_reusable():
    pending = prepare_batch("daa-1939-v1", RECORDS, extraction_version="extractor-1")
    with pytest.raises(ExtractionError, match="PARTIAL"):
        complete_batch(pending, {"record_keys": ["record-a"], "partial": True}, token_count=1, cost_usd=0.01)


def test_only_identical_green_batch_is_reusable():
    pending = prepare_batch("daa-2018-20-v1", RECORDS, extraction_version="extractor-1")
    green = complete_batch(pending, {"record_keys": ["record-a", "record-b"], "observations": []}, token_count=5, cost_usd=0.02)
    assert reusable(green, pending)
    assert not reusable(green, replace(pending, input_hash="changed"))


def _bundle():
    text = "Våben: tre roser."
    return {
        "schema_version": "1.0", "source_rendition": [], "source_records": [],
        "source_record_anchor_events": [], "source_record_revision_events": [],
        "record_placements": [], "persona_placements": [], "text_variants": [],
        "mentions": [], "source_personas": [], "extraction_run": {"run_id": "run-1"},
        "source_record_occurrences": [{
            "occurrence_id": "occ-1", "rendition_id": "rendition-1", "extraction_run_id": "run-1",
            "verbatim_text": text, "span": {"rendition_id": "rendition-1", "page_from": 1, "page_to": 1,
                "char_from": 0, "char_to": len(text), "bbox": None},
        }],
        "observations": [{
            "observation_id": "obs-1", "occurrence_id": "occ-1", "kind": "heraldry_clause",
            "verbatim_text": text, "extraction_method": "model", "extraction_run_id": "run-1",
            "span": {"rendition_id": "rendition-1", "page_from": 1, "page_to": 1,
                "char_from": 0, "char_to": len(text), "bbox": None},
        }],
    }


def test_granular_claim_requires_observed_evidence_bundle():
    with pytest.raises(ExtractionError, match="EVIDENCE_BUNDLE"):
        validate_output({"claims": [{"predicate": "title.rank", "observation_ids": ["obs-1"], "value": "greve"}]})


def test_granular_claim_rejects_unknown_predicate_and_missing_observation():
    with pytest.raises(ExtractionError, match="PREDICATE"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{"predicate": "made.up", "observation_ids": ["obs-1"], "value": "x"}]})
    with pytest.raises(ExtractionError, match="OBSERVATION"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{"predicate": "heraldry.blazon", "observation_ids": ["missing"], "value": "tre roser"}]})


def test_non_personal_heraldry_claim_is_valid_without_artificial_persona():
    assert validate_output({"evidence_bundle": _bundle(), "claims": [{
        "predicate": "heraldry.blazon", "observation_ids": ["obs-1"], "value": "tre roser",
    }]}) is None


def test_person_claim_requires_a_source_persona_not_an_invented_person():
    with pytest.raises(ExtractionError, match="PERSONA"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{
            "predicate": "person.name", "observation_ids": ["obs-1"], "value": "Anna",
        }]})


def test_person_claim_requires_persona_traceable_to_an_accepted_record():
    bundle = _bundle()
    bundle["source_personas"] = [{"persona_id": "persona-1"}]
    with pytest.raises(ExtractionError, match="PERSONA_RECORD"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "person.name", "source_persona_id": "persona-1",
            "observation_ids": ["obs-1"], "value": "Anna",
        }]})

    bundle["source_personas"] = [{"persona_id": "persona-1", "mention_ids": ["mention-1"]}]
    bundle["mentions"] = [{"mention_id": "mention-1", "observation_id": "obs-1"}]
    bundle["source_record_anchor_events"] = [{
        "event_id": "anchor-1", "occurrence_id": "occ-1", "source_record_id": "record-1",
        "decision_status": "accepted", "version": 1,
    }]
    assert validate_output({"evidence_bundle": bundle, "claims": [{
        "predicate": "person.name", "source_persona_id": "persona-1",
        "observation_ids": ["obs-1"], "value": "Anna",
    }]}) is None
