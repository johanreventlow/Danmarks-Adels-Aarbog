from source_persona import (
    IdentityCandidate,
    ManualIdentityDecision,
    evaluate_candidate,
    enforce_global_injectivity,
    remap_manual_decisions,
)


def candidate(persona, person, *, evidence=(), contradictions=(), scores=(), proposed_action="unresolved"):
    return IdentityCandidate(
        source_persona_id=persona,
        canonical_person_id=person,
        evidence_ids=tuple(evidence),
        contradictions=tuple(contradictions),
        score_components=dict(scores),
        proposed_action=proposed_action,
    )


def test_same_name_without_positive_anchor_stays_unresolved():
    result = evaluate_candidate(candidate("persona-a", "person-1", scores=(("name", 1.0),)))
    assert result.proposed_action == "unresolved"


def test_spouse_and_date_anchor_can_propose_same_when_contradiction_free():
    result = evaluate_candidate(candidate(
        "persona-a", "person-1",
        evidence=("spouse:reventlow-42", "date:1840-01-01"),
        scores=(("spouse", 1.0), ("date", 1.0)),
    ))
    assert result.proposed_action == "same"


def test_conflicting_printed_person_number_blocks_automatic_same():
    result = evaluate_candidate(candidate(
        "persona-a", "person-1", evidence=("person_number:17",),
        contradictions=("person_number:18",), scores=(("person_number", 1.0),),
    ))
    assert result.proposed_action == "unresolved"


def test_global_injectivity_parks_two_personas_claiming_same_person():
    resolved = enforce_global_injectivity([
        evaluate_candidate(candidate("persona-a", "person-1", evidence=("spouse:a",))),
        evaluate_candidate(candidate("persona-b", "person-1", evidence=("spouse:b",))),
    ])
    assert {item.proposed_action for item in resolved} == {"unresolved"}


def test_global_injectivity_parks_one_persona_claiming_two_people():
    resolved = enforce_global_injectivity([
        evaluate_candidate(candidate("persona-a", "person-1", evidence=("spouse:a", "date:1840"))),
        evaluate_candidate(candidate("persona-a", "person-2", evidence=("spouse:b", "date:1841"))),
    ])
    assert {item.proposed_action for item in resolved} == {"unresolved"}


def test_empty_anchor_values_never_propose_same():
    result = evaluate_candidate(candidate("persona-a", "person-1", evidence=("spouse:", "date:")))
    assert result.proposed_action == "unresolved"


def test_direct_same_input_is_revalidated_by_global_gate():
    resolved = enforce_global_injectivity([
        candidate("persona-a", "person-1", proposed_action="same"),
    ])
    assert resolved[0].proposed_action == "unresolved"


def test_one_persona_can_retain_multiple_source_mentions_without_canonical_merge():
    first = evaluate_candidate(candidate("persona-a", "person-1", evidence=("record:one",)))
    second = evaluate_candidate(candidate("persona-a", "person-2", evidence=("record:two",)))
    assert first.source_persona_id == second.source_persona_id
    assert {first.canonical_person_id, second.canonical_person_id} == {"person-1", "person-2"}
    assert first.proposed_action == second.proposed_action == "unresolved"


def test_manual_decision_survives_reextract_only_via_record_provenance():
    prior = ManualIdentityDecision(
        source_persona_id="old-persona", record_key="1939:reventlow:42",
        external_person_number="17", canonical_person_id="person-1", action="same",
    )
    remapped, unresolved = remap_manual_decisions(
        [prior],
        [{"source_persona_id": "new-persona", "record_key": "1939:reventlow:42", "external_person_number": "17"}],
    )
    assert remapped == [ManualIdentityDecision(
        source_persona_id="new-persona", record_key="1939:reventlow:42",
        external_person_number="17", canonical_person_id="person-1", action="same",
    )]
    assert unresolved == []


def test_manual_decision_is_parked_when_record_provenance_is_ambiguous():
    prior = ManualIdentityDecision("old", "1939:reventlow:42", "17", "person-1", "same")
    remapped, unresolved = remap_manual_decisions(
        [prior],
        [
            {"source_persona_id": "new-a", "record_key": "1939:reventlow:42", "external_person_number": "17"},
            {"source_persona_id": "new-b", "record_key": "1939:reventlow:42", "external_person_number": "17"},
        ],
    )
    assert remapped == []
    assert unresolved == [prior]


def test_conflicting_historical_manual_same_decisions_are_both_parked():
    first = ManualIdentityDecision("old-a", "1939:reventlow:42", "17", "person-1", "same")
    second = ManualIdentityDecision("old-b", "1939:reventlow:42", "17", "person-2", "same")
    remapped, unresolved = remap_manual_decisions(
        [first, second],
        [{"source_persona_id": "new", "record_key": "1939:reventlow:42", "external_person_number": "17"}],
    )
    assert remapped == []
    assert unresolved == [first, second]
