#!/usr/bin/env python3
"""Pure, deterministic dewrap + ordinal-strip transform (``narrative_norm_v1``).

Implements the "Dewrap-transformens kontrakt" (points 1-6) from
``docs/superpowers/plans/2026-08-18-1939-v50-resten-af-genimporten.md``
(Fase B):

1. Paragraphs are preserved: runs of two or more ``\\n`` collapse to exactly
   ``\\n\\n``.
2. A lone ``\\n`` (not preceded by a hyphen) becomes a single space. Pre-
   existing double spaces are never collapsed beyond the one space this
   rule introduces.
3. A hyphen immediately followed by exactly one ``\\n`` (``X-\\nY``) is a
   line-wrap hyphenation candidate:
   - ``Y`` starts lower-case  -> word-split, contract to ``XY``.
   - ``Y`` starts upper-case  -> compound candidate, keep the hyphen, drop
     only the newline (``X-Y``).
   - The corpus (the full Calamari OCR text) breaks a tie: if ``XY``
     appears unbroken elsewhere but ``X-Y`` does not (or vice versa), that
     form wins regardless of case.
   - If the corpus is inconclusive (both or neither form present) and case
     is the only signal, the upper-case default is kept **and** a
     ``hyphen_ambiguous`` flag is emitted -- fail-closed, never a silent
     guess.
   - If either side of the hyphen is not a genuine letter run (e.g. a
     numeral range ``1735-\\n50``, or an abbreviation-period immediately
     before the hyphen such as ``Sek.-\\nMajor``), this is not the
     illustrated word-hyphenation pattern at all: nothing is merged or
     rejoined, the two raw characters are left untouched, and a
     ``hyphen_ambiguous`` flag is emitted.
4. A leading sibling ordinal ``^\\d{1,2}\\.\\s+`` is stripped after an
   initial ``lstrip()`` (numbering survives elsewhere -- record keys,
   identity register, verbatim -- so this is presentation-layer only).
   A leading digit run that looks like an ordinal but does not fit that
   exact shape (missing the period, or wrapped in a closing paren) is left
   untouched and flagged ``ordinal_ambiguous`` -- never stripped by guess.
5. No other changes: punctuation, spelling, ae/oe/aa, OCR errors etc. are
   untouched -- this is evidence, not editing.
6. This module is version ``narrative_norm_v1``.

The function is pure (no I/O): callers pass in ``corpus`` (the full
Calamari text) for the hyphen tie-break lookups.

Rule application order and why it matters
------------------------------------------
Rules are applied in a single left-to-right scan in this order: (1) lstrip +
ordinal handling, (2) paragraph normalization, (3) hyphen-at-linebreak,
(4) soft linebreak -> space. The order resolves two interference cases:

- Ordinal after a leading ``\\n``: ``lstrip()`` removes the leading newline
  *before* the ordinal regex is tried, so ``"\\n2. Foo"`` strips correctly.
- Hyphen at a paragraph boundary: because paragraph collapsing always runs
  first and only ever leaves runs of exactly one or exactly two ``\\n``
  behind, the hyphen rule -- which only fires for *exactly one* trailing
  newline -- never fires across a genuine paragraph break. A hyphen
  immediately followed by a real paragraph break (``X-\\n\\n\\nY``, which
  collapses to ``X-\\n\\nY``) is therefore left completely untouched by the
  hyphen rule; only the newline run itself was normalized to ``\\n\\n``.
  This also protects embedded ``### PAGE nnnn ###`` markers that sit inside
  a person's verbatim span when it crosses a PDF page boundary: a
  hyphenated word broken across such a marker (``Med-\\n\\n### PAGE 0053
  ###\\nlem``) is never merged or treated as a compound -- rejoining across
  a page marker is out of scope for this transform.
"""
from __future__ import annotations

from typing import Dict, List, TypedDict

VERSION = "narrative_norm_v1"

_ORDINAL_OK_PREFIX_LEN = 2  # max digits considered for a sibling ordinal
_CONTEXT_RADIUS = 40


class Flag(TypedDict):
    kind: str
    context: str
    char_offset: int


class Applied(TypedDict):
    soft_breaks_joined: int
    hyphens_merged: int
    hyphens_kept_compound: int
    ordinal_stripped: int


class NormalizeResult(TypedDict):
    text: str
    flags: List[Flag]
    applied: Applied


def _context(raw: str, offset: int) -> str:
    lo = max(0, offset - _CONTEXT_RADIUS)
    hi = min(len(raw), offset + _CONTEXT_RADIUS)
    return raw[lo:hi]


def _match_ordinal_ok(remainder: str) -> int:
    """Return the length of a matched ``^\\d{1,2}\\.\\s+`` prefix, or 0."""
    i = 0
    n = len(remainder)
    while i < n and remainder[i].isdigit() and i < _ORDINAL_OK_PREFIX_LEN:
        i += 1
    if i == 0 or i >= n or remainder[i] != ".":
        return 0
    j = i + 1
    k = j
    while k < n and remainder[k].isspace():
        k += 1
    if k == j:
        return 0
    return k


def _match_ordinal_ambiguous(remainder: str) -> int:
    """Return the length of an ordinal-*looking* but non-conforming prefix.

    Covers the two known OCR variants: a digit run with no period
    (``"7 Heinrich..."``) or a digit run closed by ``")"`` instead of a
    period (``"2) Greve..."``). Returns 0 if nothing ordinal-shaped is
    present at all (the "no ordinal" bucket, left silently untouched).
    """
    i = 0
    n = len(remainder)
    while i < n and remainder[i].isdigit() and i < _ORDINAL_OK_PREFIX_LEN:
        i += 1
    if i == 0:
        return 0
    j = i
    if j < n and remainder[j] == ")":
        j += 1
    k = j
    while k < n and remainder[k].isspace():
        k += 1
    if k == j:
        return 0
    return k


def _word_run_before(raw: str, hyphen_index: int, floor: int) -> str:
    start = hyphen_index
    while start > floor and raw[start - 1].isalpha():
        start -= 1
    return raw[start:hyphen_index]


def _word_run_after(raw: str, start: int) -> str:
    end = start
    n = len(raw)
    while end < n and raw[end].isalpha():
        end += 1
    return raw[start:end]


def normalize_narrative_v1(raw: str, corpus: str) -> NormalizeResult:
    """Dewrap + ordinal-strip ``raw`` per the ``narrative_norm_v1`` contract.

    Pure and deterministic: identical inputs always produce an identical
    result (including flag order). ``corpus`` is only ever read via ``in``
    membership checks on unbroken candidate forms -- no other regex or
    heuristics beyond what is documented on the module.
    """
    flags: List[Flag] = []
    applied: Applied = {
        "soft_breaks_joined": 0,
        "hyphens_merged": 0,
        "hyphens_kept_compound": 0,
        "ordinal_stripped": 0,
    }

    lstripped = raw.lstrip()
    pos = len(raw) - len(lstripped)
    content_floor = pos

    remainder = raw[pos:]
    ok_len = _match_ordinal_ok(remainder)
    if ok_len:
        applied["ordinal_stripped"] = 1
        pos += ok_len
        content_floor = pos
    else:
        amb_len = _match_ordinal_ambiguous(remainder)
        if amb_len:
            flags.append(
                {
                    "kind": "ordinal_ambiguous",
                    "context": _context(raw, pos),
                    "char_offset": pos,
                }
            )
        # else: genuinely no ordinal at this position -- left untouched,
        # unflagged (the "50 without" bucket).

    out: List[str] = []
    i = pos
    n = len(raw)
    while i < n:
        ch = raw[i]

        if (
            ch == "-"
            and i + 1 < n
            and raw[i + 1] == "\n"
            and not (i + 2 < n and raw[i + 2] == "\n")
        ):
            x_word = _word_run_before(raw, i, content_floor)
            y_word = _word_run_after(raw, i + 2)

            if not x_word or not y_word:
                # Not the illustrated word-hyphenation pattern (a numeral
                # range, an abbreviation period, or nothing left to join
                # to) -- fail closed: leave both characters exactly as
                # they are and flag for human review.
                out.append(raw[i : i + 2])
                flags.append(
                    {
                        "kind": "hyphen_ambiguous",
                        "context": _context(raw, i),
                        "char_offset": i,
                    }
                )
                i += 2
                continue

            joined = x_word + y_word
            hyphenated = x_word + "-" + y_word
            joined_in_corpus = joined in corpus
            hyphenated_in_corpus = hyphenated in corpus

            if joined_in_corpus and not hyphenated_in_corpus:
                keep_hyphen = False
            elif hyphenated_in_corpus and not joined_in_corpus:
                keep_hyphen = True
            else:
                # Corpus inconclusive (both or neither present) -- fall
                # back to the case-based default from the contract.
                keep_hyphen = y_word[0].isupper()
                if keep_hyphen:
                    flags.append(
                        {
                            "kind": "hyphen_ambiguous",
                            "context": _context(raw, i),
                            "char_offset": i,
                        }
                    )
                # Lower-case default (word-split) is the common, low-risk
                # case and is not flagged -- case is the "only signal"
                # clause in the contract applies to the upper-case branch.

            y_start = i + 2
            y_end = y_start + len(y_word)
            if keep_hyphen:
                out.append("-" + y_word)
                applied["hyphens_kept_compound"] += 1
            else:
                out.append(y_word)
                applied["hyphens_merged"] += 1
            i = y_end
            continue

        if ch == "\n":
            j = i
            while j < n and raw[j] == "\n":
                j += 1
            run_len = j - i
            if run_len >= 2:
                out.append("\n\n")
            else:
                out.append(" ")
                applied["soft_breaks_joined"] += 1
            i = j
            continue

        out.append(ch)
        i += 1

    return {"text": "".join(out), "flags": flags, "applied": applied}
