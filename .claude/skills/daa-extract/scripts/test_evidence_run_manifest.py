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
                          code_sha256=kw.get("code", "c" * 64),
                          codex_cli_version=kw.get("codex", "0.155.1"))


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
                          code_sha256="c" * 64, codex_cli_version="0.155.1") is None


@pytest.mark.parametrize("aendring,kode", [
    (dict(schema_text="{\"skema\": 2}"), "SCHEMA_DRIFT"),
    (dict(runner_contract_version="evidence-runner-9.9"), "RUNNER_CONTRACT_DRIFT"),
    (dict(code_sha256="d" * 64), "RUNNER_CODE_DRIFT"),
    (dict(codex_cli_version="0.156.0"), "CODEX_VERSION_DRIFT"),
])
def test_kontraktdrift_stopper(aendring, kode):
    args = dict(schema_text=SKEMA, runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                code_sha256="c" * 64, codex_cli_version="0.155.1")
    args.update(aendring)
    assert check_contract(m45(), **args) == kode


def test_manipuleret_manifest_stopper():
    m = m45()
    m["records"].append("R-99")
    assert check_contract(m, schema_text=SKEMA,
                          runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                          code_sha256="c" * 64, codex_cli_version="0.155.1") == "MANIFEST_TAMPERED"


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
    ledger = {"schema_version": evidence_runner.LEDGER_SCHEMA_VERSION, "policy_version": "exclusion-2018-20-v1",
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


def _koersel(tmp_path, monkeypatch, *, klausul="t", kode=None, codex="0.155.1",
             noegler=("R-1",), codex_stub=None, policy="exclusion-2018-20-v1", udelukket=None,
             profile_id="daa-2018-20-v1"):
    """Hele runnerens main med én record og en stub i stedet for modellen."""
    import run_evidence_43b
    def lav(k):
        return {"record_key": k, "persona_id": "p", "post_verbatim_text": "t",
                "clauses": [{"ordinal": 1, "verbatim_text": klausul,
                             "verbatim_sha256": evidence_runner.sha256_text(klausul)}]}
    recs = {k: lav(k) for k in noegler}
    shas = {k: evidence_runner.canonical_record_input(r) for k, r in recs.items()}
    ledger = {"schema_version": evidence_runner.LEDGER_SCHEMA_VERSION, "policy_version": policy,
              "rules_script_sha256": "r" * 64, "source_id": 1, "restore_identity": "x",
              "records": {k: {"status": "eligible", "reasons": [], "record_input_sha256": shas[k]}
                          for k in noegler}}
    for k, aarsager in (udelukket or {}).items():
        ledger["records"][k] = {"status": "excluded", "reasons": list(aarsager), "record_input_sha256": "0" * 64}
    (tmp_path / "ledger.json").write_text(json.dumps(ledger), encoding="utf-8")
    (tmp_path / "input.json").write_text(json.dumps({"records": recs}), encoding="utf-8")
    udvalg = {"records": list(noegler), "bundter": {"bundt_1": list(noegler)},
              "record_input_sha256": shas, "strata_version": "t", "strata_sha256": "s" * 64}
    m = build_manifest(udvalg, dagsvaerk="4.5", restore_identity="x",
                       ledger_sha256=hashlib.sha256((tmp_path / "ledger.json").read_bytes()).hexdigest(),
                       profil=evidence_extract.load_profile(profile_id),
                       claims_schema_sha256=evidence_runner.sha256_text(
                           bm.SKEMA.read_text(encoding="utf-8")),
                       code_sha256=kode or runner_code_sha256(), codex_cli_version="0.155.1")
    (tmp_path / "m.json").write_text(json.dumps(m), encoding="utf-8")
    kaldt = []
    # CI har ingen Codex: versionen injiceres, så testen ikke afhænger af maskinen.
    monkeypatch.setattr(evidence_runner, "codex_cli_version",
                        codex if callable(codex) else (lambda **k: codex))
    monkeypatch.setattr(evidence_runner, "run_codex",
                        (lambda *a, **k: (kaldt.append(1), codex_stub())[1]) if codex_stub
                        else (lambda *a, **k: kaldt.append(1)))
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


def test_runneren_kalder_ikke_modellen_ved_ny_codex_version(tmp_path, monkeypatch, capsys):
    """Review 35, P1: CLI'en har opdateret sig selv mellem GO og kørsel."""
    rc, kaldt = _koersel(tmp_path, monkeypatch, codex="0.156.0")
    assert rc == 1 and kaldt == [] and not (tmp_path / "o.json").exists()
    assert "CODEX_VERSION_DRIFT" in capsys.readouterr().out


def test_runneren_kalder_ikke_modellen_naar_versionen_ikke_kan_laeses(tmp_path, monkeypatch, capsys):
    def ulaeselig(**k):
        raise evidence_runner.RunnerError("RUNNER_CODEX_VERSION_UNKNOWN")
    rc, kaldt = _koersel(tmp_path, monkeypatch, codex=ulaeselig)
    assert rc == 1 and kaldt == [] and not (tmp_path / "o.json").exists()
    assert "RUNNER_CODEX_VERSION_UNKNOWN" in capsys.readouterr().out


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
        ledger = {"schema_version": evidence_runner.LEDGER_SCHEMA_VERSION, "policy_version": "exclusion-2018-20-v1",
                  "rules_script_sha256": "r" * 64, "source_id": 1, "restore_identity": "x",
                  "records": {"R-1": {"status": "eligible", "reasons": [],
                                      "record_input_sha256":
                                          evidence_runner.canonical_record_input(rec)}}}
        return evidence_runner.run_record_guarded(rec, ledger=ledger)

    assert guard(_post("t", "t")) == "kørt" and videre == [1]          # kontrol: gyldig går videre
    udfald = guard(_post("t", "fremmed"))
    assert udfald.error_kind == "not_eligible" and videre == [1]


# --- review 35, P1: Codex-versionen er en del af det godkendte miljø ---------

def test_manifest_binds_the_codex_version():
    m = m45()
    assert m["codex_cli_version"] == "0.155.1"
    kw = dict(schema_text=SKEMA, runner_contract_version=m["runner_contract_version"],
              code_sha256="c" * 64)
    assert check_contract(m, codex_cli_version="0.155.1", **kw) is None
    assert check_contract(m, codex_cli_version="0.156.0", **kw) == "CODEX_VERSION_DRIFT"


def test_a_manifest_must_bind_the_codex_version():
    """Versionen er påkrævet: et manifest uden den ville lade en selvopdaterende CLI
    skifte opførsel mellem GO og kørsel (P1)."""
    m = m45(codex=None)
    assert "codex_cli_version" not in m
    kw = dict(schema_text=SKEMA, runner_contract_version=m["runner_contract_version"],
              code_sha256="c" * 64)
    assert check_contract(m, codex_cli_version="0.155.1", **kw) == "CODEX_VERSION_UNBOUND"


# --- genbinding af 4.4: piloten om under profil v2 ------------------------------

def _main_manifest(tmp_path, monkeypatch, *extra):
    udvalg = udvalg45()
    (tmp_path / "u.json").write_text(json.dumps(udvalg), encoding="utf-8")
    (tmp_path / "l.json").write_text("{}", encoding="utf-8")
    monkeypatch.setattr(evidence_runner, "codex_cli_version", lambda **k: "0.155.1")
    monkeypatch.setattr("sys.argv", ["b", "--selection", str(tmp_path / "u.json"),
                                     "--ledger", str(tmp_path / "l.json"),
                                     "--out", str(tmp_path / "m.json"),
                                     "--restore-identity", "daa44g_x",
                                     *(extra if "--dagsvaerk" in extra else ("--dagsvaerk", "4.5", *extra))])
    assert bm.main() == 0
    return json.loads((tmp_path / "m.json").read_text(encoding="utf-8"))


def test_manifestet_kan_bindes_til_profil_v2(tmp_path, monkeypatch):
    m = _main_manifest(tmp_path, monkeypatch, "--profile-id", "daa-2018-20-v2")
    v2 = evidence_extract.load_profile("daa-2018-20-v2")
    assert m["profile_id"] == "daa-2018-20-v2" and m["profile_version"] == v2["version"]
    assert m["codex_cli_version"] == "0.155.1"


def test_profilen_er_stadig_v1_uden_flag(tmp_path, monkeypatch):
    """4.3b/4.5-manifesterne blev bygget uden flaget; standarden ændres ikke."""
    assert _main_manifest(tmp_path, monkeypatch)["profile_id"] == "daa-2018-20-v1"


def test_ogsaa_et_43b_manifest_uden_kodehash_skal_binde_versionen(tmp_path, monkeypatch):
    """Review af P1, fund 2: `--dagsvaerk` står som standard på 4.3b, der ikke binder
    kodehashen.  Versionen må ikke følge med den undtagelse."""
    m = build_manifest(udvalg45(), dagsvaerk="4.3b", restore_identity="x", ledger_sha256="L",
                       profil=PROFIL, claims_schema_sha256=evidence_runner.sha256_text(SKEMA))
    assert "runner_code_sha256" not in m
    assert check_contract(m, schema_text=SKEMA, runner_contract_version=m["runner_contract_version"],
                          code_sha256="c" * 64, codex_cli_version="0.155.1") == "CODEX_VERSION_UNBOUND"
    bygget = _main_manifest(tmp_path, monkeypatch, "--dagsvaerk", "4.3b")
    assert bygget["dagsvaerk"] == "4.3b" and bygget["codex_cli_version"] == "0.155.1"


@pytest.mark.parametrize("kind,forventet", [("tool_use", "STOP_TOOL_USE"),
                                           ("quota_exhausted", "STOP_QUOTA_EXHAUSTED"),
                                           ("validation_failed", None), ("timeout", None), (None, None)])
def test_bundtet_stopper_efter_vaerktoejsbrug_og_kvote(kind, forventet):
    """Review af P1: record N+1 blev sendt efter `tool_use` i N."""
    import run_evidence_43b
    assert run_evidence_43b.stop_reason(kind) == forventet


def test_driveren_stopper_ved_versionsskift_midt_i_bundtet(tmp_path, monkeypatch, capsys):
    """Versionen tjekkes før HVERT kald, ikke kun ved kontrakten."""
    svar = iter(["0.155.1", "0.156.0"])
    rc, kaldt = _koersel(tmp_path, monkeypatch, codex=lambda **k: next(svar))
    assert rc == 1 and kaldt == []
    assert "CODEX_VERSION_DRIFT før R-1" in capsys.readouterr().out


def test_manifest_6c1_binds_code_and_source(tmp_path, monkeypatch):
    (tmp_path / "ri.json").write_text(json.dumps({"source_id": 3, "records": {}}), encoding="utf-8")
    m = _main_manifest(tmp_path, monkeypatch, "--dagsvaerk", "6c-1",
                       "--runner-input", str(tmp_path / "ri.json"))
    assert m["dagsvaerk"] == "6c-1" and m["source_id"] == 3
    assert m["runner_contract_version"] == "evidence-runner-1.4"
    assert len(m["runner_code_sha256"]) == 64


def test_manifest_6c1_without_runner_input_is_refused(tmp_path, monkeypatch, capsys):
    with pytest.raises(AssertionError):
        _main_manifest(tmp_path, monkeypatch, "--dagsvaerk", "6c-1")
    assert "RUNNER_INPUT_SOURCE_MISSING" in capsys.readouterr().out


def test_runner_rejects_14_manifest_without_code_sha():
    m = build_manifest(udvalg45(), dagsvaerk="6c-1", restore_identity="x", ledger_sha256="L",
                       profil=PROFIL, claims_schema_sha256=evidence_runner.sha256_text(SKEMA),
                       codex_cli_version="0.155.1", source_id=3)
    assert "runner_code_sha256" not in m
    assert check_contract(m, schema_text=SKEMA, runner_contract_version=m["runner_contract_version"],
                          code_sha256="c" * 64, codex_cli_version="0.155.1") == "RUNNER_CODE_SHA_MISSING"


def test_runner_accepts_13_manifest_without_code_sha():
    m = build_manifest(udvalg45(), dagsvaerk="4.5", restore_identity="x", ledger_sha256="L",
                       profil=PROFIL, claims_schema_sha256=evidence_runner.sha256_text(SKEMA),
                       codex_cli_version="0.155.1")
    m["runner_contract_version"] = "evidence-runner-1.3"
    m["manifest_sha256"] = manifest_sha256(m)
    assert check_contract(m, schema_text=SKEMA, runner_contract_version="evidence-runner-1.3",
                          code_sha256="c" * 64, codex_cli_version="0.155.1") is None


def test_run_evidence_stops_bundle_on_quota_without_type(tmp_path, monkeypatch, capsys):
    """Review Focus 3: en kvotefejl uden `error.type` midt i et bundt standser det —
    record 2 sendes ikke og har intet cacheindslag."""
    import subprocess
    fixtur = (Path(__file__).resolve().parent / "tests" / "fixtures" / "codex-exec"
              / "failure-quota-no-type.jsonl").read_text(encoding="utf-8")
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: subprocess.CompletedProcess(a, 0, "", ""))
    rc, kaldt = _koersel(tmp_path, monkeypatch, noegler=("R-1", "R-2"),
                         codex_stub=lambda: (fixtur, ""))
    out = capsys.readouterr().out
    assert len(kaldt) == 1
    assert "STOP_QUOTA_EXHAUSTED ved R-1" in out
    assert not list((tmp_path / "c").glob("*.json"))


def _kvote_stub(monkeypatch):
    import subprocess
    fixtur = (Path(__file__).resolve().parent / "tests" / "fixtures" / "codex-exec"
              / "failure-quota-no-type.jsonl").read_text(encoding="utf-8")
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: subprocess.CompletedProcess(a, 0, "", ""))
    return lambda: (fixtur, "")


def test_run_evidence_reads_a_1939_ledger(tmp_path, monkeypatch, capsys):
    """Trin 6c-1 Task 5: runneren læser en exclusion-1939-v1-ledger (årsagerne valideres mod politikken)
    og sender den eligible record; den udelukkede sendes ikke."""
    rc, kaldt = _koersel(tmp_path, monkeypatch, codex_stub=_kvote_stub(monkeypatch),
                         policy="exclusion-1939-v1", profile_id="daa-1939-v2",
                         udelukket={"R-9": ["no_published_persona", "text_year_ge_1915"]})
    assert len(kaldt) == 1
    assert "STOP_QUOTA_EXHAUSTED ved R-1" in capsys.readouterr().out


def test_run_evidence_refuses_a_2018_20_reason_in_a_1939_ledger(tmp_path, monkeypatch):
    with pytest.raises(evidence_runner.EligibilityError, match="LEDGER_REASON_UNKNOWN"):
        _koersel(tmp_path, monkeypatch, codex_stub=_kvote_stub(monkeypatch),
                 policy="exclusion-1939-v1", profile_id="daa-1939-v2",
                 udelukket={"R-9": ["birth_year_text_filter"]})


def test_run_evidence_refuses_an_unknown_policy(tmp_path, monkeypatch):
    with pytest.raises(evidence_runner.EligibilityError, match="LEDGER_POLICY_UNKNOWN"):
        _koersel(tmp_path, monkeypatch, codex_stub=_kvote_stub(monkeypatch), policy="p")


@pytest.mark.parametrize("policy,profile_id", [("exclusion-1939-v1", "daa-2018-20-v1"),
                                               ("exclusion-2018-20-v1", "daa-1939-v2")])
def test_run_evidence_refuses_a_ledger_from_another_edition(tmp_path, monkeypatch, capsys, policy, profile_id):
    """Fix-runde 1: ledgerens politik er bundet til profilens udgave; ingen model kaldes."""
    rc, kaldt = _koersel(tmp_path, monkeypatch, codex_stub=_kvote_stub(monkeypatch),
                         policy=policy, profile_id=profile_id)
    assert rc == 1 and kaldt == [] and not (tmp_path / "o.json").exists()
    assert "LEDGER_POLICY_EDITION_MISMATCH" in capsys.readouterr().out
