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


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    k = sp.add_parser("klassificer")
    k.add_argument("--ud", required=True)
    k.add_argument("--maal", required=True)
    args = ap.parse_args(argv)
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


if __name__ == "__main__":
    sys.exit(main())
