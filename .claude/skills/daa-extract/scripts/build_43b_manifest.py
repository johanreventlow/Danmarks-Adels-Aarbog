#!/usr/bin/env python3
"""Pre-run-manifestet til 4.3b (plan Task 2 Step 3, spec §10).

Spec §10 kræver projektejerens GO med **manifest-hash og budget** — ikke kun en
ledger-SHA (anden læsers R5). Manifestet bygges derfor FØR modellen kaldes og
binder alt, kørslen er godkendt til: records, deres inputhashes, ledgeren,
profilen, prompten, modellen, outputskemaet og budgettet.

Manifestets hash er GO-grundlaget. Efter kørslen afledes et resultatmanifest uden
at ændre den godkendte inputidentitet.

Indeholder ingen biografitekst — kun nøgler og hashes.
"""
from __future__ import annotations

import argparse, hashlib, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import evidence_extract, evidence_runner

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selection", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--restore-identity", required=True)
    args = ap.parse_args()

    udvalg = json.loads(Path(args.selection).read_text(encoding="utf-8"))
    profil = evidence_extract.load_profile("daa-2018-20-v1")
    prompt = evidence_extract.resolve_prompt(profil["prompt_file"], profil["prompt_sha256"])
    skema = (Path(__file__).resolve().parents[1] / "references" / "evidence-claims-1.0.json")

    # Budget: probens målte overhead pr. kald plus postens egen længde. Tokens,
    # ikke kroner — prisberegning udgik med afvigelse D.
    overhead = 15266
    manifest = {
        "schema_version": "evidence-run-manifest-1.0",
        "status": "pending",
        "dagsvaerk": "4.3b",
        "restore_identity": args.restore_identity,
        "records": udvalg["records"],
        "bundt_1": udvalg["bundt_1"],
        "bundt_2": udvalg["bundt_2"],
        "record_input_sha256": udvalg["record_input_sha256"],
        "strata_version": udvalg["strata_version"],
        "eligibility_ledger_sha256": hashlib.sha256(
            Path(args.ledger).read_bytes()).hexdigest(),
        "profile_id": profil["profile_id"],
        "profile_version": profil["version"],
        "prompt_file": profil["prompt_file"],
        "prompt_sha256": profil["prompt_sha256"],
        "model": profil["model_id"],
        "claims_schema_sha256": evidence_runner.sha256_text(
            skema.read_text(encoding="utf-8")),
        "runner_contract_version": evidence_runner.RUNNER_CONTRACT_VERSION,
        "budget": {
            "enhed": "input-tokens",
            "overhead_pr_kald": overhead,
            "antal_kald": len(udvalg["records"]),
            "forventet_overhead_i_alt": overhead * len(udvalg["records"]),
            "note": "Nyttelasten kommer oveni og afhænger af postlængden. "
                    "Ingen kroneomregning (afvigelse D).",
        },
    }
    krop = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    manifest["manifest_sha256"] = hashlib.sha256(krop.encode("utf-8")).hexdigest()

    out = Path(args.out)
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    out.chmod(0o600)
    print(f"MANIFEST_OK records={len(manifest['records'])}")
    print(f"  manifest_sha256: {manifest['manifest_sha256']}")
    print(f"  ledger_sha256:   {manifest['eligibility_ledger_sha256'][:32]}…")
    print(f"  prompt_sha256:   {manifest['prompt_sha256'][:32]}…")
    print(f"  model:           {manifest['model']}  profil {manifest['profile_version']}")
    print(f"  budget:          ~{manifest['budget']['forventet_overhead_i_alt']:,} input-tokens overhead")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
