#!/usr/bin/env python3
"""Menneskeark for C0's efterkørsel — token pr. linje, byte-låst kontekst.

Følger husets grænseflade-mønster: ret KUN tokenet i den firkantede parentes;
alt andet på linjen verificeres byte-for-byte ved indlæsning. Anbefalingerne
er udfyldt på forhånd, så en urørt linje betyder "enig".

Målt 2026-08-21 er der otte flag i alt, alle ``hyphen_unproven``, fordelt på
fire personer. Fase B havde 178 til sammenligning.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
from typing import Any, Dict, List

DEFAULT_ACTION = {"hyphen_unproven": "merge"}
TOKEN_BY_ACTION = {"merge": "[MERGE]", "keep": "[KEEP] "}

HEADER = """\
# DAA 1939 — C0's efterkørsel: ni record-koblinger
#
# Ret KUN tokenet i den firkantede parentes forrest på hver linje.
# Alt andet på linjen er låst og verificeres byte-for-byte ved indlæsning.
#
# PERSON-linjer — skal koblingen udføres?
#   [ACCEPT] erstat personens narrativ og opret bindingen
#   [AFVIS]  spring denne person over (de øvrige kører alligevel)
#
# ORDDELING-linjer — er de to stumper ét ord?
#   [MERGE]  Revent- + low  ->  Reventlow
#   [KEEP]   bevar bindestregen (ægte kompositum)
#
# Anbefalingerne er UDFYLDT. Lad en linje stå, hvis du er enig.
# Intet skrives til databasen her — det sker i en særskilt runde, du godkender.
"""


def review_sequence(flags_doc: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Én autoritativ sekvens for både rendering og positionel parsing.

    Hvert beslutningspunkt bærer sin eksakte, byte-låste hale. Overskrifter
    er med i samme sekvens, så rendererens grupperingsorden heller ikke kan
    drive fra konverterens positionssemantik.
    """
    sequence: List[Dict[str, Any]] = []
    for op in flags_doc["operations"]:
        pid = op["person_id"]
        n_flag = len(op["flags"])
        sequence.append({
            "type": "heading",
            "text": "== PERSON %d — s.%d — %d tegn — %s ==" % (
                pid, op["page_from"], len(op["default_text"]),
                "%d orddeling(er) at afgøre" % n_flag
                if n_flag else "ingen valg; teksten er allerede korrekt"),
        })
        sequence.append({
            "type": "person",
            "id": pid,
            "tail": "%d  %s" % (pid, op["source_record_key"]),
        })
        for flag in op["flags"]:
            if flag["kind"] not in DEFAULT_ACTION:
                # Maalingen 2026-08-21 gav kun hyphen_unproven, men det er en
                # egenskab ved DATA, ikke ved koden. En ny flagtype skal give
                # en laesbar fejl, ikke en KeyError midt i en render.
                raise SystemExit("C0F_REVIEW_FLAG_KIND_UNKNOWN:" + flag["kind"])
            sequence.append({
                "type": "flag",
                "id": flag["flag_id"],
                "kind": flag["kind"],
                "tail": "%s  |  %s" % (
                    flag["flag_id"], flag["context"].replace("\n", "\\n")),
            })
    return sequence


def render_review(flags_doc: Dict[str, Any], flags_sha256: str) -> str:
    """Render a review sheet bound to the exact raw flags bytes."""
    if (not isinstance(flags_sha256, str) or len(flags_sha256) != 64
            or any(char not in "0123456789abcdef" for char in flags_sha256)):
        raise SystemExit("C0F_REVIEW_FLAGS_SHA256_INVALID")
    lines = ["# DAA 1939 — C0's efterkørsel: ni record-koblinger", "# flags_sha256: " + flags_sha256, *HEADER.splitlines()[1:]]
    for item in review_sequence(flags_doc):
        if item["type"] == "heading":
            lines.extend(("", item["text"]))
        elif item["type"] == "person":
            lines.append("[ACCEPT] " + item["tail"])
        else:
            token = TOKEN_BY_ACTION[DEFAULT_ACTION[item["kind"]]]
            lines.append("%s %s" % (token, item["tail"]))
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flags", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    out = pathlib.Path(args.output)
    if out.exists():
        raise SystemExit("C0F_REVIEW_OUTPUT_EXISTS")
    flags_bytes = pathlib.Path(args.flags).read_bytes()
    doc = json.loads(flags_bytes.decode("utf-8"))
    out.write_text(render_review(doc, hashlib.sha256(flags_bytes).hexdigest()), encoding="utf-8")
    total = sum(len(op["flags"]) for op in doc["operations"])
    print("personer=%d orddelingsvalg=%d" % (len(doc["operations"]), total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
