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


# ===========================================================================
# Runneren, svar-cachen og fejltaksonomien (dagsværk 4.3a, Task 3)
# ===========================================================================

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

#: Bumpes, når runnerens egen kontrakt ændrer sig (argv, parsing, validering).
#: Indgår i cache-nøglen, så et gammelt råsvar ikke genbruges under nye regler.
RUNNER_CONTRACT_VERSION = "evidence-runner-1.0"

#: Modelpolitikken er frossen (decisions 2026-09-06, valg 1).
ALLOWED_MODELS = ("gpt-5.6-terra", "gpt-5.6-sol")

#: Spec §6.3.  Alle er fail-closed: batchen forbliver `pending`, intet merges.
ERROR_KINDS = {"quota_exhausted", "model_refusal", "schema_violation",
               "timeout", "validation_failed", "unknown"}

#: Spec §6.3 + anden læsers R7.  De to sidste felter er R7's tilføjelse: uden dem
#: kan et ændret outputskema eller en ændret runner genbruge et gammelt råsvar.
CACHE_KEY_FIELDS = ("profile_id", "profile_version", "model", "prompt_sha256",
                    "record_input_sha256", "claims_schema_sha256", "runner_contract_version")

#: Fejltyper aflæses af `turn.failed`'s `error.type`.  Ukendte former bliver
#: `unknown` — aldrig stiltiende accepteret.
_FAILURE_TYPES = {
    "usage_limit_reached": "quota_exhausted",
    "quota_exceeded": "quota_exhausted",
    "rate_limit_exceeded": "quota_exhausted",
    "refusal": "model_refusal",
    "content_filter": "model_refusal",
    "output_schema_violation": "schema_violation",
    "invalid_output": "schema_violation",
}


def build_argv(*, model: str, call_dir: str, schema_path: str, prompt_path: str) -> list[str]:
    """Argv for ét modelkald (spec §6.2 + afvigelse A).

    `--ignore-user-config` er afvigelse A: uden den injicerer CLI'en brugerens
    `~/.codex/AGENTS.md` i hvert kald, og den ligger uden for `prompt_sha256` —
    så et "reproducerbart" kald ville ikke være det.  Målt: 6.288 af 21.554
    input-tokens.
    """
    if model not in ALLOWED_MODELS:
        raise RunnerError("RUNNER_MODEL_NOT_ALLOWED")
    return ["codex", "exec", "--model", model, "--sandbox", "read-only", "--ephemeral",
            "--ignore-rules", "--ignore-user-config", "--skip-git-repo-check",
            "-C", call_dir, "--json", "--output-schema", schema_path, "-", prompt_path]


def _events(jsonl: str) -> list[dict]:
    parsed = []
    for line in jsonl.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            continue  # en ulæselig linje er ikke et regnskab; den ignoreres her
    return parsed


def parse_usage(jsonl: str) -> dict:
    """Forbruget fra `turn.completed` (spec §6.4).

    Et manglende `usage` på en ellers vellykket tur er `unknown`, ikke nul: nul
    ville være en løgn i budgettet, og budgettet er hele grunden til 4.3a.
    """
    for event in _events(jsonl):
        if event.get("type") == "turn.completed":
            usage = event.get("usage")
            if isinstance(usage, dict) and usage:
                return usage
            raise RunnerError("RUNNER_USAGE_UNKNOWN")
    raise RunnerError("RUNNER_USAGE_UNKNOWN")


def classify_failure(jsonl: str, *, exit_code: int | None, timed_out: bool = False) -> str:
    """Fejltype efter spec §6.3.  Ukendt er en rigtig kategori, ikke en rest."""
    if timed_out:
        return "timeout"
    for event in _events(jsonl):
        if event.get("type") == "turn.failed":
            error = event.get("error")
            if isinstance(error, dict):
                return _FAILURE_TYPES.get(error.get("type"), "unknown")
            return "unknown"
    return "unknown"


class ResponseCache:
    """Per-record uforanderlig svar-cache (spec §6.3).

    Append-only: en eksisterende nøgle med afvigende værdi er en konflikt, ikke
    en overskrivning — ellers kunne en kørsel stille erstatte et svar, en tidligere
    validering byggede på.  Filer er `0600` i en `0700`-mappe (§9.1); `tempfile`-
    standarder og brugerens umask er ikke kontrakten.
    """

    def __init__(self, root):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)

    @staticmethod
    def key(ident: Mapping[str, Any]) -> str:
        missing = set(CACHE_KEY_FIELDS) - set(ident)
        if missing:
            raise RunnerError("RUNNER_CACHE_IDENT_INCOMPLETE")
        material = "\x1f".join(str(ident[field]) for field in CACHE_KEY_FIELDS)
        return hashlib.sha256(material.encode("utf-8")).hexdigest()

    def _path(self, ident: Mapping[str, Any]) -> Path:
        return self.root / f"{self.key(ident)}.json"

    def get(self, ident: Mapping[str, Any]) -> dict | None:
        path = self._path(ident)
        if not path.exists():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def put(self, ident: Mapping[str, Any], *, raw: str, usage: Mapping[str, Any]) -> None:
        path = self._path(ident)
        entry = {"raw": raw, "usage": dict(usage)}
        if path.exists():
            if json.loads(path.read_text(encoding="utf-8")) != entry:
                raise RunnerError("RUNNER_CACHE_CONFLICT")
            return
        # Opret med 0600 fra starten frem for at rette bagefter: ellers findes filen
        # et øjeblik med umask'ens rettigheder.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(entry, handle, ensure_ascii=False, sort_keys=True)


@dataclass(frozen=True)
class RecordOutcome:
    record_key: str
    status: str                      # "green" | "failed"
    error_kind: str | None = None
    usage: Mapping[str, Any] | None = None
    claims: tuple = ()
    from_cache: bool = False

    def log_line(self) -> str:
        """Til logs: type og record-nøgle, ALDRIG tekst (spec §6.3).

        Hverken modellens svar, kildeteksten eller fejlbeskeder må herind — en
        logfil er ikke et sted, persondata skal kunne ende.
        """
        if self.status == "green":
            return f"record={self.record_key} status=green cached={str(self.from_cache).lower()}"
        return f"record={self.record_key} status=failed kind={self.error_kind}"


def run_codex(argv: Sequence[str], *, cwd: str | None = None, timeout: int = 600):
    """Produktionssømmen: ét ikke-interaktivt Codex-kald med lukket stdin.

    Kaldet forventes at køre bag Seatbelt-gaten
    (`scripts/sandbox/runner-gate.sb.template`) med `cwd` sat til call-dir — se
    gatens hoved for hvorfor begge dele er nødvendige.
    """
    completed = subprocess.run(list(argv), cwd=cwd, stdin=subprocess.DEVNULL,
                               capture_output=True, text=True, timeout=timeout)
    return completed.stdout, completed.stderr


def run_record(export: Mapping[str, Any], *, ident: Mapping[str, Any], cache: ResponseCache,
               run=run_codex, argv: Sequence[str] | None = None, cwd: str | None = None) -> RecordOutcome:
    """Kør én record gennem modellen, eller hent den fra cachen.

    Fail-closed hele vejen: et svar, der ikke kan valideres, cachelagres **ikke**
    og kan derfor ikke senere genbruges som grønt.
    """
    record_key = str(export.get("record_key", ""))

    hit = cache.get(ident)
    if hit is not None:
        claims = json.loads(hit["raw"]).get("claims", [])
        validate_record_claims(claims, export)   # cachen er data, ikke en garanti
        return RecordOutcome(record_key, "green", usage=hit["usage"],
                             claims=tuple(claims), from_cache=True)

    try:
        events, last_message = run(argv or [], cwd=cwd)
    except subprocess.TimeoutExpired:
        return RecordOutcome(record_key, "failed", error_kind="timeout")

    try:
        usage = parse_usage(events)
    except RunnerError:
        return RecordOutcome(record_key, "failed",
                             error_kind=classify_failure(events, exit_code=1))

    try:
        payload = json.loads(last_message)
        claims = payload["claims"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return RecordOutcome(record_key, "failed", error_kind="schema_violation")

    try:
        validate_record_claims(claims, export)
    except RunnerError:
        return RecordOutcome(record_key, "failed", error_kind="validation_failed", usage=usage)

    cache.put(ident, raw=last_message, usage=usage)
    return RecordOutcome(record_key, "green", usage=usage, claims=tuple(claims))


def batch_status(record_states: Sequence[tuple[str, str]]) -> str:
    """En batch er kun `green`, når HVER record har en valideret post (spec §6.3).

    Delvis dækning er `pending` — også en tom batch, som ellers ville være
    "grøn" på et tomt grundlag.
    """
    if not record_states:
        return "pending"
    return "green" if all(state == "green" for _, state in record_states) else "pending"
