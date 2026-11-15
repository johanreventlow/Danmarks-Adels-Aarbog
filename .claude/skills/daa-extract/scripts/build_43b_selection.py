#!/usr/bin/env python3
"""Model-fri preflight og stratificeret udvalg til 4.3b (plan Task 0 Step 9 + Task 1).

Kører INGEN model. Den validerer, at hvert runner-input kan sendes — og vælger
derefter de ti records, kørslen skal omfatte.

Preflighten er fail-closed: fejler ét record, stopper dagsværket her, før noget
sendes. Det er billigere at opdage en brudt kæde uden et modelkald end midt i et.

Udvalget er **stratificeret** (anden læsers R11): et alfabetisk prefix er
deterministisk, men kan være homogent, og dagsværkets formål er netop at møde
forkortelser, OCR-støj, indskud og ortografi. Strata defineres på målbare signaler
og vælges deterministisk indenfor.

Printer kun nøgler, tal og hashes — aldrig biografitekst.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from private_io import write_private_replace  # noqa: E402

from evidence_runner import (EligibilityError, canonical_record_input, check_eligibility,
                             load_ledger, sha256_text)

#: Strata-definitionen hashes og skrives ned FØR udvælgelsen, så den ikke kan
#: justeres bagefter til at give et pænere udvalg.
STRATA_VERSION = "43b-strata-v1"


def strata_of(record: dict) -> str:
    """Hvilket stratum hører recorden til?

    Signalerne er valgt, fordi de er målbare uden at læse teksten som menneske og
    fordi de rammer netop de vanskeligheder, dagsværket skal undersøge.
    """
    clauses = record["clauses"]
    n = len(clauses)
    tekstlaengde = len(record["post_verbatim_text"])
    har_forkortelse = any("." in c["verbatim_text"][:-1] for c in clauses)
    har_parentes = any("(" in c["verbatim_text"] for c in clauses)

    if n == 1:
        return "enkelt-klausul"
    if n >= 8:
        return "mange-klausuler"
    if tekstlaengde > 1500:
        return "lang-tekst"
    if har_forkortelse and har_parentes:
        return "forkortelser-og-parenteser"
    if har_forkortelse:
        return "forkortelser"
    return "almindelig"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runner-input", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--count", type=int, default=10)
    args = ap.parse_args()

    runner_input = json.loads(Path(args.runner_input).read_text(encoding="utf-8"))
    ledger = load_ledger(json.loads(Path(args.ledger).read_text(encoding="utf-8")))
    records = runner_input["records"]

    # --- preflight -------------------------------------------------------
    eligible, afvist = [], {}
    for key, rec in records.items():
        try:
            check_eligibility(ledger, key, canonical_record_input(rec))
        except EligibilityError as exc:
            afvist[key] = str(exc).split()[0]
            continue
        # Ordinaler skal være 1..n uden huller, og hver klausultekst skal matche
        # sin egen hash — ellers er grundlaget for claim-valideringen skredet.
        ordinaler = [c["ordinal"] for c in rec["clauses"]]
        if ordinaler != list(range(1, len(ordinaler) + 1)):
            afvist[key] = "ORDINAL_GAP"
            continue
        if any(sha256_text(c["verbatim_text"]) != c["verbatim_sha256"] for c in rec["clauses"]):
            afvist[key] = "CLAUSE_HASH_MISMATCH"
            continue
        if not rec.get("persona_id"):
            afvist[key] = "NO_PERSONA"
            continue
        eligible.append(key)

    aarsager: dict[str, int] = {}
    for grund in afvist.values():
        aarsager[grund] = aarsager.get(grund, 0) + 1
    print(f"PREFLIGHT records={len(records)} klar={len(eligible)} afvist={len(afvist)}")
    for grund, n in sorted(aarsager.items()):
        print(f"  {grund}: {n}")

    if not eligible:
        print("PREFLIGHT_FAILED — ingen records kan sendes.")
        return 1

    # --- stratificeret udvalg -------------------------------------------
    strata: dict[str, list[str]] = {}
    for key in eligible:
        strata.setdefault(strata_of(records[key]), []).append(key)
    for bucket in strata.values():
        bucket.sort()   # deterministisk indenfor stratum

    # Rundgang over strata, så udvalget spreder sig frem for at klumpe.
    valgt: list[str] = []
    navne = sorted(strata)
    i = 0
    while len(valgt) < args.count and any(strata[n] for n in navne):
        bucket = strata[navne[i % len(navne)]]
        if bucket:
            valgt.append(bucket.pop(0))
        i += 1

    print(f"\nSTRATA ({STRATA_VERSION}):")
    for navn in navne:
        antal = len([k for k in eligible if strata_of(records[k]) == navn])
        udtaget = len([k for k in valgt if strata_of(records[k]) == navn])
        print(f"  {navn:28} i puljen={antal:3}  valgt={udtaget}")

    udvalg = {
        "strata_version": STRATA_VERSION,
        "strata_sha256": sha256_text(STRATA_VERSION + "|" + json.dumps(
            {n: len(strata[n]) for n in navne}, sort_keys=True)),
        "ledger_sha256": hashlib.sha256(
            Path(args.ledger).read_bytes()).hexdigest(),
        "records": valgt,
        "bundt_1": valgt[:5],
        "bundt_2": valgt[5:10],
        "record_input_sha256": {k: canonical_record_input(records[k]) for k in valgt},
    }
    out = Path(args.out)
    write_private_replace(out, json.dumps(udvalg, ensure_ascii=False, indent=2))
    print(f"\nUDVALG ({len(valgt)}): bundt 1 = {valgt[:5]}")
    print(f"                bundt 2 = {valgt[5:10]}")
    print(f"skrevet: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
