import copy
import hashlib
import importlib.util
import json
from pathlib import Path

import pytest


SCRIPT_DIR = Path(__file__).resolve().parent
MODULE_PATH = SCRIPT_DIR / "build_c3_html_review_1939_v50.py"
FIXTURE_PATH = SCRIPT_DIR / "c3_html_review_test_fixtures.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


fixtures = load_module("c3_html_review_test_fixtures", FIXTURE_PATH)
mod = load_module("build_c3_html_review_1939_v50", MODULE_PATH)


def fixture_chain(tmp_path):
    paths = fixtures.write_fixture(tmp_path)
    selection = json.loads(paths["selection"].read_text(encoding="utf-8"))
    state = json.loads(paths["state"].read_text(encoding="utf-8"))
    review_raw = paths["review"].read_bytes()
    return paths, selection, state, review_raw, fixtures.input_hashes(paths)


def html_error(expected, call):
    with pytest.raises(SystemExit) as caught:
        call()
    token = str(caught.value)
    assert token == expected
    assert token.startswith("C3_HTML_")
    assert "Syntetisk" not in token
    assert fixtures.ATTACK_SENTINEL not in token


def with_review_hash(hashes, review_raw):
    changed = dict(hashes)
    changed["review_sha256"] = hashlib.sha256(review_raw).hexdigest()
    return changed


def encode_document(document):
    return (json.dumps(
        document, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode(
            "utf-8")


def rebind_documents(selection, state, hashes):
    selection_raw = encode_document(selection)
    changed_hashes = dict(hashes)
    changed_hashes["selection_sha256"] = hashlib.sha256(
        selection_raw).hexdigest()
    state["selection_sha256"] = changed_hashes["selection_sha256"]
    state_raw = encode_document(state)
    changed_hashes["state_sha256"] = hashlib.sha256(state_raw).hexdigest()
    return selection_raw, state_raw, changed_hashes


def test_fixture_factory_writes_locked_synthetic_chain(tmp_path):
    paths, selection, state, review_raw, hashes = fixture_chain(tmp_path)
    assert set(paths) == {"selection", "state", "review"}
    assert selection["case_count"] == 7
    assert selection["record_count"] == 8
    assert selection["decision_line_count"] == 15
    assert len(selection["cases"]) == 7
    assert sum(len(case["records"]) for case in selection["cases"]) == 8
    assert selection["cases"][-1]["case_kind"] == "1017_1021"
    assert [row["rid"] for row in selection["cases"][-1]["records"]] == [
        "R15", "R40"]
    assert state["selection_sha256"] == hashes["selection_sha256"]
    decoded = review_raw.decode("utf-8")
    assert sum(line.startswith("[") for line in decoded.splitlines()) == 15
    assert "ÆØÅ" in decoded
    assert fixtures.ATTACK_SENTINEL in decoded


def test_decision_slots_are_unique_ordered_exact_byte_intervals(tmp_path):
    paths, _, _, review_raw, hashes = fixture_chain(tmp_path)
    slots = mod.decision_slots(
        review_raw, paths["selection"].read_bytes(),
        paths["state"].read_bytes(), hashes)
    assert len(slots) == 15
    assert len({slot["decision_id"] for slot in slots}) == 15
    assert all(slots[index]["end"] <= slots[index + 1]["start"]
               for index in range(14))
    assert all(review_raw[slot["start"]:slot["end"]].decode("utf-8")
               == slot["default_token"] for slot in slots)
    assert [(slot["decision_id"], slot["default_token"])
            for slot in slots[-3:]] == [
        ("identity:1017:1021", "SAMME 1021 1017"),
        ("record:R40", "TIL 1017"),
        ("record:R15", "TIL 1021"),
    ]
    assert [slot["case_id"] for slot in slots[-3:]] == [
        "1017/1021", "1017/1021", "1017/1021"]


@pytest.mark.parametrize("hash_name", [
    "c0_candidates_sha256",
    "c0_decisions_sha256",
    "selection_sha256",
    "state_sha256",
    "review_sha256",
])
def test_any_hash_drift_is_terminal(tmp_path, hash_name):
    paths, _, _, review_raw, hashes = fixture_chain(tmp_path)
    hashes[hash_name] = "0" * 64
    html_error(
        "C3_HTML_HASH_MISMATCH",
        lambda: mod.decision_slots(
            review_raw, paths["selection"].read_bytes(),
            paths["state"].read_bytes(), hashes))


def test_selection_content_drift_with_old_hash_is_terminal(tmp_path):
    paths, selection, _, review_raw, hashes = fixture_chain(tmp_path)
    selection["extra_valid_field"] = "changed"
    changed_selection_raw = encode_document(selection)
    html_error(
        "C3_HTML_HASH_MISMATCH",
        lambda: mod.decision_slots(
            review_raw, changed_selection_raw, paths["state"].read_bytes(),
            hashes))


def test_state_content_drift_with_old_hash_is_terminal(tmp_path):
    paths, _, state, review_raw, hashes = fixture_chain(tmp_path)
    state["database_identity"] = "43"
    changed_state_raw = encode_document(state)
    html_error(
        "C3_HTML_HASH_MISMATCH",
        lambda: mod.decision_slots(
            review_raw, paths["selection"].read_bytes(), changed_state_raw,
            hashes))


def test_invalid_utf8_is_terminal_without_input_leakage(tmp_path):
    paths, _, _, review_raw, hashes = fixture_chain(tmp_path)
    invalid = review_raw + b"\xff"
    hashes = with_review_hash(hashes, invalid)
    html_error(
        "C3_HTML_REVIEW_INVALID",
        lambda: mod.decision_slots(
            invalid, paths["selection"].read_bytes(),
            paths["state"].read_bytes(), hashes))


@pytest.mark.parametrize("change", ["missing", "extra", "duplicate", "reordered"])
def test_decision_line_structure_drift_is_terminal(tmp_path, change):
    paths, _, _, review_raw, hashes = fixture_chain(tmp_path)
    lines = review_raw.decode("utf-8").splitlines(keepends=True)
    decision_indexes = [index for index, line in enumerate(lines)
                        if line.startswith("[")]
    first, second = decision_indexes[:2]
    if change == "missing":
        lines.pop(first)
    elif change == "extra":
        lines.insert(first, "EKSTRA LINJE\n")
    elif change == "duplicate":
        lines.insert(first, lines[first])
    else:
        lines[first], lines[second] = lines[second], lines[first]
    changed = "".join(lines).encode("utf-8")
    html_error(
        "C3_HTML_REVIEW_INVALID",
        lambda: mod.decision_slots(
            changed, paths["selection"].read_bytes(),
            paths["state"].read_bytes(),
            with_review_hash(hashes, changed)))


def test_duplicate_authoritative_decision_ids_are_terminal(tmp_path,
                                                            monkeypatch):
    paths, _, _, review_raw, hashes = fixture_chain(tmp_path)
    real_sequence = mod.build.review_sequence

    def duplicate_sequence(selection_doc, state_doc):
        sequence = copy.deepcopy(real_sequence(selection_doc, state_doc))
        decisions = [item for item in sequence if item["type"] != "heading"]
        decisions[1]["decision_id"] = decisions[0]["decision_id"]
        return sequence

    monkeypatch.setattr(mod.build, "review_sequence", duplicate_sequence)
    html_error(
        "C3_HTML_DECISION_DUPLICATE",
        lambda: mod.decision_slots(
            review_raw, paths["selection"].read_bytes(),
            paths["state"].read_bytes(), hashes))


@pytest.mark.parametrize("mutation", [
    "zero_width", "out_of_range", "overlap", "wrong_bytes"])
def test_invalid_interval_contract_is_terminal(tmp_path, mutation):
    paths, _, _, review_raw, hashes = fixture_chain(tmp_path)
    slots = mod._discover_slots(
        review_raw, paths["selection"].read_bytes(),
        paths["state"].read_bytes(), hashes)
    changed = list(slots)
    first = changed[0]
    second = changed[1]
    if mutation == "zero_width":
        changed[0] = mod.DecisionSlot(
            first.decision_id, first.case_id, first.decision_type,
            first.start, first.start, first.default_token,
            first.allowed_person_ids)
    elif mutation == "out_of_range":
        changed[0] = mod.DecisionSlot(
            first.decision_id, first.case_id, first.decision_type,
            first.start, len(review_raw) + 1, first.default_token,
            first.allowed_person_ids)
    elif mutation == "overlap":
        changed[1] = mod.DecisionSlot(
            second.decision_id, second.case_id, second.decision_type,
            first.end - 1, second.end, second.default_token,
            second.allowed_person_ids)
    else:
        changed[0] = mod.DecisionSlot(
            first.decision_id, first.case_id, first.decision_type,
            first.start, first.end, "FORSKELLIGE",
            first.allowed_person_ids)
    html_error(
        "C3_HTML_SLOT_INVALID",
        lambda: mod._validate_slot_contract(review_raw, changed))


@pytest.mark.parametrize("field,value", [
    ("case_count", 6),
    ("record_count", 7),
    ("decision_line_count", 14),
])
def test_any_unlocked_count_is_terminal(tmp_path, field, value):
    _, selection, state, review_raw, hashes = fixture_chain(tmp_path)
    selection[field] = value
    selection_raw, state_raw, hashes = rebind_documents(
        selection, state, hashes)
    html_error(
        "C3_HTML_COUNT_INVALID",
        lambda: mod.decision_slots(
            review_raw, selection_raw, state_raw, hashes))


@pytest.mark.parametrize("removed", ["case", "record"])
def test_actual_case_and_record_counts_are_terminal(tmp_path, removed):
    _, selection, state, review_raw, hashes = fixture_chain(tmp_path)
    if removed == "case":
        selection["cases"].pop(0)
    else:
        selection["cases"][0]["records"].pop()
    selection_raw, state_raw, hashes = rebind_documents(
        selection, state, hashes)
    html_error(
        "C3_HTML_COUNT_INVALID",
        lambda: mod.decision_slots(
            review_raw, selection_raw, state_raw, hashes))


@pytest.mark.parametrize("drift", [
    "kind", "ids", "record_order", "r15_candidates", "r40_candidates"])
def test_broken_special_contract_is_terminal(tmp_path, drift):
    _, selection, state, review_raw, hashes = fixture_chain(tmp_path)
    special = selection["cases"][-1]
    if drift == "kind":
        special["case_kind"] = "ordinary"
    elif drift == "ids":
        special["candidate_person_ids"] = [1017]
    elif drift == "record_order":
        special["records"].reverse()
    elif drift == "r15_candidates":
        special["records"][0]["candidates"].pop()
    else:
        special["records"][1]["candidates"][0]["person_id"] = 1021
    selection_raw, state_raw, hashes = rebind_documents(
        selection, state, hashes)
    html_error(
        "C3_HTML_SPECIAL_INVALID",
        lambda: mod.decision_slots(
            review_raw, selection_raw, state_raw, hashes))


def test_fixture_cli_prints_only_safe_metadata(tmp_path, capsys):
    assert fixtures.main(["--output-dir", str(tmp_path)]) == 0
    captured = capsys.readouterr()
    assert captured.err == ""
    assert "selection.json state.json review.txt" in captured.out
    assert "sager=7 records=8 beslutningslinjer=15" in captured.out
    assert "Syntetisk" not in captured.out
    assert fixtures.ATTACK_SENTINEL not in captured.out
