#!/usr/bin/env python3
"""Review remaining v50 source records against already mapped DAA 1939 people."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from build_identity_review_1939_v50 import (
    KINSHIP_TRANSITION_RE, _best_literal_name, _profile_signals, _qualifies,
)


class MappedIdentityReviewError(ValueError):
    pass


def _fail(code: str) -> None:
    raise MappedIdentityReviewError(code)


def _text(value: Any) -> str:
    if not isinstance(value, str) or not value:
        _fail("MAPPED_IDENTITY_INPUT_INVALID")
    return value


def principal_name_before_transition(source: str, name: str) -> bool:
    found = _best_literal_name(source, name)
    if found is None:
        return False
    transition = KINSHIP_TRANSITION_RE.search(source)
    return found[0] <= 120 and (transition is None or found[0] < transition.start())


def filter_principal_signals(source: str, signals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    transition = KINSHIP_TRANSITION_RE.search(source)
    limit = transition.start() if transition is not None else len(source)
    result = []
    for signal in signals:
        if signal.get("kind") == "literal_fact_value" and \
                signal.get("fact_type") in {"fødsel", "død"}:
            if not re.search(r"\d{3,4}", signal.get("text", "")):
                continue
            if signal.get("source_start", len(source)) >= limit:
                continue
        result.append(signal)
    return result


def _profile(clean: dict[str, Any], person_id: int) -> dict[str, Any]:
    key = _text(clean.get("record_key"))
    name = clean.get("navn")
    if not isinstance(name, str) or not name:
        _fail("MAPPED_IDENTITY_PROFILE_NOT_SEARCHABLE")
    facts = []
    for index, fact in enumerate(clean.get("facts") or []):
        raw = fact.get("date_raw") or fact.get("vaerdi")
        citation = fact.get("kilde_span")
        facts.append({
            "fact_id": f"{key}:fact:{index}", "fact_type": fact.get("faktatype") or "ukendt",
            "raw_value": raw if isinstance(raw, str) and raw else None,
            "citation": ({"text": citation} if isinstance(citation, str) and citation else None),
        })
    families = []
    for index, marriage in enumerate(clean.get("aegteskaber") or []):
        partner = marriage.get("partner_navn")
        if isinstance(partner, str) and partner:
            families.append({"family_id": f"{key}:marriage:{index}", "members": [
                {"person_id": person_id, "display_name": name},
                {"person_id": -(index + 1), "display_name": partner},
            ]})
    narrative = clean.get("narrative")
    return {
        "record_key": key, "person_id": person_id,
        "display_name": name, "staged": False,
        "narratives": ([{"narrative_id": f"{key}:narrative", "text": narrative}]
                       if isinstance(narrative, str) and narrative else []),
        "facts": facts, "relations": [], "families": families,
    }


def build_mapped_review(*, import_preview: dict[str, Any], database_preview: dict[str, Any],
                        identity_decisions: dict[str, Any], clean_records: list[dict[str, Any]],
                        input_hashes: dict[str, str], expected_subjects: int = 32,
                        expected_profiles: int = 543) -> dict[str, Any]:
    if (import_preview.get("schema_version") != "1939-v50-import-preview-v1" or
        import_preview.get("preview_gate") != "GO" or
        import_preview.get("canonical_mutations_authorized") is not False or
        database_preview.get("schema_version") != "1939-v50-database-preview-v1" or
        database_preview.get("canonical_mutations_authorized") is not False or
        identity_decisions.get("schema_version") != "1939-v50-identity-decisions-v1" or
        identity_decisions.get("decision_gate") != "GO" or
        identity_decisions.get("canonical_mutations_authorized") is not False or
        identity_decisions.get("database_write_authorized") is not False):
        _fail("MAPPED_IDENTITY_INPUT_INVALID")
    expected_hash_keys = {"import_preview_sha256", "database_preview_sha256",
                          "identity_decisions_sha256", "clean_sha256"}
    if set(input_hashes) != expected_hash_keys or any(
            not isinstance(value, str) or len(value) != 64 for value in input_hashes.values()):
        _fail("MAPPED_IDENTITY_HASH_INVALID")
    approved = {_text(row.get("source_record_key")) for row in identity_decisions.get("decisions", [])}
    subjects = [row for row in import_preview.get("genuinely_new_pending", [])
                if row.get("new_record_key") not in approved]
    if len(subjects) != expected_subjects:
        _fail("MAPPED_IDENTITY_SUBJECT_COVERAGE_INVALID")
    mapped_keys = [_text(row.get("baseline_record_key")) for row in import_preview.get("mapped_existing", [])]
    if len(mapped_keys) != expected_profiles or len(set(mapped_keys)) != len(mapped_keys):
        _fail("MAPPED_IDENTITY_PROFILE_COVERAGE_INVALID")
    person_by_key = {_text(row.get("baseline_record_key")): row.get("person_id")
                     for row in database_preview.get("person_anchors", {}).get("matched", [])}
    clean_by_key: dict[str, list[dict[str, Any]]] = {}
    for row in clean_records:
        key = row.get("record_key")
        if isinstance(key, str) and key:
            clean_by_key.setdefault(key, []).append(row)
    profiles = []
    unsearchable_profile_keys = []
    for key in mapped_keys:
        if key not in person_by_key or not isinstance(person_by_key[key], int) or \
                len(clean_by_key.get(key, [])) != 1:
            _fail("MAPPED_IDENTITY_PROFILE_COVERAGE_INVALID")
        try:
            profiles.append(_profile(clean_by_key[key][0], person_by_key[key]))
        except MappedIdentityReviewError as error:
            if str(error) != "MAPPED_IDENTITY_PROFILE_NOT_SEARCHABLE":
                raise
            unsearchable_profile_keys.append(key)

    output_subjects = []
    for subject in subjects:
        source = _text(subject.get("verbatim_text"))
        candidates = []
        for profile in profiles:
            signals = filter_principal_signals(source, _profile_signals(source, profile))
            if not principal_name_before_transition(source, profile["display_name"]):
                continue
            if not _qualifies(source, signals):
                continue
            candidates.append({
                "candidate_record_key": profile["record_key"],
                "candidate_person_id": profile["person_id"],
                "candidate_display_name": profile["display_name"],
                "classification": "mapped_1939_review_candidate",
                "proposed_action": "unresolved", "signals": signals,
            })
        candidates.sort(key=lambda row: row["candidate_record_key"])
        output_subjects.append({
            "new_record_key": subject["new_record_key"], "source_span": subject["source_span"],
            "verbatim_text": source, "review_state": "pending",
            "person_creation": "forbidden", "candidates": candidates,
        })
    return {
        "schema_version": "1939-v50-mapped-identity-review-v1",
        "generator_version": "build_mapped_identity_review_1939_v50.py:v1",
        "input_hashes": dict(sorted(input_hashes.items())),
        "review_only": True, "review_state": "pending",
        "canonical_mutations_authorized": False,
        "counts": {
            "subjects": len(output_subjects), "profiles": len(mapped_keys),
            "searchable_profiles": len(profiles),
            "unsearchable_profiles": len(unsearchable_profile_keys),
            "candidate_links": sum(len(row["candidates"]) for row in output_subjects),
            "linked_subjects": sum(bool(row["candidates"]) for row in output_subjects),
            "unlinked_subjects": sum(not row["candidates"] for row in output_subjects),
            "ambiguous_subjects": sum(len(row["candidates"]) > 1 for row in output_subjects),
        },
        "unsearchable_profile_keys": sorted(unsearchable_profile_keys),
        "subjects": output_subjects,
        "review_gate": "GO", "identity_decision_gate": "NO-GO", "reimport_gate": "NO-GO",
    }


def _load(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--import-preview", required=True, type=Path)
    parser.add_argument("--database-preview", required=True, type=Path)
    parser.add_argument("--identity-decisions", required=True, type=Path)
    parser.add_argument("--clean", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-subjects", type=int, default=32)
    parser.add_argument("--expected-profiles", type=int, default=543)
    args = parser.parse_args(argv)
    paths = [args.import_preview, args.database_preview, args.identity_decisions, args.clean]
    hashes = dict(zip(("import_preview_sha256", "database_preview_sha256",
                       "identity_decisions_sha256", "clean_sha256"), map(_sha, paths)))
    result = build_mapped_review(
        import_preview=_load(args.import_preview), database_preview=_load(args.database_preview),
        identity_decisions=_load(args.identity_decisions), clean_records=_load(args.clean),
        input_hashes=hashes, expected_subjects=args.expected_subjects,
        expected_profiles=args.expected_profiles)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2); handle.write("\n")
    print(json.dumps({"output": str(args.output), "counts": result["counts"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
