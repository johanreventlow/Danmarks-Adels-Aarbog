import pytest
from build_45_selection import (SelectionCoverageError, coverage, definition_sha256,
                                er_henvisning, features, gift_antal, select_new)


def rec(key, tekst):
    return {"record_key": key, "persona_id": f"p-{key}", "post_verbatim_text": tekst,
            "clauses": [{"ordinal": 1, "verbatim_text": tekst, "verbatim_sha256": "x"}]}


def test_features_maaler_alle_akser_og_gift_som_antal():
    f = features(rec("A", "Kammerherre, gift 1850, ægtede 1860, † ca. 1901 " + "x" * 900))
    assert f == {"laengde": "lang", "gift": "2+", "gift_mindst_et": True, "gift_flere": True,
                 "titel": True, "usikker_dato": True}


def test_features_kort_uden_signaler():
    f = features(rec("B", "Født 1800."))
    assert f == {"laengde": "kort", "gift": "0", "gift_mindst_et": False, "gift_flere": False,
                 "titel": False, "usikker_dato": False}


def test_gift_antal_taeller_hvert_udsagn():
    assert gift_antal("gift 1800; ægtede 1810; gift 1820") == 3


def test_henvisning_er_kort_og_siger_se():
    assert er_henvisning(rec("C", "Se Reventlow, Conrad."))
    assert not er_henvisning(rec("D", "Se " + "x" * 120))
    assert not er_henvisning(rec("E", "Født 1800, død 1850."))


def _pulje():
    records = {}
    for i in range(80):
        key = f"I-{i:03d}"
        gift = "gift ægtede " if i % 4 == 0 else ("gift " if i % 2 else "")
        tekst = gift + ("ca. " if i % 5 == 0 else "") \
            + ("Kammerherre " if i % 3 == 0 else "") + "x" * (50 + 30 * i)
        records[key] = rec(key, tekst)
    return records


def test_udvalget_er_deterministisk_og_uafhaengigt_af_raekkefoelge():
    records = _pulje()
    keys = sorted(records)
    a = select_new(records, keys, set(), 24, 6)
    b = select_new(dict(reversed(list(records.items()))), list(reversed(keys)), set(), 24, 6)
    assert a == b and len(a[0]) == 24 and len(a[1]) == 6
    assert not set(a[0]) & set(a[1])


def test_udvalget_springer_koerte_og_ikke_eligible_over():
    records = _pulje()
    keys = sorted(records)
    exclude, eligible = set(keys[:10]), keys[:70]
    valgt, reserve = select_new(records, eligible, exclude, 24, 6)
    assert not (set(valgt) | set(reserve)) & exclude
    assert set(valgt) | set(reserve) <= set(eligible)


def test_udvalget_spreder_over_laengde_og_gift_antal():
    records = _pulje()
    valgt, _ = select_new(records, sorted(records), set(), 24)
    strata = {(features(records[k])["laengde"], features(records[k])["gift"]) for k in valgt}
    assert len(strata) >= 6


def test_manglende_daekning_stopper():
    records = {f"K-{i}": rec(f"K-{i}", "x" * 300) for i in range(40)}
    with pytest.raises(SelectionCoverageError) as exc:
        select_new(records, sorted(records), set(), 24)
    assert "gift_mindst_et=0" in str(exc.value)


def test_for_lille_pulje_stopper():
    records = _pulje()
    with pytest.raises(SelectionCoverageError, match="valgt=10"):
        select_new(records, sorted(records)[:10], set(), 24)


def test_definitionshash_binder_graenser(monkeypatch):
    import build_45_selection as b
    foer = definition_sha256()
    monkeypatch.setattr(b, "LAENGDE_GRAENSER", (150, 800))
    assert definition_sha256() != foer
