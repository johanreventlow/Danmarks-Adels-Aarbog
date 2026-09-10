"""Acceptance tests for the edition-neutral evidence extraction contract."""

import hashlib
import json
import re
from pathlib import Path

import pytest

from evidence_contract import (
    ContractError,
    Interpretation,
    Mention,
    Observation,
    RecordAnchorEvent,
    RecordOccurrence,
    RecordPlacement,
    RevisionEvent,
    SourcePersona,
    SourceSpan,
    mint_record_key,
    validate_bundle,
)


def interpretation_table_status_values(schema_sql):
    table = re.search(
        r"CREATE TABLE private\.interpretation\s*\((.*?)\n\);\s*"
        r"CREATE TABLE private\.interpretation_observation",
        schema_sql,
        re.DOTALL,
    )
    assert table is not None
    status_check = re.search(
        r"\bstatus\s+text\s+NOT NULL\s+CHECK\s*\(\s*"
        r"status\s+IN\s*\(([^)]*)\)\s*\)",
        table.group(1),
        re.DOTALL,
    )
    assert status_check is not None
    return re.findall(r"'([^']+)'", status_check.group(1))


def span(text="Gift 12. Maj 1814 med Anna."):
    return SourceSpan(
        rendition_id="rendition-2018-pdftext-v1",
        page_from=101,
        page_to=101,
        column_label="a",
        char_from=0,
        char_to=len(text),
        source_text=text,
        bbox=None,
    )


def observation(text="Gift 12. Maj 1814 med Anna."):
    return Observation(
        observation_id="obs-marriage-1",
        occurrence_id="occurrence-1",
        kind="marriage_clause",
        verbatim_text=text,
        span=span(text),
        extraction_method="deterministic",
        extraction_run_id="run-1",
    )


def occurrence(rendition_id="rendition-2018-pdftext-v1"):
    return RecordOccurrence(
        occurrence_id="occurrence-1",
        rendition_id=rendition_id,
        extraction_run_id="run-1",
        span=span(),
        verbatim_text="Gift 12. Maj 1814 med Anna.",
    )


def evidence_bundle(**overrides):
    bundle = {
        "schema_version": "1.0",
        "source_rendition": [],
        "source_records": [],
        "source_record_occurrences": [occurrence()],
        "source_record_anchor_events": [],
        "source_record_revision_events": [],
        "record_placements": [],
        "persona_placements": [],
        "observations": [observation()],
        "text_variants": [],
        "mentions": [],
        "source_personas": [],
        "extraction_run": {"run_id": "run-1"},
        "interpretations": [],
    }
    bundle.update(overrides)
    return bundle


def linked_bundle():
    rendition_text = "Forord. Anna blev født 1801. Efterskrift."
    occurrence_text = "Anna blev født 1801."
    occurrence_from = rendition_text.index(occurrence_text)
    occurrence_to = occurrence_from + len(occurrence_text)
    observation_text = "Anna"
    observation_from = rendition_text.index(observation_text)
    observation_to = observation_from + len(observation_text)
    return {
        "schema_version": "1.1",
        "source_rendition": [{
            "rendition_id": "rendition-2018-pdftext-v1",
            "source_id": "2018-20",
            "sha256": hashlib.sha256(rendition_text.encode("utf-8")).hexdigest(),
            "verbatim_text": rendition_text,
        }],
        "source_records": [{
            "id": "record-1",
            "record_key": "rk-1",
            "source_id": "2018-20",
        }],
        "source_record_occurrences": [{
            "occurrence_id": "occurrence-1",
            "rendition_id": "rendition-2018-pdftext-v1",
            "extraction_run_id": "run-1",
            "verbatim_text": occurrence_text,
            "span": {
                "rendition_id": "rendition-2018-pdftext-v1",
                "page_from": 1,
                "page_to": 1,
                "column_label": None,
                "char_from": occurrence_from,
                "char_to": occurrence_to,
            },
        }],
        "source_record_anchor_events": [{
            "event_id": "anchor-1",
            "occurrence_id": "occurrence-1",
            "source_record_id": "record-1",
            "decision_status": "accepted",
            "version": 1,
        }],
        "source_record_revision_events": [],
        "record_placements": [],
        "persona_placements": [],
        "observations": [{
            "observation_id": "obs-1",
            "occurrence_id": "occurrence-1",
            "kind": "person_name",
            "verbatim_text": observation_text,
            "span": {
                "rendition_id": "rendition-2018-pdftext-v1",
                "page_from": 1,
                "page_to": 1,
                "column_label": None,
                "char_from": observation_from,
                "char_to": observation_to,
            },
            "extraction_method": "deterministic",
            "extraction_run_id": "run-1",
        }],
        "text_variants": [],
        "mentions": [{
            "mention_id": "mention-1",
            "observation_id": "obs-1",
            "char_from": 0,
            "char_to": len(observation_text),
            "verbatim_text": observation_text,
        }],
        "source_personas": [{
            "persona_id": "persona-1",
            "source_id": "2018-20",
            "mention_ids": ["mention-1"],
        }],
        "extraction_run": {"run_id": "run-1"},
        "interpretations": [],
    }


def source_record(record_id, record_key):
    return {"id": record_id, "record_key": record_key}


def test_observation_requires_exact_source_span():
    with pytest.raises(ContractError, match="verbatim"):
        Observation(
            observation_id="obs-1",
            occurrence_id="occurrence-1",
            kind="marriage_clause",
            verbatim_text="Gift 1814 med Anna.",
            span=span(),
            extraction_method="deterministic",
            extraction_run_id="run-1",
        )


def test_normalized_text_cannot_replace_verbatim_text():
    source = "Gift med A\u030aase."
    with pytest.raises(ContractError, match="verbatim"):
        Observation(
            observation_id="obs-1",
            occurrence_id="occurrence-1",
            kind="marriage_clause",
            verbatim_text="Gift med Åase.",
            span=span(source),
            extraction_method="ocr",
            extraction_run_id="run-1",
        )


def test_mention_offsets_must_be_inside_observation():
    with pytest.raises(ContractError, match="mention"):
        Mention(
            mention_id="mention-anna",
            observation_id="obs-marriage-1",
            char_from=0,
            char_to=100,
            verbatim_text="Anna",
        ).validate_against(observation())


def test_source_persona_is_scoped_to_one_source_edition():
    with pytest.raises(ContractError, match="source"):
        SourcePersona(
            persona_id="persona-anna",
            source_id="source-2018",
            mention_ids=("mention-anna",),
            occurrence_source_ids=("source-2018", "source-1939"),
        ).validate()


def test_record_key_is_minted_opaque_and_not_from_layout_or_name():
    first = mint_record_key()
    second = mint_record_key()
    assert first != second
    assert "Anna" not in first
    assert "101" not in first


def test_occurrence_can_remain_unanchored_without_data_loss():
    assert validate_bundle(evidence_bundle()) is None


def test_bundle_rejects_anchor_to_unknown_source_record():
    bundle = evidence_bundle(
        source_record_anchor_events=[
            RecordAnchorEvent("anchor-1", "occurrence-1", "missing-record", "accepted", 1),
        ],
    )
    with pytest.raises(ContractError, match="unknown source record"):
        validate_bundle(bundle)


def test_bundle_rejects_duplicate_source_record_key():
    bundle = evidence_bundle(source_records=[
        source_record("record-1", "record-same"),
        source_record("record-2", "record-same"),
    ])
    with pytest.raises(ContractError, match="duplicate source record key"):
        validate_bundle(bundle)


def test_two_renditions_can_map_to_one_logical_record():
    second_occurrence = RecordOccurrence(
        occurrence_id="occurrence-2",
        rendition_id="rendition-2018-corrected-v2",
        extraction_run_id="run-2",
        span=SourceSpan(
            rendition_id="rendition-2018-corrected-v2",
            page_from=101,
            page_to=101,
            column_label="a",
            char_from=0,
            char_to=len("Gift 12. Maj 1814 med Anna."),
            source_text="Gift 12. Maj 1814 med Anna.",
            bbox=None,
        ),
        verbatim_text="Gift 12. Maj 1814 med Anna.",
    )
    bundle = evidence_bundle(
        source_records=[source_record("record-1", "record-key-1")],
        source_record_occurrences=[occurrence(), second_occurrence],
        source_record_anchor_events=[
            RecordAnchorEvent("anchor-1", "occurrence-1", "record-1", "accepted", 1),
            RecordAnchorEvent("anchor-2", "occurrence-2", "record-1", "accepted", 1),
        ],
    )
    assert validate_bundle(bundle) is None


def test_occurrence_has_at_most_one_accepted_record_anchor():
    bundle = evidence_bundle(
        source_records=[
            source_record("record-1", "record-key-1"),
            source_record("record-2", "record-key-2"),
        ],
        source_record_anchor_events=[
            RecordAnchorEvent("anchor-1", "occurrence-1", "record-1", "accepted", 1),
            RecordAnchorEvent("anchor-2", "occurrence-1", "record-2", "accepted", 1),
        ],
    )
    with pytest.raises(ContractError, match="accepted"):
        validate_bundle(bundle)


def test_split_or_merge_requires_reviewed_revision_events():
    with pytest.raises(ContractError, match="review"):
        RevisionEvent(
            event_id="revision-1",
            predecessor_record_id="record-old",
            successor_record_id="record-new",
            relation_kind="split_into",
            decision_status="accepted",
            version=1,
            reviewed_by=None,
        ).validate()


def test_interpretation_requires_observation_ids():
    with pytest.raises(ContractError, match="observation"):
        Interpretation(
            interpretation_id="int-1",
            observation_ids=(),
            predicate="marriage.date",
            value="1814-05-12",
            status="proposed",
            method="deterministic",
        ).validate()


def test_unknown_and_absent_are_distinct():
    assert Interpretation.unknown_value() != Interpretation.absent_value()


def test_confidence_is_not_an_identity_decision():
    with pytest.raises(ContractError, match="identity"):
        Interpretation(
            interpretation_id="int-1",
            observation_ids=("obs-marriage-1",),
            predicate="person.identity",
            value="person-123",
            status="accepted",
            method="model",
            confidence=1.0,
        ).validate()


def test_observed_record_placement_requires_header_observation():
    with pytest.raises(ContractError, match="header"):
        RecordPlacement(
            record_key="record-1",
            scheme_entry_id="scheme-entry-1",
            printed_number="12",
            generation_local=3,
            generation_global=None,
            generation_label_raw="Tredje Slægtled",
            kuld_label=None,
            header_observation_id=None,
        ).validate()


def test_source_span_rejects_negative_or_reversed_offsets():
    with pytest.raises(ContractError, match="character span"):
        SourceSpan(
            rendition_id="rendition-1",
            page_from=1,
            page_to=1,
            column_label=None,
            char_from=4,
            char_to=3,
            source_text="tekst",
            bbox=None,
        ).validate()


def test_bundle_rejects_unknown_top_level_fields():
    bundle = evidence_bundle(invented_field=True)
    with pytest.raises(ContractError, match="unknown"):
        validate_bundle(bundle)


def test_bundle_rejects_duplicate_occurrence_ids():
    bundle = evidence_bundle(source_record_occurrences=[occurrence(), occurrence()])
    with pytest.raises(ContractError, match="duplicate occurrence"):
        validate_bundle(bundle)


def test_bundle_rejects_observation_outside_its_occurrence():
    bundle = linked_bundle()
    bundle["observations"][0]["span"].update(char_from=0, char_to=4)
    bundle["observations"][0]["verbatim_text"] = "Foro"
    with pytest.raises(ContractError, match="inside its occurrence"):
        validate_bundle(bundle)


def test_bundle_rejects_unknown_nested_mention_field():
    bundle = linked_bundle()
    bundle["mentions"][0]["invented"] = True
    with pytest.raises(ContractError, match="unknown mention fields"):
        validate_bundle(bundle)


def test_bundle_rejects_rendition_hash_drift():
    bundle = linked_bundle()
    bundle["source_rendition"][0]["sha256"] = "0" * 64
    with pytest.raises(ContractError, match="rendition sha256"):
        validate_bundle(bundle)


def test_interpretation_cannot_reference_unknown_observation():
    bundle = evidence_bundle(
        interpretations=[
            Interpretation("int-1", ("missing-observation",), "marriage.date", "1814-05-12", "proposed", "model"),
        ],
    )
    with pytest.raises(ContractError, match="unknown observation"):
        validate_bundle(bundle)


def test_synthetic_fixture_obeys_contract_shape():
    fixture = Path(__file__).parent / "tests" / "fixtures" / "evidence-observation.synthetic.json"
    assert fixture.is_file()
    validate_bundle(fixture)


def test_json_schemas_use_the_current_interpretation_status_vocabulary():
    references = Path(__file__).parent.parent / "references"
    for filename in ("observation-schema.json", "interpretation-schema.json"):
        with (references / filename).open(encoding="utf-8") as handle:
            schema = json.load(handle)
        assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"

    with (references / "interpretation-schema.json").open(encoding="utf-8") as handle:
        interpretation_schema = json.load(handle)
    schema_sql = (Path(__file__).parents[4] / "schema.sql").read_text(encoding="utf-8")
    assert interpretation_schema["properties"]["status"]["enum"] == (
        interpretation_table_status_values(schema_sql)
    )


def test_interpretation_status_vocabulary_comes_from_table_not_rpc_body():
    schema_sql = """
CREATE TABLE private.interpretation (
  status text NOT NULL CHECK (status IN ('proposed','accepted'))
);
CREATE TABLE private.interpretation_observation (
  interpretation_id uuid NOT NULL
);
CREATE FUNCTION red_decide_interpretation(p_decision_status text) RETURNS void AS $$
BEGIN
  IF p_decision_status NOT IN ('accepted','rejected','unresolved','superseded') THEN
    RAISE EXCEPTION 'invalid';
  END IF;
END $$ LANGUAGE plpgsql;
"""
    assert interpretation_table_status_values(schema_sql) == ["proposed", "accepted"]


def _clause_bundle():
    """linked_bundle() + en helpost 'obs-post' over hele occurrence-teksten, schema 1.2."""
    bundle = json.loads(json.dumps(linked_bundle()))
    bundle["schema_version"] = "1.2"
    occ = bundle["source_record_occurrences"][0]
    bundle["observations"].append({
        "observation_id": "obs-post", "occurrence_id": "occurrence-1", "kind": "person_post",
        "verbatim_text": occ["verbatim_text"], "span": dict(occ["span"]),
        "extraction_method": "deterministic", "extraction_run_id": "run-1",
    })
    return bundle


def _clause(bundle, ordinal, rel_from, rel_to, classification="record_text", flags=()):
    parent = next(o for o in bundle["observations"] if o["observation_id"] == "obs-post")
    base = parent["span"]["char_from"]
    text = parent["verbatim_text"][rel_from:rel_to]
    return {
        "observation_id": f"obs-post-c{ordinal}", "occurrence_id": parent["occurrence_id"], "kind": "clause",
        "verbatim_text": text,
        "span": {**parent["span"], "char_from": base + rel_from, "char_to": base + rel_to},
        "extraction_method": "clause_segment_v1", "extraction_run_id": parent["extraction_run_id"],
        "parent_observation_id": "obs-post", "clause_ordinal": ordinal,
        "clause_classification": classification, "clause_flags": list(flags),
    }


def test_bundle_1_2_accepts_clause_under_parent():
    bundle = _clause_bundle()
    bundle["observations"].append(_clause(bundle, 1, 0, 9))   # "Anna blev"
    bundle["observations"].append(_clause(bundle, 2, 10, 20))  # "født 1801."
    validate_bundle(bundle)


def test_bundle_1_1_rejects_clause_fields():
    bundle = _clause_bundle()
    bundle["schema_version"] = "1.1"
    bundle["observations"].append(_clause(bundle, 1, 0, 9))
    with pytest.raises(ContractError):  # _exact_fields afviser de ukendte felter i strict 1.1
        validate_bundle(bundle)


def test_bundle_1_2_rejects_clause_without_parent():
    bundle = _clause_bundle()
    clause = _clause(bundle, 1, 0, 9)
    clause["parent_observation_id"] = "obs-missing"
    bundle["observations"].append(clause)
    with pytest.raises(ContractError, match="clause requires parent"):
        validate_bundle(bundle)


def test_bundle_1_2_rejects_span_outside_parent():
    # Klausulen "Anna blev" (occurrence-relativ 0-9) ligger inde i occurrencen, men peger på obs-1
    # ("Anna", 0-4) som forælder: gyldig som observation, ugyldig som klausul under obs-1.
    bundle = _clause_bundle()
    clause = _clause(bundle, 1, 0, 9)
    clause["parent_observation_id"] = "obs-1"
    bundle["observations"].append(clause)
    with pytest.raises(ContractError, match="clause span outside parent"):
        validate_bundle(bundle)


def test_bundle_1_2_rejects_parent_that_is_itself_a_clause():
    bundle = _clause_bundle()
    first = _clause(bundle, 1, 0, 9)
    second = _clause(bundle, 2, 10, 20)
    second["parent_observation_id"] = first["observation_id"]
    bundle["observations"] += [first, second]
    with pytest.raises(ContractError, match="parent observation must be top level"):
        validate_bundle(bundle)


def test_observation_level_clause_invariants():
    # Observation.validate() fanger selv tekst ≠ span og ulovlige klausulfelter, før bundle-niveauet.
    bundle = _clause_bundle()
    clause = _clause(bundle, 1, 0, 9)
    clause["clause_classification"] = "layout"
    bundle["observations"].append(clause)
    with pytest.raises(ContractError, match="unknown clause classification"):
        validate_bundle(bundle)
    post = next(o for o in bundle["observations"] if o["observation_id"] == "obs-post")
    post["parent_observation_id"] = "obs-1"
    with pytest.raises(ContractError, match="clause fields are only allowed on kind clause"):
        validate_bundle(bundle)
