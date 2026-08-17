#!/usr/bin/env python3
"""Materialize explicit human v50 identity approvals into a private artifact.

This is an append-only decision document for a future source-persona writer.
It performs no database operation and grants no mutation authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


class IdentityDecisionError(ValueError):
    pass


def _fail(code: str, detail: str | None = None) -> None:
    raise IdentityDecisionError(code if detail is None else f"{code}: {detail}")


def _text(value: Any, code: str = "IDENTITY_DECISION_INPUT_INVALID") -> str:
    if not isinstance(value, str) or not value:
        _fail(code)
    return value


def _sha(value: Any) -> str:
    value = _text(value, "IDENTITY_DECISION_HASH_INVALID")
    if len(value) != 64 or any(char not in "0123456789abcdef" for char in value):
        _fail("IDENTITY_DECISION_HASH_INVALID")
    return value


def _integer(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        _fail("IDENTITY_DECISION_INPUT_INVALID")
    return value


def _canonical_digest(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _validate_review(review: dict[str, Any]) -> dict[str, tuple[dict[str, Any], dict[str, Any]]]:
    if (not isinstance(review, dict) or
        review.get("schema_version") != "1939-v50-identity-review-v1" or
        review.get("review_only") is not True or
        review.get("review_state") != "pending" or
        review.get("canonical_mutations_authorized") is not False or
        review.get("review_gate") != "GO" or
        review.get("identity_decision_gate") != "NO-GO" or
        review.get("reimport_gate") != "NO-GO"):
        _fail("IDENTITY_DECISION_REVIEW_INVALID")
    subjects = review.get("subjects")
    profiles = review.get("profiles")
    counts = review.get("counts")
    if (not isinstance(subjects, list) or not isinstance(profiles, list) or
        not isinstance(counts, dict) or counts.get("subjects") != len(subjects) or
        counts.get("profiles") != len(profiles)):
        _fail("IDENTITY_DECISION_REVIEW_INVALID")
    profile_pairs = {}
    for row in profiles:
        key = _text(row.get("record_key"))
        person_id = _integer(row.get("person_id"))
        if key in profile_pairs or person_id in profile_pairs.values():
            _fail("IDENTITY_DECISION_REVIEW_INVALID")
        profile_pairs[key] = person_id
    candidates: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
    link_count = 0
    for subject in subjects:
        source_key = _text(subject.get("new_record_key"))
        if source_key in candidates or subject.get("review_state") != "pending" or \
                subject.get("person_creation") != "forbidden":
            _fail("IDENTITY_DECISION_REVIEW_INVALID")
        rows = subject.get("candidates")
        if not isinstance(rows, list):
            _fail("IDENTITY_DECISION_REVIEW_INVALID")
        for candidate in rows:
            link_count += 1
            candidate_key = _text(candidate.get("candidate_record_key"))
            person_id = _integer(candidate.get("candidate_person_id"))
            if (profile_pairs.get(candidate_key) != person_id or
                candidate.get("classification") != "review_candidate" or
                candidate.get("proposed_action") != "unresolved" or
                not isinstance(candidate.get("signals"), list) or
                not candidate["signals"] or
                candidate.get("competing_candidate_record_keys") != [] or
                candidate.get("competing_subject_record_keys") != []):
                _fail("IDENTITY_DECISION_CANDIDATE_INVALID", source_key)
            compound = f"{source_key}\0{candidate_key}"
            if compound in candidates:
                _fail("IDENTITY_DECISION_REVIEW_INVALID")
            candidates[compound] = (subject, candidate)
    if counts.get("candidate_links") != link_count:
        _fail("IDENTITY_DECISION_REVIEW_INVALID")
    return candidates


def materialize_decisions(review: dict[str, Any], approvals: dict[str, Any],
                          review_sha256: str, expected_decisions: int = 9) -> dict[str, Any]:
    review_sha256 = _sha(review_sha256)
    candidates = _validate_review(review)
    if (not isinstance(approvals, dict) or set(approvals) != {
            "schema_version", "review_sha256", "reviewed_by", "decision_batch",
            "confirmation", "approvals"} or
        approvals.get("schema_version") != "1939-v50-identity-approvals-v1" or
        _sha(approvals.get("review_sha256")) != review_sha256):
        _fail("IDENTITY_DECISION_APPROVALS_INVALID")
    reviewed_by = _text(approvals.get("reviewed_by"))
    decision_batch = _text(approvals.get("decision_batch"))
    confirmation = _text(approvals.get("confirmation"))
    rows = approvals.get("approvals")
    if not isinstance(rows, list) or len(rows) != expected_decisions:
        _fail("IDENTITY_DECISION_COUNT_INVALID")

    seen_subjects: set[str] = set()
    seen_candidates: set[str] = set()
    decisions = []
    for approval in rows:
        if not isinstance(approval, dict) or set(approval) != {
                "source_record_key", "candidate_record_key", "action"}:
            _fail("IDENTITY_DECISION_APPROVALS_INVALID")
        source_key = _text(approval.get("source_record_key"))
        candidate_key = _text(approval.get("candidate_record_key"))
        if approval.get("action") != "same":
            _fail("IDENTITY_DECISION_ACTION_INVALID")
        if source_key in seen_subjects or candidate_key in seen_candidates:
            _fail("IDENTITY_DECISION_INJECTIVITY_INVALID")
        seen_subjects.add(source_key)
        seen_candidates.add(candidate_key)
        match = candidates.get(f"{source_key}\0{candidate_key}")
        if match is None:
            _fail("IDENTITY_DECISION_CANDIDATE_NOT_FOUND", source_key)
        subject, candidate = match
        decisions.append({
            "source_record_key": source_key,
            "candidate_record_key": candidate_key,
            "canonical_person_id": candidate["candidate_person_id"],
            "action": "same",
            "record_provenance": {
                "record_key": source_key,
                "external_person_number": None,
            },
            "source_span": subject["source_span"],
            "candidate_evidence_sha256": _canonical_digest(candidate),
            "source_persona_status": "pending_materialization",
            "database_write_authorized": False,
        })

    return {
        "schema_version": "1939-v50-identity-decisions-v1",
        "generator_version": "materialize_identity_decisions_1939_v50.py:v1",
        "input_review_sha256": review_sha256,
        "reviewed_by": reviewed_by,
        "decision_batch": decision_batch,
        "confirmation": confirmation,
        "decision_basis": "explicit_user_confirmation",
        "canonical_mutations_authorized": False,
        "database_write_authorized": False,
        "counts": {"decisions": len(decisions), "same": len(decisions)},
        "decisions": decisions,
        "decision_gate": "GO",
        "source_persona_materialization_gate": "NO-GO",
        "database_gate": "NO-GO",
        "reimport_gate": "NO-GO",
    }


def render_markdown(result: dict[str, Any]) -> str:
    lines = [
        "# DAA 1939 v50 identity decisions",
        "",
        "Hashbundet menneskelig beslutningsbatch. Ingen databaseændringer er autoriseret.",
        "",
        f"- reviewed_by: `{result['reviewed_by']}`",
        f"- decision_batch: `{result['decision_batch']}`",
        f"- beslutninger: {result['counts']['decisions']}",
        f"- source-persona materialisering: **{result['source_persona_materialization_gate']}**",
        f"- database: **{result['database_gate']}**",
        f"- reimport: **{result['reimport_gate']}**",
        "", "## Godkendte identiteter", "",
    ]
    for index, row in enumerate(result["decisions"], 1):
        lines.append(
            f"{index}. `{row['source_record_key']}` → `{row['candidate_record_key']}` "
            f"(person {row['canonical_person_id']})")
    lines.append("")
    return "\n".join(lines)


def write_outputs(result: dict[str, Any], output_path: Path | str,
                  report_path: Path | str) -> None:
    output, report = Path(output_path), Path(report_path)
    if output.resolve() == report.resolve():
        _fail("IDENTITY_DECISION_OUTPUT_INVALID")
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


def _load(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--approvals", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-decisions", type=int, default=9)
    args = parser.parse_args(argv)
    review_bytes = args.review.read_bytes()
    result = materialize_decisions(
        json.loads(review_bytes), _load(args.approvals),
        hashlib.sha256(review_bytes).hexdigest(), args.expected_decisions)
    write_outputs(result, args.output, args.report)
    print(json.dumps({"output": str(args.output), "report": str(args.report),
                      "decisions": result["counts"]["decisions"],
                      "database_write_authorized": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

