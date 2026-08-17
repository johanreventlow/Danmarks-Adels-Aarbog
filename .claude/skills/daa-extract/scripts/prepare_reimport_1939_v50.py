#!/usr/bin/env python3
"""Build a fail-closed, DB-free import preview from the approved 1939 v50."""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any, Mapping, Sequence


class PreviewError(ValueError):
    """Raised when preview input cannot be proven to be the approved v50 set."""


SCHEMA_VERSION = "1939-v50-import-preview-v1"
RECONCILIATION_KEYS = {
    "schema_version", "source", "decision_source", "baseline_entries",
    "new_entries", "report",
}
INPUT_HASH_KEYS = {
    "reconciliation_sha256", "reconciliation_report_sha256", "ledger_sha256",
    "materialization_sha256", "clean_sha256", "calamari_sha256",
}
ACTIVE_BASELINE_DISPOSITIONS = {"unchanged", "accepted_carryover"}
RETIRED_BASELINE_DISPOSITIONS = {"retired_duplicate", "retired_fragment"}
NEW_CLASS_BY_DISPOSITION = {
    "accepted_genuinely_new_source_record": "genuinely_new_pending",
    "accepted_structural_context": "source_only_structural",
    "accepted_cross_reference": "source_only_cross_reference",
}
V50_EXPECTED_COUNTS = {
    "mapped_existing": 543,
    "retired_legacy": 3,
    "genuinely_new_pending": 41,
    "source_only_structural": 6,
    "source_only_cross_reference": 2,
    "source_records": 592,
}
V50_PINNED_HASHES = {
    "reconciliation_sha256": "6e2749f98edb0aee0ec0240c06c3f46ab80d26e23ce0e7f5ed7f186895734b0b",
    "reconciliation_report_sha256": "4f56f13f6f532735ccb0f0fedce1b77042ed365e2ad6cfff278e74606a2cec03",
    "ledger_sha256": "a133665c2daa7a353815473a7f7ca96571e1038772a6b318173db29d5b64b4d2",
    "materialization_sha256": "73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f",
    "clean_sha256": "c68ace8bffd8d653c4af0aa24586c5c01c3d1f267efe74d546ddddd964b3551b",
    "calamari_sha256": "020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37",
}


def _fail(message: str) -> None:
    raise PreviewError(message)


def _sha256(value: object, field: str) -> str:
    if (not isinstance(value, str) or len(value) != 64
            or any(char not in "0123456789abcdef" for char in value.lower())):
        _fail(f"{field} skal være en gyldig SHA-256")
    return value.lower()


def _text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        _fail(f"{field} kræves")
    return value


def _mapping(value: object, field: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        _fail(f"{field} skal være et objekt")
    return value


def _list(value: object, field: str) -> list[Any]:
    if not isinstance(value, list):
        _fail(f"{field} skal være en liste")
    return value


def _closed_keys(value: Mapping[str, Any], allowed: set[str], field: str) -> None:
    extra = set(value) - allowed
    if extra:
        _fail(f"{field} har ukendte felter: {', '.join(sorted(extra))}")


def _span(value: object, source_length: int, field: str) -> tuple[int, int]:
    span = _mapping(value, field)
    if set(span) != {"char_from", "char_to"}:
        _fail(f"{field} har ukendte felter eller mangler positioner")
    start, end = span.get("char_from"), span.get("char_to")
    if (type(start) is not int or type(end) is not int or start < 0
            or end <= start or end > source_length):
        _fail(f"{field} er ugyldigt")
    return start, end


def _unique_by(rows: object, key_field: str, field: str) -> tuple[list[Mapping[str, Any]], dict[str, Mapping[str, Any]]]:
    ordered = _list(rows, field)
    result: dict[str, Mapping[str, Any]] = {}
    validated: list[Mapping[str, Any]] = []
    for raw in ordered:
        row = _mapping(raw, f"{field} entry")
        key = _text(row.get(key_field), f"{field}.{key_field}")
        if key in result:
            _fail(f"{field} har dublet {key_field}")
        result[key] = row
        validated.append(row)
    return validated, result


def _validate_report(reconciliation: Mapping[str, Any], standalone: object) -> None:
    report = _mapping(reconciliation.get("report"), "reconciliation report")
    external = _mapping(standalone, "standalone report")
    if report != external:
        _fail("standalone report matcher ikke reconciliation report")
    baseline = _list(reconciliation.get("baseline_entries"), "baseline_entries")
    new = _list(reconciliation.get("new_entries"), "new_entries")
    baseline_counts = dict(sorted(Counter(
        _mapping(row, "baseline entry").get("disposition") for row in baseline
    ).items()))
    new_counts = dict(sorted(Counter(
        _mapping(row, "new entry").get("disposition") for row in new
    ).items()))
    if (report.get("baseline_total") != len(baseline)
            or report.get("new_total") != len(new)
            or report.get("baseline_dispositions") != baseline_counts
            or report.get("new_dispositions") != new_counts
            or report.get("remaining_baseline_review") != 0
            or report.get("remaining_new_review") != 0
            or report.get("reconciliation_gate") != "GO"):
        _fail("reconciliation report-regnskabet er inkonsistent")


def _validate_materialization(materialization: object, ledger: object,
                              calamari_text: str, calamari_sha256: str) -> dict[str, dict[str, Any]]:
    mat = _mapping(materialization, "materialization")
    if mat.get("schema_version") != "1.0":
        _fail("materialization schema_version 1.0 kræves")
    report = _mapping(mat.get("report"), "materialization report")
    if report.get("materialization_gate") != "GO" or report.get("unresolved_intervals") != 0:
        _fail("komplet GO-materialisering kræves")
    review = _mapping(mat.get("source_record_review"), "source_record_review")
    if review.get("schema_version") != "1.0":
        _fail("source_record_review schema_version 1.0 kræves")
    if (_sha256(review.get("rendition_sha256"), "rendition_sha256") != calamari_sha256
            or review.get("rendition_text") != calamari_text):
        _fail("materialisering matcher ikke den hashbundne Calamari-rendition")

    ledger_obj = _mapping(ledger, "ledger")
    if ledger_obj.get("schema_version") != "1.0":
        _fail("ledger schema_version 1.0 kræves")
    ledger_rows, _ = _unique_by(ledger_obj.get("entries"), "acceptance_id", "ledger entries")
    ledger_by_acceptance: dict[str, str] = {}
    ledger_record_keys: set[str] = set()
    for row in ledger_rows:
        acceptance_id = _text(row.get("acceptance_id"), "ledger acceptance_id")
        record_key = _text(row.get("record_key"), "ledger record_key")
        _sha256(row.get("immutable"), "ledger immutable")
        if record_key in ledger_record_keys:
            _fail("ledger har dublet record_key")
        ledger_record_keys.add(record_key)
        ledger_by_acceptance[acceptance_id] = record_key

    materialized = _list(review.get("records"), "materialized records")
    if len(materialized) != report.get("accepted_record_candidates"):
        _fail("materialiseringens recordoptælling stemmer ikke")
    by_key: dict[str, dict[str, Any]] = {}
    seen_acceptances: set[str] = set()
    previous_end = -1
    for raw in materialized:
        row = _mapping(raw, "materialized record")
        acceptance_id = _text(row.get("acceptance_id"), "materialized acceptance_id")
        if acceptance_id in seen_acceptances:
            _fail("materialisering har dublet acceptance_id")
        seen_acceptances.add(acceptance_id)
        record_key = ledger_by_acceptance.get(acceptance_id)
        if record_key is None:
            _fail("materialisering mangler i ledger")
        start, end = _span(row.get("source_anchor"), len(calamari_text), "materialisering span")
        if start < previous_end:
            _fail("materialiseringens source spans overlapper")
        verbatim = row.get("verbatim_text")
        if not isinstance(verbatim, str) or verbatim != calamari_text[start:end]:
            _fail("materialiseringens verbatim matcher ikke source span")
        by_key[record_key] = {
            "acceptance_id": acceptance_id,
            "new_record_key": record_key,
            "source_span": {"char_from": start, "char_to": end},
            "verbatim_text": verbatim,
        }
        previous_end = end
    if len(by_key) != len(materialized):
        _fail("materialisering har dublet record_key")
    return by_key


def _claim_candidate(raw: object, verbatim: str, retired: bool = False) -> dict[str, Any]:
    payload = dict(_mapping(raw, "claim"))
    if retired:
        status = "retired_source_record"
    else:
        excerpt = payload.get("kilde_span")
        if not isinstance(excerpt, str) or not excerpt:
            status = "missing_provenance"
        elif excerpt in verbatim:
            status = "source_bound_literal"
        else:
            status = "nonliteral_provenance"
    return {
        "legacy_payload": payload,
        "provenance_status": status,
        "authorized": False,
    }


def _source_record(new_entry: Mapping[str, Any], materialized: Mapping[str, Any]) -> dict[str, Any]:
    disposition = _text(new_entry.get("disposition"), "new disposition")
    owners = _list(new_entry.get("baseline_record_keys"), "baseline_record_keys")
    return {
        "new_record_key": materialized["new_record_key"],
        "acceptance_id": materialized["acceptance_id"],
        "record_kind": _text(new_entry.get("record_kind"), "new record_kind"),
        "disposition": disposition,
        "source_span": materialized["source_span"],
        "verbatim_text": materialized["verbatim_text"],
        "baseline_record_keys": list(owners),
        "person_creation": "requires_existing_anchor" if owners else "forbidden",
    }


def build_import_preview(*, reconciliation: object, reconciliation_report: object,
                         ledger: object, materialization: object, clean: object,
                         calamari_text: str, input_hashes: object,
                         expected_counts: object) -> dict[str, Any]:
    """Validate and compose a deterministic non-writing import preview."""
    recon = _mapping(reconciliation, "reconciliation")
    _closed_keys(recon, RECONCILIATION_KEYS, "reconciliation")
    if recon.get("schema_version") != "1.0":
        _fail("reconciliation schema_version 1.0 kræves")
    source = _mapping(recon.get("source"), "reconciliation source")
    if source.get("edition") != "1939":
        _fail("reconciliation edition 1939 kræves")

    hashes = _mapping(input_hashes, "input_hashes")
    if set(hashes) != INPUT_HASH_KEYS:
        _fail("input_hashes har ukendte felter eller mangler SHA-256")
    normalized_hashes = {key: _sha256(hashes.get(key), key) for key in sorted(INPUT_HASH_KEYS)}
    actual_calamari_sha = hashlib.sha256(calamari_text.encode("utf-8")).hexdigest()
    if normalized_hashes["calamari_sha256"] != actual_calamari_sha:
        _fail("calamari_sha256 matcher ikke Calamari-bytes")
    if _sha256(source.get("calamari_sha256"), "source calamari_sha256") != actual_calamari_sha:
        _fail("reconciliation matcher ikke Calamari SHA-256")

    _validate_report(recon, reconciliation_report)
    materialized_by_key = _validate_materialization(
        materialization, ledger, calamari_text, actual_calamari_sha
    )
    baseline_rows, baseline_by_key = _unique_by(
        recon.get("baseline_entries"), "baseline_record_key", "baseline_entries"
    )
    new_rows, new_by_key = _unique_by(
        recon.get("new_entries"), "new_record_key", "new_entries"
    )
    clean_rows, clean_by_key = _unique_by(clean, "record_key", "clean records")
    if set(clean_by_key) != set(baseline_by_key):
        _fail("clean record_keys dækker ikke baseline præcist")
    if set(new_by_key) != set(materialized_by_key):
        _fail("v50 new record_keys dækker ikke materialiseringen præcist")

    source_records = []
    for row in new_rows:
        key = row["new_record_key"]
        source_span = _span(row.get("source_span"), len(calamari_text), "v50 source span")
        mat = materialized_by_key[key]
        if source_span != (mat["source_span"]["char_from"], mat["source_span"]["char_to"]):
            _fail("v50 source span matcher ikke materialisering span")
        source_records.append(_source_record(row, mat))

    mapped_existing = []
    retired_legacy = []
    active_baseline_keys: set[str] = set()
    mapped_new_keys: set[str] = set()
    for baseline in baseline_rows:
        baseline_key = baseline["baseline_record_key"]
        disposition = _text(baseline.get("disposition"), "baseline disposition")
        clean_record = clean_by_key[baseline_key]
        if disposition in ACTIVE_BASELINE_DISPOSITIONS:
            matches = _list(baseline.get("matches"), "baseline matches")
            if len(matches) != 1:
                _fail("aktiv baseline skal have præcis én ejer/match")
            new_key = _text(_mapping(matches[0], "baseline match").get("new_record_key"), "match new_record_key")
            new_entry = new_by_key.get(new_key)
            if new_entry is None:
                _fail("baseline ejer ukendt new record")
            owners = new_entry.get("baseline_record_keys")
            if owners != [baseline_key] or new_key in mapped_new_keys:
                _fail("baseline/new ejerforbindelse er ikke entydig")
            mapped_new_keys.add(new_key)
            active_baseline_keys.add(baseline_key)
            verbatim = materialized_by_key[new_key]["verbatim_text"]
            facts = [_claim_candidate(row, verbatim) for row in _list(clean_record.get("facts", []), "facts")]
            marriages = [_claim_candidate(row, verbatim) for row in _list(clean_record.get("aegteskaber", []), "aegteskaber")]
            relationships = []
            if clean_record.get("boern"):
                relationships.append({
                    "kind": "children_reference",
                    "legacy_payload": clean_record["boern"],
                    "provenance_status": "legacy_structure_pending_revalidation",
                    "authorized": False,
                })
            legacy_narrative = clean_record.get("narrative")
            if legacy_narrative is not None and not isinstance(legacy_narrative, str):
                _fail("legacy narrative skal være tekst eller null")
            legacy_narrative = legacy_narrative or ""
            mapped_existing.append({
                "baseline_record_key": baseline_key,
                "new_record_key": new_key,
                "legacy_name": clean_record.get("navn"),
                "narrative_change": {
                    "legacy_sha256": hashlib.sha256(legacy_narrative.encode("utf-8")).hexdigest(),
                    "source_sha256": hashlib.sha256(verbatim.encode("utf-8")).hexdigest(),
                    "changed": legacy_narrative != verbatim,
                    "authorized": False,
                },
                "fact_candidates": facts,
                "marriage_candidates": marriages,
                "relationship_candidates": relationships,
            })
        elif disposition in RETIRED_BASELINE_DISPOSITIONS:
            facts = [_claim_candidate(row, "", retired=True) for row in _list(clean_record.get("facts", []), "facts")]
            marriages = [_claim_candidate(row, "", retired=True) for row in _list(clean_record.get("aegteskaber", []), "aegteskaber")]
            retired_legacy.append({
                "baseline_record_key": baseline_key,
                "disposition": disposition,
                "canonical_baseline_record_key": baseline.get("canonical_baseline_record_key"),
                "retirement_reason": baseline.get("retirement_reason"),
                "fact_candidates": facts,
                "marriage_candidates": marriages,
                "authorized": False,
            })
        else:
            _fail("baseline indeholder uløst eller ukendt disposition")

    genuinely_new_pending = []
    source_only_records = []
    for new_entry in new_rows:
        key = new_entry["new_record_key"]
        owners = _list(new_entry.get("baseline_record_keys"), "baseline_record_keys")
        disposition = _text(new_entry.get("disposition"), "new disposition")
        if disposition in {"unchanged", "accepted_carryover"}:
            if len(owners) != 1 or key not in mapped_new_keys or owners[0] not in active_baseline_keys:
                _fail("mapped new record har ugyldig ejer")
            continue
        if owners:
            _fail("ejerløs new-klasse har uventet owner/ejer")
        classification = NEW_CLASS_BY_DISPOSITION.get(disposition)
        source_record = next(record for record in source_records if record["new_record_key"] == key)
        if classification == "genuinely_new_pending":
            genuinely_new_pending.append({
                "new_record_key": key,
                "source_span": source_record["source_span"],
                "verbatim_text": source_record["verbatim_text"],
                "person_creation": "forbidden",
                "pending_gates": ["source_persona", "identity", "interpretation_provenance"],
            })
        elif classification in {"source_only_structural", "source_only_cross_reference"}:
            source_only_records.append({
                "new_record_key": key,
                "classification": classification,
                "record_kind": source_record["record_kind"],
                "source_span": source_record["source_span"],
                "verbatim_text": source_record["verbatim_text"],
                "person_creation": "forbidden",
            })
        else:
            _fail("new record indeholder uløst eller ukendt disposition")

    mapped_existing.sort(key=lambda row: row["baseline_record_key"])
    retired_legacy.sort(key=lambda row: row["baseline_record_key"])
    genuinely_new_pending.sort(key=lambda row: row["new_record_key"])
    source_only_records.sort(key=lambda row: row["new_record_key"])
    source_records.sort(key=lambda row: (row["source_span"]["char_from"], row["new_record_key"]))

    fact_counts = Counter(
        candidate["provenance_status"]
        for row in mapped_existing for candidate in row["fact_candidates"]
    )
    marriage_counts = Counter(
        candidate["provenance_status"]
        for row in mapped_existing for candidate in row["marriage_candidates"]
    )
    for row in retired_legacy:
        fact_counts.update(candidate["provenance_status"] for candidate in row["fact_candidates"])
        marriage_counts.update(candidate["provenance_status"] for candidate in row["marriage_candidates"])
    claim_statuses = [
        "source_bound_literal", "missing_provenance", "nonliteral_provenance",
        "retired_source_record",
    ]
    base_counts = {
        "mapped_existing": len(mapped_existing),
        "retired_legacy": len(retired_legacy),
        "genuinely_new_pending": len(genuinely_new_pending),
        "source_only_structural": sum(
            row["classification"] == "source_only_structural" for row in source_only_records
        ),
        "source_only_cross_reference": sum(
            row["classification"] == "source_only_cross_reference" for row in source_only_records
        ),
        "source_records": len(source_records),
    }
    expected = _mapping(expected_counts, "expected_counts")
    if base_counts != dict(expected):
        _fail(f"preview counts/optælling afviger: {base_counts!r}")
    counts = base_counts | {
        "facts": {status: fact_counts[status] for status in claim_statuses},
        "marriages": {status: marriage_counts[status] for status in claim_statuses},
        "relationships": {
            "legacy_structure_pending_revalidation": sum(
                len(row["relationship_candidates"]) for row in mapped_existing
            )
        },
    }
    return {
        "schema_version": SCHEMA_VERSION,
        "generator_version": "prepare_reimport_1939_v50.py:v1",
        "source": {
            "edition": "1939",
            "source_id": _mapping(materialization, "materialization")["source_record_review"]["source_id"],
            "rendition_id": _mapping(materialization, "materialization")["source_record_review"]["rendition_id"],
            "input_hashes": normalized_hashes,
        },
        "canonical_mutations_authorized": False,
        "counts": counts,
        "source_records": source_records,
        "mapped_existing": mapped_existing,
        "retired_legacy": retired_legacy,
        "genuinely_new_pending": genuinely_new_pending,
        "source_only_records": source_only_records,
        "expected_database_changes": {
            "source_record_candidates": [row["new_record_key"] for row in source_records],
            "legacy_retirement_candidates": [row["baseline_record_key"] for row in retired_legacy],
            "canonical_person_creates": [],
            "canonical_person_updates": [],
            "canonical_person_deletes": [],
            "authorized": False,
        },
        "preview_gate": "GO",
        "reimport_gate": "NO-GO",
        "reimport_blockers": [
            "genuinely_new_identity_pending",
            "claim_provenance_pending",
            "relationship_provenance_pending",
            "database_comparison_pending",
            "production_writer_not_authorized",
        ],
    }


def render_markdown(preview: Mapping[str, Any]) -> str:
    counts = preview["counts"]
    facts = counts["facts"]
    marriages = counts["marriages"]
    lines = [
        "# DAA 1939 v50 import-preview",
        "",
        "DB-fri og ikke-skrivende. Ingen canonical mutationer er autoriseret.",
        "",
        "## Kilderegnskab",
        f"- source records: {counts['source_records']}",
        f"- mapped existing: {counts['mapped_existing']}",
        f"- retired legacy: {counts['retired_legacy']}",
        f"- genuinely new pending: {counts['genuinely_new_pending']}",
        f"- structural source-only: {counts['source_only_structural']}",
        f"- cross-reference source-only: {counts['source_only_cross_reference']}",
        "",
        "## Provenance",
        f"- facts literal/missing/nonliteral/retired: {facts['source_bound_literal']}/{facts['missing_provenance']}/{facts['nonliteral_provenance']}/{facts['retired_source_record']}",
        f"- marriages literal/missing/nonliteral/retired: {marriages['source_bound_literal']}/{marriages['missing_provenance']}/{marriages['nonliteral_provenance']}/{marriages['retired_source_record']}",
        f"- relationer til genvalidering: {counts['relationships']['legacy_structure_pending_revalidation']}",
        "",
        f"- preview gate: **{preview['preview_gate']}**",
        f"- reimport gate: **{preview['reimport_gate']}**",
        "",
        "## Reimport-blokeringer",
    ]
    lines.extend(f"- `{blocker}`" for blocker in preview["reimport_blockers"])
    return "\n".join(lines) + "\n"


def write_preview_outputs(preview: Mapping[str, Any], bundle_path: Path,
                          report_path: Path) -> None:
    bundle_path = Path(bundle_path)
    report_path = Path(report_path)
    if bundle_path == report_path:
        raise ValueError("bundle og report skal have forskellige stier")
    handles = []
    created: list[Path] = []
    try:
        bundle_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        for path in (bundle_path, report_path):
            handles.append(path.open("x", encoding="utf-8"))
            created.append(path)
        json.dump(preview, handles[0], ensure_ascii=False, indent=2, sort_keys=True)
        handles[0].write("\n")
        handles[1].write(render_markdown(preview))
        for handle in handles:
            handle.close()
        handles.clear()
    except BaseException:
        for handle in handles:
            try:
                handle.close()
            except OSError:
                pass
        for path in created:
            try:
                path.unlink()
            except OSError:
                pass
        raise


def _read_json(path: Path) -> tuple[Any, str]:
    raw = path.read_bytes()
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reconciliation", type=Path, required=True)
    parser.add_argument("--reconciliation-report", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--materialization", type=Path, required=True)
    parser.add_argument("--clean", type=Path, required=True)
    parser.add_argument("--calamari", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(argv)

    reconciliation, reconciliation_sha = _read_json(args.reconciliation)
    reconciliation_report, report_sha = _read_json(args.reconciliation_report)
    ledger, ledger_sha = _read_json(args.ledger)
    materialization, materialization_sha = _read_json(args.materialization)
    clean, clean_sha = _read_json(args.clean)
    calamari_raw = args.calamari.read_bytes()
    calamari_text = calamari_raw.decode("utf-8")
    input_hashes = {
        "reconciliation_sha256": reconciliation_sha,
        "reconciliation_report_sha256": report_sha,
        "ledger_sha256": ledger_sha,
        "materialization_sha256": materialization_sha,
        "clean_sha256": clean_sha,
        "calamari_sha256": hashlib.sha256(calamari_raw).hexdigest(),
    }
    if input_hashes != V50_PINNED_HASHES:
        _fail("inputfiler matcher ikke den eksakte godkendte v50-kontrakt")
    preview = build_import_preview(
        reconciliation=reconciliation,
        reconciliation_report=reconciliation_report,
        ledger=ledger,
        materialization=materialization,
        clean=clean,
        calamari_text=calamari_text,
        input_hashes=input_hashes,
        expected_counts=V50_EXPECTED_COUNTS,
    )
    write_preview_outputs(preview, args.output, args.report)
    print(json.dumps({"output": str(args.output), "report": str(args.report),
                      "counts": preview["counts"], "reimport_gate": preview["reimport_gate"]},
                     ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
