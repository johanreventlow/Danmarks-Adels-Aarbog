"""Tests til persona_kort.py (trin 6c-2 Task 8): kort pr. persona, svarfil → ark v2. Kun syntetiske fixtures."""
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

import pytest

import control_model_v2 as v2
import persona_kort as pk
from control_model import ControlError

HERE = Path(__file__).parent
SCRIPT = str(HERE / "persona_kort.py")
SQL = HERE / "persona_kort_kontekst.sql"
FIX = HERE / "fixtures" / "persona-kort-syntetisk"
SRC = 3
#: Det flettede ark for fixturens svarfil. Hardkodet: ændres arkformatet eller fixturen, skal tallet ændres bevidst.
ARK_SHA256 = "e91dc4c00214d97364a37552823b1ba5ae81ef4f54cb815530d04e9a004d9362"
NAVNE = ("Testrup", "Prøvegaard", "Eksempel", "Fiktivsen", "Opdigtet", "Syntetica")


def _json(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))


@pytest.fixture()
def planmappe(tmp_path):
    ud = tmp_path / "plan"
    classification = _json(FIX / "classification.json")
    rows = _json(FIX / "rows.json")
    plan = v2.plan_run_v2(classification, rows, source_id=SRC, strata={"ubekraeftet": 1, "oevrige": 1})
    meta = {k: plan[k] for k in ("source_id", "sample_ids", "real_diff_ids", "skrivemaade_ids", "match", "personas",
                                 "persona_ids", "universe_ids", "strata", "counts")}
    meta["sample_sha256"] = v2._canonical_sha(plan["sample_ids"])
    meta["rows_kontrol_sha256"] = v2._write(ud / "rows-kontrol.json", v2._json_bytes(plan["rows_kontrol"]))
    meta["machine_candidates_sha256"] = v2._write(ud / "machine-candidates.json",
                                                  v2._json_bytes(plan["machine_candidates"]))
    v2._write(ud / "plan.json", v2._json_bytes(meta))
    return ud


def _svar(plan_sha: str, **over) -> dict:
    s = _json(FIX / "svar.json")
    s["plan_sha256"] = plan_sha
    for k, v in over.items():
        s["svar"][k].update(v)
    return s


def _plan_sha(ud: Path) -> str:
    return hashlib.sha256((ud / "plan.json").read_bytes()).hexdigest()


# --- kortene ----------------------------------------------------------------------------------------------------

def test_html_viser_hverken_klasse_eller_stikproeve(planmappe, tmp_path):
    plan, _ = v2._load_plan(planmappe)
    sider = pk.render_pages(plan, _json(FIX / "kontekst.json"), _plan_sha(planmappe))
    assert sider
    for html in sider:
        lav = html.lower()
        for ord_ in ("sample", "stikpr", "maskin", "machine", "klasse"):
            assert ord_ not in lav, ord_
        for klasse in v2.CLASSES_V2:
            assert klasse not in html, klasse
        for sid in plan["sample_ids"]:
            assert sid in html        # id'erne er der (de er svarfelter), men uden mærkning
    # Svarfelterne er ens opbygget, uanset om de er stikprøve, REAL_DIFF eller SKRIVEMAADE.
    kort = pk.build_cards(plan, _json(FIX / "kontekst.json"))
    noegler = {tuple(sorted(f)) for k in kort for f in k["svar_felter"]}
    assert len(noegler) == 1
    assert {f["interpretation_id"] for k in kort for f in k["svar_felter"]} == \
        {r["interpretation_id"] for r in plan["rows_kontrol"]}


def test_felter_grupperet_pr_persona_i_planens_orden(planmappe):
    plan, _ = v2._load_plan(planmappe)
    kort = pk.build_cards(plan, _json(FIX / "kontekst.json"))
    forventet = [(p["persona_id"], [r["interpretation_id"] for r in felter])
                 for p, felter in v2.sheet_order_v2(plan)]
    assert [(k["persona_id"], [f["interpretation_id"] for f in k["svar_felter"]]) for k in kort] == forventet


def test_hoejst_30_personas_pr_ark(tmp_path):
    n = 65
    items, rows = [], []
    for i in range(1, n + 1):
        items.append({"interpretation_id": f"00000000-0000-4000-8000-{i:012d}", "version": 1,
                      "predicate": "person.title", "class": "REAL_DIFF", "assertion_id": None})
        rows.append({"interpretation_id": items[-1]["interpretation_id"], "version": 1, "record_key": f"I-{i:04d}",
                     "predicate": "person.title", "value_text": "titel", "confidence": 1, "persona_role": "principal",
                     "cited": [], "persona_id": f"11111111-0000-4000-8000-{i:012d}", "identity_outcome": "enig",
                     "identity_version": 1, "navn_forkortes": False, "rettelse_maal": None})
    plan = v2.plan_run_v2({"items": items, "counts": {}}, rows, source_id=SRC, strata={"ubekraeftet": 0, "oevrige": 0})
    kt = {"personas": {}}
    sider = pk.render_pages(plan, kt, "a" * 64)
    assert [len(re.findall(r'"persona_id"', s)) for s in sider] == [30, 30, 5]
    assert all(len(c) <= 30 for c in pk.chunk_cards(pk.build_cards(plan, kt)))
    with pytest.raises(ControlError):
        pk.render_pages(plan, kt, "a" * 64, max_personas=31)


def test_match_uden_svar_er_laese_kun_kontekst(planmappe):
    plan, _ = v2._load_plan(planmappe)
    kort = pk.build_cards(plan, _json(FIX / "kontekst.json"))
    svar_ids = {f["interpretation_id"] for k in kort for f in k["svar_felter"]}
    kontekst_ids = {f["interpretation_id"] for k in kort for f in k["kontekst_felter"]}
    maskine = {m["interpretation_id"] for m in plan["machine_candidates"]
               if m["persona_id"] in {k["persona_id"] for k in kort}}
    assert kontekst_ids == maskine and kontekst_ids and not (kontekst_ids & svar_ids)
    assert all("tok" not in f for k in kort for f in k["kontekst_felter"])


def test_b_tilbydes_kun_hvor_apply_plan_v2_accepterer_den(planmappe):
    plan, meta = v2._load_plan(planmappe)
    kort = pk.build_cards(plan, _json(FIX / "kontekst.json"))
    felter = [f for k in kort for f in k["svar_felter"]]
    assert any(not f["b"] for f in felter) and any(f["b"] for f in felter)
    hashes = {"classification_sha256": "c" * 64, "sample_sha256": "d" * 64, "rows_kontrol_sha256": "e" * 64}
    arsag = {}
    for f in felter:
        if f["interpretation_id"] in plan["sample_ids"]:
            assert f["b"]            # stikprøvefelter skal kunne få B
            continue
        # Samme afgørelse som apply_plan_v2: B på kun dette felt (alle andre D) afvises, netop når kortet skjuler B.
        svar = {r["interpretation_id"]: ("B" if r["interpretation_id"] == f["interpretation_id"]
                                         else ("B" if r["interpretation_id"] in plan["sample_ids"] else "D"))
                for r in plan["rows_kontrol"]}
        tekst = v2.render_sheet_v2(plan, {p["persona_id"]: "-" for p in plan["personas"]},
                                   {i: (t, "") for i, t in svar.items()})
        try:
            v2.apply_plan_v2(plan, tekst, sheet_sha256="a" * 64, hashes=hashes)
            afvist = False
        except ControlError as e:
            afvist = "SHEET_V2_LINE_INVALID" in str(e)
        assert afvist == (not f["b"]), f["interpretation_id"]
        if not f["b"]:
            arsag[f["interpretation_id"]] = f["b_aarsag"]
    # navn_forkortes sand, dato uden grænser, intet entydigt mål: tre forskellige forklaringer.
    assert len(set(arsag.values())) == 3 and all(arsag.values())
    # NULL tæller som »ikke false«.
    r = dict(plan["rows_kontrol"][0], navn_forkortes=None, predicate="person.name")
    assert v2.b_afvisning(r, "REAL_DIFF") == "navn_forkortes"


def test_persona_svar_starter_ubesluttet_og_kraeves(planmappe):
    plan, _ = v2._load_plan(planmappe)
    for html in pk.render_pages(plan, _json(FIX / "kontekst.json"), _plan_sha(planmappe)):
        # Ingen forudfyldte personsvar i siden; kun brugerens egne valg (localStorage) udfylder dem.
        assert 'let svar = { personas: {}, felter: {} }' in html
    s = _svar(_plan_sha(planmappe))
    del s["svar"]["personas"]["11111111-0000-4000-8000-000000000004"]
    with pytest.raises(ControlError, match="KORT_UBESVARET"):
        pk.flet_sheet(plan, _plan_sha(planmappe), [s])
    s = _svar(_plan_sha(planmappe))
    s["svar"]["personas"]["11111111-0000-4000-8000-000000000004"] = "_"
    with pytest.raises(ControlError, match="KORT_PERSONA_TOKEN"):
        pk.flet_sheet(plan, _plan_sha(planmappe), [s])


# --- flet -------------------------------------------------------------------------------------------------------

def test_round_trip_svarfil_til_ark_v2_og_parse(planmappe):
    plan, _ = v2._load_plan(planmappe)
    sha = _plan_sha(planmappe)
    tekst = pk.flet_sheet(plan, sha, [_svar(sha)])
    assert hashlib.sha256(tekst.encode("utf-8")).hexdigest() == ARK_SHA256
    fields, personas = v2.parse_sheet_v2(tekst)
    v2.check_sheet_v2(plan, fields, personas)
    assert {f.interpretation_id: f.token for f in fields}["00000000-0000-4000-8000-000000000011"] == "V"
    assert [(p.token, p.person_id) for p in personas][1] == ("P", 4999)
    # P-personaens ubesvarede felter står som _ og er tilladt.
    assert {f.interpretation_id: f.token for f in fields}["00000000-0000-4000-8000-000000000005"] == "_"
    # Samme overskrift som det tomme ark (formatet bor kun i control_model_v2).
    assert tekst.split("\n\n")[0] == v2.render_sheet_v2(plan).split("\n\n")[0]


def test_flet_splitter_over_flere_svarfiler(planmappe):
    plan, _ = v2._load_plan(planmappe)
    sha = _plan_sha(planmappe)
    helt = _svar(sha)
    pers = sorted(helt["svar"]["personas"])
    a = {"plan_sha256": sha, "svar": {"personas": {p: helt["svar"]["personas"][p] for p in pers[:2]}, "felter": {}}}
    b = {"plan_sha256": sha, "svar": {"personas": {p: helt["svar"]["personas"][p] for p in pers[2:]},
                                      "felter": helt["svar"]["felter"]}}
    assert pk.flet_sheet(plan, sha, [a, b]) == pk.flet_sheet(plan, sha, [helt])


@pytest.mark.parametrize("aendring,kode", [
    ({"felter": {"00000000-0000-4000-8000-000000000005": {"tok": "B", "note": ""}}}, "KORT_B_IKKE_TILBUDT"),
    ({"felter": {"00000000-0000-4000-8000-000000000009": {"tok": "B", "note": ""}}}, "KORT_B_IKKE_TILBUDT"),
    ({"felter": {"00000000-0000-4000-8000-000000000011": {"tok": "B", "note": ""}}}, "KORT_B_IKKE_TILBUDT"),
    ({"felter": {"00000000-0000-4000-8000-000000000004": {"tok": "X", "note": ""}}}, "KORT_FELT_TOKEN"),
    ({"felter": {"00000000-0000-4000-8000-000000000999": {"tok": "D", "note": ""}}}, "KORT_SVAR_UKENDT"),
    ({"personas": {"11111111-0000-4000-8000-000000000001": "P x"}}, "KORT_PERSONA_TOKEN"),
])
def test_flet_afviser_ugyldige_svar(planmappe, aendring, kode):
    plan, _ = v2._load_plan(planmappe)
    sha = _plan_sha(planmappe)
    with pytest.raises(ControlError, match=kode):
        pk.flet_sheet(plan, sha, [_svar(sha, **aendring)])


def test_flet_kraever_samme_plan_og_ubesvarede_felter_uden_P(planmappe):
    plan, _ = v2._load_plan(planmappe)
    sha = _plan_sha(planmappe)
    with pytest.raises(ControlError, match="KORT_SVAR_ANDEN_PLAN"):
        pk.flet_sheet(plan, sha, [_svar("f" * 64)])
    s = _svar(sha)
    del s["svar"]["felter"]["00000000-0000-4000-8000-000000000004"]
    with pytest.raises(ControlError, match="KORT_UBESVARET"):
        pk.flet_sheet(plan, sha, [s])


# --- CLI, personfølsomhed og SQL --------------------------------------------------------------------------------

def _kor(*args):
    env = {k: v for k, v in os.environ.items() if k != "NODE_OPTIONS"}
    return subprocess.run([sys.executable, SCRIPT, *map(str, args)], capture_output=True, text=True, env=env)


def test_cli_ende_til_ende_printer_kun_tal_og_hashes(planmappe, tmp_path):
    k = _kor("kontekst-ids", "--plan-dir", planmappe)
    assert k.returncode == 0
    assert set(k.stdout.strip().split(",")) == set(_json(planmappe / "plan.json")["persona_ids"])
    ud = tmp_path / "kort"
    h = _kor("html", "--plan-dir", planmappe, "--kontekst", FIX / "kontekst.json", "--out-dir", ud)
    assert h.returncode == 0, h.stderr
    svar = tmp_path / "svar.json"
    svar.write_text(json.dumps(_svar(_plan_sha(planmappe)), ensure_ascii=False), encoding="utf-8")
    ark = tmp_path / "ud" / "ark.txt"
    f = _kor("flet", "--plan-dir", planmappe, "--svar", svar, "--out", ark)
    assert f.returncode == 0, f.stderr
    assert ARK_SHA256 in f.stdout
    for res in (k, h, f):
        for navn in NAVNE + ("Opdigtet", "syntetisk testperson", "hofjægermester", "kammerherre"):
            assert navn not in res.stdout + res.stderr
    sider = sorted(ud.glob("*.html"))
    assert sider and all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in sider + [ark])
    # Fejl bærer kode og tal, aldrig værdier.
    svar.write_text(json.dumps(_svar("f" * 64)), encoding="utf-8")
    bad = _kor("flet", "--plan-dir", planmappe, "--svar", svar, "--out", tmp_path / "x.txt")
    assert bad.returncode == 1 and "KORT_SVAR_ANDEN_PLAN" in bad.stdout + bad.stderr


def test_kontekst_sql_er_laese_kun():
    sql = SQL.read_text(encoding="utf-8")
    assert "SET TRANSACTION READ ONLY" in sql and "ROLLBACK" in sql
    kode = "\n".join(l for l in sql.splitlines() if not l.lstrip().startswith("--"))
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT)\b", kode, re.I)
    assert ":'personas'" in sql
