"""DB-frie tests for manifest-byggeren."""
import hashlib
import importlib.util
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "c0f_manifest", _DIR / "build_c0_followup_manifest_1939_v50.py")
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)

RAW = "Revent-\nlow til Gaarz.\n"


def _flags_doc():
    import importlib.util as iu
    spec = iu.spec_from_file_location(
        "c0f_flags", _DIR / "build_c0_followup_flags_1939_v50.py")
    flags_mod = iu.module_from_spec(spec)
    spec.loader.exec_module(flags_mod)
    default = flags_mod.normalize_narrative_v1(RAW, RAW)
    return {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "operations": [{
            "person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
            "source_record_key": "record-y", "page_from": 504,
            "default_text": default["text"],
            "flags": [dict(f, flag_id="record-y:%d:%s" % (f["char_offset"], f["kind"]),
                           person_id=992, source_record_key="record-y")
                      for f in default["flags"]],
        }],
        "flag_counts": {"hyphen_unproven": len(default["flags"])},
    }


def _candidates():
    return {"records": [{"new_record_key": "record-y", "verbatim_text": RAW,
                         "pages": {"page_from": 504, "page_to": 504}}]}


def _decisions(doc, action="merge"):
    return {"decisions": {f["flag_id"]: action
                          for op in doc["operations"] for f in op["flags"]},
            "accepted_person_ids": [992]}


def test_default_decisions_reproduce_default_text():
    doc = _flags_doc()
    man = mod.build_manifest(doc, _decisions(doc), _candidates())
    assert man["operations"][0]["new_text"] == doc["operations"][0]["default_text"]


def test_keep_changes_the_text():
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    man = mod.build_manifest(doc, _decisions(doc, "keep"), _candidates())
    assert man["operations"][0]["new_text"] != doc["operations"][0]["default_text"]


def test_rejected_person_is_excluded():
    doc = _flags_doc()
    dec = _decisions(doc)
    dec["accepted_person_ids"] = []
    with pytest.raises(SystemExit, match="C0F_MANIFEST_EMPTY"):
        mod.build_manifest(doc, dec, _candidates())


def test_missing_decision_is_terminal():
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    dec = _decisions(doc)
    dec["decisions"] = {}
    with pytest.raises(SystemExit, match="C0F_MANIFEST_DECISION_MISSING"):
        mod.build_manifest(doc, dec, _candidates())


def test_new_text_sha256_matches_the_text():
    doc = _flags_doc()
    man = mod.build_manifest(doc, _decisions(doc), _candidates())
    op = man["operations"][0]
    assert op["new_text_sha256"] == hashlib.sha256(
        op["new_text"].encode("utf-8")).hexdigest()


def test_invariants_are_reasserted_after_splice():
    """Et splice kan i princippet genindføre et brud; invarianterne hævdes
    derfor igen på den FÆRDIGE tekst, ikke kun på default_text."""
    doc = _flags_doc()
    doc["operations"][0]["default_text"] += "\n### PAGE 0001 ###"
    with pytest.raises(SystemExit, match="C0F_MANIFEST_INVARIANT"):
        mod.build_manifest(doc, _decisions(doc), _candidates())
