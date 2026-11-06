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
import re
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

    kort = [{"type": "gruppe", "gruppe": g["gruppe"], "art": g["art"], "billede": g.get("billede"),
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


# --- anvendelse og ceremoniens SQL (Task 6) ---------------------------------------------------------------------

def anvend(bidder: list, noegle: dict, samlet: dict, ark_tekst: str) -> dict:
    """Arket anvendt på postens aktuelle tekst. Forsvar i dybden: manifestet regnes om af samlet og skal være arkets;
    arket skal dække præcis de svarbare rettelser; rettelser findes igen entydigt og uden overlap i den aktuelle tekst,
    hvis sha skal være nøglens. L og K retter læserteksten; K meldes desuden som kildetekst-sag (skrives ikke her)."""
    sha = samlet["manifest_sha256"]
    if mg.manifest(samlet["B"], samlet["grupper_b"]) != sha or mg.grupper_b(samlet["B"]) != samlet["grupper_b"]:
        raise GennemgangError("MANIFEST_MISMATCH")
    ark_sha, svar = laes_ark(ark_tekst)
    if ark_sha != sha:
        raise GennemgangError("MANIFEST_MISMATCH")
    b = {r["ref"]: r for r in samlet["B"]}
    for ref in svar:
        if ref not in b:
            raise GennemgangError("SVAR_UKENDT_REF")
        if not _svarbar(b[ref]):
            raise GennemgangError("SVAR_IKKE_TILLADT")
    if set(svar) != {ref for ref, r in b.items() if _svarbar(r)}:
        raise GennemgangError("SVAR_MANGLER")

    poster = _poster(bidder)
    valgt: dict = {}
    for r in samlet["B"]:
        if svar.get(r["ref"]) in ("L", "K"):
            valgt.setdefault(r["post"], []).append(r)
    ud = {"source_id": None, "poster": [], "k_sager": [], "graense": [], "legacy": [], "kun_rapport": []}
    for post_ref, rettelser in valgt.items():
        n = noegle[post_ref]
        tekst = poster[post_ref]["tekst"]
        if mg._sha(tekst.encode("utf-8")) != n["tekst_sha256"]:
            raise GennemgangError("TEKST_DRIFT")
        if not n["skrivbar"]:
            raise GennemgangError("SVAR_IKKE_TILLADT")
        intervaller = []
        for r in rettelser:
            start = mg._entydig(tekst, r["fra"])
            slut = start + len(r["fra"])
            if (start, slut) != (r["start"], r["slut"]):
                raise GennemgangError("RETTELSE_IKKE_ENTYDIG")
            if any(start < s2 and s1 < slut for s1, s2, _ in intervaller):
                raise GennemgangError("RETTELSE_OVERLAPPER")
            intervaller.append((start, slut, r["til"]))
        efter = tekst
        for start, slut, til in sorted(intervaller, reverse=True):
            efter = efter[:start] + til + efter[slut:]
        ud["source_id"] = n["source_id"]
        ud["poster"].append({"post": post_ref, "record_key": n["record_key"], "person_id": n["person_id"],
                             "state_sha256": n["state_sha256"], "foer_sha256": n["tekst_sha256"],
                             "efter_tekst": efter, "efter_sha256": mg._sha(efter.encode("utf-8")),
                             "rettelser": len(rettelser)})
        for r in rettelser:
            if svar[r["ref"]] == "K":
                ud["k_sager"].append({"ref": r["ref"], "post": post_ref, "record_key": n["record_key"],
                                      "person_id": n["person_id"], "fra": r["fra"], "til": r["til"], "art": r["art"],
                                      "forslag": [noegle[f]["interpretation_id"] for f in r.get("rammer_forslag", [])
                                                  if f in noegle]})
    for r in samlet["B"]:
        n = noegle[r["post"]]
        ud["source_id"] = ud["source_id"] or n["source_id"]
        if r["art"] == "graense":
            ud["graense"].append({"ref": r["ref"], "record_key": n["record_key"]})
        elif r.get("kun_rapport"):
            maal = "legacy" if n.get("legacy_ref") else "kun_rapport"
            ud[maal].append({"ref": r["ref"], "post": r["post"], "record_key": n["record_key"],
                             "person_id": n["person_id"], "narrative_id": n["narrative_id"],
                             "legacy_ref": n.get("legacy_ref"), "fra": r["fra"], "til": r["til"], "art": r["art"]})
    return ud


def _lit(s: str) -> str:
    """SQL-literal under standard_conforming_strings=on: kun ' fordobles; backslash er bogstavelig, ingen E''."""
    if "\x00" in s:
        raise GennemgangError("TEKST_UGYLDIG")
    return "'" + s.replace("'", "''") + "'"


SHA = re.compile(r"^[0-9a-f]{64}$")


def sql_b(anvendt: dict, source_id: int) -> str:
    """Ceremonien i én transaktion: pr. post en revision med eksportens state_sha256 (RPC'en kaster
    NARRATIVE_RECORD_STATE_STALE ved drift, og ON_ERROR_STOP ruller det hele tilbage). Aktør som 6c-2 (`-v actor`)."""
    if not isinstance(source_id, int) or isinstance(source_id, bool):
        raise GennemgangError("KILDE_UGYLDIG")
    ud = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;",
          # RPC'ernes rollegate læser request.jwt.claim.sub (som 6c-2's ceremoni 4).
          "SELECT set_config('request.jwt.claim.sub', :'actor', true) \\g /dev/null",
          "SET LOCAL ROLE authenticated;"]
    for p in anvendt["poster"]:
        if not SHA.match(p["state_sha256"] or ""):
            raise GennemgangError("STATE_SHA_MANGLER")
        ud.append("SELECT set_config('app.change_set_id','',true) \\g /dev/null")
        ud.append(f"SELECT public.red_revider_publiceret_person_narrative_record({int(p['person_id'])}, {source_id}, "
                  f"{_lit(p['record_key'])}, {_lit(p['efter_tekst'])}, {_lit(p['state_sha256'])}) \\g /dev/null")
    ud += ["RESET ROLE;", "COMMIT;"]
    return "\n".join(ud) + "\n"


def verify_b_sql(anvendt: dict) -> str:
    """Læse-kun efterkontrol: hver revideret posts publicerede narrativ har den forventede tekst-sha."""
    src = anvendt["source_id"]
    if not isinstance(src, int) or isinstance(src, bool):
        raise GennemgangError("KILDE_UGYLDIG")
    rk = ", ".join(f"({_lit(p['record_key'])}, {_lit(p['efter_sha256'])})" for p in anvendt["poster"])
    forventet = f"(VALUES {rk})" if rk else "(SELECT NULL::text, NULL::text WHERE false)"
    optalt = " ".join([
        "WITH forventet(record_key, sha) AS " + forventet + ",",
        "faktisk AS (SELECT sr.record_key, encode(extensions.digest(n.tekst, 'sha256'), 'hex') AS sha",
        "FROM private.source_record sr",
        "JOIN private.narrative_record_publication b ON b.source_record_id = sr.id AND b.status = 'published'",
        f"JOIN public.narrative n ON n.id = b.narrative_id WHERE sr.source_id = {src})",
        "SELECT count(*) AS poster, count(*) FILTER (WHERE a.sha = f.sha) AS lig",
        "FROM forventet f LEFT JOIN faktisk a ON a.record_key = f.record_key"])
    return "\n".join([
        "-- Læse-kun efterkontrol af læsertekst-ceremonien (trin 6m del 1). Printer kun antal.",
        "\\set ON_ERROR_STOP on", "BEGIN;", "SET TRANSACTION READ ONLY;",
        f"SELECT format('VERIFY_B poster=%s lig=%s', o.poster, o.lig) FROM ({optalt}) o;",
        # Værnet: en afvigelse fejler kørslen (exit ≠ 0), uafhængigt af klientens NOTICE-niveau.
        f"DO $v$ DECLARE o record; BEGIN SELECT * INTO o FROM ({optalt}) x; IF o.lig <> o.poster THEN "
        "RAISE EXCEPTION 'VERIFY_B_AFVIGER poster=% lig=%', o.poster, o.lig; END IF; END $v$;",
        "ROLLBACK;"]) + "\n"


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


def cmd_sql(a) -> int:
    ud = Path(a.ud)
    filer = ["apply-b.sql", "verify-b.sql", "k-sager.json", "graensefejl.txt", "legacy-sager.json"]
    if any((ud / f).exists() for f in filer):
        raise GennemgangError("SQL_FINDES")
    samlet = mg._laes_json(ud / "samlet.json")
    anvendt = anvend(mg._bidder_i(ud), mg._laes_json(ud / "noegle.json"), samlet,
                     (ud / "ark-b.txt").read_text(encoding="utf-8"))
    src = anvendt["source_id"]
    if not anvendt["poster"]:
        raise GennemgangError("INGEN_RETTELSER")   # intet L/K på arket: ingen ceremoni
    sha = _skriv(ud / "apply-b.sql", sql_b(anvendt, src))
    _skriv(ud / "verify-b.sql", verify_b_sql(anvendt))
    mg._skriv_json(ud / "k-sager.json", anvendt["k_sager"])
    mg._skriv_json(ud / "legacy-sager.json", {"legacy": anvendt["legacy"], "kun_rapport": anvendt["kun_rapport"]})
    _skriv(ud / "graensefejl.txt", "".join(f"GRÆNSEFEJL: {g['ref']} {g['record_key']}\n" for g in anvendt["graense"]))
    print(f"LT_SQL_OK poster={len(anvendt['poster'])} rettelser={sum(p['rettelser'] for p in anvendt['poster'])} "
          f"k_sager={len(anvendt['k_sager'])} graense={len(anvendt['graense'])} legacy={len(anvendt['legacy'])} "
          f"kun_rapport={len(anvendt['kun_rapport'])} sha256={sha}")
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
    s = sub.add_parser("sql")
    s.add_argument("--ud", type=Path, required=True)
    a = ap.parse_args(argv)
    try:
        return {"kort": cmd_kort, "flet": cmd_flet, "sql": cmd_sql}[a.cmd](a)
    except GennemgangError as e:
        print(f"LT_FEJL {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
