"""Syntetiske fixtures uden rigtige navne — profilindlæser og kanonisk hash."""
import json
from pathlib import Path

import pytest

import reimport_profile as rp

FIXTURE_WRITER_CONFIG = {
    "citation_label_template": "Synthetic side {page_from}",
    "extractor_version": "fixture-v1",
    "observation_extraction_method": "fixture_method",
    "rendition_key": "fixture-rendition",
    "rendition_kind": "pdf_text_layer",
    "rendition_metadata": {
        "edition": "fixture",
        "pdf_sha256": "a" * 64,
        "pdftotext_version": "fixture 0.0",
    },
    "run_key_prefix": "fixture:",
    "schema_version": "fixture-manifest-v1",
}
# Verificeret 2026-09-03 mod PostgreSQL 17 med samme kanoniske tekstregel som
# private.reimport_canonical_json_text (schema.sql:2480-2489).
KNOWN_VECTOR = "834feadfd65f4b7cecad2fa3d8b058e1d2cd03fe2a805cf9c6cfa2fa6e789ef7"


def profile_dict(**overrides):
    profile = {
        "profile_schema_version": "reimport-source-evidence-profile-v1",
        "source_id": 4242,
        "profile_id": "fixture-source-evidence-v1",
        "profile_version": "fixture-v1",
        "writer_config": json.loads(json.dumps(FIXTURE_WRITER_CONFIG)),
        "pdf_sha256": "a" * 64,
        "raw_text_sha256": "b" * 64,
        "segment_version": "segment.py@fixture-v1",
        "expected_counts": {"person_creates": 0, "source_evidence": 3},
        "pdftotext_args": {
            "layout": True,
            "first_page": 1,
            "last_page": 2,
            "page_marker": "### PAGE {page} ###",
        },
    }
    profile.update(overrides)
    return profile


def write(tmp_path, profile):
    path = tmp_path / "profile.json"
    path.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8")
    return path


def test_canonical_sha_matches_postgres_known_vector():
    assert rp.canonical_json_sha256(FIXTURE_WRITER_CONFIG) == KNOWN_VECTOR


def test_canonical_text_sorts_keys_and_drops_separators():
    assert rp.canonical_json_text({"b": 1, "a": {"d": [1, 2], "c": "x"}}) == \
        '{"a":{"c":"x","d":[1,2]},"b":1}'


def test_canonical_text_renders_bool_and_null_like_jsonb():
    assert rp.canonical_json_text({"t": True, "f": False, "n": None}) == \
        '{"f":false,"n":null,"t":true}'


def test_canonical_sha_rejects_float():
    with pytest.raises(rp.ProfileError) as error:
        rp.canonical_json_sha256({"a": 1.5})
    assert str(error.value) == "PROFILE_CANONICAL_FLOAT_FORBIDDEN"


def test_load_profile_returns_profile_sha256(tmp_path):
    loaded = rp.load_profile(write(tmp_path, profile_dict()))
    assert loaded["profile_sha256"] == KNOWN_VECTOR


def test_load_profile_rejects_unfilled_placeholder(tmp_path):
    broken = profile_dict(pdf_sha256="<UDFYLDES FRA INVENTERING>")
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, broken))
    assert str(error.value) == "PROFILE_PLACEHOLDER_UNFILLED"


def test_load_profile_rejects_unknown_top_level_key(tmp_path):
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, profile_dict(extra="x")))
    assert str(error.value) == "PROFILE_FIELD_SET_INVALID"


def test_load_profile_rejects_writer_config_field_drift(tmp_path):
    config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
    del config["run_key_prefix"]
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, profile_dict(writer_config=config)))
    assert str(error.value) == "PROFILE_WRITER_CONFIG_INVALID"


def test_load_profile_rejects_citation_template_with_two_tokens(tmp_path):
    config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
    config["citation_label_template"] = "Synthetic {page_from} {page_to}"
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, profile_dict(writer_config=config)))
    assert str(error.value) == "PROFILE_WRITER_CONFIG_INVALID"


def test_load_profile_rejects_collation_ambiguous_keys(tmp_path):
    config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
    config["rendition_metadata"] = {"pdf_a": 1, "pdfa": 2}
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, profile_dict(writer_config=config)))
    assert str(error.value) == "PROFILE_KEY_COLLATION_UNSTABLE"


def test_load_profile_rejects_nested_pdf_sha_mismatch(tmp_path):
    config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
    config["rendition_metadata"]["pdf_sha256"] = "c" * 64
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, profile_dict(writer_config=config)))
    assert str(error.value) == "PROFILE_PDF_SHA256_MISMATCH"


def test_load_profile_rejects_nonzero_person_creates(tmp_path):
    broken = profile_dict(expected_counts={"person_creates": 1, "source_evidence": 3})
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, broken))
    assert str(error.value) == "PROFILE_EXPECTED_COUNTS_INVALID"


def test_repository_profile_has_the_locked_identity():
    path = (Path(__file__).resolve().parents[1] /
            "references/reimport-profiles/daa-2018-20-source-evidence-v1.json")
    raw = json.loads(path.read_text(encoding="utf-8"))
    assert raw["source_id"] == 1
    assert raw["profile_id"] == "daa-2018-20-source-evidence-v1"
    assert raw["expected_counts"] == {"person_creates": 0, "source_evidence": 591}
    assert raw["writer_config"]["rendition_key"] == "daa-2018-20-pdftotext-r1"
    assert raw["writer_config"]["rendition_kind"] == "pdf_text_layer"


def legacy_profile_dict(**overrides):
    profile = {
        "profile_schema_version": "reimport-legacy-migration-profile-v1",
        "source_id": 4242,
        "profile_id": "fixture-legacy-migration-v1",
        "profile_version": "fixture-v1",
        "writer_config": json.loads(json.dumps(FIXTURE_WRITER_CONFIG)),
        "raw_text_sha256": "b" * 64,
        "expected_counts": {
            "person_creates": 0,
            "source_evidence": 0,
            "legacy_migrations": 2,
        },
        "expected_dispositions": {
            "bound_published": 1,
            "bound_draft": 1,
            "unresolved_text": 0,
            "unresolved_identity": 0,
        },
        "stop_threshold": {"unresolved_max_share_percent": 10},
    }
    profile.update(overrides)
    return profile


def test_load_legacy_migration_profile_returns_profile_sha256(tmp_path):
    loaded = rp.load_profile(write(tmp_path, legacy_profile_dict()))
    assert loaded["profile_sha256"] == KNOWN_VECTOR


def test_legacy_migration_profile_rejects_extra_key(tmp_path):
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, legacy_profile_dict(extra="x")))
    assert str(error.value) == "PROFILE_KEYS_INVALID"


def test_legacy_migration_profile_rejects_invalid_rendition_pdf_hash(tmp_path):
    config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
    config["rendition_metadata"]["pdf_sha256"] = "not-a-hash"
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, legacy_profile_dict(writer_config=config)))
    assert str(error.value) == "PROFILE_MEASURED_HASH_INVALID"


@pytest.mark.parametrize("threshold", [-1, 101, True])
def test_legacy_migration_profile_requires_percentage_threshold(tmp_path, threshold):
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, legacy_profile_dict(
            stop_threshold={"unresolved_max_share_percent": threshold})))
    assert str(error.value) == "PROFILE_STOP_THRESHOLD_INVALID"


@pytest.mark.parametrize("expected_dispositions", [
    {"bound_published": 1, "bound_draft": 1, "unresolved_text": 0},
    {"bound_published": 1, "bound_draft": 1, "unresolved_text": 0,
     "unresolved_identity": -1},
    {"bound_published": 1, "bound_draft": 1, "unresolved_text": 0,
     "unresolved_identity": True},
])
def test_legacy_migration_profile_requires_exact_nonnegative_dispositions(
        tmp_path, expected_dispositions):
    with pytest.raises(rp.ProfileError) as error:
        rp.load_profile(write(tmp_path, legacy_profile_dict(
            expected_dispositions=expected_dispositions)))
    assert str(error.value) == "PROFILE_EXPECTED_DISPOSITIONS_INVALID"


# --- Omsegmentering: revisionsprofilen (spec 2026-09-27) --------------------
CLAUSE_EVIDENCE_PROFILE = Path(__file__).resolve().parents[1] / "references/reimport-profiles/daa-2018-20-clause-evidence-v1.json"


def _revision_profile(**counts):
    profile = json.loads(CLAUSE_EVIDENCE_PROFILE.read_text(encoding="utf-8"))
    profile["profile_schema_version"] = "reimport-clause-revision-profile-v1"
    profile["profile_id"] = "fixture-clause-revision"
    profile["expected_counts"] = counts or {"person_creates": 0, "source_evidence": 0, "clause_revisions": 51}
    return profile


def test_revision_profile_loads_with_clause_revisions_count(tmp_path):
    path = tmp_path / "revision.json"
    path.write_text(json.dumps(_revision_profile()), encoding="utf-8")
    assert rp.load_profile(path)["expected_counts"]["clause_revisions"] == 51


def test_revision_profile_rejects_the_clause_evidence_count(tmp_path):
    path = tmp_path / "revision.json"
    path.write_text(json.dumps(_revision_profile(person_creates=0, source_evidence=0, clause_evidence=51)), encoding="utf-8")
    with pytest.raises(rp.ProfileError, match="PROFILE_EXPECTED_COUNTS_INVALID"):
        rp.load_profile(path)


REPO_ROOT = Path(__file__).resolve().parents[4]
PROFILE_1939 = (Path(__file__).resolve().parents[1] /
                "references/reimport-profiles/daa-1939-clause-evidence-v1.json")
EXPECTED_1939_SHA = "2aa5a358063fdf98f19954a683279cc3cabfd3eb5d5dd9c7fdaf5e42571b66d7"


def _seed_writer_config(sql_file):
    """writer_config-strengen i INSERT-rækken for 1939-klausulprofilen, læst direkte fra SQL-filen."""
    import re
    text = (REPO_ROOT / sql_file).read_text(encoding="utf-8")
    start = text.index("'daa-1939-clause-evidence-v1'")
    match = re.search(r"VALUES \(\s*'(\{.*?\})'::jsonb", text[start:], re.S)
    assert match, sql_file
    return json.loads(match.group(1))


@pytest.mark.parametrize("sql_file", ["schema.sql", "db-migrations.sql"])
def test_1939_profile_hash_matches_db_seed(sql_file):
    profile = rp.load_profile(PROFILE_1939)
    seeded = _seed_writer_config(sql_file)
    assert profile["writer_config"] == seeded
    assert profile["profile_sha256"] == rp.canonical_json_sha256(seeded) == EXPECTED_1939_SHA
    assert profile["expected_counts"]["clause_evidence"] == 584


def test_pdf_metadata_still_required_for_pdf_text_layer(tmp_path):
    raw = json.loads(PROFILE_1939.read_text(encoding="utf-8"))
    raw["writer_config"]["rendition_kind"] = "pdf_text_layer"
    with pytest.raises(rp.ProfileError):
        rp.load_profile(write(tmp_path, raw))


def test_unknown_text_form_rejected(tmp_path):
    raw = json.loads(PROFILE_1939.read_text(encoding="utf-8"))
    raw["writer_config"]["text_form"] = "folded"
    with pytest.raises(rp.ProfileError):
        rp.load_profile(write(tmp_path, raw))
