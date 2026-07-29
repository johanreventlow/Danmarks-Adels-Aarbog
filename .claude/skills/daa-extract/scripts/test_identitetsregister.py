# test_identitetsregister.py — unit-tests for identitetsregister.py.
# KUN SYNTETISKE poster — ingen data fra artefakterne (PII-disciplin).
import json

from identitetsregister import (
    Register,
    Lokator,
    mint,
    reconcile,
)


def post(side, lokal_id, **kw):
    return {"side": side, "lokal_id": lokal_id, **kw}


# --- Mintning: ét id pr. bogpost, aldrig genbrugt ---

def test_mint_giver_hver_post_et_id():
    reg = mint(Register(), [post("504", "A.V.1"), post("504", "A.V.2")], udgave="1939")
    assert len(reg.poster) == 2
    assert len({p.book_post_id for p in reg.poster.values()}) == 2


def test_mint_er_idempotent():
    poster = [post("504", "A.V.1"), post("505", "B.I.3")]
    reg = mint(Register(), poster, udgave="1939")
    foer = {k: v.book_post_id for k, v in reg.poster.items()}
    reg = mint(reg, poster, udgave="1939")
    assert {k: v.book_post_id for k, v in reg.poster.items()} == foer
    assert len(reg.poster) == 2


def test_mint_afviser_dublet_lokator():
    # (side, lokal_id) SKAL være entydig — ellers kan to bogposter ikke skelnes.
    try:
        mint(Register(), [post("504", "A.V.1"), post("504", "A.V.1")], udgave="1939")
    except ValueError as e:
        assert "lokator" in str(e).lower()
    else:
        raise AssertionError("dublet-lokator skulle være afvist")


def test_id_genbruges_aldrig_efter_tombstone():
    reg = mint(Register(), [post("504", "A.V.1")], udgave="1939")
    gammelt = next(iter(reg.poster.values())).book_post_id
    reg.tombstone(Lokator("1939", "504", "A.V.1"), "dublet")
    reg = mint(reg, [post("504", "A.V.9")], udgave="1939")
    nye = [p.book_post_id for p in reg.poster.values() if p.status == "aktiv"]
    assert gammelt not in nye


# --- Reconciliation: genfind samme fysiske bogpost i et NYT udtræk ---

def test_uaendret_lokator_genbruger_id():
    reg = mint(Register(), [post("504", "A.V.1")], udgave="1939")
    forventet = next(iter(reg.poster.values())).book_post_id
    res = reconcile(reg, [post("504", "A.V.1")], udgave="1939")
    assert res.entydige[0][1] == forventet
    assert not res.tvetydige and not res.nye and not res.bortfaldne


def test_ny_post_faar_nyt_id():
    reg = mint(Register(), [post("504", "A.V.1")], udgave="1939")
    res = reconcile(reg, [post("504", "A.V.1"), post("506", "C.II.7")], udgave="1939")
    assert [p["lokal_id"] for p in res.nye] == ["C.II.7"]


def test_bortfalden_post_meldes_ikke_slettes():
    reg = mint(Register(), [post("504", "A.V.1"), post("505", "B.I.3")], udgave="1939")
    res = reconcile(reg, [post("504", "A.V.1")], udgave="1939")
    assert [l.lokal_id for l in res.bortfaldne] == ["B.I.3"]
    # registeret må ALDRIG selv rydde op — bortfald er en beslutning, ikke en automatik
    assert all(p.status == "aktiv" for p in reg.poster.values())


def test_tombstone_matcher_ikke():
    reg = mint(Register(), [post("504", "A.V.1")], udgave="1939")
    reg.tombstone(Lokator("1939", "504", "A.V.1"), "dublet")
    res = reconcile(reg, [post("504", "A.V.1")], udgave="1939")
    assert res.entydige == [] and len(res.nye) == 1


def test_flyttet_side_er_TVETYDIG_ikke_gaet():
    # Samme lokal_id, ny side: kunne være samme post flyttet — eller en anden post.
    # Registeret gætter ALDRIG; det stopper fail-closed.
    reg = mint(Register(), [post("504", "A.V.1")], udgave="1939")
    res = reconcile(reg, [post("507", "A.V.1")], udgave="1939")
    assert res.tvetydige, "flyttet side skal give tvetydighed, ikke et gæt"
    assert not res.entydige


def test_udgaver_er_adskilte():
    reg = mint(Register(), [post("504", "A.V.1")], udgave="1939")
    res = reconcile(reg, [post("504", "A.V.1")], udgave="2018-20")
    assert res.entydige == [] and len(res.nye) == 1


# --- Persistens ---

def test_roundtrip_bevarer_alt():
    reg = mint(Register(), [post("504", "A.V.1"), post("505", "B.I.3")], udgave="1939")
    reg.tombstone(Lokator("1939", "505", "B.I.3"), "dublet — omtale")
    genlaest = Register.from_json(json.loads(reg.to_json()))
    assert genlaest.to_json() == reg.to_json()
    tomb = [p for p in genlaest.poster.values() if p.status == "tombstone"]
    assert len(tomb) == 1 and tomb[0].begrundelse.startswith("dublet")


def test_json_er_deterministisk_sorteret():
    a = mint(Register(), [post("505", "B.I.3"), post("504", "A.V.1")], udgave="1939")
    b = mint(Register(), [post("504", "A.V.1"), post("505", "B.I.3")], udgave="1939")
    # Samme poster i forskellig rækkefølge → samme RÆKKEFØLGE i filen (så
    # git-diffs er læsbare). ID'erne er tilfældige og skal IKKE sammenlignes.
    def lokatorer(reg):
        return [(r["side"], r["lokal_id"]) for r in json.loads(reg.to_json())["poster"]]
    assert lokatorer(a) == lokatorer(b) == [("504", "A.V.1"), ("505", "B.I.3")]


def test_reconcile_afviser_dublet_lokator():
    """Uden denne vagt ville to poster med samme lokator BEGGE få samme id
    tildelt — tavst. Kontrollen fandtes kun i mint() (Codex-review 2026-07-29)."""
    reg = mint(Register(), [post("504", "A.V.1")], udgave="1939")
    try:
        reconcile(reg, [post("504", "A.V.1"), post("504", "A.V.1")], udgave="1939")
    except ValueError as e:
        assert "lokator" in str(e).lower()
    else:
        raise AssertionError("dublet-lokator i udtrækket skulle være afvist")
