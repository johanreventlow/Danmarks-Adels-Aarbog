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


# --- briefs og sammenlægning (Task 4) ------------------------------------------------------------------------------

TAERSKEL = 300
A_SVAR = {"OK", "FORSLAG_FEJL", "DB_FEJL", "BEGGE", "TVIVL"}
A_BILLEDE = {"bekraefter", "modsiger", "ikke_fundet"}
B_ART = {"ocr", "orddeling", "mangler", "overskydende", "graense"}
B_RETTELSE_BILLEDE = {"bekraefter", "tvivl"}
GRUPPERBAR = {"ocr", "orddeling"}


def skriv_briefs(skabelon: str, mappe: Path, bidder: int) -> list:
    mappe = Path(mappe)
    stier = []
    for k in range(1, bidder + 1):
        t = (skabelon.replace("{INPUT}", str(mappe / f"input-{k}.json"))
             .replace("{SVAR_A}", str(mappe / f"svar-A-{k}.json"))
             .replace("{SVAR_B}", str(mappe / f"svar-B-{k}.json"))
             .replace("{SIDER}", str(mappe / "sider")))
        p = mappe / f"brief-{k}.md"
        p.write_text(t, encoding="utf-8")
        os.chmod(p, 0o600)
        stier.append(p)
    return stier


def _liste(sti: Path) -> list:
    try:
        data = _laes_json(sti)
    except (OSError, ValueError):
        raise GennemgangError("SVAR_UGYLDIGT")
    if not isinstance(data, list) or not all(isinstance(x, dict) for x in data):
        raise GennemgangError("SVAR_UGYLDIGT")
    return data


def _tekst(x) -> bool:
    return isinstance(x, str) and x.strip() != ""


def over_taerskel(a_grupper: int, b_grupper: int) -> bool:
    """Spec §4.3.3 over begge spor: flere end TAERSKEL markerede elementer efter gruppering."""
    return a_grupper + b_grupper > TAERSKEL


def grupper_b(b: list) -> list:
    """Svarbare B-rettelser grupperet: `ocr`/`orddeling` på (art, fra, til, billede), ellers én pr. rettelse.
    Billedstøtten er en del af nøglen: ét gruppesvar må aldrig dække både set og tvivlsomme rettelser.
    Grænserettelser og rettelser på `kun_rapport`-poster er ikke svarbare og grupperes ikke."""
    grupper: dict = {}
    for r in b:
        if r["art"] == "graense" or r.get("kun_rapport"):
            continue
        noegle = ((r["art"], r["fra"], r["til"], r.get("billede")) if r["art"] in GRUPPERBAR
                  else ("enkelt", r["ref"]))
        grupper.setdefault(noegle, {"art": r["art"], "billede": r.get("billede"), "elementer": []})[
            "elementer"].append(r["ref"])
    return [dict(g, gruppe=f"bg{i}") for i, g in enumerate(grupper.values(), 1)]


def grupper_a(a: list) -> list:
    """Markerede A-svar (alt andet end OK): `FORSLAG_FEJL` på (svar, felt, vaerdi, bogens_laesning), ellers én pr. svar."""
    grupper: dict = {}
    for x in a:
        if x["svar"] == "OK":
            continue
        noegle = ((x["svar"], x["felt"], x["vaerdi"], x["bogens_laesning"]) if x["svar"] == "FORSLAG_FEJL"
                  else ("enkelt", x["ref"]))
        grupper.setdefault(noegle, {"svar": x["svar"], "elementer": []})["elementer"].append(x["ref"])
    return [dict(g, gruppe=f"ag{i}") for i, g in enumerate(grupper.values(), 1)]


def manifest(b: list, grupper: list) -> str:
    """sha256 af den kanoniske JSON af alle B-rettelser og B-grupperne (Codex #2): ejersvar bindes til den."""
    felter = ("ref", "post", "start", "slut", "fra", "til", "art", "billede")
    kanon = {"b": [{k: r[k] for k in felter} for r in b], "grupper": grupper}
    return _sha(json.dumps(kanon, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def _entydig(tekst: str, fra: str) -> int:
    start = tekst.find(fra)
    if start < 0 or tekst.find(fra, start + 1) >= 0:
        raise GennemgangError("RETTELSE_IKKE_ENTYDIG")
    return start


def saml(bidder: list, noegle: dict, svar_a: list, svar_b: list) -> dict:
    """Fail-closed sammenlægning af modelsvarene: hvert sendt forslag og hver post præcis én gang, kun gyldige
    værdier, entydige og ikke-overlappende rettelser med halvåbne intervaller [start, slut) i postens tekst."""
    poster = {p["post"]: p for b in bidder for p in b["poster"]}
    forslag = {f["ref"]: (p, f) for p in poster.values() for f in p["forslag"]}
    for ref, p in poster.items():
        if noegle.get(ref, {}).get("tekst_sha256") != _sha(p["tekst"].encode("utf-8")):
            raise GennemgangError("TEKST_DRIFT")

    a_ud, set_a = [], set()
    for x in (y for f in svar_a for y in _liste(f)):
        ref = x.get("ref")
        if ref in set_a:
            raise GennemgangError("SVAR_DUBLET")
        if ref not in forslag:
            raise GennemgangError("SVAR_UKENDT_REF")
        set_a.add(ref)
        post, f = forslag[ref]
        svar, billede, laesning = x.get("svar"), x.get("billede"), x.get("bogens_laesning")
        if svar not in A_SVAR or billede not in A_BILLEDE:
            raise GennemgangError("SVAR_UGYLDIGT")
        if svar == "FORSLAG_FEJL" and not _tekst(laesning):
            raise GennemgangError("SVAR_UGYLDIGT")
        if svar == "DB_FEJL" and "databasen" not in f:
            raise GennemgangError("SVAR_UGYLDIGT")
        if svar in ("OK", "FORSLAG_FEJL", "DB_FEJL") and billede != "bekraefter":
            raise GennemgangError("BILLEDSTOETTE_MANGLER")   # uden billedstøtte er svaret TVIVL
        if billede == "bekraefter" and not post["sider"]:
            raise GennemgangError("BILLEDSTOETTE_MANGLER")   # posten har intet sidebillede at bekræfte med
        a_ud.append({"ref": ref, "post": post["post"], "felt": f["felt"], "vaerdi": f["vaerdi"],
                     "databasen": f.get("databasen"), "svar": svar,
                     "bogens_laesning": laesning if svar == "FORSLAG_FEJL" else None, "billede": billede,
                     "grund": x.get("grund")})
    if set_a != set(forslag):
        raise GennemgangError("SVAR_MANGLER")

    b_ud, b_poster, set_b, manglende = [], [], set(), 0
    for x in (y for f in svar_b for y in _liste(f)):
        ref = x.get("post")
        if ref in set_b:
            raise GennemgangError("SVAR_DUBLET")
        if ref not in poster:
            raise GennemgangError("SVAR_UKENDT_REF")
        set_b.add(ref)
        post = poster[ref]
        rettelser, pbillede, mf = x.get("rettelser"), x.get("billede"), x.get("manglende_fakta")
        if (not isinstance(rettelser, list) or pbillede not in A_BILLEDE or not isinstance(mf, int)
                or isinstance(mf, bool) or mf < 0):
            raise GennemgangError("SVAR_UGYLDIGT")
        if pbillede == "modsiger" and not rettelser:
            raise GennemgangError("SVAR_UGYLDIGT")
        if pbillede == "bekraefter" and not post["sider"]:
            raise GennemgangError("BILLEDSTOETTE_MANGLER")
        manglende += mf
        b_poster.append({"post": ref, "billede": pbillede, "rettelser": len(rettelser), "manglende_fakta": mf})
        intervaller = []
        for i, r in enumerate(rettelser, 1):
            if (not isinstance(r, dict) or not _tekst(r.get("fra")) or not isinstance(r.get("til"), str)
                    or r.get("art") not in B_ART or r.get("billede") not in B_RETTELSE_BILLEDE
                    or not isinstance(r.get("rammer_forslag", []), list) or r.get("fra") == r.get("til")):
                raise GennemgangError("SVAR_UGYLDIGT")
            if (pbillede == "ikke_fundet" or not post["sider"]) and r["billede"] != "tvivl":
                raise GennemgangError("BILLEDSTOETTE_MANGLER")
            egne = {f["ref"] for f in post["forslag"]}
            if any(fr not in egne for fr in r.get("rammer_forslag", [])):
                raise GennemgangError("SVAR_UKENDT_REF")
            start = _entydig(post["tekst"], r["fra"])
            slut = start + len(r["fra"])
            if any(start < s2 and s1 < slut for s1, s2 in intervaller):
                raise GennemgangError("RETTELSE_OVERLAPPER")
            intervaller.append((start, slut))
            b_ud.append({"ref": f"{ref}-r{i}", "post": ref, "start": start, "slut": slut, "fra": r["fra"],
                         "til": r["til"], "art": r["art"], "billede": r["billede"],
                         "rammer_forslag": list(r.get("rammer_forslag", [])), "grund": r.get("grund"),
                         "kun_rapport": post["kun_rapport"]})
    if set_b != set(poster):
        raise GennemgangError("SVAR_MANGLER")

    ga, gb = grupper_a(a_ud), grupper_b(b_ud)
    taelling = {
        "a_ok": sum(1 for x in a_ud if x["svar"] == "OK"), "a_markeret": sum(1 for x in a_ud if x["svar"] != "OK"),
        # OK = ingen rettelser OG teksten set på sidebilledet; ellers er posten ikke kontrolleret mod bogen.
        "b_poster_ok": sum(1 for x in b_poster if not x["rettelser"] and x["billede"] == "bekraefter"),
        "b_poster_uverificeret": sum(1 for x in b_poster if x["billede"] == "ikke_fundet"),
        "b_rettelser": len(b_ud), "a_grupper": len(ga), "b_grupper": len(gb),
        "graense": sum(1 for r in b_ud if r["art"] == "graense"),
        "tvivl": sum(1 for x in a_ud if x["svar"] == "TVIVL") + sum(1 for r in b_ud if r["billede"] == "tvivl"),
        "kun_rapport": sum(1 for r in b_ud if r["kun_rapport"] and r["art"] != "graense"),
        "manglende_fakta": manglende, "over_taerskel": int(over_taerskel(len(ga), len(gb)))}
    return {"A": a_ud, "B": b_ud, "B_poster": b_poster, "grupper_a": ga, "grupper_b": gb, "taelling": taelling,
            "manifest_sha256": manifest(b_ud, gb)}


def _bidder_i(ud: Path) -> list:
    stier = sorted(Path(ud).glob("input-*.json"), key=lambda p: int(p.stem.split("-")[1]))
    if not stier:
        raise GennemgangError("INPUT_MANGLER")
    return [_laes_json(p) for p in stier]


def cmd_briefs(a) -> int:
    bidder = _bidder_i(a.ud)
    stier = skriv_briefs(Path(a.skabelon).read_text(encoding="utf-8"), a.ud, len(bidder))
    print(f"MG_BRIEFS_OK briefs={len(stier)} skabelon={_sha(Path(a.skabelon).read_bytes())[:8]}")
    return 0


def cmd_saml(a) -> int:
    ud = Path(a.ud)
    bidder = _bidder_i(ud)
    ks = [b["bid"] for b in bidder]
    svar_a, svar_b = [ud / f"svar-A-{k}.json" for k in ks], [ud / f"svar-B-{k}.json" for k in ks]
    if not all(p.exists() for p in svar_a + svar_b):
        raise GennemgangError("SVAR_MANGLER")
    if (ud / "samlet.json").exists():
        raise GennemgangError("SAMLET_FINDES")
    s = saml(bidder, _laes_json(ud / "noegle.json"), svar_a, svar_b)
    _skriv_json(ud / "samlet.json", s)
    t = s["taelling"]
    print("MG_SAML_OK " + " ".join(f"{k}={t[k]}" for k in (
        "a_ok", "a_markeret", "b_poster_ok", "b_poster_uverificeret", "b_rettelser", "a_grupper", "b_grupper", "graense", "tvivl",
        "kun_rapport", "manglende_fakta", "over_taerskel")) + f" manifest={s['manifest_sha256'][:8]}")
    return 3 if t["over_taerskel"] else 0


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
    br = sub.add_parser("briefs")
    br.add_argument("--ud", type=Path, required=True)
    br.add_argument("--skabelon", type=Path, default=Path(__file__).parent / "model_gennemgang_brief.md")
    sa = sub.add_parser("saml")
    sa.add_argument("--ud", type=Path, required=True)
    a = ap.parse_args(argv)
    try:
        return {"input": cmd_input, "briefs": cmd_briefs, "saml": cmd_saml}[a.cmd](a)
    except GennemgangError as e:
        print(f"MG_FEJL {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
