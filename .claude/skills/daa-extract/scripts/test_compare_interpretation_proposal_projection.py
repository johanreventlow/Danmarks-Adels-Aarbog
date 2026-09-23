"""Closed synthetic contracts for the interpretation-proposal projection."""
from __future__ import annotations

from decimal import Decimal
import copy
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compare_interpretation_proposal_projection as cp


SCRIPTS = Path(__file__).resolve().parent


def test_sql_contract_requires_one_read_only_snapshot_and_no_raw_values():
    paths = {
        "owner": SCRIPTS / "interpretation_proposal_projection.sql",
        "anon": SCRIPTS / "interpretation_proposal_anon_projection.sql",
        "driver": SCRIPTS / "interpretation_proposal_projection.psql",
        "target": SCRIPTS / "interpretation_proposal_target_identity.sql",
    }
    texts = {name: path.read_text(encoding="utf-8") for name, path in paths.items()}
    assert "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY" in texts["driver"]
    assert "SET LOCAL ROLE anon" in texts["driver"]
    assert "RESET ROLE" in texts["driver"]
    owner_include = "\\ir interpretation_proposal_projection.sql"
    for setting in ("SET LOCAL TimeZone TO 'UTC'", "SET LOCAL DateStyle TO 'ISO, YMD'",
                    "SET LOCAL IntervalStyle TO 'postgres'", "SET LOCAL extra_float_digits TO 1"):
        assert texts["driver"].find(setting) < texts["driver"].find(owner_include)
    assert "current_setting('transaction_read_only') <> 'on'" in texts["owner"]
    assert "current_setting('transaction_isolation') <> 'repeatable read'" in texts["owner"]
    assert "current_user <> 'anon'" in texts["anon"]
    for relation in ("private.interpretation", "private.interpretation_observation",
                     "private.extraction_run", "private.clause_disposition",
                     "private.reimport_authorization", "private.reimport_batch",
                     "private.reimport_event", "private.interpretation_promotion"):
        assert relation in texts["owner"]
    for forbidden in ("narrative.tekst", "'value', i.value", "::text AS value", "i.value)"):
        assert forbidden not in texts["owner"]
    # Kildetekst maa kun forlade en raekke som SHA-256: hver forekomst er hash-indpakket.
    for column in ("verbatim_text", ".tekst"):
        for index in [i for i in range(len(texts["owner"])) if texts["owner"].startswith(column, i)]:
            prefix = texts["owner"][max(0, index - 40):index]
            assert prefix.endswith("sha256(convert_to(o.") or prefix.endswith("sha256(convert_to(n"), (column, prefix)
    assert "\\ir interpretation_proposal_anon_projection.sql" in texts["driver"]
    assert "INTERPRETATION_PROJECTION_SNAPSHOT_MISMATCH" in texts["driver"]
    assert "INTERPRETATION_PROJECTION_NOT_OWNER" in texts["owner"]


def H(char: str) -> str:
    return char * 64


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
    "manifest_content_sha256", "source", "expected_counts",
    "operations", "provenance",
})
OPERATION_KEYS = frozenset({
    "element_id", "dependency_class", "source_record_key",
    "runner_manifest_sha256", "model_version", "prompt_version", "claims",
})
CLAIM_KEYS = frozenset({
    "claim_id", "predicate", "interpretation_kind", "value",
    "confidence", "cited_clauses", "persona_role",
})
CITATION_KEYS = frozenset({"ordinal", "verbatim_sha256"})


def rehash(manifest: dict) -> dict:
    manifest["manifest_content_sha256"] = cp.compute_manifest_sha256(manifest)
    return manifest


def claim(claim_id: str, value, ordinal: int, role: str = "principal") -> dict:
    return {
        "claim_id": claim_id,
        "predicate": "person.birth",
        "interpretation_kind": "fact",
        "value": value,
        "confidence": 0.9,
        "cited_clauses": [{"ordinal": ordinal, "verbatim_sha256": H("c")}],
        "persona_role": role,
    }


def manifest() -> dict:
    return rehash({
        "source": {"id": 1, "profile_id": "profile-v1", "profile_sha256": H("a")},
        "expected_counts": {
            "person_creates": 0,
            "source_evidence": 0,
            "canonical_delta": 0,
            "interpretation_proposals": 1,
        },
        "operations": [{
            "element_id": "interpretation-proposal:R1",
            "dependency_class": "interpretation_proposal",
            "source_record_key": "R1",
            "runner_manifest_sha256": H("b"),
            "model_version": "gpt-5.6-terra",
            "prompt_version": H("d"),
            "claims": [
                claim("1" * 32, "1701-01-01", 1),
                claim("2" * 32, {"raw": "gift 1702", "normalized": "gift"}, 2, "other"),
            ],
        }],
        "provenance": {
            "schema_version": "interpretation-proposal-manifest-1.0",
            "runner_manifest_sha256": H("b"),
            "eligibility_ledger_sha256": H("e"),
            "cache_files": {"cache.json": H("f")},
            "predicates_sha256": H("0"),
            "runner_contract_version": "evidence-runner-1.0",
            "denylist_version": "denylist-1",
            "persona_role_map_version": "roles-1",
            "regnskab": {"raa_claims": 2, "kontrakt_afviste": 0, "h1_afviste": 0,
                           "dubletter": 0, "ukendt_rolle": 0, "ingestible": 2},
            "h1_afviste": [],
            "dublet_claims": [],
            "ukendt_rolle_claims": [],
            "usage": {"input_tokens": 0, "output_tokens": 0,
                      "reasoning_output_tokens": 0, "cached_input_tokens": 0,
                      "cache_write_input_tokens": 0},
        },
    })


def projection() -> dict:
    return {
        "schema_version": PROJECTION_SCHEMA,
        "source_id": 1,
        "database_target_identity": {
            "database_name": "fixture", "system_identifier_sha256": H("1"),
        },
        "source_records": [{"record_key": "R1"}],
        "source_anchors": [{"record_key": "R1", "occurrence_id": "occ-1"}],
        "narrative_bindings": [],
        "narrative_sha256": [],
        "persons": [],
        "upstream_sha256": H("2"),
        "neutral_sha256": H("3"),
        "anon_sha256": H("4"),
        "clauses": [{"observation_id": "obs-1", "row_sha256": H("5")}],
        "interpretations": [],
        "interpretation_links": [],
        "extraction_runs": [{"run_id": "run-1", "row_sha256": H("6")}],
        "proposal_events": [{"event_id": "event-1", "row_sha256": H("7")}],
        "reversal_events": [],
        "authorizations": [{"authorization_id": "auth-1", "row_sha256": H("8")}],
        "batches": [{"batch_id": "batch-1", "row_sha256": H("9")}],
        "promotion_sha256": H("a"),
    }


def error(callable_, code: str):
    with pytest.raises(cp.ProjectionError) as caught:
        callable_()
    assert caught.value.code == code
    return caught.value


def test_fixture_has_exact_pinned_top_level_key_sets():
    assert set(manifest()) == MANIFEST_TOP_KEYS
    assert set(projection()) == PROJECTION_KEYS
    assert set(manifest()["operations"][0]) == OPERATION_KEYS
    assert set(manifest()["operations"][0]["claims"][0]) == CLAIM_KEYS
    assert set(manifest()["operations"][0]["claims"][0]["cited_clauses"][0]) == CITATION_KEYS


@pytest.mark.parametrize("mutate", [
    lambda value: value.update(extra=True),
    lambda value: value["source"].update(extra=True),
    lambda value: value["expected_counts"].update(extra=True),
    lambda value: value["operations"][0].update(extra=True),
    lambda value: value["operations"][0]["claims"][0].update(extra=True),
    lambda value: value["operations"][0]["claims"][0]["cited_clauses"][0].update(extra=True),
    lambda value: value["provenance"].update(extra=True),
])
def test_manifest_unknown_key_fails_closed_without_echoing_claim_value(mutate):
    value = manifest()
    secret = value["operations"][0]["claims"][0]["value"]
    mutate(value)
    rehash(value)
    caught = error(lambda: cp.validate_manifest(value), "INTERPRETATION_PROJECTION_MANIFEST_INVALID")
    assert secret not in str(caught.details)


def test_manifest_hash_mismatch_has_a_distinct_no_go_code():
    value = manifest()
    value["source"]["profile_id"] = "other"
    error(lambda: cp.validate_manifest(value), "INTERPRETATION_PROJECTION_MANIFEST_HASH_MISMATCH")


@pytest.mark.parametrize("mutate", [
    lambda value: value.update(extra=True),
    lambda value: value["database_target_identity"].update(extra=True),
])
def test_projection_unknown_key_fails_closed(mutate):
    value = projection()
    mutate(value)
    error(lambda: cp.validate_projection(value), "INTERPRETATION_PROJECTION_SHAPE_INVALID")


def test_integral_numeric_spellings_have_one_recursive_canonical_value_hash():
    values = [
        {"n": 1, "nested": [1, {"other": 1}]},
        {"n": Decimal("1.0"), "nested": [Decimal("1e0"), {"other": Decimal("1.00")}]},
        cp.strict_json_loads('{"n":1e0,"nested":[1.0,{"other":1}]}'),
    ]
    normalized = [cp.normalize_interpretation_proposal_claim_value(value) for value in values]
    assert normalized == [{"n": 1, "nested": [1, {"other": 1}]}] * 3
    assert len({cp.proposal_canonical_sha256(value) for value in values}) == 1
    assert cp.normalize_interpretation_proposal_claim_value("1.0") == "1.0"


@pytest.mark.parametrize("value", [
    Decimal("1.5"), Decimal("9007199254740992"), Decimal("-9007199254740992"),
    {"nested": Decimal("1.5")},
])
def test_non_integral_or_unsafe_numeric_value_is_rejected(value):
    error(lambda: cp.normalize_interpretation_proposal_claim_value(value),
          "INTERPRETATION_PROJECTION_MANIFEST_INVALID")


@pytest.mark.parametrize("raw", [
    '{"n":NaN}', '{"n":Infinity}', '{"n":-Infinity}', '{"n":1,"n":2}',
])
def test_strict_json_decoder_rejects_non_json_or_duplicate_numeric_inputs(raw):
    error(lambda: cp.strict_json_loads(raw), "INTERPRETATION_PROJECTION_MANIFEST_INVALID")
