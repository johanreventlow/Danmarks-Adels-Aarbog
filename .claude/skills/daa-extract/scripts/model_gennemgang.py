#!/usr/bin/env python3
"""Modelgennemgang af en udgave (trin 6m del 1; spec 2026-11-05 §4.1-4.2): modelinput, briefs og sammenlægning.

  input --eksport F --pdf P --ud D [--bid 25]  -> D/input-<k>.json, D/noegle.json, D/sider/s<p>.png (alle 0600)

Input kommer fra `model_gennemgang_eksport.sql` (læse-kun). Modellen får ingen interne id'er, kun ref'er (`p<n>` for
en post, `p<n>-f<i>` for et forslag); nøglen bliver hos operatøren. Filter (decisions 2026-11-05, fail-closed): et
forslag om en person, hvis databaseværdier ikke opfylder `sikker`, sendes ikke; det tælles som manuelt. Databasens
værdi vises kun for kontrolfelterne (navn, titel, fødsel, død) og kun for bundne, sikre personer.
Generaliseret fra 6c-2's modelforslag.py (operatørens private kopi). Printer kun antal; filer skrives 0600.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

import persona_kort as pk

MAX_SIDER = 4
NABO_TAERSKEL = 0.15
#: Kontrolfelterne og den visningsværdi, databasen sammenlignes med (samme som persona_kort.VISNING).
VISNING = pk.VISNING


class GennemgangError(Exception):
    """Fejlkode som streng, fx `SVAR_DUBLET`."""


def _sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sikker(person: dict) -> bool:
    """Død ikke-tom, eller største 4-cifrede år i `foedt` til og med 1939."""
    if (person.get("doed") or "").strip():
        return True
    aar = [int(a) for a in re.findall(r"1[0-9]{3}", person.get("foedt") or "")]
    return bool(aar) and max(aar) <= 1939


def ord_i(tekst: str) -> set:
    return set(re.findall(r"[A-Za-zÆØÅæøå]{5,}", tekst or ""))


def vaelg_sider(occ_sider: list, post_ord: set, sideord: Callable[[int], set], almindelige: set,
                max_sider: int = MAX_SIDER) -> list:
    """Altid forekomstsiderne; dertil ±1 naboside, hvis mindst 15 % af postens særord (ikke almindelige) står i
    sidens tekstlag. Højst `max_sider`, sorteret."""
    occ = sorted(set(occ_sider))
    if not occ:
        return []
    post = set(post_ord) - set(almindelige)
    kand = [s for s in range(occ[0] - 1, occ[-1] + 2) if s >= 1 and s not in occ]
    andel = {s: len(post & sideord(s)) / max(1, len(post)) for s in kand}
    naboer = sorted((s for s in kand if post and andel[s] >= NABO_TAERSKEL), key=lambda s: (-andel[s], s))
    return sorted(occ[:max_sider] + naboer[:max(0, max_sider - len(occ))])


def sideord_fra_pdf(pdf: Path, side: int) -> set:
    r = subprocess.run(["pdftotext", "-f", str(side), "-l", str(side), str(pdf), "-"], capture_output=True, text=True)
    return ord_i(r.stdout) if r.returncode == 0 else set()


def render_side(pdf: Path, side: int, ud: Path) -> Path:
    f = Path(ud) / f"s{side}.png"
    if not f.exists():
        subprocess.run(["pdftoppm", "-r", "150", "-png", "-singlefile", "-f", str(side), "-l", str(side), str(pdf),
                        str(f.with_suffix(""))], check=True, capture_output=True)
    os.chmod(f, 0o600)
    return f


def _occ_sider(placering: list) -> list:
    return sorted({s for o in placering or [] for s in range(o["side_fra"], o["side_til"] + 1)})


def _db_vaerdi(predicate: str, person: dict):
    for felt in VISNING.get(predicate, ()):
        if person.get(felt):
            return person[felt]
    return None


def byg_input(eksport: dict, *, bid: int = 25,
              sidevaelger: Callable[[list, str], list] | None = None) -> tuple:
    """Bidder à `bid` poster og nøglen ref -> id. `sidevaelger(occ_sider, posttekst)` giver postens sider
    (standard: forekomstsiderne); bidden nævner dem som `s<p>.png`."""
    if bid < 1:
        raise GennemgangError("BID_UGYLDIG")
    personer = eksport.get("personer") or {}
    noegle: dict = {}
    poster: list = []
    for n, p in enumerate(eksport["poster"], 1):
        ref = f"p{n}"
        nar, leg = p.get("narrativ"), p.get("legacy")
        vindue = pk.vindue(p.get("placering") or [])
        if nar:
            tekst, kilde = nar["tekst"], "narrativ"
            skrivbar = nar.get("status") == "published" and "publish_revision" in (nar.get("tilladte") or [])
        elif leg:
            tekst, kilde, skrivbar = leg["tekst"], "legacy", False
        else:
            tekst, kilde, skrivbar = (vindue or {}).get("post") or "", "ocr", False
        kilde_person = nar or leg or {}
        noegle[ref] = {"type": "post", "source_id": eksport["source_id"], "record_key": p["record_key"],
                       "person_id": kilde_person.get("person_id"), "narrative_id": kilde_person.get("narrative_id"),
                       "state_sha256": (nar or {}).get("state_sha256"), "tekst_sha256": _sha(tekst.encode("utf-8")),
                       "skrivbar": skrivbar, "legacy_ref": (leg or {}).get("legacy_ref") if not nar else None}
        occ = _occ_sider(p.get("placering") or [])
        sider = sidevaelger(occ, (vindue or {}).get("post") or tekst) if sidevaelger else occ
        forslag, manuelle = [], 0
        for i, f in enumerate(p.get("forslag") or [], 1):
            fref = f"{ref}-f{i}"
            pid = f.get("person_id")
            person = personer.get(str(pid)) if pid is not None else None
            manuel = pid is not None and not (person and sikker(person))
            noegle[fref] = {"type": "forslag", "interpretation_id": f["interpretation_id"], "version": f["version"],
                            "manuel": manuel}
            if manuel:
                manuelle += 1
                continue
            felt = {"ref": fref, "felt": f["predicate"], "vaerdi": f.get("value_text"), "status": f["status"]}
            if person is not None and f["predicate"] in VISNING:
                db = _db_vaerdi(f["predicate"], person)
                if db is not None:
                    felt["databasen"] = db
            forslag.append(felt)
        poster.append({"post": ref, "tekst": tekst, "tekstkilde": kilde, "ocr_vindue": vindue,
                       "sider": [f"s{s}.png" for s in sider], "kun_rapport": not skrivbar, "forslag": forslag,
                       "manuelle_forslag": manuelle})
    bidder = [{"udgave": eksport.get("udgave"), "bid": k + 1, "poster": poster[i:i + bid]}
              for k, i in enumerate(range(0, len(poster), bid))]
    return bidder, noegle


def _skriv_json(sti: Path, data) -> None:
    sti.write_text(json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
    os.chmod(sti, 0o600)


def _laes_json(sti: Path):
    return json.loads(Path(sti).read_text(encoding="utf-8"))


def cmd_input(a) -> int:
    eksport = _laes_json(a.eksport)
    ud = Path(a.ud)
    ud.mkdir(mode=0o700, parents=True, exist_ok=True)
    sider_mappe = ud / "sider"
    sider_mappe.mkdir(mode=0o700, exist_ok=True)
    cache: dict = {}

    def sideord(s: int) -> set:
        if s not in cache:
            cache[s] = sideord_fra_pdf(a.pdf, s)
        return cache[s]

    alle = sorted({s for p in eksport["poster"] for s in _occ_sider(p.get("placering") or [])})
    almindelige: set = set()
    if alle:
        from collections import Counter
        spaend = range(alle[0], alle[-1] + 1)
        taelling = Counter(w for s in spaend for w in sideord(s))
        almindelige = {w for w, n in taelling.items() if n > len(spaend) * 0.10}

    def vaelger(occ: list, posttekst: str) -> list:
        return vaelg_sider(occ, ord_i(posttekst), sideord, almindelige)

    bidder, noegle = byg_input(eksport, bid=a.bid, sidevaelger=vaelger)
    sider = sorted({int(s[1:-4]) for b in bidder for p in b["poster"] for s in p["sider"]})
    for s in sider:
        render_side(a.pdf, s, sider_mappe)
    for b in bidder:
        _skriv_json(ud / f"input-{b['bid']}.json", b)
    _skriv_json(ud / "noegle.json", noegle)
    poster = [p for b in bidder for p in b["poster"]]
    print(f"MG_INPUT_OK poster={len(poster)} bidder={len(bidder)} "
          f"forslag={sum(len(p['forslag']) for p in poster)} manuelle={sum(p['manuelle_forslag'] for p in poster)} "
          f"sider={len(sider)} uden_billede={sum(1 for p in poster if not p['sider'])}")
    return 0


def main(argv: list | None = None) -> int:
    os.umask(0o077)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("input")
    i.add_argument("--eksport", type=Path, required=True)
    i.add_argument("--pdf", type=Path, required=True)
    i.add_argument("--ud", type=Path, required=True)
    i.add_argument("--bid", type=int, default=25)
    a = ap.parse_args(argv)
    try:
        return {"input": cmd_input}[a.cmd](a)
    except GennemgangError as e:
        print(f"MG_FEJL {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
