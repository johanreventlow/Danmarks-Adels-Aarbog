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


@dataclass(frozen=True)
class DecisionSlot:
    decision_id: str
    case_id: str
    decision_type: str
    start: int
    end: int
    default_token: str
    allowed_person_ids: Tuple[int, ...]


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
                       for person_id in slot.allowed_person_ids)):
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
            "unresolved": 12}:
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

function makeSelect(values, labels) {
  const select = makeElement("select", "choice");
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

function renderContext(card, caseData) {
  const context = makeElement("details", "context");
  const summary = makeElement("summary", "", "Vis kildetekst og strukturel tilstand");
  const body = makeElement("pre", "context-body");
  body.textContent = JSON.stringify({
    records: caseData.records,
    persons: caseData.persons,
    narratives: caseData.narratives,
    identity_edges: caseData.identity_edges,
    partner_conflicts: caseData.partner_conflicts
  }, null, 2);
  context.append(summary, body);
  card.append(context);
}

function renderIdentityControl(container, control, vocabulary, states, refreshStatus) {
  const state = parseDefault(control);
  const action = makeSelect(
    vocabulary.identity_actions,
    ["Uafklaret", "Forskellige personer", "Samme menneske"]);
  const ids = control.allowed_person_ids.map(String);
  const alias = makeSelect(ids);
  const canonical = makeSelect(ids);
  if (!state.alias) {
    state.alias = ids[0];
  }
  if (!state.canonical) {
    state.canonical = ids[1];
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
  const action = makeSelect(
    vocabulary.record_actions,
    ["Uafklaret", "Tilhører person", "Ingen publikation", "Kræver record-revision"]);
  const ids = control.allowed_person_ids.map(String);
  const person = makeSelect(ids);
  const revision = makeSelect(vocabulary.revision_kinds);
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
body { margin: 0; color: #172032; background: #f4f1e8; }
main { max-width: 70rem; margin: 0 auto; padding: 1rem; }
.toolbar { position: sticky; top: 0; z-index: 2; display: flex; flex-wrap: wrap;
  gap: .65rem; align-items: center; padding: .8rem; background: #172032;
  color: white; border-radius: .5rem; }
.case-navigation { display: flex; flex-wrap: wrap; gap: .3rem; }
button, select { font: inherit; padding: .45rem .6rem; }
button { cursor: pointer; }
button:disabled { cursor: not-allowed; opacity: .55; }
.download { background: #f2c14e; border: 0; font-weight: 700; }
.digest { flex-basis: 100%; overflow-wrap: anywhere; }
.case-card { margin-top: 1rem; padding: 1rem; background: white; border-radius: .5rem;
  box-shadow: 0 .1rem .4rem #0002; }
.context { margin-bottom: 1rem; }
.context-body { max-height: 24rem; overflow: auto; padding: .8rem;
  white-space: pre-wrap; background: #f7f7f7; }
.decision-control { margin-top: .8rem; padding: 1rem; border: 1px solid #ccd2dc;
  border-radius: .4rem; }
.dependent { display: inline-flex; gap: .4rem; align-items: center; margin-left: .6rem; }
.token-label { display: block; margin-top: .8rem; }
.exact-token { display: inline-block; padding: .2rem .4rem; background: #eef3fa; }
.control-error { color: #9d211c; font-weight: 700; }
[hidden] { display: none !important; }
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


def _arguments(argv: Sequence[str]) -> Dict[str, str]:
    allowed = {"--selection", "--state", "--review", "--output"}
    values: Dict[str, str] = {}
    position = 0
    while position < len(argv):
        option = argv[position]
        if (option not in allowed or option in values
                or position + 1 >= len(argv)
                or argv[position + 1].startswith("--")):
            fail("C3_HTML_ARGUMENTS_INVALID")
        values[option] = argv[position + 1]
        position += 2
    if set(values) != allowed:
        fail("C3_HTML_ARGUMENTS_INVALID")
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


def main(argv: Optional[Sequence[str]] = None) -> int:
    values = _arguments(list(sys.argv[1:] if argv is None else argv))
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
