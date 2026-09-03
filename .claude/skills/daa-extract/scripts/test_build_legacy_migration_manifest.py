"""Syntetiske fixtures — legacy-migration-byggerens dispositioner og gates."""
import hashlib, json, pytest
import build_legacy_migration_manifest as builder

CORPUS = "### PAGE 0010 ###\nAlfa Bravo, f. 1801,\nd. 1860.\n"
def sha(s): return hashlib.sha256(s.encode("utf-8")).hexdigest()
def profile(**o):
    p = {"source_id": 7, "profile_id": "fixture-legacy-migration-v1", "profile_sha256": "b"*64,
         "raw_text_sha256": sha(CORPUS),
         "expected_counts": {"person_creates": 0, "source_evidence": 0, "legacy_migrations": 2},
         "expected_dispositions": {"bound_published": 1, "bound_draft": 1, "unresolved_text": 0, "unresolved_identity": 0},
         "stop_threshold": {"unresolved_max_share_percent": 10}}
    p.update(o); return p
def cand(key, **o):
    c = {"record_key": key, "person_id": 1, "narrative_id": 2, "person_levende": False, "person_privat": False,
         "person_staged": False, "narrative_privat": False, "narrative_text_sha256": sha("Alfa Bravo, f. 1801, d. 1860."),
         "occurrence_verbatim_sha256": sha("Alfa Bravo, f. 1801, d. 1860."), "legacy_publication_ref": "11111111-1111-4111-8111-111111111111",
         "legacy_status": "grandfathered_publication", "legacy_baseline_sha256": "3"*64, "persons_for_record_key": 1,
         "external_ids_for_person": 1, "narratives_for_person": 1, "already_bound": False}
    c.update(o); return c
def texts(key, n="Alfa Bravo, f. 1801, d. 1860.", o="Alfa Bravo, f. 1801, d. 1860."):
    return {key: {"narrative_text": n, "occurrence_text": o}}

def test_bound_published_and_draft():
    living = cand("K2", person_levende=True, legacy_publication_ref=None, legacy_status=None, legacy_baseline_sha256=None)
    m = builder.build_manifest(profile(), [cand("K1"), living], {**texts("K1"), **texts("K2")}, CORPUS)
    kinds = {d["record_key"]: d["disposition"] for d in m["dispositions"]}
    assert kinds == {"K1": "bound_published", "K2": "bound_draft"}
    assert m["expected_counts"]["legacy_migrations"] == 2
    assert [op["element_id"] for op in m["operations"]] == ["legacy-migration:K1", "legacy-migration:K2"]
    assert '"narrative_text":' not in json.dumps(m) and "Alfa" not in json.dumps(m)

def test_unresolved_text_is_not_an_element():
    p = profile(expected_counts={"person_creates": 0, "source_evidence": 0, "legacy_migrations": 0},
                expected_dispositions={"bound_published": 0, "bound_draft": 0, "unresolved_text": 1, "unresolved_identity": 0},
                stop_threshold={"unresolved_max_share_percent": 100})
    changed = "Alfa Bravo, f. 1801, d. 1861."
    m = builder.build_manifest(p, [cand("K1", narrative_text_sha256=sha(changed))], texts("K1", n=changed), CORPUS)
    assert m["dispositions"][0]["disposition"] == "unresolved_text" and m["operations"] == []

def test_unresolved_identity():
    p = profile(expected_counts={"person_creates": 0, "source_evidence": 0, "legacy_migrations": 0},
                expected_dispositions={"bound_published": 0, "bound_draft": 0, "unresolved_text": 0, "unresolved_identity": 1},
                stop_threshold={"unresolved_max_share_percent": 100})
    m = builder.build_manifest(p, [cand("K1", external_ids_for_person=2)], texts("K1"), CORPUS)
    assert m["dispositions"][0]["disposition"] == "unresolved_identity"

def test_ledger_inconsistent_stops():
    with pytest.raises(builder.BuildError, match="LEGACY_MIGRATION_LEDGER_INCONSISTENT"):
        builder.build_manifest(profile(), [cand("K1", legacy_status=None, legacy_publication_ref=None, legacy_baseline_sha256=None)], texts("K1"), CORPUS)

def test_stop_threshold():
    p = profile(stop_threshold={"unresolved_max_share_percent": 0})
    with pytest.raises(builder.BuildError, match="LEGACY_MIGRATION_STOP_THRESHOLD"):
        builder.build_manifest(p, [cand("K1", narrative_text_sha256=sha("x"))], texts("K1", n="x"), CORPUS)

def test_expected_dispositions_mismatch_stops():
    p = profile(expected_dispositions={"bound_published": 2, "bound_draft": 0, "unresolved_text": 0, "unresolved_identity": 0})
    with pytest.raises(builder.BuildError, match="LEGACY_MIGRATION_EXPECTED_DISPOSITIONS_MISMATCH"):
        builder.build_manifest(p, [cand("K1")], texts("K1"), CORPUS)

def test_text_hash_consistency_between_files():
    with pytest.raises(builder.BuildError, match="LEGACY_MIGRATION_TEXT_HASH_MISMATCH"):
        builder.build_manifest(profile(), [cand("K1", narrative_text_sha256="0"*64)], texts("K1"), CORPUS)

def test_deterministic():
    a = builder.build_manifest(profile(), [cand("K1"), cand("K2", person_levende=True, legacy_publication_ref=None, legacy_status=None, legacy_baseline_sha256=None)], {**texts("K1"), **texts("K2")}, CORPUS)
    b = builder.build_manifest(profile(), [cand("K2", person_levende=True, legacy_publication_ref=None, legacy_status=None, legacy_baseline_sha256=None), cand("K1")], {**texts("K2"), **texts("K1")}, CORPUS)
    assert a["manifest_content_sha256"] == b["manifest_content_sha256"]
