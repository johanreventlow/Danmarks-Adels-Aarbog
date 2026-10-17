"""Trin 5b 2b-ii (spec §5.2, errata §15.1): andet gennemløb over de ægteskaber, del 1 parkerede.

Deterministisk; ingen model læser teksten. Spændet er det entydige minimale ordnede ordvindue
(SQL-tvillingen er private.relation_ordered_windows). CLI'en ligger i relation_marriage_sheet.py.
"""
from __future__ import annotations

import re

from relation_persona_extract import GIFT, LETTER, MAX_NAME_WORDS, MAX_TITLE_WORDS, MED, NAME_END, UPPER

PROFILE = "relation-persona-2018-20-v2"
RULE = "vielsesaar-120-v1"
# Eksplicit ordklasse = SQL-klassen i private.relation_ordered_windows (ikke \w, som i PG afhænger af lc_ctype).
WORD = re.compile(r"[0-9A-Za-zÀ-ÖØ-öø-ÿ]+")
YEAR = re.compile(r"\b(1[0-9]{3}|20[0-9]{2})\b")   # = SQL '\m(…)\M' i write_relation_person_create


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


def _name(seg: str):
    """Del 1's navneregel; uden »med« må navnet følge efter »Gift« og et løb af tal og tegnsætning (spec §5.2 pkt. 3)."""
    m = MED.search(seg)
    g = GIFT.match(seg)
    if m:
        start, after_gift = m.end(), False
    elif g:
        start, after_gift = g.end(), True
    else:
        start, after_gift = 0, False
    u = UPPER.search(seg, start)
    if u is None:
        return None
    titel = seg[start:u.start()]
    if after_gift:
        if not re.fullmatch(r"[\s\d.,°/-]*", titel):
            return None
    elif any(ch in titel for ch in ";()*†") or re.search(r"\d", titel) or len(titel.split()) > MAX_TITLE_WORDS:
        return None
    end_m = NAME_END.search(seg, u.start())
    end = end_m.start() if end_m else len(seg)
    name = seg[u.start():end].rstrip()
    if not LETTER.search(name) or len(name.split()) > MAX_NAME_WORDS:
        return None
    return u.start(), u.start() + len(name)


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
    nm = _name(text[sf:st])
    if nm is None:
        return {"tok": "I", "reason": "intet_navn", "span_from": sf, "span_to": st}
    nf, nt = sf + nm[0], sf + nm[1]
    years = sorted({int(y) for y in YEAR.findall(text)})
    out = {"span_from": sf, "span_to": st, "name_from": nf, "name_to": nt, "clause_years": years}
    hits = {p["person_id"] for p in row.get("principal_partners", []) if _shares_half(text[nf:nt], p.get("navn"))}
    if len(hits) == 1:
        return {**out, "tok": "S", "reason": "partnermatch", "partner_person_id": hits.pop()}
    if years and max(years) <= cutoff:
        return {**out, "tok": "D", "reason": "aldersregel"}
    return {**out, "tok": "N", "reason": "kan_ikke_erklaeres_afdoed"}
