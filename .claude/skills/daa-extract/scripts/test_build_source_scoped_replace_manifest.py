"""Closed-schema tests for the source-scoped replace manifest compiler."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from build_source_scoped_replace_manifest import ManifestError, build_source_scoped_replace_manifest


SOURCE_ID = 77
PERSON_ID = 42
ELEMENT_ID = 9
RECORD_KEY = "1939:0001"
TEXT = "Et godkendt udkast."
TEXT_SHA256 = hashlib.sha256(TEXT.encode("utf-8")).hexdigest()
INPUT_SHA256 = "a" * 64
DRY_RUN_SHA256 = "b" * 64
OWNERSHIP_SHA256 = "c" * 64


def base_reports():
    dry_run = {
        "schema": "source-scoped-replace-dry-run-v1",
        "source_id": SOURCE_ID,
        "dry_run_sha256": DRY_RUN_SHA256,
        "records": [{
            "record_key": RECORD_KEY,
            "outcome": "entydig",
            "person_id": PERSON_ID,
            "element_id": ELEMENT_ID,
            "narrative_transition": "draft_created",
            "text": TEXT,
            "text_sha256": TEXT_SHA256,
            "expected_state_sha256": "d" * 64,
            "source_operation": {"action": "replace_owned_facts", "record_key": RECORD_KEY},
        }],
        "expected_counts": {"narrative_operations": 1, "source_operations": 1},
        "policy_decisions": {"new_records": [], "discontinued_records": []},
    }
    ownership = {
        "schema": "source-scoped-replace-ownership-v1",
        "source_id": SOURCE_ID,
        "ownership_sha256": OWNERSHIP_SHA256,
        "records": [{"record_key": RECORD_KEY, "owned": True}],
    }
    return dry_run, ownership


def manifest_bytes(manifest):
    return json.dumps(manifest, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def test_builds_closed_canonical_manifest():
    dry_run, ownership = base_reports()

    actual = build_source_scoped_replace_manifest(dry_run, ownership, INPUT_SHA256)

    assert set(actual) == {
        "schema", "source_id", "record_keys", "input_sha256", "dry_run_sha256",
        "ownership_sha256", "expected_counts", "policy_decisions", "narrative_operations",
        "source_operations",
    }
    assert actual["schema"] == "source-scoped-replace-v1"
    assert actual["record_keys"] == [RECORD_KEY]
    assert actual["narrative_operations"] == [{
        "element_id": ELEMENT_ID, "person_id": PERSON_ID, "source_id": SOURCE_ID,
        "record_key": RECORD_KEY, "text": TEXT, "text_sha256": TEXT_SHA256,
        "expected_state_sha256": "d" * 64,
    }]
    assert actual["source_operations"] == [{"action": "replace_owned_facts", "record_key": RECORD_KEY}]


@pytest.mark.parametrize("seed", ["1", "42"])
def test_manifest_bytes_are_deterministic_across_python_hash_seeds(seed):
    dry_run, ownership = base_reports()
    script = (
        "import json; from test_build_source_scoped_replace_manifest import base_reports, INPUT_SHA256; "
        "from build_source_scoped_replace_manifest import build_source_scoped_replace_manifest; "
        "d,o=base_reports(); print(json.dumps(build_source_scoped_replace_manifest(d,o,INPUT_SHA256),"
        "ensure_ascii=False,separators=(',',':')) )"
    )
    env = dict(os.environ, PYTHONHASHSEED=seed)
    output = subprocess.check_output([sys.executable, "-B", "-c", script], cwd=Path(__file__).parent,
                                     env=env, text=True).strip()
    assert output.encode("utf-8") == manifest_bytes(build_source_scoped_replace_manifest(dry_run, ownership, INPUT_SHA256))


@pytest.mark.parametrize("mutate", [
    lambda d, o: d.update({"dry_run_sha256": ""}),
    lambda d, o: o.update({"ownership_sha256": ""}),
    lambda d, o: d["records"].append(copy.deepcopy(d["records"][0])),
    lambda d, o: d["records"].__setitem__(0, dict(d["records"][0], outcome="tvetydig")),
    lambda d, o: d["records"].__setitem__(0, dict(d["records"][0], narrative_transition="published")),
    lambda d, o: d["records"].__setitem__(0, dict(d["records"][0], text_sha256="e" * 64)),
    lambda d, o: d["records"].__setitem__(0, dict(d["records"][0], unexpected=True)),
])
def test_rejects_invalid_or_open_record_inputs(mutate):
    dry_run, ownership = base_reports()
    mutate(dry_run, ownership)

    with pytest.raises(ManifestError):
        build_source_scoped_replace_manifest(dry_run, ownership, INPUT_SHA256)


def test_rejects_reordered_record_keys():
    dry_run, ownership = base_reports()
    extra = copy.deepcopy(dry_run["records"][0])
    extra["record_key"] = "1939:0000"
    extra["source_operation"] = {"action": "replace_owned_facts", "record_key": "1939:0000"}
    dry_run["records"].append(extra)
    ownership["records"].append({"record_key": "1939:0000", "owned": True})

    with pytest.raises(ManifestError, match="RECORD_KEYS"):
        build_source_scoped_replace_manifest(dry_run, ownership, INPUT_SHA256)


@pytest.mark.parametrize(("outcome", "decision", "error"), [
    ("new", {"record_key": RECORD_KEY, "mode": "wrong"}, "NEW_POLICY"),
    ("bortfalden", {"record_key": RECORD_KEY, "mode": "wrong"}, "DISCONTINUED_POLICY"),
])
def test_requires_exact_policy_allowlist_for_new_and_discontinued(outcome, decision, error):
    dry_run, ownership = base_reports()
    dry_run["records"][0]["outcome"] = outcome
    key = "new_records" if outcome == "new" else "discontinued_records"
    dry_run["policy_decisions"][key] = [decision]

    with pytest.raises(ManifestError, match=error):
        build_source_scoped_replace_manifest(dry_run, ownership, INPUT_SHA256)


def test_new_record_requires_create_staged_and_discontinued_is_report_only():
    dry_run, ownership = base_reports()
    dry_run["records"][0]["outcome"] = "new"
    dry_run["policy_decisions"]["new_records"] = [{"record_key": RECORD_KEY, "mode": "create_staged"}]
    new_manifest = build_source_scoped_replace_manifest(dry_run, ownership, INPUT_SHA256)
    assert new_manifest["narrative_operations"][0]["record_key"] == RECORD_KEY

    dry_run, ownership = base_reports()
    dry_run["records"][0]["outcome"] = "bortfalden"
    dry_run["policy_decisions"]["discontinued_records"] = [{"record_key": RECORD_KEY, "mode": "retain_report_only"}]
    dry_run["expected_counts"] = {"narrative_operations": 0, "source_operations": 0}
    manifest = build_source_scoped_replace_manifest(dry_run, ownership, INPUT_SHA256)
    assert manifest["narrative_operations"] == []
    assert manifest["source_operations"] == []
