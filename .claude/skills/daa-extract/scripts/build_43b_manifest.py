#!/usr/bin/env python3
"""Pre-run-manifestet til 4.3b og 4.5 (spec §10).

Spec §10 kræver projektejerens GO med **manifest-hash og budget** — ikke kun en
ledger-SHA (anden læsers R5). Manifestet bygges derfor FØR modellen kaldes og
binder alt, kørslen er godkendt til: records, deres inputhashes, ledgeren,
profilen, prompten, modellen, outputskemaet, runner-kontrakten, runner-koden og
budgettet. `check_contract` genvaliderer det ved kørslen (4.5-review, fund 3).

Manifestets hash er GO-grundlaget. Indeholder ingen biografitekst.
"""
from __future__ import annotations

import argparse, hashlib, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import evidence_extract, evidence_runner

SCRIPTS = Path(__file__).resolve().parent
SKEMA = SCRIPTS.parent / "references" / "evidence-claims-1.0.json"
#: Filerne, hvis bytes afgør hvad der sendes og hvordan svaret valideres.
RUNNER_CODE_FILES = ("evidence_extract.py", "evidence_runner.py", "run_evidence_43b.py")
OVERHEAD = 15266


def runner_code_sha256(scripts_dir: Path = SCRIPTS) -> str:
    h = hashlib.sha256()
    for navn in RUNNER_CODE_FILES:
        h.update(navn.encode("utf-8") + b"\0" + (scripts_dir / navn).read_bytes() + b"\0")
    return h.hexdigest()


def manifest_sha256(manifest: dict) -> str:
    krop = {k: v for k, v in manifest.items() if k != "manifest_sha256"}
    return hashlib.sha256(json.dumps(krop, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def bundles_of(manifest: dict) -> dict[str, list[str]]:
    if "bundter" in manifest:
        return manifest["bundter"]
    return {"bundt_1": manifest["bundt_1"], "bundt_2": manifest["bundt_2"]}


def build_manifest(udvalg: dict, *, dagsvaerk: str, restore_identity: str,
                   ledger_sha256: str, profil: dict, claims_schema_sha256: str,
                   code_sha256: str | None = None) -> dict:
    manifest = {
        "schema_version": "evidence-run-manifest-1.0",
        "status": "pending",
        "dagsvaerk": dagsvaerk,
        "restore_identity": restore_identity,
        "records": udvalg["records"],
        "record_input_sha256": udvalg["record_input_sha256"],
        "strata_version": udvalg["strata_version"],
        "eligibility_ledger_sha256": ledger_sha256,
        "profile_id": profil["profile_id"],
        "profile_version": profil["version"],
        "prompt_file": profil["prompt_file"],
        "prompt_sha256": profil["prompt_sha256"],
        "model": profil["model_id"],
        "claims_schema_sha256": claims_schema_sha256,
        "runner_contract_version": evidence_runner.RUNNER_CONTRACT_VERSION,
        "budget": {
            "enhed": "input-tokens",
            "overhead_pr_kald": OVERHEAD,
            "antal_kald": len(udvalg["records"]),
            "forventet_overhead_i_alt": OVERHEAD * len(udvalg["records"]),
            "note": "Nyttelasten kommer oveni og afhænger af postlængden. "
                    "Ingen kroneomregning (afvigelse D).",
        },
    }
    if "bundter" in udvalg:
        manifest["bundter"] = udvalg["bundter"]
        manifest["strata_sha256"] = udvalg["strata_sha256"]
    else:
        manifest["bundt_1"] = udvalg["bundt_1"]
        manifest["bundt_2"] = udvalg["bundt_2"]
    if code_sha256 is not None:
        manifest["runner_code_sha256"] = code_sha256
    manifest["manifest_sha256"] = manifest_sha256(manifest)
    return manifest


def check_contract(manifest: dict, *, schema_text: str, runner_contract_version: str,
                   code_sha256: str) -> str | None:
    """None hvis kørselsmiljøet er det godkendte; ellers en navngivet STOP-kode."""
    if manifest_sha256(manifest) != manifest.get("manifest_sha256"):
        return "MANIFEST_TAMPERED"
    if evidence_runner.sha256_text(schema_text) != manifest["claims_schema_sha256"]:
        return "SCHEMA_DRIFT"
    if runner_contract_version != manifest["runner_contract_version"]:
        return "RUNNER_CONTRACT_DRIFT"
    if "runner_code_sha256" in manifest and code_sha256 != manifest["runner_code_sha256"]:
        return "RUNNER_CODE_DRIFT"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selection", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--restore-identity", required=True)
    ap.add_argument("--dagsvaerk", default="4.3b")
    args = ap.parse_args()

    udvalg = json.loads(Path(args.selection).read_text(encoding="utf-8"))
    profil = evidence_extract.load_profile("daa-2018-20-v1")
    evidence_extract.resolve_prompt(profil["prompt_file"], profil["prompt_sha256"])
    manifest = build_manifest(
        udvalg, dagsvaerk=args.dagsvaerk, restore_identity=args.restore_identity,
        ledger_sha256=hashlib.sha256(Path(args.ledger).read_bytes()).hexdigest(),
        profil=profil,
        claims_schema_sha256=evidence_runner.sha256_text(SKEMA.read_text(encoding="utf-8")),
        code_sha256=None if args.dagsvaerk == "4.3b" else runner_code_sha256())

    out = Path(args.out)
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    out.chmod(0o600)
    print(f"MANIFEST_OK records={len(manifest['records'])} bundter={sorted(bundles_of(manifest))}")
    print(f"  manifest_sha256: {manifest['manifest_sha256']}")
    print(f"  ledger_sha256:   {manifest['eligibility_ledger_sha256'][:32]}…")
    print(f"  prompt_sha256:   {manifest['prompt_sha256'][:32]}…")
    print(f"  model:           {manifest['model']}  profil {manifest['profile_version']}")
    print(f"  budget:          ~{manifest['budget']['forventet_overhead_i_alt']:,} input-tokens overhead")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
