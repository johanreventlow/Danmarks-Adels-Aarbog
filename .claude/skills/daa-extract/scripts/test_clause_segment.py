import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import clause_ledger
import clause_segment
import evidence_extract

FIXTURE = os.path.join(os.path.dirname(__file__), "tests", "fixtures", "evidence-clauses.synthetic.json")


def rules():
    return evidence_extract.load_profile("daa-2018-20-v1")["clause_rules"]


class TestClauseSegment(unittest.TestCase):
    def setUp(self):
        with open(FIXTURE, encoding="utf-8") as fh:
            self.cases = json.load(fh)["cases"]
        self.rules = rules()

    def test_fixture_cases_segment_as_expected(self):
        for case in self.cases:
            with self.subTest(case["key"]):
                result = clause_segment.build_record_ledger(case["key"], f"source-evidence:{case['key']}", case["text"], self.rules)
                clause_ledger.validate_ledger(result["ledger"], case["text"])
                self.assertEqual(len(result["clauses"]), case["expect_clauses"])
                flags = sorted({flag for clause in result["clauses"] for flag in clause["flags"]})
                self.assertEqual(flags, sorted(case["expect_flags"]))
                structural = sum(1 for c in result["clauses"] if c["classification"] == "structural_header")
                self.assertEqual(structural, case.get("expect_structural", 0))
                self.assertEqual(result["gap_violations"], [])

    def test_clauses_are_exact_substrings_with_one_based_ordinals(self):
        text = self.cases[0]["text"]
        result = clause_segment.build_record_ledger("k", "source-evidence:k", text, self.rules)
        for expected_ordinal, clause in enumerate(result["clauses"], 1):
            self.assertEqual(clause["ordinal"], expected_ordinal)
            self.assertEqual(text[clause["char_from"]:clause["char_to"]], clause["verbatim_text"])
            self.assertNotEqual(clause["verbatim_text"].strip(), "")

    def test_ledger_never_carries_uuids_and_uses_record_scoped_ids(self):
        result = clause_segment.build_record_ledger("rec-1", "source-evidence:rec-1", self.cases[0]["text"], self.rules)
        for row in result["ledger"]:
            self.assertEqual(row["occurrence_id"], "source-evidence:rec-1")
            for oid in row["observation_ids"]:
                self.assertRegex(oid, r"^rec-1#\d+$")

    def test_gap_outside_charset_is_reported_not_swallowed(self):
        # Efterfølgende NBSP bliver et layout-span (ingen hård fejl på whitespace i enderne),
        # og NBSP står ikke i gap_charset -> rapporteres, ikke slugt.
        text = "Alfa Bravo, f. 1801. Gift 1830 m. Charlie.\u00a0"
        result = clause_segment.build_record_ledger("k", "source-evidence:k", text, self.rules)
        self.assertEqual(result["gap_violations"], ["\u00a0"])
        self.assertEqual(len(result["clauses"]), 2)

    def test_non_gap_whitespace_between_clauses_is_flagged_not_swallowed(self):
        # ". " + NBSP splitter ikke (næste tegn er ikke stort); klausulen bliver én, men flagges.
        text = "Alfa Bravo, f. 1801.\u00a0Gift 1830 m. Charlie."
        result = clause_segment.build_record_ledger("k", "source-evidence:k", text, self.rules)
        self.assertEqual(len(result["clauses"]), 1)
        self.assertIn("non_gap_whitespace_in_clause", result["clauses"][0]["flags"])

    def test_leading_and_trailing_whitespace_become_layout_spans(self):
        text = "  Alfa Bravo, f. 1801. "
        result = clause_segment.build_record_ledger("k", "source-evidence:k", text, self.rules)
        self.assertEqual(result["ledger"][0]["classification"], "layout")
        self.assertEqual(result["ledger"][-1]["classification"], "layout")
        self.assertEqual(result["gap_violations"], [])

    def test_ledger_sha_is_stable_for_same_input(self):
        a = clause_segment.build_record_ledger("k", "source-evidence:k", self.cases[0]["text"], self.rules)
        b = clause_segment.build_record_ledger("k", "source-evidence:k", self.cases[0]["text"], self.rules)
        self.assertEqual(a["ledger_sha256"], b["ledger_sha256"])
        self.assertRegex(a["ledger_sha256"], r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
