"""Review 37, E2: validatoren må ikke skrive nulevendes oplysninger til stderr.

Kun syntetiske data; work_presens/ læses aldrig (invariant 8).
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).with_name("validate_presens.py")
NAVN = "Testine Syntetisk"
DATO = "31. februar 2099"


def _kør(tmp_path: Path, personer: list, *ekstra: str, fil: str = "gren-1.json") -> subprocess.CompletedProcess:
    blocks = [{"linje": "I", "gren": 1, "raw_text": f"{NAVN}, f. 1. jan. 2001."}]
    (tmp_path / "blocks.json").write_text(json.dumps(blocks), encoding="utf-8")
    ext = tmp_path / "extracted"
    ext.mkdir()
    (ext / fil).write_text(json.dumps({"linje": "I", "gren": 1, "personer": personer}),
                                     encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(SCRIPT), str(tmp_path / "blocks.json"), str(ext),
         "--clean", str(tmp_path / "clean.json"), "--review", str(tmp_path / "review.json"), *ekstra],
        capture_output=True, text=True, check=True)


def _person(**kw) -> dict:
    p = {"lokal_id": "a", "navn": NAVN, "koen": "kvinde", "foedsel": {"date_raw": DATO}}
    p.update(kw)
    return p


def test_advisory_for_ren_blok_naar_ikke_stderr_men_advisory_filen(tmp_path):
    r = _kør(tmp_path, [_person()], "--advisory", str(tmp_path / "advisory.json"))
    assert DATO not in r.stderr and NAVN not in r.stderr
    assert "1 advisory" in r.stderr
    adv = json.loads((tmp_path / "advisory.json").read_text(encoding="utf-8"))
    assert adv[0]["fil"] == "gren-1.json" and DATO in adv[0]["advisory"][0]
    assert len(json.loads((tmp_path / "clean.json").read_text(encoding="utf-8"))) == 1


def test_uden_advisory_fil_nævnes_kun_antallet(tmp_path):
    r = _kør(tmp_path, [_person()])
    assert DATO not in r.stderr and "ikke gemt" in r.stderr


def test_flaggede_blokke_viser_kun_regelkoder(tmp_path):
    r = _kør(tmp_path, [_person(koen=None, foraelder_lokal_id="x-findes-ikke")])
    assert DATO not in r.stderr and NAVN not in r.stderr and "x-findes-ikke" not in r.stderr
    assert "FLAG gren-1.json: 2 brud (S1, S3); se review-filen" in r.stderr
    review = json.loads((tmp_path / "review.json").read_text(encoding="utf-8"))
    assert any("x-findes-ikke" in b for b in review[0]["brud"])
    assert DATO in review[0]["advisory"][0]


def test_filnavne_uden_for_konventionen_vises_ikke(tmp_path):
    fil = f"{NAVN} 2001-01-01.json"
    r = _kør(tmp_path, [_person(koen=None)], fil=fil)
    assert NAVN not in r.stderr and "2001-01-01" not in r.stderr
    assert "FLAG fil nr. 1 (navn ikke vist): 1 brud (S3)" in r.stderr
    assert json.loads((tmp_path / "review.json").read_text(encoding="utf-8"))[0]["fil"] == fil
