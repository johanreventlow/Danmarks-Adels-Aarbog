#!/usr/bin/env python3
"""Indlæs og validér én udgaveprofil for den generelle source_evidence-writer.

Den kanoniske JSON-regel er en bit-for-bit spejling af
private.reimport_canonical_json_text (schema.sql:2480-2489): objekter serialiseres
med sorterede nøgler, ingen mellemrum, og skalarer som jsonb::text.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

HASH_RE = re.compile(r"^[0-9a-f]{64}$")
KEY_RE = re.compile(r"^[a-z][a-z0-9_]*$")
PLACEHOLDER = "<UDFYLDES FRA INVENTERING>"
PROFILE_SCHEMA_VERSION = "reimport-source-evidence-profile-v1"
LEGACY_PROFILE_SCHEMA_VERSION = "reimport-legacy-migration-profile-v1"
CLAUSE_PROFILE_SCHEMA_VERSION = "reimport-clause-evidence-profile-v1"
#: Omsegmentering (spec 2026-09-27): samme felter som klausulprofilen, men writeren
#: er clause_revision, og tællingen er clause_revisions.
CLAUSE_REVISION_PROFILE_SCHEMA_VERSION = "reimport-clause-revision-profile-v1"
#: Kildetekst-revision (trin 6a, spec §4.4): ny tekst for helposten, projiceret med en navngiven
#: tekstform; klausulerne skæres af den nye tekst. Writeren er source_text_revision.
SOURCE_TEXT_REVISION_PROFILE_SCHEMA_VERSION = "reimport-source-text-revision-profile-v1"

PROFILE_KEYS = {
    "profile_schema_version", "source_id", "profile_id", "profile_version",
    "writer_config", "pdf_sha256", "raw_text_sha256", "segment_version",
    "expected_counts", "pdftotext_args",
}
LEGACY_PROFILE_KEYS = {
    "profile_schema_version", "source_id", "profile_id", "profile_version",
    "writer_config", "raw_text_sha256", "expected_counts",
    "expected_dispositions", "stop_threshold",
}
CLAUSE_PROFILE_KEYS = {
    "profile_schema_version", "source_id", "profile_id", "profile_version",
    "writer_config", "raw_text_sha256", "clause_rules_version",
    "segmenter_version", "expected_counts",
}
CLAUSE_EXPECTED_COUNTS_KEYS = {"person_creates", "source_evidence", "clause_evidence"}
#: Segmentprofilerne (segment.UDGAVE_PROFILER) før og efter revisionen er udgavedata og bor i profilen,
#: ikke i byggeren.
SOURCE_TEXT_REVISION_PROFILE_KEYS = CLAUSE_PROFILE_KEYS | {"segment_profile_before", "segment_profile_after"}
SOURCE_TEXT_REVISION_EXPECTED_COUNTS_KEYS = {"source_text_revision"}
WRITER_CONFIG_KEYS = {
    "citation_label_template", "extractor_version", "observation_extraction_method",
    "rendition_key", "rendition_kind", "rendition_metadata", "run_key_prefix",
    "schema_version",
}
#: Valgfri nøgler (trin 6a, B7). Udeladt = default, så 2018-20's profiler og hashes er uændrede.
WRITER_CONFIG_OPTIONAL_KEYS = {"text_form", "helpost_observation_kind"}
TEXT_FORMS = ("raw", "folded_projection@anywhere", "folded_projection@page_header")
WRITER_CONFIG_TEXT_KEYS = (
    "run_key_prefix", "schema_version", "extractor_version", "rendition_key",
    "rendition_kind", "observation_extraction_method",
)
RENDITION_METADATA_KEYS = {"edition", "pdf_sha256", "pdftotext_version"}
PDFTOTEXT_ARGS_KEYS = {"layout", "first_page", "last_page", "page_marker"}
EXPECTED_COUNTS_KEYS = {"person_creates", "source_evidence"}
LEGACY_EXPECTED_COUNTS_KEYS = {
    "person_creates", "source_evidence", "legacy_migrations",
}
LEGACY_EXPECTED_DISPOSITIONS_KEYS = {
    "bound_published", "bound_draft", "unresolved_text",
    "unresolved_identity",
}
LEGACY_STOP_THRESHOLD_KEYS = {"unresolved_max_share_percent"}


class ProfileError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ProfileError(code)


def canonical_json_text(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    if isinstance(value, dict):
        parts = []
        for key in sorted(value):
            if not isinstance(key, str):
                _fail("PROFILE_CANONICAL_TYPE_INVALID")
            parts.append(json.dumps(key, ensure_ascii=False) + ":"
                         + canonical_json_text(value[key]))
        return "{" + ",".join(parts) + "}"
    if isinstance(value, list):
        return "[" + ",".join(canonical_json_text(item) for item in value) + "]"
    if isinstance(value, float):
        _fail("PROFILE_CANONICAL_FLOAT_FORBIDDEN")
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    _fail("PROFILE_CANONICAL_TYPE_INVALID")
    raise AssertionError("unreachable")


def canonical_json_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json_text(value).encode("utf-8")).hexdigest()


def _assert_collation_stable(value: Any) -> None:
    """PostgreSQLs ORDER BY 1 kan ignorere tegnsætning; kodepunktordenen skal
    give samme resultat, ellers divergerer profile_sha256 fra databasens."""
    if isinstance(value, list):
        for item in value:
            _assert_collation_stable(item)
        return
    if not isinstance(value, dict):
        return
    keys = list(value)
    for key in keys:
        if not isinstance(key, str) or not KEY_RE.match(key):
            _fail("PROFILE_KEY_COLLATION_UNSTABLE")
    normalized_keys = [key.replace("_", "") for key in keys]
    if len(normalized_keys) != len(set(normalized_keys)) \
            or sorted(keys) != sorted(keys, key=lambda k: (k.replace("_", ""), k)):
        _fail("PROFILE_KEY_COLLATION_UNSTABLE")
    for key in keys:
        _assert_collation_stable(value[key])


def _assert_no_placeholder(value: Any) -> None:
    if isinstance(value, str) and PLACEHOLDER in value:
        _fail("PROFILE_PLACEHOLDER_UNFILLED")
    if isinstance(value, dict):
        for item in value.values():
            _assert_no_placeholder(item)
    if isinstance(value, list):
        for item in value:
            _assert_no_placeholder(item)


def _text(value: Any) -> bool:
    return isinstance(value, str) and value.strip() != "" and "\x00" not in value


def _positive_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 1


def _nonnegative_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _validate_writer_config(config: Any, pdf_sha256: str | None) -> None:
    if not isinstance(config, dict) or not WRITER_CONFIG_KEYS <= set(config) \
            or set(config) - WRITER_CONFIG_KEYS - WRITER_CONFIG_OPTIONAL_KEYS:
        _fail("PROFILE_WRITER_CONFIG_INVALID")
    for key in WRITER_CONFIG_TEXT_KEYS:
        if not _text(config[key]):
            _fail("PROFILE_WRITER_CONFIG_INVALID")
    if "text_form" in config and config["text_form"] not in TEXT_FORMS:
        _fail("PROFILE_WRITER_CONFIG_INVALID")
    if "helpost_observation_kind" in config and not _text(config["helpost_observation_kind"]):
        _fail("PROFILE_WRITER_CONFIG_INVALID")
    template = config["citation_label_template"]
    if not isinstance(template, str) or template.count("{page_from}") != 1 \
            or re.search(r"\{[^}]*\}", template.replace("{page_from}", "")):
        _fail("PROFILE_WRITER_CONFIG_INVALID")
    metadata = config["rendition_metadata"]
    if not isinstance(metadata, dict) or not set(metadata) <= RENDITION_METADATA_KEYS \
            or not _text(metadata.get("edition")):
        _fail("PROFILE_WRITER_CONFIG_INVALID")
    if config["rendition_kind"] == "pdf_text_layer":
        # pdf_sha256 og pdftotext_version kræves kun for et PDF-tekstlag.
        if set(metadata) != RENDITION_METADATA_KEYS or not _text(metadata["pdftotext_version"]) \
                or not isinstance(metadata["pdf_sha256"], str):
            _fail("PROFILE_WRITER_CONFIG_INVALID")
        if metadata["pdf_sha256"] != pdf_sha256:
            _fail("PROFILE_PDF_SHA256_MISMATCH")
    elif set(metadata) != {"edition"}:
        _fail("PROFILE_WRITER_CONFIG_INVALID")


def _validate_source_evidence_profile(profile: dict[str, Any]) -> None:
    if set(profile) != PROFILE_KEYS:
        _fail("PROFILE_FIELD_SET_INVALID")
    if not _positive_int(profile["source_id"]) or not _text(profile["profile_id"]) \
            or not _text(profile["profile_version"]) or not _text(profile["segment_version"]):
        _fail("PROFILE_FIELD_SET_INVALID")
    for key in ("pdf_sha256", "raw_text_sha256"):
        if not isinstance(profile[key], str) or not HASH_RE.match(profile[key]):
            _fail("PROFILE_MEASURED_HASH_INVALID")
    counts = profile["expected_counts"]
    if not isinstance(counts, dict) or set(counts) != EXPECTED_COUNTS_KEYS \
            or counts["person_creates"] != 0 or not _positive_int(counts["source_evidence"]):
        _fail("PROFILE_EXPECTED_COUNTS_INVALID")
    args = profile["pdftotext_args"]
    if not isinstance(args, dict) or set(args) != PDFTOTEXT_ARGS_KEYS \
            or args["layout"] is not True or not _positive_int(args["first_page"]) \
            or not _positive_int(args["last_page"]) or args["last_page"] < args["first_page"] \
            or args["page_marker"] != "### PAGE {page} ###":
        _fail("PROFILE_PDFTOTEXT_ARGS_INVALID")
    _assert_collation_stable(profile["writer_config"])
    _validate_writer_config(profile["writer_config"], profile["pdf_sha256"])


def _validate_legacy_migration_profile(profile: dict[str, Any]) -> None:
    if set(profile) != LEGACY_PROFILE_KEYS:
        _fail("PROFILE_KEYS_INVALID")
    if not _positive_int(profile["source_id"]) or not _text(profile["profile_id"]) \
            or not _text(profile["profile_version"]):
        _fail("PROFILE_FIELD_SET_INVALID")
    if not isinstance(profile["raw_text_sha256"], str) \
            or not HASH_RE.match(profile["raw_text_sha256"]):
        _fail("PROFILE_MEASURED_HASH_INVALID")
    counts = profile["expected_counts"]
    if not isinstance(counts, dict) or set(counts) != LEGACY_EXPECTED_COUNTS_KEYS \
            or counts["person_creates"] != 0 or counts["source_evidence"] != 0 \
            or not _positive_int(counts["legacy_migrations"]):
        _fail("PROFILE_EXPECTED_COUNTS_INVALID")
    dispositions = profile["expected_dispositions"]
    if not isinstance(dispositions, dict) \
            or set(dispositions) != LEGACY_EXPECTED_DISPOSITIONS_KEYS \
            or not all(_nonnegative_int(value) for value in dispositions.values()):
        _fail("PROFILE_EXPECTED_DISPOSITIONS_INVALID")
    threshold = profile["stop_threshold"]
    if not isinstance(threshold, dict) \
            or set(threshold) != LEGACY_STOP_THRESHOLD_KEYS \
            or not isinstance(threshold["unresolved_max_share_percent"], int) \
            or isinstance(threshold["unresolved_max_share_percent"], bool) \
            or not 0 <= threshold["unresolved_max_share_percent"] <= 100:
        _fail("PROFILE_STOP_THRESHOLD_INVALID")
    _assert_collation_stable(profile["writer_config"])
    config = profile["writer_config"]
    metadata = config.get("rendition_metadata") if isinstance(config, dict) else None
    if not isinstance(metadata, dict) or not isinstance(metadata.get("pdf_sha256"), str) \
            or not HASH_RE.match(metadata["pdf_sha256"]):
        _fail("PROFILE_MEASURED_HASH_INVALID")
    _validate_writer_config(config, metadata["pdf_sha256"])


def _validate_clause_evidence_profile(profile: dict[str, Any], count_key: str = "clause_evidence") -> None:
    """#148 4.1c: profilen for clause_evidence-writeren.

    raw_text_sha256 er renditionens hash — manifest-builderen nægter at bygge,
    hvis pdftotext-outputtet ikke hasher til netop den, for offset-kortet gælder
    kun for præcis den tekst.
    """
    if set(profile) != CLAUSE_PROFILE_KEYS:
        _fail("PROFILE_KEYS_INVALID")
    if not _positive_int(profile["source_id"]) or not _text(profile["profile_id"]) \
            or not _text(profile["profile_version"]) or not _text(profile["clause_rules_version"]) \
            or not _text(profile["segmenter_version"]):
        _fail("PROFILE_FIELD_SET_INVALID")
    if not isinstance(profile["raw_text_sha256"], str) \
            or not HASH_RE.match(profile["raw_text_sha256"]):
        _fail("PROFILE_MEASURED_HASH_INVALID")
    counts = profile["expected_counts"]
    if not isinstance(counts, dict) or set(counts) != {"person_creates", "source_evidence", count_key} \
            or counts["person_creates"] != 0 or counts["source_evidence"] != 0 \
            or not _positive_int(counts[count_key]):
        _fail("PROFILE_EXPECTED_COUNTS_INVALID")
    _assert_collation_stable(profile["writer_config"])
    config = profile["writer_config"]
    metadata = config.get("rendition_metadata") if isinstance(config, dict) else None
    if not isinstance(metadata, dict):
        _fail("PROFILE_WRITER_CONFIG_INVALID")
    pdf_hash = None
    if config.get("rendition_kind") == "pdf_text_layer":
        pdf_hash = metadata.get("pdf_sha256")
        if not isinstance(pdf_hash, str) or not HASH_RE.match(pdf_hash):
            _fail("PROFILE_MEASURED_HASH_INVALID")
    _validate_writer_config(config, pdf_hash)


def _validate_source_text_revision_profile(profile: dict[str, Any]) -> None:
    """Trin 6a: profilen for source_text_revision-writeren (spec §4.4).

    Som klausulprofilen (raw_text_sha256 binder renditionen, regler og segmenter-version binder
    klausulerne), men tekstformen SKAL være deklareret og være en foldet projektion, og de to
    segmentprofiler skal navngives. Den eneste tælling er source_text_revision.
    """
    if set(profile) != SOURCE_TEXT_REVISION_PROFILE_KEYS:
        _fail("PROFILE_KEYS_INVALID")
    clause_part = {k: v for k, v in profile.items() if k not in ("segment_profile_before", "segment_profile_after")}
    counts = profile["expected_counts"]
    if not isinstance(counts, dict) or set(counts) != SOURCE_TEXT_REVISION_EXPECTED_COUNTS_KEYS \
            or not _positive_int(counts["source_text_revision"]):
        _fail("PROFILE_EXPECTED_COUNTS_INVALID")
    # Klausuldelen valideres af klausulprofilens regler (med en lånt tællingsform).
    _validate_clause_evidence_profile(dict(clause_part, expected_counts={
        "person_creates": 0, "source_evidence": 0, "source_text_revision": counts["source_text_revision"]}),
        "source_text_revision")
    if not _text(profile["segment_profile_before"]) or not _text(profile["segment_profile_after"]) \
            or profile["segment_profile_before"] == profile["segment_profile_after"]:
        _fail("PROFILE_FIELD_SET_INVALID")
    text_form = profile["writer_config"].get("text_form")
    if not isinstance(text_form, str) or not text_form.startswith("folded_projection@"):
        _fail("PROFILE_WRITER_CONFIG_INVALID")


def load_profile(path: Path) -> dict[str, Any]:
    try:
        profile = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        _fail("PROFILE_UNREADABLE")
    _assert_no_placeholder(profile)
    if not isinstance(profile, dict):
        _fail("PROFILE_FIELD_SET_INVALID")
    if profile.get("profile_schema_version") == PROFILE_SCHEMA_VERSION:
        _validate_source_evidence_profile(profile)
    elif profile.get("profile_schema_version") == LEGACY_PROFILE_SCHEMA_VERSION:
        _validate_legacy_migration_profile(profile)
    elif profile.get("profile_schema_version") == CLAUSE_PROFILE_SCHEMA_VERSION:
        _validate_clause_evidence_profile(profile)
    elif profile.get("profile_schema_version") == CLAUSE_REVISION_PROFILE_SCHEMA_VERSION:
        _validate_clause_evidence_profile(profile, "clause_revisions")
    elif profile.get("profile_schema_version") == SOURCE_TEXT_REVISION_PROFILE_SCHEMA_VERSION:
        _validate_source_text_revision_profile(profile)
    else:
        _fail("PROFILE_FIELD_SET_INVALID")
    profile["profile_sha256"] = canonical_json_sha256(profile["writer_config"])
    return profile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    args = parser.parse_args()
    profile = load_profile(Path(args.profile))
    print(json.dumps({
        "source_id": profile["source_id"],
        "profile_id": profile["profile_id"],
        "profile_version": profile["profile_version"],
        "profile_sha256": profile["profile_sha256"],
        "expected_counts": profile["expected_counts"],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
