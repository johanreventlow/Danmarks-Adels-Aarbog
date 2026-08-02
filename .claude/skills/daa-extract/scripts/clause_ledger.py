#!/usr/bin/env python3
"""Fail-closed clause coverage ledger for raw source renditions.

The ledger accounts for every character in the raw rendition.  A clause may
refer to an accepted logical ``record_key`` but never manufactures one from a
printed number, line label, or OCR text.
"""
from __future__ import annotations

from collections import deque
from typing import Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


class LedgerError(ValueError):
    """Raised when a ledger loses source coverage or encodes an unsafe span."""


def _require_int(value: object, field: str) -> int:
    if not isinstance(value, int):
        raise LedgerError("%s must be an integer" % field)
    return value


def build_ledger(source_text: str, clauses: Sequence[Mapping[str, object]]) -> List[Dict[str, object]]:
    """Normalize and validate declared, non-nested source clauses.

    Newlines and whitespace must be represented too; callers normally mark
    them ``layout``.  This makes omissions visible rather than silently lost.
    """
    normalized: List[Dict[str, object]] = []
    for clause_id, item in enumerate(clauses, 1):
        start = _require_int(item.get("char_from"), "char_from")
        end = _require_int(item.get("char_to"), "char_to")
        if start < 0 or end <= start or end > len(source_text):
            raise LedgerError("clause span is outside source text")
        classification = item.get("classification")
        if classification not in ("record_text", "structural_header", "layout", "noise"):
            raise LedgerError("unknown clause classification")
        observations = item.get("observation_ids", [])
        if not isinstance(observations, list) or any(not isinstance(value, str) or not value for value in observations):
            raise LedgerError("observation_ids must be a list of nonempty strings")
        occurrence_id = item.get("occurrence_id")
        if not isinstance(occurrence_id, str) or not occurrence_id:
            raise LedgerError("occurrence_id is required")
        record_key = item.get("record_key")
        if record_key is not None and (not isinstance(record_key, str) or not record_key):
            raise LedgerError("record_key must be a nonempty string or null")
        normalized.append({
            "clause_id": item.get("clause_id") or "clause-%06d" % clause_id,
            "record_key": record_key,
            "occurrence_id": occurrence_id,
            "span": {"char_from": start, "char_to": end},
            "classification": classification,
            "observation_ids": observations,
            "verbatim_text": source_text[start:end],
        })
    validate_ledger(normalized, source_text)
    return normalized


def validate_ledger(ledger: Sequence[Mapping[str, object]], source_text: Optional[str] = None) -> None:
    """Enforce non-overlap and complete character coverage.

    Nested source spans live in observations/mentions, not as overlapping
    top-level clauses.  This keeps the coverage invariant mechanically simple.
    """
    spans: List[Tuple[int, int]] = []
    for row in ledger:
        span = row.get("span")
        if not isinstance(span, Mapping):
            raise LedgerError("ledger row lacks span")
        start = _require_int(span.get("char_from"), "span.char_from")
        end = _require_int(span.get("char_to"), "span.char_to")
        if start < 0 or end <= start:
            raise LedgerError("invalid ledger span")
        spans.append((start, end))
    spans.sort()
    previous_end = 0
    for start, end in spans:
        if start < previous_end:
            raise LedgerError("top-level clauses overlap")
        if source_text is not None and start != previous_end:
            raise LedgerError("source character is not covered by a clause")
        previous_end = end
    if source_text is not None and previous_end != len(source_text):
        raise LedgerError("source character is not covered by a clause")


def placement_from_header(record_key: str, header_observation_id: str,
                          generation_label_raw: Optional[str], generation_local: Optional[int],
                          generation_global: Optional[int], kuld_label: Optional[str]) -> Dict[str, object]:
    """Create a placement only for an already accepted logical source record."""
    if not record_key or not header_observation_id:
        raise LedgerError("placement requires an accepted record key and header evidence")
    return {
        "record_key": record_key,
        "header_observation_id": header_observation_id,
        "generation_label_raw": generation_label_raw,
        "generation_local": generation_local,
        "generation_global": generation_global,
        "kuld_label": kuld_label,
    }


def persona_placements_from_record(record_key: str, principal_persona_id: str,
                                   principal_generation: Optional[int],
                                   mentioned_persona_ids: Iterable[str]) -> Dict[str, Optional[int]]:
    """A printed generation belongs to the principal, never automatically spouse mentions."""
    if not record_key or not principal_persona_id:
        raise LedgerError("principal source persona is required")
    placements = {principal_persona_id: principal_generation}
    for persona_id in mentioned_persona_ids:
        placements[persona_id] = None
    return placements


def persona_placements_from_records(records: Iterable[Mapping[str, object]]) -> Dict[str, Optional[int]]:
    placements: Dict[str, Optional[int]] = {}
    for record in records:
        key = record.get("record_key")
        persona_id = record.get("principal_persona_id")
        if not isinstance(key, str) or not isinstance(persona_id, str):
            raise LedgerError("record placement requires record_key and principal_persona_id")
        placements[persona_id] = record.get("generation")  # type: ignore[assignment]
    return placements


def compute_blood_generations(founders: Iterable[str], parent_edges: Iterable[Tuple[str, str]],
                              spouse_edges: Iterable[Tuple[str, str]]) -> Dict[str, int]:
    """Compute generations from parentage alone; spouse edges are deliberately ignored."""
    del spouse_edges
    generations = {founder: 1 for founder in founders}
    pending = deque(parent_edges)
    progressed = True
    while pending and progressed:
        progressed = False
        for _ in range(len(pending)):
            parent, child = pending.popleft()
            if parent not in generations:
                pending.append((parent, child))
                continue
            candidate = generations[parent] + 1
            if child not in generations or candidate < generations[child]:
                generations[child] = candidate
            progressed = True
    return generations
