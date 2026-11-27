#!/usr/bin/env python3
"""Forslagsark og plan-fil for godsernes sammenlægning (#471, fase 1).

Læser `estate` og godsernes relationer fra en prod-kopi (kun læsning), foreslår grupper af rækker,
der er samme gård eller samme majorat (grevskab/baroni/stamhus), og skriver

* et HTML-ark til projektejeren (UDEN FOR repo'et), hvor hver gruppe har et nummer og et eller flere valg, og
* en maskinlæsbar plan-fil (`plan.forslag.json`) med de forvalgte operationer i Task 10's format plus alle
  alternativer, så planen kan rettes efter projektejerens svar.

Ingen persondata: værktøjet læser aldrig personnavne. Det eneste opslag i `person` er `levende`-flaget, og det
returnerer kun gods-id'er (se SQL_LEVENDE_EJER). Arket og planen indeholder gods-, relations- og medie-id'er,
godsnavne, perioder og udgaver — aldrig hvem.

Brug:
    python3 -I tools/godser-471/forslag.py --db <prod-kopi> --ark <sti uden for repo>.html \
        --plan tools/godser-471/plan.forslag.json

Beslutningen bag: docs/decisions.md »BESLUTTET: godserne ryddes op i to niveauer — majorat og gård (#471)«.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

MAJORAT = ("grevskab", "baroni", "stamhus")
FORMORD = {"grevskab": "Grevskabet", "baroni": "Baroniet", "stamhus": "Stamhuset"}
ART_ETIKET = {"gård": "gård", "grevskab": "grevskab", "baroni": "baroni", "stamhus": "stamhus", None: "ukendt"}
OPS = ("opret", "saet", "sammenlaeg", "kopier", "hoerer_under", "flyt")
LIGHED = 0.85  # grænse for »ligner« (difflib-ratio på de foldede navne)


class PlanFejl(Exception):
    """En plan, der ikke må udføres (kæde, snapshot-række lagt sammen væk, manglende oprettelse …)."""


# ---------------------------------------------------------------- SQL (kun læsning)

# Kilde-hash: præcis samme udtryk som målingen af prod (laeserflade-6e1-maaling.md, »Genmåling #478«).
SQL_HASH_ESTATE = ("select md5(string_agg(id||'|'||coalesce(navn,'∅')||'|'||coalesce(slags,'∅')||'|'||"
                   "coalesce(sted_id::text,'∅'), '#' order by id)) from estate")
SQL_HASH_RELATION = ("select md5(string_agg(id||'|'||subjekt_type||subjekt_id||'|'||objekt_type||objekt_id||'|'||"
                     "rolle||'|'||coalesce(periode_raw,'∅'), '#' order by id)) from relation "
                     "where objekt_type='estate' or subjekt_type='estate'")

SQL_ESTATES = """
select coalesce(json_agg(json_build_object('id', e.id, 'navn', e.navn, 'slags', e.slags, 'sted_id', e.sted_id,
                                           'sted', pl.navn) order by e.id), '[]')
  from estate e left join place pl on pl.id = e.sted_id
"""

# Ejerforhold: periode, udgave (via påstand → citation → kilde) og om Task 5 kan kopiere det (præcis én påstand med
# præcis én citation, valgt af en afklaret konklusion).
SQL_EJER = """
select coalesce(json_agg(json_build_object(
         'rid', r.id, 'estate', r.objekt_id, 'periode', r.periode_raw,
         'kilder', (select coalesce(json_agg(distinct jsonb_build_object('source_id', s.id,
                                                    'udgave', coalesce(s.udgave, s.titel))), '[]')
                      from assertion a join citation c on c.assertion_id = a.id left join source s on s.id = c.source_id
                     where a.target_type = 'relation' and a.target_id = r.id),
         'kopierbar', (select count(*) from assertion a where a.target_type = 'relation' and a.target_id = r.id) = 1
                  and (select count(*) from assertion a join citation c on c.assertion_id = a.id
                        where a.target_type = 'relation' and a.target_id = r.id) = 1
                  and exists (select 1 from conclusion k join assertion a on a.id = k.valgt_assertion_id
                               where k.target_type = 'relation' and k.target_id = r.id and k.status = 'afklaret'))
       order by r.id), '[]')
  from relation r
 where r.objekt_type = 'estate' and r.rolle = 'ejer'
"""

# Billeder. Titlen læses kun for gods-billeder (sidens overskrift i DAA 2018-20, ingen personer).
SQL_MEDIA = """
select coalesce(json_agg(json_build_object('rid', r.id, 'media_id', m.id, 'estate', r.objekt_id, 'slags', m.slags,
                                           'datering', m.datering,
                                           'titel', case when m.slags = 'gods' then m.titel end) order by r.id), '[]')
  from relation r join media m on m.id = r.subjekt_id
 where r.subjekt_type = 'media' and r.objekt_type = 'estate' and r.rolle = 'afbildet'
"""

# Godser, som et slettet ejerforhold (eller anden slettet gods-relation) i change_event peger på: fortryd skal kunne
# genskabe dem, så de må aldrig lægges sammen væk.
SQL_SNAPSHOTS = """
select coalesce(json_agg(distinct x.id order by x.id), '[]') from (
  select (foer->>'objekt_id')::bigint id from change_event
   where tabel = 'relation' and op = 'DELETE' and foer->>'objekt_type' = 'estate'
  union
  select (foer->>'subjekt_id')::bigint from change_event
   where tabel = 'relation' and op = 'DELETE' and foer->>'subjekt_type' = 'estate') x
"""

# Relationer mellem godser (hører_under, sammenlagt_i) og andre roller end ejer/afbildet.
SQL_GODS_RELATIONER = """
select coalesce(json_agg(json_build_object('rid', r.id, 'subjekt_type', r.subjekt_type, 'subjekt_id', r.subjekt_id,
                                           'objekt_type', r.objekt_type, 'objekt_id', r.objekt_id, 'rolle', r.rolle)
                         order by r.id), '[]')
  from relation r
 where (r.objekt_type = 'estate' or r.subjekt_type = 'estate') and r.rolle not in ('ejer', 'afbildet')
"""

# Andre koblinger til godser (red_sammenlaeg_estate afviser at lægge sådan en række sammen væk).
SQL_ANDRE_KOBLINGER = """
select coalesce(json_agg(distinct x.id order by x.id), '[]') from (
  select target_id id from assertion where target_type = 'estate'
  union select objekt_id from assertion where objekt_type = 'estate'
  union select target_id from conclusion where target_type = 'estate'
  union select subjekt_id from entity_description where subjekt_type = 'estate'
  union select subjekt_id from fact where subjekt_type = 'estate'
  union select subjekt_id from haendelse where subjekt_type = 'estate'
  union select subjekt_id from narrative where subjekt_type = 'estate'
  union select target_id from note where target_type = 'estate'
  union select subjekt_id from story where subjekt_type = 'estate'
  union select maal_id from text_mention where maal_type = 'estate') x
"""

# Samme ejer på et andet gods: [ejerforhold, andet gods, andet ejerforhold, eksakt]. »Eksakt« = samme periode og
# samme kilde, dvs. red_kopier_ejerforhold ville returnere den eksisterende række (ingen ny). Ingen person-id'er.
SQL_SAMME_EJER = """
select coalesce(json_agg(json_build_array(r1.id, r2.objekt_id, r2.id,
         r2.periode_raw is not distinct from r1.periode_raw
         and exists (select 1 from assertion a1 join citation c1 on c1.assertion_id = a1.id
                       join assertion a2 on a2.target_type = 'relation' and a2.target_id = r2.id
                       join citation c2 on c2.assertion_id = a2.id
                      where a1.target_type = 'relation' and a1.target_id = r1.id
                        and c2.source_id is not distinct from c1.source_id))
       order by r1.id, r2.id), '[]')
  from relation r1
  join relation r2 on r2.subjekt_type = r1.subjekt_type and r2.subjekt_id = r1.subjekt_id and r2.id <> r1.id
                  and r2.objekt_type = 'estate' and r2.rolle = 'ejer' and r2.objekt_id <> r1.objekt_id
 where r1.objekt_type = 'estate' and r1.rolle = 'ejer'
"""

# Det ENESTE opslag i person: hvilke godser har en levende ejer (kun gods-id'er, aldrig navne).
SQL_LEVENDE_EJER = """
select coalesce(json_agg(distinct r.objekt_id order by r.objekt_id), '[]')
  from relation r join person p on p.id = r.subjekt_id
 where r.subjekt_type = 'person' and r.objekt_type = 'estate' and r.rolle = 'ejer' and p.levende
"""

SQL_KILDER = """
select coalesce(json_object_agg(coalesce(udgave, titel), id), '{}') from source where udgave is not null
"""


def _psql(db: str, sql: str) -> str:
    env = dict(os.environ)
    env["PGOPTIONS"] = "-c default_transaction_read_only=on"
    ud = subprocess.run(["psql", "-XAtq", "-v", "ON_ERROR_STOP=1", "-d", db, "-c", sql],
                        env=env, capture_output=True, text=True)
    if ud.returncode != 0:
        raise SystemExit(f"psql fejlede: {ud.stderr.strip()}")
    return ud.stdout.strip()


def hent_data(db: str) -> tuple[dict, dict]:
    """Læser alt fra databasen (kun læsning). Returnerer (data, kilde_hash)."""
    if _psql(db, "show transaction_read_only") != "on":
        raise SystemExit("forbindelsen er ikke skrivebeskyttet (transaction_read_only er ikke on)")
    kilde_hash = {"estate": _psql(db, SQL_HASH_ESTATE), "relation": _psql(db, SQL_HASH_RELATION)}
    data = {
        "estates": json.loads(_psql(db, SQL_ESTATES)),
        "ejer": json.loads(_psql(db, SQL_EJER)),
        "media": json.loads(_psql(db, SQL_MEDIA)),
        "snapshots": json.loads(_psql(db, SQL_SNAPSHOTS)),
        "gods_relationer": json.loads(_psql(db, SQL_GODS_RELATIONER)),
        "andre_koblinger": json.loads(_psql(db, SQL_ANDRE_KOBLINGER)),
        "samme_ejer": json.loads(_psql(db, SQL_SAMME_EJER)),
        "levende_estates": json.loads(_psql(db, SQL_LEVENDE_EJER)),
        "kilder": json.loads(_psql(db, SQL_KILDER)),
    }
    return data, kilde_hash


# ---------------------------------------------------------------- navnet

# Kun den bløde bindestreg fjernes fra navnet; hårde bindestreger (U+2010-2012, fx »Ober‑Ellguth« i 2018-20) bevares
# i navnet og ignoreres kun i nøglen.
_BINDESTREG = {0x00AD: None}
_BS = "‐‑‒-"  # bindestreg sidst, så den kan stå sidst i en tegnklasse
_FORMORD_RE = re.compile(r"^(grevskab|baroni|stamhus)(et|erne|ene)?\s+(.+)$", re.I)
_NAVNESKIFT_RE = re.compile(r"^(?:fra\s+\d{3,4}\s+|senere\s+)([A-ZÆØÅÄÖÜ][^,;()]*)$")
_IKKE_GAARD_RE = re.compile(
    r"\b(len|herred|herreder|sogn|fogderi|fogderiet|birk|palæ|hus|frihus|kongsgaard|kongsgård|kloster|"
    r"skovdistrikt|forpagter|forlening|andel|skænkede|slot|kalkbjerg|fideikommis\w*)\b|o\.s\.v", re.I)
_EMBEDE_RE = re.compile(r"\b(høvedsmand|hofmester|amtmand)\b", re.I)
_HALE_RE = re.compile(r"\s+[—–-]\s+|,\s+|\s+(?:ved|i|paa|på)\s+(?=[A-ZÆØÅÄÖÜ])")
_HALE_UDEN_KOMMA_RE = re.compile(r"\s+[—–-]\s+|\s+(?:ved|i|paa|på)\s+(?=[A-ZÆØÅÄÖÜ])")
_LISTE_RE = re.compile(r",\s*|\s+og\s+")


@dataclass
class Navn:
    original: str
    art: str  # gård | grevskab | baroni | stamhus (forslag ud fra formordet)
    hoved: str  # gårdens/majoratets navn uden formord, parentes og »til«
    noegle: str  # grupperingsnøgle »art:navn«
    liste: str | None = None  # med | og | flertal
    dele: list = field(default_factory=list)  # med/flertal: de øvrige; og: alle led
    landsbyer: bool = False
    sammen_med: bool = False
    tvivl_dele: bool = False
    har_parentes: bool = False
    til_foran: bool = False
    parentes_med: bool = False
    navneskift: str | None = None
    ikke_gaard: str | None = None  # ordet, der gør arten tvivlsom
    kerne: str = ""  # navnet uden stedtilføjelse (»ved …«, », … Herred«) — til »ligner«

    @property
    def ren(self) -> bool:
        return not (self.har_parentes or self.til_foran or self.liste or self.sammen_med
                    or self.kerne != self.hoved)


def _norm(s: str) -> str:
    s = s.lower()
    s = re.sub(rf"[\s—–{_BS}]+", "", s)
    return s.strip(".,;:")


def fold(s: str) -> str:
    """Grov stavefoldning til »ligner«-forslag (aldrig til forvalg)."""
    s = s.lower()
    for a, b in (("æ", "ae"), ("ø", "o"), ("å", "a"), ("ä", "a"), ("ö", "o"), ("ü", "u"), ("é", "e"),
                 ("ß", "ss"), ("aa", "a"), ("ph", "f"), ("th", "t"), ("dt", "t"), ("ck", "k"), ("c", "k"),
                 ("w", "v"), ("v", "f")):
        s = s.replace(a, b)
    s = re.sub(r"[^a-z]", "", s)
    return re.sub(r"(.)\1+", r"\1", s)


def _naer(a: str, b: str) -> bool:
    """Næsten samme foldede navn: samme forbogstav, mindst 5 tegn og difflib-ratio ≥ LIGHED."""
    return (len(a) >= 5 and len(b) >= 5 and a[0] == b[0]
            and difflib.SequenceMatcher(None, a, b).ratio() >= LIGHED)


def _dele(tekst: str) -> list:
    dele = [d.strip() for d in _LISTE_RE.split(tekst) if d.strip()]
    # »Gross- og Klein-Koppel« → Gross-Koppel, Klein-Koppel
    for i in range(len(dele) - 1):
        if dele[i][-1] in _BS and re.search(f"[{_BS}]", dele[i + 1]):
            dele[i] += re.split(f"[{_BS}]", dele[i + 1])[-1]
    return dele


def _ligner_navn(d: str) -> bool:
    return len(d) >= 3 and d[0].isupper() and d[-1] not in _BS and not re.fullmatch(r"[IVX]+", d)


def parse_navn(navn: str) -> Navn:
    s = unicodedata.normalize("NFC", navn).translate(_BINDESTREG).strip()
    parenteser = []
    while True:
        fund = re.findall(r"\(([^()]*)\)", s)
        if not fund:
            break
        parenteser.extend(fund)
        s = re.sub(r"\s*\([^()]*\)", " ", s)
    s = re.sub(r"\s*\[[^\]]*\]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"\s+([,.;:])", r"\1", s)
    til_foran = bool(re.match(r"til\s+", s, re.I))
    s = re.sub(r"^til\s+", "", s, flags=re.I)
    s = re.sub(r"\s+til$", "", s, flags=re.I)

    art, flertal = "gård", False
    m = _FORMORD_RE.match(s)
    if m:
        art, flertal, s = m.group(1).lower(), (m.group(2) or "").lower() in ("erne", "ene"), m.group(3).strip()

    sammen_med = bool(re.search(r"\bsammen med\b", navn, re.I))
    if sammen_med:
        s = re.split(r",?\s*\bsammen med\b", s, flags=re.I)[0].strip(" ,")

    n = Navn(original=navn, art=art, hoved=s, noegle="", har_parentes=bool(parenteser), til_foran=til_foran,
             sammen_med=sammen_med)
    n.parentes_med = any(re.search(r"\bmed\s+(?!Hr\.|Fru\b)[A-ZÆØÅÄÖÜ]", p) and not re.search(r"sammen med", p)
                         for p in parenteser)
    for p in parenteser:
        mm = _NAVNESKIFT_RE.match(p.strip())
        if mm:
            n.navneskift = mm.group(1).strip()

    if flertal:
        dele = _dele(s)
        n.liste, n.hoved, n.dele = "flertal", dele[0], dele[1:]
    elif re.search(r"\smed\s", s):
        x, y = s.split(" med ", 1)
        n.liste, n.hoved = "med", x.strip()
        if re.search(r"landsby", y, re.I):
            n.landsbyer = True
        else:
            n.dele = _dele(y)
            n.tvivl_dele = (not all(_ligner_navn(d) for d in n.dele)) or bool(re.search(r"\w-\s+og\s", y))
    elif re.search(r"\s+og\s+", s):
        n.liste, n.dele = "og", _dele(s)

    n.kerne = (_HALE_UDEN_KOMMA_RE if n.liste == "og" else _HALE_RE).split(n.hoved)[0].strip()
    if art == "gård":
        hit = _IKKE_GAARD_RE.search(n.kerne)
        hit = hit or re.search(r"\b(?:til\s+)?(len|forlen\w*)\b", n.hoved[len(n.kerne):], re.I)
        hit = hit or next((_EMBEDE_RE.search(p) for p in parenteser if _EMBEDE_RE.search(p)), None)
        n.ikke_gaard = hit.group(0) if hit else None
    n.noegle = f"{art}:{_norm(n.hoved)}"
    return n


_SOGN_RE = re.compile(r"((?:[A-ZÆØÅÄÖÜ][\w\-]*\.?\s+){0,2}?[A-ZÆØÅÄÖÜ][\w\-]*)\s+(S\.|Sogn|H\.|Herred)(?![\w])")


def sogne_i_navn(navn: str) -> list:
    """Sogn og herred, som navnet selv nævner (»Gaarz (Oldenburg Sogn …)«, »Vingegaard (Sønder Dyrs H.)«):
    [(»sogn«|»herred«, navn)]."""
    return [("herred" if t in ("H.", "Herred") else "sogn", n.strip()) for n, t in _SOGN_RE.findall(navn or "")]


def sted_dele(sted: str | None) -> dict:
    """place.navn (»Göhl S., Oldenburg Kr.«) → {"sogn": "Göhl", "herred": …} for de led, der findes."""
    ud = {}
    for d in (sted or "").split(","):
        d = d.strip()
        m = re.match(r"^(.+?)\s+(S\.|Sogn|H\.|Herred)$", d)
        if m:
            ud.setdefault("herred" if m.group(2) in ("H.", "Herred") else "sogn", m.group(1).strip())
    return ud


def samme_sted(a: str, b: str) -> bool:
    """Tolerant sammenligning af sogne-/herredsnavne (Krokels/Krokek, Strø/Östra Strö)."""
    fa, fb = fold(a), fold(b)
    if not fa or not fb:
        return True
    return (fa == fb or (min(len(fa), len(fb)) >= 4 and (fa in fb or fb in fa))
            or difflib.SequenceMatcher(None, fa, fb).ratio() >= 0.75)


def periode_spaend(periode: str | None):
    """(start, slut) for en periode; slut None = åben (»1750‑†«, »1731-«). Ingen årstal → None."""
    aar = _aar(periode)
    if not aar:
        return None
    tekst = (periode or "").strip()
    aaben = "†" in tekst or bool(re.search(r"[-\u2010-\u2014]\s*$", tekst))
    return min(aar), (None if aaben or (len(aar) == 1 and re.search(r"\d[-\u2010-\u2014]", tekst)) else max(aar))


def navn_ens(navn: str) -> str:
    """Navne, læseren ikke kan skelne: samme bogstaver uanset store/små, bindestregstype og mellemrum."""
    s = unicodedata.normalize("NFC", navn or "").casefold()
    s = re.sub(r"[\u2010-\u2014\-]", "-", s)
    return re.sub(r"\s+", " ", s).strip()


def kort_navn(n: Navn) -> str:
    """Godsets navn uden bogens tilføjelser: teksten før første parentes, komma eller tankestreg, uden »til«.
    For »X med Y« og »Grevskaberne X og Y« er det X. Hårde bindestreger og stavemåde bevares (ingen aa→å)."""
    if n.liste in ("med", "flertal"):
        return kanonisk_navn(n)
    if n.liste == "og":
        return n.hoved  # hele listen; aldrig kun første led
    s = unicodedata.normalize("NFC", n.original).translate(_BINDESTREG).strip()
    s = re.sub(r"^til\s+", "", s, flags=re.I)
    s = re.split(r"\s*[(\[,]|\s+[—–]\s+", s, maxsplit=1)[0].strip()
    s = re.sub(r"\s+til$", "", s, flags=re.I).strip()
    m = _FORMORD_RE.match(s)
    if m and n.art in MAJORAT:
        s = f"{FORMORD[n.art]} {m.group(3).strip()}"
    return s or n.original


def kort_entydigt(n: Navn, kort: str) -> bool:
    """Er det korte navn utvetydigt et godsnavn: 1-3 ord med stort begyndelsesbogstav, ingen tal, ingen »og«-liste."""
    rest = kort.split(" ", 1)[1] if n.art in MAJORAT and " " in kort else kort
    return (n.liste != "og" and not re.search(r"\d", rest)
            and bool(re.fullmatch(r"[A-ZÆØÅÄÖÜ][^\s,()]*(?: [A-ZÆØÅÄÖÜ][^\s,()]*){0,2}", rest)))


def parentes_forklaring(navn: str) -> list:
    """Hvad bogens tilføjelser til navnet er, i klart sprog (til forklaringen ved »kort navn«)."""
    ud = []
    for p_ in re.findall(r"\(([^()]*)\)", navn):
        p_ = p_.strip()
        if not p_ or p_.lower() == "til":
            continue
        if (re.search(r"\bved\b|\b(S\.|Sogn|H\.|Herred|Amt|Kr\.)", p_)
                or re.fullmatch(r"[A-ZÆØÅÄÖÜ][\w\-\u2010-\u2012' ]*", p_)):
            ud.append(f"»{p_}« er et sted eller et andet navn for godset. Fase 2 kan gemme det som sted eller "
                      f"»også kaldet«; intet går tabt, for hele bogens tekst gemmes ved ejerforholdene.")
        else:
            ud.append(f"»{p_}« er bogens oplysning om ejerforholdet (år, køb, salg, forlening …). Fase 2 flytter "
                      f"den over på ejerforholdet; hele bogens tekst gemmes ved ejerforholdene.")
    hale = re.split(r"\)\s*,|\s+[—–]\s+", navn, maxsplit=1)
    if len(hale) == 2 and hale[1].strip():
        ud.append(f"»{hale[1].strip()}« er bogens oplysning om ejerforholdet; fase 2 flytter den over på "
                  f"ejerforholdet, og hele bogens tekst gemmes ved ejerforholdene.")
    elif "(" not in navn and "," in navn and not re.search(r"\bog\b", navn):
        ud.append(f"»{navn.split(',', 1)[1].strip()}« er en tilføjelse til navnet (sted eller oplysning); hele "
                  f"bogens tekst gemmes ved ejerforholdene.")
    return ud


def _problem(g, navne: dict, ikke_gaard: list) -> str:
    """Én linje i klart sprog: hvorfor står gruppen i arket?"""
    medl = g.medlemmer
    n0 = navne[g.overlever]
    art = {"gård": "gård", "grevskab": "grevskab", "baroni": "baroni", "stamhus": "stamhus"}[g.art]
    dele = []
    if len(medl) > 1:
        dele.append(f"Databasen har {len(medl)} rækker for det, der ser ud til at være samme {art}, fordi bogen "
                    f"skriver navnet forskelligt.")
    elif n0.liste == "og":
        dele.append("Navnet nævner flere godser i én række.")
    elif n0.liste in ("med", "flertal") and n0.dele:
        dele.append("Navnet nævner flere godser; ejerforholdet skal stå på hvert af dem.")
    elif kort_navn(n0) != n0.original:
        dele.append("Navnet rummer mere end godsets navn (årstal, køb/salg, sted eller »til«).")
    if ikke_gaard:
        dele.append(f"Navnet tyder ikke på en gård (»{', '.join(ikke_gaard)}«), så vi ved ikke, hvilken slags det er.")
    return " ".join(dele) or "Intet problem — kun slags (gård, grevskab …) sættes."


def kanonisk_navn(n: Navn) -> str:
    return f"{FORMORD[n.art]} {n.hoved}" if n.art in MAJORAT else n.hoved


def _aar(periode: str | None) -> list:
    return [int(a) for a in re.findall(r"(?<!\d)(1[0-9]{3}|20[0-9]{2})(?!\d)", periode or "")]


# ---------------------------------------------------------------- forslagets byggesten

@dataclass
class Alternativ:
    kode: str
    tekst: str
    ops: dict
    adskilt: bool = False  # »Behold rækkerne adskilt«: kan ikke forenes med et S-»ja«


@dataclass
class Gruppe:
    nr: int
    noegle: str
    art: str
    medlemmer: list
    overlever: int
    navn: str
    tvivl: list = field(default_factory=list)
    info: list = field(default_factory=list)
    alternativer: dict = field(default_factory=dict)
    forvalg: str | None = None
    kategori: str = ""  # tvivl | aendring | enkel
    problem: str = ""  # én linje i klart sprog: hvorfor gruppen står i arket


@dataclass
class Spoergsmaal:
    """S (ligner hinanden), H (hører under) eller N (to grupper opretter en ny gård med samme navn)."""
    nr: str
    tekst: str
    medlemmer: list
    grupper: list
    alternativer: dict = field(default_factory=dict)
    forvalg: str | None = None
    info: list = field(default_factory=list)
    majorat_gruppe: int | None = None
    gaard_gruppe: int | None = None
    krenkerup: bool = False
    ekstra: dict = field(default_factory=dict)  # metadata til planens »poster« (S: flyttes; N: noegler, faelles)


def _tomme_ops() -> dict:
    return {k: [] for k in OPS}


def _laeg_til(ops: dict, andre: dict) -> None:
    for k in OPS:
        for o in andre.get(k, []):
            if k == "opret" and any(x["noegle"] == o["noegle"] for x in ops["opret"]):
                continue
            ops[k].append(o)


@dataclass
class Forslag:
    grupper: list
    sammenhaenge: list
    hoerer: list
    nye: list
    raekker: dict
    navne: dict
    snapshots: set
    ejer_pr_gods: dict
    media_pr_gods: dict
    sprunget_over: list
    kilder: dict = field(default_factory=dict)

    def poster(self):
        return list(self.grupper) + list(self.hoerer) + list(self.sammenhaenge) + list(self.nye)

    def plan(self, kilde_db: str, kilde_hash: dict) -> dict:
        ops, aabne, forvalg, alternativer, poster = _tomme_ops(), [], {}, {}, {}
        for p in self.poster():
            pid = post_id(p)
            alternativer[pid] = {k: {"tekst": a.tekst, **({"adskilt": True} if a.adskilt else {}), **a.ops}
                                 for k, a in p.alternativer.items()}
            if isinstance(p, Gruppe):
                poster[pid] = {"type": "gruppe", "medlemmer": p.medlemmer, "overlever": p.overlever,
                               "kategori": p.kategori}
            elif p.nr.startswith("S"):
                poster[pid] = {"type": "S", "grupper": [f"G{n}" for n in p.grupper], **p.ekstra}
            elif p.nr.startswith("N"):
                poster[pid] = {"type": "N", **p.ekstra}
            else:
                poster[pid] = {"type": "H", "grupper": [f"G{n}" for n in p.grupper]}
            if p.forvalg:
                forvalg[pid] = p.forvalg
                _laeg_til(ops, p.alternativer[p.forvalg].ops)
            else:
                aabne.append(pid)
        return {"version": 1, "kilde_db": kilde_db, "kilde_hash": kilde_hash, **ops,
                "aabne": aabne, "forvalg": forvalg, "alternativer": alternativer, "poster": poster,
                "snapshots": sorted(self.snapshots),
                "kilder": {k: v for k, v in sorted(self.kilder.items()) if k.startswith("DAA")}}


def post_id(p) -> str:
    """Postens id i arket, svaret og planen: »G12« for gruppe 12, ellers »S3«/»H2«."""
    return f"G{p.nr}" if isinstance(p, Gruppe) else p.nr


def byg_forslag(data: dict) -> Forslag:
    estates = {e["id"]: e for e in data["estates"]}
    snapshots = set(data.get("snapshots", []))
    andre = set(data.get("andre_koblinger", []))
    gods_rel = data.get("gods_relationer", [])
    sammenlagt_allerede = {r["subjekt_id"] for r in gods_rel if r["rolle"] == "sammenlagt_i"}
    hoerer_eksisterende = {}
    andre_roller = {}
    for r in gods_rel:
        if r["rolle"] == "hører_under":
            hoerer_eksisterende.setdefault(r["subjekt_id"], set()).add(r["objekt_id"])
        elif r["rolle"] != "sammenlagt_i":
            for t, i in ((r["subjekt_type"], r["subjekt_id"]), (r["objekt_type"], r["objekt_id"])):
                if t == "estate":
                    andre_roller.setdefault(i, set()).add(r["rolle"])
    ejer_pr_gods, media_pr_gods = {}, {}
    for e in data["ejer"]:
        ejer_pr_gods.setdefault(e["estate"], []).append(e)
    for m in data.get("media", []):
        media_pr_gods.setdefault(m["estate"], []).append(m)
    billede_af = {m["rid"]: m for m in data.get("media", [])}
    samme_ejer = {}
    for rid, gods, anden, eksakt in data.get("samme_ejer", []):
        samme_ejer.setdefault((rid, gods), []).append((anden, eksakt))
    kilde_2018 = data.get("kilder", {}).get("DAA 2018-20")

    # Persondata-vagt: et godsnavn med fritekst (parentes, »af«, »til« …) må ikke have en levende ejer, for så kunne
    # navnet nævne en nulevende og ende i planens citat og arket.
    for gid in data.get("levende_estates", []):
        navn = estates.get(gid, {}).get("navn") or ""
        if re.search(r"[(),—–\[]|\baf\b|\btil\b|sammen med", navn):
            raise PlanFejl(f"gods {gid} har en levende ejer og et navn med fritekst; gennemgå det manuelt")

    navne = {i: parse_navn(e["navn"] or "") for i, e in estates.items() if i not in sammenlagt_allerede}

    def udgaver(i):
        return sorted({k["udgave"] for e in ejer_pr_gods.get(i, []) for k in e["kilder"]})

    def har_2018(i):
        return "DAA 2018-20" in udgaver(i)

    def rang(i):
        # Stedet kan ikke flyttes af sammenlægningen, navnet sættes bagefter: rækken med sted vinder over det rene navn.
        return (har_2018(i), bool(estates[i].get("sted_id")), navne[i].ren,
                len(ejer_pr_gods.get(i, [])) + len(media_pr_gods.get(i, [])), -i)

    # 1) grupper efter nøgle; 2) navneskift (»senere X«, »fra 1741 X«) samler gruppen med X's gruppe.
    efter_noegle = {}
    for i in sorted(navne):
        efter_noegle.setdefault(navne[i].noegle, []).append(i)
    gammelt_navn = set()
    for i in sorted(navne):
        n = navne[i]
        if n.navneskift:
            maal = f"{n.art}:{_norm(n.navneskift)}"
            egen = next(k for k, v in efter_noegle.items() if i in v)
            if maal in efter_noegle and maal != egen:
                gammelt_navn.update(efter_noegle[egen])
                efter_noegle[maal] = sorted(efter_noegle[maal] + efter_noegle.pop(egen))

    raa = []
    for noegle, medl in efter_noegle.items():
        snap = [m for m in medl if m in snapshots]
        overlever = max(snap or medl, key=rang)
        kandidater = [m for m in medl if m not in gammelt_navn] or medl
        kandidater = [m for m in kandidater if har_2018(m)] or kandidater
        navnekilde = max(kandidater, key=lambda m: (navne[m].ren, len(ejer_pr_gods.get(m, [])), -m))
        raa.append((noegle, medl, overlever, kanonisk_navn(navne[navnekilde])))
    raa.sort(key=lambda t: (t[3].lower(), t[1][0]))

    grupper, efter_gnoegle, gruppe_af = [], {}, {}
    for nr, (noegle, medl, overlever, navn) in enumerate(raa, start=1):
        g = Gruppe(nr=nr, noegle=noegle, art=navne[medl[0]].art, medlemmer=medl, overlever=overlever, navn=navn)
        grupper.append(g)
        efter_gnoegle[noegle] = g
        for m in medl:
            gruppe_af[m] = g

    # Løse nøgler til »ligner«: kernen (uden stedtilføjelse) foldet.
    def loese(g):
        return {fold(navne[m].kerne) for m in g.medlemmer} - {""}

    def find_maal(del_navn: str, art: str, egen: Gruppe):
        """Et led i en liste → (mål, beskrivelse, tvivl-tekst, ny-oprettelse, kandidater).
        Kandidater er de andre mulige mål [(mål, beskrivelse, ny-oprettelse)], som arket tilbyder som egne valg.
        En ny gård får en nøgle pr. gruppe (»ny:G48:Aalstrup«), så to grupper aldrig deler en ny gård tavst."""
        dn = parse_navn(del_navn)
        g = efter_gnoegle.get(f"{art}:{_norm(dn.hoved)}")
        if g is egen:
            return None, None, None, None, []
        if g:
            return (g.overlever, f"{ART_ETIKET[art]}en {g.navn} (række {g.overlever}, gruppe {g.nr})", None, None,
                    [])
        ny_navn = dn.kerne or dn.hoved
        ny = {"noegle": f"ny:G{egen.nr}:{ny_navn}", "navn": ny_navn, "slags": art}
        ny_beskr = f"en ny {ART_ETIKET[art]} {ny_navn}"
        fk = fold(dn.kerne or dn.hoved)
        lign = [x for x in grupper if x.art == art and x is not egen and fk and fk in loese(x)]
        if len(fk) < 5:
            # Et kort navn rammer let ord i andre navne: alle grupper, hvor det står som helt ord, er kandidater.
            lign += [x for x in grupper if x.art == art and x is not egen and x not in lign
                     and any(fk in {fold(w) for w in re.split(r"[\s\-\u2010-\u2012/]+", navne[m].kerne)}
                             for m in x.medlemmer)]

        def eksisterende(x):
            return (x.overlever, f"{ART_ETIKET[art]}en {x.navn} (række {x.overlever}, gruppe {x.nr})", None)
        if len(lign) >= 2 or (lign and len(fk) < 5 and lign[0].noegle.split(":", 1)[1] != _norm(dn.hoved)):
            return (ny["noegle"], ny_beskr,
                    f"»{del_navn}« passer løst på " + ", ".join(f"gruppe {x.nr} ({x.navn})" for x in lign) +
                    f" — vælg nedenfor, om kopien skal til en af dem eller til en ny {ART_ETIKET[art]}",
                    ny, [eksisterende(x) for x in lign])
        if len(lign) == 1:
            x = lign[0]
            return (x.overlever, f"{ART_ETIKET[art]}en {x.navn} (række {x.overlever}, gruppe {x.nr})",
                    f"»{del_navn}« er koblet til gruppe {x.nr} ({x.navn}) ud fra et løst navnematch — vælg nedenfor, "
                    f"om det i stedet er en ny {ART_ETIKET[art]}", None, [(ny["noegle"], ny_beskr, ny)])
        naer = [x for x in grupper if x.art == art and x is not egen and fk and any(_naer(fk, b) for b in loese(x))]
        tv = None
        if naer:
            tv = (f"»{del_navn}« ligner " + ", ".join(f"gruppe {x.nr} ({x.navn})" for x in naer) +
                  f" — vælg nedenfor, om kopien skal til en af dem eller til en ny {ART_ETIKET[art]}")
        return ny["noegle"], ny_beskr, tv, ny, [eksisterende(x) for x in naer]

    def kopier_for(m: int, g: Gruppe, dele: list, art: str, ops: dict, tvivl: list, info: list,
                   valgfri: list | None = None):
        sogne = [sted_dele(estates[x].get("sted")).get("sogn") for x in (m, g.overlever)]
        sogne += [n_ for t_, n_ in sogne_i_navn(navne[m].original) if t_ == "sogn"]
        for d in dele:
            maal, beskr, tv, ny, kand = find_maal(d, art, g)
            if maal is None:
                continue
            if kand and valgfri is not None:
                valgfri.append((d, kand))
            if tv:
                tvivl.append(tv)
            sogn = next((x for x in sogne if x and fold(x) == fold(parse_navn(d).kerne or d)), None)
            if sogn:
                tvivl.append(f"»{d}« er også navnet på sognet ({sogn}), som godset ligger i — måske er det sognet og "
                             f"ikke en gård; kopien er ikke valgt på forhånd")
            if ny:
                ops["opret"].append({**ny, "gruppe": g.nr})
            maal_medl = gruppe_af[maal].medlemmer if isinstance(maal, int) else []
            for e in ejer_pr_gods.get(m, []):
                if not e.get("kopierbar", True):
                    tvivl.append(f"ejerforhold {e['rid']} kan ikke kopieres (uklar kilde) — skal klares i hånden")
                    continue
                fund = [(a, x) for mm in maal_medl for (a, x) in samme_ejer.get((e["rid"], mm), [])]
                if any(x for _, x in fund):
                    info.append(f"ejerforhold {e['rid']} findes allerede på {beskr} med samme periode og udgave "
                                f"(relation {next(a for a, x in fund if x)}) — kopieres ikke")
                    continue
                if fund:
                    info.append(f"samme ejer som i ejerforhold {e['rid']} står allerede på {beskr} "
                                f"(relation {fund[0][0]}); kopien giver en linje mere")
                ops["kopier"].append({"relation": e["rid"], "til": maal, "citat": navne[m].original,
                                      "gruppe": g.nr, "_del": d})

    def billeder_flyt(g: Gruppe, ops: dict, info: list, tvivl: list):
        for m in g.medlemmer:
            for b in media_pr_gods.get(m, []):
                if b["slags"] != "gods" or not b.get("titel"):
                    continue
                vist = b["titel"].split("(")[0].split(",")[0].strip()
                if g.art in MAJORAT:
                    gg = efter_gnoegle.get(f"gård:{_norm(vist)}")
                    if gg:
                        ops["flyt"].append({"relation": b["rid"], "til": gg.overlever, "gruppe": g.nr})
                        info.append(f"billedet (media {b['media_id']}) viser gården {vist}: flyttes til "
                                    f"række {gg.overlever} (gruppe {gg.nr})")
                    else:
                        info.append(f"billedet (media {b['media_id']}) viser gården {vist}, som ikke findes som "
                                    f"række — se spørgsmålene om »hører under«")
                elif _norm(vist) != _norm(navne[g.overlever].hoved) and _norm(vist) != g.noegle.split(":", 1)[1]:
                    tvivl.append(f"billedet (media {b['media_id']}) har titlen »{b['titel']}« — viser det en anden "
                                 f"gård end {g.navn}?")

    # ---- alternativer pr. gruppe
    for g in grupper:
        medl, ov = g.medlemmer, g.overlever
        tvivl, info = g.tvivl, g.info
        n_ov = navne[ov]
        snap = [m for m in medl if m in snapshots]
        if len(snap) >= 2:
            tvivl.append(f"flere rækker har slettede ejerforhold i historikken ({', '.join(map(str, snap))}) og må "
                         f"ikke lægges sammen væk; kun de øvrige kan lægges ind i {ov}")
        elif snap:
            info.append(f"række {snap[0]} har et slettet ejerforhold i historikken (fortryd) og er derfor den, "
                        f"der bliver stående")
        # Stedet sammenlignes på sognet (første led): place-tabellen har samme sogn stavet på flere måder.
        steder = {fold(estates[m]["sted"].split(",")[0]) if estates[m].get("sted") else str(estates[m]["sted_id"])
                  for m in medl if estates[m].get("sted_id")}
        if len(steder) > 1:
            tvivl.append("rækkerne har forskellige steder (" +
                         "; ".join(f"{m}: {estates[m]['sted']}" for m in medl if estates[m].get("sted_id")) +
                         ") — måske to forskellige godser")
        for m in medl:
            if m in andre and m != ov:
                tvivl.append(f"række {m} har andre koblinger (fx en tekst) og kan ikke lægges sammen af værktøjet")
            if andre_roller.get(m):
                tvivl.append(f"række {m} har relationer med rollen {', '.join(sorted(andre_roller[m]))}")
        majorater = {mj for m in medl for mj in hoerer_eksisterende.get(m, set())}
        if len(majorater) > 1:
            tvivl.append(f"rækkerne hører i dag under forskellige majorater ({', '.join(map(str, sorted(majorater)))})")
        if medl != [ov] and len({kanonisk_navn(navne[m]) for m in medl}) > 1:
            info.append("andre stavemåder i gruppen: " +
                        ", ".join(sorted({kanonisk_navn(navne[m]) for m in medl} - {g.navn})))
        ref = ov if estates[ov].get("sted") else next((m for m in medl if estates[m].get("sted")), None)
        ref_dele = sted_dele(estates[ref]["sted"]) if ref else {}
        set_sogne = {}
        for m in medl:
            for typ, nv in sogne_i_navn(navne[m].original):
                if m == ref:
                    continue
                if typ in ref_dele:
                    if not samme_sted(nv, ref_dele[typ]):
                        tvivl.append(f"række {m} nævner {typ}et »{nv}«, men række {ref} ligger i "
                                     f"»{estates[ref]['sted']}« — måske to forskellige godser")
                elif ref is None and len(medl) > 1:
                    for m2, nv2 in set_sogne.get(typ, []):
                        if not samme_sted(nv, nv2):
                            tvivl.append(f"række {m} nævner {typ}et »{nv}«, række {m2} »{nv2}« — måske to "
                                         f"forskellige godser")
                    set_sogne.setdefault(typ, []).append((m, nv))
                    info.append(f"række {m} nævner {typ}et »{nv}«; den overlevende række {ov} har intet sted "
                                f"(planen kan ikke sætte et)")
        if not estates[ov].get("sted_id"):
            for m in medl:
                if m != ov and estates[m].get("sted_id"):
                    info.append(f"stedet ({estates[m]['sted']}) står på række {m}, som lægges sammen; planen kan ikke "
                                f"flytte stedet til række {ov}")
        if any(m in gammelt_navn for m in medl):
            info.append("navneskift: bogen siger selv, at godset senere fik det nye navn (samme gods)")
        if any(navne[m].landsbyer for m in medl):
            info.append("»med landsbyerne …«: landsbyer er ikke gårde, så ejerforholdet kopieres ikke til dem")
        if any(navne[m].sammen_med for m in medl):
            info.append("»sammen med …« nævner en medejer, ikke en gård; intet kopieres")
        if any(navne[m].parentes_med for m in medl):
            tvivl.append("parentesen nævner flere godser (»med …«); ejerforholdet kopieres ikke til dem i fase 1")
        if any(navne[m].tvivl_dele for m in medl):
            tvivl.append("listen har led, der ikke ligner hele gårdnavne (fx »Gross- og Klein-…«)")
        if any(m in media_pr_gods for m in medl):
            info.append("billede(r): " + ", ".join(f"media {b['media_id']} ({b['slags']})" for m in medl
                                                   for b in media_pr_gods.get(m, [])) +
                        " — følger med til den række, der bliver stående")
        ikke_gaard = sorted({navne[m].ikke_gaard for m in medl if navne[m].ikke_gaard})
        if ikke_gaard:
            tvivl.append(f"navnet tyder ikke på en gård (»{', '.join(ikke_gaard)}«) — vælg art")

        def saet(estate, navn, slags):
            return {"estate": estate, "navn": navn, "slags": slags, "gruppe": g.nr}

        # Basis-alternativet A: læg sammen (eller sæt navn og art på en enkelt række).
        a = _tomme_ops()
        a_tvivl, a_info, valgfri = [], [], []
        if len(medl) == 1:
            if n_ov.liste in ("med", "flertal"):
                a_navn = kanonisk_navn(n_ov)
                if n_ov.har_parentes:
                    a_info.append("parentesen fjernes fra navnet; hele bogens form bevares som citat på ejerforholdet")
            elif n_ov.liste == "og":
                a_navn = n_ov.original
            elif n_ov.ren:
                a_navn = kanonisk_navn(n_ov)
            else:
                a_navn = n_ov.original
            a["saet"].append(saet(ov, a_navn, g.art))
        else:
            a["saet"].append(saet(ov, g.navn, g.art))
            for m in medl:
                if m == ov or (m in snapshots) or m in andre:
                    continue
                a["sammenlaeg"].append({"fra": m, "til": ov, "gruppe": g.nr})
            for m in medl:
                if m != ov and (m in snapshots or m in andre):
                    a["saet"].append(saet(m, navne[m].original, g.art))
        for m in medl:
            n = navne[m]
            if n.liste in ("med", "flertal") and n.dele:
                kopier_for(m, g, n.dele, "gård" if n.liste == "med" else n.art, a, a_tvivl, a_info, valgfri)
        billeder_flyt(g, a, a_info, a_tvivl)
        tvivl.extend(t for t in a_tvivl if t not in tvivl)
        info.extend(t for t in a_info if t not in info)

        def hvor(x):
            if isinstance(x, str):
                return f"den nye gård {x[3:]}"
            return f"række {x} ({gruppe_af[x].navn})" if x in gruppe_af else f"række {x}"

        def slags_tekst(x):
            return "ikke angivet (vi ved ikke, om det er en gård)" if x is None else ART_ETIKET[x]

        def beskriv(ops):
            dele = []
            hoved = [x for x in ops["saet"] if x["estate"] == ov] or ops["saet"][:1]
            andre_saet = [x for x in ops["saet"] if x not in hoved]
            if ops["saet"] and len(ops["saet"]) > 1 and not ops["sammenlaeg"]:
                dele.append(f"Siden viser fortsat {len(ops['saet'])} sider: " +
                            ", ".join(f"»{x['navn']}«" for x in ops["saet"]) +
                            f" · slags: {slags_tekst(ops['saet'][0]['slags'])}")
            else:
                for x in hoved:
                    gl = estates[x["estate"]]["navn"]
                    t = f"Siden viser: »{x['navn']}« · slags: {slags_tekst(x['slags'])}"
                    if x["navn"] != gl:
                        t += f" · bogens fulde tekst (»{gl}«) gemmes ved ejerforholdene"
                    dele.append(t)
                for x in andre_saet:
                    dele.append(f"række {x['estate']} forbliver en egen side »{x['navn']}« (den har slettede "
                                f"ejerforhold i historikken)")
            for x in ops["sammenlaeg"]:
                if x["til"] == ov:
                    continue
                dele.append(f"Siden viser: »{gruppe_af[x['til']].navn}« (gruppe {gruppe_af[x['til']].nr}) — "
                            f"denne række lægges ind i den, og bogens fulde tekst gemmes ved ejerforholdet")
            ind = [x["fra"] for x in ops["sammenlaeg"] if x["til"] == ov]
            if ind:
                ne = sum(len(ejer_pr_gods.get(x, [])) for x in ind)
                nb = sum(len(media_pr_gods.get(x, [])) for x in ind)
                dele.append(f"{len(ind)} andre række{'r' if len(ind) > 1 else ''} ({', '.join(map(str, ind))}) lægges "
                            f"ind i denne side; deres {ne} ejerforhold" + (f" og {nb} billede(r)" if nb else "") +
                            " flyttes med, og deres navne gemmes ved ejerforholdene")
            nye = {o["noegle"] for o in ops["opret"]}
            if ops["kopier"]:
                maal = []
                for k in ops["kopier"]:
                    t = (f"{k['til'][3:]} (ny side)" if k["til"] in nye or isinstance(k["til"], str)
                         else f"{gruppe_af[k['til']].navn} (række {k['til']})")
                    if t not in maal:
                        maal.append(t)
                dele.append("ejerforholdet står også på: " + ", ".join(maal))
            for f_ in ops["flyt"]:
                b = billede_af.get(f_["relation"])
                hvad = f"billedet (media {b['media_id']})" if b else f"ejerforhold {f_['relation']}"
                dele.append(f"{hvad} flyttes til {hvor(f_['til'])}")
            return " · ".join(dele) or "ingen ændring"

        alts = []
        if len(medl) > 1:
            alts.append(("Læg sammen til én side", a))
            adskilt = _tomme_ops()
            for m in medl:
                adskilt["saet"].append(saet(m, navne[m].original, g.art))
            alts.append(("Behold rækkerne adskilt som hver sin side", adskilt))
        elif n_ov.liste == "og" and not all(_ligner_navn(d) and not _IKKE_GAARD_RE.search(d) for d in n_ov.dele):
            alts.append(("Behold som én side (listen ligner ikke flere gårde)", a))
            tvivl.append(f"»{n_ov.original}« er ikke oplagt en liste af gårde; ingen forvalg")
        elif n_ov.liste == "og":
            # Del op: første led bliver gården, de øvrige får en kopi af ejerforholdet.
            delt = _tomme_ops()
            d_tvivl, d_info = [], []
            maal, _, tv, ny, _k = find_maal(n_ov.dele[0], g.art, g)
            if tv:
                d_info.append(tv)
            if isinstance(maal, int) and ov not in snapshots and ov not in andre:
                # Målets navn og art sættes af målets egen gruppe.
                delt["sammenlaeg"].append({"fra": ov, "til": maal, "gruppe": g.nr})
            else:
                delt["saet"].append(saet(ov, parse_navn(n_ov.dele[0]).hoved, g.art))
            kopier_for(ov, g, n_ov.dele[1:], g.art, delt, d_tvivl, d_info)
            info.extend(t for t in d_info + d_tvivl if t not in info)
            alts.append((f"Del op: {' / '.join(n_ov.dele)} er hver sin gård", delt))
            alts.append(("Behold som én side med bogens navn", a))
            kort = kort_navn(n_ov)
            if kort != n_ov.original:
                b = json.loads(json.dumps(a))
                b["saet"][0]["navn"] = kort
                alts.append(("Behold som én side med det korte navn", b))
            tvivl.append("»og«-liste: er det flere gårde (del op) eller ét navn? Ingen forvalg")
        else:
            kort = kort_navn(n_ov)
            if kort == n_ov.original:
                alts.append(("Navnet er i orden", a))
            else:
                k_ops = json.loads(json.dumps(a))
                k_ops["saet"][0]["navn"] = kort
                u_ops = json.loads(json.dumps(a))
                u_ops["saet"][0]["navn"] = n_ov.original
                kort_alt = ("Kort navn" if len(kort) < len(n_ov.original) - 1 else "Ret skrivemåden", k_ops)
                uaendret = ("Behold navnet, som det står i databasen", u_ops)
                if kort_entydigt(n_ov, kort):
                    alts += [kort_alt, uaendret]
                else:
                    alts += [uaendret, kort_alt]
                    tvivl.append(f"det korte navn »{kort}« er ikke oplagt et godsnavn — vælg selv")
                if len(kort) < len(n_ov.original) - 1:
                    info.extend(x for x in parentes_forklaring(n_ov.original) if x not in info)
        for d, kand in valgfri:
            for maal, beskr, ny in kand:
                v = json.loads(json.dumps(alts[0][1]))
                for k in v["kopier"]:
                    if k.get("_del") == d:
                        k["til"] = maal
                if ny:
                    v["opret"].append({**ny, "gruppe": g.nr})
                brugt = {k["til"] for k in v["kopier"]}
                v["opret"] = [o for o in v["opret"] if o["noegle"] in brugt]
                alts.append((f"{alts[0][0]}, men »{d}« er {beskr}", v))
        if a["kopier"]:
            # Kopierne skal kunne fravælges for sig (»X med Y« kan også være én gård med et andet navn).
            uk = json.loads(json.dumps(alts[0][1]))
            brugt = {k["til"] for k in uk["kopier"]}
            uk["kopier"] = []
            uk["opret"] = [o for o in uk["opret"] if o["noegle"] not in brugt]
            alts.append((alts[0][0] + ", men uden kopier til de andre gårde", uk))
        if ikke_gaard and g.art == "gård":
            ekstra = []
            for tekst, ops in alts:
                u = json.loads(json.dumps(ops))
                for s_ in u["saet"]:
                    s_["slags"] = None
                ekstra.append((tekst + ", men slags ikke angivet", u))
            # Navnet tyder ikke på en gård: »slags ikke angivet« er det sandsynlige svar og står først.
            alts = ekstra + alts
        for _t, ops in alts:
            for k in ops["kopier"]:
                k.pop("_del", None)
            for k in [k for k in ops["opret"]]:
                k.pop("_del", None)
        for i, (tekst, ops) in enumerate(alts):
            kode = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i]
            g.alternativer[kode] = Alternativ(kode, f"{tekst}. {beskriv(ops)}", ops,
                                             adskilt=tekst.startswith("Behold rækkerne adskilt"))
        g.problem = _problem(g, navne, ikke_gaard)
        g.forvalg = None if tvivl else "A"
        ændrer = (len(medl) > 1 or any(g.alternativer["A"].ops[k] for k in ("kopier", "flyt", "opret"))
                  or g.alternativer["A"].ops["saet"][0]["navn"] != navne[ov].original)
        g.kategori = "tvivl" if tvivl else ("aendring" if ændrer else "enkel")

    # ---- H: hører under (majorat og gård med samme navn, eller bogens »hovedsæde i grevskabet X«)
    hoerer = []
    hs_re = re.compile(r"^(?P<gaard>[^(,]+?)\s*\(.*?\)\s*(?P<periode>\d{4}\s*-\s*\d{4})\s+hovedsæde i\s+"
                       r"(?P<formord>grevskabet|baroniet|stamhuset)\s+(?P<navn>.+?)\.?$", re.I)
    for mg in [x for x in grupper if x.art in MAJORAT]:
        base = mg.noegle.split(":", 1)[1]
        mper = [x for m in mg.medlemmer for e in ejer_pr_gods.get(m, []) for x in [periode_spaend(e["periode"])] if x]
        # Majoratets levetid: første start til seneste udtrykkelige slut (fx »afløst 1924«), når den ligger efter alle
        # starter; ellers er det åbent (»1736‑†« er ejerens levetid, ikke majoratets ophør).
        mslut_kendt = [b for _, b in mper if b is not None]
        mstart = min((a_ for a_, _ in mper), default=None)
        mslut = (max(mslut_kendt) if mslut_kendt and max(mslut_kendt) >= max(a_ for a_, _ in mper) else None)
        evidens = []
        for m in mg.medlemmer:
            for b in media_pr_gods.get(m, []):
                mm = hs_re.match(b.get("titel") or "")
                if mm and _norm(mm.group("navn")) == base:
                    evidens.append((b, mm))
        par = [x for x in grupper if x.art == "gård" and (x.noegle.split(":", 1)[1] == base
                                                           or (loese(x) & loese(mg)))]
        par = [(x, next(((b, mm) for b, mm in evidens if _norm(mm.group("gaard")) == x.noegle.split(":", 1)[1]),
                        None)) for x in par]
        for b, mm in evidens:
            if not any(_norm(mm.group("gaard")) == x.noegle.split(":", 1)[1] for x, _ in par if x):
                par.append((None, (b, mm)))  # gården findes ikke som række; hver får sit eget billede
        for gg, ev in par:
            nr = f"H{len(hoerer) + 1}"
            h = Spoergsmaal(nr=nr, tekst="", medlemmer=list(mg.medlemmer) + (gg.medlemmer if gg else []),
                            grupper=[mg.nr] + ([gg.nr] if gg else []), majorat_gruppe=mg.nr,
                            gaard_gruppe=gg.nr if gg else None)
            ja = _tomme_ops()
            if gg is None:
                gnavn = ev[1].group("gaard").strip()
                gaard = f"ny:{nr}:{gnavn}"
                ja["opret"].append({"noegle": gaard, "navn": gnavn, "slags": "gård", "gruppe": nr})
                ja["flyt"].append({"relation": ev[0]["rid"], "til": gaard, "gruppe": nr})
                h.info.append(f"gården {gnavn} findes ikke som række; »ja« opretter den og flytter billedet "
                              f"(media {ev[0]['media_id']}) dertil")
            else:
                gaard, gnavn = gg.overlever, gg.navn
            if ev:
                ja["hoerer_under"].append({"gaard": gaard, "majorat": mg.overlever,
                                           "periode": re.sub(r"\s+", "", ev[1].group("periode")),
                                           "source": kilde_2018, "citat": ev[0]["titel"], "gruppe": nr})
                h.info.append(f"bogens ord (billedets overskrift i DAA 2018-20): »{ev[0]['titel']}«")
                h.tekst = f"Hørte {gnavn} under {mg.navn}? Bogen siger det i billedets overskrift."
            else:
                ja["hoerer_under"].append({"gaard": gaard, "majorat": mg.overlever, "periode": None,
                                           "source": None, "citat": None, "gruppe": nr})
                h.tekst = (f"Hørte gården {gnavn} (gruppe {gg.nr}) under {mg.navn} (gruppe {mg.nr})? Godsnavnene "
                           f"siger det ikke; vælg »ja« og udfyld periode, udgave og bogens ord — eller »nej«.")
                if gg.noegle.split(":", 1)[1] != base:
                    h.info.append("navnene ligner kun hinanden (løst match)")
            hu = ja["hoerer_under"][0]
            ja_tekst = (f"Ja. Gårdens side viser »Hørte under {mg.navn}«, og majoratets side nævner gården. Der "
                        f"oprettes en »hører under«-relation fra {'den nye gård ' + gnavn if gg is None else f'række {gaard} ({gnavn})'}"
                        f" til række {mg.overlever} ({mg.navn})")
            if hu["citat"]:
                ja_tekst += (f", periode {hu['periode']}, kilde DAA 2018-20, med bogens ord som citat"
                             + (f"; den nye gård {gnavn} oprettes, og billedet (media {ev[0]['media_id']}) flyttes dertil"
                                if gg is None else ""))
            else:
                ja_tekst += " — udfyld periode, udgave og bogens ord i felterne nedenfor; ingen ejerforhold flyttes"
            h.alternativer["ja"] = Alternativ("ja", ja_tekst, ja)
            h.alternativer["nej"] = Alternativ("nej", "Nej. Siderne viser ingen forbindelse mellem gården og "
                                                      "majoratet", _tomme_ops())
            if gg is not None:
                gper = [x for m in gg.medlemmer for e in ejer_pr_gods.get(m, []) for x in [periode_spaend(e["periode"])]
                        if x]

                def inden_for(per):
                    a_, b_ = per
                    if mstart is None or a_ < mstart:
                        return False
                    if mslut is None:
                        return True
                    # Streng ulighed: en ejer, der tiltræder det år majoratet ophører (»1924‑†«), er ikke inden for.
                    return a_ < mslut and (b_ is None or b_ < mslut)

                if gper and all(inden_for(x) for x in gper):
                    h.krenkerup = True
                    vis = lambda a_, b_: f"{a_}-{'' if b_ is None else b_}"
                    h.info.append(f"Krenkerup-mønster: gårdens ejerperioder ({', '.join(vis(*x) for x in gper)}) "
                                  f"ligger inden for majoratets ({vis(mstart, mslut)}) — måske menes majoratet")
                    fl = _tomme_ops()
                    for m in gg.medlemmer:
                        for e in ejer_pr_gods.get(m, []):
                            fl["flyt"].append({"relation": e["rid"], "til": mg.overlever, "gruppe": nr})
                    h.alternativer["flyt"] = Alternativ(
                        "flyt", f"Bogen mente majoratet. Ejerforholdet vises på siden »{mg.navn}« i stedet for "
                                f"på gårdens side; bogens tekst gemmes ved ejerforholdet", fl)
                    gg.info.append(f"Krenkerup-mønster: ejeren af gården ejede i samme periode {mg.navn} — se {nr}")
                else:
                    gg.info.append(f"der findes også {mg.navn} (gruppe {mg.nr}) — se {nr}")
            hoerer.append(h)

    # ---- S: grupper, der ligner hinanden (stavemåde eller stedtilføjelse)
    sammenhaenge = []
    kant = {g.nr: set() for g in grupper}

    def ord_i(g):
        """Foldede ord i rækkernes navne uden parentes og uden hale efter tankestreg/komma (og-lister undtaget)."""
        ud = set()
        for m in g.medlemmer:
            if navne[m].liste == "og":
                continue
            n = navne[m]
            # Stedtilføjelsen (»ved Altenhof«) tæller kun med, når kernen er et fællesord (»gård i Bistingsmåla«).
            del_ = n.kerne if n.kerne[:1].isupper() and not n.ikke_gaard else n.hoved
            del_ = re.split(r"\s+[—–-]\s+|,\s+", del_)[0]
            ud |= {fold(w) for w in re.split(r"[\s\-‐-‒/]+", del_) if w}
        return ud

    # Et enkeltords-gårdnavn (5+ bogstaver), der står som helt ord eller med »gaard« bagefter i en anden gruppes navn
    # (»Glibstrup Gaard i Andst Sogn«, »gård i Bistingsmåla«, »Tølløsegaard«).
    enkeltord = {g.nr: next(iter(loese(g))) for g in grupper
                 if len(loese(g)) == 1 and len(next(iter(loese(g)))) >= 5
                 and all(" " not in navne[m].kerne and navne[m].kerne[:1].isupper() and not navne[m].ikke_gaard
                         for m in g.medlemmer)}
    for g1 in grupper:
        k = enkeltord.get(g1.nr)
        if not k:
            continue
        for g2 in grupper:
            if g2 is not g1 and g1.art == g2.art and any(w == k or w == k + "gard" for w in ord_i(g2)):
                kant[g1.nr].add(g2.nr)
                kant[g2.nr].add(g1.nr)
    for i, g1 in enumerate(grupper):
        l1 = loese(g1)
        for g2 in grupper[i + 1:]:
            if g1.art == g2.art and (l1 & loese(g2) or any(_naer(a, b) for a in l1 for b in loese(g2))):
                kant[g1.nr].add(g2.nr)
                kant[g2.nr].add(g1.nr)
    efter_nr = {g.nr: g for g in grupper}
    set_ = set()
    for g in grupper:
        if g.nr in set_ or not kant[g.nr]:
            continue
        komp, stak = set(), [g.nr]
        while stak:
            x = stak.pop()
            if x not in komp:
                komp.add(x)
                stak.extend(kant[x] - komp)
        set_ |= komp
        gs = sorted((efter_nr[x] for x in komp),
                    key=lambda x: (any(m in snapshots for m in x.medlemmer), rang(x.overlever)), reverse=True)
        hoved_g, rest = gs[0], gs[1:]
        nr = f"S{len(sammenhaenge) + 1}"
        s = Spoergsmaal(nr=nr, medlemmer=[m for x in gs for m in x.medlemmer], grupper=[x.nr for x in gs],
                        tekst=(f"Er {', '.join(f'gruppe {x.nr} ({x.navn})' for x in gs[:-1])} og gruppe "
                               f"{gs[-1].nr} ({gs[-1].navn}) samme {ART_ETIKET[hoved_g.art]}? Navnene er ens "
                               f"bortset fra stavning eller en stedtilføjelse." +
                               (" Er kun nogle af dem samme gods, så vælg »kun nogle« og sæt flueben ved dem."
                                if len(gs) > 2 else "")))
        s.ekstra = {"flyttes": {f"G{x.nr}": [m for m in x.medlemmer if m not in snapshots and m not in andre]
                                for x in gs}}
        ja = _tomme_ops()
        for x in rest:
            if any(m in snapshots for m in x.medlemmer):
                s.info.append(f"gruppe {x.nr} har en række med slettede ejerforhold i historikken; den kan ikke "
                              f"lægges sammen væk — »ja« lægger kun de øvrige rækker ind")
            for m in x.medlemmer:
                if m not in snapshots and m not in andre:
                    ja["sammenlaeg"].append({"fra": m, "til": hoved_g.overlever, "gruppe": nr})
        if len({x.art for x in gs}) > 1:
            s.info.append("grupperne har forskellig art")
        s.alternativer["ja"] = Alternativ(
            "ja", f"Ja, samme gods. Siden viser: »{hoved_g.navn}« (gruppe {hoved_g.nr}) · rækkerne fra gruppe "
                  f"{', '.join(str(x.nr) for x in rest)} lægges ind i den, og deres navne gemmes ved ejerforholdene "
                  f"(det erstatter de gruppers egne valg om sammenlægning)", ja)
        s.alternativer["nej"] = Alternativ("nej", "Nej, forskellige godser. Siderne forbliver adskilt, som grupperne "
                                                  "selv bestemmer", _tomme_ops())
        if len(gs) > 2:
            s.alternativer["delvis"] = Alternativ(
                "delvis", "Kun nogle af grupperne er samme gods. Sæt flueben ved dem, der er samme gods (mindst to); "
                          "de lægges ind i den første af dem, og de øvrige forbliver egne sider", _tomme_ops())
        sammenhaenge.append(s)
        for x in gs:
            x.info.append(f"ligner gruppe {', '.join(str(y.nr) for y in gs if y is not x)} — se {nr}")

    def resultatnavn(x):
        a_ = x.alternativer.get(x.forvalg or "A")
        if not a_:
            return None
        sv = [o for o in a_.ops["saet"] if o["estate"] == x.overlever]
        return sv[0]["navn"] if sv else None

    s_af = {}
    for q in sammenhaenge:
        for n_ in q.grupper:
            s_af[n_] = q.nr
    navne_ud = {}
    for x in grupper:
        r = resultatnavn(x)
        if r:
            navne_ud.setdefault((navn_ens(r), x.art), []).append(x)
    for x in grupper:
        if not x.forvalg or not x.alternativer[x.forvalg].tekst.startswith(("Kort navn", "Ret skrivemåden")):
            continue
        andre_g = [y for y in navne_ud.get((navn_ens(resultatnavn(x)), x.art), []) if y is not x]
        if andre_g:
            x.forvalg = None
            x.kategori = "tvivl"
            x.tvivl.append(f"det korte navn »{resultatnavn(x)}« er også navnet på " +
                           ", ".join(f"gruppe {y.nr}" + (f" (se {s_af[y.nr]})" if s_af.get(y.nr) == s_af.get(x.nr)
                                                          and s_af.get(x.nr) else "") for y in andre_g) +
                           " — to sider med samme navn kan læseren ikke skelne; vælg selv")

    nye = {}
    for x in list(grupper) + list(hoerer):
        for a_ in x.alternativer.values():
            for o in a_.ops["opret"]:
                nye.setdefault((navn_ens(o["navn"]), o["slags"]), {}).setdefault(post_id(x), o["noegle"])
    nye_q = []
    for (nv, sl), noegler in sorted(nye.items()):
        if len(noegler) < 2:
            continue
        nr = f"N{len(nye_q) + 1}"
        navn_vis = next(o["navn"] for x in list(grupper) + list(hoerer) for a_ in x.alternativer.values()
                        for o in a_.ops["opret"] if (navn_ens(o["navn"]), o["slags"]) == (nv, sl))
        gnr = [int(k[1:]) for k in noegler if k.startswith("G")]
        q = Spoergsmaal(nr=nr, medlemmer=[m for x in grupper if x.nr in gnr for m in x.medlemmer], grupper=gnr,
                        tekst=(f"Er den nye {ART_ETIKET[sl]} »{navn_vis}«, som {' og '.join(noegler)} hver vil "
                               f"oprette, samme {ART_ETIKET[sl]}?"))
        q.ekstra = {"noegler": noegler, "faelles": f"ny:{navn_vis}"}
        q.info.append("»Ja«: der oprettes én side, og alle kopierne står på den. »Nej«: to sider med samme navn "
                      "kan læseren ikke skelne, så højst én af grupperne må oprette den (vælg »uden kopier« i en af dem).")
        q.alternativer["ja"] = Alternativ("ja", f"Ja, samme {ART_ETIKET[sl]}. Siden viser: »{navn_vis}« — én ny side "
                                                f"med ejerforholdene fra {' og '.join(noegler)}", _tomme_ops())
        q.alternativer["nej"] = Alternativ("nej", f"Nej, forskellige. Hver gruppe opretter sin egen side "
                                                  f"»{navn_vis}«", _tomme_ops())
        for k in noegler:
            for x in grupper:
                if post_id(x) == k:
                    x.info.append(f"den nye {ART_ETIKET[sl]} »{navn_vis}« vil også blive oprettet af "
                                  f"{', '.join(y for y in noegler if y != k)} — se {nr}")
        nye_q.append(q)

    return Forslag(grupper=grupper, sammenhaenge=sammenhaenge, hoerer=hoerer, nye=nye_q, raekker=estates, navne=navne,
                   snapshots=snapshots, ejer_pr_gods=ejer_pr_gods, media_pr_gods=media_pr_gods,
                   sprunget_over=sorted(sammenlagt_allerede), kilder=dict(data.get("kilder", {})))


# ---------------------------------------------------------------- planens vagter

def valider_plan(p: dict, snapshots: set) -> None:
    fra = [s["fra"] for s in p.get("sammenlaeg", [])]
    til = {s["til"] for s in p.get("sammenlaeg", [])}
    if len(fra) != len(set(fra)):
        raise PlanFejl("en række lægges sammen mere end én gang")
    if set(fra) & til:
        raise PlanFejl(f"kæde: {sorted(set(fra) & til)} er både fra og til")
    if set(fra) & snapshots:
        raise PlanFejl(f"rækker med slettede ejerforhold lægges sammen væk: {sorted(set(fra) & snapshots)}")
    fl = [f_["relation"] for f_ in p.get("flyt", [])]
    if len(fl) != len(set(fl)):
        raise PlanFejl(f"samme relation flyttes flere gange: {sorted({x for x in fl if fl.count(x) > 1})}")
    kp = [(k["relation"], k["til"]) for k in p.get("kopier", [])]
    if len(kp) != len(set(kp)):
        raise PlanFejl("samme kopi står flere gange")
    oprettet = {o["noegle"] for o in p.get("opret", [])}
    maal = ([k["til"] for k in p.get("kopier", [])] + [f["til"] for f in p.get("flyt", [])] +
            [h["gaard"] for h in p.get("hoerer_under", [])] + [h["majorat"] for h in p.get("hoerer_under", [])])
    for x in maal:
        if isinstance(x, str) and x not in oprettet:
            raise PlanFejl(f"{x} bruges, men oprettes ikke")
        if x in set(fra):
            raise PlanFejl(f"række {x} er mål for en kopi/flytning, men lægges selv sammen væk")
    art = {s["estate"]: s.get("slags") for s in p.get("saet", [])}
    art.update({o["noegle"]: o.get("slags") for o in p.get("opret", [])})
    for s in p.get("saet", []):
        if "slags" not in s:
            raise PlanFejl(f"saet for {s['estate']} mangler slags (NULL betyder »ukendt«, ikke »uændret«)")
    for h in p.get("hoerer_under", []):
        if art.get(h["gaard"]) != "gård" or art.get(h["majorat"]) not in MAJORAT:
            raise PlanFejl(f"hører_under {h['gaard']} → {h['majorat']} uden gård/majorat-art i planen")
        if not h.get("citat") or not h.get("source"):
            raise PlanFejl(f"hører_under {h['gaard']} → {h['majorat']} mangler kilde eller citat")


# ---------------------------------------------------------------- arket

def tjek_ark_sti(sti: Path) -> Path:
    s = Path(os.path.abspath(sti)).resolve()
    if s == REPO or REPO in s.parents:
        raise SystemExit(f"arket må ikke ligge i repo'et ({REPO}); vælg en sti udenfor")
    return s


def _e(x) -> str:
    return html.escape("" if x is None else str(x))


CSS = """
:root{--bg:#fbfaf7;--fg:#1d1b17;--muted:#6b665c;--card:#ffffff;--line:#e4e0d6;--accent:#7a4b12;
--warn-bg:#fff3e0;--warn-fg:#8a4b00;--ok-bg:#eaf5ea;--ok-fg:#25622b;--chip:#f1ede4;--fokus:#2f6fd6;--fejl:#b3261e}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#16150f;--fg:#ece8de;--muted:#a59f92;
--card:#1f1e17;--line:#38352b;--accent:#e0a85a;--warn-bg:#3a2a12;--warn-fg:#ffc77a;--ok-bg:#1c3220;--ok-fg:#8fd69a;
--chip:#2a2820;--fokus:#7fb0ff;--fejl:#ff8a80}}
:root[data-theme="dark"]{--bg:#16150f;--fg:#ece8de;--muted:#a59f92;--card:#1f1e17;--line:#38352b;--accent:#e0a85a;
--warn-bg:#3a2a12;--warn-fg:#ffc77a;--ok-bg:#1c3220;--ok-fg:#8fd69a;--chip:#2a2820;--fokus:#7fb0ff;--fejl:#ff8a80}
*{box-sizing:border-box}html,body{overflow-x:hidden}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:980px;margin:0 auto;padding:0 16px 80px;overflow-wrap:anywhere}
header.top{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--line);padding:8px 16px}
header.top .indre{max-width:980px;margin:0 auto;display:flex;flex-wrap:wrap;gap:6px 10px;align-items:center}
.bar{flex:1 1 180px;height:10px;background:var(--chip);border-radius:999px;overflow:hidden}
.bar i{display:block;height:100%;background:var(--ok-fg);width:0}
button,select,input[type=search],input[type=text],textarea{font:inherit;color:inherit;background:var(--card);
border:1px solid var(--line);border-radius:8px;padding:4px 10px}
button{cursor:pointer}button.primaer{background:var(--accent);color:var(--bg);border-color:var(--accent)}
.filtre label{margin-right:8px;white-space:nowrap}
h1{font-size:1.5rem;margin:.6em 0 .2em}h2{margin-top:1.6em;border-bottom:2px solid var(--line);padding-bottom:.2em}
.muted{color:var(--muted)}.kort{background:var(--card);border:1px solid var(--line);border-radius:10px;
padding:12px 14px;margin:12px 0;scroll-margin-top:120px}
.kort.aktiv{outline:3px solid var(--fokus);outline-offset:2px}.kort.besvaret{border-left:6px solid var(--ok-fg)}
.kort.mangler{border-left:6px solid var(--warn-fg)}
.kort h3{margin:0 0 .4em;font-size:1.1rem}.nr{color:var(--accent);font-weight:700;margin-right:.3em}
.chip{display:inline-block;background:var(--chip);border-radius:999px;padding:0 .6em;font-size:.85rem;margin-left:.3em}
.tvivl{background:var(--warn-bg);color:var(--warn-fg);border-radius:8px;padding:6px 10px;margin:6px 0}
.forslag{background:var(--ok-bg);color:var(--ok-fg);border-radius:999px;padding:0 .6em;font-size:.8rem;font-weight:600}
.vaelg{background:var(--warn-bg);color:var(--warn-fg);border-radius:999px;padding:0 .6em;font-size:.8rem;font-weight:600}
.tabel{overflow-x:auto;max-width:100%}table{border-collapse:collapse;width:100%;font-size:.9rem}
@media (max-width:600px){table{font-size:.8rem}th,td{padding:3px 4px}}
th,td{text-align:left;vertical-align:top;padding:4px 6px;border-top:1px solid var(--line)}
th{color:var(--muted);font-weight:600}ul{margin:.3em 0;padding-left:1.2em}
fieldset.valg{border:1px solid var(--line);border-radius:8px;margin:8px 0 0;padding:6px 10px}
fieldset.valg legend{font-weight:600;padding:0 4px}
fieldset.valg label{display:block;padding:4px 0;cursor:pointer}fieldset.valg label b{color:var(--accent)}
.hfelter{display:none;margin:6px 0 0 24px}.hfelter.vis{display:block}.hfelter label{display:block;margin:4px 0}
.hfelter input,.hfelter textarea,.hfelter select{width:100%}.fejl{color:var(--fejl);font-weight:600}
details summary{cursor:pointer;font-weight:600}code,kbd{font-size:.9em}
.skjult{display:none}#kopiboks{width:100%;height:8em;display:none}
.problem{margin:.2em 0 .5em}#aendret{display:none}#aendret.vis{display:block}
"""


def _raekker_html(f, medl, overlever):
    rk = []
    for m in medl:
        e = f.raekker[m]
        ejer = f.ejer_pr_gods.get(m, [])
        udg = {}
        for x in ejer:
            for k in x["kilder"]:
                u = k["udgave"].replace("DAA ", "")
                udg[u] = udg.get(u, 0) + 1
        per = "; ".join(f"{x['rid']}: {_e((x['periode'] or '').strip() or 'uden periode')}" for x in ejer)
        bil = ", ".join(f"media {_e(b['media_id'])} ({_e(b['slags'])}, relation {_e(b['rid'])})"
                        for b in f.media_pr_gods.get(m, []))
        maerker = []
        if m == overlever:
            maerker.append("bliver stående")
        if m in f.snapshots:
            maerker.append("slettet ejerforhold i historikken")
        rk.append(f"<tr><td>{m}</td><td>{_e(e['navn'])}{''.join(f'<span class=chip>{_e(x)}</span>' for x in maerker)}"
                  f"</td><td>{_e(', '.join(f'{u} ({n})' for u, n in sorted(udg.items(), reverse=True)) or '—')}</td>"
                  f"<td>{len(ejer)}{' — ' + per if per else ''}</td><td>{bil or '—'}</td>"
                  f"<td>{_e(e.get('sted') or '—')}</td></tr>")
    return ("<div class=tabel><table><tr><th>Række</th><th>Navn i databasen (bogens form)</th><th>Udgave</th>"
            "<th>Ejerforhold (antal — relation: periode)</th><th>Billeder</th><th>Sted</th></tr>" + "".join(rk) +
            "</table></div>")


def valg_hash(p) -> str:
    """Fingeraftryk af en posts valgmuligheder (koder og operationer, ikke teksten). Gemte svar i browseren
    genbruges kun, hvis fingeraftrykket er uændret."""
    ops = {k: {"adskilt": a.adskilt, **a.ops} for k, a in sorted(p.alternativer.items())}
    return hashlib.sha256(json.dumps([p.forvalg, ops], sort_keys=True, ensure_ascii=False)
                          .encode("utf-8")).hexdigest()[:16]


def _valg_html(pid: str, p, forvalg: str | None, legend: str = "Dit valg") -> str:
    ud = [f"<fieldset class=valg><legend>{_e(legend)}</legend>"]
    for kode, a in p.alternativer.items():
        checked = " checked" if forvalg == kode else ""
        maerke = " <span class=forslag>Forslag</span>" if p.forvalg == kode else ""
        ud.append(f"<label><input type=radio name=\"{_e(pid)}\" value=\"{_e(kode)}\"{checked}> "
                  f"<b>{_e(kode)}</b> — {_e(a.tekst)}{maerke}</label>")
    ud.append("</fieldset>")
    return "".join(ud)


def _flag_html(tvivl: list, info: list) -> str:
    tv = "".join(f"<div class=tvivl>{_e(t)}</div>" for t in tvivl)
    return tv + (("<ul>" + "".join(f"<li>{_e(t)}</li>" for t in info) + "</ul>") if info else "")


def _gruppe_html(f, g) -> str:
    pid = post_id(g)
    skal = g.forvalg is None
    kat = "tvivl" if skal else g.kategori
    maerke = " <span class=vaelg>Du skal vælge</span>" if skal else ""
    soeg = " ".join([str(g.nr), pid, g.navn] + [f.raekker[m]["navn"] or "" for m in g.medlemmer]).lower()
    hoved = (f"<h3><span class=nr>{g.nr}</span>{_e(g.navn)}<span class=chip>{_e(ART_ETIKET[g.art])}</span>"
             f"<span class=chip>{len(g.medlemmer)} række{'r' if len(g.medlemmer) > 1 else ''}</span>{maerke}</h3>")
    indhold = (f"<p class=problem><b>Hvad er problemet?</b> {_e(g.problem)}</p>" +
               _raekker_html(f, g.medlemmer, g.overlever) + _flag_html(g.tvivl, g.info))
    flere = len(g.alternativer) > 1
    if skal:
        valg = _valg_html(pid, g, None)
    elif kat == "enkel":
        valg = (f"<details><summary>ret</summary>{_valg_html(pid, g, g.forvalg)}</details>" if flere else
                f"<p class=muted>{_e(g.alternativer[g.forvalg].tekst)}</p>")
    else:
        valg = _valg_html(pid, g, g.forvalg) if flere else f"<p class=muted>{_e(g.alternativer[g.forvalg].tekst)}</p>"
    beslut = skal or flere
    attrs = (f"class=kort id=\"{pid}\" data-kat=\"{kat}\" data-skal=\"{1 if skal else 0}\" "
             f"data-forvalg=\"{_e(g.forvalg or '')}\" data-soeg=\"{_e(soeg)}\" data-valghash=\"{valg_hash(g)}\""
             + (f" data-id=\"{pid}\"" if beslut else ""))
    if kat == "enkel":
        return f"<section {attrs}>{hoved}<details><summary>vis rækker</summary>{indhold}</details>{valg}</section>"
    return f"<section {attrs}>{hoved}{indhold}{valg}</section>"


def _spoergsmaal_html(f, q, kilder: dict) -> str:
    pid = post_id(q)
    soeg = " ".join([pid, q.tekst] + [f.raekker[m]["navn"] or "" for m in q.medlemmer]).lower()
    ud = [f"<section class=kort id=\"{pid}\" data-id=\"{pid}\" data-kat=\"{pid[0]}\" data-skal=\"1\" data-forvalg=\"\" "
          f"data-soeg=\"{_e(soeg)}\" data-valghash=\"{valg_hash(q)}\"><h3><span class=nr>{_e(pid)}</span>{_e(q.tekst)} "
          f"<span class=vaelg>Du skal vælge</span></h3>",
          f"<p class=muted>Grupper: {', '.join(f'<a href=#G{n}>{n}</a>' for n in q.grupper)}</p>",
          _raekker_html(f, q.medlemmer, None), _flag_html([], q.info), _valg_html(pid, q, None, "Dit svar")]
    if pid.startswith("H"):
        hu = (q.alternativer["ja"].ops["hoerer_under"] or [{}])[0]
        valgt_kilde = hu.get("source")
        opts = "<option value=\"\">vælg udgave</option>" + "".join(
            f"<option value=\"{_e(sid)}\"{' selected' if sid == valgt_kilde else ''}>{_e(navn)}</option>"
            for navn, sid in sorted(kilder.items()) if navn.startswith("DAA"))
        ud.append(f"<div class=hfelter data-h=\"{pid}\"><p class=muted>Udfyld ved »ja«. Udgave og bogens ord skal "
                  f"med; perioden kan stå tom, hvis bogen ikke angiver den.</p>"
                  f"<label>Periode <input type=text name=\"{pid}-periode\" value=\"{_e(hu.get('periode') or '')}\" "
                  f"placeholder=\"fx 1729-1924\"></label>"
                  f"<label>Udgave <select name=\"{pid}-kilde\">{opts}</select></label>"
                  f"<label>Bogens ord (citat) <textarea name=\"{pid}-citat\" rows=2>{_e(hu.get('citat') or '')}"
                  f"</textarea></label><div class=fejl data-fejl=\"{pid}\"></div></div>")
    if "delvis" in q.alternativer:
        ud.append(f"<div class=hfelter data-delvis=\"{pid}\"><p class=muted>Sæt flueben ved de grupper, der er samme "
                  f"gods (mindst to):</p>" +
                  "".join(f"<label><input type=checkbox name=\"{pid}-gruppe\" value=\"G{n}\"> gruppe {n} "
                          f"({_e(next(g.navn for g in f.grupper if g.nr == n))})</label>" for n in q.grupper) +
                  f"<div class=fejl data-fejl=\"{pid}\"></div></div>")
    ud.append("</section>")
    return "".join(ud)


JS = r"""
(function () {
  "use strict";
  var META = JSON.parse(document.getElementById("meta").textContent);
  // Nøglen følger kun dataene; hvert svar bærer postens fingeraftryk (data-valghash), så et nyt ark genbruger
  // svar for uændrede poster og spørger igen, hvor valgmulighederne er ændret.
  var NOEGLE = "471-svar:" + META.kilde_hash.estate + ":" + META.kilde_hash.relation;
  var kort = Array.prototype.slice.call(document.querySelectorAll("section.kort"));
  var beslut = kort.filter(function (k) { return k.hasAttribute("data-id"); });
  var aktiv = null;
  function q(sel) { return document.querySelector(sel); }
  function felt(navn) { var el = document.querySelector('[name="' + navn + '"]'); return el ? el.value : ""; }
  function valgt(id) { var el = document.querySelector('input[name="' + id + '"]:checked'); return el ? el.value : null; }
  function hMangler(id) {
    var m = [];
    if (!felt(id + "-kilde")) m.push("udgave");
    if (!felt(id + "-citat").trim()) m.push("bogens ord");
    return m;
  }
  function delvisValgt(id) {
    return Array.prototype.map.call(document.querySelectorAll('input[name="' + id + '-gruppe"]:checked'),
                                    function (c) { return c.value; });
  }
  function besvaret(k) {
    var id = k.id, v = valgt(id);
    if (!v) return false;
    if (id.charAt(0) === "H" && v === "ja") return hMangler(id).length === 0;
    if (v === "delvis") return delvisValgt(id).length >= 2;
    return true;
  }
  function svar() {
    var ud = {};
    beslut.forEach(function (k) {
      var id = k.id, v = valgt(id);
      if (!v || !besvaret(k)) return;
      if (id.charAt(0) === "H") {
        var o = { svar: v };
        if (v === "ja") { o.periode = felt(id + "-periode").trim(); o.citat = felt(id + "-citat").trim();
                          o.kilde = Number(felt(id + "-kilde")); }
        ud[id] = o;
      } else if (v === "delvis") {
        ud[id] = { svar: "delvis", grupper: delvisValgt(id) };
      } else if (k.getAttribute("data-skal") === "1" || v !== k.getAttribute("data-forvalg")) {
        ud[id] = v;
      }
    });
    return { version: 1, kilde_hash: META.kilde_hash, plan_forslag_sha256: META.plan_sha, svar: ud };
  }
  function gem() {
    var tilstand = gemt_tilstand();
    beslut.forEach(function (k) {
      var v = valgt(k.id), o = { h: k.getAttribute("data-valghash"), v: v };
      // Et urørt forslag gemmes ikke: så giver et nyt ark ingen falsk besked om ændrede valg.
      if (v && k.getAttribute("data-skal") !== "1" && v === k.getAttribute("data-forvalg")) v = o.v = null;
      if (k.id.charAt(0) === "H" && v) { o.f = {}; ["periode", "citat", "kilde"].forEach(function (f) {
        o.f[f] = felt(k.id + "-" + f); }); }
      if (v === "delvis") o.g = delvisValgt(k.id);
      if (v) tilstand[k.id] = o; else delete tilstand[k.id];
    });
    try { window.localStorage.setItem(NOEGLE, JSON.stringify(tilstand)); q("#gemt").textContent = "Gemt i browseren"; }
    catch (e) { q("#gemt").textContent = "Kan ikke gemme i browseren — brug »Gem svar«"; }
  }
  function gemt_tilstand() {
    try { return JSON.parse(window.localStorage.getItem(NOEGLE) || "{}") || {}; } catch (e) { return {}; }
  }
  function hent() {
    var t = gemt_tilstand(), aendret = [];
    Object.keys(t).forEach(function (id) {
      var o = t[id], k = document.getElementById(id);
      if (!o || typeof o !== "object") return;
      if (!k || !k.hasAttribute("data-id") || k.getAttribute("data-valghash") !== o.h) {
        if (o.v) aendret.push(id);
        return;
      }
      if (o.v) { var r = k.querySelector('input[type=radio][value="' + String(o.v).replace(/"/g, "") + '"]');
                 if (r) r.checked = true; }
      if (o.f) Object.keys(o.f).forEach(function (f) { var el = k.querySelector('[name="' + id + "-" + f + '"]');
                                                        if (el) el.value = o.f[f]; });
      if (o.g) o.g.forEach(function (gid) { var c = k.querySelector('input[name="' + id + '-gruppe"][value="' +
                                                                     String(gid).replace(/"/g, "") + '"]');
                                             if (c) c.checked = true; });
    });
    if (aendret.length) {
      var b = q("#aendret");
      b.textContent = "Valgmulighederne er ændret siden sidst for " + aendret.join(", ") +
        " — dit tidligere svar er ikke brugt; svar venligst igen.";
      b.classList.add("vis");
    }
  }
  function opdater(uden_gem) {
    var skal = beslut.filter(function (k) { return k.getAttribute("data-skal") === "1"; });
    var n = 0;
    beslut.forEach(function (k) {
      var b = besvaret(k), id = k.id;
      if (k.getAttribute("data-skal") === "1") { if (b) n++; k.classList.toggle("besvaret", b); k.classList.toggle("mangler", !b); }
      if (id.charAt(0) === "H") {
        var ja = valgt(id) === "ja", hf = k.querySelector(".hfelter"), fe = k.querySelector("[data-fejl]");
        hf.classList.toggle("vis", ja);
        var m = ja ? hMangler(id) : [];
        fe.textContent = m.length ? "Mangler: " + m.join(" og ") : "";
      }
      var dv = k.querySelector("[data-delvis]");
      if (dv) {
        var del = valgt(id) === "delvis";
        dv.classList.toggle("vis", del);
        dv.querySelector("[data-fejl]").textContent = del && delvisValgt(id).length < 2 ? "Vælg mindst to grupper" : "";
      }
    });
    q("#taeller").textContent = n + " af " + skal.length + " besvaret";
    q(".bar i").style.width = (skal.length ? 100 * n / skal.length : 100) + "%";
    if (!uden_gem) gem();
  }
  function synlig(k) { return !k.classList.contains("skjult") && !k.closest(".afsnit.skjult"); }
  function filtrer() {
    var f = (document.querySelector("input[name=filter]:checked") || {}).value || "skal";
    var s = q("#soeg").value.trim().toLowerCase();
    kort.forEach(function (k) {
      var kat = k.getAttribute("data-kat"), ok;
      if (f === "skal") ok = k.getAttribute("data-skal") === "1";
      else if (f === "forslag") ok = kat === "aendring";
      else if (f === "enkle") ok = kat === "enkel";
      else ok = true;
      if (s) ok = ok && (k.getAttribute("data-soeg") || "").indexOf(s) >= 0;
      k.classList.toggle("skjult", !ok);
    });
    Array.prototype.forEach.call(document.querySelectorAll(".afsnit"), function (a) {
      a.classList.toggle("skjult", !a.querySelector("section.kort:not(.skjult)"));
    });
  }
  function saetAktiv(k) {
    if (aktiv) aktiv.classList.remove("aktiv");
    aktiv = k; if (!k) return;
    k.classList.add("aktiv"); k.scrollIntoView({ block: "start", behavior: "smooth" });
  }
  function flyt(trin, kunUbesvarede) {
    var liste = kort.filter(function (k) {
      return synlig(k) && (!kunUbesvarede || (k.getAttribute("data-skal") === "1" && !besvaret(k)));
    });
    if (!liste.length) { if (kunUbesvarede) window.alert("Alt er besvaret."); return; }
    var i = aktiv ? kort.indexOf(aktiv) : -1;
    var naeste = null;
    if (trin > 0) { naeste = liste.filter(function (k) { return kort.indexOf(k) > i; })[0] || liste[0]; }
    else { var f = liste.filter(function (k) { return kort.indexOf(k) < i; }); naeste = f[f.length - 1] || liste[liste.length - 1]; }
    saetAktiv(naeste);
  }
  function download() {
    var tekst = JSON.stringify(svar(), null, 1);
    var a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([tekst], { type: "application/json" }));
    a.download = "471-svar.json"; document.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }
  function kopier() {
    var tekst = JSON.stringify(svar(), null, 1), boks = q("#kopiboks");
    function reserve() {
      boks.style.display = "block"; boks.value = tekst; boks.select();
      var ok = false; try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
      q("#gemt").textContent = ok ? "Kopieret" : "Markér teksten i feltet og kopiér den selv";
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(tekst).then(function () { q("#gemt").textContent = "Kopieret"; }, reserve);
    } else reserve();
  }
  function alleSNej() {
    var mangler = beslut.filter(function (k) { return k.id.charAt(0) === "S" && !valgt(k.id); });
    if (!mangler.length) { window.alert("Ingen ubesvarede S-spørgsmål."); return; }
    if (!window.confirm("Sæt alle " + mangler.length + " ubesvarede S-spørgsmål til »nej«?")) return;
    mangler.forEach(function (k) { var r = k.querySelector('input[value="nej"]'); if (r) r.checked = true; });
    opdater();
  }
  document.addEventListener("change", function () { opdater(); });
  document.addEventListener("input", function (e) { if (e.target.closest(".hfelter")) opdater(); });
  // (afkrydsningsfelterne for »kun nogle« udløser »change« og dermed opdater)
  document.addEventListener("click", function (e) { var k = e.target.closest("section.kort"); if (k && k !== aktiv) {
    if (aktiv) aktiv.classList.remove("aktiv"); aktiv = k; k.classList.add("aktiv"); } });
  document.addEventListener("keydown", function (e) {
    var t = e.target;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (t && (t.tagName === "TEXTAREA" || t.tagName === "SELECT" || (t.tagName === "INPUT" && t.type !== "radio"))) return;
    if (e.key === "j") { flyt(1, false); e.preventDefault(); }
    else if (e.key === "k") { flyt(-1, false); e.preventDefault(); }
    else if (e.key === "n") { flyt(1, true); e.preventDefault(); }
    else if (/^[1-9]$/.test(e.key) && aktiv) {
      var r = aktiv.querySelectorAll("fieldset.valg input[type=radio]")[Number(e.key) - 1];
      if (r) { r.checked = true; opdater(); e.preventDefault(); }
    }
  });
  Array.prototype.forEach.call(document.querySelectorAll("input[name=filter]"), function (r) {
    r.addEventListener("change", filtrer); });
  q("#soeg").addEventListener("input", filtrer);
  q("#naeste").addEventListener("click", function () { flyt(1, true); });
  q("#gem").addEventListener("click", download);
  q("#kopier").addEventListener("click", kopier);
  q("#snej").addEventListener("click", alleSNej);
  hent(); filtrer(); opdater(true);
})();
"""


def plan_tekst(plan: dict) -> str:
    return json.dumps(plan, ensure_ascii=False, indent=1) + "\n"


def plan_sha(plan: dict) -> str:
    return hashlib.sha256(plan_tekst(plan).encode("utf-8")).hexdigest()


def taelling(f, plan: dict) -> dict:
    return {
        "grupper": len(f.grupper),
        "grupper_flere_raekker": sum(1 for g in f.grupper if len(g.medlemmer) > 1),
        "grupper_uden_forvalg": sum(1 for g in f.grupper if not g.forvalg),
        "spoergsmaal_S": len(f.sammenhaenge),
        "spoergsmaal_H": len(f.hoerer),
        "spoergsmaal_N": len(f.nye),
        "krenkerup": sum(1 for h in f.hoerer if h.krenkerup),
        **{f"plan_{k}": len(plan[k]) for k in OPS},
        "aabne": len(plan["aabne"]),
    }


def render_html(f, meta: dict) -> str:
    plan = f.plan(meta.get("kilde_db", ""), meta.get("kilde_hash", {}))
    sha = meta.get("plan_sha") or plan_sha(plan)
    t = taelling(f, plan)
    tvivl = [g for g in f.grupper if g.forvalg is None]
    aendr = [g for g in f.grupper if g.forvalg and g.kategori == "aendring"]
    enkel = [g for g in f.grupper if g.forvalg and g.kategori == "enkel"]
    kh = meta.get("kilde_hash", {})
    meta_json = json.dumps({"kilde_hash": kh, "plan_sha": sha}).replace("</", "<\\/")
    dele = [
        "<!doctype html><html lang=da><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'><title>Godser forslagsark</title>"
        f"<style>{CSS}</style></head><body>",
        f"<script type=application/json id=meta>{meta_json}</script>",
        "<header class=top><div class=indre><strong>Godser #471</strong>"
        "<div class=bar><i></i></div><span id=taeller></span>"
        "<button id=naeste class=primaer title='Tast n'>Næste ubesvarede</button>"
        "<button id=gem>Gem svar</button><button id=kopier>Kopiér svar</button>"
        "<span id=gemt class=muted></span></div>"
        "<div class='indre filtre'><span class=muted>Vis:</span>"
        "<label><input type=radio name=filter value=skal checked> Skal afgøres</label>"
        "<label><input type=radio name=filter value=forslag> Forslag</label>"
        "<label><input type=radio name=filter value=enkle> Enkle</label>"
        "<label><input type=radio name=filter value=alle> Alle</label>"
        "<input type=search id=soeg placeholder='Søg navn eller nummer' aria-label=Søg></div></header><main>",
        "<h1>Godserne: dine valg</h1>",
        "<div class=kort><b>Sådan gør du</b><ul>"
        "<li>Vælg et svar ved hvert kort. Står der <span class=vaelg>Du skal vælge</span>, er intet valgt på "
        "forhånd. Står der <span class=forslag>Forslag</span>, er forslaget valgt, men du kan ændre det.</li>"
        "<li>Dine valg gemmes i browseren, mens du arbejder. Når du er færdig: tryk <b>Gem svar</b> (henter "
        "filen <code>471-svar.json</code>) eller <b>Kopiér svar</b>, og giv filen eller teksten videre.</li>"
        "<li>Taster: <kbd>n</kbd> næste ubesvarede, <kbd>j</kbd>/<kbd>k</kbd> næste/forrige kort, "
        "<kbd>1</kbd>-<kbd>9</kbd> vælger svar i det markerede kort.</li>"
        "<li>»Læg sammen« flytter ejerforhold og billeder over på den række, der bliver stående; bogens "
        "oprindelige formulering gemmes som citat, så intet går tabt. »Kopieres til« betyder, at bogen nævner flere "
        "gårde i ét navn, så samme ejerforhold også kommer til at stå på dem.</li>"
        "<li><b>Slags</b> er, hvad godset var: en gård, eller et majorat (grevskab, baroni, stamhus — en "
        "ejerform, der samlede flere gårde). »Ikke angivet« betyder, at vi ikke ved det (fx et len eller et "
        "herred).</li>"
        "<li>»Siden viser« er det navn, læseren ser på godsets side. Bogens fulde tekst går aldrig tabt: den "
        "gemmes ved hvert ejerforhold.</li>"
        "<li>Arket viser kun godsnavne, perioder og udgaver — aldrig hvem der ejede.</li></ul>"
        f"<p class=muted>{t['grupper']} grupper · {len(tvivl)} skal afgøres · {t['spoergsmaal_H']} om »hører "
        f"under« (H) · {t['spoergsmaal_S']} om navne der ligner hinanden (S) · kilde {_e(meta.get('kilde_db'))} · "
        f"estate-md5 {_e(kh.get('estate'))} · relation-md5 {_e(kh.get('relation'))} · plan-sha256 {_e(sha[:12])}…</p>"
        "<div id=aendret class=tvivl></div>"
        "<button id=snej>Alle ubesvarede S-spørgsmål: nej</button>"
        "<textarea id=kopiboks readonly aria-label='Svar til kopiering'></textarea></div>",
        f"<div class=afsnit><h2>Grupper, der skal afgøres ({len(tvivl)})</h2>",
        *(_gruppe_html(f, g) for g in tvivl), "</div>",
        f"<div class=afsnit><h2>Hører under (H, {len(f.hoerer)})</h2>"
        "<p class=muted>»Hører under« registreres kun, hvor bogen selv siger det.</p>",
        *(_spoergsmaal_html(f, h, f.kilder) for h in f.hoerer), "</div>",
        f"<div class=afsnit><h2>Navne der ligner hinanden (S, {len(f.sammenhaenge)})</h2>"
        "<p class=muted>Svar »ja«, hvis grupperne er samme gods. »Ja« lægger alle rækkerne ind i den første "
        "gruppes række og erstatter de andre gruppers egne sammenlægninger.</p>",
        *(_spoergsmaal_html(f, s_, f.kilder) for s_ in f.sammenhaenge), "</div>",
        f"<div class=afsnit><h2>Nye gårde med samme navn (N, {len(f.nye)})</h2>"
        "<p class=muted>To grupper vil hver oprette en ny side med samme navn.</p>",
        *(_spoergsmaal_html(f, q_, f.kilder) for q_ in f.nye), "</div>",
        f"<div class=afsnit><h2>Forslag ({len(aendr)})</h2>", *(_gruppe_html(f, g) for g in aendr), "</div>",
        f"<div class=afsnit><h2>Enkle rækker ({len(enkel)})</h2>"
        "<p class=muted>Navnet beholdes; kun arten sættes.</p>", *(_gruppe_html(f, g) for g in enkel), "</div>",
        f"</main><script>{JS}</script></body></html>",
    ]
    return "\n".join(dele)


# ---------------------------------------------------------------- svar → plan (fail-closed)

class FletFejl(PlanFejl):
    def __init__(self, fejl: list):
        self.fejl = fejl
        super().__init__("svarene kan ikke flettes:\n- " + "\n- ".join(fejl))


def _gruppe_af_estate(poster: dict) -> dict:
    return {m: pid for pid, x in poster.items() if x["type"] == "gruppe" for m in x["medlemmer"]}


def flet(forslag_plan: dict, forslag_sha: str, svar: dict, svar_bytes: bytes | None = None) -> tuple:
    """Projektejerens svar + plan.forslag.json → (plan, opsummering). Kaster FletFejl ved enhver uklarhed.

    S-»ja« (eller »delvis« med de afkrydsede grupper) erstatter de berørte gruppers egne sammenlægninger og navne;
    alle mål, der pegede på deres rækker, peger om. N-»ja« lader grupperne dele én ny gård. To overlevende sider med
    samme navn og slags afvises (læseren kan ikke skelne dem)."""
    fejl = []
    if not isinstance(svar, dict) or set(svar) != {"version", "kilde_hash", "plan_forslag_sha256", "svar"}:
        raise FletFejl(["svarfilen skal have præcis nøglerne version, kilde_hash, plan_forslag_sha256 og svar"])
    if svar["version"] != 1:
        fejl.append(f"ukendt version {svar['version']!r}")
    if svar["kilde_hash"] != forslag_plan.get("kilde_hash"):
        fejl.append("svarene er givet på andre data (kilde_hash passer ikke med plan.forslag.json)")
    if svar["plan_forslag_sha256"] != forslag_sha:
        fejl.append("svarene er givet på et andet forslag (plan_forslag_sha256 passer ikke)")
    alt, poster = forslag_plan["alternativer"], forslag_plan["poster"]
    kilde_ids = set(forslag_plan.get("kilder", {}).values())
    s_ = svar["svar"] if isinstance(svar["svar"], dict) else None
    if s_ is None:
        raise FletFejl(fejl + ["»svar« skal være et objekt"])
    valg = {}
    for pid, v in s_.items():
        if pid not in alt:
            fejl.append(f"{pid}: ukendt gruppe/spørgsmål")
            continue
        if pid[0] == "H":
            if not isinstance(v, dict) or not set(v) <= {"svar", "periode", "citat", "kilde"} or "svar" not in v:
                fejl.append(f"{pid}: svaret skal være {{svar, periode, citat, kilde}}")
                continue
            if not isinstance(v["svar"], str) or v["svar"] not in alt[pid]:
                fejl.append(f"{pid}: ukendt svar {v['svar']!r} (mulige: {', '.join(alt[pid])})")
                continue
            if v["svar"] == "ja":
                if not isinstance(v.get("citat"), str) or not v["citat"].strip():
                    fejl.append(f"{pid}: »ja« kræver bogens ord (citat) som tekst")
                if v.get("periode") is not None and not isinstance(v.get("periode"), str):
                    fejl.append(f"{pid}: perioden skal være tekst")
                k_ = v.get("kilde")
                if not isinstance(k_, int) or isinstance(k_, bool) or k_ not in kilde_ids:
                    fejl.append(f"{pid}: »ja« kræver udgaven som et af kilde-id'erne "
                                f"{', '.join(f'{i_} ({n_})' for n_, i_ in forslag_plan.get('kilder', {}).items())}")
            valg[pid] = v
        elif pid[0] == "S" and isinstance(v, dict):
            gl = poster[pid]["grupper"]
            if ("delvis" not in alt[pid] or set(v) != {"svar", "grupper"} or v["svar"] != "delvis"
                    or not isinstance(v["grupper"], list) or len(set(map(str, v["grupper"]))) < 2
                    or not set(map(str, v["grupper"])) <= set(gl) or len(set(v["grupper"])) != len(v["grupper"])):
                fejl.append(f"{pid}: »kun nogle« skal være {{svar: delvis, grupper: [mindst to af {', '.join(gl)}]}}")
                continue
            valg[pid] = {"svar": "delvis", "grupper": [g for g in gl if g in v["grupper"]]}
        else:
            if not isinstance(v, str) or v not in alt[pid] or v == "delvis":
                fejl.append(f"{pid}: ukendt valg {v!r} (mulige: {', '.join(k for k in alt[pid] if k != 'delvis')})")
                continue
            valg[pid] = {"svar": v}
    for pid in forslag_plan["aabne"]:
        if pid not in valg and not any(f.startswith(f"{pid}:") for f in fejl):
            fejl.append(f"{pid}: mangler svar")
    if fejl:
        raise FletFejl(fejl)

    def kode(pid):
        return valg[pid]["svar"] if pid in valg else forslag_plan["forvalg"].get(pid)

    # S: de grupper, der er samme gods (alle ved »ja«, de afkrydsede ved »delvis«), lægges ind i den første af dem.
    opsl, erstattet, s_valgt, s_ops = {}, set(), {}, []
    for pid, x in poster.items():
        if x["type"] != "S" or kode(pid) not in ("ja", "delvis"):
            continue
        gl = x["grupper"] if kode(pid) == "ja" else valg[pid]["grupper"]
        s_valgt[pid] = gl
        til = poster[gl[0]]["overlever"]
        for g in gl:
            if alt[g][kode(g)].get("adskilt") and len(poster[g]["medlemmer"]) > 1:
                fejl.append(f"{pid} siger, at {', '.join(gl)} er samme gods, men {g} er valgt »behold rækkerne "
                            f"adskilt« ({kode(g)}) — vælg ét af dem")
        for g in gl[1:]:
            for m in x["flyttes"][g]:
                opsl[m] = til
                s_ops.append({"fra": m, "til": til, "gruppe": pid})
            erstattet.add(g)
    if fejl:
        raise FletFejl(fejl)
    # N: delte nye gårde
    ny_om = {}
    for pid, x in poster.items():
        if x["type"] == "N" and kode(pid) == "ja":
            for noegle in x["noegler"].values():
                ny_om[noegle] = x["faelles"]

    ops = _tomme_ops()
    aendret = []
    for pid in forslag_plan["alternativer"]:
        k = kode(pid)
        if k is None:
            continue
        a = alt[pid][k]
        if pid in valg and pid in forslag_plan["forvalg"] and k != forslag_plan["forvalg"][pid]:
            aendret.append(f"{pid}: {k} (forslag {forslag_plan['forvalg'][pid]})")
        stk = {o: [dict(x) for x in a.get(o, [])] for o in OPS}
        if pid in erstattet:
            stk["sammenlaeg"] = []
            stk["saet"] = [x for x in stk["saet"] if x["estate"] not in opsl]
        if pid[0] == "H" and k == "ja" and pid in valg:
            for hu in stk["hoerer_under"]:
                hu["periode"] = (valg[pid].get("periode") or "").strip() or None
                hu["citat"] = valg[pid]["citat"].strip()
                hu["source"] = valg[pid]["kilde"]
        _laeg_til(ops, stk)
    _laeg_til(ops, {"sammenlaeg": s_ops})

    def om(x):
        return ny_om.get(x, opsl.get(x, x)) if isinstance(x, (int, str)) else x
    for o in ops["opret"]:
        if o["noegle"] in ny_om:
            o["noegle"] = ny_om[o["noegle"]]
    ops["opret"] = [o for i_, o in enumerate(ops["opret"])
                    if all(o["noegle"] != x["noegle"] for x in ops["opret"][:i_])]
    for o in ops["sammenlaeg"]:
        o["til"] = om(o["til"])
    ops["sammenlaeg"] = [o for o in ops["sammenlaeg"] if o["fra"] != o["til"]]
    for o in ops["kopier"] + ops["flyt"]:
        o["til"] = om(o["til"])
    for o in ops["hoerer_under"]:
        o["gaard"], o["majorat"] = om(o["gaard"]), om(o["majorat"])

    # Samme række må kun lægges sammen ét sted og kun have ét navn.
    set_fra = {}
    for o in ops["sammenlaeg"]:
        if o["fra"] in set_fra and set_fra[o["fra"]] != o["til"]:
            fejl.append(f"række {o['fra']} lægges sammen to steder ({set_fra[o['fra']]} og {o['til']})")
        set_fra[o["fra"]] = o["til"]
    ops["sammenlaeg"] = [o for i_, o in enumerate(ops["sammenlaeg"])
                         if all(o["fra"] != x["fra"] for x in ops["sammenlaeg"][:i_])]
    set_saet = {}
    for o in ops["saet"]:
        if o["estate"] in set_saet and (set_saet[o["estate"]]["navn"], set_saet[o["estate"]]["slags"]) != (
                o["navn"], o["slags"]):
            fejl.append(f"række {o['estate']} får to forskellige navne/slags "
                        f"(gruppe {set_saet[o['estate']]['gruppe']} og {o['gruppe']})")
        set_saet[o["estate"]] = o
    ops["saet"] = [o for o in ops["saet"] if set_saet[o["estate"]] is o and o["estate"] not in set_fra]
    # Kopier: samme kopi to gange er én; »hører under« med samme nøgle og forskelligt citat ville tabe et citat.
    ops["kopier"] = [o for i_, o in enumerate(ops["kopier"])
                     if all((o["relation"], o["til"]) != (x["relation"], x["til"]) for x in ops["kopier"][:i_])]
    hu_set = {}
    for o in ops["hoerer_under"]:
        n_ = (o["gaard"], o["majorat"], o["periode"], o["source"])
        if n_ in hu_set and hu_set[n_]["citat"] != o["citat"]:
            fejl.append(f"{hu_set[n_]['gruppe']} og {o['gruppe']} giver begge »hører under« {o['gaard']} → "
                        f"{o['majorat']} ({o['periode'] or 'uden periode'}, samme udgave) med forskellige citater; "
                        f"kun ét kan gemmes — ret perioden eller citatet i en af dem")
        hu_set.setdefault(n_, o)
    ops["hoerer_under"] = [o for o in ops["hoerer_under"]
                           if hu_set[(o["gaard"], o["majorat"], o["periode"], o["source"])] is o]

    # Navnekollision: to overlevende sider med samme navn og slags kan læseren ikke skelne.
    g_af = _gruppe_af_estate(poster)
    sider = {}
    for o in ops["saet"]:
        sider.setdefault((navn_ens(o["navn"]), o["slags"]), []).append((o["navn"], g_af.get(o["estate"],
                                                                                            str(o["gruppe"]))))
    for o in ops["opret"]:
        sider.setdefault((navn_ens(o["navn"]), o["slags"]), []).append(
            (o["navn"], o["noegle"].split(":")[1] if o["noegle"].count(":") == 2 else o["noegle"]))
    s_af = {}
    for q, x in poster.items():
        if x["type"] in ("S", "N"):
            for g in (x.get("grupper") or list(x.get("noegler", {}))):
                s_af.setdefault(g, set()).add(q)
    for (_nv, sl), liste in sider.items():
        if len(liste) < 2:
            continue
        hvem = sorted({h for _, h in liste})
        if len(hvem) == 1:
            fejl.append(f"{hvem[0]}: rækkerne holdes adskilt, men {len(liste)} af dem ville vise »{liste[0][0]}« "
                        f"({ART_ETIKET.get(sl, sl)}) — to sider med samme navn kan læseren ikke skelne; vælg »læg "
                        f"sammen« i {hvem[0]}")
            continue
        spm = sorted(set.intersection(*[s_af.get(h, set()) for h in hvem]))
        fejl.append(f"{' og '.join(hvem)} ville begge vise »{liste[0][0]}« ({ART_ETIKET.get(sl, sl)}) — to sider "
                    f"med samme navn kan læseren ikke skelne: " +
                    (f"svar ja i {', '.join(spm)}, eller " if spm else "") +
                    "vælg et andet navn (eller »uden kopier«) i en af grupperne")
    if fejl:
        raise FletFejl(fejl)
    svar_sha = hashlib.sha256(svar_bytes if svar_bytes is not None else
                              json.dumps(svar, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()
    plan = {"version": 1, "kilde_db": forslag_plan["kilde_db"], "kilde_hash": forslag_plan["kilde_hash"],
            **ops, "grundlag": {"plan_forslag_sha256": forslag_sha, "svar_sha256": svar_sha}}
    try:
        valider_plan(plan, set(forslag_plan.get("snapshots", [])))
    except PlanFejl as e:
        raise FletFejl([f"planen holder ikke: {e}"])
    forslag_tal = {k: len(forslag_plan[k]) for k in OPS}
    ops_ord = {"opret": "nye gårde", "saet": "navn/slags sat", "sammenlaeg": "sammenlægninger", "kopier": "kopier",
               "hoerer_under": "»hører under«", "flyt": "flytninger"}
    opsum = ["Planen efter dine svar (forslaget i parentes):"]
    opsum += [f"  {ops_ord[k]}: {len(plan[k])} ({forslag_tal[k]})" for k in OPS]
    opsum.append(f"  besvaret: {len(valg)} poster ({sum(1 for x in valg if x in forslag_plan['aabne'])} åbne), "
                 f"{len(aendret)} forslag ændret; S samme gods: {len(s_valgt)}; "
                 f"H-ja: {sum(1 for p_ in valg if p_[0] == 'H' and valg[p_]['svar'] == 'ja')}; "
                 f"N-ja: {sum(1 for p_ in valg if p_[0] == 'N' and valg[p_]['svar'] == 'ja')}")
    if aendret:
        opsum.append("  ændret: " + ", ".join(aendret))
    return plan, opsum


# ---------------------------------------------------------------- kørsel

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", help="prod-kopi (læses kun)")
    ap.add_argument("--ark", help="HTML-arkets sti, uden for repo'et")
    ap.add_argument("--plan", default=str(Path(__file__).resolve().parent / "plan.forslag.json"),
                    help="plan.forslag.json (skrives ved generering, læses ved --flet)")
    ap.add_argument("--flet", help="svarfil fra arket (471-svar.json): flet til en endelig plan")
    ap.add_argument("--plan-ud", help="den endelige plan (plan.json) ved --flet")
    a = ap.parse_args(argv)
    if a.flet:
        if not a.plan_ud:
            ap.error("--flet kræver --plan-ud")
        if Path(a.plan_ud).resolve() == Path(a.plan).resolve():
            print("FEJL — intet skrevet. --plan-ud må ikke være forslagsfilen selv", file=sys.stderr)
            return 1
        raa = Path(a.plan).read_bytes()
        try:
            forslag_plan = json.loads(raa.decode("utf-8"))
            svar_raa = Path(a.flet).read_bytes()
            svar = json.loads(svar_raa.decode("utf-8"))
        except (OSError, ValueError) as e:
            print(f"FEJL: kan ikke læse filerne: {e}", file=sys.stderr)
            return 2
        try:
            plan, opsum = flet(forslag_plan, hashlib.sha256(raa).hexdigest(), svar, svar_raa)
        except FletFejl as e:
            print(f"FEJL — intet skrevet. {e}", file=sys.stderr)
            return 1
        ud = Path(a.plan_ud)
        tmp = ud.with_name(ud.name + ".tmp")
        tmp.write_text(plan_tekst(plan), encoding="utf-8")
        tmp.replace(ud)
        print("\n".join(opsum))
        print(f"Skrev {ud} (sha256 {hashlib.sha256(ud.read_bytes()).hexdigest()})")
        return 0
    if not a.db or not a.ark:
        ap.error("--db og --ark er påkrævet (eller --flet)")
    ark = tjek_ark_sti(Path(a.ark))
    data, kilde_hash = hent_data(a.db)
    f = byg_forslag(data)
    plan = f.plan(a.db, kilde_hash)
    valider_plan(plan, f.snapshots)
    tekst = plan_tekst(plan)
    Path(a.plan).write_text(tekst, encoding="utf-8")
    ark.parent.mkdir(parents=True, exist_ok=True)
    ark.write_text(render_html(f, {"kilde_db": a.db, "kilde_hash": kilde_hash,
                                   "plan_sha": hashlib.sha256(tekst.encode("utf-8")).hexdigest()}),
                   encoding="utf-8")
    print(json.dumps({"kilde_db": a.db, "kilde_hash": kilde_hash, **taelling(f, plan)}, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
