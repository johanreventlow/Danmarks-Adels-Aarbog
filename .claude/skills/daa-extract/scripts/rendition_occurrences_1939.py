#!/usr/bin/env python3
"""Extract exact, rendition-local 1939 source occurrences.

The result deliberately contains no logical identity.  It is an immutable
source envelope for later, separately reviewed evidence binding.
"""
from __future__ import annotations

import hashlib
import json
import re

import segment


RENDITIONS = {"calamari", "raw_ocr"}
POST_CLASSES = {"nummereret", "stamfader", "oversigtspost"}

CALAMARI_R6_TO_PDF_V1 = (
    (1, 496), (5, 500), (10, 505), (15, 510), (20, 515),
    (25, 520), (30, 525), (40, 535), (45, 540), (50, 545),
    (53, 550), (58, 555), (63, 575), (68, 580), (73, 585),
    (78, 590), (83, 595), (85, 598), (86, 598),
)

_PAGE_RE = re.compile(r"^###\s*PAGE\s+(\d+)\s*###\s*$")
_PRINTED_MARKER_RE = re.compile(r"^\s*\??\s*(\d{1,4}[a-z]?)\.\s+\S", re.I)
_ROMAN_SECTION_RE = re.compile(r"^\s*([IVXLCDM]+)[.,]?\s*$", re.I)
_ROMAN_GENERATION_RE = re.compile(
    r"^\s*([IVXLCDM]+)\.\s+.+\bslægtled\s*$", re.I
)
_CLAUSE_KEYS = {
    "clause_id", "record_key", "occurrence_id", "span", "classification",
    "observation_ids", "verbatim_text",
}
_CANONICAL_OCCURRENCE_KEYS = (
    "order", "span", "verbatim_sha256", "pdf_pages", "post_class",
    "printed_marker", "section_signature",
)


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _is_exact_int(value: object) -> bool:
    return type(value) is int


def _is_exact_str(value: object) -> bool:
    return type(value) is str


def _validate_page_map(rendition: str, page_map: object) -> tuple[tuple[int, int], ...] | None:
    if type(rendition) is not str or rendition not in RENDITIONS:
        raise ValueError("rendition must be one of %s" % sorted(RENDITIONS))
    if rendition == "raw_ocr":
        if page_map is not None:
            raise ValueError("page_map must be None for raw_ocr")
        return None
    if type(page_map) is not tuple or not page_map:
        raise ValueError("page_map must be a nonempty ordered tuple for calamari")
    previous_source_page = 0
    previous_pdf_page = -1
    validated = []
    for point in page_map:
        if type(point) is not tuple or len(point) != 2:
            raise ValueError("page_map points must be two-item tuples")
        source_page, pdf_page = point
        if not _is_exact_int(source_page) or not _is_exact_int(pdf_page):
            raise ValueError("page_map pages must be integers")
        if source_page <= previous_source_page or pdf_page < previous_pdf_page:
            raise ValueError("page_map must be ordered by source and PDF page")
        validated.append((source_page, pdf_page))
        previous_source_page = source_page
        previous_pdf_page = pdf_page
    mapping = tuple(validated)
    if mapping != CALAMARI_R6_TO_PDF_V1:
        raise ValueError("page_map must exactly equal CALAMARI_R6_TO_PDF_V1")
    return mapping


def _validate_complete_clause_partition(source_text: str, clauses: object) -> None:
    """Accept only the exact JSON ledger shape and exact source coverage."""
    if type(clauses) is not list:
        raise ValueError("clauses must be a list")
    if not clauses:
        if source_text:
            raise ValueError("clauses do not cover source text")
        return
    cursor = 0
    for clause in clauses:
        if type(clause) is not dict or set(clause) != _CLAUSE_KEYS:
            raise ValueError("clause has an invalid JSON shape")
        if not _is_exact_str(clause["clause_id"]):
            raise ValueError("clause_id must be a string")
        if clause["record_key"] is not None:
            raise ValueError("record_key is not permitted in rendition clauses")
        if not _is_exact_str(clause["occurrence_id"]):
            raise ValueError("occurrence_id must be a string")
        if type(clause["span"]) is not dict or set(clause["span"]) != {"char_from", "char_to"}:
            raise ValueError("clause span has an invalid JSON shape")
        start = clause["span"]["char_from"]
        end = clause["span"]["char_to"]
        if not _is_exact_int(start) or not _is_exact_int(end) or start != cursor or end <= start:
            raise ValueError("clause spans must be ordered, contiguous, and nonempty")
        if end > len(source_text):
            raise ValueError("clause span is outside source text")
        if clause["classification"] not in {"record_text", "structural_header", "layout", "noise"}:
            raise ValueError("clause has an unknown classification")
        observation_ids = clause["observation_ids"]
        if type(observation_ids) is not list or any(not _is_exact_str(item) for item in observation_ids):
            raise ValueError("clause observation_ids must be a list of strings")
        if not _is_exact_str(clause["verbatim_text"]):
            raise ValueError("clause verbatim_text must be a string")
        if source_text[start:end] != clause["verbatim_text"]:
            raise ValueError("clause verbatim_text does not match source text")
        cursor = end
    if cursor != len(source_text):
        raise ValueError("clauses do not cover source text")


def _section_label(clause: dict) -> str | None:
    """Return a structural Roman label, never a person-derived label."""
    line = clause["verbatim_text"].rstrip("\r\n")
    match = _ROMAN_SECTION_RE.match(line) or _ROMAN_GENERATION_RE.match(line)
    return match.group(1).upper() if match else None


def _is_source_structural_clause(clause: dict) -> bool:
    if clause["classification"] == "structural_header":
        return True
    return _section_label(clause) is not None


def _map_pdf_page(page: int, rendition: str,
                  page_mapping: tuple[tuple[int, int], ...] | None) -> int:
    if rendition == "raw_ocr":
        return page
    assert page_mapping is not None
    for source_page, pdf_page in page_mapping:
        if page == source_page:
            return pdf_page
    for (left_source, left_pdf), (right_source, right_pdf) in zip(page_mapping, page_mapping[1:]):
        if left_source < page < right_source:
            numerator = (page - left_source) * (right_pdf - left_pdf)
            denominator = right_source - left_source
            # Half pages round up, so the result is deterministic and does not
            # inherit Python's banker's-rounding behaviour.
            return left_pdf + (2 * numerator + denominator) // (2 * denominator)
    raise ValueError("page marker is outside page_map")


def _pages_in_slice(source_text: str, start: int, end: int, rendition: str,
                    page_mapping: tuple[tuple[int, int], ...] | None) -> list[int]:
    preceding_page = None
    for raw_line in source_text[:start].splitlines():
        match = _PAGE_RE.match(raw_line)
        if match:
            preceding_page = _map_pdf_page(int(match.group(1)), rendition, page_mapping)
    pages = [preceding_page] if preceding_page is not None else []
    for raw_line in source_text[start:end].splitlines():
        match = _PAGE_RE.match(raw_line)
        if match:
            pdf_page = _map_pdf_page(int(match.group(1)), rendition, page_mapping)
            if not pages or pages[-1] != pdf_page:
                pages.append(pdf_page)
    return pages


def _first_record_text_clause(clauses: list[dict], assignments: list[int], group: int) -> dict:
    fallback = None
    for clause, assigned_group in zip(clauses, assignments):
        if assigned_group != group or clause["classification"] != "record_text":
            continue
        fallback = fallback or clause
        if not _is_source_structural_clause(clause):
            return clause
    if fallback is not None:
        return fallback
    raise ValueError("occurrence has no record text")


def _collapse_occurrence_clauses(source_text: str, clauses: list[dict], *, rendition: str,
                                 page_mapping: tuple[tuple[int, int], ...] | None) -> list[dict]:
    """Collapse ledger-local clauses while retaining a contiguous source partition."""
    owner_groups = []
    owner_for_clause = []
    group_for_occurrence_id = {}
    section_for_group = {}
    section_signature = []

    for clause in clauses:
        label = _section_label(clause)
        if label is not None:
            section_signature = [label]
        is_owner = (clause["classification"] == "record_text"
                    and not _is_source_structural_clause(clause))
        if not is_owner:
            owner_for_clause.append(None)
            continue
        occurrence_id = clause["occurrence_id"]
        group = group_for_occurrence_id.get(occurrence_id)
        if group is None:
            group = len(owner_groups)
            group_for_occurrence_id[occurrence_id] = group
            owner_groups.append(occurrence_id)
            section_for_group[group] = list(section_signature)
        owner_for_clause.append(group)

    if not clauses:
        return []
    if not owner_groups:
        owner_groups.append("unclassified-source")
        owner_for_clause = [0] * len(clauses)
        section_for_group[0] = list(section_signature)
    else:
        next_owner = [None] * len(clauses)
        nearest = None
        for index in range(len(clauses) - 1, -1, -1):
            if owner_for_clause[index] is not None:
                nearest = owner_for_clause[index]
            next_owner[index] = nearest
        previous = None
        for index, owner in enumerate(owner_for_clause):
            if owner is not None:
                previous = owner
                continue
            following = next_owner[index]
            owner_for_clause[index] = following if following is not None else previous

    grouped = [[] for _ in owner_groups]
    for clause, group in zip(clauses, owner_for_clause):
        if group is None:
            raise ValueError("could not assign source clause to an occurrence")
        grouped[group].append(clause)

    occurrences = []
    for order, group_clauses in enumerate(grouped):
        start = group_clauses[0]["span"]["char_from"]
        end = group_clauses[-1]["span"]["char_to"]
        first_text = _first_record_text_clause(clauses, owner_for_clause, order)
        marker_match = _PRINTED_MARKER_RE.match(first_text["verbatim_text"].rstrip("\r\n"))
        printed_marker = marker_match.group(1).lower() if marker_match else None
        occurrence = {
            "order": order,
            "span": {"char_from": start, "char_to": end},
            "verbatim_sha256": _sha256_text(source_text[start:end]),
            "pdf_pages": _pages_in_slice(source_text, start, end, rendition, page_mapping),
            "post_class": "nummereret" if printed_marker is not None else None,
            "printed_marker": printed_marker,
            "section_signature": section_for_group[order],
        }
        signature = _canonical_occurrence_signature(occurrence)
        occurrence["occurrence_id"] = "occ:%s:%s" % (rendition, signature)
        occurrences.append(occurrence)
    return occurrences


def _canonical_occurrence_signature(occurrence: dict) -> str:
    canonical = {key: occurrence[key] for key in _CANONICAL_OCCURRENCE_KEYS}
    encoded = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return _sha256_text(encoded)


def _attach_neighbor_signatures(occurrences: list[dict]) -> None:
    for index, occurrence in enumerate(occurrences):
        occurrence["predecessor_signature"] = (
            _canonical_occurrence_signature(occurrences[index - 1]) if index else None
        )
        occurrence["successor_signature"] = (
            _canonical_occurrence_signature(occurrences[index + 1])
            if index + 1 < len(occurrences) else None
        )


def _validate_occurrence_partition(occurrences: list[dict], source_length: int) -> None:
    cursor = 0
    for order, occurrence in enumerate(occurrences):
        if "record_key" in occurrence:
            raise ValueError("occurrences must not include record_key")
        span = occurrence.get("span")
        if type(span) is not dict or span.get("char_from") != cursor:
            raise ValueError("occurrences do not form an ordered source partition")
        end = span.get("char_to")
        if not _is_exact_int(end) or end <= cursor:
            raise ValueError("occurrence span is invalid")
        if occurrence.get("order") != order:
            raise ValueError("occurrence order is invalid")
        if occurrence.get("post_class") not in POST_CLASSES | {None}:
            raise ValueError("occurrence post class is invalid")
        cursor = end
    if cursor != source_length:
        raise ValueError("occurrences do not cover source text")


def extract_rendition_occurrences(source_text: str, *, rendition: str,
                                  page_map: tuple[tuple[int, int], ...] | None) -> dict:
    """Return exact, record-key-free source occurrences for one OCR rendition."""
    if type(source_text) is not str:
        raise ValueError("source_text must be a string")
    page_mapping = _validate_page_map(rendition, page_map)
    ledger = segment._evidence_ledger(source_text)
    if type(ledger) is not dict or set(ledger) != {
        "schema_version", "source_length", "clauses", "observations", "record_placements",
    }:
        raise ValueError("evidence ledger has an invalid JSON shape")
    if ledger["source_length"] != len(source_text):
        raise ValueError("evidence ledger source length does not match source text")
    _validate_complete_clause_partition(source_text, ledger["clauses"])
    occurrences = _collapse_occurrence_clauses(
        source_text, ledger["clauses"], rendition=rendition, page_mapping=page_mapping
    )
    _attach_neighbor_signatures(occurrences)
    _validate_occurrence_partition(occurrences, len(source_text))
    return {
        "schema_version": 1,
        "rendition": rendition,
        "source_sha256": _sha256_text(source_text),
        "source_length": len(source_text),
        "page_mapping_id": (
            "calamari-r6-to-pdf-v1" if rendition == "calamari" else "raw-ocr-physical-pdf-v1"
        ),
        "page_mapping_points": [list(point) for point in page_mapping] if page_mapping else [],
        "occurrences": occurrences,
    }
