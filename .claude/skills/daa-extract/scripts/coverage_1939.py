"""Fail-closed validation of private, anchored 1939 coverage."""

from __future__ import annotations

import copy
import re
from collections.abc import Mapping


ALLOWED_STATUSES = {"accepteret", "eksplicit_dublet", "menneskeark"}
POSTKLASSER = {"nummereret", "stamfader", "oversigtspost"}
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _mapping(value: object, label: str) -> Mapping:
    if not isinstance(value, Mapping):
        raise ValueError(f"{label} skal være en mapping")
    return value


def _nonempty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} skal være en ikke-tom streng")
    return value


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
    candidate_id = _nonempty_string(candidate.get("candidate_id"), "candidate_id")
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

    bridge = _mapping(candidate.get("raw_structure_bridge"), "rå-bro")
    _nonempty_string(bridge.get("kind"), "rå-bro kind")
    raw_from = _nonnegative_int(bridge.get("raw_char_from"), "rå-bro raw_char_from")
    raw_to = _nonnegative_int(bridge.get("raw_char_to"), "rå-bro raw_char_to")
    if raw_from >= raw_to:
        raise ValueError("rå-bro skal have raw_char_from < raw_char_to")


def validate_coverage(bundle: dict, *, expected_baseline_keys: set[str]) -> dict[str, dict]:
    """Validate complete private 1939 coverage without I/O or input mutation."""
    root = _mapping(bundle, "coverage")
    if root.get("schema_version") != 1:
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
    return result
