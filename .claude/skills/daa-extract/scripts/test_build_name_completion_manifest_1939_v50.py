from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from build_name_completion_manifest_1939_v50 import (
    SOURCE_MANIFEST_BYTES_SHA256,
    SOURCE_MANIFEST_CONTENT_SHA256,
    ManifestError,
    artifact_sha,
    build_manifest,
    canonical_sha,
)

LOCKED_ROWS = (
    ("record-3766faae-ae21-412a-8cfb-745a19ac77f0", 1846, "Ditlev", 503),
    ("record-43d4974a-0532-421d-a3fb-8e7c575a67e7", 1847, "Gerhard (Gherardus de Reventlow)", 506),
    ("record-80180a6e-2cc6-4968-81ca-004b6662d8ce", 1848, "Henning", 506),
    ("record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422", 1849, "Henning Reventlow", 508),
    ("record-8f346104-cf3c-465f-bfa3-efb78be436b2", 1850, "Iven (Ywanus de Reuentlo)", 506),
    ("record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58", 1851, "Henning", 508),
    ("record-b626f5ff-f2fb-4061-bfce-988dbddec846", 1852, "Henrik", 506),
    ("record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d", 1853, "Margrethe", 517),
)
LOCKED_MAP = {key: (person, name, page) for key, person, name, page in LOCKED_ROWS}


def _production_inputs():
    creates = []
    audits = []
    for key, person_id, name, page in LOCKED_ROWS:
        text = f"{name}, source text for {key}."
        payload = {
            "element_id": f"person-create:{key}",
            "source_record_key": key,
            "source_id": 3,
            "edition": "1939",
            "source_persona_id": f"persona-{person_id}",
            "name": name,
            "source_span": {"char_from": person_id, "char_to": person_id + 10},
            "page_evidence": {"page_from": page, "page_to": page},
            "verbatim_text": text,
            "verbatim_sha256": hashlib.sha256(text.encode()).hexdigest(),
            "staged": True,
            "facts": [],
            "relations": [],
            "families": [],
        }
        creates.append(payload)
        audits.append({
            "person_id": person_id,
            "source_record_key": key,
            "source_persona_id": payload["source_persona_id"],
            "name": name,
            "page": page,
            "verbatim_text": text,
            "staged": True,
            "name_fact_count": 0,
        })
    manifest_path = Path(__file__).parents[4] / "work/task25-1939-v50-production-writer/production-write-manifest-v1.json"
    production_manifest = json.loads(manifest_path.read_text())
    create_by_key = {row["source_record_key"]: row for row in production_manifest["person_creates"]}
    for audit in audits:
        source = create_by_key[audit["source_record_key"]]
        audit["source_persona_id"] = source["source_persona_id"]
        audit["verbatim_text"] = source["verbatim_text"]
        audit["page"] = source["page_evidence"]["page_from"]
    production_apply = {
        "mode": "apply",
        "status": "finalized",
        "committed": True,
        "person_id_map": {key: binding[0] for key, binding in LOCKED_MAP.items()},
    }
    post_apply_audit = {
        "schema_version": "1939-v50-post-apply-audit-v1",
        "batch_id": "560c39f8-5c87-4c0d-a768-025d97fa2974",
        "rows": audits,
    }
    return production_manifest, production_apply, post_apply_audit


def production_inputs():
    return copy.deepcopy(_production_inputs())


def production_hashes():
    return [SOURCE_MANIFEST_BYTES_SHA256, artifact_sha(production_inputs()[1]), artifact_sha(production_inputs()[2])]


def cli_hashes(paths):
    return [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]


def hash_inputs(values):
    return [artifact_sha(value) for value in values]


def mutate_production_inputs(mutation):
    values = list(production_inputs())
    manifest, apply, audit = values
    if mutation == "wrong_batch":
        manifest["batch_id"] = "wrong"
    elif mutation == "wrong_person":
        apply["person_id_map"][LOCKED_ROWS[0][0]] = 9999
    elif mutation == "wrong_record":
        audit["rows"][0]["source_record_key"] = "record-wrong"
    elif mutation == "wrong_name":
        manifest["person_creates"][0]["name"] = "Wrong"
    elif mutation == "wrong_page":
        audit["rows"][0]["page"] = 999
    elif mutation == "wrong_text":
        audit["rows"][0]["verbatim_text"] = "drift"
    elif mutation == "wrong_persona":
        audit["rows"][0]["source_persona_id"] = "persona-wrong"
    elif mutation == "duplicate_person":
        apply["person_id_map"][LOCKED_ROWS[1][0]] = 1846
    elif mutation == "missing_operation":
        del manifest["person_creates"][-1]
        del audit["rows"][-1]
        del apply["person_id_map"][LOCKED_ROWS[-1][0]]
    elif mutation == "unknown_field":
        manifest["person_creates"][0]["unexpected"] = True
    elif mutation == "reordered_apply_map":
        apply["person_id_map"] = dict(reversed(list(apply["person_id_map"].items())))
    else:
        raise AssertionError(mutation)
    return tuple(values)


def test_builds_exact_eight_source_bound_name_operations():
    out = build_manifest(*production_inputs(), input_hashes=production_hashes())
    assert out["schema_version"] == "1939-v50-name-completion-manifest-v1"
    assert out["counts"] == {"name_completions": 8, "operations": 8}
    assert [x["person_id"] for x in out["operations"]] == list(range(1846, 1854))
    assert out["operations"][0]["name"] == "Ditlev"
    assert out["operations"][-1]["name"] == "Margrethe"
    assert out["expected_changes"] == {
        "facts_created": 8, "assertions_created": 8,
        "citations_created": 8, "conclusions_created": 8,
        "persons_created": 0, "persons_activated": 0,
        "relations_changed": 0, "families_changed": 0,
    }


@pytest.mark.parametrize("mutation", [
    "wrong_batch", "wrong_person", "wrong_record", "wrong_name",
    "wrong_page", "wrong_text", "wrong_persona", "duplicate_person",
    "missing_operation", "unknown_field", "reordered_apply_map",
])
def test_rejects_locked_universe_drift(mutation):
    inputs = mutate_production_inputs(mutation)
    with pytest.raises(ManifestError):
        build_manifest(*inputs, input_hashes=hash_inputs(inputs))


def test_payload_hash_is_canonical_and_output_flags_are_closed():
    out = build_manifest(*production_inputs(), input_hashes=production_hashes())
    first = out["operations"][0]
    assert first["source_payload_sha256"] == canonical_sha(
        _production_inputs()[0]["person_creates"][0]
    )
    assert out["production_authorized"] is False
    assert out["cutover_authorized"] is False


def test_subprocess_builds_are_byte_identical_across_hash_seeds(tmp_path):
    values = production_inputs()
    paths = []
    for index, value in enumerate(values):
        path = tmp_path / f"input-{index}.json"
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
        paths.append(path)
    outputs = []
    module = Path(__file__).with_name("build_name_completion_manifest_1939_v50.py")
    for seed in ("1", "987654"):
        output = tmp_path / f"out-{seed}.json"
        command = [sys.executable, str(module)]
        for label, path, digest in zip(("production-manifest", "production-apply", "post-apply-audit"), paths, cli_hashes(paths)):
            command.extend([f"--{label}", str(path), f"--{label}-sha256", digest])
        command.extend(["--output", str(output)])
        subprocess.run(command, check=True, env={**os.environ, "PYTHONHASHSEED": seed})
        outputs.append(output.read_bytes())
    assert outputs[0] == outputs[1]


def test_cli_refuses_existing_output_path(tmp_path):
    values = production_inputs()
    paths = []
    for index, value in enumerate(values):
        path = tmp_path / f"input-{index}.json"
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
        paths.append(path)
    output = tmp_path / "existing.json"
    output.write_text("sentinel")
    module = Path(__file__).with_name("build_name_completion_manifest_1939_v50.py")
    command = [sys.executable, str(module)]
    for label, path, digest in zip(("production-manifest", "production-apply", "post-apply-audit"), paths, cli_hashes(paths)):
        command.extend([f"--{label}", str(path), f"--{label}-sha256", digest])
    command.extend(["--output", str(output)])
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode != 0
    assert "OUTPUT_EXISTS" in result.stderr
    assert output.read_text() == "sentinel"


@pytest.mark.parametrize("attack", [
    "mutated_manifest_rehashed", "missing_persona", "null_persona",
    "missing_span", "malformed_span", "nonpositive_span",
    "unknown_manifest_field", "reversed_create_order", "reversed_audit_order", "unknown_audit_row_field",
])
def test_rejects_additional_closed_boundary_attacks(attack):
    values = list(production_inputs())
    if attack == "mutated_manifest_rehashed":
        values[0]["person_creates"][0]["name"] = "Attacker"
    elif attack == "missing_persona":
        del values[0]["person_creates"][0]["source_persona_id"]
    elif attack == "null_persona":
        values[0]["person_creates"][0]["source_persona_id"] = None
    elif attack == "missing_span":
        del values[0]["person_creates"][0]["source_span"]
    elif attack == "malformed_span":
        values[0]["person_creates"][0]["source_span"] = {"char_from": 1}
    elif attack == "nonpositive_span":
        values[0]["person_creates"][0]["source_span"] = {"char_from": 0, "char_to": 0}
    elif attack == "unknown_manifest_field":
        values[0]["unknown"] = True
    elif attack == "reversed_create_order":
        values[0]["person_creates"].reverse()
    elif attack == "reversed_audit_order":
        values[2]["rows"].reverse()
    elif attack == "unknown_audit_row_field":
        values[2]["rows"][0]["unexpected"] = True
    with pytest.raises(ManifestError):
        build_manifest(*values, input_hashes=hash_inputs(values))


def test_cli_accepts_nonpreferred_json_whitespace_with_raw_hash(tmp_path):
    values = production_inputs()
    paths, hashes = [], []
    for index, value in enumerate(values):
        path = tmp_path / f"input-{index}.json"
        raw = (Path(__file__).parents[4] / "work/task25-1939-v50-production-writer/production-write-manifest-v1.json").read_bytes() if index == 0 else json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode() + b"\n"
        path.write_bytes(raw)
        paths.append(path)
        hashes.append(hashlib.sha256(raw).hexdigest())
    output = tmp_path / "out.json"
    module = Path(__file__).with_name("build_name_completion_manifest_1939_v50.py")
    command = [sys.executable, str(module)]
    for label, path, digest in zip(("production-manifest", "production-apply", "post-apply-audit"), paths, hashes):
        command.extend([f"--{label}", str(path), f"--{label}-sha256", digest])
    command.extend(["--output", str(output)])
    subprocess.run(command, check=True)


def test_cli_rejects_byte_different_semantically_identical_source_manifest(tmp_path):
    values = production_inputs()
    paths = []
    for index, value in enumerate(values):
        path = tmp_path / f"input-{index}.json"
        raw = json.dumps(value, ensure_ascii=False, indent=2).encode() + b" \n"
        path.write_bytes(raw)
        paths.append(path)
    output = tmp_path / "out.json"
    module = Path(__file__).with_name("build_name_completion_manifest_1939_v50.py")
    command = [sys.executable, str(module)]
    for label, path, digest in zip(("production-manifest", "production-apply", "post-apply-audit"), paths, cli_hashes(paths)):
        command.extend([f"--{label}", str(path), f"--{label}-sha256", digest])
    command.extend(["--output", str(output)])
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode != 0
    assert "SOURCE_MANIFEST_BYTES_INVALID" in result.stderr


def test_rejects_consistently_mutated_source_manifest_by_content_closure():
    values = list(production_inputs())
    values[0]["person_creates"][0]["source_persona_id"] = "persona-attacker"
    values[2]["rows"][0]["source_persona_id"] = "persona-attacker"
    with pytest.raises(ManifestError):
        build_manifest(*values, input_hashes=[SOURCE_MANIFEST_BYTES_SHA256, *hash_inputs(values)[1:]])


@pytest.mark.parametrize("value", [True, False])
def test_rejects_boolean_span_coordinates(value):
    values = list(production_inputs())
    values[0]["person_creates"][0]["source_span"]["char_from"] = value
    with pytest.raises(ManifestError, match="NAME_COMPLETION_SOURCE_EVIDENCE_INVALID"):
        build_manifest(*values, input_hashes=[SOURCE_MANIFEST_BYTES_SHA256, *hash_inputs(values)[1:]])
