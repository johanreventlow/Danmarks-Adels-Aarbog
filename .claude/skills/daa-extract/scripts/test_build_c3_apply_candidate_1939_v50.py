import copy
import hashlib
import importlib.util
import json
import os
import stat
import subprocess
from pathlib import Path

import pytest


SCRIPT_DIR = Path(__file__).resolve().parent
MODULE_PATH = SCRIPT_DIR / "build_c3_apply_candidate_1939_v50.py"
BUILD_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"
CONVERT_PATH = SCRIPT_DIR / "convert_c3_decisions_1939_v50.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


mod = load_module("build_c3_apply_candidate_1939_v50", MODULE_PATH)
build = load_module("build_c3_review_for_apply_candidate_test", BUILD_PATH)
convert = load_module("convert_c3_decisions_for_apply_candidate_test", CONVERT_PATH)


ORDINARY_CASES = (
    ("R03", (1101, 1102)),
    ("R07", (1201, 1202)),
    ("R11", (1301, 1302)),
    ("R19", (1401, 1402)),
    ("R25", (1501, 1502)),
    ("R31", (1601, 1602)),
)


def canonical_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")


def candidate(person_id, rid):
    return {
        "person_id": person_id,
        "visning_navn": "SYNTHETIC_NAME_{}_{}".format(rid, person_id),
        "staged": False,
        "side": str(500 + int(rid[1:])),
        "person_tekst": "SYNTHETIC_PERSON_CONTEXT_{}_{}".format(rid, person_id),
    }


def record(rid, person_ids):
    return {
        "rid": rid,
        "new_record_key": "synthetic-{}".format(rid.lower()),
        "classification": "sammenlaegning" if rid != "R40" else "kobling",
        "verbatim_text": "1. Synthetic {} line-\nbreak.".format(rid),
        "candidates": [candidate(person_id, rid) for person_id in person_ids],
    }


def selection_doc():
    cases = [{
        "case_kind": "ordinary",
        "candidate_person_ids": list(person_ids),
        "records": [record(rid, person_ids)],
    } for rid, person_ids in ORDINARY_CASES]
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


def state_doc(selection_raw):
    selection = json.loads(selection_raw)
    person_ids = selection["person_ids"]
    return {
        "schema_version": "1939-v50-c3-current-state-v1",
        "database_name": "synthetic",
        "database_identity": "42",
        "generator": "synthetic:v1",
        "selection_sha256": hashlib.sha256(selection_raw).hexdigest(),
        "persons": [{"person_id": person_id, "staged": False, "privat": False}
                    for person_id in person_ids],
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


def replace_token(text, decision_id, token, selection, state):
    item = next(row for row in build.review_sequence(selection, state)
                if row.get("decision_id") == decision_id)
    old = "[{}] {}".format(item["default_token"], item["tail"])
    new = "[{}] {}".format(token, item["tail"])
    assert text.count(old) == 1
    return text.replace(old, new, 1)


def chain(tokens=None):
    selection = selection_doc()
    selection_raw = canonical_bytes(selection)
    state = state_doc(selection_raw)
    state_raw = canonical_bytes(state)
    review = build.render_review(
        selection, state, hashlib.sha256(selection_raw).hexdigest(),
        hashlib.sha256(state_raw).hexdigest())
    # Spejler fasens reelle facon (revideret 2026-08-23): fem hele sager,
    # fire assigns og TO no_publication — R19 er testens modstykke til den
    # ægte R28, hvis recordbeslutning blev flippet fra assign til
    # no_publication, da personens narrativ allerede var publiceret fra en
    # anden kildepost.
    default_tokens = {
        "identity:R03": "FORSKELLIGE", "record:R03": "TIL 1101",
        "identity:R07": "FORSKELLIGE", "record:R07": "TIL 1202",
        "identity:R11": "FORSKELLIGE", "record:R11": "INGEN_PUBLIKATION",
        "identity:R19": "FORSKELLIGE", "record:R19": "INGEN_PUBLIKATION",
        "identity:1017:1021": "FORSKELLIGE",
        "record:R40": "TIL 1017", "record:R15": "TIL 1021",
    }
    default_tokens.update(tokens or {})
    for decision_id, token in default_tokens.items():
        review = replace_token(review, decision_id, token, selection, state)
    review_raw = review.encode("utf-8")
    hashes = {
        "c0_candidates_sha256": selection["input_hashes"]["c0_candidates_sha256"],
        "c0_decisions_sha256": selection["input_hashes"]["c0_decisions_sha256"],
        "selection_sha256": hashlib.sha256(selection_raw).hexdigest(),
        "state_sha256": hashlib.sha256(state_raw).hexdigest(),
        "review_sha256": hashlib.sha256(review_raw).hexdigest(),
    }
    decisions = convert.parse_review(review, selection, state, hashes)
    return {
        "decisions": decisions,
        "decisions_raw": canonical_bytes(decisions),
        "selection": selection,
        "selection_raw": selection_raw,
        "state": state,
        "state_raw": state_raw,
        "review": review,
        "review_raw": review_raw,
    }


def build_candidate(values=None):
    values = values or chain()
    return mod.build_candidate_manifest(
        values["decisions_raw"], values["selection_raw"],
        values["state_raw"], values["review_raw"])


def assert_fails(code, values):
    with pytest.raises(SystemExit) as error:
        build_candidate(values)
    assert str(error.value) == code


def test_exact_five_whole_cases_and_payload_contract():
    values = chain()
    result = build_candidate(values)
    assert result["schema_version"] == "1939-v50-c3-apply-candidate-v1"
    assert result["counts"] == {
        "cases": 5,
        "identity_different": 5,
        "record_assign": 4,
        "record_no_publication": 2,
    }
    assert [case["case_id"] for case in result["cases"]] == [
        "R03", "R07", "R11", "R19", "1017/1021"]
    assert all(case["identity"]["action"] == "different"
               for case in result["cases"])
    assert not {"R25", "R31"}.intersection(
        case["case_id"] for case in result["cases"])
    assign = result["cases"][0]["record_decisions"][0]
    assert assign == {
        "action": "assign",
        "rid": "R03",
        "record_key": "synthetic-r03",
        "target_person_id": 1101,
        "target_display_name": "SYNTHETIC_NAME_R03_1101",
        "source_text": "1. Synthetic R03 line-\nbreak.",
        "raw_sha256": hashlib.sha256(
            values["selection"]["cases"][0]["records"][0]["verbatim_text"].encode("utf-8")
        ).hexdigest(),
        "normalized_text": "Synthetic R03 linebreak.",
        "normalized_sha256": hashlib.sha256(
            b"Synthetic R03 linebreak.").hexdigest(),
        "normalization_version": "narrative_norm_v1",
        "normalization_flags": [{
            "kind": "hyphen_unproven",
            "context": "1. Synthetic R03 line-\nbreak.",
            "char_offset": 21,
        }],
        "expected_narrative": {
            "privat": False,
            "side": "503",
            "record_label": "synthetic-r03",
            "citation_label": "DAA 1939 side 503",
        },
    }
    no_publication = result["cases"][2]["record_decisions"][0]
    assert no_publication == {
        "action": "no_publication", "rid": "R11",
        "record_key": "synthetic-r11",
    }
    assert not ({"normalized_text", "normalized_sha256", "raw_sha256",
                 "normalization_flags", "expected_narrative"}
                & set(no_publication))
    assert result["input_hashes"] == {
        "decisions_sha256": hashlib.sha256(values["decisions_raw"]).hexdigest(),
        "selection_sha256": hashlib.sha256(values["selection_raw"]).hexdigest(),
        "state_sha256": hashlib.sha256(values["state_raw"]).hexdigest(),
        "review_sha256": hashlib.sha256(values["review_raw"]).hexdigest(),
        "c0_candidates_sha256": "c" * 64,
        "c0_decisions_sha256": "d" * 64,
    }
    assert len(result["canonical_content_sha256"]) == 64


def test_canonical_content_sha_is_independently_reproducible_and_sensitive():
    result = build_candidate()
    stated = result["canonical_content_sha256"]
    unhashed = copy.deepcopy(result)
    del unhashed["canonical_content_sha256"]
    independently_rendered = (json.dumps(
        unhashed, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        allow_nan=False) + "\n").encode("utf-8")
    assert hashlib.sha256(independently_rendered).hexdigest() == stated

    unhashed["cases"][0]["identity"]["person_ids"][0] += 1
    mutated_rendered = (json.dumps(
        unhashed, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        allow_nan=False) + "\n").encode("utf-8")
    assert hashlib.sha256(mutated_rendered).hexdigest() != stated


@pytest.mark.parametrize("tokens", [
    {"record:R03": "UAFKLARET"},
    {"identity:R19": "UAFKLARET", "record:R19": "UAFKLARET"},
    {"identity:R25": "FORSKELLIGE", "record:R25": "TIL 1501"},
    {"identity:R03": "SAMME 1101 1102"},
    {"record:R03": "REVISION split_into"},
])
def test_rejects_partial_wrong_partition_same_and_revision(tokens):
    assert_fails("C3_APPLY_DECISION_SET_INVALID", chain(tokens))


@pytest.mark.parametrize("mutation", ["unknown", "duplicate_case", "reorder_cases"])
def test_rejects_decision_document_drift_and_duplicates(mutation):
    values = chain()
    decisions = copy.deepcopy(values["decisions"])
    if mutation == "unknown":
        decisions["cases"][0]["identity"]["action"] = "mystery"
    elif mutation == "duplicate_case":
        decisions["cases"][1] = copy.deepcopy(decisions["cases"][0])
    else:
        decisions["cases"][0], decisions["cases"][1] = (
            decisions["cases"][1], decisions["cases"][0])
    values["decisions_raw"] = canonical_bytes(decisions)
    assert_fails("C3_APPLY_DECISIONS_MISMATCH", values)


def test_rejects_duplicate_rid_and_reordered_selection():
    for mutation in ("duplicate", "reorder"):
        values = chain()
        selection = copy.deepcopy(values["selection"])
        if mutation == "duplicate":
            selection["cases"][1]["records"][0]["rid"] = "R03"
        else:
            selection["cases"][0], selection["cases"][1] = (
                selection["cases"][1], selection["cases"][0])
        values["selection_raw"] = canonical_bytes(selection)
        assert_fails("C3_APPLY_SELECTION_INVALID", values)


def test_rejects_reordered_state_rows():
    values = chain()
    state = copy.deepcopy(values["state"])
    state["persons"][0], state["persons"][1] = (
        state["persons"][1], state["persons"][0])
    values["state_raw"] = canonical_bytes(state)
    assert_fails("C3_APPLY_SELECTION_INVALID", values)


@pytest.mark.parametrize("field", [
    "c0_candidates_sha256", "c0_decisions_sha256", "selection_sha256",
    "state_sha256", "review_sha256",
])
def test_rejects_each_declared_upstream_hash_drift(field):
    values = chain()
    decisions = copy.deepcopy(values["decisions"])
    decisions["input_hashes"][field] = "f" * 64
    values["decisions_raw"] = canonical_bytes(decisions)
    assert_fails("C3_APPLY_UPSTREAM_HASH_MISMATCH", values)


@pytest.mark.parametrize("input_name", ["selection_raw", "state_raw", "review_raw"])
def test_rejects_raw_byte_drift_in_hash_declared_inputs(input_name):
    values = chain()
    values[input_name] += b" "
    assert_fails("C3_APPLY_UPSTREAM_HASH_MISMATCH", values)


def test_binds_exact_decisions_bytes_even_when_json_value_is_unchanged():
    values = chain()
    original = build_candidate(values)
    values["decisions_raw"] = values["decisions_raw"].rstrip(b"\n") + b"  \n"
    changed = build_candidate(values)
    assert changed["input_hashes"]["decisions_sha256"] != (
        original["input_hashes"]["decisions_sha256"])
    assert changed["cases"] == original["cases"]


@pytest.mark.parametrize("input_name", ["decisions_raw", "selection_raw", "state_raw"])
def test_strict_json_rejects_nonfinite_constants(input_name):
    values = chain()
    values[input_name] = b'{"value":NaN}\n'
    assert_fails("C3_APPLY_{}_INVALID".format(
        input_name.replace("_raw", "").upper()), values)


@pytest.mark.parametrize("input_name,raw", [
    ("decisions_raw", b'{"schema_version":"x","schema_version":"x"}\n'),
    ("decisions_raw", b'{"schema_version":"x","schema_version":"y"}\n'),
    ("selection_raw", b'{"input_hashes":{"selection_sha256":"a","selection_sha256":"a"}}\n'),
    ("selection_raw", b'{"input_hashes":{"selection_sha256":"a","selection_sha256":"b"}}\n'),
    ("state_raw", b'{"narratives":[{"person_id":1,"person_id":1}]}\n'),
    ("state_raw", b'{"narratives":[{"person_id":1,"person_id":2}]}\n'),
])
def test_strict_json_rejects_recursive_same_and_different_duplicate_keys(
        input_name, raw):
    values = chain()
    values[input_name] = raw
    assert_fails("C3_APPLY_{}_INVALID".format(
        input_name.replace("_raw", "").upper()), values)


def test_normalization_uses_full_corpus_twice_and_rejects_nondeterminism(monkeypatch):
    values = chain()
    calls = []
    real = mod.normalize_narrative_v1

    def observing(raw, corpus):
        calls.append((raw, corpus))
        return real(raw, corpus)

    monkeypatch.setattr(mod, "normalize_narrative_v1", observing)
    build_candidate(values)
    corpus = "\n".join(record["verbatim_text"]
                       for case in values["selection"]["cases"]
                       for record in case["records"])
    # Fire assigns, hver normaliseret to gange (byggekald + genberegnings-CAS).
    assert len(calls) == 8
    assert all(call[1] == corpus for call in calls)

    counter = {"value": 0}

    def unstable(raw, corpus):
        result = copy.deepcopy(real(raw, corpus))
        counter["value"] += 1
        if counter["value"] % 2 == 0:
            result["text"] += "x"
        return result

    monkeypatch.setattr(mod, "normalize_narrative_v1", unstable)
    assert_fails("C3_APPLY_NORMALIZATION_NONDETERMINISTIC", values)


def test_rejects_duplicate_normalization_flags(monkeypatch):
    values = chain()
    real = mod.normalize_narrative_v1

    def duplicate_flags(raw, corpus):
        result = copy.deepcopy(real(raw, corpus))
        flag = {"kind": "synthetic", "context": "safe", "char_offset": 0}
        result["flags"] = [flag, copy.deepcopy(flag)]
        return result

    monkeypatch.setattr(mod, "normalize_narrative_v1", duplicate_flags)
    assert_fails("C3_APPLY_NORMALIZATION_FLAGS_INVALID", values)


def write_chain(tmp_path, values=None):
    values = values or chain()
    paths = {}
    for name in ("decisions", "selection", "state", "review"):
        path = tmp_path / (name + (".txt" if name == "review" else ".json"))
        path.write_bytes(values[name + "_raw"])
        paths[name] = path
    paths["output"] = tmp_path / "candidate.json"
    return paths


def invoke(paths, env=None):
    return subprocess.run([
        "/usr/bin/python3", str(MODULE_PATH),
        "--decisions", str(paths["decisions"]),
        "--selection", str(paths["selection"]),
        "--state", str(paths["state"]),
        "--review", str(paths["review"]),
        "--output", str(paths["output"]),
    ], text=True, capture_output=True, check=False, env=env)


def test_cli_publishes_canonical_no_clobber_output_with_safe_stdout(tmp_path):
    paths = write_chain(tmp_path)
    env = dict(os.environ)
    pg_values = {
        "PGDATABASE": "SENSITIVE_DB_SENTINEL",
        "PGHOST": "SENSITIVE_HOST_SENTINEL",
        "PGPORT": "65432",
        "PGUSER": "SENSITIVE_USER_SENTINEL",
        "PGPASSWORD": "SENSITIVE_PASSWORD_SENTINEL",
    }
    env.update(pg_values)
    completed = invoke(paths, env=env)
    assert completed.returncode == 0
    output_raw = paths["output"].read_bytes()
    assert output_raw == canonical_bytes(json.loads(output_raw))
    assert json.loads(output_raw) == build_candidate()
    assert completed.stderr == ""
    assert "schema=1939-v50-c3-apply-candidate-v1" in completed.stdout
    assert "cases=5" in completed.stdout
    assert paths["output"].name in completed.stdout
    assert hashlib.sha256(output_raw).hexdigest() in completed.stdout
    combined_output = completed.stdout + completed.stderr
    for forbidden in ("Synthetic", "line-break", str(tmp_path),
                      *pg_values.keys(), *pg_values.values()):
        assert forbidden not in combined_output

    original = output_raw
    second = invoke(paths)
    assert second.returncode == 1
    assert second.stderr == "C3_APPLY_OUTPUT_EXISTS\n"
    assert paths["output"].read_bytes() == original


@pytest.mark.parametrize("kind", [
    "input_symlink", "input_directory", "output_symlink", "output_parent_symlink",
])
def test_cli_rejects_symlink_and_non_file_paths(tmp_path, kind):
    paths = write_chain(tmp_path)
    if kind == "input_symlink":
        target = paths["selection"]
        link = tmp_path / "selection-link.json"
        link.symlink_to(target)
        paths["selection"] = link
    elif kind == "input_directory":
        paths["selection"] = tmp_path
    elif kind == "output_symlink":
        paths["output"].symlink_to(paths["selection"])
    else:
        real_parent = tmp_path / "real-parent"
        real_parent.mkdir()
        linked_parent = tmp_path / "linked-parent"
        linked_parent.symlink_to(real_parent, target_is_directory=True)
        paths["output"] = linked_parent / "candidate.json"
    completed = invoke(paths)
    assert completed.returncode == 1
    assert not list(tmp_path.glob(".candidate.json.*.tmp"))


def test_publish_cleans_temp_after_link_failure(tmp_path, monkeypatch):
    output = tmp_path / "candidate.json"

    def fail_link(source, destination, *args, **kwargs):
        raise OSError("synthetic link failure")

    monkeypatch.setattr(mod.os, "link", fail_link)
    with pytest.raises(SystemExit) as error:
        mod.publish_output(output, "{}\n")
    assert str(error.value) == "C3_APPLY_OUTPUT_WRITE_FAILED"
    assert not output.exists()
    assert not list(tmp_path.glob(".c3-apply-*.tmp"))


def test_publish_rolls_back_target_when_temp_unlink_fails(
        tmp_path, monkeypatch):
    output = tmp_path / "candidate.json"
    real_unlink = mod.os.unlink
    failed = {"value": False}

    def fail_first_temp_unlink(path, *args, **kwargs):
        if str(path).endswith(".tmp") and not failed["value"]:
            failed["value"] = True
            raise OSError("synthetic temp unlink failure")
        return real_unlink(path, *args, **kwargs)

    monkeypatch.setattr(mod.os, "unlink", fail_first_temp_unlink)
    with pytest.raises(SystemExit) as error:
        mod.publish_output(output, "{}\n")
    assert str(error.value) == "C3_APPLY_OUTPUT_WRITE_FAILED"
    assert not output.exists()
    assert not list(tmp_path.glob(".c3-apply-*.tmp"))


def test_publish_does_not_claim_success_when_directory_fsync_fails(
        tmp_path, monkeypatch):
    output = tmp_path / "candidate.json"
    real_fsync = mod.os.fsync

    def fail_directory_fsync(descriptor):
        if stat.S_ISDIR(os.fstat(descriptor).st_mode):
            raise OSError("synthetic directory fsync failure")
        return real_fsync(descriptor)

    monkeypatch.setattr(mod.os, "fsync", fail_directory_fsync)
    with pytest.raises(SystemExit) as error:
        mod.publish_output(output, "{}\n")
    assert str(error.value) == "C3_APPLY_OUTPUT_RECOVERY_REQUIRED"
    assert not output.exists()
    assert not list(tmp_path.glob(".c3-apply-*.tmp"))


def dirfd_inventory(directory):
    descriptor = os.open(
        str(directory), os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        return {
            name: (os.stat(name, dir_fd=descriptor, follow_symlinks=False).st_dev,
                   os.stat(name, dir_fd=descriptor, follow_symlinks=False).st_ino)
            for name in os.listdir(descriptor)
        }
    finally:
        os.close(descriptor)


def test_parent_path_replacement_after_open_cannot_redirect_publication(
        tmp_path, monkeypatch):
    parent = tmp_path / "parent"
    parent.mkdir()
    moved_parent = tmp_path / "verified-parent"
    output = parent / "candidate.json"
    real_open = mod.os.open
    swapped = {"value": False}

    def swap_after_parent_open(path, flags, *args, **kwargs):
        descriptor = real_open(path, flags, *args, **kwargs)
        if path == str(parent) and kwargs.get("dir_fd") is None and not swapped["value"]:
            swapped["value"] = True
            parent.rename(moved_parent)
            parent.mkdir()
            (parent / "candidate.json").write_bytes(b"replacement-target")
        return descriptor

    monkeypatch.setattr(mod.os, "open", swap_after_parent_open)
    mod.publish_output(output, "{}\n")

    assert set(dirfd_inventory(parent)) == {"candidate.json"}
    assert (parent / "candidate.json").read_bytes() == b"replacement-target"
    moved = dirfd_inventory(moved_parent)
    assert set(moved) == {"candidate.json"}
    assert (moved_parent / "candidate.json").read_text(encoding="utf-8") == "{}\n"


def test_randomized_temp_name_collision_never_touches_existing_entry(
        tmp_path, monkeypatch):
    collision_token = "a" * 32
    unique_token = "b" * 32
    collision = tmp_path / ".c3-apply-{}.tmp".format(collision_token)
    collision.write_bytes(b"pre-existing")
    names = iter((collision_token, unique_token))
    monkeypatch.setattr(mod.secrets, "token_hex", lambda _size: next(names))

    output = tmp_path / "candidate.json"
    mod.publish_output(output, "{}\n")

    assert collision.read_bytes() == b"pre-existing"
    inventory = dirfd_inventory(tmp_path)
    assert set(inventory) == {collision.name, "candidate.json"}
    assert stat.S_IMODE(output.stat().st_mode) == 0o600


def test_compound_temp_unlink_and_target_rollback_failure_requires_recovery(
        tmp_path, monkeypatch):
    output = tmp_path / "candidate.json"
    real_unlink = mod.os.unlink

    def fail_temp_and_target_unlink(path, *args, **kwargs):
        if str(path).endswith(".tmp") or str(path) == "candidate.json":
            raise OSError("synthetic permanent unlink failure")
        return real_unlink(path, *args, **kwargs)

    monkeypatch.setattr(mod.os, "unlink", fail_temp_and_target_unlink)
    with pytest.raises(SystemExit) as error:
        mod.publish_output(output, "{}\n")
    assert str(error.value) == "C3_APPLY_OUTPUT_RECOVERY_REQUIRED"
    inventory = dirfd_inventory(tmp_path)
    assert "candidate.json" in inventory
    residues = [name for name in inventory if name.startswith(".c3-apply-")]
    assert len(residues) == 1
    assert inventory["candidate.json"] == inventory[residues[0]]


def test_compound_link_and_temp_cleanup_failure_requires_recovery(
        tmp_path, monkeypatch):
    output = tmp_path / "candidate.json"
    real_link = mod.os.link
    real_unlink = mod.os.unlink

    def fail_link(*args, **kwargs):
        raise OSError("synthetic link failure")

    def fail_temp_cleanup(path, *args, **kwargs):
        if str(path).endswith(".tmp"):
            raise OSError("synthetic permanent temp cleanup failure")
        return real_unlink(path, *args, **kwargs)

    monkeypatch.setattr(mod.os, "link", fail_link)
    monkeypatch.setattr(mod.os, "unlink", fail_temp_cleanup)
    with pytest.raises(SystemExit) as error:
        mod.publish_output(output, "{}\n")
    assert str(error.value) == "C3_APPLY_OUTPUT_RECOVERY_REQUIRED"
    inventory = dirfd_inventory(tmp_path)
    assert "candidate.json" not in inventory
    assert len([name for name in inventory if name.startswith(".c3-apply-")]) == 1


def test_existing_target_is_never_removed_during_collision_cleanup(
        tmp_path):
    output = tmp_path / "candidate.json"
    output.write_bytes(b"pre-existing-target")
    before = dirfd_inventory(tmp_path)["candidate.json"]
    with pytest.raises(SystemExit) as error:
        mod.publish_output(output, "{}\n")
    assert str(error.value) == "C3_APPLY_OUTPUT_EXISTS"
    assert output.read_bytes() == b"pre-existing-target"
    assert dirfd_inventory(tmp_path)["candidate.json"] == before


def test_ownership_fd_remains_open_through_inventory_and_all_fds_close(
        tmp_path, monkeypatch):
    output = tmp_path / "candidate.json"
    real_open = mod.os.open
    real_dup = mod.os.dup
    real_stat = mod.os.stat
    temp_descriptors = []
    all_descriptors = []

    def recording_open(path, flags, *args, **kwargs):
        descriptor = real_open(path, flags, *args, **kwargs)
        all_descriptors.append(descriptor)
        if (kwargs.get("dir_fd") is not None
                and str(path).startswith(".c3-apply-")):
            temp_descriptors.append(descriptor)
        return descriptor

    def recording_dup(descriptor):
        duplicate = real_dup(descriptor)
        all_descriptors.append(duplicate)
        return duplicate

    def ownership_checked_stat(path, *args, **kwargs):
        if kwargs.get("dir_fd") is not None:
            assert any(_fd_is_open(descriptor)
                       for descriptor in temp_descriptors)
        return real_stat(path, *args, **kwargs)

    def _fd_is_open(descriptor):
        try:
            os.fstat(descriptor)
        except OSError:
            return False
        return True

    monkeypatch.setattr(mod.os, "open", recording_open)
    monkeypatch.setattr(mod.os, "dup", recording_dup)
    monkeypatch.setattr(mod.os, "stat", ownership_checked_stat)
    mod.publish_output(output, "{}\n")

    assert len(temp_descriptors) == 1
    assert all(not _fd_is_open(descriptor) for descriptor in all_descriptors)


@pytest.mark.parametrize("mutation", ["remove", "replace"])
def test_final_inventory_detects_target_mutation_during_directory_fsync(
        tmp_path, monkeypatch, mutation):
    output = tmp_path / "candidate.json"
    real_fsync = mod.os.fsync
    real_unlink = mod.os.unlink
    real_open = mod.os.open
    mutated = {"value": False}

    def mutate_after_first_directory_fsync(descriptor):
        result = real_fsync(descriptor)
        if (stat.S_ISDIR(os.fstat(descriptor).st_mode)
                and not mutated["value"]):
            mutated["value"] = True
            real_unlink("candidate.json", dir_fd=descriptor)
            if mutation == "replace":
                foreign = real_open(
                    "candidate.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600, dir_fd=descriptor)
                try:
                    os.write(foreign, b"foreign-target")
                    real_fsync(foreign)
                finally:
                    os.close(foreign)
        return result

    monkeypatch.setattr(mod.os, "fsync", mutate_after_first_directory_fsync)
    with pytest.raises(SystemExit) as error:
        mod.publish_output(output, "{}\n")
    assert str(error.value) == "C3_APPLY_OUTPUT_RECOVERY_REQUIRED"
    assert not list(tmp_path.glob(".c3-apply-*.tmp"))
    if mutation == "remove":
        assert not output.exists()
    else:
        assert output.read_bytes() == b"foreign-target"


def test_post_link_failure_never_unlinks_foreign_replacement(
        tmp_path, monkeypatch):
    output = tmp_path / "candidate.json"
    real_unlink = mod.os.unlink
    real_open = mod.os.open
    replaced = {"value": False}

    def replace_target_when_temp_unlink_fails(path, *args, **kwargs):
        if str(path).endswith(".tmp") and not replaced["value"]:
            replaced["value"] = True
            directory_fd = kwargs["dir_fd"]
            real_unlink("candidate.json", dir_fd=directory_fd)
            foreign = real_open(
                "candidate.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600, dir_fd=directory_fd)
            try:
                os.write(foreign, b"foreign-after-link")
                os.fsync(foreign)
            finally:
                os.close(foreign)
            raise OSError("synthetic post-link failure")
        return real_unlink(path, *args, **kwargs)

    monkeypatch.setattr(mod.os, "unlink", replace_target_when_temp_unlink_fails)
    with pytest.raises(SystemExit) as error:
        mod.publish_output(output, "{}\n")
    assert str(error.value) == "C3_APPLY_OUTPUT_RECOVERY_REQUIRED"
    assert output.read_bytes() == b"foreign-after-link"
    assert not list(tmp_path.glob(".c3-apply-*.tmp"))


def test_cli_argument_surface_is_exact(tmp_path):
    paths = write_chain(tmp_path)
    completed = subprocess.run(
        ["/usr/bin/python3", str(MODULE_PATH), "--unknown", "x"],
        text=True, capture_output=True, check=False)
    assert completed.returncode == 1
    assert completed.stderr == "C3_APPLY_ARGUMENTS_INVALID\n"
