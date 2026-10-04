import copy
import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import transfer_pack as tp  # noqa: E402

FX = Path(__file__).resolve().parents[4] / "tests" / "fixtures" / "transfer-pack"


def load(name):
    return json.loads((FX / name).read_text(encoding="utf-8"))


def build(**over):
    args = dict(export=load("export.json"), fingerprints=load("fingerprints.json"), digests=load("digests.json"),
                baseline=load("baseline.json"), record_check=load("record-check.json"), classification=load("classification.json"),
                classification_sha256="ded0", receipt=load("dump-receipt.json"),
                manifest_content_sha256="80f3", ledger_sha256="e620")
    args.update(over)
    return tp.build_pack(**args)


def test_build_counts_and_fields():
    decisions, manifest = build()
    assert [d["interpretation_key"] for d in decisions] == ["k-1", "k-2", "k-3"]
    assert set(decisions[0]) == {"interpretation_key", "restore_interpretation_id", "expected_version", "status",
                                 "decision_fingerprint", "evidence"}
    assert decisions[0]["expected_version"] == 1
    assert decisions[1]["decision_fingerprint"] == "f2"
    assert manifest["counts_by_method_status"] == {"human-sheet-kontrol-v1|accepted": 1,
                                                   "human-sheet-kontrol-v1|unresolved": 1,
                                                   "machine-corroboration-v1|accepted": 1}
    assert manifest["n_accepted"] == 2 and manifest["accepted_keys"] == ["k-1", "k-3"]
    assert manifest["keyed_classification"] == {"k-1": ["MATCH", 7], "k-2": ["REAL_DIFF", None], "k-3": ["MATCH", 7]}
    assert manifest["record_check"] == {"n_no_record": 0, "n_multi_record": 0}
    assert len(manifest["actor_sha256"]) == 64


def test_pack_sha_is_canonical_and_excludes_itself():
    _, m = build()
    again = dict(m)
    assert tp.pack_sha256(again) == m["pack_sha256"]
    shuffled = dict(reversed(list(m.items())))
    assert tp.pack_sha256(shuffled) == m["pack_sha256"]
    changed = dict(m, ledger_sha256="other")
    assert tp.pack_sha256(changed) != m["pack_sha256"]


def test_duplicate_key_is_error():
    ex = load("export.json")
    ex["decisions"].append(copy.deepcopy(ex["decisions"][0]))
    with pytest.raises(tp.PackError, match="PACK_DUPLICATE_KEY"):
        build(export=ex)


def test_decision_without_fingerprint_is_error():
    fp = load("fingerprints.json")
    del fp["k-3"]
    with pytest.raises(tp.PackError, match="PACK_FINGERPRINT_MISSING"):
        build(fingerprints=fp)


def test_counts_must_match_digests():
    dg = load("digests.json")
    dg["n_decided"] = 4
    with pytest.raises(tp.PackError, match="PACK_COUNT_MISMATCH"):
        build(digests=dg)


def test_record_check_ambiguous_is_error():
    with pytest.raises(tp.PackError, match="PACK_RECORD_AMBIGUOUS"):
        build(record_check={"n_no_record": 1, "n_multi_record": 0})
    with pytest.raises(tp.PackError, match="PACK_RECORD_AMBIGUOUS"):
        build(record_check={"n_no_record": 0, "n_multi_record": 2})


def test_drift_fields_constant():
    assert tp.DRIFT_BASELINE_FIELDS == ("canonical_sha256", "clause_set_sha256", "schema_sha256")


def test_exactly_one_actor():
    ex = load("export.json")
    ex["decisions"][2]["decided_by"] = "u-2"
    with pytest.raises(tp.PackError, match="PACK_ACTOR_COUNT"):
        build(export=ex)


def test_classification_must_map_to_keys():
    cl = load("classification.json")
    cl["items"].append({"interpretation_id": "v-9", "version": 1, "predicate": "x", "class": "MATCH", "assertion_id": 1})
    with pytest.raises(tp.PackError, match="PACK_CLASSIFICATION_UNMAPPED"):
        build(classification=cl)


def test_classification_duplicate_is_error():
    cl = load("classification.json")
    cl["items"].append(dict(cl["items"][0]))
    with pytest.raises(tp.PackError, match="PACK_CLASSIFICATION_DUPLICATE"):
        build(classification=cl)


def test_machine_decision_must_be_match_with_same_assertion():
    cl = load("classification.json")
    cl["items"][2]["class"] = "REAL_DIFF"
    with pytest.raises(tp.PackError, match="PACK_MACHINE_NOT_MATCH"):
        build(classification=cl)
    cl = load("classification.json")
    cl["items"][2]["assertion_id"] = 8
    with pytest.raises(tp.PackError, match="PACK_MACHINE_NOT_MATCH"):
        build(classification=cl)


def test_human_decision_must_be_classified():
    cl = load("classification.json")
    del cl["items"][1]
    with pytest.raises(tp.PackError, match="PACK_HUMAN_UNCLASSIFIED"):
        build(classification=cl)


def test_baseline_must_have_drift_fields():
    bl = load("baseline.json")
    del bl["schema_sha256"]
    with pytest.raises(tp.PackError, match="PACK_BASELINE_INCOMPLETE"):
        build(baseline=bl)


def test_evidence_none_is_pack_error():
    ex = load("export.json")
    ex["decisions"][0]["evidence"] = None
    with pytest.raises(tp.PackError, match="PACK_EVIDENCE_INVALID"):
        build(export=ex)


def test_universe_counts_must_match_digests():
    fp = load("fingerprints.json")
    del fp["k-4"]
    with pytest.raises(tp.PackError, match="PACK_COUNT_MISMATCH"):
        build(fingerprints=fp)
    ex = load("export.json")
    del ex["key_by_v1_id"]["v-4"]
    with pytest.raises(tp.PackError, match="PACK_COUNT_MISMATCH"):
        build(export=ex)


def test_state_mixed_cases():
    _, m = build()
    full = load("digests.json")
    partial = dict(full, n_decided=1, decided_by_method_status={"human-sheet-kontrol-v1|accepted": 1},
                   n_bindings=0, binding_digest=tp.EMPTY_SHA)
    assert tp.classify_state(partial, m) == "MIXED"
    bind_only = dict(full, n_decided=0, decided_by_method_status={}, decision_digest=tp.EMPTY_SHA)
    assert tp.classify_state(bind_only, m) == "MIXED"
    changed = dict(full, proposal_digest="X", n_decided=0, decided_by_method_status={},
                   decision_digest=tp.EMPTY_SHA, n_bindings=0, binding_digest=tp.EMPTY_SHA)
    assert tp.classify_state(changed, m) == "MIXED"


def test_state_cli_rejects_tampered_manifest(tmp_path):
    _, m = build()
    m["n_accepted"] = 99
    mf = tmp_path / "m.json"
    mf.write_text(json.dumps(m))
    res = subprocess.run([sys.executable, str(Path(tp.__file__)), "state", "--digests", str(FX / "digests.json"),
                          "--pack-manifest", str(mf)], capture_output=True, text=True)
    assert res.returncode == 1 and "PACK_SHA_MISMATCH" in res.stdout


def test_state_classifier_five_states():
    _, m = build()
    full = load("digests.json")
    empty = {"n_interpretations": 0, "proposal_digest": tp.EMPTY_SHA, "n_decided": 0,
             "decided_by_method_status": {}, "decision_digest": tp.EMPTY_SHA, "n_bindings": 0,
             "binding_digest": tp.EMPTY_SHA}
    proposed = dict(full, n_decided=0, decided_by_method_status={}, decision_digest=tp.EMPTY_SHA, n_bindings=0,
                    binding_digest=tp.EMPTY_SHA)
    decided = dict(full, n_bindings=0, binding_digest=tp.EMPTY_SHA)
    assert tp.classify_state(empty, m) == "EMPTY"
    assert tp.classify_state(proposed, m) == "PROPOSED"
    assert tp.classify_state(decided, m) == "DECIDED"
    assert tp.classify_state(full, m) == "COMPLETE"
    assert tp.classify_state(dict(full, proposal_digest="X"), m) == "MIXED"
    assert tp.classify_state(dict(decided, decision_digest="X"), m) == "MIXED"
    assert tp.classify_state(dict(empty, n_bindings=1), m) == "MIXED"


def test_cli_prints_no_notes_or_values(tmp_path):
    out = tmp_path / "pack"
    out.mkdir(mode=0o700)
    cmd = [sys.executable, str(Path(tp.__file__)), "build"]
    for flag, name in (("--export", "export.json"), ("--fingerprints", "fingerprints.json"),
                       ("--digests", "digests.json"), ("--baseline", "baseline.json"), ("--record-check", "record-check.json"),
                       ("--classification", "classification.json"), ("--dump-receipt", "dump-receipt.json")):
        cmd += [flag, str(FX / name)]
    cmd += ["--manifest-content-sha256", "80f3", "--ledger-sha256", "e620", "--out-dir", str(out)]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    assert "titel i navn" not in res.stdout + res.stderr
    assert "PACK_OK" in res.stdout
    for f in ("decisions-keyed.json", "pack-manifest.json"):
        assert (out / f).stat().st_mode & 0o777 == 0o600
    dec = (out / "decisions-keyed.json").read_bytes()
    man = json.loads((out / "pack-manifest.json").read_text(encoding="utf-8"))
    import hashlib
    assert hashlib.sha256(dec).hexdigest() == man["decisions_keyed_sha256"]


def test_cli_rejects_open_out_dir(tmp_path):
    out = tmp_path / "pack"
    out.mkdir(mode=0o755)
    out.chmod(0o755)
    cmd = [sys.executable, str(Path(tp.__file__)), "build"]
    for flag, name in (("--export", "export.json"), ("--fingerprints", "fingerprints.json"),
                       ("--digests", "digests.json"), ("--baseline", "baseline.json"),
                       ("--record-check", "record-check.json"),
                       ("--classification", "classification.json"), ("--dump-receipt", "dump-receipt.json")):
        cmd += [flag, str(FX / name)]
    cmd += ["--manifest-content-sha256", "80f3", "--ledger-sha256", "e620", "--out-dir", str(out)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 1 and "PACK_OUT_DIR_MODE" in res.stdout


def test_machine_assertion_id_must_be_int_on_classification_side():
    for bad in ("7", 7.0, True, None):
        cl = load("classification.json")
        cl["items"][2]["assertion_id"] = bad
        ex = load("export.json")
        if bad is True:  # True == 1 i Python; evidensen skal ikke kunne matche en bool
            ex["decisions"][2]["evidence"]["assertion_id"] = 1
        with pytest.raises(tp.PackError, match="PACK_MACHINE_NOT_MATCH"):
            build(classification=cl, export=ex)


ACTOR = "a4700000-0000-4000-8000-000000000001"


def test_decide_sql_shape():
    decisions, manifest = build()
    sql = tp.decide_sql(decisions, manifest)
    assert sql.startswith("\\set ON_ERROR_STOP on\n\\set QUIET on\nBEGIN;\n"
                          "SELECT set_config('daa.src', :'src', true) \\g /dev/null\n")
    assert ":src" not in sql.replace(":'src'", "")
    assert sql.rstrip().endswith("\\echo 'TRANSFER_07_OK afgørelser=3'")
    assert sql.count("COMMIT;") == 1 and sql.index("COMMIT;") > sql.rindex("DECISION_DIGEST_MISMATCH")
    order = ["TRANSFER_STATE_NOT_PROPOSED", "CLAUSE_SET_DRIFT", "MACHINE_PREMISE_DRIFT",
             "DECISION_FINGERPRINT_MISMATCH", "DECISION_KEY_UNRESOLVED", "TRANSFER_ACTOR_MISMATCH",
             "red_decide_interpretation", "DECISION_DIGEST_MISMATCH"]
    pos = [sql.index(code) for code in order]
    assert pos == sorted(pos)
    assert sql.index("SET LOCAL ROLE authenticated") < sql.index("red_decide_interpretation")
    assert sql.index("red_decide_interpretation") < sql.index("RESET ROLE")
    assert sql.index("RESET ROLE") < sql.index("SET CONSTRAINTS ALL IMMEDIATE") < sql.rindex(
        "interpretation_transfer_digests.sql")
    assert manifest["pack_sha256"] in sql and manifest["actor_sha256"] in sql
    # Aktør-id'et og kildevariablen må ikke nå stdout; ingen sessionsindstilling må sættes LOCAL.
    assert "SELECT set_config('request.jwt.claim.sub', :'actor', true) \\g /dev/null" in sql
    for guc in ("TimeZone", "extra_float_digits", "IntervalStyle", "DateStyle", "search_path"):
        assert f"SET LOCAL {guc}" not in sql and f"'{guc}'" not in sql
    # Præmissen og nøgleopslaget er afgrænset til kilden.
    assert sql.count("current_setting('daa.src')::bigint") >= 2
    assert "count(DISTINCT p->>'k')" in sql
    assert "p->>'fp' IS NULL" in sql


def test_decide_sql_rejects_other_versions():
    decisions, manifest = build()
    decisions[0]["expected_version"] = 2
    with pytest.raises(tp.PackError, match="PACK_EXPECTED_VERSION"):
        tp.decide_sql(decisions, manifest)


def test_bind_sql_shape():
    _, manifest = build()
    sql = tp.bind_sql(manifest)
    assert sql.startswith("\\set ON_ERROR_STOP on\n\\set QUIET on\nBEGIN;\n")
    order = ["TRANSFER_STATE_NOT_DECIDED", "BIND_SCOPE_DRIFT", "interpretation_promotion_targets_scoped.sql",
             "TRANSFER_ACTOR_MISMATCH", "BIND_NOT_ELIGIBLE", "red_promote_interpretations_batch",
             "BINDING_DIGEST_MISMATCH"]
    pos = [sql.index(code) for code in order]
    assert pos == sorted(pos)
    assert '["k-1","k-3"]' in sql
    assert sql.index("RESET ROLE") < sql.index("SET CONSTRAINTS ALL IMMEDIATE") < sql.rindex(
        "interpretation_transfer_digests.sql")
    assert "SELECT set_config('request.jwt.claim.sub', :'actor', true) \\g /dev/null" in sql
    assert sql.rstrip().endswith("\\echo 'TRANSFER_08_OK bindinger=2'")


def _write_pack(tmp_path):
    out = tmp_path / "pack"
    out.mkdir(mode=0o700)
    decisions, manifest = build()
    (out / "decisions-keyed.json").write_text(tp.canonical(decisions), encoding="utf-8")
    (out / "pack-manifest.json").write_text(tp.canonical(manifest) + "\n", encoding="utf-8")
    return out, manifest


@pytest.mark.parametrize("cmd,tag", [("decide-sql", "DECIDE_SQL_OK"), ("bind-sql", "BIND_SQL_OK")])
def test_sql_cli_writes_private_and_prints_only_hashes(tmp_path, cmd, tag):
    pdir, manifest = _write_pack(tmp_path)
    out = tmp_path / "x.sql"
    res = subprocess.run([sys.executable, str(Path(tp.__file__)), cmd, "--pack-dir", str(pdir), "--out", str(out)],
                         capture_output=True, text=True)
    assert res.returncode == 0, res.stdout
    assert res.stdout.startswith(tag) and manifest["pack_sha256"] in res.stdout
    assert "titel i navn" not in res.stdout + res.stderr and "u-1" not in res.stdout
    assert out.stat().st_mode & 0o777 == 0o600
    sql = out.read_text(encoding="utf-8")
    assert f"sha256={tp.sha256_text(sql)}" in res.stdout


def test_sql_cli_rejects_tampered_decisions(tmp_path):
    pdir, _ = _write_pack(tmp_path)
    f = pdir / "decisions-keyed.json"
    f.write_text(f.read_text(encoding="utf-8") + " ", encoding="utf-8")  # samme JSON, andre bytes
    res = subprocess.run([sys.executable, str(Path(tp.__file__)), "decide-sql", "--pack-dir", str(pdir),
                          "--out", str(tmp_path / "x.sql")], capture_output=True, text=True)
    assert res.returncode == 1 and "PACK_DECISIONS_SHA_MISMATCH" in res.stdout
    assert not (tmp_path / "x.sql").exists()


def test_sql_cli_rejects_tampered_manifest(tmp_path):
    pdir, manifest = _write_pack(tmp_path)
    manifest["n_accepted"] = 9
    (pdir / "pack-manifest.json").write_text(tp.canonical(manifest), encoding="utf-8")
    res = subprocess.run([sys.executable, str(Path(tp.__file__)), "bind-sql", "--pack-dir", str(pdir),
                          "--out", str(tmp_path / "x.sql")], capture_output=True, text=True)
    assert res.returncode == 1 and "PACK_SHA_MISMATCH" in res.stdout


def test_decide_sql_rejects_dollar_tag_in_notes():
    decisions, manifest = build()
    decisions[1]["evidence"]["note"] = "x $p$ y"
    with pytest.raises(tp.PackError, match="PACK_DOLLAR_TAG"):
        tp.decide_sql(decisions, manifest)
    decisions[1]["evidence"]["note"] = "koster $5"
    tp.decide_sql(decisions, manifest)
