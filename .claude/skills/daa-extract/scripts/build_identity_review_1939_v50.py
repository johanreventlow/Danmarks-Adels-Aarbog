#!/usr/bin/env python3
"""Build a fail-closed, review-only identity package for DAA 1939 v50.

The output never decides identity. Candidate links require reproducible literal
signals and always remain unresolved pending a separate human decision.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = "1939-v50-identity-review-v1"
GENERATOR_VERSION = "build_identity_review_1939_v50.py:v1"
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
WORD_RE = re.compile(r"[^\W_]+", re.UNICODE)
KINSHIP_TRANSITION_RE = re.compile(
    r"\b(?:fader\s+til|moder\s+til|hvis\s+søn|hvis\s+datter|sønnerne|døtrene|"
    r"sønnesøn|datterdatter|søn\s+var|datter\s+var|havde\s+søn|havde\s+datter)\b",
    re.IGNORECASE,
)


class IdentityReviewError(ValueError):
    pass


def _fail(code: str, detail: str | None = None) -> None:
    raise IdentityReviewError(code if detail is None else f"{code}: {detail}")


def _text(value: Any, code: str = "IDENTITY_REVIEW_INPUT_INVALID") -> str:
    if not isinstance(value, str) or not value:
        _fail(code)
    return value


def _integer(value: Any, code: str = "IDENTITY_REVIEW_INPUT_INVALID") -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        _fail(code)
    return value


def _hash(value: Any) -> str:
    value = _text(value)
    if not HASH_RE.fullmatch(value):
        _fail("IDENTITY_REVIEW_HASH_INVALID")
    return value


def _canonical_sha(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _assert_keys(value: dict[str, Any], expected: set[str], code: str) -> None:
    if not isinstance(value, dict) or set(value) != expected:
        _fail(code)


def _find_all(text: str, needle: str) -> list[tuple[int, int]]:
    if not needle:
        return []
    result: list[tuple[int, int]] = []
    start = 0
    while True:
        index = text.find(needle, start)
        if index < 0:
            return result
        result.append((index, index + len(needle)))
        start = index + max(1, len(needle))


def _word_count(value: str) -> int:
    return len(WORD_RE.findall(value))


def _discriminating(value: str) -> bool:
    return _word_count(value) >= 2 and len("".join(WORD_RE.findall(value))) >= 8


def _best_literal_name(source: str, name: str) -> tuple[int, int, str] | None:
    """Return the longest exact, contiguous name fragment in source.

    Whitespace is never normalized into evidence. Token n-grams merely select
    a literal substring from the profile name, which is then searched exactly.
    """
    words = list(WORD_RE.finditer(name))
    candidates: list[tuple[int, int, str]] = []
    for size in range(len(words), 0, -1):
        # A person's display name can contain titles, estates and other tails.
        # Only a prefix anchored at the first name token may identify the
        # person; an isolated tail such as "Baroniet Brahe" is not a name.
        first = words[0]
        last = words[size - 1]
        needle = name[first.start():last.end()]
        for start, end in _find_all(source, needle):
            candidates.append((start, end, needle))
        if candidates:
            return min(candidates, key=lambda row: (row[0], row[1], row[2]))
    return None


def _signal(kind: str, source: str, start: int, end: int,
            profile_source: dict[str, Any], **extra: Any) -> dict[str, Any]:
    if start < 0 or end <= start or end > len(source):
        _fail("IDENTITY_REVIEW_SIGNAL_OFFSET_INVALID")
    return {
        "kind": kind,
        "source_start": start,
        "source_end": end,
        "text": source[start:end],
        "profile_source": profile_source,
        **extra,
    }


def _deduplicate_signals(signals: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[tuple[Any, ...]] = set()
    result = []
    for row in signals:
        source = row["profile_source"]
        key = (row["kind"], row["source_start"], row["source_end"],
               source.get("kind"), source.get("id"), source.get("field"))
        if key not in seen:
            seen.add(key)
            result.append(row)
    return sorted(result, key=lambda row: (
        row["source_start"], row["source_end"], row["kind"],
        str(row["profile_source"].get("id", ""))))


def _profile_signals(source: str, profile: dict[str, Any]) -> list[dict[str, Any]]:
    signals: list[dict[str, Any]] = []
    name_sources: list[tuple[str, Any, str]] = [
        ("profile", profile["record_key"], profile["display_name"]),
    ]
    for fact in profile["facts"]:
        if fact["fact_type"] == "navn" and fact.get("raw_value"):
            name_sources.append(("fact", fact["fact_id"], fact["raw_value"]))
    for source_kind, source_id, name in name_sources:
        found = _best_literal_name(source, name)
        if found is not None:
            start, end, literal = found
            if len("".join(WORD_RE.findall(literal))) >= 4:
                signals.append(_signal(
                    "literal_name", source, start, end,
                    {"kind": source_kind, "id": source_id, "field": "name"},
                    word_count=_word_count(literal),
                    discriminating=_discriminating(literal),
                ))

    stripped_source = source.strip()
    source_offset = source.find(stripped_source) if stripped_source else 0
    for narrative in profile["narratives"]:
        narrative_text = (narrative.get("text") or "").strip()
        if len(narrative_text) < 40:
            continue
        for start, end in _find_all(source, narrative_text):
            signals.append(_signal(
                "literal_narrative_overlap", source, start, end,
                {"kind": "narrative", "id": narrative["narrative_id"], "field": "text"},
                overlap_relation="profile_text_in_source",
            ))
        if stripped_source and len(stripped_source) >= 40 and stripped_source in narrative_text:
            signals.append(_signal(
                "literal_narrative_overlap", source, source_offset,
                source_offset + len(stripped_source),
                {"kind": "narrative", "id": narrative["narrative_id"], "field": "text"},
                overlap_relation="source_text_in_profile",
            ))

    for fact in profile["facts"]:
        if fact["fact_type"] == "navn":
            continue
        values: list[tuple[str, str]] = []
        if fact.get("raw_value"):
            values.append(("raw_value", fact["raw_value"]))
        citation = fact.get("citation")
        if isinstance(citation, dict) and citation.get("text"):
            values.append(("citation", citation["text"]))
        for field, value in values:
            if len(value.strip()) < 4:
                continue
            for start, end in _find_all(source, value):
                signals.append(_signal(
                    "literal_fact_value", source, start, end,
                    {"kind": "fact", "id": fact["fact_id"], "field": field},
                    fact_type=fact["fact_type"],
                ))

    own_id = profile["person_id"]
    for family in profile["families"]:
        for member in family["members"]:
            if member["person_id"] == own_id:
                continue
            found = _best_literal_name(source, member["display_name"])
            if found is not None and _discriminating(found[2]):
                start, end, literal = found
                signals.append(_signal(
                    "literal_family_name", source, start, end,
                    {"kind": "family", "id": family["family_id"], "field": "member_name"},
                    related_person_id=member["person_id"], word_count=_word_count(literal),
                ))

    for relation in profile["relations"]:
        related_name = (relation.get("object_display_name")
                        if relation.get("subject_person_id") == own_id
                        else relation.get("subject_display_name"))
        if related_name:
            found = _best_literal_name(source, related_name)
            if found is not None and _discriminating(found[2]):
                start, end, literal = found
                signals.append(_signal(
                    "literal_relation_name", source, start, end,
                    {"kind": "relation", "id": relation["relation_id"], "field": "related_name"},
                    role=relation["role"], word_count=_word_count(literal),
                ))
    return _deduplicate_signals(signals)


def _principal_placement(source: str, signals: list[dict[str, Any]]) -> bool:
    transition = KINSHIP_TRANSITION_RE.search(source)
    limit = transition.start() if transition is not None else min(len(source), 120)
    name_before_transition = any(
        row["kind"] == "literal_name" and row["source_start"] <= 120 and
        row["source_start"] < limit
        for row in signals
    )
    narrative_at_start = any(
        row["kind"] == "literal_narrative_overlap" and row["source_start"] == 0
        for row in signals
    )
    vital_fact_ids = {row["profile_source"]["id"] for row in signals
                      if row["kind"] == "literal_fact_value" and
                      row.get("fact_type") in {"fødsel", "død"}}
    return name_before_transition or (narrative_at_start and len(vital_fact_ids) >= 1)


def _qualifies(source: str, signals: list[dict[str, Any]]) -> bool:
    names = [row for row in signals if row["kind"] == "literal_name"]
    discriminating_names = [row for row in names if row["discriminating"]]
    narratives = [row for row in signals if row["kind"] == "literal_narrative_overlap"]
    fact_ids = {row["profile_source"]["id"] for row in signals
                if row["kind"] == "literal_fact_value" and
                row.get("fact_type") in {"fødsel", "død"}}
    related_names = [row for row in signals if row["kind"] in {
        "literal_family_name", "literal_relation_name"}]
    corroborating = bool(narratives or fact_ids or related_names)
    if not _principal_placement(source, signals):
        return False
    if discriminating_names and corroborating:
        return True
    if names and narratives and fact_ids:
        return True
    if names and fact_ids:
        return True
    if related_names and len(fact_ids) >= 2:
        return True
    return False


def _validate_inputs(import_preview: dict[str, Any], database_preview: dict[str, Any],
                     profiles: dict[str, Any], linked_records: list[dict[str, Any]],
                     input_hashes: dict[str, str], expected_subject_count: int,
                     expected_profile_count: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]],
                                                           dict[str, dict[str, Any]]]:
    _assert_keys(input_hashes, {"import_preview_sha256", "database_preview_sha256",
                                "database_profiles_sha256", "linked_clean_sha256"},
                 "IDENTITY_REVIEW_HASHES_INVALID")
    for value in input_hashes.values():
        _hash(value)
    if (not isinstance(import_preview, dict) or
        import_preview.get("schema_version") != "1939-v50-import-preview-v1" or
        import_preview.get("preview_gate") != "GO" or
        import_preview.get("reimport_gate") != "NO-GO" or
        import_preview.get("canonical_mutations_authorized") is not False or
        import_preview.get("source", {}).get("edition") != "1939"):
        _fail("IDENTITY_REVIEW_IMPORT_PREVIEW_INVALID")
    subjects = import_preview.get("genuinely_new_pending")
    if (not isinstance(subjects, list) or len(subjects) != expected_subject_count or
            import_preview.get("counts", {}).get("genuinely_new_pending") != len(subjects)):
        _fail("IDENTITY_REVIEW_SUBJECT_COVERAGE_INVALID")
    subject_keys = []
    for row in subjects:
        if not isinstance(row, dict) or row.get("person_creation") != "forbidden":
            _fail("IDENTITY_REVIEW_SUBJECT_INVALID")
        key = _text(row.get("new_record_key"))
        span = row.get("source_span")
        source = _text(row.get("verbatim_text"))
        if not isinstance(span, dict) or set(span) != {"char_from", "char_to"}:
            _fail("IDENTITY_REVIEW_SUBJECT_INVALID")
        start, end = _integer(span.get("char_from")), _integer(span.get("char_to"))
        if end <= start or end - start != len(source):
            _fail("IDENTITY_REVIEW_SUBJECT_INVALID")
        subject_keys.append(key)
    if len(set(subject_keys)) != len(subject_keys):
        _fail("IDENTITY_REVIEW_SUBJECT_COVERAGE_INVALID")

    if (not isinstance(database_preview, dict) or
        database_preview.get("schema_version") != "1939-v50-database-preview-v1" or
        database_preview.get("reimport_gate") != "NO-GO" or
        database_preview.get("canonical_mutations_authorized") is not False or
        database_preview.get("database", {}).get("transaction_read_only") != "on"):
        _fail("IDENTITY_REVIEW_DATABASE_PREVIEW_INVALID")
    anchors = database_preview.get("person_anchors", {}).get("database_only")
    anchor_keys = database_preview.get("person_anchors", {}).get("database_only_record_keys")
    if (not isinstance(anchors, list) or not isinstance(anchor_keys, list) or
            len(anchors) != expected_profile_count):
        _fail("IDENTITY_REVIEW_PROFILE_COVERAGE_INVALID")
    anchor_pairs = [(_text(row.get("record_key")), _integer(row.get("person_id"))) for row in anchors]
    if len(set(anchor_pairs)) != len(anchor_pairs) or sorted(key for key, _ in anchor_pairs) != sorted(anchor_keys):
        _fail("IDENTITY_REVIEW_PROFILE_COVERAGE_INVALID")

    if (not isinstance(profiles, dict) or
        profiles.get("schema_version") != "1939-v50-identity-db-profiles-v1" or
        profiles.get("review_only") is not True or
        profiles.get("canonical_mutations_authorized") is not False or
        profiles.get("database", {}).get("transaction_read_only") != "on" or
        profiles.get("input", {}).get("database_preview_sha256") != input_hashes["database_preview_sha256"] or
        profiles.get("input", {}).get("import_preview_input_hashes") !=
            import_preview.get("source", {}).get("input_hashes")):
        _fail("IDENTITY_REVIEW_DATABASE_PROFILES_INVALID")
    profile_rows = profiles.get("profiles")
    if (not isinstance(profile_rows, list) or len(profile_rows) != expected_profile_count or
        profiles.get("counts", {}).get("profiles") != len(profile_rows)):
        _fail("IDENTITY_REVIEW_PROFILE_COVERAGE_INVALID")
    profile_pairs = []
    for row in profile_rows:
        if not isinstance(row, dict):
            _fail("IDENTITY_REVIEW_DATABASE_PROFILES_INVALID")
        required = {"record_key", "person_id", "display_name", "staged", "narratives",
                    "facts", "relations", "families"}
        if set(row) != required or not all(isinstance(row[field], list)
                                           for field in ("narratives", "facts", "relations", "families")):
            _fail("IDENTITY_REVIEW_DATABASE_PROFILES_INVALID")
        profile_pairs.append((_text(row["record_key"]), _integer(row["person_id"])))
    if sorted(profile_pairs) != sorted(anchor_pairs) or len(set(profile_pairs)) != len(profile_pairs):
        _fail("IDENTITY_REVIEW_PROFILE_PAIR_MISMATCH")

    if not isinstance(linked_records, list):
        _fail("IDENTITY_REVIEW_LINKED_INVALID")
    linked_by_key: dict[str, list[dict[str, Any]]] = {}
    for row in linked_records:
        if not isinstance(row, dict):
            _fail("IDENTITY_REVIEW_LINKED_INVALID")
        key_value = row.get("record_key")
        if key_value is None or key_value == "":
            # Rows outside the declared 23-profile scope cannot become
            # candidates. Required profile keys are checked exactly below.
            continue
        key = _text(key_value)
        linked_by_key.setdefault(key, []).append(row)
    linked_selected: dict[str, dict[str, Any]] = {}
    for key, _ in profile_pairs:
        matches = linked_by_key.get(key, [])
        if len(matches) != 1:
            _fail("IDENTITY_REVIEW_LINKED_COVERAGE_INVALID", key)
        linked_selected[key] = matches[0]
    return subjects, sorted(profile_rows, key=lambda row: row["record_key"]), linked_selected


def build_identity_review(*, import_preview: dict[str, Any], database_preview: dict[str, Any],
                          database_profiles: dict[str, Any], linked_records: list[dict[str, Any]],
                          input_hashes: dict[str, str], expected_subject_count: int = 41,
                          expected_profile_count: int = 23) -> dict[str, Any]:
    subjects, profiles, linked = _validate_inputs(
        import_preview, database_preview, database_profiles, linked_records,
        input_hashes, expected_subject_count, expected_profile_count)

    profile_summaries = [{
        "record_key": row["record_key"],
        "person_id": row["person_id"],
        "display_name": row["display_name"],
        "staged": row["staged"],
        "linked_payload_sha256": _canonical_sha(linked[row["record_key"]]),
        "evidence_counts": {
            "narratives": len(row["narratives"]), "facts": len(row["facts"]),
            "relations": len(row["relations"]), "families": len(row["families"]),
        },
    } for row in profiles]

    output_subjects: list[dict[str, Any]] = []
    for source_row in subjects:
        source = source_row["verbatim_text"]
        candidates = []
        for profile in profiles:
            signals = _profile_signals(source, profile)
            if not _qualifies(source, signals):
                continue
            candidates.append({
                "candidate_record_key": profile["record_key"],
                "candidate_person_id": profile["person_id"],
                "candidate_display_name": profile["display_name"],
                "classification": "review_candidate",
                "proposed_action": "unresolved",
                "signals": signals,
                "competing_candidate_record_keys": [],
                "competing_subject_record_keys": [],
            })
        candidates.sort(key=lambda row: row["candidate_record_key"])
        candidate_keys = [row["candidate_record_key"] for row in candidates]
        for candidate in candidates:
            candidate["competing_candidate_record_keys"] = [
                key for key in candidate_keys if key != candidate["candidate_record_key"]]
        output_subjects.append({
            "new_record_key": source_row["new_record_key"],
            "source_span": source_row["source_span"],
            "verbatim_text": source,
            "review_state": "pending",
            "person_creation": "forbidden",
            "candidates": candidates,
        })

    subjects_by_profile: dict[str, list[str]] = {}
    for row in output_subjects:
        for candidate in row["candidates"]:
            subjects_by_profile.setdefault(candidate["candidate_record_key"], []).append(row["new_record_key"])
    for row in output_subjects:
        for candidate in row["candidates"]:
            candidate["competing_subject_record_keys"] = [
                key for key in subjects_by_profile[candidate["candidate_record_key"]]
                if key != row["new_record_key"]]

    links = sum(len(row["candidates"]) for row in output_subjects)
    ambiguous = sum(len(row["candidates"]) > 1 for row in output_subjects)
    reused = sum(len(set(keys)) > 1 for keys in subjects_by_profile.values())
    signal_counts: dict[str, int] = {}
    for row in output_subjects:
        for candidate in row["candidates"]:
            for signal in candidate["signals"]:
                signal_counts[signal["kind"]] = signal_counts.get(signal["kind"], 0) + 1

    return {
        "schema_version": SCHEMA_VERSION,
        "generator_version": GENERATOR_VERSION,
        "input_hashes": dict(sorted(input_hashes.items())),
        "review_only": True,
        "review_state": "pending",
        "canonical_mutations_authorized": False,
        "counts": {
            "subjects": len(output_subjects), "profiles": len(profile_summaries),
            "candidate_links": links,
            "linked_subjects": sum(bool(row["candidates"]) for row in output_subjects),
            "unlinked_subjects": sum(not row["candidates"] for row in output_subjects),
            "ambiguous_subjects": ambiguous,
            "profiles_competing_across_subjects": reused,
            "signals": dict(sorted(signal_counts.items())),
        },
        "profiles": profile_summaries,
        "subjects": output_subjects,
        "review_gate": "GO",
        "identity_decision_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }


def render_markdown(bundle: dict[str, Any]) -> str:
    counts = bundle["counts"]
    lines = [
        "# DAA 1939 v50 identity review",
        "",
        "Review-only kandidatpakke. Ingen identiteter eller databaseændringer er godkendt.",
        "",
        "## Dækning",
        f"- source subjects: {counts['subjects']}",
        f"- eksisterende kandidatprofiler: {counts['profiles']}",
        f"- kandidatlinks: {counts['candidate_links']}",
        f"- subjects med/uden kandidat: {counts['linked_subjects']}/{counts['unlinked_subjects']}",
        f"- tvetydige subjects: {counts['ambiguous_subjects']}",
        f"- profiler foreslået til flere subjects: {counts['profiles_competing_across_subjects']}",
        "",
        "## Kandidater",
    ]
    for row in bundle["subjects"]:
        if not row["candidates"]:
            continue
        lines.extend(["", f"### {row['new_record_key']}"])
        for candidate in row["candidates"]:
            kinds = sorted({signal["kind"] for signal in candidate["signals"]})
            lines.append(
                f"- {candidate['candidate_display_name']} (`{candidate['candidate_record_key']}`): "
                f"unresolved; {', '.join(kinds)}")
    lines.extend([
        "", "## Gates",
        f"- review manifest: **{bundle['review_gate']}**",
        f"- identitetsafgørelse: **{bundle['identity_decision_gate']}**",
        f"- reimport: **{bundle['reimport_gate']}**",
        "",
    ])
    return "\n".join(lines)


def write_outputs(bundle: dict[str, Any], output_path: Path | str,
                  report_path: Path | str) -> None:
    output = Path(output_path)
    report = Path(report_path)
    if output.resolve() == report.resolve():
        raise IdentityReviewError("IDENTITY_REVIEW_OUTPUT_INVALID")
    output.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    created: list[Path] = []
    try:
        with output.open("x", encoding="utf-8", newline="\n") as handle:
            created.append(output)
            json.dump(bundle, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        with report.open("x", encoding="utf-8", newline="\n") as handle:
            created.append(report)
            handle.write(render_markdown(bundle))
    except Exception:
        for path in created:
            path.unlink(missing_ok=True)
        raise


def _load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--import-preview", required=True, type=Path)
    parser.add_argument("--database-preview", required=True, type=Path)
    parser.add_argument("--database-profiles", required=True, type=Path)
    parser.add_argument("--linked-clean", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-subjects", type=int, default=41)
    parser.add_argument("--expected-profiles", type=int, default=23)
    args = parser.parse_args(argv)
    paths = [args.import_preview, args.database_preview, args.database_profiles, args.linked_clean]
    hashes = dict(zip(
        ("import_preview_sha256", "database_preview_sha256",
         "database_profiles_sha256", "linked_clean_sha256"),
        map(_file_sha, paths),
    ))
    bundle = build_identity_review(
        import_preview=_load_json(args.import_preview),
        database_preview=_load_json(args.database_preview),
        database_profiles=_load_json(args.database_profiles),
        linked_records=_load_json(args.linked_clean),
        input_hashes=hashes,
        expected_subject_count=args.expected_subjects,
        expected_profile_count=args.expected_profiles,
    )
    write_outputs(bundle, args.output, args.report)
    print(json.dumps({
        "output": os.fspath(args.output), "report": os.fspath(args.report),
        "counts": bundle["counts"], "review_only": True,
        "canonical_mutations_authorized": False,
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
