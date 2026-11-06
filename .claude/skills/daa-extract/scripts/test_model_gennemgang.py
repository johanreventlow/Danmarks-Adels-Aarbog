"""Tests til trin 6m del 1: læse-kun eksport og model_gennemgang.py. Kun syntetiske fixtures, ingen rigtige navne."""
from __future__ import annotations

import re
from pathlib import Path

HERE = Path(__file__).parent
EKSPORT_SQL = HERE / "model_gennemgang_eksport.sql"


def _kode(sql: str) -> str:
    return "\n".join(l for l in sql.splitlines() if not l.lstrip().startswith("--"))


# --- Task 2: læse-kun eksport ---------------------------------------------------------------------------------

def test_eksport_sql_er_laese_kun():
    sql = EKSPORT_SQL.read_text(encoding="utf-8")
    kode = [l for l in _kode(sql).splitlines() if l.strip()]
    # Ét fast øjebliksbillede for hele eksporten: VOLATILE-funktioner ser ellers nyere commits (Codex 3).
    assert kode[0].strip() == "BEGIN;"
    assert kode[1].strip() == "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;"
    assert kode[-1].strip() == "ROLLBACK;"
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT)\b", "\n".join(kode), re.I)
    assert ":'src'" in sql or ":src" in sql
    # narrative_record_state med true låser (FOR UPDATE + LOCK TABLE) og fejler i READ ONLY (Codex #1).
    kald = re.findall(r"narrative_record_state\s*\(([^;]*?)\)", "\n".join(kode), re.S)
    assert kald, "eksporten skal hente state_sha256 fra narrative_record_state"
    for argumenter in kald:
        assert argumenter.split(",")[-1].strip().lower() == "false"


# --- Task 3: modelinput med filter og sidebilleder --------------------------------------------------------------

import hashlib  # noqa: E402
import json  # noqa: E402

import pytest  # noqa: E402

import control_model_v2 as v2  # noqa: E402
import model_gennemgang as mg  # noqa: E402

RID = "11111111-1111-4111-8111-111111111111"


def _plac(side: int, fra: int, tekst: str) -> list:
    return [{"side_fra": side, "side_til": side, "fra": fra, "til": fra + len(tekst), "rendition_id": RID,
             "stykker": [{"f": fra, "t": tekst}]}]


def _forslag(i: int, predicate: str, vaerdi: str, person_id=None, status="proposed") -> dict:
    return {"interpretation_id": f"aaaaaaaa-0000-4000-8000-{i:012d}", "version": 1, "predicate": predicate,
            "value_text": vaerdi, "status": status, "persona_id": f"bbbbbbbb-0000-4000-8000-{i:012d}",
            "person_id": person_id}


def _narrativ(person_id: int, tekst: str, status="published", tilladte=("publish_revision", "withdraw"),
              blokeret=None) -> dict:
    return {"person_id": person_id, "narrative_id": person_id * 10, "tekst": tekst, "status": status,
            "blokeret": blokeret, "tilladte": list(tilladte), "state_sha256": "c" * 64}


def eksport(**post_over) -> dict:
    """To poster: p1 med publiceret narrativ om person 1 (død), p2 uden narrativ. Person 2 er ikke sikker."""
    p1 = {"record_key": "R-1", "narrativ": _narrativ(1, "Testperson Alfa, f. 1801, død 1870."), "legacy": None,
          "placering": _plac(10, 0, "Testperson Alfa, f. 1801, d. 1870."),
          "forslag": [_forslag(1, "person.name", "Testperson Alfa", 1),
                      _forslag(2, "person.birth", "1801", 1),
                      _forslag(3, "mention.place", "Teststed", 1),
                      _forslag(4, "person.title", "Kammerherre", 2),
                      _forslag(5, "person.name", "Ubunden Beta")]}
    p1.update(post_over)
    p2 = {"record_key": "R-2", "narrativ": None, "legacy": None, "placering": _plac(11, 100, "Gamma, f. 1820."),
          "forslag": []}
    return {"udgave": "Testudgave 1939", "source_id": 3, "poster": [p1, p2],
            "personer": {"1": {"navn": "Testperson Alfa", "fuldt_navn": "Testperson Alfa", "foedt": "1801",
                               "doed": "1870", "titel": None},
                         "2": {"navn": "Ung Delta", "fuldt_navn": None, "foedt": "1950", "doed": None,
                               "titel": "Kammerherre"}}}


def _alle_forslag(bidder):
    return [f for b in bidder for p in b["poster"] for f in p["forslag"]]


def test_sikker_doed_eller_foedt_senest_1939():
    assert mg.sikker({"doed": "x"}) is True
    assert mg.sikker({"foedt": "f. 1936"}) is True
    assert mg.sikker({"foedt": "1940"}) is False
    assert mg.sikker({}) is False


def test_forslag_om_usikker_person_gaar_uden_dbvaerdi():
    """Projektejeren 6/11: forslaget går til modellen (bogteksten ser den alligevel), men databasens værdi for en
    person, der ikke opfylder filteret, sendes aldrig."""
    e = eksport()
    e["personer"]["2"]["titel"] = "Hemmelig Titel"
    bidder, noegle = mg.byg_input(e)
    felt = {f["ref"]: f for f in _alle_forslag(bidder)}
    assert felt["p1-f4"]["vaerdi"] == "Kammerherre" and "databasen" not in felt["p1-f4"]
    assert "Hemmelig Titel" not in json.dumps(bidder, ensure_ascii=False)
    assert bidder[0]["poster"][0]["uden_db"] == 1
    assert "manuel" not in json.dumps(noegle)


def test_databasevaerdi_kun_for_kontrolfelter_og_bundne():
    bidder, _ = mg.byg_input(eksport())
    felt = {f["vaerdi"]: f for f in _alle_forslag(bidder)}
    assert felt["Testperson Alfa"]["databasen"] == "Testperson Alfa"
    assert felt["1801"]["databasen"] == "1801"
    assert "databasen" not in felt["Teststed"]          # sted-forslag
    assert "databasen" not in felt["Ubunden Beta"]      # ubundet persona


def test_ingen_interne_id_i_bidder():
    bidder, _ = mg.byg_input(eksport())
    tekst = json.dumps(bidder, ensure_ascii=False)
    assert not re.search(v2.UUID, tekst)
    assert "person_id" not in tekst and "R-1" not in tekst


@pytest.mark.parametrize("over", [
    {"narrativ": _narrativ(1, "x", tilladte=("withdraw",))},
    {"narrativ": _narrativ(1, "x", status="stale_published", tilladte=("revalidate", "withdraw"))},
    {"narrativ": _narrativ(1, "x", tilladte=(), blokeret="NARRATIVE_RECORD_ACTIVE_BINDING_CONFLICT")},
])
def test_kun_rapport_uden_publish_revision(over):
    bidder, noegle = mg.byg_input(eksport(**over))
    assert bidder[0]["poster"][0]["kun_rapport"] is True
    assert noegle["p1"]["skrivbar"] is False


def test_kun_rapport_legacy_med_egen_tekst():
    legacy = {"person_id": 1, "legacy_ref": "dddddddd-0000-4000-8000-000000000001", "narrative_id": 10,
              "tekst": "Legacy-tekst om Alfa."}
    bidder, noegle = mg.byg_input(eksport(narrativ=None, legacy=legacy))
    post = bidder[0]["poster"][0]
    assert post["tekst"] == "Legacy-tekst om Alfa." and post["tekstkilde"] == "legacy" and post["kun_rapport"] is True
    assert noegle["p1"]["legacy_ref"] == legacy["legacy_ref"] and noegle["p1"]["skrivbar"] is False


def test_skrivbar_publiceret_med_publish_revision():
    bidder, noegle = mg.byg_input(eksport())
    assert bidder[0]["poster"][0]["kun_rapport"] is False and noegle["p1"]["skrivbar"] is True
    assert bidder[0]["poster"][1]["tekstkilde"] == "ocr" and bidder[0]["poster"][1]["kun_rapport"] is True


def test_noegle_baerer_person_og_kilde():
    _, noegle = mg.byg_input(eksport())
    p = noegle["p1"]
    assert p["type"] == "post" and p["person_id"] == 1 and p["source_id"] == 3 and p["record_key"] == "R-1"
    assert p["state_sha256"] == "c" * 64
    assert p["tekst_sha256"] == hashlib.sha256("Testperson Alfa, f. 1801, død 1870.".encode()).hexdigest()
    assert noegle["p1-f1"] == {"type": "forslag", "interpretation_id": "aaaaaaaa-0000-4000-8000-000000000001",
                               "version": 1}


def test_bidder_deles_efter_antal_poster():
    e = eksport()
    e["poster"] = e["poster"] * 30   # 60 poster
    bidder, noegle = mg.byg_input(e, bid=25)
    assert [len(b["poster"]) for b in bidder] == [25, 25, 10]
    assert bidder[2]["poster"][-1]["post"] == "p60" and "p60" in noegle


def test_vaelg_sider_altid_forekomst_og_belagt_nabo():
    post = {f"ord{i}" for i in range(10)}
    sideord = {9: {"ord0"}, 10: set(), 11: {"ord0", "ord1"}}.get
    assert mg.vaelg_sider([10], post, lambda s: sideord(s) or set(), set()) == [10, 11]   # 9: 10 %, 11: 20 %
    alle = lambda s: post  # noqa: E731
    assert mg.vaelg_sider([10, 11, 12, 13], post, alle, set()) == [10, 11, 12, 13]   # max 4
    assert mg.vaelg_sider([10], post, alle, post) == [10]      # kun almindelige ord: ingen belæg


def test_cli_printer_kun_tal(tmp_path, monkeypatch, capsys):
    f = tmp_path / "eksport.json"
    f.write_text(json.dumps(eksport()), encoding="utf-8")
    ud = tmp_path / "ud"

    def falsk_render(pdf, side, mappe):
        p = Path(mappe) / f"s{side}.png"
        p.write_bytes(b"png")
        return p

    monkeypatch.setattr(mg, "render_side", falsk_render)
    monkeypatch.setattr(mg, "sideord_fra_pdf", lambda pdf, side: set())
    assert mg.main(["input", "--eksport", str(f), "--pdf", str(tmp_path / "bog.pdf"), "--ud", str(ud)]) == 0
    out = capsys.readouterr().out.strip()
    assert re.fullmatch(r"MG_INPUT_OK( [a-z_]+=[0-9]+)+", out), out
    assert "poster=2" in out and "uden_db=1" in out and "forslag=5" in out
    assert (ud / "input-1.json").exists() and (ud / "noegle.json").exists() and (ud / "sider" / "s10.png").exists()
    for p in [ud / "input-1.json", ud / "noegle.json"]:
        assert p.stat().st_mode & 0o077 == 0
    bid = json.loads((ud / "input-1.json").read_text(encoding="utf-8"))
    assert bid["poster"][0]["sider"] == ["s10.png"]


# --- Task 4: brief-skabelon og fail-closed sammenlægning --------------------------------------------------------

SKABELON = HERE / "model_gennemgang_brief.md"
A_REFS = ["p1-f1", "p1-f2", "p1-f3", "p1-f4", "p1-f5"]   # p1-f4: person 2 er ikke sikker -> uden databasen


def _a(ref, svar="OK", billede="bekraefter", laesning=None):
    return {"ref": ref, "svar": svar, "bogens_laesning": laesning, "billede": billede, "grund": "g"}


def _r(fra, til, art="ocr", billede="bekraefter", rammer=()):
    return {"fra": fra, "til": til, "art": art, "billede": billede, "rammer_forslag": list(rammer), "grund": "g"}


def _b(post, rettelser=(), billede="bekraefter", manglende=0):
    return {"post": post, "billede": billede, "rettelser": list(rettelser), "manglende_fakta": manglende}


def _skriv(tmp_path, a, b, navn="1"):
    fa, fb = tmp_path / f"svar-A-{navn}.json", tmp_path / f"svar-B-{navn}.json"
    fa.write_text(json.dumps(a), encoding="utf-8")
    fb.write_text(json.dumps(b), encoding="utf-8")
    return [fa], [fb]


def _saml(tmp_path, a=None, b=None, e=None):
    bidder, noegle = mg.byg_input(e or eksport())
    a = [_a(r) for r in A_REFS] if a is None else a
    b = [_b("p1"), _b("p2")] if b is None else b
    fa, fb = _skriv(tmp_path, a, b)
    return mg.saml(bidder, noegle, fa, fb)


def _kode_af(fn):
    with pytest.raises(mg.GennemgangError) as e:
        fn()
    return str(e.value)


def test_saml_alt_ok(tmp_path):
    s = _saml(tmp_path)
    t = s["taelling"]
    assert (t["a_ok"], t["a_markeret"], t["b_poster_ok"], t["b_rettelser"]) == (5, 0, 2, 0)
    assert t["over_taerskel"] == 0 and re.fullmatch(r"[0-9a-f]{64}", s["manifest_sha256"])


def test_saml_svar_dublet(tmp_path):
    a = [_a(r) for r in A_REFS] + [_a("p1-f1")]
    assert _kode_af(lambda: _saml(tmp_path, a=a)) == "SVAR_DUBLET"
    assert _kode_af(lambda: _saml(tmp_path, b=[_b("p1"), _b("p2"), _b("p2")])) == "SVAR_DUBLET"


def test_saml_svar_mangler(tmp_path):
    assert _kode_af(lambda: _saml(tmp_path, a=[_a(r) for r in A_REFS[:-1]])) == "SVAR_MANGLER"
    assert _kode_af(lambda: _saml(tmp_path, b=[_b("p1")])) == "SVAR_MANGLER"


def test_saml_svar_ukendt_ref(tmp_path):
    assert _kode_af(lambda: _saml(tmp_path, a=[_a(r) for r in A_REFS] + [_a("p9-f1")])) == "SVAR_UKENDT_REF"
    b = [_b("p1", [_r("f. 1801", "f. 1802", rammer=["p2-f1"])]), _b("p2")]
    assert _kode_af(lambda: _saml(tmp_path, b=b)) == "SVAR_UKENDT_REF"


@pytest.mark.parametrize("a_svar", [
    _a("p1-f1", svar="MAASKE"),
    _a("p1-f1", svar="FORSLAG_FEJL"),                       # mangler bogens_laesning
    _a("p1-f3", svar="DB_FEJL"),                            # sted-forslag har ingen databaseværdi
    _a("p1-f1", billede="maaske"),
])
def test_saml_svar_ugyldigt_a(tmp_path, a_svar):
    a = [a_svar] + [_a(r) for r in A_REFS if r != a_svar["ref"]]
    assert _kode_af(lambda: _saml(tmp_path, a=a)) == "SVAR_UGYLDIGT"


@pytest.mark.parametrize("rettelse", [
    _r("f. 1801", "f. 1802", art="stavning"),
    _r("", "x"),
    _r("f. 1801", "f. 1802", billede="ikke_fundet"),
])
def test_saml_svar_ugyldigt_b(tmp_path, rettelse):
    assert _kode_af(lambda: _saml(tmp_path, b=[_b("p1", [rettelse]), _b("p2")])) == "SVAR_UGYLDIGT"


def test_saml_rettelse_ikke_entydig(tmp_path):
    assert _kode_af(lambda: _saml(tmp_path, b=[_b("p1", [_r("findes ikke", "x")]), _b("p2")])) \
        == "RETTELSE_IKKE_ENTYDIG"
    assert _kode_af(lambda: _saml(tmp_path, b=[_b("p1", [_r("18", "19")]), _b("p2")])) == "RETTELSE_IKKE_ENTYDIG"


def test_saml_rettelse_overlapper(tmp_path):
    b = [_b("p1", [_r("f. 1801", "f. 1802"), _r("1801, død", "1801, d.")]), _b("p2")]
    assert _kode_af(lambda: _saml(tmp_path, b=b)) == "RETTELSE_OVERLAPPER"


def test_saml_ikke_fundet_kraever_tvivl(tmp_path):
    a = [_a("p1-f1", svar="FORSLAG_FEJL", billede="ikke_fundet", laesning="Testperson Alpha")] + \
        [_a(r) for r in A_REFS[1:]]
    assert _kode_af(lambda: _saml(tmp_path, a=a)) == "BILLEDSTOETTE_MANGLER"
    # posten står ikke på billedet, men rettelsen påstår billedstøtte
    b = [_b("p1", [_r("f. 1801", "f. 1802")], billede="ikke_fundet"), _b("p2")]
    assert _kode_af(lambda: _saml(tmp_path, b=b)) == "BILLEDSTOETTE_MANGLER"
    # TVIVL uden billede er gyldigt, og en tvivlsrettelse ligeså
    a = [_a("p1-f1", svar="TVIVL", billede="ikke_fundet")] + [_a(r) for r in A_REFS[1:]]
    b = [_b("p1", [_r("f. 1801", "f. 1802", billede="tvivl")], billede="ikke_fundet"), _b("p2")]
    s = _saml(tmp_path, a=a, b=b)
    assert s["taelling"]["tvivl"] == 2


def test_saml_beregner_interval_og_manifest(tmp_path):
    b = [_b("p1", [_r("død 1870", "d. 1870", rammer=["p1-f2"])]), _b("p2", [_r("Gamma,", "Gamma ,", art="graense")])]
    s1 = _saml(tmp_path, b=b)
    tekst = "Testperson Alfa, f. 1801, død 1870."
    r = s1["B"][0]
    assert r["ref"] == "p1-r1" and tekst[r["start"]:r["slut"]] == "død 1870"
    assert _saml(tmp_path, b=b)["manifest_sha256"] == s1["manifest_sha256"]
    b[0]["rettelser"][0]["til"] = "d. 1871"
    assert _saml(tmp_path, b=b)["manifest_sha256"] != s1["manifest_sha256"]
    assert s1["taelling"]["graense"] == 1 and s1["taelling"]["b_grupper"] == 1


def test_grupper_b_samler_samme_ocr_par():
    b = [{"ref": f"p{i}-r1", "post": f"p{i}", "art": "ocr", "fra": "rn", "til": "m", "kun_rapport": False,
          "billede": "bekraefter"} for i in (1, 2, 3)]
    b.append({"ref": "p4-r1", "post": "p4", "art": "mangler", "fra": "a", "til": "ab", "kun_rapport": False})
    b.append({"ref": "p5-r1", "post": "p5", "art": "graense", "fra": "x", "til": "y", "kun_rapport": False})
    b.append({"ref": "p6-r1", "post": "p6", "art": "ocr", "fra": "rn", "til": "m", "kun_rapport": True})
    g = mg.grupper_b(b)
    assert sorted(len(x["elementer"]) for x in g) == [1, 3]
    assert {"p1-r1", "p2-r1", "p3-r1"} in [set(x["elementer"]) for x in g]


def test_grupper_a_samler_samme_forslagsfejl():
    a = [{"ref": f"p{i}-f1", "svar": "FORSLAG_FEJL", "felt": "person.title", "vaerdi": "Kammerjunkcr",
          "bogens_laesning": "Kammerjunker"} for i in (1, 2)]
    a.append({"ref": "p3-f1", "svar": "DB_FEJL", "felt": "person.title", "vaerdi": "x", "bogens_laesning": None})
    a.append({"ref": "p4-f1", "svar": "OK", "felt": "person.title", "vaerdi": "x", "bogens_laesning": None})
    assert sorted(len(x["elementer"]) for x in mg.grupper_a(a)) == [1, 2]


def test_taerskel_300_over_begge_spor():
    assert mg.over_taerskel(200, 101) is True
    assert mg.over_taerskel(200, 100) is False


def test_cli_saml_exit_3_over_taerskel(tmp_path, monkeypatch, capsys):
    bidder, noegle = mg.byg_input(eksport())
    for b in bidder:
        mg._skriv_json(tmp_path / f"input-{b['bid']}.json", b)
    mg._skriv_json(tmp_path / "noegle.json", noegle)
    a = [_a("p1-f1", svar="TVIVL")] + [_a(r) for r in A_REFS[1:]]
    _skriv(tmp_path, a, [_b("p1"), _b("p2")])
    assert mg.main(["saml", "--ud", str(tmp_path)]) == 0
    out = capsys.readouterr().out.strip()
    assert re.fullmatch(r"MG_SAML_OK( [a-z_]+=[0-9]+)+ manifest=[0-9a-f]{8}", out), out
    assert "over_taerskel=0" in out and (tmp_path / "samlet.json").stat().st_mode & 0o077 == 0
    monkeypatch.setattr(mg, "TAERSKEL", 0)
    (tmp_path / "samlet.json").unlink()
    assert mg.main(["saml", "--ud", str(tmp_path)]) == 3
    assert "over_taerskel=1" in capsys.readouterr().out


def test_cli_saml_kraever_svarfil_pr_bid(tmp_path, capsys):
    bidder, noegle = mg.byg_input(eksport())
    mg._skriv_json(tmp_path / "input-1.json", bidder[0])
    mg._skriv_json(tmp_path / "noegle.json", noegle)
    (tmp_path / "svar-A-1.json").write_text("[]", encoding="utf-8")
    assert mg.main(["saml", "--ud", str(tmp_path)]) == 2
    assert "SVAR_MANGLER" in capsys.readouterr().err


def test_skabelon_naevner_alle_svarvaerdier():
    t = SKABELON.read_text(encoding="utf-8")
    for v in ["OK", "FORSLAG_FEJL", "DB_FEJL", "BEGGE", "TVIVL", "bekraefter", "modsiger", "ikke_fundet", "tvivl",
              "ocr", "orddeling", "mangler", "overskydende", "graense", "manglende_fakta", "rammer_forslag"]:
        assert f'"{v}"' in t or f"`{v}`" in t, v
    assert "sidebillede" in t
    assert "Dit svar til sessionen er kun antal" in t
    for felt in ["{INPUT}", "{SVAR_A}", "{SVAR_B}", "{SIDER}"]:
        assert felt in t


def test_skriv_briefs_indsaetter_stier(tmp_path):
    stier = mg.skriv_briefs(SKABELON.read_text(encoding="utf-8"), tmp_path, 2)
    assert [p.name for p in stier] == ["brief-1.md", "brief-2.md"]
    t = stier[1].read_text(encoding="utf-8")
    assert str(tmp_path / "input-2.json") in t and str(tmp_path / "svar-B-2.json") in t
    assert "{INPUT}" not in t and stier[1].stat().st_mode & 0o077 == 0


# --- review-fund efter Task 6: billedstøtte og tvivl holdes adskilt ---------------------------------------------

def test_saml_ok_kraever_billedstoette(tmp_path):
    for billede in ("modsiger", "ikke_fundet"):
        a = [_a("p1-f1", billede=billede)] + [_a(r) for r in A_REFS[1:]]
        assert _kode_af(lambda: _saml(tmp_path, a=a)) == "BILLEDSTOETTE_MANGLER"


def test_saml_post_uden_rettelser_ikke_fundet_er_uverificeret(tmp_path):
    s = _saml(tmp_path, b=[_b("p1", billede="ikke_fundet"), _b("p2")])
    assert s["taelling"]["b_poster_ok"] == 1 and s["taelling"]["b_poster_uverificeret"] == 1
    assert {x["post"]: x["billede"] for x in s["B_poster"]} == {"p1": "ikke_fundet", "p2": "bekraefter"}
    # modsiger uden en eneste rettelse er selvmodsigende
    assert _kode_af(lambda: _saml(tmp_path, b=[_b("p1", billede="modsiger"), _b("p2")])) == "SVAR_UGYLDIGT"


def test_saml_post_uden_sidebilleder_kan_ikke_bekraefte(tmp_path):
    e = eksport(placering=[])                     # p1 har ingen sider
    a = [_a(r, svar="TVIVL", billede="ikke_fundet") for r in A_REFS]
    b = [_b("p1", billede="ikke_fundet"), _b("p2")]
    assert _saml(tmp_path, a=a, b=b, e=e)["taelling"]["b_poster_uverificeret"] == 1
    assert _kode_af(lambda: _saml(tmp_path, a=[_a("p1-f1", svar="BEGGE")] + a[1:], b=b, e=e)) \
        == "BILLEDSTOETTE_MANGLER"
    assert _kode_af(lambda: _saml(tmp_path, a=a, b=[_b("p1"), _b("p2")], e=e)) == "BILLEDSTOETTE_MANGLER"


def test_grupper_b_holder_tvivl_for_sig():
    """Tvivlsrettelser grupperes aldrig, heller ikke med hinanden: hver kræver sit eget klik (Opus 2)."""
    b = [{"ref": f"p{i}-r1", "post": f"p{i}", "art": "ocr", "fra": "rn", "til": "m", "kun_rapport": False,
          "billede": "tvivl" if i >= 3 else "bekraefter"} for i in (1, 2, 3, 4)]
    g = mg.grupper_b(b)
    assert sorted(sorted(x["elementer"]) for x in g) == [["p1-r1", "p2-r1"], ["p3-r1"], ["p4-r1"]]
    assert {x["billede"] for x in g} == {"bekraefter", "tvivl"}


def test_manifest_binder_postens_identitet_og_tekst(tmp_path):
    """Samme stump på samme ref i en anden post (anden record_key/tekst) giver et andet manifest (Codex 1)."""
    b = [_b("p1", [_r("død 1870", "d. 1870")]), _b("p2")]
    s1 = _saml(tmp_path, b=b)
    assert s1["B"][0]["record_key"] == "R-1" and re.fullmatch(r"[0-9a-f]{64}", s1["B"][0]["tekst_sha256"])
    e = eksport()
    e["poster"][0]["record_key"] = "R-99"
    assert _saml(tmp_path, b=b, e=e)["manifest_sha256"] != s1["manifest_sha256"]


@pytest.mark.parametrize("til", ["d.\u200b 1870", "d. 1870\x07", "d.\u202e 1870"])
def test_saml_afviser_usynlige_tegn_i_til(tmp_path, til):
    b = [_b("p1", [_r("død 1870", til.encode().decode("unicode_escape"))]), _b("p2")]
    assert _kode_af(lambda: _saml(tmp_path, b=b)) == "SVAR_UGYLDIGT"


def test_saml_begge_kraever_databasevaerdi(tmp_path):
    a = [_a("p1-f3", svar="BEGGE")] + [_a(r) for r in A_REFS if r != "p1-f3"]   # sted-forslag: ingen databasen
    assert _kode_af(lambda: _saml(tmp_path, a=a)) == "SVAR_UGYLDIGT"


def test_cli_saml_pilot_paa_een_bid(tmp_path, capsys):
    """Piloten (Task 8 step 1): kun bid k samles, til samlet-pilot-<k>.json; den fulde saml kan køre bagefter."""
    e = eksport()
    e["poster"] = e["poster"][1:] * 2          # to poster uden forslag, to bidder à 1
    bidder, noegle = mg.byg_input(e, bid=1)
    for b in bidder:
        mg._skriv_json(tmp_path / f"input-{b['bid']}.json", b)
    mg._skriv_json(tmp_path / "noegle.json", noegle)
    for k, post in ((1, "p1"), (2, "p2")):
        (tmp_path / f"svar-A-{k}.json").write_text("[]", encoding="utf-8")
        (tmp_path / f"svar-B-{k}.json").write_text(json.dumps([_b(post)]), encoding="utf-8")
    (tmp_path / "svar-B-2.json").unlink()
    assert mg.main(["saml", "--ud", str(tmp_path), "--bid", "1"]) == 0
    assert "b_poster_ok=1" in capsys.readouterr().out
    assert (tmp_path / "samlet-pilot-1.json").exists() and not (tmp_path / "samlet.json").exists()
    (tmp_path / "svar-B-2.json").write_text(json.dumps([_b("p2")]), encoding="utf-8")
    assert mg.main(["saml", "--ud", str(tmp_path)]) == 0
    assert "b_poster_ok=2" in capsys.readouterr().out


@pytest.mark.parametrize("til", ["d.  1870", "d.ㅤ 1870", "d.  1870", "d.͏ 1870", "d. 1870"])
def test_saml_afviser_flere_usynlige_tegn(tmp_path, til):
    """Linjeseparator, fyldtegn, hårdt mellemrum, ignorerbare mærker og private tegn kan ikke ses på kortet."""
    b = [_b("p1", [_r("død 1870", til)]), _b("p2")]
    assert _kode_af(lambda: _saml(tmp_path, b=b)) == "SVAR_UGYLDIGT"


def test_saml_tillader_usynligt_tegn_der_allerede_staar_i_teksten(tmp_path):
    """Et hårdt mellemrum, der står i den nuværende tekst (OCR), må blive stående i rettelsen."""
    e = eksport()
    e["poster"][0]["narrativ"]["tekst"] = "Testperson Alfa, f. 1801, død 1870."
    b = [_b("p1", [_r("død 1870", "d. 1870")]), _b("p2")]
    assert _saml(tmp_path, b=b, e=e)["B"][0]["til"] == "d. 1870"


def test_saml_usynlige_tegn_taelles_og_styretegn_er_altid_forbudt(tmp_path):
    """Et tegn fra den nuværende tekst må ikke mangfoldiggøres, og styre-/formattegn afvises, selv om de står i fra."""
    e = eksport()
    e["poster"][0]["narrativ"]["tekst"] = "Testperson Alfa, f. 1801, død 1870‮."
    to_nbsp = [_b("p1", [_r("død 1870", "d.  1870")]), _b("p2")]
    assert _kode_af(lambda: _saml(tmp_path, b=to_nbsp, e=e)) == "SVAR_UGYLDIGT"
    bidi = [_b("p1", [_r("død 1870‮", "d. 1870‮")]), _b("p2")]
    assert _kode_af(lambda: _saml(tmp_path, b=bidi, e=e)) == "SVAR_UGYLDIGT"
