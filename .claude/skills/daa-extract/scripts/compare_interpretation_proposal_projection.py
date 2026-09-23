#!/usr/bin/env python3
"""Closed, database-free contracts for interpretation-proposal projections."""
from __future__ import annotations

import argparse
from collections import Counter
from decimal import Decimal, InvalidOperation
import hashlib
import json
import os
from pathlib import Path
import sys
from typing import Any, Mapping
import uuid


PROJECTION_SCHEMA = "daa-interpretation-proposal-projection-v1"
RESULT_SCOPE = "interpretation-proposal-delta-v1"
PROJECTION_KEYS = frozenset({
    "schema_version", "source_id", "database_target_identity",
    "source_records", "source_anchors", "narrative_bindings",
    "narrative_sha256", "persons", "upstream_sha256", "neutral_sha256",
    "anon_sha256", "clauses", "interpretations", "interpretation_links",
    "extraction_runs", "proposal_events", "reversal_events",
    "authorizations", "batches", "promotion_sha256",
})
MANIFEST_TOP_KEYS = frozenset({
    "manifest_content_sha256", "source", "expected_counts", "operations", "provenance",
})
SOURCE_KEYS = frozenset({"id", "profile_id", "profile_sha256"})
COUNT_KEYS = frozenset({
    "person_creates", "source_evidence", "canonical_delta", "interpretation_proposals",
})
OPERATION_KEYS = frozenset({
    "element_id", "dependency_class", "source_record_key", "runner_manifest_sha256",
    "model_version", "prompt_version", "claims",
})
CLAIM_KEYS = frozenset({
    "claim_id", "predicate", "interpretation_kind", "value", "confidence",
    "cited_clauses", "persona_role",
})
CITATION_KEYS = frozenset({"ordinal", "verbatim_sha256"})
PROVENANCE_KEYS = frozenset({
    "schema_version", "runner_manifest_sha256", "eligibility_ledger_sha256", "cache_files",
    "predicates_sha256", "runner_contract_version", "denylist_version",
    "persona_role_map_version", "regnskab", "h1_afviste", "dublet_claims",
    "ukendt_rolle_claims", "usage",
})
REGNSKAB_KEYS = frozenset({
    "raa_claims", "kontrakt_afviste", "h1_afviste", "dubletter", "ukendt_rolle",
    "ingestible",
})
USAGE_KEYS = frozenset({
    "input_tokens", "output_tokens", "reasoning_output_tokens", "cached_input_tokens",
    "cache_write_input_tokens",
})
SAFE_INTEGER_MIN = -9007199254740991
SAFE_INTEGER_MAX = 9007199254740991
NEUTRAL_LISTS = (
    "source_records", "source_anchors", "narrative_bindings", "narrative_sha256", "persons",
)
ROW_KEYS = {
    "source_records": frozenset({"record_key"}),
    "source_anchors": frozenset({"record_key", "occurrence_id"}),
    "narrative_bindings": frozenset({"record_key", "narrative_id", "status"}),
    "narrative_sha256": frozenset({"narrative_id", "sha256"}),
    "persons": frozenset({"person_id"}),
    "clauses": frozenset({
        "observation_id", "record_key", "clause_ordinal", "version", "disposition",
        "decided_by_kind", "evidence_batch_id", "evidence_extraction_run_id",
        "evidence_element_id", "evidence_manifest_sha256", "row_sha256",
    }),
    "interpretations": frozenset({
        "interpretation_id", "interpretation_key", "version", "status", "record_key",
        "predicate", "interpretation_kind", "schema_version", "derivation_kind", "method",
        "confidence", "persona_bound", "extraction_run_id", "supersedes_id", "value_sha256",
        "key_material_sha256", "key_matches", "row_sha256",
    }),
    "interpretation_links": frozenset({
        "interpretation_id", "observation_id", "evidence_role", "link_ordinal", "record_key",
        "clause_ordinal", "verbatim_sha256", "row_sha256",
    }),
    "extraction_runs": frozenset({
        "run_id", "run_key", "schema_version", "extractor_version", "profile_version",
        "input_sha256", "row_sha256",
    }),
    "proposal_events": frozenset({
        "event_id", "batch_id", "element_id", "source_record_key", "run_id",
        "runner_manifest_sha256", "model_version", "prompt_version", "claim_count",
        "result_receipt", "result_receipt_sha256", "before_sha256", "after_sha256", "row_sha256",
    }),
    "reversal_events": frozenset({
        "event_id", "batch_id", "element_id", "source_record_key", "before_sha256",
        "after_sha256", "row_sha256",
    }),
    "authorizations": frozenset({
        "authorization_id", "operation", "status", "consumed", "manifest_sha256",
        "preview_sha256", "profile_id", "profile_sha256", "principal_id", "expected_counts",
        "authorized_elements_sha256", "authorized_element_ids", "row_sha256",
    }),
    "batches": frozenset({
        "batch_id", "authorization_id", "status", "finalized", "manifest_sha256",
        "preview_sha256", "profile_id", "profile_sha256", "principal_id", "expected_counts",
        "observed_counts", "row_sha256",
    }),
}
RECEIPT_KEYS = frozenset({"schema_version", "claims", "clause_dispositions"})
RECEIPT_CLAIM_KEYS = frozenset({
    "claim_id", "interpretation_id", "interpretation_key", "version", "value_sha256",
    "key_material_sha256", "row_sha256", "extraction_run_id", "observations",
})
RECEIPT_OBSERVATION_KEYS = frozenset({
    "observation_id", "clause_ordinal", "verbatim_sha256", "evidence_role",
    "link_ordinal", "row_sha256",
})
RECEIPT_DISPOSITION_KEYS = frozenset({"observation_id", "before", "written"})
RECEIPT_DISPOSITION_STATE_KEYS = frozenset({
    "observation_id", "version", "disposition", "decided_by_kind", "evidence",
    "decided_by", "decided_by_name", "decided_at", "created_at", "row_sha256",
})
BEFORE_EVIDENCE_KEYS = frozenset({
    "batch_id", "element_id", "manifest_sha256", "clause_rules_version",
})
WRITTEN_EVIDENCE_KEYS = frozenset({
    "batch_id", "element_id", "manifest_sha256", "extraction_run_id",
})
EXPECTED_COUNT_ORDER = (
    "person_creates", "source_evidence", "legacy_migrations", "clause_evidence",
    "interpretation_proposals",
)
REPLAY_SCOPE = "interpretation-proposal-replay-v1"


class ProjectionError(ValueError):
    """A sanitized, fail-closed projection/manifest contract error."""

    def __init__(self, code: str, details: dict[str, Any] | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.details = details or {}


def _fail(code: str, **details: Any) -> None:
    raise ProjectionError(code, details)


def _is_sha(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _is_plain_int(value: Any) -> bool:
    return type(value) is int


def _canon(value: Any) -> str:
    if value is None:
        return "null"
    if type(value) is bool:
        return "true" if value else "false"
    if type(value) is int:
        return str(value)
    if isinstance(value, Decimal):
        if not value.is_finite():
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="json_number")
        text = format(value, "f")
        if "." in text:
            text = text.rstrip("0").rstrip(".")
        return "0" if text in {"-0", ""} else text
    if isinstance(value, float):
        if value != value or value in {float("inf"), float("-inf")}:
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="json_number")
        return json.dumps(value, allow_nan=False, separators=(",", ":"))
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ",".join(_canon(item) for item in value) + "]"
    if isinstance(value, Mapping):
        return "{" + ",".join(
            f"{json.dumps(key, ensure_ascii=False)}:{_canon(value[key])}"
            for key in sorted(value)
        ) + "}"
    raise TypeError(f"unsupported JSON type: {type(value).__name__}")


def _reject_constant(_: str) -> None:
    _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="json_number")


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="json_object")
        result[key] = value
    return result


def strict_json_loads(raw: str) -> Any:
    """Decode cached/transport JSON without accepting lossy number syntax."""
    if not isinstance(raw, str):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="json")
    try:
        value = json.loads(raw, parse_float=Decimal, parse_int=int,
                           parse_constant=_reject_constant, object_pairs_hook=_reject_duplicate_pairs)
    except ProjectionError:
        raise
    except (json.JSONDecodeError, InvalidOperation):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="json")
    _validate_json_scalars(value)
    return value


def _validate_json_scalars(value: Any) -> None:
    if isinstance(value, str):
        if "\x00" in value or any(0xD800 <= ord(character) <= 0xDFFF for character in value):
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="json_string")
        return
    if isinstance(value, list):
        for item in value:
            _validate_json_scalars(item)
        return
    if isinstance(value, Mapping):
        for key, item in value.items():
            if not isinstance(key, str):
                _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="json_object")
            _validate_json_scalars(key)
            _validate_json_scalars(item)


def normalize_interpretation_proposal_claim_value(value: Any) -> Any:
    """Return the shared, safe-integer JSON value or raise a sanitized NO-GO."""
    if value is None or isinstance(value, str) or type(value) is bool:
        _validate_json_scalars(value)
        return value
    if _is_plain_int(value):
        if not SAFE_INTEGER_MIN <= value <= SAFE_INTEGER_MAX:
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim_value_number")
        return value
    if isinstance(value, Decimal):
        if not value.is_finite() or value != value.to_integral_value():
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim_value_number")
        integer = int(value)
        if not SAFE_INTEGER_MIN <= integer <= SAFE_INTEGER_MAX:
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim_value_number")
        return integer
    if isinstance(value, float):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim_value_number")
    if isinstance(value, list):
        return [normalize_interpretation_proposal_claim_value(item) for item in value]
    if isinstance(value, Mapping):
        result: dict[str, Any] = {}
        for key, item in value.items():
            if not isinstance(key, str) or key in result:
                _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim_value_object")
            _validate_json_scalars(key)
            result[key] = normalize_interpretation_proposal_claim_value(item)
        return result
    _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim_value")


def proposal_canonical_bytes(value: Any) -> bytes:
    return _canon(normalize_interpretation_proposal_claim_value(value)).encode("utf-8")


def proposal_canonical_sha256(value: Any) -> str:
    return hashlib.sha256(proposal_canonical_bytes(value)).hexdigest()


def _manifest_canonical_sha256(value: Any) -> str:
    return hashlib.sha256(_canon(value).encode("utf-8")).hexdigest()


def compute_manifest_sha256(manifest: dict[str, Any]) -> str:
    body = {key: value for key, value in manifest.items() if key != "manifest_content_sha256"}
    return _manifest_canonical_sha256(body)


def _require_nonempty_string(value: Any, part: str) -> None:
    if not isinstance(value, str) or not value:
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part=part)


def _validate_provenance(provenance: Any) -> None:
    if not isinstance(provenance, dict) or set(provenance) != PROVENANCE_KEYS:
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="provenance")
    if provenance["schema_version"] != "interpretation-proposal-manifest-1.0":
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="provenance")
    for key in ("runner_manifest_sha256", "eligibility_ledger_sha256", "predicates_sha256"):
        if not _is_sha(provenance[key]):
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="provenance")
    if (not isinstance(provenance["cache_files"], dict)
            or not all(isinstance(key, str) and _is_sha(value)
                       for key, value in provenance["cache_files"].items())):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="provenance")
    if not all(isinstance(provenance[key], str) and provenance[key]
               for key in ("runner_contract_version", "denylist_version", "persona_role_map_version")):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="provenance")
    accounting = provenance["regnskab"]
    if (not isinstance(accounting, dict) or set(accounting) != REGNSKAB_KEYS
            or not all(_is_plain_int(value) and value >= 0 for value in accounting.values())):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="provenance")
    if not all(isinstance(provenance[key], list)
               for key in ("h1_afviste", "dublet_claims", "ukendt_rolle_claims")):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="provenance")
    usage = provenance["usage"]
    if (not isinstance(usage, dict) or set(usage) != USAGE_KEYS
            or not all(_is_plain_int(value) and value >= 0 for value in usage.values())):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="provenance")


def validate_manifest(manifest: Any) -> dict[str, Any]:
    if not isinstance(manifest, dict) or set(manifest) != MANIFEST_TOP_KEYS:
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="top")
    if not _is_sha(manifest["manifest_content_sha256"]):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="manifest_content_sha256")
    source = manifest["source"]
    if (not isinstance(source, dict) or set(source) != SOURCE_KEYS
            or not _is_plain_int(source["id"]) or source["id"] <= 0
            or not isinstance(source["profile_id"], str) or not source["profile_id"]
            or not _is_sha(source["profile_sha256"])):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="source")
    counts = manifest["expected_counts"]
    if (not isinstance(counts, dict) or set(counts) != COUNT_KEYS
            or any(not _is_plain_int(value) or value < 0 for value in counts.values())
            or any(counts[key] != 0 for key in ("person_creates", "source_evidence", "canonical_delta"))):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="expected_counts")
    operations = manifest["operations"]
    if not isinstance(operations, list) or not operations or counts["interpretation_proposals"] != len(operations):
        _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="operations")
    source_records: set[str] = set()
    claim_ids: set[str] = set()
    for operation in operations:
        if not isinstance(operation, dict) or set(operation) != OPERATION_KEYS:
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="operation")
        record_key = operation["source_record_key"]
        if (not isinstance(record_key, str) or not record_key or record_key in source_records
                or operation["element_id"] != f"interpretation-proposal:{record_key}"
                or operation["dependency_class"] != "interpretation_proposal"):
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="operation")
        source_records.add(record_key)
        if not all(isinstance(operation[key], str) and operation[key]
                   for key in ("model_version", "prompt_version")) or not _is_sha(operation["runner_manifest_sha256"]):
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="operation")
        claims = operation["claims"]
        if not isinstance(claims, list) or not claims:
            _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claims")
        for claim in claims:
            if not isinstance(claim, dict) or set(claim) != CLAIM_KEYS:
                _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim")
            claim_id = claim["claim_id"]
            if (not isinstance(claim_id, str) or len(claim_id) != 32
                    or any(char not in "0123456789abcdef" for char in claim_id)
                    or claim_id in claim_ids):
                _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim")
            claim_ids.add(claim_id)
            if (not isinstance(claim["predicate"], str) or not claim["predicate"]
                    or not isinstance(claim["interpretation_kind"], str) or not claim["interpretation_kind"]
                    or claim["persona_role"] not in {"principal", "other"}
                    or not isinstance(claim["confidence"], (int, float, Decimal))
                    or isinstance(claim["confidence"], bool)
                    or not Decimal(str(claim["confidence"])).is_finite()
                    or not Decimal(0) <= Decimal(str(claim["confidence"])) <= Decimal(1)):
                _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="claim")
            normalize_interpretation_proposal_claim_value(claim["value"])
            citations = claim["cited_clauses"]
            if not isinstance(citations, list) or not citations:
                _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="cited_clauses")
            ordinals: set[int] = set()
            for citation in citations:
                if (not isinstance(citation, dict) or set(citation) != CITATION_KEYS
                        or not _is_plain_int(citation["ordinal"]) or citation["ordinal"] < 1
                        or citation["ordinal"] in ordinals or not _is_sha(citation["verbatim_sha256"])):
                    _fail("INTERPRETATION_PROJECTION_MANIFEST_INVALID", part="cited_clauses")
                ordinals.add(citation["ordinal"])
    _validate_provenance(manifest["provenance"])
    if compute_manifest_sha256(manifest) != manifest["manifest_content_sha256"]:
        _fail("INTERPRETATION_PROJECTION_MANIFEST_HASH_MISMATCH")
    return manifest


def _is_uuid(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        return str(uuid.UUID(value)) == value.lower()
    except ValueError:
        return False


def _is_nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value)


def _is_positive_int(value: Any) -> bool:
    return _is_plain_int(value) and value > 0


def _is_counts(value: Any) -> bool:
    return (isinstance(value, dict) and all(isinstance(key, str) and key for key in value)
            and all(_is_plain_int(item) and item >= 0 for item in value.values()))


def _receipt_state_shape(value: Any, *, written: bool) -> bool:
    if not isinstance(value, dict) or set(value) != RECEIPT_DISPOSITION_STATE_KEYS:
        return False
    evidence = value["evidence"]
    evidence_keys = WRITTEN_EVIDENCE_KEYS if written else BEFORE_EVIDENCE_KEYS
    if not isinstance(evidence, dict) or set(evidence) != evidence_keys:
        return False
    if (not _is_uuid(evidence["batch_id"]) or not _is_nonempty_string(evidence["element_id"])
            or not _is_sha(evidence["manifest_sha256"])):
        return False
    if written:
        if not _is_uuid(evidence["extraction_run_id"]):
            return False
    elif not _is_nonempty_string(evidence["clause_rules_version"]):
        return False
    return (
        _is_uuid(value["observation_id"])
        and _is_positive_int(value["version"])
        and _is_nonempty_string(value["disposition"])
        and _is_nonempty_string(value["decided_by_kind"])
        and (value["decided_by"] is None or _is_uuid(value["decided_by"]))
        and (value["decided_by_name"] is None or isinstance(value["decided_by_name"], str))
        and (value["decided_at"] is None or _is_nonempty_string(value["decided_at"]))
        and _is_nonempty_string(value["created_at"])
        and _is_sha(value["row_sha256"])
    )


def _receipt_shape(value: Any) -> bool:
    if (not isinstance(value, dict) or set(value) != RECEIPT_KEYS
            or not isinstance(value["schema_version"], str)
            or not isinstance(value["claims"], list)
            or not isinstance(value["clause_dispositions"], list)):
        return False
    for claim in value["claims"]:
        if (not isinstance(claim, dict) or set(claim) != RECEIPT_CLAIM_KEYS
                or not isinstance(claim["claim_id"], str)
                or len(claim["claim_id"]) != 32
                or any(char not in "0123456789abcdef" for char in claim["claim_id"])
                or not _is_uuid(claim["interpretation_id"])
                or not _is_uuid(claim["interpretation_key"])
                or not _is_positive_int(claim["version"])
                or not all(_is_sha(claim[key]) for key in (
                    "value_sha256", "key_material_sha256", "row_sha256"))
                or not _is_uuid(claim["extraction_run_id"])
                or not isinstance(claim["observations"], list)):
            return False
        for observation in claim["observations"]:
            if (not isinstance(observation, dict) or set(observation) != RECEIPT_OBSERVATION_KEYS
                    or not _is_uuid(observation["observation_id"])
                    or not _is_positive_int(observation["clause_ordinal"])
                    or not _is_sha(observation["verbatim_sha256"])
                    or not _is_nonempty_string(observation["evidence_role"])
                    or not _is_positive_int(observation["link_ordinal"])
                    or not _is_sha(observation["row_sha256"])):
                return False
    for disposition in value["clause_dispositions"]:
        if (not isinstance(disposition, dict) or set(disposition) != RECEIPT_DISPOSITION_KEYS
                or not _is_uuid(disposition["observation_id"])
                or not _receipt_state_shape(disposition["before"], written=False)
                or not _receipt_state_shape(disposition["written"], written=True)):
            return False
    return True


def _row_shape(name: str, row: dict[str, Any]) -> bool:
    if set(row) != ROW_KEYS[name]:
        return False
    if name == "source_records":
        return _is_nonempty_string(row["record_key"])
    if name == "source_anchors":
        return _is_nonempty_string(row["record_key"]) and _is_uuid(row["occurrence_id"])
    if name == "narrative_bindings":
        return (_is_nonempty_string(row["record_key"]) and _is_positive_int(row["narrative_id"])
                and _is_nonempty_string(row["status"]))
    if name == "narrative_sha256":
        return _is_positive_int(row["narrative_id"]) and _is_sha(row["sha256"])
    if name == "persons":
        return _is_positive_int(row["person_id"])
    if name == "clauses":
        return (
            _is_uuid(row["observation_id"]) and _is_nonempty_string(row["record_key"])
            and _is_positive_int(row["clause_ordinal"]) and _is_positive_int(row["version"])
            and _is_nonempty_string(row["disposition"])
            and _is_nonempty_string(row["decided_by_kind"])
            and (row["evidence_batch_id"] is None or _is_uuid(row["evidence_batch_id"]))
            and (row["evidence_extraction_run_id"] is None or _is_uuid(row["evidence_extraction_run_id"]))
            and (row["evidence_element_id"] is None or _is_nonempty_string(row["evidence_element_id"]))
            and (row["evidence_manifest_sha256"] is None or _is_sha(row["evidence_manifest_sha256"]))
            and _is_sha(row["row_sha256"])
        )
    if name == "interpretations":
        return (
            _is_uuid(row["interpretation_id"]) and _is_uuid(row["interpretation_key"])
            and _is_positive_int(row["version"])
            and all(_is_nonempty_string(row[key]) for key in (
                "status", "record_key", "predicate", "interpretation_kind", "schema_version",
                "derivation_kind", "method", "confidence"))
            and type(row["persona_bound"]) is bool
            and _is_uuid(row["extraction_run_id"])
            and (row["supersedes_id"] is None or _is_uuid(row["supersedes_id"]))
            and all(_is_sha(row[key]) for key in (
                "value_sha256", "key_material_sha256", "row_sha256"))
            and type(row["key_matches"]) is bool
        )
    if name == "interpretation_links":
        return (
            _is_uuid(row["interpretation_id"]) and _is_uuid(row["observation_id"])
            and _is_nonempty_string(row["evidence_role"])
            and _is_positive_int(row["link_ordinal"])
            and _is_nonempty_string(row["record_key"])
            and _is_positive_int(row["clause_ordinal"])
            and _is_sha(row["verbatim_sha256"]) and _is_sha(row["row_sha256"])
        )
    if name == "extraction_runs":
        return (
            _is_uuid(row["run_id"])
            and all(_is_nonempty_string(row[key]) for key in (
                "run_key", "schema_version", "extractor_version", "profile_version"))
            and _is_sha(row["input_sha256"]) and _is_sha(row["row_sha256"])
        )
    if name == "proposal_events":
        return (
            _is_positive_int(row["event_id"]) and _is_uuid(row["batch_id"])
            and all(_is_nonempty_string(row[key]) for key in (
                "element_id", "source_record_key", "model_version", "prompt_version"))
            and _is_uuid(row["run_id"]) and _is_sha(row["runner_manifest_sha256"])
            and _is_plain_int(row["claim_count"]) and row["claim_count"] >= 0
            and _receipt_shape(row["result_receipt"])
            and _is_sha(row["result_receipt_sha256"])
            and (row["before_sha256"] is None or _is_sha(row["before_sha256"]))
            and _is_sha(row["after_sha256"]) and _is_sha(row["row_sha256"])
        )
    if name == "reversal_events":
        return (
            _is_positive_int(row["event_id"]) and _is_uuid(row["batch_id"])
            and _is_nonempty_string(row["element_id"])
            and _is_nonempty_string(row["source_record_key"])
            and (row["before_sha256"] is None or _is_sha(row["before_sha256"]))
            and (row["after_sha256"] is None or _is_sha(row["after_sha256"]))
            and _is_sha(row["row_sha256"])
        )
    if name == "authorizations":
        return (
            _is_uuid(row["authorization_id"])
            and all(_is_nonempty_string(row[key]) for key in (
                "operation", "status", "profile_id"))
            and type(row["consumed"]) is bool
            and all(_is_sha(row[key]) for key in (
                "manifest_sha256", "preview_sha256", "profile_sha256",
                "authorized_elements_sha256", "row_sha256"))
            and _is_uuid(row["principal_id"]) and _is_counts(row["expected_counts"])
            and isinstance(row["authorized_element_ids"], list)
            and all(_is_nonempty_string(item) for item in row["authorized_element_ids"])
            and len(set(row["authorized_element_ids"])) == len(row["authorized_element_ids"])
        )
    if name == "batches":
        return (
            _is_uuid(row["batch_id"]) and _is_uuid(row["authorization_id"])
            and all(_is_nonempty_string(row[key]) for key in ("status", "profile_id"))
            and type(row["finalized"]) is bool
            and all(_is_sha(row[key]) for key in (
                "manifest_sha256", "preview_sha256", "profile_sha256", "row_sha256"))
            and _is_uuid(row["principal_id"]) and _is_counts(row["expected_counts"])
            and _is_counts(row["observed_counts"])
        )
    return False


def validate_projection(projection: Any) -> dict[str, Any]:
    if not isinstance(projection, dict) or set(projection) != PROJECTION_KEYS:
        _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part="top")
    if (projection["schema_version"] != PROJECTION_SCHEMA
            or not _is_positive_int(projection["source_id"])):
        _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part="header")
    identity = projection["database_target_identity"]
    if (not isinstance(identity, dict) or set(identity) != {"database_name", "system_identifier_sha256"}
            or not _is_nonempty_string(identity["database_name"])
            or not _is_sha(identity["system_identifier_sha256"])):
        _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part="database_target_identity")
    for key in ("upstream_sha256", "neutral_sha256", "anon_sha256", "promotion_sha256"):
        if not _is_sha(projection[key]):
            _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part=key)
    for name in ROW_KEYS:
        rows = projection[name]
        if (not isinstance(rows, list) or not all(isinstance(row, dict) and _row_shape(name, row)
                                                  for row in rows)):
            _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part=name)
    return projection


def target_sha256(identity: dict[str, Any]) -> str:
    if (not isinstance(identity, dict) or set(identity) != {"database_name", "system_identifier_sha256"}
            or not isinstance(identity["database_name"], str) or not _is_sha(identity["system_identifier_sha256"])):
        _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part="database_target_identity")
    return hashlib.sha256(
        f"{identity['database_name']}\n{identity['system_identifier_sha256']}".encode("utf-8")
    ).hexdigest()


def _row_identity(name: str, row: dict[str, Any]) -> Any:
    fields = {
        "clauses": ("observation_id", "version"),
        "interpretations": ("interpretation_id",),
        "interpretation_links": ("interpretation_id", "link_ordinal"),
        "extraction_runs": ("run_id",),
        "proposal_events": ("event_id",),
        "reversal_events": ("event_id",),
        "authorizations": ("authorization_id",),
        "batches": ("batch_id",),
    }[name]
    values = tuple(row[field] for field in fields)
    return values[0] if len(values) == 1 else values


def _row_map(projection: dict[str, Any], name: str) -> dict[Any, dict[str, Any]]:
    result: dict[Any, dict[str, Any]] = {}
    for row in projection[name]:
        identity = _row_identity(name, row)
        if identity in result:
            _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part=name)
        result[identity] = row
    return result


def _new_rows(before: dict[str, Any], after: dict[str, Any], name: str) -> list[dict[str, Any]]:
    before_rows = _row_map(before, name)
    return [row for identity, row in _row_map(after, name).items() if identity not in before_rows]


def _require_preserved(before: dict[str, Any], after: dict[str, Any], name: str,
                       code: str = "INTERPRETATION_PROJECTION_FOREIGN_DRIFT") -> None:
    before_rows = _row_map(before, name)
    after_rows = _row_map(after, name)
    changed = [identity for identity, row in before_rows.items()
               if identity not in after_rows or _canon(row) != _canon(after_rows[identity])]
    if changed:
        _fail(code, part=name, rows=len(changed))


def _expected_counts(manifest: dict[str, Any]) -> dict[str, int]:
    return {key: manifest["expected_counts"][key]
            for key in EXPECTED_COUNT_ORDER if key in manifest["expected_counts"]}


def _manifest_claims(manifest: dict[str, Any]) -> list[tuple[dict[str, Any], dict[str, Any]]]:
    return [(operation, claim) for operation in manifest["operations"]
            for claim in operation["claims"]]


def _compare_source_and_target(manifest: dict[str, Any], before: dict[str, Any],
                               after: dict[str, Any], expected_target_sha256: str) -> str:
    if not _is_sha(expected_target_sha256):
        _fail("INTERPRETATION_PROJECTION_TARGET_MISMATCH", part="expected_target_sha256")
    if not (manifest["source"]["id"] == before["source_id"] == after["source_id"]):
        _fail("INTERPRETATION_PROJECTION_SOURCE_MISMATCH")
    if before["database_target_identity"] != after["database_target_identity"]:
        _fail("INTERPRETATION_PROJECTION_TARGET_MISMATCH", part="database_target_identity")
    actual = target_sha256(after["database_target_identity"])
    if actual != expected_target_sha256:
        _fail("INTERPRETATION_PROJECTION_TARGET_MISMATCH", part="expected_target_sha256")
    return actual


def _compare_neutral_surfaces(before: dict[str, Any], after: dict[str, Any]) -> None:
    changed_lists = [name for name in NEUTRAL_LISTS
                     if sorted(_canon(row) for row in before[name])
                     != sorted(_canon(row) for row in after[name])]
    if changed_lists:
        _fail("INTERPRETATION_PROJECTION_NEUTRAL_LIST_DRIFT", parts=changed_lists)
    for field, code in (
        ("upstream_sha256", "INTERPRETATION_PROJECTION_UPSTREAM_DRIFT"),
        ("neutral_sha256", "INTERPRETATION_PROJECTION_CANONICAL_DRIFT"),
        ("anon_sha256", "INTERPRETATION_PROJECTION_ANON_DRIFT"),
        ("promotion_sha256", "INTERPRETATION_PROJECTION_PROMOTION_DRIFT"),
    ):
        if before[field] != after[field]:
            _fail(code, part=field)


def _check_preexisting(manifest: dict[str, Any], before: dict[str, Any],
                       after: dict[str, Any]) -> None:
    elements = {operation["element_id"] for operation in manifest["operations"]}
    if any(event["element_id"] in elements for event in before["proposal_events"]):
        _fail("INTERPRETATION_PROJECTION_PREEXISTING_TARGET", part="proposal_events")
    manifest_records = {operation["source_record_key"] for operation in manifest["operations"]}
    manifest_predicates = {claim["predicate"] for _, claim in _manifest_claims(manifest)}
    after_keys = {row["interpretation_key"] for row in after["interpretations"]
                  if row["record_key"] in manifest_records and row["predicate"] in manifest_predicates}
    if any(row["interpretation_key"] in after_keys for row in before["interpretations"]):
        _fail("INTERPRETATION_PROJECTION_PREEXISTING_TARGET", part="interpretations")


def _validate_new_event_receipt(event: dict[str, Any]) -> None:
    receipt = event["result_receipt"]
    receipt_hash = proposal_canonical_sha256(receipt)
    if (receipt["schema_version"] != "interpretation-proposal-result-v1"
            or event["result_receipt_sha256"] != receipt_hash
            or event["after_sha256"] != receipt_hash):
        _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="hash")


def _compare_batch_authorization_and_events(
        manifest: dict[str, Any], before: dict[str, Any], after: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    new_batches = _new_rows(before, after, "batches")
    new_authorizations = _new_rows(before, after, "authorizations")
    expected_counts = _expected_counts(manifest)
    element_ids = sorted(operation["element_id"] for operation in manifest["operations"])
    if len(new_batches) != 1 or len(new_authorizations) != 1:
        _fail("INTERPRETATION_PROJECTION_BATCH_BINDING_INVALID",
              batches=len(new_batches), authorizations=len(new_authorizations))
    batch, authorization = new_batches[0], new_authorizations[0]
    source = manifest["source"]
    batch_ok = (
        batch["status"] == "finalized" and batch["finalized"] is True
        and batch["manifest_sha256"] == manifest["manifest_content_sha256"]
        and batch["profile_id"] == source["profile_id"]
        and batch["profile_sha256"] == source["profile_sha256"]
        and batch["expected_counts"] == expected_counts
        and batch["observed_counts"] == expected_counts
        and batch["authorization_id"] == authorization["authorization_id"]
    )
    authorization_ok = (
        authorization["operation"] == "reimport" and authorization["status"] == "consumed"
        and authorization["consumed"] is True
        and authorization["manifest_sha256"] == manifest["manifest_content_sha256"]
        and authorization["preview_sha256"] == batch["preview_sha256"]
        and authorization["profile_id"] == batch["profile_id"]
        and authorization["profile_sha256"] == batch["profile_sha256"]
        and authorization["principal_id"] == batch["principal_id"]
        and authorization["expected_counts"] == expected_counts
        and authorization["authorized_element_ids"] == element_ids
    )
    if not batch_ok or not authorization_ok:
        _fail("INTERPRETATION_PROJECTION_BATCH_BINDING_INVALID", part="binding")

    new_events = _new_rows(before, after, "proposal_events")
    if len(new_events) != len(manifest["operations"]):
        _fail("INTERPRETATION_PROJECTION_EVENT_HISTORY_DRIFT",
              events=len(new_events), expected=len(manifest["operations"]))
    events_by_element = {event["element_id"]: event for event in new_events}
    if len(events_by_element) != len(new_events) or set(events_by_element) != set(element_ids):
        _fail("INTERPRETATION_PROJECTION_EVENT_HISTORY_DRIFT", part="elements")
    run_ids: set[str] = set()
    for operation in manifest["operations"]:
        event = events_by_element[operation["element_id"]]
        if event["batch_id"] != batch["batch_id"]:
            _fail("INTERPRETATION_PROJECTION_BATCH_BINDING_INVALID", part="event_batch")
        event_ok = (
            event["source_record_key"] == operation["source_record_key"]
            and event["element_id"] == f"interpretation-proposal:{operation['source_record_key']}"
            and event["runner_manifest_sha256"] == operation["runner_manifest_sha256"]
            and event["model_version"] == operation["model_version"]
            and event["prompt_version"] == operation["prompt_version"]
            and event["claim_count"] == len(operation["claims"])
            and event["before_sha256"] is None
            and all(receipt_claim["extraction_run_id"] == event["run_id"]
                    for receipt_claim in event["result_receipt"]["claims"])
        )
        if not event_ok:
            _fail("INTERPRETATION_PROJECTION_EVENT_HISTORY_DRIFT", part="event")
        _validate_new_event_receipt(event)
        run_ids.add(event["run_id"])
    if len(run_ids) != 1:
        _fail("INTERPRETATION_PROJECTION_RUN_DRIFT", part="event_runs")
    return batch, events_by_element


def _compare_claims_links_and_run(
        manifest: dict[str, Any], before: dict[str, Any], after: dict[str, Any],
        events_by_element: dict[str, dict[str, Any]]
) -> tuple[int, int, str]:
    manifest_claims = _manifest_claims(manifest)
    new_interpretations = _new_rows(before, after, "interpretations")
    new_links = _new_rows(before, after, "interpretation_links")
    receipt_claims: dict[str, tuple[dict[str, Any], dict[str, Any], dict[str, Any]]] = {}
    for operation in manifest["operations"]:
        event = events_by_element[operation["element_id"]]
        claims = event["result_receipt"]["claims"]
        expected_ids = {claim["claim_id"] for claim in operation["claims"]}
        if {claim["claim_id"] for claim in claims} != expected_ids or len(claims) != len(expected_ids):
            _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="claims")
        for receipt in claims:
            receipt_claims[receipt["claim_id"]] = (operation, event, receipt)
    if len(receipt_claims) != len(manifest_claims) or len(new_interpretations) != len(manifest_claims):
        _fail("INTERPRETATION_PROJECTION_CLAIM_DRIFT", part="count")
    interpretations = {row["interpretation_id"]: row for row in new_interpretations}
    if len(interpretations) != len(new_interpretations):
        _fail("INTERPRETATION_PROJECTION_CLAIM_DRIFT", part="interpretation_id")
    expected_link_count = 0
    seen_interpretations: set[str] = set()
    for operation, claim in manifest_claims:
        receipt_entry = receipt_claims.get(claim["claim_id"])
        if receipt_entry is None:
            _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="claim_id")
        _, event, receipt = receipt_entry
        row = interpretations.get(receipt["interpretation_id"])
        if row is None:
            _fail("INTERPRETATION_PROJECTION_CLAIM_DRIFT", part="interpretation_id")
        seen_interpretations.add(row["interpretation_id"])
        try:
            confidence_ok = Decimal(row["confidence"]) == Decimal(str(claim["confidence"]))
        except InvalidOperation:
            confidence_ok = False
        expected = {
            "version": 1,
            "status": "proposed",
            "record_key": operation["source_record_key"],
            "predicate": claim["predicate"],
            "interpretation_kind": claim["interpretation_kind"],
            "schema_version": "interpretation-proposal-v1",
            "derivation_kind": "model_inference",
            "method": "model",
            "persona_bound": claim["persona_role"] == "principal",
            "extraction_run_id": event["run_id"],
            "supersedes_id": None,
            "value_sha256": proposal_canonical_sha256(claim["value"]),
            "key_matches": True,
        }
        mismatched = [field for field, wanted in expected.items() if row[field] != wanted]
        if not confidence_ok:
            mismatched.append("confidence")
        for field in ("interpretation_id", "interpretation_key", "version", "value_sha256",
                      "key_material_sha256", "extraction_run_id"):
            if receipt[field] != row[field]:
                mismatched.append(field)
        if mismatched:
            _fail("INTERPRETATION_PROJECTION_CLAIM_DRIFT", fields=sorted(set(mismatched)))
        if receipt["row_sha256"] != row["row_sha256"]:
            _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="claim_row_sha256")

        actual_links = sorted(
            (link for link in new_links if link["interpretation_id"] == row["interpretation_id"]),
            key=lambda link: link["link_ordinal"],
        )
        expected_link_count += len(claim["cited_clauses"])
        if len(actual_links) != len(claim["cited_clauses"]):
            _fail("INTERPRETATION_PROJECTION_LINK_DRIFT", part="count")
        for ordinal, (citation, link) in enumerate(zip(claim["cited_clauses"], actual_links), start=1):
            link_expected = {
                "interpretation_id": row["interpretation_id"],
                "evidence_role": "supporting",
                "link_ordinal": ordinal,
                "record_key": operation["source_record_key"],
                "clause_ordinal": citation["ordinal"],
                "verbatim_sha256": citation["verbatim_sha256"],
            }
            before_clause = [item for item in before["clauses"]
                             if item["record_key"] == operation["source_record_key"]
                             and item["clause_ordinal"] == citation["ordinal"]]
            if not before_clause:
                _fail("INTERPRETATION_PROJECTION_LINK_DRIFT", part="observation")
            expected_observation_id = max(before_clause, key=lambda item: item["version"])["observation_id"]
            link_expected["observation_id"] = expected_observation_id
            mismatched_links = [field for field, wanted in link_expected.items() if link[field] != wanted]
            if mismatched_links:
                _fail("INTERPRETATION_PROJECTION_LINK_DRIFT", fields=mismatched_links)
            observations = receipt["observations"]
            if len(observations) != len(actual_links):
                _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="observations")
            receipt_link = observations[ordinal - 1]
            for field in RECEIPT_OBSERVATION_KEYS - {"row_sha256"}:
                if receipt_link[field] != link[field]:
                    _fail("INTERPRETATION_PROJECTION_LINK_DRIFT", fields=[field])
            if receipt_link["row_sha256"] != link["row_sha256"]:
                _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="link_row_sha256")
    if seen_interpretations != set(interpretations) or len(new_links) != expected_link_count:
        _fail("INTERPRETATION_PROJECTION_LINK_DRIFT", part="unaccounted")

    run_ids = {event["run_id"] for event in events_by_element.values()}
    run_id = next(iter(run_ids))
    after_runs = _row_map(after, "extraction_runs")
    run = after_runs.get(run_id)
    if run is None:
        _fail("INTERPRETATION_PROJECTION_RUN_DRIFT", part="missing")
    operation = manifest["operations"][0]
    run_expected = {
        "run_id": run_id,
        "run_key": f"interpretation-proposal:{operation['runner_manifest_sha256']}",
        "schema_version": "interpretation-proposal-v1",
        "extractor_version": operation["model_version"],
        "profile_version": operation["prompt_version"],
        "input_sha256": operation["runner_manifest_sha256"],
    }
    if (any(row["runner_manifest_sha256"] != operation["runner_manifest_sha256"]
            or row["model_version"] != operation["model_version"]
            or row["prompt_version"] != operation["prompt_version"]
            for row in events_by_element.values())
            or any(run[field] != wanted for field, wanted in run_expected.items())):
        _fail("INTERPRETATION_PROJECTION_RUN_DRIFT", part="binding")
    new_run_ids = {row["run_id"] for row in _new_rows(before, after, "extraction_runs")}
    if new_run_ids not in ({run_id}, set()):
        _fail("INTERPRETATION_PROJECTION_RUN_DRIFT", part="unaccounted")
    return len(manifest_claims), expected_link_count, run_id


def _compare_clause_dispositions(
        manifest: dict[str, Any], before: dict[str, Any], after: dict[str, Any],
        batch: dict[str, Any], events_by_element: dict[str, dict[str, Any]], run_id: str
) -> Counter[str]:
    current: dict[tuple[str, int], dict[str, Any]] = {}
    for row in before["clauses"]:
        key = (row["record_key"], row["clause_ordinal"])
        if key not in current or row["version"] > current[key]["version"]:
            current[key] = row
    expected: dict[str, tuple[dict[str, Any], str, str]] = {}
    for operation in manifest["operations"]:
        for claim in operation["claims"]:
            for citation in claim["cited_clauses"]:
                before_row = current.get((operation["source_record_key"], citation["ordinal"]))
                if before_row is None or before_row["decided_by_kind"] != "machine":
                    _fail("INTERPRETATION_PROJECTION_DISPOSITION_DRIFT", part="before")
                disposition = ("afventer_identitet" if claim["persona_role"] == "other"
                               else "fortolkning_foreslaaet")
                existing = expected.get(before_row["observation_id"])
                if existing and existing[1] == "afventer_identitet":
                    disposition = "afventer_identitet"
                expected[before_row["observation_id"]] = (before_row, disposition, operation["element_id"])
    new_clauses = _new_rows(before, after, "clauses")
    actual = {row["observation_id"]: row for row in new_clauses}
    if len(actual) != len(new_clauses) or set(actual) != set(expected):
        _fail("INTERPRETATION_PROJECTION_DISPOSITION_DRIFT", part="set")
    receipt_rows: dict[str, dict[str, Any]] = {}
    for event in events_by_element.values():
        for item in event["result_receipt"]["clause_dispositions"]:
            if item["observation_id"] in receipt_rows:
                _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="clause_dispositions")
            receipt_rows[item["observation_id"]] = item
    if set(receipt_rows) != set(expected):
        _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="clause_dispositions")
    counts: Counter[str] = Counter()
    manifest_sha = manifest["manifest_content_sha256"]
    for observation_id, (before_row, disposition, element_id) in expected.items():
        row = actual[observation_id]
        wanted = {
            "observation_id": observation_id,
            "record_key": before_row["record_key"],
            "clause_ordinal": before_row["clause_ordinal"],
            "version": before_row["version"] + 1,
            "disposition": disposition,
            "decided_by_kind": "machine",
            "evidence_batch_id": batch["batch_id"],
            "evidence_extraction_run_id": run_id,
            "evidence_element_id": element_id,
            "evidence_manifest_sha256": manifest_sha,
        }
        mismatched = [field for field, value in wanted.items() if row[field] != value]
        if mismatched:
            _fail("INTERPRETATION_PROJECTION_DISPOSITION_DRIFT", fields=mismatched)
        receipt = receipt_rows[observation_id]
        before_receipt, written_receipt = receipt["before"], receipt["written"]
        for field in ("observation_id", "version", "disposition", "decided_by_kind", "row_sha256"):
            if before_receipt[field] != before_row[field]:
                _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="disposition_before")
            if written_receipt[field] != row[field]:
                _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="disposition_written")
        expected_evidence = {
            "batch_id": batch["batch_id"], "element_id": element_id,
            "manifest_sha256": manifest_sha, "extraction_run_id": run_id,
        }
        if written_receipt["evidence"] != expected_evidence:
            _fail("INTERPRETATION_PROJECTION_RECEIPT_INVALID", part="disposition_evidence")
        counts[disposition] += 1
    return counts


def compare_apply(manifest: Any, before: Any, after: Any,
                  expected_target_sha256: str) -> dict[str, Any]:
    validated_manifest = validate_manifest(manifest)
    validated_before = validate_projection(before)
    validated_after = validate_projection(after)
    target = _compare_source_and_target(
        validated_manifest, validated_before, validated_after, expected_target_sha256)
    _compare_neutral_surfaces(validated_before, validated_after)
    for name in ("clauses", "interpretations", "interpretation_links", "extraction_runs",
                 "authorizations", "batches"):
        _require_preserved(validated_before, validated_after, name)
    for name in ("proposal_events", "reversal_events"):
        _require_preserved(validated_before, validated_after, name,
                           "INTERPRETATION_PROJECTION_EVENT_HISTORY_DRIFT")
    if validated_before["reversal_events"] != validated_after["reversal_events"]:
        _fail("INTERPRETATION_PROJECTION_EVENT_HISTORY_DRIFT", part="reversal_events")
    _check_preexisting(validated_manifest, validated_before, validated_after)
    batch, events = _compare_batch_authorization_and_events(
        validated_manifest, validated_before, validated_after)
    claims, links, run_id = _compare_claims_links_and_run(
        validated_manifest, validated_before, validated_after, events)
    dispositions = _compare_clause_dispositions(
        validated_manifest, validated_before, validated_after, batch, events, run_id)
    return {
        "status": "match",
        "scope": RESULT_SCOPE,
        "source_id": validated_after["source_id"],
        "database_target_sha256": target,
        "manifest_content_sha256": validated_manifest["manifest_content_sha256"],
        "batch_id": batch["batch_id"],
        "counts": {
            "elements": len(validated_manifest["operations"]),
            "claims": claims,
            "links": links,
            "dispositions": dict(sorted(dispositions.items())),
        },
    }


def compare_replay(after: Any, replayed: Any, replay_authorization_id: str,
                   expected_target_sha256: str) -> dict[str, Any]:
    original = validate_projection(after)
    replay = validate_projection(replayed)
    if not _is_uuid(replay_authorization_id) or not _is_sha(expected_target_sha256):
        _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="arguments")
    if (original["source_id"] != replay["source_id"]
            or original["database_target_identity"] != replay["database_target_identity"]
            or target_sha256(replay["database_target_identity"]) != expected_target_sha256):
        _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="target")
    for key in PROJECTION_KEYS - {"authorizations"}:
        if _canon(original[key]) != _canon(replay[key]):
            _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part=key)
    original_auth = {row["authorization_id"]: row for row in original["authorizations"]}
    replay_auth = {row["authorization_id"]: row for row in replay["authorizations"]}
    if (len(original_auth) != len(original["authorizations"])
            or len(replay_auth) != len(replay["authorizations"])):
        _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="authorizations")
    for authorization_id, row in original_auth.items():
        if authorization_id not in replay_auth or _canon(row) != _canon(replay_auth[authorization_id]):
            _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="authorization_history")
    extra = [row for authorization_id, row in replay_auth.items() if authorization_id not in original_auth]
    if len(extra) != 1 or extra[0]["authorization_id"] != replay_authorization_id:
        _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="authorization_delta")
    batch_ids = {event["batch_id"] for event in original["proposal_events"]}
    if len(batch_ids) != 1:
        _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="proposal_batch")
    batch_id = next(iter(batch_ids))
    batches = [row for row in original["batches"] if row["batch_id"] == batch_id
               and row["status"] == "finalized" and row["finalized"] is True]
    if len(batches) != 1:
        _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="proposal_batch")
    original_authorization = original_auth.get(batches[0]["authorization_id"])
    if original_authorization is None:
        _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="original_authorization")
    new_authorization = extra[0]
    binding_fields = (
        "manifest_sha256", "preview_sha256", "profile_id", "profile_sha256", "principal_id",
        "expected_counts", "authorized_elements_sha256", "authorized_element_ids",
    )
    if (new_authorization["operation"] != "reimport"
            or new_authorization["status"] != "consumed"
            or new_authorization["consumed"] is not True
            or any(new_authorization[field] != original_authorization[field]
                   for field in binding_fields)):
        _fail("INTERPRETATION_PROJECTION_REPLAY_DRIFT", part="binding")
    return {
        "status": "match",
        "scope": REPLAY_SCOPE,
        "source_id": replay["source_id"],
        "database_target_sha256": expected_target_sha256,
        "batch_id": batch_id,
        "replay_authorization_id": replay_authorization_id,
    }


class UsageError(ValueError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _load_json(path: str) -> Any:
    try:
        return strict_json_loads(Path(path).expanduser().read_text(encoding="utf-8"))
    except ProjectionError:
        raise
    except (OSError, UnicodeError):
        raise UsageError("INTERPRETATION_PROJECTION_INPUT_UNREADABLE") from None


def _report_path(raw: str) -> Path:
    path = Path(raw).expanduser().absolute()
    if not path.parent.is_dir():
        raise UsageError("INTERPRETATION_PROJECTION_REPORT_DIR_MISSING")
    if path.exists() or path.is_symlink():
        raise UsageError("INTERPRETATION_PROJECTION_REPORT_EXISTS")
    return path


def _write_private(path: Path, value: dict[str, Any]) -> None:
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise UsageError("INTERPRETATION_PROJECTION_REPORT_EXISTS") from None
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))
        handle.write("\n")
    os.chmod(path, 0o600)


def _emit(value: dict[str, Any]) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mode", choices=("fresh", "replay"))
    parser.add_argument("--manifest")
    parser.add_argument("--before")
    parser.add_argument("--after")
    parser.add_argument("--replayed")
    parser.add_argument("--replay-authorization-id")
    parser.add_argument("--expect-target-sha256")
    parser.add_argument("--report")
    parser.add_argument("--print-manifest-sha256")
    args = parser.parse_args(argv)
    if args.print_manifest_sha256 is not None:
        if any((args.mode, args.manifest, args.before, args.after, args.replayed,
                args.replay_authorization_id, args.expect_target_sha256, args.report)):
            _emit({"status": "usage-error", "code": "INTERPRETATION_PROJECTION_ARGUMENTS_INVALID"})
            return 2
        try:
            value = _load_json(args.print_manifest_sha256)
            if not isinstance(value, dict):
                raise UsageError("INTERPRETATION_PROJECTION_INPUT_UNREADABLE")
            print(compute_manifest_sha256(value))
            return 0
        except ProjectionError as caught:
            _emit({"status": "no-go", "code": caught.code, "details": caught.details})
            return 1
        except UsageError as caught:
            _emit({"status": "usage-error", "code": caught.code})
            return 2
    try:
        if (args.mode is None or args.report is None or args.expect_target_sha256 is None
                or not _is_sha(args.expect_target_sha256)):
            raise UsageError("INTERPRETATION_PROJECTION_ARGUMENTS_INVALID")
        report = _report_path(args.report)
        if args.mode == "fresh":
            if (not all((args.manifest, args.before, args.after))
                    or any((args.replayed, args.replay_authorization_id))):
                raise UsageError("INTERPRETATION_PROJECTION_ARGUMENTS_INVALID")
            inputs = (_load_json(args.manifest), _load_json(args.before), _load_json(args.after))
            result = compare_apply(*inputs, args.expect_target_sha256)
        else:
            if (not all((args.after, args.replayed, args.replay_authorization_id))
                    or any((args.manifest, args.before))):
                raise UsageError("INTERPRETATION_PROJECTION_ARGUMENTS_INVALID")
            result = compare_replay(_load_json(args.after), _load_json(args.replayed),
                                    args.replay_authorization_id, args.expect_target_sha256)
    except ProjectionError as caught:
        result = {"status": "no-go", "code": caught.code, "details": caught.details}
        try:
            _write_private(report, result)
        except UsageError as usage:
            _emit({"status": "usage-error", "code": usage.code})
            return 2
        _emit(result)
        return 1
    except UsageError as caught:
        _emit({"status": "usage-error", "code": caught.code})
        return 2
    _write_private(report, result)
    _emit(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
