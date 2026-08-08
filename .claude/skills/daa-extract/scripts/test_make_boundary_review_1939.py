import hashlib
import json
import sys

import pytest

import make_boundary_review_1939 as subject

from make_boundary_review_1939 import build_boundary_view_model

SOURCE = {"edition": "1939", "profile_version": "1939-v2",
          "baseline_sha256": "a" * 64, "calamari_sha256": "b" * 64,
          "raw_ocr_sha256": "c" * 64, "pdf_sha256": "d" * 64}


def automatic_span(key, candidate_id, char_from, char_to):
    candidate = {
        "candidate_id": candidate_id,
        "postklasse": "nummereret",
        "calamari_span": {"char_from": char_from, "char_to": char_to},
        "pdf_pages": [496],
        "raw_structure_bridge": {
            "kind": "dual_rendition_consensus_v1",
            "raw_char_from": char_from,
            "raw_char_to": char_to,
            "raw_excerpt_sha256": "e" * 64,
        },
    }
    return {
        "baseline_record_key": key,
        "candidate_id": candidate_id,
        "char_from": char_from,
        "char_to": char_to,
        "origin": "automatisk",
        "candidate": candidate,
    }


def test_a_gap_with_a_head_only_in_raw_ocr_requires_judgement():
    calamari = "6. Christine Augusta; g. 1708.\n7 Heinrich til Gottesgabe\n"
    raw = "6. Christine Augusta; g. 1708.\n7. H e i n r i c h til Gottesgabe\n"
    spans = [automatic_span("rk-6", "1939:6", 0, 30)]
    clauses = [{"char_from": 0, "char_to": 30, "classification": "record_text"},
               {"char_from": 30, "char_to": len(calamari),
                "classification": "structural_header"}]
    records = {"rk-6": {"record_key": "rk-6", "navn": "Christine Augusta",
                        "_orig_nr": 6, "_gruppe_nr": 1,
                        "_v2_lokal_id": "III.Sjette.III.6", "sider": "535"}}

    model = build_boundary_view_model(
        spans, clauses, calamari, raw, records, SOURCE,
    )

    tail = model["boundaries"][-1]
    assert tail["bulk_confirmable"] is False
    assert tail["boundary_id"] in model["views"]["kraever_vurdering"]
    assert model["summary"]["graenser"] == 2


def test_the_canonical_global_injectivity_contract_is_called(monkeypatch):
    """validate_source_bound_evidence beviser ikke globalt fravær af overlap."""
    calls = []
    monkeypatch.setattr(
        "make_boundary_review_1939.validate_effective_candidate_injectivity",
        lambda effective, source: calls.append(effective),
    )
    spans = [automatic_span("rk-a", "1939:a", 0, 10)]
    candidate = spans[0]["candidate"]
    records = {"rk-a": {"record_key": "rk-a", "navn": "Anders", "_orig_nr": 1,
                        "_gruppe_nr": 1, "_v2_lokal_id": "I.1", "sider": "496"}}

    build_boundary_view_model(
        spans, [{"char_from": 0, "char_to": 20, "classification": "record_text"}],
        "1. Anders, f. 1900.\n", "1. Anders, f. 1900.\n", records, SOURCE,
    )

    assert calls == [{"rk-a": candidate}]
    assert calls[0]["rk-a"] is candidate
    assert calls[0]["rk-a"]["raw_structure_bridge"] == candidate["raw_structure_bridge"]
    assert "approval" not in calls[0]["rk-a"]


def _write_inputs(tmp_path):
    calamari = tmp_path / "calamari.txt"
    raw = tmp_path / "raw.txt"
    calamari.write_text("### PAGE 0001 ###\\n1. Anders, f. 1900.\\n", encoding="utf-8")
    raw.write_text("### PAGE 0001 ###\\n1. Anders, f. 1900.\\n", encoding="utf-8")
    baseline = tmp_path / "baseline.json"
    baseline.write_text(json.dumps([{
        "record_key": "rk-a", "navn": "Anders", "sider": "496", "_orig_nr": 1,
        "_gruppe_nr": 1, "_v2_lokal_id": "I.1",
    }]), encoding="utf-8")
    source = {
        "edition": "1939", "profile_version": "1939-v2",
        "baseline_sha256": hashlib.sha256(baseline.read_bytes()).hexdigest(),
        "calamari_sha256": hashlib.sha256(calamari.read_bytes()).hexdigest(),
        "raw_ocr_sha256": hashlib.sha256(raw.read_bytes()).hexdigest(),
        "pdf_sha256": "d" * 64,
    }
    source_manifest = tmp_path / "source.json"
    source_manifest.write_text(json.dumps({"schema_version": 1, "source": source}),
                               encoding="utf-8")
    queue = tmp_path / "queue.json"
    queue.write_text(json.dumps({"schema_version": 1, "source": source, "entries": [{
        "baseline_record_key": "rk-a", "queue_class": "human_required",
        "reason_code": "no_candidate", "reason_da": "ingen kandidat",
    }]}), encoding="utf-8")
    anchored = tmp_path / "anchored.json"
    anchored.write_text(json.dumps({"human:a": {
        "baseline_record_key": "rk-a", "candidate": {
            "candidate_id": "human:a", "postklasse": "nummereret",
            "calamari_span": {"char_from": 18, "char_to": 37},
            "pdf_pages": [496],
            "approval": {"kind": "human_approved_span_v1",
                         "calamari_excerpt_sha256": "e" * 64}}}}),
        encoding="utf-8")
    return baseline, queue, source_manifest, calamari, raw, anchored


def _argv(baseline, queue, source, calamari, raw, anchored, out):
    return ["make_boundary_review_1939.py", "--baseline", str(baseline),
            "--queue-manifest", str(queue), "--source-manifest", str(source),
            "--calamari", str(calamari), "--raw", str(raw),
            "--anchored", str(anchored), "--out", str(out)]


def test_main_writes_a_self_contained_page(tmp_path, monkeypatch):
    inputs = _write_inputs(tmp_path)
    out = tmp_path / "graenser.html"
    monkeypatch.setattr(sys, "argv", _argv(*inputs, out))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    assert "window.DAABoundaryReview.init(" in rendered
    assert "DAAReviewShared" in rendered
    assert "const DATA=" in rendered


def test_main_refuses_a_changed_calamari_file(tmp_path, monkeypatch):
    baseline, queue, source, calamari, raw, anchored = _write_inputs(tmp_path)
    calamari.write_text("ændret kilde", encoding="utf-8")
    out = tmp_path / "graenser.html"
    monkeypatch.setattr(sys, "argv",
                        _argv(baseline, queue, source, calamari, raw, anchored, out))

    with pytest.raises(ValueError, match="calamari hash"):
        subject.main()
    assert not out.exists()


def test_main_refuses_to_overwrite_an_existing_page(tmp_path, monkeypatch):
    inputs = _write_inputs(tmp_path)
    out = tmp_path / "graenser.html"
    out.write_text("findes", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(*inputs, out))

    with pytest.raises(FileExistsError):
        subject.main()


def test_main_embeds_an_earlier_verdict_export(tmp_path, monkeypatch):
    baseline, queue, source, calamari, raw, anchored = _write_inputs(tmp_path)
    model_source = json.loads(source.read_text(encoding="utf-8"))["source"]
    verdicts = tmp_path / "domme.json"
    verdicts.write_text(json.dumps({
        "schema_version": 1, "source": model_source,
        "exported_at": "2026-08-08T10:00:00.000Z",
        "entries": [], "ocr_noter": [],
    }), encoding="utf-8")
    out = tmp_path / "graenser.html"
    monkeypatch.setattr(sys, "argv", _argv(
        baseline, queue, source, calamari, raw, anchored, out) + [
        "--verdicts", str(verdicts)])

    assert subject.main() == 0
    assert '"tidligere_domme"' in out.read_text(encoding="utf-8")
