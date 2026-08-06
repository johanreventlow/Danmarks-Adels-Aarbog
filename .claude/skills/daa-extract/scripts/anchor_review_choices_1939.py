"""Deterministically re-anchor exported 1939 human review choices.

A browser export carries the editor's candidate selections, but those
selections reference presentation-only identities that can never become
positive accepted evidence.  This module re-derives every selection as an
exact, hash-locked Calamari span (fail-closed, never guessing) and emits
the anchored-candidates wrapper required by ``convert_review_choices``,
matching human evidence entries, rewritten choices whose anchored
selections reference the new ``human:`` identities, and a parking report
with one precise Danish reason per unresolvable choice.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import hashlib
import io
import json
import re
from collections.abc import Mapping
from pathlib import Path

import segment
from coverage_1939 import validate_coverage
from dual_rendition_evidence_1939 import align_renditions
from make_human_review_1939 import _pages
from review_choices_1939 import validate_choice_export
from review_queue_1939 import sample_auto_resolved


RULE_ID = "human_anchor_v1"
APPROVAL_KIND = "human_approved_span_v1"
BRIDGE_KIND = "human_approved_occurrence_pair_v1"
POSTKLASSER = {"nummereret", "stamfader", "oversigtspost"}
PARKED_REASONS_DA = {
    "text_anchor_not_reproducible": (
        "Tekstankeret kan ikke genberegnes entydigt fra baseline-narrativet "
        "i Calamari-kilden."
    ),
    "parser_post_not_found": (
        "Kandidat-id'et matcher ingen regenereret kildepost med "
        "kildelinje-interval."
    ),
    "parser_post_ambiguous": (
        "Kandidat-id'et matcher flere regenererede kildeposter."
    ),
    "span_verbatim_mismatch": (
        "Kildeudsnittet er tomt eller uden ordret tekst."
    ),
    "pdf_pages_mismatch": (
        "PDF-siderne kan ikke etableres entydigt fra hverken kildeforekomst "
        "eller postens sideangivelse."
    ),
    "candidate_claimed_by_multiple_records": (
        "Samme kildekandidat er valgt af flere baseline-poster."
    ),
    "overlaps_automatic_candidate": (
        "Kildeudsnittet overlapper en automatisk accepteret kandidat."
    ),
    "overlaps_other_manual_choice": (
        "Kildeudsnittet overlapper et andet manuelt valg."
    ),
}
_VALIDATION_SOURCE = {
    "edition": "1939",
    "calamari_sha256": "a" * 64,
    "raw_ocr_sha256": "b" * 64,
    "pdf_sha256": "c" * 64,
}


class _Parked(Exception):
    """Internal control flow for one precisely reasoned parked choice."""

    def __init__(self, reason_code: str):
        super().__init__(reason_code)
        self.reason_code = reason_code


def _mapping(value: object, label: str) -> Mapping:
    if not isinstance(value, Mapping):
        raise ValueError(f"{label} skal være en mapping")
    return value


def _nonempty(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} skal være en ikke-tom streng")
    return value


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _line_offsets(calamari_text: str) -> tuple[list[str], list[int]]:
    lines = calamari_text.splitlines()
    offsets = []
    position = 0
    for line in lines:
        offsets.append(position)
        position += len(line) + 1
    return lines, offsets


def _resolve_span(
    choice_id: str, key: str, baseline_records: Mapping, posts: list,
    lines: list[str], offsets: list[int], calamari_text: str,
    profile_version: str,
) -> tuple[int, int, Mapping | None]:
    """Return the exact half-open source span for one choice, or park it."""
    text_anchor = re.fullmatch(
        rf"presentation:{re.escape(profile_version)}:text-anchor:(.+)", choice_id
    )
    if text_anchor:
        narrative = baseline_records[key].get("narrative")
        if not isinstance(narrative, str) or not narrative:
            raise _Parked("text_anchor_not_reproducible")
        start = calamari_text.find(narrative)
        if start < 0 or calamari_text.find(narrative, start + 1) >= 0:
            raise _Parked("text_anchor_not_reproducible")
        end = start + len(narrative)
        digest = hashlib.sha256(
            f"{profile_version}\0{key}\0{start}\0{end}".encode("utf-8")
        ).hexdigest()
        if text_anchor.group(1) != digest:
            raise _Parked("text_anchor_not_reproducible")
        return start, end, None
    post_match = re.fullmatch(
        rf"presentation:{re.escape(profile_version)}:post:(\d+)", choice_id
    )
    if post_match:
        index = int(post_match.group(1))
        if index >= len(posts):
            raise _Parked("parser_post_not_found")
        post = posts[index]
    else:
        matches = [
            candidate_post for candidate_post in posts
            if candidate_post.get("candidate_id") == choice_id
            or candidate_post.get("lokal_id") == choice_id
        ]
        if not matches:
            raise _Parked("parser_post_not_found")
        if len(matches) > 1:
            raise _Parked("parser_post_ambiguous")
        post = matches[0]
    linjer = post.get("linjer")
    if not isinstance(linjer, Mapping):
        raise _Parked("parser_post_not_found")
    fra, til = linjer.get("fra"), linjer.get("til")
    if (
        not isinstance(fra, int) or isinstance(fra, bool)
        or not isinstance(til, int) or isinstance(til, bool)
        or fra < 0 or til <= fra or til > len(lines)
    ):
        raise _Parked("parser_post_not_found")
    return offsets[fra], offsets[til - 1] + len(lines[til - 1]), post


def _unique_covering_occurrence(
    occurrences: list, char_from: int, char_to: int,
) -> Mapping | None:
    covering = [
        occurrence for occurrence in occurrences
        if occurrence["span"]["char_from"] <= char_from
        and char_to <= occurrence["span"]["char_to"]
    ]
    return covering[0] if len(covering) == 1 else None


def _resolve_pdf_pages(covering: Mapping | None, record: Mapping) -> list[int]:
    if covering is not None:
        return list(covering["pdf_pages"])
    try:
        pages = _pages(record.get("sider"))
    except ValueError as error:
        raise _Parked("pdf_pages_mismatch") from error
    if not pages or any(page <= 0 for page in pages):
        raise _Parked("pdf_pages_mismatch")
    return pages


def _raw_bridge(
    covering: Mapping | None, pair_by_calamari: dict[str, str],
    ambiguous_ids: set[str], raw_by_id: dict[str, Mapping], raw_text: str,
) -> dict | None:
    if covering is None:
        return None
    raw_id = pair_by_calamari.get(covering["occurrence_id"])
    if raw_id is None:
        return None
    if covering["occurrence_id"] in ambiguous_ids or raw_id in ambiguous_ids:
        return None
    raw = raw_by_id.get(raw_id)
    if raw is None:
        return None
    raw_from, raw_to = raw["span"]["char_from"], raw["span"]["char_to"]
    return {
        "kind": BRIDGE_KIND,
        "raw_char_from": raw_from,
        "raw_char_to": raw_to,
        "raw_excerpt_sha256": _sha256_text(raw_text[raw_from:raw_to]),
    }


def _postklasse(post: Mapping | None, classification: object) -> str:
    if post is not None:
        value = post.get("postklasse") or "nummereret"
    else:
        value = (
            classification.get("postklasse")
            if isinstance(classification, Mapping) else None
        ) or "nummereret"
    if value not in POSTKLASSER:
        raise ValueError("postklasse er ukendt")
    return value


def _automatic_claims(classifications: Mapping) -> dict[str, Mapping]:
    claims: dict[str, Mapping] = {}
    for key, raw_entry in classifications.items():
        entry = _mapping(raw_entry, "classification")
        if entry.get("queue_class") != "auto_resolved":
            continue
        candidate = _mapping(entry.get("candidate"), "automatisk kandidat")
        _mapping(candidate.get("calamari_span"), "automatisk kandidats calamari_span")
        claims[_nonempty(key, "classification key")] = candidate
    return claims


def _claim_span(
    candidate: Mapping, container: str, from_field: str, to_field: str,
) -> tuple[int, int] | None:
    span = candidate.get(container)
    if not isinstance(span, Mapping):
        return None
    start, end = span.get(from_field), span.get(to_field)
    if (
        not isinstance(start, int) or isinstance(start, bool)
        or not isinstance(end, int) or isinstance(end, bool)
        or start < 0 or start >= end
    ):
        return None
    return start, end


def _global_collision_reasons(
    resolved: dict[str, dict], auto_claims: dict[str, Mapping],
) -> dict[str, str]:
    """Assign the first applicable global parking reason per resolved key."""
    reasons: dict[str, str] = {}
    owners_by_id: dict[str, list[str]] = {}
    for key in sorted(resolved):
        owners_by_id.setdefault(resolved[key]["candidate_id"], []).append(key)
    auto_ids = {
        candidate.get("candidate_id") for candidate in auto_claims.values()
    }
    for candidate_id, owners in owners_by_id.items():
        if len(owners) > 1 or candidate_id in auto_ids:
            for key in owners:
                reasons.setdefault(key, "candidate_claimed_by_multiple_records")
    for container, from_field, to_field in (
        ("calamari_span", "char_from", "char_to"),
        ("raw_structure_bridge", "raw_char_from", "raw_char_to"),
    ):
        auto_spans = [
            span for candidate in auto_claims.values()
            if (span := _claim_span(candidate, container, from_field, to_field))
        ]
        human_spans = [
            (key, span) for key in sorted(resolved)
            if (span := _claim_span(resolved[key], container, from_field, to_field))
        ]
        for key, (start, end) in human_spans:
            if any(start < other_end and other_start < end
                   for other_start, other_end in auto_spans):
                reasons.setdefault(key, "overlaps_automatic_candidate")
        for index, (left_key, (left_start, left_end)) in enumerate(human_spans):
            for right_key, (right_start, right_end) in human_spans[index + 1:]:
                if left_start < right_end and right_start < left_end:
                    reasons.setdefault(left_key, "overlaps_other_manual_choice")
                    reasons.setdefault(right_key, "overlaps_other_manual_choice")
    return reasons


def _assert_wrapper_candidates_valid(anchored: dict[str, dict]) -> None:
    """Enforce the accepted-candidate contract on every emitted wrapper."""
    if not anchored:
        return
    validate_coverage(
        {
            "schema_version": 1,
            "source": copy.deepcopy(_VALIDATION_SOURCE),
            "entries": [
                {
                    "baseline_record_key": wrapper["baseline_record_key"],
                    "status": "accepteret",
                    "candidate": copy.deepcopy(wrapper["candidate"]),
                }
                for wrapper in anchored.values()
            ],
        },
        expected_baseline_keys={
            wrapper["baseline_record_key"] for wrapper in anchored.values()
        },
    )


def build_human_anchored_candidates(
    choices: dict,
    audit_keys: set[str],
    classifications: dict,
    baseline_records: dict,
    posts: list,
    calamari_text: str,
    raw_text: str,
    calamari_occurrences: dict,
    raw_occurrences: dict,
    profile_version: str,
) -> dict:
    """Re-anchor every manual choice fail-closed, parking what cannot be proven."""
    _nonempty(profile_version, "profile_version")
    choices = _mapping(choices, "choices")
    classifications = _mapping(classifications, "classifications")
    baseline_records = _mapping(baseline_records, "baseline_records")
    if not isinstance(audit_keys, set) or any(
        not isinstance(key, str) for key in audit_keys
    ):
        raise ValueError("audit_keys skal være et sæt af strenge")
    if not isinstance(posts, list) or any(
        not isinstance(post, Mapping) for post in posts
    ):
        raise ValueError("posts skal være en liste af mappings")
    if not isinstance(calamari_text, str) or not isinstance(raw_text, str):
        raise ValueError("kildetekster skal være strenge")

    alignment = align_renditions(calamari_occurrences, raw_occurrences)
    pair_by_calamari = {
        pair["calamari_occurrence_id"]: pair["raw_occurrence_id"]
        for pair in alignment["pairs"]
    }
    ambiguous_ids = set(alignment["ambiguous_occurrence_ids"])
    cal_occurrence_list = calamari_occurrences["occurrences"]
    raw_by_id = {
        occurrence["occurrence_id"]: occurrence
        for occurrence in raw_occurrences["occurrences"]
    }
    lines, offsets = _line_offsets(calamari_text)

    parked_by_key: dict[str, str] = {}
    chosen_ids: dict[str, str] = {}
    resolved: dict[str, dict] = {}
    for key in sorted(choices):
        choice = _mapping(choices[key], "choice")
        if choice.get("baseline_record_key") != key:
            raise ValueError("choice har forkert baseline_record_key")
        if key in audit_keys or choice.get("outcome") != "human_selected_candidate":
            continue
        choice_id = _nonempty(choice.get("candidate_id"), "candidate_id")
        if key not in baseline_records:
            raise ValueError("ukendt baseline_record_key")
        chosen_ids[key] = choice_id
        try:
            char_from, char_to, post = _resolve_span(
                choice_id, key, baseline_records, posts, lines, offsets,
                calamari_text, profile_version,
            )
            excerpt = calamari_text[char_from:char_to]
            if not excerpt.strip():
                raise _Parked("span_verbatim_mismatch")
            excerpt_sha = _sha256_text(excerpt)
            covering = _unique_covering_occurrence(
                cal_occurrence_list, char_from, char_to
            )
            candidate = {
                "candidate_id": "human:%s:span:%s" % (
                    profile_version,
                    hashlib.sha256(
                        f"{profile_version}\0{char_from}\0{char_to}\0{excerpt_sha}"
                        .encode("utf-8")
                    ).hexdigest(),
                ),
                "postklasse": _postklasse(post, classifications.get(key)),
                "calamari_span": {"char_from": char_from, "char_to": char_to},
                "pdf_pages": _resolve_pdf_pages(covering, baseline_records[key]),
                "approval": {
                    "kind": APPROVAL_KIND,
                    "calamari_excerpt_sha256": excerpt_sha,
                },
            }
            bridge = _raw_bridge(
                covering, pair_by_calamari, ambiguous_ids, raw_by_id, raw_text
            )
            if bridge is not None:
                candidate["raw_structure_bridge"] = bridge
            resolved[key] = candidate
        except _Parked as parked:
            parked_by_key[key] = parked.reason_code

    collision_reasons = _global_collision_reasons(
        resolved, _automatic_claims(classifications)
    )
    for key, reason_code in collision_reasons.items():
        parked_by_key[key] = reason_code
        del resolved[key]

    rewritten_choices: dict[str, dict] = {}
    for key in sorted(choices):
        rewritten = copy.deepcopy(dict(choices[key]))
        if (
            rewritten.get("outcome") == "human_selected_candidate"
            and key in resolved
        ):
            rewritten["candidate_id"] = resolved[key]["candidate_id"]
        rewritten_choices[key] = rewritten

    anchored: dict[str, dict] = {}
    evidence_entries: list[dict] = []
    for key in sorted(resolved):
        candidate = resolved[key]
        anchored[candidate["candidate_id"]] = {
            "baseline_record_key": key,
            "candidate": copy.deepcopy(candidate),
        }
        evidence_entries.append({
            "baseline_record_key": key,
            "candidates": [copy.deepcopy(candidate)],
            "conflicts": [],
            "source_blockers": [],
            "rule_id": RULE_ID,
            "positive_provenance": {
                "kind": APPROVAL_KIND,
                "baseline_record_key": key,
                "candidate_id": candidate["candidate_id"],
            },
        })
    _assert_wrapper_candidates_valid(anchored)
    parked = [
        {
            "baseline_record_key": key,
            "reason_code": reason_code,
            "reason_da": PARKED_REASONS_DA[reason_code],
            "candidate_id": chosen_ids[key],
        }
        for key, reason_code in sorted(parked_by_key.items())
    ]
    return {
        "anchored": anchored,
        "evidence_entries": evidence_entries,
        "parked": parked,
        "rewritten_choices": rewritten_choices,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--choices", type=Path, required=True)
    parser.add_argument("--queue-manifest", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--calamari", type=Path, required=True)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--calamari-occurrences", type=Path, required=True)
    parser.add_argument("--raw-occurrences", type=Path, required=True)
    parser.add_argument("--wrapper-out", type=Path, required=True)
    parser.add_argument("--evidence-out", type=Path, required=True)
    parser.add_argument("--report-out", type=Path, required=True)
    parser.add_argument("--rewritten-choices-out", type=Path, required=True)
    args = parser.parse_args()

    queue = json.loads(args.queue_manifest.read_text(encoding="utf-8"))
    if not isinstance(queue, dict):
        raise ValueError("queue manifest skal være en mapping")
    source = queue.get("source")
    if not isinstance(source, dict):
        raise ValueError("queue manifest source skal være en mapping")
    baseline_bytes = args.baseline.read_bytes()
    calamari_bytes = args.calamari.read_bytes()
    raw_bytes = args.raw.read_bytes()
    for label, content, field in (
        ("baseline", baseline_bytes, "baseline_sha256"),
        ("calamari", calamari_bytes, "calamari_sha256"),
        ("raw OCR", raw_bytes, "raw_ocr_sha256"),
    ):
        if hashlib.sha256(content).hexdigest() != source.get(field):
            raise ValueError(f"{label} hash matcher ikke queue manifest")
    for out_path in (
        args.wrapper_out, args.evidence_out, args.report_out,
        args.rewritten_choices_out,
    ):
        if out_path.exists():
            raise FileExistsError(out_path)

    records = json.loads(baseline_bytes)
    if not isinstance(records, list):
        raise ValueError("baseline skal være en liste")
    baseline_records: dict[str, dict] = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("baseline record skal være en mapping")
        key = _nonempty(record.get("record_key"), "record_key")
        if key in baseline_records:
            raise ValueError("dublet record_key")
        baseline_records[key] = record
    export_root = json.loads(args.choices.read_text(encoding="utf-8"))
    choices = validate_choice_export(export_root, source, set(baseline_records))
    audit_keys = set(sample_auto_resolved(queue))
    classifications = {
        entry["baseline_record_key"]: entry for entry in queue["entries"]
    }
    calamari_occurrences = json.loads(
        args.calamari_occurrences.read_text(encoding="utf-8")
    )
    raw_occurrences = json.loads(args.raw_occurrences.read_text(encoding="utf-8"))
    profile_version = source.get("profile_version")
    if profile_version not in segment.UDGAVE_PROFILER:
        raise ValueError("ukendt profile_version")
    calamari_text = calamari_bytes.decode("utf-8")
    with contextlib.redirect_stdout(io.StringIO()), \
            contextlib.redirect_stderr(io.StringIO()):
        posts = segment._segment_1939_v2(
            calamari_text.splitlines(), segment.UDGAVE_PROFILER[profile_version]
        )
    result = build_human_anchored_candidates(
        choices, audit_keys, classifications, baseline_records, posts,
        calamari_text, raw_bytes.decode("utf-8"), calamari_occurrences,
        raw_occurrences, profile_version,
    )
    report = {
        "schema_version": 1,
        "source": copy.deepcopy(source),
        "anchored_count": len(result["anchored"]),
        "parked_count": len(result["parked"]),
        "parked": result["parked"],
    }
    rewritten_entries = [
        copy.deepcopy(
            result["rewritten_choices"][entry["baseline_record_key"]]
            if "outcome" in entry else entry
        )
        for entry in export_root["entries"]
    ]
    rewritten_export = {
        "schema_version": 1,
        "source": copy.deepcopy(source),
        "baseline_sha256": source["baseline_sha256"],
        "exported_at": export_root["exported_at"],
        "entries": rewritten_entries,
    }
    validate_choice_export(rewritten_export, source, set(baseline_records))
    for out_path, payload in (
        (args.wrapper_out, result["anchored"]),
        (args.evidence_out, result["evidence_entries"]),
        (args.report_out, report),
        (args.rewritten_choices_out, rewritten_export),
    ):
        with out_path.open("x", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
