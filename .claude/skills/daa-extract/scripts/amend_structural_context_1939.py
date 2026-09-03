#!/usr/bin/env python3
"""Derive reviewed 1939 boundary geometry with structural-context records."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any, Mapping


class AmendmentError(ValueError):
    pass


def _sha(value: object, field: str) -> str:
    if (not isinstance(value, str) or len(value) != 64
            or any(char not in "0123456789abcdef" for char in value.lower())):
        raise AmendmentError(f"{field} er ugyldig")
    return value.lower()


def _ints(value: object, field: str) -> list[int]:
    if not isinstance(value, list) or any(type(item) is not int for item in value):
        raise AmendmentError(f"{field} skal være en liste af heltal")
    if len(value) != len(set(value)):
        raise AmendmentError(f"{field} har dubletter")
    return list(value)


def _spans(value: object, field: str) -> list[tuple[int, int]]:
    if not isinstance(value, list):
        raise AmendmentError(f"{field} skal være en liste")
    result = []
    for item in value:
        if not isinstance(item, Mapping) or set(item) != {"char_from", "char_to"}:
            raise AmendmentError(f"{field} har ugyldigt objekt")
        start, end = item["char_from"], item["char_to"]
        if type(start) is not int or type(end) is not int or start < 0 or end <= start:
            raise AmendmentError(f"{field} har ugyldigt spænd")
        result.append((start, end))
    result.sort()
    if len(result) != len(set(result)) or any(b_start < a_end for (_, a_end), (b_start, _) in zip(result, result[1:])):
        raise AmendmentError(f"{field} har dublet eller overlap")
    return result


def amend_export(data: Mapping[str, Any], decisions: Mapping[str, Any], *,
                 export_sha256: str) -> dict[str, Any]:
    expected = _sha(decisions.get("source_export_sha256"), "source_export_sha256")
    if _sha(export_sha256, "export_sha256") != expected:
        raise AmendmentError("grænseeksportens hash matcher ikke beslutningen")
    if decisions.get("schema_version") != "1.0":
        raise AmendmentError("decision schema_version 1.0 kræves")
    batch = decisions.get("decision_batch")
    if not isinstance(batch, str) or not batch.strip():
        raise AmendmentError("decision_batch kræves")
    remove_cuts = set(_ints(decisions.get("remove_cuts"), "remove_cuts"))
    add_cuts = set(_ints(decisions.get("add_cuts"), "add_cuts"))
    remove_omissions = set(_spans(decisions.get("remove_omissions"), "remove_omissions"))
    references = _spans(decisions.get("structural_references"), "structural_references")

    result = copy.deepcopy(dict(data))
    cuts = result.get("skaeringer")
    omissions = result.get("udeladelser")
    if not isinstance(cuts, list) or not isinstance(omissions, list):
        raise AmendmentError("grænseeksport mangler geometri")
    current_cuts = {item.get("char_offset") for item in cuts if isinstance(item, Mapping)}
    current_omissions = {
        (item.get("char_from"), item.get("char_to"))
        for item in omissions if isinstance(item, Mapping)
    }
    if not remove_cuts <= current_cuts or remove_omissions - current_omissions:
        raise AmendmentError("deklareret gammel geometri findes ikke")
    if add_cuts & (current_cuts - remove_cuts):
        raise AmendmentError("ny skæring findes allerede")
    effective_cuts = (current_cuts - remove_cuts) | add_cuts
    if any(start not in effective_cuts or end not in effective_cuts for start, end in references):
        raise AmendmentError("strukturel henvisning mangler eksakte skæringer")

    result["skaeringer"] = sorted(
        [item for item in cuts if item["char_offset"] not in remove_cuts]
        + [{"char_offset": offset, "oprindelse": "bruger"} for offset in add_cuts],
        key=lambda item: item["char_offset"],
    )
    result["udeladelser"] = [
        item for item in omissions
        if (item["char_from"], item["char_to"]) not in remove_omissions
    ]
    result["strukturelle_henvisninger"] = [{
        "char_from": start,
        "char_to": end,
        "record_kind": "structural_context",
        "person_creation": "forbidden",
    } for start, end in references]
    result["derived_from"] = {
        "source_export_sha256": expected,
        "decision_batch": batch,
    }
    return result


def _load(path: Path) -> tuple[bytes, Mapping[str, Any]]:
    try:
        payload = path.read_bytes()
        value = json.loads(payload.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AmendmentError("JSON-input kunne ikke læses") from exc
    if not isinstance(value, Mapping):
        raise AmendmentError("JSON-input skal være et objekt")
    return payload, value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("export", type=Path)
    parser.add_argument("--decisions", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    export_bytes, data = _load(args.export)
    _, decisions = _load(args.decisions)
    result = amend_export(
        data, decisions, export_sha256=hashlib.sha256(export_bytes).hexdigest()
    )
    try:
        with args.out.open("x", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
    except FileExistsError as exc:
        raise AmendmentError("outputfil findes allerede") from exc
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
