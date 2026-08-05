"""Generate a private, browser-local human review view for 1939."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path

import segment


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
  <div id="list"></div>
</aside>
<main id="card"></main>
<script>
const DATA=__PAYLOAD__;
let rows=DATA.rows, selected=0;
const key='daa1939-'+DATA.baseline_sha256;
const saved=JSON.parse(localStorage.getItem(key)||'{}');
for(const r of rows)Object.assign(r.decision,saved[r.record_key]||{});
function e(x){let d=document.createElement('div');d.textContent=x||'';return d.innerHTML}
function persist(){localStorage.setItem(key,JSON.stringify(Object.fromEntries(rows.map(r=>[r.record_key,r.decision]))))}
function showSaved(message){document.querySelector('#save-state').textContent=message}
function setTrack(localId){
  const r=rows[selected], note=`Visuelt spor: parserpost ${localId}. Kræver stadig eksakt Calamari- og rå-OCR-ankring.`;
  r.decision.review_status='menneskeark';
  r.decision.reason=note;
  persist();
  showSaved('✓ Visuelt spor er gemt lokalt.');
  render();
}
function render(){
  const q=document.querySelector('#q').value.toLowerCase();
  const shown=rows.filter(r=>JSON.stringify(r).toLowerCase().includes(q));
  const list=document.querySelector('#list'); list.innerHTML='';
  shown.forEach(r=>{const i=rows.indexOf(r),d=document.createElement('div');d.className='row '+(i===selected?'active':'');d.innerHTML='<b>'+e(r.navn||'(uden navn)')+'</b><br><small>PDF s. '+e(r.sider)+' · '+e(r.lokal_id)+' · '+e(r.decision.review_status)+'</small>';d.onclick=()=>{selected=i;render()};list.append(d)});
  const r=rows[selected]; if(!r)return;
  const candidates=(r.candidates||[]).map(c=>'<section class="candidate"><h4>Parserpost '+e(c.lokal_id||'(uden lokalt id)')+'</h4><p class="muted">PDF s. '+e(c.sider)+' · Calamari-scan '+e(c.calamari_sider)+'</p><p><b>Boksens start og slut er parserens foreslåede postgrænse.</b> Den kan godt omtale flere beslægtede personer.</p><pre>'+e(c.raw_text)+'</pre><button onclick="setTrack('+JSON.stringify(c.lokal_id)+')">Markér som visuelt spor</button></section>').join('')||'<p class="warn">Ingen parserkandidat på samme PDF-side. Lad posten stå urørt eller send den til menneskearket med en begrundelse.</p>';
  document.querySelector('#card').innerHTML='<h1>'+e(r.navn||'(uden navn)')+'</h1><p class="muted">Linje: '+e(r.linje)+' · Nr.: '+e(r.nr)+' · PDF-sider: '+e(r.sider)+' · Lokal id: '+e(r.lokal_id)+'</p><div class="guide"><b>Hvad skal du vurdere?</b> Om én af de viste kandidatposter ser ud til at rumme den relevante kildetekst for den gamle post. Den gamle tekst kan fortsætte ind i nabo-personer; det er ikke i sig selv en fejl. Vælg kun “Markér som visuelt spor”, når kandidaten tydeligt er den rigtige historiske sammenhæng. Det er <em>ikke</em> en endelig accept: en senere maskinel kontrol skal stadig finde de eksakte tekstankre.</div><h3>Gammel kildetekst (arvet, kan være bred)</h3><pre>'+e(r.narrative)+'</pre><h3>Ny OCR: kandidatposter på samme PDF-side</h3>'+candidates+'<h3>Din kladdeafgørelse</h3><label>Status<select id="status"><option value="unreviewed">Ikke gennemgået</option><option value="menneskeark">Menneskeark / kræver ankring</option><option value="eksplicit_dublet">Eksplicit dublet</option></select></label><label>Begrundelse (påkrævet ved menneskeark)<textarea id="reason"></textarea></label><label>Dubletmål: baseline record_key (kun ved eksplicit dublet)<input id="target"></label><p class="warn">Endelig “accepteret” kan ikke vælges her, fordi den kræver fulde, eksakte Calamari- og rå-OCR-ankre. Arket gætter aldrig.</p>';
  const s=document.querySelector('#status'),reason=document.querySelector('#reason'),target=document.querySelector('#target');
  s.value=r.decision.review_status==='accepteret'?'unreviewed':r.decision.review_status;
  reason.value=r.decision.reason||'';target.value=r.decision.duplicate_of_baseline_record_key||'';
  s.onchange=()=>{r.decision.review_status=s.value;persist();showSaved('✓ Status er gemt lokalt.')};
  reason.oninput=()=>{r.decision.reason=reason.value;persist();showSaved('✓ Kladde er gemt lokalt.')};
  target.oninput=()=>{r.decision.duplicate_of_baseline_record_key=target.value;persist();showSaved('✓ Kladde er gemt lokalt.')};
}
function save(){persist();showSaved('✓ Hele kladden er gemt lokalt i browseren.')}
function downloadFile(){const b=new Blob([JSON.stringify({schema_version:1,baseline_sha256:DATA.baseline_sha256,entries:rows.map(r=>r.decision)},null,2)],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='1939-review-kladd.json';a.click()}
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
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
    review = json.loads(args.review.read_text(encoding="utf-8"))
    # The extractor writes its normal artifact and diagnostics to standard
    # streams. This UI generator consumes only its in-memory posts.
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        posts = segment._segment_1939_v2(
            args.calamari.read_text(encoding="utf-8").splitlines(),
            segment.UDGAVE_PROFILER["1939-v2"],
        )
    by_pdf_page: dict[str, list[dict]] = {}
    for post in posts:
        scan_pages = _pages(post.get("sider"))
        pdf_pages = [args.calamari_first_pdf_page + page - 1 for page in scan_pages]
        candidate = {
            "lokal_id": post.get("lokal_id"),
            "sider": _display_span(pdf_pages),
            "calamari_sider": post.get("sider"),
            "raw_text": post.get("raw_text"),
        }
        for page in pdf_pages:
            by_pdf_page.setdefault(str(page), []).append(candidate)
    decisions = {x["baseline_record_key"]: x for x in review["entries"]}
    rows = [
        {
            "record_key": record["record_key"],
            "navn": record.get("navn"),
            "linje": record.get("linje"),
            "nr": record.get("nr_label"),
            "sider": record.get("sider"),
            "lokal_id": record.get("_v2_lokal_id") or record.get("_lokal_id"),
            "usikker": record.get("usikker"),
            "narrative": record.get("narrative"),
            "candidates": sum(
                (by_pdf_page.get(str(page), []) for page in _pages(record.get("sider"))), []
            ),
            "decision": decisions[record["record_key"]],
        }
        for record in records
    ]
    payload = json.dumps(
        {"baseline_sha256": hashlib.sha256(baseline_bytes).hexdigest(), "rows": rows},
        ensure_ascii=False,
    ).replace("</", "<\\/")
    args.out.write_text(HTML.replace("__PAYLOAD__", payload), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
