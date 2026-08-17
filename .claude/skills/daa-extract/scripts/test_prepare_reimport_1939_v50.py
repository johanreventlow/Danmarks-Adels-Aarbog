from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

import pytest

import prepare_reimport_1939_v50 as subject


PreviewError = subject.PreviewError


def sha(value: bytes | str) -> str:
    if isinstance(value, str):
        value = value.encode("utf-8")
    return hashlib.sha256(value).hexdigest()


def fixture_inputs():
    calamari = "Anna blev født 1700.\nSlægtsoversigt\nSe nr. 2.\nBent døde 1800.\n"
    records = [
        ("accept-a", "new-a", 0, 23, "unclassified"),
        ("accept-s", "new-s", 23, 39, "structural_context"),
        ("accept-x", "new-x", 39, 49, "unclassified"),
        ("accept-b", "new-b", 49, len(calamari), "unclassified"),
    ]
    materialized = []
    ledger_entries = []
    for acceptance_id, record_key, start, end, kind in records:
        materialized.append({
            "acceptance_id": acceptance_id,
            "record_kind": kind,
            "decision_status": "accepted",
            "reviewed_by": "reviewer",
            "decision_version": 1,
            "verbatim_text": calamari[start:end],
            "span": {"page_from": 1, "page_to": 1, "char_from": 0,
                     "char_to": end - start, "bbox": None},
            "source_anchor": {"char_from": start, "char_to": end},
        })
        ledger_entries.append({
            "acceptance_id": acceptance_id,
            "record_key": record_key,
            "immutable": sha(f"{acceptance_id}:{record_key}"),
        })

    baseline_entries = [
        {
            "baseline_record_key": "old-a",
            "name": "Anna",
            "matches": [{"new_record_key": "new-a", "geometry_relation": "exact_span"}],
            "disposition": "unchanged",
        },
        {
            "baseline_record_key": "old-retired",
            "name": "Fragment",
            "matches": [],
            "disposition": "retired_fragment",
            "canonical_baseline_record_key": "old-a",
            "retirement_reason": "continuation_extraction_fragment",
            "reviewed_by": "reviewer",
            "decision_batch": "batch",
        },
    ]
    new_entries = [
        {
            "new_record_key": "new-a",
            "record_kind": "unclassified",
            "source_span": {"char_from": 0, "char_to": 23},
            "baseline_record_keys": ["old-a"],
            "disposition": "unchanged",
        },
        {
            "new_record_key": "new-s",
            "record_kind": "structural_context",
            "source_span": {"char_from": 23, "char_to": 39},
            "baseline_record_keys": [],
            "disposition": "accepted_structural_context",
        },
        {
            "new_record_key": "new-x",
            "record_kind": "cross_reference",
            "source_span": {"char_from": 39, "char_to": 49},
            "baseline_record_keys": [],
            "disposition": "accepted_cross_reference",
            "human_annotation": {
                "new_record_key": "new-x",
                "record_kind": "cross_reference",
                "person_creation": "forbidden_without_separate_evidence",
            },
        },
        {
            "new_record_key": "new-b",
            "record_kind": "unclassified",
            "source_span": {"char_from": 49, "char_to": len(calamari)},
            "baseline_record_keys": [],
            "disposition": "accepted_genuinely_new_source_record",
            "acceptance_basis": "human_verified_genuinely_new_source_record",
            "reviewed_by": "reviewer",
            "decision_batch": "batch",
        },
    ]
    embedded_report = {
        "baseline_total": 2,
        "new_total": 4,
        "applied_decisions": 1,
        "accepted_carryovers": 0,
        "retired_duplicates": 0,
        "retired_fragments": 1,
        "baseline_dispositions": {"retired_fragment": 1, "unchanged": 1},
        "new_dispositions": {
            "accepted_cross_reference": 1,
            "accepted_genuinely_new_source_record": 1,
            "accepted_structural_context": 1,
            "unchanged": 1,
        },
        "remaining_baseline_review": 0,
        "remaining_new_review": 0,
        "reconciliation_gate": "GO",
    }
    reconciliation = {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "baseline_sha256": "b" * 64,
            "calamari_sha256": sha(calamari),
        },
        "decision_source": {
            "reconciliation_sha256": "c" * 64,
            "reviewed_by": "reviewer",
            "decision_batch": "batch",
        },
        "baseline_entries": baseline_entries,
        "new_entries": new_entries,
        "report": embedded_report,
    }
    materialization = {
        "schema_version": "1.0",
        "report": {
            "materialization_gate": "GO",
            "cut_intervals": 4,
            "accepted_record_candidates": 4,
            "omitted_intervals": 0,
            "unresolved_intervals": 0,
            "structural_record_candidates": 1,
        },
        "source_record_review": {
            "schema_version": "1.0",
            "source_id": "daa-1939",
            "rendition_id": "calamari-test",
            "extraction_run_id": "test-run",
            "rendition_sha256": sha(calamari),
            "rendition_text": calamari,
            "records": materialized,
        },
    }
    ledger = {"schema_version": "1.0", "entries": ledger_entries}
    clean = [
        {
            "record_key": "old-a",
            "navn": "Anna",
            "narrative": "Anna blev født 1700.",
            "facts": [
                {"faktatype": "fødsel", "date_raw": "1700",
                 "kilde_span": "født 1700"},
                {"faktatype": "note", "vaerdi": "normaliseret",
                 "kilde_span": "ikke ordret"},
                {"faktatype": "ukendt", "kilde_span": None},
            ],
            "aegteskaber": [
                {"ordinal": 1, "partner_navn": "Else", "kilde_span": "Anna"},
                {"ordinal": 2, "partner_navn": "Mette", "kilde_span": ""},
            ],
            "boern": {"nr_range": [2, 3]},
        },
        {
            "record_key": "old-retired",
            "navn": "Fragment",
            "narrative": "Fragment",
            "facts": [{"faktatype": "note", "kilde_span": "Fragment"}],
            "aegteskaber": [],
            "boern": None,
        },
    ]
    input_hashes = {
        "reconciliation_sha256": sha(json.dumps(reconciliation, sort_keys=True)),
        "reconciliation_report_sha256": sha(json.dumps(embedded_report, sort_keys=True)),
        "ledger_sha256": sha(json.dumps(ledger, sort_keys=True)),
        "materialization_sha256": sha(json.dumps(materialization, sort_keys=True)),
        "clean_sha256": sha(json.dumps(clean, sort_keys=True)),
        "calamari_sha256": sha(calamari),
    }
    expected_counts = {
        "mapped_existing": 1,
        "retired_legacy": 1,
        "genuinely_new_pending": 1,
        "source_only_structural": 1,
        "source_only_cross_reference": 1,
        "source_records": 4,
    }
    return {
        "reconciliation": reconciliation,
        "reconciliation_report": copy.deepcopy(embedded_report),
        "ledger": ledger,
        "materialization": materialization,
        "clean": clean,
        "calamari_text": calamari,
        "input_hashes": input_hashes,
        "expected_counts": expected_counts,
    }


def build(values=None):
    return subject.build_import_preview(**(values or fixture_inputs()))


def test_builds_closed_preview_without_authorizing_canonical_mutations():
    result = build()

    assert result["schema_version"] == "1939-v50-import-preview-v1"
    assert result["canonical_mutations_authorized"] is False
    assert result["counts"] == fixture_inputs()["expected_counts"] | {
        "facts": {
            "source_bound_literal": 1,
            "nonliteral_provenance": 1,
            "missing_provenance": 1,
            "retired_source_record": 1,
        },
        "marriages": {
            "source_bound_literal": 1,
            "missing_provenance": 1,
            "nonliteral_provenance": 0,
            "retired_source_record": 0,
        },
        "relationships": {"legacy_structure_pending_revalidation": 1},
    }
    assert len(result["source_records"]) == 4
    assert result["mapped_existing"][0]["baseline_record_key"] == "old-a"
    assert result["genuinely_new_pending"][0]["person_creation"] == "forbidden"
    assert result["source_only_records"][0]["person_creation"] == "forbidden"
    assert result["expected_database_changes"]["canonical_person_creates"] == []


def test_classifies_claim_provenance_against_exact_target_verbatim():
    mapped = build()["mapped_existing"][0]

    assert [row["provenance_status"] for row in mapped["fact_candidates"]] == [
        "source_bound_literal", "nonliteral_provenance", "missing_provenance"
    ]
    assert [row["provenance_status"] for row in mapped["marriage_candidates"]] == [
        "source_bound_literal", "missing_provenance"
    ]
    assert mapped["relationship_candidates"] == [{
        "kind": "children_reference",
        "legacy_payload": {"nr_range": [2, 3]},
        "provenance_status": "legacy_structure_pending_revalidation",
        "authorized": False,
    }]


@pytest.mark.parametrize("field", [
    "reconciliation_sha256", "reconciliation_report_sha256", "ledger_sha256",
    "materialization_sha256", "clean_sha256", "calamari_sha256",
])
def test_rejects_invalid_or_missing_input_hashes(field):
    values = fixture_inputs()
    values["input_hashes"][field] = "not-a-sha"

    with pytest.raises(PreviewError, match="SHA-256"):
        build(values)


def test_rejects_report_drift():
    values = fixture_inputs()
    values["reconciliation_report"]["new_total"] = 5

    with pytest.raises(PreviewError, match="report"):
        build(values)


def test_rejects_duplicate_or_inconsistent_ownership():
    values = fixture_inputs()
    values["reconciliation"]["new_entries"][0]["baseline_record_keys"] = [
        "old-a", "old-retired"
    ]

    with pytest.raises(PreviewError, match="ejer|owner"):
        build(values)


def test_rejects_materialized_span_or_verbatim_drift():
    values = fixture_inputs()
    values["materialization"]["source_record_review"]["records"][0][
        "source_anchor"
    ]["char_to"] -= 1

    with pytest.raises(PreviewError, match="span|verbatim|materialisering"):
        build(values)


def test_rejects_unknown_top_level_fields():
    values = fixture_inputs()
    values["reconciliation"]["surprise"] = True

    with pytest.raises(PreviewError, match="ukendte felter"):
        build(values)


def test_rejects_count_drift_even_when_input_is_otherwise_consistent():
    values = fixture_inputs()
    values["expected_counts"]["mapped_existing"] = 2

    with pytest.raises(PreviewError, match="counts|optælling"):
        build(values)


def test_write_outputs_is_exclusive_and_cleans_partial_failure(tmp_path: Path):
    bundle_path = tmp_path / "preview.json"
    report_path = tmp_path / "preview.md"
    subject.write_preview_outputs(build(), bundle_path, report_path)

    first_bundle = bundle_path.read_bytes()
    first_report = report_path.read_bytes()
    with pytest.raises(FileExistsError):
        subject.write_preview_outputs(build(), bundle_path, report_path)
    assert bundle_path.read_bytes() == first_bundle
    assert report_path.read_bytes() == first_report

    partial_bundle = tmp_path / "partial.json"
    occupied_report = tmp_path / "occupied.md"
    occupied_report.write_text("keep", encoding="utf-8")
    with pytest.raises(FileExistsError):
        subject.write_preview_outputs(build(), partial_bundle, occupied_report)
    assert not partial_bundle.exists()
    assert occupied_report.read_text(encoding="utf-8") == "keep"
