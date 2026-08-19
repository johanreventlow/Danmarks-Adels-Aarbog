#!/usr/bin/env python3
"""Byg fase C0's kandidatliste: de 41 »ægte nye« kilderecords mod prods
1939-personer.

Read-only, deterministisk. Skriver intet til databasen, producerer intet
manifest og autoriserer ingenting -- kun beslutningsgrundlag til det
menneskelige review.

Baggrund: fase B efterlod narrativer med gammel tekst, fordi 41 records
blev klassificeret ``accepted_genuinely_new_source_record`` /
``person_creation: forbidden`` uden baseline-tilknytning. C0 omgør de
klassifikationer, og fordi den oprindelige klassifikation var
model-assisteret, skal omgørelsen være genkørbar og reviewbar.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

_SCRIPTS_DIR = Path(__file__).resolve().parent

# Hash-låst grundlag. Filnavne-versionering (source-record-reconciliation-v33
# ... -v49) er IKKE en ordning og må aldrig bruges til at vælge input --
# strømmen hedder v50, mens filerne hedder v33-v49. Hash-låsen er båndet.
LOCKED_IMPORT_PREVIEW_SHA256 = "04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5"
LOCKED_DATABASE_PREVIEW_SHA256 = "a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c"
LOCKED_BOUNDARY_SHA256 = "73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f"
LOCKED_CALAMARI_SHA256 = "020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37"
# Task 25's produktionsmanifest -- samme hash som fase A og B låste. Dets 8
# person_creates er records fra netop denne mængde, som ALLEREDE er
# materialiseret i prod (personerne 1846-1853). Import-preview er fra
# 2026-08-17, altså før task 25 kørte, så den ved det ikke.
LOCKED_PRODUCTION_MANIFEST_SHA256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"

CALAMARI_RENDITION_ID = "daa-1939-calamari-r6-clean"
CALAMARI_SOURCE_ID = "1939"

EXPECTED_GENUINELY_NEW = 41

CLASSES = ("kobling", "gennemgang", "for_kort", "sammenlaegning", "aegte_ny",
           "allerede_materialiseret")

# Positivt anker: bekræftet sandt positiv. Recorden dækker s. 574-575, og
# person 1299 bærer i prod netop den tekst.
CALIBRATION_RECORD_KEY = "record-82f49e95-e5ce-4e08-9840-d0e334b4ba50"
CALIBRATION_PERSON_ID = 1299

# Negativt anker: valgt empirisk efter første kørsel (planens Task 3, step 5b).
# Recorden er en ren strukturel overgangstekst -- «Fra ovennævnte Joachim
# Reventlow til Rixdorf nedstammer den yngre holstenske Linje ... uddøde i
# Mandsstammen 1783» -- den handler om en LINJE, ikke om én person, og må
# aldrig blive en kobling uanset hvordan tærsklerne justeres.
NEGATIVE_ANCHOR_RECORD_KEY = "record-4ba8b3b2-a4d4-40e6-b4f9-1a0aaf8b4cfa"

# Alarmgrænse, ikke en sandhed: 41 records mod ~26 personer med gammel tekst
# gør et stort antal koblinger usandsynligt. Rammer den, er tærsklerne løse.
MAX_PLAUSIBLE_KOBLING = 25


def _fail(code: str) -> None:
    print(code, file=sys.stderr)
    sys.exit(2)


def _import_match_module():
    """Importér søstermodulet via importlib (ikke bar import), så scriptet
    virker uanset kalderens working directory -- samme mønster som
    build_narrative_replacement_manifest_1939_v50.py."""
    spec = importlib.util.spec_from_file_location(
        "match_c0_records_1939_v50", _SCRIPTS_DIR / "match_c0_records_1939_v50.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


match = _import_match_module()


def load_locked(path: Path, expected_sha256: str, failure_code: str) -> Dict[str, Any]:
    raw = Path(path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected_sha256:
        _fail(failure_code)
    return json.loads(raw.decode("utf-8"))


def load_free(path: Path, failure_code: str) -> Any:
    """Læs en fil hvis hash IKKE er låst (den friske prod-eksport), men
    registrér dens hash, så outputtet kan spores til præcis dette input."""
    try:
        raw = Path(path).read_bytes()
    except OSError:
        _fail(failure_code)
    return json.loads(raw.decode("utf-8")), hashlib.sha256(raw).hexdigest()


def boundary_pages(boundary: Dict[str, Any], records_by_key: Dict[str, Dict[str, Any]],
                   calamari_sha256: str) -> Dict[str, Dict[str, int]]:
    """Slå side op pr. record via boundary-materialiseringens ankre.

    Samme opslag og samme fail-closed adfærd som fase A's manifest-bygger:
    ankeret (char_from, char_to) skal findes, og dets verbatim_text skal
    matche byte-for-byte -- ellers er de to artefakter drevet fra hinanden,
    og et sidetal ville være gætteri."""
    review = boundary.get("source_record_review") if isinstance(boundary, dict) else None
    if (not isinstance(review, dict) or boundary.get("schema_version") != "1.0" or
            review.get("schema_version") != "1.0" or
            review.get("source_id") != CALAMARI_SOURCE_ID or
            review.get("rendition_id") != CALAMARI_RENDITION_ID or
            review.get("rendition_sha256") != calamari_sha256 or
            not isinstance(review.get("records"), list)):
        _fail("C0_LINKAGE_BOUNDARY_INVALID")
    by_anchor: Dict[Any, Dict[str, Any]] = {}
    for row in review["records"]:
        if not isinstance(row, dict):
            _fail("C0_LINKAGE_BOUNDARY_INVALID")
        anchor, span = row.get("source_anchor"), row.get("span")
        if (not isinstance(anchor, dict) or set(anchor) != {"char_from", "char_to"} or
                not isinstance(span, dict) or not isinstance(span.get("page_from"), int) or
                not isinstance(span.get("page_to"), int) or span["page_from"] < 1 or
                span["page_to"] < span["page_from"] or
                not isinstance(row.get("verbatim_text"), str)):
            _fail("C0_LINKAGE_BOUNDARY_INVALID")
        key = (anchor["char_from"], anchor["char_to"])
        if key in by_anchor:
            _fail("C0_LINKAGE_BOUNDARY_INVALID")
        by_anchor[key] = row
    result: Dict[str, Dict[str, int]] = {}
    for key, source in records_by_key.items():
        span = source["source_span"]
        row = by_anchor.get((span["char_from"], span["char_to"]))
        if row is None or row.get("verbatim_text") != source["verbatim_text"]:
            _fail(f"C0_LINKAGE_BOUNDARY_LOOKUP_FAILED:{key}")
        result[key] = {"page_from": row["span"]["page_from"],
                       "page_to": row["span"]["page_to"]}
    return result


def build_records(records: List[Dict[str, Any]], persons: List[Dict[str, Any]],
                  pages_by_key: Dict[str, Dict[str, int]],
                  prefilter_stats: Optional[Dict[str, int]] = None,
                  materialized_keys: Optional[set] = None) -> List[Dict[str, Any]]:
    """``materialized_keys`` er records der allerede blev til personer i task
    25. De klassificeres ``allerede_materialiseret`` uanset tekstsignal --
    det er et faktum om databasen, ikke en vurdering af lighed. Uden dem
    ville arket foreslå at koble syv records, hvis arbejde for længst er
    gjort, og hvis narrativ allerede har en (UNIQUE) binding."""
    materialized_keys = materialized_keys or set()
    person_skeletons = [(p, match.text_skeleton(p["tekst"])) for p in persons]
    out: List[Dict[str, Any]] = []
    for record in sorted(records, key=lambda r: r["new_record_key"]):
        verbatim = record["verbatim_text"]
        record_skeleton = match.text_skeleton(verbatim)
        pages = pages_by_key.get(record["new_record_key"])
        candidates: List[Dict[str, Any]] = []
        for person, person_skeleton in person_skeletons:
            if prefilter_stats is not None:
                prefilter_stats["pairs_total"] = prefilter_stats.get("pairs_total", 0) + 1
            # Forfilteret er en optimering, ikke en beslutning -- og det tælles,
            # så et stille loft aldrig kan læses som fuld dækning.
            if not match.shares_ngram(record_skeleton, person_skeleton):
                if prefilter_stats is not None:
                    prefilter_stats["pairs_skipped"] = prefilter_stats.get("pairs_skipped", 0) + 1
                continue
            scores = match.similarity(record_skeleton, person_skeleton)
            if (scores["coverage"] < match.CANDIDATE_COVERAGE
                    and scores["containment"] == "none"):
                continue
            # Ankerkravet er diskriminatoren: uden det gør min-normaliseringen
            # korte modparter promiskuøse (spredte bogstaver -> coverage 1.0).
            if not match.has_anchor(scores, len(record_skeleton), len(person_skeleton)):
                continue
            candidates.append({
                "person_id": person["person_id"],
                "visning_navn": person["visning_navn"],
                "staged": person["staged"],
                "side": person.get("side"),
                "ratio": scores["ratio"],
                "coverage": scores["coverage"],
                "longest": scores["longest"],
                "containment": scores["containment"],
                "name_signal": match.name_signal(verbatim, person["visning_navn"]),
                "page_signal": match.page_signal(pages, person.get("side")),
                "person_tekst": person["tekst"],
            })
        candidates.sort(key=lambda c: (-c["coverage"], c["person_id"]))
        if record["new_record_key"] in materialized_keys:
            classification = "allerede_materialiseret"
        else:
            classification = match.classify(candidates, len(record_skeleton))
        if classification == "for_kort":
            # Kandidatlisten er ordsammenfald; de fem bedste vises alene til
            # orientering, så arket ikke drukner i støj.
            candidates = candidates[:5]
        out.append({
            "new_record_key": record["new_record_key"],
            "source_span": record["source_span"],
            "pages": pages,
            "verbatim_text": verbatim,
            "skeleton_len": len(record_skeleton),
            "classification": classification,
            "candidates": candidates,
        })
    return out


def build_closure(records: List[Dict[str, Any]], old_text_persons: List[int],
                  database_only_persons: List[int]) -> Dict[str, Any]:
    """Adskil FORKLARET fra LØST.

    *Forklaret* = mindst én record peger på personen. En person ingen record
    peger på, er fasens ægte fund: så er hypotesen om fejlklassifikation
    ufuldstændig for netop den.

    *Løst i C0* = forklaret af en record der kan afgøres nu (kobling eller
    gennemgang). Fragmentposterne forklarer, men løser ikke -- de er udskudt
    til C3.

    ``for_kort`` bidrager til INGEN af delene: dens kandidater er
    ordsammenfald, ikke evidens, og at lade dem tælle som forklaring ville
    skjule ægte uforklarede personer bag støj."""
    explained = set()
    resolvable = set()
    short_hint = set()
    for record in records:
        if record["classification"] == "allerede_materialiseret":
            # Ligger uden for C0's handlingsrum: personen findes, teksten er
            # rigtig, bindingen er der. Den hverken forklarer eller løser
            # noget af det, C0 skal afgøre.
            continue
        if record["classification"] == "for_kort":
            # Bidrager ikke til forklaringen, men noteres særskilt: en person
            # der KUN berøres af en for kort record er ikke helt uden spor,
            # og at kalde den 'uforklaret' uden forbehold ville være for hårdt.
            for candidate in record["candidates"]:
                short_hint.add(candidate["person_id"])
            continue
        for candidate in record["candidates"]:
            explained.add(candidate["person_id"])
            if record["classification"] in ("kobling", "gennemgang"):
                resolvable.add(candidate["person_id"])
    old_text = sorted(set(old_text_persons))
    database_only = sorted(set(database_only_persons))
    return {
        "old_text_persons": old_text,
        "old_text_explained": sorted(p for p in old_text if p in explained),
        "old_text_unexplained": sorted(p for p in old_text if p not in explained),
        "old_text_resolved_in_c0": sorted(p for p in old_text if p in resolvable),
        "old_text_deferred_c3": sorted(
            p for p in old_text if p in explained and p not in resolvable),
        "old_text_only_short_record_hint": sorted(
            p for p in old_text if p not in explained and p in short_hint),
        "database_only_persons": database_only,
        "database_only_unexplained": sorted(p for p in database_only if p not in explained),
    }


# ---------------------------------------------------------------------------
# gates
# ---------------------------------------------------------------------------

def assert_calibration(built: List[Dict[str, Any]]) -> None:
    """Positivt anker: beviser at tærsklerne ikke er for STRAMME."""
    calibration = next(
        (r for r in built if r["new_record_key"] == CALIBRATION_RECORD_KEY), None)
    if calibration is None:
        _fail("C0_LINKAGE_CALIBRATION_RECORD_MISSING")
    if (calibration["classification"] != "kobling" or not calibration["candidates"] or
            calibration["candidates"][0]["person_id"] != CALIBRATION_PERSON_ID):
        _fail(f"C0_LINKAGE_CALIBRATION_FAILED:{calibration['classification']}")


def assert_negative_anchor(built: List[Dict[str, Any]]) -> None:
    """Negativt anker: beviser at tærsklerne ikke er for LØSE.

    Uden dette kunne enhver opblødning af tærsklerne passere kalibreringen,
    som kun straffer for stramme grænser."""
    negative = next(
        (r for r in built if r["new_record_key"] == NEGATIVE_ANCHOR_RECORD_KEY), None)
    if negative is None:
        _fail("C0_LINKAGE_NEGATIVE_ANCHOR_MISSING")
    if negative["classification"] != "aegte_ny":
        _fail(f"C0_LINKAGE_NEGATIVE_ANCHOR_FAILED:{negative['classification']}")


def assert_no_person_claimed_twice(built: List[Dict[str, Any]]) -> None:
    """To poster der begge peger på samme person er en selvmodsigelse, som
    arket ikke afslører: linjerne står langt fra hinanden, hver især
    plausible. Det er også netop hvad en for løs tærskel producerer."""
    claimed: Dict[int, str] = {}
    for record in built:
        if record["classification"] not in ("kobling", "gennemgang") or not record["candidates"]:
            continue
        top = record["candidates"][0]["person_id"]
        if top in claimed:
            _fail(f"C0_LINKAGE_PERSON_CLAIMED_TWICE:{top}:{claimed[top]}:{record['new_record_key']}")
        claimed[top] = record["new_record_key"]


def assert_kobling_distribution_plausible(built: List[Dict[str, Any]]) -> None:
    """Alarm, ikke sandhed. Flyder korpus ind som koblinger, er tærsklerne
    løse -- og et menneskes realistiske adfærd over for 41 udfyldte
    [KOBL]-anbefalinger er at acceptere dem."""
    count = sum(1 for r in built if r["classification"] == "kobling")
    if count > MAX_PLAUSIBLE_KOBLING:
        _fail(f"C0_LINKAGE_KOBLING_DISTRIBUTION_IMPLAUSIBLE:{count}")


# ---------------------------------------------------------------------------
# rapport
# ---------------------------------------------------------------------------

def render_report(document: Dict[str, Any]) -> str:
    counts = document["counts"]
    closure = document["closure"]
    prefilter = document["prefilter"]
    lines = [
        "# DAA 1939 v50 — fase C0: kandidatliste", "",
        "Read-only. Ingen prod-skrivning, intet manifest, ingen autorisation.", "",
        "## Input (SHA-256)", "",
    ]
    for name, digest in sorted(document["input_hashes"].items()):
        lines.append(f"- `{name}`: `{digest}`")
    lines += ["", "## Klassefordeling", ""]
    for key in CLASSES:
        lines.append(f"- {key}: {counts[key]}")
    lines += [
        "", f"- records i alt: {counts['records']}",
        "", "## Lukning begge veje", "",
        f"- personer m. gammel tekst: {len(closure['old_text_persons'])}",
        f"- heraf forklaret: {len(closure['old_text_explained'])}",
        f"- heraf løst i C0: {len(closure['old_text_resolved_in_c0'])}",
        f"- heraf udskudt til C3: {len(closure['old_text_deferred_c3'])}",
        f"- **uforklaret: {len(closure['old_text_unexplained'])}** "
        f"→ {closure['old_text_unexplained']}",
        f"  - heraf berørt af en for kort record (ikke helt uden spor): "
        f"{closure['old_text_only_short_record_hint']}",
        "",
        f"- database_only (preview 2026-08-17): {len(closure['database_only_persons'])}",
        f"- **heraf uforklaret: {len(closure['database_only_unexplained'])}** "
        f"→ {closure['database_only_unexplained']}",
        "", "## Forfilter", "",
        f"- par i alt: {prefilter.get('pairs_total', 0)}",
        f"- sprunget over (intet fælles {match.NGRAM}-gram): {prefilter.get('pairs_skipped', 0)}",
        "",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--import-preview", required=True)
    parser.add_argument("--database-preview", required=True)
    parser.add_argument("--boundary", required=True)
    parser.add_argument("--calamari", required=True)
    parser.add_argument("--production-manifest", required=True)
    parser.add_argument("--narrative-state", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report")
    args = parser.parse_args(argv)

    output = Path(args.output)
    if output.exists():
        _fail("C0_LINKAGE_OUTPUT_EXISTS")

    import_preview = load_locked(Path(args.import_preview), LOCKED_IMPORT_PREVIEW_SHA256,
                                 "C0_LINKAGE_IMPORT_PREVIEW_HASH_MISMATCH")
    database_preview = load_locked(Path(args.database_preview), LOCKED_DATABASE_PREVIEW_SHA256,
                                   "C0_LINKAGE_DATABASE_PREVIEW_HASH_MISMATCH")
    boundary = load_locked(Path(args.boundary), LOCKED_BOUNDARY_SHA256,
                           "C0_LINKAGE_BOUNDARY_HASH_MISMATCH")
    calamari_raw = Path(args.calamari).read_bytes()
    calamari_sha256 = hashlib.sha256(calamari_raw).hexdigest()
    if calamari_sha256 != LOCKED_CALAMARI_SHA256:
        _fail("C0_LINKAGE_CALAMARI_HASH_MISMATCH")
    production_manifest = load_locked(
        Path(args.production_manifest), LOCKED_PRODUCTION_MANIFEST_SHA256,
        "C0_LINKAGE_PRODUCTION_MANIFEST_HASH_MISMATCH")
    narrative_state, narrative_state_sha256 = load_free(
        Path(args.narrative_state), "C0_LINKAGE_NARRATIVE_STATE_UNREADABLE")

    pending = import_preview.get("genuinely_new_pending")
    if not isinstance(pending, list) or len(pending) != EXPECTED_GENUINELY_NEW:
        _fail(f"C0_LINKAGE_GENUINELY_NEW_COUNT_UNEXPECTED:"
              f"{len(pending) if isinstance(pending, list) else 'invalid'}")

    rows = narrative_state.get("rows")
    if not isinstance(rows, list) or narrative_state.get("schema_version") != "1.0":
        _fail("C0_LINKAGE_NARRATIVE_STATE_INVALID")

    # Gammel tekst = intet record-binding. Proxyen er verificeret mod den
    # empiriske liste i planens Task 1, step 6b.
    old_text_persons = [r["person_id"] for r in rows if not r["har_record_binding"]]
    database_only_persons = [
        row["person_id"] for row in database_preview["person_anchors"]["database_only"]]

    records_by_key = {r["new_record_key"]: r for r in pending}
    pages_by_key = boundary_pages(boundary, records_by_key, calamari_sha256)

    materialized_keys = {p["source_record_key"] for p in production_manifest["person_creates"]}
    if not materialized_keys <= set(records_by_key):
        _fail("C0_LINKAGE_MATERIALIZED_KEY_OUTSIDE_PENDING")

    prefilter_stats: Dict[str, int] = {"pairs_total": 0, "pairs_skipped": 0}
    built = build_records(pending, rows, pages_by_key, prefilter_stats, materialized_keys)

    assert_calibration(built)
    assert_negative_anchor(built)
    assert_no_person_claimed_twice(built)
    assert_kobling_distribution_plausible(built)

    counts = {"records": len(built)}
    for key in CLASSES:
        counts[key] = sum(1 for r in built if r["classification"] == key)

    document = {
        "schema_version": "1.0",
        "compare_version": match.COMPARE_VERSION,
        "generator": "build_c0_record_linkage_1939_v50.py:v1",
        "input_hashes": {
            "import_preview_sha256": LOCKED_IMPORT_PREVIEW_SHA256,
            "database_preview_sha256": LOCKED_DATABASE_PREVIEW_SHA256,
            "boundary_sha256": LOCKED_BOUNDARY_SHA256,
            "production_manifest_sha256": LOCKED_PRODUCTION_MANIFEST_SHA256,
            "calamari_sha256": calamari_sha256,
            "narrative_state_sha256": narrative_state_sha256,
        },
        "thresholds": {
            "candidate_coverage": match.CANDIDATE_COVERAGE,
            "strong_coverage": match.STRONG_COVERAGE,
            "min_skeleton_chars": match.MIN_SKELETON_CHARS,
            "ngram": match.NGRAM,
        },
        "counts": counts,
        "prefilter": dict(prefilter_stats, ngram=match.NGRAM),
        "closure": build_closure(built, old_text_persons, database_only_persons),
        "records": built,
    }

    output.write_text(
        json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8")
    if args.report:
        Path(args.report).write_text(render_report(document), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
