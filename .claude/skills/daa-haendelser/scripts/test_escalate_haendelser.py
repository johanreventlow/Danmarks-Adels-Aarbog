import unittest

import escalate_haendelser as eh


SOURCE = {"narrative_id": 1, "tekst": "I 1580 blev han lensmand. I 1590 rejste han."}


def extraction(events):
    return {"narrative_id": 1, "haendelser": events}


class EscalateHaendelserTest(unittest.TestCase):
    def test_promotes_clean_improvement_with_snapshot(self):
        snapshot = extraction([])
        reextracted = extraction([
            {"klausul": "I 1580 blev han lensmand.", "date_raw": "1580", "kategori": "embede"}
        ])
        promote, enriched, issues, _ = eh.decide(reextracted, snapshot, SOURCE)
        self.assertTrue(promote)
        self.assertEqual([], issues)
        self.assertEqual("1580-01-01", enriched["haendelser"][0]["date_min"])

    def test_rejects_missing_snapshot_fail_closed(self):
        reextracted = extraction([{"klausul": "I 1580 blev han lensmand."}])
        promote, _, issues, _ = eh.decide(reextracted, None, SOURCE)
        self.assertFalse(promote)
        self.assertTrue(any(x.startswith("E1") for x in issues))

    def test_rejects_blocking_reextraction(self):
        reextracted = extraction([{"klausul": "I 1700 blev han lensmand."}])
        promote, _, issues, _ = eh.decide(reextracted, extraction([]), SOURCE)
        self.assertFalse(promote)
        self.assertTrue(any(x.startswith("H1") for x in issues))

    def test_merge_replaces_clean_and_removes_review(self):
        reextracted = extraction([{"klausul": "I 1590 rejste han.", "date_raw": "1590"}])
        clean, review, promoted, decisions = eh.merge_escalated(
            [SOURCE], [{"narrative_id": 1, "grunde": ["H8"]}], {1: reextracted},
            {1: extraction([])}, [extraction([])],
            [{"narrative_id": 1, "brud": ["gammel"]}],
        )
        self.assertEqual([1], promoted)
        self.assertEqual([], review)
        self.assertEqual("I 1590 rejste han.", clean[0]["haendelser"][0]["klausul"])
        self.assertEqual("promoveret", decisions[0]["status"])

    def test_failed_merge_is_removed_from_clean_and_diagnosed(self):
        bad = extraction([{"klausul": "opdigtet"}])
        clean, review, promoted, _ = eh.merge_escalated(
            [SOURCE], [{"narrative_id": 1}], {1: bad}, {1: extraction([])},
            [extraction([])], [],
        )
        self.assertEqual([], clean)
        self.assertEqual([], promoted)
        self.assertTrue(review[0]["brud"])


if __name__ == "__main__":
    unittest.main()
