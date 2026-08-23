import copy
import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path

import pytest


SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURE_PATH = SCRIPT_DIR / "c3_html_review_test_fixtures.py"
RENDERER_PATH = SCRIPT_DIR / "build_c3_html_review_1939_v50.py"
MODULE_PATH = SCRIPT_DIR / "convert_c3_apply_approvals_1939_v50.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


fixtures = load_module("c3_html_review_test_fixtures_for_apply_convert_test",
                       FIXTURE_PATH)
renderer = load_module(
    "build_c3_html_review_1939_v50_for_apply_convert_test", RENDERER_PATH)


def converter():
    return load_module("convert_c3_apply_approvals_1939_v50", MODULE_PATH)


def manifest_and_raw(mutate=None):
    document = fixtures.apply_manifest_document()
    if mutate is not None:
        mutate(document)
        document.pop("canonical_content_sha256", None)
        document["canonical_content_sha256"] = fixtures.finalize_builder._sha(
            fixtures.finalize_builder._canonical_bytes(document))
    return document, fixtures.apply_manifest_bytes(document)


def baseline_sheet(document):
    events = renderer._apply_assign_events(document)
    text_bundle_sha256 = renderer.apply_text_bundle_sha256(events)
    sheet_bytes, slots = renderer.apply_approval_sheet(
        text_bundle_sha256, events)
    return sheet_bytes.decode("utf-8"), slots, text_bundle_sha256


def approve(sheet_text, element_id):
    """Sæt præcis ét elements token til GODKENDT."""
    lines = sheet_text.splitlines(keepends=True)
    tail = "] approve:{}\n".format(element_id)
    for index, line in enumerate(lines):
        if line.startswith("[") and line.endswith(tail):
            lines[index] = "[GODKENDT" + tail
            return "".join(lines)
    raise AssertionError("element_id not found: " + element_id)


def parse_failure(text, document, manifest_raw, expected):
    with pytest.raises(SystemExit, match="^{}$".format(expected)) as error:
        converter().parse_approvals(text, document, manifest_raw)
    assert "Syntetisk" not in str(error.value)
    assert fixtures.APPLY_ATTACK_SENTINEL not in str(error.value)


def test_unchanged_sheet_roundtrips_to_all_unresolved():
    document, manifest_raw = manifest_and_raw()
    text, slots, text_bundle_sha256 = baseline_sheet(document)
    out = converter().parse_approvals(text, document, manifest_raw)
    assert set(out) == {
        "schema_version", "approvals_raw_sha256", "manifest_raw_sha256",
        "manifest_canonical_content_sha256", "text_bundle_sha256",
        "decisions", "counts"}
    assert out["schema_version"] == "1939-v50-c3-apply-approvals-decisions-v1"
    assert out["text_bundle_sha256"] == text_bundle_sha256
    assert out["manifest_raw_sha256"] == hashlib.sha256(
        manifest_raw).hexdigest()
    assert out["manifest_canonical_content_sha256"] == document[
        "canonical_content_sha256"]
    assert out["approvals_raw_sha256"] == hashlib.sha256(
        text.encode("utf-8")).hexdigest()
    assert out["counts"] == {"decisions": 5, "approved": 0, "unresolved": 5}
    assert [decision["status"] for decision in out["decisions"]] == (
        ["unresolved"] * 5)
    assert [decision["element_id"] for decision in out["decisions"]] == [
        slot["element_id"] for slot in slots]
    serialized = json.dumps(out, ensure_ascii=False)
    for forbidden in ("Syntetisk", "normalized_text", "verbatim_sha256"):
        assert forbidden not in serialized
    assert fixtures.APPLY_ATTACK_SENTINEL not in serialized


def test_fully_approved_sheet_marks_all_five_approved():
    document, manifest_raw = manifest_and_raw()
    text, slots, _ = baseline_sheet(document)
    approved_text = text.replace("[UAFKLARET]", "[GODKENDT]")
    out = converter().parse_approvals(approved_text, document, manifest_raw)
    assert out["counts"] == {"decisions": 5, "approved": 5, "unresolved": 0}
    assert [decision["status"] for decision in out["decisions"]] == (
        ["approved"] * 5)


def test_partial_approval_only_changes_the_approved_lines():
    document, manifest_raw = manifest_and_raw()
    text, slots, _ = baseline_sheet(document)
    edited = approve(text, slots[0]["element_id"])
    out = converter().parse_approvals(edited, document, manifest_raw)
    assert out["counts"] == {"decisions": 5, "approved": 1, "unresolved": 4}
    assert out["decisions"][0] == {
        "element_id": slots[0]["element_id"], "status": "approved"}
    assert all(decision["status"] == "unresolved"
               for decision in out["decisions"][1:])


def test_approval_sheet_is_portable_across_preview_derived_manifest_drift():
    """Fund B1: én menneskelig godkendelse skal gælde for både rehearsal og
    prod-manifester, så længe kun preview-/DB-afledte felter afviger."""
    document, manifest_raw = manifest_and_raw()
    text, _slots, _ = baseline_sheet(document)
    approved_text = text.replace("[UAFKLARET]", "[GODKENDT]")

    def drift_preview_only(doc):
        doc["database"]["database_name"] = "prod_db_name"
        doc["input_hashes"]["preview_raw_sha256"] = "f" * 64
        for case in doc["cases"]:
            for event in case["events"]:
                event["before_state"]["source_record"][
                    "verbatim_sha256"] = "9" * 64
                if event["action"] == "assign":
                    event["before_state"]["target_narrative"][
                        "narrative_id"] = 999999
                    event["before_state"]["target_narrative"][
                        "old_sha256"] = None

    drifted_document, drifted_raw = manifest_and_raw(mutate=drift_preview_only)
    out = converter().parse_approvals(
        approved_text, drifted_document, drifted_raw)
    assert out["counts"] == {"decisions": 5, "approved": 5, "unresolved": 0}
    assert out["text_bundle_sha256"] == converter().renderer.apply_text_bundle_sha256(
        converter().renderer._apply_assign_events(document))
    assert out["manifest_raw_sha256"] == hashlib.sha256(
        drifted_raw).hexdigest()


def test_candidate_derived_manifest_drift_invalidates_the_sheet():
    """Rette hjørne af B1: teksten SKAL binde, kun before_state må variere."""
    document, manifest_raw = manifest_and_raw()
    text, _slots, _ = baseline_sheet(document)
    approved_text = text.replace("[UAFKLARET]", "[GODKENDT]")

    def drift_text(doc):
        doc["cases"][0]["events"][0]["after_state"]["normalized_text"] += (
            " ÆNDRET")

    drifted_document, drifted_raw = manifest_and_raw(mutate=drift_text)
    parse_failure(
        approved_text, drifted_document, drifted_raw,
        "C3_APPLY_APPROVALS_HASH_MISMATCH")


def test_stale_schema_line_is_terminal():
    document, manifest_raw = manifest_and_raw()
    text, _slots, _ = baseline_sheet(document)
    tampered = text.replace(
        "# schema=1939-v50-c3-apply-approvals-v1",
        "# schema=1939-v50-c3-apply-approvals-v2", 1)
    parse_failure(
        tampered, document, manifest_raw, "C3_APPLY_APPROVALS_SCHEMA_MISMATCH")


def test_stale_bundle_hash_line_is_terminal():
    document, manifest_raw = manifest_and_raw()
    text, _slots, text_bundle_sha256 = baseline_sheet(document)
    tampered = text.replace(text_bundle_sha256, "0" * 64, 1)
    parse_failure(
        tampered, document, manifest_raw, "C3_APPLY_APPROVALS_HASH_MISMATCH")


def test_missing_decision_line_is_terminal():
    document, manifest_raw = manifest_and_raw()
    text, _slots, _ = baseline_sheet(document)
    lines = text.splitlines(keepends=True)
    del lines[2]
    parse_failure(
        "".join(lines), document, manifest_raw,
        "C3_APPLY_APPROVALS_LINE_MISSING")


def test_extra_line_is_terminal():
    document, manifest_raw = manifest_and_raw()
    text, _slots, _ = baseline_sheet(document)
    parse_failure(
        text + "UNEXPECTED\n", document, manifest_raw,
        "C3_APPLY_APPROVALS_LINE_UNEXPECTED")


def test_duplicate_decision_line_is_terminal():
    document, manifest_raw = manifest_and_raw()
    text, _slots, _ = baseline_sheet(document)
    lines = text.splitlines(keepends=True)
    lines.insert(3, lines[2])
    del lines[-1]
    parse_failure(
        "".join(lines), document, manifest_raw,
        "C3_APPLY_APPROVALS_DECISION_DUPLICATE")


def test_swapped_decision_lines_are_terminal():
    document, manifest_raw = manifest_and_raw()
    text, _slots, _ = baseline_sheet(document)
    lines = text.splitlines(keepends=True)
    lines[2], lines[3] = lines[3], lines[2]
    parse_failure(
        "".join(lines), document, manifest_raw,
        "C3_APPLY_APPROVALS_LINE_TAMPERED")


def test_tail_tampering_is_terminal():
    document, manifest_raw = manifest_and_raw()
    text, slots, _ = baseline_sheet(document)
    tampered = text.replace(
        "approve:" + slots[0]["element_id"],
        "approve:" + slots[0]["element_id"] + "-x", 1)
    parse_failure(
        tampered, document, manifest_raw, "C3_APPLY_APPROVALS_LINE_TAMPERED")


@pytest.mark.parametrize("token", ["GODKENDT ", " GODKENDT", "godkendt",
                                   "UAFKLARET ", "MAYBE"])
def test_unknown_tokens_are_terminal(token):
    document, manifest_raw = manifest_and_raw()
    text, slots, _ = baseline_sheet(document)
    lines = text.splitlines(keepends=True)
    tail = "] approve:{}\n".format(slots[0]["element_id"])
    lines[2] = "[{}{}".format(token, tail)
    parse_failure(
        "".join(lines), document, manifest_raw,
        "C3_APPLY_APPROVALS_TOKEN_INVALID")


def test_line_not_starting_with_bracket_is_token_invalid():
    document, manifest_raw = manifest_and_raw()
    text, slots, _ = baseline_sheet(document)
    lines = text.splitlines(keepends=True)
    tail = "] approve:{}\n".format(slots[0]["element_id"])
    lines[2] = "GODKENDT" + tail
    parse_failure(
        "".join(lines), document, manifest_raw,
        "C3_APPLY_APPROVALS_TOKEN_INVALID")


@pytest.mark.parametrize("mutate,expected", [
    (lambda doc: doc.pop("database"), "C3_APPLY_APPROVALS_MANIFEST_INVALID"),
    (lambda doc: doc["counts"].__setitem__("assign_events", 4),
     "C3_APPLY_APPROVALS_MANIFEST_INVALID"),
])
def test_structural_manifest_drift_is_remapped_to_own_namespace(
        mutate, expected):
    # `document` and `manifest_raw` must stay self-consistent (the mutation
    # applied to both) so this test exercises the intended structural gate,
    # not the manifest_doc/manifest_raw binding guard covered separately
    # below by test_manifest_doc_not_derived_from_manifest_raw_is_terminal.
    document, _pristine_raw = manifest_and_raw()
    mutate(document)
    manifest_raw = fixtures.apply_manifest_bytes(document)
    text, _slots, _ = baseline_sheet(fixtures.apply_manifest_document())
    parse_failure(text, document, manifest_raw, expected)


def test_manifest_self_hash_tamper_is_remapped():
    document, _pristine_raw = manifest_and_raw()
    document["canonical_content_sha256"] = "0" * 64
    manifest_raw = fixtures.apply_manifest_bytes(document)
    text, _slots, _ = baseline_sheet(fixtures.apply_manifest_document())
    parse_failure(
        text, document, manifest_raw,
        "C3_APPLY_APPROVALS_MANIFEST_HASH_MISMATCH")


def test_manifest_doc_not_derived_from_manifest_raw_is_terminal():
    """A library caller (Task 5/6, per this codebase's import-sibling-
    function idiom) could pass a decoded document that did not actually
    come from the raw bytes it also passes. Since the converter's output
    stamps `manifest_raw_sha256` for a later authorization gate to rely on,
    the two MUST be proven consistent before anything is emitted."""
    document, _manifest_raw = manifest_and_raw()
    other_document, other_manifest_raw = manifest_and_raw(
        mutate=lambda doc: doc["cases"][0].__setitem__(
            "case_id", "case-1-other"))
    text, _slots, _ = baseline_sheet(document)
    parse_failure(
        text, document, other_manifest_raw,
        "C3_APPLY_APPROVALS_MANIFEST_BINDING_MISMATCH")


@pytest.mark.parametrize("which,bad", [
    ("text", []),
    ("document", []),
    ("document", {"schema_version": []}),
    ("manifest_raw", "not-bytes"),
])
def test_wrong_python_types_never_raise_raw_exceptions(which, bad):
    document, manifest_raw = manifest_and_raw()
    text, _slots, _ = baseline_sheet(document)
    values = {"text": text, "document": document, "manifest_raw": manifest_raw}
    values[which] = bad
    with pytest.raises(SystemExit, match="^C3_APPLY_APPROVALS_[A-Z0-9_]+$"):
        converter().parse_approvals(
            values["text"], values["document"], values["manifest_raw"])


def write_cli_inputs(tmp_path):
    document, manifest_raw = manifest_and_raw()
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_bytes(manifest_raw)
    text, _slots, _ = baseline_sheet(document)
    approved_text = text.replace("[UAFKLARET]", "[GODKENDT]", 1)
    approvals_path = tmp_path / "approvals.txt"
    approvals_path.write_text(approved_text, encoding="utf-8")
    return manifest_path, manifest_raw, approvals_path, approved_text


def run_cli(arguments):
    return subprocess.run(
        ["/usr/bin/python3", str(MODULE_PATH)] + arguments,
        check=False, capture_output=True, text=True)


def test_cli_hashes_raw_bytes_and_writes_text_free_json_atomically(tmp_path):
    manifest_path, manifest_raw, approvals_path, approved_text = (
        write_cli_inputs(tmp_path))
    output_path = tmp_path / "decisions.json"
    completed = run_cli([
        "--approvals", str(approvals_path), "--manifest", str(manifest_path),
        "--output", str(output_path),
    ])
    assert completed.returncode == 0
    assert completed.stdout == "beslutninger=5 godkendt=1 uafklarede=4\n"
    assert completed.stderr == ""
    out = json.loads(output_path.read_text(encoding="utf-8"))
    assert out["counts"] == {"decisions": 5, "approved": 1, "unresolved": 4}
    assert out["manifest_raw_sha256"] == hashlib.sha256(
        manifest_raw).hexdigest()
    assert "Syntetisk" not in json.dumps(out, ensure_ascii=False)
    assert fixtures.APPLY_ATTACK_SENTINEL not in json.dumps(
        out, ensure_ascii=False)
    assert list(tmp_path.glob(".decisions.json.*.tmp")) == []


@pytest.mark.parametrize("arguments", [
    [], ["--help"], ["--approvals"], ["--approvals", "x", "--approvals", "y"],
])
def test_cli_argument_errors_are_token_only(arguments):
    completed = run_cli(arguments)
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_APPLY_APPROVALS_ARGUMENTS_INVALID\n"


def test_cli_rejects_existing_output_and_preserves_it(tmp_path):
    manifest_path, _, approvals_path, _ = write_cli_inputs(tmp_path)
    output_path = tmp_path / "decisions.json"
    output_path.write_text("preexisting", encoding="utf-8")
    completed = run_cli([
        "--approvals", str(approvals_path), "--manifest", str(manifest_path),
        "--output", str(output_path),
    ])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_APPLY_APPROVALS_OUTPUT_EXISTS\n"
    assert output_path.read_text(encoding="utf-8") == "preexisting"


def test_cli_invalid_utf8_approvals_is_token_only(tmp_path):
    manifest_path, _, approvals_path, _ = write_cli_inputs(tmp_path)
    approvals_path.write_bytes(b"\xffMODEL_BLIND_SENTINEL")
    output_path = tmp_path / "decisions.json"
    completed = run_cli([
        "--approvals", str(approvals_path), "--manifest", str(manifest_path),
        "--output", str(output_path),
    ])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_APPLY_APPROVALS_TEXT_INVALID\n"
    assert "MODEL_BLIND_SENTINEL" not in completed.stdout + completed.stderr
    assert not output_path.exists()


def test_cli_wrong_top_level_manifest_json_type_is_token_only(tmp_path):
    manifest_path, _, approvals_path, _ = write_cli_inputs(tmp_path)
    manifest_path.write_text("[]", encoding="utf-8")
    output_path = tmp_path / "decisions.json"
    completed = run_cli([
        "--approvals", str(approvals_path), "--manifest", str(manifest_path),
        "--output", str(output_path),
    ])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_APPLY_APPROVALS_MANIFEST_INVALID\n"
    assert not output_path.exists()


def test_atomic_publication_rejects_race_and_cleans_temp(tmp_path, monkeypatch):
    module = converter()
    output_path = tmp_path / "decisions.json"
    created_temp_paths = []
    real_mkstemp = module.tempfile.mkstemp
    real_link = module.os.link

    def capture_mkstemp(*args, **kwargs):
        descriptor, path = real_mkstemp(*args, **kwargs)
        created_temp_paths.append(Path(path))
        return descriptor, path

    def race_link(source, destination):
        Path(destination).write_text("racer", encoding="utf-8")
        return real_link(source, destination)

    monkeypatch.setattr(module.tempfile, "mkstemp", capture_mkstemp)
    monkeypatch.setattr(module.os, "link", race_link)
    with pytest.raises(SystemExit, match="^C3_APPLY_APPROVALS_OUTPUT_EXISTS$"):
        module.publish_output(output_path, "safe")
    assert output_path.read_text(encoding="utf-8") == "racer"
    assert all(not path.exists() for path in created_temp_paths)


def test_atomic_write_error_leaves_no_output_or_temp(tmp_path, monkeypatch):
    module = converter()
    output_path = tmp_path / "decisions.json"
    created_temp_paths = []
    real_mkstemp = module.tempfile.mkstemp

    def capture_mkstemp(*args, **kwargs):
        descriptor, path = real_mkstemp(*args, **kwargs)
        created_temp_paths.append(Path(path))
        return descriptor, path

    def fail_fdopen(descriptor, *args, **kwargs):
        os.close(descriptor)
        raise OSError("MODEL_BLIND_SENTINEL")

    monkeypatch.setattr(module.tempfile, "mkstemp", capture_mkstemp)
    monkeypatch.setattr(module.os, "fdopen", fail_fdopen)
    with pytest.raises(SystemExit,
                       match="^C3_APPLY_APPROVALS_OUTPUT_WRITE_FAILED$"):
        module.publish_output(output_path, "safe")
    assert not output_path.exists()
    assert all(not path.exists() for path in created_temp_paths)
