"""Kontrollér en eksport fra 1939-tekstfladen mod kilden.

Fladens egen byte-gate beskytter kildeteksten. Denne kontrol er noget andet: den
ser på om *markeringerne* hænger sammen — og den findes, fordi en menneskelig
gennemgang af 611 skæringer og 131 udeladelser har fejlmåder, ingen gate fanger.
To af dem er observeret i praksis:

* en udeladelse der begynder ét tegn efter et linjeskift, så overskriftens første
  bogstav bliver stående (fundet 76 gange i én omgang, alle utilsigtede)
* et trykt postnummer i tekst uden ejer, som ingen har skåret

Kontrollen dømmer ikke om indhold. Den peger på steder hvor formen afviger, og
skelner udtrykkeligt mellem afvigelser og artefakter: en skæring inde i en
udeladelse er et fund, medmindre den står på udeladelsens sidste tegn — dér er
den grænsen mellem den udeladte overskrift og posten efter.

Brug:
    python check_graenseflade_export.py <eksport.json> --calamari <kilde.txt> \
        [--boundaries <menneskeark-graenser.html>] [--forrige <tidligere.json>]
"""

from __future__ import annotations

import argparse
import bisect
import json
import re
from pathlib import Path

PAGE_RE = re.compile(r"^### PAGE (\d+) ###$", re.M)
PRINTED_RE = re.compile(r"^\s*\d{1,3}\.\s+\S", re.M)
CALAMARI_R6_TO_PDF_V1 = (
    (1, 496), (5, 500), (10, 505), (15, 510), (20, 515),
    (25, 520), (30, 525), (40, 535), (45, 540), (50, 545),
    (53, 550), (58, 555), (59, 571), (60, 572), (61, 573),
    (62, 574), (63, 575), (68, 580), (73, 585),
    (78, 590), (83, 595), (84, 596), (85, 597), (86, 598),
)


def pdf_page(source_page: int) -> int:
    for anchor, page in CALAMARI_R6_TO_PDF_V1:
        if source_page == anchor:
            return page
    for (left, left_pdf), (right, right_pdf) in zip(
        CALAMARI_R6_TO_PDF_V1, CALAMARI_R6_TO_PDF_V1[1:]
    ):
        if left < source_page < right:
            numerator = (source_page - left) * (right_pdf - left_pdf)
            denominator = right - left
            return left_pdf + (2 * numerator + denominator) // (2 * denominator)
    raise ValueError(f"kildeside {source_page} findes ikke i sidekortet")


class Fund:
    def __init__(self) -> None:
        self.linjer: list[str] = []
        self.antal_fund = 0

    def ok(self, navn: str, detalje: str = "") -> None:
        self.linjer.append(f"OK    {navn}{f' — {detalje}' if detalje else ''}")

    def fund(self, navn: str, detalje: str = "") -> None:
        self.antal_fund += 1
        self.linjer.append(f"FUND  {navn}{f' — {detalje}' if detalje else ''}")

    def note(self, tekst: str) -> None:
        self.linjer.append(f"      {tekst}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("eksport", type=Path)
    parser.add_argument("--calamari", type=Path, required=True)
    parser.add_argument("--boundaries", type=Path,
                        help="menneskeark-graenser HTML, til hul-dækning")
    parser.add_argument("--forrige", type=Path, help="tidligere eksport, til diff")
    args = parser.parse_args()

    text = args.calamari.read_text(encoding="utf-8")
    data = json.loads(args.eksport.read_text(encoding="utf-8"))
    cuts = sorted({item["char_offset"] for item in data["skaeringer"]})
    bruger = sorted({item["char_offset"] for item in data["skaeringer"]
                     if item.get("oprindelse") == "bruger"})
    omraader = sorted((u["char_from"], u["char_to"]) for u in data["udeladelser"])

    page_starts = [(m.start(), int(m.group(1))) for m in PAGE_RE.finditer(text)]
    offsets = [start for start, _ in page_starts]

    def side(offset: int) -> int:
        index = bisect.bisect_right(offsets, offset) - 1
        return pdf_page(page_starts[index][1]) if index >= 0 else 0

    r = Fund()
    r.note(f"{len(cuts)} skæringer ({len(bruger)} fra mennesket) · "
           f"{len(omraader)} udeladelser · "
           f"{len(data['sider']['gennemgaaet'])} af {data['sider']['i_alt']} sider")

    # 1. Udeladelse der begynder ét tegn for sent — overskriftens første bogstav
    #    bliver stående. Observeret 76 gange; aldrig med vilje.
    skaeve = [a for a, _ in omraader
              if a >= 2 and text[a - 2] == "\n" and text[a - 1].strip()]
    if skaeve:
        r.fund("udeladelser der begynder ét tegn efter et linjeskift", str(len(skaeve)))
        for a in skaeve[:8]:
            r.note(f"s.{side(a)}: efterlader {text[a - 1]!r} → {text[a:a + 42]!r}")
    else:
        r.ok("ingen udeladelse begynder ét tegn for sent")

    # 2. Overlap og tomme områder.
    overlap = [(b1, a2) for (a1, b1), (a2, b2) in zip(omraader, omraader[1:]) if a2 < b1]
    tomme = [(a, b) for a, b in omraader if b <= a]
    if overlap or tomme:
        r.fund("overlappende eller tomme udeladelser", f"{len(overlap)} / {len(tomme)}")
    else:
        r.ok("ingen overlappende eller tomme udeladelser")

    # 3. Menneskesatte skæringer skal stå ved et linjeskift. De forudsatte gør
    #    det ikke nødvendigvis — deres kanoniske position ligger ved linjens slut.
    midt = [o for o in bruger if o > 0 and text[o - 1] != "\n" and text[o] != "\n"]
    if midt:
        r.fund("menneskesatte skæringer midt i en linje", str(len(midt)))
        for o in midt[:6]:
            r.note(f"s.{side(o)}: {text[max(0, o - 30):o]!r} ▸ {text[o:o + 30]!r}")
    else:
        r.ok(f"alle {len(bruger)} menneskesatte skæringer står ved en linjegrænse")

    # 4. Skæring inde i en udeladelse. Står den på udeladelsens sidste tegn, er
    #    den grænsen mellem overskriften og posten efter — ikke et fund.
    inde, artefakt = [], 0
    for offset in cuts:
        for a, b in omraader:
            if a < offset < b:
                if b - offset == 1:
                    artefakt += 1
                else:
                    inde.append(offset)
                break
    if inde:
        r.fund("skæringer inde i udeladt tekst", str(len(inde)))
        for o in inde[:6]:
            r.note(f"s.{side(o)}: {text[o:text.find(chr(10), o)][:52]!r}")
    else:
        r.ok("ingen skæring ligger inde i udeladt tekst",
             f"{artefakt} står på udeladelsens kant (grænsen efter en overskrift)")

    # 5. Bogens egne trykte numre i tekst uden ejer: kildens kvittering for at
    #    der mangler en post. Kræver hul-modellen.
    if args.boundaries:
        html = args.boundaries.read_text(encoding="utf-8")
        start = html.index("const DATA=") + len("const DATA=")
        model, _ = json.JSONDecoder().raw_decode(html[start:])
        cut_set = set(cuts)

        def daekket(offset: int) -> bool:
            return (any(abs(offset - c) <= 2 for c in cut_set)
                    or any(a <= offset < b for a, b in omraader))

        i_alt = mangler = 0
        for boundary in model["boundaries"]:
            gap = boundary.get("gap") or {}
            if not isinstance(gap.get("char_from"), int):
                continue
            a, b = gap["char_from"], gap["char_to"]
            for match in PRINTED_RE.finditer(text[a:b]):
                i_alt += 1
                if not daekket(a + match.start()):
                    mangler += 1
                    if mangler <= 6:
                        offset = a + match.start()
                        r.note(f"s.{side(offset)}: "
                               f"{text[offset:offset + 46].strip()!r}")
        if mangler:
            r.fund("trykte postnumre i ejerløs tekst uden skæring",
                   f"{mangler} af {i_alt}")
        else:
            r.ok("alle trykte postnumre i ejerløs tekst er skåret eller udeladt",
                 f"{i_alt} af {i_alt}")

    # 6. Diff mod forrige eksport.
    if args.forrige:
        tidligere = json.loads(args.forrige.read_text(encoding="utf-8"))
        gamle = {item["char_offset"] for item in tidligere["skaeringer"]}
        gamle_ud = {(u["char_from"], u["char_to"]) for u in tidligere["udeladelser"]}
        nye = sorted(set(cuts) - gamle)
        r.note(f"siden forrige: +{len(nye)} skæringer, "
               f"-{len(gamle - set(cuts))} · "
               f"+{len(set(omraader) - gamle_ud)} udeladelser, "
               f"-{len(gamle_ud - set(omraader))}")
        # En skæring siger "her begynder en post", så vis linjen EFTER den. Står
        # skæringen ved en linjes slut, er linjen før den et andet stykke tekst —
        # en tidligere udgave viste den og fik fem gyldige skæringer nederst på en
        # side til at ligne afklip midt i en sætning.
        for offset in nye[:20]:
            rest = text[offset:].lstrip("\n")
            foerste = rest.split("\n", 1)[0]
            r.note(f"  ny skæring s.{side(offset)} ▸ {foerste[:52]!r}")

    print("\n".join(r.linjer))
    print(f"\n{r.antal_fund} fund")
    return 1 if r.antal_fund else 0


if __name__ == "__main__":
    raise SystemExit(main())
