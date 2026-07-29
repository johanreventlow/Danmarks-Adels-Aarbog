#!/usr/bin/env python3
"""Vælg og udskriv kalibrerings-batch for DAA 1939-re-ekstraktionen.

Formål: afgøre modeltier på EVIDENS frem for ræsonnement, jf.
`docs/reviews/re-ekstraktion-forberedelse-2026-07-29.md` §Del 1.

Stratificeringen er valgt så den rammer præcis dér hvor det gik galt sidst —
ikke tilfældigt:

  A. OMTALER  — de 24 gravsatte poster. Facit er kendt: `er_omtale` SKAL være
     true. Det er den dyreste fejl (gav ~30 spøgelsespersoner), og det eneste
     stratum hvor vi har facit uden at slå op i bogen.
  B. FLERE ÆGTESKABER — tester ægtefælle-dekomponering og `ordinal_kilde`.
     Ægtefæller havde præcis ét faktum efter sidste udtræk.
  C. TÆTTE BIOGRAFIER — lange narrativer med embeder, dekorationer, godser og
     tredjeparts-personer. Det er her klassifikation (embede vs karriere) og
     `kilde_span` bliver svært, og hvor den billige tier målt tabte sidst.

Udskriver til work/kalibrering/ (gitignoreret — narrativerne er PII).

Kør:
  python3 tools/kalibrering/vaelg-poster.py [--antal-pr-stratum 10]
"""
import argparse
import json
import random
import sys
from pathlib import Path

ROD = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROD / ".claude/skills/daa-extract/scripts"))

ARTEFAKT = ROD / "work_1939_stamtavle/linked_clean.json"
PROD_DUMP = ROD / "work_1939_stamtavle/prod_dump_1939_2026-07-28.json"
NARRATIV_ARTEFAKT = ROD / "work_1939_stamtavle/narrative_1939_patch_v2.json"
UD = ROD / "work/kalibrering"
FRØ = 20260729  # fast frø: samme udvalg ved gentagne kørsler, så kørsler kan sammenlignes


def nr_map(recs):
    import convert_1939_stamtavle as C
    nr, ud = 0, {}
    for unit in C.build_units(recs):
        for r in unit:
            nr += 1
            ud[nr] = r
    return ud


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--antal-pr-stratum", type=int, default=10)
    a = ap.parse_args()

    recs = json.loads(ARTEFAKT.read_text(encoding="utf-8"))
    alle = nr_map(recs)
    prod = {p["nr"]: p for p in json.loads(PROD_DUMP.read_text(encoding="utf-8"))}
    narrativ = {n: (p.get("narrativ") or "") for n, p in prod.items()}
    side = {n: p.get("side") for n, p in prod.items()}
    # Gravsatte poster er slettet i prod og mangler derfor i dumpet. Deres prosa
    # findes stadig i segmenterens output — den er kilden, ikke basen.
    if NARRATIV_ARTEFAKT.exists():
        for rad in json.loads(NARRATIV_ARTEFAKT.read_text(encoding="utf-8")):
            n = rad.get("nr")
            if n is None or narrativ.get(n):
                continue
            narrativ[n] = rad.get("narrative") or ""
            sider = rad.get("sider")
            side.setdefault(n, sider[0] if isinstance(sider, list) and sider else sider)

    omtaler = sorted(n for n, r in alle.items() if r.get("fjernet"))
    levende = [n for n, r in alle.items() if not r.get("fjernet")]
    flere = sorted(n for n in levende if len(alle[n].get("aegteskaber") or []) > 1)
    taette = sorted((n for n in levende if len(narrativ.get(n, "")) > 800),
                    key=lambda n: -len(narrativ.get(n, "")))

    rng = random.Random(FRØ)
    valgt = {
        # Omtalerne er den vigtigste prøve — tag dem spredt, ikke bare de første.
        "A_omtale": sorted(rng.sample(omtaler, min(a.antal_pr_stratum, len(omtaler)))),
        "B_flere_aegteskaber": sorted(rng.sample(flere, min(a.antal_pr_stratum, len(flere)))),
        # Tætte: tag de længste — det er dér klassifikationen er sværest.
        "C_taet_biografi": sorted(taette[:a.antal_pr_stratum]),
    }
    # Gravsatte poster har ingen narrativ i prod (de er slettet) — deres tekst
    # findes kun i det gamle dump. Meld hvis den mangler, frem for at sende tom prosa.
    UD.mkdir(parents=True, exist_ok=True)
    manglende = []
    batch = []
    for stratum, nrs in valgt.items():
        for n in nrs:
            tekst = narrativ.get(n, "")
            if not tekst:
                manglende.append((stratum, n))
                continue
            batch.append({
                "kalibrering_id": f"{stratum}:{n}",
                "stratum": stratum,
                "nr": n,
                "side": side.get(n),
                "linje": "1939",
                "nr_label": str(n),
                "raw_text": tekst,
            })

    (UD / "batch.json").write_text(
        json.dumps(batch, ensure_ascii=False, indent=1), encoding="utf-8")

    # Facit-skabelon: kun de dimensioner der FEJLEDE sidst. Kort nok til at
    # kunne udfyldes mod bogen uden at blive et projekt i sig selv.
    facit = [{
        "kalibrering_id": b["kalibrering_id"],
        "side": b["side"],
        "_udfyld": "sæt værdierne nedenfor efter opslag i bogen",
        "er_omtale": None,
        "antal_aegteskaber": None,
        "aegtefaelle_har_datoer": None,
        "antal_embeder": None,
        "antal_godser": None,
        "koen": None,
    } for b in batch]
    (UD / "facit-skabelon.json").write_text(
        json.dumps(facit, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"batch:  {len(batch)} poster → {UD}/batch.json")
    for s, nrs in valgt.items():
        i_batch = sum(1 for b in batch if b["stratum"] == s)
        print(f"  {s:22} {i_batch}/{len(nrs)}  nr {nrs}")
    if manglende:
        print(f"\n⚠ {len(manglende)} poster uden narrativ i prod-dumpet (slettede omtaler):")
        for s, n in manglende:
            print(f"    {s}: nr {n}")
        print("  → deres prosa skal hentes fra et ældre dump eller fra OCR-teksten.")
    print(f"\nfacit-skabelon → {UD}/facit-skabelon.json")


if __name__ == "__main__":
    main()
