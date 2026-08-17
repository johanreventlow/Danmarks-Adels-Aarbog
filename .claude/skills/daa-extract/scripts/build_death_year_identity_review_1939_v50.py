#!/usr/bin/env python3
"""Build a review-only v50 identity package from principal death-year evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from build_identity_review_1939_v50 import WORD_RE


class DeathYearIdentityReviewError(ValueError):
    pass


def _fail(code: str, detail: str | None = None) -> None:
    raise DeathYearIdentityReviewError(code if detail is None else f"{code}: {detail}")


def _text(value: Any) -> str:
    if not isinstance(value, str) or not value:
        _fail("DEATH_YEAR_IDENTITY_INPUT_INVALID")
    return value


def _integer(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        _fail("DEATH_YEAR_IDENTITY_INPUT_INVALID")
    return value


def _sha(value: Any) -> str:
    value = _text(value)
    if len(value) != 64 or any(char not in "0123456789abcdef" for char in value):
        _fail("DEATH_YEAR_IDENTITY_HASH_INVALID")
    return value


YEAR_RE = re.compile(r"\b1[2-9]\d{2}\b")
KINSHIP_RE = re.compile(
    r"\b(?:fader\s+til|moder\s+til|hvis\s+søn|hvis\s+datter|"
    r"der\s+havde\s+søn(?:nen|nerne)?|havde\s+søn(?:nen|nerne)?|"
    r"der\s+havde\s+datter(?:en|døtrene)?|havde\s+datter(?:en|døtrene)?)\b",
    re.IGNORECASE,
)


def principal_end(source: str) -> int:
    match = KINSHIP_RE.search(source)
    return match.start() if match else len(source)


def literal_name_signal(source: str, name: str, limit: int,
                        record_key: str) -> dict[str, Any] | None:
    words = WORD_RE.findall(name)
    if not words:
        return None
    pattern = re.compile(
        r"(?<!\w)" + r"\s+".join(re.escape(word) for word in words) + r"(?!\w)")
    found = pattern.search(source, 0, limit)
    if found is None:
        return None
    start, end = found.span()
    return {
        "kind": "literal_name",
        "source_start": start,
        "source_end": end,
        "text": source[start:end],
        "profile_source": {
            "kind": "profile",
            "id": record_key,
            "field": "name",
        },
    }


def death_year_signals(source: str, limit: int,
                       profile: dict[str, Any]) -> list[dict[str, Any]]:
    source_years: dict[str, list[tuple[int, int]]] = {}
    for match in YEAR_RE.finditer(source, 0, limit):
        source_years.setdefault(match.group(), []).append(match.span())
    signals = []
    seen: set[tuple[str, int, int]] = set()
    for fact in profile.get("facts", []):
        if fact.get("fact_type") != "død":
            continue
        raw_value = fact.get("raw_value")
        if not isinstance(raw_value, str):
            continue
        for year in YEAR_RE.findall(raw_value):
            for start, end in source_years.get(year, []):
                key = (str(fact.get("fact_id")), start, end)
                if key in seen:
                    continue
                seen.add(key)
                signals.append({
                    "kind": "literal_death_year",
                    "source_start": start,
                    "source_end": end,
                    "text": source[start:end],
                    "profile_source": {
                        "kind": "fact",
                        "id": fact.get("fact_id"),
                        "field": "raw_value",
                    },
                    "fact_type": "død",
                })
    return sorted(signals, key=lambda row: (
        row["source_start"], row["source_end"], str(row["profile_source"]["id"])))


def qualifying_candidate(source: str,
                         profile: dict[str, Any]) -> dict[str, Any] | None:
    limit = principal_end(source)
    name_signal = literal_name_signal(
        source, profile["display_name"], limit, profile["record_key"])
    year_signals = death_year_signals(source, limit, profile)
    if name_signal is None or not year_signals:
        return None
    return {
        "candidate_record_key": profile["record_key"],
        "candidate_person_id": profile["person_id"],
        "candidate_display_name": profile["display_name"],
        "classification": "death_year_review_candidate",
        "proposed_action": "unresolved",
        "signals": [name_signal, *year_signals],
    }


def _validate_mapped_review(
        review: dict[str, Any]) -> tuple[list[dict[str, Any]], set[str]]:
    if (not isinstance(review, dict) or
        review.get("schema_version") != "1939-v50-mapped-identity-review-v1" or
        review.get("review_only") is not True or
        review.get("review_state") != "pending" or
        review.get("canonical_mutations_authorized") is not False or
        review.get("review_gate") != "GO" or
        review.get("identity_decision_gate") != "NO-GO" or
        review.get("reimport_gate") != "NO-GO"):
        _fail("DEATH_YEAR_IDENTITY_MAPPED_REVIEW_INVALID")
    subjects, counts = review.get("subjects"), review.get("counts")
    if (not isinstance(subjects, list) or not isinstance(counts, dict) or
        counts.get("subjects") != len(subjects)):
        _fail("DEATH_YEAR_IDENTITY_MAPPED_REVIEW_INVALID")
    seen: set[str] = set()
    for row in subjects:
        key = _text(row.get("new_record_key"))
        if (key in seen or row.get("review_state") != "pending" or
            row.get("person_creation") != "forbidden" or
            not isinstance(row.get("candidates"), list) or
            not isinstance(row.get("verbatim_text"), str) or
            not isinstance(row.get("source_span"), dict)):
            _fail("DEATH_YEAR_IDENTITY_MAPPED_REVIEW_INVALID")
        seen.add(key)
    candidate_links = sum(len(row["candidates"]) for row in subjects)
    linked = sum(bool(row["candidates"]) for row in subjects)
    ambiguous = sum(len(row["candidates"]) > 1 for row in subjects)
    unsearchable = review.get("unsearchable_profile_keys")
    if (counts.get("candidate_links") != candidate_links or
        counts.get("linked_subjects") != linked or
        counts.get("unlinked_subjects") != len(subjects) - linked or
        counts.get("ambiguous_subjects") != ambiguous or
        not isinstance(counts.get("profiles"), int) or
        not isinstance(counts.get("searchable_profiles"), int) or
        not isinstance(counts.get("unsearchable_profiles"), int) or
        counts["searchable_profiles"] + counts["unsearchable_profiles"] !=
        counts["profiles"] or not isinstance(unsearchable, list) or
        any(not isinstance(key, str) or not key for key in unsearchable) or
        len(set(unsearchable)) != counts["unsearchable_profiles"]):
        _fail("DEATH_YEAR_IDENTITY_MAPPED_REVIEW_INVALID")
    return subjects, set(unsearchable)


def _validate_decision_batches(
        batches: list[dict[str, Any]]) -> tuple[set[str], set[int]]:
    if not isinstance(batches, list) or not batches:
        _fail("DEATH_YEAR_IDENTITY_DECISIONS_INVALID")
    sources: set[str] = set()
    candidate_keys: set[str] = set()
    person_ids: set[int] = set()
    for batch in batches:
        if (not isinstance(batch, dict) or
            batch.get("schema_version") != "1939-v50-identity-decisions-v1" or
            batch.get("canonical_mutations_authorized") is not False or
            batch.get("database_write_authorized") is not False or
            batch.get("decision_gate") != "GO" or
            batch.get("source_persona_materialization_gate") != "NO-GO" or
            batch.get("database_gate") != "NO-GO" or
            batch.get("reimport_gate") != "NO-GO"):
            _fail("DEATH_YEAR_IDENTITY_DECISIONS_INVALID")
        rows, counts = batch.get("decisions"), batch.get("counts")
        if (not isinstance(rows, list) or not isinstance(counts, dict) or
            counts.get("decisions") != len(rows) or counts.get("same") != len(rows)):
            _fail("DEATH_YEAR_IDENTITY_DECISIONS_INVALID")
        for row in rows:
            source_key = _text(row.get("source_record_key"))
            candidate_key = _text(row.get("candidate_record_key"))
            person_id = _integer(row.get("canonical_person_id"))
            if (row.get("action") != "same" or
                row.get("database_write_authorized") is not False or
                source_key in sources or candidate_key in candidate_keys or
                person_id in person_ids):
                _fail("DEATH_YEAR_IDENTITY_DECISIONS_INVALID")
            sources.add(source_key)
            candidate_keys.add(candidate_key)
            person_ids.add(person_id)
    return sources, person_ids


def _validate_profiles(database_preview: dict[str, Any],
                       clean_records: list[dict[str, Any]],
                       expected_profiles: int,
                       declared_unsearchable: set[str]) -> tuple[
                           list[dict[str, Any]], set[str]]:
    if (not isinstance(database_preview, dict) or
        database_preview.get("schema_version") != "1939-v50-database-preview-v1" or
        database_preview.get("canonical_mutations_authorized") is not False or
        database_preview.get("dry_run_gate") != "NO-GO" or
        database_preview.get("reimport_gate") != "NO-GO"):
        _fail("DEATH_YEAR_IDENTITY_DATABASE_PREVIEW_INVALID")
    anchors = database_preview.get("person_anchors")
    if not isinstance(anchors, dict):
        _fail("DEATH_YEAR_IDENTITY_DATABASE_PREVIEW_INVALID")
    matched = anchors.get("matched")
    if (not isinstance(matched, list) or len(matched) != expected_profiles or
        anchors.get("matched_count") != len(matched) or
        anchors.get("missing_count") != 0 or anchors.get("collision_count") != 0):
        _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
    clean_by_key: dict[str, list[dict[str, Any]]] = {}
    if not isinstance(clean_records, list):
        _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
    for row in clean_records:
        if isinstance(row, dict) and isinstance(row.get("record_key"), str):
            clean_by_key.setdefault(row["record_key"], []).append(row)
    profiles = []
    observed_unsearchable: set[str] = set()
    seen_keys: set[str] = set()
    seen_people: set[int] = set()
    for anchor in matched:
        key = _text(anchor.get("baseline_record_key"))
        person_id = _integer(anchor.get("person_id"))
        rows = clean_by_key.get(key, [])
        if key in seen_keys or person_id in seen_people or len(rows) != 1:
            _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
        clean = rows[0]
        name = clean.get("navn")
        if not isinstance(name, str) or not name:
            if key not in declared_unsearchable:
                _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
            observed_unsearchable.add(key)
            seen_keys.add(key)
            seen_people.add(person_id)
            continue
        if key in declared_unsearchable:
            _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
        facts = []
        for index, fact in enumerate(clean.get("facts") or []):
            if not isinstance(fact, dict):
                _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
            raw = fact.get("date_raw") or fact.get("vaerdi")
            facts.append({
                "fact_id": f"{key}:fact:{index}",
                "fact_type": fact.get("faktatype") or "ukendt",
                "raw_value": raw if isinstance(raw, str) and raw else None,
            })
        profiles.append({
            "record_key": key, "person_id": person_id,
            "display_name": name, "facts": facts,
        })
        seen_keys.add(key)
        seen_people.add(person_id)
    if observed_unsearchable != declared_unsearchable:
        _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
    return sorted(profiles, key=lambda row: row["record_key"]), observed_unsearchable


def _validate_hashes(input_hashes: dict[str, Any], batch_count: int) -> dict[str, Any]:
    if not isinstance(input_hashes, dict) or set(input_hashes) != {
            "mapped_review_sha256", "database_preview_sha256", "clean_sha256",
            "identity_decision_sha256s"}:
        _fail("DEATH_YEAR_IDENTITY_HASH_INVALID")
    result = {
        "mapped_review_sha256": _sha(input_hashes["mapped_review_sha256"]),
        "database_preview_sha256": _sha(input_hashes["database_preview_sha256"]),
        "clean_sha256": _sha(input_hashes["clean_sha256"]),
    }
    decision_hashes = input_hashes["identity_decision_sha256s"]
    if not isinstance(decision_hashes, list) or len(decision_hashes) != batch_count:
        _fail("DEATH_YEAR_IDENTITY_HASH_INVALID")
    result["identity_decision_sha256s"] = [_sha(value) for value in decision_hashes]
    return result


def build_death_year_review(*, mapped_review: dict[str, Any],
                            database_preview: dict[str, Any],
                            clean_records: list[dict[str, Any]],
                            identity_decision_batches: list[dict[str, Any]],
                            input_hashes: dict[str, Any],
                            expected_subjects: int = 30,
                            expected_links: int = 11,
                            expected_profiles: int = 543) -> dict[str, Any]:
    hashes = _validate_hashes(input_hashes, len(identity_decision_batches))
    subjects, declared_unsearchable = _validate_mapped_review(mapped_review)
    if mapped_review["counts"]["profiles"] != expected_profiles:
        _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
    decided_sources, decided_people = _validate_decision_batches(
        identity_decision_batches)
    profiles, unsearchable = _validate_profiles(
        database_preview, clean_records, expected_profiles,
        declared_unsearchable)
    if len(profiles) + len(unsearchable) != expected_profiles:
        _fail("DEATH_YEAR_IDENTITY_PROFILE_COVERAGE_INVALID")
    remaining = [row for row in subjects if row["new_record_key"] not in decided_sources]
    if len(remaining) != expected_subjects:
        _fail("DEATH_YEAR_IDENTITY_SUBJECT_COVERAGE_INVALID")

    output_subjects = []
    used_candidate_keys: set[str] = set()
    used_people: set[int] = set()
    for row in remaining:
        source = row["verbatim_text"]
        matches = [candidate for profile in profiles
                   if profile["person_id"] not in decided_people
                   if (candidate := qualifying_candidate(source, profile)) is not None]
        if len(matches) > 1:
            _fail("DEATH_YEAR_IDENTITY_AMBIGUOUS", row["new_record_key"])
        if matches:
            candidate = matches[0]
            candidate_key = candidate["candidate_record_key"]
            person_id = candidate["candidate_person_id"]
            if candidate_key in used_candidate_keys or person_id in used_people:
                _fail("DEATH_YEAR_IDENTITY_INJECTIVITY_INVALID")
            used_candidate_keys.add(candidate_key)
            used_people.add(person_id)
        output_subjects.append({
            "new_record_key": row["new_record_key"],
            "source_span": row["source_span"],
            "verbatim_text": source,
            "review_state": "pending",
            "person_creation": "forbidden",
            "candidates": matches,
        })
    link_count = sum(len(row["candidates"]) for row in output_subjects)
    if link_count != expected_links:
        _fail("DEATH_YEAR_IDENTITY_LINK_COVERAGE_INVALID")
    linked = sum(bool(row["candidates"]) for row in output_subjects)
    return {
        "schema_version": "1939-v50-death-year-identity-review-v1",
        "generator_version": "build_death_year_identity_review_1939_v50.py:v1",
        "input_hashes": hashes,
        "review_only": True,
        "review_state": "pending",
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {
            "subjects": len(output_subjects), "profiles": expected_profiles,
            "searchable_profiles": len(profiles),
            "unsearchable_profiles": len(unsearchable),
            "candidate_links": link_count, "linked_subjects": linked,
            "unlinked_subjects": len(output_subjects) - linked,
        },
        "subjects": output_subjects,
        "review_gate": "GO",
        "identity_decision_gate": "NO-GO",
        "database_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }


def render_markdown(result: dict[str, Any]) -> str:
    counts = result["counts"]
    lines = [
        "# DAA 1939 v50 death-year identity review",
        "",
        "Review-only kandidatpakke. Ingen identitets- eller databasebeslutning er autoriseret.",
        "",
        f"- subjects: {counts['subjects']}",
        f"- kandidatlinks: {counts['candidate_links']}",
        f"- uden link: {counts['unlinked_subjects']}",
        f"- identity decision: **{result['identity_decision_gate']}**",
        f"- database: **{result['database_gate']}**",
        f"- reimport: **{result['reimport_gate']}**",
        "",
        "## Kandidater",
        "",
    ]
    number = 0
    for row in result["subjects"]:
        for candidate in row["candidates"]:
            number += 1
            death_years = sorted({
                signal["text"] for signal in candidate["signals"]
                if signal["kind"] == "literal_death_year"})
            lines.append(
                f"{number}. `{row['new_record_key']}` → "
                f"`{candidate['candidate_record_key']}` "
                f"(person {candidate['candidate_person_id']}, "
                f"{candidate['candidate_display_name']}, død {', '.join(death_years)})")
    lines.append("")
    return "\n".join(lines)


def write_outputs(result: dict[str, Any], output_path: Path | str,
                  report_path: Path | str) -> None:
    output, report = Path(output_path), Path(report_path)
    if output.resolve() == report.resolve():
        _fail("DEATH_YEAR_IDENTITY_OUTPUT_INVALID")
    output.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    created = []
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


def _load_bytes(path: Path) -> tuple[bytes, Any]:
    payload = path.read_bytes()
    return payload, json.loads(payload)


def _digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mapped-review", required=True, type=Path)
    parser.add_argument("--database-preview", required=True, type=Path)
    parser.add_argument("--clean", required=True, type=Path)
    parser.add_argument("--identity-decisions", required=True, type=Path,
                        action="append")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-subjects", type=int, default=30)
    parser.add_argument("--expected-links", type=int, default=11)
    parser.add_argument("--expected-profiles", type=int, default=543)
    args = parser.parse_args(argv)

    mapped_bytes, mapped_review = _load_bytes(args.mapped_review)
    database_bytes, database_preview = _load_bytes(args.database_preview)
    clean_bytes, clean_records = _load_bytes(args.clean)
    decision_payloads = [_load_bytes(path) for path in args.identity_decisions]
    result = build_death_year_review(
        mapped_review=mapped_review,
        database_preview=database_preview,
        clean_records=clean_records,
        identity_decision_batches=[value for _, value in decision_payloads],
        input_hashes={
            "mapped_review_sha256": _digest(mapped_bytes),
            "database_preview_sha256": _digest(database_bytes),
            "clean_sha256": _digest(clean_bytes),
            "identity_decision_sha256s": [
                _digest(payload) for payload, _ in decision_payloads],
        },
        expected_subjects=args.expected_subjects,
        expected_links=args.expected_links,
        expected_profiles=args.expected_profiles,
    )
    write_outputs(result, args.output, args.report)
    print(json.dumps({
        "output": str(args.output), "report": str(args.report),
        **result["counts"], "database_write_authorized": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
