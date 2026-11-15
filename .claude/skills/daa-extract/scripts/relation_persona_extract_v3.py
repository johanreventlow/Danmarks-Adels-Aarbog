"""Trin 5b 2b-ii runde 2 (spec §17.4-17.5): navneregel v3, partnersammenligning og P-forslag.

Deterministisk; ingen model læser teksten. Ordvinduet og årstallene er v2's (SQL-tvillingerne er uændrede).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

import relation_persona_extract as _v1
from relation_persona_extract import LETTER, MAX_NAME_WORDS, UPPER
from relation_persona_extract_v2 import CAP, STOP_TITLE, TOKEN, WORD, YEAR, _shares_half, _start, _words, fold_raw_text, windows
from relation_persona_extract_v2 import PARTICLES as _PARTICLES_V2
from private_io import write_private_replace

PROFILE = "relation-persona-2018-20-v3"
RULE = "aarstal-120-v1"
# Lukket titelliste (spec §17.5) = SQL-tvillingen private.relation_title_words(); test_title_words_match_schema låser dem.
TITLE_WORDS = ("baron", "baronesse", "friherre", "friherreinde", "greve", "grevinde", "hertug", "hertuginde",
               "komtesse", "prins", "prinsesse")
TITLE_PREFIXES = ("rigs", "lens")
PARTICLES = _PARTICLES_V2 | {"und", "zu", "dem", "genannt"}
NOT_NAME = {"til"}   # »til <gods>« ≠ navn (beslutning 2026-10-03); udløser ikke navn_afkortet
LOWER_WORD = re.compile(r"[a-zæøåà-öø-ÿ]+(?:-[a-zæøåà-öø-ÿ]+)*")   # også »rigs-grevinde«; ».,;:« strippes først


class NameOverrideError(ValueError):
    """Arkets navn: står ikke ordret og entydigt fra navnestarten inden for vinduet."""


# #244 (spec §5): bogens eget ægteskabsnummer forrest i påstanden (»g. 2°«/»gift 2°«). Eksplicitte klasser, ikke \s/\d
# (som vinduet). SQL-tvilling: private.relation_book_ordinal; fælles liste tests/fixtures/relation-book-ordinal.json.
BOOK_ORDINAL = re.compile(r"^[ \t]*(g[.]|gift)[ \t]*([0-9]{1,3})[ \t]*[°º]")


def book_ordinal(raw: str | None) -> int | None:
    m = BOOK_ORDINAL.match((raw or "").lower())
    return int(m.group(2)) if m else None

def is_title(word: str) -> bool:
    w = word.lower()
    return w in TITLE_WORDS or any(w.startswith(p) and w[len(p):] in TITLE_WORDS for p in TITLE_PREFIXES)


def title_free(name: str) -> bool:
    """Sikring ved D (spec §17.5): hvert ord har versal eller er en partikel, og intet ord er en titel.
    Ordene deles som i SQL-tvillingen (på alle ikke-ordtegn), så »Rigs-Grevinde« fanges allerede på arket."""
    for m in WORD.finditer(name):
        w = m.group(0)
        if is_title(w) or not (CAP.fullmatch(w) or w.lower() in PARTICLES):
            return False
    return True


def _links_to_name(toks, k: int) -> bool:
    """Partikler og titler inde i navnet: kæden fra k skal ende i et ord med versal. Komma/punktum må ikke stå
    inde i kæden, men gerne efter slutordet (hovedløkken afslutter navnet dér)."""
    j = k
    while j < len(toks):
        word = toks[j][2]
        bare = word.rstrip(",.;:")
        if bare.lower() in PARTICLES or is_title(bare):
            if bare != word:
                return False
            j += 1
            continue
        return bool(CAP.fullmatch(bare))
    return False


def _truncated(text: str, nt: int, st: int) -> bool:
    """Reglen stoppede foran et ulistet småord, som efterfølges af et versalord (fx en ukendt titel inde i
    navnet). Sådan et navn er afkortet og må ikke blive D (spec §17.9)."""
    m = re.match(r"\s+(\S+)\s+(\S+)", text[nt:st])
    if not m:
        return False
    w, nxt = m.group(1).rstrip(",.;:"), m.group(2).rstrip(",.;:")
    return bool(LOWER_WORD.fullmatch(w)) and w not in PARTICLES and w not in NOT_NAME and bool(CAP.fullmatch(nxt))


def _name(seg: str):
    """Som v2, men navneløbet fortsætter over partikel- og titelkæder, der ender i et versalord."""
    start, after_gift = _start(seg)
    toks = [(m.start(), m.end(), m.group(0)) for m in TOKEN.finditer(seg, start)]
    k = 0
    while k < len(toks):                                   # spring titler/forkortelser over (som v2)
        word = toks[k][2]
        bare = word.rstrip(",.;:")
        if CAP.fullmatch(bare) and not (word.endswith(".") and len(bare) <= 4):
            break
        k += 1
    if k == len(toks):
        return None
    titel = seg[start:toks[k][0]]
    if any(ch in titel for ch in ";()*†") or STOP_TITLE.search(titel):
        return None
    if after_gift and not re.fullmatch(r"[\s\d.,°/-]*", titel):
        return None
    if not after_gift and any(ch.isdigit() for ch in titel):
        return None
    nf, nt, words = toks[k][0], None, 0
    while k < len(toks):
        s, _e, word = toks[k]
        bare = word.rstrip(",.;:")
        if CAP.fullmatch(bare):
            nt, words = s + len(bare), words + 1
        elif nt is not None and bare == word and _links_to_name(toks, k):
            nt = s + len(bare)
        else:
            break
        if bare != word:                                   # komma/punktum afslutter navnet
            break
        k += 1
    if nt is None or words > MAX_NAME_WORDS or not LETTER.search(seg[nf:nt]):
        return None
    return nf, nt


def _core(name: str | None) -> list[str]:
    return [w for _, _, w in _words(name or "") if not w.isdigit() and w not in PARTICLES and not is_title(w)]


def partner_hit(name: str, partner_name: str | None) -> bool:
    """Træf ved S: efternavnet (sidste kerneord) passer, mindst ét kerneord mere er fælles, og mindst halvdelen
    af navnets kerneord er fælles. Efternavnet alene er ikke nok (final review F2)."""
    a, b = _core(name), _core(partner_name)
    if not a or not b or a[-1] != b[-1]:
        return False
    sa, shared = set(a), set(a) & set(b)
    return len(shared) >= 2 and 2 * len(shared) >= len(sa)


def partner_similar(name: str, partner_name: str | None) -> bool:
    """Løst dubletværn før D/N og P (final review F2): v2's halvdelsregel eller blot ét fælles kerneord."""
    return _shares_half(name, partner_name) or bool(set(_core(name)) & set(_core(partner_name)))


def propose(row: dict, cutoff: int, name_override: str | None = None, text_form: str = "folded") -> dict:
    """Forslag for én række. En navn:-rettelse kræver en navnestart; ellers NameOverrideError (spec §17.6),
    også ved de tidlige U og ved I, så rettelsen aldrig ignoreres tavst."""
    if text_form == "raw" and len(row.get("clauses") or []) == 1:
        # Rå tekst (6d-3): reglen kører på den foldede tekst (så et navn ikke deles af et linjeskift eller en
        # orddeling), og positionerne føres tilbage til originalens, som writeren kontrollerer.
        ft, org = fold_raw_text(row["clauses"][0]["verbatim_text"])
        fr, _ = fold_raw_text(row.get("raw") or "")
        f_row = {**row, "raw": fr, "clauses": [{**row["clauses"][0], "verbatim_text": ft}]}
        p = _propose(f_row, cutoff, name_override, "folded")
        for k in ("span_from", "name_from"):
            if k in p:
                p[k] = org[p[k]]
        for k in ("span_to", "name_to"):
            if k in p:
                p[k] = org[p[k] - 1] + 1
    else:
        p = _propose(row, cutoff, name_override, text_form)
    if name_override is not None and "name_from" not in p:
        raise NameOverrideError("ingen navnestart")
    return p


def _propose(row: dict, cutoff: int, name_override: str | None, text_form: str = "folded") -> dict:
    if not row.get("principal_ok") or row.get("principal_person_id") is None:
        return {"tok": "U", "reason": "ingen_hovedperson"}
    if row["supporting_count"] != 1 or len(row["clauses"]) != 1:
        return {"tok": "U", "reason": "flere_klausuler"}
    if row.get("marriage_ordinal") is None:
        return {"tok": "U", "reason": "intet_nummer"}
    bo = book_ordinal(row.get("raw"))
    if bo is not None and bo != row["marriage_ordinal"]:
        return {"tok": "U", "reason": "nummer_modsiger_bog"}
    text, raw = row["clauses"][0]["verbatim_text"], row.get("raw") or ""
    w = windows(text, raw, text_form)
    if len(w) != 1:
        return {"tok": "U", "reason": "intet_vindue" if not w else "tvetydigt_vindue"}
    sf, st = w[0]
    seg = text[sf:st]
    nm = _name(seg)
    if nm is None:
        if UPPER.search(seg, _start(seg)[0]) is None:
            return {"tok": "I", "reason": "intet_navn", "span_from": sf, "span_to": st}
        return {"tok": "U", "reason": "navn_uklart"}
    nf, nt = sf + nm[0], sf + nm[1]
    rule_name, basis = text[nf:nt], "rule"
    if name_override is not None:
        o = name_override
        end = nf + len(o)
        if (o != o.strip() or not LETTER.search(o) or not text.startswith(o, nf)
                or end > st or text.count(o) != 1
                or not o[-1].isalpha() or (end < len(text) and text[end].isalnum())):   # helt ord, ingen tegnsætning
            raise NameOverrideError("navn")
        nt, basis = nf + len(o), "sheet"
    name = text[nf:nt]
    years = sorted({int(y) for y in YEAR.findall(text)})
    out = {"span_from": sf, "span_to": st, "name_from": nf, "name_to": nt, "clause_years": years, "name_basis": basis}
    hits = [p for p in row.get("principal_partners", []) if partner_hit(name, p.get("navn"))]
    ids = {p["person_id"] for p in hits}
    if len(ids) == 1:
        return {**out, "tok": "S", "reason": "partnermatch", "partner_person_id": hits[0]["person_id"],
                "partner_ordinal": hits[0].get("ordinal")}
    if ids:
        same = {p["person_id"] for p in hits if p.get("ordinal") == row["marriage_ordinal"]}
        if len(same) == 1:
            return {**out, "tok": "S", "reason": "partnermatch_nummer", "partner_person_id": same.pop(),
                    "partner_ordinal": row["marriage_ordinal"]}
        return {**out, "tok": "U", "reason": "flere_partnere"}
    if any(partner_similar(n, p.get("navn")) for n in {name, rule_name} for p in row.get("principal_partners", [])):
        return {**out, "tok": "U", "reason": "partner_ligner"}
    if not title_free(name):
        return {**out, "tok": "U", "reason": "titel_i_navn"}
    if basis == "rule" and _truncated(text, nt, st):
        return {**out, "tok": "U", "reason": "navn_afkortet"}
    if years and max(years) <= cutoff:
        return {**out, "tok": "D", "reason": "aldersregel"}
    return {**out, "tok": "N", "reason": "kan_ikke_erklaeres_afdoed"}


def propose_redecide(prow: dict, cutoff: int) -> dict:
    """P-linjen (spec §17.6): en new_person_needed uden deceased; D kun efter aldersreglen og uden partnertræf."""
    if not prow.get("clause_is_current"):
        return {"tok": "U", "reason": "klausul_afloest"}
    if prow.get("principal_person_id") is None:
        return {"tok": "U", "reason": "ingen_hovedperson"}
    if prow.get("marriage_ordinal") is None:
        return {"tok": "U", "reason": "intet_nummer"}
    name = prow.get("name_text") or ""
    if any(partner_similar(name, p.get("navn")) for p in prow.get("principal_partners", [])):
        return {"tok": "U", "reason": "partner_findes"}
    if not title_free(name):
        return {"tok": "U", "reason": "titel_i_navn"}
    years = sorted({int(y) for y in YEAR.findall(prow.get("clause_text") or "")})
    if years and max(years) <= cutoff:
        return {"tok": "D", "reason": "aldersregel", "clause_years": years}
    return {"tok": "N", "reason": "kan_ikke_erklaeres_afdoed", "clause_years": years}


# --- Trin 6d-3: profilen som data. Udtrækket (CLI) læser prædikatformer og tekstform fra en profilfil. ----------------
SCRIPTS_DIR = Path(__file__).resolve().parent
# Uden --profile: den profilfil, hvis relation_profile er PROFILE (2018-20-v3); adfærden er den hidtidige.
DEFAULT_PROFILE_FILE = SCRIPTS_DIR.parent / "profiles" / "relation-persona-2018-20.json"
FORMS = ("v1", "v3")   # understøttede payloadformer; v2 har intet udtræk her


def load_profile(path: Path | str | None = None) -> dict:
    """Profilfilens relation_profile (DB-profilrækkens navn), predicate_forms (prædikat -> v1/v3) og text_form."""
    p = json.loads(Path(path or DEFAULT_PROFILE_FILE).read_text(encoding="utf-8"))
    forms, tf = p.get("predicate_forms"), p.get("text_form")
    if (not isinstance(p.get("relation_profile"), str) or not p["relation_profile"]
            or not isinstance(forms, dict) or not forms or any(v not in FORMS for v in forms.values())
            or tf not in ("folded", "raw")):
        raise ValueError("PROFILE_FILE_INVALID")
    return {"relation_profile": p["relation_profile"], "predicate_forms": forms, "text_form": tf}


class InputError(ValueError):
    """v1- og v3-inputtet hænger ikke sammen (fail closed): udtrækket nægter at lave et manifest."""


def _v3_element(r: dict, line: int, *, profile: str, text_form: str, cutoff: int, sheet_sha256: str):
    """Ét ægteskab fra v3-inputtet, afgjort af præcis de samme argumenter som arkflowet (render: propose(r, cutoff)):
    rækken uændret med hovedperson og partnere. S/D/N giver element (= arket med uændrede forslag); I/U parkeres
    med forslagets grund, så partner_ligner/flere_partnere aldrig bliver til personas."""
    p = propose(r, cutoff, text_form=text_form)
    if p["tok"] not in ("S", "D", "N"):
        return None, p["reason"]
    c = r["clauses"][0]
    return {"birth_raw": None, "clause_observation_id": c["observation_id"], "clause_set_seq": c["clause_set_seq"],
            "clause_set_sha256": c["clause_set_sha256"], "death_raw": None,
            "interpretation_key": r["interpretation_key"], "interpretation_version": r["interpretation_version"],
            "marriage_ordinal": r["marriage_ordinal"], "name_basis": p["name_basis"], "name_from": p["name_from"],
            "name_to": p["name_to"], "post_offset": c["post_char_from"] + p["span_from"], "predicate": r["predicate"],
            "profile": profile, "sheet_line": line, "sheet_sha256": sheet_sha256,
            "span_from": p["span_from"], "span_to": p["span_to"]}, None


# Alle felter, v1- og v3-rækken har til fælles (v3-rækken er v1-rækken + hovedperson, partnere og posttekst). De skal
# findes i begge og være ens: writeren og dublet-filteret læser record_key, klausulerne og nummeret, og
# supporting_count/occurrence_id er en del af serverens afgrænsning af rækken.
_JOIN_FIELDS = ("interpretation_version", "predicate", "raw", "record_key", "occurrence_id", "marriage_ordinal",
                "supporting_count", "clauses", "principal_ok")


def canonical_sha256(value) -> str:
    """Serverens kanoniske hash (private.reimport_canonical_json_sha256): objektnøgler sorteret, ingen blanktegn,
    skalarer som jsonb::text (UTF-8, ingen \\u-escape af ikke-ASCII). Nøglerne i inputtet er ASCII med små bogstaver
    og understreg, så kodepunktsorden = databasens ORDER BY."""
    def txt(v) -> str:
        if isinstance(v, dict):
            return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + txt(v[k]) for k in sorted(v)) + "}"
        if isinstance(v, list):
            return "[" + ",".join(txt(x) for x in v) + "]"
        return json.dumps(v, ensure_ascii=False)
    return hashlib.sha256(txt(value).encode("utf-8")).hexdigest()


def extract_rows(v1_rows: list[dict], v3_rows: list[dict] | None, profile: dict, *, v3_sheet_sha256: str | None,
                 cutoff: int = 0) -> tuple[dict, dict]:
    """Manifest og statistik. v3-formens prædikater (ægteskaber) afgøres fra v3_rows (med hovedperson og partnere),
    sammenkædet med v1-rækkerne på interpretation_key; v1-formens prædikater udtrækkes fra v1-rækkerne; øvrige
    prædikater parkeres (praedikat_ikke_i_profil). Fail closed (InputError): v3-prædikat uden v3-input, v1-række uden
    v3-række, v3-række uden v1-række (eller uden for profilens v3-prædikater), eller afvigende rækkeindhold.
    sheet_line er rækkens nummer i v3-inputtet; sheet_sha256 = v3-inputtets sha256 (binder elementet til det input,
    reglen kørte over; der er intet ark, og writeren kræver blot 64 hex)."""
    forms, name = profile["predicate_forms"], profile["relation_profile"]
    v3_preds = {k for k, v in forms.items() if v == "v3"}
    v1_by_key = {r["interpretation_key"]: r for r in v1_rows}
    if len(v1_by_key) != len(v1_rows):
        raise InputError("INPUT_DUPLICATE_KEY v1")
    need_v3 = [r for r in v1_rows if r["predicate"] in v3_preds]
    if need_v3 and v3_rows is None:
        raise InputError("V3_INPUT_REQUIRED: profilen har v3-prædikater, men --v3-input mangler")
    v3_rows = v3_rows or []
    v3_by_key = {r["interpretation_key"]: r for r in v3_rows}
    if len(v3_by_key) != len(v3_rows):
        raise InputError("INPUT_DUPLICATE_KEY v3")
    for r in need_v3:
        if r["interpretation_key"] not in v3_by_key:
            raise InputError("V3_ROW_MISSING: ægteskabsrække uden v3-række")
    for k, r3 in v3_by_key.items():
        r1 = v1_by_key.get(k)
        if r1 is None:
            raise InputError("V1_ROW_MISSING: v3-række uden v1-række")
        if r1["predicate"] not in v3_preds:
            raise InputError("V3_ROW_NOT_IN_PROFILE: v3-række for et prædikat uden v3-form")
        if any(f not in r1 or f not in r3 or r1[f] != r3[f] for f in _JOIN_FIELDS):
            raise InputError("INPUT_ROW_MISMATCH: v1- og v3-rækken afviger")
    parked: Counter = Counter()
    elements: dict[str, dict] = {}
    v1_rows_todo = []
    for r in v1_rows:
        form = forms.get(r["predicate"])
        if form is None:
            parked["praedikat_ikke_i_profil"] += 1
        elif form == "v1":
            v1_rows_todo.append(r)
    for line, r3 in enumerate(v3_rows, 1):
        el, reason = _v3_element(r3, line, profile=name, text_form=profile["text_form"], cutoff=cutoff,
                                 sheet_sha256=v3_sheet_sha256)
        if el is None:
            parked[reason] += 1
        else:
            elements["relation-persona:" + r3["interpretation_key"]] = el
    # Uadskillelige dubletter (som v1, spec §5.1): samme post, prædikat, post_offset og spændlængde parkeres begge.
    # BEVIDST FORSKEL fra arkflowet: arket viser alle ægteskaber til et menneske og parkerer ikke dubletter; den
    # maskinelle vej har intet menneske og parkerer dem konservativt (som v1-udtrækket). Parity-testen mod arket
    # udelader derfor dublettilfældet (test_cli_parkerer_dubletter).
    rec = {r["interpretation_key"]: r["record_key"] for r in v1_rows}
    sig = {k: (rec[e["interpretation_key"]], e["predicate"], e["post_offset"], e["span_to"] - e["span_from"])
           for k, e in elements.items()}
    n = Counter(sig.values())
    for k in [k for k in elements if n[sig[k]] > 1]:
        del elements[k]
        parked["dublet"] += 1
    if v1_rows_todo:                               # v1 dedublerer selv
        m1, st1 = _v1.extract_rows(v1_rows_todo, profile=name)
        elements.update(m1["authorized_elements"])
        parked.update(st1["parkeret"])
    manifest = {"expected_counts": {"person_creates": 0, "source_evidence": 0, "relation_personas": len(elements)},
                "authorized_elements": dict(sorted(elements.items()))}
    per = Counter(e["predicate"] for e in elements.values())
    return manifest, {"elementer": len(elements), "parkeret": dict(sorted(parked.items())),
                      "pr_praedikat": dict(sorted(per.items()))}


def _read(path: str) -> tuple[dict, str]:
    b = Path(path).read_bytes()
    return json.loads(b.decode("utf-8")), hashlib.sha256(b).hexdigest()   # (indhold, sha256 af filens bytes)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="v1-input (relation_persona_input.sql)")
    ap.add_argument("--v3-input", help="v3-input (relation_v3_rows.sql); kræves, når profilen har v3-prædikater")
    ap.add_argument("--out", required=True)
    ap.add_argument("--profile", help="profilfil (profiles/relation-persona-*.json); uden: standardprofilen")
    a = ap.parse_args(argv)
    try:
        profile = load_profile(a.profile)
        d1, f1_sha = _read(a.input)
        claimed = d1.get("input_sha256")
        if claimed is not None and claimed != canonical_sha256(d1["input"]):
            raise InputError("V1_INPUT_SHA_MISMATCH: inputtets kanoniske hash er ikke den serveren oplyste")
        d3 = f3_sha = None
        if a.v3_input:
            d3, f3_sha = _read(a.v3_input)
            if d3.get("contract") != "relation-persona-v3-input" or "rows" not in d3:
                raise InputError("V3_INPUT_CONTRACT_INVALID")
        manifest, stats = extract_rows(d1["input"], d3["rows"] if d3 else None, profile, v3_sheet_sha256=f3_sha,
                                       cutoff=int(d3["deceased_cutoff_year"]) if d3 else 0)
    except (InputError, ValueError, KeyError) as exc:
        print(f"RELATION_EXTRACT_FEJL {exc}", file=sys.stderr)
        return 1
    # Binding af inputtene (writer-kontrakten er uændret; authorized_elements røres ikke). Filhasherne er over filens
    # bytes; input_sha256 er serverens kanoniske v1-hash, kontrolleret ovenfor (kun hvis filen oplyser den).
    manifest["v1_input_file_sha256"] = f1_sha
    if claimed is not None:
        manifest["input_sha256"] = claimed
    if f3_sha:
        manifest["v3_input_file_sha256"] = f3_sha           # = elementernes sheet_sha256
    out = Path(a.out)
    body = json.dumps(manifest, ensure_ascii=False, sort_keys=True).encode("utf-8")
    write_private_replace(out, body)
    print(f"RELATION_EXTRACT_OK elementer={stats['elementer']} parkeret={json.dumps(stats['parkeret'])} "
          f"pr_praedikat={json.dumps(stats['pr_praedikat'])}")
    print(f"  manifest_fil_sha256 {hashlib.sha256(body).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
