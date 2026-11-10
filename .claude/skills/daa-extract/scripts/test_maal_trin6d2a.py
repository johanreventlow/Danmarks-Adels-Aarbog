"""Trin 6d-2a Task 6: maalingen maal_trin6d2a.sql, koert mod en lokal fixturebase (foer -> ddl -> data).

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; basen oprettes af testen (t6d2a_t6_maal_<pid>) og droppes
ALDRIG af den (i CI er serveren engangs). Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true)
fejler den. Alt er syntetisk, og maalingen viser kun tal og hashes.
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
MAAL = SCRIPTS / "maal_trin6d2a.sql"
CEREMONI = SCRIPTS / "identitet_ceremoni.sql"
SRC = -6420
ANDEN = -6421
DB = f"t6d2a_t6_maal_{os.getpid()}"
LINE = re.compile(r"T6D2A_MAAL fase=(foer|ddl|data) regel=(\d+|na) synlige_anon=(\d+|na) bio_oversigt=(\d+|na) kanter_par=([01]) "
                  r"unresolved=(\d+) uden_identitet=(\d+) KOORD_2018_20=([0-9a-f]{32}) KOORD_SRC=([0-9a-f]{32}) "
                  r"FAKTA=([0-9a-f]{32}) BIO=([0-9a-f]{32})")
FELTER = ("fase", "regel", "anon", "bio_oversigt", "kanter_par", "unresolved", "uden_identitet", "koord", "koord_src", "fakta", "bio")


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
    for f in ("tests/sql/evidence-promotion-bootstrap.sql", "schema.sql", "db-rls.sql"):
        _must(_psql("-f", f, db=DB), f)
    _must(_psql(db=DB, stdin=_SETUP), "setup")
    return DB


# To kilder; kilden har to personaer (en unresolved, en uden identitetsraekke) og en person med en offentlig narrativ.
_SETUP = f"""
\\set ON_ERROR_STOP on
SET session_replication_role = replica;
INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({SRC},'Fixture 6d2a','synthetic','1900','DAA-udgave'),
                                                           ({ANDEN},'Fixture 6d2a anden','synthetic','2018','DAA-udgave');
INSERT INTO public.person(id,levende) VALUES (-642001,false),(-642002,false),(-642101,false);
INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES
  (-642001,{SRC},'I',1,'a1'),(-642101,{ANDEN},'I',1,'b1');
INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst) VALUES ('person',-642001,{SRC},'Opdigtet tekst');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES ('12000000-0000-0000-0000-00000006d201',{SRC},'t6-run','fixture','fixture','fixture',repeat('1',64),'{{}}');
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES
  ('12000000-0000-0000-0000-00000006d2a1',{SRC},'u1','12000000-0000-0000-0000-00000006d201'),
  ('12000000-0000-0000-0000-00000006d2a2',{SRC},'u2','12000000-0000-0000-0000-00000006d201');
INSERT INTO auth.users(id,email) VALUES ('12000000-0000-0000-0000-00000006d2f0','t6@6d2a.invalid') ON CONFLICT DO NOTHING;
INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
  decided_by,decided_by_name,decided_at) VALUES ('12000000-0000-0000-0000-00000006d2a1',NULL,'unresolved',1,'{{"fixture":"t6"}}','12000000-0000-0000-0000-00000006d2f0','fixture',now());
INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
  decided_by,decided_by_name,decided_at) VALUES ('12000000-0000-0000-0000-00000006d2a1',NULL,'unresolved',1,'{{"fixture":"t6"}}','12000000-0000-0000-0000-00000006d2f0','fixture',now());
"""

PAR = ("-v", "par_a=-642001", "-v", "par_b=-642002")


def _maal(db, *extra: str) -> dict[str, str]:
    out = _must(_psql("-v", f"src={SRC}", *(extra or PAR), "-f", str(MAAL), db=db), "maal").strip()
    assert "\n" not in out, out
    g = LINE.fullmatch(out)
    assert g, out
    return dict(zip(FELTER, g.groups()))


_READER = "public.public_person_bio_source_versions_v2(bigint[])"


def _foer(db, *, paa: bool) -> dict:
    """paa=True simulerer fasen foer: reglen omdoebes, og laeseren (som kalder reglen) erstattes af en tom stub, hvis
    originale definition huskes; paa=False gendanner begge."""
    if paa:
        defn = _must(_psql("-c", f"SELECT pg_get_functiondef('{_READER}'::regprocedure)", db=db), "def").strip()
        _must(_psql("-c", "ALTER FUNCTION private.overview_mention_narratives(bigint[]) "
                          "RENAME TO overview_mention_narratives_t6", db=db), "omdoeb")
        _must(_psql(db=db, stdin="""CREATE OR REPLACE FUNCTION public.public_person_bio_source_versions_v2(p_person_ids bigint[])
RETURNS TABLE(person_id bigint, source_id bigint, source_year integer, record_order integer, source_record_ref uuid,
  source_label text, record_label text, narrative_text text, citation_label text, provenance_kind text)
LANGUAGE sql STABLE AS $$ SELECT NULL::bigint,NULL::bigint,NULL::integer,NULL::integer,NULL::uuid,NULL::text,NULL::text,
  NULL::text,NULL::text,NULL::text WHERE false $$;"""), "stub")
        return {"def": defn}
    _must(_psql("-c", "ALTER FUNCTION private.overview_mention_narratives_t6(bigint[]) "
                      "RENAME TO overview_mention_narratives", db=db), "omdoeb")
    return {}


def test_foer_ddl_data_og_taellingerne(db):
    gem = _foer(db, paa=True)
    foer = _maal(db)
    assert foer["fase"] == "foer" and foer["regel"] == "na" and foer["anon"] == "na" and foer["bio_oversigt"] == "na"
    _foer(db, paa=False)
    _must(_psql(db=db, stdin=gem["def"] + ";"), "gendan laeser")
    ddl = _maal(db)
    assert ddl["fase"] == "ddl" and ddl["regel"] == "0" and ddl["anon"] == "0" and ddl["bio_oversigt"] == "0"
    assert ddl["unresolved"] == "1" and ddl["uden_identitet"] == "1" and ddl["kanter_par"] == "0"
    # kvitteringen (ogsaa ved fire N) flytter fasen til data; den roerer ikke hashes eller taellinger
    kv = "INSERT INTO public.change_set(operation,summary,subjekt_type,subjekt_id) VALUES " \
         "('identitet_ceremoni','T6D2A_OK kanter=0 identiteter=0 regel=0','source',%d)"
    _must(_psql("-c", kv % ANDEN, db=db), "kvittering for en anden kilde")
    assert _maal(db)["fase"] == "ddl"  # en anden kildes kvittering tæller ikke
    _must(_psql("-c", kv % SRC, db=db), "kvittering")
    data = _maal(db)
    assert data["fase"] == "data"
    assert {k: v for k, v in data.items() if k != "fase"} == {k: v for k, v in ddl.items() if k != "fase"}
    assert foer["koord"] == ddl["koord"] == data["koord"] and foer["koord_src"] == data["koord_src"]
    assert foer["fakta"] == ddl["fakta"] and _maal(db) == data


_RULE = "private.overview_mention_narratives(bigint[])"


def _def(db, sig: str) -> str:
    return _must(_psql("-c", f"SELECT pg_get_functiondef('{sig}'::regprocedure)", db=db), "def").strip() + ";"


def test_positiv_kontrol_for_anon_og_bio_tallene(db):
    """Reglen stubbes til at pege paa fixturens narrativ: anon kan laese den direkte (synlige_anon=1), mens den rigtige
    laeser udelader den (bio_oversigt=0). Erstattes laeseren af en stub, der ignorerer reglen, leverer den teksten, og
    bio_oversigt=1: taelleren kan altsaa vaere forskellig fra 0."""
    regel_def, laeser_def = _def(db, _RULE), _def(db, _READER)
    try:
        _must(_psql(db=db, stdin="""CREATE OR REPLACE FUNCTION private.overview_mention_narratives(p_person_ids bigint[])
RETURNS TABLE(narrative_id bigint, person_id bigint, source_id bigint, detail_person_id bigint)
LANGUAGE sql STABLE AS $$ SELECT n.id,n.subjekt_id,n.source_id,-1::bigint FROM public.narrative n
  WHERE n.subjekt_type='person' AND n.subjekt_id=ANY(p_person_ids) $$;"""), "regelstub")
        normal = _maal(db)
        assert normal["regel"] == "1" and normal["anon"] == "1" and normal["bio_oversigt"] == "0"
        _must(_psql(db=db, stdin="""CREATE OR REPLACE FUNCTION public.public_person_bio_source_versions_v2(p_person_ids bigint[])
RETURNS TABLE(person_id bigint, source_id bigint, source_year integer, record_order integer, source_record_ref uuid,
  source_label text, record_label text, narrative_text text, citation_label text, provenance_kind text)
LANGUAGE sql STABLE AS $$ SELECT n.subjekt_id,n.source_id,NULL::integer,NULL::integer,NULL::uuid,NULL::text,NULL::text,
  n.tekst,NULL::text,NULL::text FROM public.narrative n WHERE n.subjekt_id=ANY(p_person_ids) $$;"""), "laeserstub")
        laekket = _maal(db)
        assert laekket["regel"] == "1" and laekket["anon"] == "1" and laekket["bio_oversigt"] == "1"
    finally:
        _must(_psql(db=db, stdin=regel_def), "gendan regel")
        _must(_psql(db=db, stdin=laeser_def), "gendan laeser")
    assert _maal(db)["regel"] == "0"


def test_kanter_par_taeller_begge_retninger(db):
    h0 = _maal(db)
    _must(_psql("-c", "INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) "
                      "VALUES ('person',-642002,'person',-642001,'samme_som')", db=db), "kant")
    h1 = _maal(db)
    assert h0["kanter_par"] == "0" and h1["kanter_par"] == "1"
    _must(_psql("-c", "DELETE FROM public.relation WHERE rolle='samme_som' AND subjekt_id=-642002", db=db), "ryd")
    assert _maal(db)["kanter_par"] == "0"


def test_koord_adskiller_kilden_fra_de_andre(db):
    h0 = _maal(db)
    _must(_psql("-c", f"UPDATE public.person_external_id SET nr=nr+10 WHERE person_id=-642101 AND source_id={ANDEN}",
                db=db), "anden")
    h1 = _maal(db)
    assert h1["koord"] != h0["koord"] and h1["koord_src"] == h0["koord_src"]
    _must(_psql("-c", f"UPDATE public.person_external_id SET nr=nr+10 WHERE person_id=-642001 AND source_id={SRC}",
                db=db), "kilde")
    h2 = _maal(db)
    assert h2["koord"] == h1["koord"] and h2["koord_src"] != h1["koord_src"]


def test_par_er_paakraevet(db):
    proc = _psql("-v", f"src={SRC}", "-f", str(MAAL), db=db)
    assert proc.returncode != 0 and "T6D2A_MAAL" not in proc.stdout


def test_sql_er_laese_kun_og_viser_ingen_tekst():
    sql = MAAL.read_text(encoding="utf-8")
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    code = re.sub(r"--[^\n]*", "", sql)
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|CREATE)\s", code)
    # uddata er kun den ene T6D2A_MAAL-linje: ingen id'er (par_a/par_b indgaar ikke), ingen tekst
    assert len(re.findall(r"^SELECT format\(", code, re.M)) == 1
    assert not re.search(r"person_id\s*=\s*-?\d{3,}|\b\d{4,}\b", code)


def _fakta(sql: str, ids: str, fids: str) -> str:
    m = re.search(r"SELECT 'f\|'.*?public_family_sources\([^)]*\) s", sql, re.S)
    assert m, "FAKTA-udtrykket mangler"
    return re.sub(r"\s+", "", m.group(0)).replace(ids, "IDS").replace(fids, "FIDS")


def test_fakta_udtrykket_er_det_samme_som_ceremoniens():
    """FAKTA i maalingen og i ceremoniens POST-sammenligning skal vaere samme udtryk (KOORD_* dækkes af shell-testen,
    som sammenligner maalingens KOORD_2018_20 foer og efter ceremonien)."""
    maal = MAAL.read_text(encoding="utf-8")
    cer = CEREMONI.read_text(encoding="utf-8")
    assert _fakta(maal, ":'ids'::bigint[]", ":'fids'::bigint[]") == _fakta(cer, "v_ids", "v_fids")
