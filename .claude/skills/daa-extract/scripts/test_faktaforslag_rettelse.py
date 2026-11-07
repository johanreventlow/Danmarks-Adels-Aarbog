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
    assert eb == {"promotion_id": _u(615), "gyldig": True}


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
        pred="person.name", vk="text", bundet=False, eb=None, med_maal=True):
    rm = {"assertion_id": 77, "forventet": {"fact_id": 5, "faktatype": "x", "vaerdi_tekst": maal_v, "date_raw": maal_v,
                                           "valgt_assertion_id": 77, "citation_sources": []},
          "graenser": None, "value_kind": vk} if med_maal else None
    return {"interpretation_id": iid, "status": status, "gaeldende_id": gid or iid, "kind": kind, "predicate": pred,
            "value_text": value, "rettelse_maal": rm, "maal_bundet_af_anden": bundet, "egen_binding": eb}


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
    r = _kl(_ar(), _fx(status="accepted", eb={"promotion_id": 1, "gyldig": True}))
    assert (r["klasse"], r["grund"]) == ("RAPPORT", "ALLEREDE_BUNDET")


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
    maal = {"forslag": [{"interpretation_id": r["interpretation_id"],
                         "tidligere": ({"status": "rejected", "grund": "fordi gammel afgørelse",
                                        "decided_at": "2026-01-01"} if r["ref"] == "p1-f1" else None),
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
    assert rk["databasen"] == "DBVAERDI" and rk["bogens_laesning"] == "Ny" and rk["vaerdi"] == "Forslag"
    assert rk["sider"] == ["../sider/sp1.png"] and "Tekst for p1" in rk["tekst"]
    h = _html(kl, a, s, b, m)
    assert "afvist" in h and "fordi gammel afgørelse" in h and "retter databasens værdi" in h


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
