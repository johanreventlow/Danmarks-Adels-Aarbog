"""Closed synthetic contracts for the interpretation-proposal projection."""
from __future__ import annotations

from decimal import Decimal
import copy
import hashlib
import json
import os
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
                    "SET LOCAL IntervalStyle TO 'postgres'", "SET LOCAL extra_float_digits TO 1",
                    "SET LOCAL bytea_output TO 'hex'"):
        assert -1 < texts["driver"].find(setting) < texts["driver"].find(owner_include)
    # Begge dele hasher x::text over hele tabeller; begge guards skal afvise en afvigende session.
    for part in ("owner", "anon"):
        for guard in ("current_setting('TimeZone') <> 'UTC'", "current_setting('extra_float_digits') <> '1'",
                      "current_setting('bytea_output') <> 'hex'"):
            assert guard in texts[part], (part, guard)
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
                {
                    **claim("2" * 32, {"raw": "gift 1702", "normalized": "gift"}, 2, "other"),
                    "cited_clauses": [
                        {"ordinal": 1, "verbatim_sha256": H("c")},
                        {"ordinal": 2, "verbatim_sha256": H("c")},
                    ],
                },
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


UUIDS = {
    "observation_1": "10000000-0000-4000-8000-000000000001",
    "observation_2": "10000000-0000-4000-8000-000000000002",
    "old_batch": "20000000-0000-4000-8000-000000000001",
    "new_batch": "20000000-0000-4000-8000-000000000002",
    "authorization": "30000000-0000-4000-8000-000000000001",
    "replay_authorization": "30000000-0000-4000-8000-000000000002",
    "principal": "40000000-0000-4000-8000-000000000001",
    "run": "50000000-0000-4000-8000-000000000001",
    "interpretation_1": "60000000-0000-4000-8000-000000000001",
    "interpretation_2": "60000000-0000-4000-8000-000000000002",
    "key_1": "70000000-0000-5000-8000-000000000001",
    "key_2": "70000000-0000-5000-8000-000000000002",
    "occurrence": "80000000-0000-4000-8000-000000000001",
}


def _clause_row(ordinal: int, version: int, disposition: str, row_hash: str,
                *, new: bool = False, manifest_sha256: str | None = None) -> dict:
    return {
        "observation_id": UUIDS[f"observation_{ordinal}"],
        "record_key": "R1",
        "clause_ordinal": ordinal,
        "version": version,
        "disposition": disposition,
        "decided_by_kind": "machine",
        "evidence_batch_id": UUIDS["new_batch" if new else "old_batch"],
        "evidence_extraction_run_id": UUIDS["run"] if new else None,
        "evidence_element_id": "interpretation-proposal:R1" if new else "clause-evidence:R1",
        "evidence_manifest_sha256": (manifest_sha256 or manifest()["manifest_content_sha256"]) if new else H("e"),
        "row_sha256": row_hash,
    }


def before() -> dict:
    value = projection()
    value.update({
        "source_anchors": [{"record_key": "R1", "occurrence_id": UUIDS["occurrence"]}],
        "clauses": [
            _clause_row(1, 1, "afventer_fortolkning", H("1")),
            _clause_row(2, 1, "afventer_fortolkning", H("2")),
        ],
        "extraction_runs": [],
        "proposal_events": [],
        "authorizations": [],
        "batches": [],
    })
    return value


def _receipt_disposition(clause: dict, *, written: bool) -> dict:
    evidence = {
        "batch_id": clause["evidence_batch_id"],
        "element_id": clause["evidence_element_id"],
        "manifest_sha256": clause["evidence_manifest_sha256"],
    }
    if written:
        evidence["extraction_run_id"] = clause["evidence_extraction_run_id"]
    else:
        evidence["clause_rules_version"] = "clause-rules-v1"
    return {
        "observation_id": clause["observation_id"],
        "version": clause["version"],
        "disposition": clause["disposition"],
        "decided_by_kind": clause["decided_by_kind"],
        "evidence": evidence,
        "decided_by": None,
        "decided_by_name": None,
        "decided_at": None,
        "created_at": "2026-09-23T00:00:00.000000Z",
        "row_sha256": clause["row_sha256"],
    }


def correctly_applied(*, principal_only: bool = False) -> dict:
    value = copy.deepcopy(before())
    m = manifest()
    if principal_only:
        m["operations"][0]["claims"] = [m["operations"][0]["claims"][0]]
        m["expected_counts"]["interpretation_proposals"] = 1
        rehash(m)
    operation = m["operations"][0]
    claims = operation["claims"]
    run = {
        "run_id": UUIDS["run"],
        "run_key": f"interpretation-proposal:{operation['runner_manifest_sha256']}",
        "schema_version": "interpretation-proposal-v1",
        "extractor_version": operation["model_version"],
        "profile_version": operation["prompt_version"],
        "input_sha256": operation["runner_manifest_sha256"],
        "row_sha256": H("3"),
    }
    interpretations = []
    links = []
    receipt_claims = []
    for index, item in enumerate(claims, start=1):
        interpretation_id = UUIDS[f"interpretation_{index}"]
        interpretation_key = UUIDS[f"key_{index}"]
        interpretation = {
            "interpretation_id": interpretation_id,
            "interpretation_key": interpretation_key,
            "version": 1,
            "status": "proposed",
            "record_key": "R1",
            "predicate": item["predicate"],
            "interpretation_kind": item["interpretation_kind"],
            "schema_version": "interpretation-proposal-v1",
            "derivation_kind": "model_inference",
            "method": "model",
            "confidence": "0.9",
            "persona_bound": item["persona_role"] == "principal",
            "extraction_run_id": UUIDS["run"],
            "supersedes_id": None,
            "value_sha256": cp.proposal_canonical_sha256(item["value"]),
            "key_material_sha256": H(str(3 + index)),
            "key_matches": True,
            "row_sha256": H(str(5 + index)),
        }
        interpretations.append(interpretation)
        receipt_links = []
        for link_ordinal, citation in enumerate(item["cited_clauses"], start=1):
            link = {
                "interpretation_id": interpretation_id,
                "observation_id": UUIDS[f"observation_{citation['ordinal']}"],
                "evidence_role": "supporting",
                "link_ordinal": link_ordinal,
                "record_key": "R1",
                "clause_ordinal": citation["ordinal"],
                "verbatim_sha256": citation["verbatim_sha256"],
                "row_sha256": H(str(7 + len(links))),
            }
            links.append(link)
            receipt_links.append({key: link[key] for key in (
                "observation_id", "clause_ordinal", "verbatim_sha256",
                "evidence_role", "link_ordinal", "row_sha256",
            )})
        receipt_claims.append({
            "claim_id": item["claim_id"],
            "interpretation_id": interpretation_id,
            "interpretation_key": interpretation_key,
            "version": 1,
            "value_sha256": interpretation["value_sha256"],
            "key_material_sha256": interpretation["key_material_sha256"],
            "row_sha256": interpretation["row_sha256"],
            "extraction_run_id": UUIDS["run"],
            "observations": receipt_links,
        })
    cited_ordinals = sorted({citation["ordinal"] for item in claims for citation in item["cited_clauses"]})
    new_clauses = []
    disposition_receipts = []
    for ordinal in cited_ordinals:
        roles = {item["persona_role"] for item in claims
                 if any(citation["ordinal"] == ordinal for citation in item["cited_clauses"])}
        disposition = "afventer_identitet" if "other" in roles else "fortolkning_foreslaaet"
        prior = value["clauses"][ordinal - 1]
        written = _clause_row(ordinal, 2, disposition, H("b" if ordinal == 1 else "c"), new=True,
                              manifest_sha256=m["manifest_content_sha256"])
        new_clauses.append(written)
        disposition_receipts.append({
            "observation_id": written["observation_id"],
            "before": _receipt_disposition(prior, written=False),
            "written": _receipt_disposition(written, written=True),
        })
    receipt = {
        "schema_version": "interpretation-proposal-result-v1",
        "claims": sorted(receipt_claims, key=lambda item: item["claim_id"]),
        "clause_dispositions": sorted(disposition_receipts, key=lambda item: item["observation_id"]),
    }
    receipt_hash = cp.proposal_canonical_sha256(receipt)
    event = {
        "event_id": 1,
        "batch_id": UUIDS["new_batch"],
        "element_id": "interpretation-proposal:R1",
        "source_record_key": "R1",
        "run_id": UUIDS["run"],
        "runner_manifest_sha256": operation["runner_manifest_sha256"],
        "model_version": operation["model_version"],
        "prompt_version": operation["prompt_version"],
        "claim_count": len(claims),
        "result_receipt": receipt,
        "result_receipt_sha256": receipt_hash,
        "before_sha256": None,
        "after_sha256": receipt_hash,
        "row_sha256": H("d"),
    }
    expected_counts = {
        key: m["expected_counts"][key]
        for key in ("person_creates", "source_evidence", "interpretation_proposals")
    }
    authorization = {
        "authorization_id": UUIDS["authorization"],
        "operation": "reimport",
        "status": "consumed",
        "consumed": True,
        "manifest_sha256": m["manifest_content_sha256"],
        "preview_sha256": H("9"),
        "profile_id": m["source"]["profile_id"],
        "profile_sha256": m["source"]["profile_sha256"],
        "principal_id": UUIDS["principal"],
        "expected_counts": expected_counts,
        "authorized_elements_sha256": H("8"),
        "authorized_element_ids": ["interpretation-proposal:R1"],
        "row_sha256": H("7"),
    }
    batch = {
        "batch_id": UUIDS["new_batch"],
        "authorization_id": UUIDS["authorization"],
        "status": "finalized",
        "finalized": True,
        "manifest_sha256": m["manifest_content_sha256"],
        "preview_sha256": H("9"),
        "profile_id": m["source"]["profile_id"],
        "profile_sha256": m["source"]["profile_sha256"],
        "principal_id": UUIDS["principal"],
        "expected_counts": expected_counts,
        "observed_counts": copy.deepcopy(expected_counts),
        "row_sha256": H("6"),
    }
    value["clauses"].extend(new_clauses)
    value["interpretations"] = interpretations
    value["interpretation_links"] = links
    value["extraction_runs"] = [run]
    value["proposal_events"] = [event]
    value["authorizations"] = [authorization]
    value["batches"] = [batch]
    return value


def principal_manifest() -> dict:
    value = manifest()
    value["operations"][0]["claims"] = [value["operations"][0]["claims"][0]]
    return rehash(value)


def _different(field: str, current):
    if field.endswith("sha256"):
        return H("f") if current != H("f") else H("e")
    if type(current) is bool:
        return not current
    if type(current) is int:
        return current + 1
    if current is None:
        return UUIDS["principal"]
    if isinstance(current, dict):
        changed = copy.deepcopy(current)
        first = next(iter(changed))
        changed[first] = changed[first] + 1 if type(changed[first]) is int else "changed"
        return changed
    if isinstance(current, list):
        return current + ["interpretation-proposal:other"]
    if field.endswith("_id") or field in {
        "interpretation_id", "interpretation_key", "observation_id", "run_id",
    }:
        return "90000000-0000-4000-8000-000000000001"
    return "changed"


def _mutate_row(after: dict, collection: str, field: str, index: int = 0) -> None:
    row = after[collection][index]
    row[field] = _different(field, row[field])


FIXTURE_PREVIEW = H("9")
FRESH_EXPECT = ("--expect-preview-sha256", FIXTURE_PREVIEW, "--expect-principal-id", UUIDS["principal"])


def compare_apply(m, b, a, target, *, preview=FIXTURE_PREVIEW, principal=UUIDS["principal"]):
    """Fixturens operatoer-forventninger; tests af selve bindingen giver dem eksplicit."""
    return cp.compare_apply(m, b, a, target, expected_preview_sha256=preview,
                            expected_principal_id=principal)


@pytest.mark.parametrize("drift", ["preview_sha256", "principal_id"])
def test_consistent_auth_and_batch_drift_is_caught_by_the_operators_expectation(drift):
    """Minor 13: autorisation og batch kan vaere enige med hinanden og stadig forkerte."""
    b, a = before(), correctly_applied()
    wrong = H("8") if drift == "preview_sha256" else "40000000-0000-4000-8000-0000000000ff"
    for collection in ("authorizations", "batches"):
        for row in a[collection]:
            if row not in b[collection]:
                row[drift] = wrong
    error(lambda: compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"])),
          "INTERPRETATION_PROJECTION_BATCH_BINDING_INVALID")


@pytest.mark.parametrize(("preview", "principal"), [
    (H("8"), UUIDS["principal"]),
    (FIXTURE_PREVIEW, "40000000-0000-4000-8000-0000000000ff"),
    ("not-a-sha", UUIDS["principal"]),
    (FIXTURE_PREVIEW, "not-a-uuid"),
])
def test_apply_requires_matching_well_formed_preview_and_principal(preview, principal):
    b = before()
    error(lambda: compare_apply(manifest(), b, correctly_applied(),
                                cp.target_sha256(b["database_target_identity"]),
                                preview=preview, principal=principal),
          "INTERPRETATION_PROJECTION_BATCH_BINDING_INVALID")


def test_two_claims_on_one_clause_write_one_identity_priority_disposition():
    result = compare_apply(manifest(), before(), correctly_applied(), cp.target_sha256(before()["database_target_identity"]))
    assert result["counts"]["claims"] == 2
    assert result["counts"]["links"] == 3
    assert result["counts"]["dispositions"] == {"afventer_identitet": 2}


def test_principal_only_claim_writes_proposed_disposition():
    result = compare_apply(principal_manifest(), before(), correctly_applied(principal_only=True),
                              cp.target_sha256(before()["database_target_identity"]))
    assert result["counts"]["dispositions"] == {"fortolkning_foreslaaet": 1}


def test_error_details_never_echo_value():
    m = manifest()
    secret = m["operations"][0]["claims"][0]["value"]
    after = correctly_applied()
    after["interpretations"][0]["value_sha256"] = H("f")
    caught = error(lambda: compare_apply(m, before(), after,
                                            cp.target_sha256(before()["database_target_identity"])),
                   "INTERPRETATION_PROJECTION_CLAIM_DRIFT")
    assert secret not in json.dumps(caught.details, ensure_ascii=False)


@pytest.mark.parametrize(("mutate", "code"), [
    (lambda m, b, a, target: (m["source"].__setitem__("id", 2), rehash(m)),
     "INTERPRETATION_PROJECTION_SOURCE_MISMATCH"),
    (lambda m, b, a, target: target.__setitem__(0, H("f")),
     "INTERPRETATION_PROJECTION_TARGET_MISMATCH"),
    (lambda m, b, a, target: a.__setitem__("upstream_sha256", H("f")),
     "INTERPRETATION_PROJECTION_UPSTREAM_DRIFT"),
    (lambda m, b, a, target: a.__setitem__("neutral_sha256", H("f")),
     "INTERPRETATION_PROJECTION_CANONICAL_DRIFT"),
    (lambda m, b, a, target: a.__setitem__("anon_sha256", H("f")),
     "INTERPRETATION_PROJECTION_ANON_DRIFT"),
    (lambda m, b, a, target: a.__setitem__("promotion_sha256", H("f")),
     "INTERPRETATION_PROJECTION_PROMOTION_DRIFT"),
])
def test_apply_header_and_hash_drift_codes(mutate, code):
    m, b, a = manifest(), before(), correctly_applied()
    target = [cp.target_sha256(b["database_target_identity"])]
    mutate(m, b, a, target)
    error(lambda: compare_apply(m, b, a, target[0]), code)


@pytest.mark.parametrize("name", [
    "source_records", "source_anchors", "narrative_bindings", "narrative_sha256", "persons",
])
def test_each_neutral_list_drift_has_one_code(name):
    after = correctly_applied()
    after[name] = copy.deepcopy(after[name]) + [copy.deepcopy(after[name][0])] if after[name] else [{
        "narrative_bindings": {"record_key": "R1", "narrative_id": 1, "status": "published"},
        "narrative_sha256": {"narrative_id": 1, "sha256": H("f")},
        "persons": {"person_id": 1},
    }[name]]
    error(lambda: compare_apply(manifest(), before(), after,
                                   cp.target_sha256(before()["database_target_identity"])),
          "INTERPRETATION_PROJECTION_NEUTRAL_LIST_DRIFT")


@pytest.mark.parametrize("preexisting", ["event", "interpretation"])
def test_preexisting_target_fails_closed(preexisting):
    b = before()
    after = correctly_applied()
    if preexisting == "event":
        b["proposal_events"] = [copy.deepcopy(after["proposal_events"][0])]
    else:
        # Samme nøgle som en NY fortolkning, men en ældre række (andet id).
        b["interpretations"] = [dict(copy.deepcopy(after["interpretations"][0]),
                                     interpretation_id="90000000-0000-4000-8000-00000000000f")]
        after["interpretations"].append(copy.deepcopy(b["interpretations"][0]))
    error(lambda: compare_apply(manifest(), b, after,
                                   cp.target_sha256(b["database_target_identity"])),
          "INTERPRETATION_PROJECTION_PREEXISTING_TARGET")


def test_foreign_row_drift_is_not_hidden_by_expected_delta():
    b, a = before(), correctly_applied()
    foreign = copy.deepcopy(a["interpretations"][0])
    foreign["interpretation_id"] = "90000000-0000-4000-8000-000000000002"
    foreign["interpretation_key"] = "90000000-0000-5000-8000-000000000003"
    foreign["row_sha256"] = H("e")
    b["interpretations"].append(copy.deepcopy(foreign))
    a["interpretations"].append(copy.deepcopy(foreign))
    a["interpretations"][-1]["row_sha256"] = H("f")
    error(lambda: compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"])),
          "INTERPRETATION_PROJECTION_FOREIGN_DRIFT")


ROW_FIELD_CODES = [
    ("interpretations", field, "INTERPRETATION_PROJECTION_RECEIPT_INVALID" if field == "row_sha256"
     else "INTERPRETATION_PROJECTION_CLAIM_DRIFT")
    for field in (
        "interpretation_id", "interpretation_key", "version", "status", "record_key", "predicate",
        "interpretation_kind", "schema_version", "derivation_kind", "method", "confidence",
        "persona_bound", "extraction_run_id", "supersedes_id", "value_sha256",
        "key_material_sha256", "key_matches", "row_sha256",
    )
] + [
    ("interpretation_links", field, "INTERPRETATION_PROJECTION_RECEIPT_INVALID" if field == "row_sha256"
     else "INTERPRETATION_PROJECTION_LINK_DRIFT")
    for field in (
        "interpretation_id", "observation_id", "evidence_role", "link_ordinal", "record_key",
        "clause_ordinal", "verbatim_sha256", "row_sha256",
    )
] + [
    ("extraction_runs", field, "INTERPRETATION_PROJECTION_RUN_DRIFT")
    for field in ("run_id", "run_key", "schema_version", "extractor_version", "profile_version",
                  "input_sha256")
] + [
    ("extraction_runs", "row_sha256", "INTERPRETATION_PROJECTION_SHAPE_INVALID")
] + [
    ("clauses", field, "INTERPRETATION_PROJECTION_RECEIPT_INVALID" if field == "row_sha256"
     else "INTERPRETATION_PROJECTION_DISPOSITION_DRIFT")
    for field in (
        "observation_id", "record_key", "clause_ordinal", "version", "disposition", "decided_by_kind",
        "evidence_batch_id", "evidence_extraction_run_id", "evidence_element_id",
        "evidence_manifest_sha256", "row_sha256",
    )
] + [
    ("proposal_events", field, "INTERPRETATION_PROJECTION_SHAPE_INVALID"
     if field in {"event_id", "row_sha256"}
     else "INTERPRETATION_PROJECTION_RECEIPT_INVALID"
     if field in {"result_receipt", "result_receipt_sha256", "after_sha256"}
     else "INTERPRETATION_PROJECTION_BATCH_BINDING_INVALID" if field == "batch_id"
     else "INTERPRETATION_PROJECTION_EVENT_HISTORY_DRIFT")
    for field in (
        "event_id", "batch_id", "element_id", "source_record_key", "run_id",
        "runner_manifest_sha256", "model_version", "prompt_version", "claim_count",
        "result_receipt", "result_receipt_sha256", "before_sha256", "after_sha256", "row_sha256",
    )
] + [
    ("authorizations", field, "INTERPRETATION_PROJECTION_SHAPE_INVALID"
     if field in {"authorized_elements_sha256", "row_sha256"}
     else "INTERPRETATION_PROJECTION_BATCH_BINDING_INVALID")
    for field in (
        "authorization_id", "operation", "status", "consumed", "manifest_sha256", "preview_sha256",
        "profile_id", "profile_sha256", "principal_id", "expected_counts",
        "authorized_elements_sha256", "authorized_element_ids", "row_sha256",
    )
] + [
    ("batches", field, "INTERPRETATION_PROJECTION_SHAPE_INVALID"
     if field == "row_sha256" else "INTERPRETATION_PROJECTION_BATCH_BINDING_INVALID")
    for field in (
        "batch_id", "authorization_id", "status", "finalized", "manifest_sha256", "preview_sha256",
        "profile_id", "profile_sha256", "principal_id", "expected_counts", "observed_counts", "row_sha256",
    )
]


@pytest.mark.parametrize(("collection", "field", "code"), ROW_FIELD_CODES)
def test_every_projection_row_field_mutation_has_a_stable_code(collection, field, code):
    b, a = before(), correctly_applied()
    index = 2 if collection == "clauses" else 0
    if code == "INTERPRETATION_PROJECTION_SHAPE_INVALID":
        a[collection][index][field] = "invalid"
    else:
        _mutate_row(a, collection, field, index)
    error(lambda: compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"])), code)


@pytest.mark.parametrize("field", ["row_sha256", "value_sha256", "interpretation_id"])
def test_receipt_claim_mutations_are_receipt_invalid(field):
    b, a = before(), correctly_applied()
    a["proposal_events"][0]["result_receipt"]["claims"][0][field] = _different(
        field, a["proposal_events"][0]["result_receipt"]["claims"][0][field])
    error(lambda: compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"])),
          "INTERPRETATION_PROJECTION_RECEIPT_INVALID")


def test_event_and_reversal_history_must_be_append_only_and_exact():
    b, a = before(), correctly_applied()
    a["reversal_events"].append({
        "event_id": 2, "batch_id": UUIDS["new_batch"], "element_id": "reversal:R1",
        "source_record_key": "R1", "before_sha256": H("1"), "after_sha256": H("2"),
        "row_sha256": H("3"),
    })
    error(lambda: compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"])),
          "INTERPRETATION_PROJECTION_EVENT_HISTORY_DRIFT")


SAMPLE_ROWS = {
    "narrative_bindings": {"record_key": "R1", "narrative_id": 1, "status": "published"},
    "narrative_sha256": {"narrative_id": 1, "sha256": H("4")},
    "persons": {"person_id": 1},
    "reversal_events": {"event_id": 2, "batch_id": UUIDS["old_batch"], "element_id": "reversal:R1",
                        "source_record_key": "R1", "before_sha256": H("1"), "after_sha256": H("2"),
                        "row_sha256": H("3")},
}


SHAPE_LEVELS = [
    ("source_records",), ("source_anchors",), ("narrative_bindings",), ("narrative_sha256",),
    ("persons",), ("clauses",), ("interpretations",), ("interpretation_links",),
    ("extraction_runs",), ("proposal_events",), ("reversal_events",),
    ("authorizations",), ("batches",),
]


@pytest.mark.parametrize("path", SHAPE_LEVELS)
@pytest.mark.parametrize("change", ["unknown", "missing"])
def test_unknown_or_missing_projection_key_at_every_row_level_is_shape_invalid(path, change):
    value = correctly_applied()
    if not value[path[0]]:
        value[path[0]].append(copy.deepcopy(SAMPLE_ROWS[path[0]]))
    cp.validate_projection(value)
    row = value[path[0]][0]
    if change == "unknown":
        row["extra"] = True
    else:
        row.pop(next(iter(row)))
    error(lambda: cp.validate_projection(value), "INTERPRETATION_PROJECTION_SHAPE_INVALID")


@pytest.mark.parametrize("part", [
    "receipt", "receipt_claim", "receipt_observation", "receipt_disposition",
    "receipt_before", "receipt_written", "receipt_evidence",
])
@pytest.mark.parametrize("change", ["unknown", "missing"])
def test_unknown_or_missing_receipt_key_at_every_level_is_shape_invalid(part, change):
    value = correctly_applied()
    receipt = value["proposal_events"][0]["result_receipt"]
    targets = {
        "receipt": receipt,
        "receipt_claim": receipt["claims"][0],
        "receipt_observation": receipt["claims"][0]["observations"][0],
        "receipt_disposition": receipt["clause_dispositions"][0],
        "receipt_before": receipt["clause_dispositions"][0]["before"],
        "receipt_written": receipt["clause_dispositions"][0]["written"],
        "receipt_evidence": receipt["clause_dispositions"][0]["written"]["evidence"],
    }
    target = targets[part]
    if change == "unknown":
        target["extra"] = True
    else:
        target.pop(next(iter(target)))
    error(lambda: cp.validate_projection(value), "INTERPRETATION_PROJECTION_SHAPE_INVALID")


def replayed() -> dict:
    value = correctly_applied()
    replay = copy.deepcopy(value["authorizations"][0])
    replay["authorization_id"] = UUIDS["replay_authorization"]
    replay["row_sha256"] = H("f")
    value["authorizations"].append(replay)
    return value


def test_replay_accepts_only_one_consumed_authorization_delta():
    after = correctly_applied()
    result = cp.compare_replay(after, replayed(), UUIDS["replay_authorization"],
                               cp.target_sha256(after["database_target_identity"]))
    assert result == {
        "status": "match",
        "scope": "interpretation-proposal-replay-v1",
        "source_id": 1,
        "database_target_sha256": cp.target_sha256(after["database_target_identity"]),
        "batch_id": UUIDS["new_batch"],
        "replay_authorization_id": UUIDS["replay_authorization"],
    }


@pytest.mark.parametrize("mutate", [
    lambda value: value["authorizations"].append(copy.deepcopy(value["authorizations"][-1])),
    lambda value: value["authorizations"][-1].__setitem__("profile_id", "wrong"),
    lambda value: value.__setitem__("neutral_sha256", H("f")),
])
def test_replay_rejects_extra_authorization_wrong_binding_and_non_authorization_delta(mutate):
    after, value = correctly_applied(), replayed()
    mutate(value)
    error(lambda: cp.compare_replay(after, value, UUIDS["replay_authorization"],
                                    cp.target_sha256(after["database_target_identity"])),
          "INTERPRETATION_PROJECTION_REPLAY_DRIFT")


def _write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


def test_cli_fresh_match_writes_private_report_and_prints_only_sanitized_json(tmp_path, capsys):
    paths = {name: tmp_path / f"{name}.json" for name in ("manifest", "before", "after")}
    _write_json(paths["manifest"], manifest())
    _write_json(paths["before"], before())
    _write_json(paths["after"], correctly_applied())
    report = tmp_path / "report.json"
    exit_code = cp.main([
        "--mode", "fresh", *FRESH_EXPECT, "--manifest", str(paths["manifest"]), "--before", str(paths["before"]),
        "--after", str(paths["after"]), "--expect-target-sha256",
        cp.target_sha256(before()["database_target_identity"]), "--report", str(report),
    ])
    terminal = json.loads(capsys.readouterr().out)
    assert exit_code == 0 and terminal["status"] == "match"
    assert json.loads(report.read_text(encoding="utf-8"))["status"] == "match"
    assert os.stat(report).st_mode & 0o777 == 0o600


def _file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_cli_reports_bind_the_exact_input_file_bytes_so_replay_chains_to_fresh(tmp_path, capsys):
    """Minor 12: en replay-rapport skal kunne kaedes til den fresh-rapport, hvis after den genbrugte."""
    paths = {name: tmp_path / f"{name}.json" for name in ("manifest", "before", "after", "replayed")}
    _write_json(paths["manifest"], manifest())
    _write_json(paths["before"], before())
    # Bevidst ikke-kanonisk formatering: hashen er over filens bytes, ikke over en re-serialisering.
    paths["after"].write_text(json.dumps(correctly_applied(), indent=1) + "\n", encoding="utf-8")
    _write_json(paths["replayed"], replayed())
    target = cp.target_sha256(before()["database_target_identity"])
    fresh_report, replay_report = tmp_path / "fresh.json", tmp_path / "replay.json"
    assert cp.main([
        "--mode", "fresh", *FRESH_EXPECT, "--manifest", str(paths["manifest"]), "--before", str(paths["before"]),
        "--after", str(paths["after"]), "--expect-target-sha256", target, "--report", str(fresh_report),
    ]) == 0
    assert cp.main([
        "--mode", "replay", "--after", str(paths["after"]), "--replayed", str(paths["replayed"]),
        "--replay-authorization-id", UUIDS["replay_authorization"],
        "--expect-target-sha256", target, "--report", str(replay_report),
    ]) == 0
    capsys.readouterr()
    fresh = json.loads(fresh_report.read_text(encoding="utf-8"))
    replay = json.loads(replay_report.read_text(encoding="utf-8"))
    assert fresh["input_file_sha256"] == {
        "manifest": _file_sha256(paths["manifest"]),
        "before": _file_sha256(paths["before"]),
        "after": _file_sha256(paths["after"]),
    }
    assert replay["input_file_sha256"] == {
        "after": _file_sha256(paths["after"]),
        "replayed": _file_sha256(paths["replayed"]),
    }
    assert replay["input_file_sha256"]["after"] == fresh["input_file_sha256"]["after"]


def test_cli_no_go_report_also_names_its_input_files(tmp_path, capsys):
    paths = {name: tmp_path / f"{name}.json" for name in ("after", "replayed")}
    _write_json(paths["after"], correctly_applied())
    value = replayed()
    value["neutral_sha256"] = H("f")
    _write_json(paths["replayed"], value)
    report = tmp_path / "replay-no-go.json"
    assert cp.main([
        "--mode", "replay", "--after", str(paths["after"]), "--replayed", str(paths["replayed"]),
        "--replay-authorization-id", UUIDS["replay_authorization"],
        "--expect-target-sha256", cp.target_sha256(before()["database_target_identity"]),
        "--report", str(report),
    ]) == 1
    capsys.readouterr()
    stored = json.loads(report.read_text(encoding="utf-8"))
    assert stored["status"] == "no-go"
    assert stored["input_file_sha256"] == {
        "after": _file_sha256(paths["after"]), "replayed": _file_sha256(paths["replayed"]),
    }


@pytest.mark.parametrize("variant", ["fresh_missing", "fresh_malformed", "replay_extra"])
def test_cli_fresh_requires_and_replay_refuses_operator_expectations(tmp_path, capsys, variant):
    path = tmp_path / "x.json"
    _write_json(path, before())
    target = cp.target_sha256(before()["database_target_identity"])
    if variant == "replay_extra":
        argv = ["--mode", "replay", "--after", str(path), "--replayed", str(path),
                "--replay-authorization-id", UUIDS["replay_authorization"], *FRESH_EXPECT]
    else:
        expect = () if variant == "fresh_missing" else (
            "--expect-preview-sha256", "ABC", "--expect-principal-id", UUIDS["principal"])
        argv = ["--mode", "fresh", "--manifest", str(path), "--before", str(path),
                "--after", str(path), *expect]
    report = tmp_path / "report.json"
    assert cp.main([*argv, "--expect-target-sha256", target, "--report", str(report)]) == 2
    assert json.loads(capsys.readouterr().out)["code"] == "INTERPRETATION_PROJECTION_ARGUMENTS_INVALID"
    assert not report.exists()


def test_cli_refuses_existing_report_and_prints_manifest_hash(tmp_path, capsys):
    manifest_path = tmp_path / "manifest.json"
    _write_json(manifest_path, manifest())
    assert cp.main(["--print-manifest-sha256", str(manifest_path)]) == 0
    assert capsys.readouterr().out.strip() == cp.compute_manifest_sha256(
        cp.strict_json_loads(manifest_path.read_text(encoding="utf-8")))
    report = tmp_path / "exists.json"
    report.write_text("keep", encoding="utf-8")
    assert cp.main([
        "--mode", "fresh", *FRESH_EXPECT, "--manifest", str(manifest_path), "--before", str(manifest_path),
        "--after", str(manifest_path), "--expect-target-sha256", H("a"), "--report", str(report),
    ]) == 2
    assert json.loads(capsys.readouterr().out)["code"] == "INTERPRETATION_PROJECTION_REPORT_EXISTS"
    assert report.read_text(encoding="utf-8") == "keep"


def test_cli_no_go_exits_one_and_writes_same_sanitized_report(tmp_path, capsys):
    paths = {name: tmp_path / f"{name}.json" for name in ("manifest", "before", "after")}
    _write_json(paths["manifest"], manifest())
    _write_json(paths["before"], before())
    after = correctly_applied()
    after["neutral_sha256"] = H("f")
    _write_json(paths["after"], after)
    report = tmp_path / "no-go.json"
    assert cp.main([
        "--mode", "fresh", *FRESH_EXPECT, "--manifest", str(paths["manifest"]), "--before", str(paths["before"]),
        "--after", str(paths["after"]), "--expect-target-sha256",
        cp.target_sha256(before()["database_target_identity"]), "--report", str(report),
    ]) == 1
    terminal = json.loads(capsys.readouterr().out)
    stored = json.loads(report.read_text(encoding="utf-8"))
    assert terminal == stored == {
        "status": "no-go", "code": "INTERPRETATION_PROJECTION_CANONICAL_DRIFT", "details": {"part": "neutral_sha256"},
        "input_file_sha256": {name: _file_sha256(path) for name, path in paths.items()},
    }


def test_manifest_hash_follows_the_builders_ordinary_float_parse():
    """Review I3: a builder manifest carrying confidence 1.0 must hash as the builder did."""
    m = manifest()
    m["operations"][0]["claims"][0]["confidence"] = 1.0
    body = {key: value for key, value in m.items() if key != "manifest_content_sha256"}
    m["manifest_content_sha256"] = hashlib.sha256(json.dumps(
        body, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    reparsed = cp.strict_json_loads(json.dumps(m))
    assert cp.validate_manifest(reparsed) is reparsed


def test_rows_outside_accepted_anchors_may_lack_record_key():
    """Review I4: a foreign, un-anchored clause/link/interpretation must not break the shape."""
    b, a = before(), correctly_applied()
    for projection_value in (b, a):
        foreign_clause = dict(projection_value["clauses"][0], record_key=None,
                              observation_id="90000000-0000-4000-8000-00000000000a")
        projection_value["clauses"].append(foreign_clause)
        projection_value["interpretations"].append(dict(
            a["interpretations"][0], interpretation_id="90000000-0000-4000-8000-00000000000b",
            interpretation_key="90000000-0000-4000-8000-00000000000c", record_key=None,
            key_material_sha256=None, key_matches=False, extraction_run_id=None))
        projection_value["interpretation_links"].append(dict(
            a["interpretation_links"][0], interpretation_id="90000000-0000-4000-8000-00000000000b",
            record_key=None))
    result = compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"]))
    assert result["status"] == "match"


def test_before_disposition_from_a_prior_proposal_is_accepted():
    """Review I5: the writer accepts any trigger-valid machine before-row, incl. one with
    extraction_run_id and without clause_rules_version."""
    value = correctly_applied()
    before_state = value["proposal_events"][0]["result_receipt"]["clause_dispositions"][0]["before"]
    before_state["evidence"] = {"batch_id": UUIDS["old_batch"], "element_id": "interpretation-proposal:R1",
                                "manifest_sha256": H("e"), "extraction_run_id": UUIDS["run"]}
    assert cp.validate_projection(value) is value


def test_machine_disposition_states_never_carry_a_name():
    """Review 9: the embedded disposition receipt must not export a decider name."""
    value = correctly_applied()
    value["proposal_events"][0]["result_receipt"]["clause_dispositions"][0]["written"]["decided_by_name"] = "Navn"
    error(lambda: cp.validate_projection(value), "INTERPRETATION_PROJECTION_SHAPE_INVALID")


def test_unrelated_preexisting_interpretation_on_same_record_predicate_is_not_a_target():
    """Review I6: only a collision with a NEW interpretation key is a preexisting target."""
    b, a = before(), correctly_applied()
    old = dict(a["interpretations"][0], interpretation_id="90000000-0000-4000-8000-00000000000d",
               interpretation_key="90000000-0000-4000-8000-00000000000e", row_sha256=H("0"))
    b["interpretations"].append(old)
    a["interpretations"].append(copy.deepcopy(old))
    result = compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"]))
    assert result["status"] == "match"


def test_sql_python_golden_vectors():
    """Review I7: the same constants are pinned in tests/sql/test-interpretation-proposal.sql."""
    vectors = [
        ('{"composed":"\u00e5","decomposed":"a\u030a"}', "proposal",
         '{"composed":"\u00e5","decomposed":"a\u030a"}',
         "79d313486ba5f3595e187ee1468b7371307aabb9d0e010f04ffa0a21e8f66b98"),
        ('{"q":"\\"","b":"\\\\","ctl":"\\b\\t\\n\\f\\r\\u0001\\u001f","astral":"\U0001F600"}', "proposal",
         '{"astral":"\U0001F600","b":"\\\\","ctl":"\\b\\t\\n\\f\\r\\u0001\\u001f","q":"\\""}',
         "a2c3d9789f87d11efa220282937d757adfb14e0266f8b4367d04d9b067dc8320"),
        ("[9223372036854775807,-9223372036854775808,0,true,false,null]", "internal",
         "[9223372036854775807,-9223372036854775808,0,true,false,null]",
         "de9f96b75b08cb3b032d8c5ff12350e1cd281b929f81ca5b6512cbec0ddc4ef3"),
        ('{"z":{"b":1,"a":[{"y":2,"x":1}]},"A":"\u00c6"}', "proposal",
         '{"A":"\u00c6","z":{"a":[{"x":1,"y":2}],"b":1}}',
         "f3147aad416985003f3f114ea73dfc477e589e6640755cd314df38cc74fee826"),
    ]
    for raw, kind, canonical, sha in vectors:
        parsed = cp.strict_json_loads(raw)
        data = (cp.proposal_canonical_bytes(parsed) if kind == "proposal"
                else cp._canon(parsed).encode("utf-8"))
        assert data.decode("utf-8") == canonical
        assert hashlib.sha256(data).hexdigest() == sha


# ---- Trin 6a, Task 13 (R13-c; spec §4.4 pkt. 6): nøgleversion pr. kvittering ------------------------------
HISTORIC = {
    "batch": "20000000-0000-4000-8000-0000000000a1",
    "run": "50000000-0000-4000-8000-0000000000a1",
    "interpretation_v1": "60000000-0000-4000-8000-0000000000a1",
    "interpretation_v2": "60000000-0000-4000-8000-0000000000a2",
    "key": "70000000-0000-5000-8000-0000000000a1",
}


def _historic_v1_proposal(*, key_matches: bool) -> tuple[dict, list[dict]]:
    """En tidligere forslags-event (key_version 1) på R0 og dens fortolkning: version 1 foreslået og version 2
    forældet af en kildetekst-revision. Projektionen genberegner begge rækker med v1-funktionen; en projektion, der
    genberegnede mod den reviderede tekst, ville give key_matches false."""
    rows = []
    for version, status, interpretation_id, supersedes in (
            (1, "proposed", HISTORIC["interpretation_v1"], None),
            (2, "superseded", HISTORIC["interpretation_v2"], HISTORIC["interpretation_v1"])):
        rows.append({
            "interpretation_id": interpretation_id, "interpretation_key": HISTORIC["key"], "version": version,
            "status": status, "record_key": "R0", "predicate": "person.birth", "interpretation_kind": "fact",
            "schema_version": "interpretation-proposal-v1", "derivation_kind": "model_inference", "method": "model",
            "confidence": "0.9", "persona_bound": True, "extraction_run_id": HISTORIC["run"],
            "supersedes_id": supersedes, "value_sha256": H("a"), "key_material_sha256": H("b"),
            "key_matches": key_matches, "row_sha256": H("c" if version == 1 else "d"),
        })
    receipt = {
        "schema_version": "interpretation-proposal-result-v1",
        "claims": [{
            "claim_id": "a" * 32, "interpretation_id": HISTORIC["interpretation_v1"],
            "interpretation_key": HISTORIC["key"], "version": 1, "value_sha256": H("a"),
            "key_material_sha256": H("b"), "row_sha256": H("c"), "extraction_run_id": HISTORIC["run"],
            "observations": [],
        }],
        "clause_dispositions": [],
    }
    event = {
        "event_id": 1, "batch_id": HISTORIC["batch"], "element_id": "interpretation-proposal:R0",
        "source_record_key": "R0", "run_id": HISTORIC["run"], "runner_manifest_sha256": H("1"),
        "model_version": "gpt-5.6-terra", "prompt_version": H("2"), "claim_count": 1,
        "result_receipt": receipt, "result_receipt_sha256": cp.proposal_canonical_sha256(receipt),
        "before_sha256": None, "after_sha256": cp.proposal_canonical_sha256(receipt), "row_sha256": H("3"),
    }
    return event, rows


def _with_historic_v1(*, key_matches: bool) -> tuple[dict, dict]:
    b, a = before(), correctly_applied()
    event, rows = _historic_v1_proposal(key_matches=key_matches)
    for value in (b, a):
        value["proposal_events"].insert(0, copy.deepcopy(event))
        value["interpretations"] = copy.deepcopy(rows) + value["interpretations"]
    # Det nye forslags event-id følger efter det historiske.
    a["proposal_events"][-1]["event_id"] = 2
    return b, a


def test_v1_and_v2_proposals_both_keep_key_matches():
    """Et historisk v1-forslag (forældet af en revision) og et nyt v2-forslag: begge nøgler genberegnes efter
    kvitteringens version, så alle rækker har key_matches true og det nye forslags nøglemateriale er kvitteringens."""
    b, a = _with_historic_v1(key_matches=True)
    new = a["interpretations"][2:]
    receipt = {c["interpretation_key"]: c for c in a["proposal_events"][-1]["result_receipt"]["claims"]}
    assert all(row["key_matches"] for row in a["interpretations"])
    assert all(row["key_material_sha256"] == receipt[row["interpretation_key"]]["key_material_sha256"] for row in new)
    result = compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"]))
    assert result["status"] == "match"


def test_v1_key_recomputed_against_revised_text_is_a_key_mismatch():
    """Negativt: genberegnes den historiske v1-nøgle mod den reviderede tekst (v2 med den gældende tekstversion),
    rammer den ikke nøglen. Komparatoren afviser, selv om rækken er ens før og efter."""
    b, a = _with_historic_v1(key_matches=False)
    caught = error(lambda: compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"])),
                   "INTERPRETATION_PROJECTION_KEY_MISMATCH")
    assert caught.details == {"part": "before", "rows": 2}


def test_new_v2_proposal_recomputed_as_v1_is_claim_drift():
    """Negativt for det nye forslag: en projektion, der genberegnede v2-nøglen med v1-funktionen, giver et andet
    nøglemateriale end kvitteringens og key_matches false."""
    b, a = _with_historic_v1(key_matches=True)
    a["interpretations"][2]["key_matches"] = False
    a["interpretations"][2]["key_material_sha256"] = H("e")
    caught = error(lambda: compare_apply(manifest(), b, a, cp.target_sha256(b["database_target_identity"])),
                   "INTERPRETATION_PROJECTION_CLAIM_DRIFT")
    assert caught.details["fields"] == ["key_matches", "key_material_sha256"]
