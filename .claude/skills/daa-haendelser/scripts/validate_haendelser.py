#!/usr/bin/env python3
"""Blokerende H1-H8-validering af hændelsesudtræk.

H8-tærsklen er tre år-tokens. Den er bevidst konservativ: ét eller to årstal kan
være rene livsgrænser eller en kildehenvisning, mens tre årstal i en DAA-biografi
normalt signalerer mindst én dateret gerning. Tærsklen skal genmåles mod en større
eksport, før den ændres.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[3]
DAA_EXTRACT_SCRIPTS = REPO_ROOT / ".claude" / "skills" / "daa-extract" / "scripts"
sys.path.insert(0, str(DAA_EXTRACT_SCRIPTS))
import validate as daa_validate  # noqa: E402

ALLOWED_TOP = {"narrative_id", "haendelser"}
ALLOWED_EVENT = {
    "klausul", "date_raw", "date_min", "date_max", "date_qualifier", "kategori"
}
QUALIFIERS = {
    "exact", "before", "after", "about", "between", "floruit",
    "until_event", "open_end", "ongoing", None,
}
YEAR_RE = re.compile(r"(?<!\d)(\d{4})(?!\d)")
H8_YEAR_THRESHOLD = 3

with (SCRIPT_DIR.parent / "references" / "vocab.json").open(encoding="utf-8") as fh:
    CATEGORIES = set(json.load(fh)["haendelse_kategori"])

PROMPT_VERSION_RE = re.compile(r"prompt-version:\s*([^>]+?)\s*-->")
prompt_text = (SCRIPT_DIR.parent / "references" / "haendelse-prompt.md").read_text(encoding="utf-8")
prompt_match = PROMPT_VERSION_RE.search(prompt_text)
PASS_VERSION = prompt_match.group(1).strip() if prompt_match else "ukendt"


def normaliser_klausul(value: str) -> str:
    """NFC, lowercase, komprimer whitespace, trim og trunkér til 160 tegn."""
    value = unicodedata.normalize("NFC", value or "").lower()
    return re.sub(r"\s+", " ", value).strip()[:160]


def _next_span(text: str, clause: str, used_offsets: set[int]) -> tuple[int | None, int | None]:
    start = 0
    while True:
        pos = text.find(clause, start)
        if pos < 0:
            return None, None
        if pos not in used_offsets:
            used_offsets.add(pos)
            return pos, len(clause)
        start = pos + 1


def validate_narrative(
    source: dict[str, Any], extracted: dict[str, Any] | None
) -> tuple[dict[str, Any] | None, list[str], list[str], list[str]]:
    """Returnér (beriget record, blokerende brud, advisory, eskaleringsgrunde)."""
    narrative_id = source.get("narrative_id")
    text = source.get("tekst") or ""
    issues: list[str] = []
    advisory: list[str] = []

    if extracted is None:
        issue = "H3: udtræk mangler"
        return None, [issue], [], [issue]
    if not isinstance(extracted, dict):
        issue = "H3: topniveau skal være et objekt"
        return None, [issue], [], [issue]

    unknown_top = sorted(set(extracted) - ALLOWED_TOP)
    if unknown_top:
        issues.append(f"H3: ukendte topfelter: {', '.join(unknown_top)}")
    if extracted.get("narrative_id") != narrative_id:
        issues.append(
            f"H3: narrative_id matcher ikke kilden ({extracted.get('narrative_id')} != {narrative_id})"
        )
    events = extracted.get("haendelser")
    if not isinstance(events, list):
        issues.append("H3: haendelser skal være en liste")
        events = []

    enriched_events: list[dict[str, Any]] = []
    used_offsets: set[int] = set()
    key_counts: Counter[str] = Counter()
    for index, raw_event in enumerate(events):
        label = f"hændelse {index + 1}"
        if not isinstance(raw_event, dict):
            issues.append(f"H3: {label} skal være et objekt")
            continue
        unknown = sorted(set(raw_event) - ALLOWED_EVENT)
        if unknown:
            issues.append(f"H3: {label} har ukendte felter: {', '.join(unknown)}")
        clause = raw_event.get("klausul")
        if not isinstance(clause, str) or not clause:
            issues.append(f"H1: {label} mangler en ikke-tom klausul")
            continue
        if clause not in text:
            issues.append(f"H1: {label}s klausul er ikke ordret substring af narrativet")

        date_raw = raw_event.get("date_raw")
        if date_raw is not None and not isinstance(date_raw, str):
            issues.append(f"H3: {label}.date_raw skal være tekst eller null")
            date_raw = None
        for year in YEAR_RE.findall(date_raw or ""):
            if year not in clause:
                issues.append(f"H2: år {year} fra {label}.date_raw findes ikke i klausulen")

        qualifier = raw_event.get("date_qualifier")
        if qualifier is not None and not isinstance(qualifier, str):
            issues.append(f"H3: {label}.date_qualifier skal være tekst eller null")
            qualifier = None
        if qualifier not in QUALIFIERS:
            issues.append(f"H3: {label}.date_qualifier er ugyldig: {qualifier}")
            qualifier = None
        date_info = daa_validate.derive_date_info(date_raw)
        derived_qualifier = date_info["qualifier"] or (qualifier if date_raw else None)

        span_start, span_length = _next_span(text, clause, used_offsets)
        if span_start is None:
            issues.append(f"H5: {label}s klausul har ingen ubrugt forekomst")

        base_key = normaliser_klausul(clause)
        key_counts[base_key] += 1
        suffix = f"#{key_counts[base_key]}" if key_counts[base_key] > 1 else ""

        category = raw_event.get("kategori")
        if category is not None and not isinstance(category, str):
            issues.append(f"H3: {label}.kategori skal være tekst eller null")
            category = "andet"
        if category is not None and category not in CATEGORIES:
            advisory.append(f"H7: ukendt kategori '{category}' i {label}; erstattet med andet")
            category = "andet"

        enriched_events.append({
            "klausul": clause,
            "date_raw": date_raw,
            "date_min": date_info["date_min"],
            "date_max": date_info["date_max"],
            "date_qualifier": derived_qualifier,
            "kategori": category,
            "span_start": span_start,
            "span_laengde": span_length,
            "noegle": base_key + suffix,
            "pass_version": PASS_VERSION,
        })

    escalation: list[str] = []
    year_count = len(YEAR_RE.findall(text))
    if year_count >= H8_YEAR_THRESHOLD and not events:
        msg = f"H8: narrativet har {year_count} år-tokens, men 0 udtrukne hændelser"
        advisory.append(msg)
        escalation.append(msg)
    escalation = issues + escalation
    enriched = {"narrative_id": narrative_id, "haendelser": enriched_events}
    return enriched, issues, advisory, escalation


def _read_extracted(directory: Path) -> tuple[dict[int, dict[str, Any]], dict[int, list[str]]]:
    records: dict[int, dict[str, Any]] = {}
    duplicates: dict[int, list[str]] = {}
    if not directory.exists():
        return records, duplicates
    for path in sorted(directory.glob("*.json")):
        try:
            obj = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        narrative_id = obj.get("narrative_id") if isinstance(obj, dict) else None
        if isinstance(narrative_id, int):
            if narrative_id in records:
                duplicates.setdefault(narrative_id, []).append(path.name)
            else:
                records[narrative_id] = obj
    return records, duplicates


def validate_all(
    sources: list[dict[str, Any]], extracted_by_id: dict[int, dict[str, Any]]
) -> tuple[
    list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]
]:
    clean: list[dict[str, Any]] = []
    review: list[dict[str, Any]] = []
    escalation: list[dict[str, Any]] = []
    advisories: list[dict[str, Any]] = []
    for source in sources:
        narrative_id = source.get("narrative_id")
        enriched, issues, advisory, reasons = validate_narrative(
            source, extracted_by_id.get(narrative_id)
        )
        if issues:
            review.append({
                "narrative_id": narrative_id,
                "brud": issues,
                "advisory": advisory,
                "udtraek": extracted_by_id.get(narrative_id),
            })
        elif enriched is not None:
            clean.append(enriched)
        if advisory:
            advisories.append({"narrative_id": narrative_id, "advisory": advisory})
        if reasons:
            escalation.append({"narrative_id": narrative_id, "grunde": reasons})
    return clean, review, escalation, advisories


def _write_json(path: str, value: Any) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("narrativer")
    parser.add_argument("extracted_dir")
    parser.add_argument("--clean", required=True)
    parser.add_argument("--review", required=True)
    parser.add_argument("--escalate", required=True)
    args = parser.parse_args()

    sources = json.loads(Path(args.narrativer).read_text(encoding="utf-8"))
    if not isinstance(sources, list):
        raise SystemExit("narrativer.json skal være en liste")
    extracted, duplicates = _read_extracted(Path(args.extracted_dir))
    clean, review, escalation, advisories = validate_all(sources, extracted)
    for narrative_id, files in duplicates.items():
        clean = [r for r in clean if r["narrative_id"] != narrative_id]
        reason = f"H3: flere udtræksfiler for narrative_id {narrative_id}: {', '.join(files)}"
        review.append({"narrative_id": narrative_id, "brud": [reason], "advisory": []})
        escalation.append({"narrative_id": narrative_id, "grunde": [reason]})

    _write_json(args.clean, clean)
    _write_json(args.review, review)
    _write_json(args.escalate, escalation)
    advisory_count = sum(len(r["advisory"]) for r in advisories)
    for entry in advisories:
        for advisory in entry["advisory"]:
            print(
                f'[validate-haendelser] ~ narrative {entry["narrative_id"]}: {advisory}',
                file=sys.stderr,
            )
    print(
        f"[validate-haendelser] {len(clean)} rene, {len(review)} i review, "
        f"{len(escalation)} til eskalering, {advisory_count} advisory",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
