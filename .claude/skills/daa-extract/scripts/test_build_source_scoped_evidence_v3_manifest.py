from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest


SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

from build_source_scoped_evidence_v3_manifest import (  # noqa: E402
    RepositoryWriterSnapshotError,
    _in_scope,
    build_repository_writer_snapshot,
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
