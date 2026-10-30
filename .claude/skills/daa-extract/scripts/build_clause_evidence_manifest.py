#!/usr/bin/env python3
"""Byg clause_evidence-manifest fra 4.1b's ledger-artefakt (#148 4.1c).

Ingen tekst i output. Scriptet rører aldrig en database og autoriserer aldrig
en skrivning.

**Hvorfor renditionen skal med.** `segment.py` gemmer helposten som
`norm(' '.join(lines))`, så posten er ALDRIG en litteral delstreng af
pdftotext-outputtet: whitespace er foldet. Målt på prod har kun 97 af 591
helposter `char_to - char_from == length(verbatim_text)`. En klausul kan derfor
ikke placeres i renditionen som `parent.char_from + post-relativ offset` — det
ville påstå en kildeposition, der er forkert for 84 % af posterne, uden at nogen
database-kontrol kunne opdage det.

Builderen bygger derfor samme projektion som `build_source_evidence_manifest`
(`project_rendition`), ankrer hver helpost på databasens egen `char_from` fra
ledgeren, verificerer ankeret mod `parent_verbatim_sha256`, og oversætter hver
klausuls offsets gennem kortet. Hver oversættelse hash-verificeres mod
ledgerens `verbatim_sha256`. Alt fejler lukket.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_source_evidence_manifest as sem
import clause_set
from reimport_profile import load_profile

LEDGER_SCHEMA_VERSION = "clause-ledger-v1"
CLAUSE_KEYS = ("char_from", "char_to", "classification", "flags", "ordinal",
               "rendition_char_from", "rendition_char_to", "verbatim_sha256")
PROJECTED_CLASSIFICATIONS = ("record_text", "structural_header")


class BuildError(ValueError):
    """Fejl der stopper bygningen. Ingen delvise manifester."""


def _fail(code: str) -> None:
    raise BuildError(code)


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


RAW_TEXT_FORM = "raw"


def _text_form(profile: dict[str, Any]) -> str:
    """Tekstformen fra writer_config; udeladt = 2018-20's foldede projektion."""
    return (profile.get("writer_config") or {}).get("text_form", "folded_projection@anywhere")


def _anchor(projected: str, offsets: Any, kandidater: dict[int, list[int]],
            record: dict[str, Any], raw: bool = False) -> tuple[int, int]:
    """Find (p, q) i projektionen for helposten, verificeret mod dens hash."""
    pcf, pct = record["parent_char_from"], record["parent_char_to"]
    if raw:
        # Identitetsprojektion: helposten ER et ordret udsnit af renditionen.
        if 0 <= pcf < pct <= len(projected) and _sha(projected[pcf:pct]) == record["parent_verbatim_sha256"]:
            return pcf, pct
        _fail("CLAUSE_EVIDENCE_PARENT_ANCHOR_FAILED")
    for p in kandidater.get(pcf, ()):
        q = p
        while q < len(offsets) and offsets[q] < pct:
            q += 1
        if q > p and offsets[q - 1] + 1 == pct \
                and _sha(projected[p:q]) == record["parent_verbatim_sha256"]:
            return p, q
    _fail("CLAUSE_EVIDENCE_PARENT_ANCHOR_FAILED")


def _operations(profile: dict[str, Any], ledger: dict[str, Any], rendition: str) -> tuple[list[dict[str, Any]], str, list[str]]:
    """Ledgerens poster som clause_evidence-operationer (fælles for begge tilstande)."""
    if _sha(rendition) != profile["raw_text_sha256"]:
        _fail("RENDITION_SHA_MISMATCH")
    if ledger.get("schema_version") != LEDGER_SCHEMA_VERSION:
        _fail("LEDGER_SCHEMA_INVALID")
    if ledger.get("rules_version") != profile["clause_rules_version"]:
        _fail("LEDGER_RULES_VERSION_MISMATCH")
    if ledger.get("segmenter_version") != profile["segmenter_version"]:
        _fail("LEDGER_SEGMENTER_VERSION_MISMATCH")
    gap_charset = ledger.get("gap_charset")
    if not isinstance(gap_charset, list) or not gap_charset \
            or not all(isinstance(g, str) and len(g) == 1 for g in gap_charset):
        _fail("LEDGER_GAP_CHARSET_INVALID")

    raw = _text_form(profile) == RAW_TEXT_FORM
    kandidater: dict[int, list[int]] = defaultdict(list)
    if raw:
        projected, offsets = rendition, range(len(rendition))
    else:
        projected, offsets = sem.project_rendition(rendition)
        for i, o in enumerate(offsets):
            kandidater[o].append(i)
    projection_sha = _sha(projected)

    operations: list[dict[str, Any]] = []
    seen: set[str] = set()
    for record in sorted(ledger["records"], key=lambda r: r["record_key"].encode("utf-8")):
        key = record["record_key"]
        if key in seen:
            _fail("LEDGER_RECORD_KEY_DUPLICATE")
        seen.add(key)
        p, q = _anchor(projected, offsets, kandidater, record, raw)
        post_length = q - p

        clauses: list[dict[str, Any]] = []
        forrige_slut = 0
        for clause in sorted(record["clauses"], key=lambda c: c["ordinal"]):
            if clause["ordinal"] != len(clauses) + 1:
                _fail("LEDGER_ORDINALS_INVALID")
            if clause["classification"] not in PROJECTED_CLASSIFICATIONS:
                _fail("LEDGER_CLASSIFICATION_NOT_PROJECTABLE")
            flags = clause["flags"]
            if not isinstance(flags, list) or any(not isinstance(f, str) or not f.strip() for f in flags):
                _fail("LEDGER_FLAGS_INVALID")
            cf, ct = clause["char_from"], clause["char_to"]
            if not (0 <= forrige_slut <= cf < ct <= post_length):
                _fail("LEDGER_CLAUSE_SPAN_INVALID")
            if _sha(projected[p + cf:p + ct]) != clause["verbatim_sha256"]:
                _fail("CLAUSE_EVIDENCE_TEXT_HASH_MISMATCH")
            raw_from = offsets[p + cf]
            raw_to = offsets[p + ct - 1] + 1
            if not (record["parent_char_from"] <= raw_from < raw_to <= record["parent_char_to"]):
                _fail("CLAUSE_EVIDENCE_RENDITION_SPAN_INVALID")
            clauses.append({
                "ordinal": clause["ordinal"], "char_from": cf, "char_to": ct,
                "rendition_char_from": raw_from, "rendition_char_to": raw_to,
                "classification": clause["classification"], "flags": list(flags),
                "verbatim_sha256": clause["verbatim_sha256"],
            })
            forrige_slut = ct
        if not clauses:
            _fail("LEDGER_RECORD_WITHOUT_CLAUSES")

        operations.append({
            "element_id": f"clause-evidence:{key}",
            "dependency_class": "clause_evidence",
            "source_record_key": key,
            "rendition_content_sha256": record["rendition_content_sha256"],
            "rendition_projection_sha256": projection_sha,
            "parent_verbatim_sha256": record["parent_verbatim_sha256"],
            "clause_rules_version": record["rules_version"],
            "segmenter_version": ledger["segmenter_version"],
            "ledger_sha256": record["ledger_sha256"],
            "gap_charset": list(gap_charset),
            "clauses": clauses,
        })
    return operations, projection_sha, list(gap_charset)


def build_manifest(profile: dict[str, Any], ledger: dict[str, Any],
                   rendition: str, ledger_file_sha256: str) -> dict[str, Any]:
    operations, projection_sha, _ = _operations(profile, ledger, rendition)
    if len(operations) != profile["expected_counts"]["clause_evidence"]:
        _fail("LEDGER_COUNT_MISMATCH")

    manifest = {
        "source": {"id": profile["source_id"], "profile_id": profile["profile_id"],
                   "profile_sha256": profile["profile_sha256"]},
        "provenance": {"ledger_file_sha256": ledger_file_sha256,
                       "raw_text_sha256": profile["raw_text_sha256"],
                       "rendition_projection_sha256": projection_sha,
                       "clause_rules_version": profile["clause_rules_version"],
                       "segmenter_version": profile["segmenter_version"]},
        "expected_counts": {"source_evidence": 0, "person_creates": 0,
                            "canonical_delta": 0, "clause_evidence": len(operations)},
        "operations": operations,
    }
    manifest["manifest_content_sha256"] = hashlib.sha256(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True,
                   separators=(",", ":")).encode("utf-8")).hexdigest()
    return manifest


def current_sets_from_projection(projection: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Det aktuelle klausulsæt pr. post, læst af klausul-projektionen (ikke af en fil)."""
    current: dict[str, dict[str, Any]] = {}
    for row in projection["clauses"]:
        if not row.get("is_current_set") or row.get("record_key") is None:
            continue
        entry = {"clause_set_seq": row["clause_set_seq"], "clause_set_sha256": row["clause_set_sha256"]}
        if current.setdefault(row["record_key"], entry) != entry:
            _fail("CLAUSE_REVISION_CURRENT_SET_AMBIGUOUS")
    return current


def build_revision_manifest(profile: dict[str, Any], ledger: dict[str, Any], rendition: str,
                            ledger_file_sha256: str, current_sets: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Omsegmentering (spec 2026-09-27): kun poster, hvis klausulsæt-hash ændres.

    En ren flag-ændring ændrer hashen og kommer med. Hver operation bærer det sæt,
    den erstatter (seq + hash fra projektionen), så writeren kan afvise en base, der er
    skredet siden manifestet blev bygget.
    """
    operations, projection_sha, _ = _operations(profile, ledger, rendition)
    revisions: list[dict[str, Any]] = []
    for op in operations:
        key = op["source_record_key"]
        base = current_sets.get(key)
        if base is None:
            _fail("CLAUSE_REVISION_BASE_MISSING")
        if clause_set.clause_set_sha256(op["clauses"]) == base["clause_set_sha256"]:
            continue
        revisions.append(dict(op, element_id=f"clause-revision:{key}", dependency_class="clause_revision",
                              replaces_clause_set_seq=base["clause_set_seq"],
                              replaces_clause_set_sha256=base["clause_set_sha256"]))
    if len(revisions) != profile["expected_counts"]["clause_revisions"]:
        _fail("LEDGER_COUNT_MISMATCH")
    manifest = {
        "source": {"id": profile["source_id"], "profile_id": profile["profile_id"],
                   "profile_sha256": profile["profile_sha256"]},
        "provenance": {"ledger_file_sha256": ledger_file_sha256,
                       "raw_text_sha256": profile["raw_text_sha256"],
                       "rendition_projection_sha256": projection_sha,
                       "clause_rules_version": profile["clause_rules_version"],
                       "segmenter_version": profile["segmenter_version"],
                       "current_sets_sha256": hashlib.sha256(json.dumps(
                           current_sets, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()},
        "expected_counts": {"source_evidence": 0, "person_creates": 0,
                            "canonical_delta": 0, "clause_revisions": len(revisions)},
        "operations": revisions,
    }
    manifest["manifest_content_sha256"] = hashlib.sha256(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True,
                   separators=(",", ":")).encode("utf-8")).hexdigest()
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    for flag in ("--profile", "--ledger", "--rendition", "--output"):
        parser.add_argument(flag, required=True)
    parser.add_argument("--current-projection",
                        help="revisions-profil: klausul-projektionen af målbasen (det aktuelle sæt pr. post)")
    parser.add_argument("--expect-ledger-sha256", required=True,
                        help="ledgerfilens SHA-256 fra 4.1b's rapport — bygningen "
                             "stopper, hvis filen ikke er præcis den reviewede")
    args = parser.parse_args()

    profile = load_profile(Path(args.profile))
    ledger_bytes = Path(args.ledger).read_bytes()
    ledger_file_sha256 = hashlib.sha256(ledger_bytes).hexdigest()
    if ledger_file_sha256 != args.expect_ledger_sha256:
        _fail("LEDGER_FILE_SHA_MISMATCH")
    ledger = json.loads(ledger_bytes.decode("utf-8"))
    rendition = Path(args.rendition).read_text(encoding="utf-8")

    out = Path(args.output)
    if out.exists():
        _fail("CLAUSE_EVIDENCE_OUTPUT_EXISTS")
    if profile.get("profile_schema_version") == "reimport-clause-revision-profile-v1":
        if not args.current_projection:
            _fail("CLAUSE_REVISION_CURRENT_PROJECTION_REQUIRED")
        current = current_sets_from_projection(json.loads(Path(args.current_projection).read_text(encoding="utf-8")))
        manifest = build_revision_manifest(profile, ledger, rendition, ledger_file_sha256, current)
    else:
        manifest = build_manifest(profile, ledger, rendition, ledger_file_sha256)
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                   encoding="utf-8")
    out.chmod(0o600)
    print(json.dumps({"operations": len(manifest["operations"]),
                      "clauses": sum(len(o["clauses"]) for o in manifest["operations"]),
                      "manifest_content_sha256": manifest["manifest_content_sha256"],
                      "ledger_file_sha256": ledger_file_sha256}, ensure_ascii=False))


if __name__ == "__main__":
    main()
