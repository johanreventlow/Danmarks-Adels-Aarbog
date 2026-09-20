#!/usr/bin/env python3
"""Build the closed, review-only DAA 1939 remaining-identity manifest."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from build_identity_review_1939_v50 import _profile_signals, _qualifies
from build_mapped_identity_review_1939_v50 import filter_principal_signals


SCHEMA_VERSION = "1939-v50-remaining-identity-review-v1"
PRODUCTION_COUNTS = (17, 543, 23)
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
WORD_RE = re.compile(r"[^\W_]+", re.UNICODE)


class RemainingIdentityReviewError(ValueError):
    pass


def _fail(code: str) -> None:
    raise RemainingIdentityReviewError(code)


def _text(value: Any, code: str = "REMAINING_IDENTITY_INPUT_INVALID") -> str:
    if not isinstance(value, str) or not value:
        _fail(code)
    return value


def _positive_int(value: Any, code: str = "REMAINING_IDENTITY_INPUT_INVALID") -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        _fail(code)
    return value


def _nonnegative_int(value: Any, code: str = "REMAINING_IDENTITY_INPUT_INVALID") -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        _fail(code)
    return value


def _hash(value: Any) -> str:
    value = _text(value, "REMAINING_IDENTITY_HASH_INVALID")
    if not HASH_RE.fullmatch(value):
        _fail("REMAINING_IDENTITY_HASH_INVALID")
    return value


def _hashes(input_hashes: dict[str, str]) -> dict[str, str]:
    expected = {
        "source_persona_sha256", "import_preview_sha256", "database_preview_sha256",
        "database_only_profiles_sha256", "clean_sha256",
        "boundary_materialization_sha256", "calamari_sha256",
    }
    if not isinstance(input_hashes, dict) or set(input_hashes) != expected:
        _fail("REMAINING_IDENTITY_HASH_INVALID")
    return {key: _hash(input_hashes[key]) for key in sorted(expected)}


def _subject(row: Any) -> dict[str, Any]:
    if not isinstance(row, dict) or set(row) != {
            "new_record_key", "pending_gates", "person_creation", "source_span", "verbatim_text"}:
        _fail("REMAINING_IDENTITY_SUBJECT_INVALID")
    key = _text(row.get("new_record_key"), "REMAINING_IDENTITY_SUBJECT_INVALID")
    source = _text(row.get("verbatim_text"), "REMAINING_IDENTITY_SUBJECT_INVALID")
    span = row.get("source_span")
    if (row.get("person_creation") != "forbidden" or not isinstance(row.get("pending_gates"), list) or
            not isinstance(span, dict) or set(span) != {"char_from", "char_to"}):
        _fail("REMAINING_IDENTITY_SUBJECT_INVALID")
    start = _nonnegative_int(span.get("char_from"), "REMAINING_IDENTITY_SUBJECT_INVALID")
    end = _nonnegative_int(span.get("char_to"), "REMAINING_IDENTITY_SUBJECT_INVALID")
    if end <= start or end - start != len(source):
        _fail("REMAINING_IDENTITY_SUBJECT_INVALID")
    return {"new_record_key": key, "source_span": {"char_from": start, "char_to": end},
            "verbatim_text": source}


def _source_record(row: Any) -> dict[str, Any]:
    if not isinstance(row, dict):
        _fail("REMAINING_IDENTITY_IMPORT_INVALID")
    key = _text(row.get("new_record_key"), "REMAINING_IDENTITY_IMPORT_INVALID")
    text = _text(row.get("verbatim_text"), "REMAINING_IDENTITY_IMPORT_INVALID")
    span = row.get("source_span")
    if not isinstance(span, dict) or set(span) != {"char_from", "char_to"}:
        _fail("REMAINING_IDENTITY_IMPORT_INVALID")
    start = _nonnegative_int(span.get("char_from"), "REMAINING_IDENTITY_IMPORT_INVALID")
    end = _nonnegative_int(span.get("char_to"), "REMAINING_IDENTITY_IMPORT_INVALID")
    if end <= start or end - start != len(text):
        _fail("REMAINING_IDENTITY_IMPORT_INVALID")
    return {"new_record_key": key, "source_span": {"char_from": start, "char_to": end},
            "verbatim_text": text}


def _validate_source_personas(source_persona_v1: dict[str, Any], hashes: dict[str, str],
                              expected_subjects: int) -> list[dict[str, Any]]:
    allowed = {
        "schema_version", "generator_version", "source", "counts", "source_personas",
        "remaining_genuinely_new_pending", "expected_database_changes",
        "canonical_mutations_authorized", "database_write_authorized",
        "source_persona_materialization_gate", "database_write_gate", "reimport_gate",
    }
    if (not isinstance(source_persona_v1, dict) or not set(source_persona_v1).issubset(allowed) or
            source_persona_v1.get("schema_version") != "1939-v50-source-persona-materialization-v1" or
            source_persona_v1.get("canonical_mutations_authorized") is not False or
            source_persona_v1.get("database_write_authorized") is not False or
            source_persona_v1.get("source_persona_materialization_gate") != "GO" or
            source_persona_v1.get("database_write_gate") != "NO-GO" or
            source_persona_v1.get("reimport_gate") != "NO-GO"):
        _fail("REMAINING_IDENTITY_SOURCE_PERSONAS_INVALID")
    source = source_persona_v1.get("source")
    input_hashes = source.get("input_hashes") if isinstance(source, dict) else None
    if (not isinstance(source, dict) or source.get("edition") != "1939" or
            not isinstance(input_hashes, dict) or
            input_hashes.get("import_preview_sha256") != hashes["import_preview_sha256"] or
            input_hashes.get("database_preview_sha256") != hashes["database_preview_sha256"]):
        _fail("REMAINING_IDENTITY_SOURCE_PERSONAS_INVALID")
    rows = source_persona_v1.get("remaining_genuinely_new_pending")
    if (not isinstance(rows, list) or len(rows) != expected_subjects or
            source_persona_v1.get("counts", {}).get("remaining_genuinely_new_pending") != len(rows)):
        _fail("REMAINING_IDENTITY_SUBJECT_COVERAGE_INVALID")
    subjects = [_subject(row) for row in rows]
    if len({row["new_record_key"] for row in subjects}) != len(subjects):
        _fail("REMAINING_IDENTITY_SUBJECT_COVERAGE_INVALID")
    return subjects


def _validate_import(import_preview: dict[str, Any], hashes: dict[str, str],
                     subjects: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if (not isinstance(import_preview, dict) or
            import_preview.get("schema_version") != "1939-v50-import-preview-v1" or
            import_preview.get("preview_gate") != "GO" or
            import_preview.get("reimport_gate") != "NO-GO" or
            import_preview.get("canonical_mutations_authorized") is not False or
            import_preview.get("source", {}).get("edition") != "1939" or
            import_preview.get("source", {}).get("input_hashes", {}).get("calamari_sha256") !=
            hashes["calamari_sha256"]):
        _fail("REMAINING_IDENTITY_IMPORT_INVALID")
    pending = import_preview.get("genuinely_new_pending")
    if not isinstance(pending, list):
        _fail("REMAINING_IDENTITY_IMPORT_INVALID")
    by_key = {_subject(row)["new_record_key"]: _subject(row) for row in pending}
    if len(by_key) != len(pending):
        _fail("REMAINING_IDENTITY_IMPORT_INVALID")
    for row in subjects:
        if by_key.get(row["new_record_key"]) != row:
            _fail("REMAINING_IDENTITY_SUBJECT_DRIFT")
    source_rows = import_preview.get("source_records", pending)
    if not isinstance(source_rows, list):
        _fail("REMAINING_IDENTITY_IMPORT_INVALID")
    records = [_source_record(row) for row in source_rows]
    if len({row["new_record_key"] for row in records}) != len(records):
        _fail("REMAINING_IDENTITY_IMPORT_INVALID")
    records_by_key = {row["new_record_key"]: row for row in records}
    for subject in subjects:
        if records_by_key.get(subject["new_record_key"]) != subject:
            _fail("REMAINING_IDENTITY_SUBJECT_DRIFT")
    return records


def _mapped_profile(clean: dict[str, Any], person_id: int) -> dict[str, Any]:
    key = _text(clean.get("record_key"), "REMAINING_IDENTITY_PROFILE_INVALID")
    name = clean.get("navn")
    if name is not None and (not isinstance(name, str) or not name):
        _fail("REMAINING_IDENTITY_PROFILE_INVALID")
    facts = []
    for index, fact in enumerate(clean.get("facts") or []):
        if not isinstance(fact, dict):
            _fail("REMAINING_IDENTITY_PROFILE_INVALID")
        raw = fact.get("date_raw") or fact.get("vaerdi")
        citation = fact.get("kilde_span")
        facts.append({"fact_id": f"{key}:fact:{index}",
                      "fact_type": fact.get("faktatype") or "ukendt",
                      "raw_value": raw if isinstance(raw, str) and raw else None,
                      "citation": {"text": citation} if isinstance(citation, str) and citation else None})
    return {"record_key": key, "person_id": person_id, "display_name": name,
            "staged": False, "narratives": [], "facts": facts,
            "relations": [], "families": []}


def _validate_profiles(database_preview: dict[str, Any], database_only_profiles: dict[str, Any],
                       clean_records: list[dict[str, Any]], hashes: dict[str, str],
                       expected_mapped: int, expected_database_only: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if (not isinstance(database_preview, dict) or
            database_preview.get("schema_version") != "1939-v50-database-preview-v1" or
            database_preview.get("canonical_mutations_authorized") is not False or
            database_preview.get("dry_run_gate") != "NO-GO" or
            database_preview.get("reimport_gate") != "NO-GO" or
            database_preview.get("database", {}).get("transaction_read_only") != "on" or
            database_preview.get("input_preview", {}).get("input_hashes", {}).get("calamari_sha256") != hashes["calamari_sha256"]):
        _fail("REMAINING_IDENTITY_DATABASE_INVALID")
    anchors = database_preview.get("person_anchors")
    if not isinstance(anchors, dict):
        _fail("REMAINING_IDENTITY_DATABASE_INVALID")
    matched = anchors.get("matched")
    db_only = anchors.get("database_only")
    if (not isinstance(matched, list) or not isinstance(db_only, list) or len(matched) != expected_mapped or
            len(db_only) != expected_database_only or anchors.get("matched_count") != len(matched) or
            anchors.get("missing_count") != 0 or anchors.get("collision_count") != 0):
        _fail("REMAINING_IDENTITY_PROFILE_COVERAGE_INVALID")
    mapped_pairs = [(_text(row.get("baseline_record_key"), "REMAINING_IDENTITY_PROFILE_COVERAGE_INVALID"),
                     _positive_int(row.get("person_id"), "REMAINING_IDENTITY_PROFILE_COVERAGE_INVALID"))
                    for row in matched if isinstance(row, dict)]
    db_pairs = [(_text(row.get("record_key"), "REMAINING_IDENTITY_PROFILE_COVERAGE_INVALID"),
                 _positive_int(row.get("person_id"), "REMAINING_IDENTITY_PROFILE_COVERAGE_INVALID"))
                for row in db_only if isinstance(row, dict)]
    if (len(mapped_pairs) != len(matched) or len(db_pairs) != len(db_only) or
            len(set(mapped_pairs)) != len(mapped_pairs) or len(set(db_pairs)) != len(db_pairs) or
            len({key for key, _ in mapped_pairs}) != len(mapped_pairs) or
            len({person for _, person in mapped_pairs}) != len(mapped_pairs) or
            len({key for key, _ in db_pairs}) != len(db_pairs) or
            len({person for _, person in db_pairs}) != len(db_pairs) or
            {key for key, _ in mapped_pairs} & {key for key, _ in db_pairs} or
            {person for _, person in mapped_pairs} & {person for _, person in db_pairs}):
        _fail("REMAINING_IDENTITY_PROFILE_COVERAGE_INVALID")
    if (not isinstance(database_only_profiles, dict) or
            database_only_profiles.get("schema_version") != "1939-v50-identity-db-profiles-v1" or
            database_only_profiles.get("review_only") is not True or
            database_only_profiles.get("canonical_mutations_authorized") is not False or
            database_only_profiles.get("database", {}).get("transaction_read_only") != "on" or
            database_only_profiles.get("input", {}).get("database_preview_sha256") != hashes["database_preview_sha256"]):
        _fail("REMAINING_IDENTITY_DATABASE_ONLY_INVALID")
    profiles = database_only_profiles.get("profiles")
    if (not isinstance(profiles, list) or len(profiles) != expected_database_only or
            database_only_profiles.get("counts", {}).get("profiles") != len(profiles)):
        _fail("REMAINING_IDENTITY_DATABASE_ONLY_INVALID")
    profile_pairs = []
    for profile in profiles:
        if not isinstance(profile, dict) or set(profile) != {
                "record_key", "person_id", "display_name", "staged", "narratives", "facts", "relations", "families"}:
            _fail("REMAINING_IDENTITY_DATABASE_ONLY_INVALID")
        profile_pairs.append((_text(profile["record_key"], "REMAINING_IDENTITY_DATABASE_ONLY_INVALID"),
                              _positive_int(profile["person_id"], "REMAINING_IDENTITY_DATABASE_ONLY_INVALID")))
    if (sorted(profile_pairs) != sorted(db_pairs) or len(set(profile_pairs)) != len(profile_pairs) or
            len({person for _, person in profile_pairs}) != len(profile_pairs)):
        _fail("REMAINING_IDENTITY_DATABASE_ONLY_INVALID")
    if not isinstance(clean_records, list):
        _fail("REMAINING_IDENTITY_PROFILE_COVERAGE_INVALID")
    clean_by_key: dict[str, list[dict[str, Any]]] = {}
    for clean in clean_records:
        if isinstance(clean, dict) and isinstance(clean.get("record_key"), str) and clean["record_key"]:
            clean_by_key.setdefault(clean["record_key"], []).append(clean)
    mapped_profiles = []
    for key, person_id in mapped_pairs:
        rows = clean_by_key.get(key, [])
        if len(rows) != 1:
            _fail("REMAINING_IDENTITY_PROFILE_COVERAGE_INVALID")
        mapped_profiles.append(_mapped_profile(rows[0], person_id))
    return (sorted(mapped_profiles, key=lambda row: row["record_key"]),
            sorted(profiles, key=lambda row: row["record_key"]))


def _source_record_index(source_records: list[dict[str, Any]]) -> tuple[dict[str, Any], ...]:
    return tuple({"record": row, "words": tuple(WORD_RE.finditer(row["verbatim_text"]))}
                 for row in sorted(source_records, key=lambda row: (
                     row["source_span"]["char_from"], row["new_record_key"])))


def _validate_boundary_evidence(boundary_materialization: dict[str, Any], hashes: dict[str, str],
                                source_records: list[dict[str, Any]], subjects: list[dict[str, Any]],
                                calamari_text: str) -> dict[str, dict[str, int]]:
    review = boundary_materialization.get("source_record_review") if isinstance(boundary_materialization, dict) else None
    if (not isinstance(review, dict) or review.get("schema_version") != "1.0" or
            review.get("source_id") != "1939" or review.get("rendition_sha256") != hashes["calamari_sha256"] or
            not isinstance(review.get("records"), list) or not isinstance(calamari_text, str)):
        _fail("REMAINING_IDENTITY_BOUNDARY_INVALID")
    boundary_by_source: dict[tuple[int, int, str], list[dict[str, Any]]] = {}
    for row in review["records"]:
        if not isinstance(row, dict):
            _fail("REMAINING_IDENTITY_BOUNDARY_INVALID")
        anchor, text = row.get("source_anchor"), row.get("verbatim_text")
        if (not isinstance(anchor, dict) or set(anchor) != {"char_from", "char_to"} or
                not isinstance(text, str) or not text):
            _fail("REMAINING_IDENTITY_BOUNDARY_INVALID")
        start = _nonnegative_int(anchor["char_from"], "REMAINING_IDENTITY_BOUNDARY_INVALID")
        end = _nonnegative_int(anchor["char_to"], "REMAINING_IDENTITY_BOUNDARY_INVALID")
        if end <= start or end - start != len(text):
            _fail("REMAINING_IDENTITY_BOUNDARY_INVALID")
        boundary_by_source.setdefault((start, end, text), []).append(row)
    pages_by_key = {}
    for record in source_records:
        span, text = record["source_span"], record["verbatim_text"]
        if calamari_text[span["char_from"]:span["char_to"]] != text:
            _fail("REMAINING_IDENTITY_CALAMARI_MISMATCH")
        matches = boundary_by_source.get((span["char_from"], span["char_to"], text), [])
        if len(matches) != 1:
            _fail("REMAINING_IDENTITY_BOUNDARY_INVALID")
        page = matches[0].get("span")
        if (not isinstance(page, dict) or set(page) - {"page_from", "page_to", "char_from", "char_to", "bbox"} or
                _positive_int(page.get("page_from"), "REMAINING_IDENTITY_BOUNDARY_INVALID") >
                _positive_int(page.get("page_to"), "REMAINING_IDENTITY_BOUNDARY_INVALID")):
            _fail("REMAINING_IDENTITY_BOUNDARY_INVALID")
        pages_by_key[record["new_record_key"]] = {"page_from": page["page_from"], "page_to": page["page_to"]}
    return {row["new_record_key"]: pages_by_key[row["new_record_key"]] for row in subjects}


def _normalize_ocr(value: str) -> str:
    value = re.sub(r"-\s*\n\s*", "", value)
    value = re.sub(r"\b([A-ZÆØÅ])\s+([A-ZÆØÅ])\b", r"\1\2", value)
    value = re.sub(r"\blven\b", "iven", value, flags=re.IGNORECASE)
    return " ".join(WORD_RE.findall(value)).casefold()


def _normalized_signal(source: str, name: str) -> dict[str, Any] | None:
    normalized_name = _normalize_ocr(name)
    if not normalized_name:
        return None
    name_words = WORD_RE.findall(name)
    if not name_words:
        return None
    source_words = list(WORD_RE.finditer(source))
    for index in range(len(source_words) - len(name_words) + 1):
        window = source_words[index:index + len(name_words)]
        if _normalize_ocr(" ".join(match.group() for match in window)) == normalized_name:
            return {"kind": "normalized_name",
                    "text": source[window[0].start():window[-1].end()],
                    "authoritative": False, "source_start": window[0].start(),
                    "source_end": window[-1].end()}
    return None


def _normalized_signal_from_words(source: str, source_words: tuple[re.Match[str], ...],
                                  normalized_name: str, name_word_count: int) -> dict[str, Any] | None:
    for index in range(len(source_words) - name_word_count + 1):
        window = source_words[index:index + name_word_count]
        if _normalize_ocr(" ".join(match.group() for match in window)) == normalized_name:
            return {"kind": "normalized_name",
                    "text": source[window[0].start():window[-1].end()],
                    "authoritative": False}
    return None


def _candidate_rows(source: str, profiles: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    candidates, presentations = [], []
    for profile in profiles:
        if not isinstance(profile.get("display_name"), str) or not profile["display_name"]:
            continue
        signals = filter_principal_signals(source, _profile_signals(source, profile))
        if _qualifies(source, signals):
            candidates.append({"candidate_record_key": profile["record_key"],
                               "candidate_person_id": profile["person_id"],
                               "candidate_display_name": profile["display_name"],
                               "classification": "review_candidate", "proposed_action": "unresolved",
                               "signals": signals})
        elif (signal := _normalized_signal(source, profile["display_name"])) is not None:
            presentations.append({"candidate_record_key": profile["record_key"],
                                  "candidate_person_id": profile["person_id"],
                                  "candidate_display_name": profile["display_name"],
                                  "classification": "presentation_only", "proposed_action": "unresolved",
                                  "signals": [signal]})
    return (sorted(candidates, key=lambda row: row["candidate_record_key"]),
            sorted(presentations, key=lambda row: row["candidate_record_key"]))


def _search_terms(rows: list[dict[str, Any]]) -> tuple[dict[str, Any], ...]:
    terms: dict[str, dict[str, Any]] = {}
    for row in rows:
        name = row["candidate_display_name"]
        words = WORD_RE.findall(name)
        normalized = _normalize_ocr(name)
        if words and normalized:
            terms.setdefault(normalized, {"literal": re.compile(
                r"(?<!\w)" + r"\s+".join(map(re.escape, words)) + r"(?!\w)", re.IGNORECASE),
                "normalized": normalized, "word_count": len(words)})
    return tuple(terms[key] for key in sorted(terms))


def _later_occurrences(subject: dict[str, Any], source_index: tuple[dict[str, Any], ...],
                       terms: tuple[dict[str, Any], ...]) -> list[dict[str, Any]]:
    result = []
    for indexed in source_index:
        record = indexed["record"]
        if record["new_record_key"] == subject["new_record_key"] or record["source_span"]["char_from"] <= subject["source_span"]["char_from"]:
            continue
        for term in terms:
            found = term["literal"].search(record["verbatim_text"])
            if found:
                signal = {"kind": "literal_name", "text": found.group(), "authoritative": True}
            else:
                signal = _normalized_signal_from_words(
                    record["verbatim_text"], indexed["words"], term["normalized"], term["word_count"])
            if signal is not None:
                result.append({"record_key": record["new_record_key"], "source_span": record["source_span"],
                               "signal": {key: signal[key] for key in ("kind", "text", "authoritative")}})
                break
    return sorted(result, key=lambda row: (row["source_span"]["char_from"], row["record_key"]))


def build_remaining_review(*, source_persona_v1: dict[str, Any], import_preview: dict[str, Any],
                           database_preview: dict[str, Any], database_only_profiles: dict[str, Any],
                           clean_records: list[dict[str, Any]], boundary_materialization: dict[str, Any],
                           calamari_text: str, input_hashes: dict[str, str], expected_subjects: int = 17,
                           expected_mapped_profiles: int = 543,
                           expected_database_only_profiles: int = 23) -> dict[str, Any]:
    hashes = _hashes(input_hashes)
    subjects = _validate_source_personas(source_persona_v1, hashes, expected_subjects)
    source_records = _validate_import(import_preview, hashes, subjects)
    mapped, database_only = _validate_profiles(
        database_preview, database_only_profiles, clean_records, hashes,
        expected_mapped_profiles, expected_database_only_profiles)
    pages = _validate_boundary_evidence(
        boundary_materialization, hashes, source_records, subjects, calamari_text)
    ordered = sorted(subjects, key=lambda row: (row["source_span"]["char_from"], row["new_record_key"]))
    profile_pool = [*mapped, *database_only]
    source_index = _source_record_index(source_records)
    output = []
    for index, row in enumerate(ordered):
        candidates, presentations = _candidate_rows(row["verbatim_text"], profile_pool)
        output.append({
            **row, "review_state": "pending", "page_evidence": pages[row["new_record_key"]],
            "previous_record": ({"new_record_key": ordered[index - 1]["new_record_key"],
                                 "source_span": ordered[index - 1]["source_span"]} if index else None),
            "next_record": ({"new_record_key": ordered[index + 1]["new_record_key"],
                            "source_span": ordered[index + 1]["source_span"]} if index + 1 < len(ordered) else None),
            "later_occurrences": _later_occurrences(
                row, source_index, _search_terms([*candidates, *presentations])),
            "candidates": candidates, "presentation_candidates": presentations,
        })
    return {"schema_version": SCHEMA_VERSION,
            "generator_version": "build_remaining_identity_review_1939_v50.py:v1",
            "input_hashes": hashes, "review_only": True, "review_state": "pending",
            "canonical_mutations_authorized": False, "database_write_authorized": False,
            "counts": {"subjects": len(output), "mapped_profiles": len(mapped),
                       "database_only_profiles": len(database_only), "profiles": len(profile_pool),
                       "candidate_links": sum(len(row["candidates"]) for row in output),
                       "presentation_only": sum(len(row["presentation_candidates"]) for row in output)},
            "subjects": output, "review_gate": "GO", "identity_decision_gate": "NO-GO",
            "database_gate": "NO-GO", "reimport_gate": "NO-GO"}


def render_markdown(result: dict[str, Any]) -> str:
    counts = result["counts"]
    lines = ["# DAA 1939 v50 remaining identity review", "",
             "Review-only manifest; alle forslag er unresolved.", "",
             f"- subjects: {counts['subjects']}", f"- mapped profiles: {counts['mapped_profiles']}",
             f"- database-only profiles: {counts['database_only_profiles']}",
             f"- identity decision: **{result['identity_decision_gate']}**", ""]
    for row in result["subjects"]:
        lines += [f"## {row['new_record_key']}", "", row["verbatim_text"].rstrip(), ""]
    return "\n".join(lines)


def write_outputs(result: dict[str, Any], output_path: Path | str, report_path: Path | str) -> None:
    output, report = Path(output_path), Path(report_path)
    if output.resolve() == report.resolve():
        _fail("REMAINING_IDENTITY_OUTPUT_INVALID")
    output.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    created = []
    try:
        with output.open("x", encoding="utf-8", newline="\n") as handle:
            created.append(output); json.dump(result, handle, ensure_ascii=False, indent=2); handle.write("\n")
        with report.open("x", encoding="utf-8", newline="\n") as handle:
            created.append(report); handle.write(render_markdown(result))
    except Exception:
        for path in created:
            path.unlink(missing_ok=True)
        raise


def _load(path: Path) -> tuple[bytes, Any]:
    payload = path.read_bytes()
    return payload, json.loads(payload)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-personas", required=True, type=Path)
    parser.add_argument("--import-preview", required=True, type=Path)
    parser.add_argument("--database-preview", required=True, type=Path)
    parser.add_argument("--database-profiles", required=True, type=Path)
    parser.add_argument("--clean", required=True, type=Path)
    parser.add_argument("--boundary-materialization", required=True, type=Path)
    parser.add_argument("--calamari", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-subjects", type=int, default=17)
    parser.add_argument("--expected-mapped-profiles", type=int, default=543)
    parser.add_argument("--expected-database-only-profiles", type=int, default=23)
    args = parser.parse_args(argv)
    if (args.expected_subjects, args.expected_mapped_profiles,
            args.expected_database_only_profiles) != PRODUCTION_COUNTS:
        _fail("REMAINING_IDENTITY_PRODUCTION_COUNTS_INVALID")
    source_bytes, source_personas = _load(args.source_personas)
    import_bytes, import_preview = _load(args.import_preview)
    database_bytes, database_preview = _load(args.database_preview)
    profiles_bytes, database_profiles = _load(args.database_profiles)
    clean_bytes, clean = _load(args.clean)
    boundary_bytes, boundary = _load(args.boundary_materialization)
    calamari_bytes = args.calamari.read_bytes()
    result = build_remaining_review(
        source_persona_v1=source_personas, import_preview=import_preview, database_preview=database_preview,
        database_only_profiles=database_profiles, clean_records=clean, boundary_materialization=boundary,
        calamari_text=calamari_bytes.decode("utf-8"), input_hashes={
            "source_persona_sha256": hashlib.sha256(source_bytes).hexdigest(),
            "import_preview_sha256": hashlib.sha256(import_bytes).hexdigest(),
            "database_preview_sha256": hashlib.sha256(database_bytes).hexdigest(),
            "database_only_profiles_sha256": hashlib.sha256(profiles_bytes).hexdigest(),
            "clean_sha256": hashlib.sha256(clean_bytes).hexdigest(),
            "boundary_materialization_sha256": hashlib.sha256(boundary_bytes).hexdigest(),
            "calamari_sha256": hashlib.sha256(calamari_bytes).hexdigest()},
        expected_subjects=args.expected_subjects, expected_mapped_profiles=args.expected_mapped_profiles,
        expected_database_only_profiles=args.expected_database_only_profiles)
    write_outputs(result, args.output, args.report)
    print(json.dumps({"output": str(args.output), "report": str(args.report), "counts": result["counts"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
