"""Trin 6m del 2: faktaforslag_maal.sql. Kun syntetiske fixtures.

Task 2 (mål-SQL). DB-testen kræver PostgreSQL + psql; basen (t6m2_<tid>_<pid>) oprettes og droppes af testen selv.
Mangler serveren, springes den kun over lokalt; i CI (CI=true) fejler den (som test_maal_trin6c2.py).
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

import pytest

import test_maal_trin6c2 as t6  # genbrug af fixture-hjælpere (kun hjælpere, ingen tests/fixtures importeres)

HERE = Path(__file__).resolve().parent
MAAL_SQL = HERE / "faktaforslag_maal.sql"
CONTROL_ROWS = HERE / "interpretation_control_rows.sql"
DBNAVN = f"t6m2_{time.strftime('%Y%m%d%H%M%S')}_{os.getpid()}"

SRC, OTHER, ACTOR = -6490, -6491, "12000000-0000-0000-0000-000000069004"
RUN_S, RUN_O = "12000000-0000-0000-0000-000000069001", "12000000-0000-0000-0000-000000069002"


def _u(n: int) -> str:
    return f"12000000-0000-0000-0000-{n:012d}"


def _kode(sql: str) -> str:
    return "\n".join(l for l in sql.splitlines() if not l.lstrip().startswith("--"))


def test_maal_sql_er_laese_kun():
    sql = MAAL_SQL.read_text(encoding="utf-8")
    kode = [l for l in _kode(sql).splitlines() if l.strip()]
    assert kode[0].strip() == "BEGIN;"
    assert kode[1].strip() == "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;"
    assert kode[-1].strip() == "ROLLBACK;"
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT|COPY)\b", "\n".join(kode), re.I)
    assert ":src" in sql and "daa.faktaforslag_ids" in sql


@pytest.fixture(scope="module")
def db():
    if shutil.which("psql") is None or subprocess.run(["psql", "-X", "-Atc", "select 1", "-d", "postgres"],
                                                      capture_output=True).returncode != 0:
        if os.environ.get("CI"):
            pytest.fail("PostgreSQL er ikke tilgaengelig i CI")
        pytest.skip("ingen lokal PostgreSQL")
    t6._must(subprocess.run(["createdb", DBNAVN], capture_output=True, text=True), "createdb")
    try:
        for f in ("tests/sql/evidence-promotion-bootstrap.sql", "schema.sql", "db-rls.sql"):
            t6._must(t6._psql("-f", f, db=DBNAVN), f)
        t6._sql(DBNAVN, _setup(), "setup")
        yield DBNAVN
    finally:
        subprocess.run(["dropdb", DBNAVN], capture_output=True)  # kun basen, testen selv oprettede


def _setup() -> str:
    run = ("INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,"
           "input_sha256,manifest) VALUES ")
    s = (f"INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({SRC},'Fixture 6m2','synthetic','1900','DAA-udgave'),"
         f"({OTHER},'Fixture anden','synthetic','1901','DAA-udgave');\n"
         + run + f"('{RUN_S}',{SRC},'t6m2-s','fixture','fixture','fixture',repeat('1',64),'{{}}'),"
         f"('{RUN_O}',{OTHER},'t6m2-o','fixture','fixture','fixture',repeat('1',64),'{{}}');\n"
         "INSERT INTO public.person(id,levende,privat,status) VALUES (-6491,false,false,'t'),(-6492,false,false,'t'),"
         "(-6493,false,false,'t'),(-6494,false,false,'t');\n")
    # P1 -6491: enkelt mål; P2 -6492: mål bundet af en anden nøgle; P3 -6493: to mål (ingen rettelse_maal); P4: uden identitet
    for n, p in ((1, -6491), (2, -6492), (3, -6493)):
        s += t6._persona(_u(100 + n), SRC, RUN_S, f"t6m2:s{n}", p)
    s += t6._persona(_u(104), SRC, RUN_S, "t6m2:s4", None, "unresolved", '{"basis":"x"}')
    s += t6._persona(_u(202), OTHER, RUN_O, "t6m2:o2", -6492)
    s += t6._date_fact(-6491, -69601, "fødsel", "12. marts\n1750", [SRC])
    s += "UPDATE public.assertion SET date_min='1750-03-12',date_max='1750-03-12',date_qualifier='exact' WHERE id=-69601;\n"
    s += t6._date_fact(-6492, -69602, "fødsel", "4. maj 1763\n", [SRC])
    s += t6._date_fact(-6493, -69603, "fødsel", "2. maj 1761", [SRC])
    s += t6._date_fact(-6493, -69604, "fødsel", "2. maj  1761", [SRC])
    # forslag (version 1, proposed): ét pr. person
    for n, key, pers, val in ((1, 501, 101, "12. marts 1750"), (2, 502, 102, "4. maj 1763"), (3, 503, 103, "2. maj 1761"),
                              (4, 504, 104, "1. jan 1700")):
        s += t6._interp(_u(400 + n), _u(key), 1, SRC, _u(pers), "person.birth", val, RUN_S)
    # kæden control_rows kræver: rendition, forekomst, post, accepteret anker, observation og kobling pr. forslag
    s += (f"INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256) "
          f"VALUES ('{_u(700)}',{SRC},'t6m2','fixture',repeat('1',64));\n")
    for n in range(1, 5):
        s += (f"INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) "
              f"VALUES ('{_u(710 + n)}',{SRC},'t6m2:r{n}','fixture','{RUN_S}');\n"
              f"INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,"
              f"char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES "
              f"('{_u(720 + n)}','{_u(700)}','o{n}',1,1,{n * 100},{n * 100 + 50},'tekst','f','f','{RUN_S}');\n"
              f"INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,"
              f"version,decided_by,decided_by_name) VALUES ('{_u(720 + n)}','{_u(710 + n)}','accepted',"
              f"'{{\"fixture\":true}}',1,'{ACTOR}','fixture');\n"
              f"INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,"
              f"char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES "
              f"('{_u(730 + n)}','{_u(720 + n)}','clause',1,1,{n * 100},{n * 100 + 50},'klausul','clear','fixture',"
              f"'{RUN_S}');\n"
              f"INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) "
              f"VALUES ('{_u(400 + n)}','{_u(730 + n)}','supporting',1);\n")
    # P2: en accepteret fortolkning med en ANDEN nøgle (anden kilde) med gyldig binding på målet
    s += t6._interp(_u(415), _u(515), 1, OTHER, _u(202), "person.birth", "4. maj 1763\n", RUN_O, status="accepted")
    s += t6._promo(_u(615), _u(415), "person-birth-v1", "assertion", -69602, '{"fixture":"t6m2"}')
    return s


def _kor(db: str, sql: Path, preamble: str, *vars_: str) -> str:
    args: list[str] = []
    for v in vars_:
        args += ["-v", v]
    return t6._must(t6._psql(*args, db=db, stdin=preamble + f"\\i {sql}\n"), sql.name)


def _maal(db: str, ids: list[str]) -> dict:
    pre = f"SET daa.faktaforslag_ids = '{json.dumps(ids)}';\n"
    return json.loads(_kor(db, MAAL_SQL, pre, f"src={SRC}"))


def _control(db: str) -> dict:
    rows = json.loads(_kor(db, CONTROL_ROWS, f"SET daa.control_src = '{SRC}';\n"))
    return {r["interpretation_id"]: r for r in rows}


def test_rettelse_maal_som_control_rows(db):
    ids = [_u(401), _u(402), _u(403), _u(404)]
    ctl = _control(db)
    ud = _maal(db, ids)
    assert ud["source_id"] == SRC
    by = {r["interpretation_id"]: r for r in ud["forslag"]}
    assert len(by) == 4
    for i in ids:  # proposed: begge filer giver samme rettelse_maal (mål-SQL'en tilføjer value_kind)
        m = by[i]["rettelse_maal"]
        c = ctl[i]["rettelse_maal"]
        if c is None:
            assert m is None
        else:
            assert m.pop("value_kind") == "date_raw"
            assert m == c
    assert by[_u(401)]["rettelse_maal"]["assertion_id"] == -69601
    assert by[_u(403)]["rettelse_maal"] is None and by[_u(404)]["rettelse_maal"] is None
    assert by[_u(404)]["person_id"] is None and by[_u(401)]["person_id"] == -6491
    assert by[_u(401)]["maal_bundet_af_anden"] is False and by[_u(402)]["maal_bundet_af_anden"] is True
    assert by[_u(401)]["egen_binding"] is None
    assert (by[_u(401)]["status"], by[_u(401)]["gaeldende_id"], by[_u(401)]["gaeldende_version"]) == ("proposed", _u(401), 1)
    assert by[_u(401)]["value_type"] == "string" and by[_u(401)]["kind"] == "property"
    # den accepterede fortolkning har en gyldig egen binding
    eb = _maal(db, [_u(415)])["forslag"][0]["egen_binding"]
    assert eb == {"promotion_id": _u(615), "gyldig": True, "target_id": -69602}


def test_afgjort_forslag_har_stadig_maal(db):
    # P1's forslag afgøres rejected (version 2): mål-SQL'en giver stadig målet, og gaeldende peger på version 2.
    t6._sql(db, f"INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,"
                f"interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,"
                f"extraction_run_id,supersedes_id,decided_by,decided_by_name,decided_at,decision_evidence) VALUES "
                f"('{_u(421)}','{_u(501)}',2,{SRC},'{_u(101)}','property','person.birth',"
                f"to_jsonb('12. marts 1750'::text),'fixture','source_statement',1,'rejected','fixture','{RUN_S}','{_u(401)}',"
                f"'{ACTOR}','fixture',now(),'{{\"grund\":\"fixture\"}}');\n")
    ud = _maal(db, [_u(401), _u(421)])
    by = {r["interpretation_id"]: r for r in ud["forslag"]}
    assert by[_u(421)]["status"] == "rejected"
    assert by[_u(421)]["rettelse_maal"]["assertion_id"] == -69601
    assert by[_u(421)]["tidligere"]["grund"] == "fixture" and by[_u(421)]["tidligere"]["decided_at"]
    assert by[_u(401)]["gaeldende_id"] == _u(421) and by[_u(401)]["gaeldende_version"] == 2
    assert by[_u(401)]["rettelse_maal"]["assertion_id"] == -69601
    # control_rows viser derimod ikke længere forslaget (kun proposed)
    assert _u(401) not in _control(db)


# --- Task 3: klassifikation (ren Python) -------------------------------------------------------------------------------
import copy  # noqa: E402

import faktaforslag_rettelse as fr  # noqa: E402


def _fx(iid="i1", status="proposed", value="Carl Hansen", kind="property", gid=None, maal_v="Carl Hansen",
        pred="person.name", vk="text", bundet=False, eb=None, med_maal=True, vt="string"):
    rm = {"assertion_id": 77, "forventet": {"fact_id": 5, "faktatype": "x", "vaerdi_tekst": maal_v, "date_raw": maal_v,
                                           "valgt_assertion_id": 77, "citation_sources": []},
          "graenser": None, "value_kind": vk} if med_maal else None
    return {"interpretation_id": iid, "status": status, "gaeldende_id": gid or iid, "kind": kind, "predicate": pred,
            "value_text": value, "value_type": vt, "rettelse_maal": rm, "maal_bundet_af_anden": bundet,
            "egen_binding": eb}


def _ar(ref="p1-f1", svar="FORSLAG_FEJL", felt="person.name", laes="Carl Hansen", vaerdi="Carl Hansen"):
    return {"ref": ref, "svar": svar, "felt": felt, "vaerdi": vaerdi, "bogens_laesning": laes, "billede": "bekraefter"}


def _kl(a, f, ref="p1-f1", iid="i1", version=1):
    return fr.klassificer([a], {ref: {"type": "forslag", "interpretation_id": iid, "version": version}},
                          {"forslag": [f]})[0]


def test_saml_blanktegn_som_sql():
    assert fr.saml_blanktegn("  a  b\nc d e ") == "a b c d e"


def test_manifest_a_stabil_og_foelsom():
    a = [_ar(laes="Carl Hansen", vaerdi="Carl Hans")]
    k = [_kl(a[0], _fx(status="accepted", value="Carl Hans", maal_v="Carl Hans"))]
    base = fr.manifest_a(k, a)
    assert fr.manifest_a(copy.deepcopy(k), copy.deepcopy(a)) == base
    a2 = copy.deepcopy(a); a2[0]["bogens_laesning"] = "Carl Hanse"
    assert fr.manifest_a(k, a2) != base
    for mut in (lambda r: r.update(version=2), lambda r: r.update(klasse="BIND"),
                lambda r: r["forventet"].update(fact_id=9)):
        k2 = copy.deepcopy(k); mut(k2[0])
        assert fr.manifest_a(k2, a) != base


def test_uaendret_og_allerede_bundet_er_rapport():
    r = _kl(_ar(laes="Carl  Hansen"), _fx(status="proposed"))
    assert (r["klasse"], r["grund"], r["ny_vaerdi"]) == ("RAPPORT", "UAENDRET", "Carl Hansen")
    r = _kl(_ar(), _fx(status="accepted", eb={"promotion_id": 1, "gyldig": True, "target_id": 77}))
    assert (r["klasse"], r["grund"]) == ("RAPPORT", "ALLEREDE_BUNDET")


def test_binding_paa_andet_maal_spaerres():
    # nøglen er gyldigt bundet til påstand 99, rettelse_maal er 77: hverken ALLEREDE_BUNDET (værdien matcher 77) eller
    # RET_OG_BIND (værdien afviger) må flytte bindingen
    andet = {"promotion_id": 1, "gyldig": True, "target_id": 99}
    for laes in ("Carl Hansen", "Carl Hansen-Testlow"):
        r = _kl(_ar(laes=laes), _fx(status="accepted", eb=andet))
        assert (r["klasse"], r["grund"], r["assertion_id"]) == ("SPAERRET", "binding_paa_andet_maal", None)
    # gyldig binding på netop rettelse_maal: matcher → ALLEREDE_BUNDET, afviger → RET_OG_BIND (genbindes på 77)
    egen = {"promotion_id": 1, "gyldig": True, "target_id": 77}
    assert _kl(_ar(), _fx(status="accepted", eb=egen))["grund"] == "ALLEREDE_BUNDET"
    r = _kl(_ar(laes="Carl Hansen-Testlow"), _fx(status="accepted", eb=egen))
    assert (r["klasse"], r["assertion_id"]) == ("RET_OG_BIND", 77)
    # en ugyldig binding på et andet mål spærrer ikke
    r = _kl(_ar(laes="Carl Hansen-Testlow"), _fx(status="accepted", eb={**andet, "gyldig": False}))
    assert (r["klasse"], r["assertion_id"]) == ("RET_OG_BIND", 77)


def test_vaerditype_og_status_spaerres():
    for svar in ("FORSLAG_FEJL", "DB_FEJL"):
        r = _kl(_ar(svar=svar), _fx(status="accepted", value=None, vt="object"))
        assert (r["klasse"], r["grund"], r["ny_vaerdi"]) == ("SPAERRET", "vaerditype", None)
        r = _kl(_ar(svar=svar), _fx(status="superseded"))
        assert (r["klasse"], r["grund"], r["ny_vaerdi"]) == ("SPAERRET", "status", None)


def test_relation_og_begge_er_rapport():
    r = _kl(_ar(felt="relation.marriage"), _fx(kind="relation", pred="relation.marriage"))
    assert (r["klasse"], r["grund"], r["ny_vaerdi"]) == ("RAPPORT", "ikke_property", None)
    r = _kl(_ar(svar="BEGGE", felt="person.title"), _fx())
    assert (r["klasse"], r["grund"]) == ("RAPPORT", "BEGGE")
    r = _kl(_ar(laes=None), _fx())
    assert (r["klasse"], r["grund"]) == ("RAPPORT", "uden_laesning")


def test_proposed_bliver_version():
    assert _kl(_ar(laes="Carl Hans"), _fx(status="proposed"))["klasse"] == "VERSION"


def test_afgjort_lig_bliver_bind():
    r = _kl(_ar(laes="Hansen "), _fx(status="accepted", value="X", maal_v="hansen"))
    assert (r["klasse"], r["assertion_id"], r["ret_paastand"]) == ("BIND", 77, False)
    assert r["forventet"]["fact_id"] == 5


def test_afgjort_ulig_bliver_ret_og_bind():
    f = _fx(status="accepted", pred="person.death", value="1900", maal_v="1899")
    r = _kl(_ar(felt="person.death", laes="12. marts 1900"), f)
    assert r["klasse"] == "RET_OG_BIND" and r["ret_paastand"] is True
    assert r["forventet"] and r["p_dato"]["date_min"] == "1900-03-12"


def test_db_fejl_bruger_gaeldende_vaerdi():
    r = _kl(_ar(svar="DB_FEJL", laes="noget andet"), _fx(status="accepted", value="Carl  Hansen", maal_v="Andet"))
    assert r["ny_vaerdi"] == "Carl Hansen" and r["klasse"] == "RET_OG_BIND"


def test_spaerret_grunde():
    acc = dict(status="accepted")
    g = {
        "intet_maal": _kl(_ar(), _fx(**acc, med_maal=False)),
        "bundet_af_anden": _kl(_ar(), _fx(**acc, bundet=True)),
        "navn_forkortes": _kl(_ar(laes="Carl"), _fx(**acc, maal_v="Carl Hansen")),
        "dato_uden_graenser": _kl(_ar(felt="person.birth", laes="ukendt"),
                                  _fx(**acc, pred="person.birth", maal_v="1900")),
    }
    for grund, r in g.items():
        assert (r["klasse"], r["grund"]) == ("SPAERRET", grund)


def test_drift_naar_gaeldende_id_aendret():
    assert _kl(_ar(), _fx(gid="i2", status="accepted"))["klasse"] == "DRIFT"


def test_maal_mangler():
    with pytest.raises(fr.FaktaError) as e:
        fr.klassificer([_ar()], {"p1-f1": {"interpretation_id": "ukendt", "version": 1}}, {"forslag": []})
    assert e.value.kode == "MAAL_MANGLER"


def test_cli_printer_kun_tal(tmp_path):
    a = [_ar(laes="Carl Hans")]
    (tmp_path / "samlet.json").write_text(json.dumps({"A": a}))
    (tmp_path / "noegle.json").write_text(json.dumps({"p1-f1": {"type": "forslag", "interpretation_id": "i1",
                                                                  "version": 1}}))
    (tmp_path / "maal.json").write_text(json.dumps({"forslag": [_fx(status="proposed")]}))
    p = subprocess.run(["python3", str(HERE / "faktaforslag_rettelse.py"), "klassificer", "--ud", str(tmp_path),
                        "--maal", str(tmp_path / "maal.json")], capture_output=True, text=True, cwd=HERE)
    assert p.returncode == 0, p.stderr
    assert re.match(r"^FF_KLASSE_OK( [a-z_]+=[0-9a-f]+)+$", p.stdout.strip())
    assert (os.stat(tmp_path / "a-klasser.json").st_mode & 0o777) == 0o600


# --- Task 4: A-kort og flet -------------------------------------------------------------------------------------

def _krk(ref, klasse, felt="person.name", status="accepted", grund=None, iid=None, ny="Ny", maal_v="Gammel"):
    return {"ref": ref, "klasse": klasse, "grund": grund, "interpretation_id": iid or f"i-{ref}", "version": 1,
            "status": status, "ny_vaerdi": ny, "assertion_id": 7 if klasse in ("BIND", "RET_OG_BIND") else None,
            "forventet": {"vaerdi_tekst": maal_v, "date_raw": maal_v} if klasse in ("BIND", "RET_OG_BIND") else None,
            "p_dato": None, "ret_paastand": klasse == "RET_OG_BIND"}


def _a4(ref, felt="person.name"):
    return {"ref": ref, "svar": "FORSLAG_FEJL", "felt": felt, "vaerdi": "Forslag", "bogens_laesning": "Ny",
            "billede": "bekraefter", "grund": "modellens grund <b>x</b>", "databasen": None, "post": ref.split("-")[0]}


def _opsaet():
    kl = [_krk("p1-f1", "RET_OG_BIND", status="rejected"), _krk("p1-f2", "RET_OG_BIND", felt="person.title"),
          _krk("p2-f1", "VERSION", status="proposed"), _krk("p2-f2", "BIND", felt="person.title"),
          _krk("p3-f1", "RAPPORT", grund="BEGGE"), _krk("p3-f2", "SPAERRET", grund="intet_maal"),
          _krk("p3-f3", "DRIFT")]
    a = [_a4(r["ref"], "person.title" if r["ref"] in ("p1-f2", "p2-f2") else "person.name") for r in kl]
    samlet = {"A": a}
    bidder = [{"udgave": "T", "poster": [{"post": p, "tekst": f"Tekst for {p} <i>", "sider": [f"s{p}.png"],
                                          "forslag": [{"ref": r["ref"]} for r in kl if r["ref"].startswith(p)]}
                                         for p in ("p1", "p2", "p3")]}]
    maal = {"forslag": [{"interpretation_id": r["interpretation_id"], "version": r["version"], "status": r["status"],
                         "tidligere": {"status": "rejected", "grund": "fordi gammel afgørelse",
                                      "decided_at": "2026-01-01"},
                         "rettelse_maal": {"value_kind": "text", "forventet": {"vaerdi_tekst": "DBVAERDI",
                                                                               "date_raw": None}}}
                        for r in kl]}
    return kl, a, samlet, bidder, maal


def _html(kl, a, samlet, bidder, maal):
    k = fr.byg_kort(kl, samlet, bidder, maal)
    return "\n".join(fr.render(k, fr.manifest_a(kl, a)))


def test_kort_er_ikke_forudfyldt():
    h = _html(*_opsaet())
    assert "checked" not in h and "selected" not in h


def test_kort_viser_tidligere_afgoerelse():
    kl, a, s, b, m = _opsaet()
    k = fr.byg_kort(kl, s, b, m)
    rk = next(x for x in k if x.get("ref") == "p1-f1")
    assert rk["tidligere_status"] == "rejected" and rk["tidligere_grund"] == "fordi gammel afgørelse"
    # databasens værdi er klasse-rækkens forventet (manifest-bundet), ikke mål-filens
    assert rk["databasen"] == "Gammel" and rk["bogens_laesning"] == "Ny" and rk["vaerdi"] == "Forslag"
    assert rk["sider"] == ["../sider/sp1.png"] and "Tekst for p1" in rk["tekst"]
    h = _html(kl, a, s, b, m)
    assert "afvist" in h and "fordi gammel afgørelse" in h and "retter databasens værdi" in h
    assert "DBVAERDI" not in h


def test_kort_afviser_maal_drift():
    kl, a, s, b, m = _opsaet()
    for felt, v in (("version", 2), ("status", "accepted")):
        m2 = copy.deepcopy(m)
        next(f for f in m2["forslag"] if f["interpretation_id"] == "i-p1-f1")[felt] = v
        with pytest.raises(fr.FaktaError) as e:
            fr.byg_kort(kl, s, b, m2)
        assert e.value.kode == "MAAL_DRIFT"


def test_kort_db_fejl_viser_forslagets_vaerdi():
    kl, a, s, b, m = _opsaet()
    next(r for r in a if r["ref"] == "p1-f2")["svar"] = "DB_FEJL"
    k = fr.byg_kort(kl, s, b, m)
    assert {x["ref"]: x["svar"] for x in k if x.get("svarbar")} == {"p1-f1": "FORSLAG_FEJL", "p1-f2": "DB_FEJL"}
    h = _html(kl, a, s, b, m)
    assert 'k.svar === "DB_FEJL" ? "Forslagets værdi (bogen og forslaget er enige)" : "Bogens læsning"' in h


def test_rapport_og_spaerret_har_ingen_knapper():
    kl, a, s, b, m = _opsaet()
    k = fr.byg_kort(kl, s, b, m)
    rap = [x for x in k if x["type"] == "rapport"]
    assert {x["ref"] for x in rap} == {"p3-f1", "p3-f2", "p3-f3"}
    assert all(not x["svarbar"] for x in rap)
    assert "gives videre til 6c-3/6d" in _html(kl, a, s, b, m)


def test_vejledning_definerer_hvert_svar():
    h = _html(*_opsaet())
    for t in ("<b>F</b>", "<b>N</b>", "<b>tomt</b>", "genåbner", "er du i tvivl, så lad den stå tom"):
        assert t in h


def test_kun_ret_og_bind_har_knapper():
    kl, a, s, b, m = _opsaet()
    k = fr.byg_kort(kl, s, b, m)
    assert {x["ref"] for x in k if x.get("svarbar")} == {"p1-f1", "p1-f2"}
    ov = next(x for x in k if x["type"] == "oversigt")
    assert ov["felter"] == {"person.name": 1, "person.title": 1} and ov["antal"] == 2
    h = _html(kl, a, s, b, m)
    assert "omfattet af det samlede F (projektejeren 2026-11-07)" in h
    assert "p2-f1" not in json.dumps([x for x in k if x.get("svarbar")])


def test_html_escaper_indhold():
    h = _html(*_opsaet())
    assert "<b>x</b>" not in h.split("const DATA")[1]   # data ligger som JSON med < escapet
    assert "\\u003cb>x\\u003c/b>" in h


def _sv(ma, side, svar):
    return {"manifest_a": ma, "side": side, "svar": svar}


def test_flet_afviser():
    kl, a, s, b, m = _opsaet()
    ma = fr.manifest_a(kl, a)

    def kode(*filer):
        with pytest.raises(fr.FaktaError) as e:
            fr.flet_a(kl, ma, list(filer))
        return e.value.kode
    assert kode(_sv("x" * 64, 1, {})) == "MANIFEST_MISMATCH"
    assert kode(_sv(ma, 1, {"p9-f9": "F"})) == "SVAR_UKENDT_REF"
    for ref in ("p3-f1", "p3-f2", "p3-f3"):
        assert kode(_sv(ma, 1, {ref: "F"})) == "SVAR_IKKE_TILLADT"
    assert kode(_sv(ma, 1, {"p1-f1": "X"})) == "SVAR_UGYLDIGT"
    assert kode(_sv(ma, 1, {"p1-f1": "F"}), _sv(ma, 2, {"p1-f1": "N"})) == "SVAR_KONFLIKT"
    assert kode(_sv(ma, 1, {"p1-f1": "F"}), _sv(ma, 1, {"p1-f2": "F"})) == "SVAR_SIDE_DUBLET"


def test_flet_ark_findes(tmp_path):
    kl, a, s, b, m = _opsaet()
    (tmp_path / "a-klasser.json").write_text(json.dumps({"manifest_a": fr.manifest_a(kl, a), "klasser": kl}))
    (tmp_path / "samlet.json").write_text(json.dumps(s))
    (tmp_path / "ark-a.txt").write_text("x")
    p = subprocess.run(["python3", str(HERE / "faktaforslag_rettelse.py"), "flet", "--ud", str(tmp_path), "x.json"],
                       capture_output=True, text=True, cwd=HERE)
    assert p.returncode == 2 and "FF_FEJL ARK_FINDES" in p.stderr


def test_samlet_f_daekker_praecis_version_og_bind():
    kl, a, s, b, m = _opsaet()
    ma = fr.manifest_a(kl, a)
    sf = fr.samlet_f(kl, ma)
    assert sf["side"] == 1001 and sf["manifest_a"] == ma
    assert sf["kilde"] == "projektejeren 2026-11-07: samlet F på VERSION og BIND"
    assert sf["svar"] == {"p2-f1": "F", "p2-f2": "F"}
    ark = fr.flet_a(kl, ma, [sf, _sv(ma, 1, {"p1-f1": "N"})])
    assert ark.splitlines() == [f"# manifest_a {ma}", "A p1-f1 : N", "A p1-f2 : _", "A p2-f1 : F", "A p2-f2 : F"]


def test_flet_afviser_samlet_svar_paa_ret_og_bind():
    kl, a, s, b, m = _opsaet()
    ma = fr.manifest_a(kl, a)
    for fil in (_sv(ma, 1001, {"p1-f1": "F"}), _sv(ma, 1, {"p2-f1": "F"}), _sv(ma, 1, {"p2-f2": "F"})):
        with pytest.raises(fr.FaktaError) as e:
            fr.flet_a(kl, ma, [fil])
        assert e.value.kode == "SVAR_IKKE_TILLADT"


def test_cli_kort_samlet_f_flet(tmp_path):
    kl, a, s, b, m = _opsaet()
    ma = fr.manifest_a(kl, a)
    (tmp_path / "a-klasser.json").write_text(json.dumps({"manifest_a": ma, "klasser": kl}))
    (tmp_path / "samlet.json").write_text(json.dumps(s))
    (tmp_path / "input-1.json").write_text(json.dumps(b[0]))
    (tmp_path / "maal.json").write_text(json.dumps(m))

    def kor(*args):
        return subprocess.run(["python3", str(HERE / "faktaforslag_rettelse.py"), *args, ], capture_output=True,
                              text=True, cwd=HERE)
    p = kor("kort", "--ud", str(tmp_path))
    assert p.returncode == 0, p.stderr
    assert (os.stat(tmp_path / "kort-a" / "kort-1.html").st_mode & 0o777) == 0o600
    p = kor("samlet-f", "--ud", str(tmp_path))
    assert p.returncode == 0, p.stderr
    assert (os.stat(tmp_path / "svar-a-1001.json").st_mode & 0o777) == 0o600
    p = kor("flet", "--ud", str(tmp_path), str(tmp_path / "svar-a-1001.json"))
    assert p.returncode == 0, p.stderr
    assert re.match(r"^FF_FLET_OK( [a-z_0-9]+=[0-9a-f]+)+$", p.stdout.strip())
    assert "Tekst" not in p.stdout
    assert (os.stat(tmp_path / "ark-a.txt").st_mode & 0o777) == 0o600


def test_svarbare_kort_er_paa_side_1_i_ref_orden():
    kl, a, s, b, m = _opsaet()
    for i in range(100):   # langt flere rapport-refs end pr_side; sorterer både før og efter p1/p2
        ref = f"p{i % 3 + 1}-g{i:03d}"
        kl.append(_krk(ref, "RAPPORT", grund="BEGGE", iid=f"ix{i}"))
        a.append(_a4(ref))
    kl.append(_krk("p0-f9", "RET_OG_BIND", iid="iz"))
    a.append(_a4("p0-f9"))
    b[0]["poster"].append({"post": "p0", "tekst": "t", "sider": [], "forslag": []})
    m["forslag"].append({"interpretation_id": "iz", "version": 1, "status": "accepted",
                         "tidligere": {"status": "accepted", "grund": None},
                         "rettelse_maal": {"value_kind": "text", "forventet": {"vaerdi_tekst": "x"}}})
    k = fr.byg_kort(kl, {"A": a}, b, m)
    side1 = k[:40]
    ret = [x["ref"] for x in k if x.get("svarbar")]
    assert ret == ["p0-f9", "p1-f1", "p1-f2"] and [x["ref"] for x in side1 if x.get("svarbar")] == ret
    assert k[0]["type"] == "oversigt"
    assert all(x["type"] == "rapport" for x in k[4:])


def test_kort_kraever_tidligere_og_post():
    kl, a, s, b, m = _opsaet()
    m2 = copy.deepcopy(m)
    for f in m2["forslag"]:
        f["tidligere"] = None
    with pytest.raises(fr.FaktaError) as e:
        fr.byg_kort(kl, s, b, m2)
    assert e.value.kode == "MAAL_MANGLER"
    with pytest.raises(fr.FaktaError) as e:
        fr.byg_kort(kl, s, [{"udgave": "T", "poster": []}], m)
    assert e.value.kode == "POST_MANGLER"


def test_flet_afviser_forkert_svarform():
    kl, a, s, b, m = _opsaet()
    ma = fr.manifest_a(kl, a)
    for fil in (_sv(ma, 1, ["p1-f1"]), _sv(ma, 1, {"p1-f1": ["F"]}), _sv(ma, 1, {"p1-f1": {"x": 1}}),
                _sv(ma, 1, {"p1-f1": 1})):
        with pytest.raises(fr.FaktaError) as e:
            fr.flet_a(kl, ma, [fil])
        assert e.value.kode == "SVAR_UGYLDIGT"


def test_cli_kort_uden_bidder_fejler(tmp_path):
    kl, a, s, b, m = _opsaet()
    (tmp_path / "a-klasser.json").write_text(json.dumps({"manifest_a": fr.manifest_a(kl, a), "klasser": kl}))
    (tmp_path / "samlet.json").write_text(json.dumps(s))
    (tmp_path / "maal.json").write_text(json.dumps(m))
    p = subprocess.run(["python3", str(HERE / "faktaforslag_rettelse.py"), "kort", "--ud", str(tmp_path)],
                       capture_output=True, text=True, cwd=HERE)
    assert p.returncode == 2 and "FF_FEJL POST_MANGLER" in p.stderr


# --- Task 5: ceremoniens SQL (ren Python) -----------------------------------------------------------------------

T5_SRC = 3


def _uid(n: int) -> str:
    return f"13000000-0000-0000-0000-{n:012d}"


def _fv5(aid, vt=None, raw=None, ft="titel"):
    return {"fact_id": aid, "faktatype": ft, "vaerdi_tekst": vt, "date_raw": raw, "valgt_assertion_id": aid,
            "citation_sources": [T5_SRC]}


def _k5(ref, klasse, n, status, ny, felt="person.title", aid=None, fv=None, p_dato=None, grund=None):
    return {"ref": ref, "klasse": klasse, "grund": grund, "interpretation_id": _uid(n),
            "version": 1 if status == "proposed" else 2, "status": status, "ny_vaerdi": ny, "assertion_id": aid,
            "forventet": fv, "p_dato": p_dato, "ret_paastand": klasse == "RET_OG_BIND", "_felt": felt}


def _t5():
    kl = [_k5("p1-f1", "VERSION", 1, "proposed", "Carl O'Neill", felt="person.name"),
          _k5("p2-f1", "BIND", 2, "accepted", "kammerherre", aid=-71, fv=_fv5(-71, "kammerherre")),
          _k5("p2-f2", "BIND", 3, "rejected", "hofjægermester", aid=-72, fv=_fv5(-72, "Hofjægermester")),
          _k5("p3-f1", "RET_OG_BIND", 4, "accepted", "12. marts 1871", felt="person.death", aid=-73,
              fv=_fv5(-73, None, "1870", "død"), p_dato=fr.cm._p_dato("12. marts 1871")),
          _k5("p3-f2", "RET_OG_BIND", 5, "rejected", "Ole O'Brien", felt="person.name", aid=-74,
              fv=_fv5(-74, "Ole OBrien", None, "navn")),
          _k5("p3-f3", "RET_OG_BIND", 6, "unresolved", "lensgreve", aid=-75, fv=_fv5(-75, "greve")),
          _k5("p4-f1", "RAPPORT", 7, "proposed", None, grund="BEGGE")]
    felter = {k["ref"]: k.pop("_felt") for k in kl}
    ny = {k["ref"]: k["ny_vaerdi"] for k in kl}
    a = [{"ref": r, "svar": "FORSLAG_FEJL", "felt": f, "vaerdi": f"VAERDI-{r}",
          "bogens_laesning": ny[r] if ny[r] is not None else f"LAES-{r}",
          "billede": "bekraefter", "grund": "modellens grund"} for r, f in felter.items()]
    noegle = {k["ref"]: {"type": "forslag", "interpretation_id": k["interpretation_id"], "version": k["version"]}
              for k in kl}
    ma = fr.manifest_a(kl, a)
    ark = fr.flet_a(kl, ma, [fr.samlet_f(kl, ma), {"manifest_a": ma, "side": 1, "svar": {"p3-f1": "F", "p3-f2": "N"}}])
    return kl, {"A": a}, noegle, ark, ma


def _sql5(**kw):
    kl, s, n, ark, ma = _t5()
    an = fr.anvend_a(kl, s, n, ark)
    return fr.sql_a(an, source_id=T5_SRC, manifest_a=ma, ark_sha256="b" * 64, **kw)


def _blok(sql: str, needle: str, tag: str = r"t6m_\w+") -> str:
    bl = [m.group(0) for m in re.finditer(rf"DO (\${tag}\$).*?\1;", sql, re.S) if needle in m.group(0)]
    assert len(bl) == 1, (needle, len(bl))
    return bl[0]


def test_sql_a_raekkefoelge():
    sql = _sql5()
    b = _blok(sql, _uid(4), r"t6m_r\d+")
    i = [b.index(x) for x in ("public.red_ret_forslag(", "public.red_ret_paastand(", "public.red_decide_interpretation(")]
    assert i == sorted(i)
    assert "'bogen_har_ret'" in b and "'accepted'" in b and '"basis": "kort-6m-a"' in b
    v = _blok(sql, _uid(1), r"t6m_r\d+")
    assert "public.red_ret_forslag(" in v
    assert "red_ret_paastand" not in v and "red_decide_interpretation" not in v
    bi = _blok(sql, _uid(2), r"t6m_r\d+")
    assert "red_ret_paastand" not in bi and "public.red_decide_interpretation(" in bi
    # versionsfølgen: kortets version, så version+1 til afgørelsen
    assert f"public.red_ret_forslag('{_uid(4)}'::uuid, 2," in b and "red_decide_interpretation(ny, 3," in b
    # evidensen til red_ret_forslag bærer præcis T1's nøgler
    ev = json.loads(re.search(r"red_ret_forslag\([^,]+, \d+, '[^']*', '(\{[^']*\})'::jsonb\)", b).group(1))
    assert ev == {"basis": "menneske-laesning-v1", "manifest_a_sha256": _t5()[4], "ark_sha256": "b" * 64,
                  "ref": "p3-f1", "svar": "FORSLAG_FEJL", "billede": "bekraefter"}


def test_sql_a_nulstiller_change_set_foer_hvert_kald():
    sql = _sql5()
    rpc = re.findall(r"public\.red_\w+\(", sql)
    reset = re.findall(r"set_config\('app\.change_set_id','',true\)", sql)
    assert len(rpc) == len(reset) and len(rpc) == 4 + 3 + 1 + 2   # forslag×F + afgørelse×3 + rettelse×1 + preview/batch
    foran = re.findall(r"PERFORM set_config\('app\.change_set_id','',true\); [^;]*?public\.red_\w+\(", sql)
    assert len(foran) == len(rpc)


def test_sql_a_citerer_apostrof():
    sql = _sql5()
    assert "'Carl O''Neill'" in sql
    assert "O'Neill'" not in sql.replace("O''Neill'", "")


def test_sql_a_binder_genaabnet_accepted():
    sql = _sql5()
    scope = next(l for l in sql.splitlines() if "daa.transfer_scope" in l)
    for n in (2, 3, 4):
        assert _uid(n) in scope
    assert _uid(1) not in scope
    assert "T6M_BIND_COUNT % af 3'" in sql
    m = _blok(sql, "T6M_MAAL_MISMATCH")
    assert re.search(rf'\["{_uid(2)}", -71\]', m)
    # R9: bindinger før måles pr. nøgle over ALLE F-kort (også en accepted BIND uden gyldig binding), intet antages
    k = _blok(sql, "INSERT INTO private.extraction_run")
    a = json.loads(re.search(r"DECLARE a jsonb := '(\[[^']*\])'::jsonb", k).group(1))
    assert a == [_uid(n) for n in (1, 2, 3, 4)]
    assert "q.interpretation_key = card.interpretation_key" in k and "'foer_bundne_f', n_bund" in k
    assert "T6M_FOER_BINDING_AFVIGER" not in sql
    e = _blok(sql, "T6M_BINDINGER_AFVIGER")
    assert "(mf->>'foer_bindinger')::bigint - (mf->>'foer_bundne_f')::bigint + 3" in e


def test_sql_a_bruger_ikke_supersedes_id():
    assert "supersedes_id" not in _sql5()


def test_sql_a_drift_tjekker_bind_og_ret_og_bind():
    sql = _sql5()
    d = _blok(sql, "PAASTAND_DRIFT")
    for aid in (-71, -72, -73):
        assert re.search(rf'"assertion_id": {aid}\b', d)
    assert "-74" not in d and "-75" not in d
    k = _blok(sql, "FORSLAG_DRIFT kilde")
    for n in (1, 2, 3, 4):
        assert _uid(n) in k
    # driften kontrolleres før første skrivning
    assert sql.index("PAASTAND_DRIFT") < sql.index("INSERT INTO private.extraction_run") < sql.index("red_ret_forslag(")


def test_anvend_afviser_aendret_samlet():
    kl, s, n, ark, ma = _t5()
    s2 = copy.deepcopy(s)
    s2["A"][3]["bogens_laesning"] = "13. marts 1871"
    with pytest.raises(fr.FaktaError) as e:
        fr.anvend_a(kl, s2, n, ark)
    assert e.value.kode == "MANIFEST_MISMATCH"


def test_anvend_afviser_ark():
    kl, s, n, ark, ma = _t5()

    def kode(a, noegle=n):
        with pytest.raises(fr.FaktaError) as e:
            fr.anvend_a(kl, s, noegle, a)
        return e.value.kode
    assert kode(ark + "A p9-f9 : F\n") == "SVAR_UKENDT_REF"
    assert kode(ark + "A p4-f1 : F\n") == "SVAR_IKKE_TILLADT"
    assert kode(ark.replace("A p3-f1 : F", "A p3-f1 : X")) == "SVAR_UGYLDIGT"
    assert kode(ark + "A p3-f1 : N\n") == "SVAR_KONFLIKT"
    assert kode(ark.replace("A p3-f3 : _\n", "")) == "ARK_UGYLDIGT"
    n2 = copy.deepcopy(n)
    n2["p3-f1"]["version"] = 3
    assert kode(ark, n2) == "NOEGLE_MISMATCH"


def test_n_og_tomt_skrives_ikke():
    kl, s, n, ark, ma = _t5()
    an = fr.anvend_a(kl, s, n, ark)
    assert set(an) == {"version", "bind", "ret_og_bind"}
    assert [r["ref"] for r in an["version"]] == ["p1-f1"]
    assert [r["ref"] for r in an["bind"]] == ["p2-f1", "p2-f2"]
    assert [r["ref"] for r in an["ret_og_bind"]] == ["p3-f1"]
    sql = fr.sql_a(an, source_id=T5_SRC, manifest_a=ma, ark_sha256="b" * 64)
    for i in (5, 6, 7):
        assert _uid(i) not in sql
    assert "Ole O''Brien" not in sql and "lensgreve" not in sql
    assert "T6M_APPLY_A_OK versioner=4 rettelser=1 afgoerelser=3 bundet=3 sha256=" + "b" * 64 in sql


def test_sql_a_afviser_delt_kilde():
    kl, s, n, ark, ma = _t5()
    an = fr.anvend_a(kl, s, n, ark)
    an["ret_og_bind"][0]["forventet"]["citation_sources"] = [T5_SRC, 9]
    with pytest.raises(fr.FaktaError) as e:
        fr.sql_a(an, source_id=T5_SRC, manifest_a=ma, ark_sha256="b" * 64)
    assert e.value.kode == "KILDE_AFVIGER"


def test_verify_a_er_laese_kun():
    kl, s, n, ark, ma = _t5()
    v = fr.verify_a_sql(fr.anvend_a(kl, s, n, ark))
    kode = [l for l in v.splitlines() if l.strip()]
    assert kode[:4] == ["\\set ON_ERROR_STOP on", "\\set SHOW_CONTEXT never", "BEGIN;", "SET TRANSACTION READ ONLY;"]
    assert kode[-1] == "ROLLBACK;"
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT)\b|public\.red_", v)
    assert "T6M_VERIFY_A_OK" in v and "binding_value_matches" in v


def test_sql_skjuler_kontekst_og_raise_baerer_ingen_vaerdier():
    kl, s, n, ark, ma = _t5()
    an = fr.anvend_a(kl, s, n, ark)
    for sql in (fr.sql_a(an, source_id=T5_SRC, manifest_a=ma, ark_sha256="b" * 64), fr.verify_a_sql(an)):
        kode = [l for l in sql.splitlines() if l.strip()]
        assert kode[:3] == ["\\set ON_ERROR_STOP on", "\\set SHOW_CONTEXT never", "BEGIN;"]
        # RAISE-teksterne: kun koder, refs, kilde-id, antal og hashes; ingen værdi fra kortene
        for m in re.finditer(r"RAISE (?:EXCEPTION|NOTICE) '[^']*'(?:, [^;]*)?;", sql):
            for v in ("Neill", "kammerherre", "1871", "jægermester", "OBrien", "greve"):
                assert v not in m.group(0), m.group(0)


def test_sql_a_bindingsvaern_foer_foerste_skrivning():
    sql = _sql5()
    b = _blok(sql, "T6M_BINDING_ANDET_MAAL")
    m = json.loads(re.search(r"DECLARE m jsonb := '(\[[^']*\])'::jsonb", b).group(1))
    # alle F-rækker; VERSION uden påstand (enhver gyldig binding afvises), ellers rækkens påstand
    assert m == [[_uid(1), None], [_uid(2), -71], [_uid(3), -72], [_uid(4), -73]]
    assert "q.interpretation_key = card.interpretation_key" in b and "assertion_binding_current(p.id)" in b
    assert "p.target_id IS DISTINCT FROM (e->>1)::bigint" in b
    assert sql.index("PAASTAND_DRIFT") < sql.index("T6M_BINDING_ANDET_MAAL") < sql.index(
        "INSERT INTO private.extraction_run") < sql.index("red_ret_forslag(")


def test_anvend_afviser_vaerdi_der_ikke_er_kildens():
    def kode(kl, s, n, maal=None):
        ma = fr.manifest_a(kl, s["A"])
        ark = fr.flet_a(kl, ma, [fr.samlet_f(kl, ma), {"manifest_a": ma, "side": 1, "svar": {"p3-f1": "F"}}])
        with pytest.raises(fr.FaktaError) as e:
            fr.anvend_a(kl, s, n, ark, maal)
        return e.value.kode
    # FORSLAG_FEJL: ny_vaerdi skal være bogens læsning (afvigelsen bygget ind før manifest og flet)
    kl, s, n, ark, ma = _t5()
    kl[3]["ny_vaerdi"] = "13. marts 1871"
    assert kode(kl, s, n) == "VAERDI_AFVIGER"
    kl, s, n, ark, ma = _t5()
    s["A"][1]["bogens_laesning"] = None
    assert kode(kl, s, n) == "VAERDI_AFVIGER"
    # DB_FEJL: ny_vaerdi skal være forslagets værdi i mål-filen (blanktegn samlet)
    kl, s, n, ark, ma = _t5()
    s["A"][1]["svar"] = "DB_FEJL"
    s["A"][1]["bogens_laesning"] = "noget andet"
    maal = {"forslag": [{"interpretation_id": k["interpretation_id"], "value_text": k["ny_vaerdi"]} for k in kl]}
    ma = fr.manifest_a(kl, s["A"])
    ark = fr.flet_a(kl, ma, [fr.samlet_f(kl, ma), {"manifest_a": ma, "side": 1, "svar": {"p3-f1": "F"}}])
    maal["forslag"][1]["value_text"] = " kammerherre\n"
    assert [r["ref"] for r in fr.anvend_a(kl, s, n, ark, maal)["bind"]] == ["p2-f1", "p2-f2"]
    maal["forslag"][1]["value_text"] = "kammerjunker"
    assert kode(kl, s, n, maal) == "VAERDI_AFVIGER"
    maal["forslag"].pop(1)
    assert kode(kl, s, n, maal) == "MAAL_MANGLER"


def test_rapport_indeholder_ingen_vaerdier(tmp_path):
    kl, s, n, ark, ma = _t5()
    (tmp_path / "a-klasser.json").write_text(json.dumps({"manifest_a": ma, "klasser": kl}))
    (tmp_path / "samlet.json").write_text(json.dumps(s))
    (tmp_path / "noegle.json").write_text(json.dumps(n))
    (tmp_path / "ark-a.txt").write_text(ark)

    def kor(*extra):
        return subprocess.run(["python3", str(HERE / "faktaforslag_rettelse.py"), "sql", "--ud", str(tmp_path),
                               "--source-id", str(T5_SRC), *extra], capture_output=True, text=True, cwd=HERE)
    p = kor()
    assert p.returncode == 0, p.stderr
    assert re.fullmatch(r"FF_SQL_OK version=1 bind=2 ret_og_bind=1 sha256=[0-9a-f]{64}", p.stdout.strip())
    sha = p.stdout.strip().rsplit("=", 1)[1]
    import hashlib
    assert hashlib.sha256((tmp_path / "apply-a.sql").read_bytes()).hexdigest() == sha
    for f in ("apply-a.sql", "verify-a.sql", "rapport-a.json"):
        assert (os.stat(tmp_path / f).st_mode & 0o777) == 0o600
    txt = (tmp_path / "rapport-a.json").read_text()
    rap = json.loads(txt)

    def noegler(o):
        if isinstance(o, dict):
            return set(o) | set().union(*(noegler(v) for v in o.values()))
        if isinstance(o, list):
            return set().union(set(), *(noegler(v) for v in o))
        return set()
    assert not noegler(rap) & {"vaerdi", "bogens_laesning", "ny_vaerdi", "forventet", "p_dato", "databasen"}
    assert "VAERDI-" not in txt and "LAES-" not in txt and "O'Brien" not in txt and "lensgreve" not in txt
    assert [r["ref"] for r in rap["rapport"]] == ["p3-f2", "p3-f3", "p4-f1"]
    assert {r["ark"] for r in rap["rapport"]} == {"N", "_", None}
    assert "Neill" not in p.stdout + p.stderr
    # en anden kilde i maal.json afvises; en eksisterende apply-a.sql overskrives ikke
    (tmp_path / "maal.json").write_text(json.dumps({"source_id": 4, "forslag": []}))
    for f in ("apply-a.sql",):
        (tmp_path / f).unlink()
    p = kor()
    assert p.returncode == 2 and "FF_FEJL KILDE_MISMATCH" in p.stderr
    (tmp_path / "maal.json").unlink()
    assert kor().returncode == 0
    p = kor()
    assert p.returncode == 2 and "FF_FEJL SQL_FINDES" in p.stderr


# --- Task 5: apply-a.sql og verify-a.sql mod en lokal fixturebase ------------------------------------------------
# Egen base (t6m5_<tid>_<pid>), oprettet og droppet af testen selv. Én VERSION (proposed), én BIND (rejected, version 2)
# og én RET_OG_BIND (accepted med gyldig binding: genåbning under den udskudte kontrol). Kilde 1 har en binding
# (k1-hashen), og kilden har en uberørt binding (tælleregnestykket).

DB5 = f"t6m5_{time.strftime('%Y%m%d%H%M%S')}_{os.getpid()}"
S5, K15 = -6595, 1
RUN5, RUN51 = "14000000-0000-0000-0000-000000069901", "14000000-0000-0000-0000-000000069902"
ACT5 = "14000000-0000-0000-0000-000000069904"
P5 = {1: -65951, 2: -65952, 3: -65953, 4: -65954, 5: -65955, 9: -65959}
A5 = {2: -659502, 3: -659503, 4: -659504, 5: -659505, 9: -659509}


def _v(n: int) -> str:
    return f"14000000-0000-0000-0000-{n:012d}"


def _setup5() -> str:
    run = ("INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,"
           "input_sha256,manifest) VALUES ")
    s = (f"INSERT INTO auth.users(id,email) VALUES ('{ACT5}','t6m5@test.invalid');\n"
         f"INSERT INTO public.profiles(id,rolle,navn,email) VALUES ('{ACT5}','redaktion','t6m5','t6m5@test.invalid');\n"
         f"INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({S5},'Fixture 6m5','synthetic','1939',"
         f"'DAA-udgave'),({K15},'Fixture 2018-20','synthetic','2018','DAA-udgave');\n"
         + run + f"('{RUN5}',{S5},'t6m5-s','fixture','fixture','fixture',repeat('1',64),'{{}}'),"
         f"('{RUN51}',{K15},'t6m5-1','fixture','fixture','fixture',repeat('1',64),'{{}}');\n"
         "INSERT INTO public.person(id,levende,privat,status) VALUES "
         + ",".join(f"({p},false,false,'t6m5')" for p in P5.values()) + ";\n")
    for n in (1, 2, 3, 4, 5):
        s += t6._persona(_v(100 + n), S5, RUN5, f"t6m5:s{n}", P5[n])
    s += t6._persona(_v(109), K15, RUN51, "t6m5:k1", P5[9])
    s += t6._date_fact(P5[2], A5[2], "titel", "kammerherre", [S5], kind="text")
    s += t6._date_fact(P5[3], A5[3], "død", "1870", [S5])
    s += f"UPDATE public.assertion SET date_min='1870-01-01',date_max='1870-12-31' WHERE id={A5[3]};\n"
    s += t6._date_fact(P5[4], A5[4], "navn", "Anna Testlow", [S5], kind="text")
    s += t6._date_fact(P5[9], A5[9], "fødsel", "5. juni 1700", [K15])
    s += t6._date_fact(P5[5], A5[5], "titel", "hofjunker", [S5], kind="text")
    # BIND fra accepted UDEN gyldig binding (R9): værdien matcher målet, ingen promotion
    s += t6._interp(_v(405), _v(505), 1, S5, _v(105), "person.title", "hofjunker", RUN5, status="accepted")
    # VERSION: proposed version 1
    s += t6._interp(_v(401), _v(501), 1, S5, _v(101), "person.death", "1850", RUN5)
    # BIND: version 1 proposed, version 2 rejected (kortets række)
    s += t6._interp(_v(402), _v(502), 1, S5, _v(102), "person.title", "Kammerherre", RUN5)
    s += t6._interp(_v(412), _v(502), 2, S5, _v(102), "person.title", "Kammerherre", RUN5, status="rejected",
                    supersedes=_v(402))
    # RET_OG_BIND: accepted og gyldigt bundet til A5[3]; bogen siger 1871
    s += t6._interp(_v(403), _v(503), 1, S5, _v(103), "person.death", "1870", RUN5, status="accepted")
    s += t6._promo(_v(603), _v(403), "person-death-v1", "assertion", A5[3], '{"fixture":"t6m5"}')
    # uberørt binding i kilden og kilde 1's binding
    s += t6._interp(_v(404), _v(504), 1, S5, _v(104), "person.name", "Anna Testlow", RUN5, status="accepted")
    s += t6._promo(_v(604), _v(404), "person-name-v1", "assertion", A5[4], '{"fixture":"t6m5"}')
    s += t6._interp(_v(409), _v(509), 1, K15, _v(109), "person.birth", "5. juni 1700", RUN51, status="accepted")
    s += t6._promo(_v(609), _v(409), "person-birth-v1", "assertion", A5[9], '{"fixture":"t6m5"}')
    # kæden, promotionsvalideringen kræver: rendition, forekomst, post, accepteret anker, observation og kobling
    s += (f"INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256) "
          f"VALUES ('{_v(700)}',{S5},'t6m5','fixture',repeat('1',64));\n")
    for n, iids in ((1, (401,)), (2, (402, 412)), (3, (403,)), (5, (405,))):
        s += (f"INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) "
              f"VALUES ('{_v(710 + n)}',{S5},'t6m5:r{n}','fixture','{RUN5}');\n"
              f"INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,"
              f"char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES "
              f"('{_v(720 + n)}','{_v(700)}','o{n}',1,1,{n * 100},{n * 100 + 50},'tekst','f','f','{RUN5}');\n"
              f"INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,"
              f"version,decided_by,decided_by_name) VALUES ('{_v(720 + n)}','{_v(710 + n)}','accepted',"
              f"'{{\"fixture\":true}}',1,'{ACT5}','fixture');\n"
              f"INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,"
              f"char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES "
              f"('{_v(730 + n)}','{_v(720 + n)}','clause',1,1,{n * 100},{n * 100 + 50},'klausul','clear','fixture',"
              f"'{RUN5}');\n")
        for i in iids:
            s += (f"INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,"
                  f"ordinal) VALUES ('{_v(i)}','{_v(730 + n)}','supporting',1);\n")
    return s


@pytest.fixture(scope="module")
def db5():
    if shutil.which("psql") is None or subprocess.run(["psql", "-X", "-Atc", "select 1", "-d", "postgres"],
                                                      capture_output=True).returncode != 0:
        if os.environ.get("CI"):
            pytest.fail("PostgreSQL er ikke tilgaengelig i CI")
        pytest.skip("ingen lokal PostgreSQL")
    t6._must(subprocess.run(["createdb", DB5], capture_output=True, text=True), "createdb")
    try:
        for f in ("tests/sql/evidence-promotion-bootstrap.sql", "schema.sql", "db-rls.sql"):
            t6._must(t6._psql("-f", f, db=DB5), f)
        t6._sql(DB5, _setup5(), "setup5")
        yield DB5
    finally:
        subprocess.run(["dropdb", DB5], capture_output=True)  # kun basen, testen selv oprettede


def _q5(db: str, sql: str) -> str:
    return t6._must(t6._psql(db=db, stdin=sql), "forespørgsel").strip()


def _bundne5(db: str) -> list:
    return _q5(db, "SELECT string_agg(q.interpretation_key::text||':'||p.target_id, ',' ORDER BY p.target_id) "
                   "FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id "
                   f"WHERE q.source_id={S5} AND private.assertion_binding_current(p.id);").split(",")


def test_apply_a_ende_til_ende(db5, tmp_path):
    import hashlib
    kort = {"q1-f1": (_v(401), 1, "person.death", "1850", "1851"),
            "q2-f1": (_v(412), 2, "person.title", "Kammerherre", "kammerherre"),
            "q3-f1": (_v(403), 1, "person.death", "1870", "1871"),
            "q5-f1": (_v(405), 1, "person.title", "hofjunker", "hofjunker")}
    a = [{"ref": r, "svar": "FORSLAG_FEJL", "felt": f, "vaerdi": v, "bogens_laesning": b,
          "billede": "modsiger" if r == "q3-f1" else "bekraefter", "grund": "fixture"}
         for r, (_, _, f, v, b) in kort.items()]
    noegle = {r: {"type": "forslag", "interpretation_id": i, "version": ver} for r, (i, ver, *_) in kort.items()}
    maal = _maal_db(db5, [i for i, *_ in kort.values()])
    kl = fr.klassificer(a, noegle, maal)
    assert {k["ref"]: (k["klasse"], k["status"]) for k in kl} == {
        "q1-f1": ("VERSION", "proposed"), "q2-f1": ("BIND", "rejected"), "q3-f1": ("RET_OG_BIND", "accepted"),
        "q5-f1": ("BIND", "accepted")}
    ma = fr.manifest_a(kl, a)
    ark = fr.flet_a(kl, ma, [fr.samlet_f(kl, ma), {"manifest_a": ma, "side": 1, "svar": {"q3-f1": "F"}}])
    ark_sha = hashlib.sha256(ark.encode()).hexdigest()
    an = fr.anvend_a(kl, {"A": a}, noegle, ark)
    apply = tmp_path / "apply-a.sql"
    apply.write_text(fr.sql_a(an, source_id=S5, manifest_a=ma, ark_sha256=ark_sha))
    verify = tmp_path / "verify-a.sql"
    verify.write_text(fr.verify_a_sql(an))

    def kor(f):
        return t6._psql("-v", f"actor={ACT5}", "-f", str(f), db=db5)
    foer = _bundne5(db5)
    assert foer == [f"{_v(504)}:{A5[4]}", f"{_v(503)}:{A5[3]}"]
    tael = "SELECT count(*) FROM private.interpretation;"
    n0 = _q5(db5, tael)

    # påstandsdrift på BIND-målet: intet skrives
    _q5(db5, f"UPDATE public.assertion SET vaerdi_tekst='hofjægermester' WHERE id={A5[2]};")
    r = kor(apply)
    assert r.returncode != 0 and "PAASTAND_DRIFT" in r.stderr, r.stderr[-800:]
    _q5(db5, f"UPDATE public.assertion SET vaerdi_tekst='kammerherre' WHERE id={A5[2]};")
    assert _q5(db5, tael) == n0

    # hovedvejen
    r = kor(apply)
    assert r.returncode == 0, r.stderr[-1500:]
    assert r.stdout.strip().splitlines()[-1] == \
        f"T6M_APPLY_A_OK versioner=4 rettelser=1 afgoerelser=3 bundet=3 sha256={ark_sha}"
    # før 2 (503, 504); foer_bundne_f målt 1 (kun 503; 505 var accepted men ubundet) → 2 − 1 + 3 = 4
    assert "T6M_VERIFY_A_OK versioner=4 rettelser=1 afgoerelser=3 bundet=3 bindinger_k=4" in r.stderr
    assert _q5(db5, "SELECT manifest->>'foer_bindinger'||'|'||(manifest->>'foer_bundne_f') FROM private.extraction_run "
                    f"WHERE source_id={S5} AND run_key LIKE 'menneske-laesning-v1:%';") == "2|1"
    assert sorted(_bundne5(db5)) == sorted([f"{_v(504)}:{A5[4]}", f"{_v(503)}:{A5[3]}", f"{_v(502)}:{A5[2]}",
                                            f"{_v(505)}:{A5[5]}"])
    assert _q5(db5, f"SELECT date_raw||'|'||date_min||'|'||date_max FROM public.assertion WHERE id={A5[3]};") == \
        "1871|1871-01-01|1871-12-31"
    assert _q5(db5, "SELECT string_agg(interpretation_key::text||':'||version||':'||status||':'||(value#>>'{}'), ',' "
                    f"ORDER BY interpretation_key) FROM private.interpretation_current WHERE interpretation_key IN "
                    f"('{_v(501)}','{_v(502)}','{_v(503)}','{_v(505)}');") == \
        (f"{_v(501)}:2:proposed:1851,{_v(502)}:4:accepted:kammerherre,{_v(503)}:3:accepted:1871,"
         f"{_v(505)}:3:accepted:hofjunker")
    assert _q5(db5, tael) == str(int(n0) + 7)

    # verify-a.sql (læse-kun) er grøn, og bindinger_k/k1-hashen er maal_trin6c2.sql's
    r = kor(verify)
    assert r.returncode == 0, r.stderr[-1500:]
    m = re.search(r"T6M_VERIFY_A_OK .* bindinger_k=(\d+) k1_bindinger_hash=([0-9a-f]{64}) vejb=t", r.stderr)
    assert m, r.stderr[-800:]
    mt = t6._must(t6._psql("-v", f"source_id={S5}", "-v", f"k1_source_id={K15}", "-f", str(t6.MAAL), db=db5), "maal")
    assert f"bindinger_k={m.group(1)} " in mt and mt.strip().endswith(f"k1_bindinger_hash={m.group(2)}"), mt

    # en genkørsel afvises før første skrivning (kortenes rækker er ikke længere gældende)
    r = kor(apply)
    assert r.returncode != 0 and "FORSLAG_DRIFT" in r.stderr
    assert _q5(db5, tael) == str(int(n0) + 7)


# Binding på andet mål: nøglen er gyldigt bundet (fra 6c-2, valgt efter værdi) til påstand X, der også citeres af en
# anden kilde, mens rettelse_maal er Y (den eneste påstand citeret af kilden alene). Egen kilde (S6), så
# ende-til-ende-testens tal for S5 er uberørte.
S6, P6, X6, Y6 = -6596, -65966, -659661, -659662
RUN6 = _v(846)


def _setup6() -> str:
    s = (f"INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({S6},'Fixture 6m6','synthetic','1939',"
         f"'DAA-udgave');\n"
         "INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,"
         f"input_sha256,manifest) VALUES ('{RUN6}',{S6},'t6m6-s','fixture','fixture','fixture',repeat('1',64),'{{}}');\n"
         f"INSERT INTO public.person(id,levende,privat,status) VALUES ({P6},false,false,'t6m6');\n")
    s += t6._persona(_v(806), S6, RUN6, "t6m6:s1", P6)
    s += t6._date_fact(P6, X6, "titel", "kammerjunker", [S6, K15], kind="text")
    s += t6._date_fact(P6, Y6, "titel", "hofjunker", [S6], kind="text")
    s += t6._interp(_v(816), _v(826), 1, S6, _v(806), "person.title", "kammerjunker", RUN6, status="accepted")
    s += t6._promo(_v(836), _v(816), "person-title-v1", "assertion", X6, '{"fixture":"t6m6"}')
    # hele kæden, promotionsvalideringen kræver: uden bindingsværnet ville ceremonien nå COMMIT
    s += (f"INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256) "
          f"VALUES ('{_v(706)}',{S6},'t6m6','fixture',repeat('1',64));\n"
          f"INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) "
          f"VALUES ('{_v(716)}',{S6},'t6m6:r1','fixture','{RUN6}');\n"
          f"INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,"
          f"char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES "
          f"('{_v(726)}','{_v(706)}','o1',1,1,100,150,'tekst','f','f','{RUN6}');\n"
          f"INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,"
          f"version,decided_by,decided_by_name) VALUES ('{_v(726)}','{_v(716)}','accepted',"
          f"'{{\"fixture\":true}}',1,'{ACT5}','fixture');\n"
          f"INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,"
          f"char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES "
          f"('{_v(736)}','{_v(726)}','clause',1,1,100,150,'klausul','clear','fixture','{RUN6}');\n"
          f"INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) "
          f"VALUES ('{_v(816)}','{_v(736)}','supporting',1);\n")
    return s


def test_binding_paa_andet_maal_spaerres_og_afvises_i_sql(db5, tmp_path):
    import hashlib
    t6._sql(db5, _setup6(), "setup6")
    ref, iid = "q6-f1", _v(816)
    a = [{"ref": ref, "svar": "FORSLAG_FEJL", "felt": "person.title", "vaerdi": "kammerjunker",
          "bogens_laesning": "jægermester", "billede": "modsiger", "grund": "fixture"}]
    noegle = {ref: {"type": "forslag", "interpretation_id": iid, "version": 1}}
    maal = json.loads(_kor(db5, MAAL_SQL, f"SET daa.faktaforslag_ids = '{json.dumps([iid])}';\n", f"src={S6}"))
    f = maal["forslag"][0]
    assert f["egen_binding"] == {"promotion_id": _v(836), "gyldig": True, "target_id": X6}
    assert f["rettelse_maal"]["assertion_id"] == Y6 and f["maal_bundet_af_anden"] is False
    kl = fr.klassificer(a, noegle, maal)
    assert [(k["klasse"], k["grund"]) for k in kl] == [("SPAERRET", "binding_paa_andet_maal")]

    # et håndlavet ark, der springer klassifikationen over (RET_OG_BIND på Y), afvises før første skrivning
    k = {**kl[0], "klasse": "RET_OG_BIND", "grund": None, "assertion_id": Y6,
         "forventet": f["rettelse_maal"]["forventet"], "p_dato": None, "ret_paastand": True}
    ma = fr.manifest_a([k], a)
    ark = fr.flet_a([k], ma, [{"manifest_a": ma, "side": 1, "svar": {ref: "F"}}])
    an = fr.anvend_a([k], {"A": a}, noegle, ark, maal)
    apply = tmp_path / "apply-a.sql"
    apply.write_text(fr.sql_a(an, source_id=S6, manifest_a=ma, ark_sha256=hashlib.sha256(ark.encode()).hexdigest()))
    tael = ("SELECT (SELECT count(*) FROM private.interpretation)||'|'||(SELECT count(*) FROM private.extraction_run "
            f"WHERE source_id={S6})||'|'||(SELECT vaerdi_tekst FROM public.assertion WHERE id={Y6})")
    n0 = _q5(db5, tael + ";")
    r = t6._psql("-v", f"actor={ACT5}", "-f", str(apply), db=db5)
    assert r.returncode != 0 and "T6M_BINDING_ANDET_MAAL afvigende=1" in r.stderr, r.stderr[-800:]
    assert "CONTEXT" not in r.stderr and "jægermester" not in r.stderr
    assert _q5(db5, tael + ";") == n0 == f"{n0.split('|')[0]}|1|hofjunker"
    assert _q5(db5, f"SELECT private.assertion_binding_current('{_v(836)}');") == "t"


def _maal_db(db: str, ids: list[str]) -> dict:
    pre = f"SET daa.faktaforslag_ids = '{json.dumps(ids)}';\n"
    return json.loads(_kor(db, MAAL_SQL, pre, f"src={S5}"))
