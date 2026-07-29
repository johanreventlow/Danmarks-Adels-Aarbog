#!/usr/bin/env python3
"""Afstem registerets lokatorer mod et artefakt hvor record_key er kendt.

BAGGRUND (målt 2026-07-29): registerets `side` kom fra prod-citationerne,
artefaktets fra segmenteringen — begge PDF-ordinaler, men målt på hver sin
kilde. 59 af 515 poster afveg, og reconcile() meldte dem alle tvetydige.
Facit fandtes allerede: artefaktets `record_key` ER registerets book_post_id
(verificeret 515/515), så afstemningen er et opslag, ikke et skøn.

FAIL-CLOSED: der opdateres kun når
  * artefakt-posten bærer et record_key der findes i registeret, og
  * kun `side`-komponenten — `lokal_id` røres ikke, og
  * den nye nøgle ikke kolliderer med en eksisterende post (så stopper vi).

Den gamle side gemmes i `begrundelse` — en versioneret observation frem for
en overskrivning (Codex-review 2026-07-29: mint aldrig om; flyt adressen og
lad id'et stå).

Kør:
  python3 afstem_lokator.py            # afstemmer 1939-registeret in place (med backup)
  python3 afstem_lokator.py --dry-run  # viser kun hvad der ville ske
"""
from __future__ import annotations

import argparse
import json
import shutil
from datetime import date
from pathlib import Path

from identitetsregister import Lokator, Post, Register, reconcile

WORK = Path(__file__).resolve().parents[4] / "work_1939_stamtavle"


def afstem(reg: Register, poster: list[dict], udgave: str) -> list[tuple[str, str, str]]:
    """Flyt registerposter til artefaktets side, id-verificeret via record_key.

    Returnerer [(book_post_id, gammel_side, ny_side)]. To-faset (slet alle,
    indsæt alle), så et internt sidebytte ikke kolliderer med sig selv.
    """
    key_af_id = {p.book_post_id: k for k, p in reg.poster.items()}
    planer: list[tuple[str, Post, Lokator]] = []
    for post in poster:
        bid, ny_side = post.get("record_key"), post.get("side")
        if not bid or not ny_side or bid not in key_af_id:
            continue
        k = key_af_id[bid]
        p = reg.poster[k]
        if p.lokator.side == str(ny_side):
            continue
        planer.append((k, p, Lokator(udgave, str(ny_side), p.lokator.lokal_id)))

    for k, _, _ in planer:
        del reg.poster[k]

    aendringer = []
    for k, p, ny_lok in planer:
        if ny_lok.key() in reg.poster:
            raise ValueError(f"afstemning ville kollidere: {ny_lok.key()} er allerede optaget")
        note = f"side afstemt {p.lokator.side}→{ny_lok.side} mod artefakt (record_key-verificeret)"
        if p.begrundelse:
            note += f"; tidligere: {p.begrundelse}"
        reg.poster[ny_lok.key()] = Post(
            book_post_id=p.book_post_id, lokator=ny_lok, status=p.status, begrundelse=note)
        aendringer.append((p.book_post_id, p.lokator.side, ny_lok.side))
    return aendringer


def _artefakt_poster(clean: list[dict]) -> list[dict]:
    ud = []
    for p in clean:
        sider = p.get("sider")
        side = (sider[0] if isinstance(sider, list) and sider else sider) or None
        ud.append({"side": str(side) if side else None,
                   "lokal_id": str(p.get("_lokal_id") or ""),
                   "record_key": p.get("record_key")})
    return ud


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--register", type=Path, default=WORK / "identitetsregister-1939.json")
    ap.add_argument("--artefakt", type=Path, default=WORK / "clean_1939.json")
    ap.add_argument("--udgave", default="1939")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    reg = Register.from_json(json.loads(a.register.read_text(encoding="utf-8")))
    poster = _artefakt_poster(json.loads(a.artefakt.read_text(encoding="utf-8")))

    aendringer = afstem(reg, poster, a.udgave)
    print(f"afstemt: {len(aendringer)} poster flyttet")
    for bid, fra, til in aendringer:
        print(f"   {bid[:8]}  side {fra} → {til}")

    # Selvverifikation FØR der skrives: efter afstemning skal reconcile give
    # nul tvetydige og alle entydige skal ramme deres eget record_key.
    res = reconcile(reg, [p for p in poster if p["side"] and p["lokal_id"]], a.udgave)
    forkerte = [b for p, b in res.entydige if p["record_key"] != b]
    print(f"verifikation: entydige={len(res.entydige)} tvetydige={len(res.tvetydige)} "
          f"forkerte={len(forkerte)} bortfaldne={len(res.bortfaldne)}")
    if res.tvetydige or forkerte:
        raise SystemExit("verifikation fejlede — registeret er IKKE skrevet")

    if a.dry_run:
        print("dry-run — intet skrevet")
        return
    backup = a.register.with_suffix(f".{date.today().isoformat()}.bak.json")
    shutil.copy2(a.register, backup)
    a.register.write_text(reg.to_json() + "\n", encoding="utf-8")
    print(f"skrevet: {a.register} (backup: {backup.name})")


if __name__ == "__main__":
    main()
