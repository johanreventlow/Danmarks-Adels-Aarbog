#!/usr/bin/env python3
"""Syntetiske, tekstsikre fixtures til C3 HTML-reviewtests."""

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"
FINALIZE_PATH = SCRIPT_DIR / "finalize_c3_apply_manifest_1939_v50.py"
ATTACK_SENTINEL = (
    "</script><img src=x onerror=globalThis.__C3_PWNED__=1>")
APPLY_ATTACK_SENTINEL = (
    "</script><img src=x onerror=globalThis.__C3_APPLY_PWNED__=1>")
ORDINARY_CASES: Tuple[Tuple[str, Tuple[int, int]], ...] = (
    ("R03", (1102, 1101)),
    ("R07", (1201, 1202)),
    ("R11", (1302, 1301)),
    ("R19", (1401, 1402)),
    ("R25", (1502, 1501)),
    ("R31", (1601, 1602)),
)
APPLY_CASE_SPECS: Tuple[Tuple[str, str, int, int, str], ...] = (
    ("case-1", "rid-1", 2101, 2102, "603"),
    ("case-2", "rid-2", 2201, 2202, "610"),
    ("case-3", "rid-3", 2301, 2302, "615"),
    ("case-4", "rid-4", 2401, 2402, "620"),
)
APPLY_SPECIAL_CASE = ("case-5", "rid-5", "rid-6", 2501, 2502, "625")


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("missing loader")
    spec.loader.exec_module(module)
    return module


def _load_review_builder():
    return _load_module("build_c3_review_1939_v50_for_html_fixture", BUILD_PATH)


review_builder = _load_review_builder()
finalize_builder = _load_module(
    "finalize_c3_apply_manifest_1939_v50_for_html_fixture", FINALIZE_PATH)


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _candidate(person_id: int, rid: str, include_attack: bool = False
               ) -> Dict[str, Any]:
    prose = "Syntetisk person med æ, ø og å: {}".format(person_id)
    if include_attack:
        prose += " " + ATTACK_SENTINEL
    return {
        "person_id": person_id,
        "visning_navn": "Syntetisk Ægir {}".format(person_id),
        "staged": False,
        "side": "500",
        "person_tekst": prose,
    }


def _record(rid: str, person_ids: Tuple[int, ...], include_attack: bool = False
            ) -> Dict[str, Any]:
    page_number = 600 + int(rid[1:])
    if rid == "R03":
        pages = {"page_from": page_number, "page_to": page_number + 1}
    elif rid == "R11":
        pages = None
    else:
        pages = {"page_from": page_number, "page_to": page_number}
    return {
        "rid": rid,
        "new_record_key": "synthetic-{}".format(rid.lower()),
        "classification": "kobling" if rid == "R40" else "sammenlaegning",
        "pages": pages,
        "verbatim_text": "Syntetisk kildetekst ÆØÅ {}".format(rid),
        "candidates": [
            _candidate(person_id, rid, include_attack and index == 0)
            for index, person_id in enumerate(person_ids)
        ],
    }


def selection_document() -> Dict[str, Any]:
    cases = []
    for index, (rid, person_ids) in enumerate(ORDINARY_CASES):
        cases.append({
            "case_kind": "ordinary",
            "candidate_person_ids": sorted(person_ids),
            "records": [_record(rid, person_ids, include_attack=index == 0)],
        })
    cases.append({
        "case_kind": "1017_1021",
        "candidate_person_ids": [1017, 1021],
        "records": [
            _record("R15", (1017, 1021)),
            _record("R40", (1017,)),
        ],
    })
    person_ids = sorted({
        person_id
        for case in cases
        for person_id in case["candidate_person_ids"]
    })
    return {
        "schema_version": "1939-v50-c3-selection-v1",
        "input_hashes": {
            "c0_candidates_sha256": "c" * 64,
            "c0_decisions_sha256": "d" * 64,
        },
        "case_count": 7,
        "record_count": 8,
        "decision_line_count": 15,
        "person_ids": person_ids,
        "cases": cases,
    }


def state_document(selection_sha256: str,
                   selection: Dict[str, Any]) -> Dict[str, Any]:
    persons = [
        {"person_id": person_id, "staged": False, "privat": False}
        for person_id in selection["person_ids"]
    ]
    next(row for row in persons if row["person_id"] == 1102)["staged"] = True
    narratives = [
        {
            "person_id": person_id,
            "narrative_id": 5000 + person_id,
            "old_sha256": "e" * 64,
            "privat": False,
            "side": "500",
            "source_record_id": None,
            "binding_status": None,
        }
        for person_id in selection["person_ids"]
    ]
    first_person_id = selection["cases"][0]["candidate_person_ids"][0]
    first_narrative = next(
        row for row in narratives if row["person_id"] == first_person_id)
    first_narrative["source_record_id"] = (
        "00000000-0000-0000-0000-000000000001")
    first_narrative["binding_status"] = "published"
    return {
        "schema_version": "1939-v50-c3-current-state-v1",
        "database_name": "synthetic",
        "database_identity": "42",
        "generator": "synthetic:v1",
        "selection_sha256": selection_sha256,
        "persons": persons,
        "narratives": narratives,
        "identity_edges": [
            {"role": "samme_som", "subject_id": first_person_id,
             "object_id": 9101},
            {"role": "ikke_samme_som", "subject_id": first_person_id,
             "object_id": 9102},
        ],
        "partner_conflicts": [
            {"left_person_id": 1101, "right_person_id": 1102,
             "family_id": 77},
        ],
    }


def _apply_assign_after_state(rid: str, record_key: str, side: str,
                              include_attack: bool = False) -> Dict[str, Any]:
    text = "Syntetisk normaliseret narrativ æøå for {}".format(rid)
    if include_attack:
        text += " " + APPLY_ATTACK_SENTINEL
    return {
        "target_person_id": None,
        "raw_sha256": _sha256(("apply-raw-" + rid).encode("utf-8")),
        "normalized_text": text,
        "normalized_sha256": _sha256(text.encode("utf-8")),
        "normalization_version": "narrative_norm_v1",
        "normalization_flags": ["ocr_cleanup", rid.replace("-", "_")],
        "expected_narrative": {
            "privat": False,
            "side": side,
            "record_label": record_key,
            "citation_label": "DAA 1939 side " + side,
        },
    }


def _apply_assign_before_state(rid: str, narrative_person_id: int
                               ) -> Dict[str, Any]:
    return {
        "source_record": {
            "match_count": 1,
            "verbatim_sha256": _sha256(("apply-raw-" + rid).encode("utf-8")),
            "side": "699",
        },
        "binding": {"status": "absent", "binding_person_id": None},
        "target_narrative": {
            "person_id": narrative_person_id,
            "narrative_id": 7000 + narrative_person_id,
            "privat": False,
            "old_sha256": _sha256(("apply-old-" + rid).encode("utf-8")),
        },
    }


def _apply_nopub_before_state(rid: str) -> Dict[str, Any]:
    return {
        "source_record": {
            "match_count": 1,
            "verbatim_sha256": _sha256(("apply-raw-" + rid).encode("utf-8")),
            "side": "699",
        },
        "binding": {"status": "absent", "binding_person_id": None},
    }


def _apply_assign_event(case_id: str, rid: str, alias_person_id: int,
                        canonical_person_id: int, side: str,
                        include_attack: bool = False) -> Dict[str, Any]:
    record_key = "synthetic-apply-{}".format(rid)
    after_state = _apply_assign_after_state(
        rid, record_key, side, include_attack=include_attack)
    after_state["target_person_id"] = alias_person_id
    return {
        "element_id": "case:{}:rid:{}".format(case_id, rid),
        "rid": rid,
        "record_key": record_key,
        "action": "assign",
        "after_state": after_state,
        "before_state": _apply_assign_before_state(rid, alias_person_id),
    }


def _apply_nopub_event(case_id: str, rid: str) -> Dict[str, Any]:
    record_key = "synthetic-apply-{}".format(rid)
    return {
        "element_id": "case:{}:rid:{}".format(case_id, rid),
        "rid": rid,
        "record_key": record_key,
        "action": "no_publication",
        "after_state": {},
        "before_state": _apply_nopub_before_state(rid),
    }


def _apply_case(case_id: str, alias_person_id: int, canonical_person_id: int,
                events: List[Dict[str, Any]]) -> Dict[str, Any]:
    return {
        "element_id": "case:" + case_id,
        "case_id": case_id,
        "after_state": {
            "action": "different",
            "person_ids": sorted([alias_person_id, canonical_person_id]),
        },
        "before_state": {
            "component_overlap": False,
            "existing_rejection": False,
        },
        "events": events,
    }


def apply_manifest_document() -> Dict[str, Any]:
    """Byg et syntetisk endeligt C3 apply-manifest (Task 3-skema)."""
    cases: List[Dict[str, Any]] = []
    for index, (case_id, rid, alias_id, canonical_id, side) in enumerate(
            APPLY_CASE_SPECS):
        event = _apply_assign_event(
            case_id, rid, alias_id, canonical_id, side,
            include_attack=index == 0)
        cases.append(_apply_case(case_id, alias_id, canonical_id, [event]))
    (special_case_id, assign_rid, nopub_rid, alias_id, canonical_id,
     side) = APPLY_SPECIAL_CASE
    assign_event = _apply_assign_event(
        special_case_id, assign_rid, alias_id, canonical_id, side)
    nopub_event = _apply_nopub_event(special_case_id, nopub_rid)
    cases.append(_apply_case(
        special_case_id, alias_id, canonical_id, [assign_event, nopub_event]))

    result: Dict[str, Any] = {
        "schema_version": finalize_builder.SCHEMA_VERSION,
        "input_hashes": {
            "candidate_raw_sha256": "a" * 64,
            "preview_raw_sha256": "b" * 64,
            "candidate_canonical_content_sha256": "c" * 64,
            "before_state_canonical_sha256": "d" * 64,
        },
        "database": {
            "database_name": "synthetic_apply_db",
            "system_identifier": "42",
        },
        "counts": {
            "cases": 5,
            "identity_events": 5,
            "assign_events": 5,
            "no_publication_events": 1,
            "events": 11,
        },
        "cases": cases,
    }
    result["canonical_content_sha256"] = finalize_builder._sha(
        finalize_builder._canonical_bytes(result))
    return result


def apply_manifest_bytes(manifest: Optional[Dict[str, Any]] = None) -> bytes:
    if manifest is None:
        manifest = apply_manifest_document()
    return finalize_builder._canonical_bytes(manifest)


def write_apply_fixture(output_dir: Path) -> Dict[str, Path]:
    """Skriv manifest.json (det endelige C3 apply-manifest) og returnér stien."""
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_bytes(apply_manifest_bytes())
    return {"manifest": manifest_path}


def write_fixture(output_dir: Path) -> Dict[str, Path]:
    """Skriv selection.json, state.json og review.txt og returnér stierne."""
    output_dir.mkdir(parents=True, exist_ok=True)
    selection_path = output_dir / "selection.json"
    state_path = output_dir / "state.json"
    review_path = output_dir / "review.txt"

    selection = selection_document()
    selection_raw = (json.dumps(
        selection, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode(
            "utf-8")
    selection_sha256 = _sha256(selection_raw)
    state = state_document(selection_sha256, selection)
    state_raw = (json.dumps(
        state, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode(
            "utf-8")
    state_sha256 = _sha256(state_raw)
    review_raw = review_builder.render_review(
        selection, state, selection_sha256, state_sha256).encode("utf-8")

    selection_path.write_bytes(selection_raw)
    state_path.write_bytes(state_raw)
    review_path.write_bytes(review_raw)
    return {
        "selection": selection_path,
        "state": state_path,
        "review": review_path,
    }


def input_hashes(paths: Dict[str, Path]) -> Dict[str, str]:
    selection = json.loads(paths["selection"].read_text(encoding="utf-8"))
    return {
        "c0_candidates_sha256": selection["input_hashes"][
            "c0_candidates_sha256"],
        "c0_decisions_sha256": selection["input_hashes"][
            "c0_decisions_sha256"],
        "selection_sha256": _sha256(paths["selection"].read_bytes()),
        "state_sha256": _sha256(paths["state"].read_bytes()),
        "review_sha256": _sha256(paths["review"].read_bytes()),
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--apply-output-dir")
    arguments = parser.parse_args(list(sys.argv[1:] if argv is None else argv))
    paths = write_fixture(Path(arguments.output_dir))
    hashes = input_hashes(paths)
    message = (
        "selection.json state.json review.txt "
        "sager=7 records=8 beslutningslinjer=15 "
        "selection_sha256={} state_sha256={} review_sha256={}".format(
            hashes["selection_sha256"], hashes["state_sha256"],
            hashes["review_sha256"]))
    if arguments.apply_output_dir:
        apply_paths = write_apply_fixture(Path(arguments.apply_output_dir))
        manifest_sha256 = _sha256(apply_paths["manifest"].read_bytes())
        message += " manifest.json manifest_sha256={}".format(
            manifest_sha256)
    print(message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
