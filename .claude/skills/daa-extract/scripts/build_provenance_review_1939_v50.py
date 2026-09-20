#!/usr/bin/env python3
"""Build the closed, review-only DAA 1939 v50 provenance manifest."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1939-v50-provenance-review-v1"
PRODUCTION_COUNTS = (130, 94, 81, 543, 8)
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
CATEGORY_ORDER = {"fact": 0, "marriage": 1, "relationship": 2}


class ProvenanceReviewError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ProvenanceReviewError(code)


def _text(value: Any, code: str = "PROVENANCE_REVIEW_INPUT_INVALID") -> str:
    if not isinstance(value, str) or not value:
        _fail(code)
    return value


def _integer(value: Any, code: str = "PROVENANCE_REVIEW_INPUT_INVALID",
             *, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        _fail(code)
    return value


def _hash(value: Any) -> str:
    value = _text(value, "PROVENANCE_REVIEW_HASH_INVALID")
    if not HASH_RE.fullmatch(value):
        _fail("PROVENANCE_REVIEW_HASH_INVALID")
    return value


def _validate_hashes(values: Any) -> dict[str, str]:
    expected = {
        "boundary_materialization_sha256", "calamari_sha256",
        "database_preview_sha256", "database_profiles_sha256",
        "import_preview_sha256", "reconciliation_sha256",
        "remaining_decisions_sha256", "source_persona_v2_sha256",
    }
    if not isinstance(values, dict) or set(values) != expected:
        _fail("PROVENANCE_REVIEW_HASH_INVALID")
    return {key: _hash(values[key]) for key in sorted(expected)}


def _span(value: Any) -> dict[str, int]:
    if not isinstance(value, dict) or set(value) != {"char_from", "char_to"}:
        _fail("PROVENANCE_REVIEW_SOURCE_INVALID")
    start = _integer(value.get("char_from"))
    end = _integer(value.get("char_to"))
    if end <= start:
        _fail("PROVENANCE_REVIEW_SOURCE_INVALID")
    return {"char_from": start, "char_to": end}


def _source_records(import_preview: dict[str, Any], calamari_text: str,
                    hashes: dict[str, str]) -> dict[str, dict[str, Any]]:
    if (not isinstance(import_preview, dict) or
            import_preview.get("schema_version") != "1939-v50-import-preview-v1" or
            import_preview.get("preview_gate") != "GO" or
            import_preview.get("reimport_gate") != "NO-GO" or
            import_preview.get("canonical_mutations_authorized") is not False or
            import_preview.get("source", {}).get("edition") != "1939" or
            import_preview.get("source", {}).get("input_hashes", {}).get("calamari_sha256") !=
            hashes["calamari_sha256"] or
            import_preview.get("source", {}).get("input_hashes", {}).get("reconciliation_sha256") !=
            hashes["reconciliation_sha256"] or
            import_preview.get("source", {}).get("input_hashes", {}).get("materialization_sha256") !=
            hashes["boundary_materialization_sha256"]):
        _fail("PROVENANCE_REVIEW_IMPORT_INVALID")
    rows = import_preview.get("source_records")
    if not isinstance(rows, list) or not isinstance(calamari_text, str):
        _fail("PROVENANCE_REVIEW_SOURCE_INVALID")
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            _fail("PROVENANCE_REVIEW_SOURCE_INVALID")
        key = _text(row.get("new_record_key"), "PROVENANCE_REVIEW_SOURCE_INVALID")
        span = _span(row.get("source_span"))
        text = _text(row.get("verbatim_text"), "PROVENANCE_REVIEW_SOURCE_INVALID")
        if span["char_to"] - span["char_from"] != len(text) or \
                calamari_text[span["char_from"]:span["char_to"]] != text or key in result:
            _fail("PROVENANCE_REVIEW_SOURCE_INVALID")
        result[key] = {"source_record_key": key, "source_span": span, "verbatim_text": text}
    return result


def _boundary_pages(boundary: dict[str, Any], source_records: dict[str, dict[str, Any]],
                    hashes: dict[str, str]) -> dict[str, dict[str, int]]:
    review = boundary.get("source_record_review") if isinstance(boundary, dict) else None
    if (not isinstance(review, dict) or boundary.get("schema_version") != "1.0" or
            review.get("schema_version") != "1.0" or review.get("source_id") != "1939" or
            review.get("rendition_id") != "daa-1939-calamari-r6-clean" or
            review.get("rendition_sha256") != hashes["calamari_sha256"] or
            not isinstance(review.get("records"), list)):
        _fail("PROVENANCE_REVIEW_BOUNDARY_INVALID")
    by_anchor: dict[tuple[int, int], dict[str, Any]] = {}
    for row in review["records"]:
        if not isinstance(row, dict):
            _fail("PROVENANCE_REVIEW_BOUNDARY_INVALID")
        anchor = _span(row.get("source_anchor"))
        key = (anchor["char_from"], anchor["char_to"])
        span = row.get("span")
        if (key in by_anchor or not isinstance(span, dict) or
                not isinstance(span.get("page_from"), int) or
                not isinstance(span.get("page_to"), int) or
                span["page_to"] < span["page_from"] or
                not isinstance(row.get("verbatim_text"), str)):
            _fail("PROVENANCE_REVIEW_BOUNDARY_INVALID")
        by_anchor[key] = row
    result = {}
    for key, source in source_records.items():
        source_span = source["source_span"]
        row = by_anchor.get((source_span["char_from"], source_span["char_to"]))
        if row is None or row.get("verbatim_text") != source["verbatim_text"]:
            _fail("PROVENANCE_REVIEW_BOUNDARY_INVALID")
        result[key] = {"page_from": row["span"]["page_from"],
                       "page_to": row["span"]["page_to"]}
    return result


def _validate_reconciliation(reconciliation: Any, source_count: int,
                             hashes: dict[str, str]) -> None:
    if (not isinstance(reconciliation, dict) or reconciliation.get("schema_version") != "1.0" or
            reconciliation.get("source", {}).get("edition") != "1939" or
            reconciliation.get("source", {}).get("calamari_sha256") != hashes["calamari_sha256"] or
            reconciliation.get("report", {}).get("reconciliation_gate") != "GO" or
            reconciliation.get("report", {}).get("remaining_baseline_review") != 0 or
            reconciliation.get("report", {}).get("remaining_new_review") != 0 or
            reconciliation.get("report", {}).get("new_total") != source_count or
            not isinstance(reconciliation.get("new_entries"), list) or
            len(reconciliation["new_entries"]) != source_count):
        _fail("PROVENANCE_REVIEW_RECONCILIATION_INVALID")


def _new_person_keys(source_persona_v2: Any, remaining_decisions: Any,
                     expected_new_persons: int) -> list[str]:
    if (not isinstance(source_persona_v2, dict) or
            source_persona_v2.get("schema_version") !=
            "1939-v50-source-persona-materialization-v2" or
            source_persona_v2.get("canonical_mutations_authorized") is not False or
            source_persona_v2.get("database_write_authorized") is not False or
            source_persona_v2.get("reimport_gate") != "NO-GO" or
            source_persona_v2.get("counts", {}).get("new_person_candidate") != expected_new_persons or
            source_persona_v2.get("counts", {}).get("unresolved") != 0):
        _fail("PROVENANCE_REVIEW_SOURCE_PERSONA_INVALID")
    candidates = source_persona_v2.get("new_person_candidates")
    if not isinstance(candidates, list) or len(candidates) != expected_new_persons:
        _fail("PROVENANCE_REVIEW_NEW_PERSON_COVERAGE_INVALID")
    persona_keys = [_text(row.get("source_record_key")) for row in candidates
                    if isinstance(row, dict)]
    if len(persona_keys) != len(candidates) or len(set(persona_keys)) != len(persona_keys):
        _fail("PROVENANCE_REVIEW_NEW_PERSON_COVERAGE_INVALID")
    if (not isinstance(remaining_decisions, dict) or
            remaining_decisions.get("schema_version") !=
            "1939-v50-remaining-identity-decisions-v1" or
            remaining_decisions.get("decision_gate") != "GO" or
            remaining_decisions.get("canonical_mutations_authorized") is not False or
            remaining_decisions.get("database_write_authorized") is not False or
            remaining_decisions.get("reimport_gate") != "NO-GO" or
            remaining_decisions.get("counts", {}).get("new_person_candidate") !=
            expected_new_persons or remaining_decisions.get("counts", {}).get("unresolved") != 0):
        _fail("PROVENANCE_REVIEW_DECISIONS_INVALID")
    decisions = remaining_decisions.get("decisions")
    if not isinstance(decisions, list):
        _fail("PROVENANCE_REVIEW_DECISIONS_INVALID")
    decision_keys = [_text(row.get("source_record_key")) for row in decisions
                     if isinstance(row, dict) and row.get("decision") == "new_person_candidate"]
    if sorted(decision_keys) != sorted(persona_keys):
        _fail("PROVENANCE_REVIEW_NEW_PERSON_COVERAGE_INVALID")
    return sorted(persona_keys)


def _profile_fact(value: Any) -> dict[str, Any]:
    expected = {"fact_id", "fact_type", "assertion_id", "raw_value", "citation",
                "editorial_events"}
    if not isinstance(value, dict) or set(value) != expected:
        _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
    _integer(value["fact_id"], minimum=1)
    _text(value["fact_type"])
    _integer(value["editorial_events"])
    return value


def _profile_relation(value: Any) -> dict[str, Any]:
    expected = {"relation_id", "role", "subject_person_id", "subject_display_name",
                "object_person_id", "object_display_name", "assertion_id", "raw_value",
                "citation", "editorial_events"}
    if not isinstance(value, dict) or set(value) != expected:
        _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
    _integer(value["relation_id"], minimum=1)
    _text(value["role"])
    _integer(value["editorial_events"])
    return value


def _profile_family(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"family_id", "members", "facts"}:
        _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
    _integer(value["family_id"], minimum=1)
    if not isinstance(value["members"], list) or not isinstance(value["facts"], list):
        _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
    for member in value["members"]:
        if not isinstance(member, dict) or set(member) != {
                "person_id", "role", "display_name", "editorial_events"}:
            _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
        _integer(member["person_id"], minimum=1)
        _text(member["role"])
        _integer(member["editorial_events"])
    for fact in value["facts"]:
        _profile_fact(fact)
    return value


def _profiles(database_profiles: Any, database_preview: Any, hashes: dict[str, str],
              expected_profiles: int) -> tuple[dict[str, dict[str, Any]], dict[str, int]]:
    if (not isinstance(database_preview, dict) or
            database_preview.get("schema_version") != "1939-v50-database-preview-v3" or
            database_preview.get("database", {}).get("transaction_read_only") != "on" or
            database_preview.get("canonical_mutations_authorized") is not False or
            database_preview.get("reimport_gate") != "NO-GO" or
            database_preview.get("input_preview", {}).get("sha256") !=
            hashes["import_preview_sha256"] or
            database_preview.get("person_anchors", {}).get("matched_count") != expected_profiles or
            database_preview.get("person_anchors", {}).get("missing_count") != 0 or
            database_preview.get("person_anchors", {}).get("collision_count") != 0 or
            database_preview.get("source_personas", {}).get("target_mismatch_count") != 0):
        _fail("PROVENANCE_REVIEW_DATABASE_INVALID")
    matched = database_preview.get("person_anchors", {}).get("matched")
    if not isinstance(matched, list) or len(matched) != expected_profiles:
        _fail("PROVENANCE_REVIEW_DATABASE_INVALID")
    targets = {}
    for row in matched:
        if not isinstance(row, dict):
            _fail("PROVENANCE_REVIEW_DATABASE_INVALID")
        key = _text(row.get("baseline_record_key"))
        person = _integer(row.get("person_id"), minimum=1)
        if key in targets or person in targets.values():
            _fail("PROVENANCE_REVIEW_DATABASE_INVALID")
        targets[key] = person
    if (not isinstance(database_profiles, dict) or
            database_profiles.get("schema_version") !=
            "1939-v50-provenance-db-profiles-v1" or
            database_profiles.get("input", {}).get("database_preview_sha256") !=
            hashes["database_preview_sha256"] or
            database_profiles.get("input", {}).get("import_preview_sha256") !=
            hashes["import_preview_sha256"] or
            database_profiles.get("database", {}).get("transaction_read_only") != "on" or
            database_profiles.get("review_only") is not True or
            database_profiles.get("database_write_authorized") is not False or
            database_profiles.get("canonical_mutations_authorized") is not False or
            database_profiles.get("counts", {}).get("profiles") != expected_profiles):
        _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
    rows = database_profiles.get("profiles")
    if not isinstance(rows, list) or len(rows) != expected_profiles:
        _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
    result = {}
    seen_person_ids = set()
    for row in rows:
        if not isinstance(row, dict) or set(row) != {
                "record_key", "person_id", "display_name", "staged", "narratives",
                "facts", "relations", "families"}:
            _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
        key = _text(row["record_key"])
        person_id = _integer(row["person_id"], minimum=1)
        if key in result or person_id in seen_person_ids or targets.get(key) != person_id or \
                not isinstance(row["staged"], bool) or not all(
                    isinstance(row[name], list) for name in ("narratives", "facts", "relations", "families")):
            _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
        for fact in row["facts"]:
            _profile_fact(fact)
        for relation in row["relations"]:
            _profile_relation(relation)
        for family in row["families"]:
            _profile_family(family)
        seen_person_ids.add(person_id)
        result[key] = row
    if set(result) != set(targets):
        _fail("PROVENANCE_REVIEW_PROFILE_INVALID")
    return result, targets


def _candidate(value: Any, category: str) -> dict[str, Any]:
    expected = {"authorized", "legacy_payload", "provenance_status"}
    if category == "relationship":
        expected.add("kind")
    if not isinstance(value, dict) or set(value) != expected or value.get("authorized") is not False or \
            not isinstance(value.get("legacy_payload"), dict):
        _fail("PROVENANCE_REVIEW_CANDIDATE_INVALID")
    allowed = {
        "fact": {"missing_provenance", "nonliteral_provenance"},
        "marriage": {"missing_provenance", "nonliteral_provenance"},
        "relationship": {"legacy_structure_pending_revalidation"},
    }
    if value.get("provenance_status") not in allowed[category]:
        _fail("PROVENANCE_REVIEW_CANDIDATE_INVALID")
    return value


def _signals(category: str, payload: dict[str, Any], source: str) -> list[dict[str, Any]]:
    declared = payload.get("kilde_span")
    if isinstance(declared, str) and declared:
        start = source.find(declared)
        if start >= 0:
            return [{"kind": "literal_declared_span", "text": declared,
                     "source_start": start, "source_end": start + len(declared),
                     "authoritative": True}]
    fields = ("date_raw", "vaerdi", "sted") if category == "fact" else \
        (("dato_raw", "partner_navn", "sted") if category == "marriage" else ())
    result = []
    for field in fields:
        value = payload.get(field)
        if not isinstance(value, str) or not value or len(value) < 3:
            continue
        start = source.find(value)
        if start >= 0 and all(row["text"] != value for row in result):
            result.append({"kind": "literal_raw_value", "text": value,
                           "source_start": start, "source_end": start + len(value),
                           "authoritative": False})
    return result


def _subject_id(category: str, baseline_key: str, source_key: str, index: int,
                payload: dict[str, Any]) -> str:
    canonical = json.dumps({"category": category, "baseline_record_key": baseline_key,
                            "source_record_key": source_key, "object_order": index,
                            "legacy_payload": payload},
                           ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return "provenance-" + hashlib.sha256(canonical.encode()).hexdigest()[:32]


def _build_provenance_review(*, import_preview: dict[str, Any],
                             source_persona_v2: dict[str, Any],
                             remaining_decisions: dict[str, Any],
                             database_preview: dict[str, Any],
                             database_profiles: dict[str, Any],
                             reconciliation: dict[str, Any],
                             boundary_materialization: dict[str, Any],
                             calamari_text: str, input_hashes: dict[str, str],
                             expected_facts: int, expected_marriages: int,
                             expected_relationships: int, expected_profiles: int,
                             expected_new_persons: int) -> dict[str, Any]:
    hashes = _validate_hashes(input_hashes)
    sources = _source_records(import_preview, calamari_text, hashes)
    pages = _boundary_pages(boundary_materialization, sources, hashes)
    _validate_reconciliation(reconciliation, len(sources), hashes)
    new_person_keys = _new_person_keys(source_persona_v2, remaining_decisions,
                                       expected_new_persons)
    profiles, targets = _profiles(database_profiles, database_preview, hashes,
                                  expected_profiles)
    mapped = import_preview.get("mapped_existing")
    if not isinstance(mapped, list) or len(mapped) != expected_profiles:
        _fail("PROVENANCE_REVIEW_MAPPED_COVERAGE_INVALID")
    seen_baseline = set()
    seen_source = set()
    subjects = []
    for mapped_row in mapped:
        if not isinstance(mapped_row, dict):
            _fail("PROVENANCE_REVIEW_MAPPED_COVERAGE_INVALID")
        baseline_key = _text(mapped_row.get("baseline_record_key"))
        source_key = _text(mapped_row.get("new_record_key"))
        if baseline_key in seen_baseline or source_key in seen_source or \
                baseline_key not in profiles or source_key not in sources:
            _fail("PROVENANCE_REVIEW_MAPPED_COVERAGE_INVALID")
        seen_baseline.add(baseline_key)
        seen_source.add(source_key)
        source = sources[source_key]
        profile = profiles[baseline_key]
        categories = (
            ("fact", mapped_row.get("fact_candidates"), profile["facts"]),
            ("marriage", mapped_row.get("marriage_candidates"), profile["families"]),
            ("relationship", mapped_row.get("relationship_candidates"), profile["relations"]),
        )
        for category, candidates, context in categories:
            if not isinstance(candidates, list):
                _fail("PROVENANCE_REVIEW_CANDIDATE_INVALID")
            for object_order, raw in enumerate(candidates):
                if category in {"fact", "marriage"} and isinstance(raw, dict) and \
                        raw.get("provenance_status") in {
                            "retired_source_record", "source_bound_literal"}:
                    continue
                candidate = _candidate(raw, category)
                payload = candidate["legacy_payload"]
                relevant_context = context
                if category == "fact":
                    fact_type = payload.get("faktatype")
                    relevant_context = [row for row in context if row.get("fact_type") == fact_type]
                subjects.append({
                    "review_subject_id": _subject_id(category, baseline_key, source_key,
                                                     object_order, payload),
                    "category": category,
                    "baseline_record_key": baseline_key,
                    "source_record_key": source_key,
                    "source_order": source["source_span"]["char_from"],
                    "object_order": object_order,
                    "provenance_status": candidate["provenance_status"],
                    "legacy_payload": payload,
                    "source_span": source["source_span"],
                    "verbatim_text": source["verbatim_text"],
                    "page_evidence": pages[source_key],
                    "canonical_target": {
                        "baseline_record_key": baseline_key,
                        "canonical_person_id": targets[baseline_key],
                        "display_name": profile["display_name"],
                        "staged": profile["staged"],
                    },
                    "database_context": relevant_context,
                    "evidence_signals": _signals(category, payload, source["verbatim_text"]),
                    "proposed_disposition": "unresolved",
                })
    if set(profiles) != seen_baseline:
        _fail("PROVENANCE_REVIEW_MAPPED_COVERAGE_INVALID")
    subjects.sort(key=lambda row: (CATEGORY_ORDER[row["category"]], row["source_order"],
                                   row["source_record_key"], row["object_order"],
                                   row["review_subject_id"]))
    actual = {
        "facts": sum(row["category"] == "fact" for row in subjects),
        "marriages": sum(row["category"] == "marriage" for row in subjects),
        "relationships": sum(row["category"] == "relationship" for row in subjects),
    }
    if actual != {"facts": expected_facts, "marriages": expected_marriages,
                  "relationships": expected_relationships} or \
            len({row["review_subject_id"] for row in subjects}) != len(subjects):
        _fail("PROVENANCE_REVIEW_SUBJECT_COVERAGE_INVALID")
    return {
        "schema_version": SCHEMA_VERSION,
        "generator_version": "build_provenance_review_1939_v50.py:v1",
        "input_hashes": hashes,
        "source": {"edition": "1939", "logical_source_id": "1939",
                   "database_source_id": database_preview["source"]["id"],
                   "rendition_id": "daa-1939-calamari-r6-clean"},
        "counts": {**actual, "subjects": len(subjects),
                   "mapped_profiles": expected_profiles,
                   "new_person_candidates": len(new_person_keys)},
        "new_person_candidate_keys": new_person_keys,
        "subjects": subjects,
        "review_only": True,
        "review_gate": "GO",
        "decision_gate": "NO-GO",
        "database_write_authorized": False,
        "canonical_mutations_authorized": False,
        "reimport_gate": "NO-GO",
    }


def build_provenance_review(*, import_preview: dict[str, Any],
                            source_persona_v2: dict[str, Any],
                            remaining_decisions: dict[str, Any],
                            database_preview: dict[str, Any],
                            database_profiles: dict[str, Any],
                            reconciliation: dict[str, Any],
                            boundary_materialization: dict[str, Any],
                            calamari_text: str, input_hashes: dict[str, str]) -> dict[str, Any]:
    return _build_provenance_review(
        import_preview=import_preview, source_persona_v2=source_persona_v2,
        remaining_decisions=remaining_decisions, database_preview=database_preview,
        database_profiles=database_profiles, reconciliation=reconciliation,
        boundary_materialization=boundary_materialization, calamari_text=calamari_text,
        input_hashes=input_hashes, expected_facts=PRODUCTION_COUNTS[0],
        expected_marriages=PRODUCTION_COUNTS[1],
        expected_relationships=PRODUCTION_COUNTS[2],
        expected_profiles=PRODUCTION_COUNTS[3], expected_new_persons=PRODUCTION_COUNTS[4])


def _report(value: dict[str, Any]) -> str:
    counts = value["counts"]
    lines = [
        "# DAA 1939 v50 provenance review v1", "",
        f"- Subjects: {counts['subjects']}",
        f"- Facts: {counts['facts']}",
        f"- Marriages: {counts['marriages']}",
        f"- Relationships: {counts['relationships']}",
        f"- Mapped profiles: {counts['mapped_profiles']}",
        f"- New person candidates: {counts['new_person_candidates']}",
        "- Review gate: GO", "- Decision gate: NO-GO",
        "- Database writes authorized: false", "",
        "Alle subjects starter unresolved. Dette er reviewevidens, ikke en skriveordre.", "",
    ]
    return "\n".join(lines)


def write_outputs(value: dict[str, Any], output: Path, report: Path) -> None:
    if output.exists() or report.exists():
        raise FileExistsError("provenance review output findes allerede")
    output.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    written = []
    try:
        with output.open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        written.append(output)
        with report.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(_report(value))
        written.append(report)
    except Exception:
        for path in written:
            path.unlink(missing_ok=True)
        raise


def _load(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--import-preview", required=True, type=Path)
    parser.add_argument("--source-personas", required=True, type=Path)
    parser.add_argument("--remaining-decisions", required=True, type=Path)
    parser.add_argument("--database-preview", required=True, type=Path)
    parser.add_argument("--database-profiles", required=True, type=Path)
    parser.add_argument("--reconciliation", required=True, type=Path)
    parser.add_argument("--boundary-materialization", required=True, type=Path)
    parser.add_argument("--calamari", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args(argv)
    paths = {
        "import_preview_sha256": args.import_preview,
        "source_persona_v2_sha256": args.source_personas,
        "remaining_decisions_sha256": args.remaining_decisions,
        "database_preview_sha256": args.database_preview,
        "database_profiles_sha256": args.database_profiles,
        "reconciliation_sha256": args.reconciliation,
        "boundary_materialization_sha256": args.boundary_materialization,
        "calamari_sha256": args.calamari,
    }
    value = build_provenance_review(
        import_preview=_load(args.import_preview),
        source_persona_v2=_load(args.source_personas),
        remaining_decisions=_load(args.remaining_decisions),
        database_preview=_load(args.database_preview),
        database_profiles=_load(args.database_profiles),
        reconciliation=_load(args.reconciliation),
        boundary_materialization=_load(args.boundary_materialization),
        calamari_text=args.calamari.read_text(encoding="utf-8"),
        input_hashes={key: _sha(path) for key, path in paths.items()},
    )
    write_outputs(value, args.output, args.report)
    print(json.dumps({"output": str(args.output), "counts": value["counts"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
