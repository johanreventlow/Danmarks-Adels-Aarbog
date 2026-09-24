#!/usr/bin/env python3
"""Pinned, resumable orchestration for granular source-evidence extraction.

This module deliberately does not call a model.  It records the immutable input
and model contract that an approved runner must honour, so ambient settings can
never silently change an extraction run or make a partial batch mergeable.
"""
from __future__ import annotations

import hashlib
import json
import re
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
# Det er med vilje en lukket, editionsneutral vokabularliste. En profil må ændre
# layoutgenkendelse, aldrig gøre en ny semantisk claim-type gyldig uden kode,
# test og menneskelig GO.
PREDICATES_FILE = ROOT / ".claude/skills/daa-extract/references/interpretation-predicates.json"


def _load_predicates() -> dict[str, dict[str, Any]]:
    """#147 4.2: prædikatvokabularet ejes af private.interpretation_predicate.

    Filen er en byte-verificeret projektion af tabellen; extractoren har ikke
    længere sin egen liste, der kan drive fra databasen.
    """
    payload = json.loads(PREDICATES_FILE.read_text(encoding="utf-8"))
    if payload.get("schema_version") != "interpretation-predicates-1.0":
        raise ExtractionError("EXTRACTION_PREDICATE_FILE_INVALID")
    return {row["predicate"]: row for row in payload["predicates"]}


PREDICATES = _load_predicates()
ALLOWED_PREDICATES = frozenset(PREDICATES)
SCALAR_VALUE_KINDS = {"text", "date_raw"}


def predicate_kind(predicate: str) -> str:
    if predicate not in PREDICATES:
        raise ExtractionError("EXTRACTION_PREDICATE_INVALID")
    return PREDICATES[predicate]["interpretation_kind"]


def validate_claim_value(predicate: str, value: Any) -> None:
    """Værdiformen følger prædikatets value_kind — skalar for text/date_raw,
    ellers et objekt med en ordret raw."""
    kind = PREDICATES.get(predicate, {}).get("value_kind")
    if kind is None:
        raise ExtractionError("EXTRACTION_PREDICATE_INVALID")
    if kind in SCALAR_VALUE_KINDS:
        if not isinstance(value, str) or not value.strip():
            raise ExtractionError("EXTRACTION_CLAIM_VALUE_INVALID")
        return
    if not isinstance(value, Mapping) or not isinstance(value.get("raw"), str) or not value["raw"].strip():
        raise ExtractionError("EXTRACTION_CLAIM_VALUE_INVALID")
    if "normalized" in value and value["normalized"] is not None and not isinstance(value["normalized"], str):
        raise ExtractionError("EXTRACTION_CLAIM_VALUE_INVALID")


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sha(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


CLAUSE_RULE_KEYS = {"version", "terminators", "non_terminal_abbreviations", "initial_pattern",
                    "ordinal_number_pattern", "structural_header_patterns", "min_clause_chars",
                    "gap_charset", "intraword_chars"}
# Valgfrie regelnøgler (#189). En profil uden dem segmenterer præcis som før — det
# er det, der lader en ny regel komme ind som en NY profilversion uden at røre de
# godkendte versioners semantik.
OPTIONAL_CLAUSE_RULE_KEYS = {"section_numeral_pattern"}


REFERENCES = ROOT / ".claude/skills/daa-extract/references"


def resolve_prompt(prompt_file: str, prompt_sha256: str) -> str:
    """Læs den prompt, en profil peger på, og bekræft dens hash (#147 4.3a).

    Før dette var `prompt_version` en ren streng, som ingen kode bandt til en fil:
    profilen sagde `evidence-extract-1.0.0`, mens `extract-prompt.md` sagde
    `2026-07-29b`, og de to havde intet med hinanden at gøre.  Nu er `prompt_sha256`
    i manifestet et bevis frem for en påstand — de bytes, der sendes til modellen,
    er de samme, der blev hashet.

    Filnavnet må ikke kunne pege ud af `references/`.
    """
    if (not isinstance(prompt_file, str) or not prompt_file
            or "/" in prompt_file or "\\" in prompt_file or prompt_file.startswith(".")):
        raise ExtractionError("EXTRACTION_PROMPT_FILE_INVALID")
    path = REFERENCES / prompt_file
    if not path.is_file():
        raise ExtractionError("EXTRACTION_PROMPT_FILE_MISSING")
    text = path.read_text(encoding="utf-8")
    if hashlib.sha256(text.encode("utf-8")).hexdigest() != prompt_sha256:
        raise ExtractionError("EXTRACTION_PROMPT_FILE_DRIFT")
    return text


def validate_clause_rules(rules: Any) -> None:
    if (not isinstance(rules, Mapping) or not CLAUSE_RULE_KEYS <= set(rules)
            or not set(rules) <= CLAUSE_RULE_KEYS | OPTIONAL_CLAUSE_RULE_KEYS):
        raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    if not isinstance(rules["version"], str) or not rules["version"].strip():
        raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    for key in ("terminators", "non_terminal_abbreviations", "structural_header_patterns", "gap_charset", "intraword_chars"):
        if not isinstance(rules[key], list) or not all(isinstance(v, str) and v for v in rules[key]):
            raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    if not rules["terminators"] or not rules["gap_charset"]:
        raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    for key in ("initial_pattern", "ordinal_number_pattern"):
        try:
            re.compile(rules[key])
        except (re.error, TypeError):
            raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    for pattern in rules["structural_header_patterns"]:
        try:
            re.compile(pattern)
        except re.error:
            raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    if "section_numeral_pattern" in rules:
        pattern = rules["section_numeral_pattern"]
        if not isinstance(pattern, str) or not pattern:
            raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
        try:
            re.compile(pattern)
        except re.error:
            raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    if not isinstance(rules["min_clause_chars"], int) or isinstance(rules["min_clause_chars"], bool) or rules["min_clause_chars"] < 1:
        raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")


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
    if "clause_rules" in profile:
        validate_clause_rules(profile["clause_rules"])
    # En profil MÅ mangle prompt-bindingen — 1939 gør, indtil trin 6 giver den en.
    # Men bærer den én, skal filen findes og hashen holde; runneren afviser en profil
    # uden binding frem for at gætte en prompt.
    if "prompt_file" in profile or "prompt_sha256" in profile:
        if "prompt_file" not in profile or "prompt_sha256" not in profile:
            raise ExtractionError("EXTRACTION_PROMPT_BINDING_INCOMPLETE")
        resolve_prompt(profile["prompt_file"], profile["prompt_sha256"])
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
    # 4.3a (spec §6.2): det, kaldet faktisk blev bundet af.  `prompt_sha256` dækker
    # prompten, `exclusion_sha256` den eligibility-ledger runneren slog op i.  `usage`
    # er Codex' eget femfeltsregnskab — RÅ TOKENTAL, der kommer gratis med svaret.
    #
    # Der er BEVIDST ingen prisberegning: kørslerne afregnes over abonnement, ikke pr.
    # token, så en kroneomregning ville være et tal uden modstykke i virkeligheden
    # (projektejerens afgørelse 2026-09-12).  Tokentallene beholdes, fordi de er det,
    # der siger, om en større kørsel kan gennemføres inden for kvoten.
    #
    # `token_count` BEVARES som selvstændigt felt frem for at blive afledt af `usage`:
    # `complete_batch` og `reusable` læser det i dag, og manifests skrevet før 4.3a har
    # ingen `usage`.  De to må ikke modsige hinanden — se `validate`.
    prompt_sha256: str | None = None
    exclusion_sha256: str | None = None
    usage: Mapping[str, Any] | None = None

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
        if self.usage is not None:
            if not isinstance(self.usage, Mapping):
                raise ExtractionError("EXTRACTION_USAGE_INVALID")
            # Et regnskab, der modsiger sin egen totalsum, er værre end intet.
            billed = self.usage.get("input_tokens", 0) + self.usage.get("output_tokens", 0)
            if self.token_count is not None and billed and self.token_count != billed:
                raise ExtractionError("EXTRACTION_USAGE_TOKEN_COUNT_CONFLICT")


def manifest_payload(manifest: BatchManifest) -> dict[str, Any]:
    """Return the canonical JSON representation used for persisted manifests."""
    manifest.validate()
    payload = asdict(manifest)
    payload["record_keys"] = list(manifest.record_keys)
    return payload


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
    if bundle.get("schema_version") not in ("1.1", "1.2"):
        raise ExtractionError("EXTRACTION_EVIDENCE_BUNDLE_VERSION_REQUIRED")
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
    record_keys = {str(record.get("id", "")): str(record.get("record_key", ""))
                   for record in bundle.get("source_records", []) if isinstance(record, Mapping)}
    accepted_record_by_occurrence = {
        str(anchor.get("occurrence_id", "")): record_keys.get(str(anchor.get("source_record_id", "")), "")
        for anchor in bundle.get("source_record_anchor_events", []) if isinstance(anchor, Mapping)
        and anchor.get("decision_status") == "accepted"
    }
    persona_observations: dict[str, set[str]] = {}
    for persona in bundle.get("source_personas", []):
        if not isinstance(persona, Mapping):
            continue
        persona_id = str(persona.get("persona_id", persona.get("id", "")))
        mention_ids = persona.get("mention_ids", [])
        if not isinstance(mention_ids, list):
            continue
        persona_observations[persona_id] = {
            mention_observation[str(mention_id)]
            for mention_id in mention_ids
            if str(mention_id) in mention_observation
        }
    for claim in claims:
        if not isinstance(claim, Mapping):
            raise ExtractionError("EXTRACTION_CLAIM_INVALID")
        predicate = claim.get("predicate")
        if not isinstance(predicate, str) or predicate not in ALLOWED_PREDICATES:
            raise ExtractionError("EXTRACTION_PREDICATE_INVALID")
        cited = claim.get("observation_ids")
        if not isinstance(cited, list) or not cited or any(not isinstance(value, str) or value not in observation_ids for value in cited):
            raise ExtractionError("EXTRACTION_OBSERVATION_REQUIRED")
        if "value" not in claim:
            raise ExtractionError("EXTRACTION_CLAIM_VALUE_REQUIRED")
        validate_claim_value(predicate, claim["value"])
        expected_keys = {accepted_record_by_occurrence.get(observation_occurrence[observation_id], "")
                         for observation_id in cited}
        record_key = claim.get("record_key")
        if (not isinstance(record_key, str) or not record_key.strip() or not expected_keys
                or "" in expected_keys or record_key not in expected_keys):
            raise ExtractionError("EXTRACTION_RECORD_KEY_REQUIRED")
        if predicate.startswith("person."):
            persona_id = claim.get("source_persona_id")
            if not isinstance(persona_id, str) or persona_id not in persona_observations:
                raise ExtractionError("EXTRACTION_PERSONA_REQUIRED")
            if not set(cited).issubset(persona_observations[persona_id]):
                raise ExtractionError("EXTRACTION_PERSONA_OBSERVATION_REQUIRED")


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
        # #147 4.2: udsagnsformen kommer fra prædikattabellen, ikke fra et gæt på
        # præfikset. 'event.marriage' og 'relation.marriage' er forskellige udsagn.
        kind = predicate_kind(predicate)
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
    # 4.3a / anden læsers R7: de nye felter skal indgå i GENBRUGSBESLUTNINGEN, ikke
    # kun bæres i payloaden.  Ændret prompt, ændret udelukkelsesgrundlag eller ændret
    # pristabel betyder, at det gamle svar ikke længere svarer på det samme spørgsmål.
    return (existing.validation_status == "green" and existing.input_hash == candidate.input_hash
            and existing.profile_id == candidate.profile_id and existing.profile_version == candidate.profile_version
            and existing.effective_model_id == candidate.effective_model_id
            and existing.prompt_version == candidate.prompt_version and existing.record_keys == candidate.record_keys
            and existing.prompt_sha256 == candidate.prompt_sha256
            and existing.exclusion_sha256 == candidate.exclusion_sha256)
