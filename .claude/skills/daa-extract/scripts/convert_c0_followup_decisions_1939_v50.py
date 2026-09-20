#!/usr/bin/env python3
"""Fail-closed konverter: menneskeark -> beslutnings-JSON.

Alt andet end tokenet er byte-låst. En redigeret kontekst er terminal, ikke
noget der forsøges tolket: ellers kunne en utilsigtet ændring flytte et valg
til et andet sted i teksten uden at nogen opdagede det.

Valideringen er POSITIONEL, ikke et opslag på et ID læst AF linjen selv. Den
forventede linjesekvens og ``render_review`` kommer fra den SAMME
``review_sequence``-generator (person, så dens flag, i operations-rækkefølge),
og linje n i arket skal bære præcis den forventede hale for position n. Et opslag keyet på
et ID parset fra selve linjen ville kun bevise, at halen er *en* gyldig hale
et sted i dokumentet -- ikke at den hører til DENNE linje. Codex-review fandt
at man derved kunne bytte to linjers HALER om uden at nogen fejl blev rejst:
begge linjer så isoleret set gyldige ud, men en afvisning flyttede stiltiende
fra én person til en anden. Positionel sammenligning gør en sådan ombytning
terminal, fordi den flyttede hale ikke længere matcher SIN plads i sekvensen.

Fordi identiteten (person_id/flag_id) altid kommer fra positionen i
``flags_doc`` -- aldrig fra tekst parset ud af arket -- er der intet sted der
forsøger ``int()`` på brugerstyret tekst. Et ødelagt person-ID i arket bliver
derfor aldrig en rå ValueError/IndexError: enhver afvigelse fra den
forventede hale (inkl. et ugyldigt ID) fanges generisk som
C0F_REVIEW_LINE_TAMPERED, FØR noget forsøges parset ud af den.

Token-hale-grænsen er et EKSAKT PRÆFIKS-SÆT pr. position, genbrugt fra
byggemodulets ``TOKEN_BY_ACTION`` -- ikke "split ved første mellemrum og
stol på strip()". ``TOKEN_BY_ACTION["keep"]`` bærer et indlejret mellemrum
("[KEEP] ") for at holde kolonnerne linjede med "[MERGE]"; en ren
partition+strip-model ville enten acceptere vilkårlig ekstra whitespace
efter tokenet (genåbner "byte-låst" til at betyde "trimmet") eller fejle på
en fuldstændig urørt maskinel KEEP-standardlinje, afhængigt af om strip()
bruges. Her udledes den PRÆCISE, forventede mellemrums-bredde for hver
position af dens egen standardhandling, og BEGGE ord-varianter (MERGE/KEEP)
skal matche den SAMME bredde -- for mennesket redigerer kun ordet i
parentesen, ikke den omkringliggende afstand.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib
import re
import sys
from typing import Any, Dict, List

_SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent


def _import_build():
    """Genbruger build-modulets DEFAULT_ACTION/TOKEN_BY_ACTION som ENESTE
    kilde til hvilke flag-typer der er kendte, og hvordan deres tokens er
    formateret. Reglerne genimplementeres ALDRIG: konverteren må ikke antage
    at rendereren allerede har passet på -- hvert led skal være selvstændigt
    fail-closed -- men den skal heller ikke risikere at drifte fra
    rendererens egne konstanter."""
    spec = importlib.util.spec_from_file_location(
        "build_c0_followup_review_1939_v50",
        _SCRIPTS_DIR / "build_c0_followup_review_1939_v50.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


_build_mod = _import_build()
DEFAULT_ACTION = _build_mod.DEFAULT_ACTION
TOKEN_BY_ACTION = _build_mod.TOKEN_BY_ACTION
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

# Person-linjer har ingen kolonne-udligning i render_review (formatstrengen
# er hardkodet "[ACCEPT] %d  %s") -- mellemrummet mellem token og hale er
# derfor ALTID ét, uanset om ordet er ACCEPT eller AFVIS.
_PERSON_BARE_WORD = {"[ACCEPT]": True, "[AFVIS]": False}
_PERSON_GAP = " "


def _bare_word(token_const: str) -> str:
    """"[MERGE]" -> "[MERGE]", "[KEEP] " -> "[KEEP]" -- selve det
    redigerbare ord i parentesen, uden det indlejrede udligningsmellemrum."""
    return token_const.rstrip(" ")


def _flag_gap_width(kind: str) -> int:
    """Mellemrums-bredden mellem token-ord og hale for DENNE positions egen
    standardhandling: render_review's literale format-mellemrum (1) plus et
    evt. indlejret udligningsmellemrum i selve token-konstanten."""
    canonical = TOKEN_BY_ACTION[DEFAULT_ACTION[kind]]
    return 1 + (len(canonical) - len(canonical.rstrip(" ")))


def _flag_prefixes(kind: str) -> Dict[str, str]:
    gap = " " * _flag_gap_width(kind)
    return {action: _bare_word(tok) + gap for action, tok in TOKEN_BY_ACTION.items()}


def _fail(code: str) -> None:
    raise SystemExit(code)


def _expected_sequence(flags_doc: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Brug rendererens fælles sekvenskilde, men uden overskriftsrækker."""
    return [dict(item, hale=item["tail"])
            for item in _build_mod.review_sequence(flags_doc)
            if item["type"] != "heading"]


def _match_prefix(line: str, prefixes: Dict[str, str]):
    """Finder det EKSAKTE præfiks (ord + korrekt udlignings-bredde for denne
    position) linjen starter med. Returnerer (handling, hale) eller
    (None, None) -- aldrig en gættet split, der senere skal valideres."""
    for action, prefix in prefixes.items():
        if line[:len(prefix)] == prefix:
            return action, line[len(prefix):]
    return None, None


def parse_review(text: str, flags_doc: Dict[str, Any],
                 flags_sha256: str) -> Dict[str, Any]:
    if not isinstance(flags_sha256, str) or _SHA256_RE.fullmatch(flags_sha256) is None:
        _fail("C0F_REVIEW_FLAGS_SHA256_INVALID")
    lines = text.splitlines()
    if len(lines) < 2 or lines[1] != "# flags_sha256: " + flags_sha256:
        _fail("C0F_REVIEW_FLAGS_SHA256_MISMATCH")
    expected = _expected_sequence(flags_doc)

    content_lines = [
        (number, line) for number, line in enumerate(lines, start=1)
        if line.strip() and not line.lstrip().startswith("#") and not line.startswith("==")
    ]

    decisions: Dict[str, str] = {}
    accepted: List[int] = []
    set_person = set()
    n = min(len(content_lines), len(expected))
    for pos in range(n):
        number, line = content_lines[pos]
        exp = expected[pos]
        if exp["type"] == "person":
            prefixes = {"accept": "[ACCEPT]" + _PERSON_GAP, "afvis": "[AFVIS]" + _PERSON_GAP}
            action, hale = _match_prefix(line, prefixes)
            if action is None:
                _fail("C0F_REVIEW_TOKEN_INVALID:line=%d:token=%s"
                      % (number, line.split(" ", 1)[0]))
            if hale != exp["hale"]:
                _fail("C0F_REVIEW_LINE_TAMPERED:line=%d" % number)
            pid = exp["id"]
            if pid in set_person:
                _fail("C0F_REVIEW_PERSON_DUPLICATE:line=%d" % number)
            set_person.add(pid)
            if action == "accept":
                accepted.append(pid)
        else:
            prefixes = _flag_prefixes(exp["kind"])
            action, hale = _match_prefix(line, prefixes)
            if action is None:
                _fail("C0F_REVIEW_TOKEN_INVALID:line=%d:token=%s"
                      % (number, line.split(" ", 1)[0]))
            if hale != exp["hale"]:
                _fail("C0F_REVIEW_LINE_TAMPERED:line=%d" % number)
            flag_id = exp["id"]
            if flag_id in decisions:
                _fail("C0F_REVIEW_FLAG_DUPLICATE:line=%d" % number)
            decisions[flag_id] = action

    if len(content_lines) > len(expected):
        _fail("C0F_REVIEW_LINE_UNEXPECTED:line=%d" % content_lines[len(expected)][0])

    if len(content_lines) < len(expected):
        missing = expected[len(content_lines):]
        missing_persons = sorted(str(e["id"]) for e in missing if e["type"] == "person")
        missing_flags = sorted(e["id"] for e in missing if e["type"] == "flag")
        if missing_persons:
            _fail("C0F_REVIEW_PERSON_MISSING:" + ",".join(missing_persons))
        _fail("C0F_REVIEW_FLAG_MISSING:" + ",".join(missing_flags))

    if not accepted:
        _fail("C0F_REVIEW_EMPTY")
    return {
        "decisions": decisions,
        "accepted_person_ids": sorted(accepted),
        "flags_sha256": flags_sha256,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", required=True)
    parser.add_argument("--flags", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    out = pathlib.Path(args.output)
    if out.exists():
        _fail("C0F_DECISIONS_OUTPUT_EXISTS")
    flags_bytes = pathlib.Path(args.flags).read_bytes()
    flags_doc = json.loads(flags_bytes.decode("utf-8"))
    result = parse_review(
        pathlib.Path(args.review).read_text(encoding="utf-8"), flags_doc,
        hashlib.sha256(flags_bytes).hexdigest())
    result["schema_version"] = "1939-v50-c0-followup-decisions-v2"
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    print("accepteret=%d afgjorte_orddelinger=%d" % (
        len(result["accepted_person_ids"]), len(result["decisions"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
