#!/usr/bin/env python3
"""Om-nøgl registeret fra LLM-æraens lokatorer til bogens trykte adresse.

BRO-PRINCIPPET: gammel artefaktpost og ny segmentpost kommer fra SAMME
kildetekst, så de matches på tekst-anker — aldrig på ordinaler. record_key i
det gamle artefakt ER registerets book_post_id (verificeret 515/515), så et
tekstmatch flytter id'ets adresse uden at røre id'et.

MATCHREGLER (fail-closed, i rækkefølge):
  1. Normalisér begge tekster (soft hyphens ud, kun alfanumerisk, lowercase);
     strip det trykte nummer-præfiks fra den gamle narrativ ("3. Hr. Eler…").
  2. Kandidat = ny post hvis prefix (70 tegn) står i den gamle narrativ,
     eller omvendt. Afhuggede gamle starter dækkes af et ekstra midtervindue.
  3. Én kandidat → match. Flere → afgør med bogens eget trykte nummer
     (gammel _orig_nr == ny nr_label); ellers TVETYDIG (menneske).
     De tvetydige er typisk 18%-problemets delte gruppe-narrativer, som
     matcher alle gruppens nye poster.
  4. Intet match → posten forbliver med sin gamle lokator og bliver
     BORTFALDEN ved reconcile (indledningens oversigtsposter og stamfædrene
     er bevidst udeladt af v1-segmenteringen — de SKAL ende her).

Den gamle lokator gemmes i `begrundelse` (versioneret observation — mint
aldrig om, flyt adressen og lad id'et stå). Tombstones røres ikke.

Kør:
  python3 omnoegl_lokator.py --nye <ny-segmentering.json> [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
from datetime import date
from pathlib import Path

from identitetsregister import Lokator, Post, Register, reconcile

WORK = Path(__file__).resolve().parents[4] / "work_1939_stamtavle"
PREFIX = 70


def _norm(s: str | None) -> str:
    s = (s or "").replace("­", "")
    return re.sub(r"[\W_]+", "", s).lower()


def _gammel_kerne(narrativ: str | None) -> str:
    """Gammel narrativ uden det trykte nummer-præfiks ("3. Hr. Eler…")."""
    return _norm(re.sub(r"^\s*\d{1,3}[a-z]?\.\s*", "", narrativ or ""))


def _side_af(p: dict) -> str | None:
    s = p.get("sider")
    if isinstance(s, list):
        s = s[0] if s else None
    if s and "-" in str(s):
        s = str(s).split("-")[0]
    return str(s) if s else None


def match_poster(gamle: list[dict], nye: list[dict]) -> dict:
    """Returnér {'match': [(gammel, ny)], 'tvetydige': [...], 'umatchede': [...]}."""
    ny_norm = [(p, _norm(p.get("raw_text"))) for p in nye]
    ud = {"match": [], "tvetydige": [], "umatchede": []}
    for g in gamle:
        gn = _gammel_kerne(g.get("narrative"))
        vinduer = [v for v in (gn[:PREFIX], gn[120:120 + PREFIX]) if len(v) >= 40]
        kandidater = []
        for p, t in ny_norm:
            tp = t[:PREFIX]
            if (tp and tp in gn) or any(v in t for v in vinduer):
                kandidater.append(p)
        if len(kandidater) > 1:
            # bogens eget trykte nummer afgør — aldrig position eller rækkefølge
            trykt = str(g.get("_orig_nr") or "")
            praecise = [p for p in kandidater if str(p.get("nr_label")) == trykt]
            if len(praecise) == 1:
                kandidater = praecise
        if len(kandidater) == 1:
            ud["match"].append((g, kandidater[0]))
        elif kandidater:
            ud["tvetydige"].append((g, [p["lokal_id"] for p in kandidater]))
        else:
            ud["umatchede"].append(g)

    # INJEKTIVITET (Codex-review 2026-07-29): en ny post må kun vindes af ÉN
    # gammel. Vinder to gamle samme nye post, kan ingen af dem skelnes —
    # begge demoteres til tvetydige frem for at den ene tavst tager adressen.
    vundet: dict[str, list] = {}
    for g, ny in ud["match"]:
        vundet.setdefault(ny["lokal_id"], []).append((g, ny))
    rene, kolliderede = [], []
    for lokal_id, par in vundet.items():
        if len(par) == 1:
            rene.extend(par)
            continue
        # bogens trykte nummer som sidste voldgift — præcis én af de gamle
        # må bære den nye posts nr_label, ellers er ingen til at stole på
        ny = par[0][1]
        praecise = [pr for pr in par
                    if str(pr[0].get("_orig_nr")) == str(ny.get("nr_label"))]
        if len(praecise) == 1:
            rene.append(praecise[0])
            kolliderede.extend(pr for pr in par if pr is not praecise[0])
        else:
            kolliderede.extend(par)
    ud["match"] = rene
    for g, ny in kolliderede:
        ud["tvetydige"].append((g, [ny["lokal_id"], "(delt med anden gammel post)"]))
    return ud


def omnoegl(reg: Register, par: list[tuple[dict, dict]], udgave: str) -> list[tuple[str, str, str]]:
    """Flyt matchede posters lokator til den nye trykte adresse. To-faset."""
    key_af_id = {p.book_post_id: k for k, p in reg.poster.items()}
    planer = []
    for gammel, ny in par:
        bid = gammel.get("record_key")
        if not bid or bid not in key_af_id:
            continue
        ny_lok = Lokator(udgave, _side_af(ny), str(ny["lokal_id"]))
        k = key_af_id[bid]
        if reg.poster[k].lokator.key() == ny_lok.key():
            continue
        planer.append((k, reg.poster[k], ny_lok))

    for k, _, _ in planer:
        del reg.poster[k]
    aendringer = []
    for k, p, ny_lok in planer:
        if ny_lok.key() in reg.poster:
            raise ValueError(f"om-nøgling ville kollidere: {ny_lok.key()}")
        note = (f"om-nøglet {p.lokator.side}|{p.lokator.lokal_id} → "
                f"{ny_lok.side}|{ny_lok.lokal_id} (tekst-anker, trykt skema 2026-07-30)")
        if p.begrundelse:
            note += f"; tidligere: {p.begrundelse}"
        reg.poster[ny_lok.key()] = Post(
            book_post_id=p.book_post_id, lokator=ny_lok, status=p.status, begrundelse=note)
        aendringer.append((p.book_post_id, p.lokator.key(), ny_lok.key()))
    return aendringer


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--register", type=Path, default=WORK / "identitetsregister-1939.json")
    ap.add_argument("--artefakt", type=Path, default=WORK / "clean_1939.json")
    ap.add_argument("--nye", type=Path, required=True,
                    help="ny segmentering (segment.py --udgave 1939-output)")
    ap.add_argument("--udgave", default="1939")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    reg = Register.from_json(json.loads(a.register.read_text(encoding="utf-8")))
    gamle = json.loads(a.artefakt.read_text(encoding="utf-8"))
    nye = json.loads(a.nye.read_text(encoding="utf-8"))
    nye = [p for p in nye if p.get("lokal_id")]

    res = match_poster(gamle, nye)
    print(f"match: {len(res['match'])} · tvetydige: {len(res['tvetydige'])} · "
          f"umatchede gamle: {len(res['umatchede'])}")

    # BLOKERENDE krydstjek: tekst-ankeret og bogens trykte nummer er to
    # uafhængige signaler — er de uenige om bare ét match, stoler vi ikke på
    # nogen af dem. (Målt ved indførelsen: 417/417 enige.)
    uenige = [(g.get("_lokal_id"), ny["lokal_id"]) for g, ny in res["match"]
              if str(g.get("_orig_nr")) != str(ny.get("nr_label"))]
    if uenige:
        for u in uenige[:10]:
            print(f"   NUMMER-UENIG: {u}")
        raise SystemExit("tekst-anker og trykt nummer uenige — registeret er IKKE skrevet")
    for g, kand in res["tvetydige"]:
        print(f"   TVETYDIG {g.get('_lokal_id')}: {kand[:3]}{'…' if len(kand) > 3 else ''}")

    aendringer = omnoegl(reg, res["match"], a.udgave)
    print(f"om-nøglet: {len(aendringer)} registerposter")

    # Selvverifikation FØR skrivning: reconcile mod den nye segmentering.
    # Kravet er nul tvetydige blandt de om-nøglede og nul kollisioner;
    # bortfaldne = gamle uden match (stamfædre + oversigtsposter) — forventet.
    rc = reconcile(reg, [{"side": _side_af(p), "lokal_id": p["lokal_id"]} for p in nye],
                   a.udgave)
    print(f"verifikation: entydige={len(rc.entydige)} tvetydige={len(rc.tvetydige)} "
          f"nye={len(rc.nye)} bortfaldne={len(rc.bortfaldne)}")
    if len(rc.entydige) < len(aendringer):
        raise SystemExit("verifikation fejlede — registeret er IKKE skrevet")

    if a.dry_run:
        print("dry-run — intet skrevet")
        return
    backup = a.register.with_suffix(f".omnoegl-{date.today().isoformat()}.bak.json")
    shutil.copy2(a.register, backup)
    a.register.write_text(reg.to_json() + "\n", encoding="utf-8")
    print(f"skrevet: {a.register} (backup: {backup.name})")


if __name__ == "__main__":
    main()
