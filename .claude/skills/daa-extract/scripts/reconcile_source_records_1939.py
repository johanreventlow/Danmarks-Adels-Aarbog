#!/usr/bin/env python3
"""Reconcile legacy 1939 record keys with reviewed source-record geometry."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Mapping, Sequence

from coverage_1939 import deterministic_human_candidate_id
from dual_rendition_evidence_1939 import deterministic_candidate_id


class ReconciliationError(ValueError):
    """Raised when record reconciliation would require trusting drifted input."""


PAGE_MARKER_RE = re.compile(r"^### PAGE \d+ ###$", re.M)


def _sha256(value: object, field: str) -> str:
    if not isinstance(value, str):
        raise ReconciliationError(f"{field} kræves")
    value = value.lower()
    if len(value) != 64 or any(char not in "0123456789abcdef" for char in value):
        raise ReconciliationError(f"{field} er ugyldig")
    return value


def _text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReconciliationError(f"{field} kræves")
    return value


def _span(value: object, field: str, source_length: int) -> tuple[int, int]:
    if not isinstance(value, Mapping):
        raise ReconciliationError(f"{field} kræves")
    start, end = value.get("char_from"), value.get("char_to")
    if (type(start) is not int or type(end) is not int or start < 0
            or end <= start or end > source_length):
        raise ReconciliationError(f"{field} er ugyldigt")
    return start, end


def _baseline_records(records: object) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    if not isinstance(records, Sequence) or isinstance(records, (str, bytes)) or not records:
        raise ReconciliationError("baseline records kræves")
    ordered = []
    by_key = {}
    for raw in records:
        if not isinstance(raw, Mapping):
            raise ReconciliationError("baseline record skal være et objekt")
        key = _text(raw.get("record_key"), "baseline record_key")
        if key in by_key:
            raise ReconciliationError("baseline har dublet record_key")
        record = dict(raw)
        ordered.append(record)
        by_key[key] = record
    return ordered, by_key


def _new_records(materialization: Mapping[str, Any], ledger: Mapping[str, Any]) -> tuple[str, str, list[dict[str, Any]]]:
    report = materialization.get("report")
    review = materialization.get("source_record_review")
    if (materialization.get("schema_version") != "1.0" or not isinstance(report, Mapping)
            or report.get("materialization_gate") != "GO" or not isinstance(review, Mapping)):
        raise ReconciliationError("komplet GO-materialisering kræves")
    source_text = _text(review.get("rendition_text"), "rendition_text")
    source_hash = _sha256(review.get("rendition_sha256"), "rendition_sha256")
    if hashlib.sha256(source_text.encode("utf-8")).hexdigest() != source_hash:
        raise ReconciliationError("rendition_text matcher ikke rendition_sha256")
    records = review.get("records")
    if not isinstance(records, list) or len(records) != report.get("accepted_record_candidates"):
        raise ReconciliationError("materialiseringens recordregnskab stemmer ikke")

    if not isinstance(ledger, Mapping) or ledger.get("schema_version") != "1.0":
        raise ReconciliationError("ledger schema_version 1.0 kræves")
    raw_entries = ledger.get("entries")
    if not isinstance(raw_entries, list):
        raise ReconciliationError("ledger entries kræves")
    ledger_by_acceptance = {}
    record_keys = set()
    for raw in raw_entries:
        if not isinstance(raw, Mapping):
            raise ReconciliationError("ledger entry skal være et objekt")
        acceptance_id = _text(raw.get("acceptance_id"), "ledger acceptance_id")
        record_key = _text(raw.get("record_key"), "ledger record_key")
        if acceptance_id in ledger_by_acceptance or record_key in record_keys:
            raise ReconciliationError("ledger har dublet identitet")
        ledger_by_acceptance[acceptance_id] = record_key
        record_keys.add(record_key)

    result = []
    previous_end = -1
    acceptance_ids = set()
    for raw in records:
        if not isinstance(raw, Mapping):
            raise ReconciliationError("materialiseret record skal være et objekt")
        acceptance_id = _text(raw.get("acceptance_id"), "acceptance_id")
        if acceptance_id in acceptance_ids:
            raise ReconciliationError("materialisering har dublet acceptance_id")
        acceptance_ids.add(acceptance_id)
        start, end = _span(raw.get("source_anchor"), "source_anchor", len(source_text))
        if start < previous_end:
            raise ReconciliationError("nye source records overlapper")
        if source_text[start:end] != raw.get("verbatim_text"):
            raise ReconciliationError("ny source record matcher ikke rendition_text")
        record_key = ledger_by_acceptance.get(acceptance_id)
        if record_key is None:
            raise ReconciliationError("materialiseret record mangler i ledger")
        result.append({
            "acceptance_id": acceptance_id,
            "record_key": record_key,
            "char_from": start,
            "char_to": end,
        })
        previous_end = end
    if set(ledger_by_acceptance) != acceptance_ids:
        raise ReconciliationError("ledger og materialisering har forskelligt recordregnskab")
    return source_text, source_hash, result


def _evidence_entries(evidence: Mapping[str, Any], baseline_keys: set[str], *,
                      baseline_sha256: str, source_sha256: str) -> dict[str, Mapping[str, Any]]:
    source = evidence.get("source")
    if evidence.get("schema_version") != 1 or not isinstance(source, Mapping):
        raise ReconciliationError("evidence schema_version 1 kræves")
    if source.get("edition") != "1939" or source.get("profile_version") != "1939-v2":
        raise ReconciliationError("evidence har forkert kildeprofil")
    if _sha256(source.get("baseline_sha256"), "evidence baseline_sha256") != baseline_sha256:
        raise ReconciliationError("evidence baseline_sha256 matcher ikke baseline")
    if _sha256(source.get("calamari_sha256"), "evidence calamari_sha256") != source_sha256:
        raise ReconciliationError("evidence calamari_sha256 matcher ikke materialisering")
    entries = evidence.get("entries")
    if not isinstance(entries, list):
        raise ReconciliationError("evidence entries kræves")
    by_key = {}
    for entry in entries:
        if not isinstance(entry, Mapping):
            raise ReconciliationError("evidence entry skal være et objekt")
        key = _text(entry.get("baseline_record_key"), "evidence baseline_record_key")
        if key in by_key:
            raise ReconciliationError("evidence har dublet baseline_record_key")
        by_key[key] = entry
    if set(by_key) != baseline_keys:
        raise ReconciliationError("evidence dækker ikke baseline record_keys præcist")
    return by_key


def _find_all(source_text: str, needle: str) -> list[tuple[int, int]]:
    result = []
    offset = 0
    while True:
        found = source_text.find(needle, offset)
        if found < 0:
            return result
        result.append((found, found + len(needle)))
        offset = found + 1


def _relation(old_start: int, old_end: int, new_start: int, new_end: int) -> str:
    if (old_start, old_end) == (new_start, new_end):
        return "exact_span"
    if new_start <= old_start and old_end <= new_end:
        return "old_inside_new"
    if old_start <= new_start and new_end <= old_end:
        return "new_inside_old"
    return "partial_overlap"


def _boundary_delta(source_text: str, old_start: int, old_end: int,
                    new_start: int, new_end: int) -> str:
    parts = []
    if old_start < new_start:
        parts.append(source_text[old_start:min(old_end, new_start)])
    if new_start < old_start:
        parts.append(source_text[new_start:min(new_end, old_start)])
    if old_end < new_end:
        parts.append(source_text[max(new_start, old_end):new_end])
    if new_end < old_end:
        parts.append(source_text[max(old_start, new_end):old_end])
    return "".join(parts)


def _mechanical_boundary_basis(entry: Mapping[str, Any], baseline: Mapping[str, Any],
                               new_record: Mapping[str, Any], source_text: str) -> str | None:
    old_span = entry.get("source_span")
    if not isinstance(old_span, Mapping):
        return None
    old_start, old_end = old_span["char_from"], old_span["char_to"]
    new_start, new_end = new_record["char_from"], new_record["char_to"]
    narrative = baseline.get("narrative")
    if isinstance(narrative, str) and narrative:
        exact = _find_all(source_text, narrative)
        if (len(exact) == 1 and new_start <= exact[0][0]
                and exact[0][1] <= new_end):
            return "unique_exact_narrative_inside_new"
    delta = _boundary_delta(
        source_text, old_start, old_end, new_start, new_end
    )
    if not PAGE_MARKER_RE.sub("", delta).strip():
        return "layout_only_boundary_delta"
    return None


def build_reconciliation(baseline_records: object, evidence: Mapping[str, Any],
                         materialization: Mapping[str, Any], ledger: Mapping[str, Any], *,
                         baseline_sha256: str) -> dict[str, Any]:
    """Build a review queue without treating layout order or names as identity."""
    baseline_sha256 = _sha256(baseline_sha256, "baseline_sha256")
    ordered_baseline, baseline_by_key = _baseline_records(baseline_records)
    source_text, source_sha256, new_records = _new_records(materialization, ledger)
    evidence_by_key = _evidence_entries(
        evidence, set(baseline_by_key), baseline_sha256=baseline_sha256,
        source_sha256=source_sha256,
    )

    preliminary = []
    prior_count = exact_narrative_count = 0
    for baseline in ordered_baseline:
        key = baseline["record_key"]
        entry = evidence_by_key[key]
        provenance = entry.get("positive_provenance")
        evidence_method = None
        source_span = None
        unresolved_reason = None
        if provenance is not None:
            if (not isinstance(provenance, Mapping)
                    or provenance.get("baseline_record_key") != key
                    or entry.get("conflicts") or entry.get("source_blockers")):
                raise ReconciliationError("positiv provenance er intern inkonsistent")
            candidate_id = _text(provenance.get("candidate_id"), "positive candidate_id")
            candidates = entry.get("candidates")
            if not isinstance(candidates, list):
                raise ReconciliationError("positive provenance mangler candidates")
            selected = [candidate for candidate in candidates
                        if isinstance(candidate, Mapping) and candidate.get("candidate_id") == candidate_id]
            if len(selected) != 1:
                raise ReconciliationError("positive candidate_id er ikke entydig")
            candidate = selected[0]
            start, end = _span(candidate.get("calamari_span"), "positive calamari_span", len(source_text))
            provenance_kind = provenance.get("kind")
            if provenance_kind == "human_approved_span_v1":
                approval = candidate.get("approval")
                excerpt_sha256 = hashlib.sha256(
                    source_text[start:end].encode("utf-8")
                ).hexdigest()
                if (not isinstance(approval, Mapping)
                        or approval.get("kind") != "human_approved_span_v1"
                        or approval.get("calamari_excerpt_sha256") != excerpt_sha256):
                    raise ReconciliationError("human approval matcher ikke kildespænd")
                try:
                    expected_id = deterministic_human_candidate_id(
                        "1939-v2", start, end, excerpt_sha256
                    )
                except ValueError as exc:
                    raise ReconciliationError("human approval er ugyldig") from exc
                if candidate_id != expected_id:
                    raise ReconciliationError("human approval candidate_id er ugyldig")
            elif provenance_kind == "dual_rendition_consensus_v1":
                bridge = candidate.get("raw_structure_bridge")
                if (not isinstance(bridge, Mapping)
                        or bridge.get("kind") != "dual_rendition_consensus_v1"):
                    raise ReconciliationError("dual rendition bridge mangler")
                raw_from, raw_to = bridge.get("raw_char_from"), bridge.get("raw_char_to")
                if (type(raw_from) is not int or type(raw_to) is not int
                        or raw_from < 0 or raw_to <= raw_from):
                    raise ReconciliationError("dual rendition raw span er ugyldigt")
                _sha256(bridge.get("raw_excerpt_sha256"), "raw_excerpt_sha256")
                expected_id = deterministic_candidate_id(
                    key,
                    {"char_from": start, "char_to": end},
                    {"char_from": raw_from, "char_to": raw_to},
                    dict(evidence["source"]),
                )
                if candidate_id != expected_id:
                    raise ReconciliationError("dual rendition candidate_id er ugyldig")
            else:
                raise ReconciliationError("ukendt positiv provenance kind")
            evidence_method = "prior_positive_span"
            source_span = (start, end)
            prior_count += 1
        else:
            narrative = baseline.get("narrative")
            if not isinstance(narrative, str) or not narrative:
                unresolved_reason = "missing_narrative"
            else:
                exact = _find_all(source_text, narrative)
                if not exact:
                    unresolved_reason = "narrative_not_exact"
                elif len(exact) > 1:
                    unresolved_reason = "narrative_repeated_exact"
                else:
                    start, end = exact[0]
                    owners = [record for record in new_records
                              if record["char_from"] <= start and end <= record["char_to"]]
                    if len(owners) != 1:
                        unresolved_reason = "unique_exact_narrative_outside_new_record"
                        source_span = (start, end)
                    else:
                        evidence_method = "unique_exact_narrative"
                        source_span = (start, end)
                        exact_narrative_count += 1

        matches = []
        if evidence_method == "prior_positive_span" and source_span is not None:
            start, end = source_span
            for new in new_records:
                if new["char_from"] < end and new["char_to"] > start:
                    matches.append({
                        "new_record_key": new["record_key"],
                        "geometry_relation": _relation(
                            start, end, new["char_from"], new["char_to"]
                        ),
                    })
            if not matches:
                unresolved_reason = "prior_positive_span_without_new_record"
        elif evidence_method == "unique_exact_narrative" and source_span is not None:
            start, end = source_span
            owner = next(record for record in new_records
                         if record["char_from"] <= start and end <= record["char_to"])
            matches = [{
                "new_record_key": owner["record_key"],
                "geometry_relation": "narrative_inside_new",
            }]

        preliminary.append({
            "baseline_record_key": key,
            "name": baseline.get("navn"),
            "evidence_method": evidence_method,
            "source_span": (None if source_span is None else {
                "char_from": source_span[0], "char_to": source_span[1],
            }),
            "matches": matches,
            "unresolved_reason": unresolved_reason,
        })

    owners: dict[str, list[str]] = defaultdict(list)
    match_counts = {}
    for entry in preliminary:
        match_counts[entry["baseline_record_key"]] = len(entry["matches"])
        for match in entry["matches"]:
            owners[match["new_record_key"]].append(entry["baseline_record_key"])

    new_by_key = {record["record_key"]: record for record in new_records}
    baseline_entries = []
    disposition_by_old = {}
    for entry in preliminary:
        matches = entry["matches"]
        target_has_multiple = any(len(owners[match["new_record_key"]]) > 1 for match in matches)
        reconciliation_basis = None
        if not matches:
            disposition = "unresolved"
        elif len(matches) > 1 and target_has_multiple:
            disposition = "split_merge_review"
        elif len(matches) > 1:
            disposition = "split_review"
        elif target_has_multiple:
            disposition = "merge_review"
        elif entry["evidence_method"] == "unique_exact_narrative":
            disposition = "text_anchor_review"
        elif matches[0]["geometry_relation"] == "exact_span":
            disposition = "unchanged"
            reconciliation_basis = "exact_positive_span"
        else:
            reconciliation_basis = _mechanical_boundary_basis(
                entry,
                baseline_by_key[entry["baseline_record_key"]],
                new_by_key[matches[0]["new_record_key"]],
                source_text,
            )
            disposition = ("unchanged" if reconciliation_basis is not None
                           else "boundary_change_review")
        disposition_by_old[entry["baseline_record_key"]] = disposition
        output = {key: value for key, value in entry.items() if value is not None}
        output["disposition"] = disposition
        if reconciliation_basis is not None:
            output["reconciliation_basis"] = reconciliation_basis
        baseline_entries.append(output)

    new_entries = []
    for new in new_records:
        old_keys = owners.get(new["record_key"], [])
        if not old_keys:
            disposition = "unmatched_new_review"
        elif len(old_keys) > 1:
            disposition = ("split_merge_review" if any(match_counts[key] > 1 for key in old_keys)
                           else "merge_review")
        else:
            disposition = disposition_by_old[old_keys[0]]
        new_entries.append({
            "new_record_key": new["record_key"],
            "source_span": {"char_from": new["char_from"], "char_to": new["char_to"]},
            "baseline_record_keys": old_keys,
            "disposition": disposition,
        })

    baseline_counts = Counter(entry["disposition"] for entry in baseline_entries)
    new_counts = Counter(entry["disposition"] for entry in new_entries)
    unchanged_bases = Counter(
        entry["reconciliation_basis"] for entry in baseline_entries
        if entry["disposition"] == "unchanged"
    )
    gate = ("GO" if baseline_counts == {"unchanged": len(baseline_entries)}
            and new_counts == {"unchanged": len(new_entries)} else "NO-GO")
    return {
        "schema_version": "1.0",
        "source": {
            "edition": "1939",
            "baseline_sha256": baseline_sha256,
            "calamari_sha256": source_sha256,
        },
        "baseline_entries": baseline_entries,
        "new_entries": new_entries,
        "report": {
            "baseline_total": len(baseline_entries),
            "new_total": len(new_entries),
            "prior_positive_anchors": prior_count,
            "unique_exact_narrative_anchors": exact_narrative_count,
            "baseline_dispositions": dict(sorted(baseline_counts.items())),
            "new_dispositions": dict(sorted(new_counts.items())),
            "unchanged_bases": dict(sorted(unchanged_bases.items())),
            "reconciliation_gate": gate,
        },
    }


def _load_json_bytes(path: Path, label: str) -> tuple[bytes, object]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result = {}
        for key, value in pairs:
            if key in result:
                raise ReconciliationError(f"{label} har dublet JSON-feltnavn")
            result[key] = value
        return result

    try:
        payload = path.read_bytes()
        value = json.loads(payload.decode("utf-8"), object_pairs_hook=reject_duplicates)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ReconciliationError(f"{label} kunne ikke læses") from exc
    return payload, value


def _json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _write_outputs(outputs: list[tuple[Path, bytes]]) -> None:
    paths = [path for path, _ in outputs]
    if len(paths) != len(set(paths)):
        raise ReconciliationError("outputstier skal være forskellige")
    created = []
    try:
        for path, payload in outputs:
            with path.open("xb") as handle:
                created.append(path)
                handle.write(payload)
    except FileExistsError as exc:
        for path in created:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        raise ReconciliationError("outputfil findes allerede") from exc
    except BaseException:
        for path in created:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--materialization", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--report-out", type=Path, required=True)
    args = parser.parse_args(argv)

    baseline_bytes, baseline = _load_json_bytes(args.baseline, "baseline")
    _, evidence = _load_json_bytes(args.evidence, "evidence")
    _, materialization = _load_json_bytes(args.materialization, "materialisering")
    _, ledger = _load_json_bytes(args.ledger, "ledger")
    if not isinstance(evidence, Mapping) or not isinstance(materialization, Mapping) or not isinstance(ledger, Mapping):
        raise ReconciliationError("evidence, materialisering og ledger skal være JSON-objekter")
    result = build_reconciliation(
        baseline,
        evidence,
        materialization,
        ledger,
        baseline_sha256=hashlib.sha256(baseline_bytes).hexdigest(),
    )
    _write_outputs([
        (args.out, _json_bytes(result)),
        (args.report_out, _json_bytes(result["report"])),
    ])
    print(json.dumps(result["report"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
