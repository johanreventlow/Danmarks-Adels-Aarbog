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
            _boundary(6, signals=("laengdeafvigelse", "mangler_eget_hoved"),
                      gap_to=18),
            _boundary(len(text), inner=False),
        ],
    }

    result = subject.build_text_model(text, model)

    assert [item["char_offset"] for item in result["forudsatte_skaeringer"]] == [0, 6, len(text)]
    assert result["forudsatte_skaeringer"][1]["text"] == (
        "=== GRÆNSESKÆRING · SIGNAL mangler_eget_hoved ==="
    )
    assert result["huller"] == [{"char_offset": 6, "tegn": 12}]
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


def test_boundary_before_newline_uses_line_start_for_view_and_canonical_offset_for_export(tmp_path):
    source = "Post.\nNæste\n"
    annotations = [
        {"kind": "boundary", "char_offset": 5, "text": "=== GRÆNSESKÆRING ==="},
    ]

    marked = subject.compose_marked_text(source, annotations)

    assert marked == "Post.\n=== GRÆNSESKÆRING ===\nNæste\n"
    assert _node_call(tmp_path, "composeMarkedText", source, annotations) == marked
    parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
    assert parsed["markers"] == [
        {"kind": "boundary", "char_offset": 6, "text": "=== GRÆNSESKÆRING ==="},
    ]
    mappings = subject.line_marker_mappings(source, annotations)
    exported = _node_call(tmp_path, "buildExport", marked, {
        "sourceText": source,
        "source": SOURCE,
        "expectedBoundaryOffsets": [5],
        "expectedProposalOffsets": [],
        "lineMarkerMappings": mappings,
    }, "2026-08-09T10:00:00.000Z")
    assert exported["value"]["skaeringer"] == [
        {"char_offset": 5, "oprindelse": "forudsat"},
    ]


def test_line_marker_cannot_move_across_non_whitespace_source_text():
    source = "Post.\nNæste\n"
    annotations = [
        {"kind": "boundary", "char_offset": 2, "text": "=== GRÆNSESKÆRING ==="},
    ]

    with pytest.raises(subject.BoundaryError, match="ikke-whitespace"):
        subject.compose_marked_text(source, annotations)


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
        {"char_offset": 2, "oprindelse": "forslag_godkendt"},
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


def test_approved_proposal_at_an_expected_boundary_round_trips_without_losing_either_marker(tmp_path):
    source = "A\n1. B\n"
    base = [
        {"kind": "boundary", "char_offset": 2, "text": "=== GRÆNSESKÆRING ==="},
        {"kind": "proposal", "char_offset": 2, "text": "=== FORSLAG? SKÆRING ==="},
    ]
    edited = subject.compose_marked_text(source, [
        base[0], {"kind": "cut", "char_offset": 2, "text": "=== SKÆRING ==="},
    ])
    exported = _node_call(tmp_path, "buildExport", edited, {
        "sourceText": source, "source": SOURCE,
        "expectedBoundaryOffsets": [2], "expectedProposalOffsets": [2],
    }, "2026-08-09T10:00:00.000Z")["value"]
    assert exported["skaeringer"] == [
        {"char_offset": 2, "oprindelse": "forslag_godkendt"},
    ]
    assert subject.compose_marked_text(source, subject.apply_markeringer(base, exported)) == edited


def test_restore_book_text_keeps_markers_at_nearest_valid_source_line(tmp_path):
    source = "første\nanden\ntredje\n"
    changed = "førsteX\n=== SKÆRING ===\nanden\ntredje\n"
    restored = _node_call(tmp_path, "restoreBookText", changed, source)
    assert restored["ok"] is True
    assert restored["text"] == "første\n=== SKÆRING ===\nanden\ntredje\n"
    assert _node_call(tmp_path, "parseMarkedText", restored["text"], source)["gate"]["ok"] is True


def test_untouched_and_deleted_proposals_share_the_sum_but_round_trip_differently(tmp_path):
    source = "A\n1. B\n"
    data = {
        "sourceText": source, "source": SOURCE,
        "expectedBoundaryOffsets": [], "expectedProposalOffsets": [2],
    }
    untouched = _node_call(
        tmp_path, "buildExport", "A\n=== FORSLAG? SKÆRING ===\n1. B\n", data,
        "2026-08-09T10:00:00.000Z",
    )["value"]
    deleted = _node_call(
        tmp_path, "buildExport", source, data, "2026-08-09T10:00:00.000Z",
    )["value"]
    assert untouched["aendringsregnskab"]["forslag_bortfaldet"] == 1
    assert deleted["aendringsregnskab"]["forslag_bortfaldet"] == 1
    assert untouched["slettede"] == []
    assert deleted["slettede"] == [{"char_offset": 2, "var": "FORSLAG"}]


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
    queue.write_text(json.dumps({"schema_version": 1, "source": source, "entries": [{
        "baseline_record_key": "rk-a", "queue_class": "human_required",
        "reason_code": "manual", "reason_da": "menneskelig forankring",
    }]}), encoding="utf-8")
    anchored.write_text(json.dumps({"human:a": {
        "baseline_record_key": "rk-a", "candidate": {
            "candidate_id": "human:a", "postklasse": "nummereret",
            "calamari_span": {"char_from": 18, "char_to": 27},
            "pdf_pages": [496],
            "approval": {"kind": "human_approved_span_v1",
                         "calamari_excerpt_sha256": "e" * 64},
        },
    }}), encoding="utf-8")
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

    mutated = script.replace(";\n(function (global)", ";\\n(function (global)", 1)
    assert mutated != script
    mutated_path = tmp_path / "mutated-generated.js"
    mutated_path.write_text(mutated, encoding="utf-8")
    mutation = subprocess.run(
        ["node", "--check", str(mutated_path)], text=True, capture_output=True,
    )
    assert mutation.returncode != 0

    monkeypatch.setattr(sys, "argv", _argv(inputs, out))
    with pytest.raises(FileExistsError):
        subject.main()


def test_main_validates_source_hash_before_creating_output(tmp_path, monkeypatch):
    inputs = _write_inputs(tmp_path)
    inputs[3].write_text("ændret\n", encoding="utf-8")
    out = tmp_path / "flade.html"
    monkeypatch.setattr(sys, "argv", _argv(inputs, out))
    with pytest.raises(ValueError, match="calamari hash"):
        subject.main()
    assert not out.exists()


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


def test_init_prefers_local_storage_then_debounces_gate_and_autosave_by_300_ms(tmp_path):
    if shutil.which("node") is None:
        pytest.skip("node findes ikke på PATH")
    runner = tmp_path / "ui-runner.js"
    runner.write_text(
        "const fs=require('fs'),vm=require('vm');\n"
        "const listeners={},nodes={};\n"
        "function node(name){return nodes[name]={value:'',textContent:'',disabled:false,dataset:{},"
        "addEventListener:(event,fn)=>{listeners[name+':'+event]=fn}}}\n"
        "node('text');node('gate');node('save');node('export');node('restore');\n"
        "const selectors={'[data-role=\\\"boundary-text\\\"]':nodes.text,'[data-role=\\\"gate-status\\\"]':nodes.gate,"
        "'[data-role=\\\"save-status\\\"]':nodes.save,'[data-action=\\\"export\\\"]':nodes.export,"
        "'[data-action=\\\"restore\\\"]':nodes.restore};\n"
        "let delay=null,callback=null,writes=0;const context={console,TextEncoder,TextDecoder,"
        "document:{querySelector:s=>selectors[s]},localStorage:{},clearTimeout:()=>{},"
        "setTimeout:(fn,ms)=>{callback=fn;delay=ms},DAAReviewShared:{"
        "readStoredDraft:()=>({marked_text:'gemt\\n'}),writeStoredDraft:()=>{writes++;return ''},downloadJson:()=>{}}};\n"
        "context.globalThis=context;vm.createContext(context);vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),context);\n"
        "context.DAABoundaryText.init({source:{calamari_sha256:'x'},sourceText:'gemt\\n',initialText:'indlejret\\n',"
        "expectedBoundaryOffsets:[],expectedProposalOffsets:[]});\n"
        "nodes.text.value='ændret\\n';listeners['text:input']();\n"
        "const before={value:nodes.text.value,delay,writes};callback();\n"
        "process.stdout.write(JSON.stringify({before,gate:nodes.gate.textContent,writes}));\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        ["node", str(runner), str(subject.UI_PATH)], text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    value = json.loads(result.stdout)
    assert value["before"] == {"value": "ændret\n", "delay": 300, "writes": 1}
    assert value["gate"] == "bogteksten er ændret ved linje 1"
    assert value["writes"] == 2
