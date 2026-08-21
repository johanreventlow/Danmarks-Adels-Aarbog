"""DB-frie tests for build_c0_followup_flags_1939_v50.py."""
import importlib.util
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "c0f_flags", _DIR / "build_c0_followup_flags_1939_v50.py")
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)

SHA = "a" * 64
IDS = [963, 967, 978, 991, 992, 1296, 1297, 1298, 1299]


def _selection(**kw):
    sel = [{"person_id": p, "narrative_id": 600 + i, "old_sha256": SHA,
            "privat": False, "side": "508"} for i, p in enumerate(IDS)]
    doc = {"schema_version": "1.0", "selected": sel}
    doc.update(kw)
    return doc


def _record_by_person():
    return {p: "record-%032x" % p for p in IDS}


def _candidates(text="Ditlev til Wittenberg.\n"):
    return {"records": [{"new_record_key": "record-%032x" % p,
                         "verbatim_text": text,
                         "pages": {"page_from": 508, "page_to": 508}}
                        for p in IDS]}


def test_happy_path_produces_nine_operations():
    doc = mod.build_flags_document(_selection(), _candidates(), _record_by_person())
    assert len(doc["operations"]) == 9
    assert [op["person_id"] for op in doc["operations"]] == IDS
    assert doc["schema_version"] == "1939-v50-c0-followup-flags-v1"


def test_database_identity_is_carried_through():
    """Uden den kan en eksport fra rehearsal-basen føde et manifest, der køres
    mod prod. D2 spærrede for det med D2_APPLY_DATABASE_MISMATCH."""
    doc = mod.build_flags_document(
        _selection(database_name="postgres", database_identity="764273"),
        _candidates(), _record_by_person())
    assert doc["database_name"] == "postgres"
    assert doc["database_identity"] == "764273"


def test_default_text_is_normalized_not_raw():
    """Rå OCR må ALDRIG nå manifestet: alle ni records har enlige linjeskift,
    og 1299 bærer '### PAGE'. Uden normalisering ville fasen indføre rå tekst
    i en bestand af 551 rensede narrativer."""
    doc = mod.build_flags_document(
        _selection(), _candidates("Revent-\nlow til Gaarz.\n\n### PAGE 0063 ###\n"),
        _record_by_person())
    for op in doc["operations"]:
        assert "### PAGE" not in op["default_text"]
        assert "-\n" not in op["default_text"]
        assert not op["default_text"].endswith(("\n", " "))


def test_side_mismatch_is_terminal():
    """narrative.side vs recordens page_from er en IDENTITETSKONTROL: den
    beviser at vi rammer den rigtige post. Målt 2026-08-21: 9/9 match."""
    sel = _selection()
    sel["selected"][0]["side"] = "999"
    with pytest.raises(SystemExit, match="C0F_FLAGS_SIDE_MISMATCH"):
        mod.build_flags_document(sel, _candidates(), _record_by_person())


def test_side_null_is_terminal():
    sel = _selection()
    sel["selected"][0]["side"] = None
    with pytest.raises(SystemExit, match="C0F_FLAGS_SIDE_MISSING"):
        mod.build_flags_document(sel, _candidates(), _record_by_person())


def test_missing_record_is_terminal():
    rbp = _record_by_person()
    del rbp[963]
    with pytest.raises(SystemExit, match="C0F_FLAGS_RECORD_MISSING"):
        mod.build_flags_document(_selection(), _candidates(), rbp)


def test_person_1017_is_rejected():
    """1017 er flyttet til C3: dens kobling ville slette ~92 tegn permanent."""
    sel = _selection()
    sel["selected"][0]["person_id"] = 1017
    with pytest.raises(SystemExit, match="C0F_FLAGS_IDS_INVALID"):
        mod.build_flags_document(sel, _candidates(), _record_by_person())


def test_empty_normalized_text_is_terminal():
    with pytest.raises(SystemExit, match="C0F_FLAGS_TEXT_EMPTY"):
        mod.build_flags_document(_selection(), _candidates("   \n  "),
                                 _record_by_person())


def test_flag_ids_are_unique_and_sorted():
    doc = mod.build_flags_document(
        _selection(), _candidates("Revent-\nlow og Futter-\nkamp.\n"),
        _record_by_person())
    ids = [f["flag_id"] for op in doc["operations"] for f in op["flags"]]
    assert len(ids) == len(set(ids))
    assert ids == sorted(ids)
