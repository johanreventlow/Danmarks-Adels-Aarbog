"""Generate a private, browser-local human review view for 1939."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path

import segment
from prepare_review_queue_1939 import build_review_view_model
from review_queue_1939 import sample_auto_resolved


UI_PATH = Path(__file__).with_name("human_review_1939_ui.js")
HTML_PREFIX = """<!doctype html>
<meta charset="utf-8">
<title>1939 menneskeark</title>
<style>
body{font:16px system-ui;margin:0;display:grid;grid-template-columns:360px 1fr;height:100vh;color:#18212a}
aside{border-right:1px solid #ccd5dd;padding:14px;overflow:auto;background:#fafbfd}main{padding:24px;overflow:auto;max-width:1280px}
button,select{font:inherit;padding:8px;margin:4px 0;box-sizing:border-box}.candidate{border:1px solid #cad7e2;border-left:5px solid #3977a9;padding:14px;margin:14px 0;border-radius:5px}pre{white-space:pre-wrap;background:#f6f8fa;padding:14px;border-radius:5px}.saved{color:#166534;font-weight:600}
</style>
<aside>
  <h2>1939 menneskeark</h2>
  <p>Du undersøger en <b>historisk kildepost</b> – ikke om personen allerede er rigtig i databasen.</p>
  <p>Gemmer kun i denne browser. Eksport henter en privat JSON-kopi; intet sendes eller overskrives.</p>
  <p data-role="save-state" class="saved">Klar. Ændringer gemmes automatisk lokalt.</p>
</aside>
<main data-role="app"></main>
<script>
const DATA="""
HTML_SUFFIX = """;
function downloadDraft(draft) {
  const blob = new Blob([JSON.stringify(draft, null, 2)], {type: 'application/json'});
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = '1939-review-kladd.json';
  link.click();
}
window.DAA1939Review.init({data: DATA, download: downloadDraft});
</script>
"""


def _pages(value: object) -> list[int]:
    """Expand a simple page span without silently dropping middle pages."""
    parts = str(value or "").split("-", 1)
    try:
        first = int(parts[0])
        last = int(parts[-1])
    except ValueError:
        return []
    return list(range(first, last + 1)) if last >= first else []


def _display_span(pages: list[int]) -> str | None:
    if not pages:
        return None
    return str(pages[0]) if pages[0] == pages[-1] else f"{pages[0]}-{pages[-1]}"


def _source_from_manifest(value: object) -> dict:
    if not isinstance(value, dict):
        raise ValueError("source manifest skal være en mapping")
    source = value.get("source", value)
    if not isinstance(source, dict):
        raise ValueError("source manifest source skal være en mapping")
    return source


def _require_same_source(label: str, actual: object, expected: dict) -> None:
    if actual != expected:
        raise ValueError(f"{label} source hashes matcher ikke source manifest")


def _review_decisions(value: object, baseline_hash: str,
                      baseline_keys: set[str]) -> dict[str, dict]:
    if not isinstance(value, dict):
        raise ValueError("review skal være en mapping")
    if value.get("baseline_sha256") != baseline_hash:
        raise ValueError("review baseline hash matcher ikke")
    entries = value.get("entries")
    if not isinstance(entries, list):
        raise ValueError("review entries skal være en liste")
    decisions: dict[str, dict] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("review entry skal være en mapping")
        key = entry.get("baseline_record_key")
        if not isinstance(key, str) or not key:
            raise ValueError("review baseline_record_key mangler")
        if key in decisions:
            raise ValueError("dublet review baseline_record_key")
        decisions[key] = entry
    if set(decisions) != baseline_keys:
        raise ValueError("review baseline-dækning fejler")
    return decisions


def _assert_sourceless_review_is_unreviewed(decisions: dict[str, dict]) -> None:
    """Permit only the decision-free Task 1 template without source provenance."""
    allowed_fields = {"baseline_record_key", "review_status", "baseline_locator"}
    for decision in decisions.values():
        if decision.get("review_status") != "unreviewed":
            raise ValueError("legacy review med afgørelse kræver source manifest")
        if set(decision) - allowed_fields:
            raise ValueError("legacy review med afgørelsesfelter kræver source manifest")


def _candidate_from_post(post: dict, calamari_first_pdf_page: int) -> dict:
    calamari_pages = _pages(post.get("sider"))
    pdf_pages = [calamari_first_pdf_page + page - 1 for page in calamari_pages]
    candidate_id = post.get("candidate_id") or post.get("lokal_id")
    if not isinstance(candidate_id, str) or not candidate_id:
        raise ValueError("segmentpost mangler candidate_id")
    return {
        "candidate_id": candidate_id,
        "lokal_id": post.get("lokal_id") or candidate_id,
        "pdf_pages": pdf_pages,
        "calamari_pages": calamari_pages,
        "raw_text": post.get("raw_text") or "",
        "rank_reason": "samme_pdf_side",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--queue-manifest", type=Path, required=True)
    parser.add_argument("--source-manifest", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--calamari", type=Path, required=True)
    parser.add_argument("--calamari-first-pdf-page", type=int, required=True,
                        help="PDF page represented by Calamari's PAGE 0001")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        raise FileExistsError(args.out)
    baseline_bytes = args.baseline.read_bytes()
    records = json.loads(baseline_bytes)
    if not isinstance(records, list):
        raise ValueError("baseline skal være en liste")
    calamari_bytes = args.calamari.read_bytes()
    source_manifest = _source_from_manifest(
        json.loads(args.source_manifest.read_text(encoding="utf-8"))
    )
    baseline_hash = hashlib.sha256(baseline_bytes).hexdigest()
    calamari_hash = hashlib.sha256(calamari_bytes).hexdigest()
    if source_manifest.get("baseline_sha256") != baseline_hash:
        raise ValueError("baseline hash matcher ikke source manifest")
    if source_manifest.get("calamari_sha256") != calamari_hash:
        raise ValueError("calamari hash matcher ikke source manifest")
    queue = json.loads(args.queue_manifest.read_text(encoding="utf-8"))
    if not isinstance(queue, dict):
        raise ValueError("queue manifest skal være en mapping")
    _require_same_source("queue", queue.get("source"), source_manifest)
    review = json.loads(args.review.read_text(encoding="utf-8"))
    if isinstance(review, dict) and "source" in review:
        _require_same_source("review", review["source"], source_manifest)
    baseline_keys = {
        record["record_key"] for record in records
        if isinstance(record, dict) and isinstance(record.get("record_key"), str)
    }
    decisions = _review_decisions(review, baseline_hash, baseline_keys)
    if not isinstance(review, dict) or "source" not in review:
        _assert_sourceless_review_is_unreviewed(decisions)
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        posts = segment._segment_1939_v2(
            calamari_bytes.decode("utf-8").splitlines(),
            segment.UDGAVE_PROFILER[source_manifest["profile_version"]],
        )
    by_pdf_page: dict[str, list[dict]] = {}
    for post in posts:
        candidate = _candidate_from_post(post, args.calamari_first_pdf_page)
        for page in candidate["pdf_pages"]:
            by_pdf_page.setdefault(str(page), []).append(candidate)
    nearby_candidates = {
        record["record_key"]: sum(
            (by_pdf_page.get(str(page), []) for page in _pages(record.get("sider"))), []
        )
        for record in records
    }
    model = build_review_view_model(
        records, queue, nearby_candidates, sample_auto_resolved(queue), decisions,
    )
    payload = json.dumps(
        {"baseline_sha256": baseline_hash, **model}, ensure_ascii=False,
    ).replace("</", "<\\/")
    controller = UI_PATH.read_text(encoding="utf-8")
    with args.out.open("x", encoding="utf-8") as handle:
        handle.write(HTML_PREFIX)
        handle.write(payload)
        handle.write(";\n")
        handle.write(controller)
        handle.write("\n")
        handle.write(HTML_SUFFIX)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
