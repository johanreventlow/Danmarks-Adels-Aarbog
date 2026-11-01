"""Trin 6c-1 Task 6: maalingen maal_trin6c1.sql, koert mod en lokal fixturebase (foer -> a -> b, hash stabil).

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; basen oprettes og droppes af testen (t6c1_t6_<pid>).
Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true) fejler den. Alt er syntetisk, og maalingen
viser kun taal og hashes. Fixturen skriver direkte (session_replication_role=replica) i stedet for gennem writeren.
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
MAAL = SCRIPTS / "maal_trin6c1.sql"
SRC = -6310
DB = f"t6c1_t6_{os.getpid()}"
RUN = "11000000-0000-0000-0000-00000006c101"
RUN1 = "11000000-0000-0000-0000-00000006c102"
LINE = re.compile(r"T6C1_MAAL tilstand=(foer|a|b|c) forslag_k3=(\d+) poster_k3=(\d+) identiteter_k3=(\d+) "
                  r"afventer=(\d+) k1_forslag_hash=([0-9a-f]{64})")


def _psql(*args: str, db: str | None = None, stdin: str | None = None) -> subprocess.CompletedProcess:
    cmd = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"] + (["-d", db] if db else []) + list(args)
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=ROOT)


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


_SETUP = f"""
\\set ON_ERROR_STOP on
SET session_replication_role = replica;
INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({SRC},'Fixture 6c1','synthetic','1900','DAA-udgave'),
                                                           (1,'Fixture 2018-20','synthetic','2018','DAA-udgave');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES ('{RUN}',{SRC},'t6-run','fixture','fixture','fixture',repeat('1',64),'{{}}'),
         ('{RUN1}',1,'t6-run1','fixture','fixture','fixture',repeat('1',64),'{{}}');
-- kilde 1: et forslag, saa k1_forslag_hash er maalbar
INSERT INTO private.interpretation(interpretation_key,version,source_id,interpretation_kind,predicate,value,schema_version,
  derivation_kind,confidence,status,method,extraction_run_id)
  VALUES ('11000000-0000-0000-0000-00000006c1a1',1,1,'property','fixture.predicate','{{"v":1}}','fixture','deterministic',1,
          'proposed','fixture','{RUN1}');
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES
  ('11000000-0000-0000-0000-00000006c1b1',{SRC},'t6:p1','{RUN}');
"""

def _rewrite_writer(db, *, strip: bool) -> None:
    """strip=True: fjern navnet fra funktionskroppen (simulerer 'foer'); strip=False: gendan fra schema.sql."""
    if strip:
        sql = ("DO $d$ DECLARE r record; BEGIN FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
               "WHERE n.nspname='private' AND p.proname='write_interpretation_proposal' LOOP "
               "EXECUTE replace(pg_get_functiondef(r.oid),'record_helpost_observation','record_helpost_obs_gammel'); "
               "END LOOP; END $d$")
        _must(_psql("-c", sql, db=db), "strip")
    else:
        sql = ("DO $d$ DECLARE r record; BEGIN FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
               "WHERE n.nspname='private' AND p.proname='write_interpretation_proposal' LOOP "
               "EXECUTE replace(pg_get_functiondef(r.oid),'record_helpost_obs_gammel','record_helpost_observation'); "
               "END LOOP; END $d$")
        _must(_psql("-c", sql, db=db), "restore")


def _add_proposals(db) -> None:
    _must(_psql(db=db, stdin=f"""
SET session_replication_role = replica;
INSERT INTO private.interpretation(interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,
  schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  VALUES ('11000000-0000-0000-0000-00000006c1c1',1,{SRC},'11000000-0000-0000-0000-00000006c1b1','property','fixture.predicate',
          '{{"v":1}}','fixture','deterministic',1,'proposed','fixture','{RUN}'),
         ('11000000-0000-0000-0000-00000006c1c2',1,{SRC},NULL,'property','fixture.predicate','{{"v":2}}','fixture',
          'deterministic',1,'proposed','fixture','{RUN}');
-- profil og autorisation udelades: FK'erne springes over under replica-rollen
-- e1: finaliseret (taeller); e0: aaben, dvs. ikke gennemfoert (taeller ikke, fund F9)
INSERT INTO private.reimport_batch(id,authorization_id,manifest_sha256,preview_sha256,principal_id,status,expected_counts,source_id,profile_id,profile_sha256)
  VALUES ('11000000-0000-0000-0000-00000006c1e1',gen_random_uuid(),repeat('b',64),repeat('c',64),gen_random_uuid(),'finalized','{{}}',{SRC},'fx-prop',repeat('a',64)),
         ('11000000-0000-0000-0000-00000006c1e0',gen_random_uuid(),repeat('b',64),repeat('c',64),gen_random_uuid(),'open','{{}}',{SRC},'fx-prop',repeat('a',64));
INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
  VALUES ('11000000-0000-0000-0000-00000006c1e1','e1','interpretation_proposal','r1','{{}}',repeat('d',64)),
         ('11000000-0000-0000-0000-00000006c1e1','e2','interpretation_proposal','r1','{{}}',repeat('d',64)),
         ('11000000-0000-0000-0000-00000006c1e1','e3','interpretation_proposal','r2','{{}}',repeat('d',64)),
         ('11000000-0000-0000-0000-00000006c1e0','e1','interpretation_proposal','r3','{{}}',repeat('d',64));
"""), "forslag")


def test_foer_a_b_og_hashen_er_stabil(db):
    # maalingen bruger source_id=3 som default; fixturens kilde er negativ, saa vi giver den eksplicit
    def m():
        out = _must(_psql("-v", f"source_id={SRC}", "-f", str(MAAL), db=db), "maal").strip()
        assert "\n" not in out, out
        g = LINE.fullmatch(out)
        assert g, out
        return g.groups()

    _rewrite_writer(db, strip=True)
    foer = m()
    assert foer[0] == "foer"
    _rewrite_writer(db, strip=False)
    a = m()
    assert a[:5] == ("a", "0", "0", "0", a[4]) and a[5] == foer[5]
    _add_proposals(db)
    b = m()
    assert b[0] == "b" and b[1] == "2" and b[2] == "2"
    assert b[3] == "0"
    # kilde 1 er uroert af kilde 3's forslag, og hashen er stabil over to koersler
    assert b[5] == a[5] == foer[5] and m() == b
    assert re.fullmatch(r"[0-9a-f]{64}", b[5]) and b[5] != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


def test_hash_aendres_naar_kilde_1_aendres(db):
    h0 = _must(_psql("-v", f"source_id={SRC}", "-f", str(MAAL), db=db), "maal").split("k1_forslag_hash=")[1].strip()
    _must(_psql("-c", "SET session_replication_role=replica; INSERT INTO private.interpretation(interpretation_key,version,"
                      "source_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,"
                      f"extraction_run_id) VALUES (gen_random_uuid(),1,1,'property','fixture.predicate','{{\"v\":9}}','fixture',"
                      f"'deterministic',1,'proposed','fixture','{RUN1}')", db=db), "k1")
    h1 = _must(_psql("-v", f"source_id={SRC}", "-f", str(MAAL), db=db), "maal").split("k1_forslag_hash=")[1].strip()
    assert h1 != h0


def test_sql_er_laese_kun_og_viser_ingen_tekst():
    sql = MAAL.read_text(encoding="utf-8")
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    assert not re.search(r"\b(INSERT|UPDATE|DELETE)\s", re.sub(r"--[^\n]*", "", sql))


def _maal(db) -> tuple:
    out = _must(_psql("-v", f"source_id={SRC}", "-f", str(MAAL), db=db), "maal").strip()
    g = LINE.fullmatch(out)
    assert g, out
    return g.groups()


def _ident_batch(db, batch_id: str, status: str, profile_id: str) -> None:
    _must(_psql(db=db, stdin=f"""
SET session_replication_role = replica;
INSERT INTO private.reimport_batch(id,authorization_id,manifest_sha256,preview_sha256,principal_id,status,expected_counts,source_id,profile_id,profile_sha256)
  VALUES ('{batch_id}',gen_random_uuid(),repeat('b',64),repeat('c',64),gen_random_uuid(),'{status}','{{}}',{SRC},'{profile_id}',repeat('a',64));
INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
  VALUES ('{batch_id}','i1','publication_identity','r1','{{}}',repeat('d',64));
"""), "ident-batch")


def test_c_kraever_finaliseret_publication_identity_batch_med_publikationsprofilen(db):
    """Fund F9 (final-review): c kræver en finaliseret/aktiveret batch med profilen daa-1939-publication-v1 og
    en publication_identity-hændelse. En åben batch eller en anden profil giver ikke c. Kører efter b-testen
    (modulets base har forslag, så udgangspunktet er b)."""
    assert _maal(db)[0] == "b"
    _ident_batch(db, "11000000-0000-0000-0000-00000006c1f1", "open", "daa-1939-publication-v1")
    assert _maal(db)[0] == "b"
    _ident_batch(db, "11000000-0000-0000-0000-00000006c1f2", "finalized", "en-anden-profil")
    assert _maal(db)[0] == "b"
    _ident_batch(db, "11000000-0000-0000-0000-00000006c1f3", "activated", "daa-1939-publication-v1")
    c = _maal(db)
    assert c[0] == "c"
    # publication_identity-hændelser er ikke forslag: poster_k3 er uændret
    assert c[2] == "2"
