from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

import pytest

import build_identity_review_1939_v50 as subject


def sha(value: object) -> str:
    if not isinstance(value, (bytes, str)):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True).encode()
    elif isinstance(value, str):
        value = value.encode()
    return hashlib.sha256(value).hexdigest()


def fixture_inputs():
    input_hashes = {letter: letter * 64 for letter in "abcdef"}
    anna_text = "Anna Marie Jensen, f. 12 Maj 1800. Gift med Peter Jensen.\n"
    claus_text = "Claus nævnes 1450.\n"
    else_text = "Else gift med Peter Jensen 12 Maj 1800.\n"
    anna_start = 10
    claus_start = anna_start + len(anna_text)
    else_start = claus_start + len(claus_text)
    import_preview = {
        "schema_version": "1939-v50-import-preview-v1",
        "preview_gate": "GO",
        "reimport_gate": "NO-GO",
        "canonical_mutations_authorized": False,
        "source": {"edition": "1939", "input_hashes": input_hashes},
        "counts": {"genuinely_new_pending": 3},
        "genuinely_new_pending": [
            {"new_record_key": "new-anna", "person_creation": "forbidden",
             "source_span": {"char_from": anna_start, "char_to": claus_start},
             "verbatim_text": anna_text},
            {"new_record_key": "new-claus", "person_creation": "forbidden",
             "source_span": {"char_from": claus_start, "char_to": else_start},
             "verbatim_text": claus_text},
            {"new_record_key": "new-else", "person_creation": "forbidden",
             "source_span": {"char_from": else_start, "char_to": else_start + len(else_text)},
             "verbatim_text": else_text},
        ],
    }
    database_preview = {
        "schema_version": "1939-v50-database-preview-v1",
        "input_preview": {"schema_version": "1939-v50-import-preview-v1",
                          "input_hashes": input_hashes},
        "database": {"transaction_read_only": "on"},
        "canonical_mutations_authorized": False,
        "person_anchors": {
            "database_only_record_keys": ["old-anna", "old-claus", "old-anna-2"],
            "database_only": [
                {"record_key": "old-anna", "person_id": 101, "visning_navn": "Anna Marie Jensen"},
                {"record_key": "old-claus", "person_id": 102, "visning_navn": "Claus"},
                {"record_key": "old-anna-2", "person_id": 103, "visning_navn": "Anna Marie Jensen"},
            ],
        },
        "reimport_gate": "NO-GO",
    }
    profiles = {
        "schema_version": "1939-v50-identity-db-profiles-v1",
        "generator_version": "profile_identity_review_1939_v50.R:v1",
        "input": {"database_preview_sha256": sha(database_preview),
                  "import_preview_input_hashes": input_hashes,
                  "declared_record_keys": ["old-anna", "old-anna-2", "old-claus"]},
        "database": {"transaction_read_only": "on"},
        "review_only": True,
        "canonical_mutations_authorized": False,
        "counts": {"profiles": 3},
        "profiles": [
            {
                "record_key": "old-anna", "person_id": 101,
                "display_name": "Anna Marie Jensen", "staged": False,
                "narratives": [{"narrative_id": 1,
                    "text": "Anna Marie Jensen, f. 12 Maj 1800. Gift med Peter Jensen.",
                    "page": "1", "private": False, "editorial_events": 0}],
                "facts": [
                    {"fact_id": 11, "fact_type": "navn", "assertion_id": 21,
                     "raw_value": "Anna Marie Jensen", "citation": None, "editorial_events": 0},
                    {"fact_id": 12, "fact_type": "fødsel", "assertion_id": 22,
                     "raw_value": "12 Maj 1800", "citation": {"citation_id": 31,
                     "text": "12 Maj 1800", "page": "1"}, "editorial_events": 0},
                ],
                "relations": [],
                "families": [{"family_id": 41, "members": [
                    {"person_id": 101, "role": "partner", "display_name": "Anna Marie Jensen",
                     "editorial_events": 0},
                    {"person_id": 201, "role": "partner", "display_name": "Peter Jensen",
                     "editorial_events": 0},
                ]}],
            },
            {
                "record_key": "old-anna-2", "person_id": 103,
                "display_name": "Anna Marie Jensen", "staged": False,
                "narratives": [],
                "facts": [
                    {"fact_id": 13, "fact_type": "navn", "assertion_id": 23,
                     "raw_value": "Anna Marie Jensen", "citation": None, "editorial_events": 0},
                    {"fact_id": 14, "fact_type": "fødsel", "assertion_id": 24,
                     "raw_value": "12 Maj 1800", "citation": None, "editorial_events": 0},
                ],
                "relations": [], "families": [],
            },
            {
                "record_key": "old-claus", "person_id": 102,
                "display_name": "Claus", "staged": False,
                "narratives": [],
                "facts": [{"fact_id": 15, "fact_type": "navn", "assertion_id": 25,
                    "raw_value": "Claus", "citation": None, "editorial_events": 0}],
                "relations": [], "families": [],
            },
        ],
    }
    linked = [
        {"record_key": "old-claus", "navn": "Claus"},
        {"record_key": "old-anna", "navn": "Anna Marie Jensen"},
        {"record_key": "old-anna-2", "navn": "Anna Marie Jensen"},
        {"record_key": None, "navn": "Unrelated legacy row without stable key"},
    ]
    hashes = {
        "import_preview_sha256": sha(import_preview),
        "database_preview_sha256": sha(database_preview),
        "database_profiles_sha256": sha(profiles),
        "linked_clean_sha256": sha(linked),
    }
    return dict(import_preview=import_preview, database_preview=database_preview,
                database_profiles=profiles, linked_records=linked,
                input_hashes=hashes, expected_subject_count=3,
                expected_profile_count=3)


def build(values=None):
    return subject.build_identity_review(**(values or fixture_inputs()))


def test_builds_review_only_manifest_with_exact_offsets_and_no_decisions():
    result = build()
    assert result["schema_version"] == "1939-v50-identity-review-v1"
    assert result["review_only"] is True
    assert result["canonical_mutations_authorized"] is False
    assert result["review_state"] == "pending"
    assert result["counts"]["subjects"] == 3
    assert result["counts"]["profiles"] == 3
    assert [row["new_record_key"] for row in result["subjects"]] == [
        "new-anna", "new-claus", "new-else"]
    anna = result["subjects"][0]
    assert len(anna["candidates"]) == 2
    assert all(row["proposed_action"] == "unresolved" for row in anna["candidates"])
    name_signal = next(signal for signal in anna["candidates"][0]["signals"]
                       if signal["kind"] == "literal_name")
    assert anna["verbatim_text"][name_signal["source_start"]:name_signal["source_end"]] == \
        name_signal["text"]


def test_common_short_name_and_date_only_do_not_create_links():
    result = build()
    claus = next(row for row in result["subjects"] if row["new_record_key"] == "new-claus")
    assert claus["candidates"] == []
    else_ = next(row for row in result["subjects"] if row["new_record_key"] == "new-else")
    assert else_["candidates"] == []


def test_name_matching_cannot_use_only_a_title_or_estate_tail():
    assert subject._best_literal_name(
        "Baroniet Brahe-Trolleborg og Greve",
        "Detlev Christian Ernst til Baroniet Brahe-Trolleborg",
    ) is None


def test_embedded_descendant_mention_is_not_principal_identity_candidate():
    values = fixture_inputs()
    text = "Peter Jensen var Fader til Anna Marie Jensen, f. 12 Maj 1800.\n"
    row = values["import_preview"]["genuinely_new_pending"][0]
    row["verbatim_text"] = text
    row["source_span"]["char_to"] = row["source_span"]["char_from"] + len(text)
    result = build(values)
    anna = result["subjects"][0]
    assert anna["candidates"] == []


def test_short_principal_name_plus_exact_vital_fact_is_review_candidate():
    values = fixture_inputs()
    claus = values["database_profiles"]["profiles"][2]
    claus["facts"].append({
        "fact_id": 16, "fact_type": "død", "assertion_id": 26,
        "raw_value": "1450", "citation": None, "editorial_events": 0,
    })
    result = build(values)
    subject_row = next(row for row in result["subjects"]
                       if row["new_record_key"] == "new-claus")
    assert [row["candidate_record_key"] for row in subject_row["candidates"]] == ["old-claus"]


def test_ambiguity_is_symmetric_and_global_profile_reuse_is_visible():
    result = build()
    anna = result["subjects"][0]
    candidate_keys = {row["candidate_record_key"] for row in anna["candidates"]}
    assert candidate_keys == {"old-anna", "old-anna-2"}
    for candidate in anna["candidates"]:
        assert set(candidate["competing_candidate_record_keys"]) == candidate_keys - {
            candidate["candidate_record_key"]}
    assert result["counts"]["ambiguous_subjects"] == 1


@pytest.mark.parametrize("mutation", [
    "profile_pair", "profile_sha", "subject_count", "linked_duplicate",
    "canonical_authorized", "unknown_schema",
])
def test_fails_closed_on_input_drift(mutation):
    values = fixture_inputs()
    if mutation == "profile_pair":
        values["database_profiles"]["profiles"][0]["person_id"] = 999
    elif mutation == "profile_sha":
        values["database_profiles"]["input"]["database_preview_sha256"] = "0" * 64
    elif mutation == "subject_count":
        values["import_preview"]["genuinely_new_pending"].pop()
    elif mutation == "linked_duplicate":
        values["linked_records"].append(copy.deepcopy(values["linked_records"][0]))
    elif mutation == "canonical_authorized":
        values["database_profiles"]["canonical_mutations_authorized"] = True
    elif mutation == "unknown_schema":
        values["database_profiles"]["schema_version"] = "future"
    with pytest.raises(subject.IdentityReviewError):
        build(values)


def test_output_is_exclusive_and_deterministic(tmp_path: Path):
    result = build()
    output = tmp_path / "review.json"
    report = tmp_path / "review.md"
    subject.write_outputs(result, output, report)
    first_json = output.read_bytes()
    first_report = report.read_bytes()
    assert b"canonical_mutations_authorized" in first_json
    assert "review-only" in first_report.decode().lower()
    with pytest.raises(FileExistsError):
        subject.write_outputs(result, output, report)
    output.unlink()
    report.unlink()
    subject.write_outputs(build(), output, report)
    assert output.read_bytes() == first_json
    assert report.read_bytes() == first_report


def test_real_v50_review_has_exact_41_23_coverage_and_nine_conservative_links(tmp_path: Path):
    worktree = Path(__file__).resolve().parents[4]
    parent_repo = Path("/Users/johanreventlow/TypeScript/danmarksadelsaarbog")
    required = [
        worktree / "work/task21-1939-v50-import-preview/import-preview-v1.json",
        worktree / "work/task21-1939-v50-import-preview/database-preview-v1.json",
        worktree / "work/task22-1939-v50-identity-review/database-profiles-v1.json",
        parent_repo / "work_1939_stamtavle/linked_clean_1939_v2.json",
    ]
    if not all(path.exists() for path in required):
        pytest.skip("ignorerede realdata-input findes ikke i denne checkout")
    output = tmp_path / "review.json"
    report = tmp_path / "review.md"
    assert subject.main([
        "--import-preview", str(required[0]),
        "--database-preview", str(required[1]),
        "--database-profiles", str(required[2]),
        "--linked-clean", str(required[3]),
        "--output", str(output), "--report", str(report),
    ]) == 0
    review = json.loads(output.read_text(encoding="utf-8"))
    assert review["counts"]["subjects"] == 41
    assert review["counts"]["profiles"] == 23
    assert review["counts"]["candidate_links"] == 9
    assert review["counts"]["ambiguous_subjects"] == 0
    assert review["counts"]["profiles_competing_across_subjects"] == 0
    pairs = {
        (row["new_record_key"], candidate["candidate_record_key"])
        for row in review["subjects"] for candidate in row["candidates"]
    }
    assert pairs == {
        ("record-07cf32bc-c613-4275-bf06-c3be7c102ac0", "9e33183d-9985-44ab-824c-089e4e7c6b7a"),
        ("record-0bde9cda-dc25-465f-b05c-82e1552791bd", "d5168bc4-b71e-438a-93dc-2d4396b7f6e0"),
        ("record-380d43cd-09bf-498d-b8d4-de05330828a3", "1bd2926b-2550-46ea-9ce3-2b2218afeb34"),
        ("record-78723bfc-daf8-4cd1-83cb-df042852bedb", "a47eb878-6ba1-412e-90f5-b9e48334f159"),
        ("record-82f49e95-e5ce-4e08-9840-d0e334b4ba50", "240f4f2f-4873-461a-b7b1-ec4acccb9c31"),
        ("record-acec041a-0951-46f5-b942-95d6e5b4aaa1", "8d92031a-46d7-4c5a-9e12-816c49e91032"),
        ("record-c684f8d2-c553-4b54-a703-79844ca7a8df", "3365953a-4757-4e98-9dde-aeb4406be1c5"),
        ("record-d790ab87-566c-40a5-80c8-079607941d75", "d8e0429c-eebb-4635-bb5d-1fe3ce988ff5"),
        ("record-e2cc8f32-71ec-4823-a406-186039ae51f2", "441aefa3-a63b-4857-ab4f-f2319f9f6e9b"),
    }
    assert all(candidate["proposed_action"] == "unresolved"
               for row in review["subjects"] for candidate in row["candidates"])
    assert review["canonical_mutations_authorized"] is False
    assert review["reimport_gate"] == "NO-GO"
