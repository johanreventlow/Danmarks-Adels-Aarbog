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
