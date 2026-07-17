# test_convert_1939.py — unit-tests for convert_1939_stamtavle.py (A3a+A3c).
# KUN SYNTETISKE poster — ingen data fra linked_clean.json (PII-disciplin).
import pytest

from convert_1939_stamtavle import (
    convert_all,
    convert_record,
    build_date_fact,
    convert_aegteskab,
    convert_godser,
    parse_slaegtled,
    name_tokens,
    names_match,
    extract_parent_tokens,
    extract_spouse_tokens,
    group_key,
    build_units,
)


def synth(_id, **over):
    """Minimal syntetisk linked_clean-post."""
    rec = {
        "_id": _id,
        "_window": "w00",
        "_ctx": {"linje": None, "slaegtled": "II", "gruppe": "g1", "foraeldre_note": None},
        "lokal_id": f"9.{_id}",
        "nr": None,
        "navn": "Testperson Alfa",
        "koen": "mand",
    }
    rec.update(over)
    return rec


# ---------- nøglerum ----------

def test_noeglerum_globalt_unikke_nr_sorteret_paa_id():
    recs = [synth(30), synth(10), synth(20)]
    out = convert_all(recs)
    assert [r["nr"] for r in out] == [1, 2, 3]          # 1..N, deterministisk
    assert [r["_id"] for r in out] == [10, 20, 30]      # sorteret på _id
    assert all(r["linje"] == "1939" for r in out)
    assert len({(r["linje"], r["nr_label"]) for r in out}) == 3  # nøgle-unikhed


def test_nr_label_er_str_af_globalt_nr_og_original_bevares():
    # Originale løbenumre er GRUPPE-lokale (duplikeres på tværs af 539 poster)
    # og pmap/resolve_barn_keys kræver nr_label == str(nr) for at A3c's
    # boern.nr_range kan opløses — originalen bevares derfor i _orig_nr.
    recs = [synth(1, nr="A)"), synth(2, nr=15), synth(3, nr=None)]
    out = convert_all(recs)
    assert [r["nr_label"] for r in out] == ["1", "2", "3"]
    assert isinstance(out[0]["nr_label"], str)
    assert [r["_orig_nr"] for r in out] == ["A)", 15, None]
    assert [r["_lokal_id"] for r in out] == ["9.1", "9.2", "9.3"]


# ---------- facts ----------

def test_dato_fakta_rutes_gennem_derive_date_info():
    rec = synth(1,
                foedsel={"date_raw": "26. sept. 1687", "sted": "Testholm"},
                doed={"date_raw": "ca. 1700", "sted": None},
                begravelse={"date_raw": None, "sted": "Testkirke"})
    out = convert_record(rec, 1)
    facts = {f["faktatype"]: f for f in out["facts"]}
    f = facts["fødsel"]
    assert (f["date_min"], f["date_max"]) == ("1687-09-26", "1687-09-26")
    assert f["date_raw"] == "26. sept. 1687"
    assert f["kilde_span"] == "26. sept. 1687"
    assert f["sted"] == "Testholm"
    d = facts["død"]
    assert (d["date_min"], d["date_max"]) == ("1700-01-01", "1700-12-31")
    assert d["date_qualifier"] == "about"
    b = facts["begravelse"]                      # sted uden dato -> stadig fakta
    assert b["date_raw"] is None and b["date_min"] is None
    assert b["sted"] == "Testkirke"


def test_tom_datoblok_giver_ingen_fakta():
    assert build_date_fact("fødsel", None) is None
    assert build_date_fact("fødsel", {"date_raw": None, "sted": None}) is None
    assert build_date_fact("fødsel", {"date_raw": "", "sted": "  "}) is None


def test_dato_usikker_overlay_saetter_uncertain():
    f = build_date_fact("død", {"date_raw": "1700", "sted": None, "dato_usikker": True})
    assert f["date_certainty"] == "uncertain"
    f2 = build_date_fact("død", {"date_raw": "1700", "sted": None})
    assert f2["date_certainty"] is None


def test_titel_bliver_vaerdifakta_og_erhverv_springes_over():
    rec = synth(1, titel="Testtitel", erhverv=["noget", "andet"])
    out = convert_record(rec, 1)
    typer = [f["faktatype"] for f in out["facts"]]
    assert "titel" in typer
    assert not any(t in ("erhverv", "uddannelse") for t in typer)
    t = next(f for f in out["facts"] if f["faktatype"] == "titel")
    assert t["vaerdi"] == "Testtitel"


# ---------- godser ----------

def test_godser_strenge_til_navn_objekter():
    assert convert_godser(["Gods Alfa", "Gods Beta"]) == [
        {"navn": "Gods Alfa"}, {"navn": "Gods Beta"}]
    assert convert_godser(None) == []
    assert convert_godser(["", "  ", "Gods Alfa"]) == [{"navn": "Gods Alfa"}]


# ---------- ægteskaber ----------

def test_aegteskab_mapping():
    a = {"ordinal": 2, "partner_navn": "Partner Beta", "partner_foraeldre": "F.: X og Y",
         "dato_raw": "26. sept. 1687", "sted": "Teststed", "skilt": True,
         "partner_note": "en note"}
    m = convert_aegteskab(a)
    assert m["ordinal"] == 2
    assert m["partner_navn"] == "Partner Beta"
    assert (m["date_min"], m["date_max"]) == ("1687-09-26", "1687-09-26")
    assert m["dato_raw"] == "26. sept. 1687"
    assert m["kilde_span"] == "26. sept. 1687"
    assert m["sted"] == "Teststed"
    assert m["skilt"] is True
    assert m["partner_foraeldre"] == "F.: X og Y"
    assert m["note"] == "en note"


def test_aegteskaber_ordinal_stigende_og_uden_dato():
    rec = synth(1, aegteskaber=[
        {"ordinal": 2, "partner_navn": "B", "dato_raw": None, "sted": None,
         "skilt": False, "partner_note": None, "partner_foraeldre": None},
        {"ordinal": 1, "partner_navn": "A", "dato_raw": None, "sted": None,
         "skilt": False, "partner_note": None, "partner_foraeldre": None},
    ])
    out = convert_record(rec, 1)
    assert [a["ordinal"] for a in out["aegteskaber"]] == [1, 2]
    assert out["aegteskaber"][0]["date_min"] is None


# ---------- narrative / boern / diverse ----------

def test_narrative_er_none_og_boern_udeladt():
    out = convert_record(synth(1), 1)
    assert out["narrative"] is None
    assert "boern" not in out


def test_usikker_afledes_af_navn_usikker_eller_ufuldstaendig():
    assert convert_record(synth(1, navn_usikker=True), 1)["usikker"] is True
    assert convert_record(synth(1, ufuldstaendig=True), 1)["usikker"] is True
    assert convert_record(synth(1), 1)["usikker"] is False


def test_koen_og_tilnavn_bevares():
    out = convert_record(synth(1, koen="kvinde", tilnavn="kaldet Test"), 1)
    assert out["koen"] == "kvinde"
    assert out["tilnavn"] == "kaldet Test"
    assert "tilnavn" not in convert_record(synth(2), 2)


def test_noter_og_kryds_ref_samles_i_note():
    rec = synth(1, noter=["note et", "note to"], note="enkelt note",
                kryds_ref=[{"type": "se", "ref": "andetsteds"}])
    out = convert_record(rec, 1)
    for stump in ("note et", "note to", "enkelt note", "andetsteds"):
        assert stump in out["note"]
    assert convert_record(synth(2), 2)["note"] is None


# =====================================================================
#  A3c — forældre-barn-links via gruppe-hierarkiet
# =====================================================================

def gsynth(_id, gruppe="gA", note=None, slaegtled="II", window="w00",
           navn="Alfa Beta", **over):
    """Syntetisk post med kontrollérbar gruppe-kontekst."""
    rec = {
        "_id": _id,
        "_window": window,
        "_ctx": {"linje": None, "slaegtled": slaegtled, "gruppe": gruppe,
                 "foraeldre_note": note},
        "lokal_id": f"9.{_id}",
        "nr": None,
        "navn": navn,
        "koen": "mand",
    }
    rec.update(over)
    return rec


# ---------- parse_slaegtled ----------

@pytest.mark.parametrize("s,forventet", [
    ("II", 2), ("VII", 7), ("IV.", 4), ("I. (usikker — lavtstillet)", 1),
    ("1", 1), ("Første Slægtled", 1), ("Andet Slægtled", 2),
    ("Anden Slægtled (udledt af nummer-sekvens)", 2),
    ("Tredje Slægtled (udledt af forward-refs til 'Fjerde Slægtled')", 3),
    ("Syvende Slægtled (udledt af fremadref 'Ottende Slægtled II./III.')", 7),
    ("Ellevte Slægtled", 11),
    ("VI (udledt - header uden for vindue)", 6),
    ("udledt: ukendt (prosaform)", None),
    ("ukendt (uden for vindue)", None),
    (None, None), ("", None),
])
def test_parse_slaegtled(s, forventet):
    assert parse_slaegtled(s) == forventet


# ---------- navne-tokens + match ----------

def test_name_tokens_dropper_titler_og_slaegtsnavn():
    assert name_tokens("Anders Bertram Greve Reventlows") == ["anders", "bertram"]
    assert name_tokens("Kammerherre Carl Greve Reventlow") == ["carl"]
    # spouse-tokenizer beholder slægtsnavn
    assert name_tokens("Berta Reventlow", drop_slaegt=False) == ["berta", "reventlow"]


def test_names_match_eksakt_genitiv_og_subsekvens():
    assert names_match(["anders", "bertram"], ["anders", "bertram"])
    assert names_match(["anders"], ["anders", "bertram"])        # subsekvens
    assert names_match(["bertrams"], ["bertram"])                # genitiv-s
    assert not names_match(["anders"], ["bertram"])
    assert not names_match([], ["anders"])
    assert not names_match(["anders", "carl"], ["carl", "anders"])  # rækkefølge


# ---------- note-ekstraktion ----------

def test_extract_parent_tokens_fra_typisk_note():
    assert extract_parent_tokens("Anders Greve Testholms Børn med Berta von Gamma") == ["anders", "testholms"]
    assert extract_parent_tokens("Kammerherre Carl Greve Testholm og Hustru — Børn:") == ["carl", "testholm"]
    # uparsebar/ukendt kontekst -> None (fail-closed)
    assert extract_parent_tokens("ukendt (uden for vindue)") is None
    assert extract_parent_tokens("gruppe-header ligger uden for vinduet") is None
    assert extract_parent_tokens(None) is None


def test_extract_spouse_tokens():
    sp = extract_spouse_tokens("Anders' Børn m. Berta von Gamma (nr. 1-2) og af 2. Ægteskab m. Cecilie Delta")
    assert ["berta", "gamma"] in sp or ["berta", "von", "gamma"] in sp
    assert any("cecilie" in seg for seg in sp)
    assert extract_spouse_tokens("Anders' Sønner var") == []


# ---------- gruppe-nøgle + blok-nummerering ----------

def test_group_key_vindue_lokal_og_singleton():
    a = gsynth(1, gruppe="gA", window="w00")
    b = gsynth(2, gruppe="gA", window="w01")          # samme bogstav, andet vindue
    c = gsynth(3, gruppe=None, note=None)
    assert group_key(a) != group_key(b)
    assert group_key(c) is None                        # singleton


def test_gruppe_blok_nummerering_kontinuert_pr_gruppe():
    # interleavede _id'er på tværs af to grupper -> hver gruppe én konsekutiv blok
    recs = [gsynth(1, gruppe="gA"), gsynth(2, gruppe="gB"),
            gsynth(3, gruppe="gA"), gsynth(4, gruppe="gB")]
    out = convert_all(recs)
    nr_af = {p["_id"]: p["nr"] for p in out}
    assert nr_af[1] == 1 and nr_af[3] == 2             # gA-blok (min-_id først)
    assert nr_af[2] == 3 and nr_af[4] == 4             # gB-blok
    assert sorted(p["nr"] for p in out) == [1, 2, 3, 4]
    assert all(p["nr_label"] == str(p["nr"]) for p in out)


def test_build_units_dokumentorden_og_intern_id_sort():
    recs = [gsynth(5, gruppe="gB"), gsynth(2, gruppe="gA"),
            gsynth(9, gruppe="gA"), gsynth(7, gruppe=None, note=None)]
    units = build_units(recs)
    assert [[r["_id"] for r in u] for u in units] == [[2, 9], [5], [7]]


# ---------- opløsning: Tier 1 (_foraelder_id) ----------

def far(_id=100, navn="Anders Testholm", slaegtled="I", **over):
    return gsynth(_id, gruppe="gFar", note=None, slaegtled=slaegtled, navn=navn, **over)


def test_tier1_foraelder_id_saetter_nr_range():
    recs = [far(100),
            gsynth(101, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(102, gruppe="gA", slaegtled="II", _foraelder_id=100)]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    posts = {p["_id"]: p for p in out}
    forael = posts[100]
    lo, hi = forael["boern"]["nr_range"]
    boern_nr = sorted(posts[i]["nr"] for i in (101, 102))
    assert [lo, hi] == [boern_nr[0], boern_nr[-1]]
    assert hi - lo + 1 == 2                            # kontinuert blok, ingen fremmede
    assert posts[101]["_link_foraelder_nr"] == forael["nr"]
    assert rapport["tier1_grupper"] == 1
    assert rapport["modsigelser"] == 0


def test_tier1_konflikt_flere_fid_uoploest():
    recs = [far(100), far(200, navn="Carl Testholm"),
            gsynth(101, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(102, gruppe="gA", slaegtled="II", _foraelder_id=200)]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    assert all("boern" not in p for p in out)
    assert rapport["tier1_konflikt_grupper"] == 1


# ---------- opløsning: Tier 2 (strukturel navnematch, fail-closed) ----------

def test_tier2_entydigt_navnematch_linker():
    recs = [far(100, navn="Anders Testholm"),
            gsynth(101, gruppe="gA", slaegtled="II",
                   note="Anders Testholms Børn m. Berta von Gamma"),
            gsynth(102, gruppe="gA", slaegtled="II",
                   note="Anders Testholms Børn m. Berta von Gamma")]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    posts = {p["_id"]: p for p in out}
    assert posts[100]["boern"]["nr_range"] == [posts[101]["nr"], posts[102]["nr"]]
    assert rapport["tier2_grupper"] == 1
    assert rapport["uoploeste_grupper"] == 0


def test_tier2_tvetydigt_navnematch_fail_closed():
    recs = [far(100, navn="Anders Testholm"), far(200, navn="Anders Testholm"),
            gsynth(101, gruppe="gA", slaegtled="II",
                   note="Anders Testholms Børn m. Berta von Gamma")]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    assert all("boern" not in p for p in out)          # GÆT ALDRIG
    assert rapport["uoploeste_grupper"] == 1
    assert rapport["tvetydige_grupper"] == 1


def test_tier2_intet_match_fail_closed():
    recs = [far(100, navn="Carl Testholm"),
            gsynth(101, gruppe="gA", slaegtled="II",
                   note="Anders Testholms Børn m. Berta von Gamma")]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    assert all("boern" not in p for p in out)
    assert rapport["uoploeste_grupper"] == 1


def test_tier2_kun_forrige_slaegtled():
    # navnematch i SAMME slægtled tæller ikke som kandidat
    recs = [far(100, navn="Anders Testholm", slaegtled="II"),
            gsynth(101, gruppe="gA", slaegtled="II",
                   note="Anders Testholms Børn m. Berta")]
    out = convert_all(recs)
    assert all("boern" not in p for p in out)


def test_tier2_aegtefaelle_disambiguerer():
    recs = [far(100, navn="Anders Testholm",
                aegteskaber=[{"ordinal": 1, "partner_navn": "Berta von Gamma",
                              "dato_raw": None, "sted": None, "skilt": False,
                              "partner_note": None, "partner_foraeldre": None}]),
            far(200, navn="Anders Testholm",
                aegteskaber=[{"ordinal": 1, "partner_navn": "Cecilie Delta",
                              "dato_raw": None, "sted": None, "skilt": False,
                              "partner_note": None, "partner_foraeldre": None}]),
            gsynth(101, gruppe="gA", slaegtled="II",
                   note="Anders Testholms Børn m. Berta von Gamma")]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    posts = {p["_id"]: p for p in out}
    assert posts[100]["boern"]["nr_range"] == [posts[101]["nr"], posts[101]["nr"]]
    assert "boern" not in posts[200]


def test_tier2_aegtefaelle_eliminerer_alle_fail_closed():
    # to navne-kandidater, ingen med matchende ægtefælle -> uopløst (ingen link)
    recs = [far(100, navn="Anders Testholm"), far(200, navn="Anders Testholm"),
            gsynth(101, gruppe="gA", slaegtled="II",
                   note="Anders Testholms Børn m. Berta von Gamma")]
    out = convert_all(recs)
    assert all("boern" not in p for p in out)


def test_ukendt_slaegtled_fail_closed():
    recs = [far(100, navn="Anders Testholm", slaegtled="I"),
            gsynth(101, gruppe="gA", slaegtled="udledt: ukendt (prosaform)",
                   note="Anders Testholms Børn m. Berta")]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    assert all("boern" not in p for p in out)
    assert rapport["uoploeste_grupper"] == 1


# ---------- Tier1/Tier2-enighed (modsigelses-vagt) ----------

def test_tier1_tier2_modsigelse_fail_closed_og_taelles():
    # fid peger på post 100, men navnematch peger entydigt på post 200
    recs = [far(100, navn="Anders Testholm"), far(200, navn="Carl Testholm"),
            gsynth(101, gruppe="gA", slaegtled="II", _foraelder_id=100,
                   note="Carl Testholms Børn m. Berta")]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    assert all("boern" not in p for p in out)          # modsigelse -> link ikke
    assert rapport["modsigelser"] == 1


def test_tier1_tier2_enighed_taelles():
    recs = [far(100, navn="Anders Testholm"),
            gsynth(101, gruppe="gA", slaegtled="II", _foraelder_id=100,
                   note="Anders Testholms Børn m. Berta")]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    posts = {p["_id"]: p for p in out}
    assert "boern" in posts[100]
    assert rapport["modsigelser"] == 0
    assert rapport["tier1_tier2_enige"] == 1


# ---------- flere grupper pr. forælder ----------

def test_multi_gruppe_tilstoedende_merges():
    recs = [far(100),
            gsynth(101, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(102, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(103, gruppe="gB", slaegtled="II", _foraelder_id=100)]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    posts = {p["_id"]: p for p in out}
    lo, hi = posts[100]["boern"]["nr_range"]
    assert hi - lo + 1 == 3                            # samlet spænd over begge blokke
    assert rapport["multi_gruppe_foraeldre"] == 1
    assert rapport["multi_gruppe_ikke_tilstoedende"] == 0


def test_multi_gruppe_ikke_tilstoedende_stoerste_blok_og_log():
    # fremmed gruppe gX ligger mellem forælderens to grupper -> ikke-tilstødende
    recs = [far(100),
            gsynth(101, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(102, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(103, gruppe="gX", slaegtled="II"),
            gsynth(104, gruppe="gB", slaegtled="II", _foraelder_id=100)]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    posts = {p["_id"]: p for p in out}
    lo, hi = posts[100]["boern"]["nr_range"]
    assert [lo, hi] == [posts[101]["nr"], posts[102]["nr"]]   # største blok (gA)
    assert posts[104].get("_link_foraelder_nr") is None       # gB IKKE linket
    assert rapport["multi_gruppe_ikke_tilstoedende"] == 1
    assert rapport["boern_udeladt_ikke_tilstoedende"] == 1


# ---------- nr_range-integritet ----------

def test_facit_strukturelle_links_og_integritet():
    from facit_1939 import facit
    recs = [far(100),
            gsynth(101, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(102, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(103, gruppe="gB", slaegtled="II")]
    out = convert_all(recs)
    r = facit(out)
    assert r["boern_strukturelt_linket"] == 2
    assert r["foraeldre_med_nr_range"] == 1
    assert r["nr_range_falske_boern"] == 0
    assert r["nr_range_ugyldige"] == 0
    assert r["grupper_ikke_kontinuert_nr"] == 0
    assert r["roedder_uden_foraelder_link"] == 2      # forælderen selv + gB-posten

    # manipuleret output: range der dækker et ikke-barn SKAL fanges
    kaput = [dict(p) for p in out]
    for p in kaput:
        if "boern" in p:
            lo, hi = p["boern"]["nr_range"]
            p["boern"] = {"nr_range": [lo, hi + 1]}   # +1 rummer gB-posten
    assert facit(kaput)["nr_range_falske_boern"] >= 1


def test_intet_range_indeholder_ikke_barn():
    recs = [far(100),
            gsynth(101, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(102, gruppe="gA", slaegtled="II", _foraelder_id=100),
            gsynth(103, gruppe="gB", slaegtled="II")]
    rapport = {}
    out = convert_all(recs, rapport=rapport)
    assert rapport["falske_boern_i_range"] == 0
    nr2post = {p["nr"]: p for p in out}
    for p in out:
        if "boern" in p:
            lo, hi = p["boern"]["nr_range"]
            for n in range(lo, hi + 1):
                assert nr2post[n].get("_link_foraelder_nr") == p["nr"]
