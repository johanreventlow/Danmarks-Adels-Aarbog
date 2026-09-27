#!/usr/bin/env python3
"""Afstem én clause_evidence-kørsel mod to læse-kun projektioner (spec §11.1, vej C).

Udgaveneutral: scriptet kender ingen udgave, fase eller historik. Et `match` beviser
kun DELTAET af én kørsel mod den godkendte måldatabase:

1. de fem kildeprojektioner, helrækkehashes af de neutrale tabeller og det, rollen
   `anon` kan se, er uændrede;
2. klausulerne for manifestets records er præcis manifestets klausuler, felt for felt,
   og bærer writerens egne invarianter (forekomst, forælder, sider, kvalitet, kørsel,
   maskinel disposition med batchens evidens);
3. de stammer fra ÉN færdig batch med manifestets genberegnede hash;
4. ingen anden klausul i kildens inventar er tilføjet, fjernet eller ændret.

Revisionstilstand (omsegmentering, spec 2026-09-27): for et clause_revision-manifest
beviser `match`, at hver post har fået præcis manifestets nye klausulsæt (sæt n+1), at det
erstattede sæt står uændret bortset fra én ny `erstattet`-disposition, at ældre sæt er
urørte, og at eventen bærer før- og efter-hash. Tilstanden vælges af manifestets tælling.

Det beviser IKKE, at prod er summen af tidligere faser, og det dækker kun de tabeller,
projektionen hasher. Scriptet åbner aldrig en database.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections import Counter
from pathlib import Path
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clause_set  # noqa: E402

PROJECTION_SCHEMA = "daa-clause-evidence-projection-v2"
RESULT_SCOPE = "clause-evidence-delta-v1"
REVISION_SCOPE = "clause-revision-delta-v1"
ELEMENT_PREFIX = "clause-evidence:"
REVISION_PREFIX = "clause-revision:"
NEUTRAL_LISTS = ("source_records", "source_anchors", "narrative_bindings", "narrative_sha256", "persons")
NEUTRAL_ROW_KEYS = {
    "source_records": frozenset(("record_key",)),
    "source_anchors": frozenset(("record_key", "occurrence_key")),
    "narrative_bindings": frozenset(("record_key", "narrative_id", "status")),
    "narrative_sha256": frozenset(("narrative_id", "sha256")),
    "persons": frozenset(("person_id",)),
}
# Uden kilde-records og ankre findes intet at skrive klausuler på.
ALWAYS_NONEMPTY = ("source_records", "source_anchors")
NEUTRAL_HASH_TABLES = (
    "person", "fact", "assertion", "conclusion", "narrative", "relation", "family_member",
    "citation", "person_external_id", "source_mention", "source_record", "source_record_occurrence",
    "source_record_anchor_event", "narrative_record_publication", "source_observation_non_clause",
    "source_observation_clause_other_sources", "clause_disposition_other_sources",
)
ANON_HASH_TABLES = ("assertion", "citation", "conclusion", "fact", "family_member", "narrative",
                    "person", "person_external_id")
EXPECTED_FIELDS = ("record_key", "clause_ordinal", "char_from", "char_to", "post_char_from",
                   "post_char_to", "classification", "flags", "verbatim_sha256",
                   "parent_verbatim_sha256", "disposition", "disposition_version")
BOOLEAN_FIELDS = ("same_occurrence_as_parent", "parent_is_root", "pages_match_parent",
                  "quality_matches_parent", "run_matches_profile", "extraction_method_matches_profile")
INVARIANT_FIELDS = ("decided_by_kind", "disposition_evidence", "disposition_evidence_keys", "extraction_method",
                    "run_input_sha256", "run_batch_id") + BOOLEAN_FIELDS
IDENTITY_FIELDS = ("observation_id", "occurrence_key", "row_sha256", "disposition_history_sha256", "run_id")
SET_FIELDS = ("clause_set_seq", "clause_set_sha256", "is_current_set")
CLAUSE_FIELDS = frozenset(EXPECTED_FIELDS + INVARIANT_FIELDS + IDENTITY_FIELDS + SET_FIELDS)
EVENT_FIELDS = frozenset(("batch_id", "manifest_sha256", "batch_status", "profile_id", "profile_sha256",
                          "row_sha256", "element_id", "source_record_key", "operation",
                          "before_clause_set_sha256", "after_clause_set_sha256"))
EVENT_OPERATIONS = frozenset(("clause_evidence", "clause_revision"))
# Felter, en revision må ændre på en klausul i det erstattede sæt (den nye `erstattet`-
# disposition). Alt andet på rækken skal være uændret.
REPLACED_CHANGING_FIELDS = frozenset(("disposition", "disposition_version", "is_current_set",
                                      "disposition_history_sha256", "decided_by_kind", "disposition_evidence",
                                      "disposition_evidence_keys", "extraction_method_matches_profile"))
PROJECTION_KEYS = frozenset(("schema_version", "source_id", "database_target_identity", "clauses",
                             "clause_evidence_events", "neutral_sha256", "anon_sha256") + NEUTRAL_LISTS)
MANIFEST_TOP_REQUIRED = frozenset(("manifest_content_sha256", "source", "expected_counts", "operations"))
MANIFEST_TOP_OPTIONAL = frozenset(("provenance",))
MANIFEST_SOURCE_KEYS = frozenset(("id", "profile_id", "profile_sha256"))
MANIFEST_COUNT_KEYS = frozenset(("source_evidence", "person_creates", "canonical_delta", "clause_evidence"))
MANIFEST_REVISION_COUNT_KEYS = frozenset(("source_evidence", "person_creates", "canonical_delta", "clause_revisions"))
MANIFEST_OPERATION_KEYS = frozenset((
    "element_id", "dependency_class", "source_record_key", "rendition_content_sha256",
    "rendition_projection_sha256", "parent_verbatim_sha256", "clause_rules_version",
    "segmenter_version", "ledger_sha256", "gap_charset", "clauses"))
MANIFEST_CLAUSE_KEYS = frozenset(("char_from", "char_to", "classification", "flags", "ordinal",
                                  "rendition_char_from", "rendition_char_to", "verbatim_sha256"))


class ProjectionError(ValueError):
    """NO-GO. `details` bærer kun nøgler, feltnavne og antal, aldrig værdier eller tekst."""

    def __init__(self, code: str, details: dict[str, Any] | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.details = details or {}


def _fail(code: str, **details: Any) -> None:
    raise ProjectionError(code, details)


def _is_sha(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _is_int(value: Any) -> bool:
    return type(value) is int


def _canon(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _canon_set(rows: list[Any]) -> list[str]:
    return sorted(_canon(r) for r in rows)


def compute_manifest_sha256(manifest: dict[str, Any]) -> str:
    """Præcis build_clause_evidence_manifest.py's formel (hash over manifestet uden hash-feltet)."""
    body = {k: v for k, v in manifest.items() if k != "manifest_content_sha256"}
    return hashlib.sha256(_canon(body).encode("utf-8")).hexdigest()


def target_sha256(identity: dict[str, Any]) -> str:
    """Samme formel som clause_evidence_target_identity.sql."""
    text = f"{identity['database_name']}\n{identity['system_identifier_sha256']}"
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _disposition(classification: str, flags: list[str]) -> str:
    # Spejler private.write_clause_evidence (db-migrations.sql, `v_disposition:=CASE`).
    if classification == "structural_header":
        return "strukturel"
    if flags:
        return "maskinelt_flagget"
    return "afventer_fortolkning"


def _validate_hashes(p: dict[str, Any], key: str, tables: tuple[str, ...]) -> None:
    group = p[key]
    if not isinstance(group, dict) or set(group) != set(tables) or not all(_is_sha(v) for v in group.values()):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part=key)


def _validate_projection(p: Any, allow_empty: frozenset[str]) -> list[dict[str, Any]]:
    if not isinstance(p, dict) or set(p) != PROJECTION_KEYS:
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="keys")
    if p["schema_version"] != PROJECTION_SCHEMA or not _is_int(p["source_id"]) or p["source_id"] <= 0:
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="header")
    identity = p["database_target_identity"]
    if (not isinstance(identity, dict) or set(identity) != {"database_name", "system_identifier_sha256"}
            or not isinstance(identity["database_name"], str) or not _is_sha(identity["system_identifier_sha256"])):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="database_target_identity")
    _validate_hashes(p, "neutral_sha256", NEUTRAL_HASH_TABLES)
    _validate_hashes(p, "anon_sha256", ANON_HASH_TABLES)
    for name in NEUTRAL_LISTS + ("clause_evidence_events", "clauses"):
        rows = p[name]
        if not isinstance(rows, list) or not all(isinstance(r, dict) for r in rows):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part=name)
    for name in NEUTRAL_LISTS:
        if not all(set(r) == NEUTRAL_ROW_KEYS[name] for r in p[name]):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part=name)
        if len(set(_canon_set(p[name]))) != len(p[name]):
            _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part=name)
        if not p[name] and (name in ALWAYS_NONEMPTY or name not in allow_empty):
            _fail("CLAUSE_PROJECTION_EMPTY_LIST", part=name)
    events = p["clause_evidence_events"]
    if not all(set(e) == EVENT_FIELDS and isinstance(e["batch_id"], str) and isinstance(e["element_id"], str)
               and _is_sha(e["row_sha256"]) and e["operation"] in EVENT_OPERATIONS for e in events):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="clause_evidence_events")
    if len({(e["batch_id"], e["element_id"]) for e in events}) != len(events):
        _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clause_evidence_events")
    seen: set[str] = set()
    for row in p["clauses"]:
        if (set(row) != CLAUSE_FIELDS or not isinstance(row["observation_id"], str)
                or not isinstance(row["occurrence_key"], str)
                or not (row["record_key"] is None or isinstance(row["record_key"], str))
                or not _is_int(row["clause_ordinal"])
                or not _is_sha(row["row_sha256"]) or not _is_sha(row["disposition_history_sha256"])
                or not all(type(row[f]) is bool for f in BOOLEAN_FIELDS)
                or not _is_int(row["clause_set_seq"]) or row["clause_set_seq"] < 1
                or not _is_sha(row["clause_set_sha256"]) or type(row["is_current_set"]) is not bool):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="clauses")
        if row["observation_id"] in seen:
            _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clauses")
        seen.add(row["observation_id"])
    return p["clauses"]


def _validate_manifest(manifest: Any, mode: str = "evidence") -> dict[str, dict[str, Any]]:
    revision = mode == "revision"
    count_keys = MANIFEST_REVISION_COUNT_KEYS if revision else MANIFEST_COUNT_KEYS
    count_key = "clause_revisions" if revision else "clause_evidence"
    op_keys = MANIFEST_OPERATION_KEYS | ({"replaces_clause_set_seq", "replaces_clause_set_sha256"} if revision else set())
    prefix, dependency = (REVISION_PREFIX, "clause_revision") if revision else (ELEMENT_PREFIX, "clause_evidence")

    def bad(part: str) -> None:
        _fail("CLAUSE_PROJECTION_MANIFEST_INVALID", part=part)

    if not isinstance(manifest, dict):
        bad("top")
    keys = set(manifest)
    if not (MANIFEST_TOP_REQUIRED <= keys <= MANIFEST_TOP_REQUIRED | MANIFEST_TOP_OPTIONAL):
        bad("top")
    if not _is_sha(manifest["manifest_content_sha256"]):
        bad("manifest_content_sha256")
    source = manifest["source"]
    if not isinstance(source, dict) or set(source) != MANIFEST_SOURCE_KEYS or not _is_int(source["id"]):
        bad("source")
    operations = manifest["operations"]
    if not isinstance(operations, list) or not operations:
        bad("operations")
    counts = manifest["expected_counts"]
    if (not isinstance(counts, dict) or set(counts) != count_keys
            or counts[count_key] != len(operations)
            or any(counts[k] != 0 for k in ("source_evidence", "person_creates", "canonical_delta"))):
        bad("expected_counts")
    by_key: dict[str, dict[str, Any]] = {}
    for op in operations:
        if not isinstance(op, dict) or set(op) != op_keys:
            bad("operation")
        key = op["source_record_key"]
        if (not isinstance(key, str) or not key or key in by_key
                or op["element_id"] != prefix + key
                or op["dependency_class"] != dependency
                or (revision and (not _is_int(op["replaces_clause_set_seq"]) or op["replaces_clause_set_seq"] < 1
                                  or not _is_sha(op["replaces_clause_set_sha256"])))
                or not _is_sha(op["parent_verbatim_sha256"])
                or not isinstance(op["clause_rules_version"], str) or not op["clause_rules_version"]):
            bad("operation")
        clauses = op["clauses"]
        if not isinstance(clauses, list) or not clauses:
            bad("clauses")
        for index, c in enumerate(clauses, start=1):
            if (not isinstance(c, dict) or set(c) != MANIFEST_CLAUSE_KEYS or c["ordinal"] != index
                    or not isinstance(c["flags"], list) or not _is_sha(c["verbatim_sha256"])):
                bad("clause")
        by_key[key] = op
    if compute_manifest_sha256(manifest) != manifest["manifest_content_sha256"]:
        _fail("CLAUSE_PROJECTION_MANIFEST_HASH_MISMATCH")
    return by_key


def expected_clauses(manifest: Any, mode: str = "evidence") -> dict[tuple[str, int], dict[str, Any]]:
    """Manifestets klausuler som projektionsrækker (kun EXPECTED_FIELDS)."""
    rows: dict[tuple[str, int], dict[str, Any]] = {}
    for key, op in _validate_manifest(manifest, mode).items():
        for c in op["clauses"]:
            rows[(key, c["ordinal"])] = {
                "record_key": key, "clause_ordinal": c["ordinal"],
                "char_from": c["rendition_char_from"], "char_to": c["rendition_char_to"],
                "post_char_from": c["char_from"], "post_char_to": c["char_to"],
                "classification": c["classification"], "flags": list(c["flags"]),
                "verbatim_sha256": c["verbatim_sha256"],
                "parent_verbatim_sha256": op["parent_verbatim_sha256"],
                "disposition": _disposition(c["classification"], c["flags"]),
                "disposition_version": 1,
            }
    return rows


def _common_checks(manifest: Any, before: Any, after: Any, expected_target_sha256: str,
                   record_keys: set[str]) -> str:
    """Fælles for begge tilstande: kilde, mål, kendte records og neutralitet."""
    if not (manifest["source"]["id"] == before["source_id"] == after["source_id"]):
        _fail("CLAUSE_PROJECTION_SOURCE_MISMATCH")
    if before["database_target_identity"] != after["database_target_identity"]:
        _fail("CLAUSE_PROJECTION_TARGET_MISMATCH")
    target = target_sha256(after["database_target_identity"])
    if target != expected_target_sha256:
        _fail("CLAUSE_PROJECTION_TARGET_UNEXPECTED")
    unknown = record_keys - {r["record_key"] for r in after["source_records"]}
    if unknown:
        _fail("CLAUSE_PROJECTION_RECORD_UNKNOWN", records=len(unknown))

    drifted = [n for n in NEUTRAL_LISTS if _canon_set(before[n]) != _canon_set(after[n])]
    if drifted:
        _fail("CLAUSE_PROJECTION_NEUTRALITY_DRIFT", lists=drifted)
    tables = [t for t in NEUTRAL_HASH_TABLES if before["neutral_sha256"][t] != after["neutral_sha256"][t]]
    if tables:
        _fail("CLAUSE_PROJECTION_CANONICAL_DRIFT", tables=tables)
    anon = [t for t in ANON_HASH_TABLES if before["anon_sha256"][t] != after["anon_sha256"][t]]
    if anon:
        _fail("CLAUSE_PROJECTION_ANON_DRIFT", tables=anon)
    return target


def _foreign_unchanged(before_clauses: list[dict[str, Any]], after_clauses: list[dict[str, Any]],
                       record_keys: set[str]) -> None:
    # Fremmede klausuler (ikke manifestets records) sammenlignes på hele rækken, inkl.
    # helrækkehash og hele dispositionshistorikken, med databasens egen identitet.
    foreign_before = {r["observation_id"]: _canon(r) for r in before_clauses if r["record_key"] not in record_keys}
    foreign_after = {r["observation_id"]: _canon(r) for r in after_clauses if r["record_key"] not in record_keys}
    if foreign_before != foreign_after:
        changed = set(foreign_before) ^ set(foreign_after)
        changed |= {k for k in set(foreign_before) & set(foreign_after) if foreign_before[k] != foreign_after[k]}
        _fail("CLAUSE_PROJECTION_FOREIGN_DRIFT", clauses=len(changed))


def _new_events(before: Any, after: Any) -> list[dict[str, Any]]:
    # Ældre hændelser skal være bevaret uændret, FØR det nye delta beregnes; ellers kan
    # en slettet gammel hændelse gemme sig bag en korrekt ny.
    after_events = set(_canon_set(after["clause_evidence_events"]))
    lost = [e for e in before["clause_evidence_events"] if _canon(e) not in after_events]
    if lost:
        _fail("CLAUSE_PROJECTION_EVENT_HISTORY_DRIFT", events=len(lost))
    before_events = set(_canon_set(before["clause_evidence_events"]))
    return [e for e in after["clause_evidence_events"] if _canon(e) not in before_events]


def compare(manifest: Any, before: Any, after: Any, expected_target_sha256: str,
            allow_empty: frozenset[str] = frozenset()) -> dict[str, Any]:
    if isinstance(manifest, dict) and isinstance(manifest.get("expected_counts"), dict) \
            and "clause_revisions" in manifest["expected_counts"]:
        return compare_revision(manifest, before, after, expected_target_sha256, allow_empty)
    before_clauses = _validate_projection(before, allow_empty)
    after_clauses = _validate_projection(after, allow_empty)
    expected = expected_clauses(manifest)
    operations = {op["source_record_key"]: op for op in manifest["operations"]}
    record_keys = set(operations)
    manifest_sha = manifest["manifest_content_sha256"]
    target = _common_checks(manifest, before, after, expected_target_sha256, record_keys)

    preexisting = {r["record_key"] for r in before_clauses if r["record_key"] in record_keys}
    if preexisting:
        _fail("CLAUSE_PROJECTION_PREEXISTING", records=len(preexisting))
    _foreign_unchanged(before_clauses, after_clauses, record_keys)
    new_events = _new_events(before, after)
    batch_ids = {e["batch_id"] for e in new_events}
    element_ids = sorted(ELEMENT_PREFIX + k for k in record_keys)
    source = manifest["source"]
    binding_ok = (
        len(batch_ids) == 1
        and not any(e["manifest_sha256"] == manifest_sha or e["batch_id"] in batch_ids
                    for e in before["clause_evidence_events"])
        and len(new_events) == len(element_ids)
        and all(e["manifest_sha256"] == manifest_sha and e["batch_status"] == "finalized"
                and e["profile_id"] == source["profile_id"] and e["profile_sha256"] == source["profile_sha256"]
                and e["element_id"] == ELEMENT_PREFIX + str(e["source_record_key"])
                and e["operation"] == "clause_evidence"
                and e["before_clause_set_sha256"] is None and e["after_clause_set_sha256"] is None
                for e in new_events)
        and sorted(e["element_id"] for e in new_events) == element_ids
    )
    if not binding_ok:
        _fail("CLAUSE_PROJECTION_BATCH_BINDING_INVALID", new_events=len(new_events),
              batches=len(batch_ids), expected=len(element_ids))
    batch_id = next(iter(batch_ids))

    actual: dict[tuple[str, int], dict[str, Any]] = {}
    for row in after_clauses:
        if row["record_key"] in record_keys:
            key = (row["record_key"], row["clause_ordinal"])
            if key in actual:
                _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clauses")
            actual[key] = row
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    mismatched = []
    for key in sorted(set(expected) & set(actual)):
        fields = [f for f in EXPECTED_FIELDS if _canon(expected[key][f]) != _canon(actual[key][f])]
        if fields:
            mismatched.append({"record_key": key[0], "clause_ordinal": key[1], "fields": fields})
    if missing or extra or mismatched:
        _fail("CLAUSE_PROJECTION_DRIFT", missing=[list(k) for k in missing],
              extra=[list(k) for k in extra], mismatched=mismatched)

    failed: set[str] = set()
    for (record_key, _), row in actual.items():
        rules = operations[record_key]["clause_rules_version"]
        checks = {
            "decided_by_kind": row["decided_by_kind"] == "machine",
            "disposition_evidence": row["disposition_evidence"] == {
                "batch_id": batch_id, "element_id": ELEMENT_PREFIX + record_key,
                "manifest_sha256": manifest_sha, "clause_rules_version": rules},
            "disposition_evidence_keys": row["disposition_evidence_keys"] == ["batch_id", "clause_rules_version", "element_id", "manifest_sha256"],
            "extraction_method": isinstance(row["extraction_method"], str)
            and row["extraction_method"].endswith(":" + rules),
            "run_input_sha256": row["run_input_sha256"] == manifest_sha,
            "run_batch_id": row["run_batch_id"] == batch_id,
            "clause_set_seq": row["clause_set_seq"] == 1,
            "is_current_set": row["is_current_set"] is True,
            "clause_set_sha256": row["clause_set_sha256"] == clause_set.clause_set_sha256(operations[record_key]["clauses"]),
        }
        checks.update({f: row[f] is True for f in BOOLEAN_FIELDS})
        failed |= {name for name, ok in checks.items() if not ok}
    if len({row["run_id"] for row in actual.values()}) != 1:
        failed.add("run_id")
    if failed:
        _fail("CLAUSE_PROJECTION_WRITER_INVARIANT_INVALID", invariants=sorted(failed))

    dispositions = Counter(row["disposition"] for row in expected.values())
    return {
        "status": "match",
        "scope": RESULT_SCOPE,
        "source_id": after["source_id"],
        "database_target_sha256": target,
        "manifest_content_sha256": manifest_sha,
        "batch_id": batch_id,
        "counts": {
            "records": len(record_keys),
            "clauses": len(expected),
            "dispositions": dict(sorted(dispositions.items())),
            "neutral_lists": {n: len(after[n]) for n in NEUTRAL_LISTS},
            "allowed_empty": sorted(n for n in allow_empty if not after[n]),
        },
    }


def compare_revision(manifest: Any, before: Any, after: Any, expected_target_sha256: str,
                     allow_empty: frozenset[str] = frozenset()) -> dict[str, Any]:
    """Afstem én clause_revision-kørsel (omsegmentering, spec 2026-09-27)."""
    before_clauses = _validate_projection(before, allow_empty)
    after_clauses = _validate_projection(after, allow_empty)
    by_key = _validate_manifest(manifest, "revision")
    expected = expected_clauses(manifest, "revision")
    record_keys = set(by_key)
    manifest_sha = manifest["manifest_content_sha256"]
    source = manifest["source"]
    target = _common_checks(manifest, before, after, expected_target_sha256, record_keys)

    # Basen: postens aktuelle sæt FØR kørslen er præcis det, manifestet erstatter.
    before_rows = {k: [r for r in before_clauses if r["record_key"] == k] for k in record_keys}
    for key, op in by_key.items():
        current = [r for r in before_rows[key] if r["is_current_set"]]
        if (not current or {r["clause_set_seq"] for r in current} != {op["replaces_clause_set_seq"]}
                or {r["clause_set_sha256"] for r in current} != {op["replaces_clause_set_sha256"]}):
            _fail("CLAUSE_PROJECTION_REVISION_BASE_DRIFT", record=key)
    _foreign_unchanged(before_clauses, after_clauses, record_keys)

    new_events = _new_events(before, after)
    batch_ids = {e["batch_id"] for e in new_events}
    element_ids = sorted(REVISION_PREFIX + k for k in record_keys)
    binding_ok = (
        len(batch_ids) == 1
        and not any(e["manifest_sha256"] == manifest_sha or e["batch_id"] in batch_ids
                    for e in before["clause_evidence_events"])
        and len(new_events) == len(element_ids)
        and all(e["manifest_sha256"] == manifest_sha and e["batch_status"] == "finalized"
                and e["profile_id"] == source["profile_id"] and e["profile_sha256"] == source["profile_sha256"]
                and e["operation"] == "clause_revision"
                and e["element_id"] == REVISION_PREFIX + str(e["source_record_key"])
                and str(e["source_record_key"]) in by_key
                and e["before_clause_set_sha256"] == by_key[str(e["source_record_key"])]["replaces_clause_set_sha256"]
                and e["after_clause_set_sha256"] == clause_set.clause_set_sha256(by_key[str(e["source_record_key"])]["clauses"])
                for e in new_events)
        and sorted(e["element_id"] for e in new_events) == element_ids
    )
    if not binding_ok:
        _fail("CLAUSE_PROJECTION_BATCH_BINDING_INVALID", new_events=len(new_events),
              batches=len(batch_ids), expected=len(element_ids))
    batch_id = next(iter(batch_ids))

    after_by_id = {r["observation_id"]: r for r in after_clauses}
    failed: set[str] = set()
    replaced_count = 0
    actual: dict[tuple[str, int], dict[str, Any]] = {}
    for key, op in by_key.items():
        seq = op["replaces_clause_set_seq"]
        # Det erstattede sæt og ældre sæt: samme rækker, kun den nye `erstattet`-disposition.
        for old in before_rows[key]:
            new = after_by_id.get(old["observation_id"])
            if new is None:
                _fail("CLAUSE_PROJECTION_REVISION_HISTORY_DRIFT", record=key)
            if not old["is_current_set"]:
                if _canon(new) != _canon(old):
                    _fail("CLAUSE_PROJECTION_REVISION_HISTORY_DRIFT", record=key)
                continue
            replaced_count += 1
            changed = {f for f in CLAUSE_FIELDS if _canon(new[f]) != _canon(old[f])}
            if not changed <= REPLACED_CHANGING_FIELDS:
                _fail("CLAUSE_PROJECTION_REVISION_HISTORY_DRIFT", record=key, fields=sorted(changed - REPLACED_CHANGING_FIELDS))
            checks = {
                "replaced_disposition": new["disposition"] == "erstattet",
                "replaced_version": new["disposition_version"] == old["disposition_version"] + 1,
                "replaced_not_current": new["is_current_set"] is False,
                "replaced_machine": new["decided_by_kind"] == "machine",
                "replaced_evidence": new["disposition_evidence"] == {
                    "batch_id": batch_id, "element_id": REVISION_PREFIX + key,
                    "manifest_sha256": manifest_sha, "replaced_by_clause_set_seq": seq + 1},
                "replaced_evidence_keys": new["disposition_evidence_keys"] == [
                    "batch_id", "element_id", "manifest_sha256", "replaced_by_clause_set_seq"],
            }
            failed |= {name for name, ok in checks.items() if not ok}
        # Det nye sæt: præcis manifestets klausuler.
        for row in after_clauses:
            if row["record_key"] != key or row["observation_id"] in {r["observation_id"] for r in before_rows[key]}:
                continue
            k = (key, row["clause_ordinal"])
            if k in actual:
                _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clauses")
            actual[k] = row
            rules = op["clause_rules_version"]
            checks = {
                "decided_by_kind": row["decided_by_kind"] == "machine",
                "disposition_evidence": row["disposition_evidence"] == {
                    "batch_id": batch_id, "element_id": REVISION_PREFIX + key,
                    "manifest_sha256": manifest_sha, "clause_rules_version": rules},
                "disposition_evidence_keys": row["disposition_evidence_keys"] == ["batch_id", "clause_rules_version", "element_id", "manifest_sha256"],
                "extraction_method": isinstance(row["extraction_method"], str) and row["extraction_method"].endswith(":" + rules),
                "run_input_sha256": row["run_input_sha256"] == manifest_sha,
                "run_batch_id": row["run_batch_id"] == batch_id,
                "clause_set_seq": row["clause_set_seq"] == seq + 1,
                "is_current_set": row["is_current_set"] is True,
                "clause_set_sha256": row["clause_set_sha256"] == clause_set.clause_set_sha256(op["clauses"]),
            }
            checks.update({f: row[f] is True for f in BOOLEAN_FIELDS})
            failed |= {name for name, ok in checks.items() if not ok}
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    mismatched = []
    for k in sorted(set(expected) & set(actual)):
        fields = [f for f in EXPECTED_FIELDS if _canon(expected[k][f]) != _canon(actual[k][f])]
        if fields:
            mismatched.append({"record_key": k[0], "clause_ordinal": k[1], "fields": fields})
    if missing or extra or mismatched:
        _fail("CLAUSE_PROJECTION_DRIFT", missing=[list(k) for k in missing],
              extra=[list(k) for k in extra], mismatched=mismatched)
    if len({row["run_id"] for row in actual.values()}) != 1:
        failed.add("run_id")
    if failed:
        _fail("CLAUSE_PROJECTION_WRITER_INVARIANT_INVALID", invariants=sorted(failed))

    dispositions = Counter(row["disposition"] for row in expected.values())
    return {
        "status": "match",
        "scope": REVISION_SCOPE,
        "source_id": after["source_id"],
        "database_target_sha256": target,
        "manifest_content_sha256": manifest_sha,
        "batch_id": batch_id,
        "counts": {
            "records": len(record_keys),
            "clauses_written": len(expected),
            "clauses_replaced": replaced_count,
            "dispositions": dict(sorted(dispositions.items())),
            "neutral_lists": {n: len(after[n]) for n in NEUTRAL_LISTS},
            "allowed_empty": sorted(n for n in allow_empty if not after[n]),
        },
    }


ALLOWED_EMPTY_CHOICES = frozenset(("narrative_bindings", "narrative_sha256", "persons"))


class UsageError(ValueError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _inside_repository(path: Path) -> bool:
    return any((parent / ".git").exists() for parent in (path.parent, *path.parent.parents))


def _check_report_path(raw: str) -> Path:
    path = Path(raw).expanduser().absolute()
    if not path.parent.is_dir():
        raise UsageError("CLAUSE_PROJECTION_REPORT_DIR_MISSING")
    if _inside_repository(path):
        raise UsageError("CLAUSE_PROJECTION_REPORT_IN_REPOSITORY")
    if path.exists() or path.is_symlink():
        raise UsageError("CLAUSE_PROJECTION_REPORT_EXISTS")
    return path


def _load(raw: str) -> tuple[Any, str]:
    try:
        data = Path(raw).expanduser().read_bytes()
        return json.loads(data.decode("utf-8")), hashlib.sha256(data).hexdigest()
    except (OSError, ValueError):
        raise UsageError("CLAUSE_PROJECTION_INPUT_UNREADABLE") from None


def _write_private(path: Path, data: dict[str, Any]) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, sort_keys=True, indent=2)
        handle.write("\n")
    os.chmod(path, 0o600)


def _emit(data: dict[str, Any]) -> None:
    print(json.dumps(data, ensure_ascii=False, sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--print-manifest-sha256")
    parser.add_argument("--manifest")
    parser.add_argument("--before")
    parser.add_argument("--after")
    parser.add_argument("--expect-target-sha256")
    parser.add_argument("--report")
    parser.add_argument("--allow-empty", default="")
    args = parser.parse_args(argv)
    if args.print_manifest_sha256:
        try:
            manifest, _ = _load(args.print_manifest_sha256)
            if not isinstance(manifest, dict):
                raise UsageError("CLAUSE_PROJECTION_INPUT_UNREADABLE")
        except UsageError as error:
            _emit({"status": "usage_error", "code": error.code})
            return 2
        print(compute_manifest_sha256(manifest))
        return 0
    try:
        if not all((args.manifest, args.before, args.after, args.expect_target_sha256, args.report)):
            raise UsageError("CLAUSE_PROJECTION_ARGUMENTS_MISSING")
        if not _is_sha(args.expect_target_sha256):
            raise UsageError("CLAUSE_PROJECTION_EXPECTED_TARGET_INVALID")
        allow_empty = frozenset(x for x in args.allow_empty.split(",") if x)
        if not allow_empty <= ALLOWED_EMPTY_CHOICES:
            raise UsageError("CLAUSE_PROJECTION_ALLOW_EMPTY_INVALID")
        report = _check_report_path(args.report)
        (manifest, manifest_sha), (before, before_sha), (after, after_sha) = (
            _load(args.manifest), _load(args.before), _load(args.after))
    except UsageError as error:
        _emit({"status": "usage_error", "code": error.code})
        return 2
    input_sha256 = {"manifest": manifest_sha, "before": before_sha, "after": after_sha}
    try:
        result: dict[str, Any] = dict(compare(manifest, before, after, args.expect_target_sha256, allow_empty),
                                      input_sha256=input_sha256)
        terminal = result
    except ProjectionError as error:
        result = {"status": "no_go", "code": error.code, "details": error.details, "input_sha256": input_sha256}
        terminal = {"status": "no_go", "code": error.code}
    _write_private(report, result)
    _emit(terminal)
    return 0 if result["status"] == "match" else 1


if __name__ == "__main__":
    sys.exit(main())
