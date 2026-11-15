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
from private_io import write_private_replace  # noqa: E402

import evidence_extract
import evidence_runner
from compare_interpretation_proposal_projection import ProjectionError, strict_json_loads
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
#: Svar skrevet før `tool_use`-værnet (review 35, P1): strømmen er ikke gemt, så det
#: kan ikke efterprøves, om modellen kørte noget.  De må kun bruges til at genbygge
#: de historiske 4.3b/4.5-manifester — udtrykkeligt, med flag.
PRE_P1_RUNNER_CONTRACTS = {"evidence-runner-1.0", "evidence-runner-1.1", "evidence-runner-1.2"}


def parse_cached_raw_claims(raw: str) -> list:
    """Decode cache JSON strictly before the existing claim boundary sees it."""
    try:
        payload = strict_json_loads(raw)
    except ProjectionError as exc:
        raise ValueError("CACHE_RAW_JSON_INVALID") from exc
    if not isinstance(payload, dict) or set(payload) != {"claims"} or not isinstance(payload["claims"], list):
        raise ValueError("CACHE_RAW_JSON_INVALID")
    # Den strenge afkodning er kun en port (dubletnøgler, NaN, U+0000, lone surrogates).
    # Claim-grænsen nedenfor forventer den almindelige afkodning (float-confidence), og
    # numeriske claim-værdier afvises dér uanset repræsentation.
    return json.loads(raw)["claims"]


def legacy_cache_key(ident: dict) -> str:
    material = "\x1f".join(str(ident[f]) for f in LEGACY_CACHE_KEY_FIELDS)
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def cache_path(cache_dir: Path, ident: dict, *, mode: str) -> Path:
    if mode == "legacy":
        return cache_dir / f"{legacy_cache_key(ident)}.json"
    if mode == "current":
        return cache_dir / f"{evidence_runner.ResponseCache.key(ident)}.json"
    raise ValueError(f"CACHE_KEY_MODE_UNKNOWN {mode}")


def verify_runner_manifest(runner_manifest: dict, expected_sha256: str) -> None:
    """Det godkendte runner-manifest — genberegnet, ikke kun aflæst (4.5-kodereview, fund 5)."""
    from build_43b_manifest import bundles_of, manifest_sha256
    if runner_manifest.get("manifest_sha256") != expected_sha256:
        raise ValueError("RUNNER_MANIFEST_DRIFT — ikke den kørsel, der blev givet GO til.")
    if manifest_sha256(runner_manifest) != expected_sha256:
        raise ValueError("RUNNER_MANIFEST_TAMPERED — indholdet svarer ikke til hashen.")
    flad = [k for keys in bundles_of(runner_manifest).values() for k in keys]
    if len(flad) != len(set(flad)) or set(flad) != set(runner_manifest["records"]):
        raise ValueError("RUNNER_BUNDLES_INVALID — bundterne er ikke en disjunkt opdeling "
                         "af manifestets records.")


def records_to_ingest(runner_manifest: dict, bundles: list[str] | None) -> list[str]:
    """Hele manifestet, eller kun de navngivne bundter (4.5: reserven kun hvis kørt)."""
    if not bundles:
        return list(runner_manifest["records"])
    from build_43b_manifest import bundles_of
    alle = bundles_of(runner_manifest)
    ukendte = [b for b in bundles if b not in alle]
    if ukendte:
        raise ValueError(f"BUNDLE_UNKNOWN {ukendte}")
    return [k for b in bundles for k in alle[b]]


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


# ---------------------------------------------------------------------------
# H2 FINDES IKKE, OG DET ER MED VILJE (plan 4.4 Task 6 Step 3).
#
# »Claimet er mere præcist end kilden« afgøres IKKE maskinelt i dette dagsværk.
# Der er ingen H2-funktion at lede efter — det er et valg, ikke en mangel.
#
# Baggrunden er 4.3b's ene usande claim. Bogen skriver:
#
#     »…var død 1353 (23. april), DA hans sønner … solgte landsbyen.«
#
# 23. april 1353 er SALGETS dato — en terminus ante quem for dødsfaldet. Modellen
# læste konstruktionen »var død [dato], da [begivenhed]« som en dødsdato. Begge
# dødsclaims stod ORDRET i teksten; modellen udledte og opfandt intet.
#
# Fejlen er derfor sproglig, ikke numerisk, og de to detektorer, tidligere
# planudgaver foreslog, kunne ikke fange den:
#   - »sammenlign søsterclaims« sammenligner modeloutput med modeloutput;
#   - »sammenlign date_min/date_max med raw« refererer til felter, et
#     `date_raw`-claim slet ikke har.
#
# Signalet »se nærmere på dette claim« bor i stedet i bedømmelsesarkets
# forudfyldte anbefalingskolonner (spec §8.2), ikke i en kolonne i databasen.
# Se plan 4.4 Task 6 for begrundelsen og for genåbningskriteriet.
# ---------------------------------------------------------------------------


def persona_rolle(predicate: str, rolle_map: dict) -> str | None:
    """`principal` eller `other` efter profilens eksplicitte kort.

    Spec §7.2 dækker kun `person.*` og mention/relation, men 4.3b's data rummer otte
    `event.*`-claims, som handler om hovedpersonen uden at have `person.`-præfiks.
    En naiv »ikke person.* → other« ville give dem persona NULL og stemple deres
    klausuler `afventer_identitet`. Se spec-errata til §7.2.

    Matchningen er præfiksbaseret, men præfikserne og deres roller er DATA i
    profilen — ikke en regel udledt af prædikatstrengens form. Det er forskellen
    på dette og 4.2's kind-afledningsfejl.

    LÆNGSTE præfiks vinder, så et senere `event.marriage` kan få en anden rolle end
    `event.`. Uden det ville listernes rækkefølge afgøre det stiltiende. Står samme
    præfiks i begge lister, er kortet selvmodsigende, og vi rejser frem for at vælge.

    Returnerer None for et prædikat, kortet ikke kender — så afviser kalderen det
    frem for at gætte.
    """
    traeffere = [(len(p), rolle)
                 for rolle in ("principal", "other")
                 for p in rolle_map[rolle]
                 if predicate.startswith(p)]
    if not traeffere:
        return None
    laengste = max(n for n, _ in traeffere)
    roller = {rolle for n, rolle in traeffere if n == laengste}
    if len(roller) != 1:
        raise ValueError(
            f"persona_role_map er selvmodsigende for {predicate!r}: {sorted(roller)}")
    return roller.pop()


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
    ap.add_argument("--cache-key", choices=["legacy", "current"], default="legacy")
    ap.add_argument("--bundles", help="kommasepareret; default: hele manifestet")
    ap.add_argument("--historisk-foer-p1", action="store_true",
                    help="tillad svar fra kontrakt 1.0-1.2 (kun til genbygning af 4.3b/4.5)")
    ap.add_argument("--expect-runner-manifest-sha256", required=True,
                    help="4.3b's godkendte manifest-hash — bygningen stopper, hvis "
                         "forslagene ikke stammer fra netop den kørsel")
    args = ap.parse_args()

    runner_manifest = json.loads(Path(args.runner_manifest).read_text(encoding="utf-8"))
    try:
        verify_runner_manifest(runner_manifest, args.expect_runner_manifest_sha256)
    except ValueError as exc:
        print(str(exc))
        return 1
    kontrakt_foer = (LEGACY_RUNNER_CONTRACT_VERSION if args.cache_key == "legacy"
                     else runner_manifest["runner_contract_version"])
    if kontrakt_foer in PRE_P1_RUNNER_CONTRACTS and not args.historisk_foer_p1:
        print(f"PRE_P1_CACHE_REFUSED {kontrakt_foer} — svar fra før værktøjsværnet (review 35, "
              "P1) bruges kun med --historisk-foer-p1.")
        return 1

    runner_input = json.loads(Path(args.runner_input).read_text(encoding="utf-8"))["records"]
    profil = json.loads(Path(args.profile).read_text(encoding="utf-8"))
    if evidence_runner.contract_at_least(runner_manifest.get("runner_contract_version"), (1, 4)):
        # Nye manifester har ingen standardværdi for kilden (Codex fund 3).
        if "source_id" not in runner_manifest:
            print("PROPOSAL_MANIFEST_SOURCE_MISSING — runner-manifestet bærer ikke source_id.")
            return 1
        if runner_manifest["source_id"] != profil.get("source_id"):
            print("PROPOSAL_MANIFEST_SOURCE_MISMATCH — runner-manifestets kilde afviger fra "
                  "writerprofilens.")
            return 1
    denylist = profil["no_counterpart_denylist"]
    rolle_map = profil["persona_role_map"]
    cache_dir = Path(args.cache_dir)

    # Fillisten hash-bindes, så manifestet kan efterprøves mod netop de filer, det
    # blev bygget af.
    filliste = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(cache_dir.glob("*.json"))}

    elementer, afvist_h1, dubletter, ukendt_rolle = [], [], [], []
    principal_uden_persona = []
    n_raa = n_kontrakt_afvist = 0
    sete_noegler: set[str] = set()
    usage_sum = {"input_tokens": 0, "output_tokens": 0, "reasoning_output_tokens": 0,
                 "cached_input_tokens": 0, "cache_write_input_tokens": 0}

    kontrakt = (LEGACY_RUNNER_CONTRACT_VERSION if args.cache_key == "legacy"
                else runner_manifest["runner_contract_version"])
    try:
        noegler = records_to_ingest(runner_manifest,
                                    args.bundles.split(",") if args.bundles else None)
    except ValueError as exc:
        print(str(exc))
        return 1
    for key in noegler:
        rec = runner_input[key]
        ident = {
            "profile_id": runner_manifest["profile_id"],
            "profile_version": runner_manifest["profile_version"],
            "model": runner_manifest["model"],
            "prompt_sha256": runner_manifest["prompt_sha256"],
            "record_input_sha256": canonical_record_input(rec),
            # Indgår kun i nøglen fra kontrakt 1.2; 4.3b/4.5's caches (1.0) adresseres
            # uændret (`ResponseCache.key` vælger felter efter kontrakten).
            "clause_set_sha256": evidence_runner.canonical_clause_set(rec),
            "claims_schema_sha256": runner_manifest["claims_schema_sha256"],
            "runner_contract_version": kontrakt,
        }
        if args.cache_key == "current":
            ident["record_key"] = key
        sti = cache_path(cache_dir, ident, mode=args.cache_key)
        if not sti.exists():
            print(f"CACHE_MISS {key} — svaret fra 4.3b kan ikke adresseres.")
            return 1
        post = json.loads(sti.read_text(encoding="utf-8"))
        for k in usage_sum:
            usage_sum[k] += post["usage"].get(k, 0)

        try:
            raa = parse_cached_raw_claims(post["raw"])
        except ValueError:
            print("CACHE_RAW_JSON_INVALID")
            return 1
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
            if rolle == "principal" and not rec.get("persona_id"):
                # Writeren afviser et principal-forslag på en post uden persona
                # (REIMPORT_WRITER_PRINCIPAL_WITHOUT_PERSONA) og ruller hele posten
                # tilbage. Afgøres derfor her, så kun dette ene claim fælder (II-35,
                # 2026-10-02: event.marriage; rollen kommer fra prædikatet). Claimet er
                # TABT, ikke udskudt: har posten andre forslag, spærrer S4-værnet et nyt
                # forslag, til et menneske har afgjort de gamle. Writeren afleder selv
                # personaen af præcis én primær mention på helposten; eksportens persona_id
                # er en stedfortræder for den regel (opus-review 2026-10-02, fund 1).
                principal_uden_persona.append({"record_key": key, "predicate": pred})
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

    if args.cache_key == "legacy" and principal_uden_persona:
        # Legacy-manifestet har ingen konto til frasorterede claims (byte-identiteten
        # for 4.3b/4.5); regnskabet ville ikke gå op. Fail closed før noget skrives.
        print(f"PRINCIPAL_UDEN_PERSONA_I_LEGACY {len(principal_uden_persona)}")
        return 1
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
            "runner_contract_version": kontrakt,
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
    if args.cache_key == "current":
        # Kun i den nye tilstand: 4.4's legacy-manifest skal kunne genbygges byte-identisk.
        manifest["provenance"]["cache_key_mode"] = "current"
        # Også kun her: kontoen er ny (2026-10-02), og legacy-manifestet skal forblive
        # byte-identisk. I legacy-tilstand er den 0 — ellers stopper bygningen ovenfor.
        manifest["provenance"]["regnskab"]["principal_uden_persona"] = len(principal_uden_persona)
        manifest["provenance"]["principal_uden_persona_claims"] = principal_uden_persona
        manifest["provenance"]["records"] = noegler
    krop = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    manifest["manifest_content_sha256"] = hashlib.sha256(krop.encode("utf-8")).hexdigest()

    out = Path(args.out)
    write_private_replace(out, json.dumps(manifest, ensure_ascii=False, indent=2))

    r = manifest["provenance"]["regnskab"]
    print(f"PROPOSAL_MANIFEST_OK elementer={len(elementer)}")
    print(f"  rå claims        {r['raa_claims']}")
    print(f"  kontrakt-afviste {r['kontrakt_afviste']}")
    print(f"  H1-afviste       {r['h1_afviste']}")
    print(f"  dubletter        {r['dubletter']}")
    print(f"  ingestible       {r['ingestible']}")
    print(f"  ukendt rolle     {r['ukendt_rolle']}")
    print(f"  principal uden persona {len(principal_uden_persona)}")
    if r["raa_claims"] != (r["kontrakt_afviste"] + r["h1_afviste"] + r["dubletter"]
                           + r["ukendt_rolle"] + len(principal_uden_persona) + r["ingestible"]):
        print("  ** REGNSKABET GÅR IKKE OP **")
        return 1
    print(f"  manifest_content_sha256: {manifest['manifest_content_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
