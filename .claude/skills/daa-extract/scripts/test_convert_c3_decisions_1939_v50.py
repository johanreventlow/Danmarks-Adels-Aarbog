import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path

import pytest


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"
MODULE_PATH = SCRIPT_DIR / "convert_c3_decisions_1939_v50.py"
NO_WRITER_PATTERN = r"\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b|red_[a-z_]+\s*\("
C3_SCRIPT_PATHS = [
    SCRIPT_DIR / "build_c3_selection_1939_v50.py",
    SCRIPT_DIR / "export_c3_current_state_1939_v50.R",
    SCRIPT_DIR / "export_c3_current_state_1939_v50_helpers.R",
    SCRIPT_DIR / "build_c3_review_1939_v50.py",
    MODULE_PATH,
]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


build = load_module("build_c3_review_for_converter_test", BUILD_PATH)


def test_c3_scripts_pass_mechanical_no_writer_audit():
    completed = subprocess.run(
        ["rg", "-n", NO_WRITER_PATTERN, *map(str, C3_SCRIPT_PATHS)],
        text=True, capture_output=True, check=False)
    assert completed.returncode == 1
    assert completed.stdout == ""
    assert completed.stderr == ""


def converter():
    return load_module("convert_c3_decisions_1939_v50", MODULE_PATH)


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


def docs():
    cases = [{
        "case_kind": "ordinary",
        "candidate_person_ids": sorted(person_ids),
        "records": [record(rid, person_ids)],
    } for rid, person_ids in ORDINARY_CASES]
    cases.append({
        "case_kind": "1017_1021",
        "candidate_person_ids": [1017, 1021],
        "records": [record("R15", (1017, 1021)), record("R40", (1017,))],
    })
    person_ids = sorted({person_id for case in cases
                         for person_id in case["candidate_person_ids"]})
    selection = {
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
    state = {
        "schema_version": "1939-v50-c3-current-state-v1",
        "database_name": "synthetic",
        "database_identity": "42",
        "generator": "synthetic:v1",
        "selection_sha256": "a" * 64,
        "persons": [{"person_id": person_id, "staged": False,
                     "privat": False} for person_id in person_ids],
        "narratives": [{
            "person_id": person_id,
            "narrative_id": 5000 + person_id,
            "old_sha256": "e" * 64,
            "privat": False,
            "side": "500",
            "source_record_id": None,
            "binding_status": None,
        } for person_id in person_ids],
        "identity_edges": [],
        "partner_conflicts": [],
    }
    return selection, state


def rendered(selection=None, state=None):
    if selection is None or state is None:
        selection, state = docs()
    return build.render_review(selection, state, "a" * 64, "b" * 64)


def hashes(text):
    return {
        "c0_candidates_sha256": "c" * 64,
        "c0_decisions_sha256": "d" * 64,
        "selection_sha256": "a" * 64,
        "state_sha256": "b" * 64,
        "review_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
    }


def replace_token(text, decision_id, replacement, selection=None, state=None):
    if selection is None or state is None:
        selection, state = docs()
    item = next(row for row in build.review_sequence(selection, state)
                if row.get("decision_id") == decision_id)
    old = "[{}] {}".format(item["default_token"], item["tail"])
    new = "[{}] {}".format(replacement, item["tail"])
    assert text.count(old) == 1
    return text.replace(old, new, 1)


def test_unchanged_sheet_roundtrips_without_prose():
    selection, state = docs()
    text = rendered(selection, state)
    out = converter().parse_review(text, selection, state, hashes(text))
    assert set(out) == {
        "schema_version", "input_hashes", "counts", "cases",
        "database_identity",
    }
    assert out["schema_version"] == "1939-v50-c3-decisions-v1"
    assert out["counts"] == {
        "cases": 7,
        "records": 8,
        "decision_lines": 15,
        "unresolved": 13,
    }
    assert out["input_hashes"] == hashes(text)
    assert out["database_identity"] == {
        "database_name": "synthetic",
        "database_identity": "42",
    }
    assert out["cases"][-1]["identity"] == {"action": "unresolved"}
    assert [row["person_id"]
            for row in out["cases"][-1]["record_decisions"]] == [1017, 1021]
    serialized = json.dumps(out, ensure_ascii=False, sort_keys=True)
    for forbidden in ("MODEL_BLIND_SENTINEL", "verbatim_text", "tail",
                      "heading", "visning_navn", "person_tekst"):
        assert forbidden not in serialized


def test_generated_baseline_is_fail_closed_when_special_alias_is_occupied():
    selection, state = docs()
    state["identity_edges"] = [{
        "role": "samme_som",
        "subject_id": 1021,
        "object_id": 9999,
    }]
    text = rendered(selection, state)

    out = converter().parse_review(text, selection, state, hashes(text))

    assert out["counts"]["unresolved"] == 13
    assert out["cases"][-1]["identity"] == {"action": "unresolved"}
    assert [row["person_id"]
            for row in out["cases"][-1]["record_decisions"]] == [1017, 1021]


def test_identity_change_does_not_change_record_axis():
    selection, state = docs()
    original_text = rendered(selection, state)
    original = converter().parse_review(
        original_text, selection, state, hashes(original_text))
    changed_text = replace_token(
        original_text, "identity:R03", "FORSKELLIGE", selection, state)
    changed = converter().parse_review(
        changed_text, selection, state, hashes(changed_text))
    assert changed["cases"][0]["identity"] == {"action": "different"}
    assert (changed["cases"][0]["record_decisions"]
            == original["cases"][0]["record_decisions"])


def test_record_change_does_not_change_identity_axis():
    selection, state = docs()
    original_text = rendered(selection, state)
    original = converter().parse_review(
        original_text, selection, state, hashes(original_text))
    changed_text = replace_token(
        original_text, "record:R03", "TIL 1101", selection, state)
    changed = converter().parse_review(
        changed_text, selection, state, hashes(changed_text))
    assert changed["cases"][0]["record_decisions"] == [{
        "rid": "R03", "action": "assign", "person_id": 1101,
    }]
    assert changed["cases"][0]["identity"] == original["cases"][0]["identity"]


@pytest.mark.parametrize("token,expected", [
    ("FORSKELLIGE", {"action": "different"}),
    ("UAFKLARET", {"action": "unresolved"}),
    ("SAMME 1101 1102", {
        "action": "same", "alias_person_id": 1101,
        "canonical_person_id": 1102,
    }),
])
def test_every_legal_identity_token_is_explicit(token, expected):
    selection, state = docs()
    text = replace_token(
        rendered(selection, state), "identity:R03", token, selection, state)
    out = converter().parse_review(text, selection, state, hashes(text))
    assert out["cases"][0]["identity"] == expected


@pytest.mark.parametrize("token,expected", [
    ("TIL 1101", {"action": "assign", "person_id": 1101}),
    ("REVISION split_into", {
        "action": "revision", "relation_kind": "split_into"}),
    ("REVISION merged_from", {
        "action": "revision", "relation_kind": "merged_from"}),
    ("REVISION replaced_by", {
        "action": "revision", "relation_kind": "replaced_by"}),
    ("INGEN_PUBLIKATION", {"action": "no_publication"}),
    ("UAFKLARET", {"action": "unresolved"}),
])
def test_every_legal_record_token_is_explicit(token, expected):
    selection, state = docs()
    text = replace_token(
        rendered(selection, state), "record:R03", token, selection, state)
    out = converter().parse_review(text, selection, state, hashes(text))
    assert out["cases"][0]["record_decisions"] == [dict(expected, rid="R03")]


def decision_line_index(text, decision_id, selection=None, state=None):
    if selection is None or state is None:
        selection, state = docs()
    item = next(row for row in build.review_sequence(selection, state)
                if row.get("decision_id") == decision_id)
    lines = text.splitlines(keepends=True)
    return next(index for index, line in enumerate(lines)
                if line.endswith("] {}\n".format(item["tail"])))


def parse_failure(text, selection, state, expected):
    with pytest.raises(SystemExit, match="^{}$".format(expected)) as error:
        converter().parse_review(text, selection, state, hashes(text))
    assert "MODEL_BLIND_SENTINEL" not in str(error.value)


def test_missing_decision_line_is_terminal():
    selection, state = docs()
    lines = rendered(selection, state).splitlines(keepends=True)
    del lines[decision_line_index("".join(lines), "identity:R03",
                                  selection, state)]
    text = "".join(lines)
    parse_failure(text, selection, state, "C3_REVIEW_LINE_MISSING")


def test_extra_nondecision_line_is_terminal():
    selection, state = docs()
    text = rendered(selection, state) + "UNEXPECTED\n"
    parse_failure(text, selection, state, "C3_REVIEW_LINE_UNEXPECTED")


def test_duplicate_decision_line_is_classified_before_extra_line():
    selection, state = docs()
    lines = rendered(selection, state).splitlines(keepends=True)
    index = decision_line_index("".join(lines), "identity:R03", selection, state)
    lines.insert(index + 1, lines[index])
    text = "".join(lines)
    parse_failure(text, selection, state, "C3_REVIEW_DECISION_DUPLICATE")


def test_swapped_decision_lines_are_terminal():
    selection, state = docs()
    lines = rendered(selection, state).splitlines(keepends=True)
    first = decision_line_index("".join(lines), "identity:R03", selection, state)
    second = decision_line_index("".join(lines), "identity:R07", selection, state)
    lines[first], lines[second] = lines[second], lines[first]
    text = "".join(lines)
    parse_failure(text, selection, state, "C3_REVIEW_LINE_TAMPERED")


@pytest.mark.parametrize("mutation", ["heading", "tail", "whitespace", "rid"])
def test_all_non_token_bytes_are_locked(mutation):
    selection, state = docs()
    text = rendered(selection, state)
    if mutation == "heading":
        text = text.replace("== SAG R03 ==", "== SAG R03 =", 1)
    elif mutation == "tail":
        text = text.replace("allowed_person_ids=1101,1102",
                            "allowed_person_ids=1101,1103", 1)
    elif mutation == "whitespace":
        text = text.replace("[UAFKLARET] identity:R03",
                            "[UAFKLARET]  identity:R03", 1)
    else:
        text = text.replace("identity:R03", "identity:R99", 1)
    parse_failure(text, selection, state, "C3_REVIEW_LINE_TAMPERED")


@pytest.mark.parametrize("decision_id,token", [
    ("identity:R03", "SAMME"),
    ("identity:R03", "SAMME 1101 9999"),
    ("identity:R03", "samme 1101 1102"),
    ("record:R03", "TIL 9999"),
    ("record:R03", "REVISION coalesced"),
    ("record:R03", "INGEN PUBLIKATION"),
])
def test_unknown_tokens_and_people_are_terminal(decision_id, token):
    selection, state = docs()
    text = replace_token(
        rendered(selection, state), decision_id, token, selection, state)
    parse_failure(text, selection, state, "C3_REVIEW_TOKEN_INVALID")


def graph_review(identity_token, edges=None, conflicts=None):
    selection, state = docs()
    state["identity_edges"] = list(edges or [])
    state["partner_conflicts"] = list(conflicts or [])
    text = rendered(selection, state)
    text = replace_token(
        text, "identity:R03", identity_token, selection, state)
    return selection, state, text


def test_same_rejects_self_link():
    selection, state, text = graph_review("SAMME 1101 1101")
    parse_failure(text, selection, state, "C3_DECISION_SELF_LINK")


def test_same_rejects_g3_occupied_alias():
    selection, state, text = graph_review(
        "SAMME 1101 1102",
        edges=[{"role": "samme_som", "subject_id": 1101,
                "object_id": 9999}])
    parse_failure(text, selection, state, "C3_DECISION_G3_CONFLICT")


def test_same_rejects_g4_existing_canonical_as_alias():
    selection, state, text = graph_review(
        "SAMME 1101 1102",
        edges=[{"role": "samme_som", "subject_id": 9999,
                "object_id": 1101}])
    parse_failure(text, selection, state, "C3_DECISION_G4_CONFLICT")


def test_same_rejects_existing_reverse_direction():
    selection, state, text = graph_review(
        "SAMME 1101 1102",
        edges=[{"role": "samme_som", "subject_id": 1102,
                "object_id": 1101}])
    parse_failure(text, selection, state, "C3_DECISION_G4_CONFLICT")


def test_same_rejects_normalized_direct_not_same():
    selection, state, text = graph_review(
        "SAMME 1101 1102",
        edges=[{"role": "ikke_samme_som", "subject_id": 1101,
                "object_id": 1102}])
    parse_failure(text, selection, state, "C3_DECISION_NOT_SAME_CONFLICT")


def test_same_rejects_partner_conflict_between_relevant_components():
    selection, state, text = graph_review(
        "SAMME 1101 1102",
        edges=[{"role": "samme_som", "subject_id": 1201,
                "object_id": 1102}],
        conflicts=[{"left_person_id": 1101, "right_person_id": 1201,
                    "family_id": 77}])
    parse_failure(text, selection, state, "C3_DECISION_PARTNER_CONFLICT")


def test_exact_existing_alias_to_canonical_can_roundtrip():
    selection, state, text = graph_review(
        "SAMME 1101 1102",
        edges=[{"role": "samme_som", "subject_id": 1101,
                "object_id": 1102}])
    out = converter().parse_review(text, selection, state, hashes(text))
    assert out["cases"][0]["identity"] == {
        "action": "same", "alias_person_id": 1101,
        "canonical_person_id": 1102,
    }


@pytest.mark.parametrize("field,value", [
    ("c0_candidates_sha256", "0" * 64),
    ("c0_decisions_sha256", "0" * 64),
    ("selection_sha256", "0" * 64),
    ("state_sha256", "0" * 64),
    ("review_sha256", "0" * 64),
])
def test_stale_input_hashes_are_terminal(field, value):
    selection, state = docs()
    text = rendered(selection, state)
    input_hashes = hashes(text)
    input_hashes[field] = value
    with pytest.raises(SystemExit, match="^C3_REVIEW_HASH_MISMATCH$"):
        converter().parse_review(text, selection, state, input_hashes)


def test_stale_review_header_hash_is_terminal():
    selection, state = docs()
    text = rendered(selection, state).replace(
        "# state_sha256=" + "b" * 64,
        "# state_sha256=" + "0" * 64, 1)
    parse_failure(text, selection, state, "C3_REVIEW_HASH_MISMATCH")


@pytest.mark.parametrize("which,bad", [
    ("text", []),
    ("selection", []),
    ("selection", {"schema_version": []}),
    ("state", []),
    ("state", {"schema_version": []}),
    ("hashes", []),
    ("hashes", {"review_sha256": []}),
])
def test_wrong_json_types_never_raise_raw_exceptions(which, bad):
    selection, state = docs()
    text = rendered(selection, state)
    input_hashes = hashes(text)
    values = {"text": text, "selection": selection, "state": state,
              "hashes": input_hashes}
    values[which] = bad
    with pytest.raises(SystemExit, match="^C3_[A-Z0-9_]+$"):
        converter().parse_review(values["text"], values["selection"],
                                 values["state"], values["hashes"])


@pytest.mark.parametrize("mutation,expected", [
    ("private_person", "C3_REVIEW_PERSON_PRIVATE"),
    ("binding_type", "C3_REVIEW_BINDING_INVALID"),
])
def test_imported_document_errors_are_stable_tokens_without_person_ids(
        mutation, expected):
    selection, state = docs()
    text = rendered(selection, state)
    if mutation == "private_person":
        state["persons"][0]["privat"] = True
    else:
        state["narratives"][0]["source_record_id"] = (
            "00000000-0000-0000-0000-000000000001")
        state["narratives"][0]["binding_status"] = []
    with pytest.raises(SystemExit, match="^{}$".format(expected)) as error:
        converter().parse_review(text, selection, state, hashes(text))
    assert str(state["persons"][0]["person_id"]) not in str(error.value)


def write_cli_inputs(tmp_path):
    selection, state = docs()
    selection_path = tmp_path / "selection.json"
    state_path = tmp_path / "state.json"
    review_path = tmp_path / "review.txt"
    selection_bytes = json.dumps(
        selection, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    selection_path.write_bytes(selection_bytes)
    selection_sha = hashlib.sha256(selection_bytes).hexdigest()
    state["selection_sha256"] = selection_sha
    state_bytes = json.dumps(
        state, ensure_ascii=False, indent=1).encode("utf-8")
    state_path.write_bytes(state_bytes)
    state_sha = hashlib.sha256(state_bytes).hexdigest()
    review_bytes = build.render_review(
        selection, state, selection_sha, state_sha).encode("utf-8")
    review_path.write_bytes(review_bytes)
    return (selection_path, state_path, review_path, selection_bytes,
            state_bytes, review_bytes)


def run_cli(arguments):
    return subprocess.run(
        ["/usr/bin/python3", str(MODULE_PATH)] + arguments,
        check=False, capture_output=True, text=True)


def test_cli_hashes_raw_bytes_and_writes_text_free_json_atomically(tmp_path):
    (selection_path, state_path, review_path, selection_bytes,
     state_bytes, review_bytes) = write_cli_inputs(tmp_path)
    output_path = tmp_path / "decisions.json"
    completed = run_cli([
        "--review", str(review_path), "--selection", str(selection_path),
        "--state", str(state_path), "--output", str(output_path),
    ])
    out = json.loads(output_path.read_text(encoding="utf-8"))
    assert completed.returncode == 0
    assert completed.stdout == (
        "sager=7 records=8 beslutningslinjer=15 uafklarede=13\n")
    assert completed.stderr == ""
    assert out["input_hashes"] == {
        "c0_candidates_sha256": "c" * 64,
        "c0_decisions_sha256": "d" * 64,
        "selection_sha256": hashlib.sha256(selection_bytes).hexdigest(),
        "state_sha256": hashlib.sha256(state_bytes).hexdigest(),
        "review_sha256": hashlib.sha256(review_bytes).hexdigest(),
    }
    assert "MODEL_BLIND_SENTINEL" not in json.dumps(out, ensure_ascii=False)
    assert list(tmp_path.glob(".decisions.json.*.tmp")) == []


@pytest.mark.parametrize("arguments", [
    [], ["--help"], ["--review"], ["--review", "x", "--review", "y"],
])
def test_cli_argument_errors_are_token_only(arguments):
    completed = run_cli(arguments)
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_DECISIONS_ARGUMENTS_INVALID\n"


def test_cli_rejects_existing_output_and_preserves_it(tmp_path):
    selection_path, state_path, review_path, _, _, _ = write_cli_inputs(tmp_path)
    output_path = tmp_path / "decisions.json"
    output_path.write_text("preexisting", encoding="utf-8")
    completed = run_cli([
        "--review", str(review_path), "--selection", str(selection_path),
        "--state", str(state_path), "--output", str(output_path),
    ])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_DECISIONS_OUTPUT_EXISTS\n"
    assert output_path.read_text(encoding="utf-8") == "preexisting"


def test_cli_stale_selection_state_relationship_has_no_partial_output(tmp_path):
    selection_path, state_path, review_path, _, _, _ = write_cli_inputs(tmp_path)
    state = json.loads(state_path.read_text(encoding="utf-8"))
    state["selection_sha256"] = "0" * 64
    state_path.write_text(json.dumps(state), encoding="utf-8")
    output_path = tmp_path / "decisions.json"
    completed = run_cli([
        "--review", str(review_path), "--selection", str(selection_path),
        "--state", str(state_path), "--output", str(output_path),
    ])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_REVIEW_HASH_MISMATCH\n"
    assert not output_path.exists()


def test_cli_invalid_input_does_not_leak_review_or_write_output(tmp_path):
    selection_path, state_path, review_path, _, _, _ = write_cli_inputs(tmp_path)
    review_path.write_text("MODEL_BLIND_SENTINEL", encoding="utf-8")
    output_path = tmp_path / "decisions.json"
    completed = run_cli([
        "--review", str(review_path), "--selection", str(selection_path),
        "--state", str(state_path), "--output", str(output_path),
    ])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_REVIEW_LINE_MISSING\n"
    assert "MODEL_BLIND_SENTINEL" not in completed.stdout + completed.stderr
    assert not output_path.exists()


@pytest.mark.parametrize("document,expected", [
    ("selection", "C3_DECISIONS_SELECTION_INVALID"),
    ("state", "C3_DECISIONS_STATE_INVALID"),
])
def test_cli_wrong_top_level_json_type_is_token_only(
        tmp_path, document, expected):
    selection_path, state_path, review_path, _, _, _ = write_cli_inputs(tmp_path)
    path = selection_path if document == "selection" else state_path
    path.write_text("[]", encoding="utf-8")
    output_path = tmp_path / "decisions.json"
    completed = run_cli([
        "--review", str(review_path), "--selection", str(selection_path),
        "--state", str(state_path), "--output", str(output_path),
    ])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == expected + "\n"
    assert not output_path.exists()


def test_cli_invalid_utf8_review_is_token_only(tmp_path):
    selection_path, state_path, review_path, _, _, _ = write_cli_inputs(tmp_path)
    review_path.write_bytes(b"\xffMODEL_BLIND_SENTINEL")
    output_path = tmp_path / "decisions.json"
    completed = run_cli([
        "--review", str(review_path), "--selection", str(selection_path),
        "--state", str(state_path), "--output", str(output_path),
    ])
    assert completed.returncode != 0
    assert completed.stdout == ""
    assert completed.stderr == "C3_DECISIONS_REVIEW_INVALID\n"
    assert "MODEL_BLIND_SENTINEL" not in completed.stdout + completed.stderr
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
    with pytest.raises(SystemExit, match="^C3_DECISIONS_OUTPUT_EXISTS$"):
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
                       match="^C3_DECISIONS_OUTPUT_WRITE_FAILED$"):
        module.publish_output(output_path, "safe")
    assert not output_path.exists()
    assert all(not path.exists() for path in created_temp_paths)
