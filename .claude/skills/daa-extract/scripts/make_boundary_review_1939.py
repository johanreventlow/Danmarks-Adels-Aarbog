"""Bygger en privat, browserlokal grænsegennemgang for 1939."""

from __future__ import annotations

import argparse
import copy
import contextlib
import hashlib
import io
import json
import tempfile
from collections.abc import Mapping
from pathlib import Path

import segment
from boundary_signals_1939 import classify_gap, raa_ocr_hoved_i_hul, span_signals
from boundary_spans_1939 import BoundaryError, build_boundaries, collect_accepted_spans
from prepare_review_queue_1939 import validate_effective_candidate_injectivity

KONTEKST_TEGN = 400
UI_PATH = Path(__file__).with_name("boundary_review_1939_ui.js")
SHARED_UI_PATH = Path(__file__).with_name("review_ui_shared.js")
HTML_PREFIX = """<!doctype html>
<meta charset="utf-8">
<title>1939 grænsegennemgang</title>
<style>
*{box-sizing:border-box}body{font:16px system-ui;margin:0;display:grid;grid-template-columns:320px minmax(0,1fr);height:100dvh;color:#18212a}
aside{border-right:1px solid #ccd5dd;padding:14px;background:#fafbfd;display:flex;flex-direction:column;min-height:0;height:100dvh;overflow:hidden}main{padding:24px;overflow:auto;max-width:1280px;min-width:0}
button,select,input{font:inherit;padding:8px;margin:4px 0}.candidate{border:1px solid #cad7e2;border-left:5px solid #3977a9;padding:14px;margin:14px 0;border-radius:5px}pre{white-space:pre-wrap;background:#f6f8fa;padding:14px;border-radius:5px}.saved{color:#166534;font-weight:600}
[data-action="toggle-sidebar"]{display:none;width:100%;text-align:left}[data-role="sidebar-navigation"]{display:flex;flex-direction:column;min-height:0;flex:1;overflow:hidden}[data-role="boundary-list"]{flex:1;min-height:0;overflow-y:auto;padding-right:4px}[data-role="record-search"]{width:100%}[data-role="record-list"]{display:flex;flex-direction:column;gap:4px;flex:1;min-height:0;overflow-y:auto;padding-right:4px}[data-role="record-list"] button{text-align:left;display:flex;justify-content:space-between;gap:8px;align-items:center;border:1px solid #ccd5dd;background:white;border-radius:5px}[data-role="record-list"] button[aria-current="true"]{border-color:#3977a9;background:#eaf4fc}[data-role="record-status"]{font-size:.78rem;font-weight:700;color:#596773}[data-status="missing"]{color:#9a3412}[data-status="draft"]{color:#166534}[data-role="dashboard"] button{width:100%;text-align:left}[data-role="dashboard"] button[aria-current="true"]{font-weight:700;border-color:#3977a9}.source-label{margin-bottom:4px}.source-text{margin-top:0;border-left:4px solid #7496b4}
@media(max-width:720px){body{display:block;height:auto}aside{position:sticky;top:0;z-index:10;border-right:0;border-bottom:1px solid #ccd5dd;height:auto;max-height:72dvh;overflow:auto}.sidebar-intro{display:none}[data-action="toggle-sidebar"]{display:block}[data-role="sidebar-navigation"]{overflow:visible}aside[data-mobile-open="false"] [data-role="sidebar-navigation"]{display:none}main{padding:16px;overflow:visible}}
</style>
<aside data-mobile-open="false">
  <div class="sidebar-intro"><h2>1939 grænsegennemgang</h2>
  <p>Du undersøger grænsen mellem to <b>historiske kildeposter</b>.</p>
  <p>Gemmer kun i denne browser. Eksport henter en privat JSON-kopi; intet sendes eller overskrives.</p></div>
  <p data-role="save-state" class="saved">Klar. Ændringer gemmes automatisk lokalt.</p>
  <button type="button" data-action="toggle-sidebar" aria-expanded="false">Vælg grænse</button>
  <div data-role="sidebar-navigation"></div>
</aside>
<main data-role="app"></main>
<script>
const DATA="""
HTML_SUFFIX = """;
function downloadDraft(draft) {
  const blob = new Blob([JSON.stringify(draft, null, 2)], {type: 'application/json'});
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = '1939-graensegennemgang.json';
  link.click();
}
window.DAABoundaryReview.init({data: DATA, download: downloadDraft});
</script>
"""


def _group_of(record: Mapping) -> object:
    gruppe = record.get("_gruppe_nr")
    if gruppe is not None:
        return ("gruppe", gruppe)
    local_id = record.get("_v2_lokal_id")
    branch = local_id.rsplit(".", 1)[0] if isinstance(local_id, str) and "." in local_id else local_id
    return ("gren", branch)


def _raw_bridge(span: Mapping | None, raw_length: int) -> tuple[int, int] | None:
    if span is None:
        return None
    candidate = span.get("candidate")
    bridge = candidate.get("raw_structure_bridge") if isinstance(candidate, Mapping) else None
    if bridge is None:
        return None
    if not isinstance(bridge, Mapping):
        raise BoundaryError("rå-OCR-broen skal være en mapping")
    raw_from, raw_to = bridge.get("raw_char_from"), bridge.get("raw_char_to")
    if any(isinstance(value, bool) or not isinstance(value, int) or value < 0
           for value in (raw_from, raw_to)):
        raise BoundaryError("rå-OCR-broen har ugyldige koordinater")
    if raw_to <= raw_from or raw_to > raw_length:
        raise BoundaryError("rå-OCR-broen ligger uden for den rå OCR-kilde")
    return raw_from, raw_to


def _raw_gap_window(boundary: Mapping, by_key: Mapping, raw_text: str) -> str:
    neighbours = []
    for side in ("before", "after"):
        boundary_span = boundary.get(side)
        key = boundary_span.get("baseline_record_key") if isinstance(boundary_span, Mapping) else None
        neighbours.append(by_key.get(key) if key is not None else None)
    before_bridge = _raw_bridge(neighbours[0], len(raw_text))
    after_bridge = _raw_bridge(neighbours[1], len(raw_text))
    if before_bridge is None or after_bridge is None:
        return ""
    raw_from, raw_to = before_bridge[1], after_bridge[0]
    if raw_to < raw_from:
        return ""
    return raw_text[raw_from:raw_to]


def _page_evidence(boundary_span: Mapping | None, by_key: Mapping,
                   records: Mapping) -> tuple[object, object]:
    if boundary_span is None:
        return None, None
    record_key = boundary_span["baseline_record_key"]
    span = by_key[record_key]
    candidate = span.get("candidate")
    pdf_pages = candidate.get("pdf_pages") if isinstance(candidate, Mapping) else None
    return copy.deepcopy(pdf_pages), copy.deepcopy(records[record_key].get("sider"))


def build_boundary_view_model(spans: list[dict], clauses: list[dict],
                              calamari_text: str, raw_text: str,
                              records: Mapping, source: Mapping) -> dict:
    """Saml alle grænser i én mistankesorteret liste uden at ændre et spænd.

    ``summary.graenser`` er det samlede antal grænser, mens
    ``summary.med_signal`` tæller grænser med mindst ét signal. Signaler ud over
    ren længdeafvigelse står først, derefter huller med brødtekst og til sidst
    resten. Der findes ingen massebekræftelses-bunke.
    """
    boundaries = build_boundaries(spans, len(calamari_text))
    by_key = {span["baseline_record_key"]: span for span in spans}
    validate_effective_candidate_injectivity(
        {key: span["candidate"] for key, span in by_key.items()},
        dict(source),
    )
    groups: dict[object, list[dict]] = {}
    for key, record in records.items():
        if not isinstance(record, Mapping):
            raise BoundaryError(f"baseline-post {key} skal være en mapping")
        entry = copy.deepcopy(dict(record))
        if key in by_key:
            entry["char_from"] = by_key[key]["char_from"]
        groups.setdefault(_group_of(record), []).append(entry)
    signals_by_key: dict[str, list[str]] = {}
    for key, span in by_key.items():
        if key not in records:
            raise BoundaryError(f"accepteret spænd har ukendt post {key}")
        record = records[key]
        siblings = groups[_group_of(record)]
        lengths = [
            by_key[sibling["record_key"]]["char_to"]
            - by_key[sibling["record_key"]]["char_from"]
            for sibling in siblings
            if sibling["record_key"] != key and sibling["record_key"] in by_key
        ]
        signals_by_key[key] = span_signals(
            span, record, calamari_text[span["char_from"]:span["char_to"]],
            siblings, sibling_lengths=lengths,
        )
    entries = []
    for boundary in boundaries:
        gap = boundary["gap"]
        gap_text = calamari_text[gap["char_from"]:gap["char_to"]]
        raw_window = _raw_gap_window(boundary, by_key, raw_text)
        summary = classify_gap(clauses, gap)
        signals = []
        for side in ("before", "after"):
            span = boundary[side]
            if span is not None:
                signals.extend(signals_by_key.get(span["baseline_record_key"], []))
        if raw_window and raa_ocr_hoved_i_hul(gap_text, raw_window):
            signals.append("hoved_i_raa_ocr")
        before_pdf_pages, before_sider = _page_evidence(
            boundary["before"], by_key, records,
        )
        after_pdf_pages, after_sider = _page_evidence(
            boundary["after"], by_key, records,
        )
        entry = {
            **boundary,
            "gap_summary": summary,
            "gap_text": gap_text,
            "raw_window": raw_window,
            "signals": sorted(set(signals)),
            "before_context": calamari_text[
                max(0, gap["char_from"] - KONTEKST_TEGN):gap["char_from"]],
            "after_context": calamari_text[
                gap["char_to"]:gap["char_to"] + KONTEKST_TEGN],
            "before_navn": (records[boundary["before"]["baseline_record_key"]].get("navn")
                            if boundary["before"] else None),
            "after_navn": (records[boundary["after"]["baseline_record_key"]].get("navn")
                           if boundary["after"] else None),
            "before_pdf_pages": before_pdf_pages,
            "before_sider": before_sider,
            "after_pdf_pages": after_pdf_pages,
            "after_sider": after_sider,
        }
        entries.append(entry)
    entries.sort(key=lambda entry: (
        0 if any(signal != "laengdeafvigelse" for signal in entry["signals"])
        else 1 if entry["gap_summary"]["har_broedtekst"] else 2,
    ))
    view_boundaries = [entry["boundary_id"] for entry in entries]
    return {
        "schema_version": 1,
        "source": copy.deepcopy(dict(source)),
        "summary": {
            "graenser": len(entries),
            "med_signal": sum(bool(entry["signals"]) for entry in entries),
        },
        "views": {"graenser": view_boundaries},
        "boundaries": entries,
    }


def _source_from_manifest(value: object) -> dict:
    if not isinstance(value, dict):
        raise BoundaryError("source manifest skal være en mapping")
    source = value.get("source", value)
    if not isinstance(source, dict):
        raise BoundaryError("source manifest source skal være en mapping")
    return source


def _automatic_candidates(queue: Mapping) -> dict:
    entries = queue.get("entries")
    if not isinstance(entries, list):
        raise BoundaryError("queue manifest entries skal være en liste")
    result = {}
    for entry in entries:
        if not isinstance(entry, Mapping) or entry.get("queue_class") != "auto_resolved":
            continue
        key = entry.get("baseline_record_key")
        if not isinstance(key, str) or not key:
            raise BoundaryError("automatisk køpost mangler baseline_record_key")
        if not isinstance(entry.get("candidate"), Mapping):
            raise BoundaryError(
                f"automatisk køpost {key} mangler en kandidat-mapping"
            )
        if key in result:
            raise BoundaryError(
                f"automatisk kø har dublet baseline_record_key {key}"
            )
        result[key] = {
            "baseline_record_key": key,
            "candidate": entry["candidate"],
        }
    return result


def _clauses_for(text: str) -> list[dict]:
    """Afled klausul-regnskabet gennem den kanoniske segmenteringsvej."""
    with tempfile.TemporaryDirectory() as directory:
        source_path = Path(directory) / "calamari.txt"
        ledger_path = Path(directory) / "evidence-ledger.json"
        source_path.write_text(text, encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            segment.main(
                str(source_path), udgave="1939-v2", emit_evidence_ledger=str(ledger_path),
            )
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    clauses = ledger.get("clauses") if isinstance(ledger, Mapping) else None
    if not isinstance(clauses, list):
        raise BoundaryError("klausul-regnskab mangler clauses")
    normalized = []
    for clause in clauses:
        if not isinstance(clause, Mapping) or not isinstance(clause.get("span"), Mapping):
            raise BoundaryError("klausul-regnskab har ugyldig klausul")
        normalized.append({
            **clause,
            "char_from": clause["span"].get("char_from"),
            "char_to": clause["span"].get("char_to"),
        })
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in ("--baseline", "--queue-manifest", "--source-manifest",
                 "--calamari", "--raw", "--anchored", "--out"):
        parser.add_argument(name, type=Path, required=True)
    parser.add_argument("--verdicts", type=Path,
                        help="tidligere eksport af grænse-domme")
    args = parser.parse_args()
    if args.out.exists():
        raise FileExistsError(args.out)
    baseline_bytes = args.baseline.read_bytes()
    calamari_bytes = args.calamari.read_bytes()
    raw_bytes = args.raw.read_bytes()
    source = _source_from_manifest(
        json.loads(args.source_manifest.read_text(encoding="utf-8")))
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
    model = build_boundary_view_model(
        spans, _clauses_for(calamari_text), calamari_text, raw_bytes.decode("utf-8"),
        records, source,
    )
    if args.verdicts:
        earlier = json.loads(args.verdicts.read_text(encoding="utf-8"))
        if earlier.get("source") != source:
            raise ValueError("tidligere domme matcher ikke source manifest")
        model["tidligere_domme"] = earlier
    payload = json.dumps(model, ensure_ascii=False).replace("<", "\\u003c")
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
    print(f"{model['summary']['graenser']} grænser · "
          f"{model['summary']['med_signal']} med signal")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
