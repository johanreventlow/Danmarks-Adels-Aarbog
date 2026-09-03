"""Syntetiske fixtures uden rigtige navne — manifest-byggerens gates."""
import hashlib
import json

import pytest

import build_source_evidence_manifest as builder

RENDITION = (
    "### PAGE 10 ###\n"
    "                    I\n"
    "        DEN SYNTETISKE LINJE\n"
    "\n"
    "1.  Alfa   Bravo,  f. 1801,\n"
    "    d. 1860.\n"
    "\n"
    "### PAGE 11 ###\n"
    "2a. Charlie Delta, f. 1830.\n"
)
RENDITION_BYTES = RENDITION.encode("utf-8")


def profile(**overrides):
    base = {
        "source_id": 4242,
        "profile_id": "fixture-source-evidence-v1",
        "profile_sha256": "d" * 64,
        "raw_text_sha256": hashlib.sha256(RENDITION_BYTES).hexdigest(),
        "segment_version": "segment.py@fixture-v1",
        "expected_counts": {"person_creates": 0, "source_evidence": 2},
    }
    base.update(overrides)
    return base


def posts():
    return [
        {"linje": "I", "nr": 1, "nr_label": "1", "sider": "10",
         "raw_text": "Alfa Bravo, f. 1801, d. 1860."},
        {"linje": "I", "nr": 2, "nr_label": "2a", "sider": "10-11",
         "raw_text": "Charlie Delta, f. 1830."},
    ]


def test_projection_collapses_whitespace_and_drops_page_markers():
    projection, offsets = builder.project_rendition(RENDITION)
    assert "### PAGE" not in projection
    assert "Alfa Bravo, f. 1801, d. 1860." in projection
    assert len(offsets) == len(projection)
    assert RENDITION[offsets[0]] == projection[0]


def test_pages_from_sider_single_page():
    assert builder.pages_from_sider("93") == (93, 93)


def test_pages_from_sider_page_range():
    assert builder.pages_from_sider("93-94") == (93, 94)


def test_pages_from_sider_rejects_free_text():
    with pytest.raises(builder.ManifestError) as error:
        builder.pages_from_sider("93 f.")
    assert str(error.value) == "SOURCE_EVIDENCE_PAGE_INVALID"


def test_pages_from_sider_rejects_descending_range():
    with pytest.raises(builder.ManifestError) as error:
        builder.pages_from_sider("94-93")
    assert str(error.value) == "SOURCE_EVIDENCE_PAGE_INVALID"


def test_record_key_uses_dash_like_load_helpers():
    assert builder.record_key_of(posts()[1]) == "I-2a"


def test_build_manifest_produces_writer_ready_operations():
    manifest = builder.build_manifest(profile(), RENDITION_BYTES, posts())
    assert set(manifest) == {"manifest_content_sha256", "source",
                             "expected_counts", "operations"}
    assert manifest["source"] == {"id": 4242,
                                  "profile_id": "fixture-source-evidence-v1",
                                  "profile_sha256": "d" * 64}
    assert manifest["expected_counts"] == {"source_evidence": 2,
                                           "person_creates": 0,
                                           "canonical_delta": 0}
    first = manifest["operations"][0]
    assert first["element_id"] == "source-evidence:I-1"
    assert first["dependency_class"] == "source_evidence"
    assert first["disposition"] == "retain_source_only"
    assert first["category"] == "person_post"
    assert first["page_evidence"] == {"page_from": 10, "page_to": 10}
    assert first["source_span"]["char_to"] > first["source_span"]["char_from"] >= 0
    assert first["rendition_content_sha256"] == profile()["raw_text_sha256"]
    assert first["anchor_method"] == "deterministic-segment"
    assert first["verbatim_sha256"] == hashlib.sha256(
        first["verbatim_text"].encode()).hexdigest()


def test_build_manifest_span_roundtrips_to_raw_text():
    manifest = builder.build_manifest(profile(), RENDITION_BYTES, posts())
    for operation in manifest["operations"]:
        span = operation["source_span"]
        sliced = RENDITION[span["char_from"]:span["char_to"]]
        assert builder.project_rendition(sliced)[0] == operation["verbatim_text"]


def test_build_manifest_rejects_text_not_in_rendition():
    broken = posts()
    broken[0]["raw_text"] = "Echo Foxtrot, f. 1900."
    with pytest.raises(builder.ManifestError) as error:
        builder.build_manifest(profile(), RENDITION_BYTES, broken)
    assert str(error.value) == "SOURCE_EVIDENCE_SPAN_NOT_FOUND"


def test_build_manifest_rejects_duplicate_lokal_id():
    broken = posts()
    broken[1]["nr_label"] = "1"
    with pytest.raises(builder.ManifestError) as error:
        builder.build_manifest(profile(), RENDITION_BYTES, broken)
    assert str(error.value) == "SOURCE_EVIDENCE_RECORD_KEY_DUPLICATE"


def test_build_manifest_rejects_rendition_hash_drift():
    with pytest.raises(builder.ManifestError) as error:
        builder.build_manifest(profile(raw_text_sha256="e" * 64),
                               RENDITION_BYTES, posts())
    assert str(error.value) == "SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH"


def test_build_manifest_rejects_count_drift():
    with pytest.raises(builder.ManifestError) as error:
        builder.build_manifest(
            profile(expected_counts={"person_creates": 0, "source_evidence": 3}),
            RENDITION_BYTES, posts())
    assert str(error.value) == "SOURCE_EVIDENCE_COUNT_MISMATCH"


def test_build_manifest_is_deterministic():
    first = builder.build_manifest(profile(), RENDITION_BYTES, posts())
    second = builder.build_manifest(profile(), RENDITION_BYTES, posts())
    assert first["manifest_content_sha256"] == second["manifest_content_sha256"]
    assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)


def test_build_manifest_carries_no_structured_person_data():
    manifest = builder.build_manifest(profile(), RENDITION_BYTES, posts())
    allowed = {"element_id", "dependency_class", "source_record_key", "source_id",
               "category", "disposition", "rendition_content_sha256", "source_span",
               "page_evidence", "verbatim_text", "verbatim_sha256", "anchor_method",
               "segment_version"}
    for operation in manifest["operations"]:
        assert set(operation) == allowed
