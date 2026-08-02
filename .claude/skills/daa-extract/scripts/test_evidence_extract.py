from dataclasses import replace

import pytest

from evidence_extract import ExtractionError, complete_batch, load_profile, prepare_batch, reusable


RECORDS = [{"record_key": "record-a", "raw": "Født 1801."}, {"record_key": "record-b", "raw": "Gift 1820."}]


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
