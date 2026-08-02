import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import clause_ledger
import segment


class TestClauseLedger(unittest.TestCase):
    def test_full_character_accounting_and_nested_observations(self):
        source = "I\nFørste slægtled\n1. Anne\n"
        clauses = [
            {"char_from": 0, "char_to": 2, "classification": "structural_header",
             "observation_ids": ["obs-line"], "record_key": None,
             "occurrence_id": "occ-1"},
            {"char_from": 2, "char_to": 19, "classification": "structural_header",
             "observation_ids": ["obs-generation"], "record_key": None,
             "occurrence_id": "occ-1"},
            {"char_from": 19, "char_to": len(source), "classification": "record_text",
             "observation_ids": [], "record_key": "record-a", "occurrence_id": "occ-1"},
        ]
        ledger = clause_ledger.build_ledger(source, clauses)
        clause_ledger.validate_ledger(ledger)
        self.assertEqual(ledger[0]["span"], {"char_from": 0, "char_to": 2})
        self.assertEqual(ledger[2]["observation_ids"], [])

    def test_rejects_unclassified_non_whitespace_and_overlapping_clauses(self):
        with self.assertRaises(clause_ledger.LedgerError):
            clause_ledger.build_ledger("abc", [{
                "char_from": 0, "char_to": 2, "classification": "record_text",
                "observation_ids": [], "record_key": None, "occurrence_id": "occ-1",
            }])
        with self.assertRaises(clause_ledger.LedgerError):
            clause_ledger.build_ledger("abc", [
                {"char_from": 0, "char_to": 2, "classification": "record_text",
                 "observation_ids": [], "record_key": None, "occurrence_id": "occ-1"},
                {"char_from": 1, "char_to": 3, "classification": "record_text",
                 "observation_ids": [], "record_key": None, "occurrence_id": "occ-1"},
            ])

    def test_record_key_is_supplied_not_derived_from_printed_line_number(self):
        source = "1. Anne\n99. Anne\n"
        ledger = clause_ledger.build_ledger(source, [
            {"char_from": 0, "char_to": 8, "classification": "record_text",
             "observation_ids": [], "record_key": "record-opaque", "occurrence_id": "occ-a"},
            {"char_from": 8, "char_to": len(source), "classification": "record_text",
             "observation_ids": [], "record_key": "record-opaque", "occurrence_id": "occ-b"},
        ])
        self.assertEqual({row["record_key"] for row in ledger}, {"record-opaque"})

    def test_generation_header_creates_placement_with_header_evidence(self):
        placement = clause_ledger.placement_from_header(
            record_key="record-a", header_observation_id="obs-generation",
            generation_label_raw="Første", generation_local=1,
            generation_global=4, kuld_label="II",
        )
        self.assertEqual(placement["header_observation_id"], "obs-generation")
        self.assertEqual(placement["generation_label_raw"], "Første")
        self.assertEqual(placement["generation_local"], 1)
        self.assertEqual(placement["generation_global"], 4)
        self.assertEqual(placement["kuld_label"], "II")

    def test_spouse_mention_does_not_inherit_principal_generation(self):
        mentions = clause_ledger.persona_placements_from_record(
            record_key="record-a", principal_persona_id="persona-anne",
            principal_generation=4, mentioned_persona_ids=["persona-spouse"],
        )
        self.assertEqual(mentions["persona-anne"], 4)
        self.assertIsNone(mentions["persona-spouse"])

    def test_uncle_and_niece_keep_different_printed_generations(self):
        placements = clause_ledger.persona_placements_from_records([
            {"record_key": "record-uncle", "principal_persona_id": "uncle", "generation": 4},
            {"record_key": "record-niece", "principal_persona_id": "niece", "generation": 6},
        ])
        self.assertEqual(placements, {"uncle": 4, "niece": 6})

    def test_spouse_edges_are_excluded_from_computed_generation(self):
        generations = clause_ledger.compute_blood_generations(
            founders=["ancestor"],
            parent_edges=[("ancestor", "child")],
            spouse_edges=[("child", "spouse")],
        )
        self.assertEqual(generations, {"ancestor": 1, "child": 2})
        self.assertNotIn("spouse", generations)


class TestSegmentEvidenceSidecar(unittest.TestCase):
    RAW = "\n".join([
        "### PAGE 1 ###", "I", "DEN HOLSTENSKE LINJE", "Første slægtled",
        "        1.       Anne, til Teststed.",
    ]) + "\n"

    def test_default_output_is_unchanged_and_sidecar_is_explicit(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as raw:
            raw.write(self.RAW)
            raw_path = raw.name
        ledger_path = raw_path + ".ledger.json"
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                default_posts = segment.main(raw_path)
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                emitted_posts = segment.main(raw_path, emit_evidence_ledger=ledger_path)
            self.assertEqual(emitted_posts, default_posts)
            ledger = json.load(open(ledger_path, encoding="utf-8"))
            clause_ledger.validate_ledger(ledger["clauses"])
            self.assertEqual(ledger["record_placements"], [])
            generation = next(obs for obs in ledger["observations"]
                              if obs["kind"] == "printed_generation_header")
            self.assertEqual(generation["generation_label_raw"], "Første")
            self.assertEqual(generation["generation_local"], 1)
            self.assertTrue(any(row["classification"] == "structural_header" for row in ledger["clauses"]))
            self.assertTrue(any(row["classification"] == "record_text" for row in ledger["clauses"]))
        finally:
            for path in (raw_path, ledger_path):
                if os.path.exists(path):
                    os.unlink(path)

    def test_1939_default_profile_remains_isolated(self):
        raw = "                    III.\n3. J o h a n fortsætter.\n"
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as fh:
            fh.write(raw)
            path = fh.name
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                posts = segment.main(path, udgave="1939")
            self.assertEqual(posts[0]["raw_text"], "J o h a n fortsætter.")
        finally:
            os.unlink(path)
