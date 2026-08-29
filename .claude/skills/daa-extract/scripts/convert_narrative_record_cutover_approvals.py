#!/usr/bin/env python3
"""Convert exact human decisions into hash-bound narrative cutover artifacts."""

from __future__ import annotations

import argparse
import importlib
import sys
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
review = importlib.import_module("build_narrative_record_cutover_review")

ContractError = review.ContractError
PublicationError = review.PublicationError

RECORD_MANIFEST_NAME = "narrative-record-baseline-manifest-v1.json"
LEGACY_MANIFEST_NAME = "narrative-legacy-baseline-manifest-v1.json"
APPROVAL_NAME = "narrative-record-cutover-approval-v1.json"
RECORD_MANIFEST_SCHEMA = "narrative-record-baseline-manifest-v1"
LEGACY_MANIFEST_SCHEMA = "narrative-legacy-baseline-manifest-v1"
APPROVAL_SCHEMA = "narrative-record-cutover-approval-v1"


def _decision_document(raw: bytes, bundle: dict[str, Any]) -> dict[str, Any]:
    value = review._require_canonical(raw)
    document = review.require_keys(
        value,
        {
            "schema_version", "database", "input_hashes", "record_decisions",
            "legacy_decisions",
        },
        "DECISION_DOCUMENT_SHAPE",
    )
    if document["schema_version"] != review.DECISIONS_SCHEMA:
        raise ContractError("DECISION_SCHEMA_VERSION")
    if review._database(document["database"]) != bundle["database"]:
        raise ContractError("DATABASE_IDENTITY_MISMATCH")
    hashes = review.require_keys(
        document["input_hashes"],
        {"record_candidates_sha256", "legacy_candidates_sha256", "inventory_sha256"},
        "DECISION_HASH_SHAPE",
    )
    for key, expected in bundle["hashes"].items():
        if review.require_sha256(hashes.get(key), key) != expected:
            raise ContractError("INPUT_HASH_MISMATCH")
    return document


def _record_decisions(value: Any, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise ContractError("RECORD_DECISIONS_REQUIRED")
    expected = {row["binding_id"]: row for row in rows}
    observed: dict[str, dict[str, Any]] = {}
    for item in value:
        decision = review.require_keys(
            item, {"binding_id", "row_sha256", "decision"}, "RECORD_DECISION_SHAPE"
        )
        binding_id = review.require_uuid(decision["binding_id"], "binding_id")
        if binding_id in observed:
            raise ContractError("DUPLICATE_RECORD_DECISION")
        if binding_id not in expected:
            raise ContractError("UNKNOWN_RECORD_DECISION")
        if decision["row_sha256"] != expected[binding_id]["row_sha256"]:
            raise ContractError("RECORD_DECISION_ROW_HASH_MISMATCH")
        if decision["decision"] == "uafklaret":
            raise ContractError("UNRESOLVED_DECISION")
        if decision["decision"] != "godkend baseline":
            raise ContractError("RECORD_DECISION_INVALID")
        observed[binding_id] = decision
    if set(observed) != set(expected):
        raise ContractError("RECORD_DECISION_ID_SET_MISMATCH")
    return [observed[row["binding_id"]] for row in rows]


def _legacy_decisions(value: Any, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise ContractError("LEGACY_DECISIONS_REQUIRED")
    expected = {row["narrative_id"]: row for row in rows}
    observed: dict[int, dict[str, Any]] = {}
    allowed = {"bevar offentligt som grandfathered", "skjul ved cutover"}
    for item in value:
        decision = review.require_keys(
            item, {"narrative_id", "row_sha256", "decision"}, "LEGACY_DECISION_SHAPE"
        )
        narrative_id = review.require_int(decision["narrative_id"], "narrative_id")
        if narrative_id in observed:
            raise ContractError("DUPLICATE_LEGACY_DECISION")
        if narrative_id not in expected:
            raise ContractError("UNKNOWN_LEGACY_DECISION")
        if decision["row_sha256"] != expected[narrative_id]["row_sha256"]:
            raise ContractError("LEGACY_DECISION_ROW_HASH_MISMATCH")
        if decision["decision"] == "uafklaret":
            raise ContractError("UNRESOLVED_DECISION")
        if decision["decision"] not in allowed:
            raise ContractError("LEGACY_DECISION_INVALID")
        observed[narrative_id] = decision
    if set(observed) != set(expected):
        raise ContractError("LEGACY_DECISION_ID_SET_MISMATCH")
    return [observed[row["narrative_id"]] for row in rows]


def convert_artifacts(
    record_raw: bytes, legacy_raw: bytes, inventory_raw: bytes, decisions_raw: bytes
) -> dict[str, bytes]:
    bundle = review.validate_candidate_bundle(record_raw, legacy_raw, inventory_raw)
    document = _decision_document(decisions_raw, bundle)
    record_decisions = _record_decisions(document["record_decisions"], bundle["record_rows"])
    legacy_decisions = _legacy_decisions(document["legacy_decisions"], bundle["legacy_rows"])

    keep_ids = {
        decision["narrative_id"] for decision in legacy_decisions
        if decision["decision"] == "bevar offentligt som grandfathered"
    }
    hide_ids = {
        decision["narrative_id"] for decision in legacy_decisions
        if decision["decision"] == "skjul ved cutover"
    }
    candidate_ids = {row["narrative_id"] for row in bundle["legacy_rows"]}
    if keep_ids & hide_ids or keep_ids | hide_ids != candidate_ids:
        raise ContractError("LEGACY_PARTITION_INVALID")

    record_manifest = {
        "schema_version": RECORD_MANIFEST_SCHEMA,
        "database": bundle["database"],
        "record_candidates_sha256": bundle["hashes"]["record_candidates_sha256"],
        "rows": bundle["record_rows"],
    }
    legacy_manifest = {
        "schema_version": LEGACY_MANIFEST_SCHEMA,
        "database": bundle["database"],
        "legacy_candidates_sha256": bundle["hashes"]["legacy_candidates_sha256"],
        "rows": [row for row in bundle["legacy_rows"] if row["narrative_id"] in keep_ids],
    }
    record_manifest_raw = review.canonical_bytes(record_manifest)
    legacy_manifest_raw = review.canonical_bytes(legacy_manifest)
    approval = {
        "schema_version": APPROVAL_SCHEMA,
        "database": bundle["database"],
        "input_hashes": {
            "approval_decisions_sha256": review.raw_sha256(decisions_raw),
            **bundle["hashes"],
            "record_manifest_sha256": review.raw_sha256(record_manifest_raw),
            "legacy_manifest_sha256": review.raw_sha256(legacy_manifest_raw),
        },
        "record_approved_ids": [row["binding_id"] for row in bundle["record_rows"]],
        "record_approved_rows": [
            {"binding_id": row["binding_id"], "row_sha256": row["row_sha256"]}
            for row in bundle["record_rows"]
        ],
        "legacy_keep_ids": sorted(keep_ids),
        "legacy_keep_rows": [
            {
                "narrative_id": row["narrative_id"],
                "legacy_publication_ref": row["legacy_publication_ref"],
                "row_sha256": row["row_sha256"],
            }
            for row in bundle["legacy_rows"] if row["narrative_id"] in keep_ids
        ],
        "legacy_hide_ids": sorted(hide_ids),
        "legacy_hide_rows": [
            {"narrative_id": row["narrative_id"], "row_sha256": row["row_sha256"]}
            for row in bundle["legacy_rows"] if row["narrative_id"] in hide_ids
        ],
        "counts": {
            "record_approved": len(bundle["record_rows"]),
            "legacy_candidates": len(bundle["legacy_rows"]),
            "legacy_keep": len(keep_ids),
            "legacy_hide": len(hide_ids),
        },
    }
    return {
        RECORD_MANIFEST_NAME: record_manifest_raw,
        LEGACY_MANIFEST_NAME: legacy_manifest_raw,
        APPROVAL_NAME: review.canonical_bytes(approval),
    }


def convert_and_publish(
    record_raw: bytes,
    legacy_raw: bytes,
    inventory_raw: bytes,
    decisions_raw: bytes,
    output_dir: Path,
    *,
    recover: bool = False,
) -> dict[str, bytes]:
    artifacts = convert_artifacts(record_raw, legacy_raw, inventory_raw, decisions_raw)
    if recover:
        review.recover_bundle(output_dir, artifacts)
    else:
        review.publish_bundle(output_dir, artifacts)
    return artifacts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--record-candidates", required=True)
    parser.add_argument("--legacy-candidates", required=True)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--decisions", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--recover", action="store_true")
    args = parser.parse_args(argv)
    try:
        artifacts = convert_and_publish(
            Path(args.record_candidates).read_bytes(),
            Path(args.legacy_candidates).read_bytes(),
            Path(args.inventory).read_bytes(),
            Path(args.decisions).read_bytes(),
            Path(args.output_dir), recover=args.recover,
        )
        for name, raw in artifacts.items():
            print(f"output={Path(args.output_dir) / name} sha256={review.raw_sha256(raw)}")
        return 0
    except (ContractError, PublicationError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
