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

LINE = re.compile(r"DATO_MAAL tilstand=(foer|ddl|n|k) versioner_v2=(\d+) match=(\d+) real_diff=(\d+) skrivemaade=(\d+) no_fact=(\d+) "
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
    assert ddl[:11] == ("ddl", "0", "1", "1", "1", "0", "0", "0", "0", "0", "1"), ddl
    p5 = (A["p5"], _u(79515))
    assert ddl[11] == _hash([p5]) and foer[11] == ddl[11]
    # n: P10's død normaliseres med v2 (version 2) og bliver MATCH; ingen er accepteret
    _sql(db, _interp(_u(79420), _u(79510), 2, SRC, _u(79110), "person.death", "10. maj 1770", RUN_S,
                     method=V2, supersedes=_u(79410)))
    n = _maal(db)
    assert n[:11] == ("n", "1", "2", "1", "0", "0", "0", "0", "0", "0", "1"), n
    # k: afgørelsen kopierer method; versioner_v2 (kun proposed) er uændret 1; den er accepteret, men endnu ikke bundet
    _sql(db, _interp(_u(79430), _u(79510), 3, SRC, _u(79110), "person.death", "10. maj 1770", RUN_S, status="accepted",
                     method=V2, supersedes=_u(79420)))
    k = _maal(db)
    assert k[:11] == ("k", "1", "1", "1", "0", "0", "1", "0", "0", "0", "1"), k
    assert k[11] == ddl[11]
    # bundet: en ny gyldig binding giver bundet_v2=1, alle_bindinger=2 og en ny hash
    _sql(db, _promo(_u(79630), _u(79430), "person-death-v1", A["p10"]))
    b = _maal(db)
    assert b[:11] == ("k", "1", "1", "1", "0", "0", "1", "1", "0", "0", "2"), b
    assert b[11] == _hash([p5, (A["p10"], _u(79510))]) and b[11] != k[11]
    # den anden kildes bindinger tæller ikke i kildens bundet_v2, men indgår i alle_bindinger
    o = _maal(db, OTHER)
    assert o[0] == "ddl" and o[1] == "0", o
    assert o[7] == "0" and o[10] == "2" and o[11] == b[11]
    # en binding, der bliver ugyldig (værdien matcher ikke længere), falder ud af tal og hash
    _sql(db, f"UPDATE public.assertion SET date_raw='11. maj 1770' WHERE id={A['p10']};")
    try:
        u = _maal(db)
        assert u[7] == "0" and u[10] == "1" and u[11] == ddl[11], u
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
    assert after[10:] == before[10:]
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
    assert (m[8], m[9]) == ("2", "1"), m
    o = _maal(db, OTHER)
    assert (o[8], o[9]) == ("1", "0"), o
    out = _must(_psql("-v", f"source_id={SRC}", "-f", str(MAAL), db=db), "maal")
    assert "r1" not in out and "marts" not in out


# ---- låsning mod drift fra private.assertion_binding_current ----

def _norm(t: str) -> str:
    return " ".join(t.split())


def _function_from_where(sql: str, last: bool) -> str:
    start_pat = "CREATE OR REPLACE FUNCTION private.assertion_binding_current("
    i = sql.rindex(start_pat) if last else sql.index(start_pat)
    j = sql.index("REVOKE ALL ON FUNCTION private.assertion_binding_current", i)
    m = re.search(r"SELECT 1\s+(FROM .*?)\s*\)\s*\$\$", sql[i:j], re.S)
    assert m, "assertion_binding_current har aendret form"
    return _norm(m.group(1).replace("p.id=p_promotion_id AND", ""))


@pytest.mark.parametrize("fil,last", [("schema.sql", False), ("db-migrations.sql", True)])
def test_gyldighedsreglen_er_ordret_funktionens_from_where(fil, last):
    krop = _function_from_where((ROOT / fil).read_text(encoding="utf-8"), last)
    assert krop in _norm(MAAL.read_text(encoding="utf-8")), fil


def test_red_decide_interpretation_kopierer_method():
    sql = (ROOT / "schema.sql").read_text(encoding="utf-8")
    i = sql.index("CREATE OR REPLACE FUNCTION red_decide_interpretation(")
    j = sql.index("CREATE OR REPLACE FUNCTION", i + 10)
    assert "p_decision_status,v_current.method" in _norm(sql[i:j]).replace(", ", ",")


# ---- fixture-paritet: én binding pr. ugyldighedsgren ----

def _gren(n: int, *, faktatype: str = "fødsel", raw: str = "1. jan 1800", kind: str = "date_raw", rule: str = "person-birth-v1",
          rule_ver: int | str = 1, status: str = "accepted", identity: str = "ok", a_target: str = "fact",
          fact_raw: str | None = None, predicate: str = "person.birth", p_target: str = "assertion",
          nyere_afvist: bool = False) -> str:
    pers, aid = -8000 - n, -80000 - n
    persona, iid, key, promo = _u(80100 + n), _u(80400 + n), _u(80500 + n), _u(80600 + n)
    out = f"INSERT INTO public.person(id,levende,privat,status) VALUES ({pers},false,false,'t3'),({pers - 500},false,false,'t3');\n"
    out += (f"INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES ('{persona}',{SRC},'t3:g{n}','{RUN_S}');\n")
    if identity != "none":
        canon = pers if identity == "ok" else pers - 500
        out += (f"INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,"
                f"decided_by,decided_by_name,decided_at) VALUES ('{persona}',{canon},'accepted',1,'{{\"fixture\":\"t3\"}}','{ACTOR}','fixture',now());\n")
    out += _fact(pers, aid, faktatype, fact_raw if fact_raw is not None else raw, SRC, kind=kind)
    if a_target != "fact":
        out += f"UPDATE public.assertion SET target_type='{a_target}' WHERE id={aid};\n"
    out += _interp(iid, key, 1, SRC, persona, predicate, raw, RUN_S, status=status)
    if nyere_afvist:
        out += _interp(_u(80700 + n), key, 2, SRC, persona, predicate, raw, RUN_S, status="rejected", supersedes=iid)
    rk = "NULL,NULL" if rule is None else f"'{rule}',{rule_ver}"
    out += (f"INSERT INTO private.interpretation_promotion(id,interpretation_id,rule_key,rule_version,target_type,target_id,evidence,"
            f"promoted_by,promoted_by_name) VALUES ('{promo}','{iid}',{rk},'{p_target}',{aid},'{{\"fixture\":\"t3\"}}','{ACTOR}','fixture');\n")
    return out


# (nummer, gren, gyldig)
GRENE = [
    (1, {}, True),
    (2, dict(faktatype="navn", raw="Anna", kind="text", rule="person-name-v1", predicate="person.name"), True),
    (3, dict(nyere_afvist=True), False),            # fortolkningen er ikke længere aktuel
    (4, dict(status="proposed"), False),            # aktuel, men ikke accepted
    (5, dict(rule_ver=99), False),                  # regel-join mangler
    (6, dict(rule=None), False),                    # ingen regel
    (7, dict(a_target="relation"), False),          # påstandens target_type er ikke 'fact'
    (8, dict(faktatype="død"), False),              # faktatypen afviger fra reglens
    (9, dict(identity="none"), False),              # identitet kræves, men mangler
    (10, dict(identity="anden"), False),            # identiteten peger på et andet subjekt
    (11, dict(fact_raw="2. jan 1800"), False),      # værdien matcher ikke
    (12, dict(p_target="person"), False),           # promotionens target_type er ikke 'assertion'
]

PARITET = ("SELECT count(*), encode(sha256(convert_to(coalesce(string_agg(p.target_id::text||':'||q.interpretation_key::text,"
           "E'\\n' ORDER BY p.target_id,q.interpretation_key),''),'UTF8')),'hex') "
           "FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id "
           "WHERE p.target_type='assertion' AND private.assertion_binding_current(p.id)")


def test_maengdereglen_giver_samme_antal_og_hash_som_funktionen_pr_promotion(db):
    _sql(db, "".join(_gren(n, **kw) for n, kw, _ in GRENE))
    for n, _, gyldig in GRENE:
        r = _must(_psql("-c", f"SELECT private.assertion_binding_current('{_u(80600 + n)}')", db=db), "fn").strip()
        assert r == ("t" if gyldig else "f"), n
    antal, hsh = _must(_psql("-c", PARITET, db=db), "paritet").strip().split("|")
    m = _maal(db)
    assert (m[10], m[11]) == (antal, hsh)
    assert int(antal) >= 2 + sum(1 for *_, g in GRENE if g)


def _maal_liste(db: str) -> list[str]:
    r = _psql("-v", f"source_id={SRC}", "-v", "liste=1", "-f", str(MAAL), db=db)
    return _must(r, "maal liste").strip().split("\n")


def test_liste_giver_de_linjer_hashen_er_taget_over(db):
    ud = _maal_liste(db)
    g = LINE.fullmatch(ud[0])
    assert g
    linjer = ud[1:]
    assert len(linjer) == int(g.group(11))
    assert hashlib.sha256("\n".join(linjer).encode()).hexdigest() == g.group(12)
    assert all(re.fullmatch(r"-?\d+:[0-9a-f-]{36}", x) for x in linjer)
    # uden liste er outputtet præcis én linje
    assert "\n" not in _must(_psql("-v", f"source_id={SRC}", "-f", str(MAAL), db=db), "maal").strip()


def test_v2_version_afloest_af_ikke_v2_giver_ikke_ddl(db):
    kilde, run = -7392, "12000000-0000-0000-0000-000000079003"
    _sql(db, f"INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({kilde},'Fixture tredje','synthetic','1902','DAA-udgave');\n"
             f"INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)"
             f" VALUES ('{run}',{kilde},'t3-3','fixture','fixture','fixture',repeat('1',64),'{{}}');\n"
             f"INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES ('{_u(79300)}',{kilde},'t3:x','{run}');\n"
             + _interp(_u(79701), _u(79801), 1, kilde, _u(79300), "person.birth", "1. jan 1800", run, method=V2))
    assert _maal(db, kilde)[:2] == ("n", "1")
    _sql(db, _interp(_u(79702), _u(79801), 2, kilde, _u(79300), "person.birth", "1. jan 1800", run, status="rejected",
                     method="fixture", supersedes=_u(79701)))
    m = _maal(db, kilde)
    assert m[0] == "n" and m[1] == "1" and m[6] == "0", m


def test_no_fact_taelles_kun_for_birth_og_death(db):
    foer = _maal(db)
    assert foer[5] == "0", foer
    pers, persona = -7450, _u(79350)
    _sql(db, f"INSERT INTO public.person(id,levende,privat,status) VALUES ({pers},false,false,'t3');\n"
             + _persona(persona, SRC, RUN_S, "t3:nf", pers)
             + _interp(_u(79450), _u(79550), 1, SRC, persona, "person.birth", "1. jan 1700", RUN_S)
             + _interp(_u(79451), _u(79551), 1, SRC, persona, "person.name", "Ingen", RUN_S))
    efter = _maal(db)
    assert efter[5] == "1" and efter[2] == foer[2] and efter[3] == foer[3] and efter[4] == foer[4], (foer, efter)
