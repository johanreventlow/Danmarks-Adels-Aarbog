# test_perturbation.py — entydighed er ikke stabilitet: forstyr udtrækket og
# se hvad reconcile() gør.
#
# Baggrund (Codex-review 2026-07-29): forslaget om position_på_side som lokator
# faldt på at "tvetydig frem for forkert" ikke holdt — en indskudt post
# forskyder alle efterfølgende positioner, og reconcile() accepterer ethvert
# eksakt lokatorhit som entydigt. De tidligere målinger kunne ikke se det, for
# de talte kun distinkte værdier i ÉT øjebliksbillede. Stabilitet er en
# egenskab ved TO øjebliksbilleder; den kan kun måles ved at forstyrre.
#
# Harnesset: hver post bærer en skjult sandhed (_sand) som lokatoren ikke kan
# se. Efter reconcile tælles de entydige match op mod sandheden. Kravet til en
# lokator er IKKE nul tvetydige — det er NUL FORKERTE. Tvetydig og ny er
# lovlige udfald (de stopper og spørger); et forkert entydigt match er det
# eneste forbudte (det gætter og tier).
#
# Tests med KENDT_SVAGHED i navnet dokumenterer hvor den NUVÆRENDE lokator
# knækker. De er grønne fordi de asserter observeret adfærd — rettes
# lokatoren, skal de vendes til deres negation, ikke slettes.
from identitetsregister import Register, mint, reconcile


def post(sand: str, side: str, lokal_id: str) -> dict:
    """_sand er facit for hvem posten ER — usynlig for lokatoren."""
    return {"_sand": sand, "side": side, "lokal_id": lokal_id}


def byg(poster: list[dict], udgave: str = "1939"):
    """Mint et register og husk hvilken sandhed hvert id blev udstedt til."""
    reg = mint(Register(), poster, udgave)
    sand_af_id = {
        reg.poster[f"{udgave}|{p['side']}|{p['lokal_id']}"].book_post_id: p["_sand"]
        for p in poster
    }
    return reg, sand_af_id


def evaluer(reg, sand_af_id, poster, udgave: str = "1939") -> dict:
    res = reconcile(reg, poster, udgave)
    return {
        "korrekte": sum(1 for p, bid in res.entydige if sand_af_id[bid] == p["_sand"]),
        # (hvem udtrækket siger, hvem id'et blev udstedt til) — tom = fail-closed holdt
        "forkerte": [(p["_sand"], sand_af_id[bid])
                     for p, bid in res.entydige if sand_af_id[bid] != p["_sand"]],
        "tvetydige": len(res.tvetydige),
        "nye": len(res.nye),
        "bortfaldne": len(res.bortfaldne),
    }


# --- basislinje -------------------------------------------------------------

def test_uperturberet_udtraek_matcher_alt():
    poster = [post("a", "10", "A.1"), post("b", "10", "A.2"), post("c", "11", "B.1")]
    reg, sand = byg(poster)
    r = evaluer(reg, sand, poster)
    assert r["korrekte"] == 3 and not r["forkerte"]


# --- de fire kendte forstyrrelser ------------------------------------------

def test_sideskift_med_unik_lokal_id_meldes_tvetydig():
    # Posten flytter side (ny paginering). Unik lokal_id → reconcile FORESLÅR
    # kandidaten frem for at gætte. Lokatorens bedste udfald under drift.
    reg, sand = byg([post("a", "10", "A.1"), post("b", "11", "B.1")])
    r = evaluer(reg, sand, [post("a", "12", "A.1"), post("b", "11", "B.1")])
    assert not r["forkerte"] and r["tvetydige"] == 1 and r["korrekte"] == 1


def test_KENDT_SVAGHED_sidedrift_med_delt_lokal_id_giver_forkert_match():
    # 1939-virkeligheden: lokal_id har kun 425 distinkte værdier for 515
    # poster, og `side` er PDF-ordinal der allerede driver (59/515). Deler to
    # poster lokal_id på nabosider, lander den ene på den andens registrerede
    # nøgle ved én sides forskydning — og reconcile kalder det ENTYDIGT.
    reg, sand = byg([post("a", "10", "1"), post("b", "11", "1")])
    r = evaluer(reg, sand, [post("a", "11", "1"), post("b", "12", "1")])
    assert r["forkerte"] == [("a", "b")], \
        "vendepunkt: er lokatoren rettet, så vend denne test og fjern KENDT_SVAGHED"


def test_split_ny_post_meldes_ny_og_resten_er_uroert():
    # Segmenteringen opdager at én post var to. Den nye halvdel har sin egen
    # lokal_id → meldes ny. Ingen naboer forstyrres.
    reg, sand = byg([post("a", "10", "A.1"), post("b", "10", "A.2")])
    r = evaluer(reg, sand,
                [post("a", "10", "A.1"), post("a2", "10", "A.1a"), post("b", "10", "A.2")])
    assert not r["forkerte"] and r["nye"] == 1 and r["korrekte"] == 2


def test_merge_giver_bortfalden_ikke_forkert():
    # To poster slås sammen under den enes lokator. Den anden meldes
    # bortfalden — tombstones IKKE automatisk, for bortfald kan lige så vel
    # være en segmenteringsfejl. At indholdet nu er a+b kan reconcile ikke se;
    # det er narrativ-diffens opgave, ikke lokatorens.
    reg, sand = byg([post("a", "10", "A.1"), post("b", "10", "A.2")])
    r = evaluer(reg, sand, [post("a", "10", "A.1")])
    assert not r["forkerte"] and r["korrekte"] == 1 and r["bortfaldne"] == 1


# --- forslaget der faldt: position som lokator ------------------------------

def test_KENDT_SVAGHED_positionslokator_indskudt_post_stjaeler_id():
    # (side, position_på_side) målte 515/515 entydig — men en overset post
    # øverst på siden forskyder alle efterfølgende, og hver post arver sin
    # forgængers id. Tavst, som "entydige" match. Det er testen der skulle
    # have været skrevet i stedet for at tælle distinkte værdier.
    reg, sand = byg([post("a", "10", "pos1"), post("b", "10", "pos2")])
    r = evaluer(reg, sand,
                [post("ny", "10", "pos1"), post("a", "10", "pos2"), post("b", "10", "pos3")])
    assert r["forkerte"] == [("ny", "a"), ("a", "b")] and r["korrekte"] == 0


# --- regression på dagens fix ----------------------------------------------

def test_reconcile_taaler_generator_input():
    # Dublet-vagten (Codex-fix 2026-07-29) itererede poster to gange; uden
    # list() ville en generator være tom i hovedløkken og melde ALT bortfaldet.
    reg, _ = byg([post("a", "10", "A.1")])
    res = reconcile(reg, iter([{"side": "10", "lokal_id": "A.1"}]), "1939")
    assert len(res.entydige) == 1 and not res.bortfaldne
