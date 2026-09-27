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


def rules_v2():
    return evidence_extract.load_profile("daa-2018-20-v2")["clause_rules"]


class TestSectionNumeral(unittest.TestCase):
    """#189: et fritstående romertal mellem to sætningstegn må ikke klippe
    den omgivende sætning i tre. Alle tekster er opfundne."""

    SANDWICH = "Alfa Bravo blev gift 1801 (se Charlie Deltason. VI. Echo Foxtrot) med Golf Hotel, f. 1780."
    SINGLE = "Alfa Bravo blev gift 1801 (se Charlie Deltason. I. Echo Foxtrot) med Golf Hotel, f. 1780."

    def segment(self, text, rules):
        result = clause_segment.build_record_ledger("k", "source-evidence:k", text, rules)
        clause_ledger.validate_ledger(result["ledger"], text)
        self.assertEqual(result["gap_violations"], [])
        return result["clauses"]

    def test_old_profile_is_unchanged_three_clauses_without_flag(self):
        # Reproducerbarhed: den godkendte regelversion skal give præcis det samme som før.
        clauses = self.segment(self.SANDWICH, rules())
        self.assertEqual([len(c["verbatim_text"]) for c in clauses][1], 3)
        self.assertEqual(len(clauses), 3)
        self.assertFalse(any("section_numeral" in c["flags"] for c in clauses))

    def test_old_profile_has_no_section_numeral_rule(self):
        self.assertNotIn("section_numeral_pattern", rules())

    def test_numeral_between_terminators_does_not_split_sentence(self):
        clauses = self.segment(self.SANDWICH, rules_v2())
        self.assertEqual(len(clauses), 1)
        self.assertEqual(clauses[0]["verbatim_text"], self.SANDWICH)
        self.assertEqual(clauses[0]["classification"], "record_text")
        self.assertIn("section_numeral", clauses[0]["flags"])

    def test_single_letter_numeral_does_not_split_before_it(self):
        # "I." blokeres allerede efter sig af initial-reglen, men splittede før sig.
        self.assertEqual(len(self.segment(self.SINGLE, rules())), 2)
        clauses = self.segment(self.SINGLE, rules_v2())
        self.assertEqual(len(clauses), 1)
        self.assertIn("section_numeral", clauses[0]["flags"])

    def test_regnal_numeral_after_name_keeps_old_behaviour(self):
        # "Christian IV." står efter et navn uden punktum — ikke mellem to sætningstegn.
        for text in ("Alfa Bravo tjente under Christian IV. Gift 1801 m. Golf Hotel.",
                     "Alfa Bravo tjente under Frederik IV.",
                     "Alfa Bravo tjente under Frederik IV. og blev senere Kmh. ved hoffet."):
            with self.subTest(text=text):
                old = self.segment(text, rules())
                new = self.segment(text, rules_v2())
                self.assertEqual([(c["char_from"], c["char_to"]) for c in new],
                                 [(c["char_from"], c["char_to"]) for c in old])
                self.assertFalse(any("section_numeral" in c["flags"] for c in new))

    def test_numeral_month_in_date_keeps_old_behaviour(self):
        # Romersk månedstal i en dato efterfølges af et ciffer, ikke et versal.
        for text in ("Alfa Bravo, f. 4. IV. 1850 i Byen. Gift 1880 m. Golf Hotel.",
                     "Alfa Bravo døde 1901. IV. 1902 flyttede enken."):
            with self.subTest(text=text):
                old = self.segment(text, rules())
                new = self.segment(text, rules_v2())
                self.assertEqual([(c["char_from"], c["char_to"]) for c in new],
                                 [(c["char_from"], c["char_to"]) for c in old])
                self.assertFalse(any("section_numeral" in c["flags"] for c in new))

    def test_initial_letters_outside_numeral_class_are_untouched(self):
        # C og L er initialer i praksis; romertalsklassen i profilen er kun I, V og X.
        text = "Alfa Bravo, f. 1801. C. Deltason var fadder. L. Echo ligeså."
        old = self.segment(text, rules())
        new = self.segment(text, rules_v2())
        self.assertEqual([(c["char_from"], c["char_to"]) for c in new],
                         [(c["char_from"], c["char_to"]) for c in old])
        self.assertFalse(any("section_numeral" in c["flags"] for c in new))

    def test_existing_fixture_cases_are_identical_under_new_rules(self):
        # Den nye regelversion må kun ændre romertalstilfældet — alt andet skal være byte-ens.
        with open(FIXTURE, encoding="utf-8") as fh:
            cases = json.load(fh)["cases"]
        for case in cases:
            with self.subTest(case["key"]):
                old = clause_segment.build_record_ledger(case["key"], "o", case["text"], rules())
                new = clause_segment.build_record_ledger(case["key"], "o", case["text"], rules_v2())
                self.assertEqual([(c["char_from"], c["char_to"], c["flags"]) for c in new["clauses"]],
                                 [(c["char_from"], c["char_to"], c["flags"]) for c in old["clauses"]])

    def test_residual_risk_initial_v_after_sentence_end_is_merged_and_flagged(self):
        # Kendt restrisiko: et initial "V." lige efter et sætningsslut kan ikke skelnes
        # fra et romertal. Motoren vælger den længere klausul OG flager — aldrig tavst.
        text = "Alfa Bravo, f. 1801. V. Deltason var fadder."
        clauses = self.segment(text, rules_v2())
        self.assertEqual(len(clauses), 1)
        self.assertIn("section_numeral", clauses[0]["flags"])


class TestAbbreviationMatch(unittest.TestCase):
    """Review 35, P3: forkortelser med stort forbogstav (`Sr.`, `Pol.`, `Jahrg.`) og
    listeord i anden kasus splittede sætningen tavst.  Målingen 2026-09-27 afviste en
    generel versal-regel (106 af 153 ramte ord står også uden punktum); rettelsen er
    listen + opslag uden hensyn til store/små bogstaver.  Alle tekster er opfundne."""

    def segment(self, text, rules):
        result = clause_segment.build_record_ledger("k", "source-evidence:k", text, rules)
        clause_ledger.validate_ledger(result["ledger"], text)
        return result["clauses"]

    def test_old_profile_is_unchanged(self):
        self.assertNotIn("abbreviation_match", rules())
        self.assertEqual(len(self.segment("Alfa Bravo var Sr. Excellenz des Herrn Charlie.", rules())), 2)

    def test_capitalised_abbreviations_from_the_measurement_do_not_split(self):
        for text in ("Alfa Bravo var Sr. Excellenz des Herrn Charlie.",
                     "Alfa Bravo studerede Pol. Echo i Foxtrot.",
                     "Se Golf Hotel, Jahrg. 10. 1909, s. 113."):
            with self.subTest(text):
                clauses = self.segment(text, rules_v2())
                self.assertEqual(len(clauses), 1)
                self.assertNotIn("unknown_abbreviation", clauses[0]["flags"])

    def test_list_lookup_ignores_case_only_when_the_rule_says_so(self):
        r = dict(rules_v2(), non_terminal_abbreviations=["ca."])
        text = "Alfa Bravo, Ca. Tre Gange gift."
        self.assertEqual(len(self.segment(text, r)), 1)
        exact = {k: v for k, v in r.items() if k != "abbreviation_match"}
        self.assertEqual(len(self.segment(text, exact)), 2)

    def test_case_insensitive_lookup_covers_a_leading_parenthesis(self):
        r = dict(rules_v2(), non_terminal_abbreviations=["ca."])
        self.assertEqual(len(self.segment("Alfa Bravo (Ca. Tre Gange) gift.", r)), 1)

    def test_rule_value_is_validated(self):
        for bad in ("CASE_INSENSITIVE", "", True, None):
            with self.subTest(bad):
                with self.assertRaises(evidence_extract.ExtractionError):
                    evidence_extract.validate_clause_rules(dict(rules_v2(), abbreviation_match=bad))
        evidence_extract.validate_clause_rules(dict(rules_v2(), abbreviation_match="exact"))


if __name__ == "__main__":
    unittest.main()
