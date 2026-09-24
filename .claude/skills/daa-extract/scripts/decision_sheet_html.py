"""Lokal HTML-redigeringsflade oven på afgørelsesarket (4.5).

Siden er kun et redigeringsværktøj: den eksporterer det samme token-ark, som
`render_sheet` bygger, med kun D-linjernes token og note udskiftet, og en
`MANGLER.txt` (postens nøgle først, ét udsagn pr. linje). Hash-bindingen og
`parse_sheet`/`check_identity` i `interpretation_decision_sheet.py sql` gælder
derfor uændret.

Filen indeholder kildetekst: den skrives 0600 uden for repoet, åbnes lokalt
(file://), henter intet udefra (CSP `default-src 'none'`, script bundet på hash)
og må aldrig publiceres eller sendes til en model.
"""
from __future__ import annotations

import base64
import hashlib
import json
import re
import unicodedata
from pathlib import Path

from interpretation_decision_sheet import (LINE_RE, SheetError, render_sheet, reviewsignal,
                                           sheet_order)

HERE = Path(__file__).resolve().parent
JS_PATH = HERE / "decision_sheet_html.js"
ANBEFALING = {"J": "A", "N": "R"}


def _read_sheet_tokens(text: str) -> dict[str, tuple[str, str]]:
    """Læs et påbegyndt ark leniently: uafgjorte (`_`) er tilladt her."""
    out = {}
    for raw in text.splitlines():
        m = LINE_RE.match(raw.rstrip())
        if not m:
            continue
        tok = m["tok"] if m["tok"] in ("A", "R", "U") else "_"
        out[m["id"]] = (tok, (m["note"] or "").strip())
    return out


def _read_mangler(text: str, keys: list[str]) -> tuple[dict[str, str], list[str]]:
    """Fordel `MANGLER.txt`-linjer på poster; ukendte linjer bevares ordret."""
    by_len = sorted(keys, key=len, reverse=True)
    placed: dict[str, list[str]] = {}
    unplaced = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key = next((k for k in by_len if line.startswith(k + " ") or line.startswith(k + "\t")),
                   None)
        if key is None:
            unplaced.append(line)
        else:
            placed.setdefault(key, []).append(line[len(key):].strip())
    return {k: "\n".join(v) for k, v in placed.items()}, unplaced


def _ws(s: str) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", s)).strip()


def _loose(s: str) -> str:
    return re.sub(r"[^\w]+", " ", _ws(s).casefold()).strip()


def verbatim(value: str, cited: list[dict]) -> str:
    """Står værdien ordret i de citerede klausuler? Mekanisk hjælp, ikke en afgørelse.

    `ordret`: tegn for tegn (kun blanktegn samlet). `næsten`: kun store/små
    bogstaver eller tegnsætning afviger. `nej`: omskrevet eller ikke til stede.
    """
    tekst = " ".join(c["text"] for c in cited)
    if _ws(value) and _ws(value) in _ws(tekst):
        return "ordret"
    if _loose(value) and _loose(value) in _loose(tekst):
        return "næsten"
    return "nej"


def record_clauses(rows: list[dict]) -> dict[str, list[dict]]:
    """Postens klausuler, som arket kender dem: foreningen af alle forslags citater.

    Rækkefilen bærer kun citerede klausuler, så en klausul, intet forslag citerer,
    findes ikke her. Hver klausul får de prædikater, der citerer den, så fx navnet
    (`person.name`) kan findes fra et kort, der kun citerer en senere klausul.
    """
    out: dict[str, dict[int, dict]] = {}
    for r in rows:
        post = out.setdefault(r["record_key"], {})
        for c in r["cited"]:
            k = post.get(c["ordinal"])
            if k is None:
                k = post[c["ordinal"]] = {"ordinal": c["ordinal"], "text": c["text"],
                                          "flags": list(c["flags"]), "predicates": set()}
            elif (k["text"], k["flags"]) != (c["text"], list(c["flags"])):
                raise SheetError(f"ROWS_CLAUSE_CONFLICT post={r['record_key']} "
                                 f"klausul={c['ordinal']}")
            k["predicates"].add(r["predicate"])
    return {key: [dict(c, predicates=sorted(c["predicates"])) for _, c in sorted(post.items())]
            for key, post in out.items()}


def build_payload(rows: list[dict], prior: dict, *, sheet_text: str | None,
                  mangler_text: str | None, rows_sha256: str) -> dict:
    text = render_sheet(rows, prior)
    lines = text.split("\n")
    d_index = {ln.split(" ")[1]: i for i, ln in enumerate(lines) if ln.startswith("D ")}
    existing = _read_sheet_tokens(sheet_text) if sheet_text is not None else None
    if existing is not None and set(existing) != set(d_index):
        raise SheetError(f"SHEET_IDENTITY_MISMATCH mangler={len(set(d_index) - set(existing))} "
                         f"ekstra={len(set(existing) - set(d_index))}")
    items, posts = [], []
    for r in sheet_order(rows):
        if not posts or posts[-1] != r["record_key"]:
            posts.append(r["record_key"])
        uid = r["interpretation_id"]
        anbefaling = ANBEFALING.get(prior.get((r["record_key"], r["predicate"], r["value_text"])))
        tok, note = existing[uid] if existing is not None else (anbefaling or "_", "")
        items.append({
            "id": uid, "version": r["version"], "line": d_index[uid],
            "record_key": r["record_key"], "predicate": r["predicate"],
            "value": r["value_text"], "confidence": r["confidence"],
            "role": r["persona_role"], "recommendation": anbefaling,
            "signals": reviewsignal(r), "cited": r["cited"],
            "verbatim": verbatim(r["value_text"], r["cited"]),
            "initial_tok": tok, "initial_note": note,
        })
    mangler, unplaced = _read_mangler(mangler_text or "", posts)
    return {"contract": "decision-sheet-html-v1", "rows_sha256": rows_sha256,
            "sheet_lines": lines, "posts": posts, "items": items,
            "record_clauses": record_clauses(rows),
            "mangler": mangler, "unplaced": "\n".join(unplaced)}


def _json_for_script(obj: dict) -> str:
    # `<`, `>` og `&` escapes, så data aldrig kan lukke script-elementet.
    return (json.dumps(obj, ensure_ascii=False)
            .replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
            .replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"))


CSS = """
:root{--bg:#f7f6f3;--card:#fff;--ink:#1d1d1f;--muted:#6b6b70;--line:#e2e0da;--acc:#2f6f4f;
--rej:#a33a2c;--unr:#8a6d1f;--focus:#2b5fb4;--mark:#fff4cc}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--card:#212124;--ink:#ececef;--muted:#9a9aa2;
--line:#34343a;--acc:#5fb48a;--rej:#e07a6c;--unr:#d9b75a;--focus:#7aa7f0;--mark:#3a3420}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);
font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
header{position:sticky;top:0;z-index:5;background:var(--card);border-bottom:1px solid var(--line);
padding:10px 16px;display:flex;flex-wrap:wrap;gap:10px;align-items:center}
header h1{font-size:16px;margin:0 12px 0 0}.stat{font-variant-numeric:tabular-nums;color:var(--muted)}
.bar{flex:1 1 160px;height:8px;background:var(--line);border-radius:4px;overflow:hidden;min-width:120px}
.bar i{display:block;height:100%;background:var(--acc)}
select,button,input,textarea{font:inherit;color:inherit}
button{border:1px solid var(--line);background:var(--card);border-radius:6px;padding:4px 10px;cursor:pointer}
button:disabled{opacity:.45;cursor:not-allowed}button.primary{background:var(--acc);color:#fff;border-color:var(--acc)}
main{max-width:980px;margin:0 auto;padding:16px}
.help{color:var(--muted);font-size:13px;margin:0 0 12px}
.post{background:var(--card);border:1px solid var(--line);border-radius:10px;margin:0 0 16px;padding:12px 14px}
.post h2{font-size:15px;margin:0 0 8px;display:flex;gap:8px;align-items:baseline}
.post h2 small{color:var(--muted);font-weight:400}
.item{border-top:1px solid var(--line);padding:10px 0;display:grid;grid-template-columns:1fr auto;gap:6px 12px}
.item.focus{outline:2px solid var(--focus);outline-offset:4px;border-radius:6px}
.item .head{display:flex;flex-wrap:wrap;gap:6px 10px;align-items:baseline}
.pred{font-family:ui-monospace,Menlo,monospace;font-size:13px;color:var(--muted)}
.val{font-size:17px;font-weight:600;background:var(--mark);padding:0 4px;border-radius:3px}
.tag{font-size:12px;border:1px solid var(--line);border-radius:10px;padding:0 7px;color:var(--muted)}
.tag.warn{border-color:var(--unr);color:var(--unr)}.tag.ok{border-color:var(--acc);color:var(--acc)}
.tag.bad{border-color:var(--rej);color:var(--rej);font-weight:600}
.cited{grid-column:1/-1;margin:2px 0 0;padding:0;list-style:none}
.cited li{font-size:14px;padding:3px 8px;border-left:3px solid var(--line);margin:3px 0;white-space:pre-wrap}
.cited .ord{color:var(--muted);font-variant-numeric:tabular-nums;margin-right:6px}
.cited .flag{color:var(--unr);font-size:12px;margin-left:6px}
.toks{display:flex;gap:4px;align-self:start}.toks button{min-width:38px;font-weight:600}
.toks button[aria-pressed=true][data-t=A]{background:var(--acc);color:#fff;border-color:var(--acc)}
.toks button[aria-pressed=true][data-t=R]{background:var(--rej);color:#fff;border-color:var(--rej)}
.toks button[aria-pressed=true][data-t=U]{background:var(--unr);color:#fff;border-color:var(--unr)}
.note{grid-column:1/-1;width:100%;border:1px solid var(--line);border-radius:6px;padding:4px 8px;background:transparent}
.miss{margin-top:8px}.miss label{font-size:13px;color:var(--muted);display:block;margin-bottom:3px}
textarea{width:100%;min-height:44px;border:1px solid var(--line);border-radius:6px;padding:6px 8px;background:transparent;resize:vertical}
.ctx{margin:0 0 6px}.ctx summary{cursor:pointer;color:var(--muted);font-size:13px}
.ctx .cited li.here{border-left-color:var(--focus)}.ctx .preds{color:var(--muted);font-size:12px;margin-left:6px}
.ctx .gap{color:var(--muted);font-size:12px;border-left-style:dashed}
.hidden{display:none}.diff{font-size:12px;color:var(--rej)}
@media (max-width:640px){.item{grid-template-columns:1fr}.toks{justify-self:start}}
"""


def render_html(payload: dict) -> str:
    js = JS_PATH.read_text(encoding="utf-8")
    js_hash = base64.b64encode(hashlib.sha256(js.encode("utf-8")).digest()).decode()
    csp = (f"default-src 'none'; script-src 'sha256-{js_hash}'; style-src 'unsafe-inline'; "
           "img-src 'none'; form-action 'none'; base-uri 'none'")
    return (
        "<!doctype html>\n<html lang=\"da\"><head><meta charset=\"utf-8\">\n"
        f"<meta http-equiv=\"Content-Security-Policy\" content=\"{csp}\">\n"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
        "<meta name=\"referrer\" content=\"no-referrer\">\n"
        "<title>Afgørelsesark</title>\n"
        f"<style>{CSS}</style></head><body>\n"
        "<noscript>Siden kræver JavaScript.</noscript>\n"
        f"<script type=\"application/json\" id=\"data\">{_json_for_script(payload)}</script>\n"
        f"<script>{js}</script>\n</body></html>\n")
