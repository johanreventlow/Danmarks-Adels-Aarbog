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

    # ---- A3c: strukturelle forældre-barn-links (uafhængig efterprøvning
    # af konverterens output — falske børn i et range SKAL være 0, ellers
    # ville loaderen skabe datakorruption) ----
    nr2post = {p["nr"]: p for p in posts}
    linkede = [p for p in posts if p.get("_link_foraelder_nr") is not None]
    r["boern_strukturelt_linket"] = len(linkede)
    r["boern_strukturelt_linket_pct"] = round(100.0 * len(linkede) / len(posts), 1) if posts else None
    r["foraeldre_med_nr_range"] = sum(1 for p in posts if isinstance(p.get("boern"), dict))

    falske = range_fejl = 0
    for p in posts:
        b = p.get("boern")
        if not isinstance(b, dict) or not b.get("nr_range"):
            continue
        lo, hi = b["nr_range"]
        if lo > hi or lo < 1:
            range_fejl += 1
            continue
        for n in range(lo, hi + 1):
            q = nr2post.get(n)
            if q is None or q.get("_link_foraelder_nr") != p["nr"]:
                falske += 1
    r["nr_range_falske_boern"] = falske          # SKAL være 0
    r["nr_range_ugyldige"] = range_fejl          # SKAL være 0

    grupper = {}
    for p in posts:
        g = p.get("_gruppe_nr")
        if g is not None:
            grupper.setdefault(g, []).append(p)
    r["grupper"] = len(grupper)
    r["grupper_ikke_kontinuert_nr"] = sum(       # SKAL være 0 (by construction)
        1 for ms in grupper.values()
        if max(x["nr"] for x in ms) - min(x["nr"] for x in ms) + 1 != len(ms))
    uden_link = [ms for ms in grupper.values()
                 if not any(x.get("_link_foraelder_nr") is not None for x in ms)]
    r["grupper_uden_foraelder_link"] = len(uden_link)
    r["boern_i_grupper_uden_link"] = sum(len(ms) for ms in uden_link)
    r["roedder_uden_foraelder_link"] = sum(
        1 for p in posts if p.get("_link_foraelder_nr") is None)
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
