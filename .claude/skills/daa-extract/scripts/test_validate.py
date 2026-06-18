import os, sys, unittest
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


if __name__ == "__main__":
    unittest.main()
