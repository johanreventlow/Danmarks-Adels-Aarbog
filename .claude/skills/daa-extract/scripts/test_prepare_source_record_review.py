import hashlib

import pytest

from prepare_source_record_review import ReviewPreparationError, build_accepted_review, write_new_json


TEXT = "Født 1801."


def post(*, linje="I", nr_label="45", raw_text=TEXT, sider="101"):
    return {
        "linje": linje,
        "nr_label": nr_label,
        "raw_text": raw_text,
        "sider": sider,
    }


def manifest(*, locator="I-45", raw_text=TEXT):
    return {
        "schema_version": "1.0",
        "raw_text_sha256": "a" * 64,
        "selection": {"person_occurrences": [{
            "occurrence_locator": locator,
            "raw_text_sha256": hashlib.sha256(raw_text.encode()).hexdigest(),
        }]},
    }


def test_build_accepted_review_uses_explicit_tuple_bridge_and_exact_text_hash():
    review = build_accepted_review(
        [post()], manifest(), rendition_id="rendition-2018-v1",
        extraction_run_id="segmentation-1", reviewed_by="johan",
    )

    assert review["source_id"] == "2018-20"
    assert review["rendition_sha256"] == "a" * 64
    assert review["records"] == [{
        "acceptance_id": "task16-2018-person-I-45",
        "record_kind": "person",
        "decision_status": "accepted",
        "reviewed_by": "johan",
        "decision_version": 1,
        "verbatim_text": TEXT,
        "span": {
            "page_from": 101, "page_to": 101,
            "char_from": 0, "char_to": len(TEXT), "bbox": None,
        },
    }]


def test_build_accepted_review_rejects_text_hash_drift():
    with pytest.raises(ReviewPreparationError, match="teksthash"):
        build_accepted_review(
            [post(raw_text="ændret")], manifest(), rendition_id="rendition-2018-v1",
            extraction_run_id="segmentation-1", reviewed_by="johan",
        )


def test_build_accepted_review_rejects_missing_or_duplicate_tuple_bridge():
    with pytest.raises(ReviewPreparationError, match="mangler"):
        build_accepted_review(
            [], manifest(), rendition_id="rendition-2018-v1",
            extraction_run_id="segmentation-1", reviewed_by="johan",
        )
    with pytest.raises(ReviewPreparationError, match="dublet"):
        build_accepted_review(
            [post(), post()], manifest(), rendition_id="rendition-2018-v1",
            extraction_run_id="segmentation-1", reviewed_by="johan",
        )


def test_write_new_json_refuses_to_overwrite_existing_file(tmp_path):
    path = tmp_path / "review.json"
    write_new_json(path, {"schema_version": "1.0"})

    with pytest.raises(ReviewPreparationError, match="findes allerede"):
        write_new_json(path, {"schema_version": "1.0"})
