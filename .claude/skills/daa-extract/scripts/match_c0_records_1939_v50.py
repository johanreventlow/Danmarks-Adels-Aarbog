#!/usr/bin/env python3
"""Deterministisk matchning af DAA 1939 v50's 41 »ægte nye« kilderecords
mod prods eksisterende 1939-personer (fase C0).

Rene funktioner, ingen I/O, ingen database, ingen model. Klassifikationen
der omgøres (``accepted_genuinely_new_source_record``) blev truffet
model-assisteret; det der omgør den skal være genkørbart og reviewbart.

Ingen af disse funktioner kobler noget. De producerer en ANBEFALING;
mennesket træffer alle 41 afgørelser.
"""
from __future__ import annotations

import difflib
import math
import re
import unicodedata
from typing import Any, Dict, List, Optional

COMPARE_VERSION = "c0_compare_v1"

# Tærskler styrer KUN hvilken anbefaling der udfyldes og hvilken rækkefølge
# posterne står i -- aldrig hvad der sker med data. Kalibreret mod BEGGE
# ankre: person 1299 (skal blive kobling) og et negativt anker (aegte_ny).
CANDIDATE_COVERAGE = 0.55
STRONG_COVERAGE = 0.85

# Under denne skeletlængde bærer teksten ikke et identitetssignal. Målt på
# det ægte grundlag: 6 af de 41 records er under 60 tegn, den korteste er
# «4. Margrethe.» -> "4margrethe" (10 tegn), som ville matche ethvert
# narrativ der nævner en Margrethe.
MIN_SKELETON_CHARS = 60

# Navne under denne længde matcher tilfældigt og må ikke bekræfte noget.
MIN_NAME_CHARS = 6

_NON_ALNUM = re.compile(r"[^0-9a-z]+")


def text_skeleton(raw: str) -> str:
    """Reducér til sammenligningsskelet: NFC, casefold, kun alfanumerisk.

    Fjerner ombrydning, bindestreger, tegnsætning og OCR-indsatte mellemrum
    i ét greb, så «Gottlie b» og «Gottlieb» er samme streng. Bruges KUN til
    sammenligning -- resultatet skrives aldrig nogen steder, og verbatim
    røres ikke."""
    if not raw:
        return ""
    folded = unicodedata.normalize("NFC", raw).casefold()
    return _NON_ALNUM.sub("", folded)


def similarity(a_skeleton: str, b_skeleton: str) -> Dict[str, Any]:
    """``coverage`` er det styrende mål; ``ratio`` er kun information.

    ``ratio()`` er symmetrisk -- ``2*M/(len(a)+len(b))`` -- så en kort record
    der ligger perfekt inde i et langt narrativ scorer nær nul. ``coverage``
    normaliserer mod den korteste af de to og er ~1.0 i netop det tilfælde.

    ``autojunk=False`` er ikke valgfrit: autojunk kasserer tegn der optræder
    i mere end 1 % af en lang streng, og på et skelet af små bogstaver ville
    det stille og roligt smide de almindelige bogstaver væk."""
    if not a_skeleton or not b_skeleton:
        return {"ratio": 0.0, "coverage": 0.0, "longest": 0, "containment": "none"}
    if a_skeleton == b_skeleton:
        return {"ratio": 1.0, "coverage": 1.0, "longest": len(a_skeleton),
                "containment": "exact"}
    containment = "none"
    if a_skeleton in b_skeleton:
        containment = "record_in_person"
    elif b_skeleton in a_skeleton:
        containment = "person_in_record"
    matcher = difflib.SequenceMatcher(None, a_skeleton, b_skeleton, autojunk=False)
    blocks = matcher.get_matching_blocks()
    matched = sum(block.size for block in blocks)
    denominator = min(len(a_skeleton), len(b_skeleton))
    return {
        "ratio": round(matcher.ratio(), 6),
        "coverage": round(matched / denominator, 6),
        "longest": max((block.size for block in blocks), default=0),
        "containment": containment,
    }


# Et ægte tekstmatch har ét langt SAMMENHÆNGENDE anker; et falsk har kun
# krummer. Uden dette krav gør min-normaliseringen korte modparter
# promiskuøse: person 1149 hedder «Henrich» (10 skelettegn), og de ti
# bogstaver findes spredt i enhver lang record -> coverage 1.0 uden at der
# er nogen som helst identitet på spil. Målt på kalibreringsrecorden skar
# kravet 60 kandidater ned til den ene rigtige.
MIN_ANCHOR_RUN = 40


def anchor_required(a_len: int, b_len: int) -> int:
    """Krævet længde på det sammenhængende anker.

    Skaleret, ikke fast: for en kort modpart kræves 80 % af dens længde, så
    ægte korte matches (fragmentstumper der står ordret) stadig kan bæres,
    mens spredt bogstavstøj falder."""
    shortest = min(a_len, b_len)
    return min(MIN_ANCHOR_RUN, math.ceil(0.8 * shortest)) if shortest else 0


def has_anchor(scores: Dict[str, Any], a_len: int, b_len: int) -> bool:
    return scores["longest"] >= anchor_required(a_len, b_len)


NGRAM = 20


def shares_ngram(a_skeleton: str, b_skeleton: str) -> bool:
    """Billigt forfilter: kræv mindst ét fælles sammenhængende n-gram, før
    den dyre sammenligning køres. Korte skeletter (< 2*NGRAM) undtages --
    ellers ville forfilteret selv skjule netop de korte records, som er dem
    der i forvejen er sværest at afgøre."""
    if len(a_skeleton) < 2 * NGRAM or len(b_skeleton) < 2 * NGRAM:
        return True
    grams = {a_skeleton[i:i + NGRAM] for i in range(len(a_skeleton) - NGRAM + 1)}
    return any(b_skeleton[i:i + NGRAM] in grams
               for i in range(len(b_skeleton) - NGRAM + 1))


def name_signal(verbatim: str, visning_navn: Optional[str]) -> bool:
    """Sandt hvis personens navn optræder i recordens tekst.

    Klammer i visning_navn (``Henrik [Reventlow]``, loaderens markering af
    udledt slægtsnavn) forsvinder i skelettet, så navnet sammenlignes som
    det læses. Navnløse personer (visning_navn er NULL i prod for flere af
    fragmenterne) giver altid falsk -- de kan ikke bekræfte noget."""
    if not visning_navn:
        return False
    name = text_skeleton(visning_navn)
    if len(name) < MIN_NAME_CHARS:
        return False
    return name in text_skeleton(verbatim)


_PAGE_NUM = re.compile(r"\d+")


def page_signal(record_pages: Optional[Dict[str, int]],
                person_side: Optional[str]) -> Optional[bool]:
    """Sandt/falsk ved sideoverlap; ``None`` når signalet ikke kan afgøres.

    ``None`` nedgraderer anbefalingen, men spærrer ikke posten -- manglende
    sidehenvisning er almindeligt i de gamle importrækker og siger intet om
    identiteten.

    Reglen er ETHVERT overlap, ikke alle-inden-for: prods sidefelter er
    ujævne (én trykt side kan dække to kildesider), så et strengere krav
    ville give falske negativer. Signalet kan kun OPGRADERE en anbefaling --
    det spærrer aldrig -- så et generøst overlap er den sikre retning."""
    if not record_pages or not person_side:
        return None
    numbers = [int(n) for n in _PAGE_NUM.findall(person_side)]
    if not numbers:
        return None
    lo, hi = record_pages["page_from"], record_pages["page_to"]
    # "574-75" betyder 574-575: et forkortet slut-tal udvides mod start-tallet.
    expanded = []
    for index, value in enumerate(numbers):
        if index > 0 and value < numbers[0]:
            prefix = str(numbers[0])[: len(str(numbers[0])) - len(str(value))]
            value = int(prefix + str(value)) if prefix else value
        expanded.append(value)
    return any(lo <= value <= hi for value in expanded)


def classify(candidates: List[Dict[str, Any]], record_skeleton_len: int) -> str:
    """Klassificér en record ud fra dens kandidatliste og dens egen længde.

    Fail-closed: enhver tvivl falder til ``gennemgang``/``for_kort``, aldrig
    til ``kobling``.

    ``for_kort`` går FORAN alt andet: en record på 10 skelettegn
    («4. Margrethe.») matcher promiskuøst, og dens kandidatliste er støj,
    ikke evidens. At kalde den ``sammenlaegning`` ville rute den til C3 som
    et fragment, den ikke er."""
    if record_skeleton_len < MIN_SKELETON_CHARS:
        return "for_kort"
    strong = [c for c in candidates if c["coverage"] >= CANDIDATE_COVERAGE
              or c["containment"] != "none"]
    if not strong:
        return "aegte_ny"
    if len(strong) > 1:
        return "sammenlaegning"
    only = strong[0]
    corroborating = sum(1 for signal in (only.get("name_signal"), only.get("page_signal"))
                        if signal is True)
    text_is_strong = only["coverage"] >= STRONG_COVERAGE or only["containment"] != "none"
    if text_is_strong and corroborating >= 1:
        return "kobling"
    return "gennemgang"
