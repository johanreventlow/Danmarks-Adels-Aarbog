#!/usr/bin/env python3
"""Materialize approved v50 identities as a non-writing source-persona bundle."""
from __future__ import annotations

import argparse
import hashlib
import json
import uuid
from pathlib import Path
from typing import Any, Mapping


class SourcePersonaMaterializationError(ValueError):
    pass


def _fail(code: str, detail: str | None = None) -> None:
    raise SourcePersonaMaterializationError(
        code if detail is None else f"{code}: {detail}")


def _mapping(value: Any, code: str = "SOURCE_PERSONA_INPUT_INVALID") -> Mapping[str, Any]:
    if not isinstance(value, dict):
        _fail(code)
    return value


def _list(value: Any, code: str = "SOURCE_PERSONA_INPUT_INVALID") -> list[Any]:
    if not isinstance(value, list):
        _fail(code)
    return value


def _text(value: Any, code: str = "SOURCE_PERSONA_INPUT_INVALID") -> str:
    if not isinstance(value, str) or not value:
        _fail(code)
    return value


def _integer(value: Any, code: str = "SOURCE_PERSONA_INPUT_INVALID") -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        _fail(code)
    return value


def _sha(value: Any) -> str:
    value = _text(value, "SOURCE_PERSONA_HASH_INVALID")
    if len(value) != 64 or any(char not in "0123456789abcdef" for char in value):
        _fail("SOURCE_PERSONA_HASH_INVALID")
    return value


def _span(value: Any) -> dict[str, int]:
    span = _mapping(value)
    if set(span) != {"char_from", "char_to"}:
        _fail("SOURCE_PERSONA_SPAN_INVALID")
    start, end = span["char_from"], span["char_to"]
    if (isinstance(start, bool) or not isinstance(start, int) or start < 0 or
            isinstance(end, bool) or not isinstance(end, int) or end <= start):
        _fail("SOURCE_PERSONA_SPAN_INVALID")
    return {"char_from": start, "char_to": end}


def _persona_id(logical_source_id: str, record_key: str) -> str:
    return str(uuid.uuid5(
        uuid.NAMESPACE_URL,
        f"daa:source-persona:{logical_source_id}:{record_key}"))


def _validate_import_preview(preview: Any) -> tuple[str, dict[str, dict[str, Any]]]:
    preview = _mapping(preview)
    if (preview.get("schema_version") != "1939-v50-import-preview-v1" or
            preview.get("canonical_mutations_authorized") is not False or
            preview.get("preview_gate") != "GO" or
            preview.get("reimport_gate") != "NO-GO"):
        _fail("SOURCE_PERSONA_IMPORT_PREVIEW_INVALID")
    source = _mapping(preview.get("source"))
    if source.get("edition") != "1939":
        _fail("SOURCE_PERSONA_IMPORT_PREVIEW_INVALID")
    logical_source_id = _text(source.get("source_id"))
    counts = _mapping(preview.get("counts"))
    pending_rows = _list(preview.get("genuinely_new_pending"))
    source_rows = _list(preview.get("source_records"))
    if (counts.get("genuinely_new_pending") != len(pending_rows) or
            counts.get("source_records") != len(source_rows)):
        _fail("SOURCE_PERSONA_IMPORT_PREVIEW_INVALID")
    source_by_key: dict[str, Mapping[str, Any]] = {}
    for row in source_rows:
        row = _mapping(row)
        key = _text(row.get("new_record_key"))
        if key in source_by_key:
            _fail("SOURCE_PERSONA_IMPORT_PREVIEW_INVALID")
        source_by_key[key] = row
    pending_by_key: dict[str, dict[str, Any]] = {}
    required_gates = ["source_persona", "identity", "interpretation_provenance"]
    for raw in pending_rows:
        row = _mapping(raw)
        key = _text(row.get("new_record_key"))
        span = _span(row.get("source_span"))
        verbatim = _text(row.get("verbatim_text"))
        source_record = source_by_key.get(key)
        if (key in pending_by_key or source_record is None or
                row.get("person_creation") != "forbidden" or
                row.get("pending_gates") != required_gates or
                _span(source_record.get("source_span")) != span or
                source_record.get("verbatim_text") != verbatim or
                source_record.get("baseline_record_keys") != []):
            _fail("SOURCE_PERSONA_IMPORT_PREVIEW_INVALID", key)
        pending_by_key[key] = dict(row)
    changes = _mapping(preview.get("expected_database_changes"))
    if (changes.get("authorized") is not False or
            changes.get("canonical_person_creates") != [] or
            changes.get("canonical_person_updates") != [] or
            changes.get("canonical_person_deletes") != []):
        _fail("SOURCE_PERSONA_IMPORT_PREVIEW_INVALID")
    return logical_source_id, pending_by_key


def _validate_database_preview(preview: Any) -> tuple[int, dict[str, int]]:
    preview = _mapping(preview)
    if (preview.get("schema_version") != "1939-v50-database-preview-v1" or
            preview.get("canonical_mutations_authorized") is not False or
            preview.get("dry_run_gate") not in {"GO", "NO-GO"} or
            preview.get("reimport_gate") != "NO-GO"):
        _fail("SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    source = _mapping(preview.get("source"))
    database_source_id = _integer(source.get("id"))
    if source.get("udgave") != "DAA 1939" or source.get("import_key") != "daa:1939":
        _fail("SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    anchors = _mapping(preview.get("person_anchors"))
    rows = _list(anchors.get("matched"))
    if (anchors.get("matched_count") != len(rows) or
            anchors.get("missing_count") != len(_list(anchors.get("missing_record_keys"))) or
            anchors.get("collision_count") != len(_list(anchors.get("collisions")))):
        _fail("SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    by_key: dict[str, int] = {}
    person_ids: set[int] = set()
    for raw in rows:
        row = _mapping(raw)
        key = _text(row.get("baseline_record_key"))
        person_id = _integer(row.get("person_id"))
        if key in by_key or person_id in person_ids:
            _fail("SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
        by_key[key] = person_id
        person_ids.add(person_id)
    database_only_keys = _list(anchors.get("database_only_record_keys"))
    database_only = _list(anchors.get("database_only"))
    if len(database_only_keys) != len(database_only):
        _fail("SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    observed_database_only_keys = []
    for raw in database_only:
        row = _mapping(raw)
        key = _text(row.get("record_key"))
        person_id = _integer(row.get("person_id"))
        if key in by_key or person_id in person_ids:
            _fail("SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
        by_key[key] = person_id
        person_ids.add(person_id)
        observed_database_only_keys.append(key)
    if sorted(_text(value) for value in database_only_keys) != sorted(
            observed_database_only_keys):
        _fail("SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    changes = _mapping(preview.get("expected_database_changes"))
    if (changes.get("authorized") is not False or
            changes.get("canonical_person_creates") != [] or
            changes.get("canonical_person_updates") != [] or
            changes.get("canonical_person_deletes") != []):
        _fail("SOURCE_PERSONA_DATABASE_PREVIEW_INVALID")
    return database_source_id, by_key


def _validate_hashes(value: Any, batch_count: int) -> dict[str, Any]:
    hashes = _mapping(value)
    if set(hashes) != {"import_preview_sha256", "database_preview_sha256",
                       "identity_decision_sha256s"}:
        _fail("SOURCE_PERSONA_HASH_INVALID")
    decision_hashes = _list(hashes.get("identity_decision_sha256s"))
    if len(decision_hashes) != batch_count:
        _fail("SOURCE_PERSONA_HASH_INVALID")
    return {
        "database_preview_sha256": _sha(hashes.get("database_preview_sha256")),
        "identity_decision_sha256s": [_sha(value) for value in decision_hashes],
        "import_preview_sha256": _sha(hashes.get("import_preview_sha256")),
    }


def build_source_persona_materialization(
        *, import_preview: Any, database_preview: Any,
        identity_decision_batches: list[Any], input_hashes: Any,
        expected_decisions: int = 24,
        expected_remaining_pending: int = 17) -> dict[str, Any]:
    """Join explicit human decisions to source records and existing persons."""
    logical_source_id, pending_by_key = _validate_import_preview(import_preview)
    database_source_id, anchors = _validate_database_preview(database_preview)
    batches = _list(identity_decision_batches)
    if not batches:
        _fail("SOURCE_PERSONA_DECISIONS_INVALID")
    hashes = _validate_hashes(input_hashes, len(batches))

    seen_sources: set[str] = set()
    seen_candidates: set[str] = set()
    seen_persons: set[int] = set()
    personas = []
    for batch_index, raw_batch in enumerate(batches):
        batch = _mapping(raw_batch)
        rows = _list(batch.get("decisions"))
        counts = _mapping(batch.get("counts"))
        if (batch.get("schema_version") != "1939-v50-identity-decisions-v1" or
                batch.get("canonical_mutations_authorized") is not False or
                batch.get("database_write_authorized") is not False or
                batch.get("decision_gate") != "GO" or
                batch.get("source_persona_materialization_gate") != "NO-GO" or
                batch.get("database_gate") != "NO-GO" or
                batch.get("reimport_gate") != "NO-GO" or
                counts.get("decisions") != len(rows) or
                counts.get("same") != len(rows)):
            _fail("SOURCE_PERSONA_DECISIONS_INVALID")
        decision_batch = _text(batch.get("decision_batch"))
        confirmation = _text(batch.get("confirmation"))
        reviewed_by = _text(batch.get("reviewed_by"))
        for raw_row in rows:
            row = _mapping(raw_row)
            source_key = _text(row.get("source_record_key"))
            candidate_key = _text(row.get("candidate_record_key"))
            person_id = _integer(row.get("canonical_person_id"))
            provenance = _mapping(row.get("record_provenance"))
            pending = pending_by_key.get(source_key)
            if (row.get("action") != "same" or
                    row.get("source_persona_status") != "pending_materialization" or
                    row.get("database_write_authorized") is not False or
                    provenance.get("record_key") != source_key or
                    provenance.get("external_person_number") is not None or
                    pending is None or _span(row.get("source_span")) != pending["source_span"] or
                    anchors.get(candidate_key) != person_id):
                _fail("SOURCE_PERSONA_DECISION_INVALID", source_key)
            if (source_key in seen_sources or candidate_key in seen_candidates or
                    person_id in seen_persons):
                _fail("SOURCE_PERSONA_INJECTIVITY_INVALID", source_key)
            seen_sources.add(source_key)
            seen_candidates.add(candidate_key)
            seen_persons.add(person_id)
            persona_key = f"{logical_source_id}:{source_key}"
            personas.append({
                "source_persona_id": _persona_id(logical_source_id, source_key),
                "persona_key": persona_key,
                "source_id": database_source_id,
                "source_record_key": source_key,
                "source_span": pending["source_span"],
                "verbatim_text": pending["verbatim_text"],
                "target_record_key": candidate_key,
                "canonical_person_id": person_id,
                "identity_status": "accepted",
                "identity_decision": {
                    "decision_batch": decision_batch,
                    "decision_batch_sha256": hashes["identity_decision_sha256s"][batch_index],
                    "candidate_evidence_sha256": _sha(row.get("candidate_evidence_sha256")),
                    "confirmation": confirmation,
                    "reviewed_by": reviewed_by,
                },
                "database_write_authorized": False,
            })

    if len(personas) != expected_decisions:
        _fail("SOURCE_PERSONA_DECISION_COUNT_INVALID")
    remaining = [dict(row) for key, row in pending_by_key.items()
                 if key not in seen_sources]
    if len(remaining) != expected_remaining_pending:
        _fail("SOURCE_PERSONA_PENDING_COUNT_INVALID")
    personas.sort(key=lambda row: row["source_record_key"])
    remaining.sort(key=lambda row: row["new_record_key"])

    return {
        "schema_version": "1939-v50-source-persona-materialization-v1",
        "generator_version": "materialize_source_personas_1939_v50.py:v1",
        "source": {
            "edition": "1939", "logical_source_id": logical_source_id,
            "database_source_id": database_source_id,
            "input_hashes": hashes,
        },
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {
            "approved_identity_decisions": len(personas),
            "source_personas": len(personas),
            "accepted_identities": len(personas),
            "remaining_genuinely_new_pending": len(remaining),
        },
        "source_personas": personas,
        "remaining_genuinely_new_pending": remaining,
        "expected_database_changes": {
            "source_persona_candidates": [row["source_persona_id"] for row in personas],
            "source_persona_identity_candidates": [row["source_persona_id"] for row in personas],
            "canonical_person_creates": [], "canonical_person_updates": [],
            "canonical_person_deletes": [], "authorized": False,
        },
        "source_persona_materialization_gate": "GO",
        "database_write_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }


def render_markdown(result: Mapping[str, Any]) -> str:
    counts = result["counts"]
    lines = [
        "# DAA 1939 v50 source-persona materialization", "",
        "Hashbundet, DB-frit preview. Ingen databaseændringer er autoriseret.", "",
        f"- materialiserede source-personaer: {counts['source_personas']}",
        f"- accepterede identiteter: {counts['accepted_identities']}",
        f"- resterende nye identiteter: {counts['remaining_genuinely_new_pending']}",
        f"- materialisering: **{result['source_persona_materialization_gate']}**",
        f"- database-write: **{result['database_write_gate']}**",
        f"- reimport: **{result['reimport_gate']}**", "", "## Identiteter", "",
    ]
    for index, row in enumerate(result["source_personas"], 1):
        lines.append(
            f"{index}. `{row['source_record_key']}` → "
            f"`{row['target_record_key']}` (person {row['canonical_person_id']})")
    lines.append("")
    return "\n".join(lines)


def write_outputs(result: Mapping[str, Any], output_path: Path | str,
                  report_path: Path | str) -> None:
    output, report = Path(output_path), Path(report_path)
    if output.resolve() == report.resolve():
        _fail("SOURCE_PERSONA_OUTPUT_INVALID")
    output.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    created: list[Path] = []
    try:
        with output.open("x", encoding="utf-8", newline="\n") as handle:
            created.append(output)
            json.dump(result, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        with report.open("x", encoding="utf-8", newline="\n") as handle:
            created.append(report)
            handle.write(render_markdown(result))
    except Exception:
        for path in created:
            path.unlink(missing_ok=True)
        raise


def _read_json(path: Path) -> tuple[Any, str]:
    data = path.read_bytes()
    return json.loads(data), hashlib.sha256(data).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--import-preview", required=True, type=Path)
    parser.add_argument("--database-preview", required=True, type=Path)
    parser.add_argument("--identity-decisions", required=True, type=Path, nargs="+")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-decisions", type=int, default=24)
    parser.add_argument("--expected-remaining-pending", type=int, default=17)
    args = parser.parse_args(argv)
    import_preview, import_hash = _read_json(args.import_preview)
    database_preview, database_hash = _read_json(args.database_preview)
    batches, batch_hashes = [], []
    for path in args.identity_decisions:
        batch, digest = _read_json(path)
        batches.append(batch)
        batch_hashes.append(digest)
    result = build_source_persona_materialization(
        import_preview=import_preview, database_preview=database_preview,
        identity_decision_batches=batches,
        input_hashes={
            "import_preview_sha256": import_hash,
            "database_preview_sha256": database_hash,
            "identity_decision_sha256s": batch_hashes,
        },
        expected_decisions=args.expected_decisions,
        expected_remaining_pending=args.expected_remaining_pending,
    )
    write_outputs(result, args.output, args.report)
    print(json.dumps({"output": str(args.output),
                      "source_personas": result["counts"]["source_personas"],
                      "remaining_pending": result["counts"]["remaining_genuinely_new_pending"],
                      "database_write_authorized": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
