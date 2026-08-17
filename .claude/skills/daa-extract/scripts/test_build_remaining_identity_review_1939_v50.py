from __future__ import annotations

import copy

import pytest

import build_remaining_identity_review_1939_v50 as subject


def _hashes() -> dict[str, str]:
    return {
        "source_persona_sha256": "a" * 64,
        "import_preview_sha256": "b" * 64,
        "database_preview_sha256": "c" * 64,
        "database_only_profiles_sha256": "d" * 64,
        "clean_sha256": "e" * 64,
        "boundary_materialization_sha256": "f" * 64,
        "calamari_sha256": "0" * 64,
    }


def _source(key: str, start: int, text: str) -> dict:
    return {
        "new_record_key": key,
        "pending_gates": ["source_persona", "identity", "interpretation_provenance"],
        "person_creation": "forbidden",
        "source_span": {"char_from": start, "char_to": start + len(text)},
        "verbatim_text": text,
    }


def fixture_inputs() -> dict:
    text_a = "Anna Marie Jensen, f. 1800.\n"
    text_b = "Iven Reventlow, død 1701.\n"
    text_c = "Claus uden identitet.\n"
    subjects = [
        _source("new-c", 80, text_c),
        _source("new-a", 10, text_a),
        _source("new-b", 45, text_b),
    ]
    calamari_text = " " * 10 + text_a + " " * (45 - 10 - len(text_a)) + text_b + " " * (80 - 45 - len(text_b)) + text_c
    import_preview = {
        "schema_version": "1939-v50-import-preview-v1",
        "preview_gate": "GO", "reimport_gate": "NO-GO",
        "canonical_mutations_authorized": False,
        "source": {"edition": "1939", "input_hashes": {"calamari_sha256": "0" * 64}},
        "counts": {"mapped_existing": 2, "genuinely_new_pending": 3},
        "mapped_existing": [
            {"baseline_record_key": "old-anna", "new_record_key": "mapped-a"},
            {"baseline_record_key": "old-iven", "new_record_key": "mapped-i"},
        ],
        "genuinely_new_pending": copy.deepcopy(subjects),
    }
    database_preview = {
        "schema_version": "1939-v50-database-preview-v1",
        "canonical_mutations_authorized": False, "dry_run_gate": "NO-GO",
        "reimport_gate": "NO-GO", "database": {"transaction_read_only": "on"},
        "input_preview": {"schema_version": "1939-v50-import-preview-v1",
                          "input_hashes": {"calamari_sha256": "0" * 64}},
        "person_anchors": {
            "matched_count": 2, "missing_count": 0, "collision_count": 0,
            "matched": [
                {"baseline_record_key": "old-anna", "person_id": 101},
                {"baseline_record_key": "old-iven", "person_id": 102},
            ],
            "database_only_record_keys": ["db-only"],
            "database_only": [{"record_key": "db-only", "person_id": 201,
                               "visning_navn": "lven Reventlow"}],
        },
    }
    source_persona_v1 = {
        "schema_version": "1939-v50-source-persona-materialization-v1",
        "canonical_mutations_authorized": False, "database_write_authorized": False,
        "source_persona_materialization_gate": "GO", "database_write_gate": "NO-GO",
        "reimport_gate": "NO-GO", "counts": {"source_personas": 0,
                                                   "remaining_genuinely_new_pending": 3},
        "source": {"edition": "1939", "input_hashes": {
            "import_preview_sha256": "b" * 64, "database_preview_sha256": "c" * 64}},
        "source_personas": [], "remaining_genuinely_new_pending": copy.deepcopy(subjects),
    }
    database_only_profiles = {
        "schema_version": "1939-v50-identity-db-profiles-v1", "review_only": True,
        "canonical_mutations_authorized": False,
        "database": {"transaction_read_only": "on"},
        "input": {"database_preview_sha256": "c" * 64,
                  "import_preview_input_hashes": {"calamari_sha256": "0" * 64},
                  "declared_record_keys": ["db-only"]},
        "counts": {"profiles": 1},
        "profiles": [{"record_key": "db-only", "person_id": 201,
                      "display_name": "lven Reventlow", "staged": False,
                      "narratives": [], "facts": [{"fact_id": 1, "fact_type": "død",
                      "raw_value": "1701", "citation": None}], "relations": [], "families": []}],
    }
    clean_records = [
        {"record_key": "old-anna", "navn": "Anna Marie Jensen", "facts": [{
            "faktatype": "fødsel", "date_raw": "1800"}], "aegteskaber": []},
        {"record_key": "old-iven", "navn": "Iven Reventlow", "facts": [{
            "faktatype": "død", "date_raw": "1701"}], "aegteskaber": []},
    ]
    boundary_materialization = {
        "schema_version": "1.0", "source_record_review": {
            "schema_version": "1.0", "source_id": "1939",
            "rendition_id": "daa-1939-calamari-r6-clean", "rendition_sha256": "0" * 64,
            "records": [
                {"verbatim_text": text_a, "span": {"page_from": 502, "page_to": 502},
                 "source_anchor": {"char_from": 10, "char_to": 10 + len(text_a)}},
                {"verbatim_text": text_b, "span": {"page_from": 503, "page_to": 503},
                 "source_anchor": {"char_from": 45, "char_to": 45 + len(text_b)}},
                {"verbatim_text": text_c, "span": {"page_from": 504, "page_to": 504},
                 "source_anchor": {"char_from": 80, "char_to": 80 + len(text_c)}},
            ],
        },
    }
    return {
        "source_persona_v1": source_persona_v1, "import_preview": import_preview,
        "database_preview": database_preview, "database_only_profiles": database_only_profiles,
        "clean_records": clean_records, "boundary_materialization": boundary_materialization,
        "calamari_text": calamari_text, "input_hashes": _hashes(),
        "expected_subjects": 3, "expected_mapped_profiles": 2,
        "expected_database_only_profiles": 1,
    }


def test_builds_exact_source_order_context_and_page_evidence():
    result = subject.build_remaining_review(**fixture_inputs())
    assert [row["new_record_key"] for row in result["subjects"]] == ["new-a", "new-b", "new-c"]
    assert result["subjects"][1]["page_evidence"] == {"page_from": 503, "page_to": 503}
    assert result["subjects"][1]["previous_record"]["new_record_key"] == "new-a"
    assert result["subjects"][1]["next_record"]["new_record_key"] == "new-c"
    assert result["counts"]["subjects"] == 3
    assert result["counts"]["mapped_profiles"] == 2
    assert result["counts"]["database_only_profiles"] == 1
    assert result["review_gate"] == "GO"
    assert result["identity_decision_gate"] == "NO-GO"


def test_literal_candidate_and_normalized_presentation_only_and_later_record_evidence():
    values = fixture_inputs()
    text = values["source_persona_v1"]["remaining_genuinely_new_pending"][1]["verbatim_text"]
    later = _source("later-iven", 120, "Iven Reventlow omtales igen.\n")
    for container in (values["source_persona_v1"], values["import_preview"]):
        rows = container["remaining_genuinely_new_pending"] if "remaining_genuinely_new_pending" in container else container["genuinely_new_pending"]
        rows.append(later)
        if "counts" in container:
            key = "remaining_genuinely_new_pending" if "remaining_genuinely_new_pending" in container["counts"] else "genuinely_new_pending"
            container["counts"][key] = 4
    # Keep the source set closed at three review subjects; a later source record may
    # only enter through the full import record list.
    values["source_persona_v1"]["remaining_genuinely_new_pending"].pop()
    values["source_persona_v1"]["counts"]["remaining_genuinely_new_pending"] = 3
    values["import_preview"]["source_records"] = [later]
    values["import_preview"]["genuinely_new_pending"].pop()
    values["import_preview"]["counts"]["genuinely_new_pending"] = 3
    values["import_preview"]["source_records"].extend(values["import_preview"]["genuinely_new_pending"])
    values["calamari_text"] += " " * (120 - len(values["calamari_text"])) + later["verbatim_text"]
    values["boundary_materialization"]["source_record_review"]["records"].append({
        "verbatim_text": later["verbatim_text"], "span": {"page_from": 505, "page_to": 505},
        "source_anchor": later["source_span"],
    })
    result = subject.build_remaining_review(**values)
    iven = next(row for row in result["subjects"] if row["new_record_key"] == "new-b")
    candidate = next(row for row in iven["candidates"] if row["candidate_record_key"] == "old-iven")
    assert candidate["classification"] == "review_candidate"
    assert candidate["proposed_action"] == "unresolved"
    assert any(signal["kind"] == "literal_name" for signal in candidate["signals"])
    assert any(signal["kind"] == "literal_fact_value" and signal["text"] == "1701"
               for signal in candidate["signals"])
    assert iven["later_occurrences"] == [{
        "record_key": "later-iven", "source_span": {"char_from": 120, "char_to": 149},
        "signal": {"kind": "literal_name", "text": "Iven Reventlow",
                   "authoritative": True},
    }]
    presentation = next(row for row in iven["presentation_candidates"]
                        if row["candidate_record_key"] == "db-only")
    assert presentation["classification"] == "presentation_only"
    assert presentation["proposed_action"] == "unresolved"
    assert presentation["signals"][0]["authoritative"] is False
    assert presentation["signals"][0]["text"] == "Iven Reventlow"


def test_rejects_fabricated_later_source_record_before_it_can_be_authoritative():
    values = fixture_inputs()
    values["import_preview"]["source_records"] = [
        *values["import_preview"]["genuinely_new_pending"],
        _source("fabricated-later", 120, "Iven Reventlow omtales igen.\n"),
    ]
    with pytest.raises(subject.RemainingIdentityReviewError):
        subject.build_remaining_review(**values)


def test_later_occurrences_do_not_rescan_full_profile_pool(monkeypatch):
    calls = []
    original = subject._profile_signals

    def counted(source_text, profile):
        calls.append((source_text, profile["record_key"]))
        return original(source_text, profile)

    monkeypatch.setattr(subject, "_profile_signals", counted)
    subject.build_remaining_review(**fixture_inputs())
    # Three review subjects and a three-profile pool: candidate discovery only.
    # Later-occurrence discovery must reuse those discovered terms.
    assert len(calls) == 9


@pytest.mark.parametrize("mutation", [
    "source_persona_hash", "subjects_16", "subjects_18", "duplicate_subject",
    "verbatim_drift", "missing_boundary_page", "calamari_mismatch", "unknown_profile",
    "duplicate_person_id", "unknown_field", "write_authority",
])
def test_fails_closed_before_output_on_drift_or_authority(mutation, tmp_path):
    values = fixture_inputs()
    if mutation == "source_persona_hash":
        values["source_persona_v1"]["source"]["input_hashes"]["import_preview_sha256"] = "9" * 64
    elif mutation == "subjects_16":
        values["expected_subjects"] = 2
    elif mutation == "subjects_18":
        values["expected_subjects"] = 4
    elif mutation == "duplicate_subject":
        values["source_persona_v1"]["remaining_genuinely_new_pending"].append(
            copy.deepcopy(values["source_persona_v1"]["remaining_genuinely_new_pending"][0]))
        values["source_persona_v1"]["counts"]["remaining_genuinely_new_pending"] = 4
    elif mutation == "verbatim_drift":
        values["import_preview"]["genuinely_new_pending"][0]["verbatim_text"] = "drift\n"
    elif mutation == "missing_boundary_page":
        del values["boundary_materialization"]["source_record_review"]["records"][0]["span"]["page_from"]
    elif mutation == "calamari_mismatch":
        values["calamari_text"] = values["calamari_text"].replace("Anna", "Anne", 1)
    elif mutation == "unknown_profile":
        values["database_only_profiles"]["profiles"][0]["record_key"] = "unknown"
    elif mutation == "duplicate_person_id":
        values["database_preview"]["person_anchors"]["database_only"][0]["person_id"] = 102
        values["database_only_profiles"]["profiles"][0]["person_id"] = 102
    elif mutation == "unknown_field":
        values["source_persona_v1"]["unexpected"] = True
    elif mutation == "write_authority":
        values["database_preview"]["canonical_mutations_authorized"] = True
    with pytest.raises(subject.RemainingIdentityReviewError):
        subject.build_remaining_review(**values)
    output, report = tmp_path / "review.json", tmp_path / "review.md"
    assert not output.exists() and not report.exists()


@pytest.mark.parametrize("pool", ["matched", "database_only"])
def test_rejects_duplicate_canonical_person_id_within_a_profile_pool(pool):
    values = fixture_inputs()
    if pool == "matched":
        values["database_preview"]["person_anchors"]["matched"][1]["person_id"] = 101
    else:
        duplicate = copy.deepcopy(values["database_preview"]["person_anchors"]["database_only"][0])
        duplicate["record_key"] = "db-only-duplicate"
        values["database_preview"]["person_anchors"]["database_only"].append(duplicate)
        values["database_preview"]["person_anchors"]["database_only_record_keys"].append("db-only-duplicate")
        duplicate_profile = copy.deepcopy(values["database_only_profiles"]["profiles"][0])
        duplicate_profile["record_key"] = "db-only-duplicate"
        values["database_only_profiles"]["profiles"].append(duplicate_profile)
        values["database_preview"]["person_anchors"]["database_only"] [0]["person_id"] = 201
        values["expected_database_only_profiles"] = 2
        values["database_only_profiles"]["counts"]["profiles"] = 2
    with pytest.raises(subject.RemainingIdentityReviewError):
        subject.build_remaining_review(**values)


def test_cli_rejects_smaller_self_consistent_universe_before_opening_inputs():
    with pytest.raises(subject.RemainingIdentityReviewError):
        subject.main([
            "--source-personas", "missing-source.json", "--import-preview", "missing-import.json",
            "--database-preview", "missing-database.json", "--database-profiles", "missing-profiles.json",
            "--clean", "missing-clean.json", "--boundary-materialization", "missing-boundary.json",
            "--calamari", "missing-calamari.txt", "--output", "output.json", "--report", "report.md",
            "--expected-subjects", "3", "--expected-mapped-profiles", "2",
            "--expected-database-only-profiles", "1",
        ])
