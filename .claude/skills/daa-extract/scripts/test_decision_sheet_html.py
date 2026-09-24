"""HTML-redigeringsfladen til afgørelsesarket (4.5): kun syntetiske data.

Siden er et redigeringsværktøj oven på token-arket — den eksporterede tekst skal
være `render_sheet`'s tekst med kun D-linjernes token/note udskiftet, så
hash-bindingen og `parse_sheet`/`check_identity` gælder uændret.
"""
import base64
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from decision_sheet_html import build_payload, record_clauses, render_html
from interpretation_decision_sheet import SheetError, check_identity, parse_sheet, render_sheet

HERE = Path(__file__).resolve().parent
JS = HERE / "decision_sheet_html.js"
SCRIPT = str(HERE / "interpretation_decision_sheet.py")
U1 = "11111111-1111-4111-8111-111111111111"
U2 = "22222222-2222-4222-8222-222222222222"
U3 = "33333333-3333-4333-8333-333333333333"
FARLIG = "</script><script>alert(1)</script> <b>x</b>"


def row(uid, key="I-1", pred="person.death", value="1850", text="† 1850", ordinal=1):
    return {"interpretation_id": uid, "version": 1, "record_key": key, "predicate": pred,
            "value_text": value, "confidence": 0.9, "persona_role": "principal",
            "cited": [{"ordinal": ordinal, "text": text, "flags": []}]}


ROWS = [row(U1), row(U2, value="1851", text=FARLIG, ordinal=2),
        row(U3, key="II-2", pred="person.birth")]
PRIOR = {("I-1", "person.death", "1850"): "J"}


def node_export(payload, state):
    node = shutil.which("node")
    assert node, "node mangler — eksporttesten må ikke springes over"
    prog = ("const m=require(process.argv[1]);let s='';process.stdin.on('data',d=>s+=d);"
            "process.stdin.on('end',()=>{const {p,st}=JSON.parse(s);"
            "process.stdout.write(JSON.stringify({sheet:m.exportSheet(p,st),"
            "mangler:m.exportMangler(p,st),init:m.initialState(p)}))});")
    out = subprocess.run([node, "-e", prog, str(JS)], input=json.dumps({"p": payload, "st": state}),
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def test_uaendret_tilstand_eksporterer_render_sheet_byte_for_byte():
    p = build_payload(ROWS, PRIOR, sheet_text=None, mangler_text=None, rows_sha256="ab" * 32)
    res = node_export(p, None)
    assert res["sheet"] == render_sheet(ROWS, PRIOR)


def test_afgoerelser_og_noter_giver_gyldigt_ark_i_arkets_orden():
    p = build_payload(ROWS, PRIOR, sheet_text=None, mangler_text=None, rows_sha256="ab" * 32)
    st = node_export(p, None)["init"]
    st["toks"][U2] = "R"
    st["toks"][U3] = "U"
    st["notes"][U2] = "forkert år\nanden linje\u2028tredje\x85fjerde"
    ark = node_export(p, st)["sheet"]
    beslutninger = parse_sheet(ark)
    check_identity(beslutninger, ROWS)
    assert {d.interpretation_id: d.status for d in beslutninger} == {
        U1: "accepted", U2: "rejected", U3: "unresolved"}
    assert [d.note for d in beslutninger if d.interpretation_id == U2] == [
        "forkert år anden linje tredje fjerde"]
    # kun D-linjerne må afvige fra render_sheet
    foer, efter = render_sheet(ROWS, PRIOR).split("\n"), ark.split("\n")
    assert len(foer) == len(efter)
    assert [i for i, (a, b) in enumerate(zip(foer, efter)) if a != b and not a.startswith("D ")] == []


def test_uafgjort_forbliver_uafgjort_og_stoppes_af_parseren():
    p = build_payload(ROWS, {}, sheet_text=None, mangler_text=None, rows_sha256="ab" * 32)
    with pytest.raises(SheetError, match="SHEET_UNDECIDED"):
        parse_sheet(node_export(p, None)["sheet"])


def test_eksisterende_ark_indlaeses_saa_intet_arbejde_tabes():
    ark = render_sheet(ROWS, PRIOR).replace(f"D {U2} 1 : _", f"D {U2} 1 : R # tjek kilde")
    p = build_payload(ROWS, PRIOR, sheet_text=ark, mangler_text=None, rows_sha256="ab" * 32)
    init = node_export(p, None)["init"]
    assert init["toks"] == {U1: "A", U2: "R", U3: "_"}
    assert init["notes"][U2] == "tjek kilde"


def test_ark_fra_andre_raekker_afvises():
    fremmed = render_sheet([row(U1), row(U2, value="1851", ordinal=2)], PRIOR)
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        build_payload(ROWS, PRIOR, sheet_text=fremmed, mangler_text=None, rows_sha256="ab" * 32)


def test_mangler_rundtur_med_ukendte_linjer_bevaret():
    tekst = "# skabelon\nI-1 fødested mangler\n\nII-2 dåb 1801\nZZ-9 ukendt post\nløs tekst\n"
    p = build_payload(ROWS, PRIOR, sheet_text=None, mangler_text=tekst, rows_sha256="ab" * 32)
    init = node_export(p, None)["init"]
    assert init["mangler"] == {"I-1": "fødested mangler", "II-2": "dåb 1801"}
    assert init["unplaced"] == "ZZ-9 ukendt post\nløs tekst"
    init["mangler"]["I-1"] += "\n  titel  \n"
    ud = node_export(p, init)["mangler"]
    linjer = [l for l in ud.split("\n") if l and not l.startswith("#")]
    assert linjer == ["I-1 fødested mangler", "I-1 titel", "II-2 dåb 1801",
                      "ZZ-9 ukendt post", "løs tekst"]


def test_html_er_selvstaendig_og_data_kan_ikke_bryde_ud():
    p = build_payload(ROWS, PRIOR, sheet_text=None, mangler_text=None, rows_sha256="ab" * 32)
    html = render_html(p)
    assert "</script><script>alert" not in html
    assert not re.search(r"https?://", html)
    assert not re.search(r"<(script|link|img|iframe)[^>]*\ssrc=", html, re.I)
    csp = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', html)[1]
    assert "default-src 'none'" in csp and "unsafe-inline" not in csp.split("style-src")[0]
    kode = re.search(r"<script>(.*?)</script>", html, re.S)[1]
    h = base64.b64encode(hashlib.sha256(kode.encode()).digest()).decode()
    assert f"'sha256-{h}'" in csp
    data = re.search(r'<script type="application/json" id="data">(.*?)</script>', html, re.S)[1]
    assert json.loads(data)["items"][1]["cited"][0]["text"] == FARLIG


def test_cli_html_skriver_0600_og_kun_tal(tmp_path):
    rows = tmp_path / "rows.json"
    rows.write_text(json.dumps(ROWS), encoding="utf-8")
    prior = tmp_path / "prior.json"
    prior.write_text(json.dumps({"\x1f".join(k): v for k, v in PRIOR.items()}), encoding="utf-8")
    ud = tmp_path / "afgoer.html"
    res = subprocess.run([sys.executable, SCRIPT, "html", "--rows", str(rows), "--prior", str(prior),
                          "--out", str(ud)], capture_output=True, text=True)
    assert res.returncode == 0, res.stdout + res.stderr
    assert ud.stat().st_mode & 0o777 == 0o600
    assert "HTML_OK forslag=3 poster=2 afgjort=1" in res.stdout
    assert "1850" not in res.stdout and "†" not in res.stdout


def test_postens_klausuler_er_foreningen_af_citater_med_praedikater():
    navn = {**row(U3, pred="person.name", value="Hans"),
            "cited": [{"ordinal": 1, "text": "† 1850", "flags": []}]}
    doed = {**row(U1), "cited": [{"ordinal": 4, "text": "var død 1353", "flags": ["f"]},
                                 {"ordinal": 1, "text": "† 1850", "flags": []}]}
    rc = record_clauses([doed, navn, row(U2, key="II-2")])
    assert rc["I-1"] == [
        {"ordinal": 1, "text": "† 1850", "flags": [], "predicates": ["person.death", "person.name"]},
        {"ordinal": 4, "text": "var død 1353", "flags": ["f"], "predicates": ["person.death"]}]
    assert [c["ordinal"] for c in rc["II-2"]] == [1]
    p = build_payload([doed, navn], {}, sheet_text=None, mangler_text=None, rows_sha256="ab" * 32)
    assert p["record_clauses"] == {"I-1": rc["I-1"]}


def test_modstridende_klausultekst_i_samme_post_afvises():
    with pytest.raises(SheetError, match="ROWS_CLAUSE_CONFLICT post=I-1 klausul=1"):
        record_clauses([row(U1), row(U2, text="† 1851")])


def test_klausullisten_indsaettes_kun_som_tekst():
    kode = JS.read_text(encoding="utf-8")
    assert ".innerHTML" not in kode and "insertAdjacentHTML" not in kode
    assert "document.write" not in kode
