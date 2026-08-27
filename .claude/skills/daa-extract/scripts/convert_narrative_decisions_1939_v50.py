#!/usr/bin/env python3
"""Plain-text decision sheet for the DAA 1939 v50 fase-B narrative flags.

Replaces the markdown review sheet's decision UX with the project's known
pattern from the 1939-grænseflade work (human-anchor-adapter): ONE editable
text file + fail-closed structural verification, instead of a hand-edited
JSON or a markdown table nobody can safely bulk-edit.

Two modes:

- ``generate``: reads the (hash-locked) flags file
  (``narrative-replacement-flags-v1.json``, Task 2's output) and writes a
  plain-text decision sheet with all 178 flags, one line each, grouped into
  4 sections, every line prefilled with a recommended ``[TOKEN]``.
- ``convert``: reads the (hash-locked) edited text file + the SAME flags
  file, and validates that EVERY line matches the freshly regenerated
  canonical form byte-for-byte except for the bracketed token -- any other
  edit (context, F-id, page, section headers, line count, line order)
  aborts with the offending line number. Also asserts all 178 F-ids appear
  exactly once and that each token is valid for its flag's kind. Writes
  the decisions JSON in the builder's expected format
  (``build_narrative_replacement_manifest_1939_v50.py --decisions``).

The F-id <-> flag_id mapping is a pure function of the flags file's own
``flags`` list (sorted by ``flag_id``, numbered from 1) -- ``convert`` never
trusts the edited text file for identity, only for the token choice.

Never touches the database; never authorizes writes.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

_SCRIPTS_DIR = Path(__file__).resolve().parent


def _import_normalize_module():
    """Import ``normalize_narrative_1939_v50`` from this same directory via
    ``importlib`` (cwd-independent), mirroring Task 2's builder. Only the
    module's own pure helpers are reused here (composition, never a
    re-derived copy of the transform's rules)."""
    spec = importlib.util.spec_from_file_location(
        "normalize_narrative_1939_v50", _SCRIPTS_DIR / "normalize_narrative_1939_v50.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


_normalize_mod = _import_normalize_module()
_match_ordinal_ambiguous = _normalize_mod._match_ordinal_ambiguous
_word_run_before = _normalize_mod._word_run_before
_word_run_after = _normalize_mod._word_run_after


HASH_RE = re.compile(r"^[0-9a-f]{64}$")

FLAGS_SCHEMA_VERSION = "1939-v50-narrative-replacement-flags-v1"
DECISIONS_SCHEMA_VERSION = "1939-v50-narrative-decisions-v1"

# Matches CONTEXT_RADIUS in build_narrative_replacement_manifest_1939_v50.py
# -- the flags file's own ``context`` field is raw[offset-60:offset+60]
# (clipped at record boundaries). Everything this script displays is
# derived from that ONE field -- no re-reading of phase-a/production
# manifests or the Calamari corpus is needed for either mode.
FLAGS_FILE_CONTEXT_RADIUS = 60
DISPLAY_RADIUS = 50
SNIPPET_MAX_LEN = 30

TOKEN_TO_ACTION = {"[MERGE]": "merge", "[KEEP]": "keep", "[STRIP]": "strip"}
ACTION_TO_TOKEN = {v: k for k, v in TOKEN_TO_ACTION.items()}
VALID_TOKENS_BY_KIND = {
    "hyphen_unproven": {"[MERGE]", "[KEEP]"},
    "hyphen_ambiguous": {"[MERGE]", "[KEEP]"},
    "ordinal_ambiguous": {"[STRIP]", "[KEEP]"},
}
TOKEN_FIELD_WIDTH = 8  # widest token "[MERGE] "/"[STRIP] " = 8 incl. 1 pad space

# Curated override applied ONLY in `generate` mode, on top of the flags
# file's mechanical `suggested_default_action`: the "karog" flag is a
# demonstrated bad merge (see task-3 review analysis) -- the underlying
# text is "1693 kar-\nog 1697 virk. Kapt.", where "kar." is almost
# certainly an abbreviation ("kar[akteriseret]", cf. "kar. Oberst" later
# in the same record) whose period was lost before the hyphen during OCR.
# Merging produces the nonsense word "karog". This does NOT change
# `convert`'s validation rules -- it only changes what `generate` prefills
# as the *recommended* token for this one flag.
CURATED_OVERRIDES: Dict[str, str] = {
    "record-04d54b46-b9ee-423b-833d-5037b0178f0e:100:hyphen_unproven": "keep",
}

STOPWORDS = {
    "og", "i", "at", "en", "et", "til", "for", "med", "som", "er", "var",
    "paa", "af", "den", "det", "de", "der", "har", "kan",
}
VOWELS = set("aeiouyæøåAEIOUYÆØÅüÜöÖäÄ")

SUSPICION_PRIORITY = {
    "stopord-hale": 0, "tomt": 1, "tal-i-ord": 2, "meget-kort": 3,
    "konsonantklynge": 4, "ingen-vokal": 5,
}


class DecisionsFileError(ValueError):
    pass


def _fail(code: str) -> None:
    raise DecisionsFileError(code)


# ---------------------------------------------------------------------------
# Flags-file loading + F-id assignment (the ONLY source of identity)
# ---------------------------------------------------------------------------

def load_flags_document(path: Path, expected_sha256: str) -> Dict[str, Any]:
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected_sha256:
        _fail("DECISIONS_FLAGS_HASH_MISMATCH")
    doc = json.loads(raw)
    if doc.get("schema_version") != FLAGS_SCHEMA_VERSION:
        _fail("DECISIONS_FLAGS_SCHEMA_INVALID")
    flags = doc.get("flags")
    if not isinstance(flags, list) or not flags:
        _fail("DECISIONS_FLAGS_INVALID")
    for f in flags:
        if not isinstance(f, dict) or not all(
            k in f for k in ("flag_id", "kind", "context", "char_offset", "page_from")
        ):
            _fail("DECISIONS_FLAGS_ROW_INVALID")
        if f["kind"] not in VALID_TOKENS_BY_KIND:
            _fail(f"DECISIONS_FLAGS_KIND_UNKNOWN:{f['flag_id']}")
    return doc


def sorted_flags(doc: Dict[str, Any]) -> List[Dict[str, Any]]:
    flags = list(doc["flags"])
    flags.sort(key=lambda f: f["flag_id"])
    ids = [f["flag_id"] for f in flags]
    if len(set(ids)) != len(ids):
        _fail("DECISIONS_FLAGS_DUPLICATE_FLAG_ID")
    return flags


def assign_fids(flags_sorted: List[Dict[str, Any]]) -> Tuple[Dict[str, str], Dict[str, Dict[str, Any]]]:
    """Pure function of the sorted flags list -- the ONLY place F-ids are
    minted. Both `generate` and `convert` call this on the same flags file,
    so the mapping is reconstructed identically every time."""
    fid_by_flag_id: Dict[str, str] = {}
    flag_by_fid: Dict[str, Dict[str, Any]] = {}
    for idx, f in enumerate(flags_sorted, start=1):
        fid = f"F{idx:03d}"
        fid_by_flag_id[f["flag_id"]] = fid
        flag_by_fid[fid] = f
    return fid_by_flag_id, flag_by_fid


# ---------------------------------------------------------------------------
# Per-flag text derivation -- everything computed from the flags file's own
# `context` field (never the raw verbatim_text / phase-a manifests).
# ---------------------------------------------------------------------------

def _local_offset(flag: Dict[str, Any]) -> int:
    off = flag["char_offset"]
    lo = max(0, off - FLAGS_FILE_CONTEXT_RADIUS)
    return off - lo


def _flatten(s: str) -> str:
    return s.replace("\n", "⏎")


def _trim_snippet(text: str, start: int, max_len: int = SNIPPET_MAX_LEN) -> str:
    """text[start:start+max_len], trimmed back to the last space so a word
    is never cut in half (unless the very first run already exceeds
    max_len, in which case it is left as-is)."""
    if start < 0 or start >= len(text):
        return ""
    end = min(len(text), start + max_len)
    snippet = text[start:end]
    if end < len(text) and " " in snippet:
        cut = snippet.rfind(" ")
        if cut > 0:
            snippet = snippet[:cut]
    return snippet.strip()


def _hyphen_words(flag: Dict[str, Any]) -> Tuple[str, str, int]:
    """Returns (x_word, y_word, local_offset) for a hyphen_* flag, read off
    the flags file's own context window."""
    ctx = flag["context"]
    local = _local_offset(flag)
    if local < 0 or local >= len(ctx) or ctx[local] != "-":
        _fail(f"DECISIONS_HYPHEN_OFFSET_MISMATCH:{flag['flag_id']}")
    x_word = _word_run_before(ctx, local, 0)
    y_word = _word_run_after(ctx, local + 2)
    return x_word, y_word, local


def _outcome_fields(flag: Dict[str, Any]) -> Tuple[str, int, int]:
    """Returns (field2_text, mark_lo, mark_hi) -- mark_lo/mark_hi are
    offsets into flag["context"] delimiting the flagged site, for the
    ``field3`` context marker."""
    kind = flag["kind"]
    ctx = flag["context"]
    if kind == "ordinal_ambiguous":
        remainder = ctx  # char_offset is always 0 for this kind
        amb_len = _match_ordinal_ambiguous(remainder)
        if amb_len == 0:
            _fail(f"DECISIONS_ORDINAL_NO_MATCH:{flag['flag_id']}")
        strip_form = _trim_snippet(remainder, amb_len)
        keep_form = _trim_snippet(remainder, 0)
        field2 = f"ved-strip: »{_flatten(strip_form)}« / ved-keep: »{_flatten(keep_form)}«"
        return field2, 0, amb_len
    x_word, y_word, local = _hyphen_words(flag)
    merged = x_word + y_word
    hyphenated = f"{x_word}-{y_word}" if (x_word or y_word) else "-"
    field2 = f"ved-merge: »{_flatten(merged) or '(intet)'}« / ved-keep: »{_flatten(hyphenated)}«"
    mark_lo = local - len(x_word)
    mark_hi = min(len(ctx), local + 2 + len(y_word))
    return field2, mark_lo, mark_hi


def _context_field(flag: Dict[str, Any], mark_lo: int, mark_hi: int) -> str:
    ctx = flag["context"]
    center = 0 if flag["kind"] == "ordinal_ambiguous" else _local_offset(flag)
    lo = max(0, center - DISPLAY_RADIUS)
    hi = min(len(ctx), center + DISPLAY_RADIUS)
    m_lo = max(lo, min(mark_lo, hi))
    m_hi = max(lo, min(mark_hi, hi))
    if m_lo >= m_hi:
        body = _flatten(ctx[lo:hi])
    else:
        body = _flatten(ctx[lo:m_lo]) + "‹" + _flatten(ctx[m_lo:m_hi]) + "›" + _flatten(ctx[m_hi:hi])
    if lo > 0:
        body = "…" + body
    if hi < len(ctx):
        body = body + "…"
    return body


def render_line(flag: Dict[str, Any], fid: str, token: str) -> str:
    field2, mark_lo, mark_hi = _outcome_fields(flag)
    field3 = _context_field(flag, mark_lo, mark_hi)
    token_field = f"{token:<{TOKEN_FIELD_WIDTH}}"
    return f"{token_field}{fid} | {field2} | {field3} | s. {flag['page_from']}"


# ---------------------------------------------------------------------------
# Mistænkeligheds-heuristik (triage sort only, never authoritative) --
# ported self-contained so `convert` needs nothing beyond the flags file.
# ---------------------------------------------------------------------------

def _suspicion_signal(flag: Dict[str, Any]) -> str:
    if flag["kind"] != "hyphen_unproven":
        return ""
    x_word, y_word, _ = _hyphen_words(flag)
    merged = x_word + y_word
    if y_word.lower() in STOPWORDS:
        return "stopord-hale"
    if not merged:
        return "tomt"
    if any(c.isdigit() for c in merged):
        return "tal-i-ord"
    if len(merged) <= 3:
        return "meget-kort"
    max_run = 0
    run = 0
    for c in merged:
        if c.isalpha() and c not in VOWELS:
            run += 1
            max_run = max(max_run, run)
        else:
            run = 0
    if max_run >= 4:
        return "konsonantklynge"
    if not any(c in VOWELS for c in merged):
        return "ingen-vokal"
    return ""


def _merged_word(flag: Dict[str, Any]) -> str:
    x_word, y_word, _ = _hyphen_words(flag)
    return x_word + y_word


def partition_sections(flags_sorted: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    ordinal = [f for f in flags_sorted if f["kind"] == "ordinal_ambiguous"]
    hyphen_amb = [f for f in flags_sorted if f["kind"] == "hyphen_ambiguous"]
    hyphen_unproven = [f for f in flags_sorted if f["kind"] == "hyphen_unproven"]

    signals = {f["flag_id"]: _suspicion_signal(f) for f in hyphen_unproven}
    suspicious = [f for f in hyphen_unproven if signals[f["flag_id"]]]
    rest = [f for f in hyphen_unproven if not signals[f["flag_id"]]]

    suspicious.sort(key=lambda f: (SUSPICION_PRIORITY[signals[f["flag_id"]]], _merged_word(f).lower(), f["flag_id"]))
    rest.sort(key=lambda f: (_merged_word(f).lower(), f["flag_id"]))

    return {
        "suspicious": suspicious,
        "hyphen_ambiguous": hyphen_amb,
        "ordinal": ordinal,
        "rest": rest,
    }


# ---------------------------------------------------------------------------
# Document assembly (shared by `generate` and `convert`'s regeneration
# check, so the two can never drift apart)
# ---------------------------------------------------------------------------

INSTRUCTIONS = (
    "RET KUN TOKENET I KANTET PARENTES PÅ LINJER DU ER UENIG I.\n"
    "Alt andet på linjen (F-id, kontekst, sidetal) må ikke ændres.\n"
    "[MERGE] = sammentræk de to orddele til ét ord (fjern bindestregen).\n"
    "[KEEP]  = behold bindestregen (ordet forbliver delt/sammensat).\n"
    "Ordenstal-flags bruger i stedet [STRIP] (fjern det formodede ordenstal) / [KEEP] (lad det stå).\n"
)

SECTION_TITLES = {
    "suspicious": "KIG PÅ DISSE ({n} mistænkelige)",
    "hyphen_ambiguous": "TVETYDIGE BINDESTREGER ({n})",
    "ordinal": "ORDENSTAL ({n})",
    "rest": "ØVRIGE SAMMENTRÆKNINGER ({n}) — forventeligt bare OK",
}
SECTION_ORDER = ["suspicious", "hyphen_ambiguous", "ordinal", "rest"]


def render_document(flags_sorted: List[Dict[str, Any]], tokens_by_flag_id: Dict[str, str]) -> str:
    fid_by_flag_id, _ = assign_fids(flags_sorted)
    sections = partition_sections(flags_sorted)
    lines: List[str] = [INSTRUCTIONS.rstrip("\n")]
    for key in SECTION_ORDER:
        group = sections[key]
        lines.append("")
        lines.append("== " + SECTION_TITLES[key].format(n=len(group)) + " ==")
        for f in group:
            fid = fid_by_flag_id[f["flag_id"]]
            token = tokens_by_flag_id[f["flag_id"]]
            lines.append(render_line(f, fid, token))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# generate
# ---------------------------------------------------------------------------

def default_tokens(flags_sorted: List[Dict[str, Any]]) -> Dict[str, str]:
    tokens: Dict[str, str] = {}
    for f in flags_sorted:
        action = CURATED_OVERRIDES.get(f["flag_id"], f["suggested_default_action"])
        token = ACTION_TO_TOKEN.get(action)
        if token is None or token not in VALID_TOKENS_BY_KIND[f["kind"]]:
            _fail(f"DECISIONS_DEFAULT_ACTION_INVALID:{f['flag_id']}")
        tokens[f["flag_id"]] = token
    return tokens


def generate_document(flags_doc: Dict[str, Any], *, expected_flag_count: Optional[int] = None) -> str:
    flags_sorted = sorted_flags(flags_doc)
    if expected_flag_count is not None and len(flags_sorted) != expected_flag_count:
        _fail(f"DECISIONS_FLAG_COUNT_UNEXPECTED:{len(flags_sorted)}")
    tokens = default_tokens(flags_sorted)
    return render_document(flags_sorted, tokens)


# ---------------------------------------------------------------------------
# convert
# ---------------------------------------------------------------------------

_DECISION_HEAD_RE = re.compile(r"^(\[[A-Z]+\])([ \t]+)(F\d{3})(?=[ \t])")


def _parse_positional(line: str) -> Optional[Tuple[str, str]]:
    """Extract (token, fid) from a candidate decision line.

    The token field's padding is deliberately NOT part of the contract:
    replacing `[MERGE]` with the shorter `[KEEP]` in place shifts the
    column, which is exactly what a human editor does. Everything after
    the F-id stays byte-exact (enforced in `convert_edited_document`)."""
    match = _DECISION_HEAD_RE.match(line)
    if match is None:
        return None
    return match.group(1), match.group(3)


def _canonical_for_compare(line: str) -> str:
    """Collapse only the whitespace run between token and F-id, so the
    byte-identity gate ignores re-alignment but nothing else."""
    match = _DECISION_HEAD_RE.match(line)
    if match is None:
        return line
    return f"{match.group(1)} {line[match.end(2):]}"


def convert_edited_document(
    flags_doc: Dict[str, Any], edited_text: str, *, expected_flag_count: Optional[int] = None
) -> Dict[str, str]:
    """Validates `edited_text` against the flags file and returns the
    decisions dict ({flag_id: action}) ready for the builder's
    ``--decisions`` JSON. Raises DecisionsFileError (fail-closed) on any
    structural deviation."""
    flags_sorted = sorted_flags(flags_doc)
    if expected_flag_count is not None and len(flags_sorted) != expected_flag_count:
        _fail(f"DECISIONS_FLAG_COUNT_UNEXPECTED:{len(flags_sorted)}")
    fid_by_flag_id, flag_by_fid = assign_fids(flags_sorted)
    all_fids = set(fid_by_flag_id.values())

    edited_lines = edited_text.split("\n")
    if edited_lines and edited_lines[-1] == "":
        edited_lines = edited_lines[:-1]  # trailing newline -> no phantom empty line

    tokens_by_fid: Dict[str, str] = {}
    fid_line_no: Dict[str, int] = {}
    for lineno, line in enumerate(edited_lines, start=1):
        parsed = _parse_positional(line)
        if parsed is None:
            if " | " in line and re.match(r"^\[[A-Z]*\]", line):
                _fail(f"DECISIONS_LINE_MALFORMED:{lineno}")
            continue
        token, fid = parsed
        if fid not in flag_by_fid:
            _fail(f"DECISIONS_UNKNOWN_FID:{lineno}:{fid}")
        if fid in tokens_by_fid:
            _fail(f"DECISIONS_DUPLICATE_FID:{fid}:lines={fid_line_no[fid]},{lineno}")
        tokens_by_fid[fid] = token
        fid_line_no[fid] = lineno

    missing = all_fids - set(tokens_by_fid)
    if missing:
        _fail(f"DECISIONS_MISSING_FID:{','.join(sorted(missing))}")

    # Token validity per flag's kind -- independent of the byte-identity
    # check below (a well-formed-but-wrong token would otherwise pass a
    # naive regeneration comparison, since render_line formats any bracket
    # token literally).
    for fid, flag in flag_by_fid.items():
        token = tokens_by_fid[fid]
        if token not in VALID_TOKENS_BY_KIND[flag["kind"]]:
            _fail(f"DECISIONS_TOKEN_INVALID_FOR_KIND:{flag['flag_id']}:{token}")

    # Fail-closed structural check: regenerate the ENTIRE expected document
    # using the tokens found in the edited file, and require it to be
    # byte-identical line-for-line. This is what actually enforces "nothing
    # but the token changed" -- the positional token/F-id parse above only
    # extracts candidates; this is the real gate.
    tokens_by_flag_id = {flag_by_fid[fid]["flag_id"]: tok for fid, tok in tokens_by_fid.items()}
    expected_text = render_document(flags_sorted, tokens_by_flag_id)
    expected_lines = expected_text.split("\n")
    if expected_lines and expected_lines[-1] == "":
        expected_lines = expected_lines[:-1]

    if len(expected_lines) != len(edited_lines):
        _fail(f"DECISIONS_LINE_COUNT_MISMATCH:expected={len(expected_lines)}:actual={len(edited_lines)}")
    for lineno, (exp, act) in enumerate(zip(expected_lines, edited_lines), start=1):
        if _canonical_for_compare(exp) != _canonical_for_compare(act):
            _fail(f"DECISIONS_LINE_MISMATCH:{lineno}")

    return {flag_by_fid[fid]["flag_id"]: TOKEN_TO_ACTION[tok] for fid, tok in tokens_by_fid.items()}


def build_decisions_document(decisions: Dict[str, str]) -> Dict[str, Any]:
    return {"schema_version": DECISIONS_SCHEMA_VERSION, "decisions": decisions}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="mode", required=True)

    g = sub.add_parser("generate")
    g.add_argument("--flags-file", required=True)
    g.add_argument("--flags-file-sha256", required=True)
    g.add_argument("--output", required=True)
    g.add_argument("--expected-flag-count", type=int, default=None)

    c = sub.add_parser("convert")
    c.add_argument("--flags-file", required=True)
    c.add_argument("--flags-file-sha256", required=True)
    c.add_argument("--edited-file", required=True)
    c.add_argument("--edited-file-sha256", required=True)
    c.add_argument("--output", required=True)
    c.add_argument("--expected-flag-count", type=int, default=None)

    a = p.parse_args(argv)

    output = Path(a.output)
    if output.exists():
        _fail("DECISIONS_OUTPUT_EXISTS")

    flags_doc = load_flags_document(Path(a.flags_file), a.flags_file_sha256)

    if a.mode == "generate":
        text = generate_document(flags_doc, expected_flag_count=a.expected_flag_count)
        output.write_text(text, encoding="utf-8")
        print(json.dumps({"output": str(output), "lines": text.count(chr(10))}, sort_keys=True))
        return 0

    edited_raw = Path(a.edited_file).read_bytes()
    if hashlib.sha256(edited_raw).hexdigest() != a.edited_file_sha256:
        _fail("DECISIONS_EDITED_FILE_HASH_MISMATCH")
    edited_text = edited_raw.decode("utf-8")

    decisions = convert_edited_document(flags_doc, edited_text, expected_flag_count=a.expected_flag_count)
    doc = build_decisions_document(decisions)
    output.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "decisions": len(decisions)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
