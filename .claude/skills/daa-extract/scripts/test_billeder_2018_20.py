"""Tests for udtræk af portrætter og billedtekster fra DAA 2018-20 (særudgaven).

Billedteksterne er kopieret fra `pdftotext -layout` af den publicerede særudgave (må læses, jf. CLAUDE.md).
"""
import hashlib

from PIL import Image

from billeder_2018_20 import lav_varianter, parse_billedtekst, vaelg_billedtekst

S300 = """                                                Hofjægermester
                 Christian Benedictus Johan Ludvig Conrad Ferdinand greve af Reventlow
                            til Agerup, Varste og Polle og fideikomisgodset Koppel
                                                   1845-1922
                                                    (V, 106)
                                          Malet af Knud Erik Larsen
           300
6116990-DAA 2018-20_saerudgave.indd 300                                                  25/10/2023 14.07
"""

S185 = """                                Emilia Louisa Henrietta lensgrevinde de Reventlou
                                             født komtesse af Bernstorff
                                                     1766-1855
                                Gift med Cay Friedrich lensgreve de Reventlou (IV, 2)
                                                                                        185
6116990-DAA 2018-20_saerudgave.indd 185                                                  25/10/2023 14.05
"""

S279 = """                                      Hildeborg Sophie grevinde af Reventlow
                                             født komtesse af Reventlow
                                                     1804-1868
                                                       (V, 70)
                                Gift med Einert Carl Detlef greve af Reventlow (V, 56)
                                               Malet 1867 af H. Olrik
                                                                                         279
6116990-DAA 2018-20_saerudgave.indd 279                                                  25/10/2023 14.06
"""

S340 = """                                          Ellen Marie grevinde af Reventlow
                                                        født Iuel
                                                     til Hverringe
                                                       født 1929
                      Gift med Claus Detlev Frederik Ferdinand greve af Reventlow (V, 164)
                                             Malet 1983 af Gertrud Boberg
           340
6116990-DAA 2018-20_saerudgave.indd 340                                                      25/10/2023 14.08
"""

S365 = """                                                   Fra venstre:
                                                  Vicepresident
                                    Alexander Rudolph Iuel greve af Reventlow
                                                  til Hverringe
                                                    født 1987
                                                      (V, 192)
                                                     Konsulent
                                          Charlotte Benedicte Iuel Arnstedt
                                             født komtesse af Reventlow
                                                     født 1991
                                                      (V, 194)
                                                         Ph.d.
                                          Ditlev Otto Iuel greve af Reventlow
                                                       født 1988
                                                        (V, 193)
                                   Foto: Martin Mydtskov Rønne, Huset Mydtskov
                                                                                 365
6116990-DAA 2018-20_saerudgave.indd 365                                           25/10/2023 14.08
"""

S323 = """                                          Kreditforeningsdirektør
                       Eduard Vilhelm Christian Ferdinand Ludvig greve af Reventlow
                                                 1855-1928
                                                  (V, 111)
                                                 og hans nevøer
                             Eduard August greve af Reventlow, 1886-1918, (V, 147)
                               Overordentlig gesandt og befuldmægtiget minister
                    Eduard Vilhelm Sofus Kristian lensgreve af Reventlow, 1883-1963, (V, 144)
                                                                                                323
6116990-DAA 2018-20_saerudgave.indd 323                                                          25/10/2023 14.07
"""


def lille_jpeg(mappe, bredde, hoejde):
    sti = mappe / f"kilde-{bredde}x{hoejde}.jpg"
    Image.new("RGB", (bredde, hoejde), (120, 80, 40)).save(sti, "JPEG", quality=90)
    return sti


def jpeg_med_nulmaske(mappe):
    """Et sort billede med en helt gennemsigtig maske (0 = gennemsigtig i en PDF-smask)."""
    kilde = mappe / "maskeret.jpg"
    Image.new("RGB", (40, 30), (0, 0, 0)).save(kilde, "JPEG", quality=90)
    maske = mappe / "maske.png"
    Image.new("L", (40, 30), 0).save(maske)
    return kilde, maske


def test_egen_med_maler():
    r = parse_billedtekst(S300)
    assert r["klasse"] == "egen" and r["refs"] == [["V", 106]]
    assert r["kunstner"] == "Knud Erik Larsen" and r["slags"] == "maleri"
    assert r["datering"] is None


def test_titel_er_billedteksten_uden_kunstner_sidetal_og_sidefod():
    titel = parse_billedtekst(S300)["titel"]
    assert titel.startswith("Hofjægermester Christian Benedictus")
    assert titel.endswith("1845-1922 (V, 106)")
    assert "Malet" not in titel and "indd" not in titel and "300" not in titel.split()


def test_aegtefaelle_uden_egen_ref():
    r = parse_billedtekst(S185)
    assert r["klasse"] == "aegtefaelle" and r["refs"] == [] and r["aegtefaelle_anker"] == ["IV", 2]
    assert r["aegtefaelle_aar"] == [1766, 1855]
    assert r["aegtefaelle_navn"].startswith("Emilia Louisa Henrietta")


def test_egen_ref_foer_gift_med_vinder():
    r = parse_billedtekst(S279)
    assert r["klasse"] == "egen" and r["refs"] == [["V", 70]]
    assert r["aegtefaelle_anker"] is None


def test_malet_aar_bliver_datering():
    r = parse_billedtekst(S340)
    assert r["datering"] == "1983" and r["kunstner"] == "Gertrud Boberg"
    assert r["klasse"] == "aegtefaelle" and r["aegtefaelle_aar"] == [1929, None]


def test_fra_venstre_er_gruppe():
    r = parse_billedtekst(S365)
    assert r["klasse"] == "gruppe" and r["refs"] == [["V", 192], ["V", 194], ["V", 193]]
    assert r["slags"] == "foto" and r["kunstner"] == "Martin Mydtskov Rønne, Huset Mydtskov"


def test_flere_refs_uden_fra_venstre_er_flere():
    r = parse_billedtekst(S323)
    assert r["klasse"] == "flere" and r["refs"] == [["V", 111], ["V", 147], ["V", 144]]
    assert r["slags"] == "portræt"


def test_tom_tekst_er_uafklaret():
    r = parse_billedtekst("272")
    assert r["klasse"] == "uafklaret" and r["refs"] == [] and r["titel"] == ""


def test_varianter_opskalerer_aldrig(tmp_path):
    v = lav_varianter(lille_jpeg(tmp_path, 499, 754), None, tmp_path, "k")
    assert v["dims"]["thumb"] == [499, 754] and v["dims"]["medium"] == [499, 754]
    assert v["dims"]["large"] == [499, 754]


def test_varianter_skalerer_bredt_billede(tmp_path):
    v = lav_varianter(lille_jpeg(tmp_path, 1500, 1000), None, tmp_path, "k")
    assert v["dims"]["thumb"][0] == 500 and v["dims"]["medium"][0] == 1100 and v["dims"]["large"][0] == 1500
    assert v["filer"] == {"large": "k-large.jpg", "medium": "k-medium.jpg", "thumb": "k-thumb.jpg"}


def test_large_uden_maske_er_originalens_bytes(tmp_path):
    kilde = lille_jpeg(tmp_path, 600, 800)
    v = lav_varianter(kilde, None, tmp_path, "k")
    assert (tmp_path / v["filer"]["large"]).read_bytes() == kilde.read_bytes()


def test_smask_flades_paa_hvid(tmp_path):
    kilde, maske = jpeg_med_nulmaske(tmp_path)
    v = lav_varianter(kilde, maske, tmp_path, "k")
    r, g, b = Image.open(tmp_path / v["filer"]["large"]).convert("RGB").getpixel((0, 0))
    assert min(r, g, b) >= 250


def test_sha_og_bytes_er_large_filens(tmp_path):
    v = lav_varianter(lille_jpeg(tmp_path, 600, 800), None, tmp_path, "k")
    data = (tmp_path / v["filer"]["large"]).read_bytes()
    assert v["sha256"] == hashlib.sha256(data).hexdigest()
    assert v["bytes"]["large"] == len(data)


def test_tom_billedside_laaner_naeste_sides_tekst():
    # Opslag (s. 272-273): billedet står på venstre side, billedteksten på højre, som ikke selv har et billede.
    naeste = "Fra venstre\nChristian Detlef greve af Reventlow, 1775-1851 (V, 47)\n273\n"
    assert vaelg_billedtekst("272\n", naeste, naeste_har_billede=False) == naeste
    assert vaelg_billedtekst("272\n", naeste, naeste_har_billede=True) == "272\n"
    assert vaelg_billedtekst(S300, naeste, naeste_har_billede=False) == S300
    assert vaelg_billedtekst("272\n", None, naeste_har_billede=False) == "272\n"
