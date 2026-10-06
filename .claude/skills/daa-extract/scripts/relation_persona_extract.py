#!/usr/bin/env python3
"""Trin 5b: deterministisk udtræk af ægtefællens navn og år fra eksisterende relationspåstande.

Input er serverens (red_relation_persona_input). Output er writerens manifest. Ingen modelkald.
Scriptet printer kun tal og hashes; filerne indeholder navne og skrives 0600 under ~/.private/5b/."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

PROFILE = "relation-persona-2018-20-v1"
# Profilens markører (versioneret: ændres de, når der er skrevet data med profilen, skal PROFILE have ny version).
# 2018-20-formen (målt 6/10 på 248 ægteskabspåstande): »Gift <dato> med <navn>« (134) eller påstanden
# begynder direkte med navnet (110); fødsel/død skrives med * og † (f./d. accepteres også).
GIFT = re.compile(r"^\s*gift\b", re.IGNORECASE)
MED = re.compile(r"\bmed\s+", re.IGNORECASE)
UPPER = re.compile(r"[A-ZÆØÅÀ-Þ]")
# Navnet slutter ved komma, semikolon, parentes, år-tegn, »til <gods>« (ikke navn), tankestreg eller slut.
# Bart »af« afskærer IKKE (»greve af Rosenborg«); forældremarkører ligger i PARENTS.
NAME_END = re.compile(r",|;|\(|\*|†|\s(?:til|f\.|d\.|født|død)\s|\s-\s|\s(?:datter|søn)\s+af\b|\.\s*$|$")
PARENTS = re.compile(r"(?:\b[ds]\.\s+af\b|\bdatter af\b|\bsøn af\b)")
BIRTH = re.compile(r"(?:\*|\bf\.|\bfødt\b)\s*[^,;()]*?\b(\d{4})\b")
DEATH = re.compile(r"(?:†|(?:^|[\s,])d\.(?!\s+af\b)|\bdød\b)\s*[^,;()]*?\b(\d{4})\b")
LETTER = re.compile(r"[A-Za-zÀ-ÿ]")
MAX_NAME_WORDS = 8
MAX_TITLE_WORDS = 6


def _park(stats: Counter, reason: str) -> None:
    stats[reason] += 1


def _name(raw: str):
    m = MED.search(raw)
    if m:
        start = m.end()
    elif GIFT.match(raw):
        return None                                   # »Gift 1975.« uden »med«: intet navn
    else:
        start = 0                                     # påstanden begynder med navnet (evt. efter titler)
    # Spring titler i små bogstaver over — også en kommasepareret opremsning (»cand.jur., kammerherre«),
    # målt 6/10: 39 tilfælde. Titelløbet må ikke rumme cifre, ;()*† eller over MAX_TITLE_WORDS ord.
    u = UPPER.search(raw, start)
    if u is None:
        return None
    titel = raw[start:u.start()]
    if any(ch in titel for ch in ";()*†") or re.search(r"\d", titel) or len(titel.split()) > MAX_TITLE_WORDS:
        return None
    start = u.start()
    end_m = NAME_END.search(raw, start)
    end = end_m.start() if end_m else len(raw)
    name = raw[start:end].rstrip()
    if not LETTER.search(name) or len(name.split()) > MAX_NAME_WORDS:
        return None
    return start, start + len(name)


def _years(segment: str):
    cut = PARENTS.search(segment)
    own = segment[:cut.start()] if cut else segment
    births, deaths = BIRTH.findall(own), DEATH.findall(own)
    if len(births) > 1 or len(deaths) > 1:
        return "tvetydige_aar"
    return (births[0] if births else None, deaths[0] if deaths else None)


def extract_rows(rows: list[dict]) -> tuple[dict, dict]:
    parked: Counter = Counter()
    candidates: dict[str, dict] = {}
    for r in rows:
        clauses = r["clauses"]
        if not r["principal_ok"]:
            _park(parked, "ingen_hovedperson"); continue
        if r["supporting_count"] != 1:
            _park(parked, "flere_klausuler"); continue
        if len(clauses) != 1:
            _park(parked, "klausul_ikke_gaeldende"); continue
        c, raw = clauses[0], r["raw"]
        text = c["verbatim_text"]
        n = text.count(raw) if raw else 0
        if n == 0:
            _park(parked, "ikke_ordret"); continue
        if n > 1:
            _park(parked, "tvetydigt_spaend"); continue
        span_from = text.index(raw)
        payload = {"birth_raw": None, "clause_observation_id": c["observation_id"], "clause_set_seq": c["clause_set_seq"],
                   "clause_set_sha256": c["clause_set_sha256"], "death_raw": None,
                   "interpretation_key": r["interpretation_key"], "interpretation_version": r["interpretation_version"],
                   "marriage_ordinal": None, "name_from": None, "name_to": None,
                   "post_offset": c["post_char_from"] + span_from, "predicate": r["predicate"], "profile": PROFILE,
                   "span_from": span_from, "span_to": span_from + len(raw)}
        if r["predicate"] == "relation.marriage":
            if r["marriage_ordinal"] is None:
                _park(parked, "intet_nummer"); continue
            nm = _name(raw)
            if nm is None:
                _park(parked, "intet_navn"); continue
            years = _years(raw[nm[1]:])
            if years == "tvetydige_aar":
                _park(parked, "tvetydige_aar"); continue
            payload.update(marriage_ordinal=r["marriage_ordinal"], name_from=span_from + nm[0], name_to=span_from + nm[1],
                           birth_raw=years[0], death_raw=years[1])
        candidates["relation-persona:" + r["interpretation_key"]] = payload
    # Uadskillelige dubletter (spec §5.1): samme post, prædikat, post_offset og spændlængde.
    groups: Counter = Counter()
    rec = {r["interpretation_key"]: r["record_key"] for r in rows}
    sig = {k: (rec[p["interpretation_key"]], p["predicate"], p["post_offset"], p["span_to"] - p["span_from"])
           for k, p in candidates.items()}
    groups.update(sig.values())
    elements = {}
    for k, p in candidates.items():
        if groups[sig[k]] > 1:
            _park(parked, "dublet")
        else:
            elements[k] = p
    manifest = {"expected_counts": {"person_creates": 0, "source_evidence": 0, "relation_personas": len(elements)},
                "authorized_elements": dict(sorted(elements.items()))}
    per = Counter(p["predicate"] for p in elements.values())
    return manifest, {"elementer": len(elements), "parkeret": dict(sorted(parked.items())), "pr_praedikat": dict(sorted(per.items()))}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    data = json.loads(Path(a.input).read_text(encoding="utf-8"))
    manifest, stats = extract_rows(data["input"])
    manifest["input_sha256"] = data["input_sha256"]
    out = Path(a.out)
    body = json.dumps(manifest, ensure_ascii=False, sort_keys=True).encode("utf-8")
    out.write_bytes(body); out.chmod(0o600)
    print(f"RELATION_EXTRACT_OK elementer={stats['elementer']} parkeret={json.dumps(stats['parkeret'])} "
          f"pr_praedikat={json.dumps(stats['pr_praedikat'])}")
    print(f"  manifest_fil_sha256 {hashlib.sha256(body).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
