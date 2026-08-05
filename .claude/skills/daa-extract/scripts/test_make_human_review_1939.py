import json
import re
import sys
import hashlib
from pathlib import Path

import pytest

import make_human_review_1939 as subject


def test_pages_expands_ranges_and_rejects_malformed_values():
    assert subject._pages("496-498") == [496, 497, 498]
    assert subject._pages("498") == [498]
    assert subject._pages("498-496") == []
    assert subject._pages("side 498") == []


def _source(baseline_bytes, calamari_bytes):
    return {
        "edition": "1939",
        "baseline_sha256": hashlib.sha256(baseline_bytes).hexdigest(),
        "calamari_sha256": hashlib.sha256(calamari_bytes).hexdigest(),
        "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }


def _write_inputs(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    queue = tmp_path / "queue.json"
    source = tmp_path / "source.json"
    calamari = tmp_path / "calamari.txt"
    baseline.write_text(json.dumps([{
        "record_key": "record-1", "navn": "Volrad", "sider": "498",
    }]), encoding="utf-8")
    calamari.write_text("### PAGE 0003 ###\nVolrad", encoding="utf-8")
    source_value = _source(baseline.read_bytes(), calamari.read_bytes())
    source.write_text(json.dumps({"schema_version": 1, "source": source_value}), encoding="utf-8")
    queue.write_text(json.dumps({"schema_version": 1, "source": source_value, "entries": [{
        "baseline_record_key": "record-1", "queue_class": "human_required",
        "reason_code": "no_candidate", "reason_da": "ingen kandidat",
    }]}), encoding="utf-8")
    review.write_text(json.dumps({"schema_version": 1, "source": source_value,
        "baseline_sha256": source_value["baseline_sha256"], "entries": [{
            "baseline_record_key": "record-1", "review_status": "unreviewed",
        }]}), encoding="utf-8")
    return baseline, review, queue, source, calamari


def _argv(baseline, review, queue, source, calamari, out):
    return ["make_human_review_1939.py", "--baseline", str(baseline),
            "--queue-manifest", str(queue), "--source-manifest", str(source),
            "--review", str(review), "--calamari", str(calamari),
            "--calamari-first-pdf-page", "496", "--out", str(out)]


def test_main_shows_candidates_on_translated_pdf_pages(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [{
        "lokal_id": "Stamme.Volrad", "sider": "3", "raw_text": "Hr. Volrad",
    }])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", out.read_text(encoding="utf-8")
    ).group(1))
    assert payload["records"][0]["candidates"] == [{
        "candidate_id": "Stamme.Volrad",
        "lokal_id": "Stamme.Volrad",
        "pdf_pages": [498],
        "calamari_pages": [3],
        "raw_text": "Hr. Volrad",
        "rank_reason": "samme_pdf_side",
    }]
    assert payload["default_view"] == "required"
    rendered = out.read_text(encoding="utf-8")
    assert "window.DAA1939Review.init({data: DATA, download: downloadDraft});" in rendered
    assert "data-action" in rendered
    assert "daa1939-review:" in rendered


def test_main_embeds_the_committed_controller_bytes_without_inline_handlers(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    rendered = out.read_bytes()
    committed = (Path(subject.__file__).parent / "human_review_1939_ui.js").read_bytes()
    start = rendered.index(b"(function (global) {")
    end = start + len(committed)
    assert rendered[start:end] == committed
    assert b"onclick=" not in rendered


@pytest.mark.parametrize("which", ["baseline", "queue", "review", "source"])
def test_main_rejects_disagreeing_hashes(tmp_path, monkeypatch, which):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    if which == "baseline":
        baseline.write_text("[]", encoding="utf-8")
    elif which == "queue":
        value = json.loads(queue.read_text(encoding="utf-8"))
        value["source"]["baseline_sha256"] = "0" * 64
        queue.write_text(json.dumps(value), encoding="utf-8")
    elif which == "review":
        value = json.loads(review.read_text(encoding="utf-8"))
        value["baseline_sha256"] = "0" * 64
        review.write_text(json.dumps(value), encoding="utf-8")
    else:
        value = json.loads(source.read_text(encoding="utf-8"))
        value["source"]["baseline_sha256"] = "0" * 64
        source.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="hash"):
        subject.main()


def test_main_refuses_to_overwrite_existing_output(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    out.write_text("old", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(FileExistsError):
        subject.main()


def test_main_accepts_task1_review_ledger_with_matching_baseline_hash(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    value = json.loads(review.read_text(encoding="utf-8"))
    value.pop("source")
    value["entries"][0]["baseline_locator"] = {"pages": "498", "local_id": None}
    review.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0


def test_main_rejects_sourceless_review_with_a_human_decision(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    value = json.loads(review.read_text(encoding="utf-8"))
    value.pop("source")
    value["entries"][0].update(review_status="menneskeark", reason="vurderet")
    review.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="legacy review"):
        subject.main()


@pytest.mark.parametrize("field", ["calamari_sha256", "raw_ocr_sha256", "pdf_sha256", "profile_version"])
def test_main_rejects_completed_review_with_changed_pinned_source(tmp_path, monkeypatch, field):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    value = json.loads(review.read_text(encoding="utf-8"))
    value["entries"][0].update(review_status="menneskeark", reason="vurderet")
    value["source"][field] = "x" * 64 if field.endswith("sha256") else "1939-v1"
    review.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="review source hashes"):
        subject.main()


def test_main_rejects_review_missing_a_baseline_key(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    value = json.loads(review.read_text(encoding="utf-8"))
    value["entries"] = []
    review.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="review baseline-dækning"):
        subject.main()


@pytest.mark.parametrize(
    ("field", "value", "message"),
    [
        ("calamari_span", {"char_from": 1, "char_to": 1}, "char_from < char_to"),
        ("raw_excerpt_sha256", "0" * 64, "matcher ikke raw_verbatim_text"),
    ],
)
def test_main_reuses_authoritative_legacy_review_validation(
    tmp_path, monkeypatch, field, value, message
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    ledger = json.loads(review.read_text(encoding="utf-8"))
    ledger["entries"][0].update({
        "review_status": "accepteret",
        "candidate_id": "candidate-1",
        "post_index": 0,
        "calamari_span": {"char_from": 0, "char_to": 1},
        "calamari_verbatim_text": "A",
        "pdf_pages": [498],
        "kind": "line_header",
        "raw_char_from": 0,
        "raw_char_to": 1,
        "raw_verbatim_text": "A",
        "raw_excerpt_sha256": hashlib.sha256(b"A").hexdigest(),
    })
    ledger["entries"][0][field] = value
    review.write_text(json.dumps(ledger), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match=message):
        subject.main()


def test_main_rejects_legacy_duplicate_target_that_is_not_accepted(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    baseline_value = [
        {"record_key": "record-1", "navn": "Volrad", "sider": "498"},
        {"record_key": "record-2", "navn": "Anden", "sider": "498"},
    ]
    baseline.write_text(json.dumps(baseline_value), encoding="utf-8")
    source_value = _source(baseline.read_bytes(), calamari.read_bytes())
    source.write_text(json.dumps({"schema_version": 1, "source": source_value}), encoding="utf-8")
    queue.write_text(json.dumps({"schema_version": 1, "source": source_value, "entries": [
        {"baseline_record_key": "record-1", "queue_class": "human_required", "reason_code": "x", "reason_da": "x"},
        {"baseline_record_key": "record-2", "queue_class": "human_required", "reason_code": "x", "reason_da": "x"},
    ]}), encoding="utf-8")
    review.write_text(json.dumps({"schema_version": 1, "source": source_value,
        "baseline_sha256": source_value["baseline_sha256"], "entries": [
            {"baseline_record_key": "record-1", "review_status": "eksplicit_dublet",
             "duplicate_of_baseline_record_key": "record-2"},
            {"baseline_record_key": "record-2", "review_status": "unreviewed"},
        ]}), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="accepteret"):
        subject.main()
