"""Trin 5b 2b-ii runde 2 (spec §17.4-17.5): navneregel v3. Kun opdigtede navne."""
import re
from pathlib import Path

import pytest

import relation_persona_extract_v3 as v3


def row(text, raw, partners=(), principal=1, ordinal=1, key="k1"):
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": "relation.marriage", "raw": raw,
            "record_key": "II-1", "marriage_ordinal": ordinal, "supporting_count": 1, "principal_ok": principal is not None,
            "principal_person_id": principal, "principal_partners": list(partners), "post_text": "Anna A. " + text,
            "clauses": [{"observation_id": "o1", "clause_set_seq": 1, "clause_set_sha256": "a" * 64,
                         "verbatim_text": text, "post_char_from": 8, "post_char_to": 8 + len(text)}]}


def partner(pid, navn, ordinal=1, fam=3):
    return {"person_id": pid, "family_id": fam, "ordinal": ordinal, "navn": navn}


def name_of(text, p):
    return text[p["name_from"]:p["name_to"]]


def test_titel_inde_i_navnet_kommer_med():
    t = "Gift 1890 med Ida komtesse Dal, f. 1801."
    p = v3.propose(row(t, "Gift med Ida komtesse Dal", [partner(7, "Ida Dal")]), 1906)
    assert p["tok"] == "S" and p["partner_person_id"] == 7 and name_of(t, p) == "Ida komtesse Dal"


def test_rigs_og_lens_praefiks():
    assert v3.is_title("rigsgrevinde") and v3.is_title("Lensgreve") and v3.is_title("komtesse")
    assert not v3.is_title("rigs") and not v3.is_title("grevskab") and not v3.is_title("Dal")


def test_partikelkaede_von_und_zu():
    t = "Gift 1890 med Eva von und zu Fik."
    p = v3.propose(row(t, "Gift med Eva von und zu Fik"), 1906)
    assert name_of(t, p) == "Eva von und zu Fik" and p["tok"] == "D" and p["clause_years"] == [1890]


def test_genannt_og_dem():
    t = "Gift 1890 med Ulf genannt von dem Hagen."
    p = v3.propose(row(t, "Gift med Ulf genannt von dem Hagen"), 1906)
    assert name_of(t, p) == "Ulf genannt von dem Hagen"


def test_efternavn_skal_passe():
    # samme fornavn, andet efternavn ⇒ intet træf (v2 gav S på fornavnet alene)
    assert not v3.partner_hit("Eva von Fik", "Eva von Gro")
    assert v3.partner_hit("Eva komtesse von Fik", "Eva Fik")


def test_partner_med_aarstal_i_navnet():
    assert v3.partner_hit("Ida Dal", "Ida Dal (1850)")


def test_to_traef_afgoeres_af_nummer():
    t = "Gift 2. gang 1890 med Eva von Fik."
    rows = [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Maria Fik", ordinal=2, fam=4)]
    p = v3.propose(row(t, "Gift med Eva von Fik", rows, ordinal=2), 1906)
    assert p["tok"] == "S" and p["partner_person_id"] == 8 and p["reason"] == "partnermatch_nummer"


def test_to_traef_uden_afgoerelse_giver_U():
    t = "Gift 1890 med Eva Fik."
    rows = [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Fik", ordinal=1, fam=4)]
    assert v3.propose(row(t, "Gift med Eva Fik", rows, ordinal=2), 1906)["tok"] == "U"


def test_skaevt_nummer_ved_eet_traef_er_stadig_S():
    t = "Gift 1890 med Ida Dal."
    p = v3.propose(row(t, "Gift med Ida Dal", [partner(7, "Ida Dal", ordinal=2)], ordinal=1), 1906)
    assert p["tok"] == "S" and p["partner_ordinal"] == 2


def test_D_og_N_kraever_nul_traef():
    # Linje 5's fælde: to træf og intet afgørende nummer må aldrig blive D
    t = "Gift 1890 med Eva Fik."
    rows = [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Fik", ordinal=3, fam=4)]
    assert v3.propose(row(t, "Gift med Eva Fik", rows, ordinal=2), 1906)["tok"] == "U"


def test_kapitaliseret_titel_foer_navnet_giver_ikke_D():
    t = "Gift 1890 med Komtesse Ida Dal."
    p = v3.propose(row(t, "Gift med Komtesse Ida Dal"), 1906)
    assert p["tok"] == "U" and p["reason"] == "titel_i_navn"


def test_ukendt_titel_giver_U():
    # spec §17.9: »markise« er ikke på listen, så reglen stopper før den (afkortet til »Ida«). Et afkortet navn
    # må aldrig blive D; forslaget er U, og navnet står på arket, så mennesket kan rette med navn:.
    t = "Gift 1890 med Ida markise Dal."
    p = v3.propose(row(t, "Gift med Ida markise Dal"), 1906)
    assert p["tok"] == "U" and p["reason"] == "navn_afkortet" and name_of(t, p) == "Ida"


def test_til_gods_er_ikke_afkortning():
    # »til <gods>« er ikke en del af navnet (beslutning 2026-10-03) og udløser ikke navn_afkortet
    t = "Gift 1890 med Ida Dal til Ørum."
    p = v3.propose(row(t, "Gift med Ida Dal til Ørum"), 1906)
    assert p["tok"] == "D" and name_of(t, p) == "Ida Dal"


def test_navnerettelse_forlaenger_slutningen():
    # reglen stopper før det ulistede »markise« (U); rettelsen forlænger navnet, og så findes partneren
    t = "Gift 1890 med Ida markise Dal, f. 1801."
    r = row(t, "Gift med Ida markise Dal", [partner(7, "Ida Dal")])
    assert v3.propose(r, 1906)["tok"] == "U"
    p = v3.propose(r, 1906, name_override="Ida markise Dal")
    assert p["tok"] == "S" and p["name_basis"] == "sheet" and name_of(t, p) == "Ida markise Dal"


def test_komma_efter_efternavnet_bag_en_titel():
    # vinduet rækker ud over navnet, så kommaet ligger inde i segmentet (Fable-review af planen, fund 1)
    t = "Gift 1890 med Ida komtesse Dal, datter af Ole Hak."
    p = v3.propose(row(t, "Gift med Ida komtesse Dal, datter af Ole Hak", [partner(7, "Ida Dal")]), 1906)
    assert p["tok"] == "S" and name_of(t, p) == "Ida komtesse Dal"


def test_flere_partnere_og_titel_viser_stadig_navnet():
    # arket skal vise regelens navn netop dér, hvor mennesket skal rette med navn:
    t = "Gift 1890 med Eva Fik."
    rows = [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Fik", ordinal=1, fam=4)]
    p = v3.propose(row(t, "Gift med Eva Fik", rows, ordinal=2), 1906)
    assert p["reason"] == "flere_partnere" and name_of(t, p) == "Eva Fik"
    t2 = "Gift 1890 med Komtesse Ida Dal."
    p2 = v3.propose(row(t2, "Gift med Komtesse Ida Dal"), 1906)
    assert p2["reason"] == "titel_i_navn" and name_of(t2, p2) == "Komtesse Ida Dal"


def test_navnerettelse_skal_slutte_ved_helt_ord():
    t = "Gift 1890 med Ida Dal, f. 1801."
    for bad in ("Ida Da", "Ida Dal,"):
        with pytest.raises(v3.NameOverrideError):
            v3.propose(row(t, "Gift med Ida Dal"), 1906, name_override=bad)


def test_navnerettelse_uden_navnestart_afvises():
    # tidlige U (her: intet nummer) må ikke sluge en navn:-rettelse tavst (spec §17.6)
    t = "Gift 1890 med Ida Dal."
    with pytest.raises(v3.NameOverrideError):
        v3.propose(row(t, "Gift med Ida Dal", ordinal=None), 1906, name_override="Ida Dal")


def test_bindestregstitel_fanges_som_i_sql():
    # SQL-tvillingen deler på alle ikke-bogstaver; Python skal fange det samme allerede på arket
    assert not v3.title_free("Ida Rigs-Grevinde Dal")


def test_navnerettelse_skal_starte_ved_navnestarten():
    t = "Gift 1890 med Ida Dal, datter af Ole Dal."
    with pytest.raises(v3.NameOverrideError):
        v3.propose(row(t, "Gift med Ida Dal, datter af Ole Dal", [partner(7, "Ole Dal")]), 1906, name_override="Ole Dal")
    with pytest.raises(v3.NameOverrideError):
        v3.propose(row(t, "Gift med Ida Dal, datter af Ole Dal"), 1906, name_override="Ida Dalx")


def test_regelnavn_har_basis_rule():
    t = "Gift 1890 med Ida Dal."
    assert v3.propose(row(t, "Gift med Ida Dal"), 1906)["name_basis"] == "rule"


def prow(**kw):
    base = {"source_persona_id": "00000000-0000-0000-0000-000000000001", "identity_version": 1,
            "previous": {"basis": "web_detail", "note": "kø", "decided_at": "2026-10-13"},
            "name_text": "Gro von Hak", "clause_text": "Gift 1314 med Gro von Hak.", "clause_is_current": True,
            "post_text": "Carl C. Gift 1314 med Gro von Hak.", "marriage_ordinal": 1, "principal_person_id": 5,
            "principal_partners": []}
    return {**base, **kw}


def test_P_D_ved_gammelt_aar():
    p = v3.propose_redecide(prow(), 1906)
    assert p == {"tok": "D", "reason": "aldersregel", "clause_years": [1314]}


def test_P_partner_findes_giver_U():
    assert v3.propose_redecide(prow(principal_partners=[partner(9, "Gro Hak")]), 1906)["tok"] == "U"


def test_P_titel_og_afloest_klausul_og_nyt_aar():
    assert v3.propose_redecide(prow(name_text="Gro komtesse Hak"), 1906)["tok"] == "U"
    assert v3.propose_redecide(prow(clause_is_current=False), 1906)["tok"] == "U"
    assert v3.propose_redecide(prow(clause_text="Gift 1950 med Gro von Hak."), 1906)["tok"] == "N"
    assert v3.propose_redecide(prow(marriage_ordinal=None), 1906)["tok"] == "U"


def test_title_words_match_schema():
    # Tvillingtest (spec §17.5): listen i Python = array-literalen i private.relation_title_words() i schema.sql
    schema = (Path(__file__).resolve().parents[4] / "schema.sql").read_text(encoding="utf-8")
    m = re.search(r"FUNCTION private\.relation_title_words\(\).*?ARRAY\[(.*?)\]", schema, re.S)
    assert m, "private.relation_title_words() mangler i schema.sql"
    assert tuple(re.findall(r"'([a-zæøå]+)'", m.group(1))) == v3.TITLE_WORDS
    m2 = re.search(r"FUNCTION private\.relation_name_has_title\(.*?\^\((\w+)\|(\w+)\)", schema, re.S)
    assert m2 and (m2.group(1), m2.group(2)) == v3.TITLE_PREFIXES
