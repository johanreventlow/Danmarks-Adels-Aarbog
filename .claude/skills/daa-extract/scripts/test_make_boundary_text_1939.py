from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

import make_boundary_text_1939 as subject


SOURCE = {
    "edition": "1939",
    "profile_version": "1939-v2",
    "baseline_sha256": "a" * 64,
    "calamari_sha256": "b" * 64,
    "raw_ocr_sha256": "c" * 64,
    "pdf_sha256": "d" * 64,
}


def _boundary(offset: int, *, signals=(), gap_to=None, inner=True):
    before = ({"char_from": 0, "char_to": offset, "baseline_record_key": "a"}
              if inner or offset else None)
    after_offset = offset if gap_to is None else gap_to
    after = ({"char_from": after_offset, "char_to": after_offset + 2,
              "baseline_record_key": "b"} if inner else None)
    return {
        "before": before,
        "after": after,
        "gap": {"char_from": offset, "char_to": after_offset},
        "signals": list(signals),
    }


def _node_call(tmp_path: Path, function: str, *arguments):
    if shutil.which("node") is None:
        pytest.skip("node findes ikke på PATH")
    runner = tmp_path / "runner.js"
    runner.write_text(
        "const fs=require('fs'),vm=require('vm');\n"
        "const context={console,TextEncoder,TextDecoder,setTimeout,clearTimeout};\n"
        "context.globalThis=context; vm.createContext(context);\n"
        "vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),context);\n"
        "const args=JSON.parse(fs.readFileSync(0,'utf8'));\n"
        f"const value=context.DAABoundaryText.{function}(...args);\n"
        "process.stdout.write(JSON.stringify(value));\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        ["node", str(runner), str(subject.UI_PATH)],
        input=json.dumps(arguments, ensure_ascii=False), text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_build_text_model_reuses_boundaries_and_only_shift_signals():
    text = "Første\n1. Forslag\nSidste\n"
    model = {
        "source": SOURCE,
        "boundaries": [
            _boundary(0, inner=False),
            _boundary(7, signals=("laengdeafvigelse", "mangler_eget_hoved"),
                      gap_to=18),
            _boundary(len(text), inner=False),
        ],
    }

    result = subject.build_text_model(text, model)

    assert [item["char_offset"] for item in result["forudsatte_skaeringer"]] == [0, 7, len(text)]
    assert result["forudsatte_skaeringer"][1]["text"] == (
        "=== GRÆNSESKÆRING · SIGNAL mangler_eget_hoved ==="
    )
    assert result["huller"] == [{"char_offset": 7, "tegn": 11}]
    assert result["forslag"] == [{"char_offset": 7}]


def test_page_markers_follow_source_page_lines_and_use_the_pdf_map():
    text = "### PAGE 0001 ###\nBog\n### PAGE 0005 ###\nMere\n"
    result = subject.build_text_model(text, {"source": SOURCE, "boundaries": []})
    assert result["pdf_sider"] == [
        {"char_offset": 18, "pdf_side": 496},
        {"char_offset": 40, "pdf_side": 500},
    ]


def test_compose_and_strip_preserve_source_bytes_including_source_page_marker(tmp_path):
    source = "### PAGE 0001 ###\n1. Ægir\n"
    annotations = [
        {"kind": "pdf", "char_offset": 18, "text": "=== PDF-SIDE 496 ==="},
        {"kind": "boundary", "char_offset": 18, "text": "=== GRÆNSESKÆRING ==="},
    ]
    marked = subject.compose_marked_text(source, annotations)
    parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
    assert parsed["ok"] is True
    assert parsed["bookText"] == source
    assert parsed["gate"]["message"] == "bogteksten er urørt"


def test_byte_gate_reports_inserted_character_line(tmp_path):
    source = "første\nanden\ntredje\n"
    marked = "første\nandenX\ntredje\n"
    parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
    assert parsed["ok"] is True
    assert parsed["gate"] == {
        "ok": False,
        "line": 2,
        "message": "bogteksten er ændret ved linje 2",
    }


def test_byte_gate_does_not_strip_a_deleted_source_page_line(tmp_path):
    source = "før\n### PAGE 0001 ###\nefter\n"
    marked = "før\nefter\n"
    parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
    assert parsed["ok"] is True
    assert parsed["gate"]["ok"] is False
    assert parsed["gate"]["line"] == 2


@pytest.mark.parametrize(
    "marked,line",
    [
        ("tekst\n=== UKENDT ===\n", 2),
        ("tekst [[OCR: x | burde stå y]\n", 1),
        ("tekst [[UDELAD]] uden slut\n", 1),
    ],
)
def test_unknown_markers_and_unpaired_inline_tags_fail_with_line(tmp_path, marked, line):
    parsed = _node_call(tmp_path, "parseMarkedText", marked, "tekst\n")
    assert parsed["ok"] is False
    assert parsed["line"] == line


def test_view_offsets_are_converted_to_source_character_offsets_both_ways(tmp_path):
    source = "A😀\nB\n"
    annotations = [
        {"kind": "boundary", "char_offset": 3, "text": "=== GRÆNSESKÆRING ==="},
        {"kind": "ocr", "char_offset": 4, "staar": "B", "burde_staa": "C"},
    ]
    marked = _node_call(tmp_path, "composeMarkedText", source, annotations)
    parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
    assert [marker["char_offset"] for marker in parsed["markers"]] == [3]
    assert parsed["ocrNotes"] == [{"char_offset": 4, "staar": "B", "burde_staa": "C"}]
    assert parsed["bookText"] == source


def test_export_is_fail_closed_and_accounts_for_boundaries_proposals_and_user_cuts(tmp_path):
    source = "A\n1. B\nC\nD\n"
    initial = [
        {"kind": "boundary", "char_offset": 0, "text": "=== GRÆNSESKÆRING ==="},
        {"kind": "boundary", "char_offset": 2, "text": "=== GRÆNSESKÆRING ==="},
        {"kind": "proposal", "char_offset": 2, "text": "=== FORSLAG? SKÆRING ==="},
    ]
    marked = subject.compose_marked_text(source, [
        initial[0],
        {"kind": "cut", "char_offset": 2, "text": "=== SKÆRING ==="},
        {"kind": "cut", "char_offset": 9, "text": "=== SKÆRING ==="},
    ])
    exported = _node_call(tmp_path, "buildExport", marked, {
        "sourceText": source,
        "source": SOURCE,
        "expectedBoundaryOffsets": [0, 2],
        "expectedProposalOffsets": [2],
    }, "2026-08-09T10:00:00.000Z")
    assert exported["ok"] is True
    payload = exported["value"]
    assert payload["skaeringer"] == [
        {"char_offset": 0, "oprindelse": "forudsat"},
        {"char_offset": 2, "oprindelse": "forudsat"},
        {"char_offset": 9, "oprindelse": "bruger"},
    ]
    assert payload["aendringsregnskab"] == {
        "forudsat": 2, "beholdt": 2, "slettet": 0, "tilfoejet": 1,
        "forslag_forudsat": 1, "forslag_godkendt": 1, "forslag_bortfaldet": 0,
    }

    broken = _node_call(tmp_path, "buildExport", marked.replace("A\n", "AX\n", 1), {
        "sourceText": source,
        "source": SOURCE,
        "expectedBoundaryOffsets": [0, 2],
        "expectedProposalOffsets": [2],
    }, "2026-08-09T10:00:00.000Z")
    assert broken["ok"] is False
    assert "linje 1" in broken["error"]


def test_restore_book_text_keeps_markers_at_nearest_valid_source_line(tmp_path):
    source = "første\nanden\ntredje\n"
    changed = "førsteX\n=== SKÆRING ===\nanden\ntredje\n"
    restored = _node_call(tmp_path, "restoreBookText", changed, source)
    assert restored["ok"] is True
    assert restored["text"] == "første\n=== SKÆRING ===\nanden\ntredje\n"
    assert _node_call(tmp_path, "parseMarkedText", restored["text"], source)["gate"]["ok"] is True


def _write_inputs(tmp_path: Path):
    source_text = "### PAGE 0001 ###\n1. Anders\n"
    calamari = tmp_path / "calamari.txt"
    raw = tmp_path / "raw.txt"
    baseline = tmp_path / "baseline.json"
    queue = tmp_path / "queue.json"
    anchored = tmp_path / "anchored.json"
    source_manifest = tmp_path / "source.json"
    calamari.write_text(source_text, encoding="utf-8")
    raw.write_text(source_text, encoding="utf-8")
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
    source_manifest.write_text(json.dumps({"schema_version": 1, "source": source}), encoding="utf-8")
    queue.write_text(json.dumps({"schema_version": 1, "source": source, "entries": []}), encoding="utf-8")
    anchored.write_text("{}", encoding="utf-8")
    return baseline, queue, source_manifest, calamari, raw, anchored


def _argv(inputs, out, markeringer=None):
    baseline, queue, source, calamari, raw, anchored = inputs
    argv = ["make_boundary_text_1939.py", "--baseline", str(baseline),
            "--queue-manifest", str(queue), "--source-manifest", str(source),
            "--calamari", str(calamari), "--raw", str(raw),
            "--anchored", str(anchored), "--out", str(out)]
    if markeringer is not None:
        argv.extend(["--markeringer", str(markeringer)])
    return argv


def test_main_writes_parseable_html_and_refuses_overwrite(tmp_path, monkeypatch):
    inputs = _write_inputs(tmp_path)
    out = tmp_path / "flade.html"
    monkeypatch.setattr(sys, "argv", _argv(inputs, out))
    assert subject.main() == 0
    rendered = out.read_text(encoding="utf-8")
    assert "<textarea" in rendered
    assert "DAABoundaryText.init" in rendered

    script = rendered.split("<script>", 1)[1].split("</script>", 1)[0]
    script_path = tmp_path / "generated.js"
    script_path.write_text(script, encoding="utf-8")
    result = subprocess.run(["node", "--check", str(script_path)], text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    assert "\\n(function (global)" not in script

    monkeypatch.setattr(sys, "argv", _argv(inputs, out))
    with pytest.raises(FileExistsError):
        subject.main()


def test_export_reload_round_trip_reconstructs_the_same_marked_surface(tmp_path):
    source = "A\n1. B\nC\n"
    base = [
        {"kind": "boundary", "char_offset": 0, "text": "=== GRÆNSESKÆRING ==="},
        {"kind": "proposal", "char_offset": 2, "text": "=== FORSLAG? SKÆRING ==="},
    ]
    edited_annotations = [
        {"kind": "cut", "char_offset": 2, "text": "=== SKÆRING ==="},
        {"kind": "cut", "char_offset": 7, "text": "=== SKÆRING ==="},
        {"kind": "ocr", "char_offset": 9, "staar": "C", "burde_staa": "D"},
        {"kind": "udelad_start", "char_offset": 0},
        {"kind": "udelad_end", "char_offset": 1},
    ]
    edited = subject.compose_marked_text(source, edited_annotations)
    exported = _node_call(tmp_path, "buildExport", edited, {
        "sourceText": source, "source": SOURCE,
        "expectedBoundaryOffsets": [0], "expectedProposalOffsets": [2],
    }, "2026-08-09T10:00:00.000Z")["value"]
    rebuilt_annotations = subject.apply_markeringer(base, exported)
    rebuilt = subject.compose_marked_text(source, rebuilt_annotations)
    assert rebuilt == edited

