from __future__ import annotations

import pytest

from evidence_phase_artifact_ledger import (
    LedgerError,
    RECEIPT_ADAPTERS,
    adapter_sha256,
    seal_ledger,
    validate_catalog,
    validate_ledger,
)


def sealed_unbound_phase_with(*, contribution_sha256: str) -> dict:
    return seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "task25.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-production-write-manifest-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": "task25-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                    "contribution_sha256": contribution_sha256,
                }
            ],
        }
    )


def test_audit_input_ledger_has_no_contribution_hash_until_projection_is_complete():
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "task25.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-production-write-manifest-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": "task25-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "mechanically_bound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    assert validate_ledger(ledger)[0].phase_id == "task25"


def test_catalog_rejects_an_undeclared_artifact_role_for_task25():
    catalog = (
        {
            "schema_version": "daa-evidence-phase-artifact-catalog-v1",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "task25.json",
                            "schema_version": "1939-v50-production-write-manifest-v1",
                            "required": True,
                        },
                        {
                            "role": "unexpected",
                            "path": "unexpected.json",
                            "schema_version": "synthetic-v1",
                            "required": True,
                        },
                    ],
                    "adapter_id": "task25-v1",
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_CONTRACT_INVALID"):
        validate_catalog(catalog)


def test_catalog_rejects_a_manifest_receipt_schema_swap_for_task25():
    catalog = {
        "schema_version": "daa-evidence-phase-artifact-catalog-v1",
        "phases": [
            {
                "phase_id": "task25",
                "sequence": 1,
                "adapter_id": "task25-v1",
                "projection_evidence": "afterdocumented_unbound",
                "authorisation_evidence": "afterdocumented_authorisation_gap",
                "artifacts": [
                    {"role": "manifest", "path": "manifest.json", "schema_version": "daa-evidence-phase-receipt-task25-v1", "required": True},
                    {"role": "receipt", "path": "receipt.json", "schema_version": "1939-v50-production-write-manifest-v1", "required": True},
                ],
            }
        ],
    }

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_CONTRACT_INVALID"):
        validate_catalog(catalog)


def test_direct_ledger_rejects_a_well_formed_noncomposite_adapter_hash():
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "synthetic",
                    "sequence": 1,
                    "artifacts": [
                        {"role": "manifest", "path": "synthetic.json", "sha256": "a" * 64, "schema_version": "synthetic-v1", "required": True}
                    ],
                    "adapter_id": "synthetic-v1",
                    "adapter_sha256": "f" * 64,
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_LEDGER_ADAPTER_HASH_INVALID"):
        validate_ledger(ledger)


def test_direct_ledger_rejects_an_undeclared_task25_role_before_audit_or_projection():
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {"role": "manifest", "path": "manifest.json", "sha256": "a" * 64, "schema_version": "1939-v50-production-write-manifest-v1", "required": True},
                        {"role": "unexpected", "path": "unexpected.json", "sha256": "b" * 64, "schema_version": "synthetic-v1", "required": True},
                    ],
                    "adapter_id": "task25-v1",
                    "adapter_sha256": "f" * 64,
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_CONTRACT_INVALID"):
        validate_ledger(ledger)


def test_reconciliation_ledger_rejects_an_unbound_phase_that_claims_a_contribution():
    ledger = sealed_unbound_phase_with(contribution_sha256="c" * 64)

    with pytest.raises(
        LedgerError,
        match="EVIDENCE_RECONCILIATION_LEDGER_EVIDENCE_INVALID",
    ):
        validate_ledger(ledger)


def test_reconciliation_requires_a_contribution_hash_for_every_mechanically_bound_phase():
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "task25.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-production-write-manifest-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": "task25-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "mechanically_bound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_INCOMPLETE"):
        validate_ledger(ledger, require_contribution_hashes=True)


def test_ledger_rejects_artifacts_with_the_same_normalized_relative_path():
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "task25.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-production-write-manifest-v1",
                            "required": True,
                        },
                        {
                            "role": "audit",
                            "path": "./task25.json",
                            "sha256": "b" * 64,
                            "schema_version": "daa-evidence-phase-audit-v1",
                            "required": True,
                        },
                    ],
                    "adapter_id": "task25-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "mechanically_bound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(
        LedgerError,
        match="EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_DUPLICATE",
    ):
        validate_ledger(ledger)


def test_ledger_rejects_a_nul_artifact_path_before_path_resolution():
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "nul\x00artifact.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-production-write-manifest-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": "task25-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID"):
        validate_ledger(ledger)


def test_ledger_requires_a_hash_declared_production_target_for_phase_b():
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "phase-b",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "phase-b.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-narrative-replacement-manifest-v2",
                            "required": True,
                        }
                    ],
                    "adapter_id": "phase-b-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_LEDGER_PHASE_INVALID"):
        validate_ledger(ledger)


@pytest.mark.parametrize(
    ("adapter_id", "manifest_schema", "receipt_schema", "identity_fields", "identity_count"),
    [
        (
            "phase-a-v1",
            "1939-v50-phase-a-anchor-manifest-v1",
            "daa-evidence-phase-receipt-phase-a-v1",
            ("record_key", "occurrence_key"),
            584,
        ),
        (
            "narrative-publication-v1",
            "1939-v50-narrative-publication-manifest-v1",
            "daa-evidence-phase-receipt-narrative-publication-v1",
            ("source_id", "record_key", "narrative_id", "binding_id"),
            8,
        ),
        (
            "name-completion-v1",
            "1939-v50-name-completion-manifest-v1",
            "daa-evidence-phase-receipt-name-completion-v1",
            ("person_id", "fact_id", "assertion_id", "citation_id", "conclusion_id"),
            8,
        ),
    ],
)
def test_ledger_declares_each_historical_receipt_adapter_contract(
    adapter_id: str,
    manifest_schema: str,
    receipt_schema: str,
    identity_fields: tuple[str, ...],
    identity_count: int,
):
    adapter = RECEIPT_ADAPTERS[adapter_id]

    assert adapter.manifest_schema_version == manifest_schema
    assert adapter.receipt_schema_version == receipt_schema
    assert adapter.identity_fields == identity_fields
    assert adapter.identity_count == identity_count


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("projection_evidence", []),
        ("projection_evidence", {}),
        ("authorisation_evidence", []),
        ("authorisation_evidence", {}),
    ],
)
def test_ledger_rejects_non_string_evidence_states_with_a_stable_token(field: str, value: object):
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "task25",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "task25.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-production-write-manifest-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": "task25-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "mechanically_bound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )
    ledger["phases"][0][field] = value
    ledger = seal_ledger(
        {key: item for key, item in ledger.items() if key != "ledger_content_sha256"}
    )

    with pytest.raises(
        LedgerError,
        match="EVIDENCE_RECONCILIATION_LEDGER_EVIDENCE_INVALID",
    ):
        validate_ledger(ledger)
