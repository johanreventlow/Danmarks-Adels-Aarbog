import base64
import copy
import hashlib
import importlib.util
import json
import re
import subprocess
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


def build_artifact(tmp_path):
    paths, _, _, review_raw, hashes = fixture_chain(tmp_path)
    selection_raw = paths["selection"].read_bytes()
    state_raw = paths["state"].read_bytes()
    payload = mod.build_payload(
        selection_raw, state_raw, review_raw, hashes)
    html = mod.render_html(payload, review_raw)
    return paths, review_raw, hashes, payload, html


def extract_client_script(html, tmp_path):
    decoded = html.decode("utf-8")
    matches = re.findall(r"<script>(.*?)</script>", decoded, re.DOTALL)
    assert len(matches) == 1
    script_path = tmp_path / "generated-c3-review.js"
    script_path.write_text(matches[0], encoding="utf-8")
    return matches[0], script_path


def run_client_function(script_path, assertions):
    runnable = script_path.with_name("generated-c3-review-test.js")
    runnable.write_text(
        script_path.read_text(encoding="utf-8") + "\n" + assertions,
        encoding="utf-8")
    return subprocess.run(
        ["node", str(runnable)], check=True, capture_output=True, text=True)


def test_payload_has_seven_cards_and_fifteen_closed_controls(tmp_path):
    _, _, _, payload, _ = build_artifact(tmp_path)
    assert payload["counts"] == {
        "cases": 7,
        "records": 8,
        "decisions": 15,
    }
    assert len(payload["cases"]) == 7
    assert [len(case["controls"]) for case in payload["cases"]] == [
        2, 2, 2, 2, 2, 2, 3]
    assert [[control["decision_type"] for control in case["controls"]]
            for case in payload["cases"][:-1]] == [
        ["identity", "record"] for _case in range(6)]
    assert [control["decision_type"]
            for control in payload["cases"][-1]["controls"]] == [
        "identity", "record", "record"]
    assert [control["default_token"]
            for case in payload["cases"]
            for control in case["controls"]] == [
        "UAFKLARET", "UAFKLARET",
        "UAFKLARET", "UAFKLARET",
        "UAFKLARET", "UAFKLARET",
        "UAFKLARET", "UAFKLARET",
        "UAFKLARET", "UAFKLARET",
        "UAFKLARET", "UAFKLARET",
        "SAMME 1021 1017", "TIL 1017", "TIL 1021",
    ]
    assert payload["vocabulary"] == {
        "identity_actions": ["UAFKLARET", "FORSKELLIGE", "SAMME"],
        "record_actions": [
            "UAFKLARET", "TIL", "INGEN_PUBLIKATION", "REVISION"],
        "revision_kinds": ["split_into", "merged_from", "replaced_by"],
    }


def test_payload_contains_local_case_context_only(tmp_path):
    _, _, _, payload, _ = build_artifact(tmp_path)
    first = payload["cases"][0]
    assert first["case_id"] == "R03"
    assert [record["rid"] for record in first["records"]] == ["R03"]
    assert [row["person_id"] for row in first["persons"]] == [1101, 1102]
    assert [row["person_id"] for row in first["narratives"]] == [1101, 1102]
    assert fixtures.ATTACK_SENTINEL in json.dumps(first, ensure_ascii=False)
    assert all(
        set(control["allowed_person_ids"]) == {1101, 1102}
        for control in first["controls"])
    special = payload["cases"][-1]
    assert special["case_id"] == "1017/1021"
    assert [record["rid"] for record in special["records"]] == ["R15", "R40"]


def test_html_keeps_all_untrusted_data_behind_base64_boundary(tmp_path):
    _, review_raw, _, payload, html = build_artifact(tmp_path)
    decoded = html.decode("utf-8")
    blocks = dict(re.findall(
        r'<div id="(c3-(?:payload|review))" hidden>([A-Za-z0-9_=-]+)</div>',
        decoded))
    assert set(blocks) == {"c3-payload", "c3-review"}
    assert json.loads(base64.urlsafe_b64decode(
        blocks["c3-payload"]).decode("utf-8")) == payload
    assert base64.urlsafe_b64decode(blocks["c3-review"]) == review_raw
    assert fixtures.ATTACK_SENTINEL not in decoded
    assert "Syntetisk Ægir" not in decoded
    assert review_raw.decode("utf-8") not in decoded


def test_generated_client_is_valid_javascript_and_has_no_forbidden_path(
        tmp_path):
    _, _, _, _, html = build_artifact(tmp_path)
    script, script_path = extract_client_script(html, tmp_path)
    checked = subprocess.run(
        ["node", "--check", str(script_path)], check=True,
        capture_output=True, text=True)
    assert checked.stdout == ""
    assert checked.stderr == ""
    forbidden = [
        r"innerHTML", r"fetch\s*\(", r"XMLHttpRequest", r"WebSocket",
        r"localStorage", r"sessionStorage", r"indexedDB",
        r"document\.cookie", r"supabase", r"\beval\s*\(",
        r"new\s+Function", r"\.setAttribute\(\s*['\"]on",
    ]
    assert not any(re.search(pattern, script, re.IGNORECASE)
                   for pattern in forbidden)
    document = html.decode("utf-8")
    assert not re.search(r"<[^>]+\son[a-z]+\s*=", document, re.IGNORECASE)
    assert not re.search(r"<(?:script|link|img)[^>]+\s(?:src|href)\s*=",
                         document, re.IGNORECASE)


def test_base64_separator_cannot_terminate_the_client_script(tmp_path):
    _, _, _, payload, _ = build_artifact(tmp_path)
    payload = copy.deepcopy(payload)
    payload["cases"][0]["records"][0]["verbatim_text"] = (
        "</script><script>globalThis.__C3_PWNED__=1</script>")
    html = mod.render_html(payload, b"</script>\x00\xff")
    decoded = html.decode("utf-8")
    assert decoded.count("<script>") == 1
    assert decoded.count("</script>") == 1
    assert "__C3_PWNED__" not in decoded
    _, script_path = extract_client_script(html, tmp_path)
    subprocess.run(["node", "--check", str(script_path)], check=True,
                   capture_output=True, text=True)


def test_client_unchanged_export_is_byte_identical(tmp_path):
    _, review_raw, _, payload, html = build_artifact(tmp_path)
    _, script_path = extract_client_script(html, tmp_path)
    slots_json = json.dumps([
        dict(slot, token=slot["default_token"])
        for slot in payload["slots"]], ensure_ascii=True)
    result = run_client_function(
        script_path,
        "const source = decodeBase64Url({});\n"
        "const result = replaceTokenBytes(source, {});\n"
        "process.stdout.write(encodeBase64Url(result));\n".format(
            json.dumps(base64.urlsafe_b64encode(review_raw).decode("ascii")),
            slots_json))
    assert base64.urlsafe_b64decode(result.stdout) == review_raw


def test_client_descending_replacement_preserves_danish_and_newlines(tmp_path):
    _, _, _, _, html = build_artifact(tmp_path)
    _, script_path = extract_client_script(html, tmp_path)
    source = "Æ[UAFKLARET]\r\nØ[UAFKLARET]\nå".encode("utf-8")
    first_start = source.index(b"UAFKLARET")
    second_start = source.index(b"UAFKLARET", first_start + 1)
    token_length = len(b"UAFKLARET")
    slots = [
        {"start": first_start, "end": first_start + token_length,
         "token": "FORSKELLIGE"},
        {"start": second_start, "end": second_start + token_length,
         "token": "TIL 7"},
    ]
    result = run_client_function(
        script_path,
        "const source = decodeBase64Url({});\n"
        "const result = replaceTokenBytes(source, {});\n"
        "process.stdout.write(encodeBase64Url(result));\n".format(
            json.dumps(base64.urlsafe_b64encode(source).decode("ascii")),
            json.dumps(slots)))
    assert base64.urlsafe_b64decode(result.stdout) == (
        "Æ[FORSKELLIGE]\r\nØ[TIL 7]\nå".encode("utf-8"))


def test_cli_publishes_one_self_contained_html_and_safe_metadata(
        tmp_path, capsys):
    fixture_dir = tmp_path / "fixture"
    paths, _, _, _, hashes = fixture_chain(fixture_dir)
    output = tmp_path / "c3-review.html"
    assert mod.main([
        "--selection", str(paths["selection"]),
        "--state", str(paths["state"]),
        "--review", str(paths["review"]),
        "--output", str(output),
    ]) == 0
    assert output.read_bytes().startswith(b"<!doctype html>\n")
    captured = capsys.readouterr()
    assert captured.err == ""
    assert "sager=7 records=8 beslutninger=15" in captured.out
    assert "c3-review.html" in captured.out
    assert "html_sha256=" in captured.out
    assert hashes["review_sha256"] in captured.out
    assert "Syntetisk" not in captured.out
    assert fixtures.ATTACK_SENTINEL not in captured.out
    assert not list(tmp_path.glob(".c3-review.html.*.tmp"))


def test_cli_refuses_existing_output_without_changing_it(tmp_path):
    paths, _, _, _, _ = fixture_chain(tmp_path / "fixture")
    output = tmp_path / "c3-review.html"
    output.write_bytes(b"bevar mig")
    html_error(
        "C3_HTML_OUTPUT_EXISTS",
        lambda: mod.main([
            "--selection", str(paths["selection"]),
            "--state", str(paths["state"]),
            "--review", str(paths["review"]),
            "--output", str(output),
        ]))
    assert output.read_bytes() == b"bevar mig"
    assert not list(tmp_path.glob(".c3-review.html.*.tmp"))


def test_cli_removes_own_temp_file_when_atomic_publish_fails(
        tmp_path, monkeypatch):
    paths, _, _, _, _ = fixture_chain(tmp_path / "fixture")
    output = tmp_path / "c3-review.html"

    def fail_link(_source, _target):
        raise OSError("synthetic link failure")

    monkeypatch.setattr(mod.os, "link", fail_link)
    html_error(
        "C3_HTML_OUTPUT_WRITE_FAILED",
        lambda: mod.main([
            "--selection", str(paths["selection"]),
            "--state", str(paths["state"]),
            "--review", str(paths["review"]),
            "--output", str(output),
        ]))
    assert not output.exists()
    assert not list(tmp_path.glob(".c3-review.html.*.tmp"))


@pytest.mark.parametrize("arguments", [
    [],
    ["--selection", "a", "--state", "b", "--review", "c"],
    ["--selection", "a", "--state", "b", "--review", "c",
     "--output", "d", "--unknown", "e"],
])
def test_cli_accepts_only_the_four_locked_path_arguments(arguments):
    html_error("C3_HTML_ARGUMENTS_INVALID", lambda: mod.main(arguments))
