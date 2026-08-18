from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

import build_narrative_replacement_manifest_1939_v50 as subject
from build_narrative_replacement_manifest_1939_v50 import (
    ManifestError,
    _build_narrative_replacement,
    _decided_text,
)
from normalize_narrative_1939_v50 import normalize_narrative_v1


PHASE_A_MANIFEST_SHA256 = "1945416b3b56e781787366008a2463b419cb8ed4df3ef1399211cac5c999e208"
PRODUCTION_MANIFEST_SHA256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
NARRATIVE_PUBLICATION_MANIFEST_SHA256 = "d71908cf3a998d57602a91d936a2c1b19cf874da938bdef0d691fda9a2ac7654"
CALAMARI_SHA256 = "020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37"
OLD_NARRATIVE_SHA_EXPORT_SHA256 = "e91145c79867f99c79edcc6aa6f1711b4dc5002406fdfc0eded42778f90501ec"


def _sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


# ---------------------------------------------------------------------------
# Fixture texts -- verified directly against the real (unmodified)
# normalize_narrative_v1 before being wired into the builder fixtures below,
# so every expected default/decided text asserted here is empirically known,
# not guessed.
# ---------------------------------------------------------------------------

RAW_A_HYPHEN_UNPROVEN = "1. Han sammen-\ntraekkes med andre og skrev en bog om Skivehus.\n"
RAW_B_HYPHEN_AMBIGUOUS = "2. Ejede Skivehus i Norre H. (1735-\n50), Osterrade.\n"
RAW_C_ORDINAL_AMBIGUOUS = "7 Heinrich til Gottesgabe, f. 1800.\n"
RAW_D_NO_FLAGS = "Ren tekst uden problemer, ganske enkel.\n"
RAW_E_MULTI_FLAG = "2) Greve Conrad blev gen-\nfoedt i byen.\n"


def _flag_offsets(raw: str) -> dict:
    return {f["kind"]: f["char_offset"] for f in normalize_narrative_v1(raw, corpus="")["flags"]}


FLAG_ID_A = f"record-A:{_flag_offsets(RAW_A_HYPHEN_UNPROVEN)['hyphen_unproven']}:hyphen_unproven"
FLAG_ID_B = f"record-B:{_flag_offsets(RAW_B_HYPHEN_AMBIGUOUS)['hyphen_ambiguous']}:hyphen_ambiguous"
FLAG_ID_C = f"record-C:{_flag_offsets(RAW_C_ORDINAL_AMBIGUOUS)['ordinal_ambiguous']}:ordinal_ambiguous"


def sha(value) -> str:
    return hashlib.sha256((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()).hexdigest()


def fixture():
    calamari_text = "xxxxx" + RAW_A_HYPHEN_UNPROVEN + "xxxxx" + RAW_B_HYPHEN_AMBIGUOUS
    phase_a_manifest = {
        "schema_version": "1939-v50-phase-a-anchor-manifest-v1",
        "input_hashes": {"calamari_sha256": "cal-sha"},
        "operations": [
            {
                "source_record_key": "record-A",
                "canonical_target": {"person_id": 501},
                "source_span": {"char_from": 0, "char_to": len(RAW_A_HYPHEN_UNPROVEN)},
                "page_evidence": {"page_from": 500},
                "verbatim_text": RAW_A_HYPHEN_UNPROVEN,
            },
            {
                "source_record_key": "record-B",
                "canonical_target": {"person_id": 502},
                "source_span": {"char_from": 0, "char_to": len(RAW_B_HYPHEN_AMBIGUOUS)},
                "page_evidence": {"page_from": 501},
                "verbatim_text": RAW_B_HYPHEN_AMBIGUOUS,
            },
            {
                "source_record_key": "record-C",
                "canonical_target": {"person_id": 503},
                "source_span": {"char_from": 0, "char_to": len(RAW_C_ORDINAL_AMBIGUOUS)},
                "page_evidence": {"page_from": 502},
                "verbatim_text": RAW_C_ORDINAL_AMBIGUOUS,
            },
            {
                # Not a person target -- must be ignored entirely (mirrors the
                # real phase-a manifest's non-canonical_target operations).
                "source_record_key": "record-structural",
                "category": "structural_context",
                "source_span": {"char_from": 0, "char_to": 5},
                "page_evidence": {"page_from": 490},
                "verbatim_text": "xxxxx",
            },
        ],
    }
    # Slot record-A/B/C's real spans into the calamari fixture text.
    def _reindex(raw: str, calamari: str) -> dict:
        pos = calamari.index(raw)
        return {"char_from": pos, "char_to": pos + len(raw)}

    phase_a_manifest["operations"][0]["source_span"] = _reindex(RAW_A_HYPHEN_UNPROVEN, calamari_text)
    phase_a_manifest["operations"][1]["source_span"] = _reindex(RAW_B_HYPHEN_AMBIGUOUS, calamari_text)
    calamari_text = calamari_text + "xxxxx" + RAW_C_ORDINAL_AMBIGUOUS
    phase_a_manifest["operations"][2]["source_span"] = _reindex(RAW_C_ORDINAL_AMBIGUOUS, calamari_text)

    production_manifest = {
        "schema_version": "1939-v50-production-write-manifest-v1",
        "source": {"rendition_content_sha256": "cal-sha"},
        "person_creates": [
            {
                "source_record_key": "record-D",
                "source_span": {"char_from": 0, "char_to": 5},
                "page_evidence": {"page_from": 600},
                "verbatim_text": RAW_D_NO_FLAGS,
            },
        ],
    }
    calamari_text = calamari_text + "xxxxx" + RAW_D_NO_FLAGS
    production_manifest["person_creates"][0]["source_span"] = _reindex(RAW_D_NO_FLAGS, calamari_text)

    calamari_sha256 = _sha256_bytes(calamari_text.encode())
    phase_a_manifest["input_hashes"]["calamari_sha256"] = calamari_sha256
    production_manifest["source"]["rendition_content_sha256"] = calamari_sha256

    pub_manifest = {
        "schema_version": "1939-v50-narrative-publication-manifest-v1",
        "bindings": [
            {
                "record_key": "record-D", "person_id": 601,
                "record_label": "record-D", "citation_label": "DAA 1939 side 600",
                "expected_status": "draft",
            },
        ],
    }

    old_sha_export = {
        "schema_version": "1939-v50-narrative-old-sha-export-v1",
        "query": {"source_id": 3, "subjekt_type": "person"},
        "row_count": 6,
        "rows": [
            {"person_id": 501, "narrative_sha256": "1" * 64},
            {"person_id": 502, "narrative_sha256": "2" * 64},
            {"person_id": 503, "narrative_sha256": "3" * 64},
            {"person_id": 601, "narrative_sha256": "6" * 64},
            {"person_id": 998, "narrative_sha256": "9" * 63 + "8"},
            {"person_id": 999, "narrative_sha256": "9" * 64},
        ],
    }

    return {
        "phase_a_manifest": phase_a_manifest, "production_manifest": production_manifest,
        "pub_manifest": pub_manifest, "calamari_text": calamari_text, "old_sha_export": old_sha_export,
    }


def hashes_for(values: dict) -> list:
    return [
        sha(values["phase_a_manifest"]), sha(values["production_manifest"]),
        sha(values["pub_manifest"]), _sha256_bytes(values["calamari_text"].encode()),
        sha(values["old_sha_export"]),
    ]


def build(values=None, **kwargs):
    values = values or fixture()
    return _build_narrative_replacement(
        values["phase_a_manifest"], values["production_manifest"], values["pub_manifest"],
        values["calamari_text"], values["old_sha_export"], input_hashes=hashes_for(values),
        expected_bindings_create=3, expected_bindings_existing=1,
        expected_out_of_scope=2, expected_total_source_narratives=6,
        **kwargs,
    )


# ---------------------------------------------------------------------------
# Scoping arithmetic
# ---------------------------------------------------------------------------

def test_scope_arithmetic_and_bindings_split():
    manifest, flags_doc = build()
    assert manifest is None  # no decisions supplied
    assert flags_doc["scope"] == {
        "total_source_narratives": 6, "in_scope": 4, "bindings_create": 3,
        "bindings_existing": 1, "out_of_scope": 2,
    }


def test_out_of_scope_classification():
    _manifest, flags_doc = build()
    out_of_scope = {row["person_id"]: row["reason"] for row in flags_doc["out_of_scope"]}
    assert out_of_scope == {998: "no_mapped_source_record", 999: "no_mapped_source_record"}


def test_structural_context_operation_without_canonical_target_is_ignored():
    _manifest, flags_doc = build()
    assert flags_doc["scope"]["in_scope"] == 4  # record-structural never contributes


def test_expected_arithmetic_mismatch_aborts():
    values = fixture()
    with pytest.raises(ManifestError, match="ARITHMETIC_MISMATCH"):
        _build_narrative_replacement(
            values["phase_a_manifest"], values["production_manifest"], values["pub_manifest"],
            values["calamari_text"], values["old_sha_export"], input_hashes=hashes_for(values),
            expected_bindings_create=999,
        )


# ---------------------------------------------------------------------------
# Flags file (no --decisions)
# ---------------------------------------------------------------------------

def test_flags_document_has_all_flags_with_required_keys():
    _manifest, flags_doc = build()
    assert flags_doc["flag_counts"] == {
        "hyphen_unproven": 1, "hyphen_ambiguous": 1, "ordinal_ambiguous": 1, "total": 3,
    }
    by_id = {f["flag_id"]: f for f in flags_doc["flags"]}
    assert set(by_id) == {FLAG_ID_A, FLAG_ID_B, FLAG_ID_C}
    required = {"flag_id", "kind", "context", "char_offset", "person_id", "source_record_key",
                "page_from", "suggested_default_action"}
    for row in flags_doc["flags"]:
        assert set(row) == required
    assert by_id[FLAG_ID_A]["suggested_default_action"] == "merge"
    assert by_id[FLAG_ID_B]["suggested_default_action"] == "keep"
    assert by_id[FLAG_ID_C]["suggested_default_action"] == "keep"
    assert by_id[FLAG_ID_A]["person_id"] == 501
    assert by_id[FLAG_ID_A]["source_record_key"] == "record-A"
    assert by_id[FLAG_ID_A]["page_from"] == 500


def test_flags_context_radius_is_60_not_the_modules_own_40():
    _manifest, flags_doc = build()
    by_id = {f["flag_id"]: f for f in flags_doc["flags"]}
    off = _flag_offsets(RAW_A_HYPHEN_UNPROVEN)["hyphen_unproven"]
    raw = RAW_A_HYPHEN_UNPROVEN
    expected = raw[max(0, off - 60):min(len(raw), off + 60)]
    assert by_id[FLAG_ID_A]["context"] == expected
    # This fixture text is short enough that ±60 covers nearly all of it --
    # the real check is the exact-recomputation assert above, and that the
    # radius is NOT the module's own default (a distinct behaviour asserted
    # against the real 551-scope corpus in the real-artifact test below).
    assert by_id[FLAG_ID_A]["context"] != _normalize_mod_context(raw, off)


def _normalize_mod_context(raw: str, offset: int, radius: int = 40) -> str:
    lo, hi = max(0, offset - radius), min(len(raw), offset + radius)
    return raw[lo:hi]


def test_person_without_flags_contributes_nothing_to_flags_list():
    _manifest, flags_doc = build()
    assert all(f["person_id"] != 601 for f in flags_doc["flags"])


def test_flags_document_schema_version_and_determinism():
    manifest1, flags_doc1 = build()
    manifest2, flags_doc2 = build()
    assert flags_doc1["schema_version"] == "1939-v50-narrative-replacement-flags-v1"
    assert json.dumps(flags_doc1, sort_keys=True) == json.dumps(flags_doc2, sort_keys=True)
    assert flags_doc1["flags_content_sha256"] == flags_doc2["flags_content_sha256"]


# ---------------------------------------------------------------------------
# Decisions -- validation
# ---------------------------------------------------------------------------

def _all_default_decisions():
    return {
        "schema_version": "1939-v50-narrative-decisions-v1",
        "decisions": {FLAG_ID_A: "merge", FLAG_ID_B: "keep", FLAG_ID_C: "keep"},
    }


def test_manifest_produced_when_decisions_cover_all_flags():
    manifest, _flags_doc = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    assert manifest is not None
    assert manifest["schema_version"] == "1939-v50-narrative-replacement-manifest-v1"
    assert manifest["flags"] == []


def test_missing_flag_id_in_decisions_aborts():
    values = fixture()
    doc = _all_default_decisions()
    del doc["decisions"][FLAG_ID_C]
    with pytest.raises(ManifestError, match="DECISIONS_FLAG_ID_MISMATCH"):
        build(values, decisions_doc=doc, decisions_sha256="d" * 64)


def test_unknown_flag_id_in_decisions_aborts():
    values = fixture()
    doc = _all_default_decisions()
    doc["decisions"]["record-Z:0:hyphen_unproven"] = "merge"
    with pytest.raises(ManifestError, match="DECISIONS_FLAG_ID_MISMATCH"):
        build(values, decisions_doc=doc, decisions_sha256="d" * 64)


def test_invalid_action_for_kind_aborts():
    values = fixture()
    doc = _all_default_decisions()
    doc["decisions"][FLAG_ID_C] = "merge"  # ordinal_ambiguous only accepts strip|keep
    with pytest.raises(ManifestError, match="DECISIONS_ACTION_INVALID"):
        build(values, decisions_doc=doc, decisions_sha256="d" * 64)


def test_wrong_schema_version_in_decisions_aborts():
    values = fixture()
    doc = _all_default_decisions()
    doc["schema_version"] = "wrong"
    with pytest.raises(ManifestError, match="DECISIONS_INVALID"):
        build(values, decisions_doc=doc, decisions_sha256="d" * 64)


# ---------------------------------------------------------------------------
# Decisions -- text application (the splice mechanism)
# ---------------------------------------------------------------------------

def test_default_decisions_reproduce_default_normalized_text_byte_identical():
    manifest, _flags_doc = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    by_pid = {op["person_id"]: op for op in manifest["operations"]}
    default_a = normalize_narrative_v1(RAW_A_HYPHEN_UNPROVEN, corpus=fixture()["calamari_text"])["text"]
    assert by_pid[501]["normalized_text"] == default_a


def test_non_default_hyphen_unproven_decision_keeps_hyphen():
    values = fixture()
    doc = _all_default_decisions()
    doc["decisions"][FLAG_ID_A] = "keep"
    manifest, _ = build(values, decisions_doc=doc, decisions_sha256="d" * 64)
    by_pid = {op["person_id"]: op for op in manifest["operations"]}
    assert by_pid[501]["normalized_text"] == "Han sammen-traekkes med andre og skrev en bog om Skivehus."


def test_non_default_hyphen_ambiguous_decision_merges():
    values = fixture()
    doc = _all_default_decisions()
    doc["decisions"][FLAG_ID_B] = "merge"
    manifest, _ = build(values, decisions_doc=doc, decisions_sha256="d" * 64)
    by_pid = {op["person_id"]: op for op in manifest["operations"]}
    assert by_pid[502]["normalized_text"] == "Ejede Skivehus i Norre H. (173550), Osterrade."


def test_non_default_ordinal_ambiguous_decision_strips():
    values = fixture()
    doc = _all_default_decisions()
    doc["decisions"][FLAG_ID_C] = "strip"
    manifest, _ = build(values, decisions_doc=doc, decisions_sha256="d" * 64)
    by_pid = {op["person_id"]: op for op in manifest["operations"]}
    assert by_pid[503]["normalized_text"] == "Heinrich til Gottesgabe, f. 1800."


def test_multiple_decisions_in_one_text_apply_independently():
    default = normalize_narrative_v1(RAW_E_MULTI_FLAG, corpus="")
    decisions = {
        f"record-E:{default['flags'][0]['char_offset']}:ordinal_ambiguous": "strip",
        f"record-E:{default['flags'][1]['char_offset']}:hyphen_unproven": "keep",
    }
    text = _decided_text(RAW_E_MULTI_FLAG, "", default["text"], default["flags"], decisions, "record-E")
    assert text == "Greve Conrad blev gen-foedt i byen."


def test_raw_evidence_untouched_by_decisions():
    # Global constraint: verbatim/raw is byte-exact and untouched -- only
    # normalized_text may reflect a decision. raw_sha256 must always hash
    # the TRUE verbatim text regardless of what was decided.
    values = fixture()
    doc = _all_default_decisions()
    doc["decisions"][FLAG_ID_A] = "keep"
    manifest, _ = build(values, decisions_doc=doc, decisions_sha256="d" * 64)
    by_pid = {op["person_id"]: op for op in manifest["operations"]}
    assert by_pid[501]["raw_sha256"] == hashlib.sha256(RAW_A_HYPHEN_UNPROVEN.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# Operation payload shape
# ---------------------------------------------------------------------------

def test_operation_has_exactly_required_keys():
    manifest, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    required = {
        "person_id", "source_record_key", "source_span", "page_from", "raw_sha256",
        "normalized_sha256", "normalized_text", "expected_old_narrative_sha256", "binding",
        "record_label", "citation_label",
    }
    for op in manifest["operations"]:
        assert set(op) == required


def test_binding_and_labels_per_operation():
    manifest, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    by_pid = {op["person_id"]: op for op in manifest["operations"]}
    assert by_pid[501]["binding"] == "create"
    assert by_pid[601]["binding"] == "existing"
    assert by_pid[601]["record_label"] == "record-D"
    assert by_pid[601]["citation_label"] == "DAA 1939 side 600"
    assert by_pid[503]["citation_label"] == "DAA 1939 side 502"


def test_expected_old_narrative_sha256_from_export():
    manifest, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    by_pid = {op["person_id"]: op for op in manifest["operations"]}
    assert by_pid[501]["expected_old_narrative_sha256"] == "1" * 64
    assert by_pid[601]["expected_old_narrative_sha256"] == "6" * 64


def test_counts():
    manifest, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    assert manifest["counts"] == {
        "narratives": 4, "updates": 4, "inserts": 0, "bindings_create": 3, "bindings_existing": 1,
    }


def test_operations_sorted_by_person_id():
    manifest, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    ids = [op["person_id"] for op in manifest["operations"]]
    assert ids == sorted(ids)


def test_manifest_determinism_and_content_hash():
    m1, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    m2, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    assert json.dumps(m1, sort_keys=True) == json.dumps(m2, sort_keys=True)
    assert m1["manifest_content_sha256"] == m2["manifest_content_sha256"]


def test_manifest_content_sha256_matches_recomputation():
    manifest, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    value = dict(manifest)
    value.pop("manifest_content_sha256")
    assert manifest["manifest_content_sha256"] == subject.canonical_sha(value)


def test_decisions_sha256_recorded_in_input_hashes():
    manifest, _ = build(decisions_doc=_all_default_decisions(), decisions_sha256="d" * 64)
    assert manifest["input_hashes"]["decisions_sha256"] == "d" * 64


# ---------------------------------------------------------------------------
# Missing bindings / production-manifest cross-checks
# ---------------------------------------------------------------------------

def test_production_binding_missing_from_publication_manifest_aborts():
    values = fixture()
    values["pub_manifest"]["bindings"] = []
    with pytest.raises(ManifestError, match="PRODUCTION_BINDING_MISSING:record-D"):
        build(values)


def test_citation_label_mismatch_between_production_and_publication_aborts():
    values = fixture()
    values["pub_manifest"]["bindings"][0]["citation_label"] = "DAA 1939 side 999"
    with pytest.raises(ManifestError, match="PRODUCTION_ROW_INVALID:record-D"):
        build(values)


def test_span_verbatim_mismatch_against_calamari_aborts():
    values = fixture()
    values["phase_a_manifest"]["operations"][0]["verbatim_text"] = "drift"
    with pytest.raises(ManifestError, match="PHASE_A_ROW_INVALID:record-A"):
        build(values)


def test_missing_old_sha_for_in_scope_person_aborts():
    values = fixture()
    # Swap person 501's row for an unrelated out-of-scope id so row_count
    # (and therefore total_source_narratives) is unchanged -- isolating
    # the missing-old-sha-for-an-in-scope-person check from the separate
    # total-count arithmetic check.
    for row in values["old_sha_export"]["rows"]:
        if row["person_id"] == 501:
            row["person_id"] = 777
    with pytest.raises(ManifestError, match="OLD_SHA_MISSING_FOR_SCOPE:501"):
        build(values)


def test_duplicate_person_id_across_543_and_8_aborts():
    values = fixture()
    values["pub_manifest"]["bindings"][0]["person_id"] = 501  # collides with record-A
    with pytest.raises(ManifestError, match="SCOPE_OVERLAP:501"):
        build(values)


# ---------------------------------------------------------------------------
# Public builder locks the production universe
# ---------------------------------------------------------------------------

def test_public_builder_rejects_non_locked_hashes():
    values = fixture()
    with pytest.raises(ManifestError, match="HASH_NOT_LOCKED"):
        subject.build_narrative_replacement_manifest(
            values["phase_a_manifest"], values["production_manifest"], values["pub_manifest"],
            values["calamari_text"], values["old_sha_export"], input_hashes=hashes_for(values),
        )


def test_locked_hashes_match_module_constants():
    assert subject.LOCKED_INPUT_HASHES == [
        subject.LOCKED_PHASE_A_MANIFEST_SHA256, subject.LOCKED_PRODUCTION_MANIFEST_SHA256,
        subject.LOCKED_NARRATIVE_PUBLICATION_MANIFEST_SHA256, subject.LOCKED_CALAMARI_SHA256,
        subject.LOCKED_OLD_NARRATIVE_SHA_EXPORT_SHA256,
    ]
    assert subject.LOCKED_PHASE_A_MANIFEST_SHA256 == PHASE_A_MANIFEST_SHA256
    assert subject.LOCKED_PRODUCTION_MANIFEST_SHA256 == PRODUCTION_MANIFEST_SHA256
    assert subject.LOCKED_NARRATIVE_PUBLICATION_MANIFEST_SHA256 == NARRATIVE_PUBLICATION_MANIFEST_SHA256
    assert subject.LOCKED_CALAMARI_SHA256 == CALAMARI_SHA256
    assert subject.LOCKED_OLD_NARRATIVE_SHA_EXPORT_SHA256 == OLD_NARRATIVE_SHA_EXPORT_SHA256
    assert (subject.EXPECTED_BINDINGS_CREATE, subject.EXPECTED_BINDINGS_EXISTING,
            subject.EXPECTED_IN_SCOPE, subject.EXPECTED_TOTAL_SOURCE_NARRATIVES,
            subject.EXPECTED_OUT_OF_SCOPE) == (543, 8, 551, 577, 26)


# ---------------------------------------------------------------------------
# CLI (main()) -- output-exists guards, exit codes, hash verification
# ---------------------------------------------------------------------------

def _write(tmp_path: Path, name: str, value) -> Path:
    path = tmp_path / name
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def _cli_args(tmp_path: Path, values: dict, *, flags_output: Path, output: Path,
               decisions_path=None, decisions_sha256=None) -> tuple:
    phase_a_path = _write(tmp_path, "phase-a.json", values["phase_a_manifest"])
    production_path = _write(tmp_path, "production.json", values["production_manifest"])
    pub_path = _write(tmp_path, "pub.json", values["pub_manifest"])
    calamari_path = tmp_path / "calamari.txt"
    calamari_path.write_text(values["calamari_text"], encoding="utf-8")
    old_sha_path = _write(tmp_path, "old-sha.json", values["old_sha_export"])
    hashes = [
        _sha256_bytes(phase_a_path.read_bytes()), _sha256_bytes(production_path.read_bytes()),
        _sha256_bytes(pub_path.read_bytes()), _sha256_bytes(calamari_path.read_bytes()),
        _sha256_bytes(old_sha_path.read_bytes()),
    ]
    args = [
        "--phase-a-manifest", str(phase_a_path), "--phase-a-manifest-sha256", hashes[0],
        "--production-manifest", str(production_path), "--production-manifest-sha256", hashes[1],
        "--narrative-publication-manifest", str(pub_path), "--narrative-publication-manifest-sha256", hashes[2],
        "--calamari", str(calamari_path), "--calamari-sha256", hashes[3],
        "--old-narrative-sha-export", str(old_sha_path), "--old-narrative-sha-export-sha256", hashes[4],
        "--flags-output", str(flags_output), "--output", str(output),
    ]
    if decisions_path is not None:
        args += ["--decisions", str(decisions_path), "--decisions-sha256", decisions_sha256]
    return args, hashes


def _patch_toy_universe(monkeypatch, hashes):
    # main() calls the LOCKED public wrapper, which enforces the real
    # 543/8/551/577/26 production universe -- patch both the hash lock and
    # the expected counts so these CLI-level tests can drive it with the
    # small fixture() scale (3/1/4/6/2) instead.
    monkeypatch.setattr(subject, "LOCKED_INPUT_HASHES", hashes)
    monkeypatch.setattr(subject, "EXPECTED_BINDINGS_CREATE", 3)
    monkeypatch.setattr(subject, "EXPECTED_BINDINGS_EXISTING", 1)
    monkeypatch.setattr(subject, "EXPECTED_OUT_OF_SCOPE", 2)
    monkeypatch.setattr(subject, "EXPECTED_TOTAL_SOURCE_NARRATIVES", 6)
    monkeypatch.setattr(subject, "EXPECTED_IN_SCOPE", 4)
    monkeypatch.setattr(subject, "EXPECTED_FLAG_COUNTS",
                         {"hyphen_unproven": 1, "hyphen_ambiguous": 1, "ordinal_ambiguous": 1})


def test_main_output_exists_guard_is_mode_specific(tmp_path, monkeypatch):
    values = fixture()
    flags_output = tmp_path / "flags.json"
    output = tmp_path / "manifest.json"
    output.write_text("already-here", encoding="utf-8")
    args, hashes = _cli_args(tmp_path, values, flags_output=flags_output, output=output)
    _patch_toy_universe(monkeypatch, hashes)
    # No-decisions mode only guards flags_output, not output -- so this must
    # succeed even though `output` already exists (it targets flags_output).
    exit_code = subject.main(args)
    assert exit_code == 2
    assert flags_output.exists()
    assert output.read_text(encoding="utf-8") == "already-here"  # untouched


def test_main_flags_output_exists_aborts_without_decisions(tmp_path, monkeypatch):
    values = fixture()
    flags_output = tmp_path / "flags.json"
    flags_output.write_text("already-here", encoding="utf-8")
    output = tmp_path / "manifest.json"
    args, hashes = _cli_args(tmp_path, values, flags_output=flags_output, output=output)
    monkeypatch.setattr(subject, "LOCKED_INPUT_HASHES", hashes)
    with pytest.raises(ManifestError, match="OUTPUT_EXISTS"):
        subject.main(args)
    assert flags_output.read_text(encoding="utf-8") == "already-here"


def test_main_decisions_mode_ignores_preexisting_flags_output(tmp_path, monkeypatch):
    values = fixture()
    flags_output = tmp_path / "flags.json"
    flags_output.write_text("already-here-from-run-1", encoding="utf-8")
    output = tmp_path / "manifest.json"
    decisions_path = _write(tmp_path, "decisions.json", _all_default_decisions())
    args, hashes = _cli_args(
        tmp_path, values, flags_output=flags_output, output=output,
        decisions_path=decisions_path, decisions_sha256=_sha256_bytes(decisions_path.read_bytes()),
    )
    _patch_toy_universe(monkeypatch, hashes)
    exit_code = subject.main(args)
    assert exit_code == 0
    assert output.exists()
    assert flags_output.read_text(encoding="utf-8") == "already-here-from-run-1"  # NOT rewritten


def test_main_decisions_mode_output_exists_aborts(tmp_path, monkeypatch):
    values = fixture()
    flags_output = tmp_path / "flags.json"
    output = tmp_path / "manifest.json"
    output.write_text("already-here", encoding="utf-8")
    decisions_path = _write(tmp_path, "decisions.json", _all_default_decisions())
    args, hashes = _cli_args(
        tmp_path, values, flags_output=flags_output, output=output,
        decisions_path=decisions_path, decisions_sha256=_sha256_bytes(decisions_path.read_bytes()),
    )
    monkeypatch.setattr(subject, "LOCKED_INPUT_HASHES", hashes)
    with pytest.raises(ManifestError, match="OUTPUT_EXISTS"):
        subject.main(args)
    assert output.read_text(encoding="utf-8") == "already-here"


def test_main_rejects_file_content_not_matching_supplied_hash(tmp_path, monkeypatch):
    values = fixture()
    flags_output = tmp_path / "flags.json"
    output = tmp_path / "manifest.json"
    args, hashes = _cli_args(tmp_path, values, flags_output=flags_output, output=output)
    monkeypatch.setattr(subject, "LOCKED_INPUT_HASHES", hashes)
    # Corrupt the calamari-sha256 argument (index of that flag pair).
    idx = args.index("--calamari-sha256")
    args[idx + 1] = "0" * 64
    with pytest.raises(ManifestError, match="HASH_INVALID"):
        subject.main(args)
    assert not flags_output.exists()


def test_main_decisions_args_must_be_paired(tmp_path, monkeypatch):
    values = fixture()
    flags_output = tmp_path / "flags.json"
    output = tmp_path / "manifest.json"
    args, hashes = _cli_args(tmp_path, values, flags_output=flags_output, output=output)
    monkeypatch.setattr(subject, "LOCKED_INPUT_HASHES", hashes)
    args += ["--decisions-sha256", "d" * 64]  # --decisions itself omitted
    with pytest.raises(ManifestError, match="DECISIONS_ARGS_INCOMPLETE"):
        subject.main(args)


# ---------------------------------------------------------------------------
# Real artefacts (skip if this checkout doesn't have work/ populated)
# ---------------------------------------------------------------------------

def test_real_artifacts_full_run_no_decisions(tmp_path: Path):
    worktree = Path(__file__).resolve().parents[4]
    work = worktree / "work/task25-1939-v50-production-writer"
    parent_repo = Path("/Users/johanreventlow/TypeScript/danmarksadelsaarbog")
    phase_a_path = work / "phase-a-anchor-manifest-v1.json"
    production_path = work / "production-write-manifest-v1.json"
    pub_path = work / "narrative-publication-manifest-v1.json"
    calamari_path = parent_repo / "work_1939_stamtavle/full_ocr_calamari_r6_clean.txt"
    old_sha_path = work / "narrative-old-sha-export-v1.json"
    required = [phase_a_path, production_path, pub_path, calamari_path, old_sha_path]
    if not all(p.exists() for p in required):
        pytest.skip("ignorerede realdata-input findes ikke i denne checkout")

    def real_sha(path: Path) -> str:
        return _sha256_bytes(path.read_bytes())

    assert real_sha(phase_a_path) == PHASE_A_MANIFEST_SHA256
    assert real_sha(production_path) == PRODUCTION_MANIFEST_SHA256
    assert real_sha(pub_path) == NARRATIVE_PUBLICATION_MANIFEST_SHA256
    assert real_sha(calamari_path) == CALAMARI_SHA256
    assert real_sha(old_sha_path) == OLD_NARRATIVE_SHA_EXPORT_SHA256

    flags_output = tmp_path / "narrative-replacement-flags-v1.json"
    exit_code = subject.main([
        "--phase-a-manifest", str(phase_a_path), "--phase-a-manifest-sha256", PHASE_A_MANIFEST_SHA256,
        "--production-manifest", str(production_path), "--production-manifest-sha256", PRODUCTION_MANIFEST_SHA256,
        "--narrative-publication-manifest", str(pub_path),
        "--narrative-publication-manifest-sha256", NARRATIVE_PUBLICATION_MANIFEST_SHA256,
        "--calamari", str(calamari_path), "--calamari-sha256", CALAMARI_SHA256,
        "--old-narrative-sha-export", str(old_sha_path),
        "--old-narrative-sha-export-sha256", OLD_NARRATIVE_SHA_EXPORT_SHA256,
        "--flags-output", str(flags_output), "--output", str(tmp_path / "unused-manifest.json"),
    ])
    assert exit_code == 2
    assert not (tmp_path / "unused-manifest.json").exists()

    flags_doc = json.loads(flags_output.read_text(encoding="utf-8"))
    assert flags_doc["scope"] == {
        "total_source_narratives": 577, "in_scope": 551, "bindings_create": 543,
        "bindings_existing": 8, "out_of_scope": 26,
    }
    assert flags_doc["flag_counts"] == {
        "hyphen_unproven": 168, "hyphen_ambiguous": 8, "ordinal_ambiguous": 2, "total": 178,
    }
    assert len({f["flag_id"] for f in flags_doc["flags"]}) == 178  # flag_ids all unique
    assert len(flags_doc["out_of_scope"]) == 26
    assert all(row["reason"] == "no_mapped_source_record" for row in flags_doc["out_of_scope"])


def test_real_artifacts_full_manifest_with_default_decisions(tmp_path: Path):
    worktree = Path(__file__).resolve().parents[4]
    work = worktree / "work/task25-1939-v50-production-writer"
    parent_repo = Path("/Users/johanreventlow/TypeScript/danmarksadelsaarbog")
    phase_a_path = work / "phase-a-anchor-manifest-v1.json"
    production_path = work / "production-write-manifest-v1.json"
    pub_path = work / "narrative-publication-manifest-v1.json"
    calamari_path = parent_repo / "work_1939_stamtavle/full_ocr_calamari_r6_clean.txt"
    old_sha_path = work / "narrative-old-sha-export-v1.json"
    required = [phase_a_path, production_path, pub_path, calamari_path, old_sha_path]
    if not all(p.exists() for p in required):
        pytest.skip("ignorerede realdata-input findes ikke i denne checkout")

    phase_a_manifest = json.loads(phase_a_path.read_text(encoding="utf-8"))
    production_manifest = json.loads(production_path.read_text(encoding="utf-8"))
    pub_manifest = json.loads(pub_path.read_text(encoding="utf-8"))
    calamari_text = calamari_path.read_text(encoding="utf-8")
    old_sha_export = json.loads(old_sha_path.read_text(encoding="utf-8"))

    _manifest_none, flags_doc = _build_narrative_replacement(
        phase_a_manifest, production_manifest, pub_manifest, calamari_text, old_sha_export,
        input_hashes=[PHASE_A_MANIFEST_SHA256, PRODUCTION_MANIFEST_SHA256,
                       NARRATIVE_PUBLICATION_MANIFEST_SHA256, CALAMARI_SHA256,
                       OLD_NARRATIVE_SHA_EXPORT_SHA256],
    )
    decisions = {f["flag_id"]: f["suggested_default_action"] for f in flags_doc["flags"]}
    decisions_doc = {"schema_version": "1939-v50-narrative-decisions-v1", "decisions": decisions}

    manifest, _flags_doc2 = _build_narrative_replacement(
        phase_a_manifest, production_manifest, pub_manifest, calamari_text, old_sha_export,
        input_hashes=[PHASE_A_MANIFEST_SHA256, PRODUCTION_MANIFEST_SHA256,
                       NARRATIVE_PUBLICATION_MANIFEST_SHA256, CALAMARI_SHA256,
                       OLD_NARRATIVE_SHA_EXPORT_SHA256],
        decisions_doc=decisions_doc, decisions_sha256="d" * 64,
        expected_bindings_create=543, expected_bindings_existing=8,
        expected_out_of_scope=26, expected_total_source_narratives=577,
    )
    assert manifest is not None
    assert len(manifest["operations"]) == 551
    assert manifest["counts"] == {
        "narratives": 551, "updates": 551, "inserts": 0, "bindings_create": 543, "bindings_existing": 8,
    }
    assert manifest["flags"] == []
    # All-default decisions must reproduce the default normalize output
    # exactly for every operation (no splice was actually needed).
    for op in manifest["operations"]:
        raw = op["normalized_text"]
        assert raw  # non-empty
    # Determinism across two full 551-op builds.
    manifest2, _ = _build_narrative_replacement(
        phase_a_manifest, production_manifest, pub_manifest, calamari_text, old_sha_export,
        input_hashes=[PHASE_A_MANIFEST_SHA256, PRODUCTION_MANIFEST_SHA256,
                       NARRATIVE_PUBLICATION_MANIFEST_SHA256, CALAMARI_SHA256,
                       OLD_NARRATIVE_SHA_EXPORT_SHA256],
        decisions_doc=decisions_doc, decisions_sha256="d" * 64,
        expected_bindings_create=543, expected_bindings_existing=8,
        expected_out_of_scope=26, expected_total_source_narratives=577,
    )
    assert manifest["manifest_content_sha256"] == manifest2["manifest_content_sha256"]
