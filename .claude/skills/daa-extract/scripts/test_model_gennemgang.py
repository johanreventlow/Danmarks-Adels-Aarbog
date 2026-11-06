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
    assert kode[0].strip() == "BEGIN;" and kode[1].strip() == "SET TRANSACTION READ ONLY;"
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


def test_forslag_om_usikker_person_gaar_uden_modelforslag():
    bidder, noegle = mg.byg_input(eksport())
    post = bidder[0]["poster"][0]
    assert "Kammerherre" not in json.dumps(bidder, ensure_ascii=False)
    assert post["manuelle_forslag"] == 1
    manuelle = [v for v in noegle.values() if v["type"] == "forslag" and v.get("manuel")]
    assert len(manuelle) == 1 and manuelle[0]["interpretation_id"].endswith("000000000004")


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
                               "version": 1, "manuel": False}


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
    assert "poster=2" in out and "manuelle=1" in out and "forslag=4" in out
    assert (ud / "input-1.json").exists() and (ud / "noegle.json").exists() and (ud / "sider" / "s10.png").exists()
    for p in [ud / "input-1.json", ud / "noegle.json"]:
        assert p.stat().st_mode & 0o077 == 0
    bid = json.loads((ud / "input-1.json").read_text(encoding="utf-8"))
    assert bid["poster"][0]["sider"] == ["s10.png"]
