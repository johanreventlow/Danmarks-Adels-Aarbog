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


HTML = r"""<!doctype html>
<meta charset="utf-8">
<title>1939 menneskeark</title>
<style>
body{font:16px system-ui;margin:0;display:grid;grid-template-columns:360px 1fr;height:100vh;color:#18212a}
aside{border-right:1px solid #ccd5dd;padding:14px;overflow:auto;background:#fafbfd}main{padding:24px;overflow:auto;max-width:1280px}
input,select,textarea,button{font:inherit;padding:8px;margin:4px 0;width:100%;box-sizing:border-box}textarea{min-height:96px}.row{padding:9px;border-bottom:1px solid #dde4ea;cursor:pointer}.active{background:#dceeff}.row small{color:#50606c}pre{white-space:pre-wrap;background:#f6f8fa;padding:14px;border-radius:5px;line-height:1.4}.candidate{border:1px solid #cad7e2;border-left:5px solid #3977a9;padding:14px;margin:14px 0;border-radius:5px}.candidate h4{margin:0 0 6px}.muted{color:#50606c}.warn{color:#8b4b00;font-weight:600}.saved{color:#166534;font-weight:600}.guide{background:#eef7f0;border-left:5px solid #398052;padding:12px}.candidate button{width:auto;padding:7px 11px}
</style>
<aside>
  <h2>1939 menneskeark</h2>
  <p>Du undersøger en <b>historisk kildepost</b> – ikke om personen allerede er rigtig i databasen.</p>
  <p class="muted">Gem gemmer kun i denne browser. Eksport henter en privat JSON-kopi; intet sendes eller overskrives.</p>
  <p id="save-state" class="saved">Klar. Ændringer gemmes automatisk lokalt.</p>
  <input id="q" placeholder="Søg navn, PDF-side eller id">
  <button onclick="save()">Gem kladde lokalt</button>
  <button onclick="downloadFile()">Eksportér kladde</button>
  <div id="views"></div>
  <div id="list"></div>
</aside>
<main id="card"></main>
<script>
const DATA=__PAYLOAD__;
let rows=DATA.records, selected=0, activeView=DATA.default_view;
const key='daa1939-'+DATA.baseline_sha256;
const saved=JSON.parse(localStorage.getItem(key)||'{}');
function ensureDecision(r){return r.decision||(r.decision={baseline_record_key:r.record_key,review_status:'unreviewed'})}
for(const r of rows)Object.assign(ensureDecision(r),saved[r.record_key]||{});
function e(x){let d=document.createElement('div');d.textContent=x||'';return d.innerHTML}
function persist(){localStorage.setItem(key,JSON.stringify(Object.fromEntries(rows.map(r=>[r.record_key,r.decision]))))}
function showSaved(message){document.querySelector('#save-state').textContent=message}
function setTrack(localId){
  const r=rows[selected], decision=ensureDecision(r), note=`Visuelt spor: parserpost ${localId}. Kræver stadig eksakt Calamari- og rå-OCR-ankring.`;
  decision.review_status='menneskeark';
  decision.reason=note;
  persist();
  showSaved('✓ Visuelt spor er gemt lokalt.');
  render();
}
function setView(view){activeView=view;selected=0;render()}
function render(){
  const q=document.querySelector('#q').value.toLowerCase();
  const shown=rows.filter(r=>DATA.views[activeView].includes(r.record_key)&&JSON.stringify(r).toLowerCase().includes(q));
  const views=document.querySelector('#views'); views.innerHTML='';
  for(const view of ['required','automatic','audit','completed']){const b=document.createElement('button');b.textContent=view+' ('+DATA.summary[view]+')';b.onclick=()=>setView(view);if(view===activeView)b.className='active';views.append(b)}
  const blocked=document.createElement('p');blocked.className='muted';blocked.textContent='Kildeblokeret: '+DATA.summary.source_blocked;views.append(blocked);
  const list=document.querySelector('#list'); list.innerHTML='';
  shown.forEach(r=>{const i=rows.indexOf(r),d=document.createElement('div');d.className='row '+(i===selected?'active':'');d.innerHTML='<b>'+e(r.navn||'(uden navn)')+'</b><br><small>PDF s. '+e(r.sider)+' · '+e(r.queue_class)+' · '+e((r.decision||{}).review_status||'unreviewed')+'</small>';d.onclick=()=>{selected=i;render()};list.append(d)});
  if(!shown.includes(rows[selected]))selected=rows.indexOf(shown[0]);
  const r=rows[selected]; if(!r)return;
  const candidates=(r.candidates||[]).map(c=>'<details class="candidate" '+(r.initial_candidate_ids.includes(c.candidate_id)?'open':'')+'><summary><b>Parserpost '+e(c.lokal_id||'(uden lokalt id)')+'</b></summary><p class="muted">PDF s. '+e((c.pdf_pages||[]).join('-'))+' · Calamari-scan '+e((c.calamari_pages||[]).join('-'))+'</p><p><b>Boksens start og slut er parserens foreslåede postgrænse.</b> Den kan godt omtale flere beslægtede personer.</p><pre>'+e(c.raw_text)+'</pre><button onclick="setTrack('+JSON.stringify(c.lokal_id)+')">Markér som visuelt spor</button></details>').join('')||'<p class="warn">Ingen parserkandidat på samme PDF-side. Lad posten stå urørt eller send den til menneskearket med en begrundelse.</p>';
  document.querySelector('#card').innerHTML='<h1>'+e(r.navn||'(uden navn)')+'</h1><p class="muted">PDF-sider: '+e(r.sider)+' · Klasse: '+e(r.queue_class)+' · Årsag: '+e(r.reason_code)+'</p><div class="guide"><b>Hvad skal du vurdere?</b> Om én af de viste kandidatposter ser ud til at rumme den relevante kildetekst for den gamle post. Side-nære kandidater er kun læsehjælp og ændrer aldrig klassifikationen. Vælg kun “Markér som visuelt spor”, når kandidaten tydeligt er den rigtige historiske sammenhæng. Det er <em>ikke</em> en endelig accept: en senere maskinel kontrol skal stadig finde de eksakte tekstankre.</div><h3>Gammel kildetekst (arvet, kan være bred)</h3><pre>'+e(r.narrative)+'</pre><h3>Ny OCR: kandidatposter på samme PDF-side</h3>'+candidates+'<h3>Din kladdeafgørelse</h3><label>Status<select id="status"><option value="unreviewed">Ikke gennemgået</option><option value="menneskeark">Menneskeark / kræver ankring</option><option value="eksplicit_dublet">Eksplicit dublet</option></select></label><label>Begrundelse (påkrævet ved menneskeark)<textarea id="reason"></textarea></label><label>Dubletmål: baseline record_key (kun ved eksplicit dublet)<input id="target"></label><p class="warn">Endelig “accepteret” kan ikke vælges her, fordi den kræver fulde, eksakte Calamari- og rå-OCR-ankre. Arket gætter aldrig.</p>';
  const s=document.querySelector('#status'),reason=document.querySelector('#reason'),target=document.querySelector('#target');
  const decision=ensureDecision(r);s.value=decision.review_status==='accepteret'?'unreviewed':decision.review_status;
  reason.value=decision.reason||'';target.value=decision.duplicate_of_baseline_record_key||'';
  s.onchange=()=>{decision.review_status=s.value;persist();showSaved('✓ Status er gemt lokalt.')};
  reason.oninput=()=>{decision.reason=reason.value;persist();showSaved('✓ Kladde er gemt lokalt.')};
  target.oninput=()=>{decision.duplicate_of_baseline_record_key=target.value;persist();showSaved('✓ Kladde er gemt lokalt.')};
}
function save(){persist();showSaved('✓ Hele kladden er gemt lokalt i browseren.')}
function downloadFile(){const b=new Blob([JSON.stringify({schema_version:1,source:DATA.source,baseline_sha256:DATA.baseline_sha256,entries:rows.map(r=>r.decision)},null,2)],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='1939-review-kladd.json';a.click()}
document.querySelector('#q').oninput=render;render();
</script>"""


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
    # The extractor writes its normal artifact and diagnostics to standard
    # streams. This UI generator consumes only its in-memory posts.
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
        {"baseline_sha256": baseline_hash, **model},
        ensure_ascii=False,
    ).replace("</", "<\\/")
    with args.out.open("x", encoding="utf-8") as handle:
        handle.write(HTML.replace("__PAYLOAD__", payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
