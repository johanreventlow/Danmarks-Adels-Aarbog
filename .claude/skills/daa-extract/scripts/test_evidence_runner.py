"""Tests for den record-scoped claim-kontrakt (#147 dagsværk 4.3a, Task 1).

Kontrakten er record-scoped: modellen ser ÉN helpost med dens klausuler og citerer
klausul-**ordinaler** — ikke rendition-absolutte offsets. `validate_output`'s strict
bundle-vej kræver hele renditionens tekst og passer derfor ikke (spec §6.1).

Testene starter aldrig Codex. Runnerens modelkald ligger bag en injicerbar søm.
"""
import json
from pathlib import Path

import pytest

import evidence_runner
from evidence_runner import RunnerError, validate_record_claims


REFERENCES = Path(__file__).resolve().parents[1] / "references"


def export(**overrides):
    """En record-scoped eksport, som den ser ud fra restoren."""
    base = {
        "record_key": "I-42",
        "persona_id": "persona-1",
        "clauses": [
            {"ordinal": 1, "verbatim_text": "Født 1. jan. 1800 i Fiktivby.",
             "verbatim_sha256": evidence_runner.sha256_text("Født 1. jan. 1800 i Fiktivby.")},
            {"ordinal": 2, "verbatim_text": "Blev cand.jur. 1825.",
             "verbatim_sha256": evidence_runner.sha256_text("Blev cand.jur. 1825.")},
        ],
    }
    base.update(overrides)
    return base


def claim(**overrides):
    base = {"clause_ordinals": [1], "predicate": "person.birth",
            "value": "1800-01-01", "confidence": 0.9, "source_persona_id": "persona-1"}
    base.update(overrides)
    return base


# --- positiv kontrol -------------------------------------------------------

def test_valid_claims_pass():
    validate_record_claims([claim()], export())


def test_empty_claims_are_allowed():
    """En record uden udtrækbare fakta er et gyldigt svar, ikke en fejl."""
    validate_record_claims([], export())


# --- ordinaler (spec §6.1) -------------------------------------------------

def test_claim_without_ordinal_is_rejected():
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_ORDINAL_REQUIRED"):
        validate_record_claims([claim(clause_ordinals=[])], export())


def test_ordinal_outside_the_export_is_rejected():
    """Modellen må ikke citere en klausul, den ikke fik at se."""
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_ORDINAL_UNKNOWN"):
        validate_record_claims([claim(clause_ordinals=[99])], export())


def test_ordinal_with_drifted_hash_is_rejected():
    """Eksportens tekst skal matche sin egen hash — ellers er grundlaget skredet."""
    bad = export()
    bad["clauses"][0]["verbatim_sha256"] = "0" * 64
    with pytest.raises(RunnerError, match="RUNNER_EXPORT_HASH_MISMATCH"):
        validate_record_claims([claim()], bad)


# --- vokabular: genbruger 4.2's tabel, intet parallelt sæt -----------------

def test_unknown_predicate_is_rejected():
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_PREDICATE_INVALID"):
        validate_record_claims([claim(predicate="person.favourite_colour")], export())


def test_model_cannot_assert_its_own_interpretation_kind():
    """4.2's lære: udsagnsformen ejes af tabellen, og gættet ud fra præfikset kunne
    ikke skelne event.marriage fra relation.marriage. Derfor er `interpretation_kind`
    slet ikke en nøgle i kontrakten — modellen kan ikke påstå en, og det lukkede
    nøglesæt afviser forsøget. Et 'match tabellen'-tjek ville være død kode."""
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_KEYS_INVALID"):
        validate_record_claims([claim(interpretation_kind="event")], export())


def test_value_form_must_match_the_predicates_value_kind():
    """person.birth er date_raw (skalar); et objekt er forkert form."""
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_VALUE_INVALID"):
        validate_record_claims([claim(value={"raw": "1800"})], export())


def test_object_valued_predicate_requires_raw():
    """relation.* har value_kind=relation og kræver en ordret raw."""
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_VALUE_INVALID"):
        validate_record_claims(
            [claim(predicate="relation.marriage", value="Prøve Fiktivsdatter")], export())


# --- konfidens -------------------------------------------------------------

@pytest.mark.parametrize("bad", [-0.1, 1.1, "høj", None])
def test_confidence_must_be_a_number_in_the_unit_interval(bad):
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_CONFIDENCE_INVALID"):
        validate_record_claims([claim(confidence=bad)], export())


# --- persona-reglen (spec §6.1 fund 3a) -----------------------------------

def test_person_claim_requires_the_records_persona():
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_PERSONA_REQUIRED"):
        validate_record_claims([claim(source_persona_id="en-anden-persona")], export())


def test_person_claim_may_cite_any_clause_under_the_post():
    """Fund 3a: reglen er 'klausuler under helposten', IKKE den snævrere
    'delmængde af personaens egne mention-observationer', som validate_output
    bruger. Forskellen står her, så den ikke senere 'rettes' tilbage."""
    validate_record_claims([claim(clause_ordinals=[1, 2])], export())


def test_non_person_claim_does_not_require_a_persona():
    validate_record_claims(
        [{"clause_ordinals": [2], "predicate": "event.appointment",
          "value": {"raw": "cand.jur. 1825"}, "confidence": 0.5}], export())


# --- lukket nøglesæt: intet må smugles med -------------------------------

def test_unknown_key_on_a_claim_is_rejected():
    """Payloaden lagres permanent; et frit nøglesæt er en vej for kildetekst."""
    with pytest.raises(RunnerError, match="RUNNER_CLAIM_KEYS_INVALID"):
        validate_record_claims([claim(kommentar="fri tekst fra modellen")], export())


# --- kontraktfilen ---------------------------------------------------------

def test_claims_contract_file_matches_the_validator():
    """--output-schema sendes til CLI'en; filen skal findes og være lukket."""
    schema = json.loads((REFERENCES / "evidence-claims-1.0.json").read_text(encoding="utf-8"))
    assert schema["schema_version"] == "evidence-claims-1.0"
    claim_schema = schema["properties"]["claims"]["items"]
    assert claim_schema["additionalProperties"] is False
    assert set(claim_schema["required"]) == {"clause_ordinals", "predicate", "value", "confidence"}
