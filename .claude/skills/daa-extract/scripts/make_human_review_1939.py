"""Generate a private, browser-local human review view for 1939."""

from __future__ import annotations

import argparse
from collections import Counter
import contextlib
import hashlib
import io
import json
from pathlib import Path
import re

import segment
from prepare_review_queue_1939 import (
    _validate_source_bound_candidate,
    build_review_view_model,
)
from prepare_coverage_1939 import validate_review_template
from review_queue_1939 import sample_auto_resolved
from review_choices_1939 import validate_choice_export


UI_PATH = Path(__file__).with_name("human_review_1939_ui.js")
HTML_PREFIX = """<!doctype html>
<meta charset="utf-8">
<title>1939 menneskeark</title>
<style>
*{box-sizing:border-box}body{font:16px system-ui;margin:0;display:grid;grid-template-columns:320px minmax(0,1fr);height:100dvh;color:#18212a}
aside{border-right:1px solid #ccd5dd;padding:14px;background:#fafbfd;display:flex;flex-direction:column;min-height:0;height:100dvh;overflow:hidden}main{padding:24px;overflow:auto;max-width:1280px;min-width:0}
button,select,input{font:inherit;padding:8px;margin:4px 0}.candidate{border:1px solid #cad7e2;border-left:5px solid #3977a9;padding:14px;margin:14px 0;border-radius:5px}pre{white-space:pre-wrap;background:#f6f8fa;padding:14px;border-radius:5px}.saved{color:#166534;font-weight:600}
[data-action="toggle-sidebar"]{display:none;width:100%;text-align:left}[data-role="sidebar-navigation"]{display:flex;flex-direction:column;min-height:0;flex:1;overflow:hidden}[data-role="record-search"]{width:100%}[data-role="record-list"]{display:flex;flex-direction:column;gap:4px;flex:1;min-height:0;overflow-y:auto;padding-right:4px}[data-role="record-list"] button{text-align:left;display:flex;justify-content:space-between;gap:8px;align-items:center;border:1px solid #ccd5dd;background:white;border-radius:5px}[data-role="record-list"] button[aria-current="true"]{border-color:#3977a9;background:#eaf4fc}[data-role="record-status"]{font-size:.78rem;font-weight:700;color:#596773}[data-status="missing"]{color:#9a3412}[data-status="draft"]{color:#166534}[data-role="dashboard"] button{width:100%;text-align:left}[data-role="dashboard"] button[aria-current="true"]{font-weight:700;border-color:#3977a9}.source-label{margin-bottom:4px}.source-text{margin-top:0;border-left:4px solid #7496b4}
@media(max-width:720px){body{display:block;height:auto}aside{position:sticky;top:0;z-index:10;border-right:0;border-bottom:1px solid #ccd5dd;height:auto;max-height:72dvh;overflow:auto}.sidebar-intro{display:none}[data-action="toggle-sidebar"]{display:block}[data-role="sidebar-navigation"]{overflow:visible}aside[data-mobile-open="false"] [data-role="sidebar-navigation"]{display:none}main{padding:16px;overflow:visible}}
</style>
<aside data-mobile-open="false">
  <div class="sidebar-intro"><h2>1939 menneskeark</h2>
  <p>Du undersøger en <b>historisk kildepost</b> – ikke om personen allerede er rigtig i databasen.</p>
  <p>Gemmer kun i denne browser. Eksport henter en privat JSON-kopi; intet sendes eller overskrives.</p></div>
  <p data-role="save-state" class="saved">Klar. Ændringer gemmes automatisk lokalt.</p>
  <button type="button" data-action="toggle-sidebar" aria-expanded="false">Vælg person</button>
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
  link.download = '1939-review-kladd.json';
  link.click();
}
window.DAA1939Review.init({data: DATA, download: downloadDraft});
</script>
"""


def _pages(value: object) -> list[int]:
    """Expand a simple page span, failing loudly on unparseable input."""
    text = str(value or "")
    if not text:
        return []
    parts = text.split("-", 1)
    try:
        first = int(parts[0])
        last = int(parts[-1])
    except ValueError as exc:
        raise ValueError("segmentpost sider er ugyldige") from exc
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


def _validate_embedded_choice_decisions(model: dict, choice_keys: set[str]) -> None:
    """Reject source-valid browser choices that the embedded UI would block."""
    records = model.get("records")
    if not isinstance(records, list):
        raise ValueError("view model records skal være en liste")
    by_key: dict[str, dict] = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("view model record skal være en mapping")
        key = record.get("record_key")
        if not isinstance(key, str) or not key or key in by_key:
            raise ValueError("view model record_key er ugyldig")
        by_key[key] = record
    if not choice_keys <= set(by_key):
        raise ValueError("browser choice har ukendt baseline_record_key")

    owners: dict[str, str] = {}

    def claim(candidate_id: object, key: str) -> None:
        if not isinstance(candidate_id, str) or not candidate_id:
            raise ValueError("browser choice kandidat_id er ugyldigt")
        owner = owners.get(candidate_id)
        if owner is not None and owner != key:
            raise ValueError("browser choice kandidat er allerede valgt for en anden post")
        owners[candidate_id] = key

    def contains_candidate(record: dict, candidate_id: object) -> bool:
        candidates = record.get("candidates")
        return (
            isinstance(candidate_id, str)
            and isinstance(candidates, list)
            and any(
                isinstance(candidate, dict) and candidate.get("candidate_id") == candidate_id
                for candidate in candidates
            )
        )

    for key, record in by_key.items():
        classification = record.get("classification")
        candidate = classification.get("candidate") if isinstance(classification, dict) else None
        if candidate is not None:
            if not isinstance(candidate, dict):
                raise ValueError("browser choice automatisk kandidat er ugyldig")
            claim(candidate.get("candidate_id"), key)

    for key, record in by_key.items():
        decision = record.get("decision")
        if (
            key not in choice_keys
            and isinstance(decision, dict)
            and decision.get("review_status") == "accepteret"
        ):
            candidate_id = decision.get("candidate_id")
            if not contains_candidate(record, candidate_id):
                raise ValueError("browser choice legacy-kandidat findes ikke blandt postens aktuelle kandidater")
            claim(candidate_id, key)

    required_by_outcome = {
        "human_selected_candidate": {
            "baseline_record_key", "outcome", "decided_at", "candidate_id",
        },
        "possible_duplicate": {
            "baseline_record_key", "outcome", "decided_at",
            "duplicate_of_baseline_record_key",
        },
        "no_candidate_fits": {
            "baseline_record_key", "outcome", "decided_at", "reason",
        },
        "undecidable": {
            "baseline_record_key", "outcome", "decided_at", "reason",
        },
    }
    for key in choice_keys:
        decision = by_key[key].get("decision")
        if not isinstance(decision, dict):
            raise ValueError("browser choice mangler decision")
        outcome = decision.get("outcome")
        required = required_by_outcome.get(outcome)
        if required is None:
            raise ValueError("browser choice har ukendt outcome")
        if not isinstance(decision.get("decided_at"), str) or not decision["decided_at"].strip():
            raise ValueError("browser choice decided_at mangler eller er ugyldigt")
        if set(decision) != required:
            raise ValueError("browser choice har uventede eller manglende felter")
        if decision.get("baseline_record_key") != key:
            raise ValueError("browser choice har forkert baseline_record_key")
        if outcome == "human_selected_candidate":
            candidate_id = decision.get("candidate_id")
            if not contains_candidate(by_key[key], candidate_id):
                raise ValueError(
                    "browser choice kandidat findes ikke blandt postens aktuelle kandidater"
                )
            claim(candidate_id, key)
        elif outcome == "possible_duplicate":
            target = decision.get("duplicate_of_baseline_record_key")
            if not isinstance(target, str) or not target or target not in by_key:
                raise ValueError("browser choice dubletmål findes ikke")
            if target == key:
                raise ValueError("browser choice dubletmål må ikke pege på sig selv")
        elif not isinstance(decision.get("reason"), str) or not decision["reason"].strip():
            raise ValueError("browser choice reason mangler eller er ugyldigt")


def _candidate_from_post(
    post: dict,
    calamari_first_pdf_page: int,
    profile_version: str,
    post_index: int,
    *,
    force_presentation_id: bool = False,
) -> dict:
    if not isinstance(profile_version, str) or not profile_version.strip():
        raise ValueError("profile_version skal være en ikke-tom streng")
    if not isinstance(post_index, int) or isinstance(post_index, bool) or post_index < 0:
        raise ValueError("post_index skal være et ikke-negativt heltal")
    calamari_pages = _pages(post.get("sider"))
    pdf_pages = [calamari_first_pdf_page + page - 1 for page in calamari_pages]
    lokal_id = post.get("lokal_id")
    if lokal_id is not None and (not isinstance(lokal_id, str) or not lokal_id.strip()):
        raise ValueError("segmentpost lokal_id skal være en ikke-tom streng eller null")
    existing_candidate_id = post.get("candidate_id") or lokal_id
    if existing_candidate_id is not None and (
        not isinstance(existing_candidate_id, str) or not existing_candidate_id.strip()
    ):
        raise ValueError("segmentpost candidate_id skal være en ikke-tom streng eller null")
    candidate_id = existing_candidate_id
    if force_presentation_id or candidate_id is None:
        candidate_id = f"presentation:{profile_version}:post:{post_index}"
    return {
        "candidate_id": candidate_id,
        "lokal_id": lokal_id or candidate_id,
        "pdf_pages": pdf_pages,
        "calamari_pages": calamari_pages,
        "raw_text": post.get("raw_text") or "",
        "rank_reason": "samme_pdf_side",
    }


def _presentation_candidates(
    posts: list[dict], calamari_first_pdf_page: int, profile_version: str
) -> list[dict]:
    if not isinstance(profile_version, str) or not profile_version.strip():
        raise ValueError("profile_version skal være en ikke-tom streng")
    if not isinstance(posts, list) or any(not isinstance(post, dict) for post in posts):
        raise ValueError("segmentposter skal være en liste af mappings")
    existing_ids = [post.get("candidate_id") or post.get("lokal_id") for post in posts]
    counts = Counter(value for value in existing_ids if isinstance(value, str) and value)
    candidates = [
        _candidate_from_post(
            post,
            calamari_first_pdf_page,
            profile_version,
            post_index,
            force_presentation_id=(
                existing_ids[post_index] is None or counts[existing_ids[post_index]] > 1
            ),
        )
        for post_index, post in enumerate(posts)
    ]
    candidate_ids = [candidate["candidate_id"] for candidate in candidates]
    if len(set(candidate_ids)) != len(candidate_ids):
        raise ValueError("candidate_id-kollision i præsentationskandidater")
    return candidates


_CALAMARI_PAGE_MARKER = re.compile(r"(?m)^### PAGE (\d{4}) ###\s*$")


def _text_anchor_fallback_keys(manifest: dict) -> set[str]:
    entries = manifest.get("entries", []) if isinstance(manifest, dict) else []
    return {
        entry["baseline_record_key"]
        for entry in entries
        if isinstance(entry, dict)
        and entry.get("queue_class") == "human_required"
        and isinstance(entry.get("baseline_record_key"), str)
    }


def _unique_exact_text_anchor_candidates(
    records: list[dict], calamari_text: str, calamari_first_pdf_page: int,
    profile_version: str,
) -> dict[str, dict]:
    """Build display-only candidates for unique, non-overlapping exact text spans."""
    markers = list(_CALAMARI_PAGE_MARKER.finditer(calamari_text))
    page_spans = [
        (int(marker.group(1)), marker.end(),
         markers[index + 1].start() if index + 1 < len(markers) else len(calamari_text))
        for index, marker in enumerate(markers)
    ]
    claims: dict[str, tuple[int, int, int, set[int]]] = {}
    for record in records:
        key = record.get("record_key")
        narrative = record.get("narrative")
        if not isinstance(key, str) or not key or not isinstance(narrative, str) or not narrative:
            continue
        start = calamari_text.find(narrative)
        if start < 0 or calamari_text.find(narrative, start + 1) >= 0:
            continue
        end = start + len(narrative)
        owners = [page for page, page_start, page_end in page_spans
                  if page_start <= start and end <= page_end]
        if len(owners) == 1:
            claims[key] = (start, end, owners[0], set(_pages(record.get("sider"))))
    overlapping = {
        key
        for key, (start, end, _, _) in claims.items()
        for other_key, (other_start, other_end, _, _) in claims.items()
        if key != other_key and start < other_end and other_start < end
    }
    result = {}
    for key, (start, end, calamari_page, expected_pdf_pages) in claims.items():
        if key in overlapping:
            continue
        digest = hashlib.sha256(
            f"{profile_version}\0{key}\0{start}\0{end}".encode("utf-8")
        ).hexdigest()
        candidate_id = f"presentation:{profile_version}:text-anchor:{digest}"
        pdf_page = calamari_first_pdf_page + calamari_page - 1
        result[key] = {
            "candidate_id": candidate_id,
            "lokal_id": candidate_id,
            "pdf_pages": [pdf_page],
            "calamari_pages": [calamari_page],
            "raw_text": calamari_text[start:end],
            "rank_reason": (
                "entydigt_tekstanker_uden_parserkandidat"
                if pdf_page in expected_pdf_pages
                else "entydigt_tekstanker_uden_forventet_side"
            ),
        }
    return result


def _hydrate_source_bound_candidates(model: dict, calamari_text: str,
                                     raw_text: str) -> None:
    """Add exact display slices while keeping classifier evidence unchanged."""
    records = model.get("records")
    if not isinstance(records, list):
        raise ValueError("view model records skal være en liste")
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("view model record skal være en mapping")
        if record.get("queue_class") != "auto_resolved":
            continue
        classification = record.get("classification")
        if not isinstance(classification, dict):
            raise ValueError("automatisk record mangler klassifikation")
        evidence = _validate_source_bound_candidate(
            classification.get("candidate"), calamari_text, raw_text,
        )
        candidates = record.get("candidates", [])
        if not isinstance(candidates, list):
            raise ValueError("view model candidates skal være en liste")
        matches = [candidate for candidate in candidates if isinstance(candidate, dict)
                   and candidate.get("candidate_id") == evidence["candidate_id"]]
        if len(matches) != 1:
            raise ValueError("automatisk kandidat findes ikke entydigt i view model")
        candidate = matches[0]
        if candidate.get("details") != evidence:
            raise ValueError("automatisk kandidats præsentation matcher ikke evidensen")
        span = evidence["calamari_span"]
        bridge = evidence["raw_structure_bridge"]
        candidate["calamari_verbatim_text"] = calamari_text[
            span["char_from"]:span["char_to"]
        ]
        candidate["raw_verbatim_text"] = raw_text[
            bridge["raw_char_from"]:bridge["raw_char_to"]
        ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--queue-manifest", type=Path, required=True)
    parser.add_argument("--source-manifest", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--calamari", type=Path, required=True)
    parser.add_argument("--raw", type=Path, required=True)
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
    raw_bytes = args.raw.read_bytes()
    source_manifest = _source_from_manifest(
        json.loads(args.source_manifest.read_text(encoding="utf-8"))
    )
    baseline_hash = hashlib.sha256(baseline_bytes).hexdigest()
    calamari_hash = hashlib.sha256(calamari_bytes).hexdigest()
    raw_hash = hashlib.sha256(raw_bytes).hexdigest()
    if source_manifest.get("baseline_sha256") != baseline_hash:
        raise ValueError("baseline hash matcher ikke source manifest")
    if source_manifest.get("calamari_sha256") != calamari_hash:
        raise ValueError("calamari hash matcher ikke source manifest")
    if source_manifest.get("raw_ocr_sha256") != raw_hash:
        raise ValueError("raw OCR hash matcher ikke source manifest")
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
    entries = review.get("entries") if isinstance(review, dict) else None
    is_choice_export = isinstance(review, dict) and "source" in review and (
        "exported_at" in review
        or (
            isinstance(entries, list)
            and any(isinstance(entry, dict) and "outcome" in entry for entry in entries)
        )
    )
    choice_keys: set[str] = set()
    if is_choice_export:
        context = validate_choice_export(
            review, source_manifest, baseline_keys, include_context=True,
        )
        browser_fields = {
            "baseline_record_key", "outcome", "candidate_id",
            "duplicate_of_baseline_record_key", "decided_at", "reason",
        }
        decisions = {
            key: {field: value for field, value in choice.items() if field in browser_fields}
            for key, choice in context["choices"].items()
        }
        choice_keys = set(context["choices"])
        decisions.update(context["final_legacy_entries"])
    else:
        decisions = _review_decisions(review, baseline_hash, baseline_keys)
        if not isinstance(review, dict) or "source" not in review:
            _assert_sourceless_review_is_unreviewed(decisions)
        validate_review_template(args.review, args.baseline)
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        posts = segment._segment_1939_v2(
            calamari_bytes.decode("utf-8").splitlines(),
            segment.UDGAVE_PROFILER[source_manifest["profile_version"]],
        )
    by_pdf_page: dict[str, list[dict]] = {}
    candidates = _presentation_candidates(
        posts, args.calamari_first_pdf_page, source_manifest["profile_version"]
    )
    for candidate in candidates:
        for page in candidate["pdf_pages"]:
            by_pdf_page.setdefault(str(page), []).append(candidate)
    nearby_candidates = {
        record["record_key"]: sum(
            (by_pdf_page.get(str(page), []) for page in _pages(record.get("sider"))), []
        )
        for record in records
    }
    fallback_candidates = _unique_exact_text_anchor_candidates(
        [
            record for record in records
            if record["record_key"] in _text_anchor_fallback_keys(queue)
            and not nearby_candidates[record["record_key"]]
        ],
        calamari_bytes.decode("utf-8"),
        args.calamari_first_pdf_page,
        source_manifest["profile_version"],
    )
    for record_key, candidate in fallback_candidates.items():
        nearby_candidates[record_key] = [candidate]
    model = build_review_view_model(
        records, queue, nearby_candidates, sample_auto_resolved(queue), decisions,
    )
    _hydrate_source_bound_candidates(
        model, calamari_bytes.decode("utf-8"), raw_bytes.decode("utf-8"),
    )
    if is_choice_export:
        _validate_embedded_choice_decisions(model, choice_keys)
    payload = json.dumps(
        {"baseline_sha256": baseline_hash, **model}, ensure_ascii=False,
    ).replace("<", "\\u003c")
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
