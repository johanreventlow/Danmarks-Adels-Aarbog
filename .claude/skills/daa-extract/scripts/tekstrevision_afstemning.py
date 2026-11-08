#!/usr/bin/env python3
"""Trin 6c-3: afstemningen efter en kildetekst-revision — fra forældede nøgler til nye nøgler, kort og kvittering.

Spec: `docs/superpowers/specs/2026-11-07-trin6c3-a6b-resten-design.md` §4.3-§4.5 og §4.7 pkt. 4; plan Task 5.

Matchningen gammel → ny står i `tekstrevision_afstemning.sql` (én kontrakt pr. art; al værdisammenligning sker dér,
med `binding_value_matches` og `saml_blanktegn_v1`). Udskriften bærer pr. forældet nøgle de nye nøgler, der opfylder
kontrakten (`kandidater`), og SQL'ens udfald. Værktøjet her genberegner udfaldet af kandidatmængderne (samme
entydighedsregel) og afviser en udskrift, der ikke stemmer; det sammenligner aldrig værdier.

Kommandoer (alle filer under `--private-root`, standard ~/.private; output 0600; stdout kun koder, antal og hashes):
  noegler          nye nøgler fra afstemningen → nøglefil (én pr. linje), evt. pr. prædikat
  afgraens         kontrolmodellens klassifikation og rækker beskåret til nøglelisten (+ afgrænset id-kort)
  kortsvar         stand-in'ens ark v2 (`F <id> <ver>`, `P <id> <ver>`) → nøglebaseret svar.json
  oversaet         svar.json + prods plan og id-kort → ark v2 med prods id'er (KORT_PROD_AFVIGER ved afvigelse)
  relationssvar    forælder- og børnearkets svar (Task 4) → relationssvar.json
  relationer-sql   ægteskabernes mængdetjek + afgørelse og alle relationsbindinger mod den gamle bindings familie
  parter-filtrer   relation_persona-manifestet afgrænset til nøglelisten
  parter-logisk    det logiske partsmanifest (uden klausul-id'er) til GO
  parter-sammenlign prods manifest mod det logiske fra stand-in'en (PARTER_AFVIGER)
  tilbagetraek-ark T/V-arket over de bindinger, der efter fakta- og relationssvarene ikke genbindes
  tilbagetraek-tjek T/V-arket læst og kontrolleret (ubesvarede/ukendte linjer afvises)
  kvittering-sql   afstemningskvitteringen (ét kald til private.write_text_revision_reconciliation) + preflight

Hash-kæden (spec §4.5): `oversaet` er deterministisk fra (svar.json, prods plan og id-kort); GO binder svar.json; kvit-
teringens context gemmer svar.json's sha (`svar_sha256`) og det oversatte arks sha (`oversat_ark_sha256`), som
`control_model_v2.py sql --approved-sha256` får.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

import control_model_v2 as v2
import relation_child_sheet as boern
import relation_parent_sheet as foraeldre
from control_model import CLASSES, ControlError, _lit, _write
from decision_sheet_core import SheetError
from spouse_exception_sheet import check_private_path

SCRIPTS = ".claude/skills/daa-extract/scripts"
AFSTEMNING_SQL = f"{SCRIPTS}/tekstrevision_afstemning.sql"
CLASSIFICATION_SQL = f"{SCRIPTS}/interpretation_control_classification.sql"

AFSTEMNING_CONTRACT = "tekstrevision-afstemning-v1"
IDKORT_CONTRACT = "tekstrevision-idkort-v1"
KORTSVAR_CONTRACT = "tekstrevision-kortsvar-v1"
RELATIONSSVAR_CONTRACT = "tekstrevision-relationssvar-v1"
PARTER_CONTRACT = "tekstrevision-parter-logisk-v1"
GRUNDLAG_CONTRACT = "tekstrevision-grundlag-v1"
TILBAGETRAEK_CONTRACT = "tekstrevision-tilbagetraek-v1"
KVITTERING_CONTRACT = "tekstrevision-kvittering-v1"

FASER = ("foer_parter", "efter_parter", "efter_afgoerelser")
RELATIONSARTER = ("aegteskab", "foraelder", "barn")
ARTER = ("fakta", "ubundet", "ukendt") + RELATIONSARTER
UDFALD = ("genfundet", "ikke_genfundet", "afventer")
#: Klassifikationens faste klasser (interpretation_control_classification.sql); de to nye kun, når de forekommer.
BASIS_KLASSER = CLASSES
NYE_KLASSER = ("ALREADY_BOUND_OTHER", "TARGET_SHARED")
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
T_RE = re.compile(rf"^T (?P<ref>(?P<key>{UUID})@(?P<type>assertion|family):(?P<id>-?[0-9]+)) : (?P<tok>\S+)"
                  r"(?:\s+#.*)?$")
GRUNDLAG_RE = re.compile(r"^# grundlag_sha256: ([0-9a-f]{64})$", re.M)
RESET = "SELECT set_config('app.change_set_id','',true) \\g /dev/null"


class AfstemningError(RuntimeError):
    """Fail-closed: intet skrives."""


def _canon(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _jlit(obj) -> str:
    return _lit(json.dumps(obj, ensure_ascii=False, sort_keys=True))


def _uuid(s) -> str:
    if not isinstance(s, str) or not re.fullmatch(UUID, s):
        raise AfstemningError("ID_UGYLDIG")
    return s


def _int(x) -> int:
    if type(x) is not int:
        raise AfstemningError("ID_UGYLDIG")
    return x


# --- afstemningens udskrift -----------------------------------------------------------------------------------------

def udled_udfald(gamle: list, fase: str) -> dict:
    """Udfaldet af kandidatmængderne, samme regel som SQL'en: præcis én kandidat, som ingen anden forældet nøgle også
    har → genfundet; relationer før parterne → afventer; ellers ikke_genfundet (ingen, flere eller delt kandidat)."""
    krav = Counter(n for g in gamle for n in g["kandidater"])
    ud = {}
    for g in gamle:
        k = g["kandidater"]
        if fase == "foer_parter" and g["art"] in RELATIONSARTER:
            ud[g["interpretation_key"]] = ("afventer", None, "afventer_parter")
        elif len(k) == 1 and krav[k[0]] == 1:
            ud[g["interpretation_key"]] = ("genfundet", k[0], None)
        else:
            ud[g["interpretation_key"]] = ("ikke_genfundet", None,
                                           "ingen" if not k else "flere" if len(k) > 1 else "delt")
    return ud


def laes_afstemning(a, *, fase: str | None = None) -> dict:
    """Kontrollér udskriften: form, referencer og at SQL'ens udfald er det, kandidatmængderne giver."""
    fejl = AfstemningError("AFSTEMNING_JSON_UGYLDIG")
    if not isinstance(a, dict) or a.get("contract") != AFSTEMNING_CONTRACT or a.get("fase") not in FASER:
        raise fejl
    if fase is not None and a["fase"] != fase:
        raise AfstemningError(f"AFSTEMNING_FASE_AFVIGER fase={a['fase']} forventet={fase}")
    try:
        _int(a["source_id"])
        gamle, nye, bindinger = a["gamle"], a["nye"], a["bindinger"]
        g_by = {_uuid(g["interpretation_key"]): g for g in gamle}
        n_by = {_uuid(n["interpretation_key"]): n for n in nye}
        if len(g_by) != len(gamle) or len(n_by) != len(nye) or set(g_by) & set(n_by):
            raise fejl
        for g in gamle:
            if g["art"] not in ARTER or g["udfald"] not in UDFALD:
                raise fejl
            if any(_uuid(k) not in n_by for k in g["kandidater"] + g["rettelse_kandidater"]):
                raise fejl
            for b in g["bindinger"]:
                _uuid(b["promotion_id"])
                _int(b["target_id"])
                if b["target_type"] not in ("assertion", "family"):
                    raise fejl
        udf = udled_udfald(gamle, a["fase"])
        for g in gamle:
            u, n, _ = udf[g["interpretation_key"]]
            if (g["udfald"], g.get("ny_noegle")) != (u, n):
                raise fejl
        fra_gamle = sorted((b["promotion_id"], g["interpretation_key"], b["target_type"], b["target_id"])
                           for g in gamle for b in g["bindinger"])
        fra_bind = sorted((b["promotion_id"], b["gammel_noegle"], b["target_type"], b["target_id"]) for b in bindinger)
        if fra_gamle != fra_bind or len({b["promotion_id"] for b in bindinger}) != len(bindinger):
            raise fejl
        for b in bindinger:
            g = g_by[b["gammel_noegle"]]
            if (b["udfald"], b.get("ny_noegle")) != (g["udfald"], g.get("ny_noegle")):
                raise fejl
            if not isinstance(b["ny_binding"], bool) or not isinstance(b["fremmed_binding"], bool):
                raise fejl
        saet = a["aegteskab_afgoerelsessaet"]
        if (a["fase"] == "foer_parter") != (saet is None) or (saet is not None and any(_uuid(k) != k for k in saet)):
            raise fejl
    except (KeyError, TypeError, AttributeError):
        raise fejl from None
    return a


# --- svarene ----------------------------------------------------------------------------------------------------------

def _laes_fakta(s) -> dict:
    fejl = AfstemningError("KORTSVAR_UGYLDIG")
    if not isinstance(s, dict) or s.get("contract") != KORTSVAR_CONTRACT:
        raise fejl
    try:
        for f in s["felter"]:
            _uuid(f["interpretation_key"])
            if f["svar"] not in ("B", "D", "V") or f["klasse"] not in ("MATCH", "REAL_DIFF", "SKRIVEMAADE"):
                raise fejl
        if any(p["svar"] != "-" for p in s["personas"]):
            raise AfstemningError("KORT_P_STOPPER")
        for k, _ in s["plan"]["maskine"]:
            _uuid(k)
    except (KeyError, TypeError, ValueError):
        raise fejl from None
    return s


def _laes_rel(r) -> dict:
    fejl = AfstemningError("RELATIONSSVAR_UGYLDIG")
    if not isinstance(r, dict) or r.get("contract") != RELATIONSSVAR_CONTRACT:
        raise fejl
    try:
        seen = set()
        for i in r["items"]:
            if (_uuid(i["interpretation_key"]) in seen or i["svar"] not in boern.TOKENS
                    or i["predicate"] not in ("relation.parent", "relation.child")):
                raise fejl
            seen.add(i["interpretation_key"])
    except (KeyError, TypeError):
        raise fejl from None
    return r


def _skaebner(a: dict, fakta: dict, rel: dict) -> dict:
    """Hvad der sker med hver ny nøgle efter svarene: bundet (MATCH/maskine), bundet_rettelse (B på REAL_DIFF eller
    SKRIVEMAADE: påstanden rettes, så bindes), afvist (D, R), uafklaret (V), accepteret (B på forælder/barn), forslag."""
    nye = {n["interpretation_key"]: n for n in a["nye"]}
    s = {}
    for f in fakta["felter"]:
        n = nye.get(f["interpretation_key"])
        if n is None or n["version"] != f["version"]:
            raise AfstemningError("SVAR_NOEGLE_UKENDT")
        if f["klasse"] == "MATCH":
            if f["svar"] != "B":
                raise AfstemningError("KORT_STIKPROEVE_IKKE_B")   # control_model_v2 ville give SAMPLE_FAILED
            s[f["interpretation_key"]] = "bundet"
        else:
            s[f["interpretation_key"]] = {"B": "bundet_rettelse", "D": "afvist", "V": "uafklaret"}[f["svar"]]
    for k, ver in fakta["plan"]["maskine"]:
        n = nye.get(k)
        if n is None or n["version"] != ver or k in s:
            raise AfstemningError("SVAR_NOEGLE_UKENDT")
        s[k] = "bundet"
    for i in rel["items"]:
        n = nye.get(i["interpretation_key"])
        if n is None or n["version"] != i["version"] or n["predicate"] != i["predicate"]:
            raise AfstemningError("SVAR_NOEGLE_UKENDT")
        s[i["interpretation_key"]] = {"B": "accepteret", "R": "afvist", "U": "forslag"}[i["svar"]]
    return s


def forventet(a: dict, fakta: dict, rel: dict) -> dict:
    """Den forventede tilstand efter afgørelser og bindinger, beregnet af afstemningen efter parterne og svarene.

    Returnerer udfald pr. forældet nøgle, pr. binding om den genbindes (og til hvilken ny nøgle), ægteskabernes
    forventede afgørelsessæt, relationsbindingerne og faktaenes forventede bindingsmål (til preflighten)."""
    laes_afstemning(a, fase="efter_parter")
    fakta, rel = _laes_fakta(fakta), _laes_rel(rel)
    if fakta["source_id"] != a["source_id"]:
        raise AfstemningError("KORTSVAR_UGYLDIG kilde")
    skaebne = _skaebner(a, fakta, rel)
    nye = {n["interpretation_key"]: n for n in a["nye"]}
    gamle = {g["interpretation_key"]: g for g in a["gamle"]}

    # Kandidaterne efter svarene: en afvist ny nøgle er ikke længere en kandidat; B på en rettelse af netop den
    # gamle bindings påstand gør den nye værdi lig påstandens, så rettelsen bliver kandidaten.
    kand = {}
    for k, g in gamle.items():
        c = [n for n in g["kandidater"] if skaebne.get(n) != "afvist"]
        if g["art"] == "fakta":
            r = [n for n in g["rettelse_kandidater"] if skaebne.get(n) == "bundet_rettelse"]
            if len(r) > 1 or (r and c and c != r):
                raise AfstemningError(f"AFSTEMNING_RETTELSE_KONFLIKT {k}")
            if r:
                c = r
        kand[k] = c
    udf = udled_udfald([{**g, "kandidater": kand[k]} for k, g in gamle.items()], a["fase"])

    bindinger, aegteskaber, relbind, fakta_maal = {}, set(), [], {}
    for b in a["bindinger"]:
        g = gamle[b["gammel_noegle"]]
        u, n, _ = udf[g["interpretation_key"]]
        gen = False
        if u == "genfundet":
            nn, sk = nye[n], skaebne.get(n)
            if g["art"] == "fakta" and b["target_type"] == "assertion":
                gen = sk == "bundet" or (sk == "bundet_rettelse" and n in g["rettelse_kandidater"])
                if gen:
                    fakta_maal[n] = b["target_id"]
            elif g["art"] == "aegteskab" and b["target_type"] == "family":
                # Review Focus 1: kun samme ægteskabsnummer og samme familie bindes maskinelt; ellers på kortet.
                gen = nn["marriage_ordinal"] == g["marriage_ordinal"] and nn["familie"] == b["target_id"]
                if gen:
                    aegteskaber.add(n)
            elif g["art"] in ("foraelder", "barn") and b["target_type"] == "family" and sk == "accepteret":
                if nn["familie"] != b["target_id"]:
                    raise AfstemningError(f"PREFLIGHT_MAAL_AFVIGER {n}")
                gen = True
            if gen and g["art"] in RELATIONSARTER:
                relbind.append({"interpretation_key": n, "family_id": b["target_id"], "predicate": nn["predicate"]})
        bindinger[b["promotion_id"]] = {"genbundet": gen, "ny_noegle": n if gen else None,
                                        "gammel_noegle": g["interpretation_key"], "target_type": b["target_type"],
                                        "target_id": b["target_id"]}
    aegteskaber = sorted(aegteskaber)
    if a["aegteskab_afgoerelsessaet"] != aegteskaber:
        # Mængde, ikke antal: maskinens afgørelse tager hele kildens sæt; et ekstra eller manglende ægteskab stopper.
        raise AfstemningError(f"AEGTESKAB_MAENGDE_AFVIGER faktisk={len(a['aegteskab_afgoerelsessaet'])} "
                              f"forventet={len(aegteskaber)}")
    # Faktaenes bindinger (kontrolleres i basen af preflighten): hver forventet binding rammer den gamle bindings
    # påstand; en MATCH, der ikke genbinder noget, må ikke ramme nogen af de gamle bindingers påstande.
    fakta_bundne = sorted(({"interpretation_key": k, "version": nye[k]["version"],
                            "klasse": "MATCH" if skaebne[k] == "bundet" else
                            next(f["klasse"] for f in fakta["felter"] if f["interpretation_key"] == k),
                            "maal": fakta_maal.get(k)}
                           for k in skaebne if skaebne[k] in ("bundet", "bundet_rettelse")),
                          key=lambda x: x["interpretation_key"])
    return {"udfald": {k: {"udfald": udf[k][0], "ny_noegle": udf[k][1]} for k in sorted(gamle)},
            "bindinger": dict(sorted(bindinger.items())), "aegteskaber": aegteskaber,
            "relationsbindinger": sorted(relbind, key=lambda x: x["interpretation_key"]),
            "fakta_bundne": fakta_bundne}


# --- tilbagetrækningsarket --------------------------------------------------------------------------------------------

def _tilbage(a: dict, fakta: dict, rel: dict) -> tuple[list[dict], str]:
    fv = forventet(a, fakta, rel)
    gamle = {g["interpretation_key"]: g for g in a["gamle"]}
    rest = []
    for p, b in fv["bindinger"].items():
        if not b["genbundet"]:
            g = gamle[b["gammel_noegle"]]
            rest.append({"promotion_id": p, "ref": f"{b['gammel_noegle']}@{b['target_type']}:{b['target_id']}",
                         "record_key": g["record_key"], "predicate": g["predicate"]})
    rest.sort(key=lambda x: (x["record_key"], x["predicate"], x["ref"]))
    grundlag = _sha(_canon({"contract": TILBAGETRAEK_CONTRACT, "afstemning_logisk_sha256": a.get("logisk_sha256"),
                            "refs": sorted(x["ref"] for x in rest), "fakta_sha256": _sha(_canon(fakta).encode()),
                            "relationssvar_sha256": _sha(_canon(rel).encode())}).encode())
    return rest, grundlag


def tilbagetraek_ark(a: dict, fakta: dict, rel: dict) -> str:
    """Token-arket: én linje pr. binding, der efter svarene ikke får en ny binding mod samme mål. Ubesvaret (_)."""
    rest, grundlag = _tilbage(a, fakta, rel)
    out = ["# ===================== TILBAGETRÆKNINGSARKET (6c-3) =====================",
           "# Kun linjerne, der starter med »T«, kan ændres — og kun tegnet efter kolonet. Alt med »#« er information.",
           "# Hver linje er en kildehenvisning, læseren ser i dag, som efter dine svar på faktakortene og",
           "# relationsarkene ikke får en ny binding mod samme mål. Begge svar trækker henvisningen tilbage:",
           "#   T = tilbagetræk · V = ved ikke (kvitteres som »ved ikke«).",
           "# Konteksten (posttekst og side) står på den lokale HTML-side.",
           f"# grundlag_sha256: {grundlag}", "#"]
    out += [f"T {x['ref']} : _  # {x['record_key']}, {x['predicate']}" for x in rest]
    return "\n".join(out) + "\n"


def parse_tilbagetraek(text: str, a: dict, fakta: dict, rel: dict) -> dict:
    """{promotion_id: {svar: 'T'|'ved_ikke', ref}} — præcis de forventede linjer, alle besvaret."""
    rest, grundlag = _tilbage(a, fakta, rel)
    m = GRUNDLAG_RE.search(text)
    if not m or m.group(1) != grundlag:
        raise AfstemningError("TILBAGETRAEK_GRUNDLAG_AFVIGER")
    by_ref = {x["ref"]: x for x in rest}
    svar = {}
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue
        t = T_RE.match(line)
        if not t or t["ref"] not in by_ref or t["tok"] not in ("T", "V") \
                or by_ref[t["ref"]]["promotion_id"] in svar:
            raise AfstemningError("TILBAGETRAEK_LINJE_UGYLDIG")
        svar[by_ref[t["ref"]]["promotion_id"]] = {"svar": "T" if t["tok"] == "T" else "ved_ikke", "ref": t["ref"]}
    if set(svar) != {x["promotion_id"] for x in rest}:
        raise AfstemningError(f"TILBAGETRAEK_LINJER_MANGLER antal={len(rest) - len(svar)}")
    return svar


# --- relationer-sql --------------------------------------------------------------------------------------------------

def relationer_sql(a: dict, fakta: dict, rel: dict) -> str:
    """Ægteskaberne: nøglemængden i private.relation_decision_set(kilde) mod de forventede (mængde, ikke antal; preview-
    RPC'en viser ikke nøglerne) umiddelbart før red_decide_relation_interpretations i samme transaktion. Derefter
    preview → batch-binding af alle genfundne relationer mod den gamle bindings familie (forældre og børn er afgjort
    af Task 4's SQL). Ingen række-id'er i filen: nøgle → gældende version slås op i transaktionen."""
    fv = forventet(a, fakta, rel)
    src = _int(a["source_id"])
    aeg = fv["aegteskaber"]
    binds = [{"interpretation_key": _uuid(b["interpretation_key"]), "family_id": _int(b["family_id"])}
             for b in fv["relationsbindinger"]]
    out = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) \\g /dev/null",
           "-- (1) ægteskaberne: afgørelsessættets nøglemængde = de forventede, umiddelbart før afgørelsen",
           f"DO $m$ DECLARE s jsonb := private.relation_decision_set({src}); f jsonb := "
           f"{_lit(json.dumps(aeg))}::jsonb; faktisk jsonb; BEGIN "
           "SELECT coalesce(jsonb_agg(x#>>'{state,interpretation,interpretation_key}' ORDER BY "
           "x#>>'{state,interpretation,interpretation_key}' COLLATE \"C\"), '[]'::jsonb) INTO faktisk "
           "FROM jsonb_array_elements(s->'items') x; "
           "IF faktisk IS DISTINCT FROM f THEN RAISE EXCEPTION 'AEGTESKAB_MAENGDE_AFVIGER faktisk=% forventet=%', "
           "jsonb_array_length(faktisk), jsonb_array_length(f); END IF; "
           "PERFORM set_config('daa.tekstrevision_aegteskab_sha256', s->>'set_sha256', true); END $m$;"]
    if aeg:
        out += ["SET LOCAL ROLE authenticated;",
                "DO $d$ DECLARE n int; BEGIN PERFORM set_config('app.change_set_id','',true); "
                f"n := public.red_decide_relation_interpretations({src}, "
                "current_setting('daa.tekstrevision_aegteskab_sha256')); "
                f"IF n <> {len(aeg)} THEN RAISE EXCEPTION 'AEGTESKAB_MAENGDE_AFVIGER afgjort=% forventet={len(aeg)}', n; "
                "END IF; END $d$;",
                "RESET ROLE;"]
    if binds:
        f = _lit(json.dumps(binds, sort_keys=True))
        out += ["-- (2) bindingerne: hver genfunden relation mod den gamle bindings familie",
                f"DO $i$ DECLARE f jsonb := {f}::jsonb; items jsonb; BEGIN "
                "SELECT jsonb_agg(jsonb_build_object('interpretation_id', ic.id::text, 'family_id', "
                "(e->>'family_id')::bigint) ORDER BY e->>'interpretation_key') INTO items "
                "FROM jsonb_array_elements(f) e CROSS JOIN LATERAL (SELECT c.id, c.status, c.source_id "
                "FROM private.interpretation_current c WHERE c.interpretation_key = (e->>'interpretation_key')::uuid) ic "
                f"WHERE ic.status = 'accepted' AND ic.source_id = {src}; "
                "IF coalesce(jsonb_array_length(items), 0) <> jsonb_array_length(f) THEN RAISE EXCEPTION "
                "'RELATION_BINDING_IKKE_ACCEPTERET % af %', coalesce(jsonb_array_length(items), 0), "
                "jsonb_array_length(f); END IF; "
                "PERFORM set_config('daa.tekstrevision_relation_items', items::text, true); END $i$;",
                "SET LOCAL ROLE authenticated;",
                "DO $b$ DECLARE items jsonb := current_setting('daa.tekstrevision_relation_items')::jsonb; p jsonb; "
                "r text; BEGIN PERFORM set_config('app.change_set_id','',true); "
                f"p := public.red_preview_relation_promotions({src}, items); "
                "SELECT i->>'reason_code' INTO r FROM jsonb_array_elements(p->'items') i "
                "WHERE (i->>'eligible')::boolean IS NOT TRUE ORDER BY (i->>'item_ordinal')::int LIMIT 1; "
                "IF r IS NOT NULL OR jsonb_array_length(p->'items') <> jsonb_array_length(items) THEN "
                "RAISE EXCEPTION 'RELATION_BINDING_IKKE_KLAR %', coalesce(r, 'antal'); END IF; "
                "PERFORM set_config('app.change_set_id','',true); "
                f"PERFORM public.red_promote_relation_interpretations_batch({src}, items, p->>'preview_sha256'); "
                "END $b$;",
                "RESET ROLE;",
                "-- (3) kontrol før COMMIT: hver ny nøgle har en gyldig familiebinding mod netop den familie",
                f"DO $c$ DECLARE f jsonb := {f}::jsonb; n int; BEGIN SELECT count(*) INTO n "
                "FROM jsonb_array_elements(f) e WHERE EXISTS (SELECT 1 FROM "
                "private.text_revision_binding_set(ARRAY[(e->>'interpretation_key')::uuid]) t "
                "WHERE t.target_type = 'family' AND t.target_id = e->>'family_id'); "
                "IF n <> jsonb_array_length(f) THEN RAISE EXCEPTION 'RELATION_BINDING_MANGLER % af %', n, "
                "jsonb_array_length(f); END IF; END $c$;"]
    out += ["COMMIT;", f"\\echo 'RELATIONER_OK aegteskaber={len(aeg)} bindinger={len(binds)}'"]
    return "\n".join(out) + "\n"


# --- kvitteringen og preflighten --------------------------------------------------------------------------------------

def _inline_afstemning(fase: str) -> list[str]:
    return ["\\set afstemning_inline 1", f"\\set fase {fase}", "\\o /dev/null", f"\\i {AFSTEMNING_SQL}", "\\o"]


def kvittering_sql(a: dict, fakta: dict, rel: dict, tv: dict, *, kontekst: dict) -> str:
    """Ét kald til private.write_text_revision_reconciliation med alle items. Items bygges i transaktionen af
    tilstanden efter bindingerne (afstemningen genkørt med fase efter_afgoerelser): genbundet slår den nye promotion op
    via den nye nøgles gyldige binding mod samme mål. Filen bærer kun forventningen (udfald og genbundet pr. binding)
    og T/V-svarene; afviger tilstanden fra forventningen, stopper kvitteringen (deklareret stoppunkt → fortryd)."""
    fv = forventet(a, fakta, rel)
    rest = {p for p, b in fv["bindinger"].items() if not b["genbundet"]}
    if set(tv) != rest:
        raise AfstemningError(f"TILBAGETRAEK_SVAR_AFVIGER mangler={len(rest - set(tv))} ekstra={len(set(tv) - rest)}")
    for p, x in tv.items():
        if x["svar"] not in ("T", "ved_ikke") or not isinstance(x.get("ref"), str) or not x["ref"].strip():
            raise AfstemningError("TILBAGETRAEK_SVAR_AFVIGER")
    for felt in ("svar_sha256", "relationssvar_sha256", "tilbagetraek_sha256", "oversat_ark_sha256"):
        if not re.fullmatch(r"[0-9a-f]{64}", str(kontekst.get(felt, ""))):
            raise AfstemningError(f"KVITTERING_KONTEKST_UGYLDIG {felt}")
    e = {"udfald": fv["udfald"],
         "bindinger": {p: {"genbundet": b["genbundet"], "ny_noegle": b["ny_noegle"],
                           "svar": tv[p]["svar"] if p in tv else None, "ref": tv[p]["ref"] if p in tv else None}
                       for p, b in fv["bindinger"].items()}}
    ctx = {"contract": KVITTERING_CONTRACT, "afstemning_logisk_sha256": a.get("logisk_sha256"),
           **{k: kontekst[k] for k in ("svar_sha256", "relationssvar_sha256", "tilbagetraek_sha256",
                                       "oversat_ark_sha256")}}
    n_gen = sum(1 for b in fv["bindinger"].values() if b["genbundet"])
    body = "\n".join([
        "DO $k$",
        "DECLARE s jsonb := current_setting('daa.tekstrevision_afstemning')::jsonb;",
        f"        e jsonb := {_jlit(e)}::jsonb;",
        f"        ctx jsonb := {_jlit(ctx)}::jsonb;",
        "        items jsonb := '[]'::jsonb; g jsonb; b jsonb; x jsonb; v_prom text; n int; r jsonb;",
        "BEGIN",
        "  IF s->>'fase' IS DISTINCT FROM 'efter_afgoerelser' THEN RAISE EXCEPTION 'KVITTERING_FASE_AFVIGER'; END IF;",
        # De forældede nøgler: samme mængde og samme udfald som forventet (tilstanden, ikke svarene, bestemmer).
        "  IF (SELECT coalesce(jsonb_agg(y->>'interpretation_key' ORDER BY y->>'interpretation_key' COLLATE \"C\"),'[]')",
        "        FROM jsonb_array_elements(s->'gamle') y)",
        "     IS DISTINCT FROM (SELECT coalesce(jsonb_agg(k ORDER BY k COLLATE \"C\"),'[]')",
        "        FROM jsonb_object_keys(e->'udfald') k) THEN",
        "    RAISE EXCEPTION 'KVITTERING_TILSTAND_AFVIGER: nøglemængden'; END IF;",
        "  FOR g IN SELECT y FROM jsonb_array_elements(s->'gamle') y LOOP",
        "    x := e->'udfald'->(g->>'interpretation_key');",
        "    IF g->>'udfald' IS DISTINCT FROM x->>'udfald' OR g->>'ny_noegle' IS DISTINCT FROM x->>'ny_noegle' THEN",
        "      RAISE EXCEPTION 'KVITTERING_TILSTAND_AFVIGER: %', g->>'interpretation_key'; END IF;",
        "    items := items || CASE WHEN g->>'udfald' = 'genfundet'",
        "      THEN jsonb_build_object('old_interpretation_key', g->>'interpretation_key', 'outcome', 'genfundet',",
        "                              'new_interpretation_key', g->>'ny_noegle')",
        "      ELSE jsonb_build_object('old_interpretation_key', g->>'interpretation_key', 'outcome', 'ikke_genfundet')",
        "      END;",
        "  END LOOP;",
        # Bindingerne: samme mængde; genbundet = tilstanden (gyldig binding på den nye nøgle mod samme mål).
        "  IF (SELECT coalesce(jsonb_agg(y->>'promotion_id' ORDER BY y->>'promotion_id' COLLATE \"C\"),'[]')",
        "        FROM jsonb_array_elements(s->'bindinger') y)",
        "     IS DISTINCT FROM (SELECT coalesce(jsonb_agg(k ORDER BY k COLLATE \"C\"),'[]')",
        "        FROM jsonb_object_keys(e->'bindinger') k) THEN",
        "    RAISE EXCEPTION 'KVITTERING_TILSTAND_AFVIGER: bindingsmængden'; END IF;",
        "  FOR b IN SELECT y FROM jsonb_array_elements(s->'bindinger') y LOOP",
        "    x := e->'bindinger'->(b->>'promotion_id');",
        "    IF (b->>'fremmed_binding')::boolean THEN",
        "      RAISE EXCEPTION 'KVITTERING_FREMMED_BINDING: %', b->>'promotion_id'; END IF;",
        "    IF (b->>'ny_binding')::boolean IS DISTINCT FROM (x->>'genbundet')::boolean",
        "       OR ((x->>'genbundet')::boolean AND b->>'ny_noegle' IS DISTINCT FROM x->>'ny_noegle') THEN",
        "      RAISE EXCEPTION 'KVITTERING_TILSTAND_AFVIGER: %', b->>'promotion_id'; END IF;",
        "    IF (b->>'ny_binding')::boolean THEN",
        "      SELECT min(t.promotion_id::text), count(*) INTO v_prom, n",
        "        FROM private.text_revision_binding_set(ARRAY[(b->>'ny_noegle')::uuid]) t",
        "       WHERE t.target_type = b->>'target_type' AND t.target_id = b->>'target_id';",
        "      IF n <> 1 THEN RAISE EXCEPTION 'KVITTERING_TILSTAND_AFVIGER: % (% nye bindinger)', b->>'promotion_id', n;",
        "      END IF;",
        "      items := items || jsonb_build_object('old_interpretation_key', b->>'gammel_noegle',",
        "        'old_promotion_id', b->>'promotion_id', 'outcome', 'genbundet', 'new_interpretation_key', b->>'ny_noegle',",
        "        'new_promotion_id', v_prom);",
        "    ELSE",
        "      items := items || jsonb_build_object('old_interpretation_key', b->>'gammel_noegle',",
        "        'old_promotion_id', b->>'promotion_id', 'outcome', 'tilbagetrukket', 'svar', x->>'svar', 'ref', x->>'ref');",
        "    END IF;",
        "  END LOOP;",
        "  r := private.write_text_revision_reconciliation(current_setting('daa.afstemning_batch')::uuid, items, ctx);",
        "  RAISE NOTICE 'TEKSTREVISION_KVITTERING_OK %', r;",
        "END $k$;"])
    out = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) \\g /dev/null",
           "-- Afstemningen genkørt efter bindingerne (tilstanden bestemmer genbundet; kræver -v batch=<revisionens batch>)",
           *_inline_afstemning("efter_afgoerelser"), body, "COMMIT;",
           f"\\echo 'KVITTERING_FORVENTET noegler={len(fv['udfald'])} bindinger={len(fv['bindinger'])} "
           f"genbundet={n_gen} tilbagetrukket={len(rest)}'"]
    return "\n".join(out) + "\n"


def preflight_sql(a: dict, fakta: dict, rel: dict) -> str:
    """Læse-kun, før første binding (efter parter, klassifikation og oversaet): afstemningen i basen er den forventede
    (samme nøgler, versioner, statusser, kandidater og mål), hvert forventet faktamål er den gamle bindings påstand
    (klassifikationen), og tilbagetrækningerne er præcis resten af revisionens bindinger."""
    fv = forventet(a, fakta, rel)
    src = _int(a["source_id"])
    e = {k: v for k, v in a.items() if k != "batch_id"}
    gamle_maal = sorted({b["target_id"] for b in a["bindinger"] if b["target_type"] == "assertion"})
    genbind = sorted(p for p, b in fv["bindinger"].items() if b["genbundet"])
    tilbage = sorted(p for p, b in fv["bindinger"].items() if not b["genbundet"])
    body = "\n".join([
        "DO $p$",
        f"DECLARE f jsonb := {_jlit(fv['fakta_bundne'])}::jsonb;",
        "        s jsonb := current_setting('daa.tekstrevision_afstemning')::jsonb;",
        f"        e jsonb := {_jlit(e)}::jsonb;",
        f"        gm jsonb := {_lit(json.dumps(gamle_maal))}::jsonb;",
        f"        gb jsonb := {_lit(json.dumps(genbind))}::jsonb;",
        f"        tb jsonb := {_lit(json.dumps(tilbage))}::jsonb;",
        "        c jsonb := current_setting('daa.control_result')::jsonb; n int; sek text;",
        "BEGIN",
        "  FOREACH sek IN ARRAY ARRAY['fase','source_id','gamle','nye','bindinger','aegteskab_afgoerelsessaet','logisk_sha256'] LOOP",
        "    IF s->sek IS DISTINCT FROM e->sek THEN",
        "      RAISE EXCEPTION 'PREFLIGHT_AFSTEMNING_AFVIGER sektion=%', sek; END IF;",
        "  END LOOP;",
        # Faktaenes forventede bindinger mod klassifikationen i basen (samme kilde-scope som kontrolmodellen).
        "  SELECT count(*) INTO n FROM jsonb_array_elements(f) x WHERE NOT EXISTS (",
        "    SELECT 1 FROM jsonb_array_elements(c->'items') i JOIN private.interpretation q",
        "        ON q.id = (i->>'interpretation_id')::uuid",
        "     WHERE q.interpretation_key = (x->>'interpretation_key')::uuid",
        "       AND (i->>'version')::int = (x->>'version')::int AND i->>'class' = x->>'klasse'",
        "       AND (x->>'klasse' <> 'MATCH'",
        "            OR (x->'maal' <> 'null'::jsonb AND (i->>'assertion_id')::bigint = (x->>'maal')::bigint)",
        "            OR (x->'maal' = 'null'::jsonb AND NOT (i->'assertion_id' <@ gm))));",
        "  IF n <> 0 THEN RAISE EXCEPTION 'PREFLIGHT_MAAL_AFVIGER % af %', n, jsonb_array_length(f); END IF;",
        # Tilbagetrækningerne er præcis resten: revisionens bindinger = genbundne ∪ tilbagetrukne, disjunkte.
        "  IF (SELECT coalesce(jsonb_agg(y->>'promotion_id' ORDER BY y->>'promotion_id' COLLATE \"C\"),'[]')",
        "        FROM jsonb_array_elements(s->'bindinger') y)",
        "     IS DISTINCT FROM (SELECT coalesce(jsonb_agg(z ORDER BY z COLLATE \"C\"),'[]')",
        "        FROM (SELECT jsonb_array_elements_text(gb) z UNION ALL SELECT jsonb_array_elements_text(tb)) w) THEN",
        "    RAISE EXCEPTION 'PREFLIGHT_TILBAGETRAEK_AFVIGER'; END IF;",
        f"  RAISE NOTICE 'TEKSTREVISION_PREFLIGHT_OK noegler=% bindinger=% genbind={len(genbind)} "
        f"tilbagetraek={len(tilbage)} fakta_bundne=%',",
        "    jsonb_array_length(s->'gamle'), jsonb_array_length(s->'bindinger'), jsonb_array_length(f);",
        "END $p$;"])
    out = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET TRANSACTION READ ONLY;", "SET LOCAL standard_conforming_strings=on;",
           "-- Afstemningen og kontrolmodellens klassifikation, begge læse-kun (kræver -v batch=<revisionens batch>)",
           *_inline_afstemning("efter_parter"),
           f"SELECT set_config('daa.control_src', '{src}', true) \\g /dev/null",
           "\\o /dev/null", f"\\i {CLASSIFICATION_SQL}", "\\o", body, "ROLLBACK;"]
    return "\n".join(out) + "\n"


# --- afgrænsningen ----------------------------------------------------------------------------------------------------

def _laes_idkort(idk) -> dict:
    fejl = AfstemningError("IDKORT_UGYLDIG")
    if not isinstance(idk, dict) or idk.get("contract") != IDKORT_CONTRACT:
        raise fejl
    try:
        ids = [_uuid(e["id"]) for e in idk["interpretations"]]
        for e in idk["interpretations"]:
            _uuid(e["interpretation_key"])
            _int(e["version"])
        pids = [_uuid(p["id"]) for p in idk["personas"]]
        if len(set(ids)) != len(ids) or len(set(pids)) != len(pids):
            raise fejl
        nk = [(e["interpretation_key"]) for e in idk["interpretations"]]
        if len(set(nk)) != len(nk):
            raise fejl
    except (KeyError, TypeError):
        raise fejl from None
    return idk


def tjek_afgraenset(classification: dict, rows: list, tilladt: set) -> None:
    """Efter beskæringen: intet id uden for nøglelisten i klassifikationen eller rækkerne."""
    laek = sum(1 for i in classification.get("items", []) if i.get("interpretation_id") not in tilladt) \
        + sum(1 for r in rows if r.get("interpretation_id") not in tilladt)
    if laek:
        raise AfstemningError(f"AFGRAENSNING_LAEK antal={laek}")


def tjek_plan_afgraenset(plan: dict, idk: dict) -> None:
    """Planens forslag og personas ligger alle i det afgrænsede id-kort; ellers AFGRAENSNING_LAEK."""
    _laes_idkort(idk)
    if idk.get("afgraenset") is not True:
        raise AfstemningError("IDKORT_IKKE_AFGRAENSET")
    ids = {e["id"] for e in idk["interpretations"]}
    pids = {p["id"] for p in idk["personas"]}
    plan_ids = (set(plan["universe_ids"]) | {r["interpretation_id"] for r in plan["rows_kontrol"]}
                | {m[0] for m in plan["match"]} | {m["interpretation_id"] for m in plan["machine_candidates"]}
                | set(plan["sample_ids"]) | set(plan["real_diff_ids"]) | set(plan["skrivemaade_ids"]))
    plan_p = set(plan["persona_ids"]) | {r["persona_id"] for r in plan["rows_kontrol"]}
    laek = len(plan_ids - ids) + len(plan_p - pids)
    if laek:
        raise AfstemningError(f"AFGRAENSNING_LAEK antal={laek}")


def afgraens(noegler: list, idk: dict, classification: dict, rows: list) -> tuple[dict, list, dict]:
    _laes_idkort(idk)
    if idk.get("afgraenset"):
        raise AfstemningError("IDKORT_UGYLDIG allerede afgrænset")
    if not isinstance(classification, dict) or not isinstance(classification.get("items"), list) \
            or not isinstance(rows, list):
        raise AfstemningError("CLASSIFICATION_INVALID")
    want = set(noegler)
    tilladt = {e["id"] for e in idk["interpretations"] if e["interpretation_key"] in want}
    items = [i for i in classification["items"] if i.get("interpretation_id") in tilladt]
    rows2 = [r for r in rows if r.get("interpretation_id") in tilladt]
    tjek_afgraenset({"items": items}, rows2, tilladt)
    # Antallene genberegnes som klassifikationens grid: pr. prædikat i scope alle faste klasser, de to nye kun, når de
    # forekommer.
    klasser = list(BASIS_KLASSER) + [c for c in NYE_KLASSER if any(i["class"] == c for i in items)]
    counts = {p: {c: sum(1 for i in items if i["predicate"] == p and i["class"] == c) for c in klasser}
              for p in sorted({i["predicate"] for i in items})}
    personas = {r.get("persona_id") for r in rows2}
    idk2 = {**idk, "afgraenset": True, "noegler_sha256": _sha(("\n".join(sorted(want)) + "\n").encode()),
            "interpretations": [e for e in idk["interpretations"] if e["id"] in tilladt],
            "personas": [p for p in idk["personas"] if p["id"] in personas]}
    return {**classification, "items": items, "counts": counts}, rows2, idk2


# --- kortsvar og oversaet ---------------------------------------------------------------------------------------------

def _klasser(plan: dict) -> dict:
    return {**{i: "REAL_DIFF" for i in plan["real_diff_ids"]}, **{i: "SKRIVEMAADE" for i in plan["skrivemaade_ids"]},
            **{i: "MATCH" for i in plan["sample_ids"]}}


def grundlag_sha256(r: dict, klasse: str, person) -> str:
    """Et id-uafhængigt beslutningsgrundlag pr. felt (Codex fund 6): klasse, personaens kanoniske person, prædikat,
    post, version, navnereglen, værdiens hash, rettelsesmålets påstand som (person, faktatype, kilde) med forventet
    tilstand og datogrænser, og datogrænserne, en rettelse ville skrive. Ingen række-id'er."""
    maal = r.get("rettelse_maal")
    m = None
    if isinstance(maal, dict):
        fv = maal.get("forventet") or {}
        m = {"person": person, "faktatype": fv.get("faktatype"), "kilde": fv.get("citation_sources"),
             "vaerdi_tekst": fv.get("vaerdi_tekst"), "date_raw": fv.get("date_raw"),
             "valgt": fv.get("valgt_assertion_id") == maal.get("assertion_id"), "graenser": maal.get("graenser")}
    vt = r.get("value_text")
    g = {"contract": GRUNDLAG_CONTRACT, "klasse": klasse, "person": person, "praedikat": r["predicate"],
         "post": r.get("record_key"), "version": r["version"], "navn_forkortes": r.get("navn_forkortes"),
         "vaerdi_sha256": None if vt is None else _sha(vt.encode("utf-8")), "rettelse_maal": m,
         "p_dato": v2._p_dato(vt) if r["predicate"] in v2.DATE_PREDICATES and vt is not None else None}
    return _sha(_canon(g).encode("utf-8"))


def _plan_noegler(plan: dict, imap: dict) -> dict:
    def kv(i):
        e = imap[i]
        return [e["interpretation_key"], e["version"]]
    return {"univers": sorted(kv(i) for i in plan["universe_ids"]),
            "match": sorted(kv(m[0]) for m in plan["match"]),
            "maskine": sorted(kv(m["interpretation_id"]) for m in plan["machine_candidates"]),
            "stikproeve": sorted(imap[i]["interpretation_key"] for i in plan["sample_ids"]),
            "real_diff": sorted(imap[i]["interpretation_key"] for i in plan["real_diff_ids"]),
            "skrivemaade": sorted(imap[i]["interpretation_key"] for i in plan["skrivemaade_ids"])}


def _felt_grundlag(plan: dict, idk: dict) -> tuple[dict, dict, dict]:
    """Pr. planfelt: (nøgle, version, klasse, grundlag); personas som (persona_key, identity_version)."""
    tjek_plan_afgraenset(plan, idk)
    imap = {e["id"]: e for e in idk["interpretations"]}
    pmap = {p["id"]: p for p in idk["personas"]}
    klasse = _klasser(plan)
    felter = {}
    for r in plan["rows_kontrol"]:
        e = imap[r["interpretation_id"]]
        if e["version"] != r["version"]:
            raise AfstemningError("IDKORT_VERSION_AFVIGER")
        felter[r["interpretation_id"]] = {
            "interpretation_key": e["interpretation_key"], "version": r["version"],
            "klasse": klasse[r["interpretation_id"]],
            "grundlag_sha256": grundlag_sha256(r, klasse[r["interpretation_id"]],
                                               pmap[r["persona_id"]]["canonical_person_id"])}
    personas = {p["persona_id"]: {"persona_key": pmap[p["persona_id"]]["persona_key"],
                                  "identity_version": p["identity_version"]} for p in plan["personas"]}
    return felter, personas, imap


def kortsvar(plan: dict, ark_text: str, idk: dict) -> dict:
    felter, personas, imap = _felt_grundlag(plan, idk)
    fields, p_svar = v2.parse_sheet_v2(ark_text)
    v2.check_sheet_v2(plan, fields, p_svar)
    if any(p.token != "-" for p in p_svar):
        # En identitetsændring hører ikke til ceremonien (Codex fund 7): stop før prod.
        raise AfstemningError(f"KORT_P_STOPPER personas={sum(1 for p in p_svar if p.token != '-')}")
    ud = []
    for f in fields:
        x = felter[f.interpretation_id]
        if x["version"] != f.version:
            raise AfstemningError("IDKORT_VERSION_AFVIGER")
        ud.append({**x, "svar": f.token, "note": f.note})
    return {"contract": KORTSVAR_CONTRACT, "source_id": plan["source_id"],
            "felter": sorted(ud, key=lambda x: x["interpretation_key"]),
            "personas": [{**personas[p.persona_id], "svar": "-"} for p in p_svar],
            "plan": _plan_noegler(plan, imap)}


def oversaet(svar: dict, plan: dict, meta: dict, idk: dict) -> str:
    """svar.json → ark v2 med prods id'er. Prods plan skal have samme nøgler, versioner, klasser, grundlag og personas
    (og samme plan-mængder); ellers KORT_PROD_AFVIGER og intet ark."""
    s = _laes_fakta(svar)
    felter, personas, imap = _felt_grundlag(plan, idk)
    want_f = {(f["interpretation_key"], f["version"], f["klasse"], f["grundlag_sha256"]) for f in s["felter"]}
    have_f = {(x["interpretation_key"], x["version"], x["klasse"], x["grundlag_sha256"]) for x in felter.values()}
    want_p = {(p["persona_key"], p["identity_version"]) for p in s["personas"]}
    have_p = {(p["persona_key"], p["identity_version"]) for p in personas.values()}
    plan_ok = _plan_noegler(plan, imap) == s["plan"]
    if want_f != have_f or want_p != have_p or not plan_ok or s["source_id"] != plan["source_id"]:
        raise AfstemningError(f"KORT_PROD_AFVIGER felter={len(want_f ^ have_f)} personas={len(want_p ^ have_p)} "
                              f"plan={'ok' if plan_ok else 'afviger'}")
    by_key = {f["interpretation_key"]: f for f in s["felter"]}
    fields = {i: (by_key[x["interpretation_key"]]["svar"], by_key[x["interpretation_key"]]["note"])
              for i, x in felter.items()}
    text = v2.render_sheet_v2(plan, {pid: "-" for pid in personas}, fields)
    # Samme kontrol som control_model_v2.py sql: arket skal kunne anvendes på prods plan.
    v2.apply_plan_v2(plan, text, sheet_sha256=_sha(text.encode("utf-8")), hashes=meta)
    return text


# --- parter -----------------------------------------------------------------------------------------------------------

def parter_logisk(manifest: dict, inp: dict) -> dict:
    """Pr. element: record, ny nøgle, prædikat, post_offset, spændlængde, navnets placering i spændet, ægteskabsnummer,
    klausulsættets (indholds)hash og værdiens hash. Ingen klausul-id'er (tilfældige pr. base; Codex fund 2)."""
    try:
        rows = {r["interpretation_key"]: r for r in inp["input"]}
        el = []
        for navn, p in sorted(manifest["authorized_elements"].items()):
            r = rows.get(p["interpretation_key"])
            if r is None or r["interpretation_version"] != p["interpretation_version"]:
                raise AfstemningError("PARTER_INPUT_MANGLER")
            navnet = None if p["name_from"] is None else [p["name_from"] - p["span_from"], p["name_to"] - p["span_from"]]
            el.append({"element": navn, "interpretation_key": p["interpretation_key"],
                       "interpretation_version": p["interpretation_version"], "record_key": r["record_key"],
                       "predicate": p["predicate"], "post_offset": p["post_offset"],
                       "spaend": p["span_to"] - p["span_from"], "navn": navnet,
                       "marriage_ordinal": p["marriage_ordinal"], "clause_set_seq": p["clause_set_seq"],
                       "clause_set_sha256": p["clause_set_sha256"], "profile": p["profile"],
                       "birth_raw": p["birth_raw"], "death_raw": p["death_raw"],
                       "vaerdi_sha256": _sha((r["raw"] or "").encode("utf-8"))})
        counts = manifest["expected_counts"]
    except (KeyError, TypeError):
        raise AfstemningError("PARTER_MANIFEST_UGYLDIG") from None
    return {"contract": PARTER_CONTRACT, "expected_counts": counts, "elementer": el,
            "elementer_sha256": _sha(_canon(el).encode("utf-8"))}


def parter_filtrer(manifest: dict, noegler: list) -> dict:
    want = set(noegler)
    el = {k: p for k, p in manifest["authorized_elements"].items() if p["interpretation_key"] in want}
    return {**manifest, "authorized_elements": dict(sorted(el.items())),
            "expected_counts": {**manifest["expected_counts"], "relation_personas": len(el)}}


# --- relationssvar ----------------------------------------------------------------------------------------------------

def relationssvar(foraelder_text: str | None, boerne_text: str | None) -> dict:
    items, seen = [], set()
    for text, mod, praed in ((foraelder_text, foraeldre, "relation.parent"), (boerne_text, boern, "relation.child")):
        if text is None:
            continue
        for line in mod.parse_sheet(text):
            if line.tok not in boern.TOKENS or line.key in seen:
                raise AfstemningError("RELATIONSSVAR_UGYLDIG")
            seen.add(line.key)
            items.append({"interpretation_key": line.key, "version": line.version, "predicate": praed,
                          "svar": line.tok})
    return {"contract": RELATIONSSVAR_CONTRACT, "items": items}


# --- CLI --------------------------------------------------------------------------------------------------------------

def _p(path: str, root: Path) -> Path:
    return check_private_path(Path(path), root)


def _laes(path: str, root: Path):
    return json.loads(_p(path, root).read_bytes().decode("utf-8"))


def _skriv_json(path: Path, obj) -> str:
    return _write(path, (json.dumps(obj, ensure_ascii=False, sort_keys=True, indent=1) + "\n").encode("utf-8"))


def _skriv_tekst(path: Path, text: str) -> str:
    return _write(path, text.encode("utf-8"))


def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    def cmd(navn, *args):
        p = sub.add_parser(navn)
        for a in args:
            p.add_argument(a, required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
        return p

    n = cmd("noegler", "--afstemning", "--out")
    n.add_argument("--praedikat", action="append", default=None)
    cmd("afgraens", "--noegler", "--idkort", "--classification", "--rows", "--out-dir")
    cmd("kortsvar", "--plan-dir", "--ark", "--idkort", "--out")
    cmd("oversaet", "--svar", "--plan-dir", "--idkort", "--out")
    r = cmd("relationssvar", "--out")
    r.add_argument("--foraelderark")
    r.add_argument("--boerneark")
    cmd("relationer-sql", "--afstemning", "--fakta-svar", "--relationssvar", "--out")
    cmd("parter-filtrer", "--manifest", "--noegler", "--out")
    cmd("parter-logisk", "--manifest", "--input", "--out")
    cmd("parter-sammenlign", "--forventet", "--manifest", "--input")
    cmd("tilbagetraek-ark", "--afstemning", "--fakta-svar", "--relationssvar", "--out")
    cmd("tilbagetraek-tjek", "--afstemning", "--fakta-svar", "--relationssvar", "--ark")
    cmd("kvittering-sql", "--afstemning", "--fakta-svar", "--relationssvar", "--tilbagetraek", "--oversat-ark",
        "--out", "--preflight")
    args = ap.parse_args(argv)
    root = Path(args.private_root)
    try:
        if args.cmd == "noegler":
            a = laes_afstemning(_laes(args.afstemning, root))
            keys = sorted(x["interpretation_key"] for x in a["nye"]
                          if args.praedikat is None or x["predicate"] in args.praedikat)
            sha = _skriv_tekst(_p(args.out, root), "".join(f"{k}\n" for k in keys))
            print(f"NOEGLER_OK fase={a['fase']} noegler={len(keys)} sha256 {sha}")
        elif args.cmd == "afgraens":
            keys = boern.load_keys(_p(args.noegler, root).read_text(encoding="utf-8"))
            k, rows, idk = _laes(args.classification, root), _laes(args.rows, root), _laes(args.idkort, root)
            k2, rows2, idk2 = afgraens(keys, idk, k, rows)
            ud = _p(args.out_dir, root)
            ks = _skriv_json(ud / "classification.json", k2)
            rs = _skriv_json(ud / "rows.json", rows2)
            iss = _skriv_json(ud / "idkort.json", idk2)
            klasser = Counter(i["class"] for i in k2["items"])
            print(f"AFGRAENS_OK noegler={len(keys)} items={len(k['items'])}->{len(k2['items'])} "
                  f"rows={len(rows)}->{len(rows2)} klasser={json.dumps(dict(sorted(klasser.items())))}")
            print(f"  classification_sha256 {ks}\n  rows_sha256 {rs}\n  idkort_sha256 {iss}")
        elif args.cmd == "kortsvar":
            plan, _ = v2._load_plan(_p(args.plan_dir, root))
            s = kortsvar(plan, _p(args.ark, root).read_bytes().decode("utf-8"), _laes(args.idkort, root))
            sha = _skriv_json(_p(args.out, root), s)
            svar = Counter(f["svar"] for f in s["felter"])
            print(f"KORTSVAR_OK felter={len(s['felter'])} personas={len(s['personas'])} "
                  f"svar={json.dumps(dict(sorted(svar.items())))} sha256 {sha}")
        elif args.cmd == "oversaet":
            svar = _laes(args.svar, root)
            plan, meta = v2._load_plan(_p(args.plan_dir, root))
            text = oversaet(svar, plan, meta, _laes(args.idkort, root))
            sha = _skriv_tekst(_p(args.out, root), text)
            print(f"OVERSAET_OK felter={len(plan['rows_kontrol'])} personas={len(plan['personas'])} "
                  f"svar_sha256 {_sha(_p(args.svar, root).read_bytes())} ark_sha256 {sha}")
        elif args.cmd == "relationssvar":
            if args.foraelderark is None and args.boerneark is None:
                raise AfstemningError("RELATIONSSVAR_UGYLDIG intet ark")
            fx = None if args.foraelderark is None else _p(args.foraelderark, root).read_text(encoding="utf-8")
            bx = None if args.boerneark is None else _p(args.boerneark, root).read_text(encoding="utf-8")
            r = relationssvar(fx, bx)
            sha = _skriv_json(_p(args.out, root), r)
            print(f"RELATIONSSVAR_OK items={len(r['items'])} "
                  f"svar={json.dumps(dict(sorted(Counter(i['svar'] for i in r['items']).items())))} sha256 {sha}")
        elif args.cmd == "relationer-sql":
            a, s, r = _laes(args.afstemning, root), _laes(args.fakta_svar, root), _laes(args.relationssvar, root)
            sql = relationer_sql(a, s, r)
            fv = forventet(a, s, r)
            sha = _skriv_tekst(_p(args.out, root), sql)
            print(f"RELATIONER_SQL_OK aegteskaber={len(fv['aegteskaber'])} "
                  f"bindinger={len(fv['relationsbindinger'])} sha256 {sha}")
        elif args.cmd == "parter-filtrer":
            keys = boern.load_keys(_p(args.noegler, root).read_text(encoding="utf-8"))
            m = _laes(args.manifest, root)
            f = parter_filtrer(m, keys)
            body = json.dumps(f, ensure_ascii=False, sort_keys=True).encode("utf-8")
            sha = _write(_p(args.out, root), body)
            print(f"PARTER_FILTRER_OK elementer={len(m['authorized_elements'])}->{len(f['authorized_elements'])} "
                  f"sha256 {sha}")
        elif args.cmd == "parter-logisk":
            lg = parter_logisk(_laes(args.manifest, root), _laes(args.input, root))
            sha = _skriv_json(_p(args.out, root), lg)
            print(f"PARTER_LOGISK_OK elementer={len(lg['elementer'])} elementer_sha256 {lg['elementer_sha256']} "
                  f"sha256 {sha}")
        elif args.cmd == "parter-sammenlign":
            want = _laes(args.forventet, root)
            have = parter_logisk(_laes(args.manifest, root), _laes(args.input, root))
            if want.get("contract") != PARTER_CONTRACT or want != have:
                wset = {_canon(e) for e in want.get("elementer", [])}
                hset = {_canon(e) for e in have["elementer"]}
                print(f"PARTER_AFVIGER mangler={len(wset - hset)} ekstra={len(hset - wset)}")
                return 1
            print(f"PARTER_OK elementer={len(have['elementer'])} elementer_sha256 {have['elementer_sha256']}")
        elif args.cmd in ("tilbagetraek-ark", "tilbagetraek-tjek"):
            a, s, r = _laes(args.afstemning, root), _laes(args.fakta_svar, root), _laes(args.relationssvar, root)
            if args.cmd == "tilbagetraek-ark":
                text = tilbagetraek_ark(a, s, r)
                sha = _skriv_tekst(_p(args.out, root), text)
                print(f"TILBAGETRAEK_ARK_OK linjer={len(_tilbage(a, s, r)[0])} sha256 {sha}")
            else:
                data = _p(args.ark, root).read_bytes()
                tv = parse_tilbagetraek(data.decode("utf-8"), a, s, r)
                c = Counter(x["svar"] for x in tv.values())
                print(f"TILBAGETRAEK_OK linjer={len(tv)} svar={json.dumps(dict(sorted(c.items())))} "
                      f"sha256 {_sha(data)}")
        elif args.cmd == "kvittering-sql":
            a, s, r = _laes(args.afstemning, root), _laes(args.fakta_svar, root), _laes(args.relationssvar, root)
            tv_bytes = _p(args.tilbagetraek, root).read_bytes()
            tv = parse_tilbagetraek(tv_bytes.decode("utf-8"), a, s, r)
            ctx = {"svar_sha256": _sha(_p(args.fakta_svar, root).read_bytes()),
                   "relationssvar_sha256": _sha(_p(args.relationssvar, root).read_bytes()),
                   "tilbagetraek_sha256": _sha(tv_bytes),
                   "oversat_ark_sha256": _sha(_p(args.oversat_ark, root).read_bytes())}
            sql = kvittering_sql(a, s, r, tv, kontekst=ctx)
            pre = preflight_sql(a, s, r)
            sha = _skriv_tekst(_p(args.out, root), sql)
            psha = _skriv_tekst(_p(args.preflight, root), pre)
            fv = forventet(a, s, r)
            gen = sum(1 for b in fv["bindinger"].values() if b["genbundet"])
            print(f"KVITTERING_SQL_OK noegler={len(fv['udfald'])} bindinger={len(fv['bindinger'])} genbundet={gen} "
                  f"tilbagetrukket={len(tv)} sha256 {sha} preflight_sha256 {psha}")
            print(f"  svar_sha256 {ctx['svar_sha256']}\n  oversat_ark_sha256 {ctx['oversat_ark_sha256']}")
    except (AfstemningError, ControlError, SheetError) as exc:
        print(str(exc).split(" — ")[0].split("\n")[0])
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
