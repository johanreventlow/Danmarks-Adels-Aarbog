#!/usr/bin/env python3
"""Build the DAA 1939 v50 fase-B narrative replacement manifest (551 ops).

Consumes the closed fase-A anchor manifest (543 canonical_target ops), task
25's production-write manifest (8 person_creates), the narrative-publication
manifest (the 8's already-published bindings), the Calamari rendition text,
and a hash-locked read-only export of the *current* prod narrative texts
(source 3), and emits either:

- WITHOUT ``--decisions``: a flags file with all human-review flags (from
  ``normalize_narrative_v1`` -- the single canonical transform, imported,
  never duplicated) plus the 26 out-of-scope classifications, and refuses to
  write the manifest (exit code 2) -- this is the input to Task 3's human
  checkpoint.
- WITH ``--decisions``: every flag resolved, the manifest frozen with the
  *decided* normalized text for each of the 551 narratives.

Never touches the database; never authorizes writes.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

_SCRIPTS_DIR = Path(__file__).resolve().parent


def _import_normalize_module():
    """Import ``normalize_narrative_1939_v50`` from this same directory via
    ``importlib`` (not a bare ``import``), so this script works regardless
    of the caller's working directory or sys.path state. Task 1's module is
    consumed as-is, unmodified -- the single source of truth for the
    dewrap/ordinal-strip transform; this builder never reimplements it."""
    spec = importlib.util.spec_from_file_location(
        "normalize_narrative_1939_v50", _SCRIPTS_DIR / "normalize_narrative_1939_v50.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


_normalize_mod = _import_normalize_module()
normalize_narrative_v1 = _normalize_mod.normalize_narrative_v1


HASH_RE = re.compile(r"^[0-9a-f]{64}$")

# Låst 2026-08-18 (task-context.md, Faktagrundlag) for de tre historiske
# artefakter; narrativ-publikations-manifestet og old-sha-eksporten er
# uafhængigt verificeret i denne session direkte mod
# daa1939_phase_a_rehearsal1 (8 published bindinger matcher filen
# byte-for-byte; 577 rækker matcher narrative-tabellens source_id=3-optælling).
LOCKED_PHASE_A_MANIFEST_SHA256 = "1945416b3b56e781787366008a2463b419cb8ed4df3ef1399211cac5c999e208"
LOCKED_PRODUCTION_MANIFEST_SHA256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
LOCKED_NARRATIVE_PUBLICATION_MANIFEST_SHA256 = "d71908cf3a998d57602a91d936a2c1b19cf874da938bdef0d691fda9a2ac7654"
LOCKED_CALAMARI_SHA256 = "020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37"
LOCKED_OLD_NARRATIVE_SHA_EXPORT_SHA256 = "e91145c79867f99c79edcc6aa6f1711b4dc5002406fdfc0eded42778f90501ec"
LOCKED_INPUT_HASHES = [
    LOCKED_PHASE_A_MANIFEST_SHA256, LOCKED_PRODUCTION_MANIFEST_SHA256,
    LOCKED_NARRATIVE_PUBLICATION_MANIFEST_SHA256, LOCKED_CALAMARI_SHA256,
    LOCKED_OLD_NARRATIVE_SHA_EXPORT_SHA256,
]

EXPECTED_BINDINGS_CREATE = 543
EXPECTED_BINDINGS_EXISTING = 8
EXPECTED_IN_SCOPE = 551
EXPECTED_TOTAL_SOURCE_NARRATIVES = 577
EXPECTED_OUT_OF_SCOPE = 26
EXPECTED_FLAG_COUNTS = {"hyphen_unproven": 168, "hyphen_ambiguous": 8, "ordinal_ambiguous": 2}

DEFAULT_ACTION = {"hyphen_unproven": "merge", "hyphen_ambiguous": "keep", "ordinal_ambiguous": "keep"}
VALID_ACTIONS = {
    "hyphen_unproven": {"merge", "keep"},
    "hyphen_ambiguous": {"merge", "keep"},
    "ordinal_ambiguous": {"strip", "keep"},
}
CONTEXT_RADIUS = 60


class ManifestError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ManifestError(code)


def canonical_sha(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def _check_hash_shape(supplied: List[str], expected_count: int) -> None:
    # NOTE: this deliberately does NOT re-derive hashes by re-serializing the
    # parsed JSON (unlike some sibling builders) -- narrative-publication-
    # manifest-v1.json was not produced with this script's own
    # json.dumps(...) convention, so a round-trip re-hash does not
    # reproduce its real byte hash. The authoritative check is main()'s
    # verification of the actual file bytes against the CLI-supplied
    # hashes, done BEFORE parsing; this function only checks shape so
    # direct (non-CLI) callers can't pass malformed hash strings through.
    if len(supplied) != expected_count or any(not HASH_RE.fullmatch(x or "") for x in supplied):
        _fail("NARRATIVE_MANIFEST_HASH_INVALID")


# ---------------------------------------------------------------------------
# Input parsing
# ---------------------------------------------------------------------------

def _publication_bindings(pub_manifest: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    if pub_manifest.get("schema_version") != "1939-v50-narrative-publication-manifest-v1":
        _fail("NARRATIVE_MANIFEST_PUBLICATION_INVALID")
    bindings = pub_manifest.get("bindings")
    if not isinstance(bindings, list):
        _fail("NARRATIVE_MANIFEST_PUBLICATION_INVALID")
    result: Dict[str, Dict[str, Any]] = {}
    seen_person_ids: set = set()
    for row in bindings:
        if not isinstance(row, dict):
            _fail("NARRATIVE_MANIFEST_PUBLICATION_INVALID")
        key = row.get("record_key")
        pid = row.get("person_id")
        record_label = row.get("record_label")
        citation_label = row.get("citation_label")
        if (not isinstance(key, str) or not key or key in result or
                not isinstance(pid, int) or pid in seen_person_ids or
                not isinstance(record_label, str) or not record_label or
                not isinstance(citation_label, str) or not citation_label or
                row.get("expected_status") != "draft"):
            _fail(f"NARRATIVE_MANIFEST_PUBLICATION_ROW_INVALID:{key}")
        seen_person_ids.add(pid)
        result[key] = {"person_id": pid, "record_label": record_label, "citation_label": citation_label}
    return result


def _phase_a_543(phase_a_manifest: Dict[str, Any], calamari_sha256: str,
                  calamari_text: str) -> Dict[int, Dict[str, Any]]:
    if (phase_a_manifest.get("schema_version") != "1939-v50-phase-a-anchor-manifest-v1" or
            phase_a_manifest.get("input_hashes", {}).get("calamari_sha256") != calamari_sha256):
        _fail("NARRATIVE_MANIFEST_PHASE_A_INVALID")
    ops = phase_a_manifest.get("operations")
    if not isinstance(ops, list):
        _fail("NARRATIVE_MANIFEST_PHASE_A_INVALID")
    result: Dict[int, Dict[str, Any]] = {}
    for row in ops:
        if not isinstance(row, dict):
            _fail("NARRATIVE_MANIFEST_PHASE_A_INVALID")
        target = row.get("canonical_target")
        if not target:
            continue
        pid = target.get("person_id")
        key = row.get("source_record_key")
        span = row.get("source_span")
        page = row.get("page_evidence", {}).get("page_from") if isinstance(row.get("page_evidence"), dict) else None
        text = row.get("verbatim_text")
        if (not isinstance(pid, int) or pid in result or
                not isinstance(key, str) or not key or
                not isinstance(span, dict) or set(span) != {"char_from", "char_to"} or
                not isinstance(span.get("char_from"), int) or not isinstance(span.get("char_to"), int) or
                not isinstance(page, int) or page < 1 or
                not isinstance(text, str) or not text or
                calamari_text[span["char_from"]:span["char_to"]] != text):
            _fail(f"NARRATIVE_MANIFEST_PHASE_A_ROW_INVALID:{key}")
        result[pid] = {
            "person_id": pid, "source_record_key": key,
            "source_span": {"char_from": span["char_from"], "char_to": span["char_to"]},
            "page_from": page, "verbatim_text": text, "binding": "create",
        }
    return result


def _production_write_8(production_manifest: Dict[str, Any], calamari_sha256: str, calamari_text: str,
                         publication: Dict[str, Dict[str, Any]]) -> Dict[int, Dict[str, Any]]:
    if (production_manifest.get("schema_version") != "1939-v50-production-write-manifest-v1" or
            production_manifest.get("source", {}).get("rendition_content_sha256") != calamari_sha256):
        _fail("NARRATIVE_MANIFEST_PRODUCTION_INVALID")
    creates = production_manifest.get("person_creates")
    if not isinstance(creates, list):
        _fail("NARRATIVE_MANIFEST_PRODUCTION_INVALID")
    result: Dict[int, Dict[str, Any]] = {}
    for row in creates:
        if not isinstance(row, dict):
            _fail("NARRATIVE_MANIFEST_PRODUCTION_INVALID")
        key = row.get("source_record_key")
        span = row.get("source_span")
        page = row.get("page_evidence", {}).get("page_from") if isinstance(row.get("page_evidence"), dict) else None
        text = row.get("verbatim_text")
        binding = publication.get(key)
        if binding is None:
            _fail(f"NARRATIVE_MANIFEST_PRODUCTION_BINDING_MISSING:{key}")
        if (not isinstance(span, dict) or set(span) != {"char_from", "char_to"} or
                not isinstance(span.get("char_from"), int) or not isinstance(span.get("char_to"), int) or
                not isinstance(page, int) or page < 1 or
                not isinstance(text, str) or not text or
                calamari_text[span["char_from"]:span["char_to"]] != text or
                binding["record_label"] != key or
                binding["citation_label"] != f"DAA 1939 side {page}"):
            _fail(f"NARRATIVE_MANIFEST_PRODUCTION_ROW_INVALID:{key}")
        pid = binding["person_id"]
        if pid in result:
            _fail(f"NARRATIVE_MANIFEST_PRODUCTION_DUP_PERSON:{pid}")
        result[pid] = {
            "person_id": pid, "source_record_key": key,
            "source_span": {"char_from": span["char_from"], "char_to": span["char_to"]},
            "page_from": page, "verbatim_text": text, "binding": "existing",
        }
    return result


def _old_sha_by_person(export: Dict[str, Any]) -> Dict[int, str]:
    if (export.get("schema_version") != "1939-v50-narrative-old-sha-export-v1" or
            export.get("query", {}).get("source_id") != 3 or
            export.get("query", {}).get("subjekt_type") != "person"):
        _fail("NARRATIVE_MANIFEST_OLD_SHA_INVALID")
    rows = export.get("rows")
    if not isinstance(rows, list) or export.get("row_count") != len(rows):
        _fail("NARRATIVE_MANIFEST_OLD_SHA_INVALID")
    result: Dict[int, str] = {}
    for row in rows:
        if not isinstance(row, dict):
            _fail("NARRATIVE_MANIFEST_OLD_SHA_INVALID")
        pid = row.get("person_id")
        sha = row.get("narrative_sha256")
        if not isinstance(pid, int) or pid in result or not HASH_RE.fullmatch(sha or ""):
            _fail("NARRATIVE_MANIFEST_OLD_SHA_ROW_INVALID")
        result[pid] = sha
    return result


# ---------------------------------------------------------------------------
# Decision application -- composition over normalize_narrative_v1, never a
# second copy of its rules. The transform is a strict single left-to-right
# pass with no lookahead beyond the flagged site itself (documented on the
# module), so truncating raw exactly at a flag's char_offset and
# re-normalizing yields an *exact* prefix of the full default output --
# giving the splice position for free via the module's own public API.
# Empirically verified against all 178 real in-scope flags before use.
# ---------------------------------------------------------------------------

def _default_span_len(kind: str, raw: str, char_offset: int) -> int:
    if kind == "ordinal_ambiguous":
        return _normalize_mod._match_ordinal_ambiguous(raw[char_offset:])
    return 1 if kind == "hyphen_ambiguous" else 0  # hyphen_unproven default merges (0 chars kept)


def _decided_text(raw: str, corpus: str, default_text: str, op_flags: List[Dict[str, Any]],
                   decisions: Dict[str, str], source_record_key: str) -> str:
    edits: List[Tuple[int, int, str]] = []
    for flag in op_flags:
        kind = flag["kind"]
        offset = flag["char_offset"]
        flag_id = f"{source_record_key}:{offset}:{kind}"
        action = decisions[flag_id]
        if action == DEFAULT_ACTION[kind]:
            continue
        default_len = _default_span_len(kind, raw, offset)
        default_span = raw[offset:offset + default_len] if kind == "ordinal_ambiguous" else ("-" if default_len else "")
        prefix_text = normalize_narrative_v1(raw[:offset], corpus)["text"]
        prefix_len = len(prefix_text)
        # Non-vacuous even when default_len==0 (hyphen_unproven, 168 of 178
        # flags): confirms the whole prefix -- not just the (possibly
        # zero-length) default span -- lines up with the default output
        # before splicing, so a drifted prefix_len can never insert a "-"
        # (or delete one) at the wrong position silently.
        if default_text[:prefix_len] != prefix_text:
            _fail(f"NARRATIVE_MANIFEST_DECISION_PREFIX_MISMATCH:{flag_id}")
        if default_text[prefix_len:prefix_len + default_len] != default_span:
            _fail(f"NARRATIVE_MANIFEST_DECISION_SPLICE_MISMATCH:{flag_id}")
        new_span = "" if action in ("strip", "merge") else "-"
        edits.append((prefix_len, prefix_len + default_len, new_span))
    edits.sort(key=lambda e: -e[0])
    text = default_text
    seen_ranges: List[Tuple[int, int]] = []
    for b_lo, b_hi, new_span in edits:
        if any(not (b_hi <= lo or b_lo >= hi) for lo, hi in seen_ranges):
            _fail("NARRATIVE_MANIFEST_DECISION_SPLICE_OVERLAP")
        seen_ranges.append((b_lo, b_hi))
        text = text[:b_lo] + new_span + text[b_hi:]
    return text


def _flag_id(source_record_key: str, flag: Dict[str, Any]) -> str:
    return f"{source_record_key}:{flag['char_offset']}:{flag['kind']}"


def _load_decisions(decisions_doc: Dict[str, Any], all_flag_ids: set) -> Dict[str, str]:
    if decisions_doc.get("schema_version") != "1939-v50-narrative-decisions-v1":
        _fail("NARRATIVE_MANIFEST_DECISIONS_INVALID")
    decisions = decisions_doc.get("decisions")
    if not isinstance(decisions, dict):
        _fail("NARRATIVE_MANIFEST_DECISIONS_INVALID")
    if set(decisions) != all_flag_ids:
        missing = all_flag_ids - set(decisions)
        extra = set(decisions) - all_flag_ids
        _fail(f"NARRATIVE_MANIFEST_DECISIONS_FLAG_ID_MISMATCH:missing={len(missing)}:extra={len(extra)}")
    for flag_id, action in decisions.items():
        kind = flag_id.rsplit(":", 1)[-1]
        if kind not in VALID_ACTIONS or action not in VALID_ACTIONS[kind]:
            _fail(f"NARRATIVE_MANIFEST_DECISIONS_ACTION_INVALID:{flag_id}")
    return decisions


# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

def _build_narrative_replacement(
    phase_a_manifest: Dict[str, Any], production_manifest: Dict[str, Any],
    pub_manifest: Dict[str, Any], calamari_text: str, old_sha_export: Dict[str, Any],
    *, input_hashes: List[str], decisions_doc: Optional[Dict[str, Any]] = None,
    decisions_sha256: Optional[str] = None,
    expected_bindings_create: Optional[int] = None, expected_bindings_existing: Optional[int] = None,
    expected_out_of_scope: Optional[int] = None, expected_total_source_narratives: Optional[int] = None,
    expected_in_scope: Optional[int] = None, expected_flag_counts: Optional[Dict[str, int]] = None,
) -> Tuple[Optional[Dict[str, Any]], Dict[str, Any]]:
    """Returns ``(manifest_or_None, flags_document)``.

    ``manifest_or_None`` is ``None`` unless ``decisions_doc`` fully resolves
    every flag -- the flags document is always produced (it is what a
    no-decisions caller writes; a decisions caller can use it to
    cross-check, but only the manifest is written in that mode).
    """
    _check_hash_shape(input_hashes, 5)
    calamari_sha256 = input_hashes[3]

    publication = _publication_bindings(pub_manifest)
    scope_543 = _phase_a_543(phase_a_manifest, calamari_sha256, calamari_text)
    scope_8 = _production_write_8(production_manifest, calamari_sha256, calamari_text, publication)

    if expected_bindings_create is not None and len(scope_543) != expected_bindings_create:
        _fail("NARRATIVE_MANIFEST_ARITHMETIC_MISMATCH:bindings_create")
    if expected_bindings_existing is not None and len(scope_8) != expected_bindings_existing:
        _fail("NARRATIVE_MANIFEST_ARITHMETIC_MISMATCH:bindings_existing")

    overlap = set(scope_543) & set(scope_8)
    if overlap:
        _fail(f"NARRATIVE_MANIFEST_SCOPE_OVERLAP:{sorted(overlap)[0]}")
    scope: Dict[int, Dict[str, Any]] = {**scope_543, **scope_8}
    if expected_in_scope is not None and len(scope) != expected_in_scope:
        _fail("NARRATIVE_MANIFEST_ARITHMETIC_MISMATCH:in_scope")

    old_sha = _old_sha_by_person(old_sha_export)
    if expected_total_source_narratives is not None and len(old_sha) != expected_total_source_narratives:
        _fail("NARRATIVE_MANIFEST_ARITHMETIC_MISMATCH:total_source_narratives")
    missing_old_sha = set(scope) - set(old_sha)
    if missing_old_sha:
        _fail(f"NARRATIVE_MANIFEST_OLD_SHA_MISSING_FOR_SCOPE:{sorted(missing_old_sha)[0]}")

    out_of_scope_ids = sorted(set(old_sha) - set(scope))
    if expected_out_of_scope is not None and len(out_of_scope_ids) != expected_out_of_scope:
        _fail("NARRATIVE_MANIFEST_ARITHMETIC_MISMATCH:out_of_scope")
    out_of_scope = [{"person_id": pid, "reason": "no_mapped_source_record"} for pid in out_of_scope_ids]

    # Pass 1: default normalize every in-scope text; collect all flags.
    defaults: Dict[int, Dict[str, Any]] = {}
    all_flags: List[Dict[str, Any]] = []
    flag_counts: Dict[str, int] = {}
    seen_flag_ids: set = set()
    for pid in sorted(scope):
        row = scope[pid]
        result = normalize_narrative_v1(row["verbatim_text"], calamari_text)
        defaults[pid] = result
        for flag in result["flags"]:
            flag_id = _flag_id(row["source_record_key"], flag)
            if flag_id in seen_flag_ids:
                _fail(f"NARRATIVE_MANIFEST_FLAG_ID_COLLISION:{flag_id}")
            seen_flag_ids.add(flag_id)
            flag_counts[flag["kind"]] = flag_counts.get(flag["kind"], 0) + 1
            raw = row["verbatim_text"]
            off = flag["char_offset"]
            lo, hi = max(0, off - CONTEXT_RADIUS), min(len(raw), off + CONTEXT_RADIUS)
            all_flags.append({
                "flag_id": flag_id, "kind": flag["kind"], "context": raw[lo:hi],
                "char_offset": off, "person_id": pid, "source_record_key": row["source_record_key"],
                "page_from": row["page_from"], "suggested_default_action": DEFAULT_ACTION[flag["kind"]],
            })
    all_flags.sort(key=lambda f: f["flag_id"])
    if expected_flag_counts is not None and flag_counts != expected_flag_counts:
        _fail("NARRATIVE_MANIFEST_ARITHMETIC_MISMATCH:flag_counts")

    flags_document = {
        "schema_version": "1939-v50-narrative-replacement-flags-v1",
        "generator_version": "build_narrative_replacement_manifest_1939_v50.py:v1",
        "input_hashes": {
            "phase_a_manifest_sha256": input_hashes[0], "production_manifest_sha256": input_hashes[1],
            "narrative_publication_manifest_sha256": input_hashes[2], "calamari_sha256": input_hashes[3],
            "old_narrative_sha_export_sha256": input_hashes[4],
        },
        "source": {"edition": "1939", "logical_source_id": "1939", "database_source_id": 3,
                    "rendition_content_sha256": calamari_sha256},
        "scope": {
            "total_source_narratives": len(old_sha), "in_scope": len(scope),
            "bindings_create": len(scope_543), "bindings_existing": len(scope_8),
            "out_of_scope": len(out_of_scope_ids),
        },
        "flags": all_flags,
        "flag_counts": {**flag_counts, "total": len(all_flags)},
        "out_of_scope": out_of_scope,
    }
    flags_document["flags_content_sha256"] = canonical_sha(flags_document)

    if decisions_doc is None:
        return None, flags_document

    all_flag_ids = {f["flag_id"] for f in all_flags}
    decisions = _load_decisions(decisions_doc, all_flag_ids)

    operations: List[Dict[str, Any]] = []
    for pid in sorted(scope):
        row = scope[pid]
        raw = row["verbatim_text"]
        default = defaults[pid]
        op_flags = default["flags"]
        text = (_decided_text(raw, calamari_text, default["text"], op_flags, decisions, row["source_record_key"])
                if op_flags else default["text"])
        operations.append({
            "person_id": pid,
            "source_record_key": row["source_record_key"],
            "source_span": row["source_span"],
            "page_from": row["page_from"],
            "raw_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
            "normalized_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            "normalized_text": text,
            "expected_old_narrative_sha256": old_sha[pid],
            "binding": row["binding"],
            "record_label": row["source_record_key"],
            "citation_label": f"DAA 1939 side {row['page_from']}",
        })

    counts = {
        "narratives": len(operations), "updates": len(operations), "inserts": 0,
        "bindings_create": len(scope_543), "bindings_existing": len(scope_8),
    }
    manifest = {
        "schema_version": "1939-v50-narrative-replacement-manifest-v1",
        "generator_version": "build_narrative_replacement_manifest_1939_v50.py:v1",
        "input_hashes": {
            "phase_a_manifest_sha256": input_hashes[0], "production_manifest_sha256": input_hashes[1],
            "narrative_publication_manifest_sha256": input_hashes[2], "calamari_sha256": input_hashes[3],
            "old_narrative_sha_export_sha256": input_hashes[4], "decisions_sha256": decisions_sha256,
        },
        "source": {"edition": "1939", "logical_source_id": "1939", "database_source_id": 3,
                    "rendition_content_sha256": calamari_sha256},
        "operations": operations,
        "counts": counts,
        "flags": [],
        "out_of_scope": out_of_scope,
        "production_authorized": False, "apply_gate": "NO-GO",
    }
    manifest["manifest_content_sha256"] = canonical_sha(manifest)
    return manifest, flags_document


def build_narrative_replacement_manifest(
    phase_a_manifest, production_manifest, pub_manifest, calamari_text, old_sha_export,
    *, input_hashes, decisions_doc=None, decisions_sha256=None,
):
    """Public entrypoint -- pins the production universe (the 5 locked
    input hashes + the 543/8/551/577/26 aritmetik). Fixtures/tests wanting
    other values call ``_build_narrative_replacement`` directly."""
    if list(input_hashes) != LOCKED_INPUT_HASHES:
        _fail("NARRATIVE_MANIFEST_HASH_NOT_LOCKED")
    return _build_narrative_replacement(
        phase_a_manifest, production_manifest, pub_manifest, calamari_text, old_sha_export,
        input_hashes=input_hashes, decisions_doc=decisions_doc, decisions_sha256=decisions_sha256,
        expected_bindings_create=EXPECTED_BINDINGS_CREATE, expected_bindings_existing=EXPECTED_BINDINGS_EXISTING,
        expected_out_of_scope=EXPECTED_OUT_OF_SCOPE,
        expected_total_source_narratives=EXPECTED_TOTAL_SOURCE_NARRATIVES,
        expected_in_scope=EXPECTED_IN_SCOPE, expected_flag_counts=EXPECTED_FLAG_COUNTS,
    )


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser()
    for name in ("phase-a-manifest", "production-manifest", "narrative-publication-manifest",
                 "calamari", "old-narrative-sha-export"):
        p.add_argument(f"--{name}", required=True)
        p.add_argument(f"--{name}-sha256", required=True)
    p.add_argument("--decisions")
    p.add_argument("--decisions-sha256")
    p.add_argument("--flags-output", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args(argv)

    if bool(a.decisions) != bool(a.decisions_sha256):
        _fail("NARRATIVE_MANIFEST_DECISIONS_ARGS_INCOMPLETE")

    flags_output = Path(a.flags_output)
    output = Path(a.output)
    writing_manifest = a.decisions is not None
    target = output if writing_manifest else flags_output
    if target.exists():
        _fail("NARRATIVE_MANIFEST_OUTPUT_EXISTS")

    paths = [a.phase_a_manifest, a.production_manifest, a.narrative_publication_manifest,
             a.calamari, a.old_narrative_sha_export]
    supplied = [a.phase_a_manifest_sha256, a.production_manifest_sha256,
                a.narrative_publication_manifest_sha256, a.calamari_sha256,
                a.old_narrative_sha_export_sha256]
    raw = [Path(path).read_bytes() for path in paths]
    if [hashlib.sha256(x).hexdigest() for x in raw] != supplied:
        _fail("NARRATIVE_MANIFEST_HASH_INVALID")
    phase_a_manifest = json.loads(raw[0])
    production_manifest = json.loads(raw[1])
    pub_manifest = json.loads(raw[2])
    calamari_text = raw[3].decode("utf-8")
    old_sha_export = json.loads(raw[4])

    decisions_doc = None
    if a.decisions is not None:
        decisions_bytes = Path(a.decisions).read_bytes()
        if hashlib.sha256(decisions_bytes).hexdigest() != a.decisions_sha256:
            _fail("NARRATIVE_MANIFEST_HASH_INVALID")
        decisions_doc = json.loads(decisions_bytes)

    manifest, flags_document = build_narrative_replacement_manifest(
        phase_a_manifest, production_manifest, pub_manifest, calamari_text, old_sha_export,
        input_hashes=supplied, decisions_doc=decisions_doc, decisions_sha256=a.decisions_sha256,
    )

    if manifest is None:
        flags_output.write_text(json.dumps(flags_document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(flags_output), "scope": flags_document["scope"],
                           "flag_counts": flags_document["flag_counts"], "manifest_written": False},
                          sort_keys=True))
        return 2

    output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "counts": manifest["counts"], "manifest_written": True},
                      sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
