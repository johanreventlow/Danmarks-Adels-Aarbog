#!/usr/bin/env python3
"""Find kun de poster hvor to modeller er UENIGE — og bed om afgørelse dér.

Den dyre del af en kalibrering er ikke kørslen; det er det menneskelige facit.
At udfylde 20 poster i blinde er timers arbejde.

Men vi behøver ikke et facit for alle poster. Vi behøver at vide **hvilken model
der er bedst** — og dét afgøres kun af de poster hvor de svarer forskelligt.
Er de enige, bidrager posten intet til rangeringen, uanset om begge har ret
eller begge tager fejl.

Så: kør begge modeller, diff dem, og bed kun om afgørelse på uenighederne. Med
to rimeligt gode modeller er det typisk en håndfuld poster frem for tyve — og
hver enkelt kommer med prosaen og de to svar side om side, så afgørelsen er et
opslag frem for en udredning.

⚠ Forbehold: enighed er ikke sandhed. To modeller kan dele samme fejl — fx begge
overse at en post er en omtale. Derfor scores stratum A stadig mod sit kendte
facit (`scor.py`), og de enige poster stikprøves.

Kør:
  python3 tools/kalibrering/uenigheder.py --a work/kalibrering/terra --b work/kalibrering/luna
"""
import argparse
import json
from pathlib import Path

ROD = Path(__file__).resolve().parents[2]


def id_fra_filnavn(stem: str) -> str:
    hoved, _, hale = stem.rpartition("_")
    return f"{hoved}:{hale}" if hoved else stem


def hent(mappe: Path) -> dict:
    ud = {}
    for f in sorted(mappe.glob("*.json")):
        try:
            ud[id_fra_filnavn(f.stem)] = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            ud[id_fra_filnavn(f.stem)] = None
    return ud


def profil(p: dict | None) -> dict:
    """De få tal en uenighed kan handle om. Holdes groft med vilje — vi leder
    efter forskelle der betyder noget, ikke efter formateringsstøj."""
    if p is None:
        return {"ugyldig": True}
    return {
        "er_omtale": bool(p.get("er_omtale")),
        "navn": (p.get("navn") or "").strip(),
        "antal_fakta": len(p.get("facts") or []),
        "antal_aegteskaber": len(p.get("aegteskaber") or []),
        "antal_embeder": len(p.get("embeder") or []),
        "antal_godser": len(p.get("godser") or []),
        "koen": p.get("koen"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", required=True, type=Path)
    ap.add_argument("--b", required=True, type=Path)
    ap.add_argument("--batch", type=Path,
                    default=ROD / "work/kalibrering/batch.json")
    ap.add_argument("--ud", type=Path,
                    default=ROD / "work/kalibrering/uenigheder.md")
    a = ap.parse_args()

    batch = {b["kalibrering_id"]: b for b in json.loads(a.batch.read_text(encoding="utf-8"))}
    ua, ub = hent(a.a), hent(a.b)
    navn_a, navn_b = a.a.name, a.b.name

    enige, uenige = [], []
    for kid in sorted(set(ua) | set(ub)):
        pa, pb = profil(ua.get(kid)), profil(ub.get(kid))
        forskelle = {k: (pa.get(k), pb.get(k)) for k in set(pa) | set(pb)
                     if pa.get(k) != pb.get(k)}
        (uenige if forskelle else enige).append((kid, forskelle))

    linjer = [f"# Uenigheder: {navn_a} vs {navn_b}", "",
              f"**{len(uenige)} af {len(uenige) + len(enige)} poster** kræver din afgørelse.",
              f"De øvrige {len(enige)} er modellerne enige om og bidrager ikke til rangeringen.", "",
              "> Enighed er ikke sandhed — to modeller kan dele samme fejl. Stratum A",
              "> scores derfor stadig mod sit kendte facit, og de enige stikprøves.", "",
              "---", ""]

    for kid, forskelle in uenige:
        b = batch.get(kid, {})
        linjer += [f"## {kid} · s. {b.get('side')}", "",
                   "```", (b.get("raw_text") or "")[:1200], "```", "",
                   f"| Felt | {navn_a} | {navn_b} | Hvem har ret? |",
                   "|---|---|---|---|"]
        for felt, (va, vb) in sorted(forskelle.items()):
            linjer.append(f"| {felt} | `{va}` | `{vb}` | ? |")
        linjer += ["", "---", ""]

    a.ud.write_text("\n".join(linjer), encoding="utf-8")
    print(f"uenigheder → {a.ud}")
    print(f"  {len(uenige)} kræver afgørelse · {len(enige)} enige (springes over)")
    if uenige:
        print("\n  fordeling pr. felt:")
        taeller = {}
        for _, f in uenige:
            for k in f:
                taeller[k] = taeller.get(k, 0) + 1
        for k, n in sorted(taeller.items(), key=lambda x: -x[1]):
            print(f"    {k:20} {n}")


if __name__ == "__main__":
    main()
