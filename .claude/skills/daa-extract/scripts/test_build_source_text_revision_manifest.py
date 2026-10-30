"""Kildetekst-revisionens manifest (trin 6a, spec §4.4). Syntetisk rendition og tekst — ingen bogtekst.

Renditionen har tre poster. Post I-1 har en mellemlinje, som v1-støjreglen (anywhere) fjerner og v2
(page_header) bevarer: samme spænd, ny tekst → operation. Post I-2 har en halelinje efter postens sidste
v1-linje: v2-spændet går ud over helpostens → disposition span_outside (I-84's form). Post I-3 har kun et
sidehoved, som begge regler fjerner: uændret.
"""
import copy
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

import build_clause_ledger
import build_source_text_revision_manifest as B
import clause_segment
import reimport_profile as rp

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[3]
PROFILE_2018 = HERE.parent / "references/reimport-profiles/daa-2018-20-source-text-revision-v1.json"
EXPECTED_2018_SHA = "60c7deaa352a3d7916ef35aba160a8f602c931474dd093a0dd1d6873d0a16f45"

RENDITION = ("### PAGE 10 ###\n"
             "I\n"
             "DEN PRØVESKE LINJE\n"
             "1.  Alfa Bravo, f. 1801. Gift 1830\n"
             "von Revisor prøvelinje\n"
             "m. Charlie Delta.\n"
             "2.  Echo Foxtrot, f. 1802.\n"
             "von Revisor halelinje\n"
             "### PAGE 11 ###\n"
             "von Revisor sidehoved\n"
             "3.  Golf Hotel, f. 1803.\n")
V1 = {"I-1": "Alfa Bravo, f. 1801. Gift 1830 m. Charlie Delta.", "I-2": "Echo Foxtrot, f. 1802."}
V2_I1 = "Alfa Bravo, f. 1801. Gift 1830 von Revisor prøvelinje m. Charlie Delta."
SPAN = {"I-1": (41, 112), "I-2": (117, 139)}
KEYS = ["0b000000-0000-4000-8000-000000000001", "1a000000-0000-4000-8000-000000000002",
        "f0000000-0000-4000-8000-000000000003"]
BINDINGS = [{"promotion_id": "2c000000-0000-4000-8000-000000000001", "target_type": "assertion"},
            {"promotion_id": "d4000000-0000-4000-8000-000000000002", "target_type": "family"}]


def _sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


RENDITION_SHA = _sha(RENDITION)


def _profile(tmp_path, count=1, **overrides):
    raw = json.loads(PROFILE_2018.read_text(encoding="utf-8"))
    raw["writer_config"] = dict(raw["writer_config"], citation_label_template="Syntetisk side {page_from}",
                                rendition_key="syntetisk-r1",
                                rendition_metadata={"edition": "syntetisk", "pdf_sha256": "a" * 64,
                                                    "pdftotext_version": "syntetisk 0.0"})
    raw.update(source_id=7, profile_id="syntetisk-source-text-revision-v1", raw_text_sha256=RENDITION_SHA,
               segmenter_version=build_clause_ledger.segmenter_version(),
               expected_counts={"source_text_revision": count})
    raw.update(overrides)
    path = tmp_path / "profile.json"
    path.write_text(json.dumps(raw), encoding="utf-8")
    return rp.load_profile(path)


def _texts(**override):
    rows = []
    for key in ("I-1", "I-2", "I-3"):
        text = V1.get(key, "Golf Hotel, f. 1803.")
        span = SPAN.get(key, (204, 224))
        rows.append({"record_key": key, "occurrence_key": f"occ-{key}", "page_from": 10, "page_to": 10,
                     "char_from": span[0], "char_to": span[1], "text_id": None, "verbatim_text": text,
                     "verbatim_sha256": _sha(text), "rendition_content_sha256": RENDITION_SHA})
    for row in rows:
        row.update(override.get(row["record_key"], {}))
    return rows


def _deps(profile, **override):
    records = []
    for key in ("I-1", "I-2"):
        records.append({"record_key": key, "helpost_status": "ok", "rendition_content_sha256": RENDITION_SHA,
                        "char_from": SPAN[key][0], "char_to": SPAN[key][1], "text_id": None,
                        "before_text_sha256": _sha(V1[key]), "clause_set_seq": 1, "clause_set_sha256": "c" * 64,
                        "expected_superseded_keys": list(KEYS) if key == "I-1" else [],
                        "expected_binding_loss": copy.deepcopy(BINDINGS) if key == "I-1" else []})
        records[-1].update(override.get(key, {}))
    return {"schema_version": "source-text-revision-dependencies-v1", "source_id": profile["source_id"],
            "profile_id": profile["profile_id"], "profile_sha256": profile["profile_sha256"],
            "helpost_kind": "person_post", "records": records}


def _build(profile, texts=None, deps=None):
    return B.build_manifest(profile, RENDITION.encode("utf-8"), texts if texts is not None else _texts(),
                            deps if deps is not None else _deps(profile), "1" * 64, "2" * 64)


def test_same_span_revision_emitted(tmp_path):
    profile = _profile(tmp_path)
    m = _build(profile)
    assert [op["source_record_key"] for op in m["operations"]] == ["I-1"]
    op = m["operations"][0]
    # Præcis writerens lukkede nøglesæt plus de to manifestfelter, som R fjerner før kaldet.
    assert set(op) - {"element_id", "dependency_class"} == set(B.PAYLOAD_KEYS)
    assert op["element_id"] == "source-text-revision:I-1" and op["dependency_class"] == "source_text_revision"
    assert op["verbatim_text"] == V2_I1 and op["after_text_sha256"] == _sha(V2_I1)
    assert op["before_text_sha256"] == _sha(V1["I-1"])
    assert op["projection_rule"] == "folded_projection@page_header"
    assert op["rendition_content_sha256"] == RENDITION_SHA
    assert (op["replaces_clause_set_seq"], op["replaces_clause_set_sha256"]) == (1, "c" * 64)
    assert op["clause_rules_version"] == "clause-rules-2018-20-v3" and op["gap_charset"] == [" "]
    # Klausulerne er v2-tekstens: post-relative offsets skærer teksten; renditionsoffsets ligger i spændet,
    # monotont, og den indskudte linje ligger i en klausul (ikke et hul).
    rules = B._clause_rules("clause-rules-2018-20-v3")
    expected = clause_segment.build_record_ledger("I-1", "occ-I-1", V2_I1, rules)
    assert op["ledger_sha256"] == expected["ledger_sha256"]
    assert [(c["char_from"], c["char_to"]) for c in op["clauses"]] == \
        [(c["char_from"], c["char_to"]) for c in expected["clauses"]]
    prev = SPAN["I-1"][0]
    for clause in op["clauses"]:
        assert set(clause) == set(B.CLAUSE_KEYS)
        assert _sha(V2_I1[clause["char_from"]:clause["char_to"]]) == clause["verbatim_sha256"]
        assert prev <= clause["rendition_char_from"] < clause["rendition_char_to"] <= SPAN["I-1"][1]
        prev = clause["rendition_char_to"]
    assert any("prøvelinje" in V2_I1[c["char_from"]:c["char_to"]] for c in op["clauses"])
    assert m["expected_counts"] == {"source_evidence": 0, "person_creates": 0, "canonical_delta": 0,
                                    "source_text_revision": 1}
    assert m["source"] == {"id": 7, "profile_id": "syntetisk-source-text-revision-v1",
                           "profile_sha256": profile["profile_sha256"]}
    unhashed = {k: v for k, v in m.items() if k != "manifest_content_sha256"}
    assert m["manifest_content_sha256"] == B._canonical_sha256(unhashed)


def test_span_outside_goes_to_dispositions(tmp_path):
    m = _build(_profile(tmp_path))
    assert "I-2" not in [op["source_record_key"] for op in m["operations"]]
    assert m["dispositions"] == [{"record_key": "I-2", "code": "span_outside",
                                  "helpost_char_from": 117, "helpost_char_to": 139,
                                  "revised_char_from": 117, "revised_char_to": 161,
                                  "before_text_sha256": _sha(V1["I-2"]),
                                  "after_text_sha256": _sha("Echo Foxtrot, f. 1802. von Revisor halelinje")}]
    # Ingen tekst i dispositionen.
    assert "Echo" not in json.dumps(m["dispositions"], ensure_ascii=False)


def test_v1_mismatch_fails(tmp_path):
    profile = _profile(tmp_path)
    # Basen har en anden gældende tekst (fx efter en gennemført revision): før-hashen stemmer ikke med v1.
    other = "Alfa Bravo, f. 1801. Gift 1830 m. Charlie Delta. Rettet."
    with pytest.raises(B.BuildError, match="TEXT_REVISION_V1_MISMATCH"):
        _build(profile, texts=_texts(**{"I-1": {"verbatim_text": other, "verbatim_sha256": _sha(other)}}),
               deps=_deps(profile, **{"I-1": {"before_text_sha256": _sha(other)}}))
    with pytest.raises(B.BuildError, match="TEXT_REVISION_V1_MISMATCH"):
        _build(profile, deps=_deps(profile, **{"I-1": {"before_text_sha256": "e" * 64}}))
    # Og helpostens spænd skal være v1-postens.
    with pytest.raises(B.BuildError, match="TEXT_REVISION_V1_SPAN_MISMATCH"):
        _build(profile, texts=_texts(**{"I-1": {"char_to": 111}}), deps=_deps(profile, **{"I-1": {"char_to": 111}}))


def test_expected_sets_sorted_and_copied(tmp_path):
    profile = _profile(tmp_path)
    op = _build(profile)["operations"][0]
    assert op["expected_superseded_keys"] == KEYS
    assert op["expected_binding_loss"] == BINDINGS
    # Kopieret, ikke delt: at ændre afhængighedsfilen bagefter ændrer ikke manifestet.
    deps = _deps(profile)
    op = _build(profile, deps=deps)["operations"][0]
    deps["records"][0]["expected_superseded_keys"].append("ff000000-0000-4000-8000-000000000009")
    deps["records"][0]["expected_binding_loss"][0]["target_type"] = "family"
    assert op["expected_superseded_keys"] == KEYS and op["expected_binding_loss"] == BINDINGS
    # Usorterede, dublerede eller ikke-kanoniske mængder afvises (writeren kræver strengt sorterede uuid'er).
    for bad in (list(reversed(KEYS)), [KEYS[0], KEYS[0]], [KEYS[0].upper()], ["ikke-en-uuid"]):
        with pytest.raises(B.BuildError):
            _build(profile, deps=_deps(profile, **{"I-1": {"expected_superseded_keys": bad}}))
    with pytest.raises(B.BuildError, match="TEXT_REVISION_EXPECTED_SET_NOT_SORTED"):
        _build(profile, deps=_deps(profile, **{"I-1": {"expected_binding_loss": list(reversed(BINDINGS))}}))
    with pytest.raises(B.BuildError, match="TEXT_REVISION_DEPENDENCIES_INVALID"):
        _build(profile, deps=_deps(profile, **{"I-1": {"expected_binding_loss": [dict(BINDINGS[0], interpretation_key=KEYS[0])]}}))


def test_dependencies_must_cover_exactly_the_changed_records(tmp_path):
    profile = _profile(tmp_path)
    deps = _deps(profile)
    deps["records"] = deps["records"][:1]
    with pytest.raises(B.BuildError, match="TEXT_REVISION_DEPENDENCIES_SET_MISMATCH"):
        _build(profile, deps=deps)
    with pytest.raises(B.BuildError, match="TEXT_REVISION_HELPOST_INVALID"):
        _build(profile, deps=_deps(profile, **{"I-1": {"helpost_status": "outside"}}))
    with pytest.raises(B.BuildError, match="TEXT_REVISION_DEPENDENCIES_PROFILE_MISMATCH"):
        _build(profile, deps=dict(_deps(profile), profile_sha256="0" * 64))
    with pytest.raises(B.BuildError, match="TEXT_REVISION_TEXTS_DEPENDENCIES_MISMATCH"):
        _build(profile, texts=_texts(**{"I-1": {"occurrence_key": None}}))


def test_count_rendition_and_versions_fail_closed(tmp_path):
    with pytest.raises(B.BuildError, match="TEXT_REVISION_COUNT_MISMATCH"):
        _build(_profile(tmp_path, count=2))
    profile = _profile(tmp_path)
    with pytest.raises(B.BuildError, match="TEXT_REVISION_RENDITION_SHA_MISMATCH"):
        B.build_manifest(profile, (RENDITION + "\n").encode("utf-8"), _texts(), _deps(profile), "1" * 64, "2" * 64)
    with pytest.raises(B.BuildError, match="TEXT_REVISION_SEGMENTER_VERSION_MISMATCH"):
        _build(_profile(tmp_path, segmenter_version="clause_segment.py@v1"))
    with pytest.raises(B.BuildError, match="TEXT_REVISION_TEXT_FORM_MISMATCH"):
        _build(_profile(tmp_path, segment_profile_after="2018-20", segment_profile_before="2018-20-v2"))
    with pytest.raises(B.BuildError, match="TEXT_REVISION_CLAUSE_RULES_NOT_UNIQUE"):
        _build(_profile(tmp_path, clause_rules_version="clause-rules-findes-ikke"))


def _run_cli(tmp_path, *extra):
    profile = _profile(tmp_path)
    texts = tmp_path / "texts.json"
    texts.write_text(json.dumps(_texts(), ensure_ascii=False), encoding="utf-8")
    deps = tmp_path / "deps.json"
    deps.write_text(json.dumps(_deps(profile)), encoding="utf-8")
    rendition = tmp_path / "rendition.txt"
    rendition.write_bytes(RENDITION.encode("utf-8"))
    out = tmp_path / "ud"
    out.mkdir(mode=0o700)
    out.chmod(0o700)
    args = [sys.executable, str(HERE / "build_source_text_revision_manifest.py"), "--profile", str(tmp_path / "profile.json"),
            "--rendition", str(rendition)]
    args += list(extra) if extra else ["--texts", str(texts), "--dependencies", str(deps), "--output", str(out)]
    return subprocess.run(args, capture_output=True, text=True), out


def test_no_text_in_index_output(tmp_path):
    result, out = _run_cli(tmp_path)
    assert result.returncode == 0, result.stderr
    index_text = (out / B.INDEX_NAME).read_text(encoding="utf-8")
    index = json.loads(index_text)
    assert "verbatim_text" not in index_text
    for text in (V2_I1, V1["I-1"], "Alfa", "Echo", "Revisor"):
        assert text not in index_text and text not in result.stdout and text not in result.stderr
    manifest_path = out / B.MANIFEST_NAME
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["operations"][0]["verbatim_text"] == V2_I1      # payloaden bærer teksten til writeren
    assert index["manifest_content_sha256"] == manifest["manifest_content_sha256"]
    assert index["manifest_file_sha256"] == hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    assert index["counts"] == {"operations": 1, "dispositions": 1, "clauses": len(manifest["operations"][0]["clauses"]),
                               "superseded_keys": 3, "binding_loss": 2}
    assert [d["code"] for d in index["dispositions"]] == ["span_outside"]
    for path in (manifest_path, out / B.INDEX_NAME):
        assert (path.stat().st_mode & 0o777) == 0o600
    stdout = json.loads(result.stdout)
    assert stdout["record_keys"] == ["I-1"] and stdout["dispositions"] == [{"record_key": "I-2", "code": "span_outside"}]
    # Anden kørsel mod samme mappe overskriver ikke.
    again = subprocess.run([sys.executable, str(HERE / "build_source_text_revision_manifest.py"),
                            "--profile", str(tmp_path / "profile.json"), "--rendition", str(tmp_path / "rendition.txt"),
                            "--texts", str(tmp_path / "texts.json"), "--dependencies", str(tmp_path / "deps.json"),
                            "--output", str(out)], capture_output=True, text=True)
    assert again.returncode != 0 and "TEXT_REVISION_OUTPUT_EXISTS" in again.stderr


def test_list_changed_keys_has_no_text(tmp_path):
    result, _ = _run_cli(tmp_path, "--list-changed-keys")
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == {"changed": 2, "record_keys": ["I-1", "I-2"]}
    assert "Alfa" not in result.stdout and "Alfa" not in result.stderr


def test_output_dir_rules(tmp_path):
    work = tmp_path / "work"
    work.mkdir(mode=0o700)
    profile = _profile(tmp_path)
    result = subprocess.run([sys.executable, str(HERE / "build_source_text_revision_manifest.py"),
                             "--profile", str(tmp_path / "profile.json"), "--rendition", "/dev/null",
                             "--texts", "/dev/null", "--dependencies", "/dev/null", "--output", str(work)],
                            capture_output=True, text=True)
    assert result.returncode != 0 and "OUTPUT_WORK_PATH" in result.stderr
    loose = tmp_path / "aaben"
    loose.mkdir()
    loose.chmod(0o755)
    result = subprocess.run([sys.executable, str(HERE / "build_source_text_revision_manifest.py"),
                             "--profile", str(tmp_path / "profile.json"), "--rendition", "/dev/null",
                             "--texts", "/dev/null", "--dependencies", "/dev/null", "--output", str(loose)],
                            capture_output=True, text=True)
    assert result.returncode != 0 and "OUTPUT_DIR_MODE_INVALID" in result.stderr
    assert profile["profile_id"]


# --- Profilen: hash lig basens seed (R12-a) ----------------------------------------------------------

def _seed_writer_config(sql_file, profile_id):
    """writer_config-strengen i INSERT-rækken for profilen, læst direkte fra SQL-filen (ikke kommentaren)."""
    import re
    text = (REPO_ROOT / sql_file).read_text(encoding="utf-8")
    start = text.index(f"SELECT 1,'{profile_id}'")
    match = re.search(r"VALUES \(\s*'(\{.*?\})'::jsonb", text[start:], re.S)
    assert match, sql_file
    return json.loads(match.group(1))


@pytest.mark.parametrize("sql_file", ["schema.sql", "db-migrations.sql"])
def test_2018_revision_profile_hash_matches_db_seed(sql_file):
    profile = rp.load_profile(PROFILE_2018)
    seeded = _seed_writer_config(sql_file, profile["profile_id"])
    assert profile["writer_config"] == seeded
    assert profile["profile_sha256"] == rp.canonical_json_sha256(seeded) == EXPECTED_2018_SHA
    assert profile["expected_counts"] == {"source_text_revision": 10}
    assert profile["segmenter_version"] == build_clause_ledger.segmenter_version()
    assert profile["writer_config"]["text_form"] == "folded_projection@page_header"


def test_revision_profile_schema_is_closed(tmp_path):
    raw = json.loads(PROFILE_2018.read_text(encoding="utf-8"))
    for mutate in (lambda r: r.pop("segment_profile_after"),
                   lambda r: r.update(expected_counts={"source_text_revision": 10, "source_evidence": 0}),
                   lambda r: r.update(expected_counts={"source_text_revisions": 10}),
                   lambda r: r["writer_config"].pop("text_form"),
                   lambda r: r["writer_config"].update(text_form="raw"),
                   lambda r: r.update(segment_profile_before=r["segment_profile_after"])):
        bad = copy.deepcopy(raw)
        mutate(bad)
        path = tmp_path / "bad.json"
        path.write_text(json.dumps(bad), encoding="utf-8")
        with pytest.raises(rp.ProfileError):
            rp.load_profile(path)
