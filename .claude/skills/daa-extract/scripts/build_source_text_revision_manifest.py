#!/usr/bin/env python3
"""Byg source_text_revision-manifestet (trin 6a, spec §4.4): ny kildetekst for helposter.

Revisionen giver en helpost en ny tekstversion i samme rendition og samme spænd. Den nye tekst er
segment.py's posttekst under profilens `segment_profile_after` (2018-20: '2018-20-v2', støjregel
`page_header`); den gamle er posttekstens under `segment_profile_before`. Kandidaterne er de poster,
hvis tekst er forskellig under de to profiler.

Input:
  --profile       reimport-source-text-revision-profile-v1 (reimport_profile.py).
  --rendition     renditionen; skal hashe til profilens raw_text_sha256.
  --texts         klausuleksporten (export_clause_source_texts.R): helpostens gældende tekst, spænd og
                  occurrence_key pr. record.
  --dependencies  source_text_revision_dependencies.sql's output: før-hash, aktuelt sæt og de forventede
                  nøgle- og bindingsmængder pr. kandidat (det, writeren sammenligner med under sine låse).
  --output        en 0700-mappe uden work-komponent. Byggeren skriver
                    source-text-revision-manifest-v1.json  (0600; payloaden bærer den nye tekst, writeren
                                                            skal have den)
                    source-text-revision-index-v1.json     (0600; ingen tekst: nøgler, hashes og antal)
Med --list-changed-keys (kun --profile og --rendition) udskrives kandidaternes nøgler, så
afhængighedsfilen kan bygges for netop dem.

Forudsætninger pr. kandidat (fejler lukket):
  * v1-teksten har sha lig den gældende tekst i basen (TEXT_REVISION_V1_MISMATCH), og v1-spændet er
    helpostens (TEXT_REVISION_V1_SPAN_MISMATCH): manifestet bygges kun mod præcis den post, basen har;
  * v2-teksten er forskellig fra v1-teksten (TEXT_REVISION_NOOP);
  * v2-postens spænd (project_rendition med after-profilens støjregel) er helpostens. Er det ikke, kommer
    recorden i manifestets `dispositions` med koden `span_outside` og ikke i operationerne: en anden
    afgrænsning er en grænserevision, ikke en tekstversion (spec §5; I-84).

Klausulerne skæres af v2-teksten med profilens klausulregler (clause_segment.build_record_ledger) og
ankres gennem v2-projektionens offset-kort. Intet output på stdout eller i indeksfilen bærer tekst.
Scriptet rører aldrig en database og autoriserer aldrig en skrivning.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import sys
import uuid
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_clause_ledger
import build_source_evidence_manifest as sem
import clause_segment
import clause_set
import evidence_extract
import segment
from reimport_profile import SOURCE_TEXT_REVISION_PROFILE_SCHEMA_VERSION, load_profile

DEPENDENCIES_SCHEMA_VERSION = "source-text-revision-dependencies-v1"
INDEX_SCHEMA_VERSION = "source-text-revision-index-v1"
MANIFEST_NAME = "source-text-revision-manifest-v1.json"
INDEX_NAME = "source-text-revision-index-v1.json"
ELEMENT_PREFIX = "source-text-revision:"
DEPENDENCY_CLASS = "source_text_revision"
FOLDED_PREFIX = "folded_projection@"
PROJECTED_CLASSIFICATIONS = ("record_text", "structural_header")
#: Payloadens lukkede nøglesæt (private.clause_write_prepare, operationen source_text_revision).
PAYLOAD_KEYS = ("after_text_sha256", "before_text_sha256", "clause_rules_version", "clauses",
                "expected_binding_loss", "expected_superseded_keys", "gap_charset", "ledger_sha256",
                "projection_rule", "rendition_content_sha256", "replaces_clause_set_seq",
                "replaces_clause_set_sha256", "segmenter_version", "source_record_key", "verbatim_text")
CLAUSE_KEYS = ("char_from", "char_to", "classification", "flags", "ordinal",
               "rendition_char_from", "rendition_char_to", "verbatim_sha256")


class BuildError(ValueError):
    """Fejl der stopper bygningen. Ingen delvise manifester."""


def _fail(code: str) -> None:
    raise BuildError(code)


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _is_hash(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _canonical_sha256(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def _segment(raw_text: str, udgave: str) -> list[dict[str, Any]]:
    profile = segment.UDGAVE_PROFILER.get(udgave)
    if profile is None:
        _fail("TEXT_REVISION_SEGMENT_PROFILE_UNKNOWN")
    # Segmenteren skriver posterne (med tekst) og kvalitetsrapporten ud; de holdes inde.
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return profile["segmenter"](raw_text.splitlines(), profile)


def _noise_rule(profile: dict[str, Any]) -> str:
    """After-profilens støjregel, som tekstformen skal navngive (fx folded_projection@page_header)."""
    after = segment.UDGAVE_PROFILER.get(profile["segment_profile_after"])
    if after is None or segment.UDGAVE_PROFILER.get(profile["segment_profile_before"]) is None:
        _fail("TEXT_REVISION_SEGMENT_PROFILE_UNKNOWN")
    rule = after.get("noise_rule")
    if profile["writer_config"].get("text_form") != FOLDED_PREFIX + str(rule):
        _fail("TEXT_REVISION_TEXT_FORM_MISMATCH")
    return rule


def _clause_rules(version: str) -> dict[str, Any]:
    """Klausulreglerne med præcis denne version (én udtræksprofil, ellers fejl)."""
    payload = json.loads(evidence_extract.PROFILES.read_text(encoding="utf-8"))
    matches = [pid for pid, p in payload.get("profiles", {}).items()
               if isinstance(p, dict) and (p.get("clause_rules") or {}).get("version") == version]
    if len(matches) != 1:
        _fail("TEXT_REVISION_CLAUSE_RULES_NOT_UNIQUE")
    return dict(evidence_extract.load_profile(matches[0])["clause_rules"])


def changed_posts(profile: dict[str, Any], rendition: str) -> tuple[dict[str, str], list[dict[str, Any]], list[dict[str, Any]]]:
    """Kandidaterne: record_key → v1-tekst for poster, hvis tekst ændres; og v1- og v2-posterne i rækkefølge.

    Grænserne (nøglesekvens og alle felter undtagen teksten) skal være ens under de to profiler.
    """
    old_posts = _segment(rendition, profile["segment_profile_before"])
    new_posts = _segment(rendition, profile["segment_profile_after"])
    old_keys = [sem.record_key_of(p) for p in old_posts]
    if old_keys != [sem.record_key_of(p) for p in new_posts] or len(set(old_keys)) != len(old_keys):
        _fail("TEXT_REVISION_BOUNDARY_CHANGED")
    changed: dict[str, str] = {}
    for old, new in zip(old_posts, new_posts):
        if {k: v for k, v in old.items() if k != "raw_text"} != {k: v for k, v in new.items() if k != "raw_text"}:
            _fail("TEXT_REVISION_BOUNDARY_CHANGED")
        if old["raw_text"] != new["raw_text"]:
            changed[sem.record_key_of(old)] = old["raw_text"]
    return changed, old_posts, new_posts


def _spans(rendition: str, posts: list[dict[str, Any]], noise_rule: str) -> tuple[str, list[int], dict[str, tuple[int, int, int, int]]]:
    """Hver posts eksakte plads i projektionen med `noise_rule` og dens renditionsspænd (som
    build_source_evidence_manifest: fremadskridende find over alle poster, roundtrip-kontrol)."""
    projection, offsets = sem.project_rendition(rendition, noise_rule)
    spans: dict[str, tuple[int, int, int, int]] = {}
    cursor = 0
    for post in posts:
        text = post.get("raw_text")
        if not isinstance(text, str) or not text:
            _fail("TEXT_REVISION_POST_TEXT_INVALID")
        start = projection.find(text, cursor)
        if start < 0:
            _fail("TEXT_REVISION_SPAN_NOT_FOUND")
        end = start + len(text)
        char_from, char_to = offsets[start], offsets[end - 1] + 1
        if sem.project_rendition(rendition[char_from:char_to], noise_rule)[0] != text:
            _fail("TEXT_REVISION_SPAN_ROUNDTRIP_MISMATCH")
        spans[sem.record_key_of(post)] = (start, end, char_from, char_to)
        cursor = end
    return projection, offsets, spans


def _sorted_uuid_strings(values: Any) -> list[str]:
    """Strengt sorterede (dermed dubletfri) uuid-strenge i små bogstaver — writerens form."""
    if not isinstance(values, list):
        _fail("TEXT_REVISION_DEPENDENCIES_INVALID")
    parsed = []
    for value in values:
        if not isinstance(value, str):
            _fail("TEXT_REVISION_DEPENDENCIES_INVALID")
        try:
            u = uuid.UUID(value)
        except ValueError:
            _fail("TEXT_REVISION_DEPENDENCIES_INVALID")
        if str(u) != value:
            _fail("TEXT_REVISION_DEPENDENCIES_INVALID")
        parsed.append(u)
    if any(b <= a for a, b in zip(parsed, parsed[1:])):
        _fail("TEXT_REVISION_EXPECTED_SET_NOT_SORTED")
    return [str(u) for u in parsed]


def _sorted_bindings(values: Any) -> list[dict[str, str]]:
    if not isinstance(values, list):
        _fail("TEXT_REVISION_DEPENDENCIES_INVALID")
    out = []
    for value in values:
        if not isinstance(value, dict) or set(value) != {"promotion_id", "target_type"} \
                or not isinstance(value["target_type"], str) or not value["target_type"].strip():
            _fail("TEXT_REVISION_DEPENDENCIES_INVALID")
        out.append({"promotion_id": value["promotion_id"], "target_type": value["target_type"]})
    _sorted_uuid_strings([b["promotion_id"] for b in out])
    return out


def _index_rows(rows: Any, name: str) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list):
        _fail(f"TEXT_REVISION_{name}_INVALID")
    by_key: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("record_key"), str):
            _fail(f"TEXT_REVISION_{name}_INVALID")
        if row["record_key"] in by_key:
            _fail(f"TEXT_REVISION_{name}_DUPLICATE")
        by_key[row["record_key"]] = row
    return by_key


def _clauses(record_key: str, occurrence_key: str, text: str, rules: dict[str, Any], projection: str,
             offsets: list[int], start: int, span: tuple[int, int]) -> tuple[list[dict[str, Any]], str]:
    result = clause_segment.build_record_ledger(record_key, occurrence_key, text, rules)
    if result["gap_violations"]:
        _fail("TEXT_REVISION_GAP_INVALID")
    clauses: list[dict[str, Any]] = []
    prev_raw_to = span[0]
    for clause in result["clauses"]:
        if clause["classification"] not in PROJECTED_CLASSIFICATIONS:
            _fail("TEXT_REVISION_CLASSIFICATION_NOT_PROJECTABLE")
        cf, ct = clause["char_from"], clause["char_to"]
        if _sha(projection[start + cf:start + ct]) != clause["verbatim_sha256"]:
            _fail("TEXT_REVISION_CLAUSE_HASH_MISMATCH")
        raw_from, raw_to = offsets[start + cf], offsets[start + ct - 1] + 1
        if not (prev_raw_to <= raw_from < raw_to <= span[1]):
            _fail("TEXT_REVISION_CLAUSE_SPAN_INVALID")
        clauses.append({"ordinal": clause["ordinal"], "char_from": cf, "char_to": ct,
                        "rendition_char_from": raw_from, "rendition_char_to": raw_to,
                        "classification": clause["classification"], "flags": list(clause["flags"]),
                        "verbatim_sha256": clause["verbatim_sha256"]})
        prev_raw_to = raw_to
    if not clauses:
        _fail("TEXT_REVISION_NO_CLAUSES")
    return clauses, result["ledger_sha256"]


def assemble_manifest(profile: dict[str, Any], operations: list[dict[str, Any]],
                      dispositions: list[dict[str, Any]], provenance: dict[str, Any]) -> dict[str, Any]:
    """Manifestformen (apply_reimport_helpers.R, validate_reimport_manifest) med sit indholdshash."""
    for op in operations:
        if set(op) != set(PAYLOAD_KEYS) | {"element_id", "dependency_class"} \
                or op["element_id"] != ELEMENT_PREFIX + op["source_record_key"] \
                or op["dependency_class"] != DEPENDENCY_CLASS:
            _fail("TEXT_REVISION_OPERATION_INVALID")
    manifest = {
        "source": {"id": profile["source_id"], "profile_id": profile["profile_id"],
                   "profile_sha256": profile["profile_sha256"]},
        "provenance": provenance,
        "expected_counts": {"source_evidence": 0, "person_creates": 0, "canonical_delta": 0,
                            "source_text_revision": len(operations)},
        "operations": sorted(operations, key=lambda op: op["source_record_key"].encode("utf-8")),
        "dispositions": sorted(dispositions, key=lambda d: d["record_key"].encode("utf-8")),
    }
    manifest["manifest_content_sha256"] = _canonical_sha256(manifest)
    return manifest


def build_manifest(profile: dict[str, Any], rendition_bytes: bytes, texts: Any, dependencies: Any,
                   texts_file_sha256: str, dependencies_file_sha256: str) -> dict[str, Any]:
    if profile.get("profile_schema_version") != SOURCE_TEXT_REVISION_PROFILE_SCHEMA_VERSION:
        _fail("TEXT_REVISION_PROFILE_INVALID")
    rendition_sha = hashlib.sha256(rendition_bytes).hexdigest()
    if rendition_sha != profile["raw_text_sha256"]:
        _fail("TEXT_REVISION_RENDITION_SHA_MISMATCH")
    rendition = rendition_bytes.decode("utf-8")
    noise_rule = _noise_rule(profile)
    rules = _clause_rules(profile["clause_rules_version"])
    segmenter_version = build_clause_ledger.segmenter_version()
    if segmenter_version != profile["segmenter_version"]:
        _fail("TEXT_REVISION_SEGMENTER_VERSION_MISMATCH")

    if not isinstance(dependencies, dict) or dependencies.get("schema_version") != DEPENDENCIES_SCHEMA_VERSION \
            or dependencies.get("source_id") != profile["source_id"] \
            or dependencies.get("profile_id") != profile["profile_id"] \
            or dependencies.get("profile_sha256") != profile["profile_sha256"] \
            or dependencies.get("helpost_kind") != profile["writer_config"].get("helpost_observation_kind", "person_post"):
        _fail("TEXT_REVISION_DEPENDENCIES_PROFILE_MISMATCH")
    deps = _index_rows(dependencies.get("records"), "DEPENDENCIES")
    rows = _index_rows(texts, "TEXTS")

    changed, old_posts, new_posts = changed_posts(profile, rendition)
    if set(deps) != set(changed):
        _fail("TEXT_REVISION_DEPENDENCIES_SET_MISMATCH")
    # v1-spændet med before-profilens støjregel: sådan blev helposten ankret i basen.
    _, _, old_spans = _spans(rendition, old_posts,
                             segment.UDGAVE_PROFILER[profile["segment_profile_before"]]["noise_rule"])
    projection, offsets, new_spans = _spans(rendition, new_posts, noise_rule)
    new_text = {sem.record_key_of(p): p["raw_text"] for p in new_posts}

    operations: list[dict[str, Any]] = []
    dispositions: list[dict[str, Any]] = []
    for key in sorted(changed, key=lambda k: k.encode("utf-8")):
        dep, row = deps[key], rows.get(key)
        if dep.get("helpost_status") != "ok" or row is None or row.get("verbatim_text") is None:
            _fail("TEXT_REVISION_HELPOST_INVALID")
        if _sha(row["verbatim_text"]) != row.get("verbatim_sha256") \
                or row.get("rendition_content_sha256") != rendition_sha \
                or dep.get("rendition_content_sha256") != rendition_sha \
                or (row.get("char_from"), row.get("char_to")) != (dep.get("char_from"), dep.get("char_to")) \
                or row.get("text_id") != dep.get("text_id") \
                or not isinstance(row.get("occurrence_key"), str) or not row["occurrence_key"]:
            _fail("TEXT_REVISION_TEXTS_DEPENDENCIES_MISMATCH")
        before = changed[key]
        before_sha = _sha(before)
        if not (before_sha == dep.get("before_text_sha256") == row["verbatim_sha256"]):
            _fail("TEXT_REVISION_V1_MISMATCH")
        helpost_span = (dep["char_from"], dep["char_to"])
        if old_spans[key][2:] != helpost_span:
            _fail("TEXT_REVISION_V1_SPAN_MISMATCH")
        after = new_text[key]
        if after == before:
            _fail("TEXT_REVISION_NOOP")
        start, _, char_from, char_to = new_spans[key]
        if (char_from, char_to) != helpost_span:
            dispositions.append({"record_key": key, "code": "span_outside",
                                 "helpost_char_from": helpost_span[0], "helpost_char_to": helpost_span[1],
                                 "revised_char_from": char_from, "revised_char_to": char_to,
                                 "before_text_sha256": before_sha, "after_text_sha256": _sha(after)})
            continue
        seq, set_sha = dep.get("clause_set_seq"), dep.get("clause_set_sha256")
        if not isinstance(seq, int) or isinstance(seq, bool) or seq < 1 or not _is_hash(set_sha):
            _fail("TEXT_REVISION_CURRENT_SET_MISSING")
        clauses, ledger_sha = _clauses(key, row["occurrence_key"], after, rules, projection, offsets, start, helpost_span)
        operations.append({
            "element_id": ELEMENT_PREFIX + key,
            "dependency_class": DEPENDENCY_CLASS,
            "source_record_key": key,
            "rendition_content_sha256": rendition_sha,
            "projection_rule": profile["writer_config"]["text_form"],
            "before_text_sha256": before_sha,
            "verbatim_text": after,
            "after_text_sha256": _sha(after),
            "replaces_clause_set_seq": seq,
            "replaces_clause_set_sha256": set_sha,
            "clause_rules_version": rules["version"],
            "segmenter_version": segmenter_version,
            "ledger_sha256": ledger_sha,
            "gap_charset": list(rules["gap_charset"]),
            "clauses": clauses,
            "expected_superseded_keys": _sorted_uuid_strings(dep.get("expected_superseded_keys")),
            "expected_binding_loss": _sorted_bindings(dep.get("expected_binding_loss")),
        })

    if len(operations) != profile["expected_counts"]["source_text_revision"]:
        _fail("TEXT_REVISION_COUNT_MISMATCH")
    provenance = {"raw_text_sha256": rendition_sha,
                  "rendition_projection_sha256": _sha(projection),
                  "segment_profile_before": profile["segment_profile_before"],
                  "segment_profile_after": profile["segment_profile_after"],
                  "clause_rules_version": rules["version"],
                  "segmenter_version": segmenter_version,
                  "texts_file_sha256": texts_file_sha256,
                  "dependencies_file_sha256": dependencies_file_sha256}
    return assemble_manifest(profile, operations, dispositions, provenance)


def index_of(manifest: dict[str, Any], manifest_file_sha256: str) -> dict[str, Any]:
    """Manifestets indeks uden tekst: nøgler, hashes og antal."""
    ops = [{"record_key": op["source_record_key"], "element_id": op["element_id"],
            "before_text_sha256": op["before_text_sha256"], "after_text_sha256": op["after_text_sha256"],
            "replaces_clause_set_seq": op["replaces_clause_set_seq"],
            "replaces_clause_set_sha256": op["replaces_clause_set_sha256"],
            "after_clause_set_sha256": clause_set.clause_set_sha256(op["clauses"]),
            "clauses": len(op["clauses"]),
            "expected_superseded_keys": op["expected_superseded_keys"],
            "expected_binding_loss": op["expected_binding_loss"]} for op in manifest["operations"]]
    return {"schema_version": INDEX_SCHEMA_VERSION,
            "manifest_content_sha256": manifest["manifest_content_sha256"],
            "manifest_file_sha256": manifest_file_sha256,
            "source": manifest["source"], "provenance": manifest["provenance"],
            "expected_counts": manifest["expected_counts"],
            "counts": {"operations": len(ops), "dispositions": len(manifest["dispositions"]),
                       "clauses": sum(o["clauses"] for o in ops),
                       "superseded_keys": sum(len(o["expected_superseded_keys"]) for o in ops),
                       "binding_loss": sum(len(o["expected_binding_loss"]) for o in ops)},
            "operations": ops, "dispositions": manifest["dispositions"]}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--rendition", required=True)
    parser.add_argument("--texts")
    parser.add_argument("--dependencies")
    parser.add_argument("--output")
    parser.add_argument("--list-changed-keys", action="store_true",
                        help="udskriv kun kandidaternes nøgler (til afhængighedsfilen)")
    args = parser.parse_args()
    profile = load_profile(Path(args.profile))
    if profile.get("profile_schema_version") != SOURCE_TEXT_REVISION_PROFILE_SCHEMA_VERSION:
        _fail("TEXT_REVISION_PROFILE_INVALID")
    rendition_bytes = Path(args.rendition).read_bytes()
    if args.list_changed_keys:
        if args.texts or args.dependencies or args.output:
            _fail("TEXT_REVISION_CLI_INVALID")
        if hashlib.sha256(rendition_bytes).hexdigest() != profile["raw_text_sha256"]:
            _fail("TEXT_REVISION_RENDITION_SHA_MISMATCH")
        _noise_rule(profile)
        changed, _, _ = changed_posts(profile, rendition_bytes.decode("utf-8"))
        keys = sorted(changed, key=lambda k: k.encode("utf-8"))
        print(json.dumps({"changed": len(keys), "record_keys": keys}, ensure_ascii=False))
        return
    if not (args.texts and args.dependencies and args.output):
        _fail("TEXT_REVISION_CLI_INVALID")
    out = build_clause_ledger._validate_output_dir(args.output)
    if (out / MANIFEST_NAME).exists() or (out / INDEX_NAME).exists():
        _fail("TEXT_REVISION_OUTPUT_EXISTS")
    texts_bytes = Path(args.texts).read_bytes()
    deps_bytes = Path(args.dependencies).read_bytes()
    manifest = build_manifest(profile, rendition_bytes, json.loads(texts_bytes.decode("utf-8")),
                              json.loads(deps_bytes.decode("utf-8")),
                              hashlib.sha256(texts_bytes).hexdigest(), hashlib.sha256(deps_bytes).hexdigest())
    build_clause_ledger._write_private(out / MANIFEST_NAME, manifest)
    manifest_file_sha256 = hashlib.sha256((out / MANIFEST_NAME).read_bytes()).hexdigest()
    index = index_of(manifest, manifest_file_sha256)
    build_clause_ledger._write_private(out / INDEX_NAME, index)
    print(json.dumps({"manifest_content_sha256": manifest["manifest_content_sha256"],
                      "manifest_file_sha256": manifest_file_sha256, **index["counts"],
                      "dispositions": [{"record_key": d["record_key"], "code": d["code"]}
                                       for d in manifest["dispositions"]],
                      "record_keys": [op["source_record_key"] for op in manifest["operations"]]},
                     ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except BuildError as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
