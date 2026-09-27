import hashlib
import json
from pathlib import Path

import pytest

import build_43b_manifest as bm
import evidence_extract
import evidence_runner
from build_43b_manifest import (build_manifest, bundles_of, check_contract,
                                manifest_sha256, runner_code_sha256)

PROFIL = {"profile_id": "daa-2018-20-v1", "version": "1.3.0",
          "prompt_file": "p.md", "prompt_sha256": "d46c", "model_id": "gpt-5.6-terra"}
SKEMA = "{\"skema\": 1}"


def udvalg45():
    return {"records": [f"R-{i}" for i in range(12)],
            "bundter": {"bundt_1": [f"R-{i}" for i in range(6)],
                        "reserve": [f"R-{i}" for i in range(6, 12)]},
            "record_input_sha256": {f"R-{i}": f"h{i}" for i in range(12)},
            "strata_version": "45-strata-v2", "strata_sha256": "s" * 64}


def m45(**kw):
    return build_manifest(udvalg45(), dagsvaerk="4.5", restore_identity="daa45_x",
                          ledger_sha256="L", profil=PROFIL,
                          claims_schema_sha256=evidence_runner.sha256_text(SKEMA),
                          code_sha256=kw.get("code", "c" * 64))


def test_manifest_baerer_bundter_dagsvaerk_og_kodehash():
    m = m45()
    assert m["dagsvaerk"] == "4.5" and m["runner_code_sha256"] == "c" * 64
    assert bundles_of(m) == udvalg45()["bundter"]
    assert m["budget"]["antal_kald"] == 12
    assert m["manifest_sha256"] == manifest_sha256(m)


def test_4_3b_manifestet_laeses_uaendret():
    gammelt = {"bundt_1": ["I-29"], "bundt_2": ["III-104"], "records": ["I-29", "III-104"]}
    assert bundles_of(gammelt) == {"bundt_1": ["I-29"], "bundt_2": ["III-104"]}


def test_kontrakten_holder_naar_intet_er_aendret():
    assert check_contract(m45(), schema_text=SKEMA,
                          runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                          code_sha256="c" * 64) is None


@pytest.mark.parametrize("aendring,kode", [
    (dict(schema_text="{\"skema\": 2}"), "SCHEMA_DRIFT"),
    (dict(runner_contract_version="evidence-runner-9.9"), "RUNNER_CONTRACT_DRIFT"),
    (dict(code_sha256="d" * 64), "RUNNER_CODE_DRIFT"),
])
def test_kontraktdrift_stopper(aendring, kode):
    args = dict(schema_text=SKEMA, runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                code_sha256="c" * 64)
    args.update(aendring)
    assert check_contract(m45(), **args) == kode


def test_manipuleret_manifest_stopper():
    m = m45()
    m["records"].append("R-99")
    assert check_contract(m, schema_text=SKEMA,
                          runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                          code_sha256="c" * 64) == "MANIFEST_TAMPERED"


def test_kontraktfillisten_daekker_de_operative_filer():
    """4.5-kodereview, fund 2: sandbox, adgangstest, prædikatkatalog, profiler og
    selve kontrollen afgør også, hvad der sendes, og hvordan svaret valideres."""
    assert set(bm.RUNNER_CODE_FILES) >= {
        "evidence_extract.py", "evidence_runner.py", "run_evidence_43b.py",
        "build_43b_manifest.py", "sandbox/runner-gate.sb.template",
        "sandbox/gate-access-test.sh", "../references/interpretation-predicates.json",
        "../references/extraction-profiles.json"}
    for navn in bm.RUNNER_CODE_FILES:
        assert (bm.SCRIPTS / navn).is_file(), navn


@pytest.mark.parametrize("navn", bm.RUNNER_CODE_FILES)
def test_kodehash_aendres_naar_en_kontraktfil_aendres(tmp_path, navn):
    scripts = tmp_path / "a" / "scripts"
    for n in bm.RUNNER_CODE_FILES:
        (scripts / n).parent.mkdir(parents=True, exist_ok=True)
        (scripts / n).write_text("x", encoding="utf-8")
    foer = runner_code_sha256(scripts)
    (scripts / navn).write_text("y", encoding="utf-8")
    assert runner_code_sha256(scripts) != foer


def test_runneren_kalder_ikke_modellen_ved_skemadrift(tmp_path, monkeypatch):
    """Mutationstest: skemaet ændres efter GO → STOP før første modelkald."""
    import run_evidence_43b
    rec = {"record_key": "R-1", "persona_id": "p", "post_verbatim_text": "t",
           "clauses": [{"ordinal": 1, "verbatim_text": "t",
                        "verbatim_sha256": evidence_runner.sha256_text("t")}]}
    ledger = {"schema_version": evidence_runner.LEDGER_SCHEMA_VERSION, "policy_version": "p",
              "rules_script_sha256": "r" * 64, "source_id": 1, "restore_identity": "x",
              "records": {"R-1": {"status": "eligible", "reasons": [],
                                  "record_input_sha256": evidence_runner.canonical_record_input(rec)}}}
    (tmp_path / "ledger.json").write_text(json.dumps(ledger), encoding="utf-8")
    (tmp_path / "input.json").write_text(json.dumps({"records": {"R-1": rec}}), encoding="utf-8")
    profil = evidence_extract.load_profile("daa-2018-20-v1")
    udvalg = {"records": ["R-1"], "bundter": {"bundt_1": ["R-1"]},
              "record_input_sha256": {"R-1": evidence_runner.canonical_record_input(rec)},
              "strata_version": "t", "strata_sha256": "s" * 64}
    m = build_manifest(udvalg, dagsvaerk="4.5", restore_identity="x",
                       ledger_sha256=hashlib.sha256((tmp_path / "ledger.json").read_bytes()).hexdigest(),
                       profil=profil, claims_schema_sha256="0" * 64,  # ≠ det aktuelle skema
                       code_sha256=runner_code_sha256())
    (tmp_path / "m.json").write_text(json.dumps(m), encoding="utf-8")
    kaldt = []
    monkeypatch.setattr(evidence_runner, "run_codex", lambda *a, **k: kaldt.append(1))
    monkeypatch.setattr("sys.argv", ["run", "--manifest", str(tmp_path / "m.json"),
                                     "--approved-sha256", m["manifest_sha256"],
                                     "--runner-input", str(tmp_path / "input.json"),
                                     "--ledger", str(tmp_path / "ledger.json"),
                                     "--bundle", "bundt_1", "--cache-dir", str(tmp_path / "c"),
                                     "--out", str(tmp_path / "o.json"),
                                     "--judgement-sheet", str(tmp_path / "a.json")])
    assert run_evidence_43b.main() == 1
    assert kaldt == []
    assert not (tmp_path / "o.json").exists()


def test_4_3b_manifestets_hash_kan_genberegnes():
    sti = Path.home() / ".private" / "43b-manifest.json"
    if not sti.exists():
        pytest.skip("privat 4.3b-manifest findes ikke på denne maskine")
    m = json.loads(sti.read_text(encoding="utf-8"))
    assert manifest_sha256(m) == m["manifest_sha256"]


def _koersel(tmp_path, monkeypatch, *, klausul="t", kode=None):
    """Hele runnerens main med én record og en stub i stedet for modellen."""
    import run_evidence_43b
    rec = {"record_key": "R-1", "persona_id": "p", "post_verbatim_text": "t",
           "clauses": [{"ordinal": 1, "verbatim_text": klausul,
                        "verbatim_sha256": evidence_runner.sha256_text(klausul)}]}
    ledger = {"schema_version": evidence_runner.LEDGER_SCHEMA_VERSION, "policy_version": "p",
              "rules_script_sha256": "r" * 64, "source_id": 1, "restore_identity": "x",
              "records": {"R-1": {"status": "eligible", "reasons": [],
                                  "record_input_sha256": evidence_runner.canonical_record_input(rec)}}}
    (tmp_path / "ledger.json").write_text(json.dumps(ledger), encoding="utf-8")
    (tmp_path / "input.json").write_text(json.dumps({"records": {"R-1": rec}}), encoding="utf-8")
    udvalg = {"records": ["R-1"], "bundter": {"bundt_1": ["R-1"]},
              "record_input_sha256": {"R-1": evidence_runner.canonical_record_input(rec)},
              "strata_version": "t", "strata_sha256": "s" * 64}
    m = build_manifest(udvalg, dagsvaerk="4.5", restore_identity="x",
                       ledger_sha256=hashlib.sha256((tmp_path / "ledger.json").read_bytes()).hexdigest(),
                       profil=evidence_extract.load_profile("daa-2018-20-v1"),
                       claims_schema_sha256=evidence_runner.sha256_text(
                           bm.SKEMA.read_text(encoding="utf-8")),
                       code_sha256=kode or runner_code_sha256())
    (tmp_path / "m.json").write_text(json.dumps(m), encoding="utf-8")
    kaldt = []
    monkeypatch.setattr(evidence_runner, "run_codex", lambda *a, **k: kaldt.append(1))
    monkeypatch.setattr("sys.argv", ["run", "--manifest", str(tmp_path / "m.json"),
                                     "--approved-sha256", m["manifest_sha256"],
                                     "--runner-input", str(tmp_path / "input.json"),
                                     "--ledger", str(tmp_path / "ledger.json"),
                                     "--bundle", "bundt_1", "--cache-dir", str(tmp_path / "c"),
                                     "--out", str(tmp_path / "o.json"),
                                     "--judgement-sheet", str(tmp_path / "a.json")])
    return run_evidence_43b.main(), kaldt


def test_runneren_kalder_ikke_modellen_ved_kodedrift(tmp_path, monkeypatch, capsys):
    rc, kaldt = _koersel(tmp_path, monkeypatch, kode="0" * 64)
    assert rc == 1 and kaldt == [] and not (tmp_path / "o.json").exists()
    assert "RUNNER_CODE_DRIFT" in capsys.readouterr().out


def test_runneren_sender_ikke_en_klausul_uden_for_den_godkendte_post(tmp_path, monkeypatch, capsys):
    """4.5-kodereview, fund 1: ledgeren hasher helposten; en klausul med fremmed tekst
    (og konsistent selvhash) må ikke kunne rejse med under en eligible record."""
    rc, kaldt = _koersel(tmp_path, monkeypatch, klausul="fremmed tekst")
    assert rc == 1 and kaldt == [] and not (tmp_path / "o.json").exists()
    assert "CLAUSE_OUTSIDE_POST" in capsys.readouterr().out


def _post(tekst, *klausuler):
    return {"record_key": "R-1", "post_verbatim_text": tekst,
            "clauses": [{"ordinal": i, "verbatim_text": k,
                         "verbatim_sha256": evidence_runner.sha256_text(k)}
                        for i, k in enumerate(klausuler, 1)]}


def test_klausuler_skal_vaere_ordnede_udsnit_af_posten():
    evidence_runner.check_clauses_within_post(_post("født 1800, død 1850", "født 1800", "død 1850"))
    for rec in (_post("født 1800", "død 1850"),                            # fremmed tekst
                _post("født 1800, død 1850", "død 1850", "født 1800"),     # ombyttet orden
                _post("født 1800", "født 1800", "født 1800")):             # overlap/genbrug
        with pytest.raises(evidence_runner.EligibilityError, match="CLAUSE_OUTSIDE_POST"):
            evidence_runner.check_clauses_within_post(rec)


def test_guarden_afviser_fremmed_klausul_foer_kaldet(monkeypatch):
    videre = []
    monkeypatch.setattr(evidence_runner, "run_record", lambda export, **kw: videre.append(1) or "kørt")

    def guard(rec):
        rec["persona_id"] = "p"
        ledger = {"schema_version": evidence_runner.LEDGER_SCHEMA_VERSION, "policy_version": "p",
                  "rules_script_sha256": "r" * 64, "source_id": 1, "restore_identity": "x",
                  "records": {"R-1": {"status": "eligible", "reasons": [],
                                      "record_input_sha256":
                                          evidence_runner.canonical_record_input(rec)}}}
        return evidence_runner.run_record_guarded(rec, ledger=ledger)

    assert guard(_post("t", "t")) == "kørt" and videre == [1]          # kontrol: gyldig går videre
    udfald = guard(_post("t", "fremmed"))
    assert udfald.error_kind == "not_eligible" and videre == [1]
