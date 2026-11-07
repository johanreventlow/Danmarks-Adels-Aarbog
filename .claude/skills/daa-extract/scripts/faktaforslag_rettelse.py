"""Trin 6m del 2: klassifikation af faktaforslag mod bogen og databasen (Task 3).

Ren Python, ingen DB. Input: samlet.json (A), noegle.json og maal-JSON fra faktaforslag_maal.sql.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import unicodedata
from pathlib import Path

import control_model_v2 as cm

_BLANK = re.compile("[ \t\n\r\f\v     ]+")


class FaktaError(Exception):
    def __init__(self, kode: str):
        super().__init__(kode)
        self.kode = kode


def saml_blanktegn(s: str) -> str:
    """Port af private.saml_blanktegn_v1."""
    return _BLANK.sub(" ", s).strip(" ")


def navn_forkortes(gammel: str, ny: str) -> bool:
    """Port af private.navn_forkortes (ICU-lower for ÆØÅ er en kendt begrænsning)."""
    g, n = saml_blanktegn(gammel).lower(), saml_blanktegn(ny).lower()
    return n in g and len(n) < len(g)


def _norm(x: str | None) -> str | None:
    """binding_value_matches: lower(btrim(normalize(x, NFC)))."""
    if x is None:
        return None
    return unicodedata.normalize("NFC", x).strip(" ").lower()


def _rapport(ref, noegle_r, grund, status=None, ny=None):
    return {"ref": ref, "klasse": "RAPPORT", "grund": grund, "interpretation_id": noegle_r["interpretation_id"],
            "version": noegle_r["version"], "status": status, "ny_vaerdi": ny, "assertion_id": None,
            "forventet": None, "p_dato": None, "ret_paastand": False}


def klassificer(a: list[dict], noegle: dict, maal: dict) -> list[dict]:
    forslag = {f["interpretation_id"]: f for f in maal["forslag"]}
    ud = []
    for r in a:
        if r["svar"] == "OK":
            continue
        ref = r["ref"]
        n = noegle[ref]
        iid = n["interpretation_id"]
        f = forslag.get(iid)
        if f is None:
            raise FaktaError("MAAL_MANGLER")
        status = f["status"]
        svar, felt = r["svar"], r["felt"]
        if svar in ("BEGGE", "TVIVL"):
            ud.append(_rapport(ref, n, svar, status))
            continue
        if f["kind"] != "property" or felt.startswith(("relation.", "mention.", "event.")):
            ud.append(_rapport(ref, n, "ikke_property", status))
            continue
        if svar == "FORSLAG_FEJL":
            laes = r.get("bogens_laesning")
            if laes is None or not str(laes).strip():
                ud.append(_rapport(ref, n, "uden_laesning", status))
                continue
            ny = saml_blanktegn(laes)
        elif svar == "DB_FEJL":
            ny = saml_blanktegn(f["value_text"])
        else:
            raise FaktaError("UKENDT_SVAR")

        def rk(klasse, grund=None, assertion_id=None, forventet=None, p_dato=None, ret=False):
            return {"ref": ref, "klasse": klasse, "grund": grund, "interpretation_id": iid,
                    "version": n["version"], "status": status, "ny_vaerdi": ny, "assertion_id": assertion_id,
                    "forventet": forventet, "p_dato": p_dato, "ret_paastand": ret}

        if iid != f["gaeldende_id"]:
            ud.append(rk("DRIFT"))
            continue
        if status == "proposed":
            ud.append(rk("RAPPORT", "UAENDRET") if ny == f["value_text"] else rk("VERSION"))
            continue
        maal_r = f.get("rettelse_maal")
        if not maal_r:
            ud.append(rk("SPAERRET", "intet_maal"))
            continue
        fv = maal_r["forventet"]
        if f.get("maal_bundet_af_anden"):
            ud.append(rk("SPAERRET", "bundet_af_anden"))
            continue
        if felt == "person.name" and navn_forkortes(fv["vaerdi_tekst"], ny):
            ud.append(rk("SPAERRET", "navn_forkortes"))
            continue
        if cm.dato_uden_graenser({"predicate": felt, "value_text": ny}):
            ud.append(rk("SPAERRET", "dato_uden_graenser"))
            continue
        maal_vaerdi = fv["date_raw"] if maal_r.get("value_kind") == "date_raw" else fv["vaerdi_tekst"]
        match = _norm(ny) == _norm(maal_vaerdi) and ny is not None
        aid = maal_r["assertion_id"]
        eb = f.get("egen_binding")
        if match and eb and eb.get("gyldig"):
            ud.append(rk("RAPPORT", "ALLEREDE_BUNDET"))
        elif match:
            ud.append(rk("BIND", assertion_id=aid, forventet=fv))
        else:
            pd = cm._p_dato(ny) if felt in cm.DATE_PREDICATES else None
            ud.append(rk("RET_OG_BIND", assertion_id=aid, forventet=fv, p_dato=pd, ret=True))
    return ud


def manifest_a(klasser: list[dict], a: list[dict]) -> str:
    arow = {r["ref"]: r for r in a}
    rows = []
    for k in sorted(klasser, key=lambda x: x["ref"]):
        r = arow[k["ref"]]
        rows.append({**k, **{x: r.get(x) for x in ("svar", "felt", "vaerdi", "bogens_laesning", "billede")}})
    s = json.dumps(rows, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


# --- Task 4: A-kort og flet -------------------------------------------------------------------------------------

SKABELON = Path(__file__).parent / "faktaforslag_kort.html"
SVARBARE = ("VERSION", "BIND", "RET_OG_BIND")
SAMLET_SIDE = 1001
TOKENS = {"F", "N"}
UDDRAG = 400
STATUS_TEKST = {"rejected": "afvist", "accepted": "accepteret", "proposed": "foreslået"}


def _poster(bidder: list) -> dict:
    return {p["post"]: p for b in bidder for p in b["poster"]}


def byg_kort(klasser: list, samlet: dict, bidder: list, maal: dict) -> list:
    """Kort: oversigt (VERSION/BIND, uden knapper) først, så svarbare RET_OG_BIND, til sidst rapport-rækker."""
    a = {r["ref"]: r for r in samlet["A"]}
    poster = _poster(bidder)
    forslag = {f["interpretation_id"]: f for f in maal["forslag"]}
    kort: list = []
    felter: dict = {}
    for k in klasser:
        if k["klasse"] in ("VERSION", "BIND"):
            felt = a[k["ref"]]["felt"]
            felter[felt] = felter.get(felt, 0) + 1
    if felter:
        kort.append({"type": "oversigt", "antal": sum(felter.values()), "felter": dict(sorted(felter.items())),
                     "svarbar": False})
    for k in sorted(klasser, key=lambda x: x["ref"]):
        r = a[k["ref"]]
        post = poster.get(r.get("post") or k["ref"].rsplit("-", 1)[0])
        if k["klasse"] == "RET_OG_BIND":
            f = forslag.get(k["interpretation_id"]) or {}
            m = f.get("rettelse_maal") or {}
            fv = m.get("forventet") or k.get("forventet") or {}
            db = fv.get("date_raw") if m.get("value_kind") == "date_raw" else fv.get("vaerdi_tekst")
            t = f.get("tidligere") or {}
            status = t.get("status") or k.get("status")
            kort.append({"type": "ret", "svarbar": True, "ref": k["ref"], "felt": r["felt"],
                         "tekst": (post["tekst"][:UDDRAG] if post else ""), "vaerdi": r.get("vaerdi"),
                         "bogens_laesning": k["ny_vaerdi"], "databasen": db,
                         "tidligere_status": status, "tidligere_tekst": STATUS_TEKST.get(status, status),
                         "tidligere_grund": t.get("grund"), "grund": r.get("grund"), "billede": r.get("billede"),
                         "sider": [f"../sider/{s}" for s in (post["sider"] if post else [])]})
        elif k["klasse"] not in SVARBARE:
            kort.append({"type": "rapport", "svarbar": False, "ref": k["ref"], "klasse": k["klasse"],
                         "grund": k["grund"], "felt": r["felt"], "vaerdi": r.get("vaerdi"),
                         "bogens_laesning": r.get("bogens_laesning")})
    return kort


def render(kort: list, manifest_a: str, pr_side: int = 40) -> list:
    tpl = SKABELON.read_text(encoding="utf-8")
    dele = [kort[i:i + pr_side] for i in range(0, len(kort), pr_side)] or [[]]
    sider = []
    for i, del_ in enumerate(dele, 1):
        data = {"manifest_a": manifest_a, "side": i, "sider": len(dele), "kort": del_}
        js = json.dumps(data, ensure_ascii=False).replace("<", "\\u003c").replace("\u2028", "\\u2028") \
            .replace("\u2029", "\\u2029")
        sider.append(tpl.replace("/*__DATA__*/null", js))
    return sider


def samlet_f(klasser: list, manifest_a: str) -> dict:
    return {"manifest_a": manifest_a, "side": SAMLET_SIDE,
            "kilde": "projektejeren 2026-11-07: samlet F på VERSION og BIND",
            "svar": {k["ref"]: "F" for k in sorted(klasser, key=lambda x: x["ref"])
                     if k["klasse"] in ("VERSION", "BIND")}}


def flet_a(klasser: list, manifest_a: str, svarfiler: list) -> str:
    """Fail-closed flet. Side 1001 (samlet F) må kun svare VERSION/BIND; kortfiler kun RET_OG_BIND.
    Arkets rækker sorteres på ref."""
    klasse = {k["ref"]: k["klasse"] for k in klasser}
    svar: dict = {}
    sider: set = set()
    for s in svarfiler:
        if not isinstance(s, dict) or s.get("manifest_a") != manifest_a:
            raise FaktaError("MANIFEST_MISMATCH")
        side = s.get("side")
        if not isinstance(side, int) or isinstance(side, bool) or side < 1:
            raise FaktaError("SVAR_UGYLDIGT")
        if side in sider:
            raise FaktaError("SVAR_SIDE_DUBLET")
        sider.add(side)
        tilladt = ("VERSION", "BIND") if side == SAMLET_SIDE else ("RET_OG_BIND",)
        for ref, tok in (s.get("svar") or {}).items():
            if ref not in klasse:
                raise FaktaError("SVAR_UKENDT_REF")
            if tok in (None, "", "_"):
                continue
            if tok not in TOKENS:
                raise FaktaError("SVAR_UGYLDIGT")
            if klasse[ref] not in tilladt:
                raise FaktaError("SVAR_IKKE_TILLADT")
            if svar.setdefault(ref, tok) != tok:
                raise FaktaError("SVAR_KONFLIKT")
    linjer = [f"# manifest_a {manifest_a}"]
    for ref in sorted(r for r, c in klasse.items() if c in SVARBARE):
        linjer.append(f"A {ref} : {svar.get(ref) or '_'}")
    return "\n".join(linjer) + "\n"


def _skriv(sti: Path, tekst: str) -> str:
    fd = os.open(sti, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(tekst)
    os.chmod(sti, 0o600)
    return hashlib.sha256(tekst.encode("utf-8")).hexdigest()


def _laes(ud: Path):
    samlet = json.loads((ud / "samlet.json").read_text(encoding="utf-8"))
    ak = json.loads((ud / "a-klasser.json").read_text(encoding="utf-8"))
    kl = ak["klasser"]
    if manifest_a(kl, samlet["A"]) != ak["manifest_a"]:
        raise FaktaError("MANIFEST_MISMATCH")
    return samlet, kl, ak["manifest_a"]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    k = sp.add_parser("klassificer")
    k.add_argument("--ud", required=True)
    k.add_argument("--maal", required=True)
    kt = sp.add_parser("kort")
    kt.add_argument("--ud", required=True)
    sf = sp.add_parser("samlet-f")
    sf.add_argument("--ud", required=True)
    fl = sp.add_parser("flet")
    fl.add_argument("--ud", required=True)
    fl.add_argument("svar", nargs="+")
    args = ap.parse_args(argv)
    os.umask(0o077)
    if args.cmd != "klassificer":
        try:
            return _cmd_a(args)
        except FaktaError as e:
            print(f"FF_FEJL {e.kode}", file=sys.stderr)
            return 2
    try:
        d = Path(args.ud)
        samlet = json.loads((d / "samlet.json").read_text(encoding="utf-8"))
        noegle = json.loads((d / "noegle.json").read_text(encoding="utf-8"))
        maal = json.loads(Path(args.maal).read_text(encoding="utf-8"))
        a = samlet["A"]
        kl = klassificer(a, noegle, maal)
        sha = manifest_a(kl, a)
    except FaktaError as e:
        print(f"FF_FEJL {e.kode}", file=sys.stderr)
        return 2
    p = d / "a-klasser.json"
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump({"manifest_a": sha, "klasser": kl}, fh, ensure_ascii=False, indent=1)
    os.chmod(p, 0o600)
    c = {x: sum(1 for r in kl if r["klasse"] == x) for x in ("VERSION", "BIND", "RET_OG_BIND", "SPAERRET", "DRIFT", "RAPPORT")}
    print(f"FF_KLASSE_OK version={c['VERSION']} bind={c['BIND']} ret_og_bind={c['RET_OG_BIND']} "
          f"spaerret={c['SPAERRET']} drift={c['DRIFT']} rapport={c['RAPPORT']} manifest_a={sha[:8]}")
    return 0


def _cmd_a(args) -> int:
    d = Path(args.ud)
    if args.cmd == "flet" and (d / "ark-a.txt").exists():
        raise FaktaError("ARK_FINDES")
    samlet, kl, ma = _laes(d)
    if args.cmd == "kort":
        bidder = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(d.glob("input-*.json"))]
        maal = json.loads((d / "maal.json").read_text(encoding="utf-8"))
        kort = byg_kort(kl, samlet, bidder, maal)
        sider = render(kort, ma)
        m = d / "kort-a"
        m.mkdir(mode=0o700, exist_ok=True)
        for i, s in enumerate(sider, 1):
            _skriv(m / f"kort-{i}.html", s)
        print(f"FF_KORT_OK sider={len(sider)} svarbare={sum(1 for k in kort if k['svarbar'])} "
              f"oversigt={sum(k['antal'] for k in kort if k['type'] == 'oversigt')} "
              f"rapport={sum(1 for k in kort if k['type'] == 'rapport')} manifest_a={ma[:8]}")
    elif args.cmd == "samlet-f":
        sv = samlet_f(kl, ma)
        sha = _skriv(d / "svar-a-1001.json", json.dumps(sv, ensure_ascii=False, indent=1))
        print(f"FF_SAMLET_OK f={len(sv['svar'])} sha256={sha}")
    else:
        ark = flet_a(kl, ma, [json.loads(Path(p).read_text(encoding="utf-8")) for p in args.svar])
        sha = _skriv(d / "ark-a.txt", ark)
        t = [l.rsplit(" ", 1)[1] for l in ark.splitlines()[1:]]
        print(f"FF_FLET_OK f={t.count('F')} n={t.count('N')} ubesvaret={t.count('_')} ark_sha256={sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
