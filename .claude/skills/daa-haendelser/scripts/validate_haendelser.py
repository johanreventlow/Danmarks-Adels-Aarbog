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


# H9: relative datoer (s.å./s. A./d. A. = samme år, s.m. = samme måned, s.d. = samme dag).
# daa-extract's parser opløser dem bevidst ikke (fakta-laget: falsk opløsning bryder evidensen).
# Hændelseslaget er regenererbar formidling, og klausulen står ordret i narrativet, så her
# opløses de fra den nærmeste foregående dato i SAMME narrativ — konservativt: et nyt årstal
# nulstiller måned/dag, så s.m./s.d. aldrig gættes ud fra en dato i et andet år. date_raw
# forbliver ordret; kun bounds udledes, og hver opløsning logges som H9-advisory.
_MAANED = {
    "januar": 1, "jan": 1, "februar": 2, "febr": 2, "feb": 2, "marts": 3, "mar": 3,
    "april": 4, "apr": 4, "maj": 5, "mai": 5, "juni": 6, "jun": 6, "juli": 7, "jul": 7,
    "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9, "oktober": 10, "okt": 10,
    "oct": 10, "november": 11, "nov": 11, "december": 12, "decbr": 12, "dec": 12,
}
_MAANED_NAVN = ["jan.", "febr.", "marts", "april", "maj", "juni", "juli", "aug.", "sept.", "okt.", "nov.", "dec."]
_MON = "(?:" + "|".join(sorted(_MAANED, key=len, reverse=True)) + r")(?![a-zæøå])"
_AAR_KERNE = r"(?:1[0-9]{3}|20[0-9]{2})"
_AAR = rf"(?<!\d)({_AAR_KERNE})(?!\d)"
_DATO_TOKEN = re.compile(
    rf"(?P<a>(?<!\d)(?P<ad>\d{{1,2}})\.?\s+(?P<am>{_MON})\.?\s+(?P<ay>{_AAR_KERNE})(?!\d))"
    rf"|(?P<b>(?<!\d)(?P<by>{_AAR_KERNE})\s*\(\s*(?P<bd>\d{{1,2}})\.?\s+(?P<bm>{_MON}))"
    rf"|(?P<y>{_AAR})"
    rf"|(?P<c>(?<!\d)(?P<cd>\d{{1,2}})\.?\s+(?P<cm>{_MON}))"
    rf"|(?P<m>\(\s*(?P<mm>{_MON}))",
    re.IGNORECASE,
)
_REL_AAR = re.compile(r"\bs\.\s?[åa]\.|\bs\.\s?a\.(?=\s|$|[,;)(-])|\bd\.\s?[aå]\.", re.IGNORECASE)
_REL_MAANED = re.compile(r"\bs\.\s?m\.", re.IGNORECASE)
_REL_DAG = re.compile(r"\bs\.\s?d\.", re.IGNORECASE)


def _dato_tilstand(prefix: str) -> tuple[int | None, int | None, int | None]:
    """(år, måned, dag) for den seneste dato i prefix, læst fra venstre mod højre."""
    y = m = d = None
    for tok in _DATO_TOKEN.finditer(prefix):
        if tok.group("a"):
            y, m, d = int(tok.group("ay")), _MAANED[tok.group("am").lower()], int(tok.group("ad"))
        elif tok.group("b"):
            y, m, d = int(tok.group("by")), _MAANED[tok.group("bm").lower()], int(tok.group("bd"))
        elif tok.group("y"):
            y, m, d = int(tok.group("y")), None, None
        elif tok.group("c") and y is not None:
            m, d = _MAANED[tok.group("cm").lower()], int(tok.group("cd"))
        elif tok.group("m") and y is not None:
            m, d = _MAANED[tok.group("mm").lower()], None
    return y, m, d


def kontekst_dato(prefix: str, date_raw: str) -> tuple[dict[str, Any], str] | None:
    """Opløs s.å./s.m./s.d. i date_raw fra prefix; None hvis ikke entydigt muligt."""
    y, m, d = _dato_tilstand(prefix)
    if y is None:
        return None
    sub = date_raw
    if _REL_DAG.search(sub):
        if m is None or d is None:
            return None
        sub = _REL_DAG.sub(f"{d}. {_MAANED_NAVN[m - 1]} {y}", sub, count=1)
    elif _REL_MAANED.search(sub):
        if m is None:
            return None
        sub = _REL_MAANED.sub(f"{_MAANED_NAVN[m - 1]} {y}", sub, count=1)
    elif _REL_AAR.search(sub):
        sub = _REL_AAR.sub(str(y), sub, count=1)
    else:
        return None
    info = daa_validate.derive_date_info(sub)
    if info["date_min"] is None and info["date_max"] is None:
        return None
    return info, sub


def parker_udaterede(clean: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Tag hændelser uden nogen datogrænse ud af clean (til senere gennemgang).

    Narrativet bliver i clean (evt. med tom liste), så loaderens merge stadig dækker det.
    """
    kept: list[dict[str, Any]] = []
    parked: list[dict[str, Any]] = []
    for record in clean:
        beholdt = []
        for event in record.get("haendelser", []):
            if event.get("date_min") is None and event.get("date_max") is None:
                parked.append({"narrative_id": record["narrative_id"], "grund": "ingen datogrænse", "haendelse": event})
            else:
                beholdt.append(event)
        kept.append({**record, "haendelser": beholdt})
    return kept, parked


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
        span_start, span_length = _next_span(text, clause, used_offsets)
        if span_start is None:
            issues.append(f"H5: {label}s klausul har ingen ubrugt forekomst")

        date_info = daa_validate.derive_date_info(date_raw)
        if (date_raw and span_start is not None and date_info["date_min"] is None
                and date_info["date_max"] is None and date_raw in clause):
            prefix = text[:span_start] + clause[:clause.find(date_raw)]
            resolved = kontekst_dato(prefix, date_raw)
            if resolved is not None:
                date_info, via = resolved
                advisory.append(
                    f"H9: {label}: '{date_raw}' udledt af konteksten som '{via}' "
                    f"({date_info['date_min']}..{date_info['date_max']})"
                )
        derived_qualifier = date_info["qualifier"] or (qualifier if date_raw else None)

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
