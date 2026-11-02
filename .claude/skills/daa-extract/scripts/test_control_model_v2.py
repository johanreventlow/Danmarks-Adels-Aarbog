"""Kontrolværktøjet v2 (trin 6c-2, spec 2026-11-02 §4.4 pkt. 2, 3, 5, 7, §4.5, §4.6; plan Task 7).

Alle fixtures er syntetiske: id'er, opdigtede værdier og ingen posttekst."""
from __future__ import annotations

import hashlib
import json
import random
import re
import subprocess
import sys
from pathlib import Path

import pytest

import control_model_v2 as v2
from control_model import ControlError

SCRIPT = str(Path(__file__).with_name("control_model_v2.py"))
SRC = 3
SHEET_SHA = "a" * 64
HASHES = {"classification_sha256": "c" * 64, "sample_sha256": "d" * 64, "rows_kontrol_sha256": "e" * 64}
STRATA = {"ubekraeftet": 10, "oevrige": 10}


def iid(n: int) -> str:
    return f"00000000-0000-4000-8000-{n:012d}"


def pid(n: int) -> str:
    return f"11111111-0000-4000-8000-{n:012d}"


def item(n: int, klasse: str = "MATCH", *, version: int = 1, predicate: str = "person.death") -> dict:
    return {"interpretation_id": iid(n), "version": version, "predicate": predicate, "class": klasse,
            "assertion_id": -n if klasse in ("MATCH", "MATCH_SINGLETON") else None}


def row(n: int, *, persona: int, outcome: str | None = "enig", version: int = 1, predicate: str = "person.death",
        value: str = "1850", navn_forkortes: bool | None = False, maal: bool = True,
        identity_version: int = 1) -> dict:
    r = {"interpretation_id": iid(n), "version": version, "record_key": f"I-{persona:04d}",
         "predicate": predicate, "value_text": value, "confidence": 1, "persona_role": "principal",
         "cited": [{"ordinal": 1, "text": "syntetisk", "flags": []}],
         "persona_id": pid(persona), "identity_outcome": outcome, "identity_version": identity_version,
         "navn_forkortes": navn_forkortes, "rettelse_maal": None}
    if maal:
        r["rettelse_maal"] = {"assertion_id": -1000 - n,
                              "forventet": {"fact_id": -2000 - n, "faktatype": "død", "vaerdi_tekst": None,
                                            "date_raw": "1849", "valgt_assertion_id": -1000 - n,
                                            "citation_sources": [SRC]}}
    return r


def bygge(n_svag: int, n_rest: int, extra: list[tuple[dict, dict]] = ()) -> tuple[dict, list[dict]]:
    """n_svag MATCH-felter fra personas med svag identitet (én persona pr. felt), n_rest fra enige."""
    items, rows = [], []
    for n in range(1, n_svag + 1):
        items.append(item(n))
        rows.append(row(n, persona=n, outcome="svag" if n % 2 else "ingen_kandidat"))
    for n in range(1001, 1001 + n_rest):
        items.append(item(n))
        rows.append(row(n, persona=n, outcome="enig"))
    for i, r in extra:
        items.append(i)
        rows.append(r)
    return {"items": items, "counts": {}}, rows


def plan_af(k, rows, strata=STRATA):
    return v2.plan_run_v2(k, rows, source_id=SRC, strata=strata)


def udfyld(plan: dict, svar: dict[str, str] | None = None, persona_svar: dict[str, str] | None = None) -> str:
    """Render det tomme ark og udfyld: stikprøvefelter B, andre felter D, personas '-'; overstyres pr. id."""
    svar, persona_svar = svar or {}, persona_svar or {}
    ud = []
    for line in v2.render_sheet_v2(plan).splitlines():
        m = re.match(r"^F (\S+) (\d+) : _$", line)
        if m:
            tok = svar.get(m[1], "B" if m[1] in plan["sample_ids"] else "D")
            line = f"F {m[1]} {m[2]} : {tok}"
        m = re.match(r"^P (\S+) (\d+) : -$", line)
        if m and m[1] in persona_svar:
            line = f"P {m[1]} {m[2]} : {persona_svar[m[1]]}"
        ud.append(line)
    return "\n".join(ud) + "\n"


def anvend(plan, tekst):
    return v2.apply_plan_v2(plan, tekst, sheet_sha256=SHEET_SHA, hashes=HASHES)


# --- stratificeret stikprøve ------------------------------------------------------------------------------------

def test_stratificering_10_og_10_under_ny_seed():
    k, rows = bygge(30, 40)
    p = plan_af(k, rows)
    svage = {i["interpretation_id"] for i in k["items"][:30]}
    nogle = sorted(svage, key=lambda x: hashlib.sha256(f"kontrolmodel-v2:{x}".encode()).hexdigest())[:10]
    oevrige = sorted({i["interpretation_id"] for i in k["items"][30:]},
                     key=lambda x: hashlib.sha256(f"kontrolmodel-v2:{x}".encode()).hexdigest())[:10]
    assert p["sample_ids"] == sorted(nogle + oevrige)
    assert p["strata"]["ubekraeftet"]["trukket"] == 10 and p["strata"]["oevrige"]["trukket"] == 10
    assert p["strata"]["opfyldt_fra_andet"] == 0
    assert len(p["machine_candidates"]) == 50
    assert not set(p["sample_ids"]) & {m["interpretation_id"] for m in p["machine_candidates"]}
    assert all(m["persona_id"] for m in p["machine_candidates"])


def test_stikproeven_er_deterministisk_og_uafhaengig_af_raekkefoelgen():
    k, rows = bygge(30, 40)
    blandet = dict(k, items=random.Random(7).sample(k["items"], len(k["items"])))
    assert plan_af(k, rows)["sample_ids"] == plan_af(blandet, list(reversed(rows)))["sample_ids"]


def test_opfyldning_fra_det_andet_stratum_rapporteres():
    k, rows = bygge(4, 40)
    p = plan_af(k, rows)
    assert len(p["sample_ids"]) == 20
    assert set(i["interpretation_id"] for i in k["items"][:4]) <= set(p["sample_ids"])
    assert p["strata"]["ubekraeftet"] == {"maal": 10, "kandidater": 4, "trukket": 4}
    assert p["strata"]["oevrige"]["trukket"] == 16
    assert p["strata"]["opfyldt_fra_andet"] == 6


def test_opfyldning_den_anden_vej():
    k, rows = bygge(40, 3)
    p = plan_af(k, rows)
    assert len(p["sample_ids"]) == 20
    assert p["strata"]["oevrige"]["trukket"] == 3 and p["strata"]["ubekraeftet"]["trukket"] == 17
    assert p["strata"]["opfyldt_fra_andet"] == 7


def test_menneskets_raekker_er_real_diff_skrivemaade_og_stikproeve():
    extra = [(item(5001, "REAL_DIFF"), row(5001, persona=5001)),
             (item(5002, "SKRIVEMAADE"), row(5002, persona=5002)),
             (item(5003, "NO_FACT"), row(5003, persona=5003)),
             (item(5004, "TARGET_SHARED"), row(5004, persona=5004)),
             (item(5005, "ALREADY_BOUND_OTHER"), row(5005, persona=5005))]
    k, rows = bygge(15, 15, extra)
    p = plan_af(k, rows)
    ark = {r["interpretation_id"] for r in p["rows_kontrol"]}
    assert ark == set(p["sample_ids"]) | {iid(5001), iid(5002)}
    assert p["real_diff_ids"] == [iid(5001)] and p["skrivemaade_ids"] == [iid(5002)]
    assert p["counts"].get("TARGET_SHARED") == 1 and p["counts"].get("ALREADY_BOUND_OTHER") == 1
    assert {x["persona_id"] for x in p["personas"]} == {r["persona_id"] for r in p["rows_kontrol"]}


def test_plan_kraever_kildescope():
    k, rows = bygge(15, 15)
    with pytest.raises(ControlError, match="PLAN_SCOPE_MANGLER"):
        v2.plan_run_v2(k, rows, source_id=None, strata=STRATA)
    uden = [{kk: vv for kk, vv in r.items() if kk not in ("identity_outcome", "persona_id")} for r in rows]
    with pytest.raises(ControlError, match="PLAN_SCOPE_MANGLER"):
        plan_af(k, uden)


# --- arket v2 ---------------------------------------------------------------------------------------------------

def test_ark_round_trip():
    extra = [(item(5001, "REAL_DIFF"), row(5001, persona=5001)),
             (item(5002, "SKRIVEMAADE", predicate="person.birth"), row(5002, persona=5001, predicate="person.birth"))]
    k, rows = bygge(15, 15, extra)
    p = plan_af(k, rows)
    tekst = udfyld(p, {iid(5001): "B", iid(5002): "V"})
    fields, personas = v2.parse_sheet_v2(tekst)
    assert {(f.interpretation_id, f.version) for f in fields} == {(r["interpretation_id"], r["version"])
                                                                    for r in p["rows_kontrol"]}
    assert {(x.persona_id, x.identity_version) for x in personas} == {(x["persona_id"], x["identity_version"])
                                                                      for x in p["personas"]}
    tok = {f.interpretation_id: f.token for f in fields}
    assert tok[iid(5001)] == "B" and tok[iid(5002)] == "V"
    # Samme ark → samme bytes → samme parse; kun syntetiske id'er i det tomme ark (ingen værdier).
    assert v2.render_sheet_v2(p) == v2.render_sheet_v2(p)
    assert "1850" not in v2.render_sheet_v2(p) and "syntetisk" not in v2.render_sheet_v2(p)
    v2.check_sheet_v2(p, fields, personas)


def test_ark_afviser_ugyldige_linjer():
    for tekst, kode in (
        (f"F {iid(1)} 1 : A\n", "SHEET_V2_LINE_INVALID"),
        (f"  F {iid(1)} 1 : B\n", "SHEET_V2_LINE_INVALID"),
        (f"D {iid(1)} 1 : A\n", "SHEET_V2_LINE_INVALID"),
        (f"P {pid(1)} 1 : X\n", "SHEET_V2_LINE_INVALID"),
        (f"P {pid(1)} 1 : P abc\n", "SHEET_V2_LINE_INVALID"),
        (f"P {pid(1)} 1 : P 5 # note\n", "SHEET_V2_LINE_INVALID"),
        (f"P {pid(1)} 1 : -\nF {iid(1)} 1 : _\n", "SHEET_V2_UNDECIDED"),
        (f"P {pid(1)} 1 : _\n", "SHEET_V2_UNDECIDED"),
        (f"P {pid(1)} 1 : -\nF {iid(1)} 1 : B\nF {iid(1)} 1 : D\n", "SHEET_DUPLICATE"),
        (f"P {pid(1)} 1 : -\nP {pid(1)} 1 : P\n", "SHEET_DUPLICATE"),
    ):
        with pytest.raises(ControlError, match=kode):
            v2.parse_sheet_v2(tekst)


def test_uafgjorte_felter_er_tilladt_under_en_P_persona():
    fields, personas = v2.parse_sheet_v2(f"P {pid(1)} 1 : P 42\nF {iid(1)} 1 : _\n")
    assert personas[0].token == "P" and personas[0].person_id == 42 and fields[0].token == "_"
    with pytest.raises(ControlError, match="SHEET_V2_UNDECIDED"):
        v2.parse_sheet_v2(f"P {pid(1)} 1 : P 42\nF {iid(1)} 1 : _\nP {pid(2)} 1 : -\nF {iid(2)} 1 : _\n")


def test_ark_skal_daekke_planen_i_planens_orden():
    extra = [(item(5001, "REAL_DIFF"), row(5001, persona=5001))]
    k, rows = bygge(15, 15, extra)
    p = plan_af(k, rows)
    linjer = udfyld(p).splitlines()
    uden = "\n".join(x for x in linjer if iid(5001) not in x) + "\n"
    with pytest.raises(ControlError, match="SHEET_IDENTITY_MISMATCH"):
        anvend(p, uden)
    blokke = "\n".join(linjer).split("\n\n")
    byttet = "\n\n".join([blokke[0], blokke[2], blokke[1]] + blokke[3:]) + "\n"
    with pytest.raises(ControlError, match="SHEET_ORDER_MISMATCH"):
        anvend(p, byttet)


# --- anvendelsen --------------------------------------------------------------------------------------------------

def test_D_paa_stikproevefelt_giver_SAMPLE_FAILED_og_ingen_sql(tmp_path):
    k, rows = bygge(15, 15)
    p = plan_af(k, rows)
    for tok in ("D", "V"):
        with pytest.raises(ControlError, match="SAMPLE_FAILED"):
            anvend(p, udfyld(p, {p["sample_ids"][0]: tok}))


def test_P_paa_stikproevepersona_giver_SAMPLE_FAILED():
    k, rows = bygge(15, 15)
    p = plan_af(k, rows)
    sp = next(r["persona_id"] for r in p["rows_kontrol"] if r["interpretation_id"] == p["sample_ids"][0])
    with pytest.raises(ControlError, match="SAMPLE_FAILED"):
        anvend(p, udfyld(p, persona_svar={sp: "P"}))


def _sidst_i_lodtraekningen(pulje: list[int], antal: int) -> list[int]:
    """Syntetiske n'er, hvis v2-nøgle ligger efter hele puljens: de trækkes aldrig foran puljen."""
    def noegle(n):
        return hashlib.sha256(f"kontrolmodel-v2:{iid(n)}".encode()).hexdigest()
    graense = max(noegle(n) for n in pulje)
    return [n for n in range(7002, 9000) if noegle(n) > graense][:antal]


def test_P_paa_persona_med_maskine_match_fjerner_dem_fra_alt():
    # Persona 7000 har et REAL_DIFF (på arket) og to MATCH-felter uden for stikprøven (maskinkandidater).
    m1, m2 = _sidst_i_lodtraekningen(list(range(1001, 1011)), 2)
    extra = [(item(7001, "REAL_DIFF"), row(7001, persona=7000)),
             (item(m1), row(m1, persona=7000)), (item(m2), row(m2, persona=7000))]
    k, rows = bygge(10, 10, extra)   # 10 + 12 MATCH; de to sidste i lodtrækningen er 7000's
    p = plan_af(k, rows)
    assert iid(m1) not in p["sample_ids"] and iid(m2) not in p["sample_ids"]
    assert {iid(m1), iid(m2)} <= {m["interpretation_id"] for m in p["machine_candidates"]}
    a = anvend(p, udfyld(p, {iid(7001): "B"}, {pid(7000): "P 4242"}))
    alle_ids = ({m["interpretation_id"] for m in a["maskine"]} | {x["interpretation_id"] for x in a["afgoerelser"]}
                | {x["interpretation_id"] for x in a["rettelser"]})
    assert not alle_ids & {iid(7001), iid(m1), iid(m2)}
    assert len(a["maskine"]) == 0
    assert a["unresolved"] == [{"persona_id": pid(7000), "identity_version": 1, "person_id": 4242,
                                "note": "ønsket_person_id=4242; grund=forkert person",
                                "context": {"basis": "human_sheet", "sheet_sha256": SHEET_SHA,
                                            "rows_sha256": HASHES["rows_kontrol_sha256"],
                                            "line": a["unresolved"][0]["context"]["line"]},
                                "line": a["unresolved"][0]["line"]}]
    assert isinstance(a["unresolved"][0]["context"]["line"], int)
    # Planpartitionen: MATCH = maskine ∪ stikprøve ∪ udtaget pga. P.
    v2.verify_sql_v2(p, a)


def test_bart_P_har_kun_grunden_i_noten():
    extra = [(item(7001, "REAL_DIFF"), row(7001, persona=7000))]
    k, rows = bygge(10, 10, extra)
    p = plan_af(k, rows)
    a = anvend(p, udfyld(p, persona_svar={pid(7000): "P"}))
    assert a["unresolved"][0]["note"] == "grund=forkert person" and a["unresolved"][0]["person_id"] is None
    assert set(a["unresolved"][0]["context"]) == {"basis", "sheet_sha256", "rows_sha256", "line"}


def test_mapping_B_D_V():
    extra = [(item(7001, "REAL_DIFF"), row(7001, persona=7001)),
             (item(7002, "SKRIVEMAADE", predicate="person.birth"),
              row(7002, persona=7002, predicate="person.birth", value="12. marts 1702")),
             (item(7003, "REAL_DIFF"), row(7003, persona=7003)),
             (item(7004, "REAL_DIFF"), row(7004, persona=7004))]
    k, rows = bygge(10, 12, extra)
    p = plan_af(k, rows)
    a = anvend(p, udfyld(p, {iid(7001): "B", iid(7002): "B # bogen", iid(7003): "D # db", iid(7004): "V # ?"}))
    ret = {r["interpretation_id"]: r for r in a["rettelser"]}
    assert set(ret) == {iid(7001), iid(7002)}
    assert ret[iid(7002)]["p_dato"] == {"date_min": "1702-03-12", "date_max": "1702-03-12", "date_qualifier": None}
    assert ret[iid(7001)]["p_dato"] == {"date_min": "1850-01-01", "date_max": "1850-12-31", "date_qualifier": None}
    assert ret[iid(7001)]["assertion_id"] == -1000 - 7001
    assert set(ret[iid(7001)]["forventet"]) == {"fact_id", "faktatype", "vaerdi_tekst", "date_raw",
                                                "valgt_assertion_id", "citation_sources"}
    st = {x["interpretation_id"]: x for x in a["afgoerelser"]}
    assert st[iid(7001)]["status"] == "accepted" and st[iid(7002)]["status"] == "accepted"
    assert st[iid(7003)]["status"] == "rejected" and st[iid(7003)]["evidence"]["grund"] == "database_har_ret"
    assert st[iid(7004)]["status"] == "unresolved"
    assert st[iid(7002)]["evidence"]["note"] == "bogen"
    assert all(x["evidence"]["method"] == "human-sheet-kontrol-v2" for x in a["afgoerelser"])
    # Stikprøvens B → accepted (afgørelser med klassen MATCH); maskinen er resten af MATCH.
    stik = {x["interpretation_id"] for x in a["afgoerelser"] if x["klasse"] == "MATCH"}
    assert stik == set(p["sample_ids"])
    assert {m["interpretation_id"] for m in a["maskine"]} == {m["interpretation_id"] for m in p["machine_candidates"]}
    assert all(m["evidence"]["method"] == "machine-corroboration-v2" for m in a["maskine"])
    v2.verify_sql_v2(p, a)


def test_B_paa_navn_forkortes_afvises():
    for nf in (True, None):
        extra = [(item(7001, "REAL_DIFF", predicate="person.name"),
                  row(7001, persona=7001, predicate="person.name", value="Testa", navn_forkortes=nf))]
        k, rows = bygge(10, 10, extra)
        p = plan_af(k, rows)
        with pytest.raises(ControlError, match="SHEET_V2_LINE_INVALID"):
            anvend(p, udfyld(p, {iid(7001): "B"}))
        anvend(p, udfyld(p, {iid(7001): "D"}))   # D og V er tilladt


def test_B_uden_entydigt_maal_afvises():
    extra = [(item(7001, "REAL_DIFF"), row(7001, persona=7001, maal=False))]
    k, rows = bygge(10, 10, extra)
    p = plan_af(k, rows)
    with pytest.raises(ControlError, match="SHEET_V2_LINE_INVALID"):
        anvend(p, udfyld(p, {iid(7001): "B"}))


# --- SQL'en -------------------------------------------------------------------------------------------------------

def _plan_med_alt():
    extra = [(item(7001, "REAL_DIFF"), row(7001, persona=7001)),
             (item(7002, "SKRIVEMAADE"), row(7002, persona=7002)),
             (item(7003, "REAL_DIFF"), row(7003, persona=7003)),
             (item(7010, "REAL_DIFF"), row(7010, persona=7010)),
             (item(7020, "REAL_DIFF"), row(7020, persona=7020))]
    m1 = _sidst_i_lodtraekningen(list(range(1001, 1013)), 1)[0]
    extra.append((item(m1), row(m1, persona=7010)))
    k, rows = bygge(10, 12, extra)
    p = plan_af(k, rows)
    a = anvend(p, udfyld(p, {iid(7001): "B", iid(7002): "B", iid(7003): "V"},
                         {pid(7010): "P 4242", pid(7020): "P"}))
    return p, a


def test_sql_raekkefoelge_P_rettelser_afgoerelser_reklassifikation_maskine_binding():
    p, a = _plan_med_alt()
    sql = v2.sql_v2(p, a)
    pos = [sql.index(s) for s in ("PERSONA_HAR_PROMOTIONER", "public.red_afgoer_source_persona(",
                                  "public.red_ret_paastand(", "public.red_decide_interpretation(",
                                  "interpretation_control_classification.sql", "MACHINE_NOT_MATCH",
                                  "machine-corroboration-v2", "interpretation_promotion_targets_scoped.sql",
                                  "public.red_promote_interpretations_batch(")]
    assert pos == sorted(pos)
    assert sql.startswith("\\set ON_ERROR_STOP on\nBEGIN;") and sql.rstrip().splitlines()[-2] == "COMMIT;"
    assert "REPEATABLE READ" not in sql and "SERIALIZABLE" not in sql
    assert f"set_config('daa.control_src', '{SRC}', true)" in sql
    assert "set_config('request.jwt.claim.sub', :'actor', true)" in sql
    assert sql.count("public.red_afgoer_source_persona(") == 2
    assert sql.count("public.red_ret_paastand(") == 2
    # De to B-rettede er accepteret i afgørelsesfasen før reklassifikationen; stikprøven efter.
    pre = sql[:sql.index("interpretation_control_classification.sql")]
    assert iid(7001) in pre and iid(7003) in pre
    post = sql[sql.index("MACHINE_NOT_MATCH"):]
    assert all(s in post for s in p["sample_ids"])


def test_hvert_red_kald_har_sin_egen_nulstilling_af_change_set():
    p, a = _plan_med_alt()
    sql = v2.sql_v2(p, a)
    reset = "set_config('app.change_set_id','',true)"
    kald = [m.start() for m in re.finditer(r"public\.red_\w+\(", sql)]
    nulstil = [m.start() for m in re.finditer(re.escape(reset), sql)]
    assert len(kald) >= 6 and len(nulstil) == len(kald)
    forrige = -1
    for k in kald:
        foer = [n for n in nulstil if forrige < n < k]
        assert len(foer) == 1, sql[max(0, k - 200):k]
        forrige = k


def test_P_vaernet_og_personkontrollen_staar_foer_identitetskaldet():
    p, a = _plan_med_alt()
    sql = v2.sql_v2(p, a)
    kald = sql.index("public.red_afgoer_source_persona(")
    foer = sql[:kald]
    assert "PERSONA_HAR_PROMOTIONER" in foer and "interpretation_promotion" in foer
    assert "interpretation_party" in foer
    assert "public.person" in foer and "4242" in foer and "SHEET_V2_LINE_INVALID" in foer
    assert "canonical_person_id" in foer and "decision_status = 'accepted'" in foer
    # Konteksten er præcis kortkvitteringen; ønsket person kun i noten.
    assert "'ønsket_person_id=4242; grund=forkert person'" in sql
    assert '"ønsket_person_id"' not in sql
    ctx = re.findall(r"'(\{\"basis\": \"human_sheet\"[^']*)'::jsonb", sql)
    assert len(ctx) == 2 and all(set(json.loads(c)) == {"basis", "sheet_sha256", "rows_sha256", "line"} for c in ctx)
    assert all(isinstance(json.loads(c)["line"], int) for c in ctx)


def test_rettelsen_sender_p_dato_kun_for_datoer():
    extra = [(item(7001, "REAL_DIFF", predicate="person.title"),
              row(7001, persona=7001, predicate="person.title", value="Testtitel")),
             (item(7002, "REAL_DIFF"), row(7002, persona=7002, value="ca. 1760"))]
    k, rows = bygge(10, 10, extra)
    p = plan_af(k, rows)
    a = anvend(p, udfyld(p, {iid(7001): "B", iid(7002): "B"}))
    sql = v2.sql_v2(p, a)
    linjer = [x for x in sql.splitlines() if "public.red_ret_paastand(" in x]
    titel = next(x for x in linjer if iid(7001) in x)
    dato = next(x for x in linjer if iid(7002) in x)
    assert titel.rstrip().endswith("'bogen_har_ret', '%s'::uuid, NULL) \\g /dev/null" % iid(7001))
    assert '"date_qualifier": "about"' in dato


def test_verify_sql_kontrakter():
    p, a = _plan_med_alt()
    sql = v2.verify_sql_v2(p, a)
    assert "SET TRANSACTION READ ONLY" in sql and sql.rstrip().endswith("ROLLBACK;")
    assert "CONTROL_V2_PROMOTION_MISMATCH" in sql and "CONTROL_V2_P_PERSONA" in sql
    forventet = sorted(set(p["sample_ids"]) | {m["interpretation_id"] for m in a["maskine"]}
                       | {r["interpretation_id"] for r in a["rettelser"]})
    assert json.dumps(forventet) in sql
    # Planpartitionen fejler, hvis maskinsættet er pillet ved.
    snydt = dict(a, maskine=a["maskine"][1:])
    with pytest.raises(ControlError, match="PLAN_PARTITION_MISMATCH"):
        v2.verify_sql_v2(p, snydt)


def test_sql_indeholder_ingen_raekketekst():
    p, a = _plan_med_alt()
    assert "syntetisk" not in v2.sql_v2(p, a)


# --- CLI: alt-eller-intet og ingen værdier på stdout --------------------------------------------------------------

def _skriv(tmp_path, k, rows):
    (tmp_path / "k.json").write_text(json.dumps(k), encoding="utf-8")
    (tmp_path / "r.json").write_text(json.dumps(rows), encoding="utf-8")


def _cli(*args):
    return subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)


def test_cli_plan_sql_og_SAMPLE_FAILED_skriver_intet(tmp_path):
    extra = [(item(7001, "REAL_DIFF"), row(7001, persona=7001, value="Hemmelig 1850"))]
    k, rows = bygge(12, 12, extra)
    _skriv(tmp_path, k, rows)
    plan_dir = tmp_path / "plan"
    r = _cli("plan", "--classification", str(tmp_path / "k.json"), "--rows", str(tmp_path / "r.json"),
             "--source-id", str(SRC), "--out-dir", str(plan_dir))
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Hemmelig" not in r.stdout + r.stderr and "syntetisk" not in r.stdout + r.stderr
    meta = json.loads((plan_dir / "plan.json").read_text())
    assert meta["seed"] == "kontrolmodel-v2" and meta["source_id"] == SRC and meta["persona_ids"]
    assert "strata" in meta
    for navn in ("plan.json", "rows-kontrol.json", "machine-candidates.json"):
        assert (plan_dir / navn).stat().st_mode & 0o777 == 0o600
    plan, _ = v2._load_plan(plan_dir)

    ark = tmp_path / "ark.txt"
    ark.write_text(udfyld(plan, {plan["sample_ids"][0]: "D"}), encoding="utf-8")
    sha = hashlib.sha256(ark.read_bytes()).hexdigest()
    out = tmp_path / "ud.sql"
    r = _cli("sql", "--plan-dir", str(plan_dir), "--sheet", str(ark), "--approved-sha256", sha, "--out", str(out))
    assert r.returncode == 1 and "SAMPLE_FAILED" in r.stdout and not out.exists()

    ark.write_text(udfyld(plan, {iid(7001): "B"}), encoding="utf-8")
    sha = hashlib.sha256(ark.read_bytes()).hexdigest()
    r = _cli("sql", "--plan-dir", str(plan_dir), "--sheet", str(ark), "--approved-sha256", "0" * 64,
             "--out", str(out))
    assert r.returncode == 1 and "SHEET_HASH_MISMATCH" in r.stdout and not out.exists()
    r = _cli("sql", "--plan-dir", str(plan_dir), "--sheet", str(ark), "--approved-sha256", sha, "--out", str(out))
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Hemmelig" not in r.stdout + r.stderr and out.stat().st_mode & 0o777 == 0o600
    vout = tmp_path / "verify.sql"
    r = _cli("verify-sql", "--plan-dir", str(plan_dir), "--sheet", str(ark), "--approved-sha256", sha,
             "--out", str(vout))
    assert r.returncode == 0 and vout.stat().st_mode & 0o777 == 0o600


def test_cli_plan_uden_kilde_afvises(tmp_path):
    k, rows = bygge(12, 12)
    _skriv(tmp_path, k, rows)
    r = _cli("plan", "--classification", str(tmp_path / "k.json"), "--rows", str(tmp_path / "r.json"),
             "--out-dir", str(tmp_path / "plan"))
    assert r.returncode != 0 and not (tmp_path / "plan").exists()
