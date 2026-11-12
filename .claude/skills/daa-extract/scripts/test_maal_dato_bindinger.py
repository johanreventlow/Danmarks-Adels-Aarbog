"""maal_dato_bindinger.sql mod en lokal fixturebase (skabelon: test_maal_trin6c2.py).

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; basen oprettes af testen (t3dato_<pid>) og droppes kun,
hvis testen selv oprettede den. Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true) fejler den.
Alt er syntetisk, og scriptet viser kun tal og hashes. Fixturen skriver direkte (session_replication_role=replica).
public.public_person_facts erstattes i fixturebasen af en stub over en fixturetabel (den rigtige kraever en hel
narrativ-publiceringskaede for at give et record_label); testen proever dermed taellelogikken, ikke labelkaeden.
Modulets tests deler basen og koerer i filens raekkefoelge.
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
MAAL = SCRIPTS / "maal_dato_bindinger.sql"
DB = f"t3dato_{os.getpid()}"

SRC = -7390
OTHER = -7391
RUN_S = "12000000-0000-0000-0000-000000079001"
RUN_O = "12000000-0000-0000-0000-000000079002"
ACTOR = "12000000-0000-0000-0000-000000079004"
V2 = "deterministisk-normalisering:dato-markoer-v2"

# P1 fødsel (MATCH efter samling af blanktegn), P7 reel forskel, P9 navn (MATCH, men ikke birth/death),
# P10 død (v2-kandidat), P5 den anden kildes gyldige binding.
P = {n: -7390 - n for n in (1, 5, 7, 9, 10, 11)}
A = {"p1": -79001, "p5": -79006, "p7": -79008, "p9": -79010, "p10": -79011, "o8": -79020}

LINE = re.compile(r"DATO_MAAL tilstand=(foer|ddl|n|k) versioner_v2=(\d+) match=(\d+) real_diff=(\d+) skrivemaade=(\d+) "
                  r"accepteret_v2=(\d+) bundet_v2=(\d+) post_foedsel=(\d+) post_doed=(\d+) alle_bindinger=(\d+) "
                  r"alle_bindinger_hash=([0-9a-f]{64})")


def _psql(*args: str, db: str | None = None, stdin: str | None = None) -> subprocess.CompletedProcess:
    cmd = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"] + (["-d", db] if db else []) + list(args)
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=ROOT)


def _must(proc: subprocess.CompletedProcess, what: str) -> str:
    assert proc.returncode == 0, f"{what} fejlede: {proc.stderr[-1500:]}"
    return proc.stdout


def _sql(db: str, sql: str, what: str = "fixture") -> str:
    return _must(_psql(db=db, stdin="\\set ON_ERROR_STOP on\nSET session_replication_role = replica;\n" + sql), what)


def _u(n: int) -> str:
    return f"12000000-0000-0000-0000-{n:012d}"


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
        subprocess.run(["dropdb", DB], capture_output=True)  # kun basen, testen selv oprettede (pid-navngivet)


def _persona(pid_uuid: str, source: int, run: str, key: str, person: int) -> str:
    return (f"INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES "
            f"('{pid_uuid}',{source},'{key}','{run}');\n"
            f"INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,"
            f"evidence,decided_by,decided_by_name,decided_at) VALUES ('{pid_uuid}',{person},'accepted',1,"
            f"'{{\"fixture\":\"t3\"}}','{ACTOR}','fixture',now());\n")


def _fact(person: int, aid: int, faktatype: str, raw: str, source: int, kind: str = "date_raw") -> str:
    col = "date_raw" if kind == "date_raw" else "vaerdi_tekst"
    lit = "E'" + raw.replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n") + "'"
    return (f"INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES ({aid},'person',{person},'{faktatype}');\n"
            f"INSERT INTO public.assertion(id,target_type,target_id,{col}) VALUES ({aid},'fact',{aid},{lit});\n"
            f"INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) "
            f"VALUES ('fact',{aid},{aid},'afklaret');\n"
            f"INSERT INTO public.citation(assertion_id,source_id,side) VALUES ({aid},{source},'1');\n")


def _interp(iid: str, key: str, version: int, source: int, persona: str, predicate: str, value: str, run: str,
            status: str = "proposed", method: str = "fixture", supersedes: str | None = None) -> str:
    val = "to_jsonb(E'" + value.replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n") + "'::text)"
    audit = ("NULL,NULL,NULL,'{}'" if status == "proposed"
             else f"'{ACTOR}','fixture',now(),'{{\"basis\":\"fixture\"}}'")
    sup = "NULL" if supersedes is None else f"'{supersedes}'"
    return (f"INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,"
            f"interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,"
            f"extraction_run_id,supersedes_id,decided_by,decided_by_name,decided_at,decision_evidence) VALUES "
            f"('{iid}','{key}',{version},{source},'{persona}','property','{predicate}',{val},'fixture','source_statement',"
            f"1,'{status}','{method}','{run}',{sup},{audit});\n")


def _promo(pid: str, iid: str, rule: str, target_id: int) -> str:
    return (f"INSERT INTO private.interpretation_promotion(id,interpretation_id,rule_key,rule_version,target_type,"
            f"target_id,evidence,promoted_by,promoted_by_name) VALUES ('{pid}','{iid}','{rule}',1,'assertion',{target_id},"
            f"'{{\"fixture\":\"t3\"}}','{ACTOR}','fixture');\n")


_SETUP = (
    f"INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({SRC},'Fixture dato','synthetic','1900','DAA-udgave'),"
    f"({OTHER},'Fixture anden','synthetic','1901','DAA-udgave');\n"
    "INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,"
    "input_sha256,manifest) VALUES "
    f"('{RUN_S}',{SRC},'t3-s','fixture','fixture','fixture',repeat('1',64),'{{}}'),"
    f"('{RUN_O}',{OTHER},'t3-o','fixture','fixture','fixture',repeat('1',64),'{{}}');\n"
    "INSERT INTO public.person(id,levende,privat,status) VALUES " + ",".join(f"({p},false,false,'t3')" for p in P.values()) + ";\n"
    + "".join(_persona(_u(79100 + n), SRC, RUN_S, f"t3:s{n}", P[n]) for n in (1, 7, 9, 10))
    + _persona(_u(79205), OTHER, RUN_O, "t3:o5", P[5])
    + _fact(P[1], A["p1"], "fødsel", "12. marts 1750", SRC)
    + _fact(P[7], A["p7"], "fødsel", "7. maj\n1766", SRC)
    + _fact(P[9], A["p9"], "navn", "Anna", SRC, kind="text")
    + _fact(P[10], A["p10"], "død", "10. maj 1770", SRC)
    + _fact(P[5], A["p5"], "fødsel", "4. maj 1763", OTHER)
    + _interp(_u(79401), _u(79501), 1, SRC, _u(79101), "person.birth", "12. marts 1750", RUN_S)
    + _interp(_u(79407), _u(79507), 1, SRC, _u(79107), "person.birth", "8. juni 1799", RUN_S)
    + _interp(_u(79409), _u(79509), 1, SRC, _u(79109), "person.name", "Anna", RUN_S)
    + _interp(_u(79410), _u(79510), 1, SRC, _u(79110), "person.death", "† 10. maj 1770", RUN_S)
    + _interp(_u(79415), _u(79515), 1, OTHER, _u(79205), "person.birth", "4. maj 1763", RUN_O, status="accepted")
    + _promo(_u(79605), _u(79415), "person-birth-v1", A["p5"])
    # stub for public_person_facts: samme signatur, raekker fra en fixturetabel
    + "CREATE TABLE public.t3_pff (person_id bigint, fact_id bigint, faktatype text, conclusion_status text, "
      "assertion_id bigint, chosen boolean, vaerdi_tekst text, date_raw text, date_min date, date_max date, "
      "date_qualifier text, date_certainty text, source_id bigint, source_label text, side text, record_ref uuid, "
      "record_label text, citation_label text);\n"
      "CREATE OR REPLACE FUNCTION public.public_person_facts(p_person_ids bigint[])\n"
      "RETURNS TABLE(person_id bigint, fact_id bigint, faktatype text, conclusion_status text, assertion_id bigint,\n"
      "  chosen boolean, vaerdi_tekst text, date_raw text, date_min date, date_max date, date_qualifier text,\n"
      "  date_certainty text, source_id bigint, source_label text, side text, record_ref uuid, record_label text,\n"
      "  citation_label text) LANGUAGE sql STABLE AS $$ SELECT * FROM public.t3_pff t "
      "WHERE t.person_id = ANY(p_person_ids) $$;\n"
)


def _maal(db: str, source: int = SRC) -> tuple:
    r = _psql("-v", f"source_id={source}", "-f", str(MAAL), db=db)
    out = _must(r, "maal").strip()
    assert "\n" not in out, out
    g = LINE.fullmatch(out)
    assert g, out
    return g.groups()


def _hash(pairs: list[tuple[int, str]]) -> str:
    # sorteret paa (assertion_id som tal, noegle som uuid-tekst = byteorden); linjer forbundet med linjeskift
    body = "\n".join(f"{a}:{k}" for a, k in sorted(pairs))
    return hashlib.sha256(body.encode()).hexdigest()


def _rename_v2(db: str, skjul: bool) -> None:
    a, b = ("normaliser_dato_markoer_v2", "normaliser_dato_markoer_v2_t3skjult")
    if not skjul:
        a, b = b, a
    _must(_psql("-c", f"ALTER FUNCTION private.{a}(text,text) RENAME TO {b}", db=db), "rename")


def test_scriptet_er_laese_kun_og_uden_fast_kilde():
    sql = MAAL.read_text(encoding="utf-8")
    body = re.sub(r"--[^\n]*", "", sql)
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|COPY)\s", body)
    assert not re.search(r"source_id\s*(=|IN)\s*\(?\s*-?\d", body)


def test_tilstande_foer_ddl_n_k_og_hashen(db):
    # foer: funktionen findes ikke
    _rename_v2(db, True)
    try:
        foer = _maal(db)
    finally:
        _rename_v2(db, False)
    assert foer[0] == "foer"
    # ddl: funktionen findes, ingen v2-version. Klasserne er kun birth/death: P1 MATCH, P7 REAL_DIFF, P10 SKRIVEMAADE
    # (markøren); navnet (MATCH) tælles ikke.
    ddl = _maal(db)
    assert ddl[:10] == ("ddl", "0", "1", "1", "1", "0", "0", "0", "0", "1"), ddl
    p5 = (A["p5"], _u(79515))
    assert ddl[10] == _hash([p5]) and foer[10] == ddl[10]
    # n: P10's død normaliseres med v2 (version 2) og bliver MATCH; ingen er accepteret
    _sql(db, _interp(_u(79420), _u(79510), 2, SRC, _u(79110), "person.death", "10. maj 1770", RUN_S,
                     method=V2, supersedes=_u(79410)))
    n = _maal(db)
    assert n[:10] == ("n", "1", "2", "1", "0", "0", "0", "0", "0", "1"), n
    # k: afgørelsen kopierer method; den er accepteret, men endnu ikke bundet
    _sql(db, _interp(_u(79430), _u(79510), 3, SRC, _u(79110), "person.death", "10. maj 1770", RUN_S, status="accepted",
                     method=V2, supersedes=_u(79420)))
    k = _maal(db)
    assert k[:10] == ("k", "1", "1", "1", "0", "1", "0", "0", "0", "1"), k
    assert k[10] == ddl[10]
    # bundet: en ny gyldig binding giver bundet_v2=1, alle_bindinger=2 og en ny hash
    _sql(db, _promo(_u(79630), _u(79430), "person-death-v1", A["p10"]))
    b = _maal(db)
    assert b[:10] == ("k", "1", "1", "1", "0", "1", "1", "0", "0", "2"), b
    assert b[10] == _hash([p5, (A["p10"], _u(79510))]) and b[10] != k[10]
    # den anden kildes bindinger tæller ikke i kildens bundet_v2, men indgår i alle_bindinger
    o = _maal(db, OTHER)
    assert o[0] == "ddl" and o[1] == "0", o
    assert o[6] == "0" and o[9] == "2" and o[10] == b[10]
    # en binding, der bliver ugyldig (værdien matcher ikke længere), falder ud af tal og hash
    _sql(db, f"UPDATE public.assertion SET date_raw='11. maj 1770' WHERE id={A['p10']};")
    try:
        u = _maal(db)
        assert u[6] == "0" and u[9] == "1" and u[10] == ddl[10], u
        # lig funktionen: den siger også ugyldig
        assert _must(_psql("-c", f"SELECT private.assertion_binding_current('{_u(79630)}')", db=db), "fn").strip() == "f"
    finally:
        _sql(db, f"UPDATE public.assertion SET date_raw='10. maj 1770' WHERE id={A['p10']};")
    assert _must(_psql("-c", f"SELECT private.assertion_binding_current('{_u(79630)}')", db=db), "fn").strip() == "t"
    assert _maal(db) == b


def test_hashen_er_uaendret_naar_den_anden_kildes_data_aendres_uden_bindinger(db):
    before = _maal(db)
    _sql(db, _persona(_u(79208), OTHER, RUN_O, "t3:o8", P[11])
         + _fact(P[11], A["o8"], "fødsel", "9. maj 1767", OTHER)
         + _interp(_u(79408), _u(79508), 1, OTHER, _u(79208), "person.birth", "9. maj 1767", RUN_O))
    after = _maal(db)
    assert after[9:] == before[9:]
    assert after[2] == before[2]  # kildens egne klassetal er uroerte
    o = _maal(db, OTHER)
    assert o[2] == "1"  # den anden kildes nye forslag er MATCH for den kilde


def test_post_taeller_kun_raekker_med_record_label(db):
    def row(person: int, ft: str, src: int, label: str | None) -> str:
        lab = "NULL" if label is None else f"'{label}'"
        return (f"INSERT INTO public.t3_pff(person_id,fact_id,faktatype,assertion_id,source_id,record_label) "
                f"VALUES ({person},1,'{ft}',1,{src},{lab});")
    _sql(db, "\n".join([row(P[1], "fødsel", SRC, "r1"), row(P[7], "fødsel", SRC, "r2"), row(P[9], "fødsel", SRC, None),
                        row(P[10], "død", SRC, "r3"), row(P[10], "død", SRC, None),
                        row(P[5], "fødsel", OTHER, "r4"), row(P[5], "navn", SRC, "r5")]))
    m = _maal(db)
    assert (m[7], m[8]) == ("2", "1"), m
    o = _maal(db, OTHER)
    assert (o[7], o[8]) == ("1", "0"), o
    out = _must(_psql("-v", f"source_id={SRC}", "-f", str(MAAL), db=db), "maal")
    assert "r1" not in out and "marts" not in out
