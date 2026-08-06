#!/usr/bin/env python3
"""Bind only uniquely occurring, verbatim baseline narratives to source envelopes."""
from __future__ import annotations

import hashlib


NARRATIVE_SOURCES = {"calamari": "calamari", "raw": "raw_ocr"}


def _is_exact_int(value: object) -> bool:
    return type(value) is int


def _is_exact_str(value: object) -> bool:
    return type(value) is str


def _validate_baseline_records(baseline_records: object) -> list[dict]:
    if type(baseline_records) is not list:
        raise ValueError("baseline_records must be a list")
    records = []
    record_keys = set()
    local_ids = set()
    for record in baseline_records:
        if type(record) is not dict:
            raise ValueError("baseline record must be a dict")
        for field in ("record_key", "_v2_lokal_id", "_narrativ_kilde", "narrative"):
            value = record.get(field)
            if not _is_exact_str(value):
                raise ValueError("%s must be a string" % field)
        for field, values in (("record_key", record_keys), ("_v2_lokal_id", local_ids)):
            value = record[field]
            if not value:
                raise ValueError("%s must not be empty" % field)
            if value in values:
                raise ValueError("duplicate %s" % field)
            values.add(value)
        records.append(record)
    return records


def _validated_occurrence_index(manifest: object, source_text: str, rendition: str) -> tuple[dict, ...]:
    if type(manifest) is not dict:
        raise ValueError("occurrence manifest must be a dict")
    if manifest.get("rendition") != rendition:
        raise ValueError("occurrence manifest rendition does not match source")
    if (not _is_exact_int(manifest.get("source_length"))
            or manifest["source_length"] != len(source_text)):
        raise ValueError("occurrence manifest source_length does not match source")
    expected_digest = hashlib.sha256(source_text.encode("utf-8")).hexdigest()
    if manifest.get("source_sha256") != expected_digest:
        raise ValueError("occurrence manifest source_sha256 does not match source")
    occurrences = manifest.get("occurrences")
    if type(occurrences) is not list:
        raise ValueError("occurrence manifest occurrences must be a list")
    cursor = 0
    ids = set()
    validated = []
    for occurrence in occurrences:
        if type(occurrence) is not dict or "record_key" in occurrence:
            raise ValueError("occurrence must be a record-key-free dict")
        occurrence_id = occurrence.get("occurrence_id")
        if not _is_exact_str(occurrence_id) or not occurrence_id or occurrence_id in ids:
            raise ValueError("occurrence_id must be a unique nonempty string")
        span = occurrence.get("span")
        if type(span) is not dict or set(span) != {"char_from", "char_to"}:
            raise ValueError("occurrence span must have char_from and char_to")
        start = span["char_from"]
        end = span["char_to"]
        if not _is_exact_int(start) or not _is_exact_int(end):
            raise ValueError("occurrence char_from and char_to must be integers")
        if start != cursor or end <= start or end > len(source_text):
            raise ValueError("occurrences must be a complete ordered source partition")
        ids.add(occurrence_id)
        validated.append({"occurrence_id": occurrence_id, "span": {"char_from": start, "char_to": end}})
        cursor = end
    if cursor != len(source_text):
        raise ValueError("occurrences must be a complete ordered source partition")
    return tuple(validated)


def _unanchored(record_key: str, reason: str) -> dict:
    return {"record_key": record_key, "status": "unanchored", "reason": reason}


def _locate_one_exact_anchor(record: dict, source_text: str, occurrences: tuple[dict, ...], rendition: str) -> dict:
    record_key = record["record_key"]
    narrative = record["narrative"]
    if not narrative:
        return _unanchored(record_key, "missing_exact_baseline_narrative")
    first = source_text.find(narrative)
    if first < 0:
        return _unanchored(record_key, "missing_exact_baseline_narrative")
    if source_text.find(narrative, first + 1) >= 0:
        return _unanchored(record_key, "repeated_exact_baseline_narrative")
    end = first + len(narrative)
    owners = [
        occurrence for occurrence in occurrences
        if occurrence["span"]["char_from"] <= first and end <= occurrence["span"]["char_to"]
    ]
    if len(owners) != 1:
        return _unanchored(record_key, "anchor_outside_occurrence")
    owner = owners[0]
    return {
        "record_key": record_key,
        "_v2_lokal_id": record["_v2_lokal_id"],
        "rendition": rendition,
        "occurrence_id": owner["occurrence_id"],
        "span": {"char_from": first, "char_to": end},
        "status": "unique_exact_anchor",
    }


def _demote_anchor_occurrence_collisions(anchors: dict[str, dict]) -> dict[str, dict]:
    claimants = {}
    for record_key, anchor in anchors.items():
        if anchor["status"] == "unique_exact_anchor":
            claimants.setdefault((anchor["rendition"], anchor["occurrence_id"]), []).append(record_key)
    collisions = {record_key for keys in claimants.values() if len(keys) > 1 for record_key in keys}
    for record_key in collisions:
        anchors[record_key] = _unanchored(record_key, "anchor_occurrence_collision")
    return anchors


def locate_baseline_anchors(
    baseline_records: list[dict], *, calamari_text: str, raw_text: str,
    calamari_occurrences: dict, raw_occurrences: dict,
) -> dict[str, dict]:
    """Return only source-safe, exact narrative anchors for baseline record keys."""
    if not _is_exact_str(calamari_text) or not _is_exact_str(raw_text):
        raise ValueError("source texts must be strings")
    records = _validate_baseline_records(baseline_records)
    occurrence_indexes = {
        "calamari": _validated_occurrence_index(calamari_occurrences, calamari_text, "calamari"),
        "raw_ocr": _validated_occurrence_index(raw_occurrences, raw_text, "raw_ocr"),
    }
    source_texts = {"calamari": calamari_text, "raw_ocr": raw_text}
    anchors = {}
    for record in records:
        rendition = NARRATIVE_SOURCES.get(record["_narrativ_kilde"])
        if rendition is None:
            anchors[record["record_key"]] = _unanchored(record["record_key"], "unknown_narrative_source")
        else:
            anchors[record["record_key"]] = _locate_one_exact_anchor(
                record, source_texts[rendition], occurrence_indexes[rendition], rendition
            )
    return _demote_anchor_occurrence_collisions(anchors)
