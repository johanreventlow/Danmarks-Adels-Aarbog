#!/usr/bin/env python3
"""Kontrolværktøjet v2: kort pr. persona med B/D/V/P, stratificeret stikprøve, rettelse før binding.

Spec: `docs/superpowers/specs/2026-11-02-trin6c2-1939-bundet-til-bogen-design.md` §4.2, §4.4 pkt. 2, 3, 5, 7,
§4.5 og §4.6. Plan 2026-11-02 Task 7. v1 (`control_model.py`, 2018-20) er uændret; dens hjælpere genbruges.

En kørsel (fra repo-roden; GUC'en `daa.control_src` sat til kilden ved eksporten):
  1. `interpretation_control_classification.sql` og `interpretation_control_rows.sql` med kildescope.
  2. `plan --source-id <kilde>` trækker stikprøven (10 `MATCH` fra personas med identitetsudfaldet `svag` eller
     `ingen_kandidat` + 10 blandt resten, SEED `kontrolmodel-v2`; et stratum med for få fyldes fra det andet) og
     skriver `plan.json`, `rows-kontrol.json` (REAL_DIFF ∪ SKRIVEMAADE ∪ stikprøve) og `machine-candidates.json`
     (resten af `MATCH`) — hash-bundet, FØR et menneske ser et kort.
  3. Kortene (Task 8) giver arket v2: `F <interpretation_id> <ver> : B|D|V` pr. felt og
     `P <persona_id> <identity_version> : -|P|P <person_id>` pr. persona, grupperet pr. persona.
  4. `sql` oversætter arket. Et stikprøvefelt, der ikke er `B`, eller en stikprøvepersona med `P` er
     `SAMPLE_FAILED`: intet skrives (ingen SQL). Ellers én transaktion: `P`-identiteter → `unresolved` (værn:
     ingen promotion af nogen måltype, ønsket person findes og er ikke den nuværende) → rettelser
     (`red_ret_paastand`, grund `bogen_har_ret`) → afgørelser → re-klassifikation → stikprøvens og maskinens accept
     → binding med den scopede målfinding. `P`-personas' forslag får ingen afgørelse og bindes ikke.
  5. `verify-sql` (læse-kun, efter bindingen): de bundne = maskine ∪ stikprøve ∪ `B`-rettede; alle
     `P`-personas' forslag er `proposed` og ubundne. Planpartitionen (MATCH = maskine ∪ stikprøve ∪ udtaget pga.
     `P`) tjekkes, før SQL'en skrives.

SQL'en køres med `psql -v actor=<redaktørens uuid>` (rollen sættes som i v1). Den bærer `p_forventet` med
påstandens værdier og menneskets noter: den hører under `~/.private` (0600), som arket og rækkefilen. Værktøjet
printer kun antal, id'er og hashes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

import validate
from control_model import CLASSES, ControlError, _canonical_sha, _json_bytes, _lit, _sha_file, _write

SEED = "kontrolmodel-v2"
HUMAN_METHOD = "human-sheet-kontrol-v2"
MACHINE_METHOD = "machine-corroboration-v2"
DECISION_REF = "spec 2026-11-02 §4.4"
SCRIPTS = ".claude/skills/daa-extract/scripts"
CLASSIFICATION_SQL = f"{SCRIPTS}/interpretation_control_classification.sql"
TARGETS_SCOPED_SQL = f"{SCRIPTS}/interpretation_promotion_targets_scoped.sql"

CLASSES_V2 = CLASSES + ("ALREADY_BOUND_OTHER", "TARGET_SHARED")
#: Stratum 1: identiteten kom fra retning 2 uden generatorens bekræftelse (spec §4.4 pkt. 3, valg b).
UBEKRAEFTET = frozenset({"svag", "ingen_kandidat"})
STRATA = {"ubekraeftet": 10, "oevrige": 10}
SCOPE_FIELDS = ("persona_id", "identity_outcome", "identity_version", "navn_forkortes")
DATE_PREDICATES = frozenset({"person.birth", "person.death"})
PREDICATE_ORDER = ("person.name", "person.byname", "person.title", "person.birth", "person.death")
P_GRUND = "forkert person"
RESET = "SELECT set_config('app.change_set_id','',true) \\g /dev/null"

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
F_RE = re.compile(rf"^F (?P<id>{UUID}) (?P<ver>[1-9][0-9]*) : (?P<tok>[BDV_])\s*(?:#\s*(?P<note>.*))?$")
P_RE = re.compile(rf"^P (?P<id>{UUID}) (?P<ver>[1-9][0-9]*) : "
                  r"(?P<tok>-|_|P(?: (?P<person>-?[1-9][0-9]*))?)$")


@dataclass(frozen=True)
class FieldAnswer:
    interpretation_id: str
    version: int
    token: str            # B | D | V | _ (kun under en P-persona)
    note: str
    line: int
    persona_id: str | None   # blokkens persona (seneste P-linje)


@dataclass(frozen=True)
class PersonaAnswer:
    persona_id: str
    identity_version: int
    token: str            # - | P
    person_id: int | None
    line: int


def _sample_key_v2(interpretation_id: str) -> str:
    """Som v1's `_sample_key`, under v2's SEED (v1's funktion læser v1's modulkonstant)."""
    return hashlib.sha256(f"{SEED}:{interpretation_id}".encode("utf-8")).hexdigest()


def _hex64(*values: str) -> bool:
    return all(re.fullmatch(r"[0-9a-f]{64}", v or "") for v in values)


# --- planen ---------------------------------------------------------------------------------------------------------

def _validate_items(classification) -> list[dict]:
    items = classification.get("items") if isinstance(classification, dict) else None
    if not isinstance(items, list):
        raise ControlError("CLASSIFICATION_INVALID items")
    seen = set()
    for i in items:
        if (not isinstance(i, dict) or i.get("class") not in CLASSES_V2
                or not isinstance(i.get("interpretation_id"), str)
                or not isinstance(i.get("version"), int) or i["version"] < 1):
            raise ControlError("CLASSIFICATION_INVALID item")
        if i["interpretation_id"] in seen:
            raise ControlError("CLASSIFICATION_INVALID duplicate")
        seen.add(i["interpretation_id"])
        if i["class"] in ("MATCH", "MATCH_SINGLETON") and not isinstance(i.get("assertion_id"), int):
            raise ControlError("CLASSIFICATION_INVALID assertion_id")
    return items


def _validate_strata(strata) -> dict:
    if (not isinstance(strata, dict) or set(strata) != set(STRATA)
            or any(not isinstance(v, int) or isinstance(v, bool) or v < 0 for v in strata.values())):
        raise ControlError("STRATA_INVALID")
    return strata


def _record_key(r: dict) -> str:
    return r.get("record_key") or ""


def plan_run_v2(classification: dict, rows: list, *, source_id: int, strata: dict) -> dict:
    """Stikprøve, menneskets rækker og maskinkandidaterne. Ren funktion; ingen I/O."""
    if not isinstance(source_id, int) or isinstance(source_id, bool):
        raise ControlError("PLAN_SCOPE_MANGLER source_id")
    if not isinstance(rows, list) or any(not isinstance(r, dict) or not all(f in r for f in SCOPE_FIELDS)
                                         for r in rows):
        raise ControlError("PLAN_SCOPE_MANGLER rækkefilen er eksporteret uden daa.control_src")
    strata = _validate_strata(strata)
    items = _validate_items(classification)
    by_id = {r["interpretation_id"]: r for r in rows}

    def raekke(i: dict) -> dict:
        r = by_id.get(i["interpretation_id"])
        if r is None:
            raise ControlError("ROWS_MISSING")
        if r["version"] != i["version"]:
            raise ControlError("ROWS_VERSION_MISMATCH")
        if not isinstance(r["persona_id"], str) or not isinstance(r["identity_version"], int):
            raise ControlError("ROWS_PERSONA_MISSING")
        return r

    match = sorted((i for i in items if i["class"] == "MATCH"), key=lambda i: _sample_key_v2(i["interpretation_id"]))
    for i in match:
        raekke(i)
    lag = {"ubekraeftet": [i for i in match if by_id[i["interpretation_id"]]["identity_outcome"] in UBEKRAEFTET],
           "oevrige": [i for i in match if by_id[i["interpretation_id"]]["identity_outcome"] not in UBEKRAEFTET]}
    trukket = {s: lag[s][:strata[s]] for s in STRATA}
    # Et stratum med for få fyldes fra det andet; tallet rapporteres.
    opfyldt = 0
    for s, anden in (("ubekraeftet", "oevrige"), ("oevrige", "ubekraeftet")):
        mangler = strata[s] - len(trukket[s])
        if mangler > 0:
            ekstra = lag[anden][len(trukket[anden]):len(trukket[anden]) + mangler]
            trukket[anden] = trukket[anden] + ekstra
            opfyldt += len(ekstra)
    sample = trukket["ubekraeftet"] + trukket["oevrige"]
    sample_ids = {i["interpretation_id"] for i in sample}
    machine = [i for i in match if i["interpretation_id"] not in sample_ids]

    real_diff = [i for i in items if i["class"] == "REAL_DIFF"]
    skrivemaade = [i for i in items if i["class"] == "SKRIVEMAADE"]
    for i in real_diff + skrivemaade:
        raekke(i)
    ark = sample_ids | {i["interpretation_id"] for i in real_diff + skrivemaade}
    rows_kontrol = [r for r in rows if r["interpretation_id"] in ark]

    personas: dict[str, int] = {}
    for r in rows_kontrol:
        if personas.setdefault(r["persona_id"], r["identity_version"]) != r["identity_version"]:
            raise ControlError("ROWS_IDENTITY_VERSION_CONFLICT")

    counts: dict[str, int] = {c: 0 for c in CLASSES}
    for i in items:
        counts[i["class"]] = counts.get(i["class"], 0) + 1
    rapport = {s: {"maal": strata[s], "kandidater": len(lag[s]),
                   "trukket": sum(1 for i in sample if i in lag[s])} for s in STRATA}
    rapport["opfyldt_fra_andet"] = opfyldt
    return {
        "source_id": source_id,
        "sample_ids": sorted(sample_ids),
        "real_diff_ids": sorted(i["interpretation_id"] for i in real_diff),
        "skrivemaade_ids": sorted(i["interpretation_id"] for i in skrivemaade),
        "match": sorted(([i["interpretation_id"], i["version"], i["assertion_id"]] for i in match)),
        "rows_kontrol": rows_kontrol,
        "machine_candidates": sorted(({"interpretation_id": i["interpretation_id"], "version": i["version"],
                                       "predicate": i["predicate"], "assertion_id": i["assertion_id"],
                                       "persona_id": by_id[i["interpretation_id"]]["persona_id"]}
                                      for i in machine), key=lambda m: m["interpretation_id"]),
        "personas": [{"persona_id": p, "identity_version": v} for p, v in sorted(personas.items())],
        "persona_ids": sorted(personas),
        "universe_ids": sorted(i["interpretation_id"] for i in items),
        "strata": rapport,
        "counts": counts,
    }


# --- arket ------------------------------------------------------------------------------------------------------------

def sheet_order_v2(plan: dict) -> list[tuple[dict, list[dict]]]:
    """Arkets faste orden: personas efter (første postnøgle, persona-id), felter efter prædikat og id."""
    pr: dict[str, list[dict]] = {}
    for r in plan["rows_kontrol"]:
        pr.setdefault(r["persona_id"], []).append(r)
    versions = {p["persona_id"]: p["identity_version"] for p in plan["personas"]}

    def felt_noegle(r):
        p = r["predicate"]
        return (PREDICATE_ORDER.index(p) if p in PREDICATE_ORDER else len(PREDICATE_ORDER), p, r["interpretation_id"])

    blokke = []
    for p in sorted(pr, key=lambda p: (min(_record_key(r) for r in pr[p]), p)):
        blokke.append(({"persona_id": p, "identity_version": versions[p]}, sorted(pr[p], key=felt_noegle)))
    return blokke


def render_sheet_v2(plan: dict, personas: dict | None = None, fields: dict | None = None) -> str:
    """Tokenarket. Uden svar: det tomme ark (kun id'er; ingen værdier, klasser eller stikprøvemarkering).
    Med `personas` ({persona_id: '-'|'P'|'P <id>'}) og `fields` ({interpretation_id: (token, note)}) udfyldt af
    kortværktøjet (`persona_kort.py flet`); manglende svar står som `_`. Eneste sted arkets linjeformat bor."""
    personas, fields = personas or {}, fields or {}
    out = ["# KONTROL AF FORSLAG (v2)",
           "# Pr. felt efter kolonet: B = bogen bekræfter forslagets værdi, D = databasen har ret, V = ved ikke.",
           "# Pr. persona (skal besvares): - = rigtig person, P = forkert person, P <person-id> = forkert person,",
           "# rigtig er <id>.",
           "# P overtrumfer felterne (de må stå som _). En note må følge efter '#' på en F-linje.",
           ""]
    for persona, felter in sheet_order_v2(plan):
        out.append(f"P {persona['persona_id']} {persona['identity_version']} : "
                   f"{personas.get(persona['persona_id'], '_')}")
        for r in felter:
            tok, note = fields.get(r["interpretation_id"], ("_", ""))
            out.append(f"F {r['interpretation_id']} {r['version']} : {tok}" + (f" # {note}" if note else ""))
        out.append("")
    return "\n".join(out)


def parse_sheet_v2(text: str) -> tuple[list[FieldAnswer], list[PersonaAnswer]]:
    fields: list[FieldAnswer] = []
    personas: list[PersonaAnswer] = []
    seen_f, seen_p, undecided = set(), set(), []
    blok: PersonaAnswer | None = None
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("F "):
            m = F_RE.match(line)
            if not m:
                raise ControlError(f"SHEET_V2_LINE_INVALID line={n}")
            if m["id"] in seen_f:
                raise ControlError(f"SHEET_DUPLICATE line={n}")
            seen_f.add(m["id"])
            if m["tok"] == "_" and (blok is None or blok.token != "P"):
                undecided.append(n)
            fields.append(FieldAnswer(m["id"], int(m["ver"]), m["tok"], (m["note"] or "").strip(), n,
                                      blok.persona_id if blok else None))
        elif line.startswith("P "):
            m = P_RE.match(line)
            if not m:
                raise ControlError(f"SHEET_V2_LINE_INVALID line={n}")
            if m["id"] in seen_p:
                raise ControlError(f"SHEET_DUPLICATE line={n}")
            seen_p.add(m["id"])
            tok = m["tok"][0]
            if tok == "_":
                undecided.append(n)
            blok = PersonaAnswer(m["id"], int(m["ver"]), tok,
                                 int(m["person"]) if m["person"] else None, n)
            personas.append(blok)
        else:
            # Alt andet end kommentarer, tomme linjer, F og P er en fejl (også indrykning og v1's D-linjer).
            raise ControlError(f"SHEET_V2_LINE_INVALID line={n}")
    if undecided:
        raise ControlError("SHEET_V2_UNDECIDED lines=" + ",".join(map(str, undecided)))
    return fields, personas


def check_sheet_v2(plan: dict, fields: list[FieldAnswer], personas: list[PersonaAnswer]) -> None:
    """Arket dækker præcis planens felter og personas, i planens orden og gruppering."""
    want_f = {(r["interpretation_id"], r["version"]) for r in plan["rows_kontrol"]}
    have_f = {(f.interpretation_id, f.version) for f in fields}
    want_p = {(p["persona_id"], p["identity_version"]) for p in plan["personas"]}
    have_p = {(p.persona_id, p.identity_version) for p in personas}
    if want_f != have_f or want_p != have_p:
        raise ControlError(f"SHEET_IDENTITY_MISMATCH mangler={len(want_f - have_f) + len(want_p - have_p)} "
                           f"ekstra={len(have_f - want_f) + len(have_p - want_p)}")
    forventet = []
    for persona, felter in sheet_order_v2(plan):
        forventet.append(("P", persona["persona_id"], None))
        forventet += [("F", r["interpretation_id"], persona["persona_id"]) for r in felter]
    faktisk = sorted([(p.line, "P", p.persona_id, None) for p in personas]
                     + [(f.line, "F", f.interpretation_id, f.persona_id) for f in fields])
    for (line, *got), want in zip(faktisk, forventet):
        if tuple(got) != want:
            raise ControlError(f"SHEET_ORDER_MISMATCH line={line}")


# --- anvendelsen ------------------------------------------------------------------------------------------------------

def _p_dato(value_text: str) -> dict:
    info = validate.derive_date_info(value_text)
    return {"date_min": info["date_min"], "date_max": info["date_max"], "date_qualifier": info["qualifier"]}


def b_afvist_navn_eller_maal(r: dict) -> str | None:
    """Årsagen til, at `B` ikke kan gives på et ikke-stikprøvefelt (navn_forkortes ikke false — NULL tæller med —
    eller intet entydigt rettelsesmål); ellers None. Brugt af `apply_plan_v2` og af kortene."""
    if r["navn_forkortes"] is not False:
        return "navn_forkortes"
    maal = r.get("rettelse_maal")
    if not isinstance(maal, dict) or not isinstance(maal.get("assertion_id"), int):
        return "intet_maal"
    return None


def dato_uden_graenser(r: dict) -> bool:
    """Sand, hvis feltet er en dato, som parseren ikke kan afgrænse: en rettelse ville skrive NULL over grænserne."""
    if r["predicate"] not in DATE_PREDICATES:
        return False
    p = _p_dato(r["value_text"])
    return p["date_min"] is None and p["date_max"] is None


def b_afvisning(r: dict, klasse: str) -> str | None:
    """Hvorfor kortet ikke må tilbyde `B` på feltet (præcis de tilfælde, hvor `apply_plan_v2` afviser arket), ellers
    None. Et stikprøvefelt (klasse MATCH) kræver B og afvises aldrig."""
    if klasse == "MATCH":
        return None
    return b_afvist_navn_eller_maal(r) or ("dato_uden_graenser" if dato_uden_graenser(r) else None)


def apply_plan_v2(plan: dict, sheet_text: str, *, sheet_sha256: str, hashes: dict) -> dict:
    """Arket → {unresolved, rettelser, afgoerelser, maskine}. Fail-closed: én fejl, intet resultat."""
    if not _hex64(sheet_sha256):
        raise ControlError("PLAN_HASH_REQUIRED sheet_sha256")
    for felt in ("classification_sha256", "sample_sha256", "rows_kontrol_sha256"):
        if not _hex64(hashes.get(felt)):
            raise ControlError(f"PLAN_HASH_REQUIRED {felt}")
    fields, personas = parse_sheet_v2(sheet_text)
    check_sheet_v2(plan, fields, personas)

    p_set = {p.persona_id for p in personas if p.token == "P"}
    rows = {r["interpretation_id"]: r for r in plan["rows_kontrol"]}
    sample = set(plan["sample_ids"])
    klasse = {**{i: "REAL_DIFF" for i in plan["real_diff_ids"]},
              **{i: "SKRIVEMAADE" for i in plan["skrivemaade_ids"]}, **{i: "MATCH" for i in sample}}

    # Stikprøven: alt-eller-intet (spec §4.4 pkt. 3).
    felt_fejl = sum(1 for f in fields if f.interpretation_id in sample and f.token != "B")
    persona_fejl = len({rows[i]["persona_id"] for i in sample} & p_set)
    if felt_fejl or persona_fejl:
        raise ControlError(f"SAMPLE_FAILED felter={felt_fejl} personas={persona_fejl}")

    base = {"sheet_sha256": sheet_sha256, "rows_sha256": hashes["rows_kontrol_sha256"]}
    unresolved = []
    for p in personas:
        if p.token != "P":
            continue
        note = (f"ønsket_person_id={p.person_id}; grund={P_GRUND}" if p.person_id is not None
                else f"grund={P_GRUND}")
        unresolved.append({"persona_id": p.persona_id, "identity_version": p.identity_version,
                           "person_id": p.person_id, "note": note,
                           "context": {"basis": "human_sheet", **base, "line": p.line}, "line": p.line})

    rettelser, afgoerelser = [], []
    for f in fields:
        r = rows[f.interpretation_id]
        k = klasse[f.interpretation_id]
        if k != "MATCH" and f.token == "B":
            # Kortet tilbyder ikke B her; arket afvises, selv under en P-persona (spec §4.5 pkt. 2). Samme prædikat
            # (`b_afvisning`) som kortene og `flet` bruger: de tre afviser præcis de samme tilfælde.
            aarsag = b_afvisning(r, k)
            if aarsag == "navn_forkortes" or aarsag == "dato_uden_graenser":
                raise ControlError(f"SHEET_V2_LINE_INVALID line={f.line} {aarsag}")
            if aarsag:
                raise ControlError(f"SHEET_V2_LINE_INVALID line={f.line} intet entydigt mål")
        if r["persona_id"] in p_set:
            continue   # P overtrumfer: ingen afgørelse for nogen af personaens forslag
        ev = {"method": HUMAN_METHOD, "decision": DECISION_REF, **base, "line": f.line, "note": f.note}
        if k == "MATCH":
            afgoerelser.append({"interpretation_id": f.interpretation_id, "version": f.version, "klasse": k,
                                "status": "accepted", "evidence": {**ev, "stikproeve": True}})
            continue
        if f.token == "B":
            maal = r["rettelse_maal"]
            p_dato = _p_dato(r["value_text"]) if r["predicate"] in DATE_PREDICATES else None
            rettelser.append({"interpretation_id": f.interpretation_id, "version": f.version,
                              "assertion_id": maal["assertion_id"], "forventet": maal["forventet"],
                              "p_dato": p_dato, "graenser_foer": maal.get("graenser"), "line": f.line})
            afgoerelser.append({"interpretation_id": f.interpretation_id, "version": f.version, "klasse": k,
                                "status": "accepted",
                                "evidence": {**ev, "grund": "bogen_har_ret", "assertion_id": maal["assertion_id"]}})
        elif f.token == "D":
            afgoerelser.append({"interpretation_id": f.interpretation_id, "version": f.version, "klasse": k,
                                "status": "rejected", "evidence": {**ev, "grund": "database_har_ret"}})
        else:
            afgoerelser.append({"interpretation_id": f.interpretation_id, "version": f.version, "klasse": k,
                                "status": "unresolved", "evidence": {**ev, "grund": "ved_ikke"}})

    maskine = []
    for m in plan["machine_candidates"]:
        if m["persona_id"] in p_set:
            continue
        maskine.append({"interpretation_id": m["interpretation_id"], "version": m["version"],
                        "assertion_id": m["assertion_id"],
                        "evidence": {"method": MACHINE_METHOD, "decision": DECISION_REF,
                                     "classification_sha256": hashes["classification_sha256"],
                                     "sample_sha256": hashes["sample_sha256"], "sheet_sha256": sheet_sha256,
                                     "assertion_id": m["assertion_id"]}})
    return {"unresolved": unresolved, "rettelser": rettelser, "afgoerelser": afgoerelser, "maskine": maskine}


# --- SQL'en -----------------------------------------------------------------------------------------------------------

def datorettelser_graenser_aendret(applied: dict) -> int:
    """Datorettelser, hvis date_min/date_max/date_qualifier ændres (påstandens grænser ved planen mod p_dato).
    Ukendte grænser før tæller som ændret (fail-loud)."""
    return sum(1 for r in applied["rettelser"] if r["p_dato"] is not None and r.get("graenser_foer") != r["p_dato"])


def _jlit(obj) -> str:
    return _lit(json.dumps(obj, ensure_ascii=False, sort_keys=True))


def _uuid(s: str) -> str:
    if not re.fullmatch(UUID, s):
        raise ControlError("ID_INVALID")
    return f"'{s}'::uuid"


def _rettelse_map(applied: dict) -> str:
    """[[forslagets plan-id, rettelsens påstands-id], …] i id-orden."""
    return json.dumps(sorted([r["interpretation_id"], int(r["assertion_id"])] for r in applied["rettelser"]))


def _expected_bound(plan: dict, applied: dict) -> list[str]:
    stik = [a["interpretation_id"] for a in applied["afgoerelser"] if a["klasse"] == "MATCH"]
    return sorted(set(stik) | {m["interpretation_id"] for m in applied["maskine"]}
                  | {r["interpretation_id"] for r in applied["rettelser"]})


def _check_partition(plan: dict, applied: dict) -> None:
    """MATCH = maskine ∪ stikprøve ∪ udtaget pga. P, parvis disjunkte."""
    p_set = {u["persona_id"] for u in applied["unresolved"]}
    match = {m[0] for m in plan["match"]}
    maskine = {m["interpretation_id"] for m in applied["maskine"]}
    stik = set(plan["sample_ids"])
    udtaget = {m["interpretation_id"] for m in plan["machine_candidates"] if m["persona_id"] in p_set}
    stik_afgjort = {a["interpretation_id"] for a in applied["afgoerelser"] if a["klasse"] == "MATCH"}
    if (maskine | stik | udtaget != match or maskine & stik or maskine & udtaget or stik & udtaget
            or stik_afgjort != stik or len(maskine) != len(applied["maskine"])):
        raise ControlError(f"PLAN_PARTITION_MISMATCH match={len(match)} maskine={len(maskine)} "
                           f"stikprøve={len(stik)} udtaget={len(udtaget)}")


def sql_v2(plan: dict, applied: dict) -> str:
    """Den samlede ceremoni-SQL i én transaktion (READ COMMITTED, standard)."""
    _check_partition(plan, applied)
    src = plan["source_id"]
    if not isinstance(src, int) or isinstance(src, bool):
        raise ControlError("PLAN_SCOPE_MANGLER source_id")
    out = ["\\set ON_ERROR_STOP on", "BEGIN;",
           # Noter og forventede værdier citeres kun ved fordobling af '; backslash er bogstavelig.
           "SET LOCAL standard_conforming_strings=on;",
           f"SELECT set_config('daa.control_src', '{src}', true) \\g /dev/null",
           # Aktøren som i v1 (`machine_sql`): RPC'ernes rollegate læser request.jwt.claim.sub.
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) \\g /dev/null"]

    # (1) P-identiteter. Værnene læser private.* og kører som den forbundne rolle, før noget skrives.
    if applied["unresolved"]:
        out.append("-- (1) P: værn")
        for u in applied["unresolved"]:
            p = _uuid(u["persona_id"])
            chk = [f"DO $p$ BEGIN",
                   "IF EXISTS (SELECT 1 FROM private.interpretation_promotion pr "
                   "JOIN private.interpretation i ON i.id = pr.interpretation_id "
                   f"WHERE i.source_persona_id = {p} OR EXISTS (SELECT 1 FROM private.interpretation_party pt "
                   f"WHERE pt.interpretation_key = i.interpretation_key AND pt.source_persona_id = {p})) "
                   f"THEN RAISE EXCEPTION 'PERSONA_HAR_PROMOTIONER persona=%', {_lit(u['persona_id'])}; END IF;"]
            if u["person_id"] is not None:
                pers = int(u["person_id"])
                chk.append(f"IF NOT EXISTS (SELECT 1 FROM public.person WHERE id = {pers}) THEN RAISE EXCEPTION "
                           f"'SHEET_V2_LINE_INVALID line={u['line']} person={pers} findes ikke'; END IF;")
                chk.append("IF EXISTS (SELECT 1 FROM private.source_persona_identity spi "
                           f"WHERE spi.source_persona_id = {p} AND spi.decision_status = 'accepted' "
                           f"AND spi.canonical_person_id = {pers}) THEN RAISE EXCEPTION "
                           f"'SHEET_V2_LINE_INVALID line={u['line']} person={pers} er personaens nuværende'; END IF;")
            chk.append("END $p$;")
            out.append(" ".join(chk))
        out.append("SET LOCAL ROLE authenticated;")
        for u in applied["unresolved"]:
            out.append(RESET)
            out.append(f"SELECT public.red_afgoer_source_persona({_uuid(u['persona_id'])}, "
                       f"{int(u['identity_version'])}, 'unresolved', NULL, {_lit(u['note'])}, "
                       f"{_jlit(u['context'])}::jsonb) \\g /dev/null")
        out.append("RESET ROLE;")

    # (2) Rettelser og (3) afgørelser af REAL_DIFF/SKRIVEMAADE.
    menneske = [a for a in applied["afgoerelser"] if a["klasse"] != "MATCH"]
    if applied["rettelser"] or menneske:
        out.append("SET LOCAL ROLE authenticated;")
        if applied["rettelser"]:
            out.append("-- (2) rettelser (bogen_har_ret)")
        for r in applied["rettelser"]:
            dato = "NULL" if r["p_dato"] is None else f"{_jlit(r['p_dato'])}::jsonb"
            out.append(RESET)
            out.append(f"SELECT public.red_ret_paastand({int(r['assertion_id'])}, {_jlit(r['forventet'])}::jsonb, "
                       f"'bogen_har_ret', {_uuid(r['interpretation_id'])}, {dato}) \\g /dev/null")
        if menneske:
            out.append("-- (3) afgørelser")
        for a in menneske:
            out.append(RESET)
            out.append(f"SELECT public.red_decide_interpretation({_uuid(a['interpretation_id'])}, "
                       f"{int(a['version'])}, '{a['status']}', {_jlit(a['evidence'])}::jsonb) \\g /dev/null")
        out.append("RESET ROLE;")

    # (4) Re-klassifikation i transaktionen, efter rettelser og afgørelser: kun det, der NU er et MATCH med samme
    # version og samme mål, accepteres (en rettelse kan have ændret et maskinfelts påstand).
    stik = [a for a in applied["afgoerelser"] if a["klasse"] == "MATCH"]
    match_by_id = {m[0]: m for m in plan["match"]}
    accept = [match_by_id[a["interpretation_id"]] for a in stik] + [
        [m["interpretation_id"], m["version"], m["assertion_id"]] for m in applied["maskine"]]
    if accept:
        out += ["-- (4) re-klassifikation",
                "\\o /dev/null", f"\\i {CLASSIFICATION_SQL}", "\\o",
                "DO $m$ DECLARE r jsonb := current_setting('daa.control_result')::jsonb; "
                f"f jsonb := {_lit(json.dumps(sorted(accept)))}::jsonb; n int; BEGIN "
                "SELECT count(*) INTO n FROM jsonb_array_elements(f) m WHERE EXISTS ("
                "SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'interpretation_id' = m->>0 "
                "AND (i->>'version')::int = (m->>1)::int AND i->>'class' = 'MATCH' "
                "AND (i->>'assertion_id')::bigint = (m->>2)::bigint); "
                "IF n <> jsonb_array_length(f) THEN RAISE EXCEPTION 'MACHINE_NOT_MATCH % af %', "
                "jsonb_array_length(f) - n, jsonb_array_length(f); END IF; END $m$;",
                "SET LOCAL ROLE authenticated;"]
        for a in stik:
            out.append(RESET)
            out.append(f"SELECT public.red_decide_interpretation({_uuid(a['interpretation_id'])}, "
                       f"{int(a['version'])}, 'accepted', {_jlit(a['evidence'])}::jsonb) \\g /dev/null")
        for m in applied["maskine"]:
            out.append(RESET)
            out.append(f"SELECT public.red_decide_interpretation({_uuid(m['interpretation_id'])}, "
                       f"{int(m['version'])}, 'accepted', {_jlit(m['evidence'])}::jsonb) \\g /dev/null")
        out.append("RESET ROLE;")

    # (5) Binding: målfindingen afgrænset til de nu accepterede nøgler; præcis det forventede sæt.
    bound = _expected_bound(plan, applied)
    if bound:
        ids = ",".join(_uuid(i) for i in bound)
        out += ["-- (5) binding",
                "SELECT set_config('daa.transfer_scope', (SELECT jsonb_agg(interpretation_key::text ORDER BY "
                f"interpretation_key::text COLLATE \"C\") FROM private.interpretation WHERE id IN ({ids}))::text, "
                "true) \\g /dev/null",
                "\\o /dev/null", f"\\i {TARGETS_SCOPED_SQL}", "\\o",
                "DO $n$ DECLARE t jsonb := current_setting('daa.targets_scoped')::jsonb; faktisk jsonb; "
                f"forventet jsonb := {_lit(json.dumps(bound))}::jsonb; "
                f"r jsonb := {_lit(_rettelse_map(applied))}::jsonb; n int; BEGIN "
                "SELECT coalesce(jsonb_agg(ni.supersedes_id::text ORDER BY ni.supersedes_id), '[]') "
                "INTO faktisk FROM jsonb_array_elements(t->'items') x "
                "JOIN private.interpretation ni ON ni.id = (x->>'interpretation_id')::uuid; "
                "IF faktisk IS DISTINCT FROM forventet OR jsonb_array_length(t->'singleton_items') <> 0 THEN "
                "RAISE EXCEPTION 'CONTROL_V2_TARGETS_MISMATCH faktisk=% forventet=%', "
                "jsonb_array_length(faktisk), jsonb_array_length(forventet); END IF; "
                # Et rettet forslag bindes til netop den påstand, rettelsen skrev — ikke til en anden med samme værdi.
                "SELECT count(*) INTO n FROM jsonb_array_elements(t->'items') x "
                "JOIN private.interpretation ni ON ni.id = (x->>'interpretation_id')::uuid "
                "JOIN jsonb_array_elements(r) m ON m->>0 = ni.supersedes_id::text "
                "WHERE x->>'target_type' = 'assertion' AND (x->>'target_id')::bigint = (m->>1)::bigint; "
                "IF n <> jsonb_array_length(r) THEN RAISE EXCEPTION 'CONTROL_V2_RETTELSE_MAAL_MISMATCH % af %', "
                "n, jsonb_array_length(r); END IF; END $n$;",
                "SET LOCAL ROLE authenticated;",
                "DO $b$ DECLARE items jsonb := current_setting('daa.targets_scoped')::jsonb->'items'; p jsonb; BEGIN "
                "PERFORM set_config('app.change_set_id','',true); "
                "p := public.red_preview_interpretation_promotions(items); "
                "IF jsonb_array_length(p->'items') <> jsonb_array_length(items) OR EXISTS (SELECT 1 FROM "
                "jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE) "
                "THEN RAISE EXCEPTION 'CONTROL_V2_BIND_NOT_ELIGIBLE'; END IF; "
                "PERFORM set_config('app.change_set_id','',true); "
                "PERFORM public.red_promote_interpretations_batch(items, p->>'preview_hash'); END $b$;",
                "RESET ROLE;",
                "DO $c$ DECLARE n int; BEGIN SELECT count(DISTINCT q.interpretation_key) INTO n "
                "FROM private.interpretation_promotion pr JOIN private.interpretation q ON q.id = pr.interpretation_id "
                f"WHERE q.supersedes_id IN ({ids}) AND private.assertion_binding_current(pr.id); "
                f"IF n <> {len(bound)} THEN RAISE EXCEPTION 'CONTROL_V2_BIND_COUNT % af {len(bound)}', n; END IF; "
                "END $c$;"]
    # (6) Verifikationen i transaktionen (ejerrollen): en RAISE ruller hele ceremonien tilbage.
    out += ["-- (6) verifikation før COMMIT", _verify_do(plan, applied),
            "COMMIT;",
            f"\\echo 'CONTROL_V2_OK unresolved={len(applied['unresolved'])} rettelser={len(applied['rettelser'])} "
            f"afgoerelser={len(menneske)} stikproeve={len(stik)} maskine={len(applied['maskine'])} "
            f"bundet={len(bound)}'"]
    return "\n".join(out) + "\n"


def _verify_do(plan: dict, applied: dict) -> str:
    """Promotionssættet og P-personas som én DO-blok (ejerrollen: læser private.*). Bruges både i ceremonien før
    COMMIT (en RAISE ruller hele ceremonien tilbage) og i `verify-sql` efter COMMIT. Lister sammenlignes i uuid-orden
    (= Pythons sortering af kanoniske små-bogstavs-uuid'er), uafhængigt af databasens collation."""
    bound = _expected_bound(plan, applied)
    p_ids = sorted(u["persona_id"] for u in applied["unresolved"])
    for i in plan["universe_ids"] + p_ids:
        _uuid(i)
    return "\n".join([
        "DO $v$",
        f"DECLARE univ jsonb := {_lit(json.dumps(plan['universe_ids']))}::jsonb;",
        f"        forventet jsonb := {_lit(json.dumps(bound))}::jsonb;",
        f"        pp jsonb := {_lit(json.dumps(p_ids))}::jsonb;",
        "        faktisk jsonb; n int;",
        "BEGIN",
        # Promotionssættet: blandt planens forslag har præcis de forventede nøgler en gældende binding.
        "  SELECT coalesce(jsonb_agg(u.id ORDER BY u.id::uuid), '[]') INTO faktisk",
        "    FROM (SELECT x AS id FROM jsonb_array_elements_text(univ) x) u",
        "    JOIN private.interpretation i ON i.id = u.id::uuid",
        "   WHERE EXISTS (SELECT 1 FROM private.interpretation_promotion pr",
        "                   JOIN private.interpretation q ON q.id = pr.interpretation_id",
        "                  WHERE q.interpretation_key = i.interpretation_key",
        "                    AND private.assertion_binding_current(pr.id));",
        "  IF faktisk IS DISTINCT FROM forventet THEN",
        "    RAISE EXCEPTION 'CONTROL_V2_PROMOTION_MISMATCH faktisk=% forventet=%',",
        "      jsonb_array_length(faktisk), jsonb_array_length(forventet);",
        "  END IF;",
        # P-personas: identiteten er uafklaret, og ingen af deres forslag i planen er afgjort eller promoveret.
        "  SELECT count(*) INTO n FROM jsonb_array_elements_text(pp) p",
        "   WHERE NOT EXISTS (SELECT 1 FROM private.source_persona_identity spi",
        "                      WHERE spi.source_persona_id = p::uuid AND spi.decision_status = 'unresolved');",
        "  IF n <> 0 THEN RAISE EXCEPTION 'CONTROL_V2_P_PERSONA_IDENTITY %', n; END IF;",
        "  SELECT count(*) INTO n FROM jsonb_array_elements_text(univ) u",
        "    JOIN private.interpretation i ON i.id = u::uuid",
        "    JOIN private.interpretation_current ic ON ic.interpretation_key = i.interpretation_key",
        "   WHERE ic.source_persona_id::text IN (SELECT jsonb_array_elements_text(pp))",
        "     AND (ic.status <> 'proposed' OR EXISTS (SELECT 1 FROM private.interpretation_promotion pr",
        "            JOIN private.interpretation q ON q.id = pr.interpretation_id",
        "           WHERE q.interpretation_key = i.interpretation_key));",
        "  IF n <> 0 THEN RAISE EXCEPTION 'CONTROL_V2_P_PERSONA_DECIDED %', n; END IF;",
        "  RAISE NOTICE 'CONTROL_V2_VERIFY_OK bundet=% p_personas=%', jsonb_array_length(faktisk),",
        "    jsonb_array_length(pp);",
        "END $v$;",
    ])


def verify_sql_v2(plan: dict, applied: dict) -> str:
    """Læse-kun, uafhængig genkontrol EFTER ceremoniens COMMIT (samme DO-blok kørte også før COMMIT i ceremonien).
    Planpartitionen tjekkes her (Python); promotionssættet i SQL'en."""
    _check_partition(plan, applied)
    return "\n".join(["\\set ON_ERROR_STOP on", "BEGIN;", "SET TRANSACTION READ ONLY;",
                      _verify_do(plan, applied), "ROLLBACK;"]) + "\n"


# --- CLI --------------------------------------------------------------------------------------------------------------

def _load_plan(plan_dir: Path) -> tuple[dict, dict]:
    meta = json.loads((plan_dir / "plan.json").read_text(encoding="utf-8"))
    for navn, felt in (("rows-kontrol.json", "rows_kontrol_sha256"),
                       ("machine-candidates.json", "machine_candidates_sha256")):
        if _sha_file(plan_dir / navn) != meta[felt]:
            raise ControlError(f"PLAN_HASH_MISMATCH {navn}")
    plan = {k: meta[k] for k in ("source_id", "sample_ids", "real_diff_ids", "skrivemaade_ids", "match",
                                 "personas", "persona_ids", "universe_ids", "strata", "counts")}
    plan["rows_kontrol"] = json.loads((plan_dir / "rows-kontrol.json").read_text(encoding="utf-8"))
    plan["machine_candidates"] = json.loads((plan_dir / "machine-candidates.json").read_text(encoding="utf-8"))
    if _canonical_sha(plan["sample_ids"]) != meta["sample_sha256"]:
        raise ControlError("PLAN_HASH_MISMATCH sample")
    return plan, meta


def _applied_from_sheet(plan_dir: Path, sheet: Path, approved: str) -> tuple[dict, dict] | None:
    plan, meta = _load_plan(plan_dir)
    data = sheet.read_bytes()   # læses én gang: hash og parsing bruger samme bytes
    faktisk = hashlib.sha256(data).hexdigest()
    if faktisk != approved:
        print("SHEET_HASH_MISMATCH — arket er ikke det, der blev godkendt.")
        return None
    return plan, apply_plan_v2(plan, data.decode("utf-8"), sheet_sha256=faktisk, hashes=meta)


def main() -> int:
    os.umask(0o077)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--classification", required=True)
    p.add_argument("--rows", required=True)
    p.add_argument("--source-id", type=int)
    p.add_argument("--strata-ubekraeftet", type=int, default=STRATA["ubekraeftet"])
    p.add_argument("--strata-oevrige", type=int, default=STRATA["oevrige"])
    p.add_argument("--out-dir", required=True)
    a = sub.add_parser("ark")
    a.add_argument("--plan-dir", required=True)
    a.add_argument("--out", required=True)
    for navn in ("sql", "verify-sql"):
        s = sub.add_parser(navn)
        s.add_argument("--plan-dir", required=True)
        s.add_argument("--sheet", required=True)
        s.add_argument("--approved-sha256", required=True)
        s.add_argument("--out", required=True)
    args = ap.parse_args()

    try:
        if args.cmd == "plan":
            if args.source_id is None:
                raise ControlError("PLAN_SCOPE_MANGLER --source-id")
            k_path, r_path = Path(args.classification), Path(args.rows)
            plan = plan_run_v2(json.loads(k_path.read_text(encoding="utf-8")),
                               json.loads(r_path.read_text(encoding="utf-8")), source_id=args.source_id,
                               strata={"ubekraeftet": args.strata_ubekraeftet, "oevrige": args.strata_oevrige})
            ud = Path(args.out_dir)
            meta = {"seed": SEED, "decision": DECISION_REF, "source_id": plan["source_id"],
                    "classification_sha256": _sha_file(k_path), "rows_sha256": _sha_file(r_path),
                    "sample_ids": plan["sample_ids"], "sample_sha256": _canonical_sha(plan["sample_ids"]),
                    "real_diff_ids": plan["real_diff_ids"], "skrivemaade_ids": plan["skrivemaade_ids"],
                    "match": plan["match"], "personas": plan["personas"], "persona_ids": plan["persona_ids"],
                    "universe_ids": plan["universe_ids"], "strata": plan["strata"], "counts": plan["counts"],
                    "rows_kontrol_sha256": _write(ud / "rows-kontrol.json", _json_bytes(plan["rows_kontrol"])),
                    "machine_candidates_sha256": _write(ud / "machine-candidates.json",
                                                        _json_bytes(plan["machine_candidates"]))}
            _write(ud / "plan.json", _json_bytes(meta))
            print(f"PLAN_V2_OK kilde={plan['source_id']} klasser={json.dumps(plan['counts'], sort_keys=True)} "
                  f"stikprøve={len(plan['sample_ids'])} strata={json.dumps(plan['strata'], sort_keys=True)} "
                  f"real_diff={len(plan['real_diff_ids'])} skrivemaade={len(plan['skrivemaade_ids'])} "
                  f"maskinkandidater={len(plan['machine_candidates'])} ark_felter={len(plan['rows_kontrol'])} "
                  f"personas={len(plan['personas'])}")
            print(f"  sample_sha256 {meta['sample_sha256']}")
            print(f"  rows_kontrol_sha256 {meta['rows_kontrol_sha256']}")
            return 0

        if args.cmd == "ark":
            plan, _ = _load_plan(Path(args.plan_dir))
            sha = _write(Path(args.out), render_sheet_v2(plan).encode("utf-8"))
            print(f"ARK_V2_OK felter={len(plan['rows_kontrol'])} personas={len(plan['personas'])} sha256 {sha}")
            return 0

        res = _applied_from_sheet(Path(args.plan_dir), Path(args.sheet), args.approved_sha256)
        if res is None:
            return 1
        plan, applied = res
        if args.cmd == "verify-sql":
            sql = verify_sql_v2(plan, applied)
            _write(Path(args.out), sql.encode("utf-8"))
            print(f"VERIFY_SQL_V2_OK bundet={len(_expected_bound(plan, applied))} "
                  f"p_personas={len(applied['unresolved'])}")
            return 0
        sql = sql_v2(plan, applied)
        _write(Path(args.out), sql.encode("utf-8"))
        tal = {s: sum(1 for x in applied["afgoerelser"] if x["klasse"] != "MATCH" and x["status"] == s)
               for s in ("accepted", "rejected", "unresolved")}
        graenser_aendret = datorettelser_graenser_aendret(applied)
        print(f"SQL_V2_OK unresolved={len(applied['unresolved'])} rettelser={len(applied['rettelser'])} "
              f"datorettelser_graenser_aendret={graenser_aendret} afgoerelser={json.dumps(tal, sort_keys=True)} "
              f"stikprøve={len(plan['sample_ids'])} maskine={len(applied['maskine'])} "
              f"bundet={len(_expected_bound(plan, applied))}")
        return 0
    except ControlError as exc:
        print(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
