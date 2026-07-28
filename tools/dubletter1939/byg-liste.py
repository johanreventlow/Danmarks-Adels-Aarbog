#!/usr/bin/env python3
"""Byg parvis dublet-kandidatliste for DAA 1939 (source 3).

Baggrund: docs/reviews/dubletter-1939-2026-07-27.md. Dubletterne stammer fra
LLM-udtraekket, ikke fra indlaesningen — dels oversigts-/prosaomtaler der blev
til selvstaendige poster (klasse A), dels vinduesoverlap (klasse B).

Fire uafhaengige detektorer forenes, saa et par der kun fanges af én stadig
kommer med. Scriptet TRAEFFER INGEN AFGOERELSER — det producerer en liste til
manuel gennemgang, med anbefalet bevaring og eksplicitte advarsler.

Kør:
  python3 tools/dubletter1939/byg-liste.py \
      --dump work_1939_stamtavle/prod_dump_1939_<dato>.json \
      --linked work_1939_stamtavle/linked_clean.json \
      --ud work_1939_stamtavle/dubletkandidater-<dato>

Skriver <ud>.json (maskinlaesbar) og <ud>.md (til gennemgang).
Begge output ligger i work_1939_stamtavle/ = gitignoreret (PII, invariant 8).
"""
import argparse
import json
import re
import sys
import unicodedata
from collections import defaultdict
from difflib import SequenceMatcher
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[2] / ".claude/skills/daa-extract/scripts"

# _ctx.gruppe-etiketter som modellen selv satte paa poster udtrukket af
# loebende prosa/oversigtslister — den staerkeste klasse-A-markoer vi har.
KAEDE = re.compile(r"kæde", re.I)
OVERSIGT = re.compile(r"^[IVXA-B)\-]+ \(")

AAR = re.compile(r"1[0-9]{3}")
NAVNESTOEJ = re.compile(
    r"\b(greve|grevinde|comtesse|baron|friherre|hr|fru|frk|geheimeraad|"
    r"geheimekonferensraad|overhofmester|storkansler|major|oberst|kaptajn|"
    r"til|og|af|von|van|de|den|det)\b", re.I)


def normaliser(navn):
    """Fornavn uden titler, diakritika og OCR-stoej. Tomt hvis intet tilbage."""
    if not navn:
        return ""
    s = unicodedata.normalize("NFKD", navn.lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = NAVNESTOEJ.sub(" ", s)
    s = re.sub(r"[^a-z ]+", " ", s)
    dele = [d for d in s.split() if len(d) > 1]
    return dele[0] if dele else ""


def aar(tekst):
    m = AAR.search(tekst or "")
    return m.group(0) if m else None


def navnelighed(a, b):
    """OCR-tolerant: 'dittev' vs 'ditlev' skal matche, 'ditlev' vs 'detlev' ogsaa."""
    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b).ratio()


def laes_ctx(linked_path):
    """nr -> (_ctx.gruppe, _window). nr rekonstrueres med converterens egen
    gruppe-blokvise nummerering, saa nøglerummet er identisk med prod's."""
    sys.path.insert(0, str(SCRIPTS))
    import convert_1939_stamtavle as C  # noqa: E402

    recs = json.loads(Path(linked_path).read_text(encoding="utf-8"))
    nr, ud = 0, {}
    for unit in C.build_units(recs):
        for rec in unit:
            nr += 1
            ctx = rec.get("_ctx") or {}
            ud[nr] = {
                "gruppe": str(ctx.get("gruppe") or ""),
                "linje": str(ctx.get("linje") or ""),
                "window": rec.get("_window"),
            }
    return ud


def er_omtale(ctx):
    """Klasse A: posten er udtrukket af loebende prosa, ikke af en nummereret post."""
    g = ctx.get("gruppe", "")
    return bool(KAEDE.search(g) or OVERSIGT.match(g))


def fuldstaendighed(p):
    """Hvilken af to raekker beskriver personen bedst. Bevidst grov — den skal
    kun rangere to naesten-identiske raekker, ikke maale kvalitet absolut."""
    return (len(p.get("narrativ") or ""), p.get("fakta", 0), p.get("fm_kanter", 0))


def kilde_matches(p):
    """samme_som-modparter i DAA 2018-20 (source 1)."""
    return {m["andet_id"] for m in (p.get("matches") or []) if m.get("andet_source") == 1}


def modstridende_aar(a, b):
    """Hard veto: to poster med KENDTE men forskellige foedsels- eller doedsaar
    er forskellige personer. Fanger aegte navnefaeller (Hedevig Ida f. 1750 vs
    f. 1760) som ellers passerer alle fire detektorer."""
    for felt in ("foedt", "doed"):
        xa, xb = aar(a.get(felt)), aar(b.get(felt))
        if xa and xb and xa != xb:
            return f"{felt}saar {xa} ≠ {xb}"
    return None


def find_par(poster, ctx_af_nr):
    """Fire detektorer -> dict[(nr_lav, nr_hoej)] = set(detektornavne)."""
    par = defaultdict(set)
    af_nr = {p["nr"]: p for p in poster}

    def tilfoej(a, b, hvorfra):
        par[(min(a, b), max(a, b))].add(hvorfra)

    # 1) identisk normaliseret narrativ. Navnekravet er ufravigeligt: gruppe-
    #    fallback gav flere SOESKENDE samme narrativ (Godske/Augustinus/Volrad),
    #    og de er reelle personer med forkert prosa — ikke dubletter.
    ens = defaultdict(list)
    for p in poster:
        t = (p.get("narrativ") or "").strip().lower()
        if len(t) > 25:
            ens[t].append(p["nr"])
    for nrs in ens.values():
        for i, a in enumerate(nrs):
            for b in nrs[i + 1:]:
                if navnelighed(normaliser(af_nr[a]["navn"]),
                               normaliser(af_nr[b]["navn"])) >= 0.75:
                    tilfoej(a, b, "identisk-narrativ")

    # 2) fornavn + doedsaar
    doed = defaultdict(list)
    for p in poster:
        f, d = normaliser(p["navn"]), aar(p.get("doed"))
        if f and d:
            doed[(f, d)].append(p["nr"])
    for nrs in doed.values():
        for i, a in enumerate(nrs):
            for b in nrs[i + 1:]:
                tilfoej(a, b, "navn+doedsaar")

    # 3) samme_som-komponent med to 1939-poster (brugerens eget matcharbejde)
    id2nr = {p["id"]: p["nr"] for p in poster}
    naboer = defaultdict(set)
    for p in poster:
        for m in p.get("matches") or []:
            naboer[p["id"]].add(m["andet_id"])
            naboer[m["andet_id"]].add(p["id"])
    set_id, komponenter = set(), []
    for start in list(naboer):
        if start in set_id:
            continue
        stak, komp = [start], []
        set_id.add(start)
        while stak:
            n = stak.pop()
            komp.append(n)
            for m in naboer[n]:
                if m not in set_id:
                    set_id.add(m)
                    stak.append(m)
        komponenter.append(komp)
    for komp in komponenter:
        egne = sorted(id2nr[i] for i in komp if i in id2nr)
        for i, a in enumerate(egne):
            for b in egne[i + 1:]:
                tilfoej(a, b, "samme_som-komponent")

    # 4) omtale-post (klasse A) mod navnelig post med samme foedsels- ELLER doedsaar.
    #    Kun omtaler soeges — ellers eksploderer listen i aegte navnefaeller.
    omtaler = [p for p in poster if er_omtale(ctx_af_nr.get(p["nr"], {}))]
    for o in omtaler:
        fo, fa, da = normaliser(o["navn"]), aar(o.get("foedt")), aar(o.get("doed"))
        if not fo:
            continue
        for p in poster:
            if p["nr"] == o["nr"]:
                continue
            if navnelighed(fo, normaliser(p["navn"])) < 0.75:
                continue
            if (fa and fa == aar(p.get("foedt"))) or (da and da == aar(p.get("doed"))):
                tilfoej(o["nr"], p["nr"], "omtale+aar")

    return par, af_nr


def bedoem(a, b, ctx_af_nr):
    """Klasse, anbefalet bevaring og advarsler for ét par."""
    ca, cb = ctx_af_nr.get(a["nr"], {}), ctx_af_nr.get(b["nr"], {})
    oa, ob = er_omtale(ca), er_omtale(cb)

    if oa and ob:
        # Begge er prosaomtaler => den rigtige post er en TREDJE raekke (eller
        # findes slet ikke). Ingen af de to boer beholdes paa dette grundlag.
        klasse = "AA"
        behold, fjern = ((a, b) if fuldstaendighed(a) >= fuldstaendighed(b) else (b, a))
        begrundelse = ("BEGGE er oversigts-/prosaomtaler — den rigtige post er en tredje række. "
                       "Behold/Fjern nedenfor er IKKE en anbefaling; find den rigtige post først")
    elif oa != ob:
        klasse = "A"  # omtale + rigtig post
        behold, fjern = (b, a) if oa else (a, b)
        begrundelse = "den rigtige post beholdes; modparten er en oversigts-/prosaomtale"
    else:
        klasse = "B" if ca.get("window") != cb.get("window") else "B?"
        behold, fjern = (a, b) if fuldstaendighed(a) >= fuldstaendighed(b) else (b, a)
        begrundelse = ("begge er nummererede poster — den fyldigste beholdes "
                       "(narrativlaengde, fakta, kanter). Afgør IKKE paa nr")

    advarsler = []
    if klasse == "AA":
        advarsler.append("begge parter er prosaomtaler — slet ikke ud fra denne række alene")
    ma, mb = kilde_matches(a), kilde_matches(b)
    if ma and mb and not (ma & mb):
        advarsler.append(
            f"matchet til FORSKELLIGE 2018-20-personer ({sorted(ma)} vs {sorted(mb)}) — "
            "enten er de to reelt forskellige personer, eller 2018-20 har selv en dublet. "
            "Behandl ikke som bekraeftet dublet")
    if kilde_matches(fjern) and not kilde_matches(behold):
        advarsler.append("den der fjernes er ENESTE bro til 2018-20 — flyt matchet foerst")
    if fjern.get("fm_kanter"):
        advarsler.append(f"{fjern['fm_kanter']} family_member-kant(er) skal flyttes foerst")
    if not fjern.get("staged"):
        advarsler.append("den der fjernes er PUBLICERET (staged=false) — offentlig visning aendres")
    if fuldstaendighed(fjern) > fuldstaendighed(behold):
        advarsler.append("den der fjernes er den fyldigste — kontrollér valget mod bogen")
    return klasse, behold, fjern, begrundelse, advarsler


def uddrag(p, n=260):
    t = p.get("narrativ") or ""
    return (t[:n] + "…") if len(t) > n else (t or "(intet narrativ)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", required=True, help="JSON-dump af source 3 fra prod")
    ap.add_argument("--linked", required=True, help="linked_clean.json (udtraeks-artefaktet)")
    ap.add_argument("--ud", required=True, help="output-sti uden endelse")
    a = ap.parse_args()

    poster = json.loads(Path(a.dump).read_text(encoding="utf-8"))
    ctx_af_nr = laes_ctx(a.linked)
    par, af_nr = find_par(poster, ctx_af_nr)

    # En omtale der passer paa flere poster er ikke opløst — markeres, droppes ikke.
    flertydige = defaultdict(set)
    for (na, nb), hvorfra in par.items():
        if "omtale+aar" in hvorfra:
            flertydige[na].add(nb)
            flertydige[nb].add(na)

    raekker, afviste, sprunget_levende = [], [], 0
    for (na, nb), hvorfra in par.items():
        pa, pb = af_nr[na], af_nr[nb]
        if pa.get("levende") or pb.get("levende"):
            sprunget_levende += 1  # PII: levende personer holdes ude af listen
            continue
        strid = modstridende_aar(pa, pb)
        if strid:
            afviste.append({"par": [na, nb], "detektorer": sorted(hvorfra), "grund": strid,
                            "navne": [pa["navn"], pb["navn"]]})
            continue
        klasse, behold, fjern, begrundelse, advarsler = bedoem(pa, pb, ctx_af_nr)
        for nr in (na, nb):
            andre = sorted(flertydige.get(nr, set()) - {na, nb})
            if andre:
                advarsler.append(
                    f"nr {nr} passer ogsaa paa nr {andre} — flertydig, afgør hvilken der er den rigtige")
        raekker.append({
            "detektorer": sorted(hvorfra),
            "styrke": len(hvorfra),
            "klasse": klasse,
            "behold": behold["nr"], "behold_id": behold["id"],
            "fjern": fjern["nr"], "fjern_id": fjern["id"],
            "begrundelse": begrundelse,
            "advarsler": advarsler,
            "poster": {
                str(p["nr"]): {
                    "id": p["id"], "navn": p["navn"], "foedt": p["foedt"], "doed": p["doed"],
                    # Sidetal fra citationen — så hvert par kan slås op i bogen uden at lede.
                    "side": p.get("side"),
                    "fakta": p["fakta"], "fm_kanter": p["fm_kanter"], "staged": p["staged"],
                    "narrativ": p["narrativ"],
                    "ctx_gruppe": ctx_af_nr.get(p["nr"], {}).get("gruppe"),
                    "window": ctx_af_nr.get(p["nr"], {}).get("window"),
                    "matches": p["matches"],
                } for p in (behold, fjern)
            },
        })

    raekker.sort(key=lambda r: (-r["styrke"], r["klasse"], r["behold"]))
    Path(a.ud + ".json").write_text(
        json.dumps({"kandidater": raekker, "afviste": afviste},
                   ensure_ascii=False, indent=1), encoding="utf-8")

    md = ["# Dublet-kandidater — DAA 1939", "",
          f"{len(raekker)} par til manuel afgørelse. Genereret af "
          "`tools/dubletter1939/byg-liste.py`.", "",
          "Baggrund og klassedefinition: `docs/reviews/dubletter-1939-2026-07-27.md`.",
          "**Scriptet afgør intet** — `Behold`/`Fjern` er et forslag, ikke en konklusion.",
          "Sorteret efter hvor mange uafhængige detektorer der fandt parret.", ""]
    if sprunget_levende:
        md.append(f"> {sprunget_levende} par udeladt fordi mindst én part er "
                  "markeret `levende` (invariant 8).\n")

    for i, r in enumerate(raekker, 1):
        b, f = r["poster"][str(r["behold"])], r["poster"][str(r["fjern"])]
        sider = sorted({str(b.get("side") or "?"), str(f.get("side") or "?")})
        md += [f"## {i}. nr {r['behold']} ↔ nr {r['fjern']} · klasse {r['klasse']} "
               f"· {r['styrke']}/4 detektorer · **s. {' + '.join(sider)}**", "",
               f"`{'`, `'.join(r['detektorer'])}`", ""]
        for rolle, p, nr in (("BEHOLD", b, r["behold"]), ("FJERN ", f, r["fjern"])):
            md += [f"**{rolle} nr {nr}** (id {p['id']}) · **s. {p.get('side') or '?'}** — {p['navn'] or '?'} · "
                   f"f. {p['foedt'] or '?'} · † {p['doed'] or '?'} · "
                   f"{p['fakta']} fakta · {p['fm_kanter']} family_member-rækker · "
                   f"{p['window']} · gruppe `{p['ctx_gruppe'] or '—'}`", "",
                   f"> {uddrag(p)}", ""]
        md.append(f"*Valg:* {r['begrundelse']}.")
        for w in r["advarsler"]:
            md.append(f"- ⚠️ {w}")
        md += ["", "- [ ] afgjort", "", "---", ""]

    if afviste:
        md += ["## Afvist automatisk (modstridende årstal)", "",
               "Fanget af mindst én detektor, men de to poster har kendte og forskellige "
               "årstal → forskellige personer. Vist for gennemsigtighed; kontrollér hvis "
               "et af årstallene kan være en OCR-fejl.", ""]
        for x in sorted(afviste, key=lambda y: y["par"]):
            md.append(f"- nr {x['par'][0]} ↔ nr {x['par'][1]} — {x['navne'][0]!r} / "
                      f"{x['navne'][1]!r} — **{x['grund']}** "
                      f"(`{'`, `'.join(x['detektorer'])}`)")
        md.append("")

    Path(a.ud + ".md").write_text("\n".join(md), encoding="utf-8")
    print(f"{len(raekker)} par -> {a.ud}.md / .json"
          + (f" · {len(afviste)} afvist (modstridende årstal)" if afviste else "")
          + (f" · {sprunget_levende} udeladt (levende)" if sprunget_levende else ""))


if __name__ == "__main__":
    main()
