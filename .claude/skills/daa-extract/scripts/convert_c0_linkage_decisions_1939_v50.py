#!/usr/bin/env python3
"""Redigerbar beslutningsfil for fase C0's 41 kilderecords.

Følger projektets etablerede mønster fra grænseflade- og fase-B-arbejdet:
ÉN redigerbar tekstfil med ét token pr. linje og fail-closed strukturel
verifikation -- ikke et markdown-læseark og ikke håndredigeret JSON.

To tilstande:

- ``generate``: læser kandidatfilen (Task 3's output) og skriver en
  tekstfil med én linje pr. record, grupperet i fem sektioner med de
  mistænkelige øverst, hver linje udfyldt med en anbefalet ``[TOKEN]``.
- ``convert``: læser den redigerede tekstfil + SAMME kandidatfil og
  verificerer at hver linje er byte-identisk med den friskt genskabte form
  bortset fra det firkantede token -- enhver anden redigering (kontekst,
  R-id, person-id, sektionsoverskrifter, linjeantal, rækkefølge) afbryder
  med det stødende linjenummer.

R-id -> record-nøgle er en ren funktion af kandidatfilens egen liste
(sorteret på ``new_record_key``, nummereret fra 1). ``convert`` stoler
ALDRIG på den redigerede tekst for identitet, kun for tokenvalget.

Rører aldrig databasen; autoriserer ingenting.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

VALID_TOKENS = ("[KOBL]", "[NY]", "[C3]", "[SPØRG]", "[FÆRDIG]")

DEFAULT_TOKEN_BY_CLASS = {
    "kobling": "[KOBL]",
    "gennemgang": "[SPØRG]",
    "for_kort": "[SPØRG]",
    "sammenlaegning": "[C3]",
    "aegte_ny": "[NY]",
    "allerede_materialiseret": "[FÆRDIG]",
}

# Mistænkelige først: det mennesket skal tage stilling til, står øverst;
# det maskinen er sikker på, står nederst.
SECTION_ORDER = ["gennemgang", "for_kort", "sammenlaegning", "kobling", "aegte_ny",
                 "allerede_materialiseret"]
SECTION_TITLES = {
    "gennemgang": "KRÆVER STILLINGTAGEN ({n}) — én kandidat, men kun ét signal",
    "for_kort": "FOR KORT TIL AT MATCHE ({n}) — kandidater er ordsammenfald, ikke forslag",
    "sammenlaegning": "SAMMENLÆGNING ({n}) — spærret for kobling, afgøres i C3",
    "kobling": "FORESLÅET KOBLING ({n}) — én kandidat, flere signaler enige",
    "aegte_ny": "INGEN KANDIDAT ({n}) — ingen tekst i prod ligner",
    "allerede_materialiseret":
        "ALLEREDE FÆRDIG ({n}) — blev til personer i task 25; ingen handling",
}

INSTRUCTIONS = """\
# DAA 1939 — fase C0: afgørelser for de 41 »ægte nye« kilderecords
#
# Ret KUN tokenet i den firkantede parentes forrest på hver linje.
# Alt andet på linjen er låst og verificeres byte-for-byte ved indlæsning.
#
#   [KOBL]   kobl recorden til den viste person (kun hvor en kandidat vises)
#   [NY]     recorden er en ægte ny kilderecord uden modstykke i basen
#   [C3]     fragment/alias — udskydes til sammenlægningsrunden C3
#   [SPØRG]  kan ikke afgøres her; tages op særskilt
#   [FÆRDIG] recorden er allerede materialiseret som person; ingen handling
#
# Anbefalingerne er UDFYLDT på forhånd. Lad en linje stå, hvis du er enig.
# Ingen af valgene skriver noget til databasen — det sker først i en
# særskilt runde, som du godkender for sig.
"""

# Cifre SKAL med i tokenklassen: [C3] indeholder et. Uden dem blev
# C3-linjerne slet ikke genkendt som beslutningslinjer, og et helt sektions
# udfald ville tavst mangle i konverteringen.
_DECISION_HEAD_RE = re.compile(r"^(\[[A-ZÆØÅ0-9]+\])([ \t]+)(R\d{2})(?=[ \t])")


def _fail(code: str) -> None:
    print(code, file=sys.stderr)
    sys.exit(2)


def assign_rids(records: List[Dict[str, Any]]) -> Dict[str, str]:
    """R-id'er er en ren funktion af kandidatfilen -- aldrig af den
    redigerede tekst. Mennesket vælger token, ikke identitet."""
    ordered = sorted(records, key=lambda r: r["new_record_key"])
    return {r["new_record_key"]: "R{:02d}".format(i)
            for i, r in enumerate(ordered, start=1)}


def _flat(text: str, limit: int = 70) -> str:
    collapsed = " ".join(text.split())
    return collapsed[:limit] + ("…" if len(collapsed) > limit else "")


def _signal_marks(candidate: Dict[str, Any]) -> str:
    navn = "navn✓" if candidate["name_signal"] else "navn✗"
    side = ("side✓" if candidate["page_signal"] is True
            else "side✗" if candidate["page_signal"] is False else "side?")
    return navn + ", " + side


def render_line(record: Dict[str, Any], rid: str, token: str) -> str:
    pages = record.get("pages")
    page_text = ("s.{}-{}".format(pages["page_from"], pages["page_to"])
                 if pages else "s.?")
    cands = record["candidates"]
    if record["classification"] == "for_kort":
        names = ", ".join("{} {}".format(c["person_id"], c["visning_navn"])
                          for c in cands) or "ingen"
        context = "[{} tegn] {}  |  ordsammenfald: {}".format(
            record["skeleton_len"], _flat(record["verbatim_text"]), names)
    elif not cands:
        context = "ingen kandidat  |  {}".format(_flat(record["verbatim_text"]))
    elif len(cands) == 1:
        c = cands[0]
        staged = " [staged]" if c["staged"] else ""
        context = "-> {} {}{}  (dækning {:.2f}, {}, {})".format(
            c["person_id"], c["visning_navn"], staged, c["coverage"],
            c["containment"], _signal_marks(c))
    else:
        ids = ", ".join("{} {}".format(c["person_id"], c["visning_navn"])
                        for c in cands)
        context = "-> {} kandidater: {}".format(len(cands), ids)
    return "{}  {}  {}  {}".format(token, rid, page_text, context)


def partition_sections(records: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    sections: Dict[str, List[Dict[str, Any]]] = {key: [] for key in SECTION_ORDER}
    for record in sorted(records, key=lambda r: r["new_record_key"]):
        classification = record["classification"]
        if classification not in sections:
            _fail("C0_DECISIONS_UNKNOWN_CLASSIFICATION:{}".format(classification))
        sections[classification].append(record)
    return sections


def render_document(records: List[Dict[str, Any]],
                    tokens_by_key: Dict[str, str]) -> str:
    rids = assign_rids(records)
    sections = partition_sections(records)
    lines: List[str] = [INSTRUCTIONS.rstrip("\n")]
    for key in SECTION_ORDER:
        group = sections[key]
        lines.append("")
        lines.append("== " + SECTION_TITLES[key].format(n=len(group)) + " ==")
        for record in group:
            lines.append(render_line(record, rids[record["new_record_key"]],
                                     tokens_by_key[record["new_record_key"]]))
    return "\n".join(lines) + "\n"


def default_tokens(records: List[Dict[str, Any]]) -> Dict[str, str]:
    tokens: Dict[str, str] = {}
    for record in records:
        token = DEFAULT_TOKEN_BY_CLASS.get(record["classification"])
        if token is None:
            _fail("C0_DECISIONS_UNKNOWN_CLASSIFICATION:{}".format(record["classification"]))
        tokens[record["new_record_key"]] = token
    return tokens


def generate_document(candidates_doc: Dict[str, Any]) -> str:
    records = candidates_doc.get("records")
    if not isinstance(records, list) or not records:
        _fail("C0_DECISIONS_CANDIDATES_INVALID")
    return render_document(records, default_tokens(records))


# ---------------------------------------------------------------------------
# convert
# ---------------------------------------------------------------------------

def _parse_positional(line: str) -> Optional[Tuple[str, str]]:
    """Udtræk (token, R-id) fra en beslutningslinje.

    Tokenfeltets udfyldning er bevidst IKKE en del af kontrakten: at
    erstatte ``[SPØRG]`` med det kortere ``[NY]`` flytter kolonnen, og det
    er præcis hvad en menneskelig redigering gør. Alt efter R-id'et er
    byte-låst."""
    match = _DECISION_HEAD_RE.match(line)
    if match is None:
        return None
    return match.group(1), match.group(3)


def _canonical_for_compare(line: str) -> str:
    """Kollaps kun whitespace-løbet mellem token og R-id."""
    match = _DECISION_HEAD_RE.match(line)
    if match is None:
        return line
    return match.group(1) + " " + line[match.end(2):]


def convert_edited_document(text: str, candidates_doc: Dict[str, Any]) -> Dict[str, Any]:
    records = candidates_doc.get("records")
    if not isinstance(records, list) or not records:
        _fail("C0_DECISIONS_CANDIDATES_INVALID")
    by_key = {r["new_record_key"]: r for r in records}
    rids = assign_rids(records)
    key_by_rid = {rid: key for key, rid in rids.items()}

    edited_lines = text.split("\n")
    chosen: Dict[str, str] = {}
    seen_rids: List[str] = []
    for number, line in enumerate(edited_lines, start=1):
        parsed = _parse_positional(line)
        if parsed is None:
            continue
        token, rid = parsed
        if token not in VALID_TOKENS:
            _fail("C0_DECISIONS_TOKEN_INVALID:line={}:token={}".format(number, token))
        if rid not in key_by_rid:
            _fail("C0_DECISIONS_RID_UNKNOWN:line={}:rid={}".format(number, rid))
        if rid in seen_rids:
            _fail("C0_DECISIONS_RID_DUPLICATE:line={}:rid={}".format(number, rid))
        seen_rids.append(rid)
        chosen[key_by_rid[rid]] = token

    if len(seen_rids) != len(records):
        _fail("C0_DECISIONS_LINE_COUNT_UNEXPECTED:{}:{}".format(
            len(seen_rids), len(records)))

    # Genskab dokumentet med MENNESKETS tokens og kræv byte-identitet.
    # Alt andet end tokenet -- kontekst, person-id, sider, overskrifter,
    # rækkefølge -- skal stemme, ellers er arket redigeret på en måde der
    # ikke kan tolkes entydigt.
    regenerated = render_document(records, chosen).split("\n")
    if len(regenerated) != len(edited_lines):
        _fail("C0_DECISIONS_LINE_COUNT_MISMATCH:{}:{}".format(
            len(edited_lines), len(regenerated)))
    for number, (edited, expected) in enumerate(zip(edited_lines, regenerated), start=1):
        if _canonical_for_compare(edited) != _canonical_for_compare(expected):
            _fail("C0_DECISIONS_LINE_MODIFIED:line={}".format(number))

    decisions = []
    counts = {token: 0 for token in VALID_TOKENS}
    for key in sorted(chosen):
        token = chosen[key]
        record = by_key[key]
        person_id = None
        if token == "[KOBL]":
            if record["classification"] == "sammenlaegning":
                _fail("C0_DECISIONS_KOBL_ON_BLOCKED_RECORD:{}".format(key))
            if record["classification"] == "allerede_materialiseret":
                # Personen findes, og dens narrativ har allerede en binding
                # (UNIQUE). En kobling ville kollidere, ikke tilføje noget.
                _fail("C0_DECISIONS_KOBL_ON_MATERIALIZED_RECORD:{}".format(key))
            if not record["candidates"]:
                _fail("C0_DECISIONS_KOBL_WITHOUT_CANDIDATE:{}".format(key))
            if record["classification"] == "for_kort" and len(record["candidates"]) > 1:
                # En for_kort-post kalder selv sine kandidater ordsammenfald.
                # Med flere af dem kan arket ikke udtrykke HVILKEN der menes,
                # og et ja ville tavst binde til den øverste støjmatch.
                _fail("C0_DECISIONS_KOBL_ON_AMBIGUOUS_SHORT_RECORD:{}".format(key))
            # Person-id'et kommer fra kandidatfilen, aldrig fra den
            # redigerede tekst.
            person_id = record["candidates"][0]["person_id"]
        counts[token] += 1
        decisions.append({"new_record_key": key, "token": token,
                          "person_id": person_id,
                          "classification": record["classification"]})

    return {"schema_version": "1.0",
            "generator": "convert_c0_linkage_decisions_1939_v50.py:v1",
            "counts": counts, "decisions": decisions}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _load(path: str, failure_code: str) -> Dict[str, Any]:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        _fail(failure_code)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)

    gen = sub.add_parser("generate")
    gen.add_argument("--candidates", required=True)
    gen.add_argument("--output", required=True)

    conv = sub.add_parser("convert")
    conv.add_argument("--candidates", required=True)
    conv.add_argument("--decisions", required=True)
    conv.add_argument("--output", required=True)

    args = parser.parse_args(argv)
    output = Path(args.output)
    if output.exists():
        _fail("C0_DECISIONS_OUTPUT_EXISTS")
    candidates = _load(args.candidates, "C0_DECISIONS_CANDIDATES_UNREADABLE")

    if args.mode == "generate":
        output.write_text(generate_document(candidates), encoding="utf-8")
        return 0

    try:
        edited = Path(args.decisions).read_text(encoding="utf-8")
    except OSError:
        _fail("C0_DECISIONS_SHEET_UNREADABLE")
    result = convert_edited_document(edited, candidates)
    output.write_text(
        json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
