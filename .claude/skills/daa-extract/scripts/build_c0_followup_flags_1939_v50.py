#!/usr/bin/env python3
"""Normalisering og flag-udtræk for C0's efterkørsel.

C0's ``verbatim_text`` er RÅ OCR. Målt 2026-08-21 fejler alle ni records fase
B's slutinvarianter: alle har enlige linjeskift, syv har uopløste orddelinger,
1299 bærer ``### PAGE 0063 ###`` og 1297 trailing whitespace. Uden
normalisering ville fasen indføre rå tekst i en bestand af 551 rensede.

Reglerne genimplementeres ALDRIG: ``normalize_narrative_1939_v50`` importeres
som den ene kanoniske transform, præcis som fase B gjorde.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib
import sys
from typing import Any, Dict, List

_SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent

# De ni koblinger. 1017 er BEVIDST udeladt -- se spec'ens afsnit "Hvorfor 1017
# ikke er med": dens kobling ville slette ~92 tegn permanent.
PERSON_IDS = [963, 967, 978, 991, 992, 1296, 1297, 1298, 1299]

CONTEXT_RADIUS = 60


def _fail(code: str) -> None:
    raise SystemExit(code)


def _import_normalize():
    spec = importlib.util.spec_from_file_location(
        "normalize_narrative_1939_v50",
        _SCRIPTS_DIR / "normalize_narrative_1939_v50.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


_normalize_mod = _import_normalize()
normalize_narrative_v1 = _normalize_mod.normalize_narrative_v1
_LONE_NEWLINE_RE = _normalize_mod._LONE_NEWLINE_RE


def assert_invariants(text: str, context: str) -> None:
    """Fase B's slutinvarianter, genhaevdet efter normalisering."""
    if "### PAGE" in text:
        _fail("C0F_FLAGS_INVARIANT_PAGE_MARKER:" + context)
    if _LONE_NEWLINE_RE.search(text):
        _fail("C0F_FLAGS_INVARIANT_LONE_NEWLINE:" + context)
    if text != text.rstrip():
        _fail("C0F_FLAGS_INVARIANT_TRAILING_WS:" + context)
    if not text.strip():
        _fail("C0F_FLAGS_TEXT_EMPTY:" + context)


def _derive_record_by_person(decision_rows: List[Dict[str, Any]]) -> Dict[int, str]:
    """Udleder record_by_person af C0's EGNE afgoerelser -- aldrig af navne
    eller raekkefoelge. Kun [KOBL]-raekker taeller.

    Begge entydigheds-retninger haandhaeves HER, mens dubletterne stadig er
    synlige i raekkerne -- IKKE efter at de er samlet i en dict. En
    Dict[int, str] kan per definition ikke baere beviset for "der var to
    raekker med samme person_id": tildelingen record_by_person[pid] = key2
    overskriver record_by_person[pid] = key1 i stilhed, og funktionen der
    modtager den faerdige dict kan aldrig genopdage at der var to. Derfor
    KAN denne kontrol kun leve i selve udledningen, ikke som en pre-pass paa
    et allerede-bygget resultat -- et interface hvis type ikke kan udtrykke
    fejlen, kan heller ikke afvise den.

    C0F_FLAGS_DUPLICATE_RECORD_KEY daekker ALLE [KOBL]-raekker, ogsaa dem
    UDEN for PERSON_IDS (fx 1017, som er bevidst udeladt fordi dens kobling
    ville slette ~92 tegn permanent). En noegle delt mellem en scoped og en
    EKSKLUDERET person er lige saa farlig som mellem to scopede -- 963 ville
    faa 1017's tekst lige saa stiltiende som hvis det var 967's. Derfor sker
    scope-filtreringen (kun de ni i det returnerede map) FOERST EFTER
    kollisionskontrollen, ikke foer.

    C0F_FLAGS_DUPLICATE_PERSON_ID daekker derimod kun PERSON_IDS -- det er en
    kontrol paa VORES egen udvaelgelse (konkurrerer to raekker om en af de
    ni?), ikke paa hele afgoerelsesfilen.

    Begge felter paa selve raekken kraeves ogsaa til stede: en [KOBL]-raekke
    uden person_id eller new_record_key fejler terminalt her, ikke med en
    bar KeyError laengere nede.

    person_id skal vaere PRAECIS int -- ``type(pid) is int``, ikke
    ``isinstance``. To grunde: (1) ``int(963.9)`` afkorter stille til 963 og
    ville lade en ikke-heltallig vaerdi glide igennem konverteringen uden
    fejl; (2) ``bool`` er en underklasse af ``int`` i Python, saa
    ``isinstance(True, int)`` er ``True`` og ville lukke ``person_id: true``
    igennem som 1. Kontrollen SKAL sidde her, foer noget bruger pid -- at
    filtrere raa vaerdier mod PERSON_IDS foer konvertering (som den gamle
    main() gjorde) er ikke det samme forsvar; det forhindrer ikke en
    ikke-heltallig vaerdi der tilfaeldigvis konverterer til et scoped tal.
    """
    record_by_person: Dict[int, str] = {}
    key_owner: Dict[str, int] = {}
    for row in decision_rows or []:
        if row.get("token") != "[KOBL]":
            continue
        pid = row.get("person_id")
        if pid is None:
            _fail("C0F_FLAGS_KOBL_ROW_MISSING_PERSON_ID")
        if type(pid) is not int:
            _fail("C0F_FLAGS_KOBL_ROW_INVALID_PERSON_ID:%r" % (pid,))
        key = row.get("new_record_key")
        if not key:
            _fail("C0F_FLAGS_KOBL_ROW_MISSING_RECORD_KEY:%d" % pid)

        # Kollisionskontrollen foerst -- daekker ALLE [KOBL]-raekker.
        if key in key_owner and key_owner[key] != pid:
            _fail("C0F_FLAGS_DUPLICATE_RECORD_KEY:%s" % key)
        key_owner[key] = pid

        # Scope-filtrering EFTER kollisionskontrollen.
        if pid not in PERSON_IDS:
            continue
        if pid in record_by_person:
            _fail("C0F_FLAGS_DUPLICATE_PERSON_ID:%d" % pid)
        record_by_person[pid] = key
    return record_by_person


def build_flags_document(selection: Dict[str, Any], candidates: Dict[str, Any],
                         decision_rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    selected = selection.get("selected") or []
    ids = sorted(int(row["person_id"]) for row in selected)
    if ids != sorted(PERSON_IDS):
        _fail("C0F_FLAGS_IDS_INVALID")

    # Base-identiteten skal vaere til stede OG ikke-tom -- uden den kan et
    # manifest bygget mod rehearsal-basen ikke skelnes fra ét bygget mod prod.
    db_name = selection.get("database_name")
    if not db_name or not str(db_name).strip():
        _fail("C0F_FLAGS_DATABASE_NAME_MISSING")
    db_identity = selection.get("database_identity")
    if not db_identity or not str(db_identity).strip():
        _fail("C0F_FLAGS_DATABASE_IDENTITY_MISSING")

    record_by_person = _derive_record_by_person(decision_rows)

    recs = {r["new_record_key"]: r for r in candidates.get("records", [])}
    # Korpus = ALLE records' rå tekst. normalize_narrative_v1 bruger det til at
    # bevise sammentrækninger; et smallere korpus ville gøre flere orddelinger
    # "unproven" og dermed flytte maskinelle afgørelser over på mennesket.
    corpus = "\n".join(r["verbatim_text"] for r in candidates.get("records", []))

    by_person = {int(row["person_id"]): row for row in selected}
    operations: List[Dict[str, Any]] = []
    flag_counts: Dict[str, int] = {}
    seen_flag_ids = set()

    for pid in sorted(PERSON_IDS):
        row = by_person[pid]
        key = record_by_person.get(pid)
        if key is None or key not in recs:
            _fail("C0F_FLAGS_RECORD_MISSING:%d" % pid)
        record = recs[key]

        # Identitetskontrol: beviser at vi rammer den rigtige post. Vi SKRIVER
        # ikke side (p_side=NULL), men en afvigelse betyder at recorden og
        # narrativet ikke er samme trykte post.
        side = row.get("side")
        if side is None:
            _fail("C0F_FLAGS_SIDE_MISSING:%d" % pid)
        page_from = int(record["pages"]["page_from"])
        if str(side).strip() != str(page_from):
            _fail("C0F_FLAGS_SIDE_MISMATCH:%d:observed=%s:expected=%d"
                  % (pid, side, page_from))

        raw = record["verbatim_text"]
        result = normalize_narrative_v1(raw, corpus)
        default_text = result["text"]
        assert_invariants(default_text, "person=%d" % pid)

        flags = []
        for flag in result["flags"]:
            flag_id = "%s:%d:%s" % (key, flag["char_offset"], flag["kind"])
            if flag_id in seen_flag_ids:
                _fail("C0F_FLAGS_ID_COLLISION:" + flag_id)
            seen_flag_ids.add(flag_id)
            off = flag["char_offset"]
            lo, hi = max(0, off - CONTEXT_RADIUS), min(len(raw), off + CONTEXT_RADIUS)
            flags.append({
                "flag_id": flag_id, "kind": flag["kind"],
                "char_offset": off, "context": raw[lo:hi],
                "person_id": pid, "source_record_key": key,
            })
            flag_counts[flag["kind"]] = flag_counts.get(flag["kind"], 0) + 1
        flags.sort(key=lambda f: f["flag_id"])

        operations.append({
            "person_id": pid,
            "narrative_id": int(row["narrative_id"]),
            "old_sha256": row["old_sha256"],
            "source_record_key": key,
            "page_from": page_from,
            "default_text": default_text,
            "flags": flags,
        })

    return {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "generator": "build_c0_followup_flags_1939_v50.py",
        # Base-identiteten baeres HELE vejen til apply. Uden den kan en eksport
        # taget mod rehearsal-basen fode et manifest, der koeres mod prod --
        # praecis det D2's D2_APPLY_DATABASE_MISMATCH spaerrer for. Genbruger
        # db_name/db_identity (valideret ovenfor) i stedet for at laese
        # selection igen -- validering og emission skal vaere SAMME vaerdi.
        "database_name": db_name,
        "database_identity": db_identity,
        "operations": operations,
        "flag_counts": flag_counts,
    }


def _sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selection", required=True)
    parser.add_argument("--candidates", required=True)
    parser.add_argument("--decisions", required=True,
                        help="C0's afgoerelsesfil (c0-afgoerelser.json)")
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    out = pathlib.Path(args.output)
    if out.exists():
        _fail("C0F_FLAGS_OUTPUT_EXISTS")

    sel_path = pathlib.Path(args.selection)
    cand_path = pathlib.Path(args.candidates)
    dec_path = pathlib.Path(args.decisions)
    selection = json.loads(sel_path.read_text(encoding="utf-8"))
    candidates = json.loads(cand_path.read_text(encoding="utf-8"))
    decisions = json.loads(dec_path.read_text(encoding="utf-8"))

    # Udledningen af record_by_person (inkl. begge entydigheds-kontroller)
    # sker INDE i build_flags_document -- se _derive_record_by_person's
    # docstring for hvorfor det ikke kan flyttes ud igen. main() sender blot
    # de raa raekker videre, ufiltrerede.
    doc = build_flags_document(selection, candidates, decisions.get("decisions", []))
    doc["input_hashes"] = {
        "selection_sha256": _sha256_file(sel_path),
        "candidates_sha256": _sha256_file(cand_path),
        "decisions_sha256": _sha256_file(dec_path),
    }
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    total = sum(doc["flag_counts"].values())
    print("operationer=%d flag=%d %s" % (len(doc["operations"]), total, doc["flag_counts"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
