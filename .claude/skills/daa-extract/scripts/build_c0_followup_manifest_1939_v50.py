#!/usr/bin/env python3
"""Manifest-bygger for C0's efterkørsel.

Beslutnings-anvendelsen er KOMPOSITION over ``normalize_narrative_v1``, aldrig
en anden kopi af dens regler: transformen er et strengt venstre-mod-højre-pas
uden lookahead ud over det flagede sted, så en afkortning af rå-teksten præcis
ved et flags ``char_offset`` og en genkørsel giver et EKSAKT præfiks af
standard-outputtet — og dermed splice-positionen via modulets eget API.
Mønsteret er verificeret mod alle 178 ægte flag i fase B.

Codex-review (2026-08-21, runde 1) fandt at præfiks-kontrollen alene IKKE er
nok: den beviser kun at ET præfiks matcher standard-outputtet, ikke at
``raw[char_offset]`` faktisk ER det flagede sted. Derfor genfindes hvert flag
i en frisk ``normalize_narrative_v1(raw, corpus)``-kørsel og krydstjekkes med
eksakt samme ``kind``/``char_offset`` -- flag-dokumentet er ikke autoritativt
over sin egen ``char_offset``, kun den friske kørsel over raw-teksten er.

Codex-review (2026-08-21, runde 2) fandt tre yderligere fund efter runde 1's
rettelse:

1. ``_safe_int`` brugte en generel ``int(value)``-konvertering, der stille
   accepterede baade floats (``992.9`` -> ``992``) og cifferstrenge
   (``"992"`` -> ``992``). Rettet til PRAECIS ``type(value) is int`` -- samme
   moenster som Task 2's ``_derive_record_by_person`` bruger for person_id,
   af noejagtig samme grund.
2. Genfindingskontrollen laa EFTER "continue"-grenen for default-handlede
   flag (og blev slet ikke koert for operationer med NUL flag), saa en
   operation koblet til en ANDEN records raw-tekst kunne passere ubemaerket
   naar alle dens beslutninger var default (merge) -- og udsende
   flag-dokumentets ``default_text``, som reelt stammede fra et andet
   dokument end den ``raw``, operationen faktisk pegede paa. Rettet ved (a)
   at flytte genfindingskontrollen op saa den gaelder ALLE flag foer nogen
   "continue", og (b) at kraeve at en frisk normalisering af raw+corpus
   giver PRAECIS ``default_text`` -- det lukker ogsaa nul-flag-tilfaeldet,
   hvor der slet ikke er noget flag-loop at koere.
3. To flag med identisk ``flag_id`` i samme operation blev begge spliced,
   fordi to nul-laengde-indsaettelser paa samme punkt ikke registreres som
   "overlappende" af det halvaabne interval-tjek (``Revent--low``). Rettet
   ved at afvise duplerede ``flag_id`` TERMINALT, foer noget naar
   splice-listen.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib
import re
import sys
from typing import Any, Dict, List, Set, Tuple

_SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent

DEFAULT_ACTION = {"hyphen_unproven": "merge"}
VALID_ACTIONS = {"hyphen_unproven": {"merge", "keep"}}
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

# De felter en operation SKAL baere for at kunne behandles. Mangler et af
# dem, er dokumentet ikke bygget af Task 2's build_flags_document -- fail
# closed med en C0F_-kode i stedet for en raa KeyError.
_REQUIRED_OP_FIELDS = (
    "person_id", "narrative_id", "old_sha256", "source_record_key",
    "page_from", "default_text", "flags",
)


def _fail(code: str) -> None:
    raise SystemExit(code)


def _import(name: str):
    spec = importlib.util.spec_from_file_location(name, _SCRIPTS_DIR / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


_flags_mod = _import("build_c0_followup_flags_1939_v50")
normalize_narrative_v1 = _flags_mod.normalize_narrative_v1


def _assert_invariants(text: str, context: str) -> None:
    if "### PAGE" in text:
        _fail("C0F_MANIFEST_INVARIANT_PAGE_MARKER:" + context)
    if _flags_mod._LONE_NEWLINE_RE.search(text):
        _fail("C0F_MANIFEST_INVARIANT_LONE_NEWLINE:" + context)
    if text != text.rstrip():
        _fail("C0F_MANIFEST_INVARIANT_TRAILING_WS:" + context)
    if not text.strip():
        _fail("C0F_MANIFEST_INVARIANT_EMPTY:" + context)


def _safe_int(value: Any, code: str) -> int:
    """Kraever PRAECIS ``type(value) is int`` -- aldrig en generel
    ``int(...)``-konvertering og aldrig en generel ``isinstance``-kontrol.

    Samme moenster som Task 2's ``_derive_record_by_person`` bruger for
    person_id, af noejagtig samme to grunde: (1) en generel ``int(value)``
    ville stille afkorte ``992.9`` til ``992`` og konvertere cifferstrengen
    ``"992"`` uden fejl -- begge blev verificeret (Codex-review runde 2) at
    glide igennem den tidligere implementering; (2) ``isinstance(True, int)``
    er ``True`` i Python, fordi ``bool`` er en underklasse af ``int``, saa
    selv en "stram" isinstance-kontrol ville lukke ``true`` igennem som 1.
    ``type(value) is int`` er den ENESTE kontrol der afviser begge klasser
    paa een gang, uden en separat bool-saerkontrol.
    """
    if type(value) is not int:
        _fail(code)
    return value


def _decided_text(raw: str, corpus: str, default_text: str,
                  op_flags: List[Dict[str, Any]], decisions: Dict[str, str],
                  pid: int) -> str:
    # Den ENESTE autoritative kilde til hvor de aegte flag sidder i raw: en
    # frisk genkoersel. Flag-dokumentets egen char_offset bruges ALDRIG blindt.
    true_result = normalize_narrative_v1(raw, corpus)

    # Runde 2, fund 2: default_text SKAL vaere PRAECIS det en frisk
    # normalisering af DENNE raw+corpus giver -- ikke bare "et praefiks
    # matcher" for de flag der rent faktisk spliced. En operation koblet til
    # en ANDEN records raw (fx via en forkert source_record_key) ville ellers
    # passere ubemaerket saa laenge alle dens beslutninger var default
    # (merge, ingen splice, intet at tjekke) -- inklusive det vaerste
    # tilfaelde: en operation med NUL flag (allerede korrekt tekst, intet at
    # afgoere) blev slet ikke tjekket overhovedet, fordi flag-loopet
    # nedenfor simpelthen ikke koerte. Denne kontrol lukker HELE klassen paa
    # een gang, uanset antal flag eller deres handlinger.
    if true_result["text"] != default_text:
        _fail("C0F_MANIFEST_DEFAULT_TEXT_MISMATCH:person=%d" % pid)
    true_flag_set = {(f["kind"], f["char_offset"]) for f in true_result["flags"]}

    edits: List[Tuple[int, int, str]] = []
    seen_flag_ids: Set[str] = set()
    for flag in op_flags:
        if not isinstance(flag, dict):
            _fail("C0F_MANIFEST_FLAG_INVALID:person=%d" % pid)
        for field in ("kind", "char_offset", "flag_id"):
            if field not in flag:
                _fail("C0F_MANIFEST_FLAG_MISSING_FIELD:%s:person=%d" % (field, pid))
        flag_id = flag["flag_id"]

        # Runde 2, fund 3: eksakt duplerede flag-id'er accepteres IKKE.
        # Splice-overlap-kontrollen laengere nede fanger det ikke: to
        # identiske nul-laengde-indsaettelser paa samme punkt
        # (prefix_len, prefix_len) registreres ikke som "overlappende" under
        # det halvaabne interval-tjek (hi <= a or lo >= b er sandt naar
        # lo == hi == a == b), saa et dupleret "keep"-flag ville splice to
        # bindestreger paa samme sted ("Revent--low"). Afvises HER, foer
        # noget naar splice-listen.
        if flag_id in seen_flag_ids:
            _fail("C0F_MANIFEST_FLAG_ID_DUPLICATE:" + flag_id)
        seen_flag_ids.add(flag_id)

        kind = flag["kind"]
        offset = _safe_int(flag["char_offset"],
                           "C0F_MANIFEST_FLAG_OFFSET_INVALID:" + str(flag_id))
        if kind not in VALID_ACTIONS:
            _fail("C0F_MANIFEST_FLAG_KIND_UNKNOWN:" + flag_id)

        # Runde 2, fund 2: genfindingskontrollen gaelder NU for ALLE flag --
        # ogsaa dem med default-handling, der aldrig naar splice-koden. Den
        # gamle placering (efter "continue") lod default-handlede flag
        # passere HELT UPROEVET.
        if (kind, offset) not in true_flag_set:
            _fail("C0F_MANIFEST_FLAG_NOT_FOUND:" + flag_id)

        action = decisions.get(flag_id)
        if action is None:
            _fail("C0F_MANIFEST_DECISION_MISSING:" + flag_id)
        if action not in VALID_ACTIONS[kind]:
            _fail("C0F_MANIFEST_ACTION_INVALID:" + flag_id)
        if action == DEFAULT_ACTION[kind]:
            continue

        prefix_text = normalize_narrative_v1(raw[:offset], corpus)["text"]
        prefix_len = len(prefix_text)
        # Ikke-tom kontrol selv naar default-spannet er 0 tegn: den bekraefter
        # at HELE praefikset flugter med standard-outputtet foer der splices,
        # saa en skredet prefix_len aldrig kan indsaette en "-" det forkerte sted.
        if default_text[:prefix_len] != prefix_text:
            _fail("C0F_MANIFEST_DECISION_PREFIX_MISMATCH:" + flag_id)
        # hyphen_unproven: standarden har allerede sammentrukket, 0 tegn beholdt.
        edits.append((prefix_len, prefix_len, "-"))
    edits.sort(key=lambda e: -e[0])
    text = default_text
    seen: List[Tuple[int, int]] = []
    for lo, hi, span in edits:
        if any(not (hi <= a or lo >= b) for a, b in seen):
            _fail("C0F_MANIFEST_DECISION_SPLICE_OVERLAP")
        seen.append((lo, hi))
        text = text[:lo] + span + text[hi:]
    return text


def build_manifest(flags_doc: Dict[str, Any], decisions_doc: Dict[str, Any],
                   candidates: Dict[str, Any], flags_sha256: str) -> Dict[str, Any]:
    if not isinstance(flags_sha256, str) or _SHA256_RE.fullmatch(flags_sha256) is None:
        _fail("C0F_MANIFEST_FLAGS_SHA256_INVALID")
    decision_flags_sha256 = decisions_doc.get("flags_sha256")
    if decision_flags_sha256 is None:
        _fail("C0F_MANIFEST_FLAGS_SHA256_MISSING")
    if (not isinstance(decision_flags_sha256, str) or
            _SHA256_RE.fullmatch(decision_flags_sha256) is None):
        _fail("C0F_MANIFEST_DECISION_FLAGS_SHA256_INVALID")
    if decision_flags_sha256 != flags_sha256:
        _fail("C0F_MANIFEST_FLAGS_SHA256_MISMATCH")

    # Sikkerhedsgaten valider sin EGEN inputkontrakt -- den kan ikke laene
    # tillid fra Task 2's producent-side validering. Uden dette ville et
    # flag-dokument uden database-identitet blive til et manifest med
    # database_name=None/database_identity=None, og Task 5's
    # levende-base-sammenligning ville aldrig faa noget at afvise imod.
    db_name = flags_doc.get("database_name")
    if not db_name or not str(db_name).strip():
        _fail("C0F_MANIFEST_DATABASE_NAME_MISSING")
    db_identity = flags_doc.get("database_identity")
    if not db_identity or not str(db_identity).strip():
        _fail("C0F_MANIFEST_DATABASE_IDENTITY_MISSING")

    accepted_raw = decisions_doc.get("accepted_person_ids", [])
    if not isinstance(accepted_raw, list):
        _fail("C0F_MANIFEST_ACCEPTED_IDS_INVALID")
    accepted = set(
        _safe_int(p, "C0F_MANIFEST_ACCEPTED_ID_INVALID:%r" % (p,))
        for p in accepted_raw)
    if not accepted:
        _fail("C0F_MANIFEST_EMPTY")

    decisions = decisions_doc.get("decisions") or {}
    if not isinstance(decisions, dict):
        _fail("C0F_MANIFEST_DECISIONS_INVALID")

    records = candidates.get("records")
    if not isinstance(records, list):
        _fail("C0F_MANIFEST_CANDIDATES_INVALID")
    recs: Dict[str, Dict[str, Any]] = {}
    for record in records:
        key = record.get("new_record_key")
        if not key:
            _fail("C0F_MANIFEST_RECORD_MISSING_KEY")
        if "verbatim_text" not in record:
            _fail("C0F_MANIFEST_RECORD_MISSING_TEXT:%s" % key)
        recs[key] = record
    # Korpus = ALLE records' rå tekst -- se Task 2's begrundelse; genbruges
    # her uaendret, ikke genimplementeret.
    corpus = "\n".join(r["verbatim_text"] for r in records)

    ops_raw = flags_doc.get("operations")
    if not isinstance(ops_raw, list):
        _fail("C0F_MANIFEST_FLAGS_DOC_INVALID")

    operations = []
    for index, op in enumerate(ops_raw):
        if not isinstance(op, dict):
            _fail("C0F_MANIFEST_OP_INVALID:index=%d" % index)
        if "person_id" not in op:
            _fail("C0F_MANIFEST_OP_MISSING_FIELD:person_id:index=%d" % index)
        pid = _safe_int(op["person_id"],
                        "C0F_MANIFEST_OP_PERSON_ID_INVALID:index=%d" % index)

        # Filtreringen mod accepted_person_ids sker FOERST -- decisions_doc's
        # "decisions" er IKKE forfiltreret efter accept, saa en afvist
        # persons flag maa aldrig naa frem til _decided_text. Roer IKKE
        # denne raekkefoelge -- den er bekraeftet korrekt af review.
        if pid not in accepted:
            continue

        for field in _REQUIRED_OP_FIELDS:
            if field not in op:
                _fail("C0F_MANIFEST_OP_MISSING_FIELD:%s:person=%d" % (field, pid))

        key = op["source_record_key"]
        if key not in recs:
            _fail("C0F_MANIFEST_RECORD_MISSING:%d" % pid)

        op_flags = op["flags"]
        if not isinstance(op_flags, list):
            _fail("C0F_MANIFEST_OP_FLAGS_INVALID:%d" % pid)

        new_text = _decided_text(recs[key]["verbatim_text"], corpus,
                                 op["default_text"], op_flags, decisions, pid)
        # Invarianterne haevdes paa den FAERDIGE tekst: et splice kan i
        # princippet genindfoere et brud, som default_text ikke havde.
        _assert_invariants(new_text, "person=%d" % pid)
        operations.append({
            "person_id": pid,
            "narrative_id": _safe_int(
                op["narrative_id"], "C0F_MANIFEST_NARRATIVE_ID_INVALID:%d" % pid),
            "expected_old_narrative_sha256": op["old_sha256"],
            "source_record_key": key,
            "page_from": _safe_int(
                op["page_from"], "C0F_MANIFEST_PAGE_FROM_INVALID:%d" % pid),
            "new_text": new_text,
            "new_text_sha256": hashlib.sha256(new_text.encode("utf-8")).hexdigest(),
        })
    operations.sort(key=lambda o: o["person_id"])
    if not operations:
        _fail("C0F_MANIFEST_EMPTY")
    return {
        "schema_version": "1939-v50-c0-followup-manifest-v1",
        "generator": "build_c0_followup_manifest_1939_v50.py",
        # Baeres videre fra flag-dokumentet; apply sammenligner mod den LEVENDE
        # base, saa et manifest fra rehearsal ikke kan koeres mod prod.
        "database_name": db_name,
        "database_identity": db_identity,
        "input_hashes": {"flags_sha256": flags_sha256},
        "source": {"edition": "1939", "database_source_id": 3},
        "counts": {"operations": len(operations), "bindings_create": len(operations)},
        "operations": operations,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flags", required=True)
    parser.add_argument("--decisions", required=True)
    parser.add_argument("--candidates", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    out = pathlib.Path(args.output)
    if out.exists():
        _fail("C0F_MANIFEST_OUTPUT_EXISTS")
    read = lambda p: json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
    flags_bytes = pathlib.Path(args.flags).read_bytes()
    man = build_manifest(
        json.loads(flags_bytes.decode("utf-8")), read(args.decisions),
        read(args.candidates), hashlib.sha256(flags_bytes).hexdigest())
    out.write_text(json.dumps(man, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    print("operationer=%d bindinger=%d" % (
        man["counts"]["operations"], man["counts"]["bindings_create"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
