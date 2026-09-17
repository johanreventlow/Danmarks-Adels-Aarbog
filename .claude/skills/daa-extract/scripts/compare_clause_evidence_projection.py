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

Det beviser IKKE, at prod er summen af tidligere faser, og det dækker kun de tabeller,
projektionen hasher. Scriptet åbner aldrig en database.
"""
from __future__ import annotations

import hashlib
import json
from collections import Counter
from typing import Any

PROJECTION_SCHEMA = "daa-clause-evidence-projection-v1"
RESULT_SCOPE = "clause-evidence-delta-v1"
ELEMENT_PREFIX = "clause-evidence:"
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
INVARIANT_FIELDS = ("decided_by_kind", "disposition_evidence", "extraction_method", "run_input_sha256",
                    "run_batch_id") + BOOLEAN_FIELDS
IDENTITY_FIELDS = ("observation_id", "occurrence_key", "row_sha256", "disposition_history_sha256", "run_id")
CLAUSE_FIELDS = frozenset(EXPECTED_FIELDS + INVARIANT_FIELDS + IDENTITY_FIELDS)
EVENT_FIELDS = frozenset(("batch_id", "manifest_sha256", "batch_status", "profile_id", "profile_sha256",
                          "row_sha256", "element_id", "source_record_key"))
PROJECTION_KEYS = frozenset(("schema_version", "source_id", "database_target_identity", "clauses",
                             "clause_evidence_events", "neutral_sha256", "anon_sha256") + NEUTRAL_LISTS)
MANIFEST_TOP_REQUIRED = frozenset(("manifest_content_sha256", "source", "expected_counts", "operations"))
MANIFEST_TOP_OPTIONAL = frozenset(("provenance",))
MANIFEST_SOURCE_KEYS = frozenset(("id", "profile_id", "profile_sha256"))
MANIFEST_COUNT_KEYS = frozenset(("source_evidence", "person_creates", "canonical_delta", "clause_evidence"))
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
               and _is_sha(e["row_sha256"]) for e in events):
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
                or not all(type(row[f]) is bool for f in BOOLEAN_FIELDS)):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="clauses")
        if row["observation_id"] in seen:
            _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clauses")
        seen.add(row["observation_id"])
    return p["clauses"]


def _validate_manifest(manifest: Any) -> dict[str, dict[str, Any]]:
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
    if (not isinstance(counts, dict) or set(counts) != MANIFEST_COUNT_KEYS
            or counts["clause_evidence"] != len(operations)
            or any(counts[k] != 0 for k in ("source_evidence", "person_creates", "canonical_delta"))):
        bad("expected_counts")
    by_key: dict[str, dict[str, Any]] = {}
    for op in operations:
        if not isinstance(op, dict) or set(op) != MANIFEST_OPERATION_KEYS:
            bad("operation")
        key = op["source_record_key"]
        if (not isinstance(key, str) or not key or key in by_key
                or op["element_id"] != ELEMENT_PREFIX + key
                or op["dependency_class"] != "clause_evidence"
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


def expected_clauses(manifest: Any) -> dict[tuple[str, int], dict[str, Any]]:
    """Manifestets klausuler som projektionsrækker (kun EXPECTED_FIELDS)."""
    rows: dict[tuple[str, int], dict[str, Any]] = {}
    for key, op in _validate_manifest(manifest).items():
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


def compare(manifest: Any, before: Any, after: Any, expected_target_sha256: str,
            allow_empty: frozenset[str] = frozenset()) -> dict[str, Any]:
    before_clauses = _validate_projection(before, allow_empty)
    after_clauses = _validate_projection(after, allow_empty)
    expected = expected_clauses(manifest)
    operations = {op["source_record_key"]: op for op in manifest["operations"]}
    record_keys = set(operations)
    manifest_sha = manifest["manifest_content_sha256"]

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

    preexisting = {r["record_key"] for r in before_clauses if r["record_key"] in record_keys}
    if preexisting:
        _fail("CLAUSE_PROJECTION_PREEXISTING", records=len(preexisting))
    # Fremmede klausuler (ikke manifestets records) sammenlignes på hele rækken, inkl.
    # helrækkehash og hele dispositionshistorikken, med databasens egen identitet.
    foreign_before = {r["observation_id"]: _canon(r) for r in before_clauses if r["record_key"] not in record_keys}
    foreign_after = {r["observation_id"]: _canon(r) for r in after_clauses if r["record_key"] not in record_keys}
    if foreign_before != foreign_after:
        changed = set(foreign_before) ^ set(foreign_after)
        changed |= {k for k in set(foreign_before) & set(foreign_after) if foreign_before[k] != foreign_after[k]}
        _fail("CLAUSE_PROJECTION_FOREIGN_DRIFT", clauses=len(changed))

    # Ældre hændelser skal være bevaret uændret, FØR det nye delta beregnes; ellers kan
    # en slettet gammel hændelse gemme sig bag en korrekt ny.
    after_events = set(_canon_set(after["clause_evidence_events"]))
    lost = [e for e in before["clause_evidence_events"] if _canon(e) not in after_events]
    if lost:
        _fail("CLAUSE_PROJECTION_EVENT_HISTORY_DRIFT", events=len(lost))
    before_events = set(_canon_set(before["clause_evidence_events"]))
    new_events = [e for e in after["clause_evidence_events"] if _canon(e) not in before_events]
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
                and e["element_id"] == ELEMENT_PREFIX + str(e["source_record_key"]) for e in new_events)
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
            "extraction_method": isinstance(row["extraction_method"], str)
            and row["extraction_method"].endswith(":" + rules),
            "run_input_sha256": row["run_input_sha256"] == manifest_sha,
            "run_batch_id": row["run_batch_id"] == batch_id,
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
