#!/usr/bin/env python3
"""Udvalget »alle `eligible` poster i et ledger« til en fuld kørsel af fortolkningskæden.

Beslutning: `docs/decisions.md` 2026-10-01. Udgaveneutralt: ledgeret afgør, hvad der må
sendes; her afgøres kun rækkefølgen og bundtdelingen. Fail-closed: en post, ledgeret kalder
`eligible`, men som runner-inputtet ikke kan levere med den godkendte hash, er en fejl og
falder ikke stille ud (`build_45_selection` springer den over — det er rigtigt for et
stikprøveudvalg, men ikke for »alle«). Samme gælder en post, hvis klausuler runneren ville
afvise midt i et bundt (ordinalhul, forkert klausulhash, klausul uden for helposten), jf.
`build_43b_selection`'s forhåndstjek, eller en post uden klausuler.

En post uden persona er IKKE en fejl: runneren afviser kun dens `person.*`-claims (I-133 i
genbindingen 28/9 gav `delvis` med andre claims). Den tælles i `uden_persona`.

Printer kun nøgler, tal og hashes — aldrig tekst.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from evidence_runner import (EligibilityError, RunnerError, canonical_clause_set,
                             canonical_record_input, check_clauses_within_post,
                             check_eligibility, load_ledger)

STRATA_VERSION = "eligible-all-v1"
BUNDT = 25


class SelectionLedgerMismatch(Exception):
    pass


def eligible_keys(records: dict, ledger: dict) -> list[str]:
    validated = load_ledger(ledger)
    wanted = sorted(k for k, r in validated["records"].items() if r["status"] == "eligible")
    if not wanted:
        raise SelectionLedgerMismatch("SELECTION_LEDGER_MISMATCH NO_ELIGIBLE")
    fejl = []
    for key in wanted:
        if key not in records:
            fejl.append(f"{key}:RUNNER_INPUT_MISSING")
            continue
        rec = records[key]
        if rec.get("record_key") != key:
            # Runneren slår op på feltet, ikke på dict-nøglen.
            fejl.append(f"{key}:RECORD_KEY_MISMATCH")
            continue
        if not isinstance(rec.get("persona_id", None), str):
            # Tom streng er eksportens »ingen persona«; et manglende felt vælter bundtet.
            fejl.append(f"{key}:PERSONA_FIELD_MISSING")
            continue
        try:
            check_eligibility(validated, key, canonical_record_input(rec))
            # Strukturen valideres her (`_clause_index`), før ordinalerne læses.
            canonical_clause_set(rec)
            check_clauses_within_post(rec)
        except RunnerError as exc:
            fejl.append(f"{key}:{str(exc).split()[0]}")
            continue
        ordinaler = [c["ordinal"] for c in rec["clauses"]]
        if not ordinaler:
            # Et kald uden klausuler ville blive `green` med 0 claims og tælle som dækket.
            fejl.append(f"{key}:NO_CLAUSES")
        elif ordinaler != list(range(1, len(ordinaler) + 1)):
            fejl.append(f"{key}:ORDINAL_GAP")
    if fejl:
        raise SelectionLedgerMismatch("SELECTION_LEDGER_MISMATCH " + " ".join(fejl))
    return wanted


def bundle(keys: list[str], size: int) -> dict[str, list[str]]:
    if size <= 0:
        raise ValueError("bundle size must be positive")
    antal = (len(keys) + size - 1) // size
    bredde = max(2, len(str(antal)))
    return {f"bundt_{n + 1:0{bredde}d}": keys[i:i + size]
            for n, i in enumerate(range(0, len(keys), size))}


def definition_sha256(size: int) -> str:
    definition = {"strata_version": STRATA_VERSION, "bundle_size": size,
                  "order": "python-str-codepoint", "filter": "ledger.status == eligible"}
    return hashlib.sha256(json.dumps(definition, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def build_selection(records: dict, ledger: dict, ledger_sha256: str, size: int) -> dict:
    keys = eligible_keys(records, ledger)
    return {
        "strata_version": STRATA_VERSION,
        "strata_sha256": definition_sha256(size),
        "ledger_sha256": ledger_sha256,
        "records": keys,
        "bundter": bundle(keys, size),
        "record_input_sha256": {k: canonical_record_input(records[k]) for k in keys},
        "uden_persona": [k for k in keys if not records[k]["persona_id"]],
        "ikke_i_ledger": sorted(set(records) - set(ledger["records"])),
        "note": "alle eligible poster i ledgeret (decisions 2026-10-01)",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runner-input", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--bundle-size", type=int, default=BUNDT)
    args = ap.parse_args()

    records = json.loads(Path(args.runner_input).read_text(encoding="utf-8"))["records"]
    ledger_bytes = Path(args.ledger).read_bytes()
    try:
        udvalg = build_selection(records, json.loads(ledger_bytes),
                                 hashlib.sha256(ledger_bytes).hexdigest(), args.bundle_size)
    except (SelectionLedgerMismatch, EligibilityError) as exc:
        print(str(exc))
        return 1
    out = Path(args.out)
    out.write_text(json.dumps(udvalg, ensure_ascii=False, indent=2), encoding="utf-8")
    out.chmod(0o600)
    print(f"UDVALG_OK records={len(udvalg['records'])} bundter={len(udvalg['bundter'])} "
          f"uden_persona={len(udvalg['uden_persona'])} ikke_i_ledger={len(udvalg['ikke_i_ledger'])}")
    print(f"  strata_sha256 {udvalg['strata_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
