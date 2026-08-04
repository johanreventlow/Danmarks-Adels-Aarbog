"""Build anchored 1939 candidates from explicit, reviewer-supplied bridges."""

from __future__ import annotations

import contextlib
import argparse
import hashlib
import io
import json
import re
from pathlib import Path
from collections import Counter
from collections.abc import Mapping

from coverage_1939 import (
    ALLOWED_STATUSES,
    POSTKLASSER,
    duplicate_target_errors,
    validate_coverage,
)
import segment


_REVIEW_ACCEPTED_FIELDS = {
    "candidate_id",
    "post_index",
    "calamari_span",
    "calamari_verbatim_text",
    "pdf_pages",
    "kind",
    "raw_char_from",
    "raw_char_to",
    "raw_verbatim_text",
    "raw_excerpt_sha256",
}
_REVIEW_DECISION_FIELDS = _REVIEW_ACCEPTED_FIELDS | {
    "duplicate_of_baseline_record_key",
    "reason",
}
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _mapping(value: object, label: str) -> Mapping:
    if not isinstance(value, Mapping):
        raise ValueError(f"{label} skal være en mapping")
    return value


def _positive_int(value: object, label: str, *, zero_allowed: bool = False) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < (0 if zero_allowed else 1):
        raise ValueError(f"{label} skal være et positivt heltal")
    return value


def _pages(value: object, label: str) -> list[int]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{label} skal være en ikke-tom liste")
    return [_positive_int(page, label) for page in value]


def _post_pages(value: object) -> list[int]:
    if not isinstance(value, str) or not value:
        raise ValueError("post sider mangler")
    pieces = value.split("-")
    if len(pieces) == 1:
        return [_positive_int(int(pieces[0]), "post side")]
    if len(pieces) == 2:
        first, last = (_positive_int(int(piece), "post side") for piece in pieces)
        if first > last:
            raise ValueError("post sideinterval er omvendt")
        return list(range(first, last + 1))
    raise ValueError("post sider har ugyldigt format")


def build_candidates(
    calamari_text: str,
    raw_text: str,
    posts: list[dict],
    raw_bridges: list[dict],
) -> list[dict]:
    """Return only candidates with one exact, explicit Calamari/raw bridge."""
    if not isinstance(calamari_text, str):
        raise ValueError("calamari_text skal være en streng")
    if not isinstance(raw_text, str):
        raise ValueError("raw_text skal være en streng")
    if not isinstance(posts, list) or not all(isinstance(post, Mapping) for post in posts):
        raise ValueError("posts skal være en liste af mappings")
    if not isinstance(raw_bridges, list):
        raise ValueError("raw_bridges skal være en liste")

    seen_indices: set[int] = set()
    seen_ids: set[str] = set()
    spans: list[tuple[int, int]] = []
    candidates: list[dict] = []
    for bridge_value in raw_bridges:
        bridge = _mapping(bridge_value, "bridge")
        candidate_id = bridge.get("candidate_id")
        if not isinstance(candidate_id, str) or not candidate_id:
            raise ValueError("candidate_id mangler")
        if candidate_id in seen_ids:
            raise ValueError("candidate_id forekommer flere gange")
        seen_ids.add(candidate_id)

        post_index = _positive_int(bridge.get("post_index"), "post_index", zero_allowed=True)
        if post_index >= len(posts):
            raise ValueError("ukendt post_index")
        if post_index in seen_indices:
            raise ValueError("post_index forekommer flere gange")
        seen_indices.add(post_index)
        post = posts[post_index]

        span = _mapping(bridge.get("calamari_span"), "Calamari-span")
        char_from = _positive_int(span.get("char_from"), "Calamari-span char_from", zero_allowed=True)
        char_to = _positive_int(span.get("char_to"), "Calamari-span char_to", zero_allowed=True)
        if char_from >= char_to or char_to > len(calamari_text):
            raise ValueError("ikke eksakt Calamari-span")
        verbatim = bridge.get("calamari_verbatim_text")
        if not isinstance(verbatim, str) or calamari_text[char_from:char_to] != verbatim:
            raise ValueError("ikke eksakt Calamari-span")
        spans.append((char_from, char_to))

        pdf_pages = _pages(bridge.get("pdf_pages"), "PDF-side")
        if _post_pages(post.get("sider")) != pdf_pages:
            raise ValueError("PDF-sider stemmer ikke")

        kind = bridge.get("kind")
        if not isinstance(kind, str) or not kind:
            raise ValueError("rå-bro kind mangler")
        raw_from = _positive_int(bridge.get("raw_char_from"), "rå-bro raw_char_from", zero_allowed=True)
        raw_to = _positive_int(bridge.get("raw_char_to"), "rå-bro raw_char_to", zero_allowed=True)
        if raw_from >= raw_to or raw_to > len(raw_text):
            raise ValueError("ikke eksakt rå-bro")
        raw_verbatim = bridge.get("raw_verbatim_text")
        if not isinstance(raw_verbatim, str) or raw_text[raw_from:raw_to] != raw_verbatim:
            raise ValueError("ikke eksakt rå-bro")
        raw_digest = bridge.get("raw_excerpt_sha256")
        if raw_digest != hashlib.sha256(raw_verbatim.encode("utf-8")).hexdigest():
            raise ValueError("rå-bro SHA-256 matcher ikke")

        postklasse = post.get("postklasse") or "nummereret"
        if postklasse not in POSTKLASSER:
            raise ValueError("postklasse er ukendt")
        candidates.append({
            "candidate_id": candidate_id,
            "postklasse": postklasse,
            "calamari_span": {"char_from": char_from, "char_to": char_to},
            "pdf_pages": pdf_pages,
            "raw_structure_bridge": {
                "kind": kind,
                "raw_char_from": raw_from,
                "raw_char_to": raw_to,
                "raw_excerpt_sha256": raw_digest,
            },
        })

    for (_, previous_end), (next_start, _) in zip(sorted(spans), sorted(spans)[1:]):
        if previous_end > next_start:
            raise ValueError("Calamari-spans overlapper")
    return candidates


def assemble_coverage(
    source: dict,
    expected_baseline_keys: set[str],
    decisions: list[dict],
    candidates: list[dict],
) -> dict:
    """Resolve reviewer decisions to candidates, then revalidate complete coverage."""
    if not isinstance(decisions, list):
        raise ValueError("decisions skal være en liste")
    candidate_by_id: dict[str, dict] = {}
    for candidate_value in candidates:
        candidate = _mapping(candidate_value, "candidate")
        candidate_id = candidate.get("candidate_id")
        if not isinstance(candidate_id, str) or not candidate_id:
            raise ValueError("candidate_id mangler")
        if candidate_id in candidate_by_id:
            raise ValueError("candidate_id forekommer flere gange")
        candidate_by_id[candidate_id] = dict(candidate)

    entries: list[dict] = []
    for decision_value in decisions:
        decision = _mapping(decision_value, "decision")
        status = decision.get("status")
        if status not in ALLOWED_STATUSES:
            raise ValueError("ukendt status")
        entry = {
            "baseline_record_key": decision.get("baseline_record_key"),
            "status": status,
        }
        if status == "accepteret":
            candidate_id = decision.get("candidate_id")
            if candidate_id not in candidate_by_id:
                raise ValueError("ukendt candidate_id")
            entry["candidate"] = candidate_by_id[candidate_id]
        elif status == "eksplicit_dublet":
            entry["duplicate_of_baseline_record_key"] = decision.get(
                "duplicate_of_baseline_record_key"
            )
        else:
            entry["reason"] = decision.get("reason")
        entries.append(entry)

    bundle = {"schema_version": 1, "source": source, "entries": entries}
    validate_coverage(bundle, expected_baseline_keys=expected_baseline_keys)
    return bundle


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _baseline_records(path: Path) -> dict[str, Mapping]:
    records = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError("baseline skal være en liste")
    keys = [record.get("record_key") for record in records if isinstance(record, Mapping)]
    if len(keys) != len(records) or any(not isinstance(key, str) or not key for key in keys):
        raise ValueError("baseline record_key mangler")
    if len(keys) != len(set(keys)):
        raise ValueError("baseline record_key er dublet")
    return {record["record_key"]: record for record in records}


def _baseline_keys(path: Path) -> set[str]:
    return set(_baseline_records(path))


def write_review_template(baseline_path: Path, out_path: Path) -> dict:
    """Write a new, decision-free private review ledger for every baseline key."""
    if out_path.exists():
        raise FileExistsError(out_path)
    records = _baseline_records(baseline_path)
    keys = sorted(records)
    template = {
        "schema_version": 1,
        "baseline_sha256": _sha256(baseline_path),
        "entries": [
            {
                "baseline_record_key": key,
                "review_status": "unreviewed",
                "baseline_locator": {
                    "pages": records[key].get("sider"),
                    "local_id": records[key].get("_v2_lokal_id"),
                },
            }
            for key in keys
        ],
    }
    with out_path.open("x", encoding="utf-8") as handle:
        json.dump(template, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    return template


def _read_review_template(review_path: Path, baseline_path: Path) -> dict:
    """Read the structural review ledger contract shared by checks and reports."""
    review = _mapping(json.loads(review_path.read_text(encoding="utf-8")), "review")
    if review.get("schema_version") != 1:
        raise ValueError("review schema_version skal være 1")
    if review.get("baseline_sha256") != _sha256(baseline_path):
        raise ValueError("review baseline SHA-256 matcher ikke")
    entries = review.get("entries")
    if not isinstance(entries, list):
        raise ValueError("review entries skal være en liste")
    expected = _baseline_keys(baseline_path)
    actual = [entry.get("baseline_record_key") for entry in entries if isinstance(entry, Mapping)]
    if len(actual) != len(entries) or set(actual) != expected or len(actual) != len(set(actual)):
        raise ValueError("review baseline-dækning fejler")
    allowed_fields = {
        "baseline_record_key",
        "review_status",
        "baseline_locator",
        "candidate_id",
        "post_index",
        "calamari_span",
        "calamari_verbatim_text",
        "pdf_pages",
        "kind",
        "raw_char_from",
        "raw_char_to",
        "raw_verbatim_text",
        "raw_excerpt_sha256",
        "duplicate_of_baseline_record_key",
        "reason",
        "review_note",
    }
    for entry in entries:
        unknown = set(entry) - allowed_fields
        if unknown:
            raise ValueError("review har uautoriserede felter")
    return dict(review)


def _review_entry_errors(entry: Mapping) -> list[str]:
    """Return semantic decision errors without attempting any source matching."""
    status = entry.get("review_status")
    if status == "unreviewed":
        if _REVIEW_DECISION_FIELDS.intersection(entry):
            return ["unreviewed må ikke have beslutningsfelter"]
        return []
    if status not in ALLOWED_STATUSES:
        return ["ukendt review_status"]
    if status == "accepteret":
        missing = [
            f"accepteret kræver {field}"
            for field in sorted(_REVIEW_ACCEPTED_FIELDS)
            if field not in entry
        ]
        if missing:
            return missing
        candidate_id = entry["candidate_id"]
        if not isinstance(candidate_id, str) or not candidate_id.strip():
            return ["candidate_id skal være en ikke-tom streng"]
        try:
            _positive_int(entry["post_index"], "post_index", zero_allowed=True)
            span = _mapping(entry["calamari_span"], "calamari_span")
            char_from = _positive_int(
                span.get("char_from"), "calamari_span char_from", zero_allowed=True
            )
            char_to = _positive_int(
                span.get("char_to"), "calamari_span char_to", zero_allowed=True
            )
            if char_from >= char_to:
                return ["calamari_span skal have char_from < char_to"]
            verbatim = entry["calamari_verbatim_text"]
            if not isinstance(verbatim, str) or not verbatim:
                return ["calamari_verbatim_text skal være en ikke-tom streng"]
            _pages(entry["pdf_pages"], "pdf_pages")
            kind = entry["kind"]
            if not isinstance(kind, str) or not kind.strip():
                return ["kind skal være en ikke-tom streng"]
            raw_from = _positive_int(
                entry["raw_char_from"], "raw_char_from", zero_allowed=True
            )
            raw_to = _positive_int(
                entry["raw_char_to"], "raw_char_to", zero_allowed=True
            )
            if raw_from >= raw_to:
                return ["raw_char_from skal være mindre end raw_char_to"]
            raw_verbatim = entry["raw_verbatim_text"]
            if not isinstance(raw_verbatim, str) or not raw_verbatim:
                return ["raw_verbatim_text skal være en ikke-tom streng"]
            raw_digest = entry["raw_excerpt_sha256"]
            if not isinstance(raw_digest, str) or not _SHA256_RE.fullmatch(raw_digest):
                return ["raw_excerpt_sha256 skal være SHA-256 med små bogstaver"]
            if raw_digest != hashlib.sha256(raw_verbatim.encode("utf-8")).hexdigest():
                return ["raw_excerpt_sha256 matcher ikke raw_verbatim_text"]
        except ValueError as error:
            return [str(error)]
        return []
    if status == "eksplicit_dublet":
        target = entry.get("duplicate_of_baseline_record_key")
        if not isinstance(target, str) or not target.strip():
            return ["eksplicit_dublet kræver duplicate_of_baseline_record_key"]
        if _REVIEW_ACCEPTED_FIELDS.intersection(entry) or "reason" in entry:
            return ["eksplicit_dublet må ikke have kandidat- eller reason-felter"]
        return []
    reason = entry.get("reason")
    if not isinstance(reason, str) or not reason.strip():
        return ["menneskeark kræver reason"]
    if _REVIEW_ACCEPTED_FIELDS.intersection(entry) or "duplicate_of_baseline_record_key" in entry:
        return ["menneskeark må ikke have kandidat- eller dubletfelter"]
    return []


def validate_review_template(review_path: Path, baseline_path: Path) -> dict:
    """Check a private review file is baseline-complete and semantically usable."""
    review = _read_review_template(review_path, baseline_path)
    for entry in review["entries"]:
        errors = _review_entry_errors(entry)
        if errors:
            raise ValueError(errors[0])
    entries_by_key = {
        entry["baseline_record_key"]: entry
        for entry in review["entries"]
    }
    target_errors = duplicate_target_errors(entries_by_key, status_field="review_status")
    if target_errors:
        raise ValueError(next(iter(target_errors.values())))
    return review


def review_summary(review_path: Path, baseline_path: Path) -> dict:
    """Report every decision blocker without writing or inferring any bridge."""
    review = _read_review_template(review_path, baseline_path)
    status_counts: Counter[str] = Counter()
    blockers: list[dict[str, str]] = []
    for entry in review["entries"]:
        key = entry["baseline_record_key"]
        status = entry.get("review_status")
        label = status if isinstance(status, str) else "invalid"
        status_counts[label] += 1
        if status == "unreviewed":
            blockers.append({"baseline_record_key": key, "issue": "unreviewed"})
        for error in _review_entry_errors(entry):
            blockers.append({"baseline_record_key": key, "issue": error})
    entries_by_key = {
        entry["baseline_record_key"]: entry
        for entry in review["entries"]
    }
    for key, error in duplicate_target_errors(
        entries_by_key, status_field="review_status"
    ).items():
        blockers.append({"baseline_record_key": key, "issue": error})
    return {
        "review": str(review_path),
        "entries": len(review["entries"]),
        "status_counts": dict(sorted(status_counts.items())),
        "ready_for_decisions": not blockers,
        "blockers": blockers,
    }


def review_to_decisions(review: dict) -> dict:
    """Convert only fully reviewed entries; never infer a decision or bridge."""
    root = _mapping(review, "review")
    entries = root.get("entries")
    if not isinstance(entries, list):
        raise ValueError("review entries skal være en liste")
    entries_by_key: dict[str, Mapping] = {}
    for value in entries:
        entry = _mapping(value, "review entry")
        key = entry.get("baseline_record_key")
        if not isinstance(key, str) or not key:
            raise ValueError("baseline_record_key mangler")
        if key in entries_by_key:
            raise ValueError("dublet baseline_record_key")
        entries_by_key[key] = entry
    target_errors = duplicate_target_errors(entries_by_key, status_field="review_status")
    if target_errors:
        raise ValueError(next(iter(target_errors.values())))
    decisions = []
    for value in entries:
        entry = dict(_mapping(value, "review entry"))
        errors = _review_entry_errors(entry)
        if errors:
            raise ValueError(errors[0])
        status = entry.pop("review_status", None)
        entry.pop("baseline_locator", None)
        if status == "unreviewed":
            raise ValueError("unreviewed entry kan ikke materialiseres")
        entry["status"] = status
        decisions.append(entry)
    return {"entries": decisions}


def materialize_coverage(
    calamari_path: Path,
    raw_path: Path,
    pdf_path: Path,
    baseline_path: Path,
    decisions_path: Path,
    out_path: Path,
) -> dict:
    """Materialize one new private coverage bundle; never overwrite output."""
    if out_path.exists():
        raise FileExistsError(out_path)
    calamari_text = calamari_path.read_text(encoding="utf-8")
    raw_text = raw_path.read_text(encoding="utf-8")
    decisions_root = _mapping(json.loads(decisions_path.read_text(encoding="utf-8")), "decisions")
    decisions = decisions_root.get("entries")
    if not isinstance(decisions, list):
        raise ValueError("decisions entries skal være en liste")
    bridges = [decision for decision in decisions
               if isinstance(decision, Mapping) and decision.get("status") == "accepteret"]
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        posts = segment._segment_1939_v2(
            calamari_text.splitlines(), segment.UDGAVE_PROFILER["1939-v2"]
        )
    candidates = build_candidates(calamari_text, raw_text, posts, bridges)
    simplified = []
    for decision in decisions:
        entry = dict(_mapping(decision, "decision"))
        if entry.get("status") == "accepteret":
            entry = {
                "baseline_record_key": entry.get("baseline_record_key"),
                "status": "accepteret",
                "candidate_id": entry.get("candidate_id"),
            }
        simplified.append(entry)
    bundle = assemble_coverage(
        {
            "edition": "1939",
            "calamari_sha256": _sha256(calamari_path),
            "raw_ocr_sha256": _sha256(raw_path),
            "pdf_sha256": _sha256(pdf_path),
        },
        _baseline_keys(baseline_path),
        simplified,
        candidates,
    )
    with out_path.open("x", encoding="utf-8") as handle:
        json.dump(bundle, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    return bundle


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Materialisér én ny, privat og fail-closed 1939 coverage-fil."
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--make-review-template", action="store_true")
    mode.add_argument("--check-review", type=Path)
    mode.add_argument("--review-summary", type=Path)
    mode.add_argument("--review-to-decisions", type=Path)
    parser.add_argument("--calamari", type=Path)
    parser.add_argument("--raw", type=Path)
    parser.add_argument("--pdf", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--decisions", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    if args.make_review_template:
        if args.baseline is None or args.out is None:
            parser.error("--make-review-template kræver --baseline og --out")
        template = write_review_template(args.baseline, args.out)
        print(json.dumps({"out": str(args.out), "entries": len(template["entries"])}, ensure_ascii=False))
        return 0
    if args.check_review is not None:
        if args.baseline is None:
            parser.error("--check-review kræver --baseline")
        review = validate_review_template(args.check_review, args.baseline)
        print(json.dumps({"review": str(args.check_review), "entries": len(review["entries"])}, ensure_ascii=False))
        return 0
    if args.review_summary is not None:
        if args.baseline is None:
            parser.error("--review-summary kræver --baseline")
        print(json.dumps(
            review_summary(args.review_summary, args.baseline),
            ensure_ascii=False,
        ))
        return 0
    if args.review_to_decisions is not None:
        if args.baseline is None or args.out is None:
            parser.error("--review-to-decisions kræver --baseline og --out")
        if args.out.exists():
            raise FileExistsError(args.out)
        decisions = review_to_decisions(
            validate_review_template(args.review_to_decisions, args.baseline)
        )
        with args.out.open("x", encoding="utf-8") as handle:
            json.dump(decisions, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        print(json.dumps({"out": str(args.out), "entries": len(decisions["entries"])}, ensure_ascii=False))
        return 0
    missing = [flag for flag, value in {
        "--calamari": args.calamari,
        "--raw": args.raw,
        "--pdf": args.pdf,
        "--baseline": args.baseline,
        "--decisions": args.decisions,
        "--out": args.out,
    }.items() if value is None]
    if missing:
        parser.error("materialisering kræver " + ", ".join(missing))
    bundle = materialize_coverage(
        args.calamari, args.raw, args.pdf, args.baseline, args.decisions, args.out
    )
    print(json.dumps({"out": str(args.out), "entries": len(bundle["entries"])}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
