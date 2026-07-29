# test_omnoegl_lokator.py — broen fra LLM-lokatorer til bogens trykte adresse.
#
# Kernereglerne: tekst-anker (aldrig ordinaler), injektivitet (én ny post kan
# kun vindes af én gammel), trykt nummer som voldgift, fail-closed alt andet.
from identitetsregister import Register, mint
from omnoegl_lokator import match_poster, omnoegl


def gammel(rk, narrativ, orig_nr=None, lokal_id="gml"):
    return {"record_key": rk, "narrative": narrativ, "_orig_nr": orig_nr,
            "_lokal_id": lokal_id}


def ny(lokal_id, tekst, nr_label="1", side="500"):
    return {"lokal_id": lokal_id, "raw_text": tekst, "nr_label": nr_label,
            "sider": side}


TEKST_A = "H a r t v i g til Gallentin var 1257 Ridder da han i Lübeck optraadte som Vidne for Greverne"
TEKST_B = "M a r g r e t h e gift før 1378 med Matthias Ziesendorf og nævnt i skiftet efter sin Fader dengang"


def test_entydigt_tekstmatch():
    res = match_poster([gammel("rk1", "1. " + TEKST_A, orig_nr=1)],
                       [ny("I.Femte.1", TEKST_A), ny("I.Femte.2", TEKST_B)])
    assert len(res["match"]) == 1 and res["match"][0][1]["lokal_id"] == "I.Femte.1"


def test_nummer_praefiks_i_gammel_narrativ_strippes():
    # "3. Hr. Eler…"-mønstret: det trykte nummer står i den gamle narrativ
    res = match_poster([gammel("rk1", "3.  " + TEKST_A, orig_nr=3)],
                       [ny("I.Femte.3", TEKST_A, nr_label="3")])
    assert len(res["match"]) == 1


def test_delt_gruppenarrativ_afgoeres_af_trykt_nummer():
    # 18%-problemet: gammel narrativ = hele gruppeblokken → matcher begge nye.
    # Bogens trykte nummer afgør; uden det havde vi tvetydighed.
    blok = TEKST_A + " " + TEKST_B
    res = match_poster([gammel("rk1", blok, orig_nr=2)],
                       [ny("I.Femte.1", TEKST_A, nr_label="1"),
                        ny("I.Femte.2", TEKST_B, nr_label="2")])
    assert len(res["match"]) == 1 and res["match"][0][1]["lokal_id"] == "I.Femte.2"


def test_injektivitet_to_gamle_om_samme_nye_demoteres():
    # To gamle vinder samme nye post og ingen har det rigtige trykte nummer →
    # BEGGE til tvetydig. En tavs vinder ville være et gæt.
    # rk2 = afhugget kopi af samme tekst (starter 10 tegn inde) — begge
    # vinder ny post 1, ingen bærer dens trykte nummer
    res = match_poster([gammel("rk1", TEKST_A, orig_nr=7),
                        gammel("rk2", TEKST_A[10:], orig_nr=9)],
                       [ny("I.Femte.1", TEKST_A, nr_label="1")])
    assert not res["match"] and len(res["tvetydige"]) == 2


def test_umatchet_gammel_beholder_sin_lokator():
    res = match_poster([gammel("rk1", "helt anden tekst om en stamfader fra tolvhundredetallet uden lige", orig_nr=None)],
                       [ny("I.Femte.1", TEKST_A)])
    assert len(res["umatchede"]) == 1


def test_omnoegl_flytter_adresse_og_bevarer_id():
    reg = mint(Register(), [{"side": "490", "lokal_id": "A.V.1"}], "1939")
    bid = reg.poster["1939|490|A.V.1"].book_post_id
    aendringer = omnoegl(reg, [(
        {"record_key": bid},
        ny("IV.Ottende.II.6", TEKST_A, side="612"),
    )], "1939")
    assert len(aendringer) == 1
    p = reg.poster["1939|612|IV.Ottende.II.6"]
    assert p.book_post_id == bid
    assert "A.V.1" in p.begrundelse          # gammel adresse = versioneret observation
    assert "1939|490|A.V.1" not in reg.poster
