#!/usr/bin/env python3
"""Model-runner for den fælles fortolkningskæde (#147 dagsværk 4.3a).

Modellen ser ÉN helpost ad gangen med dens klausuler og returnerer claims, der
citerer klausul-**ordinaler**.  Det er en anden kontrakt end
`evidence_extract.validate_output`, hvis strict bundle-vej kræver hele
renditionens tekst og rendition-absolutte offsets (spec §6.1).

Kun bundle-/offset-halvdelen er ny.  Vokabular og værdiformer genbruges fra 4.2's
`private.interpretation_predicate` gennem `evidence_extract`, så der ikke opstår et
parallelt prædikatsæt, der kan drive fra databasen.

Modulet kalder ikke selv Codex: kaldet ligger bag en injicerbar søm, så tests
aldrig starter en model.
"""
from __future__ import annotations

import hashlib
from typing import Any, Mapping, Sequence

from evidence_extract import ExtractionError, predicate_kind, validate_claim_value


class RunnerError(ValueError):
    """Fejl i runnerens egen kontrakt.  Alle er fail-closed: batchen forbliver
    `pending`, og intet merges."""


#: Lukket nøglesæt.  Payloaden lagres permanent i `private.reimport_event`, så et
#: frit felt ville være en vej for kildetekst ind i en tabel, vi ikke rydder.
CLAIM_KEYS = {"clause_ordinals", "predicate", "value", "confidence", "source_persona_id"}
REQUIRED_CLAIM_KEYS = {"clause_ordinals", "predicate", "value", "confidence"}


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _clause_index(export: Mapping[str, Any]) -> dict[int, Mapping[str, Any]]:
    """Ordinal → klausul, med hashen efterprøvet undervejs.

    Eksporten er vores eget artefakt, ikke modellens.  Skrider dens tekst fra sin
    egen hash, er grundlaget for hele valideringen væk — så det tjekkes her frem
    for at blive antaget.
    """
    clauses = export.get("clauses")
    if not isinstance(clauses, Sequence) or isinstance(clauses, (str, bytes)):
        raise RunnerError("RUNNER_EXPORT_INVALID")
    index: dict[int, Mapping[str, Any]] = {}
    for clause in clauses:
        if not isinstance(clause, Mapping):
            raise RunnerError("RUNNER_EXPORT_INVALID")
        ordinal, text = clause.get("ordinal"), clause.get("verbatim_text")
        if not isinstance(ordinal, int) or isinstance(ordinal, bool) or ordinal < 1:
            raise RunnerError("RUNNER_EXPORT_INVALID")
        if not isinstance(text, str) or ordinal in index:
            raise RunnerError("RUNNER_EXPORT_INVALID")
        if clause.get("verbatim_sha256") != sha256_text(text):
            raise RunnerError("RUNNER_EXPORT_HASH_MISMATCH")
        index[ordinal] = clause
    return index


def validate_record_claims(claims: Any, export: Mapping[str, Any]) -> None:
    """Validér modellens claims mod den record, den faktisk fik at se.

    En tom liste er gyldig: en record uden udtrækbare fakta er ikke en fejl.
    """
    if not isinstance(claims, Sequence) or isinstance(claims, (str, bytes)):
        raise RunnerError("RUNNER_CLAIMS_INVALID")
    index = _clause_index(export)
    persona_id = export.get("persona_id")

    for claim in claims:
        if not isinstance(claim, Mapping):
            raise RunnerError("RUNNER_CLAIM_INVALID")
        keys = set(claim)
        if not keys <= CLAIM_KEYS or not REQUIRED_CLAIM_KEYS <= keys:
            raise RunnerError("RUNNER_CLAIM_KEYS_INVALID")

        ordinals = claim["clause_ordinals"]
        if (not isinstance(ordinals, Sequence) or isinstance(ordinals, (str, bytes))
                or not ordinals):
            raise RunnerError("RUNNER_CLAIM_ORDINAL_REQUIRED")
        for ordinal in ordinals:
            if not isinstance(ordinal, int) or isinstance(ordinal, bool):
                raise RunnerError("RUNNER_CLAIM_ORDINAL_REQUIRED")
            if ordinal not in index:
                raise RunnerError("RUNNER_CLAIM_ORDINAL_UNKNOWN")

        predicate = claim["predicate"]
        if not isinstance(predicate, str):
            raise RunnerError("RUNNER_CLAIM_PREDICATE_INVALID")
        # Opslaget validerer prædikatet mod tabellen.  Udsagnsformen (`interpretation_kind`)
        # HENTES her og modtages aldrig fra modellen: den er ikke en nøgle i CLAIM_KEYS,
        # så et forsøg afvises allerede af nøglesættet ovenfor.  4.2's lære — formen blev
        # før gættet ud fra præfikset og kunne ikke skelne `event.marriage` fra
        # `relation.marriage`.
        try:
            predicate_kind(predicate)
        except ExtractionError as exc:
            raise RunnerError("RUNNER_CLAIM_PREDICATE_INVALID") from exc

        try:
            validate_claim_value(predicate, claim["value"])
        except ExtractionError as exc:
            raise RunnerError("RUNNER_CLAIM_VALUE_INVALID") from exc

        confidence = claim["confidence"]
        if (not isinstance(confidence, (int, float)) or isinstance(confidence, bool)
                or not 0.0 <= float(confidence) <= 1.0):
            raise RunnerError("RUNNER_CLAIM_CONFIDENCE_INVALID")

        # Persona-reglen, spec §6.1 fund 3a: et person.*-claim må citere HVILKEN SOM
        # HELST klausul under den helpost, personaen har mention i.  Det er bevidst
        # bredere end `validate_output`'s "delmængde af personaens egne
        # mention-observationer" — klausullaget har ikke mentions pr. klausul.
        # Ret ikke dette tilbage uden at læse §6.1.
        if predicate.startswith("person."):
            claimed = claim.get("source_persona_id")
            if not isinstance(claimed, str) or not claimed.strip() or claimed != persona_id:
                raise RunnerError("RUNNER_CLAIM_PERSONA_REQUIRED")
