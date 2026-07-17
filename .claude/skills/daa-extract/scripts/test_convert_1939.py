# test_convert_1939.py — unit-tests for convert_1939_stamtavle.py (A3a).
# KUN SYNTETISKE poster — ingen data fra linked_clean.json (PII-disciplin).
import pytest

from convert_1939_stamtavle import (
    convert_all,
    convert_record,
    build_date_fact,
    convert_aegteskab,
    convert_godser,
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
