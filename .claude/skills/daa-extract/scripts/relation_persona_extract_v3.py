"""Trin 5b 2b-ii runde 2 (spec §17.4-17.5): navneregel v3, partnersammenligning og P-forslag.

Deterministisk; ingen model læser teksten. Ordvinduet og årstallene er v2's (SQL-tvillingerne er uændrede).
"""
from __future__ import annotations

import re

from relation_persona_extract import LETTER, MAX_NAME_WORDS, UPPER
from relation_persona_extract_v2 import CAP, STOP_TITLE, TOKEN, WORD, YEAR, _shares_half, _start, _words, windows
from relation_persona_extract_v2 import PARTICLES as _PARTICLES_V2

PROFILE = "relation-persona-2018-20-v3"
RULE = "aarstal-120-v1"
# Lukket titelliste (spec §17.5) = SQL-tvillingen private.relation_title_words(); test_title_words_match_schema låser dem.
TITLE_WORDS = ("baron", "baronesse", "friherre", "friherreinde", "greve", "grevinde", "hertug", "hertuginde",
               "komtesse", "prins", "prinsesse")
TITLE_PREFIXES = ("rigs", "lens")
PARTICLES = _PARTICLES_V2 | {"und", "zu", "dem", "genannt"}
NOT_NAME = {"til"}   # »til <gods>« ≠ navn (beslutning 2026-10-03); udløser ikke navn_afkortet
LOWER_WORD = re.compile(r"[a-zæøåà-öø-ÿ]+(?:-[a-zæøåà-öø-ÿ]+)*")   # også »rigs-grevinde«; ».,;:« strippes først


class NameOverrideError(ValueError):
    """Arkets navn: står ikke ordret og entydigt fra navnestarten inden for vinduet."""


# #244 (spec §5): bogens eget ægteskabsnummer forrest i påstanden (»g. 2°«/»gift 2°«). Eksplicitte klasser, ikke \s/\d
# (som vinduet). SQL-tvilling: private.relation_book_ordinal; fælles liste tests/fixtures/relation-book-ordinal.json.
BOOK_ORDINAL = re.compile(r"^[ \t]*(g[.]|gift)[ \t]*([0-9]{1,3})[ \t]*[°º]")


def book_ordinal(raw: str | None) -> int | None:
    m = BOOK_ORDINAL.match((raw or "").lower())
    return int(m.group(2)) if m else None

def is_title(word: str) -> bool:
    w = word.lower()
    return w in TITLE_WORDS or any(w.startswith(p) and w[len(p):] in TITLE_WORDS for p in TITLE_PREFIXES)


def title_free(name: str) -> bool:
    """Sikring ved D (spec §17.5): hvert ord har versal eller er en partikel, og intet ord er en titel.
    Ordene deles som i SQL-tvillingen (på alle ikke-ordtegn), så »Rigs-Grevinde« fanges allerede på arket."""
    for m in WORD.finditer(name):
        w = m.group(0)
        if is_title(w) or not (CAP.fullmatch(w) or w.lower() in PARTICLES):
            return False
    return True


def _links_to_name(toks, k: int) -> bool:
    """Partikler og titler inde i navnet: kæden fra k skal ende i et ord med versal. Komma/punktum må ikke stå
    inde i kæden, men gerne efter slutordet (hovedløkken afslutter navnet dér)."""
    j = k
    while j < len(toks):
        word = toks[j][2]
        bare = word.rstrip(",.;:")
        if bare.lower() in PARTICLES or is_title(bare):
            if bare != word:
                return False
            j += 1
            continue
        return bool(CAP.fullmatch(bare))
    return False


def _truncated(text: str, nt: int, st: int) -> bool:
    """Reglen stoppede foran et ulistet småord, som efterfølges af et versalord (fx en ukendt titel inde i
    navnet). Sådan et navn er afkortet og må ikke blive D (spec §17.9)."""
    m = re.match(r"\s+(\S+)\s+(\S+)", text[nt:st])
    if not m:
        return False
    w, nxt = m.group(1).rstrip(",.;:"), m.group(2).rstrip(",.;:")
    return bool(LOWER_WORD.fullmatch(w)) and w not in PARTICLES and w not in NOT_NAME and bool(CAP.fullmatch(nxt))


def _name(seg: str):
    """Som v2, men navneløbet fortsætter over partikel- og titelkæder, der ender i et versalord."""
    start, after_gift = _start(seg)
    toks = [(m.start(), m.end(), m.group(0)) for m in TOKEN.finditer(seg, start)]
    k = 0
    while k < len(toks):                                   # spring titler/forkortelser over (som v2)
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
    if not after_gift and any(ch.isdigit() for ch in titel):
        return None
    nf, nt, words = toks[k][0], None, 0
    while k < len(toks):
        s, _e, word = toks[k]
        bare = word.rstrip(",.;:")
        if CAP.fullmatch(bare):
            nt, words = s + len(bare), words + 1
        elif nt is not None and bare == word and _links_to_name(toks, k):
            nt = s + len(bare)
        else:
            break
        if bare != word:                                   # komma/punktum afslutter navnet
            break
        k += 1
    if nt is None or words > MAX_NAME_WORDS or not LETTER.search(seg[nf:nt]):
        return None
    return nf, nt


def _core(name: str | None) -> list[str]:
    return [w for _, _, w in _words(name or "") if not w.isdigit() and w not in PARTICLES and not is_title(w)]


def partner_hit(name: str, partner_name: str | None) -> bool:
    """Træf ved S: efternavnet (sidste kerneord) passer, mindst ét kerneord mere er fælles, og mindst halvdelen
    af navnets kerneord er fælles. Efternavnet alene er ikke nok (final review F2)."""
    a, b = _core(name), _core(partner_name)
    if not a or not b or a[-1] != b[-1]:
        return False
    sa, shared = set(a), set(a) & set(b)
    return len(shared) >= 2 and 2 * len(shared) >= len(sa)


def partner_similar(name: str, partner_name: str | None) -> bool:
    """Løst dubletværn før D/N og P (final review F2): v2's halvdelsregel eller blot ét fælles kerneord."""
    return _shares_half(name, partner_name) or bool(set(_core(name)) & set(_core(partner_name)))


def propose(row: dict, cutoff: int, name_override: str | None = None) -> dict:
    """Forslag for én række. En navn:-rettelse kræver en navnestart; ellers NameOverrideError (spec §17.6),
    også ved de tidlige U og ved I, så rettelsen aldrig ignoreres tavst."""
    p = _propose(row, cutoff, name_override)
    if name_override is not None and "name_from" not in p:
        raise NameOverrideError("ingen navnestart")
    return p


def _propose(row: dict, cutoff: int, name_override: str | None) -> dict:
    if not row.get("principal_ok") or row.get("principal_person_id") is None:
        return {"tok": "U", "reason": "ingen_hovedperson"}
    if row["supporting_count"] != 1 or len(row["clauses"]) != 1:
        return {"tok": "U", "reason": "flere_klausuler"}
    if row.get("marriage_ordinal") is None:
        return {"tok": "U", "reason": "intet_nummer"}
    bo = book_ordinal(row.get("raw"))
    if bo is not None and bo != row["marriage_ordinal"]:
        return {"tok": "U", "reason": "nummer_modsiger_bog"}
    text, raw = row["clauses"][0]["verbatim_text"], row.get("raw") or ""
    w = windows(text, raw)
    if len(w) != 1:
        return {"tok": "U", "reason": "intet_vindue" if not w else "tvetydigt_vindue"}
    sf, st = w[0]
    seg = text[sf:st]
    nm = _name(seg)
    if nm is None:
        if UPPER.search(seg, _start(seg)[0]) is None:
            return {"tok": "I", "reason": "intet_navn", "span_from": sf, "span_to": st}
        return {"tok": "U", "reason": "navn_uklart"}
    nf, nt = sf + nm[0], sf + nm[1]
    rule_name, basis = text[nf:nt], "rule"
    if name_override is not None:
        o = name_override
        end = nf + len(o)
        if (o != o.strip() or not LETTER.search(o) or not text.startswith(o, nf)
                or end > st or text.count(o) != 1
                or not o[-1].isalpha() or (end < len(text) and text[end].isalnum())):   # helt ord, ingen tegnsætning
            raise NameOverrideError("navn")
        nt, basis = nf + len(o), "sheet"
    name = text[nf:nt]
    years = sorted({int(y) for y in YEAR.findall(text)})
    out = {"span_from": sf, "span_to": st, "name_from": nf, "name_to": nt, "clause_years": years, "name_basis": basis}
    hits = [p for p in row.get("principal_partners", []) if partner_hit(name, p.get("navn"))]
    ids = {p["person_id"] for p in hits}
    if len(ids) == 1:
        return {**out, "tok": "S", "reason": "partnermatch", "partner_person_id": hits[0]["person_id"],
                "partner_ordinal": hits[0].get("ordinal")}
    if ids:
        same = {p["person_id"] for p in hits if p.get("ordinal") == row["marriage_ordinal"]}
        if len(same) == 1:
            return {**out, "tok": "S", "reason": "partnermatch_nummer", "partner_person_id": same.pop(),
                    "partner_ordinal": row["marriage_ordinal"]}
        return {**out, "tok": "U", "reason": "flere_partnere"}
    if any(partner_similar(n, p.get("navn")) for n in {name, rule_name} for p in row.get("principal_partners", [])):
        return {**out, "tok": "U", "reason": "partner_ligner"}
    if not title_free(name):
        return {**out, "tok": "U", "reason": "titel_i_navn"}
    if basis == "rule" and _truncated(text, nt, st):
        return {**out, "tok": "U", "reason": "navn_afkortet"}
    if years and max(years) <= cutoff:
        return {**out, "tok": "D", "reason": "aldersregel"}
    return {**out, "tok": "N", "reason": "kan_ikke_erklaeres_afdoed"}


def propose_redecide(prow: dict, cutoff: int) -> dict:
    """P-linjen (spec §17.6): en new_person_needed uden deceased; D kun efter aldersreglen og uden partnertræf."""
    if not prow.get("clause_is_current"):
        return {"tok": "U", "reason": "klausul_afloest"}
    if prow.get("principal_person_id") is None:
        return {"tok": "U", "reason": "ingen_hovedperson"}
    if prow.get("marriage_ordinal") is None:
        return {"tok": "U", "reason": "intet_nummer"}
    name = prow.get("name_text") or ""
    if any(partner_similar(name, p.get("navn")) for p in prow.get("principal_partners", [])):
        return {"tok": "U", "reason": "partner_findes"}
    if not title_free(name):
        return {"tok": "U", "reason": "titel_i_navn"}
    years = sorted({int(y) for y in YEAR.findall(prow.get("clause_text") or "")})
    if years and max(years) <= cutoff:
        return {"tok": "D", "reason": "aldersregel", "clause_years": years}
    return {"tok": "N", "reason": "kan_ikke_erklaeres_afdoed", "clause_years": years}
