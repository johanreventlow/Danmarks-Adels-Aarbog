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


def write_nonfinite_fixture(paths, selection, state, value):
    selection["cases"][0]["records"][0]["candidates"][0][
        "confidence"] = value
    selection_raw = encode_document(selection)
    selection_sha256 = hashlib.sha256(selection_raw).hexdigest()
    state["selection_sha256"] = selection_sha256
    state_raw = encode_document(state)
    state_sha256 = hashlib.sha256(state_raw).hexdigest()
    review_raw = fixtures.review_builder.render_review(
        selection, state, selection_sha256, state_sha256).encode("utf-8")
    paths["selection"].write_bytes(selection_raw)
    paths["state"].write_bytes(state_raw)
    paths["review"].write_bytes(review_raw)
    return selection_raw, state_raw, review_raw, fixtures.input_hashes(paths)


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
    records = [record for case in selection["cases"]
               for record in case["records"]]
    r03 = next(record for record in records if record["rid"] == "R03")
    r11 = next(record for record in records if record["rid"] == "R11")
    assert r03["pages"] == {"page_from": 603, "page_to": 604}
    assert r11["pages"] is None
    assert all(
        record["pages"] is None
        or str(record["pages"]["page_from"])
        not in {candidate["side"] for candidate in record["candidates"]}
        for record in records)
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
        ("identity:1017:1021", "UAFKLARET"),
        ("record:R40", "TIL 1017"),
        ("record:R15", "TIL 1021"),
    ]
    assert [slot["case_id"] for slot in slots[-3:]] == [
        "1017/1021", "1017/1021", "1017/1021"]
    assert slots[-3]["preferred_alias_person_id"] == 1021
    assert slots[-3]["preferred_canonical_person_id"] == 1017
    assert slots[0]["preferred_alias_person_id"] is None
    assert slots[0]["preferred_canonical_person_id"] is None


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


@pytest.mark.parametrize("alias_id,canonical_id", [
    (1017, 1017),
    (9999, 1017),
    (1021, None),
    (None, None),
])
def test_invalid_preferred_same_direction_is_terminal(
        tmp_path, monkeypatch, alias_id, canonical_id):
    paths, _, _, review_raw, hashes = fixture_chain(tmp_path)
    real_sequence = mod.build.review_sequence

    def invalid_sequence(selection_doc, state_doc):
        sequence = copy.deepcopy(real_sequence(selection_doc, state_doc))
        special = next(
            item for item in sequence
            if item.get("decision_id") == "identity:1017:1021")
        if alias_id is None:
            special.pop("preferred_alias_person_id", None)
        else:
            special["preferred_alias_person_id"] = alias_id
        if canonical_id is None:
            special.pop("preferred_canonical_person_id", None)
        else:
            special["preferred_canonical_person_id"] = canonical_id
        return sequence

    monkeypatch.setattr(mod.build, "review_sequence", invalid_sequence)
    html_error(
        "C3_HTML_SLOT_INVALID",
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
        "UAFKLARET", "TIL 1017", "TIL 1021",
    ]
    special_identity = payload["cases"][-1]["controls"][0]
    assert special_identity["preferred_alias_person_id"] == 1021
    assert special_identity["preferred_canonical_person_id"] == 1017
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


def test_client_uses_semantic_readable_context_without_json_surface(tmp_path):
    _, _, _, _, html = build_artifact(tmp_path)
    script, _ = extract_client_script(html, tmp_path)
    assert "JSON.stringify" not in script
    assert 'makeElement("pre"' not in script
    for semantic_class in (
            "comparison", "source-record", "source-text",
            "candidate-grid", "candidate-card", "candidate-text",
            "narrative-info", "identity-relations", "partner-warning"):
        assert semantic_class in script
    for readable_label in (
            "Kilderecord", "Kildetekst", "Side", "Kandidatpersoner",
            "Eksisterende narrativ", "Eksisterende identitetsrelationer",
            "Partnerkonflikter", "Ikke registreret"):
        assert readable_label in script


def test_client_renders_missing_values_explicitly(tmp_path):
    _, _, _, _, html = build_artifact(tmp_path)
    _, script_path = extract_client_script(html, tmp_path)
    result = run_client_function(
        script_path,
        "process.stdout.write([readableValue(null), readableValue(undefined), "
        "readableValue('')].join('|'));\n")
    assert result.stdout == (
        "Ikke registreret|Ikke registreret|Ikke registreret")


def test_client_formats_only_authoritative_record_pages(tmp_path):
    _, _, _, _, html = build_artifact(tmp_path)
    script, script_path = extract_client_script(html, tmp_path)
    formatter = re.search(
        r"function recordPage\(record\) \{(.*?)\n\}", script, re.DOTALL)
    assert formatter is not None
    assert "candidate" not in formatter.group(1)
    assert "record.pages" in formatter.group(1)
    result = run_client_function(
        script_path,
        "process.stdout.write(["
        "recordPage({pages:{page_from:603,page_to:603}}),"
        "recordPage({pages:{page_from:603,page_to:604}}),"
        "recordPage({pages:null}),"
        "recordPage({pages:{page_from:null,page_to:604}})"
        "].join('|'));\n")
    assert result.stdout == "603|603–604|Ikke registreret|Ikke registreret"


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


@pytest.mark.parametrize("value", [float("nan"), float("inf")])
def test_nonfinite_input_metadata_is_terminal(tmp_path, value):
    paths, selection, state, _, _ = fixture_chain(tmp_path)
    selection_raw, state_raw, review_raw, hashes = write_nonfinite_fixture(
        paths, selection, state, value)
    html_error(
        "C3_HTML_REVIEW_INVALID",
        lambda: mod.build_payload(
            selection_raw, state_raw, review_raw, hashes))


@pytest.mark.parametrize("value", [float("nan"), float("inf")])
def test_render_html_rejects_nonfinite_payload(tmp_path, value):
    html_error(
        "C3_HTML_PAYLOAD_INVALID",
        lambda: mod.render_html({"plausible_metadata": value}, b"review"))


@pytest.mark.parametrize("value", [float("nan"), float("inf")])
def test_cli_rejects_nonfinite_input_without_artifacts(tmp_path, value):
    paths, selection, state, _, _ = fixture_chain(tmp_path / "fixture")
    write_nonfinite_fixture(paths, selection, state, value)
    output = tmp_path / "c3-review.html"
    result = subprocess.run([
        "/usr/bin/python3", str(MODULE_PATH),
        "--selection", str(paths["selection"]),
        "--state", str(paths["state"]),
        "--review", str(paths["review"]),
        "--output", str(output),
    ], check=False, capture_output=True, text=True)
    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == "C3_HTML_REVIEW_INVALID\n"
    assert not output.exists()
    assert not list(tmp_path.glob(".c3-review.html.*.tmp"))


# ---------------------------------------------------------------------------
# Apply-tilstand: godkendelsesark for de fem `assign`-sager i det endelige
# C3 apply-manifest (Task 4). Bruger udelukkende syntetiske fixtures — ingen
# database, ingen ægte prosa.
# ---------------------------------------------------------------------------

def apply_error(expected, call):
    with pytest.raises(SystemExit) as caught:
        call()
    token = str(caught.value)
    assert token == expected
    assert token.startswith("C3_HTML_APPLY_")
    assert "Syntetisk" not in token
    assert fixtures.APPLY_ATTACK_SENTINEL not in token


def apply_manifest_raw(mutate=None):
    document = fixtures.apply_manifest_document()
    if mutate is not None:
        mutate(document)
        document.pop("canonical_content_sha256", None)
        document["canonical_content_sha256"] = fixtures.finalize_builder._sha(
            fixtures.finalize_builder._canonical_bytes(document))
    return fixtures.apply_manifest_bytes(document), document


def test_apply_fixture_has_five_assign_and_one_no_publication_event():
    raw, document = apply_manifest_raw()
    assert document["counts"] == {
        "cases": 5, "identity_events": 5, "assign_events": 5,
        "no_publication_events": 1, "events": 11,
    }
    events = [event for case in document["cases"] for event in case["events"]]
    assign = [event for event in events if event["action"] == "assign"]
    no_pub = [event for event in events if event["action"] == "no_publication"]
    assert len(assign) == 5
    assert len(no_pub) == 1
    assert fixtures.APPLY_ATTACK_SENTINEL in raw.decode("utf-8")


def test_apply_assign_events_are_sorted_by_element_id():
    raw, document = apply_manifest_raw()
    events = mod._apply_assign_events(document)
    assert len(events) == 5
    assert [event["element_id"] for event in events] == sorted(
        event["element_id"] for event in events)


def test_apply_text_bundle_sha256_ignores_preview_derived_drift():
    raw, document = apply_manifest_raw()
    events = mod._apply_assign_events(document)
    baseline = mod.apply_text_bundle_sha256(events)

    def drift_preview_only(doc):
        doc["database"]["database_name"] = "other_synthetic_db"
        doc["input_hashes"]["preview_raw_sha256"] = "f" * 64
        for case in doc["cases"]:
            for event in case["events"]:
                event["before_state"]["source_record"][
                    "verbatim_sha256"] = "9" * 64
                if event["action"] == "assign":
                    event["before_state"]["target_narrative"][
                        "old_sha256"] = None
                    event["before_state"]["target_narrative"][
                        "narrative_id"] = 999999
                    event["before_state"]["binding"]["status"] = (
                        "draft_same_record")
                    event["before_state"]["binding"]["binding_person_id"] = (
                        event["before_state"]["target_narrative"][
                            "person_id"])

    _, drifted_document = apply_manifest_raw(mutate=drift_preview_only)
    drifted_events = mod._apply_assign_events(drifted_document)
    assert mod.apply_text_bundle_sha256(drifted_events) == baseline


@pytest.mark.parametrize("mutate", [
    lambda doc: doc["cases"][0]["events"][0].__setitem__(
        "after_state",
        dict(doc["cases"][0]["events"][0]["after_state"],
             normalized_text=(
                 doc["cases"][0]["events"][0]["after_state"][
                     "normalized_text"] + " ÆNDRET"))),
    lambda doc: doc["cases"][0]["events"][0]["after_state"].__setitem__(
        "normalization_flags", list(reversed(
            doc["cases"][0]["events"][0]["after_state"][
                "normalization_flags"]))),
])
def test_apply_text_bundle_sha256_changes_with_candidate_derived_drift(
        mutate):
    raw, document = apply_manifest_raw()
    baseline = mod.apply_text_bundle_sha256(mod._apply_assign_events(document))
    _, drifted_document = apply_manifest_raw(mutate=mutate)
    drifted = mod.apply_text_bundle_sha256(
        mod._apply_assign_events(drifted_document))
    assert drifted != baseline


@pytest.mark.parametrize("mutate", [
    lambda doc: doc["cases"][0]["events"][0].__setitem__(
        "rid", doc["cases"][0]["events"][0]["rid"] + "-DRIFTED"),
    lambda doc: doc["cases"][0]["events"][0]["after_state"].__setitem__(
        "normalization_version", "narrative_norm_v2"),
])
def test_apply_text_bundle_sha256_is_sensitive_to_rid_and_normalization_version(
        mutate):
    """Pins the remaining two fields of the documented hash input set.

    `apply_text_bundle_sha256` is documented (its own docstring, and the
    Task 4 report) to bind exactly: element_id, rid, normalization_version,
    normalized_text, normalization_flags. The parametrized test above
    (`..._changes_with_candidate_derived_drift`) already proves
    normalized_text/normalization_flags sensitivity; this covers the
    other two so the full input set is regression-pinned, not just
    described in prose. If either mutation here stops changing the hash,
    a field silently fell out of the payload.
    """
    raw, document = apply_manifest_raw()
    baseline = mod.apply_text_bundle_sha256(mod._apply_assign_events(document))
    _, drifted_document = apply_manifest_raw(mutate=mutate)
    drifted = mod.apply_text_bundle_sha256(
        mod._apply_assign_events(drifted_document))
    assert drifted != baseline


def test_apply_text_bundle_sha256_binds_target_person_id_and_expected_narrative():
    """Følgeafgørelse 2026-08-23 — bruger, efter Task 4's review.

    En uafhængig kontrol viste, at `apply_text_bundle_sha256` som
    oprindeligt defineret (kun element_id/rid/normalization_version/
    normalized_text/normalization_flags) IKKE bandt `target_person_id`,
    `record_key` eller `expected_narrative`: to manifester med samme
    tekst men FORSKELLIGE personmål delte samme hash, og et fuldt
    godkendt ark for det ene validerede også rent mod det andet — se
    ledger for Task 4 (fix round 2). Brugeren har besluttet at udvide
    bundlen fremfor at stole på en udenomsystemisk manuel kontrol.

    Dette koster IKKE B1's rehearsal/prod-portabilitet: `target_person_id`,
    `record_key` og `expected_narrative` er alle kandidat-afledte
    (Task 1, databaseuafhængige — hele assign `after_state` kopieres
    direkte fra kandidatens `decision` i
    `finalize_c3_apply_manifest_1939_v50.py`), præcis som record-tekst og
    normalisering allerede er. Kun de reelt database-afledte felter
    (databasenavn, system identifier, `narrative_id`, `old_sha256`,
    bindings-status) forbliver uden for bundlen.

    This test now asserts the OPPOSITE of the previous
    "KNOWN_LIMITATION" version: mutating `target_person_id`,
    `record_key`, or a field inside `expected_narrative` MUST change
    `text_bundle_sha256`. If this assertion ever starts failing again,
    that is a regression of the target-person binding fix, not a test
    bug to "relax".
    """
    raw, document = apply_manifest_raw()
    baseline = mod.apply_text_bundle_sha256(mod._apply_assign_events(document))

    def drift_target(doc):
        event = doc["cases"][0]["events"][0]
        event["after_state"]["target_person_id"] = (
            event["after_state"]["target_person_id"] + 999)
        event["record_key"] = event["record_key"] + "-OTHER-TARGET"
        event["after_state"]["expected_narrative"]["citation_label"] = (
            event["after_state"]["expected_narrative"]["citation_label"]
            + " ANDET MAAL")

    _, drifted_document = apply_manifest_raw(mutate=drift_target)
    drifted = mod.apply_text_bundle_sha256(
        mod._apply_assign_events(drifted_document))
    # Discriminating check: prove the mutation actually landed (the
    # manifest's own canonical_content_sha256 differs), so an inequality
    # assertion on the bundle hash below cannot pass vacuously because
    # drift_target silently did nothing.
    assert (drifted_document["canonical_content_sha256"]
            != document["canonical_content_sha256"])
    assert drifted != baseline


@pytest.mark.parametrize("mutate", [
    lambda event: event["after_state"].__setitem__(
        "target_person_id", event["after_state"]["target_person_id"] + 1),
    lambda event: event.__setitem__(
        "record_key", event["record_key"] + "-DRIFT"),
    lambda event: event["after_state"]["expected_narrative"].__setitem__(
        "record_label", event["after_state"]["expected_narrative"][
            "record_label"] + "-DRIFT"),
    lambda event: event["after_state"]["expected_narrative"].__setitem__(
        "citation_label", event["after_state"]["expected_narrative"][
            "citation_label"] + " DRIFT"),
])
def test_apply_text_bundle_sha256_is_sensitive_to_each_target_field(mutate):
    """Regression-pins each of the three newly-bound fields individually.

    The combined test above mutates all three at once; this parametrized
    test proves each one alone is load-bearing, so a partial regression
    (e.g. `record_key` silently dropped from the payload again) cannot
    hide behind the other two still being bound.
    """
    raw, document = apply_manifest_raw()
    baseline = mod.apply_text_bundle_sha256(mod._apply_assign_events(document))

    def drift_one(doc):
        mutate(doc["cases"][0]["events"][0])

    _, drifted_document = apply_manifest_raw(mutate=drift_one)
    drifted = mod.apply_text_bundle_sha256(
        mod._apply_assign_events(drifted_document))
    assert (drifted_document["canonical_content_sha256"]
            != document["canonical_content_sha256"])
    assert drifted != baseline


def test_apply_approval_sheet_has_exact_locked_byte_sequence():
    raw, document = apply_manifest_raw()
    events = mod._apply_assign_events(document)
    text_bundle_sha256 = mod.apply_text_bundle_sha256(events)
    sheet_bytes, slots = mod.apply_approval_sheet(text_bundle_sha256, events)
    decoded = sheet_bytes.decode("utf-8")
    lines = decoded.splitlines(keepends=True)
    assert lines[0] == "# schema=1939-v50-c3-apply-approvals-v1\n"
    assert lines[1] == "# text_bundle_sha256={}\n".format(text_bundle_sha256)
    assert len(lines) == 7
    assert len(slots) == 5
    assert [slot["element_id"] for slot in slots] == sorted(
        event["element_id"] for event in events)
    for index, slot in enumerate(slots):
        assert lines[2 + index] == "[UAFKLARET] approve:{}\n".format(
            slot["element_id"])
        assert sheet_bytes[slot["start"]:slot["end"]].decode(
            "utf-8") == "UAFKLARET"
        assert slot["default_token"] == "UAFKLARET"
    assert all(slots[index]["end"] <= slots[index + 1]["start"]
               for index in range(4))


def test_apply_approval_sheet_rejects_wrong_event_count():
    raw, document = apply_manifest_raw()
    events = mod._apply_assign_events(document)
    apply_error(
        "C3_HTML_APPLY_COUNT_INVALID",
        lambda: mod.apply_approval_sheet("a" * 64, events[:-1]))


def test_apply_approval_sheet_rejects_invalid_bundle_hash():
    raw, document = apply_manifest_raw()
    events = mod._apply_assign_events(document)
    apply_error(
        "C3_HTML_APPLY_HASH_INVALID",
        lambda: mod.apply_approval_sheet("not-hex", events))


def build_apply_artifact(mutate=None):
    raw, _document = apply_manifest_raw(mutate=mutate)
    payload, sheet_bytes = mod.build_apply_payload(raw)
    html = mod.render_apply_html(payload, sheet_bytes)
    return raw, payload, sheet_bytes, html


def test_apply_payload_has_five_cards_matching_slot_order():
    _, payload, _, _ = build_apply_artifact()
    assert payload["counts"] == {"decisions": 5}
    assert len(payload["cards"]) == 5
    assert len(payload["slots"]) == 5
    assert [card["element_id"] for card in payload["cards"]] == [
        slot["element_id"] for slot in payload["slots"]]
    assert payload["vocabulary"] == {
        "approval_actions": ["UAFKLARET", "GODKENDT"]}
    assert re.fullmatch(r"[0-9a-f]{64}", payload["text_bundle_sha256"])


def test_apply_payload_card_carries_readable_before_after_fields():
    _, payload, _, _ = build_apply_artifact()
    first = payload["cards"][0]
    assert set(first) == {
        "element_id", "case_id", "rid", "record_key", "before", "after"}
    assert set(first["before"]) == {
        "source_record", "binding", "target_narrative"}
    assert set(first["after"]) == {
        "target_person_id", "raw_sha256", "normalized_text",
        "normalized_sha256", "normalization_version",
        "normalization_flags", "expected_narrative"}
    assert fixtures.APPLY_ATTACK_SENTINEL in first["after"]["normalized_text"]


@pytest.mark.parametrize("mutate,expected", [
    (lambda doc: doc.pop("database"), "C3_HTML_APPLY_MANIFEST_INVALID"),
    (lambda doc: doc["counts"].__setitem__("assign_events", 4),
     "C3_HTML_APPLY_COUNT_INVALID"),
    (lambda doc: doc["cases"][0]["events"][0]["before_state"][
        "source_record"].__setitem__("side", 7),
     "C3_HTML_APPLY_MANIFEST_INVALID"),
    (lambda doc: doc["cases"][0]["events"][0]["after_state"].__setitem__(
        "normalization_flags", "not-a-list"),
     "C3_HTML_APPLY_MANIFEST_INVALID"),
])
def test_build_apply_payload_rejects_structural_drift(mutate, expected):
    document = fixtures.apply_manifest_document()
    mutate(document)
    raw = fixtures.apply_manifest_bytes(document)
    apply_error(expected, lambda: mod.build_apply_payload(raw))


def test_build_apply_payload_rejects_self_hash_tamper():
    document = fixtures.apply_manifest_document()
    document["canonical_content_sha256"] = "0" * 64
    raw = fixtures.apply_manifest_bytes(document)
    apply_error(
        "C3_HTML_APPLY_MANIFEST_HASH_MISMATCH",
        lambda: mod.build_apply_payload(raw))


def test_build_apply_payload_rejects_non_bytes_and_invalid_json():
    apply_error(
        "C3_HTML_APPLY_MANIFEST_INVALID",
        lambda: mod.build_apply_payload("not-bytes"))
    apply_error(
        "C3_HTML_APPLY_MANIFEST_INVALID",
        lambda: mod.build_apply_payload(b"not json"))


def test_apply_html_keeps_all_untrusted_data_behind_base64_boundary():
    _, payload, sheet_bytes, html = build_apply_artifact()
    decoded = html.decode("utf-8")
    blocks = dict(re.findall(
        r'<div id="(c3-apply-(?:payload|sheet))" hidden>'
        r'([A-Za-z0-9_=-]+)</div>',
        decoded))
    assert set(blocks) == {"c3-apply-payload", "c3-apply-sheet"}
    assert json.loads(base64.urlsafe_b64decode(
        blocks["c3-apply-payload"]).decode("utf-8")) == payload
    assert base64.urlsafe_b64decode(blocks["c3-apply-sheet"]) == sheet_bytes
    assert fixtures.APPLY_ATTACK_SENTINEL not in decoded
    assert sheet_bytes.decode("utf-8") not in decoded


def test_apply_generated_client_is_valid_javascript_and_has_no_forbidden_path(
        tmp_path):
    _, _, _, html = build_apply_artifact()
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
        r"JSON\.stringify",
    ]
    assert not any(re.search(pattern, script, re.IGNORECASE)
                   for pattern in forbidden)
    document = html.decode("utf-8")
    assert not re.search(r"<[^>]+\son[a-z]+\s*=", document, re.IGNORECASE)
    assert not re.search(r"<(?:script|link|img)[^>]+\s(?:src|href)\s*=",
                         document, re.IGNORECASE)


def test_apply_client_unchanged_export_is_byte_identical(tmp_path):
    _, payload, sheet_bytes, html = build_apply_artifact()
    _, script_path = extract_client_script(html, tmp_path)
    slots_json = json.dumps([
        dict(slot, token=slot["default_token"])
        for slot in payload["slots"]], ensure_ascii=True)
    result = run_client_function(
        script_path,
        "const source = decodeBase64Url({});\n"
        "const result = replaceTokenBytes(source, {});\n"
        "process.stdout.write(encodeBase64Url(result));\n".format(
            json.dumps(base64.urlsafe_b64encode(sheet_bytes).decode("ascii")),
            slots_json))
    assert base64.urlsafe_b64decode(result.stdout) == sheet_bytes


def test_apply_client_length_changing_export_replaces_bytes_exactly(
        tmp_path):
    _, payload, sheet_bytes, html = build_apply_artifact()
    _, script_path = extract_client_script(html, tmp_path)
    tokens = ["GODKENDT" if index == 0 else "UAFKLARET"
              for index in range(len(payload["slots"]))]
    slots_json = json.dumps([
        dict(slot, token=tokens[index])
        for index, slot in enumerate(payload["slots"])], ensure_ascii=True)
    result = run_client_function(
        script_path,
        "const source = decodeBase64Url({});\n"
        "const result = replaceTokenBytes(source, {});\n"
        "process.stdout.write(encodeBase64Url(result));\n".format(
            json.dumps(base64.urlsafe_b64encode(sheet_bytes).decode("ascii")),
            slots_json))
    exported = base64.urlsafe_b64decode(result.stdout)
    assert exported != sheet_bytes
    decoded = exported.decode("utf-8")
    lines = decoded.splitlines(keepends=True)
    assert lines[2] == "[GODKENDT] approve:{}\n".format(
        payload["slots"][0]["element_id"])
    for index in range(1, len(payload["slots"])):
        assert lines[2 + index] == "[UAFKLARET] approve:{}\n".format(
            payload["slots"][index]["element_id"])


def apply_fixture_chain(tmp_path):
    paths = fixtures.write_apply_fixture(tmp_path)
    manifest_raw = paths["manifest"].read_bytes()
    return paths, manifest_raw


def test_apply_cli_publishes_one_self_contained_html_and_safe_metadata(
        tmp_path, capsys):
    fixture_dir = tmp_path / "fixture"
    paths, manifest_raw = apply_fixture_chain(fixture_dir)
    output = tmp_path / "c3-apply.html"
    assert mod.main([
        "--mode", "apply",
        "--manifest", str(paths["manifest"]),
        "--output", str(output),
    ]) == 0
    assert output.read_bytes().startswith(b"<!doctype html>\n")
    captured = capsys.readouterr()
    assert captured.err == ""
    assert "beslutninger=5" in captured.out
    assert "c3-apply.html" in captured.out
    assert "text_bundle_sha256=" in captured.out
    assert "html_sha256=" in captured.out
    assert "Syntetisk" not in captured.out
    assert fixtures.APPLY_ATTACK_SENTINEL not in captured.out
    assert not list(tmp_path.glob(".c3-apply.html.*.tmp"))


def test_apply_cli_refuses_existing_output_without_changing_it(tmp_path):
    paths, _ = apply_fixture_chain(tmp_path / "fixture")
    output = tmp_path / "c3-apply.html"
    output.write_bytes(b"bevar mig")
    html_error(
        "C3_HTML_OUTPUT_EXISTS",
        lambda: mod.main([
            "--mode", "apply",
            "--manifest", str(paths["manifest"]),
            "--output", str(output),
        ]))
    assert output.read_bytes() == b"bevar mig"


@pytest.mark.parametrize("arguments", [
    ["--mode", "apply"],
    ["--mode", "apply", "--manifest", "a"],
    ["--mode", "apply", "--manifest", "a", "--output", "b", "--review", "c"],
    ["--mode", "bogus", "--manifest", "a", "--output", "b"],
])
def test_apply_cli_accepts_only_the_locked_apply_arguments(arguments):
    html_error("C3_HTML_ARGUMENTS_INVALID", lambda: mod.main(arguments))


def _extract_js_function(script, name):
    """Udtræk en JS-funktionskrop via akkolade-optælling (ikke regex-‑
    grådighed, som kan stoppe ved en indlejret ``}``)."""
    start = script.index("function " + name + "(")
    open_index = script.index("{", start)
    depth = 0
    index = open_index
    while True:
        if script[index] == "{":
            depth += 1
        elif script[index] == "}":
            depth -= 1
            if depth == 0:
                break
        index += 1
    return script[start:index + 1]


def test_apply_client_shares_the_same_helper_bodies_as_review_client():
    """Den sikkerhedsbærende byte-erstatning (replaceTokenBytes) og de
    øvrige DOM-hjælpefunktioner må IKKE genimplementeres uafhængigt for
    apply-tilstanden — det var C0-efterkørslens parkerede fejl. Eneste
    tilladte forskel er apply-scriptets egen fejl-token-navnerum
    (``C3_HTML_APPLY_EXPORT_INVALID`` i stedet for
    ``C3_HTML_EXPORT_INVALID``), som normaliseres væk før sammenligning."""
    shared_names = [
        "decodeBase64Url", "encodeBase64Url", "replaceTokenBytes",
        "makeElement", "makeSelect", "readableValue", "appendLabelledValue",
    ]
    for name in shared_names:
        review_body = _extract_js_function(mod.CLIENT_SCRIPT, name)
        apply_body = _extract_js_function(mod.CLIENT_APPLY_SCRIPT, name)
        normalized_apply_body = apply_body.replace(
            "C3_HTML_APPLY_EXPORT_INVALID", "C3_HTML_EXPORT_INVALID")
        assert normalized_apply_body == review_body, name


def test_review_mode_cli_is_unaffected_by_explicit_mode_flag(tmp_path):
    paths, _, _, _, hashes = fixture_chain(tmp_path / "fixture")
    output = tmp_path / "c3-review.html"
    assert mod.main([
        "--mode", "review",
        "--selection", str(paths["selection"]),
        "--state", str(paths["state"]),
        "--review", str(paths["review"]),
        "--output", str(output),
    ]) == 0
    assert output.read_bytes().startswith(b"<!doctype html>\n")
