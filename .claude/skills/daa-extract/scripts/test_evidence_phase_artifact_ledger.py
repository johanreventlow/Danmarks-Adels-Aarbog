from __future__ import annotations

import pytest

from evidence_phase_artifact_ledger import (
    LedgerError,
    HISTORICAL_PHASE_CONTRACTS,
    RECEIPT_ADAPTERS,
    adapter_sha256,
    seal_ledger,
    validate_catalog,
    validate_historical_reconciliation_ledger,
    validate_ledger,
)


def test_historical_contracts_name_the_retained_runtime_artifacts_without_invented_receipt_schemas():
    assert {
        phase.adapter_id: tuple((artifact.role, artifact.schema_version) for artifact in phase.artifacts)
        for phase in HISTORICAL_PHASE_CONTRACTS
    } == {
        "task25-v1": (
            ("manifest", "1939-v50-production-write-manifest-v1"),
            ("apply_record", None),
        ),
        "phase-a-v1": (
            ("manifest", "1939-v50-phase-a-anchor-manifest-v1"),
            ("apply_record", None),
        ),
        "phase-b-v1": (
            ("manifest", "1939-v50-narrative-replacement-manifest-v1"),
            ("apply_record", None),
        ),
        "narrative-publication-v1": (
            ("manifest", "1939-v50-narrative-publication-manifest-v1"),
            ("apply_record", None),
        ),
        "name-completion-v1": (
            ("manifest", "1939-v50-name-completion-manifest-v1"),
            ("apply_record", None),
        ),
        "c0-followup-v1": (
            ("manifest", "1939-v50-c0-followup-manifest-v1"),
        ),
        "d1-historical-exception-v1": (),
        "c3-apply-v1": (
            ("manifest", "1939-v50-c3-apply-manifest-v1"),
            ("apply_record", None),
        ),
    }
    assert [(phase.phase_id, phase.sequence, phase.adapter_id) for phase in HISTORICAL_PHASE_CONTRACTS] == [
        ("task25", 1, "task25-v1"),
        ("phase-a", 2, "phase-a-v1"),
        ("phase-b", 3, "phase-b-v1"),
        ("narrative-publication", 4, "narrative-publication-v1"),
        ("name-completion", 5, "name-completion-v1"),
        ("c0", 6, "c0-followup-v1"),
        ("d1", 7, "d1-historical-exception-v1"),
        ("c3", 8, "c3-apply-v1"),
    ]


def test_catalog_accepts_an_unversioned_retained_apply_record_without_promoting_it_to_a_receipt():
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
                    {
                        "role": "manifest",
                        "path": "manifest.json",
                        "schema_version": "1939-v50-production-write-manifest-v1",
                        "required": True,
                    },
                    {
                        "role": "apply_record",
                        "path": "production-apply.json",
                        "schema_version": None,
                        "required": True,
                    },
                ],
            }
        ],
    }

    phase = validate_catalog(catalog)[0]

    assert phase.projection_evidence == "afterdocumented_unbound"
    assert phase.artifacts[1].schema_version is None


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


def test_historical_reconciliation_rejects_a_one_phase_ledger_before_admission():
    """A caller cannot turn one adapter into the historical reconciliation scope."""
    ledger = seal_ledger(
        {
            "schema_version": "daa-evidence-phase-artifact-ledger-v2",
            "phases": [
                {
                    "phase_id": "phase-a",
                    "sequence": 1,
                    "artifacts": [
                        {
                            "role": "manifest",
                            "path": "phase-a.json",
                            "sha256": "a" * 64,
                            "schema_version": "1939-v50-phase-a-anchor-manifest-v1",
                            "required": True,
                        }
                    ],
                    "adapter_id": "phase-a-v1",
                    "adapter_sha256": adapter_sha256(),
                    "projection_evidence": "afterdocumented_unbound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID"):
        validate_historical_reconciliation_ledger(ledger)


def _complete_historical_reconciliation_ledger(*, authorisations: dict[str, str] | None = None) -> dict:
    authorisations = authorisations or {}
    phases = []
    for contract in HISTORICAL_PHASE_CONTRACTS:
        unavailable = contract.phase_id == "d1"
        phases.append(
            {
                "phase_id": contract.phase_id,
                "sequence": contract.sequence,
                "artifacts": [
                    {
                        "role": artifact.role,
                        "path": f"{contract.phase_id}-{artifact.role}.json",
                        "sha256": "a" * 64,
                        "schema_version": artifact.schema_version,
                        "required": artifact.required,
                    }
                    for artifact in contract.artifacts
                ],
                "adapter_id": contract.adapter_id,
                "adapter_sha256": adapter_sha256(),
                "projection_evidence": "unavailable" if unavailable else "mechanically_bound",
                "authorisation_evidence": authorisations.get(
                    contract.phase_id,
                    "unavailable" if unavailable else (
                        "afterdocumented_authorisation_gap"
                        if contract.phase_id == "task25"
                        else "contemporaneous_phase_package"
                    ),
                ),
                **({} if unavailable else {
                    "contribution_sha256": "b" * 64,
                    "database_target_identity_sha256": "c" * 64,
                }),
            }
        )
    return seal_ledger({"schema_version": "daa-evidence-phase-artifact-ledger-v2", "phases": phases})


def test_historical_reconciliation_rejects_afterdocumented_artifact_pairs_promoted_to_bound():
    with pytest.raises(
        LedgerError,
        match="EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_CONTRACT_INVALID",
    ):
        validate_historical_reconciliation_ledger(
            _complete_historical_reconciliation_ledger()
        )


def test_historical_reconciliation_checks_promoted_phases_before_reporting_incomplete():
    ledger = _complete_historical_reconciliation_ledger()
    ledger.pop("ledger_content_sha256")
    ledger["phases"][0]["projection_evidence"] = "afterdocumented_unbound"
    ledger["phases"][0].pop("contribution_sha256")
    ledger["phases"][0].pop("database_target_identity_sha256")

    with pytest.raises(
        LedgerError,
        match="EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_CONTRACT_INVALID",
    ):
        validate_historical_reconciliation_ledger(seal_ledger(ledger))


@pytest.mark.parametrize(
    ("phase_id", "override"),
    [
        ("task25", "contemporaneous_phase_package"),
        ("phase-a", "afterdocumented_authorisation_gap"),
        ("phase-b", "afterdocumented_authorisation_gap"),
        ("narrative-publication", "afterdocumented_authorisation_gap"),
        ("name-completion", "afterdocumented_authorisation_gap"),
        ("c0", "afterdocumented_authorisation_gap"),
        ("d1", "afterdocumented_authorisation_gap"),
    ],
)
def test_historical_reconciliation_rejects_caller_authorisation_override(phase_id, override):
    ledger = _complete_historical_reconciliation_ledger(
        authorisations={phase_id: override}
    )

    with pytest.raises(LedgerError, match="EVIDENCE_RECONCILIATION_HISTORICAL_AUTHORISATION_INVALID"):
        validate_historical_reconciliation_ledger(ledger)


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
