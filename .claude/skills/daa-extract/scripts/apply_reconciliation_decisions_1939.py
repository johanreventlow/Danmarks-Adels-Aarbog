#!/usr/bin/env python3
"""Apply source-bound human decisions to a 1939 reconciliation queue."""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Mapping, Sequence


class DecisionError(ValueError):
    """Raised when a decision cannot safely be applied to its exact source."""


RESOLVED_DISPOSITIONS = {
    "unchanged", "accepted_carryover", "accepted_structural_context",
    "retired_duplicate", "retired_fragment",
}
ALLOWED_SOURCE_DISPOSITIONS = {"split_review", "split_merge_review"}


def _text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise DecisionError(f"{field} kræves")
    return value


def _sha256(value: object, field: str) -> str:
    value = _text(value, field).lower()
    if len(value) != 64 or any(char not in "0123456789abcdef" for char in value):
        raise DecisionError(f"{field} er ugyldig")
    return value


def _objects(value: object, field: str) -> list[dict[str, Any]]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        raise DecisionError(f"{field} kræves")
    result = []
    for item in value:
        if not isinstance(item, Mapping):
            raise DecisionError(f"{field} skal indeholde objekter")
        result.append(dict(item))
    return result


def _unique(entries: Sequence[Mapping[str, Any]], field: str, label: str) -> dict[str, Mapping[str, Any]]:
    result = {}
    for entry in entries:
        key = _text(entry.get(field), f"{label} {field}")
        if key in result:
            raise DecisionError(f"{label} har dublet {field}")
        result[key] = entry
    return result


def _unresolved_disposition(entry: Mapping[str, Any], owners: Mapping[str, list[str]]) -> str:
    original = entry.get("disposition")
    if original == "retired_duplicate":
        return original
    matches = entry.get("matches")
    if not isinstance(matches, list) or not matches:
        return "unresolved"
    target_has_multiple = any(
        len(owners.get(match.get("new_record_key"), [])) > 1
        for match in matches if isinstance(match, Mapping)
    )
    if len(matches) > 1:
        return "split_merge_review" if target_has_multiple else "split_review"
    if target_has_multiple:
        return "merge_review"
    if original in RESOLVED_DISPOSITIONS:
        return str(original)
    if entry.get("evidence_method") == "unique_exact_narrative" or original == "text_anchor_review":
        return "text_anchor_review"
    return "boundary_change_review"


def apply_decisions(reconciliation: Mapping[str, Any], decisions: Mapping[str, Any], *,
                    reconciliation_sha256: str) -> dict[str, Any]:
    """Return a new queue with exact, reviewed split-target choices applied."""
    reconciliation_sha256 = _sha256(reconciliation_sha256, "reconciliation_sha256")
    if reconciliation.get("schema_version") != "1.0":
        raise DecisionError("reconciliation schema_version 1.0 kræves")
    source = reconciliation.get("source")
    decision_source = decisions.get("source")
    if not isinstance(source, Mapping) or not isinstance(decision_source, Mapping):
        raise DecisionError("source kræves")
    if decisions.get("schema_version") != "1.0" or decision_source.get("edition") != "1939":
        raise DecisionError("decision schema_version 1.0 for 1939 kræves")
    if _sha256(decision_source.get("reconciliation_sha256"), "decision reconciliation_sha256") != reconciliation_sha256:
        raise DecisionError("decision matcher ikke reconciliation-bytes")
    for field in ("baseline_sha256", "calamari_sha256"):
        if _sha256(decision_source.get(field), f"decision {field}") != _sha256(source.get(field), field):
            raise DecisionError(f"decision {field} matcher ikke reconciliation")

    reviewed_by = _text(decisions.get("reviewed_by"), "reviewed_by")
    decision_batch = _text(decisions.get("decision_batch"), "decision_batch")
    baseline_entries = _objects(reconciliation.get("baseline_entries"), "baseline_entries")
    new_entries = _objects(reconciliation.get("new_entries"), "new_entries")
    old_by_key = _unique(baseline_entries, "baseline_record_key", "baseline_entries")
    new_by_key = _unique(new_entries, "new_record_key", "new_entries")
    raw_decisions = _objects(decisions.get("decisions"), "decisions")
    if not raw_decisions:
        raise DecisionError("mindst én decision kræves")

    decision_by_old = {}
    retirement_by_retired = {}
    retirement_by_canonical = {}
    affected_old_keys = set()
    selected_targets = set()
    annotation_by_new = {}
    for decision in raw_decisions:
        old_key = _text(decision.get("baseline_record_key"), "decision baseline_record_key")
        if old_key in affected_old_keys:
            raise DecisionError("decision har modstridende baseline_record_key")
        old = old_by_key.get(old_key)
        if decision.get("decision_kind") == "retire_continuation_fragment":
            if set(decision) != {
                "baseline_record_key", "decision_kind",
                "canonical_baseline_record_key", "new_record_key", "reason",
            } or decision.get("reason") != "continuation_extraction_fragment":
                raise DecisionError("ukendt continuation fragment retirement-handling")
            canonical_key = _text(
                decision.get("canonical_baseline_record_key"),
                "canonical_baseline_record_key",
            )
            target = _text(decision.get("new_record_key"), "new_record_key")
            canonical = old_by_key.get(canonical_key)
            target_entry = new_by_key.get(target)
            if old is None or canonical is None or target_entry is None:
                raise DecisionError("continuation fragment peger på ukendt record")
            if old_key == canonical_key or canonical_key in affected_old_keys:
                raise DecisionError("continuation fragment har modstridende baseline-records")
            if (old.get("disposition") != "merge_review"
                    or canonical.get("disposition") != "merge_review"
                    or target_entry.get("disposition") != "merge_review"):
                raise DecisionError("continuation fragment kræver merge-review records")
            canonical_span = canonical.get("source_span")
            fragment_span = old.get("source_span")
            target_span = target_entry.get("source_span")
            spans = (canonical_span, fragment_span, target_span)
            if any(
                not isinstance(span, Mapping)
                or type(span.get("char_from")) is not int
                or type(span.get("char_to")) is not int
                or span["char_from"] < 0
                or span["char_to"] <= span["char_from"]
                for span in spans
            ):
                raise DecisionError("continuation fragment kræver gyldige kildespænd")
            if (canonical_span["char_to"] > fragment_span["char_from"]
                    or fragment_span["char_from"] - canonical_span["char_to"] > 1):
                raise DecisionError("continuation fragment kræver sammenhængende rækkefølge")
            if (target_span["char_from"] > canonical_span["char_from"]
                    or target_span["char_to"] < fragment_span["char_to"]):
                raise DecisionError("continuation fragment skal ligge i målets kildespænd")
            for entry in (old, canonical):
                matches = entry.get("matches")
                if (not isinstance(matches, list) or len(matches) != 1
                        or not isinstance(matches[0], Mapping)
                        or matches[0].get("new_record_key") != target):
                    raise DecisionError("continuation fragment kræver ét fælles mål")
            if target in selected_targets:
                raise DecisionError("flere beslutninger bruger samme new_record_key")
            affected_old_keys.update((old_key, canonical_key))
            selected_targets.add(target)
            retirement = (decision, canonical_key, target, "fragment")
            retirement_by_retired[old_key] = retirement
            retirement_by_canonical[canonical_key] = (decision, old_key, target, "fragment")
            continue
        if decision.get("decision_kind") == "retire_duplicate_record":
            if set(decision) != {
                "baseline_record_key", "decision_kind",
                "canonical_baseline_record_key", "new_record_key", "reason",
            } or decision.get("reason") != "duplicate_extraction_record":
                raise DecisionError("ukendt duplicate retirement-handling")
            canonical_key = _text(
                decision.get("canonical_baseline_record_key"),
                "canonical_baseline_record_key",
            )
            target = _text(decision.get("new_record_key"), "new_record_key")
            canonical = old_by_key.get(canonical_key)
            if old is None or canonical is None or target not in new_by_key:
                raise DecisionError("duplicate retirement peger på ukendt record")
            if old_key == canonical_key or canonical_key in affected_old_keys:
                raise DecisionError("duplicate retirement har modstridende baseline-records")
            if (old.get("disposition") != "merge_review"
                    or canonical.get("disposition") != "merge_review"):
                raise DecisionError("duplicate retirement kræver to merge-review records")
            old_span = old.get("source_span")
            canonical_span = canonical.get("source_span")
            if (not isinstance(old_span, Mapping) or old_span != canonical_span
                    or type(old_span.get("char_from")) is not int
                    or type(old_span.get("char_to")) is not int
                    or old_span["char_from"] < 0
                    or old_span["char_to"] <= old_span["char_from"]):
                raise DecisionError("duplicate retirement kræver identisk kildespænd")
            for entry in (old, canonical):
                matches = entry.get("matches")
                if (not isinstance(matches, list) or len(matches) != 1
                        or not isinstance(matches[0], Mapping)
                        or matches[0].get("new_record_key") != target):
                    raise DecisionError("duplicate retirement kræver ét fælles mål")
            if target in selected_targets:
                raise DecisionError("flere beslutninger bruger samme new_record_key")
            affected_old_keys.update((old_key, canonical_key))
            selected_targets.add(target)
            retirement = (decision, canonical_key, target, "duplicate")
            retirement_by_retired[old_key] = retirement
            retirement_by_canonical[canonical_key] = (decision, old_key, target, "duplicate")
            continue
        if decision.get("decision_kind") == "accept_boundary_change":
            if set(decision) != {
                "baseline_record_key", "decision_kind", "selected_new_record_key",
            } or old is None or old.get("disposition") != "boundary_change_review":
                raise DecisionError("boundary acceptance kræver én eksisterende boundary-change review")
            matches = old.get("matches")
            selected = _text(
                decision.get("selected_new_record_key"), "selected_new_record_key"
            )
            if (not isinstance(matches, list) or len(matches) != 1
                    or not isinstance(matches[0], Mapping)
                    or matches[0].get("new_record_key") != selected
                    or selected not in new_by_key):
                raise DecisionError("boundary acceptance kræver præcis ét eksisterende mål")
            if selected in selected_targets:
                raise DecisionError("flere beslutninger vælger samme new_record_key")
            affected_old_keys.add(old_key)
            selected_targets.add(selected)
            decision_by_old[old_key] = (
                decision, selected, "human_accepted_boundary_change",
            )
            continue
        if decision.get("decision_kind") == "accept_text_anchor":
            if set(decision) != {
                "baseline_record_key", "decision_kind", "selected_new_record_key",
            } or old is None or old.get("disposition") != "text_anchor_review":
                raise DecisionError(
                    "text-anchor acceptance kræver én eksisterende text-anchor review"
                )
            if old.get("evidence_method") != "unique_exact_narrative":
                raise DecisionError(
                    "text-anchor acceptance kræver unique_exact_narrative"
                )
            matches = old.get("matches")
            selected = _text(
                decision.get("selected_new_record_key"), "selected_new_record_key"
            )
            if (not isinstance(matches, list) or len(matches) != 1
                    or not isinstance(matches[0], Mapping)
                    or matches[0].get("new_record_key") != selected
                    or selected not in new_by_key):
                raise DecisionError(
                    "text-anchor acceptance kræver præcis ét eksisterende mål"
                )
            if selected in selected_targets:
                raise DecisionError("flere beslutninger vælger samme new_record_key")
            affected_old_keys.add(old_key)
            selected_targets.add(selected)
            decision_by_old[old_key] = (
                decision, selected, "human_accepted_text_anchor",
            )
            continue
        if old is None or old.get("disposition") not in ALLOWED_SOURCE_DISPOSITIONS:
            raise DecisionError("decision må kun afgøre en eksisterende split-review")
        if (decision.get("decision_kind") != "select_carryover_target"
                or decision.get("nonselected_action") != "retain_distinct_source_records"):
            raise DecisionError("ukendt eller usikker decision-handling")
        selected = _text(decision.get("selected_new_record_key"), "selected_new_record_key")
        match_keys = {
            match.get("new_record_key") for match in old.get("matches", [])
            if isinstance(match, Mapping)
        }
        if selected not in match_keys or selected not in new_by_key:
            raise DecisionError("valgt new_record_key er ikke kandidat for baseline-record")
        if selected in selected_targets:
            raise DecisionError("flere beslutninger vælger samme new_record_key")
        affected_old_keys.add(old_key)
        selected_targets.add(selected)

        annotations = _objects(decision.get("record_annotations", []), "record_annotations")
        for annotation in annotations:
            annotated = _text(annotation.get("new_record_key"), "annotation new_record_key")
            if annotated not in match_keys or annotated == selected:
                raise DecisionError("annotation skal gælde en fravalgt kandidat")
            if (annotation.get("record_kind") != "cross_reference"
                    or annotation.get("person_creation") != "forbidden_without_separate_evidence"
                    or set(annotation) != {"new_record_key", "record_kind", "person_creation"}):
                raise DecisionError("ukendt record annotation")
            if annotated in annotation_by_new:
                raise DecisionError("dublet record annotation")
            annotation_by_new[annotated] = dict(annotation)
        decision_by_old[old_key] = (
            decision, selected, "human_selected_split_target",
        )

    original_owners: dict[str, list[str]] = defaultdict(list)
    for entry in baseline_entries:
        for match in entry.get("matches", []):
            if isinstance(match, Mapping) and match.get("new_record_key") in new_by_key:
                original_owners[match["new_record_key"]].append(entry["baseline_record_key"])
    for old_key, (_, selected, _) in decision_by_old.items():
        other_owners = [key for key in original_owners[selected] if key != old_key]
        if other_owners and not all(key in decision_by_old for key in other_owners):
            raise DecisionError("valgt mål har fortsat flere baseline-ejere")
    for retired_key, (_, canonical_key, target, _) in retirement_by_retired.items():
        if set(original_owners[target]) != {retired_key, canonical_key}:
            raise DecisionError("duplicate retirement har ikke præcis to ejere")

    resolved_baseline = []
    for entry in baseline_entries:
        output = dict(entry)
        old_key = entry["baseline_record_key"]
        retirement = retirement_by_retired.get(old_key)
        retained = retirement_by_canonical.get(old_key)
        choice = decision_by_old.get(old_key)
        if retirement is not None:
            decision, canonical_key, _, retirement_kind = retirement
            output["matches"] = []
            output["disposition"] = (
                "retired_fragment" if retirement_kind == "fragment" else "retired_duplicate"
            )
            output["canonical_baseline_record_key"] = canonical_key
            output["retirement_reason"] = decision.get("reason")
            output["reviewed_by"] = reviewed_by
            output["decision_batch"] = decision_batch
        elif retained is not None:
            _, _, target, retirement_kind = retained
            output["matches"] = [
                dict(match) for match in entry["matches"]
                if match.get("new_record_key") == target
            ]
            output["disposition"] = "accepted_carryover"
            if retirement_kind == "fragment":
                output["selected_new_record_key"] = target
                output["reconciliation_basis"] = "human_accepted_contiguous_merge"
            else:
                output["reconciliation_basis"] = "human_retained_duplicate_target"
            output["reviewed_by"] = reviewed_by
            output["decision_batch"] = decision_batch
        elif choice is not None:
            _, selected, reconciliation_basis = choice
            output["matches"] = [
                dict(match) for match in entry["matches"]
                if match.get("new_record_key") == selected
            ]
            output["selected_new_record_key"] = selected
            output["disposition"] = "accepted_carryover"
            output["reconciliation_basis"] = reconciliation_basis
            output["reviewed_by"] = reviewed_by
            output["decision_batch"] = decision_batch
        resolved_baseline.append(output)

    owners: dict[str, list[str]] = defaultdict(list)
    for entry in resolved_baseline:
        for match in entry.get("matches", []):
            if isinstance(match, Mapping):
                owners[match.get("new_record_key")].append(entry["baseline_record_key"])
    disposition_by_old = {}
    for entry in resolved_baseline:
        if entry["baseline_record_key"] in retirement_by_retired:
            disposition = retirement_by_retired[entry["baseline_record_key"]][3]
            disposition = "retired_fragment" if disposition == "fragment" else "retired_duplicate"
        elif (entry["baseline_record_key"] in decision_by_old
              or entry["baseline_record_key"] in retirement_by_canonical):
            disposition = "accepted_carryover"
        else:
            disposition = _unresolved_disposition(entry, owners)
            entry["disposition"] = disposition
        disposition_by_old[entry["baseline_record_key"]] = disposition

    resolved_new = []
    for entry in new_entries:
        output = dict(entry)
        key = entry["new_record_key"]
        old_keys = owners.get(key, [])
        output["baseline_record_keys"] = old_keys
        if not old_keys:
            disposition = ("accepted_structural_context"
                           if entry.get("record_kind") == "structural_context"
                           else "unmatched_new_review")
        elif len(old_keys) > 1:
            disposition = "merge_review"
        else:
            disposition = disposition_by_old[old_keys[0]]
        output["disposition"] = disposition
        if key in annotation_by_new:
            output["human_annotation"] = annotation_by_new[key]
            output["reviewed_by"] = reviewed_by
            output["decision_batch"] = decision_batch
        resolved_new.append(output)

    baseline_counts = Counter(entry["disposition"] for entry in resolved_baseline)
    new_counts = Counter(entry["disposition"] for entry in resolved_new)
    remaining_baseline = sum(
        count for disposition, count in baseline_counts.items()
        if disposition not in RESOLVED_DISPOSITIONS
    )
    remaining_new = sum(
        count for disposition, count in new_counts.items()
        if disposition not in RESOLVED_DISPOSITIONS
    )
    report = {
        "baseline_total": len(resolved_baseline),
        "new_total": len(resolved_new),
        "applied_decisions": len(raw_decisions),
        "accepted_carryovers": baseline_counts.get("accepted_carryover", 0),
        "retired_duplicates": baseline_counts.get("retired_duplicate", 0),
        "retired_fragments": baseline_counts.get("retired_fragment", 0),
        "baseline_dispositions": dict(sorted(baseline_counts.items())),
        "new_dispositions": dict(sorted(new_counts.items())),
        "remaining_baseline_review": remaining_baseline,
        "remaining_new_review": remaining_new,
        "reconciliation_gate": "GO" if not remaining_baseline and not remaining_new else "NO-GO",
    }
    return {
        "schema_version": "1.0",
        "source": dict(source),
        "decision_source": {
            "reconciliation_sha256": reconciliation_sha256,
            "reviewed_by": reviewed_by,
            "decision_batch": decision_batch,
        },
        "baseline_entries": resolved_baseline,
        "new_entries": resolved_new,
        "report": report,
    }


def _load_json_bytes(path: Path, label: str) -> tuple[bytes, object]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result = {}
        for key, value in pairs:
            if key in result:
                raise DecisionError(f"{label} har dublet JSON-feltnavn")
            result[key] = value
        return result
    try:
        payload = path.read_bytes()
        return payload, json.loads(payload.decode("utf-8"), object_pairs_hook=reject_duplicates)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise DecisionError(f"{label} kunne ikke læses") from exc


def _json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _write_outputs(outputs: list[tuple[Path, bytes]]) -> None:
    paths = [path for path, _ in outputs]
    if len(paths) != len(set(paths)):
        raise DecisionError("outputstier skal være forskellige")
    created = []
    try:
        for path, payload in outputs:
            with path.open("xb") as handle:
                created.append(path)
                handle.write(payload)
    except FileExistsError as exc:
        for path in created:
            path.unlink(missing_ok=True)
        raise DecisionError("outputfil findes allerede") from exc
    except BaseException:
        for path in created:
            path.unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reconciliation", type=Path)
    parser.add_argument("--decisions", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--report-out", type=Path, required=True)
    args = parser.parse_args(argv)
    reconciliation_bytes, reconciliation = _load_json_bytes(args.reconciliation, "reconciliation")
    _, decisions = _load_json_bytes(args.decisions, "decisions")
    if not isinstance(reconciliation, Mapping) or not isinstance(decisions, Mapping):
        raise DecisionError("input skal være JSON-objekter")
    result = apply_decisions(
        reconciliation, decisions,
        reconciliation_sha256=hashlib.sha256(reconciliation_bytes).hexdigest(),
    )
    _write_outputs([
        (args.out, _json_bytes(result)),
        (args.report_out, _json_bytes(result["report"])),
    ])
    print(json.dumps(result["report"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
