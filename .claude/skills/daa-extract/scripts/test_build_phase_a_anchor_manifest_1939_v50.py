from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

import pytest

import build_phase_a_anchor_manifest_1939_v50 as subject
from build_phase_a_anchor_manifest_1939_v50 import ManifestError, _build_phase_a_anchor_manifest


IMPORT_PREVIEW_SHA256 = "04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5"
DATABASE_PREVIEW_SHA256 = "a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c"
PRODUCTION_MANIFEST_SHA256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
BOUNDARY_SHA256 = "73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f"
CALAMARI_SHA256 = "020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37"


def sha(value):
    return hashlib.sha256((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()).hexdigest()


def fixture():
    text_a = "1. Ida, f. 1800, d. 1850.\n"
    text_b = "2. Bertel, nyt slaegtled.\n"
    text_c = "Se ovenfor om slaegten.\n"
    filler = "x" * 5
    calamari_text = filler + text_a + filler + text_b + filler + text_c + filler
    offset_a = len(filler)
    span_a = {"char_from": offset_a, "char_to": offset_a + len(text_a)}
    offset_b = span_a["char_to"] + len(filler)
    span_b = {"char_from": offset_b, "char_to": offset_b + len(text_b)}
    offset_c = span_b["char_to"] + len(filler)
    span_c = {"char_from": offset_c, "char_to": offset_c + len(text_c)}
    fixture_calamari_sha256 = hashlib.sha256(calamari_text.encode()).hexdigest()

    import_preview = {
        "schema_version": "1939-v50-import-preview-v1",
        "canonical_mutations_authorized": False,
        "source": {"input_hashes": {"calamari_sha256": fixture_calamari_sha256}},
        "source_records": [
            {"new_record_key": "record-A", "record_kind": "unclassified",
             "person_creation": "requires_existing_anchor", "source_span": span_a,
             "verbatim_text": text_a},
            {"new_record_key": "record-B", "record_kind": "unclassified",
             "person_creation": "forbidden", "source_span": span_b,
             "verbatim_text": text_b},
            {"new_record_key": "record-C", "record_kind": "structural_context",
             "person_creation": "forbidden", "source_span": span_c,
             "verbatim_text": text_c},
        ],
        "mapped_existing": [
            {"new_record_key": "record-A", "baseline_record_key": "baseline-A",
             "legacy_name": "Ida"},
        ],
    }
    database_preview = {
        "schema_version": "1939-v50-database-preview-v1",
        "canonical_mutations_authorized": False,
        "input_preview": {"input_hashes": {"calamari_sha256": fixture_calamari_sha256}},
        "person_anchors": {
            "matched_count": 1, "missing_count": 0, "collision_count": 0,
            "matched": [{"baseline_record_key": "baseline-A", "person_id": 501}],
        },
    }
    production_manifest = {
        "schema_version": "1939-v50-production-write-manifest-v1",
        "production_authorized": False,
        "source": {"rendition_content_sha256": fixture_calamari_sha256},
        "person_creates": [{"source_record_key": "record-B", "name": "Bertel"}],
    }
    boundary = {
        "schema_version": "1.0",
        "source_record_review": {
            "schema_version": "1.0", "source_id": "1939",
            "rendition_id": "daa-1939-calamari-r6-clean", "rendition_sha256": fixture_calamari_sha256,
            "records": [
                {"source_anchor": span_a, "span": {"page_from": 10, "page_to": 10},
                 "verbatim_text": text_a},
                {"source_anchor": span_b, "span": {"page_from": 10, "page_to": 10},
                 "verbatim_text": text_b},
                {"source_anchor": span_c, "span": {"page_from": 11, "page_to": 11},
                 "verbatim_text": text_c},
            ],
        },
    }
    return {
        "import_preview": import_preview, "database_preview": database_preview,
        "production_manifest": production_manifest, "boundary": boundary,
        "calamari_text": calamari_text,
    }


def hashes_for(values: dict) -> list[str]:
    return [
        sha(values["import_preview"]), sha(values["database_preview"]),
        sha(values["production_manifest"]), sha(values["boundary"]),
        hashlib.sha256(values["calamari_text"].encode()).hexdigest(),
    ]


def build(values=None):
    values = values or fixture()
    return _build_phase_a_anchor_manifest(
        values["import_preview"], values["database_preview"], values["production_manifest"],
        values["boundary"], values["calamari_text"], input_hashes=hashes_for(values),
    )


def test_excludes_already_written_records():
    result = build()
    assert len(result["operations"]) == 2
    keys = {op["source_record_key"] for op in result["operations"]}
    assert keys == {"record-A", "record-C"}
    assert result["arithmetic"] == {
        "source_records": 3, "excluded_already_written": 1, "elements": 2,
        "canonical_targets": 1,
    }


def test_element_payload_has_exactly_allowed_keys():
    # De 11 tilladte nøgler pinnet LITERALT (uafhængigt af modulets egen
    # SQL_PAYLOAD_KEYS-konstant) — skal matche schema.sql:2489
    # (red_apply_1939_v50_source_evidence's `p_payload-ARRAY[...]`) ord for ord,
    # så en drivet konstant i selve byggeren ikke kan gøre denne test grøn.
    allowed_keys = {
        "review_subject_id", "source_record_key", "category", "disposition",
        "evidence_sha256", "canonical_target", "source_span", "page_evidence",
        "verbatim_text", "legacy_payload", "rendition_content_sha256",
    }
    required_present_keys = {
        "source_record_key", "disposition", "source_span", "page_evidence",
        "verbatim_text", "rendition_content_sha256",
    }
    result = build()
    for op in result["operations"]:
        payload_keys = set(op) - {"element_id", "dependency_class"}
        assert payload_keys <= allowed_keys
        assert required_present_keys <= payload_keys
        assert op["disposition"] == "retain_source_only"
    by_key = {op["source_record_key"]: op for op in result["operations"]}
    assert "canonical_target" in by_key["record-A"]
    assert by_key["record-A"]["canonical_target"] == {"person_id": 501}
    assert by_key["record-A"]["legacy_payload"] == {
        "baseline_record_key": "baseline-A", "legacy_name": "Ida",
    }
    assert "canonical_target" not in by_key["record-C"]
    assert "legacy_payload" not in by_key["record-C"]
    assert by_key["record-C"]["category"] == "structural_context"
    assert by_key["record-A"]["category"] == "person"


def test_verbatim_must_match_calamari_span():
    values = fixture()
    values["import_preview"]["source_records"][0]["verbatim_text"] = "drift"
    values["import_preview"]["source_records"][0]["source_span"] = {
        "char_from": values["import_preview"]["source_records"][0]["source_span"]["char_from"],
        "char_to": values["import_preview"]["source_records"][0]["source_span"]["char_from"] + len("drift"),
    }
    # Boundary must still agree with the (now mismatched-vs-calamari) source record
    # so the failure surfaces at the calamari byte-check, not the boundary lookup.
    values["boundary"]["source_record_review"]["records"][0]["verbatim_text"] = "drift"
    values["boundary"]["source_record_review"]["records"][0]["source_anchor"] = (
        values["import_preview"]["source_records"][0]["source_span"]
    )
    with pytest.raises(ManifestError, match="SPAN_MISMATCH"):
        build(values)


def test_page_evidence_from_boundary_lookup():
    result = build()
    by_key = {op["source_record_key"]: op for op in result["operations"]}
    assert by_key["record-A"]["page_evidence"] == {"page_from": 10, "page_to": 10}
    assert by_key["record-C"]["page_evidence"] == {"page_from": 11, "page_to": 11}


def test_missing_boundary_anchor_aborts_with_record_key():
    values = fixture()
    del values["boundary"]["source_record_review"]["records"][2]
    with pytest.raises(ManifestError, match="record-C"):
        build(values)


def test_boundary_verbatim_drift_aborts_with_record_key():
    values = fixture()
    values["boundary"]["source_record_review"]["records"][2]["verbatim_text"] = "andet"
    with pytest.raises(ManifestError, match="record-C"):
        build(values)


def test_ambiguous_boundary_anchor_aborts():
    # Kravet lyder "manglende/TVETYDIGT opslag aborterer" — to boundary-records
    # med samme (char_from,char_to) er tvetydigt, uafhængigt af om nogen
    # source_record rammer den præcise nøgle. Guard: builder ~linje 190-192
    # (`if anchor_key in by_anchor: _fail(...)`), som ellers kunne "forenkles"
    # væk uden at nogen test blev rød.
    values = fixture()
    duplicate_anchor_row = dict(values["boundary"]["source_record_review"]["records"][0])
    values["boundary"]["source_record_review"]["records"].append(duplicate_anchor_row)
    with pytest.raises(ManifestError, match="PHASE_A_MANIFEST_BOUNDARY_INVALID"):
        build(values)


def test_anchor_lookup_failed_when_mapped_existing_entry_missing():
    # Gren 1 af ANCHOR_LOOKUP_FAILED (builder ~linje 257-259): record-A er
    # `requires_existing_anchor`, men mapped_existing har ingen post for den.
    # I produktion er denne gren uopnåelig fordi expected_canonical_targets=543
    # fyrer allerede i den offentlige funktion — testes derfor direkte mod den
    # private funktion (uden expected_*), så guarden ikke rådner ubemærket.
    values = fixture()
    values["import_preview"]["mapped_existing"] = []
    with pytest.raises(ManifestError, match="PHASE_A_MANIFEST_ANCHOR_LOOKUP_FAILED:record-A"):
        build(values)


def test_anchor_lookup_failed_when_person_anchor_entry_missing():
    # Gren 2 af ANCHOR_LOOKUP_FAILED (builder ~linje 262-263): mapped_existing
    # peger på baseline-A, men database-preview's person_anchors.matched
    # indeholder ingen post for baseline-A.
    values = fixture()
    values["database_preview"]["person_anchors"]["matched"] = []
    values["database_preview"]["person_anchors"]["matched_count"] = 0
    with pytest.raises(ManifestError, match="PHASE_A_MANIFEST_ANCHOR_LOOKUP_FAILED:record-A"):
        build(values)


def test_main_output_exists_aborts_without_overwriting(tmp_path: Path):
    # Bindende krav: "output-fil må ikke findes i forvejen". Guard er det
    # allerførste main() gør (før nogen fil læses/hash-verificeres), så vi kan
    # bruge vilkårlige/ikke-eksisterende inputstier og stadig teste guarden
    # isoleret — og bekræfte at det eksisterende output IKKE overskrives.
    output_path = tmp_path / "existing-manifest.json"
    output_path.write_text("allerede-her", encoding="utf-8")
    placeholder_sha = "0" * 64
    with pytest.raises(ManifestError, match="PHASE_A_MANIFEST_OUTPUT_EXISTS"):
        subject.main([
            "--import-preview", "does-not-matter.json", "--import-preview-sha256", placeholder_sha,
            "--database-preview", "does-not-matter.json", "--database-preview-sha256", placeholder_sha,
            "--production-manifest", "does-not-matter.json", "--production-manifest-sha256", placeholder_sha,
            "--boundary", "does-not-matter.json", "--boundary-sha256", placeholder_sha,
            "--calamari", "does-not-matter.txt", "--calamari-sha256", placeholder_sha,
            "--output", str(output_path),
        ])
    assert output_path.read_text(encoding="utf-8") == "allerede-her"


def test_counts_and_determinism():
    values = fixture()
    result_1 = build(values)
    assert result_1["counts"] == {
        "person_creates": 0, "source_evidence": 2, "canonical_delta": 0,
    }
    result_2 = build(values)
    assert json.dumps(result_1, sort_keys=True) == json.dumps(result_2, sort_keys=True)
    assert result_1["manifest_content_sha256"] == result_2["manifest_content_sha256"]


@pytest.mark.parametrize("mutate", [
    lambda v: v["import_preview"].update(canonical_mutations_authorized=True),
    lambda v: v["production_manifest"].update(production_authorized=True),
    lambda v: v["database_preview"]["person_anchors"]["matched"].append(
        {"baseline_record_key": "baseline-x", "person_id": 999}),
    lambda v: v["boundary"]["source_record_review"].update(rendition_sha256="0" * 64),
])
def test_drift_fails_closed(mutate):
    values = fixture()
    mutate(values)
    with pytest.raises(ManifestError):
        build(values)


def test_excluded_key_missing_from_source_records_aborts():
    values = fixture()
    values["production_manifest"]["person_creates"].append(
        {"source_record_key": "record-not-in-source"})
    with pytest.raises(ManifestError, match="record-not-in-source"):
        build(values)


def test_legacy_name_none_is_permitted_for_nameless_baseline_records():
    # 13 af de 543 mapped_existing-poster i den rigtige production-1939-database
    # har legacy_name=None (navnløse baseline-personer) — dette er kendt, ikke
    # en datafejl, og skal give legacy_payload.legacy_name=None, ikke aborte.
    values = fixture()
    values["import_preview"]["mapped_existing"][0]["legacy_name"] = None
    result = build(values)
    by_key = {op["source_record_key"]: op for op in result["operations"]}
    assert by_key["record-A"]["legacy_payload"] == {
        "baseline_record_key": "baseline-A", "legacy_name": None,
    }


def test_legacy_name_empty_string_fails_closed():
    values = fixture()
    values["import_preview"]["mapped_existing"][0]["legacy_name"] = ""
    with pytest.raises(ManifestError):
        build(values)


def test_boundary_page_from_below_one_fails_closed():
    values = fixture()
    values["boundary"]["source_record_review"]["records"][0]["span"]["page_from"] = 0
    values["boundary"]["source_record_review"]["records"][0]["span"]["page_to"] = 0
    with pytest.raises(ManifestError, match="PHASE_A_MANIFEST_BOUNDARY_INVALID"):
        build(values)


def test_public_builder_locks_production_hashes_and_universe():
    assert subject.LOCKED_INPUT_HASHES == [
        subject.LOCKED_IMPORT_PREVIEW_SHA256, subject.LOCKED_DATABASE_PREVIEW_SHA256,
        subject.LOCKED_PRODUCTION_MANIFEST_SHA256, subject.LOCKED_BOUNDARY_SHA256,
        subject.LOCKED_CALAMARI_SHA256,
    ]
    assert (subject.EXPECTED_SOURCE_RECORDS, subject.EXPECTED_EXCLUDED_ALREADY_WRITTEN,
            subject.EXPECTED_ELEMENTS, subject.EXPECTED_CANONICAL_TARGETS) == (592, 8, 584, 543)
    assert "expected_source_records" not in subject.build_phase_a_anchor_manifest.__code__.co_varnames


def test_public_builder_rejects_non_locked_hashes():
    values = fixture()
    with pytest.raises(ManifestError, match="PHASE_A_MANIFEST_HASH_NOT_LOCKED"):
        subject.build_phase_a_anchor_manifest(
            values["import_preview"], values["database_preview"],
            values["production_manifest"], values["boundary"], values["calamari_text"],
            input_hashes=hashes_for(values),
        )


def test_real_artifacts_full_arithmetic(tmp_path: Path):
    worktree = Path(__file__).resolve().parents[4]
    parent_repo = Path("/Users/johanreventlow/TypeScript/danmarksadelsaarbog")
    import_preview_path = worktree / "work/task21-1939-v50-import-preview/import-preview-v1.json"
    database_preview_path = worktree / "work/task21-1939-v50-import-preview/database-preview-v1.json"
    production_manifest_path = (
        worktree / "work/task25-1939-v50-production-writer/production-write-manifest-v1.json"
    )
    boundary_path = worktree / "work/task20-1939-full/boundary-materialization-v3-ditlev.json"
    calamari_path = parent_repo / "work_1939_stamtavle/full_ocr_calamari_r6_clean.txt"
    required = [import_preview_path, database_preview_path, production_manifest_path,
                boundary_path, calamari_path]
    if not all(path.exists() for path in required):
        pytest.skip("ignorerede realdata-input findes ikke i denne checkout")

    def real_sha(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    assert real_sha(import_preview_path) == IMPORT_PREVIEW_SHA256
    assert real_sha(database_preview_path) == DATABASE_PREVIEW_SHA256
    assert real_sha(production_manifest_path) == PRODUCTION_MANIFEST_SHA256
    assert real_sha(boundary_path) == BOUNDARY_SHA256
    assert real_sha(calamari_path) == CALAMARI_SHA256

    output_path = tmp_path / "phase-a-anchor-manifest-v1.json"
    exit_code = subject.main([
        "--import-preview", str(import_preview_path),
        "--import-preview-sha256", IMPORT_PREVIEW_SHA256,
        "--database-preview", str(database_preview_path),
        "--database-preview-sha256", DATABASE_PREVIEW_SHA256,
        "--production-manifest", str(production_manifest_path),
        "--production-manifest-sha256", PRODUCTION_MANIFEST_SHA256,
        "--boundary", str(boundary_path),
        "--boundary-sha256", BOUNDARY_SHA256,
        "--calamari", str(calamari_path),
        "--calamari-sha256", CALAMARI_SHA256,
        "--output", str(output_path),
    ])
    assert exit_code == 0

    result = json.loads(output_path.read_text(encoding="utf-8"))
    assert result["arithmetic"] == {
        "source_records": 592, "excluded_already_written": 8, "elements": 584,
        "canonical_targets": 543,
    }
    assert result["counts"] == {
        "person_creates": 0, "source_evidence": 584, "canonical_delta": 0,
    }
    operations = result["operations"]
    assert len(operations) == 584
    from collections import Counter
    category_counts = Counter(op["category"] for op in operations)
    assert category_counts == {"person": 576, "structural_context": 6, "cross_reference": 2}
    with_target = [op for op in operations if "canonical_target" in op]
    assert len(with_target) == 543
    assert all(isinstance(op["canonical_target"]["person_id"], int) for op in with_target)
    assert all("legacy_payload" in op for op in with_target)
    without_target = [op for op in operations if "canonical_target" not in op]
    assert all("legacy_payload" not in op for op in without_target)
    assert all(op["disposition"] == "retain_source_only" for op in operations)
    assert all(op["rendition_content_sha256"] == CALAMARI_SHA256 for op in operations)
    assert result["manifest_content_sha256"] == sha_without_manifest_content(result)


def sha_without_manifest_content(result: dict) -> str:
    from build_phase_a_anchor_manifest_1939_v50 import canonical_sha
    value = dict(result)
    value.pop("manifest_content_sha256")
    return canonical_sha(value)
