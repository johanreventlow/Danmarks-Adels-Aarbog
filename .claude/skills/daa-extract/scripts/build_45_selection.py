#!/usr/bin/env python3
"""Udvalget til dagsværk 4.5 (spec §8.1): 24 nye poster + 6 i reserve oven i 4.3b's 10.

Deterministisk og hash-bundet: længdegrænser, regulære udtryk, dækningskrav og
algoritmeversion indgår alle i `strata_sha256`.

Spec §8.1's akser »gift«-udsagn og indgiftede måles samlet af gift-antallet (V4): i
2018-20 optræder indgiftede som ægtefællen i et slægtsmedlems post, og tekstens egne
udsagn er et signal, der ikke skifter betydning, når flere slægter indlæses.
Printer kun nøgler, tal og hashes — aldrig tekst.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from evidence_runner import (EligibilityError, canonical_record_input, check_eligibility,
                             load_ledger, sha256_text)

STRATA_VERSION = "45-strata-v3"
LAENGDE_GRAENSER = (200, 800)
GIFT_RE = re.compile(r"\b(?:gift|ægte\w*)", re.IGNORECASE)
TITEL_RE = re.compile(
    r"\b(?:kammerherre|hofjægermester|lensgreve|greve|baron|godsejer|amtmand|"
    r"stiftamtmand|generalmajor|oberst|kaptajn|ritmester|premierløjtnant|minister|"
    r"gehejmeråd|konferensråd|etatsråd|kammerjunker|hofmarskal|stiftsdame|hofdame)\b",
    re.IGNORECASE)
USIKKER_RE = re.compile(r"(?:\bca\.|\bomkr\.|\?|\b\d{3,4}/\d{2,4}\b)", re.IGNORECASE)
HENVISNING_RE = re.compile(r"\bse\b", re.IGNORECASE)
KRAV = {"gift_mindst_et": 9, "gift_flere": 3, "usikker_dato": 3, "titel": 6}
BUNDT = 6
RESERVE = 6


class SelectionCoverageError(RuntimeError):
    pass


def gift_antal(tekst: str) -> int:
    return len(GIFT_RE.findall(tekst))


def features(record: dict) -> dict:
    tekst = record["post_verbatim_text"]
    n, g = len(tekst), gift_antal(tekst)
    kort, middel = LAENGDE_GRAENSER
    return {
        "laengde": "kort" if n < kort else ("middel" if n < middel else "lang"),
        "gift": "0" if g == 0 else ("1" if g == 1 else "2+"),
        "gift_mindst_et": g >= 1,
        "gift_flere": g >= 2,
        "titel": bool(TITEL_RE.search(tekst)),
        "usikker_dato": bool(USIKKER_RE.search(tekst)),
    }


def er_henvisning(record: dict) -> bool:
    tekst = record["post_verbatim_text"]
    return len(tekst) < 100 and bool(HENVISNING_RE.search(tekst))


def coverage(records: dict, keys: list[str]) -> dict[str, int]:
    out = {akse: 0 for akse in KRAV}
    for k in keys:
        f = features(records[k])
        for akse in KRAV:
            out[akse] += f[akse]
    return out


def definition_sha256() -> str:
    return sha256_text(STRATA_VERSION + "|" + json.dumps(
        {"laengde": LAENGDE_GRAENSER, "gift": GIFT_RE.pattern, "titel": TITEL_RE.pattern,
         "usikker": USIKKER_RE.pattern, "henvisning": HENVISNING_RE.pattern,
         "krav": KRAV, "bundt": BUNDT,
         "reserve": RESERVE, "algoritme": "laengde-x-gift-rundgang-sjaeldne-foerst-v1"},
        sort_keys=True))


def select_new(records: dict, eligible: list[str], exclude: set[str],
               count: int, reserve: int = 0) -> tuple[list[str], list[str]]:
    strata: dict[tuple[str, str], list[str]] = {}
    for k in sorted(set(eligible) - exclude):
        if er_henvisning(records[k]):
            continue
        f = features(records[k])
        strata.setdefault((f["laengde"], f["gift"]), []).append(k)
    for bucket in strata.values():
        bucket.sort(key=lambda k: (-sum(features(records[k])[a] for a in KRAV), k))
    navne = sorted(strata)
    raekke: list[str] = []
    i = 0
    while len(raekke) < count + reserve and any(strata[n] for n in navne):
        bucket = strata[navne[i % len(navne)]]
        if bucket:
            raekke.append(bucket.pop(0))
        i += 1
    valgt, reserve_keys = raekke[:count], raekke[count:]
    daekning = coverage(records, valgt)
    if any(daekning[a] < krav for a, krav in KRAV.items()) or len(valgt) < count:
        raise SelectionCoverageError("SELECTION_COVERAGE valgt=%d " % len(valgt) + " ".join(
            f"{a}={daekning[a]}" for a in KRAV))
    return valgt, reserve_keys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runner-input", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--exclude-selection", required=True, help="4.3b's udvalgsfil")
    ap.add_argument("--out", required=True)
    ap.add_argument("--count", type=int, default=24)
    args = ap.parse_args()

    records = json.loads(Path(args.runner_input).read_text(encoding="utf-8"))["records"]
    ledger = load_ledger(json.loads(Path(args.ledger).read_text(encoding="utf-8")))
    exclude = set(json.loads(Path(args.exclude_selection).read_text(encoding="utf-8"))["records"])

    eligible = []
    for key, rec in records.items():
        try:
            check_eligibility(ledger, key, canonical_record_input(rec))
        except EligibilityError:
            continue
        eligible.append(key)
    henvisninger = sum(1 for k in eligible if k not in exclude and er_henvisning(records[k]))

    try:
        valgt, reserve = select_new(records, eligible, exclude, args.count, RESERVE)
    except SelectionCoverageError as exc:
        print(str(exc))
        return 1

    bundter = {f"bundt_{n + 1}": valgt[i:i + BUNDT]
               for n, i in enumerate(range(0, len(valgt), BUNDT))}
    if reserve:
        bundter["reserve"] = reserve
    alle = valgt + reserve
    udvalg = {
        "strata_version": STRATA_VERSION,
        "strata_sha256": definition_sha256(),
        "ledger_sha256": hashlib.sha256(Path(args.ledger).read_bytes()).hexdigest(),
        "records": alle,
        "hovedudvalg": valgt,
        "reserve": reserve,
        "bundter": bundter,
        "udelukket_allerede_koert": sorted(exclude),
        "udelukket_henvisninger": henvisninger,
        "daekning": coverage(records, valgt),
        "record_input_sha256": {k: canonical_record_input(records[k]) for k in alle},
    }
    out = Path(args.out)
    out.write_text(json.dumps(udvalg, ensure_ascii=False, indent=2), encoding="utf-8")
    out.chmod(0o600)
    print(f"UDVALG_OK nye={len(valgt)} reserve={len(reserve)} bundter={len(bundter)} "
          f"henvisninger_udelukket={henvisninger}")
    print(f"  daekning {udvalg['daekning']}")
    print(f"  strata_sha256 {udvalg['strata_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
