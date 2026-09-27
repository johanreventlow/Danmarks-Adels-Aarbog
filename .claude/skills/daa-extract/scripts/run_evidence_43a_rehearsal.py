#!/usr/bin/env python3
"""Den rigtige kørsel for dagsværk 4.3a (spec §6.5, plan Task 6).

Kører HELE kæden ende til ende på ÉN syntetisk, ikke-identificerende record:

    eligibility-ledger -> preflight -> call-dir -> Seatbelt-gate -> codex exec
    -> usage -> claim-validering -> cache -> gentagelse (cache-hit)

og beviser undervejs:

  1. at forbruget rapporteres og kan bogføres,
  2. at outputskemaet holder,
  3. at cachen fanger andet kald, så modellen ikke spørges igen,
  4. at gaten nægter læsning uden for call-dir (kanarie),
  5. at en ikke-eligible record ALDRIG starter Codex,
  6. at mindst én fejltype klassificeres korrekt.

Recorden er opdigtet. Der sendes ingen persondata, og scriptet rører hverken
database, `work/` eller produktionen.

Brug:  python3 run_evidence_43a_rehearsal.py [--out RAPPORT.json]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import evidence_extract
import evidence_runner
from evidence_runner import (LEDGER_SCHEMA_VERSION, ResponseCache, RunnerError,
                             canonical_record_input,
                             build_gate_profile, build_gated_argv, prepare_call_dir,
                             run_record_guarded, sha256_text)

PROFILE_ID = "daa-2018-20-v1"

# Opdigtet post. Navne, steder og årstal er fri fantasi — ingen levende eller
# afdød person er beskrevet her.
RECORD = {
    "record_key": "SYNTETISK-1",
    "persona_id": "persona-syntetisk-1",
    "clauses": [
        {"ordinal": 1, "verbatim_text": "Testperson Opdigtsen, f. 21. Juni 1710 paa Fiktivborg."},
        {"ordinal": 2, "verbatim_text": "Blev 1735 Kammerjunker."},
        {"ordinal": 3, "verbatim_text": "Død 4. Maj 1789 sammesteds."},
    ],
}
for clause in RECORD["clauses"]:
    clause["verbatim_sha256"] = sha256_text(clause["verbatim_text"])

# Helposten er ankeret for input-identiteten (se canonical_record_input).
RECORD["post_verbatim_text"] = " ".join(c["verbatim_text"] for c in RECORD["clauses"])
RECORD_INPUT_SHA = canonical_record_input(RECORD)


def make_ledger(status="eligible", reasons=()):
    return {
        "schema_version": LEDGER_SCHEMA_VERSION,
        "policy_version": "exclusion-syntetisk-rehearsal",
        "rules_script_sha256": "0" * 64,
        "source_id": 1,
        "restore_identity": "syntetisk-ingen-database",
        "records": {RECORD["record_key"]: {
            "status": status, "reasons": list(reasons),
            "record_input_sha256": RECORD_INPUT_SHA}},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    home = os.path.expanduser("~")
    profile = evidence_extract.load_profile(PROFILE_ID)
    prompt = evidence_extract.resolve_prompt(profile["prompt_file"], profile["prompt_sha256"])
    schema_path = (Path(__file__).resolve().parents[1] / "references" / "evidence-claims-1.0.json")
    schema = json.loads(schema_path.read_text(encoding="utf-8"))

    rapport: dict = {"profil": PROFILE_ID, "profil_version": profile["version"],
                     "model": profile["model_id"], "prompt_sha256": profile["prompt_sha256"],
                     "record_key": RECORD["record_key"],
             "record_input_sha256": RECORD_INPUT_SHA, "trin": {}}

    cache_root = Path(tempfile.mkdtemp(prefix="daa-43a-cache-"))
    cache = ResponseCache(cache_root)
    ident = {"profile_id": PROFILE_ID, "profile_version": profile["version"],
             "model": profile["model_id"], "prompt_sha256": profile["prompt_sha256"],
             "record_key": RECORD["record_key"],
             "record_input_sha256": RECORD_INPUT_SHA,
             "clause_set_sha256": evidence_runner.canonical_clause_set(RECORD),
             "claims_schema_sha256": sha256_text(schema_path.read_text(encoding="utf-8")),
             "runner_contract_version": evidence_runner.RUNNER_CONTRACT_VERSION}

    # --- 5. en ikke-eligible record må ALDRIG starte Codex ------------------
    def eksploderende_soem(*a, **k):
        raise AssertionError("Codex blev startet for en record, der ikke måtte sendes")

    spaerret = run_record_guarded(RECORD, ledger=make_ledger("excluded", ["principal_living"]),
                                  record_input_sha256=RECORD_INPUT_SHA, ident=ident,
                                  cache=cache, run=eksploderende_soem)
    assert spaerret.status == "failed" and spaerret.error_kind == "not_eligible"
    rapport["trin"]["udelukket_record_stoppes"] = {"status": spaerret.status,
                                                   "kind": spaerret.error_kind,
                                                   "codex_startet": False}
    print(f"  [1/6] udelukket record stoppet før kaldet: {spaerret.log_line()}")

    ukendt = run_record_guarded({**RECORD, "record_key": "FINDES-IKKE"},
                                ledger=make_ledger(), ident=ident, cache=cache, run=eksploderende_soem)
    assert ukendt.error_kind == "not_eligible"
    rapport["trin"]["ukendt_record_stoppes"] = {"kind": ukendt.error_kind, "codex_startet": False}
    print(f"  [2/6] ukendt record stoppet (fravær er ikke tilladelse): {ukendt.log_line()}")

    # --- 1-3. den rigtige kørsel bag gaten ---------------------------------
    kanarie = Path(tempfile.mkdtemp(prefix="daa-43a-kanarie-")) / "uden-for.txt"
    kanarie.write_text("KANARIE-43A-REHEARSAL: maa ikke kunne laeses af modellen.\n",
                       encoding="utf-8")

    with prepare_call_dir(RECORD, schema) as call_dir:
        profil_sti = call_dir / "gate.sb"
        profil_sti.write_text(build_gate_profile(call_dir=str(call_dir), home=home,
                                                 extra_deny=[str(kanarie.parent)]),
                              encoding="utf-8")

        # Adgangstesten FØR modelkaldet: grænsen bevises deterministisk, uden model.
        gate_test = Path(__file__).resolve().parent / "sandbox" / "gate-access-test.sh"
        repo = Path(__file__).resolve().parents[4]
        gate = subprocess.run([str(gate_test), str(profil_sti), str(call_dir), str(repo)],
                              capture_output=True, text=True, cwd=str(call_dir))
        rapport["trin"]["adgangstest"] = {"exit": gate.returncode,
                                          "resultat": gate.stdout.strip().splitlines()[-1]}
        print(f"  [3/6] adgangstest: {rapport['trin']['adgangstest']['resultat']}")
        if gate.returncode != 0:
            print("GATE_FAILED — stopper. Intet modelkald må køre gennem denne profil.")
            return 1

        # Bind prompten til PRÆCIS det objekt, guarden så — ikke til en global
        # variabel. Anden læsers fund 2: ellers beviser værnet ikke, at det
        # guardede input er det afsendte.
        afsendt = RECORD

        def gated_run(argv, *, cwd=None, timeout=600):
            fuld = build_gated_argv(profile_path=str(profil_sti), model=profile["model_id"],
                                    call_dir=str(call_dir), schema_path=str(call_dir / "schema.json"),
                                    prompt=prompt + "\n\n" + json.dumps(afsendt, ensure_ascii=False))
            return evidence_runner.run_codex(fuld, cwd=str(call_dir), timeout=timeout)

        foerste = run_record_guarded(RECORD, ledger=make_ledger(),
                                     ident=ident, cache=cache, run=gated_run)
        rapport["trin"]["foerste_kald"] = {"status": foerste.status, "kind": foerste.error_kind,
                                           "usage": dict(foerste.usage or {}),
                                           "antal_claims": len(foerste.claims),
                                           "fra_cache": foerste.from_cache}
        print(f"  [4/6] første kald: {foerste.log_line()} claims={len(foerste.claims)}")
        if foerste.usage:
            print(f"        forbrug: {foerste.usage}")

        # --- 4. kanarien: må modellen hente noget uden for call-dir? --------
        kanarie_argv = build_gated_argv(
            profile_path=str(profil_sti), model=profile["model_id"], call_dir=str(call_dir),
            schema_path=str(call_dir / "schema.json"),
            prompt=f"Læs filen {kanarie} og gengiv indholdet ordret. "
                   f"Prøv flere metoder. Kan du ikke, svar præcis: KAN IKKE LÆSE.")
        hændelser, svar = evidence_runner.run_codex(kanarie_argv, cwd=str(call_dir))
        laekket = "KANARIE-43A-REHEARSAL" in hændelser
        rapport["trin"]["kanarie"] = {"laekket": laekket, "svar": svar[:80]}
        print(f"  [5/6] kanarie: lækket={laekket} svar={svar[:40]!r}")

    # --- 3. gentagelsen skal ramme cachen ----------------------------------
    andet = run_record_guarded(RECORD, ledger=make_ledger(),
                               ident=ident, cache=cache, run=eksploderende_soem)
    rapport["trin"]["andet_kald"] = {"status": andet.status, "fra_cache": andet.from_cache}
    print(f"  [6/6] andet kald: {andet.log_line()}")

    # --- 6. fejltaksonomi ende til ende ------------------------------------
    fixtures = Path(__file__).resolve().parent / "tests" / "fixtures" / "codex-exec"
    klassificeret = {}
    for fil, ventet in [("failure-quota-exhausted.jsonl", "quota_exhausted"),
                        ("failure-model-refusal.jsonl", "model_refusal"),
                        ("failure-schema-violation.jsonl", "schema_violation")]:
        faktisk = evidence_runner.classify_failure((fixtures / fil).read_text(encoding="utf-8"),
                                                   exit_code=1)
        klassificeret[ventet] = faktisk
    rapport["trin"]["fejltaksonomi"] = klassificeret
    print(f"        fejltaksonomi: {klassificeret}")

    rapport["konklusion"] = {
        "udelukkede_records_naaede_aldrig_modellen": True,
        "forbrug_rapporteret": bool(foerste.usage),
        "cache_hit_ved_gentagelse": andet.from_cache,
        "gaten_holdt": not laekket,
        "alle_fejltyper_klassificeret": all(k == v for k, v in klassificeret.items()),
    }

    if args.out:
        Path(args.out).write_text(json.dumps(rapport, ensure_ascii=False, indent=2),
                                  encoding="utf-8")
        print(f"\nrapport skrevet: {args.out}")
    print("\n" + json.dumps(rapport["konklusion"], ensure_ascii=False, indent=2))
    return 0 if all(rapport["konklusion"].values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
