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
