from __future__ import annotations

import pytest

from evidence_phase_artifact_ledger import LedgerError, seal_ledger, validate_ledger


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
                    "adapter_sha256": "b" * 64,
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
                    "adapter_sha256": "b" * 64,
                    "projection_evidence": "mechanically_bound",
                    "authorisation_evidence": "afterdocumented_authorisation_gap",
                }
            ],
        }
    )

    assert validate_ledger(ledger)[0].phase_id == "task25"


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
                    "adapter_sha256": "b" * 64,
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
                    "adapter_sha256": "c" * 64,
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
                    "adapter_sha256": "b" * 64,
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
