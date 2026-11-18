"""Trin 5a (#151): identitetskernen er privat, og hver kalder har en lovlig, allowlistet oprindelse.

Statisk, fordi db-migrations.sql ikke kører i én transaktion: en uguardet definition eller grant
nogetsteds i filen ville være aktiv under deployet, selv om sluttilstanden er rigtig. Mellemtilstanden
før de omskrevne linjer dækkes af cutover-blokken øverst (testet i test-identity-cutover.sql).
"""
from __future__ import annotations  # /usr/bin/python3 lokalt er 3.9; CI kører 3.11

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[4]
KERNE = "private.decide_source_persona_identity("
# Trin 6b: publication_binding (spec §4.3.1; decisions 2026-10-31). Kalderne write_publication_identity (Task 6) og
# red_reverse_reimport_publication (Task 7, reversal) står i ALLOWLIST (ledger-ruling R2).
OPRINDELSER = ("human", "person_create", "legacy_match", "reversal", "family_corroboration", "relation_person_create",
               "publication_binding", "person_purge")
CUTOVER = re.compile(r"-- BEGIN 5a-cutover.*?-- END 5a-cutover", re.S)
# Eksakt allowlist (fil, omsluttende funktion, oprindelse) -> antal kald. Målt 2026-09-24.
# En ny kalder kræver en ændring her OG en beslutning (spec §4.2) — aldrig bare en ny linje.
# 5b 2026-10-06: family_corroboration (decisions 2026-10-06).
ALLOWLIST = {
    ("schema.sql", "red_afgoer_source_persona", "human"): 1,
    ("schema.sql", "red_apply_reimport_person_create", "person_create"): 1,
    ("schema.sql", "migrate_legacy_narrative_record", "legacy_match"): 1,
    ("schema.sql", "red_reverse_reimport", "reversal"): 1,
    ("schema.sql", "red_corroborate_family_identities", "family_corroboration"): 1,
    # Trin 5b 2b-ii: ny oprindelse relation_person_create (hovedspec §8.4; decisions 2026-10-06 pkt. 3, ændret 2026-10-17).
    ("schema.sql", "write_relation_person_create", "relation_person_create"): 1,
    ("db-migrations.sql", "red_afgoer_source_persona", "human"): 4,   # 2b-ii: kopi med deceased-konteksten; dubletreglen (2026-10-25); 6b Task 3: kø-vagten IDENTITY_AWAITING_PUBLICATION_CONTROL
    ("db-migrations.sql", "red_apply_1939_v50_person_create", "person_create"): 1,
    ("db-migrations.sql", "red_apply_reimport_person_create", "person_create"): 2,
    ("db-migrations.sql", "migrate_legacy_narrative_record", "legacy_match"): 1,
    ("db-migrations.sql", "red_reverse_1939_v50_reimport", "reversal"): 3,
    ("db-migrations.sql", "red_reverse_reimport", "reversal"): 1,
    ("db-migrations.sql", "red_corroborate_family_identities", "family_corroboration"): 1,
    ("db-migrations.sql", "write_relation_person_create", "relation_person_create"): 2,   # 2b-ii runde 2: kopi med titelværn og aktualitetstjek
    # Trin 6b Task 6 (ledger-ruling R2; decisions 2026-10-31): C's writer kalder kernen med publication_binding (enig) og
    # med human (arkets S/F/U, basis human_sheet) — den anden serverkalder af human ud over red_afgoer_source_persona.
    ("schema.sql", "write_publication_identity", "publication_binding"): 1,
    ("schema.sql", "write_publication_identity", "human"): 1,
    # Trin 6b opfølgning (I2): kopi i blokken »C kan genkøres efter fortrydelse« (versionsvagt for fortrudte identiteter).
    # Trin 6c-1 retning 2 (delspec 6c-1 §4.8): kopi i blokken »C3-bindingen er identiteten for de automatiske udfald«
    # (publication_binding for enig, svag og ingen_kandidat; human for uenig og navnefaelle). Samme oprindelser.
    ("db-migrations.sql", "write_publication_identity", "publication_binding"): 3,
    ("db-migrations.sql", "write_publication_identity", "human"): 3,
    # Trin 6b Task 7: fortrydelsen af C (superseded gennem reversal-oprindelsen, med versionsvagt).
    ("schema.sql", "red_reverse_reimport_publication", "reversal"): 1,
    ("db-migrations.sql", "red_reverse_reimport_publication", "reversal"): 1,
    # Fuld personsletning (decisions 2026-11-14; spec Q7): P's personas afvises som not_a_person, version n+1,
    # med oprindelsen person_purge. Eneste kalder er red_slet_person_helt (Task 8b).
    ("schema.sql", "red_slet_person_helt", "person_purge"): 1,
    ("db-migrations.sql", "red_slet_person_helt", "person_purge"): 1,
}


def _uden_kommentarer(s: str) -> str:
    return re.sub(r"--[^\n]*", "", s)


def _tekst(navn: str) -> str:
    return _uden_kommentarer((ROOT / navn).read_text(encoding="utf-8"))


def _uden_cutover(raa: str) -> str:
    """Skær cutover-blokken ud af RÅTEKSTEN og strip derefter kommentarer. Rækkefølgen er bærende:
    blokkens markører er selv kommentarer og forsvinder, hvis der strippes først (Codex 2026-10-05)."""
    return _uden_kommentarer(CUTOVER.sub("", raa))


def offentlig_kerne_uden_for_cutover(raa: str) -> list[str]:
    s = _uden_cutover(raa)
    fund = []
    for m in re.finditer(r"red_decide_source_persona_identity\(", s):
        linje = s[s.rfind("\n", 0, m.start()) + 1:s.find("\n", m.start())]
        if "DROP FUNCTION IF EXISTS public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)" not in linje:
            fund.append(linje.strip()[:120])
    return fund


def femarguments_wrapper_uden_for_cutover(raa: str) -> bool:
    s = _uden_cutover(raa).replace("DROP FUNCTION IF EXISTS red_afgoer_source_persona(uuid,integer,text,bigint,text)", "")
    return ("red_afgoer_source_persona(uuid,integer,text,bigint,text)" in s
            or bool(re.search(r"FUNCTION\s+(public\.)?red_afgoer_source_persona\(\s*p_source_persona_id uuid,\s*"
                              r"p_expected_version integer,\s*p_action text,\s*p_canonical_person_id bigint,\s*p_note text\s*\)", s)))


def kernekald(s: str) -> list[tuple[str | None, str | None, str, int]]:
    """(omsluttende funktion, oprindelse, kaldtekst, position) for hvert kald af kernen."""
    ud = []
    for m in re.finditer(re.escape(KERNE), s):
        if re.search(r"FUNCTION\s+$", s[max(0, m.start() - 30):m.start()]) or s[m.end():m.end() + 5] == "uuid,":
            continue   # definitionen selv og REVOKE-signaturer
        i, dybde = m.end(), 1
        while dybde:
            dybde += {"(": 1, ")": -1}.get(s[i], 0)
            i += 1
        kald = s[m.start():i]
        o = re.search(r"'([a-z_]+)'\s*\)$", kald)
        fn = None
        for f in re.finditer(r"FUNCTION\s+([a-z0-9_.]+)\(", s[:m.start()]):   # cifre: red_apply_1939_v50_…
            fn = f
        ud.append((fn.group(1).split(".")[-1] if fn else None, o.group(1) if o else None, kald, m.start()))
    return ud


def optael(s: str, fil: str) -> dict:
    t: dict = {}
    for fn, o, kald, _ in kernekald(s):
        assert o in OPRINDELSER, f"{fil}: kald uden lovlig oprindelse i {fn}: {kald[-80:]}"
        t[(fil, fn, o)] = t.get((fil, fn, o), 0) + 1
    return t


def test_checkeren_fanger_fejl():
    ok = "CREATE FUNCTION public.red_afgoer_source_persona(x int) AS $$ BEGIN PERFORM private.decide_source_persona_identity(a,b,0,'x','{}','human'); END $$;"
    assert optael(ok, "f") == {("f", "red_afgoer_source_persona", "human"): 1}
    for daarlig in ["CREATE FUNCTION f() AS $$ PERFORM private.decide_source_persona_identity(a,b,0,'x','{}'); $$;",
                    "CREATE FUNCTION f() AS $$ PERFORM private.decide_source_persona_identity(a,b,0,'x','{}','batch'); $$;"]:
        with pytest.raises(AssertionError):
            optael(daarlig, "f")
    ukendt = "CREATE FUNCTION public.ny_writer() AS $$ PERFORM private.decide_source_persona_identity(a,b,0,'x','{}','human'); $$;"
    assert ("f", "ny_writer", "human") in optael(ukendt, "f")   # fanges af allowlist-sammenligningen


def test_kaldere_er_praecis_allowlisten():
    faktisk = {**optael(_tekst("schema.sql"), "schema.sql"), **optael(_tekst("db-migrations.sql"), "db-migrations.sql")}
    assert faktisk == ALLOWLIST


def test_ingen_offentlig_kerne_uden_for_cutover_og_drop():
    for navn in ("schema.sql", "db-migrations.sql"):
        assert offentlig_kerne_uden_for_cutover((ROOT / navn).read_text(encoding="utf-8")) == [], navn


def test_femarguments_wrapper_findes_kun_i_cutover_og_drop():
    for navn in ("schema.sql", "db-migrations.sql"):
        assert not femarguments_wrapper_uden_for_cutover((ROOT / navn).read_text(encoding="utf-8")), navn


# Den planlagte blok (Step 8) ordret: vagten skal ignorere den, men kun inden for markørerne.
CUTOVER_FIXTURE = r"""-- BEGIN 5a-cutover (#151): lukker klientvejen til den gamle identitetskerne og femarguments-
DO $cutover_5a$
BEGIN
  IF to_regprocedure('public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
  END IF;
  IF to_regprocedure('public.red_afgoer_source_persona(uuid,integer,text,bigint,text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.red_afgoer_source_persona(uuid,integer,text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
  END IF;
END $cutover_5a$;
-- END 5a-cutover
"""


def test_cutover_blokken_ignoreres_kun_inden_for_markoererne():
    assert offentlig_kerne_uden_for_cutover(CUTOVER_FIXTURE) == []
    assert not femarguments_wrapper_uden_for_cutover(CUTOVER_FIXTURE)
    uden_markoerer = CUTOVER_FIXTURE.replace("-- BEGIN 5a-cutover", "-- BEGIN x").replace("-- END 5a-cutover", "-- END x")
    assert offentlig_kerne_uden_for_cutover(uden_markoerer)
    assert femarguments_wrapper_uden_for_cutover(uden_markoerer)
    # Regressionsvagt: strip-først-rækkefølgen ville aldrig skære blokken ud.
    assert "red_decide_source_persona_identity(" in CUTOVER.sub("", _uden_kommentarer(CUTOVER_FIXTURE))


def test_kernen_grantes_aldrig():
    for navn in ("schema.sql", "db-migrations.sql"):
        for g in re.findall(r"GRANT[^;]*;", _tekst(navn), re.S):
            assert "decide_source_persona_identity" not in g and "insert_person_with_receipt" not in g, f"{navn}: {g[:120]}"


def test_person_create_kaldere_opretter_via_kvittering():
    for navn in ("schema.sql", "db-migrations.sql"):
        s = _tekst(navn)
        for fn, o, _, pos in kernekald(s):
            if o != "person_create":
                continue
            start = max(m.start() for m in re.finditer(r"FUNCTION\s+[a-z0-9_.]+\(", s[:pos]))
            krop = s[start:pos]
            assert "insert_person_with_receipt(" in krop and "INSERT INTO public.person(" not in krop, f"{navn}: {fn}"


def test_cutover_staar_foer_foerste_saetning():
    raa = (ROOT / "db-migrations.sql").read_text(encoding="utf-8")
    blok = CUTOVER.search(raa)
    assert blok, "cutover-blokken mangler"
    foerste = re.search(r"^(CREATE|ALTER|DROP|GRANT|REVOKE|INSERT|UPDATE|DELETE|DO|COMMENT)\b", raa, re.M)
    assert foerste and foerste.start() > blok.start(), "en sætning står før cutover-blokken"
    for sig in ("public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)",
                "public.red_afgoer_source_persona(uuid,integer,text,bigint,text)"):
        assert f"REVOKE ALL ON FUNCTION {sig} FROM PUBLIC,anon,authenticated,service_role" in blok.group(0), sig


def test_person_purge_udbakke_er_ikke_identitetsskrivere():
    # Task 12: læsning / kvittering / annullering ved stigenbrug; ingen identitetsskrivning.
    for navn in ("schema.sql", "db-migrations.sql"):
        s = _tekst(navn)
        for skema, fn in (("public", "red_person_purge_udbakke"),
                          ("public", "red_person_purge_udbakke_kvitter"),
                          ("private", "person_purge_udbakke_genbrug")):
            assert re.search(r"FUNCTION\s+" + skema + r"\." + fn + r"\(", s), (navn, fn)
            assert not any(kalder == fn for kalder, _, _, _ in kernekald(s)), (navn, fn)
