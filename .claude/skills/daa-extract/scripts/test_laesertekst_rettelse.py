"""Tests til laesertekst_rettelse.py (trin 6m del 1, Task 5-6): B-kort, flet og ceremoniens SQL. Kun syntetiske data."""
from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

import laesertekst_rettelse as lt
import model_gennemgang as mg

HERE = Path(__file__).parent
RID = "11111111-1111-4111-8111-111111111111"
TEKST = {1: "Alfa blev Kammerjunkcr 1820.", 2: "Beta blev Kammerjunkcr 1830, død 1890. Næste",
         3: "Gamma blev Kammerjunkcr 1840."}


def _post(n: int, tilladte=("publish_revision", "withdraw")) -> dict:
    t = TEKST[n]
    return {"record_key": f"R-{n}", "legacy": None, "forslag": [],
            "narrativ": {"person_id": n, "narrative_id": n * 10, "tekst": t, "status": "published", "blokeret": None,
                         "tilladte": list(tilladte), "state_sha256": f"{n}" * 64},
            "placering": [{"side_fra": 10 + n, "side_til": 10 + n, "fra": n * 100, "til": n * 100 + len(t),
                           "rendition_id": RID, "stykker": [{"f": n * 100, "t": t}]}]}


def _r(fra, til, art="ocr", billede="bekraefter"):
    return {"fra": fra, "til": til, "art": art, "billede": billede, "rammer_forslag": [], "grund": "g"}


def opsaet(tmp_path, b_svar=None):
    """p1, p2 skrivbare; p3 kun_rapport. Samme OCR-par på alle tre; p2 har desuden en grænserettelse."""
    eksport = {"udgave": "Testudgave", "source_id": 3, "personer": {},
               "poster": [_post(1), _post(2), _post(3, tilladte=("withdraw",))]}
    bidder, noegle = mg.byg_input(eksport)
    b_svar = b_svar or [
        {"post": "p1", "billede": "bekraefter", "manglende_fakta": 0, "rettelser": [_r("Kammerjunkcr", "Kammerjunker")]},
        {"post": "p2", "billede": "bekraefter", "manglende_fakta": 0,
         "rettelser": [_r("Kammerjunkcr", "Kammerjunker"), _r("1890. Næste", "1890.", art="graense")]},
        {"post": "p3", "billede": "bekraefter", "manglende_fakta": 0, "rettelser": [_r("Kammerjunkcr", "Kammerjunker")]}]
    fa, fb = tmp_path / "svar-A-1.json", tmp_path / "svar-B-1.json"
    fa.write_text("[]", encoding="utf-8")
    fb.write_text(json.dumps(b_svar), encoding="utf-8")
    samlet = mg.saml(bidder, noegle, [fa], [fb])
    return bidder, noegle, samlet


def _svarfil(samlet, grupper=None, elementer=None):
    return {"manifest_sha256": samlet["manifest_sha256"], "side": 1,
            "svar": {"grupper": grupper or {}, "elementer": elementer or {}}}


def _kode_af(fn):
    with pytest.raises(mg.GennemgangError) as e:
        fn()
    return str(e.value)


# --- Task 5: kort og flet ------------------------------------------------------------------------------------------

def test_byg_kort_grupper_og_rapport(tmp_path):
    bidder, _, samlet = opsaet(tmp_path)
    kort = lt.byg_kort(samlet, bidder)
    gruppe = [k for k in kort if k["type"] == "gruppe"]
    rapport = [k for k in kort if k["type"] == "rapport"]
    assert len(gruppe) == 1 and [e["ref"] for e in gruppe[0]["elementer"]] == ["p1-r1", "p2-r1"]
    assert all(e["svarbar"] for e in gruppe[0]["elementer"])
    assert sorted(e["ref"] for k in rapport for e in k["elementer"]) == ["p2-r2", "p3-r1"]
    assert not any(e["svarbar"] for k in rapport for e in k["elementer"])
    e = gruppe[0]["elementer"][0]
    assert e["foer"] + e["fra"] + e["efter"] == TEKST[1]
    assert e["sider"] == ["../sider/s11.png"]


def test_kort_er_ikke_forudfyldt(tmp_path):
    bidder, _, samlet = opsaet(tmp_path)
    sider = lt.render(lt.byg_kort(samlet, bidder), samlet["manifest_sha256"])
    assert len(sider) == 1
    html = sider[0]
    assert not re.search(r"\b(checked|selected)\b", html)
    assert samlet["manifest_sha256"] in html
    data = json.loads(re.search(r"const DATA = (\{.*?\});\n", html, re.S).group(1))
    noegler = {n for k in data["kort"] for n in k} | {n for k in data["kort"] for e in k["elementer"] for n in e}
    assert not noegler & {"svar", "tok", "token", "valgt"}     # intet forvalgt svar i dataene


def test_graense_og_kun_rapport_har_ingen_knapper(tmp_path):
    bidder, _, samlet = opsaet(tmp_path)
    html = lt.render(lt.byg_kort(samlet, bidder), samlet["manifest_sha256"])[0]
    # knapperne bygges kun for svarbare elementer, og rapportkortene forklarer hvorfor
    assert "if (e.svarbar)" in html
    assert "parkeres til 6d" in html and "rettes ikke her" in html


def test_vejledning_definerer_hvert_svar(tmp_path):
    bidder, _, samlet = opsaet(tmp_path)
    html = lt.render(lt.byg_kort(samlet, bidder), samlet["manifest_sha256"])[0]
    for tegn in ["<b>L</b>", "<b>K</b>", "<b>N</b>", "<b>tomt</b>"]:
        assert tegn in html
    assert "er du i tvivl, så lad den stå tom" in html.lower()


def test_render_deler_i_sider(tmp_path):
    bidder, _, samlet = opsaet(tmp_path)
    assert len(lt.render(lt.byg_kort(samlet, bidder), samlet["manifest_sha256"], pr_side=1)) == 3


def test_flet_gruppesvar_med_undtagelse(tmp_path):
    _, _, samlet = opsaet(tmp_path)
    ark = lt.flet_b(samlet, [_svarfil(samlet, {"bg1": "L"}, {"p2-r1": "N"})])
    assert ark.splitlines() == [f"# manifest {samlet['manifest_sha256']}", "R p1-r1 : L", "R p2-r1 : N"]


def test_flet_ubesvaret_er_tom(tmp_path):
    _, _, samlet = opsaet(tmp_path)
    ark = lt.flet_b(samlet, [_svarfil(samlet, {}, {"p1-r1": "K"})])
    assert ark.splitlines()[1:] == ["R p1-r1 : K", "R p2-r1 : _"]


def test_flet_afviser_andet_manifest(tmp_path):
    _, _, samlet = opsaet(tmp_path)
    s = _svarfil(samlet, {"bg1": "L"})
    s["manifest_sha256"] = "0" * 64
    assert _kode_af(lambda: lt.flet_b(samlet, [s])) == "MANIFEST_MISMATCH"


def test_flet_afviser_forbudte_svar(tmp_path):
    _, _, samlet = opsaet(tmp_path)
    assert _kode_af(lambda: lt.flet_b(samlet, [_svarfil(samlet, {}, {"p9-r1": "L"})])) == "SVAR_UKENDT_REF"
    assert _kode_af(lambda: lt.flet_b(samlet, [_svarfil(samlet, {"bg9": "L"})])) == "SVAR_UKENDT_REF"
    assert _kode_af(lambda: lt.flet_b(samlet, [_svarfil(samlet, {}, {"p2-r2": "L"})])) == "SVAR_IKKE_TILLADT"
    assert _kode_af(lambda: lt.flet_b(samlet, [_svarfil(samlet, {}, {"p3-r1": "K"})])) == "SVAR_IKKE_TILLADT"
    assert _kode_af(lambda: lt.flet_b(samlet, [_svarfil(samlet, {"bg1": "X"})])) == "SVAR_UGYLDIGT"
    to = [_svarfil(samlet, {}, {"p1-r1": "L"}), _svarfil(samlet, {}, {"p1-r1": "N"})]
    assert _kode_af(lambda: lt.flet_b(samlet, to)) == "SVAR_KONFLIKT"
    ens = [_svarfil(samlet, {}, {"p1-r1": "L"}), _svarfil(samlet, {}, {"p1-r1": "L"})]
    assert lt.flet_b(samlet, ens).splitlines()[1] == "R p1-r1 : L"


def _cli_mappe(tmp_path):
    bidder, noegle, samlet = opsaet(tmp_path)
    for b in bidder:
        mg._skriv_json(tmp_path / f"input-{b['bid']}.json", b)
    mg._skriv_json(tmp_path / "noegle.json", noegle)
    mg._skriv_json(tmp_path / "samlet.json", samlet)
    return samlet


def test_cli_kort_og_flet(tmp_path, capsys):
    samlet = _cli_mappe(tmp_path)
    assert lt.main(["kort", "--ud", str(tmp_path)]) == 0
    out = capsys.readouterr().out.strip()
    assert re.fullmatch(r"LT_KORT_OK( [a-z_]+=[0-9a-f]+)+", out), out
    assert (tmp_path / "kort-b" / "kort-1.html").stat().st_mode & 0o077 == 0
    sv = tmp_path / "svar.json"
    sv.write_text(json.dumps(_svarfil(samlet, {"bg1": "L"})), encoding="utf-8")
    assert lt.main(["flet", "--ud", str(tmp_path), str(sv)]) == 0
    out = capsys.readouterr().out.strip()
    assert re.fullmatch(r"LT_FLET_OK L=2 K=0 N=0 ubesvaret=0 ark_sha256=[0-9a-f]{64}", out), out


def test_flet_ark_findes(tmp_path, capsys):
    samlet = _cli_mappe(tmp_path)
    sv = tmp_path / "svar.json"
    sv.write_text(json.dumps(_svarfil(samlet, {"bg1": "L"})), encoding="utf-8")
    assert lt.main(["flet", "--ud", str(tmp_path), str(sv)]) == 0
    assert lt.main(["flet", "--ud", str(tmp_path), str(sv)]) == 2
    assert "ARK_FINDES" in capsys.readouterr().err


# --- Task 6: ceremoniens SQL og verifikation ----------------------------------------------------------------------

def _anvendt(tmp_path, grupper=None, elementer=None, b_svar=None):
    bidder, noegle, samlet = opsaet(tmp_path, b_svar)
    ark = lt.flet_b(samlet, [_svarfil(samlet, grupper if grupper is not None else {"bg1": "L"}, elementer)])
    return bidder, noegle, samlet, ark


def test_anvend_retter_teksten_og_binder_state(tmp_path):
    bidder, noegle, samlet, ark = _anvendt(tmp_path)
    a = lt.anvend(bidder, noegle, samlet, ark)
    assert [p["record_key"] for p in a["poster"]] == ["R-1", "R-2"]
    p1 = a["poster"][0]
    assert p1["efter_tekst"] == "Alfa blev Kammerjunker 1820." and p1["rettelser"] == 1
    assert p1["state_sha256"] == "1" * 64 and p1["person_id"] == 1
    assert p1["foer_sha256"] == mg._sha(TEKST[1].encode()) and p1["efter_sha256"] == mg._sha(p1["efter_tekst"].encode())
    assert [g["record_key"] for g in a["graense"]] == ["R-2"]


def test_sql_b_bruger_eksportens_state_sha(tmp_path):
    a = lt.anvend(*_anvendt(tmp_path))
    sql = lt.sql_b(a, 3)
    kald = [l for l in sql.splitlines() if "red_revider_publiceret_person_narrative_record(" in l]
    assert len(kald) == 2
    assert "'" + "1" * 64 + "'" in kald[0] and "'" + "2" * 64 + "'" in kald[1]
    assert kald[0].startswith("SELECT public.red_revider_publiceret_person_narrative_record(1, 3, 'R-1', ")
    assert sql.index("BEGIN;") < sql.index("request.jwt.claim.sub") < sql.index(kald[0]) < sql.index("COMMIT;")
    assert "SET LOCAL ROLE authenticated;" in sql and "ON_ERROR_STOP on" in sql


def test_sql_b_nulstiller_change_set_mellem_kald(tmp_path):
    sql = lt.sql_b(lt.anvend(*_anvendt(tmp_path)), 3)
    assert sql.count("set_config('app.change_set_id'") == sql.count("red_revider_publiceret_person_narrative_record(")


def test_sql_b_citerer_apostrof():
    a = {"source_id": 3, "poster": [{"record_key": "R-1", "person_id": 1, "state_sha256": "a" * 64,
                                     "efter_tekst": "O'Neill og \\n", "efter_sha256": "x", "rettelser": 1}]}
    sql = lt.sql_b(a, 3)
    assert "'O''Neill og \\n'" in sql and "E'" not in sql
    kald = [l for l in sql.splitlines() if "red_revider" in l][0]
    assert kald.replace("''", "").count("'") % 2 == 0


def test_anvend_afviser_overlap_mod_aktuel_tekst(tmp_path):
    bidder, noegle, samlet = opsaet(tmp_path)
    # en ekstra rettelse, der overlapper p1-r1, smugles ind efter saml; manifestet regnes om, så kun overlapvagten står
    samlet["B"].insert(1, {"ref": "p1-r2", "post": "p1", "record_key": "R-1",
                           "tekst_sha256": samlet["B"][0]["tekst_sha256"], "start": 10, "slut": 27, "fra": "Kammerjunkcr 1820",
                           "til": "Kammerjunker 1821", "art": "mangler", "billede": "bekraefter", "rammer_forslag": [],
                           "grund": "g", "kun_rapport": False})
    samlet["grupper_b"] = mg.grupper_b(samlet["B"])
    samlet["manifest_sha256"] = mg.manifest(samlet["B"], samlet["grupper_b"])
    ark = lt.flet_b(samlet, [_svarfil(samlet, {g["gruppe"]: "L" for g in samlet["grupper_b"]})])
    assert _kode_af(lambda: lt.anvend(bidder, noegle, samlet, ark)) == "RETTELSE_OVERLAPPER"


def test_k_skrives_ikke_i_del_1(tmp_path):
    a = lt.anvend(*_anvendt(tmp_path, {"bg1": "L"}, {"p1-r1": "K"}))
    assert a["poster"][0]["efter_tekst"] == "Alfa blev Kammerjunker 1820."
    assert [k["ref"] for k in a["k_sager"]] == ["p1-r1"] and a["k_sager"][0]["record_key"] == "R-1"
    sql = lt.sql_b(a, 3)
    assert "source_text" not in sql and "reimport" not in sql


def test_kun_rapport_rores_ikke(tmp_path):
    a = lt.anvend(*_anvendt(tmp_path))
    assert "R-3" not in [p["record_key"] for p in a["poster"]]
    assert "'R-3'" not in lt.sql_b(a, 3)
    assert [k["ref"] for k in a["kun_rapport"]] == ["p3-r1"]


def test_n_og_ubesvaret_rores_ikke(tmp_path):
    a = lt.anvend(*_anvendt(tmp_path, {}, {"p1-r1": "N"}))
    assert a["poster"] == []


def test_anvend_afviser_aendret_samlet(tmp_path):
    bidder, noegle, samlet, ark = _anvendt(tmp_path)
    samlet["B"][0]["til"] = "Kammerjunkerinde"
    assert _kode_af(lambda: lt.anvend(bidder, noegle, samlet, ark)) == "MANIFEST_MISMATCH"


def test_anvend_afviser_ark_med_andet_manifest(tmp_path):
    bidder, noegle, samlet, ark = _anvendt(tmp_path)
    ark = ark.replace(samlet["manifest_sha256"], "0" * 64)
    assert _kode_af(lambda: lt.anvend(bidder, noegle, samlet, ark)) == "MANIFEST_MISMATCH"


def test_anvend_afviser_ark_med_forkerte_linjer(tmp_path):
    bidder, noegle, samlet, ark = _anvendt(tmp_path)
    assert _kode_af(lambda: lt.anvend(bidder, noegle, samlet, ark + "R p3-r1 : L\n")) == "SVAR_IKKE_TILLADT"
    assert _kode_af(lambda: lt.anvend(bidder, noegle, samlet, ark + "R p9-r1 : L\n")) == "SVAR_UKENDT_REF"
    assert _kode_af(lambda: lt.anvend(bidder, noegle, samlet, "\n".join(ark.splitlines()[:-1]))) == "SVAR_MANGLER"


def test_anvend_kraever_tekst_sha(tmp_path):
    bidder, noegle, samlet, ark = _anvendt(tmp_path)
    bidder[0]["poster"][0]["tekst"] = TEKST[1] + " "
    assert _kode_af(lambda: lt.anvend(bidder, noegle, samlet, ark)) == "TEKST_DRIFT"


def test_verify_b_sql_er_laese_kun(tmp_path):
    a = lt.anvend(*_anvendt(tmp_path))
    sql = lt.verify_b_sql(a)
    assert "SET TRANSACTION READ ONLY" in sql and "ROLLBACK;" in sql
    kode = "\n".join(l for l in sql.splitlines() if not l.lstrip().startswith("--"))
    assert not re.search(r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT)\b", kode, re.I)
    for p in a["poster"]:
        assert p["efter_sha256"] in sql
    assert "VERIFY_B_AFVIGER" in sql and "source_id = 3" in sql


def test_cli_sql(tmp_path, capsys):
    samlet = _cli_mappe(tmp_path)
    sv = tmp_path / "svar.json"
    sv.write_text(json.dumps(_svarfil(samlet, {"bg1": "K"})), encoding="utf-8")
    assert lt.main(["flet", "--ud", str(tmp_path), str(sv)]) == 0
    capsys.readouterr()
    assert lt.main(["sql", "--ud", str(tmp_path)]) == 0
    out = capsys.readouterr().out.strip()
    assert re.fullmatch(r"LT_SQL_OK poster=2 rettelser=2 k_sager=2 graense=1 legacy=0 kun_rapport=1 "
                        r"sha256=[0-9a-f]{64}", out), out
    for f in ["apply-b.sql", "verify-b.sql", "k-sager.json", "graensefejl.txt", "legacy-sager.json"]:
        assert (tmp_path / f).stat().st_mode & 0o077 == 0, f
    assert (tmp_path / "graensefejl.txt").read_text(encoding="utf-8").splitlines() == ["GRÆNSEFEJL: p2-r2 R-2"]
    assert lt.main(["sql", "--ud", str(tmp_path)]) == 2
    assert "SQL_FINDES" in capsys.readouterr().err


def test_cli_sql_uden_rettelser(tmp_path, capsys):
    samlet = _cli_mappe(tmp_path)
    sv = tmp_path / "svar.json"
    sv.write_text(json.dumps(_svarfil(samlet, {"bg1": "N"})), encoding="utf-8")
    assert lt.main(["flet", "--ud", str(tmp_path), str(sv)]) == 0
    assert lt.main(["sql", "--ud", str(tmp_path)]) == 2
    assert "INGEN_RETTELSER" in capsys.readouterr().err and not (tmp_path / "apply-b.sql").exists()
