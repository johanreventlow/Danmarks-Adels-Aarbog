from identitetsregister import Register, mint
from types import SimpleNamespace

from afstem_v2 import Afstemningsresultat, _rapport, afstem_identiteter, anvend_forslag


def gammel(record_key, lokal_id, *, side="500", navn="Clarelia",
           narrative="1. C l a r e l i a var nævnt i det gamle dokument som sikkert tekstanker",
           orig_nr="1"):
    return {
        "record_key": record_key,
        "_lokal_id": lokal_id,
        "sider": side,
        "navn": navn,
        "narrative": narrative,
        "_orig_nr": orig_nr,
    }


def ny(lokal_id, *, side="500", navn="Clare1ia", nr_label="1",
       postklasse="stamfader", dublet=False):
    return {
        "lokal_id": lokal_id,
        "side": side,
        "sider": side,
        "nr_label": nr_label,
        "raw_text": f"{navn} var nævnt i det gamle dokument som sikkert tekstanker og senere igen",
        "postklasse": postklasse,
        "dublet_af_stamtavle": dublet,
    }


def register_for(gamle):
    reg = Register()
    for i, g in enumerate(gamle):
        reg = mint(reg, [{"side": g["sider"], "lokal_id": g["_lokal_id"]}], "1939")
        post = reg.poster[f"1939|{g['sider']}|{g['_lokal_id']}"]
        old_id = post.book_post_id
        post.book_post_id = g["record_key"]
        assert old_id != post.book_post_id
    return reg


def test_legacy_bro_kraever_side_navn_og_tekstanker_og_taaler_l_mod_1():
    gamle = [gammel("rk1", "Legacy.1")]
    resultat = afstem_identiteter(
        register_for(gamle), gamle, [ny("Ny.I.U1")], "1939",
        legacy_lokal_ids={"Legacy.1"},
    )
    assert len(resultat.auto_forslag) == 1
    forslag = resultat.auto_forslag[0]
    assert forslag["book_post_id"] == "rk1"
    assert forslag["broklasse"] == "legacy_48"
    assert forslag["ny_lokator"]["lokal_id"] == "Ny.I.U1"
    assert forslag["evidens"] == {
        "side": True, "navn": True, "tekstanker": True, "nummer": True,
    }
    assert not resultat.menneskeark


def test_legacy_bro_gaar_paa_menneskeark_ved_navn_mismatch():
    gamle = [gammel("rk1", "Legacy.1", navn="EtAndetNavn")]
    resultat = afstem_identiteter(
        register_for(gamle), gamle, [ny("Ny.I.U1")], "1939",
        legacy_lokal_ids={"Legacy.1"},
    )
    assert not resultat.auto_forslag
    assert resultat.menneskeark[0]["grund"] == "ingen_entydig_tre_signalsbro"
    assert resultat.menneskeark[0]["broklasse"] == "legacy_48"


def test_nummereret_bro_afviser_nummeruenighed_selv_med_tekstanker():
    gamle = [gammel("rk1", "Kort.II.2", orig_nr="2")]
    resultat = afstem_identiteter(
        register_for(gamle), gamle,
        [ny("Langt-raatekst-afsnit.4", nr_label="4", postklasse=None)],
        "1939", legacy_lokal_ids=set(),
    )
    assert not resultat.auto_forslag
    assert resultat.menneskeark[0]["grund"] == "ingen_entydig_nummer_ankerbro"


def test_to_gamle_der_vinder_samme_nye_demoteres_begge():
    gamle = [gammel("rk1", "Legacy.1"), gammel("rk2", "Legacy.2")]
    resultat = afstem_identiteter(
        register_for(gamle), gamle, [ny("Ny.I.U1")], "1939",
        legacy_lokal_ids={"Legacy.1", "Legacy.2"},
    )
    assert not resultat.auto_forslag
    assert {r["book_post_id"] for r in resultat.menneskeark} == {"rk1", "rk2"}
    assert {r["grund"] for r in resultat.menneskeark} == {"ikke_injektiv_bro"}


def test_dubletmarkeret_oversigt_er_altid_menneskeafgoerelse():
    gamle = [gammel("rk1", "Legacy.1")]
    resultat = afstem_identiteter(
        register_for(gamle), gamle,
        [ny("Oversigt.Indledning.U1", postklasse="oversigtspost", dublet=True)],
        "1939", legacy_lokal_ids={"Legacy.1"},
    )
    assert not resultat.auto_forslag
    assert resultat.menneskeark[0]["grund"] == "dublet_af_stamtavle_kraever_menneske"


def test_anvend_forslag_flytter_kun_kopi_og_bevarer_id():
    gamle = [gammel("rk1", "Legacy.1")]
    reg = register_for(gamle)
    resultat = afstem_identiteter(
        reg, gamle, [ny("Ny.I.U1")], "1939",
        legacy_lokal_ids={"Legacy.1"},
    )
    simuleret = anvend_forslag(reg, resultat.auto_forslag)
    assert "1939|500|Legacy.1" in reg.poster
    assert "1939|500|Ny.I.U1" in simuleret.poster
    assert simuleret.poster["1939|500|Ny.I.U1"].book_post_id == "rk1"


def test_rapport_opremser_hvert_dubletmaal_praecis_en_gang():
    række = {
        "book_post_id": "rk1", "gammel_lokator": None,
        "kandidat_lokatorer": [{"udgave": "1939", "side": "500",
                                "lokal_id": "Oversigt.Indledning.U1"}],
        "postklasse": "oversigtspost", "dublet_af_stamtavle": True,
        "broklasse": "legacy_48",
        "grund": "dublet_af_stamtavle_kraever_menneske",
    }
    resultat = Afstemningsresultat(menneskeark=[række, {**række, "book_post_id": "rk2"}])
    tom = SimpleNamespace(entydige=[], tvetydige=[], nye=[], bortfaldne=[])
    rapport = _rapport(resultat, tom, tom, 2)
    assert rapport.count("`Oversigt.Indledning.U1` — afventer") == 1
