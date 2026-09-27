"""Klausulsættets identitet — Python-siden af private.clause_set_sha256 (omsegmentering).

sha256 over kanonisk JSON (nøgler sorteret, ingen mellemrum, UTF-8 uden escapes) af en
liste sorteret efter ordinal. Hver klausul: ordinal, post_char_from/to (helpost-relativ),
char_from/to (renditions-absolut), classification, flags (sorteret, uden dubletter) og
verbatim_sha256. Pariteten med SQL låses af tests/fixtures/clause-set-sha256.json.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Iterable, Mapping


def clause_set_sha256(clauses: Iterable[Mapping[str, Any]]) -> str:
    """Hash for klausuler i manifest-/payloadform (char_* post-relativ, rendition_char_* absolut)."""
    items = [{
        "ordinal": c["ordinal"],
        "post_char_from": c["char_from"], "post_char_to": c["char_to"],
        "char_from": c["rendition_char_from"], "char_to": c["rendition_char_to"],
        "classification": c["classification"],
        "flags": sorted(set(c["flags"])),
        "verbatim_sha256": c["verbatim_sha256"],
    } for c in sorted(clauses, key=lambda c: c["ordinal"])]
    text = json.dumps(items, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()
