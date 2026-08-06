#!/usr/bin/env python3
"""Bind only uniquely occurring, verbatim baseline narratives to source envelopes."""
from __future__ import annotations

import hashlib
from functools import lru_cache


NARRATIVE_SOURCES = {"calamari": "calamari", "raw": "raw_ocr"}
POST_CLASSES = {"nummereret", "stamfader", "oversigtspost"}


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


def _validated_occurrences(manifest: object, rendition: str) -> tuple[dict, ...]:
    """Read just the extracted occurrence facts used for cross-rendition safety."""
    if type(manifest) is not dict or manifest.get("rendition") != rendition:
        raise ValueError("occurrence manifest rendition does not match source")
    source_length = manifest.get("source_length")
    if not _is_exact_int(source_length) or source_length < 0:
        raise ValueError("occurrence manifest source_length must be a nonnegative integer")
    occurrences = manifest.get("occurrences")
    if type(occurrences) is not list:
        raise ValueError("occurrence manifest occurrences must be a list")
    ids = set()
    orders = set()
    validated = []
    for occurrence in occurrences:
        if type(occurrence) is not dict or "record_key" in occurrence:
            raise ValueError("occurrence must be a record-key-free dict")
        occurrence_id = occurrence.get("occurrence_id")
        order = occurrence.get("order")
        if (not _is_exact_str(occurrence_id) or not occurrence_id or occurrence_id in ids
                or not _is_exact_int(order) or order < 0 or order in orders):
            raise ValueError("occurrence id and order must be unique")
        span = occurrence.get("span")
        if type(span) is not dict or set(span) != {"char_from", "char_to"}:
            raise ValueError("occurrence span must have char_from and char_to")
        start, end = span["char_from"], span["char_to"]
        if (not _is_exact_int(start) or not _is_exact_int(end)
                or start < 0 or end <= start or end > source_length):
            raise ValueError("occurrence span is outside source text")
        pages = occurrence.get("pdf_pages")
        if (type(pages) is not list or not pages
                or any(not _is_exact_int(page) or page <= 0 for page in pages)
                or pages != sorted(set(pages))):
            raise ValueError("occurrence pdf_pages must be sorted physical pages")
        post_class = occurrence.get("post_class")
        if post_class is not None and post_class not in POST_CLASSES:
            raise ValueError("occurrence post_class is invalid")
        printed_marker = occurrence.get("printed_marker")
        if printed_marker is not None and (not _is_exact_str(printed_marker) or not printed_marker):
            raise ValueError("occurrence printed_marker is invalid")
        section = occurrence.get("section_signature")
        if type(section) is not list or any(not _is_exact_str(value) for value in section):
            raise ValueError("occurrence section_signature is invalid")
        ids.add(occurrence_id)
        orders.add(order)
        validated.append({
            "occurrence_id": occurrence_id,
            "order": order,
            "span": {"char_from": start, "char_to": end},
            "pdf_pages": tuple(pages),
            "post_class": post_class,
            "printed_marker": printed_marker,
            "section_signature": tuple(section),
        })
    if orders != set(range(len(validated))):
        raise ValueError("occurrence orders must be contiguous from zero")
    return tuple(sorted(validated, key=lambda occurrence: occurrence["order"]))


def _pages_compatible(left: dict, right: dict) -> bool:
    return left["pdf_pages"] == right["pdf_pages"]


def _compatible(left: dict, right: dict) -> bool:
    return all((
        left["post_class"] in POST_CLASSES,
        right["post_class"] in POST_CLASSES,
        left["post_class"] == right["post_class"],
        left["printed_marker"] == right["printed_marker"],
        _pages_compatible(left, right),
        left["section_signature"] == right["section_signature"],
    ))


def _compatibility_edges(calamari: tuple[dict, ...], raw: tuple[dict, ...]) -> set[tuple[int, int]]:
    return {
        (left_index, right_index)
        for left_index, left in enumerate(calamari)
        for right_index, right in enumerate(raw)
        if _compatible(left, right)
    }


def _alignment_table(edges: set[tuple[int, int]], left_count: int, right_count: int) -> list[list[int]]:
    """Maximum monotone-cardinality table; no scores or tie-breaking are used."""
    table = [[0] * (right_count + 1) for _ in range(left_count + 1)]
    for left_index in range(left_count - 1, -1, -1):
        best_edge_suffix = 0
        for right_index in range(right_count - 1, -1, -1):
            if (left_index, right_index) in edges:
                best_edge_suffix = max(best_edge_suffix, 1 + table[left_index + 1][right_index + 1])
            table[left_index][right_index] = max(table[left_index + 1][right_index], best_edge_suffix)
    return table


def _maximum_monotone_cardinality(edges: set[tuple[int, int]], left_count: int, right_count: int) -> int:
    return _alignment_table(edges, left_count, right_count)[0][0]


def _optimal_path_membership(
    edges: set[tuple[int, int]], left_count: int, right_count: int,
) -> tuple[int, frozenset[tuple[int, int]]]:
    """Return the capped path count and the intersection of all optimal paths.

    A path chooses either to skip the current left occurrence or to pair it
    with one compatible later right occurrence.  That representation is unique
    for every monotone alignment, so counts do not depend on skip iteration.
    """
    table = _alignment_table(edges, left_count, right_count)
    right_edges = [[] for _ in range(left_count)]
    for left_index, right_index in edges:
        right_edges[left_index].append(right_index)
    right_edges = tuple(tuple(sorted(indices)) for indices in right_edges)

    @lru_cache(maxsize=None)
    def paths(left_index: int, right_index: int) -> tuple[int, frozenset[tuple[int, int]]]:
        if left_index == left_count:
            return 1, frozenset()
        optimum = table[left_index][right_index]
        branches = []
        if table[left_index + 1][right_index] == optimum:
            branches.append(paths(left_index + 1, right_index))
        for candidate_right in right_edges[left_index]:
            if candidate_right < right_index:
                continue
            if 1 + table[left_index + 1][candidate_right + 1] != optimum:
                continue
            count, required = paths(left_index + 1, candidate_right + 1)
            branches.append((count, required | {(left_index, candidate_right)}))
        if not branches:
            raise AssertionError("optimal alignment state has no branch")
        count = min(2, sum(branch_count for branch_count, _ in branches))
        required = branches[0][1]
        for _, branch_required in branches[1:]:
            required = required & branch_required
        return count, frozenset(required)

    return paths(0, 0)


def _edges_present_in_every_optimal_alignment(
    edges: set[tuple[int, int]], optimum: int, path_count: int,
    required: frozenset[tuple[int, int]],
) -> frozenset[tuple[int, int]]:
    if optimum == 0 or path_count == 0:
        return frozenset()
    return required


def _alignment_result(
    calamari: tuple[dict, ...], raw: tuple[dict, ...], invariant_pairs: frozenset[tuple[int, int]],
    edges: set[tuple[int, int]],
) -> dict:
    pairs = [
        {
            "calamari_occurrence_id": calamari[left_index]["occurrence_id"],
            "raw_occurrence_id": raw[right_index]["occurrence_id"],
        }
        for left_index, right_index in sorted(invariant_pairs)
    ]
    invariant_ids = {
        ("calamari", calamari[left_index]["occurrence_id"])
        for left_index, _ in invariant_pairs
    } | {
        ("raw_ocr", raw[right_index]["occurrence_id"])
        for _, right_index in invariant_pairs
    }
    edge_ids = {
        ("calamari", calamari[left_index]["occurrence_id"])
        for left_index, _ in edges
    } | {
        ("raw_ocr", raw[right_index]["occurrence_id"])
        for _, right_index in edges
    }
    ambiguous_ids = edge_ids - invariant_ids
    return {
        "pairs": pairs,
        "calamari_unmatched": [
            occurrence["occurrence_id"] for occurrence in calamari
            if ("calamari", occurrence["occurrence_id"]) not in edge_ids
        ],
        "raw_unmatched": [
            occurrence["occurrence_id"] for occurrence in raw
            if ("raw_ocr", occurrence["occurrence_id"]) not in edge_ids
        ],
        "ambiguous_occurrence_ids": [
            occurrence["occurrence_id"] for occurrence in calamari
            if ("calamari", occurrence["occurrence_id"]) in ambiguous_ids
        ] + [
            occurrence["occurrence_id"] for occurrence in raw
            if ("raw_ocr", occurrence["occurrence_id"]) in ambiguous_ids
        ],
    }


def align_renditions(calamari_manifest: dict, raw_manifest: dict) -> dict:
    """Emit only occurrence pairs common to every maximum monotone alignment."""
    calamari = _validated_occurrences(calamari_manifest, "calamari")
    raw = _validated_occurrences(raw_manifest, "raw_ocr")
    edges = _compatibility_edges(calamari, raw)
    optimum = _maximum_monotone_cardinality(edges, len(calamari), len(raw))
    path_count, required = _optimal_path_membership(edges, len(calamari), len(raw))
    invariant_pairs = _edges_present_in_every_optimal_alignment(edges, optimum, path_count, required)
    return _alignment_result(calamari, raw, invariant_pairs, edges)


def _bidirectional_pair_index(pairs: object) -> tuple[dict[str, str | None], dict[str, str | None]]:
    if type(pairs) is not list:
        raise ValueError("alignment pairs must be a list")
    calamari_to_raw: dict[str, str | None] = {}
    raw_to_calamari: dict[str, str | None] = {}
    for pair in pairs:
        if type(pair) is not dict:
            raise ValueError("alignment pair must be a dict")
        calamari_id = pair.get("calamari_occurrence_id")
        raw_id = pair.get("raw_occurrence_id")
        if not _is_exact_str(calamari_id) or not _is_exact_str(raw_id):
            raise ValueError("alignment pair ids must be strings")
        previous_raw = calamari_to_raw.get(calamari_id, raw_id)
        previous_calamari = raw_to_calamari.get(raw_id, calamari_id)
        calamari_to_raw[calamari_id] = raw_id if previous_raw == raw_id else None
        raw_to_calamari[raw_id] = calamari_id if previous_calamari == calamari_id else None
    return calamari_to_raw, raw_to_calamari


def _edge_token(occurrences: tuple[dict, ...], index: int, direction: int) -> tuple[str, tuple[str, ...] | str]:
    neighbor_index = index + direction
    if neighbor_index < 0 or neighbor_index >= len(occurrences):
        return ("document_start" if direction < 0 else "document_end", "")
    current = occurrences[index]
    neighbor = occurrences[neighbor_index]
    if current["section_signature"] != neighbor["section_signature"]:
        return ("section_edge", current["section_signature"])
    return ("occurrence", neighbor["occurrence_id"])


def _has_nested_same_section_boundary(occurrences: tuple[dict, ...], index: int) -> bool:
    current = occurrences[index]
    for neighbor_index in (index - 1, index + 1):
        if neighbor_index < 0 or neighbor_index >= len(occurrences):
            continue
        neighbor = occurrences[neighbor_index]
        if neighbor["section_signature"] != current["section_signature"]:
            continue
        if (neighbor_index < index and neighbor["span"]["char_to"] > current["span"]["char_from"]
                or neighbor_index > index and current["span"]["char_to"] > neighbor["span"]["char_from"]):
            return True
    return False


def _neighbors_agree(
    calamari: tuple[dict, ...], raw: tuple[dict, ...], calamari_index: int, raw_index: int,
    calamari_to_raw: dict[str, str | None], direction: int,
) -> bool:
    calamari_token = _edge_token(calamari, calamari_index, direction)
    raw_token = _edge_token(raw, raw_index, direction)
    if calamari_token[0] != raw_token[0]:
        return False
    if calamari_token[0] != "occurrence":
        return calamari_token == raw_token
    mapped = calamari_to_raw.get(calamari_token[1])
    if mapped != raw_token[1]:
        return False
    return _compatible(
        calamari[calamari_index + direction], raw[raw_index + direction]
    )


def _unanchored_consensus(record_key: str, reason: str) -> dict:
    return {"record_key": record_key, "status": "unanchored", "reason": reason}


def _derive_one_consensus(
    record_key: str, anchor: object, calamari_to_raw: dict[str, str | None], raw_to_calamari: dict[str, str | None],
    calamari: tuple[dict, ...], raw: tuple[dict, ...], calamari_by_id: dict[str, int], raw_by_id: dict[str, int],
) -> dict:
    if type(anchor) is not dict or anchor.get("status") != "unique_exact_anchor":
        reason = anchor.get("reason") if type(anchor) is dict else None
        return _unanchored_consensus(record_key, reason if _is_exact_str(reason) else "ambiguous_structure")
    rendition = anchor.get("rendition")
    occurrence_id = anchor.get("occurrence_id")
    if rendition == "calamari":
        calamari_id, raw_id = occurrence_id, calamari_to_raw.get(occurrence_id)
    elif rendition == "raw_ocr":
        raw_id, calamari_id = occurrence_id, raw_to_calamari.get(occurrence_id)
    else:
        return _unanchored_consensus(record_key, "ambiguous_structure")
    if (not _is_exact_str(calamari_id) or not _is_exact_str(raw_id)
            or calamari_id not in calamari_by_id or raw_id not in raw_by_id):
        return _unanchored_consensus(record_key, "ambiguous_structure")
    calamari_index, raw_index = calamari_by_id[calamari_id], raw_by_id[raw_id]
    left, right = calamari[calamari_index], raw[raw_index]
    if left["post_class"] != right["post_class"]:
        return _unanchored_consensus(record_key, "post_class_disagreement")
    if not _pages_compatible(left, right):
        return _unanchored_consensus(record_key, "page_disagreement")
    if left["printed_marker"] != right["printed_marker"] or left["section_signature"] != right["section_signature"]:
        return _unanchored_consensus(record_key, "boundary_disagreement")
    if _has_nested_same_section_boundary(calamari, calamari_index) or _has_nested_same_section_boundary(raw, raw_index):
        return _unanchored_consensus(record_key, "boundary_disagreement")
    if not _neighbors_agree(calamari, raw, calamari_index, raw_index, calamari_to_raw, -1):
        return _unanchored_consensus(record_key, "predecessor_disagreement")
    if not _neighbors_agree(calamari, raw, calamari_index, raw_index, calamari_to_raw, 1):
        return _unanchored_consensus(record_key, "successor_disagreement")
    return {
        "record_key": record_key,
        "status": "consensus",
        "calamari_occurrence_id": calamari_id,
        "raw_occurrence_id": raw_id,
        "calamari_span": dict(left["span"]),
        "raw_span": dict(right["span"]),
    }


def _demote_global_consensus_conflicts(result: dict[str, dict]) -> dict[str, dict]:
    claims: dict[tuple[str, str], list[str]] = {}
    for record_key, consensus in result.items():
        if consensus["status"] != "consensus":
            continue
        claims.setdefault(("calamari", consensus["calamari_occurrence_id"]), []).append(record_key)
        claims.setdefault(("raw_ocr", consensus["raw_occurrence_id"]), []).append(record_key)
    collisions = {record_key for record_keys in claims.values() if len(record_keys) > 1 for record_key in record_keys}
    for record_key in collisions:
        result[record_key] = _unanchored_consensus(record_key, "occurrence_collision")
    overlaps = set()
    for span_key in ("calamari_span", "raw_span"):
        active = []
        for record_key, consensus in sorted(
            ((key, value) for key, value in result.items() if value["status"] == "consensus"),
            key=lambda item: (item[1][span_key]["char_from"], item[1][span_key]["char_to"], item[0]),
        ):
            start, end = consensus[span_key]["char_from"], consensus[span_key]["char_to"]
            active = [(other_end, other_key) for other_end, other_key in active if other_end > start]
            overlaps.update(other_key for _, other_key in active)
            if active:
                overlaps.add(record_key)
            active.append((end, record_key))
    for record_key in overlaps:
        result[record_key] = _unanchored_consensus(record_key, "span_overlap")
    return result


def derive_consensus(
    anchors: dict[str, dict], alignment: dict, *, calamari_manifest: dict, raw_manifest: dict,
) -> dict[str, dict]:
    """Require invariant counterpart, both boundaries, and global injectivity."""
    if type(anchors) is not dict or type(alignment) is not dict:
        raise ValueError("anchors and alignment must be dicts")
    calamari = _validated_occurrences(calamari_manifest, "calamari")
    raw = _validated_occurrences(raw_manifest, "raw_ocr")
    calamari_to_raw, raw_to_calamari = _bidirectional_pair_index(alignment.get("pairs"))
    calamari_by_id = {occurrence["occurrence_id"]: index for index, occurrence in enumerate(calamari)}
    raw_by_id = {occurrence["occurrence_id"]: index for index, occurrence in enumerate(raw)}
    result = {}
    for record_key in sorted(anchors):
        if not _is_exact_str(record_key) or not record_key:
            raise ValueError("anchor record_key must be a nonempty string")
        result[record_key] = _derive_one_consensus(
            record_key, anchors[record_key], calamari_to_raw, raw_to_calamari,
            calamari, raw, calamari_by_id, raw_by_id,
        )
    return _demote_global_consensus_conflicts(result)
