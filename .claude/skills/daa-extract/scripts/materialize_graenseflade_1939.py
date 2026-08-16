#!/usr/bin/env python3
"""Turn a reviewed 1939 boundary export into source-record review input.

The adapter preserves exact Calamari spans and deliberately does not mint
logical ``record_key`` values.  That remains the append-only ledger's job.
"""
from __future__ import annotations

import argparse
import bisect
import hashlib
import json
import re
from pathlib import Path
from typing import Any, Mapping

from rendition_occurrences_1939 import CALAMARI_R6_TO_PDF_V1
from source_record_ledger import LedgerError, materialize


PAGE_RE = re.compile(r"^### PAGE (\d+) ###$", re.M)
ALLOWED_CUT_ORIGINS = {"forudsat", "bruger", "forslag_godkendt"}


class MaterializationError(ValueError):
    """Raised when reviewed geometry cannot be materialized without guessing."""


def _require_text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise MaterializationError(f"{field} kræves")
    return value


def _require_sha256(value: object, field: str) -> str:
    text = _require_text(value, field).lower()
    if len(text) != 64 or any(char not in "0123456789abcdef" for char in text):
        raise MaterializationError(f"{field} er ugyldig")
    return text


def _pdf_page(source_page: int) -> int:
    for anchor, page in CALAMARI_R6_TO_PDF_V1:
        if source_page == anchor:
            return page
    for (left, left_pdf), (right, right_pdf) in zip(
        CALAMARI_R6_TO_PDF_V1, CALAMARI_R6_TO_PDF_V1[1:]
    ):
        if left < source_page < right:
            numerator = (source_page - left) * (right_pdf - left_pdf)
            denominator = right - left
            return left_pdf + (2 * numerator + denominator) // (2 * denominator)
    raise MaterializationError(f"kildeside {source_page} findes ikke i sidekortet")


def _validated_geometry(data: Mapping[str, Any], source_text: str) -> tuple[list[int], list[tuple[int, int]]]:
    if not isinstance(data, Mapping) or data.get("schema_version") != 1:
        raise MaterializationError("grænseeksport schema_version 1 kræves")
    source = data.get("source")
    if not isinstance(source, Mapping):
        raise MaterializationError("grænseeksport source kræves")
    if source.get("edition") != "1939" or source.get("profile_version") != "1939-v2":
        raise MaterializationError("grænseeksport har forkert edition eller profile_version")
    expected_hash = _require_sha256(source.get("calamari_sha256"), "calamari_sha256")
    actual_hash = hashlib.sha256(source_text.encode("utf-8")).hexdigest()
    if actual_hash != expected_hash:
        raise MaterializationError("kildetekst matcher ikke calamari_sha256")

    pages = data.get("sider")
    if not isinstance(pages, Mapping) or pages.get("identitet") != "kildeside":
        raise MaterializationError("sideidentitet skal være kildeside")
    total = pages.get("i_alt")
    reviewed = pages.get("gennemgaaet")
    if type(total) is not int or total < 1 or reviewed != list(range(1, total + 1)):
        raise MaterializationError("alle kildesider skal være gennemgået præcist én gang")
    observed_pages = [int(match.group(1)) for match in PAGE_RE.finditer(source_text)]
    if observed_pages != list(range(1, total + 1)):
        raise MaterializationError("kildetekstens sidemarkører matcher ikke sidegennemgangen")

    raw_cuts = data.get("skaeringer")
    if not isinstance(raw_cuts, list) or not raw_cuts:
        raise MaterializationError("grænseeksport kræver skæringer")
    cuts = []
    for item in raw_cuts:
        if not isinstance(item, Mapping):
            raise MaterializationError("skæring skal være et objekt")
        offset = item.get("char_offset")
        if type(offset) is not int or offset < 0 or offset >= len(source_text):
            raise MaterializationError("skæring ligger uden for kildeteksten")
        if item.get("oprindelse") not in ALLOWED_CUT_ORIGINS:
            raise MaterializationError("skæring har ukendt oprindelse")
        cuts.append(offset)
    if len(cuts) != len(set(cuts)):
        raise MaterializationError("grænseeksport har dublet skæring")
    cuts.sort()

    raw_omissions = data.get("udeladelser")
    if not isinstance(raw_omissions, list):
        raise MaterializationError("grænseeksport kræver udeladelser")
    omissions = []
    for item in raw_omissions:
        if not isinstance(item, Mapping):
            raise MaterializationError("udeladelse skal være et objekt")
        start, end = item.get("char_from"), item.get("char_to")
        if type(start) is not int or type(end) is not int or start < 0 or end <= start or end > len(source_text):
            raise MaterializationError("udeladelse ligger uden for kildeteksten")
        omissions.append((start, end))
    omissions.sort()
    if any(right_start < left_end for (_, left_end), (right_start, _) in zip(omissions, omissions[1:])):
        raise MaterializationError("grænseeksport har overlap mellem udeladelser")
    return cuts, omissions


def _meaningful_bounds(source_text: str, start: int, end: int,
                       omissions: list[tuple[int, int]],
                       page_markers: list[tuple[int, int]]) -> tuple[int, int] | None:
    ignored = sorted([*omissions, *page_markers])
    first = last = None
    ignored_index = 0
    for offset in range(start, end):
        while ignored_index < len(ignored) and ignored[ignored_index][1] <= offset:
            ignored_index += 1
        if ignored_index < len(ignored) and ignored[ignored_index][0] <= offset < ignored[ignored_index][1]:
            continue
        if source_text[offset].isspace():
            continue
        first = offset if first is None else first
        last = offset
    return None if first is None else (first, last)


def _page_span(page_starts: list[int], page_numbers: list[int], start: int, end: int) -> tuple[int, int]:
    first_index = bisect.bisect_right(page_starts, start) - 1
    last_index = bisect.bisect_left(page_starts, end) - 1
    if first_index < 0 or last_index < first_index:
        raise MaterializationError("kildepost mangler sikker sidemarkør")
    return _pdf_page(page_numbers[first_index]), _pdf_page(page_numbers[last_index])


def _acceptance_id(source_hash: str, start: int, end: int) -> str:
    payload = json.dumps(["1939", source_hash, start, end], separators=(",", ":"))
    return "boundary-acceptance-" + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:24]


def build_materialization(data: Mapping[str, Any], source_text: str, *,
                          rendition_id: str, extraction_run_id: str,
                          reviewed_by: str) -> dict[str, Any]:
    """Build a complete boundary account and accepted source-record review."""
    rendition_id = _require_text(rendition_id, "rendition_id")
    extraction_run_id = _require_text(extraction_run_id, "extraction_run_id")
    reviewed_by = _require_text(reviewed_by, "reviewed_by")
    if not isinstance(source_text, str) or not source_text:
        raise MaterializationError("kildetekst kræves")
    cuts, omissions = _validated_geometry(data, source_text)
    source_hash = hashlib.sha256(source_text.encode("utf-8")).hexdigest()

    page_matches = list(PAGE_RE.finditer(source_text))
    page_starts = [match.start() for match in page_matches]
    page_numbers = [int(match.group(1)) for match in page_matches]
    page_markers = [(match.start(), match.end()) for match in page_matches]

    prefix_omissions = [(max(0, start), min(cuts[0], end)) for start, end in omissions
                        if start < cuts[0] and end > 0]
    if _meaningful_bounds(source_text, 0, cuts[0], prefix_omissions, page_markers) is not None:
        raise MaterializationError("meningsbærende tekst før første skæring er uden ejer")

    records = []
    intervals = []
    omitted_count = unresolved_count = 0
    for order, interval_start in enumerate(cuts, start=1):
        interval_end = cuts[order] if order < len(cuts) else len(source_text)
        overlapping = [
            (max(interval_start, start), min(interval_end, end))
            for start, end in omissions if start < interval_end and end > interval_start
        ]
        bounds = _meaningful_bounds(
            source_text, interval_start, interval_end, overlapping, page_markers
        )
        base = {
            "order": order,
            "interval_span": {"char_from": interval_start, "char_to": interval_end},
            "omission_spans": [
                {"char_from": start, "char_to": end} for start, end in overlapping
            ],
        }
        if bounds is None:
            omitted_count += 1
            intervals.append({**base, "disposition": "omitted"})
            continue

        first_meaningful, last_meaningful = bounds
        splits = any(first_meaningful < start and end <= last_meaningful
                     for start, end in overlapping)
        if splits:
            unresolved_count += 1
            intervals.append({
                **base,
                "disposition": "unresolved",
                "reason": "omission_splits_meaningful_text",
            })
            continue

        record_start, record_end = interval_start, interval_end
        for start, end in overlapping:
            if end <= first_meaningful:
                record_start = max(record_start, end)
            if start > last_meaningful:
                record_end = min(record_end, start)
        if any(start < record_end and end > record_start for start, end in overlapping):
            raise MaterializationError("udeladelse blev ikke entydigt beskåret fra kildepost")

        page_from, page_to = _page_span(page_starts, page_numbers, record_start, record_end)
        verbatim_text = source_text[record_start:record_end]
        acceptance_id = _acceptance_id(source_hash, record_start, record_end)
        records.append({
            "acceptance_id": acceptance_id,
            "record_kind": "unclassified",
            "decision_status": "accepted",
            "reviewed_by": reviewed_by,
            "decision_version": 1,
            "verbatim_text": verbatim_text,
            "span": {
                "page_from": page_from,
                "page_to": page_to,
                "char_from": 0,
                "char_to": len(verbatim_text),
                "bbox": None,
            },
            "source_anchor": {"char_from": record_start, "char_to": record_end},
        })
        intervals.append({
            **base,
            "disposition": "accepted_record_candidate",
            "acceptance_id": acceptance_id,
            "record_span": {"char_from": record_start, "char_to": record_end},
        })

    report = {
        "materialization_gate": "GO" if unresolved_count == 0 else "NO-GO",
        "cut_intervals": len(cuts),
        "accepted_record_candidates": len(records),
        "omitted_intervals": omitted_count,
        "unresolved_intervals": unresolved_count,
    }
    return {
        "schema_version": "1.0",
        "source_record_review": {
            "schema_version": "1.0",
            "source_id": "1939",
            "rendition_id": rendition_id,
            "rendition_sha256": source_hash,
            "rendition_text": source_text,
            "extraction_run_id": extraction_run_id,
            "records": records,
        },
        "intervals": intervals,
        "report": report,
    }


def build_source_record_artifacts(materialization: Mapping[str, Any],
                                  ledger: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Mint stable record keys only for a complete, GO-gated materialization."""
    if not isinstance(materialization, Mapping):
        raise MaterializationError("materialisering skal være et objekt")
    report = materialization.get("report")
    if not isinstance(report, Mapping) or report.get("materialization_gate") != "GO":
        raise MaterializationError("materialization_gate er NO-GO")
    review = materialization.get("source_record_review")
    if not isinstance(review, Mapping):
        raise MaterializationError("source_record_review mangler")
    if len(review.get("records", [])) != report.get("accepted_record_candidates"):
        raise MaterializationError("source_record_review matcher ikke materialiseringsrapport")
    try:
        return materialize(review, ledger)
    except LedgerError as exc:
        raise MaterializationError("source-record ledger afviste materialiseringen") from exc


def _load_json(path: Path, label: str) -> Mapping[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result = {}
        for key, value in pairs:
            if key in result:
                raise MaterializationError(f"{label} har dublet JSON-feltnavn")
            result[key] = value
        return result

    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise MaterializationError(f"{label} kunne ikke læses") from exc
    if not isinstance(value, Mapping):
        raise MaterializationError(f"{label} skal være et JSON-objekt")
    return value


def _json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _write_outputs(outputs: list[tuple[Path, bytes]]) -> None:
    paths = [path for path, _ in outputs]
    if len(paths) != len(set(paths)):
        raise MaterializationError("outputstier skal være forskellige")
    created: list[Path] = []
    try:
        for path, payload in outputs:
            with path.open("xb") as handle:
                created.append(path)
                handle.write(payload)
    except FileExistsError as exc:
        for path in created:
            path.unlink(missing_ok=True)
        raise MaterializationError("outputfil findes allerede") from exc
    except BaseException:
        for path in created:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("export", type=Path)
    parser.add_argument("--calamari", type=Path, required=True)
    parser.add_argument("--reviewed-by", required=True)
    parser.add_argument("--rendition-id", required=True)
    parser.add_argument("--extraction-run-id", required=True)
    parser.add_argument("--ledger-in", type=Path)
    parser.add_argument("--materialization-out", type=Path, required=True)
    parser.add_argument("--ledger-out", type=Path, required=True)
    parser.add_argument("--bundle-out", type=Path, required=True)
    args = parser.parse_args(argv)

    data = _load_json(args.export, "grænseeksport")
    try:
        source_text = args.calamari.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise MaterializationError("Calamari-kildetekst kunne ikke læses") from exc
    ledger_in = (_load_json(args.ledger_in, "ledger") if args.ledger_in else
                 {"schema_version": "1.0", "entries": []})
    materialization = build_materialization(
        data,
        source_text,
        rendition_id=args.rendition_id,
        extraction_run_id=args.extraction_run_id,
        reviewed_by=args.reviewed_by,
    )
    ledger, bundle = build_source_record_artifacts(materialization, ledger_in)
    _write_outputs([
        (args.materialization_out, _json_bytes(materialization)),
        (args.ledger_out, _json_bytes(ledger)),
        (args.bundle_out, _json_bytes(bundle)),
    ])
    print(json.dumps(materialization["report"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
