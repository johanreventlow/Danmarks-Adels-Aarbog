"""Fælles kerne for token-ark (4.5-fortolkninger, 5a-identitet): hash-binding og SQL-citering.

Arkene rummer kildetekst; kernen ser kun bytes, hashes og id'er."""
from __future__ import annotations

import hashlib
import re


class SheetError(RuntimeError):
    pass


def sql_literal(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def require_hex64(*hashes: str) -> None:
    for h in hashes:
        if not re.fullmatch(r"[0-9a-f]{64}", h or ""):
            raise SheetError("SHEET_HASH_REQUIRED")


def verify_bound(rows_bytes: bytes, expect_rows_sha256: str,
                 sheet_bytes: bytes, approved_sha256: str) -> tuple[str, str]:
    rows_sha = hashlib.sha256(rows_bytes).hexdigest()
    if rows_sha != expect_rows_sha256:
        raise SheetError("ROWS_HASH_MISMATCH — rækkefilen er ikke den, arket blev bygget af.")
    sheet_sha = hashlib.sha256(sheet_bytes).hexdigest()
    if sheet_sha != approved_sha256:
        raise SheetError("SHEET_HASH_MISMATCH — arket er ikke det, der blev godkendt.")
    return rows_sha, sheet_sha
