#!/usr/bin/env python3
"""Build the closed V3 repository writer snapshot from committed Git blobs only."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from datetime import date
from pathlib import Path
from typing import Any


class RepositoryWriterSnapshotError(ValueError):
    pass


class ManifestError(ValueError):
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
    'db-rls.sql': '8085ac8be9b3db830c055488e7b60cf7367ef7ce7a3aae7d5035476cc816fd3b',
    'db-rollback-fase2.sql': '8b453de06c8b413f06bf8ce40cbd5a527309c9dd8d6971f51f56ed4ea3339d01',
    'db-rollback-fase3.sql': '0ccf949bc8fe4597262f4733d220faadf214ad3e46a0f28b6fec2fe6204b81eb',
    'db-rollback-foraeldrefamilie.sql': 'e6246c5f104c738b0ada2b8ffcf2aaf04170398589e750f07e7bfdf73f3fa340',
    'db-verify-media.sql': '6be02d4cc2b3563c6f4374c405ebdb4d26fafaaae26337e630dee7377e86087f',
    'db-verify.sql': '4e1b7d038928c92fb9bb809864e90228932ec70354c6d49d81fb68260d4ac11e',
    'schema.sql': '3aa35a7e47997348373910b496594341abf4b9e269f498f09ec15fbf88294f60',
}

_SOURCE_SCOPED_REPLACE_V3_SCHEMA = "source-scoped-replace-v3-semantic-v1"
_SEMANTIC_FIELDS = (
    "schema", "source_id", "record_keys", "input_sha256",
    "dry_run_semantic_sha256", "ownership_semantic_sha256", "expected_counts",
    "policy_decisions", "narrative_operations", "source_operations",
)
_SOURCE_OPERATION_FIELDS = (
    "element_id", "operation", "chain_key", "source_record_key", "source_persona_id",
    "identity_event_id", "person_id", "prestate_sha256", "desired_chain", "desired_chain_sha256",
    "ownership_sha256", "preservation_set_sha256", "expected_after_sha256",
    "previous_manifest_semantic_sha256", "previous_batch_id", "previous_manifest_artifact_sha256",
)
_DESIRED_CHAIN_FIELDS = ("schema", "members")
_FACT_MEMBER_FIELDS = (
    "member_kind", "member_key", "subjekt_type", "subjekt_id", "faktatype", "sted_id",
)
_ASSERTION_MEMBER_FIELDS = (
    "member_kind", "member_key", "target_type", "target_member_key", "vaerdi_tekst",
    "objekt_type", "objekt_id", "date_min", "date_max", "date_qualifier",
    "date_certainty", "date_raw", "calendar", "uforanderlig",
)
_CITATION_MEMBER_FIELDS = (
    "member_kind", "member_key", "assertion_member_key", "source_id", "side",
    "citat_tekst", "citat_dato", "kvalitet",
)
_DESIRED_CHAIN_SCHEMA = "source-scoped-evidence-v3-desired-chain-v1"
_MEMBER_KEY = re.compile(r"^(fact|assertion|citation):([1-9][0-9]*)$")
_NARRATIVE_UPSERT_FIELDS = (
    "operation", "element_id", "person_id", "source_id", "record_key", "text", "text_sha256",
    "privat", "expected_state_sha256",
)
_NARRATIVE_REVERSE_FIELDS = (
    "operation", "element_id", "person_id", "source_id", "record_key", "original_event_id",
    "reversal_state_sha256",
)
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
_CHAIN_KEY_SCHEMA = "source-scoped-evidence-v3-chain-key-v1"
_EXPECTED_COUNT_FIELDS = (
    "source_operations", "content_revisions", "tombstone_revisions", "facts",
    "assertions", "citations", "narrative_operations",
)
_DATE_QUALIFIERS = frozenset({
    "exact", "before", "after", "between", "about", "floruit", "until_event", "open_end", "ongoing",
})
_DATE_CERTAINTIES = frozenset({"certain", "uncertain", "ambiguous"})
_CALENDARS = frozenset({"gregoriansk", "juliansk"})


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


def _manifest_error() -> None:
    raise ManifestError("SOURCE_SCOPED_REPLACE_MANIFEST_INVALID")


def _reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            _manifest_error()
        result[key] = value
    return result


def parse_manifest_raw(raw: bytes | str) -> dict[str, Any]:
    """Decode a manifest once, rejecting duplicate keys at every object level."""
    try:
        text = raw.decode("utf-8", errors="strict") if isinstance(raw, bytes) else raw
        if not isinstance(text, str):
            _manifest_error()
        payload = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_json_keys,
            parse_constant=lambda _: _manifest_error(),
        )
    except (UnicodeDecodeError, json.JSONDecodeError):
        _manifest_error()
    if not isinstance(payload, dict):
        _manifest_error()
    return payload


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _exact_mapping(value: Any, fields: tuple[str, ...]) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != set(fields):
        _manifest_error()
    return value


def _sha(value: Any) -> str:
    if not isinstance(value, str) or not _SHA256.fullmatch(value):
        _manifest_error()
    return value


def _uuid(value: Any) -> str:
    if not isinstance(value, str) or not _UUID.fullmatch(value):
        _manifest_error()
    return value


def _stable_object_list(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or any(not isinstance(item, dict) for item in value):
        _manifest_error()
    return sorted(value, key=lambda item: json.dumps(item, sort_keys=True, separators=(",", ":")))


def _nullable_string(value: Any) -> None:
    if value is not None and not isinstance(value, str):
        _manifest_error()


def _nullable_iso_date(value: Any) -> date | None:
    _nullable_string(value)
    if value is None:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        _manifest_error()


def _member_key(value: Any, kind: str) -> int:
    if not isinstance(value, str):
        _manifest_error()
    match = _MEMBER_KEY.fullmatch(value)
    if match is None or match.group(1) != kind:
        _manifest_error()
    return int(match.group(2))


def _desired_chain(value: Any, source_id: int, person_id: int, operation_kind: str) -> dict[str, Any]:
    chain = _exact_mapping(value, _DESIRED_CHAIN_FIELDS)
    if chain["schema"] != _DESIRED_CHAIN_SCHEMA or not isinstance(chain["members"], list):
        _manifest_error()
    if not chain["members"]:
        if operation_kind not in {"remove_owned_chain", "compensate_chain"}:
            _manifest_error()
        return {"schema": chain["schema"], "members": []}
    if operation_kind == "remove_owned_chain":
        _manifest_error()

    members: list[dict[str, Any]] = []
    assertion_keys: set[str] = set()
    citation_targets: list[str] = []
    fact_count = 0
    for member in chain["members"]:
        if not isinstance(member, dict) or not isinstance(member.get("member_kind"), str):
            _manifest_error()
        kind = member["member_kind"]
        if kind == "fact":
            item = _exact_mapping(member, _FACT_MEMBER_FIELDS)
            if (
                _member_key(item["member_key"], "fact") != 1
                or item["subjekt_type"] != "person"
                or not _is_int(item["subjekt_id"])
                or item["subjekt_id"] != person_id
                or not isinstance(item["faktatype"], str)
                or not item["faktatype"]
                or (item["sted_id"] is not None and not _is_int(item["sted_id"]))
            ):
                _manifest_error()
            fact_count += 1
        elif kind == "assertion":
            item = _exact_mapping(member, _ASSERTION_MEMBER_FIELDS)
            number = _member_key(item["member_key"], "assertion")
            if item["target_type"] != "fact" or item["target_member_key"] != "fact:1":
                _manifest_error()
            for field in ("vaerdi_tekst", "objekt_type", "date_qualifier", "date_certainty", "date_raw", "calendar"):
                _nullable_string(item[field])
            if item["objekt_id"] is not None and not _is_int(item["objekt_id"]):
                _manifest_error()
            if (item["objekt_type"] is None) != (item["objekt_id"] is None):
                _manifest_error()
            date_min = _nullable_iso_date(item["date_min"])
            date_max = _nullable_iso_date(item["date_max"])
            if date_min is not None and date_max is not None and date_min > date_max:
                _manifest_error()
            if item["date_qualifier"] is not None and item["date_qualifier"] not in _DATE_QUALIFIERS:
                _manifest_error()
            if item["date_certainty"] is not None and item["date_certainty"] not in _DATE_CERTAINTIES:
                _manifest_error()
            if item["calendar"] is not None and item["calendar"] not in _CALENDARS:
                _manifest_error()
            if not isinstance(item["uforanderlig"], bool):
                _manifest_error()
            assertion_keys.add(f"assertion:{number}")
        elif kind == "citation":
            item = _exact_mapping(member, _CITATION_MEMBER_FIELDS)
            _member_key(item["member_key"], "citation")
            _member_key(item["assertion_member_key"], "assertion")
            if not _is_int(item["source_id"]) or item["source_id"] != source_id:
                _manifest_error()
            for field in ("side", "citat_tekst", "citat_dato", "kvalitet"):
                _nullable_string(item[field])
            citation_targets.append(item["assertion_member_key"])
        else:
            _manifest_error()
        members.append(item)

    if (
        fact_count != 1
        or not assertion_keys
        or any(target not in assertion_keys for target in citation_targets)
        or set(citation_targets) != assertion_keys
    ):
        _manifest_error()
    kind_rank = {"fact": 0, "assertion": 1, "citation": 2}
    members.sort(key=lambda item: (kind_rank[item["member_kind"]], _member_key(item["member_key"], item["member_kind"])))
    expected_keys = {
        "fact": ["fact:1"],
        "assertion": [f"assertion:{index}" for index in range(1, len(assertion_keys) + 1)],
        "citation": [f"citation:{index}" for index in range(1, len(citation_targets) + 1)],
    }
    for kind, expected in expected_keys.items():
        observed = [item["member_key"] for item in members if item["member_kind"] == kind]
        if observed != expected:
            _manifest_error()
    return {"schema": chain["schema"], "members": members}


def _source_operation(value: Any, record_keys: set[str], source_id: int) -> dict[str, Any]:
    operation = _exact_mapping(value, _SOURCE_OPERATION_FIELDS)
    if (
        not isinstance(operation["element_id"], str) or not operation["element_id"]
        or operation["operation"] not in {"create_chain", "replace_chain", "remove_owned_chain", "compensate_chain"}
        or not isinstance(operation["chain_key"], str) or not _SHA256.fullmatch(operation["chain_key"])
        or not isinstance(operation["source_record_key"], str)
        or operation["source_record_key"] not in record_keys
        or not _is_int(operation["person_id"])
    ):
        _manifest_error()
    _uuid(operation["source_persona_id"])
    _uuid(operation["identity_event_id"])
    expected_chain_key = _canonical_sha256({
        "schema": _CHAIN_KEY_SCHEMA,
        "source_id": source_id,
        "source_record_key": operation["source_record_key"],
        "element_id": operation["element_id"],
    })
    if operation["chain_key"] != expected_chain_key:
        _manifest_error()
    for field in (
        "prestate_sha256", "desired_chain_sha256", "ownership_sha256",
        "preservation_set_sha256", "expected_after_sha256",
    ):
        _sha(operation[field])
    desired_chain = _desired_chain(
        operation["desired_chain"], source_id, operation["person_id"], operation["operation"]
    )
    if _canonical_sha256(desired_chain) != operation["desired_chain_sha256"]:
        _manifest_error()
    previous_fields = (
        "previous_manifest_semantic_sha256", "previous_batch_id", "previous_manifest_artifact_sha256",
    )
    if operation["operation"] == "compensate_chain":
        _sha(operation["previous_manifest_semantic_sha256"])
        _uuid(operation["previous_batch_id"])
        _sha(operation["previous_manifest_artifact_sha256"])
    elif any(operation[field] is not None for field in previous_fields):
        _manifest_error()
    return {**operation, "desired_chain": desired_chain}


def _narrative_operation(
    value: Any, source_id: int, source_operations: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    if not isinstance(value, dict) or not isinstance(value.get("operation"), str):
        _manifest_error()
    if value["operation"] == "upsert":
        operation = _exact_mapping(value, _NARRATIVE_UPSERT_FIELDS)
    elif value["operation"] == "reverse":
        operation = _exact_mapping(value, _NARRATIVE_REVERSE_FIELDS)
    else:
        _manifest_error()
    source = source_operations.get(operation["element_id"])
    if (
        source is None
        or not _is_int(operation["person_id"])
        or operation["person_id"] != source["person_id"]
        or not _is_int(operation["source_id"])
        or operation["source_id"] != source_id
        or not isinstance(operation["record_key"], str)
        or operation["record_key"] != source["source_record_key"]
    ):
        _manifest_error()
    if operation["operation"] == "upsert":
        if not isinstance(operation["text"], str) or not isinstance(operation["privat"], bool):
            _manifest_error()
        _sha(operation["text_sha256"])
        _sha(operation["expected_state_sha256"])
        if hashlib.sha256(operation["text"].encode("utf-8")).hexdigest() != operation["text_sha256"]:
            _manifest_error()
    else:
        if source["operation"] != "compensate_chain":
            _manifest_error()
        _uuid(operation["original_event_id"])
        _sha(operation["reversal_state_sha256"])
    return operation


def _semantic_projection(payload: Any) -> dict[str, Any]:
    manifest = _exact_mapping(payload, _SEMANTIC_FIELDS + ("manifest_semantic_sha256",)) \
        if isinstance(payload, dict) and "manifest_semantic_sha256" in payload \
        else _exact_mapping(payload, _SEMANTIC_FIELDS)
    if manifest["schema"] != _SOURCE_SCOPED_REPLACE_V3_SCHEMA or not _is_int(manifest["source_id"]):
        _manifest_error()
    record_keys = manifest["record_keys"]
    if (
        not isinstance(record_keys, list) or not record_keys
        or any(not isinstance(key, str) or not key for key in record_keys)
        or len(set(record_keys)) != len(record_keys)
    ):
        _manifest_error()
    for field in ("input_sha256", "dry_run_semantic_sha256", "ownership_semantic_sha256"):
        _sha(manifest[field])
    if (
        not isinstance(manifest["expected_counts"], dict)
        or set(manifest["expected_counts"]) != set(_EXPECTED_COUNT_FIELDS)
        or any(not _is_int(count) or count < 0 for count in manifest["expected_counts"].values())
        or manifest["policy_decisions"] != []
    ):
        _manifest_error()
    source_operations = [_source_operation(item, set(record_keys), manifest["source_id"]) for item in manifest["source_operations"]] \
        if isinstance(manifest["source_operations"], list) else _manifest_error()
    if not source_operations or len({item["element_id"] for item in source_operations}) != len(source_operations):
        _manifest_error()
    source_operations_by_element = {item["element_id"]: item for item in source_operations}
    narrative_operations = [
        _narrative_operation(item, manifest["source_id"], source_operations_by_element)
        for item in manifest["narrative_operations"]
    ] if isinstance(manifest["narrative_operations"], list) else _manifest_error()
    if len({item["element_id"] for item in narrative_operations}) != len(narrative_operations):
        _manifest_error()
    derived_counts = {
        "source_operations": len(source_operations),
        "content_revisions": sum(bool(item["desired_chain"]["members"]) for item in source_operations),
        "tombstone_revisions": sum(not item["desired_chain"]["members"] for item in source_operations),
        "facts": sum(1 for item in source_operations if item["desired_chain"]["members"]),
        "assertions": sum(
            1 for item in source_operations for member in item["desired_chain"]["members"]
            if member["member_kind"] == "assertion"
        ),
        "citations": sum(
            1 for item in source_operations for member in item["desired_chain"]["members"]
            if member["member_kind"] == "citation"
        ),
        "narrative_operations": len(narrative_operations),
    }
    if manifest["expected_counts"] != derived_counts:
        _manifest_error()
    return {
        "schema": manifest["schema"],
        "source_id": manifest["source_id"],
        "record_keys": sorted(record_keys),
        "input_sha256": manifest["input_sha256"],
        "dry_run_semantic_sha256": manifest["dry_run_semantic_sha256"],
        "ownership_semantic_sha256": manifest["ownership_semantic_sha256"],
        "expected_counts": manifest["expected_counts"],
        "policy_decisions": [],
        "narrative_operations": sorted(narrative_operations, key=lambda item: item["element_id"]),
        "source_operations": sorted(source_operations, key=lambda item: item["element_id"]),
    }


def semantic_hash(payload: Any) -> str:
    """Hash only the closed, canonical V3 semantic projection."""
    return _canonical_sha256(_semantic_projection(payload))


def build_manifest(payload: Any) -> dict[str, Any]:
    """Validate and compile a closed V3 source-scoped semantic manifest."""
    semantic = _semantic_projection(payload)
    return {**semantic, "manifest_semantic_sha256": _canonical_sha256(semantic)}


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
