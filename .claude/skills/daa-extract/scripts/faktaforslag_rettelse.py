"""Trin 6m del 2: klassifikation af faktaforslag mod bogen og databasen (Task 3), A-kort og flet (Task 4) og
ceremoniens SQL (Task 5: anvend_a, sql_a, verify_a_sql, CLI `sql`).

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
    oversigt: list = []
    ret: list = []
    rapport: list = []
    felter: dict = {}
    for k in klasser:
        if k["klasse"] in ("VERSION", "BIND"):
            felt = a[k["ref"]]["felt"]
            felter[felt] = felter.get(felt, 0) + 1
    if felter:
        oversigt.append({"type": "oversigt", "antal": sum(felter.values()), "felter": dict(sorted(felter.items())),
                     "svarbar": False})
    for k in sorted(klasser, key=lambda x: x["ref"]):
        r = a[k["ref"]]
        post = poster.get(r.get("post") or k["ref"].rsplit("-", 1)[0])
        if k["klasse"] == "RET_OG_BIND":
            if post is None:
                raise FaktaError("POST_MANGLER")
            f = forslag.get(k["interpretation_id"])
            if f is None or not f.get("tidligere"):
                raise FaktaError("MAAL_MANGLER")
            m = f.get("rettelse_maal") or {}
            fv = m.get("forventet") or k.get("forventet") or {}
            db = fv.get("date_raw") if m.get("value_kind") == "date_raw" else fv.get("vaerdi_tekst")
            t = f["tidligere"]
            status = t.get("status")
            ret.append({"type": "ret", "svarbar": True, "ref": k["ref"], "felt": r["felt"],
                         "tekst": post["tekst"][:UDDRAG], "vaerdi": r.get("vaerdi"),
                         "bogens_laesning": k["ny_vaerdi"], "databasen": db,
                         "tidligere_status": status, "tidligere_tekst": STATUS_TEKST.get(status, status),
                         "tidligere_grund": t.get("grund"), "grund": r.get("grund"), "billede": r.get("billede"),
                         "sider": [f"../sider/{s}" for s in post["sider"]]})
        elif k["klasse"] not in SVARBARE:
            rapport.append({"type": "rapport", "svarbar": False, "ref": k["ref"], "klasse": k["klasse"],
                         "grund": k["grund"], "felt": r["felt"], "vaerdi": r.get("vaerdi"),
                         "bogens_laesning": r.get("bogens_laesning")})
    return oversigt + ret + rapport


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
        sv = s.get("svar") if s.get("svar") is not None else {}
        if not isinstance(sv, dict):
            raise FaktaError("SVAR_UGYLDIGT")
        for ref, tok in sv.items():
            if ref not in klasse:
                raise FaktaError("SVAR_UKENDT_REF")
            if tok is not None and not isinstance(tok, str):
                raise FaktaError("SVAR_UGYLDIGT")
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


# --- Task 5: ceremoniens SQL og verifikation ---------------------------------------------------------------------
#
# apply-a.sql køres fra repo-roden (TARGETS_SCOPED_SQL og filen, den inkluderer, er repo-relative \i som i sql_v2) med
# `psql -X -v actor=<redaktørens auth-uid> -f apply-a.sql`. Én transaktion; en RAISE ruller alt tilbage. Den bærer
# værdier (ny_vaerdi, forventet): 0600 under ~/.private. private.extraction_run har UNIQUE(source_id, run_key), og
# run_key bærer arkets sha: samme ark kan kun anvendes én gang (en genkørsel efter COMMIT afvises af databasen).
# Kilden gives med `sql --source-id`; findes D/maal.json, skal dens source_id være den samme (KILDE_MISMATCH).
# Slutlinjen T6M_APPLY_A_OK ... sha256=<ark_sha256>: arkets sha (filen kan ikke bære sin egen); FF_SQL_OK's sha256
# er apply-a.sql's. Bindingstallene følger maal_trin6c2.sql's gyldighed (alle måltyper), så bindinger_k kan
# sammenlignes med runnerens maal; målingen før første skrivning står i kørslens manifest (foer_bindinger,
# foer_k1_bindinger_hash, foer_bundne_f, k1_source_id), så verify-a.sql ikke behøver input ud over arket.

SVAR_RPC = ("FORSLAG_FEJL", "DB_FEJL")
BILLEDE_RPC = ("bekraefter", "modsiger", "ikke_fundet")
AFGJORT = ("accepted", "rejected", "unresolved")
FORVENTET_NOEGLER = ("fact_id", "faktatype", "vaerdi_tekst", "date_raw", "valgt_assertion_id", "citation_sources")
ARK_HOVED = re.compile(r"# manifest_a ([0-9a-f]{64})")
ARK_LINJE = re.compile(r"A (\S+) : (\S+)")
HEX64 = re.compile(r"[0-9a-f]{64}")
K1_KILDE = 1
TAG = "$t6m_"
NULSTIL = "PERFORM set_config('app.change_set_id','',true);"
FASER = ("version", "bind", "ret_og_bind")


def _er_int(x) -> bool:
    return isinstance(x, int) and not isinstance(x, bool)


def _q(s: str) -> str:
    """SQL-strengliteral (standard_conforming_strings=on): kun ' fordobles."""
    if not isinstance(s, str) or "\x00" in s:
        raise FaktaError("VAERDI_UGYLDIG")
    return "'" + s.replace("'", "''") + "'"


def _id(s) -> str:
    try:
        return cm._uuid(s)
    except (cm.ControlError, TypeError):
        raise FaktaError("ID_UGYLDIG") from None


def _laes_ark(ark_tekst: str) -> tuple[str, dict]:
    linjer = ark_tekst.split("\n")
    if linjer and linjer[-1] == "":
        linjer.pop()
    hoved = ARK_HOVED.fullmatch(linjer[0]) if linjer else None
    if hoved is None:
        raise FaktaError("ARK_UGYLDIGT")
    svar: dict = {}
    for linje in linjer[1:]:
        m = ARK_LINJE.fullmatch(linje)
        if m is None:
            raise FaktaError("ARK_UGYLDIGT")
        ref, tok = m.groups()
        if tok not in ("F", "N", "_"):
            raise FaktaError("SVAR_UGYLDIGT")
        if ref in svar:
            raise FaktaError("SVAR_KONFLIKT")
        svar[ref] = tok
    return hoved.group(1), svar


def _forventet_ok(fv) -> bool:
    return (isinstance(fv, dict) and all(k in fv for k in FORVENTET_NOEGLER) and _er_int(fv["fact_id"])
            and isinstance(fv["faktatype"], str) and (fv["vaerdi_tekst"] is None or isinstance(fv["vaerdi_tekst"], str))
            and (fv["date_raw"] is None or isinstance(fv["date_raw"], str))
            and (fv["valgt_assertion_id"] is None or _er_int(fv["valgt_assertion_id"]))
            and isinstance(fv["citation_sources"], list) and all(_er_int(c) for c in fv["citation_sources"]))


def anvend_a(klasser: list, samlet: dict, noegle: dict, ark_tekst: str) -> dict:
    """Arkets F-rækker, fail-closed. manifest_a genberegnes og skal være arkets; arket skal have præcis én linje pr.
    svarbar ref (som flet_a skriver det). N og _ skrives ikke."""
    a = samlet["A"]
    ma = manifest_a(klasser, a)
    ark_ma, svar = _laes_ark(ark_tekst)
    if ark_ma != ma:
        raise FaktaError("MANIFEST_MISMATCH")
    klasse = {k["ref"]: k for k in klasser}
    for ref in svar:
        if ref not in klasse:
            raise FaktaError("SVAR_UKENDT_REF")
        if klasse[ref]["klasse"] not in SVARBARE:
            raise FaktaError("SVAR_IKKE_TILLADT")
    if set(svar) != {r for r, k in klasse.items() if k["klasse"] in SVARBARE}:
        raise FaktaError("ARK_UGYLDIGT")
    arow = {r["ref"]: r for r in a}
    ud: dict = {f: [] for f in FASER}
    for ref in sorted(svar):
        if svar[ref] != "F":
            continue
        k, r = klasse[ref], arow[ref]
        n = noegle.get(ref) if isinstance(noegle, dict) else None
        if (not isinstance(n, dict) or n.get("interpretation_id") != k["interpretation_id"]
                or n.get("version") != k["version"]):
            raise FaktaError("NOEGLE_MISMATCH")
        _id(k["interpretation_id"])
        if not _er_int(k["version"]) or k["version"] < 1:
            raise FaktaError("KLASSE_UGYLDIG")
        if r.get("svar") not in SVAR_RPC or r.get("billede") not in BILLEDE_RPC:
            raise FaktaError("EVIDENS_UGYLDIG")
        ny = k["ny_vaerdi"]
        if not isinstance(ny, str) or not ny or saml_blanktegn(ny) != ny:
            raise FaktaError("VAERDI_UGYLDIG")
        rk = {"ref": ref, "interpretation_id": k["interpretation_id"], "version": k["version"], "status": k["status"],
              "ny_vaerdi": ny, "felt": r["felt"], "svar": r["svar"], "billede": r["billede"]}
        if k["klasse"] == "VERSION":
            if k["status"] != "proposed":
                raise FaktaError("KLASSE_UGYLDIG")
            ud["version"].append(rk)
            continue
        if k["status"] not in AFGJORT or not _er_int(k["assertion_id"]) or not _forventet_ok(k["forventet"]):
            raise FaktaError("KLASSE_UGYLDIG")
        dato = r["felt"] in cm.DATE_PREDICATES
        rk.update(assertion_id=k["assertion_id"], forventet=k["forventet"], value_kind="date_raw" if dato else "text")
        if k["klasse"] == "BIND":
            ud["bind"].append(rk)
        else:
            if dato != isinstance(k["p_dato"], dict) or (not dato and k["p_dato"] is not None):
                raise FaktaError("KLASSE_UGYLDIG")
            rk["p_dato"] = k["p_dato"]
            ud["ret_og_bind"].append(rk)
    return ud


def rapport_a(klasser: list, samlet: dict, ark_tekst: str) -> list:
    """Alt, der ikke skrives: ikke-svarbare rækker og svarbare med N eller _. Kun ref, klasse, grund, felt og arkets
    svar (None for ikke-svarbare); ingen værdier."""
    _, svar = _laes_ark(ark_tekst)
    felt = {r["ref"]: r.get("felt") for r in samlet["A"]}
    return [{"ref": k["ref"], "klasse": k["klasse"], "grund": k["grund"], "felt": felt.get(k["ref"]),
             "ark": svar.get(k["ref"])}
            for k in sorted(klasser, key=lambda x: x["ref"]) if svar.get(k["ref"]) != "F"]


def _alle(anvendt: dict) -> list:
    return [(fase, r) for fase in FASER for r in anvendt[fase]]


def _kontroller(anvendt: dict, source_id) -> None:
    rows = _alle(anvendt)
    if not rows:
        raise FaktaError("INGEN_F")
    ids = [r["interpretation_id"] for _, r in rows]
    if len(set(ids)) != len(ids):
        raise FaktaError("KLASSE_DUBLET")
    maal = [r["assertion_id"] for f, r in rows if f != "version"]
    if len(set(maal)) != len(maal):
        raise FaktaError("MAAL_DUBLET")
    for f, r in rows:
        _id(r["interpretation_id"])
        if f != "version" and source_id is not None and r["forventet"]["citation_sources"] != [source_id]:
            raise FaktaError("KILDE_AFVIGER")
    blob = json.dumps(anvendt, ensure_ascii=False)
    if TAG in blob:
        raise FaktaError("SQL_TAG_KONFLIKT")


def _bindinger_sql(v_src: str, v_k1: str, ud: str) -> str:
    """maal_trin6c2.sql's bindinger med gyldighed (samme CASE), afgrænset til de to kilder: antal gyldige for v_src og
    k1_bindinger_hash for v_k1 (linjer '<promotion-id>:<true|false>' i uuid-orden)."""
    return ("WITH b AS (SELECT p.id, q.source_id, (CASE p.target_type "
            "WHEN 'assertion' THEN private.assertion_binding_current(p.id) "
            "WHEN 'family' THEN cur.id=p.interpretation_id AND cur.status='accepted' "
            "AND private.relation_binding_state_sha256(p.interpretation_id)=p.evidence->>'state_sha256' "
            "ELSE false END) IS TRUE AS gyldig "
            "FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id "
            "JOIN private.interpretation_current cur ON cur.interpretation_key=q.interpretation_key "
            f"WHERE q.source_id IN ({v_src}, {v_k1})) "
            f"SELECT (SELECT count(*) FROM b WHERE b.source_id={v_src} AND b.gyldig), "
            "encode(sha256(convert_to(coalesce((SELECT string_agg(b.id::text||':'||b.gyldig::text,E'\\n' ORDER BY b.id) "
            f"FROM b WHERE b.source_id={v_k1}),''),'UTF8')),'hex') INTO {ud};")


def _efter_do(anvendt: dict) -> str:
    """Tilstanden efter skrivningen (ejerrollen; læser private.*), både før COMMIT i apply-a.sql og i verify-a.sql.
    Kørslen findes fra F-rækkernes version+1 (ingen ekstra input): alle skal komme fra samme menneske-laesning-v1-kørsel,
    hvis manifest bærer målingen før skrivningen."""
    rows = _alle(anvendt)
    f = [{"id": r["interpretation_id"], "til_version": r["version"] + (1 if fase == "version" else 2),
          "til_status": "proposed" if fase == "version" else "accepted", "ny": r["ny_vaerdi"]} for fase, r in rows]
    m = [[r["interpretation_id"], r["assertion_id"]] for fase, r in rows if fase != "version"]
    ret = [[r["assertion_id"], r["value_kind"], r["ny_vaerdi"]] for r in anvendt["ret_og_bind"]]
    nf, nb, nr = len(rows), len(m), len(ret)
    return "\n".join([
        "DO $t6m_efter$",
        f"DECLARE f jsonb := {cm._jlit(f)}::jsonb;",
        f"        m jsonb := {cm._jlit(m)}::jsonb;",
        f"        rt jsonb := {cm._jlit(ret)}::jsonb;",
        "        v_run uuid; v_run_t text; v_src bigint; v_k1 bigint; mf jsonb; n int; n2 int; nv int; nd int; nr int;",
        "        b_efter bigint; k1_efter text; vejb boolean;",
        "BEGIN",
        # Kørslen: hver F-rækkes version+1 findes, og alle kommer fra én kørsel.
        "  SELECT count(*), count(DISTINCT v.extraction_run_id), min(v.extraction_run_id::text) INTO n, n2, v_run_t",
        "    FROM jsonb_array_elements(f) x JOIN private.interpretation c ON c.id = (x->>'id')::uuid",
        "    JOIN private.interpretation v ON v.interpretation_key = c.interpretation_key AND v.version = c.version + 1;",
        f"  IF n <> {nf} OR n2 <> 1 THEN RAISE EXCEPTION 'T6M_KOERSEL_AFVIGER versioner=% koersler=%', n, n2; END IF;",
        "  v_run := v_run_t::uuid;",
        "  SELECT r.source_id, r.manifest INTO v_src, mf FROM private.extraction_run r",
        "   WHERE r.id = v_run AND r.run_key = 'menneske-laesning-v1:' || (r.manifest->>'ark');",
        "  IF mf IS NULL THEN RAISE EXCEPTION 'T6M_KOERSEL_AFVIGER'; END IF;",
        "  v_k1 := (mf->>'k1_source_id')::bigint;",
        # Versioner (red_ret_forslag) og afgørelser (decide kopierer kørslen) fra kørslen.
        "  SELECT count(*) FILTER (WHERE i.decision_evidence->>'basis' = 'menneske-laesning-v1'),",
        "         count(*) FILTER (WHERE i.decision_evidence->>'basis' = 'kort-6m-a'), count(*)",
        "    INTO nv, nd, n FROM private.interpretation i WHERE i.extraction_run_id = v_run;",
        f"  IF nv <> {nf} OR nd <> {nb} OR n <> {nf + nb} THEN",
        "    RAISE EXCEPTION 'T6M_VERSIONER_AFVIGER versioner=% afgoerelser=% i_alt=%', nv, nd, n; END IF;",
        # Hver nøgles gældende række: version, status og værdi.
        "  SELECT count(*) INTO n FROM jsonb_array_elements(f) x",
        "    JOIN private.interpretation c ON c.id = (x->>'id')::uuid",
        "    JOIN private.interpretation_current cur ON cur.interpretation_key = c.interpretation_key",
        "   WHERE cur.version = (x->>'til_version')::int AND cur.status = x->>'til_status'",
        "     AND (cur.value #>> '{}') = x->>'ny' AND cur.extraction_run_id = v_run;",
        f"  IF n <> {nf} THEN RAISE EXCEPTION 'T6M_TILSTAND_AFVIGER % af {nf}', n; END IF;",
        # Rettelserne: journalrækker fra kørslen og påstandens værdi = ny_vaerdi.
        "  SELECT count(*) INTO nr FROM public.paastand_korrektion k",
        "    JOIN private.interpretation q ON q.id = k.interpretation_id",
        "   WHERE q.extraction_run_id = v_run AND k.grund = 'bogen_har_ret';",
        "  SELECT count(*) INTO n FROM jsonb_array_elements(rt) x JOIN public.assertion a ON a.id = (x->>0)::bigint",
        "   WHERE (CASE x->>1 WHEN 'date_raw' THEN a.date_raw ELSE a.vaerdi_tekst END) = x->>2;",
        f"  IF nr <> {nr} OR n <> {nr} THEN RAISE EXCEPTION 'T6M_RETTELSER_AFVIGER journal=% vaerdi=%', nr, n; END IF;",
        # Bindingerne pr. nøgle: nøglens gyldige binding ligger på netop rækkens påstand, og den er påstandens eneste.
        "  SELECT count(*) INTO n FROM jsonb_array_elements(m) x JOIN private.interpretation c ON c.id = (x->>0)::uuid",
        "   WHERE EXISTS (SELECT 1 FROM private.interpretation_promotion p",
        "                   JOIN private.interpretation q ON q.id = p.interpretation_id",
        "                  WHERE q.interpretation_key = c.interpretation_key AND p.target_type = 'assertion'",
        "                    AND p.target_id = (x->>1)::bigint AND private.assertion_binding_current(p.id))",
        "     AND (SELECT count(*) FROM private.interpretation_promotion p WHERE p.target_type = 'assertion'",
        "           AND p.target_id = (x->>1)::bigint AND private.assertion_binding_current(p.id)) = 1;",
        f"  IF n <> {nb} THEN RAISE EXCEPTION 'T6M_BIND_EFTER_AFVIGER % af {nb}', n; END IF;",
        # Kildens gyldige bindinger og k1-hashen mod målingen før første skrivning.
        "  " + _bindinger_sql("v_src", "v_k1", "b_efter, k1_efter"),
        f"  IF b_efter <> (mf->>'foer_bindinger')::bigint - (mf->>'foer_bundne_f')::bigint + {nb}",
        "     OR k1_efter IS DISTINCT FROM mf->>'foer_k1_bindinger_hash' THEN",
        "    RAISE EXCEPTION 'T6M_BINDINGER_AFVIGER foer=% efter=% k1_uaendret=%', mf->>'foer_bindinger', b_efter,",
        "      k1_efter IS NOT DISTINCT FROM mf->>'foer_k1_bindinger_hash'; END IF;",
        # Vej B (som maal_trin6c2.sql's vejb).
        "  SELECT to_regprocedure('private.binding_value_matches(text,jsonb,text,text)') IS NOT NULL",
        "     AND coalesce((SELECT bool_or(position('binding_value_matches' IN p.prosrc) > 0)",
        "                     FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace",
        "                    WHERE s.nspname = 'public' AND p.proname = 'public_person_facts'), false) INTO vejb;",
        "  IF NOT vejb THEN RAISE EXCEPTION 'T6M_VEJB_MANGLER'; END IF;",
        "  RAISE NOTICE 'T6M_VERIFY_A_OK versioner=% rettelser=% afgoerelser=% bundet=% bindinger_k=% "
        "k1_bindinger_hash=% vejb=t', nv, nr, nd, " + str(nb) + ", b_efter, k1_efter;",
        "END $t6m_efter$;",
    ])


def sql_a(anvendt: dict, *, source_id: int, manifest_a: str, ark_sha256: str, k1_source_id: int = K1_KILDE) -> str:
    """apply-a.sql: én transaktion (READ COMMITTED). Trin (1) aktør, (2) kildeværn + påstandsdrift + måling før,
    (3) kørslen, (4) RPC'erne pr. F-række, (5) binding nøglet på interpretation_key, (6) efterkontrol, (7) COMMIT."""
    if not _er_int(source_id) or not _er_int(k1_source_id):
        raise FaktaError("KILDE_UGYLDIG")
    if not (isinstance(manifest_a, str) and HEX64.fullmatch(manifest_a)
            and isinstance(ark_sha256, str) and HEX64.fullmatch(ark_sha256)):
        raise FaktaError("HASH_UGYLDIG")
    _kontroller(anvendt, source_id)
    rows = _alle(anvendt)
    bindes = [r for fase, r in rows if fase != "version"]
    nf, nb, nr = len(rows), len(bindes), len(anvendt["ret_og_bind"])
    kort = [{"id": r["interpretation_id"], "version": r["version"], "status": r["status"]} for _, r in rows]
    drift = [{"assertion_id": r["assertion_id"], "forventet": r["forventet"]} for r in bindes]
    f_ids = [r["interpretation_id"] for _, r in rows]
    src = source_id

    out = ["\\set ON_ERROR_STOP on", "BEGIN;",
           # Værdier citeres kun ved fordobling af '; backslash er bogstavelig.
           "SET LOCAL standard_conforming_strings=on;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) \\g /dev/null",
           "-- (2) kildeværn: hvert forslag er kildens, gældende og har kortets version og status",
           "DO $t6m_kilde$ DECLARE f jsonb := " + cm._jlit(kort) + "::jsonb; n int; nk int; BEGIN "
           "SELECT count(*) INTO n FROM jsonb_array_elements(f) x "
           "LEFT JOIN private.interpretation i ON i.id = (x->>'id')::uuid "
           f"WHERE i.id IS NULL OR i.source_id IS DISTINCT FROM {src} OR i.version <> (x->>'version')::int "
           "OR i.status IS DISTINCT FROM x->>'status' OR EXISTS (SELECT 1 FROM private.interpretation nv "
           "WHERE nv.interpretation_key = i.interpretation_key AND nv.version > i.version); "
           "SELECT count(DISTINCT i.interpretation_key) INTO nk FROM jsonb_array_elements(f) x "
           "JOIN private.interpretation i ON i.id = (x->>'id')::uuid; "
           f"IF n <> 0 OR nk <> {nf} THEN RAISE EXCEPTION 'FORSLAG_DRIFT kilde={src} afvigende=% noegler=%', n, nk; "
           "END IF; END $t6m_kilde$;"]
    if drift:
        out += ["-- (2) påstandsdrift: målet præcis som kortet viste det (red_ret_paastand's sammenligninger)",
                "DO $t6m_paastand$ DECLARE p jsonb := " + cm._jlit(drift) + "::jsonb; n int; BEGIN "
                "SELECT count(*) INTO n FROM jsonb_array_elements(p) x "
                "LEFT JOIN public.assertion a ON a.id = (x->>'assertion_id')::bigint AND a.target_type = 'fact' "
                "LEFT JOIN public.fact ft ON ft.id = a.target_id AND ft.subjekt_type = 'person' "
                "WHERE ft.id IS NULL "
                "OR (x->'forventet'->>'fact_id')::bigint IS DISTINCT FROM ft.id "
                "OR (x->'forventet'->>'faktatype') IS DISTINCT FROM ft.faktatype "
                "OR (x->'forventet'->>'vaerdi_tekst') IS DISTINCT FROM a.vaerdi_tekst "
                "OR (x->'forventet'->>'date_raw') IS DISTINCT FROM a.date_raw "
                "OR (x->'forventet'->>'valgt_assertion_id')::bigint IS DISTINCT FROM (SELECT c.valgt_assertion_id "
                "FROM public.conclusion c WHERE c.target_type = 'fact' AND c.target_id = ft.id LIMIT 1) "
                "OR ARRAY(SELECT DISTINCT e::bigint FROM jsonb_array_elements_text(x->'forventet'->'citation_sources') e "
                "ORDER BY 1) IS DISTINCT FROM ARRAY(SELECT DISTINCT ci.source_id FROM public.citation ci "
                "WHERE ci.assertion_id = a.id ORDER BY 1); "
                "IF n <> 0 THEN RAISE EXCEPTION 'PAASTAND_DRIFT afvigende=%', n; END IF; END $t6m_paastand$;"]
    manifest = (f"jsonb_build_object('antal', {nf}, 'manifest_a', {_q(manifest_a)}, 'ark', {_q(ark_sha256)}, "
                f"'k1_source_id', {k1_source_id}, 'foer_bindinger', b_foer, 'foer_k1_bindinger_hash', k1_foer, "
                "'foer_bundne_f', n_bund)")
    # R9: foer_bundne_f måles (ikke antages): F-rækker (alle klasser), hvis nøgle nu har en gyldig assertion-binding.
    # Efter skrivningen: kildens gyldige bindinger = før − foer_bundne_f + |bind ∪ ret_og_bind|.
    out += ["-- (2)+(3) måling før første skrivning og kørslen (ejerrollen); målingen gemmes i kørslens manifest",
            "DO $t6m_koersel$ DECLARE a jsonb := " + cm._jlit(f_ids) + "::jsonb; "
            f"v_src bigint := {src}; v_k1 bigint := {k1_source_id}; n_bund int; b_foer bigint; k1_foer text; r uuid; "
            "BEGIN "
            "SELECT count(*) INTO n_bund FROM jsonb_array_elements_text(a) x "
            "JOIN private.interpretation card ON card.id = x::uuid WHERE EXISTS (SELECT 1 "
            "FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id = p.interpretation_id "
            "WHERE q.interpretation_key = card.interpretation_key AND p.target_type = 'assertion' "
            "AND private.assertion_binding_current(p.id)); "
            + _bindinger_sql("v_src", "v_k1", "b_foer, k1_foer") + " "
            "INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,"
            "input_sha256,manifest) VALUES "
            f"(v_src, {_q('menneske-laesning-v1:' + ark_sha256)}, 'menneske-laesning-v1', 'faktaforslag_rettelse.py', "
            f"'kort-6m-a', {_q(manifest_a)}, {manifest}) RETURNING id INTO r; "
            "PERFORM set_config('daa.extraction_run_id', r::text, true); END $t6m_koersel$;",
            "-- (4) pr. F-række: læsningen, så rettelsen, så afgørelsen",
            "SET LOCAL ROLE authenticated;"]
    for i, (fase, r) in enumerate(rows, 1):
        tag = f"$t6m_r{i}$"
        v = r["version"]
        ev = {"basis": "menneske-laesning-v1", "manifest_a_sha256": manifest_a, "ark_sha256": ark_sha256,
              "ref": r["ref"], "svar": r["svar"], "billede": r["billede"]}
        b = [f"DO {tag} DECLARE r jsonb; ny uuid; BEGIN",
             f"  {NULSTIL} r := public.red_ret_forslag({_id(r['interpretation_id'])}, {v}, {_q(r['ny_vaerdi'])}, "
             f"{cm._jlit(ev)}::jsonb);",
             f"  IF (r->>'version')::int IS DISTINCT FROM {v + 1} OR r->>'foer_status' IS DISTINCT FROM "
             f"{_q(r['status'])} THEN RAISE EXCEPTION 'FORSLAG_DRIFT ref=%', {_q(r['ref'])}; END IF;",
             "  ny := (r->>'interpretation_id')::uuid;"]
        if fase == "ret_og_bind":
            dato = "NULL" if r["p_dato"] is None else f"{cm._jlit(r['p_dato'])}::jsonb"
            b.append(f"  {NULSTIL} PERFORM public.red_ret_paastand({int(r['assertion_id'])}, "
                     f"{cm._jlit(r['forventet'])}::jsonb, 'bogen_har_ret', ny, {dato});")
        if fase != "version":
            dev = {"basis": "kort-6m-a", "ref": r["ref"], "ark_sha256": ark_sha256}
            b.append(f"  {NULSTIL} PERFORM public.red_decide_interpretation(ny, {v + 1}, 'accepted', "
                     f"{cm._jlit(dev)}::jsonb);")
        b.append(f"END {tag};")
        out.append("\n".join(b))
    out.append("RESET ROLE;")

    if bindes:
        m = [[r["interpretation_id"], r["assertion_id"]] for r in bindes]
        ids = ",".join(_id(r["interpretation_id"]) for r in bindes)
        out += ["-- (5) binding: målfindingen afgrænset til nøglerne; bevis og mål nøglet på interpretation_key",
                f"SELECT set_config('daa.control_src', '{src}', true) \\g /dev/null",
                cm.ANALYZE_SQL,
                "SELECT set_config('daa.transfer_scope', (SELECT jsonb_agg(interpretation_key::text ORDER BY "
                f"interpretation_key::text COLLATE \"C\") FROM private.interpretation WHERE id IN ({ids}))::text, "
                "true) \\g /dev/null",
                "\\o /dev/null", f"\\i {cm.TARGETS_SCOPED_SQL}", "\\o",
                "DO $t6m_maal$ DECLARE t jsonb := current_setting('daa.targets_scoped')::jsonb; "
                f"m jsonb := {cm._jlit(m)}::jsonb; n int; BEGIN "
                "IF jsonb_array_length(t->'singleton_items') <> 0 OR jsonb_array_length(t->'items') <> "
                "jsonb_array_length(m) THEN RAISE EXCEPTION 'T6M_TARGETS_MISMATCH items=% singletons=% forventet=%', "
                "jsonb_array_length(t->'items'), jsonb_array_length(t->'singleton_items'), jsonb_array_length(m); "
                "END IF; "
                # Kortets række → nøglen → den gældende (accepterede, version+2) række → dens item → rækkens påstand.
                "SELECT count(*) INTO n FROM jsonb_array_elements(m) e "
                "JOIN private.interpretation card ON card.id = (e->>0)::uuid "
                "JOIN private.interpretation_current cur ON cur.interpretation_key = card.interpretation_key "
                "WHERE cur.status = 'accepted' AND cur.version = card.version + 2 AND EXISTS (SELECT 1 FROM "
                "jsonb_array_elements(t->'items') x WHERE (x->>'interpretation_id')::uuid = cur.id "
                "AND x->>'target_type' = 'assertion' AND (x->>'target_id')::bigint = (e->>1)::bigint); "
                "IF n <> jsonb_array_length(m) THEN RAISE EXCEPTION 'T6M_MAAL_MISMATCH % af %', n, "
                "jsonb_array_length(m); END IF; END $t6m_maal$;",
                "SET LOCAL ROLE authenticated;",
                "DO $t6m_bind$ DECLARE items jsonb := current_setting('daa.targets_scoped')::jsonb->'items'; p jsonb; "
                f"BEGIN {NULSTIL} p := public.red_preview_interpretation_promotions(items); "
                "IF jsonb_array_length(p->'items') <> jsonb_array_length(items) OR EXISTS (SELECT 1 FROM "
                "jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE) "
                "THEN RAISE EXCEPTION 'T6M_BIND_NOT_ELIGIBLE %', (SELECT string_agg(DISTINCT coalesce(i->>'reason_code', "
                "'?'), ',') FROM jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE); END IF; "
                f"{NULSTIL} PERFORM public.red_promote_interpretations_batch(items, p->>'preview_hash'); END $t6m_bind$;",
                "RESET ROLE;", cm.ANALYZE_SQL,
                "DO $t6m_bundet$ DECLARE m jsonb := " + cm._jlit(m) + "::jsonb; n int; BEGIN "
                "SELECT count(DISTINCT card.interpretation_key) INTO n FROM jsonb_array_elements(m) e "
                "JOIN private.interpretation card ON card.id = (e->>0)::uuid "
                "JOIN private.interpretation q ON q.interpretation_key = card.interpretation_key "
                "JOIN private.interpretation_promotion pr ON pr.interpretation_id = q.id "
                "WHERE pr.target_type = 'assertion' AND pr.target_id = (e->>1)::bigint "
                "AND private.assertion_binding_current(pr.id); "
                f"IF n <> {nb} THEN RAISE EXCEPTION 'T6M_BIND_COUNT % af {nb}', n; END IF; END $t6m_bundet$;"]
    out += ["-- (6) efterkontrol før COMMIT (ejerrollen): en RAISE ruller hele ceremonien tilbage",
            _efter_do(anvendt),
            "COMMIT;",
            f"\\echo 'T6M_APPLY_A_OK versioner={nf} rettelser={nr} afgoerelser={nb} bundet={nb} sha256={ark_sha256}'"]
    return "\n".join(out) + "\n"


def verify_a_sql(anvendt: dict) -> str:
    """Læse-kun efterkontrol efter COMMIT: samme DO-blok som apply-a.sql's trin (6), med målingen før fra kørslens
    manifest; NOTICE-linjen bærer bindinger_k og k1_bindinger_hash til sammenligning med maal_trin6c2.sql."""
    _kontroller(anvendt, None)
    return "\n".join(["\\set ON_ERROR_STOP on", "BEGIN;", "SET TRANSACTION READ ONLY;", _efter_do(anvendt),
                      "ROLLBACK;"]) + "\n"


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
    sq = sp.add_parser("sql")
    sq.add_argument("--ud", required=True)
    sq.add_argument("--source-id", type=int, required=True)
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
    if args.cmd == "sql" and (d / "apply-a.sql").exists():
        raise FaktaError("SQL_FINDES")
    samlet, kl, ma = _laes(d)
    if args.cmd == "sql":
        return _cmd_sql(d, samlet, kl, ma, args.source_id)
    if args.cmd == "kort":
        bidder = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(d.glob("input-*.json"))]
        if not bidder:
            raise FaktaError("POST_MANGLER")
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


def _cmd_sql(d: Path, samlet: dict, kl: list, ma: str, source_id: int) -> int:
    """sql --ud D --source-id N: D/apply-a.sql, D/verify-a.sql og D/rapport-a.json (0600). Kun antal og en hash ud."""
    if (d / "maal.json").exists():
        if json.loads((d / "maal.json").read_text(encoding="utf-8")).get("source_id") != source_id:
            raise FaktaError("KILDE_MISMATCH")
    noegle = json.loads((d / "noegle.json").read_text(encoding="utf-8"))
    ark_b = (d / "ark-a.txt").read_bytes()
    ark = ark_b.decode("utf-8")
    ark_sha = hashlib.sha256(ark_b).hexdigest()
    an = anvend_a(kl, samlet, noegle, ark)
    apply_sql = sql_a(an, source_id=source_id, manifest_a=ma, ark_sha256=ark_sha)
    verify_sql = verify_a_sql(an)
    rapport = {"manifest_a": ma, "ark_sha256": ark_sha, "rapport": rapport_a(kl, samlet, ark)}
    sha = _skriv(d / "apply-a.sql", apply_sql)
    _skriv(d / "verify-a.sql", verify_sql)
    _skriv(d / "rapport-a.json", json.dumps(rapport, ensure_ascii=False, indent=1))
    print(f"FF_SQL_OK version={len(an['version'])} bind={len(an['bind'])} ret_og_bind={len(an['ret_og_bind'])} "
          f"sha256={sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
