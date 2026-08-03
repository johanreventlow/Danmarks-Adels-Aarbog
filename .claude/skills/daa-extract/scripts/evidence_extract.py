#!/usr/bin/env python3
"""Pinned, resumable orchestration for granular source-evidence extraction.

This module deliberately does not call a model.  It records the immutable input
and model contract that an approved runner must honour, so ambient settings can
never silently change an extraction run or make a partial batch mergeable.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Mapping, Sequence

from evidence_contract import ContractError, validate_bundle


class ExtractionError(ValueError):
    pass


ROOT = Path(__file__).resolve().parents[4]
PROFILES = ROOT / ".claude/skills/daa-extract/references/extraction-profiles.json"
ALLOWED_MODELS = {"gpt-5.6-terra", "gpt-5.6-sol"}
# Kategorierne er editionsneutrale: de beskriver hvad en bog kan hævde, ikke
# hvordan én bestemt slægt eller OCR-profil skal repareres.
CLAIM_FAMILIES = {
    "person", "life_event", "relationship", "title", "form_of_address", "rank", "office",
    "education", "estate", "residence", "military_service", "honour", "publication",
    "lineage", "genealogy", "heraldry", "image", "reference",
}


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sha(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def load_profile(profile_id: str, path: Path = PROFILES) -> Mapping[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    profile = payload.get("profiles", {}).get(profile_id)
    required = {"edition", "version", "model_id", "escalation_model_id", "prompt_version", "layout", "record_identity"}
    if payload.get("schema_version") != "1.0" or not isinstance(profile, dict) or required - set(profile):
        raise ExtractionError("EXTRACTION_PROFILE_INVALID")
    if profile["model_id"] != "gpt-5.6-terra" or profile["escalation_model_id"] != "gpt-5.6-sol":
        raise ExtractionError("EXTRACTION_MODEL_POLICY_INVALID")
    if not all(isinstance(profile[key], str) and profile[key].strip() for key in required):
        raise ExtractionError("EXTRACTION_PROFILE_INVALID")
    return {"profile_id": profile_id, **profile}


@dataclass(frozen=True)
class BatchManifest:
    profile_id: str
    profile_version: str
    effective_model_id: str
    prompt_version: str
    record_keys: tuple[str, ...]
    input_hash: str
    extraction_version: str
    escalation_reason: str | None
    output_hash: str | None = None
    token_count: int | None = None
    cost_usd: float | None = None
    validation_status: str = "pending"

    def validate(self) -> None:
        if (not self.record_keys or len(self.record_keys) != len(set(self.record_keys))
                or any(not key.strip() for key in self.record_keys)):
            raise ExtractionError("EXTRACTION_RECORD_KEYS_INVALID")
        if self.effective_model_id not in ALLOWED_MODELS or not self.prompt_version:
            raise ExtractionError("EXTRACTION_MODEL_OR_PROMPT_REQUIRED")
        if self.effective_model_id == "gpt-5.6-sol" and not self.escalation_reason:
            raise ExtractionError("EXTRACTION_ESCALATION_GATE_REQUIRED")
        if self.effective_model_id == "gpt-5.6-terra" and self.escalation_reason:
            raise ExtractionError("EXTRACTION_ESCALATION_REASON_INVALID")
        if self.validation_status not in {"pending", "green", "rejected"}:
            raise ExtractionError("EXTRACTION_VALIDATION_STATUS_INVALID")
        if self.validation_status == "green" and (not self.output_hash or self.token_count is None or self.cost_usd is None):
            raise ExtractionError("EXTRACTION_GREEN_ACCOUNTING_REQUIRED")


def prepare_batch(profile_id: str, records: Sequence[Mapping[str, Any]], *, extraction_version: str,
                  escalate: bool = False, escalation_reason: str | None = None) -> BatchManifest:
    """Create a deterministic manifest without reading model-related environment/settings."""
    profile = load_profile(profile_id)
    record_keys = tuple(str(record.get("record_key", "")).strip() for record in records)
    model = profile["escalation_model_id"] if escalate else profile["model_id"]
    manifest = BatchManifest(profile_id, profile["version"], model, profile["prompt_version"], record_keys,
                             _sha(records), extraction_version, escalation_reason)
    manifest.validate()
    return manifest


def complete_batch(manifest: BatchManifest, output: Mapping[str, Any], *, token_count: int, cost_usd: float) -> BatchManifest:
    """Only a wholly validated output can become a reusable green batch."""
    if token_count < 0 or cost_usd < 0:
        raise ExtractionError("EXTRACTION_ACCOUNTING_INVALID")
    if set(output.get("record_keys", ())) != set(manifest.record_keys) or output.get("partial") is True:
        raise ExtractionError("EXTRACTION_PARTIAL_OUTPUT")
    validate_output(output)
    completed = BatchManifest(**{**asdict(manifest), "output_hash": _sha(output), "token_count": token_count,
                                 "cost_usd": cost_usd, "validation_status": "green"})
    completed.validate()
    return completed


def validate_output(output: Mapping[str, Any]) -> None:
    """Validate granular claims without turning source claims into canonical facts.

    A batch without claims is permitted during structural extraction.  Once a
    claim exists, it must cite a valid evidence bundle; this deliberately makes
    it impossible to pass a model's free text directly into projection.
    """
    claims = output.get("claims", [])
    if not isinstance(claims, list):
        raise ExtractionError("EXTRACTION_CLAIMS_INVALID")
    if not claims:
        return
    bundle = output.get("evidence_bundle")
    if not isinstance(bundle, Mapping):
        raise ExtractionError("EXTRACTION_EVIDENCE_BUNDLE_REQUIRED")
    try:
        validate_bundle(bundle)
    except (ContractError, KeyError, TypeError, ValueError) as exc:
        raise ExtractionError("EXTRACTION_EVIDENCE_BUNDLE_INVALID") from exc
    observation_ids = {str(observation.get("observation_id", ""))
                       for observation in bundle.get("observations", []) if isinstance(observation, Mapping)}
    observation_occurrence = {str(observation.get("observation_id", "")): str(observation.get("occurrence_id", ""))
                              for observation in bundle.get("observations", []) if isinstance(observation, Mapping)}
    mention_observation = {str(mention.get("mention_id", mention.get("id", ""))): str(mention.get("observation_id", ""))
                           for mention in bundle.get("mentions", []) if isinstance(mention, Mapping)}
    anchored_occurrences = {str(anchor.get("occurrence_id", "")) for anchor in bundle.get("source_record_anchor_events", [])
                            if isinstance(anchor, Mapping) and anchor.get("decision_status") == "accepted"
                            and isinstance(anchor.get("source_record_id"), str) and anchor.get("source_record_id")}
    record_keys = {str(record.get("id", "")): str(record.get("record_key", ""))
                   for record in bundle.get("source_records", []) if isinstance(record, Mapping)}
    accepted_record_by_occurrence = {
        str(anchor.get("occurrence_id", "")): record_keys.get(str(anchor.get("source_record_id", "")), "")
        for anchor in bundle.get("source_record_anchor_events", []) if isinstance(anchor, Mapping)
        and anchor.get("decision_status") == "accepted"
    }
    persona_records = {}
    for persona in bundle.get("source_personas", []):
        if not isinstance(persona, Mapping):
            continue
        persona_id = str(persona.get("persona_id", persona.get("id", "")))
        mention_ids = persona.get("mention_ids", [])
        if not isinstance(mention_ids, list):
            continue
        persona_records[persona_id] = any(
            observation_occurrence.get(mention_observation.get(str(mention_id), ""), "") in anchored_occurrences
            for mention_id in mention_ids
        )
    for claim in claims:
        if not isinstance(claim, Mapping):
            raise ExtractionError("EXTRACTION_CLAIM_INVALID")
        predicate = claim.get("predicate")
        if not isinstance(predicate, str) or "." not in predicate or predicate.split(".", 1)[0] not in CLAIM_FAMILIES:
            raise ExtractionError("EXTRACTION_PREDICATE_INVALID")
        cited = claim.get("observation_ids")
        if not isinstance(cited, list) or not cited or any(not isinstance(value, str) or value not in observation_ids for value in cited):
            raise ExtractionError("EXTRACTION_OBSERVATION_REQUIRED")
        if "value" not in claim:
            raise ExtractionError("EXTRACTION_CLAIM_VALUE_REQUIRED")
        expected_keys = {accepted_record_by_occurrence.get(observation_occurrence[observation_id], "")
                         for observation_id in cited}
        record_key = claim.get("record_key")
        if (not isinstance(record_key, str) or not record_key.strip() or not expected_keys
                or "" in expected_keys or record_key not in expected_keys):
            raise ExtractionError("EXTRACTION_RECORD_KEY_REQUIRED")
        if predicate.startswith("person."):
            persona_id = claim.get("source_persona_id")
            if not isinstance(persona_id, str) or persona_id not in persona_records:
                raise ExtractionError("EXTRACTION_PERSONA_REQUIRED")
            if not persona_records[persona_id]:
                raise ExtractionError("EXTRACTION_PERSONA_RECORD_REQUIRED")


def build_interpretation_candidates(output: Mapping[str, Any], *, source_id: int, extraction_run_id: str) -> list[dict[str, Any]]:
    """Lower validated claims to private proposals, never canonical mutations.

    The database ingestion step may assign UUIDs, but it must retain this exact
    provenance payload and may only promote an accepted interpretation later.
    """
    if not isinstance(source_id, int) or source_id < 1 or not isinstance(extraction_run_id, str) or not extraction_run_id.strip():
        raise ExtractionError("EXTRACTION_INTERPRETATION_CONTEXT_REQUIRED")
    validate_output(output)
    candidates = []
    for claim in output.get("claims", []):
        predicate = str(claim["predicate"])
        family = predicate.split(".", 1)[0]
        kind = "relation" if family == "relationship" else "event" if family == "life_event" else "property"
        confidence = claim.get("confidence")
        if not isinstance(confidence, (int, float)) or isinstance(confidence, bool) or not 0 <= confidence <= 1:
            raise ExtractionError("EXTRACTION_CONFIDENCE_INVALID")
        candidates.append({
            "source_id": source_id, "source_persona_id": claim.get("source_persona_id"),
            "interpretation_kind": kind, "predicate": predicate, "value": claim["value"],
            "status": "proposed", "derivation_kind": "model_inference", "confidence": float(confidence),
            "method": "model", "extraction_run_id": extraction_run_id,
            "record_key": claim["record_key"], "observation_ids": list(claim["observation_ids"]),
        })
    return candidates


def reusable(existing: BatchManifest, candidate: BatchManifest) -> bool:
    """A changed input, profile, prompt or model always forces a fresh run."""
    return (existing.validation_status == "green" and existing.input_hash == candidate.input_hash
            and existing.profile_id == candidate.profile_id and existing.profile_version == candidate.profile_version
            and existing.effective_model_id == candidate.effective_model_id
            and existing.prompt_version == candidate.prompt_version and existing.record_keys == candidate.record_keys)
