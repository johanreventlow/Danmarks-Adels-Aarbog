"""Paritet for klausulsættets hash mellem Python og private.clause_set_sha256 (SQL)."""
import hashlib
import json
from pathlib import Path

import clause_set

FIXTURE = Path(__file__).resolve().parents[4] / "tests" / "fixtures" / "clause-set-sha256.json"


def _payload_clauses(fixture):
    """Fixturens felter i manifest-/payloadform (char_* = post-relativ, rendition_char_* = absolut)."""
    return [{"ordinal": c["ordinal"], "char_from": c["post_char_from"], "char_to": c["post_char_to"],
             "rendition_char_from": c["char_from"], "rendition_char_to": c["char_to"],
             "classification": c["classification"], "flags": c["flags"],
             "verbatim_sha256": hashlib.sha256(c["verbatim_text"].encode("utf-8")).hexdigest()}
            for c in fixture["clauses"]]


def test_python_hash_matches_the_pinned_sql_hash():
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert clause_set.clause_set_sha256(_payload_clauses(fixture)) == fixture["clause_set_sha256"]


def test_flag_order_and_duplicates_do_not_matter_but_flags_do():
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    base = _payload_clauses(fixture)
    shuffled = [dict(c, flags=list(reversed(c["flags"])) + c["flags"]) for c in base]
    assert clause_set.clause_set_sha256(shuffled) == clause_set.clause_set_sha256(base)
    assert clause_set.clause_set_sha256([dict(c, flags=[]) for c in base]) != clause_set.clause_set_sha256(base)


def test_clause_order_in_the_input_does_not_matter():
    two = [{"ordinal": 2, "char_from": 5, "char_to": 9, "rendition_char_from": 105, "rendition_char_to": 109,
            "classification": "record_text", "flags": [], "verbatim_sha256": "b" * 64},
           {"ordinal": 1, "char_from": 0, "char_to": 4, "rendition_char_from": 100, "rendition_char_to": 104,
            "classification": "record_text", "flags": [], "verbatim_sha256": "a" * 64}]
    assert clause_set.clause_set_sha256(two) == clause_set.clause_set_sha256(list(reversed(two)))
