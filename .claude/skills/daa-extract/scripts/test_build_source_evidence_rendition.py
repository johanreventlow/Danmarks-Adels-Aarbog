"""Syntetiske fixtures uden rigtige navne — rendition- og paritetsgates."""
import hashlib
import json

import pytest

import build_source_evidence_rendition as rendition


def profile(**overrides):
    base = {
        "pdf_sha256": hashlib.sha256(b"fixture-pdf").hexdigest(),
        "raw_text_sha256": hashlib.sha256(b"fixture-text").hexdigest(),
        "segment_version": "segment.py@fixture-v1",
        "expected_counts": {"person_creates": 0, "source_evidence": 2},
    }
    base.update(overrides)
    return base


def posts():
    return [
        {"linje": "I", "nr": 1, "nr_label": "1", "sider": "10", "raw_text": "Alfa beta"},
        {"linje": "I", "nr": 2, "nr_label": "2a", "sider": "10-11", "raw_text": "Gamma delta"},
    ]


def test_verify_pdf_accepts_locked_hash():
    assert rendition.verify_pdf(b"fixture-pdf", profile()) == \
        hashlib.sha256(b"fixture-pdf").hexdigest()


def test_verify_pdf_rejects_other_pdf():
    with pytest.raises(rendition.RenditionError) as error:
        rendition.verify_pdf(b"other-pdf", profile())
    assert str(error.value) == "SOURCE_EVIDENCE_PDF_SHA_MISMATCH"


def test_verify_rendition_accepts_locked_hash():
    assert rendition.verify_rendition(b"fixture-text", profile()) == \
        hashlib.sha256(b"fixture-text").hexdigest()


def test_verify_rendition_rejects_drifted_text():
    with pytest.raises(rendition.RenditionError) as error:
        rendition.verify_rendition(b"fixture-text ", profile())
    assert str(error.value) == "SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH"


def test_baseline_lokal_ids_reads_only_structural_keys(tmp_path):
    (tmp_path / "I-1.json").write_text(
        json.dumps({"linje": "I", "nr": 1, "nr_label": "1", "navn": "IKKE-LÆST"}),
        encoding="utf-8")
    (tmp_path / "I-2a.json").write_text(
        json.dumps({"linje": "I", "nr": 2, "nr_label": "2a", "navn": "IKKE-LÆST"}),
        encoding="utf-8")
    assert rendition.baseline_lokal_ids(tmp_path) == ["I.1", "I.2a"]


def test_segment_parity_accepts_identical_sets():
    assert rendition.segment_parity(posts(), ["I.1", "I.2a"], 2) == ["I.1", "I.2a"]


def test_segment_parity_rejects_missing_lokal_id():
    with pytest.raises(rendition.RenditionError) as error:
        rendition.segment_parity(posts(), ["I.1", "I.2a", "I.3"], 3)
    assert str(error.value) == "SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH"


def test_segment_parity_rejects_extra_lokal_id():
    with pytest.raises(rendition.RenditionError) as error:
        rendition.segment_parity(posts(), ["I.1"], 2)
    assert str(error.value) == "SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH"


def test_segment_parity_rejects_wrong_expected_count():
    with pytest.raises(rendition.RenditionError) as error:
        rendition.segment_parity(posts(), ["I.1", "I.2a"], 3)
    assert str(error.value) == "SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH"


def test_segment_parity_rejects_missing_linje():
    broken = posts()
    broken[0]["linje"] = None
    with pytest.raises(rendition.RenditionError) as error:
        rendition.segment_parity(broken, ["I.1", "I.2a"], 2)
    assert str(error.value) == "SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH"


def test_segment_digest_contains_no_verbatim_text():
    digest = rendition.segment_digest(posts(), profile())
    assert digest["segment_version"] == "segment.py@fixture-v1"
    assert digest["posts"] == [
        {"record_key": "I-1",
         "verbatim_sha256": hashlib.sha256("Alfa beta".encode()).hexdigest()},
        {"record_key": "I-2a",
         "verbatim_sha256": hashlib.sha256("Gamma delta".encode()).hexdigest()},
    ]
    serialized = json.dumps(digest, ensure_ascii=False)
    assert "Alfa beta" not in serialized and "Gamma delta" not in serialized


def test_segment_digest_is_deterministic():
    assert rendition.segment_digest(posts(), profile()) == \
        rendition.segment_digest(posts(), profile())
