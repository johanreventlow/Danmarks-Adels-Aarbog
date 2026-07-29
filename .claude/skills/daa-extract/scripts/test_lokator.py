# test_lokator.py — lokatoren påhæftes DETERMINISTISK, ikke af modellen.
#
# Baggrund: tørløbet 2026-07-29 viste at et kontrakt-konformt udtræk hverken har
# `side` eller `lokal_id`. reconcile() matchede derfor 0 af 30 poster og meldte
# hele registeret bortfaldet. På en rigtig re-ekstraktion ville det have mintet
# 515 nye identiteter og efterladt 613 samme_som-match forældreløse.
#
# Rettelsen følger samme mønster som narrative, boern og record_key: pipelinen
# ved hvor prosaen kom fra — modellen skal ikke spørges om identitet.
import validate


def test_lokator_paahaeftes_fra_kilde_posten():
    rec = {"linje": "1939", "nr_label": "42", "navn": "Ditlev"}
    src = {"sider": "508", "lokal_id": "A.V.1", "raw_text": "…"}
    ud = validate.paahaeft_lokator(rec, src)
    assert ud["side"] == "508"
    assert ud["lokal_id"] == "A.V.1"


def test_modellens_egne_vaerdier_overskrives():
    # Identitet udledes ikke af modellen — også hvis den finder på at gætte.
    rec = {"side": "999", "lokal_id": "GÆT"}
    src = {"sider": "508", "lokal_id": "A.V.1"}
    ud = validate.paahaeft_lokator(rec, src)
    assert (ud["side"], ud["lokal_id"]) == ("508", "A.V.1")


def test_sider_kan_vaere_liste():
    # segment.py skriver undertiden et interval; første side er postens anker.
    ud = validate.paahaeft_lokator({}, {"sider": ["508", "509"]})
    assert ud["side"] == "508"


def test_manglende_kilde_efterlader_felterne_tomme():
    # Fail-open ville give en post uden lokator, som reconcile ikke kan matche.
    # Vi sætter None frem for at opfinde noget — gaten fanger det.
    ud = validate.paahaeft_lokator({"navn": "X"}, None)
    assert ud["side"] is None and ud["lokal_id"] is None


def test_tom_streng_bliver_none():
    ud = validate.paahaeft_lokator({}, {"sider": "", "lokal_id": "  "})
    assert ud["side"] is None and ud["lokal_id"] is None


def test_lokator_mangler_er_en_R_fejl():
    # Uden lokator kan posten ikke genfindes ved en senere re-ekstraktion.
    # Det SKAL fanges af valideringen, ikke opdages bagefter.
    issues = validate.tjek_lokator({"linje": "1939", "nr_label": "42"})
    assert any("lokator" in i.lower() for i in issues)


def test_komplet_lokator_giver_ingen_fejl():
    assert validate.tjek_lokator(
        {"linje": "1939", "nr_label": "42", "side": "508", "lokal_id": "A.V.1"}) == []


def test_r10_omtale_mod_eget_nummeranker_spaerres():
    # Kalibrering 2026-07-29: terra kasserede 4 RIGTIGE personer med afhugget
    # tekst som omtaler. Omtaler har intet eget løbenummer — anker-forankring
    # modsiger påstanden, og gaten sender posten til review.
    issues = validate.tjek_omtale({"er_omtale": True}, {"metode": "anker"})
    assert issues and "R10" in issues[0]


def test_r10_tier_uden_anker_signal():
    # Fail-soft: fallback-segmenteret eller ukendt metode → kan ikke konkludere.
    assert validate.tjek_omtale({"er_omtale": True}, {"metode": "gruppe-fallback"}) == []
    assert validate.tjek_omtale({"er_omtale": True}, None) == []
    assert validate.tjek_omtale({"er_omtale": False}, {"metode": "anker"}) == []


def test_r10_haandhaeves_af_validate_selv():
    issues, _ = validate.validate(
        {"linje": "1939", "nr_label": "42", "side": "508", "lokal_id": "A.1",
         "er_omtale": True, "facts": []},
        {"raw_text": "N.N. † 1300.", "metode": "anker"}, {})
    assert any(i.startswith("R10") for i in issues)


def test_kontraktfelter_passerer_r5():
    # er_omtale/tekst_afhugget/koen_kilde manglede i ALLOWED_TOP — R5 ville
    # have flagget ethvert kontrakt-konformt udtræk som tredjeparts-felter.
    issues, _ = validate.validate(
        {"linje": "1939", "nr_label": "42", "side": "508", "lokal_id": "A.1",
         "er_omtale": False, "tekst_afhugget": True, "koen_kilde": "kilde", "facts": []},
        {"raw_text": "N.N. † 1300."}, {})
    assert not any(i.startswith("R5") for i in issues)


def test_r9_haandhaeves_af_validate_selv():
    # Codex-review 2026-07-29, fund 1: tjek_lokator fandtes men blev aldrig
    # kaldt — validate() lod poster uden lokator passere RENE, og registeret
    # gjorde str(None) til en gyldig nøgle. Gaten er nu inde i validate().
    issues, _ = validate.validate(
        {"linje": "1939", "nr_label": "42", "facts": []},
        {"raw_text": "N.N. † 1300."}, {})
    assert any(i.startswith("R9") for i in issues)
