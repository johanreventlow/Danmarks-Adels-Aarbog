#!/usr/bin/env python3
"""Byg den browserlokale 1939-tekstflade til grænsekontrol."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections.abc import Mapping
from pathlib import Path

from boundary_spans_1939 import BoundaryError, collect_accepted_spans
from make_boundary_review_1939 import (
    _automatic_candidates,
    _clauses_for,
    _source_from_manifest,
    build_boundary_view_model,
)
from rendition_occurrences_1939 import CALAMARI_R6_TO_PDF_V1, _PRINTED_MARKER_RE


UI_PATH = Path(__file__).with_name("boundary_text_1939_ui.js")
SHARED_UI_PATH = Path(__file__).with_name("review_ui_shared.js")
_PAGE_RE = re.compile(r"^###\s*PAGE\s+(\d+)\s*###\s*$")
_SHIFT_SIGNALS = ("mangler_eget_hoved", "slugt_hoved")

HTML_PREFIX = """<!doctype html>
<meta charset="utf-8">
<title>1939-grænsekontrol · tekstflade</title>
<style>
*{box-sizing:border-box}body{font:16px system-ui;margin:0;color:#18212a;background:#f7f8fa}
main{height:100dvh;display:flex;flex-direction:column;gap:10px;padding:14px}
.toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.toolbar button{font:inherit;padding:8px 12px}
[data-role="gate-status"]{font-weight:700}[data-gate="ok"]{color:#166534}[data-gate="error"]{color:#b42318}
details{border:1px solid #cbd5df;border-radius:4px;background:#fff;padding:7px 10px}summary{cursor:pointer;font-weight:700}details ul{margin:8px 0 2px;padding-left:24px}details li{margin:3px 0}code{font:14px ui-monospace,SFMono-Regular,Menlo,monospace}
.workspace{display:grid;grid-template-columns:minmax(260px,330px) minmax(0,1fr);gap:10px;flex:1;min-height:0}
[data-role="page-list"]{overflow:auto;border:1px solid #cbd5df;border-radius:4px;background:#fff;padding:6px;display:flex;flex-direction:column;gap:4px}
[data-role="page-list"] button{font:13px/1.3 system-ui;text-align:left;border:1px solid transparent;border-radius:3px;background:#f3f5f7;padding:7px;cursor:pointer}
[data-role="page-list"] button[aria-current="page"]{border-color:#2563eb;background:#eff6ff}
textarea{min-height:0;width:100%;resize:none;border:1px solid #9aa8b5;border-radius:4px;padding:14px;font:15px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace;white-space:pre;tab-size:2}
@media(max-width:800px){.workspace{grid-template-columns:1fr;grid-template-rows:minmax(100px,25vh) minmax(0,1fr)}}
</style>
<main>
  <div class="toolbar">
    <span data-role="gate-status" data-gate="ok">bogteksten er urørt</span>
    <strong data-role="page-progress">side 1 af 86 · 86 mangler</strong>
    <button type="button" data-action="complete-page">Færdig med siden</button>
    <button type="button" data-action="restore">Gendan bogteksten, behold mine markører</button>
    <button type="button" data-action="export">Eksportér 1939-graenseflade.json</button>
    <span data-role="save-status">Klar. Ændringer gemmes automatisk lokalt.</span>
  </div>
  <details data-role="editing-key">
    <summary>Nøgle til redigering</summary>
    <ul>
      <li><code>=== GRÆNSESKÆRING ===</code> er godkendt, når du lader linjen stå.</li>
      <li>Forkast en skæring ved at slette hele markørlinjen.</li>
      <li>Tilføj en skæring med en ny linje: <code>=== SKÆRING ===</code>.</li>
      <li>Et <code>=== FORSLAG? SKÆRING ===</code> tæller først, når du fjerner <code>FORSLAG? </code>, så linjen bliver <code>=== SKÆRING ===</code>.</li>
      <li><code>=== EJERLØS TEKST · N tegn ===</code> betyder, at ingen post ejer teksten. Brug Cmd+F på EJERLØS.</li>
      <li>OCR-note: <code>[[OCR: Rcventlow | burde stå Reventlow]]</code>. Venstre side er rå tekst; skriv ikke “der står”.</li>
    </ul>
  </details>
  <div class="workspace">
    <nav data-role="page-list" aria-label="Bogsider"></nav>
    <textarea data-role="boundary-text" spellcheck="false" aria-label="1939-grænsetekst"></textarea>
  </div>
</main>
<script>
const DATA="""

HTML_SUFFIX = """;
window.DAABoundaryText.init(DATA);
</script>
"""


def _pdf_page(calamari_page: int) -> int:
    for source_page, pdf_page in CALAMARI_R6_TO_PDF_V1:
        if calamari_page == source_page:
            return pdf_page
    for (left_source, left_pdf), (right_source, right_pdf) in zip(
        CALAMARI_R6_TO_PDF_V1, CALAMARI_R6_TO_PDF_V1[1:]
    ):
        if left_source < calamari_page < right_source:
            numerator = (calamari_page - left_source) * (right_pdf - left_pdf)
            denominator = right_source - left_source
            return left_pdf + (2 * numerator + denominator) // (2 * denominator)
    raise BoundaryError(f"Calamari-side {calamari_page} findes ikke i PDF-sidekortet")


def _boundary_offset(boundary: Mapping) -> int:
    before, after = boundary.get("before"), boundary.get("after")
    if isinstance(before, Mapping):
        return before["char_to"]
    if isinstance(after, Mapping):
        return after["char_from"]
    gap = boundary.get("gap")
    if not isinstance(gap, Mapping):
        raise BoundaryError("grænse mangler hulkoordinater")
    return gap["char_from"]


def _line_offsets(text: str):
    offset = 0
    for line in text.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        yield offset, content, offset + len(line)
        offset += len(line)
    if not text:
        return
    if not text.endswith(("\n", "\r")) and offset < len(text):
        yield offset, text[offset:], len(text)


def build_text_model(calamari_text: str, boundary_model: Mapping) -> dict:
    """Omsæt fase 1's view-model til tekstfladens deterministiske markører."""
    boundaries = boundary_model.get("boundaries")
    if not isinstance(boundaries, list):
        raise BoundaryError("boundary view-model mangler boundaries")

    cuts = []
    holes = []
    proposals = []
    for boundary in sorted(boundaries, key=_boundary_offset):
        offset = _boundary_offset(boundary)
        signals = [name for name in _SHIFT_SIGNALS if name in boundary.get("signals", [])]
        marker = "=== GRÆNSESKÆRING ==="
        if signals:
            marker = f"=== GRÆNSESKÆRING · SIGNAL {', '.join(signals)} ==="
        cuts.append({"char_offset": offset, "text": marker})

        gap = boundary.get("gap")
        before, after = boundary.get("before"), boundary.get("after")
        if isinstance(gap, Mapping) and gap["char_to"] > gap["char_from"]:
            gap_from, gap_to = gap["char_from"], gap["char_to"]
            gap_text = calamari_text[gap_from:gap_to]
            if gap_text.strip():
                holes.append({"char_offset": gap_from, "tegn": gap_to - gap_from})
                if isinstance(before, Mapping) and isinstance(after, Mapping):
                    for line_offset, line, _ in _line_offsets(gap_text):
                        if _PRINTED_MARKER_RE.match(line):
                            proposals.append({"char_offset": gap_from + line_offset})

    pdf_pages = []
    for line_offset, line, next_offset in _line_offsets(calamari_text):
        match = _PAGE_RE.fullmatch(line)
        if match:
            pdf_pages.append({
                "char_offset": next_offset,
                "pdf_side": _pdf_page(int(match.group(1))),
            })

    return {
        "schema_version": 1,
        "source": dict(boundary_model.get("source", {})),
        "forudsatte_skaeringer": cuts,
        "huller": holes,
        "forslag": proposals,
        "pdf_sider": pdf_pages,
    }


def _base_annotations(text_model: Mapping) -> list[dict]:
    annotations = [
        {"kind": "boundary", **item}
        for item in text_model["forudsatte_skaeringer"]
    ]
    annotations.extend({
        "kind": "hole", "char_offset": item["char_offset"],
        "text": f"=== EJERLØS TEKST · {item['tegn']} tegn ===",
    } for item in text_model["huller"])
    annotations.extend({
        "kind": "proposal", "char_offset": item["char_offset"],
        "text": "=== FORSLAG? SKÆRING ===",
    } for item in text_model["forslag"])
    annotations.extend({
        "kind": "pdf", "char_offset": item["char_offset"],
        "text": f"=== PDF-SIDE {item['pdf_side']} ===",
    } for item in text_model["pdf_sider"])
    return annotations


def build_page_view_models(source_text: str, annotations: list[Mapping]) -> list[dict]:
    """Del kilden på dens egne PAGE-linjer og giv hver markør én side."""
    starts = []
    for line_offset, line, _ in _line_offsets(source_text):
        match = _PAGE_RE.fullmatch(line)
        if match:
            starts.append((line_offset, int(match.group(1))))
    if not starts:
        raise BoundaryError("kildeteksten indeholder ingen ### PAGE-linjer")
    if starts[0][0] != 0:
        raise BoundaryError("kildeteksten har tekst før første ### PAGE-linje")

    pages = []
    for index, (char_from, source_page) in enumerate(starts):
        char_to = starts[index + 1][0] if index + 1 < len(starts) else len(source_text)
        page_annotations = []
        counts = {"ejerloes": 0, "forslag": 0, "signaler": 0}
        for annotation in annotations:
            offset = annotation.get("char_offset")
            if not isinstance(offset, int) or isinstance(offset, bool):
                raise BoundaryError("markør har ugyldig kildetekstposition")
            belongs = char_from <= offset < char_to
            if index == len(starts) - 1 and offset == char_to:
                belongs = True
            if not belongs:
                continue
            local = dict(annotation)
            local["char_offset"] = offset - char_from
            page_annotations.append(local)
            if annotation.get("kind") == "hole":
                counts["ejerloes"] += 1
            elif annotation.get("kind") == "proposal":
                counts["forslag"] += 1
            elif (
                annotation.get("kind") == "boundary"
                and "· SIGNAL " in str(annotation.get("text", ""))
            ):
                counts["signaler"] += 1

        page_source = source_text[char_from:char_to]
        pages.append({
            "ordinal": index + 1,
            "sourcePage": source_page,
            "pdfPage": _pdf_page(source_page),
            "charFrom": char_from,
            "charTo": char_to,
            "initialText": compose_marked_text(page_source, page_annotations),
            "counts": counts,
        })
    return pages


_LINE_RANK = {"pdf": 10, "boundary": 20, "hole": 30, "proposal": 40, "cut": 50}
_INLINE_RANK = {"udelad_start": 0, "ocr": 1, "udelad_end": 2}


def _line_marker_display_offset(source_text: str, canonical_offset: int) -> int:
    """Find næste linjestart uden at flytte markøren hen over bogtekst."""
    if canonical_offset == 0 or source_text[canonical_offset - 1:canonical_offset] in {"\n", "\r"}:
        return canonical_offset
    for offset in range(canonical_offset, len(source_text)):
        character = source_text[offset]
        if not character.isspace():
            raise BoundaryError(
                f"linjemarkør ved {canonical_offset} har ikke-whitespace før næste linjestart"
            )
        if character == "\n":
            return offset + 1
        if character == "\r" and source_text[offset + 1:offset + 2] != "\n":
            return offset + 1
    raise BoundaryError(f"linjemarkør ved {canonical_offset} har ingen efterfølgende linjestart")


def line_marker_mappings(source_text: str, annotations: list[Mapping]) -> list[dict]:
    """Beskriv den tabsfri kanonisk↔visning-omregning for linjemarkører."""
    mappings = []
    for item in annotations:
        if item.get("kind") not in _LINE_RANK:
            continue
        canonical = item.get("char_offset")
        if isinstance(canonical, bool) or not isinstance(canonical, int) or not 0 <= canonical <= len(source_text):
            raise BoundaryError("markør har ugyldig kildetekstposition")
        mapping = {
            "kind": item["kind"],
            "text": item["text"],
            "canonicalOffset": canonical,
            "displayOffset": _line_marker_display_offset(source_text, canonical),
        }
        if item.get("origin") is not None:
            mapping["origin"] = item["origin"]
        mappings.append(mapping)
    return mappings


def compose_marked_text(source_text: str, annotations: list[Mapping]) -> str:
    """Indsæt markører ved kildens tegnkoordinater uden at ændre kildeteksten."""
    by_offset: dict[int, list[Mapping]] = {}
    for item in annotations:
        offset = item.get("char_offset")
        if isinstance(offset, bool) or not isinstance(offset, int) or not 0 <= offset <= len(source_text):
            raise BoundaryError("markør har ugyldig kildetekstposition")
        display_offset = (
            _line_marker_display_offset(source_text, offset)
            if item.get("kind") in _LINE_RANK else offset
        )
        by_offset.setdefault(display_offset, []).append(item)

    parts = []
    for offset in range(len(source_text) + 1):
        items = by_offset.get(offset, [])
        line_items = sorted(
            (item for item in items if item.get("kind") in _LINE_RANK),
            key=lambda item: (_LINE_RANK[item["kind"]], item.get("text", "")),
        )
        for item in line_items:
            parts.append(item["text"] + "\n")
        inline_items = sorted(
            (item for item in items if item.get("kind") in _INLINE_RANK),
            key=lambda item: _INLINE_RANK[item["kind"]],
        )
        for item in inline_items:
            kind = item["kind"]
            if kind == "ocr":
                parts.append(f"[[OCR: {item['staar']} | burde stå {item['burde_staa']}]]")
            elif kind == "udelad_start":
                parts.append("[[UDELAD]]")
            else:
                parts.append("[[/UDELAD]]")
        if offset < len(source_text):
            parts.append(source_text[offset])
    return "".join(parts)


def apply_markeringer(base: list[Mapping], exported: Mapping) -> list[dict]:
    """Genopbyg markørlisten fra §7-eksporten uden at eksportere bogteksten."""
    deleted = {
        (item.get("char_offset"), item.get("var"))
        for item in exported.get("slettede", []) if isinstance(item, Mapping)
    }
    cuts = {
        item.get("char_offset"): item.get("oprindelse")
        for item in exported.get("skaeringer", []) if isinstance(item, Mapping)
    }
    result = []
    for item in base:
        copy = dict(item)
        offset, kind = copy["char_offset"], copy["kind"]
        if kind == "boundary" and (offset, "GRÆNSESKÆRING") in deleted:
            continue
        if kind == "proposal":
            if cuts.get(offset) == "forslag_godkendt":
                result.append({"kind": "cut", "char_offset": offset,
                               "text": "=== SKÆRING ===",
                               "origin": "forslag_godkendt"})
                continue
            if (offset, "FORSLAG") in deleted:
                continue
        result.append(copy)

    occupied = {item["char_offset"] for item in result if item["kind"] in {"boundary", "cut"}}
    for offset, origin in sorted(cuts.items()):
        if offset not in occupied and origin in {"bruger", "forslag_godkendt"}:
            result.append({"kind": "cut", "char_offset": offset,
                           "text": "=== SKÆRING ===", "origin": origin})
    result.extend({"kind": "ocr", **dict(item)} for item in exported.get("ocr_noter", []))
    for item in exported.get("udeladelser", []):
        result.append({"kind": "udelad_start", "char_offset": item["char_from"]})
        result.append({"kind": "udelad_end", "char_offset": item["char_to"]})
    return result


def _completed_pages(exported: Mapping | None, pages: list[Mapping]) -> list[int]:
    if not exported or "sider" not in exported:
        return []
    sides = exported.get("sider")
    if not isinstance(sides, Mapping) or sides.get("i_alt") != len(pages):
        raise BoundaryError("markeringernes sidefremskridt matcher ikke fladen")
    reviewed = sides.get("gennemgaaet")
    if not isinstance(reviewed, list):
        raise BoundaryError("markeringernes gennemgåede sider er ugyldige")
    allowed = {page["pdfPage"] for page in pages}
    if any(
        isinstance(page, bool) or not isinstance(page, int) or page not in allowed
        for page in reviewed
    ):
        raise BoundaryError("markeringerne henviser til en ukendt PDF-side")
    if len(set(reviewed)) != len(reviewed):
        raise BoundaryError("markeringerne gentager en gennemgået PDF-side")
    return sorted(reviewed)


def _load_inputs(args) -> tuple[bytes, bytes, bytes, dict, Mapping]:
    baseline_bytes = args.baseline.read_bytes()
    calamari_bytes = args.calamari.read_bytes()
    raw_bytes = args.raw.read_bytes()
    source = _source_from_manifest(json.loads(args.source_manifest.read_text(encoding="utf-8")))
    for label, data, field in (
        ("baseline", baseline_bytes, "baseline_sha256"),
        ("calamari", calamari_bytes, "calamari_sha256"),
        ("raw OCR", raw_bytes, "raw_ocr_sha256"),
    ):
        if source.get(field) != hashlib.sha256(data).hexdigest():
            raise ValueError(f"{label} hash matcher ikke source manifest")
    queue = json.loads(args.queue_manifest.read_text(encoding="utf-8"))
    if queue.get("source") != source:
        raise ValueError("queue source hashes matcher ikke source manifest")
    return baseline_bytes, calamari_bytes, raw_bytes, source, queue


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in ("--baseline", "--queue-manifest", "--source-manifest",
                 "--calamari", "--raw", "--anchored", "--out"):
        parser.add_argument(name, type=Path, required=True)
    parser.add_argument("--markeringer", type=Path, help="tidligere 1939-graenseflade.json")
    args = parser.parse_args()
    if args.out.exists():
        raise FileExistsError(args.out)

    baseline_bytes, calamari_bytes, raw_bytes, source, queue = _load_inputs(args)
    records = {
        record["record_key"]: record
        for record in json.loads(baseline_bytes)
        if isinstance(record, Mapping) and isinstance(record.get("record_key"), str)
    }
    calamari_text = calamari_bytes.decode("utf-8")
    spans = collect_accepted_spans(
        json.loads(args.anchored.read_text(encoding="utf-8")),
        _automatic_candidates(queue),
    )
    boundary_model = build_boundary_view_model(
        spans, _clauses_for(calamari_text), calamari_text, raw_bytes.decode("utf-8"),
        records, source,
    )
    text_model = build_text_model(calamari_text, boundary_model)
    base_annotations = _base_annotations(text_model)
    annotations = base_annotations
    exported = None
    if args.markeringer:
        exported = json.loads(args.markeringer.read_text(encoding="utf-8"))
        if exported.get("source") != source:
            raise ValueError("markeringer matcher ikke source manifest")
        annotations = apply_markeringer(annotations, exported)
    initial_text = compose_marked_text(calamari_text, annotations)
    pages = build_page_view_models(calamari_text, annotations)
    if "".join(page["initialText"] for page in pages) != initial_text:
        raise BoundaryError("siderne kan ikke samles til den markerede tekst")
    mappings = line_marker_mappings(calamari_text, base_annotations)
    mappings.extend(line_marker_mappings(calamari_text, annotations))
    unique_mappings = list({
        (item["kind"], item["text"], item["canonicalOffset"], item["displayOffset"], item.get("origin")):
        item for item in mappings
    }.values())
    data = {
        "schemaVersion": 1,
        "source": source,
        "sourceText": calamari_text,
        "initialText": initial_text,
        "pages": pages,
        "completedPages": _completed_pages(exported, pages),
        "expectedBoundaryOffsets": [item["char_offset"] for item in text_model["forudsatte_skaeringer"]],
        "expectedProposalOffsets": [item["char_offset"] for item in text_model["forslag"]],
        "lineMarkerMappings": unique_mappings,
    }
    payload = json.dumps(data, ensure_ascii=False).replace("<", "\\u003c")
    shared = SHARED_UI_PATH.read_text(encoding="utf-8")
    controller = UI_PATH.read_text(encoding="utf-8")
    with args.out.open("x", encoding="utf-8") as handle:
        handle.write(HTML_PREFIX)
        handle.write(payload)
        handle.write(";\n")
        handle.write(shared)
        handle.write("\n")
        handle.write(controller)
        handle.write("\n")
        handle.write(HTML_SUFFIX)
    print(
        f"{len(text_model['forudsatte_skaeringer'])} grænser · "
        f"{len(text_model['huller'])} huller · {len(text_model['forslag'])} forslag · "
        f"{len(text_model['pdf_sider'])} PDF-sider"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
