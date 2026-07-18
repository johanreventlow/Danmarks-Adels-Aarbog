#!/usr/bin/env python3
"""Fail-closed promotion af ét Opus-genudtræk pr. eskaleret narrativ.

Modellen køres uden for dette script. Scriptet kræver et Sonnet-snapshot, validerer
Opus-outputtet med præcis samme H1-H8-validator og promoverer kun output uden
blokerende brud og uden nye H8-advisory-typer.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import validate_haendelser as validator


def _h8_types(advisory: list[str] | None) -> set[str]:
    return {item for item in (advisory or []) if item.startswith("H8")}


def decide(
    reextracted: dict[str, Any],
    snapshot: dict[str, Any] | None,
    source: dict[str, Any],
) -> tuple[bool, dict[str, Any] | None, list[str], list[str]]:
    """Returnér (promote, enriched, issues, advisory); manglende snapshot afvises."""
    enriched, issues, advisory, _ = validator.validate_narrative(source, reextracted)
    if snapshot is None:
        return False, enriched, issues + ["E1: Sonnet-snapshot mangler"], advisory
    _, snapshot_issues, snapshot_advisory, _ = validator.validate_narrative(source, snapshot)
    # Snapshot må gerne have blokerende brud; formålet med genudtrækket er netop at
    # reparere dem. Kun det nye output skal være blokkeringsfrit. H8 må forbedres eller
    # være uændret, aldrig skifte til en ny advisory-type.
    promote = not issues and _h8_types(advisory) <= _h8_types(snapshot_advisory)
    if not promote and not issues and snapshot_issues:
        # Ingen ekstra fejltekst nødvendig: et rent output med uændret/forbedret H8
        # ville være promoveret. Denne gren er kun dokumentation af beslutningsgrundlaget.
        pass
    return promote, enriched, issues, advisory


def _load_dir(directory: Path, snapshots: bool) -> dict[int, dict[str, Any]]:
    out: dict[int, dict[str, Any]] = {}
    if not directory.exists():
        return out
    for path in sorted(directory.glob("*.json")):
        is_snapshot = path.name.endswith(".sonnet.json")
        if is_snapshot != snapshots:
            continue
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        narrative_id = record.get("narrative_id") if isinstance(record, dict) else None
        if isinstance(narrative_id, int):
            if narrative_id in out:
                raise ValueError(f"Dublet narrative_id {narrative_id} i {directory}")
            out[narrative_id] = record
    return out


def merge_escalated(
    sources: list[dict[str, Any]],
    escalation: list[dict[str, Any]],
    reextracted_by_id: dict[int, dict[str, Any]],
    snapshot_by_id: dict[int, dict[str, Any]],
    clean: list[dict[str, Any]],
    review: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[int], list[dict[str, Any]]]:
    source_by_id = {row.get("narrative_id"): row for row in sources}
    clean_by_id = {row.get("narrative_id"): row for row in clean}
    review_by_id = {row.get("narrative_id"): row for row in review}
    promoted: list[int] = []
    decisions: list[dict[str, Any]] = []

    for entry in escalation:
        narrative_id = entry.get("narrative_id")
        source = source_by_id.get(narrative_id)
        reextracted = reextracted_by_id.get(narrative_id)
        if not isinstance(narrative_id, int) or source is None or reextracted is None:
            reasons = ["E1: kilde eller Opus-genudtræk mangler"]
            clean_by_id.pop(narrative_id, None)
            review_by_id[narrative_id] = {
                "narrative_id": narrative_id, "brud": reasons, "advisory": []
            }
            decisions.append({"narrative_id": narrative_id, "status": "afvist", "grunde": reasons})
            continue

        promote, enriched, issues, advisory = decide(
            reextracted, snapshot_by_id.get(narrative_id), source
        )
        if promote and enriched is not None:
            clean_by_id[narrative_id] = enriched
            review_by_id.pop(narrative_id, None)
            promoted.append(narrative_id)
            decisions.append({"narrative_id": narrative_id, "status": "promoveret"})
        else:
            reasons = issues or ["E2: Opus-output introducerer ny H8-advisory-type"]
            clean_by_id.pop(narrative_id, None)
            review_by_id[narrative_id] = {
                "narrative_id": narrative_id,
                "brud": reasons,
                "advisory": advisory,
                "udtraek": reextracted,
            }
            decisions.append({"narrative_id": narrative_id, "status": "afvist", "grunde": reasons})

    return list(clean_by_id.values()), list(review_by_id.values()), promoted, decisions


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("narrativer")
    parser.add_argument("reextracted_dir")
    parser.add_argument("snapshot_dir")
    parser.add_argument("escalation")
    parser.add_argument("clean")
    parser.add_argument("review")
    parser.add_argument("--diff", required=True)
    args = parser.parse_args()

    sources = json.loads(Path(args.narrativer).read_text(encoding="utf-8"))
    escalation = json.loads(Path(args.escalation).read_text(encoding="utf-8"))
    clean = json.loads(Path(args.clean).read_text(encoding="utf-8"))
    review = json.loads(Path(args.review).read_text(encoding="utf-8"))
    new_clean, new_review, promoted, decisions = merge_escalated(
        sources,
        escalation,
        _load_dir(Path(args.reextracted_dir), snapshots=False),
        _load_dir(Path(args.snapshot_dir), snapshots=True),
        clean,
        review,
    )
    _write_json(Path(args.clean), new_clean)
    _write_json(Path(args.review), new_review)
    _write_json(Path(args.diff), decisions)
    print(
        f"[escalate-haendelser] {len(promoted)} promoveret, "
        f"{len(escalation) - len(promoted)} afvist",
    )


if __name__ == "__main__":
    main()
