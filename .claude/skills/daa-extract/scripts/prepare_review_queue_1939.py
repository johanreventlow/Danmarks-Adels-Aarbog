"""Build a lossless private view model for the 1939 exception review queue."""

from __future__ import annotations

import argparse
import copy
from collections import Counter
from collections.abc import Mapping
import hashlib
import json
from pathlib import Path

from coverage_1939 import (
    LEGACY_REVIEW_ALLOWED_FIELDS,
    POSTKLASSER,
    duplicate_target_errors,
    legacy_review_entry_errors,
)
from review_choices_1939 import validate_choice_export
from review_queue_1939 import (
    QUEUE_CLASSES,
    classify_review_entries,
    sample_auto_resolved,
)


_PRESENTATION_FIELDS = (
    "candidate_id", "lokal_id", "pdf_pages", "calamari_pages", "raw_text", "rank_reason",
)
_COMPLETED_STATUSES = {"menneskeark", "eksplicit_dublet", "accepteret"}
_PINNED_PROFILE_VERSION = "1939-v2"
_COLLISION_REASONS = (
    "candidate_collision", "calamari_span_overlap", "raw_ocr_span_overlap",
)
_SOURCE_FIELDS = {
    "edition", "baseline_sha256", "calamari_sha256", "raw_ocr_sha256",
    "pdf_sha256", "profile_version",
}
_EVIDENCE_ENTRY_FIELDS = {
    "baseline_record_key", "candidates", "positive_provenance", "conflicts",
    "source_blockers", "rule_id",
}
_CANDIDATE_FIELDS = {
    "candidate_id", "postklasse", "calamari_span", "pdf_pages",
    "raw_structure_bridge",
}


def _nonempty(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} skal være en ikke-tom streng")
    return value


def _deduplicate_candidates(candidates):
    """Keep one byte-for-byte presentation copy per id, in stable order."""
    by_id = {}
    for candidate in candidates:
        if not isinstance(candidate, Mapping):
            raise ValueError("candidate skal være en mapping")
        candidate_id = _nonempty(candidate.get("candidate_id"), "candidate_id")
        previous = by_id.get(candidate_id)
        if previous is not None and previous != candidate:
            raise ValueError("samme candidate_id har forskelligt indhold")
        by_id[candidate_id] = copy.deepcopy(dict(candidate))
    return [by_id[key] for key in sorted(by_id)]


def _presentation_candidate(candidate: Mapping) -> dict:
    candidate_id = _nonempty(candidate.get("candidate_id"), "candidate_id")
    missing = [field for field in _PRESENTATION_FIELDS if field not in candidate]
    if missing:
        raise ValueError(f"candidate mangler præsentationsfelt: {missing[0]}")
    value = {field: copy.deepcopy(candidate[field]) for field in _PRESENTATION_FIELDS}
    if value["candidate_id"] != candidate_id:
        raise ValueError("candidate_id er ugyldig")
    return value


def _anchored_presentation(candidate: Mapping) -> dict:
    """Expose an anchored candidate without dropping its private evidence."""
    candidate_id = _nonempty(candidate.get("candidate_id"), "candidate_id")
    return {
        "candidate_id": candidate_id,
        "lokal_id": copy.deepcopy(candidate.get("lokal_id", candidate_id)),
        "pdf_pages": copy.deepcopy(candidate.get("pdf_pages", [])),
        "calamari_pages": copy.deepcopy(candidate.get("calamari_pages", [])),
        "raw_text": copy.deepcopy(candidate.get("raw_text", "")),
        "rank_reason": copy.deepcopy(candidate.get("rank_reason", "forankret_evidens")),
        "details": copy.deepcopy(dict(candidate)),
    }


def _attach_anchored_details(candidates: list[dict], classification: Mapping) -> list[dict]:
    """Attach, rather than replace, a classifier's anchored evidence object."""
    if classification["queue_class"] != "auto_resolved":
        return candidates
    anchored = classification.get("candidate")
    if not isinstance(anchored, Mapping):
        raise ValueError("auto_resolved entry kræver candidate")
    candidate_id = _nonempty(anchored.get("candidate_id"), "candidate_id")
    by_id = {candidate["candidate_id"]: candidate for candidate in candidates}
    if candidate_id in by_id:
        by_id[candidate_id]["details"] = copy.deepcopy(dict(anchored))
    else:
        candidates.append(_anchored_presentation(anchored))
        candidates.sort(key=lambda candidate: candidate["candidate_id"])
    return candidates


def _attach_accepted_review(candidates: list[dict], decision: Mapping | None) -> list[dict]:
    """Keep an authoritatively accepted manual anchor inspectable across page boundaries."""
    if not isinstance(decision, Mapping) or decision.get("review_status") != "accepteret":
        return candidates
    candidate_id = _nonempty(decision.get("candidate_id"), "candidate_id")
    by_id = {candidate["candidate_id"]: candidate for candidate in candidates}
    if candidate_id in by_id:
        by_id[candidate_id]["accepted_review_details"] = copy.deepcopy(dict(decision))
        return candidates
    candidates.append({
        "candidate_id": candidate_id,
        "lokal_id": candidate_id,
        "pdf_pages": copy.deepcopy(decision.get("pdf_pages", [])),
        "calamari_pages": [],
        "raw_text": copy.deepcopy(
            decision.get("raw_verbatim_text", decision.get("calamari_verbatim_text", ""))
        ),
        "rank_reason": "accepteret_review_evidens",
        "accepted_review_details": copy.deepcopy(dict(decision)),
    })
    candidates.sort(key=lambda candidate: candidate["candidate_id"])
    return candidates


def _baseline_index(baseline: object) -> tuple[list[dict], set[str]]:
    if not isinstance(baseline, list):
        raise ValueError("baseline skal være en liste")
    records = []
    keys: set[str] = set()
    for value in baseline:
        if not isinstance(value, Mapping):
            raise ValueError("baseline record skal være en mapping")
        record = copy.deepcopy(dict(value))
        key = _nonempty(record.get("record_key"), "record_key")
        if key in keys:
            raise ValueError("dublet baseline_record_key")
        keys.add(key)
        records.append(record)
    return records, keys


def _manifest_index(manifest: object, baseline_keys: set[str]) -> tuple[dict[str, dict], dict]:
    if not isinstance(manifest, Mapping):
        raise ValueError("manifest skal være en mapping")
    # Task 2's sampler validates the Task 1 manifest grammar; it is deliberately
    # reused here instead of recreating a second classifier/validator.
    sample_auto_resolved(dict(manifest))
    entries = manifest.get("entries")
    if not isinstance(entries, list):
        raise ValueError("manifest entries skal være en liste")
    by_key: dict[str, dict] = {}
    for value in entries:
        if not isinstance(value, Mapping):
            raise ValueError("manifest entry skal være en mapping")
        entry = copy.deepcopy(dict(value))
        key = _nonempty(entry.get("baseline_record_key"), "baseline_record_key")
        if key in by_key:
            raise ValueError("dublet baseline_record_key")
        if entry.get("queue_class") not in QUEUE_CLASSES:
            raise ValueError("ukendt queue_class")
        by_key[key] = entry
    if set(by_key) != baseline_keys:
        raise ValueError("baseline-dækning fejler")
    return by_key, copy.deepcopy(dict(manifest["source"]))


def _decision_for(key: str, decisions: Mapping) -> dict | None:
    value = decisions.get(key)
    if value is None:
        return None
    if not isinstance(value, Mapping):
        raise ValueError("review decision skal være en mapping")
    decision = copy.deepcopy(dict(value))
    declared_key = decision.get("baseline_record_key")
    if declared_key is not None and declared_key != key:
        raise ValueError("review decision har forkert baseline_record_key")
    return decision


def _is_completed(decision: dict | None) -> bool:
    if decision is None:
        return False
    status = decision.get("review_status", decision.get("status"))
    if status in (None, "", "unreviewed"):
        return False
    if status not in _COMPLETED_STATUSES:
        raise ValueError("ukendt review_status")
    return True


def _view_record(record: dict, classification: dict, nearby: list[dict], is_audit: bool,
                 decision: dict | None) -> dict:
    candidates = [_presentation_candidate(candidate) for candidate in nearby]
    candidates = _attach_anchored_details(candidates, classification)
    candidates = _attach_accepted_review(candidates, decision)
    initial_candidate_ids = [candidate["candidate_id"] for candidate in candidates[:3]]
    if isinstance(decision, Mapping) and decision.get("review_status") == "accepteret":
        accepted_candidate_id = _nonempty(decision.get("candidate_id"), "candidate_id")
        if accepted_candidate_id not in initial_candidate_ids:
            initial_candidate_ids.append(accepted_candidate_id)
    queue_class = classification["queue_class"]
    completed = _is_completed(decision)
    return {
        "record_key": record["record_key"],
        "navn": copy.deepcopy(record.get("navn")),
        "sider": copy.deepcopy(record.get("sider")),
        "narrative": copy.deepcopy(record.get("narrative")),
        "classification": copy.deepcopy(classification),
        "queue_class": queue_class,
        "reason_code": copy.deepcopy(classification.get("reason_code")),
        "reason_da": copy.deepcopy(classification.get("reason_da")),
        "is_audit": is_audit,
        "is_completed": completed,
        "candidate_count": len(candidates),
        "initial_candidate_ids": initial_candidate_ids,
        "candidates": candidates,
        "decision": decision,
    }


def build_review_view_model(baseline: list[dict], manifest: dict,
                            nearby_candidates: dict[str, list[dict]],
                            audit_keys: list[str], decisions: dict[str, dict]) -> dict:
    """Build all queue views without allowing a display aid to change a class."""
    records, baseline_keys = _baseline_index(baseline)
    by_key, source = _manifest_index(manifest, baseline_keys)
    if not isinstance(nearby_candidates, Mapping):
        raise ValueError("nearby_candidates skal være en mapping")
    if set(nearby_candidates) - baseline_keys:
        raise ValueError("nearby candidate har ukendt baseline_record_key")
    if not isinstance(audit_keys, list) or any(not isinstance(key, str) for key in audit_keys):
        raise ValueError("audit_keys skal være en liste af strenge")
    audit_set = set(audit_keys)
    if len(audit_set) != len(audit_keys):
        raise ValueError("dublet audit baseline_record_key")
    if not audit_set <= baseline_keys:
        raise ValueError("audit har ukendt baseline_record_key")
    if any(by_key[key]["queue_class"] != "auto_resolved" for key in audit_set):
        raise ValueError("audit kræver auto_resolved entry")
    if not isinstance(decisions, Mapping):
        raise ValueError("decisions skal være en mapping")
    if set(decisions) - baseline_keys:
        raise ValueError("review decision har ukendt baseline_record_key")

    view_records = []
    for record in records:
        key = record["record_key"]
        nearby = _deduplicate_candidates(nearby_candidates.get(key, []))
        view_records.append(_view_record(
            record, by_key[key], nearby, key in audit_set, _decision_for(key, decisions),
        ))

    views = {
        "required": [record["record_key"] for record in view_records
                     if record["queue_class"] in {"human_required", "source_blocked"}],
        "automatic": [record["record_key"] for record in view_records
                      if record["queue_class"] == "auto_resolved"],
        "audit": [record["record_key"] for record in view_records if record["is_audit"]],
        "completed": [record["record_key"] for record in view_records if record["is_completed"]],
    }
    return {
        "schema_version": 1,
        "source": source,
        "default_view": "required",
        "summary": {
            "required": len(views["required"]),
            "automatic": len(views["automatic"]),
            "audit": len(views["audit"]),
            "completed": len(views["completed"]),
            "source_blocked": sum(
                record["queue_class"] == "source_blocked" for record in view_records
            ),
        },
        "views": views,
        "records": view_records,
    }


def _queue_entries(manifest: object) -> tuple[list[dict], dict[str, dict]]:
    if not isinstance(manifest, Mapping) or manifest.get("schema_version") != 1:
        raise ValueError("queue manifest schema_version skal være 1")
    entries = manifest.get("entries")
    if not isinstance(entries, list):
        raise ValueError("queue manifest entries skal være en liste")
    copied: list[dict] = []
    by_key: dict[str, dict] = {}
    for value in entries:
        if not isinstance(value, Mapping):
            raise ValueError("queue entry skal være en mapping")
        entry = copy.deepcopy(dict(value))
        key = _nonempty(entry.get("baseline_record_key"), "baseline_record_key")
        if key in by_key:
            raise ValueError("dublet baseline_record_key")
        if entry.get("queue_class") not in QUEUE_CLASSES:
            raise ValueError("ukendt queue_class")
        _nonempty(entry.get("reason_code"), "reason_code")
        _nonempty(entry.get("reason_da"), "reason_da")
        copied.append(entry)
        by_key[key] = entry
    return copied, by_key


def _stratum(entry: Mapping) -> str:
    rule_id = entry.get("rule_id")
    postklasse = entry.get("postklasse")
    if not isinstance(rule_id, str) or not rule_id.strip():
        return "invalid|invalid"
    if not isinstance(postklasse, str) or not postklasse.strip():
        return "invalid|invalid"
    return f"{rule_id}|{postklasse}"


def build_queue_report(
    manifest: dict,
    *,
    audit_keys: list[str],
    completed_keys: set[str],
    audit_results: list[dict],
) -> dict:
    """Account for the private queue and keep publication fail-closed."""
    entries, by_key = _queue_entries(manifest)
    source = manifest.get("source")
    if not isinstance(source, Mapping):
        raise ValueError("source skal være en mapping")
    if (
        not isinstance(audit_keys, list)
        or any(not isinstance(key, str) or not key for key in audit_keys)
        or len(set(audit_keys)) != len(audit_keys)
    ):
        raise ValueError("audit_keys skal være unikke ikke-tomme strenge")
    audit_set = set(audit_keys)
    if not audit_set <= set(by_key):
        raise ValueError("audit har ukendt baseline_record_key")
    if any(by_key[key]["queue_class"] != "auto_resolved" for key in audit_set):
        raise ValueError("audit kræver auto_resolved entry")
    if (
        not isinstance(completed_keys, set)
        or any(not isinstance(key, str) or not key for key in completed_keys)
        or not completed_keys <= set(by_key)
    ):
        raise ValueError("completed_keys er ugyldige")
    if not isinstance(audit_results, list):
        raise ValueError("audit_results skal være en liste")

    result_by_key: dict[str, dict] = {}
    for value in audit_results:
        if not isinstance(value, Mapping):
            raise ValueError("audit result skal være en mapping")
        result = copy.deepcopy(dict(value))
        key = _nonempty(result.get("baseline_record_key"), "audit baseline_record_key")
        if key in result_by_key:
            raise ValueError("dublet audit baseline_record_key")
        if key not in audit_set:
            raise ValueError("audit result har ikke-samplet baseline_record_key")
        result_by_key[key] = result

    expected_audit_keys: list[str] = []
    automatic_candidates_valid = True
    try:
        expected_audit_keys = sample_auto_resolved(copy.deepcopy(manifest))
    except (TypeError, ValueError):
        automatic_candidates_valid = False
    audit_sample_matches = automatic_candidates_valid and set(expected_audit_keys) == audit_set

    reason_counts = Counter(entry["reason_code"] for entry in entries)
    stratum_counts = Counter(
        _stratum(entry) for entry in entries if entry["queue_class"] == "auto_resolved"
    )
    blocked_rule_groups: set[str] = set()
    for key in audit_set | set(expected_audit_keys):
        entry = by_key.get(key)
        group = _stratum(entry) if entry is not None else "invalid|invalid"
        result = result_by_key.get(key)
        if (
            entry is None
            or result is None
            or result.get("audit_status") != "audit_confirmed"
            or result.get("rule_id") != entry.get("rule_id")
        ):
            blocked_rule_groups.add(group)
    if not automatic_candidates_valid and any(
        entry["queue_class"] == "auto_resolved" for entry in entries
    ):
        blocked_rule_groups.add("invalid|invalid")

    counts = Counter(entry["queue_class"] for entry in entries)
    human_keys = {
        key for key, entry in by_key.items() if entry["queue_class"] == "human_required"
    }
    every_audit_confirmed = (
        len(result_by_key) == len(audit_set)
        and all(
            result_by_key[key].get("audit_status") == "audit_confirmed"
            for key in audit_set
        )
    )
    publication_ready = all((
        len(entries) == 546,
        automatic_candidates_valid,
        audit_sample_matches,
        every_audit_confirmed,
        human_keys <= completed_keys,
        counts["source_blocked"] == 0,
        not blocked_rule_groups,
    ))
    return {
        "schema_version": 1,
        "source": copy.deepcopy(dict(source)),
        "baseline_total": len(entries),
        "auto_resolved": counts["auto_resolved"],
        "human_required": counts["human_required"],
        "source_blocked": counts["source_blocked"],
        "audit": len(audit_keys),
        "completed": len(completed_keys),
        "reason_code_counts": dict(sorted(reason_counts.items())),
        "stratum_counts": dict(sorted(stratum_counts.items())),
        "collision_overlap_counts": {
            reason: reason_counts[reason] for reason in _COLLISION_REASONS
        },
        "automatic_candidates_valid": automatic_candidates_valid,
        "audit_sample_matches": audit_sample_matches,
        "audit_confirmed": sum(
            result.get("audit_status") == "audit_confirmed"
            for result in result_by_key.values()
        ),
        "audit_failed_or_undecidable": sum(
            result.get("audit_status") != "audit_confirmed"
            for result in result_by_key.values()
        ) + len(audit_set - set(result_by_key)),
        "audit_blocked_rule_groups": sorted(blocked_rule_groups),
        "publication_gate": "GO" if publication_ready else "NO-GO",
    }


def _strict_json_bytes(value: bytes, label: str) -> object:
    def reject_duplicate_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"{label} indeholder dublet JSON-feltnavn")
            result[key] = value
        return result

    try:
        text = value.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"{label} skal være UTF-8") from error
    return json.loads(text, object_pairs_hook=reject_duplicate_keys)


def _hash_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _decoded_source_text(value: bytes, label: str) -> str:
    try:
        return value.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"{label} skal være UTF-8") from error


def _nonnegative_int(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{label} skal være et ikke-negativt heltal")
    return value


def _strict_string_list(value: object, label: str) -> list[str]:
    if not isinstance(value, list):
        raise ValueError(f"{label} skal være en liste")
    return [_nonempty(item, label) for item in value]


def _is_schema_version_one(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value == 1


def _validate_source_bound_candidate(
    value: object, calamari_text: str, raw_text: str
) -> dict:
    if not isinstance(value, Mapping) or set(value) != _CANDIDATE_FIELDS:
        raise ValueError("evidence candidate har uautoriserede eller manglende felter")
    candidate = copy.deepcopy(dict(value))
    _nonempty(candidate.get("candidate_id"), "candidate_id")
    if candidate.get("postklasse") not in POSTKLASSER:
        raise ValueError("postklasse er ukendt")

    span = candidate.get("calamari_span")
    if not isinstance(span, Mapping) or set(span) != {"char_from", "char_to"}:
        raise ValueError("Calamari-span har uautoriserede eller manglende felter")
    char_from = _nonnegative_int(span.get("char_from"), "Calamari-span char_from")
    char_to = _nonnegative_int(span.get("char_to"), "Calamari-span char_to")
    if char_from >= char_to or char_to > len(calamari_text):
        raise ValueError("Calamari-span er uden for den aktuelle kilde")
    if not calamari_text[char_from:char_to]:
        raise ValueError("Calamari-span er tomt")

    pages = candidate.get("pdf_pages")
    if not isinstance(pages, list) or not pages:
        raise ValueError("PDF-side skal være en ikke-tom liste")
    if any(not isinstance(page, int) or isinstance(page, bool) or page <= 0 for page in pages):
        raise ValueError("PDF-side skal være et positivt heltal")

    bridge = candidate.get("raw_structure_bridge")
    bridge_fields = {"kind", "raw_char_from", "raw_char_to", "raw_excerpt_sha256"}
    if not isinstance(bridge, Mapping) or set(bridge) != bridge_fields:
        raise ValueError("rå-bro har uautoriserede eller manglende felter")
    _nonempty(bridge.get("kind"), "rå-bro kind")
    raw_from = _nonnegative_int(bridge.get("raw_char_from"), "rå-bro raw_char_from")
    raw_to = _nonnegative_int(bridge.get("raw_char_to"), "rå-bro raw_char_to")
    if raw_from >= raw_to or raw_to > len(raw_text):
        raise ValueError("rå-bro er uden for den aktuelle kilde")
    raw_excerpt = raw_text[raw_from:raw_to]
    if not raw_excerpt:
        raise ValueError("rå-bro er tom")
    if bridge.get("raw_excerpt_sha256") != _hash_bytes(raw_excerpt.encode("utf-8")):
        raise ValueError("raw_excerpt_sha256 matcher ikke den aktuelle rå-OCR-kilde")
    return candidate


def _source_less_evidence_entries(
    value: Mapping, source: dict, baseline_keys: set[str]
) -> list[dict]:
    allowed_root = {"schema_version", "baseline_sha256", "entries"}
    if set(value) - allowed_root or not {"baseline_sha256", "entries"} <= set(value):
        raise ValueError("source-løs evidence skal være en strikt unreviewed template")
    if not _is_schema_version_one(value.get("schema_version", 1)):
        raise ValueError("source-løs evidence schema_version skal være 1")
    if value.get("baseline_sha256") != source["baseline_sha256"]:
        raise ValueError("evidence baseline hash matcher ikke")
    entries = value.get("entries")
    if not isinstance(entries, list):
        raise ValueError("evidence entries skal være en liste")
    allowed_entry = {
        "baseline_record_key", "review_status", "baseline_locator", "review_note",
    }
    seen: set[str] = set()
    normalized: list[dict] = []
    for item in entries:
        if (
            not isinstance(item, Mapping)
            or set(item) - allowed_entry
            or not {"baseline_record_key", "review_status"} <= set(item)
            or item.get("review_status") != "unreviewed"
        ):
            raise ValueError("source-løs evidence kræver source for positive felter")
        key = _nonempty(item.get("baseline_record_key"), "baseline_record_key")
        if key not in baseline_keys:
            raise ValueError("evidence har ukendt baseline_record_key")
        if key in seen:
            raise ValueError("dublet evidence baseline_record_key")
        seen.add(key)
        _validate_review_metadata(item)
        normalized.append({
            "baseline_record_key": key,
            "candidates": [],
            "positive_provenance": None,
            "conflicts": [],
            "source_blockers": [],
            "rule_id": None,
        })
    if seen != baseline_keys:
        raise ValueError("source-løs evidence baseline-dækning fejler")
    return normalized


def _source_bound_evidence_entries(
    value: Mapping,
    source: dict,
    baseline_keys: set[str],
    calamari_text: str,
    raw_text: str,
) -> list[dict]:
    if set(value) != {"schema_version", "source", "entries"}:
        raise ValueError("evidence root har uautoriserede eller manglende felter")
    if not _is_schema_version_one(value.get("schema_version")):
        raise ValueError("evidence schema_version skal være 1")
    evidence_source = value.get("source")
    if (
        not isinstance(evidence_source, Mapping)
        or set(evidence_source) != _SOURCE_FIELDS
        or dict(evidence_source) != source
    ):
        raise ValueError("evidence source matcher ikke de aktuelle CLI-kilder")
    entries = value.get("entries")
    if not isinstance(entries, list):
        raise ValueError("evidence entries skal være en liste")

    seen: set[str] = set()
    validated: list[dict] = []
    for item in entries:
        if not isinstance(item, Mapping) or set(item) != _EVIDENCE_ENTRY_FIELDS:
            raise ValueError("evidenspost har uautoriserede eller manglende felter")
        entry = copy.deepcopy(dict(item))
        key = _nonempty(entry.get("baseline_record_key"), "baseline_record_key")
        if key not in baseline_keys:
            raise ValueError("evidence har ukendt baseline_record_key")
        if key in seen:
            raise ValueError("dublet evidence baseline_record_key")
        seen.add(key)

        candidates = entry.get("candidates")
        if not isinstance(candidates, list):
            raise ValueError("candidates skal være en liste")
        entry["candidates"] = [
            _validate_source_bound_candidate(candidate, calamari_text, raw_text)
            for candidate in candidates
        ]
        entry["conflicts"] = _strict_string_list(entry.get("conflicts"), "conflict")
        entry["source_blockers"] = _strict_string_list(
            entry.get("source_blockers"), "source_blocker"
        )
        rule_id = entry.get("rule_id")
        if rule_id is not None:
            _nonempty(rule_id, "rule_id")

        provenance = entry.get("positive_provenance")
        if provenance is not None:
            provenance_fields = {"kind", "baseline_record_key", "candidate_id"}
            if not isinstance(provenance, Mapping) or set(provenance) != provenance_fields:
                raise ValueError("positive_provenance har uautoriserede eller manglende felter")
            if (
                provenance.get("kind") != "record_key_v2_locator"
                or provenance.get("baseline_record_key") != key
                or len(entry["candidates"]) != 1
                or provenance.get("candidate_id") != entry["candidates"][0]["candidate_id"]
            ):
                raise ValueError("positive_provenance matcher ikke den entydige candidate")
            entry["positive_provenance"] = copy.deepcopy(dict(provenance))
        validated.append(entry)
    if seen != baseline_keys:
        raise ValueError("evidence baseline-dækning fejler")
    return validated


def _validated_evidence_entries(
    value: object,
    source: dict,
    baseline_keys: set[str],
    calamari_text: str,
    raw_text: str,
) -> list[dict]:
    if not isinstance(value, Mapping):
        raise ValueError("evidence skal være en mapping")
    if "source" not in value:
        return _source_less_evidence_entries(value, source, baseline_keys)
    return _source_bound_evidence_entries(
        value, source, baseline_keys, calamari_text, raw_text
    )


def _validate_review_metadata(entry: Mapping) -> None:
    if "baseline_locator" in entry:
        locator = entry["baseline_locator"]
        if not isinstance(locator, Mapping) or set(locator) != {"pages", "local_id"}:
            raise ValueError("baseline_locator har uautoriserede eller manglende felter")
        if locator["pages"] is not None and not isinstance(locator["pages"], str):
            raise ValueError("baseline_locator pages skal være en streng eller null")
        if locator["local_id"] is not None and not isinstance(locator["local_id"], str):
            raise ValueError("baseline_locator local_id skal være en streng eller null")
    if "review_note" in entry and not isinstance(entry["review_note"], str):
        raise ValueError("review_note skal være en streng")


def _source_less_template_keys(
    value: Mapping, source: dict, baseline_keys: set[str]
) -> set[str]:
    allowed_root = {"schema_version", "baseline_sha256", "entries"}
    if set(value) - allowed_root or value.get("schema_version", 1) != 1:
        raise ValueError("review source kræves for beslutnings- eller auditdata")
    if value.get("baseline_sha256") != source["baseline_sha256"]:
        raise ValueError("review baseline hash matcher ikke")
    entries = value.get("entries")
    if not isinstance(entries, list):
        raise ValueError("source-løs review template entries skal være en liste")
    allowed_entry = {
        "baseline_record_key", "review_status", "baseline_locator", "review_note",
    }
    seen: set[str] = set()
    for item in entries:
        if (
            not isinstance(item, Mapping)
            or set(item) - allowed_entry
            or item.get("review_status") != "unreviewed"
        ):
            raise ValueError("review source kræves for beslutnings- eller auditdata")
        key = _nonempty(item.get("baseline_record_key"), "baseline_record_key")
        if key not in baseline_keys:
            raise ValueError("review har ukendt baseline_record_key")
        if key in seen:
            raise ValueError("dublet review baseline_record_key")
        seen.add(key)
        _validate_review_metadata(item)
    if seen != baseline_keys:
        raise ValueError("source-løs review template baseline-dækning fejler")
    return seen


def _validate_audit_results(value: object, baseline_keys: set[str]) -> list[dict]:
    if not isinstance(value, list):
        raise ValueError("review audit_results skal være en liste")
    statuses = {"audit_confirmed", "audit_failed", "audit_undecidable"}
    seen: set[str] = set()
    results: list[dict] = []
    for raw_result in value:
        if not isinstance(raw_result, Mapping):
            raise ValueError("audit result skal være en mapping")
        result = copy.deepcopy(dict(raw_result))
        key = _nonempty(result.get("baseline_record_key"), "audit baseline_record_key")
        status = result.get("audit_status")
        if key not in baseline_keys:
            raise ValueError("audit result har ukendt baseline_record_key")
        if key in seen:
            raise ValueError("dublet audit baseline_record_key")
        if status not in statuses:
            raise ValueError("audit result har ukendt audit_status")
        _nonempty(result.get("rule_id"), "audit rule_id")
        required = {"baseline_record_key", "audit_status", "rule_id"}
        if status == "audit_confirmed":
            if set(result) != required:
                raise ValueError("audit result har ugyldig schema")
        else:
            if set(result) != required | {"reason"}:
                raise ValueError("audit result har ugyldig schema")
            _nonempty(result["reason"], "audit reason")
        seen.add(key)
        results.append(result)
    return results


def _review_state(
    value: object, source: dict, baseline_keys: set[str]
) -> tuple[set[str], list[dict]]:
    if not isinstance(value, Mapping):
        raise ValueError("review skal være en mapping")
    review_source = value.get("source")
    if review_source is None:
        _source_less_template_keys(value, source, baseline_keys)
        return set(), []
    if review_source != source:
        raise ValueError("review source hashes matcher ikke")
    if value.get("schema_version") != 1:
        raise ValueError("review schema_version skal være 1")
    baseline_sha256 = value.get("baseline_sha256")
    if baseline_sha256 is not None and baseline_sha256 != source["baseline_sha256"]:
        raise ValueError("review baseline hash matcher ikke")

    entries = value.get("entries", [])
    if "exported_at" in value or (
        isinstance(entries, list)
        and any(isinstance(item, Mapping) and "outcome" in item for item in entries)
    ):
        context = validate_choice_export(
            copy.deepcopy(dict(value)), source, baseline_keys, include_context=True
        )
        return set(context["final_legacy_entries"]), []

    allowed_root = {
        "schema_version", "source", "baseline_sha256", "entries", "decisions",
        "audit_results",
    }
    if set(value) - allowed_root:
        raise ValueError("review har uautoriserede felter")

    legacy_entries: dict[str, dict] = {}
    seen: set[str] = set()
    for container, status_field in ((value.get("entries", []), "review_status"),
                                    (value.get("decisions", []), "status")):
        if not isinstance(container, list):
            raise ValueError("review entries/decisions skal være lister")
        for item in container:
            if not isinstance(item, Mapping):
                raise ValueError("review decision skal være en mapping")
            key = _nonempty(item.get("baseline_record_key"), "baseline_record_key")
            if key not in baseline_keys:
                raise ValueError("review har ukendt baseline_record_key")
            if key in seen:
                raise ValueError("dublet review baseline_record_key")
            seen.add(key)
            entry = copy.deepcopy(dict(item))
            if status_field == "status":
                if "review_status" in entry:
                    raise ValueError("review decision har både status og review_status")
                entry["review_status"] = entry.pop("status", None)
            if set(entry) - LEGACY_REVIEW_ALLOWED_FIELDS:
                raise ValueError("review decision har uautoriserede felter")
            _validate_review_metadata(entry)
            errors = legacy_review_entry_errors(entry)
            if errors:
                raise ValueError(errors[0])
            legacy_entries[key] = entry
    target_errors = duplicate_target_errors(
        legacy_entries, status_field="review_status"
    )
    if target_errors:
        raise ValueError(next(iter(target_errors.values())))
    audit_results = _validate_audit_results(value.get("audit_results", []), baseline_keys)
    completed = {
        key for key, entry in legacy_entries.items()
        if entry["review_status"] in _COMPLETED_STATUSES
    }
    return completed, audit_results


def _write_json_exclusive(path: Path, value: object) -> None:
    created = False
    try:
        with path.open("x", encoding="utf-8") as handle:
            created = True
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
    except BaseException:
        if created:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Forbered privat 1939-undtagelseskø")
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--calamari", type=Path, required=True)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--profile-version", required=True)
    parser.add_argument("--queue-out", type=Path, required=True)
    parser.add_argument("--report-out", type=Path, required=True)
    args = parser.parse_args(argv)

    if args.profile_version != _PINNED_PROFILE_VERSION:
        raise ValueError(f"profile_version skal være {_PINNED_PROFILE_VERSION}")
    if args.queue_out == args.report_out:
        raise ValueError("queue-out og report-out skal være forskellige")
    for output in (args.queue_out, args.report_out):
        if output.exists():
            raise FileExistsError(output)

    baseline_bytes = args.baseline.read_bytes()
    evidence_bytes = args.evidence.read_bytes()
    review_bytes = args.review.read_bytes()
    calamari_bytes = args.calamari.read_bytes()
    raw_bytes = args.raw.read_bytes()
    pdf_bytes = args.pdf.read_bytes()

    baseline_value = _strict_json_bytes(baseline_bytes, "baseline")
    _, baseline_keys = _baseline_index(baseline_value)
    source = {
        "edition": "1939",
        "baseline_sha256": _hash_bytes(baseline_bytes),
        "calamari_sha256": _hash_bytes(calamari_bytes),
        "raw_ocr_sha256": _hash_bytes(raw_bytes),
        "pdf_sha256": _hash_bytes(pdf_bytes),
        "profile_version": args.profile_version,
    }
    evidence_value = _strict_json_bytes(evidence_bytes, "evidence")
    evidence_entries = _validated_evidence_entries(
        evidence_value,
        source,
        baseline_keys,
        _decoded_source_text(calamari_bytes, "Calamari"),
        _decoded_source_text(raw_bytes, "rå OCR"),
    )
    manifest = classify_review_entries(source, baseline_keys, evidence_entries)
    audit_keys = sample_auto_resolved(manifest)
    completed_keys, audit_results = _review_state(
        _strict_json_bytes(review_bytes, "review"), source, baseline_keys
    )

    created: list[Path] = []
    try:
        _write_json_exclusive(args.queue_out, manifest)
        created.append(args.queue_out)
        written_manifest = json.loads(args.queue_out.read_bytes())
        report = build_queue_report(
            written_manifest,
            audit_keys=audit_keys,
            completed_keys=completed_keys,
            audit_results=audit_results,
        )
        _write_json_exclusive(args.report_out, report)
        created.append(args.report_out)
    except BaseException:
        for path in reversed(created):
            path.unlink(missing_ok=True)
        raise

    print(json.dumps({
        "queue_out": str(args.queue_out),
        "report_out": str(args.report_out),
        "baseline_total": report["baseline_total"],
        "publication_gate": report["publication_gate"],
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
