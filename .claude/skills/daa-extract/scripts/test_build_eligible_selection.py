import json
import stat

import pytest
from build_43b_manifest import build_manifest, bundles_of
from build_43b_proposal_manifest import verify_runner_manifest
from build_eligible_selection import (SelectionLedgerMismatch, build_selection, bundle,
                                      definition_sha256, eligible_keys, main)
from evidence_runner import canonical_record_input, sha256_text

H = "a" * 64


def rec(key, tekst="Født 1800.", persona=True):
    return {"record_key": key, "persona_id": f"p-{key}" if persona else "",
            "post_verbatim_text": tekst,
            "clauses": [{"ordinal": 1, "verbatim_text": tekst, "verbatim_sha256": sha256_text(tekst)}]}


def ledger(rows, policy="exclusion-2018-20-v1"):
    return {"schema_version": "evidence-eligibility-1.0", "policy_version": policy,
            "rules_script_sha256": H, "source_id": "s", "restore_identity": "r", "records": rows}


def row(r, status="eligible"):
    return {"status": status, "reasons": [] if status == "eligible" else ["principal_living"],
            "record_input_sha256": canonical_record_input(r)}


def setup(*keys):
    records = {k: rec(k) for k in keys}
    return records, {k: row(r) for k, r in records.items()}


def test_alle_eligible_i_kodepunkt_orden():
    records, rows = setup("V-2", "I-10", "I-9", "IV-1")
    assert eligible_keys(records, ledger(rows)) == ["I-10", "I-9", "IV-1", "V-2"]


def test_en_1939_ledger_laeses():
    """Trin 6c-1 Task 5: udvalget læser en exclusion-1939-v1-ledger med 1939's årsager."""
    records, rows = setup("I-1", "I-2", "I-3")
    rows["I-2"] = dict(row(records["I-2"], "excluded"), reasons=["no_published_persona"])
    rows["I-3"] = dict(row(records["I-3"], "excluded"), reasons=["relative_living", "text_year_ge_1915"])
    assert eligible_keys(records, ledger(rows, "exclusion-1939-v1")) == ["I-1"]


def test_en_2018_20_aarsag_i_en_1939_ledger_afvises():
    from evidence_runner import EligibilityError
    records, rows = setup("I-1", "I-2")
    rows["I-2"] = dict(row(records["I-2"], "excluded"), reasons=["spouse_undated_marriage"])
    with pytest.raises(EligibilityError, match="LEDGER_REASON_UNKNOWN"):
        eligible_keys(records, ledger(rows, "exclusion-1939-v1"))


def test_excluded_kommer_ikke_med():
    records, rows = setup("I-1", "I-2")
    rows["I-2"] = row(records["I-2"], "excluded")
    assert eligible_keys(records, ledger(rows)) == ["I-1"]


def test_runner_input_uden_ledger_raekke_kommer_ikke_med():
    records, rows = setup("I-1")
    records["I-2"] = rec("I-2")
    assert eligible_keys(records, ledger(rows)) == ["I-1"]


def test_eligible_med_anden_inputhash_er_fejl_ikke_spring():
    records, rows = setup("I-1", "I-2")
    records["I-2"] = rec("I-2", "Født 1801.")
    with pytest.raises(SelectionLedgerMismatch, match="I-2:RECORD_INPUT_DRIFT"):
        eligible_keys(records, ledger(rows))


def test_eligible_uden_runner_input_er_fejl():
    records, rows = setup("I-1")
    rows["I-2"] = row(rec("I-2"))
    with pytest.raises(SelectionLedgerMismatch, match="I-2:RUNNER_INPUT_MISSING"):
        eligible_keys(records, ledger(rows))


def test_ordinalhul_er_fejl():
    records, rows = setup("I-1")
    records["I-1"]["clauses"][0]["ordinal"] = 2
    with pytest.raises(SelectionLedgerMismatch, match="I-1:ORDINAL_GAP"):
        eligible_keys(records, ledger(rows))


def test_forkert_klausulhash_er_fejl():
    records, rows = setup("I-1")
    records["I-1"]["clauses"][0]["verbatim_sha256"] = H
    with pytest.raises(SelectionLedgerMismatch, match="I-1:RUNNER_EXPORT_HASH_MISMATCH"):
        eligible_keys(records, ledger(rows))


def test_klausul_uden_for_helposten_er_fejl():
    records, rows = setup("I-1")
    fremmed = "Død 1900."
    records["I-1"]["clauses"][0].update(verbatim_text=fremmed, verbatim_sha256=sha256_text(fremmed))
    with pytest.raises(SelectionLedgerMismatch, match="I-1:CLAUSE_OUTSIDE_POST"):
        eligible_keys(records, ledger(rows))


def test_post_uden_klausuler_er_fejl():
    records, rows = setup("I-1")
    records["I-1"]["clauses"] = []
    with pytest.raises(SelectionLedgerMismatch, match="I-1:NO_CLAUSES"):
        eligible_keys(records, ledger(rows))


def test_record_key_feltet_skal_matche_noeglen():
    records, rows = setup("I-1")
    records["I-1"]["record_key"] = "I-2"
    with pytest.raises(SelectionLedgerMismatch, match="I-1:RECORD_KEY_MISMATCH"):
        eligible_keys(records, ledger(rows))


def test_manglende_persona_felt_er_fejl_men_tom_streng_er_ikke():
    records, rows = setup("I-1", "I-2")
    del records["I-1"]["persona_id"]
    records["I-2"]["persona_id"] = ""
    with pytest.raises(SelectionLedgerMismatch) as exc:
        eligible_keys(records, ledger(rows))
    assert "I-1:PERSONA_FIELD_MISSING" in str(exc.value)
    assert "I-2:" not in str(exc.value)


def test_manglende_posttekst_er_fejl():
    records, rows = setup("I-1")
    records["I-1"]["post_verbatim_text"] = ""
    with pytest.raises(SelectionLedgerMismatch, match="I-1:RECORD_INPUT_TEXT_MISSING"):
        eligible_keys(records, ledger(rows))


def test_flere_fejl_samles_i_een_besked():
    records, rows = setup("I-1", "I-2", "I-3")
    records["I-1"]["clauses"][0]["ordinal"] = 2
    del records["I-3"]
    with pytest.raises(SelectionLedgerMismatch) as exc:
        eligible_keys(records, ledger(rows))
    assert str(exc.value) == "SELECTION_LEDGER_MISMATCH I-1:ORDINAL_GAP I-3:RUNNER_INPUT_MISSING"


def test_nul_eligible_er_fejl():
    records, rows = setup("I-1")
    rows["I-1"] = row(records["I-1"], "excluded")
    with pytest.raises(SelectionLedgerMismatch, match="NO_ELIGIBLE"):
        eligible_keys(records, ledger(rows))


def test_bundter_nulpolstret_og_sidste_kort():
    b = bundle([f"K{i:02d}" for i in range(7)], 3)
    assert list(b) == ["bundt_01", "bundt_02", "bundt_03"]
    assert b["bundt_03"] == ["K06"]
    assert sum(b.values(), []) == [f"K{i:02d}" for i in range(7)]


def test_bundtstoerrelse_skal_vaere_positiv():
    with pytest.raises(ValueError):
        bundle(["K1"], 0)


def test_definitionen_afhaenger_af_bundtstoerrelsen():
    assert definition_sha256(25) != definition_sha256(26)
    assert len(definition_sha256(25)) == 64


def test_udvalget_har_manifestets_felter_og_taeller_uden_persona():
    records, rows = setup("I-1", "I-2", "I-3")
    records["I-3"] = rec("I-3", persona=False)
    rows["I-3"] = row(records["I-3"])
    u = build_selection(records, ledger(rows), "f" * 64, 2)
    assert u["records"] == ["I-1", "I-2", "I-3"]
    assert u["bundter"] == {"bundt_01": ["I-1", "I-2"], "bundt_02": ["I-3"]}
    assert u["record_input_sha256"] == {k: canonical_record_input(r) for k, r in records.items()}
    assert u["strata_version"] == "eligible-all-v1"
    assert u["strata_sha256"] == definition_sha256(2)
    assert u["ledger_sha256"] == "f" * 64
    assert u["uden_persona"] == ["I-3"]
    assert u["ikke_i_ledger"] == []


def test_udvalget_taeller_runner_input_uden_ledger_raekke():
    records, rows = setup("I-1")
    records["I-9"] = rec("I-9")
    assert build_selection(records, ledger(rows), "f" * 64, 25)["ikke_i_ledger"] == ["I-9"]


def test_udvalget_kan_bygges_til_et_gyldigt_runner_manifest():
    records, rows = setup(*[f"I-{i:02d}" for i in range(60)])
    u = build_selection(records, ledger(rows), "f" * 64, 25)
    profil = {"profile_id": "p", "version": "1", "prompt_file": "x.md", "prompt_sha256": H,
              "model_id": "m"}
    m = build_manifest(u, dagsvaerk="test", restore_identity="r", ledger_sha256="f" * 64,
                       profil=profil, claims_schema_sha256=H, code_sha256=H,
                       codex_cli_version="0.0.0")
    assert list(bundles_of(m)) == ["bundt_01", "bundt_02", "bundt_03"]
    assert m["strata_sha256"] == u["strata_sha256"]
    verify_runner_manifest(m, m["manifest_sha256"])


def _skriv(tmp_path, records, rows):
    ri, lg = tmp_path / "ri.json", tmp_path / "lg.json"
    ri.write_text(json.dumps({"records": records}), encoding="utf-8")
    lg.write_text(json.dumps(ledger(rows)), encoding="utf-8")
    return ri, lg


def test_cli_skriver_0600_og_ok_linje(tmp_path, monkeypatch, capsys):
    records, rows = setup("I-1", "I-2")
    ri, lg = _skriv(tmp_path, records, rows)
    out = tmp_path / "udvalg.json"
    monkeypatch.setattr("sys.argv", ["x", "--runner-input", str(ri), "--ledger", str(lg),
                                     "--out", str(out)])
    assert main() == 0
    assert stat.S_IMODE(out.stat().st_mode) == 0o600
    assert "UDVALG_OK records=2 bundter=1 uden_persona=0 ikke_i_ledger=0" in capsys.readouterr().out
    assert json.loads(out.read_text(encoding="utf-8"))["records"] == ["I-1", "I-2"]


def test_cli_fejl_skriver_ingen_fil(tmp_path, monkeypatch, capsys):
    records, rows = setup("I-1")
    records["I-1"]["clauses"] = []
    ri, lg = _skriv(tmp_path, records, rows)
    out = tmp_path / "udvalg.json"
    monkeypatch.setattr("sys.argv", ["x", "--runner-input", str(ri), "--ledger", str(lg),
                                     "--out", str(out)])
    assert main() == 1
    assert not out.exists()
    assert "I-1:NO_CLAUSES" in capsys.readouterr().out
