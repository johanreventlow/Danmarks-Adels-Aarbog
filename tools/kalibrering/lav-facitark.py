#!/usr/bin/env python3
"""Lav et LÆSBART facitark — prosaen står i arket, så bogen ikke skal slås op.

Den første facit-skabelon var en JSON med bare et nummer pr. post. Den var
ubrugelig i praksis: man kunne ikke se hvem posten handlede om, og skulle slå
op i årbogen for hver eneste linje.

Indsigten der gør det unødvendigt: **kalibreringen tester om modellen udtrækker
korrekt FRA EN GIVEN TEKST** — ikke om OCR'en er rigtig. Prosaen er derfor
facit-grundlaget, og den har vi allerede. Bogen skal kun frem hvis man
mistænker at selve teksten er forkert segmenteret.

Arket forudfylder alt der kan udledes maskinelt, så mennesket kun udfylder det
der kræver læsning.

Kør:
  python3 tools/kalibrering/lav-facitark.py
"""
import json
from pathlib import Path

ROD = Path(__file__).resolve().parents[2]
UD = ROD / "work/kalibrering"


def main():
    batch = json.loads((UD / "batch.json").read_text(encoding="utf-8"))
    prod = {p["nr"]: p for p in json.loads(
        (ROD / "work_1939_stamtavle/prod_dump_1939_2026-07-28.json").read_text(encoding="utf-8"))}

    linjer = ["# Facitark — kalibrering af DAA 1939-udtræk", "",
              "Prosaen står under hver post. **Du behøver ikke slå op i bogen** —",
              "kalibreringen tester om modellen udtrækker korrekt *fra denne tekst*.",
              "Slå kun op hvis du mistænker at teksten selv er forkert klippet.", "",
              "Udfyld kun felter markeret `?`. Resten er udledt maskinelt.", "",
              "---", ""]

    for b in batch:
        n = b["nr"]
        p = prod.get(n, {})
        navn = p.get("navn") or "(slettet post — navn ikke i basen)"
        er_omtale = "**ja** _(kendt: posten er gravsat som omtale)_" \
            if b["stratum"] == "A_omtale" else "?"
        # Antal ægteskaber kan tælles i det gamle udtræk — som HINT, ikke facit
        hint_aegt = len(p.get("matches") or []) and "" or ""
        linjer += [
            f"## {b['kalibrering_id']} · s. {b['side']} · {navn}", "",
            "```",
            b["raw_text"][:1600] + ("…" if len(b["raw_text"]) > 1600 else ""),
            "```", "",
            "| Spørgsmål | Svar |",
            "|---|---|",
            f"| Er posten kun en **omtale** inde i en anden persons tekst? | {er_omtale} |",
            "| Hvor mange **ægteskaber** nævnes? | ? |",
            "| Har ægtefællen **datoer** i teksten (født/død/viet)? | ? |",
            "| Hvor mange **embeder** nævnes? (amtmand, kammerherre, oberst …) | ? |",
            "| Hvor mange **godser** nævnes? | ? |",
            "| Personens **køn** | ? |",
            "", "---", "",
        ]

    (UD / "facitark.md").write_text("\n".join(linjer), encoding="utf-8")
    kraever_svar = sum(1 for b in batch if b["stratum"] != "A_omtale")
    print(f"facitark → {UD}/facitark.md")
    print(f"  {len(batch)} poster · {kraever_svar} kræver læsning "
          f"({len(batch) - kraever_svar} er forudfyldt)")
    print("  prosaen står i arket — bogen skal ikke slås op")


if __name__ == "__main__":
    main()
