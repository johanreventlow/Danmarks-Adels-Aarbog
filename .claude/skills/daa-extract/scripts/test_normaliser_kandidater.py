"""Trin 6c-2 slutreview, fix B: normaliser_kandidater.sql (hash-bundet GO-liste over §4.3's datoversioner) og dens
runnerkontrakt mod en lokal fixturebase.

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; basen oprettes af testen (t6c2_sr2_<pid>) og droppes kun,
hvis testen selv oprettede den. Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true) fejler den.
Alt er syntetisk, og scriptet viser kun tal, id'er, versioner og en hash. Fixturen skriver direkte
(session_replication_role=replica); kontrakttesten kalder den rigtige red_normaliser_forslag uden replica.

Modulets tests deler basen og koerer i filens raekkefoelge: den sidste test committer ceremonien.
"""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parents[3]
KANDIDATER = SCRIPTS / "normaliser_kandidater.sql"
LISTE = SCRIPTS / "normaliser_kandidat_liste.sql"
DB = f"t6c2_sr2_{os.getpid()}"

SRC = -6395      # kilden under maaling (gives eksplicit; standarden er 3)
OTHER = -6396    # en anden kilde
RUN_S = "12000000-0000-0000-0000-000000069001"
RUN_O = "12000000-0000-0000-0000-000000069002"
ACTOR = "12000000-0000-0000-0000-000000069004"
METHOD = "deterministisk-normalisering:dato-markoer-v1"

LINE = re.compile(r"T6C2_NORMALISER antal=(\d+) kandidater_sha256=([0-9a-f]{64})")
ELEM = re.compile(r"([0-9a-f-]{36})\|(\d+)")


def _u(n: int) -> str:
    return f"12000000-0000-0000-0000-{n:012d}"


# Forslag (n -> kilde, praedikat, vaerdi, status): kandidater er 1-3.
#   1 SRC birth 'f. 12. marts 1750'   kandidat (markoer)
#   2 SRC death '† 10. maj 1770'      kandidat (markoer)
#   3 SRC birth '11. maj\n1771'        kandidat (blanktegn samles)
#   4 SRC birth '12. marts 1751'      allerede normal
#   5 SRC name  'f. Anna'             ikke et datoprædikat
#   6 SRC title '† Testtitel'         ikke et datoprædikat
#   7 SRC birth 'f. 1760'             accepted, ikke proposed
#   8 OTHER birth 'f. 1790'           anden kilde
#   9 SRC birth {"raw":"f. 1800"}     ikke en streng
KANDIDAT_ID = {_u(69401), _u(69402), _u(69403)}


def _psql(*args: str, db: str | None = None, stdin: str | None = None) -> subprocess.CompletedProcess:
    cmd = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"] + (["-d", db] if db else []) + list(args)
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=ROOT)


def _must(proc: subprocess.CompletedProcess, what: str) -> str:
    assert proc.returncode == 0, f"{what} fejlede: {proc.stderr[-1500:]}"
    return proc.stdout


def _sql(db: str, sql: str, what: str = "fixture") -> None:
    _must(_psql(db=db, stdin="\\set ON_ERROR_STOP on\nSET session_replication_role = replica;\n" + sql), what)


def _lit(value: str) -> str:
    return "E'" + value.replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n") + "'"


def _interp(n: int, source: int, persona: str, predicate: str, value_sql: str, run: str, status: str = "proposed",
            version: int = 1, supersedes: str | None = None, iid: str | None = None) -> str:
    audit = ("NULL,NULL,NULL,'{}'" if status == "proposed"
             else f"'{ACTOR}','fixture',now(),'{{\"basis\":\"fixture\"}}'")
    sup = "NULL" if supersedes is None else f"'{supersedes}'"
    return (f"INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,"
            f"interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,"
            f"extraction_run_id,supersedes_id,decided_by,decided_by_name,decided_at,decision_evidence) VALUES "
            f"('{iid or _u(69400 + n)}','{_u(69500 + n)}',{version},{source},'{persona}','property','{predicate}',"
            f"{value_sql},'fixture','source_statement',1,'{status}','fixture','{run}',{sup},{audit});\n")


def _s(value: str) -> str:
    return f"to_jsonb({_lit(value)}::text)"


_OBS_S = _u(69704)
_SETUP = (
    f"INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({SRC},'Fixture sr2','synthetic','1900','DAA-udgave'),"
    f"({OTHER},'Fixture sr2 anden','synthetic','1901','DAA-udgave');\n"
    "INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,"
    "input_sha256,manifest) VALUES "
    f"('{RUN_S}',{SRC},'sr2-s','fixture','fixture','fixture',repeat('1',64),'{{}}'),"
    f"('{RUN_O}',{OTHER},'sr2-o','fixture','fixture','fixture',repeat('1',64),'{{}}');\n"
    # kildens observationskaede (red_normaliser_forslag kopierer observationslinks; kilden skal passe)
    f"INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES "
    f"('{_u(69702)}',{SRC},'sr2-rendition','text_layer',repeat('8',64),'{{}}');\n"
    "INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,"
    "verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES "
    f"('{_u(69703)}','{_u(69702)}','sr2-occ',1,1,0,4,'1750','phys-sr2','struct-sr2','{RUN_S}');\n"
    "INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,"
    "verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES "
    f"('{_OBS_S}','{_u(69703)}','name_clause',1,1,0,4,'1750','clear','fixture','{RUN_S}');\n"
    f"INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES "
    f"('{_u(69101)}',{SRC},'sr2:s1','{RUN_S}'),('{_u(69201)}',{OTHER},'sr2:o1','{RUN_O}');\n"
    + _interp(1, SRC, _u(69101), "person.birth", _s("f. 12. marts 1750"), RUN_S)
    + _interp(2, SRC, _u(69101), "person.death", _s("† 10. maj 1770"), RUN_S)
    + _interp(3, SRC, _u(69101), "person.birth", _s("11. maj\n1771"), RUN_S)
    + _interp(4, SRC, _u(69101), "person.birth", _s("12. marts 1751"), RUN_S)
    + _interp(5, SRC, _u(69101), "person.name", _s("f. Anna"), RUN_S)
    + _interp(6, SRC, _u(69101), "person.title", _s("† Testtitel"), RUN_S)
    + _interp(7, SRC, _u(69101), "person.birth", _s("f. 1760"), RUN_S, status="accepted")
    + _interp(8, OTHER, _u(69201), "person.birth", _s("f. 1790"), RUN_O)
    + _interp(9, SRC, _u(69101), "person.birth", "'{\"raw\":\"f. 1800\"}'::jsonb", RUN_S)
    + "INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) "
    f"SELECT id,'{_OBS_S}','supporting',1 FROM private.interpretation WHERE source_id={SRC};\n"
)


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
        _sql(DB, _SETUP, "setup")
        yield DB
    finally:
        # kun basen, testen selv oprettede ovenfor (pid-navngivet)
        subprocess.run(["dropdb", DB], capture_output=True)


def _kandidater(db: str, source: int = SRC) -> subprocess.CompletedProcess:
    return _psql("-v", f"source_id={source}", "-f", str(KANDIDATER), db=db)


def _liste(db: str) -> tuple[int, str, list[tuple[str, int]]]:
    out = _must(_kandidater(db), "normaliser_kandidater").splitlines()
    g = LINE.fullmatch(out[0])
    assert g, out[0]
    elems = []
    for x in out[1:]:
        m = ELEM.fullmatch(x)
        assert m, "linjen er ikke <uuid>|<version>"
        elems.append((m.group(1), int(m.group(2))))
    assert int(g.group(1)) == len(elems)
    return int(g.group(1)), g.group(2), elems


def _sha(elems: list[tuple[str, int]]) -> str:
    return hashlib.sha256(",".join(f"{i}:{v}" for i, v in elems).encode("utf-8")).hexdigest()


def _blok(navn: str) -> str:
    """En af headerens ordrette kontraktblokke ([koersel], [efterkontrol]) uden kommentarpræfiks."""
    tekst = KANDIDATER.read_text(encoding="utf-8")
    m = re.search(rf"^-- \[{navn}\]\n(.*?)^-- \[/{navn}\]$", tekst, re.S | re.M)
    assert m, navn
    return "\n".join(x[3:] if x.startswith("-- ") else x[2:] for x in m.group(1).splitlines()) + "\n"


def test_scriptet_er_laese_kun_og_uden_fast_kilde():
    for f in (KANDIDATER, LISTE):
        sql = f.read_text(encoding="utf-8")
        body = re.sub(r"--[^\n]*", "", sql)
        if f is KANDIDATER:
            assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql and "\\set source_id 3" in sql
        assert not re.search(r"\b(INSERT|UPDATE|DELETE|COPY)\s", body), f.name
        assert not re.search(r"source_id\s*(=|IN)\s*\(?\s*-?\d", body), f.name
    # runnerkontrakten: nulstilling før hvert kald og kasseret kvittering (også i linjeskift-headeren)
    for f in (KANDIDATER, SCRIPTS / "linjeskift_kandidater.sql"):
        sql = f.read_text(encoding="utf-8")
        assert "set_config('app.change_set_id','',true)" in sql and "kvittering" in sql, f.name


def test_afgraensning_og_format(db):
    n, sha, elems = _liste(db)
    assert {i for i, _ in elems} == KANDIDAT_ID          # f./†/blanktegn med; normal, ikke-dato, accepted, anden kilde
    assert all(v == 1 for _, v in elems)                  # og objektværdi ude
    assert [i for i, _ in elems] == sorted(i for i, _ in elems)
    assert sha == _sha(elems) and n == 3


def test_standardkilden_er_3(db):
    out = _must(_psql("-f", str(KANDIDATER), db=db), "standard").splitlines()
    assert out == [f"T6C2_NORMALISER antal=0 kandidater_sha256={hashlib.sha256(b'').hexdigest()}"]


def test_sha_er_stabil_og_foelger_versionen(db):
    _, sha1, elems1 = _liste(db)
    assert _liste(db)[1] == sha1
    ny = _u(69412)
    _sql(db, _interp(2, SRC, _u(69101), "person.death", _s("† 10. maj 1770"), RUN_S, version=2,
                     supersedes=_u(69402), iid=ny))
    try:
        _, sha2, elems2 = _liste(db)
        assert (ny, 2) in elems2 and (_u(69402), 1) not in elems2
        assert sha2 != sha1 and sha2 == _sha(elems2)
    finally:
        _sql(db, f"DELETE FROM private.interpretation WHERE id='{ny}';\n", "oprydning")
    assert _liste(db)[1] == sha1


def test_tom_vaerdi_stopper_listen(db):
    tom = _u(69420)
    _sql(db, f"INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,"
             f"interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,"
             f"extraction_run_id) VALUES ('{tom}','{_u(69520)}',1,{SRC},'{_u(69101)}','property','person.birth',"
             f"to_jsonb('†'::text),'fixture','source_statement',1,'proposed','fixture','{RUN_S}');\n")
    try:
        p = _kandidater(db)
        assert p.returncode != 0 and "NORMALISER_VAERDI_TOM: 1 " in p.stderr and p.stdout == ""
    finally:
        _sql(db, f"DELETE FROM private.interpretation WHERE id='{tom}';\n", "oprydning")


def _ceremoni(go: str, go_sha: str, kald: list[tuple[str, int]], slut: str) -> str:
    """Runnerkontrakten (a)-(d) som psql-input; kald = de elementer, der faktisk kaldes."""
    calls = "".join("SELECT set_config('app.change_set_id','',true) \\g /dev/null\n"
                    f"SELECT public.red_normaliser_forslag('{i}'::uuid,{v},'dato-markoer-v1') \\g /dev/null\n"
                    for i, v in kald)
    return (
        "\\set ON_ERROR_STOP on\n\\set QUIET on\nBEGIN;\n"
        f"INSERT INTO auth.users(id,email) VALUES ('{ACTOR}','sr2@invalid') ON CONFLICT DO NOTHING;\n"
        f"INSERT INTO public.profiles(id,rolle,navn,email) VALUES ('{ACTOR}','redaktion','sr2','sr2@invalid') "
        "ON CONFLICT DO NOTHING;\n"
        # (a) genkør kandidatsættet og kræv identisk liste og sha
        f"SELECT set_config('daa.normaliser_kilde','{SRC}',true) \\g /dev/null\n"
        f"\\i {LISTE}\n"
        f"SELECT set_config('daa.normaliser_go','{go}',true) \\g /dev/null\n"
        f"SELECT set_config('daa.normaliser_go_sha','{go_sha}',true) \\g /dev/null\n"
        "DO $a$ BEGIN IF current_setting('daa.normaliser_kandidater')<>current_setting('daa.normaliser_go') "
        "OR current_setting('daa.normaliser_kandidater_sha256')<>current_setting('daa.normaliser_go_sha') THEN "
        "RAISE EXCEPTION 'NORMALISER_GO_DRIFT'; END IF; END $a$;\n"
        # (b) ceremoniens extraction_run (uden request.jwt.claim.sub), ordret fra headeren
        + _blok("koersel")
        # (c) kaldene
        + f"SELECT set_config('request.jwt.claim.sub','{ACTOR}',true) \\g /dev/null\n"
        "SET LOCAL ROLE authenticated;\n" + calls + "RESET ROLE;\n"
        # (d) efterkontrollen, ordret fra headeren
        + _blok("efterkontrol") + slut + "\n"
    )


def test_efterkontrollen_afviser_et_manglende_kald(db):
    _, sha, elems = _liste(db)
    go = ",".join(f"{i}:{v}" for i, v in elems)
    p = _psql(db=db, stdin=_ceremoni(go, sha, elems[:-1], "ROLLBACK;"))
    assert p.returncode != 0 and "NORMALISER_EFTERKONTROL: 2 af 3 elementer" in p.stderr, p.stderr[-800:]
    p = _psql(db=db, stdin=_ceremoni(go, "0" * 64, elems, "ROLLBACK;"))
    assert p.returncode != 0 and "NORMALISER_GO_DRIFT" in p.stderr, p.stderr[-800:]
    assert _liste(db)[2] == elems


def test_kontrakten_kalder_red_normaliser_forslag_og_listen_toemmes(db):
    _, sha, elems = _liste(db)
    go = ",".join(f"{i}:{v}" for i, v in elems)
    p = _psql(db=db, stdin=_ceremoni(go, sha, elems, "COMMIT;"))
    assert p.returncode == 0, p.stderr[-1500:]
    assert p.stdout == ""                                   # kvitteringerne er kasseret; intet ud
    assert _liste(db) == (0, hashlib.sha256(b"").hexdigest(), [])
    out = _must(_psql("-c", (
        "SELECT count(*) FILTER (WHERE c.method='" + METHOD + "' AND c.version=2 AND c.supersedes_id=o.id),"
        " count(DISTINCT c.extraction_run_id), min(r.run_key)='normalisering:dato-markoer-v1:" + sha + "',"
        " min(r.input_sha256)='" + sha + "', min((r.manifest->>'antal')::int)"
        " FROM private.interpretation o JOIN private.interpretation_current c ON c.interpretation_key=o.interpretation_key"
        " JOIN private.extraction_run r ON r.id=c.extraction_run_id"
        f" WHERE o.id IN ({','.join(repr(i) for i, _ in elems)})"), db=db), "efter").strip()
    assert out == "3|1|t|t|3", out
    # observationslinks kopieret, og forslag uden for listen er urørte
    out = _must(_psql("-c", (
        "SELECT (SELECT count(*) FROM private.interpretation_observation io JOIN private.interpretation i"
        f" ON i.id=io.interpretation_id WHERE i.method='{METHOD}'),"
        f" (SELECT count(*) FROM private.interpretation WHERE version>1 AND method<>'{METHOD}')"), db=db), "links").strip()
    assert out == "3|0", out
