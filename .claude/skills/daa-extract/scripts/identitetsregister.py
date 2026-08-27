#!/usr/bin/env python3
"""Identitetsregister for trykte bogposter.

FORMÅLET: en bogpost skal kunne genfindes på tværs af re-ekstraktioner, så
redaktionelt arbejde (match, rettelser, sletninger) overlever at bogen læses
igen. Alle tidligere identitetsforsøg brød på samme måde: de brugte noget
BEREGNET — et løbenummer, en optælling, en position i vores egen segmentering.
Alt beregnet kan falde anderledes ud næste gang beregningen kører.

Reglen her: **identitet udstedes, den udledes ikke.** Et opaque id mintes ÉN
gang og skrives i registeret sammen med en fysisk lokator. Ved en senere
ekstraktion genfindes posten via lokatoren — og er den ikke entydig, stopper vi
frem for at gætte.

LOKATOREN er (udgave, side, lokal_id) — den nuværende adresse, med KENDTE
svagheder (Codex-review 2026-07-29): `side` er i praksis PDF-sideordinal, ikke
bogens trykte tal (59/515 poster afviger allerede mellem register og artefakt),
og `lokal_id` er LLM-genereret i 42 forskellige formater. Entydighed i ét
øjebliksbillede (515/515 med side) er IKKE stabilitet på tværs af udtræk —
dét måler test_perturbation.py, og kravet dér er nul FORKERTE match.

Lokatoren behøver ikke være perfekt stabil. Den skal være god nok til at
FORESLÅ et match; tvetydighed er et lovligt udfald der kræver en menneskelig
afgørelse. Det er forskellen på en nøgle og et gæt.

Registeret rydder ALDRIG selv op: en post der er forsvundet fra udtrækket
meldes som bortfalden, men tombstones ikke automatisk. Bortfald kan lige så vel
betyde en segmenteringsfejl som en rigtig sletning.

PII: registeret indeholder kun id, side, strukturel sti og status — ingen navne
eller datoer. Det kan derfor versionsstyres, i modsætning til artefakterne.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from typing import Iterable


def record_provenance_key(record_key: object, external_person_number: object) -> tuple[str, str | None]:
    """Stabil provenance for personaafgørelser ved genudtræk.

    Bogens `(linje,nr)` er en lokator, ikke en identitet. Et record_key er
    obligatorisk; eksternt personnummer styrker nøglens præcision, men kan være
    ukendt uden at vi opfinder en værdi.
    """
    if not isinstance(record_key, str) or not record_key.strip():
        raise ValueError("record_key kræves for persona-provenance")
    if external_person_number is None or str(external_person_number).strip() == "":
        return record_key, None
    return record_key, str(external_person_number)


@dataclass(frozen=True)
class Lokator:
    """Hvor i den trykte bog posten står. Nøglen registeret slår op på."""
    udgave: str
    side: str
    lokal_id: str

    def key(self) -> str:
        return f"{self.udgave}|{self.side}|{self.lokal_id}"


@dataclass
class Post:
    book_post_id: str
    lokator: Lokator
    status: str = "aktiv"          # aktiv | tombstone
    begrundelse: str | None = None


@dataclass
class Reconciliation:
    """Udfaldet af at holde et nyt udtræk op mod registeret."""
    entydige: list = field(default_factory=list)    # [(post_dict, book_post_id)]
    tvetydige: list = field(default_factory=list)   # [(post_dict, [kandidat-id'er], grund)]
    nye: list = field(default_factory=list)         # [post_dict] — ingen kandidat
    bortfaldne: list = field(default_factory=list)  # [Lokator] — i registeret, ikke i udtrækket


class Register:
    def __init__(self, poster: dict[str, Post] | None = None):
        self.poster: dict[str, Post] = poster or {}

    # --- opslag ---
    def find(self, lok: Lokator) -> Post | None:
        return self.poster.get(lok.key())

    def tombstone(self, lok: Lokator, begrundelse: str) -> None:
        p = self.poster.get(lok.key())
        if p is None:
            raise KeyError(f"ukendt lokator: {lok.key()}")
        p.status = "tombstone"
        p.begrundelse = begrundelse

    # --- persistens ---
    def to_json(self) -> str:
        # Sorteret på lokator-nøgle, så filen er deterministisk og git-diffs læsbare.
        return json.dumps({
            "version": 1,
            "poster": [
                {
                    "book_post_id": p.book_post_id,
                    "udgave": p.lokator.udgave,
                    "side": p.lokator.side,
                    "lokal_id": p.lokator.lokal_id,
                    "status": p.status,
                    **({"begrundelse": p.begrundelse} if p.begrundelse else {}),
                }
                for _, p in sorted(self.poster.items())
            ],
        }, ensure_ascii=False, indent=1, sort_keys=False)

    @classmethod
    def from_json(cls, data: dict) -> "Register":
        reg = cls()
        for r in data.get("poster", []):
            lok = Lokator(r["udgave"], r["side"], r["lokal_id"])
            reg.poster[lok.key()] = Post(
                book_post_id=r["book_post_id"], lokator=lok,
                status=r.get("status", "aktiv"), begrundelse=r.get("begrundelse"),
            )
        return reg


def _lokator(post: dict, udgave: str) -> Lokator:
    side, lokal_id = post.get("side"), post.get("lokal_id")
    # Fail-closed ved grænsen (Codex-review 2026-07-29, fund 1): str(None) blev
    # til den GYLDIGE nøgle "1939|None|None", så poster uden lokator kunne både
    # mintes og matches. Registeret afviser dem nu selv — R9-gaten i validate
    # er første forsvarslinje, dette er den sidste.
    if not side or not lokal_id:
        raise ValueError(
            f"post uden komplet lokator (side={side!r}, lokal_id={lokal_id!r}) — "
            "kør paahaeft_lokator + R9-gaten før registeret")
    return Lokator(udgave, str(side), str(lokal_id))


def mint(reg: Register, poster: Iterable[dict], udgave: str) -> Register:
    """Udsted id for poster der ikke har et. Idempotent.

    Afviser hvis to poster deler lokator — da kan de ikke skelnes, og et id
    ville blive tildelt vilkårligt.
    """
    poster = list(poster)
    set_ = set()
    for p in poster:
        k = _lokator(p, udgave).key()
        if k in set_:
            raise ValueError(f"dublet-lokator i udtrækket: {k}")
        set_.add(k)

    for p in poster:
        lok = _lokator(p, udgave)
        if lok.key() in reg.poster:
            continue                      # allerede mintet — rør den ikke
        reg.poster[lok.key()] = Post(book_post_id=str(uuid.uuid4()), lokator=lok)
    return reg


def _sidetal(s: str) -> int | None:
    try:
        return int(s)
    except (TypeError, ValueError):
        return None


def _inden_for(side_a: str, side_b: str, vindue: int) -> bool:
    a, b = _sidetal(side_a), _sidetal(side_b)
    if a is None or b is None:
        return True   # kan ikke afstandsmåles → konservativt: tæl med
    return abs(a - b) <= vindue


def reconcile(reg: Register, poster: Iterable[dict], udgave: str,
              drift_vindue: int = 10) -> Reconciliation:
    """Hold et nyt udtræk op mod registeret. Gætter aldrig.

    * lokator findes og er aktiv → entydigt genbrug af id — MEDMINDRE en anden
      aktiv post deler lokal_id inden for `drift_vindue` sider. Så kan hittet
      ikke skelnes fra sidedrift (perturbationstesten viste at et eksakt hit
      under drift kan være en NABOS nøgle), og udfaldet er TVETYDIGT.
      Vinduet er valgt fra empiri: observeret drift ≤ ~6 sider, delte
      lokal_id'er mindst 15 sider fra hinanden (målt 2026-07-29).
    * lokator findes ikke, men `lokal_id` gør på en anden side → TVETYDIG.
      Posten kan være flyttet, eller det kan være en anden post. Kræver
      menneskelig afgørelse.
    * hverken lokator eller `lokal_id` kendes → ny post
    * i registeret, ikke i udtrækket → bortfalden (meldes, tombstones IKKE)
    """
    poster = list(poster)   # itereres to gange — en generator ville være tom i 2. løkke
    res = Reconciliation()
    set_i_udtraek: set[str] = set()

    fra_lokal_id: dict[str, list[Post]] = {}
    for q in reg.poster.values():
        if q.status == "aktiv" and q.lokator.udgave == udgave:
            fra_lokal_id.setdefault(q.lokator.lokal_id, []).append(q)

    # Samme vagt som mint(): to poster med samme lokator kan ikke skelnes, og
    # uden dette tjek ville BEGGE tavst få det samme book_post_id tildelt.
    # (Codex-review 2026-07-29: kontrollen fandtes kun i mint.)
    seet: set[str] = set()
    for p in poster:
        k = _lokator(p, udgave).key()
        if k in seet:
            raise ValueError(f"dublet-lokator i udtrækket: {k}")
        seet.add(k)

    for p in poster:
        lok = _lokator(p, udgave)
        set_i_udtraek.add(lok.key())
        kendt = reg.poster.get(lok.key())
        if kendt is not None and kendt.status == "aktiv":
            naboer = [q.book_post_id for q in fra_lokal_id.get(lok.lokal_id, ())
                      if q.lokator.key() != lok.key()
                      and _inden_for(q.lokator.side, lok.side, drift_vindue)]
            if naboer:
                res.tvetydige.append((p, [kendt.book_post_id, *naboer],
                                      f"eksakt hit, men delt lokal_id inden for {drift_vindue} siders drift"))
            else:
                res.entydige.append((p, kendt.book_post_id))
            continue
        if kendt is not None:                     # tombstone: må ikke genopstå
            res.nye.append(p)
            continue
        kandidater = [q.book_post_id for q in fra_lokal_id.get(lok.lokal_id, ())]
        if kandidater:
            res.tvetydige.append((p, kandidater, "samme lokal_id, anden side"))
        else:
            res.nye.append(p)

    for k, q in reg.poster.items():
        if q.status == "aktiv" and q.lokator.udgave == udgave and k not in set_i_udtraek:
            res.bortfaldne.append(q.lokator)
    return res
