#!/usr/bin/env python3
"""Byg ét lokalt, deterministisk C3-reviewark uden databaseadgang."""

import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional


SELECTION_SCHEMA = "1939-v50-c3-selection-v1"
STATE_SCHEMA = "1939-v50-c3-current-state-v1"
SPECIAL_PERSON_IDS = [1017, 1021]
SPECIAL_RID = "R15"
COMPANION_RID = "R40"
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_RID_RE = re.compile(r"^R([0-9]{2})$")
_UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_SAFE_NAME_RE = re.compile(r"^[A-Za-z0-9_.:/-]+$")
_CLI_ERROR_RE = re.compile(r"^C3_[A-Z0-9_]+(?::[A-Za-z0-9_.-]+)*$")

HEADER = """\
# DAA 1939 — C3: identitet og recordplacering
#
# selection_sha256={selection_sha256}
# state_sha256={state_sha256}
# sager=7 records=8 beslutningslinjer=15
#
# Ret KUN tokenet i den firkantede parentes forrest på en beslutningslinje.
# Overskrifter, rækkefølge, ID'er, kontekst og resten af linjen er byte-låst.
# Identitet og recordplacering er to uafhængige beslutninger.
#
# Identitet: SAMME <alias> <canonical> | FORSKELLIGE | UAFKLARET
# Record: TIL <person-id> | REVISION <split_into|merged_from|replaced_by>
#         INGEN_PUBLIKATION | UAFKLARET
#
# Arket skriver intet til databasen og autoriserer ingen apply-handling.
"""


def fail(code: str) -> None:
    raise SystemExit(code)


def _is_sha(value: Any) -> bool:
    return isinstance(value, str) and _SHA256_RE.fullmatch(value) is not None


def _is_id(value: Any) -> bool:
    return type(value) is int and value > 0


def _ids(value: Any) -> Optional[List[int]]:
    if (not isinstance(value, list) or not value
            or any(not _is_id(item) for item in value)):
        return None
    return list(value)


def _record_candidate_ids(record: Dict[str, Any], token: str) -> List[int]:
    candidates = record.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        fail(token)
    candidate_ids: List[int] = []
    for candidate in candidates:
        if not isinstance(candidate, dict) or not _is_id(candidate.get("person_id")):
            fail(token)
        candidate_ids.append(candidate["person_id"])
    if len(set(candidate_ids)) != len(candidate_ids):
        fail(token)
    return sorted(candidate_ids)


def _validate_record(record: Any, rid: str, candidate_ids: List[int],
                     classification: str, token: str) -> None:
    if (not isinstance(record, dict) or record.get("rid") != rid
            or record.get("classification") != classification
            or not isinstance(record.get("new_record_key"), str)
            or not record["new_record_key"]
            or not isinstance(record.get("verbatim_text"), str)
            or not record["verbatim_text"]
            or _record_candidate_ids(record, token) != candidate_ids):
        fail(token)


def _validate_selection(selection_doc: Any) -> List[int]:
    if (not isinstance(selection_doc, dict)
            or selection_doc.get("schema_version") != SELECTION_SCHEMA):
        fail("C3_REVIEW_SELECTION_INVALID")
    hashes = selection_doc.get("input_hashes")
    if (not isinstance(hashes, dict)
            or set(hashes) != {"c0_candidates_sha256", "c0_decisions_sha256"}
            or not all(_is_sha(value) for value in hashes.values())):
        fail("C3_REVIEW_SELECTION_HASH_INVALID")
    expected_counts = {"case_count": 7, "record_count": 8,
                       "decision_line_count": 15}
    if any(type(selection_doc.get(field)) is not int
           or selection_doc[field] != expected
           for field, expected in expected_counts.items()):
        fail("C3_REVIEW_COUNT_INVALID")
    selected_ids = _ids(selection_doc.get("person_ids"))
    if selected_ids is None or selected_ids != sorted(set(selected_ids)):
        fail("C3_REVIEW_SELECTION_INVALID")
    cases = selection_doc.get("cases")
    if not isinstance(cases, list) or len(cases) != 7:
        fail("C3_REVIEW_COUNT_INVALID")

    ordinary_rids: List[str] = []
    record_keys = set()
    covered_ids = set()
    for case in cases[:-1]:
        if not isinstance(case, dict) or case.get("case_kind") != "ordinary":
            fail("C3_REVIEW_CASE_INVALID")
        case_ids = _ids(case.get("candidate_person_ids"))
        records = case.get("records")
        if (case_ids is None or len(case_ids) < 2
                or case_ids != sorted(set(case_ids))
                or not isinstance(records, list) or len(records) != 1):
            fail("C3_REVIEW_CASE_INVALID")
        record = records[0]
        rid = record.get("rid") if isinstance(record, dict) else None
        match = _RID_RE.fullmatch(rid) if isinstance(rid, str) else None
        if (match is None or int(match.group(1)) < 1
                or rid in {SPECIAL_RID, COMPANION_RID}):
            fail("C3_REVIEW_CASE_INVALID")
        if rid in ordinary_rids:
            fail("C3_REVIEW_RID_DUPLICATE:" + rid)
        _validate_record(record, rid, case_ids, "sammenlaegning",
                         "C3_REVIEW_CASE_INVALID:" + rid)
        if record["new_record_key"] in record_keys:
            fail("C3_REVIEW_CASE_INVALID:" + rid)
        record_keys.add(record["new_record_key"])
        ordinary_rids.append(rid)
        covered_ids.update(case_ids)
    if ordinary_rids != sorted(ordinary_rids,
                               key=lambda rid: int(rid[1:])):
        fail("C3_REVIEW_CASE_INVALID")

    special = cases[-1]
    if (not isinstance(special, dict)
            or special.get("case_kind") != "1017_1021"
            or special.get("candidate_person_ids") != SPECIAL_PERSON_IDS
            or not isinstance(special.get("records"), list)
            or len(special["records"]) != 2
            or [record.get("rid") if isinstance(record, dict) else None
                for record in special["records"]] != [SPECIAL_RID, COMPANION_RID]):
        fail("C3_REVIEW_SPECIAL_INVALID")
    r15, r40 = special["records"]
    _validate_record(r15, SPECIAL_RID, SPECIAL_PERSON_IDS, "sammenlaegning",
                     "C3_REVIEW_R15_INVALID")
    _validate_record(r40, COMPANION_RID, [1017], "kobling",
                     "C3_REVIEW_R40_INVALID")
    for record in (r15, r40):
        if record["new_record_key"] in record_keys:
            fail("C3_REVIEW_SPECIAL_INVALID")
        record_keys.add(record["new_record_key"])
    covered_ids.update(SPECIAL_PERSON_IDS)
    if sorted(covered_ids) != selected_ids or len(record_keys) != 8:
        fail("C3_REVIEW_SELECTION_INVALID")
    return selected_ids


def _validate_state(state_doc: Any, selected_ids: List[int]) -> None:
    if (not isinstance(state_doc, dict)
            or state_doc.get("schema_version") != STATE_SCHEMA):
        fail("C3_REVIEW_STATE_INVALID")
    if (not isinstance(state_doc.get("database_name"), str)
            or _SAFE_NAME_RE.fullmatch(state_doc["database_name"]) is None
            or not isinstance(state_doc.get("database_identity"), str)
            or re.fullmatch(r"[0-9]+", state_doc["database_identity"]) is None
            or not isinstance(state_doc.get("generator"), str)
            or _SAFE_NAME_RE.fullmatch(state_doc["generator"]) is None
            or not _is_sha(state_doc.get("selection_sha256"))):
        fail("C3_REVIEW_STATE_INVALID")

    persons = state_doc.get("persons")
    if not isinstance(persons, list):
        fail("C3_REVIEW_PERSON_SET_INVALID")
    person_ids: List[int] = []
    for row in persons:
        if (not isinstance(row, dict) or not _is_id(row.get("person_id"))
                or type(row.get("staged")) is not bool):
            fail("C3_REVIEW_PERSON_SET_INVALID")
        person_id = row["person_id"]
        if row.get("privat") is not False:
            fail("C3_REVIEW_PERSON_PRIVATE:" + str(person_id))
        person_ids.append(person_id)
    if person_ids != selected_ids or len(set(person_ids)) != len(person_ids):
        fail("C3_REVIEW_PERSON_SET_INVALID")

    narratives = state_doc.get("narratives")
    if not isinstance(narratives, list):
        fail("C3_REVIEW_NARRATIVE_SET_INVALID")
    narrative_person_ids: List[int] = []
    narrative_ids = set()
    for row in narratives:
        if (not isinstance(row, dict) or not _is_id(row.get("person_id"))
                or not _is_id(row.get("narrative_id"))):
            fail("C3_REVIEW_NARRATIVE_SET_INVALID")
        person_id = row["person_id"]
        if person_id in narrative_person_ids:
            fail("C3_REVIEW_NARRATIVE_DUPLICATE:" + str(person_id))
        if row["narrative_id"] in narrative_ids:
            fail("C3_REVIEW_NARRATIVE_DUPLICATE:" + str(person_id))
        narrative_person_ids.append(person_id)
        narrative_ids.add(row["narrative_id"])
        if row.get("privat") is not False:
            fail("C3_REVIEW_NARRATIVE_PRIVATE:" + str(person_id))
        if not _is_sha(row.get("old_sha256")):
            fail("C3_REVIEW_NARRATIVE_INVALID:" + str(person_id))
        side = row.get("side")
        if side is not None and (not isinstance(side, str) or not side):
            fail("C3_REVIEW_NARRATIVE_INVALID:" + str(person_id))
        source_record_id = row.get("source_record_id")
        binding_status = row.get("binding_status")
        bound = source_record_id is not None
        if ((bound and (not isinstance(source_record_id, str)
                        or _UUID_RE.fullmatch(source_record_id) is None))
                or bound != (binding_status is not None)
                or (binding_status is not None
                    and not isinstance(binding_status, str))
                or (isinstance(binding_status, str)
                    and binding_status not in {"draft", "published", "withdrawn"})):
            fail("C3_REVIEW_BINDING_INVALID:" + str(person_id))
    if (narrative_person_ids != selected_ids
            or len(set(narrative_person_ids)) != len(narrative_person_ids)):
        fail("C3_REVIEW_NARRATIVE_SET_INVALID")

    edges = state_doc.get("identity_edges")
    if not isinstance(edges, list):
        fail("C3_REVIEW_STATE_INVALID")
    edge_keys = set()
    for edge in edges:
        if (not isinstance(edge, dict)
                or not isinstance(edge.get("role"), str)
                or edge.get("role") not in {"samme_som", "ikke_samme_som"}
                or not _is_id(edge.get("subject_id"))
                or not _is_id(edge.get("object_id"))
                or edge["subject_id"] == edge["object_id"]
                or (edge["subject_id"] not in selected_ids
                    and edge["object_id"] not in selected_ids)
                or (edge["role"] == "ikke_samme_som"
                    and edge["subject_id"] > edge["object_id"])):
            fail("C3_REVIEW_EDGE_INVALID")
        edge_key = (edge["role"], edge["subject_id"], edge["object_id"])
        if edge_key in edge_keys:
            fail("C3_REVIEW_EDGE_INVALID")
        edge_keys.add(edge_key)

    conflicts = state_doc.get("partner_conflicts")
    if not isinstance(conflicts, list):
        fail("C3_REVIEW_STATE_INVALID")
    conflict_keys = set()
    for conflict in conflicts:
        if (not isinstance(conflict, dict)
                or not _is_id(conflict.get("left_person_id"))
                or not _is_id(conflict.get("right_person_id"))
                or not _is_id(conflict.get("family_id"))
                or conflict["left_person_id"] >= conflict["right_person_id"]
                or conflict["left_person_id"] not in selected_ids
                or conflict["right_person_id"] not in selected_ids):
            fail("C3_REVIEW_PARTNER_INVALID")
        conflict_key = (conflict["left_person_id"],
                        conflict["right_person_id"], conflict["family_id"])
        if conflict_key in conflict_keys:
            fail("C3_REVIEW_PARTNER_INVALID")
        conflict_keys.add(conflict_key)


def _validate_documents(selection_doc: Any, state_doc: Any) -> List[int]:
    selected_ids = _validate_selection(selection_doc)
    _validate_state(state_doc, selected_ids)
    return selected_ids


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"))


def _decision(decision_type: str, decision_id: str, default_token: str,
              allowed_person_ids: List[int],
              preferred_alias_person_id: Optional[int] = None,
              preferred_canonical_person_id: Optional[int] = None
              ) -> Dict[str, Any]:
    ids = sorted(set(allowed_person_ids))
    result = {
        "type": decision_type,
        "decision_id": decision_id,
        "tail": "{} | allowed_person_ids={}".format(
            decision_id, ",".join(str(person_id) for person_id in ids)),
        "allowed_person_ids": ids,
        "default_token": default_token,
    }
    if (preferred_alias_person_id is not None
            or preferred_canonical_person_id is not None):
        if (decision_type != "identity"
                or preferred_alias_person_id is None
                or preferred_canonical_person_id is None
                or preferred_alias_person_id == preferred_canonical_person_id
                or preferred_alias_person_id not in ids
                or preferred_canonical_person_id not in ids):
            fail("C3_REVIEW_DECISION_INVALID")
        result["preferred_alias_person_id"] = preferred_alias_person_id
        result["preferred_canonical_person_id"] = (
            preferred_canonical_person_id)
    return result


def _record_headings(record: Dict[str, Any]) -> List[Dict[str, Any]]:
    rid = record["rid"]
    result = [
        {"type": "heading", "heading_kind": "record_text", "rid": rid},
        {"type": "heading", "heading_kind": "record_meta", "rid": rid},
    ]
    for candidate in sorted(record["candidates"],
                            key=lambda row: row["person_id"]):
        result.append({
            "type": "heading",
            "heading_kind": "candidate",
            "rid": rid,
            "person_id": candidate["person_id"],
        })
    return result


def _state_headings(person_ids: List[int]) -> List[Dict[str, Any]]:
    result: List[Dict[str, Any]] = []
    for person_id in sorted(set(person_ids)):
        result.append({
            "type": "heading",
            "heading_kind": "person_state",
            "person_id": person_id,
        })
    return result


def _graph_headings(state_doc: Dict[str, Any]) -> List[Dict[str, Any]]:
    result: List[Dict[str, Any]] = []
    for index, _edge in enumerate(state_doc["identity_edges"]):
        result.append({"type": "heading", "heading_kind": "identity_edge",
                       "state_index": index})
    for index, _conflict in enumerate(state_doc["partner_conflicts"]):
        result.append({"type": "heading", "heading_kind": "partner_conflict",
                       "state_index": index})
    return result


def _render_heading(item: Dict[str, Any], selection_doc: Dict[str, Any],
                    state_doc: Dict[str, Any]) -> str:
    if "text" in item:
        return item["text"]
    kind = item["heading_kind"]
    if kind in {"record_text", "record_meta", "candidate"}:
        record = next(record for case in selection_doc["cases"]
                      for record in case["records"] if record["rid"] == item["rid"])
        if kind == "record_text":
            return "KILDERECORD {} | {}".format(
                item["rid"], _canonical(record["verbatim_text"]))
        if kind == "record_meta":
            metadata = {key: value for key, value in record.items()
                        if key not in {"candidates", "verbatim_text"}}
            return "RECORDMETA {} | {}".format(item["rid"], _canonical(metadata))
        candidate = next(row for row in record["candidates"]
                         if row["person_id"] == item["person_id"])
        return "KANDIDAT {}:{} | {}".format(
            item["rid"], item["person_id"], _canonical(candidate))
    if kind == "person_state":
        person_id = item["person_id"]
        person = next(row for row in state_doc["persons"]
                      if row["person_id"] == person_id)
        narrative = next(row for row in state_doc["narratives"]
                         if row["person_id"] == person_id)
        return "AKTUEL_PERSON {} | person={} | narrative={}".format(
            person_id, _canonical(person), _canonical(narrative))
    if kind == "identity_edge":
        return "IDENTITY_EDGE | " + _canonical(
            state_doc["identity_edges"][item["state_index"]])
    return "PARTNER_CONFLICT | " + _canonical(
        state_doc["partner_conflicts"][item["state_index"]])


def review_sequence(selection_doc: Dict[str, Any], state_doc: Dict[str, Any]
                    ) -> List[Dict[str, Any]]:
    """Returnér den ene autoritative kontekst- og beslutningsrækkefølge."""
    _validate_documents(selection_doc, state_doc)
    sequence: List[Dict[str, Any]] = _graph_headings(state_doc)
    ordinary_cases = selection_doc["cases"][:-1]
    for case in ordinary_cases:
        record = case["records"][0]
        rid = record["rid"]
        ids = sorted(set(case["candidate_person_ids"]))
        sequence.append({"type": "heading", "text": "== SAG {} ==".format(rid)})
        sequence.extend(_record_headings(record))
        sequence.extend(_state_headings(ids))
        sequence.append(_decision("identity", "identity:" + rid,
                                  "UAFKLARET", ids))
        sequence.append(_decision("record", "record:" + rid,
                                  "UAFKLARET", ids))

    special = selection_doc["cases"][-1]
    records = {record["rid"]: record for record in special["records"]}
    sequence.append({"type": "heading", "text": "== SAG 1017/1021 =="})
    sequence.extend(_record_headings(records[COMPANION_RID]))
    sequence.extend(_record_headings(records[SPECIAL_RID]))
    sequence.extend(_state_headings(SPECIAL_PERSON_IDS))
    sequence.append(_decision("identity", "identity:1017:1021",
                              "UAFKLARET", SPECIAL_PERSON_IDS,
                              preferred_alias_person_id=1021,
                              preferred_canonical_person_id=1017))
    sequence.append(_decision("record", "record:R40", "TIL 1017",
                              SPECIAL_PERSON_IDS))
    sequence.append(_decision("record", "record:R15", "TIL 1021",
                              SPECIAL_PERSON_IDS))
    return sequence


def render_review(selection_doc: Dict[str, Any], state_doc: Dict[str, Any],
                  selection_sha256: str, state_sha256: str) -> str:
    if not _is_sha(selection_sha256) or not _is_sha(state_sha256):
        fail("C3_REVIEW_HASH_INVALID")
    _validate_documents(selection_doc, state_doc)
    if state_doc["selection_sha256"] != selection_sha256:
        fail("C3_REVIEW_SELECTION_HASH_MISMATCH")
    lines = [HEADER.format(selection_sha256=selection_sha256,
                           state_sha256=state_sha256)]
    for item in review_sequence(selection_doc, state_doc):
        if item["type"] == "heading":
            lines.append(_render_heading(item, selection_doc, state_doc))
        else:
            lines.append("[{}] {}".format(item["default_token"], item["tail"]))
    return "\n".join(lines) + "\n"


def _arguments(argv: List[str]) -> Dict[str, str]:
    allowed = {"--selection", "--state", "--output"}
    values: Dict[str, str] = {}
    position = 0
    while position < len(argv):
        option = argv[position]
        if (option not in allowed or option in values
                or position + 1 >= len(argv)
                or argv[position + 1].startswith("--")):
            fail("C3_REVIEW_ARGUMENTS_INVALID")
        values[option] = argv[position + 1]
        position += 2
    if set(values) != allowed:
        fail("C3_REVIEW_ARGUMENTS_INVALID")
    return values


def _read_input(path: str, failure_code: str) -> bytes:
    try:
        return Path(path).read_bytes()
    except OSError:
        fail(failure_code)
    raise AssertionError("unreachable")


def _decode_document(raw: bytes, failure_code: str) -> Dict[str, Any]:
    try:
        document = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        fail(failure_code)
    if not isinstance(document, dict):
        fail(failure_code)
    return document


def publish_output(output: Path, rendered: str) -> None:
    """Publisér via hard-link, så en samtidig destination aldrig overskrives."""
    temp_path: Optional[Path] = None
    descriptor: Optional[int] = None
    try:
        if os.path.lexists(str(output)):
            fail("C3_REVIEW_OUTPUT_EXISTS")
        descriptor, temporary = tempfile.mkstemp(
            prefix="." + output.name + ".", suffix=".tmp", dir=str(output.parent))
        temp_path = Path(temporary)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = None
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(str(temp_path), str(output))
        except FileExistsError:
            fail("C3_REVIEW_OUTPUT_EXISTS")
        os.unlink(str(temp_path))
        temp_path = None
    except OSError:
        fail("C3_REVIEW_OUTPUT_WRITE_FAILED")
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


def main(argv: Optional[List[str]] = None) -> int:
    values = _arguments(list(sys.argv[1:] if argv is None else argv))
    selection_raw = _read_input(values["--selection"],
                                "C3_REVIEW_SELECTION_INVALID")
    state_raw = _read_input(values["--state"], "C3_REVIEW_STATE_INVALID")
    selection_doc = _decode_document(selection_raw,
                                     "C3_REVIEW_SELECTION_INVALID")
    state_doc = _decode_document(state_raw, "C3_REVIEW_STATE_INVALID")
    selection_sha256 = hashlib.sha256(selection_raw).hexdigest()
    state_sha256 = hashlib.sha256(state_raw).hexdigest()
    rendered = render_review(selection_doc, state_doc, selection_sha256,
                             state_sha256)
    publish_output(Path(values["--output"]), rendered)
    review_sha256 = hashlib.sha256(rendered.encode("utf-8")).hexdigest()
    print("sager=7 records=8 beslutningslinjer=15 review_sha256={}".format(
        review_sha256))
    return 0


def _cli_status() -> int:
    try:
        return main()
    except SystemExit as error:
        token = str(error)
        if _CLI_ERROR_RE.fullmatch(token) is None:
            token = "C3_REVIEW_INTERNAL_ERROR"
        print(token, file=sys.stderr)
        return 1
    except Exception:
        print("C3_REVIEW_INTERNAL_ERROR", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(_cli_status())
