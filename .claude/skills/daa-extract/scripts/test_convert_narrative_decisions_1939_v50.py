from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

import convert_narrative_decisions_1939_v50 as subject
from convert_narrative_decisions_1939_v50 import (
    DecisionsFileError,
    assign_fids,
    convert_edited_document,
    generate_document,
    load_flags_document,
    partition_sections,
    render_document,
    sorted_flags,
)
from normalize_narrative_1939_v50 import normalize_narrative_v1


SCRIPT_PATH = Path(__file__).resolve().parent / "convert_narrative_decisions_1939_v50.py"

REAL_FLAGS_PATH = Path(
    "/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/"
    "evidensbaseret-genimport/work/task25-1939-v50-production-writer/"
    "narrative-replacement-flags-v1.json"
)
REAL_FLAGS_SHA256 = "707e993fa73aebb626bebe1414f3e6e4c7f790cc357556d29bf437be50d5d47e"
KAROG_FLAG_ID = "record-04d54b46-b9ee-423b-833d-5037b0178f0e:100:hyphen_unproven"


def _sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _sha256_text(text: str) -> str:
    return _sha256_bytes(text.encode("utf-8"))


# ---------------------------------------------------------------------------
# Synthetic fixture -- a small flags document covering all 3 kinds, built
# from REAL normalize_narrative_v1 output (so context/char_offset/word-runs
# are genuine, not hand-guessed) but wrapped as a standalone flags document
# (this script never reads phase-a/production manifests, only the flags
# file's own `flags` list).
# ---------------------------------------------------------------------------

RAW_HYPHEN_UNPROVEN = "Han sammen-\ntraekkes med andre og skrev en bog om Skivehus."
RAW_HYPHEN_UNPROVEN_STOPTAIL = "Han blev der-\nog blev boende i mange aar."
RAW_HYPHEN_AMBIGUOUS = "Ejede Skivehus i Norre H. (1735-\n50), Osterrade."
RAW_ORDINAL_AMBIGUOUS = "7 Heinrich til Gottesgabe, f. 1800 i Kbhvn."

CONTEXT_RADIUS = subject.FLAGS_FILE_CONTEXT_RADIUS


def _context(raw: str, offset: int) -> str:
    lo = max(0, offset - CONTEXT_RADIUS)
    hi = min(len(raw), offset + CONTEXT_RADIUS)
    return raw[lo:hi]


def _flag_row(record_key: str, raw: str, kind: str, person_id: int, page_from: int) -> dict:
    result = normalize_narrative_v1(raw, corpus="")
    matches = [f for f in result["flags"] if f["kind"] == kind]
    assert matches, f"fixture raw did not produce a {kind} flag: {raw!r}"
    flag = matches[0]
    offset = flag["char_offset"]
    suggested = {"hyphen_unproven": "merge", "hyphen_ambiguous": "keep", "ordinal_ambiguous": "keep"}[kind]
    return {
        "flag_id": f"{record_key}:{offset}:{kind}",
        "kind": kind,
        "context": _context(raw, offset),
        "char_offset": offset,
        "person_id": person_id,
        "source_record_key": record_key,
        "page_from": page_from,
        "suggested_default_action": suggested,
    }


def fixture_flags_doc() -> dict:
    flags = [
        _flag_row("record-A", RAW_HYPHEN_UNPROVEN, "hyphen_unproven", 501, 500),
        _flag_row("record-B", RAW_HYPHEN_UNPROVEN_STOPTAIL, "hyphen_unproven", 502, 500),
        _flag_row("record-C", RAW_HYPHEN_AMBIGUOUS, "hyphen_ambiguous", 503, 501),
        _flag_row("record-D", RAW_ORDINAL_AMBIGUOUS, "ordinal_ambiguous", 504, 502),
    ]
    flags.sort(key=lambda f: f["flag_id"])
    doc = {
        "schema_version": "1939-v50-narrative-replacement-flags-v1",
        "flags": flags,
        "flag_counts": {"hyphen_unproven": 2, "hyphen_ambiguous": 1, "ordinal_ambiguous": 1, "total": 4},
    }
    return doc


def write_flags_file(tmp_path: Path) -> tuple[Path, str]:
    doc = fixture_flags_doc()
    text = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    path = tmp_path / "flags.json"
    path.write_text(text, encoding="utf-8")
    return path, _sha256_text(text)


# ---------------------------------------------------------------------------
# F-id assignment + partitioning
# ---------------------------------------------------------------------------

def test_fid_assignment_is_deterministic_flag_id_sorted():
    doc = fixture_flags_doc()
    flags_sorted = sorted_flags(doc)
    fid_by_flag_id, flag_by_fid = assign_fids(flags_sorted)
    assert list(fid_by_flag_id.values()) == [f"F{i:03d}" for i in range(1, len(flags_sorted) + 1)]
    # re-running on the same doc (any input order) gives the identical mapping
    shuffled = {"flags": list(reversed(doc["flags"])), "schema_version": doc["schema_version"]}
    fid_by_flag_id_2, _ = assign_fids(sorted_flags(shuffled))
    assert fid_by_flag_id == fid_by_flag_id_2


def test_partition_sections_covers_every_flag_exactly_once():
    doc = fixture_flags_doc()
    flags_sorted = sorted_flags(doc)
    sections = partition_sections(flags_sorted)
    total = sum(len(v) for v in sections.values())
    assert total == len(flags_sorted)
    all_ids_in_sections = [f["flag_id"] for group in sections.values() for f in group]
    assert sorted(all_ids_in_sections) == sorted(f["flag_id"] for f in flags_sorted)
    # record-B's merged word ends on a Danish stopword ("og") -> suspicious
    assert any(f["source_record_key"] == "record-B" for f in sections["suspicious"])
    assert not any(f["source_record_key"] == "record-B" for f in sections["rest"])


# ---------------------------------------------------------------------------
# Round trip: generate -> flip 3 tokens -> convert -> expected decisions
# ---------------------------------------------------------------------------

def test_round_trip_unedited_document_uses_suggested_defaults():
    doc = fixture_flags_doc()
    text = generate_document(doc)
    decisions = convert_edited_document(doc, text)
    assert decisions == {f["flag_id"]: f["suggested_default_action"] for f in doc["flags"]}


def test_round_trip_flip_three_tokens_changes_only_those_actions():
    doc = fixture_flags_doc()
    flags_sorted = sorted_flags(doc)
    fid_by_flag_id, flag_by_fid = assign_fids(flags_sorted)
    text = generate_document(doc)

    # Flip: record-A merge->keep, record-C keep->merge, record-D keep->strip.
    flag_a_id = next(f["flag_id"] for f in flags_sorted if f["source_record_key"] == "record-A")
    fid_a = fid_by_flag_id[flag_a_id]
    flag_a = flag_by_fid[fid_a]
    fid_c = fid_by_flag_id[[f["flag_id"] for f in flags_sorted if f["source_record_key"] == "record-C"][0]]
    fid_d = fid_by_flag_id[[f["flag_id"] for f in flags_sorted if f["source_record_key"] == "record-D"][0]]

    edited = text
    edited = edited.replace(f"[MERGE] {fid_a}", f"[KEEP]  {fid_a}", 1)
    edited = edited.replace(f"[KEEP]  {fid_c}", f"[MERGE] {fid_c}", 1)
    edited = edited.replace(f"[KEEP]  {fid_d}", f"[STRIP] {fid_d}", 1)

    decisions = convert_edited_document(doc, edited)
    expected = {f["flag_id"]: f["suggested_default_action"] for f in doc["flags"]}
    expected[flag_a["flag_id"]] = "keep"
    expected[flag_by_fid[fid_c]["flag_id"]] = "merge"
    expected[flag_by_fid[fid_d]["flag_id"]] = "strip"
    assert decisions == expected


def test_accepts_token_replaced_in_place_without_realigning_columns():
    """A human editing `[MERGE]` -> `[KEEP]` in place leaves one space, not
    two. Padding between token and F-id is presentation, not contract."""
    doc = fixture_flags_doc()
    flags_sorted = sorted_flags(doc)
    fid_by_flag_id, flag_by_fid = assign_fids(flags_sorted)
    fid_a = fid_by_flag_id[
        next(f["flag_id"] for f in flags_sorted if f["source_record_key"] == "record-A")
    ]

    # No padding compensation: exactly what an editor produces.
    edited = generate_document(doc).replace(f"[MERGE] {fid_a}", f"[KEEP] {fid_a}", 1)
    assert f"[KEEP] {fid_a}" in edited and f"[KEEP]  {fid_a}" not in edited

    decisions = convert_edited_document(doc, edited)
    expected = {f["flag_id"]: f["suggested_default_action"] for f in doc["flags"]}
    expected[flag_by_fid[fid_a]["flag_id"]] = "keep"
    assert decisions == expected


def test_realignment_tolerance_does_not_mask_context_edits():
    """The relaxed padding must not weaken the byte-identity gate: an edit
    elsewhere on a re-aligned line is still rejected."""
    doc = fixture_flags_doc()
    flags_sorted = sorted_flags(doc)
    fid_a = assign_fids(flags_sorted)[0][
        next(f["flag_id"] for f in flags_sorted if f["source_record_key"] == "record-A")
    ]
    edited = generate_document(doc).replace(f"[MERGE] {fid_a}", f"[KEEP] {fid_a}", 1)
    edited = edited.replace("s. 500", "s. 999", 1)
    with pytest.raises(subject.DecisionsFileError) as excinfo:
        convert_edited_document(doc, edited)
    assert "DECISIONS_LINE_MISMATCH" in str(excinfo.value)


# ---------------------------------------------------------------------------
# Rejections
# ---------------------------------------------------------------------------

def test_rejects_edited_context():
    doc = fixture_flags_doc()
    text = generate_document(doc)
    lines = text.split("\n")
    idx = next(i for i, l in enumerate(lines) if l.startswith("[MERGE] F001") or l.startswith("[KEEP]  F001"))
    lines[idx] = lines[idx].replace("»", "«EDITED»", 1)
    with pytest.raises(DecisionsFileError, match=r"DECISIONS_LINE_MISMATCH:\d+"):
        convert_edited_document(doc, "\n".join(lines))


def test_rejects_missing_fid():
    doc = fixture_flags_doc()
    text = generate_document(doc)
    lines = [l for l in text.split("\n") if not l.startswith("[MERGE] F001") and not l.startswith("[KEEP]  F001")]
    with pytest.raises(DecisionsFileError, match="DECISIONS_MISSING_FID:F001"):
        convert_edited_document(doc, "\n".join(lines))


def test_rejects_duplicated_fid():
    doc = fixture_flags_doc()
    text = generate_document(doc)
    lines = text.split("\n")
    idx = next(i for i, l in enumerate(lines) if l.startswith("[MERGE] F001") or l.startswith("[KEEP]  F001"))
    lines = lines[: idx + 1] + [lines[idx]] + lines[idx + 1 :]
    with pytest.raises(DecisionsFileError, match="DECISIONS_DUPLICATE_FID:F001"):
        convert_edited_document(doc, "\n".join(lines))


def test_rejects_invalid_token_for_kind():
    doc = fixture_flags_doc()
    flags_sorted = sorted_flags(doc)
    fid_by_flag_id, _ = assign_fids(flags_sorted)
    ordinal_flag_id = [f["flag_id"] for f in flags_sorted if f["kind"] == "ordinal_ambiguous"][0]
    fid = fid_by_flag_id[ordinal_flag_id]
    text = generate_document(doc)
    # ordinal_ambiguous only accepts [STRIP]/[KEEP] -- [MERGE] is invalid
    edited = text.replace(f"[KEEP]  {fid}", f"[MERGE] {fid}", 1)
    with pytest.raises(DecisionsFileError, match=f"DECISIONS_TOKEN_INVALID_FOR_KIND:{ordinal_flag_id}"):
        convert_edited_document(doc, edited)


def test_rejects_unbalanced_line_count():
    doc = fixture_flags_doc()
    text = generate_document(doc)
    with pytest.raises(DecisionsFileError, match="DECISIONS_LINE_COUNT_MISMATCH"):
        convert_edited_document(doc, text + "en ekstra linje som ikke burde vaere her\n")


def test_load_flags_document_rejects_hash_mismatch(tmp_path):
    path, _ = write_flags_file(tmp_path)
    with pytest.raises(DecisionsFileError, match="DECISIONS_FLAGS_HASH_MISMATCH"):
        load_flags_document(path, "0" * 64)


# ---------------------------------------------------------------------------
# CLI (subprocess, exercises argparse + file I/O + output-exists guard)
# ---------------------------------------------------------------------------

def test_cli_generate_then_convert_round_trip(tmp_path):
    flags_path, flags_sha = write_flags_file(tmp_path)
    txt_path = tmp_path / "afgoerelser.txt"

    r1 = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "generate",
         "--flags-file", str(flags_path), "--flags-file-sha256", flags_sha,
         "--output", str(txt_path)],
        capture_output=True, text=True,
    )
    assert r1.returncode == 0, r1.stderr
    assert txt_path.exists()

    # generate refuses to overwrite an existing output
    r1b = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "generate",
         "--flags-file", str(flags_path), "--flags-file-sha256", flags_sha,
         "--output", str(txt_path)],
        capture_output=True, text=True,
    )
    assert r1b.returncode != 0
    assert "DECISIONS_OUTPUT_EXISTS" in r1b.stderr

    edited_sha = _sha256_bytes(txt_path.read_bytes())
    out_path = tmp_path / "decisions.json"
    r2 = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "convert",
         "--flags-file", str(flags_path), "--flags-file-sha256", flags_sha,
         "--edited-file", str(txt_path), "--edited-file-sha256", edited_sha,
         "--output", str(out_path)],
        capture_output=True, text=True,
    )
    assert r2.returncode == 0, r2.stderr
    written = json.loads(out_path.read_text(encoding="utf-8"))
    assert written["schema_version"] == "1939-v50-narrative-decisions-v1"
    doc = fixture_flags_doc()
    assert set(written["decisions"]) == {f["flag_id"] for f in doc["flags"]}


def test_cli_convert_rejects_edited_file_hash_mismatch(tmp_path):
    flags_path, flags_sha = write_flags_file(tmp_path)
    txt_path = tmp_path / "afgoerelser.txt"
    txt_path.write_text(generate_document(fixture_flags_doc()), encoding="utf-8")
    out_path = tmp_path / "decisions.json"
    r = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "convert",
         "--flags-file", str(flags_path), "--flags-file-sha256", flags_sha,
         "--edited-file", str(txt_path), "--edited-file-sha256", "0" * 64,
         "--output", str(out_path)],
        capture_output=True, text=True,
    )
    assert r.returncode != 0
    assert "DECISIONS_EDITED_FILE_HASH_MISMATCH" in r.stderr
    assert not out_path.exists()


# ---------------------------------------------------------------------------
# Real artifacts (skipped if the work/ files are absent -- mirrors Task 2's
# real-data test pattern)
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not REAL_FLAGS_PATH.exists(), reason="real flags file not present in this checkout")
def test_real_flags_file_178_flags_28_8_2_140_sections():
    doc = load_flags_document(REAL_FLAGS_PATH, REAL_FLAGS_SHA256)
    flags_sorted = sorted_flags(doc)
    assert len(flags_sorted) == 178
    sections = partition_sections(flags_sorted)
    assert len(sections["suspicious"]) == 28
    assert len(sections["hyphen_ambiguous"]) == 8
    assert len(sections["ordinal"]) == 2
    assert len(sections["rest"]) == 140


@pytest.mark.skipif(not REAL_FLAGS_PATH.exists(), reason="real flags file not present in this checkout")
def test_real_flags_karog_curated_override_recommends_keep():
    doc = load_flags_document(REAL_FLAGS_PATH, REAL_FLAGS_SHA256)
    flags_sorted = sorted_flags(doc)
    tokens = subject.default_tokens(flags_sorted)
    assert tokens[KAROG_FLAG_ID] == "[KEEP]"
    karog_flag = next(f for f in flags_sorted if f["flag_id"] == KAROG_FLAG_ID)
    assert karog_flag["suggested_default_action"] == "merge"  # mechanical default would have been merge


@pytest.mark.skipif(not REAL_FLAGS_PATH.exists(), reason="real flags file not present in this checkout")
def test_real_flags_generate_unedited_round_trip_is_deterministic():
    doc = load_flags_document(REAL_FLAGS_PATH, REAL_FLAGS_SHA256)
    text1 = generate_document(doc)
    text2 = generate_document(doc)
    assert text1 == text2
    decisions = convert_edited_document(doc, text1)
    assert len(decisions) == 178
    assert decisions[KAROG_FLAG_ID] == "keep"
