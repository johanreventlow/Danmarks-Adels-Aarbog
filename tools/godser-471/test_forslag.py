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
            "hoerer_under": [], "samme_ejer": list(samme_ejer), "levende_estates": [],
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
    assert til == [367, "ny:Aalstrup", "ny:Frihedsminde"]
    assert {k["citat"] for k in ops["kopier"]} == {"Christianssæde med Pederstrup, Aalstrup og Frihedsminde"}
    assert {k["relation"] for k in ops["kopier"]} == {17100}
    assert [o["noegle"] for o in ops["opret"]] == ["ny:Aalstrup", "ny:Frihedsminde"]
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
    assert g.forvalg == "A"
    assert g.alternativer["A"].ops["saet"][0]["navn"] == "Kain (1690)"
    assert any(a.ops["saet"][0]["navn"] == "Kain" for a in g.alternativer.values())


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
    assert gruppe_med(f, 100).nr in p["aabne"]
    assert [o["noegle"] for o in p["opret"]].count("ny:Aalstrup") == 1
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
