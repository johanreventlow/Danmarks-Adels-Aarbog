"""Trin 5b 2b-ii (spec §5.2, errata §15.1): andet udtræksgennemløb for de parkerede ægteskaber."""
import relation_persona_extract_v2 as v2


def row(text, raw, partners=(), principal=1, sup=1, ordinal=1, key="k1"):
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": "relation.marriage", "raw": raw,
            "record_key": "II-1", "marriage_ordinal": ordinal, "supporting_count": sup, "principal_ok": principal is not None,
            "principal_person_id": principal, "principal_partners": list(partners),
            "clauses": [{"observation_id": "o1", "clause_set_seq": 1, "clause_set_sha256": "a" * 64,
                         "verbatim_text": text, "post_char_from": 100, "post_char_to": 100 + len(text)}]}


def test_window_matches_sql_fixture():
    # Review Focus 1: samme tekster og tal som tests/sql/test-relation-persona-v2.sql
    assert v2.windows("Gift 1. gang 1890 med Bo Beta, f. 1801.", "gift med Bo Beta") == [(0, 29)]
    assert v2.windows("g. 2° m. Søren Ærø-Ødegård, f. 1850.", "m. søren ødegård") == [(6, 26)]
    assert len(v2.windows("Gift med Åse Ø. Gift med Åse Ø.", "gift med åse ø")) == 2
    assert v2.windows("Gift med Bo.", "gift med Cia") == []
    assert v2.windows("Gift 1975.", "Gift 1975.") == [(0, 9)]


def test_D_ved_gamle_aar():
    t = "Gift 1. gang 1890 med Bo Beta, f. 1801."
    p = v2.propose(row(t, "Gift med Bo Beta"), 1906)
    assert p["tok"] == "D" and p["clause_years"] == [1801, 1890]
    assert t[p["name_from"]:p["name_to"]] == "Bo Beta" and (p["span_from"], p["span_to"]) == (0, 29)


def test_N_ved_nyt_aar_og_ved_intet_aar():
    assert v2.propose(row("Gift 1950 med Bo Beta.", "Gift med Bo Beta"), 1906)["tok"] == "N"
    assert v2.propose(row("Gift med Bo Beta.", "Gift med Bo Beta"), 1906)["tok"] == "N"


def test_S_ved_partnermatch():
    p = v2.propose(row("Gift 1890 med Bo Beta.", "Gift med Bo Beta",
                       partners=[{"person_id": 7, "family_id": 3, "ordinal": 1, "navn": "Bo Carl Beta"}]), 1906)
    assert p["tok"] == "S" and p["partner_person_id"] == 7


def test_S_kraever_entydig_partner():
    partners = [{"person_id": 7, "navn": "Bo Beta"}, {"person_id": 8, "navn": "Bo Beta"}]
    assert v2.propose(row("Gift 1890 med Bo Beta.", "Gift med Bo Beta", partners=partners), 1906)["tok"] == "D"


def test_navn_uden_med():
    t = "Gift 1925 Anna Xi."
    p = v2.propose(row(t, "Gift 1925 Anna Xi"), 1906)
    assert t[p["name_from"]:p["name_to"]] == "Anna Xi" and p["tok"] == "N"


def test_I_U_graenser():
    assert v2.propose(row("Gift 1975.", "Gift 1975."), 1906)["tok"] == "I"
    assert v2.propose(row("Gift med Åse Ø. Gift med Åse Ø.", "gift med åse ø"), 1906)["tok"] == "U"   # tvetydigt
    assert v2.propose(row("Gift med Bo Beta.", "Gift med Bo Beta", principal=None), 1906)["tok"] == "U"
    assert v2.propose(row("Gift med Bo Beta.", "Gift med Bo Beta", sup=2), 1906)["tok"] == "U"
    assert v2.propose(row("Gift med Bo Beta.", "Gift med Cia"), 1906)["tok"] == "U"                      # intet vindue


def test_U_uden_aegteskabsnummer():
    # write_relation_persona kræver marriage_ordinal for ægteskaber (del 1: intet_nummer)
    assert v2.propose(row("Gift 1890 med Bo Beta.", "Gift med Bo Beta", ordinal=None), 1906)["tok"] == "U"


def test_sent_foedselsaar_giver_N():
    # Hvert årstal kan være et fødselsår (errata §15.5): »f. 1918« alene giver ikke D.
    assert v2.propose(row("Gift med Bo Beta, f. 1918.", "Gift med Bo Beta"), 1906)["tok"] == "N"
    assert v2.propose(row("Gift 1905 med Bo Beta, f. 1880.", "Gift med Bo Beta"), 1906)["tok"] == "D"


def _navn(t, raw):
    p = v2.propose(row(t, raw), 1906)
    return p["tok"], (t[p["name_from"]:p["name_to"]] if "name_from" in p else None)


def test_navn_efter_lange_titler_og_stop_ved_smaat_ord():
    # Plan-ruling Task 8: navnet er løbet af ord med versal (+ partikler); titler foran springes over.
    t = "Gift 2° 15. jan. 1890 med kammerherre, hofjægermester, r. af Dbg. Bo Carl Beta komtesse til Holm."
    assert _navn(t, "Gift 2° 15. jan. 1890 med Bo Carl Beta")[1] == "Bo Carl Beta"
    t = "Gift 12. sept. 1890 på Gods i Sogn med Anna von Berg Holm datter af godsejer Hans Holm."
    assert _navn(t, "Gift 12. sept. 1890 på Gods i Sogn med Anna von Berg Holm")[1] == "Anna von Berg Holm"


def test_datter_af_i_titelloebet_giver_U():
    tok, navn = _navn("Gift 1890 med en datter af Peter Hansen.", "Gift 1890 med datter af Peter Hansen")
    assert tok == "U" and navn is None


def test_I_kun_uden_versal_efter_gift():
    assert _navn("Gift 1975.", "Gift 1975.")[0] == "I"
    assert _navn("Gift 1890 med kammerherre m.fl.", "Gift 1890 med kammerherre")[0] == "I"
