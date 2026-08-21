import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path

import pytest


SCRIPT_DIR = Path(__file__).resolve().parent
MODULE_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


mod = load_module("build_c3_review_1939_v50", MODULE_PATH)


ORDINARY_CASES = (
    ("R03", (1102, 1101)),
    ("R07", (1201, 1202)),
    ("R11", (1302, 1301)),
    ("R19", (1401, 1402)),
    ("R25", (1502, 1501)),
    ("R31", (1601, 1602)),
)


def candidate(person_id, rid):
    return {
        "person_id": person_id,
        "visning_navn": "SYNTHETIC_NAME_{}_{}".format(rid, person_id),
        "staged": False,
        "side": "500",
        "person_tekst": "MODEL_BLIND_SENTINEL_PERSON_{}_{}".format(
            rid, person_id),
    }


def record(rid, person_ids):
    return {
        "rid": rid,
        "new_record_key": "synthetic-{}".format(rid.lower()),
        "classification": "sammenlaegning" if rid != "R40" else "kobling",
        "verbatim_text": "MODEL_BLIND_SENTINEL_RECORD_{}".format(rid),
        "candidates": [candidate(person_id, rid) for person_id in person_ids],
    }


def selection_doc():
    cases = []
    for rid, person_ids in ORDINARY_CASES:
        cases.append({
            "case_kind": "ordinary",
            "candidate_person_ids": sorted(person_ids),
            "records": [record(rid, person_ids)],
        })
    cases.append({
        "case_kind": "1017_1021",
        "candidate_person_ids": [1017, 1021],
        "records": [record("R15", (1017, 1021)), record("R40", (1017,))],
    })
    person_ids = sorted({person_id for case in cases
                         for person_id in case["candidate_person_ids"]})
    return {
        "schema_version": "1939-v50-c3-selection-v1",
        "input_hashes": {
            "c0_candidates_sha256": "c" * 64,
            "c0_decisions_sha256": "d" * 64,
        },
        "case_count": 7,
        "record_count": 8,
        "decision_line_count": 15,
        "person_ids": person_ids,
        "cases": cases,
    }


def state_doc(selection=None):
    selection = selection if selection is not None else selection_doc()
    persons = [{"person_id": person_id, "staged": False, "privat": False}
               for person_id in selection["person_ids"]]
    narratives = [{
        "person_id": person_id,
        "narrative_id": 5000 + person_id,
        "old_sha256": "e" * 64,
        "privat": False,
        "side": "500",
        "source_record_id": None,
        "binding_status": None,
    } for person_id in selection["person_ids"]]
    return {
        "schema_version": "1939-v50-c3-current-state-v1",
        "database_name": "synthetic",
        "database_identity": "42",
        "generator": "synthetic:v1",
        "selection_sha256": "a" * 64,
        "persons": persons,
        "narratives": narratives,
        "identity_edges": [],
        "partner_conflicts": [],
    }


def editable_sequence(selection=None, state=None):
    selection = selection if selection is not None else selection_doc()
    state = state if state is not None else state_doc(selection)
    return [item for item in mod.review_sequence(selection, state)
            if item["type"] != "heading"]


def test_sequence_has_fifteen_decisions_and_locked_special_tail():
    editable = editable_sequence()
    assert len(editable) == 15
    assert [(item["decision_id"], item["default_token"])
            for item in editable[-3:]] == [
        ("identity:1017:1021", "SAMME 1021 1017"),
        ("record:R40", "TIL 1017"),
        ("record:R15", "TIL 1021"),
    ]


def test_ordinary_axes_are_independent_and_default_unresolved():
    editable = editable_sequence()
    assert [(item["decision_id"], item["default_token"])
            for item in editable[:4]] == [
        ("identity:R03", "UAFKLARET"),
        ("record:R03", "UAFKLARET"),
        ("identity:R07", "UAFKLARET"),
        ("record:R07", "UAFKLARET"),
    ]
    assert editable[0]["allowed_person_ids"] == [1101, 1102]
    assert editable[1]["allowed_person_ids"] == [1101, 1102]
    assert editable[-3]["allowed_person_ids"] == [1017, 1021]
    assert editable[-2]["allowed_person_ids"] == [1017, 1021]
    assert editable[-1]["allowed_person_ids"] == [1017, 1021]
    assert all(isinstance(item["tail"], str) and item["tail"]
               for item in editable)


def test_authoritative_sequence_does_not_return_narrative_prose():
    sequence = mod.review_sequence(selection_doc(), state_doc())
    serialized = json.dumps(sequence, ensure_ascii=False, sort_keys=True)
    assert "MODEL_BLIND_SENTINEL" not in serialized


def test_rendered_synthetic_fixture_has_locked_golden_sha256():
    rendered = mod.render_review(selection_doc(), state_doc(), "a" * 64,
                                 "b" * 64)
    assert rendered.endswith("\n")
    assert rendered.count("MODEL_BLIND_SENTINEL_RECORD_") == 8
    assert "selection_sha256=" + "a" * 64 in rendered
    assert "state_sha256=" + "b" * 64 in rendered
    digest = hashlib.sha256(rendered.encode("utf-8")).hexdigest()
    assert digest == "789453b38527c4e09b693e305c81d49d76a72c7411c4acaed96302b783f8b0f5"


def test_fixture_is_json_roundtrip_stable():
    selection = selection_doc()
    state = state_doc(selection)
    assert json.loads(json.dumps(selection)) == selection
    assert json.loads(json.dumps(state)) == state


@pytest.mark.parametrize("document, expected", [
    ("selection", "C3_REVIEW_SELECTION_INVALID"),
    ("state", "C3_REVIEW_STATE_INVALID"),
])
def test_wrong_schema_is_terminal(document, expected):
    selection = selection_doc()
    state = state_doc(selection)
    if document == "selection":
        selection["schema_version"] = "wrong"
    else:
        state["schema_version"] = "wrong"
    with pytest.raises(SystemExit, match="^{}$".format(expected)):
        mod.render_review(selection, state, "a" * 64, "b" * 64)


@pytest.mark.parametrize("field,value", [
    ("c0_candidates_sha256", "A" * 64),
    ("c0_decisions_sha256", "d" * 63),
])
def test_selection_input_hashes_are_lowercase_sha256(field, value):
    selection = selection_doc()
    selection["input_hashes"][field] = value
    with pytest.raises(SystemExit, match="^C3_REVIEW_SELECTION_HASH_INVALID$"):
        mod.render_review(selection, state_doc(selection), "a" * 64, "b" * 64)


@pytest.mark.parametrize("selection_hash,state_hash", [
    ("A" * 64, "b" * 64),
    ("a" * 63, "b" * 64),
    ("a" * 64, "not-a-sha"),
])
def test_render_input_hashes_are_lowercase_sha256(selection_hash, state_hash):
    with pytest.raises(SystemExit, match="^C3_REVIEW_HASH_INVALID$"):
        mod.render_review(selection_doc(), state_doc(), selection_hash, state_hash)


def test_state_must_bind_the_exact_selection_bytes():
    state = state_doc()
    state["selection_sha256"] = "f" * 64
    with pytest.raises(SystemExit,
                       match="^C3_REVIEW_SELECTION_HASH_MISMATCH$"):
        mod.render_review(selection_doc(), state, "a" * 64, "b" * 64)


@pytest.mark.parametrize("field,value", [
    ("case_count", 6),
    ("case_count", 7.0),
    ("record_count", 7),
    ("decision_line_count", 14),
])
def test_locked_counts_are_terminal_contracts(field, value):
    selection = selection_doc()
    selection[field] = value
    with pytest.raises(SystemExit, match="^C3_REVIEW_COUNT_INVALID$"):
        mod.render_review(selection, state_doc(selection), "a" * 64, "b" * 64)


@pytest.mark.parametrize("change", ["missing", "extra", "duplicate"])
def test_state_person_coverage_is_exact(change):
    selection = selection_doc()
    state = state_doc(selection)
    if change == "missing":
        state["persons"].pop()
    elif change == "extra":
        state["persons"].append({"person_id": 9999, "staged": False,
                                 "privat": False})
    else:
        state["persons"].append(dict(state["persons"][0]))
    with pytest.raises(SystemExit, match="^C3_REVIEW_PERSON_SET_INVALID$"):
        mod.render_review(selection, state, "a" * 64, "b" * 64)


@pytest.mark.parametrize("private_value", [True, None])
def test_private_or_unknown_private_person_is_terminal(private_value):
    selection = selection_doc()
    state = state_doc(selection)
    person_id = state["persons"][0]["person_id"]
    state["persons"][0]["privat"] = private_value
    with pytest.raises(SystemExit,
                       match="^C3_REVIEW_PERSON_PRIVATE:{}$".format(person_id)):
        mod.render_review(selection, state, "a" * 64, "b" * 64)


@pytest.mark.parametrize("change", ["missing", "extra", "duplicate"])
def test_state_narrative_coverage_is_exact_and_unique(change):
    selection = selection_doc()
    state = state_doc(selection)
    if change == "missing":
        state["narratives"].pop()
        expected = "C3_REVIEW_NARRATIVE_SET_INVALID"
    elif change == "extra":
        extra = dict(state["narratives"][0])
        extra.update(person_id=9999, narrative_id=99999)
        state["narratives"].append(extra)
        expected = "C3_REVIEW_NARRATIVE_SET_INVALID"
    else:
        duplicate = dict(state["narratives"][0])
        duplicate["narrative_id"] += 1
        state["narratives"].append(duplicate)
        expected = "C3_REVIEW_NARRATIVE_DUPLICATE:{}".format(
            duplicate["person_id"])
    with pytest.raises(SystemExit, match="^{}$".format(expected)):
        mod.render_review(selection, state, "a" * 64, "b" * 64)


@pytest.mark.parametrize("private_value", [True, None])
def test_private_or_unknown_private_narrative_is_terminal(private_value):
    selection = selection_doc()
    state = state_doc(selection)
    person_id = state["narratives"][0]["person_id"]
    state["narratives"][0]["privat"] = private_value
    with pytest.raises(
            SystemExit,
            match="^C3_REVIEW_NARRATIVE_PRIVATE:{}$".format(person_id)):
        mod.render_review(selection, state, "a" * 64, "b" * 64)


def test_only_exporter_binding_states_are_accepted():
    for status in ("draft", "published", "withdrawn"):
        selection = selection_doc()
        state = state_doc(selection)
        state["narratives"][0]["source_record_id"] = (
            "00000000-0000-0000-0000-000000000001")
        state["narratives"][0]["binding_status"] = status
        assert mod.render_review(selection, state, "a" * 64, "b" * 64)


@pytest.mark.parametrize("source_record_id,binding_status", [
    (None, "active"),
    (None, "draft"),
    ("00000000-0000-0000-0000-000000000001", None),
])
def test_unknown_or_inconsistent_binding_is_terminal(source_record_id,
                                                     binding_status):
    selection = selection_doc()
    state = state_doc(selection)
    person_id = state["narratives"][0]["person_id"]
    state["narratives"][0]["source_record_id"] = source_record_id
    state["narratives"][0]["binding_status"] = binding_status
    with pytest.raises(SystemExit,
                       match="^C3_REVIEW_BINDING_INVALID:{}$".format(person_id)):
        mod.render_review(selection, state, "a" * 64, "b" * 64)


@pytest.mark.parametrize("drift, expected", [
    ("case_kind", "C3_REVIEW_SPECIAL_INVALID"),
    ("candidate_ids", "C3_REVIEW_SPECIAL_INVALID"),
    ("record_order", "C3_REVIEW_SPECIAL_INVALID"),
    ("r15_candidates", "C3_REVIEW_R15_INVALID"),
    ("r40_candidates", "C3_REVIEW_R40_INVALID"),
])
def test_special_contract_drift_is_terminal(drift, expected):
    selection = selection_doc()
    special = selection["cases"][-1]
    if drift == "case_kind":
        special["case_kind"] = "ordinary"
    elif drift == "candidate_ids":
        special["candidate_person_ids"] = [1017]
    elif drift == "record_order":
        special["records"].reverse()
    elif drift == "r15_candidates":
        special["records"][0]["candidates"] = [candidate(1017, "R15")]
    else:
        special["records"][1]["candidates"] = [candidate(1021, "R40")]
    with pytest.raises(SystemExit, match="^{}$".format(expected)):
        mod.render_review(selection, state_doc(), "a" * 64, "b" * 64)


def test_renderer_includes_structural_graph_context():
    selection = selection_doc()
    state = state_doc(selection)
    state["identity_edges"] = [{"role": "samme_som", "subject_id": 1101,
                                "object_id": 9101}]
    state["partner_conflicts"] = [{"left_person_id": 1017,
                                   "right_person_id": 1021,
                                   "family_id": 77}]
    rendered = mod.render_review(selection, state, "a" * 64, "b" * 64)
    assert "IDENTITY_EDGE | " in rendered
    assert "PARTNER_CONFLICT | " in rendered


def write_cli_inputs(tmp_path):
    selection = selection_doc()
    selection_path = tmp_path / "selection.json"
    state_path = tmp_path / "state.json"
    selection_bytes = json.dumps(selection, ensure_ascii=False,
                                 separators=(",", ":")).encode("utf-8")
    selection_path.write_bytes(selection_bytes)
    state = state_doc(selection)
    state["selection_sha256"] = hashlib.sha256(selection_bytes).hexdigest()
    state_bytes = json.dumps(state, ensure_ascii=False, indent=1).encode("utf-8")
    state_path.write_bytes(state_bytes)
    return selection_path, state_path, selection_bytes, state_bytes


def run_cli(arguments):
    return subprocess.run(["/usr/bin/python3", str(MODULE_PATH)] + arguments,
                          check=False, capture_output=True, text=True)


def test_cli_hashes_exact_input_and_output_bytes_without_prose_leak(tmp_path):
    selection_path, state_path, selection_bytes, state_bytes = write_cli_inputs(
        tmp_path)
    output_path = tmp_path / "review.txt"
    completed = run_cli(["--selection", str(selection_path), "--state",
                         str(state_path), "--output", str(output_path)])

    output_bytes = output_path.read_bytes()
    output_sha = hashlib.sha256(output_bytes).hexdigest()
    assert completed.returncode == 0
    assert completed.stdout == (
        "sager=7 records=8 beslutningslinjer=15 review_sha256={}\n".format(
            output_sha))
    assert completed.stderr == ""
    assert "MODEL_BLIND_SENTINEL" not in completed.stdout + completed.stderr
    rendered = output_bytes.decode("utf-8")
    assert "selection_sha256=" + hashlib.sha256(selection_bytes).hexdigest() in rendered
    assert "state_sha256=" + hashlib.sha256(state_bytes).hexdigest() in rendered


@pytest.mark.parametrize("arguments", [[], ["--help"], ["--selection"]])
def test_cli_argument_failures_are_token_only(arguments):
    completed = run_cli(arguments)
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_REVIEW_ARGUMENTS_INVALID\n"


def test_cli_existing_output_is_terminal_and_preserved(tmp_path):
    selection_path, state_path, _, _ = write_cli_inputs(tmp_path)
    output_path = tmp_path / "review.txt"
    output_path.write_text("preexisting", encoding="utf-8")
    completed = run_cli(["--selection", str(selection_path), "--state",
                         str(state_path), "--output", str(output_path)])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_REVIEW_OUTPUT_EXISTS\n"
    assert output_path.read_text(encoding="utf-8") == "preexisting"


def test_cli_invalid_document_does_not_leak_input(tmp_path):
    selection_path = tmp_path / "selection.json"
    state_path = tmp_path / "state.json"
    output_path = tmp_path / "review.txt"
    selection_path.write_text("MODEL_BLIND_SENTINEL", encoding="utf-8")
    state_path.write_text("{}", encoding="utf-8")
    completed = run_cli(["--selection", str(selection_path), "--state",
                         str(state_path), "--output", str(output_path)])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_REVIEW_SELECTION_INVALID\n"
    assert "MODEL_BLIND_SENTINEL" not in completed.stdout + completed.stderr
    assert not output_path.exists()


def test_atomic_publication_rejects_race_and_cleans_temp(tmp_path, monkeypatch):
    output_path = tmp_path / "review.txt"
    created_temp_paths = []
    real_mkstemp = mod.tempfile.mkstemp
    real_link = mod.os.link

    def capture_mkstemp(*args, **kwargs):
        descriptor, path = real_mkstemp(*args, **kwargs)
        created_temp_paths.append(Path(path))
        return descriptor, path

    def race_link(source, destination):
        Path(destination).write_text("racer", encoding="utf-8")
        return real_link(source, destination)

    monkeypatch.setattr(mod.tempfile, "mkstemp", capture_mkstemp)
    monkeypatch.setattr(mod.os, "link", race_link)
    with pytest.raises(SystemExit, match="^C3_REVIEW_OUTPUT_EXISTS$"):
        mod.publish_output(output_path, "safe")
    assert output_path.read_text(encoding="utf-8") == "racer"
    assert all(not path.exists() for path in created_temp_paths)


def test_atomic_publication_write_error_leaves_no_output_or_temp(
        tmp_path, monkeypatch):
    output_path = tmp_path / "review.txt"
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
    with pytest.raises(SystemExit, match="^C3_REVIEW_OUTPUT_WRITE_FAILED$"):
        mod.publish_output(output_path, "safe")
    assert not output_path.exists()
    assert all(not path.exists() for path in created_temp_paths)
