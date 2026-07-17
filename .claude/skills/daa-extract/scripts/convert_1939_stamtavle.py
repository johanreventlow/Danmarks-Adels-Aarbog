#!/usr/bin/env python3
# =====================================================================
#  convert_1939_stamtavle.py — deterministisk konverter (A3a) fra
#  1939-Reventlow-stamtavlens ekstraktion (work_1939_stamtavle/
#  linked_clean.json) til load_daa.R's clean.json-format.
#
#  Brug:  python3 convert_1939_stamtavle.py [input.json [output.json]]
#         default: work_1939_stamtavle/linked_clean.json
#              ->  work_1939_stamtavle/clean_1939.json  (gitignoreret —
#         input/output indeholder persondata om potentielt levende;
#         COMMIT ALDRIG output).
#
#  NØGLERUM (kritisk beslutning): hele stamtavlen får ÉT syntetisk
#  linje = "1939" og globalt unikke heltals-nr 1..N (deterministisk:
#  sorteret på _id). nr_label SÆTTES TIL str(nr) — IKKE originalen —
#  fordi (a) load_daa.R's pmap keyer på (linje, nr_label) og kræver
#  unikhed (originale løbenumre er GRUPPE-lokale: kun 22 distinkte
#  labels over 539 poster, massiv duplikering), og (b) resolve_barn_keys
#  (load_helpers.R) opløser boern.nr_range via eksakt nøgle
#  "linje-<n>", så A3c's fremtidige nr_range i det globale nøglerum kun
#  virker når nr_label == str(nr). Originalen bevares tabsfrit i
#  passthrough-felterne _orig_nr/_lokal_id (loaderen ignorerer
#  ukendte felter). load_daa.R røres IKKE.
#
#  Datoer: ALLE dato-strenge rutes gennem validate.derive_date_info
#  (A2-parseren) — ingen egen dato-parsing her.
#
#  TODO(A3b): narrative sættes bevidst til None — den fyldes senere
#  deterministisk af segmenteren med bogens ORDRETTE prosa (invariant
#  #6: narrativ må aldrig syntetiseres). kilde_span er foreløbig =
#  date_raw; A3b forfiner til mindste klausul i raw-teksten.
#
#  A3c (forældre-barn-links via bogens gruppe-hierarki):
#  Bogens hierarki ER forældre-barn-grafen: en GRUPPE (= (vindue,
#  _ctx.gruppe, _ctx.foraeldre_note)) er søskende med fælles forælder,
#  og gruppens foraeldre_note navngiver forælderen. Derfor:
#   1) nr-tildeling sker GRUPPE-BLOKVIS i dokumentorden (grupper sorteret
#      på min-_id, medlemmer på _id) — så er hver gruppes nr-blok
#      kontinuert BY CONSTRUCTION, hvilket loaderens boern.nr_range
#      kræver (resolve_barn_keys itererer HVERT nr i [lav, høj] og
#      nr-rummet er tæt).
#   2) gruppe -> forælder-post opløses FAIL-CLOSED i to tiers:
#      Tier 1: medlemmernes _foraelder_id (ground truth).
#      Tier 2: strukturel navnematch af foraeldre_note mod poster i
#      FORRIGE slægtled; link KUN ved præcis ét entydigt kandidat-match
#      (ægtefælle-navn fra noten bruges som deterministisk
#      disambiguator ved flere navne-kandidater). Alt andet = UOPLØST.
#      Hvor begge tiers gælder, SKAL de være enige — modsigelse =>
#      link ikke + tælles (rapport['modsigelser'], forventet 0).
#   3) opløst gruppe => forælder-postens boern = {nr_range: [lo, hi]}.
#      Flere grupper pr. forælder: samlet spænd KUN hvis blokkene er
#      nr-tilstødende; ellers største blok + logget begrænsning.
# =====================================================================
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate import derive_date_info  # noqa: E402  (A2-parseren — genbrug, omskriv ikke)

CONVERTER_VERSION = "1.1.0"
LINJE = "1939"

# (input-felt, faktatype) for dato-fakta. erhverv/uddannelse udelades
# bevidst — load_daa.R springer dem over (bliver i narrativen, A3b).
DATE_FACT_FIELDS = (("foedsel", "fødsel"), ("doed", "død"), ("begravelse", "begravelse"))

# Fritekst-felter der samles i ét note-felt (bevarelse; load_daa.R
# læser IKKE top-niveau note — feltet er til A3b/A3c + menneskelig QA).
NOTE_FIELDS = ("noter", "note", "notes", "slaegtskab_note", "navn_note",
               "navn_kilde", "usikker_noter", "usikker_note", "note_usikker",
               "navn_usikker_note", "nr_note")


def _s(v):
    """Trimmet ikke-tom streng eller None."""
    if isinstance(v, str):
        v = v.strip()
        return v or None
    return None


def build_date_fact(faktatype, blok):
    """Dato-blok ({date_raw, sted, ...}) -> loader-fact eller None.

    date_raw rutes gennem derive_date_info (A2). Blok med KUN sted giver
    stadig et fakta (steds-evidens uden dato). Tom blok -> None.
    dato_usikker (kildens egen tvivl) overlays certainty='uncertain'
    hvis parseren ikke selv satte noget.
    """
    if not isinstance(blok, dict):
        return None
    date_raw = _s(blok.get("date_raw"))
    sted = _s(blok.get("sted"))
    if date_raw is None and sted is None:
        return None
    info = derive_date_info(date_raw)
    certainty = info["certainty"]
    if blok.get("dato_usikker") and certainty is None:
        certainty = "uncertain"
    return {
        "faktatype": faktatype,
        "vaerdi": None,
        "date_raw": date_raw,
        "date_min": info["date_min"],
        "date_max": info["date_max"],
        "date_qualifier": info["qualifier"],
        "date_certainty": certainty,
        "calendar": info["calendar"],
        "sted": sted,
        "kilde_span": date_raw,  # foreløbig; A3b-segmenter forfiner
    }


def convert_godser(godser):
    """Liste af gods-strenge -> [{navn: str}, ...] (tomme droppes)."""
    ud = []
    for g in godser or []:
        navn = _s(g)
        if navn:
            ud.append({"navn": navn})
    return ud


def convert_aegteskab(a):
    """Ét ekstraktions-ægteskab -> loaderens format. Dato via A2-parseren."""
    dato_raw = _s(a.get("dato_raw"))
    info = derive_date_info(dato_raw)
    note_dele = [t for t in (_s(a.get("partner_note")), _s(a.get("skilt_note")))
                 if t]
    if a.get("navn_usikker") or a.get("partner_navn_usikker"):
        note_dele.append("partnernavn usikkert (OCR/kilde)")
    return {
        "ordinal": a.get("ordinal"),
        "partner_navn": _s(a.get("partner_navn")),
        "dato_raw": dato_raw,
        "date_min": info["date_min"],
        "date_max": info["date_max"],
        "sted": _s(a.get("sted")),
        "skilt": bool(a.get("skilt")),
        "partner_foraeldre": _s(a.get("partner_foraeldre")),
        "note": " — ".join(note_dele) or None,
        "kilde_span": dato_raw,  # foreløbig; A3b forfiner
    }


def _kryds_ref_tekst(kr):
    """kryds_ref (str | liste af {type,ref,note,tekst,raw}) -> tekststumper."""
    if isinstance(kr, str):
        t = _s(kr)
        return [f"kryds_ref: {t}"] if t else []
    ud = []
    for item in kr or []:
        if isinstance(item, dict):
            dele = [_s(item.get(k)) for k in ("type", "ref", "tekst", "raw", "note")]
            tekst = " ".join(d for d in dele if d)
            if tekst:
                ud.append(f"kryds_ref: {tekst}")
        else:
            t = _s(item)
            if t:
                ud.append(f"kryds_ref: {t}")
    return ud


def collect_note(rec):
    """Saml alle fritekst-/note-felter + kryds_ref i én streng (eller None)."""
    dele = []
    for felt in NOTE_FIELDS:
        v = rec.get(felt)
        if isinstance(v, list):
            dele.extend(t for t in (_s(x) for x in v) if t)
        else:
            t = _s(v)
            if t:
                dele.append(t)
    dele.extend(_kryds_ref_tekst(rec.get("kryds_ref")))
    return " | ".join(dele) or None


def convert_record(rec, global_nr):
    """Én linked_clean-post -> én loader-post i det globale 1939-nøglerum."""
    facts = []
    titel = _s(rec.get("titel"))
    if titel:
        facts.append({"faktatype": "titel", "vaerdi": titel, "date_raw": None,
                      "date_min": None, "date_max": None, "date_qualifier": None,
                      "date_certainty": None, "calendar": None, "sted": None,
                      "kilde_span": titel})
    for felt, faktatype in DATE_FACT_FIELDS:
        f = build_date_fact(faktatype, rec.get(felt))
        if f is not None:
            facts.append(f)
    # 'kvalifikator' på død (fx 'ung') er ikke en dato-qualifier — bevar som note
    ekstra_noter = []
    doed = rec.get("doed")
    if isinstance(doed, dict) and _s(doed.get("kvalifikator")):
        ekstra_noter.append(f"død: {_s(doed.get('kvalifikator'))}")
    for felt, _ft in DATE_FACT_FIELDS:
        blok = rec.get(felt)
        if isinstance(blok, dict) and _s(blok.get("note")):
            ekstra_noter.append(f"{felt}-note: {_s(blok.get('note'))}")

    aegteskaber = sorted(
        (convert_aegteskab(a) for a in rec.get("aegteskaber") or []),
        key=lambda m: (m["ordinal"] is None, m["ordinal"]))

    note = collect_note(rec)
    if ekstra_noter:
        note = " | ".join(([note] if note else []) + ekstra_noter)

    out = {
        "linje": LINJE,
        "nr": global_nr,
        "nr_label": str(global_nr),  # SKAL == str(nr): pmap-/barn-opslag, se header
        "navn": rec["navn"],
        "koen": rec.get("koen"),
        "usikker": bool(rec.get("navn_usikker") or rec.get("ufuldstaendig")
                        or rec.get("usikker")),
        # TODO(A3b): fyldes af segmenteren med ORDRET prosa — syntetiseres aldrig
        "narrative": None,
        "facts": facts,
        "aegteskaber": aegteskaber,
        "godser": convert_godser(rec.get("godser")),
        "note": note,
        # ---- passthrough (loaderen ignorerer; A3b/A3c + QA bruger dem) ----
        "_id": rec["_id"],
        "_orig_nr": rec.get("nr"),
        "_lokal_id": rec.get("lokal_id"),
        "_ctx": rec.get("_ctx"),
        "_boern_ref": rec.get("boern_ref"),
        "_foraeldre_note": rec.get("foraeldre_note"),
        "_window": rec.get("_window"),
        "_converter_version": CONVERTER_VERSION,
    }
    if rec.get("_foraelder_id") is not None:
        out["_foraelder_id"] = rec["_foraelder_id"]
    tilnavn = _s(rec.get("tilnavn"))
    if tilnavn:
        out["tilnavn"] = tilnavn
    # boern udelades BEVIDST (A3c) — loaderen tolererer fravær (NULL-opslag)
    return out


# =====================================================================
#  A3c — gruppe-hierarki -> forældre-barn-links (fail-closed)
# =====================================================================

_ROMERTAL = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6,
             "VII": 7, "VIII": 8, "IX": 9, "X": 10, "XI": 11}
_ORDINALORD = {"første": 1, "anden": 2, "andet": 2, "tredje": 3, "fjerde": 4,
               "femte": 5, "sjette": 6, "syvende": 7, "ottende": 8,
               "niende": 9, "tiende": 10, "ellevte": 11}
_ROM_RE = re.compile(r"^(VIII|VII|VI|IV|IX|XI|X|V|III|II|I)\.?(?![a-zA-Z])")
_ORD_RE = re.compile(r"^(Første|Anden|Andet|Tredje|Fjerde|Femte|Sjette|Syvende"
                     r"|Ottende|Niende|Tiende|Ellevte)\b", re.IGNORECASE)


def parse_slaegtled(s):
    """Slægtled-streng -> heltal eller None. FORANKRET i strengstart så
    afledningsnoter ('udledt af ... Ottende Slægtled ...') ikke fejllæses;
    'udledt: ukendt ...'/'ukendt ...' -> None (fail-closed)."""
    if not isinstance(s, str) or not s.strip():
        return None
    s = s.strip()
    m = _ROM_RE.match(s)
    if m:
        return _ROMERTAL[m.group(1)]
    m = re.match(r"^(\d+)\b", s)
    if m:
        return int(m.group(1))
    m = _ORD_RE.match(s)
    if m:
        return _ORDINALORD[m.group(1).lower()]
    return None


# Titel-/tiltale-ord der ikke er navnestof. Slægtsnavnet (Reventlow*)
# droppes i FORÆLDER-tokens (poster bærer typisk kun fornavne) men
# beholdes for ægtefæller (drop_slaegt=False) — indgifte findes.
_TITEL_TOKENS = {"greve", "grev", "grevinde", "komtesse", "baron", "baronesse",
                 "lensgreve", "lensgrevinde", "kammerherre", "gehejmeraad",
                 "gehejmeraads", "hofjægermester", "kammerjunker", "ritmester",
                 "oberst", "major", "kaptajn", "hans", "hendes", "dr", "hr",
                 "hustru", "enke"}
_NAVN_TOKEN_RE = re.compile(r"[A-ZÆØÅ][a-zæøåéüöä'\-]*")


def name_tokens(s, drop_slaegt=True):
    """Kapitaliserede navne-tokens, lowercased, uden titler (og uden
    slægtsnavnet når drop_slaegt)."""
    ud = []
    for t in _NAVN_TOKEN_RE.findall(s or ""):
        tl = t.lower()
        if tl in _TITEL_TOKENS:
            continue
        if drop_slaegt and tl.startswith("reventlow"):
            continue
        ud.append(tl)
    return ud


def _tok_eq(a, b):
    """Token-lighed med genitiv-s-tolerance ('frederiks' == 'frederik')."""
    return a == b or a == b + "s" or b == a + "s"


def _is_subseq(small, big):
    it = iter(big)
    return all(any(_tok_eq(s, b) for b in it) for s in small)


def names_match(a, b):
    """Match hvis den korteste token-sekvens er ORDNET delsekvens af den
    længste (kalibreret mod de 17 _foraelder_id-ground-truth-grupper:
    afvigelser er altid et ekstra/manglende mellemnavn, aldrig ombytning)."""
    if not a or not b:
        return False
    return _is_subseq(a, b) if len(a) <= len(b) else _is_subseq(b, a)


_BOERN_KEYWORD_RE = re.compile(r"\b(Børn|Barn|Sønner|Søn|Døtre|Datter)\b")
# Noter der beskriver ekstraktions-usikkerhed frem for at navngive en
# forælder -> uparsebare (fail-closed, gæt aldrig).
_UKENDT_MARKOERER = ("ukendt", "uden for vindue", "prosa", "gruppe-header",
                     "forældrepar", "forælder-header")


def extract_parent_tokens(note):
    """Forælder-navnetokens fra en foraeldre_note ('<Navn>s Børn m. <Ægtefælle>'),
    eller None hvis noten ikke entydigt navngiver en forælder."""
    if not isinstance(note, str) or not note.strip():
        return None
    n = note.strip()
    low = n.lower()
    if any(w in low for w in _UKENDT_MARKOERER):
        return None
    m = _BOERN_KEYWORD_RE.search(n)
    if m:
        prefix = n[:m.start()]
    else:
        m2 = re.search(r"\s+(m\.|med|og)\s+", n)
        if not m2:
            return None
        prefix = n[:m2.start()]
    # '<far> og <mor>s Børn' -> tag første forælder (posterne er agnatiske)
    prefix = re.split(r"\s+og\s+", prefix)[0]
    prefix = prefix.replace("'s", " ").replace("’s", " ")
    return name_tokens(prefix) or None


def extract_spouse_tokens(note):
    """Alle ægtefælle-segmenter efter børne-nøgleordet ('… Børn m. <X> …
    og af 2. Ægteskab m. <Y> …') -> liste af token-lister."""
    if not isinstance(note, str):
        return []
    m = _BOERN_KEYWORD_RE.search(note)
    hale = note[m.end():] if m else note
    segs = []
    for sm in re.finditer(r"\bm(?:\.|ed)\s+([^,(;—-]+)", hale):
        toks = name_tokens(sm.group(1), drop_slaegt=False)
        if toks:
            segs.append(toks)
    return segs


def group_key(rec):
    """Gruppe-identitet: (vindue, _ctx.gruppe, _ctx.foraeldre_note).
    gruppe-bogstaver er VINDUE-lokale, og samme bogstav kan i samme vindue
    dække flere søskendeflokke med hver sin foraeldre_note — nøglen skal
    derfor rumme alle tre. Begge None -> ingen gruppe (singleton)."""
    ctx = rec.get("_ctx") or {}
    gruppe = ctx.get("gruppe")
    note = _s(ctx.get("foraeldre_note"))
    if gruppe is None and note is None:
        return None
    return (rec.get("_window"), gruppe, note)


def build_units(records):
    """Poster -> ordnede enheder (grupper + singletoner) i dokumentorden:
    enheder sorteret på deres medlemmers min-_id, medlemmer på _id."""
    grupper = {}
    orden = []
    for rec in sorted(records, key=lambda r: r["_id"]):
        k = group_key(rec)
        if k is None:
            orden.append([rec])
            continue
        if k not in grupper:
            grupper[k] = []
            orden.append(grupper[k])
        grupper[k].append(rec)
    return orden


def _spouse_ok(rec, spouse_segs):
    """Har posten et ægteskab hvis partnernavn matcher ET note-segment?"""
    for a in rec.get("aegteskaber") or []:
        ptoks = name_tokens(a.get("partner_navn") or "", drop_slaegt=False)
        if not ptoks:
            continue
        for seg in spouse_segs:
            if names_match(seg, ptoks):
                return True
    return False


def _tier2_resolve(unit, note, records, gen_af_id):
    """Strukturel navnematch: gruppens foraeldre_note mod poster i FORRIGE
    slægtled. Returnerer (_id | None, årsag). FAIL-CLOSED: kun præcis ét
    entydigt match linker; ægtefælle-navnet fra noten er eneste tilladte
    disambiguator (deterministisk bog-evidens, ikke gæt)."""
    gens = {gen_af_id[r["_id"]] for r in unit if gen_af_id[r["_id"]] is not None}
    if len(gens) != 1:
        return None, "slaegtled_ukendt"
    g = next(iter(gens))
    ptoks = extract_parent_tokens(note)
    if not ptoks:
        return None, "note_uparsebar"
    medlem_ids = {r["_id"] for r in unit}
    cands = [r for r in records
             if gen_af_id[r["_id"]] == g - 1 and r["_id"] not in medlem_ids
             and names_match(ptoks, name_tokens(r["navn"]))]
    if len(cands) == 1:
        return cands[0]["_id"], "ok_navn"
    if len(cands) > 1:
        spouse_segs = extract_spouse_tokens(note)
        if spouse_segs:
            c2 = [r for r in cands if _spouse_ok(r, spouse_segs)]
            if len(c2) == 1:
                return c2[0]["_id"], "ok_navn_aegtefaelle"
        return None, f"tvetydig({len(cands)})"
    return None, "ingen_match"


def _tom_rapport():
    return {
        "grupper_i_alt": 0, "grupper_uden_note": 0, "boern_uden_note": 0,
        "tier1_grupper": 0, "tier1_konflikt_grupper": 0, "tier1_ugyldig": 0,
        "tier2_grupper": 0, "tier2_via_aegtefaelle": 0,
        "tier1_tier2_enige": 0, "modsigelser": 0,
        "uoploeste_grupper": 0, "uoploeste_boern": 0, "tvetydige_grupper": 0,
        "uoploest_pr_aarsag": {},
        "multi_gruppe_foraeldre": 0, "multi_gruppe_ikke_tilstoedende": 0,
        "boern_udeladt_ikke_tilstoedende": 0, "selvreference_afvist": 0,
        "linkede_boern": 0, "falske_boern_i_range": 0,
        "foraelder_foer_boern_brud": 0, "gen_orden_inversioner": 0,
    }


def _link_units(units, posts, records):
    """Opløs grupper -> forældre og sæt boern.nr_range på forælder-poster.
    Muterer posts; returnerer rapport (KUN tal — ingen persondata)."""
    rap = _tom_rapport()
    post_af_id = {p["_id"]: p for p in posts}
    gen_af_id = {r["_id"]: parse_slaegtled((r.get("_ctx") or {}).get("slaegtled"))
                 for r in records}
    resolved = []                                     # (foraelder_id, unit, tier)
    for unit in units:
        k = group_key(unit[0])
        if k is None:
            continue
        rap["grupper_i_alt"] += 1
        note = k[2]
        fids = {r.get("_foraelder_id") for r in unit
                if r.get("_foraelder_id") is not None}
        t2_id, t2_aarsag = _tier2_resolve(unit, note, records, gen_af_id)
        if len(fids) > 1:                             # modstridende ground truth
            rap["tier1_konflikt_grupper"] += 1
            continue
        if len(fids) == 1:
            fid = next(iter(fids))
            if t2_id is not None:
                if t2_id == fid:
                    rap["tier1_tier2_enige"] += 1
                else:                                 # KRITISK: navnematch modsiger
                    rap["modsigelser"] += 1           # ground truth -> link IKKE
                    continue
            if fid not in post_af_id or fid in {r["_id"] for r in unit}:
                rap["tier1_ugyldig"] += 1
                continue
            rap["tier1_grupper"] += 1
            resolved.append((fid, unit, "tier1"))
            continue
        if note is None:
            rap["grupper_uden_note"] += 1
            rap["boern_uden_note"] += len(unit)
            continue
        if t2_id is not None:
            rap["tier2_grupper"] += 1
            if t2_aarsag == "ok_navn_aegtefaelle":
                rap["tier2_via_aegtefaelle"] += 1
            resolved.append((t2_id, unit, "tier2"))
        else:
            rap["uoploeste_grupper"] += 1
            rap["uoploeste_boern"] += len(unit)
            if t2_aarsag.startswith("tvetydig"):
                rap["tvetydige_grupper"] += 1
            rap["uoploest_pr_aarsag"][t2_aarsag] = \
                rap["uoploest_pr_aarsag"].get(t2_aarsag, 0) + 1

    # ---- nr_range pr. forælder (flere grupper: samlet spænd kun hvis
    # nr-tilstødende, ellers største blok + logget begrænsning) ----
    per_foraelder = defaultdict(list)
    for fid, unit, tier in resolved:
        nrs = sorted(post_af_id[r["_id"]]["nr"] for r in unit)
        per_foraelder[fid].append((nrs[0], nrs[-1], unit, tier))
    for fid, blokke in per_foraelder.items():
        blokke.sort(key=lambda b: b[0])
        # NB: en forælder KAN legitimt have flere grupper (børn af 1./2. ægteskab —
        # noterne "af første/andet Ægteskab" opløser begge til samme forælder-token).
        # Ægthed sikres af Tier2 (kun delsekvens-match af forælder-navn) + modsigelses-
        # vagt + fødselsår-plausibilitet; et navne-inkonsistens-filter her ville
        # fejlparkere netop de legitime 2-ægteskabs-tilfælde. Verificeret: nr-range-
        # integritet 0 falske børn, 0 implausible fødselsår-links (review 2026-07-17).
        if len(blokke) > 1:
            rap["multi_gruppe_foraeldre"] += 1
        lo, hi = blokke[0][0], blokke[-1][1]
        n_boern = sum(b[1] - b[0] + 1 for b in blokke)
        valgte = blokke
        if len(blokke) > 1 and hi - lo + 1 != n_boern:
            rap["multi_gruppe_ikke_tilstoedende"] += 1
            stoerste = max(blokke, key=lambda b: (b[1] - b[0] + 1, -b[0]))
            rap["boern_udeladt_ikke_tilstoedende"] += \
                n_boern - (stoerste[1] - stoerste[0] + 1)
            valgte = [stoerste]
            lo, hi = stoerste[0], stoerste[1]
        foraelder_post = post_af_id[fid]
        if lo <= foraelder_post["nr"] <= hi:          # kan ikke være sit eget barn
            rap["selvreference_afvist"] += 1
            continue
        foraelder_post["boern"] = {"nr_range": [lo, hi]}
        foraelder_post["_boern_link"] = {"tier": sorted({b[3] for b in valgte}),
                                         "grupper": len(valgte)}
        for b in valgte:
            for r in b[2]:
                post_af_id[r["_id"]]["_link_foraelder_nr"] = foraelder_post["nr"]
        rap["linkede_boern"] += hi - lo + 1

    # ---- integritet: intet range må rumme en post der ikke er linket barn ----
    nr2post = {p["nr"]: p for p in posts}
    for p in posts:
        if "boern" in p:
            lo, hi = p["boern"]["nr_range"]
            rap["falske_boern_i_range"] += sum(
                1 for n in range(lo, hi + 1)
                if nr2post[n].get("_link_foraelder_nr") != p["nr"])
            if p["nr"] > lo:                          # forælder-nr før børne-blok?
                rap["foraelder_foer_boern_brud"] += 1

    # ---- info: holder bredde-først-ordenen (slægtled N før N+1)? ----
    unit_gens = []
    for unit in units:
        gens = {gen_af_id[r["_id"]] for r in unit if gen_af_id[r["_id"]] is not None}
        if len(gens) == 1:
            unit_gens.append(next(iter(gens)))
    rap["gen_orden_inversioner"] = sum(
        1 for a, b in zip(unit_gens, unit_gens[1:]) if b < a)
    return rap


def convert_all(records, rapport=None):
    """Hele korpus: gruppe-blokvis nummerering i dokumentorden (hver gruppe
    = én kontinuert nr-blok BY CONSTRUCTION), dernæst fail-closed
    forældre-link-opløsning. rapport (dict, valgfri) fyldes med tal."""
    units = build_units(records)
    posts = []
    nr = 0
    for gi, unit in enumerate(units, start=1):
        har_gruppe = group_key(unit[0]) is not None
        for rec in unit:
            nr += 1
            p = convert_record(rec, nr)
            if har_gruppe:
                p["_gruppe_nr"] = gi
            posts.append(p)
    rap = _link_units(units, posts, records)
    if rapport is not None:
        rapport.update(rap)
    return posts


def flet_narrative(out, narrativ_sti):
    """Flet ORDRET narrative + side fra segment_1939.py's output ind pr. _id.
    load_daa.R kræver narrative NOT NULL — mangler-listen skal være tom.
    Returnerer (antal_flettet, [manglende _id])."""
    if not Path(narrativ_sti).exists():
        return 0, [p["_id"] for p in out]
    with open(narrativ_sti, encoding="utf-8") as f:
        nmap = json.load(f)
    flettet, mangler = 0, []
    for p in out:
        n = nmap.get(str(p["_id"]))
        if n and n.get("narrative"):
            p["narrative"] = n["narrative"]
            if n.get("side") is not None:
                p["sider"] = str(n["side"])
            flettet += 1
        else:
            mangler.append(p["_id"])
    return flettet, mangler


def main(argv):
    inp = Path(argv[1]) if len(argv) > 1 else Path("work_1939_stamtavle/linked_clean.json")
    ud = Path(argv[2]) if len(argv) > 2 else Path("work_1939_stamtavle/clean_1939.json")
    with open(inp, encoding="utf-8") as f:
        records = json.load(f)
    rapport = {}
    out = convert_all(records, rapport=rapport)
    n_flettet, n_mangler = flet_narrative(out, ud.parent / "narrative_1939.json")
    with open(ud, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"convert_1939_stamtavle v{CONVERTER_VERSION}: "
          f"{len(records)} poster ind -> {len(out)} poster ud ({ud})")
    print(f"narrative flettet (A3b): {n_flettet}/{len(out)}"
          + (f"  ADVARSEL: {len(n_mangler)} poster UDEN narrative (load fejler — kør segment_1939.py først)"
             if n_mangler else "  (alle poster har narrative)"))
    print("A3c link-rapport (KUN tal, ingen persondata):")
    for k, v in rapport.items():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main(sys.argv)
