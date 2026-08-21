"""DB-frie tests for menneskearket og dets fail-closed konverter."""
import importlib.util
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, _DIR / (name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


build = _load("build_c0_followup_review_1939_v50")
conv = _load("convert_c0_followup_decisions_1939_v50")


def _flags_doc():
    return {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "operations": [
            {"person_id": 991, "narrative_id": 660, "old_sha256": "a" * 64,
             "source_record_key": "record-x", "page_from": 504,
             "default_text": "Hr. Iven til Rixdorf.", "flags": []},
            {"person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
             "source_record_key": "record-y", "page_from": 504,
             "default_text": "Reventlow til Gaarz.", "flags": [
                 {"flag_id": "record-y:12:hyphen_unproven",
                  "kind": "hyphen_unproven", "char_offset": 12,
                  "context": "Revent-\nlow til", "person_id": 992,
                  "source_record_key": "record-y"}]},
        ],
        "flag_counts": {"hyphen_unproven": 1},
    }


def test_sheet_prefills_the_recommended_action():
    """Anbefalingerne er UDFYLDT: står en linje urørt, er den enig."""
    text = build.render_review(_flags_doc())
    assert "[MERGE] record-y:12:hyphen_unproven" in text


def test_sheet_lists_person_without_flags_as_auto():
    """991 har ingen flag — dens tekst er allerede korrekt. Den skal fremgå,
    så mennesket ser HELE mængden, ikke kun det der kræver et valg."""
    text = build.render_review(_flags_doc())
    assert "991" in text


def test_roundtrip_unchanged_sheet_yields_defaults():
    doc = _flags_doc()
    out = conv.parse_review(build.render_review(doc), doc)
    assert out["decisions"] == {"record-y:12:hyphen_unproven": "merge"}
    assert out["accepted_person_ids"] == [991, 992]


def test_keep_is_honoured():
    doc = _flags_doc()
    text = build.render_review(doc).replace("[MERGE] record-y", "[KEEP] record-y", 1)
    assert conv.parse_review(text, doc)["decisions"] == {
        "record-y:12:hyphen_unproven": "keep"}


def test_afvis_removes_the_person_but_keeps_the_others():
    """Delvis accept: afvises én, kører de øvrige. Alt-eller-intet ville
    presse mod at acceptere noget tvivlsomt for at få resten igennem."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("[ACCEPT] 991", "[AFVIS]  991", 1)
    out = conv.parse_review(text, doc)
    assert out["accepted_person_ids"] == [992]


def test_unknown_token_is_terminal():
    doc = _flags_doc()
    text = build.render_review(doc).replace("[MERGE] record-y", "[MAASKE] record-y", 1)
    with pytest.raises(SystemExit, match="C0F_REVIEW_TOKEN_INVALID"):
        conv.parse_review(text, doc)


def test_edited_context_is_terminal():
    """Byte-låst kontekst: alt andet end tokenet verificeres. Ellers kunne en
    utilsigtet redigering flytte et valg til et andet sted i teksten."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("Revent-\\n", "Rvent-\\n", 1)
    with pytest.raises(SystemExit, match="C0F_REVIEW_LINE_TAMPERED"):
        conv.parse_review(text, doc)


def test_missing_line_is_terminal():
    doc = _flags_doc()
    text = "\n".join(l for l in build.render_review(doc).splitlines()
                     if "record-y:12" not in l)
    with pytest.raises(SystemExit, match="C0F_REVIEW_FLAG_MISSING"):
        conv.parse_review(text, doc)


def test_all_rejected_is_terminal():
    """En tom mængde er ikke en gyldig kørsel — samme regel som D2_APPLY_EMPTY."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("[ACCEPT]", "[AFVIS] ")
    with pytest.raises(SystemExit, match="C0F_REVIEW_EMPTY"):
        conv.parse_review(text, doc)


def test_unknown_flag_kind_is_terminal():
    """Målingen gav kun hyphen_unproven, men det er en egenskab ved DATA, ikke
    ved koden. En ny flagtype skal give en læsbar fejl, ikke en rå KeyError."""
    doc = _flags_doc()
    doc["operations"][1]["flags"][0]["kind"] = "some_future_flag_kind"
    with pytest.raises(SystemExit, match="C0F_REVIEW_FLAG_KIND_UNKNOWN"):
        build.render_review(doc)
