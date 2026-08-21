#!/usr/bin/env python3
"""Syntetiske, tekstsikre fixtures til C3 HTML-reviewtests."""

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict, Optional, Sequence, Tuple


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_PATH = SCRIPT_DIR / "build_c3_review_1939_v50.py"
ATTACK_SENTINEL = (
    "</script><img src=x onerror=globalThis.__C3_PWNED__=1>")
ORDINARY_CASES: Tuple[Tuple[str, Tuple[int, int]], ...] = (
    ("R03", (1102, 1101)),
    ("R07", (1201, 1202)),
    ("R11", (1302, 1301)),
    ("R19", (1401, 1402)),
    ("R25", (1502, 1501)),
    ("R31", (1601, 1602)),
)


def _load_review_builder():
    spec = importlib.util.spec_from_file_location(
        "build_c3_review_1939_v50_for_html_fixture", BUILD_PATH)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("missing loader")
    spec.loader.exec_module(module)
    return module


review_builder = _load_review_builder()


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
    arguments = parser.parse_args(list(sys.argv[1:] if argv is None else argv))
    paths = write_fixture(Path(arguments.output_dir))
    hashes = input_hashes(paths)
    print(
        "selection.json state.json review.txt "
        "sager=7 records=8 beslutningslinjer=15 "
        "selection_sha256={} state_sha256={} review_sha256={}".format(
            hashes["selection_sha256"], hashes["state_sha256"],
            hashes["review_sha256"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
