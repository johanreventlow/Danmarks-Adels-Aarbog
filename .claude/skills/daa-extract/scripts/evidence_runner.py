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
import re
import unicodedata
from typing import Any, Mapping, Sequence

from evidence_extract import PREDICATES, ExtractionError, predicate_kind, validate_claim_value


class RunnerError(ValueError):
    """Fejl i runnerens egen kontrakt.  Alle er fail-closed: batchen forbliver
    `pending`, og intet merges."""


#: Lukket nøglesæt.  Payloaden lagres permanent i `private.reimport_event`, så et
#: frit felt ville være en vej for kildetekst ind i en tabel, vi ikke rydder.
CLAIM_KEYS = {"clause_ordinals", "predicate", "value", "confidence", "source_persona_id"}
REQUIRED_CLAIM_KEYS = {"clause_ordinals", "predicate", "value", "confidence"}


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def normalize_ws(text: str) -> str:
    """Den ENE definition af »samme tekst« for ordrethed: NFC, blanktegn samlet.

    Linjeskift og dobbelte mellemrum er sats, ikke tekst.  Store/små bogstaver og
    tegnsætning er derimod en del af den ordrette form.  Afgørelsesarket
    (`decision_sheet_html`) importerer netop denne funktion, så runnerens afvisning
    og arkets ordret-mærke ikke kan drive fra hinanden.
    """
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", text)).strip()


#: Prædikat-formerne, hvis værdi SKAL stå ordret i en citeret klausul (review 35,
#: fund P10).  Kun datoer: promptens regel 3 og stopkriteriets nævner (»claims m.
#: ordret krav«).  Titler o.l. må skæres til (4.3b), og objekt-`raw` håndhæves
#: ikke — projektejerens valg 2026-09-26, fordi to omskrevne hændelser i 4.3b var
#: bedømt sande.  Udvid ikke uden en ny beslutning.
VERBATIM_VALUE_KINDS = {"date_raw"}


def canonical_record_input(export: Mapping[str, Any]) -> str:
    """Den ENE definition af en records input-identitet.

    Anden læser (4.3b-review, fund 3) fandt, at ledgeren og runneren hashede to
    forskellige ting: R-eksporten `string_agg(verbatim_text)` over observationer,
    Python en JSON-serialisering af hele record-objektet.  De kan aldrig matche, så
    kontrollen ville enten afvise alt eller blive omgået for at komme videre.

    Definitionen her er valgt, fordi BÅDE SQL og Python kan producere den bit for
    bit: helpostens ordrette tekst, intet andet.  Klausulerne er udskåret af netop
    den tekst, så ændrer den sig, er klausulerne også andre.
    """
    text = export.get("post_verbatim_text")
    if not isinstance(text, str) or not text:
        raise EligibilityError("RECORD_INPUT_TEXT_MISSING")
    return sha256_text(text)


def canonical_clause_set(export: Mapping[str, Any]) -> str:
    """Hash over klausulsættet: sorteret `(ordinal, sha256(tekst))` (review 35, P4).

    `canonical_record_input` binder kun helposten, men modellen citerer ordinaler.
    Klippes den samme helpost anderledes (P3/#189), peger et cachet svars ordinal 2
    på en anden klausul — derfor indgår klausulsættet i cache-nøglen.  Hashen
    beregnes af teksten, ikke af eksportens egen hash-kolonne (`_clause_index`
    efterprøver den undervejs).
    """
    index = _clause_index(export)
    pairs = [[ordinal, sha256_text(index[ordinal]["verbatim_text"])] for ordinal in sorted(index)]
    return sha256_text(json.dumps(pairs, separators=(",", ":")))


def check_clauses_within_post(export: Mapping[str, Any]) -> None:
    """Klausulerne skal være ordnede, ikke-overlappende udsnit af helposten.

    Ledgeren og manifestet binder kun helpostens tekst (`canonical_record_input`),
    men modellen ser klausulerne.  Uden dette tjek kunne tekst fra en anden — evt.
    udelukket — record rejse med som klausul under en eligible record (4.5-kodereview,
    fund 1).  Målt 2026-09-24: alle 591 records i 2018-20-inputtet opfylder det.
    """
    text = export.get("post_verbatim_text")
    clauses = export.get("clauses")
    if not isinstance(text, str) or not isinstance(clauses, Sequence) \
            or isinstance(clauses, (str, bytes)):
        raise EligibilityError(f"CLAUSE_OUTSIDE_POST record={export.get('record_key')}")
    pos = 0
    for clause in sorted(clauses, key=lambda c: c.get("ordinal", 0) if isinstance(c, Mapping) else 0):
        fragment = clause.get("verbatim_text") if isinstance(clause, Mapping) else None
        i = text.find(fragment, pos) if isinstance(fragment, str) and fragment else -1
        if i < 0:
            raise EligibilityError(f"CLAUSE_OUTSIDE_POST record={export.get('record_key')}")
        pos = i + len(fragment)


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


def partition_record_claims(claims: Any, export: Mapping[str, Any]) -> tuple[list, list]:
    """Del claims i (gyldige, afviste) — ét ugyldigt claim fælder ikke resten.

    Projektejerens afgørelse 2026-09-12 efter bundt 1: modellen ramte værdiformen
    i 34 af 35 tilfælde, men ét objekt hvor der skulle stå en streng fældede hele
    posten og dens seks øvrige, korrekte claims.  Ved den fejlrate ville omtrent
    hver tredje rige post gå tabt — ikke fordi udtrækket var dårligt, men fordi ét
    felt havde forkert type.

    Det er lige så sikkert: et afvist claim lagres aldrig.  Forskellen er kun, hvor
    meget der reddes.  Posten markeres `delvis`, så tabet forbliver synligt.

    Afviste bærer deres fejltoken, så mønstre kan tælles frem for at forsvinde.
    """
    gyldige, afviste = [], []
    for claim in (claims if isinstance(claims, Sequence)
                  and not isinstance(claims, (str, bytes)) else []):
        try:
            validate_record_claims([claim], export)
        except RunnerError as exc:
            afviste.append({"claim": claim, "fejl": str(exc)})
        else:
            gyldige.append(claim)
    return gyldige, afviste


def validate_record_claims(claims: Any, export: Mapping[str, Any]) -> None:
    """Validér modellens claims mod den record, den faktisk fik at se.

    Kaster ved FØRSTE ugyldige claim.  Brug `partition_record_claims`, når et
    enkelt dårligt claim ikke skal fælde de øvrige.

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

        # Formen er gyldig; står værdien også i det, claimet citerer?  Klausulerne
        # sammenføjes i ordinalorden, så en værdi, der krydser en klausulgrænse,
        # ikke afvises.  Et tjek af formen alene lod en ISO-omregnet dato passere.
        if PREDICATES[predicate].get("value_kind") in VERBATIM_VALUE_KINDS:
            cited = " ".join(index[o]["verbatim_text"] for o in sorted(set(ordinals)))
            if normalize_ws(claim["value"]) not in normalize_ws(cited):
                raise RunnerError("RUNNER_CLAIM_VALUE_NOT_VERBATIM")

        confidence = claim["confidence"]
        if (not isinstance(confidence, (int, float)) or isinstance(confidence, bool)
                or not 0.0 <= float(confidence) <= 1.0):
            raise RunnerError("RUNNER_CLAIM_CONFIDENCE_INVALID")

        # Persona-reglen, spec §6.1 fund 3a: et person.*-claim må citere HVILKEN SOM
        # HELST klausul under den helpost, personaen har mention i.  Det er bevidst
        # bredere end `validate_output`'s "delmængde af personaens egne
        # mention-observationer" — klausullaget har ikke mentions pr. klausul.
        # Ret ikke dette tilbage uden at læse §6.1.
        # `source_persona_id` er ALTID en nøgle i svaret: structured outputs kræver,
        # at hvert felt står i `required`, så valgfriheden udtrykkes med null frem
        # for fravær (målt mod API'et 2026-09-12).  Et null er derfor legitimt for
        # ikke-person-claims — men ikke for person.*.
        if predicate.startswith("person."):
            claimed = claim.get("source_persona_id")
            if not isinstance(claimed, str) or not claimed.strip() or claimed != persona_id:
                raise RunnerError("RUNNER_CLAIM_PERSONA_REQUIRED")


# ===========================================================================
# Runneren, svar-cachen og fejltaksonomien (dagsværk 4.3a, Task 3)
# ===========================================================================

import contextlib
import json
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

#: Bumpes, når runnerens egen kontrakt ændrer sig (argv, parsing, validering).
#: Indgår i cache-nøglen, så et gammelt råsvar ikke genbruges under nye regler.
#: 1.1 (2026-09-26): date_raw-værdier skal stå ordret i en citeret klausul.
#: 1.2 (2026-09-27): klausulsættet indgår i cache-nøglen (review 35, P4).
#: 1.3 (2026-09-28): et kald med værktøjsbrug fældes (`tool_use`, review 35, P1).  Et
#:     1.2-svar kan være skrevet af et kald, der kørte en kommando; strømmen gemmes
#:     ikke i cachen, så det kan ikke efterprøves og må ikke genbruges.
RUNNER_CONTRACT_VERSION = "evidence-runner-1.3"

#: Modelpolitikken er frossen (decisions 2026-09-06, valg 1).
ALLOWED_MODELS = ("gpt-5.6-terra", "gpt-5.6-sol")

#: Spec §6.3.  Alle er fail-closed: batchen forbliver `pending`, intet merges.
ERROR_KINDS = {"quota_exhausted", "model_refusal", "schema_violation",
               "timeout", "validation_failed", "unknown",
               # Ikke en kørselsfejl: recorden måtte slet ikke sendes (§9.2).
               # Den står i taksonomien, så udelukkede records kan tælles frem for
               # at forsvinde ud af regnskabet.
               "not_eligible",
               # Review 35, P1: modellen har brugt et værktøj (kørt en kommando, rørt en
               # fil, søgt på nettet).  Et brud på grænsen, ikke et kvalitetsudfald.
               "tool_use"}

#: De eneste item-typer, et kald uden værktøjsbrug må rumme.  TILLADELSESLISTE:
#: en ny værktøjstype i en senere CLI-version skal fælde recorden, ikke glide igennem.
#: `error` er CLI'ens meddelelse om en fejl, ikke et værktøj; selve fejlen afgøres af
#: `turn.failed`.
ALLOWED_ITEM_TYPES = {"agent_message", "reasoning", "error"}

#: Spec §6.3 + anden læsers R7.  De to sidste felter er R7's tilføjelse: uden dem
#: kan et ændret outputskema eller en ændret runner genbruge et gammelt råsvar.
#: `record_key` er MED, selv om `record_input_sha256` afleder af teksten: to records
#: kan have identisk helposttekst.  Målt i 2018-20: 591 records, kun 588 unikke
#: teksthashes — TRE kollisioner i de faktiske data.  Uden nøglen ville to poster
#: dele cachepost, og et cachet svar kunne ikke henføres til den record, det
#: beskriver.  (Anden læsers fund 2 ved reviewet af plan 4.4.)
#:
#: `clause_set_sha256` (1.2, review 35 P4): modellen citerer klausul-ordinaler, så en
#: omsegmentering af samme helpost må ikke genbruge et svar, hvis ordinal 2 nu er en
#: anden klausul.
CACHE_KEY_FIELDS = ("profile_id", "profile_version", "model", "prompt_sha256",
                    "record_key", "record_input_sha256", "clause_set_sha256",
                    "claims_schema_sha256", "runner_contract_version")

#: Nøgleudledningen følger den kontrakt, identiteten bærer — ikke den aktuelle.  Så
#: kan 4.3b/4.5's caches stadig adresseres, som de blev skrevet, og en ukendt
#: kontrakt har ingen udledning frem for et gæt.
_PRE_CLAUSE_SET_FIELDS = tuple(f for f in CACHE_KEY_FIELDS if f != "clause_set_sha256")
CACHE_KEY_FIELDS_BY_CONTRACT = {
    "evidence-runner-1.0": _PRE_CLAUSE_SET_FIELDS,
    "evidence-runner-1.1": _PRE_CLAUSE_SET_FIELDS,
    "evidence-runner-1.2": CACHE_KEY_FIELDS,
    RUNNER_CONTRACT_VERSION: CACHE_KEY_FIELDS,
}

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


def build_argv(*, model: str, call_dir: str, schema_path: str, prompt: str) -> list[str]:
    """Argv for ét modelkald (spec §6.2 + afvigelse A).

    `--ignore-user-config` er afvigelse A: uden den injicerer CLI'en brugerens
    `~/.codex/AGENTS.md` i hvert kald, og den ligger uden for `prompt_sha256` —
    så et "reproducerbart" kald ville ikke være det.  Målt: 6.288 af 21.554
    input-tokens.

    Prompten sendes som det POSITIONELLE argument — dens indhold, ikke en sti.
    `-` ville betyde "læs prompten fra stdin", og stdin er lukket (`DEVNULL`),
    så kaldet ville få en tom prompt.  Kalderen læser filen og hasher de samme
    bytes til `prompt_sha256`, så hashen og det afsendte ikke kan divergere.
    """
    if model not in ALLOWED_MODELS:
        raise RunnerError("RUNNER_MODEL_NOT_ALLOWED")
    if not isinstance(prompt, str) or not prompt.strip():
        raise RunnerError("RUNNER_PROMPT_REQUIRED")
    return ["codex", "exec", "--model", model, "--sandbox", "read-only", "--ephemeral",
            "--ignore-rules", "--ignore-user-config", "--skip-git-repo-check",
            "-C", call_dir, "--json", "--output-schema", schema_path, prompt]


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


def tool_items(jsonl: str) -> list[str]:
    """Item-typer i strømmen, som ikke er svar eller ræsonnement — i rækkefølge, unikke.

    Review 35, P1: beskyttelsen mod, at modellen læser uden for call-dir, hvilede på,
    at Codex' indre `--sandbox read-only` ikke kan starte inde i Seatbelt (rc=71) —
    en utilsigtet egenskab ved en selvopdaterende binær.  Dette tjek gør det til en
    regel: har modellen KØRT noget, er recorden fældet, uanset hvad den svarede.
    """
    fundne: list[str] = []
    for event in _events(jsonl):
        if event.get("type") not in ("item.started", "item.updated", "item.completed"):
            continue
        item = event.get("item")
        item_type = item.get("type") if isinstance(item, Mapping) else None
        if item_type not in ALLOWED_ITEM_TYPES:
            navn = str(item_type)
            if navn not in fundne:
                fundne.append(navn)
    return fundne


_CODEX_VERSION_RE = re.compile(r"codex-cli (\d+\.\d+\.\d+)")


def codex_cli_version(*, run=None) -> str:
    """Den installerede Codex-CLI's version, som den står i `codex --version`.

    Review 35, P1: CLI'en opdaterer sig selv (0.153.4 d. 11/9, 0.155.1 d. 25/9), og
    grænsens opførsel afhænger af den.  Versionen bindes derfor i manifestet, og en
    uventet form er en fejl — aldrig et gæt.
    """
    if run is None:
        def run(argv):
            return subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True,
                                  text=True, timeout=30).stdout
    match = _CODEX_VERSION_RE.fullmatch((run(["codex", "--version"]) or "").strip())
    if match is None:
        raise RunnerError("RUNNER_CODEX_VERSION_UNKNOWN")
    return match.group(1)


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
        fields = CACHE_KEY_FIELDS_BY_CONTRACT.get(ident.get("runner_contract_version"))
        if fields is None:
            raise RunnerError("RUNNER_CACHE_CONTRACT_UNKNOWN")
        missing = set(fields) - set(ident)
        if missing:
            raise RunnerError("RUNNER_CACHE_IDENT_INCOMPLETE")
        material = "\x1f".join(str(ident[field]) for field in fields)
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
    rejected: tuple = ()
    from_cache: bool = False

    def log_line(self) -> str:
        """Til logs: type og record-nøgle, ALDRIG tekst (spec §6.3).

        Hverken modellens svar, kildeteksten eller fejlbeskeder må herind — en
        logfil er ikke et sted, persondata skal kunne ende.
        """
        if self.status in ("green", "delvis"):
            afvist = f" afviste={len(self.rejected)}" if self.rejected else ""
            return (f"record={self.record_key} status={self.status}"
                    f" cached={str(self.from_cache).lower()}{afvist}")
        return f"record={self.record_key} status=failed kind={self.error_kind}"


def extract_last_message(jsonl: str) -> str:
    """Modellens sidste svar, hentet ud af selve hændelsesstrømmen.

    Svaret ligger i det SIDSTE `item.completed` med `type: agent_message`.  Der kan
    være flere: en tur kan begynde med "Jeg forsøger at læse filen…" og først
    derefter give svaret.  stderr er IKKE svaret — den bærer fx
    "Reading additional input from stdin...", som aldrig kan parses som JSON.
    """
    sidste = ""
    for event in _events(jsonl):
        if event.get("type") == "item.completed":
            item = event.get("item")
            if isinstance(item, Mapping) and item.get("type") == "agent_message":
                text = item.get("text")
                if isinstance(text, str):
                    sidste = text
    return sidste


def run_codex(argv: Sequence[str], *, cwd: str | None = None, timeout: int = 600):
    """Produktionssømmen: ét ikke-interaktivt Codex-kald med lukket stdin.

    Kaldet forventes at køre bag Seatbelt-gaten
    (`scripts/sandbox/runner-gate.sb.template`) med `cwd` sat til call-dir — se
    gatens hoved for hvorfor begge dele er nødvendige.

    Returnerer `(hændelsesstrøm, sidste besked)`.  Begge udledes af stdout;
    `--json` gør strømmen selvbærende, så der behøves ingen `-o`-fil — og dermed
    ét privat artefakt mindre at rydde op efter.
    """
    completed = subprocess.run(list(argv), cwd=cwd, stdin=subprocess.DEVNULL,
                               capture_output=True, text=True, timeout=timeout)
    return completed.stdout, extract_last_message(completed.stdout)


def run_record(export: Mapping[str, Any], *, ident: Mapping[str, Any], cache: ResponseCache,
               run=run_codex, argv: Sequence[str] | None = None, cwd: str | None = None) -> RecordOutcome:
    """Kør én record gennem modellen, eller hent den fra cachen.

    Fail-closed hele vejen: et svar, der ikke kan valideres, cachelagres **ikke**
    og kan derfor ikke senere genbruges som grønt.
    """
    record_key = str(export.get("record_key", ""))

    # Klausulsættet i nøglen beregnes af kalderen; det skal være DETTE inputs sæt,
    # ellers kan et svar for en anden segmentering hentes eller gemmes (P4).  Samme
    # lære som eligibility-værnet: en hash, kalderen blot opgiver, beviser intet.
    if "clause_set_sha256" in CACHE_KEY_FIELDS_BY_CONTRACT.get(ident.get("runner_contract_version"), ()) \
            and ident.get("clause_set_sha256") != canonical_clause_set(export):
        raise RunnerError("RUNNER_CLAUSE_SET_DRIFT")

    hit = cache.get(ident)
    if hit is not None:
        # Cachen er data, ikke en garanti: den revalideres.  Fejler den, er udfaldet
        # et fail-closed resultat som alle andre steder — ikke en exception, der
        # ville vælte hele batchen i stedet for at markere én record.
        try:
            raa = json.loads(hit["raw"])["claims"]
        except (json.JSONDecodeError, KeyError, TypeError):
            return RecordOutcome(record_key, "failed", error_kind="validation_failed",
                                 usage=hit.get("usage"), from_cache=True)
        gyldige, afviste = partition_record_claims(raa, export)
        if afviste and not gyldige:
            return RecordOutcome(record_key, "failed", error_kind="validation_failed",
                                 usage=hit.get("usage"), from_cache=True)
        return RecordOutcome(record_key, "green" if not afviste else "delvis",
                             usage=hit["usage"], claims=tuple(gyldige),
                             rejected=tuple(afviste), from_cache=True)

    try:
        events, last_message = run(argv or [], cwd=cwd)
    except subprocess.TimeoutExpired:
        return RecordOutcome(record_key, "failed", error_kind="timeout")

    # En fejlet tur klassificeres som før (spec §6.6 stopper på `quota_exhausted`);
    # recorden er fældet og caches ikke, uanset værktøjsbrug.
    if any(event.get("type") == "turn.failed" for event in _events(events)):
        try:
            usage = parse_usage(events)
        except RunnerError:
            usage = None
        return RecordOutcome(record_key, "failed", usage=usage,
                             error_kind=classify_failure(events, exit_code=1))

    # Derefter værktøjsbrug, FØR svaret læses: et gyldigt svar redder ikke et kald, der
    # har kørt en kommando, og det må aldrig nå cachen (review 35, P1).
    if tool_items(events):
        try:
            usage = parse_usage(events)
        except RunnerError:
            usage = None
        return RecordOutcome(record_key, "failed", error_kind="tool_use", usage=usage)

    try:
        usage = parse_usage(events)
    except RunnerError:
        return RecordOutcome(record_key, "failed",
                             error_kind=classify_failure(events, exit_code=1))

    try:
        payload = json.loads(last_message)
        claims = payload["claims"]
    except (json.JSONDecodeError, KeyError, TypeError):
        # Forbruget er brugt, selv om svaret er ubrugeligt — og budgettet er hele
        # grunden til 4.3a, så tallet må ikke tabes her.
        return RecordOutcome(record_key, "failed", error_kind="schema_violation", usage=usage)

    gyldige, afviste = partition_record_claims(claims, export)
    if afviste and not gyldige:
        # Intet brugbart kom igennem — det er en ægte fejl, ikke en delvis succes.
        return RecordOutcome(record_key, "failed", error_kind="validation_failed", usage=usage)

    # Cachen gemmer det RÅ svar; valideringen køres igen ved hvert opslag, så en
    # senere regelændring ikke stiltiende godkender noget, der blev afvist i dag.
    cache.put(ident, raw=last_message, usage=usage)
    return RecordOutcome(record_key, "green" if not afviste else "delvis",
                         usage=usage, claims=tuple(gyldige), rejected=tuple(afviste))


@contextlib.contextmanager
def prepare_call_dir(record_input: Mapping[str, Any], schema: Mapping[str, Any], *, root=None):
    """Kaldets egen mappe: præcis det, modellen skal se — og intet andet.

    Sammen med Seatbelt-gaten er dette afvigelse C's afhjælpning: mappen er den
    ENESTE læsbare del af brugerens data under kaldet, og gaten håndhæver det.
    Mappen ligger uden for repoet, er `0700`, og filerne oprettes `0600` med
    `O_EXCL` (§9.1) — aldrig via umask.

    Ryddes i `finally`, også ved kvotestop, timeout og exception: en efterladt
    mappe med kildetekst er et fund, ikke et restprodukt.
    """
    call_dir = Path(tempfile.mkdtemp(prefix="daa-evidence-", dir=root))
    os.chmod(call_dir, 0o700)
    try:
        for navn, indhold in (("record.json", record_input), ("schema.json", schema)):
            sti = call_dir / navn
            fd = os.open(sti, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(indhold, handle, ensure_ascii=False, sort_keys=True)
        yield call_dir
    finally:
        shutil.rmtree(call_dir, ignore_errors=True)


def batch_status(record_states: Sequence[tuple[str, str]]) -> str:
    """En batch er kun `green`, når HVER record har en valideret post (spec §6.3).

    Delvis dækning er `pending` — også en tom batch, som ellers ville være
    "grøn" på et tomt grundlag.
    """
    if not record_states:
        return "pending"
    # `delvis` tæller med: recorden HAR en valideret post, blot ikke alle claims.
    # Tabet står i regnskabet via antallet af afviste claims.
    return "green" if all(state in ("green", "delvis") for _, state in record_states) else "pending"


# ===========================================================================
# Eligibility-ledgeren (dagsværk 4.3a, Task 5 — spec §9.1-9.2)
#
# Invariant 8 er projektets hårdeste: prosa om levende personer må aldrig sendes
# til en model.  Ledgeren er den ene af to mekanismer, der håndhæver det —
# Seatbelt-gaten er den anden.  De dækker hver sin halvdel:
#
#   ledgeren  styrer hvad vi SENDER
#   gaten     styrer hvad modellen selv kan HENTE
#
# GRUNDREGLEN ER, AT FRAVÆR IKKE ER TILLADELSE.  En record, der ikke står i
# ledgeren som eksplicit `eligible`, sendes ikke — heller ikke når ledgeren i
# øvrigt er gyldig.  En udelukkelsesliste, man kun tjekker for tilstedeværelse,
# beskytter intet: den siger, hvem der er forbudt, men ikke hvem der er godkendt.
# ===========================================================================

LEDGER_SCHEMA_VERSION = "evidence-eligibility-1.0"

#: §9.2's fire regler.  Lukket sæt: en årsag uden for listen betyder, at ledgeren
#: er skrevet af noget, denne kode ikke kender — og så er den ikke troværdig.
EXCLUSION_REASONS = {
    "principal_living",           # 1. hovedpersonen er levende eller uafklaret
    "relative_living",            # 2. partner eller barn i samme family er levende
    "spouse_undated_marriage",    # 3. partner uden dødsdato, vielse >=1950 eller udateret
    "birth_year_text_filter",     # 4. teksten rummer "f." + fødselsår >=1950
}

_LEDGER_FIELDS = ("schema_version", "policy_version", "rules_script_sha256",
                  "source_id", "restore_identity", "records")


class EligibilityError(RunnerError):
    """Rejst når en record ikke må sendes — eller når ledgeren ikke kan stoles på.

    Arver fra `RunnerError`, så den fanges af de samme fail-closed veje, men har
    egen type, fordi den er et PERSONDATA-værn og ikke en almindelig kørselsfejl.
    """


def load_ledger(ledger: Mapping[str, Any]) -> dict:
    """Validér ledgerens skema og provenance (R3).

    Hashen over selve eksportresultatet er ikke nok: uden regelversion,
    script-hash og snapshot-identitet kan en gammel eller fejlimplementeret
    ledger være internt konsistent og alligevel forkert.  Og fordi *fravær*
    læses som tilladelse i den forkerte implementering, er netop det farligt.
    """
    if not isinstance(ledger, Mapping):
        raise EligibilityError("LEDGER_INCOMPLETE")
    for field in _LEDGER_FIELDS:
        if field not in ledger or ledger[field] in (None, ""):
            raise EligibilityError("LEDGER_INCOMPLETE")
    if ledger["schema_version"] != LEDGER_SCHEMA_VERSION:
        raise EligibilityError("LEDGER_SCHEMA_UNKNOWN")

    records = ledger["records"]
    if not isinstance(records, Mapping):
        raise EligibilityError("LEDGER_INCOMPLETE")
    for record_key, row in records.items():
        if not isinstance(row, Mapping):
            raise EligibilityError("LEDGER_INCOMPLETE")
        status = row.get("status")
        if status not in ("eligible", "excluded"):
            raise EligibilityError("LEDGER_STATUS_INVALID")
        reasons = row.get("reasons")
        if not isinstance(reasons, Sequence) or isinstance(reasons, (str, bytes)):
            raise EligibilityError("LEDGER_REASON_REQUIRED")
        if status == "excluded" and not reasons:
            # En udelukkelse uden årsag kan ikke efterprøves af et menneske.
            raise EligibilityError("LEDGER_REASON_REQUIRED")
        for reason in reasons:
            if reason not in EXCLUSION_REASONS:
                raise EligibilityError("LEDGER_REASON_UNKNOWN")
        sha = row.get("record_input_sha256")
        if not isinstance(sha, str) or len(sha) != 64:
            raise EligibilityError("LEDGER_INCOMPLETE")
    return dict(ledger)


def check_eligibility(ledger: Mapping[str, Any], record_key: str,
                      record_input_sha256: str) -> str:
    """Må denne record sendes til en model?  Kaster, hvis svaret ikke er et klart ja.

    Rækkefølgen er en del af værnet: ledgeren valideres, FØR nogen record slås op,
    så en utroværdig ledger ikke kan nå at godkende noget.
    """
    validated = load_ledger(ledger)
    row = validated["records"].get(str(record_key))
    if row is None:
        # Fravær er ikke tilladelse.
        raise EligibilityError(f"RECORD_UNKNOWN record={record_key}")
    if row["status"] != "eligible":
        raise EligibilityError(
            f"RECORD_EXCLUDED record={record_key} reasons={','.join(row['reasons'])}")
    if row["record_input_sha256"] != record_input_sha256:
        # Ledgeren godkendte ét bestemt input; et andet er ikke dækket af den godkendelse.
        raise EligibilityError(f"RECORD_INPUT_DRIFT record={record_key}")
    return "eligible"


def run_record_guarded(export: Mapping[str, Any], *, ledger: Mapping[str, Any],
                       **kwargs) -> RecordOutcome:
    """`run_record` med eligibility-værnet foran.

    Preflighten kører FØR prompt, call-dir og subproces overhovedet bygges: en
    record, der ikke må sendes, efterlader intet spor på disken og starter aldrig
    Codex.  Et værn, der først spørger efter at have skrevet kildeteksten til en
    midlertidig mappe, har allerede fejlet.

    **Hashen beregnes HER af `export`** — den modtages ikke længere som argument.
    Anden læser (4.3b-review, fund 2) påviste hullet: da kalderen selv angav
    `record_input_sha256`, kunne den opgive en godkendt records nøgle og hash og
    derefter sende et andet indhold videre.  Værnet beviste altså ikke, at det
    guardede input var det afsendte.  Nu er de to pr. konstruktion det samme.

    Udelukkede records forsvinder ikke ud af regnskabet (§9.2): de får et synligt
    `not_eligible`-udfald med record-nøglen, så de kan tælles og ses i køen.
    """
    record_key = str(export.get("record_key", ""))
    try:
        check_eligibility(ledger, record_key, canonical_record_input(export))
        check_clauses_within_post(export)
    except EligibilityError:
        return RecordOutcome(record_key, "failed", error_kind="not_eligible")
    return run_record(export, **kwargs)


def build_gate_profile(*, call_dir: str, home: str, extra_deny: Sequence[str] = ()) -> str:
    """Udfyld Seatbelt-skabelonen for ét kald.

    Skabelonen ligger i `sandbox/runner-gate.sb.template` og bærer selv
    begrundelserne.  Kort: hele hjemmemappen er lukket for læsning, og kun
    `~/.codex`, `~/.local` og call-dir er åbne.  `~/Library` er bevidst IKKE med —
    den var åben i et tidligere udkast, og `~/Library/Keychains` var læsbar med den.
    """
    template = (Path(__file__).resolve().parent / "sandbox" / "runner-gate.sb.template")
    profile = template.read_text(encoding="utf-8")
    # Seatbelt matcher den OPLØSTE sti: /var/folders og /tmp er symlinks til /private/…,
    # og en uopløst call-dir ville ikke blive genåbnet efter spærringen af dem.
    call_dir = os.path.realpath(call_dir)
    denies = "\n".join(f'(deny file-read* (subpath "{path}"))' for path in extra_deny)
    return (profile.replace("__HOME__", home)
                   .replace("__CALL_DIR__", call_dir)
                   .replace("__EXTRA_DENY__", denies))


def build_gated_argv(*, profile_path: str, **kwargs) -> list[str]:
    """`build_argv` pakket ind i Seatbelt-gaten.

    Det er DENNE form, der må bruges mod rigtige data: `codex exec --sandbox
    read-only` alene er ikke en læsegrænse (se profilens hoved).  Kaldet skal køre
    med call-dir som arbejdsmappe — ellers fejler det med »Operation not
    permitted«, fordi cwd selv er spærret.
    """
    return ["sandbox-exec", "-f", profile_path] + build_argv(**kwargs)
