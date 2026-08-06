"""Fail-closed validation of private, anchored 1939 coverage."""

from __future__ import annotations

import copy
import hashlib
import re
from collections.abc import Mapping


ALLOWED_STATUSES = {"accepteret", "eksplicit_dublet", "menneskeark"}
POSTKLASSER = {"nummereret", "stamfader", "oversigtspost"}
PRESENTATION_CANDIDATE_PREFIX = "presentation:"
APPROVAL_KINDS = {"human_approved_span_v1"}
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
LEGACY_REVIEW_ACCEPTED_FIELDS = {
    "candidate_id",
    "post_index",
    "calamari_span",
    "calamari_verbatim_text",
    "pdf_pages",
    "kind",
    "raw_char_from",
    "raw_char_to",
    "raw_verbatim_text",
    "raw_excerpt_sha256",
}
LEGACY_REVIEW_DECISION_FIELDS = LEGACY_REVIEW_ACCEPTED_FIELDS | {
    "duplicate_of_baseline_record_key",
    "reason",
}
LEGACY_REVIEW_ALLOWED_FIELDS = {
    "baseline_record_key",
    "review_status",
    "baseline_locator",
    "review_note",
} | LEGACY_REVIEW_DECISION_FIELDS


class PresentationCandidateIdError(ValueError):
    """Raised when display identity is presented as positive accepted evidence."""


def is_schema_version_one(value: object) -> bool:
    """Accept only JSON integer 1, never Python's equal booleans or floats."""
    return type(value) is int and value == 1


def _mapping(value: object, label: str) -> Mapping:
    if not isinstance(value, Mapping):
        raise ValueError(f"{label} skal være en mapping")
    return value


def _nonempty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} skal være en ikke-tom streng")
    return value


def is_presentation_candidate_id(value: object) -> bool:
    """Identify display-only IDs that can never be positive accepted evidence."""
    return isinstance(value, str) and value.startswith(PRESENTATION_CANDIDATE_PREFIX)


def validate_accepted_candidate_id(value: object) -> str:
    """Validate the candidate identity shared by every accepted-evidence path."""
    candidate_id = _nonempty_string(value, "candidate_id")
    if is_presentation_candidate_id(candidate_id):
        raise PresentationCandidateIdError(
            "accepteret candidate_id bruger reserveret presentation:-namespace"
        )
    return candidate_id


def _nonnegative_int(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{label} skal være et ikke-negativt heltal")
    return value


def _validate_source(value: object) -> None:
    source = _mapping(value, "source")
    if source.get("edition") != "1939":
        raise ValueError("source edition skal være 1939")
    for field in ("calamari_sha256", "raw_ocr_sha256", "pdf_sha256"):
        digest = source.get(field)
        if not isinstance(digest, str) or not _SHA256_RE.fullmatch(digest):
            raise ValueError(f"{field} skal være SHA-256 med små bogstaver")


def _validate_candidate(value: object, seen_ids: set[str], seen_spans: set[tuple[int, int]]) -> None:
    candidate = _mapping(value, "candidate")
    candidate_id = validate_accepted_candidate_id(candidate.get("candidate_id"))
    if candidate_id in seen_ids:
        raise ValueError("ikke-injektiv kandidat: candidate_id forekommer flere gange")
    seen_ids.add(candidate_id)

    if candidate.get("postklasse") not in POSTKLASSER:
        raise ValueError("postklasse er ukendt")

    span = _mapping(candidate.get("calamari_span"), "Calamari-span")
    char_from = _nonnegative_int(span.get("char_from"), "Calamari-span char_from")
    char_to = _nonnegative_int(span.get("char_to"), "Calamari-span char_to")
    if char_from >= char_to:
        raise ValueError("Calamari-span skal have char_from < char_to")
    span_key = (char_from, char_to)
    if span_key in seen_spans:
        raise ValueError("ikke-injektiv kandidat: Calamari-span forekommer flere gange")
    seen_spans.add(span_key)

    pages = candidate.get("pdf_pages")
    if not isinstance(pages, list) or not pages:
        raise ValueError("PDF-side skal være en ikke-tom liste")
    if any(not isinstance(page, int) or isinstance(page, bool) or page <= 0 for page in pages):
        raise ValueError("PDF-side skal være et positivt heltal")

    bridge_value = candidate.get("raw_structure_bridge")
    approval_value = candidate.get("approval")
    if bridge_value is None and approval_value is None:
        raise ValueError("accepteret candidate kræver raw_structure_bridge eller approval")
    if bridge_value is not None:
        bridge = _mapping(bridge_value, "rå-bro")
        _nonempty_string(bridge.get("kind"), "rå-bro kind")
        raw_from = _nonnegative_int(bridge.get("raw_char_from"), "rå-bro raw_char_from")
        raw_to = _nonnegative_int(bridge.get("raw_char_to"), "rå-bro raw_char_to")
        if raw_from >= raw_to:
            raise ValueError("rå-bro skal have raw_char_from < raw_char_to")
        raw_digest = bridge.get("raw_excerpt_sha256")
        if not isinstance(raw_digest, str) or not _SHA256_RE.fullmatch(raw_digest):
            raise ValueError("raw_excerpt_sha256 skal være SHA-256 med små bogstaver")
    if approval_value is not None:
        approval = _mapping(approval_value, "approval")
        if set(approval) != {"kind", "calamari_excerpt_sha256"}:
            raise ValueError("approval har uautoriserede eller manglende felter")
        if approval.get("kind") not in APPROVAL_KINDS:
            raise ValueError("approval kind er ukendt")
        digest = approval.get("calamari_excerpt_sha256")
        if not isinstance(digest, str) or not _SHA256_RE.fullmatch(digest):
            raise ValueError("calamari_excerpt_sha256 skal være SHA-256 med små bogstaver")


def duplicate_target_errors(
    entries: Mapping[str, Mapping], *, status_field: str = "status"
) -> dict[str, str]:
    """Return every duplicate target that lacks one accepted, distinct owner."""
    errors: dict[str, str] = {}
    for key, entry in entries.items():
        if entry.get(status_field) != "eksplicit_dublet":
            continue
        target = entry.get("duplicate_of_baseline_record_key")
        if target not in entries:
            errors[key] = "ukendt dubletmål"
        elif target == key:
            errors[key] = "dublet må ikke pege på sig selv"
        elif entries[target].get(status_field) != "accepteret":
            errors[key] = "dubletmål skal være accepteret"
    return errors


def legacy_review_entry_errors(entry: Mapping) -> list[str]:
    """Return authoritative semantic errors for one legacy review-ledger entry."""
    status = entry.get("review_status")
    if status == "unreviewed":
        if LEGACY_REVIEW_DECISION_FIELDS.intersection(entry):
            return ["unreviewed må ikke have beslutningsfelter"]
        return []
    if status not in ALLOWED_STATUSES:
        return ["ukendt review_status"]
    if status == "accepteret":
        missing = [
            f"accepteret kræver {field}"
            for field in sorted(LEGACY_REVIEW_ACCEPTED_FIELDS)
            if field not in entry
        ]
        if missing:
            return missing
        try:
            validate_accepted_candidate_id(entry["candidate_id"])
            _nonnegative_int(entry["post_index"], "post_index")
            span = _mapping(entry["calamari_span"], "calamari_span")
            char_from = _nonnegative_int(span.get("char_from"), "calamari_span char_from")
            char_to = _nonnegative_int(span.get("char_to"), "calamari_span char_to")
            if char_from >= char_to:
                return ["calamari_span skal have char_from < char_to"]
            _nonempty_string(entry["calamari_verbatim_text"], "calamari_verbatim_text")
            pages = entry["pdf_pages"]
            if not isinstance(pages, list) or not pages:
                return ["pdf_pages skal være en ikke-tom liste"]
            if any(
                not isinstance(page, int) or isinstance(page, bool) or page <= 0
                for page in pages
            ):
                return ["pdf_pages skal være et positivt heltal"]
            _nonempty_string(entry["kind"], "kind")
            raw_from = _nonnegative_int(entry["raw_char_from"], "raw_char_from")
            raw_to = _nonnegative_int(entry["raw_char_to"], "raw_char_to")
            if raw_from >= raw_to:
                return ["raw_char_from skal være mindre end raw_char_to"]
            raw_verbatim = _nonempty_string(entry["raw_verbatim_text"], "raw_verbatim_text")
            raw_digest = entry["raw_excerpt_sha256"]
            if not isinstance(raw_digest, str) or not _SHA256_RE.fullmatch(raw_digest):
                return ["raw_excerpt_sha256 skal være SHA-256 med små bogstaver"]
            if raw_digest != hashlib.sha256(raw_verbatim.encode("utf-8")).hexdigest():
                return ["raw_excerpt_sha256 matcher ikke raw_verbatim_text"]
        except ValueError as error:
            return [str(error)]
        return []
    if status == "eksplicit_dublet":
        target = entry.get("duplicate_of_baseline_record_key")
        if not isinstance(target, str) or not target.strip():
            return ["eksplicit_dublet kræver duplicate_of_baseline_record_key"]
        if LEGACY_REVIEW_ACCEPTED_FIELDS.intersection(entry) or "reason" in entry:
            return ["eksplicit_dublet må ikke have kandidat- eller reason-felter"]
        return []
    reason = entry.get("reason")
    if not isinstance(reason, str) or not reason.strip():
        return ["menneskeark kræver reason"]
    if (
        LEGACY_REVIEW_ACCEPTED_FIELDS.intersection(entry)
        or "duplicate_of_baseline_record_key" in entry
    ):
        return ["menneskeark må ikke have kandidat- eller dubletfelter"]
    return []


def validate_coverage(bundle: dict, *, expected_baseline_keys: set[str]) -> dict[str, dict]:
    """Validate complete private 1939 coverage without I/O or input mutation."""
    root = _mapping(bundle, "coverage")
    if not is_schema_version_one(root.get("schema_version")):
        raise ValueError("schema_version skal være 1")
    _validate_source(root.get("source"))
    entries = root.get("entries")
    if not isinstance(entries, list):
        raise ValueError("entries skal være en liste")
    if any(not isinstance(key, str) or not key for key in expected_baseline_keys):
        raise ValueError("forventede baseline-nøgler skal være ikke-tomme strenge")

    seen_keys: set[str] = set()
    seen_candidate_ids: set[str] = set()
    seen_spans: set[tuple[int, int]] = set()
    result: dict[str, dict] = {}
    for entry_value in entries:
        entry = _mapping(entry_value, "coverage entry")
        key = _nonempty_string(entry.get("baseline_record_key"), "baseline_record_key")
        if key in seen_keys:
            raise ValueError("dublet baseline_record_key")
        seen_keys.add(key)

        status = entry.get("status")
        if status not in ALLOWED_STATUSES:
            raise ValueError("ukendt status")
        has_candidate = "candidate" in entry
        if status == "accepteret":
            if not has_candidate:
                raise ValueError("accepteret entry kræver candidate")
            _validate_candidate(entry["candidate"], seen_candidate_ids, seen_spans)
        elif status == "eksplicit_dublet":
            if has_candidate:
                raise ValueError("eksplicit_dublet må ikke have candidate")
            _nonempty_string(
                entry.get("duplicate_of_baseline_record_key"),
                "duplicate_of_baseline_record_key",
            )
        else:
            if has_candidate:
                raise ValueError("menneskeark må ikke have candidate")
            _nonempty_string(entry.get("reason"), "reason")

        result[key] = copy.deepcopy(dict(entry))

    if seen_keys != expected_baseline_keys:
        raise ValueError("baseline-dækning fejler")
    target_errors = duplicate_target_errors(result)
    if target_errors:
        raise ValueError(next(iter(target_errors.values())))
    return result
