"""Edition-neutral, fail-closed contracts for extracted source evidence."""

from __future__ import annotations

import hashlib
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
    parent_observation_id: Optional[str] = None
    clause_ordinal: Optional[int] = None
    clause_classification: Optional[str] = None
    clause_flags: Tuple[str, ...] = ()

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
        is_clause = self.kind == "clause"
        has_clause_fields = any([self.parent_observation_id, self.clause_ordinal is not None,
                                 self.clause_classification, self.clause_flags])
        if not is_clause and has_clause_fields:
            raise ContractError("clause fields are only allowed on kind clause")
        if not is_clause:
            return
        if not (self.parent_observation_id and self.clause_ordinal is not None
                and self.clause_classification is not None and self.clause_flags is not None):
            raise ContractError("clause requires parent, ordinal, classification and flags")
        if self.clause_classification not in ("record_text", "structural_header"):
            raise ContractError("unknown clause classification")
        # bool er en int-subklasse i Python; True ville ellers passere som ordinal 1.
        if isinstance(self.clause_ordinal, bool) or not isinstance(self.clause_ordinal, int) \
                or self.clause_ordinal < 1:
            raise ContractError("clause ordinal must be a positive integer")
        if any(not isinstance(flag, str) or not flag.strip() for flag in self.clause_flags):
            raise ContractError("clause flags must be non-empty strings")
        # Spec 4.1.2: klausulen bæres af den versionerede segmenteringsregel — samme
        # krav som trg_source_observation_clause håndhæver i databasen.
        if not self.extraction_method.startswith("clause_segment_v1"):
            raise ContractError("clause extraction_method must be the versioned clause_segment_v1 rule")


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


def _exact_fields(value: Mapping[str, Any], allowed: set[str], label: str) -> None:
    unknown = set(value) - allowed
    if unknown:
        raise ContractError("unknown %s fields: %s" % (label, ", ".join(sorted(unknown))))


def _exact_fields_subset(value: Mapping[str, Any], allowed: set[str],
                         required: set[str], label: str) -> None:
    _exact_fields(value, allowed, label)
    missing = required - set(value)
    if missing:
        raise ContractError("missing %s fields: %s" % (label, ", ".join(sorted(missing))))


def _mapping(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ContractError("%s must be an object" % label)
    return value


def _span_from_dict(value: Mapping[str, Any], source_text: str, *, strict: bool = False) -> SourceSpan:
    if strict:
        _exact_fields(value, {
            "rendition_id", "page_from", "page_to", "column_label",
            "char_from", "char_to", "bbox",
        }, "span")
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


def _as_occurrence(value: Union[RecordOccurrence, Mapping[str, Any]],
                   rendition_texts: Optional[Mapping[str, str]] = None) -> RecordOccurrence:
    if isinstance(value, RecordOccurrence):
        return value
    strict = rendition_texts is not None
    if strict:
        _exact_fields(value, {
            "occurrence_id", "rendition_id", "extraction_run_id", "span", "verbatim_text",
        }, "source record occurrence")
    text = value["verbatim_text"]
    span_value = _mapping(value["span"], "occurrence span")
    source_text = text
    if strict:
        rendition_id = _require(span_value.get("rendition_id"), "span rendition_id")
        if rendition_id not in rendition_texts:
            raise ContractError("occurrence references an unknown rendition")
        source_text = rendition_texts[rendition_id]
    return RecordOccurrence(
        occurrence_id=value["occurrence_id"],
        rendition_id=value["rendition_id"],
        extraction_run_id=value["extraction_run_id"],
        span=_span_from_dict(span_value, source_text, strict=strict),
        verbatim_text=text,
    )


def _as_observation(value: Union[Observation, Mapping[str, Any]],
                    rendition_texts: Optional[Mapping[str, str]] = None,
                    schema_version: str = "1.1") -> Observation:
    if isinstance(value, Observation):
        return value
    strict = rendition_texts is not None
    required = {
        "observation_id", "occurrence_id", "kind", "verbatim_text", "span",
        "extraction_method", "extraction_run_id",
    }
    allowed = set(required)
    if schema_version == "1.2":
        allowed |= {"parent_observation_id", "clause_ordinal",
                    "clause_classification", "clause_flags"}
    if strict:
        _exact_fields_subset(value, allowed, required, "observation")
    text = value["verbatim_text"]
    span_value = _mapping(value["span"], "observation span")
    source_text = text
    if strict:
        rendition_id = _require(span_value.get("rendition_id"), "span rendition_id")
        if rendition_id not in rendition_texts:
            raise ContractError("observation references an unknown rendition")
        source_text = rendition_texts[rendition_id]
    return Observation(
        observation_id=value["observation_id"],
        occurrence_id=value["occurrence_id"],
        kind=value["kind"],
        verbatim_text=text,
        span=_span_from_dict(span_value, source_text, strict=strict),
        extraction_method=value["extraction_method"],
        extraction_run_id=value["extraction_run_id"],
        parent_observation_id=value.get("parent_observation_id"),
        clause_ordinal=value.get("clause_ordinal"),
        clause_classification=value.get("clause_classification"),
        clause_flags=(tuple(value["clause_flags"]) if isinstance(value.get("clause_flags"), (list, tuple))
                      else value.get("clause_flags")),
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


def _strict_renditions(bundle: Mapping[str, Any]) -> tuple[dict[str, str], dict[str, str]]:
    texts: dict[str, str] = {}
    sources: dict[str, str] = {}
    for raw_value in bundle["source_rendition"]:
        raw = _mapping(raw_value, "source rendition")
        _exact_fields(raw, {"rendition_id", "source_id", "sha256", "verbatim_text"}, "source rendition")
        rendition_id = _require(raw.get("rendition_id"), "rendition_id")
        source_id = _require(raw.get("source_id"), "source_id")
        rendition_text = _require(raw.get("verbatim_text"), "rendition verbatim_text")
        digest = _require(raw.get("sha256"), "rendition sha256").lower()
        if hashlib.sha256(rendition_text.encode("utf-8")).hexdigest() != digest:
            raise ContractError("rendition sha256 does not match verbatim_text")
        if rendition_id in texts:
            raise ContractError("duplicate rendition id")
        texts[rendition_id] = rendition_text
        sources[rendition_id] = source_id
    return texts, sources


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
    schema_version = bundle.get("schema_version")
    if schema_version not in ("1.0", "1.1", "1.2"):
        raise ContractError("unsupported schema version")

    strict = schema_version in ("1.1", "1.2")
    rendition_texts: Optional[Mapping[str, str]] = None
    rendition_sources: Mapping[str, str] = {}
    if strict:
        rendition_texts, rendition_sources = _strict_renditions(bundle)
        extraction_run = _mapping(bundle["extraction_run"], "extraction run")
        _exact_fields(extraction_run, {
            "run_id", "source_id", "schema_version", "extractor_version",
            "profile_version", "input_sha256", "manifest",
        }, "extraction run")
        extraction_run_id = _require(extraction_run.get("run_id"), "extraction run_id")
    else:
        extraction_run_id = str(bundle.get("extraction_run", {}).get("run_id", ""))

    if strict:
        for raw_value in bundle["source_record_anchor_events"]:
            _exact_fields(_mapping(raw_value, "anchor event"), {
                "event_id", "occurrence_id", "source_record_id", "decision_status", "version",
            }, "anchor event")
        for raw_value in bundle["source_record_revision_events"]:
            _exact_fields(_mapping(raw_value, "revision event"), {
                "event_id", "predecessor_record_id", "successor_record_id", "relation_kind",
                "decision_status", "version", "reviewed_by",
            }, "revision event")
        for raw_value in bundle.get("interpretations", ()):
            _exact_fields(_mapping(raw_value, "interpretation"), {
                "interpretation_id", "observation_ids", "predicate", "value", "status",
                "method", "confidence",
            }, "interpretation")

    occurrences = [_as_occurrence(value, rendition_texts) for value in bundle["source_record_occurrences"]]
    observations = [_as_observation(value, rendition_texts, schema_version)
                    for value in bundle.get("observations", ())]
    anchors = [_as_anchor(value) for value in bundle["source_record_anchor_events"]]
    revisions = [_as_revision(value) for value in bundle["source_record_revision_events"]]
    interpretations = [_as_interpretation(value) for value in bundle.get("interpretations", ())]

    occurrence_ids = set()
    occurrence_by_id = {}
    for item in occurrences:
        item.validate()
        if strict:
            if item.extraction_run_id != extraction_run_id:
                raise ContractError("occurrence extraction run differs from bundle")
            source_slice = item.span.source_text[item.span.char_from:item.span.char_to]
            if source_slice != item.verbatim_text:
                raise ContractError("occurrence verbatim_text must exactly equal the rendition span")
        if item.occurrence_id in occurrence_ids:
            raise ContractError("duplicate occurrence id")
        occurrence_ids.add(item.occurrence_id)
        occurrence_by_id[item.occurrence_id] = item

    source_record_ids = set()
    source_record_keys = set()
    source_record_source = {}
    for value in bundle["source_records"]:
        value = _mapping(value, "source record")
        if strict:
            _exact_fields(value, {"id", "record_key", "source_id"}, "source record")
        record_id = _require(value.get("id"), "source record id")
        record_key = _require(value.get("record_key"), "source record key")
        if strict:
            source_record_source[record_id] = _require(value.get("source_id"), "source record source_id")
        if record_id in source_record_ids:
            raise ContractError("duplicate source record id")
        if record_key in source_record_keys:
            raise ContractError("duplicate source record key")
        source_record_ids.add(record_id)
        source_record_keys.add(record_key)

    observation_ids = set()
    observation_by_id = {}
    for item in observations:
        item.validate()
        if item.occurrence_id not in occurrence_ids:
            raise ContractError("observation references an unknown occurrence")
        if strict:
            parent = occurrence_by_id[item.occurrence_id]
            if item.extraction_run_id != extraction_run_id or item.extraction_run_id != parent.extraction_run_id:
                raise ContractError("observation extraction run differs from its occurrence")
            if (item.span.rendition_id != parent.span.rendition_id
                    or item.span.char_from < parent.span.char_from
                    or item.span.char_to > parent.span.char_to):
                raise ContractError("observation span must be inside its occurrence")
        if item.observation_id in observation_ids:
            raise ContractError("duplicate observation id")
        observation_ids.add(item.observation_id)
        observation_by_id[item.observation_id] = item

    if schema_version == "1.2":
        seen_ordinals = set()
        for item in observations:
            if item.kind != "clause":
                continue
            # Databasen har et unikt indeks på (parent_observation_id, clause_ordinal).
            ordinal_key = (item.parent_observation_id, item.clause_ordinal)
            if ordinal_key in seen_ordinals:
                raise ContractError("duplicate clause ordinal under parent")
            seen_ordinals.add(ordinal_key)
            parent = observation_by_id.get(item.parent_observation_id or "")
            if parent is None:
                raise ContractError("clause requires parent")
            if parent.kind == "clause" or parent.parent_observation_id:
                raise ContractError("parent observation must be top level")
            if parent.occurrence_id != item.occurrence_id:
                raise ContractError("clause occurrence differs from parent")
            if item.span.char_from < parent.span.char_from or item.span.char_to > parent.span.char_to:
                raise ContractError("clause span outside parent")
            # Sider er grænser, ikke en påstand om præcis side (spec 4.1.2): klausulen
            # arver forælderens sideinterval uændret, som trg_source_observation_clause
            # håndhæver i databasen.
            if (item.span.page_from != parent.span.page_from
                    or item.span.page_to != parent.span.page_to):
                raise ContractError("clause pages must equal parent pages")
            start = item.span.char_from - parent.span.char_from
            length = item.span.char_to - item.span.char_from
            if parent.verbatim_text[start:start + length] != item.verbatim_text:
                raise ContractError("clause verbatim_text must equal the parent slice")
    elif any(item.parent_observation_id for item in observations):
        raise ContractError("clause fields require schema version 1.2")

    accepted_by_occurrence = {}
    for item in anchors:
        item.validate()
        if item.occurrence_id not in occurrence_ids:
            raise ContractError("anchor references an unknown occurrence")
        if item.source_record_id not in source_record_ids:
            raise ContractError("anchor references an unknown source record")
        if strict:
            occurrence = occurrence_by_id[item.occurrence_id]
            occurrence_source = rendition_sources[occurrence.rendition_id]
            if source_record_source[item.source_record_id] != occurrence_source:
                raise ContractError("anchor source record differs from occurrence source")
        if item.decision_status == "accepted":
            previous = accepted_by_occurrence.setdefault(item.occurrence_id, item.source_record_id)
            if previous != item.source_record_id:
                raise ContractError("an occurrence has more than one accepted anchor")

    for item in revisions:
        item.validate()
        if strict and (item.predecessor_record_id not in source_record_ids
                       or item.successor_record_id not in source_record_ids):
            raise ContractError("revision references an unknown source record")

    for item in interpretations:
        item.validate()
        if any(observation_id not in observation_ids for observation_id in item.observation_ids):
            raise ContractError("interpretation references an unknown observation")

    if not strict:
        return

    mention_ids = set()
    mention_observation = {}
    for raw_value in bundle["mentions"]:
        raw = _mapping(raw_value, "mention")
        _exact_fields(raw, {
            "mention_id", "observation_id", "char_from", "char_to", "verbatim_text",
            "mention_kind", "created_run_id",
        }, "mention")
        mention = Mention(
            mention_id=raw["mention_id"], observation_id=raw["observation_id"],
            char_from=raw["char_from"], char_to=raw["char_to"], verbatim_text=raw["verbatim_text"],
        )
        if mention.observation_id not in observation_by_id:
            raise ContractError("mention references an unknown observation")
        mention.validate_against(observation_by_id[mention.observation_id])
        if mention.mention_id in mention_ids:
            raise ContractError("duplicate mention id")
        mention_ids.add(mention.mention_id)
        mention_observation[mention.mention_id] = mention.observation_id

    persona_ids = set()
    for raw_value in bundle["source_personas"]:
        raw = _mapping(raw_value, "source persona")
        _exact_fields(raw, {
            "persona_id", "source_id", "mention_ids", "persona_key", "created_run_id",
        }, "source persona")
        persona_id = _require(raw.get("persona_id"), "persona_id")
        source_id = _require(raw.get("source_id"), "source persona source_id")
        raw_mention_ids = raw.get("mention_ids")
        if not isinstance(raw_mention_ids, list) or not raw_mention_ids:
            raise ContractError("source persona requires at least one mention")
        if any(not isinstance(value, str) or value not in mention_ids for value in raw_mention_ids):
            raise ContractError("source persona references an unknown mention")
        for mention_id in raw_mention_ids:
            observation = observation_by_id[mention_observation[mention_id]]
            occurrence = occurrence_by_id[observation.occurrence_id]
            if rendition_sources[occurrence.rendition_id] != source_id:
                raise ContractError("source persona must be scoped to one source edition")
        if persona_id in persona_ids:
            raise ContractError("duplicate source persona id")
        persona_ids.add(persona_id)

    for raw_value in bundle["record_placements"]:
        raw = _mapping(raw_value, "record placement")
        _exact_fields(raw, {
            "record_key", "scheme_entry_id", "printed_number", "generation_local",
            "generation_global", "generation_label_raw", "kuld_label",
            "header_observation_id", "section_path", "status", "placement_id",
            "supersedes_placement_id",
        }, "record placement")
        placement = RecordPlacement(
            record_key=raw["record_key"], scheme_entry_id=raw["scheme_entry_id"],
            printed_number=raw.get("printed_number"), generation_local=raw.get("generation_local"),
            generation_global=raw.get("generation_global"),
            generation_label_raw=raw.get("generation_label_raw"), kuld_label=raw.get("kuld_label"),
            header_observation_id=raw.get("header_observation_id"),
        )
        placement.validate()
        if placement.record_key not in source_record_keys:
            raise ContractError("record placement references an unknown source record")
        if placement.header_observation_id not in observation_ids:
            raise ContractError("record placement references an unknown header observation")

    for raw_value in bundle["persona_placements"]:
        raw = _mapping(raw_value, "persona placement")
        _exact_fields(raw, {
            "source_persona_id", "record_placement_id", "placement_role",
            "basis_observation_id", "status",
        }, "persona placement")
        if _require(raw.get("source_persona_id"), "placement source_persona_id") not in persona_ids:
            raise ContractError("persona placement references an unknown source persona")
        if _require(raw.get("basis_observation_id"), "placement basis_observation_id") not in observation_ids:
            raise ContractError("persona placement references an unknown observation")

    for raw_value in bundle["text_variants"]:
        raw = _mapping(raw_value, "text variant")
        _exact_fields(raw, {
            "text_variant_id", "id", "observation_id", "rendition_id", "version",
            "verbatim_text", "char_from", "char_to", "bbox", "is_preferred",
            "supersedes_id",
        }, "text variant")
        observation_id = _require(raw.get("observation_id"), "text variant observation_id")
        rendition_id = _require(raw.get("rendition_id"), "text variant rendition_id")
        if observation_id not in observation_ids:
            raise ContractError("text variant references an unknown observation")
        if rendition_id not in rendition_texts:
            raise ContractError("text variant references an unknown rendition")
        char_from, char_to = raw.get("char_from"), raw.get("char_to")
        if not isinstance(char_from, int) or not isinstance(char_to, int) or char_from < 0 or char_to <= char_from:
            raise ContractError("text variant character span is invalid")
        verbatim_text = _require(raw.get("verbatim_text"), "text variant verbatim_text")
        if rendition_texts[rendition_id][char_from:char_to] != verbatim_text:
            raise ContractError("text variant must exactly equal the rendition span")
