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


class KontekstDatoTest(unittest.TestCase):
    """H9: s.å./s.m./s.d. opløses fra den nærmeste foregående dato i narrativet."""

    def bounds(self, text, clause, date_raw):
        event = {"klausul": clause, "date_raw": date_raw}
        enriched, issues, advisory, _ = vh.validate_narrative(source(text), extraction([event]))
        self.assertEqual([], issues)
        got = enriched["haendelser"][0]
        return (got["date_min"], got["date_max"]), got["date_raw"], advisory

    def test_saa_takes_nearest_preceding_year_and_keeps_day(self):
        text = "Kaptajn 1675, deltog s.å. (4. dec.) i slaget ved Lund."
        b, raw, advisory = self.bounds(text, "deltog s.å. (4. dec.) i slaget ved Lund", "s.å. (4. dec.)")
        self.assertEqual(("1675-12-04", "1675-12-04"), b)
        self.assertEqual("s.å. (4. dec.)", raw)  # date_raw forbliver ordret
        self.assertTrue(any(a.startswith("H9") for a in advisory))

    def test_s_a_variant_without_day_gives_whole_year(self):
        text = "1865 Fanejunker ved Dragonreg., s. A. Officersexamen."
        b, _, _ = self.bounds(text, "s. A. Officersexamen", "s. A.")
        self.assertEqual(("1865-01-01", "1865-12-31"), b)

    def test_chained_saa_resolves_through_previous_relative_date(self):
        text = "1469 beseglede han, s.å. (2. maj) i Kiel, s.å. (8. juli) i Lübeck."
        b, _, _ = self.bounds(text, "s.å. (8. juli) i Lübeck", "s.å. (8. juli)")
        self.assertEqual(("1469-07-08", "1469-07-08"), b)

    def test_sm_takes_year_and_month_from_preceding_date(self):
        text = "Udnævnt 13. juli 1469, bestalling 28. s.m. i Kiel."
        b, _, _ = self.bounds(text, "bestalling 28. s.m. i Kiel", "28. s.m.")
        self.assertEqual(("1469-07-28", "1469-07-28"), b)

    def test_sm_after_year_with_parenthesised_day(self):
        text = "1776 (9 Dec.) Deputeret, 15. s.m. Kammerherre."
        b, _, _ = self.bounds(text, "15. s.m. Kammerherre", "15. s.m.")
        self.assertEqual(("1776-12-15", "1776-12-15"), b)

    def test_sd_takes_full_preceding_date(self):
        text = "Gift 1700 (2. maj) i Kiel, s.d. Amtmand."
        b, _, _ = self.bounds(text, "s.d. Amtmand", "s.d.")
        self.assertEqual(("1700-05-02", "1700-05-02"), b)

    def test_new_year_resets_month_so_sm_is_not_guessed(self):
        text = "13. juli 1469 i Kiel; 1470 i Lübeck, 28. s.m. vidne."
        b, _, advisory = self.bounds(text, "28. s.m. vidne", "28. s.m.")
        self.assertEqual((None, None), b)
        self.assertFalse(any(a.startswith("H9") for a in advisory))

    def test_no_preceding_year_stays_undated(self):
        b, _, _ = self.bounds("Han deltog s.å. i slaget.", "deltog s.å. i slaget", "s.å.")
        self.assertEqual((None, None), b)

    def test_parsable_date_is_never_rewritten(self):
        b, _, advisory = self.bounds("1580 rejste han; 1590 blev han lensmand.", "1590 blev han lensmand", "1590")
        self.assertEqual(("1590-01-01", "1590-12-31"), b)
        self.assertFalse(any(a.startswith("H9") for a in advisory))


class ParkerUdateredeTest(unittest.TestCase):
    def test_events_without_any_bound_are_parked_and_narrative_kept(self):
        clean = [{"narrative_id": 1, "haendelser": [
            {"klausul": "a", "date_raw": "1580", "date_min": "1580-01-01", "date_max": "1580-12-31"},
            {"klausul": "b", "date_raw": "før 1565", "date_min": None, "date_max": "1565-12-31"},
            {"klausul": "c", "date_raw": "17 Aug.", "date_min": None, "date_max": None},
        ]}, {"narrative_id": 2, "haendelser": [
            {"klausul": "d", "date_raw": "s.d.", "date_min": None, "date_max": None},
        ]}]
        kept, parked = vh.parker_udaterede(clean)
        self.assertEqual([["a", "b"], []], [[h["klausul"] for h in r["haendelser"]] for r in kept])
        self.assertEqual([1, 2], [r["narrative_id"] for r in kept])  # narrativet bliver i inputtet
        self.assertEqual([(1, "c"), (2, "d")], [(p["narrative_id"], p["haendelse"]["klausul"]) for p in parked])


if __name__ == "__main__":
    unittest.main()
