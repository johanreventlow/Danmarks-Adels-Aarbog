"""Trin 6e-2 Task 9: maalingen maal_trin6e2.sql, koert mod en lokal fixturebase (foer -> ddl -> data, hashes stabile).

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; basen oprettes og droppes af testen (t6e2_t9_maal_<pid>).
Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true) fejler den. Alt er syntetisk, og maalingen
viser kun tal og hashes. Fixturen skriver direkte (session_replication_role=replica) i stedet for gennem writerne;
ceremonien selv proeves ende-til-ende af tests/sql/test-etiket-ceremoni.sh.
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
MAAL = SCRIPTS / "maal_trin6e2.sql"
CEREMONI = SCRIPTS / "etiket_ceremoni.sql"
SRC = -6930
ANDEN = -6931
DB = f"t6e2_t9_maal_{os.getpid()}"
RUN = "11000000-0000-0000-0000-00000006e201"
REC = "11000000-0000-0000-0000-00000006e2"
LINE = re.compile(r"T6E2_MAAL fase=(foer|ddl|data) KOORD_ANDRE=([0-9a-f]{32}) ETIKETTER_ANDRE=([0-9a-f]{32}) "
                  r"BINDINGER_RECORD=(\d+) SPRUNGET=(\d+) UDEN_PLACEMENT=(\d+) STALE=(\d+) BIO_OFFENTLIGE=(\d+) FAKTA_BUNDNE=(\d+) "
                  r"FAMILIEKILDER=([0-9a-f]{32}) SKEMA_ETIKETTER=([0-9a-f]{32})")
FELTER = ("fase", "koord", "etiketter", "bindinger_record", "sprunget", "uden_placement", "stale", "bio", "fakta", "famkilder",
          "skema")


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


# To kilder: kilden med to record-bindinger (den ene uden placement, ingen hændelser, saa begge er stale) og et
# linjeskema; den anden kilde med en bognoegle-binding og en legacy-raekke (koordinater).
_SETUP = f"""
\\set ON_ERROR_STOP on
SET session_replication_role = replica;
INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({SRC},'Fixture 6e2','DAA K','1900','DAA-udgave'),
                                                           ({ANDEN},'Fixture 6e2 anden','DAA A','2018','DAA-udgave');
INSERT INTO public.person(id) VALUES (-693001),(-693002),(-693101);
INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES
  (-693001,{SRC},'I',1,NULL),(-693101,{ANDEN},'V',1,'V-1');
INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug,status) VALUES (-6930,'Fixture','Fixture','f6e2-maal','active');
INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES (-6930,-6930,{SRC},'stamtavle','fixture');
INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order)
  VALUES (-6930,-6930,-6930,'I','Den testske Linje.',1);
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES ('{RUN}',{SRC},'t9-run','fixture','fixture','fixture',repeat('1',64),'{{}}');
INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES
  ('{REC}a1',{SRC},'record-11000000-0000-0000-0000-00000006e2a1','person_post','{RUN}'),
  ('{REC}a2',{SRC},'record-11000000-0000-0000-0000-00000006e2a2','person_post','{RUN}'),
  ('{REC}a3',{ANDEN},'V-1','person_post','{RUN}');
INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst) VALUES
  (-693001,'person',-693001,{SRC},'Opdigtet.'),(-693002,'person',-693002,{SRC},'Opdigtet.'),
  (-693101,'person',-693101,{ANDEN},'Opdigtet.');
INSERT INTO private.narrative_record_publication(id,narrative_id,source_record_id,record_label,citation_label,status,published_at)
  VALUES ('{REC}b1',-693001,'{REC}a1','record-11000000-0000-0000-0000-00000006e2a1','DAA K side 10','published',now()),
         ('{REC}b2',-693002,'{REC}a2','record-11000000-0000-0000-0000-00000006e2a2','DAA K side 11','published',now()),
         ('{REC}b3',-693101,'{REC}a3','V-1','DAA A, s. 45','published',now());
-- Placementen peger paa en header-observation, som ikke findes (replica: ingen FK-kontrol; maalingen laeser den ikke).
INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status,printed_number)
  VALUES ('{REC}d1','{REC}a1',-6930,'{REC}c1','accepted','1');
INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
  VALUES ('{REC}d1',1,'accepted','{{"fixture":"t9"}}','migration','fixture');
"""


def _maal(db) -> dict[str, str]:
    out = _must(_psql("-v", f"src={SRC}", "-f", str(MAAL), db=db), "maal").strip()
    assert "\n" not in out, out
    g = LINE.fullmatch(out)
    assert g, out
    return dict(zip(FELTER, g.groups()))


def _ddl_markoer(db, *, fjern: bool) -> None:
    """fjern=True: omdoeb narrative_record_wanted_labels (simulerer 'foer'); fjern=False: gendan."""
    a, b = ("narrative_record_wanted_labels", "narrative_record_wanted_labels_t9") if fjern else \
        ("narrative_record_wanted_labels_t9", "narrative_record_wanted_labels")
    _must(_psql("-c", f"ALTER FUNCTION private.{a}(uuid) RENAME TO {b}", db=db), "omdoeb")


def test_foer_ddl_data_og_andre_kilder_er_stabile(db):
    _ddl_markoer(db, fjern=True)
    foer = _maal(db)
    assert foer["fase"] == "foer"
    _ddl_markoer(db, fjern=False)
    ddl = _maal(db)
    assert ddl["fase"] == "ddl" and ddl["bindinger_record"] == "2" and ddl["uden_placement"] == "1"
    assert ddl["sprunget"] == "0"
    # bindingerne har ingen hændelser, saa begge kildens (og modpartens) er stale i fixturen
    assert ddl["stale"] == "3"
    _must(_psql("-c", f"UPDATE public.source SET sidekort='[{{\"pdf_fra\":1,\"pdf_til\":20,\"trykt_fra\":1}}]' "
                      f"WHERE id={SRC}", db=db), "sidekort")
    data = _maal(db)
    assert data["fase"] == "data"
    # runnerens stopregel: KOORD_ANDRE og ETIKETTER_ANDRE i ddl og data = foer
    for k in ("koord", "etiketter", "skema", "famkilder", "bio", "fakta"):
        assert foer[k] == ddl[k] == data[k], k
    assert _maal(db) == data
    _must(_psql("-c", f"UPDATE public.source SET sidekort=NULL WHERE id={SRC}", db=db), "sidekort tilbage")


def test_andre_adskiller_kilden_fra_de_andre(db):
    h0 = _maal(db)
    _must(_psql("-c", f"UPDATE private.narrative_record_publication SET citation_label='DAA K, s. 10' "
                      f"WHERE id='{REC}b1'", db=db), "kilde")
    h1 = _maal(db)
    assert h1["etiketter"] == h0["etiketter"] and h1["koord"] == h0["koord"]
    _must(_psql("-c", f"UPDATE private.narrative_record_publication SET citation_label='DAA A, s. 46' "
                      f"WHERE id='{REC}b3'", db=db), "anden binding")
    h2 = _maal(db)
    assert h2["etiketter"] != h1["etiketter"] and h2["koord"] == h1["koord"]
    _must(_psql("-c", f"UPDATE public.person_external_id SET nr=2 WHERE person_id=-693101 AND source_id={ANDEN}",
                db=db), "anden legacy")
    h3 = _maal(db)
    assert h3["koord"] != h2["koord"] and h3["etiketter"] == h2["etiketter"]
    _must(_psql("-c", f"UPDATE public.lineage_scheme_entry SET label='I. Den testske Linje.' WHERE id=-6930",
                db=db), "skema")
    h4 = _maal(db)
    assert h4["skema"] != h3["skema"] and h4["koord"] == h3["koord"] and h4["etiketter"] == h3["etiketter"]


def test_sql_er_laese_kun_og_viser_ingen_tekst():
    sql = MAAL.read_text(encoding="utf-8")
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    assert not re.search(r"\b(INSERT|UPDATE|DELETE)\s", re.sub(r"--[^\n]*", "", sql))


def _udtryk(sql: str, start: str, slut: str) -> str:
    """Hash-udtrykket fra `start` til og med `slut`, uden mellemrum."""
    m = re.search(re.escape(start) + r".*?" + re.escape(slut), sql, re.S)
    assert m, f"udtrykket {start}… mangler"
    return re.sub(r"\s+", "", m.group(0))


@pytest.mark.parametrize("start,slut", [
    ("md5(coalesce(string_agg(ROW(c.person_id", "ORDER BY c.person_id,c.source_id),''))"),
    ("md5(coalesce(string_agg(concat_ws('|',b.id,b.record_label,b.citation_label)", "ORDER BY b.id),''))"),
])
def test_andre_hashes_er_de_samme_som_ceremoniens(start, slut):
    """KOORD_ANDRE og ETIKETTER_ANDRE fra fase foer sammenlignes med ceremoniens efterbetingelse: ens udtryk."""
    assert _udtryk(MAAL.read_text(encoding="utf-8"), start, slut) == \
        _udtryk(CEREMONI.read_text(encoding="utf-8"), start, slut)


def test_laesertal_er_de_samme_som_ceremoniens():
    """BIO_OFFENTLIGE og FAKTA_BUNDNE: samme saetninger (som anon) i maalingen og ceremonien."""
    m, c = MAAL.read_text(encoding="utf-8"), CEREMONI.read_text(encoding="utf-8")
    for s in ("SELECT count(*) AS bio_offentlige FROM public.public_person_bio_source_versions_v2(:'ids'::bigint[]) \\gset",
              "SELECT count(*) AS fakta_bundne FROM public.public_person_facts(:'ids'::bigint[]) WHERE record_ref IS NOT NULL \\gset",
              "WHERE public.person_offentlig(id)",
              "coalesce((s #>> '{publication_state,publication_policy,person_publication_allowed}')::boolean,false)"):
        assert s in m and s in c, s
