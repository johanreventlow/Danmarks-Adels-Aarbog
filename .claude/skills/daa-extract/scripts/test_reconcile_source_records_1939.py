from __future__ import annotations

import hashlib
import json

import pytest

import reconcile_source_records_1939 as subject


ReconciliationError = subject.ReconciliationError
build_reconciliation = subject.build_reconciliation


def inputs(*, text="1. Anna\n2. Bent\n", spans=None, baseline=None, evidence=None):
    source_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
    spans = spans or [(0, 8, "accept-a", "new-a"), (8, len(text), "accept-b", "new-b")]
    records = []
    ledger_entries = []
    for start, end, acceptance_id, record_key in spans:
        records.append({
            "acceptance_id": acceptance_id,
            "record_kind": "unclassified",
            "verbatim_text": text[start:end],
            "source_anchor": {"char_from": start, "char_to": end},
        })
        ledger_entries.append({
            "acceptance_id": acceptance_id,
            "record_key": record_key,
            "immutable": "a" * 64,
        })
    baseline = baseline or [
        {"record_key": "old-a", "navn": "Anna", "narrative": "1. Anna\n"},
        {"record_key": "old-b", "navn": "Bent", "narrative": "2. Bent\n"},
    ]
    evidence = evidence or {
        "schema_version": 1,
        "source": {
            "edition": "1939",
            "profile_version": "1939-v2",
            "baseline_sha256": "b" * 64,
            "calamari_sha256": source_hash,
        },
        "entries": [
            anchored("old-a", 0, 8, text),
            anchored("old-b", 8, len(text), text),
        ],
    }
    materialization = {
        "schema_version": "1.0",
        "report": {
            "materialization_gate": "GO",
            "accepted_record_candidates": len(records),
        },
        "source_record_review": {
            "rendition_sha256": source_hash,
            "rendition_text": text,
            "records": records,
        },
    }
    ledger = {"schema_version": "1.0", "entries": ledger_entries}
    return baseline, evidence, materialization, ledger


def anchored(record_key, start, end, source_text):
    excerpt_sha256 = hashlib.sha256(source_text[start:end].encode("utf-8")).hexdigest()
    digest = hashlib.sha256(
        f"1939-v2\0{start}\0{end}\0{excerpt_sha256}".encode("utf-8")
    ).hexdigest()
    candidate_id = "human:1939-v2:span:" + digest
    return {
        "baseline_record_key": record_key,
        "candidates": [{
            "candidate_id": candidate_id,
            "calamari_span": {"char_from": start, "char_to": end},
            "approval": {
                "kind": "human_approved_span_v1",
                "calamari_excerpt_sha256": excerpt_sha256,
            },
        }],
        "conflicts": [],
        "source_blockers": [],
        "rule_id": "human_anchor_v1",
        "positive_provenance": {
            "kind": "human_approved_span_v1",
            "baseline_record_key": record_key,
            "candidate_id": candidate_id,
        },
    }


def unanchored(record_key):
    return {
        "baseline_record_key": record_key,
        "candidates": [],
        "conflicts": ["ambiguous_structure"],
        "source_blockers": [],
        "rule_id": None,
        "positive_provenance": None,
    }


def reconcile(values):
    baseline, evidence, materialization, ledger = values
    return build_reconciliation(
        baseline,
        evidence,
        materialization,
        ledger,
        baseline_sha256="b" * 64,
    )


def test_exact_one_to_one_positive_spans_are_unchanged_and_gate_go():
    result = reconcile(inputs())

    assert result["report"] == {
        "baseline_total": 2,
        "new_total": 2,
        "prior_positive_anchors": 2,
        "unique_exact_narrative_anchors": 0,
        "baseline_dispositions": {"unchanged": 2},
        "new_dispositions": {"unchanged": 2},
        "unchanged_bases": {"exact_positive_span": 2},
        "reconciliation_gate": "GO",
    }
    assert result["baseline_entries"][0] == {
        "baseline_record_key": "old-a",
        "name": "Anna",
        "evidence_method": "prior_positive_span",
        "source_span": {"char_from": 0, "char_to": 8},
        "matches": [{"new_record_key": "new-a", "geometry_relation": "exact_span"}],
        "disposition": "unchanged",
        "reconciliation_basis": "exact_positive_span",
    }


@pytest.mark.parametrize("layout_prefix", ["\n", "### PAGE 0002 ###\n"])
def test_one_to_one_boundary_delta_with_only_layout_is_proven_unchanged(layout_prefix):
    text = layout_prefix + "1. Anna\n"
    start = len(layout_prefix)
    values = inputs(
        text=text,
        spans=[(0, len(text), "accept-a", "new-a")],
        baseline=[{"record_key": "old-a", "navn": "Anna", "narrative": "ikke ordret"}],
        evidence={
            "schema_version": 1,
            "source": {
                "edition": "1939", "profile_version": "1939-v2",
                "baseline_sha256": "b" * 64,
                "calamari_sha256": hashlib.sha256(text.encode()).hexdigest(),
            },
            "entries": [anchored("old-a", start, len(text), text)],
        },
    )

    result = reconcile(values)

    assert result["baseline_entries"][0]["disposition"] == "unchanged"
    assert result["baseline_entries"][0]["reconciliation_basis"] == (
        "layout_only_boundary_delta"
    )


def test_unique_exact_baseline_narrative_inside_changed_boundary_proves_same_record():
    text = "Overskrift\n1. Anna\nNabotekst\n"
    old_start = text.index("1. Anna")
    old_end = old_start + len("1. Anna\n")
    values = inputs(
        text=text,
        spans=[(0, len(text), "accept-a", "new-a")],
        baseline=[{"record_key": "old-a", "navn": "Anna", "narrative": "1. Anna\n"}],
        evidence={
            "schema_version": 1,
            "source": {
                "edition": "1939", "profile_version": "1939-v2",
                "baseline_sha256": "b" * 64,
                "calamari_sha256": hashlib.sha256(text.encode()).hexdigest(),
            },
            "entries": [anchored("old-a", old_start, old_end, text)],
        },
    )

    result = reconcile(values)

    assert result["baseline_entries"][0]["disposition"] == "unchanged"
    assert result["baseline_entries"][0]["reconciliation_basis"] == (
        "unique_exact_narrative_inside_new"
    )


def test_meaningful_boundary_delta_without_exact_narrative_stays_in_review():
    text = "Overskrift\n1. Anna\nNabotekst\n"
    old_start = text.index("1. Anna")
    old_end = old_start + len("1. Anna\n")
    values = inputs(
        text=text,
        spans=[(0, len(text), "accept-a", "new-a")],
        baseline=[{"record_key": "old-a", "navn": "Anna", "narrative": "normaliseret Anna"}],
        evidence={
            "schema_version": 1,
            "source": {
                "edition": "1939", "profile_version": "1939-v2",
                "baseline_sha256": "b" * 64,
                "calamari_sha256": hashlib.sha256(text.encode()).hexdigest(),
            },
            "entries": [anchored("old-a", old_start, old_end, text)],
        },
    )

    result = reconcile(values)

    assert result["baseline_entries"][0]["disposition"] == "boundary_change_review"
    assert "reconciliation_basis" not in result["baseline_entries"][0]


def test_one_old_span_crossing_two_new_records_is_a_split_review():
    text = "1. Anna og Bent\n"
    values = inputs(
        text=text,
        spans=[(0, 8, "accept-a", "new-a"), (8, len(text), "accept-b", "new-b")],
        baseline=[{"record_key": "old-a", "navn": "Anna og Bent", "narrative": text}],
        evidence={
            "schema_version": 1,
            "source": {
                "edition": "1939", "profile_version": "1939-v2",
                "baseline_sha256": "b" * 64,
                "calamari_sha256": hashlib.sha256(text.encode()).hexdigest(),
            },
            "entries": [anchored("old-a", 0, len(text), text)],
        },
    )

    result = reconcile(values)

    assert result["baseline_entries"][0]["disposition"] == "split_review"
    assert [entry["disposition"] for entry in result["new_entries"]] == [
        "split_review", "split_review"
    ]
    assert result["report"]["reconciliation_gate"] == "NO-GO"


def test_two_old_spans_pointing_to_one_new_record_are_a_merge_review():
    text = "Anna og Bent\n"
    values = inputs(
        text=text,
        spans=[(0, len(text), "accept-a", "new-a")],
        baseline=[
            {"record_key": "old-a", "navn": "Anna", "narrative": "Anna"},
            {"record_key": "old-b", "navn": "Bent", "narrative": "Bent"},
        ],
        evidence={
            "schema_version": 1,
            "source": {
                "edition": "1939", "profile_version": "1939-v2",
                "baseline_sha256": "b" * 64,
                "calamari_sha256": hashlib.sha256(text.encode()).hexdigest(),
            },
            "entries": [anchored("old-a", 0, 4, text), anchored("old-b", 8, 12, text)],
        },
    )

    result = reconcile(values)

    assert [entry["disposition"] for entry in result["baseline_entries"]] == [
        "merge_review", "merge_review"
    ]
    assert result["new_entries"][0]["disposition"] == "merge_review"
    assert result["new_entries"][0]["baseline_record_keys"] == ["old-a", "old-b"]


def test_unique_exact_narrative_inside_one_new_record_is_review_not_identity_fact():
    text = "1. Anna med længere tekst\n"
    values = inputs(
        text=text,
        spans=[(0, len(text), "accept-a", "new-a")],
        baseline=[{"record_key": "old-a", "navn": "Anna", "narrative": "Anna med længere"}],
        evidence={
            "schema_version": 1,
            "source": {
                "edition": "1939", "profile_version": "1939-v2",
                "baseline_sha256": "b" * 64,
                "calamari_sha256": hashlib.sha256(text.encode()).hexdigest(),
            },
            "entries": [unanchored("old-a")],
        },
    )

    result = reconcile(values)

    old = result["baseline_entries"][0]
    assert old["evidence_method"] == "unique_exact_narrative"
    assert old["disposition"] == "text_anchor_review"
    assert old["matches"] == [{
        "new_record_key": "new-a",
        "geometry_relation": "narrative_inside_new",
    }]
    assert result["report"]["reconciliation_gate"] == "NO-GO"


def test_missing_exact_narrative_and_unmatched_new_record_remain_visible():
    text = "1. Anna\n"
    values = inputs(
        text=text,
        spans=[(0, len(text), "accept-a", "new-a")],
        baseline=[{"record_key": "old-a", "navn": "Anden", "narrative": "Ikke i kilden"}],
        evidence={
            "schema_version": 1,
            "source": {
                "edition": "1939", "profile_version": "1939-v2",
                "baseline_sha256": "b" * 64,
                "calamari_sha256": hashlib.sha256(text.encode()).hexdigest(),
            },
            "entries": [unanchored("old-a")],
        },
    )

    result = reconcile(values)

    assert result["baseline_entries"][0]["disposition"] == "unresolved"
    assert result["baseline_entries"][0]["unresolved_reason"] == "narrative_not_exact"
    assert result["new_entries"][0]["disposition"] == "unmatched_new_review"


def test_rejects_baseline_or_calamari_hash_drift():
    baseline, evidence, materialization, ledger = inputs()
    with pytest.raises(ReconciliationError, match="baseline_sha256"):
        build_reconciliation(
            baseline, evidence, materialization, ledger,
            baseline_sha256="c" * 64,
        )

    evidence["source"]["calamari_sha256"] = "d" * 64
    with pytest.raises(ReconciliationError, match="calamari_sha256"):
        build_reconciliation(
            baseline, evidence, materialization, ledger,
            baseline_sha256="b" * 64,
        )


def test_rejects_tampered_human_span_approval():
    baseline, evidence, materialization, ledger = inputs()
    evidence["entries"][0]["candidates"][0]["approval"][
        "calamari_excerpt_sha256"
    ] = "f" * 64

    with pytest.raises(ReconciliationError, match="human approval"):
        build_reconciliation(
            baseline, evidence, materialization, ledger,
            baseline_sha256="b" * 64,
        )


def test_cli_writes_full_reconciliation_and_summary_exclusively(tmp_path):
    baseline, evidence, materialization, ledger = inputs()
    baseline_path = tmp_path / "baseline.json"
    evidence_path = tmp_path / "evidence.json"
    materialization_path = tmp_path / "materialization.json"
    ledger_path = tmp_path / "ledger.json"
    out_path = tmp_path / "reconciliation.json"
    report_path = tmp_path / "report.json"
    baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
    evidence["source"]["baseline_sha256"] = hashlib.sha256(
        baseline_path.read_bytes()
    ).hexdigest()
    evidence_path.write_text(json.dumps(evidence), encoding="utf-8")
    materialization_path.write_text(json.dumps(materialization), encoding="utf-8")
    ledger_path.write_text(json.dumps(ledger), encoding="utf-8")

    assert subject.main([
        str(baseline_path),
        "--evidence", str(evidence_path),
        "--materialization", str(materialization_path),
        "--ledger", str(ledger_path),
        "--out", str(out_path),
        "--report-out", str(report_path),
    ]) == 0

    result = json.loads(out_path.read_text(encoding="utf-8"))
    report = json.loads(report_path.read_text(encoding="utf-8"))
    assert result["report"]["reconciliation_gate"] == "GO"
    assert report == result["report"]

    with pytest.raises(ReconciliationError, match="findes allerede"):
        subject.main([
            str(baseline_path),
            "--evidence", str(evidence_path),
            "--materialization", str(materialization_path),
            "--ledger", str(ledger_path),
            "--out", str(tmp_path / "second.json"),
            "--report-out", str(report_path),
        ])
    assert not (tmp_path / "second.json").exists()


def test_inactive_append_only_ledger_history_does_not_enter_current_reconciliation():
    values = inputs()
    baseline, evidence, materialization, ledger = values
    ledger["entries"].append({
        "acceptance_id": "historical-acceptance",
        "record_key": "historical-record-key",
        "immutable": "c" * 64,
    })

    result = build_reconciliation(
        baseline, evidence, materialization, ledger,
        baseline_sha256="b" * 64,
    )

    assert result["report"]["new_total"] == 2
    assert {entry["new_record_key"] for entry in result["new_entries"]} == {
        "new-a", "new-b",
    }


def test_structural_record_kind_is_preserved_in_reconciliation_output():
    values = inputs()
    values[2]["source_record_review"]["records"][0]["record_kind"] = (
        "structural_context"
    )

    result = reconcile(values)

    assert result["new_entries"][0]["record_kind"] == "structural_context"
    assert result["new_entries"][1]["record_kind"] == "unclassified"


@pytest.mark.parametrize("record_kind", [None, "person", "", 17])
def test_unknown_or_missing_record_kind_fails_closed(record_kind):
    values = inputs()
    record = values[2]["source_record_review"]["records"][0]
    if record_kind is None:
        record.pop("record_kind")
    else:
        record["record_kind"] = record_kind

    with pytest.raises(ReconciliationError, match="record_kind"):
        reconcile(values)
