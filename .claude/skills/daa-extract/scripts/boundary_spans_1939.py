"""Danner grænserne mellem accepterede kildespænd, uden at ændre dem."""

from __future__ import annotations

import copy
import hashlib
from collections.abc import Mapping


class BoundaryError(ValueError):
    pass


def _coordinates(char_from: object, char_to: object, label: str) -> tuple[int, int]:
    for value in (char_from, char_to):
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise BoundaryError(f"{label} har ugyldige koordinater")
    if char_to <= char_from:
        raise BoundaryError(f"{label} har tomt spænd")
    return char_from, char_to


def _span_of(candidate: object, label: str) -> tuple[int, int]:
    if not isinstance(candidate, Mapping):
        raise BoundaryError(f"{label} mangler kandidat")
    span = candidate.get("calamari_span")
    if not isinstance(span, Mapping):
        raise BoundaryError(f"{label} mangler calamari_span")
    char_from, char_to = span.get("char_from"), span.get("char_to")
    return _coordinates(char_from, char_to, f"{label} har ugyldigt calamari_span")


def _validated_span(span: object, label: str) -> dict:
    if not isinstance(span, Mapping):
        raise BoundaryError(f"{label} skal være en mapping")
    record_key = span.get("baseline_record_key")
    if not isinstance(record_key, str) or not record_key:
        raise BoundaryError(f"{label} mangler baseline_record_key")
    candidate_id = span.get("candidate_id")
    if not isinstance(candidate_id, str) or not candidate_id:
        raise BoundaryError(f"{label} mangler candidate_id")
    origin = span.get("origin")
    if origin not in {"menneske", "automatisk"}:
        raise BoundaryError(f"{label} har ugyldig oprindelse")
    char_from, char_to = _coordinates(
        span.get("char_from"), span.get("char_to"), label,
    )
    return {
        "baseline_record_key": record_key,
        "candidate_id": candidate_id,
        "char_from": char_from,
        "char_to": char_to,
        "origin": origin,
    }


def _validated_ordered_spans(spans: object) -> list[dict]:
    if not isinstance(spans, list):
        raise BoundaryError("spænd skal leveres som en liste")
    validated = [_validated_span(span, "accepteret spænd") for span in spans]
    for left, right in zip(validated, validated[1:]):
        if (right["char_from"], right["char_to"]) < (left["char_from"], left["char_to"]):
            raise BoundaryError("accepterede spænd er ikke sorteret")
        if right["char_from"] < left["char_to"]:
            raise BoundaryError(
                f"spænd overlapper: {left['baseline_record_key']} og "
                f"{right['baseline_record_key']}"
            )
    return validated


def _entry(record_key: object, candidate: object, origin: str) -> dict:
    char_from, char_to = _span_of(candidate, "accepteret spænd")
    span = _validated_span({
        "baseline_record_key": record_key,
        "candidate_id": candidate.get("candidate_id"),
        "char_from": char_from,
        "char_to": char_to,
        "origin": origin,
    }, "accepteret spænd")
    span["candidate"] = copy.deepcopy(candidate)
    return span


def collect_accepted_spans(anchored: object, automatic: object) -> list[dict]:
    """Saml de accepterede spænd fra begge producenter, fail-closed på overlap."""
    if not isinstance(anchored, Mapping) or not isinstance(automatic, Mapping):
        raise BoundaryError("accepterede spænd skal leveres som mappings")
    spans: list[dict] = []
    for entry in anchored.values():
        if not isinstance(entry, Mapping):
            raise BoundaryError("forankret kandidat skal være en mapping")
        spans.append(_entry(entry.get("baseline_record_key"),
                            entry.get("candidate"), "menneske"))
    for entry in automatic.values():
        if not isinstance(entry, Mapping):
            raise BoundaryError("automatisk kandidat skal være en mapping")
        spans.append(_entry(entry.get("baseline_record_key"),
                            entry.get("candidate"), "automatisk"))
    owners: dict[str, str] = {}
    for span in spans:
        key = span["baseline_record_key"]
        if key in owners:
            raise BoundaryError(f"post {key} ejer et spænd to gange")
        owners[key] = span["candidate_id"]
    spans.sort(key=lambda span: (span["char_from"], span["char_to"]))
    _validated_ordered_spans(spans)
    return spans


def boundary_id_for(before: Mapping | None, after: Mapping | None,
                    revision: int) -> str:
    """Identiteten er de to nabospænd PLUS revisionen.

    Uden revisionen ville A -> B -> A give det oprindelige id igen, og en gammel
    dom kunne fremstå gyldig for en grænse der har været igennem to rettelser.
    """
    if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
        raise BoundaryError("revision skal være et ikke-negativt heltal")

    before = None if before is None else _validated_span(before, "forrige spænd")
    after = None if after is None else _validated_span(after, "næste spænd")
    if before is not None and after is not None:
        _validated_ordered_spans([before, after])

    def part(span: Mapping | None, label: str) -> str:
        if span is None:
            return label
        return f"{span['candidate_id']}:{span['char_from']}:{span['char_to']}"

    digest = hashlib.sha256(
        "\0".join(("1939-v2", part(before, "kildestart"), part(after, "kildeslut"),
                   str(revision))).encode("utf-8")
    ).hexdigest()
    return f"graense:1939-v2:{digest}"


def build_boundaries(spans: list[dict], source_length: int) -> list[dict]:
    """Én grænse pr. skifte i ejerskab, inklusive kildens to rande."""
    if isinstance(source_length, bool) or not isinstance(source_length, int) or source_length < 0:
        raise BoundaryError("source_length skal være et ikke-negativt heltal")
    spans = _validated_ordered_spans(spans)
    for span in spans:
        if span["char_to"] > source_length:
            raise BoundaryError(
                f"post {span['baseline_record_key']} rækker ud over kildeteksten"
            )
    edges: list[tuple[dict | None, dict | None, int, int]] = []
    if not spans:
        edges.append((None, None, 0, source_length))
    else:
        edges.append((None, spans[0], 0, spans[0]["char_from"]))
        for left, right in zip(spans, spans[1:]):
            edges.append((left, right, left["char_to"], right["char_from"]))
        edges.append((spans[-1], None, spans[-1]["char_to"], source_length))
    return [
        {
            "boundary_id": boundary_id_for(before, after, 0),
            "revision": 0,
            "before": before,
            "after": after,
            "gap": {"char_from": gap_from, "char_to": gap_to},
        }
        for before, after, gap_from, gap_to in edges
    ]
