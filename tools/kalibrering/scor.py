#!/usr/bin/env python3
"""Scor et kalibrerings-udtræk mod facit.

Scorer KUN de dimensioner der faktisk fejlede i DAA 1939-udtrækket — ikke alt
skemaet kan udtrykke. En bred score ville udvande netop de tal beslutningen
skal hvile på.

  er_omtale       — den dyreste fejl (~30 spøgelsespersoner). Vægtes højest.
  ægtefælle-data  — havde præcis ét faktum (navnet) efter sidste udtræk
  embeder         — 0 af 515 poster fik et embede
  godser          — 85 ægtefæller havde gods inde i navnefeltet
  navn rent       — titel/gods må ikke stå i navnet
  kilde_span      — BLOKERENDE i pipelinen (R7): skal være ordret substring

`er_omtale` for stratum A har facit uden opslag i bogen: de 10 poster ER de
gravsatte omtaler. De øvrige felter kræver menneskeligt facit.

Kør:
  python3 tools/kalibrering/scor.py --udtraek work/kalibrering/terra/ \\
      --facit work/kalibrering/facit.json --batch work/kalibrering/batch.json
"""
import argparse
import json
from pathlib import Path


def id_fra_filnavn(stem: str) -> str:
    """`A_omtale_43` → `A_omtale:43`.

    Stratum-navnet indeholder selv underscores, så det er den SIDSTE der er
    separatoren. En naiv replace-fra-venstre gav `A:omtale_43`, som ikke matchede
    facit — og scoringen sprang så tavst er_omtale over.
    """
    hoved, _, hale = stem.rpartition("_")
    return f"{hoved}:{hale}" if hoved else stem


def hent_udtraek(mappe: Path) -> dict:
    """Ét JSON-objekt pr. post; filnavn = kalibrering_id med ':' → '_'."""
    ud = {}
    for f in sorted(mappe.glob("*.json")):
        kid = id_fra_filnavn(f.stem)
        try:
            ud[kid] = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            ud[kid] = {"_ugyldig_json": str(e)}
    return ud


def span_ordret(post: dict, raw: str) -> tuple[int, int]:
    """(antal spans, antal der IKKE findes ordret i raw_text). R7 er blokerende."""
    spans = [f.get("kilde_span") for f in (post.get("facts") or [])]
    spans += [a.get("kilde_span") for a in (post.get("aegteskaber") or [])]
    spans = [s for s in spans if s]
    return len(spans), sum(1 for s in spans if s not in raw)


NAVNESTØJ = ("til ", "Greve", "Grevinde", "Comtesse", "Baron", "Kammerherre",
             "Geheime", "General", "Oberst", "Amtmand", "(")


def navn_urent(navn: str) -> bool:
    return any(t in (navn or "") for t in NAVNESTØJ)


def scor(udtraek: dict, facit: dict, batch: dict) -> dict:
    r = {"poster": 0, "ugyldig_json": 0,
         "omtale_ret": 0, "omtale_forkert": 0, "omtale_facit": 0,
         "span_i_alt": 0, "span_ikke_ordret": 0,
         "navn_urent": 0,
         "aegt_m_partnerdata": 0, "aegt_i_alt": 0,
         "embeder": 0, "godser": 0,
         "ordinal_kilde_sat": 0, "koen_kilde_sat": 0}
    afvigelser = []
    for kid, post in sorted(udtraek.items()):
        r["poster"] += 1
        if post.get("_ugyldig_json"):
            r["ugyldig_json"] += 1
            afvigelser.append((kid, "ugyldig JSON", post["_ugyldig_json"][:60]))
            continue
        f = facit.get(kid, {})
        b = batch.get(kid, {})

        # er_omtale — vigtigste dimension
        if f.get("er_omtale") is not None:
            r["omtale_facit"] += 1
            if bool(post.get("er_omtale")) == bool(f["er_omtale"]):
                r["omtale_ret"] += 1
            else:
                r["omtale_forkert"] += 1
                afvigelser.append((kid, "er_omtale",
                                   f"udtræk={post.get('er_omtale')} facit={f['er_omtale']}"))

        n, ikke = span_ordret(post, b.get("raw_text", ""))
        r["span_i_alt"] += n
        r["span_ikke_ordret"] += ikke
        if ikke:
            afvigelser.append((kid, "kilde_span ikke ordret", f"{ikke} af {n}"))

        if navn_urent(post.get("navn", "")):
            r["navn_urent"] += 1
            afvigelser.append((kid, "navn indeholder titel/gods", post.get("navn", "")[:50]))

        for a in (post.get("aegteskaber") or []):
            r["aegt_i_alt"] += 1
            if any(a.get(k) for k in ("partner_foedsel", "partner_doed", "partner_daab",
                                      "partner_koen", "partner_titel", "partner_godser")):
                r["aegt_m_partnerdata"] += 1
            if a.get("ordinal_kilde"):
                r["ordinal_kilde_sat"] += 1
        r["embeder"] += len(post.get("embeder") or [])
        r["godser"] += len(post.get("godser") or [])
        if post.get("koen_kilde"):
            r["koen_kilde_sat"] += 1
    return r, afvigelser


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--udtraek", required=True, type=Path)
    ap.add_argument("--facit", type=Path)
    ap.add_argument("--batch", required=True, type=Path)
    ap.add_argument("--navn", default=None, help="etiket i rapporten, fx 'terra'")
    a = ap.parse_args()

    batch = {b["kalibrering_id"]: b for b in json.loads(a.batch.read_text(encoding="utf-8"))}
    facit = {}
    if a.facit and a.facit.exists():
        facit = {f["kalibrering_id"]: f for f in json.loads(a.facit.read_text(encoding="utf-8"))}
    else:
        # Stratum A har facit uden bogopslag: de poster ER de gravsatte omtaler.
        facit = {k: {"er_omtale": True} for k in batch if k.startswith("A_omtale")}
        print("(intet facit angivet — scorer kun er_omtale for stratum A)\n")

    udtraek = hent_udtraek(a.udtraek)
    ukendte = [k for k in udtraek if k not in batch]
    if ukendte:
        print(f"⚠ {len(ukendte)} udtræks-id matcher INGEN post i batchen: {ukendte[:3]}")
        print("  (filnavn skal være <kalibrering_id> med ':' erstattet af '_')\n")
    r, afv = scor(udtraek, facit, batch)
    navn = a.navn or a.udtraek.name
    print(f"=== {navn} ===")
    print(f"  poster                 {r['poster']}   ugyldig JSON: {r['ugyldig_json']}")
    if r["omtale_facit"]:
        pct = 100 * r["omtale_ret"] / r["omtale_facit"]
        print(f"  er_omtale korrekt      {r['omtale_ret']}/{r['omtale_facit']}  ({pct:.0f} %)")
    print(f"  kilde_span ikke ordret {r['span_ikke_ordret']}/{r['span_i_alt']}   ← BLOKERENDE i pipelinen")
    print(f"  navn m. titel/gods     {r['navn_urent']}")
    print(f"  ægteskaber m. partnerdata {r['aegt_m_partnerdata']}/{r['aegt_i_alt']}")
    print(f"  ordinal_kilde sat      {r['ordinal_kilde_sat']}/{r['aegt_i_alt']}")
    print(f"  koen_kilde sat         {r['koen_kilde_sat']}/{r['poster']}")
    print(f"  embeder i alt          {r['embeder']}")
    print(f"  godser i alt           {r['godser']}")
    if afv:
        print(f"\n  afvigelser ({len(afv)}):")
        for kid, hvad, detalje in afv[:15]:
            print(f"    {kid:26} {hvad:28} {detalje}")
        if len(afv) > 15:
            print(f"    … og {len(afv) - 15} mere")


if __name__ == "__main__":
    main()
