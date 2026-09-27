"""Kontrolmodellen (decisions 2026-09-27; plan 2026-09-27 Task 4)."""
from __future__ import annotations

import hashlib
import json
import random
import subprocess
import sys
from pathlib import Path

import pytest

import control_model
from control_model import ControlError, machine_sql, plan_run, verify_sql
from interpretation_decision_sheet import sheet_order

SCRIPT = str(Path(__file__).with_name("control_model.py"))
H = "a" * 64


def iid(n: int) -> str:
    return f"00000000-0000-4000-8000-{n:012d}"


def item(n: int, klasse: str = "MATCH", *, version: int = 1, predicate: str = "person.death") -> dict:
    return {"interpretation_id": iid(n), "version": version, "predicate": predicate, "class": klasse,
            "assertion_id": -n if klasse in ("MATCH", "MATCH_SINGLETON") else None}


def row(n: int, *, version: int = 1) -> dict:
    return {"interpretation_id": iid(n), "version": version, "record_key": f"I-{n}",
            "predicate": "person.death", "value_text": "1850", "confidence": 1,
            "persona_role": "principal", "cited": [{"ordinal": 1, "text": "x", "flags": []}]}


def klassifikation(*items: dict) -> dict:
    return {"items": list(items), "counts": {}}


def naturlig(n_match: int, extra: tuple = ()) -> tuple[dict, list[dict]]:
    items = [item(n) for n in range(1, n_match + 1)] + list(extra)
    return klassifikation(*items), [row(int(i["interpretation_id"][-12:]), version=i["version"]) for i in items]


# --- stikprøven -------------------------------------------------------------

def test_stikproeven_er_deterministisk_og_uafhaengig_af_raekkefoelgen():
    k, rows = naturlig(50)
    blandet = dict(k, items=random.Random(7).sample(k["items"], len(k["items"])))
    assert plan_run(k, rows)["sample_ids"] == plan_run(blandet, rows)["sample_ids"]


def test_stikproeven_er_de_foerste_20_efter_seed_hash():
    k, rows = naturlig(50)
    forventet = sorted((i["interpretation_id"] for i in k["items"]),
                       key=lambda x: hashlib.sha256(f"kontrolmodel-v1:{x}".encode()).hexdigest())[:20]
    p = plan_run(k, rows)
    assert p["sample_ids"] == sorted(forventet)
    assert len(p["machine"]) == 30
    assert not set(p["sample_ids"]) & {m["interpretation_id"] for m in p["machine"]}


def test_faa_kandidater_giver_tomt_maskinsaet():
    """Er der ≤ 20 kandidater, ser mennesket dem alle, og intet accepteres maskinelt."""
    k, rows = naturlig(20)
    p = plan_run(k, rows)
    assert len(p["sample_ids"]) == 20 and p["machine"] == []


def test_kun_bulk_match_kan_accepteres_maskinelt():
    extra = tuple(item(n, c) for n, c in ((101, "MATCH_SINGLETON"), (102, "AMBIGUOUS"),
                                          (103, "SKRIVEMAADE"), (104, "NO_FACT"), (105, "REAL_DIFF"),
                                          (106, "NO_IDENTITY"), (107, "NO_PLACEMENT"),
                                          (108, "UNSUPPORTED_RULE")))
    k, rows = naturlig(25, extra)
    p = plan_run(k, rows)
    maskine = {m["interpretation_id"] for m in p["machine"]}
    assert maskine and all(int(m[-12:]) <= 25 for m in maskine)
    assert not {iid(n) for n in range(101, 109)} & (maskine | set(p["sample_ids"]))


def test_arket_er_real_diff_og_stikproeven_i_raekkefilens_orden():
    k, rows = naturlig(25, (item(105, "REAL_DIFF"), item(103, "SKRIVEMAADE")))
    p = plan_run(k, rows)
    ark = [r["interpretation_id"] for r in p["rows_kontrol"]]
    assert set(ark) == set(p["sample_ids"]) | {iid(105)}
    assert ark == [r["interpretation_id"] for r in rows if r["interpretation_id"] in set(ark)]


def test_raekke_mangler_eller_har_anden_version():
    k, rows = naturlig(3)
    with pytest.raises(ControlError, match="ROWS_MISSING"):
        plan_run(k, rows[1:])
    with pytest.raises(ControlError, match="ROWS_VERSION_MISMATCH"):
        plan_run(k, [row(1, version=2)] + rows[1:])


@pytest.mark.parametrize("bad", [
    klassifikation(item(1), item(1)),
    klassifikation(dict(item(1), **{"class": "MAYBE"})),
    klassifikation(dict(item(1), assertion_id=None)),
    {"items": "ikke en liste"},
])
def test_ugyldig_klassifikation_afvises(bad):
    with pytest.raises(ControlError, match="CLASSIFICATION_INVALID"):
        plan_run(bad, [row(1)])


# --- gaten og den maskinelle SQL ------------------------------------------

def ark_for(p: dict, tokens: dict[str, str] | None = None) -> str:
    tokens = tokens or {}
    return "".join(f"D {r['interpretation_id']} {r['version']} : {tokens.get(r['interpretation_id'], 'A')}\n"
                   for r in sheet_order(p["rows_kontrol"]))


def test_stikproeve_med_R_stopper():
    k, rows = naturlig(30)
    p = plan_run(k, rows)
    with pytest.raises(ControlError, match="SAMPLE_FAILED rejected=1 unresolved=0"):
        machine_sql(p, ark_for(p, {p["sample_ids"][3]: "R"}), sheet_sha256=H, hashes={})


def test_stikproeve_med_U_stopper():
    """En uafklaret stikprøve er ikke en godkendt stikprøve."""
    k, rows = naturlig(30)
    p = plan_run(k, rows)
    with pytest.raises(ControlError, match="SAMPLE_FAILED rejected=0 unresolved=1"):
        machine_sql(p, ark_for(p, {p["sample_ids"][0]: "U"}), sheet_sha256=H, hashes={})


def test_afvist_real_diff_stopper_ikke():
    k, rows = naturlig(30, (item(105, "REAL_DIFF"),))
    p = plan_run(k, rows)
    sql = machine_sql(p, ark_for(p, {iid(105): "R"}), sheet_sha256=H, hashes={})
    assert sql.count("red_decide_interpretation(") == 10


def test_maskinel_sql_baerer_metode_version_maal_og_kontroller():
    k, rows = naturlig(22, (item(23, version=3),))
    p = plan_run(k, rows)
    hashes = {"classification_sha256": "c" * 64, "sample_sha256": "d" * 64}
    sql = machine_sql(p, ark_for(p), sheet_sha256=H, hashes=hashes)
    assert sql.startswith("\\set ON_ERROR_STOP on\nBEGIN;") and sql.rstrip().endswith("COMMIT;")
    assert "SET LOCAL ROLE authenticated;" in sql
    assert "set_config('request.jwt.claim.sub', :'actor', true)" in sql
    assert sql.count("red_decide_interpretation(") == len(p["machine"]) == 3
    for m in p["machine"]:
        assert f"red_decide_interpretation('{m['interpretation_id']}'::uuid, {m['version']}, 'accepted'," in sql
    ev = [json.loads(line.split("'")[5]) for line in sql.splitlines()
          if "red_decide_interpretation(" in line]
    assert {e["method"] for e in ev} == {"machine-corroboration-v1"}
    assert {e["decision"] for e in ev} == {"decisions.md 2026-09-27"}
    assert all(e["classification_sha256"] == "c" * 64 and e["sample_sha256"] == "d" * 64
               and e["sheet_sha256"] == H for e in ev)
    assert sorted(e["assertion_id"] for e in ev) == sorted(m["assertion_id"] for m in p["machine"])
    # Menneskets afgørelser skal være skrevet først — ellers er gaten kun en påstand.
    assert "SAMPLE_NOT_APPLIED" in sql and "human-sheet-kontrol-v1" in sql
    assert "MACHINE_COUNT_MISMATCH" in sql


def test_arket_skal_daekke_praecis_raekkefilen():
    k, rows = naturlig(25)
    p = plan_run(k, rows)
    uden_en = "".join(ark_for(p).splitlines(keepends=True)[1:])
    with pytest.raises(Exception, match="SHEET_IDENTITY_MISMATCH"):
        machine_sql(p, uden_en, sheet_sha256=H, hashes={})


def test_tomt_maskinsaet_giver_ingen_sql():
    k, rows = naturlig(5)
    p = plan_run(k, rows)
    assert machine_sql(p, ark_for(p), sheet_sha256=H, hashes={}) is None


def test_verify_sql_sammenligner_maengder_via_supersedes():
    k, rows = naturlig(22)
    p = plan_run(k, rows)
    sql = verify_sql(p)
    assert "\\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql" in sql
    assert "supersedes_id" in sql and "CONTROL_TARGETS_MISMATCH" in sql
    for i in p["sample_ids"] + [m["interpretation_id"] for m in p["machine"]]:
        assert i in sql


# --- CLI: hash-bindingerne --------------------------------------------------

def _plan_cli(tmp_path: Path, n_match: int = 25) -> Path:
    k, rows = naturlig(n_match)
    (tmp_path / "k.json").write_text(json.dumps(k), encoding="utf-8")
    (tmp_path / "rows.json").write_text(json.dumps(rows), encoding="utf-8")
    ud = tmp_path / "plan"
    p = subprocess.run([sys.executable, SCRIPT, "plan", "--classification", str(tmp_path / "k.json"),
                        "--rows", str(tmp_path / "rows.json"), "--out-dir", str(ud)],
                       capture_output=True, text=True)
    assert p.returncode == 0, p.stdout + p.stderr
    assert "PLAN_OK" in p.stdout
    return ud


def _machine_cli(ud: Path, ark: Path, godkendt: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, SCRIPT, "machine-sql", "--plan-dir", str(ud), "--sheet", str(ark),
                           "--approved-sha256", godkendt, "--out", str(ud / "maskine.sql")],
                          capture_output=True, text=True)


def test_cli_plan_skriver_private_filer_med_hashes(tmp_path):
    ud = _plan_cli(tmp_path)
    plan = json.loads((ud / "plan.json").read_text())
    for navn in ("plan.json", "rows-kontrol.json", "machine-plan.json"):
        assert (ud / navn).stat().st_mode & 0o777 == 0o600
    assert plan["rows_kontrol_sha256"] == hashlib.sha256((ud / "rows-kontrol.json").read_bytes()).hexdigest()
    assert plan["machine_plan_sha256"] == hashlib.sha256((ud / "machine-plan.json").read_bytes()).hexdigest()
    assert plan["sample_size"] == 20 and plan["seed"] == "kontrolmodel-v1"
    assert len(plan["sample_ids"]) == 20


def test_cli_machine_sql_komplet(tmp_path):
    ud = _plan_cli(tmp_path)
    p = json.loads((ud / "plan.json").read_text())
    ark = tmp_path / "ark.txt"
    ark.write_text("".join(f"D {r['interpretation_id']} {r['version']} : A\n"
                           for r in sheet_order(json.loads((ud / "rows-kontrol.json").read_text()))), encoding="utf-8")
    r = _machine_cli(ud, ark, hashlib.sha256(ark.read_bytes()).hexdigest())
    assert r.returncode == 0 and "MACHINE_SQL_OK maskinelle=5" in r.stdout
    assert (ud / "maskine.sql").stat().st_mode & 0o777 == 0o600
    assert p["classification_sha256"] in (ud / "maskine.sql").read_text()


def test_cli_afviser_aendret_ark(tmp_path):
    ud = _plan_cli(tmp_path)
    ark = tmp_path / "ark.txt"
    ark.write_text("noget andet\n", encoding="utf-8")
    r = _machine_cli(ud, ark, H)
    assert r.returncode == 1 and "SHEET_HASH_MISMATCH" in r.stdout and not (ud / "maskine.sql").exists()


@pytest.mark.parametrize("navn", ["machine-plan.json", "rows-kontrol.json"])
def test_cli_afviser_aendret_planfil(tmp_path, navn):
    ud = _plan_cli(tmp_path)
    ark = tmp_path / "ark.txt"
    ark.write_text("".join(f"D {r['interpretation_id']} {r['version']} : A\n"
                           for r in sheet_order(json.loads((ud / "rows-kontrol.json").read_text()))), encoding="utf-8")
    f = ud / navn
    data = json.loads(f.read_text())
    f.write_text(json.dumps(data[:-1] if navn == "machine-plan.json" else data), encoding="utf-8")
    r = _machine_cli(ud, ark, hashlib.sha256(ark.read_bytes()).hexdigest())
    assert r.returncode == 1 and "PLAN_HASH_MISMATCH" in r.stdout and not (ud / "maskine.sql").exists()


def test_cli_stikproeve_fejl_skriver_intet(tmp_path):
    ud = _plan_cli(tmp_path)
    p = json.loads((ud / "plan.json").read_text())
    ark = tmp_path / "ark.txt"
    ark.write_text("".join(f"D {r['interpretation_id']} {r['version']} : "
                           f"{'R' if r['interpretation_id'] == p['sample_ids'][0] else 'A'}\n"
                           for r in sheet_order(json.loads((ud / "rows-kontrol.json").read_text()))), encoding="utf-8")
    r = _machine_cli(ud, ark, hashlib.sha256(ark.read_bytes()).hexdigest())
    assert r.returncode == 1 and "SAMPLE_FAILED" in r.stdout and not (ud / "maskine.sql").exists()
