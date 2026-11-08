"""Trin 6c-3: afstemningsværktøjet (spec 2026-11-07-trin6c3-a6b-resten-design.md §4.3-§4.5; plan Task 5).

Alle fixtures er syntetiske JSON (ingen database): id'er, nøgler og opdigtede værdier, ingen posttekst. Matchningen
gammel → ny står i `tekstrevision_afstemning.sql`; her testes værktøjets forbrug af dens udskrift (kandidatmængderne og
udfaldet), afgrænsningen, oversættelsen af kortsvar og den genererede SQL's struktur."""
from __future__ import annotations

import copy
import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

import control_model_v2 as v2
import tekstrevision_afstemning as ta

SRC = 1
CM_SCRIPT = str(Path(__file__).with_name("control_model_v2.py"))


def key(n: int) -> str:
    return f"aaaaaaaa-0000-4000-8000-{n:012d}"


def sid(n: int) -> str:     # stand-in'ens interpretation.id
    return f"00000000-0000-4000-8000-{n:012d}"


def pid_(n: int) -> str:    # prods interpretation.id (andre tilfældige id'er)
    return f"99999999-0000-4000-8000-{n:012d}"


def per(n: int) -> str:     # persona-id (samme i begge baser for eksisterende personas)
    return f"11111111-0000-4000-8000-{n:012d}"


def prom(n: int) -> str:
    return f"22222222-0000-4000-8000-{n:012d}"


# --- syntetisk afstemning ---------------------------------------------------------------------------------------

def gammel(n, *, art, predicate, persona="I-9#p", principal=None, modpart=None, ordinal=None, bindinger=(),
           kandidater=(), rettelse=(), record="I-9", element=None):
    return {"interpretation_key": key(n), "version": 2, "status": "superseded", "status_foer": "accepted",
            "element_id": element or f"source-text-revision:{record}", "record_key": record, "predicate": predicate,
            "art": art, "persona": persona, "principal": principal, "modpart": modpart, "marriage_ordinal": ordinal,
            "bindinger": [{"promotion_id": p, "target_type": t, "target_id": i} for p, t, i in bindinger],
            "kandidater": sorted(kandidater), "rettelse_kandidater": sorted(rettelse)}


def ny(n, *, predicate, persona="I-9#p", principal=None, modpart=None, ordinal=None, familie=None, record="I-9",
       status="proposed", version=1):
    return {"interpretation_key": key(n), "version": version, "status": status,
            "element_id": f"source-text-revision:{record}", "record_key": record, "predicate": predicate,
            "persona": persona, "principal": principal, "modpart": modpart, "marriage_ordinal": ordinal,
            "familie": familie, "binding_familie": None}


def afstemning(gamle, nye, *, fase="efter_parter", aegteskab=None):
    """Udfald og bindingsafsnit afledes som SQL'en gør (samme regel som ta.udled_udfald)."""
    a = {"contract": ta.AFSTEMNING_CONTRACT, "batch_id": "33333333-0000-4000-8000-000000000001", "fase": fase,
         "source_id": SRC, "gamle": copy.deepcopy(gamle), "nye": copy.deepcopy(nye),
         "aegteskab_afgoerelsessaet": None if fase == "foer_parter" else sorted(aegteskab or [])}
    udf = ta.udled_udfald(a["gamle"], fase)
    bindinger = []
    for g in a["gamle"]:
        u, n, grund = udf[g["interpretation_key"]]
        g.update(udfald=u, ny_noegle=n, grund=grund)
        for b in g["bindinger"]:
            bindinger.append({**b, "gammel_noegle": g["interpretation_key"], "udfald": u, "ny_noegle": n,
                              "ny_binding": False, "fremmed_binding": False})
    a["bindinger"] = sorted(bindinger, key=lambda b: b["promotion_id"])
    a["logisk_sha256"] = "f" * 64
    return a


def fakta_svar(felter=(), maskine=()):
    return {"contract": ta.KORTSVAR_CONTRACT, "source_id": SRC,
            "felter": [{"interpretation_key": k, "version": 1, "svar": s, "note": "", "klasse": c,
                        "grundlag_sha256": "0" * 64} for k, c, s in felter],
            "personas": [{"persona_key": "I-9#p", "identity_version": 1, "svar": "-"}],
            "plan": {"univers": sorted([k, 1] for k, _, _ in felter) + sorted([k, 1] for k in maskine),
                     "match": sorted([k, 1] for k, c, _ in felter if c == "MATCH") + sorted([k, 1] for k in maskine),
                     "maskine": sorted([k, 1] for k in maskine),
                     "stikproeve": sorted(k for k, c, _ in felter if c == "MATCH"),
                     "real_diff": sorted(k for k, c, _ in felter if c == "REAL_DIFF"),
                     "skrivemaade": sorted(k for k, c, _ in felter if c == "SKRIVEMAADE")}}


def rel_svar(items=()):
    return {"contract": ta.RELATIONSSVAR_CONTRACT,
            "items": [{"interpretation_key": k, "version": 1, "predicate": p, "svar": s} for k, p, s in items]}


def refs(ark: str) -> list[str]:
    return [m[1] for m in re.finditer(r"^T (\S+) : ", ark, re.M)]


def ref(old: int, ttype: str, tid: int) -> str:
    return f"{key(old)}@{ttype}:{tid}"


# --- I-89: to ægteskaber, modellen genfinder ét (Review Focus 1) -------------------------------------------------

def i89(*, genfundet_a=False, b_claim=False):
    """Gamle A (nr. 1, familie 501, ægtefælle A) og B (nr. 2, familie 502, ægtefælle B); ny N som nr. 1."""
    g = [gammel(1, art="aegteskab", predicate="relation.marriage", record="I-89", persona="I-89#p",
                principal="I-89#p", modpart="I-89#rel-marriage-10-8", ordinal=1, bindinger=[(prom(1), "family", 501)],
                kandidater=[key(101)] if genfundet_a else []),
         gammel(2, art="aegteskab", predicate="relation.marriage", record="I-89", persona="I-89#p",
                principal="I-89#p", modpart="I-89#rel-marriage-40-9", ordinal=2, bindinger=[(prom(2), "family", 502)],
                kandidater=[key(101)] if b_claim else [])]
    if genfundet_a:
        n = ny(101, predicate="relation.marriage", record="I-89", persona="I-89#p", principal="I-89#p",
               modpart="I-89#rel-marriage-10-8", ordinal=1, familie=501)
    else:   # nummeret flyttede: B står nu som nr. 1 med en ny ægtefælle-persona uden identitet (ingen familie)
        n = ny(101, predicate="relation.marriage", record="I-89", persona="I-89#p", principal="I-89#p",
               modpart="I-89#rel-marriage-38-9", ordinal=1, familie=None)
    return g, [n]


def test_ordinal_flyttet_er_ikke_genfundet(tmp_path):
    g, n = i89()
    a = afstemning(g, n)
    assert [x["udfald"] for x in a["gamle"]] == ["ikke_genfundet", "ikke_genfundet"]
    fv = ta.forventet(a, fakta_svar(), rel_svar())
    assert fv["aegteskaber"] == [] and fv["relationsbindinger"] == []
    assert refs(ta.tilbagetraek_ark(a, fakta_svar(), rel_svar())) == sorted([ref(1, "family", 501),
                                                                            ref(2, "family", 502)])
    sql = ta.relationer_sql(a, fakta_svar(), rel_svar())
    assert "'[]'::jsonb" in sql and "red_promote_relation_interpretations_batch" not in sql

    # Det genfundne (A med samme nummer og familie) bindes; B kommer på kortet.
    g, n = i89(genfundet_a=True)
    a = afstemning(g, n, aegteskab=[key(101)])
    assert a["gamle"][0]["udfald"] == "genfundet" and a["gamle"][1]["udfald"] == "ikke_genfundet"
    fv = ta.forventet(a, fakta_svar(), rel_svar())
    assert fv["aegteskaber"] == [key(101)]
    assert fv["relationsbindinger"] == [{"interpretation_key": key(101), "family_id": 501,
                                         "predicate": "relation.marriage"}]
    assert refs(ta.tilbagetraek_ark(a, fakta_svar(), rel_svar())) == [ref(2, "family", 502)]

    # En udskrift, der påstår B genfundet med et flyttet nummer: ingen binding, B på kortet, og står N i
    # afgørelsessættet, stopper relationer-sql (ægteskabet må ikke afgøres maskinelt mod en anden familie).
    g, n = i89(b_claim=True)
    n[0]["modpart"] = "I-89#rel-marriage-40-9"
    n[0]["familie"] = 502
    a = afstemning(g, n)
    assert a["gamle"][1]["udfald"] == "genfundet"
    fv = ta.forventet(a, fakta_svar(), rel_svar())
    assert fv["aegteskaber"] == [] and fv["bindinger"][prom(2)]["genbundet"] is False
    assert ref(2, "family", 502) in refs(ta.tilbagetraek_ark(a, fakta_svar(), rel_svar()))
    a2 = afstemning(g, n, aegteskab=[key(101)])
    with pytest.raises(ta.AfstemningError, match="AEGTESKAB_MAENGDE_AFVIGER"):
        ta.relationer_sql(a2, fakta_svar(), rel_svar())


def test_udfald_tvetydig_er_ikke_genfundet():
    g = [gammel(1, art="ubundet", predicate="person.title", kandidater=[key(101), key(102)]),
         gammel(2, art="ubundet", predicate="person.office", kandidater=[key(103)]),
         gammel(3, art="ubundet", predicate="person.office", kandidater=[key(103)])]
    u = ta.udled_udfald(g, "efter_parter")
    assert u[key(1)] == ("ikke_genfundet", None, "flere")
    assert u[key(2)] == ("ikke_genfundet", None, "delt") and u[key(3)] == ("ikke_genfundet", None, "delt")


def test_relationer_afventer_foer_parter():
    g = [gammel(1, art="barn", predicate="relation.child", bindinger=[(prom(1), "family", 7)])]
    a = afstemning(g, [], fase="foer_parter")
    assert a["gamle"][0]["udfald"] == "afventer"
    with pytest.raises(ta.AfstemningError, match="AFSTEMNING_FASE_AFVIGER"):
        ta.forventet(a, fakta_svar(), rel_svar())


def test_sql_udfald_skal_stemme_med_kandidaterne():
    g = [gammel(1, art="ubundet", predicate="person.title", kandidater=[key(101)])]
    a = afstemning(g, [ny(101, predicate="person.title")])
    a["gamle"][0]["udfald"] = "ikke_genfundet"
    a["gamle"][0]["ny_noegle"] = None
    with pytest.raises(ta.AfstemningError, match="AFSTEMNING_JSON_UGYLDIG"):
        ta.laes_afstemning(a)


# --- fakta og tilbagetrækningsarket (Review Focus 5) --------------------------------------------------------------

def fakta_post():
    """Død (gammel 1, bundet til påstand 900) og navn (gammel 2, bundet til påstand 901)."""
    g = [gammel(1, art="fakta", predicate="person.death", bindinger=[(prom(1), "assertion", 900)],
                kandidater=[key(101)]),
         gammel(2, art="fakta", predicate="person.name", bindinger=[(prom(2), "assertion", 901)],
                kandidater=[], rettelse=[key(102)])]
    n = [ny(101, predicate="person.death"), ny(102, predicate="person.name")]
    return g, n


def test_real_diff_b_fjerner_binding_fra_tilbagetraek():
    g, n = fakta_post()
    a = afstemning(g, n)
    assert a["gamle"][1]["udfald"] == "ikke_genfundet"    # værdien er en anden end den bundne påstands
    # B på REAL_DIFF'et, der retter netop den bundne påstand og binder: navnebindingen står ikke på arket.
    s = fakta_svar([(key(101), "MATCH", "B"), (key(102), "REAL_DIFF", "B")])
    ark = ta.tilbagetraek_ark(a, s, rel_svar())
    assert refs(ark) == []
    fv = ta.forventet(a, s, rel_svar())
    assert fv["udfald"][key(2)] == {"udfald": "genfundet", "ny_noegle": key(102)}
    assert fv["bindinger"][prom(2)] == {"genbundet": True, "ny_noegle": key(102), "gammel_noegle": key(2),
                                        "target_type": "assertion", "target_id": 901}
    # D (databasen har ret) eller V: bindingen står på arket.
    for tok in ("D", "V"):
        s = fakta_svar([(key(101), "MATCH", "B"), (key(102), "REAL_DIFF", tok)])
        assert refs(ta.tilbagetraek_ark(a, s, rel_svar())) == [ref(2, "assertion", 901)]
    # Kvitteringens genbundet afledes af tilstanden: SQL'en bærer kun forventningen, ingen ny promotion.
    s = fakta_svar([(key(101), "MATCH", "B"), (key(102), "REAL_DIFF", "B")])
    sql = ta.kvittering_sql(a, s, rel_svar(), ta.parse_tilbagetraek(ark, a, s, rel_svar()),
                            kontekst=_ctx())
    assert "text_revision_binding_set" in sql and "write_text_revision_reconciliation" in sql
    assert "new_promotion_id" in sql and prom(1) in sql and not re.search(r"new_promotion_id\"\s*:\s*\"", sql)


def test_stikproeven_skal_vaere_b():
    g, n = fakta_post()
    with pytest.raises(ta.AfstemningError, match="KORT_STIKPROEVE_IKKE_B"):
        ta.forventet(afstemning(g, n), fakta_svar([(key(101), "MATCH", "D")]), rel_svar())


def test_rettelse_konflikt_stopper():
    g, n = fakta_post()
    g[1]["kandidater"] = [key(103)]
    n.append(ny(103, predicate="person.name"))
    a = afstemning(g, n)
    s = fakta_svar([(key(101), "MATCH", "B"), (key(102), "REAL_DIFF", "B"), (key(103), "MATCH", "B")])
    with pytest.raises(ta.AfstemningError, match="AFSTEMNING_RETTELSE_KONFLIKT"):
        ta.forventet(a, s, rel_svar())


def _ctx():
    return {"svar_sha256": "1" * 64, "relationssvar_sha256": "2" * 64, "tilbagetraek_sha256": "3" * 64,
            "oversat_ark_sha256": "4" * 64}


def test_tilbagetraek_parse_afviser_ubesvarede_og_ukendte(tmp_path):
    g, n = fakta_post()
    a = afstemning(g, n)
    s = fakta_svar([(key(101), "MATCH", "B"), (key(102), "REAL_DIFF", "V")])
    ark = ta.tilbagetraek_ark(a, s, rel_svar())
    with pytest.raises(ta.AfstemningError, match="TILBAGETRAEK_LINJE_UGYLDIG"):
        ta.parse_tilbagetraek(ark, a, s, rel_svar())            # ubesvaret (_)
    besvaret = ark.replace(": _", ": V")
    assert ta.parse_tilbagetraek(besvaret, a, s, rel_svar()) == {
        prom(2): {"svar": "ved_ikke", "ref": ref(2, "assertion", 901)}}
    ukendt = besvaret + f"T {ref(9, 'assertion', 1)} : T\n"
    with pytest.raises(ta.AfstemningError, match="TILBAGETRAEK_LINJE_UGYLDIG"):
        ta.parse_tilbagetraek(ukendt, a, s, rel_svar())
    with pytest.raises(ta.AfstemningError, match="TILBAGETRAEK_LINJE_UGYLDIG"):
        ta.parse_tilbagetraek(besvaret.replace(": V", ": X"), a, s, rel_svar())
    with pytest.raises(ta.AfstemningError, match="TILBAGETRAEK_LINJER_MANGLER"):
        ta.parse_tilbagetraek(re.sub(r"^T .*\n", "", besvaret, flags=re.M), a, s, rel_svar())
    # Arket er bygget over andre svar (fx B i stedet for V): grundlaget afviger.
    s_b = fakta_svar([(key(101), "MATCH", "B"), (key(102), "REAL_DIFF", "B")])
    with pytest.raises(ta.AfstemningError, match="TILBAGETRAEK"):
        ta.parse_tilbagetraek(besvaret, a, s_b, rel_svar())


# --- kvitteringen og preflighten ---------------------------------------------------------------------------------

def blandet_post():
    """Fakta (genbundet), et ikke-genfundet faktum (tilbagetrukket), et barn (B, genbundet), et ubundet forslag."""
    g = [gammel(1, art="fakta", predicate="person.death", bindinger=[(prom(1), "assertion", 900)],
                kandidater=[key(101)]),
         gammel(2, art="fakta", predicate="person.title", bindinger=[(prom(2), "assertion", 901)]),
         gammel(3, art="barn", predicate="relation.child", principal="I-9#p", bindinger=[(prom(3), "family", 77)],
                kandidater=[key(103)]),
         gammel(4, art="ubundet", predicate="person.office", kandidater=[key(104)])]
    n = [ny(101, predicate="person.death"), ny(103, predicate="relation.child", principal="I-9#p", familie=77),
         ny(104, predicate="person.office")]
    return afstemning(g, n), fakta_svar([(key(101), "MATCH", "B")]), \
        rel_svar([(key(103), "relation.child", "B")])


def _forventning(sql: str) -> dict:
    m = re.search(r"e jsonb := '(.*?)'::jsonb;", sql, re.S)
    return json.loads(m[1].replace("''", "'"))


def test_kvittering_sql_daekker_hver_binding_praecis_en_gang():
    a, s, r = blandet_post()
    ark = ta.tilbagetraek_ark(a, s, r).replace(": _", ": T")
    tv = ta.parse_tilbagetraek(ark, a, s, r)
    assert set(tv) == {prom(2)}
    sql = ta.kvittering_sql(a, s, r, tv, kontekst=_ctx())
    e = _forventning(sql)
    assert sorted(e["bindinger"]) == sorted(b["promotion_id"] for b in a["bindinger"])
    assert sorted(e["udfald"]) == sorted(g["interpretation_key"] for g in a["gamle"])
    genbundet = {p for p, x in e["bindinger"].items() if x["genbundet"]}
    tilbage = {p for p, x in e["bindinger"].items() if not x["genbundet"]}
    assert genbundet == {prom(1), prom(3)} and tilbage == {prom(2)} and not genbundet & tilbage
    assert e["bindinger"][prom(2)]["svar"] == "T" and e["bindinger"][prom(2)]["ref"] == ref(2, "assertion", 901)
    assert all(x["svar"] is None for p, x in e["bindinger"].items() if x["genbundet"])
    assert "fase efter_afgoerelser" in sql and ":'actor'" in sql and "COMMIT;" in sql
    # Ingen interpretation.id'er eller nye promotions i filen: kun de gamle promotions (revisionens mængde).
    uuids = set(re.findall(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", sql))
    assert uuids <= {g["interpretation_key"] for g in a["gamle"]} | {n["interpretation_key"] for n in a["nye"]} \
        | {b["promotion_id"] for b in a["bindinger"]}
    # Et svar på en binding, der genbindes, eller et manglende svar: stop før SQL.
    with pytest.raises(ta.AfstemningError, match="TILBAGETRAEK_SVAR_AFVIGER"):
        ta.kvittering_sql(a, s, r, {**tv, prom(1): {"svar": "T", "ref": "x"}}, kontekst=_ctx())
    with pytest.raises(ta.AfstemningError, match="TILBAGETRAEK_SVAR_AFVIGER"):
        ta.kvittering_sql(a, s, r, {}, kontekst=_ctx())


def test_afvist_kandidat_er_ikke_genfundet():
    """R på det genfundne barn: den nye nøgle bliver rejected, så den gamle nøgle er ikke genfundet efter
    afgørelserne (writeren afviser genfundet → rejected), og bindingen står på T/V-arket."""
    a, s, _ = blandet_post()
    r = rel_svar([(key(103), "relation.child", "R")])
    fv = ta.forventet(a, s, r)
    assert fv["udfald"][key(3)] == {"udfald": "ikke_genfundet", "ny_noegle": None}
    assert fv["bindinger"][prom(3)]["genbundet"] is False and fv["relationsbindinger"] == []
    assert ref(3, "family", 77) in refs(ta.tilbagetraek_ark(a, s, r))
    # U (lad stå): stadig genfundet (forslaget består), men ikke bundet → T/V.
    u = rel_svar([(key(103), "relation.child", "U")])
    assert ta.forventet(a, s, u)["udfald"][key(3)] == {"udfald": "genfundet", "ny_noegle": key(103)}
    assert ref(3, "family", 77) in refs(ta.tilbagetraek_ark(a, s, u))


def test_preflight_afviser_forventet_maal_forskelligt_fra_gammelt():
    a, s, r = blandet_post()
    pf = ta.preflight_sql(a, s, r)
    assert "SET TRANSACTION READ ONLY" in pf and "ROLLBACK;" in pf and "PREFLIGHT_MAAL_AFVIGER" in pf
    assert "interpretation_control_classification.sql" in pf and "fase efter_parter" in pf
    # Fakta: den forventede MATCH-binding skal ramme den gamle bindings påstand (kontrolleres i basen).
    e = json.loads(re.search(r"f jsonb := '(.*?)'::jsonb;", pf, re.S)[1].replace("''", "'"))
    assert {"interpretation_key": key(101), "version": 1, "klasse": "MATCH", "maal": 900} in e
    # Barnet: den nye nøgles familie i afstemningen er ikke den gamle bindings mål → stop allerede her.
    a2 = copy.deepcopy(a)
    next(n for n in a2["nye"] if n["interpretation_key"] == key(103))["familie"] = 78
    with pytest.raises(ta.AfstemningError, match="PREFLIGHT_MAAL_AFVIGER"):
        ta.preflight_sql(a2, s, r)


# --- relationer-sql (ægteskabsmængden) ----------------------------------------------------------------------------

def test_relationer_sql_forkert_aegteskabsmaengde():
    g, n = i89(genfundet_a=True)
    a = afstemning(g, n, aegteskab=[key(101)])
    sql = ta.relationer_sql(a, fakta_svar(), rel_svar())
    assert f"'[\"{key(101)}\"]'::jsonb" in sql and "AEGTESKAB_MAENGDE_AFVIGER" in sql
    assert sql.index("relation_decision_set") < sql.index("red_decide_relation_interpretations") \
        < sql.index("red_preview_relation_promotions") < sql.index("red_promote_relation_interpretations_batch")
    # Afgørelsessættet har en nøgle mere (et andet af kildens ægteskaber) eller mangler det genfundne.
    for saet in ([key(101), key(999)], []):
        with pytest.raises(ta.AfstemningError, match="AEGTESKAB_MAENGDE_AFVIGER"):
            ta.relationer_sql(afstemning(g, n, aegteskab=saet), fakta_svar(), rel_svar())


# --- afgrænsning (Review Focus 3) ---------------------------------------------------------------------------------

def _klassifikation(ids_klasse):
    return {"items": [{"interpretation_id": i, "version": 1, "predicate": "person.death", "class": c,
                       "assertion_id": 900 + n if c == "MATCH" else None}
                      for n, (i, c) in enumerate(ids_klasse)],
            "counts": {"person.death": {"MATCH": 99}}}


def _row(i, *, persona, record="I-9", predicate="person.death", value="1850", faktatype="død", graenser=None,
         kilde=(SRC,)):
    return {"interpretation_id": i, "version": 1, "record_key": record, "predicate": predicate, "value_text": value,
            "confidence": 1, "persona_role": "principal", "cited": [{"ordinal": 1, "text": "x", "flags": []}],
            "persona_id": persona, "identity_outcome": "enig", "identity_version": 1, "navn_forkortes": False,
            "rettelse_maal": {"assertion_id": 700, "forventet": {"fact_id": 1, "faktatype": faktatype,
                                                                 "vaerdi_tekst": None, "date_raw": "1849",
                                                                 "valgt_assertion_id": 700,
                                                                 "citation_sources": list(kilde)},
                              "graenser": graenser or {"date_min": "1849-01-01", "date_max": "1849-12-31",
                                                       "date_qualifier": None}}}


def _idkort(par, personas):
    return {"contract": ta.IDKORT_CONTRACT, "source_id": SRC,
            "interpretations": [{"id": i, "interpretation_key": k, "version": 1} for i, k in par],
            "personas": [{"id": p, "persona_key": pk, "canonical_person_id": c, "identity_version": 1}
                         for p, pk, c in personas]}


def _skriv(path: Path, obj) -> Path:
    path.write_text(json.dumps(obj), encoding="utf-8")
    return path


def test_afgraens_fjerner_andre_noegler(tmp_path):
    # Kildebred klassifikation: to af de nye nøgler og to af kilde 1's andre forslag.
    ids = [(sid(1), "MATCH"), (sid(2), "REAL_DIFF"), (sid(3), "MATCH"), (sid(4), "REAL_DIFF")]
    k = _klassifikation(ids)
    rows = [_row(sid(1), persona=per(1)), _row(sid(2), persona=per(1)), _row(sid(3), persona=per(2)),
            _row(sid(4), persona=per(3))]
    idk = _idkort([(sid(n), key(n)) for n in range(1, 5)],
                  [(per(1), "I-9#p", 10), (per(2), "X-1#p", 20), (per(3), "X-2#p", 30)])
    (tmp_path / "noegler.txt").write_text(f"{key(1)}\n{key(2)}\n", encoding="utf-8")
    ud = tmp_path / "afgr"
    assert ta.main(["afgraens", "--noegler", str(tmp_path / "noegler.txt"), "--idkort",
                    str(_skriv(tmp_path / "idkort.json", idk)), "--classification",
                    str(_skriv(tmp_path / "k.json", k)), "--rows", str(_skriv(tmp_path / "r.json", rows)),
                    "--out-dir", str(ud), "--private-root", str(tmp_path)]) == 0
    k2 = json.loads((ud / "classification.json").read_text())
    r2 = json.loads((ud / "rows.json").read_text())
    i2 = json.loads((ud / "idkort.json").read_text())
    assert [i["interpretation_id"] for i in k2["items"]] == [sid(1), sid(2)]
    assert k2["counts"] == {"person.death": {**{c: 0 for c in ta.BASIS_KLASSER}, "MATCH": 1, "REAL_DIFF": 1}}
    assert [r["interpretation_id"] for r in r2] == [sid(1), sid(2)]
    assert i2["afgraenset"] is True and {e["id"] for e in i2["interpretations"]} == {sid(1), sid(2)}
    assert {p["id"] for p in i2["personas"]} == {per(1)}
    assert (ud / "rows.json").stat().st_mode & 0o777 == 0o600
    # Kontrolmodellen accepterer det afgrænsede input.
    p = v2.plan_run_v2(k2, r2, source_id=SRC, strata={"ubekraeftet": 0, "oevrige": 20})
    assert p["universe_ids"] == [sid(1), sid(2)] and p["sample_ids"] == [sid(1)]
    # En plan med et id uden for listen (bygget af den uafgrænsede klassifikation) afvises.
    p_fuld = v2.plan_run_v2(k, rows, source_id=SRC, strata={"ubekraeftet": 0, "oevrige": 20})
    with pytest.raises(ta.AfstemningError, match="AFGRAENSNING_LAEK"):
        ta.tjek_plan_afgraenset(p_fuld, i2)
    # Det uafgrænsede id-kort godtages ikke som afgrænsning.
    with pytest.raises(ta.AfstemningError, match="IDKORT_IKKE_AFGRAENSET"):
        ta.tjek_plan_afgraenset(p, idk)


def test_afgraensning_laek_i_selve_beskaeringen():
    with pytest.raises(ta.AfstemningError, match="AFGRAENSNING_LAEK"):
        ta.tjek_afgraenset({"items": [{"interpretation_id": sid(3)}]}, [], {sid(1)})


# --- kortsvar og oversaet (Review Focus 4) -----------------------------------------------------------------------

def _plan_dir(tmp: Path, navn: str, k: dict, rows: list) -> Path:
    d = tmp / navn
    d.mkdir()
    kf, rf = _skriv(d / "k.json", k), _skriv(d / "r.json", rows)
    out = subprocess.run([sys.executable, CM_SCRIPT, "plan", "--classification", str(kf), "--rows", str(rf),
                          "--source-id", str(SRC), "--strata-ubekraeftet", "0", "--strata-oevrige", "20",
                          "--out-dir", str(d / "plan")], capture_output=True, text=True)
    assert out.returncode == 0, out.stdout + out.stderr
    return d / "plan"


def _base(idf, *, klasse2="REAL_DIFF", rows_kw=None):
    """Tre felter på to personas: en MATCH (stikprøve), et REAL_DIFF og et SKRIVEMAADE. Nøgler 1-3."""
    rows_kw = rows_kw or {}
    k = _klassifikation([(idf(1), "MATCH"), (idf(2), klasse2), (idf(3), "SKRIVEMAADE")])
    rows = [_row(idf(1), persona=per(1)), _row(idf(2), persona=per(1), **rows_kw.get(2, {})),
            _row(idf(3), persona=per(2), predicate="person.name", value="Anna", faktatype="navn")]
    idk = {**_idkort([(idf(n), key(n)) for n in (1, 2, 3)], [(per(1), "I-9#p", 10), (per(2), "I-11#p", 11)]),
           "afgraenset": True, "noegler_sha256": "5" * 64}
    return k, rows, idk


def _besvar(plan: dict, svar: dict) -> str:
    fields = {r["interpretation_id"]: (svar[r["interpretation_id"]], "") for r in plan["rows_kontrol"]}
    return v2.render_sheet_v2(plan, {p["persona_id"]: "-" for p in plan["personas"]}, fields)


def _kortsvar(tmp, plan_dir, ark_text, idk, navn="svar.json", rc=0):
    (tmp / f"{navn}.ark").write_text(ark_text, encoding="utf-8")
    res = ta.main(["kortsvar", "--plan-dir", str(plan_dir), "--ark", str(tmp / f"{navn}.ark"), "--idkort",
                   str(_skriv(tmp / f"{navn}.idkort", idk)), "--out", str(tmp / navn), "--private-root", str(tmp)])
    assert res == rc
    return tmp / navn


def test_kortsvar_oversaet_roundtrip(tmp_path):
    k, rows, idk = _base(sid)
    pd = _plan_dir(tmp_path, "standin", k, rows)
    plan, _ = v2._load_plan(pd)
    svar = {sid(1): "B", sid(2): "B", sid(3): "V"}
    ark = _besvar(plan, svar).replace(f"F {sid(2)} 1 : B", f"F {sid(2)} 1 : B # bogen har ret")
    sf = _kortsvar(tmp_path, pd, ark, idk)
    s = json.loads(sf.read_text())
    assert sf.stat().st_mode & 0o777 == 0o600
    assert [f["interpretation_key"] for f in s["felter"]] == [key(1), key(2), key(3)]
    assert [f["svar"] for f in s["felter"]] == ["B", "B", "V"] and s["felter"][1]["note"] == "bogen har ret"
    assert all(re.fullmatch(r"[0-9a-f]{64}", f["grundlag_sha256"]) for f in s["felter"])
    assert s["personas"] == [{"persona_key": "I-9#p", "identity_version": 1, "svar": "-"},
                             {"persona_key": "I-11#p", "identity_version": 1, "svar": "-"}]
    # Ingen interpretation.id i svarfilen.
    assert not re.search(r"0{8}-0000-4000-8000", sf.read_text())

    # Prod: samme nøgler, andre interpretation.id'er.
    kp, rowsp, idkp = _base(pid_)
    pp = _plan_dir(tmp_path, "prod", kp, rowsp)
    ud = tmp_path / "prod-ark.txt"
    assert ta.main(["oversaet", "--svar", str(sf), "--plan-dir", str(pp), "--idkort",
                    str(_skriv(tmp_path / "idkp.json", idkp)), "--out", str(ud), "--private-root",
                    str(tmp_path)]) == 0
    prod_ark = ud.read_text()
    plan_p, meta_p = v2._load_plan(pp)
    v2.apply_plan_v2(plan_p, prod_ark, sheet_sha256="a" * 64, hashes=meta_p)
    # Samme ark modulo id'er (persona-id'erne er de samme; felternes id'er er prods).
    assert prod_ark.replace("99999999-", "00000000-") == ark
    # Deterministisk: samme input giver samme bytes.
    ud2 = tmp_path / "prod-ark2.txt"
    ta.main(["oversaet", "--svar", str(sf), "--plan-dir", str(pp), "--idkort", str(tmp_path / "idkp.json"),
             "--out", str(ud2), "--private-root", str(tmp_path)])
    assert ud2.read_bytes() == ud.read_bytes()


@pytest.mark.parametrize("prod_kw", [
    {"klasse2": "SKRIVEMAADE"},                                                  # anden klasse
    {"rows_kw": {2: {"faktatype": "begravelse"}}},                               # samme klasse, andet rettelsesmål
    {"rows_kw": {2: {"kilde": (SRC, 3)}}},                                       # målets kilder
    {"rows_kw": {2: {"graenser": {"date_min": "1849-06-01", "date_max": "1849-12-31",
                                  "date_qualifier": None}}}},                    # andre datogrænser
])
def test_kort_prod_afviger(tmp_path, prod_kw, capsys):
    k, rows, idk = _base(sid)
    pd = _plan_dir(tmp_path, "standin", k, rows)
    plan, _ = v2._load_plan(pd)
    sf = _kortsvar(tmp_path, pd, _besvar(plan, {sid(1): "B", sid(2): "D", sid(3): "V"}), idk)
    kp, rowsp, idkp = _base(pid_, **prod_kw)
    pp = _plan_dir(tmp_path, "prod", kp, rowsp)
    ud = tmp_path / "prod-ark.txt"
    capsys.readouterr()
    assert ta.main(["oversaet", "--svar", str(sf), "--plan-dir", str(pp), "--idkort",
                    str(_skriv(tmp_path / "idkp.json", idkp)), "--out", str(ud), "--private-root",
                    str(tmp_path)]) == 1
    assert capsys.readouterr().out.startswith("KORT_PROD_AFVIGER")
    assert not ud.exists()


def test_kort_prod_afviger_ved_anden_version(tmp_path, capsys):
    k, rows, idk = _base(sid)
    pd = _plan_dir(tmp_path, "standin", k, rows)
    plan, _ = v2._load_plan(pd)
    sf = _kortsvar(tmp_path, pd, _besvar(plan, {sid(1): "B", sid(2): "D", sid(3): "V"}), idk)
    kp, rowsp, idkp = _base(pid_)
    for i in kp["items"]:
        i["version"] = 2
    for r in rowsp:
        r["version"] = 2
    for e in idkp["interpretations"]:
        e["version"] = 2
    pp = _plan_dir(tmp_path, "prod", kp, rowsp)
    capsys.readouterr()
    assert ta.main(["oversaet", "--svar", str(sf), "--plan-dir", str(pp), "--idkort",
                    str(_skriv(tmp_path / "idkp.json", idkp)), "--out", str(tmp_path / "x.txt"),
                    "--private-root", str(tmp_path)]) == 1
    assert capsys.readouterr().out.startswith("KORT_PROD_AFVIGER")


@pytest.mark.parametrize("p_svar", ["P", "P 4711"])
def test_kort_p_stopper(tmp_path, p_svar, capsys):
    k, rows, idk = _base(sid)
    pd = _plan_dir(tmp_path, "standin", k, rows)
    plan, _ = v2._load_plan(pd)
    ark = _besvar(plan, {sid(1): "B", sid(2): "D", sid(3): "V"}).replace(f"P {per(2)} 1 : -", f"P {per(2)} 1 : {p_svar}")
    capsys.readouterr()
    _kortsvar(tmp_path, pd, ark, idk, rc=1)
    assert capsys.readouterr().out.startswith("KORT_P_STOPPER")
    assert not (tmp_path / "svar.json").exists()


def test_kortsvar_afviser_plan_uden_for_afgraensningen(tmp_path, capsys):
    k, rows, idk = _base(sid)
    pd = _plan_dir(tmp_path, "standin", k, rows)
    plan, _ = v2._load_plan(pd)
    idk["interpretations"] = idk["interpretations"][:2]
    capsys.readouterr()
    _kortsvar(tmp_path, pd, _besvar(plan, {sid(1): "B", sid(2): "D", sid(3): "V"}), idk, rc=1)
    assert capsys.readouterr().out.startswith("AFGRAENSNING_LAEK")


# --- parter ---------------------------------------------------------------------------------------------------------

def _manifest(clause_id: str, n_extra=0):
    el = {}
    for n in range(1, 3 + n_extra):
        el[f"relation-persona:{key(n)}"] = {
            "birth_raw": None, "clause_observation_id": clause_id, "clause_set_seq": 2, "clause_set_sha256": "6" * 64,
            "death_raw": None, "interpretation_key": key(n), "interpretation_version": 1,
            "marriage_ordinal": n if n == 1 else None, "name_from": 13 if n == 1 else None,
            "name_to": 20 if n == 1 else None, "post_offset": 100 * n, "predicate": "relation.marriage" if n == 1
            else "relation.child", "profile": "relation-persona-2018-20-v1", "span_from": 5, "span_to": 25}
    return {"expected_counts": {"person_creates": 0, "source_evidence": 0, "relation_personas": len(el)},
            "authorized_elements": el, "input_sha256": clause_id[:8] * 8}


def _input(clause_id: str, raws=("Gift m. Bo Beta", "Børn: 2")):
    return {"input_sha256": clause_id[:8] * 8, "input": [
        {"interpretation_key": key(n), "interpretation_version": 1, "record_key": "I-89", "raw": raw,
         "clauses": [{"observation_id": clause_id}]} for n, raw in enumerate(raws, 1)]}


def test_parter_logisk_og_sammenlign(tmp_path, capsys):
    standin = tmp_path / "m-standin.json"
    _skriv(standin, _manifest("cccccccc-0000-4000-8000-000000000001"))
    _skriv(tmp_path / "in-standin.json", _input("cccccccc-0000-4000-8000-000000000001"))
    assert ta.main(["parter-logisk", "--manifest", str(standin), "--input", str(tmp_path / "in-standin.json"),
                    "--out", str(tmp_path / "logisk.json"), "--private-root", str(tmp_path)]) == 0
    lg = (tmp_path / "logisk.json").read_text()
    assert "cccccccc" not in lg and "Bo Beta" not in lg
    # Prod: andre klausul-id'er, samme logiske indhold → lig.
    _skriv(tmp_path / "m-prod.json", _manifest("dddddddd-0000-4000-8000-000000000002"))
    _skriv(tmp_path / "in-prod.json", _input("dddddddd-0000-4000-8000-000000000002"))
    argv = ["parter-sammenlign", "--forventet", str(tmp_path / "logisk.json"), "--manifest",
            str(tmp_path / "m-prod.json"), "--input", str(tmp_path / "in-prod.json"), "--private-root",
            str(tmp_path)]
    assert ta.main(argv) == 0
    # Et ekstra element, et andet spænd eller en anden værdi → PARTER_AFVIGER.
    _skriv(tmp_path / "m-prod.json", _manifest("dddddddd-0000-4000-8000-000000000002", n_extra=1))
    _skriv(tmp_path / "in-prod.json", _input("dddddddd-0000-4000-8000-000000000002",
                                             raws=("Gift m. Bo Beta", "Børn: 2", "Gift m. Cy")))
    capsys.readouterr()
    assert ta.main(argv) == 1 and capsys.readouterr().out.startswith("PARTER_AFVIGER")
    m = _manifest("dddddddd-0000-4000-8000-000000000002")
    m["authorized_elements"][f"relation-persona:{key(1)}"]["span_to"] = 26
    _skriv(tmp_path / "m-prod.json", m)
    _skriv(tmp_path / "in-prod.json", _input("dddddddd-0000-4000-8000-000000000002"))
    assert ta.main(argv) == 1
    # Et element uden inputrække kan ikke gøres logisk.
    _skriv(tmp_path / "m-prod.json", _manifest("dddddddd-0000-4000-8000-000000000002", n_extra=1))
    assert ta.main(argv) == 1 and capsys.readouterr().out.splitlines()[-1].startswith("PARTER_INPUT_MANGLER")
    _skriv(tmp_path / "m-prod.json", _manifest("dddddddd-0000-4000-8000-000000000002"))
    _skriv(tmp_path / "in-prod.json", _input("dddddddd-0000-4000-8000-000000000002", raws=("Gift m. Bo Betta",
                                                                                         "Børn: 2")))
    assert ta.main(argv) == 1


def test_parter_filtrer(tmp_path):
    _skriv(tmp_path / "m.json", _manifest("cccccccc-0000-4000-8000-000000000001", n_extra=1))
    (tmp_path / "k.txt").write_text(f"{key(2)}\n", encoding="utf-8")
    assert ta.main(["parter-filtrer", "--manifest", str(tmp_path / "m.json"), "--noegler", str(tmp_path / "k.txt"),
                    "--out", str(tmp_path / "f.json"), "--private-root", str(tmp_path)]) == 0
    f = json.loads((tmp_path / "f.json").read_text())
    assert list(f["authorized_elements"]) == [f"relation-persona:{key(2)}"]
    assert f["expected_counts"]["relation_personas"] == 1


# --- relationssvar, nøgler og stier ---------------------------------------------------------------------------------

def test_relationssvar_fra_arkene(tmp_path):
    (tmp_path / "f.txt").write_text(f"# x\nP {key(5)} 1 : B\n", encoding="utf-8")
    (tmp_path / "b.txt").write_text(f"# x\nC {key(6)} 1 : U # note\n", encoding="utf-8")
    assert ta.main(["relationssvar", "--foraelderark", str(tmp_path / "f.txt"), "--boerneark",
                    str(tmp_path / "b.txt"), "--out", str(tmp_path / "r.json"), "--private-root",
                    str(tmp_path)]) == 0
    r = json.loads((tmp_path / "r.json").read_text())
    assert r["items"] == [{"interpretation_key": key(5), "version": 1, "predicate": "relation.parent", "svar": "B"},
                          {"interpretation_key": key(6), "version": 1, "predicate": "relation.child", "svar": "U"}]
    (tmp_path / "b.txt").write_text(f"C {key(6)} 1 : _\n", encoding="utf-8")
    assert ta.main(["relationssvar", "--boerneark", str(tmp_path / "b.txt"), "--out", str(tmp_path / "r.json"),
                    "--private-root", str(tmp_path)]) == 1


def test_noegler_fra_afstemningen(tmp_path):
    a, _, _ = blandet_post()
    _skriv(tmp_path / "a.json", a)
    assert ta.main(["noegler", "--afstemning", str(tmp_path / "a.json"), "--praedikat", "relation.child",
                    "--out", str(tmp_path / "k.txt"), "--private-root", str(tmp_path)]) == 0
    assert (tmp_path / "k.txt").read_text().split() == [key(103)]


def test_stier_uden_for_private_root_afvises(tmp_path, capsys):
    a, _, _ = blandet_post()
    _skriv(tmp_path / "a.json", a)
    capsys.readouterr()
    assert ta.main(["noegler", "--afstemning", str(tmp_path / "a.json"), "--out", str(tmp_path / "k.txt"),
                    "--private-root", str(tmp_path / "andet")]) == 1
    assert capsys.readouterr().out.startswith("SHEET_PATH_NOT_PRIVATE")


# --- fixrunde 1 -----------------------------------------------------------------------------------------------------

def test_ubundet_relation_kraever_parterne():
    """En ubunden relationsnøgle (ingen binding) følger kvitterings-writerens partsben: før parterne afventer den, og
    en udskrift, der påstår genfundet med samme værdi men en anden principal-part, afvises (writeren ville afvise
    kvitteringen efter bindingerne)."""
    g = [gammel(1, art="ubundet_relation", predicate="relation.parent", persona=None, principal="I-9#p",
                kandidater=[key(101)])]
    n = [ny(101, predicate="relation.parent", persona=None, principal="I-9#p")]
    assert afstemning(g, n, fase="foer_parter")["gamle"][0]["udfald"] == "afventer"
    assert afstemning(g, n)["gamle"][0]["udfald"] == "genfundet"
    ta.laes_afstemning(afstemning(g, n))
    n_anden = [ny(101, predicate="relation.parent", persona=None, principal="I-10#p")]
    with pytest.raises(ta.AfstemningError, match="AFSTEMNING_JSON_UGYLDIG"):
        ta.laes_afstemning(afstemning(g, n_anden))
    # Den rigtige udskrift (SQL'ens kontrakt kræver samme principal) har ingen kandidat: ikke genfundet.
    g[0]["kandidater"] = []
    assert afstemning(g, n_anden)["gamle"][0]["udfald"] == "ikke_genfundet"
    # Ægteskab: samme principal, anden ægtefælle-part → afvist.
    gm = [gammel(2, art="ubundet_relation", predicate="relation.marriage", persona=None, principal="I-9#p",
                 modpart="I-9#rel-marriage-1-2", kandidater=[key(102)])]
    nm = [ny(102, predicate="relation.marriage", persona=None, principal="I-9#p", modpart="I-9#rel-marriage-5-2")]
    with pytest.raises(ta.AfstemningError, match="AFSTEMNING_JSON_UGYLDIG"):
        ta.laes_afstemning(afstemning(gm, nm))


def _match_base(idf, n_match):
    k = _klassifikation([(idf(i), "MATCH") for i in range(1, n_match + 1)])
    rows = [_row(idf(i), persona=per(i)) for i in range(1, n_match + 1)]
    idk = {**_idkort([(idf(i), key(i)) for i in range(1, n_match + 1)],
                     [(per(i), f"I-{i}#p", 10 + i) for i in range(1, n_match + 1)]),
           "afgraenset": True, "noegler_sha256": "5" * 64}
    return k, rows, idk


def _plan_strata(tmp, navn, k, rows, oevrige):
    d = tmp / navn
    d.mkdir()
    out = subprocess.run([sys.executable, CM_SCRIPT, "plan", "--classification", str(_skriv(d / "k.json", k)),
                          "--rows", str(_skriv(d / "r.json", rows)), "--source-id", str(SRC),
                          "--strata-ubekraeftet", "0", "--strata-oevrige", str(oevrige), "--out-dir", str(d / "plan")],
                         capture_output=True, text=True)
    assert out.returncode == 0, out.stdout + out.stderr
    return d / "plan"


@pytest.mark.parametrize("n_match,oevrige,kode", [(21, 20, "KORT_MATCH_OVER_GRAENSE"),
                                                   (3, 2, "KORT_STIKPROEVE_IKKE_ALLE_MATCH")])
def test_match_loft_og_maskinkandidater_stopper(tmp_path, capsys, n_match, oevrige, kode):
    k, rows, idk = _match_base(sid, n_match)
    pd = _plan_strata(tmp_path, "standin", k, rows, oevrige)
    plan, _ = v2._load_plan(pd)
    assert plan["machine_candidates"]           # plan_run_v2's udtryk for MATCH uden menneskeligt svar
    ark = _besvar(plan, {r["interpretation_id"]: "B" for r in plan["rows_kontrol"]})
    capsys.readouterr()
    _kortsvar(tmp_path, pd, ark, idk, rc=1)
    assert capsys.readouterr().out.startswith(kode)
    # oversaet på prods plan stopper på samme måde (før sammenligningen).
    kp, rowsp, idkp = _match_base(pid_, n_match)
    pp = _plan_strata(tmp_path, "prod", kp, rowsp, oevrige)
    with pytest.raises(ta.AfstemningError, match=kode):
        plan_p, meta_p = v2._load_plan(pp)
        ta.oversaet(fakta_svar(), plan_p, meta_p, idkp)


def test_svar_med_maskinkandidater_eller_over_loftet_afvises():
    g, n = fakta_post()
    a = afstemning(g, n)
    with pytest.raises(ta.AfstemningError, match="KORT_STIKPROEVE_IKKE_ALLE_MATCH"):
        ta.forventet(a, fakta_svar(maskine=[key(101)]), rel_svar())
    s = fakta_svar([(key(101), "MATCH", "B")])
    s["plan"]["match"] = [[key(900 + i), 1] for i in range(21)]
    with pytest.raises(ta.AfstemningError, match="KORT_MATCH_OVER_GRAENSE"):
        ta.forventet(a, s, rel_svar())


def test_tilbagetraek_html(tmp_path, capsys):
    a, s, r = blandet_post()
    a["gamle"][1]["record_key"] = "I-11"          # to poster: den tilbagetrukne titel ligger på I-11
    r2 = rel_svar([(key(103), "relation.child", "R")])   # barnet afvises → også på arket
    kontekst = {"contract": ta.KONTEKST_CONTRACT, "poster": [
        {"element_id": "source-text-revision:I-9", "record_key": "I-9", "side_fra": 12, "side_til": 13,
         "tekst": "Gift <med> A & \"B\"."},
        {"element_id": "source-text-revision:I-11", "record_key": "I-11", "side_fra": 40, "side_til": 40,
         "tekst": "Kammerherre <script>x</script>"}]}
    for navn, obj in (("a.json", a), ("s.json", s), ("r.json", r2), ("k.json", kontekst)):
        _skriv(tmp_path / navn, obj)
    fl = ["--afstemning", str(tmp_path / "a.json"), "--fakta-svar", str(tmp_path / "s.json"), "--relationssvar",
          str(tmp_path / "r.json"), "--private-root", str(tmp_path)]
    capsys.readouterr()
    assert ta.main(["tilbagetraek-ark", *fl, "--out", str(tmp_path / "tv.txt")]) == 0
    assert ta.main(["tilbagetraek-html", *fl, "--kontekst", str(tmp_path / "k.json"),
                    "--out", str(tmp_path / "tv.html")]) == 0
    ud = capsys.readouterr().out
    assert "Gift" not in ud and "Kammerherre" not in ud and "TILBAGETRAEK_HTML_OK linjer=2" in ud
    h = (tmp_path / "tv.html").read_text()
    sheet_refs = refs((tmp_path / "tv.txt").read_text())
    assert sheet_refs == [ref(2, "assertion", 901), ref(3, "family", 77)]   # (post, prædikat, ref)-orden
    assert re.findall(r'<section data-ref="([^"]+)">', h) == sheet_refs
    assert "&lt;med&gt; A &amp; &quot;B&quot;." in h and "<med>" not in h and "<script>" not in h
    assert "side 12–13" in h and "side 40" in h and "default-src 'none'" in h
    assert (tmp_path / "tv.html").stat().st_mode & 0o777 == 0o600
    grundlag = re.search(r"# grundlag_sha256: (\w+)", (tmp_path / "tv.txt").read_text())[1]
    assert f"grundlag_sha256: {grundlag}" in h
    # En post uden kontekst stopper.
    _skriv(tmp_path / "k.json", {**kontekst, "poster": kontekst["poster"][:1]})
    capsys.readouterr()
    assert ta.main(["tilbagetraek-html", *fl, "--kontekst", str(tmp_path / "k.json"),
                    "--out", str(tmp_path / "tv2.html")]) == 1
    assert capsys.readouterr().out.startswith("TILBAGETRAEK_KONTEKST_MANGLER")


def test_parter_logisk_hasher_aarene(tmp_path):
    m = _manifest("cccccccc-0000-4000-8000-000000000001")
    m["authorized_elements"][f"relation-persona:{key(1)}"]["birth_raw"] = "1850"
    _skriv(tmp_path / "m.json", m)
    _skriv(tmp_path / "in.json", _input("cccccccc-0000-4000-8000-000000000001"))
    assert ta.main(["parter-logisk", "--manifest", str(tmp_path / "m.json"), "--input", str(tmp_path / "in.json"),
                    "--out", str(tmp_path / "l.json"), "--private-root", str(tmp_path)]) == 0
    lg = json.loads((tmp_path / "l.json").read_text())
    assert "1850" not in json.dumps(lg) and "birth_raw" not in json.dumps(lg)
    e1 = next(e for e in lg["elementer"] if e["interpretation_key"] == key(1))
    assert re.fullmatch(r"[0-9a-f]{64}", e1["birth_sha256"]) and e1["death_sha256"] is None
