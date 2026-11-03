"""Trin 6c-2 Task 9: maal_trin6c2.sql, linjeskift_kandidater.sql og vejb_tid.sql mod en lokal fixturebase.

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; basen oprettes af testen (t6c2_t9_<pid>) og droppes kun,
hvis testen selv oprettede den. Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true) fejler den.
Alt er syntetisk, og scripts viser kun tal, id'er og hashes. Fixturen skriver direkte
(session_replication_role=replica) i stedet for gennem writerne.

Modulets tests deler basen og koerer i filens raekkefoelge: tilstandstesten efterlader basen i tilstand d.
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
MAAL = SCRIPTS / "maal_trin6c2.sql"
LINJESKIFT = SCRIPTS / "linjeskift_kandidater.sql"
FORVENTET = SCRIPTS / "linjeskift_forventet.sql"
KANDIDAT_PAR = SCRIPTS / "linjeskift_kandidat_par.sql"
VEJB = SCRIPTS / "vejb_tid.sql"
DB = f"t6c2_t9_{os.getpid()}"

SRC = -6390      # kilden under maaling (gives eksplicit; standarden er 3)
OTHER = -6391    # en anden kilde (delt citation, egen binding, eget forslag)
K1 = 1           # 2018-20 (k1_bindinger_hash)
RUN_S = "11000000-0000-0000-0000-000000069001"
RUN_O = "11000000-0000-0000-0000-000000069002"
RUN_1 = "11000000-0000-0000-0000-000000069003"
ACTOR = "11000000-0000-0000-0000-000000069004"

# personer: P1 almindelig kandidat, P2 delt citation, P3 to maal, P4 to forslag paa samme paastand, P5 gyldig binding
# der ville brydes, P6 intet blanktegn at rette, P7 reel forskel, P8 kun den anden kildes forslag, P9 navn (bindes i d),
# P10 doedsdato, der faar en dato-markoer-version i c, P11 forslaget er lig den raa vaerdi (ikke den samlede),
# PK kilde 1's binding.
P = {n: -6390 - n for n in range(1, 12)}
PK = -6411
# paastands-id'er (faste, saa forventningerne kan staa i testen)
A = {"p1": -69001, "p2": -69002, "p3a": -69003, "p3b": -69004, "p4": -69005, "p5": -69006, "p6": -69007,
     "p7": -69008, "p8": -69009, "p9": -69010, "p10": -69011, "k1": -69012,
     "p11": -69013}

LINE = re.compile(r"T6C2_MAAL tilstand=(foer|a|b|c|d) forslag_k=(\d+) match=(\d+) skrivemaade=(\d+) real_diff=(\d+) "
                  r"accepteret_k=(\d+) bindinger_k=(\d+) rettelser=(\d+) unresolved_fra_kort=(\d+) "
                  r"k1_bindinger_hash=([0-9a-f]{64})")
LK_LINE = re.compile(r"T6C2_LINJESKIFT antal=(\d+) delstreng_i_tilstand=(\d+) forventet_sha256=([0-9a-f]{64}) "
                     r"graenser_udfyldt=(\d+) graenser_sha256=([0-9a-f]{64})")
PAR = re.compile(r"(-?\d+)\|([0-9a-f-]{36})")
VEJB_LINE = re.compile(r"T6C2_VEJB person=(-?\d+) ms=(\d+)")


def _psql(*args: str, db: str | None = None, stdin: str | None = None) -> subprocess.CompletedProcess:
    cmd = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"] + (["-d", db] if db else []) + list(args)
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=ROOT)


def _must(proc: subprocess.CompletedProcess, what: str) -> str:
    assert proc.returncode == 0, f"{what} fejlede: {proc.stderr[-1500:]}"
    return proc.stdout


def _sql(db: str, sql: str, what: str = "fixture") -> None:
    _must(_psql(db=db, stdin="\\set ON_ERROR_STOP on\nSET session_replication_role = replica;\n" + sql), what)


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


def _persona(pid_uuid: str, source: int, run: str, key: str, person: int | None, status: str = "accepted",
             evidence: str = '{"fixture":"t9"}') -> str:
    canon = "NULL" if person is None else str(person)
    return (f"INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES "
            f"('{pid_uuid}',{source},'{key}','{run}');\n"
            f"INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,"
            f"evidence,decided_by,decided_by_name,decided_at) VALUES ('{pid_uuid}',{canon},'{status}',1,'{evidence}',"
            f"'{ACTOR}','fixture',now());\n")


def _date_fact(person: int, aid: int, faktatype: str, raw: str, sources: list[int], kind: str = "date_raw") -> str:
    col = "date_raw" if kind == "date_raw" else "vaerdi_tekst"
    lit = "E'" + raw.replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n") + "'"
    cites = "".join(f"INSERT INTO public.citation(assertion_id,source_id,side) VALUES ({aid},{s},'1');\n" for s in sources)
    return (f"INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES ({aid},'person',{person},'{faktatype}');\n"
            f"INSERT INTO public.assertion(id,target_type,target_id,{col}) VALUES ({aid},'fact',{aid},{lit});\n"
            f"INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) "
            f"VALUES ('fact',{aid},{aid},'afklaret');\n" + cites)


def _interp(iid: str, key: str, version: int, source: int, persona: str, predicate: str, value: str, run: str,
            status: str = "proposed", method: str = "fixture", supersedes: str | None = None) -> str:
    val = "to_jsonb(E'" + value.replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n") + "'::text)"
    audit = ("NULL,NULL,NULL,'{}'" if status == "proposed"
             else f"'{ACTOR}','fixture',now(),'{{\"basis\":\"fixture\"}}'")
    sup = "NULL" if supersedes is None else f"'{supersedes}'"
    kind = "relation" if predicate.startswith("relation.") else "property"
    return (f"INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,"
            f"interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,"
            f"extraction_run_id,supersedes_id,decided_by,decided_by_name,decided_at,decision_evidence) VALUES "
            f"('{iid}','{key}',{version},{source},'{persona}','{kind}','{predicate}',{val},'fixture','source_statement',1,"
            f"'{status}','{method}','{run}',{sup},{audit});\n")


def _u(n: int) -> str:
    return f"11000000-0000-0000-0000-{n:012d}"


def _promo(pid: str, iid: str, rule: str | None, target_type: str, target_id: int, evidence: str) -> str:
    rk = "NULL,NULL" if rule is None else f"'{rule}',1"
    return (f"INSERT INTO private.interpretation_promotion(id,interpretation_id,rule_key,rule_version,target_type,"
            f"target_id,evidence,promoted_by,promoted_by_name) VALUES ('{pid}','{iid}',{rk},'{target_type}',{target_id},"
            f"'{evidence}','{ACTOR}','fixture');\n")


_SETUP = (
    f"INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES ({SRC},'Fixture 6c2','synthetic','1900','DAA-udgave'),"
    f"({OTHER},'Fixture anden','synthetic','1901','DAA-udgave'),({K1},'Fixture 2018-20','synthetic','2018','DAA-udgave');\n"
    "INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,"
    "input_sha256,manifest) VALUES "
    f"('{RUN_S}',{SRC},'t9-s','fixture','fixture','fixture',repeat('1',64),'{{}}'),"
    f"('{RUN_O}',{OTHER},'t9-o','fixture','fixture','fixture',repeat('1',64),'{{}}'),"
    f"('{RUN_1}',{K1},'t9-1','fixture','fixture','fixture',repeat('1',64),'{{}}');\n"
    "INSERT INTO public.person(id,levende,privat,status) VALUES "
    + ",".join(f"({p},false,false,'t9')" for p in [*P.values(), PK]) + ";\n"
    # personas med accepteret identitet (kilden under maaling, den anden kilde, kilde 1)
    + "".join(_persona(_u(69100 + n), SRC, RUN_S, f"t9:s{n}", P[n]) for n in range(1, 12))
    + _persona(_u(69205), OTHER, RUN_O, "t9:o5", P[5])
    + _persona(_u(69208), OTHER, RUN_O, "t9:o8", P[8])
    + _persona(_u(69300), K1, RUN_1, "t9:k1", PK)
    # paastande (date_raw for datoer, vaerdi_tekst for navn)
    + _date_fact(P[1], A["p1"], "fødsel", "12. marts\n1750", [SRC])
    + f"UPDATE public.assertion SET date_min='1750-03-12',date_max='1750-03-12',date_qualifier='exact' "
      f"WHERE id={A['p1']};\n"
    + _date_fact(P[2], A["p2"], "fødsel", "1. maj\n1760", [SRC, OTHER])
    + _date_fact(P[3], A["p3a"], "fødsel", "2. maj\n1761", [SRC])
    + _date_fact(P[3], A["p3b"], "fødsel", "2. maj  1761", [SRC])
    + _date_fact(P[4], A["p4"], "fødsel", "3. maj\n1762", [SRC])
    + _date_fact(P[5], A["p5"], "fødsel", "4. maj 1763\n", [SRC])
    + _date_fact(P[6], A["p6"], "fødsel", "6. maj 1765", [SRC])
    + _date_fact(P[7], A["p7"], "fødsel", "7. maj\n1766", [SRC])
    + _date_fact(P[8], A["p8"], "fødsel", "9. maj\n1767", [OTHER])
    + _date_fact(P[9], A["p9"], "navn", "Anna", [SRC], kind="text")
    + _date_fact(P[10], A["p10"], "død", "10. maj 1770", [SRC])
    + _date_fact(P[11], A["p11"], "fødsel", "11. maj\n1771", [SRC])
    + _date_fact(PK, A["k1"], "fødsel", "5. juni 1700", [K1])
    # kildens forslag (version 1, proposed)
    + _interp(_u(69401), _u(69501), 1, SRC, _u(69101), "person.birth", "12. marts 1750", RUN_S)
    + _interp(_u(69402), _u(69502), 1, SRC, _u(69102), "person.birth", "1. maj 1760", RUN_S)
    + _interp(_u(69403), _u(69503), 1, SRC, _u(69103), "person.birth", "2. maj 1761", RUN_S)
    + _interp(_u(69404), _u(69504), 1, SRC, _u(69104), "person.birth", "3. maj 1762", RUN_S)
    + _interp(_u(69414), _u(69514), 1, SRC, _u(69104), "person.birth", "3. maj 1762", RUN_S)
    + _interp(_u(69405), _u(69505), 1, SRC, _u(69105), "person.birth", "4. maj 1763", RUN_S)
    + _interp(_u(69406), _u(69506), 1, SRC, _u(69106), "person.birth", "6. maj 1765", RUN_S)
    + _interp(_u(69407), _u(69507), 1, SRC, _u(69107), "person.birth", "8. juni 1799", RUN_S)
    + _interp(_u(69409), _u(69509), 1, SRC, _u(69109), "person.name", "Anna", RUN_S)
    + _interp(_u(69410), _u(69510), 1, SRC, _u(69110), "person.death", "† 10. maj 1770", RUN_S)
    + _interp(_u(69411), _u(69511), 1, SRC, _u(69111), "person.birth", "11. maj\n1771", RUN_S)
    # den anden kilde: P8's forslag; P5's accepterede fortolkning med en gyldig binding paa den raa vaerdi
    + _interp(_u(69408), _u(69508), 1, OTHER, _u(69208), "person.birth", "9. maj 1767", RUN_O)
    + _interp(_u(69415), _u(69515), 1, OTHER, _u(69205), "person.birth", "4. maj 1763\n", RUN_O, status="accepted")
    + _promo(_u(69605), _u(69415), "person-birth-v1", "assertion", A["p5"], '{"fixture":"t9"}')
    # kilde 1: en gyldig assertion-binding og en familiebinding uden gyldig tilstand
    + _interp(_u(69301), _u(69811), 1, K1, _u(69300), "person.birth", "5. juni 1700", RUN_1, status="accepted")
    + _promo(_u(69601), _u(69301), "person-birth-v1", "assertion", A["k1"], '{"fixture":"t9"}')
    + _interp(_u(69302), _u(69812), 1, K1, _u(69300), "relation.marriage", "gift", RUN_1, status="accepted")
    + _promo(_u(69602), _u(69302), None, "family", -69700, '{"state_sha256":"' + "e" * 64 + '"}')
)


def _run(db: str, script: Path, *vars_: str) -> subprocess.CompletedProcess:
    args: list[str] = []
    for v in vars_:
        args += ["-v", v]
    return _psql(*args, "-f", str(script), db=db)


def _maal(db: str, *vars_: str) -> tuple:
    out = _must(_run(db, MAAL, f"source_id={SRC}", *vars_), "maal").strip()
    assert "\n" not in out, out
    g = LINE.fullmatch(out)
    assert g, out
    return g.groups()


def _rename_pff(db: str, frm: str, to: str) -> None:
    sql = ("DO $d$ DECLARE r record; BEGIN FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
           "WHERE n.nspname='public' AND p.proname='public_person_facts' LOOP "
           f"EXECUTE replace(pg_get_functiondef(r.oid),'{frm}','{to}'); END LOOP; END $d$")
    _must(_psql("-c", sql, db=db), "pff")


def _skjul_writere(db: str, skjul: bool) -> None:
    if skjul:
        sql = ("ALTER FUNCTION public.red_ret_paastand(bigint,jsonb,text,uuid,jsonb) RENAME TO red_ret_paastand_t9skjult;"
               "ALTER TABLE public.paastand_korrektion RENAME TO paastand_korrektion_t9skjult;")
    else:
        sql = ("ALTER FUNCTION public.red_ret_paastand_t9skjult(bigint,jsonb,text,uuid,jsonb) RENAME TO red_ret_paastand;"
               "ALTER TABLE public.paastand_korrektion_t9skjult RENAME TO paastand_korrektion;")
    _must(_psql("-c", sql, db=db), "writere")


def test_scripts_er_laese_kun_og_uden_fast_kilde():
    for f in (MAAL, LINJESKIFT, VEJB, FORVENTET, KANDIDAT_PAR):
        sql = f.read_text(encoding="utf-8")
        body = re.sub(r"--[^\n]*", "", sql)
        if f not in (FORVENTET, KANDIDAT_PAR):  # snippets koerer i kalderens transaktion
            assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql, f.name
        assert not re.search(r"\b(INSERT|UPDATE|DELETE|COPY)\s", body), f.name
        # kilden kommer fra -v source_id (standard 3), aldrig som literal i en forespoergsel
        assert not re.search(r"source_id\s*(=|IN)\s*\(?\s*-?\d", body), f.name
    for f in (MAAL, LINJESKIFT):
        assert "\\set source_id 3" in f.read_text(encoding="utf-8")
    assert "SET LOCAL ROLE anon" in VEJB.read_text(encoding="utf-8")


def test_tilstande_foer_a_b_c_d_og_k1_hashen_er_stabil(db):
    # foer: vej B's mængdetjek er ikke i public_person_facts
    _rename_pff(db, "binding_value_matches", "binding_value_matchez")
    foer = _maal(db)
    assert foer[0] == "foer"
    # a: vej B paa plads, writerne (rettelsesvejen og journalen) mangler
    _rename_pff(db, "binding_value_matchez", "binding_value_matches")
    _skjul_writere(db, True)
    a = _maal(db)
    assert a[0] == "a" and a[7] == "0"
    assert a[9] == foer[9]
    # b: writerne findes; kort 122 tælles som human_sheet-unresolved for kilden (ikke web_detail, ikke anden kilde)
    _skjul_writere(db, False)
    b = _maal(db)
    assert b[:9] == ("b", "11", "3", "7", "1", "0", "0", "0", "0"), b
    _sql(db, _persona(_u(69151), SRC, RUN_S, "t9:s-kort", None, "unresolved",
                      '{"basis":"human_sheet","note":"x"}')
         + _persona(_u(69152), SRC, RUN_S, "t9:s-web", None, "unresolved", '{"basis":"web_detail","note":"x"}')
         + _persona(_u(69251), OTHER, RUN_O, "t9:o-kort", None, "unresolved", '{"basis":"human_sheet","note":"x"}'))
    b = _maal(db)
    assert b[0] == "b" and b[8] == "1"
    # c: en dato-markoer-version for kilden; P10 bliver MATCH. En linjeskift-rettelse tæller, men giver ikke d;
    # en fortrudt rettelse og en rettelse paa en anden kildes forslag tæller ikke.
    _sql(db, _interp(_u(69420), _u(69510), 2, SRC, _u(69110), "person.death", "10. maj 1770", RUN_S,
                     method="deterministisk-normalisering:dato-markoer-v1", supersedes=_u(69410)))
    c = _maal(db)
    assert c[:9] == ("c", "11", "4", "6", "1", "0", "0", "0", "1"), c
    _sql(db, "INSERT INTO public.change_set(id,operation) VALUES (-69801,'red_ret_paastand'),(-69802,'red_ret_paastand'),"
             "(-69803,'red_ret_paastand');\n"
             "INSERT INTO public.change_set(id,operation,reverterer_id) VALUES (-69804,'fortryd',-69802);\n"
             "INSERT INTO public.paastand_korrektion(assertion_id,interpretation_id,grund,foer,efter,change_set_id) VALUES "
             f"({A['p1']},'{_u(69401)}','linjeskift-v1','{{}}','{{}}',-69801),"
             f"({A['p2']},'{_u(69402)}','linjeskift-v1','{{}}','{{}}',-69802),"
             f"({A['p8']},'{_u(69408)}','linjeskift-v1','{{}}','{{}}',-69803);\n")
    c = _maal(db)
    assert c[0] == "c" and c[7] == "1"
    # en afvisning eller en uafklaret afgørelse alene giver også d (P7's REAL_DIFF afgøres og fjernes igen)
    for status in ("rejected", "unresolved"):
        _sql(db, _interp(_u(69427), _u(69507), 2, SRC, _u(69107), "person.birth", "8. juni 1799", RUN_S,
                         status=status, supersedes=_u(69407)))
        try:
            dx = _maal(db)
            assert dx[:9] == ("d", "10", "4", "6", "0", "0", "0", "1", "1"), (status, dx)
        finally:
            _sql(db, f"DELETE FROM private.interpretation WHERE id='{_u(69427)}';")
    assert _maal(db) == c
    # d: kildens navneforslag accepteres (afgørelsen alene giver d) og bindes
    _sql(db, _interp(_u(69429), _u(69509), 2, SRC, _u(69109), "person.name", "Anna", RUN_S, status="accepted",
                     supersedes=_u(69409)))
    d0 = _maal(db)
    assert d0[:9] == ("d", "10", "3", "6", "1", "1", "0", "1", "1"), d0
    _sql(db, _promo(_u(69609), _u(69429), "person-name-v1", "assertion", A["p9"], '{"fixture":"t9"}'))
    d = _maal(db)
    assert d[:9] == ("d", "10", "3", "6", "1", "1", "1", "1", "1"), d
    # kilde 1's bindinger er uroerte hele vejen, og maalingen er deterministisk
    assert foer[9] == a[9] == b[9] == c[9] == d0[9] == d[9]
    assert _maal(db) == d


def test_standardkilden_er_3(db):
    out = _must(_run(db, MAAL), "maal").strip()
    g = LINE.fullmatch(out)
    assert g and g.group(2) == "0" and g.group(6) == "0", out


def test_k1_hash_og_den_noeglede_liste(db, tmp_path):
    liste = tmp_path / "bindinger.txt"
    m = _maal(db, f"liste={liste}")
    rows = [ln.split("|") for ln in liste.read_text(encoding="utf-8").splitlines()]
    assert all(len(r) == 3 and r[2] in ("t", "f") for r in rows), rows
    # alle bindinger (alle kilder), sorteret paa promotion-id
    assert [r[0] for r in rows] == sorted(r[0] for r in rows)
    assert {(r[0], r[1], r[2]) for r in rows} == {
        (_u(69601), str(K1), "t"), (_u(69602), str(K1), "f"), (_u(69605), str(OTHER), "t"),
        (_u(69609), str(SRC), "t")}
    # hashen er sha256 over kilde 1's "id:gyldig"-linjer i uuid-orden
    k1 = "\n".join(f"{r[0]}:{'true' if r[2] == 't' else 'false'}" for r in rows if r[1] == str(K1))
    assert m[9] == hashlib.sha256(k1.encode()).hexdigest()
    # en kilde 1-binding, der bliver ugyldig, aendrer hashen, og listen viser hvilken
    _sql(db, f"UPDATE public.assertion SET date_raw='5. juni 1701' WHERE id={A['k1']};")
    try:
        liste2 = tmp_path / "bindinger2.txt"
        m2 = _maal(db, f"liste={liste2}")
        assert m2[9] != m[9]
        rows2 = {r.split("|")[0]: r.split("|")[2] for r in liste2.read_text(encoding="utf-8").splitlines()}
        assert rows2[_u(69601)] == "f"
    finally:
        _sql(db, f"UPDATE public.assertion SET date_raw='5. juni 1700' WHERE id={A['k1']};")
    assert _maal(db)[9] == m[9]
    # en tom -v liste= skriver ingen liste (heller ikke til stdout): stadig én linje
    assert _maal(db, "liste=") == _maal(db)


def test_flere_gyldige_bindinger_paa_en_paastand_stopper_maalingen(db):
    _sql(db, _interp(_u(69303), _u(69813), 1, K1, _u(69300), "person.birth", "5. juni 1700", RUN_1,
                     status="accepted")
         + _promo(_u(69603), _u(69303), "person-birth-v1", "assertion", A["k1"], '{"fixture":"t9"}'))
    try:
        r = _run(db, MAAL, f"source_id={SRC}")
        assert r.returncode != 0
        assert "MAAL_FLERE_BINDINGER" in r.stderr
        assert "T6C2_MAAL" not in r.stdout
        assert _u(69603) not in r.stderr and str(A["k1"]) not in r.stderr
    finally:
        _sql(db, f"DELETE FROM private.interpretation_promotion WHERE id='{_u(69603)}';"
                 f"DELETE FROM private.interpretation WHERE id='{_u(69303)}';")
    assert _maal(db)[0] == "d"


def _lk(db: str, source: int) -> subprocess.CompletedProcess:
    return _run(db, LINJESKIFT, f"source_id={source}")


def _lk_full(db: str, source: int) -> tuple[tuple, list[tuple[int, str]], str, tuple]:
    out = _must(_lk(db, source), "linjeskift").strip().splitlines()
    g = LK_LINE.fullmatch(out[0])
    assert g, out
    par = []
    for x in out[1:]:
        m = PAR.fullmatch(x)
        assert m, x
        par.append((int(m.group(1)), m.group(2)))
    assert int(g.group(1)) == len(par)
    assert [a for a, _ in par] == sorted(a for a, _ in par)
    return g.groups()[:2], par, g.group(3), (g.group(4), g.group(5))


def _lk_ok(db: str, source: int) -> tuple[tuple, list[int]]:
    g, par, _, _ = _lk_full(db, source)
    return g, [a for a, _ in par]


def _par(par: list[tuple[int, str]]) -> str:
    return ",".join(f"{a}:{i}" for a, i in par)


def _forventet(db: str, par: list[tuple[int, str]], *udtryk: str) -> list[str]:
    """Snippet'et direkte, som runneren bruger det: par ind i GUC'en, GUC'er ud (udtryk efter eget valg)."""
    sel = ",".join(udtryk) or "current_setting('daa.linjeskift_forventet_sha256')"
    sql = (f"BEGIN READ ONLY;\nSELECT set_config('daa.linjeskift_par','{_par(par)}',true) \\g /dev/null\n"
           f"\\i {FORVENTET}\nSELECT {sel};\nROLLBACK;\n")
    return _must(_psql(db=db, stdin=sql), "forventet").strip().split("|")


def _forventet_sha(db: str, par: list[tuple[int, str]]) -> str:
    out = _forventet(db, par)[0]
    assert re.fullmatch(r"[0-9a-f]{64}", out), out
    return out


def test_linjeskift_kandidater_afgraensning(db):
    # kun P1: P2 delt citation (to citerende kilder, K5), P3 to maal, P4 to forslag, P5 gyldig binding der ville
    # brydes, P6 intet at rette, P7 ikke lig efter samling, P8 den anden kildes forslag, P10 intet at rette,
    # P11 kun lig den raa vaerdi
    g, ids = _lk_ok(db, SRC)
    assert ids == [A["p1"]] and g == ("1", "0")
    # kilden er en parameter: for den anden kilde er P8 kandidat (kun citeret af den), P2 ikke
    g, ids = _lk_ok(db, OTHER)
    assert ids == [A["p8"]]


def test_linjeskift_par_og_forventet_sha(db):
    p1 = [(A["p1"], _u(69401))]
    # par: paastand og forslagets aktuelle version; grænserne udfyldt for P1, ikke for P8
    _, par, sha, gr = _lk_full(db, SRC)
    assert par == p1 and gr[0] == "1"
    _, par_o, _, gr_o = _lk_full(db, OTHER)
    assert par_o == [(A["p8"], _u(69408))] and gr_o[0] == "0"
    # stabil over koersler, og lig snippet'et kaldt direkte (én definition)
    assert _lk_full(db, SRC)[2] == sha == _forventet_sha(db, p1)
    # parret er hash-bundet: et andet interpretation_id giver en anden sha
    assert _forventet_sha(db, [(A["p1"], _u(69402))]) != sha
    # date_raw aendres (stadig kandidat): sha'en aendres, grænserne ikke
    _sql(db, f"UPDATE public.assertion SET date_raw=E'12. marts\\n\\n1750' WHERE id={A['p1']};")
    try:
        _, par2, sha2, gr2 = _lk_full(db, SRC)
        assert par2 == par and sha2 != sha and gr2 == gr
    finally:
        _sql(db, f"UPDATE public.assertion SET date_raw=E'12. marts\\n1750' WHERE id={A['p1']};")
    assert _lk_full(db, SRC)[2] == sha
    # citationsmaengden aendres: runnerens genberegning paa de samme par giver en anden sha
    _sql(db, f"INSERT INTO public.citation(id,assertion_id,source_id,side) VALUES (-69990,{A['p1']},{OTHER},'1');")
    try:
        assert _forventet_sha(db, p1) != sha
    finally:
        _sql(db, "DELETE FROM public.citation WHERE id=-69990;")
    assert _forventet_sha(db, p1) == sha
    # grænserne aendres: graenser_sha256 aendres
    _sql(db, f"UPDATE public.assertion SET date_max='1750-03-13' WHERE id={A['p1']};")
    try:
        assert _lk_full(db, SRC)[3] != gr
    finally:
        _sql(db, f"UPDATE public.assertion SET date_max='1750-03-12' WHERE id={A['p1']};")
    # ingen vaerdier i udskriften
    out = _must(_lk(db, SRC), "linjeskift")
    assert "marts" not in out and "1750" not in out


def test_forventet_citationskilder_stigende_og_i_sha(db):
    """P2 citeres af to kilder (indsat SRC foer OTHER, mens OTHER < SRC): citation_sources er stigende, og sha'en er
    sha256 over netop den jsonb-tekst."""
    par = [(A["p2"], _u(69402))]
    liste, sha = _forventet(db, par, "current_setting('daa.linjeskift_forventet')",
                            "current_setting('daa.linjeskift_forventet_sha256')")
    assert json.loads(liste)[0]["forventet"]["citation_sources"] == sorted([SRC, OTHER])
    assert set(json.loads(liste)[0]) == {"assertion_id", "interpretation_id", "forventet"}
    assert set(json.loads(liste)[0]["forventet"]) == {"fact_id", "faktatype", "vaerdi_tekst", "date_raw",
                                                      "valgt_assertion_id", "citation_sources"}
    assert sha == hashlib.sha256(liste.encode()).hexdigest()


def test_kandidatlisten_genberegnes_af_snippet(db):
    """Runnerens (a): linjeskift_kandidat_par.sql giver samme parliste som scriptet."""
    sql = (f"BEGIN READ ONLY;\nSELECT set_config('daa.linjeskift_kilde','{SRC}',true) \\g /dev/null\n"
           f"\\i {KANDIDAT_PAR}\nSELECT current_setting('daa.linjeskift_kandidat_par');\nROLLBACK;\n")
    assert _must(_psql(db=db, stdin=sql), "kandidat_par").strip() == _par(_lk_full(db, SRC)[1])


def test_forventet_accepteres_af_red_ret_paastand_og_graenser_uaendret(db):
    """Elementets "forventet" er præcis det p_forventet, RPC'en kræver; efter rettelsen er grænserne uændrede og den
    forventede tilstand en anden (rulles tilbage)."""
    sql = f"""
\\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(id,email) VALUES ('{ACTOR}','t9@invalid') ON CONFLICT DO NOTHING;
INSERT INTO public.profiles(id,rolle,navn,email) VALUES ('{ACTOR}','redaktion','t9','t9@invalid') ON CONFLICT DO NOTHING;
SELECT set_config('daa.linjeskift_par','{A["p1"]}:{_u(69401)}',true) \\g /dev/null
\\i {FORVENTET}
SELECT current_setting('daa.linjeskift_graenser_sha256') AS g0, current_setting('daa.linjeskift_graenser_udfyldt') AS u0,
       current_setting('daa.linjeskift_forventet_sha256') AS f0 \\gset
SELECT set_config('request.jwt.claim.sub','{ACTOR}',true) \\g /dev/null
SELECT set_config('app.change_set_id','',true) \\g /dev/null
SET LOCAL ROLE authenticated;
SELECT (public.red_ret_paastand((e->>'assertion_id')::bigint,e->'forventet','linjeskift-v1',
        (e->>'interpretation_id')::uuid)->>'assertion_id')
  FROM (SELECT current_setting('daa.linjeskift_forventet')::jsonb->0 AS e) x;
RESET ROLE;
SELECT a.date_raw = '12. marts 1750' FROM public.assertion a WHERE a.id={A["p1"]};
\\i {FORVENTET}
SELECT current_setting('daa.linjeskift_graenser_sha256')=:'g0',
       current_setting('daa.linjeskift_graenser_udfyldt')=:'u0' AND :'u0'='1',
       current_setting('daa.linjeskift_forventet_sha256')<>:'f0';
ROLLBACK;
"""
    out = _must(_psql(db=db, stdin=sql), "red_ret_paastand").strip().splitlines()
    assert out == [str(A["p1"]), "t", "t|t|t"], out
    assert _lk_ok(db, SRC)[1] == [A["p1"]]


def test_linjeskift_tilstandsgate(db):
    raw = "12. marts\\n1750"
    # (1) en placement-tilstand (gemt source_basis) indeholder kandidatens date_raw: gate, ingen liste
    _sql(db, f"INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis) "
             f"VALUES ({P[1]},-69900,'member',jsonb_build_object('state',jsonb_build_object('d',E'{raw}')));")
    try:
        r = _lk(db, SRC)
        assert r.returncode != 0 and "LINJESKIFT_TILSTAND_BEROERT" in r.stderr
        assert "T6C2_LINJESKIFT" not in r.stdout and str(A["p1"]) not in r.stdout + r.stderr
    finally:
        _sql(db, f"DELETE FROM public.person_lineage_membership WHERE person_id={P[1]};")
    # (2) en familiebindings gemte tilstand for en familie, personen er medlem af
    _sql(db, f"INSERT INTO public.family_member(family_id,person_id,rolle) VALUES (-69700,{P[1]},'partner');"
             f"UPDATE private.interpretation_promotion SET evidence=evidence||jsonb_build_object('x',E'{raw}') "
             f"WHERE id='{_u(69602)}';")
    try:
        r = _lk(db, SRC)
        assert r.returncode != 0 and "LINJESKIFT_TILSTAND_BEROERT" in r.stderr
        assert "T6C2_LINJESKIFT" not in r.stdout
    finally:
        _sql(db, f"UPDATE private.interpretation_promotion SET evidence=evidence-'x' WHERE id='{_u(69602)}';"
                 f"DELETE FROM public.family_member WHERE family_id=-69700;")
    # (3) publiceringstilstand: som hel vaerdi -> gate; som delstreng af narrativteksten -> kun talt
    _sql(db, f"INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst) VALUES (-69950,'person',{P[1]},"
             f"{SRC},'syntetisk');"
             "INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,"
             "narrative_id,source_id,legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,"
             f"after_state_sha256,decided_by_name) VALUES (-69801,'{_u(69960)}',1,'legacy_migrated',-69950,{SRC},"
             f"'{_u(69960)}','fixture','{{}}',jsonb_build_object('narrative',jsonb_build_object('text',"
             f"E'Foedt {raw} paa X')),repeat('a',64),repeat('b',64),'fixture');")
    g, ids = _lk_ok(db, SRC)
    assert ids == [A["p1"]] and g == ("1", "1")
    _sql(db, "INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,"
             "narrative_id,source_id,legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,"
             f"after_state_sha256,decided_by_name) VALUES (-69801,'{_u(69960)}',2,'legacy_migrated',-69950,{SRC},"
             f"'{_u(69960)}','fixture','{{}}',jsonb_build_object('d',E'{raw}'),repeat('a',64),repeat('b',64),"
             "'fixture');")
    try:
        r = _lk(db, SRC)
        assert r.returncode != 0 and "LINJESKIFT_TILSTAND_BEROERT" in r.stderr
    finally:
        _sql(db, "DELETE FROM private.narrative_publication_event WHERE narrative_id=-69950;"
                 "DELETE FROM public.narrative WHERE id=-69950;")
    assert _lk_ok(db, SRC)[1] == [A["p1"]]


def test_linjeskift_publiceringsgate_bruger_recordens_kilde(db):
    """Den beregnede publiceringstilstand kaldes med recordens kilde (sr.source_id). Narrativets source_id er her
    sat til en anden kilde; med n.source_id ville opslaget fejle (NARRATIVE_RECORD_NOT_FOUND) i stedet for gaten.
    Narrativteksten er lig kandidatens date_raw, saa tilstanden indeholder den som hel vaerdi."""
    raw = "12. marts\\n1750"
    _sql(db, "INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES "
             f"('{_u(69970)}',{SRC},'t9:post1','person_post','{RUN_S}');"
             f"INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst) VALUES (-69971,'person',{P[1]},"
             f"{OTHER},E'{raw}');"
             "INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,"
             f"status) VALUES (-69971,'{_u(69970)}','t9','t9','published');")
    try:
        r = _lk(db, SRC)
        assert r.returncode != 0 and "LINJESKIFT_TILSTAND_BEROERT" in r.stderr, r.stderr
        assert "T6C2_LINJESKIFT" not in r.stdout
    finally:
        _sql(db, "DELETE FROM private.narrative_record_publication WHERE narrative_id=-69971;"
                 "DELETE FROM public.narrative WHERE id=-69971;"
                 f"DELETE FROM private.source_record WHERE id='{_u(69970)}';")
    assert _lk_ok(db, SRC)[1] == [A["p1"]]


def test_vejb_linjeformat(db):
    out = _must(_run(db, VEJB, f"personer={P[1]}, {P[9]}"), "vejb").strip().splitlines()
    assert len(out) == 10
    gs = [VEJB_LINE.fullmatch(x) for x in out]
    assert all(gs), out
    assert [int(g.group(1)) for g in gs] == [P[1]] * 5 + [P[9]] * 5
    for bad in ("personer=", "personer=1;2", "personer=abc"):
        r = _run(db, VEJB, bad)
        assert r.returncode != 0 and "VEJB_PERSONER_UGYLDIG" in r.stderr, (bad, r.stderr)
    r = _run(db, VEJB)
    assert r.returncode != 0 and "VEJB_PERSONER_MANGLER" in r.stderr
