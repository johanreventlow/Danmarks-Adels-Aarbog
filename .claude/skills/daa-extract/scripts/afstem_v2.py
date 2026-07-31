#!/usr/bin/env python3
"""Read-only afstemning af 1939-v2 mod identitetsregisteret.

Scriptet skriver aldrig registeret. Det foreslår kun om-nøglinger som er
krydstjekket på uafhængige kildesignaler og simulerer dem på en kopi. Alt der
ikke er entydigt og injektivt, ender i menneskearket.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

import segment
import validate
from identitetsregister import Lokator, Post, Register, reconcile
from omnoegl_lokator import PREFIX, _gammel_kerne, _norm


WORK = Path(__file__).resolve().parents[4] / "work_1939_stamtavle"


@dataclass
class Afstemningsresultat:
    uændrede: list[dict] = field(default_factory=list)
    auto_forslag: list[dict] = field(default_factory=list)
    menneskeark: list[dict] = field(default_factory=list)


def _side(v) -> str | None:
    return validate._foerste_side(v)


def _nummer(v) -> str:
    return str(v or "").strip().lower().replace(" ", "").replace("l", "1")


def _tekstanker(gammel: dict, ny: dict) -> bool:
    """Samme prefix-/midtervinduebro som omnoegl_lokator.py."""
    gn = _gammel_kerne(gammel.get("narrative"))
    nn = _norm(ny.get("raw_text"))
    ny_prefix = nn[:PREFIX]
    gamle_vinduer = [v for v in (gn[:PREFIX], gn[120:120 + PREFIX]) if len(v) >= 40]
    return bool((len(ny_prefix) >= 40 and ny_prefix in gn)
                or any(v in nn for v in gamle_vinduer))


def _navneanker(gammel: dict, ny: dict) -> bool:
    navn = _norm(gammel.get("navn"))
    return len(navn) >= 4 and navn in _norm(ny.get("raw_text"))


def _evidens(gammel: dict, ny: dict) -> dict[str, bool]:
    gammelt_nummer = _nummer(gammel.get("_orig_nr"))
    return {
        "side": _side(gammel.get("sider", gammel.get("side"))) == _side(ny.get("side", ny.get("sider"))),
        "navn": _navneanker(gammel, ny),
        "tekstanker": _tekstanker(gammel, ny),
        "nummer": not gammelt_nummer or gammelt_nummer == _nummer(ny.get("nr_label")),
    }


def _lokator_dict(lok: Lokator) -> dict:
    return {"udgave": lok.udgave, "side": lok.side, "lokal_id": lok.lokal_id}


def _ny_lokator(ny: dict, udgave: str) -> Lokator:
    return Lokator(udgave, str(_side(ny.get("side", ny.get("sider")))), str(ny["lokal_id"]))


def _menneskerække(*, grund: str, broklasse: str,
                   gammel: dict | None = None,
                   registerpost: Post | None = None, kandidater: list[dict] | None = None,
                   ny: dict | None = None) -> dict:
    kandidat_lokatorer = [_lokator_dict(_ny_lokator(p, "1939")) for p in (kandidater or [])]
    if ny is not None and not kandidat_lokatorer:
        kandidat_lokatorer = [_lokator_dict(_ny_lokator(ny, "1939"))]
    return {
        "book_post_id": registerpost.book_post_id if registerpost else None,
        "gammel_lokator": _lokator_dict(registerpost.lokator) if registerpost else None,
        "gammel_lokal_id": gammel.get("_lokal_id") if gammel else None,
        "kandidat_lokatorer": kandidat_lokatorer,
        "postklasse": (ny or (kandidater or [None])[0] or {}).get("postklasse") or "nummereret",
        "dublet_af_stamtavle": bool((ny or (kandidater or [None])[0] or {}).get("dublet_af_stamtavle")),
        "broklasse": broklasse,
        "grund": grund,
    }


def afstem_identiteter(reg: Register, gamle: list[dict], nye: list[dict],
                       udgave: str, *, legacy_lokal_ids: set[str]) -> Afstemningsresultat:
    """Klassificér alle aktive registerposter og alle nye v2-lokatorer.

    Legacy-poster kræver side + navn + tekstanker. Andre formdriftsposter
    kræver side + nummer + mindst ét tekstligt anker. En mål-lokator kan kun
    vindes af én identitet; kollision demoterer alle vindere til menneskeark.
    """
    resultat = Afstemningsresultat()
    gamle_by_id = {g.get("record_key"): g for g in gamle if g.get("record_key")}
    nye_by_key = {_ny_lokator(n, udgave).key(): n for n in nye}

    aktive = [p for p in reg.poster.values()
              if p.status == "aktiv" and p.lokator.udgave == udgave]
    optagne_nye: set[str] = set()
    uafklarede: list[tuple[Post, dict]] = []
    for rp in aktive:
        gammel = gamle_by_id.get(rp.book_post_id)
        if gammel is None:
            resultat.menneskeark.append(_menneskerække(
                grund="mangler_record_key_artefakt", broklasse="register_uden_artefakt",
                registerpost=rp))
            continue
        ny = nye_by_key.get(rp.lokator.key())
        if ny is not None:
            resultat.uændrede.append({
                "book_post_id": rp.book_post_id,
                "lokator": _lokator_dict(rp.lokator),
            })
            optagne_nye.add(rp.lokator.key())
        else:
            uafklarede.append((rp, gammel))

    frie_nye = [n for n in nye if _ny_lokator(n, udgave).key() not in optagne_nye]
    foreløbige: list[tuple[Post, dict, dict, dict]] = []
    menneske_targets: set[str] = set()
    for rp, gammel in uafklarede:
        legacy = gammel.get("_lokal_id") in legacy_lokal_ids
        broklasse = "legacy_48" if legacy else "nummereret_formdrift"
        kandidater = []
        for ny in frie_nye:
            ev = _evidens(gammel, ny)
            if legacy:
                godkendt = ev["side"] and ev["navn"] and ev["tekstanker"]
            else:
                godkendt = ev["side"] and ev["nummer"] and (ev["tekstanker"] or ev["navn"])
            if godkendt:
                kandidater.append((ny, ev))

        if len(kandidater) != 1:
            grund = ("ingen_entydig_tre_signalsbro" if legacy
                     else "ingen_entydig_nummer_ankerbro")
            resultat.menneskeark.append(_menneskerække(
                grund=grund, broklasse=broklasse, gammel=gammel, registerpost=rp,
                kandidater=[n for n, _ in kandidater]))
            menneske_targets.update(_ny_lokator(n, udgave).key() for n, _ in kandidater)
            continue
        ny, ev = kandidater[0]
        menneske_targets.add(_ny_lokator(ny, udgave).key())
        if ny.get("dublet_af_stamtavle"):
            resultat.menneskeark.append(_menneskerække(
                grund="dublet_af_stamtavle_kraever_menneske", broklasse=broklasse,
                gammel=gammel,
                registerpost=rp, ny=ny))
            continue
        foreløbige.append((rp, gammel, ny, ev))

    vindere = Counter(_ny_lokator(ny, udgave).key() for _, _, ny, _ in foreløbige)
    for rp, gammel, ny, ev in foreløbige:
        ny_lok = _ny_lokator(ny, udgave)
        if vindere[ny_lok.key()] != 1:
            resultat.menneskeark.append(_menneskerække(
                grund="ikke_injektiv_bro",
                broklasse=("legacy_48" if gammel.get("_lokal_id") in legacy_lokal_ids
                           else "nummereret_formdrift"),
                gammel=gammel, registerpost=rp, ny=ny))
            continue
        resultat.auto_forslag.append({
            "book_post_id": rp.book_post_id,
            "gammel_lokator": _lokator_dict(rp.lokator),
            "ny_lokator": _lokator_dict(ny_lok),
            "postklasse": ny.get("postklasse") or "nummereret",
            "dublet_af_stamtavle": bool(ny.get("dublet_af_stamtavle")),
            "broklasse": ("legacy_48" if gammel.get("_lokal_id") in legacy_lokal_ids
                           else "nummereret_formdrift"),
            "evidens": ev,
        })

    dækkede_targets = (optagne_nye
                       | {_ny_lokator(n, udgave).key() for _, _, n, _ in foreløbige}
                       | menneske_targets)
    for ny in frie_nye:
        key = _ny_lokator(ny, udgave).key()
        if key in dækkede_targets:
            continue
        grund = ("dublet_af_stamtavle_kraever_menneske"
                 if ny.get("dublet_af_stamtavle") else "v2_post_uden_entydig_registeridentitet")
        resultat.menneskeark.append(_menneskerække(
            grund=grund, broklasse="v2_uden_register", ny=ny))
    return resultat


def anvend_forslag(reg: Register, forslag: list[dict]) -> Register:
    """Anvend forslag på en dyb kopi; inputregisteret røres aldrig."""
    kopi = Register.from_json(json.loads(reg.to_json()))
    planer = []
    for f in forslag:
        gl = f["gammel_lokator"]
        nl = f["ny_lokator"]
        gammel = Lokator(gl["udgave"], gl["side"], gl["lokal_id"])
        ny = Lokator(nl["udgave"], nl["side"], nl["lokal_id"])
        post = kopi.poster.get(gammel.key())
        if post is None or post.book_post_id != f["book_post_id"]:
            raise ValueError(f"forslagets gamle lokator/id er ikke entydig: {gammel.key()}")
        planer.append((gammel.key(), post, ny))
    for key, _, _ in planer:
        del kopi.poster[key]
    for _, post, ny in planer:
        if ny.key() in kopi.poster:
            raise ValueError(f"simuleret om-nøgling kolliderer: {ny.key()}")
        kopi.poster[ny.key()] = Post(
            book_post_id=post.book_post_id, lokator=ny, status=post.status,
            begrundelse=post.begrundelse)
    return kopi


def _segmenter_v2(raw_path: Path) -> list[dict]:
    lines = raw_path.read_text(encoding="utf-8").splitlines()
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        poster = segment._segment_1939_v2(lines, segment.UDGAVE_PROFILER["1939-v2"])
    for post in poster:
        validate.paahaeft_lokator(post, post)
    return poster


def _legacy_ids(path: Path) -> set[str]:
    tekst = path.read_text(encoding="utf-8")
    markør = "## Til orientering: strukturelt parkerede"
    if markør not in tekst:
        raise ValueError(f"mangler legacy-sektion i {path}")
    ids = set(re.findall(r"^- `([^`]+)`", tekst.split(markør, 1)[1], re.MULTILINE))
    if len(ids) != 48:
        raise ValueError(f"forventede 48 parkerede legacy-id'er, fandt {len(ids)}")
    return ids


def _rapport(resultat: Afstemningsresultat, baseline, simuleret, aktive: int) -> str:
    grunde = Counter(r["grund"] for r in resultat.menneskeark)
    auto_klasser = Counter(r["postklasse"] for r in resultat.auto_forslag)
    auto_broer = Counter(r["broklasse"] for r in resultat.auto_forslag)
    menneske_broer = Counter(r["broklasse"] for r in resultat.menneskeark
                             if r["book_post_id"])
    aktive_menneske = {r["book_post_id"] for r in resultat.menneskeark if r["book_post_id"]}
    dublet_lokatorer = sorted({
        k["lokal_id"]
        for r in resultat.menneskeark if r["dublet_af_stamtavle"]
        for k in r["kandidat_lokatorer"]
    })
    linjer = [
        "# Afstemning af 1939-v2 mod identitetsregisteret — 2026-07-31", "",
        "Registeret er ikke ændret. Om-nøglinger nedenfor er kun forslag.", "",
        "## Fordeling", "",
        f"- Efter første-side-normalisering: entydige={len(baseline.entydige)}, "
        f"tvetydige={len(baseline.tvetydige)}, nye={len(baseline.nye)}, "
        f"bortfaldne={len(baseline.bortfaldne)}.",
        f"- Simuleret med auto-forslag: entydige={len(simuleret.entydige)}, "
        f"tvetydige={len(simuleret.tvetydige)}, nye={len(simuleret.nye)}, "
        f"bortfaldne={len(simuleret.bortfaldne)}.",
        f"- Aktive registerposter: {aktive}; uændrede={len(resultat.uændrede)}, "
        f"auto-om-nøglinger={len(resultat.auto_forslag)}, "
        f"eksplicit menneskeark={len(aktive_menneske)}.", "",
        "## Auto-krydstjekkede om-nøglinger", "",
    ]
    for klasse, antal in sorted(auto_klasser.items()):
        linjer.append(f"- {klasse}: {antal}")
    for broklasse, antal in sorted(auto_broer.items()):
        linjer.append(f"- Broklasse {broklasse}: {antal}")
    linjer.extend(["", "Alle legacy-forslag kræver samtidig side-, navne- og "
                    "narrativ-prefixanker. Nummererede formdriftsposter kræver "
                    "side, nummerenighed og tekstligt anker. Alle mål er injektive.", "",
                    "## Menneskeark", ""])
    for grund, antal in sorted(grunde.items()):
        linjer.append(f"- {grund}: {antal}")
    for broklasse, antal in sorted(menneske_broer.items()):
        linjer.append(f"- Aktive på menneskeark, broklasse {broklasse}: {antal}")
    linjer.extend(["", "### Dublet-markerede oversigtsposter", ""])
    for mål in dublet_lokatorer:
        linjer.append(f"- `{mål}` — afventer menneskeafgørelse; ikke mint-kandidat.")
    linjer.extend(["", "### Øvrige ankerløse eller tvetydige", ""])
    for række in resultat.menneskeark:
        if række["dublet_af_stamtavle"]:
            continue
        gammel = (række["gammel_lokator"] or {}).get("lokal_id", "ingen registeridentitet")
        mål = ", ".join(k["lokal_id"] for k in række["kandidat_lokatorer"]) or "ingen entydig kandidat"
        linjer.append(f"- `{gammel}` → `{mål}` — {række['grund']}.")
    return "\n".join(linjer) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", type=Path, default=WORK / "raw.txt")
    ap.add_argument("--register", type=Path, default=WORK / "identitetsregister-1939.json")
    ap.add_argument("--artefakt", type=Path, default=WORK / "clean_1939.json")
    ap.add_argument("--legacy-ark", type=Path, default=WORK / "omnoegl-afgoerelser-2026-07-30.md")
    ap.add_argument("--forslag", type=Path, default=WORK / "omnoegl-v2-forslag-2026-07-31.json")
    ap.add_argument("--rapport", type=Path, default=WORK / "afstem-v2-rapport-2026-07-31.md")
    a = ap.parse_args()

    register_bytes = a.register.read_bytes()
    register_sha = hashlib.sha256(register_bytes).hexdigest()
    reg = Register.from_json(json.loads(register_bytes))
    gamle = json.loads(a.artefakt.read_text(encoding="utf-8"))
    nye = _segmenter_v2(a.raw)
    baseline = reconcile(reg, nye, "1939")
    resultat = afstem_identiteter(
        reg, gamle, nye, "1939", legacy_lokal_ids=_legacy_ids(a.legacy_ark))
    sim_reg = anvend_forslag(reg, resultat.auto_forslag)
    sim_rc = reconcile(sim_reg, nye, "1939")

    aktive_ids = {p.book_post_id for p in reg.poster.values()
                  if p.status == "aktiv" and p.lokator.udgave == "1939"}
    dækkede_ids = ({r["book_post_id"] for r in resultat.uændrede}
                   | {r["book_post_id"] for r in resultat.auto_forslag}
                   | {r["book_post_id"] for r in resultat.menneskeark if r["book_post_id"]})
    if dækkede_ids != aktive_ids:
        raise SystemExit(f"aktiv identitetsdækning fejler: {len(dækkede_ids)}/{len(aktive_ids)}")
    dublet_targets = {k["lokal_id"] for r in resultat.menneskeark
                      if r["dublet_af_stamtavle"] for k in r["kandidat_lokatorer"]}
    forventede_dubletter = {p["lokal_id"] for p in nye if p.get("dublet_af_stamtavle")}
    if dublet_targets != forventede_dubletter:
        raise SystemExit(f"dublet-menneskeark fejler: {len(dublet_targets)}/7")

    output = {
        "version": 1,
        "udgave": "1939-v2",
        "anvendt": False,
        "register_sha256": register_sha,
        "side_normalisering": "første side i span; strengformat som registeret",
        "uændrede": resultat.uændrede,
        "auto_krydstjekkede": resultat.auto_forslag,
        "menneskeark": resultat.menneskeark,
        "reconcile": {
            "baseline": {"entydige": len(baseline.entydige), "tvetydige": len(baseline.tvetydige),
                         "nye": len(baseline.nye), "bortfaldne": len(baseline.bortfaldne)},
            "simuleret": {"entydige": len(sim_rc.entydige), "tvetydige": len(sim_rc.tvetydige),
                          "nye": len(sim_rc.nye), "bortfaldne": len(sim_rc.bortfaldne)},
        },
    }
    a.forslag.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    a.rapport.write_text(_rapport(resultat, baseline, sim_rc, len(aktive_ids)), encoding="utf-8")
    if hashlib.sha256(a.register.read_bytes()).hexdigest() != register_sha:
        raise SystemExit("registerfilen ændrede sig under kørslen")
    print(f"uændrede={len(resultat.uændrede)} auto={len(resultat.auto_forslag)} "
          f"menneskerækker={len(resultat.menneskeark)} aktive={len(aktive_ids)}")


if __name__ == "__main__":
    main()
