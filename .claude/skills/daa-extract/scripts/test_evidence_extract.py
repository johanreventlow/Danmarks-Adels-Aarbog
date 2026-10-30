import hashlib
import json
from dataclasses import replace

import pytest

import evidence_extract
from evidence_extract import ExtractionError, complete_batch, load_profile, manifest_payload, prepare_batch, reusable


RECORDS = [{"record_key": "record-a", "raw": "Født 1801."}, {"record_key": "record-b", "raw": "Gift 1820."}]


def validate_output(*args, **kwargs):
    implementation = getattr(evidence_extract, "validate_output", None)
    if implementation is None:
        pytest.fail("validate_output mangler")
    return implementation(*args, **kwargs)


def test_profiles_pin_terra_and_sol_without_ambient_settings(monkeypatch):
    monkeypatch.setenv("MODEL", "anything-else")
    batch = prepare_batch("daa-1939-v1", RECORDS, extraction_version="extractor-1")
    assert batch.effective_model_id == "gpt-5.6-terra"
    assert batch.prompt_version == load_profile("daa-1939-v1")["prompt_version"]


def test_sol_requires_explicit_escalation_gate():
    with pytest.raises(ExtractionError, match="ESCALATION"):
        prepare_batch("daa-1939-v1", RECORDS, extraction_version="extractor-1", escalate=True)
    assert prepare_batch("daa-1939-v1", RECORDS, extraction_version="extractor-1", escalate=True,
                         escalation_reason="unreadable structural header").effective_model_id == "gpt-5.6-sol"


def test_batch_rejects_missing_or_duplicate_record_key():
    with pytest.raises(ExtractionError, match="RECORD_KEYS"):
        prepare_batch("daa-1939-v1", [{"record_key": ""}], extraction_version="extractor-1")
    with pytest.raises(ExtractionError, match="RECORD_KEYS"):
        prepare_batch("daa-1939-v1", [RECORDS[0], RECORDS[0]], extraction_version="extractor-1")


def test_partial_output_never_becomes_green_or_reusable():
    pending = prepare_batch("daa-1939-v1", RECORDS, extraction_version="extractor-1")
    with pytest.raises(ExtractionError, match="PARTIAL"):
        complete_batch(pending, {"record_keys": ["record-a"], "partial": True}, token_count=1, cost_usd=0.01)


def test_only_identical_green_batch_is_reusable():
    pending = prepare_batch("daa-2018-20-v1", RECORDS, extraction_version="extractor-1")
    green = complete_batch(pending, {"record_keys": ["record-a", "record-b"], "observations": []}, token_count=5, cost_usd=0.02)
    assert reusable(green, pending)
    assert not reusable(green, replace(pending, input_hash="changed"))


def test_manifest_payload_has_json_stable_record_keys():
    batch = prepare_batch("daa-2018-20-v1", RECORDS, extraction_version="extractor-1")

    payload = manifest_payload(batch)

    assert payload["record_keys"] == ["record-a", "record-b"]
    assert payload == json.loads(json.dumps(payload))


def _bundle():
    text = "Våben: tre roser."
    return {
        "schema_version": "1.1", "source_rendition": [{
            "rendition_id": "rendition-1", "source_id": "2018-20",
            "sha256": hashlib.sha256(text.encode()).hexdigest(), "verbatim_text": text,
        }], "source_records": [],
        "source_record_anchor_events": [], "source_record_revision_events": [],
        "record_placements": [], "persona_placements": [], "text_variants": [],
        "mentions": [], "source_personas": [], "extraction_run": {"run_id": "run-1"},
        "source_record_occurrences": [{
            "occurrence_id": "occ-1", "rendition_id": "rendition-1", "extraction_run_id": "run-1",
            "verbatim_text": text, "span": {"rendition_id": "rendition-1", "page_from": 1, "page_to": 1,
                "char_from": 0, "char_to": len(text), "bbox": None},
        }],
        "observations": [{
            "observation_id": "obs-1", "occurrence_id": "occ-1", "kind": "heraldry_clause",
            "verbatim_text": text, "extraction_method": "model", "extraction_run_id": "run-1",
            "span": {"rendition_id": "rendition-1", "page_from": 1, "page_to": 1,
                "char_from": 0, "char_to": len(text), "bbox": None},
        }],
    }


def _anchored_bundle():
    bundle = _bundle()
    bundle["source_records"] = [{"id": "record-1", "record_key": "rk-1", "source_id": "2018-20"}]
    bundle["source_record_anchor_events"] = [{
        "event_id": "anchor-1", "occurrence_id": "occ-1", "source_record_id": "record-1",
        "decision_status": "accepted", "version": 1,
    }]
    return bundle


def two_person_bundle():
    rendition_text = "Anna. Bodil."
    bundle = {
        "schema_version": "1.1",
        "source_rendition": [{
            "rendition_id": "rendition-1", "source_id": "2018-20",
            "sha256": hashlib.sha256(rendition_text.encode()).hexdigest(),
            "verbatim_text": rendition_text,
        }],
        "source_records": [
            {"id": "record-a", "record_key": "rk-a", "source_id": "2018-20"},
            {"id": "record-b", "record_key": "rk-b", "source_id": "2018-20"},
        ],
        "source_record_occurrences": [], "source_record_anchor_events": [],
        "source_record_revision_events": [], "record_placements": [], "persona_placements": [],
        "observations": [], "text_variants": [], "mentions": [], "source_personas": [],
        "extraction_run": {"run_id": "run-1"}, "interpretations": [],
    }
    for suffix, name, start in (("a", "Anna", 0), ("b", "Bodil", 6)):
        end = start + len(name)
        bundle["source_record_occurrences"].append({
            "occurrence_id": "occ-" + suffix, "rendition_id": "rendition-1",
            "extraction_run_id": "run-1", "verbatim_text": name,
            "span": {"rendition_id": "rendition-1", "page_from": 1, "page_to": 1,
                     "char_from": start, "char_to": end, "bbox": None},
        })
        bundle["source_record_anchor_events"].append({
            "event_id": "anchor-" + suffix, "occurrence_id": "occ-" + suffix,
            "source_record_id": "record-" + suffix, "decision_status": "accepted", "version": 1,
        })
        bundle["observations"].append({
            "observation_id": "obs-" + suffix, "occurrence_id": "occ-" + suffix,
            "kind": "person_name", "verbatim_text": name, "extraction_method": "model",
            "extraction_run_id": "run-1",
            "span": {"rendition_id": "rendition-1", "page_from": 1, "page_to": 1,
                     "char_from": start, "char_to": end, "bbox": None},
        })
        bundle["mentions"].append({
            "mention_id": "mention-" + suffix, "observation_id": "obs-" + suffix,
            "char_from": 0, "char_to": len(name), "verbatim_text": name,
        })
        bundle["source_personas"].append({
            "persona_id": "persona-" + suffix, "source_id": "2018-20",
            "mention_ids": ["mention-" + suffix],
        })
    return bundle


def test_person_claim_rejects_another_personas_observation():
    bundle = two_person_bundle()
    with pytest.raises(ExtractionError, match="PERSONA_OBSERVATION"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "person.name", "record_key": "rk-b",
            "source_persona_id": "persona-a", "observation_ids": ["obs-b"],
            "value": "Bodil",
        }]})


def test_granular_claim_requires_observed_evidence_bundle():
    with pytest.raises(ExtractionError, match="EVIDENCE_BUNDLE"):
        validate_output({"claims": [{"predicate": "title.rank", "observation_ids": ["obs-1"], "value": "greve"}]})


def test_granular_claim_rejects_unknown_predicate_and_missing_observation():
    with pytest.raises(ExtractionError, match="PREDICATE"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{"predicate": "made.up", "observation_ids": ["obs-1"], "value": "x"}]})
    with pytest.raises(ExtractionError, match="OBSERVATION"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{"predicate": "heraldry.blazon", "observation_ids": ["missing"], "value": "tre roser"}]})


def test_known_granular_predicates_are_explicit_and_unknown_subtypes_fail_closed():
    bundle = _anchored_bundle()
    # #147 4.2: navnene kommer nu fra prædikattabellen. Værdiformen følger
    # prædikatets value_kind — skalar for text/date_raw, objekt med raw for
    # name/event/relation/mention — så prøven skal bygge begge former.
    expected_predicates = [
        "person.birth",
        "person.baptism",
        "person.death",
        "person.burial",
        "relation.marriage",
        "relation.parent",
        "relation.child",
        "person.title",
        "person.form_of_address",
        "person.rank",
        "person.office",
        "person.education",
        "person.estate",
        "person.residence",
        "person.military_service",
        "person.decoration",
        "person.publication",
        "lineage.introduction",
        "genealogy.generation_header",
        "heraldry.blazon",
        "image.caption",
        "reference.cross_reference",
    ]
    scalar_kinds = {"text", "date_raw"}
    def _value(predicate):
        return "x" if evidence_extract.PREDICATES[predicate]["value_kind"] in scalar_kinds else {"raw": "x"}
    # person.*-claims kræver en persona, der ejer observationen. Kæden bygges her
    # frem for at udelade den: prøven skal ligne det, extractoren faktisk leverer.
    bundle["mentions"].append({
        "mention_id": "mention-1", "observation_id": "obs-1",
        "char_from": 0, "char_to": 5, "verbatim_text": bundle["observations"][0]["verbatim_text"][:5],
    })
    bundle["source_personas"].append({
        "persona_id": "persona-1", "source_id": "2018-20", "mention_ids": ["mention-1"],
    })
    validate_output({"evidence_bundle": bundle, "claims": [{
        "predicate": predicate, "record_key": "rk-1", "observation_ids": ["obs-1"],
        "value": _value(predicate),
        **({"source_persona_id": "persona-1"} if predicate.startswith("person.") else {}),
    } for predicate in expected_predicates]})

    with pytest.raises(ExtractionError, match="PREDICATE"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "person.invented", "record_key": "rk-1", "source_persona_id": "persona-1",
            "observation_ids": ["obs-1"], "value": "x",
        }]})


def test_non_personal_heraldry_claim_is_valid_without_artificial_persona():
    assert validate_output({"evidence_bundle": _anchored_bundle(), "claims": [{
        "predicate": "heraldry.blazon", "record_key": "rk-1", "observation_ids": ["obs-1"], "value": "tre roser",
    }]}) is None


def test_person_claim_requires_a_source_persona_not_an_invented_person():
    with pytest.raises(ExtractionError, match="PERSONA"):
        validate_output({"evidence_bundle": _anchored_bundle(), "claims": [{
            "predicate": "person.name", "record_key": "rk-1", "observation_ids": ["obs-1"], "value": "Anna",
        }]})


def test_person_claim_accepts_complete_persona_observation_chain():
    bundle = _anchored_bundle()
    text = bundle["observations"][0]["verbatim_text"]
    bundle["source_personas"] = [{
        "persona_id": "persona-1", "source_id": "2018-20", "mention_ids": ["mention-1"],
    }]
    bundle["mentions"] = [{
        "mention_id": "mention-1", "observation_id": "obs-1",
        "char_from": 0, "char_to": len(text), "verbatim_text": text,
    }]
    assert validate_output({"evidence_bundle": bundle, "claims": [{
        "predicate": "person.name", "record_key": "rk-1", "source_persona_id": "persona-1",
        "observation_ids": ["obs-1"], "value": "Anna",
    }]}) is None


def test_claim_record_key_must_name_its_accepted_source_record():
    bundle = _bundle()
    bundle["source_records"] = [{"id": "record-1", "record_key": "rk-1", "source_id": "2018-20"}]
    bundle["source_record_anchor_events"] = [{
        "event_id": "anchor-1", "occurrence_id": "occ-1", "source_record_id": "record-1",
        "decision_status": "accepted", "version": 1,
    }]
    with pytest.raises(ExtractionError, match="RECORD_KEY"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "heraldry.blazon", "record_key": "wrong", "observation_ids": ["obs-1"], "value": "tre roser",
        }]})


def test_every_granular_claim_requires_its_accepted_record_key():
    bundle = _bundle()
    bundle["source_records"] = [{"id": "record-1", "record_key": "rk-1", "source_id": "2018-20"}]
    bundle["source_record_anchor_events"] = [{
        "event_id": "anchor-1", "occurrence_id": "occ-1", "source_record_id": "record-1",
        "decision_status": "accepted", "version": 1,
    }]
    with pytest.raises(ExtractionError, match="RECORD_KEY"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "heraldry.blazon", "observation_ids": ["obs-1"], "value": "tre roser",
        }]})


def test_valid_claim_becomes_proposed_private_interpretation_not_canonical_fact():
    implementation = getattr(evidence_extract, "build_interpretation_candidates", None)
    if implementation is None:
        pytest.fail("build_interpretation_candidates mangler")
    candidates = implementation({"evidence_bundle": _anchored_bundle(), "claims": [{
        "predicate": "heraldry.blazon", "record_key": "rk-1", "observation_ids": ["obs-1"],
        "value": "tre roser", "confidence": 0.8,
    }]}, source_id=1939, extraction_run_id="run-1")
    assert candidates == [{
        "source_id": 1939, "source_persona_id": None, "interpretation_kind": "property",
        "predicate": "heraldry.blazon", "value": "tre roser", "status": "proposed",
        "derivation_kind": "model_inference", "confidence": 0.8, "method": "model",
        "extraction_run_id": "run-1", "record_key": "rk-1", "observation_ids": ["obs-1"],
    }]


def test_unanchored_observation_cannot_bypass_record_key_gate_with_empty_string():
    with pytest.raises(ExtractionError, match="RECORD_KEY"):
        validate_output({"evidence_bundle": _bundle(), "claims": [{
            "predicate": "heraldry.blazon", "record_key": "", "observation_ids": ["obs-1"], "value": "tre roser",
        }]})


def test_claims_reject_legacy_draft_bundle_version():
    bundle = _anchored_bundle()
    bundle["schema_version"] = "1.0"
    with pytest.raises(ExtractionError, match="BUNDLE_VERSION"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "heraldry.blazon", "record_key": "rk-1",
            "observation_ids": ["obs-1"], "value": "tre roser",
        }]})


def test_interpretation_candidate_requires_explicit_model_confidence():
    with pytest.raises(ExtractionError, match="CONFIDENCE"):
        build = getattr(evidence_extract, "build_interpretation_candidates")
        build({"evidence_bundle": _anchored_bundle(), "claims": [{
            "predicate": "heraldry.blazon", "record_key": "rk-1", "observation_ids": ["obs-1"], "value": "tre roser",
        }]}, source_id=1939, extraction_run_id="run-1")


def test_profile_clause_rules_are_validated(tmp_path):
    payload = json.loads(evidence_extract.PROFILES.read_text(encoding="utf-8"))
    profile = payload["profiles"]["daa-2018-20-v1"]
    assert profile["version"] != "1.0.0"          # bumpet; præcis værdi pinnes ikke (Task 5 kan give 1.2.0)
    rules = profile["clause_rules"]
    assert rules["version"].startswith("clause-rules-2018-20-v")
    assert set(rules) == {"version", "terminators", "non_terminal_abbreviations", "initial_pattern",
                          "ordinal_number_pattern", "structural_header_patterns", "min_clause_chars",
                          "gap_charset", "intraword_chars"}
    broken = json.loads(json.dumps(payload))
    del broken["profiles"]["daa-2018-20-v1"]["clause_rules"]["gap_charset"]
    path = tmp_path / "profiles.json"
    path.write_text(json.dumps(broken), encoding="utf-8")
    with pytest.raises(evidence_extract.ExtractionError, match="EXTRACTION_CLAUSE_RULES_INVALID"):
        evidence_extract.load_profile("daa-2018-20-v1", path)


def test_profile_v2_is_additive_and_leaves_v1_untouched():
    # #189: den nye regel kommer som en ny profil; den godkendte v1 bevares byte for
    # byte i betydning, så tidligere kørsler stadig kan reproduceres og hashes.
    payload = json.loads(evidence_extract.PROFILES.read_text(encoding="utf-8"))
    v1 = payload["profiles"]["daa-2018-20-v1"]
    v2 = payload["profiles"]["daa-2018-20-v2"]
    assert v1["version"] == "1.3.0"
    assert v1["clause_rules"]["version"] == "clause-rules-2018-20-v2"
    assert "section_numeral_pattern" not in v1["clause_rules"]
    assert v2["version"] != v1["version"]
    assert v2["clause_rules"]["version"] == "clause-rules-2018-20-v3"
    assert v2["requires_human_go_for_change"] is True
    assert "abbreviation_match" not in v1["clause_rules"]
    # Review 35, P3: v2 tilføjer opslag uden hensyn til store/små bogstaver og tre
    # forkortelser — additivt, v1's liste står uændret som præfiks.
    assert v2["clause_rules"]["abbreviation_match"] == "case_insensitive"
    nta1, nta2 = (v["clause_rules"]["non_terminal_abbreviations"] for v in (v1, v2))
    assert nta2 == nta1 + ["Sr.", "Pol.", "Jahrg."]
    strip = lambda rules: {k: v for k, v in rules.items()
                           if k not in ("version", "section_numeral_pattern", "abbreviation_match",
                                        "non_terminal_abbreviations")}
    assert strip(v2["clause_rules"]) == strip(v1["clause_rules"])
    assert {k: v for k, v in v2.items() if k not in ("version", "clause_rules")} == \
           {k: v for k, v in v1.items() if k not in ("version", "clause_rules")}
    loaded = load_profile("daa-2018-20-v2")
    assert loaded["clause_rules"]["section_numeral_pattern"]


def test_section_numeral_pattern_is_optional_but_validated(tmp_path):
    payload = json.loads(evidence_extract.PROFILES.read_text(encoding="utf-8"))
    path = tmp_path / "profiles.json"
    broken = json.loads(json.dumps(payload))
    broken["profiles"]["daa-2018-20-v2"]["clause_rules"]["section_numeral_pattern"] = "(["
    path.write_text(json.dumps(broken), encoding="utf-8")
    with pytest.raises(ExtractionError, match="EXTRACTION_CLAUSE_RULES_INVALID"):
        load_profile("daa-2018-20-v2", path)
    broken["profiles"]["daa-2018-20-v2"]["clause_rules"]["section_numeral_pattern"] = ""
    path.write_text(json.dumps(broken), encoding="utf-8")
    with pytest.raises(ExtractionError, match="EXTRACTION_CLAUSE_RULES_INVALID"):
        load_profile("daa-2018-20-v2", path)
    broken["profiles"]["daa-2018-20-v2"]["clause_rules"]["section_numeral_pattern"] = "^[IVX]{1,4}\\.$"
    broken["profiles"]["daa-2018-20-v2"]["clause_rules"]["ukendt_noegle"] = "x"
    path.write_text(json.dumps(broken), encoding="utf-8")
    with pytest.raises(ExtractionError, match="EXTRACTION_CLAUSE_RULES_INVALID"):
        load_profile("daa-2018-20-v2", path)


def test_predicates_come_from_generated_file():
    assert "person.birth" in evidence_extract.ALLOWED_PREDICATES
    assert "life_event.birth" not in evidence_extract.ALLOWED_PREDICATES
    assert evidence_extract.predicate_kind("event.marriage") == "event"
    assert evidence_extract.predicate_kind("relation.marriage") == "relation"
    assert evidence_extract.predicate_kind("mention.place") == "mention"
    assert evidence_extract.predicate_kind("person.title") == "property"


@pytest.mark.parametrize("predicate,value,ok", [
    ("person.birth", "12. maj 1801", True),
    ("person.birth", {"raw": "12. maj 1801"}, False),
    ("person.name_part", {"raw": "Bravo", "normalized": "Bravo"}, True),
    ("person.name_part", "Bravo", False),
    ("event.marriage", {"raw": "Gift 1830 m. Charlie", "date_raw": "1830", "participants": []}, True),
    ("event.marriage", {"normalized": "x"}, False),
])
def test_claim_value_form_follows_value_kind(predicate, value, ok):
    if ok:
        evidence_extract.validate_claim_value(predicate, value)
    else:
        with pytest.raises(evidence_extract.ExtractionError, match="EXTRACTION_CLAIM_VALUE_INVALID"):
            evidence_extract.validate_claim_value(predicate, value)


def test_interpretation_schema_defines_all_six_value_forms():
    """#147 4.2: skemaet skal kende de seks værdiformer, tabellen kan udtrykke."""
    import json as _json
    from pathlib import Path as _Path
    schema = _json.loads((_Path(evidence_extract.PREDICATES_FILE).parent / "interpretation-schema.json").read_text(encoding="utf-8"))
    assert schema["$id"].endswith("evidence-interpretation-1.1.json")
    assert set(schema["$defs"]) == {"text", "date_raw", "name", "event", "relation", "mention"}
    # Enhver værdiform i den genererede fil skal have et skema.
    kinds = {row["value_kind"] for row in _json.loads(_Path(evidence_extract.PREDICATES_FILE).read_text(encoding="utf-8"))["predicates"]}
    assert kinds <= set(schema["$defs"])


def test_1939_profile_clause_rules_and_optional_page_keys(tmp_path):
    profile = evidence_extract.load_profile("daa-1939-v1")
    assert profile["version"] == "1.2.0"
    rules = profile["clause_rules"]
    assert rules["version"] == "clause-rules-1939-v1"
    assert rules["gap_charset"] == [" ", "\n"]
    assert rules["terminators"] == [". ", "; ", ".\n", ";\n"]
    assert rules["page_marker_pattern"] == r"^###\s*PAGE\s+\d+\s*###\s*$"
    assert profile["text_form"] == "raw" and profile["helpost_observation_kind"] == "person"
    # nøglerne er valgfri: uden dem er reglerne stadig gyldige
    bare = {k: v for k, v in rules.items() if k not in ("page_marker_pattern", "possible_layout_line_pattern")}
    evidence_extract.validate_clause_rules(bare)
    for key in ("page_marker_pattern", "possible_layout_line_pattern"):
        for bad in ("([", "", 5):
            with pytest.raises(ExtractionError, match="CLAUSE_RULES_INVALID"):
                evidence_extract.validate_clause_rules(dict(rules, **{key: bad}))
