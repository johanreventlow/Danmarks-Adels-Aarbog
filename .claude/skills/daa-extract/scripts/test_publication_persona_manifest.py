"""Trin 6b Task 11: manifest og maaling for 1939's personas, koert mod en lokal fixturebase.

Kraever en PostgreSQL 17 (PG*-miljoevariabler, som de oevrige pg-jobs) og psql. Basen oprettes og droppes af testen
(t6b_11_<pid>). Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true) fejler den.
Alt er syntetisk (tests/sql/fixtures/publication-persona.sql); hverken manifest eller maaling viser tekst.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parents[3]
MANIFEST = SCRIPTS / "publication_persona_manifest.sql"
MAAL = SCRIPTS / "maal_trin6b.sql"
SRC, PROFILE, ACTOR = -6210, "fixture-pub-a", "11000000-0000-0000-0000-00000006b2ff"
DB = f"t6b_11_{os.getpid()}"


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
        for f in ("tests/sql/evidence-promotion-bootstrap.sql", "schema.sql", "db-rls.sql",
                  "tests/sql/1939-v50-writer-bootstrap.sql"):
            _must(_psql("-f", f, db=DB), f)
        _must(_psql("-c", "BEGIN", "-f", "tests/sql/reimport-writer-v2-bootstrap.sql", "-c", "COMMIT", db=DB), "v2")
        _must(_psql("-f", "db-rls.sql", db=DB), "db-rls")
        _must(_psql(db=DB, stdin=_SETUP), "setup")
        yield DB
    finally:
        subprocess.run(["dropdb", "--if-exists", DB], capture_output=True)


_SETUP = f"""
\\set ON_ERROR_STOP on
\\i tests/sql/fixtures/publication-persona.sql
DO $s$
DECLARE v jsonb:=pg_temp.pp_source({SRC},'{ACTOR}'); a jsonb; b jsonb; c jsonb; d jsonb; e jsonb; r uuid;
BEGIN
  a:=pg_temp.pp_post(v,'p1',-621101);
  b:=pg_temp.pp_post(v,'p2',-621102,'{{"subs":2}}');
  c:=pg_temp.pp_post(v,'p3',-621103);
  UPDATE public.person SET staged=true WHERE id=-621103;
  d:=pg_temp.pp_post(v,'p4',-621104,'{{"binding":"draft"}}');   -- helpost uden publiceret binding
  e:=pg_temp.pp_post(v,'p5',-621105);                           -- har allerede en persona
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES ({SRC},'1939:p5',(v->>'run')::uuid)
    RETURNING id INTO r;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
    VALUES (r,(e->>'mention')::uuid,'primary',1);
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES ({SRC},'p6','structural_context',(v->>'run')::uuid);
  -- kilde 1 (2018-20) med en persona og en identitet, så k1_hash er målbar
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES (1,'Fixture 2018-20','synthetic','2018','DAA-udgave');
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES ('11000000-0000-0000-0000-00000006b2a1',1,'k1-run','fixture','fixture','fixture',repeat('1',64),'{{}}');
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (1,'k1a','11000000-0000-0000-0000-00000006b2a1')
    RETURNING id INTO r;
  INSERT INTO private.source_persona_identity_event(source_persona_id,decision_status,version,evidence) VALUES (r,'proposed',1,'{{"fixture":true}}');
  INSERT INTO private.source_persona_identity(source_persona_id,decision_status,version,evidence) VALUES (r,'proposed',1,'{{"fixture":true}}');
  INSERT INTO public.person(id,levende,privat,status) VALUES (-621107,false,false,'pp');
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (-621107,{SRC},'I',7,'p7');
END $s$;
"""


def _run(db, sqlfile: Path, source: int = SRC, profile: str = PROFILE) -> str:
    out = _must(_psql("-v", f"source_id={source}", "-v", f"profile_id={profile}", "-f", str(sqlfile), db=db), sqlfile.name)
    return out.strip()


def _manifest(db) -> dict:
    return json.loads(_run(db, MANIFEST))


def _maal(db, profile: str = PROFILE) -> dict:
    line = _run(db, MAAL, profile=profile)
    assert line.startswith("T6B_MAAL ") and "\n" not in line, line
    return dict(kv.split("=", 1) for kv in line.split()[1:])


def test_manifest_has_one_element_per_bound_helpost_without_persona(db):
    m = _manifest(db)
    keys = list(m["elements"])
    assert keys == ["publication-persona:p1", "publication-persona:p2", "publication-persona:p3"]
    assert keys == sorted(keys)
    assert m["expected_counts"] == {"person_creates": 0, "source_evidence": 0, "publication_personas": 3}
    for key, payload in m["elements"].items():
        rk = key.split(":", 1)[1]
        assert sorted(payload) == ["binding_id", "binding_status", "mention_id", "mention_text_sha256", "person_id",
                                   "persona_key", "source_id", "source_record_key"]
        assert payload["source_record_key"] == rk and payload["persona_key"] == f"1939:{rk}"
        assert payload["binding_status"] == "published" and payload["source_id"] == SRC
        assert re.fullmatch(r"[0-9a-f]{64}", payload["mention_text_sha256"])
    assert m["elements"]["publication-persona:p2"]["person_id"] == -621102


def test_manifest_dispositions(db):
    d = _manifest(db)["dispositions"]
    by = {}
    for x in d:
        by.setdefault(x["label"], []).append(x.get("record_key", x.get("person_id")))
    assert {k: sorted(v, key=str) for k, v in by.items()} == {
        "allerede_persona": ["p5"], "ingen_helpost": ["p6"], "ingen_postbinding": ["p4"],
        "staged_ikke_offentlig": ["p3"], "ingen_bundet_narrativ": sorted([-621107, -621104], key=str)}
    assert "helpost_uegnet" not in by and "binding_uegnet" not in by


def test_manifest_is_stable_and_read_only(db):
    a = _run(db, MANIFEST)
    b = _run(db, MANIFEST)
    assert a == b and a.count("\n") == 0
    sql = MANIFEST.read_text(encoding="utf-8")
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    assert not re.search(r"\b(INSERT|UPDATE|DELETE)\s", re.sub(r"--[^\n]*", "", sql))
    # ingen posttekst/navne: payloads bærer kun hashes og id'er
    assert "Fixture Navn" not in a and "Syntetisk tekst" not in a


def test_maal_goes_from_foer_to_b_after_apply(db):
    assert _maal(db, "findes-ikke")["tilstand"] == "foer"
    before = _maal(db)
    assert before["tilstand"] == "a"
    assert (before["personas_k3"], before["identiteter_k3"], before["afventer"]) == ("1", "0", "0")
    assert re.fullmatch(r"[0-9a-f]{32}", before["k1_hash"])

    els = _manifest(db)["elements"]
    script = f"""
\\set ON_ERROR_STOP on
\\i tests/sql/fixtures/publication-persona.sql
SELECT set_config('app.els', $j${json.dumps(els)}$j$, false);
DO $d$
DECLARE
  v jsonb:=jsonb_build_object('source',{SRC},'actor','{ACTOR}','profile_sha256',
     (SELECT profile_sha256 FROM private.reimport_writer_profile WHERE source_id={SRC} AND profile_id='{PROFILE}'));
  e jsonb:=current_setting('app.els')::jsonb; k text; batch uuid;
BEGIN
  batch:=pg_temp.pp_begin(v,'{PROFILE}','t11',e);
  FOR k IN SELECT jsonb_object_keys(e) LOOP PERFORM pg_temp.pp_apply(v,batch,k,e->k); END LOOP;
  PERFORM set_config('request.jwt.claim.sub','{ACTOR}',true); PERFORM set_config('role','authenticated',true);
  PERFORM public.red_finalize_reimport(batch);
  RESET role;
END $d$;
"""
    _must(_psql(db=db, stdin=script), "apply")
    after = _maal(db)
    assert after["tilstand"] == "b"
    assert (after["personas_k3"], after["identiteter_k3"], after["afventer"]) == ("4", "0", "3")
    assert (after["k1_personas"], after["k1_identiteter"], after["k1_hash"]) == \
        (before["k1_personas"], before["k1_identiteter"], before["k1_hash"])
    assert (before["k1_personas"], before["k1_identiteter"]) == ("1", "1")
    assert before["k1_hash"] != "d41d8cd98f00b204e9800998ecf8427e"  # ikke md5('')
    # efter B er alle tre allerede_persona, og manifestet er tomt
    m = _manifest(db)
    assert m["elements"] == {} and m["expected_counts"]["publication_personas"] == 0
    assert sum(x["label"] == "allerede_persona" for x in m["dispositions"]) == 4


def test_k1_hash_changes_when_source_1_changes(db):
    h0 = _maal(db)["k1_hash"]
    # ny version af identiteten (lovlig skrivevej: identitetsrækken er en versioneret aktuel-række)
    # ny identitetsversion: ny event-række (append-only) og state-rækken, i samme transaktion
    new = ("DO $n$ DECLARE r uuid; u uuid:=gen_random_uuid(); t timestamptz:=now(); BEGIN "
           "SELECT id INTO r FROM private.source_persona WHERE source_id=1; "
           "INSERT INTO private.source_persona_identity_event(source_persona_id,decision_status,version,evidence,decided_by,"
           "decided_by_name,decided_at) VALUES (r,'unresolved',2,'{\"x\":1}',u,'fixture',t); "
           "UPDATE private.source_persona_identity SET version=2, decision_status='unresolved', evidence='{\"x\":1}', "
           "decided_by=u, decided_by_name='fixture', decided_at=t WHERE source_persona_id=r; END $n$")
    _must(_psql("-c", new, db=db), "identitet")
    h1 = _maal(db)["k1_hash"]
    assert h1 != h0
    _must(_psql("-c", "INSERT INTO private.source_persona(source_id,persona_key,created_run_id) "
                      "VALUES (1,'k1b','11000000-0000-0000-0000-00000006b2a1')", db=db), "persona")
    m = _maal(db)
    assert m["k1_hash"] not in (h0, h1) and m["k1_personas"] == "2"


def test_wrong_profile_or_source_fails_loudly(db):
    for source, profile in ((SRC, "findes-ikke"), (-1, PROFILE)):
        p = _psql("-v", f"source_id={source}", "-v", f"profile_id={profile}", "-f", str(MANIFEST), db=db)
        assert p.returncode != 0 and p.stdout.strip() == "", (source, profile)


def test_maal_is_read_only_too(db):
    sql = re.sub(r"--[^\n]*", "", MAAL.read_text(encoding="utf-8"))
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|ALTER|DROP|CREATE)\s", sql)
