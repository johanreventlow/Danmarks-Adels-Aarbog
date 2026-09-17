"""Komparatoren for klausul-projektionen (spec §11.1, vej C). Alt syntetisk."""
from __future__ import annotations

import copy
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compare_clause_evidence_projection as cp

BATCH = "00000000-0000-4000-8000-00000000b001"


def H(char: str) -> str:
    return char * 64


def clause(ordinal, post_from, post_to, abs_from, abs_to, flags, sha, classification="record_text"):
    return {"ordinal": ordinal, "char_from": post_from, "char_to": post_to,
            "rendition_char_from": abs_from, "rendition_char_to": abs_to,
            "classification": classification, "flags": list(flags), "verbatim_sha256": sha}


def operation(key, parent_sha, clauses):
    return {"element_id": f"clause-evidence:{key}", "dependency_class": "clause_evidence",
            "source_record_key": key, "rendition_content_sha256": H("c"),
            "rendition_projection_sha256": H("e"), "parent_verbatim_sha256": parent_sha,
            "clause_rules_version": "rules-v1", "segmenter_version": "seg-v1",
            "ledger_sha256": H("d"), "gap_charset": [" "], "clauses": clauses}


def rehash(m):
    m["manifest_content_sha256"] = cp.compute_manifest_sha256(m)
    return m


def manifest():
    return rehash({
        "source": {"id": 1, "profile_id": "p", "profile_sha256": H("b")},
        "provenance": {"ledger_file_sha256": H("a")},
        "expected_counts": {"source_evidence": 0, "person_creates": 0,
                            "canonical_delta": 0, "clause_evidence": 2},
        "operations": [
            operation("R1", H("2"), [clause(1, 0, 10, 100, 110, [], H("3")),
                                     clause(2, 11, 20, 111, 121, ["short_clause"], H("4"))]),
            operation("R2", H("5"), [clause(1, 0, 5, 200, 205, [], H("6"))]),
        ],
    })


IDENTITY = {"database_name": "fixture", "system_identifier_sha256": H("7")}
TARGET = cp.target_sha256(IDENTITY)
OCCURRENCE = {"R1": "o1", "R2": "o2", "R9": "o9"}


def projection(clauses=(), events=()):
    return {
        "schema_version": cp.PROJECTION_SCHEMA,
        "source_id": 1,
        "database_target_identity": dict(IDENTITY),
        "source_records": [{"record_key": "R1"}, {"record_key": "R2"}, {"record_key": "R9"}],
        "source_anchors": [{"record_key": k, "occurrence_key": v} for k, v in OCCURRENCE.items()],
        "narrative_bindings": [{"record_key": "R1", "narrative_id": 7, "status": "published"}],
        "narrative_sha256": [{"narrative_id": 7, "sha256": H("8")}],
        "persons": [{"person_id": 42}],
        "clauses": [copy.deepcopy(c) for c in clauses],
        "clause_evidence_events": [copy.deepcopy(e) for e in events],
        "neutral_sha256": {t: H("0") for t in cp.NEUTRAL_HASH_TABLES},
        "anon_sha256": {t: H("1") for t in cp.ANON_HASH_TABLES},
    }


RUN = "00000000-0000-4000-8000-0000000000e1"


def written_rows(m, batch=BATCH):
    rules = {op["source_record_key"]: op["clause_rules_version"] for op in m["operations"]}
    rows = []
    for (key, ordinal), row in sorted(cp.expected_clauses(m).items()):
        rows.append(dict(row, occurrence_key=OCCURRENCE[key], decided_by_kind="machine",
                         observation_id=f"obs-{key}-{ordinal}", row_sha256=H("a"),
                         disposition_history_sha256=H("b"), run_id=RUN,
                         run_matches_profile=True, extraction_method_matches_profile=True,
                         disposition_evidence={"batch_id": batch, "element_id": f"clause-evidence:{key}",
                                               "manifest_sha256": m["manifest_content_sha256"],
                                               "clause_rules_version": rules[key]},
                         disposition_evidence_keys=["batch_id", "clause_rules_version", "element_id", "manifest_sha256"],
                         extraction_method=f"clause_segment_v1:{rules[key]}",
                         run_input_sha256=m["manifest_content_sha256"], run_batch_id=batch,
                         same_occurrence_as_parent=True, parent_is_root=True,
                         pages_match_parent=True, quality_matches_parent=True))
    return rows


def events_for(m, status="finalized", batch=BATCH):
    return [{"batch_id": batch, "manifest_sha256": m["manifest_content_sha256"], "batch_status": status,
             "profile_id": m["source"]["profile_id"], "profile_sha256": m["source"]["profile_sha256"],
             "row_sha256": H("e"),
             "element_id": op["element_id"], "source_record_key": op["source_record_key"]}
            for op in m["operations"]]


OLD_EVENT = {"batch_id": "00000000-0000-4000-8000-00000000b0dd", "manifest_sha256": H("c"),
             "batch_status": "finalized", "profile_id": "p", "profile_sha256": H("b"),
             "row_sha256": H("f"), "element_id": "clause-evidence:R9", "source_record_key": "R9"}


def applied(m):
    return projection(written_rows(m), events_for(m))


def run(m, before, after, target=TARGET, allow_empty=frozenset()):
    return cp.compare(m, before, after, target, allow_empty)


def no_go(m, before, after, target=TARGET, allow_empty=frozenset()):
    with pytest.raises(cp.ProjectionError) as e:
        run(m, before, after, target, allow_empty)
    return e.value


def foreign(ordinal=1, sha=H("f"), record_key="R9", occurrence_key="o9", observation_id="obs-foreign",
            row_sha=H("c"), history_sha=H("d")):
    return {"observation_id": observation_id, "row_sha256": row_sha, "disposition_history_sha256": history_sha,
            "run_id": "run-old", "run_matches_profile": True, "extraction_method_matches_profile": True,
            "record_key": record_key, "occurrence_key": occurrence_key, "clause_ordinal": ordinal,
            "char_from": 900, "char_to": 910, "post_char_from": 0, "post_char_to": 10,
            "classification": "record_text", "flags": [], "verbatim_sha256": sha,
            "parent_verbatim_sha256": H("e"), "disposition": "afventer_fortolkning",
            "disposition_version": 1, "decided_by_kind": "machine",
            "disposition_evidence": {"batch_id": "old"}, "disposition_evidence_keys": ["batch_id"],
            "extraction_method": "x:y",
            "run_input_sha256": H("9"), "run_batch_id": "old",
            "same_occurrence_as_parent": True, "parent_is_root": True,
            "pages_match_parent": True, "quality_matches_parent": True}


# ---- match og manifest -------------------------------------------------------

def test_match_counts_and_reports_target():
    m = manifest()
    result = run(m, projection(), applied(m))
    assert result["status"] == "match"
    assert result["scope"] == cp.RESULT_SCOPE
    assert result["database_target_sha256"] == TARGET
    assert result["batch_id"] == BATCH
    assert result["counts"]["records"] == 2
    assert result["counts"]["clauses"] == 3
    assert result["counts"]["dispositions"] == {"afventer_fortolkning": 2, "maskinelt_flagget": 1}
    assert result["counts"]["neutral_lists"]["source_records"] == 3


def test_compute_manifest_sha256_matches_builder_formula():
    import hashlib
    import json
    m = manifest()
    body = {k: v for k, v in m.items() if k != "manifest_content_sha256"}
    expected = hashlib.sha256(json.dumps(body, ensure_ascii=False, sort_keys=True,
                                         separators=(",", ":")).encode("utf-8")).hexdigest()
    assert cp.compute_manifest_sha256(m) == expected


def test_expected_clauses_maps_offsets_and_disposition_rule():
    m = manifest()
    m["operations"][1]["clauses"][0].update(classification="structural_header", flags=["x"])
    rows = cp.expected_clauses(rehash(m))
    r1 = rows[("R1", 1)]
    assert (r1["char_from"], r1["char_to"]) == (100, 110)
    assert (r1["post_char_from"], r1["post_char_to"]) == (0, 10)
    assert r1["parent_verbatim_sha256"] == H("2")
    assert r1["disposition_version"] == 1
    assert rows[("R1", 2)]["disposition"] == "maskinelt_flagget"
    assert rows[("R2", 1)]["disposition"] == "strukturel"


@pytest.mark.parametrize("mutate", [
    lambda m: m["provenance"].update(ledger_file_sha256=H("9")),
    lambda m: m["operations"][0].update(ledger_sha256=H("9")),
    lambda m: m["operations"][0].update(gap_charset=[" ", "\t"]),
    lambda m: m["source"].update(profile_sha256=H("9")),
])
def test_non_row_field_changed_without_rehash_is_hash_mismatch(mutate):
    m = manifest()
    after = applied(m)
    mutate(m)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_MANIFEST_HASH_MISMATCH"


@pytest.mark.parametrize("mutate", [
    lambda m: m["expected_counts"].update(clause_evidence=3),
    lambda m: m["expected_counts"].update(person_creates=1),
    lambda m: m["operations"][0]["clauses"][1].update(ordinal=3),
    lambda m: m["operations"][0].update(element_id="clause-evidence:R2"),
    lambda m: m["operations"][0].update(dependency_class="source_evidence"),
    lambda m: m["operations"][0].update(extra=1),
    lambda m: m["operations"][0]["clauses"][0].update(verbatim_text="tekst"),
    lambda m: m["source"].update(extra=1),
    lambda m: m.update(extra=1),
    lambda m: m.update(operations=[]),
])
def test_manifest_shape_invalid(mutate):
    m = manifest()
    after = applied(manifest())
    mutate(m)
    rehash(m)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_MANIFEST_INVALID"


def test_manifest_hash_not_hex_is_invalid():
    m = manifest()
    m["manifest_content_sha256"] = "x"
    assert no_go(m, projection(), applied(manifest())).code == "CLAUSE_PROJECTION_MANIFEST_INVALID"


def test_manifest_without_provenance_is_allowed():
    m = manifest()
    del m["provenance"]
    rehash(m)
    assert run(m, projection(), applied(m))["status"] == "match"


# ---- mål og kilde -----------------------------------------------------------

def test_source_mismatch():
    m = manifest()
    m["source"]["id"] = 2
    rehash(m)
    assert no_go(m, projection(), applied(m)).code == "CLAUSE_PROJECTION_SOURCE_MISMATCH"


def test_target_mismatch_between_before_and_after():
    m = manifest()
    after = applied(m)
    after["database_target_identity"]["database_name"] = "other"
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_TARGET_MISMATCH"


def test_consistent_but_unexpected_target_is_no_go():
    m = manifest()
    before, after = projection(), applied(m)
    for p in (before, after):
        p["database_target_identity"]["database_name"] = "restore-kopi"
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_TARGET_UNEXPECTED"


def test_record_unknown():
    m = manifest()
    before, after = projection(), applied(m)
    for p in (before, after):
        p["source_records"] = [r for r in p["source_records"] if r["record_key"] != "R2"]
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_RECORD_UNKNOWN"


# ---- neutralitet ------------------------------------------------------------

@pytest.mark.parametrize("name,field,value", [
    ("source_records", "record_key", "R8"),
    ("source_anchors", "occurrence_key", "oX"),
    ("narrative_bindings", "status", "draft"),
    ("narrative_sha256", "sha256", H("1")),
    ("persons", "person_id", 43),
])
def test_neutral_list_value_change_is_drift(name, field, value):
    m = manifest()
    after = applied(m)
    after[name][-1] = dict(after[name][-1], **{field: value})
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_NEUTRALITY_DRIFT"
    assert err.details["lists"] == [name]


@pytest.mark.parametrize("name", ["source_records", "source_anchors", "narrative_bindings",
                                  "narrative_sha256", "persons"])
def test_neutral_row_with_extra_key_is_shape_invalid(name):
    m = manifest()
    after = applied(m)
    after[name][-1] = dict(after[name][-1], marker=1)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_SHAPE_INVALID"


@pytest.mark.parametrize("table", ["fact", "source_record_anchor_event", "clause_disposition_other_sources"])
def test_neutral_table_hash_change_is_canonical_drift(table):
    m = manifest()
    after = applied(m)
    after["neutral_sha256"][table] = H("2")
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_CANONICAL_DRIFT"
    assert err.details["tables"] == [table]


def test_anon_hash_change_is_anon_drift():
    m = manifest()
    after = applied(m)
    after["anon_sha256"]["person"] = H("2")
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_ANON_DRIFT"
    assert err.details["tables"] == ["person"]


def test_list_order_does_not_matter():
    m = manifest()
    after = applied(m)
    after["source_records"].reverse()
    after["clauses"].reverse()
    assert run(m, projection(), after)["status"] == "match"


# ---- klausuler --------------------------------------------------------------

def test_missing_clause_is_drift():
    m = manifest()
    after = applied(m)
    after["clauses"] = [c for c in after["clauses"] if c["record_key"] != "R2"]
    after["clause_evidence_events"] = events_for(m)
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_DRIFT"
    assert err.details["missing"] == [["R2", 1]]


def test_extra_clause_is_drift():
    m = manifest()
    after = applied(m)
    after["clauses"].append(dict(after["clauses"][0], clause_ordinal=3, observation_id="obs-extra"))
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_DRIFT"
    assert err.details["extra"] == [["R1", 3]]


@pytest.mark.parametrize("field,value", [
    ("post_char_to", 9), ("char_from", 101), ("verbatim_sha256", H("9")),
    ("parent_verbatim_sha256", H("9")), ("flags", ["other"]),
    ("disposition", "strukturel"), ("disposition_version", 2), ("classification", "structural_header"),
])
def test_field_mismatch_names_field_without_values(field, value):
    m = manifest()
    after = applied(m)
    after["clauses"][0][field] = value
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_DRIFT"
    assert err.details["mismatched"][0]["fields"] == [field]
    assert str(value) not in str(err.details)


@pytest.mark.parametrize("field,value", [
    ("decided_by_kind", "human"),
    ("disposition_evidence", {"batch_id": BATCH}),
    ("disposition_evidence_keys", ["batch_id", "clause_rules_version", "element_id", "manifest_sha256", "note"]),
    ("extraction_method", "clause_segment_v1:other-rules"),
    ("run_input_sha256", H("9")),
    ("run_batch_id", "00000000-0000-4000-8000-00000000b002"),
    ("same_occurrence_as_parent", False),
    ("parent_is_root", False),
    ("pages_match_parent", False),
    ("quality_matches_parent", False),
    ("run_matches_profile", False),
    ("extraction_method_matches_profile", False),
])
def test_writer_invariant_violation(field, value):
    m = manifest()
    after = applied(m)
    after["clauses"][0][field] = value
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_WRITER_INVARIANT_INVALID"
    assert err.details["invariants"] == [field]


def test_target_clauses_from_two_runs_is_invariant_invalid():
    m = manifest()
    after = applied(m)
    after["clauses"][0]["run_id"] = "run-andet"
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_WRITER_INVARIANT_INVALID"
    assert err.details["invariants"] == ["run_id"]


def test_preexisting_clauses_for_manifest_record_is_no_go():
    m = manifest()
    assert no_go(m, applied(m), applied(m)).code == "CLAUSE_PROJECTION_PREEXISTING"


def test_unchanged_foreign_clause_is_match():
    m = manifest()
    before = projection([foreign()])
    after = applied(m)
    after["clauses"].append(foreign())
    assert run(m, before, after)["status"] == "match"


def test_changed_foreign_clause_is_foreign_drift():
    m = manifest()
    before = projection([foreign()])
    after = applied(m)
    after["clauses"].append(foreign(sha=H("1")))
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


@pytest.mark.parametrize("change", [{"row_sha": H("1")}, {"history_sha": H("1")}])
def test_foreign_clause_full_row_or_history_change_is_foreign_drift(change):
    m = manifest()
    before = projection([foreign()])
    after = applied(m)
    after["clauses"].append(foreign(**change))
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


def test_new_clause_on_unanchored_occurrence_is_foreign_drift():
    m = manifest()
    after = applied(m)
    after["clauses"].append(foreign(record_key=None, occurrence_key="o-uden-anker"))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


def test_removed_clause_on_unanchored_occurrence_is_foreign_drift():
    m = manifest()
    before = projection([foreign(record_key=None, occurrence_key="o-uden-anker")])
    assert no_go(m, before, applied(m)).code == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


# ---- batch-binding ----------------------------------------------------------

def test_wrong_manifest_hash_on_events_is_binding_invalid():
    m = manifest()
    after = applied(m)
    for ev in after["clause_evidence_events"]:
        ev["manifest_sha256"] = H("9")
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_open_batch_is_binding_invalid():
    m = manifest()
    after = projection(written_rows(m), events_for(m, status="open"))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_events_split_over_two_batches_is_binding_invalid():
    m = manifest()
    events = events_for(m)
    events[1]["batch_id"] = "00000000-0000-4000-8000-00000000b002"
    after = projection(written_rows(m), events)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_missing_event_is_binding_invalid():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].pop()
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_event_already_before_is_binding_invalid():
    m = manifest()
    assert no_go(m, projection(events=events_for(m)), applied(m)).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_unrelated_new_clause_event_is_binding_invalid():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append(dict(OLD_EVENT, batch_id=BATCH, manifest_sha256=H("9")))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


@pytest.mark.parametrize("field,value", [("profile_sha256", H("9")), ("profile_id", "andet")])
def test_batch_bound_to_other_profile_is_binding_invalid(field, value):
    m = manifest()
    events = events_for(m)
    for ev in events:
        ev[field] = value
    assert no_go(m, projection(), projection(written_rows(m), events)).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_old_event_preserved_is_match():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append(dict(OLD_EVENT))
    assert run(m, projection(events=[OLD_EVENT]), after)["status"] == "match"


@pytest.mark.parametrize("mutate", [
    lambda events: events.remove(OLD_EVENT),
    lambda events: events.__setitem__(events.index(OLD_EVENT), dict(OLD_EVENT, batch_status="reversed")),
    # Ændret payload/after_sha256/created_at i den gamle hændelse: kun helrækkehashen flytter sig.
    lambda events: events.__setitem__(events.index(OLD_EVENT), dict(OLD_EVENT, row_sha256=H("1"))),
])
def test_old_event_removed_or_changed_is_history_drift(mutate):
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append(dict(OLD_EVENT))
    mutate(after["clause_evidence_events"])
    assert no_go(m, projection(events=[OLD_EVENT]), after).code == "CLAUSE_PROJECTION_EVENT_HISTORY_DRIFT"


def test_duplicate_event_identity_is_no_go():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append(dict(after["clause_evidence_events"][0], batch_status="open"))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_DUPLICATE_ROW"


# ---- form -------------------------------------------------------------------

@pytest.mark.parametrize("name", ["source_records", "source_anchors", "narrative_bindings",
                                  "narrative_sha256", "persons"])
def test_empty_list_is_no_go_unless_allowed(name):
    m = manifest()
    before, after = projection(), applied(m)
    before[name], after[name] = [], []
    if name in ("source_records", "source_anchors"):
        assert no_go(m, before, after, allow_empty=frozenset({name})).code == "CLAUSE_PROJECTION_EMPTY_LIST"
        return
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_EMPTY_LIST"
    result = run(m, before, after, allow_empty=frozenset({name}))
    assert result["counts"]["allowed_empty"] == [name]


def test_duplicate_row_is_no_go():
    m = manifest()
    after = applied(m)
    after["persons"].append({"person_id": 42})
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_DUPLICATE_ROW"


def test_duplicate_clause_identity_is_no_go():
    m = manifest()
    after = applied(m)
    after["clauses"].append(dict(after["clauses"][0], verbatim_sha256=H("9")))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_DUPLICATE_ROW"


@pytest.mark.parametrize("mutate", [
    lambda p: p.update(extra=1),
    lambda p: p.update(schema_version="daa-evidence-production-snapshot-v1"),
    lambda p: p.update(source_id="1"),
    lambda p: p["neutral_sha256"].pop("fact"),
    lambda p: p["anon_sha256"].pop("person"),
    lambda p: p["anon_sha256"].update(relation=H("1")),
    lambda p: p["clauses"].append({"record_key": "R9"}),
    lambda p: p["clauses"][0].update(same_occurrence_as_parent="true"),
    lambda p: p["clause_evidence_events"][0].pop("batch_id"),
    lambda p: p["database_target_identity"].update(system_identifier_sha256="x"),
])
def test_shape_invalid(mutate):
    m = manifest()
    after = applied(m)
    mutate(after)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_SHAPE_INVALID"


# ---- CLI tests ---------------------------------------------------------------

import json as _json
import os
import stat
import subprocess

SCRIPT = Path(__file__).resolve().parent / "compare_clause_evidence_projection.py"


def write(tmp_path, name, data):
    path = tmp_path / name
    path.write_text(_json.dumps(data), encoding="utf-8")
    return path


def run_cli(*args):
    env = {k: v for k, v in os.environ.items() if k != "NODE_OPTIONS"}
    return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                          capture_output=True, text=True, env=env)


def cli_inputs(tmp_path, after=None):
    m = manifest()
    return (write(tmp_path, "manifest.json", m), write(tmp_path, "before.json", projection()),
            write(tmp_path, "after.json", after if after is not None else applied(m)))


def cli(tmp_path, mp, bp, ap, report="report.json", target=TARGET, *extra):
    return run_cli("--manifest", mp, "--before", bp, "--after", ap,
                   "--expect-target-sha256", target, "--report", tmp_path / report, *extra)


def test_cli_match_writes_private_report_with_input_hashes(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = cli(tmp_path, mp, bp, ap)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    terminal = _json.loads(proc.stdout)
    assert terminal["status"] == "match" and "details" not in terminal
    assert terminal["database_target_sha256"] == TARGET
    import hashlib
    assert terminal["input_sha256"]["after"] == hashlib.sha256(ap.read_bytes()).hexdigest()
    report = tmp_path / "report.json"
    assert stat.S_IMODE(report.stat().st_mode) == 0o600
    assert _json.loads(report.read_text())["status"] == "match"


def test_cli_no_go_keeps_record_keys_out_of_stdout(tmp_path):
    m = manifest()
    after = applied(m)
    after["clauses"][0]["post_char_to"] = 9
    mp, bp, ap = cli_inputs(tmp_path, after)
    proc = cli(tmp_path, mp, bp, ap)
    assert proc.returncode == 1
    assert _json.loads(proc.stdout) == {"status": "no_go", "code": "CLAUSE_PROJECTION_DRIFT"}
    assert "R1" not in proc.stdout and "R1" not in proc.stderr
    report = _json.loads((tmp_path / "report.json").read_text())
    assert report["details"]["mismatched"][0]["record_key"] == "R1"


def test_cli_unexpected_target_is_no_go(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = cli(tmp_path, mp, bp, ap, "report.json", H("9"))
    assert proc.returncode == 1
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_TARGET_UNEXPECTED"


def test_cli_rejects_malformed_expected_target(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = cli(tmp_path, mp, bp, ap, "report.json", "prod")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_EXPECTED_TARGET_INVALID"
    assert not (tmp_path / "report.json").exists()


def test_cli_refuses_existing_report(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    (tmp_path / "report.json").write_text("x")
    proc = cli(tmp_path, mp, bp, ap)
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_REPORT_EXISTS"
    assert (tmp_path / "report.json").read_text() == "x"


def test_cli_refuses_report_inside_repository(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    report = SCRIPT.parent / "must-not-exist-clause-projection-report.json"
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap,
                   "--expect-target-sha256", TARGET, "--report", report)
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_REPORT_IN_REPOSITORY"
    assert not report.exists()


def test_cli_rejects_unknown_allow_empty(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = cli(tmp_path, mp, bp, ap, "report.json", TARGET, "--allow-empty", "source_records")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_ALLOW_EMPTY_INVALID"


def test_cli_unreadable_input_is_usage_error(tmp_path):
    mp, bp, _ = cli_inputs(tmp_path)
    bad = tmp_path / "bad.json"
    bad.write_text("{", encoding="utf-8")
    proc = cli(tmp_path, mp, bp, bad)
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_INPUT_UNREADABLE"
    assert not (tmp_path / "report.json").exists()


def test_cli_report_dir_missing(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap,
                   "--expect-target-sha256", TARGET, "--report", tmp_path / "findes-ikke" / "r.json")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_REPORT_DIR_MISSING"
    assert not (tmp_path / "findes-ikke").exists()


def test_cli_arguments_missing(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap, "--report", tmp_path / "r.json")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_ARGUMENTS_MISSING"
    assert not (tmp_path / "r.json").exists()


def test_cli_print_manifest_sha256(tmp_path):
    m = manifest()
    unhashed = {k: v for k, v in m.items() if k != "manifest_content_sha256"}
    path = write(tmp_path, "unhashed.json", unhashed)
    proc = run_cli("--print-manifest-sha256", path)
    assert proc.returncode == 0
    assert proc.stdout.strip() == m["manifest_content_sha256"]
