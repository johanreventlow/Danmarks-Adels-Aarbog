"""Trin 5b 2b-ii (spec §5.2, errata §15.1): andet gennemløb over de ægteskaber, del 1 parkerede.

Deterministisk; ingen model læser teksten. Spændet er det entydige minimale ordnede ordvindue
(SQL-tvillingen er private.relation_ordered_windows). CLI'en ligger i relation_marriage_sheet.py.
"""
from __future__ import annotations

import re

from relation_persona_extract import GIFT, LETTER, MAX_NAME_WORDS, MED, UPPER

PROFILE = "relation-persona-2018-20-v2"
RULE = "aarstal-120-v1"   # errata §15.5: hvert årstal kan være et fødselsår
# Eksplicit ordklasse = SQL-klassen i private.relation_ordered_windows (ikke \w, som i PG afhænger af lc_ctype).
WORD = re.compile(r"[0-9A-Za-zÀ-ÖØ-öø-ÿ]+")
# Cifergrænser, ikke ordgrænser: »1950erne« tæller som 1950 (review 2026-10-18).
YEAR = re.compile(r"(?<![0-9])(1[0-9]{3}|20[0-9]{2})(?![0-9])")   # = SQL-tvillingen i write_relation_person_create


def _words(s: str):
    return [(m.start(), m.end(), m.group(0).lower()) for m in WORD.finditer(s)]


def windows(text: str, raw: str) -> list[tuple[int, int]]:
    """Alle minimale vinduer i text, der rummer raw's ord i rækkefølge (0-baseret, eksklusiv slut)."""
    tw, rw = _words(text), [w for _, _, w in _words(raw)]
    if not tw or not rw:
        return []
    found: dict[int, int] = {}                     # slutindeks -> senest start
    for i, (_, _, w) in enumerate(tw):
        if w != rw[0]:
            continue
        j, k = i, 1
        while k < len(rw):
            j += 1
            if j >= len(tw):
                break
            if tw[j][2] == rw[k]:
                k += 1
        if k == len(rw):
            found[j] = i
    return sorted((tw[s][0], tw[e][1]) for e, s in found.items())


PARTICLES = {"von", "de", "af", "du", "la", "van", "zu", "der", "den"}
CAP = re.compile(r"[A-ZÆØÅÀ-Þ][0-9A-Za-zÀ-ÖØ-öø-ÿ'’‑-]*")
STOP_TITLE = re.compile(r"\b(datter|søn)\b", re.IGNORECASE)
TOKEN = re.compile(r"\S+")


def _start(seg: str) -> tuple[int, bool]:
    m = MED.search(seg)
    if m:
        return m.end(), False
    g = GIFT.match(seg)
    if g:
        return g.end(), True
    return 0, False


def _name(seg: str):
    """Navnet efter »med« (eller efter »Gift« + tal): titler, små ord og forkortelser (»Dbg.«) springes over;
    navnet er det sammenhængende løb af ord med versal, med partikler (von, de, af …) imellem, og det slutter
    ved første andet ord eller ved komma/punktum. »datter«/»søn« før navnet ⇒ intet forslag (spec §5.2 pkt. 3,
    plan-ruling Task 8; mennesket verificerer navnet på arket)."""
    start, after_gift = _start(seg)
    toks = [(m.start(), m.end(), m.group(0)) for m in TOKEN.finditer(seg, start)]
    k = 0
    while k < len(toks):                                   # spring titler/forkortelser over
        word = toks[k][2]
        bare = word.rstrip(",.;:")
        if CAP.fullmatch(bare) and not (word.endswith(".") and len(bare) <= 4):
            break
        k += 1
    if k == len(toks):
        return None
    titel = seg[start:toks[k][0]]
    if any(ch in titel for ch in ";()*†") or STOP_TITLE.search(titel):
        return None
    if after_gift and not re.fullmatch(r"[\s\d.,°/-]*", titel):
        return None
    if not after_gift and re.search(r"\d", titel):
        return None
    nf, nt, words = toks[k][0], None, 0
    while k < len(toks):
        s, e, word = toks[k]
        bare = word.rstrip(",.;:")
        nxt = toks[k + 1][2].rstrip(",.;:") if k + 1 < len(toks) else ""
        if CAP.fullmatch(bare) or (bare in PARTICLES and nt is not None and CAP.fullmatch(nxt) and bare == word):
            nt, words = s + len(bare), words + 1
            if bare != word:                               # komma/punktum afslutter navnet
                break
            k += 1
        else:
            break
    if nt is None or words > MAX_NAME_WORDS or not LETTER.search(seg[nf:nt]):
        return None
    return nf, nt


def _shares_half(name: str, partner: str | None) -> bool:
    a = {w for _, _, w in _words(name)}
    b = {w for _, _, w in _words(partner or "")}
    return bool(a) and 2 * len(a & b) >= len(a)


def propose(row: dict, cutoff: int) -> dict:
    """Forslag for én række: tok ∈ S/D/N/I/U med grund og (ved S/D/N) klausul-relative spænd."""
    if not row.get("principal_ok") or row.get("principal_person_id") is None:
        return {"tok": "U", "reason": "ingen_hovedperson"}
    if row["supporting_count"] != 1 or len(row["clauses"]) != 1:
        return {"tok": "U", "reason": "flere_klausuler"}
    if row.get("marriage_ordinal") is None:
        return {"tok": "U", "reason": "intet_nummer"}
    text, raw = row["clauses"][0]["verbatim_text"], row.get("raw") or ""
    w = windows(text, raw)
    if len(w) != 1:
        return {"tok": "U", "reason": "intet_vindue" if not w else "tvetydigt_vindue"}
    sf, st = w[0]
    seg = text[sf:st]
    nm = _name(seg)
    if nm is None:
        # I kun når der slet ingen versal er efter »Gift/med« (bogen nævner ikke ægtefællen); ellers er
        # navnet der, men reglen kan ikke isolere det ⇒ U.
        if UPPER.search(seg, _start(seg)[0]) is None:
            return {"tok": "I", "reason": "intet_navn", "span_from": sf, "span_to": st}
        return {"tok": "U", "reason": "navn_uklart"}
    nf, nt = sf + nm[0], sf + nm[1]
    years = sorted({int(y) for y in YEAR.findall(text)})
    out = {"span_from": sf, "span_to": st, "name_from": nf, "name_to": nt, "clause_years": years}
    hits = {p["person_id"] for p in row.get("principal_partners", []) if _shares_half(text[nf:nt], p.get("navn"))}
    if len(hits) == 1:
        return {**out, "tok": "S", "reason": "partnermatch", "partner_person_id": hits.pop()}
    if years and max(years) <= cutoff:
        return {**out, "tok": "D", "reason": "aldersregel"}
    return {**out, "tok": "N", "reason": "kan_ikke_erklaeres_afdoed"}
