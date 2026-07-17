#!/usr/bin/env python3
# =====================================================================
#  facit_1939.py — struktur-facit for clean_1939.json (Codex min-krav
#  #6, delvist). Rapporterer KUN TAL — aldrig navne/persondata (PII-
#  disciplin: korpus rummer potentielt levende personer).
#
#  Brug:  python3 facit_1939.py [work_1939_stamtavle/clean_1939.json]
# =====================================================================
import json
import sys
from collections import Counter
from pathlib import Path

GDPR_AAR = 1926  # fødsels-ISO-år >= 1926 uden dødsdato-fakta => potentielt levende


def facit(posts):
    r = {}
    r["poster"] = len(posts)

    # nøgle-unikhed
    noegler = [(p["linje"], p["nr_label"]) for p in posts]
    r["dublette_noegler"] = len(noegler) - len(set(noegler))
    nrs = [p["nr"] for p in posts]
    r["dublette_nr"] = len(nrs) - len(set(nrs))

    # facts pr. faktatype + dato-parse-rate
    pr_type = Counter()
    dato_fakta = dato_med_bounds = dato_tomme_bounds = 0
    for p in posts:
        for f in p.get("facts") or []:
            pr_type[f["faktatype"]] += 1
            if f.get("date_raw"):
                dato_fakta += 1
                if f.get("date_min") or f.get("date_max"):
                    dato_med_bounds += 1
                else:
                    dato_tomme_bounds += 1
    r["facts_pr_type"] = dict(sorted(pr_type.items()))
    r["dato_fakta"] = dato_fakta
    r["dato_med_bounds"] = dato_med_bounds
    r["dato_tomme_bounds"] = dato_tomme_bounds
    r["dato_parse_rate_pct"] = round(100.0 * dato_med_bounds / dato_fakta, 1) if dato_fakta else None

    # GDPR-flag: fødsel-ISO-år >= GDPR_AAR og INGEN død-fakta
    def iso_aar(f):
        for k in ("date_min", "date_max"):
            v = f.get(k)
            if v:
                return int(v[:4])
        return None

    gdpr = gdpr_inkl_begravelse = 0
    for p in posts:
        facts = p.get("facts") or []
        typer = {f["faktatype"] for f in facts}
        foedsel_aar = [iso_aar(f) for f in facts
                       if f["faktatype"] == "fødsel" and iso_aar(f) is not None]
        if foedsel_aar and max(foedsel_aar) >= GDPR_AAR:
            if "død" not in typer:
                gdpr += 1
                if "begravelse" not in typer:
                    gdpr_inkl_begravelse += 1
    r["gdpr_flag_foedt_1926plus_uden_doed"] = gdpr
    r["  heraf_ogsaa_uden_begravelse"] = gdpr_inkl_begravelse

    # dækning
    r["med_aegteskaber"] = sum(1 for p in posts if p.get("aegteskaber"))
    r["aegteskaber_ialt"] = sum(len(p.get("aegteskaber") or []) for p in posts)
    ae_dato = [a for p in posts for a in p.get("aegteskaber") or [] if a.get("dato_raw")]
    r["aegteskaber_med_dato_raw"] = len(ae_dato)
    r["aegteskaber_dato_med_bounds"] = sum(1 for a in ae_dato if a.get("date_min") or a.get("date_max"))
    r["med_godser"] = sum(1 for p in posts if p.get("godser"))
    r["godser_ialt"] = sum(len(p.get("godser") or []) for p in posts)
    r["med_titel_fakta"] = sum(1 for p in posts if any(
        f["faktatype"] == "titel" for f in p.get("facts") or []))
    r["med_usikker"] = sum(1 for p in posts if p.get("usikker"))
    r["med_note"] = sum(1 for p in posts if p.get("note"))
    r["narrative_ikke_none"] = sum(1 for p in posts if p.get("narrative") is not None)
    r["med_boern_felt"] = sum(1 for p in posts if "boern" in p)
    return r


def main(argv):
    sti = Path(argv[1]) if len(argv) > 1 else Path("work_1939_stamtavle/clean_1939.json")
    with open(sti, encoding="utf-8") as f:
        posts = json.load(f)
    r = facit(posts)
    print(f"facit_1939 — {sti} (KUN tal, ingen persondata)")
    for k, v in r.items():
        if k == "facts_pr_type":
            print("facts_pr_type:")
            for t, n in v.items():
                print(f"    {t}: {n}")
        else:
            print(f"{k}: {v}")


if __name__ == "__main__":
    main(sys.argv)
