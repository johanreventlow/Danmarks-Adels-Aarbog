from __future__ import annotations

import copy

import pytest

import amend_structural_context_1939 as subject


def source_export():
    return {
        "schema_version": 1,
        "skaeringer": [
            {"char_offset": 10, "oprindelse": "bruger"},
            {"char_offset": 20, "oprindelse": "bruger"},
        ],
        "udeladelser": [{"char_from": 12, "char_to": 20}],
    }


def decisions():
    return {
        "schema_version": "1.0",
        "source_export_sha256": "a" * 64,
        "decision_batch": "structural-1",
        "remove_cuts": [20],
        "add_cuts": [12, 21],
        "remove_omissions": [{"char_from": 12, "char_to": 20}],
        "structural_references": [{"char_from": 12, "char_to": 21}],
    }


def test_amends_only_declared_geometry_and_preserves_input():
    original = source_export()
    before = copy.deepcopy(original)

    result = subject.amend_export(original, decisions(), export_sha256="a" * 64)

    assert original == before
    assert [item["char_offset"] for item in result["skaeringer"]] == [10, 12, 21]
    assert result["udeladelser"] == []
    assert result["strukturelle_henvisninger"] == [{
        "char_from": 12,
        "char_to": 21,
        "record_kind": "structural_context",
        "person_creation": "forbidden",
    }]
    assert result["derived_from"] == {
        "source_export_sha256": "a" * 64,
        "decision_batch": "structural-1",
    }


@pytest.mark.parametrize("mutation", ["hash", "cut", "omission"])
def test_rejects_drift_or_missing_declared_geometry(mutation):
    export = source_export()
    decision = decisions()
    digest = "a" * 64
    if mutation == "hash":
        digest = "b" * 64
    elif mutation == "cut":
        decision["remove_cuts"] = [19]
    else:
        decision["remove_omissions"] = [{"char_from": 11, "char_to": 20}]

    with pytest.raises(subject.AmendmentError):
        subject.amend_export(export, decision, export_sha256=digest)
