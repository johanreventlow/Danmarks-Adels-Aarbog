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


class ExtractionError(ValueError):
    pass


ROOT = Path(__file__).resolve().parents[4]
PROFILES = ROOT / ".claude/skills/daa-extract/references/extraction-profiles.json"
ALLOWED_MODELS = {"gpt-5.6-terra", "gpt-5.6-sol"}


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
    completed = BatchManifest(**{**asdict(manifest), "output_hash": _sha(output), "token_count": token_count,
                                 "cost_usd": cost_usd, "validation_status": "green"})
    completed.validate()
    return completed


def reusable(existing: BatchManifest, candidate: BatchManifest) -> bool:
    """A changed input, profile, prompt or model always forces a fresh run."""
    return (existing.validation_status == "green" and existing.input_hash == candidate.input_hash
            and existing.profile_id == candidate.profile_id and existing.profile_version == candidate.profile_version
            and existing.effective_model_id == candidate.effective_model_id
            and existing.prompt_version == candidate.prompt_version and existing.record_keys == candidate.record_keys)
