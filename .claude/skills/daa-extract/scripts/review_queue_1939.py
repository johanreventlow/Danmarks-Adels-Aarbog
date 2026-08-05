"""Pure, fail-closed classification for 1939 evidence review entries."""

from __future__ import annotations

import copy
import re
from collections.abc import Mapping

from coverage_1939 import validate_coverage


QUEUE_CLASSES = {"auto_resolved", "human_required", "source_blocked"}
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_PROVENANCE_KINDS = {"record_key_v2_locator"}
_HUMAN_REASONS_DA = {
    "no_candidate": "Ingen kandidat med komplet kildebro.",
    "multiple_candidates": "Flere kandidater kræver menneskelig vurdering.",
    "missing_positive_provenance": "Mangler gyldig positiv proveniens.",
    "evidence_conflict": "Evidensen indeholder en konflikt.",
    "missing_rule_id": "Mangler stabil regelidentitet for den automatiske afgørelse.",
    "candidate_collision": "Kandidaten er knyttet til flere baseline-poster.",
    "calamari_span_overlap": "Calamari-ankeret overlapper en anden automatisk kandidat.",
}


def classify_review_entries(
    source: dict, baseline_keys: set[str], evidence_entries: list[dict]
) -> dict:
    """Classify every baseline record exactly once without changing its inputs."""
    _validate_source_manifest(source)
    by_key = _complete_evidence_index(baseline_keys, evidence_entries)
    provisional = [_classify_one(key, by_key[key], source) for key in sorted(baseline_keys)]
    _demote_candidate_collisions(provisional)
    _demote_span_overlaps(provisional)
    if {entry["baseline_record_key"] for entry in provisional} != baseline_keys:
        raise ValueError("queue baseline-dækning fejler")
    return {
        "schema_version": 1,
        "source": copy.deepcopy(source),
        "entries": provisional,
    }


def _validate_source_manifest(source: object) -> None:
    if not isinstance(source, Mapping):
        raise ValueError("source skal være en mapping")
    if source.get("edition") != "1939":
        raise ValueError("source edition skal være 1939")
    for field in (
        "baseline_sha256",
        "calamari_sha256",
        "raw_ocr_sha256",
        "pdf_sha256",
    ):
        digest = source.get(field)
        if not isinstance(digest, str) or not _SHA256_RE.fullmatch(digest):
            raise ValueError(f"{field} skal være SHA-256 med små bogstaver")
    _nonempty_string(source.get("profile_version"), "profile_version")


def _complete_evidence_index(
    baseline_keys: object, evidence_entries: object
) -> dict[str, dict]:
    if not isinstance(baseline_keys, set) or any(
        not isinstance(key, str) or not key for key in baseline_keys
    ):
        raise ValueError("forventede baseline-nøgler skal være ikke-tomme strenge")
    if not isinstance(evidence_entries, list):
        raise ValueError("evidensposter skal være en liste")

    by_key: dict[str, dict] = {}
    for value in evidence_entries:
        if not isinstance(value, Mapping):
            raise ValueError("evidenspost skal være en mapping")
        entry = copy.deepcopy(dict(value))
        key = _nonempty_string(entry.get("baseline_record_key"), "baseline_record_key")
        if key in by_key:
            raise ValueError("dublet baseline_record_key")
        if key not in baseline_keys:
            raise ValueError("ukendt baseline_record_key")
        _validate_evidence_shape(entry)
        by_key[key] = entry

    if set(by_key) != baseline_keys:
        raise ValueError("queue baseline-dækning fejler")
    return by_key


def _validate_evidence_shape(entry: dict) -> None:
    for field in ("candidates", "conflicts", "source_blockers"):
        value = entry.get(field, [])
        if not isinstance(value, list):
            raise ValueError(f"{field} skal være en liste")
    for blocker in entry.get("source_blockers", []):
        _nonempty_string(blocker, "source_blocker")


def _classify_one(key: str, evidence: dict, source: dict) -> dict:
    if evidence.get("source_blockers"):
        return _blocked(key, evidence["source_blockers"][0])
    candidates = evidence.get("candidates") or []
    if len(candidates) != 1:
        return _human(key, "no_candidate" if not candidates else "multiple_candidates")
    candidate = candidates[0]
    candidate_id = candidate.get("candidate_id") if isinstance(candidate, Mapping) else None
    provenance = evidence.get("positive_provenance")
    if not _valid_positive_provenance(provenance, key, candidate_id):
        return _human(key, "missing_positive_provenance")
    if evidence.get("conflicts"):
        return _human(key, "evidence_conflict")
    if not _nonempty_optional_string(evidence.get("rule_id")):
        return _human(key, "missing_rule_id")
    _validate_one_candidate_with_existing_contract(key, candidate, source)
    return _automatic(key, candidate, evidence["rule_id"])


def _valid_positive_provenance(
    provenance: object, baseline_record_key: str, candidate_id: object
) -> bool:
    return (
        isinstance(provenance, Mapping)
        and provenance.get("kind") in _PROVENANCE_KINDS
        and provenance.get("baseline_record_key") == baseline_record_key
        and isinstance(candidate_id, str)
        and provenance.get("candidate_id") == candidate_id
    )


def _validate_one_candidate_with_existing_contract(
    key: str, candidate: object, source: dict
) -> None:
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
            ],
        },
        expected_baseline_keys={key},
    )


def _automatic(key: str, candidate: object, rule_id: str) -> dict:
    candidate_copy = copy.deepcopy(candidate)
    return {
        "baseline_record_key": key,
        "queue_class": "auto_resolved",
        "reason_code": "complete_unique_anchored_candidate",
        "reason_da": "Én komplet, entydig og konfliktfri kildebro.",
        "candidate": candidate_copy,
        "rule_id": rule_id,
        "postklasse": candidate_copy["postklasse"],
    }


def _human(key: str, reason_code: str) -> dict:
    return {
        "baseline_record_key": key,
        "queue_class": "human_required",
        "reason_code": reason_code,
        "reason_da": _HUMAN_REASONS_DA[reason_code],
    }


def _blocked(key: str, reason_code: str) -> dict:
    return {
        "baseline_record_key": key,
        "queue_class": "source_blocked",
        "reason_code": reason_code,
        "reason_da": f"Kildemateriale er blokeret: {reason_code}.",
    }


def _demote_candidate_collisions(entries: list[dict]) -> None:
    by_candidate_id: dict[str, list[dict]] = {}
    for entry in entries:
        if entry["queue_class"] != "auto_resolved":
            continue
        by_candidate_id.setdefault(entry["candidate"]["candidate_id"], []).append(entry)
    for colliding_entries in by_candidate_id.values():
        if len(colliding_entries) > 1:
            _demote(colliding_entries, "candidate_collision")


def _demote_span_overlaps(entries: list[dict]) -> None:
    automatic_entries = [
        entry for entry in entries if entry["queue_class"] == "auto_resolved"
    ]
    overlapping: list[dict] = []
    for index, left in enumerate(automatic_entries):
        left_span = left["candidate"]["calamari_span"]
        for right in automatic_entries[index + 1 :]:
            right_span = right["candidate"]["calamari_span"]
            if (
                left_span["char_from"] < right_span["char_to"]
                and right_span["char_from"] < left_span["char_to"]
            ):
                overlapping.extend((left, right))
    if overlapping:
        _demote(overlapping, "calamari_span_overlap")


def _demote(entries: list[dict], reason_code: str) -> None:
    for entry in entries:
        key = entry["baseline_record_key"]
        entry.clear()
        entry.update(_human(key, reason_code))


def _nonempty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} skal være en ikke-tom streng")
    return value


def _nonempty_optional_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())
