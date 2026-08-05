"""Validate provisional 1939 browser choices and convert them fail-closed."""

from __future__ import annotations

import copy
from collections.abc import Mapping
from datetime import datetime
import re

from coverage_1939 import (
    LEGACY_REVIEW_ALLOWED_FIELDS,
    duplicate_target_errors,
    legacy_review_entry_errors,
    validate_coverage,
)


_OUTCOMES = {
    "human_selected_candidate",
    "possible_duplicate",
    "no_candidate_fits",
    "undecidable",
}
_FINAL_LEGACY_STATUSES = {"accepteret", "eksplicit_dublet", "menneskeark"}
_PRESERVED_METADATA_FIELDS = {"review_status", "baseline_locator", "review_note"}
_SOURCE_FIELDS = {
    "edition",
    "baseline_sha256",
    "calamari_sha256",
    "raw_ocr_sha256",
    "pdf_sha256",
    "profile_version",
}
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_TIMESTAMP_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"
)
_VALIDATION_SOURCE = {
    "edition": "1939",
    "calamari_sha256": "a" * 64,
    "raw_ocr_sha256": "b" * 64,
    "pdf_sha256": "c" * 64,
}


def _mapping(value: object, label: str) -> Mapping:
    if not isinstance(value, Mapping):
        raise ValueError(f"{label} skal være en mapping")
    return value


def _nonempty(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} skal være en ikke-tom streng")
    return value


def _timestamp(value: object, label: str) -> str:
    text = _nonempty(value, label)
    if not _TIMESTAMP_RE.fullmatch(text):
        raise ValueError(f"{label} er ugyldigt")
    try:
        parsed = datetime.fromisoformat(text[:-1] + "+00:00" if text.endswith("Z") else text)
    except ValueError as error:
        raise ValueError(f"{label} er ugyldigt") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError(f"{label} skal have tidszone")
    return text


def _validate_source(value: object) -> dict:
    source = _mapping(value, "source")
    if set(source) != _SOURCE_FIELDS or source.get("edition") != "1939":
        raise ValueError("choice export source/version matcher ikke")
    for field in ("baseline_sha256", "calamari_sha256", "raw_ocr_sha256", "pdf_sha256"):
        if not isinstance(source.get(field), str) or not _SHA256_RE.fullmatch(source[field]):
            raise ValueError("choice export source/version matcher ikke")
    _nonempty(source.get("profile_version"), "profile_version")
    return copy.deepcopy(dict(source))


def _unique_entries(value: object, expected_keys: set[str]) -> list[Mapping]:
    if not isinstance(value, list):
        raise ValueError("choice export entries skal være en liste")
    seen: set[str] = set()
    entries: list[Mapping] = []
    for raw_entry in value:
        entry = _mapping(raw_entry, "choice entry")
        key = _nonempty(entry.get("baseline_record_key"), "baseline_record_key")
        if key in seen:
            raise ValueError("dublet baseline_record_key")
        if key not in expected_keys:
            raise ValueError("ukendt baseline_record_key")
        seen.add(key)
        entries.append(entry)
    return entries


def _validate_preserved_metadata(entry: Mapping) -> None:
    if "review_status" in entry and entry["review_status"] not in {
        "unreviewed", *_FINAL_LEGACY_STATUSES,
    }:
        raise ValueError("ukendt review_status")
    if "baseline_locator" in entry:
        locator = _mapping(entry["baseline_locator"], "baseline_locator")
        if set(locator) != {"pages", "local_id"}:
            raise ValueError("baseline_locator har uautoriserede eller manglende felter")
        if locator["pages"] is not None and not isinstance(locator["pages"], str):
            raise ValueError("baseline_locator pages skal være en streng eller null")
        if locator["local_id"] is not None and not isinstance(locator["local_id"], str):
            raise ValueError("baseline_locator local_id skal være en streng eller null")
    if "review_note" in entry and not isinstance(entry["review_note"], str):
        raise ValueError("review_note skal være en streng")


def _validate_choice(value: object, expected_keys: set[str]) -> dict:
    choice = _mapping(value, "choice")
    key = _nonempty(choice.get("baseline_record_key"), "baseline_record_key")
    if key not in expected_keys:
        raise ValueError("ukendt baseline_record_key")
    outcome = choice.get("outcome")
    if outcome not in _OUTCOMES:
        raise ValueError("ukendt outcome")
    status = choice.get("review_status")
    if status in _FINAL_LEGACY_STATUSES:
        raise ValueError("provisional outcome må ikke overskrive endelig legacy-status")
    if status not in (None, "unreviewed"):
        raise ValueError("ukendt review_status")
    allowed = {
        "baseline_record_key", "outcome", "decided_at", *_PRESERVED_METADATA_FIELDS,
    }
    required = {"baseline_record_key", "outcome"}
    if outcome == "human_selected_candidate":
        allowed.add("candidate_id")
        required.add("candidate_id")
    elif outcome == "possible_duplicate":
        allowed.add("duplicate_of_baseline_record_key")
        required.add("duplicate_of_baseline_record_key")
    else:
        allowed.add("reason")
        required.add("reason")
    unknown = set(choice) - allowed
    if unknown:
        raise ValueError("choice har uautoriserede felter")
    if required - set(choice):
        field = sorted(required - set(choice))[0]
        raise ValueError(f"choice kræver {field}")
    if "decided_at" in choice:
        _timestamp(choice["decided_at"], "beslutningstidspunkt")
    _validate_preserved_metadata(choice)
    if outcome == "human_selected_candidate":
        _nonempty(choice["candidate_id"], "candidate_id")
    elif outcome == "possible_duplicate":
        target = _nonempty(
            choice["duplicate_of_baseline_record_key"],
            "duplicate_of_baseline_record_key",
        )
        if target == key:
            raise ValueError("dublet må ikke pege på sig selv")
    else:
        _nonempty(choice["reason"], "reason")
    return copy.deepcopy(dict(choice))


def _validate_legacy_export_entry(entry: Mapping) -> dict:
    unknown = set(entry) - LEGACY_REVIEW_ALLOWED_FIELDS
    if unknown:
        raise ValueError("choice har uautoriserede felter")
    _validate_preserved_metadata(entry)
    errors = legacy_review_entry_errors(entry)
    if errors:
        raise ValueError(errors[0])
    return copy.deepcopy(dict(entry))


def validate_choice_export(
    value: dict, expected_source: dict, expected_keys: set[str]
) -> dict[str, dict]:
    """Validate one exact browser export without mutating it."""
    root = _mapping(value, "choice export")
    expected = _validate_source(expected_source)
    if root.get("schema_version") != 1 or root.get("source") != expected:
        raise ValueError("choice export source/version matcher ikke")
    allowed_root = {"schema_version", "source", "baseline_sha256", "exported_at", "entries"}
    if set(root) - allowed_root:
        raise ValueError("choice export har uautoriserede felter")
    if "baseline_sha256" in root and root["baseline_sha256"] != expected["baseline_sha256"]:
        raise ValueError("choice export source/version matcher ikke")
    _timestamp(root.get("exported_at"), "eksporttidspunkt")
    if not isinstance(expected_keys, set) or any(
        not isinstance(key, str) or not key for key in expected_keys
    ):
        raise ValueError("forventede baseline-nøgler skal være ikke-tomme strenge")
    entries = _unique_entries(root.get("entries"), expected_keys)
    actual_keys = {entry["baseline_record_key"] for entry in entries}
    if actual_keys != expected_keys:
        raise ValueError("choice export baseline-dækning fejler")

    choices: dict[str, dict] = {}
    legacy_statuses: dict[str, dict] = {}
    for entry in entries:
        key = entry["baseline_record_key"]
        if "outcome" in entry:
            validated = _validate_choice(entry, expected_keys)
            choices[key] = validated
            legacy_statuses[key] = {
                "review_status": validated.get("review_status", "unreviewed")
            }
        else:
            validated = _validate_legacy_export_entry(entry)
            legacy_statuses[key] = validated
    target_errors = duplicate_target_errors(
        legacy_statuses, status_field="review_status"
    )
    if target_errors:
        raise ValueError(next(iter(target_errors.values())))
    return choices


def _candidate_is_valid(key: str, candidate: object) -> bool:
    try:
        validate_coverage(
            {
                "schema_version": 1,
                "source": copy.deepcopy(_VALIDATION_SOURCE),
                "entries": [{
                    "baseline_record_key": key,
                    "status": "accepteret",
                    "candidate": copy.deepcopy(candidate),
                }],
            },
            expected_baseline_keys={key},
        )
    except ValueError:
        return False
    return True


def _classification_index(value: object) -> dict[str, dict]:
    classifications = _mapping(value, "classifications")
    result: dict[str, dict] = {}
    for map_key, raw_entry in classifications.items():
        key = _nonempty(map_key, "classification key")
        entry = _mapping(raw_entry, "classification")
        if entry.get("baseline_record_key") != key:
            raise ValueError("classification har forkert baseline_record_key")
        queue_class = entry.get("queue_class")
        if queue_class not in {"auto_resolved", "human_required", "source_blocked"}:
            raise ValueError("ukendt queue_class")
        copied = copy.deepcopy(dict(entry))
        if queue_class == "auto_resolved":
            if not _candidate_is_valid(key, copied.get("candidate")):
                raise ValueError("automatisk kandidat er ugyldig")
            _nonempty(copied.get("rule_id"), "rule_id")
            if copied["candidate"].get("postklasse") != copied.get("postklasse"):
                raise ValueError("automatisk kandidat har forkert postklasse")
        result[key] = copied
    return result


def _anchored_index(value: object) -> dict[str, object]:
    """Index addressable wrappers without validating unrelated candidates."""
    anchored = _mapping(value, "anchored_candidates")
    result: dict[str, object] = {}
    for map_id, raw_wrapper in anchored.items():
        if isinstance(map_id, str) and map_id:
            result[map_id] = copy.deepcopy(raw_wrapper)
    return result


def _selected_candidate(
    anchored: Mapping[str, object], key: str, candidate_id: str
) -> dict | None:
    """Return one exact, owner-matched candidate; malformed selections stay local."""
    wrapper = anchored.get(candidate_id)
    if not isinstance(wrapper, Mapping) or wrapper.get("baseline_record_key") != key:
        return None
    candidate = wrapper.get("candidate")
    if (
        not isinstance(candidate, Mapping)
        or candidate.get("candidate_id") != candidate_id
        or not _candidate_is_valid(key, candidate)
    ):
        return None
    return copy.deepcopy(dict(candidate))


def _span(candidate: Mapping, container: str, start: str, end: str) -> tuple[int, int]:
    value = candidate[container]
    return value[start], value[end]


def _claims_conflict(left: Mapping, right: Mapping) -> bool:
    if left["candidate_id"] == right["candidate_id"]:
        return True
    for container, start, end in (
        ("calamari_span", "char_from", "char_to"),
        ("raw_structure_bridge", "raw_char_from", "raw_char_to"),
    ):
        left_from, left_to = _span(left, container, start, end)
        right_from, right_to = _span(right, container, start, end)
        if left_from < right_to and right_from < left_to:
            return True
    return False


def _manual_collision_keys(
    automatic_candidates: dict[str, dict], proposed: dict[str, dict]
) -> set[str]:
    claims = [
        (key, candidate, False) for key, candidate in automatic_candidates.items()
    ] + [
        (key, candidate, True) for key, candidate in proposed.items()
    ]
    collisions: set[str] = set()
    for index, (left_key, left_candidate, left_manual) in enumerate(claims):
        for right_key, right_candidate, right_manual in claims[index + 1:]:
            if left_key == right_key or not _claims_conflict(left_candidate, right_candidate):
                continue
            if not left_manual and not right_manual:
                raise ValueError("automatiske kandidater er ikke globalt injektive")
            if left_manual:
                collisions.add(left_key)
            if right_manual:
                collisions.add(right_key)
    return collisions


def _audit_result(choice: Mapping, classification: Mapping) -> dict:
    key = choice["baseline_record_key"]
    rule_id = classification["rule_id"]
    automatic_id = classification["candidate"]["candidate_id"]
    if choice["outcome"] == "human_selected_candidate" and choice["candidate_id"] == automatic_id:
        return {
            "baseline_record_key": key,
            "audit_status": "audit_confirmed",
            "rule_id": rule_id,
        }
    if choice["outcome"] in {"no_candidate_fits", "undecidable"}:
        reason = choice["reason"]
    elif choice["outcome"] == "human_selected_candidate":
        reason = f"selected_different_candidate:{choice['candidate_id']}"
    else:
        reason = f"possible_duplicate:{choice['duplicate_of_baseline_record_key']}"
    return {
        "baseline_record_key": key,
        "audit_status": "audit_failed",
        "rule_id": rule_id,
        "reason": reason,
    }


def convert_review_choices(
    choices: dict[str, dict],
    anchored_candidates: dict[str, dict],
    classifications: dict[str, dict],
    audit_keys: set[str],
) -> dict:
    """Convert provisional choices, never inferring or replacing automatic evidence."""
    indexed_classifications = _classification_index(classifications)
    classification_keys = set(indexed_classifications)
    if not isinstance(audit_keys, set) or any(not isinstance(key, str) for key in audit_keys):
        raise ValueError("audit_keys skal være et sæt af strenge")
    if not audit_keys <= classification_keys:
        raise ValueError("audit har ukendt baseline_record_key")
    if any(indexed_classifications[key]["queue_class"] != "auto_resolved" for key in audit_keys):
        raise ValueError("audit kræver auto_resolved entry")

    raw_choices = _mapping(choices, "choices")
    validated_choices: dict[str, dict] = {}
    for map_key, raw_choice in raw_choices.items():
        key = _nonempty(map_key, "choice key")
        choice = _validate_choice(raw_choice, classification_keys)
        if choice["baseline_record_key"] != key:
            raise ValueError("choice har forkert baseline_record_key")
        classification = indexed_classifications[key]
        if classification["queue_class"] == "auto_resolved" and key not in audit_keys:
            raise ValueError("automatisk post uden audit må ikke have choice")
        validated_choices[key] = choice

    anchored = _anchored_index(anchored_candidates)
    automatic_candidates = {
        key: entry["candidate"]
        for key, entry in indexed_classifications.items()
        if entry["queue_class"] == "auto_resolved"
    }
    _manual_collision_keys(automatic_candidates, {})

    proposed: dict[str, dict] = {}
    for key, one_choice in validated_choices.items():
        if key in audit_keys or one_choice["outcome"] != "human_selected_candidate":
            continue
        selected = _selected_candidate(anchored, key, one_choice["candidate_id"])
        if selected is not None:
            proposed[key] = selected
    collision_keys = _manual_collision_keys(automatic_candidates, proposed)

    decisions: list[dict] = []
    audit_results: list[dict] = []
    for key, one_choice in validated_choices.items():
        if key in audit_keys:
            continue
        outcome = one_choice["outcome"]
        if outcome == "human_selected_candidate":
            candidate_id = one_choice["candidate_id"]
            candidate = proposed.get(key)
            if candidate is None:
                decisions.append({
                    "baseline_record_key": key,
                    "status": "menneskeark",
                    "reason": f"human_selected_candidate_requires_exact_anchor:{candidate_id}",
                })
            elif key in collision_keys:
                decisions.append({
                    "baseline_record_key": key,
                    "status": "menneskeark",
                    "reason": f"human_selected_candidate_not_globally_injective:{candidate_id}",
                })
            else:
                decisions.append({
                    "baseline_record_key": key,
                    "status": "accepteret",
                    "candidate_id": candidate_id,
                })
        elif outcome == "possible_duplicate":
            decisions.append({
                "baseline_record_key": key,
                "status": "eksplicit_dublet",
                "duplicate_of_baseline_record_key": one_choice["duplicate_of_baseline_record_key"],
            })
        else:
            decisions.append({
                "baseline_record_key": key,
                "status": "menneskeark",
                "reason": f"{outcome}:{one_choice['reason']}",
            })

    statuses = {
        key: {"status": "accepteret" if entry["queue_class"] == "auto_resolved" else "menneskeark"}
        for key, entry in indexed_classifications.items()
    }
    for decision in decisions:
        statuses[decision["baseline_record_key"]] = decision
    target_errors = duplicate_target_errors(statuses)
    if target_errors:
        raise ValueError(next(iter(target_errors.values())))

    for key, one_choice in validated_choices.items():
        if key not in audit_keys:
            continue
        if one_choice["outcome"] == "possible_duplicate":
            audit_statuses = copy.deepcopy(statuses)
            audit_statuses[key] = {
                "status": "eksplicit_dublet",
                "duplicate_of_baseline_record_key": one_choice[
                    "duplicate_of_baseline_record_key"
                ],
            }
            audit_target_errors = duplicate_target_errors(audit_statuses)
            if key in audit_target_errors:
                raise ValueError(audit_target_errors[key])
        audit_results.append(_audit_result(one_choice, indexed_classifications[key]))

    return {"decisions": decisions, "audit_results": audit_results}
