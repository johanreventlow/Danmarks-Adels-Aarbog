#!/usr/bin/env python3
"""Closed, database-free contracts for interpretation-proposal projections."""
from __future__ import annotations

from decimal import Decimal, InvalidOperation
import hashlib
import json
from typing import Any, Mapping


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
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


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
                    or not isinstance(claim["confidence"], (int, float))
                    or isinstance(claim["confidence"], bool)
                    or not 0 <= float(claim["confidence"]) <= 1):
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


def validate_projection(projection: Any) -> dict[str, Any]:
    if not isinstance(projection, dict) or set(projection) != PROJECTION_KEYS:
        _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part="top")
    if projection["schema_version"] != PROJECTION_SCHEMA or not _is_plain_int(projection["source_id"]) or projection["source_id"] <= 0:
        _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part="header")
    identity = projection["database_target_identity"]
    if (not isinstance(identity, dict) or set(identity) != {"database_name", "system_identifier_sha256"}
            or not isinstance(identity["database_name"], str) or not identity["database_name"]
            or not _is_sha(identity["system_identifier_sha256"])):
        _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part="database_target_identity")
    for key in ("upstream_sha256", "neutral_sha256", "anon_sha256", "promotion_sha256"):
        if not _is_sha(projection[key]):
            _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part=key)
    for key in PROJECTION_KEYS - {"schema_version", "source_id", "database_target_identity",
                                  "upstream_sha256", "neutral_sha256", "anon_sha256", "promotion_sha256"}:
        if not isinstance(projection[key], list) or not all(isinstance(row, dict) for row in projection[key]):
            _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part=key)
    return projection


def target_sha256(identity: dict[str, Any]) -> str:
    if (not isinstance(identity, dict) or set(identity) != {"database_name", "system_identifier_sha256"}
            or not isinstance(identity["database_name"], str) or not _is_sha(identity["system_identifier_sha256"])):
        _fail("INTERPRETATION_PROJECTION_SHAPE_INVALID", part="database_target_identity")
    return hashlib.sha256(
        f"{identity['database_name']}\n{identity['system_identifier_sha256']}".encode("utf-8")
    ).hexdigest()
