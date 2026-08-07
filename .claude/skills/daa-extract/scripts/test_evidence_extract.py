import hashlib
import json
from dataclasses import replace

import pytest

import evidence_extract
from evidence_extract import ExtractionError, complete_batch, load_profile, manifest_payload, prepare_batch, reusable


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


def test_manifest_payload_has_json_stable_record_keys():
    batch = prepare_batch("daa-2018-20-v1", RECORDS, extraction_version="extractor-1")

    payload = manifest_payload(batch)

    assert payload["record_keys"] == ["record-a", "record-b"]
    assert payload == json.loads(json.dumps(payload))


def _bundle():
    text = "Våben: tre roser."
    return {
        "schema_version": "1.1", "source_rendition": [{
            "rendition_id": "rendition-1", "source_id": "2018-20",
            "sha256": hashlib.sha256(text.encode()).hexdigest(), "verbatim_text": text,
        }], "source_records": [],
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


def _anchored_bundle():
    bundle = _bundle()
    bundle["source_records"] = [{"id": "record-1", "record_key": "rk-1", "source_id": "2018-20"}]
    bundle["source_record_anchor_events"] = [{
        "event_id": "anchor-1", "occurrence_id": "occ-1", "source_record_id": "record-1",
        "decision_status": "accepted", "version": 1,
    }]
    return bundle


def two_person_bundle():
    rendition_text = "Anna. Bodil."
    bundle = {
        "schema_version": "1.1",
        "source_rendition": [{
            "rendition_id": "rendition-1", "source_id": "2018-20",
            "sha256": hashlib.sha256(rendition_text.encode()).hexdigest(),
            "verbatim_text": rendition_text,
        }],
        "source_records": [
            {"id": "record-a", "record_key": "rk-a", "source_id": "2018-20"},
            {"id": "record-b", "record_key": "rk-b", "source_id": "2018-20"},
        ],
        "source_record_occurrences": [], "source_record_anchor_events": [],
        "source_record_revision_events": [], "record_placements": [], "persona_placements": [],
        "observations": [], "text_variants": [], "mentions": [], "source_personas": [],
        "extraction_run": {"run_id": "run-1"}, "interpretations": [],
    }
    for suffix, name, start in (("a", "Anna", 0), ("b", "Bodil", 6)):
        end = start + len(name)
        bundle["source_record_occurrences"].append({
            "occurrence_id": "occ-" + suffix, "rendition_id": "rendition-1",
            "extraction_run_id": "run-1", "verbatim_text": name,
            "span": {"rendition_id": "rendition-1", "page_from": 1, "page_to": 1,
                     "char_from": start, "char_to": end, "bbox": None},
        })
        bundle["source_record_anchor_events"].append({
            "event_id": "anchor-" + suffix, "occurrence_id": "occ-" + suffix,
            "source_record_id": "record-" + suffix, "decision_status": "accepted", "version": 1,
        })
        bundle["observations"].append({
            "observation_id": "obs-" + suffix, "occurrence_id": "occ-" + suffix,
            "kind": "person_name", "verbatim_text": name, "extraction_method": "model",
            "extraction_run_id": "run-1",
            "span": {"rendition_id": "rendition-1", "page_from": 1, "page_to": 1,
                     "char_from": start, "char_to": end, "bbox": None},
        })
        bundle["mentions"].append({
            "mention_id": "mention-" + suffix, "observation_id": "obs-" + suffix,
            "char_from": 0, "char_to": len(name), "verbatim_text": name,
        })
        bundle["source_personas"].append({
            "persona_id": "persona-" + suffix, "source_id": "2018-20",
            "mention_ids": ["mention-" + suffix],
        })
    return bundle


def test_person_claim_rejects_another_personas_observation():
    bundle = two_person_bundle()
    with pytest.raises(ExtractionError, match="PERSONA_OBSERVATION"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "person.name", "record_key": "rk-b",
            "source_persona_id": "persona-a", "observation_ids": ["obs-b"],
            "value": "Bodil",
        }]})


def test_granular_claim_requires_observed_evidence_bundle():
    with pytest.raises(ExtractionError, match="EVIDENCE_BUNDLE"):
        validate_output({"claims": [{"predicate": "title.rank", "observation_ids": ["obs-1"], "value": "greve"}]})


def test_granular_claim_rejects_unknown_predicate_and_missing_observation():
    with pytest.raises(ExtractionError, match="PREDICATE"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{"predicate": "made.up", "observation_ids": ["obs-1"], "value": "x"}]})
    with pytest.raises(ExtractionError, match="OBSERVATION"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{"predicate": "heraldry.blazon", "observation_ids": ["missing"], "value": "tre roser"}]})


def test_known_granular_predicates_are_explicit_and_unknown_subtypes_fail_closed():
    bundle = _anchored_bundle()
    expected_predicates = [
        "life_event.birth", "life_event.baptism", "life_event.death", "life_event.burial",
        "relationship.marriage", "relationship.parent", "relationship.child",
        "title.title", "form_of_address.form_of_address", "rank.rank", "office.office",
        "education.education", "estate.estate", "residence.residence",
        "military_service.military_service", "honour.honour", "publication.publication",
        "lineage.introduction", "genealogy.generation_header", "heraldry.blazon",
        "image.caption", "reference.cross_reference",
    ]
    validate_output({"evidence_bundle": bundle, "claims": [{
        "predicate": predicate, "record_key": "rk-1", "observation_ids": ["obs-1"], "value": "x",
    } for predicate in expected_predicates]})

    with pytest.raises(ExtractionError, match="PREDICATE"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "person.invented", "record_key": "rk-1", "source_persona_id": "persona-1",
            "observation_ids": ["obs-1"], "value": "x",
        }]})


def test_non_personal_heraldry_claim_is_valid_without_artificial_persona():
    assert validate_output({"evidence_bundle": _anchored_bundle(), "claims": [{
        "predicate": "heraldry.blazon", "record_key": "rk-1", "observation_ids": ["obs-1"], "value": "tre roser",
    }]}) is None


def test_person_claim_requires_a_source_persona_not_an_invented_person():
    with pytest.raises(ExtractionError, match="PERSONA"):
        validate_output({"evidence_bundle": _anchored_bundle(), "claims": [{
            "predicate": "person.name", "record_key": "rk-1", "observation_ids": ["obs-1"], "value": "Anna",
        }]})


def test_person_claim_accepts_complete_persona_observation_chain():
    bundle = _anchored_bundle()
    text = bundle["observations"][0]["verbatim_text"]
    bundle["source_personas"] = [{
        "persona_id": "persona-1", "source_id": "2018-20", "mention_ids": ["mention-1"],
    }]
    bundle["mentions"] = [{
        "mention_id": "mention-1", "observation_id": "obs-1",
        "char_from": 0, "char_to": len(text), "verbatim_text": text,
    }]
    assert validate_output({"evidence_bundle": bundle, "claims": [{
        "predicate": "person.name", "record_key": "rk-1", "source_persona_id": "persona-1",
        "observation_ids": ["obs-1"], "value": "Anna",
    }]}) is None


def test_claim_record_key_must_name_its_accepted_source_record():
    bundle = _bundle()
    bundle["source_records"] = [{"id": "record-1", "record_key": "rk-1", "source_id": "2018-20"}]
    bundle["source_record_anchor_events"] = [{
        "event_id": "anchor-1", "occurrence_id": "occ-1", "source_record_id": "record-1",
        "decision_status": "accepted", "version": 1,
    }]
    with pytest.raises(ExtractionError, match="RECORD_KEY"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "heraldry.blazon", "record_key": "wrong", "observation_ids": ["obs-1"], "value": "tre roser",
        }]})


def test_every_granular_claim_requires_its_accepted_record_key():
    bundle = _bundle()
    bundle["source_records"] = [{"id": "record-1", "record_key": "rk-1", "source_id": "2018-20"}]
    bundle["source_record_anchor_events"] = [{
        "event_id": "anchor-1", "occurrence_id": "occ-1", "source_record_id": "record-1",
        "decision_status": "accepted", "version": 1,
    }]
    with pytest.raises(ExtractionError, match="RECORD_KEY"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "heraldry.blazon", "observation_ids": ["obs-1"], "value": "tre roser",
        }]})


def test_valid_claim_becomes_proposed_private_interpretation_not_canonical_fact():
    implementation = getattr(evidence_extract, "build_interpretation_candidates", None)
    if implementation is None:
        pytest.fail("build_interpretation_candidates mangler")
    candidates = implementation({"evidence_bundle": _anchored_bundle(), "claims": [{
        "predicate": "heraldry.blazon", "record_key": "rk-1", "observation_ids": ["obs-1"],
        "value": "tre roser", "confidence": 0.8,
    }]}, source_id=1939, extraction_run_id="run-1")
    assert candidates == [{
        "source_id": 1939, "source_persona_id": None, "interpretation_kind": "property",
        "predicate": "heraldry.blazon", "value": "tre roser", "status": "proposed",
        "derivation_kind": "model_inference", "confidence": 0.8, "method": "model",
        "extraction_run_id": "run-1", "record_key": "rk-1", "observation_ids": ["obs-1"],
    }]


def test_unanchored_observation_cannot_bypass_record_key_gate_with_empty_string():
    with pytest.raises(ExtractionError, match="RECORD_KEY"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{
            "predicate": "heraldry.blazon", "record_key": "", "observation_ids": ["obs-1"], "value": "tre roser",
        }]})


def test_claims_reject_legacy_draft_bundle_version():
    bundle = _anchored_bundle()
    bundle["schema_version"] = "1.0"
    with pytest.raises(ExtractionError, match="BUNDLE_VERSION"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "heraldry.blazon", "record_key": "rk-1",
            "observation_ids": ["obs-1"], "value": "tre roser",
        }]})


def test_interpretation_candidate_requires_explicit_model_confidence():
    with pytest.raises(ExtractionError, match="CONFIDENCE"):
        build = getattr(evidence_extract, "build_interpretation_candidates")
        build({"evidence_bundle": _anchored_bundle(), "claims": [{
            "predicate": "heraldry.blazon", "record_key": "rk-1", "observation_ids": ["obs-1"], "value": "tre roser",
        }]}, source_id=1939, extraction_run_id="run-1")
