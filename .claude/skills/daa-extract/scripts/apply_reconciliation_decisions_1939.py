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
    "accepted_genuinely_new_source_record", "retired_duplicate", "retired_fragment",
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


def _span(value: object, field: str) -> dict[str, int]:
    if (not isinstance(value, Mapping) or set(value) != {"char_from", "char_to"}
            or type(value.get("char_from")) is not int
            or type(value.get("char_to")) is not int
            or value["char_from"] < 0
            or value["char_to"] <= value["char_from"]):
        raise DecisionError(f"{field} skal være et gyldigt kildespænd")
    return {"char_from": value["char_from"], "char_to": value["char_to"]}


def _span_difference(stale: Mapping[str, int], selected: Mapping[str, int]) -> list[dict[str, int]]:
    """Return the ordered half-open interval difference stale - selected."""
    result = []
    if stale["char_from"] < selected["char_from"]:
        end = min(stale["char_to"], selected["char_from"])
        if stale["char_from"] < end:
            result.append({"char_from": stale["char_from"], "char_to": end})
    if selected["char_to"] < stale["char_to"]:
        start = max(stale["char_from"], selected["char_to"])
        if start < stale["char_to"]:
            result.append({"char_from": start, "char_to": stale["char_to"]})
    if not result and (selected["char_to"] <= stale["char_from"]
                       or stale["char_to"] <= selected["char_from"]):
        result.append(dict(stale))
    return result


def _unresolved_disposition(entry: Mapping[str, Any], owners: Mapping[str, list[str]]) -> str:
    original = entry.get("disposition")
    if original in {"retired_duplicate", "retired_fragment"}:
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


def _validate_historical_spanless_adoptions(
        baseline_entries: Sequence[Mapping[str, Any]],
        new_entries: Sequence[Mapping[str, Any]],
        owners: Mapping[str, list[str]],
        new_by_key: Mapping[str, Mapping[str, Any]],
) -> None:
    """Reject any partial or mismatched spanless-baseline adoption graph."""
    adoptions_by_baseline: dict[str, str] = {}
    adoptions_by_target: dict[str, str] = {}
    baseline_markers = set()
    target_markers = set()

    for baseline in baseline_entries:
        key = _text(baseline.get("baseline_record_key"), "baseline_record_key")
        matches = baseline.get("matches")
        has_recovered_match = (
            isinstance(matches, list)
            and any(
                isinstance(match, Mapping)
                and match.get("geometry_relation")
                == "human_recovered_spanless_baseline"
                for match in matches
            )
        )
        is_adoption = (
            baseline.get("reconciliation_basis") == "human_adopted_spanless_baseline"
        )
        if is_adoption or has_recovered_match or "spanless_baseline_recovery" in baseline:
            baseline_markers.add(key)
        if not is_adoption:
            continue
        if ("source_span" in baseline
                or baseline.get("disposition") != "accepted_carryover"
                or not isinstance(matches, list)
                or len(matches) != 1
                or not isinstance(matches[0], Mapping)
                or set(matches[0]) != {"new_record_key", "geometry_relation"}
                or matches[0].get("geometry_relation")
                != "human_recovered_spanless_baseline"):
            raise DecisionError("historisk spanless adoption-baseline er ugyldig")
        target_key = _text(matches[0].get("new_record_key"), "historisk adoption target")
        if (baseline.get("selected_new_record_key") != target_key
                or target_key not in new_by_key):
            raise DecisionError("historisk spanless adoption mangler præcist mål")
        recovery = baseline.get("spanless_baseline_recovery")
        if (not isinstance(recovery, Mapping)
                or set(recovery) != {"selected_new_source_span", "reason"}
                or recovery.get("reason")
                != "spanless_baseline_exact_source_recovery"):
            raise DecisionError("historisk spanless adoption-recovery er ugyldig")
        _span(recovery.get("selected_new_source_span"), "historisk adoption kildespænd")
        _text(baseline.get("reviewed_by"), "historisk adoption reviewed_by")
        _text(baseline.get("decision_batch"), "historisk adoption decision_batch")
        if key in adoptions_by_baseline or target_key in adoptions_by_target:
            raise DecisionError("historisk spanless adoption har dublet ejer eller mål")
        adoptions_by_baseline[key] = target_key
        adoptions_by_target[target_key] = key

    for target in new_entries:
        key = _text(target.get("new_record_key"), "new_record_key")
        is_adoption = (
            target.get("reconciliation_basis") == "human_adopted_spanless_baseline"
        )
        if is_adoption or "prior_genuinely_new_acceptance" in target:
            target_markers.add(key)
        if key not in adoptions_by_target and not is_adoption:
            continue
        if not is_adoption:
            raise DecisionError("historisk spanless adoption-target er delvis")
        baseline_key = adoptions_by_target.get(key)
        if (baseline_key is None
                or target.get("record_kind") != "unclassified"
                or target.get("disposition") != "accepted_carryover"
                or target.get("baseline_record_keys") != [baseline_key]
                or owners.get(key, []) != [baseline_key]
                or "acceptance_basis" in target
                or "human_annotation" in target):
            raise DecisionError("historisk spanless adoption-target er ugyldig")
        prior = target.get("prior_genuinely_new_acceptance")
        if (not isinstance(prior, Mapping)
                or set(prior) != {
                    "acceptance_basis", "reviewed_by", "decision_batch",
                }
                or prior.get("acceptance_basis")
                != "human_verified_genuinely_new_source_record"):
            raise DecisionError("historisk spanless adoption mangler prior acceptance")
        _text(prior.get("reviewed_by"), "historisk prior reviewed_by")
        _text(prior.get("decision_batch"), "historisk prior decision_batch")
        baseline = next(
            entry for entry in baseline_entries
            if entry.get("baseline_record_key") == baseline_key
        )
        recovery = baseline["spanless_baseline_recovery"]
        if (_span(target.get("source_span"), "historisk target source_span")
                != _span(recovery["selected_new_source_span"], "historisk recovery span")
                or target.get("reviewed_by") != baseline.get("reviewed_by")
                or target.get("decision_batch") != baseline.get("decision_batch")):
            raise DecisionError("historisk spanless adoption-metadata matcher ikke")

    if baseline_markers != set(adoptions_by_baseline):
        raise DecisionError("historisk spanless adoption-baseline er delvis")
    if target_markers != set(adoptions_by_target):
        raise DecisionError("historisk spanless adoption-target er delvis")


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
    original_owners: dict[str, list[str]] = defaultdict(list)
    for entry in baseline_entries:
        matches = entry.get("matches", [])
        if not isinstance(matches, list):
            raise DecisionError("baseline matches skal være en liste")
        for match in matches:
            if isinstance(match, Mapping) and match.get("new_record_key") in new_by_key:
                original_owners[match["new_record_key"]].append(entry["baseline_record_key"])
    for entry in new_entries:
        declared_owners = entry.get("baseline_record_keys")
        if (not isinstance(declared_owners, list)
                or any(type(owner) is not str or owner not in old_by_key
                       for owner in declared_owners)
                or len(declared_owners) != len(set(declared_owners))
                or declared_owners != original_owners[entry["new_record_key"]]):
            raise DecisionError("new-entry baseline-ejere matcher ikke forward matches")
        if entry.get("disposition") == "accepted_genuinely_new_source_record":
            if (entry.get("record_kind") != "unclassified"
                    or declared_owners != []
                    or original_owners[entry["new_record_key"]] != []
                    or "human_annotation" in entry
                    or entry.get("acceptance_basis")
                    != "human_verified_genuinely_new_source_record"):
                raise DecisionError("tidligere genuinely-new acceptance er ugyldig")
            _text(entry.get("reviewed_by"), "genuinely-new reviewed_by")
            _text(entry.get("decision_batch"), "genuinely-new decision_batch")
    _validate_historical_spanless_adoptions(
        baseline_entries, new_entries, original_owners, new_by_key,
    )
    raw_decisions = _objects(decisions.get("decisions"), "decisions")
    if not raw_decisions:
        raise DecisionError("mindst én decision kræves")

    decision_by_old = {}
    retirement_by_retired = {}
    retirement_by_canonical = {}
    legacy_anchor_repairs = {}
    legacy_repair_targets = {
        entry["selected_new_record_key"] for entry in baseline_entries
        if entry.get("reconciliation_basis") == "human_repaired_legacy_anchor"
        and isinstance(entry.get("selected_new_record_key"), str)
    }
    affected_old_keys = set()
    selected_targets = set()
    annotation_by_new = {}
    genuinely_new_acceptances = {}
    spanless_adoptions = {}
    spanless_adoptions_by_target = {}
    for decision in raw_decisions:
        if decision.get("decision_kind") == "accept_genuinely_new":
            if set(decision) != {
                "decision_kind", "new_record_key", "new_source_span",
                "record_kind", "reason",
            }:
                raise DecisionError("ukendt genuinely-new acceptance-handling")
            target = _text(decision.get("new_record_key"), "new_record_key")
            target_entry = new_by_key.get(target)
            if (decision.get("record_kind") != "unclassified"
                    or decision.get("reason")
                    != "visually_verified_distinct_source_record"
                    or target_entry is None
                    or target_entry.get("record_kind") != "unclassified"
                    or _span(decision.get("new_source_span"), "new_source_span")
                    != _span(target_entry.get("source_span"), "target source_span")
                    or target_entry.get("disposition") != "unmatched_new_review"
                    or target_entry.get("baseline_record_keys") != []
                    or original_owners[target] != []
                    or any(field in target_entry for field in (
                        "human_annotation", "acceptance_basis", "reviewed_by",
                        "decision_batch",
                    ))):
                raise DecisionError(
                    "genuinely-new acceptance kræver ejerløs unmatched unclassified target"
                )
            if target in selected_targets or target in annotation_by_new:
                raise DecisionError("flere beslutninger bruger samme new_record_key")
            genuinely_new_acceptances[target] = dict(decision)
            selected_targets.add(target)
            continue
        old_key = _text(decision.get("baseline_record_key"), "decision baseline_record_key")
        if old_key in affected_old_keys:
            raise DecisionError("decision har modstridende baseline_record_key")
        old = old_by_key.get(old_key)
        if decision.get("decision_kind") == "adopt_genuinely_new_target":
            if set(decision) != {
                "baseline_record_key", "decision_kind", "selected_new_record_key",
                "selected_new_source_span", "reason",
            } or decision.get("reason") != "spanless_baseline_exact_source_recovery":
                raise DecisionError("ukendt spanless adoption-handling")
            target = _text(
                decision.get("selected_new_record_key"), "selected_new_record_key"
            )
            target_entry = new_by_key.get(target)
            if (old is None
                    or "source_span" in old
                    or old.get("disposition") != "unresolved"
                    or old.get("unresolved_reason") != "narrative_not_exact"
                    or old.get("matches") != []
                    or any(field in old for field in (
                        "selected_new_record_key", "reconciliation_basis", "reviewed_by",
                        "decision_batch", "human_annotation", "spanless_baseline_recovery",
                    ))
                    or target_entry is None
                    or target_entry.get("record_kind") != "unclassified"
                    or _span(decision.get("selected_new_source_span"), "selected_new_source_span")
                    != _span(target_entry.get("source_span"), "target source_span")
                    or target_entry.get("disposition")
                    != "accepted_genuinely_new_source_record"
                    or target_entry.get("baseline_record_keys") != []
                    or original_owners[target] != []
                    or any(field in target_entry for field in (
                        "human_annotation", "reconciliation_basis",
                        "prior_genuinely_new_acceptance",
                    ))
                    or target_entry.get("acceptance_basis")
                    != "human_verified_genuinely_new_source_record"):
                raise DecisionError(
                    "spanless adoption kræver ejerløs accepted genuinely-new target"
                )
            _text(target_entry.get("reviewed_by"), "genuinely-new reviewed_by")
            _text(target_entry.get("decision_batch"), "genuinely-new decision_batch")
            if target in selected_targets or target in annotation_by_new:
                raise DecisionError("flere beslutninger bruger samme new_record_key")
            affected_old_keys.add(old_key)
            selected_targets.add(target)
            spanless_adoptions[old_key] = (decision, target)
            spanless_adoptions_by_target[target] = old_key
            continue
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
            declared_owners = target_entry.get("baseline_record_keys")
            derived_owners = original_owners[target]
            if (not isinstance(declared_owners, list)
                    or any(type(owner) is not str for owner in declared_owners)
                    or len(declared_owners) != 2
                    or len(set(declared_owners)) != 2
                    or set(declared_owners) != {canonical_key, old_key}
                    or declared_owners != derived_owners):
                raise DecisionError(
                    "continuation fragment kræver præcise deklarerede baseline-ejere"
                )
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
        if decision.get("decision_kind") == "repair_legacy_anchor":
            if set(decision) != {
                "baseline_record_key", "decision_kind", "selected_new_record_key",
                "stale_source_span", "selected_new_source_span",
                "discarded_source_spans", "reason",
            } or decision.get("reason") != "neighbor_record_contamination":
                raise DecisionError("ukendt legacy-anchor repair-handling")
            selected = _text(
                decision.get("selected_new_record_key"), "selected_new_record_key"
            )
            target = new_by_key.get(selected)
            if (old is None or target is None
                    or old.get("disposition") != "unresolved"
                    or old.get("unresolved_reason")
                    != "unique_exact_narrative_outside_new_record"
                    or old.get("matches") != []
                    or target.get("disposition") != "unmatched_new_review"
                    or target.get("baseline_record_keys") != []
                    or "human_annotation" in target):
                raise DecisionError("legacy-anchor repair kræver ejerløs unresolved baseline og target")
            stale_span = _span(decision.get("stale_source_span"), "stale_source_span")
            selected_span = _span(
                decision.get("selected_new_source_span"), "selected_new_source_span"
            )
            if _span(old.get("source_span"), "baseline source_span") != stale_span:
                raise DecisionError("legacy-anchor repair har stale baseline-kildespænd")
            if _span(target.get("source_span"), "target source_span") != selected_span:
                raise DecisionError("legacy-anchor repair har forkert target-kildespænd")
            declared_discarded = _objects(
                decision.get("discarded_source_spans"), "discarded_source_spans"
            )
            discarded = [
                _span(span, "discarded_source_spans") for span in declared_discarded
            ]
            if not discarded:
                raise DecisionError("legacy-anchor repair kræver forkastede kildespænd")
            if any(
                discarded[index]["char_from"] >= discarded[index + 1]["char_from"]
                or discarded[index]["char_to"] > discarded[index + 1]["char_from"]
                for index in range(len(discarded) - 1)
            ):
                raise DecisionError("forkastede kildespænd skal være sorterede uden overlap")
            if discarded != _span_difference(stale_span, selected_span):
                raise DecisionError("forkastede kildespænd matcher ikke stale-minus-target")
            if (selected in selected_targets or selected in annotation_by_new
                    or selected in legacy_repair_targets):
                raise DecisionError("legacy-anchor repair genbruger eller annoterer target")
            affected_old_keys.add(old_key)
            selected_targets.add(selected)
            legacy_repair_targets.add(selected)
            legacy_anchor_repairs[old_key] = (decision, selected)
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
            if annotated in legacy_repair_targets:
                raise DecisionError("annotation må ikke berøre legacy-anchor repair-target")
            annotation_by_new[annotated] = dict(annotation)
        decision_by_old[old_key] = (
            decision, selected, "human_selected_split_target",
        )

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
        repair = legacy_anchor_repairs.get(old_key)
        adoption = spanless_adoptions.get(old_key)
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
        elif repair is not None:
            decision, target = repair
            output["matches"] = [{
                "new_record_key": target,
                "geometry_relation": "human_repaired_legacy_anchor",
            }]
            output["selected_new_record_key"] = target
            output["disposition"] = "accepted_carryover"
            output["reconciliation_basis"] = "human_repaired_legacy_anchor"
            output["reviewed_by"] = reviewed_by
            output["decision_batch"] = decision_batch
            output["legacy_anchor_repair"] = {
                "stale_source_span": dict(decision["stale_source_span"]),
                "selected_new_source_span": dict(decision["selected_new_source_span"]),
                "discarded_source_spans": [
                    dict(span) for span in decision["discarded_source_spans"]
                ],
                "reason": decision["reason"],
            }
        elif adoption is not None:
            decision, target = adoption
            output.pop("source_span", None)
            output["matches"] = [{
                "new_record_key": target,
                "geometry_relation": "human_recovered_spanless_baseline",
            }]
            output["selected_new_record_key"] = target
            output["disposition"] = "accepted_carryover"
            output["reconciliation_basis"] = "human_adopted_spanless_baseline"
            output["reviewed_by"] = reviewed_by
            output["decision_batch"] = decision_batch
            output["spanless_baseline_recovery"] = {
                "selected_new_source_span": dict(decision["selected_new_source_span"]),
                "reason": decision["reason"],
            }
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
              or entry["baseline_record_key"] in retirement_by_canonical
              or entry["baseline_record_key"] in legacy_anchor_repairs
              or entry["baseline_record_key"] in spanless_adoptions):
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
        if key in spanless_adoptions_by_target:
            output["prior_genuinely_new_acceptance"] = {
                "acceptance_basis": entry["acceptance_basis"],
                "reviewed_by": entry["reviewed_by"],
                "decision_batch": entry["decision_batch"],
            }
            output.pop("acceptance_basis", None)
            output["disposition"] = "accepted_carryover"
            output["reconciliation_basis"] = "human_adopted_spanless_baseline"
            output["reviewed_by"] = reviewed_by
            output["decision_batch"] = decision_batch
        elif key in genuinely_new_acceptances:
            output["disposition"] = "accepted_genuinely_new_source_record"
            output["acceptance_basis"] = "human_verified_genuinely_new_source_record"
            output["reviewed_by"] = reviewed_by
            output["decision_batch"] = decision_batch
        elif entry.get("disposition") == "accepted_genuinely_new_source_record":
            output["disposition"] = "accepted_genuinely_new_source_record"
        elif not old_keys:
            disposition = ("accepted_structural_context"
                           if entry.get("record_kind") == "structural_context"
                           else "unmatched_new_review")
            output["disposition"] = disposition
        elif len(old_keys) > 1:
            disposition = "merge_review"
            output["disposition"] = disposition
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
