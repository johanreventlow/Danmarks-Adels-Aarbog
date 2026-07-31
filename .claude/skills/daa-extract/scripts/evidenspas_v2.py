#!/usr/bin/env python3
"""Kalibreret evidenspas for de 48 v2-menneskeposter og syv oversigtsdubletter.

Registeret er read-only. Alle om-nøglinger og mints udføres kun på en kopi.
Selve afgørelsestabellen er bevidst eksplicit: dette er et evidenspas, ikke en
generel fuzzy matcher.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

from afstem_v2 import _segmenter_v2, anvend_forslag
from identitetsregister import Register, reconcile
from omnoegl_lokator import _norm


WORK = Path(__file__).resolve().parents[4] / "work_1939_stamtavle"


# Kalibreret mod raw.txt. Kun injektive mål med mindst to uafhængige signaler.
OMNOEGLINGER = {
    "AI.stamfar": "Stamme-holstenske.I.U1",
    "A.III.3": "Stamme-holstenske.III.3",
    "A.IVB.1": "Stamme-holstenske.IV-B-Hr-Iven-Reventlows-Sønner.1",
    "A.IVB.3": "Stamme-holstenske.IV-B-Hr-Iven-Reventlows-Sønner.3",
    "A.IVC.3": "Stamme-holstenske.IV-C-Hr-Claus-Reventlows-Sønner.3",
    "A.V.3": "Stamme-holstenske.V.3",
    "VIIA.1": "Stamme-holstenske.hagen-VII-A-Henrik-Reventlows-Sønner.1",
    "VIIA.2": "Stamme-holstenske.hagen-VII-A-Henrik-Reventlows-Sønner.2",
    "AML-II.1": "Stamme-ældre-meklenborgske.II.1",
    "VI.2.N1": "III.Første.U1",
    "VI.2.N1.1.1": "III.Andet.4",
    "8II.1": "I.Ottende.II.U1",
    "LGallentin-3.1": "II.Tredje.U1",
    "LGallentin-6.1": "II.Sjette.1",
    "LGallentin-10I.7": "II.Tiende.I.7",
    "4II.2": "IV.Fjerde.II.2",
    "7I.1": "IV.Syvende.I.U1",
    "8IV.1": "IV.Ottende.IV.U1",
    "9II.1": "IV.Niende.II.U1",
    "4V.1": "V.Fjerde.V.U1",
    "p592-II.1": "V.Sjette.II.1",
    "Lfyn-2.2": "VI.Andet.2",
    "Uplac.11": "Oversigt.Uplacerede.U11",
    "Uplac.13": "Oversigt.Uplacerede.U14",
    "Uplac.16": "Oversigt.Uplacerede.U17",
}


# Kandidaten dokumenterer konflikten, men må netop ikke anvendes som om-nøgling.
TVIVL = {
    "A.III.claus2": ("Stamme-holstenske.III.3", "personen ligger i Volrads samlepost; ingen selvstændig v2-lokator"),
    "A.III.emeke": ("Stamme-holstenske.III.3", "personen ligger i Volrads samlepost; ingen selvstændig v2-lokator"),
    "A.III.henrik2": ("Stamme-holstenske.III.3", "personen ligger i Volrads samlepost; navnebroren i IV-C er en anden generation"),
    "A.IVA.1": ("Stamme-holstenske.III.3", "IV-A-prosaen er kollapset ind i Volrads v2-post"),
    "A.IVA.doso": ("Stamme-holstenske.III.3", "Doso er prosa i IV-A, ikke en selvstændig v2-post"),
    "YHL-II": ("I.Andet.2", "oversigtsreferencen peger på en allerede identificeret detaljepost"),
    "YHL-IIB.iven": ("I.Fjerde.havde-hende-i-Huset-II-Otto-Reventlows-Børn-m-Dorothea-von-Ahlefeldt.1", "oversigtsreferencen peger på en allerede identificeret detaljepost"),
    "YHL-IIB.iven.bertram": ("I.Femte.II.2", "oversigtsreferencen peger på en allerede identificeret detaljepost"),
    "YHL-IV": ("I.Andet.4", "oversigtsreferencen peger på en allerede identificeret detaljepost"),
    "YHL-Bertram.A.otto.detlev": ("I.Ottende.I.2", "oversigten nævner Detlev som efterkommer; detaljeposten har allerede identitet"),
    "YHL-Bertram.B.frederik.friederichadolph": ("I.Ottende.III.5", "oversigten nævner Friederich Adolph som efterkommer; detaljeposten har allerede identitet"),
    "VI.2.N1.1.1.1.I": ("III.Fjerde.I.1", "nedstigningsoversigten dublerer en allerede identificeret detaljepost"),
    "VI.2.N1.1.1.1.II.A.2.1": ("V.Første.U1", "nedstigningsoversigten dublerer første pass sikre stamfaderidentitet"),
    "VI.2.N1.1.1.1.II.B.1.B.1": ("IV.Fjerde.II.5", "nedstigningsoversigten dublerer en allerede identificeret detaljepost"),
    "VI.2.N1.1.1.1.II.B.1.B.3.1": ("IV.Femte.IV.3", "nedstigningsoversigten dublerer en allerede identificeret detaljepost"),
    "VI.2.N1.1.1.1.II.C": ("III.Femte.II.9", "nedstigningsoversigten dublerer en allerede identificeret detaljepost"),
    "5U.5": ("III.Femte.II.5", "målposten har allerede identitet; gammel post er en fejlklippet dublet"),
    "5U.11": ("III.Femte.II.10", "v2 har slået nr. 11 sammen med nr. 10, som allerede har identitet"),
    "Uplac.7": ("Oversigt.Uplacerede.U7", "gammel post indeholder to Claus-personer, v2 U7 og U8"),
    "7III.2": ("IV.Syvende.III.1", "v2 har kollapset trykt nr. 2-5 ind i nr. 1; selvstændig mållokator mangler"),
    "7III.3": ("IV.Syvende.III.1", "v2 har kollapset trykt nr. 2-5 ind i nr. 1; selvstændig mållokator mangler"),
    "7III.4": ("IV.Syvende.III.1", "v2 har kollapset trykt nr. 2-5 ind i nr. 1; selvstændig mållokator mangler"),
    "7III.5": ("IV.Syvende.III.1", "v2 har kollapset trykt nr. 2-5 ind i nr. 1; selvstændig mållokator mangler"),
}


DUBLETTER = {
    "Oversigt.Indledning.U1": ["I.Andet.2"],
    "Oversigt.Indledning.U2": ["I.Andet.3"],
    "Oversigt.Indledning.U3": [
        "I.Andet.4",
        "I.Fjerde.4-M-a-r-g-r-e-t-h-e-III-Cai-Reventlows-Børn-m-Anna-Rantzau.1",
    ],
    "Oversigt.Indledning.U4": [
        "I.Tredje.I.7",
        "I.Fjerde.Ditlev-Reventlows-Børn-af-første-Ægteskab-m-Anna-Rantzau.1",
        "I.Tredje.I.9",
    ],
    "Oversigt.Indledning.U5": [
        "I.Fjerde.havde-hende-i-Huset-II-Otto-Reventlows-Børn-m-Dorothea-von-Ahlefeldt.1",
        "I.Femte.II.2",
        "I.Sjette.Bertram-Reventlows-Børn-m-Christine-Rantzau.1",
    ],
    "Oversigt.Indledning.U6": [
        "I.Syvende.I.2", "I.Ottende.I.2", "I.Ottende.I.3",
        "I.Sjette.Bertram-Reventlows-Børn-m-Christine-Rantzau.6",
    ],
    "Oversigt.Indledning.U7": [
        "I.Syvende.sum-Skanse-II-Ditlev-Reventlows-Børn-med-Marie-Elisabeth-Buchwald.10",
        "I.Ottende.III.5",
    ],
}


PRAEFIKSKLASSER = {
    "AI/A.*": "holstensk stamme; romertal er bogafsnit, sidste tal er trykt post",
    "VIIA.*": "holstensk stamme VII A, Henrik Reventlows sønner, i bogrækkefølge",
    "YHL-*": "yngre holstensk linjes komprimerede oversigt; ikke selvstændige detaljeposter",
    "AML-*": "ældre meklenborgske linje; romertal og postnummer følger bogens struktur",
    "VI.2.N1*": "nedstigningsserie under ældre meklenborgske VI.2; krydshenviser til senere linjer",
    "Uplac.*": "uplacerede personer; navne- og årstalsrækkefølge er afgørende, ikke tallet alene",
    "formdrift": "trykt nummer plus kuld-/unionskontekst; U1 bruges kun ved reelt unummereret post",
}


def _kort_citat(tekst: str, *, start: int = 0, max_ord: int = 12) -> str:
    ord_ = re.sub(r"\s+", " ", tekst or "").strip().split()
    if not ord_:
        return "mangler tekstanker"
    start = min(start, max(0, len(ord_) - 1))
    return " ".join(ord_[start:start + max_ord])


def _klasse(legacy_id: str, broklasse: str) -> str:
    if broklasse == "nummereret_formdrift":
        return "nummereret_formdrift"
    if legacy_id.startswith(("AI", "A.", "VIIA")):
        return "holstensk_legacy"
    if legacy_id.startswith("YHL"):
        return "yngre_holstensk_oversigt"
    if legacy_id.startswith(("AML", "VI.2")):
        return "meklenborgsk_legacy"
    if legacy_id.startswith("Uplac"):
        return "uplaceret_legacy"
    return "oevrig_legacy"


def _navnekerne(navn: str) -> str:
    navn = re.sub(r"\[[^]]*\]", "", navn)
    dele = [d for d in re.findall(r"[A-Za-zÆØÅæøåÉéÎî]+", navn)
            if d.lower() not in {"af", "reventlow"}]
    return _norm("".join(dele))


def _bedste_navneratio(navn: str, tekst: str) -> float:
    kerne = _navnekerne(navn)
    maal = _norm(tekst)
    if not kerne or not maal:
        return 0.0
    n = len(kerne)
    return max(difflib.SequenceMatcher(None, kerne, maal[i:i + n]).ratio()
               for i in range(max(1, min(len(maal) - n + 1, 160))))


def _strukturanker(legacy_id: str, maal_id: str) -> tuple[str, str]:
    if legacy_id == "AI.stamfar":
        return "Gotskalks og Elisabeths Sønner var formentlig", "stamfaderen står umiddelbart før første sønnekuld"
    if maal_id.startswith("Stamme-holstenske.III"):
        return "Hr. Iven Reventlows Sønner var antagelig", "A.III og trykt postnummer følger afsnit III"
    if ".IV-B-" in maal_id:
        return "IV B. Hr. Iven Reventlows Sønner", "A.IVB og trykt postnummer følger afsnit IV B"
    if ".IV-C-" in maal_id:
        return "IV C. Hr. Claus Reventlows Sønner", "A.IVC og trykt postnummer følger afsnit IV C"
    if maal_id.startswith("Stamme-holstenske.V."):
        return "Hr. Henrik Grove Reventlows Sønner", "A.V og trykt postnummer følger afsnit V"
    if ".hagen-VII-A-" in maal_id:
        return "VII A. Henrik Reventlows Sønner", "VIIA og trykt postnummer følger afsnit VII A"
    if maal_id.startswith("Stamme-ældre-meklenborgske"):
        return "Den ældre meklenborgske Linje", "AML-II og trykt postnummer følger afsnit II"
    if maal_id.startswith("III."):
        return "Den ældre meklenborgske Linje af Ziesendorf", "VI.2-nedstigningsserien krydshenviser til Ziesendorf-linjen"
    if maal_id.startswith("II."):
        return "Linjen Gallentin", "LGallentin-adressen følger slægtled og trykt postnummer"
    if maal_id.startswith("VI."):
        return "Den fyenske Linje", "Lfyn-adressen følger den fyenske linjes slægtled og postnummer"
    if maal_id.startswith("Oversigt.Uplacerede"):
        return "Personer af Navnet Reventlow, der ikke kan anvises Plads", "Uplac følger bogens uplacerede navne- og årstalssekvens"
    slægtled = maal_id.split(".", 2)[1]
    return f"{slægtled} Slægtled", "formdrift afgøres af slægtled samt trykt nummer eller unionskontekst"


def _match_signaler(legacy_id: str, gammel: dict, ny: dict, nabo: dict | None,
                    klasse: str) -> list[dict]:
    tekst = ny.get("raw_text", "")
    strukturcitat, strukturregel = _strukturanker(legacy_id, ny["lokal_id"])
    ratio = _bedste_navneratio(str(gammel.get("navn") or ""), tekst)
    if ratio < 0.65:
        raise ValueError(f"identitetsanker under tærskel for {legacy_id}: {ratio:.3f}")
    signaler = [
        {
            "type": "strukturel_adresse",
            "citat": strukturcitat,
            "forklaring": f"{klasse}: {strukturregel}; mål {ny['lokal_id']}",
            "verificeret": True,
            "grundlag": ["legacy_id", "v2_lokal_id", "trykt_struktur"],
        },
        {
            "type": "identitetsanker",
            "citat": _kort_citat(tekst, max_ord=12),
            "forklaring": f"OCR-normaliseret navnekerne matcher '{gammel.get('navn')}' (ratio {ratio:.2f})",
            "verificeret": True,
            "grundlag": ["clean_1939.navn", "raw_text"],
        },
    ]
    if nabo is not None:
        signaler.append({
            "type": "naboskab",
            "citat": _kort_citat(nabo.get("raw_text", ""), max_ord=10),
            "forklaring": f"naboposten {nabo['lokal_id']} låser rækkefølgen i samme afsnit",
        })
    return signaler


def _doubt_signaler(gammel: dict, kandidat: dict, hvorfor: str) -> list[dict]:
    gammelt_anker = gammel.get("narrative") or gammel.get("navn") or ""
    return [
        {
            "type": "legacy_tekstanker",
            "citat": _kort_citat(gammelt_anker, max_ord=12),
            "forklaring": "den gamle identitet har et konkret navn eller narrativanker",
        },
        {
            "type": "modstrid_eller_granularitet",
            "citat": _kort_citat(kandidat.get("raw_text", ""), max_ord=12),
            "forklaring": hvorfor,
        },
    ]


def _nabo(nye: list[dict], indeks: int) -> dict | None:
    maal = nye[indeks]
    rod = maal["lokal_id"].rsplit(".", 1)[0]
    for j in (indeks - 1, indeks + 1):
        if 0 <= j < len(nye) and nye[j]["lokal_id"].rsplit(".", 1)[0] == rod:
            return nye[j]
    return None


def byg_evidenspas(*, forslag_path: Path, artefakt_path: Path, raw_path: Path,
                   register_path: Path) -> dict:
    register_bytes = register_path.read_bytes()
    register_sha = hashlib.sha256(register_bytes).hexdigest()
    register = Register.from_json(json.loads(register_bytes))
    foerste_pas = json.loads(forslag_path.read_text(encoding="utf-8"))
    gamle = json.loads(artefakt_path.read_text(encoding="utf-8"))
    gamle_by_key = {p.get("record_key"): p for p in gamle}
    nye = _segmenter_v2(raw_path)
    nye_by_id = {p["lokal_id"]: p for p in nye}
    indeks_by_id = {p["lokal_id"]: i for i, p in enumerate(nye)}
    menneske = [p for p in foerste_pas["menneskeark"] if p.get("book_post_id")]
    menneske_by_id = {p["gammel_lokal_id"]: p for p in menneske}

    forventede = set(menneske_by_id)
    afgjorte = set(OMNOEGLINGER) | set(TVIVL)
    if forventede != afgjorte:
        raise ValueError(f"afgørelsestabel dækker ikke menneskearket: mangler={sorted(forventede-afgjorte)}, ekstra={sorted(afgjorte-forventede)}")
    if len(set(OMNOEGLINGER.values())) != len(OMNOEGLINGER):
        raise ValueError("om-nøglingerne er ikke injektive")

    aktive_lokatorer = {p.lokator.key(): p.book_post_id for p in register.poster.values() if p.status == "aktiv"}
    for auto in foerste_pas["auto_krydstjekkede"]:
        lok = auto["ny_lokator"]
        aktive_lokatorer[f"{lok['udgave']}|{lok['side']}|{lok['lokal_id']}"] = auto["book_post_id"]
    poster = []
    forslag = []
    for legacy_id in sorted(forventede):
        række = menneske_by_id[legacy_id]
        gammel = gamle_by_key[række["book_post_id"]]
        klasse = _klasse(legacy_id, række["broklasse"])
        if legacy_id in OMNOEGLINGER:
            maal_id = OMNOEGLINGER[legacy_id]
            ny = nye_by_id[maal_id]
            lokator = {"udgave": "1939", "side": str(ny["side"]), "lokal_id": maal_id}
            post = {
                "legacy_id": legacy_id,
                "book_post_id": række["book_post_id"],
                "klasse": klasse,
                "afgoerelse": "omnoegling",
                "foreslaaet_v2_lokator": lokator,
                "signaler": _match_signaler(legacy_id, gammel, ny, _nabo(nye, indeks_by_id[maal_id]), klasse),
                "konfidens_begrundelse": "Mindst to uafhængige signaler er enige; ingen modstrid og målet er injektivt.",
            }
            forslag.append({
                "book_post_id": række["book_post_id"],
                "gammel_lokator": række["gammel_lokator"],
                "ny_lokator": lokator,
            })
        else:
            kandidat_id, hvorfor = TVIVL[legacy_id]
            kandidat = nye_by_id[kandidat_id]
            kandidat_key = f"1939|{kandidat['side']}|{kandidat_id}"
            besat = kandidat_key in aktive_lokatorer
            post = {
                "legacy_id": legacy_id,
                "book_post_id": række["book_post_id"],
                "klasse": klasse,
                "afgoerelse": "ægte tvivl",
                "foreslaaet_v2_lokator": "ægte tvivl",
                "konflikt_kandidat": {"udgave": "1939", "side": str(kandidat["side"]), "lokal_id": kandidat_id},
                "signaler": _doubt_signaler(gammel, kandidat, hvorfor),
                "konfidens_begrundelse": f"Ingen om-nøgling: {hvorfor}. Kandidatlokatoren er {'allerede besat' if besat else 'ikke en entydig enkeltperson'}.",
            }
        poster.append(post)

    for oversigt_id, detalje_ids in sorted(DUBLETTER.items()):
        oversigt = nye_by_id[oversigt_id]
        detaljer = [nye_by_id[i] for i in detalje_ids]
        if len(detalje_ids) == 1:
            indstilling = f"dublet af {detalje_ids[0]} → bør IKKE have selvstændig identitet (2.11-præcedens: parkér)"
        else:
            indstilling = ("oversigtsblok af allerede detaljerede personer [" + ", ".join(detalje_ids) +
                            "] → bør IKKE have selvstændig identitet (2.11-præcedens: parkér)")
        poster.append({
            "legacy_id": oversigt_id,
            "book_post_id": None,
            "klasse": "dubletmarkeret_oversigt",
            "afgoerelse": "dublet-indstilling",
            "foreslaaet_v2_lokator": "dublet-indstilling",
            "dublet_af_v2_lokal_ids": detalje_ids,
            "dublet_indstilling": indstilling,
            "signaler": ([{"type": "oversigt_tekst", "citat": _kort_citat(oversigt["raw_text"], max_ord=12),
                            "forklaring": "oversigtsblokkens navn, år og gods"}] +
                         [{"type": "detaljepost_tekst", "citat": _kort_citat(d["raw_text"], max_ord=8),
                           "forklaring": f"personen udfoldes i {d['lokal_id']}"} for d in detaljer]),
            "konfidens_begrundelse": "Alle navngivne personer i oversigtsblokken genfindes som detaljerede stamtavleposter; blokken skal parkeres.",
        })

    baseline = reconcile(register, nye, "1939")
    sim_reg = anvend_forslag(register, foerste_pas["auto_krydstjekkede"] + forslag)
    total = reconcile(sim_reg, nye, "1939")
    dublet_ids = set(DUBLETTER)
    anvendte_maal = {
        p["ny_lokator"]["lokal_id"]
        for p in foerste_pas["auto_krydstjekkede"] + forslag
    }
    baseline_nye_ids = {p["lokal_id"] for p in baseline.nye}
    forventede_nye_ids = baseline_nye_ids - anvendte_maal
    faktiske_nye_ids = {p["lokal_id"] for p in total.nye}
    uventede_nye = sorted(faktiske_nye_ids - forventede_nye_ids)
    manglende_nye = sorted(forventede_nye_ids - faktiske_nye_ids)
    mint_kandidater = [p for p in total.nye
                       if p["lokal_id"] in forventede_nye_ids and p["lokal_id"] not in dublet_ids]
    tvivl_keys = {f"1939|{menneske_by_id[i]['gammel_lokator']['side']}|{menneske_by_id[i]['gammel_lokator']['lokal_id']}" for i in TVIVL}
    uforklarede_bortfaldne = [lok.key() for lok in total.bortfaldne if lok.key() not in tvivl_keys]
    uforklarede = (len(total.tvetydige) + len(uforklarede_bortfaldne) +
                   len(uventede_nye) + len(manglende_nye))

    return {
        "version": 1,
        "udgave": "1939-v2",
        "anvendt": False,
        "register_sha256": register_sha,
        "praefiksklasser": PRAEFIKSKLASSER,
        "poster": poster,
        "simuleret_total_reconcile": {
            "foerste_pas_auto_omnoeglinger": len(foerste_pas["auto_krydstjekkede"]),
            "evidenspas_omnoeglinger": len(forslag),
            "ægte_tvivl": len(TVIVL),
            "mint_kandidater_ikke_anvendt": len(mint_kandidater),
            "dubletter_parkeret": len(DUBLETTER),
            "forventede_nye_fra_baseline": len(forventede_nye_ids),
            "uventede_nye_lokatorer": uventede_nye,
            "manglende_forventede_nye_lokatorer": manglende_nye,
            "mekanisk": {
                "entydige": len(total.entydige),
                "tvetydige": len(total.tvetydige),
                "nye": len(total.nye),
                "bortfaldne": len(total.bortfaldne),
            },
            "uforklarede": uforklarede,
        },
    }


def _rapport(data: dict) -> str:
    poster = data["poster"]
    afg = Counter(p["klasse"] for p in poster if p["afgoerelse"] == "omnoegling")
    tvivl = Counter(p["klasse"] for p in poster if p["afgoerelse"] == "ægte tvivl")
    sim = data["simuleret_total_reconcile"]
    linjer = [
        "# Kalibreret evidenspas — 1939-v2 — 2026-07-31", "",
        "Registerfilen er ikke ændret. Kun de 18 første-pas-forslag og evidenspassets om-nøglinger er simuleret på en kopi.", "",
        "## Præfiksklassernes semantik", "",
    ]
    linjer.extend(f"- `{k}`: {v}." for k, v in data["praefiksklasser"].items())
    linjer.extend(["", "## Afgjorte og ægte tvivl pr. klasse", ""])
    legacy_afgjorte = sum(afg[k] for k in afg if k != "nummereret_formdrift")
    legacy_tvivl = sum(tvivl[k] for k in tvivl if k != "nummereret_formdrift")
    linjer.extend([
        f"- Legacy i alt: afgjorte={legacy_afgjorte}, ægte tvivl={legacy_tvivl}.",
        f"- Nummereret formdrift: afgjorte={afg['nummereret_formdrift']}, ægte tvivl={tvivl['nummereret_formdrift']}.",
    ])
    for klasse in sorted(set(afg) | set(tvivl)):
        linjer.append(f"- {klasse}: afgjorte={afg[klasse]}, ægte tvivl={tvivl[klasse]}.")
    linjer.extend(["", "## Ægte tvivl", ""])
    for p in poster:
        if p["afgoerelse"] == "ægte tvivl":
            linjer.append(f"- `{p['legacy_id']}` — {p['konfidens_begrundelse']}")
    linjer.extend(["", "## Dublet-indstillinger", ""])
    for p in poster:
        if p["afgoerelse"] == "dublet-indstilling":
            linjer.append(f"- `{p['legacy_id']}` — {p['dublet_indstilling']}.")
    m = sim["mekanisk"]
    linjer.extend([
        "", "## Simuleret total-reconcile", "",
        f"- Forslag anvendt på kopi: første pas={sim['foerste_pas_auto_omnoeglinger']}, evidenspas={sim['evidenspas_omnoeglinger']}.",
        f"- Mint er ikke simuleret: {sim['mint_kandidater_ikke_anvendt']} nye v2-poster er klassificeret som ikke-anvendte mint-kandidater; {sim['dubletter_parkeret']} oversigtsblokke er parkeret.",
        f"- Mekanisk: entydige={m['entydige']}, tvetydige={m['tvetydige']}, nye={m['nye']}, bortfaldne={m['bortfaldne']}.",
        f"- Uafhængig baseline-mængdekontrol: forventede nye={sim['forventede_nye_fra_baseline']}, uventede={len(sim['uventede_nye_lokatorer'])}, manglende={len(sim['manglende_forventede_nye_lokatorer'])}.",
        f"- Klassificeret rest: ægte tvivl={sim['ægte_tvivl']}, mint-kandidater={sim['mint_kandidater_ikke_anvendt']}, dubletparkering={sim['dubletter_parkeret']}.",
        f"- Uforklarede rest={sim['uforklarede']}.",
    ])
    return "\n".join(linjer) + "\n"


def generer(*, output_path: Path = WORK / "evidenspas-v2-2026-07-31.json",
            rapport_path: Path = WORK / "evidenspas-v2-rapport-2026-07-31.md",
            forslag_path: Path = WORK / "omnoegl-v2-forslag-2026-07-31.json",
            artefakt_path: Path = WORK / "clean_1939.json",
            raw_path: Path = WORK / "raw.txt",
            register_path: Path = WORK / "identitetsregister-1939.json") -> dict:
    foer = register_path.read_bytes()
    data = byg_evidenspas(forslag_path=forslag_path, artefakt_path=artefakt_path,
                         raw_path=raw_path, register_path=register_path)
    output_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    rapport_path.write_text(_rapport(data), encoding="utf-8")
    if register_path.read_bytes() != foer:
        raise RuntimeError("registerfilen blev ændret")
    return data


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, default=WORK / "evidenspas-v2-2026-07-31.json")
    ap.add_argument("--rapport", type=Path, default=WORK / "evidenspas-v2-rapport-2026-07-31.md")
    args = ap.parse_args()
    data = generer(output_path=args.output, rapport_path=args.rapport)
    sim = data["simuleret_total_reconcile"]
    print(f"afgjorte={sim['evidenspas_omnoeglinger']} tvivl={sim['ægte_tvivl']} "
          f"dubletter={sim['dubletter_parkeret']} uforklarede={sim['uforklarede']}")


if __name__ == "__main__":
    main()
