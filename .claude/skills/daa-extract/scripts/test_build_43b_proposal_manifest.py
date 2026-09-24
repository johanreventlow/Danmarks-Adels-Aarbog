"""Klassifikationsreglerne i 4.4's manifest-builder.

Her — ikke i writeren — afgøres om et claim kommer med. Writeren ser én record
ad gangen, så en exception der ruller hele recorden tilbage; det var den fejl,
projektejeren afgjorde imod efter 4.3b's bundt 1. Derfor skal reglerne have
deres egen dækning.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from build_43b_proposal_manifest import parse_cached_raw_claims, persona_rolle, uden_modpart
from evidence_runner import partition_record_claims, sha256_text

PROFIL = (Path(__file__).resolve().parents[1]
          / "references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json")


@pytest.fixture(scope="module")
def profil() -> dict:
    return json.loads(PROFIL.read_text(encoding="utf-8"))


# --- persona_role -------------------------------------------------------------

@pytest.mark.parametrize("predicate,forventet", [
    ("person.death", "principal"),
    # Spec §7.2's hul: event.* handler om hovedpersonen uden person.-præfiks.
    ("event.appointment", "principal"),
    ("event.dismissal", "principal"),
    ("event.acquisition", "principal"),
    ("heraldry.blazon", "principal"),
    ("lineage.introduction", "principal"),
    ("mention.person", "other"),
    ("relation.marriage", "other"),
])
def test_rollen_kommer_fra_profilens_kort(profil, predicate, forventet):
    assert persona_rolle(predicate, profil["persona_role_map"]) == forventet


def test_ukendt_praedikat_giver_ingen_rolle(profil):
    """Fail-closed: kalderen afviser claimet frem for at gætte en rolle."""
    assert persona_rolle("ukendt.ting", profil["persona_role_map"]) is None


def test_laengste_praefiks_vinder():
    """Ellers ville listernes rækkefølge afgøre det stiltiende."""
    kort = {"principal": ["event."], "other": ["event.marriage"]}
    assert persona_rolle("event.marriage", kort) == "other"
    assert persona_rolle("event.travel", kort) == "principal"


def test_selvmodsigende_kort_rejser():
    kort = {"principal": ["event."], "other": ["event."]}
    with pytest.raises(ValueError, match="selvmodsigende"):
        persona_rolle("event.x", kort)


# --- H1: relation uden modpart ------------------------------------------------

@pytest.mark.parametrize("raw", ["NN.", "N. N.", "ukendt", "4 sønner", "fire døtre",
                                 "tvillinger", "børn", "  "])
def test_h1_fanger_vaerdier_uden_modpart(profil, raw):
    assert uden_modpart(raw, profil["no_counterpart_denylist"]) is True


@pytest.mark.parametrize("raw", ["Anne Sophie Reventlow", "4 sønner, som døde små",
                                 "Christian Ditlev"])
def test_h1_er_anchored_paa_hele_strengen(profil, raw):
    """Med vilje: H1 er en tidsbesparelse, ikke en korrekthedsgate. 4.5 er gaten."""
    assert uden_modpart(raw, profil["no_counterpart_denylist"]) is False


def test_h1_laeser_baade_streng_og_objektvaerdi(profil):
    deny = profil["no_counterpart_denylist"]
    assert uden_modpart({"raw": "NN."}, deny) is True
    assert uden_modpart({"raw": "Anne"}, deny) is False
    assert uden_modpart({"ingen_raw": "NN."}, deny) is False


def test_numeric_claim_values_are_rejected_before_builder_key_derivation():
    """Mutation caught: accepting a numeric value would let it reach key material."""
    text = "Født 1. jan. 1800 i Fiktivby."
    record = {
        "record_key": "I-42", "persona_id": "persona-1", "clauses": [
            {"ordinal": 1, "verbatim_text": text, "verbatim_sha256": sha256_text(text)},
        ],
    }
    legal = {"clause_ordinals": [1], "predicate": "person.birth", "value": "1800-01-01",
             "confidence": 0.9, "source_persona_id": "persona-1"}
    numeric = dict(legal, value={"raw": "1800", "normalized": 1800})
    accepted, rejected = partition_record_claims([legal, numeric], record)
    assert accepted == [legal]
    assert rejected == [{"claim": numeric, "fejl": "RUNNER_CLAIM_VALUE_INVALID"}]


def test_cached_raw_claims_reject_duplicate_json_keys_before_partitioning():
    """Mutation caught: an ordinary json decoder silently retains the last key."""
    with pytest.raises(ValueError, match="CACHE_RAW_JSON_INVALID"):
        parse_cached_raw_claims('{"claims":[],"claims":[]}')


def test_cached_raw_claims_returns_only_a_json_claim_list():
    assert parse_cached_raw_claims('{"claims":[]}') == []


def test_cached_raw_fractional_confidence_survives_the_claim_boundary():
    """Review C1: strict decoding must not turn a legal 0.9 confidence into a Decimal
    that the runner's float check then rejects."""
    text = "Født 1. jan. 1800 i Fiktivby."
    record = {
        "record_key": "I-42", "persona_id": "persona-1", "clauses": [
            {"ordinal": 1, "verbatim_text": text, "verbatim_sha256": sha256_text(text)},
        ],
    }
    raw = ('{"claims":[{"clause_ordinals":[1],"predicate":"person.birth",'
           '"value":"1800-01-01","confidence":0.9,"source_persona_id":"persona-1"}]}')
    accepted, rejected = partition_record_claims(parse_cached_raw_claims(raw), record)
    assert rejected == []
    assert len(accepted) == 1 and accepted[0]["confidence"] == 0.9


def test_current_cache_key_finder_filen_med_record_key(tmp_path):
    import build_43b_proposal_manifest as b
    import evidence_runner
    rec = {"record_key": "R-1", "persona_id": "p", "post_verbatim_text": "t",
           "clauses": [{"ordinal": 1, "verbatim_text": "t",
                        "verbatim_sha256": evidence_runner.sha256_text("t")}]}
    ident = {"profile_id": "daa-2018-20-v1", "profile_version": "1.3.0", "model": "m",
             "prompt_sha256": "p", "record_key": "R-1",
             "record_input_sha256": evidence_runner.canonical_record_input(rec),
             "claims_schema_sha256": "s",
             "runner_contract_version": evidence_runner.RUNNER_CONTRACT_VERSION}
    assert b.cache_path(tmp_path, ident, mode="current").name == \
        f"{evidence_runner.ResponseCache.key(ident)}.json"
    legacy = {k: v for k, v in ident.items() if k != "record_key"}
    assert b.cache_path(tmp_path, legacy, mode="legacy").name == \
        f"{b.legacy_cache_key(legacy)}.json"


def test_records_to_ingest_tager_kun_navngivne_bundter():
    import pytest
    import build_43b_proposal_manifest as b
    m = {"records": ["A", "B", "C"], "bundter": {"bundt_1": ["A", "B"], "reserve": ["C"]}}
    assert b.records_to_ingest(m, None) == ["A", "B", "C"]
    assert b.records_to_ingest(m, ["bundt_1"]) == ["A", "B"]
    with pytest.raises(ValueError, match="BUNDLE_UNKNOWN"):
        b.records_to_ingest(m, ["bundt_9"])
