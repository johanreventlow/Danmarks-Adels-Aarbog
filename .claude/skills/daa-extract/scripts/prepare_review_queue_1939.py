"""Build a lossless private view model for the 1939 exception review queue."""

from __future__ import annotations

import argparse
import copy
from collections import Counter
from collections.abc import Mapping
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

from coverage_1939 import (
    LEGACY_REVIEW_ACCEPTED_FIELDS,
    POSTKLASSER,
    duplicate_target_errors,
    is_schema_version_one,
    legacy_review_entry_errors,
    validate_accepted_candidate_id,
    validate_coverage,
)
from dual_rendition_evidence_1939 import RULE_ID, deterministic_candidate_id
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
_OPTIONAL_EVIDENCE_ENTRY_FIELDS = _EVIDENCE_ENTRY_FIELDS | {"boundary_evidence"}
_BOUNDARY_EXCERPT_LIMIT = 160
_CANDIDATE_FIELDS = {
    "candidate_id", "postklasse", "calamari_span", "pdf_pages",
    "raw_structure_bridge",
}
_PROVENANCE_KINDS = {"record_key_v2_locator", "dual_rendition_consensus_v1"}


@dataclass(frozen=True)
class _ValidatedReviewState:
    """Validated partition data, never a publication-authority capability."""

    source: dict
    manifest: dict | None
    audit_keys: tuple[str, ...]
    completed_keys: frozenset[str]
    audit_results: tuple[dict, ...]

    def __iter__(self):
        """Preserve the private helper's historical two-value unpacking API."""
        yield set(self.completed_keys)
        yield [copy.deepcopy(result) for result in self.audit_results]


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
    if (
        not isinstance(manifest, Mapping)
        or not is_schema_version_one(manifest.get("schema_version"))
    ):
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


_BOUNDARY_CONTEXT_DA = {
    "boundary_disagreement": "Calamari: postgrænsen afviger · rå OCR: postgrænsen afviger.",
    "predecessor_disagreement": "Calamari: foregående post afviger · rå OCR: foregående post afviger.",
    "successor_disagreement": "Calamari: følgende post afviger · rå OCR: følgende post afviger.",
    "missing_in_calamari": "Calamari: ingen sikker postgrænse · rå OCR: postgrænse fundet.",
    "missing_in_raw_ocr": "Calamari: postgrænse fundet · rå OCR: ingen sikker postgrænse.",
    "multiple_calamari_occurrences": "Calamari: flere mulige postgrænser · rå OCR: én sammenligning mulig.",
    "multiple_raw_occurrences": "Calamari: én sammenligning mulig · rå OCR: flere mulige postgrænser.",
}


def _boundary_context(classification: Mapping) -> str:
    """Provide a brief human diagnostic without exposing source hashes by default."""
    source_blocked = classification.get("boundary_context")
    if isinstance(source_blocked, str) and source_blocked.strip():
        return source_blocked
    boundary_evidence = classification.get("boundary_evidence")
    if isinstance(boundary_evidence, Mapping):
        direction = boundary_evidence.get("direction")
        raw_ocr = boundary_evidence.get("raw_ocr")
        calamari = boundary_evidence.get("calamari")
        direction_da = {
            "predecessor": "foregående post",
            "successor": "følgende post",
        }.get(direction)
        if direction_da is not None and (
            isinstance(calamari, Mapping) or isinstance(raw_ocr, Mapping)
        ):
            def source_detail(excerpt: object) -> str:
                text = excerpt.get("text") if isinstance(excerpt, Mapping) else None
                return f'{direction_da} “{text}”' if isinstance(text, str) else f"{direction_da} mangler"

            return f"Calamari: {source_detail(calamari)} · rå OCR: {source_detail(raw_ocr)}."
    reason_code = classification.get("reason_code")
    if reason_code in _BOUNDARY_CONTEXT_DA:
        return _BOUNDARY_CONTEXT_DA[reason_code]
    return "Calamari: ukendt · rå OCR: ukendt. Kræver menneskelig vurdering."


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
        "boundary_context": _boundary_context(classification),
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
        "audit": [record["record_key"] for record in view_records if record["is_audit"]],
        "completed": [record["record_key"] for record in view_records if record["is_completed"]],
    }
    return {
        "schema_version": 1,
        "source": source,
        "default_view": "required",
        "summary": {
            "required": len(views["required"]),
            "automatic": sum(record["queue_class"] == "auto_resolved" for record in view_records),
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
    if (
        not isinstance(manifest, Mapping)
        or not is_schema_version_one(manifest.get("schema_version"))
    ):
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
    audit_keys: list[str] | None = None,
    completed_keys: set[str] | None = None,
    audit_results: list[dict] | None = None,
    review_state: _ValidatedReviewState | None = None,
) -> dict:
    """Build a diagnostic queue report whose public gate is always NO-GO."""
    if review_state is not None:
        if any(value is not None for value in (audit_keys, completed_keys, audit_results)):
            raise ValueError("review_state må ikke blandes med løse review-felter")
        if type(review_state) is not _ValidatedReviewState:
            raise ValueError("review_state skal have intern state-type")
        if review_state.manifest != manifest:
            raise ValueError("review_state manifest matcher ikke queue manifest")
        if review_state.source != manifest.get("source"):
            raise ValueError("review_state source matcher ikke queue manifest")
        if (
            type(review_state.audit_keys) is not tuple
            or type(review_state.completed_keys) is not frozenset
            or type(review_state.audit_results) is not tuple
        ):
            raise ValueError("review_state har ugyldig intern schema")
        audit_keys = list(review_state.audit_keys)
        completed_keys = set(review_state.completed_keys)
        audit_results = [copy.deepcopy(result) for result in review_state.audit_results]
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

    if review_state is not None:
        validated_results = _validate_audit_results(audit_results, set(by_key))
        if validated_results != audit_results:
            raise ValueError("review_state audit_results er ikke kanoniske")
        if completed_keys & set(result_by_key):
            raise ValueError("review_state beslutnings- og auditnøgler overlapper")
        if any(by_key[key]["queue_class"] == "auto_resolved" for key in completed_keys):
            raise ValueError("review_state har auto_resolved completed key")
        expected_state_audit_keys = sample_auto_resolved(copy.deepcopy(manifest))
        if audit_keys != expected_state_audit_keys:
            raise ValueError("review_state audit sample matcher ikke manifest")
        for key, result in result_by_key.items():
            if (
                by_key[key]["queue_class"] != "auto_resolved"
                or result["rule_id"] != by_key[key].get("rule_id")
            ):
                raise ValueError("review_state audit matcher ikke auto_resolved entry")

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
        "publication_gate": "NO-GO",
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


def _validate_dual_consensus_contract(entry: dict, source: dict) -> None:
    """Check only the cross-layer facts consumed by the dual-consensus rule."""
    candidate = entry["candidates"][0]
    provenance = entry["positive_provenance"]
    bridge = candidate["raw_structure_bridge"]
    markers = (entry["rule_id"], provenance["kind"], bridge["kind"])
    candidate_id = candidate["candidate_id"]
    is_dual = RULE_ID in markers or candidate_id.startswith("1939:dual-v1:")
    if not is_dual:
        return
    if markers != (RULE_ID, RULE_ID, RULE_ID):
        raise ValueError("dual consensus rule/kind matcher ikke")
    expected_id = deterministic_candidate_id(
        entry["baseline_record_key"], candidate["calamari_span"], {
            "char_from": bridge["raw_char_from"],
            "char_to": bridge["raw_char_to"],
        }, source,
    )
    if candidate_id != expected_id:
        raise ValueError("dual consensus candidate_id matcher ikke source-bound evidens")


def _source_less_evidence_entries(
    value: Mapping, source: dict, baseline_keys: set[str]
) -> list[dict]:
    allowed_root = {"schema_version", "baseline_sha256", "entries"}
    if not is_schema_version_one(value.get("schema_version")):
        raise ValueError("source-løs evidence schema_version skal være 1")
    if set(value) != allowed_root:
        raise ValueError("source-løs evidence skal være en strikt unreviewed template")
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
    if not is_schema_version_one(value.get("schema_version")):
        raise ValueError("evidence schema_version skal være 1")
    if set(value) != {"schema_version", "source", "entries"}:
        raise ValueError("evidence root har uautoriserede eller manglende felter")
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
        if (
            not isinstance(item, Mapping)
            or not _EVIDENCE_ENTRY_FIELDS <= set(item) <= _OPTIONAL_EVIDENCE_ENTRY_FIELDS
        ):
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
        _validate_boundary_evidence(
            entry.get("boundary_evidence"), calamari_text, raw_text,
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
                provenance.get("kind") not in _PROVENANCE_KINDS
                or provenance.get("baseline_record_key") != key
                or len(entry["candidates"]) != 1
                or provenance.get("candidate_id") != entry["candidates"][0]["candidate_id"]
            ):
                raise ValueError("positive_provenance matcher ikke den entydige candidate")
            entry["positive_provenance"] = copy.deepcopy(dict(provenance))
        if len(entry["candidates"]) == 1 and entry["positive_provenance"] is not None:
            _validate_dual_consensus_contract(entry, source)
        validated.append(entry)
    if seen != baseline_keys:
        raise ValueError("evidence baseline-dækning fejler")
    return validated


def _validate_boundary_evidence(
    value: object, calamari_text: str, raw_text: str,
) -> None:
    if value is None:
        return
    if not isinstance(value, Mapping) or set(value) != {"direction", "calamari", "raw_ocr"}:
        raise ValueError("boundary_evidence har ugyldigt schema")
    if value.get("direction") not in {"predecessor", "successor"}:
        raise ValueError("boundary_evidence har ugyldig retning")
    for label, source_text in (("calamari", calamari_text), ("raw_ocr", raw_text)):
        excerpt = value.get(label)
        if excerpt is None:
            continue
        if not isinstance(excerpt, Mapping) or set(excerpt) != {"char_from", "char_to", "text"}:
            raise ValueError("boundary_evidence har ugyldigt uddrag")
        start, end, text = excerpt.get("char_from"), excerpt.get("char_to"), excerpt.get("text")
        if (
            type(start) is not int or type(end) is not int or not isinstance(text, str)
            or start < 0 or end <= start or end - start > _BOUNDARY_EXCERPT_LIMIT
            or end > len(source_text) or source_text[start:end] != text
        ):
            raise ValueError("boundary_evidence matcher ikke den bundne kilde")


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
    if not is_schema_version_one(value.get("schema_version")):
        raise ValueError("review schema_version skal være 1")
    if set(value) != allowed_root:
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


def _evidence_index(value: list[dict] | None) -> dict[str, dict] | None:
    if value is None:
        return None
    result: dict[str, dict] = {}
    for raw_entry in value:
        entry = copy.deepcopy(dict(raw_entry))
        key = _nonempty(entry.get("baseline_record_key"), "baseline_record_key")
        if key in result:
            raise ValueError("dublet evidence baseline_record_key")
        result[key] = entry
    return result


def _normalize_review_decision(
    value: object,
    status_field: str,
    *,
    baseline_record: Mapping | None = None,
) -> dict:
    if not isinstance(value, Mapping):
        raise ValueError("review decision skal være en mapping")
    entry = copy.deepcopy(dict(value))
    if status_field == "status":
        if "review_status" in entry:
            raise ValueError("review decision har både status og review_status")
        status = entry.get("status")
        required_by_status = {
            "accepteret": {"baseline_record_key", "status", "candidate_id"},
            "menneskeark": {"baseline_record_key", "status", "reason"},
            "eksplicit_dublet": {
                "baseline_record_key", "status", "duplicate_of_baseline_record_key",
            },
        }
        if status not in required_by_status:
            raise ValueError("Task 5-beslutning har ukendt status")
        if set(entry) != required_by_status[status]:
            raise ValueError("Task 5-beslutning har ugyldige felter")
        entry["review_status"] = entry.pop("status")
        if status == "accepteret":
            validate_accepted_candidate_id(entry.get("candidate_id"))
        else:
            errors = legacy_review_entry_errors(entry)
            if errors:
                raise ValueError(errors[0])
        return entry
    if status_field != "review_status":
        raise ValueError("ukendt review status-felt")

    status = entry.get("review_status")
    common = {"baseline_record_key", "review_status"}
    optional_metadata = {"baseline_locator", "review_note"}
    required_by_status = {
        "unreviewed": common,
        "accepteret": common | LEGACY_REVIEW_ACCEPTED_FIELDS,
        "menneskeark": common | {"reason"},
        "eksplicit_dublet": common | {"duplicate_of_baseline_record_key"},
    }
    if status not in required_by_status:
        raise ValueError("ukendt review_status")
    required = required_by_status[status]
    if not required <= set(entry) or set(entry) - required - optional_metadata:
        raise ValueError("legacy review decision har ugyldige felter")
    _validate_review_metadata(entry)
    if "baseline_locator" in entry:
        if baseline_record is None:
            raise ValueError("baseline_locator kræver aktuel baseline")
        expected_locator = {
            "pages": baseline_record.get("sider"),
            "local_id": baseline_record.get("_v2_lokal_id"),
        }
        if entry["baseline_locator"] != expected_locator:
            raise ValueError("baseline_locator matcher ikke aktuel baseline")
    errors = legacy_review_entry_errors(entry)
    if errors:
        raise ValueError(errors[0])
    return entry


def _joined_accepted_candidate(
    entry: Mapping,
    evidence_by_key: dict[str, dict] | None,
    source: dict,
    calamari_text: str | None = None,
    raw_text: str | None = None,
) -> dict:
    candidate_id = validate_accepted_candidate_id(entry.get("candidate_id"))
    if evidence_by_key is None:
        raise ValueError("accepteret beslutning kræver source-bound evidence")
    key = entry["baseline_record_key"]
    evidence = evidence_by_key.get(key)
    if evidence is None:
        raise ValueError("accepteret beslutning mangler evidence candidate for ejer")
    if evidence.get("conflicts") or evidence.get("source_blockers"):
        raise ValueError("accepteret evidence har konflikt eller source blocker")
    matches = [
        (index, candidate)
        for index, candidate in enumerate(evidence.get("candidates", []))
        if isinstance(candidate, Mapping) and candidate.get("candidate_id") == candidate_id
    ]
    if len(matches) != 1:
        raise ValueError("accepteret beslutning kræver præcis én evidence candidate for ejer")
    provenance = evidence.get("positive_provenance")
    if (
        not isinstance(provenance, Mapping)
        or set(provenance) != {"kind", "baseline_record_key", "candidate_id"}
        or provenance.get("kind") not in _PROVENANCE_KINDS
        or provenance.get("baseline_record_key") != key
        or provenance.get("candidate_id") != candidate_id
    ):
        raise ValueError("accepteret evidence mangler matchende positiv proveniens")
    candidate_index, matched_candidate = matches[0]
    candidate = copy.deepcopy(dict(matched_candidate))
    validate_coverage(
        {
            "schema_version": 1,
            "source": copy.deepcopy(source),
            "entries": [{
                "baseline_record_key": key,
                "status": "accepteret",
                "candidate": copy.deepcopy(candidate),
            }],
        },
        expected_baseline_keys={key},
    )

    if LEGACY_REVIEW_ACCEPTED_FIELDS <= set(entry):
        if calamari_text is None or raw_text is None:
            raise ValueError("legacy accepted anchors kræver aktuelle OCR-kilder")
        span = candidate["calamari_span"]
        bridge = candidate["raw_structure_bridge"]
        expected = {
            "candidate_id": candidate["candidate_id"],
            "post_index": candidate_index,
            "calamari_span": span,
            "calamari_verbatim_text": calamari_text[
                span["char_from"]:span["char_to"]
            ],
            "pdf_pages": candidate["pdf_pages"],
            "kind": bridge["kind"],
            "raw_char_from": bridge["raw_char_from"],
            "raw_char_to": bridge["raw_char_to"],
            "raw_verbatim_text": raw_text[
                bridge["raw_char_from"]:bridge["raw_char_to"]
            ],
            "raw_excerpt_sha256": bridge["raw_excerpt_sha256"],
        }
        for field, expected_value in expected.items():
            if entry[field] != expected_value:
                raise ValueError(
                    f"legacy accepted {field} matcher ikke evidence-derived værdi"
                )
    return candidate


def _claims_overlap(left: Mapping, right: Mapping) -> bool:
    if left["candidate_id"] == right["candidate_id"]:
        return True
    for container, start, end in (
        ("calamari_span", "char_from", "char_to"),
        ("raw_structure_bridge", "raw_char_from", "raw_char_to"),
    ):
        left_span = left[container]
        right_span = right[container]
        if left_span[start] < right_span[end] and right_span[start] < left_span[end]:
            return True
    return False


def _validate_effective_state(
    decisions: dict[str, dict],
    accepted: dict[str, dict],
    manifest: Mapping | None,
    source: dict,
) -> None:
    statuses: dict[str, dict] = {}
    effective_candidates: dict[str, dict] = {}
    if manifest is not None:
        _, queue_by_key = _queue_entries(manifest)
        for key, classification in queue_by_key.items():
            if classification["queue_class"] == "auto_resolved":
                statuses[key] = {"status": "accepteret"}
                effective_candidates[key] = copy.deepcopy(classification["candidate"])
            else:
                statuses[key] = {"status": "menneskeark"}
    for key, decision in decisions.items():
        status = decision["review_status"]
        statuses[key] = {"status": status}
        if status == "eksplicit_dublet":
            statuses[key]["duplicate_of_baseline_record_key"] = decision[
                "duplicate_of_baseline_record_key"
            ]
        if status == "accepteret":
            effective_candidates[key] = copy.deepcopy(accepted[key])
        else:
            effective_candidates.pop(key, None)
    target_errors = duplicate_target_errors(statuses)
    if target_errors:
        raise ValueError(next(iter(target_errors.values())))
    if effective_candidates:
        validate_coverage(
            {
                "schema_version": 1,
                "source": copy.deepcopy(source),
                "entries": [
                    {
                        "baseline_record_key": key,
                        "status": "accepteret",
                        "candidate": copy.deepcopy(candidate),
                    }
                    for key, candidate in sorted(effective_candidates.items())
                ],
            },
            expected_baseline_keys=set(effective_candidates),
        )
    claims = sorted(effective_candidates.items())
    for index, (left_key, left) in enumerate(claims):
        for right_key, right in claims[index + 1:]:
            if left_key != right_key and _claims_overlap(left, right):
                raise ValueError("effektiv accepteret evidens er ikke globalt injektiv")


def _review_state(
    value: object,
    source: dict,
    baseline_keys: set[str],
    *,
    evidence_entries: list[dict] | None = None,
    manifest: Mapping | None = None,
    baseline_by_key: Mapping[str, Mapping] | None = None,
    calamari_text: str | None = None,
    raw_text: str | None = None,
) -> _ValidatedReviewState:
    if not isinstance(value, Mapping):
        raise ValueError("review skal være en mapping")
    review_source = value.get("source")
    task5_output = review_source is None and set(value) == {"decisions", "audit_results"}
    if review_source is None and not task5_output:
        _source_less_template_keys(value, source, baseline_keys)
        return _ValidatedReviewState(
            source=copy.deepcopy(source),
            manifest=copy.deepcopy(dict(manifest)) if manifest is not None else None,
            audit_keys=tuple(sample_auto_resolved(dict(manifest))) if manifest else (),
            completed_keys=frozenset(),
            audit_results=(),
        )
    if review_source is not None:
        if review_source != source:
            raise ValueError("review source hashes matcher ikke")
        if not is_schema_version_one(value.get("schema_version")):
            raise ValueError("review schema_version skal være 1")
        baseline_sha256 = value.get("baseline_sha256")
        if baseline_sha256 is not None and baseline_sha256 != source["baseline_sha256"]:
            raise ValueError("review baseline hash matcher ikke")

    entries = value.get("entries", [])
    if review_source is not None and (
        "exported_at" in value
        or (
            isinstance(entries, list)
            and any(isinstance(item, Mapping) and "outcome" in item for item in entries)
        )
    ):
        context = validate_choice_export(
            copy.deepcopy(dict(value)), source, baseline_keys, include_context=True
        )
        containers = [(list(context["final_legacy_entries"].values()), "review_status")]
        audit_value: object = []
    else:
        if not task5_output:
            allowed_root = {
                "schema_version", "source", "baseline_sha256", "entries", "decisions",
                "audit_results",
            }
            if set(value) - allowed_root:
                raise ValueError("review har uautoriserede felter")
        containers = [
            (value.get("entries", []), "review_status"),
            (value.get("decisions", []), "status"),
        ]
        audit_value = value.get("audit_results", [])

    decisions: dict[str, dict] = {}
    accepted: dict[str, dict] = {}
    evidence_by_key = _evidence_index(evidence_entries)
    for container, status_field in containers:
        if not isinstance(container, list):
            raise ValueError("review entries/decisions skal være lister")
        for item in container:
            raw_key = item.get("baseline_record_key") if isinstance(item, Mapping) else None
            baseline_record = (
                baseline_by_key.get(raw_key)
                if baseline_by_key is not None and isinstance(raw_key, str)
                else None
            )
            entry = _normalize_review_decision(
                item, status_field, baseline_record=baseline_record
            )
            key = _nonempty(entry.get("baseline_record_key"), "baseline_record_key")
            if key not in baseline_keys:
                raise ValueError("review har ukendt baseline_record_key")
            if key in decisions:
                raise ValueError("dublet review baseline_record_key")
            decisions[key] = entry
            if entry["review_status"] == "accepteret":
                accepted[key] = _joined_accepted_candidate(
                    entry, evidence_by_key, source, calamari_text, raw_text
                )
    audit_results = _validate_audit_results(audit_value, baseline_keys)
    audit_result_keys = {
        result["baseline_record_key"] for result in audit_results
    }
    decision_keys = set(decisions)

    audit_keys: list[str] = []
    validated_manifest = copy.deepcopy(dict(manifest)) if manifest is not None else None
    if manifest is not None:
        _, queue_by_key = _queue_entries(dict(manifest))
        audit_keys = sample_auto_resolved(dict(manifest))
        audit_key_set = set(audit_keys)
        for key in decision_keys:
            if queue_by_key[key]["queue_class"] == "auto_resolved":
                raise ValueError(
                    "auto_resolved må kun have audit og må ikke have beslutning"
                )
        if decision_keys & audit_result_keys:
            raise ValueError("beslutnings- og auditnøgler skal være disjunkte")
        for result in audit_results:
            key = result["baseline_record_key"]
            queue_entry = queue_by_key[key]
            queue_class = queue_entry["queue_class"]
            if queue_class != "auto_resolved":
                raise ValueError(f"audit må ikke tilhøre {queue_class}")
            if key not in audit_key_set:
                raise ValueError("audit result har ikke-samplet baseline_record_key")
            if result["rule_id"] != queue_entry.get("rule_id"):
                raise ValueError("audit rule_id matcher ikke auto_resolved entry")
    elif audit_results:
        raise ValueError("audit result kræver queue manifest")

    _validate_effective_state(decisions, accepted, manifest, source)
    completed = {
        key
        for key, decision in decisions.items()
        if decision["review_status"] in _COMPLETED_STATUSES
    }
    return _ValidatedReviewState(
        source=copy.deepcopy(source),
        manifest=validated_manifest,
        audit_keys=tuple(audit_keys),
        completed_keys=frozenset(completed),
        audit_results=tuple(copy.deepcopy(audit_results)),
    )


def _require_exact_json_types(value: object, label: str) -> None:
    value_type = type(value)
    if value_type is dict:
        for key, item in value.items():
            if type(key) is not str:
                raise ValueError(f"{label} kræver eksakte JSON-typer")
            _require_exact_json_types(item, label)
        return
    if value_type is list:
        for item in value:
            _require_exact_json_types(item, label)
        return
    if value_type not in (str, int, float, bool, type(None)):
        raise ValueError(f"{label} kræver eksakte JSON-typer")


def _validate_publication_boundary_types(
    manifest: object,
    profile_version: object,
    byte_values: tuple[tuple[str, object], ...],
) -> None:
    if type(manifest) is not dict:
        raise ValueError("queue manifest kræver eksakte JSON-typer")
    if type(profile_version) is not str:
        raise ValueError("profile_version skal være eksakt str")
    for label, value in byte_values:
        if type(value) is not bytes:
            raise ValueError(f"{label} skal være eksakt bytes")
    _require_exact_json_types(manifest, "queue manifest")
    if not is_schema_version_one(manifest.get("schema_version")):
        raise ValueError("queue manifest schema_version skal være 1")


def _build_publication_queue_report(
    manifest: dict,
    *,
    baseline_bytes: bytes,
    evidence_bytes: bytes,
    review_bytes: bytes,
    calamari_bytes: bytes,
    raw_bytes: bytes,
    pdf_bytes: bytes,
    profile_version: str,
) -> dict:
    """Rederive publication eligibility from the original CLI input bytes."""
    _validate_publication_boundary_types(
        manifest,
        profile_version,
        (
            ("baseline_bytes", baseline_bytes),
            ("evidence_bytes", evidence_bytes),
            ("review_bytes", review_bytes),
            ("calamari_bytes", calamari_bytes),
            ("raw_bytes", raw_bytes),
            ("pdf_bytes", pdf_bytes),
        ),
    )
    if profile_version != _PINNED_PROFILE_VERSION:
        raise ValueError(f"profile_version skal være {_PINNED_PROFILE_VERSION}")
    baseline_value = _strict_json_bytes(baseline_bytes, "baseline")
    baseline_records, baseline_keys = _baseline_index(baseline_value)
    baseline_by_key = {record["record_key"]: record for record in baseline_records}
    source = {
        "edition": "1939",
        "baseline_sha256": _hash_bytes(baseline_bytes),
        "calamari_sha256": _hash_bytes(calamari_bytes),
        "raw_ocr_sha256": _hash_bytes(raw_bytes),
        "pdf_sha256": _hash_bytes(pdf_bytes),
        "profile_version": profile_version,
    }
    evidence_value = _strict_json_bytes(evidence_bytes, "evidence")
    calamari_text = _decoded_source_text(calamari_bytes, "Calamari")
    raw_text = _decoded_source_text(raw_bytes, "rå OCR")
    evidence_entries = _validated_evidence_entries(
        evidence_value,
        source,
        baseline_keys,
        calamari_text,
        raw_text,
    )
    rederived_manifest = classify_review_entries(
        source, baseline_keys, evidence_entries
    )
    if rederived_manifest != manifest:
        raise ValueError("queue manifest matcher ikke rederiverede CLI-input")
    review_state = _review_state(
        _strict_json_bytes(review_bytes, "review"),
        source,
        baseline_keys,
        evidence_entries=(
            evidence_entries
            if isinstance(evidence_value, Mapping) and "source" in evidence_value
            else None
        ),
        manifest=rederived_manifest,
        baseline_by_key=baseline_by_key,
        calamari_text=calamari_text,
        raw_text=raw_text,
    )
    report = build_queue_report(rederived_manifest, review_state=review_state)

    entries, by_key = _queue_entries(rederived_manifest)
    audit_results = {
        result["baseline_record_key"]: result
        for result in review_state.audit_results
    }
    every_audit_confirmed = (
        len(audit_results) == len(review_state.audit_keys)
        and all(
            audit_results[key]["audit_status"] == "audit_confirmed"
            for key in review_state.audit_keys
        )
    )
    human_keys = {
        key for key, entry in by_key.items()
        if entry["queue_class"] == "human_required"
    }
    publication_ready = all((
        len(entries) == 546,
        every_audit_confirmed,
        human_keys <= review_state.completed_keys,
        not any(
            entry["queue_class"] == "source_blocked" for entry in entries
        ),
    ))
    report["publication_gate"] = "GO" if publication_ready else "NO-GO"
    return report


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
    baseline_records, baseline_keys = _baseline_index(baseline_value)
    baseline_by_key = {record["record_key"]: record for record in baseline_records}
    source = {
        "edition": "1939",
        "baseline_sha256": _hash_bytes(baseline_bytes),
        "calamari_sha256": _hash_bytes(calamari_bytes),
        "raw_ocr_sha256": _hash_bytes(raw_bytes),
        "pdf_sha256": _hash_bytes(pdf_bytes),
        "profile_version": args.profile_version,
    }
    evidence_value = _strict_json_bytes(evidence_bytes, "evidence")
    calamari_text = _decoded_source_text(calamari_bytes, "Calamari")
    raw_text = _decoded_source_text(raw_bytes, "rå OCR")
    evidence_entries = _validated_evidence_entries(
        evidence_value,
        source,
        baseline_keys,
        calamari_text,
        raw_text,
    )
    manifest = classify_review_entries(source, baseline_keys, evidence_entries)
    review_state = _review_state(
        _strict_json_bytes(review_bytes, "review"),
        source,
        baseline_keys,
        evidence_entries=(
            evidence_entries
            if isinstance(evidence_value, Mapping) and "source" in evidence_value
            else None
        ),
        manifest=manifest,
        baseline_by_key=baseline_by_key,
        calamari_text=calamari_text,
        raw_text=raw_text,
    )
    if review_state.manifest is None:
        raise ValueError("review_state mangler queue manifest")

    created: list[Path] = []
    try:
        _write_json_exclusive(args.queue_out, review_state.manifest)
        created.append(args.queue_out)
        written_manifest = json.loads(args.queue_out.read_bytes())
        report = _build_publication_queue_report(
            written_manifest,
            baseline_bytes=baseline_bytes,
            evidence_bytes=evidence_bytes,
            review_bytes=review_bytes,
            calamari_bytes=calamari_bytes,
            raw_bytes=raw_bytes,
            pdf_bytes=pdf_bytes,
            profile_version=args.profile_version,
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
