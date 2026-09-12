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
        "post_verbatim_text": "Født 1. jan. 1800 i Fiktivby. Blev cand.jur. 1825.",
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
    """--output-schema sendes til CLI'en; filen skal findes og være lukket.

    ALLE felter står i `required` — også `source_persona_id`. Det er ikke en
    skødesløshed: structured outputs afviste skemaet, indtil hvert felt var
    påkrævet (målt mod API'et 2026-09-12). Valgfrihed udtrykkes med `null`.
    Sænk ikke kravet tilbage uden at køre et rigtigt kald igen."""
    schema = json.loads((REFERENCES / "evidence-claims-1.0.json").read_text(encoding="utf-8"))
    assert schema["schema_version"] == "evidence-claims-1.0"
    claim_schema = schema["properties"]["claims"]["items"]
    assert claim_schema["additionalProperties"] is False
    assert set(claim_schema["required"]) == {"clause_ordinals", "predicate", "value",
                                             "confidence", "source_persona_id"}
    assert "null" in claim_schema["properties"]["source_persona_id"]["type"]


def test_the_contract_uses_anyof_not_oneof():
    """`oneOf` er ikke tilladt i et structured-output-skema — API'et afviste det
    med `invalid_json_schema` (målt 2026-09-12).

    Tjekker STRUKTUREN, ikke teksten: ordet "oneOf" står med vilje i skemaets egen
    forklaring, og en tekstsøgning ville derfor fejle på sin egen dokumentation."""
    schema = json.loads((REFERENCES / "evidence-claims-1.0.json").read_text(encoding="utf-8"))

    def nogen_oneof(node):
        if isinstance(node, dict):
            return "oneOf" in node or any(nogen_oneof(v) for v in node.values())
        if isinstance(node, list):
            return any(nogen_oneof(v) for v in node)
        return False

    assert not nogen_oneof(schema)
    assert "anyOf" in schema["properties"]["claims"]["items"]["properties"]["value"]


# ===========================================================================
# Task 3: runneren, cachen og fejltaksonomien
#
# Ingen test i denne fil må starte Codex.  Sømmen `run_codex` erstattes overalt
# af en fixture-leverandør, og standardsømmen i testmiljø kaster.
# ===========================================================================

import evidence_extract
from evidence_runner import (CACHE_KEY_FIELDS, ERROR_KINDS, ResponseCache, build_argv,
                             classify_failure, parse_usage, run_record)


FIXTURES = Path(__file__).resolve().parent / "tests" / "fixtures" / "codex-exec"


def read_fixture(name):
    return (FIXTURES / name).read_text(encoding="utf-8")


def exploding_seam(*args, **kwargs):
    """Bevis for at intet kald slipper ud: sømmen kaster, hvis den bruges."""
    raise AssertionError("run_codex blev kaldt i en test — sømmen skulle have været injiceret")


# --- argv (spec §6.2 + afvigelse A) ---------------------------------------

PROMPT = "Udtræk claims fra posten nedenfor."


def test_argv_carries_every_required_flag():
    argv = build_argv(model="gpt-5.6-terra", call_dir="/tmp/kald",
                      schema_path="/tmp/kald/schema.json", prompt=PROMPT)
    for flag in ("--model", "--sandbox", "--ephemeral", "--ignore-rules",
                 "--ignore-user-config", "--json", "--output-schema"):
        assert flag in argv, f"{flag} mangler i argv"
    assert argv[argv.index("--sandbox") + 1] == "read-only"
    assert argv[argv.index("--model") + 1] == "gpt-5.6-terra"


def test_prompt_is_passed_by_value_never_as_a_stdin_placeholder():
    """`-` ville betyde "læs prompten fra stdin", og stdin er lukket — kaldet ville
    få en TOM prompt. Fejlen findes kun i produktionsstien, som sømmen skjuler for
    de øvrige tests, så den asserteres eksplicit her."""
    argv = build_argv(model="gpt-5.6-terra", call_dir="/tmp/kald",
                      schema_path="/tmp/kald/schema.json", prompt=PROMPT)
    assert argv[-1] == PROMPT
    assert "-" not in argv


def test_argv_refuses_an_empty_prompt():
    with pytest.raises(RunnerError, match="RUNNER_PROMPT_REQUIRED"):
        build_argv(model="gpt-5.6-terra", call_dir="/tmp/kald",
                   schema_path="/tmp/kald/s.json", prompt="   ")


def test_argv_refuses_a_model_outside_the_pinned_set():
    """Modelpolitikken er frossen; runneren må ikke kunne kalde noget andet."""
    with pytest.raises(RunnerError, match="RUNNER_MODEL_NOT_ALLOWED"):
        build_argv(model="gpt-4o", call_dir="/tmp/kald",
                   schema_path="/tmp/kald/s.json", prompt=PROMPT)


# --- svaret hentes af strømmen, ikke af stderr ----------------------------

def test_last_message_comes_from_the_event_stream():
    """stderr bærer "Reading additional input from stdin..." og kan aldrig parses
    som JSON. Svaret ligger i det sidste agent_message."""
    from evidence_runner import extract_last_message
    besked = extract_last_message(read_fixture("turn-completed-with-usage.jsonl"))
    assert json.loads(besked)["claims"][0]["predicate"] == "person.birth_date"


def test_last_message_takes_the_final_answer_when_several_exist():
    """En tur kan begynde med "Jeg forsøger…" og først derefter svare."""
    from evidence_runner import extract_last_message
    assert extract_last_message(read_fixture("sandbox-allowlist-denies-model.jsonl")) == "KAN IKKE LÆSE"


# --- call-dir (Task 2 Step 2-3) -------------------------------------------

def test_call_dir_holds_only_the_record_and_the_schema():
    from evidence_runner import prepare_call_dir
    with prepare_call_dir({"record_key": "I-42"}, {"type": "object"}) as call_dir:
        assert sorted(p.name for p in call_dir.iterdir()) == ["record.json", "schema.json"]
        assert (call_dir.stat().st_mode & 0o777) == 0o700
        for path in call_dir.iterdir():
            assert (path.stat().st_mode & 0o777) == 0o600


def test_call_dir_is_removed_even_when_the_call_raises():
    """En efterladt mappe med kildetekst er et fund, ikke et restprodukt."""
    from evidence_runner import prepare_call_dir
    set_aside = None
    with pytest.raises(ZeroDivisionError):
        with prepare_call_dir({"record_key": "I-42"}, {}) as call_dir:
            set_aside = call_dir
            1 / 0
    assert set_aside is not None and not set_aside.exists()


# --- usage-parser (spec §6.4) ---------------------------------------------

def test_usage_is_read_from_the_observed_fixture():
    usage = parse_usage(read_fixture("turn-completed-with-usage.jsonl"))
    assert usage == {"input_tokens": 21801, "cached_input_tokens": 0, "cache_write_input_tokens": 0,
                     "output_tokens": 218, "reasoning_output_tokens": 84}


def test_missing_usage_on_a_successful_turn_is_unknown_not_zero():
    """Et manglende regnskab er ukendt forbrug. Nul ville være en løgn i budgettet."""
    events = '{"type":"thread.started"}\n{"type":"turn.started"}\n{"type":"turn.completed"}\n'
    with pytest.raises(RunnerError, match="RUNNER_USAGE_UNKNOWN"):
        parse_usage(events)


# --- fejltaksonomi (spec §6.3) --------------------------------------------

def test_every_taxonomy_kind_from_the_spec_exists():
    assert ERROR_KINDS == {"quota_exhausted", "model_refusal", "schema_violation",
                           "timeout", "validation_failed", "unknown", "not_eligible"}


@pytest.mark.parametrize("fixture,forventet", [
    ("failure-quota-exhausted.jsonl", "quota_exhausted"),
    ("failure-model-refusal.jsonl", "model_refusal"),
    ("failure-schema-violation.jsonl", "schema_violation"),
])
def test_failures_are_classified_from_the_event_stream(fixture, forventet):
    assert classify_failure(read_fixture(fixture), exit_code=1) == forventet


def test_timeout_is_classified_from_the_seam_not_the_stream():
    assert classify_failure("", exit_code=None, timed_out=True) == "timeout"


def test_an_unrecognised_failure_is_unknown_never_silently_ok():
    assert classify_failure('{"type":"turn.failed","error":{"kode":42}}', exit_code=1) == "unknown"


# --- cache-identitet (spec §6.3 + anden læsers R7) ------------------------

def test_cache_key_covers_schema_and_runner_version():
    """R7: uden claim-skemaets SHA og runner-kontrakten kan et ændret outputskema
    genbruge et gammelt råsvar."""
    assert CACHE_KEY_FIELDS == ("profile_id", "profile_version", "model", "prompt_sha256",
                                "record_input_sha256", "claims_schema_sha256", "runner_contract_version")


def cache_ident(**overrides):
    base = {"profile_id": "daa-2018-20-v1", "profile_version": "1.3.0", "model": "gpt-5.6-terra",
            "prompt_sha256": "a" * 64, "record_input_sha256": "b" * 64,
            "claims_schema_sha256": "c" * 64, "runner_contract_version": "evidence-runner-1.0"}
    base.update(overrides)
    return base


def test_cache_round_trip(tmp_path):
    cache = ResponseCache(tmp_path)
    cache.put(cache_ident(), raw='{"claims":[]}', usage={"input_tokens": 1})
    hit = cache.get(cache_ident())
    assert hit["raw"] == '{"claims":[]}' and hit["usage"] == {"input_tokens": 1}


def test_cache_miss_returns_none(tmp_path):
    assert ResponseCache(tmp_path).get(cache_ident()) is None


@pytest.mark.parametrize("felt", CACHE_KEY_FIELDS)
def test_every_key_field_changes_the_identity(tmp_path, felt):
    """Én negativ test pr. felt — ellers ved vi ikke, at feltet faktisk indgår."""
    cache = ResponseCache(tmp_path)
    cache.put(cache_ident(), raw="{}", usage={})
    assert cache.get(cache_ident(**{felt: "ANDERLEDES"})) is None


def test_cache_is_append_only(tmp_path):
    """En eksisterende nøgle med afvigende værdi er en konflikt, ikke en overskrivning."""
    cache = ResponseCache(tmp_path)
    cache.put(cache_ident(), raw='{"claims":[]}', usage={})
    with pytest.raises(RunnerError, match="RUNNER_CACHE_CONFLICT"):
        cache.put(cache_ident(), raw='{"claims":[{"noget":"andet"}]}', usage={})


def test_rewriting_the_identical_value_is_not_a_conflict(tmp_path):
    cache = ResponseCache(tmp_path)
    cache.put(cache_ident(), raw="{}", usage={"input_tokens": 1})
    cache.put(cache_ident(), raw="{}", usage={"input_tokens": 1})


def test_cache_files_are_private(tmp_path):
    """§9.1: private artefakter er 0600 i en 0700-mappe — ikke hvad umask tilfældigvis giver."""
    cache = ResponseCache(tmp_path / "cache")
    cache.put(cache_ident(), raw="{}", usage={})
    assert (cache.root.stat().st_mode & 0o777) == 0o700
    for path in cache.root.iterdir():
        assert (path.stat().st_mode & 0o777) == 0o600


# --- orkestrering ---------------------------------------------------------

def seam_returning(fixture_name, last_message):
    def seam(argv, **kwargs):
        return read_fixture(fixture_name), last_message
    return seam


def test_run_record_validates_and_caches(tmp_path):
    cache = ResponseCache(tmp_path)
    last = json.dumps({"claims": [{"clause_ordinals": [1], "predicate": "person.birth",
                                   "value": "1800-01-01", "confidence": 1.0,
                                   "source_persona_id": "persona-1"}]})
    outcome = run_record(export(), ident=cache_ident(), cache=cache,
                         run=seam_returning("turn-completed-with-usage.jsonl", last))
    assert outcome.status == "green" and not outcome.from_cache
    assert outcome.usage["input_tokens"] == 21801

    # Andet kald rammer cachen og starter ikke modellen.
    again = run_record(export(), ident=cache_ident(), cache=cache, run=exploding_seam)
    assert again.status == "green" and again.from_cache


def test_invalid_claims_fail_closed_as_validation_failed(tmp_path):
    last = json.dumps({"claims": [{"clause_ordinals": [99], "predicate": "person.birth",
                                   "value": "1800", "confidence": 1.0,
                                   "source_persona_id": "persona-1"}]})
    outcome = run_record(export(), ident=cache_ident(), cache=ResponseCache(tmp_path),
                         run=seam_returning("turn-completed-with-usage.jsonl", last))
    assert outcome.status == "failed" and outcome.error_kind == "validation_failed"


def test_a_failed_record_is_never_cached(tmp_path):
    """Fail-closed: et afvist svar må ikke kunne genbruges som grønt senere."""
    cache = ResponseCache(tmp_path)
    last = json.dumps({"claims": [{"clause_ordinals": [99], "predicate": "person.birth",
                                   "value": "1800", "confidence": 1.0,
                                   "source_persona_id": "persona-1"}]})
    run_record(export(), ident=cache_ident(), cache=cache,
               run=seam_returning("turn-completed-with-usage.jsonl", last))
    assert cache.get(cache_ident()) is None


def test_failure_log_carries_type_and_record_key_but_never_text(tmp_path):
    """§6.3: fejl logges med typen, aldrig med tekst — heller ikke modellens svar."""
    hemmelig = "Hemmelig prosa om en nulevende person"
    outcome = run_record(export(), ident=cache_ident(), cache=ResponseCache(tmp_path),
                         run=seam_returning("failure-model-refusal.jsonl", hemmelig))
    assert outcome.status == "failed"
    rendered = outcome.log_line()
    assert "model_refusal" in rendered and "I-42" in rendered
    assert hemmelig not in rendered


# --- batch-optælling (spec §6.3) ------------------------------------------

def test_batch_is_green_only_when_every_record_has_a_validated_entry(tmp_path):
    from evidence_runner import batch_status
    assert batch_status([("I-1", "green"), ("I-2", "green")]) == "green"
    assert batch_status([("I-1", "green"), ("I-2", "failed")]) == "pending"
    assert batch_status([]) == "pending"


# --- reusable udvides (anden læsers R7) -----------------------------------

def manifest(**overrides):
    base = dict(profile_id="daa-2018-20-v1", profile_version="1.3.0",
                effective_model_id="gpt-5.6-terra", prompt_version="evidence-extract-1.0.0",
                record_keys=("I-42",), input_hash="a" * 64, extraction_version="ex-1",
                escalation_reason=None, output_hash="d" * 64, token_count=1, cost_usd=0.0,
                validation_status="green")
    base.update(overrides)
    return evidence_extract.BatchManifest(**base)


@pytest.mark.parametrize("felt,vaerdi", [
    ("prompt_sha256", "f" * 64),
    ("exclusion_sha256", "e" * 64),
])
def test_reusable_is_false_when_a_new_manifest_field_changes(felt, vaerdi):
    """R7: de nye felter skal indgå i genbrugsbeslutningen, ikke bare i payloaden."""
    existing = manifest(**{felt: "0" * 64})
    candidate = manifest(**{felt: vaerdi})
    assert evidence_extract.reusable(existing, candidate) is False


# ===========================================================================
# Task 4: prompt-bindingen (afvigelse B + anden læsers R9)
#
# Før 4.3a var `prompt_version` en ren streng, som ingen kode bandt til en fil.
# Profilen sagde `evidence-extract-1.0.0`; filen `extract-prompt.md` sagde
# `2026-07-29b`. Nu skal en profil, der bruges af runneren, pege på en RIGTIG fil
# og bære dens hash.
# ===========================================================================

def test_the_2018_20_profile_binds_a_prompt_file():
    profile = evidence_extract.load_profile("daa-2018-20-v1")
    assert profile["prompt_file"] == "evidence-extract-prompt-1.0.0.md"
    assert len(profile["prompt_sha256"]) == 64


def test_the_bound_hash_matches_the_file_on_disk():
    """Hashen og de bytes, der sendes til modellen, må ikke kunne divergere."""
    profile = evidence_extract.load_profile("daa-2018-20-v1")
    path = REFERENCES / profile["prompt_file"]
    assert evidence_runner.sha256_text(path.read_text(encoding="utf-8")) == profile["prompt_sha256"]


def test_a_drifted_prompt_hash_is_rejected(tmp_path, monkeypatch):
    """En prompt, der ændrer sig uden en ny version, skal stoppe kørslen — ellers
    er `prompt_sha256` i manifestet en påstand, ikke et bevis."""
    with pytest.raises(evidence_extract.ExtractionError, match="EXTRACTION_PROMPT_FILE_DRIFT"):
        evidence_extract.resolve_prompt("evidence-extract-prompt-1.0.0.md", "0" * 64)


def test_a_missing_prompt_file_is_rejected():
    with pytest.raises(evidence_extract.ExtractionError, match="EXTRACTION_PROMPT_FILE_MISSING"):
        evidence_extract.resolve_prompt("findes-ikke-1.0.0.md", "0" * 64)


@pytest.mark.parametrize("ondsindet", ["../../../etc/passwd", "/etc/passwd", "under/mappe.md"])
def test_prompt_file_cannot_escape_the_references_directory(ondsindet):
    """R9: filnavnet må ikke kunne pege ud af references/."""
    with pytest.raises(evidence_extract.ExtractionError, match="EXTRACTION_PROMPT_FILE_INVALID"):
        evidence_extract.resolve_prompt(ondsindet, "0" * 64)


def test_the_1939_profile_is_untouched_and_has_no_prompt_file():
    """1939 bruges ikke af runneren før trin 6. Den skal IKKE have en tom eller
    gættet binding — fraværet er det ærlige svar, og runneren afviser den."""
    profile = evidence_extract.load_profile("daa-1939-v1")
    assert "prompt_file" not in profile
    assert profile["version"] == "1.0.0"


def test_the_legacy_trin3_prompt_is_left_alone():
    """extract-prompt.md er den gamle vejs kontrakt og bruges stadig af SKILL.md."""
    legacy = REFERENCES / "extract-prompt.md"
    assert legacy.exists()
    assert "prompt-version: 2026-07-29b" in legacy.read_text(encoding="utf-8")[:200]


# ===========================================================================
# Task 5: eligibility-ledgeren (spec §9.1-9.2, omskrevet af anden læsers R2/R3)
#
# Grundreglen: FRAVÆR ER IKKE TILLADELSE. En record, der ikke står i ledgeren som
# eksplicit `eligible`, må ikke sendes til en model — heller ikke hvis ledgeren
# i øvrigt er gyldig og hashen passer.
# ===========================================================================

from evidence_runner import (EligibilityError, LEDGER_SCHEMA_VERSION, canonical_record_input,
                             check_eligibility, load_ledger, run_record_guarded)


def ledger_rows(**overrides):
    rows = {
        "I-42": {"status": "eligible", "reasons": [],
                 "record_input_sha256": canonical_record_input(export())},
        "I-99": {"status": "excluded", "reasons": ["principal_living"],
                 "record_input_sha256": "c" * 64},
        "I-50": {"status": "excluded",
                 "reasons": ["principal_living", "relative_living", "spouse_undated_marriage"],
                 "record_input_sha256": "d" * 64},
    }
    rows.update(overrides)
    return rows


def ledger(**overrides):
    base = {"schema_version": LEDGER_SCHEMA_VERSION,
            "policy_version": "exclusion-2018-20-v1",
            "rules_script_sha256": "e" * 64,
            "source_id": 1,
            "restore_identity": "daa-restore-20260912",
            "records": ledger_rows()}
    base.update(overrides)
    return base


# --- ledgerens egen gyldighed --------------------------------------------

def test_a_valid_ledger_loads():
    assert load_ledger(ledger())["policy_version"] == "exclusion-2018-20-v1"


@pytest.mark.parametrize("felt", ["schema_version", "policy_version", "rules_script_sha256",
                                  "source_id", "restore_identity", "records"])
def test_every_provenance_field_is_required(felt):
    """R3: hashen må ikke kun dække eksportresultatet. Uden regler, script og
    snapshot kan en gammel eller fejlimplementeret liste se gyldig ud."""
    ufuldstaendig = {k: v for k, v in ledger().items() if k != felt}
    with pytest.raises(EligibilityError, match="LEDGER_INCOMPLETE"):
        load_ledger(ufuldstaendig)


def test_a_ledger_from_another_schema_version_is_rejected():
    with pytest.raises(EligibilityError, match="LEDGER_SCHEMA_UNKNOWN"):
        load_ledger(ledger(schema_version="noget-andet-1.0"))


def test_a_row_with_an_unknown_status_is_rejected():
    """Kun `eligible` og `excluded` findes. Et tredje ord må ikke kunne tolkes."""
    rows = ledger_rows(**{"I-7": {"status": "maaske", "reasons": [],
                                  "record_input_sha256": "f" * 64}})
    with pytest.raises(EligibilityError, match="LEDGER_STATUS_INVALID"):
        load_ledger(ledger(records=rows))


def test_an_excluded_row_must_carry_at_least_one_reason():
    """En udelukkelse uden årsag kan ikke efterprøves af et menneske."""
    rows = ledger_rows(**{"I-8": {"status": "excluded", "reasons": [],
                                  "record_input_sha256": "f" * 64}})
    with pytest.raises(EligibilityError, match="LEDGER_REASON_REQUIRED"):
        load_ledger(ledger(records=rows))


def test_reasons_must_come_from_the_closed_rule_set():
    rows = ledger_rows(**{"I-9": {"status": "excluded", "reasons": ["fordi-jeg-synes"],
                                  "record_input_sha256": "f" * 64}})
    with pytest.raises(EligibilityError, match="LEDGER_REASON_UNKNOWN"):
        load_ledger(ledger(records=rows))


# --- opslaget: fravær er ikke tilladelse ---------------------------------

def test_an_eligible_record_passes():
    assert check_eligibility(ledger(), "I-42", canonical_record_input(export())) == "eligible"


@pytest.mark.parametrize("aarsag", ["principal_living", "relative_living",
                                    "spouse_undated_marriage", "birth_year_text_filter"])
def test_each_of_the_four_rules_blocks_on_its_own(aarsag):
    """§9.2's fire regler. Hver skal kunne stoppe en record alene."""
    rows = ledger_rows(**{"I-1": {"status": "excluded", "reasons": [aarsag],
                                  "record_input_sha256": "a" * 64}})
    with pytest.raises(EligibilityError, match="RECORD_EXCLUDED"):
        check_eligibility(ledger(records=rows), "I-1", "a" * 64)


def test_multiple_reasons_are_all_carried():
    """En record kan rammes af flere regler; alle årsager skal med i fejlen."""
    with pytest.raises(EligibilityError) as exc:
        check_eligibility(ledger(), "I-50", "d" * 64)
    for aarsag in ("principal_living", "relative_living", "spouse_undated_marriage"):
        assert aarsag in str(exc.value)


def test_an_unknown_record_is_refused_not_allowed():
    """KERNEREGLEN. En record, ledgeren ikke kender, er ikke tilladt — den er ukendt,
    og ukendt betyder nej."""
    with pytest.raises(EligibilityError, match="RECORD_UNKNOWN"):
        check_eligibility(ledger(), "I-DENNE-FINDES-IKKE", "a" * 64)


def test_an_eligible_row_with_a_drifted_input_hash_is_refused():
    """Ledgeren godkendte ét input. Sendes et andet, gælder godkendelsen ikke."""
    with pytest.raises(EligibilityError, match="RECORD_INPUT_DRIFT"):
        check_eligibility(ledger(), "I-42", canonical_record_input(
            export(post_verbatim_text="En anden tekst end den godkendte.")))


def test_the_canonical_hash_is_the_post_text_alone():
    """ÉN definition, brugt af både ledger-eksporten (SQL) og runneren (Python).
    Et tidligere udkast hashede forskellige ting de to steder, så kontrollen enten
    afviste alt eller blev omgået (anden læsers fund 3)."""
    e = export()
    assert canonical_record_input(e) == evidence_runner.sha256_text(e["post_verbatim_text"])


def test_a_record_without_post_text_cannot_be_hashed():
    """Fail-closed: uden et input at binde godkendelsen til er der intet at godkende."""
    uden = {k: v for k, v in export().items() if k != "post_verbatim_text"}
    with pytest.raises(EligibilityError, match="RECORD_INPUT_TEXT_MISSING"):
        canonical_record_input(uden)


# --- værnet foran runneren ------------------------------------------------

@pytest.mark.parametrize("record_key,overrides", [
    ("I-99", {}),                                              # excluded
    ("I-UKENDT", {}),                                          # står ikke i ledgeren
    ("I-42", {"post_verbatim_text": "En HELT anden tekst."}),   # eligible nøgle, andet input
])
def test_codex_is_never_started_for_a_non_eligible_record(tmp_path, record_key, overrides):
    """BEVISET, ikke blot en returværdi: sømmen kaster, hvis den overhovedet kaldes.
    Består testen, er modellen aldrig blevet spurgt."""
    outcome = run_record_guarded(export(record_key=record_key, **overrides), ledger=ledger(),
                                 ident=cache_ident(), cache=ResponseCache(tmp_path),
                                 run=exploding_seam)
    assert outcome.status == "failed"
    assert outcome.error_kind == "not_eligible"


def test_the_guard_lets_an_eligible_record_through(tmp_path):
    last = json.dumps({"claims": []})
    outcome = run_record_guarded(export(record_key="I-42"), ledger=ledger(),
                                 ident=cache_ident(), cache=ResponseCache(tmp_path),
                                 run=seam_returning("turn-completed-with-usage.jsonl", last))
    assert outcome.status == "green"


def test_an_excluded_record_stays_visible_in_the_accounting(tmp_path):
    """Step 6: udelukkede records er ikke tab. De skal kunne ses i logget."""
    outcome = run_record_guarded(export(record_key="I-50"), ledger=ledger(),
                                 ident=cache_ident(), cache=ResponseCache(tmp_path),
                                 run=exploding_seam)
    linje = outcome.log_line()
    assert "I-50" in linje and "not_eligible" in linje


# ===========================================================================
# Task 6: kaldet bag gaten
# ===========================================================================

from evidence_runner import build_gate_profile, build_gated_argv


def test_gate_profile_closes_the_home_directory(tmp_path):
    profil = build_gate_profile(call_dir="/tmp/kald", home="/Users/x", extra_deny=[])
    assert '(deny file-read* (subpath "/Users/x"))' in profil
    assert '(allow file-read* (subpath "/tmp/kald"))' in profil
    # ~/Library må IKKE stå der: den var åben i et tidligere udkast, og
    # ~/Library/Keychains var læsbar med den.
    assert "/Users/x/Library" not in profil


def test_gate_profile_takes_extra_denies():
    profil = build_gate_profile(call_dir="/tmp/k", home="/Users/x",
                                extra_deny=["/tmp/syntetisk-pii"])
    assert '(deny file-read* (subpath "/tmp/syntetisk-pii"))' in profil


def test_gated_argv_wraps_codex_in_sandbox_exec():
    argv = build_gated_argv(profile_path="/tmp/k/gate.sb", model="gpt-5.6-terra",
                            call_dir="/tmp/k", schema_path="/tmp/k/schema.json",
                            prompt="Udtræk claims.")
    assert argv[:3] == ["sandbox-exec", "-f", "/tmp/k/gate.sb"]
    assert argv[3] == "codex"
    assert "--ignore-user-config" in argv and argv[-1] == "Udtræk claims."
