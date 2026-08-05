"""Build a lossless private view model for the 1939 exception review queue."""

from __future__ import annotations

import copy
from collections.abc import Mapping

from review_queue_1939 import QUEUE_CLASSES, sample_auto_resolved


_PRESENTATION_FIELDS = (
    "candidate_id", "lokal_id", "pdf_pages", "calamari_pages", "raw_text", "rank_reason",
)
_COMPLETED_STATUSES = {"menneskeark", "eksplicit_dublet", "accepteret"}


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
        by_id[candidate_id]["details"] = copy.deepcopy(dict(decision))
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
        "details": copy.deepcopy(dict(decision)),
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
