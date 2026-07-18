import unittest

import validate_haendelser as vh


def source(text="I 1580 blev han lensmand.", narrative_id=1):
    return {"narrative_id": narrative_id, "tekst": text}


def extraction(events, narrative_id=1, **extra):
    return {"narrative_id": narrative_id, "haendelser": events, **extra}


class ValidateHaendelserTest(unittest.TestCase):
    def test_h1_rejects_paraphrase_and_typography_change(self):
        for clause in ["I 1580 var han lensmand.", "I 1580 blev han Lensmand."]:
            _, issues, _, _ = vh.validate_narrative(source(), extraction([{"klausul": clause}]))
            self.assertTrue(any(x.startswith("H1") for x in issues))

    def test_h2_rejects_year_not_in_clause(self):
        event = {"klausul": "Han blev lensmand.", "date_raw": "1580"}
        _, issues, _, _ = vh.validate_narrative(source("Han blev lensmand. I 1580 rejste han."), extraction([event]))
        self.assertTrue(any(x.startswith("H2") for x in issues))

    def test_h3_rejects_unknown_fields(self):
        event = {"klausul": "I 1580 blev han lensmand.", "opfundet": True}
        _, issues, _, _ = vh.validate_narrative(source(), extraction([event], andet=True))
        self.assertGreaterEqual(sum(x.startswith("H3") for x in issues), 2)

    def test_h4_overwrites_bounds_with_shared_parser(self):
        event = {
            "klausul": "ca. 1580 blev han lensmand.", "date_raw": "ca. 1580",
            "date_min": "1900-01-01", "date_max": "1900-12-31", "date_qualifier": "exact",
        }
        enriched, issues, _, _ = vh.validate_narrative(source(event["klausul"]), extraction([event]))
        self.assertEqual([], issues)
        got = enriched["haendelser"][0]
        self.assertEqual(("1580-01-01", "1580-12-31", "about"),
                         (got["date_min"], got["date_max"], got["date_qualifier"]))

    def test_h5_indexes_repeated_occurrences(self):
        clause = "I 1580 rejste han."
        text = f"{clause} Senere: {clause}"
        enriched, issues, _, _ = vh.validate_narrative(
            source(text), extraction([{"klausul": clause}, {"klausul": clause}])
        )
        self.assertEqual([], issues)
        spans = [e["span_start"] for e in enriched["haendelser"]]
        self.assertEqual([0, text.rfind(clause)], spans)

    def test_h6_keys_are_deterministic_normalized_and_suffixed(self):
        a = "  I 1580\nREJSTE han.  "
        b = "i 1580 rejste HAN."
        self.assertEqual(vh.normaliser_klausul(a), vh.normaliser_klausul(b))
        self.assertEqual(160, len(vh.normaliser_klausul("X" * 200)))
        clause = "I 1580 rejste han."
        text = f"{clause} {clause}"
        enriched, issues, _, _ = vh.validate_narrative(
            source(text), extraction([{"klausul": clause}, {"klausul": clause}])
        )
        self.assertEqual([], issues)
        keys = [e["noegle"] for e in enriched["haendelser"]]
        self.assertEqual(["i 1580 rejste han.", "i 1580 rejste han.#2"], keys)

    def test_h7_unknown_category_becomes_andet(self):
        event = {"klausul": "I 1580 blev han lensmand.", "kategori": "magi"}
        enriched, issues, advisory, _ = vh.validate_narrative(source(), extraction([event]))
        self.assertEqual([], issues)
        self.assertTrue(any(x.startswith("H7") for x in advisory))
        self.assertEqual("andet", enriched["haendelser"][0]["kategori"])

    def test_h8_escalates_year_rich_empty_extraction(self):
        enriched, issues, advisory, escalation = vh.validate_narrative(
            source("Født 1500, nævnt 1520 og død 1540."), extraction([])
        )
        self.assertEqual([], issues)
        self.assertEqual([], enriched["haendelser"])
        self.assertTrue(any(x.startswith("H8") for x in advisory))
        self.assertTrue(any(x.startswith("H8") for x in escalation))

    def test_one_blocker_moves_whole_narrative_to_review(self):
        good = {"klausul": "I 1580 blev han lensmand."}
        bad = {"klausul": "I 1590 rejste han."}
        clean, review, escalation, advisories = vh.validate_all([source()], {1: extraction([good, bad])})
        self.assertEqual([], clean)
        self.assertEqual(1, len(review))
        self.assertEqual(1, len(escalation))
        self.assertEqual([], advisories)

    def test_h7_advisory_survives_batch_validation(self):
        event = {"klausul": "I 1580 blev han lensmand.", "kategori": "magi"}
        clean, review, escalation, advisories = vh.validate_all(
            [source()], {1: extraction([event])}
        )
        self.assertEqual(1, len(clean))
        self.assertEqual([], review)
        self.assertEqual([], escalation)
        self.assertTrue(advisories[0]["advisory"][0].startswith("H7"))


if __name__ == "__main__":
    unittest.main()
