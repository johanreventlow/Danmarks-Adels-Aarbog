#!/usr/bin/env python3
"""Rettelse af læserteksten efter modelgennemgangens spor B (trin 6m del 1; spec 2026-11-05 §4.1 B, §4.3).

  kort --ud D            -> D/kort-b/kort-<n>.html: én blok pr. gruppe/post, ikke forudfyldt
  flet --ud D SVAR...    -> D/ark-b.txt: `# manifest <sha256>` + `R <ref> : L|K|N|_` pr. svarbar rettelse

D er modelgennemgangens mappe (`model_gennemgang.py`): input-<k>.json, noegle.json, samlet.json, sider/.
Svar: L = ret læsertekst, K = ret læsertekst og meld kildetekst-sag til del 2, N = afvis, _ = ubesvaret (ingen
handling). Grænserettelser og rettelser på `kun_rapport`-poster er ikke svarbare. Svarfiler og ark er bundet til
samlet.json's `manifest_sha256`. Printer kun antal og hashes; filer skrives 0600.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import model_gennemgang as mg
from model_gennemgang import GennemgangError

KONTEKST = 80
PR_SIDE = 40
TOKENS = {"L", "K", "N"}
SKABELON = Path(__file__).parent / "laesertekst_kort.html"


def _poster(bidder: list) -> dict:
    return {p["post"]: p for b in bidder for p in b["poster"]}


def _svarbar(r: dict) -> bool:
    return r["art"] != "graense" and not r.get("kun_rapport")


def byg_kort(samlet: dict, bidder: list) -> list:
    """Svarbare grupper som `gruppe`-kort; grænserettelser og `kun_rapport`-poster som `rapport`-kort pr. post."""
    poster = _poster(bidder)
    b = {r["ref"]: r for r in samlet["B"]}

    def raekke(r: dict) -> dict:
        p = poster[r["post"]]
        t = p["tekst"]
        return {"ref": r["ref"], "post": r["post"], "foer": t[max(0, r["start"] - KONTEKST):r["start"]],
                "fra": r["fra"], "til": r["til"], "efter": t[r["slut"]:r["slut"] + KONTEKST], "art": r["art"],
                "billede": r["billede"], "grund": r.get("grund"), "rammer_forslag": len(r.get("rammer_forslag") or []),
                "sider": [f"../sider/{s}" for s in p["sider"]], "svarbar": _svarbar(r)}

    kort = [{"type": "gruppe", "gruppe": g["gruppe"], "art": g["art"],
             "elementer": [raekke(b[ref]) for ref in g["elementer"]]} for g in samlet["grupper_b"]]
    rapport: dict = {}
    for r in samlet["B"]:
        if not _svarbar(r):
            grund = "graense" if r["art"] == "graense" else "kun_rapport"
            rapport.setdefault((r["post"], grund), []).append(raekke(r))
    kort += [{"type": "rapport", "post": post, "grund": grund, "elementer": el}
             for (post, grund), el in rapport.items()]
    return kort


def render(kort: list, manifest_sha256: str, pr_side: int = PR_SIDE, udgave: str | None = None) -> list:
    tpl = SKABELON.read_text(encoding="utf-8")
    dele = [kort[i:i + pr_side] for i in range(0, len(kort), pr_side)] or [[]]
    sider = []
    for i, del_ in enumerate(dele, 1):
        data = {"manifest_sha256": manifest_sha256, "udgave": udgave, "side": i, "sider": len(dele), "kort": del_}
        # `<` som \u003c (gyldig JSON): hverken `</script>` eller `<!--` kan åbne noget i siden (som persona_kort).
        js = json.dumps(data, ensure_ascii=False).replace("<", "\\u003c").replace("\u2028", "\\u2028") \
            .replace("\u2029", "\\u2029")
        sider.append(tpl.replace("/*__DATA__*/null", js))
    return sider


def flet_b(manifest: dict, svarfiler: list) -> str:
    """Projektejerens svarfiler → ark. `manifest` er samlet.json. Fail-closed: forbudte, ukendte og modstridende
    svar afvises (Codex #6). Et elements eget svar går forud for gruppens."""
    sha = manifest["manifest_sha256"]
    b = {r["ref"]: r for r in manifest["B"]}
    grupper = {g["gruppe"]: g for g in manifest["grupper_b"]}
    g_svar: dict = {}
    e_svar: dict = {}
    for s in svarfiler:
        if not isinstance(s, dict) or s.get("manifest_sha256") != sha:
            raise GennemgangError("MANIFEST_MISMATCH")
        sv = s.get("svar") or {}
        for kilde, maal, kendte in ((sv.get("grupper") or {}, g_svar, grupper), (sv.get("elementer") or {}, e_svar, b)):
            for ref, tok in kilde.items():
                if ref not in kendte:
                    raise GennemgangError("SVAR_UKENDT_REF")
                if tok in (None, "", "_"):
                    continue
                if tok not in TOKENS:
                    raise GennemgangError("SVAR_UGYLDIGT")
                if kendte is b and not _svarbar(b[ref]):
                    raise GennemgangError("SVAR_IKKE_TILLADT")
                if maal.setdefault(ref, tok) != tok:
                    raise GennemgangError("SVAR_KONFLIKT")
    gruppe_af = {ref: g["gruppe"] for g in manifest["grupper_b"] for ref in g["elementer"]}
    linjer = [f"# manifest {sha}"]
    for r in manifest["B"]:
        if _svarbar(r):
            linjer.append(f"R {r['ref']} : {e_svar.get(r['ref']) or g_svar.get(gruppe_af.get(r['ref'])) or '_'}")
    return "\n".join(linjer) + "\n"


def laes_ark(tekst: str) -> tuple:
    """(manifest_sha256, {ref: token}) fra et ark; afviser alt andet end arkets egen form."""
    linjer = tekst.splitlines()
    if not linjer or not linjer[0].startswith("# manifest "):
        raise GennemgangError("ARK_UGYLDIGT")
    svar: dict = {}
    for l in linjer[1:]:
        dele = l.split(" ")
        if len(dele) != 4 or dele[0] != "R" or dele[2] != ":" or dele[3] not in TOKENS | {"_"}:
            raise GennemgangError("ARK_UGYLDIGT")
        if dele[1] in svar:
            raise GennemgangError("SVAR_DUBLET")
        svar[dele[1]] = dele[3]
    return linjer[0][len("# manifest "):], svar


def _skriv(sti: Path, tekst: str) -> str:
    sti.write_text(tekst, encoding="utf-8")
    os.chmod(sti, 0o600)
    return mg._sha(tekst.encode("utf-8"))


def cmd_kort(a) -> int:
    ud = Path(a.ud)
    samlet = mg._laes_json(ud / "samlet.json")
    bidder = mg._bidder_i(ud)
    kort = byg_kort(samlet, bidder)
    sider = render(kort, samlet["manifest_sha256"], udgave=bidder[0].get("udgave"))
    mappe = ud / "kort-b"
    mappe.mkdir(mode=0o700, exist_ok=True)
    for i, s in enumerate(sider, 1):
        _skriv(mappe / f"kort-{i}.html", s)
    el = [e for k in kort for e in k["elementer"]]
    print(f"LT_KORT_OK sider={len(sider)} grupper={sum(1 for k in kort if k['type'] == 'gruppe')} "
          f"svarbare={sum(1 for e in el if e['svarbar'])} rapport={sum(1 for e in el if not e['svarbar'])} "
          f"manifest={samlet['manifest_sha256'][:8]}")
    return 0


def cmd_flet(a) -> int:
    ud = Path(a.ud)
    if (ud / "ark-b.txt").exists():
        raise GennemgangError("ARK_FINDES")
    samlet = mg._laes_json(ud / "samlet.json")
    ark = flet_b(samlet, [mg._laes_json(p) for p in a.svar])
    sha = _skriv(ud / "ark-b.txt", ark)
    t = list(laes_ark(ark)[1].values())
    print(f"LT_FLET_OK L={t.count('L')} K={t.count('K')} N={t.count('N')} ubesvaret={t.count('_')} ark_sha256={sha}")
    return 0


def main(argv: list | None = None) -> int:
    os.umask(0o077)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    k = sub.add_parser("kort")
    k.add_argument("--ud", type=Path, required=True)
    f = sub.add_parser("flet")
    f.add_argument("--ud", type=Path, required=True)
    f.add_argument("svar", type=Path, nargs="+")
    a = ap.parse_args(argv)
    try:
        return {"kort": cmd_kort, "flet": cmd_flet}[a.cmd](a)
    except GennemgangError as e:
        print(f"LT_FEJL {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
