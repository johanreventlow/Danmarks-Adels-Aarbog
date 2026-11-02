#!/usr/bin/env python3
"""Kortværktøj pr. persona til kontrolværktøjet v2 (trin 6c-2 Task 8; spec §4.4 pkt. 6-8).

Generaliseret fra 6c-1 C's identitetskort (`~/.private/5ab-overfoersel/c-kort/kort.py`): ét kort pr. persona med navn,
titel, fødsel og død samlet, posttekst, side og familie. Rigtige ark og svar bliver i `~/.private`; her er kun koden.

  kontekst-ids --plan-dir D                              -> komma-listen af persona-id'er til `persona_kort_kontekst.sql`
  html  --plan-dir D --kontekst K.json --out-dir O       -> kort-1.html, kort-2.html, ... (højst 30 personas pr. side)
  flet  --plan-dir D --svar S.json [S2.json ...] --out ark.txt
                                                         -> tokenark v2 (`control_model_v2.parse_sheet_v2`-gyldigt)

Kortet viser aldrig forslagets afgørelsesklasse eller hvilke felter, der indgår i kontrollens udtræk. Svarfelter er
REAL_DIFF, rest-SKRIVEMAADE og udtrukne felter, alle bygget ens; personaens øvrige MATCH-felter er læse-kun kontekst.
`B` tilbydes ikke, hvor `control_model_v2.apply_plan_v2` ville afvise det (samme prædikater: `b_afvisning`).
Arkets linjeformat bor kun i `control_model_v2.render_sheet_v2`/`parse_sheet_v2`; `flet` kalder dem.
Værktøjet printer kun antal, id'er og hashes (aldrig værdier, navne eller posttekst); filer skrives 0600.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path

import control_model_v2 as v2
from control_model import ControlError

MAX_PERSONAS = 30
PERSONA_TOKEN = re.compile(r"^(-|P|P -?[1-9][0-9]*)$")
FELT_TOKEN = re.compile(r"^[BDV]$")
VISNING = {"person.name": ("fuldt_navn", "navn"), "person.byname": ("navn",), "person.title": ("titel",),
           "person.birth": ("foedt",), "person.death": ("doed",)}
B_TEKST = {
    "navn_forkortes": "Forslaget forkorter et navn, som databasen allerede har. B tilbydes ikke; vælg D eller V.",
    "intet_maal": "Der er ikke præcis én påstand i databasen at rette. B tilbydes ikke; vælg D eller V.",
    "dato_uden_graenser": "Datoen kan ikke afgrænses til år og dag. B tilbydes ikke; vælg D eller V.",
}


def _sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def _felt_noegle(f: dict):
    p = f["predicate"]
    order = v2.PREDICATE_ORDER
    return (order.index(p) if p in order else len(order), p, f["interpretation_id"])


def vindue(placering: list) -> dict | None:
    """Syr bogteksten omkring posten sammen af renditionens stykker; huller vises som ' […] '."""
    if not placering:
        return None
    fra, til = min(o["fra"] for o in placering), max(o["til"] for o in placering)
    tegn: dict[int, str] = {}
    for o in placering:
        for s in o.get("stykker") or []:
            for j, ch in enumerate(s["t"]):
                tegn.setdefault(s["f"] + j, ch)

    def udsnit(a: int, b: int) -> str:
        out, hul = [], False
        for pos in range(a, b):
            ch = tegn.get(pos)
            if ch is None:
                if not hul and out:
                    out.append(" […] ")
                hul = True
            else:
                out.append(ch)
                hul = False
        return "".join(out).strip()

    return {"foer": udsnit(fra - 2000, fra), "post": udsnit(fra, til), "efter": udsnit(til, til + 800)}


def _db_vaerdi(r: dict, person: dict) -> str | None:
    maal = r.get("rettelse_maal")
    if isinstance(maal, dict) and isinstance(maal.get("forventet"), dict):
        f = maal["forventet"]
        if f.get("vaerdi_tekst") or f.get("date_raw"):
            return f.get("vaerdi_tekst") or f.get("date_raw")
    for nogle in VISNING.get(r["predicate"], ()):
        if person.get(nogle):
            return person[nogle]
    return None


def build_cards(plan: dict, kontekst: dict) -> list[dict]:
    """Kortene i arkets orden. Alle svarfelter har præcis de samme nøgler."""
    kt = (kontekst or {}).get("personas") or {}
    sample = set(plan["sample_ids"])
    maskine: dict[str, list[dict]] = {}
    for m in plan["machine_candidates"]:
        maskine.setdefault(m["persona_id"], []).append(m)
    kort = []
    for nr, (persona, felter) in enumerate(v2.sheet_order_v2(plan), 1):
        k = kt.get(persona["persona_id"]) or {}
        person = k.get("person") or {}
        forslag = {f["interpretation_id"]: f for f in k.get("forslag") or []}
        svar = []
        for r in felter:
            klasse = "MATCH" if r["interpretation_id"] in sample else "ANDET"
            aarsag = v2.b_afvisning(r, klasse)
            svar.append({"interpretation_id": r["interpretation_id"], "version": r["version"],
                         "predicate": r["predicate"], "vaerdi": r["value_text"],
                         "db_vaerdi": _db_vaerdi(r, person), "b": aarsag is None,
                         "b_aarsag": B_TEKST[aarsag] if aarsag else None})
        kontekst_felter = sorted(
            ({"interpretation_id": m["interpretation_id"], "predicate": m["predicate"],
              "vaerdi": (forslag.get(m["interpretation_id"]) or {}).get("value_text")}
             for m in maskine.get(persona["persona_id"], [])), key=_felt_noegle)
        pl = (k.get("post") or {}).get("placering") or []
        post = {"record_key": (k.get("post") or {}).get("record_key"),
                "sider": sorted({(o["side_fra"], o["side_til"]) for o in pl}), "vindue": vindue(pl)}
        kort.append({"nr": nr, "persona_id": persona["persona_id"], "identity_version": persona["identity_version"],
                     "identitet": k.get("identitet"), "person": person, "post": post,
                     "svar_felter": svar, "kontekst_felter": kontekst_felter})
    return kort


def chunk_cards(kort: list[dict], max_personas: int = MAX_PERSONAS) -> list[list[dict]]:
    if not 1 <= max_personas <= MAX_PERSONAS:
        raise ControlError(f"KORT_FOR_MANGE_PR_ARK max={MAX_PERSONAS}")
    return [kort[i:i + max_personas] for i in range(0, len(kort), max_personas)]


def render_pages(plan: dict, kontekst: dict, plan_sha256: str, max_personas: int = MAX_PERSONAS) -> list[str]:
    tpl = (Path(__file__).with_name("persona_kort.html")).read_text(encoding="utf-8")
    dele = chunk_cards(build_cards(plan, kontekst), max_personas)
    sider = []
    for i, kort in enumerate(dele, 1):
        data = {"plan_sha256": plan_sha256, "side": i, "sider": len(dele), "kort": kort}
        js = json.dumps(data, ensure_ascii=False).replace("</", "<\\/").replace(" ", "\\u2028") \
            .replace(" ", "\\u2029")
        sider.append(tpl.replace("/*__DATA__*/null", js))
    return sider


def _note(s) -> str:
    s = "".join(ch if ch.isprintable() else " " for ch in str(s or ""))
    return " ".join(s.split())[:300]


def flet_sheet(plan: dict, plan_sha256: str, svarfiler: list[dict]) -> str:
    """Svarfil(er) → tokenark v2. Fail-closed: den første fejl afviser det hele; fejl bærer kun kode og tal."""
    personas: dict[str, str] = {}
    felter: dict[str, tuple[str, str]] = {}
    for s in svarfiler:
        if not isinstance(s, dict) or s.get("plan_sha256") != plan_sha256:
            raise ControlError("KORT_SVAR_ANDEN_PLAN")
        sv = s.get("svar") or {}
        for pid_, tok in (sv.get("personas") or {}).items():
            if personas.setdefault(pid_, tok) != tok:
                raise ControlError("KORT_SVAR_DUBLET persona")
        for iid, a in (sv.get("felter") or {}).items():
            ny = (str((a or {}).get("tok", "")), _note((a or {}).get("note")))
            if felter.setdefault(iid, ny) != ny:
                raise ControlError("KORT_SVAR_DUBLET felt")
    rows = {r["interpretation_id"]: r for r in plan["rows_kontrol"]}
    sample = set(plan["sample_ids"])
    plan_personas = {p["persona_id"] for p in plan["personas"]}
    ukendt = (set(personas) - plan_personas) | (set(felter) - set(rows))
    if ukendt:
        raise ControlError(f"KORT_SVAR_UKENDT antal={len(ukendt)}")
    mangler_p = plan_personas - set(personas)
    if mangler_p:
        raise ControlError(f"KORT_UBESVARET personas={len(mangler_p)}")
    for tok in personas.values():
        if not isinstance(tok, str) or not PERSONA_TOKEN.match(tok):
            raise ControlError("KORT_PERSONA_TOKEN")
    for iid, (tok, _) in felter.items():
        if tok != "_" and not FELT_TOKEN.match(tok):
            raise ControlError("KORT_FELT_TOKEN")
        if tok == "B" and v2.b_afvisning(rows[iid], "MATCH" if iid in sample else "ANDET"):
            raise ControlError("KORT_B_IKKE_TILBUDT")
    fuldt = {i: t for i, t in felter.items() if t[0] != "_"}
    p_set = {p for p, t in personas.items() if t.startswith("P")}
    mangler_f = [i for i, r in rows.items() if i not in fuldt and r["persona_id"] not in p_set]
    if mangler_f:
        raise ControlError(f"KORT_UBESVARET felter={len(mangler_f)}")
    tekst = v2.render_sheet_v2(plan, personas, fuldt)
    f, p = v2.parse_sheet_v2(tekst)      # arket skal kunne læses af kontrolværktøjet
    v2.check_sheet_v2(plan, f, p)
    return tekst


def _plan_dir(d: Path) -> tuple[dict, str]:
    plan, _ = v2._load_plan(d)           # hash-tjekker rækkefilerne mod plan.json
    return plan, _sha((d / "plan.json").read_bytes())


def main() -> int:
    os.umask(0o077)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    k = sub.add_parser("kontekst-ids")
    k.add_argument("--plan-dir", required=True)
    h = sub.add_parser("html")
    h.add_argument("--plan-dir", required=True)
    h.add_argument("--kontekst", required=True)
    h.add_argument("--out-dir", required=True)
    h.add_argument("--max-personas", type=int, default=MAX_PERSONAS)
    f = sub.add_parser("flet")
    f.add_argument("--plan-dir", required=True)
    f.add_argument("--svar", required=True, nargs="+")
    f.add_argument("--out", required=True)
    a = ap.parse_args()
    try:
        plan, sha = _plan_dir(Path(a.plan_dir))
        if a.cmd == "kontekst-ids":
            print(",".join(plan["persona_ids"]))
            return 0
        if a.cmd == "html":
            kt = json.loads(Path(a.kontekst).read_text(encoding="utf-8"))
            sider = render_pages(plan, kt, sha, a.max_personas)
            ud = Path(a.out_dir)
            for i, s in enumerate(sider, 1):
                print(f"KORT_HTML_SIDE {i}/{len(sider)} sha256={v2._write(ud / f'kort-{i}.html', s.encode('utf-8'))}")
            print(f"KORT_HTML_OK sider={len(sider)} personas={len(plan['personas'])} felter={len(plan['rows_kontrol'])} "
                  f"plan_sha256={sha}")
            return 0
        sv = [json.loads(Path(p).read_text(encoding="utf-8")) for p in a.svar]
        tekst = flet_sheet(plan, sha, sv)
        ark_sha = v2._write(Path(a.out), tekst.encode("utf-8"))
        fields, personas = v2.parse_sheet_v2(tekst)
        n_p = sum(1 for p in personas if p.token == "P")
        print(f"KORT_FLET_OK personas={len(personas)} P={n_p} felter={len(fields)} ark_sha256={ark_sha}")
        return 0
    except ControlError as exc:
        print(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
