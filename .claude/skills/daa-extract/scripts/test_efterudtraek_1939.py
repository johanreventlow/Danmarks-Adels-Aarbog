import copy
import hashlib
import json
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).parent
sys.path.insert(0, str(SCRIPTS))

import efterudtraek_1939 as pipeline


def rec(key, narrative="Gift med Anna 1700. Født 1690.", **extra):
    return {
        "record_key": key, "narrative": narrative, "lokal_id": key,
        "_v2_lokal_id": key, "linje": None, "nr": None, "nr_label": None,
        "boern": None, "_boern_link": None, "_boern_ref": None,
        "facts": [], "aegteskaber": [], **extra,
    }


def output(batch_id, *records, attempt=1):
    return {"batch_id": batch_id, "model": "gpt-5.6-terra", "attempt": attempt,
            "records": list(records)}


def fact(kind, raw, span=None):
    return {"faktatype": kind, "date_raw": raw, "kilde_span": span or raw}


def marriage(ordinal, name, span, **extra):
    return {"ordinal": ordinal, "partner_navn": name, "kilde_span": span, **extra}


def test_prepare_is_deterministic_and_preserves_completed_output(tmp_path):
    baseline = tmp_path / "baseline.json"
    baseline.write_text(json.dumps([rec("a"), rec("b"), rec("c")]), encoding="utf-8")
    run = tmp_path / "run"
    (run / "output").mkdir(parents=True)
    completed = run / "output" / "batch-000.json"
    completed.write_text("finished", encoding="utf-8")

    first = pipeline.prepare(baseline, run, batch_size=2)
    second = pipeline.prepare(baseline, run, batch_size=2)

    assert first == second == 2
    assert completed.read_text(encoding="utf-8") == "finished"
    assert json.loads((run / "input" / "batch-000.json").read_text()) == {
        "batch_id": "batch-000",
        "records": [
            {"index": 0, "record_key": "a", "narrative": rec("a")["narrative"]},
            {"index": 1, "record_key": "b", "narrative": rec("b")["narrative"]},
        ],
    }


def test_check_rejects_unicode_or_whitespace_nonexact_spans(tmp_path):
    baseline = [rec("a", "Gift med A\u030aase 1700.")]
    batch = {"batch-000": ["a"]}
    bad = output("batch-000", {"record_key": "a", "facts": [fact("død", "1700", "Gift med Åse 1700.")], "aegteskaber": []})

    issues = pipeline.validate_wrapper(bad, batch, {"a": baseline[0]})

    assert any("kilde_span" in issue.reason for issue in issues)


def test_date_validation_calls_derive_date_info_and_requires_life_date(monkeypatch):
    calls = []
    monkeypatch.setattr(pipeline.validate, "derive_date_info", lambda raw: calls.append(raw) or {
        "date_min": "1700-01-01", "date_max": "1700-12-31", "qualifier": None,
        "certainty": None, "calendar": None})
    base = rec("a", "Født 1700.")
    good = output("batch-000", {"record_key": "a", "facts": [fact("fødsel", "1700", "Født 1700")], "aegteskaber": []})
    assert not pipeline.validate_wrapper(good, {"batch-000": ["a"]}, {"a": base})
    assert calls == ["1700"]
    bad = output("batch-000", {"record_key": "a", "facts": [{"faktatype": "fødsel", "kilde_span": "Født"}], "aegteskaber": []})
    assert any("date_raw" in x.reason for x in pipeline.validate_wrapper(bad, {"batch-000": ["a"]}, {"a": base}))


def test_date_validation_allows_all_null_but_blocks_parser_errors_and_contradictions(monkeypatch):
    base = rec("a", "Født 1700.")
    wrapped = output("batch-000", {"record_key": "a", "facts": [fact("fødsel", "1700", "Født 1700")], "aegteskaber": []})
    monkeypatch.setattr(pipeline.validate, "derive_date_info", lambda _: {
        "date_min": None, "date_max": None, "qualifier": None, "certainty": None, "calendar": None})
    assert not pipeline.validate_wrapper(wrapped, {"batch-000": ["a"]}, {"a": base})
    monkeypatch.setattr(pipeline.validate, "derive_date_info", lambda _: {
        "date_min": "1699-01-01", "date_max": None, "qualifier": None, "certainty": None, "calendar": None})
    assert any("modsiger" in x.reason for x in pipeline.validate_wrapper(wrapped, {"batch-000": ["a"]}, {"a": base}))
    monkeypatch.setattr(pipeline.validate, "derive_date_info", lambda _: (_ for _ in ()).throw(ValueError("bad")))
    assert any("fejlede" in x.reason for x in pipeline.validate_wrapper(wrapped, {"batch-000": ["a"]}, {"a": base}))


def test_merge_retains_old_facts_puts_new_first_and_rejects_duplicates():
    old = rec("a", facts=[fact("titel", None, "Gift"), fact("død", "1700", "1700")])
    new = {"record_key": "a", "facts": [fact("fødsel", "1690", "1690")], "aegteskaber": []}
    merged, stats = pipeline.merge_record(old, new)
    assert [x["faktatype"] for x in merged["facts"]] == ["fødsel", "titel", "død"]
    assert stats["retained_facts"] == 2
    duplicate = {**new, "facts": [fact("fødsel", "1690"), fact("fødsel", "1690")]}
    with pytest.raises(pipeline.PipelineError, match="dublet"):
        pipeline.merge_record(old, duplicate)


def test_new_fact_type_replaces_legacy_variant_but_other_old_types_are_retained():
    old = rec("a", facts=[
        fact("død", "var død 1700", "var død 1700"),
        fact("titel", None, "Gift"),
    ])
    new = {"record_key": "a", "facts": [fact("død", "1700", "1700")], "aegteskaber": []}

    merged, stats = pipeline.merge_record(old, new)

    assert merged["facts"] == [fact("død", "1700", "1700"), fact("titel", None, "Gift")]
    assert stats["replaced_facts"] == 1
    assert stats["retained_facts"] == 1


def test_merge_supplements_marriage_but_preserves_conflicts_and_requires_evidence_for_new_union():
    old = rec("a", aegteskaber=[marriage(1, "Anna", "Gift med Anna", sted=None)])
    supplemented, stats = pipeline.merge_record(old, {"record_key": "a", "facts": [], "aegteskaber": [marriage(1, "Anna", "Gift med Anna", sted="København")]})
    assert supplemented["aegteskaber"][0]["sted"] == "København"
    assert stats["supplemented_fields"] == 1
    conflict, stats = pipeline.merge_record(old, {"record_key": "a", "facts": [], "aegteskaber": [marriage(1, "Birgit", "Gift med Birgit")]})
    assert conflict["aegteskaber"] == old["aegteskaber"]
    assert stats["marriage_conflicts"] == 1
    accepted, _ = pipeline.merge_record(rec("a"), {"record_key": "a", "facts": [], "aegteskaber": [marriage(1, "Anna", "Gift med Anna")]})
    assert len(accepted["aegteskaber"]) == 1
    rejected, stats = pipeline.merge_record(rec("a"), {"record_key": "a", "facts": [], "aegteskaber": [marriage(1, "Anna", "Anna")]})
    assert not rejected["aegteskaber"] and stats["rejected_unions"] == 1


def test_merge_keeps_immutable_fields():
    old = rec("a", linje="I", nr=7, boern={"nr_range": [1, 2]})
    merged, _ = pipeline.merge_record(old, {"record_key": "a", "facts": [], "aegteskaber": [], "linje": "II", "boern": {}})
    assert merged["linje"] == "I"
    assert merged["boern"] == {"nr_range": [1, 2]}


def test_verify_requires_exact_546_active_register_keys_and_manifest(tmp_path):
    records = [rec(f"k{i}") for i in range(546)]
    result = tmp_path / "clean_1939_v3.json"
    result.write_text(json.dumps(records, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    manifest = {"artefakt": result.name, "sha256": hashlib.sha256(result.read_bytes()).hexdigest(),
                "rene": 546, "flaggede": 0, "andel_rene": 1.0}
    Path(str(result) + ".manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    registry = tmp_path / "registry.json"
    registry.write_text(json.dumps({"poster": [{"book_post_id": f"k{i}", "udgave": "1939", "side": "1", "lokal_id": str(i), "status": "aktiv"} for i in range(546)]}), encoding="utf-8")
    assert pipeline.verify_result(records, records, result, registry) == []
    bad = copy.deepcopy(records)
    bad[0]["record_key"] = "unknown"
    assert any("register" in x for x in pipeline.verify_result(records, bad, result, registry))


def test_wrapper_rejects_nonobjects_missing_required_fields_and_wrong_types():
    base = rec("a", "Gift med Anna 1700.")
    malformed = output("batch-000", {"record_key": "a", "facts": ["not-an-object"], "aegteskaber": []})
    assert any("object" in x.reason for x in pipeline.validate_wrapper(malformed, {"batch-000": ["a"]}, {"a": base}))
    missing = output("batch-000", {"record_key": "a", "facts": [{"kilde_span": "Gift"}], "aegteskaber": [{"partner_navn": "Anna", "kilde_span": "Gift med Anna"}]})
    reasons = [x.reason for x in pipeline.validate_wrapper(missing, {"batch-000": ["a"]}, {"a": base})]
    assert any("faktatype" in reason for reason in reasons)
    assert any("ordinal" in reason for reason in reasons)
    wrong = output("batch-000", {"record_key": "a", "facts": [{"faktatype": 7, "kilde_span": "Gift"}], "aegteskaber": [{"ordinal": "1", "kilde_span": "Gift"}]})
    assert any("type" in x.reason for x in pipeline.validate_wrapper(wrong, {"batch-000": ["a"]}, {"a": base}))


def test_wrapper_rejects_fact_types_outside_requested_extraction_layer():
    base = rec("a", "nævnes 1700")
    wrapped = output("batch-000", {
        "record_key": "a",
        "facts": [fact("floruit", "1700", "nævnes 1700")],
        "aegteskaber": [],
    })

    issues = pipeline.validate_wrapper(wrapped, {"batch-000": ["a"]}, {"a": base})

    assert any("faktatype" in issue.reason for issue in issues)


def test_g_dot_is_clear_marriage_evidence():
    accepted, stats = pipeline.merge_record(rec("a"), {"record_key": "a", "facts": [], "aegteskaber": [marriage(1, "Anna", "g. med Anna")]})
    assert accepted["aegteskaber"][0]["partner_navn"] == "Anna"
    assert stats["accepted_unions"] == 1


def test_check_writes_retry_for_malformed_json_and_nonobject_output(tmp_path):
    baseline = tmp_path / "baseline.json"
    baseline.write_text(json.dumps([rec("a")]), encoding="utf-8")
    run = tmp_path / "run"
    (run / "input").mkdir(parents=True)
    (run / "output").mkdir()
    (run / "input" / "batch-000.json").write_text(json.dumps({"batch_id": "batch-000", "records": [{"index": 0, "record_key": "a", "narrative": rec("a")["narrative"]}]}), encoding="utf-8")
    (run / "output" / "batch-000.json").write_text("{broken", encoding="utf-8")
    issues = pipeline.check(baseline, run, expected_count=1)
    assert any("ugyldig JSON" in x.reason for x in issues)
    assert json.loads((run / "retry.json").read_text())[0]["batch_id"] == "batch-000"
    (run / "output" / "batch-000.json").write_text("[]", encoding="utf-8")
    issues = pipeline.check(baseline, run, expected_count=1)
    assert any("wrapper" in x.reason for x in issues)


def test_supplement_counts_unequal_nonempty_fields_including_nested_conflicts():
    old = rec("a", aegteskaber=[marriage(1, "Anna", "Gift med Anna", sted="A", partner_foedsel={"date_raw": "1700", "sted": "A"})])
    merged, stats = pipeline.merge_record(old, {"record_key": "a", "facts": [], "aegteskaber": [marriage(1, "Anna", "Gift med Anna", sted="B", partner_foedsel={"date_raw": "1700", "sted": "B"})]})
    assert merged["aegteskaber"][0]["sted"] == "A"
    assert merged["aegteskaber"][0]["partner_foedsel"]["sted"] == "A"
    assert stats["marriage_field_conflicts"] == 2


def test_verify_proves_old_unions_and_nonempty_values_are_preserved(tmp_path):
    records = [rec(f"k{i}", aegteskaber=[marriage(1, "Anna", "Gift med Anna", sted="A")]) for i in range(546)]
    result = tmp_path / "clean_1939_v3.json"
    result.write_text(json.dumps(records, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    manifest = {"artefakt": result.name, "sha256": hashlib.sha256(result.read_bytes()).hexdigest(), "rene": 546, "flaggede": 0, "andel_rene": 1.0}
    Path(str(result) + ".manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    registry = tmp_path / "registry.json"
    registry.write_text(json.dumps({"poster": [{"book_post_id": f"k{i}", "udgave": "1939", "side": "1", "lokal_id": str(i), "status": "aktiv"} for i in range(546)]}), encoding="utf-8")
    altered = copy.deepcopy(records)
    altered[0]["aegteskaber"][0]["sted"] = "B"
    assert any("ægteskab" in x for x in pipeline.verify_result(records, altered, result, registry))


def test_merge_preserves_and_reports_legacy_provenance_gap(tmp_path, monkeypatch):
    baseline = tmp_path / "baseline.json"
    baseline.write_text(json.dumps([rec("a", "Gyldig tekst", facts=[{"faktatype": "titel", "kilde_span": "mangler"}])]), encoding="utf-8")
    run = tmp_path / "run"
    (run / "output").mkdir(parents=True)
    (run / "output" / "batch-000.json").write_text(json.dumps(output("batch-000", {"record_key": "a", "facts": [], "aegteskaber": []})), encoding="utf-8")
    (run / "retry.json").write_text("[]", encoding="utf-8")
    (run / "provenance.json").write_text(json.dumps({
        "reused_quarantine_batches": [], "fresh_terra_batches": ["batch-000"],
    }), encoding="utf-8")
    monkeypatch.setattr(pipeline, "check", lambda *_args, **_kwargs: [])
    result = tmp_path / "v3.json"

    stats = pipeline.merge(baseline, run, result, tmp_path / "report.md")

    assert json.loads(result.read_text())[0]["facts"] == [{"faktatype": "titel", "kilde_span": "mangler"}]
    assert stats["legacy_provenance_issues"] == 1


def test_verify_detects_result_that_is_not_the_deterministic_merge(tmp_path, monkeypatch):
    baseline = [rec(f"k{i}") for i in range(546)]
    baseline_path = tmp_path / "baseline.json"
    baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
    run = tmp_path / "run"
    (run / "output").mkdir(parents=True)
    wrapper = output("batch-000", *[
        {"record_key": record["record_key"], "facts": [], "aegteskaber": []}
        for record in baseline
    ])
    (run / "output" / "batch-000.json").write_text(json.dumps(wrapper), encoding="utf-8")
    result = copy.deepcopy(baseline)
    result[0]["facts"] = [fact("død", "1700", "1700")]
    result_path = tmp_path / "v3.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    Path(str(result_path) + ".manifest.json").write_text(json.dumps({
        "artefakt": result_path.name,
        "sha256": hashlib.sha256(result_path.read_bytes()).hexdigest(),
        "rene": 546, "flaggede": 0, "andel_rene": 1.0,
    }), encoding="utf-8")
    registry = tmp_path / "registry.json"
    registry.write_text(json.dumps({"poster": [
        {"book_post_id": f"k{i}", "udgave": "1939", "status": "aktiv"}
        for i in range(546)
    ]}), encoding="utf-8")
    monkeypatch.setattr(pipeline, "check", lambda *_args, **_kwargs: [])

    errors = pipeline.verify(baseline_path, run, result_path, registry)

    assert any("deterministisk merge" in error for error in errors)


def test_check_rejects_boolean_attempt_and_nonstring_unhashable_record_key_to_retry(tmp_path):
    baseline = tmp_path / "baseline.json"
    baseline.write_text(json.dumps([rec("a")]), encoding="utf-8")
    run = tmp_path / "run"
    (run / "input").mkdir(parents=True)
    (run / "output").mkdir()
    (run / "input" / "batch-000.json").write_text(json.dumps({"batch_id": "batch-000", "records": [{"index": 0, "record_key": "a", "narrative": rec("a")["narrative"]}]}), encoding="utf-8")
    bad = output("batch-000", {"record_key": [], "facts": [], "aegteskaber": []}, attempt=True)
    (run / "output" / "batch-000.json").write_text(json.dumps(bad), encoding="utf-8")

    issues = pipeline.check(baseline, run, expected_count=1)

    reasons = [issue.reason for issue in issues]
    assert any("attempt" in reason for reason in reasons)
    assert any("record_key" in reason for reason in reasons)
    assert json.loads((run / "retry.json").read_text())


def test_coverage_reports_every_requested_fact_type_and_marriage():
    records = [
        rec("a", facts=[fact("fødsel", "1690"), fact("dåb", "1691")]),
        rec("b", facts=[fact("død", "1700"), fact("begravelse", "1701"),
                        fact("titel", None, "Gift")],
            aegteskaber=[marriage(1, "Anna", "Gift med Anna")]),
    ]

    assert pipeline._coverage(records) == {
        "fødsel": 1, "dåb": 1, "død": 1, "begravelse": 1,
        "titel": 1, "ægteskab": 1,
    }


def test_batch_provenance_requires_exact_partition(tmp_path):
    wrappers = [{"batch_id": f"batch-{i:03d}"} for i in range(3)]
    (tmp_path / "provenance.json").write_text(json.dumps({
        "reused_quarantine_batches": ["batch-000"],
        "fresh_terra_batches": ["batch-001", "batch-002"],
    }), encoding="utf-8")

    assert pipeline._batch_provenance(tmp_path, wrappers) == (1, 2)
    (tmp_path / "provenance.json").write_text(json.dumps({
        "reused_quarantine_batches": ["batch-000"],
        "fresh_terra_batches": ["batch-001"],
    }), encoding="utf-8")
    with pytest.raises(pipeline.PipelineError, match="proveniens"):
        pipeline._batch_provenance(tmp_path, wrappers)
