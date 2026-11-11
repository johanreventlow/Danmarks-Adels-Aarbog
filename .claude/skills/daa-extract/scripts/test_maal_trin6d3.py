"""Trin 6d-3 Task 7: maalingen maal_trin6d3.sql mod en lokal fixturebase, plus statiske laase paa D/O-ceremonien.

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; baserne oprettes af testen (t6d3t7_maal_<pid> og
t6d3t7_maaltom_<pid>) og droppes ALDRIG af den (i CI er serveren engangs). Mangler psql/serveren, springes testen kun
over lokalt; i CI (CI=true) fejler den. Alt er syntetisk (negative id'er), og maalingen viser kun tal og hashes.
Fixturbasen er en kontrakt 2-base (som CI's writer-job) med D/O-fixturen (tests/sql/fixtures/ceremoni-6d3.sql) og to
bundne, publicerede aegteskaber i hver sin kilde (K1 = -643100 og en anden -643200), saa K1_* og FAMKILDER er ikke-tomme.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parents[3]
MAAL = SCRIPTS / "maal_trin6d3.sql"
D_SQL = SCRIPTS / "samme_som_kort_ceremoni.sql"
O_SQL = SCRIPTS / "privat_kort_ceremoni.sql"
SRC, K1, ANDEN, SKJUL = -630100, -643100, -643200, -630160
DB = f"t6d3t7_maal_{os.getpid()}"
DB_TOM = f"t6d3t7_maaltom_{os.getpid()}"
LINE = re.compile(r"T6D3_MAAL fase=(foer|ddl|d|o|r) forslag_k3=(\d+)/(\d+)/(\d+) bundne_k3=(\d+) samme_som=(\d+) "
                  r"dobbelt=(\d+) privat_1791=([01]) uden_position=(\d+) K1_ORD=([0-9a-f]{32}) K1_BIND=([0-9a-f]{32}) "
                  r"FAMKILDER=([0-9a-f]{32})")
FELTER = ("fase", "m", "p", "c", "bundne", "samme_som", "dobbelt", "privat", "uden_position", "k1_ord", "k1_bind", "famkilder")


def _psql(*args: str, db: str | None = None, stdin: str | None = None) -> subprocess.CompletedProcess:
    cmd = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"] + (["-d", db] if db else []) + list(args)
    env = {k: v for k, v in os.environ.items() if k != "PGOPTIONS"}
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=ROOT, env=env)


def _must(proc: subprocess.CompletedProcess, what: str) -> str:
    assert proc.returncode == 0, f"{what} fejlede: {proc.stderr[-1500:]}"
    return proc.stdout


def _server() -> None:
    if shutil.which("psql") is None or subprocess.run(["psql", "-X", "-Atc", "select 1", "-d", "postgres"],
                                                      capture_output=True).returncode != 0:
        if os.environ.get("CI"):
            pytest.fail("PostgreSQL er ikke tilgaengelig i CI")
        pytest.skip("ingen lokal PostgreSQL")


# To bundne og publicerede aegteskaber (som f2a_bound i tests/sql/test-family-sources.sql), hver i egen kilde.
_K1 = """
\\set ON_ERROR_STOP on
BEGIN;
\\ir tests/sql/fixtures/relation-5b.sql
\\ir tests/sql/fixtures/relation-2a.sql
CREATE OR REPLACE FUNCTION pg_temp.f6d3_bound(p_base bigint,p_actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s jsonb; m jsonb; pv jsonb; items jsonb;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (p_base,false,false,'6d3'),(p_base-1,false,false,'6d3');
  s:=pg_temp.f5b_source(p_base);
  m:=pg_temp.f2a_marriage(p_base,s,'B'||p_base,p_base,p_base-1,p_actor,1,1);
  PERFORM pg_temp.f2a_publish(p_base,s,m->'post',p_base,p_actor,'Anna Alfa. Gift med Bo Beta.');
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  pv:=red_preview_relation_decisions(p_base);
  PERFORM red_decide_relation_interpretations(p_base,pv->>'set_sha256');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',(m->>'family')::bigint)) INTO items
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->'claim'->>'key')::uuid;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_base,items);
  PERFORM red_promote_relation_interpretations_batch(p_base,items,pv->>'preview_sha256');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;
DO $k1$
BEGIN
  PERFORM pg_temp.f5b_actor('11000000-0000-0000-0000-0000006d3701');
  PERFORM pg_temp.f6d3_bound(%(k1)d,'11000000-0000-0000-0000-0000006d3701');
  PERFORM pg_temp.f6d3_bound(%(anden)d,'11000000-0000-0000-0000-0000006d3701');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
END $k1$;
COMMIT;
""" % {"k1": K1, "anden": ANDEN}


@pytest.fixture(scope="module")
def db():
    _server()
    _must(subprocess.run(["createdb", DB], capture_output=True, text=True), "createdb")
    for f in ("tests/sql/evidence-promotion-bootstrap.sql", "schema.sql", "db-rls.sql",
              "tests/sql/1939-v50-writer-bootstrap.sql"):
        _must(_psql("-f", f, db=DB), f)
    _must(_psql("-c", "BEGIN", "-f", "tests/sql/reimport-writer-v2-bootstrap.sql", "-c", "COMMIT", db=DB), "v2-bootstrap")
    _must(_psql("-f", "db-rls.sql", db=DB), "db-rls")
    _must(_psql("-f", "tests/sql/fixtures/ceremoni-6d3.sql", db=DB), "ceremoni-6d3")
    _must(_psql(db=DB, stdin=_K1), "K1-fixture")
    return DB


def _run(db, fase="d", **over) -> subprocess.CompletedProcess:
    v = {"fase": fase, "src": str(SRC), "k1_src": str(K1), "skjul_person": str(SKJUL)} | over
    args = []
    for k, x in v.items():
        if x is not None:
            args += ["-v", f"{k}={x}"]
    return _psql(*args, "-f", str(MAAL), db=db)


def _maal(db, fase="d") -> dict[str, str]:
    out = _must(_run(db, fase), "maal").strip()
    assert "\n" not in out, out
    g = LINE.fullmatch(out)
    assert g, out
    return dict(zip(FELTER, g.groups()))


def _sql(db, *stmts: str) -> None:
    args = []
    for s in stmts:
        args += ["-c", s]
    _must(_psql(*args, db=db), stmts[0])


def test_format_og_vaerdier(db):
    for fase in ("foer", "ddl", "d", "o", "r"):
        assert _maal(db, fase)["fase"] == fase
    h = _maal(db)
    # 4 forslag (D-1: 1, D-2: 2, D-9: 1), ingen bundne i kilden, fire samme_som, tre D-kandidater (-6301, -6302, -6303),
    # D-9 uden position
    assert (h["m"], h["p"], h["c"], h["bundne"]) == ("4", "0", "0", "0")
    assert (h["samme_som"], h["dobbelt"], h["privat"], h["uden_position"]) == ("4", "3", "0", "1")
    assert _maal(db) == h
    # bundne_k3 bruger samme bundet-definition som K1_BIND: med den anden bundne kilde som src taeller den 1.
    byt = _must(_run(db, src=str(ANDEN)), "maal").strip()
    assert LINE.fullmatch(byt) and " bundne_k3=1 " in byt and " dobbelt=0 " in byt, byt


def test_d_aendrer_kun_samme_som_og_dobbelt(db):
    h0 = _maal(db)
    _sql(db, "INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) "
             "VALUES ('person',-630111,'person',-630216,'samme_som')")
    try:
        h1 = _maal(db)
    finally:
        _sql(db, "DELETE FROM public.relation WHERE rolle='samme_som' AND subjekt_id=-630111")
    assert h1["samme_som"] == "5" and h1["dobbelt"] == "2"
    assert {k: v for k, v in h1.items() if k not in ("samme_som", "dobbelt")} == \
           {k: v for k, v in h0.items() if k not in ("samme_som", "dobbelt")}
    assert _maal(db) == h0


def test_privat_og_famkilder_er_uafhaengige_af_k1(db):
    h0 = _maal(db)
    _sql(db, f"UPDATE public.person SET privat=true WHERE id={SKJUL}")
    try:
        h1 = _maal(db)
    finally:
        _sql(db, f"UPDATE public.person SET privat=false WHERE id={SKJUL}")
    assert h1["privat"] == "1" and {k: v for k, v in h1.items() if k != "privat"} == \
           {k: v for k, v in h0.items() if k != "privat"}
    # Den anden kildes aegtefaelle skjules: dens familie forsvinder fra FAMKILDER, K1 er uaendret.
    _sql(db, f"UPDATE public.person SET privat=true WHERE id={ANDEN - 1}")
    try:
        h2 = _maal(db)
    finally:
        _sql(db, f"UPDATE public.person SET privat=false WHERE id={ANDEN - 1}")
    assert h2["famkilder"] != h0["famkilder"]
    assert (h2["k1_ord"], h2["k1_bind"]) == (h0["k1_ord"], h0["k1_bind"])
    assert _maal(db) == h0


def test_k1_bind_kraever_gemt_hash_lig_genberegnet(db):
    """En promotion, hvis gemte state_sha256 ikke er den genberegnede, er ikke bundet; K1's eneste binding falder bort,
    og maalingen fejler paa den tomme maengde."""
    h0 = _maal(db)
    sel = (f"SELECT p.id FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id "
           f"WHERE q.source_id={K1}")
    _sql(db, "SET session_replication_role=replica",
         f"UPDATE private.interpretation_promotion SET evidence=jsonb_set(evidence,'{{state_sha256}}','\"{'0' * 64}\"') "
         f"WHERE id IN ({sel})")
    try:
        proc = _run(db)
    finally:
        _sql(db, "SET session_replication_role=replica",
             f"UPDATE private.interpretation_promotion p SET evidence=jsonb_set(p.evidence,'{{state_sha256}}',"
             f"to_jsonb(private.reimport_canonical_json_sha256(private.relation_binding_state(p.interpretation_id)))) "
             f"WHERE id IN ({sel})")
    assert proc.returncode != 0 and "T6D3_MAAL_TOM K1_BIND" in proc.stderr and "T6D3_MAAL " not in proc.stdout
    assert _maal(db) == h0


def test_tom_maengde_er_en_fejl():
    _server()
    _must(subprocess.run(["createdb", DB_TOM], capture_output=True, text=True), "createdb")
    for f in ("tests/sql/evidence-promotion-bootstrap.sql", "schema.sql", "db-rls.sql"):
        _must(_psql("-f", f, db=DB_TOM), f)
    _sql(DB_TOM, f"INSERT INTO public.person(id) VALUES ({SKJUL})")
    proc = _run(DB_TOM)
    assert proc.returncode != 0 and "T6D3_MAAL_TOM K1_ORD,K1_BIND,FAMKILDER" in proc.stderr, proc.stderr
    assert "T6D3_MAAL " not in proc.stdout


@pytest.mark.parametrize("over", [{"fase": "data"}, {"fase": None}, {"src": None}, {"k1_src": None},
                                  {"skjul_person": None}, {"src": "x"}, {"k1_src": str(SRC)}, {"skjul_person": "-1"}])
def test_argumenter(db, over):
    proc = _run(db, **({"fase": "d"} | over))
    assert proc.returncode != 0 and "T6D3_MAAL_ARGS" in proc.stderr, proc.stderr
    assert "T6D3_MAAL " not in proc.stdout


def test_kanonisk_json_paritet(db):
    """SQL'ens private.reimport_canonical_json_sha256 = Pythons json.dumps(ensure_ascii=False, sort_keys=True,
    separators=(",", ":")) for et vanskeligt objekt (non-ASCII, null, escapes, kontroltegn, non-BMP, negative tal)."""
    obj = {"narrativ": None, "klausuler": ["Æble ø å °", '"citat" \\ back', "linje\nskift\ttab", "kontrol \x01 og \x1f",
                                           "ls   ps  ", "non-BMP \U0001F600", ""],
           "tal": -630216, "tom": [], "obj": {"z": True, "a": False, "m": None}}
    py = hashlib.sha256(json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    sql = _must(_psql("-v", "p=" + json.dumps(obj), db=db,
                      stdin="\\encoding UTF8\nSELECT private.reimport_canonical_json_sha256(:'p'::jsonb);\n"), "paritet")
    assert sql.strip() == py


def _code(path: Path) -> str:
    return re.sub(r"--[^\n]*", "", path.read_text(encoding="utf-8"))


def test_maal_er_laese_kun_og_viser_kun_en_linje():
    sql = MAAL.read_text(encoding="utf-8")
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    code = _code(MAAL)
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|CREATE)\s", code)
    assert len(re.findall(r"^SELECT format\(", code, re.M)) == 1
    assert not re.search(r"\b\d{4,}\b", code)


@pytest.mark.parametrize("path", [MAAL, D_SQL, O_SQL])
def test_ingen_udgaver_eller_id_literaler(path):
    code = _code(path)
    assert not re.search(r"'1939'|'2018-20'|source_id\s*=\s*-?\d|subjekt_id\s*=\s*-?\d|\bid\s*=\s*-?\d", code)
    assert not re.search(r"(?<![\w{])-?\d{3,}\b(?!\s*min)", code.replace("family_id_1939", "")), path.name


def _blok(path: Path, start: str, slut: str) -> str:
    s = path.read_text(encoding="utf-8")
    i, j = s.index(start), s.index(slut)
    return re.sub(r"\s+", " ", s[s.index("\n", i):j]).strip().rstrip(";").strip()


def test_kanon_er_samme_udtryk_i_maal_og_ceremoni():
    assert _blok(MAAL, "-- BEGIN kanon", "-- END kanon") == _blok(D_SQL, "-- BEGIN kanon", "-- END kanon")


def test_filvalideringen_er_ens_i_d_og_o():
    start, slut = "CREATE FUNCTION pg_temp.t6d3_filer", "END $f$;"
    d = D_SQL.read_text(encoding="utf-8")
    o = O_SQL.read_text(encoding="utf-8")
    fd = d[d.index(start):d.index(slut, d.index(start))]
    fo = o[o.index(start):o.index(slut, o.index(start))]
    assert fd == fo
