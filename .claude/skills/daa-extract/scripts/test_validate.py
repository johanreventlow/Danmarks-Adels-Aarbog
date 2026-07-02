import os, sys, json, tempfile, unittest
sys.path.insert(0, os.path.dirname(__file__))
import validate


class TestDeriveBoern(unittest.TestCase):
    def test_antal_og_range(self):
        raw = "Gottschalk, til Glasau. 3 børn: Tiende slægtled, II, nr. 31-35."
        self.assertEqual(validate.derive_boern(raw),
                         {"antal": 3, "slaegtled": "Tiende slægtled", "linje": "II", "nr_range": [31, 35]})

    def test_enkelt_barn_soen(self):
        raw = "N.N., til X. Søn: nr. 199."
        got = validate.derive_boern(raw)
        self.assertEqual(got["nr_range"], [199, 199])
        self.assertEqual(got["antal"], 1)

    def test_ingen_boerneklausul(self):
        self.assertIsNone(validate.derive_boern("Levede ugift, deres børn boede i udlandet."))

    def test_bar_boern_uden_antal(self):
        raw = "børn: nr. 12-14."
        got = validate.derive_boern(raw)
        self.assertEqual(got["nr_range"], [12, 14])
        self.assertEqual(got["antal"], 3)


class TestDeriveAegteskaber(unittest.TestCase):
    def test_enkelt_aegteskab(self):
        raw = "Frederik, til Brahetrolleborg. g. 26. juli 1975 m. Margrethe Holstein."
        got = validate.derive_aegteskaber(raw)
        self.assertEqual(len(got), 1)
        self.assertEqual(got[0]["ordinal"], 1)
        self.assertEqual(got[0]["partner_navn"], "Margrethe Holstein")
        self.assertFalse(got[0]["skilt"])

    def test_to_aegteskaber_ordinaler(self):
        raw = ("Christian, til Christianssæde. Gift 1° 1698 med Anna Sophie Reedtz, "
               "2° 1712 med Birgitte Restorff, skilt.")
        got = validate.derive_aegteskaber(raw)
        self.assertEqual([a["ordinal"] for a in got], [1, 2])
        self.assertEqual(got[0]["partner_navn"], "Anna Sophie Reedtz")
        self.assertTrue(got[1]["skilt"])

    def test_ingen_aegteskab(self):
        self.assertEqual(validate.derive_aegteskaber("Døde ugift 1701."), [])

    def test_dato_raw_findes_i_tekst(self):
        raw = "N.N. g. 1750 m. Sofie."
        got = validate.derive_aegteskaber(raw)
        self.assertIn(got[0]["dato_raw"].strip(), raw)


class TestExpectedSignals(unittest.TestCase):
    def test_venter_aegteskab_men_mangler(self):
        raw = "N.N. g. 1750 m. Sofie. † 1799."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_aegteskab"])
        self.assertTrue(sig["venter_doed"])

    def test_ingen_signaler(self):
        raw = "N.N. levede ugift uden kendte børn."
        sig = validate.expected_signals(raw)
        self.assertFalse(sig["venter_aegteskab"])
        self.assertFalse(sig["venter_boern"])
        self.assertFalse(sig["venter_doed"])

    def test_venter_boern(self):
        raw = "N.N. 3 børn: Tiende slægtled, II, nr. 31-35."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_boern"])
        self.assertFalse(sig["venter_aegteskab"])

    def test_doed_dagger_symbol(self):
        raw = "N.N. † 1801."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_doed"])
        self.assertFalse(sig["venter_aegteskab"])
        self.assertFalse(sig["venter_boern"])

    # Pilot 2026-06-18: parenteser bærer tredjeparts-data (slægtninge, gift-ind,
    # kilde-refs). Et tredjeparts † eller (gift…) i parentes må IKKE flagge posten.
    def test_tredjeparts_doed_i_parentes_flagger_ikke(self):
        raw = "Lüder til X. Beseglede 1469. Gift med Mette (F.: Hans B., † før 1496)."
        sig = validate.expected_signals(raw)
        self.assertFalse(sig["venter_doed"])     # † er kun i parentes (svigerfar)

    def test_egen_doed_flagger_stadig(self):
        raw = "Lüder † 1500. Gift med Mette (F.: Hans B., † før 1496)."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_doed"])      # postens egen † uden for parentes

    def test_tredjeparts_aegteskab_i_parentes_flagger_ikke(self):
        raw = "Lüder, søn af NN (gift 2° med Erik Schrandi)."
        sig = validate.expected_signals(raw)
        self.assertFalse(sig["venter_aegteskab"])  # ægteskab kun i parentes (tredjepart)

    def test_egen_aegteskab_uden_for_parentes_flagger(self):
        raw = "Lüder. Gift med Mette Breide (gift 2° med Erik Schrandi)."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_aegteskab"])   # postens eget ægteskab uden for parentes

    def test_nestede_parenteser_strippes(self):
        raw = "Lüder til X (F.: Hans (af Kaden) † 1490)."
        sig = validate.expected_signals(raw)
        self.assertFalse(sig["venter_doed"])     # nested parentes-† tæller ikke

    def test_r8_advisory_i_validate(self):
        """validate() tilføjer R8-advisories (non-blocking) ved mismatch."""
        rec = {
            "linje": "I",
            "nr": 1,
            "nr_label": "1",
            "navn": "N.N.",
            "aegteskaber": [],
            "boern": None,
            "facts": [],
        }
        src = {"raw_text": "N.N. g. 1750 m. Sofie. † 1799.", "linje": "I", "nr": 1, "nr_label": "1"}
        issues, advisory = validate.validate(rec, src, {"I": {1}})
        self.assertEqual(issues, [], "R8 må ikke blokere (skal være advisory, ikke issue)")
        r8_lines = [a for a in advisory if a.startswith("R8:")]
        self.assertGreaterEqual(len(r8_lines), 2, f"Forventet mindst 2 R8-advisories, fik: {advisory}")
        aegt_flags = [a for a in r8_lines if "ægteskab" in a]
        doed_flags = [a for a in r8_lines if "død" in a]
        self.assertTrue(aegt_flags, "Mangler R8-advisory for ægteskab")
        self.assertTrue(doed_flags, "Mangler R8-advisory for død")


class TestProvenansGate(unittest.TestCase):
    def _run(self, rec, raw):
        src = {"raw_text": raw}
        issues, _ = validate.validate(rec, src, {})
        return issues

    def test_span_findes(self):
        rec = {"linje": "I", "nr": 1, "facts": [{"faktatype": "død", "kilde_span": "† 1300"}]}
        self.assertEqual([i for i in self._run(rec, "N.N. † 1300, til X.") if i.startswith("R7")], [])

    def test_span_hallucineret(self):
        rec = {"linje": "I", "nr": 1, "facts": [{"faktatype": "død", "kilde_span": "† 1399"}]}
        bad = [i for i in self._run(rec, "N.N. † 1300, til X.") if i.startswith("R7")]
        self.assertEqual(len(bad), 1)


class TestEscalationEntry(unittest.TestCase):
    def test_blokerende_eskaleres(self):
        rec = {"linje": "I", "nr": 5, "nr_label": "5"}
        e = validate.escalation_entry(rec, ["R1: årstal ..."], [])
        self.assertIsNotNone(e)
        self.assertEqual(e["nr_label"], "5")
        self.assertEqual(e["grunde"], ["R1: årstal ..."])

    def test_r8_miss_eskaleres(self):
        rec = {"linje": "I", "nr": 5, "nr_label": "5"}
        e = validate.escalation_entry(rec, [], ["R8: prosa nævner død, men intet død-fakta"])
        self.assertIsNotNone(e)
        self.assertEqual(e["grunde"], ["R8: prosa nævner død, men intet død-fakta"])

    def test_ren_post_eskaleres_ikke(self):
        self.assertIsNone(validate.escalation_entry({"linje": "I", "nr": 5}, [], []))

    def test_v9_vocab_eskalerer_ikke(self):
        e = validate.escalation_entry({"linje": "I", "nr": 5}, [], ["V9: ukendt faktatype"])
        self.assertIsNone(e)


class TestNormalizeRecord(unittest.TestCase):
    """C1: normalize_record() deler boern-logikken med validate.main()."""

    def test_udleder_boern_fra_prosa(self):
        rec = {"linje": "I", "nr": 1, "boern": None}
        src = {"raw_text": "N.N. 3 børn: Tiende slægtled, II, nr. 31-35."}
        validate.normalize_record(rec, src)
        self.assertIsNotNone(rec["boern"])
        self.assertEqual(rec["boern"]["nr_range"], [31, 35])
        self.assertEqual(rec["boern"]["antal"], 3)

    def test_nulstiller_hallucineret_boern(self):
        rec = {"linje": "I", "nr": 1, "boern": {"antal": 2, "nr_range": [10, 11]}}
        src = {"raw_text": "N.N. Levede ugift uden børn."}
        validate.normalize_record(rec, src)
        self.assertIsNone(rec["boern"])

    def test_ingen_src_bevaerer_boern(self):
        boern = {"antal": 1, "nr_range": [5, 5]}
        rec = {"linje": "I", "nr": 1, "boern": boern}
        validate.normalize_record(rec, None)
        self.assertEqual(rec["boern"], boern)


class TestValidateMainReviewNrLabel(unittest.TestCase):
    """C3: validate.main() skriver nr_label ind i review-recorden."""

    def test_review_record_har_nr_label(self):
        # Opsæt temp-mappe med én udtrukket post der fejler R1 (hallucination)
        with tempfile.TemporaryDirectory() as tmpdir:
            posts = [{"linje": "I", "nr": 15, "nr_label": "15a",
                      "raw_text": "Peter til X. † 1700."}]
            posts_path = os.path.join(tmpdir, "posts.json")
            json.dump(posts, open(posts_path, 'w', encoding='utf-8'), ensure_ascii=False)

            # Extracted post med hallucineret årstal → R1-brud
            rec = {"linje": "I", "nr": 15, "nr_label": "15a", "navn": "Peter",
                   "facts": [{"faktatype": "død", "date_raw": "† 1999"}],
                   "aegteskaber": [], "boern": None}
            ext_dir = os.path.join(tmpdir, "extracted")
            os.makedirs(ext_dir)
            json.dump(rec, open(os.path.join(ext_dir, "015a.json"), 'w', encoding='utf-8'),
                      ensure_ascii=False)

            clean_path = os.path.join(tmpdir, "clean.json")
            review_path = os.path.join(tmpdir, "review.json")

            sys.argv = ["validate.py", posts_path, ext_dir,
                        "--clean", clean_path, "--review", review_path]
            validate.main()

            review = json.load(open(review_path, encoding='utf-8'))
            self.assertEqual(len(review), 1)
            self.assertEqual(review[0].get("nr_label"), "15a",
                             "review-record mangler nr_label — C3-fix ikke anvendt")


class TestDateBounds(unittest.TestCase):
    def test_aar_kun(self):
        self.assertEqual(validate.derive_date_bounds("1698"), ("1698-01-01", "1698-12-31"))

    def test_fuld_dato(self):
        self.assertEqual(validate.derive_date_bounds("26. juli 1975"), ("1975-07-26", "1975-07-26"))

    def test_ca(self):
        lo, hi = validate.derive_date_bounds("ca. 1500")
        self.assertTrue(lo.startswith("1500") and hi.startswith("1500"))

    def test_uparsebar(self):
        self.assertEqual(validate.derive_date_bounds("ukendt"), (None, None))

    def test_to_aars_span_bevares(self):
        self.assertEqual(validate.derive_date_bounds("1257-1272"), ("1257-01-01", "1272-12-31"))

    def test_flere_end_to_aar_uparsebart(self):
        self.assertEqual(validate.derive_date_bounds("1500 1600 1700"), (None, None))


class TestR1DateAttribution(unittest.TestCase):
    """Hærdet R1: date_min's år skal faktisk stå i date_raw (fanger fejl-
    attribuering, fx et vielsesår udtrukket som dødsår)."""

    def test_mis_attribueret_dato_flager(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "1698", "date_min": "1750-01-01"}]}
        src = {"raw_text": "N.N. gift 1698, død 1750."}
        issues, _ = validate.validate(rec, src, {})
        self.assertTrue(any(i.startswith("R1") and "fejl-attribueret" in i for i in issues))

    def test_korrekt_attribueret_dato_flager_ikke(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "1750", "date_min": "1750-01-01"}]}
        src = {"raw_text": "N.N. gift 1698, død 1750."}
        issues, _ = validate.validate(rec, src, {})
        self.assertFalse(any("fejl-attribueret" in i for i in issues))


class TestNormalizeRecordDateOverride(unittest.TestCase):
    """normalize_record overskriver date_min/date_max deterministisk fra date_raw."""

    def test_overskriver_llm_dato(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "1750", "date_min": "1999-01-01", "date_max": "1999-12-31"}]}
        src = {"raw_text": "N.N. død 1750."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0]["date_min"], "1750-01-01")
        self.assertEqual(rec["facts"][0]["date_max"], "1750-12-31")

    def test_span_bevares_ved_normalize(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "floruit", "date_raw": "1257-1272"}]}
        src = {"raw_text": "N.N. floruit 1257-1272."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0]["date_min"], "1257-01-01")
        self.assertEqual(rec["facts"][0]["date_max"], "1272-12-31")


class TestKontekstMerge(unittest.TestCase):
    def test_merge_kuld_og_kontekst(self):
        rec = {"linje": "I", "nr": 66, "nr_label": "66", "navn": "X"}
        src = {"linje": "I", "nr": 66, "nr_label": "66",
               "raw_text": "X, til Y. 1700.", "kuld": "I",
               "aegteskab_kontekst": "af første ægteskab med Anna von Ahlefeldt"}
        out = validate.merge_kontekst(dict(rec), src)
        self.assertEqual(out["kuld"], "I")
        self.assertEqual(out["aegteskab_kontekst"], "af første ægteskab med Anna von Ahlefeldt")

    def test_merge_haandterer_manglende_src(self):
        out = validate.merge_kontekst({"linje":"I","nr":1,"nr_label":"1","navn":"X"}, None)
        self.assertIsNone(out["kuld"])


if __name__ == "__main__":
    unittest.main()
