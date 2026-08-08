import pytest

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
