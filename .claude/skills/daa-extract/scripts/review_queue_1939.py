"""Pure, fail-closed classification for 1939 evidence review entries."""

from __future__ import annotations

import copy
from collections import defaultdict
import hashlib
import math
import re
from collections.abc import Mapping

from coverage_1939 import (
    PresentationCandidateIdError,
    is_schema_version_one,
    validate_coverage,
)
from dual_rendition_evidence_1939 import RULE_ID, deterministic_candidate_id


QUEUE_CLASSES = {"auto_resolved", "human_required", "source_blocked"}
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_PROVENANCE_KINDS = {"record_key_v2_locator", "dual_rendition_consensus_v1"}
_CONSENSUS_CONFLICT_CODES = {
    "missing_in_calamari",
    "missing_in_raw_ocr",
    "multiple_calamari_occurrences",
    "multiple_raw_occurrences",
    "boundary_disagreement",
    "predecessor_disagreement",
    "successor_disagreement",
    "page_disagreement",
    "post_class_disagreement",
    "occurrence_collision",
    "span_overlap",
    "ambiguous_structure",
    "known_overview_duplicate",
    "missing_exact_baseline_narrative",
    "repeated_exact_baseline_narrative",
    "anchor_outside_occurrence",
    "anchor_occurrence_collision",
    "unknown_narrative_source",
}
_HUMAN_REASONS_DA = {
    "human_approved_evidence": "Menneskegodkendt evidens kræver en menneskelig beslutning.",
    "no_candidate": "Ingen kandidat med komplet kildebro.",
    "multiple_candidates": "Flere kandidater kræver menneskelig vurdering.",
    "missing_positive_provenance": "Mangler gyldig positiv proveniens.",
    "evidence_conflict": "Evidensen indeholder en konflikt.",
    "missing_rule_id": "Mangler stabil regelidentitet for den automatiske afgørelse.",
    "candidate_collision": "Kandidaten er knyttet til flere baseline-poster.",
    "calamari_span_overlap": "Calamari-ankeret overlapper en anden kandidat.",
    "raw_ocr_span_overlap": "Rå-OCR-ankeret overlapper en anden kandidat.",
    "missing_in_calamari": "Posten kan ikke afgrænses i Calamari-kilden.",
    "missing_in_raw_ocr": "Posten kan ikke afgrænses i rå OCR.",
    "multiple_calamari_occurrences": "Flere Calamari-forekomster er mulige.",
    "multiple_raw_occurrences": "Flere rå-OCR-forekomster er mulige.",
    "boundary_disagreement": "OCR-kilderne er uenige om postens grænse.",
    "predecessor_disagreement": "OCR-kilderne er uenige om den foregående post.",
    "successor_disagreement": "OCR-kilderne er uenige om den følgende post.",
    "page_disagreement": "OCR-kilderne er uenige om PDF-siden.",
    "post_class_disagreement": "OCR-kilderne er uenige om posttypen.",
    "occurrence_collision": "En kildeforekomst er krævet af flere poster.",
    "span_overlap": "Kildeintervallet overlapper en anden post.",
    "ambiguous_structure": "Kildestrukturen er ikke entydig.",
    "known_overview_duplicate": "Kendt oversigtsdublet kræver menneskelig vurdering.",
    "missing_exact_baseline_narrative": "Det lagrede narrativ findes ikke præcist én gang i den angivne OCR-kilde; derfor findes ingen positiv kildebro.",
    "repeated_exact_baseline_narrative": "Det lagrede narrativ forekommer flere gange i den angivne OCR-kilde; derfor findes ingen entydig positiv kildebro.",
    "anchor_outside_occurrence": "Det lagrede narrativ ligger ikke inden for præcis én kildepost; derfor findes ingen positiv kildebro.",
    "anchor_occurrence_collision": "Den samme kildepost kræves af flere baseline-poster; derfor findes ingen positiv kildebro.",
    "unknown_narrative_source": "Postens narrativesource er ukendt; derfor findes ingen positiv kildebro.",
}
_SOURCE_BLOCKER_DIAGNOSTICS_DA = {
    "raw_ocr_missing": (
        "Rå OCR-kilden mangler; posten kan ikke sammenholdes sikkert.",
        "Calamari: tilgængelig · rå OCR: mangler.",
    ),
    "calamari_missing": (
        "Calamari-kilden mangler; posten kan ikke sammenholdes sikkert.",
        "Calamari: mangler · rå OCR: tilgængelig.",
    ),
    "pdf_missing": (
        "PDF-kilden mangler; sidereferencen kan ikke kontrolleres.",
        "Calamari: ukendt · rå OCR: ukendt. Kræver menneskelig vurdering.",
    ),
}


def classify_review_entries(
    source: dict, baseline_keys: set[str], evidence_entries: list[dict]
) -> dict:
    """Classify every baseline record exactly once without changing its inputs."""
    _validate_source_manifest(source)
    by_key = _complete_evidence_index(baseline_keys, evidence_entries)
    provisional = [_classify_one(key, by_key[key], source) for key in sorted(baseline_keys)]
    _demote_global_claim_collisions(provisional, by_key)
    if {entry["baseline_record_key"] for entry in provisional} != baseline_keys:
        raise ValueError("queue baseline-dækning fejler")
    return {
        "schema_version": 1,
        "source": copy.deepcopy(source),
        "entries": provisional,
    }


def sample_auto_resolved(
    manifest: dict, *, rate: float = 0.05, minimum_per_stratum: int = 2
) -> list[str]:
    """Select a deterministic, stratified audit sample without mutating evidence."""
    _validate_rate(rate, minimum_per_stratum)
    if not isinstance(manifest, Mapping):
        raise ValueError("manifest skal være en mapping")
    if not is_schema_version_one(manifest.get("schema_version")):
        raise ValueError("manifest schema_version skal være 1")
    source = manifest.get("source")
    _validate_source_manifest(source)
    entries = manifest.get("entries")
    if not isinstance(entries, list):
        raise ValueError("manifest entries skal være en liste")

    seed = _source_seed(source)
    strata = defaultdict(list)
    seen_keys: set[str] = set()
    for entry in entries:
        if not isinstance(entry, Mapping):
            raise ValueError("manifest entry skal være en mapping")
        key = _nonempty_string(entry.get("baseline_record_key"), "baseline_record_key")
        if key in seen_keys:
            raise ValueError("dublet baseline_record_key")
        seen_keys.add(key)
        queue_class = entry.get("queue_class")
        if queue_class not in QUEUE_CLASSES:
            raise ValueError("ukendt queue_class")
        if queue_class == "auto_resolved":
            stratum = _validate_auto_resolved_entry(entry, source)
            strata[stratum].append(entry)

    selected = []
    for stratum, stratum_entries in sorted(strata.items()):
        count = min(
            len(stratum_entries),
            max(minimum_per_stratum, math.ceil(len(stratum_entries) * rate)),
        )
        ordered = sorted(
            stratum_entries,
            key=lambda entry: hashlib.sha256(
                f"{seed}|{stratum}|{entry['baseline_record_key']}".encode("utf-8")
            ).hexdigest(),
        )
        selected.extend(entry["baseline_record_key"] for entry in ordered[:count])
    return sorted(selected)


def _validate_rate(rate: float, minimum_per_stratum: int) -> None:
    if (
        not isinstance(rate, (int, float))
        or isinstance(rate, bool)
        or not math.isfinite(rate)
        or not 0 <= rate <= 1
    ):
        raise ValueError("rate skal være mellem 0 og 1")
    if (
        not isinstance(minimum_per_stratum, int)
        or isinstance(minimum_per_stratum, bool)
        or minimum_per_stratum <= 0
    ):
        raise ValueError("minimum_per_stratum skal være positiv")


def _source_seed(source: Mapping) -> str:
    return source["baseline_sha256"]


def _validate_auto_resolved_entry(entry: Mapping, source: Mapping) -> tuple[str, str]:
    _nonempty_string(entry.get("baseline_record_key"), "baseline_record_key")
    if entry.get("queue_class") != "auto_resolved":
        raise ValueError("queue_class skal være auto_resolved")
    if entry.get("reason_code") != "complete_unique_anchored_candidate":
        raise ValueError("auto_resolved reason_code er ugyldig")
    _nonempty_string(entry.get("reason_da"), "reason_da")
    rule_id = _nonempty_string(entry.get("rule_id"), "rule_id")
    postklasse = _nonempty_string(entry.get("postklasse"), "postklasse")
    candidate = entry.get("candidate")
    if not isinstance(candidate, dict):
        raise ValueError("auto_resolved entry kræver candidate som dict")
    _validate_one_candidate_with_existing_contract(
        entry["baseline_record_key"], candidate, source
    )
    if candidate["postklasse"] != postklasse:
        raise ValueError("candidate postklasse stemmer ikke med auto_resolved entry")
    return rule_id, postklasse


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
    boundary_evidence = entry.get("boundary_evidence")
    if boundary_evidence is not None and not isinstance(boundary_evidence, Mapping):
        raise ValueError("boundary_evidence skal være en mapping eller null")


def _classify_one(key: str, evidence: dict, source: dict) -> dict:
    if evidence.get("source_blockers"):
        return _blocked(key, evidence["source_blockers"][0])
    if _is_human_evidence(evidence):
        return _human(key, "human_approved_evidence")
    candidates = evidence.get("candidates") or []
    conflict_reason = _allowlisted_consensus_conflict(evidence.get("conflicts"))
    if len(candidates) != 1:
        if not candidates and conflict_reason is not None:
            return _human(
                key, conflict_reason, evidence.get("boundary_evidence"),
                evidence.get("anchor_rendition"),
            )
        if evidence.get("conflicts"):
            return _human(key, "evidence_conflict")
        return _human(key, "no_candidate" if not candidates else "multiple_candidates")
    candidate = candidates[0]
    if not _valid_dual_consensus_contract(key, evidence, candidate, source):
        return _human(key, "evidence_conflict")
    candidate_id = candidate.get("candidate_id") if isinstance(candidate, Mapping) else None
    provenance = evidence.get("positive_provenance")
    if not _valid_positive_provenance(provenance, key, candidate_id):
        return _human(key, "missing_positive_provenance")
    if evidence.get("conflicts"):
        return _human(
            key, conflict_reason or "evidence_conflict", evidence.get("boundary_evidence"),
            evidence.get("anchor_rendition"),
        )
    if not _nonempty_optional_string(evidence.get("rule_id")):
        return _human(key, "missing_rule_id")
    try:
        _validate_one_candidate_with_existing_contract(key, candidate, source)
    except PresentationCandidateIdError:
        return _human(key, "missing_positive_provenance")
    return _automatic(key, candidate, evidence["rule_id"])


def _is_human_evidence(evidence: Mapping) -> bool:
    candidates = evidence.get("candidates")
    if isinstance(candidates, list) and any(
        isinstance(candidate, Mapping) and "approval" in candidate
        for candidate in candidates
    ):
        return True
    provenance = evidence.get("positive_provenance")
    provenance_kind = (
        provenance.get("kind") if isinstance(provenance, Mapping) else None
    )
    return any(
        isinstance(marker, str) and marker.startswith("human_")
        for marker in (evidence.get("rule_id"), provenance_kind)
    )


def _valid_dual_consensus_contract(
    key: str, evidence: dict, candidate: object, source: dict,
) -> bool:
    if not isinstance(candidate, Mapping):
        return True
    provenance = evidence.get("positive_provenance")
    bridge = candidate.get("raw_structure_bridge")
    markers = (
        evidence.get("rule_id"),
        provenance.get("kind") if isinstance(provenance, Mapping) else None,
        bridge.get("kind") if isinstance(bridge, Mapping) else None,
    )
    candidate_id = candidate.get("candidate_id")
    is_dual = RULE_ID in markers or (
        isinstance(candidate_id, str) and candidate_id.startswith("1939:dual-v1:")
    )
    if not is_dual:
        return True
    if markers != (RULE_ID, RULE_ID, RULE_ID):
        return False
    try:
        expected_id = deterministic_candidate_id(
            key, candidate["calamari_span"], {
                "char_from": bridge["raw_char_from"],
                "char_to": bridge["raw_char_to"],
            }, source,
        )
    except (KeyError, TypeError):
        return False
    return candidate_id == expected_id


def _allowlisted_consensus_conflict(conflicts: object) -> str | None:
    if (
        isinstance(conflicts, list)
        and len(conflicts) == 1
        and isinstance(conflicts[0], str)
        and conflicts[0] in _CONSENSUS_CONFLICT_CODES
    ):
        return conflicts[0]
    return None


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


def _human_reason_da(reason_code: str, anchor_rendition: object) -> str:
    source_da = {"calamari": "Calamari", "raw_ocr": "rå OCR"}.get(anchor_rendition)
    if reason_code == "missing_exact_baseline_narrative" and source_da:
        return f"Det lagrede narrativ findes ikke præcist én gang i {source_da}; derfor findes ingen positiv kildebro."
    if reason_code == "repeated_exact_baseline_narrative" and source_da:
        return f"Det lagrede narrativ forekommer flere gange i {source_da}; derfor findes ingen entydig positiv kildebro."
    if reason_code == "anchor_outside_occurrence" and source_da:
        return f"Det lagrede narrativ ligger ikke inden for præcis én {source_da}-post; derfor findes ingen positiv kildebro."
    if reason_code == "anchor_occurrence_collision" and source_da:
        return f"Den samme {source_da}-post kræves af flere baseline-poster; derfor findes ingen positiv kildebro."
    return _HUMAN_REASONS_DA[reason_code]


def _human(
    key: str, reason_code: str, boundary_evidence: object = None,
    anchor_rendition: object = None,
) -> dict:
    result = {
        "baseline_record_key": key,
        "queue_class": "human_required",
        "reason_code": reason_code,
        "reason_da": _human_reason_da(reason_code, anchor_rendition),
    }
    if boundary_evidence is not None:
        result["boundary_evidence"] = copy.deepcopy(boundary_evidence)
    if anchor_rendition in {"calamari", "raw_ocr"}:
        result["anchor_rendition"] = anchor_rendition
    return result


def _blocked(key: str, reason_code: str) -> dict:
    reason_da, boundary_context = _SOURCE_BLOCKER_DIAGNOSTICS_DA.get(
        reason_code,
        (
            f"Kildemateriale er blokeret: {reason_code}.",
            "Calamari: ukendt · rå OCR: ukendt. Kræver menneskelig vurdering.",
        ),
    )
    return {
        "baseline_record_key": key,
        "queue_class": "source_blocked",
        "reason_code": reason_code,
        "reason_da": reason_da,
        "boundary_context": boundary_context,
    }


def _demote_global_claim_collisions(
    entries: list[dict], evidence_by_key: dict[str, dict]
) -> None:
    """Demote global duplicate/overlap claims, including already-human evidence."""
    claims = list(_all_candidate_claims(evidence_by_key))
    reasons_by_key: dict[str, str] = {}
    _add_collision_reason(
        reasons_by_key, _duplicate_candidate_id_keys(claims), "candidate_collision"
    )
    _add_collision_reason(
        reasons_by_key,
        _overlapping_span_keys(claims, "calamari_span", "char_from", "char_to"),
        "calamari_span_overlap",
    )
    _add_collision_reason(
        reasons_by_key,
        _overlapping_span_keys(
            claims, "raw_structure_bridge", "raw_char_from", "raw_char_to"
        ),
        "raw_ocr_span_overlap",
    )

    entries_by_key = {entry["baseline_record_key"]: entry for entry in entries}
    for key, reason_code in reasons_by_key.items():
        entry = entries_by_key[key]
        if entry["queue_class"] == "source_blocked":
            continue
        entry.clear()
        entry.update(_human(key, reason_code))


def _all_candidate_claims(evidence_by_key: dict[str, dict]):
    for key, evidence in evidence_by_key.items():
        for candidate in evidence.get("candidates", []):
            if isinstance(candidate, Mapping):
                yield key, candidate


def _duplicate_candidate_id_keys(claims: list[tuple[str, Mapping]]) -> set[str]:
    owners_by_candidate_id: dict[str, set[str]] = {}
    for key, candidate in claims:
        candidate_id = candidate.get("candidate_id")
        if _nonempty_optional_string(candidate_id):
            owners_by_candidate_id.setdefault(candidate_id, set()).add(key)
    return {
        key
        for owners in owners_by_candidate_id.values()
        if len(owners) > 1
        for key in owners
    }


def _overlapping_span_keys(
    claims: list[tuple[str, Mapping]],
    container_field: str,
    from_field: str,
    to_field: str,
) -> set[str]:
    spans: list[tuple[str, int, int]] = []
    for key, candidate in claims:
        span = candidate.get(container_field)
        if not isinstance(span, Mapping):
            continue
        char_from = span.get(from_field)
        char_to = span.get(to_field)
        if not _valid_half_open_span(char_from, char_to):
            continue
        spans.append((key, char_from, char_to))

    colliding_keys: set[str] = set()
    for index, (left_key, left_from, left_to) in enumerate(spans):
        for right_key, right_from, right_to in spans[index + 1 :]:
            if left_key == right_key:
                continue
            if left_from < right_to and right_from < left_to:
                colliding_keys.update((left_key, right_key))
    return colliding_keys


def _add_collision_reason(
    reasons_by_key: dict[str, str], keys: set[str], reason_code: str
) -> None:
    for key in keys:
        reasons_by_key.setdefault(key, reason_code)


def _valid_half_open_span(char_from: object, char_to: object) -> bool:
    return (
        isinstance(char_from, int)
        and not isinstance(char_from, bool)
        and isinstance(char_to, int)
        and not isinstance(char_to, bool)
        and char_from >= 0
        and char_from < char_to
    )


def _nonempty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} skal være en ikke-tom streng")
    return value


def _nonempty_optional_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())
