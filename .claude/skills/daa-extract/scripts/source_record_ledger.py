"""Private, append-only minting for accepted source-record segmentations."""
from __future__ import annotations

import copy
import hashlib
import json
from typing import Any, Mapping

from evidence_contract import ContractError, mint_record_key, validate_bundle


class LedgerError(ValueError):
    pass


def _require(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise LedgerError(f"{field} kræves")
    return value


def _canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _digest(value: object) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _stable_id(prefix: str, source_id: str, acceptance_id: str) -> str:
    return f"{prefix}-{_digest([source_id, acceptance_id])[:24]}"


def _span(record: Mapping[str, Any], rendition_id: str, verbatim_text: str) -> dict[str, Any]:
    value = record.get("span")
    if not isinstance(value, Mapping):
        raise LedgerError("span kræves")
    required = ("page_from", "page_to", "char_from", "char_to")
    if any(not isinstance(value.get(key), int) for key in required):
        raise LedgerError("span kræver heltalsfelter")
    if value["page_from"] < 1 or value["page_to"] < value["page_from"]:
        raise LedgerError("span har ugyldige sider")
    if value["char_from"] != 0 or value["char_to"] != len(verbatim_text):
        raise LedgerError("span skal dække hele verbatim tekst")
    bbox = value.get("bbox")
    if bbox is not None and (not isinstance(bbox, (list, tuple)) or len(bbox) != 4
                             or any(not isinstance(item, int) for item in bbox)):
        raise LedgerError("span bbox er ugyldig")
    return {
        "rendition_id": rendition_id,
        "page_from": value["page_from"],
        "page_to": value["page_to"],
        "column_label": value.get("column_label"),
        "char_from": value["char_from"],
        "char_to": value["char_to"],
        "bbox": list(bbox) if bbox is not None else None,
    }


def _accepted_records(review: Mapping[str, Any]) -> tuple[dict[str, str], list[dict[str, Any]]]:
    if not isinstance(review, Mapping) or review.get("schema_version") != "1.0":
        raise LedgerError("review schema_version 1.0 kræves")
    context = {
        "source_id": _require(review.get("source_id"), "source_id"),
        "rendition_id": _require(review.get("rendition_id"), "rendition_id"),
        "rendition_sha256": _require(review.get("rendition_sha256"), "rendition_sha256").lower(),
        "extraction_run_id": _require(review.get("extraction_run_id"), "extraction_run_id"),
    }
    if len(context["rendition_sha256"]) != 64 or any(char not in "0123456789abcdef" for char in context["rendition_sha256"]):
        raise LedgerError("rendition_sha256 er ugyldig")
    records = review.get("records")
    if not isinstance(records, list) or not records:
        raise LedgerError("review records kræves")
    seen: set[str] = set()
    accepted: list[dict[str, Any]] = []
    for raw in records:
        if not isinstance(raw, Mapping):
            raise LedgerError("review record skal være objekt")
        acceptance_id = _require(raw.get("acceptance_id"), "acceptance_id")
        if acceptance_id in seen:
            raise LedgerError("duplicate acceptance_id")
        seen.add(acceptance_id)
        if raw.get("decision_status") != "accepted":
            raise LedgerError("kun accepted records må mintes")
        reviewed_by = _require(raw.get("reviewed_by"), "reviewed_by")
        decision_version = raw.get("decision_version")
        if not isinstance(decision_version, int) or decision_version < 1:
            raise LedgerError("decision_version skal være positiv")
        verbatim_text = _require(raw.get("verbatim_text"), "verbatim_text")
        accepted.append({
            **context,
            "acceptance_id": acceptance_id,
            "record_kind": _require(raw.get("record_kind"), "record_kind"),
            "reviewed_by": reviewed_by,
            "decision_version": decision_version,
            "verbatim_text": verbatim_text,
            "span": _span(raw, context["rendition_id"], verbatim_text),
        })
    return context, sorted(accepted, key=lambda item: item["acceptance_id"])


def _immutable(record: Mapping[str, Any]) -> str:
    return _digest({key: record[key] for key in (
        "source_id", "rendition_id", "rendition_sha256", "record_kind", "verbatim_text", "span",
    )})


def _ledger_entries(ledger: Mapping[str, Any]) -> dict[str, dict[str, str]]:
    if not isinstance(ledger, Mapping) or ledger.get("schema_version") != "1.0":
        raise LedgerError("ledger schema_version 1.0 kræves")
    entries = ledger.get("entries")
    if not isinstance(entries, list):
        raise LedgerError("ledger entries kræves")
    result: dict[str, dict[str, str]] = {}
    record_keys: set[str] = set()
    for raw in entries:
        if not isinstance(raw, Mapping):
            raise LedgerError("ledger entry skal være objekt")
        acceptance_id = _require(raw.get("acceptance_id"), "ledger acceptance_id")
        record_key = _require(raw.get("record_key"), "ledger record_key")
        immutable = _require(raw.get("immutable"), "ledger immutable")
        if acceptance_id in result or record_key in record_keys:
            raise LedgerError("duplicate ledger entry")
        result[acceptance_id] = {
            "acceptance_id": acceptance_id,
            "record_key": record_key,
            "immutable": immutable,
        }
        record_keys.add(record_key)
    return result


def _bundle(context: Mapping[str, str], records: list[dict[str, Any]], entries: Mapping[str, Mapping[str, str]]) -> dict[str, Any]:
    source_records = []
    occurrences = []
    anchors = []
    for record in records:
        acceptance_id = record["acceptance_id"]
        source_record_id = _stable_id("source-record", context["source_id"], acceptance_id)
        occurrence_id = _stable_id("occurrence", context["source_id"], acceptance_id)
        source_records.append({"id": source_record_id, "record_key": entries[acceptance_id]["record_key"]})
        occurrences.append({
            "occurrence_id": occurrence_id,
            "rendition_id": context["rendition_id"],
            "extraction_run_id": context["extraction_run_id"],
            "verbatim_text": record["verbatim_text"],
            "span": record["span"],
        })
        anchors.append({
            "event_id": _stable_id("anchor", context["source_id"], acceptance_id),
            "occurrence_id": occurrence_id,
            "source_record_id": source_record_id,
            "decision_status": "accepted",
            "version": record["decision_version"],
        })
    return {
        "schema_version": "1.0",
        "source_rendition": [{
            "rendition_id": context["rendition_id"],
            "sha256": context["rendition_sha256"],
        }],
        "source_records": source_records,
        "source_record_occurrences": occurrences,
        "source_record_anchor_events": anchors,
        "source_record_revision_events": [],
        "record_placements": [],
        "persona_placements": [],
        "observations": [],
        "text_variants": [],
        "mentions": [],
        "source_personas": [],
        "extraction_run": {"run_id": context["extraction_run_id"]},
    }


def materialize(review: Mapping[str, Any], ledger: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Mint only accepted records and return a new ledger plus valid evidence bundle."""
    context, records = _accepted_records(review)
    entries = _ledger_entries(ledger)
    next_entries = copy.deepcopy(entries)
    for record in records:
        acceptance_id = record["acceptance_id"]
        immutable = _immutable(record)
        prior = entries.get(acceptance_id)
        if prior is not None:
            if prior["immutable"] != immutable:
                raise LedgerError("accepted record drift")
            continue
        next_entries[acceptance_id] = {
            "acceptance_id": acceptance_id,
            "record_key": mint_record_key(),
            "immutable": immutable,
        }
    next_ledger = {
        "schema_version": "1.0",
        "entries": [next_entries[key] for key in sorted(next_entries)],
    }
    bundle = _bundle(context, records, next_entries)
    try:
        validate_bundle(bundle)
    except ContractError as exc:
        raise LedgerError("genereret bundle er ugyldigt") from exc
    return next_ledger, bundle
