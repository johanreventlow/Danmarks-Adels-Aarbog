import pytest

from build_1939_v2 import (
    assert_known_regression_lock,
    attach_record_keys,
    build_linked_v2,
    choose_narrative,
    deterministic_name,
    filter_duplicate_summaries,
    mint_new_records,
)
from identitetsregister import Lokator, Post, Register


def post(lokal_id, raw_text="Clare1ia omtales i denne entydige kildetekst med ekstra ankerord", **extra):
    return {
        "side": "500",
        "sider": "500",
        "lokal_id": lokal_id,
        "raw_text": raw_text,
        **extra,
    }


def test_filter_duplicate_summaries_removes_only_explicit_markers():
    records = [
        post("I.1"),
        post("Oversigt.U1", dublet_af_stamtavle=True),
        post("I.2", dublet_af_stamtavle=False),
    ]

    usable, removed = filter_duplicate_summaries(records)

    assert [record["lokal_id"] for record in usable] == ["I.1", "I.2"]
    assert [record["lokal_id"] for record in removed] == ["Oversigt.U1"]


def test_choose_narrative_uses_direct_unique_l_one_match():
    calamari = {
        "10": {"narrative": "Clarelia omtales i denne entydige kildetekst med ekstra ankerord"},
        "11": {"narrative": "En helt anden post"},
    }

    narrative, source, match_id = choose_narrative(post("I.1"), calamari)

    assert narrative == calamari["10"]["narrative"]
    assert source == "calamari"
    assert match_id == "10"


def test_choose_narrative_falls_back_to_raw_on_ambiguous_match():
    raw = "Clare1ia omtales i denne entydige kildetekst med ekstra ankerord"
    calamari = {
        "10": {"narrative": "Clarelia omtales i denne entydige kildetekst med ekstra ankerord"},
        "11": {"narrative": "Clarelia omtales i denne entydige kildetekst med ekstra ankerord igen"},
    }

    narrative, source, match_id = choose_narrative(post("I.1", raw), calamari)

    assert narrative == raw
    assert source == "raw"
    assert match_id is None


def test_mint_new_records_mints_only_reconcile_new_set():
    reg = Register({
        "1939|500|I.1": Post("known-id", Lokator("1939", "500", "I.1")),
    })
    records = [post("I.1"), post("I.2"), post("I.3")]

    updated, minted = mint_new_records(reg, records, "1939", expected_new=2)

    assert minted == 2
    assert updated.poster["1939|500|I.1"].book_post_id == "known-id"
    assert len({p.book_post_id for p in updated.poster.values()}) == 3


def test_mint_new_records_fails_closed_on_unexpected_count():
    with pytest.raises(ValueError, match="forventede 55 nye, fandt 1"):
        mint_new_records(Register(), [post("I.1")], "1939", expected_new=55)


def test_attach_record_keys_requires_complete_unique_reconciliation():
    reg = Register({
        "1939|500|I.1": Post("id-1", Lokator("1939", "500", "I.1")),
        "1939|500|I.2": Post("id-2", Lokator("1939", "500", "I.2")),
    })
    records = [post("I.1"), post("I.2")]

    attached = attach_record_keys(reg, records, "1939")

    assert [record["record_key"] for record in attached] == ["id-1", "id-2"]
    assert records[0].get("record_key") is None


def test_attach_record_keys_rejects_incomplete_coverage():
    with pytest.raises(ValueError, match="record_key-dækning fejler"):
        attach_record_keys(Register(), [post("I.1")], "1939")


def test_deterministic_name_strips_number_spacing_title_and_tenure():
    assert deterministic_name({
        "raw_text": "3. Hr. C l a r e l i a Testsen til Testholm, nævnes 1700."
    }) == "Clarelia Testsen"


def test_deterministic_name_fails_closed_without_a_bounded_source_label():
    with pytest.raises(ValueError, match="navn kunne ikke udledes"):
        deterministic_name({"raw_text": "† 1700."})


def test_build_linked_v2_keeps_known_baseline_and_appends_new_after_old_ids():
    old = [
        {"_id": 1, "record_key": "id-1", "navn": "Kendt", "fjernet": False},
        {"_id": 2, "record_key": "gone", "navn": "Bortfalden", "fjernet": False},
    ]
    records = [
        {**post("I.1"), "record_key": "id-1"},
        {**post("I.2", raw_text="2. Ny Testperson til Testholm, nævnes 1700."),
         "record_key": "id-2", "linje": "I", "slaegtled": "II"},
    ]
    narratives = {
        "id-1": {"narrative": "kendt narrativ", "source": "raw"},
        "id-2": {"narrative": "nyt narrativ", "source": "raw"},
    }

    linked, narrative_map, stats = build_linked_v2(old, records, narratives)

    assert linked[0]["_id"] == 1 and linked[0]["fjernet"] is False
    # The old row remains an ordering/link scaffold during conversion and is
    # filtered from final output by record_key afterwards.
    assert linked[1]["_id"] == 2 and linked[1]["fjernet"] is False
    assert linked[2]["_id"] == 3 and linked[2]["record_key"] == "id-2"
    assert linked[2]["_fakta_status"] == "efterudtraek"
    assert linked[2]["_ctx"] == {
        "linje": None, "slaegtled": None, "gruppe": None, "foraeldre_note": None,
    }
    assert narrative_map["3"]["narrative"] == "nyt narrativ"
    assert stats == {"genbrugt": 0, "nyudtraek": 0, "efterudtraek": 2}


def test_regression_lock_allows_only_narrative_side_and_v2_metadata_changes():
    old = [{"record_key": "id-1", "navn": "Kendt", "facts": [{"faktatype": "titel"}],
            "narrative": "gammel", "sider": "500"}]
    new = [{**old[0], "narrative": "forbedret", "sider": "1",
            "_fakta_status": "efterudtraek", "_narrativ_kilde": "calamari"}]
    assert_known_regression_lock(old, new, {"id-1"})
    new[0]["facts"] = []
    with pytest.raises(ValueError, match="regressionslås fejler"):
        assert_known_regression_lock(old, new, {"id-1"})
