#!/usr/bin/env python3
"""Kørslen for dagsværk 4.3b: rigtige records gennem modellen (plan Task 3).

Genbruger 4.3a's runner, gate, ledger og cache uændret. Det nye er, at inputtet
er virkelige biografier i stedet for en opdigtet post.

Kræver et GODKENDT pre-run-manifest: kørslen nægter at starte, hvis manifestets
hash ikke er den, projektejeren gav GO til, eller hvis nogen record uden for
manifestet skulle nå at blive sendt.

PII: scriptet printer kun nøgler, tal og prædikater — aldrig biografitekst.
Bedømmelsesarket (som SKAL rumme tekst) skrives 0600 i en privat mappe.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import evidence_extract
import evidence_runner
from build_43b_manifest import bundles_of, check_contract, runner_code_sha256
from evidence_runner import (ResponseCache, build_gate_profile, build_gated_argv,
                             canonical_record_input, load_ledger, prepare_call_dir,
                             run_record_guarded, sha256_text)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--approved-sha256", required=True,
                    help="manifest-hashen fra projektejerens GO")
    ap.add_argument("--runner-input", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--bundle", required=True)
    ap.add_argument("--cache-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--judgement-sheet", required=True)
    args = ap.parse_args()

    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    if manifest.get("manifest_sha256") != args.approved_sha256:
        print("MANIFEST_NOT_APPROVED — hashen er ikke den, der blev givet GO til.")
        return 1

    runner_input = json.loads(Path(args.runner_input).read_text(encoding="utf-8"))["records"]
    ledger = load_ledger(json.loads(Path(args.ledger).read_text(encoding="utf-8")))
    if hashlib.sha256(Path(args.ledger).read_bytes()).hexdigest() != manifest["eligibility_ledger_sha256"]:
        print("LEDGER_DRIFT — ledgeren er ikke den, manifestet blev godkendt med.")
        return 1

    profil = evidence_extract.load_profile(manifest["profile_id"])
    if profil["version"] != manifest["profile_version"]:
        print("PROFILE_DRIFT — profilversionen er ændret siden GO.")
        return 1
    prompt = evidence_extract.resolve_prompt(profil["prompt_file"], profil["prompt_sha256"])
    if profil["prompt_sha256"] != manifest["prompt_sha256"]:
        print("PROMPT_DRIFT — prompten er ændret siden GO. Beviset nulstilles.")
        return 1

    skema_sti = Path(__file__).resolve().parents[1] / "references" / "evidence-claims-1.0.json"
    skema_tekst = skema_sti.read_text(encoding="utf-8")
    # Den godkendte kontrakt genvalideres FØR første kald (4.5-review, fund 3).
    fejl = check_contract(manifest, schema_text=skema_tekst,
                          runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                          code_sha256=runner_code_sha256())
    if fejl:
        print(f"{fejl} — kørselsmiljøet er ikke det, der blev givet GO til. Intet sendes.")
        return 1
    skema = json.loads(skema_tekst)
    cache = ResponseCache(args.cache_dir)
    home = os.path.expanduser("~")
    repo = Path(__file__).resolve().parents[4]

    bundter = bundles_of(manifest)
    if args.bundle not in bundter:
        print(f"BUNDLE_UNKNOWN {args.bundle} — manifestet har {sorted(bundter)}")
        return 1
    keys = bundter[args.bundle]
    print(f"== {args.bundle}: {len(keys)} records ==\n")

    resultater, ark = [], []
    for key in keys:
        rec = runner_input[key]
        ident = {
            "profile_id": manifest["profile_id"], "profile_version": manifest["profile_version"],
            "model": manifest["model"], "prompt_sha256": manifest["prompt_sha256"],
            # record_key er MED i cache-identiteten: 591 records har kun 588 unikke
            # helposthashes, så tre par ville ellers dele cachepost (#147, fund 2
            # ved reviewet af plan 4.4).
            "record_key": key,
            "record_input_sha256": canonical_record_input(rec),
            # Klausulsættet (kontrakt 1.2, review 35 P4): en omsegmenteret post må
            # ikke ramme et svar, der citerer den gamle opdeling.
            "clause_set_sha256": evidence_runner.canonical_clause_set(rec),
            "claims_schema_sha256": manifest["claims_schema_sha256"],
            "runner_contract_version": manifest["runner_contract_version"],
        }
        try:
            # Før call-dir: klausulerne skal ligge i den godkendte helpost (4.5-kodereview, fund 1).
            evidence_runner.check_clauses_within_post(rec)
        except evidence_runner.EligibilityError as exc:
            print(f"{exc} — stopper. Intet mere sendes.")
            return 1
        with prepare_call_dir(rec, skema) as call_dir:
            profil_sti = call_dir / "gate.sb"
            profil_sti.write_text(build_gate_profile(call_dir=str(call_dir), home=home),
                                  encoding="utf-8")
            # Adgangstesten umiddelbart før kaldet — ikke tidligere på dagen.
            import subprocess
            gate = subprocess.run(
                [str(Path(__file__).resolve().parent / "sandbox" / "gate-access-test.sh"),
                 str(profil_sti), str(call_dir), str(repo)],
                capture_output=True, text=True, cwd=str(call_dir))
            if gate.returncode != 0:
                print(f"GATE_FAILED før {key} — stopper. Intet mere sendes.")
                return 1

            afsendt = rec   # prompten bindes til PRÆCIS det objekt, guarden ser

            def gated_run(argv, *, cwd=None, timeout=900):
                fuld = build_gated_argv(
                    profile_path=str(profil_sti), model=manifest["model"],
                    call_dir=str(call_dir), schema_path=str(call_dir / "schema.json"),
                    prompt=prompt + "\n\n## Posten\n\n" + json.dumps(
                        {"record_key": afsendt["record_key"],
                         "persona_id": afsendt["persona_id"],
                         "clauses": [{"ordinal": c["ordinal"], "verbatim_text": c["verbatim_text"]}
                                     for c in afsendt["clauses"]]},
                        ensure_ascii=False, indent=2))
                return evidence_runner.run_codex(fuld, cwd=str(call_dir), timeout=timeout)

            udfald = run_record_guarded(rec, ledger=ledger, ident=ident,
                                        cache=cache, run=gated_run)

        praedikater = sorted({c["predicate"] for c in udfald.claims})
        resultater.append({
            "record_key": key, "status": udfald.status, "error_kind": udfald.error_kind,
            "antal_klausuler": len(rec["clauses"]), "antal_claims": len(udfald.claims),
            "praedikater": praedikater, "usage": dict(udfald.usage or {}),
            "afviste": [r["fejl"] for r in udfald.rejected],
            "fra_cache": udfald.from_cache,
        })
        print(f"  {key:10} {udfald.status:7} klausuler={len(rec['clauses']):2} "
              f"claims={len(udfald.claims):2}  {','.join(praedikater[:4])}")
        if udfald.usage:
            print(f"             forbrug: {udfald.usage['input_tokens']} ind / "
                  f"{udfald.usage['output_tokens']} ud / "
                  f"{udfald.usage['reasoning_output_tokens']} reasoning")

        # Bedømmelsesarket er det ENESTE sted, teksten står. 0600, uden for repoet.
        ark.append({
            "record_key": key,
            "klausuler": [{"ordinal": c["ordinal"], "tekst": c["verbatim_text"]}
                          for c in rec["clauses"]],
            "claims": [dict(c) for c in udfald.claims],
            "dom": {"praecision": None, "klausulbinding": None, "ordrethed": None},
            "forventede_udtraek": "UDFYLDES AF MENNESKET: hvilke udsagn i teksten burde "
                                  "have givet et claim? (grundlag for dækningsmålet)",
        })

    # `delvis` TÆLLER MED: recorden har en valideret post, blot ikke alle claims.
    # Tabet står i regnskabet via antallet af afviste. Samme regel som batch_status —
    # den blev rettet dér, men ikke her, så bundt 2 meldte falsk PENDING.
    green = sum(1 for r in resultater if r["status"] in ("green", "delvis"))
    tokens = sum(r["usage"].get("input_tokens", 0) for r in resultater)
    delvise = sum(1 for r in resultater if r["status"] == "delvis")
    print(f"\n== {green}/{len(keys)} dækket ({delvise} delvis) · {sum(r['antal_claims'] for r in resultater)} claims "
          f"· {tokens:,} input-tokens ==")
    if green != len(keys):
        print("BATCH_PENDING — ikke alle records har en valideret post.")

    Path(args.out).write_text(json.dumps(
        {"bundle": args.bundle, "manifest_sha256": manifest["manifest_sha256"],
         "resultater": resultater}, ensure_ascii=False, indent=2), encoding="utf-8")
    Path(args.out).chmod(0o600)
    sheet = Path(args.judgement_sheet)
    sheet.write_text(json.dumps(ark, ensure_ascii=False, indent=2), encoding="utf-8")
    sheet.chmod(0o600)
    print(f"\nresultat:          {args.out}")
    print(f"bedømmelsesark:    {sheet}  (indeholder tekst — 0600, uden for repoet)")
    print(f"ark-sha256:        {sha256_text(sheet.read_text(encoding='utf-8'))}")
    return 0 if green == len(keys) else 1


if __name__ == "__main__":
    raise SystemExit(main())
