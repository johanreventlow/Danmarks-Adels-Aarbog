#!/usr/bin/env python3
"""Byg et hash-låst legacy-migration-manifest (spec §4, §6.2, §7). Ingen tekst i output."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from typing import Any
from normalize_narrative_1939_v50 import normalize_narrative_v1

DISPOSITIONS = ("bound_published", "bound_draft", "unresolved_text", "unresolved_identity")

class BuildError(ValueError):
    pass

def _fail(code: str) -> None:
    raise BuildError(code)

def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def _publishable(c: dict[str, Any]) -> bool:
    return c["person_levende"] is False and not c["person_privat"] and not c["person_staged"] and not c["narrative_privat"]

def dispose(c: dict[str, Any], t: dict[str, str], corpus: str) -> tuple[str, str, str]:
    """Returnér (disposition, reason, normalized_sha256)."""
    # Trin 6a (R13-b): occurrence_text er bevidst FOREKOMSTENS tekst, ikke helpostens gældende tekstversion. En
    # kildetekst-revision lader forekomsten stå urørt (spec §4.4), og writeren (migrate_legacy_narrative_record) og
    # 149b-manifesterne er bundet til netop den tekst og dens hash.
    if _sha(t["narrative_text"]) != c["narrative_text_sha256"] or _sha(t["occurrence_text"]) != c["occurrence_verbatim_sha256"]:
        _fail("LEGACY_MIGRATION_TEXT_HASH_MISMATCH")
    if c["persons_for_record_key"] != 1 or c["external_ids_for_person"] != 1 or c["narratives_for_person"] != 1 or c["already_bound"]:
        return "unresolved_identity", "identity_not_injective_or_bound", ""
    n_norm = normalize_narrative_v1(t["narrative_text"], corpus)["text"]
    o_norm = normalize_narrative_v1(t["occurrence_text"], corpus)["text"]
    if n_norm != o_norm:
        return "unresolved_text", "normalized_text_differs", ""
    publishable = _publishable(c)
    if publishable:
        if c["legacy_status"] != "grandfathered_publication" or not c["legacy_publication_ref"] or not c["legacy_baseline_sha256"]:
            _fail("LEGACY_MIGRATION_LEDGER_INCONSISTENT")
        return "bound_published", "publishable_grandfathered", _sha(n_norm)
    if c["legacy_status"] is not None:
        _fail("LEGACY_MIGRATION_LEDGER_INCONSISTENT")
    return "bound_draft", "not_publishable", _sha(n_norm)

def build_manifest(profile: dict[str, Any], candidates: list[dict[str, Any]], texts: dict[str, dict[str, str]], corpus: str) -> dict[str, Any]:
    if _sha(corpus) != profile["raw_text_sha256"]:
        _fail("LEGACY_MIGRATION_CORPUS_SHA_MISMATCH")
    seen: set[str] = set()
    dispositions: list[dict[str, Any]] = []
    operations: list[dict[str, Any]] = []
    for c in sorted(candidates, key=lambda x: x["record_key"]):
        key = c["record_key"]
        if key in seen:
            _fail("LEGACY_MIGRATION_RECORD_KEY_DUPLICATE")
        seen.add(key)
        if key not in texts:
            _fail("LEGACY_MIGRATION_TEXT_MISSING")
        disposition, reason, norm_sha = dispose(c, texts[key], corpus)
        dispositions.append({"record_key": key, "person_id": c["person_id"], "narrative_id": c["narrative_id"],
                             "disposition": disposition, "reason": reason})
        if disposition.startswith("bound_"):
            operations.append({
                "element_id": f"legacy-migration:{key}", "dependency_class": "legacy_migration",
                "source_record_key": key, "source_id": profile["source_id"],
                "person_id": c["person_id"], "narrative_id": c["narrative_id"], "disposition": disposition,
                "narrative_text_sha256": c["narrative_text_sha256"],
                "occurrence_verbatim_sha256": c["occurrence_verbatim_sha256"],
                "normalized_text_sha256": norm_sha,
                "legacy_publication_ref": c["legacy_publication_ref"] if disposition == "bound_published" else None,
                "legacy_baseline_sha256": c["legacy_baseline_sha256"] if disposition == "bound_published" else None,
                "persona_key": key})
    tally = {d: sum(1 for x in dispositions if x["disposition"] == d) for d in DISPOSITIONS}
    unresolved = tally["unresolved_text"] + tally["unresolved_identity"]
    if dispositions and unresolved * 100 > profile["stop_threshold"]["unresolved_max_share_percent"] * len(dispositions):
        _fail("LEGACY_MIGRATION_STOP_THRESHOLD")
    if tally != profile["expected_dispositions"]:
        _fail("LEGACY_MIGRATION_EXPECTED_DISPOSITIONS_MISMATCH")
    if len(operations) != profile["expected_counts"]["legacy_migrations"]:
        _fail("LEGACY_MIGRATION_COUNT_MISMATCH")
    manifest = {
        "source": {"id": profile["source_id"], "profile_id": profile["profile_id"], "profile_sha256": profile["profile_sha256"]},
        "expected_counts": {"source_evidence": 0, "person_creates": 0, "canonical_delta": 0, "legacy_migrations": len(operations)},
        "dispositions": dispositions,
        "operations": operations,
    }
    manifest["manifest_content_sha256"] = hashlib.sha256(json.dumps(
        manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    return manifest

def main() -> None:
    parser = argparse.ArgumentParser()
    for flag in ("--profile", "--candidates", "--texts", "--rendition-text", "--output"):
        parser.add_argument(flag, required=True)
    args = parser.parse_args()
    from reimport_profile import load_profile  # samme mappe
    profile = load_profile(Path(args.profile))
    candidates = json.loads(Path(args.candidates).read_text(encoding="utf-8"))
    texts = json.loads(Path(args.texts).read_text(encoding="utf-8"))
    corpus = Path(args.rendition_text).read_text(encoding="utf-8")
    out = Path(args.output)
    if out.exists():
        _fail("LEGACY_MIGRATION_OUTPUT_EXISTS")
    out.write_text(json.dumps(build_manifest(profile, candidates, texts, corpus), ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

if __name__ == "__main__":
    main()
