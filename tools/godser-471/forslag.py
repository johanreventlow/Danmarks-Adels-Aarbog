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
ART_ETIKET = {"gård": "gård", "grevskab": "grevskab", "baroni": "baroni", "stamhus": "stamhus", None: "art ukendt"}
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
        hit = hit or next((_EMBEDE_RE.search(p) for p in parenteser if _EMBEDE_RE.search(p)), None)
        n.ikke_gaard = hit.group(0) if hit else None
    n.noegle = f"{art}:{_norm(n.hoved)}"
    return n


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


@dataclass
class Spoergsmaal:
    """S (ligner hinanden) eller H (hører under)."""
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
    raekker: dict
    navne: dict
    snapshots: set
    ejer_pr_gods: dict
    media_pr_gods: dict
    sprunget_over: list

    def poster(self):
        return list(self.grupper) + list(self.hoerer) + list(self.sammenhaenge)

    def plan(self, kilde_db: str, kilde_hash: dict) -> dict:
        ops, aabne, forvalg, alternativer = _tomme_ops(), [], {}, {}
        for p in self.poster():
            alternativer[str(p.nr)] = {k: {"tekst": a.tekst, **a.ops} for k, a in p.alternativer.items()}
            if p.forvalg:
                forvalg[str(p.nr)] = p.forvalg
                _laeg_til(ops, p.alternativer[p.forvalg].ops)
            else:
                aabne.append(p.nr)
        return {"version": 1, "kilde_db": kilde_db, "kilde_hash": kilde_hash, **ops,
                "aabne": aabne, "forvalg": forvalg, "alternativer": alternativer}


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
        """Et led i en liste → (mål, beskrivelse, tvivl-tekst eller None, eventuel ny-oprettelse)."""
        dn = parse_navn(del_navn)
        g = efter_gnoegle.get(f"{art}:{_norm(dn.hoved)}")
        if g is egen:
            return None, None, None, None
        if g:
            return g.overlever, f"{ART_ETIKET[art]}en {g.navn} (række {g.overlever}, gruppe {g.nr})", None, None
        fk = fold(dn.kerne or dn.hoved)
        lign = [x for x in grupper if x.art == art and x is not egen and fk and fk in loese(x)]
        if len(lign) == 1:
            x = lign[0]
            return (x.overlever, f"{ART_ETIKET[art]}en {x.navn} (række {x.overlever}, gruppe {x.nr})",
                    f"»{del_navn}« er lagt sammen med gruppe {x.nr} ({x.navn}) ud fra et løst navnematch — "
                    f"svar »ny«, hvis det er en anden {ART_ETIKET[art]}", None)
        ny_navn = dn.kerne or dn.hoved
        noegle = f"ny:{ny_navn}"
        tv = None
        naer = [x for x in grupper if x.art == art and x is not egen and fk and any(_naer(fk, b) for b in loese(x))]
        if naer:
            tv = (f"»{del_navn}« ligner " + ", ".join(f"gruppe {x.nr} ({x.navn})" for x in naer) +
                  f" — forslaget opretter en ny {ART_ETIKET[art]}; svar med gruppenummeret, hvis det er samme")
        return (noegle, f"en ny {ART_ETIKET[art]} {ny_navn}", tv,
                {"noegle": noegle, "navn": ny_navn, "slags": art})

    def kopier_for(m: int, g: Gruppe, dele: list, art: str, ops: dict, tvivl: list, info: list):
        for d in dele:
            maal, beskr, tv, ny = find_maal(d, art, g)
            if maal is None:
                continue
            if tv:
                tvivl.append(tv)
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
                                      "gruppe": g.nr})

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
            tvivl.append("parentesen nævner flere godser (»med …«); de kopieres ikke automatisk — sig til, "
                         "hvis ejerforholdet også skal stå på dem")
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
        a_tvivl, a_info = [], []
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
                kopier_for(m, g, n.dele, "gård" if n.liste == "med" else n.art, a, a_tvivl, a_info)
        billeder_flyt(g, a, a_info, a_tvivl)
        tvivl.extend(t for t in a_tvivl if t not in tvivl)
        info.extend(t for t in a_info if t not in info)

        def hvor(x):
            if isinstance(x, str):
                return f"den nye gård {x[3:]}"
            return f"række {x} ({gruppe_af[x].navn})" if x in gruppe_af else f"række {x}"

        def beskriv(ops):
            dele = []
            for s in ops["saet"]:
                gl = estates[s["estate"]]["navn"]
                hed = (f"beholder navnet »{gl}«" if s["navn"] == gl else f"får navnet »{s['navn']}« (før »{gl}«)")
                dele.append(f"række {s['estate']} {hed}, art {ART_ETIKET[s['slags']]}")
            for s in ops["sammenlaeg"]:
                ne = len(ejer_pr_gods.get(s["fra"], []))
                nb = len(media_pr_gods.get(s["fra"], []))
                dele.append(f"række {s['fra']} lægges ind i række {s['til']} ({ne} ejerforhold" +
                            (f" og {nb} billede" if nb else "") + " flyttes med)")
            for o in ops["opret"]:
                dele.append(f"ny {ART_ETIKET[o['slags']]} oprettes: {o['navn']}")
            for k in ops["kopier"]:
                dele.append(f"ejerforhold {k['relation']} kopieres til {hvor(k['til'])}")
            for f_ in ops["flyt"]:
                b = billede_af.get(f_["relation"])
                hvad = f"billedet (media {b['media_id']})" if b else f"ejerforhold {f_['relation']}"
                dele.append(f"{hvad} flyttes til {hvor(f_['til'])}")
            return "; ".join(dele) or "ingen ændring"

        alts = []
        if len(medl) > 1:
            alts.append(("A", "Læg sammen", a))
            adskilt = _tomme_ops()
            for m in medl:
                adskilt["saet"].append(saet(m, navne[m].original, g.art))
            alts.append(("C", "Behold rækkerne adskilt (kun art sættes)", adskilt))
        elif n_ov.liste == "og" and not all(_ligner_navn(d) and not _IKKE_GAARD_RE.search(d) for d in n_ov.dele):
            alts.append(("A", "Navn og art (listen ligner ikke flere gårde, så den deles ikke)", a))
            tvivl.append(f"»{n_ov.original}« er ikke oplagt en liste af gårde; ingen forvalg")
        elif n_ov.liste == "og":
            # Del op: første led bliver gården, de øvrige får en kopi af ejerforholdet.
            delt = _tomme_ops()
            d_tvivl, d_info = [], []
            maal, _, tv, ny = find_maal(n_ov.dele[0], g.art, g)
            if tv:
                d_info.append(tv)
            if isinstance(maal, int) and ov not in snapshots and ov not in andre:
                # Målets navn og art sættes af målets egen gruppe.
                delt["sammenlaeg"].append({"fra": ov, "til": maal, "gruppe": g.nr})
            else:
                delt["saet"].append(saet(ov, parse_navn(n_ov.dele[0]).hoved, g.art))
            kopier_for(ov, g, n_ov.dele[1:], g.art, delt, d_tvivl, d_info)
            info.extend(t for t in d_info + d_tvivl if t not in info)
            alts.append(("A", f"Del op: {' / '.join(n_ov.dele)} er hver sin gård", delt))
            alts.append(("C", "Behold som én række med bogens navn", a))
            tvivl.append("»og«-liste: er det flere gårde (del op) eller ét navn? Ingen forvalg")
        else:
            alts.append(("A", "Navn og art", a))
            renset = kanonisk_navn(n_ov)
            if a["saet"][0]["navn"] != renset:
                b = json.loads(json.dumps(a))
                b["saet"][0]["navn"] = renset
                alts.append(("B", "Som A, men uden parentes/»til« i navnet", b))
        if ikke_gaard and g.art == "gård":
            ekstra = []
            for kode, tekst, ops in alts:
                u = json.loads(json.dumps(ops))
                for s in u["saet"]:
                    s["slags"] = None
                ekstra.append((kode + "u", tekst + " — art ukendt (ikke en gård)", u))
            alts += ekstra
        for kode, tekst, ops in alts:
            g.alternativer[kode] = Alternativ(kode, f"{tekst}: {beskriv(ops)}", ops)
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
        mspan = [a for m in mg.medlemmer for e in ejer_pr_gods.get(m, []) for a in _aar(e["periode"])]
        evidens = []
        for m in mg.medlemmer:
            for b in media_pr_gods.get(m, []):
                mm = hs_re.match(b.get("titel") or "")
                if mm and _norm(mm.group("navn")) == base:
                    evidens.append((b, mm))
        par = [x for x in grupper if x.art == "gård" and (x.noegle.split(":", 1)[1] == base
                                                           or (loese(x) & loese(mg)))]
        for b, mm in evidens:
            if not any(_norm(mm.group("gaard")) == x.noegle.split(":", 1)[1] for x in par):
                par.append(None)  # gården findes ikke som række
        for gg in par:
            nr = f"H{len(hoerer) + 1}"
            h = Spoergsmaal(nr=nr, tekst="", medlemmer=list(mg.medlemmer) + (gg.medlemmer if gg else []),
                            grupper=[mg.nr] + ([gg.nr] if gg else []), majorat_gruppe=mg.nr,
                            gaard_gruppe=gg.nr if gg else None)
            ev = next(((b, mm) for b, mm in evidens
                       if gg is None or _norm(mm.group("gaard")) == gg.noegle.split(":", 1)[1]), None)
            ja = _tomme_ops()
            if gg is None:
                gnavn = ev[1].group("gaard").strip()
                gaard = f"ny:{gnavn}"
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
                           f"siger det ikke; svar »ja« med periode, udgave og bogens ord — eller »nej«.")
                if gg.noegle.split(":", 1)[1] != base:
                    h.info.append("navnene ligner kun hinanden (løst match)")
            h.alternativer["ja"] = Alternativ("ja", "Ja: gården hører under majoratet", ja)
            h.alternativer["nej"] = Alternativ("nej", "Nej: ingen »hører under«", _tomme_ops())
            if gg is not None:
                gspan = [a for m in gg.medlemmer for e in ejer_pr_gods.get(m, []) for a in _aar(e["periode"])]
                if mspan and gspan and min(mspan) <= min(gspan) and max(gspan) <= max(mspan):
                    h.krenkerup = True
                    h.info.append(f"Krenkerup-mønster: gårdens ejerperioder ({min(gspan)}-{max(gspan)}) ligger inden "
                                  f"for majoratets ({min(mspan)}-{max(mspan)}) — måske menes majoratet")
                    fl = _tomme_ops()
                    for m in gg.medlemmer:
                        for e in ejer_pr_gods.get(m, []):
                            fl["flyt"].append({"relation": e["rid"], "til": mg.overlever, "gruppe": nr})
                    h.alternativer["flyt"] = Alternativ(
                        "flyt", f"Gårdens ejerforhold flyttes til {mg.navn} (bogen mente majoratet)", fl)
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
                               f"bortset fra stavning eller en stedtilføjelse. Svar evt. kun for nogle af "
                               f"grupperne (fx »{nr} ja {rest[0].nr}, nej …«)."))
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
            "ja", f"Ja: alle rækker i gruppe {', '.join(str(x.nr) for x in rest)} lægges ind i række "
                  f"{hoved_g.overlever} (gruppe {hoved_g.nr}); det erstatter de gruppers egne sammenlægninger", ja)
        s.alternativer["nej"] = Alternativ("nej", "Nej: forskellige godser", _tomme_ops())
        sammenhaenge.append(s)
        for x in gs:
            x.info.append(f"ligner gruppe {', '.join(str(y.nr) for y in gs if y is not x)} — se {nr}")

    return Forslag(grupper=grupper, sammenhaenge=sammenhaenge, hoerer=hoerer, raekker=estates, navne=navne,
                   snapshots=snapshots, ejer_pr_gods=ejer_pr_gods, media_pr_gods=media_pr_gods,
                   sprunget_over=sorted(sammenlagt_allerede))


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
--warn-bg:#fff3e0;--warn-fg:#8a4b00;--ok-bg:#eaf5ea;--ok-fg:#25622b;--chip:#f1ede4}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#16150f;--fg:#ece8de;--muted:#a59f92;
--card:#1f1e17;--line:#38352b;--accent:#e0a85a;--warn-bg:#3a2a12;--warn-fg:#ffc77a;--ok-bg:#1c3220;--ok-fg:#8fd69a;
--chip:#2a2820}}
:root[data-theme="dark"]{--bg:#16150f;--fg:#ece8de;--muted:#a59f92;--card:#1f1e17;--line:#38352b;--accent:#e0a85a;
--warn-bg:#3a2a12;--warn-fg:#ffc77a;--ok-bg:#1c3220;--ok-fg:#8fd69a;--chip:#2a2820}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:980px;margin:0 auto;padding:16px;overflow-wrap:anywhere}
html,body{overflow-x:hidden}
h1{font-size:1.6rem;margin:.2em 0}h2{margin-top:2em;border-bottom:2px solid var(--line);padding-bottom:.2em}
.muted{color:var(--muted)}.kort{background:var(--card);border:1px solid var(--line);border-radius:10px;
padding:12px 14px;margin:12px 0}
.kort h3{margin:0 0 .4em;font-size:1.1rem}.nr{color:var(--accent);font-weight:700;margin-right:.3em}
.chip{display:inline-block;background:var(--chip);border-radius:999px;padding:0 .6em;font-size:.85rem;
margin-left:.3em}
.tvivl{background:var(--warn-bg);color:var(--warn-fg);border-radius:8px;padding:6px 10px;margin:6px 0}
.forslag{background:var(--ok-bg);color:var(--ok-fg);border-radius:999px;padding:0 .6em;font-size:.8rem;
font-weight:600}.vaelg{background:var(--warn-bg);color:var(--warn-fg);border-radius:999px;padding:0 .6em;
font-size:.8rem;font-weight:600}
.tabel{overflow-x:auto;max-width:100%}table{border-collapse:collapse;width:100%;font-size:.92rem}
@media (max-width:600px){table{font-size:.82rem}th,td{padding:3px 4px}}
th,td{text-align:left;vertical-align:top;padding:4px 6px;border-top:1px solid var(--line)}
th{color:var(--muted);font-weight:600}ul{margin:.3em 0;padding-left:1.2em}
.alt{margin:.3em 0}.alt b{color:var(--accent)}details summary{cursor:pointer;font-weight:600}
code{font-size:.9em}
"""


def _raekker_html(f: Forslag, medl: list, overlever: int | None) -> str:
    rk = []
    for m in medl:
        e = f.raekker[m]
        ejer = f.ejer_pr_gods.get(m, [])
        udg = {}
        for x in ejer:
            for k in x["kilder"]:
                u = k["udgave"].replace("DAA ", "")
                udg[u] = udg.get(u, 0) + 1
        perioder = [x["periode"] for x in ejer if (x["periode"] or "").strip()]
        uden = len(ejer) - len(perioder)
        per = "; ".join(_e(p) for p in perioder) + (f"{'; ' if perioder else ''}uden periode ×{uden}" if uden else "")
        bil = ", ".join(f"{_e(b['media_id'])} ({_e(b['slags'])})" for b in f.media_pr_gods.get(m, []))
        mærker = []
        if m == overlever:
            mærker.append("bliver stående")
        if m in f.snapshots:
            mærker.append("slettet ejerforhold i historikken")
        rk.append(f"<tr><td>{m}</td><td>{_e(e['navn'])}{''.join(f'<span class=chip>{_e(x)}</span>' for x in mærker)}"
                  f"</td><td>{_e(', '.join(f'{u} ({n})' for u, n in sorted(udg.items(), reverse=True)) or '—')}</td>"
                  f"<td>{len(ejer)}{': ' + per if per else ''}</td><td>{bil or '—'}</td>"
                  f"<td>{_e(e.get('sted') or '—')}</td></tr>")
    return ("<div class=tabel><table><tr><th>Række</th><th>Navn i databasen (bogens form)</th><th>Udgave</th>"
            "<th>Ejerforhold (perioder)</th><th>Billeder</th><th>Sted</th></tr>" + "".join(rk) + "</table></div>")


def _alternativer_html(p) -> str:
    ud = []
    for kode, a in p.alternativer.items():
        mærke = " <span class=forslag>Forslag</span>" if p.forvalg == kode else ""
        ud.append(f"<div class=alt><b>{_e(kode)}</b> — {_e(a.tekst)}{mærke}</div>")
    return "".join(ud)


def _gruppe_html(f: Forslag, g: Gruppe) -> str:
    vælg = "" if g.forvalg else " <span class=vaelg>Du skal vælge</span>"
    tv = "".join(f"<div class=tvivl>{_e(t)}</div>" for t in g.tvivl)
    info = ("<ul>" + "".join(f"<li>{_e(t)}</li>" for t in g.info) + "</ul>") if g.info else ""
    return (f"<section class=kort id=g{g.nr}><h3><span class=nr>{g.nr}</span>{_e(g.navn)}"
            f"<span class=chip>{_e(ART_ETIKET[g.art])}</span><span class=chip>{len(g.medlemmer)} "
            f"række{'r' if len(g.medlemmer) > 1 else ''}</span>{vælg}</h3>"
            f"{_raekker_html(f, g.medlemmer, g.overlever)}{tv}{info}{_alternativer_html(g)}</section>")


def _spoergsmaal_html(f: Forslag, s: Spoergsmaal) -> str:
    info = ("<ul>" + "".join(f"<li>{_e(t)}</li>" for t in s.info) + "</ul>") if s.info else ""
    return (f"<section class=kort id={_e(s.nr)}><h3><span class=nr>{_e(s.nr)}</span>{_e(s.tekst)} "
            f"<span class=vaelg>Du skal vælge</span></h3>"
            f"<p class=muted>Grupper: {', '.join(f'<a href=#g{n}>{n}</a>' for n in s.grupper)}</p>"
            f"{_raekker_html(f, s.medlemmer, None)}{info}{_alternativer_html(s)}</section>")


def taelling(f: Forslag, plan: dict) -> dict:
    return {
        "grupper": len(f.grupper),
        "grupper_flere_raekker": sum(1 for g in f.grupper if len(g.medlemmer) > 1),
        "grupper_uden_forvalg": sum(1 for g in f.grupper if not g.forvalg),
        "spoergsmaal_S": len(f.sammenhaenge),
        "spoergsmaal_H": len(f.hoerer),
        "krenkerup": sum(1 for h in f.hoerer if h.krenkerup),
        **{f"plan_{k}": len(plan[k]) for k in OPS},
        "aabne": len(plan["aabne"]),
    }


def render_html(f: Forslag, meta: dict) -> str:
    plan = f.plan(meta.get("kilde_db", ""), meta.get("kilde_hash", {}))
    t = taelling(f, plan)
    tvivl = [g for g in f.grupper if g.kategori == "tvivl"]
    aendr = [g for g in f.grupper if g.kategori == "aendring"]
    enkel = [g for g in f.grupper if g.kategori == "enkel"]
    kh = meta.get("kilde_hash", {})
    dele = [
        "<!doctype html><html lang=da><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'><title>Godser forslagsark</title>"
        f"<style>{CSS}</style></head><body><main>",
        "<h1>Godserne: forslag til oprydning</h1>",
        "<p class=muted>Issue #471, fase 1. Hver gruppe er rækker i databasen, som ser ud til at være samme gård "
        "eller samme majorat (grevskab, baroni, stamhus). Arket viser kun godsnavne, perioder og udgaver — aldrig "
        "hvem der ejede.</p>",
        "<div class=kort><b>Sådan svarer du</b><ul>"
        "<li>Skriv i chatten nummeret og bogstavet, fx <code>12 C</code>, <code>S3 nej</code> eller "
        "<code>H2 ja 1729-1924 »bogens ord«</code>.</li>"
        "<li>Står der <span class=forslag>Forslag</span> ved et valg, og er du enig, behøver du ikke svare.</li>"
        "<li>Står der <span class=vaelg>Du skal vælge</span>, er der tvivl, og intet er valgt på forhånd.</li>"
        "<li>»Læg sammen« flytter ejerforhold og billeder over på den række, der bliver stående; den tomme række "
        "skjules og henviser videre. Bogens oprindelige formulering gemmes som citat på hvert ejerforhold, så "
        "intet går tabt.</li>"
        "<li>»Kopieres til« betyder: bogen nævner flere gårde i ét navn (»X med Y og Z«), så samme ejerforhold "
        "kommer også til at stå på Y og Z.</li></ul></div>",
        f"<div class=kort><b>Overblik</b><ul><li>{t['grupper']} grupper ({t['grupper_flere_raekker']} med flere "
        f"rækker), {len(f.raekker) - len(f.sprunget_over)} rækker</li>"
        f"<li>{len(tvivl)} grupper skal afgøres, {len(aendr)} har et forslag, {len(enkel)} er enkle</li>"
        f"<li>{t['spoergsmaal_H']} spørgsmål om »hører under« (H), {t['spoergsmaal_S']} om navne, der ligner "
        f"hinanden (S)</li>"
        f"<li>Forslaget i alt: {t['plan_sammenlaeg']} sammenlægninger, {t['plan_opret']} nye gårde, "
        f"{t['plan_kopier']} kopier, {t['plan_flyt']} flytninger, {t['plan_hoerer_under']} »hører under«</li>"
        f"</ul><p class=muted>Kilde: {_e(meta.get('kilde_db'))} · estate-md5 {_e(kh.get('estate'))} · "
        f"relation-md5 {_e(kh.get('relation'))}</p></div>",
        f"<h2>1. Skal afgøres ({len(tvivl)})</h2>",
        *(_gruppe_html(f, g) for g in tvivl),
        f"<h2>2. Hører under (H, {len(f.hoerer)})</h2>"
        "<p class=muted>»Hører under« registreres kun, hvor bogen selv siger det.</p>",
        *(_spoergsmaal_html(f, h) for h in f.hoerer),
        f"<h2>3. Navne der ligner hinanden (S, {len(f.sammenhaenge)})</h2>"
        "<p class=muted>Ingen af disse er valgt på forhånd. Svar »ja«, hvis de to grupper er samme gods.</p>",
        *(_spoergsmaal_html(f, s) for s in f.sammenhaenge),
        f"<h2>4. Sammenlægninger og omdøbninger med forslag ({len(aendr)})</h2>",
        *(_gruppe_html(f, g) for g in aendr),
        f"<h2>5. Enkeltrækker uden tvivl ({len(enkel)})</h2>"
        "<p class=muted>Navnet beholdes; kun arten sættes. Svar kun, hvis du er uenig.</p>"
        "<details><summary>Vis alle</summary>",
        *(_gruppe_html(f, g) for g in enkel),
        "</details></main></body></html>",
    ]
    return "\n".join(dele)


# ---------------------------------------------------------------- kørsel

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", required=True, help="prod-kopi (læses kun)")
    ap.add_argument("--ark", required=True, help="HTML-arkets sti, uden for repo'et")
    ap.add_argument("--plan", required=True, help="plan-filen (plan.forslag.json)")
    a = ap.parse_args(argv)
    ark = tjek_ark_sti(Path(a.ark))
    data, kilde_hash = hent_data(a.db)
    f = byg_forslag(data)
    plan = f.plan(a.db, kilde_hash)
    valider_plan(plan, f.snapshots)
    Path(a.plan).write_text(json.dumps(plan, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    ark.parent.mkdir(parents=True, exist_ok=True)
    ark.write_text(render_html(f, {"kilde_db": a.db, "kilde_hash": kilde_hash}), encoding="utf-8")
    print(json.dumps({"kilde_db": a.db, "kilde_hash": kilde_hash, **taelling(f, plan)}, ensure_ascii=False,
                     indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
