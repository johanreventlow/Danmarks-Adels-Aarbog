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
PILOT_STRATA_VERSION = "eligible-pilot-v1"
BUNDT = 25


class SelectionLedgerMismatch(Exception):
    pass


def eligible_keys(records: dict, ledger: dict, only: list[str] | None = None) -> list[str]:
    validated = load_ledger(ledger)
    wanted = sorted(k for k, r in validated["records"].items() if r["status"] == "eligible")
    if only is not None:
        # Afgrænsning (6c-3): kun poster ledgeret kalder `eligible` må vælges; alt andet er en fejl, ikke et spring.
        ikke = sorted(set(only) - set(wanted))
        if ikke:
            raise SelectionLedgerMismatch("SELECTION_RECORD_NOT_ELIGIBLE " + " ".join(ikke))
        wanted = sorted(set(only))
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


def _median(values: list[int]) -> float:
    ordered = sorted(values)
    mid = len(ordered) // 2
    return float(ordered[mid]) if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2


def stratum_of(rec: dict, klausul_median: float, laengde_median: float) -> str:
    return (("klausuler_hoej" if len(rec["clauses"]) > klausul_median else "klausuler_lav") + "|"
            + ("laengde_hoej" if len(rec["post_verbatim_text"]) > laengde_median else "laengde_lav"))


def pilot_definition_sha256(size: int, limit: int, seed: str) -> str:
    definition = {"strata_version": PILOT_STRATA_VERSION, "bundle_size": size, "limit": limit, "seed": seed,
                  "order": "python-str-codepoint", "filter": "ledger.status == eligible",
                  "strata": "(antal klausuler <=/> median) x (posttekstlaengde <=/> median), median over eligible",
                  "pick": "sha256(seed|record_key) stigende inden for stratum; rundgang over strata i navneorden"}
    return hashlib.sha256(json.dumps(definition, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def pilot_pick(records: dict, keys: list[str], limit: int, seed: str) -> tuple[list[str], dict]:
    if limit <= 0 or limit > len(keys):
        raise SelectionLedgerMismatch(f"SELECTION_LIMIT_INVALID limit={limit} eligible={len(keys)}")
    km = _median([len(records[k]["clauses"]) for k in keys])
    lm = _median([len(records[k]["post_verbatim_text"]) for k in keys])
    strata: dict[str, list[str]] = {}
    for k in keys:
        strata.setdefault(stratum_of(records[k], km, lm), []).append(k)
    eligible_pr = {n: len(v) for n, v in sorted(strata.items())}
    for bucket in strata.values():
        bucket.sort(key=lambda k: (hashlib.sha256(f"{seed}|{k}".encode("utf-8")).hexdigest(), k))
    navne = sorted(strata)
    valgt: list[str] = []
    i = 0
    while len(valgt) < limit:
        bucket = strata[navne[i % len(navne)]]
        if bucket:
            valgt.append(bucket.pop(0))
        i += 1
    return sorted(valgt), {"klausul_median": km, "laengde_median": lm, "eligible_pr_stratum": eligible_pr}


def _filter_info(only: list[str] | None) -> dict:
    if only is None:
        return {}
    return {"records_filter_sha256": hashlib.sha256(json.dumps(sorted(set(only)), separators=(",", ":"))
                                                    .encode("utf-8")).hexdigest()}


def load_records_filter(path: Path) -> list[str]:
    """`--records`: JSON-liste af record-nøgler, eller et objekt med `records` (fx et tidligere udvalg)."""
    data = json.loads(path.read_text(encoding="utf-8"))
    keys = data.get("records") if isinstance(data, dict) else data
    if not isinstance(keys, list) or not keys or not all(isinstance(k, str) for k in keys):
        raise SelectionLedgerMismatch("SELECTION_RECORDS_FILE_INVALID")
    return keys


def build_selection(records: dict, ledger: dict, ledger_sha256: str, size: int,
                    limit: int | None = None, seed: str = "0", only: list[str] | None = None) -> dict:
    keys = eligible_keys(records, ledger, only)
    if limit is not None:
        keys, info = pilot_pick(records, keys, limit, seed)
        km, lm = info["klausul_median"], info["laengde_median"]
        valgt_pr: dict[str, int] = {}
        for k in keys:
            n = stratum_of(records[k], km, lm)
            valgt_pr[n] = valgt_pr.get(n, 0) + 1
        return {
            "strata_version": PILOT_STRATA_VERSION,
            "strata_sha256": pilot_definition_sha256(size, limit, seed),
            "ledger_sha256": ledger_sha256,
            "seed": seed,
            "limit": limit,
            **info,
            "valgt_pr_stratum": dict(sorted(valgt_pr.items())),
            "records": keys,
            "bundter": bundle(keys, size),
            "record_input_sha256": {k: canonical_record_input(records[k]) for k in keys},
            "uden_persona": [k for k in keys if not records[k]["persona_id"]],
            "ikke_i_ledger": sorted(set(records) - set(ledger["records"])),
            "note": "pilotudvalg af eligible poster, stratificeret og seedet (trin 6c-1)",
            **_filter_info(only),
        }
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
        **_filter_info(only),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runner-input", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--bundle-size", type=int, default=BUNDT)
    ap.add_argument("--limit", type=int, default=None)
    # Seedet er en streng (planen bruger `6c1-pilot-v1`) og giver kun mening med --limit (fund F5).
    ap.add_argument("--seed", type=str, default=None)
    ap.add_argument("--records", default=None,
                    help="JSON-liste af record-nøgler; kun disse tages med (kun eligible, ellers SELECTION_RECORD_NOT_ELIGIBLE)")
    args = ap.parse_args()
    if args.seed is not None and args.limit is None:
        print("SELECTION_SEED_WITHOUT_LIMIT — --seed vælger et pilotudvalg og kræver --limit.")
        return 1

    records = json.loads(Path(args.runner_input).read_text(encoding="utf-8"))["records"]
    ledger_bytes = Path(args.ledger).read_bytes()
    try:
        only = load_records_filter(Path(args.records)) if args.records else None
        udvalg = build_selection(records, json.loads(ledger_bytes),
                                 hashlib.sha256(ledger_bytes).hexdigest(), args.bundle_size,
                                 args.limit, "0" if args.seed is None else args.seed, only)
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
