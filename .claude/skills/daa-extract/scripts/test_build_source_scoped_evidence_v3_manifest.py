from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest


SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

from build_source_scoped_evidence_v3_manifest import (  # noqa: E402
    RepositoryWriterSnapshotError,
    _in_scope,
    build_manifest,
    build_repository_writer_snapshot,
    parse_manifest_raw,
    semantic_hash,
)


def git(root: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)


def commit(root: Path, path: str, text: str, message: str) -> None:
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)
    git(root, "add", path)
    git(root, "commit", "-m", message)


def initialized_repo(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    root.mkdir()
    git(root, "init")
    git(root, "config", "user.email", "fixture@example.invalid")
    git(root, "config", "user.name", "Fixture")
    commit(root, "R/reader.R", "invisible(NULL)\n", "baseline")
    return root


def test_unclassified_direct_model_writer_is_rejected(tmp_path: Path) -> None:
    root = initialized_repo(tmp_path)
    before = build_repository_writer_snapshot(root)

    commit(
        root,
        "R/new_writer.R",
        "DBI::dbExecute(con, 'INSERT INTO fact DEFAULT VALUES')\n",
        "new writer",
    )
    with pytest.raises(RepositoryWriterSnapshotError, match="SOURCE_SCOPED_EVIDENCE_REPOSITORY_WRITER_UNCLASSIFIED"):
        build_repository_writer_snapshot(root)


def test_changed_classified_root_sql_writer_requires_reclassification(tmp_path: Path) -> None:
    root = initialized_repo(tmp_path)
    before = build_repository_writer_snapshot(root)

    commit(
        root,
        "schema.sql",
        "INSERT INTO fact DEFAULT VALUES;\nINSERT INTO assertion DEFAULT VALUES;\nINSERT INTO citation DEFAULT VALUES;\n",
        "root sql writer",
    )
    with pytest.raises(RepositoryWriterSnapshotError, match="SOURCE_SCOPED_EVIDENCE_REPOSITORY_RECLASSIFICATION_REQUIRED"):
        build_repository_writer_snapshot(root)


def test_artifact_snapshot_uses_head_not_untracked_or_index(tmp_path: Path) -> None:
    root = initialized_repo(tmp_path)
    baseline = build_repository_writer_snapshot(root)
    (root / "R" / "untracked_writer.R").write_text(
        "DBI::dbExecute(con, 'DELETE FROM fact')\n"
    )
    assert build_repository_writer_snapshot(root) == baseline


def test_current_committed_writer_inventory_builds() -> None:
    """Every classified writer in the committed repository is reclassified."""
    repo_root = SCRIPTS.parents[3]

    snapshot = build_repository_writer_snapshot(repo_root)

    expected_tree_id = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=repo_root, text=True
    ).strip()
    assert snapshot["repository_tree_id"] == expected_tree_id
    assert snapshot["entries"]


def test_unknown_dynamic_sql_writer_is_rejected(tmp_path: Path) -> None:
    root = initialized_repo(tmp_path)
    commit(
        root,
        "R/dynamic_writer.R",
        "DBI::dbExecute(con, paste0('INSERT INTO ', target, ' DEFAULT VALUES'))\n",
        "dynamic writer",
    )
    with pytest.raises(RepositoryWriterSnapshotError, match="SOURCE_SCOPED_EVIDENCE_REPOSITORY_WRITER_UNCLASSIFIED"):
        build_repository_writer_snapshot(root)


def test_model_dml_without_a_local_db_api_is_a_writer_route(tmp_path: Path) -> None:
    root = initialized_repo(tmp_path)
    commit(
        root,
        "R/wrapper_writer.R",
        "query <- 'INSERT INTO public.fact DEFAULT VALUES'\nshared_execute(con, query)\n",
        "wrapper writer",
    )
    with pytest.raises(RepositoryWriterSnapshotError, match="SOURCE_SCOPED_EVIDENCE_REPOSITORY_WRITER_UNCLASSIFIED"):
        build_repository_writer_snapshot(root)


def test_changed_dynamic_sql_writer_requires_reclassification(tmp_path: Path) -> None:
    root = initialized_repo(tmp_path)
    commit(
        root,
        "R/update-2018-narratives.R",
        "# assertion\nDBI::dbExecute(con, paste0('UPDATE fact SET value = value'))\n",
        "classified dynamic writer",
    )
    with pytest.raises(RepositoryWriterSnapshotError, match="SOURCE_SCOPED_EVIDENCE_REPOSITORY_RECLASSIFICATION_REQUIRED"):
        build_repository_writer_snapshot(root)


def test_new_dynamic_sql_in_a_non_dynamic_classified_entrypoint_is_rejected(tmp_path: Path) -> None:
    root = initialized_repo(tmp_path)
    commit(
        root,
        "schema.sql",
        "INSERT INTO fact DEFAULT VALUES;\nINSERT INTO assertion DEFAULT VALUES;\n"
        "INSERT INTO citation DEFAULT VALUES;\nSELECT paste0('unexpected');\n",
        "new dynamic schema sql",
    )
    with pytest.raises(RepositoryWriterSnapshotError, match="SOURCE_SCOPED_EVIDENCE_REPOSITORY_RECLASSIFICATION_REQUIRED"):
        build_repository_writer_snapshot(root)


def test_protected_work_tree_is_not_an_entrypoint_scope() -> None:
    assert _in_scope("work/protected/extraction.R") is False


def test_artifact_entries_have_only_the_authoritative_six_fields(tmp_path: Path) -> None:
    snapshot = build_repository_writer_snapshot(initialized_repo(tmp_path))
    assert all(set(entry) == {
        "path", "blob_sha256", "language", "writer_class", "allowed_db_api", "model_targets"
    } for entry in snapshot["entries"])


def canonical_desired_chain() -> dict[str, object]:
    return {
        "schema": "source-scoped-evidence-v3-desired-chain-v1",
        "members": [
            {
                "member_kind": "fact",
                "member_key": "fact:1",
                "subjekt_type": "person",
                "subjekt_id": 153,
                "faktatype": "navn",
                "sted_id": None,
            },
            {
                "member_kind": "assertion",
                "member_key": "assertion:1",
                "target_type": "fact",
                "target_member_key": "fact:1",
                "vaerdi_tekst": "Example Person",
                "objekt_type": None,
                "objekt_id": None,
                "date_min": None,
                "date_max": None,
                "date_qualifier": None,
                "date_certainty": None,
                "date_raw": None,
                "calendar": "gregoriansk",
                "uforanderlig": True,
            },
            {
                "member_kind": "citation",
                "member_key": "citation:1",
                "assertion_member_key": "assertion:1",
                "source_id": 153,
                "side": "p. 1",
                "citat_tekst": "Example citation",
                "citat_dato": None,
                "kvalitet": "primær",
            },
        ],
    }


def desired_chain_hash_for(chain: dict[str, object]) -> str:
    return hashlib.sha256(
        json.dumps(chain, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()


def desired_chain_hash() -> str:
    return desired_chain_hash_for(canonical_desired_chain())


def source_operation(operation: str = "create_chain") -> dict[str, object]:
    chain = canonical_desired_chain()
    return {
        "element_id": "evidence:one",
        "operation": operation,
        "chain_key": "f76b8207f2faf5da65cc85749d5ecc7e2229f1e1cb77e3a3caf467580ea60cb2",
        "source_record_key": "record:one",
        "source_persona_id": "00000000-0000-0000-0000-000000000153",
        "identity_event_id": "00000000-0000-0000-0000-000000000154",
        "person_id": 153,
        "prestate_sha256": "b" * 64,
        "desired_chain": {"schema": chain["schema"], "members": list(reversed(chain["members"]))},
        "desired_chain_sha256": desired_chain_hash(),
        "ownership_sha256": "d" * 64,
        "preservation_set_sha256": "e" * 64,
        "expected_after_sha256": "f" * 64,
        "previous_manifest_semantic_sha256": None,
        "previous_batch_id": None,
        "previous_manifest_artifact_sha256": None,
    }


def semantic_payload() -> dict[str, object]:
    return {
        "schema": "source-scoped-replace-v3-semantic-v1",
        "source_id": 153,
        "record_keys": ["record:one"],
        "input_sha256": "1" * 64,
        "dry_run_semantic_sha256": "2" * 64,
        "ownership_semantic_sha256": "3" * 64,
        "expected_counts": {
            "source_operations": 1,
            "content_revisions": 1,
            "tombstone_revisions": 0,
            "facts": 1,
            "assertions": 1,
            "citations": 1,
            "narrative_operations": 0,
        },
        "policy_decisions": [],
        "narrative_operations": [],
        "source_operations": [source_operation()],
    }


def v1_source_operation(operation: str = "create_chain") -> dict[str, object]:
    result = source_operation(operation)
    result.update({
        "chain_key": "f76b8207f2faf5da65cc85749d5ecc7e2229f1e1cb77e3a3caf467580ea60cb2",
        "previous_manifest_semantic_sha256": None,
        "previous_batch_id": None,
        "previous_manifest_artifact_sha256": None,
    })
    return result


def v1_semantic_payload() -> dict[str, object]:
    payload = semantic_payload()
    payload["expected_counts"] = {
        "source_operations": 1,
        "content_revisions": 1,
        "tombstone_revisions": 0,
        "facts": 1,
        "assertions": 1,
        "citations": 1,
        "narrative_operations": 0,
    }
    payload["source_operations"] = [v1_source_operation()]
    return payload


def test_semantic_hash_excludes_its_derived_manifest_field() -> None:
    payload = semantic_payload()
    assert semantic_hash(payload) == semantic_hash(
        {**payload, "manifest_semantic_sha256": "0" * 64}
    )


def test_manifest_accepts_closed_v1_counts_and_null_predecessor_fields() -> None:
    compiled = build_manifest(v1_semantic_payload())
    assert compiled["expected_counts"] == {
        "source_operations": 1,
        "content_revisions": 1,
        "tombstone_revisions": 0,
        "facts": 1,
        "assertions": 1,
        "citations": 1,
        "narrative_operations": 0,
    }


def test_manifest_accepts_compensation_only_with_all_predecessor_references() -> None:
    payload = v1_semantic_payload()
    operation = v1_source_operation("compensate_chain")
    operation.update({
        "previous_manifest_semantic_sha256": "7" * 64,
        "previous_batch_id": "00000000-0000-0000-0000-000000000157",
        "previous_manifest_artifact_sha256": "8" * 64,
    })
    payload["source_operations"] = [operation]
    compiled = build_manifest(payload)
    assert compiled["source_operations"][0]["operation"] == "compensate_chain"


def test_manifest_accepts_closed_narrative_upsert_operation() -> None:
    payload = v1_semantic_payload()
    payload["expected_counts"]["narrative_operations"] = 1
    payload["narrative_operations"] = [{
        "operation": "upsert",
        "element_id": "evidence:one",
        "person_id": 153,
        "source_id": 153,
        "record_key": "record:one",
        "text": "synthetic narrative",
        "text_sha256": "d788542b03b28979f114e2247442491046794fbe3fe2f7e60ce70577f2665c4b",
        "privat": False,
        "expected_state_sha256": "1" * 64,
    }]
    compiled = build_manifest(payload)
    assert compiled["narrative_operations"][0]["operation"] == "upsert"


def test_manifest_accepts_closed_narrative_reverse_only_for_compensation() -> None:
    payload = v1_semantic_payload()
    operation = v1_source_operation("compensate_chain")
    operation.update({
        "previous_manifest_semantic_sha256": "7" * 64,
        "previous_batch_id": "00000000-0000-0000-0000-000000000157",
        "previous_manifest_artifact_sha256": "8" * 64,
    })
    payload["source_operations"] = [operation]
    payload["expected_counts"]["narrative_operations"] = 1
    payload["narrative_operations"] = [{
        "operation": "reverse",
        "element_id": "evidence:one",
        "person_id": 153,
        "source_id": 153,
        "record_key": "record:one",
        "original_event_id": "00000000-0000-0000-0000-000000000158",
        "reversal_state_sha256": "9" * 64,
    }]
    compiled = build_manifest(payload)
    assert compiled["narrative_operations"][0]["operation"] == "reverse"


def test_manifest_rejects_nonempty_policy_decisions() -> None:
    payload = semantic_payload()
    payload["policy_decisions"] = [{"decision": "unreviewed"}]
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_rejects_nonderived_expected_counts() -> None:
    payload = semantic_payload()
    payload["expected_counts"] = {"facts": 999}
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_rejects_chain_key_not_derived_from_source_record_and_element() -> None:
    payload = semantic_payload()
    payload["source_operations"][0]["chain_key"] = "0" * 64
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_rejects_non_iso_date_before_gateway_use() -> None:
    payload = semantic_payload()
    chain = canonical_desired_chain()
    assertion = chain["members"][1]
    assertion["date_min"] = "not-a-date"
    assertion["date_max"] = "not-a-date"
    payload["source_operations"][0]["desired_chain"] = chain
    payload["source_operations"][0]["desired_chain_sha256"] = desired_chain_hash_for(chain)
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_rejects_unknown_source_operation_before_any_gateway_use() -> None:
    payload = semantic_payload()
    payload["source_operations"] = [source_operation("delete")]
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_canonicalizes_closed_desired_chain_before_hashing() -> None:
    compiled = build_manifest(semantic_payload())
    operation = compiled["source_operations"][0]
    assert operation["desired_chain"] == canonical_desired_chain()
    assert operation["desired_chain_sha256"] == desired_chain_hash()


def test_manifest_rejects_create_chain_without_desired_chain() -> None:
    payload = semantic_payload()
    del payload["source_operations"][0]["desired_chain"]
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_rejects_desired_chain_hash_drift() -> None:
    payload = semantic_payload()
    payload["source_operations"][0]["desired_chain_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_rejects_nonempty_desired_chain_for_remove() -> None:
    payload = semantic_payload()
    payload["source_operations"] = [source_operation("remove_owned_chain")]
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_rejects_noninteger_desired_chain_database_id() -> None:
    payload = semantic_payload()
    chain = canonical_desired_chain()
    chain["members"][0]["subjekt_id"] = 153.0
    payload["source_operations"][0]["desired_chain"] = chain
    payload["source_operations"][0]["desired_chain_sha256"] = desired_chain_hash_for(chain)
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)


def test_manifest_raw_parser_rejects_duplicate_keys_before_semantic_validation() -> None:
    raw = b'{"schema":"source-scoped-replace-v3-semantic-v1","schema":"forged"}'
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        parse_manifest_raw(raw)


def test_manifest_rejects_narrative_operation_without_matching_source_element() -> None:
    payload = semantic_payload()
    payload["narrative_operations"] = [{
        "element_id": "evidence:missing",
        "person_id": 153,
        "source_id": 153,
        "record_key": "record:one",
        "text": "synthetic narrative",
        "text_sha256": hashlib.sha256(b"synthetic narrative").hexdigest(),
        "privat": False,
        "expected_state_sha256": "1" * 64,
    }]
    with pytest.raises(ValueError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
        build_manifest(payload)
