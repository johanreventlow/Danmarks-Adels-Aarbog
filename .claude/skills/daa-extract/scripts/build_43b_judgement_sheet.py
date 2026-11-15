#!/usr/bin/env python3
"""Bedømmelsesark til 4.3b (plan Task 4) — som TOKEN-FIL, ikke som JSON.

Projektets egen lære: et menneske skal kunne arbejde i filen, ikke læse den. Ét
token pr. linje, forudfyldt hvor maskinen kan afgøre det, så mennesket kun tager
stilling til det, kun et menneske kan.

FORUDFYLDT (maskinelt målt):
  - klausulbinding: findes den citerede ordinal i posten?
  - ordrethed: står værdien ordret i den citerede klausul?

SKAL UDFYLDES AF MENNESKET:
  - S (sandhed): er påstanden sand ifølge teksten?  J / N
  - de manglende udtræk pr. post (grundlaget for dækningsmålet)

Filen indeholder biografitekst og skrives 0600 uden for repoet.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from private_io import write_private_new  # noqa: E402
from evidence_runner import sha256_text


def vaerdi_tekst(value) -> str:
    if isinstance(value, dict):
        return str(value.get("raw", ""))
    return str(value)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", required=True, help="bedoemmelsesark-*.json fra kørslen")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    ark = json.loads(Path(args.sheet).read_text(encoding="utf-8"))
    linjer: list[str] = []
    add = linjer.append

    add("# BEDØMMELSE AF 4.3b, BUNDT 1")
    add("#")
    add("# Sæt J eller N i S-kolonnen for hvert claim. Alt andet er forudfyldt.")
    add("#   S = er påstanden SAND ifølge klausulteksten?")
    add("#   B = citerer claimet den rigtige klausul?   (forudfyldt maskinelt)")
    add("#   O = står værdien ORDRET i klausulen?       (forudfyldt maskinelt)")
    add("#")
    add("# Udfyld også MANGLER-linjerne: hvilke udsagn i posten burde have givet")
    add("# et claim, men gjorde ikke? Skriv ét pr. linje. Det er grundlaget for")
    add("# dækningsmålet — og udeladelser er det, der afgør, om laget kan bære")
    add("# en senere promotion.")
    add("#")
    add("# Gem filen når du er færdig. Intet andet skal ændres.")
    add("")

    i_alt = bundet = ordret = 0
    for post in ark:
        add("=" * 78)
        add(f"POST {post['record_key']}   ({len(post['claims'])} claims, "
            f"{len(post['klausuler'])} klausuler)")
        add("=" * 78)
        add("")
        for kl in post["klausuler"]:
            add(f"  [{kl['ordinal']}] {kl['tekst']}")
        add("")

        if not post["claims"]:
            add("  (modellen udtrak intet fra denne post)")
            add("")
        for n, c in enumerate(post["claims"], 1):
            ords = c.get("clause_ordinals", [])
            kl_tekster = {k["ordinal"]: k["tekst"] for k in post["klausuler"]}
            b = "J" if all(o in kl_tekster for o in ords) else "N"
            vt = vaerdi_tekst(c.get("value"))
            o = "J" if any(vt and vt in kl_tekster.get(x, "") for x in ords) else "N"
            i_alt += 1
            bundet += b == "J"
            ordret += o == "J"
            add(f"  --- claim {n} ---")
            add(f"  citerer klausul : {ords}")
            add(f"  prædikat        : {c.get('predicate')}")
            add(f"  værdi           : {vt}")
            add(f"  B (binding)     : {b}     <- forudfyldt")
            add(f"  O (ordrethed)   : {o}     <- forudfyldt")
            add(f"  S (sandhed)     : _     <- UDFYLD: J eller N")
            add("")
        add(f"  MANGLER i {post['record_key']} (ét udsagn pr. linje, slet linjen hvis intet mangler):")
        add("  - ")
        add("")

    add("=" * 78)
    add("FORUDFYLDT OPSUMMERING (maskinelt)")
    add("=" * 78)
    add(f"  claims i alt        : {i_alt}")
    add(f"  korrekt binding     : {bundet}/{i_alt}"
        + (f"  ({100*bundet//i_alt} %)" if i_alt else ""))
    add(f"  ordret gengivet     : {ordret}/{i_alt}"
        + (f"  ({100*ordret//i_alt} %)" if i_alt else ""))
    add("  sandhed             : afventer din bedømmelse")
    add("  dækning             : afventer MANGLER-linjerne")

    out = Path(args.out)
    # Udfyldbart bedømmelsesark: et eksisterende (måske udfyldt) ark overskrives aldrig.
    write_private_new(out, "\n".join(linjer) + "\n")
    print(f"ark skrevet: {out}")
    print(f"  {i_alt} claims at bedømme fordelt på {len(ark)} poster")
    print(f"  forudfyldt: binding {bundet}/{i_alt}, ordrethed {ordret}/{i_alt}")
    print(f"  sha256: {sha256_text(out.read_text(encoding='utf-8'))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
