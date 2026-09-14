#!/usr/bin/env python3
"""Manifest-builder til dagsværk 4.4 (plan Task 4): fra 4.3b's cache til writer-payload.

**Her klassificeres claims — ikke i writeren.** Ét writer-element er én record, så
en exception for ét claim ruller hele recorden tilbage. Det er den fejl,
projektejeren afgjorde imod efter 4.3b's bundt 1, hvor ét ugyldigt claim fældede
seks korrekte. Alt, der kan afgøres før writeren, afgøres her.

Femtals-regnskabet er derfor kernen:

    rå claims → kontrakt-afviste → H1-afviste → dubletter → ingestible

Alle fem tal ender i manifestet. Uden dem kan »antal = manifestets« ikke kontrolleres
mod noget.

Payloaden bærer claim-værdier, som kan være ordrette kildeudsnit. Det er autoriseret
privat evidens (spec §7.1 kræver `value`), men hel klausul- eller helposttekst må
ikke med, og filen skrives 0600.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import evidence_extract
import evidence_runner
from evidence_runner import (canonical_record_input, partition_record_claims,
                             sha256_text)

#: 4.3b's cachefiler blev skrevet FØR `record_key` kom ind i cache-nøglen (PR #188).
#: De findes derfor ikke under den nuværende `ResponseCache.key()`. Builderen
#: re-udleder med den nøgleudledning, der GJALDT VED KØRSLEN — eksplicit, så en
#: senere ændring af den aktuelle funktion ikke stiltiende gør de gamle filer
#: uadresserbare.
LEGACY_CACHE_KEY_FIELDS = ("profile_id", "profile_version", "model", "prompt_sha256",
                           "record_input_sha256", "claims_schema_sha256",
                           "runner_contract_version")
LEGACY_RUNNER_CONTRACT_VERSION = "evidence-runner-1.0"


def legacy_cache_key(ident: dict) -> str:
    material = "\x1f".join(str(ident[f]) for f in LEGACY_CACHE_KEY_FIELDS)
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def normaliser(tekst: str) -> str:
    """NFKC, casefold, whitespace-kollaps, strip af afsluttende tegnsætning."""
    t = unicodedata.normalize("NFKC", tekst).casefold()
    t = re.sub(r"\s+", " ", t).strip()
    return t.strip(" .,;:!?-–—")


def uden_modpart(value, denylist: dict) -> bool:
    """H1: identificerer claimets værdi nogen?

    ANCHORED på hele strengen. »4 sønner, som døde små« slipper altså igennem —
    det er en tidsbesparelse, ikke en korrekthedsgate, og 4.5 er menneskegatet.
    Reglen må ikke omtales som en generel »identificerbar person«-detektor.
    """
    raw = value.get("raw") if isinstance(value, dict) else value
    if not isinstance(raw, str):
        return False
    n = normaliser(raw)
    if not n:
        return True
    if n in {normaliser(x) for x in denylist["unknown_person"]}:
        return True
    q = denylist["quantity_only"]
    if n in {normaliser(x) for x in q["bare_kinship"]}:
        return True
    dele = n.split()
    if len(dele) == 2 and dele[0] in {normaliser(x) for x in q["numbers"]} \
            and dele[1] in {normaliser(x) for x in q["kinship"]}:
        return True
    return False


def persona_rolle(predicate: str, rolle_map: dict) -> str | None:
    """`principal` eller `other` efter profilens EKSPLICITTE kort — ikke efter præfiks.

    Spec §7.2 dækker kun `person.*` og mention/relation, men 4.3b's data rummer otte
    `event.*`-claims, som handler om hovedpersonen uden at have `person.`-præfiks.
    En naiv »ikke person.* → other« ville give dem persona NULL og stemple deres
    klausuler `afventer_identitet`.

    Returnerer None for et prædikat, kortet ikke kender — så afviser kalderen det
    frem for at gætte.
    """
    for præfiks in rolle_map["principal"]:
        if predicate.startswith(præfiks):
            return "principal"
    for præfiks in rolle_map["other"]:
        if predicate.startswith(præfiks):
            return "other"
    return None


def interpretation_key_input(source_id: int, record_key: str, predicate: str,
                             ordinals, value) -> str:
    """Kanonisk nøgleinput — versioneret JSON, ikke en separatorstreng.

    En separatorbaseret form kolliderer, hvis et felt indeholder skilletegnet.
    Ordinaler sorteres og dedupliceres, så samme claim ikke får to nøgler afhængigt
    af rækkefølgen i modellens svar.

    Spec §7.1's fem felter — `interpretation_kind` og `persona_role` indgår
    bevidst IKKE: den første er funktionelt bestemt af prædikatet, og den anden
    ville kun være nødvendig, hvis samme claim legitimt kunne optræde i begge
    roller. At tilføje dem ville være en spec-ændring.
    """
    return json.dumps({
        "v": "interpretation-key-1",
        "source_id": source_id,
        "record_key": record_key,
        "predicate": predicate,
        "ordinals": sorted(set(int(o) for o in ordinals)),
        "value_sha256": sha256_text(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                               separators=(",", ":"))),
    }, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runner-manifest", required=True)
    ap.add_argument("--runner-input", required=True)
    ap.add_argument("--cache-dir", required=True)
    ap.add_argument("--profile", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--expect-runner-manifest-sha256", required=True,
                    help="4.3b's godkendte manifest-hash — bygningen stopper, hvis "
                         "forslagene ikke stammer fra netop den kørsel")
    args = ap.parse_args()

    runner_manifest = json.loads(Path(args.runner_manifest).read_text(encoding="utf-8"))
    if runner_manifest.get("manifest_sha256") != args.expect_runner_manifest_sha256:
        print("RUNNER_MANIFEST_DRIFT — ikke den kørsel, der blev givet GO til.")
        return 1

    runner_input = json.loads(Path(args.runner_input).read_text(encoding="utf-8"))["records"]
    profil = json.loads(Path(args.profile).read_text(encoding="utf-8"))
    denylist = profil["no_counterpart_denylist"]
    rolle_map = profil["persona_role_map"]
    cache_dir = Path(args.cache_dir)

    # Fillisten hash-bindes, så manifestet kan efterprøves mod netop de filer, det
    # blev bygget af.
    filliste = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(cache_dir.glob("*.json"))}

    elementer, afvist_h1, dubletter, ukendt_rolle = [], [], [], []
    n_raa = n_kontrakt_afvist = 0
    sete_noegler: set[str] = set()
    usage_sum = {"input_tokens": 0, "output_tokens": 0, "reasoning_output_tokens": 0,
                 "cached_input_tokens": 0, "cache_write_input_tokens": 0}

    for key in runner_manifest["records"]:
        rec = runner_input[key]
        ident = {
            "profile_id": runner_manifest["profile_id"],
            "profile_version": runner_manifest["profile_version"],
            "model": runner_manifest["model"],
            "prompt_sha256": runner_manifest["prompt_sha256"],
            "record_input_sha256": canonical_record_input(rec),
            "claims_schema_sha256": runner_manifest["claims_schema_sha256"],
            "runner_contract_version": LEGACY_RUNNER_CONTRACT_VERSION,
        }
        sti = cache_dir / f"{legacy_cache_key(ident)}.json"
        if not sti.exists():
            print(f"CACHE_MISS {key} — svaret fra 4.3b kan ikke adresseres.")
            return 1
        post = json.loads(sti.read_text(encoding="utf-8"))
        for k in usage_sum:
            usage_sum[k] += post["usage"].get(k, 0)

        raa = json.loads(post["raw"]).get("claims", [])
        n_raa += len(raa)

        # Re-kør kontraktvalideringen: cachens `raw` rummer ALLE modellens claims,
        # inklusive dem, 4.3b's kørsel afviste.
        gyldige, afviste = partition_record_claims(raa, rec)
        n_kontrakt_afvist += len(afviste)

        claims = []
        for c in gyldige:
            pred = c["predicate"]
            if pred.startswith("relation.") and uden_modpart(c.get("value"), denylist):
                afvist_h1.append({"record_key": key, "predicate": pred})
                continue
            rolle = persona_rolle(pred, rolle_map)
            if rolle is None:
                # Fail-closed: en gættet rolle er 4.2's kind-afledningsfejl igen.
                ukendt_rolle.append({"record_key": key, "predicate": pred})
                continue
            nøgle_input = interpretation_key_input(
                runner_manifest.get("source_id", 1), key, pred,
                c["clause_ordinals"], c["value"])
            nøgle = sha256_text(nøgle_input)
            if nøgle in sete_noegler:
                # Modellen kan gentage et claim inden for samme record (IV-19 gav 25).
                # Uden dedup her ville writeren afvise hele recorden på
                # ..._PROPOSAL_EXISTS — atomicitetsfejlen igen.
                dubletter.append({"record_key": key, "predicate": pred})
                continue
            sete_noegler.add(nøgle)
            claims.append({
                "claim_id": nøgle[:32],
                "predicate": pred,
                "interpretation_kind": evidence_extract.predicate_kind(pred),
                "value": c["value"],
                "confidence": c["confidence"],
                "cited_clauses": [
                    {"ordinal": o,
                     "verbatim_sha256": next(x["verbatim_sha256"] for x in rec["clauses"]
                                             if x["ordinal"] == o)}
                    for o in sorted(set(c["clause_ordinals"]))],
                "persona_role": rolle,
            })

        if claims:
            elementer.append({
                # R-klienten kræver `dependency_class` og `element_id` på hver
                # operation — se apply_reimport_helpers.R's validate-blok.
                #
                # Operationen er FLAD: writer-payloaden er operationen MINUS
                # `element_id` og `dependency_class` (apply_reimport_helpers.R,
                # `reimport_authorized_payloads`). En nøgle `payload` ville derfor
                # selv blive en payload-nøgle og fælde writerens lukkede nøglesæt
                # (`ARRAY['claims','model_version','prompt_version',
                # 'runner_manifest_sha256','source_record_key']`). Autorisationen
                # fanger det ikke: den sammenligner kun de to sider med hinanden.
                "dependency_class": "interpretation_proposal",
                "element_id": f"interpretation-proposal:{key}",
                "source_record_key": key,
                "runner_manifest_sha256": runner_manifest["manifest_sha256"],
                "model_version": runner_manifest["model"],
                "prompt_version": runner_manifest["prompt_sha256"],
                "claims": claims,
            })

    n_ingestible = sum(len(e["claims"]) for e in elementer)
    # Manifestets nøglesæt er LUKKET af R-klienten: kun manifest_content_sha256,
    # source, expected_counts og operations — plus de valgfrie dispositions og
    # provenance. Regnskabet hører derfor i `provenance`, som netop er den
    # ikke-autoriserende blok, der binder manifestet til de artefakter, det er
    # bygget af (4.1c's mønster).
    manifest = {
        "source": {
            "id": runner_manifest.get("source_id", 1),
            "profile_id": profil["profile_id"],
            # SAMME definition som databasens private.reimport_canonical_json_sha256:
            # kanonisk JSON af writer_config, ikke en hash af hele filen. Verificeret
            # at Postgres og Python giver bit-identisk resultat.
            "profile_sha256": sha256_text(json.dumps(
                profil["writer_config"], ensure_ascii=False,
                separators=(",", ":"), sort_keys=True)),
        },
        # `canonical_delta` skal med: R-klientens sidste kontrol sammenligner ALLE
        # navne i sin egen counts-vektor mod manifestet, og den vektor rummer
        # canonical_delta = 0 uanset operation.
        "expected_counts": {"person_creates": 0, "source_evidence": 0,
                            "canonical_delta": 0,
                            "interpretation_proposals": len(elementer)},
        "operations": elementer,
        "provenance": {
            "schema_version": "interpretation-proposal-manifest-1.0",
            "runner_manifest_sha256": runner_manifest["manifest_sha256"],
            "eligibility_ledger_sha256": runner_manifest["eligibility_ledger_sha256"],
            "cache_files": filliste,
            "predicates_sha256": sha256_text(
                (Path(__file__).resolve().parents[1] / "references"
                 / "interpretation-predicates.json").read_text(encoding="utf-8")),
            "runner_contract_version": LEGACY_RUNNER_CONTRACT_VERSION,
            "denylist_version": denylist["version"],
            "persona_role_map_version": rolle_map["version"],
            # FEM tal, ikke tre. Uden dem kan "antal = manifestets" ikke
            # kontrolleres mod noget.
            "regnskab": {
                "raa_claims": n_raa,
                "kontrakt_afviste": n_kontrakt_afvist,
                "h1_afviste": len(afvist_h1),
                "dubletter": len(dubletter),
                "ukendt_rolle": len(ukendt_rolle),
                "ingestible": n_ingestible,
            },
            "h1_afviste": afvist_h1,
            "dublet_claims": dubletter,
            "ukendt_rolle_claims": ukendt_rolle,
            "usage": usage_sum,
        },
    }
    krop = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    manifest["manifest_content_sha256"] = hashlib.sha256(krop.encode("utf-8")).hexdigest()

    out = Path(args.out)
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    out.chmod(0o600)

    r = manifest["provenance"]["regnskab"]
    print(f"PROPOSAL_MANIFEST_OK elementer={len(elementer)}")
    print(f"  rå claims        {r['raa_claims']}")
    print(f"  kontrakt-afviste {r['kontrakt_afviste']}")
    print(f"  H1-afviste       {r['h1_afviste']}")
    print(f"  dubletter        {r['dubletter']}")
    print(f"  ingestible       {r['ingestible']}")
    print(f"  ukendt rolle     {r['ukendt_rolle']}")
    if r["raa_claims"] != (r["kontrakt_afviste"] + r["h1_afviste"] + r["dubletter"]
                           + r["ukendt_rolle"] + r["ingestible"]):
        print("  ** REGNSKABET GÅR IKKE OP **")
        return 1
    print(f"  manifest_content_sha256: {manifest['manifest_content_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
