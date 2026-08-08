"""Bygger en privat, browserlokal grænsegennemgang for 1939."""

from __future__ import annotations

import argparse
import copy
import json
from collections.abc import Mapping
from pathlib import Path

from boundary_signals_1939 import classify_gap, may_bulk_confirm, span_signals
from boundary_spans_1939 import BoundaryError, build_boundaries, collect_accepted_spans
from prepare_review_queue_1939 import validate_effective_candidate_injectivity

KONTEKST_TEGN = 400


def _group_of(record: Mapping) -> object:
    gruppe = record.get("_gruppe_nr")
    return ("gruppe", gruppe) if gruppe is not None else ("gren", record.get("_v2_lokal_id"))


def build_boundary_view_model(spans: list[dict], clauses: list[dict],
                              calamari_text: str, raw_text: str,
                              records: Mapping, source: Mapping) -> dict:
    """Saml grænserne, deres signaler og deres bunke — uden at ændre et spænd."""
    boundaries = build_boundaries(spans, len(calamari_text))
    by_key = {span["baseline_record_key"]: span for span in spans}
    validate_effective_candidate_injectivity(
        {key: span["candidate"] for key, span in by_key.items()},
        dict(source),
    )
    groups: dict[object, list[dict]] = {}
    for key, span in by_key.items():
        record = records.get(key)
        if record is None:
            raise BoundaryError(f"accepteret spænd har ukendt post {key}")
        entry = {**copy.deepcopy(dict(record)), "char_from": span["char_from"]}
        groups.setdefault(_group_of(record), []).append(entry)
    signals_by_key: dict[str, list[str]] = {}
    for key, span in by_key.items():
        record = records[key]
        siblings = groups[_group_of(record)]
        lengths = [
            by_key[sibling["record_key"]]["char_to"]
            - by_key[sibling["record_key"]]["char_from"]
            for sibling in siblings if sibling["record_key"] != key
        ]
        signals_by_key[key] = span_signals(
            span, record, calamari_text[span["char_from"]:span["char_to"]],
            siblings, sibling_lengths=lengths,
        )
    view_required, view_bulk, entries = [], [], []
    for boundary in boundaries:
        gap = boundary["gap"]
        gap_text = calamari_text[gap["char_from"]:gap["char_to"]]
        raw_window = raw_text[gap["char_from"]:gap["char_to"]] if raw_text else ""
        summary = classify_gap(clauses, gap)
        signals = []
        for side in ("before", "after"):
            span = boundary[side]
            if span is not None:
                signals.extend(signals_by_key.get(span["baseline_record_key"], []))
        bulk = may_bulk_confirm(gap_text, raw_window, summary) and not [
            signal for signal in signals if signal != "laengdeafvigelse"
        ]
        entry = {
            **boundary,
            "gap_summary": summary,
            "gap_text": gap_text,
            "raw_window": raw_window,
            "signals": sorted(set(signals)),
            "bulk_confirmable": bulk,
            "before_context": calamari_text[
                max(0, gap["char_from"] - KONTEKST_TEGN):gap["char_from"]],
            "after_context": calamari_text[
                gap["char_to"]:gap["char_to"] + KONTEKST_TEGN],
            "before_navn": (records[boundary["before"]["baseline_record_key"]].get("navn")
                            if boundary["before"] else None),
            "after_navn": (records[boundary["after"]["baseline_record_key"]].get("navn")
                           if boundary["after"] else None),
        }
        entries.append(entry)
        (view_bulk if bulk else view_required).append(entry["boundary_id"])
    return {
        "schema_version": 1,
        "source": copy.deepcopy(dict(source)),
        "summary": {
            "graenser": len(entries),
            "kraever_vurdering": len(view_required),
            "hurtig_bekraeftelse": len(view_bulk),
        },
        "views": {
            "kraever_vurdering": view_required,
            "hurtig_bekraeftelse": view_bulk,
        },
        "boundaries": entries,
    }
