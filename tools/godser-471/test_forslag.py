"""Tests for forslagsarket til godsernes sammenlægning (#471, fase 1).

Kører uden database: alle data er små fixtures. Kør med
`/usr/bin/python3 -m pytest tools/godser-471/test_forslag.py`.
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

import pytest

HER = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("forslag", HER / "forslag.py")
forslag = importlib.util.module_from_spec(_spec)
sys.modules["forslag"] = forslag
_spec.loader.exec_module(forslag)

REPO = HER.parents[1]


def data(rows, snapshots=(), media=(), samme_ejer=(), udgave=None):
    """rows: (id, navn[, antal ejerforhold[, periode]]). Ejerforholdenes relations-id = id*100 + n."""
    estates, ejer = [], []
    for r in rows:
        eid, navn = r[0], r[1]
        n = r[2] if len(r) > 2 else 1
        periode = r[3] if len(r) > 3 else None
        estates.append({"id": eid, "navn": navn, "slags": None, "sted_id": None, "sted": None})
        for i in range(n):
            u = (udgave or {}).get(eid, "DAA 2018-20")
            ejer.append({"rid": eid * 100 + i, "estate": eid, "periode": periode,
                         "kilder": [{"source_id": 1 if u == "DAA 2018-20" else 3, "udgave": u}],
                         "kopierbar": True})
    return {"estates": estates, "ejer": ejer, "media": list(media), "snapshots": list(snapshots),
            "gods_relationer": [], "andre_koblinger": [], "samme_ejer": list(samme_ejer), "levende_estates": [],
            "kilder": {"DAA 2018-20": 1, "DAA 1939": 3}}


def gruppe_med(f, eid):
    for g in f.grupper:
        if eid in g.medlemmer:
            return g
    raise AssertionError(f"ingen gruppe med {eid}")


# ---------- navnenøglen ----------

def test_noegle_ignorerer_parentes_til_og_store_bogstaver():
    keys = {forslag.parse_navn(n).noegle for n in ["Wittenberg", "Wittenberg (1779)", "Wittenberg (til)"]}
    assert keys == {"gård:wittenberg"}


def test_noegle_for_majorat_uden_formord():
    a = forslag.parse_navn("Grevskabet Christianssæde (1775)")
    b = forslag.parse_navn("grevskabet Christianssæde")
    assert a.noegle == b.noegle == "grevskab:christianssæde"
    assert a.art == "grevskab"


def test_noegle_uden_bindestreg_og_haarde_bindestreger():
    assert forslag.parse_navn("Baroniet Brahe-Trolleborg (1722)").noegle == \
        forslag.parse_navn("baroniet Brahetrolleborg").noegle
    assert forslag.parse_navn("Ober-Ellguth").noegle == forslag.parse_navn("Ober‑Ellguth").noegle


def test_til_foran_og_flertal_af_formord():
    p = forslag.parse_navn("til Grevskaberne Reventlow og Christianssæde")
    assert p.art == "grevskab" and p.liste == "flertal"
    assert p.noegle == "grevskab:reventlow"
    assert p.dele == ["Christianssæde"]


def test_ingen_automatisk_aa_til_aa():
    p = forslag.parse_navn("Gaarz")
    assert p.hoved == "Gaarz" and p.noegle == "gård:gaarz"


def test_med_liste_giver_gaard_og_dele():
    p = forslag.parse_navn("Christianssæde med Pederstrup, Aalstrup og Frihedsminde")
    assert p.liste == "med" and p.hoved == "Christianssæde"
    assert p.dele == ["Pederstrup", "Aalstrup", "Frihedsminde"]
    assert p.noegle == "gård:christianssæde"


def test_landsbyer_er_ikke_gaarde():
    p = forslag.parse_navn("Rixdorf med landsbyerne Sellin")
    assert p.hoved == "Rixdorf" and p.landsbyer and p.dele == []


def test_sammen_med_er_ikke_en_liste():
    p = forslag.parse_navn("Bjørnholm (Sønder Dyrs H.), sammen med broderen Ove")
    assert p.sammen_med and p.liste is None and p.dele == []


def test_og_liste_er_egen_gruppe_med_dele():
    p = forslag.parse_navn("Aakær og Dybvad (1802 Medejer, 1816-1836 Eneejer)")
    assert p.liste == "og" and p.dele == ["Aakær", "Dybvad"]
    assert p.noegle != forslag.parse_navn("Aakær").noegle


def test_ikke_gaard_ord_flages():
    assert forslag.parse_navn("Silkeborg Len").ikke_gaard
    assert forslag.parse_navn("det Reventlowske palæ").ikke_gaard
    assert forslag.parse_navn("Lollands Sønder Herred (1752)").ikke_gaard
    assert not forslag.parse_navn("Skivehus").ikke_gaard
    assert not forslag.parse_navn("Bibow (pantegods)").ikke_gaard


def test_navneskift_i_parentes():
    assert forslag.parse_navn("grevskabet Christiansborg (fra 1741 Christianssæde)").navneskift == "Christianssæde"
    assert forslag.parse_navn("Gjællebrede (senere Ditlevslyst)").navneskift == "Ditlevslyst"


# ---------- gruppering og forslag ----------

def test_wittenberg_en_gruppe_gaard():
    f = forslag.byg_forslag(data([(5, "Wittenberg", 3), (405, "Wittenberg (1779)"), (417, "Wittenberg (til)")]))
    g = gruppe_med(f, 5)
    assert sorted(g.medlemmer) == [5, 405, 417]
    assert g.art == "gård" and g.forvalg == "A"
    ops = g.alternativer["A"].ops
    assert ops["saet"] == [{"estate": 5, "navn": "Wittenberg", "slags": "gård", "gruppe": g.nr}]
    assert sorted(o["fra"] for o in ops["sammenlaeg"]) == [405, 417]
    assert all(o["til"] == 5 for o in ops["sammenlaeg"])


def test_christianssaede_majorat_en_gruppe_med_stort_formord():
    f = forslag.byg_forslag(data([(372, "Grevskabet Christianssæde (1775)"), (170, "grevskabet Christianssæde", 6)]))
    g = gruppe_med(f, 170)
    assert sorted(g.medlemmer) == [170, 372] and g.art == "grevskab"
    ops = g.alternativer[g.forvalg].ops
    assert ops["saet"][0]["estate"] == 170
    assert ops["saet"][0]["navn"] == "Grevskabet Christianssæde"
    assert ops["sammenlaeg"] == [{"fra": 372, "til": 170, "gruppe": g.nr}]


def test_med_liste_gaard_og_kopi_til_tre_gaarde():
    f = forslag.byg_forslag(data([(171, "Christianssæde med Pederstrup, Aalstrup og Frihedsminde"),
                                  (367, "Pederstrup med Skjelstofte (1725)")]))
    g = gruppe_med(f, 171)
    assert g.art == "gård" and g.navn == "Christianssæde" and g.forvalg == "A"
    ops = g.alternativer["A"].ops
    assert ops["saet"][0] == {"estate": 171, "navn": "Christianssæde", "slags": "gård", "gruppe": g.nr}
    til = [k["til"] for k in ops["kopier"]]
    assert til == [367, f"ny:G{g.nr}:Aalstrup", f"ny:G{g.nr}:Frihedsminde"]
    assert {k["citat"] for k in ops["kopier"]} == {"Christianssæde med Pederstrup, Aalstrup og Frihedsminde"}
    assert {k["relation"] for k in ops["kopier"]} == {17100}
    assert [o["noegle"] for o in ops["opret"]] == [f"ny:G{g.nr}:Aalstrup", f"ny:G{g.nr}:Frihedsminde"]
    assert all(o["slags"] == "gård" for o in ops["opret"])


def test_landsbyer_flages_og_giver_ingen_kopi():
    f = forslag.byg_forslag(data([(34, "Rixdorf", 6), (290, "Rixdorf med landsbyerne Sellin"), (52, "Sellin", 2)]))
    g = gruppe_med(f, 290)
    assert 34 in g.medlemmer
    assert any("landsby" in t.lower() for t in g.info + g.tvivl)
    for alt in g.alternativer.values():
        assert alt.ops["kopier"] == []


def test_gaarz_forbliver_gaarz():
    f = forslag.byg_forslag(data([(27, "Gaarz", 2)]))
    g = gruppe_med(f, 27)
    assert g.navn == "Gaarz"
    assert g.alternativer[g.forvalg].ops["saet"][0]["navn"] == "Gaarz"


def test_snapshot_raekke_overlever():
    # 261 har et slettet ejerforhold i change_event; 172 har det nyeste navn og billedet.
    d = data([(261, "Baroniet Brahe-Trolleborg", 6), (172, "baroniet Brahetrolleborg", 8)],
             snapshots=[261], udgave={261: "DAA 1939"})
    f = forslag.byg_forslag(d)
    g = gruppe_med(f, 172)
    ops = g.alternativer[g.forvalg].ops
    assert ops["sammenlaeg"] == [{"fra": 172, "til": 261, "gruppe": g.nr}]
    assert ops["saet"][0] == {"estate": 261, "navn": "Baroniet Brahetrolleborg", "slags": "baroni", "gruppe": g.nr}


def test_to_snapshot_raekker_giver_ingen_forvalg():
    f = forslag.byg_forslag(data([(1, "Lammershagen", 3), (298, "Lammershagen (solgt 1668)")], snapshots=[1, 298]))
    g = gruppe_med(f, 1)
    assert g.forvalg is None and g.tvivl


def test_forskellige_steder_giver_ingen_forvalg():
    d = data([(90, "Gottesgabe", 2), (120, "Gottesgabe (Sterdebølgaard)")])
    d["estates"][0]["sted_id"], d["estates"][1]["sted_id"] = 436, 453
    g = gruppe_med(forslag.byg_forslag(d), 90)
    assert g.forvalg is None


def test_ikke_gaard_har_intet_forvalg_for_art():
    g = gruppe_med(forslag.byg_forslag(data([(100, "Silkeborg Len")])), 100)
    assert g.forvalg is None
    assert {a.ops["saet"][0]["slags"] for a in g.alternativer.values()} == {"gård", None}


def test_og_liste_tilbydes_delt_uden_forvalg():
    f = forslag.byg_forslag(data([(161, "Aakær"), (162, "Dybvad"), (408, "Aakær og Dybvad (1802 Medejer)")]))
    g = gruppe_med(f, 408)
    assert g.medlemmer == [408] and g.forvalg is None
    delt = [a for a in g.alternativer.values() if a.ops["sammenlaeg"]]
    assert delt and delt[0].ops["sammenlaeg"] == [{"fra": 408, "til": 161, "gruppe": g.nr}]
    assert [k["til"] for k in delt[0].ops["kopier"]] == [162]


def test_enkeltraekke_med_parentes_beholder_navnet():
    g = gruppe_med(forslag.byg_forslag(data([(360, "Kain (1690)")])), 360)
    # Runde 3: det korte navn er forslaget, når det er utvetydigt; bogens navn kan stadig vælges.
    assert g.forvalg == "A"
    assert g.alternativer["A"].ops["saet"][0]["navn"] == "Kain"
    assert any(a.ops["saet"][0]["navn"] == "Kain (1690)" for a in g.alternativer.values())


def test_navneskift_samler_grupper():
    f = forslag.byg_forslag(data([(170, "grevskabet Christianssæde", 6),
                                  (205, "grevskabet Christiansborg (fra 1741 Christianssæde)"),
                                  (363, "Grevskabet Christiansborg (1729)")]))
    g = gruppe_med(f, 170)
    assert sorted(g.medlemmer) == [170, 205, 363]


def test_stavevariant_er_et_spoergsmaal_ikke_et_forvalg():
    f = forslag.byg_forslag(data([(198, "Broløkke", 2), (427, "Brolykke")]))
    assert gruppe_med(f, 198) is not gruppe_med(f, 427)
    s = [s for s in f.sammenhaenge if {198, 427} <= set(s.medlemmer)]
    assert s and s[0].forvalg is None


def test_ved_tilfoejelse_er_et_spoergsmaal():
    f = forslag.byg_forslag(data([(146, "Aschau", 6), (406, "Aschau ved Altenhof (1782)")]))
    assert any({146, 406} <= set(s.medlemmer) for s in f.sammenhaenge)


def test_hoerer_under_er_altid_et_spoergsmaal_og_krenkerup_moenstret_flages():
    f = forslag.byg_forslag(data([(202, "stamhuset Krenkerup", 3, "1736-1790"), (210, "Krenkerup", 1, "1750-1760")]))
    h = [h for h in f.hoerer if h.majorat_gruppe == gruppe_med(f, 202).nr]
    assert h and h[0].forvalg is None and h[0].krenkerup
    assert any("Krenkerup" in t for t in gruppe_med(f, 210).info + gruppe_med(f, 210).tvivl)


def test_bygningsbillede_paa_majorat_flyttes_til_gaarden():
    media = [{"rid": 3433, "media_id": 208, "estate": 172, "slags": "gods",
              "titel": "Brahetrolleborg (Brahetrolleborg Sogn, Sallinge Herred) 1722-1972 i slægtens eje"},
             {"rid": 3412, "media_id": 189, "estate": 172, "slags": "våben", "titel": None}]
    f = forslag.byg_forslag(data([(172, "baroniet Brahetrolleborg", 8), (189, "Brahetrolleborg")], media=media))
    g = gruppe_med(f, 172)
    assert g.alternativer[g.forvalg].ops["flyt"] == [{"relation": 3433, "til": 189, "gruppe": g.nr}]


def test_eksakt_kopi_der_allerede_findes_udelades_og_flages():
    # Ejeren af relation 7500 står allerede på Tresdorf (6) med samme periode og kilde.
    d = data([(5, "Wittenberg", 2), (75, "Wittenberg med Tresdorf"), (6, "Tresdorf")],
             samme_ejer=[[7500, 6, 600, True]])
    g = gruppe_med(forslag.byg_forslag(d), 75)
    assert g.alternativer[g.forvalg].ops["kopier"] == []
    assert any("findes allerede" in t for t in g.info)


# ---------- samlet plan ----------

def test_plan_samler_kun_forvalg_og_har_kilde_hash():
    f = forslag.byg_forslag(data([(5, "Wittenberg", 3), (405, "Wittenberg (1779)"), (100, "Silkeborg Len"),
                                  (171, "Christianssæde med Pederstrup, Aalstrup og Frihedsminde"),
                                  (369, "Taastrup og Aalstrup (1728)")]))
    p = f.plan("db", {"estate": "e", "relation": "r"})
    assert p["version"] == 1 and p["kilde_hash"] == {"estate": "e", "relation": "r"}
    assert list(p)[:9] == ["version", "kilde_db", "kilde_hash", "opret", "saet", "sammenlaeg", "kopier",
                           "hoerer_under", "flyt"]
    assert 100 not in {s["estate"] for s in p["saet"]}
    assert f"G{gruppe_med(f, 100).nr}" in p["aabne"]
    assert [o["navn"] for o in p["opret"]].count("Aalstrup") == 1
    forslag.valider_plan(p, snapshots=set())


def test_valider_plan_afviser_kaede_og_snapshot():
    p = {"opret": [], "saet": [], "kopier": [], "hoerer_under": [], "flyt": [],
         "sammenlaeg": [{"fra": 1, "til": 2}, {"fra": 2, "til": 3}]}
    with pytest.raises(forslag.PlanFejl):
        forslag.valider_plan(p, snapshots=set())
    p["sammenlaeg"] = [{"fra": 1, "til": 2}]
    with pytest.raises(forslag.PlanFejl):
        forslag.valider_plan(p, snapshots={1})
    p["sammenlaeg"], p["kopier"] = [], [{"relation": 1, "til": "ny:X", "citat": "c"}]
    with pytest.raises(forslag.PlanFejl):
        forslag.valider_plan(p, snapshots=set())


# ---------- arket, sti-vagt og persondata ----------

def test_ark_inde_i_repo_afvises(tmp_path):
    with pytest.raises(SystemExit):
        forslag.tjek_ark_sti(REPO / "tools" / "godser-471" / "x.html")
    with pytest.raises(SystemExit):
        forslag.tjek_ark_sti(REPO / "tools" / ".." / "tools" / "x.html")
    assert forslag.tjek_ark_sti(tmp_path / "ark.html") == (tmp_path / "ark.html").resolve()


def test_html_escaper_navne():
    f = forslag.byg_forslag(data([(1, "<script>x</script>")]))
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": {"estate": "e", "relation": "r"}})
    assert "<script>x</script>" not in html and "&lt;script&gt;" in html


def test_sql_laeser_kun_personers_levende_flag():
    sql = [v for k, v in vars(forslag).items() if k.startswith("SQL_")]
    assert sql
    med_person = [s for s in sql if re.search(r"\bperson\b\s+\w+\s+on|\bjoin\s+person\b|\bfrom\s+person\b", s, re.I)]
    assert med_person == [forslag.SQL_LEVENDE_EJER]
    assert re.search(r"\bp\.levende\b", forslag.SQL_LEVENDE_EJER)
    assert not re.search(r"\bp\.(navn|visning|fornavn|efternavn|koen)", forslag.SQL_LEVENDE_EJER, re.I)


def test_levende_ejer_paa_navn_med_tekst_stopper():
    d = data([(5, "Wittenberg (købt af Hr. X)")])
    d["levende_estates"] = [5]
    with pytest.raises(forslag.PlanFejl):
        forslag.byg_forslag(d)


# ---------- rettelser efter første kørsel mod prod-kopien ----------

def test_forkortet_bindestreg_udvides():
    p = forslag.parse_navn("Koppel med Gross- og Klein‑Koppel, Etelsen")
    assert p.dele == ["Gross-Koppel", "Klein\u2011Koppel", "Etelsen"]


def test_med_i_parentes_kraever_et_stednavn():
    assert not forslag.parse_navn("Gneningen (Hansiihn S., arvet med hustru)").parentes_med
    assert forslag.parse_navn("Lammershagen (med Selent, Bäslin og Bauersdorf)").parentes_med


def test_stedtilfoejelse_goer_ikke_arten_tvivlsom():
    assert not forslag.parse_navn("Glibstrup Gaard i Andst Sogn").ikke_gaard
    assert not forslag.parse_navn("Kollerup, Galten Herred (1692)").ikke_gaard
    assert forslag.parse_navn("Dänischenhagen Sogn (til 1780)").ikke_gaard


def test_overlevende_er_raekken_med_sted():
    d = data([(93, "Dörphof"), (136, "Dörphof (Torp)")])
    d["estates"][1]["sted_id"], d["estates"][1]["sted"] = 471, "Karby S."
    g = gruppe_med(forslag.byg_forslag(d), 93)
    assert g.overlever == 136 and g.navn == "Dörphof"


def test_og_deling_saetter_ikke_maalets_navn_og_springer_maerkelige_lister_over():
    f = forslag.byg_forslag(data([(27, "Gaarz", 2), (267, "Gaarz og Kaden (arvekrav 1528)"),
                                  (190, "Polle I og II")]))
    delt = gruppe_med(f, 267).alternativer["A"].ops
    assert delt["saet"] == [] and delt["sammenlaeg"][0] == {"fra": 267, "til": 27, "gruppe": gruppe_med(f, 267).nr}
    polle = gruppe_med(f, 190)
    assert polle.forvalg is None and not any(a.ops["sammenlaeg"] or a.ops["kopier"]
                                             for a in polle.alternativer.values())


def test_kopi_til_navn_der_ligner_en_eksisterende_gaard_er_tvivl():
    f = forslag.byg_forslag(data([(75, "Lundsgaard med Filipsborg"), (316, "Philipsburg i Angel (forpagtet 1700)")]))
    g = gruppe_med(f, 75)
    assert g.forvalg is None
    assert any("Philipsburg" in t for t in g.tvivl)


def test_og_lister_der_kun_adskiller_sig_ved_sted_er_et_spoergsmaal():
    f = forslag.byg_forslag(data([(213, "Ballegaard og Bøgskov"), (393, "Ballegaard og Bøgskov i Sundeved")]))
    assert any({213, 393} <= set(s.medlemmer) for s in f.sammenhaenge)


def test_samme_sogn_stavet_forskelligt_er_ikke_tvivl():
    d = data([(147, "Osterrade"), (140, "Osterrade med Bovenau")])
    d["estates"][0].update(sted_id=484, sted="Bovenau S., Rendsburg Kr.")
    d["estates"][1].update(sted_id=478, sted="Bovenau S., Rendsburg-Egernførde Kr.")
    assert not any("steder" in t for t in gruppe_med(forslag.byg_forslag(d), 147).tvivl)


def test_stavevarianter_samles_i_et_spoergsmaal():
    f = forslag.byg_forslag(data([(262, "Neudorf"), (106, "Neudorff"), (151, "Neuendorf"), (34, "Pugerup"),
                                  (219, "Ugerup")]))
    s = [s for s in f.sammenhaenge if 262 in s.medlemmer]
    assert len(s) == 1 and {262, 106, 151} <= set(s[0].medlemmer)
    assert not any({34, 219} <= set(x.medlemmer) for x in f.sammenhaenge)  # forskelligt forbogstav


def test_med_hr_i_parentes_er_ikke_en_liste():
    assert not forslag.parse_navn("Gaarz og Kaden (arvekrav 1528, trætte med Hr. Iven Reventlow)").parentes_med


def test_haard_bindestreg_bevares_i_navnet():
    f = forslag.byg_forslag(data([(158, "Ober\u2011Ellguth"), (416, "Ober-Ellguth")], udgave={416: "DAA 1939"}))
    g = gruppe_med(f, 158)
    assert sorted(g.medlemmer) == [158, 416] and g.navn == "Ober\u2011Ellguth"


def test_gaardnavn_inde_i_et_andet_navn_er_et_spoergsmaal():
    f = forslag.byg_forslag(data([(32, "Glibstrup"), (264, "Glibstrup Gaard i Andst Sogn"), (371, "Tølløse"),
                                  (203, "Tølløsegaard"), (384, "til Bistingsmåla i Mønsterås"),
                                  (226, "gård i Bistingsmåla"), (306, "Lammershagen — solgt til Bertram Rantzau"),
                                  (143, "Rantzau")]))
    par = [set(s.medlemmer) for s in f.sammenhaenge]
    for a, b in ((32, 264), (371, 203), (384, 226)):
        assert any({a, b} <= x for x in par), (a, b)
    assert not any({306, 143} <= x for x in par)


def test_sted_paa_raekke_der_laegges_sammen_vises():
    d = data([(170, "grevskabet Christianssæde", 6), (205, "grevskabet Christiansborg (fra 1741 Christianssæde)")],
             snapshots=[170])
    d["estates"][1].update(sted_id=667, sted="Skørringe S., Fuglse H.")
    g = gruppe_med(forslag.byg_forslag(d), 170)
    assert g.overlever == 170 and any("Skørringe" in t for t in g.info)


def test_stedtilfoejelse_skaber_ikke_lighed_med_stedet():
    f = forslag.byg_forslag(data([(119, "Altenhof"), (406, "Aschau ved Altenhof (1782)"), (36, "kongsgård i Hamburg"),
                                  (37, "Hvidøre Kongsgaard")]))
    par = [set(s.medlemmer) for s in f.sammenhaenge]
    assert not any({119, 406} <= x for x in par) and not any({36, 37} <= x for x in par)



# ---------- review-runde 1 ----------

def test_fixture_noegler_er_dem_hent_data_giver():
    d = data([(1, "X")])
    kilde = Path(forslag.__file__).read_text(encoding="utf-8")
    for k in d:
        assert f'"{k}"' in kilde, k


def test_forskellige_majorater_i_dag_giver_tvivl():
    d = data([(5, "Wittenberg"), (405, "Wittenberg (1779)"), (170, "grevskabet A"), (163, "grevskabet B")])
    d["gods_relationer"] = [
        {"rid": 1, "subjekt_type": "estate", "subjekt_id": 5, "objekt_type": "estate", "objekt_id": 170,
         "rolle": "hører_under"},
        {"rid": 2, "subjekt_type": "estate", "subjekt_id": 405, "objekt_type": "estate", "objekt_id": 163,
         "rolle": "hører_under"}]
    g = gruppe_med(forslag.byg_forslag(d), 5)
    assert g.forvalg is None and any("forskellige majorater" in t for t in g.tvivl)


def test_kopi_til_sognets_navn_er_tvivl():
    d = data([(147, "Osterrade"), (140, "Osterrade med Bovenau")])
    d["estates"][0].update(sted_id=484, sted="Bovenau S., Rendsburg Kr.")
    d["estates"][1].update(sted_id=478, sted="Bovenau S., Rendsburg-Egernførde Kr.")
    g = gruppe_med(forslag.byg_forslag(d), 147)
    assert g.forvalg is None and any("sognet" in t and "Bovenau" in t for t in g.tvivl)
    assert any(not a.ops["kopier"] and a.ops["sammenlaeg"] for a in g.alternativer.values())


def test_sogn_i_parentes_mod_overlevendes_sted():
    d = data([(27, "Gaarz", 2), (254, "Gaarz (Oldenburg Sogn, nævnt 1472)")])
    d["estates"][0].update(sted_id=392, sted="Göhl S., Oldenburg Kr.")
    g = gruppe_med(forslag.byg_forslag(d), 27)
    assert g.forvalg is None and any("Oldenburg" in t for t in g.tvivl)
    # stavevarianter af samme sogn er ikke tvivl
    for sted, navn in (("Krokek S., Östergötland Len", "Getå (Krokels S.)"),
                       ("Östra Strö S., Malmöhus Len", "Jeppstorp (Strø S.)"),
                       ("Oldenburg S., Ostholstein Kr.", "Bankendorf (Oldenburg Sogn i Holsten)")):
        hoved = navn.split(" (")[0]
        d = data([(1, hoved), (2, navn)])
        d["estates"][0].update(sted_id=9, sted=sted)
        assert gruppe_med(forslag.byg_forslag(d), 1).forvalg == "A", navn


def test_sogn_i_parentes_uden_sted_paa_overlevende_er_info():
    g = gruppe_med(forslag.byg_forslag(data([(174, "Pugerup", 4), (378, "Pugerup (Gudmunstorp S.) (1845)")])), 174)
    assert g.forvalg == "A" and any("Gudmunstorp" in t for t in g.info)


def test_krenkerup_moenster_streng_slut_og_aabne_perioder():
    assert forslag.periode_spaend("1924\u2011†") == (1924, None)
    assert forslag.periode_spaend("1889\u2011afløst 26. marts 1924") == (1889, 1924)
    # Christianssæde: gårdens ejer tiltræder det år, grevskabet afløses → ikke mønstret
    f = forslag.byg_forslag(data([(170, "grevskabet Christianssæde", 1, "1889\u2011afløst 26. marts 1924"),
                                  (171, "Christianssæde", 1, "1924\u2011†")]))
    assert not any(h.krenkerup for h in f.hoerer)
    # Krenkerup: stamhusets ejere 1736‑† (åbent), gårdens 1750‑† → mønstret
    f = forslag.byg_forslag(data([(202, "stamhuset Krenkerup", 1, "1736\u2011†"), (210, "Krenkerup", 1, "1750\u2011†")]))
    assert any(h.krenkerup for h in f.hoerer)


def test_kort_navn_med_flere_loese_traef_er_tvivl():
    f = forslag.byg_forslag(data([(1, "Holm med Kain"), (2, "Kain Mark"), (3, "Store Kain")]))
    g = gruppe_med(f, 1)
    assert g.forvalg is None and any("passer løst" in t for t in g.tvivl)


def test_enkeltraekke_med_kopi_kan_beholde_navnet_og_fravaelge_kopien():
    g = gruppe_med(forslag.byg_forslag(data([(367, "Pederstrup med Skjelstofte (1725)")])), 367)
    alts = list(g.alternativer.values())
    assert any(a.ops["saet"][0]["navn"] == "Pederstrup med Skjelstofte (1725)" and a.ops["kopier"] for a in alts)
    assert any(a.ops["saet"][0]["navn"] == "Pederstrup" and not a.ops["kopier"] and not a.ops["opret"] for a in alts)


def test_len_efter_komma_er_ikke_en_gaard():
    assert forslag.parse_navn("Below (Bälau ved Mölln), fik 1376 til Len af Greve Henrik").ikke_gaard


def test_ingen_dobbelt_art_og_ingen_kryptiske_koder():
    g = gruppe_med(forslag.byg_forslag(data([(100, "Silkeborg Len")])), 100)
    assert all(re.fullmatch(r"[A-P]", k) for k in g.alternativer)
    assert not any("art art" in a.tekst for a in g.alternativer.values())



# ---------- runde 2: udfyldeligt ark og fletning af svar ----------

import json as _json

FIXTUR = [(5, "Wittenberg", 3), (405, "Wittenberg (1779)"), (100, "Silkeborg Len"),
          (171, "Christianssæde med Pederstrup, Aalstrup og Frihedsminde"), (367, "Pederstrup med Skjelstofte (1725)"),
          (369, "Taastrup og Aalstrup (1728)"), (198, "Broløkke", 2), (427, "Brolykke"), (199, "Brolykke (til)"),
          (202, "stamhuset Krenkerup", 1, "1736\u2011†"), (210, "Krenkerup", 1, "1750\u2011†"),
          (75, "Lundsgaard med Filipsborg"), (316, "Philipsburg i Angel (forpagtet 1700)")]
KH = {"estate": "e", "relation": "r"}


def _forslag():
    f = forslag.byg_forslag(data(FIXTUR))
    p = f.plan("db", KH)
    return f, p, forslag.plan_sha(p)


def _fuldt_svar(p, sha, **saerlige):
    svar = {}
    for pid in p["aabne"]:
        if pid.startswith("S"):
            svar[pid] = "nej"
        elif pid.startswith("H"):
            svar[pid] = {"svar": "nej"}
        else:
            svar[pid] = sorted(p["alternativer"][pid])[0]
    svar.update(saerlige)
    return {"version": 1, "kilde_hash": KH, "plan_forslag_sha256": sha, "svar": svar}


def test_flet_fuldt_svar_giver_gyldig_plan():
    f, p, sha = _forslag()
    plan, opsum = forslag.flet(p, sha, _fuldt_svar(p, sha))
    forslag.valider_plan(plan, f.snapshots)
    assert list(plan)[:9] == ["version", "kilde_db", "kilde_hash", *forslag.OPS]
    assert "aabne" not in plan and "alternativer" not in plan
    assert any("sammenlægninger" in l for l in opsum)


@pytest.mark.parametrize("fejl", ["mangler", "ukendt", "gammel_hash", "gammel_sha", "ugyldigt_valg", "ekstra_noegle",
                                  "h_uden_citat"])
def test_flet_afviser(fejl):
    f, p, sha = _forslag()
    s = _fuldt_svar(p, sha)
    if fejl == "mangler":
        del s["svar"][p["aabne"][0]]
    elif fejl == "ukendt":
        s["svar"]["G999"] = "A"
    elif fejl == "gammel_hash":
        s["kilde_hash"] = {"estate": "x", "relation": "r"}
    elif fejl == "gammel_sha":
        s["plan_forslag_sha256"] = "0" * 64
    elif fejl == "ugyldigt_valg":
        s["svar"][p["aabne"][0]] = "Z"
    elif fejl == "ekstra_noegle":
        s["bemaerkning"] = "x"
    elif fejl == "h_uden_citat":
        h = next(x for x in p["aabne"] if x.startswith("H"))
        s["svar"][h] = {"svar": "ja", "periode": "1750-1760", "citat": "", "kilde": 1}
    with pytest.raises(forslag.FletFejl):
        forslag.flet(p, sha, s)


def test_flet_h_ja_bruger_svarets_felter():
    f, p, sha = _forslag()
    h = next(x for x in p["aabne"] if x.startswith("H"))
    plan, _ = forslag.flet(p, sha, _fuldt_svar(p, sha, **{h: {"svar": "ja", "periode": "1750-1760",
                                                              "citat": "bogens ord", "kilde": 3}}))
    assert plan["hoerer_under"] == [{"gaard": 210, "majorat": 202, "periode": "1750-1760", "source": 3,
                                     "citat": "bogens ord", "gruppe": h}]


def test_flet_s_ja_erstatter_gruppernes_egne_sammenlaegninger():
    f, p, sha = _forslag()
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S"
                and {198, 427} <= {m for g in x["grupper"] for m in p["poster"][g]["medlemmer"]})
    gl = p["poster"][s_id]["grupper"]
    hoved = p["poster"][gl[0]]["overlever"]
    plan, _ = forslag.flet(p, sha, _fuldt_svar(p, sha, **{s_id: "ja"}))
    medl = [m for g in gl for m in p["poster"][g]["medlemmer"] if m != hoved]
    assert sorted(o["fra"] for o in plan["sammenlaeg"] if o["fra"] in medl) == sorted(medl)
    assert all(o["til"] == hoved for o in plan["sammenlaeg"] if o["fra"] in medl)
    assert not any(o["estate"] in medl for o in plan["saet"])


def test_flet_s_ja_mod_behold_adskilt_afvises():
    f, p, sha = _forslag()
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S"
                and any(len(p["poster"][g]["medlemmer"]) > 1 for g in x["grupper"]))
    gl = p["poster"][s_id]["grupper"]
    g = next(g for g in gl if len(p["poster"][g]["medlemmer"]) > 1)
    adskilt = next(k for k, a in p["alternativer"][g].items() if a.get("adskilt"))
    if g == gl[0]:
        # hovedgruppen kan ikke både holdes adskilt og samle de andre
        with pytest.raises(forslag.FletFejl, match="adskilt"):
            forslag.flet(p, sha, _fuldt_svar(p, sha, **{s_id: "ja", g: adskilt}))
    else:
        # en gruppe, som S-»ja« afgør: dens gamle svar ignoreres
        plan, opsum = forslag.flet(p, sha, _fuldt_svar(p, sha, **{s_id: "ja", g: adskilt}))
        assert any(g in l and "ignoreret" in l for l in opsum)


def test_ark_har_en_inputgruppe_pr_beslutning_og_ingen_personfelter():
    f, p, sha = _forslag()
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH, "plan_sha": sha})
    radio_navne = {n for n in re.findall(r'type=radio name="([^"]+)"', html) if "~" not in n}
    beslut = set(re.findall(r'data-id="([^"]+)"', html))
    assert radio_navne == beslut
    forventet = {f"G{g.nr}" for g in f.grupper}  # alle grupper kan deles op
    forventet |= {s.nr for s in f.sammenhaenge} | {h.nr for h in f.hoerer} | {q.nr for q in f.nye}
    assert beslut == forventet
    alle_navne = set(re.findall(r'name="([^"]+)"', html.split("<script>")[0]))
    assert all(re.fullmatch(r"[GSHN]\d+(~G\d+|-periode|-citat|-kilde|-gruppe)?", n) for n in alle_navne), alle_navne
    assert not re.search(r"person|fornavn|efternavn", html, re.I)
    # ingen forvalg ved »Du skal vælge«
    for pid in p["aabne"]:
        assert not re.search(rf'name="{pid}" value="[^"]+" checked', html), pid
    assert '"plan_sha": "' + sha in html and "http" not in html.split("<script>")[1]


def test_rundtur_ark_svar_flet_valider():
    f, p, sha = _forslag()
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH, "plan_sha": sha})
    meta = _json.loads(re.search(r"<script type=application/json id=meta>(.*?)</script>", html).group(1))
    svar = {}
    for pid in sorted(set(re.findall(r'data-id="([^"]+)"', html))):
        koder = re.findall(rf'name="{pid}" value="([^"]+)"', html)
        if pid.startswith("H"):
            svar[pid] = {"svar": "ja", "periode": "", "citat": "bogens ord", "kilde": 1}
        elif pid in p["aabne"]:
            svar[pid] = [k for k in koder if k not in ("del", "samme")][-1]
    plan, _ = forslag.flet(p, sha, {"version": 1, "kilde_hash": meta["kilde_hash"],
                                    "plan_forslag_sha256": meta["plan_sha"], "svar": svar})
    forslag.valider_plan(plan, f.snapshots)


def test_cli_flet_skriver_intet_ved_fejl(tmp_path):
    f, p, sha = _forslag()
    pf = tmp_path / "plan.forslag.json"
    pf.write_text(forslag.plan_tekst(p), encoding="utf-8")
    svar = _fuldt_svar(p, sha)
    del svar["svar"][p["aabne"][0]]
    sf = tmp_path / "svar.json"
    sf.write_text(_json.dumps(svar), encoding="utf-8")
    ud = tmp_path / "plan.json"
    assert forslag.main(["--flet", str(sf), "--plan", str(pf), "--plan-ud", str(ud)]) == 1
    assert not ud.exists()
    sf.write_text(_json.dumps(_fuldt_svar(p, sha)), encoding="utf-8")
    assert forslag.main(["--flet", str(sf), "--plan", str(pf), "--plan-ud", str(ud)]) == 0
    forslag.valider_plan(_json.loads(ud.read_text(encoding="utf-8")), f.snapshots)


# ---------- runde 3: kort navn og klart sprog ----------

def test_below_faar_det_korte_navn_tilbudt():
    navn = "Below (Bälau ved Mölln), fik 1376 til Len af Greve Henrik"
    n = forslag.parse_navn(navn)
    assert forslag.kort_navn(n) == "Below" and forslag.kort_entydigt(n, "Below")
    g = gruppe_med(forslag.byg_forslag(data([(249, navn)])), 249)
    assert g.forvalg is None  # »Len« gør slags tvivlsom
    valg = {(a.ops["saet"][0]["navn"], a.ops["saet"][0]["slags"]) for a in g.alternativer.values()}
    assert ("Below", None) in valg and ("Below", "gård") in valg and (navn, "gård") in valg
    # det dårlige mellemvalg (parentes væk, sætningen bevaret) tilbydes ikke længere
    assert not any(x[0].startswith("Below, fik") for x in valg)
    assert any("Bälau ved Mölln" in t and "sted" in t for t in g.info)
    assert "Navnet rummer mere end godsets navn" in g.problem and "ikke på en gård" in g.problem


def test_kort_navn_er_forslag_kun_naar_det_er_utvetydigt():
    f = forslag.byg_forslag(data([(361, "Kollerup, Galten Herred (1692)"), (253, "Forpagter af Gjelskov i Fyen (1670)"),
                                  (158, "Ober‑Ellguth (1739)")]))
    assert gruppe_med(f, 361).alternativer[gruppe_med(f, 361).forvalg].ops["saet"][0]["navn"] == "Kollerup"
    assert gruppe_med(f, 158).alternativer["A"].ops["saet"][0]["navn"] == "Ober‑Ellguth"
    g = gruppe_med(f, 253)
    assert g.forvalg is None and any(a.ops["saet"][0]["navn"] == "Forpagter af Gjelskov"
                                     for a in g.alternativer.values())


def test_gaardliste_med_er_uaendret():
    g = gruppe_med(forslag.byg_forslag(data([(171, "Christianssæde med Pederstrup, Aalstrup og Frihedsminde")])), 171)
    a = g.alternativer["A"].ops
    assert a["saet"][0]["navn"] == "Christianssæde" and len(a["kopier"]) == 3


def test_valgene_siger_hvad_laeseren_ser():
    f = forslag.byg_forslag(data([(5, "Wittenberg", 3), (405, "Wittenberg (1779)"), (100, "Silkeborg Len")]))
    for g in f.grupper:
        for a in g.alternativer.values():
            assert "Siden viser" in a.tekst, a.tekst
            assert " art " not in a.tekst and "parentes" not in a.tekst
        assert g.problem
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH})
    assert "Hvad er problemet?" in html


def test_autosave_noegle_pr_post_med_fingeraftryk():
    f = forslag.byg_forslag(data(FIXTUR))
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH, "plan_sha": "x" * 64})
    js = html.split("<script>")[1]
    noegle = re.search(r"var NOEGLE = ([^;]+);", js).group(1)
    assert "plan_sha" not in noegle and "kilde_hash" in noegle
    for p_ in f.poster():
        pid = forslag.post_id(p_)
        m = re.search(rf'id="{pid}"[^>]*data-valghash="([0-9a-f]+)"', html)
        assert m and m.group(1) == forslag.valg_hash(p_), pid
    g = f.grupper[0]
    h0 = forslag.valg_hash(g)
    for a in g.alternativer.values():
        a.tekst += " (ny formulering)"
    assert forslag.valg_hash(g) == h0  # ny tekst: svaret genbruges
    next(iter(g.alternativer.values())).ops["saet"][0]["navn"] += "x"
    assert forslag.valg_hash(g) != h0  # andre operationer: spørg igen
    # flettingen afviser stadig et svar på et andet forslag
    p = f.plan("db", KH)
    s = _fuldt_svar(p, "0" * 64)
    with pytest.raises(forslag.FletFejl, match="andet forslag"):
        forslag.flet(p, forslag.plan_sha(p), s)


# ---------- review-runde 2 (runde 2-3): modstridende svar ----------

def _alle_aabne(f, p, **saerlige):
    svar = {}
    for pid in p["aabne"]:
        if pid[0] in "SN":
            svar[pid] = "nej"
        elif pid[0] == "H":
            svar[pid] = {"svar": "nej"}
        else:
            svar[pid] = sorted(p["alternativer"][pid])[0]
    svar.update(saerlige)
    return svar


def _flet(f, svar):
    p = f.plan("db", KH)
    sha = forslag.plan_sha(p)
    return forslag.flet(p, sha, {"version": 1, "kilde_hash": KH, "plan_forslag_sha256": sha, "svar": svar})


def _kode(g, navn=None, pred=None):
    for k, a in g.alternativer.items():
        if (navn is None or a.ops["saet"] and a.ops["saet"][0]["navn"] == navn) and (pred is None or pred(a)):
            return k
    raise AssertionError((navn, list(g.alternativer)))


def test_m1_kort_navn_der_rammer_en_anden_gruppe_er_ikke_forslag_og_kollision_afvises():
    f = forslag.byg_forslag(data([(162, "Kollerup"), (361, "Kollerup, Galten Herred (1692)")]))
    g = gruppe_med(f, 361)
    assert g.forvalg is None and any("også navnet på gruppe" in t for t in g.tvivl)
    p = f.plan("db", KH)
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S")
    svar = _alle_aabne(f, p, **{f"G{g.nr}": _kode(g, "Kollerup")})
    with pytest.raises(forslag.FletFejl, match=rf"(?i)svar ja i {s_id}.*»Kollerup«"):
        _flet(f, svar)
    plan, _ = _flet(f, {**svar, s_id: "ja"})
    assert {"fra": 361, "til": 162, "gruppe": s_id} in plan["sammenlaeg"]


def test_m2_nye_gaarde_deles_kun_ved_ja():
    f = forslag.byg_forslag(data([(1, "Holm med Aalstrup"), (2, "Gram med Aalstrup")]))
    g1, g2 = gruppe_med(f, 1), gruppe_med(f, 2)
    n1 = g1.alternativer["A"].ops["opret"][0]["noegle"]
    n2 = g2.alternativer["A"].ops["opret"][0]["noegle"]
    assert n1 != n2 and n1.startswith(f"ny:G{g1.nr}:")
    assert len(f.nye) == 1
    nid = f.nye[0].nr
    with pytest.raises(forslag.FletFejl, match=rf"(?i)svar ja i {nid}.*»Aalstrup«"):
        _flet(f, {nid: "nej"})
    plan, _ = _flet(f, {nid: "ja"})
    assert [o["noegle"] for o in plan["opret"]] == ["ny:Aalstrup"]
    assert {k["til"] for k in plan["kopier"]} == {"ny:Aalstrup"} and len(plan["kopier"]) == 2
    # nej er i orden, når kun den ene gruppe opretter gården
    plan, _ = _flet(f, {nid: "nej", f"G{g2.nr}": _kode(g2, pred=lambda a: not a.ops["kopier"])})
    assert len(plan["opret"]) == 1


FRIS = [(201, "stamhuset Frisenvold", 1, "1731‑†"), (166, "Frisenvold", 1, "1684-1703"),
        (358, "Friisenvold")]


def test_m3_hoerer_under_med_forskellige_citater_efter_s_ja_afvises_ens_citat_samles():
    f = forslag.byg_forslag(data(FRIS))
    p = f.plan("db", KH)
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S")
    h = [x.nr for x in f.hoerer]
    assert len(h) == 2
    ja = lambda c: {"svar": "ja", "periode": "1731-1800", "citat": c, "kilde": 1}
    with pytest.raises(forslag.FletFejl, match="forskellige citater"):
        _flet(f, _alle_aabne(f, p, **{s_id: "ja", h[0]: ja("ord A"), h[1]: ja("ord B")}))
    plan, _ = _flet(f, _alle_aabne(f, p, **{s_id: "ja", h[0]: ja("ord A"), h[1]: ja("ord A")}))
    # L4: »hører under« peger om på den overlevende gård
    surv = p["poster"][p["poster"][s_id]["grupper"][0]]["overlever"]
    assert [(o["gaard"], o["majorat"]) for o in plan["hoerer_under"]] == [(surv, 201)]


def test_l4_kopier_og_flytninger_peger_om_efter_s_ja():
    media = [{"rid": 3434, "media_id": 209, "estate": 170, "slags": "gods",
              "titel": "Tresdorf (Selent Sogn) 1700-1800 i slægtens eje"}]
    f = forslag.byg_forslag(data([(5, "Wittenberg med Tresdorf"), (6, "Tresdorf"), (7, "Tresdorff", 3),
                                  (170, "grevskabet Tresdorf", 2)], media=media, udgave={6: "DAA 1939"}))
    p = f.plan("db", KH)
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S")
    gl = p["poster"][s_id]["grupper"]
    surv = p["poster"][gl[0]]["overlever"]
    assert surv == 7  # 6 (1939) lægges ind i 7 (2018-20)
    plan, _ = _flet(f, _alle_aabne(f, p, **{s_id: "ja"}))
    fra = {o["fra"] for o in plan["sammenlaeg"]}
    assert 6 in fra
    assert {k["til"] for k in plan["kopier"]} == {7}
    assert [x["til"] for x in plan["flyt"]] == [7]


def test_m4_ingen_chatinstrukser_og_kopimaal_kan_vaelges_i_arket():
    f = forslag.byg_forslag(data([(75, "Lundsgaard med Filipsborg"), (316, "Philipsburg i Angel (forpagtet 1700)"),
                                  (1, "Neudorf"), (2, "Neudorff"), (3, "Neuendorf")]))
    g = gruppe_med(f, 75)
    maal = {a.ops["kopier"][0]["til"] for a in g.alternativer.values() if a.ops["kopier"]}
    assert 316 in maal and any(isinstance(x, str) and x.endswith(":Filipsborg") for x in maal)
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH})
    for t in ("svar med gruppenummeret", "svar »ny«", "sig til", "i chatten", "Svar evt.", "fx »H"):
        assert t not in html, t
    s = next(x for x in f.sammenhaenge if len(x.grupper) == 3)
    assert "delvis" in s.alternativer and html.count(f'name="{s.nr}-gruppe"') == 3


def test_s_delvis_laegger_kun_de_valgte_sammen():
    f = forslag.byg_forslag(data([(1, "Neudorf", 2), (2, "Neudorff"), (3, "Neuendorf")]))
    p = f.plan("db", KH)
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S")
    gl = p["poster"][s_id]["grupper"]
    plan, _ = _flet(f, _alle_aabne(f, p, **{s_id: {"svar": "delvis", "grupper": [gl[2], gl[0]]}}))
    head = p["poster"][gl[0]]["overlever"]
    flyttet = {o["fra"] for o in plan["sammenlaeg"] if o["gruppe"] == s_id}
    assert flyttet == set(p["poster"][s_id]["flyttes"][gl[2]]) and all(
        o["til"] == head for o in plan["sammenlaeg"] if o["gruppe"] == s_id)
    for daarlig in ({"svar": "delvis", "grupper": [gl[0]]}, {"svar": "delvis", "grupper": [gl[0], "G999"]},
                    ["ja"], "delvis"):
        with pytest.raises(forslag.FletFejl):
            _flet(f, _alle_aabne(f, p, **{s_id: daarlig}))


def test_og_liste_kort_navn_beholder_hele_listen():
    n = forslag.parse_navn("Eskær, Astrup og Skivehus i Nørre H. (1735-50)")
    assert forslag.kort_navn(n) == "Eskær, Astrup og Skivehus"


@pytest.mark.parametrize("h", [{"svar": "ja", "citat": ["liste"], "kilde": 1},
                               {"svar": "ja", "citat": "x", "kilde": 999},
                               {"svar": "ja", "citat": "x", "kilde": 1.0},
                               {"svar": "ja", "citat": "x", "kilde": True},
                               {"svar": "ja", "periode": {"x": 1}, "citat": "x", "kilde": 1},
                               {"svar": ["ja"]}])
def test_l1_h_felternes_typer_og_kilde(h):
    f = forslag.byg_forslag(data(FRIS))
    p = f.plan("db", KH)
    with pytest.raises(forslag.FletFejl):
        _flet(f, _alle_aabne(f, p, **{f.hoerer[0].nr: h}))


def test_l2_svar_sha_er_filens_bytes_og_l3_plan_ud_maa_ikke_vaere_forslaget(tmp_path):
    f, p, sha = _forslag()
    pf = tmp_path / "plan.forslag.json"
    pf.write_text(forslag.plan_tekst(p), encoding="utf-8")
    sf = tmp_path / "svar.json"
    sf.write_bytes(("  " + _json.dumps(_fuldt_svar(p, sha), indent=3) + "\n").encode("utf-8"))
    ud = tmp_path / "plan.json"
    assert forslag.main(["--flet", str(sf), "--plan", str(pf), "--plan-ud", str(ud)]) == 0
    import hashlib
    assert _json.loads(ud.read_text())["grundlag"]["svar_sha256"] == hashlib.sha256(sf.read_bytes()).hexdigest()
    foer = pf.read_bytes()
    assert forslag.main(["--flet", str(sf), "--plan", str(pf), "--plan-ud", str(pf)]) == 1
    assert pf.read_bytes() == foer


def test_l3_samme_relation_flyttet_to_gange_afvises():
    p = {"opret": [], "saet": [], "sammenlaeg": [], "kopier": [], "hoerer_under": [],
         "flyt": [{"relation": 1, "til": 2}, {"relation": 1, "til": 3}]}
    with pytest.raises(forslag.PlanFejl):
        forslag.valider_plan(p, snapshots=set())


def test_l3_to_nye_gaarde_under_samme_majorat_faar_hvert_sit_billede():
    media = [{"rid": 10, "media_id": 1, "estate": 196, "slags": "gods",
              "titel": "Vallø (Valløby Sogn) 1713-1730 hovedsæde i grevskabet Vallø"},
             {"rid": 11, "media_id": 2, "estate": 196, "slags": "gods",
              "titel": "Gammel Vallø (Valløby Sogn) 1700-1712 hovedsæde i grevskabet Vallø"}]
    f = forslag.byg_forslag(data([(196, "grevskabet Vallø")], media=media))
    flyt = sorted(h.alternativer["ja"].ops["flyt"][0]["relation"] for h in f.hoerer)
    assert flyt == [10, 11]


def test_l5_autosave_gemmer_ikke_uroerte_forslag():
    js = forslag.JS
    assert 'k.getAttribute("data-skal") !== "1" && v === k.getAttribute("data-forvalg")' in js



# ---------- projektejerens navneregel 27/11: »det skal bare være godset« ----------

@pytest.mark.parametrize("navn, kort", [
    ("Aschau ved Altenhof (1782)", "Aschau"),
    ("Tovskov i Sommersted Sogn (købt før 1476)", "Tovskov"),
    ("Kongsgaard i Hamborg (forlenet 1510)", "Kongsgaard"),
    ("Steensgaard i Fyen (ejede 1472)", "Steensgaard"),
    ("Nørre-Gyldenbjerg ved Nakskov (til)", "Nørre-Gyldenbjerg"),
    ("Wennberga i Brostorp i Frosta Herred", "Wennberga"),
    ("til Rudbjerggaard, Maribo Amt (1891)", "Rudbjerggaard"),
    ("Ober\u2011Ellguth ved X", "Ober\u2011Ellguth"),
    ("Gaarz (Oldenburg Sogn)", "Gaarz"),
    ("gård i Bistingsmåla", "gård i Bistingsmåla"),
    ("det Reventlowske hus i Amaliegade", "det Reventlowske hus i Amaliegade"),
    ("Ballegaard og Bøgskov i Sundeved", "Ballegaard og Bøgskov"),
    ("Grevskabet Christianssæde (1775)", "Grevskabet Christianssæde"),
])
def test_godsets_navn_uden_stedtilfoejelse(navn, kort):
    assert forslag.kort_navn(forslag.parse_navn(navn)) == kort


def test_stedtilfoejelse_giver_forslag_naar_utvetydigt_og_tvivl_ved_kollision():
    f = forslag.byg_forslag(data([(406, "Aschau ved Altenhof (1782)"), (333, "Stubbe i Riseby S. (1722)")]))
    for eid, navn in ((406, "Aschau"), (333, "Stubbe")):
        g = gruppe_med(f, eid)
        assert g.forvalg and g.alternativer[g.forvalg].ops["saet"][0]["navn"] == navn
    f = forslag.byg_forslag(data([(146, "Aschau", 6), (406, "Aschau ved Altenhof (1782)")]))
    g = gruppe_med(f, 406)
    assert g.forvalg is None and any("også navnet på gruppe" in t for t in g.tvivl)


def test_ny_gaard_fra_liste_faar_godsets_navn_og_teksten_viser_ikke_noeglen():
    f = forslag.byg_forslag(data([(213, "Ballegaard og Bøgskov i Sundeved")]))
    g = gruppe_med(f, 213)
    delt = next(a for a in g.alternativer.values() if a.ops["opret"])
    assert [o["navn"] for o in delt.ops["opret"]] == ["Bøgskov"]
    assert "Bøgskov (ny side)" in delt.tekst and ":Bøgskov" not in delt.tekst


def test_n_nej_siger_hvornaar_det_virker():
    f = forslag.byg_forslag(data([(1, "Holm med Aalstrup"), (2, "Gram med Aalstrup i Salling")]))
    assert len(f.nye) == 1
    assert f.nye[0].alternativer["nej"].tekst.startswith("Nej, forskellige gårde — virker kun, hvis")


# ---------- arket viser navnekonflikter, mens man svarer (JS = Python) ----------

import random as _random
import shutil as _shutil
import subprocess as _subprocess


def _tilfaeldige_valg(p, n, frø=0):
    rng = _random.Random(frø)
    ud = []
    for _ in range(n):
        v = {}
        for pid, alts in p["alternativer"].items():
            if pid not in p["aabne"] and rng.random() < 0.6:
                continue
            k = rng.choice(list(alts))
            if pid[0] == "G" and rng.random() < 0.05:
                v[pid] = {"svar": "ikke"}
                continue
            if pid[0] == "G" and rng.random() < 0.05:
                v[pid] = {"svar": "samme", "maal": rng.choice([x for x in p["poster"] if x[0] == "G" and x != pid])}
                continue
            if pid[0] == "G" and rng.random() < 0.08:
                maal = rng.choice(["ny", rng.choice([x for x in p["poster"] if x[0] == "G" and x != pid])])
                v[pid] = {"svar": "del", "dele": [{"navn": f"Del{pid}", "slags": "gård", "maal": "ny"},
                                                   {"navn": "Koppel", "slags": None, "maal": maal}]}
                continue
            if k == "delvis":
                gl = p["poster"][pid]["grupper"]
                v[pid] = {"svar": "delvis", "grupper": rng.sample(gl, rng.randint(2, len(gl)))}
            else:
                v[pid] = {"svar": k}
        ud.append(v)
    return ud


def _reparerede_svar(p, n, frø=3):
    """Svarsæt, der kan godkendes: S/N ja, H nej, tilfældige ikke-adskilte gruppevalg; grupper i konflikt
    sættes tilbage til forslaget (eller første valg), til reglen ikke finder flere."""
    d = forslag.konfliktdata(p)
    ud = []
    for i in range(n):
        rng = _random.Random(frø * 1000 + i)
        svar = {}
        for pid, alts in p["alternativer"].items():
            if pid[0] in "SN":
                svar[pid] = "ja"
            elif pid[0] == "H":
                svar[pid] = {"svar": "nej"}
            elif pid in p["aabne"] or rng.random() < 0.5:
                svar[pid] = rng.choice([k for k, a in alts.items() if not a.get("adskilt")])
        for _ in range(6):
            ks = forslag.konflikter(d, {k: (v if isinstance(v, dict) else {"svar": v}) for k, v in svar.items()})
            if not ks:
                break
            for k in ks:
                for h in k["hvem"]:
                    if h.startswith("G"):
                        svar[h] = p["forvalg"].get(h) or list(p["alternativer"][h])[0]
        ud.append(svar)
    return ud


def _planer_til_test():
    planer = [_forslag()[1]]
    rigtig = HER / "plan.forslag.json"
    if rigtig.exists():
        planer.append(_json.loads(rigtig.read_text(encoding="utf-8")))
    return planer


@pytest.mark.skipif(not _shutil.which("node"), reason="node findes ikke på maskinen")
def test_arkets_konfliktberegning_er_den_samme_som_fletningens(tmp_path):
    for p in _planer_til_test():
        d = forslag.konfliktdata(p)
        valg = _tilfaeldige_valg(p, 150) + [{}] + [
            {k: (v if isinstance(v, dict) else {"svar": v}) for k, v in s.items()} for s in _reparerede_svar(p, 30)]
        py = [[forslag.konflikter(d, v), forslag.afgjorte(d, v)] for v in valg]
        js_fil = tmp_path / "k.js"
        js_fil.write_text(forslag.JS_KONFLIKT + "\nconst D = " + _json.dumps(d, ensure_ascii=False) +
                          ";\nconst V = " + _json.dumps(valg, ensure_ascii=False) +
                          ";\nprocess.stdout.write(JSON.stringify(V.map(v => [konflikter(D, v), afgjorte(D, v)])));\n", encoding="utf-8")
        ud = _subprocess.run(["node", str(js_fil)], capture_output=True, text=True, check=True).stdout
        assert _json.loads(ud) == _json.loads(_json.dumps(py, ensure_ascii=False))
        assert any(x[0] for x in py) and any(x[1] for x in py)  # testen rammer konflikter og afgjorte grupper


def test_konfliktreglen_passer_med_den_faerdige_plan():
    """Hvor regel og plan er enige: ingen konflikt ⇒ planen har ingen to sider med samme navn og slags."""
    for p in _planer_til_test():
        sha = forslag.plan_sha(p)
        d = forslag.konfliktdata(p)
        godkendt = 0
        tilf = []
        for v in _tilfaeldige_valg(p, 200, frø=7):
            s_ = {pid: (x if x["svar"] == "delvis" else x["svar"]) for pid, x in v.items() if pid[0] != "H"}
            s_.update({pid: {"svar": "nej"} for pid in p["aabne"] if pid[0] == "H"})
            tilf.append(s_)
        for svar in tilf + _reparerede_svar(p, 40):
            valg = {pid: (x if isinstance(x, dict) else {"svar": x}) for pid, x in svar.items()}
            try:
                plan, _ = forslag.flet(p, sha, {"version": 1, "kilde_hash": p["kilde_hash"],
                                                "plan_forslag_sha256": sha, "svar": svar})
            except forslag.FletFejl:
                continue
            # Godkendt plan ⇒ reglen fandt ingen konflikt, og planen har ingen to sider med samme navn og slags.
            assert not forslag.konflikter(d, valg)
            navne = [(forslag.navn_ens(o["navn"]), o["slags"]) for o in plan["saet"] + plan["opret"]]
            assert len(navne) == len(set(navne))
            godkendt += 1
        assert godkendt >= 40  # mindst de reparerede svarsæt godkendes


def test_arket_har_konfliktdata_og_advarer_ved_gem():
    f, p, sha = _forslag()
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH, "plan_sha": sha})
    d = _json.loads(re.search(r"<script type=application/json id=konflikt>(.*?)</script>", html).group(1))
    assert d == _json.loads(_json.dumps(forslag.konfliktdata(p), ensure_ascii=False))
    assert "id=konflikter" in html and "fletningen vil afvise dem" in html and "function konflikter(" in html



# ---------- et »ja« til samme gods afgør de berørte grupper ----------

def test_s_ja_afgoer_gruppen_i_fletningen_og_nej_kraever_den_igen():
    f = forslag.byg_forslag(data([(146, "Aschau", 6), (406, "Aschau ved Altenhof (1782)")]))
    p = f.plan("db", KH)
    g8 = f"G{gruppe_med(f, 406).nr}"
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S")
    assert g8 in p["aabne"]
    d = forslag.konfliktdata(p)
    assert forslag.afgjorte(d, {s_id: {"svar": "ja"}}) == {g8: [s_id, f"G{gruppe_med(f, 146).nr}"]}
    plan, opsum = _flet(f, {s_id: "ja"})  # G8 mangler: afgjort af S
    assert {"fra": 406, "til": 146, "gruppe": s_id} in plan["sammenlaeg"]
    assert not any(o["estate"] == 406 for o in plan["saet"])
    plan2, opsum2 = _flet(f, {s_id: "ja", g8: "B"})  # gammelt svar ignoreres
    assert plan2["sammenlaeg"] == plan["sammenlaeg"] and any("ignoreret: " + g8 in l for l in opsum2)
    with pytest.raises(forslag.FletFejl, match=f"{g8}: mangler svar"):
        _flet(f, {s_id: "nej"})
    assert forslag.afgjorte(d, {s_id: {"svar": "nej"}}) == {}


def test_s_ja_afgoer_ikke_en_gruppe_med_kopier():
    f = forslag.byg_forslag(data([(88, "Lundegaard", 3), (75, "Lundsgaard med Filipsborg")]))
    p = f.plan("db", KH)
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S")
    g = f"G{gruppe_med(f, 75).nr}"
    assert g in p["poster"][s_id]["grupper"][1:]
    assert g not in forslag.afgjorte(forslag.konfliktdata(p), {s_id: {"svar": "ja"}})


def test_arket_har_spoergsmaalet_inde_i_gruppen_og_foer_den():
    f = forslag.byg_forslag(data([(146, "Aschau", 6), (406, "Aschau ved Altenhof (1782)")]))
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH})
    s_id = f.sammenhaenge[0].nr
    g8 = f"G{gruppe_med(f, 406).nr}"
    assert f'name="{s_id}~{g8}"' in html and f'data-spejl="{s_id}"' in html
    assert html.index(f'id="{s_id}"') < html.index(f'id="{g8}"')
    assert "Svar først på, om grupperne er samme gods" in html
    assert "function afgjorte(" in forslag.JS_KONFLIKT



# ---------- »del op i flere godser« ----------

FIDEI = [(395, "Fideikommisgodserne Varste-Polle og Koppel"), (182, "Koppel", 2), (180, "Varste")]


def test_del_forslag_fra_navnet_uden_ejerskabsform():
    f = forslag.byg_forslag(data(FIDEI))
    g = gruppe_med(f, 395)
    assert g.dele_forslag == [{"navn": "Varste-Polle", "slags": "gård", "maal": "ny"},
                              {"navn": "Koppel", "slags": "gård", "maal": f"G{gruppe_med(f, 182).nr}"}]


def test_del_op_omdoeber_og_kopierer_til_eksisterende_gruppe():
    f = forslag.byg_forslag(data(FIDEI))
    g, koppel = gruppe_med(f, 395), gruppe_med(f, 182)
    p = f.plan("db", KH)
    dele = [{"navn": "Varste-Polle", "slags": "gård", "maal": "ny"},
            {"navn": "Koppel", "slags": "gård", "maal": f"G{koppel.nr}"}]
    plan, opsum = _flet(f, _alle_aabne(f, p, **{f"G{g.nr}": {"svar": "del", "dele": dele}}))
    assert {"estate": 395, "navn": "Varste-Polle", "slags": "gård", "gruppe": g.nr} in plan["saet"]
    assert {"relation": 39500, "til": 182, "citat": "Fideikommisgodserne Varste-Polle og Koppel",
            "gruppe": g.nr} in plan["kopier"]
    assert any("delt op i 2" in l for l in opsum)


def test_del_op_med_to_nye_sider():
    f = forslag.byg_forslag(data(FIDEI))
    g = gruppe_med(f, 395)
    p = f.plan("db", KH)
    dele = [{"navn": "Varste-Polle", "slags": "gård", "maal": "ny"}, {"navn": "Nykoppel", "slags": None, "maal": "ny"}]
    plan, _ = _flet(f, _alle_aabne(f, p, **{f"G{g.nr}": {"svar": "del", "dele": dele}}))
    assert {"noegle": f"ny:G{g.nr}:Nykoppel", "navn": "Nykoppel", "slags": None, "gruppe": g.nr} in plan["opret"]
    assert {"relation": 39500, "til": f"ny:G{g.nr}:Nykoppel", "citat": "Fideikommisgodserne Varste-Polle og Koppel",
            "gruppe": g.nr} in plan["kopier"]


def test_del_op_del_1_til_eksisterende_laegger_raekken_ind():
    f = forslag.byg_forslag(data(FIDEI))
    g, varste = gruppe_med(f, 395), gruppe_med(f, 180)
    p = f.plan("db", KH)
    dele = [{"navn": "Varste", "slags": "gård", "maal": f"G{varste.nr}"},
            {"navn": "Koppel", "slags": "gård", "maal": f"G{gruppe_med(f, 182).nr}"}]
    plan, _ = _flet(f, _alle_aabne(f, p, **{f"G{g.nr}": {"svar": "del", "dele": dele}}))
    assert {"fra": 395, "til": 180, "gruppe": g.nr} in plan["sammenlaeg"]
    assert not any(o["estate"] == 395 for o in plan["saet"])


@pytest.mark.parametrize("dele, tekst", [
    ([{"navn": "Varste-Polle", "slags": "gård", "maal": "ny"}], "mindst to"),
    ([{"navn": "Varste-Polle", "slags": "gård", "maal": "ny"}, {"navn": "Koppel", "slags": "gård", "maal": "G999"}],
     "ukendt mål"),
    ([{"navn": "Varste-Polle", "slags": "gård", "maal": "ny"}, {"navn": "", "slags": "gård", "maal": "ny"}],
     "navnet mangler"),
    ([{"navn": "Varste (1700)", "slags": "gård", "maal": "ny"}, {"navn": "Koppel", "slags": "gård", "maal": "ny"}],
     "ikke kun godsets navn"),
    ([{"navn": "Varste-Polle", "slags": "hus", "maal": "ny"}, {"navn": "Koppel", "slags": "gård", "maal": "ny"}],
     "ukendt slags"),
    ([{"navn": "Varste-Polle", "slags": "gård", "maal": "ny"}, {"navn": "Koppel", "slags": "gård", "maal": "SELV"}],
     "gruppen selv"),
])
def test_del_op_ugyldigt_afvises(dele, tekst):
    f = forslag.byg_forslag(data(FIDEI))
    g = gruppe_med(f, 395)
    p = f.plan("db", KH)
    dele = [dict(d, maal=f"G{g.nr}" if d["maal"] == "SELV" else d["maal"]) for d in dele]
    with pytest.raises(forslag.FletFejl, match=tekst):
        _flet(f, _alle_aabne(f, p, **{f"G{g.nr}": {"svar": "del", "dele": dele}}))


def test_del_op_til_afgjort_gruppe_afvises():
    f = forslag.byg_forslag(data([(146, "Aschau", 6), (406, "Aschau ved Altenhof (1782)"),
                                  (395, "Holm og Aschau ved Altenhof")]))
    p = f.plan("db", KH)
    s_id = next(pid for pid, x in p["poster"].items() if x["type"] == "S" and
                f"G{gruppe_med(f, 406).nr}" in x["grupper"])
    g = gruppe_med(f, 395)
    dele = [{"navn": "Holm", "slags": "gård", "maal": "ny"},
            {"navn": "Aschau", "slags": "gård", "maal": f"G{gruppe_med(f, 406).nr}"}]
    with pytest.raises(forslag.FletFejl, match="peg på"):
        _flet(f, _alle_aabne(f, p, **{s_id: "ja", f"G{g.nr}": {"svar": "del", "dele": dele}}))


def test_del_op_navnekonflikt_vises_i_reglen():
    f = forslag.byg_forslag(data(FIDEI))
    p = f.plan("db", KH)
    g = gruppe_med(f, 395)
    v = {f"G{g.nr}": {"svar": "del", "dele": [{"navn": "Koppel", "slags": "gård", "maal": "ny"},
                                               {"navn": "X", "slags": "gård", "maal": "ny"}]}}
    ks = forslag.konflikter(forslag.konfliktdata(p), v)
    assert any(k["navn"] == "Koppel" for k in ks)



# ---------- »samme gods som en anden gruppe« ----------

def _sogn_data():
    d = data([(157, "Kaltenhof", 1, "1750-1780"), (351, "Dänischenhagen Sogn (til 1780)", 1, "-1780"),
              (5, "Wittenberg", 2)], udgave={157: "DAA 1939", 351: "DAA 1939"})
    d["samme_ejer"] = [[35100, 157, 15700, False], [15700, 351, 35100, False]]
    return d


def test_samme_gods_laegger_raekken_ind_med_citat_og_hint():
    f = forslag.byg_forslag(_sogn_data())
    g69, g154 = gruppe_med(f, 351), gruppe_med(f, 157)
    assert g69.samme_hint == [[f"G{g154.nr}", "Kaltenhof"]] and not gruppe_med(f, 5).samme_hint
    p = f.plan("db", KH)
    plan, opsum = _flet(f, _alle_aabne(f, p, **{f"G{g69.nr}": {"svar": "samme", "maal": f"G{g154.nr}"}}))
    assert {"fra": 351, "til": 157, "gruppe": g69.nr} in plan["sammenlaeg"]
    assert not any(o["estate"] == 351 for o in plan["saet"])  # navnet gemmes som citat af sammenlægningen
    assert any("samme gods som" in l for l in opsum)
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH})
    assert "Mulig rigtig gård" in html and 'value="samme"' in html and "slet ikke et gods" in html


def test_samme_gods_kaede_og_snapshot_afvises():
    f = forslag.byg_forslag(_sogn_data())
    g69, g154, g5 = gruppe_med(f, 351), gruppe_med(f, 157), gruppe_med(f, 5)
    p = f.plan("db", KH)
    with pytest.raises(forslag.FletFejl, match="lægges selv ind i"):
        _flet(f, _alle_aabne(f, p, **{f"G{g69.nr}": {"svar": "samme", "maal": f"G{g154.nr}"},
                                      f"G{g154.nr}": {"svar": "samme", "maal": f"G{g5.nr}"}}))
    with pytest.raises(forslag.FletFejl, match="sig selv"):
        _flet(f, _alle_aabne(f, p, **{f"G{g69.nr}": {"svar": "samme", "maal": f"G{g69.nr}"}}))
    d = _sogn_data()
    d["snapshots"] = [351]
    f = forslag.byg_forslag(d)
    p = f.plan("db", KH)
    with pytest.raises(forslag.FletFejl, match="slettede ejerforhold"):
        _flet(f, _alle_aabne(f, p, **{f"G{gruppe_med(f, 351).nr}": {"svar": "samme",
                                                                     "maal": f"G{gruppe_med(f, 157).nr}"}}))


def test_raekke_uden_ejerforhold_beholder_bogens_navn():
    f = forslag.byg_forslag(data([(360, "Kain (1690)", 0)]))
    g = gruppe_med(f, 360)
    assert {a.ops["saet"][0]["navn"] for a in g.alternativer.values()} == {"Kain (1690)"}
    assert any("ingen ejerforhold" in t for t in g.info)
    p = f.plan("db", KH)
    with pytest.raises(forslag.FletFejl, match="ingen ejerforhold"):
        _flet(f, _alle_aabne(f, p, **{f"G{g.nr}": {"svar": "del", "dele": [
            {"navn": "Kain", "slags": "gård", "maal": "ny"}, {"navn": "Holm", "slags": "gård", "maal": "ny"}]}}))
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH})
    assert 'data-uden-ejer="Kain (1690)"' in html



# ---------- »ikke et gods (skjules)« ----------

IKKE = [(251, "Forlening af Preetz Kloster (1399)"),
        (230, "Skænkede o. 1240-45 (sammen med hustru X) et stykke jord til Bredenberg Sogn — bortgivet, ikke i eje."),
        (237, "andel af Ziesendorf (forlenet 1397)"), (84, "Ziesendorf", 3), (5, "Wittenberg", 2),
        (64, "Wittenberg med Ziesendorf")]


def test_ikke_gods_hint_og_aldrig_forvalgt():
    f = forslag.byg_forslag(data(IKKE))
    for eid in (251, 230, 237):
        g = gruppe_med(f, eid)
        assert g.ikke_hint and g.forvalg != "ikke" and "ikke" not in g.alternativer
    assert not gruppe_med(f, 84).ikke_hint and not gruppe_med(f, 5).ikke_hint
    html = forslag.render_html(f, {"kilde_db": "db", "kilde_hash": KH})
    assert "Forslag: Ikke et gods" in html and 'value="ikke"' in html and "Ikke et gods (skjules)" in html
    assert not re.search(r'value="ikke" checked', html)


def test_ikke_gods_saetter_slags_og_beholder_navn():
    f = forslag.byg_forslag(data(IKKE))
    p = f.plan("db", KH)
    g90, g230 = gruppe_med(f, 251), gruppe_med(f, 230)
    plan, opsum = _flet(f, _alle_aabne(f, p, **{f"G{g90.nr}": "ikke", f"G{g230.nr}": "ikke"}))
    for g, eid in ((g90, 251), (g230, 230)):
        assert {"estate": eid, "navn": f.raekker[eid]["navn"], "slags": "ikke_gods", "gruppe": g.nr} in plan["saet"]
    assert not any(o["fra"] in (251, 230) or o["til"] in (251, 230) for o in plan["sammenlaeg"])
    assert any("ikke et gods" in l for l in opsum)


def test_ikke_gods_kan_ikke_vaere_maal():
    f = forslag.byg_forslag(data(IKKE))
    p = f.plan("db", KH)
    g84, g64, g237 = f"G{gruppe_med(f, 84).nr}", f"G{gruppe_med(f, 64).nr}", f"G{gruppe_med(f, 237).nr}"
    # kopien fra »Wittenberg med Ziesendorf« peger på Ziesendorf
    with pytest.raises(forslag.FletFejl, match="ikke et gods"):
        _flet(f, _alle_aabne(f, p, **{g84: "ikke"}))
    with pytest.raises(forslag.FletFejl, match="ikke et gods"):
        _flet(f, _alle_aabne(f, p, **{g84: "ikke", g64: _kode(gruppe_med(f, 64), pred=lambda a: not a.ops["kopier"]),
                                      g237: {"svar": "samme", "maal": g84}}))
    d = forslag.konfliktdata(p)
    assert forslag.konflikter(d, {g237: {"svar": "ikke"}}) == []  # skjulte rækker kolliderer ikke


def test_ikke_gods_mod_s_ja_afvises():
    f = forslag.byg_forslag(data([(84, "Ziesendorf", 3), (237, "andel af Ziesendorf (forlenet 1397)")]))
    p = f.plan("db", KH)
    s_id = next((pid for pid, x in p["poster"].items() if x["type"] == "S"), None)
    if s_id is None:
        pytest.skip("intet S-spørgsmål i fixturen")
    g = p["poster"][s_id]["grupper"][1]
    with pytest.raises(forslag.FletFejl, match="ikke et gods"):
        _flet(f, _alle_aabne(f, p, **{s_id: "ja", g: "ikke"}))
