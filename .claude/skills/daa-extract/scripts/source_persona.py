"""Fail-closed kandidater mellem kildepersona og kanonisk person.

En kandidat er aldrig en merge. Den er et revisionsbart forslag, som først kan
promoveres af en særskilt, versionsstyret beslutning i identitetslaget.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Literal, Mapping, Sequence

from identitetsregister import record_provenance_key


IdentityAction = Literal["same", "different", "unresolved"]
POLICY_VERSION = "source-persona-v1"


@dataclass(frozen=True)
class IdentityCandidate:
    source_persona_id: str
    canonical_person_id: str
    evidence_ids: tuple[str, ...]
    contradictions: tuple[str, ...]
    score_components: Mapping[str, float]
    proposed_action: IdentityAction


@dataclass(frozen=True)
class ManualIdentityDecision:
    source_persona_id: str
    record_key: str
    external_person_number: str | None
    canonical_person_id: str
    action: IdentityAction


def _has_anchor(evidence_ids: Sequence[str], prefix: str) -> bool:
    return any(
        value.startswith(prefix) and bool(value[len(prefix):].strip())
        for value in evidence_ids
    )


def evaluate_candidate(candidate: IdentityCandidate) -> IdentityCandidate:
    """Rangér uden at gætte.

    Den bevidst smalle v1-policy kræver to uafhængige, positive ankre: ægtefælle
    og dato. Navnelighed er kun en scorekomponent og kan aldrig alene acceptere.
    """
    if candidate.contradictions:
        return replace(candidate, proposed_action="unresolved")
    if _has_anchor(candidate.evidence_ids, "spouse:") and _has_anchor(candidate.evidence_ids, "date:"):
        return replace(candidate, proposed_action="same")
    return replace(candidate, proposed_action="unresolved")


def enforce_global_injectivity(candidates: Sequence[IdentityCandidate]) -> list[IdentityCandidate]:
    """Tillad højst én automatisk same-kandidat pr. kanonisk person.

    Konflikter bliver uafklarede for alle implicerede personaer; en stabil
    sortering eller score må ikke afgøre identitet ved lighed.
    """
    evaluated = [evaluate_candidate(candidate) for candidate in candidates]
    same_person_counts: dict[str, int] = {}
    same_persona_counts: dict[str, int] = {}
    for candidate in evaluated:
        if candidate.proposed_action == "same":
            same_person_counts[candidate.canonical_person_id] = same_person_counts.get(candidate.canonical_person_id, 0) + 1
            same_persona_counts[candidate.source_persona_id] = same_persona_counts.get(candidate.source_persona_id, 0) + 1
    return [
        replace(candidate, proposed_action="unresolved")
        if candidate.proposed_action == "same" and (
            same_person_counts[candidate.canonical_person_id] > 1
            or same_persona_counts[candidate.source_persona_id] > 1
        )
        else candidate
        for candidate in evaluated
    ]


def remap_manual_decisions(
    decisions: Sequence[ManualIdentityDecision],
    new_personas: Sequence[Mapping[str, object]],
) -> tuple[list[ManualIdentityDecision], list[ManualIdentityDecision]]:
    """Genknyt kun en manuel afgørelse ved præcis, entydig record-provenance."""
    by_provenance: dict[tuple[str, str | None], list[str]] = {}
    for persona in new_personas:
        key = record_provenance_key(
            persona.get("record_key"), persona.get("external_person_number"),
        )
        persona_id = persona.get("source_persona_id")
        if not isinstance(persona_id, str) or not persona_id:
            raise ValueError("source_persona_id kræves for remapping")
        by_provenance.setdefault(key, []).append(persona_id)

    remapped: list[ManualIdentityDecision] = []
    unresolved: list[ManualIdentityDecision] = []
    same_targets_by_provenance: dict[tuple[str, str | None], set[str]] = {}
    for decision in decisions:
        if decision.action == "same":
            key = record_provenance_key(decision.record_key, decision.external_person_number)
            same_targets_by_provenance.setdefault(key, set()).add(decision.canonical_person_id)
    for decision in decisions:
        key = record_provenance_key(decision.record_key, decision.external_person_number)
        targets = by_provenance.get(key, [])
        if len(targets) != 1 or len(same_targets_by_provenance.get(key, set())) > 1:
            unresolved.append(decision)
            continue
        remapped.append(replace(decision, source_persona_id=targets[0]))
    return remapped, unresolved
