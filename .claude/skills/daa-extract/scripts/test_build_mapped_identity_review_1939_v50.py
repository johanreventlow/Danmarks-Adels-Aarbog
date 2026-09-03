from __future__ import annotations

import hashlib
import json

import build_mapped_identity_review_1939_v50 as subject


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def test_builds_pending_candidate_from_mapped_1939_person():
    source_text = "I. Ditlev, Biskop i Lübeck † 1536.\n"
    import_preview = {
        "schema_version": "1939-v50-import-preview-v1", "preview_gate": "GO",
        "reimport_gate": "NO-GO", "canonical_mutations_authorized": False,
        "counts": {"mapped_existing": 1, "genuinely_new_pending": 2},
        "mapped_existing": [{"baseline_record_key": "old-d", "new_record_key": "mapped-d"}],
        "genuinely_new_pending": [
            {"new_record_key": "new-d", "person_creation": "forbidden",
             "source_span": {"char_from": 0, "char_to": len(source_text)},
             "verbatim_text": source_text},
            {"new_record_key": "new-approved", "person_creation": "forbidden",
             "source_span": {"char_from": 50, "char_to": 54}, "verbatim_text": "Done"},
        ],
    }
    database_preview = {
        "schema_version": "1939-v50-database-preview-v1", "reimport_gate": "NO-GO",
        "canonical_mutations_authorized": False,
        "person_anchors": {"matched": [{"baseline_record_key": "old-d", "person_id": 101}]},
    }
    decisions = {
        "schema_version": "1939-v50-identity-decisions-v1", "decision_gate": "GO",
        "canonical_mutations_authorized": False, "database_write_authorized": False,
        "decisions": [{"source_record_key": "new-approved", "candidate_record_key": "old-x",
                       "canonical_person_id": 999, "action": "same"}],
    }
    clean = [{
        "record_key": "old-d", "navn": "Ditlev", "narrative": "Ditlev, Biskop i Lübeck † 1536.",
        "facts": [{"faktatype": "død", "date_raw": "1536", "kilde_span": "1536"},
                  {"faktatype": "titel", "vaerdi": "Biskop i Lübeck",
                   "kilde_span": "Biskop i Lübeck"}],
        "aegteskaber": [],
    }]
    hashes = {name: "a" * 64 for name in (
        "import_preview_sha256", "database_preview_sha256",
        "identity_decisions_sha256", "clean_sha256")}
    result = subject.build_mapped_review(
        import_preview=import_preview, database_preview=database_preview,
        identity_decisions=decisions, clean_records=clean, input_hashes=hashes,
        expected_subjects=1, expected_profiles=1)
    assert result["counts"]["subjects"] == 1
    assert result["counts"]["candidate_links"] == 1
    candidate = result["subjects"][0]["candidates"][0]
    assert candidate["candidate_record_key"] == "old-d"
    assert candidate["candidate_person_id"] == 101
    assert candidate["proposed_action"] == "unresolved"
    assert result["canonical_mutations_authorized"] is False


def test_embedded_person_is_not_candidate():
    assert subject.principal_name_before_transition(
        "Cay Friedrich, hvis Søn Ditlev Reventlow", "Ditlev Reventlow") is False
    assert subject.principal_name_before_transition(
        "Ditlev Reventlow † 1783", "Ditlev Reventlow") is True
    signals = [{"kind": "literal_fact_value", "fact_type": "død",
                "text": "1700", "source_start": 30}]
    assert subject.filter_principal_signals("Otto † 1676, Fader til Otto † 1700", signals) == []
    weak = [{"kind": "literal_fact_value", "fact_type": "død",
             "text": "s. A.", "source_start": 5}]
    assert subject.filter_principal_signals("Henrik nævnes s. A.", weak) == []
