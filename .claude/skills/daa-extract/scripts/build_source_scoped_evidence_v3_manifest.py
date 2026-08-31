#!/usr/bin/env python3
"""Build the closed V3 repository writer snapshot from committed Git blobs only."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any


class RepositoryWriterSnapshotError(ValueError):
    pass


_SOURCE_SUFFIXES = (".R", ".py", ".sql")
_TEST_PREFIXES = ("tests/",)
_NON_ENTRYPOINT_PREFIXES = ("docs/", "design/", "work/")
_TEST_BASENAME_PREFIXES = ("test_",)
_MODEL_TARGET = re.compile(r"\b(?:fact|assertion|citation)\b", re.IGNORECASE)
_DML = re.compile(r"\b(?:INSERT|UPDATE|DELETE|COPY)\b", re.IGNORECASE)
_DB_API = re.compile(
    r"\b(?:DBI::)?(?:dbExecute|dbAppendTable)\s*\(|\bcursor\.execute\s*\(",
    re.IGNORECASE,
)
_DYNAMIC_SQL = re.compile(r"\b(?:paste0?|sprintf|glue|sqlInterpolate)\s*\(", re.IGNORECASE)
_MODEL_DML = re.compile(
    r"\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|COPY)\s+(?:public\.)?(?:fact|assertion|citation)\b",
    re.IGNORECASE,
)
_DYNAMIC_SQL_ALLOWLIST = frozenset({
    ".claude/skills/daa-haendelser/scripts/load_haendelser.R",
    ".claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R",
    ".claude/skills/daa-extract/scripts/backfill_slaegtled.R",
    ".claude/skills/daa-extract/scripts/export_c3_apply_preview_1939_v50.R",
    ".claude/skills/daa-extract/scripts/fix_boern_multi_union.R",
    ".claude/skills/daa-extract/scripts/load_daa.R",
    ".claude/skills/daa-extract/scripts/post_load_fixup.R",
    ".claude/skills/daa-extract/scripts/replace_dryrun.R",
    ".claude/skills/daa-extract/scripts/verify_narrative_record_cutover_postverify.R",
    "R/geo-enrich/run-geo-enrich.R",
    "R/media-janitor.R",
    "R/tng-qa/01-extract-tng.R",
    "R/tng-qa/02-pull-ours.R",
    "R/update-1939-narratives.R",
    "R/update-2018-narratives.R",
    "supabase_load.R",
    ".claude/skills/daa-presens/scripts/load_presens.R",
})
_WRITER_ALLOWLIST: dict[str, tuple[str, tuple[str, ...], tuple[str, ...]]] = {
    ".claude/skills/daa-extract/scripts/apply_c3_1939_v50.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-haendelser/scripts/load_haendelser.R": ("non_model_writer", ("dbExecute",), ("assertion", "fact")),
    ".claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/apply_phase_a_1939_v50_helpers.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/backfill_slaegtled.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/export_c3_apply_preview_1939_v50.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/export_narrative_record_cutover.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/fix_boern_multi_union.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/load_daa.R": ("direct_model_writer", ("dbAppendTable", "dbExecute"), ("assertion", "citation", "fact")),
    ".claude/skills/daa-extract/scripts/post_load_fixup.R": ("direct_model_writer", ("dbExecute",), ("assertion", "citation")),
    ".claude/skills/daa-extract/scripts/preview_reimport_1939_v50.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/profile_identity_review_1939_v50.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/profile_provenance_review_1939_v50.R": ("non_model_writer", ("dbExecute",), ()),
    ".claude/skills/daa-extract/scripts/replace_dryrun.R": ("direct_model_writer", ("dbExecute",), ("fact",)),
    ".claude/skills/daa-extract/scripts/verify_narrative_record_cutover_postverify.R": ("non_model_writer", ("dbExecute",), ()),
    "R/geo-enrich/run-geo-enrich.R": ("non_model_writer", ("dbExecute",), ()),
    "R/media-janitor.R": ("direct_model_writer", ("dbExecute",), ("assertion", "citation")),
    "R/tng-qa/01-extract-tng.R": ("non_model_writer", ("dbExecute",), ()),
    "R/tng-qa/02-pull-ours.R": ("direct_model_writer", ("dbExecute",), ("assertion", "fact")),
    "R/update-1939-narratives.R": ("direct_model_writer", ("dbAppendTable", "dbExecute"), ("assertion", "fact")),
    "R/update-2018-narratives.R": ("direct_model_writer", ("dbExecute",), ("assertion", "fact")),
    "supabase_load.R": ("direct_model_writer", ("dbExecute",), ("assertion", "citation", "fact")),
    ".claude/skills/daa-presens/scripts/load_presens.R": ("direct_model_writer", ("dbExecute",), ("assertion", "citation", "fact")),
    "db-backfill-foraeldrefamilie.sql": ("direct_model_writer", ("sql_dml",), ("assertion", "citation", "fact")),
    "db-migrations-c3-identity.sql": ("direct_model_writer", ("sql_dml",), ("assertion", "citation", "fact")),
    "db-migrations.sql": ("direct_model_writer", ("sql_dml",), ("assertion", "citation", "fact")),
    "db-rls.sql": ("direct_model_writer", ("sql_dml",), ("assertion", "citation", "fact")),
    "db-rollback-fase2.sql": ("non_model_writer", ("sql_dml",), ()),
    "db-rollback-fase3.sql": ("non_model_writer", ("sql_dml",), ()),
    "db-rollback-foraeldrefamilie.sql": ("direct_model_writer", ("sql_dml",), ("assertion", "citation", "fact")),
    "db-verify-media.sql": ("disposable_test_writer", ("sql_dml",), ("assertion", "citation")),
    "db-verify.sql": ("disposable_test_writer", ("sql_dml",), ("assertion", "citation", "fact")),
    "schema.sql": ("direct_model_writer", ("sql_dml",), ("assertion", "citation", "fact")),
}
_WRITER_BLOB_SHA256 = {
    '.claude/skills/daa-extract/scripts/apply_c3_1939_v50.R': '2a81c62ef7e1bb1e90d1272128871014cc4f6fdbb3581cbceeaea9f7891b27bf',
    '.claude/skills/daa-haendelser/scripts/load_haendelser.R': '837841b73165e38d88bf67368be8a5c17ed3ac7330ac2e0618a77fb8e4e6f9bf',
    '.claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R': 'b39edff2cecb7eaa2e68cba4db71c613e480b45b41764195203468503f27fbeb',
    '.claude/skills/daa-extract/scripts/apply_phase_a_1939_v50_helpers.R': '4f4ca1617b9df0875742f248ec50ae7453e46ae67470d81f83253e1c7daa5d8c',
    '.claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R': '2569b17737c725692307fdc5a35a06a7d5ba9b192f5fc588f196ef236c0f09b0',
    '.claude/skills/daa-extract/scripts/backfill_slaegtled.R': 'e6da13816bf9033d8ee42dc66c6f879c61f265aaaa42278829fed0f99f077e47',
    '.claude/skills/daa-extract/scripts/export_c3_apply_preview_1939_v50.R': 'f78aec197acacd6130c157ff6386dd10467a1eed03d58966bb0e4147ea217dc4',
    '.claude/skills/daa-extract/scripts/export_narrative_record_cutover.R': 'cca54f86a80dff82eb9eeab9c3890655ac60bb89a09ef9c938279a5017f3a149',
    '.claude/skills/daa-extract/scripts/fix_boern_multi_union.R': 'd3a2cb0c60278a114f557f084bcc1bef785a8cd1f7feb3faa8b2bdcfa3d2189a',
    '.claude/skills/daa-extract/scripts/load_daa.R': '16d34bb0f05dba90dd911af3d643cd408dcd9eecf2893c274e851bca1d6d21fa',
    '.claude/skills/daa-extract/scripts/post_load_fixup.R': 'df22884bcca9da3824da66675872a080d1352d790e0ec3f4977ac11c1d5f2b8c',
    '.claude/skills/daa-extract/scripts/preview_reimport_1939_v50.R': '59ef534c604d0c5636a462961cdadaf78bda639a49e803f52217c634f42cd8e8',
    '.claude/skills/daa-extract/scripts/profile_identity_review_1939_v50.R': 'd5e8ed29aa711a941c883dc14e406e4673cc3f0d569f4ae93eba54285a29c4f2',
    '.claude/skills/daa-extract/scripts/profile_provenance_review_1939_v50.R': '1eaabaa86c925d22debdf7f86e8006d0b333316c9737c8a8febf91ecd727b323',
    '.claude/skills/daa-extract/scripts/replace_dryrun.R': '69b179cc0d885b1b26c3dc905881a9ba3217a8797d8ccb0554c76b8d92b1f6c1',
    '.claude/skills/daa-extract/scripts/verify_narrative_record_cutover_postverify.R': '9f2af8a32498c968d9d87b5b7463690743de0b41ba7e12df65d583ca39881341',
    'R/geo-enrich/run-geo-enrich.R': '6d3f9b1e6da29112a29c64a8b58a8069937012ef105887a6d8f70b45bef3a510',
    'R/media-janitor.R': 'ca682b78501291fd30b3936685c733c953cc58db6c17896ac2d2a5d2c2dca410',
    'R/tng-qa/01-extract-tng.R': 'dae4cb34dd6beb82800af65d63fc382a38fee8e2327a1e0d8df2f86565525e60',
    'R/tng-qa/02-pull-ours.R': 'a5a56fe165767e2412a065bd0dfe62f27416fc85a0a079aec1a4279c05889d20',
    'R/update-1939-narratives.R': 'df4f640705562c2e122713cc60383a83caee9625a7cce8dcef78c4961a70a559',
    'R/update-2018-narratives.R': '855366debbfa5cd9bae6db199c41174366cbef402e2b20e7e9e4098746eb6167',
    'supabase_load.R': '105b92f549e083cf75eb32a2c0fab11b64346c4820a5ece2d28e8db1898839e2',
    '.claude/skills/daa-presens/scripts/load_presens.R': 'bcfe5d53f578de8a65d0f444912f3fbff785aa781416861933c03e19471c03ab',
    'db-backfill-foraeldrefamilie.sql': '98b8f30a4c1958580fd2f60a7ea02f61dcb35220e03904f5529b3f235695df8c',
    'db-migrations-c3-identity.sql': '81cb181097da6f8f10ec44fd7ea452ad357026bda6acd8bdd0d1785cdd0bec0e',
    'db-migrations.sql': '5473e830f449c670e747780446cbe6dde57c9cc28d64f6a9e3a55cc2bd8ab9e6',
    'db-rls.sql': 'de9d5bf6cad373981e868cf84b06036d6b88b5602d3f753927b317576c94ad99',
    'db-rollback-fase2.sql': '8b453de06c8b413f06bf8ce40cbd5a527309c9dd8d6971f51f56ed4ea3339d01',
    'db-rollback-fase3.sql': '0ccf949bc8fe4597262f4733d220faadf214ad3e46a0f28b6fec2fe6204b81eb',
    'db-rollback-foraeldrefamilie.sql': 'e6246c5f104c738b0ada2b8ffcf2aaf04170398589e750f07e7bfdf73f3fa340',
    'db-verify-media.sql': '6be02d4cc2b3563c6f4374c405ebdb4d26fafaaae26337e630dee7377e86087f',
    'db-verify.sql': '4e1b7d038928c92fb9bb809864e90228932ec70354c6d49d81fb68260d4ac11e',
    'schema.sql': '3aa35a7e47997348373910b496594341abf4b9e269f498f09ec15fbf88294f60',
}


def _git(repo_root: Path, *args: str) -> bytes:
    result = subprocess.run(
        ["git", *args], cwd=repo_root, check=False, capture_output=True
    )
    if result.returncode:
        raise RepositoryWriterSnapshotError("SOURCE_SCOPED_EVIDENCE_REPOSITORY_GIT_FAILED")
    return result.stdout


def _canonical_sha256(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()


def _in_scope(path: str) -> bool:
    name = path.rsplit("/", 1)[-1]
    return (
        path.endswith(_SOURCE_SUFFIXES)
        and not path.startswith(_TEST_PREFIXES)
        and not path.startswith(_NON_ENTRYPOINT_PREFIXES)
        and not name.startswith(_TEST_BASENAME_PREFIXES)
    )


def _language(path: str) -> str:
    if path.endswith(".R"):
        return "R"
    if path.endswith(".py"):
        return "Python"
    if path.endswith(".sql"):
        return "SQL"
    return "text"


def _observed_db_api(path: str, text: str) -> tuple[str, ...]:
    if path.endswith(".sql") and _DML.search(text):
        return ("sql_dml",)
    api: list[str] = []
    if re.search(r"\b(?:DBI::)?dbAppendTable\s*\(", text, re.IGNORECASE):
        api.append("dbAppendTable")
    if re.search(r"\b(?:DBI::)?dbExecute\s*\(", text, re.IGNORECASE):
        api.append("dbExecute")
    if re.search(r"\bcursor\.execute\s*\(", text, re.IGNORECASE):
        api.append("cursor.execute")
    return tuple(api)


def _entry(path: str, blob: bytes) -> dict[str, Any]:
    text = blob.decode("utf-8", errors="strict")
    has_writer_syntax = bool(
        _DB_API.search(text)
        or (_DML.search(text) and path.endswith(".sql"))
        or _MODEL_DML.search(text)
    )
    has_dynamic_sql = bool(_DYNAMIC_SQL.search(text))
    observed_targets = tuple(sorted(set(match.group(0).lower() for match in _MODEL_TARGET.finditer(text))))
    observed_api = _observed_db_api(path, text)
    if not has_writer_syntax:
        writer_class, allowed_db_api, targets = "non_writer", (), ()
    else:
        classified = _WRITER_ALLOWLIST.get(path)
        if classified is None:
            raise RepositoryWriterSnapshotError("SOURCE_SCOPED_EVIDENCE_REPOSITORY_WRITER_UNCLASSIFIED")
        writer_class, allowed_db_api, targets = classified
        if _WRITER_BLOB_SHA256.get(path) != hashlib.sha256(blob).hexdigest():
            raise RepositoryWriterSnapshotError("SOURCE_SCOPED_EVIDENCE_REPOSITORY_RECLASSIFICATION_REQUIRED")
        if observed_api != allowed_db_api or observed_targets != targets:
            raise RepositoryWriterSnapshotError("SOURCE_SCOPED_EVIDENCE_REPOSITORY_WRITER_DRIFT")
        if has_dynamic_sql and path not in _DYNAMIC_SQL_ALLOWLIST:
            raise RepositoryWriterSnapshotError("SOURCE_SCOPED_EVIDENCE_REPOSITORY_DYNAMIC_SQL_UNCLASSIFIED")
    return {
        "path": path,
        "blob_sha256": hashlib.sha256(blob).hexdigest(),
        "language": _language(path),
        "writer_class": writer_class,
        "allowed_db_api": list(allowed_db_api),
        "model_targets": list(targets),
    }


def build_repository_writer_snapshot(repo_root: Path) -> dict[str, Any]:
    """Return a stable snapshot of scoped HEAD blobs, never index/worktree files."""
    root = Path(repo_root).resolve()
    tree_id = _git(root, "rev-parse", "HEAD^{tree}").decode("ascii").strip()
    raw_paths = _git(root, "ls-tree", "-r", "-z", "--name-only", "HEAD")
    paths = sorted(
        item.decode("utf-8") for item in raw_paths.split(b"\0") if item and _in_scope(item.decode("utf-8"))
    )
    entries = [_entry(path, _git(root, "cat-file", "blob", f"HEAD:{path}")) for path in paths]
    payload = {"schema": "source-scoped-evidence-v3-repository-writer-snapshot-v1", "entries": entries}
    return {
        "schema": payload["schema"],
        "repository_tree_id": tree_id,
        "entries": entries,
        "repository_writer_artifact_sha256": _canonical_sha256(payload),
    }
