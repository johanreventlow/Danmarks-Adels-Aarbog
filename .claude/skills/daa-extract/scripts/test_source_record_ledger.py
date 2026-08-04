import copy

import pytest

from evidence_contract import validate_bundle
from evidence_extract import prepare_batch
from source_record_ledger import LedgerError, batch_records, materialize


TEXT = "Født 1801."


def accepted(acceptance_id="accept-1", **overrides):
    value = {
        "acceptance_id": acceptance_id,
        "record_kind": "person",
        "decision_status": "accepted",
        "reviewed_by": "editor-1",
        "decision_version": 1,
        "verbatim_text": TEXT,
        "span": {
            "page_from": 101,
            "page_to": 101,
            "char_from": 0,
            "char_to": len(TEXT),
            "bbox": None,
        },
    }
    value.update(overrides)
    return value


def review(*, source_id="2018-20", records=None):
    return {
        "schema_version": "1.0",
        "source_id": source_id,
        "rendition_id": "rendition-2018-pdftext-v1",
        "rendition_sha256": "a" * 64,
        "extraction_run_id": "segmentation-1",
        "records": records if records is not None else [accepted()],
    }


def empty_ledger():
    return {"schema_version": "1.0", "entries": []}


def test_materialize_mints_opaque_key_once_and_is_idempotent():
    first_ledger, first_bundle = materialize(review(), empty_ledger())
    second_ledger, second_bundle = materialize(review(), first_ledger)

    assert first_ledger == second_ledger
    assert first_bundle == second_bundle
    assert first_bundle["source_records"][0]["record_key"].startswith("record-")
    assert "101" not in first_bundle["source_records"][0]["record_key"]


def test_materialize_rejects_changed_text_for_known_acceptance_without_mutating_ledger():
    ledger, _ = materialize(review(), empty_ledger())
    ledger_before = copy.deepcopy(ledger)

    with pytest.raises(LedgerError, match="drift"):
        materialize(review(records=[accepted(verbatim_text="Ændret tekst.", span={
            "page_from": 101, "page_to": 101, "char_from": 0, "char_to": 13, "bbox": None,
        })]), ledger)

    assert ledger == ledger_before


def test_materialize_rejects_changed_absolute_source_anchor_for_known_acceptance():
    record = accepted(source_anchor={"char_from": 100, "char_to": 112})
    ledger, _ = materialize(review(records=[record]), empty_ledger())

    with pytest.raises(LedgerError, match="drift"):
        materialize(review(records=[accepted(source_anchor={"char_from": 101, "char_to": 113})]), ledger)


def test_materialize_rejects_duplicate_acceptance_id():
    with pytest.raises(LedgerError, match="duplicate acceptance"):
        materialize(review(records=[accepted("accept-1"), accepted("accept-1")]), empty_ledger())


def test_materialize_rejects_nonaccepted_record():
    with pytest.raises(LedgerError, match="accepted"):
        materialize(review(records=[accepted(decision_status="proposed")]), empty_ledger())


def test_materialize_rejects_existing_acceptance_in_another_edition():
    ledger, _ = materialize(review(source_id="2018-20"), empty_ledger())

    with pytest.raises(LedgerError, match="drift"):
        materialize(review(source_id="1939"), ledger)


def test_materialize_returns_a_contract_valid_bundle():
    _, bundle = materialize(review(), empty_ledger())

    assert validate_bundle(bundle) is None
    assert bundle["source_record_anchor_events"][0]["decision_status"] == "accepted"


def test_batch_records_bind_verbatim_text_to_the_accepted_record_key():
    _, bundle = materialize(review(), empty_ledger())

    records = batch_records(bundle)
    batch = prepare_batch("daa-2018-20-v1", records, extraction_version="ledger-1")
    changed = prepare_batch("daa-2018-20-v1", [
        {**records[0], "verbatim_text": "ændret"},
    ], extraction_version="ledger-1")

    assert records == [{
        "record_key": bundle["source_records"][0]["record_key"],
        "verbatim_text": TEXT,
    }]
    assert batch.input_hash != changed.input_hash
