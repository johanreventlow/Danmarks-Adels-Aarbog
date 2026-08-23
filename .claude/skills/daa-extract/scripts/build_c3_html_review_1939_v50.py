#!/usr/bin/env python3
"""Validér C3-reviewbytes og find de 15 redigerbare tokenintervaller."""

import base64
import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"
CONVERTER_PATH = SCRIPT_DIR / "convert_c3_decisions_1939_v50.py"
APPLY_MANIFEST_PATH = SCRIPT_DIR / "finalize_c3_apply_manifest_1939_v50.py"
APPLY_SHEET_SCHEMA = "1939-v50-c3-apply-approvals-v1"
APPLY_TOKENS = ("UAFKLARET", "GODKENDT")
_APPLY_MANIFEST_TOP_KEYS = {
    "schema_version", "input_hashes", "database", "counts", "cases",
    "canonical_content_sha256"}
_APPLY_INPUT_HASH_KEYS = {
    "candidate_raw_sha256", "preview_raw_sha256",
    "candidate_canonical_content_sha256", "before_state_canonical_sha256"}
_APPLY_DATABASE_KEYS = {"database_name", "system_identifier"}
_APPLY_COUNTS_EXACT = {
    "cases": 5, "identity_events": 5, "assign_events": 4,
    "no_publication_events": 2, "events": 11}
_APPLY_CASE_KEYS = {
    "element_id", "case_id", "after_state", "before_state", "events"}
_APPLY_CASE_AFTER_KEYS = {"action", "person_ids"}
_APPLY_CASE_BEFORE_KEYS = {"component_overlap", "existing_rejection"}
_APPLY_EVENT_KEYS = {
    "element_id", "rid", "record_key", "action", "after_state",
    "before_state"}
_APPLY_ASSIGN_AFTER_KEYS = {
    "target_person_id", "raw_sha256", "normalized_text", "normalized_sha256",
    "normalization_version", "normalization_flags", "expected_narrative"}
_APPLY_EXPECTED_NARRATIVE_KEYS = {
    "privat", "side", "record_label", "citation_label"}
_APPLY_ASSIGN_BEFORE_KEYS = {"source_record", "binding", "target_narrative"}
_APPLY_NOPUB_BEFORE_KEYS = {"source_record", "binding"}
_APPLY_SOURCE_RECORD_KEYS = {"match_count", "verbatim_sha256", "side"}
_APPLY_BINDING_KEYS = {"status", "binding_person_id"}
_APPLY_TARGET_NARRATIVE_KEYS = {
    "person_id", "narrative_id", "privat", "old_sha256"}
_APPLY_BINDING_STATUSES = {
    "absent", "draft_same_record", "draft_other_record", "published",
    "withdrawn"}
HASH_KEYS = {
    "c0_candidates_sha256",
    "c0_decisions_sha256",
    "selection_sha256",
    "state_sha256",
    "review_sha256",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CLI_ERROR_RE = re.compile(r"^C3_HTML_[A-Z0-9_]+$")
VOCABULARY = {
    "identity_actions": ["UAFKLARET", "FORSKELLIGE", "SAMME"],
    "record_actions": [
        "UAFKLARET", "TIL", "INGEN_PUBLIKATION", "REVISION"],
    "revision_kinds": ["split_into", "merged_from", "replaced_by"],
}


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("missing loader")
    spec.loader.exec_module(module)
    return module


build = _load_module("build_c3_review_1939_v50_for_html", BUILD_PATH)
converter = _load_module(
    "convert_c3_decisions_1939_v50_for_html", CONVERTER_PATH)
apply_manifest = _load_module(
    "finalize_c3_apply_manifest_1939_v50_for_html", APPLY_MANIFEST_PATH)


@dataclass(frozen=True)
class DecisionSlot:
    decision_id: str
    case_id: str
    decision_type: str
    start: int
    end: int
    default_token: str
    allowed_person_ids: Tuple[int, ...]
    preferred_alias_person_id: Optional[int] = None
    preferred_canonical_person_id: Optional[int] = None


def fail(code: str) -> None:
    raise SystemExit(code)


def _valid_hashes(input_hashes: Any) -> bool:
    return (
        isinstance(input_hashes, Mapping)
        and set(input_hashes) == HASH_KEYS
        and all(isinstance(value, str)
                and SHA256_RE.fullmatch(value) is not None
                for value in input_hashes.values())
    )


def _decode_document(raw: bytes) -> Dict[str, Any]:
    def reject_nonfinite(_value: str) -> None:
        raise ValueError("non-finite JSON number")

    try:
        document = json.loads(
            raw.decode("utf-8"), parse_constant=reject_nonfinite)
    except (UnicodeDecodeError, ValueError):
        fail("C3_HTML_REVIEW_INVALID")
    if not isinstance(document, dict):
        fail("C3_HTML_REVIEW_INVALID")
    return document


def _map_review_error(error: SystemExit) -> None:
    token = str(error).split(":", 1)[0]
    if token in {
            "C3_REVIEW_HASH_INVALID",
            "C3_REVIEW_HASH_MISMATCH",
            "C3_REVIEW_SELECTION_HASH_INVALID",
            "C3_REVIEW_SELECTION_HASH_MISMATCH"}:
        fail("C3_HTML_HASH_MISMATCH")
    if token == "C3_REVIEW_COUNT_INVALID":
        fail("C3_HTML_COUNT_INVALID")
    if token in {
            "C3_REVIEW_SPECIAL_INVALID",
            "C3_REVIEW_R15_INVALID",
            "C3_REVIEW_R40_INVALID"}:
        fail("C3_HTML_SPECIAL_INVALID")
    fail("C3_HTML_REVIEW_INVALID")


def _validated_sequence(selection_doc: Mapping[str, Any],
                        state_doc: Mapping[str, Any]
                        ) -> List[Dict[str, Any]]:
    try:
        sequence = build.review_sequence(selection_doc, state_doc)
    except SystemExit as error:
        _map_review_error(error)
        raise AssertionError("unreachable")
    if not isinstance(sequence, list):
        fail("C3_HTML_REVIEW_INVALID")
    return sequence


def _validate_locked_counts(selection_doc: Mapping[str, Any]) -> None:
    expected = {
        "case_count": 7,
        "record_count": 8,
        "decision_line_count": 15,
    }
    if any(type(selection_doc.get(field)) is not int
           or selection_doc.get(field) != value
           for field, value in expected.items()):
        fail("C3_HTML_COUNT_INVALID")
    cases = selection_doc.get("cases")
    if not isinstance(cases, list):
        fail("C3_HTML_REVIEW_INVALID")
    if len(cases) != 7:
        fail("C3_HTML_COUNT_INVALID")
    record_count = 0
    for case in cases:
        if not isinstance(case, Mapping) or not isinstance(
                case.get("records"), list):
            fail("C3_HTML_REVIEW_INVALID")
        record_count += len(case["records"])
    if record_count != 8:
        fail("C3_HTML_COUNT_INVALID")


def _case_id(decision_id: str) -> str:
    if decision_id == "identity:1017:1021" or decision_id in {
            "record:R40", "record:R15"}:
        return "1017/1021"
    parts = decision_id.split(":")
    if len(parts) != 2 or not parts[1]:
        fail("C3_HTML_REVIEW_INVALID")
    return parts[1]


def _validate_slot_contract(review_bytes: bytes,
                            slots: Sequence[DecisionSlot]) -> None:
    decision_ids = [slot.decision_id for slot in slots]
    if len(set(decision_ids)) != len(decision_ids):
        fail("C3_HTML_DECISION_DUPLICATE")
    previous_end = 0
    for slot in slots:
        preferred_alias = slot.preferred_alias_person_id
        preferred_canonical = slot.preferred_canonical_person_id
        preferred_present = (preferred_alias is not None
                             or preferred_canonical is not None)
        if (
                not isinstance(slot.decision_id, str)
                or not slot.decision_id
                or not isinstance(slot.case_id, str)
                or not slot.case_id
                or slot.decision_type not in {"identity", "record"}
                or type(slot.start) is not int
                or type(slot.end) is not int
                or slot.start < previous_end
                or slot.start < 0
                or slot.end <= slot.start
                or slot.end > len(review_bytes)
                or not isinstance(slot.default_token, str)
                or not slot.default_token
                or not isinstance(slot.allowed_person_ids, tuple)
                or not slot.allowed_person_ids
                or tuple(sorted(set(slot.allowed_person_ids)))
                != slot.allowed_person_ids
                or any(type(person_id) is not int or person_id <= 0
                       for person_id in slot.allowed_person_ids)
                or (slot.decision_id == "identity:1017:1021"
                    and not preferred_present)
                or (preferred_present and (
                    slot.decision_type != "identity"
                    or type(preferred_alias) is not int
                    or type(preferred_canonical) is not int
                    or preferred_alias == preferred_canonical
                    or preferred_alias not in slot.allowed_person_ids
                    or preferred_canonical not in slot.allowed_person_ids))):
            fail("C3_HTML_SLOT_INVALID")
        expected = slot.default_token.encode("utf-8")
        if review_bytes[slot.start:slot.end] != expected:
            fail("C3_HTML_SLOT_INVALID")
        try:
            review_bytes[:slot.start].decode("utf-8")
            review_bytes[:slot.end].decode("utf-8")
        except UnicodeDecodeError:
            fail("C3_HTML_SLOT_INVALID")
        previous_end = slot.end


def _discover_slots(review_bytes: bytes,
                    selection_bytes: bytes,
                    state_bytes: bytes,
                    input_hashes: Mapping[str, str]) -> List[DecisionSlot]:
    if not _valid_hashes(input_hashes):
        fail("C3_HTML_HASH_MISMATCH")
    if (not isinstance(review_bytes, bytes)
            or not isinstance(selection_bytes, bytes)
            or not isinstance(state_bytes, bytes)):
        fail("C3_HTML_REVIEW_INVALID")
    exact_inputs = (
        (review_bytes, "review_sha256"),
        (selection_bytes, "selection_sha256"),
        (state_bytes, "state_sha256"),
    )
    if any(hashlib.sha256(raw).hexdigest() != input_hashes[hash_name]
           for raw, hash_name in exact_inputs):
        fail("C3_HTML_HASH_MISMATCH")
    selection_doc = _decode_document(selection_bytes)
    state_doc = _decode_document(state_bytes)
    selection_hashes = selection_doc.get("input_hashes")
    if selection_hashes != {
            "c0_candidates_sha256": input_hashes["c0_candidates_sha256"],
            "c0_decisions_sha256": input_hashes["c0_decisions_sha256"]}:
        fail("C3_HTML_HASH_MISMATCH")
    if state_doc.get("selection_sha256") != input_hashes[
            "selection_sha256"]:
        fail("C3_HTML_HASH_MISMATCH")
    _validate_locked_counts(selection_doc)
    try:
        review_text = review_bytes.decode("utf-8")
    except UnicodeDecodeError:
        fail("C3_HTML_REVIEW_INVALID")

    sequence = _validated_sequence(selection_doc, state_doc)
    try:
        parsed = converter.parse_review(
            review_text, selection_doc, state_doc, dict(input_hashes))
    except SystemExit as error:
        _map_review_error(error)
        raise AssertionError("unreachable")
    if parsed.get("counts") != {
            "cases": 7,
            "records": 8,
            "decision_lines": 15,
            "unresolved": 13}:
        fail("C3_HTML_COUNT_INVALID")

    header = build.HEADER.format(
        selection_sha256=input_hashes["selection_sha256"],
        state_sha256=input_hashes["state_sha256"]) + "\n"
    lines = review_text.splitlines(keepends=True)
    header_line_count = len(header.splitlines(keepends=True))
    line_offsets: List[int] = []
    byte_offset = 0
    for line in lines:
        line_offsets.append(byte_offset)
        byte_offset += len(line.encode("utf-8"))

    slots: List[DecisionSlot] = []
    for position, item in enumerate(sequence):
        if item.get("type") == "heading":
            continue
        line_index = header_line_count + position
        if line_index >= len(lines):
            fail("C3_HTML_REVIEW_INVALID")
        default_token = item.get("default_token")
        tail = item.get("tail")
        decision_id = item.get("decision_id")
        allowed_ids = item.get("allowed_person_ids")
        preferred_alias = item.get("preferred_alias_person_id")
        preferred_canonical = item.get("preferred_canonical_person_id")
        if (
                item.get("type") not in {"identity", "record"}
                or not isinstance(default_token, str)
                or not isinstance(tail, str)
                or not isinstance(decision_id, str)
                or not isinstance(allowed_ids, list)):
            fail("C3_HTML_REVIEW_INVALID")
        expected_line = "[{}] {}\n".format(default_token, tail)
        if lines[line_index] != expected_line:
            fail("C3_HTML_SLOT_INVALID")
        start = line_offsets[line_index] + len("[".encode("utf-8"))
        end = start + len(default_token.encode("utf-8"))
        slots.append(DecisionSlot(
            decision_id=decision_id,
            case_id=_case_id(decision_id),
            decision_type=item["type"],
            start=start,
            end=end,
            default_token=default_token,
            allowed_person_ids=tuple(allowed_ids),
            preferred_alias_person_id=preferred_alias,
            preferred_canonical_person_id=preferred_canonical,
        ))
    if len(slots) != 15:
        fail("C3_HTML_COUNT_INVALID")
    _validate_slot_contract(review_bytes, slots)
    return slots


def decision_slots(review_bytes: bytes,
                   selection_bytes: bytes,
                   state_bytes: bytes,
                   input_hashes: Mapping[str, str]) -> List[Dict[str, Any]]:
    """Validér rå inputbytes og returnér JSON-sikre tokenintervaller."""
    slots = _discover_slots(
        review_bytes, selection_bytes, state_bytes, input_hashes)
    return [
        {
            "decision_id": slot.decision_id,
            "case_id": slot.case_id,
            "decision_type": slot.decision_type,
            "start": slot.start,
            "end": slot.end,
            "default_token": slot.default_token,
            "allowed_person_ids": list(slot.allowed_person_ids),
            "preferred_alias_person_id": slot.preferred_alias_person_id,
            "preferred_canonical_person_id": (
                slot.preferred_canonical_person_id),
        }
        for slot in slots
    ]


def _case_context(case: Mapping[str, Any], state_doc: Mapping[str, Any],
                  slots: Sequence[DecisionSlot]) -> Dict[str, Any]:
    if case.get("case_kind") == "1017_1021":
        case_id = "1017/1021"
    else:
        records = case.get("records")
        if not isinstance(records, list) or len(records) != 1:
            fail("C3_HTML_PAYLOAD_INVALID")
        case_id = records[0].get("rid")
    if not isinstance(case_id, str) or not case_id:
        fail("C3_HTML_PAYLOAD_INVALID")
    allowed_ids = case.get("candidate_person_ids")
    if not isinstance(allowed_ids, list):
        fail("C3_HTML_PAYLOAD_INVALID")
    allowed = set(allowed_ids)
    controls = [
        {
            "decision_id": slot.decision_id,
            "decision_type": slot.decision_type,
            "default_token": slot.default_token,
            "allowed_person_ids": list(slot.allowed_person_ids),
            "preferred_alias_person_id": slot.preferred_alias_person_id,
            "preferred_canonical_person_id": (
                slot.preferred_canonical_person_id),
            "start": slot.start,
            "end": slot.end,
        }
        for slot in slots if slot.case_id == case_id
    ]
    persons = [row for row in state_doc["persons"]
               if row["person_id"] in allowed]
    narratives = [row for row in state_doc["narratives"]
                  if row["person_id"] in allowed]
    edges = [row for row in state_doc["identity_edges"]
             if row["subject_id"] in allowed or row["object_id"] in allowed]
    conflicts = [row for row in state_doc["partner_conflicts"]
                 if row["left_person_id"] in allowed
                 or row["right_person_id"] in allowed]
    return {
        "case_id": case_id,
        "case_kind": case["case_kind"],
        "candidate_person_ids": list(allowed_ids),
        "records": list(case["records"]),
        "persons": persons,
        "narratives": narratives,
        "identity_edges": edges,
        "partner_conflicts": conflicts,
        "controls": controls,
    }


def _slot_dict(slot: DecisionSlot) -> Dict[str, Any]:
    return {
        "decision_id": slot.decision_id,
        "case_id": slot.case_id,
        "decision_type": slot.decision_type,
        "start": slot.start,
        "end": slot.end,
        "default_token": slot.default_token,
        "allowed_person_ids": list(slot.allowed_person_ids),
        "preferred_alias_person_id": slot.preferred_alias_person_id,
        "preferred_canonical_person_id": slot.preferred_canonical_person_id,
    }


def build_payload(selection_bytes: bytes, state_bytes: bytes,
                  review_bytes: bytes,
                  input_hashes: Mapping[str, str]) -> Dict[str, Any]:
    """Byg den validerede browser-view-model fra eksakte inputbytes."""
    slots = _discover_slots(
        review_bytes, selection_bytes, state_bytes, input_hashes)
    selection_doc = _decode_document(selection_bytes)
    state_doc = _decode_document(state_bytes)
    cases = [
        _case_context(case, state_doc, slots)
        for case in selection_doc["cases"]
    ]
    if ([len(case["controls"]) for case in cases]
            != [2, 2, 2, 2, 2, 2, 3]):
        fail("C3_HTML_COUNT_INVALID")
    return {
        "schema_version": "1939-v50-c3-html-payload-v1",
        "input_hashes": dict(input_hashes),
        "counts": {"cases": 7, "records": 8, "decisions": 15},
        "vocabulary": {key: list(value)
                       for key, value in VOCABULARY.items()},
        "cases": cases,
        "slots": [_slot_dict(slot) for slot in slots],
    }


CLIENT_SCRIPT = r'''"use strict";

function decodeBase64Url(value) {
  const padded = value + "=".repeat((4 - value.length % 4) % 4);
  const binary = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function encodeBase64Url(bytes) {
  let binary = "";
  for (let index = 0; index < bytes.length; index += 1) {
    binary += String.fromCharCode(bytes[index]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_");
}

function replaceTokenBytes(sourceBytes, replacements) {
  const encoder = new TextEncoder();
  const ordered = replacements.slice().sort((left, right) => right.start - left.start);
  let result = sourceBytes.slice();
  for (const replacement of ordered) {
    if (!Number.isInteger(replacement.start) || !Number.isInteger(replacement.end) ||
        replacement.start < 0 || replacement.end <= replacement.start ||
        replacement.end > sourceBytes.length || typeof replacement.token !== "string") {
      throw new Error("C3_HTML_EXPORT_INVALID");
    }
    const tokenBytes = encoder.encode(replacement.token);
    const next = new Uint8Array(
      replacement.start + tokenBytes.length + result.length - replacement.end);
    next.set(result.slice(0, replacement.start), 0);
    next.set(tokenBytes, replacement.start);
    next.set(result.slice(replacement.end), replacement.start + tokenBytes.length);
    result = next;
  }
  return result;
}

function makeElement(tagName, className, text) {
  const node = document.createElement(tagName);
  if (className) {
    node.className = className;
  }
  if (text !== undefined) {
    node.textContent = text;
  }
  return node;
}

function makeSelect(values, labels, accessibleName) {
  const select = makeElement("select", "choice");
  select.setAttribute("aria-label", accessibleName);
  values.forEach((value, index) => {
    const option = makeElement("option", "", labels ? labels[index] : value);
    option.value = String(value);
    select.append(option);
  });
  return select;
}

function parseDefault(control) {
  const parts = control.default_token.split(" ");
  if (control.decision_type === "identity") {
    if (parts[0] === "SAMME" && parts.length === 3) {
      return {action: "SAMME", alias: parts[1], canonical: parts[2]};
    }
    return {action: control.default_token};
  }
  if (parts[0] === "TIL" && parts.length === 2) {
    return {action: "TIL", person: parts[1]};
  }
  if (parts[0] === "REVISION" && parts.length === 2) {
    return {action: "REVISION", revision: parts[1]};
  }
  return {action: control.default_token};
}

function identityToken(state, control) {
  if (state.action === "UAFKLARET" || state.action === "FORSKELLIGE") {
    return state.action;
  }
  const alias = Number(state.alias);
  const canonical = Number(state.canonical);
  if (state.action !== "SAMME" || alias === canonical ||
      !control.allowed_person_ids.includes(alias) ||
      !control.allowed_person_ids.includes(canonical)) {
    throw new Error("C3_HTML_IDENTITY_INVALID");
  }
  return `SAMME ${alias} ${canonical}`;
}

function recordToken(state, control, vocabulary) {
  if (state.action === "UAFKLARET" || state.action === "INGEN_PUBLIKATION") {
    return state.action;
  }
  if (state.action === "TIL") {
    const person = Number(state.person);
    if (!control.allowed_person_ids.includes(person)) {
      throw new Error("C3_HTML_RECORD_INVALID");
    }
    return `TIL ${person}`;
  }
  if (state.action === "REVISION" && vocabulary.revision_kinds.includes(state.revision)) {
    return `REVISION ${state.revision}`;
  }
  throw new Error("C3_HTML_RECORD_INVALID");
}

function controlToken(state, control, vocabulary) {
  return control.decision_type === "identity"
    ? identityToken(state, control)
    : recordToken(state, control, vocabulary);
}

function readableValue(value) {
  return value === null || value === undefined || value === ""
    ? "Ikke registreret"
    : String(value);
}

function appendLabelledValue(container, label, value, className) {
  const row = makeElement("p", className || "labelled-value");
  row.append(makeElement("strong", "", `${label}: `),
             makeElement("span", "", readableValue(value)));
  container.append(row);
}

function recordPage(record) {
  const pages = record.pages;
  if (!pages || !Number.isInteger(pages.page_from) ||
      !Number.isInteger(pages.page_to) || pages.page_from < 1 ||
      pages.page_to < pages.page_from) {
    return "Ikke registreret";
  }
  return pages.page_from === pages.page_to
    ? String(pages.page_from)
    : `${pages.page_from}–${pages.page_to}`;
}

function classificationLabel(value) {
  const labels = {
    sammenlaegning: "Mulig sammenlægning",
    kobling: "Mulig kobling"
  };
  return labels[value] || readableValue(value);
}

function renderSourceRecord(container, record) {
  const article = makeElement("article", "source-record");
  article.append(makeElement("h3", "", `Kilderecord ${readableValue(record.rid)}`));
  const metadata = makeElement("div", "source-metadata");
  appendLabelledValue(metadata, "Side", recordPage(record));
  appendLabelledValue(metadata, "Vurdering", classificationLabel(record.classification));
  appendLabelledValue(metadata, "Recordnøgle", record.new_record_key);
  article.append(metadata, makeElement("h4", "", "Kildetekst"),
                 makeElement("p", "source-text", readableValue(record.verbatim_text)));
  container.append(article);
}

function bindingLabel(narrative) {
  if (!narrative || narrative.source_record_id === null) {
    return "ingen recordbinding";
  }
  const labels = {
    draft: "kladdebinding",
    published: "publiceret binding",
    withdrawn: "tilbagetrukket binding"
  };
  return labels[narrative.binding_status] || "bindingens status er ikke registreret";
}

function renderCandidate(container, candidate, person, narrative) {
  const article = makeElement("article", "candidate-card");
  article.append(makeElement("h3", "candidate-name",
                             readableValue(candidate && candidate.visning_navn)));
  article.append(makeElement("p", "candidate-id",
                             `Person-ID ${readableValue(candidate && candidate.person_id)}`));
  const badges = makeElement("div", "candidate-badges");
  badges.append(
    makeElement("span", "badge", person && person.staged
      ? "Kladdeperson" : "Eksisterende person"),
    makeElement("span", "badge", person && person.privat
      ? "Privat" : "Offentlig")
  );
  article.append(badges);
  appendLabelledValue(article, "Side", candidate && candidate.side);
  article.append(makeElement("h4", "", "Eksisterende persontekst"),
                 makeElement("p", "candidate-text",
                             readableValue(candidate && candidate.person_tekst)),
                 makeElement("h4", "", "Eksisterende narrativ"));
  if (!narrative) {
    article.append(makeElement("p", "narrative-info", "Ikke registreret"));
  } else {
    article.append(makeElement(
      "p", "narrative-info",
      `Narrativ ${readableValue(narrative.narrative_id)} · side ` +
      `${readableValue(narrative.side)} · ${bindingLabel(narrative)}`));
    if (narrative.source_record_id !== null) {
      appendLabelledValue(article, "Recordbinding", narrative.source_record_id,
                          "binding-id");
    }
  }
  container.append(article);
}

function renderIdentityRelations(container, edges) {
  const section = makeElement("section", "identity-relations");
  section.append(makeElement("h3", "", "Eksisterende identitetsrelationer"));
  if (edges.length === 0) {
    section.append(makeElement(
      "p", "empty-state", "Ingen eksisterende identitetsrelationer registreret."));
  } else {
    const list = makeElement("ul", "relation-list");
    edges.forEach(edge => {
      const sentence = edge.role === "samme_som"
        ? `Person ${edge.subject_id} er registreret som samme person som person ${edge.object_id}.`
        : `Person ${edge.subject_id} er registreret som forskellig fra person ${edge.object_id}.`;
      list.append(makeElement("li", "", sentence));
    });
    section.append(list);
  }
  container.append(section);
}

function renderPartnerConflicts(container, conflicts) {
  const section = makeElement("section", "partner-conflicts");
  section.append(makeElement("h3", "", "Partnerkonflikter"));
  if (conflicts.length === 0) {
    section.append(makeElement("p", "empty-state", "Ingen partnerkonflikter registreret."));
  } else {
    const list = makeElement("ul", "partner-warning");
    conflicts.forEach(conflict => {
      list.append(makeElement(
        "li", "",
        `Advarsel: Person ${conflict.left_person_id} og person ` +
        `${conflict.right_person_id} er partnere i familie ${conflict.family_id}.`));
    });
    section.append(list);
  }
  container.append(section);
}

function renderContext(card, caseData) {
  const comparison = makeElement("section", "comparison");
  comparison.append(makeElement("h2", "comparison-heading", "Sammenlign grundlaget"));
  const records = makeElement("section", "source-records");
  caseData.records.forEach(record => renderSourceRecord(records, record));
  comparison.append(records, makeElement("h2", "", "Kandidatpersoner"));

  const candidates = makeElement("section", "candidate-grid");
  caseData.candidate_person_ids.forEach(personId => {
    let candidate = null;
    caseData.records.forEach(record => {
      const match = record.candidates.find(row => row.person_id === personId);
      if (candidate === null && match) {
        candidate = match;
      }
    });
    const person = caseData.persons.find(row => row.person_id === personId);
    const narrative = caseData.narratives.find(row => row.person_id === personId);
    renderCandidate(candidates, candidate, person, narrative);
  });
  comparison.append(candidates);
  renderIdentityRelations(comparison, caseData.identity_edges);
  renderPartnerConflicts(comparison, caseData.partner_conflicts);
  card.append(comparison);
}

function renderIdentityControl(container, control, vocabulary, states, refreshStatus) {
  const state = parseDefault(control);
  const accessiblePrefix = `Beslutning ${control.decision_id}`;
  const action = makeSelect(
    vocabulary.identity_actions,
    ["Uafklaret", "Forskellige personer", "Samme menneske"],
    `${accessiblePrefix}: handling`);
  const ids = control.allowed_person_ids.map(String);
  const alias = makeSelect(ids, null, `${accessiblePrefix}: aliasperson`);
  const canonical = makeSelect(
    ids, null, `${accessiblePrefix}: kanonisk person`);
  if (!state.alias) {
    state.alias = control.preferred_alias_person_id === null
      ? ids[0]
      : String(control.preferred_alias_person_id);
  }
  if (!state.canonical) {
    state.canonical = control.preferred_canonical_person_id === null
      ? ids[1]
      : String(control.preferred_canonical_person_id);
  }
  action.value = state.action;
  alias.value = state.alias;
  canonical.value = state.canonical;
  const direction = makeElement("div", "dependent");
  const swap = makeElement("button", "swap-direction", "Byt retning");
  swap.type = "button";
  direction.append(makeElement("span", "", "Alias "), alias,
                   makeElement("span", "", " → canonical "), canonical, swap);
  const exact = makeElement("code", "exact-token");
  const error = makeElement("p", "control-error");
  const update = () => {
    state.action = action.value;
    state.alias = alias.value;
    state.canonical = canonical.value;
    direction.hidden = state.action !== "SAMME";
    Array.from(alias.options).forEach(option => {
      option.disabled = state.action === "SAMME" && option.value === canonical.value;
    });
    Array.from(canonical.options).forEach(option => {
      option.disabled = state.action === "SAMME" && option.value === alias.value;
    });
    try {
      state.token = identityToken(state, control);
      state.valid = true;
      exact.textContent = state.token;
      error.textContent = "";
    } catch (_error) {
      state.valid = false;
      exact.textContent = "Kan ikke eksporteres";
      error.textContent = "Alias og canonical skal være forskellige tilladte personer.";
    }
    refreshStatus();
  };
  action.addEventListener("change", update);
  alias.addEventListener("change", update);
  canonical.addEventListener("change", update);
  swap.addEventListener("click", () => {
    const previousAlias = alias.value;
    alias.value = canonical.value;
    canonical.value = previousAlias;
    update();
  });
  container.append(action, direction, makeElement("span", "token-label", "Eksakt token: "), exact, error);
  states.set(control.decision_id, state);
  update();
}

function renderRecordControl(container, control, vocabulary, states, refreshStatus) {
  const state = parseDefault(control);
  const accessiblePrefix = `Beslutning ${control.decision_id}`;
  const action = makeSelect(
    vocabulary.record_actions,
    ["Uafklaret", "Tilhører person", "Ingen publikation", "Kræver record-revision"],
    `${accessiblePrefix}: handling`);
  const ids = control.allowed_person_ids.map(String);
  const person = makeSelect(ids, null, `${accessiblePrefix}: person`);
  const revision = makeSelect(
    vocabulary.revision_kinds, null, `${accessiblePrefix}: revisionstype`);
  if (!state.person) {
    state.person = ids[0];
  }
  if (!state.revision) {
    state.revision = vocabulary.revision_kinds[0];
  }
  action.value = state.action;
  person.value = state.person;
  revision.value = state.revision;
  const personRow = makeElement("div", "dependent");
  personRow.append(makeElement("span", "", "Person "), person);
  const revisionRow = makeElement("div", "dependent");
  revisionRow.append(makeElement("span", "", "Revisionstype "), revision);
  const exact = makeElement("code", "exact-token");
  const error = makeElement("p", "control-error");
  const update = () => {
    state.action = action.value;
    state.person = person.value;
    state.revision = revision.value;
    personRow.hidden = state.action !== "TIL";
    revisionRow.hidden = state.action !== "REVISION";
    try {
      state.token = recordToken(state, control, vocabulary);
      state.valid = true;
      exact.textContent = state.token;
      error.textContent = "";
    } catch (_error) {
      state.valid = false;
      exact.textContent = "Kan ikke eksporteres";
      error.textContent = "Valget ligger uden for den lukkede valgmængde.";
    }
    refreshStatus();
  };
  action.addEventListener("change", update);
  person.addEventListener("change", update);
  revision.addEventListener("change", update);
  container.append(action, personRow, revisionRow,
                   makeElement("span", "token-label", "Eksakt token: "), exact, error);
  states.set(control.decision_id, state);
  update();
}

function boot() {
  const payloadBytes = decodeBase64Url(document.getElementById("c3-payload").textContent.trim());
  const reviewBytes = decodeBase64Url(document.getElementById("c3-review").textContent.trim());
  const payload = JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(payloadBytes));
  const root = document.getElementById("c3-app");
  const states = new Map();
  const cards = [];
  const navigation = makeElement("nav", "case-navigation");
  const position = makeElement("strong", "position");
  const counts = makeElement("span", "counts");
  const previous = makeElement("button", "", "Forrige");
  previous.type = "button";
  const next = makeElement("button", "", "Næste");
  next.type = "button";
  const download = makeElement("button", "download", "Download c3-afgoerelser-redigeret.txt");
  download.type = "button";
  const digest = makeElement("output", "digest");
  let current = 0;

  const showCase = index => {
    current = Math.max(0, Math.min(payload.cases.length - 1, index));
    cards.forEach((card, cardIndex) => {
      card.hidden = cardIndex !== current;
    });
    Array.from(navigation.querySelectorAll("button")).forEach((button, buttonIndex) => {
      button.disabled = buttonIndex === current;
    });
    previous.disabled = current === 0;
    next.disabled = current === payload.cases.length - 1;
    position.textContent = `${current + 1} af ${payload.cases.length}`;
  };

  const refreshStatus = () => {
    if (states.size !== payload.counts.decisions) {
      return;
    }
    const values = Array.from(states.values());
    const unresolved = values.filter(state => state.token === "UAFKLARET").length;
    const invalid = values.filter(state => !state.valid).length;
    counts.textContent = `${values.length - unresolved} afklarede · ${unresolved} uafklarede`;
    download.disabled = invalid > 0;
  };

  payload.cases.forEach((caseData, caseIndex) => {
    const navButton = makeElement("button", "case-link", caseData.case_id);
    navButton.type = "button";
    navButton.addEventListener("click", () => showCase(caseIndex));
    navigation.append(navButton);
    const card = makeElement("section", "case-card");
    card.append(makeElement("h2", "", `Sag ${caseData.case_id}`));
    renderContext(card, caseData);
    caseData.controls.forEach(control => {
      const field = makeElement("section", "decision-control");
      const question = control.decision_type === "identity"
        ? "Er personerne samme menneske?"
        : `Hvem tilhører ${control.decision_id.slice(7)}?`;
      field.append(makeElement("h3", "", question));
      if (control.decision_type === "identity") {
        renderIdentityControl(field, control, payload.vocabulary, states, refreshStatus);
      } else {
        renderRecordControl(field, control, payload.vocabulary, states, refreshStatus);
      }
      card.append(field);
    });
    cards.push(card);
  });

  previous.addEventListener("click", () => showCase(current - 1));
  next.addEventListener("click", () => showCase(current + 1));
  download.addEventListener("click", async () => {
    try {
      const replacements = payload.slots.map(slot => {
        const state = states.get(slot.decision_id);
        if (!state || !state.valid) {
          throw new Error("C3_HTML_EXPORT_INVALID");
        }
        const token = controlToken(state, slot, payload.vocabulary);
        return {start: slot.start, end: slot.end, token};
      });
      const exported = replaceTokenBytes(reviewBytes, replacements);
      const hashBuffer = await crypto.subtle.digest("SHA-256", exported);
      const hash = Array.from(new Uint8Array(hashBuffer))
        .map(value => value.toString(16).padStart(2, "0")).join("");
      const blob = new Blob([exported], {type: "text/plain;charset=utf-8"});
      const objectUrl = URL.createObjectURL(blob);
      const anchor = makeElement("a", "");
      anchor.href = objectUrl;
      anchor.download = "c3-afgoerelser-redigeret.txt";
      anchor.click();
      URL.revokeObjectURL(objectUrl);
      digest.textContent = `SHA-256: ${hash}`;
    } catch (_error) {
      digest.textContent = "Download afvist: et valg er ugyldigt.";
    }
  });

  const toolbar = makeElement("header", "toolbar");
  toolbar.append(position, counts, navigation, previous, next, download, digest);
  root.append(toolbar, ...cards);
  showCase(0);
  refreshStatus();
}

if (typeof document !== "undefined") {
  boot();
}
'''


STYLE = r'''
:root { color-scheme: light; font-family: system-ui, sans-serif; }
* { box-sizing: border-box; }
body { margin: 0; color: #172032; background: #f4f1e8; }
main { width: 100%; max-width: 70rem; margin: 0 auto; padding: 1rem; }
.toolbar { position: sticky; top: 0; z-index: 2; display: flex; flex-wrap: wrap;
  gap: .65rem; align-items: center; padding: .8rem; background: #172032;
  color: white; border-radius: .5rem; }
.case-navigation { display: flex; flex-wrap: wrap; gap: .3rem; }
button, select { max-width: 100%; font: inherit; padding: .45rem .6rem; }
button { cursor: pointer; }
button:disabled { cursor: not-allowed; opacity: .55; }
.download { background: #f2c14e; border: 0; font-weight: 700; }
.digest { flex-basis: 100%; overflow-wrap: anywhere; }
.digest-static { overflow-wrap: anywhere; margin: 0 1rem 1rem; }
.case-card { min-width: 0; margin-top: 1rem; padding: 1rem; background: white; border-radius: .5rem;
  overflow-wrap: anywhere;
  box-shadow: 0 .1rem .4rem #0002; }
.comparison { margin-bottom: 1.3rem; }
.comparison-heading { font-size: 1.25rem; }
.source-records { display: grid; gap: 1rem; }
.source-record { padding: 1rem; border-left: .35rem solid #426b82; background: #eef5f7; }
.source-record h3, .candidate-card h3 { margin-top: 0; }
.source-metadata { display: flex; flex-wrap: wrap; gap: .3rem 1.2rem; }
.source-metadata p { margin: 0; }
.source-text, .candidate-text { white-space: pre-wrap; line-height: 1.55; }
.candidate-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 1rem; }
.candidate-card { min-width: 0; padding: 1rem; border: 1px solid #aeb9c8;
  border-radius: .4rem; background: #fbfcfd; }
.candidate-id, .binding-id { color: #566175; font-size: .9rem; overflow-wrap: anywhere; }
.candidate-badges { display: flex; flex-wrap: wrap; gap: .35rem; }
.badge { padding: .18rem .45rem; border-radius: 99rem; background: #e3eaf2;
  font-size: .88rem; font-weight: 650; }
.identity-relations, .partner-conflicts { margin-top: 1rem; padding: .8rem 1rem;
  border-radius: .4rem; background: #f4f6f8; }
.identity-relations h3, .partner-conflicts h3 { margin-top: 0; }
.partner-conflicts { border-left: .35rem solid #ad3b31; background: #fff1ef; }
.partner-warning { color: #7d211c; font-weight: 650; }
.empty-state { color: #566175; }
.decision-control { margin-top: .8rem; padding: 1rem; border: 1px solid #ccd2dc;
  border-radius: .4rem; }
.dependent { display: inline-flex; flex-wrap: wrap; max-width: 100%; gap: .4rem;
  align-items: center; margin-left: .6rem; }
.dependent select { min-width: 0; }
.token-label { display: block; margin-top: .8rem; }
.exact-token { display: inline-block; padding: .2rem .4rem; background: #eef3fa; }
.control-error { color: #9d211c; font-weight: 700; }
.page-intro { max-width: 46rem; line-height: 1.55; }
.card-intro { color: #3c485c; line-height: 1.5; }
.status-line { padding: .6rem .8rem; border-radius: .4rem; background: #eef5f7;
  border-left: .35rem solid #426b82; }
.technical-detail { margin-top: 1rem; }
.technical-detail summary { cursor: pointer; color: #566175; font-size: .9rem; }
.technical-detail p { font-size: .9rem; }
[hidden] { display: none !important; }
@media (max-width: 44rem) {
  .candidate-grid { grid-template-columns: 1fr; }
  .dependent { display: flex; flex-direction: column; align-items: stretch;
    margin: .6rem 0 0; }
}
'''


def _base64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii")


def render_html(payload: Mapping[str, Any], review_bytes: bytes) -> bytes:
    """Returnér ét komplet HTML-dokument med kun Base64-kodede data."""
    if not isinstance(payload, Mapping) or not isinstance(review_bytes, bytes):
        fail("C3_HTML_PAYLOAD_INVALID")
    try:
        payload_raw = json.dumps(
            payload, ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError):
        fail("C3_HTML_PAYLOAD_INVALID")
    document = """<!doctype html>
<html lang="da">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DAA 1939 C3 — lokal review</title>
<style>{style}</style>
</head>
<body>
<main id="c3-app"><h1>DAA 1939 C3 — lokal review</h1></main>
<div id="c3-payload" hidden>{payload}</div>
<div id="c3-review" hidden>{review}</div>
<script>{script}</script>
</body>
</html>
""".format(
        style=STYLE,
        payload=_base64url(payload_raw),
        review=_base64url(review_bytes),
        script=CLIENT_SCRIPT)
    return document.encode("utf-8")


# ---------------------------------------------------------------------------
# Apply-tilstand: godkendelsesark for de fem `assign`-sager i det endelige
# C3 apply-manifest (Task 3's output). Genbruger dette scripts eksisterende
# base64url-embedding, CSP-sikre klientkontrakt og atomiske publish_output —
# tilføjer ikke en ny renderer (Fund H6).
# ---------------------------------------------------------------------------

def _apply_exact_keys(value: Any, expected: set) -> None:
    if not isinstance(value, Mapping) or set(value.keys()) != expected:
        fail("C3_HTML_APPLY_MANIFEST_INVALID")


def _apply_hex64(value: Any) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def _apply_nonempty_str(value: Any) -> bool:
    return isinstance(value, str) and value != ""


def _apply_bool(value: Any) -> bool:
    return type(value) is bool


def _apply_positive_int(value: Any) -> bool:
    return type(value) is int and value > 0


def _apply_optional_positive_int(value: Any) -> bool:
    return value is None or _apply_positive_int(value)


def _apply_optional_hex64(value: Any) -> bool:
    return value is None or _apply_hex64(value)


def _validate_apply_source_record(value: Any) -> None:
    _apply_exact_keys(value, _APPLY_SOURCE_RECORD_KEYS)
    if (not (isinstance(value["match_count"], int)
              and type(value["match_count"]) is not bool)
            or not _apply_hex64(value["verbatim_sha256"])
            or not _apply_nonempty_str(value["side"])):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")


def _validate_apply_binding(value: Any) -> None:
    _apply_exact_keys(value, _APPLY_BINDING_KEYS)
    if (not isinstance(value["status"], str)
            or value["status"] not in _APPLY_BINDING_STATUSES
            or not _apply_optional_positive_int(value["binding_person_id"])):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")


def _validate_apply_event(event: Any) -> None:
    _apply_exact_keys(event, _APPLY_EVENT_KEYS)
    if (not _apply_nonempty_str(event["element_id"])
            or not _apply_nonempty_str(event["rid"])
            or not _apply_nonempty_str(event["record_key"])
            or event["action"] not in {"assign", "no_publication"}):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    before_state = event["before_state"]
    if event["action"] == "assign":
        _apply_exact_keys(before_state, _APPLY_ASSIGN_BEFORE_KEYS)
        _validate_apply_source_record(before_state["source_record"])
        _validate_apply_binding(before_state["binding"])
        target = before_state["target_narrative"]
        _apply_exact_keys(target, _APPLY_TARGET_NARRATIVE_KEYS)
        if (not (isinstance(target["person_id"], int)
                  and type(target["person_id"]) is not bool)
                or not _apply_optional_positive_int(target["narrative_id"])
                or not _apply_bool(target["privat"])
                or not _apply_optional_hex64(target["old_sha256"])):
            fail("C3_HTML_APPLY_MANIFEST_INVALID")
        after_state = event["after_state"]
        _apply_exact_keys(after_state, _APPLY_ASSIGN_AFTER_KEYS)
        if (not _apply_positive_int(after_state["target_person_id"])
                or not _apply_hex64(after_state["raw_sha256"])
                or not _apply_nonempty_str(after_state["normalized_text"])
                or not _apply_hex64(after_state["normalized_sha256"])
                or not _apply_nonempty_str(
                    after_state["normalization_version"])
                or not isinstance(
                    after_state["normalization_flags"], list)
                # Samme flag-pin som kandidatbyggeren (build_c3_apply_
                # candidate_1939_v50.py): hvert flag er et objekt med præcis
                # {kind, context, char_offset} — aldrig en bar streng.
                or not all(
                    isinstance(flag, dict)
                    and set(flag) == {"kind", "context", "char_offset"}
                    and isinstance(flag["kind"], str) and flag["kind"]
                    and isinstance(flag["context"], str)
                    and isinstance(flag["char_offset"], int)
                    and type(flag["char_offset"]) is not bool
                    and flag["char_offset"] >= 0
                    for flag in after_state["normalization_flags"])):
            fail("C3_HTML_APPLY_MANIFEST_INVALID")
        expected_narrative = after_state["expected_narrative"]
        _apply_exact_keys(
            expected_narrative, _APPLY_EXPECTED_NARRATIVE_KEYS)
        if (expected_narrative["privat"] is not False
                or not _apply_nonempty_str(expected_narrative["side"])
                or not _apply_nonempty_str(
                    expected_narrative["record_label"])
                or not _apply_nonempty_str(
                    expected_narrative["citation_label"])):
            fail("C3_HTML_APPLY_MANIFEST_INVALID")
    else:
        _apply_exact_keys(before_state, _APPLY_NOPUB_BEFORE_KEYS)
        _validate_apply_source_record(before_state["source_record"])
        _validate_apply_binding(before_state["binding"])
        if event["after_state"] != {}:
            fail("C3_HTML_APPLY_MANIFEST_INVALID")


def _validate_apply_case(case: Any) -> None:
    _apply_exact_keys(case, _APPLY_CASE_KEYS)
    if not _apply_nonempty_str(case["case_id"]):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    after_state = case["after_state"]
    _apply_exact_keys(after_state, _APPLY_CASE_AFTER_KEYS)
    person_ids = after_state["person_ids"]
    if (after_state["action"] != "different"
            or not isinstance(person_ids, list) or len(person_ids) != 2
            or not all(_apply_positive_int(pid) for pid in person_ids)
            or person_ids[0] >= person_ids[1]):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    before_state = case["before_state"]
    _apply_exact_keys(before_state, _APPLY_CASE_BEFORE_KEYS)
    if (not _apply_bool(before_state["component_overlap"])
            or not _apply_bool(before_state["existing_rejection"])):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    events = case["events"]
    if not isinstance(events, list) or not events:
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    for event in events:
        _validate_apply_event(event)


def _validate_apply_manifest(doc: Any) -> Dict[str, Any]:
    """Strukturel, uafhængig gyldighedskontrol af det endelige apply-manifest.

    Kontrollerer nøglesæt, typer og optalte tælle-invarianter, og
    genberegner manifestets egen `canonical_content_sha256` (samme
    kanoniske hash-konvention som Task 1/3). Genudleder IKKE Task 1's
    semantiske label-regler (fx `citation_label`-formatet) — det er
    Task 3's ansvar, allerede håndhævet der.
    """
    _apply_exact_keys(doc, _APPLY_MANIFEST_TOP_KEYS)
    if doc["schema_version"] != apply_manifest.SCHEMA_VERSION:
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    _apply_exact_keys(doc["input_hashes"], _APPLY_INPUT_HASH_KEYS)
    if any(not _apply_hex64(value) for value in doc["input_hashes"].values()):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    _apply_exact_keys(doc["database"], _APPLY_DATABASE_KEYS)
    if any(not _apply_nonempty_str(value)
           for value in doc["database"].values()):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    if doc["counts"] != _APPLY_COUNTS_EXACT:
        fail("C3_HTML_APPLY_COUNT_INVALID")
    if not _apply_hex64(doc["canonical_content_sha256"]):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    cases = doc["cases"]
    if not isinstance(cases, list) or len(cases) != 5:
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    for case in cases:
        _validate_apply_case(case)

    stated_hash = doc["canonical_content_sha256"]
    unhashed = {key: value for key, value in doc.items()
                if key != "canonical_content_sha256"}
    if (apply_manifest._sha(apply_manifest._canonical_bytes(unhashed))
            != stated_hash):
        fail("C3_HTML_APPLY_MANIFEST_HASH_MISMATCH")
    return doc


def _apply_assign_events(manifest_doc: Mapping[str, Any]
                         ) -> List[Dict[str, Any]]:
    """Udtræk de fem `assign`-hændelser i stabil, deterministisk rækkefølge.

    Sorteringen (efter `element_id`) er den ENE autoritative rækkefølge —
    kort, godkendelsesark og konverter deler den, fordi de alle sorterer
    de samme fem hændelser efter det samme felt.
    """
    events: List[Dict[str, Any]] = []
    for case in manifest_doc["cases"]:
        for event in case["events"]:
            if event["action"] == "assign":
                events.append({
                    "element_id": event["element_id"],
                    "case_id": case["case_id"],
                    "rid": event["rid"],
                    "record_key": event["record_key"],
                    "before": event["before_state"],
                    "after": event["after_state"],
                })
    expected = _APPLY_COUNTS_EXACT["assign_events"]
    if (len(events) != expected
            or len({event["element_id"] for event in events}) != expected):
        fail("C3_HTML_APPLY_COUNT_INVALID")
    return sorted(events, key=lambda event: event["element_id"])


def apply_text_bundle_sha256(assign_events: Sequence[Mapping[str, Any]]
                             ) -> str:
    """Kanonisk hash over de kandidat-afledte felter for de fem sager.

    Bindes til (element_id, rid, record_key, target_person_id,
    normaliseringsprofil-version, normaliseret tekst, flags,
    expected_narrative) — ALDRIG til preview-/DB-afledte felter (fx
    `before_state`, `database`, `input_hashes`, `narrative_id`,
    `old_sha256`, bindings-status). Det er præcis det, der gør ÉN
    menneskelig godkendelse gyldig i både rehearsal og prod
    (brief-rettelse "fund B1"): teksten og dens mål er de samme uanset
    hvilken database, der senere leverer before-state.

    `record_key`, `target_person_id` og `expected_narrative` blev
    tilføjet ved "Følgeafgørelse 2026-08-23" (bruger, efter Task 4's
    review): en uafhængig kontrol viste, at bundlen uden dem IKKE bandt
    hvilken person teksten skulle tildeles — to manifester med samme
    tekst men forskellige mål delte samme hash, og et fuldt godkendt ark
    for det ene validerede rent mod det andet. De tre felter er alle
    kandidat-afledte (Task 1, databaseuafhængige — hele assign
    `after_state` kopieres direkte fra kandidatens `decision` i
    `finalize_c3_apply_manifest_1939_v50.py`), præcis som record-tekst
    og normalisering allerede var, så tilføjelsen koster ikke B1's
    rehearsal/prod-portabilitet: samme kandidat giver samme
    bundle-værdi i begge forløb, uændret.
    """
    ordered = sorted(assign_events, key=lambda event: event["element_id"])
    payload = [
        {
            "element_id": event["element_id"],
            "rid": event["rid"],
            "record_key": event["record_key"],
            "target_person_id": event["after"]["target_person_id"],
            "normalization_version": event["after"]["normalization_version"],
            "normalized_text": event["after"]["normalized_text"],
            "normalization_flags": list(event["after"]["normalization_flags"]),
            "expected_narrative": dict(event["after"]["expected_narrative"]),
        }
        for event in ordered
    ]
    return apply_manifest._sha(apply_manifest._canonical_bytes(payload))


def apply_approval_sheet(text_bundle_sha256: str,
                         assign_events: Sequence[Mapping[str, Any]]
                         ) -> Tuple[bytes, List[Dict[str, Any]]]:
    """Den ENE autoritative byte-sekvens for godkendelsesarket.

    Kaldes af BÅDE denne renderer og den separate godkendelseskonverter
    (`convert_c3_apply_approvals_1939_v50.py`) — ingen af dem implementerer
    rækkefølgen selvstændigt (den parkerede C0-efterkørselsfejl).
    Returnerer (arkets rå bytes, de fem redigerbare tokenintervaller) i ét
    kald, så positionerne aldrig kan afvige fra teksten, de blev fundet i.
    """
    if not _apply_hex64(text_bundle_sha256):
        fail("C3_HTML_APPLY_HASH_INVALID")
    ordered = sorted(assign_events, key=lambda event: event["element_id"])
    element_ids = [event["element_id"] for event in ordered]
    expected = _APPLY_COUNTS_EXACT["assign_events"]
    if len(element_ids) != expected or len(set(element_ids)) != expected:
        fail("C3_HTML_APPLY_COUNT_INVALID")
    header = "# schema={}\n# text_bundle_sha256={}\n".format(
        APPLY_SHEET_SCHEMA, text_bundle_sha256)
    header_bytes = header.encode("utf-8")
    body = bytearray()
    slots: List[Dict[str, Any]] = []
    offset = len(header_bytes)
    default_token = APPLY_TOKENS[0]
    token_bytes = default_token.encode("utf-8")
    for element_id in element_ids:
        line = "[{}] approve:{}\n".format(default_token, element_id)
        line_bytes = line.encode("utf-8")
        start = offset + len(b"[")
        end = start + len(token_bytes)
        slots.append({
            "element_id": element_id,
            "start": start,
            "end": end,
            "default_token": default_token,
        })
        body.extend(line_bytes)
        offset += len(line_bytes)
    return header_bytes + bytes(body), slots


def _apply_card(event: Mapping[str, Any]) -> Dict[str, Any]:
    before = event["before"]
    after = event["after"]
    return {
        "element_id": event["element_id"],
        "case_id": event["case_id"],
        "rid": event["rid"],
        "record_key": event["record_key"],
        "before": {
            "source_record": dict(before["source_record"]),
            "binding": dict(before["binding"]),
            "target_narrative": dict(before["target_narrative"]),
        },
        "after": {
            "target_person_id": after["target_person_id"],
            "raw_sha256": after["raw_sha256"],
            "normalized_text": after["normalized_text"],
            "normalized_sha256": after["normalized_sha256"],
            "normalization_version": after["normalization_version"],
            "normalization_flags": list(after["normalization_flags"]),
            "expected_narrative": dict(after["expected_narrative"]),
        },
    }


def build_apply_payload(manifest_raw: bytes
                        ) -> Tuple[Dict[str, Any], bytes]:
    """Validér rå manifestbytes og byg den browser-view-model + arkbytes."""
    if not isinstance(manifest_raw, bytes):
        fail("C3_HTML_APPLY_MANIFEST_INVALID")
    manifest_doc = apply_manifest._decode_document(
        manifest_raw, "C3_HTML_APPLY_MANIFEST_INVALID")
    _validate_apply_manifest(manifest_doc)
    assign_events = _apply_assign_events(manifest_doc)
    text_bundle_sha256 = apply_text_bundle_sha256(assign_events)
    sheet_bytes, slots = apply_approval_sheet(
        text_bundle_sha256, assign_events)
    cards = [_apply_card(event) for event in assign_events]
    if [card["element_id"] for card in cards] != [
            slot["element_id"] for slot in slots]:
        fail("C3_HTML_APPLY_INTERNAL_ERROR")
    payload = {
        "schema_version": "1939-v50-c3-apply-html-payload-v1",
        "manifest_hashes": {
            "manifest_raw_sha256": hashlib.sha256(manifest_raw).hexdigest(),
            "manifest_canonical_content_sha256":
                manifest_doc["canonical_content_sha256"],
        },
        "text_bundle_sha256": text_bundle_sha256,
        "counts": {"decisions": _APPLY_COUNTS_EXACT["assign_events"]},
        "vocabulary": {"approval_actions": list(APPLY_TOKENS)},
        "cards": cards,
        "slots": slots,
    }
    return payload, sheet_bytes


CLIENT_APPLY_SCRIPT = r'''"use strict";

function decodeBase64Url(value) {
  const padded = value + "=".repeat((4 - value.length % 4) % 4);
  const binary = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function encodeBase64Url(bytes) {
  let binary = "";
  for (let index = 0; index < bytes.length; index += 1) {
    binary += String.fromCharCode(bytes[index]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_");
}

function replaceTokenBytes(sourceBytes, replacements) {
  const encoder = new TextEncoder();
  const ordered = replacements.slice().sort((left, right) => right.start - left.start);
  let result = sourceBytes.slice();
  for (const replacement of ordered) {
    if (!Number.isInteger(replacement.start) || !Number.isInteger(replacement.end) ||
        replacement.start < 0 || replacement.end <= replacement.start ||
        replacement.end > sourceBytes.length || typeof replacement.token !== "string") {
      throw new Error("C3_HTML_APPLY_EXPORT_INVALID");
    }
    const tokenBytes = encoder.encode(replacement.token);
    const next = new Uint8Array(
      replacement.start + tokenBytes.length + result.length - replacement.end);
    next.set(result.slice(0, replacement.start), 0);
    next.set(tokenBytes, replacement.start);
    next.set(result.slice(replacement.end), replacement.start + tokenBytes.length);
    result = next;
  }
  return result;
}

function makeElement(tagName, className, text) {
  const node = document.createElement(tagName);
  if (className) {
    node.className = className;
  }
  if (text !== undefined) {
    node.textContent = text;
  }
  return node;
}

function makeSelect(values, labels, accessibleName) {
  const select = makeElement("select", "choice");
  select.setAttribute("aria-label", accessibleName);
  values.forEach((value, index) => {
    const option = makeElement("option", "", labels ? labels[index] : value);
    option.value = String(value);
    select.append(option);
  });
  return select;
}

function readableValue(value) {
  return value === null || value === undefined || value === ""
    ? "Ikke registreret"
    : String(value);
}

function appendLabelledValue(container, label, value, className) {
  const row = makeElement("p", className || "labelled-value");
  row.append(makeElement("strong", "", `${label}: `),
             makeElement("span", "", readableValue(value)));
  container.append(row);
}

function bindingStatusPlain(status) {
  const labels = {
    absent: "Der er endnu ikke registreret nogen tekst her — dette er en ny tilføjelse.",
    draft_same_record: "Der findes allerede en kladde her for samme kildepost.",
    draft_other_record: "Der findes allerede en kladde her for en anden kildepost.",
    published: "Der er allerede en offentliggjort tekst her.",
    withdrawn: "En tidligere tekst her er trukket tilbage."
  };
  return labels[status] || "Status for denne tekst kunne ikke aflæses.";
}

function appendDetailRow(container, label, value) {
  const row = makeElement("p", "labelled-value");
  row.append(makeElement("strong", "", `${label}: `),
             makeElement("span", "", readableValue(value)));
  container.append(row);
}

function renderApplyCard(card, index, total) {
  const article = makeElement("section", "case-card");
  article.append(makeElement(
    "h2", "", `Tekst ${index + 1} af ${total}`));
  article.append(makeElement(
    "p", "card-intro",
    `Kilde: ${readableValue(card.after.expected_narrative.citation_label)}. `
    + "Læs teksten nedenfor, og markér den som godkendt, hvis den er korrekt."));

  const comparison = makeElement("section", "comparison");
  comparison.append(makeElement(
    "p", "status-line", bindingStatusPlain(card.before.binding.status)));

  const after = makeElement("article", "candidate-card");
  after.append(makeElement("h3", "", "Foreslået tekst"));
  after.append(makeElement("p", "candidate-text", readableValue(card.after.normalized_text)));
  comparison.append(after);

  const details = makeElement("details", "technical-detail");
  details.append(makeElement("summary", "", "Tekniske detaljer (til kontrol af sagen)"));
  appendDetailRow(details, "Tildeles person med database-ID", card.after.target_person_id);
  appendDetailRow(details, "Recordnøgle", card.record_key);
  appendDetailRow(details, "Sagsnummer", card.case_id);
  appendDetailRow(details, "Kildehash (raw_sha256)", card.after.raw_sha256);
  appendDetailRow(details, "Normaliseret hash (normalized_sha256)", card.after.normalized_sha256);
  appendDetailRow(details, "Normaliseringsversion", card.after.normalization_version);
  appendDetailRow(
    details, "Flags",
    card.after.normalization_flags.length
      ? card.after.normalization_flags
          .map(flag => `${flag.kind} (tegn ${flag.char_offset})`)
          .join(", ")
      : null);
  appendDetailRow(details, "Eksisterende narrativ-ID", card.before.target_narrative.narrative_id);
  appendDetailRow(details, "Eksisterende hash (old_sha256)", card.before.target_narrative.old_sha256);
  appendDetailRow(details, "Bindingsstatus (rå værdi)", card.before.binding.status);
  comparison.append(details);

  article.append(comparison);
  return article;
}

function boot() {
  const payloadBytes = decodeBase64Url(document.getElementById("c3-apply-payload").textContent.trim());
  const sheetBytes = decodeBase64Url(document.getElementById("c3-apply-sheet").textContent.trim());
  const payload = JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(payloadBytes));
  const root = document.getElementById("c3-apply-app");
  const states = new Map();

  const download = makeElement("button", "download", "Download c3-apply-godkendelser.txt");
  download.type = "button";
  const counts = makeElement("span", "counts");
  const bundleHash = makeElement("p", "digest-static", `text_bundle_sha256: ${payload.text_bundle_sha256}`);
  const digest = makeElement("output", "digest");

  const refreshStatus = () => {
    if (states.size !== payload.counts.decisions) {
      return;
    }
    const values = Array.from(states.values());
    const approved = values.filter(value => value === "GODKENDT").length;
    counts.textContent = `${approved} godkendt · ${values.length - approved} uafklaret`;
  };

  const intro = makeElement(
    "p", "page-intro",
    `Der er ${payload.counts.decisions} tekster klar til godkendelse. Gennemgå dem `
    + "én ad gangen, og markér hver som \"Godkendt\", hvis den er korrekt. Når du er "
    + "færdig, download filen med dine beslutninger nedenfor.");
  root.append(intro);

  const toolbar = makeElement("header", "toolbar");
  toolbar.append(counts, download, digest);
  root.append(toolbar, bundleHash);

  payload.cards.forEach((card, index) => {
    const article = renderApplyCard(card, index, payload.cards.length);
    const control = makeElement("section", "decision-control");
    control.append(makeElement("h3", "", "Godkend indsættelse af denne tekst"));
    const slot = payload.slots.find(row => row.element_id === card.element_id);
    const select = makeSelect(
      payload.vocabulary.approval_actions, ["Uafklaret", "Godkendt"],
      `Beslutning ${card.element_id}: godkendelse`);
    select.value = slot.default_token;
    const exact = makeElement("code", "exact-token", select.value);
    const update = () => {
      states.set(card.element_id, select.value);
      exact.textContent = select.value;
      refreshStatus();
    };
    select.addEventListener("change", update);
    control.append(
      select, makeElement("span", "token-label", "Din beslutning gemmes som: "), exact);
    article.append(control);
    root.append(article);
    states.set(card.element_id, select.value);
  });

  download.addEventListener("click", async () => {
    try {
      const replacements = payload.slots.map(slot => {
        const token = states.get(slot.element_id);
        if (typeof token !== "string") {
          throw new Error("C3_HTML_APPLY_EXPORT_INVALID");
        }
        return {start: slot.start, end: slot.end, token};
      });
      const exported = replaceTokenBytes(sheetBytes, replacements);
      const hashBuffer = await crypto.subtle.digest("SHA-256", exported);
      const hash = Array.from(new Uint8Array(hashBuffer))
        .map(value => value.toString(16).padStart(2, "0")).join("");
      const blob = new Blob([exported], {type: "text/plain;charset=utf-8"});
      const objectUrl = URL.createObjectURL(blob);
      const anchor = makeElement("a", "");
      anchor.href = objectUrl;
      anchor.download = "c3-apply-godkendelser.txt";
      anchor.click();
      URL.revokeObjectURL(objectUrl);
      digest.textContent = `SHA-256: ${hash}`;
    } catch (_error) {
      digest.textContent = "Download afvist: et valg er ugyldigt.";
    }
  });

  refreshStatus();
}

if (typeof document !== "undefined") {
  boot();
}
'''


def render_apply_html(payload: Mapping[str, Any], sheet_bytes: bytes) -> bytes:
    """Returnér ét komplet HTML-dokument for apply-godkendelsestilstanden."""
    if not isinstance(payload, Mapping) or not isinstance(sheet_bytes, bytes):
        fail("C3_HTML_APPLY_PAYLOAD_INVALID")
    try:
        payload_raw = json.dumps(
            payload, ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError):
        fail("C3_HTML_APPLY_PAYLOAD_INVALID")
    document = """<!doctype html>
<html lang="da">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DAA 1939 C3 apply — lokal godkendelse</title>
<style>{style}</style>
</head>
<body>
<main id="c3-apply-app"><h1>DAA 1939 C3 apply — lokal godkendelse</h1></main>
<div id="c3-apply-payload" hidden>{payload}</div>
<div id="c3-apply-sheet" hidden>{sheet}</div>
<script>{script}</script>
</body>
</html>
""".format(
        style=STYLE,
        payload=_base64url(payload_raw),
        sheet=_base64url(sheet_bytes),
        script=CLIENT_APPLY_SCRIPT)
    return document.encode("utf-8")


def _arguments(argv: Sequence[str]) -> Dict[str, str]:
    args = list(argv)
    mode = "review"
    if "--mode" in args:
        index = args.index("--mode")
        if index + 1 >= len(args):
            fail("C3_HTML_ARGUMENTS_INVALID")
        mode = args[index + 1]
        del args[index:index + 2]
    if mode == "review":
        allowed = {"--selection", "--state", "--review", "--output"}
    elif mode == "apply":
        allowed = {"--manifest", "--output"}
    else:
        fail("C3_HTML_ARGUMENTS_INVALID")
        raise AssertionError("unreachable")
    values: Dict[str, str] = {}
    position = 0
    while position < len(args):
        option = args[position]
        if (option not in allowed or option in values
                or position + 1 >= len(args)
                or args[position + 1].startswith("--")):
            fail("C3_HTML_ARGUMENTS_INVALID")
        values[option] = args[position + 1]
        position += 2
    if set(values) != allowed:
        fail("C3_HTML_ARGUMENTS_INVALID")
    values["--mode"] = mode
    return values


def _read_input(path: str, failure_code: str) -> bytes:
    try:
        return Path(path).read_bytes()
    except OSError:
        fail(failure_code)
    raise AssertionError("unreachable")


def publish_output(output: Path, rendered: bytes) -> None:
    """Publisér bytes atomisk via hard-link uden overskrivning."""
    temp_path: Optional[Path] = None
    descriptor: Optional[int] = None
    try:
        if os.path.lexists(str(output)):
            fail("C3_HTML_OUTPUT_EXISTS")
        descriptor, temporary = tempfile.mkstemp(
            prefix="." + output.name + ".", suffix=".tmp",
            dir=str(output.parent))
        temp_path = Path(temporary)
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = None
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(str(temp_path), str(output))
        except FileExistsError:
            fail("C3_HTML_OUTPUT_EXISTS")
        os.unlink(str(temp_path))
        temp_path = None
    except OSError:
        fail("C3_HTML_OUTPUT_WRITE_FAILED")
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temp_path is not None:
            try:
                os.unlink(str(temp_path))
            except OSError:
                pass


def _main_review(values: Dict[str, str]) -> int:
    output = Path(values["--output"])
    if os.path.lexists(str(output)):
        fail("C3_HTML_OUTPUT_EXISTS")
    selection_raw = _read_input(
        values["--selection"], "C3_HTML_SELECTION_INVALID")
    state_raw = _read_input(values["--state"], "C3_HTML_STATE_INVALID")
    review_raw = _read_input(values["--review"], "C3_HTML_REVIEW_INVALID")
    selection_doc = _decode_document(selection_raw)
    c0_hashes = selection_doc.get("input_hashes")
    if not isinstance(c0_hashes, Mapping):
        fail("C3_HTML_SELECTION_INVALID")
    input_hashes = {
        "c0_candidates_sha256": c0_hashes.get("c0_candidates_sha256"),
        "c0_decisions_sha256": c0_hashes.get("c0_decisions_sha256"),
        "selection_sha256": hashlib.sha256(selection_raw).hexdigest(),
        "state_sha256": hashlib.sha256(state_raw).hexdigest(),
        "review_sha256": hashlib.sha256(review_raw).hexdigest(),
    }
    payload = build_payload(
        selection_raw, state_raw, review_raw, input_hashes)
    rendered = render_html(payload, review_raw)
    publish_output(output, rendered)
    print(
        "sager=7 records=8 beslutninger=15 output={} review_sha256={} "
        "html_sha256={}".format(
            output.name, input_hashes["review_sha256"],
            hashlib.sha256(rendered).hexdigest()))
    return 0


def _main_apply(values: Dict[str, str]) -> int:
    output = Path(values["--output"])
    if os.path.lexists(str(output)):
        fail("C3_HTML_OUTPUT_EXISTS")
    manifest_raw = _read_input(
        values["--manifest"], "C3_HTML_APPLY_MANIFEST_INVALID")
    payload, sheet_bytes = build_apply_payload(manifest_raw)
    rendered = render_apply_html(payload, sheet_bytes)
    publish_output(output, rendered)
    print(
        "beslutninger={} output={} manifest_sha256={} "
        "text_bundle_sha256={} html_sha256={}".format(
            payload["counts"]["decisions"], output.name,
            payload["manifest_hashes"]["manifest_raw_sha256"],
            payload["text_bundle_sha256"],
            hashlib.sha256(rendered).hexdigest()))
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    values = _arguments(list(sys.argv[1:] if argv is None else argv))
    if values["--mode"] == "apply":
        return _main_apply(values)
    return _main_review(values)


def _cli_status() -> int:
    try:
        return main()
    except SystemExit as error:
        token = str(error)
        if CLI_ERROR_RE.fullmatch(token) is None:
            token = "C3_HTML_INTERNAL_ERROR"
        print(token, file=sys.stderr)
        return 1
    except Exception:
        print("C3_HTML_INTERNAL_ERROR", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(_cli_status())
