"""Acceptance tests for the edition-neutral evidence extraction contract."""

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
        source_record_occurrences=[occurrence(), second_occurrence],
        source_record_anchor_events=[
            RecordAnchorEvent("anchor-1", "occurrence-1", "record-1", "accepted", 1),
            RecordAnchorEvent("anchor-2", "occurrence-2", "record-1", "accepted", 1),
        ],
    )
    assert validate_bundle(bundle) is None


def test_occurrence_has_at_most_one_accepted_record_anchor():
    bundle = evidence_bundle(
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
