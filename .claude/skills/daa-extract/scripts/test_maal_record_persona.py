"""record_persona Task 4: maalingen maal_record_persona.sql mod en lokal fixturebase (foer -> ddl -> data).

Kraever en PostgreSQL 17 (PG*-miljoevariabler) og psql; basen oprettes af testen (rp_maal_<pid>) og droppes ALDRIG af
den (i CI er serveren engangs). Mangler psql/serveren, springes testen kun over lokalt; i CI (CI=true) fejler den.
Alt er syntetisk (tests/sql/fixtures/ceremoni-record-persona.sql), og maalingen viser kun tal og hashes.
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
MAAL = SCRIPTS / "maal_record_persona.sql"
CEREMONI = SCRIPTS / "record_persona_ceremoni.sql"
SRC = -6400
DB = f"rp_maal_{os.getpid()}"
LINE = re.compile(r"T_RP_MAAL fase=(foer|ddl|data) personas=(\d+) identiteter=(\d+) placements=(\d+) kladder=(\d+) "
                  r"eligible=(\d+) header_violations=(\d+) synlige_1939=(\d+) KOORD_2018_20=([0-9a-f]{32}) "
                  r"KOORD_SRC=([0-9a-f]{32}) FAKTA=([0-9a-f]{32}) BIO=([0-9a-f]{32})")
FELTER = ("fase", "personas", "identiteter", "placements", "kladder", "eligible", "header_violations", "synlige",
          "koord", "koord_src", "fakta", "bio")
DDL_MARKOER = "public.red_apply_reimport_record_persona(uuid,text,jsonb)"


def _psql(*args: str, db: str | None = None, stdin: str | None = None, cwd: Path = ROOT) -> subprocess.CompletedProcess:
    cmd = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"] + (["-d", db] if db else []) + list(args)
    env = {k: v for k, v in os.environ.items() if k != "PGOPTIONS"}
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=cwd, env=env)


def _must(proc: subprocess.CompletedProcess, what: str) -> str:
    assert proc.returncode == 0, f"{what} fejlede: {proc.stderr[-1500:]}"
    return proc.stdout


@pytest.fixture(scope="module")
def db(tmp_path_factory):
    if shutil.which("psql") is None or subprocess.run(["psql", "-X", "-Atc", "select 1", "-d", "postgres"],
                                                      capture_output=True).returncode != 0:
        if os.environ.get("CI"):
            pytest.fail("PostgreSQL er ikke tilgaengelig i CI")
        pytest.skip("ingen lokal PostgreSQL")
    _must(subprocess.run(["createdb", DB], capture_output=True, text=True), "createdb")
    for f in ("tests/sql/evidence-promotion-bootstrap.sql", "schema.sql", "db-rls.sql",
              "tests/sql/1939-v50-writer-bootstrap.sql"):
        _must(_psql("-f", f, db=DB), f)
    _must(_psql("-c", "BEGIN", "-f", "tests/sql/reimport-writer-v2-bootstrap.sql", "-c", "COMMIT", db=DB), "v2")
    _must(_psql("-f", "db-rls.sql", db=DB), "db-rls.sql (anden gang)")
    _must(_psql("-f", "ceremoni-record-persona.sql", db=DB, cwd=ROOT / "tests/sql/fixtures"), "fixture")
    # Manifestet: maalingen laeser kun record_key, person_id og mention_id; resten er udfyldt som i kortbyggeren.
    rows = _must(_psql("-c", f"""SELECT r.record_key||'|'||m.id FROM private.source_record r
        JOIN private.source_record_anchor_current a ON a.source_record_id=r.id
        JOIN private.source_observation o ON o.occurrence_id=a.occurrence_id AND o.observation_kind='person'
        JOIN private.source_mention m ON m.observation_id=o.id
       WHERE r.source_id={SRC} AND r.record_key IN ('rpc-a','rpc-b') ORDER BY r.record_key""", db=DB), "mentions")
    person = {"rpc-a": -640001, "rpc-b": -640002}
    linjer = []
    for i, row in enumerate(rows.split()):
        key, mention = row.split("|")
        linjer.append(json.dumps({"kort": f"K{i + 1}", "linje": i + 1, "mention_id": mention, "person_id": person[key],
                                  "record_key": key}, sort_keys=True, separators=(",", ":")))
    manifest = tmp_path_factory.mktemp("rp") / "manifest.jsonl"
    manifest.write_text("\n".join(linjer) + "\n", encoding="utf-8")
    return {"db": DB, "manifest": str(manifest)}


def _maal(ctx, *extra: str) -> dict[str, str]:
    out = _must(_psql("-v", f"src={SRC}", "-v", f"manifest_path={ctx['manifest']}", *extra, "-f", str(MAAL),
                      db=ctx["db"]), "maal").strip()
    assert "\n" not in out, out
    g = LINE.fullmatch(out)
    assert g, out
    return dict(zip(FELTER, g.groups()))


def _sql(ctx, sql: str) -> str:
    return _must(_psql(db=ctx["db"], stdin="\\set ON_ERROR_STOP on\n" + sql), "sql")


# Skriver det, ceremonien ville skrive for rpc-a (persona paa helpost-mentionen, identitet, kladde), uden ceremonien.
_PERSONA = f"""
INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
  SELECT {SRC},'maal:'||r.record_key,r.created_run_id FROM private.source_record r WHERE r.source_id={SRC} AND r.record_key=:'k';
INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
  SELECT sp.id,m.id,'primary',1 FROM private.source_persona sp, private.source_record r
    JOIN private.source_record_anchor_current a ON a.source_record_id=r.id
    JOIN private.source_observation o ON o.occurrence_id=a.occurrence_id AND o.observation_kind='person'
    JOIN private.source_mention m ON m.observation_id=o.id
   WHERE sp.persona_key='maal:'||:'k' AND r.source_id={SRC} AND r.record_key=:'k';
"""


def _persona(ctx, key: str) -> None:
    _must(_psql("-v", f"k={key}", db=ctx["db"], stdin=_PERSONA), "persona")


def _identitet(ctx, key: str, person: int) -> None:
    """Accepteret identitet (tilstand + haendelse i samme transaktion, som skemaets konsistenstrigger kraever)."""
    cols = "source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at"
    sel = (f"SELECT id,{person},'accepted',1,'{{\"fixture\":\"maal\"}}','a6400000-0000-0000-0000-000000006400',"
           f"'fixture',now() FROM private.source_persona WHERE persona_key='maal:{key}'")
    _sql(ctx, f"BEGIN;\nINSERT INTO private.source_persona_identity({cols}) {sel};\n"
              f"INSERT INTO private.source_persona_identity_event({cols}) {sel};\nCOMMIT;")


def test_faser_og_taellingerne(db):
    ddl = _maal(db)
    assert ddl["fase"] == "ddl"
    assert (ddl["personas"], ddl["identiteter"], ddl["placements"], ddl["kladder"], ddl["eligible"],
            ddl["header_violations"]) == ("0", "0", "0", "0", "0", "0")
    # foer: operationen findes ikke (markoeren omdoebes midlertidigt)
    _sql(db, f"ALTER FUNCTION {DDL_MARKOER} RENAME TO red_apply_reimport_record_persona_maal;")
    try:
        foer = _maal(db)
    finally:
        _sql(db, "ALTER FUNCTION public.red_apply_reimport_record_persona_maal(uuid,text,jsonb) "
                 "RENAME TO red_apply_reimport_record_persona;")
    assert foer["fase"] == "foer" and {k: v for k, v in foer.items() if k != "fase"} == \
        {k: v for k, v in ddl.items() if k != "fase"}
    # en persona paa den ene post: taelles, men fasen er stadig ddl (ingen kvittering, ikke alle poster)
    _persona(db, "rpc-a")
    en = _maal(db)
    assert en["fase"] == "ddl" and en["personas"] == "1" and en["identiteter"] == "0"
    _identitet(db, "rpc-a", -640001)
    assert _maal(db)["identiteter"] == "1"
    # kvitteringen for en anden kilde og kvitteringen alene flytter ikke fasen; kvittering + alle personas goer
    kv = ("INSERT INTO public.change_set(operation,summary,subjekt_type,subjekt_id) VALUES ('record_persona_ceremoni',"
          "'T_RP_OK personas=2 identiteter=2 placements=2 medlemskab=2 kladder=2','source',%d);")
    _sql(db, kv % -6401)
    _sql(db, kv % SRC)
    assert _maal(db)["fase"] == "ddl"
    _persona(db, "rpc-b")
    # identiteten taelles kun mod manifestlinjens person (rpc-b's persona peger paa rpc-a's person)
    _identitet(db, "rpc-b", -640001)
    data = _maal(db)
    assert data["fase"] == "data" and data["personas"] == "2" and data["identiteter"] == "1"
    assert (data["koord"], data["fakta"], data["bio"], data["synlige"]) == \
        (ddl["koord"], ddl["fakta"], ddl["bio"], ddl["synlige"])


def test_kladder_taeller_kun_draft_paa_manifestposterne(db):
    h0 = _maal(db)
    _sql(db, f"""
INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES ('person',-640003,{SRC},'9','Opdigtet c');
INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
  SELECT (SELECT max(id) FROM public.narrative),r.id,'F','F','draft' FROM private.source_record r
   WHERE r.source_id={SRC} AND r.record_key='rpc-c';""")
    assert _maal(db)["kladder"] == h0["kladder"]  # rpc-c staar ikke i manifestet
    _sql(db, f"""
INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES ('person',-640002,{SRC},'9','Opdigtet b');
INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
  SELECT (SELECT max(id) FROM public.narrative),r.id,'F','F','draft' FROM private.source_record r
   WHERE r.source_id={SRC} AND r.record_key='rpc-b';""")
    assert int(_maal(db)["kladder"]) == int(h0["kladder"]) + 1


def test_koord_adskiller_kilden_fra_de_andre(db):
    h0 = _maal(db)
    _sql(db, "UPDATE public.person_external_id SET nr=nr+10 WHERE person_id=-640101 AND source_id=-6401;")
    h1 = _maal(db)
    assert h1["koord"] != h0["koord"] and h1["koord_src"] == h0["koord_src"]
    _sql(db, f"UPDATE public.person_external_id SET nr=nr+10 WHERE person_id=-640001 AND source_id={SRC};")
    h2 = _maal(db)
    assert h2["koord"] == h1["koord"] and h2["koord_src"] != h1["koord_src"]


def test_manifest_er_paakraevet(db):
    proc = _psql("-v", f"src={SRC}", "-f", str(MAAL), db=db["db"])
    assert proc.returncode != 0 and "T_RP_MAAL" not in proc.stdout


def test_sql_er_laese_kun_og_uden_noegler():
    sql = MAAL.read_text(encoding="utf-8")
    assert "BEGIN READ ONLY" in sql and "ROLLBACK" in sql
    code = re.sub(r"--[^\n]*", "", sql)
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|CREATE)\s", code)
    assert len(re.findall(r"^SELECT format\(", code, re.M)) == 1
    # ingen kilde-, person- eller post-id'er og ingen udgave i logikken: alt kommer fra -v
    assert not re.search(r"-?\b\d{3,}\b", code)
    assert "record-" not in code and "1939:" not in code


def _udtryk(sql: str, start: str, slut: str) -> str:
    m = re.search(re.escape(start) + r".*?" + re.escape(slut), sql, re.S)
    assert m, f"udtrykket {start}…{slut} mangler"
    return re.sub(r"\s+", "", m.group(0))


def test_hashudtrykkene_er_de_samme_som_ceremoniens():
    """FAKTA, BIO, KOORD og synlige i maalingen og i ceremoniens POST-sammenligning skal vaere samme udtryk."""
    maal = MAAL.read_text(encoding="utf-8")
    cer = CEREMONI.read_text(encoding="utf-8")
    for start, slut in (("SELECT 'f|'", "public_family_sources("), ("string_agg(b::text", "public_person_bio_source_versions_v2("),
                        ("concat_ws('|',quote_nullable(c.person_id)", "ORDER BY c.person_id,c.source_id)")):
        a = _udtryk(maal, start, slut).replace(":'ids'::bigint[]", "IDS").replace(":src", "SRC")
        b = _udtryk(cer, start, slut).replace("v_ids", "IDS").replace("p_src", "SRC")
        assert a == b, (start, a, b)


def test_ceremonien_er_kildeneutral():
    """Ceremonien naevner ingen kilde, udgave, post, person eller profil i logikken: alt kommer fra -v og filerne."""
    code = re.sub(r"--[^\n]*", "", CEREMONI.read_text(encoding="utf-8"))
    assert not re.search(r"-?\b\d{3,}\b", code)
    assert "1939" not in code and "2018" not in code and "fixture" not in code
    # personaens noegleprefix og helpost-slagsen kommer fra profilen
    assert "writer_config->>'persona_key_prefix'" in code and "writer_config_helpost_kind" in code
    # ét skrivende forloeb: én transaktion, change_set-laasen efter finalize og foer foerste identitet
    assert code.count("\nBEGIN;") == 1 and code.count("\nCOMMIT;") == 1
    # svarfilen (ethvert N) og foertilstanden afgoeres foer authorize
    assert code.index("T_RP_PRE_SVAR") < code.index("T_RP_PRE_MANIFEST kort") < code.index("red_authorize_reimport(")
    assert code.index("red_finalize_reimport") < code.index("LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE") \
        < code.index("red_afgoer_source_persona") < code.index("write_record_placement") \
        < code.index("record_legacy_disposition(r.person_id") < code.index("red_promote_placement_memberships") \
        < code.index("red_upsert_person_narrative_record")
