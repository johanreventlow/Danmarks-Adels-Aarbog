"""Build an explicit private acceptance review from a frozen pilot manifest."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Mapping, Sequence


class ReviewPreparationError(ValueError):
    pass


def _require(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReviewPreparationError(f"{field} kræves")
    return value


def _page_span(value: object) -> tuple[int, int]:
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:-\d+)?", value):
        raise ReviewPreparationError("sider mangler sikker PDF-side")
    parts = [int(part) for part in value.split("-")]
    if parts[0] < 1 or parts[-1] < parts[0]:
        raise ReviewPreparationError("sider er ugyldig")
    return parts[0], parts[-1]


def _selection_key(locator: object) -> tuple[str, str]:
    if not isinstance(locator, str):
        raise ReviewPreparationError("occurrence_locator kræves")
    match = re.fullmatch(r"([IVX]+)-(.+)", locator)
    if not match:
        raise ReviewPreparationError("occurrence_locator har ugyldigt format")
    return match.group(1), match.group(2)


def build_accepted_review(posts: Sequence[Mapping[str, Any]], manifest: Mapping[str, Any], *, rendition_id: str,
                          extraction_run_id: str, reviewed_by: str, rendition_text: str) -> dict[str, Any]:
    """Build only the user-approved person acceptances; never infer an identity."""
    if manifest.get("schema_version") != "1.0":
        raise ReviewPreparationError("manifest schema_version 1.0 kræves")
    source_hash = _require(manifest.get("raw_text_sha256"), "manifest raw_text_sha256")
    if len(source_hash) != 64 or any(char not in "0123456789abcdef" for char in source_hash.lower()):
        raise ReviewPreparationError("manifest raw_text_sha256 er ugyldig")
    rendition_text = _require(rendition_text, "rendition_text")
    if hashlib.sha256(rendition_text.encode("utf-8")).hexdigest() != source_hash.lower():
        raise ReviewPreparationError("rendition teksthash matcher ikke manifest")
    by_key: dict[tuple[str, str], Mapping[str, Any]] = {}
    for post in posts:
        key = (_require(post.get("linje"), "post linje"), _require(post.get("nr_label"), "post nr_label"))
        if key in by_key:
            raise ReviewPreparationError("dublet posttuple")
        by_key[key] = post
    selection = manifest.get("selection")
    if not isinstance(selection, Mapping) or not isinstance(selection.get("person_occurrences"), list):
        raise ReviewPreparationError("manifest person_occurrences kræves")
    records = []
    selected: set[tuple[str, str]] = set()
    for item in selection["person_occurrences"]:
        if not isinstance(item, Mapping):
            raise ReviewPreparationError("manifest person occurrence skal være objekt")
        locator = _require(item.get("occurrence_locator"), "occurrence_locator")
        key = _selection_key(locator)
        if key in selected:
            raise ReviewPreparationError("dublet manifesttuple")
        selected.add(key)
        post = by_key.get(key)
        if post is None:
            raise ReviewPreparationError("manifesttuple mangler i posts")
        text = _require(post.get("raw_text"), "post raw_text")
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != _require(item.get("raw_text_sha256"), "post raw_text_sha256"):
            raise ReviewPreparationError("post teksthash matcher ikke manifest")
        anchor_from = rendition_text.find(text)
        if anchor_from < 0 or rendition_text.find(text, anchor_from + 1) >= 0:
            raise ReviewPreparationError("post tekstanker er ikke entydigt")
        page_from, page_to = _page_span(post.get("sider"))
        records.append({
            "acceptance_id": f"task16-2018-person-{locator}",
            "record_kind": "person",
            "decision_status": "accepted",
            "reviewed_by": _require(reviewed_by, "reviewed_by"),
            "decision_version": 1,
            "verbatim_text": text,
            "span": {
                "page_from": page_from,
                "page_to": page_to,
                "char_from": 0,
                "char_to": len(text),
                "bbox": None,
            },
            "source_anchor": {"char_from": anchor_from, "char_to": anchor_from + len(text)},
        })
    if not records:
        raise ReviewPreparationError("manifest har ingen person occurrences")
    return {
        "schema_version": "1.0",
        "source_id": "2018-20",
        "rendition_id": _require(rendition_id, "rendition_id"),
        "rendition_sha256": source_hash.lower(),
        "rendition_text": rendition_text,
        "extraction_run_id": _require(extraction_run_id, "extraction_run_id"),
        "records": records,
    }


def write_new_json(path: Path, value: Mapping[str, Any]) -> None:
    """Persist a private review once, refusing to overwrite a prior decision."""
    try:
        with path.open("x", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
    except FileExistsError as exc:
        raise ReviewPreparationError("fil findes allerede") from exc
