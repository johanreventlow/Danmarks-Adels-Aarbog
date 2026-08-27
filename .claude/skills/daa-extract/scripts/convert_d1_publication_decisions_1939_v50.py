#!/usr/bin/env python3
"""Redigerbar beslutningsfil for fase D1's publicering af staged probander.

Følger projektets etablerede mønster (grænseflade-arbejdet, fase B, fase C0):
ÉN redigerbar tekstfil med ét token pr. linje og fail-closed strukturel
verifikation -- ikke et markdown-læseark og ikke håndredigeret JSON.

To tilstande:

- ``generate``: læser Task 1's udvælgelsesfil og skriver en tekstfil med én
  linje pr. proband, hver udfyldt med ``[PUBLICÉR]``.
- ``convert``: læser den redigerede tekstfil + SAMME udvælgelsesfil,
  verificerer byte-identitet bortset fra tokenet, og udleder id-listen til
  ``red_publicer_personer`` sammen med den forventede effekt.

**Den vigtigste regel:** et ``[VENT]`` som RPC'en alligevel ville overhøre
bliver afvist. RPC'ens UPDATE afstager enhver staged person med en
familie-kant til id-listen, så en tilbageholdt person, der deler familie med
en valgt, ville blive publiceret uanset tokenet. Målt mod prod 2026-08-19
gælder det 26 af de 44 -- det er hovedreglen, ikke en sjælden kant. En flade
der stiltiende ignorerer et valg er værre end ingen flade.

Rører aldrig databasen; autoriserer ingenting.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

VALID_TOKENS = ("[PUBLICÉR]", "[VENT]")
DEFAULT_TOKEN = "[PUBLICÉR]"

INSTRUCTIONS = """\
# DAA 1939 — fase D1: publicering af {n} staged probander
#
# Ret KUN tokenet i den firkantede parentes forrest på hver linje.
# Alt andet på linjen er låst og verificeres byte-for-byte ved indlæsning.
#
#   [PUBLICÉR]  gør personen offentligt synlig
#   [VENT]      hold personen tilbage til en senere runde
#
# Publicering trækker personens ægtefælle-STUBS med sig — det er med vilje,
# så du ikke får et ægteskab med en usynlig part. Linjen viser hvilke.
#
# »KOBLET til valgt« betyder at personen deler familie med en anden person
# på listen. Sådan et par kan ikke skilles ad: holder du den ene tilbage
# uden den anden, publicerer databasen den alligevel. Vælg [VENT] på BEGGE,
# eller lad dem begge stå.
#
# Ingen af valgene skriver noget endnu — det sker i en særskilt runde, som
# du godkender for sig.
"""

# Accenttegn SKAL med i tokenklassen: É i [PUBLICÉR] ville ellers falde
# uden for, og hele arket blev tomt ved konvertering. (Samme klasse fælde som
# de manglende cifre i fase C0's [C3].)
_DECISION_HEAD_RE = re.compile(r"^(\[[A-ZÆØÅÉ0-9]+\])([ \t]+)(P\d{2})(?=[ \t])")


def _fail(code: str) -> None:
    print(code, file=sys.stderr)
    sys.exit(2)


def assign_pids(selected: List[Dict[str, Any]]) -> Dict[int, str]:
    """P-id'er er en ren funktion af udvælgelsesfilen -- aldrig af den
    redigerede tekst. Mennesket vælger token, ikke identitet."""
    ordered = sorted(selected, key=lambda r: r["person_id"])
    return {r["person_id"]: "P{:02d}".format(i)
            for i, r in enumerate(ordered, start=1)}


def render_line(record: Dict[str, Any], pid: str, token: str,
                selected_ids: set) -> str:
    """Skelner mellem partnere der er STUBS (følger passivt med) og partnere
    der selv er VALGTE (binder de to linjer sammen: holdes den ene tilbage
    uden den anden, overhører RPC'en tokenet)."""
    partner_ids = record["partner_ids"]
    stubs = [p for p in partner_ids if p not in selected_ids]
    koblede = [p for p in partner_ids if p in selected_ids]
    dele = []
    if stubs:
        dele.append("stub følger med: " + ", ".join(str(p) for p in stubs))
    if koblede:
        dele.append("KOBLET til valgt: " + ", ".join(str(p) for p in koblede))
    if not dele:
        dele.append("ingen partner følger med")
    tvaer = " [samme_som 2020]" if record["samme_som_2020"] else ""
    side = record["side"] if record["side"] else "?"
    return "{}  {}  s.{}  {} ({} fakta){}  |  {}".format(
        token, pid, side, record["visning_navn"], record["fakta"], tvaer,
        "  |  ".join(dele))


def render_document(selected: List[Dict[str, Any]],
                    tokens_by_person: Dict[int, str]) -> str:
    pids = assign_pids(selected)
    selected_ids = {r["person_id"] for r in selected}
    lines = [INSTRUCTIONS.format(n=len(selected)).rstrip("\n"), ""]
    for record in sorted(selected, key=lambda r: r["person_id"]):
        lines.append(render_line(record, pids[record["person_id"]],
                                 tokens_by_person[record["person_id"]],
                                 selected_ids))
    return "\n".join(lines) + "\n"


def generate_document(selection_doc: Dict[str, Any]) -> str:
    selected = selection_doc.get("selected")
    if not isinstance(selected, list) or not selected:
        _fail("D1_DECISIONS_SELECTION_INVALID")
    return render_document(selected,
                           {r["person_id"]: DEFAULT_TOKEN for r in selected})


def recompute_partners(selection_doc: Dict[str, Any],
                       chosen_ids: List[int]) -> List[int]:
    """Partnere udledes af de VALGTE id'er alene.

    Holdes en proband tilbage, må dens stub-partner ikke publiceres i dens
    sted -- med mindre en anden valgt proband også deler familie med
    partneren. Det spejler RPC'ens egen familie-klausul, scopet til
    udvalget."""
    chosen = set(chosen_ids)
    out = []
    for partner in selection_doc.get("predicted_partners", []):
        if chosen & set(partner["via_person_ids"]):
            out.append(partner["person_id"])
    return sorted(out)


def assert_vent_is_honourable(selection_doc: Dict[str, Any],
                              chosen_ids: List[int],
                              held_back_ids: List[int]) -> None:
    """Afvis et [VENT], som RPC'en alligevel ville overhøre.

    UPDATE'en afstager enhver staged person med en familie-kant til
    id-listen. Er en tilbageholdt person partner til en VALGT person, bliver
    hen publiceret uanset tokenet -- og fladen ville have løjet."""
    chosen = set(chosen_ids)
    by_id = {r["person_id"]: r for r in selection_doc["selected"]}
    for held in sorted(held_back_ids):
        record = by_id.get(held)
        if record is None:
            continue
        via = sorted(chosen & set(record["partner_ids"]))
        if via:
            _fail("D1_DECISIONS_VENT_INEFFECTIVE:{}:via={}".format(
                held, ",".join(str(v) for v in via)))


def _parse_positional(line: str) -> Optional[Tuple[str, str]]:
    """Udtræk (token, P-id) fra en beslutningslinje.

    Tokenfeltets udfyldning er bevidst IKKE en del af kontrakten: at erstatte
    ``[PUBLICÉR]`` med det kortere ``[VENT]`` flytter kolonnen, og det er
    præcis hvad en menneskelig redigering gør."""
    match = _DECISION_HEAD_RE.match(line)
    if match is None:
        return None
    return match.group(1), match.group(3)


def _canonical_for_compare(line: str) -> str:
    """Kollaps kun whitespace-løbet mellem token og P-id."""
    match = _DECISION_HEAD_RE.match(line)
    if match is None:
        return line
    return match.group(1) + " " + line[match.end(2):]


def convert_edited_document(text: str,
                            selection_doc: Dict[str, Any]) -> Dict[str, Any]:
    selected = selection_doc.get("selected")
    if not isinstance(selected, list) or not selected:
        _fail("D1_DECISIONS_SELECTION_INVALID")
    pids = assign_pids(selected)
    person_by_pid = {pid: person_id for person_id, pid in pids.items()}

    edited_lines = text.split("\n")
    chosen_token: Dict[int, str] = {}
    seen: List[str] = []
    for number, line in enumerate(edited_lines, start=1):
        parsed = _parse_positional(line)
        if parsed is None:
            continue
        token, pid = parsed
        if token not in VALID_TOKENS:
            _fail("D1_DECISIONS_TOKEN_INVALID:line={}:token={}".format(number, token))
        if pid not in person_by_pid:
            _fail("D1_DECISIONS_PID_UNKNOWN:line={}:pid={}".format(number, pid))
        if pid in seen:
            _fail("D1_DECISIONS_PID_DUPLICATE:line={}:pid={}".format(number, pid))
        seen.append(pid)
        chosen_token[person_by_pid[pid]] = token

    if len(seen) != len(selected):
        _fail("D1_DECISIONS_LINE_COUNT_UNEXPECTED:{}:{}".format(
            len(seen), len(selected)))

    # Genskab dokumentet med MENNESKETS tokens og kræv byte-identitet.
    regenerated = render_document(selected, chosen_token).split("\n")
    if len(regenerated) != len(edited_lines):
        _fail("D1_DECISIONS_LINE_COUNT_MISMATCH:{}:{}".format(
            len(edited_lines), len(regenerated)))
    for number, (edited, expected) in enumerate(zip(edited_lines, regenerated), start=1):
        if _canonical_for_compare(edited) != _canonical_for_compare(expected):
            _fail("D1_DECISIONS_LINE_MODIFIED:line={}".format(number))

    person_ids = sorted(p for p, t in chosen_token.items() if t == DEFAULT_TOKEN)
    held_back = sorted(p for p, t in chosen_token.items() if t == "[VENT]")
    assert_vent_is_honourable(selection_doc, person_ids, held_back)
    partners = recompute_partners(selection_doc, person_ids)

    return {
        "schema_version": "1.0",
        "generator": "convert_d1_publication_decisions_1939_v50.py:v1",
        "person_ids": person_ids,
        "held_back": held_back,
        "predicted_partners": partners,
        "expected_unstaged_total": len(person_ids) + len(partners),
        "staged_total": selection_doc.get("counts", {}).get("staged_total"),
    }


def _load(path: str, failure_code: str) -> Dict[str, Any]:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        _fail(failure_code)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)

    gen = sub.add_parser("generate")
    gen.add_argument("--selection", required=True)
    gen.add_argument("--output", required=True)

    conv = sub.add_parser("convert")
    conv.add_argument("--selection", required=True)
    conv.add_argument("--decisions", required=True)
    conv.add_argument("--output", required=True)

    args = parser.parse_args(argv)
    output = Path(args.output)
    if output.exists():
        _fail("D1_DECISIONS_OUTPUT_EXISTS")
    selection = _load(args.selection, "D1_DECISIONS_SELECTION_UNREADABLE")

    if args.mode == "generate":
        output.write_text(generate_document(selection), encoding="utf-8")
        return 0

    try:
        edited = Path(args.decisions).read_text(encoding="utf-8")
    except OSError:
        _fail("D1_DECISIONS_SHEET_UNREADABLE")
    result = convert_edited_document(edited, selection)
    output.write_text(
        json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
