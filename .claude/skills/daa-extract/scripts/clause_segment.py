#!/usr/bin/env python3
"""Deterministisk klausul-segmentering af én helpost (spec #148, 4.1b).

Ingen modelkald. Reglerne kommer fra udgaveprofilen; motoren kender kun
mekanikken. Tvivl segmenteres konservativt (længere klausul) og flagges.
Alle offsets er helpost-relative.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Mapping

import clause_ledger

FLAGS = ("unknown_abbreviation", "unbalanced_parentheses", "short_clause",
         "multiple_marriages", "uncertain_marker", "non_gap_whitespace_in_clause",
         "section_numeral")
_MARRIAGE_RE = re.compile(r"\bgift\b", re.IGNORECASE)
_WORD_BEFORE_DOT_RE = re.compile(r"(\S+)\.$")


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _is_non_terminal(prefix: str, rules: Mapping[str, Any]) -> tuple[bool, bool]:
    """Returnér (må ikke splittes her, ukendt kort token). prefix slutter på '.'"""
    match = _WORD_BEFORE_DOT_RE.search(prefix)
    if not match:
        return False, False
    token = match.group(1) + "."
    if token in rules["non_terminal_abbreviations"]:
        return True, False
    # Forkortelser bag en åbnende parentes bærer parentesen med i tokenet:
    # "(ca." ville ellers ikke findes i listen, selv om "ca." står der.
    if token.lstrip("([") in rules["non_terminal_abbreviations"]:
        return True, False
    # Valgfri regel (review 35, P3): listen slås op uden hensyn til store/små bogstaver,
    # så "Bd." ved sætningsstart dækkes af "bd.".  Uden nøglen: uændret, eksakt opslag.
    if rules.get("abbreviation_match") == "case_insensitive":
        folded = {a.casefold() for a in rules["non_terminal_abbreviations"]}
        if token.casefold() in folded or token.lstrip("([").casefold() in folded:
            return True, False
    # Et punktum EFTER en lukkeparentes afslutter sætningen — "(5000 Kr.). Gift".
    # Uden denne regel fanger flerpunkts-reglen nedenfor "Kr.)." og smelter to
    # ægte klausuler sammen.
    if match.group(1).endswith((")", "]")):
        return False, False
    if re.search(rules["initial_pattern"], prefix):
        return True, False
    if re.search(rules["ordinal_number_pattern"], prefix):
        return True, False
    bare = match.group(1).strip("()[]")
    if bare and bare.isalpha() and len(bare) <= 4 and not bare[0].isupper():
        return True, True  # ukendt kort forkortelse: split ikke, men flag
    # Flerpunkts-forkortelser (s.å., cand.jur., D.M., R.St. …): bare.isalpha() er
    # falsk på grund af den indlejrede prik, så tokenet hverken blokerede eller
    # flagede — splitten skete tavst midt i en titel eller en dekoration.
    # Tvivl segmenteres konservativt og flagges, som resten af motoren.
    inner = bare.strip(".")
    def _wordish(part: str) -> bool:
        stripped = part.replace("-", "")
        return bool(stripped) and (stripped.isalpha() or stripped.isdigit())

    if inner and "." in bare and all(_wordish(part) for part in inner.split(".") if part):
        return True, True
    return False, False


def _numeral_heads_sentence(text: str, pos: int, pattern: str) -> bool:
    """Står et fritstående romertal ved pos, fulgt af mellemrum og et versal? (#189)"""
    end = pos
    while end < len(text) and not text[end].isspace():
        end += 1
    if end == pos or not re.search(pattern, text[pos:end]):
        return False
    after = end
    while after < len(text) and text[after].isspace():
        after += 1
    return after > end and after < len(text) and text[after].isupper()


def _numeral_after_terminator(prefix: str, pattern: str, rules: Mapping[str, Any]) -> bool:
    """Er tokenet, prefix slutter på, et romertal, der selv står lige efter et sætningstegn? (#189)"""
    match = re.search(r"(?:^|(?<=\s))(\S+)$", prefix)
    if not match or not re.search(pattern, match.group(1)):
        return False
    before = prefix[:match.start()]
    if not before or not before[-1].isspace():
        return False
    return before.rstrip().endswith(tuple(t.rstrip() for t in rules["terminators"] if t.strip()))


def _split_points(text: str, rules: Mapping[str, Any]) -> list[tuple[int, list[str]]]:
    """Positioner (indeks i text hvor en ny klausul begynder) + flag for den klausul, der slutter der."""
    points: list[tuple[int, list[str]]] = []
    # Valgfri regel (#189): et fritstående romertal mellem to sætningstegn — fx en
    # henvisning eller et afsnitsnummer midt i en sætning — klipper ikke sætningen i
    # tre. Hverken før eller efter tallet splittes; klausulen bliver længere og flages
    # (samme konservative linje som resten af motoren). Uden nøglen: uændret adfærd.
    numeral = rules.get("section_numeral_pattern")
    for terminator in rules["terminators"]:
        start = 0
        while True:
            idx = text.find(terminator, start)
            if idx < 0:
                break
            end_of_clause = idx + len(terminator.rstrip())
            next_start = idx + len(terminator)
            # Spring yderligere whitespace over, før næste tegn bedømmes. Uden dette
            # forhindrer et dobbelt mellemrum (eller et linjeskift) stiltiende en split:
            # næste tegn er da whitespace, ikke et versal, og de to klausuler smelter
            # sammen UDEN flag. Whitespacen bliver i stedet et layout-span, og et
            # tegn uden for gap_charset dukker op som gap_violation, hvor det kan måles.
            while next_start < len(text) and text[next_start].isspace():
                next_start += 1
            flags: list[str] = []
            if terminator.startswith("."):
                blocked, unknown = _is_non_terminal(text[:idx + 1], rules)
                if unknown:
                    flags.append("unknown_abbreviation")
                if blocked:
                    if unknown:
                        points.append((-next_start, flags))  # negativ = kun flag, ingen split
                    start = next_start
                    continue
            nxt = text[next_start:next_start + 1]
            if nxt and (nxt.isupper() or nxt.isdigit() or nxt in "†([\"“"):
                if numeral and (_numeral_heads_sentence(text, next_start, numeral)
                                or (terminator.startswith(".") and nxt.isupper()
                                    and _numeral_after_terminator(text[:idx + 1], numeral, rules))):
                    points.append((-next_start, flags + ["section_numeral"]))  # kun flag, ingen split
                else:
                    points.append((next_start, flags))
            start = next_start
    return points


def segment_clauses(text: str, rules: Mapping[str, Any]) -> list[dict[str, Any]]:
    # Førende/efterfølgende whitespace og linjeskift bliver layout-spans og måles som
    # gap-tegn i build_record_ledger; kun tom tekst er en hård fejl.
    if not text or not text.strip():
        raise ValueError("CLAUSE_TEXT_EMPTY")
    raw_points = _split_points(text, rules)
    starts = sorted({p for p, _ in raw_points if p > 0})
    pending_flags: dict[int, list[str]] = {}
    for p, flags in raw_points:
        pending_flags.setdefault(abs(p), []).extend(flags)
    bounds = [0] + starts + [len(text)]
    clauses: list[dict[str, Any]] = []
    for a, b in zip(bounds, bounds[1:]):
        piece = text[a:b]
        lead = len(piece) - len(piece.lstrip())
        trail = len(piece) - len(piece.rstrip())
        if lead:
            clauses.append({"char_from": a, "char_to": a + lead, "classification": "layout", "flags": []})
        cf, ct = a + lead, b - trail
        if ct > cf:
            flags = sorted(set(f for pos, fl in pending_flags.items() if cf < pos <= ct for f in fl))
            clause_text = text[cf:ct]
            if clause_text.count("(") != clause_text.count(")") or clause_text.count("[") != clause_text.count("]"):
                flags.append("unbalanced_parentheses")
            if len(_MARRIAGE_RE.findall(clause_text)) > 1:
                flags.append("multiple_marriages")
            if "?" in clause_text:
                flags.append("uncertain_marker")
            if len(clause_text) < rules["min_clause_chars"]:
                flags.append("short_clause")
            # Whitespace inde i klausulen, som ikke er et tilladt mellemrumstegn (NBSP, linjeskift):
            # segmenteringen kan have sluppet en klausulgrænse, så det flagges frem for at forsvinde.
            if any(ch.isspace() and ch not in rules["gap_charset"] for ch in clause_text):
                flags.append("non_gap_whitespace_in_clause")
            classification = "structural_header" if any(re.search(p, clause_text) for p in rules["structural_header_patterns"]) else "record_text"
            clauses.append({"char_from": cf, "char_to": ct, "classification": classification, "flags": sorted(set(flags))})
        if trail:
            clauses.append({"char_from": ct, "char_to": b, "classification": "layout", "flags": []})
    # Ubalanceret parentes: flet klausulerne fra den åbne parentes og frem til én (konservativt).
    merged: list[dict[str, Any]] = []
    open_depth = 0
    for clause in clauses:
        piece = text[clause["char_from"]:clause["char_to"]]
        if merged and merged[-1]["classification"] != "layout" and clause["classification"] != "layout" and open_depth > 0:
            last = merged[-1]
            last["char_to"] = clause["char_to"]
            last["flags"] = sorted(set(last["flags"]) | set(clause["flags"]) | {"unbalanced_parentheses"})
            # opslug layout-spannet mellem de to
            if len(merged) >= 2 and merged[-2]["classification"] == "layout" and merged[-2]["char_to"] == last["char_from"]:
                pass
        else:
            merged.append(dict(clause))
        if clause["classification"] != "layout":
            open_depth += piece.count("(") - piece.count(")")
            open_depth = max(open_depth, 0)
    # Efter fletning kan layout-spans ligge inde i en flettet klausul; fjern dem.
    result: list[dict[str, Any]] = []
    for clause in merged:
        if result and clause["char_from"] < result[-1]["char_to"]:
            continue
        result.append(clause)
    # Sammenhængende dækning: layout-spans mellem klausuler, der ikke længere findes, genskabes.
    filled: list[dict[str, Any]] = []
    cursor = 0
    for clause in result:
        if clause["char_from"] > cursor:
            filled.append({"char_from": cursor, "char_to": clause["char_from"], "classification": "layout", "flags": []})
        filled.append(clause)
        cursor = clause["char_to"]
    if cursor < len(text):
        filled.append({"char_from": cursor, "char_to": len(text), "classification": "layout", "flags": []})
    for clause in filled:
        clause["verbatim_text"] = text[clause["char_from"]:clause["char_to"]]
    return filled


def build_record_ledger(record_key: str, occurrence_key: str, text: str, rules: Mapping[str, Any]) -> dict[str, Any]:
    if not record_key or not occurrence_key:
        raise ValueError("CLAUSE_RECORD_KEYS_REQUIRED")
    pieces = segment_clauses(text, rules)
    ordinal = 0
    ledger_input = []
    clauses = []
    gap_violations: list[str] = []
    for piece in pieces:
        if piece["classification"] == "layout":
            for ch in piece["verbatim_text"]:
                if ch not in rules["gap_charset"] and ch not in gap_violations:
                    gap_violations.append(ch)
            ledger_input.append({"char_from": piece["char_from"], "char_to": piece["char_to"], "classification": "layout",
                                 "observation_ids": [], "occurrence_id": occurrence_key, "record_key": record_key})
            continue
        ordinal += 1
        observation_id = f"{record_key}#{ordinal}"
        ledger_input.append({"char_from": piece["char_from"], "char_to": piece["char_to"],
                             "classification": piece["classification"], "observation_ids": [observation_id],
                             "occurrence_id": occurrence_key, "record_key": record_key})
        clauses.append({"ordinal": ordinal, "char_from": piece["char_from"], "char_to": piece["char_to"],
                        "classification": piece["classification"], "flags": piece["flags"],
                        "verbatim_text": piece["verbatim_text"],
                        "verbatim_sha256": hashlib.sha256(piece["verbatim_text"].encode("utf-8")).hexdigest()})
    ledger = clause_ledger.build_ledger(text, ledger_input)
    clause_ledger.validate_ledger(ledger, text)
    ledger_sha256 = hashlib.sha256(_canonical([{k: v for k, v in row.items() if k != "verbatim_text"} for row in ledger]).encode("utf-8")).hexdigest()
    return {"record_key": record_key, "occurrence_key": occurrence_key, "rules_version": rules["version"],
            "ledger": ledger, "clauses": clauses, "gap_violations": gap_violations, "ledger_sha256": ledger_sha256}
