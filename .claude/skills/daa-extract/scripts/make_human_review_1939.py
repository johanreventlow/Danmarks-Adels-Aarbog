"""Generate a private, browser-local human review view for 1939."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


HTML = """<!doctype html><meta charset="utf-8"><title>1939 menneskeark</title>
<style>body{font:15px system-ui;margin:0;display:grid;grid-template-columns:360px 1fr;height:100vh}aside{border-right:1px solid #ccc;padding:12px;overflow:auto}main{padding:24px;overflow:auto}input,select,textarea,button{font:inherit;padding:7px;margin:4px 0;width:100%;box-sizing:border-box}textarea{min-height:80px}.row{padding:8px;border-bottom:1px solid #ddd;cursor:pointer}.active{background:#dceeff}pre{white-space:pre-wrap;background:#f5f5f5;padding:12px}.warn{color:#8b4b00;font-weight:600}small{color:#555}</style>
<aside><h2>1939 menneskeark</h2><p>Du reviewer en <b>historisk kildepost</b>, ikke en databaseperson.</p><p>Gem gemmer kun lokalt i browseren. Eksport henter en privat JSON-kopi; intet sendes eller overskrives.</p><input id="q" placeholder="Søg navn, side, linje eller id"><button onclick="save()">Gem kladde lokalt</button><button onclick="downloadFile()">Eksportér kladde</button><div id="list"></div></aside>
<main id="card"></main><script>const DATA=__PAYLOAD__;let rows=DATA.rows,selected=0,key='daa1939-'+DATA.baseline_sha256,saved=JSON.parse(localStorage.getItem(key)||'{}');for(const r of rows)Object.assign(r.decision,saved[r.record_key]||{});function e(x){let d=document.createElement('div');d.textContent=x||'';return d.innerHTML}function render(){let q=document.querySelector('#q').value.toLowerCase(),shown=rows.filter(r=>JSON.stringify(r).toLowerCase().includes(q)),list=document.querySelector('#list');list.innerHTML='';shown.forEach(r=>{let i=rows.indexOf(r),d=document.createElement('div');d.className='row '+(i===selected?'active':'');d.innerHTML='<b>'+e(r.navn||'(uden navn)')+'</b><br><small>'+e(r.sider)+' · '+e(r.lokal_id)+' · '+e(r.decision.review_status)+'</small>';d.onclick=()=>{selected=i;render()};list.append(d)});let r=rows[selected];if(!r)return;document.querySelector('#card').innerHTML='<h1>'+e(r.navn||'(uden navn)')+'</h1><p><b>Hvad vurderer du?</b> Om denne historiske post kan få en positiv kildebro. Uden sikker bro: vælg menneskeark og skriv hvorfor.</p><p>Linje: '+e(r.linje)+' · Nr.: '+e(r.nr)+' · Sider: '+e(r.sider)+' · Lokal id: '+e(r.lokal_id)+(r.usikker?' <span class=\"warn\">Usikker kildepost</span>':'')+'</p><h3>Kildetekst</h3><pre>'+e(r.narrative)+'</pre><h3>Din afgørelse</h3><label>Status<select id=\"status\"><option>unreviewed</option><option>accepteret</option><option>eksplicit_dublet</option><option>menneskeark</option></select></label><label>Begrundelse<textarea id=\"reason\"></textarea></label><label>Dubletmål record_key<input id=\"target\"></label><p class=\"warn\">Accepteret kræver senere eksakte Calamari-, PDF- og rå-OCR-ankre; der må ikke gættes.</p>';let s=document.querySelector('#status'),reason=document.querySelector('#reason'),target=document.querySelector('#target');s.value=r.decision.review_status;reason.value=r.decision.reason||'';target.value=r.decision.duplicate_of_baseline_record_key||'';s.onchange=()=>r.decision.review_status=s.value;reason.oninput=()=>r.decision.reason=reason.value;target.oninput=()=>r.decision.duplicate_of_baseline_record_key=target.value}function save(){localStorage.setItem(key,JSON.stringify(Object.fromEntries(rows.map(r=>[r.record_key,r.decision]))));alert('Gemt lokalt i browseren.')}function downloadFile(){let b=new Blob([JSON.stringify({schema_version:1,baseline_sha256:DATA.baseline_sha256,entries:rows.map(r=>r.decision)},null,2)],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='1939-review-kladd.json';a.click()}document.querySelector('#q').oninput=render;render()</script>"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        raise FileExistsError(args.out)
    baseline_bytes = args.baseline.read_bytes()
    records = json.loads(baseline_bytes)
    review = json.loads(args.review.read_text(encoding="utf-8"))
    decisions = {x["baseline_record_key"]: x for x in review["entries"]}
    rows = [{"record_key": x["record_key"], "navn": x.get("navn"), "linje": x.get("linje"), "nr": x.get("nr_label"), "sider": x.get("sider"), "lokal_id": x.get("_v2_lokal_id") or x.get("_lokal_id"), "usikker": x.get("usikker"), "narrative": x.get("narrative"), "decision": decisions[x["record_key"]]} for x in records]
    payload = json.dumps({"baseline_sha256": hashlib.sha256(baseline_bytes).hexdigest(), "rows": rows}, ensure_ascii=False).replace("</", "<\\/")
    args.out.write_text(HTML.replace("__PAYLOAD__", payload), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
