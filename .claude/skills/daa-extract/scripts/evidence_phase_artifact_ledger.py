"""Hash-sealed, versioned admission ledger for evidence-phase artifacts."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from typing import Mapping


LEDGER_SCHEMA = "daa-evidence-phase-artifact-ledger-v2"
CATALOG_SCHEMA = "daa-evidence-phase-artifact-catalog-v1"
PROJECTION_STATES = {
    "mechanically_bound",
    "afterdocumented_unbound",
    "unavailable",
}
AUTHORISATION_STATES = {
    "contemporaneous_phase_package",
    "afterdocumented_authorisation_gap",
    "unavailable",
}


class LedgerError(ValueError):
    """A stable, fail-closed evidence-ledger error."""


@dataclass(frozen=True)
class ArtifactEntry:
    role: str
    path: str
    sha256: str
    schema_version: str
    required: bool


@dataclass(frozen=True)
class CatalogArtifactEntry:
    """Hash-free artifact metadata admitted from the private operator catalog."""

    role: str
    path: str
    schema_version: str
    required: bool


@dataclass(frozen=True)
class PhaseEntry:
    phase_id: str
    sequence: int
    artifacts: tuple[ArtifactEntry, ...]
    adapter_id: str
    adapter_sha256: str
    projection_evidence: str
    authorisation_evidence: str
    contribution_sha256: str | None = None
    database_target_identity_sha256: str | None = None


@dataclass(frozen=True)
class CatalogPhaseEntry:
    """A catalog phase before the CLI records immutable artifact hashes."""

    phase_id: str
    sequence: int
    artifacts: tuple[CatalogArtifactEntry, ...]
    adapter_id: str
    projection_evidence: str
    authorisation_evidence: str
    database_target_identity_sha256: str | None = None


@dataclass(frozen=True)
class ReceiptAdapter:
    """Data-free contract for an adapter's manifest-to-receipt binding."""

    adapter_id: str
    manifest_role: str
    manifest_schema_version: str
    receipt_role: str
    receipt_schema_version: str
    manifest_sha256_field: str
    database_target_identity_field: str
    identity_map_field: str
    identity_fields: tuple[str, ...]
    identity_unique_fields: tuple[str, ...]
    identity_count: int
    publication_statuses: frozenset[str]


@dataclass(frozen=True)
class ArtifactContract:
    role: str
    schema_version: str
    required: bool = True


@dataclass(frozen=True)
class HistoricalPhaseContract:
    phase_id: str
    sequence: int
    adapter_id: str
    artifacts: tuple[ArtifactContract, ...]


ADAPTER_ARTIFACT_CONTRACTS: Mapping[str, tuple[ArtifactContract, ...]] = {
    "task25-v1": (
        ArtifactContract("manifest", "1939-v50-production-write-manifest-v1"),
        ArtifactContract("receipt", "daa-evidence-phase-receipt-task25-v1"),
    ),
    "phase-a-v1": (
        ArtifactContract("manifest", "1939-v50-phase-a-anchor-manifest-v1"),
        ArtifactContract("receipt", "daa-evidence-phase-receipt-phase-a-v1"),
    ),
    "phase-b-v1": (
        ArtifactContract("manifest", "1939-v50-narrative-replacement-manifest-v2"),
        ArtifactContract("receipt", "daa-evidence-phase-receipt-phase-b-v1"),
    ),
    "narrative-publication-v1": (
        ArtifactContract("manifest", "1939-v50-narrative-publication-manifest-v1"),
        ArtifactContract("receipt", "daa-evidence-phase-receipt-narrative-publication-v1"),
    ),
    "name-completion-v1": (
        ArtifactContract("manifest", "1939-v50-name-completion-manifest-v1"),
        ArtifactContract("receipt", "daa-evidence-phase-receipt-name-completion-v1"),
    ),
    "c0-followup-v1": (
        ArtifactContract("manifest", "1939-v50-c0-followup-manifest-v1"),
        ArtifactContract("receipt", "daa-evidence-phase-receipt-c0-v1"),
    ),
    "d1-historical-exception-v1": (
        ArtifactContract("historical_apply_script", "1939-v50-d1-historical-apply-v1"),
    ),
}


HISTORICAL_PHASE_CONTRACTS = (
    HistoricalPhaseContract("task25", 1, "task25-v1", ADAPTER_ARTIFACT_CONTRACTS["task25-v1"]),
    HistoricalPhaseContract("phase-a", 2, "phase-a-v1", ADAPTER_ARTIFACT_CONTRACTS["phase-a-v1"]),
    HistoricalPhaseContract("phase-b", 3, "phase-b-v1", ADAPTER_ARTIFACT_CONTRACTS["phase-b-v1"]),
    HistoricalPhaseContract(
        "narrative-publication", 4, "narrative-publication-v1", ADAPTER_ARTIFACT_CONTRACTS["narrative-publication-v1"]
    ),
    HistoricalPhaseContract("name-completion", 5, "name-completion-v1", ADAPTER_ARTIFACT_CONTRACTS["name-completion-v1"]),
    HistoricalPhaseContract("c0", 6, "c0-followup-v1", ADAPTER_ARTIFACT_CONTRACTS["c0-followup-v1"]),
    HistoricalPhaseContract("d1", 7, "d1-historical-exception-v1", ADAPTER_ARTIFACT_CONTRACTS["d1-historical-exception-v1"]),
)


HISTORICAL_PHASE_AUTHORISATIONS: Mapping[str, str] = {
    "task25": "afterdocumented_authorisation_gap",
    "phase-a": "contemporaneous_phase_package",
    "phase-b": "contemporaneous_phase_package",
    "narrative-publication": "contemporaneous_phase_package",
    "name-completion": "contemporaneous_phase_package",
    "c0": "contemporaneous_phase_package",
    "d1": "unavailable",
}


ADAPTER_SOURCE_FILENAMES = (
    "audit_evidence_phase_artifacts_1939_v50.py",
    "evidence_phase_artifact_ledger.py",
    "project_evidence_phase_artifacts_1939_v50.py",
)


def adapter_sha256() -> str:
    """Bind every admission component's relative filename and exact source bytes."""
    digest = hashlib.sha256()
    source_dir = Path(__file__).parent
    for filename in ADAPTER_SOURCE_FILENAMES:
        raw = (source_dir / filename).read_bytes()
        encoded_name = filename.encode("utf-8")
        digest.update(len(encoded_name).to_bytes(2, "big"))
        digest.update(encoded_name)
        digest.update(len(raw).to_bytes(8, "big"))
        digest.update(raw)
    return digest.hexdigest()


TASK25_RECEIPT_ADAPTER = ReceiptAdapter(
    adapter_id="task25-v1",
    manifest_role="manifest",
    manifest_schema_version="1939-v50-production-write-manifest-v1",
    receipt_role="receipt",
    receipt_schema_version="daa-evidence-phase-receipt-task25-v1",
    manifest_sha256_field="manifest_sha256",
    database_target_identity_field="database_target_identity",
    identity_map_field="operation_identities",
    identity_fields=("element_id", "source_id", "record_key", "person_id"),
    identity_unique_fields=("element_id", "record_key"),
    identity_count=313,
    publication_statuses=frozenset(),
)


RECEIPT_ADAPTERS: Mapping[str, ReceiptAdapter] = {
    "phase-b-v1": ReceiptAdapter(
        adapter_id="phase-b-v1",
        manifest_role="manifest",
        manifest_schema_version="1939-v50-narrative-replacement-manifest-v2",
        receipt_role="receipt",
        receipt_schema_version="daa-evidence-phase-receipt-phase-b-v1",
        manifest_sha256_field="manifest_sha256",
        database_target_identity_field="database_target_identity",
        identity_map_field="identity_map",
        identity_fields=(
            "person_id",
            "record_key",
            "narrative_id",
            "before_sha256",
            "after_sha256",
            "publication_status",
        ),
        identity_unique_fields=("person_id", "record_key", "narrative_id"),
        identity_count=551,
        publication_statuses=frozenset({"published"}),
    ),
    "phase-a-v1": ReceiptAdapter(
        adapter_id="phase-a-v1",
        manifest_role="manifest",
        manifest_schema_version="1939-v50-phase-a-anchor-manifest-v1",
        receipt_role="receipt",
        receipt_schema_version="daa-evidence-phase-receipt-phase-a-v1",
        manifest_sha256_field="manifest_sha256",
        database_target_identity_field="database_target_identity",
        identity_map_field="identity_map",
        identity_fields=("record_key", "occurrence_key"),
        identity_unique_fields=("record_key", "occurrence_key"),
        identity_count=584,
        publication_statuses=frozenset(),
    ),
    "narrative-publication-v1": ReceiptAdapter(
        adapter_id="narrative-publication-v1",
        manifest_role="manifest",
        manifest_schema_version="1939-v50-narrative-publication-manifest-v1",
        receipt_role="receipt",
        receipt_schema_version="daa-evidence-phase-receipt-narrative-publication-v1",
        manifest_sha256_field="manifest_sha256",
        database_target_identity_field="database_target_identity",
        identity_map_field="identity_map",
        identity_fields=("source_id", "record_key", "narrative_id", "binding_id"),
        identity_unique_fields=("source_id", "record_key", "narrative_id", "binding_id"),
        identity_count=8,
        publication_statuses=frozenset(),
    ),
    "name-completion-v1": ReceiptAdapter(
        adapter_id="name-completion-v1",
        manifest_role="manifest",
        manifest_schema_version="1939-v50-name-completion-manifest-v1",
        receipt_role="receipt",
        receipt_schema_version="daa-evidence-phase-receipt-name-completion-v1",
        manifest_sha256_field="manifest_sha256",
        database_target_identity_field="database_target_identity",
        identity_map_field="completion_results",
        identity_fields=("person_id", "fact_id", "assertion_id", "citation_id", "conclusion_id"),
        identity_unique_fields=("person_id",),
        identity_count=8,
        publication_statuses=frozenset(),
    ),
}


def _require(condition: bool, token: str) -> None:
    if not condition:
        raise LedgerError(token)


def _is_hex_sha256(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def canonical_sha256(document: Mapping[str, object], excluded_field: str) -> str:
    payload = {key: value for key, value in document.items() if key != excluded_field}
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _valid_text(value: object) -> bool:
    return isinstance(value, str) and bool(value) and value.strip() == value


def _relative_path_identity(path: object) -> str:
    _require(_valid_text(path), "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID")
    assert isinstance(path, str)
    _require("\x00" not in path, "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID")
    candidate = Path(path)
    _require(
        not candidate.is_absolute() and ".." not in candidate.parts,
        "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID",
    )
    return candidate.as_posix()


def _validate_artifact(row: object) -> ArtifactEntry:
    _require(isinstance(row, dict), "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID")
    _require(
        set(row) == {"role", "path", "sha256", "schema_version", "required"},
        "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID",
    )
    _require(_valid_text(row["role"]), "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID")
    path = _relative_path_identity(row["path"])
    _require(_is_hex_sha256(row["sha256"]), "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID")
    _require(_valid_text(row["schema_version"]), "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID")
    _require(type(row["required"]) is bool, "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID")
    return ArtifactEntry(
        role=row["role"],
        path=path,
        sha256=row["sha256"],
        schema_version=row["schema_version"],
        required=row["required"],
    )


def _validate_catalog_artifact(row: object) -> CatalogArtifactEntry:
    _require(isinstance(row, dict), "EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_INVALID")
    _require(
        set(row) == {"role", "path", "schema_version", "required"},
        "EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_INVALID",
    )
    _require(_valid_text(row["role"]), "EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_INVALID")
    path = _relative_path_identity(row["path"])
    _require(_valid_text(row["schema_version"]), "EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_INVALID")
    _require(type(row["required"]) is bool, "EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_INVALID")
    return CatalogArtifactEntry(
        role=row["role"],
        path=path,
        schema_version=row["schema_version"],
        required=row["required"],
    )


def _validate_artifact_contract(
    adapter_id: str,
    artifacts: tuple[ArtifactEntry, ...] | tuple[CatalogArtifactEntry, ...],
    *,
    token: str,
    require_complete: bool = False,
) -> None:
    expected = ADAPTER_ARTIFACT_CONTRACTS.get(adapter_id)
    if expected is None:
        return
    expected_by_role = {
        artifact.role: (artifact.schema_version, artifact.required) for artifact in expected
    }
    observed_by_role = {
        artifact.role: (artifact.schema_version, artifact.required) for artifact in artifacts
    }
    _require(
        observed_by_role == expected_by_role if require_complete else observed_by_role.items() <= expected_by_role.items(),
        token,
    )
    _require(
        "historical_apply_script" in observed_by_role
        if adapter_id == "d1-historical-exception-v1"
        else "manifest" in observed_by_role,
        token,
    )


def validate_phase_contract(phase: PhaseEntry) -> None:
    """Reject roles and schemas that the phase adapter has not declared."""
    _require(
        len({artifact.role for artifact in phase.artifacts}) == len(phase.artifacts)
        and len({artifact.path for artifact in phase.artifacts}) == len(phase.artifacts),
        "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_DUPLICATE",
    )
    _validate_artifact_contract(
        phase.adapter_id,
        phase.artifacts,
        token="EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_CONTRACT_INVALID",
    )


def validate_catalog(document: object) -> list[CatalogPhaseEntry]:
    """Validate the deliberately hash-free, private artifact catalog."""
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_CATALOG_INVALID")
    _require(document.get("schema_version") == CATALOG_SCHEMA, "EVIDENCE_RECONCILIATION_CATALOG_SCHEMA_INVALID")
    _require(set(document) == {"schema_version", "phases"}, "EVIDENCE_RECONCILIATION_CATALOG_INVALID")
    rows = document["phases"]
    _require(isinstance(rows, list) and bool(rows), "EVIDENCE_RECONCILIATION_CATALOG_INVALID")
    phase_ids: set[str] = set()
    sequences: set[int] = set()
    entries: list[CatalogPhaseEntry] = []
    required = {
        "phase_id",
        "sequence",
        "artifacts",
        "adapter_id",
        "projection_evidence",
        "authorisation_evidence",
    }
    optional = {"database_target_identity_sha256"}
    for row in rows:
        _require(isinstance(row, dict) and set(row) in (required, required | optional), "EVIDENCE_RECONCILIATION_CATALOG_PHASE_INVALID")
        phase_id = row["phase_id"]
        sequence = row["sequence"]
        _require(_valid_text(phase_id), "EVIDENCE_RECONCILIATION_CATALOG_PHASE_INVALID")
        _require("/" not in phase_id and "\\" not in phase_id and "\x00" not in phase_id, "EVIDENCE_RECONCILIATION_CATALOG_PHASE_INVALID")
        _require(type(sequence) is int and sequence > 0, "EVIDENCE_RECONCILIATION_CATALOG_PHASE_INVALID")
        _require(phase_id not in phase_ids, "EVIDENCE_RECONCILIATION_CATALOG_PHASE_DUPLICATE")
        _require(sequence not in sequences, "EVIDENCE_RECONCILIATION_CATALOG_SEQUENCE_DUPLICATE")
        phase_ids.add(phase_id)
        sequences.add(sequence)
        artifacts_raw = row["artifacts"]
        _require(isinstance(artifacts_raw, list) and bool(artifacts_raw), "EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_INVALID")
        artifacts = tuple(_validate_catalog_artifact(artifact) for artifact in artifacts_raw)
        _require(len({artifact.role for artifact in artifacts}) == len(artifacts), "EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_DUPLICATE")
        _require(len({artifact.path for artifact in artifacts}) == len(artifacts), "EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_DUPLICATE")
        _require(_valid_text(row["adapter_id"]), "EVIDENCE_RECONCILIATION_CATALOG_PHASE_INVALID")
        _validate_artifact_contract(
            row["adapter_id"],
            artifacts,
            token="EVIDENCE_RECONCILIATION_CATALOG_ARTIFACT_CONTRACT_INVALID",
        )
        projection_evidence = row["projection_evidence"]
        authorisation_evidence = row["authorisation_evidence"]
        _require(_valid_text(projection_evidence) and projection_evidence in PROJECTION_STATES, "EVIDENCE_RECONCILIATION_CATALOG_EVIDENCE_INVALID")
        _require(_valid_text(authorisation_evidence) and authorisation_evidence in AUTHORISATION_STATES, "EVIDENCE_RECONCILIATION_CATALOG_EVIDENCE_INVALID")
        target_hash = row.get("database_target_identity_sha256")
        if target_hash is not None:
            _require(_is_hex_sha256(target_hash), "EVIDENCE_RECONCILIATION_CATALOG_PHASE_INVALID")
        entries.append(
            CatalogPhaseEntry(
                phase_id=phase_id,
                sequence=sequence,
                artifacts=artifacts,
                adapter_id=row["adapter_id"],
                projection_evidence=projection_evidence,
                authorisation_evidence=authorisation_evidence,
                database_target_identity_sha256=target_hash,
            )
        )
    return entries


def validate_historical_catalog(document: object) -> list[CatalogPhaseEntry]:
    """Admit only the complete, canonical 1939-v50 phase inventory for the CLI."""
    entries = validate_catalog(document)
    expected = tuple(
        (contract.phase_id, contract.sequence, contract.adapter_id)
        for contract in HISTORICAL_PHASE_CONTRACTS
    )
    observed = tuple((entry.phase_id, entry.sequence, entry.adapter_id) for entry in entries)
    _require(observed == expected, "EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID")
    _validate_historical_authorisations(entries)
    return entries


def _validate_historical_authorisations(
    entries: tuple[CatalogPhaseEntry, ...] | list[CatalogPhaseEntry] | list[PhaseEntry],
) -> None:
    by_id = {entry.phase_id: entry for entry in entries}
    _require(
        all(by_id[phase_id].authorisation_evidence == value for phase_id, value in HISTORICAL_PHASE_AUTHORISATIONS.items()),
        "EVIDENCE_RECONCILIATION_HISTORICAL_AUTHORISATION_INVALID",
    )
    _require(by_id["d1"].projection_evidence == "unavailable", "EVIDENCE_RECONCILIATION_HISTORICAL_AUTHORISATION_INVALID")


def validate_phase_rows(
    rows: object, *, allow_missing_target_for_incomplete: bool = False
) -> list[PhaseEntry]:
    _require(isinstance(rows, list) and bool(rows), "EVIDENCE_RECONCILIATION_LEDGER_INVALID")
    phase_ids: set[str] = set()
    sequences: set[int] = set()
    entries: list[PhaseEntry] = []
    expected = {
        "phase_id",
        "sequence",
        "artifacts",
        "adapter_id",
        "adapter_sha256",
        "projection_evidence",
        "authorisation_evidence",
    }
    for row in rows:
        _require(isinstance(row, dict), "EVIDENCE_RECONCILIATION_LEDGER_PHASE_INVALID")
        optional = {"contribution_sha256", "database_target_identity_sha256"}
        _require(
            set(row) in (
                expected,
                expected | {"contribution_sha256"},
                expected | {"database_target_identity_sha256"},
                expected | optional,
            ),
            "EVIDENCE_RECONCILIATION_LEDGER_PHASE_INVALID",
        )
        phase_id = row["phase_id"]
        sequence = row["sequence"]
        _require(_valid_text(phase_id), "EVIDENCE_RECONCILIATION_LEDGER_PHASE_INVALID")
        _require(type(sequence) is int and sequence > 0, "EVIDENCE_RECONCILIATION_LEDGER_PHASE_INVALID")
        _require(phase_id not in phase_ids, "EVIDENCE_RECONCILIATION_LEDGER_PHASE_DUPLICATE")
        _require(sequence not in sequences, "EVIDENCE_RECONCILIATION_LEDGER_SEQUENCE_DUPLICATE")
        phase_ids.add(phase_id)
        sequences.add(sequence)
        artifacts_raw = row["artifacts"]
        _require(isinstance(artifacts_raw, list) and bool(artifacts_raw), "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_INVALID")
        artifacts = tuple(_validate_artifact(artifact) for artifact in artifacts_raw)
        _require(len({artifact.role for artifact in artifacts}) == len(artifacts), "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_DUPLICATE")
        _require(len({artifact.path for artifact in artifacts}) == len(artifacts), "EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_DUPLICATE")
        adapter_id = row["adapter_id"]
        _require(_valid_text(adapter_id), "EVIDENCE_RECONCILIATION_LEDGER_PHASE_INVALID")
        validate_phase_contract(
            PhaseEntry(
                phase_id=phase_id,
                sequence=sequence,
                artifacts=artifacts,
                adapter_id=adapter_id,
                adapter_sha256=row["adapter_sha256"],
                projection_evidence="afterdocumented_unbound",
                authorisation_evidence="afterdocumented_authorisation_gap",
            )
        )
        _require(
            _is_hex_sha256(row["adapter_sha256"])
            and row["adapter_sha256"] == adapter_sha256(),
            "EVIDENCE_RECONCILIATION_LEDGER_ADAPTER_HASH_INVALID",
        )
        projection_evidence = row["projection_evidence"]
        authorisation_evidence = row["authorisation_evidence"]
        _require(
            _valid_text(projection_evidence)
            and projection_evidence in PROJECTION_STATES,
            "EVIDENCE_RECONCILIATION_LEDGER_EVIDENCE_INVALID",
        )
        _require(
            _valid_text(authorisation_evidence)
            and authorisation_evidence in AUTHORISATION_STATES,
            "EVIDENCE_RECONCILIATION_LEDGER_EVIDENCE_INVALID",
        )
        contribution_sha256 = row.get("contribution_sha256")
        if contribution_sha256 is not None:
            _require(projection_evidence == "mechanically_bound", "EVIDENCE_RECONCILIATION_LEDGER_EVIDENCE_INVALID")
            _require(_is_hex_sha256(contribution_sha256), "EVIDENCE_RECONCILIATION_LEDGER_EVIDENCE_INVALID")
        database_target_identity_sha256 = row.get("database_target_identity_sha256")
        if adapter_id in RECEIPT_ADAPTERS and not (
            allow_missing_target_for_incomplete
            and projection_evidence != "mechanically_bound"
            and database_target_identity_sha256 is None
        ):
            _require(
                _is_hex_sha256(database_target_identity_sha256),
                "EVIDENCE_RECONCILIATION_LEDGER_PHASE_INVALID",
            )
        elif database_target_identity_sha256 is not None:
            _require(
                _is_hex_sha256(database_target_identity_sha256),
                "EVIDENCE_RECONCILIATION_LEDGER_PHASE_INVALID",
            )
        entries.append(
            PhaseEntry(
                phase_id=phase_id,
                sequence=sequence,
                artifacts=artifacts,
                adapter_id=adapter_id,
                adapter_sha256=row["adapter_sha256"],
                projection_evidence=projection_evidence,
                authorisation_evidence=authorisation_evidence,
                contribution_sha256=contribution_sha256,
                database_target_identity_sha256=database_target_identity_sha256,
            )
        )
    return entries


def validate_ledger(
    document: object,
    *,
    require_contribution_hashes: bool = False,
    allow_missing_target_for_incomplete: bool = False,
) -> list[PhaseEntry]:
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_LEDGER_INVALID")
    _require(document.get("schema_version") == LEDGER_SCHEMA, "EVIDENCE_RECONCILIATION_LEDGER_SCHEMA_INVALID")
    _require(
        document.get("ledger_content_sha256")
        == canonical_sha256(document, "ledger_content_sha256"),
        "EVIDENCE_RECONCILIATION_LEDGER_HASH_INVALID",
    )
    entries = validate_phase_rows(
        document.get("phases"),
        allow_missing_target_for_incomplete=(
            allow_missing_target_for_incomplete or require_contribution_hashes
        ),
    )
    if require_contribution_hashes:
        _require(
            all(
                entry.projection_evidence == "mechanically_bound"
                and entry.contribution_sha256
                for entry in entries
            ),
            "EVIDENCE_RECONCILIATION_INCOMPLETE",
        )
    return entries


def validate_historical_reconciliation_ledger(document: object) -> list[PhaseEntry]:
    """Admit only the fixed historical scope before any public reconciliation.

    The private audit ledger may preserve incomplete evidence.  Public
    reconciliation has a narrower contract: callers cannot select their own
    subset, evidence states, receipt set, or database target.
    """
    entries = validate_ledger(document, allow_missing_target_for_incomplete=True)
    expected = tuple(
        (contract.phase_id, contract.sequence, contract.adapter_id)
        for contract in HISTORICAL_PHASE_CONTRACTS
    )
    observed = tuple((entry.phase_id, entry.sequence, entry.adapter_id) for entry in entries)
    _require(observed == expected, "EVIDENCE_RECONCILIATION_HISTORICAL_INVENTORY_INVALID")

    _validate_historical_authorisations(entries)

    target_hashes: set[str] = set()
    for entry in entries:
        if entry.phase_id == "d1":
            continue
        _require(
            entry.projection_evidence == "mechanically_bound",
            "EVIDENCE_RECONCILIATION_INCOMPLETE",
        )
        _require(
            entry.contribution_sha256 is not None,
            "EVIDENCE_RECONCILIATION_INCOMPLETE",
        )
        _validate_artifact_contract(
            entry.adapter_id,
            entry.artifacts,
            token="EVIDENCE_RECONCILIATION_LEDGER_ARTIFACT_CONTRACT_INVALID",
            require_complete=True,
        )
        _require(
            _is_hex_sha256(entry.database_target_identity_sha256),
            "EVIDENCE_RECONCILIATION_DATABASE_TARGET_REQUIRED",
        )
        assert entry.database_target_identity_sha256 is not None
        target_hashes.add(entry.database_target_identity_sha256)
    _require(len(target_hashes) == 1, "EVIDENCE_RECONCILIATION_DATABASE_TARGET_MISMATCH")
    return entries


def seal_ledger(document: Mapping[str, object]) -> dict[str, object]:
    _require(isinstance(document, dict), "EVIDENCE_RECONCILIATION_LEDGER_INVALID")
    _require("ledger_content_sha256" not in document, "EVIDENCE_RECONCILIATION_LEDGER_ALREADY_SEALED")
    sealed = dict(document)
    sealed["ledger_content_sha256"] = canonical_sha256(sealed, "ledger_content_sha256")
    return sealed
