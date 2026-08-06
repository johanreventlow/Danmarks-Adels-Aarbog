#!/usr/bin/env python3
"""Materialize source-bound dual-rendition evidence as exclusive artifacts."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from dual_rendition_evidence_1939 import (
    align_renditions,
    build_source_bound_evidence,
    derive_consensus,
    locate_baseline_anchors,
)


_OUTPUT_NAMES = (
    "calamari_occurrences",
    "raw_occurrences",
    "evidence",
    "report",
)
_NARRATIVE_RENDITIONS = {"calamari": "calamari", "raw": "raw_ocr"}


def _canonical_json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def _write_exclusive(path: Path, payload: bytes) -> None:
    """Write one payload atomically from the caller's ownership perspective."""
    created = False
    try:
        with path.open("xb") as handle:
            created = True
            handle.write(payload)
    except BaseException:
        if created:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        raise


def _validate_output_paths(outputs: dict[str, Path]) -> None:
    resolved = [path.resolve() for path in outputs.values()]
    if len(set(resolved)) != len(resolved):
        raise ValueError("output paths must be pairwise distinct")
    for path in outputs.values():
        if path.exists() or path.is_symlink():
            raise FileExistsError(path)


def _anchor_counts(records: list[dict], anchors: dict[str, dict]) -> dict[str, dict[str, int]]:
    counts = {"calamari": Counter(), "raw_ocr": Counter(), "unknown": Counter()}
    for record in records:
        rendition = _NARRATIVE_RENDITIONS.get(record["_narrativ_kilde"], "unknown")
        counts[rendition][anchors[record["record_key"]]["status"]] += 1
    return {
        rendition: dict(sorted(counter.items()))
        for rendition, counter in sorted(counts.items())
    }


def _report(
    evidence: dict, baseline: list[dict], calamari_text: str, raw_text: str,
    calamari_occurrences: dict, raw_occurrences: dict,
    artifact_payloads: dict[str, bytes],
) -> dict:
    anchors = locate_baseline_anchors(
        baseline,
        calamari_text=calamari_text,
        raw_text=raw_text,
        calamari_occurrences=calamari_occurrences,
        raw_occurrences=raw_occurrences,
    )
    alignment = align_renditions(calamari_occurrences, raw_occurrences)
    consensus = derive_consensus(
        anchors,
        alignment,
        calamari_manifest=calamari_occurrences,
        raw_manifest=raw_occurrences,
    )
    consensus_status_counts = Counter(result["status"] for result in consensus.values())
    reason_counts = Counter(
        result.get("reason", "consensus") for result in consensus.values()
    )
    return {
        "schema_version": 1,
        "source": evidence["source"],
        "baseline_total": len(baseline),
        "exact_anchor_counts": _anchor_counts(baseline, anchors),
        "occurrence_counts": {
            "calamari": len(calamari_occurrences["occurrences"]),
            "raw_ocr": len(raw_occurrences["occurrences"]),
        },
        "alignment_counts": {
            "invariant_pairs": len(alignment["pairs"]),
            "calamari_unmatched": len(alignment["calamari_unmatched"]),
            "raw_unmatched": len(alignment["raw_unmatched"]),
            "ambiguous_occurrence_ids": len(alignment["ambiguous_occurrence_ids"]),
        },
        "consensus_total": sum(consensus_status_counts.get(status, 0) for status in ("consensus",)),
        "consensus_status_counts": dict(sorted(consensus_status_counts.items())),
        "reason_counts": dict(sorted(reason_counts.items())),
        "collision_overlap_counts": {
            "occurrence_collision": reason_counts["occurrence_collision"],
            "span_overlap": reason_counts["span_overlap"],
        },
        "artifact_sha256": {
            name: hashlib.sha256(payload).hexdigest()
            for name, payload in sorted(artifact_payloads.items())
        },
    }


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare exclusive source-bound 1939 dual-rendition evidence artifacts."
    )
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--calamari", required=True, type=Path)
    parser.add_argument("--raw", required=True, type=Path)
    parser.add_argument("--pdf", required=True, type=Path)
    parser.add_argument("--profile-version", required=True)
    parser.add_argument("--calamari-occurrences-out", required=True, type=Path)
    parser.add_argument("--raw-occurrences-out", required=True, type=Path)
    parser.add_argument("--evidence-out", required=True, type=Path)
    parser.add_argument("--report-out", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    outputs = {
        "calamari_occurrences": args.calamari_occurrences_out,
        "raw_occurrences": args.raw_occurrences_out,
        "evidence": args.evidence_out,
        "report": args.report_out,
    }
    _validate_output_paths(outputs)

    baseline_bytes = args.baseline.read_bytes()
    calamari_bytes = args.calamari.read_bytes()
    raw_bytes = args.raw.read_bytes()
    pdf_bytes = args.pdf.read_bytes()
    evidence, calamari_occurrences, raw_occurrences = build_source_bound_evidence(
        baseline_bytes, calamari_bytes, raw_bytes, pdf_bytes,
        profile_version=args.profile_version,
    )
    baseline = json.loads(baseline_bytes.decode("utf-8"))
    artifact_payloads = {
        "calamari_occurrences": _canonical_json_bytes(calamari_occurrences),
        "raw_occurrences": _canonical_json_bytes(raw_occurrences),
        "evidence": _canonical_json_bytes(evidence),
    }
    report = _report(
        evidence,
        baseline,
        calamari_bytes.decode("utf-8"),
        raw_bytes.decode("utf-8"),
        calamari_occurrences,
        raw_occurrences,
        artifact_payloads,
    )
    payloads = {
        **artifact_payloads,
        "report": _canonical_json_bytes(report),
    }
    created: list[Path] = []
    try:
        for name in _OUTPUT_NAMES:
            _write_exclusive(outputs[name], payloads[name])
            created.append(outputs[name])
    except BaseException:
        for path in reversed(created):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
