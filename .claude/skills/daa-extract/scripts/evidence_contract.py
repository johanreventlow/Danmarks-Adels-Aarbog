"""Edition-neutral, fail-closed contracts for extracted source evidence."""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Optional, Sequence, Tuple, Union


class ContractError(ValueError):
    """Raised when extracted evidence cannot be traced or is internally unsafe."""


def _require(value: Optional[str], field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ContractError("%s is required" % field)
    return value


@dataclass(frozen=True)
class SourceSpan:
    rendition_id: str
    page_from: int
    page_to: int
    column_label: Optional[str]
    char_from: int
    char_to: int
    source_text: str
    bbox: Optional[Tuple[int, int, int, int]]

    def validate(self) -> None:
        _require(self.rendition_id, "rendition_id")
        if self.page_from < 1 or self.page_to < self.page_from:
            raise ContractError("page span is invalid")
        if self.char_from < 0 or self.char_to <= self.char_from:
            raise ContractError("character span is invalid")
        if self.char_to > len(self.source_text):
            raise ContractError("character span exceeds source text")


@dataclass(frozen=True)
class Observation:
    observation_id: str
    occurrence_id: str
    kind: str
    verbatim_text: str
    span: SourceSpan
    extraction_method: str
    extraction_run_id: str

    def __post_init__(self) -> None:
        self.validate()

    def validate(self) -> None:
        _require(self.observation_id, "observation_id")
        _require(self.occurrence_id, "occurrence_id")
        _require(self.kind, "observation kind")
        _require(self.verbatim_text, "verbatim_text")
        _require(self.extraction_method, "extraction_method")
        _require(self.extraction_run_id, "extraction_run_id")
        self.span.validate()
        source_slice = self.span.source_text[self.span.char_from:self.span.char_to]
        if source_slice != self.verbatim_text:
            raise ContractError("verbatim_text must exactly equal the source span")


@dataclass(frozen=True)
class RecordOccurrence:
    occurrence_id: str
    rendition_id: str
    extraction_run_id: str
    span: SourceSpan
    verbatim_text: str

    def validate(self) -> None:
        _require(self.occurrence_id, "occurrence_id")
        _require(self.rendition_id, "rendition_id")
        _require(self.extraction_run_id, "extraction_run_id")
        _require(self.verbatim_text, "occurrence verbatim_text")
        self.span.validate()
        if self.rendition_id != self.span.rendition_id:
            raise ContractError("occurrence rendition differs from its span")


@dataclass(frozen=True)
class Mention:
    mention_id: str
    observation_id: str
    char_from: int
    char_to: int
    verbatim_text: str

    def validate_against(self, parent: Observation) -> None:
        _require(self.mention_id, "mention_id")
        if parent.observation_id != self.observation_id:
            raise ContractError("mention points to another observation")
        if self.char_from < 0 or self.char_to <= self.char_from or self.char_to > len(parent.verbatim_text):
            raise ContractError("mention offsets must be inside its observation")
        if parent.verbatim_text[self.char_from:self.char_to] != self.verbatim_text:
            raise ContractError("mention verbatim text must equal its observation slice")


@dataclass(frozen=True)
class SourcePersona:
    persona_id: str
    source_id: str
    mention_ids: Tuple[str, ...]
    occurrence_source_ids: Tuple[str, ...]

    def validate(self) -> None:
        _require(self.persona_id, "persona_id")
        _require(self.source_id, "source_id")
        if not self.mention_ids:
            raise ContractError("source persona requires at least one mention")
        if any(source_id != self.source_id for source_id in self.occurrence_source_ids):
            raise ContractError("source persona must be scoped to one source edition")


@dataclass(frozen=True)
class RecordAnchorEvent:
    event_id: str
    occurrence_id: str
    source_record_id: str
    decision_status: str
    version: int

    def validate(self) -> None:
        _require(self.event_id, "anchor event_id")
        _require(self.occurrence_id, "anchor occurrence_id")
        _require(self.source_record_id, "anchor source_record_id")
        if self.decision_status not in ("proposed", "accepted", "rejected"):
            raise ContractError("unknown anchor decision status")
        if self.version < 1:
            raise ContractError("anchor version must be positive")


@dataclass(frozen=True)
class RevisionEvent:
    event_id: str
    predecessor_record_id: str
    successor_record_id: str
    relation_kind: str
    decision_status: str
    version: int
    reviewed_by: Optional[str]

    def validate(self) -> None:
        _require(self.event_id, "revision event_id")
        _require(self.predecessor_record_id, "predecessor_record_id")
        _require(self.successor_record_id, "successor_record_id")
        if self.predecessor_record_id == self.successor_record_id:
            raise ContractError("revision event cannot point to the same record")
        if self.relation_kind not in ("split_into", "merged_from", "replaced_by"):
            raise ContractError("unknown revision relation kind")
        if self.decision_status not in ("proposed", "accepted", "rejected"):
            raise ContractError("unknown revision decision status")
        if self.version < 1:
            raise ContractError("revision version must be positive")
        if self.decision_status != "proposed" and not self.reviewed_by:
            raise ContractError("review is required for accepted or rejected revision events")


@dataclass(frozen=True)
class Interpretation:
    interpretation_id: str
    observation_ids: Tuple[str, ...]
    predicate: str
    value: Any
    status: str
    method: str
    confidence: Optional[float] = None

    def validate(self) -> None:
        _require(self.interpretation_id, "interpretation_id")
        if not self.observation_ids or any(not value for value in self.observation_ids):
            raise ContractError("interpretation requires observation ids")
        _require(self.predicate, "predicate")
        _require(self.status, "interpretation status")
        _require(self.method, "interpretation method")
        if self.predicate == "person.identity":
            raise ContractError("identity decisions are not interpretations")
        if self.confidence is not None and not 0.0 <= self.confidence <= 1.0:
            raise ContractError("confidence must be in [0, 1]")

    @staticmethod
    def unknown_value() -> Mapping[str, bool]:
        return {"unknown": True}

    @staticmethod
    def absent_value() -> Mapping[str, bool]:
        return {"absent": True}


@dataclass(frozen=True)
class RecordPlacement:
    record_key: str
    scheme_entry_id: str
    printed_number: Optional[str]
    generation_local: Optional[int]
    generation_global: Optional[int]
    generation_label_raw: Optional[str]
    kuld_label: Optional[str]
    header_observation_id: Optional[str]

    def validate(self) -> None:
        _require(self.record_key, "record_key")
        _require(self.scheme_entry_id, "scheme_entry_id")
        _require(self.header_observation_id, "header_observation_id")


def mint_record_key() -> str:
    """Mint an opaque source-record key without using names or layout locators."""
    return "record-" + str(uuid.uuid4())


def _span_from_dict(value: Mapping[str, Any], source_text: str) -> SourceSpan:
    return SourceSpan(
        rendition_id=value["rendition_id"],
        page_from=value["page_from"],
        page_to=value["page_to"],
        column_label=value.get("column_label"),
        char_from=value["char_from"],
        char_to=value["char_to"],
        source_text=source_text,
        bbox=tuple(value["bbox"]) if value.get("bbox") is not None else None,
    )


def _as_occurrence(value: Union[RecordOccurrence, Mapping[str, Any]]) -> RecordOccurrence:
    if isinstance(value, RecordOccurrence):
        return value
    text = value["verbatim_text"]
    return RecordOccurrence(
        occurrence_id=value["occurrence_id"],
        rendition_id=value["rendition_id"],
        extraction_run_id=value["extraction_run_id"],
        span=_span_from_dict(value["span"], text),
        verbatim_text=text,
    )


def _as_observation(value: Union[Observation, Mapping[str, Any]]) -> Observation:
    if isinstance(value, Observation):
        return value
    text = value["verbatim_text"]
    return Observation(
        observation_id=value["observation_id"],
        occurrence_id=value["occurrence_id"],
        kind=value["kind"],
        verbatim_text=text,
        span=_span_from_dict(value["span"], text),
        extraction_method=value["extraction_method"],
        extraction_run_id=value["extraction_run_id"],
    )


def _as_anchor(value: Union[RecordAnchorEvent, Mapping[str, Any]]) -> RecordAnchorEvent:
    if isinstance(value, RecordAnchorEvent):
        return value
    return RecordAnchorEvent(
        event_id=value["event_id"],
        occurrence_id=value["occurrence_id"],
        source_record_id=value["source_record_id"],
        decision_status=value["decision_status"],
        version=value["version"],
    )


def _as_revision(value: Union[RevisionEvent, Mapping[str, Any]]) -> RevisionEvent:
    if isinstance(value, RevisionEvent):
        return value
    return RevisionEvent(
        event_id=value["event_id"],
        predecessor_record_id=value["predecessor_record_id"],
        successor_record_id=value["successor_record_id"],
        relation_kind=value["relation_kind"],
        decision_status=value["decision_status"],
        version=value["version"],
        reviewed_by=value.get("reviewed_by"),
    )


def _as_interpretation(value: Union[Interpretation, Mapping[str, Any]]) -> Interpretation:
    if isinstance(value, Interpretation):
        return value
    return Interpretation(
        interpretation_id=value["interpretation_id"],
        observation_ids=tuple(value["observation_ids"]),
        predicate=value["predicate"],
        value=value.get("value"),
        status=value["status"],
        method=value["method"],
        confidence=value.get("confidence"),
    )


def validate_bundle(bundle: Union[Path, Mapping[str, Any]]) -> None:
    """Validate internal cross-references without requiring an accepted anchor."""
    if isinstance(bundle, Path):
        with bundle.open(encoding="utf-8") as handle:
            bundle = json.load(handle)
    if not isinstance(bundle, Mapping):
        raise ContractError("evidence bundle must be an object")
    required_fields = {
        "schema_version", "source_rendition", "source_records",
        "source_record_occurrences", "source_record_anchor_events",
        "source_record_revision_events", "record_placements",
        "persona_placements", "observations", "text_variants", "mentions",
        "source_personas", "extraction_run",
    }
    allowed_fields = required_fields | {"interpretations"}
    unknown_fields = set(bundle) - allowed_fields
    if unknown_fields:
        raise ContractError("unknown evidence bundle fields: %s" % ", ".join(sorted(unknown_fields)))
    missing_fields = required_fields - set(bundle)
    if missing_fields:
        raise ContractError("missing evidence bundle fields: %s" % ", ".join(sorted(missing_fields)))
    if bundle.get("schema_version") != "1.0":
        raise ContractError("unsupported schema version")

    occurrences = [_as_occurrence(value) for value in bundle["source_record_occurrences"]]
    observations = [_as_observation(value) for value in bundle.get("observations", ())]
    anchors = [_as_anchor(value) for value in bundle["source_record_anchor_events"]]
    revisions = [_as_revision(value) for value in bundle["source_record_revision_events"]]
    interpretations = [_as_interpretation(value) for value in bundle.get("interpretations", ())]

    occurrence_ids = set()
    for item in occurrences:
        item.validate()
        if item.occurrence_id in occurrence_ids:
            raise ContractError("duplicate occurrence id")
        occurrence_ids.add(item.occurrence_id)

    observation_ids = set()
    for item in observations:
        item.validate()
        if item.occurrence_id not in occurrence_ids:
            raise ContractError("observation references an unknown occurrence")
        if item.observation_id in observation_ids:
            raise ContractError("duplicate observation id")
        observation_ids.add(item.observation_id)

    accepted_by_occurrence = {}
    for item in anchors:
        item.validate()
        if item.occurrence_id not in occurrence_ids:
            raise ContractError("anchor references an unknown occurrence")
        if item.decision_status == "accepted":
            previous = accepted_by_occurrence.setdefault(item.occurrence_id, item.source_record_id)
            if previous != item.source_record_id:
                raise ContractError("an occurrence has more than one accepted anchor")

    for item in revisions:
        item.validate()

    for item in interpretations:
        item.validate()
        if any(observation_id not in observation_ids for observation_id in item.observation_ids):
            raise ContractError("interpretation references an unknown observation")
