# test_afstem_lokator.py — side-afstemning er et opslag, ikke et skøn.
#
# afstem() flytter kun en registerpost når artefaktet bærer postens eget
# record_key (= book_post_id). Uden facit røres intet; kollision stopper alt.
from identitetsregister import Register, mint, reconcile
from afstem_lokator import afstem


def _reg(*poster):
    return mint(Register(), [{"side": s, "lokal_id": l} for s, l in poster], "1939")


def _bid(reg, side, lokal_id):
    return reg.poster[f"1939|{side}|{lokal_id}"].book_post_id


def test_afstemning_flytter_side_og_bevarer_id():
    reg = _reg(("490", "A.1"), ("500", "B.1"))
    bid = _bid(reg, "490", "A.1")
    aendringer = afstem(reg, [{"record_key": bid, "side": "496", "lokal_id": "A.1"}], "1939")
    assert aendringer == [(bid, "490", "496")]
    assert reg.poster["1939|496|A.1"].book_post_id == bid
    assert "1939|490|A.1" not in reg.poster
    # gammel side står i begrundelsen — observation, ikke overskrivning
    assert "490" in reg.poster["1939|496|A.1"].begrundelse


def test_uden_record_key_roeres_intet():
    reg = _reg(("490", "A.1"))
    assert afstem(reg, [{"side": "496", "lokal_id": "A.1"}], "1939") == []
    assert "1939|490|A.1" in reg.poster


def test_ukendt_record_key_roeres_intet():
    reg = _reg(("490", "A.1"))
    assert afstem(reg, [{"record_key": "findes-ikke", "side": "496"}], "1939") == []


def test_kollision_med_uflyttet_post_afvises():
    # A vil flytte til B's nøgle mens B bliver stående → stop, ingen tavs fusion
    reg = _reg(("10", "1"), ("11", "1"))
    bid_a = _bid(reg, "10", "1")
    try:
        afstem(reg, [{"record_key": bid_a, "side": "11"}], "1939")
    except ValueError as e:
        assert "kollidere" in str(e)
    else:
        raise AssertionError("kollision skulle være afvist")


def test_internt_sidebytte_lykkes():
    # A og B bytter sider — to-faset flytning gør at de ikke kolliderer med
    # hinandens GAMLE nøgler undervejs
    reg = _reg(("10", "1"), ("11", "1"))
    bid_a, bid_b = _bid(reg, "10", "1"), _bid(reg, "11", "1")
    aendringer = afstem(reg, [
        {"record_key": bid_a, "side": "11"},
        {"record_key": bid_b, "side": "10"},
    ], "1939")
    assert len(aendringer) == 2
    assert reg.poster["1939|11|1"].book_post_id == bid_a
    assert reg.poster["1939|10|1"].book_post_id == bid_b


def test_efter_afstemning_er_reconcile_ren():
    reg = _reg(("490", "A.1"), ("500", "B.1"))
    bid = _bid(reg, "490", "A.1")
    afstem(reg, [{"record_key": bid, "side": "496", "lokal_id": "A.1"}], "1939")
    res = reconcile(reg, [{"side": "496", "lokal_id": "A.1"},
                          {"side": "500", "lokal_id": "B.1"}], "1939")
    assert len(res.entydige) == 2 and not res.tvetydige and not res.bortfaldne
