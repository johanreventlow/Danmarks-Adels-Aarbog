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
    PRODUCTION_BINDINGS,
    ManifestError,
    artifact_sha,
    build_manifest,
    canonical_sha,
)


def _production_inputs():
    creates = []
    audits = []
    for key, (person_id, name, page) in PRODUCTION_BINDINGS.items():
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
    production_manifest = {
        "schema_version": "1939-v50-production-write-manifest-v1",
        "batch_id": "560c39f8-5c87-4c0d-a768-025d97fa2974",
        "person_creates": creates,
    }
    production_apply = {
        "schema_version": "1939-v50-production-apply-result-v1",
        "batch_id": "560c39f8-5c87-4c0d-a768-025d97fa2974",
        "status": "finalized",
        "committed": True,
        "person_id_map": {key: binding[0] for key, binding in PRODUCTION_BINDINGS.items()},
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
    return [artifact_sha(value) for value in production_inputs()]


def hash_inputs(values):
    return [artifact_sha(value) for value in values]


def mutate_production_inputs(mutation):
    values = list(production_inputs())
    manifest, apply, audit = values
    if mutation == "wrong_batch":
        manifest["batch_id"] = "wrong"
    elif mutation == "wrong_person":
        apply["person_id_map"][next(iter(PRODUCTION_BINDINGS))] = 9999
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
        apply["person_id_map"][list(PRODUCTION_BINDINGS)[1]] = 1846
    elif mutation == "missing_operation":
        del manifest["person_creates"][-1]
        del audit["rows"][-1]
        del apply["person_id_map"][list(PRODUCTION_BINDINGS)[-1]]
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
        for label, path, digest in zip(("production-manifest", "production-apply", "post-apply-audit"), paths, production_hashes()):
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
    for label, path, digest in zip(("production-manifest", "production-apply", "post-apply-audit"), paths, production_hashes()):
        command.extend([f"--{label}", str(path), f"--{label}-sha256", digest])
    command.extend(["--output", str(output)])
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode != 0
    assert "OUTPUT_EXISTS" in result.stderr
    assert output.read_text() == "sentinel"
