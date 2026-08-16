from __future__ import annotations

import hashlib
import json

import pytest

import materialize_graenseflade_1939 as subject
from evidence_contract import validate_bundle


MaterializationError = subject.MaterializationError
build_materialization = subject.build_materialization


def export_for(text: str, *, cuts: list[int], omissions: list[tuple[int, int]] = (),
               structural: list[tuple[int, int]] = ()) -> dict:
    result = {
        "schema_version": 1,
        "source": {
            "edition": "1939",
            "profile_version": "1939-v2",
            "baseline_sha256": "a" * 64,
            "calamari_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            "raw_ocr_sha256": "b" * 64,
            "pdf_sha256": "c" * 64,
        },
        "skaeringer": [
            {"char_offset": offset, "oprindelse": "bruger"} for offset in cuts
        ],
        "udeladelser": [
            {"char_from": start, "char_to": end} for start, end in omissions
        ],
        "sider": {"i_alt": 1, "identitet": "kildeside", "gennemgaaet": [1]},
    }
    if structural:
        result["strukturelle_henvisninger"] = [{
            "char_from": start,
            "char_to": end,
            "record_kind": "structural_context",
            "person_creation": "forbidden",
        } for start, end in structural]
    return result


def test_materializes_exact_cut_bounded_structural_context_record():
    text = "### PAGE 0001 ###\n1. Anna\nBørn: II.\n2. Bent\n"
    first = text.index("1. Anna")
    reference = text.index("Børn: II.")
    second = text.index("2. Bent")

    result = build_materialization(
        export_for(
            text,
            cuts=[first, reference, second],
            structural=[(reference, second)],
        ),
        text,
        rendition_id="rendition-1",
        extraction_run_id="run-1",
        reviewed_by="editor-1",
    )

    assert [record["record_kind"] for record in result["source_record_review"]["records"]] == [
        "unclassified", "structural_context", "unclassified",
    ]
    assert result["source_record_review"]["records"][1]["source_anchor"] == {
        "char_from": reference,
        "char_to": second,
    }
    assert result["report"]["structural_record_candidates"] == 1


def test_builds_exact_unclassified_review_records_without_minting_record_keys():
    text = "### PAGE 0001 ###\nOverskrift\n1. Anna\n2. Bent\n"
    heading_start = text.index("Overskrift")
    first = text.index("1. Anna")
    second = text.index("2. Bent")

    result = build_materialization(
        export_for(text, cuts=[first, second], omissions=[(heading_start, first)]),
        text,
        rendition_id="daa-1939-calamari-r6-clean",
        extraction_run_id="boundary-review-2026-08-16",
        reviewed_by="editor-1",
    )

    review = result["source_record_review"]
    assert result["report"] == {
        "materialization_gate": "GO",
        "cut_intervals": 2,
        "accepted_record_candidates": 2,
        "omitted_intervals": 0,
        "unresolved_intervals": 0,
        "structural_record_candidates": 0,
    }
    assert [record["verbatim_text"] for record in review["records"]] == [
        "1. Anna\n",
        "2. Bent\n",
    ]
    assert all(record["record_kind"] == "unclassified" for record in review["records"])
    assert all("record_key" not in record for record in review["records"])
    assert review["records"][0]["span"] == {
        "page_from": 496,
        "page_to": 496,
        "char_from": 0,
        "char_to": len("1. Anna\n"),
        "bbox": None,
    }
    assert review["records"][0]["source_anchor"] == {
        "char_from": first,
        "char_to": second,
    }
    assert review["records"][0]["acceptance_id"] == build_materialization(
        export_for(text, cuts=[first, second], omissions=[(heading_start, first)]),
        text,
        rendition_id="daa-1939-calamari-r6-clean",
        extraction_run_id="boundary-review-2026-08-16",
        reviewed_by="editor-1",
    )["source_record_review"]["records"][0]["acceptance_id"]


def test_omission_only_interval_is_accounted_without_creating_a_record():
    text = "### PAGE 0001 ###\n1. Anna\nMellemoverskrift\n2. Bent\n"
    first = text.index("1. Anna")
    heading = text.index("Mellemoverskrift")
    second = text.index("2. Bent")

    result = build_materialization(
        export_for(
            text,
            cuts=[first, heading, second],
            omissions=[(heading, second)],
        ),
        text,
        rendition_id="rendition-1",
        extraction_run_id="run-1",
        reviewed_by="editor-1",
    )

    assert result["report"]["materialization_gate"] == "GO"
    assert result["report"]["accepted_record_candidates"] == 2
    assert result["report"]["omitted_intervals"] == 1
    assert [item["disposition"] for item in result["intervals"]] == [
        "accepted_record_candidate",
        "omitted",
        "accepted_record_candidate",
    ]


def test_internal_omission_between_meaningful_text_is_parked_fail_closed():
    text = "### PAGE 0001 ###\n1. Før\nUdeladt\nFortsat\n"
    first = text.index("1. Før")
    omitted_from = text.index("Udeladt")
    omitted_to = omitted_from + len("Udeladt\n")

    result = build_materialization(
        export_for(text, cuts=[first], omissions=[(omitted_from, omitted_to)]),
        text,
        rendition_id="rendition-1",
        extraction_run_id="run-1",
        reviewed_by="editor-1",
    )

    assert result["report"] == {
        "materialization_gate": "NO-GO",
        "cut_intervals": 1,
        "accepted_record_candidates": 0,
        "omitted_intervals": 0,
        "unresolved_intervals": 1,
        "structural_record_candidates": 0,
    }
    assert result["source_record_review"]["records"] == []
    assert result["intervals"][0]["disposition"] == "unresolved"
    assert result["intervals"][0]["reason"] == "omission_splits_meaningful_text"


def test_rejects_structural_context_that_is_not_an_exact_available_interval():
    text = "### PAGE 0001 ###\n1. Anna\nBørn: II.\n2. Bent\n"
    first = text.index("1. Anna")
    reference = text.index("Børn: II.")
    second = text.index("2. Bent")

    with pytest.raises(MaterializationError, match="overlapper udeladelse"):
        build_materialization(
            export_for(
                text, cuts=[first, reference, second],
                omissions=[(reference, second)], structural=[(reference, second)],
            ), text, rendition_id="r", extraction_run_id="x", reviewed_by="e",
        )

    with pytest.raises(MaterializationError, match="helt cut-interval"):
        build_materialization(
            export_for(
                text, cuts=[first, reference, second],
                structural=[(reference + 1, second)],
            ), text, rendition_id="r", extraction_run_id="x", reviewed_by="e",
        )

    duplicate = export_for(
        text, cuts=[first, reference, second], structural=[(reference, second)]
    )
    duplicate["strukturelle_henvisninger"].append(
        dict(duplicate["strukturelle_henvisninger"][0])
    )
    with pytest.raises(MaterializationError, match="dublet"):
        build_materialization(
            duplicate, text, rendition_id="r", extraction_run_id="x", reviewed_by="e",
        )

    overlap = export_for(
        text, cuts=[first, reference, second], structural=[
            (reference, second), (reference + 1, second + 1),
        ]
    )
    with pytest.raises(MaterializationError, match="overlap"):
        build_materialization(
            overlap, text, rendition_id="r", extraction_run_id="x", reviewed_by="e",
        )


def test_source_record_artifacts_mint_opaque_keys_only_after_gate_is_go():
    text = "### PAGE 0001 ###\n1. Anna\n2. Bent\n"
    first = text.index("1. Anna")
    second = text.index("2. Bent")
    materialization = build_materialization(
        export_for(text, cuts=[first, second]),
        text,
        rendition_id="rendition-1",
        extraction_run_id="run-1",
        reviewed_by="editor-1",
    )

    ledger, bundle = subject.build_source_record_artifacts(
        materialization, {"schema_version": "1.0", "entries": []}
    )

    assert validate_bundle(bundle) is None
    assert len(ledger["entries"]) == 2
    assert all(entry["record_key"].startswith("record-") for entry in ledger["entries"])
    assert all("Anna" not in entry["record_key"] for entry in ledger["entries"])
    assert len({entry["record_key"] for entry in ledger["entries"]}) == 2


def test_source_record_artifacts_reject_partial_no_go_materialization():
    text = "### PAGE 0001 ###\n1. Før\nUdeladt\nFortsat\n"
    first = text.index("1. Før")
    omitted_from = text.index("Udeladt")
    materialization = build_materialization(
        export_for(
            text,
            cuts=[first],
            omissions=[(omitted_from, omitted_from + len("Udeladt\n"))],
        ),
        text,
        rendition_id="rendition-1",
        extraction_run_id="run-1",
        reviewed_by="editor-1",
    )

    with pytest.raises(MaterializationError, match="NO-GO"):
        subject.build_source_record_artifacts(
            materialization, {"schema_version": "1.0", "entries": []}
        )


def test_cli_writes_materialization_ledger_and_valid_bundle_exclusively(tmp_path):
    text = "### PAGE 0001 ###\n1. Anna\n2. Bent\n"
    export_path = tmp_path / "export.json"
    source_path = tmp_path / "calamari.txt"
    materialization_path = tmp_path / "materialization.json"
    ledger_path = tmp_path / "ledger.json"
    bundle_path = tmp_path / "bundle.json"
    export_path.write_text(json.dumps(export_for(
        text, cuts=[text.index("1. Anna"), text.index("2. Bent")]
    )), encoding="utf-8")
    source_path.write_text(text, encoding="utf-8")

    assert subject.main([
        str(export_path),
        "--calamari", str(source_path),
        "--reviewed-by", "editor-1",
        "--rendition-id", "rendition-1",
        "--extraction-run-id", "run-1",
        "--materialization-out", str(materialization_path),
        "--ledger-out", str(ledger_path),
        "--bundle-out", str(bundle_path),
    ]) == 0

    materialization = json.loads(materialization_path.read_text(encoding="utf-8"))
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    assert materialization["report"]["accepted_record_candidates"] == 2
    assert len(ledger["entries"]) == 2
    assert validate_bundle(bundle) is None


def test_cli_removes_new_outputs_if_a_later_exclusive_output_already_exists(tmp_path):
    text = "### PAGE 0001 ###\n1. Anna\n"
    export_path = tmp_path / "export.json"
    source_path = tmp_path / "calamari.txt"
    materialization_path = tmp_path / "materialization.json"
    ledger_path = tmp_path / "ledger.json"
    bundle_path = tmp_path / "bundle.json"
    export_path.write_text(json.dumps(export_for(
        text, cuts=[text.index("1. Anna")]
    )), encoding="utf-8")
    source_path.write_text(text, encoding="utf-8")
    bundle_path.write_text("sentinel", encoding="utf-8")

    with pytest.raises(MaterializationError, match="findes allerede"):
        subject.main([
            str(export_path),
            "--calamari", str(source_path),
            "--reviewed-by", "editor-1",
            "--rendition-id", "rendition-1",
            "--extraction-run-id", "run-1",
            "--materialization-out", str(materialization_path),
            "--ledger-out", str(ledger_path),
            "--bundle-out", str(bundle_path),
        ])

    assert not materialization_path.exists()
    assert not ledger_path.exists()
    assert bundle_path.read_text(encoding="utf-8") == "sentinel"


def test_rejects_incomplete_page_review_and_source_hash_drift():
    text = "### PAGE 0001 ###\n1. Anna\n"
    data = export_for(text, cuts=[text.index("1. Anna")])
    data["sider"]["gennemgaaet"] = []

    with pytest.raises(MaterializationError, match="alle kildesider"):
        build_materialization(
            data,
            text,
            rendition_id="rendition-1",
            extraction_run_id="run-1",
            reviewed_by="editor-1",
        )

    data = export_for(text, cuts=[text.index("1. Anna")])
    data["source"]["calamari_sha256"] = "f" * 64
    with pytest.raises(MaterializationError, match="calamari_sha256"):
        build_materialization(
            data,
            text,
            rendition_id="rendition-1",
            extraction_run_id="run-1",
            reviewed_by="editor-1",
        )


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        (lambda data: data["skaeringer"].append(dict(data["skaeringer"][0])), "dublet"),
        (
            lambda data: data["udeladelser"].extend(
                [{"char_from": 20, "char_to": 24}, {"char_from": 22, "char_to": 26}]
            ),
            "overlap",
        ),
    ],
)
def test_rejects_ambiguous_export_geometry(mutation, message):
    text = "### PAGE 0001 ###\n1. Anna\n"
    data = export_for(text, cuts=[text.index("1. Anna")])
    mutation(data)

    with pytest.raises(MaterializationError, match=message):
        build_materialization(
            data,
            text,
            rendition_id="rendition-1",
            extraction_run_id="run-1",
            reviewed_by="editor-1",
        )
