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


@pytest.mark.parametrize(
    ("source_page", "pdf_page"),
    [(59, 571), (60, 572), (61, 573), (62, 574)],
)
def test_pdf_page_skips_inserted_portraits_before_source_page_59(
    source_page, pdf_page,
):
    assert subject._pdf_page(source_page) == pdf_page


@pytest.mark.parametrize(
    ("source_page", "pdf_page"),
    [(84, 596), (85, 597), (86, 598)],
)
def test_pdf_page_keeps_final_text_pages_consecutive(source_page, pdf_page):
    assert subject._pdf_page(source_page) == pdf_page


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
    assert result["huller"] == [{"char_offset": 6, "char_to": 18, "tegn": 12}]
    assert result["forslag"] == [{"char_offset": 7}]


def test_build_text_model_does_not_banner_a_whitespace_only_gap():
    text = "A\nB\n"
    model = {
        "source": SOURCE,
        "boundaries": [_boundary(1, gap_to=2)],
    }

    result = subject.build_text_model(text, model)

    assert result["huller"] == []


def test_build_text_model_banners_real_text_at_both_document_edges():
    text = "kant\nPOST\nslut"
    span = {"char_from": 5, "char_to": 9, "baseline_record_key": "post"}
    model = {
        "source": SOURCE,
        "boundaries": [
            {
                "before": None,
                "after": span,
                "gap": {"char_from": 0, "char_to": 5},
                "signals": [],
            },
            {
                "before": span,
                "after": None,
                "gap": {"char_from": 9, "char_to": len(text)},
                "signals": [],
            },
        ],
    }

    result = subject.build_text_model(text, model)

    assert result["huller"] == [
        {"char_offset": 0, "char_to": 5, "tegn": 5},
        {"char_offset": 9, "char_to": 14, "tegn": 5},
    ]


def test_hole_annotations_frame_the_exact_source_span_and_strip_without_offset_drift(
    tmp_path,
):
    source = "F\nEjerløst\nN\n"
    text_model = {
        "forudsatte_skaeringer": [],
        "huller": [{"char_offset": 2, "char_to": 11, "tegn": 9}],
        "forslag": [],
        "pdf_sider": [],
    }

    annotations = subject._base_annotations(text_model)
    marked = subject.compose_marked_text(source, annotations)

    assert marked == (
        "F\n"
        "=== EJERLØS TEKST · 9 tegn ===\n"
        "Ejerløst\n"
        "=== SLUT EJERLØS TEKST ===\n"
        "N\n"
    )
    parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
    assert parsed["ok"] is True
    assert parsed["bookText"] == source
    assert parsed["gate"]["ok"] is True
    assert parsed["markers"] == [
        {"kind": "hole", "char_offset": 2,
         "text": "=== EJERLØS TEKST · 9 tegn ==="},
        {"kind": "holeEnd", "char_offset": 11,
         "text": "=== SLUT EJERLØS TEKST ==="},
    ]


def test_edge_banners_do_not_expand_the_existing_inner_gap_proposal_set():
    text = "1. kant\nPOST\n2. slut"
    span = {"char_from": 8, "char_to": 12, "baseline_record_key": "post"}
    model = {
        "source": SOURCE,
        "boundaries": [
            {
                "before": None, "after": span,
                "gap": {"char_from": 0, "char_to": 8}, "signals": [],
            },
            {
                "before": span, "after": None,
                "gap": {"char_from": 12, "char_to": len(text)}, "signals": [],
            },
        ],
    }

    result = subject.build_text_model(text, model)

    assert len(result["huller"]) == 2
    assert result["forslag"] == []


def test_page_markers_follow_source_page_lines_and_use_the_pdf_map():
    text = "### PAGE 0001 ###\nBog\n### PAGE 0005 ###\nMere\n"
    result = subject.build_text_model(text, {"source": SOURCE, "boundaries": []})
    assert result["pdf_sider"] == [
        {"char_offset": 18, "pdf_side": 496},
        {"char_offset": 40, "pdf_side": 500},
    ]


def test_build_page_view_models_assigns_boundary_marker_to_new_page_once():
    page_1 = "### PAGE 0001 ###\nFørste side.\n"
    page_2 = "### PAGE 0005 ###\nAnden side.\n"
    page_3 = "### PAGE 0010 ###\nTredje side.\n"
    source = page_1 + page_2 + page_3
    second_start = len(page_1)
    third_start = second_start + len(page_2)
    annotations = [
        {
            "kind": "boundary",
            "char_offset": second_start,
            "text": "=== GRÆNSESKÆRING · SIGNAL mangler_eget_hoved ===",
        },
        {
            "kind": "hole",
            "char_offset": page_1.index("Første"),
            "text": "=== EJERLØS TEKST · 12 tegn ===",
        },
        {
            "kind": "proposal",
            "char_offset": third_start,
            "text": "=== FORSLAG? SKÆRING ===",
        },
    ]

    pages = subject.build_page_view_models(source, annotations)

    assert [page["sourcePage"] for page in pages] == [1, 5, 10]
    assert [page["pdfPage"] for page in pages] == [496, 500, 505]
    assert [page["charFrom"] for page in pages] == [0, second_start, third_start]
    assert [page["charTo"] for page in pages] == [second_start, third_start, len(source)]
    assert "GRÆNSESKÆRING · SIGNAL" not in pages[0]["initialText"]
    assert pages[1]["initialText"].count("GRÆNSESKÆRING · SIGNAL") == 1
    assert "GRÆNSESKÆRING · SIGNAL" not in pages[2]["initialText"]
    assert sum(page["initialText"].count("GRÆNSESKÆRING · SIGNAL") for page in pages) == 1
    assert [page["counts"] for page in pages] == [
        {"ejerloes": 1, "forslag": 0, "signaler": 0},
        {"ejerloes": 0, "forslag": 0, "signaler": 1},
        {"ejerloes": 0, "forslag": 1, "signaler": 0},
    ]
    assert "".join(page["initialText"] for page in pages) == subject.compose_marked_text(
        source, annotations
    )


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
        "sourceLine": 2,
        "message": "bogteksten er ændret ved linje 2 (kildens linje 2)",
    }


def test_gate_reports_textarea_line_when_marker_lines_shift_source_numbering(tmp_path):
    source = "første\nanden\n"
    marked = (
        "=== GRÆNSESKÆRING ===\n"
        "første\n"
        "=== PDF-SIDE 496 ===\n"
        "andenX\n"
    )

    parsed = _node_call(tmp_path, "parseMarkedText", marked, source)

    assert parsed["gate"] == {
        "ok": False,
        "line": 4,
        "sourceLine": 2,
        "message": "bogteksten er ændret ved linje 4 (kildens linje 2)",
    }

    broken_marker = marked.replace("=== PDF-SIDE 496 ===", "=== UKENDT ===")
    grammar_error = _node_call(tmp_path, "parseMarkedText", broken_marker, source)
    assert grammar_error == {
        "ok": False,
        "line": 3,
        "error": "ukendt ===-markør ved linje 3",
    }


def test_byte_gate_does_not_strip_a_deleted_source_page_line(tmp_path):
    source = "før\n### PAGE 0001 ###\nefter\n"
    marked = "før\nefter\n"
    parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
    assert parsed["ok"] is True
    assert parsed["gate"]["ok"] is False
    assert parsed["gate"]["line"] == 2


def test_page_gate_checks_hidden_pages_and_reports_pdf_page_and_local_line(tmp_path):
    page_1 = "### PAGE 0001 ###\nFørste\n"
    page_2 = "### PAGE 0002 ###\nAnden\n"
    source = page_1 + page_2
    pages = subject.build_page_view_models(source, [])
    page_texts = [page["initialText"] for page in pages]
    page_texts[1] = page_texts[1].replace("Anden", "AndenX")

    result = _node_call(tmp_path, "validatePageTexts", page_texts, {
        "sourceText": source,
        "pages": pages,
    })

    assert result == {
        "ok": False,
        "pageIndex": 1,
        "pdfPage": 497,
        "pageLine": 2,
        "message": "bogteksten er ændret på side 497 ved linje 2",
    }


def test_page_export_keeps_boundary_at_page_start_once_and_exports_progress(tmp_path):
    page_1 = "### PAGE 0001 ###\nFørste\n"
    page_2 = "### PAGE 0002 ###\nAnden\n"
    source = page_1 + page_2
    boundary_offset = len(page_1)
    annotations = [{
        "kind": "boundary",
        "char_offset": boundary_offset,
        "text": "=== GRÆNSESKÆRING ===",
    }]
    pages = subject.build_page_view_models(source, annotations)
    page_texts = [page["initialText"] for page in pages]

    exported = _node_call(tmp_path, "buildExportFromPages", page_texts, {
        "sourceText": source,
        "source": SOURCE,
        "pages": pages,
        "expectedBoundaryOffsets": [boundary_offset],
        "expectedProposalOffsets": [],
        "lineMarkerMappings": subject.line_marker_mappings(source, annotations),
    }, "2026-08-09T10:00:00.000Z", [1, 2])

    assert exported["ok"] is True
    assert exported["value"]["skaeringer"] == [
        {"char_offset": boundary_offset, "oprindelse": "forudsat"},
    ]
    assert exported["value"]["aendringsregnskab"]["beholdt"] == 1
    assert exported["value"]["sider"] == {
        "i_alt": 2,
        "identitet": "kildeside",
        "gennemgaaet": [1, 2],
    }


def test_progress_counter_and_page_list_include_status_and_waiting_signals(tmp_path):
    data = {
        "pages": [
            {"ordinal": 1, "sourcePage": 1, "pdfPage": 496,
             "counts": {"ejerloes": 2, "forslag": 1, "signaler": 0}},
            {"ordinal": 2, "sourcePage": 2, "pdfPage": 497,
             "counts": {"ejerloes": 0, "forslag": 0, "signaler": 3}},
        ],
    }

    progress = _node_call(tmp_path, "pageProgress", data, [1], 1)

    assert progress["counter"] == "side 2 af 2 · 1 mangler"
    assert progress["items"] == [
        "PDF-side 496 · gennemgået · 2 ejerløs · 1 forslag · 0 signal",
        "PDF-side 497 · mangler · 0 ejerløs · 0 forslag · 3 signal",
    ]


def test_page_acknowledgement_requires_green_gate_advances_and_can_be_undone(tmp_path):
    data = {"pages": [
        {"sourcePage": 1, "pdfPage": 496},
        {"sourcePage": 2, "pdfPage": 497},
        {"sourcePage": 3, "pdfPage": 498},
    ]}

    blocked = _node_call(tmp_path, "togglePageCompletion", data, [], 0, False)
    assert blocked == {"reviewedPages": [], "currentIndex": 0, "changed": False}

    completed = _node_call(tmp_path, "togglePageCompletion", data, [], 0, True)
    assert completed == {"reviewedPages": [1], "currentIndex": 1, "changed": True}

    undone = _node_call(tmp_path, "togglePageCompletion", data, [1], 0, False)
    assert undone == {"reviewedPages": [], "currentIndex": 0, "changed": True}


def test_duplicate_pdf_labels_have_independent_source_page_progress(tmp_path):
    data = {"pages": [
        {"sourcePage": 85, "pdfPage": 598,
         "counts": {"ejerloes": 0, "forslag": 0, "signaler": 0}},
        {"sourcePage": 86, "pdfPage": 598,
         "counts": {"ejerloes": 0, "forslag": 0, "signaler": 0}},
    ]}

    first = _node_call(tmp_path, "togglePageCompletion", data, [], 0, True)
    assert first == {"reviewedPages": [85], "currentIndex": 1, "changed": True}
    after_first = _node_call(tmp_path, "pageProgress", data, first["reviewedPages"], 1)
    assert after_first == {
        "counter": "side 2 af 2 · 1 mangler",
        "items": [
            "PDF-side 598 (1/2) · gennemgået · 0 ejerløs · 0 forslag · 0 signal",
            "PDF-side 598 (2/2) · mangler · 0 ejerløs · 0 forslag · 0 signal",
        ],
    }

    second = _node_call(
        tmp_path, "togglePageCompletion", data, first["reviewedPages"], 1, True,
    )
    assert second == {"reviewedPages": [85, 86], "currentIndex": 1, "changed": True}
    assert _node_call(
        tmp_path, "pageProgress", data, second["reviewedPages"], 1,
    )["counter"] == "side 2 af 2 · 0 mangler"


def test_legacy_pdf_progress_migrates_unique_values_and_drops_ambiguous_value():
    pages = [
        {"sourcePage": 1, "pdfPage": 496},
        {"sourcePage": 85, "pdfPage": 598},
        {"sourcePage": 86, "pdfPage": 598},
    ]
    exported = {"sider": {"i_alt": 3, "gennemgaaet": [496, 598]}}

    completed, migration = subject._completed_pages(exported, pages)

    assert completed == [1]
    assert migration == {
        "translated": 1,
        "dropped": 1,
        "message": (
            "Sidefremskridt fra gammel eksport: 1 oversat · "
            "1 bortfalden (tvetydigt PDF-sidetal)"
        ),
    }


def test_legacy_browser_progress_uses_the_same_fail_closed_migration(tmp_path):
    data = {"pages": [
        {"sourcePage": 1, "pdfPage": 496},
        {"sourcePage": 85, "pdfPage": 598},
        {"sourcePage": 86, "pdfPage": 598},
    ]}

    migration = _node_call(tmp_path, "migrateLegacyPdfPages", data, [496, 598])

    assert migration == {
        "reviewedPages": [1],
        "translated": 1,
        "dropped": 1,
        "message": (
            "Sidefremskridt fra gammel eksport: 1 oversat · "
            "1 bortfalden (tvetydigt PDF-sidetal)"
        ),
    }


def test_new_source_page_progress_round_trips_without_migration_loss(tmp_path):
    source = "### PAGE 0085 ###\nNæstsidste\n### PAGE 0086 ###\nSidste\n"
    pages = subject.build_page_view_models(source, [])
    page_texts = [page["initialText"] for page in pages]
    data = {
        "sourceText": source,
        "source": SOURCE,
        "pages": pages,
        "expectedBoundaryOffsets": [],
        "expectedProposalOffsets": [],
        "lineMarkerMappings": [],
    }

    exported = _node_call(
        tmp_path, "buildExportFromPages", page_texts, data,
        "2026-08-10T10:00:00.000Z", [85, 86],
    )["value"]

    assert exported["sider"] == {
        "i_alt": 2,
        "identitet": "kildeside",
        "gennemgaaet": [85, 86],
    }
    completed, migration = subject._completed_pages(exported, pages)
    assert completed == [85, 86]
    assert migration is None


def test_unknown_marker_on_hidden_page_reports_that_page_and_its_local_line(tmp_path):
    page_1 = "### PAGE 0001 ###\nFørste\n"
    page_2 = "### PAGE 0002 ###\nAnden\n"
    source = page_1 + page_2
    annotations = [{
        "kind": "boundary", "char_offset": 0, "text": "=== GRÆNSESKÆRING ===",
    }]
    pages = subject.build_page_view_models(source, annotations)
    page_texts = [page["initialText"] for page in pages]
    page_texts[1] = page_texts[1].replace(
        "### PAGE 0002 ###\n", "### PAGE 0002 ###\n=== UKENDT ===\n",
    )

    result = _node_call(tmp_path, "validatePageTexts", page_texts, {
        "sourceText": source,
        "pages": pages,
    })

    assert result == {
        "ok": False,
        "pageIndex": 1,
        "pdfPage": 497,
        "pageLine": 2,
        "message": "ukendt ===-markør på side 497 ved linje 2",
    }


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


def test_all_four_udelad_forms_export_identical_source_coordinates_and_rebuild(tmp_path):
    source = "Før\nFemte slægtled.\nEfter\n"
    prefix = "Før\n"
    omitted = "Femte slægtled."
    forms = [
        "Før\n[[UDELAD]]Femte slægtled.[[/UDELAD]]\nEfter\n",
        "Før\n[[UDELAD]]\nFemte slægtled.\n[[/UDELAD]]\nEfter\n",
        "Før\n[[UDELAD]]\nFemte slægtled.[[/UDELAD]]\nEfter\n",
        "Før\n[[UDELAD]]Femte slægtled.\n[[/UDELAD]]\nEfter\n",
    ]
    expected = {"char_from": len(prefix), "char_to": len(prefix) + len(omitted)}
    exports = []

    for marked in forms:
        parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
        assert parsed["ok"] is True
        assert parsed["gate"]["ok"] is True
        exported = _node_call(tmp_path, "buildExport", marked, {
            "sourceText": source,
            "source": SOURCE,
            "expectedBoundaryOffsets": [],
            "expectedProposalOffsets": [],
            "lineMarkerMappings": [],
        }, "2026-08-09T10:00:00.000Z")["value"]
        assert exported["udeladelser"] == [expected]
        exports.append(exported["udeladelser"])

        rebuilt = subject.compose_marked_text(
            source, subject.apply_markeringer([], exported),
        )
        reparsed = _node_call(tmp_path, "parseMarkedText", rebuilt, source)
        assert reparsed["gate"]["ok"] is True
        assert reparsed["omissions"] == [expected]

    assert exports == [[expected]] * 4


@pytest.mark.parametrize(("marked", "expected_count"), [
    ("Før\nX[[UDELAD]]Overskrift[[/UDELAD]]\nEfter\n", 1),
    ("Før\n[[UDELAD]]XOverskrift[[/UDELAD]]\nEfter\n", 0),
    ("Før\nXO[[UDELAD]]verskrift[[/UDELAD]]\nEfter\n", 0),
    ("Før\n [[UDELAD]]Overskrift[[/UDELAD]]\nEfter\n", 0),
])
def test_omission_warning_only_fires_for_one_nonblank_character_after_line_start(
    tmp_path, marked, expected_count,
):
    source = "Før\nXOverskrift\nEfter\n" if "XO" in marked else (
        "Før\n Overskrift\nEfter\n" if "\n [[" in marked
        else "Før\nXOverskrift\nEfter\n"
    )
    pages = [{
        "ordinal": 1, "sourcePage": 1, "pdfPage": 496,
        "charFrom": 0, "charTo": len(source),
    }]

    warnings = _node_call(tmp_path, "omissionWarnings", marked, {
        "sourceText": source,
        "pages": pages,
    })

    assert len(warnings) == expected_count
    if expected_count:
        assert warnings == [{
            "charOffset": 5,
            "sourcePage": 1,
            "pdfPage": 496,
            "pageLine": 2,
        }]


def test_tag_like_solo_lines_fail_as_tags_while_real_book_changes_still_hit_gate(tmp_path):
    source = "Før\nFemte slægtled.\nEfter\n"
    for marked, error in (
        ("[[OCR: Rcventlow | burde stå Reventlow]]\n" + source,
         "ukendt inline-tag ved linje 1"),
        (" [[UDELAD]]\n" + source, "ukendt inline-tag ved linje 1"),
        ("[[UDELAD]]\n" + source, "uparret UDELAD-tag ved linje 1"),
        ("[[/UDELAD]]\n" + source, "uparret /UDELAD-tag ved linje 1"),
    ):
        parsed = _node_call(tmp_path, "parseMarkedText", marked, source)
        assert parsed == {"ok": False, "line": 1, "error": error}

    changed = "Før\n[[UDELAD]]\nFemte Xslægtled.\n[[/UDELAD]]\nEfter\n"
    parsed = _node_call(tmp_path, "parseMarkedText", changed, source)
    assert parsed["ok"] is True
    assert parsed["gate"]["ok"] is False
    assert parsed["gate"]["message"].startswith("bogteksten er ændret ved linje ")


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


def test_colocated_user_cut_and_in_place_approved_proposal_keep_distinct_canonical_offsets(
    tmp_path,
):
    source = "A \nB\n"
    # Offset 1 ligger før whitespace og vises derfor ved linjestarten på offset 3.
    # Forslaget ligger kanonisk på offset 3. Efter in-place-godkendelsen er de to
    # viste linjer ens, men de skal stadig konsumere hver sin mapping.
    mappings = subject.line_marker_mappings(source, [
        {"kind": "proposal", "char_offset": 3,
         "text": "=== FORSLAG? SKÆRING ==="},
        {"kind": "cut", "char_offset": 1, "text": "=== SKÆRING ===",
         "origin": "bruger"},
    ])
    marked = "A \n=== SKÆRING ===\n=== SKÆRING ===\nB\n"

    exported = _node_call(tmp_path, "buildExport", marked, {
        "sourceText": source,
        "source": SOURCE,
        "expectedBoundaryOffsets": [],
        "expectedProposalOffsets": [3],
        "lineMarkerMappings": mappings,
    }, "2026-08-10T10:00:00.000Z")

    assert exported["ok"] is True
    assert exported["value"]["skaeringer"] == [
        {"char_offset": 1, "oprindelse": "bruger"},
        {"char_offset": 3, "oprindelse": "forslag_godkendt"},
    ]
    assert exported["value"]["aendringsregnskab"]["forslag_godkendt"] == 1
    assert exported["value"]["aendringsregnskab"]["forslag_bortfaldet"] == 0


def test_expected_proposal_offset_overrides_stale_user_origin_hint(tmp_path):
    source = "A\n"
    marked = "=== SKÆRING ===\nA\n"
    mappings = subject.line_marker_mappings(source, [{
        "kind": "cut", "char_offset": 0, "text": "=== SKÆRING ===",
        "origin": "bruger",
    }])

    exported = _node_call(tmp_path, "buildExport", marked, {
        "sourceText": source,
        "source": SOURCE,
        "expectedBoundaryOffsets": [],
        "expectedProposalOffsets": [0],
        "lineMarkerMappings": mappings,
    }, "2026-08-10T10:00:00.000Z")["value"]

    assert exported["skaeringer"] == [
        {"char_offset": 0, "oprindelse": "forslag_godkendt"},
    ]
    assert exported["aendringsregnskab"]["forslag_godkendt"] == 1


def test_reload_replaces_proposal_with_cut_even_when_old_export_called_it_user():
    source = "A\n1. B\n"
    base = [{
        "kind": "proposal", "char_offset": 2,
        "text": "=== FORSLAG? SKÆRING ===",
    }]
    old_export = {
        "skaeringer": [{"char_offset": 2, "oprindelse": "bruger"}],
        "slettede": [],
        "ocr_noter": [],
        "udeladelser": [],
    }

    rebuilt = subject.apply_markeringer(base, old_export)

    assert rebuilt == [{
        "kind": "cut", "char_offset": 2, "text": "=== SKÆRING ===",
        "origin": "forslag_godkendt",
    }]
    assert subject.compose_marked_text(source, rebuilt) == "A\n=== SKÆRING ===\n1. B\n"


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


def _write_inputs(tmp_path: Path, page_count=1):
    source_text = "### PAGE 0001 ###\n1. Anders\n" + "".join(
        f"### PAGE {page:04d} ###\nSide {page}\n"
        for page in range(2, page_count + 1)
    )
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


def test_main_writes_parseable_html_and_refuses_overwrite(tmp_path, monkeypatch, capsys):
    inputs = _write_inputs(tmp_path)
    out = tmp_path / "flade.html"
    monkeypatch.setattr(sys, "argv", _argv(inputs, out))
    assert subject.main() == 0
    assert capsys.readouterr().out == "2 grænser · 1 huller · 0 forslag · 1 PDF-sider\n"
    rendered = out.read_text(encoding="utf-8")
    assert "<textarea" in rendered
    assert "DAABoundaryText.init" in rendered
    assert 'data-role="page-progress"' in rendered
    assert 'data-role="page-list"' in rendered
    assert 'data-action="complete-page"' in rendered
    assert 'data-role="omission-warning"' in rendered

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


def test_generated_help_key_is_outside_textarea_and_cannot_change_text_payload(
    tmp_path, monkeypatch
):
    inputs = _write_inputs(tmp_path)
    out = tmp_path / "flade-med-noegle.html"
    monkeypatch.setattr(sys, "argv", _argv(inputs, out))
    assert subject.main() == 0
    rendered = out.read_text(encoding="utf-8")

    key_start = rendered.index('<details data-role="editing-key">')
    key_end = rendered.index("</details>", key_start) + len("</details>")
    textarea_start = rendered.index('<textarea data-role="boundary-text"')
    textarea_content_start = rendered.index(">", textarea_start) + 1
    textarea_end = rendered.index("</textarea>", textarea_content_start)
    assert key_start < key_end < textarea_start
    assert rendered[textarea_content_start:textarea_end] == ""

    key = rendered[key_start:key_end]
    assert "Nøgle til redigering" in key
    assert key.count("<li>") == 6
    assert "[[OCR: Rcventlow | burde stå Reventlow]]" in key
    assert "der står Rcventlow" not in key

    without_key = rendered[:key_start] + rendered[key_end:]
    payload = lambda html: html.split("const DATA=", 1)[1].split(
        ";\n(function (global)", 1
    )[0]
    assert payload(rendered) == payload(without_key)
    without_textarea_start = without_key.index('<textarea data-role="boundary-text"')
    without_content_start = without_key.index(">", without_textarea_start) + 1
    without_textarea_end = without_key.index("</textarea>", without_content_start)
    assert without_key[without_content_start:without_textarea_end] == ""


def test_main_validates_source_hash_before_creating_output(tmp_path, monkeypatch):
    inputs = _write_inputs(tmp_path)
    inputs[3].write_text("ændret\n", encoding="utf-8")
    out = tmp_path / "flade.html"
    monkeypatch.setattr(sys, "argv", _argv(inputs, out))
    with pytest.raises(ValueError, match="calamari hash"):
        subject.main()
    assert not out.exists()


def test_main_markeringer_rebuilds_an_udelad_export_as_a_valid_surface(
    tmp_path, monkeypatch
):
    inputs = _write_inputs(tmp_path)
    source = json.loads(inputs[2].read_text(encoding="utf-8"))["source"]
    markeringer = tmp_path / "1939-graenseflade.json"
    markeringer.write_text(json.dumps({
        "schema_version": 1,
        "source": source,
        "exported_at": "2026-08-09T10:00:00.000Z",
        "skaeringer": [],
        "aendringsregnskab": {
            "forudsat": 2, "beholdt": 0, "slettet": 2, "tilfoejet": 0,
            "forslag_forudsat": 0, "forslag_godkendt": 0,
            "forslag_bortfaldet": 0,
        },
        "slettede": [
            {"char_offset": 18, "var": "GRÆNSESKÆRING"},
            {"char_offset": 27, "var": "GRÆNSESKÆRING"},
        ],
        "ocr_noter": [],
        "udeladelser": [{"char_from": 18, "char_to": 27}],
    }), encoding="utf-8")
    out = tmp_path / "genindlaest.html"
    monkeypatch.setattr(sys, "argv", _argv(inputs, out, markeringer))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    data = json.loads(rendered.split("const DATA=", 1)[1].split(
        ";\n(function (global)", 1
    )[0])
    assert data["completedPages"] == []
    parsed = _node_call(tmp_path, "parseMarkedText", data["initialText"], data["sourceText"])
    assert parsed["gate"]["ok"] is True
    assert parsed["omissions"] == [{"char_from": 18, "char_to": 27}]


def test_main_markeringer_round_trips_two_reviewed_pages_and_84_missing(
    tmp_path, monkeypatch
):
    inputs = _write_inputs(tmp_path, page_count=86)
    source = json.loads(inputs[2].read_text(encoding="utf-8"))["source"]
    markeringer = tmp_path / "to-gennemgaaede.json"
    markeringer.write_text(json.dumps({
        "schema_version": 1,
        "source": source,
        "exported_at": "2026-08-09T10:00:00.000Z",
        "skaeringer": [
            {"char_offset": 18, "oprindelse": "forudsat"},
            {"char_offset": 27, "oprindelse": "forudsat"},
        ],
        "aendringsregnskab": {
            "forudsat": 2, "beholdt": 2, "slettet": 0, "tilfoejet": 0,
            "forslag_forudsat": 0, "forslag_godkendt": 0,
            "forslag_bortfaldet": 0,
        },
        "slettede": [],
        "ocr_noter": [],
        "udeladelser": [],
        "sider": {"i_alt": 86, "gennemgaaet": [496, 497]},
    }), encoding="utf-8")
    out = tmp_path / "86-sider.html"
    monkeypatch.setattr(sys, "argv", _argv(inputs, out, markeringer))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    data = json.loads(rendered.split("const DATA=", 1)[1].split(
        ";\n(function (global)", 1
    )[0])
    assert len(data["pages"]) == 86
    assert data["completedPages"] == [1, 2]
    progress = _node_call(tmp_path, "pageProgress", data, data["completedPages"], 0)
    assert progress["counter"] == "side 1 af 86 · 84 mangler"


def test_export_reload_round_trip_reconstructs_the_same_marked_surface(tmp_path):
    source = "A\n1. B\nC\n"
    base = [
        {"kind": "boundary", "char_offset": 0, "text": "=== GRÆNSESKÆRING ==="},
        {"kind": "proposal", "char_offset": 2, "text": "=== FORSLAG? SKÆRING ==="},
    ]
    edited_annotations = [
        {"kind": "cut", "char_offset": 2, "text": "=== SKÆRING ==="},
        {"kind": "cut", "char_offset": 7, "text": "=== SKÆRING ==="},
        {"kind": "ocr", "char_offset": 8, "staar": "C", "burde_staa": "D"},
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
        "function node(name){return nodes[name]={value:'',textContent:'',innerHTML:'',disabled:false,dataset:{},"
        "addEventListener:(event,fn)=>{listeners[name+':'+event]=fn}}}\n"
        "node('text');node('gate');node('save');node('export');node('restore');"
        "node('complete');node('progress');node('list');node('importStatus');node('warning');\n"
        "const selectors={'[data-role=\\\"boundary-text\\\"]':nodes.text,'[data-role=\\\"gate-status\\\"]':nodes.gate,"
        "'[data-role=\\\"save-status\\\"]':nodes.save,'[data-action=\\\"export\\\"]':nodes.export,"
        "'[data-action=\\\"restore\\\"]':nodes.restore,'[data-action=\\\"complete-page\\\"]':nodes.complete,"
        "'[data-role=\\\"page-progress\\\"]':nodes.progress,'[data-role=\\\"page-list\\\"]':nodes.list,"
        "'[data-role=\\\"progress-import-status\\\"]':nodes.importStatus,"
        "'[data-role=\\\"omission-warning\\\"]':nodes.warning};\n"
        "let delay=null,callback=null,writes=0;const context={console,TextEncoder,TextDecoder,"
        "document:{querySelector:s=>selectors[s]},localStorage:{},clearTimeout:()=>{},"
        "setTimeout:(fn,ms)=>{callback=fn;delay=ms},DAAReviewShared:{"
        "readStoredDraft:()=>({page_texts:['gemt\\n'],reviewed_pages:[],current_page:0}),"
        "writeStoredDraft:()=>{writes++;return ''},downloadJson:()=>{}}};\n"
        "context.globalThis=context;vm.createContext(context);vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),context);\n"
        "context.DAABoundaryText.init({source:{calamari_sha256:'x'},sourceText:'gemt\\n',initialText:'indlejret\\n',"
        "pages:[{ordinal:1,sourcePage:1,pdfPage:496,charFrom:0,charTo:5,initialText:'indlejret\\n',"
        "counts:{ejerloes:0,forslag:0,signaler:0}}],completedPages:[],"
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
    assert value["gate"] == "bogteksten er ændret på side 496 ved linje 1"
    assert value["writes"] == 2
