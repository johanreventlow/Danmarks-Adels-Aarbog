"""Tests for finalize_c3_apply_manifest_1939_v50.py.

Fixtures mirror the exact five-case/six-record shape that
build_c3_apply_candidate_1939_v50.py (Task 1) and
export_c3_apply_preview_1939_v50.R (Task 2, see
test_export_c3_apply_preview_1939_v50.R's fake-gateway fixtures) actually
produce. Identifiers, hashes, and structural metadata only -- no real
narrative prose; "PROSE-FIXTURE-NEVER-SENT-TO-STDOUT" is fixture noise used
only to prove it never reaches stdout/stderr, exactly as Task 2's own test
suite documents for its analogous fixture string.
"""

import copy
import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path
from typing import Any, Callable, Dict, Optional

import pytest


SCRIPT_DIR = Path(__file__).resolve().parent
MODULE_PATH = SCRIPT_DIR / "finalize_c3_apply_manifest_1939_v50.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


mod = load_module("finalize_c3_apply_manifest_1939_v50", MODULE_PATH)


def sha(letter: str) -> str:
    return letter * 64


DB_NAME = "postgres"
SYSTEM_IDENTIFIER = "1234567890123456789"


# ---------------------------------------------------------------------------
# Candidate fixture (Task 1's exact five-case, six-record output shape)
# ---------------------------------------------------------------------------

def assign_decision(rid, record_key, target_person_id, side="501",
                     raw_char="a", norm_char="b"):
    return {
        "action": "assign", "rid": rid, "record_key": record_key,
        "target_person_id": target_person_id,
        "raw_sha256": sha(raw_char),
        "normalized_text": "PROSE-FIXTURE-NEVER-SENT-TO-STDOUT",
        "normalized_sha256": sha(norm_char),
        "normalization_version": "narrative_norm_v1",
        "normalization_flags": [],
        "expected_narrative": {
            "privat": False, "side": side, "record_label": record_key,
            "citation_label": "DAA 1939 side " + side,
        },
    }


def no_publication_decision(rid, record_key):
    return {"action": "no_publication", "rid": rid, "record_key": record_key}


def candidate_cases():
    return [
        {"case_id": "case-1",
         "identity": {"action": "different", "person_ids": [101, 201]},
         "record_decisions": [assign_decision("rid-1", "rk-1", 101)]},
        {"case_id": "case-2",
         "identity": {"action": "different", "person_ids": [102, 202]},
         "record_decisions": [assign_decision("rid-2", "rk-2", 102)]},
        {"case_id": "case-3",
         "identity": {"action": "different", "person_ids": [103, 203]},
         "record_decisions": [assign_decision("rid-3", "rk-3", 103)]},
        # Spejler fasens reelle facon (2026-08-23): case-4 er testens
        # modstykke til den ægte R28 — recordbeslutningen flippet fra assign
        # til no_publication.
        {"case_id": "case-4",
         "identity": {"action": "different", "person_ids": [104, 204]},
         "record_decisions": [no_publication_decision("rid-4", "rk-4")]},
        {"case_id": "case-5",
         "identity": {"action": "different", "person_ids": [105, 205]},
         "record_decisions": [
             assign_decision("rid-5", "rk-5", 105),
             no_publication_decision("rid-6", "rk-6")]},
    ]


def candidate_document(cases=None) -> Dict[str, Any]:
    doc = {
        "schema_version": "1939-v50-c3-apply-candidate-v1",
        "input_hashes": {
            "decisions_sha256": sha("1"), "selection_sha256": sha("2"),
            "state_sha256": sha("3"), "review_sha256": sha("4"),
            "c0_candidates_sha256": sha("5"), "c0_decisions_sha256": sha("6"),
        },
        "counts": {"cases": 5, "identity_different": 5, "record_assign": 4,
                   "record_no_publication": 2},
        "cases": cases if cases is not None else candidate_cases(),
    }
    doc["canonical_content_sha256"] = mod._sha(mod._canonical_bytes(doc))
    return doc


def candidate_raw_bytes(doc: Optional[Dict[str, Any]] = None) -> bytes:
    doc = doc if doc is not None else candidate_document()
    return json.dumps(doc, ensure_ascii=False).encode("utf-8")


# ---------------------------------------------------------------------------
# DB-preview fixture (Task 2's exact db-preview envelope)
# ---------------------------------------------------------------------------

def default_identity_pairs():
    return [
        {"case_id": "case-%d" % i, "person_ids": [100 + i, 200 + i],
         "component_overlap": False, "existing_rejection": False}
        for i in range(1, 6)
    ]


def default_source_records():
    rows = [
        {"rid": "rid-%d" % i, "record_key": "rk-%d" % i, "match_count": 1,
         "verbatim_sha256": sha("a"), "side": "501"}
        for i in range(1, 6)
    ]
    rows.append({"rid": "rid-6", "record_key": "rk-6", "match_count": 1,
                 "verbatim_sha256": sha("e"), "side": "502"})
    return rows


def default_target_narratives():
    # rid-4 er no_publication og har derfor ingen target-narrativ-række.
    return [
        {"rid": "rid-%d" % i, "person_id": 100 + i, "narrative_id": 9000 + i,
         "privat": False, "old_sha256": sha("c")}
        for i in (1, 2, 3, 5)
    ]


def default_bindings():
    # En 'absent'-binding HAR ingen person: både DB-validatoren
    # (validate_reimport_case_elements) og R-gatewayen kræver null her.
    rows = [
        {"record_key": "rk-%d" % i, "status": "absent",
         "binding_person_id": None}
        for i in range(1, 6)
    ]
    rows.append({"record_key": "rk-6", "status": "absent",
                 "binding_person_id": None})
    return rows


def default_before_state():
    return {
        "database_name": DB_NAME, "system_identifier": SYSTEM_IDENTIFIER,
        "identity_pairs": default_identity_pairs(),
        "source_records": default_source_records(),
        "target_narratives": default_target_narratives(),
        "bindings": default_bindings(),
        "source_anchors": [], "identity_components": [],
    }


def preview_document(candidate_doc=None, candidate_bytes=None,
                      before_state=None) -> Dict[str, Any]:
    candidate_doc = candidate_doc if candidate_doc is not None else candidate_document()
    candidate_bytes = (candidate_bytes if candidate_bytes is not None
                       else candidate_raw_bytes(candidate_doc))
    before_state = before_state if before_state is not None else default_before_state()
    before_state_canonical = json.dumps(before_state, ensure_ascii=False)
    return {
        "schema_version": "1939-v50-c3-apply-db-preview-v1",
        "candidate_file_sha256": hashlib.sha256(candidate_bytes).hexdigest(),
        "candidate_canonical_content_sha256": candidate_doc["canonical_content_sha256"],
        "database": {"database_name": DB_NAME,
                     "system_identifier": SYSTEM_IDENTIFIER},
        "before_state": before_state,
        "before_state_canonical": before_state_canonical,
        "before_state_canonical_sha256":
            hashlib.sha256(before_state_canonical.encode("utf-8")).hexdigest(),
        "candidate": candidate_doc,
    }


def preview_raw_bytes(doc: Dict[str, Any]) -> bytes:
    return json.dumps(doc, ensure_ascii=False).encode("utf-8")


def build_pair(candidate_doc=None, before_state=None,
               preview_mutator: Optional[Callable[[Dict[str, Any]], None]] = None):
    candidate_doc = candidate_doc if candidate_doc is not None else candidate_document()
    candidate_bytes = candidate_raw_bytes(candidate_doc)
    preview_doc = preview_document(candidate_doc, candidate_bytes, before_state)
    if preview_mutator is not None:
        preview_mutator(preview_doc)
    return candidate_bytes, preview_raw_bytes(preview_doc)


def finalize(candidate_doc=None, before_state=None, preview_mutator=None):
    candidate_bytes, preview_bytes = build_pair(
        candidate_doc, before_state, preview_mutator)
    return mod.finalize_manifest(candidate_bytes, preview_bytes)


def before_state_with(mutator: Callable[[Dict[str, Any]], None]) -> Dict[str, Any]:
    state = default_before_state()
    mutator(state)
    return state


def assert_fails(code, candidate_doc=None, before_state=None,
                 preview_mutator=None, candidate_bytes=None, preview_bytes=None):
    if candidate_bytes is None or preview_bytes is None:
        candidate_bytes, preview_bytes = build_pair(
            candidate_doc, before_state, preview_mutator)
    with pytest.raises(SystemExit) as error:
        mod.finalize_manifest(candidate_bytes, preview_bytes)
    assert str(error.value) == code, (code, str(error.value))


# ===========================================================================
# Step 1: one-to-one join, exact counts, stable element IDs
# ===========================================================================

def test_exact_counts_and_shape():
    manifest = finalize()
    assert manifest["schema_version"] == "1939-v50-c3-apply-manifest-v1"
    assert manifest["counts"] == {
        "cases": 5, "identity_events": 5,
        "assign_events": 4, "no_publication_events": 2,
        "events": 11,
    }
    assert manifest["database"] == {
        "database_name": DB_NAME, "system_identifier": SYSTEM_IDENTIFIER}
    assert len(manifest["cases"]) == 5
    # Each case's "events" list holds only its record decisions (assign /
    # no_publication) -- 5 + 1 = 6. counts["events"] (11) additionally
    # counts the one identity-different resolution per case (5), which is
    # represented on the case itself (after_state/before_state), not as a
    # separate list entry.
    assert sum(len(case["events"]) for case in manifest["cases"]) == 6


def test_stable_element_ids_are_case_id_and_case_id_rid_derived():
    manifest = finalize()
    case_1 = manifest["cases"][0]
    assert case_1["element_id"] == "case:case-1"
    assert case_1["case_id"] == "case-1"
    assign_event = case_1["events"][0]
    assert assign_event["element_id"] == "case:case-1:rid:rid-1"
    case_5 = manifest["cases"][4]
    no_pub_event = [e for e in case_5["events"] if e["action"] == "no_publication"][0]
    assert no_pub_event["element_id"] == "case:case-5:rid:rid-6"
    # Every element_id across the manifest is unique.
    ids = [case["element_id"] for case in manifest["cases"]]
    ids += [event["element_id"] for case in manifest["cases"]
            for event in case["events"]]
    assert len(ids) == len(set(ids))


def test_assign_event_carries_after_state_and_before_state():
    manifest = finalize()
    event = manifest["cases"][0]["events"][0]
    assert event["action"] == "assign"
    assert event["rid"] == "rid-1"
    assert event["record_key"] == "rk-1"
    assert event["after_state"] == {
        "target_person_id": 101,
        "raw_sha256": sha("a"),
        "normalized_text": "PROSE-FIXTURE-NEVER-SENT-TO-STDOUT",
        "normalized_sha256": sha("b"),
        "normalization_version": "narrative_norm_v1",
        "normalization_flags": [],
        "expected_narrative": {
            "privat": False, "side": "501", "record_label": "rk-1",
            "citation_label": "DAA 1939 side 501",
        },
    }
    assert event["before_state"] == {
        "source_record": {"match_count": 1, "verbatim_sha256": sha("a"),
                          "side": "501"},
        "target_narrative": {"person_id": 101, "narrative_id": 9001,
                             "privat": False, "old_sha256": sha("c")},
        "binding": {"status": "absent", "binding_person_id": None},
    }


def test_no_publication_event_has_no_target_narrative_and_empty_after_state():
    manifest = finalize()
    case_5 = manifest["cases"][4]
    event = [e for e in case_5["events"] if e["action"] == "no_publication"][0]
    assert event["after_state"] == {}
    assert set(event["before_state"]) == {"source_record", "binding"}


def test_rejects_duplicate_case_id_in_identity_pairs():
    def mutate(state):
        state["identity_pairs"][4]["case_id"] = "case-1"
    assert_fails("C3_APPLY_MANIFEST_CASE_JOIN_MISMATCH",
                before_state=before_state_with(mutate))


def test_rejects_unknown_case_id_in_identity_pairs():
    def mutate(state):
        state["identity_pairs"][4]["case_id"] = "case-9"
    assert_fails("C3_APPLY_MANIFEST_CASE_JOIN_MISMATCH",
                before_state=before_state_with(mutate))


def test_rejects_short_identity_pairs_list_as_malformed_response():
    def mutate(state):
        del state["identity_pairs"][4]
    assert_fails("C3_APPLY_MANIFEST_PREVIEW_INVALID",
                before_state=before_state_with(mutate))


def test_rejects_same_size_swapped_rid_in_source_records():
    def mutate(state):
        state["source_records"][4]["rid"] = "rid-9"
    assert_fails("C3_APPLY_MANIFEST_RECORD_JOIN_MISMATCH",
                before_state=before_state_with(mutate))


def test_rejects_duplicate_rid_in_source_records():
    def mutate(state):
        state["source_records"][5]["rid"] = "rid-1"
    assert_fails("C3_APPLY_MANIFEST_RECORD_JOIN_MISMATCH",
                before_state=before_state_with(mutate))


def test_rejects_same_size_swapped_record_key_in_bindings():
    def mutate(state):
        state["bindings"][4]["record_key"] = "rk-9"
    assert_fails("C3_APPLY_MANIFEST_BINDING_JOIN_MISMATCH",
                before_state=before_state_with(mutate))


def test_rejects_duplicate_record_key_in_bindings():
    def mutate(state):
        state["bindings"][5]["record_key"] = "rk-1"
    assert_fails("C3_APPLY_MANIFEST_BINDING_JOIN_MISMATCH",
                before_state=before_state_with(mutate))


def test_rejects_short_target_narratives_list():
    def mutate(state):
        del state["target_narratives"][3]
    assert_fails("C3_APPLY_MANIFEST_PREVIEW_INVALID",
                before_state=before_state_with(mutate))


def test_rejects_extra_no_publication_row_in_target_narratives():
    def mutate(state):
        state["target_narratives"].append({
            "rid": "rid-6", "person_id": 105, "narrative_id": None,
            "privat": False, "old_sha256": None})
    assert_fails("C3_APPLY_MANIFEST_PREVIEW_INVALID",
                before_state=before_state_with(mutate))


# ===========================================================================
# Step 2: drift and binding-state
# ===========================================================================

def test_hash_drift():
    def mutate(state):
        state["source_records"][0]["verbatim_sha256"] = sha("9")
    assert_fails("C3_APPLY_MANIFEST_HASH_DRIFT",
                before_state=before_state_with(mutate))


def test_side_drift():
    def mutate(state):
        state["source_records"][0]["side"] = "999"
    assert_fails("C3_APPLY_MANIFEST_SIDE_DRIFT",
                before_state=before_state_with(mutate))


def test_source_anchor_mismatch():
    def mutate(state):
        state["source_records"][0]["record_key"] = "rk-9"
    assert_fails("C3_APPLY_MANIFEST_SOURCE_ANCHOR_MISMATCH",
                before_state=before_state_with(mutate))


def test_match_count_invalid():
    def mutate(state):
        state["source_records"][0]["match_count"] = 2
    assert_fails("C3_APPLY_MANIFEST_MATCH_COUNT_INVALID",
                before_state=before_state_with(mutate))


def test_target_person_mismatch():
    def mutate(state):
        state["target_narratives"][0]["person_id"] = 999
    assert_fails("C3_APPLY_MANIFEST_TARGET_PERSON_MISMATCH",
                before_state=before_state_with(mutate))


def test_narrative_private_drift():
    def mutate(state):
        state["target_narratives"][0]["privat"] = True
    assert_fails("C3_APPLY_MANIFEST_PRIVATE_DRIFT",
                before_state=before_state_with(mutate))


def test_noncanonical_binding_label():
    def mutate(state):
        state["bindings"][0]["status"] = "weird_status"
    assert_fails("C3_APPLY_MANIFEST_NONCANONICAL_LABEL",
                before_state=before_state_with(mutate))


@pytest.mark.parametrize("status", ["draft_other_record", "published", "withdrawn"])
def test_assign_binding_other_than_absent_or_draft_same_record(status):
    def mutate(state):
        state["bindings"][0]["status"] = status
    assert_fails("C3_APPLY_MANIFEST_BINDING_INVALID",
                before_state=before_state_with(mutate))


def test_assign_draft_same_record_wrong_owner():
    def mutate(state):
        state["bindings"][0]["status"] = "draft_same_record"
        state["bindings"][0]["binding_person_id"] = 999
    assert_fails("C3_APPLY_MANIFEST_BINDING_INVALID",
                before_state=before_state_with(mutate))


def test_assign_draft_same_record_correct_owner_is_accepted():
    def mutate(state):
        state["bindings"][0]["status"] = "draft_same_record"
        state["bindings"][0]["binding_person_id"] = 101
    manifest = finalize(before_state=before_state_with(mutate))
    binding = manifest["cases"][0]["events"][0]["before_state"]["binding"]
    assert binding == {"status": "draft_same_record", "binding_person_id": 101}


@pytest.mark.parametrize("status", [
    "draft_same_record", "draft_other_record", "published", "withdrawn"])
def test_no_publication_with_any_non_absent_binding(status):
    def mutate(state):
        state["bindings"][5]["status"] = status
    assert_fails("C3_APPLY_MANIFEST_BINDING_ACTIVE_FOR_NO_PUBLICATION",
                before_state=before_state_with(mutate))


def test_component_overlap():
    def mutate(state):
        state["identity_pairs"][0]["component_overlap"] = True
    assert_fails("C3_APPLY_MANIFEST_COMPONENT_OVERLAP",
                before_state=before_state_with(mutate))


def test_rejection_fingerprint_differing_from_preview():
    def mutate(state):
        state["identity_pairs"][0]["existing_rejection"] = True
    assert_fails("C3_APPLY_MANIFEST_REJECTION_FINGERPRINT_MISMATCH",
                before_state=before_state_with(mutate))


def test_identity_pair_person_ids_mismatch():
    def mutate(state):
        state["identity_pairs"][0]["person_ids"] = [101, 999]
    assert_fails("C3_APPLY_MANIFEST_IDENTITY_PAIR_MISMATCH",
                before_state=before_state_with(mutate))


def test_wrong_database_name():
    def mutate(preview_doc):
        preview_doc["database"]["database_name"] = "otherdb"
    assert_fails("C3_APPLY_MANIFEST_DATABASE_MISMATCH", preview_mutator=mutate)


def test_wrong_system_identifier():
    def mutate(preview_doc):
        preview_doc["database"]["system_identifier"] = "999"
    assert_fails("C3_APPLY_MANIFEST_DATABASE_MISMATCH", preview_mutator=mutate)


def test_database_name_structurally_invalid():
    def mutate(preview_doc):
        preview_doc["database"]["database_name"] = ""
        preview_doc["before_state"]["database_name"] = ""
    assert_fails("C3_APPLY_MANIFEST_DATABASE_INVALID", preview_mutator=mutate)


# ===========================================================================
# Cross-hash linkage between candidate and preview
# ===========================================================================

def test_candidate_file_hash_mismatch():
    def mutate(preview_doc):
        preview_doc["candidate_file_sha256"] = sha("f")
    assert_fails("C3_APPLY_MANIFEST_CANDIDATE_FILE_HASH_MISMATCH",
                preview_mutator=mutate)


def test_candidate_canonical_hash_mismatch():
    def mutate(preview_doc):
        preview_doc["candidate_canonical_content_sha256"] = sha("f")
    assert_fails("C3_APPLY_MANIFEST_CANDIDATE_CANONICAL_HASH_MISMATCH",
                preview_mutator=mutate)


def test_candidate_embed_mismatch():
    def mutate(preview_doc):
        preview_doc["candidate"]["cases"][0]["case_id"] = "case-tampered"
    assert_fails("C3_APPLY_MANIFEST_CANDIDATE_EMBED_MISMATCH",
                preview_mutator=mutate)


def test_before_state_hash_mismatch():
    def mutate(preview_doc):
        preview_doc["before_state_canonical_sha256"] = sha("f")
    assert_fails("C3_APPLY_MANIFEST_BEFORE_STATE_HASH_MISMATCH",
                preview_mutator=mutate)


def test_before_state_canonical_text_disagrees_with_before_state_object():
    def mutate(preview_doc):
        divergent = json.dumps({**preview_doc["before_state"],
                                "database_name": "tampered"})
        preview_doc["before_state_canonical"] = divergent
        preview_doc["before_state_canonical_sha256"] = hashlib.sha256(
            divergent.encode("utf-8")).hexdigest()
    assert_fails("C3_APPLY_MANIFEST_BEFORE_STATE_CANONICAL_MISMATCH",
                preview_mutator=mutate)


def test_before_state_canonical_nonfinite_constant_is_rejected_in_namespace():
    # before_state_canonical is a string VALUE inside the already-decoded
    # preview document, so it never passed through the strict-JSON reader
    # on its own. A non-finite constant embedded there must still fail
    # closed with an in-namespace C3_APPLY_MANIFEST_* token (not leak a
    # bare ValueError, and not silently reparse as a Python float).
    def mutate(preview_doc):
        divergent = '{"NaN_probe": NaN}'
        preview_doc["before_state_canonical"] = divergent
        preview_doc["before_state_canonical_sha256"] = hashlib.sha256(
            divergent.encode("utf-8")).hexdigest()
    assert_fails("C3_APPLY_MANIFEST_PREVIEW_INVALID", preview_mutator=mutate)


def test_before_state_canonical_duplicate_keys_are_rejected():
    def mutate(preview_doc):
        divergent = '{"a": 1, "a": 2}'
        preview_doc["before_state_canonical"] = divergent
        preview_doc["before_state_canonical_sha256"] = hashlib.sha256(
            divergent.encode("utf-8")).hexdigest()
    assert_fails("C3_APPLY_MANIFEST_PREVIEW_INVALID", preview_mutator=mutate)


def test_candidate_self_hash_tamper_is_detected():
    doc = candidate_document()
    tampered = copy.deepcopy(doc)
    tampered["cases"][0]["identity"]["person_ids"] = [999, 1000]
    # canonical_content_sha256 left untouched: stale relative to the tampered body.
    candidate_bytes = json.dumps(tampered, ensure_ascii=False).encode("utf-8")
    preview_doc = preview_document(tampered, candidate_bytes, default_before_state())
    preview_bytes = preview_raw_bytes(preview_doc)
    assert_fails("C3_APPLY_MANIFEST_CANDIDATE_HASH_MISMATCH",
                candidate_bytes=candidate_bytes, preview_bytes=preview_bytes)


# ===========================================================================
# Output hashes
# ===========================================================================

def test_input_hashes_are_exact_raw_byte_shas():
    candidate_bytes, preview_bytes = build_pair()
    manifest = mod.finalize_manifest(candidate_bytes, preview_bytes)
    assert manifest["input_hashes"]["candidate_raw_sha256"] == hashlib.sha256(
        candidate_bytes).hexdigest()
    assert manifest["input_hashes"]["preview_raw_sha256"] == hashlib.sha256(
        preview_bytes).hexdigest()


def test_canonical_content_sha_is_independently_reproducible_and_sensitive():
    manifest = finalize()
    stated = manifest["canonical_content_sha256"]
    unhashed = copy.deepcopy(manifest)
    del unhashed["canonical_content_sha256"]
    independently_rendered = (json.dumps(
        unhashed, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        allow_nan=False) + "\n").encode("utf-8")
    assert hashlib.sha256(independently_rendered).hexdigest() == stated

    unhashed["cases"][0]["case_id"] = "case-mutated"
    mutated_rendered = (json.dumps(
        unhashed, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        allow_nan=False) + "\n").encode("utf-8")
    assert hashlib.sha256(mutated_rendered).hexdigest() != stated


def test_strict_json_rejects_duplicate_keys():
    malformed = b'{"schema_version":"x","schema_version":"y"}'
    candidate_bytes, preview_bytes = build_pair()
    with pytest.raises(SystemExit) as error:
        mod.finalize_manifest(malformed, preview_bytes)
    assert str(error.value) == "C3_APPLY_MANIFEST_CANDIDATE_INVALID"


# ===========================================================================
# CLI: exact --candidate/--preview/--output, atomic no-clobber publish
# ===========================================================================

def write_pair(tmp_path):
    candidate_bytes, preview_bytes = build_pair()
    candidate_path = tmp_path / "candidate.json"
    preview_path = tmp_path / "preview.json"
    candidate_path.write_bytes(candidate_bytes)
    preview_path.write_bytes(preview_bytes)
    return {
        "candidate": candidate_path, "preview": preview_path,
        "output": tmp_path / "manifest.json",
    }


def invoke(paths, env=None):
    return subprocess.run([
        "/usr/bin/python3", str(MODULE_PATH),
        "--candidate", str(paths["candidate"]),
        "--preview", str(paths["preview"]),
        "--output", str(paths["output"]),
    ], text=True, capture_output=True, check=False, env=env)


def test_cli_publishes_canonical_no_clobber_output_with_safe_stdout(tmp_path):
    paths = write_pair(tmp_path)
    completed = invoke(paths)
    assert completed.returncode == 0
    output_raw = paths["output"].read_bytes()
    rendered = json.loads(output_raw)
    assert output_raw == mod._canonical_bytes(rendered)
    assert completed.stderr == ""
    assert "schema=1939-v50-c3-apply-manifest-v1" in completed.stdout
    assert "cases=5" in completed.stdout
    assert "events=11" in completed.stdout
    assert paths["output"].name in completed.stdout
    assert hashlib.sha256(output_raw).hexdigest() in completed.stdout
    for forbidden in ("PROSE-FIXTURE", str(tmp_path)):
        assert forbidden not in (completed.stdout + completed.stderr)

    original = output_raw
    second = invoke(paths)
    assert second.returncode == 1
    assert second.stderr == "C3_APPLY_MANIFEST_OUTPUT_EXISTS\n"
    assert paths["output"].read_bytes() == original
    assert not list(tmp_path.glob(".c3-apply-*.tmp"))


def test_cli_argument_surface_is_exact(tmp_path):
    completed = subprocess.run(
        ["/usr/bin/python3", str(MODULE_PATH), "--unknown", "x"],
        text=True, capture_output=True, check=False)
    assert completed.returncode == 1
    assert completed.stderr == "C3_APPLY_MANIFEST_ARGUMENTS_INVALID\n"


def test_cli_missing_flag_is_rejected(tmp_path):
    paths = write_pair(tmp_path)
    completed = subprocess.run([
        "/usr/bin/python3", str(MODULE_PATH),
        "--candidate", str(paths["candidate"]),
        "--output", str(paths["output"]),
    ], text=True, capture_output=True, check=False)
    assert completed.returncode == 1
    assert completed.stderr == "C3_APPLY_MANIFEST_ARGUMENTS_INVALID\n"


def test_cli_rejects_symlinked_input(tmp_path):
    paths = write_pair(tmp_path)
    link = tmp_path / "candidate-link.json"
    link.symlink_to(paths["candidate"])
    paths["candidate"] = link
    completed = invoke(paths)
    assert completed.returncode == 1
    assert completed.stderr == "C3_APPLY_MANIFEST_CANDIDATE_INVALID\n"


def test_cli_rejects_business_rule_violation_end_to_end(tmp_path):
    def mutate(state):
        state["source_records"][0]["verbatim_sha256"] = sha("9")
    candidate_bytes, preview_bytes = build_pair(before_state=before_state_with(mutate))
    candidate_path = tmp_path / "candidate.json"
    preview_path = tmp_path / "preview.json"
    candidate_path.write_bytes(candidate_bytes)
    preview_path.write_bytes(preview_bytes)
    completed = invoke({
        "candidate": candidate_path, "preview": preview_path,
        "output": tmp_path / "manifest.json",
    })
    assert completed.returncode == 1
    assert completed.stderr == "C3_APPLY_MANIFEST_HASH_DRIFT\n"
    assert not (tmp_path / "manifest.json").exists()
