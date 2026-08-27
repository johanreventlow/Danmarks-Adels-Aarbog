import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


SCRIPT_DIR = Path(__file__).resolve().parent
MODULE_PATH = SCRIPT_DIR / "build_c3_selection_1939_v50.py"
C0_PATH = SCRIPT_DIR / "convert_c0_linkage_decisions_1939_v50.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


mod = load_module("build_c3_selection_1939_v50", MODULE_PATH)
c0 = load_module("convert_c0_linkage_decisions_1939_v50", C0_PATH)


def fixture_documents():
    c3_numbers = {3, 7, 15, 19, 25, 31, 37}
    records = []
    decisions = []
    for number in range(1, 42):
        key = "record-{:02d}".format(number)
        classification = ("sammenlaegning" if number in c3_numbers
                          else "kobling" if number == 40 else "aegte_ny")
        candidates = []
        if number == 15:
            candidates = [
                {"person_id": 1017, "visning_navn": "A"},
                {"person_id": 1021, "visning_navn": "B"},
            ]
        elif number == 40:
            candidates = [{"person_id": 1017, "visning_navn": "A"}]
        records.append({
            "new_record_key": key,
            "classification": classification,
            "candidates": candidates,
            "fixture_marker": "complete-record-{}".format(number),
        })
        decisions.append({
            "new_record_key": key,
            "token": "[C3]" if number in c3_numbers
            else "[KOBL]" if number == 40 else "[NY]",
            "person_id": 1017 if number == 40 else None,
            "classification": classification,
        })
    return ({"schema_version": "1.0", "records": records},
            {"schema_version": "1.0", "decisions": decisions})


def selected_case(result, rid):
    return next(case for case in result["cases"]
                if any(record["rid"] == rid for record in case["records"]))


def test_builds_exact_seven_plus_companion_and_binds_both_inputs():
    candidates, decisions = fixture_documents()
    result = mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)
    assert result["input_hashes"] == {
        "c0_candidates_sha256": "a" * 64,
        "c0_decisions_sha256": "b" * 64,
    }
    assert (result["case_count"], result["record_count"],
            result["decision_line_count"]) == (7, 8, 15)
    assert result["schema_version"] == "1939-v50-c3-selection-v1"
    assert [record["rid"] for record in result["cases"][-1]["records"]] == [
        "R15", "R40"]
    assert selected_case(result, "R15")["records"][0]["fixture_marker"] == (
        "complete-record-15")


def test_missing_c3_is_terminal():
    candidates, decisions = fixture_documents()
    next(row for row in decisions["decisions"]
         if row["token"] == "[C3]")["token"] = "[NY]"
    with pytest.raises(SystemExit, match="C3_SELECTION_COUNT_INVALID"):
        mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)


def test_extra_c3_is_terminal():
    candidates, decisions = fixture_documents()
    next(row for row in decisions["decisions"]
         if row["new_record_key"] == "record-01")["token"] = "[C3]"
    with pytest.raises(SystemExit, match="C3_SELECTION_COUNT_INVALID"):
        mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)


def test_duplicate_key_is_terminal():
    candidates, decisions = fixture_documents()
    decisions["decisions"].append(dict(decisions["decisions"][0]))
    with pytest.raises(SystemExit, match="C3_SELECTION_KEY_DUPLICATE"):
        mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)


def test_selected_classification_drift_is_terminal():
    candidates, decisions = fixture_documents()
    next(row for row in candidates["records"]
         if row["new_record_key"] == "record-03")["classification"] = "kobling"
    with pytest.raises(SystemExit, match="C3_SELECTION_CLASS_INVALID:record-03"):
        mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)


def test_r15_candidate_drift_is_terminal():
    candidates, decisions = fixture_documents()
    next(row for row in candidates["records"]
         if row["new_record_key"] == "record-15")["candidates"] = [
             {"person_id": 1017, "visning_navn": "A"}]
    with pytest.raises(SystemExit, match="C3_SELECTION_R15_INVALID"):
        mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)


@pytest.mark.parametrize("field, value", [("token", "[NY]"),
                                           ("person_id", 1021)])
def test_r40_decision_drift_is_terminal(field, value):
    candidates, decisions = fixture_documents()
    rids = c0.assign_rids(candidates["records"])
    r40_key = next(key for key, rid in rids.items() if rid == "R40")
    next(row for row in decisions["decisions"]
         if row["new_record_key"] == r40_key)[field] = value
    with pytest.raises(SystemExit, match="C3_SELECTION_R40_INVALID"):
        mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)


@pytest.mark.parametrize("candidates_hash, decisions_hash", [
    ("A" * 64, "b" * 64), ("a" * 63, "b" * 64),
    ("a" * 64, "not-a-sha"),
])
def test_malformed_hash_is_terminal(candidates_hash, decisions_hash):
    candidates, decisions = fixture_documents()
    with pytest.raises(SystemExit, match="C3_SELECTION_HASH_INVALID"):
        mod.build_selection(candidates, decisions, candidates_hash, decisions_hash)


def test_reversed_input_arrays_produce_identical_selection():
    candidates, decisions = fixture_documents()
    forward = mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)
    candidates["records"].reverse()
    decisions["decisions"].reverse()
    backward = mod.build_selection(candidates, decisions, "a" * 64, "b" * 64)
    assert backward == forward


def test_cli_hashes_raw_input_bytes_and_does_not_emit_fixture_text(tmp_path):
    candidates, decisions = fixture_documents()
    candidates_path = tmp_path / "candidates.json"
    decisions_path = tmp_path / "decisions.json"
    output_path = tmp_path / "selection.json"
    candidates_bytes = json.dumps(candidates, indent=1).encode("utf-8")
    decisions_bytes = json.dumps(decisions, separators=(",", ":")).encode("utf-8")
    candidates_path.write_bytes(candidates_bytes)
    decisions_path.write_bytes(decisions_bytes)

    completed = subprocess.run(
        [sys.executable, str(MODULE_PATH), "--candidates", str(candidates_path),
         "--c0-decisions", str(decisions_path), "--output", str(output_path)],
        check=False, capture_output=True, text=True)

    assert completed.returncode == 0
    assert completed.stdout == "sager=7 records=8 beslutningslinjer=15\n"
    assert "complete-record" not in completed.stdout + completed.stderr
    result = json.loads(output_path.read_text(encoding="utf-8"))
    assert result["input_hashes"] == {
        "c0_candidates_sha256": hashlib.sha256(candidates_bytes).hexdigest(),
        "c0_decisions_sha256": hashlib.sha256(decisions_bytes).hexdigest(),
    }


@pytest.mark.parametrize("arguments", [[], ["--help"], ["--candidates"]])
def test_cli_argument_failures_are_token_only(arguments):
    completed = subprocess.run(
        [sys.executable, str(MODULE_PATH)] + arguments,
        check=False, capture_output=True, text=True)

    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_SELECTION_ARGUMENTS_INVALID\n"


def test_cli_existing_output_is_terminal_and_preserved(tmp_path):
    candidates, decisions = fixture_documents()
    candidates_path = tmp_path / "candidates.json"
    decisions_path = tmp_path / "decisions.json"
    output_path = tmp_path / "selection.json"
    candidates_path.write_text(json.dumps(candidates), encoding="utf-8")
    decisions_path.write_text(json.dumps(decisions), encoding="utf-8")
    output_path.write_text("preexisting", encoding="utf-8")

    completed = subprocess.run(
        [sys.executable, str(MODULE_PATH), "--candidates", str(candidates_path),
         "--c0-decisions", str(decisions_path), "--output", str(output_path)],
        check=False, capture_output=True, text=True)

    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_SELECTION_OUTPUT_EXISTS\n"
    assert output_path.read_text(encoding="utf-8") == "preexisting"


def test_atomic_publication_rejects_racing_destination_and_cleans_temp(
        tmp_path, monkeypatch):
    output_path = tmp_path / "selection.json"
    real_link = mod.os.link
    created_temp_paths = []
    real_mkstemp = mod.tempfile.mkstemp

    def capture_mkstemp(*args, **kwargs):
        descriptor, path = real_mkstemp(*args, **kwargs)
        created_temp_paths.append(Path(path))
        return descriptor, path

    def race_link(source, destination):
        Path(destination).write_text("racer", encoding="utf-8")
        return real_link(source, destination)

    monkeypatch.setattr(mod.tempfile, "mkstemp", capture_mkstemp)
    monkeypatch.setattr(mod.os, "link", race_link)

    with pytest.raises(SystemExit, match="C3_SELECTION_OUTPUT_EXISTS"):
        mod.publish_output(output_path, "complete")

    assert output_path.read_text(encoding="utf-8") == "racer"
    assert all(not path.exists() for path in created_temp_paths)


def test_atomic_publication_write_error_leaves_no_destination_or_temp(
        tmp_path, monkeypatch):
    output_path = tmp_path / "selection.json"
    created_temp_paths = []
    real_mkstemp = mod.tempfile.mkstemp

    def capture_mkstemp(*args, **kwargs):
        descriptor, path = real_mkstemp(*args, **kwargs)
        created_temp_paths.append(Path(path))
        return descriptor, path

    def fail_fdopen(descriptor, *args, **kwargs):
        os.close(descriptor)
        raise OSError("simulated write failure")

    monkeypatch.setattr(mod.tempfile, "mkstemp", capture_mkstemp)
    monkeypatch.setattr(mod.os, "fdopen", fail_fdopen)

    with pytest.raises(SystemExit, match="C3_SELECTION_OUTPUT_WRITE_FAILED"):
        mod.publish_output(output_path, "complete")

    assert not output_path.exists()
    assert all(not path.exists() for path in created_temp_paths)
