"""Trin 6d-1 Task 7: maalingen maal_trin6d1.sql, koert mod en lokal fixturebase (foer -> ddl -> data, hashes stabile).

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; basen oprettes og droppes af testen (t6d1_t7_maal_<pid>).
Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true) fejler den. Alt er syntetisk, og maalingen
viser kun tal og hashes. Fixturen skriver direkte (session_replication_role=replica) i stedet for gennem writerne.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parents[3]
MAAL = SCRIPTS / "maal_trin6d1.sql"
CEREMONI = SCRIPTS / "placement_ceremoni.sql"
SRC = -6410
ANDEN = -6411
DB = f"t6d1_t7_maal_{os.getpid()}"
RUN = "11000000-0000-0000-0000-00000006d101"
LINE = re.compile(r"T6D1_MAAL fase=(foer|ddl|data) entries=(\d+) placements=(\d+) persona=(\d+) ledger_mapped=(\d+) "
                  r"ledger_retained=(\d+) memberships=(\d+) published=(\d+) stale=(\d+) corroborated=(\d+|na) "
                  r"conflict=(\d+|na) KOORD_2018_20=([0-9a-f]{32}) KOORD_SRC=([0-9a-f]{32})")
FELTER = ("fase", "entries", "placements", "persona", "ledger_mapped", "ledger_retained", "memberships", "published",
          "stale", "corroborated", "conflict", "koord", "koord_src")


def _psql(*args: str, db: str | None = None, stdin: str | None = None) -> subprocess.CompletedProcess:
    cmd = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"] + (["-d", db] if db else []) + list(args)
    env = {k: v for k, v in os.environ.items() if k != "PGOPTIONS"}
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=ROOT, env=env)


def _must(proc: subprocess.CompletedProcess, what: str) -> str:
    assert proc.returncode == 0, f"{what} fejlede: {proc.stderr[-1500:]}"
    return proc.stdout


@pytest.fixture(scope="module")
def db():
    if shutil.which("psql") is None or subprocess.run(["psql", "-X", "-Atc", "select 1", "-d", "postgres"],
                                                      capture_output=True).returncode != 0:
        if os.environ.get("CI"):
            pytest.fail("PostgreSQL er ikke tilgaengelig i CI")
        pytest.skip("ingen lokal PostgreSQL")
    _must(subprocess.run(["createdb", DB], capture_output=True, text=True), "createdb")
    try:
        for f in ("tests/sql/evidence-promotion-bootstrap.sql", "schema.sql", "db-rls.sql"):
            _must(_psql("-f", f, db=DB), f)
        _must(_psql(db=DB, stdin=_SETUP), "setup")
        yield DB
    finally:
        subprocess.run(["dropdb", "--if-exists", DB], capture_output=True)


# To kilder med hver to personer (kun legacy-rækker), kildens stamtavle-schema med én entry og én record.
_SETUP = f"""
\\set ON_ERROR_STOP on
SET session_replication_role = replica;
INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({SRC},'Fixture 6d1','synthetic','1900','DAA-udgave'),
                                                           ({ANDEN},'Fixture 6d1 anden','synthetic','2018','DAA-udgave');
INSERT INTO public.person(id) VALUES (-641001),(-641002),(-641101),(-641102);
INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES
  (-641001,{SRC},'I',1,'a1'),(-641002,{SRC},'I',2,'a2'),(-641101,{ANDEN},'I',1,'b1'),(-641102,{ANDEN},'II',1,'b2');
INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug,status) VALUES (-6410,'Fixture','Fixture','f6d1-maal','active');
INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES (-6410,-6410,{SRC},'stamtavle','fixture');
INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES (-6410,-6410,-6410,'I','I',1);
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES ('{RUN}',{SRC},'t7-run','fixture','fixture','fixture',repeat('1',64),'{{}}');
INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
  VALUES ('11000000-0000-0000-0000-00000006d1a1',{SRC},'a1','person_post','{RUN}');
"""


def _maal(db) -> dict[str, str]:
    out = _must(_psql("-v", f"src={SRC}", "-f", str(MAAL), db=db), "maal").strip()
    assert "\n" not in out, out
    g = LINE.fullmatch(out)
    assert g, out
    return dict(zip(FELTER, g.groups()))


def _komponent_ddl(db, *, fjern: bool) -> None:
    """fjern=True: omdoeb membership_component_states (simulerer 'foer'); fjern=False: gendan."""
    a, b = ("membership_component_states", "membership_component_states_t7") if fjern else \
        ("membership_component_states_t7", "membership_component_states")
    _must(_psql("-c", f"ALTER FUNCTION private.{a}() RENAME TO {b}", db=db), "omdoeb")


def _placement(db) -> None:
    _must(_psql(db=db, stdin="""
SET session_replication_role = replica;
INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status,
  printed_number) VALUES ('11000000-0000-0000-0000-00000006d1b1','11000000-0000-0000-0000-00000006d1a1',-6410,
  '11000000-0000-0000-0000-00000006d1c1','accepted','1');
INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
  VALUES ('11000000-0000-0000-0000-00000006d1b1',1,'accepted','{"fixture":"t7"}','migration','fixture');
"""), "placement")


def test_foer_ddl_data_og_koordinaterne_er_stabile(db):
    _komponent_ddl(db, fjern=True)
    foer = _maal(db)
    assert foer["fase"] == "foer" and foer["corroborated"] == "na" and foer["conflict"] == "na"
    _komponent_ddl(db, fjern=False)
    ddl = _maal(db)
    assert ddl["fase"] == "ddl" and ddl["entries"] == "1" and ddl["placements"] == "0"
    assert ddl["corroborated"] == "0" and ddl["conflict"] == "0"
    _placement(db)
    data = _maal(db)
    assert data["fase"] == "data" and data["placements"] == "1"
    # runnerens stopregel: KOORD_2018_20 i ddl og data = foer; kildens egne rækker er ogsaa uroerte her
    assert foer["koord"] == ddl["koord"] == data["koord"]
    assert foer["koord_src"] == ddl["koord_src"] == data["koord_src"]
    assert foer["koord"] != foer["koord_src"] and _maal(db) == data


def test_koord_adskiller_kilden_fra_de_andre(db):
    h0 = _maal(db)
    _must(_psql("-c", f"UPDATE public.person_external_id SET nr=nr+10 WHERE person_id=-641102 AND source_id={ANDEN}",
                db=db), "anden")
    h1 = _maal(db)
    assert h1["koord"] != h0["koord"] and h1["koord_src"] == h0["koord_src"]
    _must(_psql("-c", f"UPDATE public.person_external_id SET nr=nr+10 WHERE person_id=-641002 AND source_id={SRC}",
                db=db), "kilde")
    h2 = _maal(db)
    assert h2["koord"] == h1["koord"] and h2["koord_src"] != h1["koord_src"]


def test_sql_er_laese_kun_og_viser_ingen_tekst():
    sql = MAAL.read_text(encoding="utf-8")
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    assert not re.search(r"\b(INSERT|UPDATE|DELETE)\s", re.sub(r"--[^\n]*", "", sql))


def _koord_udtryk(sql: str) -> str:
    """Koordinat-hashens udtryk (fra md5( til ORDER BY-ledet), uden mellemrum."""
    m = re.search(r"md5\(coalesce\(string_agg\(concat_ws\(.*?ORDER BY c\.person_id,c\.source_id\)", sql, re.S)
    assert m, "koordinat-hashen mangler"
    return re.sub(r"\s+", "", m.group(0))


def test_koordinat_hashen_er_den_samme_som_ceremoniens():
    """KOORD_2018_20 fra fase foer sammenlignes med ceremoniens efterbetingelse: udtrykkene skal vaere ens."""
    assert _koord_udtryk(MAAL.read_text(encoding="utf-8")) == _koord_udtryk(CEREMONI.read_text(encoding="utf-8"))
